extends CharacterBody3D
## Jefe final: "El Rector Eterno, Sínodo de la Última Tesis" (Aula Magna).
## Pelón, con barba de candado y túnica académica. Antes de pelear habla con el
## jugador (lo maneja final_fight.gd). Si la pelea empieza:
##
##   Fase 1: desenfunda la espada con una sola mano y pelea de forma desesperada
##           y con mucha destreza: combos rápidos, estocadas, giros, esquiva tus
##           golpes y contraataca; hechizos de área (nova, círculos, anillo de
##           fuego) y, si te alejas, saca un pequeño revólver y te dispara.
##   Fase 2: se le vuelve a llenar la vida, se quita la túnica y su espada brilla
##           en rojo: cortes de fuego y de electricidad (ondas), lluvia de flechas,
##           código que compila espadas espectrales o hechizos, invoca 1–2 IAs
##           holográficas y manipula el espacio: se teletransporta a tu espalda y
##           te jala hacia su espada para acertar.
## Al morir suelta la tesis (el controlador la crea).

signal health_changed(current: float, maximum: float)
signal damaged(amount: float)
signal battle_started
signal phase_changed(phase: int)
signal defeated
## Frases que dice durante la pelea (el controlador las muestra como subtítulos).
signal said(text: String, time: float)

const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const FX := preload("res://boss_profesor/boss_fx.gd")
const BOSS_SKIN := preload("res://boss_profesor/boss_skin.gd")
## Modelos de Blender (arte/blender/jefe_rector.py): con toga (fase 1) y sin ella (fase 2).
## Si no existen se usan las primitivas.
const SKIN_PATH := "res://modelos/jefes/rector.glb"
const SKIN_F2_PATH := "res://modelos/jefes/rector_sin_toga.glb"
const BOLT := preload("res://mundo/enemy_bolt.gd")
const ENEMY := preload("res://mundo/enemy.gd")

enum State { DORMANT, TALK, INTRO, FIGHT, BUSY, TRANSITION, DEAD }

@export var boss_name: String = "El Rector Eterno, Sínodo de la Última Tesis"
@export var max_health: float = 1600.0
@export var damage_multiplier: float = 1.0
@export var move_speed: float = 4.6
@export_range(0.0, 1.0) var electrocute_chance: float = 0.25

var state: int = State.DORMANT
var phase := 1
var health := 0.0
var target: Node3D
var fx_parent: Node
var minion_parent: Node
var arena_center := Vector3.ZERO
var arena_radius := 27.0

# Modelo
var model: Node3D
var J := {}
var _meshes: Array[MeshInstance3D] = []
var _robe: Array[Node3D] = []
var _skin: Node
var _skin2: Node
var m_skin: StandardMaterial3D
var m_blade: StandardMaterial3D
var m_eye: StandardMaterial3D
var m_flash: StandardMaterial3D
var m_holo: StandardMaterial3D
var m_circuit: StandardMaterial3D
var sword_hand: Node3D
var sword_sheathed: Node3D
var revolver_hand: Node3D
var revolver_holster: Node3D
var muzzle: Node3D
var _blade_light: OmniLight3D

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

# IA
var _rng := RandomNumberGenerator.new()
var _attack_id := 0
var _cooldown := 1.0
var _tracking := 1.0
var _lunge := Vector3.ZERO
var _kinematic := false
var _flash := 0.0
var _last: Array[String] = []
var _dodge_cd := 2.0
var _gun_cd := 2.0
var _spell_cd := 4.0
var _ai_cd := 6.0
var _code_cd := 5.0
var _warp_cd := 4.0
var _ais: Array = []
var _walk_target := Vector3.INF

const CODE_LINES := ["defensa_final.run()", "if jugador.digno: pelear()", "espada.afilar(∞)", "import catedra", "tesis.capitulo = 1", "while residencia: luchar()", "sudo reprobar --todos", "arma = EspadaRoja.new()"]


func _ready() -> void:
	_rng.randomize()
	add_to_group("boss")
	add_to_group("enemy")
	health = max_health
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.5
		cap.height = 2.3
		cs.shape = cap
		cs.position = Vector3(0, 1.15, 0)
		add_child(cs)
	_build_model()
	_define_poses()
	_cur = poses["waiting"].duplicate()
	_from = _cur.duplicate()
	_to = _cur.duplicate()


# =====================================================================
#  API (la usa final_fight.gd)
# =====================================================================

func place_dormant(pos: Vector3, look_point: Vector3) -> void:
	global_position = pos
	_face_instant(look_point)
	state = State.DORMANT
	_pose("waiting", 0.1)


## Mientras habla con el jugador.
func start_talk() -> void:
	state = State.TALK
	_kinematic = true
	_pose("talk", 0.5)


func gesture(name: String) -> void:
	_pose(name, 0.4)


func face_target() -> void:
	if _valid_target():
		var t0 := rotation.y
		var d := target.global_position - global_position
		var want := atan2(-d.x, -d.z)
		var tw := create_tween()
		tw.tween_method(func(v: float): rotation.y = lerp_angle(t0, want, v), 0.0, 1.0, 0.8).set_trans(Tween.TRANS_SINE)


## Final de "titularse": camina hasta el jugador y le pone la mano en el hombro.
func walk_to_player() -> void:
	if not _valid_target():
		return
	_kinematic = true
	_pose("walk_calm", 0.4)
	var to := target.global_position - global_position
	to.y = 0.0
	var dest := target.global_position - to.normalized() * 1.4
	var dur := maxf(1.0, to.length() / 2.0)
	var start := global_position
	_walk_target = dest
	var tw := create_tween()
	tw.tween_method(func(t: float):
		global_position = start.lerp(dest, t)
		_walk_phase += 0.03
		_walk_amt = 0.5, 0.0, 1.0, dur)
	tw.tween_callback(func():
		_walk_amt = 0.0
		_pose("hand_shoulder", 0.5))


## Elige pelear: desenfunda la espada con una mano.
func begin_fight() -> void:
	state = State.INTRO
	_kinematic = true
	_pose("draw", 0.35)
	await _w(0.35)
	sword_sheathed.visible = false
	sword_hand.visible = true
	FX.burst(fx_parent, sword_hand.global_position, true, 20, 0.6)
	_pose("salute", 0.3)
	await _w(0.8)
	_pose("guard", 0.35)
	await _w(0.35)
	_kinematic = false
	state = State.FIGHT
	_cooldown = 0.4
	battle_started.emit()


func take_damage(amount: float, _from_pos: Variant = null) -> void:
	if state in [State.DORMANT, State.TALK, State.INTRO, State.TRANSITION, State.DEAD]:
		return
	health -= amount
	_flash = 1.0
	damaged.emit(amount)
	if health <= 0.0:
		health = 0.0
		health_changed.emit(health, max_health)
		if phase == 1:
			_start_phase2()
		else:
			_die()
		return
	health_changed.emit(health, max_health)


func debug_force_phase2() -> void:
	if phase == 1 and state in [State.FIGHT, State.BUSY]:
		health = 0.0
		_start_phase2()


func clear_minions() -> void:
	for a in _ais:
		if is_instance_valid(a) and not a.is_dead:
			a._die()
	_ais.clear()


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
	if phase == 2:
		m_blade.emission_energy_multiplier = 3.5 + sin(_anim_t * 7.0) * 1.0
	_ais = _ais.filter(func(a): return is_instance_valid(a) and not a.is_dead)
	if state == State.FIGHT:
		_think(delta)
	_dodge_cd -= delta
	_gun_cd -= delta
	_spell_cd -= delta
	_ai_cd -= delta
	_code_cd -= delta
	_warp_cd -= delta


func _update_movement(delta: float) -> void:
	var desired := Vector3.ZERO
	if state == State.FIGHT and _valid_target():
		var to := target.global_position - global_position
		to.y = 0.0
		_turn_toward(target.global_position, delta, 1.0)
		var d := to.length()
		if d > 3.0:
			desired = to.normalized() * move_speed * (1.2 if phase == 2 else 1.0)
		else:
			# Rodea al jugador con pasos laterales (destreza)
			desired = to.normalized().cross(Vector3.UP) * move_speed * 0.5 * (1.0 if int(_anim_t / 2.0) % 2 == 0 else -1.0)
	elif state == State.BUSY and _valid_target():
		_turn_toward(target.global_position, delta, _tracking)
	desired += _lunge
	_lunge = _lunge.move_toward(Vector3.ZERO, 22.0 * delta)
	velocity.x = desired.x
	velocity.z = desired.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - 30.0 * delta
	move_and_slide()
	var flat := Vector2(velocity.x, velocity.z).length()
	_walk_amt = move_toward(_walk_amt, clampf(flat / move_speed, 0.0, 1.4), delta * 5.0)
	_walk_phase += delta * flat * 1.2


