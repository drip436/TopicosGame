extends CharacterBody3D
## Cuarto jefe: "Doctor Viktor Kessler, el Paciente Cero" (Laboratorio de Biogenética).
## Científico loco que experimentaba con humanos… y consigo mismo. Viejo enorme y
## musculoso, pelo blanco peinado hacia atrás, cara llena de cicatrices, un ojo
## muerto, traje negro con bata de laboratorio rota.
## Armas: un TUBO RADIACTIVO (cuerpo a cuerpo) y una PISTOLA LÁSER (a distancia).
##
##   Fase 1 (escurridizo): lanza frascos de veneno (daño en área + charcos que llenan
##           la barra de VENENO), dispara la pistola láser, golpea con el tubo,
##           invoca mutantes pequeños mientras sigue con sus experimentos (si no lo
##           interrumpes, se cura), y suelta hordas de 6+ mutantes para esconderse
##           (se vuelve casi invisible detrás de ellos). Si te le acercas, escapa.
##   Fase 2 (al 50 %): se inyecta su suero y se convierte en un mutante gigante:
##           lanza barriles de toxinas, te agarra y te estampa contra la pared,
##           aplasta con el tubo y barre la sala con un rayo láser.
## El controlador de la pelea es lab_fight.gd.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float)
signal battle_started
signal phase_changed(phase: int)
signal defeated

const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const FX := preload("res://boss_profesor/boss_fx.gd")
const ENEMY := preload("res://mundo/enemy.gd")
const BOLT := preload("res://mundo/enemy_bolt.gd")

enum State { DORMANT, INTRO, FIGHT, BUSY, TRANSITION, DEAD }

@export var boss_name: String = "Doctor Viktor Kessler, el Paciente Cero"
@export var max_health: float = 1450.0
@export_range(0.1, 0.9) var phase2_threshold: float = 0.5
@export var move_speed: float = 3.3
@export var damage_multiplier: float = 1.0
## Máximo de mutantes invocados vivos al mismo tiempo.
@export var max_minions: int = 4

var state: int = State.DORMANT
var phase := 1
var health := 0.0
var target: Node3D
var fx_parent: Node
## Nodo donde se agregan los mutantes invocados (lo pone el controlador).
var minion_parent: Node
var arena_center := Vector3.ZERO
var arena_radius := 19.0

# Modelo
var model: Node3D
var J := {}
var _meshes: Array[MeshInstance3D] = []
var _mut_parts: Array[Node3D] = []
var _coat: Array[Node3D] = []
var m_skin: StandardMaterial3D
var m_eye: StandardMaterial3D
var m_flash: StandardMaterial3D
var m_tube: StandardMaterial3D
var m_poison: StandardMaterial3D
var m_puddle: StandardMaterial3D
var muzzle: Node3D

# Poses
var poses := {}
var _from := {}
var _to := {}
var _cur := {}
var _pose_t := 1.0
var _pose_dur := 0.3
var _walk_phase := 0.0
var _walk_amt := 0.0
var _anim_t := 0.0
var _jitter := 0.0

# IA
var _rng := RandomNumberGenerator.new()
var _attack_id := 0
var _cooldown := 1.2
var _tracking := 1.0
var _lunge := Vector3.ZERO
var _kinematic := false
var _flash := 0.0
var _last: Array[String] = []
var _close_t := 0.0
var _escape_cd := 4.0
var _horde_cd := 14.0
var _summon_cd := 3.0
var _experiment_cd := 8.0
var _grab_cd := 3.0
var _hidden := false
var _hide_t := 0.0
var _channeling := false
var _minions: Array = []
var _puddles: Array = []        # [{node, pos, r, t}]
var _puddle_tick := 0.0


func _ready() -> void:
	_rng.randomize()
	add_to_group("boss")
	add_to_group("enemy")
	health = max_health
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.6
		cap.height = 2.7
		cs.shape = cap
		cs.position = Vector3(0, 1.35, 0)
		add_child(cs)
	_build_model()
	_define_poses()
	_cur = poses["experiment"].duplicate()
	_from = _cur.duplicate()
	_to = _cur.duplicate()


# =====================================================================
#  API
# =====================================================================

## Trabajando en su mesa, de espaldas, hasta que llega el jugador.
func place_dormant(pos: Vector3, look_point: Vector3) -> void:
	global_position = pos
	_face_instant(look_point)
	state = State.DORMANT
	_pose("experiment", 0.1)


