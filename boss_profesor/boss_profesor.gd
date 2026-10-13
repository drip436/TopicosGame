extends CharacterBody3D
## "Catedrático de Hierro": primer jefe.
## Profesor con armadura pesada, casco cerrado con birrete y maza con cadena.
##   Fase 1: ataques con la maza (golpe vertical, barrido giratorio, lanzamiento de cadena, salto).
##   Fase 2 (al 50 % de vida): invoca la tormenta, la maza se carga de electricidad,
##            sus golpes sueltan ondas eléctricas y hace caer rayos sobre la arena.
## El modelo es procedural (primitivas articuladas); no necesita archivos .glb.
## Busca su objetivo en el grupo "player"; el objetivo debe tener take_damage(cantidad, desde).

signal health_changed(current: float, maximum: float)
signal damaged(amount: float)
signal intro_landed
signal battle_started
signal phase_changed(phase: int)
signal defeated

const FX := preload("boss_fx.gd")
const STRIKE := preload("lightning_strike.gd")

@export var boss_name: String = "Catedrático de Hierro, Heraldo de la Tormenta"
@export var max_health: float = 1400.0
@export_range(0.1, 0.9) var phase2_threshold: float = 0.5
@export var move_speed: float = 3.1
@export var damage_multiplier: float = 1.0
@export var model_scale: float = 1.5

enum State { DORMANT, INTRO, FIGHT, BUSY, TRANSITION, DEAD }

var state: int = State.DORMANT
var phase := 1
var health := 0.0
var target: Node3D = null
var weather: Node = null
var fx_parent: Node = null

# --- modelo
var model: Node3D
var pelvis: Node3D
var joints := {}
var tip: Marker3D
var cape: Node3D
var m_steel: StandardMaterial3D
var m_eye: StandardMaterial3D
var m_chain: StandardMaterial3D
var m_ball: StandardMaterial3D
var eye_light: OmniLight3D

# --- poses
var poses := {}
var _pose_from := {}
var _pose_to := {}
var _pose_cur := {}
var _pose_t := 1.0
var _pose_dur := 0.3
var _walk_phase := 0.0
var _walk_amt := 0.0
var _anim_t := 0.0

# --- maza con cadena
const BALL_R := 0.42
const CHAIN_REST := 2.4
var ball: Node3D
var links: Array[MeshInstance3D] = []
var ball_pos := Vector3.ZERO
var ball_vel := Vector3.ZERO
var ball_mode := "hang"     # hang | local | world | proj
var ball_local := Vector3.ZERO
var ball_world := Vector3.ZERO
var ball_k := 12.0
var ball_speed := 30.0
var chain_len := CHAIN_REST
var electrified := false
var ball_light: OmniLight3D
var ball_sparks: GPUParticles3D
var ball_arcs: MeshInstance3D
var _arc_t := 0.0

# --- control
var _rng := RandomNumberGenerator.new()
var _attack_id := 0
var _cooldown := 1.0
var _tracking := 1.0
var _spin_left := 0.0
var _spin_rate := 0.0
var _lunge := Vector3.ZERO
var _kinematic := false
var _jump_t := 99.0
var _jump_T := 1.0
var _jump_from := Vector3.ZERO
var _jump_to := Vector3.ZERO
var _jump_h := 5.0
var _hit_flash := 0.0
var _storm_cd := 6.0
var _ambient_cd := 5.0
var _last_attacks: Array[String] = []
var _hit_this_attack := false
var _waves: Array = []


func _ready() -> void:
	_rng.randomize()
	add_to_group("boss")
	add_to_group("enemy")
	health = max_health
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.95
	cap.height = 3.2
	cs.shape = cap
	cs.position = Vector3(0, 1.6, 0)
	add_child(cs)
	_build_model()
	_build_flail()
	_define_poses()
	_pose_cur = poses["dormant"].duplicate()
	_pose_to = _pose_cur.duplicate()
	_pose_from = _pose_cur.duplicate()
	ball_pos = global_position + Vector3(0.5, BALL_R, -1.0)
	_set_eyes(Color(1.0, 0.45, 0.12), 0.6)


# =====================================================================
#  API pública
# =====================================================================

## Coloca al jefe (dormido) sobre la azotea, mirando hacia `look_point`.
func place_dormant(pos: Vector3, look_point: Vector3) -> void:
	global_position = pos
	_face_instant(look_point)
	ball_pos = global_position + global_basis * Vector3(0.9, 0.6, -0.6)
	ball_vel = Vector3.ZERO
	state = State.DORMANT


## Secuencia de entrada: rugido en la azotea, salto y caída en la arena.
func begin_intro(land_pos: Vector3) -> void:
	if state != State.DORMANT:
		return
	state = State.INTRO
	_kinematic = true
	_face_instant(land_pos)
	_pose("roar", 0.8)
	ball_mode = "local"
	ball_local = Vector3(0.5, 5.6, 0.2)
	ball_k = 4.0
	_set_eyes(Color(1.0, 0.45, 0.12), 4.0)
	await _w(1.1)
	if weather and weather.has_method("flash"):
		weather.flash(Vector2(0, -1))
	_shake_target(0.25)
	await _w(0.9)
	ball_mode = "hang"
	_pose("crouch", 0.35)
	await _w(0.4)
	_pose("air", 0.25)
	_start_jump(land_pos, 1.8, 7.0)
	await _w(1.8)
	_pose("land", 0.07)
	_impact(land_pos, 5.0, 20.0, 1.0)
	FX.burst(fx_parent, land_pos + Vector3(0, 0.3, 0), false, 60, 2.2)
	intro_landed.emit()
	await _w(1.0)
	_pose("roar", 0.5)
	ball_mode = "local"
	ball_local = Vector3(0.5, 5.0, 0.4)
	ball_k = 5.0
	await _w(0.6)
	FX.shockwave(fx_parent, global_position, 9.0, Color(0.8, 0.8, 0.8), 0.6)
	_shake_target(0.35)
	await _w(1.0)
	ball_mode = "hang"
	_pose("idle", 0.6)
	_kinematic = false
	await _w(0.6)
	state = State.FIGHT
	_cooldown = 0.6
	battle_started.emit()


func take_damage(amount: float, _from: Variant = null) -> void:
	if state in [State.DORMANT, State.INTRO, State.TRANSITION, State.DEAD]:
		return
	health -= amount
	_hit_flash = 1.0
	damaged.emit(amount)
	if phase == 1 and health <= max_health * phase2_threshold:
		health = max_health * phase2_threshold
		health_changed.emit(health, max_health)
		_start_phase2()
		return
	if health <= 0.0:
		health = 0.0
		health_changed.emit(health, max_health)
		_die()
		return
	health_changed.emit(health, max_health)