func _turn_toward(p: Vector3, delta: float, factor: float) -> void:
	if factor <= 0.0:
		return
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	rotation.y = rotate_toward(rotation.y, atan2(-d.x, -d.z), deg_to_rad(320.0 if phase == 1 else 400.0) * factor * delta)


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
	var d := _flat(target.global_position, global_position)
	# Esquiva tus ataques y contraataca
	var attacking: bool = "_attack_t" in target and float(target.get("_attack_t")) > 0.2
	if attacking and d < 3.8 and _dodge_cd <= 0.0 and _rng.randf() < (0.35 if phase == 1 else 0.5):
		_dodge_cd = _rng.randf_range(2.5, 4.0)
		_start("esquiva")
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var pick := ""
	if phase == 1:
		if d > 11.0:
			pick = _weighted({"revolver": 5 if _gun_cd <= 0.0 else 0, "estocada": 3, "hechizo": 3 if _spell_cd <= 0.0 else 0})
		elif d > 4.0:
			pick = _weighted({"estocada": 4, "hechizo": 3 if _spell_cd <= 0.0 else 0, "revolver": 1 if _gun_cd <= 0.0 else 0, "combo": 2})
		else:
			pick = _weighted({"combo": 6, "giro": 2, "nova": 2 if _spell_cd <= 0.0 else 0})
	else:
		if _ais.size() < 2 and _ai_cd <= 0.0:
			pick = "invocar_ia"
		elif d > 11.0:
			pick = _weighted({"revolver": 3 if _gun_cd <= 0.0 else 0, "corte_fuego": 3, "corte_rayo": 3, "flechas": 3 if _spell_cd <= 0.0 else 0,
				"codigo": 3 if _code_cd <= 0.0 else 0, "teletransporte": 3 if _warp_cd <= 0.0 else 0, "distorsion": 2 if _warp_cd <= 0.0 else 0})
		elif d > 4.0:
			pick = _weighted({"corte_fuego": 3, "corte_rayo": 3, "estocada": 2, "distorsion": 3 if _warp_cd <= 0.0 else 0, "flechas": 2 if _spell_cd <= 0.0 else 0,
				"codigo": 2 if _code_cd <= 0.0 else 0, "teletransporte": 2 if _warp_cd <= 0.0 else 0})
		else:
			pick = _weighted({"combo": 5, "giro": 3, "nova": 2 if _spell_cd <= 0.0 else 0, "teletransporte": 1 if _warp_cd <= 0.0 else 0})
	if pick == "":
		_cooldown = 0.25
		return
	if _last.size() >= 2 and _last[-1] == pick and _last[-2] == pick:
		_cooldown = 0.15
		_last.append("_")
		return
	_start(pick)


func _start(pick: String) -> void:
	_last.append(pick)
	if _last.size() > 4:
		_last.pop_front()
	state = State.BUSY
	_attack_id += 1
	var id := _attack_id
	match pick:
		"combo": _atk_combo(id)
		"estocada": _atk_lunge(id)
		"giro": _atk_spin(id)
		"esquiva": _atk_dodge(id)
		"revolver": _atk_revolver(id)
		"hechizo": _atk_spell(id)
		"nova": _atk_nova(id)
		"corte_fuego": _atk_wave(id, "fuego")
		"corte_rayo": _atk_wave(id, "rayo")
		"flechas": _atk_arrow_rain(id)
		"codigo": _atk_code(id)
		"invocar_ia": _atk_summon_ai(id)
		"teletransporte": _atk_teleport(id)
		"distorsion": _atk_pull(id)


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
	state = State.FIGHT
	_cooldown = recovery * (0.7 if phase == 2 else 1.0)
	_tracking = 1.0
	_set_gun(false)
	_pose("guard", 0.3)


func _x(id: int) -> bool:
	return id != _attack_id or state in [State.DEAD, State.TRANSITION]


func _sp() -> float:
	return 0.8 if phase == 2 else 1.0


# =====================================================================
#  Espada
# =====================================================================

## Combo desesperado de 3 a 5 tajos rapidísimos.
func _atk_combo(id: int) -> void:
	var hits := _rng.randi_range(3, 5)
	for i in hits:
		var side := "a" if i % 2 == 0 else "b"
		_tracking = 1.0
		_pose("slash_wind_" + side, 0.16)
		await _w((0.36 if i == 0 else 0.2) * _sp())
		if _x(id): return
		_tracking = 0.3
		_lunge = -global_basis.z * 7.0
		_pose("slash_" + side, 0.08)
		await _w(0.06)
		if _x(id): return
		_melee(3.0, 0.1, 11.0)
		_trail_fx()
		await _w(0.12 * _sp())
		if _x(id): return
	await _w(0.45)
	_end(id, _rng.randf_range(0.4, 0.8))


## Estocada a distancia: cruza el espacio en un instante.
func _atk_lunge(id: int) -> void:
	_tracking = 1.0
	_pose("thrust_wind", 0.3)
	await _w(0.45 * _sp())
	if _x(id): return
	_tracking = 0.15
	_pose("thrust", 0.08)
	var t := 0.0
	while t < 0.35:
		await get_tree().physics_frame
		if _x(id): return
		t += get_physics_process_delta_time()
		_lunge = -global_basis.z * 24.0
		if _valid_target() and _flat(target.global_position, global_position) < 2.2:
			break
	_lunge = Vector3.ZERO
	_melee(3.0, 0.3, 16.0)
	_trail_fx()
	await _w(0.5)
	_end(id, 0.6)


## Giro: tajo de 360°.
func _atk_spin(id: int) -> void:
	_tracking = 0.0
	_pose("spin_wind", 0.2)
	await _w(0.35 * _sp())
	if _x(id): return
	_pose("spin", 0.08)
	var t0 := rotation.y
	var tw := create_tween()
	tw.tween_method(func(v: float): rotation.y = t0 + v, 0.0, TAU, 0.35)
	await _w(0.15)
	if _x(id): return
	_melee(3.6, -1.0, 15.0)
	FX.shockwave(fx_parent, global_position, 3.6, _blade_color(), 0.3)
	await _w(0.5)
	_end(id, 0.6)


## Esquiva hacia un lado con una estela y contraataca.
func _atk_dodge(id: int) -> void:
	var side := global_basis.x * (1.0 if _rng.randf() < 0.5 else -1.0)
	_pose("dodge", 0.08)
	_afterimage()
	_lunge = side * 13.0 + global_basis.z * 3.0
	await _w(0.25)
	if _x(id): return
	if _rng.randf() < 0.7:
		_tracking = 1.0
		_pose("slash_wind_a", 0.1)
		await _w(0.18)
		if _x(id): return
		_lunge = -global_basis.z * 9.0
		_pose("slash_a", 0.07)
		await _w(0.06)
		if _x(id): return
		_melee(3.2, 0.1, 14.0)
		_trail_fx()
	await _w(0.4)
	_end(id, 0.5)


# =====================================================================
#  Revólver
# =====================================================================

## Saca un pequeño revólver y dispara (cuando estás lejos).
func _atk_revolver(id: int) -> void:
	_gun_cd = _rng.randf_range(4.0, 6.0)
	_tracking = 1.0
	_pose("gun_draw", 0.2)
	await _w(0.25)
	if _x(id): return
	_set_gun(true)
	_pose("gun_aim", 0.18)
	await _w(0.45)
	var shots := 6 if phase == 2 else _rng.randi_range(3, 4)
	for i in shots:
		if _x(id) or not _valid_target(): break
		_shoot()
		_pose("gun_recoil", 0.05)
		await _w(0.07)
		if _x(id): break
		_pose("gun_aim", 0.1)
		await _w(0.18 if phase == 1 else 0.11)
	if _x(id): return
	await _w(0.3)
	_end(id, 0.6)


func _set_gun(on: bool) -> void:
	revolver_hand.visible = on
	revolver_holster.visible = not on


