extends CharacterBody3D
## Jugador de PRUEBA para probar la pelea (cámara en tercera persona).
## Cuando tengas tu propio personaje, desactiva "spawn_test_player" en BossFight y
## agrega tu jugador al grupo "player" con estos métodos:
##   take_damage(cantidad: float, desde: Vector3)    <- el jefe lo llama al golpearte
##   add_camera_shake(fuerza: float)                  <- opcional
##   var is_dead: bool                                <- opcional
##   apply_status(efecto, segundos)                   <- opcional: "electrocutado",
##                                                       "quemadura" o "atrapado"
## Para dañar al jefe: jefe.take_damage(cantidad)  (está en el grupo "boss").
##
## Controles: WASD mover · Shift correr · Espacio rodar · Clic izq. atacar
##            Clic medio / Tab fijar objetivo · R beber café (curar) · E interactuar
##            (hogueras) · Esc soltar mouse
## Clases (jugador/player_classes.gd + jugador/class_kit.gd): Clic der. habilidad
## de la clase · Q cambiar hechizo / IA · G bebida energética (maná, solo Frontend).

signal died
signal health_changed(hp: float, max_hp: float)
signal status_changed(effects: Array)
signal interact_pressed

## Acumulación ("barra de afecto"): al llenarse a 100 se aplica el estado.
const BUILDUP := {
	"veneno": {"duration": 15.0, "decay": 5.0},
	"ameba": {"duration": 10.0, "decay": 12.0},
}

const PLAYER_MODEL: PackedScene = preload("res://Modelo/modelo.glb")
const CLASSES := preload("res://jugador/player_classes.gd")
const KIT := preload("res://jugador/class_kit.gd")
const RIG := preload("res://jugador/player_rig.gd")


@export var max_hp := 100.0
@export var max_stamina := 100.0
@export var attack_damage := 40.0
@export var flasks := 4

var hp := 100.0
var stamina := 100.0
var is_dead := false
## Diálogos y finales: el jugador no se mueve ni ataca (la cámara sí gira).
var input_locked := false

var _yaw := 0.0
var _pitch := -0.25
var _cam_yaw_node: Node3D
var _cam_pitch_node: Node3D
var _spring: SpringArm3D
var camera: Camera3D
var _visual: Node3D
var _model_meshes: Array[MeshInstance3D] = []
var _sword_pivot: Node3D
var _trauma := 0.0
var _st_delay := 0.0

var _roll_t := 0.0
var _roll_dir := Vector3.ZERO
var _attack_t := 0.0
var _attack_hit := false
var _heal_t := 0.0
var _stagger_t := 0.0
var _iframes := 0.0
var _knock := Vector3.ZERO
var _locked := false
var _focus_target: Node3D
var _face_dir := Vector3.FORWARD
var _m_body: StandardMaterial3D

# Estados alterados: nombre -> segundos restantes
var _status := {}
var _burn_tick := 0.0
var _max_flasks := 4
var _fx_shock: GPUParticles3D
var _fx_burn: GPUParticles3D
var _fx_poison: GPUParticles3D
var _buildup := {}
var _buildup_wait := {}
var _poison_tick := 0.0
var _amoeba_tick := 0.0

# Clase
var class_id := "cyber"
var kit: KIT
var _cfg: Dictionary
var _cast_t := 0.0
var _atk := {}
# Esqueleto, combos y animaciones
var rig: RIG
var _combo_step := 0
var _combo_queued := false
var _combo_window := 0.0
var _drink_t := 0.0
var _running := false
var _rim := {}


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	stamina = max_stamina
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		cs = CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4
		cap.height = 1.8
		cs.shape = cap
		cs.position = Vector3(0, 0.9, 0)
		add_child(cs)
	_max_flasks = flasks
	class_id = CLASSES.current()
	_cfg = CLASSES.data(class_id)
	max_hp = _cfg["hp"]
	hp = max_hp
	_build_visual()
	_build_rig()
	kit = KIT.new()
	add_child(kit)
	kit.setup(self, class_id)
	if rig:
		kit.attach_to_rig(rig)
	_build_status_fx()
	_build_camera()
	_yaw = rotation.y
	rotation.y = 0.0
	_face_dir = Vector3(-sin(_yaw), 0, -cos(_yaw))


