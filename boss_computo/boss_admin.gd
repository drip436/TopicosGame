extends CharacterBody3D
## Tercer jefe: "ADA-7, la Administradora del Núcleo" (Centro de Cómputo).
## Humanoide mitad androide de casi 5 m: la mitad derecha humana y la izquierda
## de cromo. Lleva un rack de servidores en la espalda del que cuelgan cables.
##
## Punto débil: la PIERNA ROBÓTICA IZQUIERDA. Los golpes dados junto a esa pierna
## hacen más daño y la van rompiendo (barra "PIERNA IZQUIERDA" en el HUD). Los
## golpes en el resto del cuerpo hacen poco daño.
##
##   Fase 1: espadas dobles (combos, estocada, giro), latigazos con cables
##           eléctricos de servidor, "scripts" que compilan armas en su mano
##           (espada grande, hacha, maza, martillo de guerra; cada una con su
##           ataque especial) y hechizos de área: electricidad, fuego y magia.
##   Fase 2: al romperse la pierna cae y se ARRASTRA persiguiendo al jugador
##           con ataques de área: golpes dobles, embestidas, tormenta de cables,
##           lluvia de armas invocadas y hechizos más seguidos.
##
## Sin puntos ciegos: si el jugador se queda detrás de ella o pegado a la pierna
## débil, responde con giros, barridos de cables en círculo, pisotones y un pulso
## electromagnético. Hay que pegar y salir, no quedarse ahí.
## El controlador de la pelea es compute_fight.gd.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float)
signal battle_started
signal phase_changed(phase: int)
signal defeated
signal leg_changed(ratio: float)

const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const FX := preload("res://boss_profesor/boss_fx.gd")
const BOSS_SKIN := preload("res://boss_profesor/boss_skin.gd")
## Modelo de Blender (arte/blender/jefe_ada.py). Si no existe se usan las primitivas.
const SKIN_PATH := "res://modelos/jefes/ada7.glb"

enum State { DORMANT, INTRO, FIGHT, BUSY, TRANSITION, DEAD }

@export var boss_name: String = "ADA-7, la Administradora del Núcleo"
@export var max_health: float = 2000.0
## Vida de la pierna izquierda: al llegar a 0 se rompe y empieza la fase 2.
@export var leg_max_health: float = 380.0
@export var damage_multiplier: float = 1.0
@export var move_speed: float = 3.0
## Multiplicadores de daño: pegarle a la pierna débil vs. al resto del cuerpo.
@export var weak_multiplier: float = 1.5
@export var armor_multiplier: float = 0.6
@export_range(0.0, 1.0) var electrocute_chance: float = 0.22

var state: int = State.DORMANT
var phase := 1
var health := 0.0
var leg_hp := 0.0
var target: Node3D
var fx_parent: Node
var arena_center := Vector3.ZERO
var arena_half := Vector2(18, 16)

# Modelo
var model: Node3D
var J := {}
var _skin: Node
var _meshes: Array[MeshInstance3D] = []
var m_flash: StandardMaterial3D
var m_eye: StandardMaterial3D
var m_core: StandardMaterial3D
var m_weak: StandardMaterial3D
var m_holo: StandardMaterial3D
var m_cable_glow: StandardMaterial3D
var _leg_lower: Array[Node3D] = []
var cables: Array = []          # [{root, segs:[Node3D]}]
var weapon_l: Node3D
var weapon_r: Node3D
var current_weapon := "dual"
var _weapon_uses := 0

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
var _crawl := false

# IA
var _rng := RandomNumberGenerator.new()
var _attack_id := 0
var _cooldown := 1.2
var _tracking := 1.0
var _lunge := Vector3.ZERO
var _kinematic := false
var _flash := 0.0
var _behind_t := 0.0
var _leg_t := 0.0
var _spell_cd := 3.0
var _script_cd := 4.0
var _cable_cd := 2.0
var _last: Array[String] = []
var _leg_spark_t := 0.0

const CODE_LINES := [
	"var arma = %s.new()", "arma.daño = 9999", "func atacar(jugador):", "while jugador.vivo:",
	"import %s", "sudo compilar --forzar", "if not piedad: return", "arma.equipar(mano_der)",
	"# TODO: no sentir nada", "for i in range(∞):", "assert(intruso == null)", "git push --force",
]


func _ready() -> void:
	_rng.randomize()
	add_to_group("boss")
	add_to_group("enemy")
	health = max_health
	leg_hp = leg_max_health
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var cap := CapsuleShape3D.new()
		cap.radius = 1.0
		cap.height = 4.4
		cs.shape = cap
		cs.position = Vector3(0, 2.2, 0)
		add_child(cs)
	_build_model()
	_define_poses()
	_cur = poses["plugged"].duplicate()
	_from = _cur.duplicate()
	_to = _cur.duplicate()


# =====================================================================
#  API
# =====================================================================

## Conectada al núcleo central, de espaldas, hasta que llega el jugador.
func place_dormant(pos: Vector3, look_point: Vector3) -> void:
	global_position = pos
	_face_instant(look_point)
	state = State.DORMANT
	_pose("plugged", 0.1)


func begin_intro() -> void:
	if state != State.DORMANT:
		return
	state = State.INTRO
	_kinematic = true
	_code_burst(global_position + Vector3(0, 4.6, 0), ["INTRUSO DETECTADO", "protocolo_defensa.start()", "desconectando del núcleo..."], Color(1.0, 0.35, 0.3))
	await _w(1.0)
	_pose("boot", 0.6)
	LFX.puff(fx_parent, global_position + Vector3(0, 3.2, 1.0), Color(0.6, 1.6, 2.6, 1), 40, 0.15, 5.0, 0.0)
	await _w(0.8)
	if _valid_target():
		var t0 := rotation.y
		var d := target.global_position - global_position
		var want := atan2(-d.x, -d.z)
		var tw := create_tween()
		tw.tween_method(func(v: float): rotation.y = lerp_angle(t0, want, v), 0.0, 1.0, 1.4).set_trans(Tween.TRANS_SINE)
	await _w(1.5)
	_pose("roar", 0.35)
	_set_eye(Color(1.0, 0.25, 0.2), 7.0)
	_shake(0.4)
	FX.shockwave(fx_parent, global_position, 10.0, Color(0.4, 0.8, 1.0), 0.7)
	FX.burst(fx_parent, global_position + Vector3(0, 3.5, 0), true, 60, 1.5)
	await _w(1.3)
	_set_eye(Color(0.35, 0.85, 1.0), 4.0)
	_pose("guard", 0.5)
	await _w(0.5)
	_kinematic = false
	state = State.FIGHT
	_cooldown = 0.6
	battle_started.emit()


func take_damage(amount: float, from_pos: Variant = null) -> void:
	if state in [State.DORMANT, State.INTRO, State.TRANSITION, State.DEAD]:
		return
	var dmg := amount
	if phase == 1:
		if from_pos is Vector3 and _is_leg_hit(from_pos):
			dmg = amount * weak_multiplier
			leg_hp = maxf(0.0, leg_hp - amount)
			leg_changed.emit(leg_hp / leg_max_health)
			_leg_t = maxf(_leg_t, 0.6)
			var knee: Vector3 = (J["kn_l"] as Node3D).global_position
			FX.burst(fx_parent, knee, true, 40, 1.0)
			LFX.puff(fx_parent, knee, Color(3.0, 1.6, 0.4, 1), 16, 0.15, 4.0, -6.0)
			m_weak.emission_energy_multiplier = lerpf(2.0, 8.0, 1.0 - leg_hp / leg_max_health)
		else:
			dmg = amount * armor_multiplier
			FX.burst(fx_parent, global_position + Vector3(0, 2.8, 0), true, 14, 0.6)
	health -= dmg
	_flash = 1.0
	damaged.emit(dmg)
	if phase == 1 and (leg_hp <= 0.0 or health <= max_health * 0.45):
		health = maxf(health, 1.0)
		health_changed.emit(health, max_health)
		_start_phase2()
		return
	if health <= 0.0:
		health = 0.0
		health_changed.emit(health, max_health)
		_die()
		return
	health_changed.emit(health, max_health)


func _is_leg_hit(from: Vector3) -> bool:
	var kl: Vector3 = (J["kn_l"] as Node3D).global_position
	var kr: Vector3 = (J["kn_r"] as Node3D).global_position
	var dl := Vector2(from.x - kl.x, from.z - kl.z).length()
	var dr := Vector2(from.x - kr.x, from.z - kr.z).length()
	return dl < 3.0 and dl < dr - 0.25


func debug_force_phase2() -> void:
	if phase == 1 and state != State.DEAD:
		leg_hp = 0.0
		leg_changed.emit(0.0)
		_start_phase2()


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
	_update_cables(delta)
	_flash = maxf(0.0, _flash - delta * 5.0)
	m_flash.emission_energy_multiplier = _flash * 2.5
	for m in _meshes:
		m.material_overlay = m_flash if _flash > 0.01 else null
	m_core.emission_energy_multiplier = 3.0 + sin(_anim_t * 3.0) * 1.0
	if phase == 1:
		m_weak.emission_energy_multiplier = maxf(m_weak.emission_energy_multiplier - delta * 1.5, lerpf(1.5, 5.0, 1.0 - leg_hp / leg_max_health) + sin(_anim_t * 6.0) * 0.6)
	else:
		_leg_spark_t -= delta
		if _leg_spark_t <= 0.0 and state != State.DEAD:
			_leg_spark_t = _rng.randf_range(0.3, 0.9)
			FX.burst(fx_parent, (J["kn_l"] as Node3D).global_position, true, 10, 0.5)
	if state in [State.FIGHT, State.BUSY]:
		_track_blind_spots(delta)
	if state == State.FIGHT:
		_think(delta)
	_spell_cd -= delta
	_script_cd -= delta
	_cable_cd -= delta


