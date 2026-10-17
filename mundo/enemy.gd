extends CharacterBody3D
## Enemigo común del campus (no es jefe). El tipo se elige con `type`:
##   "robot"           robot vigilante pequeño: puñetazos y embestidas.
##   "robot_hacha"     robot mediano con hacha gigante: hachazo y barrido lentos y fuertes.
##   "robot_espada"    robot mediano con espada: combo de dos tajos y estocada.
##   "robot_laser"     robot mediano con pistola láser: dispara ráfagas a distancia.
##   "mecha"           mecha gigante que merodea zonas abiertas: barrido, pisotón y cañón.
##   "mutante_peq"     espécimen rastrero, rápido: mordidas y saltos (veneno).
##   "mutante_med"     espécimen encorvado con garras: zarpazos y escupitajo (veneno).
##   "mutante_grande"  mole de carne: golpe de área, manotazo y escupitajos (veneno).
## Los mutantes llenan la barra de VENENO del jugador al golpearlo.
## Lo crea y lo reinicia "VidaDelCampus" (world_life.gd), pero también puedes
## instanciar Enemigo.tscn a mano en cualquier escena y elegir el tipo.

signal died(enemy: Node)

const MODELS := preload("enemy_models.gd")
const BOLT := preload("enemy_bolt.gd")
const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const FX := preload("res://boss_profesor/boss_fx.gd")

enum State { IDLE, WANDER, CHASE, ATTACK, STAGGER, RETURN, DEAD }