func begin_intro() -> void:
	if state != State.DORMANT:
		return
	state = State.INTRO
	_kinematic = true
	_pose("idle", 0.6)
	await _w(0.8)
	if _valid_target():
		var t0 := rotation.y
		var d := target.global_position - global_position
		var want := atan2(-d.x, -d.z)
		var tw := create_tween()
		tw.tween_method(func(v: float): rotation.y = lerp_angle(t0, want, v), 0.0, 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	await _w(1.3)
	_pose("laugh", 0.3)
	_jitter = 0.6
	LFX.puff(fx_parent, global_position + Vector3(0, 1.0, 0), Color(0.4, 1.2, 0.2, 0.8), 40, 0.5, 3.0, 1.0)
	await _w(1.6)
	_jitter = 0.0
	_pose("guard", 0.4)
	await _w(0.4)
	_kinematic = false
	state = State.FIGHT
	_cooldown = 0.5
	battle_started.emit()


func take_damage(amount: float, _from_pos: Variant = null) -> void:
	if state in [State.DORMANT, State.INTRO, State.TRANSITION, State.DEAD]:
		return
	health -= amount
	_flash = 1.0
	damaged.emit(amount)
	# Interrumpe sus experimentos
	if _channeling:
		_channeling = false
		_attack_id += 1
		_kinematic = false
		state = State.FIGHT
		_cooldown = 0.6
		_pose("stagger", 0.15)
		LFX.puff(fx_parent, global_position + Vector3(0, 1.4, 0), Color(0.5, 1.4, 0.2, 0.9), 30, 0.25, 4.0, -5.0)
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
	if phase == 1:
		_close_t += 0.5


func debug_force_phase2() -> void:
	if phase == 1 and state != State.DEAD:
		health = max_health * phase2_threshold
		health_changed.emit(health, max_health)
		_start_phase2()


## Elimina a todos los mutantes invocados (al ganar o reintentar).
func clear_minions() -> void:
	for m in _minions:
		if is_instance_valid(m) and not m.is_dead:
			m._die()
	_minions.clear()


# =====================================================================
#  Bucle
# =====================================================================

func _physics_process(delta: float) -> void:
	_anim_t += delta
	if not _kinematic:
		_update_movement(delta)
	else:
		velocity = Vector3(0, -0.5 if is_on_floor() else velocity.y - 30.0 * delta, 0)
		move_and_slide()
	_update_pose(delta)
	_flash = maxf(0.0, _flash - delta * 5.0)
	m_flash.emission_energy_multiplier = _flash * 2.5
	for m in _meshes:
		m.material_overlay = m_flash if _flash > 0.01 else null
	m_tube.emission_energy_multiplier = 2.5 + sin(_anim_t * 5.0) * 0.8
	_update_puddles(delta)
	_minions = _minions.filter(func(m): return is_instance_valid(m) and not m.is_dead)
	if state in [State.FIGHT, State.BUSY] and _valid_target():
		var d := _flat(target.global_position, global_position)
		_close_t = _close_t + delta if d < 3.8 else maxf(0.0, _close_t - delta)
	if state == State.FIGHT:
		_think(delta)
	_escape_cd -= delta
	_horde_cd -= delta
	_summon_cd -= delta
	_experiment_cd -= delta
	_grab_cd -= delta
	if _hidden:
		_hide_t -= delta


func _update_movement(delta: float) -> void:
	var desired := Vector3.ZERO
	if state == State.FIGHT and _valid_target():
		var to := target.global_position - global_position
		to.y = 0.0
		var d := to.length()
		_turn_toward(target.global_position, delta, 1.0)
		if phase == 1:
			# Escurridizo: prefiere mantener distancia media
			if d < 5.0:
				desired = -to.normalized() * move_speed * 0.9
			elif d > 11.0 and not _hidden:
				desired = to.normalized() * move_speed
			else:
				desired = to.normalized().cross(Vector3.UP) * move_speed * 0.6 * (1.0 if int(_anim_t / 3.0) % 2 == 0 else -1.0)
		elif d > 4.0:
			desired = to.normalized() * move_speed * 1.05
	elif state == State.BUSY and _valid_target():
		_turn_toward(target.global_position, delta, _tracking)
	desired += _lunge
	_lunge = _lunge.move_toward(Vector3.ZERO, 16.0 * delta)
	# No salir de la sala
	var off := global_position + desired * delta - arena_center
	off.y = 0.0
	if off.length() > arena_radius and desired.dot(off) > 0.0:
		desired -= off.normalized() * desired.dot(off.normalized())
	velocity.x = desired.x
	velocity.z = desired.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - 30.0 * delta
	move_and_slide()
	var flat := Vector2(velocity.x, velocity.z).length()
	_walk_amt = move_toward(_walk_amt, clampf(flat / move_speed, 0.0, 1.3), delta * 4.0)
	_walk_phase += delta * flat * (1.1 if phase == 1 else 0.6)


func _turn_toward(p: Vector3, delta: float, factor: float) -> void:
	if factor <= 0.0:
		return
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	rotation.y = rotate_toward(rotation.y, atan2(-d.x, -d.z), deg_to_rad(200.0 if phase == 1 else 130.0) * factor * delta)


func _face_instant(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		rotation.y = atan2(-d.x, -d.z)


# =====================================================================
#  IA
# =====================================================================

func _think(delta: float) -> void:
	if not _valid_target():
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var d := _flat(target.global_position, global_position)
	var alive := _minions.size()
	var pick := ""
	if phase == 1:
		if _hidden:
			if alive <= 2 or _hide_t <= 0.0:
				_set_hidden(false)
			elif d < 4.5 and _escape_cd <= 0.0:
				pick = "escape"
			else:
				pick = _weighted({"frascos": 4, "laser": 3})
		if pick == "":
			if d < 3.8 and _close_t > 1.0 and _escape_cd <= 0.0:
				pick = "escape"
			elif _horde_cd <= 0.0 and alive < 4:
				pick = "horda"
			elif d < 3.8:
				pick = _weighted({"tubo": 5, "frascos": 1, "escape": 2 if _escape_cd <= 0.0 else 0})
			elif d < 10.0:
				pick = _weighted({"frascos": 4, "laser": 3, "invocar": 2 if _summon_cd <= 0.0 and alive < 6 else 0, "experimento": 2 if _experiment_cd <= 0.0 else 0})
			else:
				pick = _weighted({"laser": 4, "frascos": 3, "invocar": 2 if _summon_cd <= 0.0 and alive < 6 else 0, "experimento": 2 if _experiment_cd <= 0.0 else 0})
	else:
		if d < 4.8:
			pick = _weighted({"aplastar": 4, "agarre": 3 if _grab_cd <= 0.0 else 0, "barrido": 3})
		elif d < 12.0:
			pick = _weighted({"agarre": 3 if _grab_cd <= 0.0 else 0, "barril": 4, "rayo": 2, "aplastar": 1})
		else:
			pick = _weighted({"barril": 4, "rayo": 4, "horda": 1 if _horde_cd <= 0.0 and alive < 4 else 0})
	if pick == "":
		_cooldown = 0.3
		return
	if _last.size() >= 2 and _last[-1] == pick and _last[-2] == pick:
		_cooldown = 0.2
		_last.append("_")
		return
	_last.append(pick)
	if _last.size() > 4:
		_last.pop_front()
	state = State.BUSY
	_attack_id += 1
	var id := _attack_id
	match pick:
		"frascos": _atk_flasks(id)
		"laser": _atk_laser(id)
		"tubo": _atk_tube(id)
		"invocar": _atk_summon(id)
		"experimento": _atk_experiment(id)
		"horda": _atk_horde(id)
		"escape": _atk_escape(id)
		"barril": _atk_barrel(id)
		"agarre": _atk_grab(id)
		"aplastar": _atk_smash(id)
		"barrido": _atk_sweep(id)
		"rayo": _atk_beam(id)


func _weighted(options: Dictionary) -> String:
	var total := 0
	for k in options:
		total += int(options[k])
	if total <= 0:
		return ""
	var r := _rng.randi_range(0, total - 1)
	for k in options:
		r -= int(options[k])
		if r < 0:
			return k
	return ""


func _end(id: int, recovery: float) -> void:
	if id != _attack_id or state in [State.DEAD, State.TRANSITION]:
		return
	_kinematic = false
	_channeling = false
	state = State.FIGHT
	_cooldown = recovery * (0.8 if phase == 2 else 1.0)
	_tracking = 1.0
	_pose("guard", 0.4)


func _x(id: int) -> bool:
	return id != _attack_id or state in [State.DEAD, State.TRANSITION]


# =====================================================================
#  Fase 1
# =====================================================================

## Lanza 1–3 frascos de veneno en arco.
func _atk_flasks(id: int) -> void:
	var n := _rng.randi_range(1, 2)
	for i in n:
		_tracking = 1.0
		_pose("throw_wind", 0.25)
		await _w(0.4 if i == 0 else 0.25)
		if _x(id) or not _valid_target(): return
		_pose("throw", 0.12)
		var to := _in_arena(target.global_position + _lead(0.7) + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-1.2, 1.2)) * (0.0 if i == 0 else 1.0))
		_lob("frasco", (J["wr_r"] as Node3D).global_position, to, 0.85)
		await _w(0.3)
		if _x(id): return
	await _w(0.5)
	_end(id, 1.4)


## Ráfaga de la pistola láser.
func _atk_laser(id: int) -> void:
	_tracking = 1.0
	_pose("aim", 0.3)
	await _w(0.55)
	for i in 4:
		if _x(id) or not _valid_target(): return
		_shoot_bolt(8.0, 26.0, 1.0)
		await _w(0.2)
	await _w(0.5)
	_end(id, 1.3)


## Golpes con el tubo radiactivo.
func _atk_tube(id: int) -> void:
	for i in 2:
		_tracking = 1.0
		_pose("tube_wind", 0.28)
		await _w(0.45 if i == 0 else 0.3)
		if _x(id): return
		_tracking = 0.2
		_pose("tube_swing", 0.1)
		_lunge = -global_basis.z * 5.0
		await _w(0.1)
		if _x(id): return
		_melee(2.9, 0.2, 11.0, 5.0)
		LFX.puff(fx_parent, (J["wr_r"] as Node3D).global_position + (-global_basis.z) * 0.8, Color(0.6, 2.0, 0.4, 1), 12, 0.15, 3.0, 0.0)
		await _w(0.3)
	await _w(0.5)
	_end(id, 0.9)


## Invoca 3 mutantes pequeños sin dejar de trabajar.
func _atk_summon(id: int) -> void:
	_summon_cd = _rng.randf_range(14.0, 18.0)
	_tracking = 0.3
	_pose("summon", 0.35)
	await _w(0.5)
	if _x(id): return
	for i in 2:
		var a := _rng.randf() * TAU
		_spawn_minion(global_position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(2.5, 4.0))
		await _w(0.15)
	await _w(0.5)
	_end(id, 0.6)


## Experimenta en su mesa: si no lo interrumpes en 3.5 s, se cura.
func _atk_experiment(id: int) -> void:
	_experiment_cd = _rng.randf_range(18.0, 24.0)
	_kinematic = true
	_channeling = true
	_pose("experiment", 0.4)
	var heal := max_health * 0.03
	var t := 0.0
	while t < 3.5:
		await _w(0.25)
		if _x(id) or not _channeling:
			return
		t += 0.25
		LFX.puff(fx_parent, (J["wr_l"] as Node3D).global_position + Vector3(0, 0.2, 0), Color(0.5, 1.6, 0.3, 0.9), 6, 0.12, 1.2, 1.5)
	if _x(id) or not _channeling:
		return
	_channeling = false
	health = minf(max_health * (1.0 if phase == 1 else phase2_threshold), health + heal)
	health_changed.emit(health, max_health)
	_pose("laugh", 0.3)
	LFX.puff(fx_parent, global_position + Vector3(0, 1.5, 0), Color(0.6, 2.0, 0.4, 1), 30, 0.3, 3.0, 1.0)
	await _w(0.8)
	_end(id, 0.6)


## Bomba de humo, horda de 6+ mutantes y se esconde (casi invisible).
func _atk_horde(id: int) -> void:
	_horde_cd = _rng.randf_range(26.0, 32.0) * (1.4 if phase == 2 else 1.0)
	_tracking = 0.0
	_pose("summon", 0.3)
	_jitter = 0.4
	await _w(0.5)
	if _x(id): return
	_jitter = 0.0
	_smoke(global_position, 2.5)
	var n := _rng.randi_range(3, 4)
	var c := target.global_position if _valid_target() else global_position
	for i in n:
		if _minions.size() >= max_minions:
			break
		var a := TAU * i / n + _rng.randf_range(-0.3, 0.3)
		var mid := (c + global_position) * 0.5
		_spawn_minion(_in_arena(mid + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(2.5, 6.0)))
	if phase == 1:
		await _dash_away(id, 14.0)
		if _x(id): return
		_set_hidden(true)
		_hide_t = 8.0
	await _w(0.6)
	_end(id, 0.8)