func _shoot() -> void:
	var from := muzzle.global_position
	var aim := target.global_position + Vector3(0, 1.0, 0) + _lead(from.distance_to(target.global_position) / 42.0)
	var b := BOLT.new()
	b.kind = "laser"
	b.target = target
	b.shooter = self
	b.damage = 9.0 * damage_multiplier
	b.size = 0.55
	b.color = Color(1.0, 0.8, 0.35)
	b.velocity = (aim - from).normalized() * 42.0
	b.life = 2.0
	fx_parent.add_child(b)
	b.global_position = from
	LFX.puff(fx_parent, from, Color(3.0, 2.2, 0.8, 1), 8, 0.12, 3.0, 0.0)
	_shake(0.06)


# =====================================================================
#  Hechizos
# =====================================================================

func _atk_spell(id: int) -> void:
	_spell_cd = _rng.randf_range(5.0, 7.0) * _sp()
	if _rng.randf() < 0.5:
		await _spell_circles(id)
	else:
		await _spell_fire_ring(id)
	if _x(id): return
	await _w(0.4)
	_end(id, 0.8)


## Nova: explosión arcana a su alrededor.
func _atk_nova(id: int) -> void:
	_spell_cd = _rng.randf_range(5.0, 7.0) * _sp()
	_tracking = 0.0
	_pose("cast_up", 0.25)
	_code(["nova(radio=7)"], Color(0.8, 0.5, 1.0))
	var ring := _warn(global_position, 7.0, Color(0.8, 0.45, 1.0), 0.75)
	await _w(0.75)
	if _x(id):
		_free(ring)
		return
	_pose("cast_slam", 0.08)
	_free(ring)
	FX.shockwave(fx_parent, global_position, 7.0, Color(0.8, 0.45, 1.0), 0.45)
	LFX.puff(fx_parent, global_position + Vector3(0, 0.5, 0), Color(1.8, 1.0, 3.0, 1), 50, 0.3, 7.0, 0.0)
	_aoe(global_position, 7.0, 18.0)
	_shake(0.4)
	await _w(0.6)
	_end(id, 0.7)


func _spell_circles(id: int) -> void:
	_tracking = 0.6
	_pose("cast_point", 0.25)
	_code(["for c in range(3): circulo(jugador)"], Color(0.8, 0.5, 1.0))
	for i in (3 if phase == 1 else 5):
		if _x(id) or not _valid_target():
			return
		var p := _in_arena(target.global_position + _lead(0.6))
		var ring := _warn(p, 3.0, Color(0.8, 0.45, 1.0), 0.9 if i == 0 else 0.65)
		await _w(0.9 if i == 0 else 0.65)
		_free(ring)
		if _x(id): return
		_pillar(p, Color(0.8, 0.45, 1.0))
		_aoe(p, 3.0, 18.0)


func _spell_fire_ring(id: int) -> void:
	_tracking = 0.0
	_pose("cast_up", 0.3)
	_code(["fuego.anillo(expandir=true)"], Color(1.0, 0.55, 0.2))
	await _w(0.5)
	if _x(id): return
	_pose("cast_slam", 0.08)
	var c := global_position
	var ring := FX.ground_ring(fx_parent, c, 1.0, Color(1.0, 0.45, 0.1), 3.5)
	var m: ShaderMaterial = ring.material_override
	m.set_shader_parameter("ring_width", 0.05)
	m.set_shader_parameter("fill_alpha", 0.0)
	var t := 0.0
	var hit := false
	var fire_t := 0.0
	while t < 1.4:
		await get_tree().physics_frame
		if _x(id) or not is_instance_valid(ring):
			break
		var dt := get_physics_process_delta_time()
		t += dt
		var r := lerpf(1.0, 18.0, t / 1.4)
		ring.scale = Vector3(r, 1, r)
		fire_t -= dt
		if fire_t <= 0.0:
			fire_t = 0.1
			for k in 6:
				var a := _rng.randf() * TAU
				LFX.puff(fx_parent, c + Vector3(cos(a), 0, sin(a)) * r + Vector3(0, 0.4, 0), Color(3.0, 1.3, 0.3, 1), 6, 0.45, 2.5, 2.5)
		if not hit and _valid_target():
			var d := _flat(target.global_position, c)
			if absf(d - r) < 1.0 and target.global_position.y < c.y + 1.8:
				hit = _hit(14.0, c, false, true)
	if is_instance_valid(ring):
		ring.queue_free()


# =====================================================================
#  Fase 2
# =====================================================================

func _start_phase2() -> void:
	state = State.TRANSITION
	_attack_id += 1
	_kinematic = true
	_lunge = Vector3.ZERO
	_set_gun(false)
	_pose("kneel", 0.5)
	said.emit("Nada mal… pero tu residencia apenas comienza.", 3.5)
	await _w(1.8)
	_pose("rise", 0.6)
	await _w(0.6)
	# Se quita la túnica
	_pose("tear", 0.25)
	_shed_robe()
	_shake(0.5)
	await _w(0.5)
	# La espada se enciende en rojo y la vida se vuelve a llenar
	phase = 2
	m_blade.albedo_color = Color(0.9, 0.15, 0.1)
	m_blade.emission_enabled = true
	m_blade.emission = Color(1.0, 0.12, 0.06)
	m_blade.emission_energy_multiplier = 4.0
	_blade_light.visible = true
	m_circuit.emission_energy_multiplier = 3.0
	m_eye.emission_energy_multiplier = 5.0
	_pose("roar", 0.3)
	said.emit("Ahora sí… defiende tu tesis.", 3.0)
	FX.shockwave(fx_parent, global_position, 12.0, Color(1.0, 0.2, 0.1), 0.8)
	FX.burst(fx_parent, global_position + Vector3(0, 1.5, 0), true, 80, 1.8)
	var tw := create_tween()
	tw.tween_method(func(v: float):
		health = v
		health_changed.emit(health, max_health), 0.0, max_health, 2.0)
	phase_changed.emit(2)
	await _w(2.2)
	if state == State.DEAD: return
	_pose("guard", 0.3)
	await _w(0.3)
	_kinematic = false
	state = State.FIGHT
	_cooldown = 0.4
	_ai_cd = 2.0
	_warp_cd = 1.0


func _shed_robe() -> void:
	for n in _robe:
		var mis := n.find_children("*", "MeshInstance3D", true, false)
		for mi in mis:
			var gt := (mi as MeshInstance3D).global_transform
			var copy := MeshInstance3D.new()
			copy.mesh = (mi as MeshInstance3D).mesh
			copy.material_override = (mi as MeshInstance3D).material_override
			fx_parent.add_child(copy)
			copy.global_transform = gt
			var out := gt.origin - global_position
			out.y = 0.0
			var land := gt.origin + out.normalized() * _rng.randf_range(1.0, 2.5)
			land.y = global_position.y + 0.05
			var tw := copy.create_tween()
			tw.tween_property(copy, "global_position", land, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(copy, "rotation", copy.rotation + Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1, 1), _rng.randf_range(-1.5, 1.5)), 0.8)
		n.visible = false
	if _skin and _skin2:
		_skin.set_visible(false)
		_skin2.set_visible(true)
	LFX.puff(fx_parent, global_position + Vector3(0, 1.4, 0), Color(0.2, 0.2, 0.25, 0.8), 30, 0.4, 3.0, -2.0)


## Corte de fuego o de electricidad: una onda que viaja por el suelo.
func _atk_wave(id: int, element: String) -> void:
	_tracking = 1.0
	_pose("wave_wind", 0.25)
	var col := Color(1.0, 0.4, 0.1) if element == "fuego" else Color(0.5, 0.85, 1.0)
	m_blade.emission = col
	await _w(0.5)
	if _x(id): return
	var n := 1 if _rng.randf() < 0.6 else 2
	for i in n:
		_tracking = 0.2
		_pose("wave_slash" if i == 0 else "slash_b", 0.08)
		_wave(element, col)
		await _w(0.35)
		if _x(id): return
		if i == 0 and n == 2:
			_pose("wave_wind", 0.15)
			_tracking = 1.0
			await _w(0.25)
			if _x(id): return
	m_blade.emission = Color(1.0, 0.12, 0.06)
	await _w(0.4)
	_end(id, 0.7)


