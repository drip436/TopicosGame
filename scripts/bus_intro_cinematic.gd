extends Node3D
## Intro cinematográfica de llegada al campus.
##
## Secuencia: plano general del campus -> el autobús entra y frena -> plano de
## puertas -> el protagonista baja desde dentro -> alguien lo saca de una patada
## (congelado + cámara lenta) -> cae -> corte a negro -> el autobús arranca y, al
## irse, revela al protagonista en el suelo con el campus detrás -> se levanta ->
## la cámara se funde con la de juego y se entrega el control.
##
## Ejes: el autobús avanza hacia +X y sus puertas miran al campus (-Z).
## Si tu .glb no apunta así, corrige "bus_model_yaw_deg" en el Inspector.
## Enter / Espacio salta la intro.

const BUS_PATH := "res://modelos/utileria/autobus_amarillo.glb"
const PLAYER_SCRIPT := preload("res://boss_profesor/test_player.gd")
const ENV_KEYS := ["fog_density", "fog_light_color", "fog_light_energy",
		"volumetric_fog_density", "volumetric_fog_albedo"]

@export_group("Autobús")
@export var bus_length := 12.0
@export var bus_width := 2.55
@export var bus_floor_height := 0.35
## Giro del modelo .glb para que su frente apunte a +X.
@export var bus_model_yaw_deg := 0.0
@export var bus_model_offset := Vector3.ZERO
## Posición de las puertas medida desde el centro del autobús (hacia el frente = +).
@export var front_door_x := 4.6
@export var rear_door_x := 0.0
## Puertas corredizas generadas por código (desactívalo si el .glb trae puertas animadas).
@export var fake_doors := true

@export_group("Escena")
## Distancia de PlayerSpawn a la calle donde para el autobús.
@export var street_offset := Vector3(0.0, 0.0, 28.0)
## Texto opcional en el tercio inferior al revelar el campus (p. ej. "Campus Norte · 7:42 a.m.").
@export var location_title := ""
@export var arrival_time := 6.0
@export var arrival_distance := 40.0
@export_range(0.05, 1.0) var slowmo_scale := 0.3
@export var skip_intro := false

var _camera: Camera3D
var _camera_flags: Array = []
var _bus: Node3D        # pivote que se desplaza por la calle
var _bus_body: Node3D   # cabeceo al frenar / arrancar
var _doors: Array[Dictionary] = []
var _player: CharacterBody3D
var _kicker: Node3D
var _kicker_leg: Node3D
var _world_env: WorldEnvironment
var _sun: DirectionalLight3D
var _env_saved := {}
var _sun_saved := {}

var _street := Vector3.ZERO
var _campus := Vector3.ZERO
var _door_pos := Vector3.ZERO
var _land_pos := Vector3.ZERO

# Cámara narrativa
var _shot := Callable()
var _shot_t := 0.0
var _smooth := 4.0
var _snap := true
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _cam_fov := 50.0
var _trauma := 0.0
var _t := 0.0

# Capa de cine
var _ui: CanvasLayer
var _bar_top: ColorRect
var _bar_bot: ColorRect
var _fade: ColorRect
var _flash: ColorRect
var _title: Label

var _tweens: Array[Tween] = []
var _running := false
var _skipped := false
var _finished := false


# =====================================================================
#  Arranque
# =====================================================================

func _ready() -> void:
	_camera = get_parent().get_node_or_null("FreeCamera") as Camera3D
	if _camera == null:
		push_warning("Intro: no se encontró FreeCamera; se omite la cinemática.")
		return
	_build_world()
	_build_overlay()
	_running = true
	if skip_intro:
		_finish(true)
	else:
		_play_intro()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if _running and not _finished and _t > 1.0 and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_skipped = true
		_finish(true)