## Escapa con un salto hacia atrás y humo; a veces deja un frasco de trampa.
func _atk_escape(id: int) -> void:
	_escape_cd = _rng.randf_range(6.0, 9.0)
	_close_t = 0.0
	if _rng.randf() < 0.5:
		_lob("frasco", global_position + Vector3(0, 1.2, 0), global_position, 0.3)
	await _dash_away(id, 9.0)
	if _x(id): return
	await _w(0.3)
	_end(id, 0.4)


func _dash_away(id: int, dist: float) -> void:
	_smoke(global_position, 1.6)
	var away := global_position - (target.global_position if _valid_target() else arena_center)
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	var best := global_position
	var best_score := -INF
	for k in 8:
		var dir := away.normalized().rotated(Vector3.UP, _rng.randf_range(-1.6, 1.6))
		var p := _in_arena(global_position + dir * dist)
		var score := _flat(p, target.global_position if _valid_target() else arena_center)
		if score > best_score:
			best_score = score
			best = p
	_pose("dash", 0.12)
	_kinematic = true
	var start := global_position
	var tw := create_tween()
	tw.tween_method(func(t: float): _dash_step(start, best, t), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	await _w(0.47)
	if _x(id): return
	_kinematic = false
	_smoke(global_position, 1.2)
	_face_instant(target.global_position if _valid_target() else arena_center)


func _dash_step(a: Vector3, b: Vector3, t: float) -> void:
	var p := a.lerp(b, t)
	p.y = a.y + sin(t * PI) * 1.6
	global_position = p


func _set_hidden(on: bool) -> void:
	if _hidden == on:
		return
	_hidden = on
	var tw := create_tween()
	for mi in _meshes:
		tw.parallel().tween_property(mi, "transparency", 0.82 if on else 0.0, 0.6)
	if not on:
		_smoke(global_position, 1.4)


# =====================================================================
#  Fase 2: el mutante
# =====================================================================

func _start_phase2() -> void:
	state = State.TRANSITION
	_attack_id += 1
	_channeling = false
	_kinematic = true
	_lunge = Vector3.ZERO
	_set_hidden(false)
	phase = 2
	# Se inyecta el suero en el cuello
	_pose("inject", 0.4)
	var syringe := Node3D.new()
	(J["wr_l"] as Node3D).add_child(syringe)
	syringe.position = Vector3(0, -0.18, 0)
	_cyl(syringe, 0.035, 0.28, Vector3(0, -0.1, 0), _glow(Color(0.4, 1.0, 0.2), 3.0), Vector3.ZERO, false)
	_cyl(syringe, 0.008, 0.16, Vector3(0, -0.3, 0), _mat(Color(0.8, 0.8, 0.85), 0.2, 0.9), Vector3.ZERO, false)
	await _w(1.0)
	_shake(0.3)
	LFX.puff(fx_parent, (J["head"] as Node3D).global_position, Color(0.5, 1.8, 0.3, 1), 30, 0.2, 3.0, 0.0)
	await _w(0.6)
	syringe.queue_free()
	# Convulsiones mientras crece
	_pose("convulse", 0.3)
	_jitter = 1.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(model, "scale", Vector3.ONE * 2.0, 2.8).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m_skin, "albedo_color", Color(0.52, 0.6, 0.46), 2.4)
	for i in 6:
		await _w(0.45)
		if state == State.DEAD: return
		_shake(0.35)
		LFX.puff(fx_parent, global_position + Vector3(0, 2.0 + i * 0.4, 0), Color(0.4, 1.5, 0.2, 0.9), 30, 0.4, 4.0, -3.0)
		if i == 2:
			for p in _mut_parts:
				p.visible = true
			for c in _coat:
				c.visible = false
			LFX.puff(fx_parent, global_position + Vector3(0, 2.5, 0), Color(0.95, 0.95, 0.95, 0.9), 30, 0.25, 4.0, -6.0)
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs:
		var cap := CapsuleShape3D.new()
		cap.radius = 1.2
		cap.height = 5.4
		cs.shape = cap
		cs.position = Vector3(0, 2.7, 0)
	_jitter = 0.0
	_pose("roar", 0.3)
	_set_eye(Color(0.5, 1.0, 0.2), 8.0)
	_shake(0.7)
	FX.shockwave(fx_parent, global_position, 10.0, Color(0.45, 1.0, 0.2), 0.7)
	_aoe(global_position, 4.5, 12.0, 30.0)
	move_speed = 3.0
	phase_changed.emit(2)
	await _w(1.3)
	if state == State.DEAD: return
	_pose("guard", 0.4)
	await _w(0.4)
	_kinematic = false
	state = State.FIGHT
	_cooldown = 0.6


## Barril de toxinas: explota en área grande y deja un charco.
func _atk_barrel(id: int) -> void:
	var n := 1 if _rng.randf() < 0.6 else 2
	for i in n:
		_tracking = 1.0
		_pose("barrel_wind", 0.35)
		await _w(0.6)
		if _x(id) or not _valid_target(): return
		_pose("barrel_throw", 0.15)
		var to := _in_arena(target.global_position + _lead(0.9))
		_lob("barril", (J["wr_r"] as Node3D).global_position + Vector3(0, 0.5, 0), to, 1.05)
		await _w(0.45)
		if _x(id): return
	await _w(0.6)
	_end(id, 1.0)


## Te agarra, te levanta y te estampa contra la pared.
func _atk_grab(id: int) -> void:
	_grab_cd = _rng.randf_range(8.0, 11.0)
	_tracking = 1.0
	_pose("grab_wind", 0.4)
	_flash_eye()
	await _w(0.7)
	if _x(id) or not _valid_target(): return
	_pose("grab_dash", 0.12)
	_tracking = 0.25
	var t := 0.0
	var caught := false
	while t < 0.6:
		await get_tree().physics_frame
		if _x(id): return
		t += get_physics_process_delta_time()
		var dir := target.global_position - global_position
		dir.y = 0.0
		_lunge = dir.normalized() * 13.0
		if _valid_target() and _flat(target.global_position, global_position) < 3.0:
			var invul: bool = "_iframes" in target and float(target.get("_iframes")) > 0.0
			if not invul:
				caught = true
				break
	_lunge = Vector3.ZERO
	if not caught:
		_pose("stagger", 0.3)
		await _w(1.0)
		_end(id, 0.6)
		return
	if target.has_method("apply_status"):
		target.apply_status("atrapado", 4.0)
	_kinematic = true
	_pose("hold", 0.2)
	_shake(0.3)
	# Lo levanta
	var hand: Node3D = J["wr_r"]
	var t2 := 0.0
	while t2 < 0.9:
		await get_tree().physics_frame
		if _x(id) or not _valid_target(): break
		t2 += get_physics_process_delta_time()
		target.global_position = hand.global_position + Vector3(0, -1.4, 0) + (-global_basis.z) * 0.4
		if "velocity" in target:
			target.set("velocity", Vector3.ZERO)
	if _x(id) or not _valid_target():
		if _valid_target() and target.has_method("clear_status"):
			target.clear_status("atrapado")
		return
	# Elige la pared: hacia donde mira, ligeramente a un lado
	var dir := (-global_basis.z).rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))
	dir.y = 0.0
	dir = dir.normalized()
	var from := target.global_position + Vector3(0, 0.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 45.0)
	var excl: Array[RID] = [get_rid()]
	if target is CollisionObject3D:
		excl.append((target as CollisionObject3D).get_rid())
	q.exclude = excl
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var wall: Vector3 = hit["position"] if not hit.is_empty() else from + dir * 18.0
	var land := wall - dir * 0.9
	land.y = global_position.y + 0.3
	_pose("throw", 0.15)
	_shake(0.3)
	var start := target.global_position
	var fly := 0.0
	var dur := clampf(start.distance_to(land) / 26.0, 0.2, 0.7)
	while fly < dur:
		await get_tree().physics_frame
		if not _valid_target(): break
		fly += get_physics_process_delta_time()
		var p := start.lerp(land, fly / dur)
		p.y += sin(fly / dur * PI) * 1.2
		target.global_position = p
	if _valid_target():
		if target.has_method("clear_status"):
			target.clear_status("atrapado")
		target.global_position = land
		_hit(18.0, wall, true)
		FX.burst(fx_parent, wall, false, 50, 1.6)
		FX.burst(fx_parent, wall, true, 30, 1.0)
		if target.has_method("add_camera_shake"):
			target.add_camera_shake(0.8)
	_kinematic = false
	await _w(1.0)
	_end(id, 1.0)