func _update_movement(delta: float) -> void:
	var desired := Vector3.ZERO
	if state == State.FIGHT and _valid_target():
		var to := target.global_position - global_position
		to.y = 0.0
		_turn_toward(target.global_position, delta, 1.0)
		var keep := 4.0 if not _crawl else 3.0
		if to.length() > keep:
			var spd := move_speed
			if _crawl:
				# Se arrastra a tirones: avanza cuando jala con los brazos
				spd = move_speed * 1.05 * (0.35 + 1.3 * maxf(0.0, sin(_walk_phase * 2.4)))
			desired = to.normalized() * spd
	elif state == State.BUSY and _valid_target():
		_turn_toward(target.global_position, delta, _tracking)
	desired += _lunge
	_lunge = _lunge.move_toward(Vector3.ZERO, 14.0 * delta)
	velocity.x = desired.x
	velocity.z = desired.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - 30.0 * delta
	move_and_slide()
	var flat := Vector2(velocity.x, velocity.z).length()
	_walk_amt = move_toward(_walk_amt, clampf(flat / move_speed, 0.0, 1.2), delta * 3.0)
	_walk_phase += delta * (maxf(flat, 1.2) * 0.75 if _crawl else flat * 0.8)


func _turn_toward(p: Vector3, delta: float, factor: float) -> void:
	if factor <= 0.0:
		return
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	var rate := 110.0 if phase == 1 else 150.0
	rotation.y = rotate_toward(rotation.y, atan2(-d.x, -d.z), deg_to_rad(rate) * factor * delta)