func _build_world() -> void:
	_world_env = get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	_sun = get_parent().get_node_or_null("StormLight") as DirectionalLight3D
	_save_lighting()

	var spawn := get_parent().get_node_or_null("PlayerSpawn") as Marker3D
	var anchor := spawn.global_position if spawn != null else Vector3(0.0, 0.0, 18.0)
	_street = anchor + street_offset
	_campus = anchor + Vector3(0.0, 4.0, -10.0)

	# Autobús: pivote (traslación) > carrocería (cabeceo) > modelo
	_bus = Node3D.new()
	_bus.name = "AutobusIntro"
	add_child(_bus)
	_bus.global_position = _bus_stop() + Vector3(-arrival_distance, 0.0, 0.0)
	_bus_body = Node3D.new()
	_bus_body.name = "Carroceria"
	_bus.add_child(_bus_body)
	var model := _spawn_bus_model()
	model.rotation_degrees.y = bus_model_yaw_deg
	model.position = bus_model_offset
	_bus_body.add_child(model)
	if fake_doors:
		for x in [front_door_x, rear_door_x]:
			_add_door(x)

	# Quien da la patada: espera dentro del autobús, oculto
	_kicker = _make_kicker()
	_bus_body.add_child(_kicker)
	_kicker.position = Vector3(front_door_x + 0.7, bus_floor_height, -0.15)
	_kicker.visible = false

	# Protagonista real: existe desde el principio, pero oculto y quieto hasta
	# que aparece DENTRO del autobús junto a la puerta.
	_player = PLAYER_SCRIPT.new() as CharacterBody3D
	_player.name = "Protagonista"
	_player.set("input_locked", true)
	add_child(_player)
	_player.visible = false
	_player.process_mode = Node.PROCESS_MODE_DISABLED

	# La cámara del jugador se hace current en diferido; esta llamada va después y gana.
	_camera_flags = [_camera.is_processing(), _camera.is_physics_processing(),
			_camera.is_processing_input(), _camera.is_processing_unhandled_input()]
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.set_process_input(false)
	_camera.set_process_unhandled_input(false)
	_camera.make_current.call_deferred()


# =====================================================================
#  Secuencia
# =====================================================================