## Aplasta con el tubo: golpe de área.
func _atk_smash(id: int) -> void:
	_tracking = 1.0
	_pose("smash_wind", 0.45)
	await _w(0.8)
	if _x(id): return
	_tracking = 0.0
	_pose("smash", 0.12)
	await _w(0.12)
	if _x(id): return
	var p := global_position + (-global_basis.z) * 3.5
	p.y = global_position.y
	_aoe(p, 4.2, 20.0, 12.0)
	FX.shockwave(fx_parent, p, 4.2, Color(0.45, 1.0, 0.2), 0.45)
	FX.burst(fx_parent, p, false, 40, 1.6)
	LFX.puff(fx_parent, p + Vector3(0, 0.4, 0), Color(0.6, 2.0, 0.4, 1), 20, 0.3, 4.0, 1.0)
	_shake(0.5)
	await _w(1.0)
	_end(id, 1.0)


## Barrido amplio con el tubo gigante.
func _atk_sweep(id: int) -> void:
	_tracking = 1.0
	_pose("sweep_wind", 0.4)
	await _w(0.7)
	if _x(id): return
	_tracking = 0.0
	_pose("sweep", 0.15)
	await _w(0.12)
	if _x(id): return
	_melee(6.0, -0.4, 16.0, 8.0)
	FX.shockwave(fx_parent, global_position, 6.0, Color(0.45, 1.0, 0.2), 0.35)
	_shake(0.35)
	await _w(0.9)
	_end(id, 0.9)


## Rayo láser continuo que barre la sala.
func _atk_beam(id: int) -> void:
	_tracking = 1.0
	_pose("aim", 0.35)
	_flash_eye()
	var warn := LFX.streak(Color(0.5, 1.0, 0.3), 30.0, 0.08, 1.0)
	fx_parent.add_child(warn)
	var t := 0.0
	while t < 0.9:
		await get_tree().physics_frame
		if _x(id) or not is_instance_valid(warn):
			if is_instance_valid(warn): warn.queue_free()
			return
		t += get_physics_process_delta_time()
		warn.global_position = muzzle.global_position
		if _valid_target():
			warn.look_at(target.global_position + Vector3(0, 1.0, 0), Vector3.UP)
			warn.rotate_object_local(Vector3.UP, PI)
	warn.queue_free()
	if _x(id): return
	_tracking = 0.0
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.22
	cm.height = 1.0
	cm.radial_segments = 10
	cm.material = LFX.emissive(Color(0.55, 1.0, 0.3), 4.0, 0.85)
	beam.mesh = cm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_parent.add_child(beam)
	var aim0 := (target.global_position - global_position) if _valid_target() else -global_basis.z
	aim0.y = 0.0
	var base_yaw := atan2(-aim0.x, -aim0.z)
	var sweep := 0.7 * (1.0 if _rng.randf() < 0.5 else -1.0)
	# Inclinación para que el rayo pase a la altura del pecho del jugador
	var aim_d := maxf(4.0, aim0.length())
	var aim_y := (target.global_position.y + 1.0) if _valid_target() else global_position.y + 1.0
	var dur := 1.5
	var tick := 0.0
	t = 0.0
	while t < dur:
		await get_tree().physics_frame
		if _x(id): break
		var dt := get_physics_process_delta_time()
		t += dt
		rotation.y = base_yaw + lerpf(-sweep, sweep, t / dur)
		var from := muzzle.global_position
		var hz := -global_basis.z
		hz.y = 0.0
		var dir := (hz.normalized() * aim_d + Vector3(0, aim_y - from.y, 0)).normalized()
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 50.0)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var to: Vector3 = hit["position"] if not hit.is_empty() and hit["collider"] is StaticBody3D else from + dir * 50.0
		var length := from.distance_to(to)
		beam.global_position = (from + to) * 0.5
		beam.look_at(to, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
		beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		beam.scale = Vector3(1, length, 1)
		tick -= dt
		if tick <= 0.0:
			tick = 0.12
			LFX.puff(fx_parent, to, Color(1.0, 2.5, 0.6, 1), 6, 0.2, 2.5, 0.0)
		if _valid_target():
			var c := target.global_position + Vector3(0, 1.0, 0)
			var ap := c - from
			var along := clampf(ap.dot(dir), 0.0, length)
			if (from + dir * along).distance_to(c) < 1.0:
				_hit(9.0, from, false)
				if target.has_method("add_buildup"):
					target.add_buildup("veneno", 6.0)
	beam.queue_free()
	await _w(0.6)
	_end(id, 1.0)


# =====================================================================
#  Muerte
# =====================================================================

func _die() -> void:
	state = State.DEAD
	_attack_id += 1
	_kinematic = true
	_lunge = Vector3.ZERO
	_channeling = false
	_set_hidden(false)
	clear_minions()
	defeated.emit()
	_pose("kneel", 0.8)
	_jitter = 0.5
	LFX.puff(fx_parent, global_position + Vector3(0, 2.0, 0), Color(0.4, 1.3, 0.2, 0.9), 50, 0.5, 4.0, -2.0)
	await _w(1.6)
	_jitter = 0.0
	var tw := create_tween()
	tw.tween_property(model, "rotation_degrees:x", 82.0, 1.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(model, "position:y", 0.4, 1.3)
	tw.tween_method(func(v: float): m_eye.emission_energy_multiplier = v, 6.0, 0.0, 2.0)
	for p in _puddles:
		if is_instance_valid(p["node"]):
			(p["node"] as Node).queue_free()
	_puddles.clear()


# =====================================================================
#  Proyectiles, charcos, mutantes
# =====================================================================

## Lanza un frasco o un barril en arco; al caer explota y deja un charco.
func _lob(kind: String, from: Vector3, to: Vector3, t: float) -> void:
	var n := Node3D.new()
	fx_parent.add_child(n)
	n.global_position = from
	var big := kind == "barril"
	if big:
		_cyl(n, 0.45, 1.1, Vector3.ZERO, _mat(Color(0.85, 0.65, 0.1), 0.5, 0.4), Vector3.ZERO, false)
		_cyl(n, 0.47, 0.12, Vector3(0, 0.3, 0), _mat(Color(0.1, 0.1, 0.1), 0.6), Vector3.ZERO, false)
		_cyl(n, 0.47, 0.12, Vector3(0, -0.3, 0), _mat(Color(0.1, 0.1, 0.1), 0.6), Vector3.ZERO, false)
		_cyl(n, 0.3, 0.05, Vector3(0, 0.56, 0), m_poison, Vector3.ZERO, false)
	else:
		_cyl(n, 0.1, 0.22, Vector3.ZERO, _glass(), Vector3.ZERO, false)
		_cyl(n, 0.085, 0.16, Vector3(0, -0.02, 0), m_poison, Vector3.ZERO, false)
		_cyl(n, 0.035, 0.12, Vector3(0, 0.16, 0), _glass(), Vector3.ZERO, false)
	var ring := _warn(to, 4.5 if big else 2.6, Color(0.45, 1.0, 0.2), t)
	var spin := Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-4, 4), _rng.randf_range(-8, 8))
	var g := 14.0
	var tw := n.create_tween()
	tw.tween_method(func(k: float):
		var p := from.lerp(to, k)
		p.y = lerpf(from.y, to.y, k) + (g * t * t * 0.5) * k * (1.0 - k)
		n.global_position = p
		n.rotation = spin * k * t, 0.0, 1.0, t)
	tw.tween_callback(func():
		_free(ring)
		_land(kind, to)
		n.queue_free())


func _land(kind: String, p: Vector3) -> void:
	var big := kind == "barril"
	var r := 4.5 if big else 2.6
	FX.shockwave(fx_parent, p, r, Color(0.45, 1.0, 0.2), 0.4)
	LFX.puff(fx_parent, p + Vector3(0, 0.4, 0), Color(0.5, 1.6, 0.25, 0.9), 40 if big else 20, 0.5 if big else 0.3, 5.0, 1.5)
	if big:
		FX.burst(fx_parent, p, false, 40, 1.6)
		_shake(0.45)
	else:
		LFX.puff(fx_parent, p + Vector3(0, 0.2, 0), Color(1.4, 1.6, 1.5, 0.8), 12, 0.08, 3.0, -8.0)
	_aoe(p, r, 14.0 if big else 7.0, 20.0 if big else 10.0)
	_puddle(p, r * (0.85 if big else 0.75), 5.0 if big else 3.0)