## Útil para pruebas: salta directo a la fase 2.
func debug_force_phase2() -> void:
	if phase == 1 and state != State.DEAD:
		health = max_health * phase2_threshold
		health_changed.emit(health, max_health)
		_start_phase2()


# =====================================================================
#  Bucle principal
# =====================================================================

func _physics_process(delta: float) -> void:
	_anim_t += delta
	if _kinematic:
		_update_jump(delta)
		velocity = Vector3.ZERO
	else:
		_update_movement(delta)
	_update_pose(delta)
	_update_flail(delta)
	_update_effects(delta)
	_update_waves(delta)
	if state == State.FIGHT:
		_think(delta)
	if phase == 2 and state in [State.FIGHT, State.BUSY]:
		_ambient_cd -= delta
		_storm_cd -= delta
		if _ambient_cd <= 0.0 and _valid_target():
			_ambient_cd = _rng.randf_range(3.5, 6.5)
			var p := target.global_position + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
			_spawn_strike(_clamp_arena(p), 1.5, 2.4, 22.0)


func _update_movement(delta: float) -> void:
	var desired := Vector3.ZERO
	if state == State.FIGHT and _valid_target():
		var to := target.global_position - global_position
		to.y = 0.0
		var d := to.length()
		_turn_toward(target.global_position, delta, 1.0)
		if d > 4.2:
			desired = to.normalized() * move_speed * (1.18 if phase == 2 else 1.0)
	elif state == State.BUSY and _valid_target():
		_turn_toward(target.global_position, delta, _tracking)
	if _spin_left > 0.0:
		_spin_left -= delta
		rotation.y += _spin_rate * delta
		if _valid_target():
			var to2 := target.global_position - global_position
			to2.y = 0.0
			if to2.length() > 2.0:
				desired = to2.normalized() * 2.6
	desired += _lunge
	_lunge = _lunge.move_toward(Vector3.ZERO, 14.0 * delta)
	velocity.x = desired.x
	velocity.z = desired.z
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	_walk_amt = move_toward(_walk_amt, clampf(flat_speed / move_speed, 0.0, 1.0) if _spin_left <= 0.0 else 0.0, delta * 4.0)
	_walk_phase += delta * flat_speed * 1.6


func _turn_toward(p: Vector3, delta: float, factor: float) -> void:
	if factor <= 0.0:
		return
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	var want := atan2(-d.x, -d.z)
	var rate := deg_to_rad(110.0 if phase == 1 else 150.0) * factor
	rotation.y = rotate_toward(rotation.y, want, rate * delta)


func _face_instant(p: Vector3) -> void:
	var d := p - global_position
	rotation.y = atan2(-d.x, -d.z)


func _start_jump(to: Vector3, time: float, height: float) -> void:
	_kinematic = true
	_jump_from = global_position
	_jump_to = to
	_jump_T = time
	_jump_t = 0.0
	_jump_h = height


func _update_jump(delta: float) -> void:
	if _jump_t >= _jump_T:
		return
	_jump_t = minf(_jump_t + delta, _jump_T)
	var k := _jump_t / _jump_T
	var base := _jump_from.lerp(_jump_to, k)
	var y := lerpf(_jump_from.y, _jump_to.y, k) + _jump_h * 4.0 * k * (1.0 - k)
	global_position = Vector3(base.x, y, base.z)
	_turn_toward(_jump_to, delta, 0.6)


# =====================================================================
#  IA
# =====================================================================

func _think(delta: float) -> void:
	if not _valid_target():
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var facing := -global_basis.z
	var aligned := facing.dot(to.normalized()) > 0.6
	var pick := ""
	if phase == 2 and _storm_cd <= 0.0 and _rng.randf() < 0.55:
		pick = "storm"
	elif d < 5.8:
		if not aligned and d < 3.5:
			pick = "sweep"
		else:
			pick = _weighted({"slam": 50, "sweep": 38, "leap": 4})
	elif d < 13.0:
		pick = _weighted({"throw": 42, "leap": 33, "": 25})
	else:
		pick = _weighted({"leap": 55, "throw": 30, "": 15})
	if pick != "" and _last_attacks.size() >= 2 and _last_attacks[-1] == pick and _last_attacks[-2] == pick:
		pick = "sweep" if pick != "sweep" else "slam"
	if pick == "":
		_cooldown = 0.5
		return
	_last_attacks.append(pick)
	if _last_attacks.size() > 4:
		_last_attacks.pop_front()
	state = State.BUSY
	_attack_id += 1
	var id := _attack_id
	match pick:
		"slam": _atk_slam(id)
		"sweep": _atk_sweep(id)
		"throw": _atk_throw(id)
		"leap": _atk_leap(id)
		"storm": _atk_storm(id)


func _weighted(options: Dictionary) -> String:
	var total := 0
	for k in options:
		total += int(options[k])
	var r := _rng.randi_range(0, total - 1)
	for k in options:
		r -= int(options[k])
		if r < 0:
			return k
	return ""


func _end_attack(id: int, recovery: float) -> void:
	if id != _attack_id or state == State.DEAD or state == State.TRANSITION:
		return
	state = State.FIGHT
	_cooldown = recovery * (0.7 if phase == 2 else 1.0)
	_tracking = 1.0


func _cancelled(id: int) -> bool:
	return id != _attack_id or state == State.DEAD or state == State.TRANSITION


func _s() -> float:
	return 0.82 if phase == 2 else 1.0


# ---- Golpe vertical
func _atk_slam(id: int) -> void:
	_hit_this_attack = false
	_tracking = 0.9
	_pose("slam_windup", 0.55 * _s())
	ball_mode = "local"
	ball_local = Vector3(0.7, 5.3, 1.7)
	ball_k = 7.0
	await _w(0.65 * _s())
	if _cancelled(id): return
	_tracking = 0.15
	_lunge = -global_basis.z * 6.0
	_pose("slam", 0.15)
	ball_mode = "world"
	ball_world = global_transform * Vector3(0.35, BALL_R, -4.8)
	ball_k = 30.0
	await _w(0.16)
	if _cancelled(id): return
	_impact(ball_world, 2.9, 34.0, 0.7)
	FX.scorch(fx_parent, ball_world, 1.6, electrified)
	if electrified:
		_electric_wave(ball_world, 11.0, 0.9, 20.0)
		FX.burst(fx_parent, ball_world, true, 50, 1.0)
	ball_mode = "hang"
	await _w(0.9 * _s())
	if _cancelled(id): return
	_pose("idle", 0.5)
	await _w(0.3)
	_end_attack(id, _rng.randf_range(0.6, 1.1))