func _build_visual() -> void:
	_visual = get_node_or_null("Visual") as Node3D
	if _visual == null:
		_visual = Node3D.new()
		_visual.name = "Visual"
		add_child(_visual)
	var model := _visual.get_node_or_null("ModeloJugador") as Node3D
	if model == null:
		model = PLAYER_MODEL.instantiate() as Node3D
		if model == null:
			push_error("El modelo del jugador debe tener una raíz Node3D.")
		else:
			model.name = "ModeloJugador"
			model.rotation_degrees = Vector3(0.0, 180.0, 0.0)
			model.scale = Vector3.ONE * 1.55
			_visual.add_child(model)
	if model:
		for node in model.find_children("*", "MeshInstance3D", true, false):
			_model_meshes.append(node as MeshInstance3D)

	_m_body = StandardMaterial3D.new()
	_m_body.albedo_color = Color(1.0, 0.1, 0.05, 0.3)
	_m_body.roughness = 0.5
	_m_body.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_m_body.emission_enabled = true
	_m_body.emission = Color(1, 0.1, 0.05)
	_m_body.emission_energy_multiplier = 0.0
	_sword_pivot = Node3D.new()
	_sword_pivot.position = Vector3(0.38, 1.25, 0)
	_visual.add_child(_sword_pivot)
	var sword := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.06, 1.2, 0.02)
	sword.mesh = sb
	sword.position = Vector3(0, 0.2, -0.55)
	sword.rotation_degrees = Vector3(-80, 0, 0)
	var swm := StandardMaterial3D.new()
	swm.albedo_color = Color(0.75, 0.76, 0.8)
	swm.metallic = 0.9
	swm.roughness = 0.2
	sword.material_override = swm
	_sword_pivot.add_child(sword)


## Esqueleto procedural sobre el modelo estático (jugador/player_rig.gd).
func _build_rig() -> void:
	var model := _visual.get_node_or_null("ModeloJugador") as Node3D
	if model == null:
		return
	rig = RIG.new()
	add_child(rig)
	var body: MeshInstance3D = rig.build(_visual, model)
	_model_meshes.clear()
	_model_meshes.append(body)