func _wave(element: String, col: Color) -> void:
	var dir := -global_basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var right := dir.cross(Vector3.UP)
	var w := Node3D.new()
	fx_parent.add_child(w)
	w.global_position = global_position + dir * 1.5 + Vector3(0, 0.7, 0)
	w.look_at(w.global_position + dir, Vector3.UP)
	var mat := LFX.emissive(col, 4.0, 0.85)
	for k in 7:
		var a := deg_to_rad(-60.0 + k * 20.0)
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.75, 0.9 - absf(k - 3) * 0.15, 0.12)
		bm.material = mat
		seg.mesh = bm
		seg.position = Vector3(sin(a) * 2.0, 0, cos(a) * 0.6)
		seg.rotation.y = a
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(seg)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 2.0
	l.omni_range = 6.0
	w.add_child(l)
	var hit := [false]
	var fx_t := [0.0]
	var start := w.global_position
	var tw := w.create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(w):
			return
		var p := start + dir * 26.0 * t
		w.global_position = p
		fx_t[0] -= 0.016
		if fx_t[0] <= 0.0:
			fx_t[0] = 0.05
			LFX.puff(fx_parent, p + right * _rng.randf_range(-1.8, 1.8), Color(col.r * 3.0, col.g * 3.0, col.b * 3.0, 1), 4, 0.25, 2.0, 2.0 if element == "fuego" else 0.0)
		if not hit[0] and _valid_target():
			var rel := target.global_position - Vector3(p.x, target.global_position.y, p.z)
			if absf(rel.dot(dir)) < 1.0 and absf(rel.dot(right)) < 2.3 and absf(target.global_position.y - global_position.y) < 2.0:
				hit[0] = true
				if element == "fuego":
					_hit(16.0, p, false, true)
				else:
					_hit(16.0, p, true, false), 0.0, 1.0, 1.1)
	tw.tween_property(w, "scale", Vector3.ONE * 0.01, 0.15)
	tw.tween_callback(w.queue_free)


## Lluvia de flechas sobre un área alrededor del jugador.
func _atk_arrow_rain(id: int) -> void:
	_spell_cd = _rng.randf_range(5.0, 7.0)
	_tracking = 0.5
	_pose("cast_up", 0.3)
	_code(["flechas = Arco.new().lluvia(30)"], Color(1.0, 0.85, 0.4))
	if not _valid_target():
		_end(id, 0.5)
		return
	var c := _in_arena(target.global_position + _lead(0.5))
	var r := 5.0
	var ring := _warn(c, r, Color(1.0, 0.8, 0.35), 1.0)
	await _w(1.0)
	if _x(id):
		_free(ring)
		return
	_pose("cast_slam", 0.1)
	for i in 30:
		var a := _rng.randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * sqrt(_rng.randf()) * r
		_falling_arrow(p)
		if i % 3 == 0:
			await _w(0.04)
			if _x(id): break
	_free(ring)
	await _w(0.6)
	_end(id, 0.6)


func _falling_arrow(p: Vector3) -> void:
	var n := Node3D.new()
	fx_parent.add_child(n)
	n.global_position = p + Vector3(_rng.randf_range(-1, 1), 14.0, _rng.randf_range(-1, 1))
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.02
	cm.height = 1.1
	cm.material = LFX.emissive(Color(1.0, 0.85, 0.45), 1.6)
	shaft.mesh = cm
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = 0.06
	hm.height = 0.2
	hm.material = cm.material
	head.mesh = hm
	head.rotation_degrees = Vector3(180, 0, 0)
	head.position = Vector3(0, -0.6, 0)
	n.add_child(head)
	n.look_at_from_position(n.global_position, p, Vector3.FORWARD)
	n.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	var tw := n.create_tween()
	tw.tween_property(n, "global_position", p + Vector3(0, 0.4, 0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		LFX.puff(fx_parent, p + Vector3(0, 0.1, 0), Color(2.0, 1.6, 0.8, 1), 4, 0.1, 1.5, -4.0)
		if _valid_target() and _flat(target.global_position, p) < 1.0:
			_hit(7.0, p, false, false))
	tw.tween_interval(1.2)
	tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.3)
	tw.tween_callback(n.queue_free)


## Código: compila espadas espectrales que vuelan hacia ti, o un hechizo.
func _atk_code(id: int) -> void:
	_code_cd = _rng.randf_range(7.0, 10.0)
	_tracking = 0.5
	_pose("cast_point", 0.25)
	if _rng.randf() < 0.6:
		_code(["for i in range(5):", "    espada[i] = Espada.compilar()", "    espada[i].lanzar(jugador)"], Color(1.0, 0.3, 0.25))
		var swords: Array = []
		for i in 5:
			var s := _spectral_sword()
			var a := deg_to_rad(-60.0 + i * 30.0)
			s.global_position = global_position + global_basis * Vector3(sin(a) * 1.8, 2.6 + cos(a) * 0.6, 0.6)
			swords.append(s)
		await _w(0.7)
		for s in swords:
			if _x(id) or not _valid_target():
				break
			_launch_sword(s, target.global_position + Vector3(0, 1.0, 0) + _lead(0.35))
			await _w(0.18)
		for s in swords:
			if is_instance_valid(s) and not s.has_meta("launched"):
				s.queue_free()
	else:
		_code(["hechizo = Hechizo.aleatorio()", "hechizo.lanzar()"], Color(0.8, 0.5, 1.0))
		await _w(0.4)
		if _x(id): return
		if _rng.randf() < 0.5:
			await _spell_circles(id)
		else:
			await _spell_fire_ring(id)
	if _x(id): return
	await _w(0.4)
	_end(id, 0.6)


func _spectral_sword() -> Node3D:
	var s := Node3D.new()
	fx_parent.add_child(s)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 1.3, 0.16)
	bm.material = m_holo
	blade.mesh = bm
	blade.position = Vector3(0, -0.5, 0)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(blade)
	var guard := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.4, 0.06, 0.1)
	gm.material = m_holo
	guard.mesh = gm
	guard.position = Vector3(0, 0.15, 0)
	s.add_child(guard)
	s.scale = Vector3.ONE * 0.01
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	LFX.puff(fx_parent, s.global_position, Color(2.5, 0.6, 0.5, 1), 8, 0.12, 2.0, 0.0)
	return s


func _launch_sword(s: Node3D, to: Vector3) -> void:
	if not is_instance_valid(s):
		return
	s.set_meta("launched", true)
	var from := s.global_position
	var dir := (to - from).normalized()
	var end := from + dir * 30.0
	s.look_at_from_position(from, to, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	s.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	var hit := [false]
	var tw := s.create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(s):
			return
		var p := from.lerp(end, t)
		s.global_position = p
		if not hit[0] and _valid_target() and p.distance_to(target.global_position + Vector3(0, 1.0, 0)) < 1.0:
			hit[0] = _hit(12.0, p, false, false) or true, 0.0, 1.0, 30.0 / 26.0)
	tw.tween_callback(s.queue_free)


## Invoca 1–2 IAs holográficas que pelean contigo.
func _atk_summon_ai(id: int) -> void:
	_ai_cd = _rng.randf_range(22.0, 28.0)
	_tracking = 0.0
	_pose("cast_up", 0.3)
	_code(["ia = IA.instanciar(modo='combate')", "ia.objetivo = jugador"], Color(0.4, 0.9, 1.0))
	said.emit("Mis asistentes de investigación te harán compañía.", 2.5)
	await _w(0.7)
	if _x(id): return
	var n := 2 - _ais.size()
	for i in n:
		var e := ENEMY.new()
		e.type = "robot_espada" if i == 0 else "robot_laser"
		e.target = target
		e.fx_parent = fx_parent
		e.wander_radius = 6.0
		var a := rotation.y + (PI * 0.5 if i == 0 else -PI * 0.5)
		var p := _in_arena(global_position + Vector3(sin(a), 0, cos(a)) * 3.0)
		e.place(p + Vector3(0, 0.1, 0), rotation.y)
		(minion_parent if minion_parent else fx_parent).add_child(e)
		for mi in e._model["meshes"]:
			(mi as MeshInstance3D).material_override = m_holo
		e.max_hp = 90.0
		e.hp = 90.0
		e._aggro()
		_ais.append(e)
		LFX.puff(fx_parent, p + Vector3(0, 1.2, 0), Color(0.6, 2.0, 2.6, 1), 30, 0.2, 3.0, 0.0)
	await _w(0.6)
	_end(id, 0.5)