# ---- Barrido giratorio
func _atk_sweep(id: int) -> void:
	_hit_this_attack = false
	_tracking = 1.0
	_pose("sweep_windup", 0.45 * _s())
	ball_mode = "local"
	ball_local = Vector3(2.6, 1.3, 2.4)
	ball_k = 6.0
	await _w(0.55 * _s())
	if _cancelled(id): return
	_tracking = 0.0
	_pose("sweep", 0.15)
	ball_local = Vector3(4.7, 1.25, 0.0)
	ball_k = 22.0
	var spin_time := 1.25 * _s()
	_spin_left = spin_time
	_spin_rate = TAU * (1.5 if phase == 1 else 2.0) / spin_time
	var t := 0.0
	var spark_t := 0.0
	while t < spin_time:
		await get_tree().physics_frame
		if _cancelled(id):
			_spin_left = 0.0
			return
		var dt := get_physics_process_delta_time()
		t += dt
		_check_ball_hit(1.8, 28.0 + (8.0 if electrified else 0.0))
		if electrified:
			spark_t -= dt
			if spark_t <= 0.0:
				spark_t = 0.12
				FX.burst(fx_parent, ball_pos, true, 10, 0.6)
	_spin_left = 0.0
	ball_mode = "hang"
	_pose("idle", 0.6)
	await _w(1.0 * _s())
	_end_attack(id, _rng.randf_range(0.6, 1.0))


# ---- Lanzamiento de la cadena
func _atk_throw(id: int) -> void:
	_hit_this_attack = false
	_tracking = 1.0
	_pose("throw_windup", 0.5 * _s())
	ball_mode = "local"
	ball_local = Vector3(0.9, 4.8, 1.4)
	ball_k = 7.0
	await _w(0.6 * _s())
	if _cancelled(id) or not _valid_target(): return
	_tracking = 0.0
	var tp := target.global_position
	if target is CharacterBody3D:
		tp += (target as CharacterBody3D).velocity * 0.25
	var flat := tp - global_position
	flat.y = 0.0
	if flat.length() > 17.0:
		flat = flat.normalized() * 17.0
	var land := global_position + flat
	land.y = BALL_R
	_face_instant(land)
	_pose("throw", 0.12)
	ball_mode = "proj"
	ball_world = land
	ball_speed = 34.0
	var dist := ball_pos.distance_to(land)
	var tw := create_tween()
	tw.tween_property(self, "chain_len", dist + 1.0, 0.2)
	var t := 0.0
	var fly := dist / ball_speed + 0.05
	while t < fly:
		await get_tree().physics_frame
		if _cancelled(id): return
		t += get_physics_process_delta_time()
		_check_ball_hit(1.7, 26.0)
	_impact(land, 2.0, 0.0, 0.35)
	if electrified:
		_spawn_strike(land, 0.45, 2.6, 24.0)
	ball_mode = "hang"
	await _w(0.55 * _s())
	if _cancelled(id): return
	ball_mode = "local"
	ball_local = Vector3(0.6, 1.0, -1.4)
	ball_k = 5.0
	var tw2 := create_tween()
	tw2.tween_property(self, "chain_len", CHAIN_REST, 0.55)
	_pose("idle", 0.45)
	await _w(0.6)
	ball_mode = "hang"
	_end_attack(id, _rng.randf_range(0.5, 0.9))


# ---- Salto aplastante
func _atk_leap(id: int) -> void:
	if not _valid_target():
		_end_attack(id, 0.5)
		return
	_tracking = 1.0
	_pose("crouch", 0.35 * _s())
	await _w(0.45 * _s())
	if _cancelled(id) or not _valid_target(): return
	var land := _clamp_arena(target.global_position)
	land.y = 0.0
	_face_instant(land)
	_pose("air", 0.2)
	var T := 1.05 * _s()
	_start_jump(land, T, 6.0)
	await _w(T)
	if _cancelled(id):
		_kinematic = false
		return
	_kinematic = false
	_pose("land", 0.07)
	_impact(land, 4.3, 30.0, 0.9)
	FX.burst(fx_parent, land + Vector3(0, 0.3, 0), false, 40, 1.6)
	if electrified:
		_electric_wave(land, 12.0, 1.0, 20.0)
	await _w(0.35)
	if _cancelled(id): return
	_pose("idle", 0.6)
	await _w(0.9 * _s())
	_end_attack(id, _rng.randf_range(0.5, 0.9))


# ---- Fase 2: invocar rayos
func _atk_storm(id: int) -> void:
	_storm_cd = _rng.randf_range(9.0, 13.0)
	_tracking = 0.4
	_pose("roar", 0.5)
	ball_mode = "local"
	ball_local = Vector3(0.4, 6.4, 0.0)
	ball_k = 6.0
	await _w(0.7)
	if _cancelled(id): return
	FX.spawn_bolt(fx_parent, ball_pos + Vector3(_rng.randf_range(-6, 6), 70, _rng.randf_range(-6, 6)), ball_pos, _rng, 0.35)
	FX.burst(fx_parent, ball_pos, true, 60, 1.2)
	if weather and weather.has_method("flash"):
		weather.flash()
	_shake_target(0.3)
	var count := _rng.randi_range(6, 9)
	for i in count:
		if _cancelled(id): return
		var p: Vector3
		if i == 0 and _valid_target():
			p = target.global_position
		elif i % 2 == 1 and _valid_target():
			p = target.global_position + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
		else:
			var a := _rng.randf() * TAU
			p = Vector3(sin(a), 0, cos(a)) * _rng.randf_range(2.0, 19.0)
		_spawn_strike(_clamp_arena(p), _rng.randf_range(1.0, 1.4), 2.7, 30.0)
		await _w(0.22)
	if _cancelled(id): return
	await _w(0.6)
	ball_mode = "hang"
	_pose("idle", 0.6)
	await _w(0.7)
	_end_attack(id, 0.6)