func _puddle(p: Vector3, r: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.03
	cm.radial_segments = 24
	cm.material = m_puddle
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_parent.add_child(mi)
	mi.global_position = p + Vector3(0, 0.04, 0)
	mi.scale = Vector3(0.1, 1, 0.1)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(r, 1, r), 0.3)
	tw.tween_interval(dur - 1.0)
	tw.tween_property(mi, "scale", Vector3(0.05, 1, 0.05), 0.7)
	tw.tween_callback(mi.queue_free)
	_puddles.append({"node": mi, "pos": p, "r": r, "t": dur})


func _update_puddles(delta: float) -> void:
	if _puddles.is_empty():
		return
	_puddle_tick -= delta
	var tick := _puddle_tick <= 0.0
	if tick:
		_puddle_tick = 0.25
	for i in range(_puddles.size() - 1, -1, -1):
		var pd: Dictionary = _puddles[i]
		pd["t"] = float(pd["t"]) - delta
		if float(pd["t"]) <= 0.0:
			_puddles.remove_at(i)
			continue
		if tick:
			if _rng.randf() < 0.5:
				var a := _rng.randf() * TAU
				LFX.puff(fx_parent, (pd["pos"] as Vector3) + Vector3(cos(a), 0.1, sin(a)) * float(pd["r"]) * 0.6, Color(0.5, 1.4, 0.25, 0.7), 3, 0.12, 0.8, 1.0)
			if _valid_target():
				var to := target.global_position - (pd["pos"] as Vector3)
				if absf(to.y) < 1.0 and Vector2(to.x, to.z).length() < float(pd["r"]):
					if target.has_method("add_buildup"):
						target.add_buildup("veneno", 2.5)
					if "hp" in target and target.has_method("take_damage") and float(target.get("_iframes")) <= 0.0:
						target.set("hp", maxf(1.0, float(target.get("hp")) - 0.25))


func _spawn_minion(p: Vector3) -> void:
	if _minions.size() >= max_minions:
		return
	var e := ENEMY.new()
	e.type = "mutante_peq"
	e.target = target
	e.fx_parent = fx_parent
	e.wander_radius = 4.0
	e.place(_in_arena(p) + Vector3(0, 0.1, 0), _rng.randf() * TAU)
	(minion_parent if minion_parent else fx_parent).add_child(e)
	e._aggro()
	_minions.append(e)
	LFX.puff(fx_parent, p + Vector3(0, 0.4, 0), Color(0.5, 1.5, 0.25, 0.9), 20, 0.3, 3.0, 1.0)


func _shoot_bolt(dmg: float, speed: float, size: float) -> void:
	var from := muzzle.global_position
	var aim := target.global_position + Vector3(0, 1.0, 0) + _lead(from.distance_to(target.global_position) / speed)
	var b := BOLT.new()
	b.kind = "laser"
	b.target = target
	b.shooter = self
	b.damage = dmg * damage_multiplier
	b.size = size
	b.color = Color(0.45, 1.0, 0.25)
	b.velocity = (aim - from).normalized() * speed
	b.life = 2.5
	fx_parent.add_child(b)
	b.global_position = from
	LFX.puff(fx_parent, from, Color(1.0, 2.5, 0.6, 1), 6, 0.12, 2.0, 0.0)


func _smoke(p: Vector3, size: float) -> void:
	LFX.puff(fx_parent, p + Vector3(0, 1.0, 0), Color(0.55, 0.62, 0.5, 0.85), int(40 * size), 0.6 * size, 3.0, 0.5)
	LFX.puff(fx_parent, p + Vector3(0, 0.3, 0), Color(0.4, 1.0, 0.3, 0.6), int(14 * size), 0.4 * size, 2.0, 0.0)


# =====================================================================
#  Utilidades de combate
# =====================================================================

func _valid_target() -> bool:
	return target != null and is_instance_valid(target) and not ("is_dead" in target and target.is_dead)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _in_arena(p: Vector3) -> Vector3:
	var off := p - arena_center
	off.y = 0.0
	if off.length() > arena_radius:
		off = off.normalized() * arena_radius
	return Vector3(arena_center.x + off.x, arena_center.y, arena_center.z + off.z)


func _lead(t: float) -> Vector3:
	if _valid_target() and target is CharacterBody3D:
		var v := (target as CharacterBody3D).velocity
		return Vector3(v.x, 0, v.z) * t
	return Vector3.ZERO


func _hit(dmg: float, from: Vector3, ignore_iframes: bool) -> bool:
	if not _valid_target() or not target.has_method("take_damage"):
		return false
	if ignore_iframes and "_iframes" in target:
		target.set("_iframes", 0.0)
	var before: float = float(target.get("hp")) if "hp" in target else 0.0
	target.take_damage(dmg * damage_multiplier, from)
	return "hp" in target and float(target.get("hp")) < before


func _melee(reach: float, dot_min: float, dmg: float, poison: float) -> void:
	if not _valid_target():
		return
	var to := target.global_position - global_position
	if absf(to.y) > 3.0:
		return
	to.y = 0.0
	var fwd := -global_basis.z
	fwd.y = 0.0
	var r := reach * (1.0 if phase == 1 else 1.0)
	if to.length() < r and (to.length() < 1.2 or fwd.normalized().dot(to.normalized()) > dot_min):
		if _hit(dmg, global_position, false) and poison > 0.0 and target.has_method("add_buildup"):
			target.add_buildup("veneno", poison)
		_shake(0.25)


func _aoe(center: Vector3, radius: float, dmg: float, poison: float) -> void:
	if not _valid_target():
		return
	var to := target.global_position - center
	if absf(to.y) < 2.5 and Vector2(to.x, to.z).length() < radius:
		if _hit(dmg, center, false) and poison > 0.0 and target.has_method("add_buildup"):
			target.add_buildup("veneno", poison)


func _warn(pos: Vector3, radius: float, color: Color, time: float) -> MeshInstance3D:
	var ring := FX.ground_ring(fx_parent, pos, radius, color, 2.2)
	var m: ShaderMaterial = ring.material_override
	var tw := ring.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("progress", v), 0.0, 1.0, time)
	tw.tween_interval(1.5)
	tw.tween_callback(ring.queue_free)
	return ring


func _free(n: Variant) -> void:
	if is_instance_valid(n) and n is Node:
		(n as Node).queue_free()


func _flash_eye() -> void:
	m_eye.emission_energy_multiplier = 10.0
	var tw := create_tween()
	tw.tween_property(m_eye, "emission_energy_multiplier", 4.0, 0.4)


func _set_eye(c: Color, energy: float) -> void:
	m_eye.albedo_color = c
	m_eye.emission = c
	m_eye.emission_energy_multiplier = energy


func _shake(a: float) -> void:
	if _valid_target() and target.has_method("add_camera_shake"):
		target.add_camera_shake(a)


func _w(t: float) -> Signal:
	return get_tree().create_timer(t, false, true).timeout


# =====================================================================
#  Modelo
# =====================================================================

func _mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.95, 0.85, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	return m


var _bm: BoxMesh
var _sm: SphereMesh
var _cm: CylinderMesh
var _km: CylinderMesh


func _box(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO, track := true) -> MeshInstance3D:
	return _add(p, _bm, size, pos, m, rot, track)


func _sph(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO, track := true) -> MeshInstance3D:
	return _add(p, _sm, size, pos, m, rot, track)


func _cyl(p: Node3D, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO, track := true) -> MeshInstance3D:
	return _add(p, _cm, Vector3(r * 2.0, h, r * 2.0), pos, m, rot, track)


func _cone(p: Node3D, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO, track := true) -> MeshInstance3D:
	return _add(p, _km, Vector3(r * 2.0, h, r * 2.0), pos, m, rot, track)


func _add(p: Node3D, mesh: Mesh, size: Vector3, pos: Vector3, m: Material, rot: Vector3, track: bool) -> MeshInstance3D:
	if _bm == null:
		_make_meshes()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = size
	p.add_child(mi)
	if track:
		_meshes.append(mi)
	return mi


func _make_meshes() -> void:
	_bm = BoxMesh.new()
	_sm = SphereMesh.new()
	_sm.radius = 0.5
	_sm.height = 1.0
	_sm.radial_segments = 16
	_sm.rings = 8
	_cm = CylinderMesh.new()
	_cm.top_radius = 0.5
	_cm.bottom_radius = 0.5
	_cm.height = 1.0
	_cm.radial_segments = 12
	_cm.rings = 1
	_km = CylinderMesh.new()
	_km.top_radius = 0.0
	_km.bottom_radius = 0.5
	_km.height = 1.0
	_km.radial_segments = 8
	_km.rings = 1