## Se teletransporta a tu espalda y ataca.
func _atk_teleport(id: int) -> void:
	_warp_cd = _rng.randf_range(4.0, 6.0)
	if not _valid_target():
		_end(id, 0.3)
		return
	_blink_out()
	await _w(0.3)
	if _x(id): return
	var tf := target.global_position - global_position
	tf.y = 0.0
	var p := _in_arena(target.global_position + tf.normalized() * 2.3)
	global_position = p
	_face_instant(target.global_position)
	_blink_in()
	_pose("slash_wind_b", 0.1)
	await _w(0.32)
	if _x(id): return
	_lunge = -global_basis.z * 8.0
	_pose("slash_b", 0.07)
	await _w(0.06)
	if _x(id): return
	_melee(3.2, 0.0, 16.0)
	_trail_fx()
	await _w(0.5)
	_end(id, 0.5)


## Distorsiona el espacio: te jala hacia su espada y te corta.
func _atk_pull(id: int) -> void:
	_warp_cd = _rng.randf_range(5.0, 7.0)
	_tracking = 1.0
	_pose("pull", 0.25)
	_code(["espacio.doblar(jugador -> aqui)"], Color(0.8, 0.4, 1.0))
	said.emit("Ven aquí.", 1.5)
	var ring := FX.ground_ring(fx_parent, global_position, 9.0, Color(0.7, 0.35, 1.0), 2.5)
	var m: ShaderMaterial = ring.material_override
	await _w(0.4)
	var t := 0.0
	while t < 0.7:
		await get_tree().physics_frame
		if _x(id): break
		var dt := get_physics_process_delta_time()
		t += dt
		m.set_shader_parameter("progress", 1.0 - t / 0.7)
		if _valid_target():
			var rolling: bool = "_iframes" in target and float(target.get("_iframes")) > 0.0
			var to := global_position - target.global_position
			to.y = 0.0
			if to.length() > 2.0 and not rolling:
				target.global_position += to.normalized() * minf(to.length() - 2.0, 16.0 * dt)
				if randf() < 0.3:
					LFX.puff(fx_parent, target.global_position + Vector3(0, 1.0, 0), Color(1.6, 0.8, 3.0, 1), 4, 0.15, 1.0, 0.0)
	_free(ring)
	if _x(id): return
	_pose("slash_wind_a", 0.08)
	await _w(0.12)
	if _x(id): return
	_pose("slash_a", 0.07)
	_lunge = -global_basis.z * 6.0
	await _w(0.05)
	_melee(3.4, 0.0, 20.0)
	_trail_fx()
	await _w(0.6)
	_end(id, 0.6)


func _blink_out() -> void:
	LFX.puff(fx_parent, global_position + Vector3(0, 1.1, 0), Color(2.0, 0.6, 2.6, 1), 30, 0.25, 3.0, 0.0)
	model.visible = false
	_kinematic = true


func _blink_in() -> void:
	model.visible = true
	_kinematic = false
	LFX.puff(fx_parent, global_position + Vector3(0, 1.1, 0), Color(2.0, 0.6, 2.6, 1), 30, 0.25, 3.0, 0.0)


# =====================================================================
#  Muerte
# =====================================================================