# ---- Cambio de fase
func _start_phase2() -> void:
	state = State.TRANSITION
	_attack_id += 1
	_spin_left = 0.0
	_kinematic = false
	_lunge = Vector3.ZERO
	chain_len = CHAIN_REST
	ball_mode = "hang"
	_pose("kneel", 0.5)
	await _w(1.4)
	if state == State.DEAD: return
	phase = 2
	phase_changed.emit(2)
	_pose("roar", 0.8)
	ball_mode = "local"
	ball_local = Vector3(0.4, 6.4, 0.0)
	ball_k = 3.5
	_set_eyes(Color(0.45, 0.75, 1.0), 2.0)
	await _w(1.5)
	if state == State.DEAD: return
	FX.spawn_bolt(fx_parent, ball_pos + Vector3(4, 75, -3), ball_pos, _rng, 0.6)
	FX.burst(fx_parent, ball_pos, true, 120, 1.6)
	if weather and weather.has_method("flash"):
		weather.flash()
	_shake_target(0.8)
	_set_electrified(true)
	_set_eyes(Color(0.45, 0.75, 1.0), 6.0)
	FX.shockwave(fx_parent, global_position, 10.0, Color(0.5, 0.75, 1.0), 0.6)
	if _valid_target():
		var d := _flat_dist(target.global_position, global_position)
		if d < 7.0:
			_hit_target(14.0, global_position)
	await _w(1.6)
	if state == State.DEAD: return
	ball_mode = "hang"
	_pose("idle", 0.6)
	await _w(0.5)
	_storm_cd = 2.5
	_ambient_cd = 4.0
	state = State.FIGHT
	_cooldown = 0.3


func _die() -> void:
	state = State.DEAD
	_attack_id += 1
	_spin_left = 0.0
	_kinematic = false
	_lunge = Vector3.ZERO
	ball_mode = "hang"
	chain_len = CHAIN_REST
	_pose("kneel", 0.6)
	_set_electrified(false)
	_set_eyes(Color(0.45, 0.75, 1.0), 1.0)
	defeated.emit()
	await _w(1.6)
	_pose("dead", 1.4)
	var tw := create_tween()
	tw.tween_method(func(v): m_eye.emission_energy_multiplier = v, 1.0, 0.0, 2.0)


# =====================================================================
#  Daño y efectos de combate
# =====================================================================