func _build_camera() -> void:
	_cam_yaw_node = Node3D.new()
	_cam_yaw_node.top_level = true
	add_child(_cam_yaw_node)
	_cam_pitch_node = Node3D.new()
	_cam_yaw_node.add_child(_cam_pitch_node)
	_spring = SpringArm3D.new()
	_spring.spring_length = 5.0
	_spring.margin = 0.3
	_spring.add_excluded_object(get_rid())
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	_spring.shape = sphere
	_cam_pitch_node.add_child(_spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 600.0
	_spring.add_child(camera)
	camera.make_current.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if input_locked and not (event is InputEventMouseMotion):
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		kit.secondary_released()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_toggle_focus()
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT and not is_dead:
			kit.secondary_pressed()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if not _locked:
			_yaw -= event.relative.x * 0.003
		_pitch = clampf(_pitch - event.relative.y * 0.003, -1.1, 0.5)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_SPACE:
				_try_roll()
			KEY_TAB:
				_toggle_focus()
			KEY_R, KEY_F:
				_try_heal()
			KEY_E:
				if not is_dead:
					interact_pressed.emit()
			KEY_Q:
				if not is_dead:
					kit.cycle()
			KEY_G:
				kit.drink()


## Objetivo más cercano (jefe o enemigo) a menos de `max_dist` metros.
func _find_boss(max_dist := 30.0) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for b in _targets():
		var d := global_position.distance_to((b as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func _targets() -> Array:
	var out: Array = []
	for g in ["boss", "enemy"]:
		for b in get_tree().get_nodes_in_group(g):
			if b is Node3D and b != self and not out.has(b) and not _target_dead(b):
				out.append(b)
	return out


func _target_dead(b: Node) -> bool:
	if not is_instance_valid(b) or b.is_queued_for_deletion():
		return true
	if "is_dead" in b and b.get("is_dead"):
		return true
	return b.is_in_group("boss") and "state" in b and b.get("state") == 5


func _toggle_focus() -> void:
	if _locked:
		_locked = false
		_focus_target = null
		return
	_focus_target = _find_boss()
	_locked = _focus_target != null
	if _locked:
		_face_focus_target()


func _face_focus_target() -> void:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return
	var to := _focus_target.global_position - global_position
	to.y = 0.0
	if to.length_squared() > 0.001:
		_face_dir = to.normalized()


func _input_dir() -> Vector3:
	if input_locked:
		return Vector3.ZERO
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): v.y -= 1
	if Input.is_key_pressed(KEY_S): v.y += 1
	if Input.is_key_pressed(KEY_A): v.x -= 1
	if Input.is_key_pressed(KEY_D): v.x += 1
	if v == Vector2.ZERO:
		return Vector3.ZERO
	v = v.normalized()
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	return (right * v.x - fwd * v.y).normalized()


func _busy() -> bool:
	return _roll_t > 0.0 or _attack_t > 0.0 or _cast_t > 0.0 or _stagger_t > 0.0 or is_dead or _stunned()


func _try_roll() -> void:
	var cost: float = _cfg["roll_cost"]
	if is_dead or _roll_t > 0.0 or _stagger_t > 0.0 or stamina < cost * 0.9 or _stunned():
		return
	_attack_t = 0.0
	_cast_t = 0.0
	var d := _input_dir()
	_roll_dir = d if d != Vector3.ZERO else -_face_dir
	_face_dir = _roll_dir
	_roll_t = _cfg["roll_time"]
	_iframes = _cfg["roll_iframes"]
	_use_stamina(cost)


func _try_attack() -> void:
	# Durante un ataque, el clic se guarda para encadenar el combo
	if _attack_t > 0.0 and not _atk.is_empty():
		var k := 1.0 - _attack_t / float(_atk.get("dur", 0.5))
		if k > 0.3:
			_combo_queued = true
		return
	if _busy() or stamina < 8.0 or kit.is_blocking():
		return
	if _combo_window <= 0.0:
		_combo_step = 0
	_start_attack()


func _start_attack() -> void:
	var atk: Dictionary = kit.primary(_combo_step)
	if atk.is_empty() or float(atk.get("dur", 0.0)) <= 0.0:
		return
	_atk = atk
	_attack_t = atk["dur"]
	_attack_hit = atk.get("no_hit", false)
	_use_stamina(atk.get("stamina", 12.0))
	var b := _focus_target if _locked and _focus_target else _find_boss(7.0)
	if b and global_position.distance_to(b.global_position) < 7.0:
		var to := b.global_position - global_position
		to.y = 0.0
		_face_dir = to.normalized()


## Beber café cura al instante: no hay que quedarse quieto ni se cancela con golpes.
func _try_heal() -> void:
	if is_dead or _stunned() or flasks <= 0 or hp >= max_hp:
		return
	flasks -= 1
	play_drink("taza")
	hp = minf(max_hp, hp + 45.0)
	health_changed.emit(hp, max_hp)


## Animación de beber (café o bebida energética): no detiene al jugador.
func play_drink(kind: String) -> void:
	_drink_t = 0.85
	if rig:
		rig.show_held(kind, 0.85)


func _use_stamina(a: float) -> void:
	stamina = maxf(0.0, stamina - a)
	_st_delay = 0.6


func take_damage(amount: float, from: Variant = null) -> void:
	if is_dead or _iframes > 0.0:
		return
	amount *= kit.damage_mult(from)
	if _status.has("atrapado"):
		amount *= kit.resist("atrapado", "grab")
	hp = maxf(0.0, hp - amount)
	health_changed.emit(hp, max_hp)
	_m_body.emission_energy_multiplier = 2.0
	for mesh in _model_meshes:
		mesh.material_overlay = _m_body
	add_camera_shake(0.45)
	_attack_t = 0.0
	_cast_t = 0.0
	_stagger_t = 0.35 if not kit.is_blocking() else 0.15
	_iframes = 0.5
	if from is Vector3:
		var away: Vector3 = global_position - from
		away.y = 0.0
		_knock = (away.normalized() if away.length() > 0.01 else -_face_dir) * (7.0 + amount * 0.1)
	if hp <= 0.0:
		_die()


func _die() -> void:
	is_dead = true
	_roll_t = 0.0
	clear_statuses()
	var tw := create_tween()
	tw.tween_property(_visual, "rotation_degrees:x", -88.0, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_visual, "position:y", 0.2, 0.6)
	died.emit()


func add_camera_shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _physics_process(delta: float) -> void:
	_iframes -= delta
	_stagger_t -= delta
	_st_delay -= delta
	if _st_delay <= 0.0 and _roll_t <= 0.0 and _attack_t <= 0.0:
		stamina = minf(max_stamina, stamina + 38.0 * delta)
	_m_body.emission_energy_multiplier = maxf(0.0, _m_body.emission_energy_multiplier - delta * 6.0)
	_update_statuses(delta)
	kit.process(delta)
	if _m_body.emission_energy_multiplier == 0.0:
		# Solo un contorno de color: el jugador se sigue viendo
		var overlay: Material = null
		var tms := Time.get_ticks_msec()
		for eff in ["electrocutado", "quemadura", "ameba", "veneno", "atrapado"]:
			if _status.has(eff):
				overlay = _rim[eff]
				# Tinte tenue que late: el jugador se sigue viendo debajo
				var a := 0.16 + 0.08 * sin(tms * 0.008)
				if eff == "electrocutado":
					a = randf_range(0.08, 0.3)
				(overlay as StandardMaterial3D).albedo_color.a = a
				break
		# Solo sobre el cuerpo (en las piezas de armadura cuadradas el contorno se ve como bloque)
		for mesh in _model_meshes:
			mesh.material_overlay = overlay

	if _locked and (_focus_target == null or _target_dead(_focus_target)
			or global_position.distance_to(_focus_target.global_position) > 40.0):
		_locked = false
		_focus_target = null
	if _locked and _focus_target:
		var to := _focus_target.global_position - global_position
		if Vector2(to.x, to.z).length_squared() > 0.001:
			_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), 1.0 - exp(-8.0 * delta))
		var target_point := _focus_target.global_position + Vector3(0, 1.6, 0)
		var camera_origin := global_position + Vector3(0, 1.7, 0)
		var aim_offset := target_point - camera_origin
		var target_pitch := atan2(aim_offset.y, Vector2(aim_offset.x, aim_offset.z).length())
		_pitch = lerp_angle(_pitch, clampf(target_pitch, -1.1, 0.5), 1.0 - exp(-8.0 * delta))
		_face_focus_target()

	var vel := Vector3.ZERO
	if is_dead:
		pass
	elif _roll_t > 0.0:
		_roll_t -= delta
		vel = _roll_dir * (float(_cfg["roll_speed"]) if _roll_t > 0.15 else 3.0)
		if rig == null:
			var rt: float = _cfg["roll_time"]
			_visual.rotation_degrees.x = -(1.0 - _roll_t / rt) * 360.0
	elif _stagger_t > 0.0:
		pass
	elif _stunned():
		_visual.rotation_degrees.x = 0.0
		if _status.has("electrocutado") and rig == null:
			_visual.rotation_degrees.z = randf_range(-7, 7)
	else:
		_visual.rotation_degrees.z = 0.0
		_visual.rotation_degrees.x = 0.0
		var d := _input_dir()
		var speed: float = _cfg["walk"]
		if _cast_t > 0.0:
			speed = 2.0
			_cast_t -= delta
		if kit.is_blocking():
			speed = 2.2
		if _attack_t > 0.0:
			speed = 0.0
			_attack_t -= delta
			var dur: float = _atk.get("dur", 0.55)
			var k := 1.0 - _attack_t / dur
			var hit_k: float = _atk.get("hit_k", 0.35)
			if not _atk.get("no_hit", false):
				kit.animate_attack(k)
				if k < hit_k:
					vel = _face_dir * 3.0
			if not _attack_hit and k > hit_k:
				_attack_hit = true
				_deal_damage()
			if _attack_t <= 0.0:
				_combo_step += 1
				_combo_window = 0.45
				if _combo_step >= kit.combo_length():
					_combo_step = 0
					_combo_window = 0.0
				if _combo_queued and _combo_window > 0.0 and stamina >= 8.0:
					_combo_queued = false
					_start_attack()
				_combo_queued = false
		else:
			kit.rest_pose(delta)
		_running = false
		if Input.is_key_pressed(KEY_SHIFT) and d != Vector3.ZERO and stamina > 1.0 and speed > 2.5:
			_running = true
			speed = _cfg["run"]
			stamina = maxf(0.0, stamina - 18.0 * delta)
			_st_delay = 0.3
		vel += d * speed
		if d != Vector3.ZERO and _attack_t <= 0.0:
			if _locked and _focus_target:
				var tb := _focus_target.global_position - global_position
				tb.y = 0.0
				_face_dir = tb.normalized()
			else:
				_face_dir = _face_dir.slerp(d, 1.0 - exp(-12.0 * delta)).normalized()
	vel += _knock
	_knock = _knock.move_toward(Vector3.ZERO, 30.0 * delta)
	velocity.x = vel.x
	velocity.z = vel.z
	if not is_on_floor():
		velocity.y -= 25.0 * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	_visual.rotation.y = atan2(-_face_dir.x, -_face_dir.z)
	_combo_window -= delta
	_drink_t -= delta
	# Guarda el arma de la mano derecha mientras bebe
	if kit.right_pivot:
		kit.right_pivot.visible = _drink_t <= 0.0
	if rig:
		rig.animate(delta, _rig_state())

	# Cámara
	_cam_yaw_node.global_position = global_position + Vector3(0, 1.7, 0)
	_cam_yaw_node.rotation = Vector3(0, _yaw, 0)
	_cam_pitch_node.rotation = Vector3(_pitch, 0, 0)
	_trauma = maxf(0.0, _trauma - delta * 1.4)
	var sh := _trauma * _trauma
	camera.h_offset = randf_range(-1, 1) * 0.35 * sh
	camera.v_offset = randf_range(-1, 1) * 0.35 * sh
	camera.rotation.z = randf_range(-1, 1) * 0.04 * sh