func _play_intro() -> void:
	# --- 1. Plano general: el campus, y el autobús entra en cuadro y frena
	_cut_to(_shot_establishing, 1.4)
	_fade_to(0.0, 2.0)
	_sound("motor_llegada", _synth(arrival_time, 85.0, 55.0, 0.4, 0.55, 0.6, 0.5), Vector3.ZERO, -4.0, _bus)
	var arrive := _tw()
	arrive.tween_property(_bus, "global_position", _bus_stop(), arrival_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# La carrocería se inclina hacia delante mientras frena…
	var lean := _tw()
	lean.tween_interval(arrival_time * 0.55)
	lean.tween_property(_bus_body, "rotation:z", deg_to_rad(-1.4), arrival_time * 0.45)
	if await _wait(arrival_time - 1.6): return
	_sound("frenos", _synth(1.6, 180.0, 90.0, 0.85, 0.5, 0.05, 1.2), _bus.global_position, -2.0)
	if await _wait(1.6): return
	# …y rebota hacia atrás al detenerse
	var settle := _tw()
	settle.tween_property(_bus_body, "rotation:z", 0.0, 1.0) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_door_pos = _door_global()
	if await _wait(0.7): return

	# --- 2. Plano de puertas (lado del campus)
	_cut_to(_shot_doors, 3.0)
	if await _wait(0.6): return
	_set_doors(true)
	_place_player_inside()
	if await _wait(0.9): return

	# --- 3. El protagonista baja caminando; la cámara lo sigue
	_player.set("cinematic_move", _out_dir() * 1.4)
	_blend_to(_shot_exit, 2.2)
	if await _wait(0.85): return
	_player.set("cinematic_move", Vector3.ZERO)   # se detiene en el escalón y mira el campus
	if await _wait(0.6): return

	# --- 4. La patada: aparece el agresor en la puerta
	_kicker.visible = true
	var approach := _tw()
	approach.tween_property(_kicker, "position",
			Vector3(front_door_x + 0.05, bus_floor_height, -0.8), 0.4)
	_cut_to(_shot_kick, 7.0)   # corte en acción, ángulo bajo
	if await _wait(0.3): return
	var leg := _tw()
	leg.tween_property(_kicker_leg, "rotation:x", -0.55, 0.2)
	leg.parallel().tween_property(_kicker, "rotation:x", deg_to_rad(-8.0), 0.2)
	leg.tween_property(_kicker_leg, "rotation:x", 1.6, 0.09) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	if await _wait(0.2): return
	_sound("silbido", _synth(0.22, 420.0, 160.0, 0.95, 0.45, 0.06, 1.0), _door_pos, -6.0)
	if await _wait(0.09): return
	_impact()
	if await _wait(0.09, true): return   # congelado del golpe (tiempo real)
	Engine.time_scale = slowmo_scale
	_blend_to(_shot_fall, 5.0)
	if await _wait(0.45): return          # vuelo en cámara lenta
	Engine.time_scale = 1.0
	_sound("caida", _synth(0.5, 70.0, 35.0, 0.35, 0.9, 0.003, 2.5), _player.global_position, 0.0)
	_trauma = 0.6
	if await _wait(0.1): return

	# --- 5. Corte a negro: el golpe marca el cambio de escena
	_fade_to(1.0, 0.1)
	if await _wait(0.15): return
	_set_doors(false, 0.5)                # se oyen las puertas en negro
	_kicker.visible = false
	_kicker.rotation.x = 0.0
	_kicker_leg.rotation.x = 0.0
	_restore_lighting(1.2)
	_land_pos = _player.global_position
	if await _wait(0.75): return

	# --- 6. Revelación: el autobús se va y deja ver al protagonista y el campus
	_cut_to(_shot_reveal, 1.1)
	_fade_to(0.0, 1.3)
	if location_title != "":
		_show_title()
	if await _wait(0.9): return
	_sound("motor", _synth(4.5, 55.0, 115.0, 0.35, 0.65, 0.4, 0.8), Vector3.ZERO, 0.0, _bus)
	var tilt := _tw()
	tilt.tween_property(_bus_body, "rotation:z", deg_to_rad(0.9), 0.5)
	tilt.tween_property(_bus_body, "rotation:z", 0.0, 1.2)
	var leave := _tw()
	leave.tween_property(_bus, "global_position", _bus.global_position + Vector3(60.0, 0.0, 0.0), 5.0) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if await _wait(2.7): return            # el autobús ya despejó el plano
	_pcall("get_up", [1.2])
	if await _wait(1.4): return

	# --- 7. Entrega del control
	_finish(false)


func _impact() -> void:
	var from := _kicker.global_position + Vector3(0.0, 1.0, 0.0)
	_sound("golpe", _synth(0.35, 120.0, 45.0, 0.45, 0.95, 0.002, 3.0), _player.global_position, 2.0)
	_player.set("cinematic_move", Vector3.ZERO)
	_pcall("play_knockdown", [from, 12.0])
	_trauma = 0.9
	_flash.color.a = 0.85
	var tw := _tw()
	tw.tween_property(_flash, "color:a", 0.0, 0.4)
	_impact_light_and_fog()
	Engine.time_scale = 0.03


func _finish(instant: bool) -> void:
	if _finished:
		return
	_finished = true
	Engine.time_scale = 1.0
	for tw in _tweens:
		if tw and tw.is_valid():
			tw.kill()
	_tweens.clear()

	if instant:
		if not _player.visible:
			_player.global_position = Vector3(_street.x, _street.y, _street.z - bus_width * 0.5 - 2.5)
		_player.process_mode = Node.PROCESS_MODE_INHERIT
		_player.visible = true
		_player.set("cinematic_move", Vector3.ZERO)
		_pcall("get_up", [0.0])
		_pcall("cinematic_face", [_campus - _player.global_position])
		_fade.color.a = 0.0
		_flash.color.a = 0.0
		_title.modulate.a = 0.0
		_bar_top.offset_bottom = 0.0
		_bar_bot.offset_top = 0.0
		_restore_lighting(0.0)
		_end()
	else:
		_handoff()


## Funde la cámara de la intro con la cámara de juego y devuelve el control.
func _handoff() -> void:
	_pcall("cinematic_face", [_campus - _player.global_position])
	_blend_to(_shot_gameplay, 3.5)
	_letterbox(false, 1.2)
	await get_tree().create_timer(1.3).timeout
	_end()


func _end() -> void:
	_running = false
	if _player_cam():
		_player_cam().make_current()
	_player.set("input_locked", false)
	_camera.set_process(_camera_flags[0])
	_camera.set_physics_process(_camera_flags[1])
	_camera.set_process_input(_camera_flags[2])
	_camera.set_process_unhandled_input(_camera_flags[3])
	if is_instance_valid(_bus):
		_bus.queue_free()


# =====================================================================
#  Planos de cámara  (cada uno devuelve posición, punto de mira y FOV)
# =====================================================================

func _shot_establishing(t: float) -> Dictionary:
	var k := smoothstep(0.0, arrival_time + 1.0, t)
	var pos := _street + Vector3(-16.0, 10.0, 20.0).lerp(Vector3(-5.0, 3.2, 13.0), k)
	var bus_pt := _bus.global_position + Vector3(bus_length * 0.3, 1.6, 0.0)
	var look := _campus.lerp(bus_pt, smoothstep(0.6, 3.2, t) * 0.85)
	return {"pos": pos, "look": look, "fov": lerpf(52.0, 40.0, k)}


func _shot_doors(t: float) -> Dictionary:
	var k := smoothstep(0.0, 3.0, t)
	var pos := _door_pos + Vector3(2.4, 1.5, -3.6).lerp(Vector3(1.9, 1.4, -3.0), k)
	return {"pos": pos, "look": _door_pos + Vector3(0.0, 1.3, 0.0), "fov": 38.0}


func _shot_exit(t: float) -> Dictionary:
	var pos := _door_pos + Vector3(2.7, 1.45, -3.5).lerp(Vector3(2.3, 1.4, -3.9), smoothstep(0.0, 2.0, t))
	return {"pos": pos, "look": _player.global_position + Vector3(0.0, 1.4, 0.0), "fov": 36.0}


func _shot_kick(_t_: float) -> Dictionary:
	var look := (_player.global_position + Vector3(0.0, 1.3, 0.0)).lerp(_door_pos + Vector3(0.0, 1.5, 0.0), 0.3)
	return {"pos": _door_pos + Vector3(-2.2, 0.9, -3.0), "look": look, "fov": 34.0}


func _shot_fall(t: float) -> Dictionary:
	var k := smoothstep(0.0, 0.5, t)
	var look := _player.global_position + Vector3(0.0, lerpf(1.2, 0.5, k), 0.0)
	return {"pos": _door_pos + Vector3(-3.0, 1.0, -3.6), "look": look, "fov": lerpf(32.0, 36.0, k)}


func _shot_reveal(t: float) -> Dictionary:
	var k := smoothstep(2.5, 6.5, t)
	var pos := _land_pos + Vector3(2.5, 0.7, 9.0).lerp(Vector3(1.2, 1.9, 5.5), k)
	var look := (_land_pos + Vector3(0.0, 0.5, 0.0)).lerp(_land_pos + Vector3(0.0, 2.6, -12.0), k * 0.8)
	return {"pos": pos, "look": look, "fov": lerpf(38.0, 50.0, k)}


func _shot_gameplay(_t_: float) -> Dictionary:
	var c := _player_cam()
	return {"pos": c.global_position, "look": c.global_position - c.global_transform.basis.z * 8.0, "fov": c.fov}


func _cut_to(shot: Callable, smooth: float) -> void:
	_shot = shot
	_shot_t = 0.0
	_smooth = smooth
	_snap = true


func _blend_to(shot: Callable, smooth: float) -> void:
	_shot = shot
	_shot_t = 0.0
	_smooth = smooth
	_snap = false


func _process(delta: float) -> void:
	if not _running or not _shot.is_valid():
		return
	_t += delta
	_shot_t += delta
	var s: Dictionary = _shot.call(_shot_t)
	var pos: Vector3 = s["pos"]
	var look: Vector3 = s["look"]
	var fov: float = s.get("fov", _cam_fov)
	if _snap:
		_cam_pos = pos
		_cam_look = look
		_cam_fov = fov
		_snap = false
	else:
		var k := 1.0 - exp(-_smooth * delta)
		_cam_pos = _cam_pos.lerp(pos, k)
		_cam_look = _cam_look.lerp(look, k)
		_cam_fov = lerpf(_cam_fov, fov, k)
	# Respiración de cámara en mano + sacudida por impacto
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	var sh := _trauma * _trauma
	var breathe := Vector3(sin(_t * 0.7), sin(_t * 0.93) * 0.6, 0.0) * 0.025
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.25 * sh
	_camera.global_position = _cam_pos + breathe + jitter
	if _camera.global_position.distance_squared_to(_cam_look) > 0.0001:
		_camera.look_at(_cam_look, Vector3.UP)
	_camera.rotate_object_local(Vector3.FORWARD, randf_range(-1, 1) * 0.05 * sh)
	_camera.fov = _cam_fov


# =====================================================================
#  Autobús, puertas, actores
# =====================================================================

func _bus_stop() -> Vector3:
	# El autobús se detiene con la puerta delantera a la altura del campus
	return Vector3(_street.x - front_door_x, _street.y, _street.z)


func _door_global() -> Vector3:
	return _bus_body.to_global(Vector3(front_door_x, 0.0, -bus_width * 0.5))


func _out_dir() -> Vector3:
	return (_bus.global_transform.basis * Vector3.FORWARD).normalized()


func _place_player_inside() -> void:
	_player.global_position = _bus_body.to_global(Vector3(front_door_x - 0.15, 0.0, -0.35))
	_player.velocity = Vector3.ZERO
	_pcall("cinematic_face", [_out_dir()])
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_player.visible = true


func _spawn_bus_model() -> Node3D:
	if ResourceLoader.exists(BUS_PATH):
		var packed := load(BUS_PATH) as PackedScene
		if packed:
			var inst := packed.instantiate() as Node3D
			if inst:
				return inst
	# Respaldo: caja azul con ruedas
	var bus := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(bus_length, 2.8, bus_width)
	body.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.25, 0.7)
	body.material_override = mat
	body.position.y = bus_floor_height + 1.4
	bus.add_child(body)
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.08, 0.08, 0.08)
	for x in [bus_length * 0.3, -bus_length * 0.2]:
		for z in [-bus_width * 0.42, bus_width * 0.42]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			cyl.height = 0.3
			wheel.mesh = cyl
			wheel.material_override = wheel_mat
			wheel.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			wheel.position = Vector3(x, 0.5, z)
			bus.add_child(wheel)
	return bus