func _valid_target() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if "is_dead" in target and target.is_dead:
		return false
	return true


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _clamp_arena(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() > 19.0:
		flat = flat.normalized() * 19.0
	return Vector3(flat.x, 0.0, flat.y)


func _hit_target(dmg: float, from: Vector3) -> void:
	if _valid_target() and target.has_method("take_damage"):
		target.take_damage(dmg * damage_multiplier, from)


func _check_ball_hit(radius: float, dmg: float) -> void:
	if _hit_this_attack or not _valid_target():
		return
	var c := target.global_position + Vector3(0, 0.9, 0)
	if ball_pos.distance_to(c) < radius:
		_hit_this_attack = true
		_hit_target(dmg, ball_pos)


func _impact(pos: Vector3, radius: float, dmg: float, shake: float) -> void:
	FX.shockwave(fx_parent, pos, radius * 1.3, Color(0.85, 0.82, 0.75) if not electrified else Color(0.5, 0.75, 1.0), 0.45)
	FX.burst(fx_parent, pos + Vector3(0, 0.2, 0), false, 26, 1.0)
	_shake_target(shake)
	if dmg > 0.0 and _valid_target() and _flat_dist(target.global_position, pos) < radius:
		if not _hit_this_attack:
			_hit_this_attack = true
			_hit_target(dmg, pos)


func _electric_wave(pos: Vector3, max_r: float, time: float, dmg: float) -> void:
	FX.shockwave(fx_parent, pos, max_r, Color(0.5, 0.75, 1.0), time)
	_waves.append({"pos": pos, "r": 0.0, "max": max_r, "speed": max_r / time, "dmg": dmg, "hit": false})


func _update_waves(delta: float) -> void:
	for i in range(_waves.size() - 1, -1, -1):
		var wv: Dictionary = _waves[i]
		wv["r"] += float(wv["speed"]) * delta
		var r: float = wv["r"]
		if not wv["hit"] and _valid_target() and r > 1.0:
			var d := _flat_dist(target.global_position, wv["pos"])
			if absf(d - r) < 0.8:
				wv["hit"] = true
				_hit_target(wv["dmg"], wv["pos"])
		if r >= float(wv["max"]):
			_waves.remove_at(i)


func _spawn_strike(pos: Vector3, delay: float, radius: float, dmg: float) -> void:
	var s := Node3D.new()
	s.set_script(STRIKE)
	s.set("delay", delay)
	s.set("radius", radius)
	s.set("damage", dmg * damage_multiplier)
	s.set("weather", weather)
	s.position = pos
	fx_parent.add_child(s)


func _shake_target(amount: float) -> void:
	if _valid_target() and target.has_method("add_camera_shake"):
		var d := target.global_position.distance_to(global_position)
		target.add_camera_shake(amount * clampf(1.4 - d / 30.0, 0.3, 1.0))


func _w(t: float) -> Signal:
	return get_tree().create_timer(t, false, true).timeout


# =====================================================================
#  Modelo
# =====================================================================

func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _cyl(top: float, bot: float, h: float, segs := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _sph(r: float, h: float, segs := 16) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = segs
	s.rings = segs / 2
	return s


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _joint(parent: Node3D, key: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = key
	j.position = pos
	parent.add_child(j)
	joints[key] = j
	return j


func _build_model() -> void:
	m_steel = _mat(Color(0.52, 0.53, 0.56), 0.38, 0.6)
	m_steel.emission_enabled = true
	m_steel.emission = Color(1, 1, 1)
	m_steel.emission_energy_multiplier = 0.0
	var m_dark := _mat(Color(0.16, 0.16, 0.17), 0.5, 0.5)
	var m_trim := _mat(Color(0.6, 0.47, 0.22), 0.35, 0.7)
	var m_shirt := _mat(Color(0.86, 0.84, 0.76), 0.9, 0.0)     # camisa blanca
	var m_denim := _mat(Color(0.15, 0.21, 0.33), 0.85, 0.0)    # mezclilla
	var m_bag := _mat(Color(0.06, 0.07, 0.11), 0.7, 0.0)       # morral azul marino
	var m_book := _mat(Color(0.42, 0.06, 0.06), 0.6, 0.0)      # libreta roja
	var m_gown := _mat(Color(0.03, 0.03, 0.035), 0.8, 0.0)     # toga académica
	var m_gold := _mat(Color(0.75, 0.55, 0.15), 0.4, 0.8)
	m_eye = _mat(Color(0, 0, 0), 0.3, 0.0)
	m_eye.emission_enabled = true
	m_eye.emission = Color(1.0, 0.45, 0.12)
	m_eye.emission_energy_multiplier = 3.0

	model = Node3D.new()
	model.name = "Model"
	model.scale = Vector3.ONE * model_scale
	add_child(model)

	pelvis = _joint(model, "pelvis", Vector3(0, 0.95, 0))
	# Cintura: escarcela, faldones, cinturón, tabardo
	_part(pelvis, _cyl(0.27, 0.31, 0.24), m_steel, Vector3(0, -0.02, 0), Vector3.ZERO, Vector3(1, 1, 0.78))
	_part(pelvis, _cyl(0.29, 0.29, 0.06), m_bag, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 1, 0.8))
	_part(pelvis, _box(Vector3(0.1, 0.08, 0.03)), m_gold, Vector3(0, 0.1, -0.235))
	for side in [-1.0, 1.0]:
		_part(pelvis, _box(Vector3(0.2, 0.26, 0.035)), m_steel, Vector3(side * 0.15, -0.22, -0.2), Vector3(-12, 0, side * -8))
		_part(pelvis, _box(Vector3(0.035, 0.26, 0.2)), m_steel, Vector3(side * 0.29, -0.2, 0.0), Vector3(0, 0, side * 10))
	_part(pelvis, _box(Vector3(0.24, 0.58, 0.02)), m_shirt, Vector3(0, -0.33, -0.235), Vector3(-6, 0, 0))
	_part(pelvis, _box(Vector3(0.2, 0.1, 0.022)), m_trim, Vector3(0, -0.6, -0.27), Vector3(-6, 0, 0))
	# Libreta roja encadenada a la cadera izquierda
	_part(pelvis, _box(Vector3(0.06, 0.26, 0.2)), m_book, Vector3(-0.36, -0.12, 0.02), Vector3(0, 0, 8))
	_part(pelvis, _box(Vector3(0.065, 0.2, 0.012)), m_shirt, Vector3(-0.36, -0.12, -0.085), Vector3(0, 0, 8))
	# Morral cruzado en la cadera derecha
	_part(pelvis, _box(Vector3(0.12, 0.3, 0.34)), m_bag, Vector3(0.37, -0.02, 0.06), Vector3(0, 0, -6))
	_part(pelvis, _box(Vector3(0.125, 0.12, 0.345)), m_dark, Vector3(0.375, 0.1, 0.06), Vector3(0, 0, -6))

	# Piernas
	for side in [-1.0, 1.0]:
		var pre := "l" if side < 0 else "r"
		var hip := _joint(pelvis, pre + "h", Vector3(side * 0.15, -0.06, 0))
		_part(hip, _cyl(0.12, 0.105, 0.44), m_denim, Vector3(0, -0.22, 0.01))
		_part(hip, _cyl(0.135, 0.115, 0.36, 10), m_steel, Vector3(0, -0.2, -0.025), Vector3.ZERO, Vector3(1, 1, 0.9))
		var knee := _joint(hip, pre + "k", Vector3(0, -0.43, 0))
		_part(knee, _sph(0.1, 0.18, 12), m_trim, Vector3(0, 0, -0.06), Vector3.ZERO, Vector3(1.1, 1, 0.8))
		_part(knee, _cyl(0.115, 0.095, 0.38), m_steel, Vector3(0, -0.21, 0))
		_part(knee, _box(Vector3(0.18, 0.1, 0.34)), m_dark, Vector3(0, -0.44, -0.07))
		_part(knee, _box(Vector3(0.16, 0.06, 0.12)), m_steel, Vector3(0, -0.41, -0.2), Vector3(20, 0, 0))

	# Torso
	var spine := _joint(pelvis, "spine", Vector3(0, 0.07, 0))
	_part(spine, _cyl(0.31, 0.27, 0.3), m_dark, Vector3(0, 0.15, 0), Vector3.ZERO, Vector3(1, 1, 0.76))
	for i in 3:
		_part(spine, _cyl(0.3 - i * 0.01, 0.32 - i * 0.01, 0.06), m_steel, Vector3(0, 0.05 + i * 0.09, 0), Vector3.ZERO, Vector3(1, 1, 0.8))
	var chest := _joint(spine, "chest", Vector3(0, 0.27, 0))
	_part(chest, _sph(0.37, 0.74, 20), m_steel, Vector3(0, 0.14, 0.0), Vector3.ZERO, Vector3(1.18, 0.95, 0.86))
	_part(chest, _box(Vector3(0.04, 0.42, 0.04)), m_trim, Vector3(0, 0.14, -0.305), Vector3(-4, 0, 0))
	_part(chest, _box(Vector3(0.5, 0.05, 0.05)), m_trim, Vector3(0, -0.06, -0.27), Vector3(10, 0, 0))
	_part(chest, _cyl(0.18, 0.21, 0.14), m_steel, Vector3(0, 0.42, 0))
	_part(chest, _cyl(0.165, 0.17, 0.07), m_shirt, Vector3(0, 0.5, 0))   # cuello de camisa
	# Correa del morral cruzando el pecho
	_part(chest, _box(Vector3(0.07, 0.86, 0.025)), m_bag, Vector3(0.0, 0.1, -0.315), Vector3(-8, 0, 38))
	_part(chest, _box(Vector3(0.07, 0.6, 0.025)), m_bag, Vector3(0.05, 0.12, 0.33), Vector3(8, 0, -38))
	# Toga académica (capa rasgada)
	cape = _joint(chest, "cape", Vector3(0, 0.36, 0.3))
	for i in 3:
		var x := (i - 1) * 0.24
		var len := 1.25 - absf(i - 1) * 0.15 + _rng.randf_range(-0.08, 0.05)
		_part(cape, _box(Vector3(0.26, len, 0.02)), m_gown, Vector3(x, -len * 0.5, 0.02 + absf(i - 1) * 0.02), Vector3(-6, (i - 1) * -12.0, 0))

	# Brazos
	for side in [-1.0, 1.0]:
		var pre := "l" if side < 0 else "r"
		var sh := _joint(chest, pre + "s", Vector3(side * 0.43, 0.27, 0))
		_part(sh, _sph(0.22, 0.32, 16), m_steel, Vector3(side * 0.04, 0.05, 0), Vector3(0, 0, side * -12), Vector3(1.15, 1, 1.1))
		_part(sh, _sph(0.2, 0.2, 14), m_steel, Vector3(side * 0.07, -0.07, 0), Vector3(0, 0, side * -25), Vector3(1.05, 1, 1.05))
		_part(sh, _box(Vector3(0.05, 0.05, 0.3)), m_trim, Vector3(side * 0.15, 0.13, 0), Vector3(0, 0, side * -30))
		_part(sh, _cyl(0.09, 0.085, 0.32), m_shirt, Vector3(0, -0.16, 0))          # manga blanca
		_part(sh, _cyl(0.1, 0.095, 0.16), m_steel, Vector3(0, -0.24, 0))
		var el := _joint(sh, pre + "e", Vector3(0, -0.32, 0))
		_part(el, _sph(0.085, 0.15, 10), m_trim, Vector3(0, 0, 0.03))
		_part(el, _cyl(0.088, 0.075, 0.26), m_steel, Vector3(0, -0.14, 0))
		_part(el, _cyl(0.11, 0.085, 0.07), m_steel, Vector3(0, -0.25, 0))
		_part(el, _box(Vector3(0.13, 0.15, 0.13)), m_dark, Vector3(0, -0.33, -0.01))
		if side > 0:
			# Mango de la maza
			var hand := Node3D.new()
			hand.position = Vector3(0, -0.33, 0)
			el.add_child(hand)
			_part(hand, _cyl(0.032, 0.035, 0.62, 8), m_dark, Vector3(0, -0.22, 0))
			_part(hand, _sph(0.05, 0.1, 8), m_trim, Vector3(0, 0.1, 0))
			_part(hand, _cyl(0.05, 0.05, 0.06, 8), m_trim, Vector3(0, -0.52, 0))
			tip = Marker3D.new()
			tip.position = Vector3(0, -0.56, 0)
			hand.add_child(tip)

	# Cabeza: yelmo cerrado con birrete
	var head := _joint(chest, "head", Vector3(0, 0.5, 0))
	_part(head, _cyl(0.165, 0.18, 0.34, 16), m_steel, Vector3(0, 0.17, 0), Vector3.ZERO, Vector3(1, 1, 1.08))
	_part(head, _sph(0.165, 0.16, 16), m_steel, Vector3(0, 0.34, 0), Vector3.ZERO, Vector3(1, 1, 1.08))
	_part(head, _box(Vector3(0.03, 0.3, 0.05)), m_trim, Vector3(0, 0.2, -0.18))
	_part(head, _box(Vector3(0.3, 0.035, 0.03)), m_dark, Vector3(0, 0.2, -0.178))
	_part(head, _box(Vector3(0.34, 0.03, 0.36)), m_trim, Vector3(0, 0.02, 0))
	for side in [-1.0, 1.0]:
		# "Lentes": rendijas redondas que brillan
		_part(head, _cyl(0.04, 0.04, 0.02, 14), m_dark, Vector3(side * 0.065, 0.2, -0.18), Vector3(90, 0, 0))
		_part(head, _cyl(0.028, 0.028, 0.02, 12), m_eye, Vector3(side * 0.065, 0.2, -0.185), Vector3(90, 0, 0))
		for k in 3:
			_part(head, _box(Vector3(0.012, 0.05, 0.02)), m_dark, Vector3(side * (0.04 + k * 0.025), 0.1, -0.185))
	_part(head, _cyl(0.06, 0.06, 0.04), m_dark, Vector3(0, 0.38, 0))
	_part(head, _box(Vector3(0.46, 0.035, 0.46)), m_dark, Vector3(0, 0.41, 0), Vector3(0, 0, 0))
	_part(head, _sph(0.025, 0.05, 8), m_gold, Vector3(0, 0.435, 0))
	var tassel := Node3D.new()
	tassel.position = Vector3(0.2, 0.42, -0.2)
	head.add_child(tassel)
	_part(tassel, _box(Vector3(0.012, 0.2, 0.012)), m_gold, Vector3(0, -0.1, 0), Vector3(0, 0, -6))
	_part(tassel, _cyl(0.015, 0.035, 0.08, 8), m_gold, Vector3(0.01, -0.22, 0))
	joints["tassel"] = tassel

	eye_light = OmniLight3D.new()
	eye_light.position = Vector3(0, 0.2, -0.3)
	eye_light.light_color = Color(1.0, 0.45, 0.12)
	eye_light.light_energy = 0.6
	eye_light.omni_range = 1.6
	head.add_child(eye_light)
	# Luz tenue de "presencia" para que el modelo se lea en la oscuridad
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.6, 1.9, -1.6)
	fill.light_color = Color(0.7, 0.75, 0.85)
	fill.light_energy = 0.7
	fill.omni_range = 5.5
	model.add_child(fill)


func _set_eyes(c: Color, energy: float) -> void:
	m_eye.emission = c
	var tw := create_tween()
	tw.tween_property(m_eye, "emission_energy_multiplier", energy, 0.4)
	eye_light.light_color = c
	tw.parallel().tween_property(eye_light, "light_energy", energy * 0.4, 0.4)


func _build_flail() -> void:
	m_chain = _mat(Color(0.18, 0.18, 0.19), 0.35, 0.9)
	m_chain.emission_enabled = true
	m_chain.emission = Color(0.4, 0.7, 1.0)
	m_chain.emission_energy_multiplier = 0.0
	m_ball = _mat(Color(0.14, 0.14, 0.15), 0.3, 0.9)
	m_ball.emission_enabled = true
	m_ball.emission = Color(0.4, 0.7, 1.0)
	m_ball.emission_energy_multiplier = 0.0

	ball = Node3D.new()
	ball.name = "FlailHead"
	ball.top_level = true
	add_child(ball)
	_part(ball, _sph(BALL_R, BALL_R * 2.0, 20), m_ball, Vector3.ZERO)
	_part(ball, _cyl(BALL_R * 1.03, BALL_R * 1.03, 0.08, 20), m_chain, Vector3.ZERO)
	var n := 18
	for i in n:
		var y := 1.0 - (i + 0.5) / n * 2.0
		var r := sqrt(1.0 - y * y)
		var a := i * 2.39996
		var dir := Vector3(cos(a) * r, y, sin(a) * r)
		var spike := MeshInstance3D.new()
		spike.mesh = _cyl(0.0, 0.075, 0.34, 6)
		spike.material_override = m_chain
		spike.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), dir * (BALL_R + 0.12))
		ball.add_child(spike)
	_part(ball, _cyl(0.06, 0.08, 0.12, 8), m_chain, Vector3(0, BALL_R + 0.03, 0))

	ball_light = OmniLight3D.new()
	ball_light.light_color = Color(0.45, 0.7, 1.0)
	ball_light.light_energy = 0.0
	ball_light.omni_range = 7.0
	ball.add_child(ball_light)

	ball_arcs = MeshInstance3D.new()
	ball_arcs.material_override = FX.bolt_material(true)
	ball_arcs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball_arcs.visible = false
	ball.add_child(ball_arcs)

	ball_sparks = GPUParticles3D.new()
	ball_sparks.amount = 40
	ball_sparks.lifetime = 0.4
	ball_sparks.emitting = false
	ball_sparks.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = BALL_R + 0.1
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -9, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	ball_sparks.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 0.12)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_color = Color(0.7, 0.85, 1.0) * 3.0
	q.material = sm
	ball_sparks.draw_pass_1 = q
	ball.add_child(ball_sparks)

	var link_mesh := TorusMesh.new()
	link_mesh.inner_radius = 0.04
	link_mesh.outer_radius = 0.085
	link_mesh.rings = 10
	link_mesh.ring_segments = 6
	for i in 16:
		var l := MeshInstance3D.new()
		l.mesh = link_mesh
		l.material_override = m_chain
		l.top_level = true
		add_child(l)
		links.append(l)