# =====================================================================
#  Estados alterados
# =====================================================================

## "electrocutado": no puedes moverte ni actuar (rayos del primer jefe).
## "quemadura": pierdes un poco de vida cada medio segundo (fuego).
## "atrapado": inmóvil mientras un jefe te sujeta.
func apply_status(effect: String, duration: float) -> void:
	if is_dead:
		return
	# Armadura de resistencia
	if effect == "electrocutado" and kit.resist_id == "aislante" and randf() < 0.5:
		return
	duration *= kit.resist(effect, "dur")
	_status[effect] = maxf(duration, float(_status.get(effect, 0.0)))
	if effect == "electrocutado" or effect == "atrapado":
		_roll_t = 0.0
		_attack_t = 0.0
		_heal_t = 0.0
	if effect == "electrocutado":
		add_camera_shake(0.35)
	_update_status_fx()
	status_changed.emit(get_status_names())


func _update_status_fx() -> void:
	_fx_shock.emitting = _status.has("electrocutado")
	_fx_burn.emitting = _status.has("quemadura")
	_fx_poison.emitting = _status.has("veneno") or _status.has("ameba")
	var pm := _fx_poison.draw_pass_1.surface_get_material(0) as StandardMaterial3D
	if pm:
		pm.albedo_color = Color(2.4, 0.6, 1.8) if _status.has("ameba") else Color(0.9, 2.6, 0.4)


