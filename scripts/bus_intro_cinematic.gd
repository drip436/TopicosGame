extends Node3D
## Intro cinematográfica de llegada al campus.
##
## 1. Plano general del campus: el autobús llega por la calle y frena.
## 2. Plano INTERIOR: el protagonista recorre el pasillo mientras se abren las puertas.
## 3. Plano exterior de la puerta: llega al escalón y mira el campus.
## 4. Un pasajero que venía detrás lo empuja (congelado + cámara lenta) y cae a la banqueta.
## 5. Corte a negro. El autobús arranca y, al irse, revela al protagonista en el suelo.
## 6. Se levanta, la cámara se funde con la de juego y se entrega el control.
##
## Durante la intro se ocultan HUD / barras (todas las CanvasLayer ajenas) y se congelan
## el jefe y la pelea (grupos "boss" y "enemy" y cualquier nodo con boss_fight.gd).
## Enter / Espacio salta la intro.
##
## Ejes del autobús (local): frente +X, puertas +Z, arriba +Y. Así sale el .glb de Blender.

signal intro_started
signal intro_finished

const BUS_PATH := "res://modelos/utileria/autobus_metropolitano.glb"
const PLAYER_SCRIPT_PATH := "res://boss_profesor/test_player.gd"
const PLAYER_SCRIPT := preload("res://boss_profesor/test_player.gd")
const ENV_KEYS := ["fog_density", "fog_light_color", "fog_light_energy",
		"volumetric_fog_density", "volumetric_fog_albedo"]

@export_group("Autobús")
@export var bus_length := 12.0
@export var bus_width := 2.55
## Altura del piso interior (0.38 en el modelo de Blender).
@export var bus_floor_height := 0.38
## Hacia dónde mira el autobús en el mundo. 180 = avanza hacia -X con las puertas hacia -Z (campus).
@export var bus_world_yaw_deg := 180.0
@export var front_door_x := 4.95
@export var wheel_radius := 0.5
@export var interior_lights := true
@export var headlights := true
@export var show_driver := true
@export var driver_shirt := Color(0.55, 0.68, 0.85)
@export var pusher_shirt := Color(0.35, 0.05, 0.06)

@export_group("Escena")
## Distancia de PlayerSpawn a la calle donde para el autobús.
@export var street_offset := Vector3(0.0, 0.0, 28.0)
## Texto opcional al revelar el campus (p. ej. "Campus Norte · 7:42 a.m.").
@export var location_title := ""
@export var arrival_time := 6.0
## Recorrido del autobús al llegar y al irse. El sector de la plaza está cerrado por
## barricadas en x = -42 y x = 45 (campus_world.gd): con 30 / 34 m no las atraviesa.
@export var arrival_distance := 30.0
@export var leave_distance := 34.0
@export_range(0.05, 1.0) var slowmo_scale := 0.3
@export var skip_intro := false

@export_group("Juego durante la intro")
## Usa el jugador que ya exista en el grupo "player" (p. ej. el que crea BossFight) en vez de crear otro.
@export var use_existing_player := true
@export var hide_hud := true
## Nodos en estos grupos quedan congelados hasta que termina la intro.
@export var pause_groups: Array[String] = ["boss", "enemy"]
## Nodos cuyo script contenga alguno de estos textos también se congelan.
@export var pause_script_hints: Array[String] = ["boss_fight"]
@export var pause_nodes: Array[NodePath] = []

@export_group("Arena")
## Abre el muro invisible de la arena (ArenaBounds) en el tramo de la puerta para que el
## jugador entre caminando desde la calle. Al cruzar se vuelve a cerrar y empieza la pelea.
@export var open_arena_gate := true
## Dirección de la puerta vista desde el centro de la arena (0 = +Z, donde está CampusGate).
@export var arena_gate_angle_deg := 0.0
@export var arena_gate_half_angle_deg := 17.0
## El jefe sigue congelado hasta que el jugador entra a la arena.
@export var hold_fight_until_inside := true

var _camera: Camera3D
var _camera_flags: Array = []
var _bus: Node3D        # pivote que se desplaza por la calle
var _bus_body: Node3D   # cabeceo al frenar / arrancar
var _bus_prev := Vector3.ZERO
var _wheels: Array[Node3D] = []
var _doors: Array[Dictionary] = []
var _player: CharacterBody3D
var _player_saved := {}
var _driver: Node3D
var _pusher: Node3D
var _walkers := {}          # NPC -> fase del ciclo de caminar
var _puppet := false        # la intro mueve y anima al jugador
var _puppet_state := "idle" # idle, walk, fly, down
var _puppet_speed := 0.0
var _puppet_yaw := 0.0
var _bob_t := 0.0
var _hud_released := false
var _tex_cache := {}
var _arena: StaticBody3D
var _gate_shapes: Array[CollisionShape3D] = []
var _arena_r := 0.0
var _watching_arena := false
var _bf: Node   # BossFight con set_cinematic(): maneja su HUD y la entrada a la arena
var _floor_body: StaticBody3D
var _player_vis: Node3D
var _world_env: WorldEnvironment
var _sun: DirectionalLight3D
var _env_saved := {}
var _sun_saved := {}

var _street := Vector3.ZERO
var _campus := Vector3.ZERO
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

# HUD y pelea suspendidos
var _hidden_ui := {}
var _paused := {}
var _sweep_t := 0.0

var _tweens: Array[Tween] = []
var _warned := {}
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
	_running = true
	get_tree().set_meta("intro_activa", true)
	intro_started.emit()
	_build_overlay()   # empieza en negro
	_take_camera()
	_bf = _find_boss_fight()
	if _bf:
		_bf.call("set_cinematic", true)
	get_tree().node_added.connect(_on_node_added)
	_sweep(true)
	# Deja que los demás nodos (BossFight, HUD…) terminen de crearse
	await get_tree().process_frame
	await get_tree().process_frame
	_sweep(true)
	_build_world()
	if skip_intro:
		_finish(true)
	else:
		_play_intro()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if get_tree() and get_tree().has_meta("intro_activa"):
		get_tree().remove_meta("intro_activa")


func _unhandled_input(event: InputEvent) -> void:
	if _running and not _finished and _t > 1.0 and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_skipped = true
		_finish(true)


func _take_camera() -> void:
	_camera_flags = [_camera.is_processing(), _camera.is_physics_processing(),
			_camera.is_processing_input(), _camera.is_processing_unhandled_input()]
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.set_process_input(false)
	_camera.set_process_unhandled_input(false)
	_camera.make_current()


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
	_bus.rotation.y = deg_to_rad(bus_world_yaw_deg)
	_bus.global_position = _bus_stop() - _bus_fwd() * arrival_distance
	_bus_prev = _bus.global_position
	_bus_body = Node3D.new()
	_bus_body.name = "Carroceria"
	_bus.add_child(_bus_body)
	var model := _spawn_bus_model()
	_bus_body.add_child(model)
	_find_bus_parts(model)
	_add_bus_extras()

	# Chofer sentado con las manos en el volante
	if show_driver:
		_driver = _make_person("Chofer", {"shirt": driver_shirt, "pants": Color(0.08, 0.1, 0.18),
				"skin": Color(0.72, 0.52, 0.38), "wear": "gorra", "mustache": true})
		_bus_body.add_child(_driver)
		_driver.position = Vector3(5.05, bus_floor_height - 0.36, -0.68)
		_npc_face(_driver, Vector3.RIGHT)
		_pose_seated(_driver)
		for side in [-1.0, 1.0]:
			_reach(_driver, side, _bl(Vector3(5.36, 1.3, -0.68 + side * 0.15)))
	# Pasajero que viaja detrás del protagonista y lo empuja fuera
	_pusher = _make_person("Empujador", {"shirt": pusher_shirt, "shirt_kind": "knit", "hoodie": true,
			"pants": Color(0.15, 0.22, 0.38), "pants_kind": "denim", "rolled": true,
			"skin": Color(0.62, 0.45, 0.33), "wear": "capucha", "stubble": true, "angry": true,
			"shoes": Color(0.16, 0.16, 0.18), "sole": Color(0.92, 0.92, 0.9), "print": "SIN RUMBO",
			"armor": true})
	_bus_body.add_child(_pusher)
	_pusher.position = Vector3(front_door_x - 5.3, bus_floor_height, 0.05)
	_npc_face(_pusher, Vector3.RIGHT)

	_setup_player()