func _die() -> void:
	state = State.DEAD
	_attack_id += 1
	_kinematic = true
	_lunge = Vector3.ZERO
	model.visible = true
	_set_gun(false)
	clear_minions()
	_pose("kneel", 0.8)
	said.emit("Tú… sí eras digno. La tesis… es tuya.", 4.0)
	defeated.emit()
	_blade_light.visible = false
	var tw := create_tween()
	tw.tween_method(func(v: float): m_blade.emission_energy_multiplier = v, 4.0, 0.0, 2.0)
	await _w(2.6)
	var tw2 := create_tween()
	tw2.tween_property(model, "rotation_degrees:x", 80.0, 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw2.parallel().tween_property(model, "position:y", 0.3, 1.2)


# =====================================================================
#  Utilidades
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


func _hit(dmg: float, from: Vector3, electric := false, burn := false) -> bool:
	if not _valid_target() or not target.has_method("take_damage"):
		return false
	var before: float = float(target.get("hp")) if "hp" in target else 0.0
	target.take_damage(dmg * damage_multiplier, from)
	var landed: bool = "hp" in target and float(target.get("hp")) < before
	if landed and target.has_method("apply_status"):
		if electric and _rng.randf() < electrocute_chance:
			target.apply_status("electrocutado", 2.0)
		if burn:
			target.apply_status("quemadura", 5.0)
	return landed


func _melee(reach: float, dot_min: float, dmg: float) -> void:
	if not _valid_target():
		return
	var to := target.global_position - global_position
	if absf(to.y) > 2.5:
		return
	to.y = 0.0
	var fwd := -global_basis.z
	fwd.y = 0.0
	if to.length() < reach and (to.length() < 1.0 or fwd.normalized().dot(to.normalized()) > dot_min):
		_hit(dmg * (1.25 if phase == 2 else 1.0), global_position, false, false)
		FX.burst(fx_parent, target.global_position + Vector3(0, 1.1, 0), true, 12, 0.5)
		_shake(0.2)


func _aoe(center: Vector3, radius: float, dmg: float) -> void:
	if not _valid_target():
		return
	var to := target.global_position - center
	if absf(to.y) < 2.5 and Vector2(to.x, to.z).length() < radius:
		_hit(dmg, center, false, false)


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


func _pillar(p: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 2.8
	cm.height = 8.0
	cm.material = LFX.emissive(col, 1.6, 0.32)
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_parent.add_child(mi)
	mi.global_position = p + Vector3(0, 4.0, 0)
	mi.scale = Vector3(0.2, 1, 0.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.12)
	tw.tween_property(mi, "scale", Vector3(0.01, 1.2, 0.01), 0.35)
	tw.tween_callback(mi.queue_free)
	LFX.puff(fx_parent, p + Vector3(0, 0.5, 0), Color(col.r * 2.5, col.g * 2.5, col.b * 2.5, 1), 24, 0.25, 5.0, 0.0)
	_shake(0.15)


func _blade_color() -> Color:
	return Color(1.0, 0.2, 0.1) if phase == 2 else Color(0.85, 0.9, 1.0)


func _trail_fx() -> void:
	var p := sword_hand.global_position + (-global_basis.z) * 0.8
	var c := _blade_color()
	LFX.puff(fx_parent, p, Color(c.r * 2.5, c.g * 2.5, c.b * 2.5, 1), 10, 0.12, 3.0, 0.0)


## Copias transparentes que quedan al esquivar (destreza).
func _afterimage() -> void:
	for mi in _meshes:
		if not mi.visible or not mi.is_visible_in_tree():
			continue
		var c := MeshInstance3D.new()
		c.mesh = mi.mesh
		c.material_override = m_holo
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fx_parent.add_child(c)
		c.global_transform = mi.global_transform
		var tw := c.create_tween()
		tw.tween_property(c, "transparency", 1.0, 0.4)
		tw.tween_callback(c.queue_free)


func _code(lines: Array, col: Color) -> void:
	var pos := global_position + Vector3(0, 2.8, 0)
	for i in lines.size():
		var l := Label3D.new()
		l.text = String(lines[i])
		l.font_size = 44
		l.pixel_size = 0.005
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = col
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.outline_size = 8
		l.shaded = false
		fx_parent.add_child(l)
		var a := TAU * i / maxf(1.0, lines.size()) + _rng.randf() * 0.5
		var start := pos + Vector3(cos(a) * 0.9, i * 0.3, sin(a) * 0.9)
		l.global_position = start
		l.modulate.a = 0.0
		var tw := l.create_tween()
		tw.tween_interval(i * 0.1)
		tw.tween_property(l, "modulate:a", 1.0, 0.12)
		tw.parallel().tween_property(l, "global_position", start + Vector3(0, 1.2, 0), 1.6)
		tw.tween_property(l, "modulate:a", 0.0, 0.4)
		tw.tween_callback(l.queue_free)


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


var _bm: BoxMesh
var _sm: SphereMesh
var _cm: CylinderMesh


func _box(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return _add(p, _bm, size, pos, m, rot)


func _sph(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return _add(p, _sm, size, pos, m, rot)


func _cyl(p: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 14
	cm.rings = 1
	return _add(p, cm, Vector3.ONE, pos, m, rot)


func _add(p: Node3D, mesh: Mesh, size: Vector3, pos: Vector3, m: Material, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = size
	p.add_child(mi)
	_meshes.append(mi)
	return mi


func _joint(parent: Node3D, key: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = key
	j.position = pos
	parent.add_child(j)
	J[key] = j
	return j


## Pieza de la túnica (se desprende en la fase 2).
func _robe_part(parent: Node3D) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	_robe.append(n)
	return n


func _build_model() -> void:
	_bm = BoxMesh.new()
	_sm = SphereMesh.new()
	_sm.radius = 0.5
	_sm.height = 1.0
	_sm.radial_segments = 16
	_sm.rings = 8
	m_skin = _mat(Color(0.78, 0.6, 0.48), 0.5)
	var beard := _mat(Color(0.16, 0.13, 0.12), 0.85)
	var cloth := _mat(Color(0.1, 0.1, 0.12), 0.6)
	var armor := _mat(Color(0.18, 0.18, 0.2), 0.4, 0.6)
	var robe := _mat(Color(0.06, 0.06, 0.1), 0.75)
	var gold := _mat(Color(0.9, 0.72, 0.3), 0.3, 0.9)
	var leather := _mat(Color(0.25, 0.15, 0.08), 0.7)
	var steel := _mat(Color(0.7, 0.72, 0.78), 0.2, 0.95)
	m_blade = _mat(Color(0.82, 0.84, 0.9), 0.15, 0.95)
	m_circuit = _glow(Color(1.0, 0.15, 0.08), 0.6)
	m_eye = _glow(Color(1.0, 0.85, 0.6), 1.0)
	m_holo = _glow(Color(1.0, 0.3, 0.25), 2.5)
	m_holo.albedo_color = Color(1.0, 0.3, 0.25, 0.45)
	m_holo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_holo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_flash = StandardMaterial3D.new()
	m_flash.albedo_color = Color(1, 1, 1, 0.35)
	m_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_flash.emission_enabled = true
	m_flash.emission = Color(1.0, 0.95, 0.85)

	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var pelvis := _joint(model, "pelvis", Vector3(0, 1.12, 0))
	_box(pelvis, Vector3(0.48, 0.26, 0.3), Vector3.ZERO, cloth)
	_box(pelvis, Vector3(0.5, 0.07, 0.32), Vector3(0, 0.1, 0), leather)
	_box(pelvis, Vector3(0.1, 0.08, 0.04), Vector3(0, 0.1, -0.17), gold)
	var spine := _joint(pelvis, "spine", Vector3(0, 0.14, 0))
	_box(spine, Vector3(0.46, 0.36, 0.28), Vector3(0, 0.18, 0), armor)
	for k in 3:
		_box(spine, Vector3(0.02, 0.3, 0.01), Vector3(-0.12 + k * 0.12, 0.18, -0.145), m_circuit)
	var chest := _joint(spine, "chest", Vector3(0, 0.36, 0))
	_box(chest, Vector3(0.62, 0.44, 0.34), Vector3(0, 0.2, 0), armor)
	_box(chest, Vector3(0.3, 0.02, 0.01), Vector3(0, 0.3, -0.175), m_circuit)
	_box(chest, Vector3(0.02, 0.3, 0.01), Vector3(0.18, 0.2, -0.175), m_circuit)
	_box(chest, Vector3(0.02, 0.3, 0.01), Vector3(-0.18, 0.2, -0.175), m_circuit)
	var neck := _joint(chest, "neck", Vector3(0, 0.46, 0))
	_cyl(neck, 0.08, 0.09, 0.16, Vector3(0, 0.06, 0), m_skin)
	var head := _joint(neck, "head", Vector3(0, 0.14, 0))
	# Pelón
	_sph(head, Vector3(0.27, 0.32, 0.3), Vector3(0, 0.15, 0), m_skin)
	_sph(head, Vector3(0.06, 0.09, 0.05), Vector3(-0.14, 0.13, 0.0), m_skin)
	_sph(head, Vector3(0.06, 0.09, 0.05), Vector3(0.14, 0.13, 0.0), m_skin)
	# Cejas, ojos y nariz
	for sx: float in [-1.0, 1.0]:
		_box(head, Vector3(0.08, 0.018, 0.02), Vector3(sx * 0.06, 0.205, -0.135), beard, Vector3(0, 0, sx * -10))
		_box(head, Vector3(0.04, 0.018, 0.01), Vector3(sx * 0.06, 0.175, -0.14), m_eye)
	_box(head, Vector3(0.035, 0.07, 0.04), Vector3(0, 0.14, -0.15), m_skin)
	# Barba de candado: bigote + barbilla unidos por las comisuras
	_box(head, Vector3(0.12, 0.025, 0.03), Vector3(0, 0.09, -0.14), beard)
	_box(head, Vector3(0.02, 0.08, 0.03), Vector3(-0.055, 0.05, -0.135), beard)
	_box(head, Vector3(0.02, 0.08, 0.03), Vector3(0.055, 0.05, -0.135), beard)
	_box(head, Vector3(0.1, 0.07, 0.06), Vector3(0, 0.0, -0.115), beard)
	_box(head, Vector3(0.06, 0.012, 0.01), Vector3(0, 0.065, -0.146), _mat(Color(0.4, 0.2, 0.18), 0.6))
	# Brazos
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var sh := _joint(chest, "sh_" + side, Vector3(sx * 0.38, 0.36, 0))
		_sph(sh, Vector3(0.2, 0.2, 0.2), Vector3.ZERO, armor)
		_box(sh, Vector3(0.13, 0.36, 0.13), Vector3(0, -0.18, 0), cloth)
		_box(sh, Vector3(0.01, 0.3, 0.01), Vector3(sx * 0.066, -0.18, 0), m_circuit)
		var el := _joint(sh, "el_" + side, Vector3(0, -0.36, 0))
		_box(el, Vector3(0.12, 0.34, 0.12), Vector3(0, -0.16, 0), leather)
		var wr := _joint(el, "wr_" + side, Vector3(0, -0.34, 0))
		_box(wr, Vector3(0.09, 0.11, 0.1), Vector3(0, -0.05, 0), m_skin)
	# Piernas
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var hip := _joint(pelvis, "hip_" + side, Vector3(sx * 0.13, -0.08, 0))
		_box(hip, Vector3(0.17, 0.5, 0.18), Vector3(0, -0.25, 0), cloth)
		var kn := _joint(hip, "kn_" + side, Vector3(0, -0.5, 0))
		_box(kn, Vector3(0.15, 0.46, 0.16), Vector3(0, -0.23, 0), cloth)
		_box(kn, Vector3(0.17, 0.2, 0.18), Vector3(0, -0.38, 0), leather)
		var an := _joint(kn, "an_" + side, Vector3(0, -0.48, 0))
		_box(an, Vector3(0.15, 0.08, 0.28), Vector3(0, -0.02, -0.05), leather)
	# Espada de una mano (en la mano derecha, oculta hasta desenfundar)
	sword_hand = Node3D.new()
	(J["wr_r"] as Node3D).add_child(sword_hand)
	sword_hand.position = Vector3(0, -0.08, 0)
	_box(sword_hand, Vector3(0.05, 0.16, 0.05), Vector3(0, 0, 0), leather)
	_box(sword_hand, Vector3(0.3, 0.04, 0.07), Vector3(0, -0.1, 0), gold)
	_box(sword_hand, Vector3(0.035, 1.1, 0.08), Vector3(0, -0.66, 0), m_blade)
	_blade_light = OmniLight3D.new()
	_blade_light.light_color = Color(1.0, 0.15, 0.08)
	_blade_light.light_energy = 1.5
	_blade_light.omni_range = 4.0
	_blade_light.position = Vector3(0, -0.6, 0)
	_blade_light.visible = false
	sword_hand.add_child(_blade_light)
	sword_hand.visible = false
	# Vaina en la cadera izquierda con la espada enfundada
	sword_sheathed = Node3D.new()
	pelvis.add_child(sword_sheathed)
	sword_sheathed.position = Vector3(-0.28, 0.0, 0.05)
	sword_sheathed.rotation_degrees = Vector3(30, 0, 8)
	_box(sword_sheathed, Vector3(0.07, 1.0, 0.1), Vector3(0, -0.45, 0), leather)
	_box(sword_sheathed, Vector3(0.28, 0.04, 0.07), Vector3(0, 0.08, 0), gold)
	_box(sword_sheathed, Vector3(0.05, 0.16, 0.05), Vector3(0, 0.18, 0), leather)
	# Revólver: en la funda (cadera derecha) y en la mano izquierda al disparar
	revolver_holster = Node3D.new()
	pelvis.add_child(revolver_holster)
	revolver_holster.position = Vector3(0.27, -0.05, 0.02)
	_box(revolver_holster, Vector3(0.07, 0.2, 0.12), Vector3.ZERO, leather)
	_box(revolver_holster, Vector3(0.05, 0.1, 0.08), Vector3(0, 0.13, 0.03), _mat(Color(0.35, 0.22, 0.12), 0.6))
	revolver_hand = Node3D.new()
	(J["wr_l"] as Node3D).add_child(revolver_hand)
	revolver_hand.position = Vector3(0, -0.08, 0)
	_box(revolver_hand, Vector3(0.05, 0.12, 0.08), Vector3(0, 0, 0.02), _mat(Color(0.35, 0.22, 0.12), 0.6))
	_cyl(revolver_hand, 0.045, 0.045, 0.08, Vector3(0, -0.1, 0), steel)
	_cyl(revolver_hand, 0.015, 0.015, 0.2, Vector3(0, -0.22, 0), steel)
	muzzle = Node3D.new()
	revolver_hand.add_child(muzzle)
	muzzle.position = Vector3(0, -0.34, 0)
	revolver_hand.visible = false
	# Túnica académica con ribetes dorados (se la quita en la fase 2)
	var rt := _robe_part(chest)
	_box(rt, Vector3(0.68, 0.5, 0.4), Vector3(0, 0.2, 0), robe)
	_box(rt, Vector3(0.06, 0.5, 0.02), Vector3(-0.1, 0.2, -0.205), gold)
	_box(rt, Vector3(0.06, 0.5, 0.02), Vector3(0.1, 0.2, -0.205), gold)
	_box(rt, Vector3(0.72, 0.12, 0.46), Vector3(0, 0.44, 0.02), robe)
	_box(rt, Vector3(0.5, 0.2, 0.12), Vector3(0, 0.4, 0.24), robe, Vector3(-30, 0, 0))   # capucha caída
	var rs := _robe_part(spine)
	_box(rs, Vector3(0.52, 0.4, 0.34), Vector3(0, 0.18, 0), robe)
	var rk := _robe_part(pelvis)
	_cyl(rk, 0.3, 0.5, 1.05, Vector3(0, -0.5, 0), robe)
	_cyl(rk, 0.505, 0.51, 0.06, Vector3(0, -1.0, 0), gold)
	_box(rk, Vector3(0.06, 1.0, 0.02), Vector3(-0.08, -0.5, -0.4), gold, Vector3(-11, 0, 0))
	_box(rk, Vector3(0.06, 1.0, 0.02), Vector3(0.08, -0.5, -0.4), gold, Vector3(-11, 0, 0))
	for side in ["l", "r"]:
		var sl := _robe_part(J["sh_" + side])
		_cyl(sl, 0.1, 0.13, 0.4, Vector3(0, -0.18, 0), robe)
		var sl2 := _robe_part(J["el_" + side])
		_cyl(sl2, 0.13, 0.24, 0.36, Vector3(0, -0.15, 0), robe)
		_cyl(sl2, 0.245, 0.25, 0.04, Vector3(0, -0.34, 0), gold)
	for mi in _meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Modelo de Blender: espada, vaina, revólver y funda siguen siendo los del código
	var keep: Array = [sword_hand, sword_sheathed, revolver_holster, revolver_hand]
	var mats := {"ojos": m_eye, "circuito": m_circuit}
	_skin = BOSS_SKIN.apply(self, model, J, SKIN_PATH, mats, keep)
	_skin2 = BOSS_SKIN.apply(self, model, J, SKIN_F2_PATH, mats, keep)
	for sk in [_skin, _skin2]:
		if sk:
			for mi in sk.meshes:
				_meshes.append(mi)
	if _skin2:
		_skin2.set_visible(false)


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
	poses["waiting"] = _P({"sh_l": Vector3(-15, 0, -12), "el_l": Vector3(70, 0, 0), "sh_r": Vector3(-15, 0, 12), "el_r": Vector3(70, 0, 0), "head": Vector3(-6, 0, 0)})
	poses["talk"] = _P({"chest": Vector3(4, 0, 0), "sh_l": Vector3(-15, 0, -12), "el_l": Vector3(70, 0, 0), "sh_r": Vector3(35, 0, 20), "el_r": Vector3(60, 0, 0), "wr_r": Vector3(-20, 0, 0)})
	poses["open_arms"] = _P({"chest": Vector3(8, 0, 0), "head": Vector3(8, 0, 0), "sh_l": Vector3(40, 0, -55), "el_l": Vector3(20, 0, 0), "sh_r": Vector3(40, 0, 55), "el_r": Vector3(20, 0, 0)})
	poses["point"] = _P({"chest": Vector3(0, -10, 0), "sh_r": Vector3(85, 0, 5), "el_r": Vector3(5, 0, 0), "sh_l": Vector3(-15, 0, -12), "el_l": Vector3(70, 0, 0)})
	poses["walk_calm"] = _P({"sh_l": Vector3(-15, 0, -12), "el_l": Vector3(70, 0, 0), "sh_r": Vector3(10, 0, 8), "el_r": Vector3(10, 0, 0)})
	poses["hand_shoulder"] = _P({"chest": Vector3(-6, 0, 0), "head": Vector3(-12, 0, 0), "sh_r": Vector3(75, 0, -5), "el_r": Vector3(25, 0, 0), "sh_l": Vector3(-15, 0, -12), "el_l": Vector3(70, 0, 0)})
	poses["draw"] = _P({"chest": Vector3(0, 30, 0), "sh_r": Vector3(20, 0, -40), "el_r": Vector3(80, 0, 0), "wr_r": Vector3(20, 0, 0), "sh_l": Vector3(10, 0, -20)})
	poses["salute"] = _P({"chest": Vector3(4, 0, 0), "sh_r": Vector3(100, 0, -20), "el_r": Vector3(110, 0, 0), "wr_r": Vector3(30, 0, 0), "sh_l": Vector3(-20, 0, -15), "el_l": Vector3(40, 0, 0)})
	poses["guard"] = _P({"root_y": -0.06, "chest": Vector3(-6, -25, 0), "head": Vector3(4, 25, 0), "sh_r": Vector3(45, 0, 15), "el_r": Vector3(50, 0, 0), "wr_r": Vector3(55, 0, 0), "sh_l": Vector3(20, 0, -30), "el_l": Vector3(70, 0, 0), "hip_l": Vector3(18, 0, 0), "kn_l": Vector3(-22, 0, 0), "hip_r": Vector3(-8, 0, 0), "kn_r": Vector3(-18, 0, 0)})
	poses["slash_wind_a"] = _P({"root_y": -0.1, "chest": Vector3(0, -55, 0), "sh_r": Vector3(150, 0, 50), "el_r": Vector3(30, 0, 0), "wr_r": Vector3(30, 0, 0), "sh_l": Vector3(30, 0, -40), "el_l": Vector3(50, 0, 0), "hip_r": Vector3(20, 0, 0), "kn_r": Vector3(-25, 0, 0), "kn_l": Vector3(-15, 0, 0)})
	poses["slash_a"] = _P({"root_y": -0.15, "chest": Vector3(-15, 45, 0), "sh_r": Vector3(55, 0, -45), "el_r": Vector3(5, 0, 0), "wr_r": Vector3(45, 0, 0), "sh_l": Vector3(-20, 0, -45), "hip_l": Vector3(35, 0, 0), "kn_l": Vector3(-35, 0, 0), "hip_r": Vector3(-20, 0, 0), "kn_r": Vector3(-20, 0, 0)})
	poses["slash_wind_b"] = _P({"root_y": -0.1, "chest": Vector3(0, 45, 0), "sh_r": Vector3(80, 0, -60), "el_r": Vector3(70, 0, 0), "wr_r": Vector3(40, 0, 0), "sh_l": Vector3(20, 0, -30), "hip_l": Vector3(20, 0, 0), "kn_l": Vector3(-25, 0, 0)})
	poses["slash_b"] = _P({"root_y": -0.15, "chest": Vector3(-15, -50, 0), "sh_r": Vector3(80, 0, 70), "el_r": Vector3(5, 0, 0), "wr_r": Vector3(30, 0, 0), "sh_l": Vector3(10, 0, -50), "hip_r": Vector3(35, 0, 0), "kn_r": Vector3(-35, 0, 0), "hip_l": Vector3(-20, 0, 0)})
	poses["thrust_wind"] = _P({"root_y": -0.25, "chest": Vector3(5, -35, 0), "sh_r": Vector3(-25, 0, 15), "el_r": Vector3(100, 0, 0), "wr_r": Vector3(80, 0, 0), "sh_l": Vector3(60, 0, -20), "el_l": Vector3(20, 0, 0), "hip_l": Vector3(35, 0, 0), "kn_l": Vector3(-55, 0, 0), "kn_r": Vector3(-35, 0, 0)})
	poses["thrust"] = _P({"root_y": -0.3, "chest": Vector3(-25, 15, 0), "head": Vector3(15, 0, 0), "sh_r": Vector3(92, 0, 0), "el_r": Vector3(0, 0, 0), "wr_r": Vector3(90, 0, 0), "sh_l": Vector3(-30, 0, -40), "hip_l": Vector3(55, 0, 0), "kn_l": Vector3(-45, 0, 0), "hip_r": Vector3(-35, 0, 0), "kn_r": Vector3(-15, 0, 0)})
	poses["spin_wind"] = _P({"root_y": -0.3, "chest": Vector3(-10, 70, 0), "sh_r": Vector3(85, 0, 85), "el_r": Vector3(5, 0, 0), "wr_r": Vector3(80, 0, 0), "sh_l": Vector3(40, 0, -60), "kn_l": Vector3(-35, 0, 0), "kn_r": Vector3(-35, 0, 0), "hip_l": Vector3(20, 0, 0), "hip_r": Vector3(20, 0, 0)})
	poses["spin"] = _P({"root_y": -0.25, "chest": Vector3(-10, -40, 0), "sh_r": Vector3(88, 0, 88), "wr_r": Vector3(85, 0, 0), "sh_l": Vector3(70, 0, -80), "kn_l": Vector3(-30, 0, 0), "kn_r": Vector3(-30, 0, 0), "hip_l": Vector3(15, 0, 0), "hip_r": Vector3(15, 0, 0)})
	poses["dodge"] = _P({"root_y": -0.3, "chest": Vector3(-20, 0, 25), "sh_r": Vector3(30, 0, 50), "el_r": Vector3(40, 0, 0), "wr_r": Vector3(50, 0, 0), "sh_l": Vector3(20, 0, -60), "hip_l": Vector3(40, 0, -20), "kn_l": Vector3(-60, 0, 0), "hip_r": Vector3(20, 0, 20), "kn_r": Vector3(-40, 0, 0)})
	poses["gun_draw"] = _P({"chest": Vector3(0, -20, 0), "sh_l": Vector3(10, 0, 30), "el_l": Vector3(70, 0, 0), "sh_r": Vector3(30, 0, 25), "el_r": Vector3(40, 0, 0), "wr_r": Vector3(40, 0, 0)})
	poses["gun_aim"] = _P({"chest": Vector3(0, 25, 0), "head": Vector3(0, -15, 0), "sh_l": Vector3(90, 0, 10), "el_l": Vector3(0, 0, 0), "wr_l": Vector3(0, 0, 0), "sh_r": Vector3(-10, 0, 30), "el_r": Vector3(30, 0, 0), "wr_r": Vector3(50, 0, 0), "hip_l": Vector3(15, 0, 0), "kn_l": Vector3(-15, 0, 0)})
	poses["gun_recoil"] = _P({"chest": Vector3(6, 25, 0), "head": Vector3(0, -15, 0), "sh_l": Vector3(105, 0, 10), "el_l": Vector3(20, 0, 0), "sh_r": Vector3(-10, 0, 30), "el_r": Vector3(30, 0, 0), "wr_r": Vector3(50, 0, 0)})
	poses["cast_up"] = _P({"chest": Vector3(10, 0, 0), "head": Vector3(10, 0, 0), "sh_l": Vector3(165, 0, -20), "el_l": Vector3(10, 0, 0), "sh_r": Vector3(30, 0, 30), "el_r": Vector3(40, 0, 0), "wr_r": Vector3(50, 0, 0)})
	poses["cast_slam"] = _P({"root_y": -0.3, "chest": Vector3(-30, 0, 0), "sh_l": Vector3(70, 0, -10), "el_l": Vector3(0, 0, 0), "sh_r": Vector3(40, 0, 30), "el_r": Vector3(40, 0, 0), "kn_l": Vector3(-40, 0, 0), "kn_r": Vector3(-40, 0, 0), "hip_l": Vector3(30, 0, 0), "hip_r": Vector3(30, 0, 0)})
	poses["cast_point"] = _P({"chest": Vector3(0, 20, 0), "sh_l": Vector3(95, 0, -5), "el_l": Vector3(0, 0, 0), "wr_l": Vector3(-30, 0, 0), "sh_r": Vector3(30, 0, 30), "el_r": Vector3(50, 0, 0), "wr_r": Vector3(50, 0, 0)})
	poses["wave_wind"] = _P({"root_y": -0.15, "chest": Vector3(5, -60, 0), "sh_r": Vector3(120, 0, 70), "el_r": Vector3(20, 0, 0), "wr_r": Vector3(40, 0, 0), "sh_l": Vector3(30, 0, -40), "kn_l": Vector3(-25, 0, 0), "kn_r": Vector3(-25, 0, 0), "hip_l": Vector3(20, 0, 0)})
	poses["wave_slash"] = _P({"root_y": -0.3, "chest": Vector3(-25, 55, 0), "sh_r": Vector3(70, 0, -60), "el_r": Vector3(0, 0, 0), "wr_r": Vector3(50, 0, 0), "sh_l": Vector3(-20, 0, -50), "hip_r": Vector3(40, 0, 0), "kn_r": Vector3(-45, 0, 0), "hip_l": Vector3(-25, 0, 0)})
	poses["pull"] = _P({"root_y": -0.15, "chest": Vector3(10, 15, 0), "sh_l": Vector3(90, 0, -10), "el_l": Vector3(30, 0, 0), "wr_l": Vector3(-60, 0, 0), "sh_r": Vector3(-10, 0, 40), "el_r": Vector3(60, 0, 0), "wr_r": Vector3(60, 0, 0), "kn_l": Vector3(-25, 0, 0), "kn_r": Vector3(-25, 0, 0)})
	poses["kneel"] = _P({"root_y": -0.5, "chest": Vector3(-30, 0, 0), "head": Vector3(-25, 0, 0), "sh_l": Vector3(20, 0, -10), "el_l": Vector3(30, 0, 0), "sh_r": Vector3(55, 0, 10), "el_r": Vector3(40, 0, 0), "wr_r": Vector3(80, 0, 0), "hip_l": Vector3(85, 0, 0), "kn_l": Vector3(-95, 0, 0), "hip_r": Vector3(-10, 0, 0), "kn_r": Vector3(-115, 0, 0)})
	poses["rise"] = _P({"root_y": -0.2, "chest": Vector3(-10, 0, 0), "head": Vector3(10, 0, 0), "sh_r": Vector3(30, 0, 20), "el_r": Vector3(40, 0, 0), "kn_l": Vector3(-30, 0, 0), "kn_r": Vector3(-30, 0, 0), "hip_l": Vector3(25, 0, 0), "hip_r": Vector3(25, 0, 0)})
	poses["tear"] = _P({"chest": Vector3(15, 0, 0), "head": Vector3(15, 0, 0), "sh_l": Vector3(150, 0, -60), "el_l": Vector3(40, 0, 0), "sh_r": Vector3(150, 0, 60), "el_r": Vector3(40, 0, 0)})
	poses["roar"] = _P({"chest": Vector3(18, 0, 0), "head": Vector3(25, 0, 0), "sh_l": Vector3(30, 0, -95), "sh_r": Vector3(30, 0, 95), "el_l": Vector3(30, 0, 0), "el_r": Vector3(30, 0, 0), "wr_r": Vector3(60, 0, 0), "kn_l": Vector3(-12, 0, 0), "kn_r": Vector3(-12, 0, 0)})


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
	var sw := sin(_walk_phase * 3.2)
	for key in _cur:
		if key == "root_y":
			continue
		var r: Vector3 = _cur[key]
		match key:
			"hip_l": r.x += sw * 30.0 * w
			"hip_r": r.x -= sw * 30.0 * w
			"kn_l": r.x -= maxf(0.0, -sw) * 45.0 * w
			"kn_r": r.x -= maxf(0.0, sw) * 45.0 * w
			"sh_l": r.x -= sw * 12.0 * w
		(J[key] as Node3D).rotation_degrees = r
	(J["pelvis"] as Node3D).position.y = 1.12 + float(_cur.get("root_y", 0.0)) + absf(sin(_walk_phase * 3.2)) * 0.05 * w