func clear_status(effect: String) -> void:
	if _status.erase(effect):
		_update_status_fx()
		_visual.rotation_degrees.z = 0.0
		status_changed.emit(get_status_names())


func clear_statuses() -> void:
	for k in _status.keys():
		clear_status(k)


func has_status(effect: String) -> bool:
	return _status.has(effect)


func get_status_names() -> Array:
	return _status.keys()


func _stunned() -> bool:
	return _status.has("electrocutado") or _status.has("atrapado")


func _update_statuses(delta: float) -> void:
	for k in _buildup.keys():
		_buildup_wait[k] = float(_buildup_wait.get(k, 0.0)) - delta
		if float(_buildup_wait[k]) <= 0.0:
			_buildup[k] = float(_buildup[k]) - float(BUILDUP[k]["decay"]) * delta
			if float(_buildup[k]) <= 0.0:
				_buildup.erase(k)
	if _status.is_empty():
		return
	if _status.has("veneno") and not is_dead:
		_poison_tick -= delta
		if _poison_tick <= 0.0:
			_poison_tick = 0.6
			_status_damage(1.0 * kit.resist("veneno", "tick"))
	if _status.has("ameba") and not is_dead:
		_amoeba_tick -= delta
		if _amoeba_tick <= 0.0:
			_amoeba_tick = 0.3
			_status_damage(3.0 * kit.resist("ameba", "tick"))
			_trauma = maxf(_trauma, 0.2)
	for k in _status.keys():
		_status[k] = float(_status[k]) - delta
		if float(_status[k]) <= 0.0:
			clear_status(k)
	if _status.has("electrocutado"):
		_trauma = maxf(_trauma, 0.25)
	if _status.has("quemadura") and not is_dead:
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick = 0.5
			_status_damage(1.0 * kit.resist("quemadura", "tick"))