func _setup_player() -> void:
	if use_existing_player:
		for p in get_tree().get_nodes_in_group("player"):
			if p is CharacterBody3D and is_instance_valid(p) and not is_ancestor_of(p):
				_player = p
				break
	if _player == null:
		_player = PLAYER_SCRIPT.new() as CharacterBody3D
		_player.name = "Protagonista"
		add_child(_player)
	_player_saved = {"mode": _player.process_mode, "visible": _player.visible}
	_player.set("input_locked", true)
	_player.visible = false
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_camera.make_current()


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
	var lean := _tw()   # la carrocería se inclina al frenar…
	lean.tween_interval(arrival_time * 0.55)
	lean.tween_property(_bus_body, "rotation:z", deg_to_rad(-1.4), arrival_time * 0.45)
	if await _wait(arrival_time - 1.6): return
	_sound("frenos", _synth(1.6, 180.0, 90.0, 0.85, 0.5, 0.05, 1.2), _bus.global_position, -2.0)
	if await _wait(1.6): return
	var settle := _tw()   # …y rebota al detenerse
	settle.tween_property(_bus_body, "rotation:z", 0.0, 1.0) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if await _wait(0.8): return

	# --- 2. Interior: el protagonista va por el pasillo; el pasajero de atrás lo sigue
	_place_player(Vector3(front_door_x - 3.4, bus_floor_height + 0.02, 0.0), _bus_dir(Vector3.RIGHT))
	_cut_to(_shot_interior, 2.5)
	if await _wait(0.7): return
	_set_doors(true)
	_turn_head(_driver, -0.7, 0.5)        # el chofer voltea hacia la puerta
	if await _wait(0.5): return
	var follow := _npc_walk(_pusher, [Vector3(front_door_x - 0.9, bus_floor_height, 0.05),
			Vector3(front_door_x - 0.05, bus_floor_height, bus_width * 0.5 - 1.2)], 1.15, 0.6)
	if await _walk_to(Vector3(front_door_x - 1.5, 0.0, 0.0), 1.25): return

	# --- 3. Exterior: llega a la puerta, gira y se detiene en el escalón
	_cut_to(_shot_door, 2.5)
	if await _walk_to(Vector3(front_door_x - 0.05, 0.0, 0.0), 1.2): return
	if await _walk_to(Vector3(front_door_x, 0.0, bus_width * 0.5 - 0.35), 0.9): return
	_face(_bus_dir(Vector3.BACK))         # se queda mirando el campus
	if await _wait_tween(follow): return
	if await _wait(0.5): return

	# --- 4. El empujón
	_cut_to(_shot_kick, 7.0)              # ángulo bajo desde la banqueta
	var push := _tw()
	push.set_parallel(true)               # carga: brazos al pecho, cuerpo atrás
	push.tween_property(_part(_pusher, "Torso"), "rotation:x", 0.12, 0.28)
	for side in ["I", "D"]:
		push.tween_property(_part(_pusher, "Hombro_" + side), "rotation:x", 1.0, 0.28)
		push.tween_property(_part(_pusher, "Codo_" + side), "rotation:x", 1.7, 0.28)
	push.chain().tween_interval(0.0)
	push.set_parallel(true)               # empuje: brazos estirados y paso al frente
	push.tween_property(_part(_pusher, "Torso"), "rotation:x", -0.35, 0.13).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	push.tween_property(_pusher, "position:z", _pusher.position.z + 0.3, 0.13)
	for side in ["I", "D"]:
		push.tween_property(_part(_pusher, "Hombro_" + side), "rotation:x", 1.45, 0.13).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		push.tween_property(_part(_pusher, "Codo_" + side), "rotation:x", 0.1, 0.13).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	if await _wait(0.3): return
	_sound("silbido", _synth(0.22, 420.0, 160.0, 0.95, 0.45, 0.06, 1.0), _door_world(), -6.0)
	if await _wait(0.12): return
	_impact()
	if await _wait(0.09, true): return    # congelado del golpe (tiempo real)
	Engine.time_scale = slowmo_scale
	var fall := _push_out()
	_blend_to(_shot_fall, 5.0)
	if await _wait(0.45): return          # vuelo en cámara lenta
	Engine.time_scale = 1.0
	if await _wait_tween(fall): return
	_sound("caida", _synth(0.5, 70.0, 35.0, 0.35, 0.9, 0.003, 2.5), _player.global_position, 0.0)
	_trauma = 0.6
	if await _wait(0.25): return

	# --- 5. Corte a negro: el golpe marca el cambio de escena
	_fade_to(1.0, 0.1)
	if await _wait(0.15): return
	_set_doors(false, 0.5)                # se oyen las puertas en negro
	_rest_pose(_pusher)                   # el que empujó se queda dentro mirando
	_pusher.position = Vector3(front_door_x - 0.5, bus_floor_height, 0.2)
	_npc_face(_pusher, Vector3.BACK)
	_turn_head(_driver, 0.0, 0.3)
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
	leave.tween_property(_bus, "global_position", _bus.global_position + _bus_fwd() * leave_distance, 4.2) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	leave.tween_callback(func() -> void: _bus.visible = false)
	if await _wait(2.7): return
	var up := _get_up(1.3)                # se levanta como si nada
	if await _wait_tween(up): return
	_release_hud()                        # vuelven la vida y la estamina
	if _bf and is_instance_valid(_bf):
		_bf.call("set_cinematic", false)
	_letterbox(false, 0.8)
	if await _wait(0.9): return

	# --- 7. Entrega del control
	_finish(false)


func _impact() -> void:
	_sound("golpe", _synth(0.35, 120.0, 45.0, 0.45, 0.95, 0.002, 3.0), _player.global_position, 2.0)
	_player.set("cinematic_move", Vector3.ZERO)
	_pcall("add_camera_shake", [0.6])
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
	if _player == null:   # se saltó antes de crear el mundo
		_build_world()

	if instant:
		if not _player.visible:
			_bus.global_position = _bus_stop()
			_player.global_position = _bus_body.to_global(Vector3(front_door_x, 0.05, bus_width * 0.5 + 2.5))
		_puppet = false
		_player.process_mode = Node.PROCESS_MODE_PAUSABLE
		_player.visible = true
		_player.set("cinematic_move", Vector3.ZERO)
		var vis := _visual()
		vis.rotation.x = 0.0
		vis.rotation.z = 0.0
		vis.position.y = 0.0
		_face(_campus - _player.global_position)
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
	_face(_campus - _player.global_position)
	_blend_to(_shot_gameplay, 3.5)
	_letterbox(false, 1.2)
	await get_tree().create_timer(1.3).timeout
	_end()


func _end() -> void:
	_running = false
	_puppet = false
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	_resume_ui()
	if _bf and is_instance_valid(_bf):
		_bf.call("set_cinematic", false)   # BossFight abre la entrada y muestra su HUD
		_resume_fight()
	elif not _open_arena():
		_resume_fight()
	if _player_cam():
		_player_cam().make_current()
	_player.set("input_locked", false)
	_player.process_mode = _player_saved.get("mode", Node.PROCESS_MODE_INHERIT)
	_camera.set_process(_camera_flags[0])
	_camera.set_physics_process(_camera_flags[1])
	_camera.set_process_input(_camera_flags[2])
	_camera.set_process_unhandled_input(_camera_flags[3])
	if is_instance_valid(_bus):
		_bus.queue_free()
	if get_tree().has_meta("intro_activa"):
		get_tree().remove_meta("intro_activa")
	_ui.queue_free()
	intro_finished.emit()