func _set_electrified(on: bool) -> void:
	electrified = on
	ball_sparks.emitting = on
	ball_arcs.visible = on
	var tw := create_tween().set_parallel(true)
	tw.tween_property(m_ball, "emission_energy_multiplier", 2.2 if on else 0.0, 0.5)
	tw.tween_property(m_chain, "emission_energy_multiplier", 1.2 if on else 0.0, 0.5)
	tw.tween_property(ball_light, "light_energy", 4.0 if on else 0.0, 0.5)


# =====================================================================
#  Animación procedural
# =====================================================================

const JOINT_KEYS := ["pelvis", "spine", "chest", "head", "ls", "le", "rs", "re", "lh", "lk", "rh", "rk"]


func _P(d: Dictionary) -> Dictionary:
	var out := {"y": 0.0}
	for k in JOINT_KEYS:
		out[k] = Vector3.ZERO
	for k in d:
		out[k] = d[k]
	return out


func _v(x: float, y: float = 0.0, z: float = 0.0) -> Vector3:
	return Vector3(x, y, z)


func _define_poses() -> void:
	poses["idle"] = _P({"spine": _v(-6), "chest": _v(-2), "head": _v(5),
		"ls": _v(12, 0, -14), "le": _v(35), "rs": _v(30, 0, 12), "re": _v(30),
		"lh": _v(12, 0, -7), "lk": _v(-20), "rh": _v(-4, 0, 7), "rk": _v(-10), "y": -0.04})
	poses["dormant"] = _P({"head": _v(-14), "ls": _v(4, 0, -8), "le": _v(12),
		"rs": _v(10, 0, 8), "re": _v(10), "lh": _v(0, 0, -5), "rh": _v(0, 0, 5)})
	poses["slam_windup"] = _P({"spine": _v(14, 15), "chest": _v(6, 10), "head": _v(-10, -20),
		"ls": _v(50, 0, -30), "le": _v(40), "rs": _v(200, 0, 18), "re": _v(25),
		"lh": _v(22, 0, -8), "lk": _v(-26), "rh": _v(-14, 0, 8), "rk": _v(-14), "y": -0.08})
	poses["slam"] = _P({"spine": _v(-32, -8), "chest": _v(-10, -5), "head": _v(22),
		"ls": _v(-25, 0, -25), "le": _v(20), "rs": _v(75, 0, 8), "re": _v(5),
		"lh": _v(40, 0, -8), "lk": _v(-58), "rh": _v(-30, 0, 8), "rk": _v(-26), "y": -0.2})
	poses["sweep_windup"] = _P({"spine": _v(-8, -35), "chest": _v(0, -20), "head": _v(0, 45),
		"ls": _v(30, 0, -35), "le": _v(50), "rs": _v(40, 0, 70), "re": _v(20),
		"lh": _v(16, 0, -12), "lk": _v(-30), "rh": _v(-10, 0, 12), "rk": _v(-20), "y": -0.12})
	poses["sweep"] = _P({"spine": _v(-10, 10), "chest": _v(0, 5), "head": _v(0, -10),
		"ls": _v(20, 0, -50), "le": _v(30), "rs": _v(10, 0, 84), "re": _v(5),
		"lh": _v(12, 0, -14), "lk": _v(-30), "rh": _v(-8, 0, 14), "rk": _v(-28), "y": -0.14})
	poses["throw_windup"] = _P({"spine": _v(10, -20), "chest": _v(4, -10), "head": _v(-4, 25),
		"ls": _v(80, 10, -5), "le": _v(5), "rs": _v(195, 0, 25), "re": _v(30),
		"lh": _v(20, 0, -8), "lk": _v(-25), "rh": _v(-15, 0, 8), "rk": _v(-12), "y": -0.08})
	poses["throw"] = _P({"spine": _v(-20, 20), "chest": _v(-6, 10), "head": _v(14, -25),
		"ls": _v(-10, 0, -30), "le": _v(30), "rs": _v(95, 0, 6), "re": _v(0),
		"lh": _v(30, 0, -8), "lk": _v(-35), "rh": _v(-25, 0, 8), "rk": _v(-15), "y": -0.12})
	poses["crouch"] = _P({"spine": _v(-25), "head": _v(20), "ls": _v(-20, 0, -25), "le": _v(40),
		"rs": _v(-15, 0, 25), "re": _v(40), "lh": _v(60, 0, -10), "lk": _v(-95),
		"rh": _v(60, 0, 10), "rk": _v(-95), "y": -0.33})
	poses["air"] = _P({"spine": _v(-10), "head": _v(8), "ls": _v(40, 0, -40), "le": _v(60),
		"rs": _v(150, 0, 30), "re": _v(30), "lh": _v(50, 0, -8), "lk": _v(-80),
		"rh": _v(10, 0, 8), "rk": _v(-40)})
	poses["land"] = _P({"spine": _v(-35), "head": _v(25), "ls": _v(-30, 0, -40), "le": _v(30),
		"rs": _v(60, 0, 20), "re": _v(10), "lh": _v(55, 0, -12), "lk": _v(-100),
		"rh": _v(40, 0, 12), "rk": _v(-90), "y": -0.33})
	poses["roar"] = _P({"spine": _v(18), "chest": _v(8), "head": _v(28), "rs": _v(172, 0, 8),
		"re": _v(5), "ls": _v(40, 0, -55), "le": _v(60), "lh": _v(14, 0, -14), "lk": _v(-22),
		"rh": _v(-8, 0, 14), "rk": _v(-12), "y": -0.08})
	poses["kneel"] = _P({"spine": _v(-20), "head": _v(-10), "ls": _v(35, 0, -20), "le": _v(60),
		"rs": _v(10, 0, 25), "re": _v(20), "lh": _v(85, 0, -6), "lk": _v(-90),
		"rh": _v(-10, 0, 6), "rk": _v(-95), "y": -0.46})
	poses["dead"] = _P({"spine": _v(-55, 0, 10), "chest": _v(-15), "head": _v(-30, 0, 15),
		"ls": _v(10, 0, -10), "le": _v(10), "rs": _v(-5, 0, 15), "re": _v(5),
		"lh": _v(85, 0, -6), "lk": _v(-90), "rh": _v(-10, 0, 6), "rk": _v(-95), "y": -0.5})