func _status_damage(amount: float) -> void:
	if is_dead:
		return
	hp = maxf(0.0, hp - amount)
	health_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_die()


## Suma a la barra de acumulación de un estado ("veneno", "ameba"). Al llegar
## a 100 se aplica el estado y la barra se vacía.
func add_buildup(effect: String, amount: float) -> void:
	if is_dead or not BUILDUP.has(effect):
		return
	_buildup_wait[effect] = 1.5
	var v := float(_buildup.get(effect, 0.0)) + amount * kit.resist(effect, "buildup")
	if v >= 100.0:
		_buildup.erase(effect)
		apply_status(effect, float(BUILDUP[effect]["duration"]))
		add_camera_shake(0.3)
	else:
		_buildup[effect] = v


## Barras para el HUD: efecto -> {"value": 0..1, "active": segundos restantes o 0}.
func get_buildups() -> Dictionary:
	var out := {}
	for k in BUILDUP.keys():
		var active := float(_status.get(k, 0.0))
		var v := float(_buildup.get(k, 0.0)) / 100.0
		if active > 0.0 or v > 0.0:
			out[k] = {"value": 1.0 if active > 0.0 else v, "active": active}
	return out


func clear_buildups() -> void:
	_buildup.clear()
	_buildup_wait.clear()


## Hoguera: vida completa, cafés recargados y sin estados alterados.
func rest() -> void:
	if is_dead:
		return
	clear_statuses()
	clear_buildups()
	hp = max_hp
	stamina = max_stamina
	flasks = _max_flasks
	kit.refill()
	health_changed.emit(hp, max_hp)


## Taza de café recogida: una taza más en el inventario (y llena).
func add_flask_capacity(n: int = 1) -> void:
	_max_flasks += n
	flasks = mini(flasks + n, _max_flasks)


func get_max_flasks() -> int:
	return _max_flasks


func _build_status_fx() -> void:
	for e in [["electrocutado", Color(0.5, 0.8, 1.0)], ["quemadura", Color(1.0, 0.45, 0.1)], ["veneno", Color(0.4, 1.0, 0.2)], ["ameba", Color(1.0, 0.4, 0.75)], ["atrapado", Color(1.0, 0.25, 0.2)]]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c: Color = e[1]
		m.albedo_color = Color(c.r * 0.9, c.g * 0.9, c.b * 0.9, 0.2)
		_rim[e[0]] = m
	# Partículas pequeñas que no tapan al jugador
	_fx_shock = _status_particles(Color(0.55, 0.85, 1.0), 16, 0.2, 0.035, 2.0)
	_fx_burn = _status_particles(Color(1.0, 0.45, 0.1), 10, 0.5, 0.06, 1.0)
	_fx_poison = _status_particles(Color(0.3, 0.85, 0.15), 8, 0.8, 0.05, 0.6)