# =====================================================================
#  Planos de cámara (cada uno devuelve posición, punto de mira y FOV)
#  _bl() = coordenadas locales del autobús: X frente, Z lado de puertas
# =====================================================================

func _shot_establishing(t: float) -> Dictionary:
	var k := smoothstep(0.0, arrival_time + 1.0, t)
	var pos := _street + Vector3(-16.0, 10.0, 20.0).lerp(Vector3(-5.0, 3.2, 13.0), k)
	var bus_pt := _bl(Vector3(bus_length * 0.3, 1.6, 0.0))
	var look := _campus.lerp(bus_pt, smoothstep(0.6, 3.2, t) * 0.85)
	return {"pos": pos, "look": look, "fov": lerpf(52.0, 40.0, k)}


func _shot_interior(t: float) -> Dictionary:
	# Desde el puesto del conductor mirando el pasillo; avanza muy despacio
	var k := smoothstep(0.0, 4.0, t)
	var pos := _bl(Vector3(front_door_x + 0.5 - 0.15 * k, bus_floor_height + 1.75, 0.15))
	var head := _player.global_position + Vector3(0.0, 1.45, 0.0)
	var aisle := _bl(Vector3(0.0, bus_floor_height + 1.3, 0.0))
	return {"pos": pos, "look": aisle.lerp(head, 0.75), "fov": 62.0}


func _shot_door(t: float) -> Dictionary:
	# Desde la banqueta: la puerta abierta y el interior iluminado detrás
	var k := smoothstep(0.0, 3.0, t)
	var pos := _bl(Vector3(front_door_x - 1.3, 1.6, bus_width * 0.5 + 4.6).lerp(
			Vector3(front_door_x - 0.8, 1.5, bus_width * 0.5 + 3.8), k))
	var door := _bl(Vector3(front_door_x, bus_floor_height + 1.3, bus_width * 0.5 - 0.3))
	var head := _player.global_position + Vector3(0.0, 1.4, 0.0)
	return {"pos": pos, "look": door.lerp(head, 0.5), "fov": 44.0}


func _shot_kick(_t_: float) -> Dictionary:
	var pos := _bl(Vector3(front_door_x + 2.1, 0.8, bus_width * 0.5 + 2.4))
	var look := (_player.global_position + Vector3(0.0, 1.3, 0.0)).lerp(
			_bl(Vector3(front_door_x, bus_floor_height + 1.4, bus_width * 0.5)), 0.3)
	return {"pos": pos, "look": look, "fov": 36.0}


func _shot_fall(t: float) -> Dictionary:
	var k := smoothstep(0.0, 0.5, t)
	var look := _player.global_position + Vector3(0.0, lerpf(1.2, 0.5, k), 0.0)
	return {"pos": _bl(Vector3(front_door_x + 3.6, 1.1, bus_width * 0.5 + 4.8)), "look": look,
			"fov": lerpf(34.0, 38.0, k)}


func _shot_reveal(t: float) -> Dictionary:
	# Desde el otro lado de la calle: el autobús tapa y al irse descubre la escena
	var street_side := (_street - _campus)
	street_side.y = 0.0
	street_side = street_side.normalized()
	var side := street_side.cross(Vector3.UP)
	var k := smoothstep(2.5, 6.5, t)
	var far := _land_pos + street_side * 9.0 + side * 2.5 + Vector3(0.0, 0.7, 0.0)
	var near := _land_pos + street_side * 5.5 + side * 1.2 + Vector3(0.0, 1.9, 0.0)
	var look := (_land_pos + Vector3(0.0, 0.5, 0.0)).lerp(_land_pos - street_side * 12.0 + Vector3(0.0, 2.6, 0.0), k * 0.8)
	return {"pos": far.lerp(near, k), "look": look, "fov": lerpf(38.0, 50.0, k)}


func _shot_gameplay(_t_: float) -> Dictionary:
	var c := _player_cam()
	if c == null:
		return {"pos": _cam_pos, "look": _cam_look, "fov": _cam_fov}
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
	if _watching_arena:
		_watch_arena()
	if not _running:
		return
	_sweep_t -= delta
	if _sweep_t <= 0.0:
		_sweep_t = 0.5
		_sweep(false)
	_spin_wheels()
	_animate_walkers(delta)
	if not _shot.is_valid():
		return
	# El jugador hace make_current() en diferido al crearse: la intro conserva la cámara
	if _camera.get_viewport().get_camera_3d() != _camera:
		_camera.make_current()
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
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	var sh := _trauma * _trauma
	var breathe := Vector3(sin(_t * 0.7), sin(_t * 0.93) * 0.6, 0.0) * 0.02
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.25 * sh
	_camera.global_position = _cam_pos + breathe + jitter
	if _camera.global_position.distance_squared_to(_cam_look) > 0.0001:
		_camera.look_at(_cam_look, Vector3.UP)
	_camera.rotate_object_local(Vector3.FORWARD, randf_range(-1, 1) * 0.05 * sh)
	_camera.fov = _cam_fov


# =====================================================================
#  Autobús
# =====================================================================

func _bus_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(bus_world_yaw_deg))


func _bus_fwd() -> Vector3:
	return _bus_basis() * Vector3.RIGHT


## Dirección local del autobús convertida a mundo (RIGHT = frente, BACK = lado de puertas).
func _bus_dir(local_dir: Vector3) -> Vector3:
	return _bus_basis() * local_dir


func _bl(local_pos: Vector3) -> Vector3:
	return _bus_body.to_global(local_pos)


## Posición del pivote para que la puerta delantera quede frente al campus.
func _bus_stop() -> Vector3:
	return _street - _bus_basis() * Vector3(front_door_x, 0.0, 0.0)


func _door_world() -> Vector3:
	return _bl(Vector3(front_door_x, 0.0, bus_width * 0.5))


func _spawn_bus_model() -> Node3D:
	if ResourceLoader.exists(BUS_PATH):
		var packed := load(BUS_PATH) as PackedScene
		if packed:
			var inst := packed.instantiate() as Node3D
			if inst:
				return inst
	push_warning("Intro: no se encontró %s; se usa un autobús de cajas." % BUS_PATH)
	var bus := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(bus_length, 3.0, bus_width)
	body.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.25, 0.7)
	body.material_override = mat
	body.position.y = 1.85
	bus.add_child(body)
	return bus


func _find_bus_parts(model: Node3D) -> void:
	for n in model.find_children("Rueda_*", "Node3D", true, false):
		if n.name.count("_") == 1:
			_wheels.append(n)
	for pair in [["PuertaDel_A", "PuertaDel_B"], ["PuertaTra_A", "PuertaTra_B"]]:
		var a := model.find_child(pair[0], true, false) as Node3D
		var b := model.find_child(pair[1], true, false) as Node3D
		if a == null or b == null:
			continue
		var center := (a.position.x + b.position.x) * 0.5
		for leaf in [a, b]:
			var c: Vector3 = leaf.position
			var side := signf(c.x - center)
			_doors.append({"node": leaf, "closed": c, "open": c + Vector3(side * 0.56, 0.0, 0.12)})