func _joint(parent: Node3D, key: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = key
	j.position = pos
	parent.add_child(j)
	J[key] = j
	return j


## Parte que solo aparece al mutar.
func _mut(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.visible = false
	parent.add_child(n)
	_mut_parts.append(n)
	return n


func _build_model() -> void:
	_make_meshes()
	m_skin = _mat(Color(0.83, 0.68, 0.6), 0.6)
	var scar := _mat(Color(0.62, 0.32, 0.32), 0.7)
	var hair := _mat(Color(0.93, 0.93, 0.9), 0.55)
	var suit := _mat(Color(0.06, 0.06, 0.07), 0.5)
	var trim := _mat(Color(0.82, 0.82, 0.84), 0.45)
	var coat := _mat(Color(0.9, 0.9, 0.87), 0.8)
	var boots := _mat(Color(0.12, 0.11, 0.1), 0.5)
	var metal := _mat(Color(0.5, 0.52, 0.55), 0.3, 0.85)
	var dark := _mat(Color(0.12, 0.12, 0.13), 0.4, 0.7)
	var bone := _mat(Color(0.88, 0.85, 0.72), 0.5)
	m_eye = _glow(Color(0.85, 0.95, 0.85), 2.0)
	m_tube = _glow(Color(0.4, 1.0, 0.2), 2.5)
	m_poison = _glow(Color(0.4, 1.0, 0.15), 2.0)
	m_puddle = _glow(Color(0.3, 0.8, 0.12), 1.2)
	m_puddle.albedo_color = Color(0.25, 0.6, 0.1, 0.75)
	m_puddle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_puddle.roughness = 0.05
	var pus := _glow(Color(0.5, 1.0, 0.2), 2.2)
	m_flash = StandardMaterial3D.new()
	m_flash.albedo_color = Color(1, 1, 1, 0.35)
	m_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_flash.emission_enabled = true
	m_flash.emission = Color(0.9, 1.0, 0.85)

	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var pelvis := _joint(model, "pelvis", Vector3(0, 1.28, 0))
	_box(pelvis, Vector3(0.62, 0.32, 0.4), Vector3.ZERO, suit)
	_box(pelvis, Vector3(0.64, 0.07, 0.42), Vector3(0, 0.12, 0), trim)
	var spine := _joint(pelvis, "spine", Vector3(0, 0.16, 0))
	_box(spine, Vector3(0.62, 0.42, 0.42), Vector3(0, 0.2, 0), suit)
	var chest := _joint(spine, "chest", Vector3(0, 0.4, 0))
	# Pecho enorme, hombros anchos (estilo Conquest)
	_box(chest, Vector3(0.98, 0.6, 0.55), Vector3(0, 0.28, 0), suit)
	_sph(chest, Vector3(0.48, 0.38, 0.3), Vector3(-0.22, 0.32, -0.16), suit)
	_sph(chest, Vector3(0.48, 0.38, 0.3), Vector3(0.22, 0.32, -0.16), suit)
	_box(chest, Vector3(0.2, 0.62, 0.02), Vector3(0, 0.3, -0.29), trim)
	_sph(chest, Vector3(0.62, 0.32, 0.5), Vector3(0, 0.62, 0.02), suit)
	# Bata de laboratorio rota
	for sx: float in [-1.0, 1.0]:
		var panel := Node3D.new()
		chest.add_child(panel)
		_box(panel, Vector3(0.36, 1.25, 0.04), Vector3(sx * 0.36, -0.3, -0.29), coat, Vector3(0, 0, sx * -3))
		_box(panel, Vector3(0.06, 1.2, 0.5), Vector3(sx * 0.52, -0.28, 0.0), coat)
		_coat.append(panel)
	var back := Node3D.new()
	chest.add_child(back)
	_box(back, Vector3(1.0, 1.4, 0.04), Vector3(0, -0.25, 0.3), coat)
	for k in 4:
		_box(back, Vector3(0.18, 0.25, 0.04), Vector3(-0.35 + k * 0.23, -1.05, 0.3), coat, Vector3(0, 0, _rng.randf_range(-20, 20)))
	_coat.append(back)
	var neck := _joint(chest, "neck", Vector3(0, 0.66, 0))
	_cyl(neck, 0.17, 0.24, Vector3(0, 0.1, 0), m_skin)
	var head := _joint(neck, "head", Vector3(0, 0.22, 0))
	_box(head, Vector3(0.36, 0.4, 0.4), Vector3(0, 0.2, 0), m_skin)
	_box(head, Vector3(0.38, 0.14, 0.3), Vector3(0, 0.05, -0.06), m_skin)   # mandíbula cuadrada
	_box(head, Vector3(0.38, 0.06, 0.08), Vector3(0, 0.3, -0.19), m_skin)  # ceño
	# Cicatrices
	_box(head, Vector3(0.03, 0.34, 0.02), Vector3(-0.08, 0.2, -0.205), scar, Vector3(0, 0, 18))
	_box(head, Vector3(0.18, 0.025, 0.02), Vector3(0.06, 0.12, -0.205), scar, Vector3(0, 0, -12))
	_box(head, Vector3(0.025, 0.2, 0.02), Vector3(0.12, 0.3, -0.205), scar, Vector3(0, 0, -25))
	_box(head, Vector3(0.12, 0.02, 0.02), Vector3(-0.1, 0.06, -0.21), scar)
	# Ojos: uno normal, otro muerto/brillante
	_box(head, Vector3(0.07, 0.03, 0.02), Vector3(0.085, 0.25, -0.205), _mat(Color(0.12, 0.15, 0.2), 0.3))
	_box(head, Vector3(0.08, 0.035, 0.02), Vector3(-0.085, 0.25, -0.206), m_eye)
	_box(head, Vector3(0.05, 0.08, 0.06), Vector3(0, 0.2, -0.22), m_skin)    # nariz
	_box(head, Vector3(0.14, 0.02, 0.02), Vector3(0, 0.09, -0.21), _mat(Color(0.35, 0.2, 0.2), 0.6))
	# Pelo blanco peinado hacia atrás y bigote/barba corta
	_box(head, Vector3(0.4, 0.12, 0.44), Vector3(0, 0.42, 0.03), hair)
	_box(head, Vector3(0.36, 0.3, 0.14), Vector3(0, 0.3, 0.22), hair, Vector3(-15, 0, 0))
	_box(head, Vector3(0.3, 0.22, 0.1), Vector3(0, 0.08, 0.26), hair, Vector3(-25, 0, 0))
	for sx: float in [-1.0, 1.0]:
		_box(head, Vector3(0.04, 0.22, 0.32), Vector3(sx * 0.2, 0.28, 0.06), hair)
	_box(head, Vector3(0.22, 0.04, 0.03), Vector3(0, 0.12, -0.215), hair)
	# Brazos gruesos
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var sh := _joint(chest, "sh_" + side, Vector3(sx * 0.6, 0.48, 0))
		_sph(sh, Vector3(0.42, 0.38, 0.42), Vector3.ZERO, suit)
		_sph(sh, Vector3(0.24, 0.6, 0.26), Vector3(0, -0.3, 0), suit)
		_coat.append(_box(sh, Vector3(0.28, 0.5, 0.28), Vector3(0, -0.3, 0), coat))
		var el := _joint(sh, "el_" + side, Vector3(0, -0.6, 0))
		_sph(el, Vector3(0.22, 0.56, 0.24), Vector3(0, -0.27, 0), m_skin)
		_coat.append(_box(el, Vector3(0.25, 0.22, 0.26), Vector3(0, -0.05, 0), coat))
		var wr := _joint(el, "wr_" + side, Vector3(0, -0.56, 0))
		_box(wr, Vector3(0.17, 0.2, 0.19), Vector3(0, -0.09, 0), m_skin)
	# Tubo radiactivo (mano derecha) y pistola láser (izquierda)
	var tube := Node3D.new()
	(J["wr_r"] as Node3D).add_child(tube)
	tube.position = Vector3(0, -0.16, 0)
	_cyl(tube, 0.07, 1.3, Vector3(0, -0.55, 0), m_tube)
	_cyl(tube, 0.1, 0.16, Vector3(0, -0.02, 0), metal)
	_cyl(tube, 0.1, 0.16, Vector3(0, -1.18, 0), metal)
	for k in 3:
		_cyl(tube, 0.085, 0.04, Vector3(0, -0.3 - k * 0.3, 0), dark)
	var gun := Node3D.new()
	(J["wr_l"] as Node3D).add_child(gun)
	gun.position = Vector3(0, -0.15, 0)
	_box(gun, Vector3(0.12, 0.36, 0.17), Vector3(0, -0.12, 0), dark)
	_box(gun, Vector3(0.08, 0.14, 0.2), Vector3(0, 0.0, 0.12), dark)
	_cyl(gun, 0.04, 0.26, Vector3(0, -0.4, 0), metal)
	_cyl(gun, 0.03, 0.03, Vector3(0, -0.54, 0), m_poison)
	muzzle = Node3D.new()
	gun.add_child(muzzle)
	muzzle.position = Vector3(0, -0.58, 0)
	# Piernas
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var hip := _joint(pelvis, "hip_" + side, Vector3(sx * 0.2, -0.08, 0))
		_sph(hip, Vector3(0.3, 0.68, 0.32), Vector3(0, -0.3, 0), suit)
		var kn := _joint(hip, "kn_" + side, Vector3(0, -0.6, 0))
		_box(kn, Vector3(0.22, 0.58, 0.24), Vector3(0, -0.28, 0), suit)
		_box(kn, Vector3(0.24, 0.2, 0.26), Vector3(0, -0.45, 0), boots)
		var an := _joint(kn, "an_" + side, Vector3(0, -0.58, 0))
		_box(an, Vector3(0.24, 0.12, 0.42), Vector3(0, -0.04, -0.08), boots)
	# Partes de la mutación (ocultas hasta la fase 2)
	var mback := _mut(chest, Vector3(0, 0.3, 0.3))
	for k in 6:
		_cone(mback, 0.06, 0.32, Vector3(_rng.randf_range(-0.3, 0.3), -0.2 + k * 0.12, 0.05), bone, Vector3(-60, 0, _rng.randf_range(-25, 25)))
	for k in 7:
		_sph(mback, Vector3.ONE * _rng.randf_range(0.1, 0.2), Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.3, 0.4), 0.02), pus)
	var mshoulder := _mut(J["sh_l"], Vector3(-0.05, 0.12, 0))
	_sph(mshoulder, Vector3(0.5, 0.42, 0.48), Vector3.ZERO, m_skin)
	for k in 4:
		_sph(mshoulder, Vector3.ONE * 0.12, Vector3(_rng.randf_range(-0.2, 0.2), 0.15, _rng.randf_range(-0.2, 0.2)), pus)
	var marm := _mut(J["el_r"], Vector3(0, -0.25, 0))
	_sph(marm, Vector3(0.38, 0.62, 0.38), Vector3.ZERO, m_skin)
	_sph(marm, Vector3.ONE * 0.13, Vector3(0.12, 0.05, -0.15), pus)
	var mclaw := _mut(J["wr_l"], Vector3(0, -0.15, 0))
	for k in 3:
		_cone(mclaw, 0.025, 0.22, Vector3(-0.05 + k * 0.05, -0.12, -0.1), bone, Vector3(160, 0, 0))
	var mface := _mut(J["head"], Vector3(0, 0.2, -0.2))
	for k in 3:
		_sph(mface, Vector3.ONE * 0.06, Vector3(_rng.randf_range(-0.14, 0.14), _rng.randf_range(-0.1, 0.12), 0.0), pus)
	# Carne que revienta el traje por delante
	var mchest := _mut(chest, Vector3(0, 0.3, -0.26))
	for k in 5:
		_sph(mchest, Vector3(_rng.randf_range(0.18, 0.3), _rng.randf_range(0.16, 0.26), 0.14), Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.2, 0.25), -0.02), m_skin)
	for k in 8:
		_sph(mchest, Vector3.ONE * _rng.randf_range(0.06, 0.12), Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.25, 0.3), -0.08), pus)
	var mabs := _mut(spine, Vector3(0, 0.2, -0.22))
	for k in 4:
		_sph(mabs, Vector3.ONE * _rng.randf_range(0.07, 0.11), Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.15, 0.15), -0.02), pus)
	# Espinas de hueso en los hombros
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var ms := _mut(J["sh_" + side], Vector3(0, 0.15, 0))
		for k in 3:
			_cone(ms, 0.05, 0.38 - k * 0.06, Vector3(sx * (0.05 + k * 0.06), 0.12, -0.08 + k * 0.08), bone, Vector3(-15 + k * 15, 0, sx * -(20 + k * 12)))
	# Antebrazo izquierdo deforme y venas brillantes en el derecho
	var mfore := _mut(J["el_l"], Vector3(0, -0.3, 0))
	_sph(mfore, Vector3(0.34, 0.5, 0.34), Vector3.ZERO, m_skin)
	_sph(mfore, Vector3.ONE * 0.1, Vector3(-0.12, 0.05, -0.1), pus)
	var mvein := _mut(J["el_r"], Vector3(0, -0.25, 0))
	for k in 3:
		_box(mvein, Vector3(0.03, 0.42, 0.03), Vector3(-0.1 + k * 0.1, 0.0, -0.19), pus, Vector3(0, 0, _rng.randf_range(-12, 12)))
	# Tumor en la cabeza y mandíbula desencajada
	var mhead := _mut(J["head"], Vector3(0.12, 0.42, 0.05))
	_sph(mhead, Vector3(0.26, 0.2, 0.26), Vector3.ZERO, m_skin)
	_sph(mhead, Vector3.ONE * 0.07, Vector3(0.06, 0.06, -0.08), pus)
	var mjaw := _mut(J["head"], Vector3(0, -0.04, -0.12))
	_box(mjaw, Vector3(0.34, 0.1, 0.24), Vector3.ZERO, m_skin, Vector3(15, 0, 0))
	for k in 5:
		_cone(mjaw, 0.018, 0.08, Vector3(-0.12 + k * 0.06, 0.06, -0.12), bone)
	for mi in _meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# =====================================================================