func _add_door(x: float) -> void:
	var z := -(bus_width * 0.5 + 0.03)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.06, 0.08, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.4
	mat.roughness = 0.1
	for side in [-1.0, 1.0]:
		var leaf := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.62, 2.3, 0.05)
		leaf.mesh = box
		leaf.material_override = mat
		var closed := Vector3(x + side * 0.31, bus_floor_height + 1.15, z)
		leaf.position = closed
		_bus_body.add_child(leaf)
		_doors.append({"node": leaf, "closed": closed, "open": closed + Vector3(side * 0.5, 0.0, -0.14)})


## Puertas de autobús: primero salen hacia fuera y luego se deslizan.
func _set_doors(open: bool, t := 0.7) -> void:
	for d in _doors:
		var node: Node3D = d["node"]
		var c: Vector3 = d["closed"]
		var o: Vector3 = d["open"]
		var out := Vector3(c.x, c.y, o.z)
		var tw := _tw()
		if open:
			tw.tween_property(node, "position", out, t * 0.3)
			tw.tween_property(node, "position", o, t * 0.7)
		else:
			tw.tween_property(node, "position", out, t * 0.7)
			tw.tween_property(node, "position", c, t * 0.3)
	_sound("puertas", _synth(0.9, 900.0, 300.0, 0.9, 0.45, 0.01, 1.5), _door_global(), -4.0)