func _pose(name: String, dur: float) -> void:
	_pose_from = _pose_cur.duplicate()
	_pose_to = poses[name]
	_pose_t = 0.0
	_pose_dur = maxf(dur, 0.01)


func _update_pose(delta: float) -> void:
	_pose_t = minf(_pose_t + delta, _pose_dur)
	var k := _pose_t / _pose_dur
	k = k * k * (3.0 - 2.0 * k)
	for key in JOINT_KEYS:
		var a: Vector3 = _pose_from[key]
		var b: Vector3 = _pose_to[key]
		_pose_cur[key] = a.lerp(b, k)
	_pose_cur["y"] = lerpf(_pose_from["y"], _pose_to["y"], k)

	var w := _walk_amt
	var s := sin(_walk_phase)
	var c := cos(_walk_phase)
	var breathe := sin(_anim_t * 1.6) * 1.5
	for key in JOINT_KEYS:
		var v: Vector3 = _pose_cur[key]
		match key:
			"lh": v.x += s * 26.0 * w
			"rh": v.x -= s * 26.0 * w
			"lk": v.x -= maxf(0.0, c) * 38.0 * w
			"rk": v.x -= maxf(0.0, -c) * 38.0 * w
			"ls": v.x -= s * 12.0 * w
			"spine":
				v.y += s * 6.0 * w
				v.x -= 4.0 * w
			"chest": v.x += breathe
		joints[key].rotation_degrees = v
	var bob := (absf(c) - 1.0) * 0.035 * w
	pelvis.position.y = 0.95 + _pose_cur["y"] + bob
	cape.rotation_degrees.x = 8.0 + sin(_anim_t * 2.3) * 3.0 + w * 10.0
	joints["tassel"].rotation_degrees.z = sin(_anim_t * 3.1) * 12.0