#  Poses
# =====================================================================

func _P(d: Dictionary) -> Dictionary:
	var keys := ["spine", "chest", "neck", "head", "sh_l", "el_l", "wr_l", "sh_r", "el_r", "wr_r", "hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]
	var out := {"root_y": float(d.get("root_y", 0.0))}
	for k in keys:
		out[k] = d.get(k, Vector3.ZERO)
	return out


func _define_poses() -> void:
	poses["idle"] = _P({"chest": Vector3(-4, 0, 0), "sh_l": Vector3(8, 0, -14), "sh_r": Vector3(8, 0, 14), "el_l": Vector3(15, 0, 0), "el_r": Vector3(15, 0, 0)})
	poses["guard"] = _P({"root_y": -0.06, "chest": Vector3(-10, -12, 0), "head": Vector3(6, 12, 0), "sh_l": Vector3(70, 0, -10), "el_l": Vector3(20, 0, 0), "sh_r": Vector3(30, 0, 20), "el_r": Vector3(50, 0, 0), "wr_r": Vector3(40, 0, 0), "hip_l": Vector3(14, 0, 0), "kn_l": Vector3(-18, 0, 0), "kn_r": Vector3(-14, 0, 0), "hip_r": Vector3(-4, 0, 0)})
	poses["experiment"] = _P({"chest": Vector3(-28, 0, 0), "neck": Vector3(-10, 0, 0), "head": Vector3(-25, 0, 0), "sh_l": Vector3(55, 0, 15), "el_l": Vector3(70, 0, 0), "sh_r": Vector3(45, 0, -10), "el_r": Vector3(80, 0, 0), "kn_l": Vector3(-8, 0, 0), "kn_r": Vector3(-8, 0, 0)})
	poses["laugh"] = _P({"chest": Vector3(18, 0, 0), "head": Vector3(30, 0, 0), "sh_l": Vector3(30, 0, -60), "sh_r": Vector3(30, 0, 60), "el_l": Vector3(60, 0, 0), "el_r": Vector3(60, 0, 0)})
	poses["throw_wind"] = _P({"chest": Vector3(8, 35, 0), "sh_r": Vector3(-60, 0, 40), "el_r": Vector3(80, 0, 0), "sh_l": Vector3(50, 0, -20), "hip_l": Vector3(20, 0, 0), "kn_l": Vector3(-20, 0, 0)})
	poses["throw"] = _P({"chest": Vector3(-20, -30, 0), "sh_r": Vector3(130, 0, 10), "el_r": Vector3(10, 0, 0), "sh_l": Vector3(-20, 0, -30), "hip_l": Vector3(25, 0, 0), "kn_l": Vector3(-25, 0, 0)})
	poses["aim"] = _P({"chest": Vector3(-4, 20, 0), "head": Vector3(0, -10, 0), "sh_l": Vector3(90, 0, 10), "el_l": Vector3(0, 0, 0), "wr_l": Vector3(0, 0, 0), "sh_r": Vector3(20, 0, 25), "el_r": Vector3(40, 0, 0), "kn_l": Vector3(-10, 0, 0), "kn_r": Vector3(-10, 0, 0)})
	poses["tube_wind"] = _P({"chest": Vector3(5, -40, 0), "sh_r": Vector3(150, 0, 45), "el_r": Vector3(40, 0, 0), "sh_l": Vector3(40, 0, -30), "kn_l": Vector3(-20, 0, 0), "kn_r": Vector3(-20, 0, 0)})
	poses["tube_swing"] = _P({"root_y": -0.1, "chest": Vector3(-22, 40, 0), "sh_r": Vector3(50, 0, -35), "el_r": Vector3(5, 0, 0), "wr_r": Vector3(40, 0, 0), "sh_l": Vector3(20, 0, -40), "hip_r": Vector3(30, 0, 0), "kn_r": Vector3(-30, 0, 0)})
	poses["summon"] = _P({"chest": Vector3(14, 0, 0), "head": Vector3(15, 0, 0), "sh_l": Vector3(150, 0, -30), "el_l": Vector3(20, 0, 0), "sh_r": Vector3(150, 0, 30), "el_r": Vector3(20, 0, 0)})
	poses["dash"] = _P({"root_y": -0.2, "chest": Vector3(20, 0, 0), "sh_l": Vector3(-40, 0, -30), "sh_r": Vector3(-40, 0, 30), "hip_l": Vector3(60, 0, 0), "kn_l": Vector3(-80, 0, 0), "hip_r": Vector3(40, 0, 0), "kn_r": Vector3(-90, 0, 0)})
	poses["stagger"] = _P({"chest": Vector3(18, 0, 10), "head": Vector3(20, 0, 0), "sh_l": Vector3(-20, 0, -40), "sh_r": Vector3(-10, 0, 40), "hip_l": Vector3(-15, 0, 0), "kn_r": Vector3(-30, 0, 0)})
	poses["inject"] = _P({"chest": Vector3(-6, -15, 0), "head": Vector3(10, -30, 15), "sh_l": Vector3(120, 0, 40), "el_l": Vector3(115, 0, 0), "wr_l": Vector3(-40, 0, 0), "sh_r": Vector3(20, 0, 20), "el_r": Vector3(30, 0, 0)})
	poses["convulse"] = _P({"root_y": -0.2, "chest": Vector3(-30, 0, 0), "head": Vector3(-30, 0, 0), "sh_l": Vector3(40, 0, -70), "el_l": Vector3(90, 0, 0), "sh_r": Vector3(40, 0, 70), "el_r": Vector3(90, 0, 0), "kn_l": Vector3(-35, 0, 0), "kn_r": Vector3(-35, 0, 0), "hip_l": Vector3(20, 0, 0), "hip_r": Vector3(20, 0, 0)})
	poses["roar"] = _P({"chest": Vector3(20, 0, 0), "head": Vector3(30, 0, 0), "sh_l": Vector3(30, 0, -95), "sh_r": Vector3(30, 0, 95), "el_l": Vector3(40, 0, 0), "el_r": Vector3(40, 0, 0), "kn_l": Vector3(-15, 0, 0), "kn_r": Vector3(-15, 0, 0)})
	poses["barrel_wind"] = _P({"chest": Vector3(15, 25, 0), "sh_r": Vector3(170, 0, 20), "el_r": Vector3(50, 0, 0), "sh_l": Vector3(160, 0, -20), "el_l": Vector3(50, 0, 0), "kn_l": Vector3(-20, 0, 0), "kn_r": Vector3(-20, 0, 0)})
	poses["barrel_throw"] = _P({"chest": Vector3(-25, -10, 0), "sh_r": Vector3(100, 0, 10), "el_r": Vector3(5, 0, 0), "sh_l": Vector3(95, 0, -10), "el_l": Vector3(5, 0, 0), "hip_l": Vector3(30, 0, 0), "kn_l": Vector3(-30, 0, 0)})
	poses["grab_wind"] = _P({"root_y": -0.2, "chest": Vector3(-25, 0, 0), "head": Vector3(25, 0, 0), "sh_l": Vector3(60, 0, -70), "sh_r": Vector3(60, 0, 70), "el_l": Vector3(40, 0, 0), "el_r": Vector3(40, 0, 0), "hip_l": Vector3(40, 0, 0), "kn_l": Vector3(-60, 0, 0), "hip_r": Vector3(30, 0, 0), "kn_r": Vector3(-50, 0, 0)})
	poses["grab_dash"] = _P({"chest": Vector3(-40, 0, 0), "head": Vector3(30, 0, 0), "sh_l": Vector3(95, 0, -15), "sh_r": Vector3(95, 0, 15), "hip_l": Vector3(45, 0, 0), "kn_l": Vector3(-25, 0, 0), "hip_r": Vector3(-30, 0, 0), "kn_r": Vector3(-50, 0, 0)})
	poses["hold"] = _P({"chest": Vector3(10, 0, 0), "head": Vector3(10, 0, 0), "sh_r": Vector3(165, 0, 10), "el_r": Vector3(10, 0, 0), "sh_l": Vector3(40, 0, -40), "el_l": Vector3(50, 0, 0)})
	poses["smash_wind"] = _P({"chest": Vector3(18, 0, 0), "head": Vector3(10, 0, 0), "sh_r": Vector3(175, 0, 5), "el_r": Vector3(25, 0, 0), "sh_l": Vector3(150, 0, -10), "el_l": Vector3(40, 0, 0), "hip_l": Vector3(20, 0, 0), "kn_l": Vector3(-20, 0, 0)})
	poses["smash"] = _P({"root_y": -0.25, "chest": Vector3(-38, 0, 0), "head": Vector3(25, 0, 0), "sh_r": Vector3(60, 0, 5), "el_r": Vector3(0, 0, 0), "wr_r": Vector3(25, 0, 0), "sh_l": Vector3(55, 0, -5), "hip_l": Vector3(45, 0, 0), "kn_l": Vector3(-55, 0, 0), "hip_r": Vector3(-20, 0, 0), "kn_r": Vector3(-35, 0, 0)})
	poses["sweep_wind"] = _P({"root_y": -0.15, "chest": Vector3(0, -70, 0), "sh_r": Vector3(90, 0, 80), "el_r": Vector3(10, 0, 0), "wr_r": Vector3(50, 0, 0), "sh_l": Vector3(40, 0, -30), "kn_l": Vector3(-25, 0, 0), "kn_r": Vector3(-25, 0, 0)})
	poses["sweep"] = _P({"root_y": -0.15, "chest": Vector3(-10, 70, 0), "sh_r": Vector3(90, 0, -50), "el_r": Vector3(0, 0, 0), "wr_r": Vector3(60, 0, 0), "sh_l": Vector3(30, 0, -40), "hip_r": Vector3(25, 0, 0), "kn_r": Vector3(-30, 0, 0)})
	poses["kneel"] = _P({"root_y": -0.55, "chest": Vector3(-30, 0, 0), "head": Vector3(-30, 0, 0), "sh_l": Vector3(30, 0, -10), "sh_r": Vector3(30, 0, 10), "el_l": Vector3(30, 0, 0), "el_r": Vector3(30, 0, 0), "hip_l": Vector3(85, 0, 0), "kn_l": Vector3(-95, 0, 0), "hip_r": Vector3(-10, 0, 0), "kn_r": Vector3(-115, 0, 0)})


func _pose(name: String, dur: float) -> void:
	if not poses.has(name):
		return
	_from = _cur.duplicate()
	_to = poses[name]
	_pose_t = 0.0
	_pose_dur = maxf(dur, 0.01)


func _update_pose(delta: float) -> void:
	_pose_t = minf(1.0, _pose_t + delta / _pose_dur)
	var k := smoothstep(0.0, 1.0, _pose_t)
	for key in _to:
		if key == "root_y":
			_cur[key] = lerpf(float(_from.get(key, 0.0)), float(_to[key]), k)
		else:
			_cur[key] = (_from.get(key, Vector3.ZERO) as Vector3).lerp(_to[key], k)
	var w := _walk_amt
	var sw := sin(_walk_phase * 3.0)
	for key in _cur:
		if key == "root_y":
			continue
		var r: Vector3 = _cur[key]
		match key:
			"hip_l": r.x += sw * 26.0 * w
			"hip_r": r.x -= sw * 26.0 * w
			"kn_l": r.x -= maxf(0.0, -sw) * 38.0 * w
			"kn_r": r.x -= maxf(0.0, sw) * 38.0 * w
			"sh_l": r.x -= sw * 14.0 * w
			"sh_r": r.x += sw * 14.0 * w
		if _jitter > 0.0 and key in ["head", "chest", "sh_l", "sh_r", "spine"]:
			r += Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)) * _jitter
		(J[key] as Node3D).rotation_degrees = r
	(J["pelvis"] as Node3D).position.y = 1.28 + float(_cur.get("root_y", 0.0)) + absf(sin(_walk_phase * 3.0)) * 0.05 * w