const TYPES := {
	"robot": {"hp": 60.0, "walk": 1.6, "run": 4.4, "radius": 0.42, "height": 1.5, "sight": 15.0, "poise": 0.0, "turn": 8.0,
		"attacks": [
			{"id": "puñetazo", "wind": 0.45, "dur": 0.95, "reach": 1.8, "arc": 0.4, "dmg": 8.0, "lunge": 3.0, "min": 0.0, "max": 2.1, "pose": "jab", "w": 3},
			{"id": "embestida", "wind": 0.6, "dur": 1.15, "reach": 2.0, "arc": 0.3, "dmg": 10.0, "lunge": 9.0, "min": 2.4, "max": 5.5, "pose": "jab", "w": 2}]},
	"robot_hacha": {"hp": 150.0, "walk": 1.3, "run": 3.1, "radius": 0.6, "height": 2.3, "sight": 16.0, "poise": 75.0, "turn": 5.0,
		"attacks": [
			{"id": "hachazo", "wind": 1.0, "dur": 1.9, "reach": 3.3, "arc": 0.5, "dmg": 22.0, "lunge": 2.5, "min": 0.0, "max": 3.1, "pose": "overhead", "w": 3},
			{"id": "barrido", "wind": 0.8, "dur": 1.5, "reach": 3.4, "arc": -0.3, "dmg": 16.0, "lunge": 1.5, "min": 0.0, "max": 3.1, "pose": "sweep", "w": 2}]},
	"robot_espada": {"hp": 130.0, "walk": 1.5, "run": 3.8, "radius": 0.55, "height": 2.2, "sight": 16.0, "poise": 60.0, "turn": 6.5,
		"attacks": [
			{"id": "tajos", "wind": 0.5, "dur": 1.35, "reach": 2.8, "arc": 0.3, "dmg": 12.0, "lunge": 4.0, "min": 0.0, "max": 2.6, "pose": "slash", "hits": 2, "gap": 0.45, "w": 3},
			{"id": "estocada", "wind": 0.75, "dur": 1.3, "reach": 3.3, "arc": 0.6, "dmg": 15.0, "lunge": 10.0, "min": 2.8, "max": 6.5, "pose": "thrust", "w": 2}]},
	"robot_laser": {"hp": 100.0, "walk": 1.5, "run": 3.6, "radius": 0.5, "height": 2.2, "sight": 20.0, "poise": 55.0, "turn": 6.0, "keep_away": 8.0,
		"attacks": [
			{"id": "ráfaga", "kind": "shoot", "wind": 0.7, "dur": 1.7, "dmg": 11.0, "shots": 3, "gap": 0.22, "min": 4.0, "max": 22.0, "pose": "aim", "speed": 24.0, "w": 4},
			{"id": "culatazo", "wind": 0.5, "dur": 1.0, "reach": 2.0, "arc": 0.4, "dmg": 9.0, "lunge": 3.0, "min": 0.0, "max": 2.4, "pose": "jab", "w": 3}]},
	"mecha": {"hp": 650.0, "walk": 2.0, "run": 3.1, "radius": 1.5, "height": 5.0, "sight": 28.0, "poise": 99999.0, "turn": 2.2, "wander": 24.0,
		"attacks": [
			{"id": "barrido", "wind": 1.1, "dur": 2.1, "reach": 5.8, "arc": -0.2, "dmg": 26.0, "lunge": 1.0, "min": 0.0, "max": 5.3, "pose": "sweep", "w": 3},
			{"id": "pisotón", "kind": "aoe", "wind": 1.2, "dur": 2.0, "radius": 6.0, "dmg": 24.0, "min": 0.0, "max": 4.5, "pose": "stomp", "w": 3},
			{"id": "cañón", "kind": "shoot", "wind": 1.0, "dur": 2.4, "dmg": 14.0, "shots": 6, "gap": 0.14, "min": 7.0, "max": 32.0, "pose": "aim", "speed": 30.0, "size": 2.0, "w": 4}]},
	"mutante_peq": {"hp": 45.0, "walk": 1.5, "run": 5.4, "radius": 0.4, "height": 0.9, "sight": 13.0, "poise": 0.0, "turn": 9.0, "mutant": true,
		"attacks": [
			{"id": "mordida", "wind": 0.35, "dur": 0.85, "reach": 1.6, "arc": 0.4, "dmg": 6.0, "buildup": 20.0, "lunge": 5.0, "min": 0.0, "max": 2.0, "pose": "bite", "w": 3},
			{"id": "salto", "wind": 0.55, "dur": 1.25, "reach": 2.0, "arc": 0.3, "dmg": 8.0, "buildup": 26.0, "lunge": 11.0, "min": 2.5, "max": 7.0, "pose": "pounce", "w": 2}]},
	"mutante_med": {"hp": 140.0, "walk": 1.4, "run": 4.2, "radius": 0.55, "height": 2.0, "sight": 15.0, "poise": 60.0, "turn": 6.0, "mutant": true,
		"attacks": [
			{"id": "zarpazos", "wind": 0.55, "dur": 1.4, "reach": 2.7, "arc": 0.3, "dmg": 11.0, "buildup": 22.0, "lunge": 4.0, "min": 0.0, "max": 2.6, "pose": "slash", "hits": 2, "gap": 0.4, "w": 3},
			{"id": "escupitajo", "kind": "spit", "wind": 0.8, "dur": 1.4, "dmg": 8.0, "buildup": 30.0, "shots": 1, "min": 4.5, "max": 14.0, "pose": "spit", "w": 2}]},
	"mutante_grande": {"hp": 480.0, "walk": 1.3, "run": 2.9, "radius": 1.1, "height": 3.4, "sight": 18.0, "poise": 99999.0, "turn": 3.2, "mutant": true,
		"attacks": [
			{"id": "aplastón", "kind": "aoe", "wind": 1.2, "dur": 2.0, "radius": 4.8, "dmg": 22.0, "buildup": 35.0, "min": 0.0, "max": 4.0, "pose": "overhead", "w": 3},
			{"id": "manotazo", "wind": 0.9, "dur": 1.6, "reach": 4.3, "arc": -0.1, "dmg": 20.0, "buildup": 28.0, "lunge": 2.0, "min": 0.0, "max": 4.0, "pose": "sweep", "w": 3},
			{"id": "escupitajos", "kind": "spit", "wind": 1.0, "dur": 1.7, "dmg": 10.0, "buildup": 30.0, "shots": 3, "gap": 0.18, "min": 5.0, "max": 16.0, "pose": "spit", "size": 1.6, "w": 2}]},
}

