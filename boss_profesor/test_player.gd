extends CharacterBody3D
## Jugador de PRUEBA para probar la pelea (cámara en tercera persona).
## Cuando tengas tu propio personaje, desactiva "spawn_test_player" en BossFight y
## agrega tu jugador al grupo "player" con estos métodos:
##   take_damage(cantidad: float, desde: Vector3)    <- el jefe lo llama al golpearte
##   add_camera_shake(fuerza: float)                  <- opcional
##   var is_dead: bool                                <- opcional
## Para dañar al jefe: jefe.take_damage(cantidad)  (está en el grupo "boss").
##
## Controles: WASD mover · Shift correr · Espacio rodar · Clic izq. atacar
##            Clic medio / Tab fijar objetivo · F beber café (curar) · Esc soltar mouse

signal died
signal health_changed(hp: float, max_hp: float)

const PLAYER_MODEL: PackedScene = preload("res://Modelo/modelo.glb")

@export var max_hp := 100.0
@export var max_stamina := 100.0
@export var attack_damage := 40.0
@export var flasks := 4

var hp := 100.0
var stamina := 100.0
var is_dead := false

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
	_build_visual()
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
			KEY_F:
				_try_heal()


func _find_boss() -> Node3D:
	var best: Node3D = null
	for b in get_tree().get_nodes_in_group("boss"):
		if b is Node3D and b != self and is_instance_valid(b) and not b.is_queued_for_deletion():
			if not ("state" in b and b.get("state") == 5):
				best = b
	return best


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
	return _roll_t > 0.0 or _attack_t > 0.0 or _heal_t > 0.0 or _stagger_t > 0.0 or is_dead


func _try_roll() -> void:
	if is_dead or _roll_t > 0.0 or _stagger_t > 0.0 or stamina < 18.0:
		return
	_attack_t = 0.0
	_heal_t = 0.0
	var d := _input_dir()
	_roll_dir = d if d != Vector3.ZERO else -_face_dir
	_face_dir = _roll_dir
	_roll_t = 0.6
	_iframes = 0.42
	_use_stamina(20.0)


func _try_attack() -> void:
	if _busy() or stamina < 10.0:
		return
	_attack_t = 0.55
	_attack_hit = false
	_use_stamina(14.0)
	var b := _find_boss()
	if b and global_position.distance_to(b.global_position) < 7.0:
		var to := b.global_position - global_position
		to.y = 0.0
		_face_dir = to.normalized()


func _try_heal() -> void:
	if _busy() or flasks <= 0:
		return
	flasks -= 1
	_heal_t = 1.1


func _use_stamina(a: float) -> void:
	stamina = maxf(0.0, stamina - a)
	_st_delay = 0.6


func take_damage(amount: float, from: Variant = null) -> void:
	if is_dead or _iframes > 0.0:
		return
	hp = maxf(0.0, hp - amount)
	health_changed.emit(hp, max_hp)
	_m_body.emission_energy_multiplier = 2.0
	for mesh in _model_meshes:
		mesh.material_overlay = _m_body
	add_camera_shake(0.45)
	_attack_t = 0.0
	_heal_t = 0.0
	_stagger_t = 0.35
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
	if _m_body.emission_energy_multiplier == 0.0:
		for mesh in _model_meshes:
			mesh.material_overlay = null

	if _locked and (
		_focus_target == null
		or not is_instance_valid(_focus_target)
		or _focus_target.is_queued_for_deletion()
		or ("state" in _focus_target and _focus_target.get("state") == 5)
	):
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
		vel = _roll_dir * (10.5 if _roll_t > 0.15 else 3.0)
		_visual.rotation_degrees.x = -(1.0 - _roll_t / 0.6) * 360.0
	elif _stagger_t > 0.0:
		pass
	else:
		_visual.rotation_degrees.x = 0.0
		var d := _input_dir()
		var speed := 5.2
		if _heal_t > 0.0:
			speed = 1.5
			_heal_t -= delta
			if _heal_t <= 0.0:
				hp = minf(max_hp, hp + 45.0)
				health_changed.emit(hp, max_hp)
		if _attack_t > 0.0:
			speed = 0.0
			_attack_t -= delta
			var k := 1.0 - _attack_t / 0.55
			_sword_pivot.rotation_degrees = Vector3(lerpf(110.0, -70.0, clampf((k - 0.15) * 3.0, 0, 1)), 0, 0)
			if k < 0.35:
				vel = _face_dir * 3.0
			if not _attack_hit and k > 0.35:
				_attack_hit = true
				_deal_damage()
		else:
			_sword_pivot.rotation_degrees = _sword_pivot.rotation_degrees.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
		if Input.is_key_pressed(KEY_SHIFT) and d != Vector3.ZERO and stamina > 1.0 and speed > 2.0:
			speed = 8.0
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

	# Cámara
	_cam_yaw_node.global_position = global_position + Vector3(0, 1.7, 0)
	_cam_yaw_node.rotation = Vector3(0, _yaw, 0)
	_cam_pitch_node.rotation = Vector3(_pitch, 0, 0)
	_trauma = maxf(0.0, _trauma - delta * 1.4)
	var sh := _trauma * _trauma
	camera.h_offset = randf_range(-1, 1) * 0.35 * sh
	camera.v_offset = randf_range(-1, 1) * 0.35 * sh
	camera.rotation.z = randf_range(-1, 1) * 0.04 * sh


func _deal_damage() -> void:
	for b in get_tree().get_nodes_in_group("boss"):
		if not (b is Node3D) or not b.has_method("take_damage"):
			continue
		var to: Vector3 = b.global_position - global_position
		to.y = 0.0
		if to.length() < 3.4 and _face_dir.dot(to.normalized()) > 0.3:
			b.take_damage(attack_damage, global_position)
			add_camera_shake(0.12)