func _status_particles(col: Color, amount: int, life: float, size: float, up: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.position = Vector3(0, 0.9, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = 0.45
	pm.emission_ring_inner_radius = 0.4
	pm.emission_ring_height = 1.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0 if up > 2.0 else 25.0
	pm.initial_velocity_min = up * 0.4
	pm.initial_velocity_max = up
	pm.gravity = Vector3(0, 0.5, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	p.process_material = pm
	# El tamaño va en la malla (la escala de partícula no se respeta con billboard)
	var q := QuadMesh.new()
	q.size = Vector2(size, size) * 1.6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = preload("res://boss_bibliotecario/library_fx.gd").soft_tex()
	# Sin brillo excesivo: el resplandor de la cámara las convertía en una mancha
	m.albedo_color = Color(col.r * 0.9, col.g * 0.9, col.b * 0.9, 0.85)
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p


## Revive al jugador (reintento tras morir contra un jefe).
func revive(pos: Vector3, yaw: float = 0.0) -> void:
	clear_statuses()
	clear_buildups()
	is_dead = false
	hp = max_hp
	stamina = max_stamina
	flasks = _max_flasks
	kit.refill()
	_roll_t = 0.0
	_attack_t = 0.0
	_cast_t = 0.0
	_stagger_t = 0.0
	_iframes = 1.0
	_knock = Vector3.ZERO
	velocity = Vector3.ZERO
	_visual.rotation_degrees = Vector3.ZERO
	_visual.position = Vector3.ZERO
	global_position = pos
	_yaw = yaw
	_face_dir = Vector3(-sin(yaw), 0, -cos(yaw))
	health_changed.emit(hp, max_hp)


func _deal_damage() -> void:
	for b in _targets():
		if not b.has_method("take_damage"):
			continue
		var to: Vector3 = b.global_position - global_position
		to.y = 0.0
		# Alcance del arma + tamaño del objetivo
		var base_reach: float = _atk.get("reach", 3.0)
		var reach := base_reach + (0.4 if b.is_in_group("boss") else float(b.get("hit_radius") if "hit_radius" in b else 0.5) - 0.7)
		var arc: float = _atk.get("arc", 0.3)
		if to.length() < reach and (to.length() < 1.0 or _face_dir.dot(to.normalized()) > arc):
			b.take_damage(_atk.get("damage", attack_damage), global_position)
			add_camera_shake(float(_atk.get("shake", 0.12)))
		elif _atk.has("aoe") and to.length() < base_reach + float(_atk["aoe"]) * 0.5:
			# Mazo: la onda del golpe alcanza un poco alrededor
			b.take_damage(float(_atk.get("damage", attack_damage)) * 0.5, global_position)


func _status_meshes() -> Array:
	var out: Array = _model_meshes.duplicate()
	if kit:
		out.append_array(kit.meshes)
	return out


## Maná para el HUD: [actual, máximo, bebidas]. Máximo 0 = la clase no usa maná.
func get_mana() -> Array:
	return [kit.mana, kit.max_mana, kit.drinks]


func get_ability_text() -> String:
	return kit.ability_text()


func get_class_name() -> String:
	return "%s · %s" % [_cfg["name"], _cfg["role"]]


## Estado que necesita el esqueleto para elegir la animación.
func _rig_state() -> Dictionary:
	var st := {}
	var hv := Vector2(velocity.x - _knock.x, velocity.z - _knock.z).length()
	st["speed"] = hv if _attack_t <= 0.0 and _roll_t <= 0.0 else 0.0
	st["run"] = _running and hv > 4.0
	st["hold"] = class_id != "ai"
	st["dead"] = is_dead
	if is_dead:
		return st
	if _roll_t > 0.0:
		st["roll"] = 1.0 - _roll_t / float(_cfg["roll_time"])
	st["stagger"] = _stagger_t > 0.0 and _roll_t <= 0.0
	st["shock"] = _status.has("electrocutado")
	st["grabbed"] = _status.has("atrapado")
	if _attack_t > 0.0 and _atk.has("anim"):
		st["action"] = _atk["anim"]
		st["k"] = 1.0 - _attack_t / float(_atk.get("dur", 0.5))
		st["hit_k"] = minf(float(_atk.get("hit_k", 0.4)), 0.9)
	elif _drink_t > 0.0:
		st["action"] = "curar"
		st["w"] = sin(clampf(_drink_t / 0.85, 0.0, 1.0) * PI) * 1.4
	elif kit.is_blocking():
		st["action"] = "bloquear"
		st["w"] = 1.0
	elif kit.action != "":
		st["action"] = kit.action
		st["w"] = clampf(minf(kit.action_t, kit.action_dur - kit.action_t) * 8.0, 0.0, 1.0)
	return st