func _face_instant(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		rotation.y = atan2(-d.x, -d.z)


## Cuenta cuánto tiempo pasa el jugador detrás de ella o pegado a la pierna débil.
func _track_blind_spots(delta: float) -> void:
	if not _valid_target():
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var fwd := -global_basis.z
	var behind := d < 9.0 and fwd.dot(to.normalized()) < -0.3
	_behind_t = _behind_t + delta if behind else maxf(0.0, _behind_t - delta * 2.0)
	var kl: Vector3 = (J["kn_l"] as Node3D).global_position
	var near_leg := Vector2(target.global_position.x - kl.x, target.global_position.z - kl.z).length() < 3.2
	_leg_t = _leg_t + delta if near_leg else maxf(0.0, _leg_t - delta * 1.5)


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
	var pick := ""
	if phase == 1:
		if _leg_t > 2.2:
			pick = _weighted({"pulso": 4, "pisoton": 4, "giro": 3})
		elif _behind_t > 1.1:
			pick = _weighted({"giro": 5, "barrido_cables": 4, "pisoton": 2})
		elif current_weapon != "dual":
			pick = _weapon_special_if_in_range(d)
			if pick == "":
				pick = _weighted({"latigazo": 3 if _cable_cd <= 0.0 else 0, "hechizo": 2 if _spell_cd <= 0.0 else 0})
				if pick == "":
					_cooldown = 0.3
					return
		elif d < 5.5:
			pick = _weighted({"combo": 5, "estocada": 2, "giro": 1, "script": 3 if _script_cd <= 0.0 else 0,
				"latigazo": 1 if _cable_cd <= 0.0 else 0, "hechizo": 1 if _spell_cd <= 0.0 else 0})
		elif d < 11.0:
			pick = _weighted({"estocada": 3, "latigazo": 4 if _cable_cd <= 0.0 else 0, "script": 3 if _script_cd <= 0.0 else 0, "hechizo": 3 if _spell_cd <= 0.0 else 0})
		else:
			pick = _weighted({"latigazo": 3 if _cable_cd <= 0.0 else 0, "hechizo": 5 if _spell_cd <= 0.0 else 0, "script": 2 if _script_cd <= 0.0 else 0})
	else:
		if _behind_t > 0.9 or (_leg_t > 1.6 and d < 3.5):
			pick = _weighted({"barrido_cables": 4, "pulso": 3, "golpe_doble": 3})
		elif d < 6.0:
			pick = _weighted({"golpe_doble": 5, "barrido_cables": 2, "hechizo": 2 if _spell_cd <= 0.0 else 0})
		elif d < 14.0:
			pick = _weighted({"embestida": 4, "tormenta_cables": 3 if _cable_cd <= 0.0 else 0, "hechizo": 3 if _spell_cd <= 0.0 else 0, "lluvia_armas": 3 if _script_cd <= 0.0 else 0})
		else:
			pick = _weighted({"embestida": 3, "hechizo": 4 if _spell_cd <= 0.0 else 0, "lluvia_armas": 3 if _script_cd <= 0.0 else 0, "tormenta_cables": 2 if _cable_cd <= 0.0 else 0})
	if pick == "":
		_cooldown = 0.35
		return
	if _last.size() >= 2 and _last[-1] == pick and _last[-2] == pick and not pick.begins_with("arma_"):
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
		"combo": _atk_combo(id)
		"estocada": _atk_thrust(id)
		"giro": _atk_spin(id)
		"latigazo": _atk_lash(id)
		"barrido_cables": _atk_cable_ring(id)
		"script": _atk_script(id)
		"hechizo": _atk_spell(id)
		"pisoton": _atk_stomp(id)
		"pulso": _atk_pulse(id)
		"arma_espada": _atk_greatsword(id)
		"arma_hacha": _atk_axe(id)
		"arma_maza": _atk_mace(id)
		"arma_martillo": _atk_hammer(id)
		"golpe_doble": _atk_double_slam(id)
		"embestida": _atk_crawl_lunge(id)
		"tormenta_cables": _atk_cable_storm(id)
		"lluvia_armas": _atk_weapon_rain(id)


func _weapon_special_if_in_range(d: float) -> String:
	match current_weapon:
		"espada":
			return "arma_espada" if d < 7.5 else ""
		"hacha":
			return "arma_hacha" if d < 13.0 else ""
		"maza":
			return "arma_maza" if d < 6.5 else ""
		"martillo":
			return "arma_martillo" if d < 17.0 else ""
	return ""


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
	_cooldown = recovery * (0.75 if phase == 2 else 1.0)
	_tracking = 1.0
	_pose("crawl" if _crawl else "guard", 0.45)


func _x(id: int) -> bool:
	return id != _attack_id or state in [State.DEAD, State.TRANSITION]


# =====================================================================
#  Ataques — fase 1 (espadas dobles)
# =====================================================================

## Tres tajos cruzados alternando espadas.
func _atk_combo(id: int) -> void:
	var hits := _rng.randi_range(2, 3)
	for i in hits:
		var side := "l" if i % 2 == 0 else "r"
		_tracking = 1.0
		_pose("slash_wind_" + side, 0.32)
		await _w(0.5 if i == 0 else 0.32)
		if _x(id): return
		_tracking = 0.2
		_lunge = -global_basis.z * 6.0
		_pose("slash_" + side, 0.12)
		await _w(0.1)
		if _x(id): return
		_melee_arc(global_position, 5.0, 0.15, 14.0)
		_swing_fx(side)
		await _w(0.25)
		if _x(id): return
	await _w(0.7)
	_end(id, _rng.randf_range(0.8, 1.2))


## Estocada doble con embestida.
func _atk_thrust(id: int) -> void:
	_tracking = 1.0
	_pose("thrust_wind", 0.45)
	_flash_eyes()
	await _w(0.75)
	if _x(id): return
	_tracking = 0.1
	_pose("thrust", 0.1)
	_lunge = -global_basis.z * 15.0
	for k in 4:
		await _w(0.06)
		if _x(id): return
		_melee_arc(global_position + (-global_basis.z) * 2.0, 3.6, 0.3, 18.0)
	await _w(0.9)
	_end(id, 1.0)


## Giro de 360°: cubre la espalda (anti punto ciego).
func _atk_spin(id: int) -> void:
	_tracking = 0.0
	_pose("spin_wind", 0.35)
	await _w(0.6)
	if _x(id): return
	_pose("spin", 0.1)
	var t0 := rotation.y
	var tw := create_tween()
	tw.tween_method(func(v: float): rotation.y = t0 + v, 0.0, TAU, 0.55).set_trans(Tween.TRANS_SINE)
	await _w(0.25)
	if _x(id): return
	_melee_arc(global_position, 5.4, -1.0, 16.0)
	FX.shockwave(fx_parent, global_position, 5.4, Color(0.4, 0.85, 1.0), 0.4)
	await _w(0.9)
	_behind_t = 0.0
	_end(id, 0.9)


## Pisotón con la pierna derecha (si el jugador se esconde junto a sus piernas).
func _atk_stomp(id: int) -> void:
	_tracking = 0.3
	_pose("stomp_wind", 0.4)
	var ring := _warn(global_position, 4.6, Color(1.0, 0.6, 0.2), 0.7)
	await _w(0.7)
	if _x(id): return
	_pose("stomp", 0.08)
	_shake(0.45)
	_aoe(global_position, 4.6, 20.0)
	FX.shockwave(fx_parent, global_position, 4.6, Color(1.0, 0.6, 0.2), 0.45)
	LFX.puff(fx_parent, global_position + Vector3(0, 0.3, 0), Color(0.5, 0.48, 0.45, 0.8), 30, 0.6, 5.0, 2.0)
	_free(ring)
	await _w(0.9)
	_leg_t = 0.0
	_end(id, 0.8)


## Pulso electromagnético: castiga quedarse pegado a la pierna débil.
func _atk_pulse(id: int) -> void:
	_tracking = 0.0
	_pose("pulse_wind", 0.4)
	_set_eye(Color(1.0, 1.0, 1.0), 9.0)
	var ring := _warn(global_position, 6.0, Color(0.5, 0.85, 1.0), 0.85)
	await _w(0.85)
	if _x(id): return
	_pose("roar", 0.1)
	_shake(0.5)
	FX.shockwave(fx_parent, global_position + Vector3(0, 1.0, 0), 6.0, Color(0.5, 0.85, 1.0), 0.4)
	FX.burst(fx_parent, global_position + Vector3(0, 2.0, 0), true, 80, 2.0)
	_aoe(global_position, 6.0, 10.0, true)
	if _valid_target():
		var away := target.global_position - global_position
		away.y = 0.0
		if away.length() < 6.0 and "_knock" in target:
			target.set("_knock", away.normalized() * 16.0)
	_free(ring)
	_set_eye(Color(0.35, 0.85, 1.0), 4.0)
	await _w(1.0)
	_leg_t = 0.0
	_behind_t = 0.0
	_end(id, 1.0)


# =====================================================================
#  Cables de servidor
# =====================================================================

## Dos latigazos eléctricos con los cables, apuntando a donde estás.
func _atk_lash(id: int) -> void:
	_cable_cd = _rng.randf_range(3.0, 5.0)
	_tracking = 1.0
	_pose("cable_wind", 0.4)
	await _w(0.55)
	if _x(id): return
	for i in 2:
		if not _valid_target(): break
		var p := target.global_position + _lead(0.35)
		_pose("cable_lash", 0.15)
		_whip(i, p, 0.28, 15.0)
		await _w(0.55)
		if _x(id): return
		_pose("cable_wind", 0.25)
		await _w(0.15)
		if _x(id): return
	await _w(0.6)
	_end(id, 1.0)


## Barrido circular de cables: alcanza también la espalda.
func _atk_cable_ring(id: int) -> void:
	_cable_cd = _rng.randf_range(2.0, 4.0)
	_tracking = 0.0
	_pose("cable_wind", 0.4)
	var ring := _warn(global_position, 6.5, Color(0.4, 0.8, 1.0), 0.75)
	await _w(0.75)
	if _x(id): return
	_pose("cable_lash", 0.12)
	var n := 8
	for i in n:
		var a := TAU * i / n + rotation.y
		var p := global_position + Vector3(sin(a), 0, cos(a)) * 5.0
		_whip(i % cables.size(), p, 0.22, 0.0)
	await _w(0.24)
	if _x(id):
		_free(ring)
		return
	_aoe(global_position, 6.5, 14.0, true)
	FX.shockwave(fx_parent, global_position, 6.5, Color(0.4, 0.8, 1.0), 0.4)
	_free(ring)
	await _w(0.9)
	_behind_t = 0.0
	_leg_t = 0.0
	_end(id, 0.9)


## Fase 2: tormenta de cables en varios puntos alrededor del jugador.
func _atk_cable_storm(id: int) -> void:
	_cable_cd = _rng.randf_range(4.0, 6.0)
	_tracking = 0.6
	_pose("crawl_rear", 0.4)
	var spots: Array[Vector3] = []
	if _valid_target():
		spots.append(target.global_position)
		for i in 6:
			var a := _rng.randf() * TAU
			spots.append(_clamp(target.global_position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(2.5, 6.0)))
	var rings: Array = []
	for s in spots:
		rings.append(_warn(s, 1.9, Color(0.4, 0.8, 1.0), 0.9))
	await _w(0.9)
	if _x(id):
		for r in rings: _free(r)
		return
	for i in spots.size():
		_whip(i % cables.size(), spots[i], 0.2, 15.0)
		await _w(0.08)
		if _x(id): break
	for r in rings: _free(r)
	await _w(0.9)
	_end(id, 1.0)


## Latigazo: un cable sale de la espalda y azota el suelo en `p`.
func _whip(cable_idx: int, p: Vector3, extend: float, dmg: float) -> void:
	var anchor: Node3D = (cables[cable_idx % cables.size()] as Dictionary)["root"]
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	mi.material_override = m_cable_glow
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_parent.add_child(mi)
	var a0 := anchor.global_position
	var up := Vector3(0, 1, 0)
	var mid := (a0 + p) * 0.5
	var c1 := a0 + up * 4.5 + (p - a0) * 0.15
	var c2 := mid + up * 3.5
	var pts := func(k: float) -> PackedVector3Array:
		var out := PackedVector3Array()
		var n := 22
		for i in n + 1:
			var t := float(i) / n * k
			var q := (1.0 - t) * (1.0 - t) * (1.0 - t) * a0 + 3.0 * (1.0 - t) * (1.0 - t) * t * c1 + 3.0 * (1.0 - t) * t * t * c2 + t * t * t * p
			out.append(q)
		return out
	var draw := func(k: float) -> void:
		var arr: PackedVector3Array = pts.call(k)
		im.clear_surfaces()
		if arr.size() < 2:
			return
		for axis in [Vector3.UP, Vector3.RIGHT]:
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
			for i in arr.size():
				var dir := (arr[mini(i + 1, arr.size() - 1)] - arr[maxi(i - 1, 0)]).normalized()
				var side: Vector3 = dir.cross(axis)
				if side.length() < 0.01:
					side = dir.cross(Vector3.FORWARD)
				side = side.normalized() * 0.11
				im.surface_add_vertex(arr[i] - side)
				im.surface_add_vertex(arr[i] + side)
			im.surface_end()
	var tw := mi.create_tween()
	tw.tween_method(draw, 0.0, 1.0, extend)
	tw.tween_callback(func():
		FX.burst(fx_parent, p + Vector3(0, 0.2, 0), true, 24, 0.9)
		FX.scorch(fx_parent, p, 1.4, true)
		if dmg > 0.0:
			_aoe(p, 1.9, dmg, true)
		_shake(0.12))
	tw.tween_interval(0.25)
	tw.tween_method(draw, 1.0, 0.0, 0.3)
	tw.tween_callback(mi.queue_free)


# =====================================================================
#  Scripts: compila armas en su mano
# =====================================================================

func _atk_script(id: int) -> void:
	_script_cd = _rng.randf_range(10.0, 14.0)
	var kinds := ["espada", "hacha", "maza", "martillo"]
	var kind: String = kinds[_rng.randi() % kinds.size()]
	_tracking = 0.4
	_pose("cast", 0.4)
	var names := {"espada": "EspadaGrande", "hacha": "Hacha", "maza": "Maza", "martillo": "MartilloDeGuerra"}
	var lines: Array = []
	for i in 4:
		var l: String = CODE_LINES[_rng.randi() % CODE_LINES.size()]
		lines.append(l % names[kind] if l.contains("%s") else l)
	lines.push_front("compilar(%s)" % names[kind])
	_code_burst((J["wr_r"] as Node3D).global_position + Vector3(0, 0.5, 0), lines, Color(0.45, 1.0, 0.6))
	await _w(0.5)
	if _x(id): return
	_set_weapon(kind, true)
	await _w(1.1)
	if _x(id): return
	_end(id, 0.4)


func _set_weapon(kind: String, animate: bool) -> void:
	current_weapon = kind
	_weapon_uses = 2 if kind != "martillo" else 1
	for c in weapon_r.get_children():
		c.queue_free()
	var w := _make_weapon(kind)
	weapon_r.add_child(w)
	weapon_l.visible = kind == "dual"
	if animate:
		w.scale = Vector3.ONE * 0.05
		var holo: Array = []
		for mi in w.find_children("*", "MeshInstance3D", true, false):
			holo.append([mi, (mi as MeshInstance3D).material_override])
			(mi as MeshInstance3D).material_override = m_holo
		var tw := w.create_tween()
		tw.tween_property(w, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.35)
		tw.tween_callback(func():
			for h in holo:
				if is_instance_valid(h[0]):
					(h[0] as MeshInstance3D).material_override = h[1])
		LFX.puff(fx_parent, (J["wr_r"] as Node3D).global_position, Color(0.6, 2.0, 1.0, 1), 30, 0.15, 3.0, 0.0)


## Después de usar el arma invocada, vuelve a las espadas dobles.
func _use_weapon() -> void:
	_weapon_uses -= 1
	if _weapon_uses <= 0:
		_code_burst((J["wr_r"] as Node3D).global_position, ["arma.free()", "volver(espadas_dobles)"], Color(0.45, 1.0, 0.6))
		LFX.puff(fx_parent, (J["wr_r"] as Node3D).global_position, Color(0.6, 2.0, 1.0, 1), 30, 0.18, 3.0, 0.0)
		_set_weapon("dual", true)


## Espada grande: tajo enorme de casi 300°.
func _atk_greatsword(id: int) -> void:
	_tracking = 1.0
	_pose("gs_wind", 0.5)
	await _w(0.9)
	if _x(id): return
	_tracking = 0.0
	_pose("gs_swing", 0.18)
	_lunge = -global_basis.z * 4.0
	await _w(0.12)
	if _x(id): return
	_melee_arc(global_position, 7.2, -0.6, 24.0)
	FX.shockwave(fx_parent, global_position, 7.2, Color(0.5, 0.9, 1.0), 0.35)
	_shake(0.3)
	await _w(1.1)
	_use_weapon()
	_end(id, 1.1)


## Hacha: hachazo vertical que abre una grieta en línea recta.
func _atk_axe(id: int) -> void:
	_tracking = 1.0
	_pose("overhead_wind", 0.5)
	await _w(0.85)
	if _x(id): return
	_tracking = 0.0
	_pose("overhead", 0.12)
	await _w(0.1)
	if _x(id): return
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var start := global_position + fwd * 3.2
	_melee_arc(global_position, 5.0, 0.4, 22.0)
	_shake(0.4)
	for k in 7:
		var p := start + fwd * (k * 1.7)
		FX.burst(fx_parent, p, false, 16, 1.0)
		FX.scorch(fx_parent, p, 1.1, false)
		LFX.puff(fx_parent, p + Vector3(0, 0.3, 0), Color(2.2, 1.2, 0.4, 1), 10, 0.25, 4.0, 3.0)
		_aoe(p, 1.4, 18.0)
		await _w(0.07)
		if _x(id): return
	await _w(0.9)
	_use_weapon()
	_end(id, 1.0)


## Maza: dos golpes al suelo con ondas de choque.
func _atk_mace(id: int) -> void:
	for i in 2:
		_tracking = 1.0
		_pose("overhead_wind", 0.4)
		await _w(0.65 if i == 0 else 0.45)
		if _x(id): return
		_tracking = 0.0
		_pose("overhead", 0.1)
		_lunge = -global_basis.z * 5.0
		await _w(0.1)
		if _x(id): return
		var p := global_position + (-global_basis.z) * 4.0
		p.y = global_position.y
		_aoe(p, 3.6, 19.0)
		FX.shockwave(fx_parent, p, 3.6, Color(1.0, 0.7, 0.3), 0.4)
		FX.burst(fx_parent, p, false, 30, 1.2)
		_shake(0.35)
		await _w(0.35)
		if _x(id): return
	await _w(0.8)
	_use_weapon()
	_end(id, 1.0)


## Martillo de guerra: salta y cae sobre el jugador (área grande).
func _atk_hammer(id: int) -> void:
	if not _valid_target():
		_end(id, 0.5)
		return
	_tracking = 1.0
	_pose("hammer_wind", 0.5)
	await _w(0.6)
	if _x(id): return
	var dest := _clamp(target.global_position)
	var ring := _warn(dest, 6.5, Color(1.0, 0.45, 0.2), 1.2)
	_kinematic = true
	var start := global_position
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p := start.lerp(dest, t)
		p.y = start.y + sin(t * PI) * 6.0
		global_position = p, 0.0, 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	_face_instant(dest)
	await _w(0.65)
	if _x(id):
		_free(ring)
		return
	_pose("hammer_slam", 0.2)
	await _w(0.4)
	if _x(id):
		_free(ring)
		return
	_free(ring)
	_shake(0.7)
	_aoe(global_position, 6.5, 30.0)
	FX.shockwave(fx_parent, global_position, 6.5, Color(1.0, 0.45, 0.2), 0.5)
	FX.burst(fx_parent, global_position, false, 70, 2.2)
	FX.scorch(fx_parent, global_position + (-global_basis.z) * 2.0, 3.0, false)
	_kinematic = false
	await _w(1.3)
	_use_weapon()
	_end(id, 1.2)


# =====================================================================
#  Hechizos de área
# =====================================================================

func _atk_spell(id: int) -> void:
	_spell_cd = _rng.randf_range(6.0, 9.0) * (0.7 if phase == 2 else 1.0)
	var kind: String = ["electricidad", "fuego", "magia"][_rng.randi() % 3]
	_tracking = 0.6
	_pose("crawl_cast" if _crawl else "cast", 0.4)
	var col := {"electricidad": Color(0.5, 0.8, 1.0), "fuego": Color(1.0, 0.5, 0.15), "magia": Color(0.75, 0.35, 1.0)}[kind] as Color
	_code_burst((J["wr_l"] as Node3D).global_position + Vector3(0, 0.6, 0), ["hechizo.%s()" % kind, "area = Area.new(r=%d)" % _rng.randi_range(3, 9)], col)
	var circle := FX.ground_ring(fx_parent, global_position, 3.0, col, 2.5)
	await _w(0.6)
	_free(circle)
	if _x(id): return
	match kind:
		"electricidad":
			await _spell_lightning(id)
		"fuego":
			await _spell_fire(id)
		_:
			await _spell_magic(id)
	if _x(id): return
	await _w(0.6)
	_end(id, 1.0)


## Rayos que caen del techo sobre círculos de aviso.
func _spell_lightning(id: int) -> void:
	var spots: Array[Vector3] = []
	if _valid_target():
		spots.append(target.global_position)
	for i in (5 if phase == 1 else 8):
		var c := target.global_position if _valid_target() else global_position
		var a := _rng.randf() * TAU
		spots.append(_clamp(c + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(2.5, 8.0)))
	var rings: Array = []
	for s in spots:
		rings.append(_warn(s, 2.2, Color(0.5, 0.8, 1.0), 0.95))
	await _w(0.95)
	for i in spots.size():
		if _x(id): break
		var s: Vector3 = spots[i]
		FX.spawn_bolt(fx_parent, s + Vector3(_rng.randf_range(-1, 1), 10.0, _rng.randf_range(-1, 1)), s, _rng, 0.3)
		FX.scorch(fx_parent, s, 1.6, true)
		_aoe(s, 2.2, 18.0, true)
		_free(rings[i])
		await _w(0.09)
	for r in rings: _free(r)


## Anillo de fuego que se expande desde ella: hay que rodar a través de él.
func _spell_fire(id: int) -> void:
	var c := global_position
	var ring := FX.ground_ring(fx_parent, c, 1.0, Color(1.0, 0.45, 0.1), 3.5)
	var m: ShaderMaterial = ring.material_override
	m.set_shader_parameter("ring_width", 0.05)
	m.set_shader_parameter("fill_alpha", 0.0)
	var max_r := 16.0
	var dur := 1.6
	var t := 0.0
	var hit := false
	var fire_t := 0.0
	while t < dur:
		await get_tree().physics_frame
		if _x(id) or not is_instance_valid(ring):
			break
		var dt := get_physics_process_delta_time()
		t += dt
		var r := lerpf(1.0, max_r, t / dur)
		ring.scale = Vector3(r, 1, r)
		fire_t -= dt
		if fire_t <= 0.0:
			fire_t = 0.12
			for k in 6:
				var a := _rng.randf() * TAU
				LFX.puff(fx_parent, c + Vector3(cos(a), 0, sin(a)) * r + Vector3(0, 0.4, 0), Color(3.0, 1.3, 0.3, 1), 6, 0.45, 2.5, 2.5)
		if not hit and _valid_target():
			var d := _flat(target.global_position, c)
			if absf(d - r) < 1.0 and target.global_position.y < c.y + 1.8:
				var before: float = float(target.get("hp")) if "hp" in target else 0.0
				_hit(16.0, c, false, true)
				hit = "hp" in target and float(target.get("hp")) < before
	if is_instance_valid(ring):
		ring.queue_free()


## Tres círculos mágicos que persiguen al jugador y estallan.
func _spell_magic(id: int) -> void:
	for i in (3 if phase == 1 else 4):
		if _x(id) or not _valid_target():
			return
		var p := _clamp(target.global_position + _lead(0.6))
		var ring := _warn(p, 3.2, Color(0.75, 0.35, 1.0), 1.05)
		await _w(1.05 if i == 0 else 0.75)
		if _x(id):
			_free(ring)
			return
		_free(ring)
		_magic_pillar(p)
		_aoe(p, 3.2, 22.0)
		await _w(0.1)


func _magic_pillar(p: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.6
	cm.bottom_radius = 3.0
	cm.height = 9.0
	cm.material = LFX.emissive(Color(0.75, 0.35, 1.0), 1.6, 0.32)
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_parent.add_child(mi)
	mi.global_position = p + Vector3(0, 4.5, 0)
	mi.scale = Vector3(0.2, 1, 0.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.12)
	tw.tween_property(mi, "scale", Vector3(0.01, 1.2, 0.01), 0.4)
	tw.tween_callback(mi.queue_free)
	LFX.puff(fx_parent, p + Vector3(0, 0.5, 0), Color(1.8, 0.8, 3.0, 1), 30, 0.25, 6.0, 0.0)
	_shake(0.2)


# =====================================================================
#  Fase 2: se arrastra
# =====================================================================

func _start_phase2() -> void:
	state = State.TRANSITION
	_attack_id += 1
	_kinematic = true
	_lunge = Vector3.ZERO
	phase = 2
	leg_hp = 0.0
	leg_changed.emit(0.0)
	_set_weapon("dual", false)
	_code_burst(global_position + Vector3(0, 4.5, 0), ["ERROR: pierna_izq.dll no encontrado", "estabilidad = 0", "modo_supervivencia = true"], Color(1.0, 0.3, 0.25))
	_pose("stagger", 0.25)
	_shake(0.6)
	var knee: Vector3 = (J["kn_l"] as Node3D).global_position
	FX.burst(fx_parent, knee, true, 120, 2.5)
	LFX.puff(fx_parent, knee, Color(3.0, 1.5, 0.4, 1), 40, 0.3, 6.0, -5.0)
	LFX.smoke(fx_parent, knee, 0.6)
	# La parte baja de la pierna se desprende y cae
	_drop_leg_part()
	await _w(0.6)
	_pose("fall", 0.7)
	await _w(0.9)
	_crawl = true
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs and cs.shape is CapsuleShape3D:
		var cap := CapsuleShape3D.new()
		cap.radius = 1.2
		cap.height = 2.6
		cs.shape = cap
		cs.position = Vector3(0, 1.3, 0)
	FX.shockwave(fx_parent, global_position, 9.0, Color(1.0, 0.3, 0.25), 0.6)
	_shake(0.5)
	await _w(0.6)
	_pose("crawl_rear", 0.5)
	_set_eye(Color(1.0, 0.2, 0.15), 8.0)
	m_core.emission = Color(1.0, 0.2, 0.15)
	await _w(0.9)
	phase_changed.emit(2)
	_pose("crawl", 0.5)
	await _w(0.5)
	_kinematic = false
	state = State.FIGHT
	_cooldown = 0.6
	_behind_t = 0.0
	_leg_t = 0.0


func _drop_leg_part() -> void:
	for n in _leg_lower:
		var mi_list := n.find_children("*", "MeshInstance3D", true, false)
		if n is MeshInstance3D:
			mi_list.append(n)
		for mi in mi_list:
			var gt := (mi as MeshInstance3D).global_transform
			var copy := MeshInstance3D.new()
			copy.mesh = (mi as MeshInstance3D).mesh
			copy.material_override = (mi as MeshInstance3D).material_override
			fx_parent.add_child(copy)
			copy.global_transform = gt
			var tw := copy.create_tween()
			var land := gt.origin
			land.y = maxf(0.25, land.y * 0.15)
			tw.tween_property(copy, "global_position", land + Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6)), 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(copy, "rotation", copy.rotation + Vector3(_rng.randf_range(-1.4, 1.4), 0, _rng.randf_range(-1.4, 1.4)), 0.6)
		n.visible = false
	if _skin:
		_skin.hide_bones(["kn_l"])


## Se levanta sobre los brazos y golpea el suelo con ambos puños.
func _atk_double_slam(id: int) -> void:
	_tracking = 1.0
	_pose("crawl_rear", 0.45)
	await _w(0.7)
	if _x(id): return
	_tracking = 0.0
	_pose("crawl_slam", 0.12)
	_lunge = -global_basis.z * 5.0
	await _w(0.12)
	if _x(id): return
	var p := global_position + (-global_basis.z) * 2.5
	p.y = global_position.y
	_aoe(p, 6.0, 24.0)
	FX.shockwave(fx_parent, p, 6.0, Color(1.0, 0.35, 0.25), 0.5)
	FX.burst(fx_parent, p, false, 50, 1.8)
	_shake(0.55)
	await _w(1.0)
	_behind_t = 0.0
	_leg_t = 0.0
	_end(id, 0.9)


## Se arrastra a toda velocidad hacia el jugador y remata con un golpe de área.
func _atk_crawl_lunge(id: int) -> void:
	_tracking = 1.0
	_pose("crawl_rear", 0.35)
	await _w(0.55)
	if _x(id): return
	_tracking = 0.35
	_pose("crawl", 0.15)
	var t := 0.0
	while t < 1.1:
		await get_tree().physics_frame
		if _x(id): return
		t += get_physics_process_delta_time()
		_lunge = -global_basis.z * 13.0
		_walk_phase += get_physics_process_delta_time() * 8.0
		if _valid_target() and _flat(target.global_position, global_position) < 3.2:
			break
	_lunge = Vector3.ZERO
	_pose("crawl_slam", 0.12)
	await _w(0.12)
	if _x(id): return
	_aoe(global_position + (-global_basis.z) * 2.0, 4.5, 22.0)
	FX.shockwave(fx_parent, global_position + (-global_basis.z) * 2.0, 4.5, Color(1.0, 0.35, 0.25), 0.45)
	_shake(0.45)
	await _w(1.0)
	_end(id, 1.0)


## Scripts en fase 2: compila armas sobre el jugador que caen como lanzas.
func _atk_weapon_rain(id: int) -> void:
	_script_cd = _rng.randf_range(7.0, 10.0)
	_tracking = 0.5
	_pose("crawl_cast", 0.4)
	_code_burst(global_position + Vector3(0, 3.5, 0), ["for arma in arsenal:", "    arma.caer_sobre(jugador)", "lluvia = true"], Color(0.45, 1.0, 0.6))
	await _w(0.5)
	var kinds := ["espada", "hacha", "maza", "martillo", "espada"]
	for i in kinds.size():
		if _x(id) or not _valid_target(): break
		var p := _clamp(target.global_position + _lead(0.5))
		_falling_weapon(kinds[i], p)
		await _w(0.42)
	if _x(id): return
	await _w(1.2)
	_end(id, 1.0)


func _falling_weapon(kind: String, p: Vector3) -> void:
	var ring := _warn(p, 2.1, Color(0.45, 1.0, 0.6), 1.0)
	var w := _make_weapon(kind)
	fx_parent.add_child(w)
	w.global_position = p + Vector3(0, 9.5, 0)
	w.rotation_degrees = Vector3(0, _rng.randf() * 360.0, 0)
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = m_holo
	var tw := w.create_tween()
	tw.tween_interval(0.75)
	tw.tween_property(w, "global_position", p + Vector3(0, 2.0, 0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if is_instance_valid(ring):
			ring.queue_free()
		FX.burst(fx_parent, p, false, 24, 1.0)
		LFX.puff(fx_parent, p + Vector3(0, 0.4, 0), Color(0.6, 2.0, 1.0, 1), 16, 0.2, 4.0, 0.0)
		_aoe(p, 2.1, 20.0)
		_shake(0.2))
	tw.tween_interval(0.8)
	tw.tween_property(w, "scale", Vector3.ONE * 0.01, 0.4)
	tw.tween_callback(w.queue_free)


# =====================================================================
#  Muerte
# =====================================================================

func _die() -> void:
	state = State.DEAD
	_attack_id += 1
	_kinematic = true
	_lunge = Vector3.ZERO
	defeated.emit()
	_code_burst(global_position + Vector3(0, 3.0, 0), ["apagando...", "respaldo: 0%", "adiós, administrador"], Color(0.6, 0.6, 0.65))
	_pose("dead", 1.2)
	FX.burst(fx_parent, global_position + Vector3(0, 1.5, 0), true, 100, 2.5)
	await _w(1.2)
	var tw := create_tween()
	tw.tween_method(func(v: float):
		m_eye.emission_energy_multiplier = v
		m_core.emission_energy_multiplier = v, 5.0, 0.0, 2.5)
	m_cable_glow.emission_energy_multiplier = 0.0


# =====================================================================
#  Utilidades de combate
# =====================================================================

func _valid_target() -> bool:
	return target != null and is_instance_valid(target) and not ("is_dead" in target and target.is_dead)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _clamp(p: Vector3) -> Vector3:
	var l := p - arena_center
	l.x = clampf(l.x, -arena_half.x, arena_half.x)
	l.z = clampf(l.z, -arena_half.y, arena_half.y)
	return Vector3(arena_center.x + l.x, arena_center.y, arena_center.z + l.z)


## Predicción del movimiento del jugador.
func _lead(t: float) -> Vector3:
	if _valid_target() and target is CharacterBody3D:
		var v := (target as CharacterBody3D).velocity
		return Vector3(v.x, 0, v.z) * t
	return Vector3.ZERO


func _hit(dmg: float, from: Vector3, electric := false, burn := false) -> void:
	if not _valid_target() or not target.has_method("take_damage"):
		return
	var before: float = float(target.get("hp")) if "hp" in target else 0.0
	target.take_damage(dmg * damage_multiplier, from)
	var landed: bool = "hp" in target and float(target.get("hp")) < before
	if landed and target.has_method("apply_status"):
		if electric and _rng.randf() < electrocute_chance:
			target.apply_status("electrocutado", 2.0)
		if burn:
			target.apply_status("quemadura", 5.0)


func _melee_arc(center: Vector3, reach: float, dot_min: float, dmg: float, electric := false) -> void:
	if not _valid_target():
		return
	var to := target.global_position - center
	if absf(to.y) > 3.5:
		return
	to.y = 0.0
	var fwd := -global_basis.z
	fwd.y = 0.0
	if to.length() < reach and (to.length() < 1.8 or fwd.normalized().dot(to.normalized()) > dot_min):
		_hit(dmg, center, electric)
		FX.burst(fx_parent, target.global_position + Vector3(0, 1.1, 0), true, 14, 0.6)
		_shake(0.25)


func _aoe(center: Vector3, radius: float, dmg: float, electric := false) -> void:
	if not _valid_target():
		return
	var to := target.global_position - center
	if absf(to.y) < 2.5 and Vector2(to.x, to.z).length() < radius:
		_hit(dmg, center, electric)


## Círculo de aviso que se llena en `time` segundos.
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


func _swing_fx(side: String) -> void:
	var w: Node3D = J["wr_" + side]
	LFX.puff(fx_parent, w.global_position + (-global_basis.z) * 1.5, Color(0.8, 1.8, 2.6, 1), 10, 0.12, 3.0, 0.0)


## Texto de código flotando en espiral (los "scripts" de ADA-7).
func _code_burst(pos: Vector3, lines: Array, col: Color) -> void:
	for i in lines.size():
		var l := Label3D.new()
		l.text = String(lines[i])
		l.font_size = 48
		l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = col
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.outline_size = 8
		l.shaded = false
		l.no_depth_test = false
		fx_parent.add_child(l)
		var a := TAU * i / maxf(1.0, lines.size()) + _rng.randf() * 0.5
		var start := pos + Vector3(cos(a) * 1.2, i * 0.35, sin(a) * 1.2)
		l.global_position = start
		l.modulate.a = 0.0
		var tw := l.create_tween()
		tw.tween_interval(i * 0.12)
		tw.tween_property(l, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(l, "global_position", start + Vector3(cos(a + 1.2) * 0.8, 1.6, sin(a + 1.2) * 0.8), 1.8)
		tw.tween_property(l, "modulate:a", 0.0, 0.5)
		tw.tween_callback(l.queue_free)


func _flash_eyes() -> void:
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


var _bm: BoxMesh
var _collect := true   # las armas (que se crean y destruyen) no entran en _meshes
var _sm: SphereMesh
var _cm: CylinderMesh


func _box(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return _add(p, _bm, size, pos, m, rot)


func _sph(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return _add(p, _sm, size, pos, m, rot)


func _cyl(p: Node3D, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return _add(p, _cm, Vector3(r * 2.0, h, r * 2.0), pos, m, rot)


func _add(p: Node3D, mesh: Mesh, size: Vector3, pos: Vector3, m: Material, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = size
	p.add_child(mi)
	if _collect:
		_meshes.append(mi)
	return mi


func _joint(parent: Node3D, key: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = key
	j.position = pos
	parent.add_child(j)
	J[key] = j
	return j


func _build_model() -> void:
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
	var skin := _mat(Color(0.86, 0.72, 0.64), 0.55)
	var suit := _mat(Color(0.07, 0.07, 0.09), 0.45, 0.2)
	var chrome := _mat(Color(0.72, 0.74, 0.78), 0.22, 0.95)
	var dark := _mat(Color(0.12, 0.12, 0.14), 0.4, 0.8)
	var hair := _mat(Color(0.12, 0.1, 0.14), 0.6)
	var rack := _mat(Color(0.1, 0.1, 0.12), 0.5, 0.6)
	m_eye = _glow(Color(0.35, 0.85, 1.0), 4.0)
	m_core = _glow(Color(0.3, 0.85, 1.0), 3.0)
	m_weak = _glow(Color(1.0, 0.45, 0.1), 2.0)
	var line := _glow(Color(0.3, 0.85, 1.0), 2.0)
	var led_g := _glow(Color(0.3, 1.0, 0.4), 3.0)
	var led_r := _glow(Color(1.0, 0.25, 0.2), 3.0)
	m_cable_glow = _glow(Color(0.35, 0.75, 1.0), 2.5)
	m_cable_glow.albedo_color = Color(0.08, 0.1, 0.14)
	m_holo = _glow(Color(0.4, 1.0, 0.6), 2.5)
	m_holo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_holo.albedo_color = Color(0.4, 1.0, 0.6, 0.45)
	m_holo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_flash = StandardMaterial3D.new()
	m_flash.albedo_color = Color(1, 1, 1, 0.35)
	m_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_flash.emission_enabled = true
	m_flash.emission = Color(0.8, 0.95, 1.0)

	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var pelvis := _joint(model, "pelvis", Vector3(0, 2.25, 0))
	_box(pelvis, Vector3(0.95, 0.45, 0.6), Vector3.ZERO, suit)
	_box(pelvis, Vector3(0.45, 0.46, 0.62), Vector3(-0.26, 0, 0), chrome)
	var spine := _joint(pelvis, "spine", Vector3(0, 0.2, 0))
	_box(spine, Vector3(0.72, 0.62, 0.45), Vector3(0, 0.3, 0), suit)
	for k in 4:
		_box(spine, Vector3(0.36, 0.06, 0.47), Vector3(-0.18, 0.1 + k * 0.14, 0), chrome)
	var chest := _joint(spine, "chest", Vector3(0, 0.6, 0))
	_box(chest, Vector3(1.05, 0.8, 0.62), Vector3(0, 0.4, 0), suit)
	_box(chest, Vector3(0.52, 0.82, 0.64), Vector3(-0.27, 0.4, 0), chrome)
	for k in 4:
		_box(chest, Vector3(0.5, 0.04, 0.05), Vector3(-0.27, 0.15 + k * 0.17, -0.33), dark)
	_box(chest, Vector3(0.03, 0.6, 0.02), Vector3(0.25, 0.4, -0.32), line)
	_box(chest, Vector3(0.4, 0.03, 0.02), Vector3(0.1, 0.62, -0.32), line)
	_cyl(chest, 0.13, 0.06, Vector3(0, 0.45, -0.33), m_core, Vector3(90, 0, 0))
	# Rack de servidores en la espalda
	_box(chest, Vector3(0.85, 1.0, 0.5), Vector3(0, 0.45, 0.55), rack)
	for k in 6:
		_box(chest, Vector3(0.75, 0.03, 0.02), Vector3(0, 0.08 + k * 0.15, 0.81), dark)
		_box(chest, Vector3(0.04, 0.04, 0.02), Vector3(-0.3 + (k % 3) * 0.08, 0.1 + k * 0.15, 0.82), led_g if k % 2 == 0 else led_r)
	var neck := _joint(chest, "neck", Vector3(0, 0.85, 0))
	_cyl(neck, 0.14, 0.3, Vector3(0, 0.12, 0), suit)
	_cyl(neck, 0.08, 0.3, Vector3(-0.07, 0.12, 0), chrome)
	var head := _joint(neck, "head", Vector3(0, 0.27, 0))
	# Mitad humana (derecha) y mitad androide (izquierda)
	_sph(head, Vector3(0.48, 0.6, 0.54), Vector3(0.02, 0.3, 0), skin)
	_sph(head, Vector3(0.27, 0.62, 0.56), Vector3(-0.13, 0.3, 0), chrome)
	_box(head, Vector3(0.02, 0.5, 0.02), Vector3(0.0, 0.3, -0.27), line)
	_sph(head, Vector3(0.09, 0.05, 0.03), Vector3(0.11, 0.36, -0.255), _mat(Color(0.95, 0.95, 0.95), 0.3))
	_sph(head, Vector3(0.04, 0.04, 0.03), Vector3(0.11, 0.36, -0.27), _mat(Color(0.15, 0.1, 0.08), 0.3))
	_box(head, Vector3(0.14, 0.04, 0.03), Vector3(-0.12, 0.36, -0.275), m_eye)
	_box(head, Vector3(0.12, 0.02, 0.02), Vector3(0.06, 0.16, -0.26), _mat(Color(0.55, 0.3, 0.3), 0.5))
	# Pelo del lado humano, cables del lado androide
	_sph(head, Vector3(0.36, 0.42, 0.58), Vector3(0.1, 0.48, 0.04), hair)
	_box(head, Vector3(0.2, 0.75, 0.2), Vector3(0.18, 0.05, 0.22), hair, Vector3(10, 0, -6))
	for k in 4:
		_cyl(head, 0.025, 0.7, Vector3(-0.16 - k * 0.03, 0.2, 0.15 + k * 0.05), dark, Vector3(25 + k * 6, 0, 20))
	# Brazos: derecho humano con guantelete, izquierdo de cromo
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var robot: bool = side == "l"
		var sh := _joint(chest, "sh_" + side, Vector3(sx * 0.68, 0.7, 0))
		_sph(sh, Vector3.ONE * 0.42, Vector3.ZERO, chrome if robot else suit)
		_box(sh, Vector3(0.5, 0.25, 0.55), Vector3(sx * 0.05, 0.12, 0), chrome if robot else dark)
		_box(sh, Vector3(0.24, 0.85, 0.26), Vector3(0, -0.45, 0), chrome if robot else suit)
		if robot:
			_cyl(sh, 0.04, 0.8, Vector3(0.0, -0.45, -0.16), dark)
		var el := _joint(sh, "el_" + side, Vector3(0, -0.95, 0))
		_sph(el, Vector3.ONE * 0.26, Vector3.ZERO, line if robot else suit)
		_box(el, Vector3(0.24, 0.85, 0.26), Vector3(0, -0.43, 0), chrome if robot else dark)
		var wr := _joint(el, "wr_" + side, Vector3(0, -0.9, 0))
		_box(wr, Vector3(0.2, 0.22, 0.24), Vector3(0, -0.08, 0), dark if robot else skin)
		for f in 3:
			_box(wr, Vector3(0.05, 0.2, 0.05), Vector3(-0.06 + f * 0.06, -0.24, -0.05), chrome if robot else skin, Vector3(25, 0, 0))
	weapon_l = Node3D.new()
	weapon_l.position = Vector3(0, -0.22, 0)
	(J["wr_l"] as Node3D).add_child(weapon_l)
	weapon_l.add_child(_make_weapon("blade"))
	weapon_r = Node3D.new()
	weapon_r.position = Vector3(0, -0.22, 0)
	(J["wr_r"] as Node3D).add_child(weapon_r)
	weapon_r.add_child(_make_weapon("blade"))
	# Piernas: derecha con traje y bota, izquierda robótica (punto débil)
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var robot: bool = side == "l"
		var hip := _joint(pelvis, "hip_" + side, Vector3(sx * 0.3, -0.1, 0))
		_sph(hip, Vector3.ONE * 0.4, Vector3.ZERO, chrome if robot else suit)
		_box(hip, Vector3(0.36, 1.0, 0.4), Vector3(0, -0.52, 0), chrome if robot else suit)
		if robot:
			for px: float in [-0.14, 0.14]:
				_cyl(hip, 0.045, 0.9, Vector3(px, -0.5, -0.22), dark)
			_box(hip, Vector3(0.1, 0.6, 0.02), Vector3(0, -0.5, -0.215), m_weak)
		var kn := _joint(hip, "kn_" + side, Vector3(0, -1.05, 0))
		if robot:
			# Núcleo de la rodilla: brilla más conforme se daña
			_sph(kn, Vector3.ONE * 0.36, Vector3.ZERO, dark)
			_sph(kn, Vector3.ONE * 0.22, Vector3(0, 0, -0.1), m_weak)
		else:
			_sph(kn, Vector3.ONE * 0.32, Vector3.ZERO, suit)
		var lower := Node3D.new()
		kn.add_child(lower)
		_box(lower, Vector3(0.32, 1.0, 0.36), Vector3(0, -0.5, 0), chrome if robot else dark)
		if robot:
			_cyl(lower, 0.05, 0.85, Vector3(0, -0.5, 0.2), dark)
			_box(lower, Vector3(0.08, 0.5, 0.02), Vector3(0, -0.5, -0.19), m_weak)
		var an := _joint(lower, "an_" + side, Vector3(0, -1.0, 0))
		_box(an, Vector3(0.38, 0.18, 0.7), Vector3(0, -0.06, -0.12), dark if robot else suit)
		if robot:
			for f in 3:
				_box(an, Vector3(0.08, 0.08, 0.3), Vector3(-0.12 + f * 0.12, -0.08, -0.55), chrome)
			_leg_lower.append(lower)
	# Cables de servidor que cuelgan del rack
	for k in 5:
		var root := Node3D.new()
		# (justo detrás del rack del modelo de Blender)
		root.position = Vector3(-0.24 + k * 0.12, 0.05, 0.5)
		chest.add_child(root)
		var segs: Array = []
		var parent := root
		for s in 7:
			var seg := Node3D.new()
			seg.position = Vector3(0, -0.42, 0) if s > 0 else Vector3.ZERO
			parent.add_child(seg)
			_cyl(seg, 0.045, 0.44, Vector3(0, -0.21, 0), rack)
			if s % 2 == 0:
				_cyl(seg, 0.05, 0.05, Vector3(0, -0.05, 0), m_cable_glow)
			segs.append(seg)
			parent = seg
		cables.append({"root": root, "segs": segs, "ph": k * 1.3})
	for mi in _meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Modelo de Blender: las espadas y los cables del rack siguen siendo los del código
	var keep: Array = [weapon_l, weapon_r]
	for c in cables:
		keep.append(c["root"])
	_skin = BOSS_SKIN.apply(self, model, J, SKIN_PATH, {"ojos": m_eye, "nucleo": m_core, "debil": m_weak}, keep)
	if _skin:
		for mi in _skin.meshes:
			_meshes.append(mi)


func _make_weapon(kind: String) -> Node3D:
	var prev := _collect
	_collect = false
	var w := Node3D.new()
	w.name = "Arma"
	var steel := _mat(Color(0.75, 0.77, 0.82), 0.2, 0.95)
	var dark := _mat(Color(0.1, 0.1, 0.12), 0.5, 0.6)
	var edge := _glow(Color(0.35, 0.85, 1.0), 2.5)
	var grip := _mat(Color(0.15, 0.1, 0.08), 0.8)
	match kind:
		"blade":
			_box(w, Vector3(0.42, 0.08, 0.14), Vector3(0, 0, 0), dark)
			_box(w, Vector3(0.07, 2.3, 0.2), Vector3(0, -1.2, 0), steel)
			_box(w, Vector3(0.03, 2.2, 0.04), Vector3(0, -1.2, -0.11), edge)
		"espada":
			_box(w, Vector3(0.8, 0.14, 0.2), Vector3(0, 0, 0), dark)
			_box(w, Vector3(0.1, 3.6, 0.48), Vector3(0, -1.9, 0), steel)
			_box(w, Vector3(0.04, 3.5, 0.05), Vector3(0, -1.9, -0.25), edge)
			_box(w, Vector3(0.04, 3.5, 0.05), Vector3(0, -1.9, 0.25), edge)
		"hacha":
			_cyl(w, 0.07, 3.2, Vector3(0, -1.3, 0), grip)
			_box(w, Vector3(0.1, 1.1, 1.2), Vector3(0, -2.55, -0.62), steel)
			_box(w, Vector3(0.12, 1.2, 0.08), Vector3(0, -2.55, -1.22), edge)
			_box(w, Vector3(0.16, 0.5, 0.3), Vector3(0, -2.55, 0), dark)
		"maza":
			_cyl(w, 0.07, 2.4, Vector3(0, -1.0, 0), grip)
			_sph(w, Vector3.ONE * 0.95, Vector3(0, -2.35, 0), dark)
			for i in 8:
				var a := TAU * i / 8.0
				_box(w, Vector3(0.12, 0.12, 0.4), Vector3(cos(a) * 0.5, -2.35 + (0.2 if i % 2 == 0 else -0.2), sin(a) * 0.5), steel, Vector3(0, -rad_to_deg(a) + 90, 0))
			_sph(w, Vector3.ONE * 0.3, Vector3(0, -2.35, 0), edge)
		"martillo":
			_cyl(w, 0.08, 3.4, Vector3(0, -1.4, 0), grip)
			_box(w, Vector3(0.8, 0.8, 1.6), Vector3(0, -3.0, 0), dark)
			_box(w, Vector3(0.84, 0.84, 0.1), Vector3(0, -3.0, -0.8), edge)
			_box(w, Vector3(0.84, 0.84, 0.1), Vector3(0, -3.0, 0.8), edge)
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collect = prev
	return w


func _update_cables(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var hang := Basis(Vector3.UP, global_rotation.y)
	for c in cables:
		var segs: Array = c["segs"]
		var ph: float = c["ph"]
		# Cuelgan por gravedad aunque ella esté inclinada o en el suelo
		(c["root"] as Node3D).global_basis = hang
		for i in segs.size():
			var s := segs[i] as Node3D
			var sway := sin(_anim_t * 1.7 + ph + i * 0.6) * (4.0 + i * 1.5)
			# Cuelgan hacia atrás y se arrastran al caminar
			var back := 8.0 + speed * 3.0 + (25.0 if i == 0 and not _crawl else 0.0)
			s.rotation_degrees = Vector3(-(back if i < 3 else back * 0.3), 0, sway)


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
	poses["plugged"] = _P({"chest": Vector3(-12, 0, 0), "neck": Vector3(-20, 0, 0), "head": Vector3(-25, 0, 0), "sh_l": Vector3(8, 0, -6), "sh_r": Vector3(8, 0, 6), "el_l": Vector3(10, 0, 0), "el_r": Vector3(10, 0, 0), "kn_l": Vector3(-6, 0, 0), "kn_r": Vector3(-6, 0, 0), "hip_l": Vector3(4, 0, 0), "hip_r": Vector3(4, 0, 0)})
	poses["boot"] = _P({"chest": Vector3(10, 0, 0), "head": Vector3(20, 0, 0), "sh_l": Vector3(20, 0, -35), "sh_r": Vector3(20, 0, 35), "el_l": Vector3(40, 0, 0), "el_r": Vector3(40, 0, 0)})
	poses["roar"] = _P({"chest": Vector3(15, 0, 0), "head": Vector3(22, 0, 0), "sh_l": Vector3(30, 0, -95), "sh_r": Vector3(30, 0, 95), "el_l": Vector3(25, 0, 0), "el_r": Vector3(25, 0, 0), "kn_l": Vector3(-10, 0, 0), "kn_r": Vector3(-10, 0, 0)})
	poses["guard"] = _P({"root_y": -0.12, "chest": Vector3(-8, -10, 0), "head": Vector3(4, 10, 0), "sh_l": Vector3(45, 0, -18), "el_l": Vector3(55, 0, 0), "wr_l": Vector3(45, 0, 0), "sh_r": Vector3(35, 0, 22), "el_r": Vector3(60, 0, 0), "wr_r": Vector3(55, 0, 0), "hip_l": Vector3(14, 0, -4), "kn_l": Vector3(-22, 0, 0), "an_l": Vector3(8, 0, 0), "hip_r": Vector3(-6, 0, 4), "kn_r": Vector3(-18, 0, 0), "an_r": Vector3(8, 0, 0)})
	poses["slash_wind_l"] = _P({"root_y": -0.15, "chest": Vector3(0, 40, 0), "sh_l": Vector3(150, 0, -40), "el_l": Vector3(30, 0, 0), "wr_l": Vector3(30, 0, 0), "sh_r": Vector3(40, 0, 25), "el_r": Vector3(60, 0, 0), "wr_r": Vector3(50, 0, 0), "hip_l": Vector3(20, 0, 0), "kn_l": Vector3(-25, 0, 0), "kn_r": Vector3(-20, 0, 0)})
	poses["slash_l"] = _P({"root_y": -0.2, "chest": Vector3(-18, -40, 0), "sh_l": Vector3(60, 0, 45), "el_l": Vector3(5, 0, 0), "wr_l": Vector3(40, 0, 0), "sh_r": Vector3(30, 0, 30), "el_r": Vector3(60, 0, 0), "wr_r": Vector3(50, 0, 0), "hip_l": Vector3(35, 0, 0), "kn_l": Vector3(-35, 0, 0), "hip_r": Vector3(-15, 0, 0), "kn_r": Vector3(-20, 0, 0)})
	poses["slash_wind_r"] = _P({"root_y": -0.15, "chest": Vector3(0, -40, 0), "sh_r": Vector3(150, 0, 40), "el_r": Vector3(30, 0, 0), "wr_r": Vector3(30, 0, 0), "sh_l": Vector3(40, 0, -25), "el_l": Vector3(60, 0, 0), "wr_l": Vector3(50, 0, 0), "hip_r": Vector3(20, 0, 0), "kn_r": Vector3(-25, 0, 0), "kn_l": Vector3(-20, 0, 0)})
	poses["slash_r"] = _P({"root_y": -0.2, "chest": Vector3(-18, 40, 0), "sh_r": Vector3(60, 0, -45), "el_r": Vector3(5, 0, 0), "wr_r": Vector3(40, 0, 0), "sh_l": Vector3(30, 0, -30), "el_l": Vector3(60, 0, 0), "wr_l": Vector3(50, 0, 0), "hip_r": Vector3(35, 0, 0), "kn_r": Vector3(-35, 0, 0), "hip_l": Vector3(-15, 0, 0), "kn_l": Vector3(-20, 0, 0)})
	poses["thrust_wind"] = _P({"root_y": -0.3, "chest": Vector3(5, 0, 0), "sh_l": Vector3(-30, 0, -20), "el_l": Vector3(100, 0, 0), "wr_l": Vector3(80, 0, 0), "sh_r": Vector3(-30, 0, 20), "el_r": Vector3(100, 0, 0), "wr_r": Vector3(80, 0, 0), "hip_l": Vector3(30, 0, 0), "kn_l": Vector3(-50, 0, 0), "hip_r": Vector3(-20, 0, 0), "kn_r": Vector3(-40, 0, 0)})
	poses["thrust"] = _P({"root_y": -0.35, "chest": Vector3(-25, 0, 0), "head": Vector3(15, 0, 0), "sh_l": Vector3(92, 0, 8), "el_l": Vector3(0, 0, 0), "wr_l": Vector3(5, 0, 0), "sh_r": Vector3(92, 0, -8), "el_r": Vector3(0, 0, 0), "wr_r": Vector3(5, 0, 0), "hip_l": Vector3(50, 0, 0), "kn_l": Vector3(-40, 0, 0), "hip_r": Vector3(-35, 0, 0), "kn_r": Vector3(-20, 0, 0)})
	poses["spin_wind"] = _P({"root_y": -0.3, "chest": Vector3(-10, 60, 0), "sh_l": Vector3(80, 0, -80), "el_l": Vector3(10, 0, 0), "wr_l": Vector3(70, 0, 0), "sh_r": Vector3(80, 0, 80), "el_r": Vector3(10, 0, 0), "wr_r": Vector3(70, 0, 0), "kn_l": Vector3(-35, 0, 0), "kn_r": Vector3(-35, 0, 0), "hip_l": Vector3(20, 0, 0), "hip_r": Vector3(20, 0, 0)})
	poses["spin"] = _P({"root_y": -0.25, "chest": Vector3(-10, -30, 0), "sh_l": Vector3(85, 0, -88), "wr_l": Vector3(80, 0, 0), "sh_r": Vector3(85, 0, 88), "wr_r": Vector3(80, 0, 0), "kn_l": Vector3(-30, 0, 0), "kn_r": Vector3(-30, 0, 0), "hip_l": Vector3(15, 0, 0), "hip_r": Vector3(15, 0, 0)})
	poses["stomp_wind"] = _P({"chest": Vector3(8, 0, 0), "sh_l": Vector3(40, 0, -50), "sh_r": Vector3(40, 0, 50), "hip_r": Vector3(75, 0, 0), "kn_r": Vector3(-75, 0, 0), "kn_l": Vector3(-12, 0, 0)})
	poses["stomp"] = _P({"root_y": -0.2, "chest": Vector3(-14, 0, 0), "sh_l": Vector3(10, 0, -40), "sh_r": Vector3(10, 0, 40), "hip_r": Vector3(8, 0, 0), "kn_r": Vector3(-12, 0, 0), "kn_l": Vector3(-25, 0, 0), "hip_l": Vector3(10, 0, 0)})
	poses["pulse_wind"] = _P({"root_y": -0.4, "chest": Vector3(-30, 0, 0), "head": Vector3(-20, 0, 0), "sh_l": Vector3(20, 0, -20), "el_l": Vector3(110, 0, 0), "sh_r": Vector3(20, 0, 20), "el_r": Vector3(110, 0, 0), "kn_l": Vector3(-45, 0, 0), "kn_r": Vector3(-45, 0, 0), "hip_l": Vector3(30, 0, 0), "hip_r": Vector3(30, 0, 0)})
	poses["cable_wind"] = _P({"chest": Vector3(14, 0, 0), "head": Vector3(10, 0, 0), "sh_l": Vector3(20, 0, -45), "sh_r": Vector3(20, 0, 45), "el_l": Vector3(40, 0, 0), "el_r": Vector3(40, 0, 0), "wr_l": Vector3(40, 0, 0), "wr_r": Vector3(40, 0, 0)})
	poses["cable_lash"] = _P({"root_y": -0.15, "chest": Vector3(-22, 0, 0), "head": Vector3(10, 0, 0), "sh_l": Vector3(30, 0, -30), "sh_r": Vector3(30, 0, 30), "el_l": Vector3(50, 0, 0), "el_r": Vector3(50, 0, 0), "kn_l": Vector3(-20, 0, 0), "kn_r": Vector3(-20, 0, 0), "hip_l": Vector3(10, 0, 0), "hip_r": Vector3(10, 0, 0)})
	poses["cast"] = _P({"chest": Vector3(6, 15, 0), "head": Vector3(8, 0, 0), "sh_l": Vector3(150, 0, -15), "el_l": Vector3(20, 0, 0), "wr_l": Vector3(-30, 0, 0), "sh_r": Vector3(30, 0, 30), "el_r": Vector3(50, 0, 0), "wr_r": Vector3(50, 0, 0)})
	poses["gs_wind"] = _P({"root_y": -0.3, "chest": Vector3(0, -70, 0), "sh_r": Vector3(90, 0, 90), "el_r": Vector3(10, 0, 0), "wr_r": Vector3(60, 0, 0), "sh_l": Vector3(70, 0, 40), "el_l": Vector3(70, 0, 0), "hip_l": Vector3(25, 0, 0), "kn_l": Vector3(-35, 0, 0), "kn_r": Vector3(-30, 0, 0)})
	poses["gs_swing"] = _P({"root_y": -0.3, "chest": Vector3(-10, 80, 0), "sh_r": Vector3(90, 0, -60), "el_r": Vector3(0, 0, 0), "wr_r": Vector3(70, 0, 0), "sh_l": Vector3(40, 0, -40), "el_l": Vector3(40, 0, 0), "hip_r": Vector3(25, 0, 0), "kn_r": Vector3(-30, 0, 0), "kn_l": Vector3(-30, 0, 0)})
	poses["overhead_wind"] = _P({"root_y": -0.1, "chest": Vector3(14, 0, 0), "head": Vector3(10, 0, 0), "sh_r": Vector3(175, 0, 5), "el_r": Vector3(25, 0, 0), "wr_r": Vector3(10, 0, 0), "sh_l": Vector3(165, 0, -5), "el_l": Vector3(40, 0, 0), "hip_r": Vector3(-10, 0, 0), "hip_l": Vector3(20, 0, 0), "kn_l": Vector3(-20, 0, 0)})
	poses["overhead"] = _P({"root_y": -0.45, "chest": Vector3(-35, 0, 0), "head": Vector3(20, 0, 0), "sh_r": Vector3(60, 0, 5), "el_r": Vector3(0, 0, 0), "wr_r": Vector3(20, 0, 0), "sh_l": Vector3(55, 0, -5), "el_l": Vector3(10, 0, 0), "hip_l": Vector3(45, 0, 0), "kn_l": Vector3(-55, 0, 0), "hip_r": Vector3(-20, 0, 0), "kn_r": Vector3(-35, 0, 0)})
	poses["hammer_wind"] = _P({"root_y": -0.6, "chest": Vector3(20, 0, 0), "sh_r": Vector3(175, 0, 10), "el_r": Vector3(40, 0, 0), "sh_l": Vector3(160, 0, -10), "el_l": Vector3(40, 0, 0), "hip_l": Vector3(55, 0, 0), "kn_l": Vector3(-90, 0, 0), "hip_r": Vector3(55, 0, 0), "kn_r": Vector3(-90, 0, 0), "an_l": Vector3(30, 0, 0), "an_r": Vector3(30, 0, 0)})
	poses["hammer_slam"] = _P({"root_y": -0.55, "chest": Vector3(-40, 0, 0), "head": Vector3(25, 0, 0), "sh_r": Vector3(70, 0, 0), "el_r": Vector3(0, 0, 0), "sh_l": Vector3(65, 0, 0), "hip_l": Vector3(45, 0, 0), "kn_l": Vector3(-70, 0, 0), "hip_r": Vector3(30, 0, 0), "kn_r": Vector3(-60, 0, 0)})
	poses["stagger"] = _P({"root_y": -0.3, "chest": Vector3(20, 0, -15), "head": Vector3(25, 0, 0), "sh_l": Vector3(-20, 0, -60), "sh_r": Vector3(-10, 0, 60), "hip_l": Vector3(-25, 0, -15), "kn_l": Vector3(-60, 0, 0), "kn_r": Vector3(-20, 0, 0)})
	# Fase 2: en el suelo, apoyada en los brazos, arrastrando la pierna sana
	poses["fall"] = _P({"root_y": -1.55, "spine": Vector3(-45, 0, -10), "chest": Vector3(-20, 0, 0), "head": Vector3(30, 0, 0), "sh_l": Vector3(70, 0, -30), "el_l": Vector3(40, 0, 0), "sh_r": Vector3(70, 0, 30), "el_r": Vector3(40, 0, 0), "hip_l": Vector3(70, 0, -20), "hip_r": Vector3(80, 0, 10), "kn_r": Vector3(-70, 0, 0)})
	poses["crawl"] = _P({"root_y": -1.6, "spine": Vector3(-55, 0, 0), "chest": Vector3(-20, 0, 0), "neck": Vector3(25, 0, 0), "head": Vector3(30, 0, 0), "sh_l": Vector3(115, 0, -20), "el_l": Vector3(-25, 0, 0), "wr_l": Vector3(-40, 0, 0), "sh_r": Vector3(115, 0, 20), "el_r": Vector3(-25, 0, 0), "wr_r": Vector3(-40, 0, 0), "hip_l": Vector3(-15, 0, -15), "hip_r": Vector3(-30, 0, 8), "kn_r": Vector3(-25, 0, 0)})
	poses["crawl_rear"] = _P({"root_y": -1.3, "spine": Vector3(-25, 0, 0), "chest": Vector3(5, 0, 0), "neck": Vector3(15, 0, 0), "head": Vector3(15, 0, 0), "sh_l": Vector3(160, 0, -35), "el_l": Vector3(30, 0, 0), "sh_r": Vector3(160, 0, 35), "el_r": Vector3(30, 0, 0), "hip_l": Vector3(10, 0, -15), "hip_r": Vector3(-15, 0, 8), "kn_r": Vector3(-40, 0, 0)})
	poses["crawl_slam"] = _P({"root_y": -1.65, "spine": Vector3(-70, 0, 0), "chest": Vector3(-25, 0, 0), "neck": Vector3(30, 0, 0), "head": Vector3(35, 0, 0), "sh_l": Vector3(75, 0, -10), "el_l": Vector3(0, 0, 0), "sh_r": Vector3(75, 0, 10), "el_r": Vector3(0, 0, 0), "hip_l": Vector3(-15, 0, -15), "hip_r": Vector3(-35, 0, 8), "kn_r": Vector3(-20, 0, 0)})
	poses["crawl_cast"] = _P({"root_y": -1.45, "spine": Vector3(-40, 0, 0), "chest": Vector3(0, 15, 0), "neck": Vector3(20, 0, 0), "head": Vector3(25, 0, 0), "sh_l": Vector3(170, 0, -10), "el_l": Vector3(10, 0, 0), "sh_r": Vector3(100, 0, 25), "el_r": Vector3(-20, 0, 0), "hip_l": Vector3(-10, 0, -15), "hip_r": Vector3(-25, 0, 8), "kn_r": Vector3(-30, 0, 0)})
	poses["dead"] = _P({"root_y": -1.95, "spine": Vector3(-80, 0, 15), "chest": Vector3(-10, 0, 0), "neck": Vector3(-10, 0, 0), "head": Vector3(-20, 0, 30), "sh_l": Vector3(160, 0, -40), "el_l": Vector3(10, 0, 0), "sh_r": Vector3(120, 0, 60), "el_r": Vector3(20, 0, 0), "hip_l": Vector3(-10, 0, -20), "hip_r": Vector3(-20, 0, 15), "kn_r": Vector3(-10, 0, 0)})


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
	var sw := sin(_walk_phase * 2.4)
	var free_move := state == State.FIGHT
	for key in _cur:
		if key == "root_y":
			continue
		var r: Vector3 = _cur[key]
		if _crawl and free_move:
			# Arrastre: los brazos se estiran y jalan por turnos
			match key:
				"sh_l": r.x += sw * 40.0 * maxf(w, 0.4)
				"sh_r": r.x -= sw * 40.0 * maxf(w, 0.4)
				"el_l": r.x += maxf(0.0, -sw) * 50.0 * maxf(w, 0.4)
				"el_r": r.x += maxf(0.0, sw) * 50.0 * maxf(w, 0.4)
				"spine": r.z += sw * 6.0
				"hip_r": r.y += sw * 8.0
		elif not _crawl:
			match key:
				"hip_l": r.x += sw * 24.0 * w
				"hip_r": r.x -= sw * 24.0 * w
				"kn_l": r.x -= maxf(0.0, -sw) * 35.0 * w
				"kn_r": r.x -= maxf(0.0, sw) * 35.0 * w
				"sh_l": r.x -= sw * 12.0 * w
				"sh_r": r.x += sw * 12.0 * w
				"chest": r.y += sw * 5.0 * w
		(J[key] as Node3D).rotation_degrees = r
	var bob := absf(sin(_walk_phase * 2.4)) * (0.08 if not _crawl else 0.12) * maxf(w, 0.3 if _crawl else 0.0)
	(J["pelvis"] as Node3D).position.y = 2.25 + float(_cur.get("root_y", 0.0)) + bob