## Poses de ataque: [preparación, golpe]; cada una es articulación -> grados.
const POSES := {
	"jab": [{"arm_r": Vector3(-40, 0, 0), "fore_r": Vector3(80, 0, 0), "torso": Vector3(0, -25, 0)},
		{"arm_r": Vector3(88, 0, 0), "fore_r": Vector3(5, 0, 0), "torso": Vector3(-10, 20, 0)}],
	"overhead": [{"arm_r": Vector3(170, 0, 0), "arm_l": Vector3(160, 0, 0), "torso": Vector3(12, 0, 0), "fore_r": Vector3(20, 0, 0)},
		{"arm_r": Vector3(55, 0, 0), "arm_l": Vector3(50, 0, 0), "torso": Vector3(-22, 0, 0)}],
	"sweep": [{"torso": Vector3(0, -75, 0), "arm_r": Vector3(80, 0, 35)},
		{"torso": Vector3(-5, 75, 0), "arm_r": Vector3(80, 0, 35)}],
	"slash": [{"arm_r": Vector3(150, 0, -25), "torso": Vector3(0, -30, 0), "arm_l": Vector3(40, 0, 20)},
		{"arm_r": Vector3(35, 0, 30), "torso": Vector3(-12, 30, 0), "arm_l": Vector3(70, 0, -20)}],
	"thrust": [{"arm_r": Vector3(-20, 0, 0), "fore_r": Vector3(100, 0, 0), "torso": Vector3(0, -30, 0)},
		{"arm_r": Vector3(92, 0, 0), "fore_r": Vector3(0, 0, 0), "torso": Vector3(-12, 15, 0)}],
	"aim": [{"arm_r": Vector3(88, 0, 0), "fore_r": Vector3(2, 0, 0), "torso": Vector3(0, 10, 0)},
		{"arm_r": Vector3(95, 0, 0), "fore_r": Vector3(-5, 0, 0), "torso": Vector3(4, 10, 0)}],
	"stomp": [{"leg_r": Vector3(55, 0, 0), "shin_r": Vector3(-55, 0, 0), "torso": Vector3(8, 0, 0), "arm_l": Vector3(30, 0, -20), "arm_r": Vector3(30, 0, 20)},
		{"leg_r": Vector3(-5, 0, 0), "torso": Vector3(-10, 0, 0), "arm_l": Vector3(0, 0, -30), "arm_r": Vector3(0, 0, 30)}],
	"spit": [{"head": Vector3(35, 0, 0), "jaw": Vector3(-10, 0, 0), "torso": Vector3(14, 0, 0)},
		{"head": Vector3(-15, 0, 0), "jaw": Vector3(-40, 0, 0), "torso": Vector3(-14, 0, 0)}],
	"bite": [{"torso": Vector3(18, 0, 0), "jaw": Vector3(-30, 0, 0)},
		{"torso": Vector3(-14, 0, 0), "jaw": Vector3(5, 0, 0)}],
	"pounce": [{"torso": Vector3(-10, 0, 0), "hip": Vector3(0, 0, 0), "jaw": Vector3(-20, 0, 0)},
		{"torso": Vector3(22, 0, 0), "jaw": Vector3(-40, 0, 0)}],
	"stagger": [{"torso": Vector3(22, 0, 0), "head": Vector3(25, 0, 0), "arm_l": Vector3(40, 0, -35), "arm_r": Vector3(40, 0, 35)},
		{"torso": Vector3(22, 0, 0)}],
}