func _add_bus_extras() -> void:
	# Piso interior con colisión, para que el protagonista camine dentro
	var body := StaticBody3D.new()
	_floor_body = body
	body.name = "PisoColision"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(bus_length - 0.3, 0.2, bus_width - 0.12)
	cs.shape = shape
	cs.position = Vector3(0.0, bus_floor_height - 0.1, 0.0)
	body.add_child(cs)
	_bus_body.add_child(body)
	# Que la lluvia (si usa colisión de partículas) no caiga dentro
	var rain_block := GPUParticlesCollisionBox3D.new()
	rain_block.size = Vector3(bus_length, 3.5, bus_width)
	rain_block.position.y = 1.75
	_bus_body.add_child(rain_block)
	if interior_lights:
		for x in [front_door_x - 1.0, -0.5, -4.0]:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.93, 0.82)
			l.light_energy = 1.4
			l.omni_range = 4.5
			l.position = Vector3(x, 3.0, 0.0)
			_bus_body.add_child(l)
	if headlights:
		for z in [-0.95, 0.95]:
			var s := SpotLight3D.new()
			s.light_color = Color(1.0, 0.95, 0.85)
			s.light_energy = 4.0
			s.spot_range = 28.0
			s.spot_angle = 28.0
			s.position = Vector3(bus_length * 0.5 + 0.1, 0.8, z)
			s.rotation = Vector3(deg_to_rad(-6.0), -PI * 0.5, 0.0)
			s.shadow_enabled = false
			_bus_body.add_child(s)


func _spin_wheels() -> void:
	if not is_instance_valid(_bus):
		return
	var p := _bus.global_position
	var d := (p - _bus_prev).dot(_bus_fwd())
	_bus_prev = p
	if absf(d) < 0.00001:
		return
	for w in _wheels:
		w.rotation.z -= d / wheel_radius


## Puertas de autobús: primero salen hacia fuera y luego se deslizan.
func _set_doors(open: bool, t := 0.8) -> void:
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
	_sound("puertas", _synth(0.9, 900.0, 300.0, 0.9, 0.45, 0.01, 1.5), _door_world(), -4.0)


# =====================================================================
#  Actores
# =====================================================================

func _place_player(local_pos: Vector3, face_dir: Vector3) -> void:
	_player.global_position = _bl(local_pos)
	_player.velocity = Vector3.ZERO
	_player.visible = true
	# La intro mueve el cuerpo y anima el esqueleto del jugador (su propio ciclo de caminar)
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_puppet = true
	_puppet_state = "idle"
	_puppet_speed = 0.0
	_face(face_dir, true)


## Orienta al jugador. El giro del cuerpo se suaviza en _physics_process.
func _face(dir: Vector3, instant := false) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	_puppet_yaw = atan2(-dir.x, -dir.z)
	if instant:
		_visual().rotation.y = _puppet_yaw
	if _player.has_method("cinematic_face"):
		_player.call("cinematic_face", dir)
	else:
		if "_face_dir" in _player:
			_player.set("_face_dir", dir)
		if "_yaw" in _player:
			_player.set("_yaw", _puppet_yaw)


func _visual() -> Node3D:
	if _player_vis == null or not is_instance_valid(_player_vis):
		_player_vis = _player.get_node_or_null("Visual") as Node3D
		if _player_vis == null:   # primer hijo que contenga el modelo
			for c in _player.get_children():
				if c is Node3D and not (c is CollisionShape3D) and not (c is Camera3D) \
						and not c.find_children("*", "MeshInstance3D", true, false).is_empty():
					_player_vis = c
					break
		if _player_vis == null:
			_player_vis = _player
	return _player_vis


## Anima al jugador mientras la intro lo controla.
func _physics_process(delta: float) -> void:
	if not _running or not _puppet or _player == null or not is_instance_valid(_player):
		return
	var vis := _visual()
	if _puppet_state == "walk" or _puppet_state == "idle":
		vis.rotation.y = lerp_angle(vis.rotation.y, _puppet_yaw, 1.0 - exp(-9.0 * delta))
	var rig: Variant = _player.get("rig")
	if rig is Object and is_instance_valid(rig) and (rig as Object).has_method("animate"):
		var st := {
			"speed": _puppet_speed,
			"run": false,
			"hold": String(_player.get("class_id")) != "ai",
			"dead": false,
			"stagger": _puppet_state == "fly",
			"shock": false,
			"grabbed": false,
		}
		(rig as Object).call("animate", delta, st)
	elif _puppet_state == "walk" or _puppet_state == "idle":
		# Sin esqueleto: balanceo y rebote de caminata en el modelo
		var k := clampf(_puppet_speed / 1.2, 0.0, 1.0)
		_bob_t += delta * (3.0 + _puppet_speed * 6.0)
		vis.position.y = lerpf(vis.position.y, absf(sin(_bob_t)) * 0.045 * k, 1.0 - exp(-12.0 * delta))
		vis.rotation.z = lerpf(vis.rotation.z, sin(_bob_t) * 0.04 * k, 1.0 - exp(-12.0 * delta))


## Camina hasta un punto (coordenadas locales del autobús) con arranque y frenado suaves.
## Devuelve true si se saltó la intro.
func _walk_to(local_target: Vector3, speed: float, timeout := 8.0) -> bool:
	var target := _bl(local_target)
	var elapsed := 0.0
	_puppet_state = "walk"
	while not _skipped:
		var pos := _player.global_position
		var to := target - pos
		to.y = 0.0
		var dist := to.length()
		if dist < 0.03 or elapsed > timeout:
			break
		var ease_in := clampf(elapsed / 0.5, 0.2, 1.0)
		var ease_out := clampf(dist / 0.7, 0.25, 1.0)
		_puppet_speed = speed * minf(ease_in, ease_out)
		_face(to)
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		elapsed += dt
		_player.global_position = pos + to / dist * minf(_puppet_speed * dt, dist)
	_puppet_speed = 0.0
	_puppet_state = "idle"
	return _skipped