func _make_kicker() -> Node3D:
	var root := Node3D.new()
	root.name = "Agresor"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.12, 0.1)
	mat.roughness = 0.8
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.2
	body.mesh = cap
	body.material_override = mat
	body.position.y = 1.25
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.17
	sph.height = 0.34
	head.mesh = sph
	head.material_override = mat
	head.position.y = 2.02
	root.add_child(head)
	# Mira hacia -Z (hacia la puerta); la pierna derecha pivota en la cadera
	for i in 2:
		var hip := Node3D.new()
		hip.position = Vector3(-0.12 if i == 0 else 0.12, 0.82, 0.0)
		root.add_child(hip)
		var leg := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.16, 0.82, 0.16)
		leg.mesh = lb
		leg.material_override = mat
		leg.position.y = -0.41
		hip.add_child(leg)
		if i == 1:
			_kicker_leg = hip
	return root


# =====================================================================
#  Capa de cine: barras, fundidos, destello, título
# =====================================================================

func _build_overlay() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 50
	add_child(_ui)
	var h := _bar_height()
	_bar_top = _overlay_rect(Color.BLACK)
	_bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_top.offset_bottom = h
	_bar_bot = _overlay_rect(Color.BLACK)
	_bar_bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bot.offset_top = -h
	_fade = _overlay_rect(Color(0, 0, 0, 1))
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash = _overlay_rect(Color(1.0, 0.95, 0.85, 0.0))
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title = Label.new()
	_title.text = location_title
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_title.add_theme_constant_override("shadow_offset_x", 2)
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_title.modulate.a = 0.0
	_title.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_title.offset_left = 56.0
	_title.offset_right = 1200.0
	_title.offset_top = -h - 80.0
	_title.offset_bottom = -h - 24.0
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_title)


func _overlay_rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(r)
	return r


func _bar_height() -> float:
	return get_viewport().get_visible_rect().size.y * 0.11