const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
instance uniform float ratio = 1.0;
instance uniform float trail = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV;
	bool border = uv.x < 0.015 || uv.x > 0.985 || uv.y < 0.14 || uv.y > 0.86;
	vec3 c = vec3(0.04, 0.03, 0.03);
	if (uv.x < trail) c = vec3(0.8, 0.65, 0.3);
	if (uv.x < ratio) c = vec3(0.6, 0.07, 0.05);
	ALBEDO = border ? vec3(0.0) : c;
	ALPHA = 0.9;
}
"""
static var _bar_shader: Shader

@export_enum("robot", "robot_hacha", "robot_espada", "robot_laser", "mecha", "mutante_peq", "mutante_med", "mutante_grande") var type: String = "robot"
## Radio en el que pasea o merodea alrededor de su punto de inicio.
@export var wander_radius: float = 6.0

var home := Vector3.ZERO
var target: Node3D
var fx_parent: Node
var max_hp := 60.0
var hp := 60.0
var is_dead := false
var hit_radius := 0.5
var state: int = State.IDLE

var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _model: Dictionary
var J := {}
var _cur := {}
var _pose := {}
var _pose_rate := 10.0
var _walk_ph := 0.0
var _walk_amt := 0.0
var _t := 0.0
var _cd := 1.0
var _atk: Dictionary
var _atk_t := 0.0
var _hit_idx := 0
var _shot_idx := 0
var _poise_acc := 0.0
var _wander_to := Vector3.ZERO
var _wander_wait := 0.0
var _sight_t := 0.0
var _seen := false
var _steer := 0.0
var _steer_t := 0.0
var _stuck_t := 0.0
var _flash_t := 0.0
var _overlay: StandardMaterial3D
var _bar: MeshInstance3D
var _bar_t := 0.0
var _trail := 1.0
var _aggro_color := Color(1.0, 0.15, 0.1)
var _idle_color := Color(1.0, 0.6, 0.15)
var _placed := false


func _ready() -> void:
	_rng.randomize()
	_cfg = TYPES.get(type, TYPES["robot"])
	max_hp = _cfg["hp"]
	hp = max_hp
	hit_radius = _cfg["radius"]
	if _cfg.has("wander"):
		wander_radius = maxf(wander_radius, _cfg["wander"])
	add_to_group("enemy")
	if not _placed:
		home = global_position
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = _cfg["radius"]
	cap.height = maxf(_cfg["height"], cap.radius * 2.0 + 0.1)
	cs.shape = cap
	cs.position = Vector3(0, cap.height * 0.5, 0)
	add_child(cs)
	_build_model()
	_build_bar()
	_wander_to = home
	_wander_wait = _rng.randf_range(0.5, 3.0)
	if target == null:
		var ps := get_tree().get_nodes_in_group("player")
		if ps.size() > 0:
			target = ps[0]
	if fx_parent == null:
		fx_parent = get_parent()


## Lo usa VidaDelCampus antes de agregarlo al árbol.
func place(pos: Vector3, yaw: float) -> void:
	home = pos
	position = pos
	rotation.y = yaw
	_placed = true


func _build_model() -> void:
	match type:
		"robot":
			_model = MODELS.robot(1.0, "", _rng)
		"robot_hacha":
			_model = MODELS.robot(1.45, "hacha", _rng)
		"robot_espada":
			_model = MODELS.robot(1.4, "espada", _rng)
		"robot_laser":
			_model = MODELS.robot(1.4, "laser", _rng)
		"mecha":
			_model = MODELS.mech(_rng)
		"mutante_peq":
			_model = MODELS.mutant_small(_rng)
		"mutante_med":
			_model = MODELS.mutant_medium(_rng)
		_:
			_model = MODELS.mutant_large(_rng)
	if _cfg.get("mutant", false):
		_aggro_color = Color(0.7, 1.0, 0.2)
		_idle_color = Color(0.45, 1.0, 0.2)
	add_child(_model["root"])
	J = _model["J"]
	for k in J.keys():
		_cur[k] = Vector3.ZERO
	_overlay = StandardMaterial3D.new()
	_overlay.albedo_color = Color(1, 1, 1, 0.45)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.emission_enabled = true
	_overlay.emission = Color(1, 0.9, 0.8)
	_overlay.emission_energy_multiplier = 1.5
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Sombras solo en los grandes (rendimiento)
	var shadows: bool = type in ["mecha", "mutante_grande"]
	for mi in _model["meshes"]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_set_eyes(false)


func _build_bar() -> void:
	if _bar_shader == null:
		_bar_shader = Shader.new()
		_bar_shader.code = BAR_SHADER
	var m := ShaderMaterial.new()
	m.shader = _bar_shader
	var q := QuadMesh.new()
	var w := clampf(float(_cfg["height"]) * 0.55, 0.8, 2.4)
	q.size = Vector2(w, w * 0.09)
	_bar = MeshInstance3D.new()
	_bar.mesh = q
	_bar.material_override = m
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.position = Vector3(0, float(_cfg["height"]) + 0.45, 0)
	_bar.visible = false
	add_child(_bar)


func _set_eyes(aggro: bool) -> void:
	for m in _model["eyes"]:
		var sm := m as StandardMaterial3D
		var c := _aggro_color if aggro else _idle_color
		sm.albedo_color = c
		sm.emission = c


# ======================================================================
#  Daño
# ======================================================================

func take_damage(amount: float, from_pos: Variant = null) -> void:
	if is_dead:
		return
	hp -= amount
	_flash_t = 0.12
	_bar_t = 5.0
	var center := global_position + Vector3(0, float(_cfg["height"]) * 0.6, 0)
	if fx_parent:
		if _cfg.get("mutant", false):
			LFX.puff(fx_parent, center, Color(0.5, 1.2, 0.2, 0.9), 14, 0.18, 3.0, -7.0)
		else:
			FX.burst(fx_parent, center, true, 18, 0.6)
	if hp <= 0.0:
		_die()
		return
	if state in [State.IDLE, State.WANDER, State.RETURN]:
		_aggro()
	var poise: float = _cfg["poise"]
	_poise_acc += amount
	if poise <= 0.0 or _poise_acc >= poise:
		_poise_acc = 0.0
		state = State.STAGGER
		_t = 0.0
		_pose = POSES["stagger"][0]
		_pose_rate = 16.0
		if from_pos is Vector3:
			var away: Vector3 = global_position - from_pos
			away.y = 0.0
			velocity = away.normalized() * 4.0 if away.length() > 0.01 else Vector3.ZERO


func _die() -> void:
	is_dead = true
	state = State.DEAD
	remove_from_group("enemy")
	_bar.visible = false
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
	for m in _model["eyes"]:
		(m as StandardMaterial3D).emission_energy_multiplier = 0.0
		(m as StandardMaterial3D).albedo_color = Color(0.1, 0.1, 0.1)
	var root: Node3D = _model["root"]
	var tw := create_tween()
	if _model["kind"] == "quad":
		tw.tween_property(root, "rotation_degrees:z", 170.0, 0.5).set_trans(Tween.TRANS_BACK)
		tw.parallel().tween_property(root, "position:y", 0.5, 0.5)
	elif type == "mecha":
		tw.tween_property(root, "rotation_degrees:x", -12.0, 0.6)
		tw.tween_property(root, "position:y", -1.6, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(root, "rotation_degrees:z", 14.0, 0.8)
	else:
		tw.tween_property(root, "rotation_degrees:x", 84.0, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(root, "position:y", float(_cfg["radius"]) * 0.6, 0.7)
	if fx_parent:
		var c := global_position + Vector3(0, float(_cfg["height"]) * 0.5, 0)
		if _cfg.get("mutant", false):
			LFX.puff(fx_parent, c, Color(0.45, 1.1, 0.2, 0.9), 40, 0.35, 4.0, -6.0)
		else:
			FX.burst(fx_parent, c, true, 50, 1.2 if type == "mecha" else 0.8)
			if type == "mecha":
				LFX.fire(fx_parent, global_position + Vector3(0, 1.2, 0), 1.3, true)
				LFX.smoke(fx_parent, global_position + Vector3(0, 3.0, 0), 1.2)
			else:
				LFX.puff(fx_parent, c, Color(0.25, 0.25, 0.25, 0.8), 14, 0.5, 1.5, 1.0)
	died.emit(self)
	tw.tween_interval(6.0)
	tw.tween_property(root, "scale", Vector3.ONE * 0.01, 1.0)
	tw.tween_callback(queue_free)


# ======================================================================
#  IA
# ======================================================================

func _physics_process(delta: float) -> void:
	_update_visuals(delta)
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= 25.0 * delta
	else:
		velocity.y = -0.5
	var tgt_ok: bool = target != null and is_instance_valid(target) and not ("is_dead" in target and target.is_dead)
	var dist := INF
	if tgt_ok:
		dist = global_position.distance_to(target.global_position)
	_cd -= delta
	_t += delta
	var move := Vector3.ZERO
	var speed := 0.0
	match state:
		State.IDLE, State.WANDER:
			if tgt_ok and dist < float(_cfg["sight"]) and _can_see(delta):
				_aggro()
			else:
				_wander_wait -= delta
				if state == State.IDLE and _wander_wait <= 0.0:
					var a := _rng.randf() * TAU
					var r := sqrt(_rng.randf()) * wander_radius
					_wander_to = home + Vector3(cos(a) * r, 0, sin(a) * r)
					state = State.WANDER
				if state == State.WANDER:
					var to := _wander_to - global_position
					to.y = 0.0
					if to.length() < 0.8 or _t > 12.0:
						state = State.IDLE
						_t = 0.0
						_wander_wait = _rng.randf_range(2.0, 5.0) if type != "mecha" else _rng.randf_range(0.5, 2.0)
					else:
						move = to.normalized()
						speed = float(_cfg["walk"])
		State.CHASE:
			if not tgt_ok or global_position.distance_to(home) > wander_radius + 30.0 or dist > float(_cfg["sight"]) * 2.4:
				_lose_target()
			else:
				var to := target.global_position - global_position
				to.y = 0.0
				var dir := to.normalized()
				var a := _choose_attack(dist) if _cd <= 0.0 else {}
				if not a.is_empty():
					_start_attack(a)
				else:
					var keep: float = _cfg.get("keep_away", 0.0)
					if keep > 0.0 and dist < keep * 0.55:
						move = -dir
						speed = float(_cfg["walk"]) * 1.2
					elif keep > 0.0 and dist < keep:
						move = dir.cross(Vector3.UP) * (1.0 if int(_t) % 6 < 3 else -1.0)
						speed = float(_cfg["walk"])
					elif dist > float(_cfg["radius"]) + 1.2:
						move = dir
						speed = float(_cfg["run"]) if dist > 3.5 else float(_cfg["walk"]) * 1.3
					_turn_to(dir, delta, 1.0)
		State.ATTACK:
			_process_attack(delta)
		State.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
			if _t > 0.55:
				state = State.CHASE
				_pose = {}
				_pose_rate = 8.0
				_cd = _rng.randf_range(0.2, 0.6)
		State.RETURN:
			var to := home - global_position
			to.y = 0.0
			hp = minf(max_hp, hp + max_hp * 0.25 * delta)
			if to.length() < 1.5:
				state = State.IDLE
				_t = 0.0
				_wander_wait = 1.0
				_set_eyes(false)
			else:
				move = to.normalized()
				speed = float(_cfg["run"])
				if tgt_ok and dist < float(_cfg["sight"]) * 0.6 and _can_see(delta) and global_position.distance_to(home) < wander_radius + 20.0:
					_aggro()
	if state != State.ATTACK and state != State.STAGGER:
		if move != Vector3.ZERO:
			move = _avoid(move, delta)
			if state != State.CHASE:
				_turn_to(move, delta, 0.7)
		velocity.x = move.x * speed
		velocity.z = move.z * speed
	_walk_amt = move_toward(_walk_amt, clampf(Vector2(velocity.x, velocity.z).length() / maxf(float(_cfg["run"]), 0.1), 0.0, 1.0), delta * 4.0)
	move_and_slide()


func _aggro() -> void:
	if state == State.DEAD:
		return
	state = State.CHASE
	_t = 0.0
	_cd = maxf(_cd, _rng.randf_range(0.3, 0.9))
	_set_eyes(true)


func _lose_target() -> void:
	state = State.RETURN
	_t = 0.0
	_pose = {}
	_set_eyes(false)


func _can_see(delta: float) -> bool:
	_sight_t -= delta
	if _sight_t > 0.0:
		return _seen
	_sight_t = 0.3
	var eye := global_position + Vector3(0, float(_cfg["height"]) * 0.85, 0)
	var q := PhysicsRayQueryParameters3D.create(eye, target.global_position + Vector3(0, 1.2, 0))
	var excl: Array[RID] = [get_rid()]
	if target is CollisionObject3D:
		excl.append((target as CollisionObject3D).get_rid())
	q.exclude = excl
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_seen = hit.is_empty() or not (hit["collider"] is StaticBody3D)
	return _seen


## Si choca con una pared, rodea el obstáculo girando un rato hacia un lado.
func _avoid(dir: Vector3, delta: float) -> Vector3:
	_steer_t -= delta
	var horiz := Vector2(velocity.x, velocity.z).length()
	if is_on_wall() and horiz < 0.6:
		_stuck_t += delta
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta)
	if _stuck_t > 0.25 and _steer_t <= 0.0:
		_steer = deg_to_rad(75.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_steer_t = _rng.randf_range(0.7, 1.4)
		_stuck_t = 0.0
	if _steer_t > 0.0:
		return dir.rotated(Vector3.UP, _steer)
	return dir


func _turn_to(dir: Vector3, delta: float, factor: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-float(_cfg["turn"]) * factor * delta))


# ======================================================================
#  Ataques
# ======================================================================

func _choose_attack(dist: float) -> Dictionary:
	var opts: Array = []
	var total := 0
	for a in _cfg["attacks"]:
		if dist >= float(a["min"]) and dist <= float(a["max"]):
			opts.append(a)
			total += int(a["w"])
	if opts.is_empty():
		return {}
	var r := _rng.randi_range(1, total)
	for a in opts:
		r -= int(a["w"])
		if r <= 0:
			return a
	return opts[0]


func _start_attack(a: Dictionary) -> void:
	state = State.ATTACK
	_atk = a
	_atk_t = 0.0
	_hit_idx = 0
	_shot_idx = 0
	_pose = POSES[a["pose"]][0]
	_pose_rate = 1.0 / maxf(float(a["wind"]) * 0.45, 0.05)
	velocity.x = 0.0
	velocity.z = 0.0


func _process_attack(delta: float) -> void:
	_atk_t += delta
	var a := _atk
	var wind: float = a["wind"]
	var kind: String = a.get("kind", "melee")
	var tgt_ok: bool = target != null and is_instance_valid(target) and not ("is_dead" in target and target.is_dead)
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	if _atk_t < wind:
		# Preparación: sigue al jugador con la mirada (telegrafiado)
		if tgt_ok:
			var to := target.global_position - global_position
			to.y = 0.0
			_turn_to(to.normalized(), delta, 0.9 if kind != "shoot" else 1.4)
		var k := _atk_t / wind
		if k > 0.7 and int(_atk_t * 20.0) % 2 == 0:
			_flash_eyes()
	else:
		match kind:
			"melee":
				var hits: int = a.get("hits", 1)
				var gap: float = a.get("gap", 0.4)
				var hit_t := wind + _hit_idx * gap
				if _hit_idx < hits and _atk_t >= hit_t:
					_pose = POSES[a["pose"]][1 if _hit_idx % 2 == 0 else 0]
					_pose_rate = 22.0
					var lunge: float = a.get("lunge", 0.0)
					velocity.x = fwd.x * lunge
					velocity.z = fwd.z * lunge
					_hit_idx += 1
					_melee_check(a, fwd)
				elif _atk_t < hit_t - gap + 0.15:
					var lunge2: float = a.get("lunge", 0.0)
					velocity.x = fwd.x * lunge2
					velocity.z = fwd.z * lunge2
			"aoe":
				if _hit_idx == 0:
					_hit_idx = 1
					_pose = POSES[a["pose"]][1]
					_pose_rate = 22.0
					_aoe(a)
			"shoot", "spit":
				var shots: int = a.get("shots", 1)
				var gap: float = a.get("gap", 0.2)
				if _shot_idx == 0:
					_pose = POSES[a["pose"]][1]
					_pose_rate = 16.0
				if _shot_idx < shots and _atk_t >= wind + _shot_idx * gap:
					_shot_idx += 1
					if tgt_ok:
						if kind == "shoot":
							_shoot(a)
						else:
							_spit(a)
				if tgt_ok and kind == "shoot":
					var to := target.global_position - global_position
					to.y = 0.0
					_turn_to(to.normalized(), delta, 0.6)
	if _atk_t >= float(a["dur"]):
		state = State.CHASE
		_pose = {}
		_pose_rate = 6.0
		_cd = _rng.randf_range(0.6, 1.6) * (1.6 if type in ["mecha", "mutante_grande"] else 1.0)
		if kind == "shoot":
			_cd += _rng.randf_range(0.8, 1.6)


func _melee_check(a: Dictionary, fwd: Vector3) -> void:
	if target == null or not is_instance_valid(target):
		return
	var to := target.global_position - global_position
	if absf(to.y) > 2.5:
		return
	to.y = 0.0
	var reach: float = a["reach"]
	if to.length() < reach + 0.4 and (to.length() < 0.8 or fwd.dot(to.normalized()) > float(a["arc"])):
		_damage_target(a)


func _aoe(a: Dictionary) -> void:
	var r: float = a["radius"]
	var col := Color(0.45, 1.0, 0.2) if _cfg.get("mutant", false) else Color(1.0, 0.55, 0.2)
	var center := global_position + (-global_basis.z) * (float(_cfg["radius"]) * 0.8)
	center.y = global_position.y
	if fx_parent:
		FX.shockwave(fx_parent, center + Vector3(0, 0.1, 0), r, col, 0.5)
		LFX.puff(fx_parent, center + Vector3(0, 0.3, 0), Color(0.45, 0.42, 0.38, 0.8), 30, 0.6, 5.0, 2.0)
	if target and target.has_method("add_camera_shake") and global_position.distance_to(target.global_position) < r * 3.0:
		target.add_camera_shake(0.35 if type == "mecha" else 0.25)
	if target == null or not is_instance_valid(target):
		return
	var to := target.global_position - center
	if absf(to.y) < 2.0 and Vector2(to.x, to.z).length() < r:
		_damage_target(a)


func _damage_target(a: Dictionary) -> void:
	if not target.has_method("take_damage"):
		return
	var before: float = float(target.get("hp")) if "hp" in target else 0.0
	target.take_damage(float(a["dmg"]), global_position)
	var bu: float = a.get("buildup", 0.0)
	if bu > 0.0 and target.has_method("add_buildup") and "hp" in target and float(target.get("hp")) < before:
		target.add_buildup("veneno", bu)


func _muzzle_pos() -> Vector3:
	var m: Node3D = J.get("muzzle")
	if m:
		return m.global_position
	var h: Node3D = J.get("head")
	if h:
		return h.global_position + (-global_basis.z) * 0.4
	return global_position + Vector3(0, float(_cfg["height"]) * 0.8, 0)


func _shoot(a: Dictionary) -> void:
	var from := _muzzle_pos()
	var aim := target.global_position + Vector3(0, 1.0, 0)
	aim += Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.2, 0.3), _rng.randf_range(-0.4, 0.4))
	var b := BOLT.new()
	b.kind = "laser"
	b.target = target
	b.shooter = self
	b.damage = a["dmg"]
	b.size = a.get("size", 1.0)
	b.color = Color(1.0, 0.45, 0.12) if type == "mecha" else Color(1.0, 0.18, 0.12)
	b.velocity = (aim - from).normalized() * float(a.get("speed", 24.0))
	b.life = 2.5
	(fx_parent if fx_parent else get_parent()).add_child(b)
	b.global_position = from
	if fx_parent:
		LFX.puff(fx_parent, from, Color(2.5, 0.8, 0.4, 1), 6, 0.12, 2.0, 0.0)


func _spit(a: Dictionary) -> void:
	var from := _muzzle_pos()
	var aim := target.global_position + Vector3(_rng.randf_range(-0.8, 0.8), 0.9, _rng.randf_range(-0.8, 0.8))
	var g := 12.0
	var flat := Vector2(aim.x - from.x, aim.z - from.z).length()
	var t := clampf(flat / 13.0, 0.45, 1.3)
	var v := (aim - from) / t
	v.y += 0.5 * g * t
	var b := BOLT.new()
	b.kind = "spit"
	b.target = target
	b.shooter = self
	b.damage = a["dmg"]
	b.buildup = a.get("buildup", 0.0)
	b.size = a.get("size", 1.0)
	b.velocity = v
	b.gravity = g
	b.life = 3.0
	(fx_parent if fx_parent else get_parent()).add_child(b)
	b.global_position = from


func _flash_eyes() -> void:
	for m in _model["eyes"]:
		(m as StandardMaterial3D).emission_energy_multiplier = 7.0


# ======================================================================
#  Animación
# ======================================================================

func _update_visuals(delta: float) -> void:
	# Destello al recibir daño
	if _flash_t > 0.0:
		_flash_t -= delta
		var on := _flash_t > 0.0
		for mi in _model["meshes"]:
			(mi as MeshInstance3D).material_overlay = _overlay if on else null
	if not is_dead:
		for m in _model["eyes"]:
			var sm := m as StandardMaterial3D
			sm.emission_energy_multiplier = move_toward(sm.emission_energy_multiplier, 3.0, delta * 12.0)
	# Barra de vida flotante
	_bar_t -= delta
	_trail = move_toward(_trail, hp / max_hp, delta * 0.5) if _trail > hp / max_hp else hp / max_hp
	_bar.visible = not is_dead and (_bar_t > 0.0 or state == State.CHASE or state == State.ATTACK) and hp < max_hp
	if _bar.visible:
		_bar.set_instance_shader_parameter("ratio", clampf(hp / max_hp, 0.0, 1.0))
		_bar.set_instance_shader_parameter("trail", clampf(_trail, 0.0, 1.0))
	if is_dead:
		return
	# Poses + caminata procedural
	_walk_ph += delta * lerpf(4.0, 9.5, _walk_amt) * (0.55 if type == "mecha" else 1.0)
	var sw := sin(_walk_ph)
	var amp := _walk_amt * (32.0 if _model["kind"] != "mech" else 22.0)
	var k := 1.0 - exp(-_pose_rate * delta)
	for n in J.keys():
		var tgt: Vector3 = _pose.get(n, Vector3.ZERO)
		_cur[n] = (_cur[n] as Vector3).lerp(tgt, k)
		var r: Vector3 = _cur[n]
		match _model["kind"]:
			"quad":
				if n == "leg_fl" or n == "leg_br":
					r.y += sw * amp
				elif n == "leg_fr" or n == "leg_bl":
					r.y -= sw * amp
				elif n.begins_with("shin_"):
					r.z += absf(sw) * amp * 0.5 * (1.0 if n.ends_with("l") else -1.0)
				elif n == "torso":
					r.z += sw * amp * 0.1
			_:
				match n:
					"leg_l":
						r.x += sw * amp
					"leg_r":
						r.x -= sw * amp
					"shin_l":
						r.x -= maxf(0.0, -cos(_walk_ph)) * amp * 0.9
					"shin_r":
						r.x -= maxf(0.0, cos(_walk_ph)) * amp * 0.9
					"arm_l":
						r.x -= sw * amp * 0.6
					"arm_r":
						if not _pose.has("arm_r"):
							r.x += sw * amp * 0.6
					"torso":
						r.y += sw * amp * 0.12
		(J[n] as Node3D).rotation_degrees = r
	# Balanceo del cuerpo al caminar / respirar
	var hip: Node3D = J.get("hip")
	if hip:
		var base := hip.position
		base.y = (hip.get_meta("y0") if hip.has_meta("y0") else base.y)
		if not hip.has_meta("y0"):
			hip.set_meta("y0", base.y)
		var bob := absf(cos(_walk_ph)) * 0.06 * _walk_amt * float(_cfg["height"]) * 0.5
		bob += sin(Time.get_ticks_msec() * 0.003) * 0.01 * float(_cfg["height"])
		hip.position.y = base.y + bob


## Revive y vuelve a su punto de inicio (al descansar en una hoguera).
func reset_to_home() -> void:
	if is_dead:
		return
	hp = max_hp
	global_position = home
	velocity = Vector3.ZERO
	state = State.IDLE
	_pose = {}
	_set_eyes(false)