## Empujón: la intro lanza al jugador fuera del autobús en arco y lo deja boca abajo (sin daño).
func _push_out() -> Tween:
	var out := _bus_dir(Vector3.BACK)
	_face(out, true)
	_puppet_state = "fly"
	_puppet_speed = 0.0
	var start := _player.global_position
	var land := start + out * 2.3
	land.y = _ground_y(land)
	var vis := _visual()
	var tw := _tw()
	tw.tween_method(func(k: float) -> void:
		var p := start.lerp(land, k)
		p.y = lerpf(start.y, land.y, k * k) + sin(k * PI) * 0.45
		_player.global_position = p, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_LINEAR)
	tw.parallel().tween_property(vis, "rotation:x", deg_to_rad(-88.0), 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(vis, "rotation:z", deg_to_rad(9.0), 0.5)
	tw.parallel().tween_property(vis, "position:y", 0.16, 0.5)
	tw.tween_callback(func() -> void: _puppet_state = "down")
	tw.tween_property(vis, "rotation:x", deg_to_rad(-78.0), 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(vis, "rotation:x", deg_to_rad(-88.0), 0.16) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	return tw


## Se incorpora: apoya una rodilla y se pone de pie, sin daño.
func _get_up(duration: float) -> Tween:
	var vis := _visual()
	var tw := _tw()
	tw.tween_property(vis, "rotation:x", deg_to_rad(-40.0), duration * 0.4) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(vis, "rotation:z", 0.0, duration * 0.4)
	tw.parallel().tween_property(vis, "position:y", 0.0, duration * 0.4)
	tw.tween_interval(duration * 0.2)
	tw.tween_property(vis, "rotation:x", 0.0, duration * 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _puppet_state = "idle")
	return tw


## Al levantarse vuelven la vida y la estamina (con un fundido suave).
func _release_hud() -> void:
	_hud_released = true
	for n in _hidden_ui:
		if not is_instance_valid(n):
			continue
		n.visible = true
		var kids: Array = [n] if n is Control else (n as Node).get_children().filter(func(c): return c is Control)
		for c in kids:
			var a: float = (c as Control).modulate.a
			(c as Control).modulate.a = 0.0
			create_tween().tween_property(c, "modulate:a", a, 0.7)
	_hidden_ui.clear()


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 6.0)
	var ex: Array[RID] = [_player.get_rid()]
	if _floor_body:
		ex.append(_floor_body.get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if hit else _street.y


# =====================================================================
#  Personas (chofer y pasajero): cuerpo articulado hecho con primitivas.
#  Miran hacia -Z. Pivotes: Torso, Cabeza, Hombro_I/D, Codo_I/D, Cadera_I/D, Rodilla_I/D
# =====================================================================

## look: shirt, pants, skin, shoes, sole (Color) · shirt_kind / pants_kind ("knit", "denim",
## "canvas") · wear ("gorra", "capucha", "") · hoodie, stubble, mustache, angry, rolled (bool) · print (String)
func _make_person(id: String, look: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = id
	var shirt: Color = look.get("shirt", Color(0.5, 0.5, 0.5))
	var pants: Color = look.get("pants", Color(0.1, 0.1, 0.15))
	var skin: Color = look.get("skin", Color(0.7, 0.5, 0.38))
	var hoodie: bool = look.get("hoodie", false)
	var m_shirt := _fabric(shirt, look.get("shirt_kind", "canvas"))
	var m_trim := _fabric(shirt.darkened(0.22), "rib")
	var m_pants := _fabric(pants, look.get("pants_kind", "canvas"))
	var m_skin := _mat(skin, 0.6)
	var m_face := _face_mat(skin, look.get("stubble", false), look.get("mustache", false), look.get("angry", false))
	var m_shoe := _fabric(look.get("shoes", Color(0.05, 0.05, 0.06)), "canvas")
	var m_sole := _mat(look.get("sole", Color(0.08, 0.08, 0.08)), 0.7)
	var m_dark := _mat(Color(0.03, 0.03, 0.03), 0.5)

	# Piernas
	for side in [-1.0, 1.0]:
		var s := "I" if side < 0 else "D"
		var hip := _pivot(root, "Cadera_" + s, Vector3(side * 0.1, 0.92, 0.0))
		_box(hip, Vector3(0.155, 0.47, 0.165), Vector3(0, -0.23, 0), m_pants)
		var knee := _pivot(hip, "Rodilla_" + s, Vector3(0, -0.46, 0))
		_box(knee, Vector3(0.135, 0.42, 0.145), Vector3(0, -0.2, 0), m_pants)
		if look.get("rolled", false):   # dobladillo del pantalón
			_box(knee, Vector3(0.148, 0.05, 0.158), Vector3(0, -0.355, 0), _fabric(pants.lightened(0.35), "denim"))
		_box(knee, Vector3(0.12, 0.07, 0.26), Vector3(0, -0.415, -0.045), m_shoe)
		_box(knee, Vector3(0.13, 0.025, 0.28), Vector3(0, -0.455, -0.05), m_sole)
		_box(knee, Vector3(0.06, 0.012, 0.1), Vector3(0, -0.378, -0.09), m_sole)   # agujetas

	# Torso
	var torso := _pivot(root, "Torso", Vector3(0, 0.92, 0))
	_box(torso, Vector3(0.36, 0.18, 0.2), Vector3(0, 0.05, 0), m_pants)
	_box(torso, Vector3(0.42, 0.5, 0.24), Vector3(0, 0.37, 0), m_shirt, true)
	_box(torso, Vector3(0.09, 0.08, 0.09), Vector3(0, 0.66, 0), m_skin)
	if hoodie:
		_box(torso, Vector3(0.43, 0.06, 0.25), Vector3(0, 0.15, 0), m_trim)            # resorte de la cintura
		_box(torso, Vector3(0.28, 0.14, 0.02), Vector3(0, 0.26, -0.122), m_trim)        # bolsa canguro
		var m_cord := _mat(Color(0.85, 0.83, 0.78), 0.6)
		for x in [-0.045, 0.045]:                                                       # cordones
			_box(torso, Vector3(0.012, 0.15, 0.012), Vector3(x, 0.52, -0.128), m_cord)
			_box(torso, Vector3(0.018, 0.03, 0.018), Vector3(x, 0.44, -0.128), m_dark)
		var txt: String = look.get("print", "")
		if txt != "":   # estampado en la espalda
			var l := Label3D.new()
			l.text = txt
			l.font_size = 56
			l.pixel_size = 0.0015
			l.outline_size = 0
			l.modulate = Color(0.88, 0.84, 0.74)
			l.shaded = true
			l.double_sided = false
			l.position = Vector3(0, 0.44, 0.123)
			torso.add_child(l)
	else:
		_box(torso, Vector3(0.37, 0.04, 0.21), Vector3(0, 0.13, 0), m_dark)               # cinturón
		_box(torso, Vector3(0.05, 0.035, 0.01), Vector3(0, 0.13, -0.107), _mat(Color(0.8, 0.65, 0.3), 0.3))
		_box(torso, Vector3(0.22, 0.04, 0.22), Vector3(0, 0.62, 0), m_shirt)             # cuello de camisa
		_box(torso, Vector3(0.08, 0.025, 0.01), Vector3(-0.1, 0.5, -0.12), _mat(Color(0.95, 0.95, 0.95), 0.5))   # gafete

	# Cabeza
	var head := _pivot(torso, "Cabeza", Vector3(0, 0.7, 0))
	_sphere(head, 0.115, Vector3(0, 0.11, 0), m_face)
	_box(head, Vector3(0.032, 0.04, 0.035), Vector3(0, 0.107, -0.114), m_skin)          # nariz
	for x in [-0.113, 0.113]:                                                           # orejas
		_sphere(head, 0.028, Vector3(x, 0.1, 0.005), m_skin)
	match String(look.get("wear", "")):
		"gorra":
			var m_cap := _fabric(pants, "canvas")
			_sphere(head, 0.122, Vector3(0, 0.15, 0.01), m_cap, true)
			_box(head, Vector3(0.2, 0.02, 0.12), Vector3(0, 0.15, -0.13), m_cap)
		"capucha":   # media esfera abierta al frente: enmarca la cara
			var m_hood := _fabric(shirt, look.get("shirt_kind", "knit")).duplicate() as StandardMaterial3D
			m_hood.cull_mode = BaseMaterial3D.CULL_DISABLED
			var hood := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.152
			sp.height = 0.304
			sp.is_hemisphere = true
			hood.mesh = sp
			hood.material_override = m_hood
			hood.rotation.x = PI * 0.5
			hood.position = Vector3(0, 0.12, -0.02)
			head.add_child(hood)
		_:
			_sphere(head, 0.12, Vector3(0, 0.14, 0.02), _mat(Color(0.08, 0.06, 0.05), 0.7), true)

	# Brazos
	for side in [-1.0, 1.0]:
		var s := "I" if side < 0 else "D"
		var sh := _pivot(torso, "Hombro_" + s, Vector3(side * 0.26, 0.58, 0))
		_box(sh, Vector3(0.115, 0.31, 0.125), Vector3(0, -0.15, 0), m_shirt)
		var el := _pivot(sh, "Codo_" + s, Vector3(0, -0.3, 0))
		_box(el, Vector3(0.105, 0.24, 0.105), Vector3(0, -0.12, 0), m_shirt)
		_box(el, Vector3(0.112, 0.045, 0.112), Vector3(0, -0.245, 0), m_trim)            # puño
		_sphere(el, 0.05, Vector3(0, -0.295, 0), m_skin)
	if look.get("armor", false):
		_add_armor(root)
		for l in torso.find_children("*", "Label3D", false, false):
			(l as Node3D).position.z = 0.145   # el estampado va pintado sobre el peto
	return root


## Armadura de pelea callejera: peto, hombreras, brazales, guanteletes, rodilleras,
## grebas, protector de boca y un tubo de metal a la espalda. Todo va en los pivotes,
## así que se mueve con las animaciones.
func _add_armor(root: Node3D) -> void:
	var steel := _metal_mat(Color(0.42, 0.43, 0.45), 0.25)
	var dark := _metal_mat(Color(0.2, 0.2, 0.22), 0.1)
	var leather := _fabric(Color(0.2, 0.11, 0.06), "leather")
	var torso := _part(root, "Torso")
	var head := _part(root, "Cabeza")

	# Peto (cubre pecho y espalda) con placa central y remaches
	var cuirass := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.232
	cap.height = 0.78
	cuirass.mesh = cap
	cuirass.material_override = steel
	cuirass.scale = Vector3(1.0, 0.88, 0.6)
	cuirass.position = Vector3(0, 0.38, 0)
	torso.add_child(cuirass)
	_box(torso, Vector3(0.05, 0.3, 0.02), Vector3(0, 0.42, -0.142), dark)
	for y in [0.32, 0.42, 0.52]:
		for x in [-0.12, 0.12]:
			_sphere(torso, 0.012, Vector3(x, y, -0.13), dark)
	# Gorjal
	var gorget := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.055
	tor.outer_radius = 0.095
	gorget.mesh = tor
	gorget.material_override = dark
	gorget.position = Vector3(0, 0.655, 0)
	torso.add_child(gorget)
	# Correas de cuero cruzadas y cinturón con hebilla y bolsas
	for sd: float in [-1.0, 1.0]:
		_box(torso, Vector3(0.05, 0.03, 0.3), Vector3(sd * 0.15, 0.64, 0), leather)
	_box(torso, Vector3(0.44, 0.06, 0.27), Vector3(0, 0.15, 0), leather)
	_box(torso, Vector3(0.07, 0.05, 0.02), Vector3(0, 0.15, -0.14), steel)
	for sd: float in [-1.0, 1.0]:
		_box(torso, Vector3(0.08, 0.09, 0.05), Vector3(sd * 0.17, 0.1, -0.1), leather)
	# Tubo de metal a la espalda, con cinta en el mango
	var pipe := Node3D.new()
	pipe.position = Vector3(0, 0.38, 0.17)
	pipe.rotation.z = deg_to_rad(38.0)
	torso.add_child(pipe)
	var rod := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.022
	cyl.bottom_radius = 0.022
	cyl.height = 0.85
	rod.mesh = cyl
	rod.material_override = _metal_mat(Color(0.5, 0.48, 0.45), 0.6)
	pipe.add_child(rod)
	var grip := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = 0.026
	gc.bottom_radius = 0.026
	gc.height = 0.22
	grip.mesh = gc
	grip.material_override = _fabric(Color(0.05, 0.05, 0.05), "rib")
	grip.position.y = 0.3
	pipe.add_child(grip)

	# Protector de boca (deja ver los ojos)
	_box(head, Vector3(0.17, 0.075, 0.05), Vector3(0, 0.055, -0.1), dark)
	for x in [-0.04, 0.0, 0.04]:
		_box(head, Vector3(0.012, 0.05, 0.01), Vector3(x, 0.055, -0.127), steel)

	for sd: float in [-1.0, 1.0]:
		var s := "I" if sd < 0 else "D"
		# Hombreras de dos placas
		var sh := _part(root, "Hombro_" + s)
		for k in 2:
			var pl := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.11 - k * 0.012
			sp.height = sp.radius * 2.0
			sp.is_hemisphere = true
			pl.mesh = sp
			pl.material_override = steel if k == 0 else dark
			pl.scale = Vector3(1.0, 0.75, 1.0)
			pl.position = Vector3(sd * 0.012, 0.0 - k * 0.07, 0)
			pl.rotation.z = -sd * deg_to_rad(15.0 + k * 10.0)
			sh.add_child(pl)
		# Codera, brazal y guantelete
		var el := _part(root, "Codo_" + s)
		_sphere(el, 0.06, Vector3(0, 0.0, 0.03), dark)
		_box(el, Vector3(0.13, 0.17, 0.13), Vector3(0, -0.14, 0), steel)
		_box(el, Vector3(0.135, 0.02, 0.135), Vector3(0, -0.07, 0), leather)
		_sphere(el, 0.058, Vector3(0, -0.295, 0), dark)
		# Escarcelas, rodilleras y grebas
		var hip := _part(root, "Cadera_" + s)
		_box(hip, Vector3(0.17, 0.17, 0.03), Vector3(0, -0.1, -0.095), steel)
		var knee := _part(root, "Rodilla_" + s)
		var kc := MeshInstance3D.new()
		var ks := SphereMesh.new()
		ks.radius = 0.075
		ks.height = 0.15
		ks.is_hemisphere = true
		kc.mesh = ks
		kc.material_override = steel
		kc.rotation.x = -PI * 0.5
		kc.position = Vector3(0, 0.0, -0.06)
		knee.add_child(kc)
		_box(knee, Vector3(0.155, 0.28, 0.165), Vector3(0, -0.2, -0.005), steel)
		_box(knee, Vector3(0.16, 0.025, 0.17), Vector3(0, -0.12, -0.005), leather)
		_box(knee, Vector3(0.16, 0.025, 0.17), Vector3(0, -0.28, -0.005), leather)


## Metal procedural: cepillado, rayones, abolladuras y algo de óxido.
func _metal_mat(base: Color, rust: float) -> StandardMaterial3D:
	var key := "metal%s%.2f" % [base.to_html(), rust]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var n := 128
	var noise := FastNoiseLite.new()
	noise.seed = hash(key)
	noise.frequency = 0.05
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var alb := Image.create(n, n, false, Image.FORMAT_RGB8)
	var bump := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rough := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var brush := noise.get_noise_2d(x * 0.15, y * 4.0) * 0.5 + 0.5
			var dent := noise.get_noise_2d(x + 200.0, y + 200.0) * 0.5 + 0.5
			var rv := noise.get_noise_2d(x * 1.5 + 700.0, y * 1.5) * 0.5 + 0.5
			var c := base * (0.85 + 0.3 * brush)
			var r := 0.35 + 0.15 * brush
			if rv > 1.0 - rust * 0.6:   # manchas de óxido
				var k := clampf((rv - (1.0 - rust * 0.6)) * 6.0, 0.0, 1.0)
				c = c.lerp(Color(0.42, 0.2, 0.08), k * 0.85)
				r = lerpf(r, 0.9, k)
			c.a = 1.0
			alb.set_pixel(x, y, c.clamp())
			bump.set_pixel(x, y, Color(dent, dent, dent))
			rough.set_pixel(x, y, Color(r, r, r))
	for i in 26:   # rayones
		var p := Vector2(rng.randf() * n, rng.randf() * n)
		var d := Vector2.from_angle(rng.randf() * TAU)
		var length := rng.randf_range(8.0, 30.0)
		for t in int(length):
			var q := p + d * t
			var xi := int(q.x) % n
			var yi := int(q.y) % n
			if xi < 0 or yi < 0:
				continue
			alb.set_pixel(xi, yi, (base * 1.6).clamp())
			bump.set_pixel(xi, yi, Color(0.2, 0.2, 0.2))
	alb.generate_mipmaps()
	rough.generate_mipmaps()
	bump.bump_map_to_normal_map(2.0)
	bump.generate_mipmaps(true)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(alb)
	m.metallic = 0.85
	m.roughness = 1.0
	m.roughness_texture = ImageTexture.create_from_image(rough)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(bump)
	m.normal_scale = 0.6
	m.uv1_scale = Vector3(2.0, 2.0, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_tex_cache[key] = m
	return m


func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## Tela procedural con relieve: "knit" (sudadera), "rib" (resortes), "denim", "canvas".
func _fabric(base: Color, kind: String) -> StandardMaterial3D:
	var key := kind + base.to_html()
	if _tex_cache.has(key):
		return _tex_cache[key]
	var n := 128
	var noise := FastNoiseLite.new()
	noise.seed = hash(key)
	noise.frequency = 0.09
	var alb := Image.create(n, n, false, Image.FORMAT_RGB8)
	var bump := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var nv := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var h := nv
			var c := base
			match kind:
				"knit":
					var rib := 0.5 + 0.5 * sin(float(x) * TAU / 4.0)
					var loop := 0.5 + 0.5 * sin(float(y) * TAU / 5.0 + (PI * 0.5 if int(x / 2.0) % 2 == 0 else 0.0))
					h = rib * 0.45 + loop * 0.3 + nv * 0.25
					var pill := noise.get_noise_2d(x * 3.0 + 500.0, y * 3.0) * 0.5 + 0.5   # motitas
					c = base * (0.78 + 0.4 * h) * (1.0 + (0.12 if pill > 0.82 else 0.0))
				"rib":
					h = (0.5 + 0.5 * sin(float(x) * TAU / 3.0)) * 0.8 + nv * 0.2
					c = base * (0.75 + 0.4 * h)
				"denim":
					var tw := 1.0 if (x + y) % 5 < 3 else 0.0
					h = tw * 0.6 + nv * 0.4
					var wash := noise.get_noise_2d(x * 0.2 + 300.0, y * 0.2) * 0.5 + 0.5
					c = base.lerp(Color(0.72, 0.78, 0.86), (1.0 - tw) * 0.3 + wash * 0.18) * (0.85 + 0.25 * h)
				"leather":
					var grain := noise.get_noise_2d(x * 2.5, y * 2.5) * 0.5 + 0.5
					h = nv * 0.4 + grain * 0.6
					c = base * (0.8 + 0.35 * h)
				"canvas":
					var wv := (0.5 + 0.5 * sin(float(x) * TAU / 3.0)) * (0.5 + 0.5 * sin(float(y) * TAU / 3.0))
					h = wv * 0.5 + nv * 0.5
					c = base * (0.86 + 0.24 * h)
				_:
					c = base * (0.85 + 0.3 * nv)
			c.a = 1.0
			alb.set_pixel(x, y, c.clamp())
			bump.set_pixel(x, y, Color(h, h, h))
	alb.generate_mipmaps()
	bump.bump_map_to_normal_map(3.0)
	bump.generate_mipmaps(true)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(alb)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(bump)
	m.normal_scale = 0.8
	m.roughness = 0.92
	m.uv1_scale = Vector3(4.0, 4.0, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_tex_cache[key] = m
	return m


## Cara pintada sobre la esfera de la cabeza (la frente queda en u = 0.5).
func _face_mat(skin: Color, stubble: bool, mustache: bool, angry: bool) -> StandardMaterial3D:
	var key := "cara%s%s%s%s" % [skin.to_html(), stubble, mustache, angry]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var w := 256
	var h := 128
	var cx := 128
	var noise := FastNoiseLite.new()
	noise.seed = hash(key)
	noise.frequency = 0.06
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var hair := Color(0.07, 0.05, 0.04)
	for y in h:
		for x in w:
			var c := skin * (0.95 + 0.1 * noise.get_noise_2d(x, y))
			var dxc := float(x - cx)
			# mejillas un poco más rojas
			for sd: float in [-1.0, 1.0]:
				var d := Vector2(dxc - sd * 17.0, y - 70.0).length()
				if d < 9.0:
					c = c.lerp(Color(0.75, 0.35, 0.3), 0.08 * (1.0 - d / 9.0))
			# barba de varios días
			if stubble and y > 66 and y < 92:
				var e := pow(dxc / 25.0, 2.0) + pow((y - 74.0) / 18.0, 2.0)
				if e < 1.0 and y > 64 + absf(dxc) * 0.15 and rng.randf() < 0.5:
					c = c.darkened(0.3)
			c.a = 1.0
			img.set_pixel(x, y, c.clamp())
	var lid := skin.darkened(0.45)
	for sd: int in [-1, 1]:
		var ex := cx + sd * 11
		var ey := 60
		for dy in range(-3, 4):
			for dx in range(-6, 7):
				var e := pow(dx / 6.0, 2.0) + pow(dy / 2.7, 2.0)
				if e <= 1.0:
					var d := Vector2(dx, dy).length()
					var col := Color(0.92, 0.9, 0.86)
					if d < 2.4:
						col = Color(0.25, 0.15, 0.08)
					if d < 1.2:
						col = Color(0.02, 0.02, 0.02)
					img.set_pixel(ex + dx, ey + dy, col)
		for dx in range(-6, 7):   # párpado
			img.set_pixel(ex + dx, ey - 3, lid)
		for dx in range(-7, 8):   # cejas (fruncidas si está enojado)
			var inner := 1.0 - clampf(absf(float(ex + dx - cx) - 4.0) / 14.0, 0.0, 1.0)
			var by := ey - 7 + (int(round(inner * 2.5)) if angry else 0)
			img.set_pixel(ex + dx, by, hair)
			img.set_pixel(ex + dx, by + 1, hair)
	for dx in range(-2, 3):       # sombra bajo la nariz
		img.set_pixel(cx + dx, 69, skin.darkened(0.25))
	var lip := skin.lerp(Color(0.5, 0.18, 0.16), 0.45)
	for dx in range(-7, 8):       # boca (comisuras abajo si está enojado)
		var my := 77 + (1 if angry and absf(dx) > 4 else 0)
		img.set_pixel(cx + dx, my, lip.darkened(0.35))
		img.set_pixel(cx + dx, my + 1, lip)
	if mustache:
		for y in range(72, 75):
			for dx in range(-9, 10):
				if absf(dx) < 9 - (y - 72):
					img.set_pixel(cx + dx, y, hair)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.55
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tex_cache[key] = m
	return m


func _pivot(parent: Node3D, id: String, pos: Vector3) -> Node3D:
	var nd := Node3D.new()
	nd.name = id
	nd.position = pos
	parent.add_child(nd)
	return nd


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rounded := false) -> void:
	var mi := MeshInstance3D.new()
	if rounded:   # torso redondeado
		var c := CapsuleMesh.new()
		c.radius = size.x * 0.5
		c.height = size.y + size.x * 0.5
		mi.mesh = c
		mi.scale = Vector3(1.0, 1.0, size.z / size.x)
	else:
		var b := BoxMesh.new()
		b.size = size
		mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


func _sphere(parent: Node3D, r: float, pos: Vector3, m: Material, half := false) -> void:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = r * 2.0
	sp.is_hemisphere = half
	mi.mesh = sp
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


func _part(person: Node3D, id: String) -> Node3D:
	return person.find_child(id, true, false) as Node3D


func _npc_face(person: Node3D, local_dir: Vector3) -> void:
	person.rotation.y = atan2(-local_dir.x, -local_dir.z)


func _turn_head(person: Node3D, yaw: float, t: float) -> void:
	if person == null:
		return
	_tw().tween_property(_part(person, "Cabeza"), "rotation:y", yaw, t)


func _pose_seated(person: Node3D) -> void:
	for s in ["I", "D"]:
		_part(person, "Cadera_" + s).rotation.x = PI * 0.5
		_part(person, "Rodilla_" + s).rotation.x = -PI * 0.5
	_part(person, "Torso").rotation.x = 0.08


func _rest_pose(person: Node3D) -> void:
	_walkers.erase(person)
	for id in ["Torso", "Hombro_I", "Hombro_D", "Codo_I", "Codo_D", "Cadera_I", "Cadera_D", "Rodilla_I", "Rodilla_D"]:
		_part(person, id).rotation = Vector3.ZERO
	_part(person, "Torso").position.y = 0.92


## IK de dos huesos para llevar una mano a un punto (en el plano frontal del brazo).
func _reach(person: Node3D, side: float, target: Vector3) -> void:
	var s := "I" if side < 0 else "D"
	var sh := _part(person, "Hombro_" + s)
	var el := _part(person, "Codo_" + s)
	var t := (sh.get_parent() as Node3D).to_local(target) - sh.position
	var fwd := -t.z
	var down := -t.y
	var a := 0.3
	var b := 0.29
	var d := clampf(Vector2(fwd, down).length(), absf(a - b) + 0.01, a + b - 0.01)
	var phi := atan2(fwd, down)
	var alpha := acos(clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0))
	var th1 := phi - alpha
	var psi := atan2(fwd - a * sin(th1), down - a * cos(th1))
	sh.rotation.x = th1
	el.rotation.x = psi - th1


## Hace caminar a un NPC por puntos (coordenadas locales del autobús).
func _npc_walk(person: Node3D, points: Array, speed: float, delay := 0.0) -> Tween:
	var tw := _tw()
	tw.set_trans(Tween.TRANS_LINEAR)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(func() -> void: _walkers[person] = 0.0)
	var prev: Vector3 = person.position
	for p in points:
		var target: Vector3 = p
		var dir := target - prev
		dir.y = 0.0
		tw.tween_callback(func() -> void: _npc_face(person, dir))
		tw.tween_property(person, "position", target, dir.length() / speed)
		prev = target
	tw.tween_callback(func() -> void: _rest_pose(person))
	return tw


func _animate_walkers(delta: float) -> void:
	for person in _walkers.keys():
		if not is_instance_valid(person):
			_walkers.erase(person)
			continue
		var ph: float = _walkers[person] + delta * 8.0
		_walkers[person] = ph
		var sw := sin(ph)
		_part(person, "Cadera_I").rotation.x = sw * 0.45
		_part(person, "Cadera_D").rotation.x = -sw * 0.45
		_part(person, "Rodilla_I").rotation.x = -maxf(0.0, -sw) * 0.7
		_part(person, "Rodilla_D").rotation.x = -maxf(0.0, sw) * 0.7
		_part(person, "Hombro_I").rotation.x = -sw * 0.35
		_part(person, "Hombro_D").rotation.x = sw * 0.35
		_part(person, "Torso").position.y = 0.92 + absf(cos(ph)) * 0.025


# =====================================================================
#  HUD oculto y pelea congelada mientras dura la intro
# =====================================================================

func _on_node_added(n: Node) -> void:
	if _running:
		_suppress_node.call_deferred(n)


func _sweep(full: bool) -> void:
	var nodes: Array = []
	if full:
		nodes = get_tree().root.find_children("*", "", true, false)
	else:
		nodes = get_tree().root.find_children("*", "CanvasLayer", true, false)
		for g in pause_groups:
			nodes.append_array(get_tree().get_nodes_in_group(g))
	for n in nodes:
		_suppress_node(n)


func _find_boss_fight() -> Node:
	for n in get_tree().root.find_children("*", "", true, false):
		if n.has_method("set_cinematic") and n.has_method("start_fight"):
			return n
	return null


func _suppress_node(n: Node) -> void:
	if not _running or not is_instance_valid(n) or not n.is_inside_tree():
		return
	if n == self or is_ancestor_of(n) or n.is_ancestor_of(self):
		return
	if _bf and (n == _bf or _bf.is_ancestor_of(n)):
		return   # BossFight oculta y muestra su propio HUD
	if (n is CanvasLayer or n is Control) and not n.find_children("*", "SubViewport", true, false).is_empty():
		return   # capas que dibujan el mundo (no son HUD)
	if hide_hud and not _hud_released and not _hidden_ui.has(n):
		if n is CanvasLayer and (n as CanvasLayer).visible:
			_hidden_ui[n] = true
			(n as CanvasLayer).visible = false
		elif n is Control and (n as Control).visible:
			var p := n.get_parent()
			if not (p is CanvasItem or p is CanvasLayer):
				_hidden_ui[n] = true
				(n as Control).visible = false
	if _player and (n == _player or _player.is_ancestor_of(n)):
		return
	if not _paused.has(n) and _should_pause(n):
		_paused[n] = n.process_mode
		n.process_mode = Node.PROCESS_MODE_DISABLED


func _should_pause(n: Node) -> bool:
	if _bf:
		return false   # el jefe duerme hasta start_fight(); no hace falta congelar nada
	for g in pause_groups:
		if n.is_in_group(g):
			return true
	var scr := n.get_script() as Script
	if scr:
		for hint in pause_script_hints:
			if hint != "" and scr.resource_path.contains(hint):
				return true
	for path in pause_nodes:
		if get_node_or_null(path) == n:
			return true
	return false


func _resume_ui() -> void:
	_hud_released = true
	for n in _hidden_ui:
		if is_instance_valid(n):
			n.visible = true
	_hidden_ui.clear()


func _resume_fight() -> void:
	for n in _paused:
		if is_instance_valid(n):
			n.process_mode = _paused[n]
	_paused.clear()


# =====================================================================
#  Entrada a la arena: el muro invisible se abre en la puerta del campus
# =====================================================================

## Abre el tramo de la puerta. Devuelve true si el jugador quedó afuera y hay que vigilar
## su entrada (la pelea sigue congelada hasta entonces).
func _open_arena() -> bool:
	if not open_arena_gate:
		return false
	_arena = get_tree().root.find_child("ArenaBounds", true, false) as StaticBody3D
	if _arena == null:
		return false
	var gate := deg_to_rad(arena_gate_angle_deg)
	var half := deg_to_rad(arena_gate_half_angle_deg)
	_gate_shapes.clear()
	for c in _arena.get_children():
		var cs := c as CollisionShape3D
		if cs == null:
			continue
		var flat := Vector2(cs.position.x, cs.position.z)
		_arena_r = maxf(_arena_r, flat.length())
		if absf(angle_difference(atan2(cs.position.x, cs.position.z), gate)) < half:
			cs.set_deferred("disabled", true)
			_gate_shapes.append(cs)
	if _player_inside_arena():
		_close_arena()
		return false
	_watching_arena = true
	return hold_fight_until_inside


func _player_inside_arena() -> bool:
	if _arena == null or _player == null or not is_instance_valid(_player):
		return true
	var l := _arena.to_local(_player.global_position)
	return Vector2(l.x, l.z).length() < _arena_r - 2.5


func _watch_arena() -> void:
	if not is_instance_valid(_arena) or _player_inside_arena():
		_watching_arena = false
		_close_arena()
		_resume_fight()


func _close_arena() -> void:
	for cs in _gate_shapes:
		if is_instance_valid(cs):
			cs.set_deferred("disabled", false)
	_gate_shapes.clear()


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
	_tw().tween_property(_fade, "color:a", alpha, t)


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

## Llama a un método del jugador solo si existe (si falta, avisa una vez y sigue).
func _pcall(method: String, args: Array = []) -> void:
	if _player.has_method(method):
		_player.callv(method, args)
	elif not _warned.has(method):
		_warned[method] = true
		push_warning("Intro: %s no tiene '%s()'. Revisa los cambios de test_player.gd." % [PLAYER_SCRIPT_PATH, method])


func _player_cam() -> Camera3D:
	return _player.get("camera") as Camera3D


func _tw() -> Tween:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tweens.append(tw)
	return tw


## Espera a que termine un tween. Devuelve true si se saltó la intro.
func _wait_tween(tw: Tween) -> bool:
	while tw and tw.is_valid() and tw.is_running() and not _skipped:
		await get_tree().process_frame
	return _skipped


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