func _letterbox(on: bool, t: float) -> void:
	var h := _bar_height() if on else 0.0
	var tw := _tw()
	tw.tween_property(_bar_top, "offset_bottom", h, t)
	tw.parallel().tween_property(_bar_bot, "offset_top", -h, t)


func _fade_to(alpha: float, t: float) -> void:
	var tw := _tw()
	tw.tween_property(_fade, "color:a", alpha, t)


func _show_title() -> void:
	var tw := _tw()
	tw.tween_interval(0.8)
	tw.tween_property(_title, "modulate:a", 1.0, 0.8)
	tw.tween_interval(2.2)
	tw.tween_property(_title, "modulate:a", 0.0, 0.8)


# =====================================================================
#  Luz y niebla del impacto (se restauran los valores originales de la escena)
# =====================================================================

func _save_lighting() -> void:
	if _world_env and _world_env.environment:
		for k in ENV_KEYS:
			_env_saved[k] = _world_env.environment.get(k)
	if _sun:
		_sun_saved = {"light_color": _sun.light_color, "light_energy": _sun.light_energy}


func _impact_light_and_fog() -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var env := _world_env.environment
	var tw := _tw()
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(env, "fog_density", 0.024, 0.55)
	tw.parallel().tween_property(env, "fog_light_color", Color(0.93, 0.72, 0.58), 0.55)
	tw.parallel().tween_property(env, "fog_light_energy", 1.15, 0.55)
	tw.parallel().tween_property(env, "volumetric_fog_density", 0.028, 0.55)
	tw.parallel().tween_property(env, "volumetric_fog_albedo", Color(0.82, 0.63, 0.46), 0.55)
	if _sun:
		tw.parallel().tween_property(_sun, "light_color", Color(0.96, 0.80, 0.63), 0.55)
		tw.parallel().tween_property(_sun, "light_energy", 0.85, 0.55)


func _restore_lighting(t: float) -> void:
	var env: Environment = _world_env.environment if _world_env else null
	if t <= 0.0:
		if env:
			for k in _env_saved:
				env.set(k, _env_saved[k])
		if _sun:
			for k in _sun_saved:
				_sun.set(k, _sun_saved[k])
		return
	if (env == null or _env_saved.is_empty()) and (_sun == null or _sun_saved.is_empty()):
		return
	var tw := _tw()
	tw.set_parallel(true)
	if env:
		for k in _env_saved:
			tw.tween_property(env, k, _env_saved[k], t)
	if _sun:
		for k in _sun_saved:
			tw.tween_property(_sun, k, _sun_saved[k], t)


# =====================================================================
#  Utilidades
# =====================================================================

var _warned := {}

## Llama a un método del jugador solo si existe (si falta, avisa una vez y sigue).
func _pcall(method: String, args: Array = []) -> void:
	if _player.has_method(method):
		_player.callv(method, args)
	elif not _warned.has(method):
		_warned[method] = true
		push_warning("Intro: %s no tiene '%s()'. Revisa los cambios de test_player.gd." % ["res://boss_profesor/test_player.gd", method])


func _player_cam() -> Camera3D:
	return _player.get("camera") as Camera3D

func _tw() -> Tween:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tw)
	return tw


## Espera `t` segundos (de juego, o reales si `real`). Devuelve true si se saltó la intro.
func _wait(t: float, real := false) -> bool:
	if _skipped or not is_inside_tree():
		return true
	var timer := get_tree().create_timer(t, true, false, real)
	while timer.time_left > 0.0 and not _skipped:
		await get_tree().process_frame
	return _skipped


func _sound(id: String, stream: AudioStreamWAV, pos: Vector3, volume_db := 0.0, parent: Node3D = null) -> void:
	var p := AudioStreamPlayer3D.new()
	p.name = "Intro_" + id
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = 8.0
	p.max_distance = 80.0
	if parent:
		parent.add_child(p)
	else:
		add_child(p)
		p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


## Sonido sintético de un solo disparo: tono que barre de f0 a f1 mezclado con ruido.
func _synth(dur: float, f0: float, f1: float, noise: float, amp: float, attack := 0.005, decay := 2.0) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var k := t / dur
		phase += TAU * lerpf(f0, f1, k) / rate
		var env := minf(1.0, t / maxf(attack, 0.0001)) * pow(1.0 - k, decay)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.35)
		var s := (sin(phase) * (1.0 - noise) + lp * noise) * env * amp
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = data
	return wav