# =====================================================================
#  Maza con cadena
# =====================================================================

func _update_flail(delta: float) -> void:
	var tp := tip.global_position
	match ball_mode:
		"hang":
			ball_vel += Vector3(0, -20.0, 0) * delta
			ball_vel *= maxf(0.0, 1.0 - 0.9 * delta)
			ball_pos += ball_vel * delta
			var d := ball_pos - tp
			if d.length() > chain_len:
				var n := d.normalized()
				ball_pos = tp + n * chain_len
				var out := ball_vel.dot(n)
				if out > 0.0:
					ball_vel -= n * out
		"local", "world":
			var target_pos := (global_transform * ball_local) if ball_mode == "local" else ball_world
			var nb := ball_pos.lerp(target_pos, 1.0 - exp(-ball_k * delta))
			ball_vel = (nb - ball_pos) / maxf(delta, 0.0001)
			ball_pos = nb
		"proj":
			var nb2 := ball_pos.move_toward(ball_world, ball_speed * delta)
			ball_vel = (nb2 - ball_pos) / maxf(delta, 0.0001)
			ball_pos = nb2
	if ball_pos.y < BALL_R:
		ball_pos.y = BALL_R
		if ball_vel.y < 0.0:
			ball_vel.y *= -0.15
		ball_vel.x *= maxf(0.0, 1.0 - 5.0 * delta)
		ball_vel.z *= maxf(0.0, 1.0 - 5.0 * delta)
	var top_anchor := ball_pos + Vector3(0, BALL_R + 0.05, 0)
	var spin_axis := (tp - ball_pos)
	ball.global_position = ball_pos
	if spin_axis.length() > 0.1 and spin_axis.normalized().dot(Vector3.DOWN) < 0.99:
		ball.global_basis = Basis(Quaternion(Vector3.UP, spin_axis.normalized()))
		top_anchor = ball_pos + spin_axis.normalized() * (BALL_R + 0.05)

	# Eslabones a lo largo de una curva con caída según la holgura
	var p0 := tp
	var p2 := top_anchor
	var dist := p0.distance_to(p2)
	var slack := maxf(0.0, chain_len - dist) if ball_mode == "hang" else 0.0
	var p1 := (p0 + p2) * 0.5 + Vector3(0, -slack * 0.55, 0)
	var n_links := links.size()
	var prev := p0
	for i in n_links:
		var t := (i + 0.5) / n_links
		var a := p0.lerp(p1, t)
		var b := p1.lerp(p2, t)
		var p := a.lerp(b, t)
		var tan := (b - a).normalized()
		if tan.length() < 0.5:
			tan = (p - prev).normalized() if (p - prev).length() > 0.001 else Vector3.DOWN
		var ref := Vector3.UP if absf(tan.y) < 0.9 else Vector3.RIGHT
		var side := tan.cross(ref).normalized()
		if i % 2 == 1:
			side = tan.cross(side).normalized()
		var third := tan.cross(side).normalized()
		var stretch := clampf(dist / (n_links * 0.16), 1.0, 2.2)
		links[i].global_transform = Transform3D(Basis(tan * 1.5 * stretch, side, third), p)
		prev = p


func _update_effects(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 7.0)
		m_steel.emission_energy_multiplier = _hit_flash * 0.6
	if electrified:
		_arc_t -= delta
		if _arc_t <= 0.0:
			_arc_t = 0.05
			var paths := []
			var widths := []
			for i in 3:
				var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
				var a := dir * BALL_R * 0.9
				var b := dir * _rng.randf_range(0.7, 1.3) + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3))
				paths.append(FX.jagged_points(a, b, 5, 0.18, _rng))
				widths.append(0.035)
			ball_arcs.mesh = FX.ribbon_mesh(paths, widths)
			ball_light.light_energy = _rng.randf_range(2.5, 5.0)
