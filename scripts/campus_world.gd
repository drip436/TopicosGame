@tool
extends "res://scripts/arena_generator.gd"
## Genera el resto del campus universitario alrededor de la plaza del primer jefe:
## avenida, caminos, residencias, estadio, estacionamiento, jardín, cafetería,
## torre de agua y las arenas de los siguientes jefes:
##   - Biblioteca Central (oeste)
##   - Centro de Cómputo (este)
##   - Laboratorio de Biogenética, con criaturas en cápsulas (noreste)
##   - Aula Magna y Torre del Reloj, arena del jefe final (norte, sellada)
##
## Reutiliza los materiales y ayudantes de arena_generator.gd. Igual que la arena,
## funciona en el editor (@tool); cambia `seed_value` o marca `rebuild_now`.
##
## En juego:
##   - El campus está dividido en sectores cerrados por barricadas; solo se pasa
##     de uno a otro por dentro de edificios de aulas, sellados con niebla hasta
##     vencer al jefe anterior (ver "sectores y edificios de conexión" abajo).
##   - Al derrotar al primer jefe se abre una puerta al oeste de la plaza (Edificio
##     de Aulas Poniente), la lluvia amaina y aparecen los nombres de las zonas.
##   - `get_arena(id)` devuelve centro, entrada, ancho de entrada y punto de
##     aparición del jefe de cada arena ("biblioteca", "computo",
##     "laboratorio", "final") para configurar sus peleas.
##   - Llama `register_boss_defeated(id)` al vencer a cada jefe: disipa el sello
##     del siguiente edificio. Cada jefe suelta una pieza de la llave; al recoger
##     las 4 (`add_key_piece`) se abre el portón del Aula Magna.

signal final_gate_opened

const LIB := Vector3(-220, 0, -85)
## Pizarrones de la Biblioteca (posición local respecto a LIB, giro en grados).
## Los usa el segundo jefe para escribir fórmulas de las que salen flechas.
const LIB_BOARDS := [
	[Vector3(-8, 0, -19.3), 0.0],
	[Vector3(8, 0, -19.3), 0.0],
	[Vector3(-19.5, 0, -3), 90.0],
	[Vector3(19.5, 0, -3), -90.0],
]
const COMP := Vector3(225, 0, -85)
const LAB := Vector3(170, 0, -280)
const FINAL := Vector3(0, 0, -325)
const AVENUE_Z := 38.0
## Límites del campus (x mínimo, z mínimo, ancho, largo).
const BOUNDS := Rect2(-300, -420, 600, 512)

const ZONES := [
	[Vector2(-220, -70), 42.0, "Biblioteca Central"],
	[Vector2(225, -70), 42.0, "Centro de Cómputo"],
	[Vector2(170, -270), 44.0, "Laboratorio de Biogenética"],
	[Vector2(0, -325), 58.0, "Aula Magna"],
	[Vector2(0, -200), 30.0, "Explanada de los Fundadores"],
	[Vector2(-80, -150), 42.0, "Estadio Universitario"],
	[Vector2(80, -150), 38.0, "Estacionamiento Norte"],
	[Vector2(0, -140), 30.0, "Jardín de los Fundadores"],
	[Vector2(-122, -98), 18.0, "Cafetería"],
	[Vector2(125, -5), 18.0, "Torre de Agua"],
	[Vector2(-210, 72), 60.0, "Residencias Estudiantiles"],
	[Vector2(210, 72), 60.0, "Residencias Estudiantiles"],
]

## (Ya no se usa: el portón se abre con las 4 piezas de la llave.)
@export var bosses_for_final_gate: PackedStringArray = PackedStringArray(["biblioteca", "computo", "laboratorio"])
## Desmárcalo para probar la arena final con el portón abierto.
@export var final_gate_locked: bool = true
@export var show_area_titles: bool = true
## Avisa en el panel Output cuando un prefab tapa un edificio de conexión o cruza
## una barricada entre sectores (revisa que el recorrido siga funcionando).
@export var warn_prefab_conflicts: bool = true
## Crea la pelea del segundo jefe en la Biblioteca (boss_bibliotecario/LibraryFight.tscn).
@export var spawn_library_boss: bool = true
## Crea la pelea del tercer jefe (Centro de Cómputo) al jugar.
@export var spawn_compute_boss: bool = true
## Crea la pelea del cuarto jefe (Laboratorio) al jugar.
@export var spawn_lab_boss: bool = true
## Crea el enfrentamiento final (Aula Magna) al jugar.
@export var spawn_final_boss: bool = true
## Crea VidaDelCampus al jugar: enemigos, hogueras, tazas de café y la ameba del lago.
@export var spawn_world_life: bool = true
## Para pruebas: desbloquea todo al iniciar (plaza, sellos y portón final).
@export var open_world_on_start: bool = false

var w_body: StaticBody3D
var w_zone: Node3D
var _mmc := {}
var _units := {}
var _paths: Array = []
var _blocked: Array = []

var m_path: ShaderMaterial
var m_marble: ShaderMaterial
var m_raised: ShaderMaterial
var m_labtile: ShaderMaterial
var m_stoneslab: ShaderMaterial
var m_asphalt: ShaderMaterial
var m_white_lab: ShaderMaterial
var m_stone_light: ShaderMaterial
var m_led: ShaderMaterial
var m_beacon: ShaderMaterial
var m_fluid: ShaderMaterial
var m_fluid_amber: ShaderMaterial
var m_wood_dark: StandardMaterial3D
var m_book: StandardMaterial3D
var m_paper: StandardMaterial3D
var m_metal: StandardMaterial3D
var m_metal_light: StandardMaterial3D
var m_rack: StandardMaterial3D
var m_screen: StandardMaterial3D
var m_cyan: StandardMaterial3D
var m_holo: StandardMaterial3D
var m_panel_light: StandardMaterial3D
var m_flesh: StandardMaterial3D
var m_flesh_dark: StandardMaterial3D
var m_eye: StandardMaterial3D
var m_glass_clear: StandardMaterial3D
var m_spill: StandardMaterial3D
var m_bubble: StandardMaterial3D
var m_hazard_y: StandardMaterial3D
var m_hazard_k: StandardMaterial3D
var m_gold: StandardMaterial3D
var m_clock: StandardMaterial3D
var m_seal: StandardMaterial3D
var m_line: StandardMaterial3D
var m_sandbag: StandardMaterial3D
var m_hedge: StandardMaterial3D
var m_canvas: StandardMaterial3D
var m_flood: StandardMaterial3D
var m_stained: Array[StandardMaterial3D] = []
var m_water: ShaderMaterial
var m_fwater: ShaderMaterial
var m_brick: ShaderMaterial
var m_plaster: ShaderMaterial
var m_chalk: StandardMaterial3D
var m_desk: StandardMaterial3D
var m_jet: StandardMaterial3D
var m_route := {}
var mesh_panel_red: BoxMesh
var _extra_zones: Array = []
var _blocked_rects: Array = []

var _gate_pivots: Array[Node3D] = []
var _gate_body: StaticBody3D
var _gate_seal: Node3D
var _gate_open := false
var _defeated := {}
## Piezas de la llave del Aula Magna recogidas (las sueltan los jefes).
var key_pieces := {}
const KEY_PIECES_NEEDED := 4
var _explore := false
var _zone := ""
var _zone_t := 0.0
var _zone_seen := {}
var _title_layer: CanvasLayer
var _title_label: Label
var _title_line: ColorRect
var _title_tw: Tween
var _rebuild_timer: Timer
var _built_at := -100000
var _zone_parent: Node3D
var _prefab_local := false


func _enter_tree() -> void:
	add_to_group("campus_world")


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild_timer = Timer.new()
		_rebuild_timer.one_shot = true
		_rebuild_timer.wait_time = 0.4
		_rebuild_timer.timeout.connect(_build)
		add_child(_rebuild_timer)
	_build()
	if not Engine.is_editor_hint():
		_runtime_setup.call_deferred()


## Lo llaman los prefabs al moverse o cambiar: regenera el campus en el editor
## cuando dejas de arrastrar.
func request_rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _rebuild_timer == null or not _rebuild_timer.is_inside_tree():
		return
	if Time.get_ticks_msec() - _built_at < 600:
		return
	_rebuild_timer.start()


func _build() -> void:
	if _root and is_instance_valid(_root):
		_root.free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	_zone_parent = null
	for pf in _find_prefabs():
		var old := (pf as Node).get_node_or_null("Generated")
		if old and old.owner == null:
			old.free()
	_mm.clear()
	_mmc.clear()
	_units.clear()
	_paths.clear()
	_blocked.clear()
	_gate_pivots.clear()
	_extra_zones.clear()
	_tree_pts.clear()
	_blocked_rects.clear()
	_gate_open = false
	rng.seed = seed_value * 31 + 7
	_make_materials()
	_make_world_materials()
	_make_district_materials()
	_make_recreation_materials()
	_make_decor_materials()
	w_body = StaticBody3D.new()
	w_body.name = "WorldCollision"
	_root.add_child(w_body)
	_reserve_hub()
	_make_paths()
	_make_connector_materials()
	_make_connectors()
	_reserve_sector_walls()
	_make_prefabs()
	_make_perimeter()
	_make_library()
	_make_computing()
	_make_lab()
	_make_final_arena()
	_make_explanade()
	_make_stadium()
	_make_parking()
	_make_garden()
	_make_cafeteria()
	_make_water_tower()
	_make_avenue()
	_make_routes()
	_make_wrecks()
	_make_signs()
	_make_sector_walls()
	_make_alamedas()
	_make_nature()
	_make_filler()
	_make_wild_grass()
	_make_world_fx()
	_make_markers()
	# Todas las luces se desvanecen a distancia (rendimiento).
	var lights := _root.find_children("*", "OmniLight3D", true, false)
	for pf in _find_prefabs():
		var g := (pf as Node).get_node_or_null("Generated")
		if g:
			lights.append_array(g.find_children("*", "OmniLight3D", true, false))
	for l in lights:
		var ol := l as OmniLight3D
		if not ol.distance_fade_enabled:
			ol.distance_fade_enabled = true
			ol.distance_fade_begin = 100.0
			ol.distance_fade_length = 30.0
	_built_at = Time.get_ticks_msec()


# ================================================================ API pública

## Datos de cada arena para configurar la pelea de su jefe.
func get_arena(id: String) -> Dictionary:
	match id:
		"biblioteca":
			return {"name": "Biblioteca Central", "center": LIB + Vector3(0, 0, 2), "boss_spawn": LIB + Vector3(0, 0, -12),
				"entrance": LIB + Vector3(0, 0, 23), "entrance_width": 10.0, "radius": 15.0}
		"computo":
			return {"name": "Centro de Cómputo", "center": COMP + Vector3(0, 0, 3), "boss_spawn": COMP + Vector3(0, 0, -8),
				"entrance": COMP + Vector3(0, 0, 22.2), "entrance_width": 8.0, "radius": 15.0}
		"laboratorio":
			return {"name": "Laboratorio de Biogenética", "center": LAB + Vector3(0, 0, 2), "boss_spawn": LAB + Vector3(0, 0, -15),
				"entrance": LAB + Vector3(0, 0, 26.6), "entrance_width": 9.0, "radius": 17.0}
		"final":
			return {"name": "Aula Magna", "center": FINAL, "boss_spawn": FINAL + Vector3(0, 0, -20),
				"entrance": FINAL + Vector3(0, 0, 47.0), "entrance_width": 13.0, "radius": 31.0}
	return {}


## Edificios de conexión: id, título, origen, base (giro) y largo. El pasillo
## interior corre por z local = 2.5 (de -largo/2 a +largo/2 en x local).
func get_connector_halls() -> Array:
	return _hall_data


## Lagos del campus (prefabs "Lago"): nodo y radios de la elipse.
func get_lakes() -> Array:
	var out: Array = []
	for pf in _find_prefabs():
		if PREFAB.Kind.keys()[pf.kind] == "LAGO":
			out.append({"node": pf, "radii": pf.lake_radii})
	return out


## Prefabs del campus de un tipo ("FUENTE", "FACULTAD", "ZONA_RECREATIVA"...).
func get_prefabs_of_kind(kind_name: String) -> Array:
	var out: Array = []
	for pf in _find_prefabs():
		if PREFAB.Kind.keys()[pf.kind] == kind_name:
			out.append(pf)
	return out


## Avísale al campus que un jefe fue derrotado (abre el siguiente edificio).
## El portón del Aula Magna ya no se abre aquí: hacen falta las piezas de la llave.
func register_boss_defeated(id: String) -> void:
	_defeated[id] = true
	if SEAL_FOR_BOSS.has(id):
		unseal(SEAL_FOR_BOSS[id])


## Se recogió una pieza de la llave (amuleto). Con las 4 se abre el Aula Magna.
## Devuelve cuántas piezas se tienen.
func add_key_piece(id: String) -> int:
	key_pieces[id] = true
	if key_pieces.size() >= KEY_PIECES_NEEDED:
		open_final_gate()
	return key_pieces.size()


## Abre el portón sellado del Aula Magna.
func open_final_gate(instant: bool = false) -> void:
	if _gate_open:
		return
	_gate_open = true
	if _gate_body and is_instance_valid(_gate_body):
		_gate_body.queue_free()
	if _gate_pivots.size() < 2:
		return
	if instant or not is_inside_tree():
		_gate_pivots[0].rotation.y = deg_to_rad(90)
		_gate_pivots[1].rotation.y = deg_to_rad(-90)
		if _gate_seal:
			_gate_seal.visible = false
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_gate_pivots[0], "rotation:y", deg_to_rad(90), 5.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_gate_pivots[1], "rotation:y", deg_to_rad(-90), 5.0).set_trans(Tween.TRANS_SINE)
	if _gate_seal:
		tw.tween_property(_gate_seal, "scale", Vector3.ONE * 0.01, 1.5)
		tw.chain().tween_callback(func(): _gate_seal.visible = false)
	final_gate_opened.emit()
	_show_title("El sello del Aula Magna se ha roto")


# ================================================================ juego

func _runtime_setup() -> void:
	_build_title_ui()
	if spawn_library_boss and get_tree().current_scene and get_tree().current_scene.find_child("LibraryFight", true, false) == null:
		var lf_scene: PackedScene = load("res://boss_bibliotecario/LibraryFight.tscn")
		if lf_scene:
			var lf := lf_scene.instantiate()
			lf.name = "LibraryFight"
			lf.set("world", self)
			get_tree().current_scene.add_child(lf)
	if spawn_compute_boss and get_tree().current_scene and get_tree().current_scene.find_child("ComputeFight", true, false) == null:
		var cf_scene: PackedScene = load("res://boss_computo/ComputeFight.tscn")
		if cf_scene:
			var cf := cf_scene.instantiate()
			cf.name = "ComputeFight"
			cf.set("world", self)
			get_tree().current_scene.add_child(cf)
	if spawn_lab_boss and get_tree().current_scene and get_tree().current_scene.find_child("LabFight", true, false) == null:
		var lab_scene: PackedScene = load("res://boss_laboratorio/LabFight.tscn")
		if lab_scene:
			var lab := lab_scene.instantiate()
			lab.name = "LabFight"
			lab.set("world", self)
			get_tree().current_scene.add_child(lab)
	if spawn_final_boss and get_tree().current_scene and get_tree().current_scene.find_child("FinalFight", true, false) == null:
		var ff_scene: PackedScene = load("res://boss_final/FinalFight.tscn")
		if ff_scene:
			var ff := ff_scene.instantiate()
			ff.name = "FinalFight"
			ff.set("world", self)
			get_tree().current_scene.add_child(ff)
	if spawn_world_life and get_tree().current_scene and get_tree().current_scene.find_child("VidaDelCampus", true, false) == null:
		var wl_scene: PackedScene = load("res://mundo/VidaDelCampus.tscn")
		if wl_scene:
			var wl := wl_scene.instantiate()
			wl.name = "VidaDelCampus"
			wl.set("world", self)
			get_tree().current_scene.add_child.call_deferred(wl)
	if not final_gate_locked:
		open_final_gate(true)
	var bf: Node = null
	if get_parent():
		bf = get_parent().get_node_or_null("BossFight")
	if bf == null and get_tree().current_scene:
		bf = get_tree().current_scene.find_child("BossFight", true, false)
	if bf and bf.has_signal("boss_defeated") and not open_world_on_start:
		bf.connect("boss_defeated", _on_first_boss_defeated.bind(bf))
	else:
		_open_world()


func _on_first_boss_defeated(bf: Node) -> void:
	_explore = true
	_open_plaza_west()
	_calm_puddles()
	_show_title(SEAL_TITLES["aulas_poniente"])
	var hud = bf.get("hud")
	if hud and hud.has_method("show_hint"):
		hud.show_hint("La tormenta amaina. Se abrió una puerta al oeste de la plaza:\nel Edificio de Aulas Poniente lleva a la Biblioteca Central.", 10.0)


## Para pruebas: abre la plaza, todos los sellos y el portón final.
func _open_world() -> void:
	_explore = true
	_open_plaza_west()
	_calm_puddles()
	for id in _seals.keys():
		unseal(id, false)
	open_final_gate(true)


## Abre el muro invisible de la plaza justo frente al Edificio de Aulas Poniente.
func _open_plaza_west() -> void:
	if _ring_opened:
		return
	_ring_opened = true
	var bounds: Node = null
	if get_parent():
		bounds = get_parent().find_child("ArenaBounds", true, false)
	if bounds:
		for c in bounds.get_children():
			if c is CollisionShape3D:
				var cp: Vector3 = (c as CollisionShape3D).position
				if absf(wrapf(atan2(cp.x, cp.z) + PI * 0.5, -PI, PI)) < 0.08:
					(c as CollisionShape3D).set_deferred("disabled", true)


## Las ondas de lluvia en los charcos casi desaparecen.
func _calm_puddles() -> void:
	var mats: Array = [m_path, m_marble, m_raised, m_labtile, m_stoneslab, m_asphalt, m_water, m_fwater]
	if get_parent() and get_parent().get("m_ground") is ShaderMaterial:
		mats.append(get_parent().get("m_ground"))
	for m in mats:
		if m is ShaderMaterial:
			var sm: ShaderMaterial = m
			var tw := create_tween()
			tw.tween_method(func(v: float): sm.set_shader_parameter("rain_intensity", v), 1.0, 0.05, 14.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _explore or not show_area_titles:
		return
	_zone_t -= delta
	if _zone_t > 0.0:
		return
	_zone_t = 0.4
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty() or not (players[0] is Node3D):
		return
	var pp: Vector3 = (players[0] as Node3D).global_position
	var p2 := Vector2(pp.x, pp.z)
	var zone := ""
	for z in _extra_zones + ZONES:
		if p2.distance_to(z[0]) < float(z[1]):
			zone = z[2]
			break
	if zone == "" and absf(pp.z - AVENUE_Z) < 9.0 and absf(pp.x) > 30.0:
		zone = "Avenida Universitaria"
	if zone == _zone:
		return
	_zone = zone
	if zone == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _zone_seen.has(zone) and now - float(_zone_seen[zone]) < 90.0:
		return
	_zone_seen[zone] = now
	_show_title(zone)


func _build_title_ui() -> void:
	_title_layer = CanvasLayer.new()
	_title_layer.layer = 9
	add_child(_title_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(root)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Cormorant Garamond", "Garamond", "Georgia", "Times New Roman", "serif"])
	_title_label = Label.new()
	_title_label.add_theme_font_override("font", font)
	_title_label.add_theme_font_size_override("font_size", 44)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.86, 0.74))
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title_label.anchor_left = 0.0
	_title_label.anchor_right = 1.0
	_title_label.offset_top = 150
	_title_label.offset_bottom = 210
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.modulate.a = 0.0
	root.add_child(_title_label)
	_title_line = ColorRect.new()
	_title_line.color = Color(0.85, 0.78, 0.6, 0.7)
	_title_line.anchor_left = 0.35
	_title_line.anchor_right = 0.65
	_title_line.offset_top = 214
	_title_line.offset_bottom = 215
	_title_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_line.modulate.a = 0.0
	root.add_child(_title_line)


func _show_title(text: String) -> void:
	if _title_label == null:
		return
	if _title_tw and _title_tw.is_valid():
		_title_tw.kill()
	_title_label.text = text
	_title_tw = create_tween()
	_title_tw.tween_property(_title_label, "modulate:a", 1.0, 1.2)
	_title_tw.parallel().tween_property(_title_line, "modulate:a", 1.0, 1.2)
	_title_tw.tween_interval(3.0)
	_title_tw.tween_property(_title_label, "modulate:a", 0.0, 1.8)
	_title_tw.parallel().tween_property(_title_line, "modulate:a", 0.0, 1.8)


# ================================================================ materiales

func _make_world_materials() -> void:
	m_path = _tile(2, Vector2(0.9, 0.45), Color(0.36, 0.34, 0.31), Color(0.45, 0.42, 0.38), Color(0.12, 0.11, 0.1), 0.05, 0.8, 0.45)
	m_marble = _tile(1, Vector2(1.4, 1.4), Color(0.46, 0.44, 0.41), Color(0.13, 0.12, 0.12), Color(0.08, 0.08, 0.08), 0.015, 0.35, 0.2)
	m_marble.set_shader_parameter("dirt", 0.55)
	m_raised = _tile(0, Vector2(0.6, 0.6), Color(0.2, 0.21, 0.23), Color(0.25, 0.26, 0.28), Color(0.02, 0.04, 0.06), 0.04, 0.15, 0.12)
	m_raised.set_shader_parameter("glow_color", Color(0.1, 0.55, 1.0))
	m_raised.set_shader_parameter("glow_energy", 0.28)
	m_raised.set_shader_parameter("grout_width", 0.025)
	m_raised.set_shader_parameter("broken", 0.12)
	m_labtile = _tile(0, Vector2(0.5, 0.5), Color(0.6, 0.62, 0.6), Color(0.7, 0.72, 0.7), Color(0.22, 0.24, 0.22), 0.04, 0.5, 0.3)
	m_labtile.set_shader_parameter("dirt", 0.65)
	m_stoneslab = _tile(3, Vector2(2.6, 2.2), Color(0.3, 0.28, 0.26), Color(0.4, 0.37, 0.33), Color(0.06, 0.06, 0.06), 0.03, 0.7, 0.35)
	m_stoneslab.set_shader_parameter("glow_color", Color(1.0, 0.58, 0.2))
	m_stoneslab.set_shader_parameter("glow_energy", 1.6)
	m_stoneslab.set_shader_parameter("center", Vector2(FINAL.x, FINAL.z))
	m_asphalt = _tile(0, Vector2(2.8, 5.6), Color(0.1, 0.1, 0.11), Color(0.13, 0.13, 0.14), Color(0.5, 0.5, 0.46), 0.022, 0.85, 0.5)
	m_asphalt.set_shader_parameter("dirt", 0.55)

	m_white_lab = _concrete(Color(0.66, 0.67, 0.65), 0.45, 0.05)
	m_stone_light = _concrete(Color(0.62, 0.58, 0.5), 0.6, 0.2)

	var led_shader: Shader = load("res://shaders/blink_led.gdshader")
	m_led = ShaderMaterial.new()
	m_led.shader = led_shader
	m_beacon = ShaderMaterial.new()
	m_beacon.shader = led_shader
	m_beacon.set_shader_parameter("tint", Color(1.0, 0.08, 0.04))
	m_beacon.set_shader_parameter("energy", 8.0)
	m_beacon.set_shader_parameter("rate", 0.9)
	m_beacon.set_shader_parameter("blink", 1.0)

	var fluid_shader: Shader = load("res://shaders/specimen_fluid.gdshader")
	m_fluid = ShaderMaterial.new()
	m_fluid.shader = fluid_shader
	m_fluid.set_shader_parameter("noise_tex", noise_tex)
	m_fluid.set_shader_parameter("opacity", 0.28)
	m_fluid.set_shader_parameter("glow", 0.9)
	m_fluid_amber = ShaderMaterial.new()
	m_fluid_amber.shader = fluid_shader
	m_fluid_amber.set_shader_parameter("noise_tex", noise_tex)
	m_fluid_amber.set_shader_parameter("fluid_color", Color(1.0, 0.62, 0.15))
	m_fluid_amber.set_shader_parameter("opacity", 0.28)
	m_fluid_amber.set_shader_parameter("glow", 0.9)

	m_wood_dark = _std(Color(0.11, 0.065, 0.035), 0.65, 0.0)
	m_book = _std(Color(1, 1, 1), 0.8, 0.0)
	m_book.vertex_color_use_as_albedo = true
	m_paper = _std(Color(0.72, 0.69, 0.6), 0.9, 0.0)
	m_paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_metal = _std(Color(0.16, 0.17, 0.19), 0.35, 0.8)
	m_metal_light = _std(Color(0.5, 0.52, 0.55), 0.3, 0.85)
	m_rack = _std(Color(0.045, 0.05, 0.055), 0.4, 0.6)
	m_screen = _emit(Color(0.2, 1.0, 0.45), 1.6)
	m_cyan = _emit(Color(0.2, 0.8, 1.0), 3.0)
	m_holo = _emit(Color(0.25, 0.85, 1.0), 2.5)
	m_holo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_holo.albedo_color.a = 0.35
	m_holo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_holo.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_panel_light = _emit(Color(0.8, 0.9, 1.0), 2.0)
	m_flesh = _std(Color(0.52, 0.43, 0.39), 0.4, 0.0)
	m_flesh_dark = _std(Color(0.3, 0.27, 0.3), 0.35, 0.0)
	m_eye = _emit(Color(1.0, 0.75, 0.2), 5.0)
	m_glass_clear = _std(Color(0.7, 0.92, 0.85, 0.2), 0.05, 0.3)
	m_glass_clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_glass_clear.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_spill = _emit(Color(0.25, 0.95, 0.4), 0.45)
	m_spill.albedo_color = Color(0.1, 0.4, 0.15, 0.75)
	m_spill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_spill.roughness = 0.02
	m_bubble = _emit(Color(0.7, 1.0, 0.75), 1.5)
	m_bubble.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_bubble.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_bubble.albedo_color = Color(0.7, 1.0, 0.8, 0.5)
	m_hazard_y = _std(Color(0.8, 0.58, 0.05), 0.5, 0.0)
	m_hazard_k = _std(Color(0.04, 0.04, 0.04), 0.5, 0.0)
	m_gold = _std(Color(0.75, 0.55, 0.2), 0.3, 1.0)
	m_clock = _emit(Color(1.0, 0.9, 0.65), 2.2)
	m_seal = _emit(Color(1.0, 0.25, 0.08), 4.0)
	m_line = _std(Color(0.7, 0.7, 0.66), 0.8, 0.0)
	m_sandbag = _std(Color(0.33, 0.29, 0.21), 0.95, 0.0)
	m_hedge = _std(Color(0.07, 0.09, 0.05), 0.9, 0.0)
	m_canvas = _std(Color(0.22, 0.26, 0.18), 0.9, 0.0)
	m_canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_flood = _emit(Color(1.0, 0.95, 0.85), 4.0)
	m_stained.clear()
	for c in [Color(0.9, 0.15, 0.1), Color(0.15, 0.3, 0.95), Color(1.0, 0.65, 0.15), Color(0.2, 0.75, 0.35)]:
		var s := _emit(c, 1.8)
		s.albedo_color = c * 0.3
		m_stained.append(s)


func _tile(pattern: int, size: Vector2, a: Color, b: Color, grout: Color, gw: float, wet: float, puddles: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/tile_floor.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex)
	m.set_shader_parameter("pattern", pattern)
	m.set_shader_parameter("tile_size", size)
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("grout_color", grout)
	m.set_shader_parameter("grout_width", gw)
	m.set_shader_parameter("wetness", wet)
	m.set_shader_parameter("puddle_coverage", puddles)
	return m


func _emit(c: Color, energy: float) -> StandardMaterial3D:
	var m := _std(c * 0.4, 0.3, 0.0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


# ================================================================ ayudantes

func _ub(mat: Material) -> BoxMesh:
	var k := "b%d" % mat.get_instance_id()
	if not _units.has(k):
		var b := BoxMesh.new()
		b.material = mat
		_units[k] = b
	return _units[k]


func _uc(mat: Material, segs := 12, top := 1.0) -> CylinderMesh:
	var k := "c%d_%d_%.2f" % [mat.get_instance_id(), segs, top]
	if not _units.has(k):
		var c := CylinderMesh.new()
		c.top_radius = 0.5 * top
		c.bottom_radius = 0.5
		c.height = 1.0
		c.radial_segments = segs
		c.rings = 1
		c.material = mat
		_units[k] = c
	return _units[k]


func _us(mat: Material, segs := 12) -> SphereMesh:
	var k := "s%d_%d" % [mat.get_instance_id(), segs]
	if not _units.has(k):
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		s.radial_segments = segs
		s.rings = maxi(4, segs / 2)
		s.material = mat
		_units[k] = s
	return _units[k]


func _rb(rot_deg: Vector3) -> Basis:
	return Basis.from_euler(rot_deg * (PI / 180.0))


## Caja (MultiMesh) en coordenadas de mundo, con colisión opcional.
func _blk(pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO, collide := false) -> void:
	var b := _rb(rot)
	_mm_add(_ub(mat), Transform3D(b * Basis.from_scale(size), pos))
	if collide:
		_wc(size, Transform3D(b, pos))


## Cilindro (MultiMesh). `top` es la proporción del radio superior.
func _cy(pos: Vector3, r: float, h: float, mat: Material, rot := Vector3.ZERO, segs := 12, top := 1.0, collide := false) -> void:
	var b := _rb(rot)
	_mm_add(_uc(mat, segs, top), Transform3D(b * Basis.from_scale(Vector3(r * 2.0, h, r * 2.0)), pos))
	if collide:
		_wc(Vector3(r * 1.7, h, r * 1.7), Transform3D(b, pos))


func _sp(pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO, segs := 12) -> void:
	_mm_add(_us(mat, segs), Transform3D(_rb(rot) * Basis.from_scale(size), pos))


## Cilindro entre dos puntos.
func _rod(a: Vector3, b: Vector3, r: float, mat: Material, segs := 6) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var basis := Basis(Quaternion(Vector3.UP, d / l)) * Basis.from_scale(Vector3(r * 2.0, l, r * 2.0))
	_mm_add(_uc(mat, segs), Transform3D(basis, (a + b) * 0.5))


func _wc(size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.transform = xf
	w_body.add_child(cs)


func _mmc_add(mesh: Mesh, xf: Transform3D, c: Color) -> void:
	var k := mesh.get_instance_id()
	if not _mmc.has(k):
		_mmc[k] = {"mesh": mesh, "xf": [], "c": []}
	_mmc[k]["xf"].append(xf)
	_mmc[k]["c"].append(c)


func _flush_colors(parent: Node3D) -> void:
	for k in _mmc:
		var d: Dictionary = _mmc[k]
		var xs: Array = d["xf"]
		var cs: Array = d["c"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = d["mesh"]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
			mm.set_instance_color(i, cs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
	_mmc.clear()


func _begin_zone(n: String) -> Node3D:
	w_zone = Node3D.new()
	w_zone.name = n
	(_zone_parent if _zone_parent else _root).add_child(w_zone)
	return w_zone


func _end_zone() -> void:
	_flush(w_zone)
	_flush_colors(w_zone)


func _omni(parent: Node3D, pos: Vector3, col: Color, energy: float, rng_: float, dropout := -1.0, speed := 3.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_
	l.omni_attenuation = 1.3
	l.light_volumetric_fog_energy = 1.5
	l.distance_fade_enabled = true
	l.distance_fade_begin = 110.0
	l.distance_fade_length = 30.0
	if dropout >= 0.0:
		l.set_script(FLICKER)
		l.set("base_energy", energy)
		l.set("dropout_chance", dropout)
		l.set("speed", speed)
	parent.add_child(l)
	return l


func _lbl(parent: Node3D, text: String, pos: Vector3, yaw_deg: float, size: int, col: Color, shaded := true, pixel := 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = col
	l.outline_size = 0
	l.shaded = shaded
	l.double_sided = false
	l.position = pos
	l.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(l)
	return l


func _reserve(c: Vector2, r: float) -> void:
	_blocked.append([c, r])


func _is_free(p: Vector2, margin: float) -> bool:
	if absf(p.y - AVENUE_Z) < 8.0 + margin:
		return false
	if p.length() < 100.0:
		return false
	for b in _blocked:
		if p.distance_to(b[0]) < float(b[1]) + margin:
			return false
	for r in _blocked_rects:
		if (r as Rect2).grow(margin).has_point(p):
			return false
	for s in _paths:
		var a: Vector2 = s[0]
		var e: Vector2 = s[1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, e)
		if p.distance_to(q) < float(s[2]) * 0.5 + margin:
			return false
	return true


func _rand_free(margin: float, tries := 30) -> Vector2:
	for t in tries:
		var p := Vector2(rng.randf_range(BOUNDS.position.x + 6, BOUNDS.end.x - 6), rng.randf_range(BOUNDS.position.y + 6, BOUNDS.end.y - 6))
		if _is_free(p, margin):
			return p
	return Vector2.INF


# ================================================================ edificios

## Los edificios de la plaza los genera arena_generator: aquí solo se reservan.
func _reserve_hub() -> void:
	for hb in [Vector2(-44, -34), Vector2(44, -30), Vector2(48, 10), Vector2(-18, -88), Vector2(32, -82),
			Vector2(-80, -40), Vector2(82, -44), Vector2(-86, 22), Vector2(88, 24), Vector2(-48, 72), Vector2(46, 70), Vector2(0, -48)]:
		_reserve(hb, 22.0)


# ================================================================ caminos

func _make_paths() -> void:
	_begin_zone("Paths")
	var defs := [
		[Vector2(-160, 32), Vector2(-160, -204), 8.0],     # Calzada oeste
		[Vector2(-160, -40), Vector2(-207, -40), 7.0],     # Ramal a la biblioteca
		[Vector2(170, 32), Vector2(170, -236), 8.0],       # Calzada este
		[Vector2(170, -45), Vector2(214, -45), 7.0],       # Ramal al centro de cómputo
		[Vector2(-164, -200), Vector2(174, -200), 9.0],    # Paseo norte
		[Vector2(0, -224), Vector2(0, -274), 14.0],        # Avenida del Aula Magna
		[Vector2(-160, -150), Vector2(-114, -150), 5.0],   # Al estadio
		[Vector2(170, -150), Vector2(112, -150), 5.0],     # Al estacionamiento
		[Vector2(0, -176), Vector2(0, -112), 5.0],         # Jardín norte-sur
		[Vector2(-46, -150), Vector2(48, -150), 4.0],      # Jardín este-oeste
		[Vector2(-160, -96), Vector2(-134, -96), 5.0],     # A la cafetería
		[Vector2(-200, 44), Vector2(-200, 62), 4.0],       # Residencias
		[Vector2(200, 44), Vector2(200, 62), 4.0],
		[Vector2(-124, 44), Vector2(-124, 64), 4.0],
		[Vector2(124, 44), Vector2(124, 66), 4.0],
		[Vector2(-160, -204), Vector2(-178, -268), 6.0],   # Al malecón del lago
		[Vector2(-232, 26), Vector2(-232, 33), 5.0],       # Facultades
		[Vector2(-232, -22), Vector2(-224, -28), 5.0],
		[Vector2(240, 26), Vector2(240, 33), 5.0],
		[Vector2(240, -22), Vector2(232, -34), 5.0],
		[Vector2(144, -90), Vector2(167, -90), 5.0],
		[Vector2(-211, -185), Vector2(-163, -185), 5.0],
		[Vector2(221, -180), Vector2(173, -180), 5.0],
		[Vector2(100, -223), Vector2(100, -276), 5.0],
		[Vector2(-100, -223), Vector2(-100, -276), 5.0],
		# Caminos entre los edificios de conexión y las arenas
		[Vector2(-109, 0.5), Vector2(-157, 0.5), 5.0],
		[Vector2(-160, -40), Vector2(-118, -40), 5.0],
		[Vector2(-118, -40), Vector2(-96, -60), 5.0],
		[Vector2(-96, -60), Vector2(-89, -63.5), 5.0],
		[Vector2(89, -63.5), Vector2(94, -58), 5.0],
		[Vector2(94, -58), Vector2(167, -58), 5.0],
		[Vector2(78, -204), Vector2(78, -213), 4.0],
		[Vector2(126, -223), Vector2(126, -230), 5.0],
		[Vector2(126, -230), Vector2(164, -240), 5.0],
		[Vector2(164, -246), Vector2(99, -252.5), 5.0],
		[Vector2(41, -252.5), Vector2(7, -252.5), 5.0],
		# Desvíos alrededor de las estructuras acomodadas en la escena (calculados con A*)
		[Vector2(89, -63.5), Vector2(97, -60), 5.0],
		[Vector2(97, -60), Vector2(127, -55), 5.0],
		[Vector2(127, -55), Vector2(130, -48), 5.0],
		[Vector2(130, -48), Vector2(130, -45), 5.0],
		[Vector2(130, -45), Vector2(137, -43), 5.0],
		[Vector2(137, -43), Vector2(163, -46), 5.0],
		[Vector2(163, -46), Vector2(214, -45), 5.0],
		[Vector2(214, -45), Vector2(173, -51), 5.0],
		[Vector2(173, -51), Vector2(159, -149), 5.0],
		[Vector2(159, -149), Vector2(124, -152), 5.0],
		[Vector2(124, -152), Vector2(115, -157), 5.0],
		[Vector2(115, -157), Vector2(90, -195), 5.0],
		[Vector2(90, -195), Vector2(78, -212), 5.0],
		[Vector2(164, -246), Vector2(138, -246), 5.0],
		[Vector2(138, -246), Vector2(126, -247), 5.0],
		[Vector2(126, -247), Vector2(111, -246), 5.0],
		[Vector2(111, -246), Vector2(107, -248), 5.0],
		[Vector2(107, -248), Vector2(99, -252.5), 5.0],
	]
	var idx := 0
	for d in defs:
		_path(d[0], d[1], d[2], idx)
		idx += 1
	# Plazas circulares
	var plazas := [
		[Vector2(-220, -40), 14.0],   # Atrio de la biblioteca
		[Vector2(225, -45), 12.0],    # Atrio del centro de cómputo
		[Vector2(170, -244), 11.0],   # Retén del laboratorio
		[Vector2(0, -200), 26.0],     # Explanada
	]
	for p in plazas:
		var c: Vector2 = p[0]
		var r: float = p[1]
		_mm_add(_uc(m_path, 48), Transform3D(Basis.from_scale(Vector3(r * 2.0, 0.07, r * 2.0)), Vector3(c.x, 0.0, c.y)))
		_cy(Vector3(c.x, 0.0, c.y), r + 0.35, 0.2, m_concrete_dark, Vector3.ZERO, 48)
		_reserve(c, r)
	_end_zone()


func _path(a: Vector2, b: Vector2, w: float, idx: int) -> void:
	_paths.append([a, b, w])
	var d := b - a
	var l := d.length()
	var yaw := atan2(d.x, d.y)
	var basis := Basis(Vector3.UP, yaw)
	var mid := (a + b) * 0.5
	var y := 0.002 * float(idx % 8)
	_mm_add(_ub(m_path), Transform3D(basis * Basis.from_scale(Vector3(w, 0.06, l + w * 0.5)), Vector3(mid.x, y, mid.y)))
	# Bordillos
	var side := basis * Vector3.RIGHT
	for s: float in [-1.0, 1.0]:
		var cp := Vector3(mid.x, 0.04, mid.y) + side * s * (w * 0.5 + 0.18)
		_mm_add(_ub(m_concrete_dark), Transform3D(basis * Basis.from_scale(Vector3(0.36, 0.16, l - 1.0)), cp))
	# Faroles a lo largo del camino
	if l > 20.0 and w >= 5.0:
		var n := int(l / 26.0)
		for k in n:
			var t := (float(k) + 0.5) / float(n)
			var s2 := 1.0 if k % 2 == 0 else -1.0
			var p := Vector3(lerpf(a.x, b.x, t), 0, lerpf(a.y, b.y, t)) + side * s2 * (w * 0.5 + 1.3)
			var face := rad_to_deg(yaw) + (90.0 if s2 > 0.0 else -90.0)
			var state := 0 if rng.randf() < 0.4 else (1 if rng.randf() < 0.7 else 2)
			_street_lamp(p, face, state)


## Farol. state: 0 encendido, 1 apagado, 2 inclinado y apagado.
func _street_lamp(pos: Vector3, yaw_deg: float, state: int) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg + 90.0))
	if state == 2:
		b = b * Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(12, 24)))
	var at := func(v: Vector3) -> Vector3: return pos + b * v
	_mm_add(_uc(m_iron, 8, 0.75), Transform3D(b * Basis.from_scale(Vector3(0.44, 0.6, 0.44)), at.call(Vector3(0, 0.3, 0))))
	_mm_add(_uc(m_iron, 6, 0.7), Transform3D(b * Basis.from_scale(Vector3(0.18, 6.0, 0.18)), at.call(Vector3(0, 3.0, 0))))
	_mm_add(_ub(m_iron), Transform3D(b * Basis.from_scale(Vector3(1.4, 0.08, 0.08)), at.call(Vector3(0.65, 5.9, 0))))
	_mm_add(_ub(m_iron), Transform3D(b * Basis.from_scale(Vector3(0.6, 0.18, 0.32)), at.call(Vector3(1.25, 5.8, 0))))
	_mm_add(_ub(m_lamp_on if state == 0 else m_glass), Transform3D(b * Basis.from_scale(Vector3(0.5, 0.04, 0.26)), at.call(Vector3(1.25, 5.69, 0))))
	if state == 0:
		_omni(w_zone, at.call(Vector3(1.25, 5.3, 0)), Color(1.0, 0.64, 0.34), 2.2, 13.0, 0.004 if rng.randf() < 0.6 else 0.03)
	_wc(Vector3(0.35, 6.0, 0.35), Transform3D(b, at.call(Vector3(0, 3.0, 0))))


# ================================================================ perímetro

func _make_perimeter() -> void:
	_begin_zone("Perimeter")
	var x0 := BOUNDS.position.x
	var x1 := BOUNDS.end.x
	var z0 := BOUNDS.position.y
	var z1 := BOUNDS.end.y
	_wall_line(Vector2(x0, z0), Vector2(x1, z0))
	_wall_line(Vector2(x1, z0), Vector2(x1, z1))
	_wall_line(Vector2(x1, z1), Vector2(x0, z1))
	_wall_line(Vector2(x0, z1), Vector2(x0, z0))

	# Barricadas donde la avenida sale del campus
	for sx: float in [-1.0, 1.0]:
		var bx := sx * (BOUNDS.end.x - 9.0)
		for k in 6:
			var bz := AVENUE_Z - 6.0 + k * 2.4 + rng.randf_range(-0.3, 0.3)
			_blk(Vector3(bx + rng.randf_range(-1.0, 1.0), 0.42, bz), Vector3(0.6, 0.85, 2.6), m_concrete, Vector3(0, rng.randf_range(-20, 20), 0), true)
		_mound(Vector3(sx * (BOUNDS.end.x - 4.0), 0, AVENUE_Z), 7.0, 2.2)
		_car(w_zone, Vector3(sx * (BOUNDS.end.x - 16.0), 0, AVENUE_Z + 3.0), 90.0 + rng.randf_range(-20, 20), 0.0, Color(0.3, 0.3, 0.32), true)
		_bus(w_zone, Vector3(sx * (BOUNDS.end.x - 22.0), 0, AVENUE_Z - 3.5), 80.0 * sx)

	# Silueta de la ciudad destruida fuera del campus (sin colisión)
	for k in 70:
		var side := rng.randi() % 4
		var off := rng.randf_range(30.0, 170.0)
		var p := Vector2.ZERO
		match side:
			0: p = Vector2(rng.randf_range(x0 - 150, x1 + 150), z0 - off)
			1: p = Vector2(x1 + off, rng.randf_range(z0 - 150, z1 + 150))
			2: p = Vector2(rng.randf_range(x0 - 150, x1 + 150), z1 + off)
			_: p = Vector2(x0 - off, rng.randf_range(z0 - 150, z1 + 150))
		var w := rng.randf_range(14, 36)
		var d := rng.randf_range(14, 30)
		var h := rng.randf_range(18, 85)
		var yaw := rng.randf_range(-15, 15)
		_blk(Vector3(p.x, h * 0.5, p.y), Vector3(w, h, d), m_concrete_dark, Vector3(0, yaw, 0))
		if rng.randf() < 0.5:
			# Remate roto e inclinado
			_blk(Vector3(p.x + rng.randf_range(-3, 3), h + 3.0, p.y), Vector3(w * 0.6, 7.0, d * 0.7), m_concrete_dark, Vector3(rng.randf_range(-14, 14), yaw, rng.randf_range(-14, 14)))
	_end_zone()


func _wall_line(a: Vector2, b: Vector2) -> void:
	var d := b - a
	var l := d.length()
	var yaw := atan2(d.x, d.y) + PI * 0.5
	var basis := Basis(Vector3.UP, yaw)
	var n := int(l / 4.0)
	for k in n:
		var t := (float(k) + 0.5) / float(n)
		var p := Vector3(lerpf(a.x, b.x, t), 0, lerpf(a.y, b.y, t))
		var roll := rng.randf()
		if roll < 0.12:
			var h := rng.randf_range(1.0, 2.6)
			_mm_add(_ub(m_concrete_dark), Transform3D(basis * Basis.from_scale(Vector3(4.02, h, 0.5)), p + Vector3(0, h * 0.5, 0)))
			_chunk(p + basis * Vector3(0, 0, rng.randf_range(-2.5, 2.5)), 0.4, 1.4)
		elif roll < 0.16:
			_mound(p, 4.0, 1.6)
		else:
			_mm_add(_ub(m_concrete_dark), Transform3D(basis * Basis.from_scale(Vector3(4.02, 3.4, 0.5)), p + Vector3(0, 1.7, 0)))
			if rng.randf() < 0.7:
				for q in 6:
					var bp := p + basis * Vector3(-1.75 + q * 0.7, 3.95, 0)
					_mm_add(mesh_bar, Transform3D(Basis.from_scale(Vector3(1, 0.5, 1)), bp))
		if k % 2 == 0:
			_mm_add(_ub(m_concrete), Transform3D(basis * Basis.from_scale(Vector3(0.7, 3.9, 0.7)), p + basis * Vector3(-2.0, 1.95, 0)))
	var mid := (a + b) * 0.5
	_wc(Vector3(l + 2.0, 14.0, 1.2), Transform3D(basis, Vector3(mid.x, 7.0, mid.y)))


# ================================================================ biblioteca

func _make_library() -> void:
	var zone := _begin_zone("Biblioteca")
	var o := LIB
	var hx := 30.0
	var hz := 22.0
	var H := 16.0
	var t := 1.2
	_reserve(Vector2(o.x, o.z + 4), 40.0)

	# Piso de mármol
	_blk(o, Vector3(hx * 2.0, 0.06, hz * 2.0), m_marble)

	# Muros (hueco de 10 m en el frente)
	_blk(o + Vector3(0, H * 0.5, -hz - t * 0.5), Vector3(hx * 2.0 + t * 2.0, H, t), m_stone, Vector3.ZERO, true)
	for s: float in [-1.0, 1.0]:
		_blk(o + Vector3(s * (hx + t * 0.5), H * 0.5, 0), Vector3(t, H, hz * 2.0), m_stone, Vector3.ZERO, true)
		var w := hx + t - 5.0
		_blk(o + Vector3(s * (5.0 + w * 0.5), H * 0.5, hz + t * 0.5), Vector3(w, H, t), m_stone, Vector3.ZERO, true)
	_blk(o + Vector3(0, 8.0 + (H - 8.0) * 0.5, hz + t * 0.5), Vector3(10, H - 8.0, t), m_stone, Vector3.ZERO, true)
	# Pilastras y cornisa exteriores
	for k in 11:
		var x := -hx + k * 6.0
		_blk(o + Vector3(x, (H + 1.0) * 0.5, -hz - t - 0.4), Vector3(1.1, H + 1.0, 0.8), m_stone_light)
	for k in 9:
		var z := -hz + k * 5.5
		for s: float in [-1.0, 1.0]:
			_blk(o + Vector3(s * (hx + t + 0.4), (H + 1.0) * 0.5, z), Vector3(0.8, H + 1.0, 1.1), m_stone_light)
	_blk(o + Vector3(0, H + 0.5, -hz - t * 0.5), Vector3(hx * 2.0 + 4.0, 1.0, 2.4), m_stone_light)
	_blk(o + Vector3(0, H + 0.5, hz + t * 0.5), Vector3(hx * 2.0 + 4.0, 1.0, 2.4), m_stone_light)
	for s: float in [-1.0, 1.0]:
		_blk(o + Vector3(s * (hx + t * 0.5), H + 0.5, 0), Vector3(2.4, 1.0, hz * 2.0 + 4.0), m_stone_light)
	# Bordes superiores dañados
	for k in 40:
		var side := rng.randi() % 4
		var p := Vector3.ZERO
		match side:
			0: p = Vector3(rng.randf_range(-hx, hx), H + 1.0, -hz - 0.6)
			1: p = Vector3(rng.randf_range(-hx, hx), H + 1.0, hz + 0.6)
			2: p = Vector3(-hx - 0.6, H + 1.0, rng.randf_range(-hz, hz))
			_: p = Vector3(hx + 0.6, H + 1.0, rng.randf_range(-hz, hz))
		_chunk(o + p, 0.4, 1.3)

	# Vitrales del muro norte y ventanas altas laterales
	for k in 5:
		var x := -20.0 + k * 10.0
		var sm: StandardMaterial3D = m_stained[k % m_stained.size()]
		_blk(o + Vector3(x, 13.1, -hz - t * 0.5), Vector3(3.2, 4.6, t + 0.08), sm)
		_blk(o + Vector3(x, 15.6, -hz - t * 0.5), Vector3(3.6, 0.4, t + 0.2), m_stone_light)
		_blk(o + Vector3(x, 10.6, -hz - t * 0.5), Vector3(3.6, 0.4, t + 0.2), m_stone_light)
		_blk(o + Vector3(x, 13.1, -hz - t * 0.5), Vector3(0.15, 4.6, t + 0.12), m_iron)
	for k in 4:
		var z := -15.0 + k * 10.0
		for s: float in [-1.0, 1.0]:
			_blk(o + Vector3(s * (hx + t * 0.5), 11.0, z), Vector3(t + 0.08, 5.0, 2.2), m_glass)

	# Columnas interiores (una rota)
	for cx: float in [-16.0, 16.0]:
		for cz: float in [-12.0, 0.0, 12.0]:
			var cp := o + Vector3(cx, 0, cz)
			_blk(cp + Vector3(0, 0.3, 0), Vector3(2.0, 0.6, 2.0), m_stone_light, Vector3.ZERO, true)
			if cx > 0.0 and cz > 0.0:
				_cy(cp + Vector3(0, 3.0, 0), 0.8, 6.0, m_stone_light, Vector3.ZERO, 14, 1.0, true)
				_rebar(cp + Vector3(0, 6.0, 0), 3)
				_cy(cp + Vector3(-4.0, 0.8, 3.5), 0.8, 8.0, m_stone_light, Vector3(0, 35, 90), 14, 1.0, true)
			else:
				_cy(cp + Vector3(0, H * 0.5, 0), 0.8, H, m_stone_light, Vector3.ZERO, 14, 1.0, true)
				_blk(cp + Vector3(0, H - 0.4, 0), Vector3(2.0, 0.8, 2.0), m_stone_light)

	# Mezzanine perimetral con barandal
	var my := 7.0
	_blk(o + Vector3(0, my, -hz + 1.7), Vector3(hx * 2.0, 0.4, 3.4), m_wood_dark, Vector3.ZERO, true)
	for s: float in [-1.0, 1.0]:
		if s > 0.0:
			# Tramo este derrumbado: una parte cuelga y otra cayó al piso
			_blk(o + Vector3(hx - 1.7, my, -hz + 3.4 + 7.0), Vector3(3.4, 0.4, 14.0), m_wood_dark, Vector3.ZERO, true)
			_blk(o + Vector3(hx - 3.0, 3.4, 6.0), Vector3(3.4, 0.4, 12.0), m_wood_dark, Vector3(-30, 0, -8), true)
			for k in 20:
				_chunk(o + Vector3(hx - rng.randf_range(2, 7), 0, rng.randf_range(0, 14)), 0.2, 0.7)
		else:
			_blk(o + Vector3(s * (hx - 1.7), my, 1.7), Vector3(3.4, 0.4, hz * 2.0 - 3.4), m_wood_dark, Vector3.ZERO, true)
	_rail(o + Vector3(-hx + 3.4, my + 0.2, -hz + 3.4), o + Vector3(hx - 3.4, my + 0.2, -hz + 3.4))
	_rail(o + Vector3(-hx + 3.4, my + 0.2, -hz + 3.4), o + Vector3(-hx + 3.4, my + 0.2, hz))
	_rail(o + Vector3(hx - 3.4, my + 0.2, -hz + 3.4), o + Vector3(hx - 3.4, my + 0.2, -hz + 17.4))
	for k in 9:
		var z := -hz + 4.0 + k * 5.0
		_blk(o + Vector3(-hx + 0.6, my - 0.8, z), Vector3(1.2, 1.2, 0.4), m_wood_dark)

	# Estanterías: muros, mezzanine y pasillos laterales
	var x := -hx + 2.5
	while x < hx - 2.0:
		_bookshelf(o + Vector3(x, 0, -hz + 0.5), 0.0, 4.0, 6.3)
		_bookshelf(o + Vector3(x, my + 0.2, -hz + 0.5), 0.0, 4.0, 3.2)
		x += 4.1
	var z := -hz + 4.0
	while z < hz - 2.0:
		_bookshelf(o + Vector3(-hx + 0.5, 0, z), 90.0, 4.0, 6.3)
		_bookshelf(o + Vector3(-hx + 0.5, my + 0.2, z), 90.0, 4.0, 3.2)
		if z < -2.0 or z > 14.0:
			_bookshelf(o + Vector3(hx - 0.5, 0, z), -90.0, 4.0, 6.3)
		z += 4.1
	for s: float in [-1.0, 1.0]:
		var xx := 7.5
		while xx < hx - 2.0:
			_bookshelf(o + Vector3(s * xx, 0, hz - 0.5), 180.0, 4.0, 6.3)
			xx += 4.1
	for s: float in [-1.0, 1.0]:
		for zz: float in [-15.5, -11.4, -7.3, 6.0, 10.1, 14.2]:
			if s > 0.0 and zz > 5.0 and zz < 12.0:
				continue
			_bookshelf(o + Vector3(s * 22.0 - 0.46, 0, zz), -90.0, 4.0, 5.4)
			_bookshelf(o + Vector3(s * 22.0 + 0.46, 0, zz), 90.0, 4.0, 5.4)
	# Estantes caídos (cobertura) y montones de libros
	_bookshelf(o + Vector3(-7.0, 0.5, 8.5), 30.0, 4.0, 5.4, -86.0)
	_bookshelf(o + Vector3(9.5, 0.5, -6.5), -50.0, 4.0, 5.4, -86.0)
	_bookshelf(o + Vector3(21.0, 0.5, 8.0), 75.0, 4.0, 5.4, -86.0)
	_bookshelf(o + Vector3(-12.6, 0.0, -5.0), -90.0, 4.0, 5.4, 22.0)
	for q in 9:
		var c := o + Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-18, 18))
		_book_pile(c, rng.randi_range(15, 40))

	# Pizarrones con ruedas (aquí escribe el Bibliófilo Demente)
	for bd in LIB_BOARDS:
		var bb := Basis(Vector3.UP, deg_to_rad(float(bd[1])))
		var bo: Vector3 = o + (bd[0] as Vector3)
		_lbox(bo, bb, Vector3(0, 1.6, 0), Vector3(4.0, 2.2, 0.06), m_chalk)
		for sx: float in [-1.0, 1.0]:
			_lbox(bo, bb, Vector3(sx * 2.08, 1.35, 0), Vector3(0.1, 2.7, 0.1), m_wood_dark)
			_lbox(bo, bb, Vector3(sx * 2.08, 0.12, 0), Vector3(0.12, 0.08, 0.9), m_iron)
			for sz: float in [-0.4, 0.4]:
				_cy(bo + bb * Vector3(sx * 2.08, 0.06, sz), 0.06, 0.05, m_tire, Vector3(90, 0, 0), 8)
		_lbox(bo, bb, Vector3(0, 2.74, 0), Vector3(4.24, 0.1, 0.1), m_wood_dark)
		_lbox(bo, bb, Vector3(0, 0.47, 0), Vector3(4.24, 0.1, 0.1), m_wood_dark)
		_lbox(bo, bb, Vector3(0, 0.5, 0.1), Vector3(4.0, 0.04, 0.14), m_wood)
		_lbox(bo, bb, Vector3(0.6, 0.53, 0.12), Vector3(0.18, 0.05, 0.06), m_paper)
		_wc(Vector3(4.3, 2.8, 0.3), Transform3D(bb, bo + bb * Vector3(0, 1.4, 0)))

	# Mesas de lectura (una volcada)
	for tp in [Vector3(-9, 0, -15), Vector3(9, 0, -15), Vector3(-9, 0, 15), Vector3(9, 0, 15)]:
		var tpos: Vector3 = o + tp
		if tp.x > 0.0 and tp.z > 0.0:
			_blk(tpos + Vector3(0, 0.8, 0), Vector3(5.0, 1.6, 0.08), m_wood_dark, Vector3(0, 12, 0), true)
			continue
		_blk(tpos + Vector3(0, 0.85, 0), Vector3(5.0, 0.08, 1.6), m_wood_dark, Vector3.ZERO)
		for lx: float in [-2.2, 2.2]:
			_blk(tpos + Vector3(lx, 0.42, 0), Vector3(0.12, 0.84, 1.4), m_wood_dark)
		_wc(Vector3(5.0, 0.9, 1.6), Transform3D(Basis.IDENTITY, tpos + Vector3(0, 0.45, 0)))
		for cxx in 3:
			var cp := tpos + Vector3(-1.6 + cxx * 1.6, 0, 1.3 * (1.0 if rng.randf() < 0.5 else -1.0))
			var fallen := rng.randf() < 0.35
			_blk(cp + Vector3(0, 0.45 if not fallen else 0.25, 0), Vector3(0.5, 0.06, 0.5), m_wood_dark, Vector3(90 if fallen else 0, rng.randf_range(0, 360), 0))

	# Techo: losas con un gran hueco (cúpula derrumbada)
	for i in 10:
		for j in 8:
			var cx := -hx + 3.0 + i * 6.0
			var cz := -hz + 2.75 + j * 5.5
			if Vector2(cx * 0.85, cz).length() < 14.0 or rng.randf() < 0.12:
				if rng.randf() < 0.3:
					_blk(o + Vector3(cx, H - 2.0, cz), Vector3(6.0, 0.5, 5.5), m_concrete_dark, Vector3(rng.randf_range(-35, 35), 0, rng.randf_range(-35, 35)))
				continue
			_blk(o + Vector3(cx, H + 0.25, cz), Vector3(6.02, 0.5, 5.52), m_concrete_dark, Vector3.ZERO, true)
	for j in 8:
		var cz := -hz + 2.75 + j * 5.5
		if absf(cz) > 10.0:
			_blk(o + Vector3(0, H - 0.4, cz), Vector3(hx * 2.0, 0.8, 0.5), m_wood_dark)
	# Tambor de la cúpula rota
	for i in 22:
		if rng.randf() < 0.25:
			continue
		var a := TAU * i / 22.0
		var hh := rng.randf_range(1.0, 3.2)
		_blk(o + Vector3(sin(a) * 15.0, H + 0.5 + hh * 0.5, cos(a) * 15.0), Vector3(4.4, hh, 0.9), m_stone_light, Vector3(0, rad_to_deg(a), 0))
	# Escombros del techo en el centro
	for q in 60:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.0, 13.0)
		_chunk(o + Vector3(sin(a) * r * 1.2, 0, cos(a) * r), 0.15, 0.8)

	# Candelabro caído y cadena colgante
	var ch := o + Vector3(3.5, 0.0, 2.0)
	for i in 16:
		var a := TAU * i / 16.0
		var p := ch + Vector3(cos(a) * 2.2, 0.35 + sin(a) * 0.45, sin(a) * 2.2)
		_blk(p, Vector3(0.9, 0.12, 0.12), m_bronze, Vector3(0, -rad_to_deg(a) + 90.0, 12))
		if i % 2 == 0:
			_cy(p + Vector3(0, 0.25, 0), 0.06, 0.4, m_paper)
	_rod(o + Vector3(3.5, H, 2.0), o + Vector3(3.0, 9.0, 2.4), 0.06, m_iron)
	_omni(zone, ch + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.3), 1.2, 7.0, 0.0, 6.0)
	# Candelabros de pie
	for cp in [Vector3(-13, 0, -19), Vector3(13, 0, -19), Vector3(-27, 0, 0), Vector3(-13, 0, 19), Vector3(13, 0, 19)]:
		var p: Vector3 = o + cp
		_cy(p + Vector3(0, 1.1, 0), 0.07, 2.2, m_bronze)
		_cy(p + Vector3(0, 2.25, 0), 0.35, 0.12, m_bronze)
		for c3 in 3:
			_cy(p + Vector3(-0.25 + c3 * 0.25, 2.45, 0), 0.04, 0.3, m_paper)
		_omni(zone, p + Vector3(0, 2.7, 0), Color(1.0, 0.62, 0.3), 1.6, 9.0, 0.0, 7.0)
	# Puerta de madera rota
	_blk(o + Vector3(-2.5, 0.2, hz - 3.0), Vector3(5.0, 0.3, 7.5), m_wood_dark, Vector3(0, 12, 0))
	_blk(o + Vector3(4.5, 3.6, hz + 0.2), Vector3(0.3, 7.5, 4.8), m_wood_dark, Vector3(0, -55, 6))
	# Hojas de papel en el piso y flotando
	for q in 220:
		var p := o + Vector3(rng.randf_range(-hx + 1, hx - 1), 0.035, rng.randf_range(-hz + 1, hz - 1))
		_mm_add(_ub(m_paper), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(0.21, 0.004, 0.29)), p))
	_floating_papers(zone, o + Vector3(0, 12, 0), Vector3(14, 2, 12))
	# Fuego en un rincón de estanterías
	_fire(zone, o + Vector3(-25.0, 0.4, 16.0), 1.0)

	# Pórtico de columnas, parcialmente derrumbado
	var fz := hz + t
	_blk(o + Vector3(0, 0.04, fz + 4.6), Vector3(38, 0.08, 9.2), m_stone_light)
	var cols := [-16.0, -10.5, -5.5, 5.5, 10.5, 16.0]
	for cx in cols:
		var cp: Vector3 = o + Vector3(cx, 0, fz + 7.5)
		_blk(cp + Vector3(0, 0.4, 0), Vector3(2.2, 0.8, 2.2), m_stone_light, Vector3.ZERO, true)
		if cx > 15.0:
			_cy(cp + Vector3(0, 2.6, 0), 0.85, 3.6, m_stone_light, Vector3.ZERO, 16, 1.0, true)
			_rebar(cp + Vector3(0, 4.4, 0), 2)
			_cy(cp + Vector3(2.5, 0.85, -3.0), 0.85, 5.0, m_stone_light, Vector3(0, 30, 90), 16, 1.0, true)
		else:
			_cy(cp + Vector3(0, 6.8, 0), 0.85, 12.0, m_stone_light, Vector3.ZERO, 16, 0.9, true)
			_blk(cp + Vector3(0, 12.9, 0), Vector3(2.1, 0.6, 2.1), m_stone_light)
	_blk(o + Vector3(-4.5, 14.0, fz + 4.4), Vector3(26, 1.8, 8.6), m_stone_light, Vector3.ZERO, true)
	_blk(o + Vector3(-10.75, 16.6, fz + 4.4), Vector3(13.4, 0.9, 8.4), m_stone_light, Vector3(0, 0, 16.5))
	_blk(o + Vector3(1.75, 16.6, fz + 4.4), Vector3(13.4, 0.9, 8.4), m_stone_light, Vector3(0, 0, -16.5))
	_blk(o + Vector3(13.0, 1.0, fz + 9.0), Vector3(10.0, 1.8, 3.2), m_stone_light, Vector3(0, 20, 12), true)
	for q in 18:
		_chunk(o + Vector3(rng.randf_range(8, 18), 0, fz + rng.randf_range(4, 12)), 0.3, 1.3)
	var title := _lbl(zone, "BIBLIOTECA CENTRAL", o + Vector3(-4.5, 14.0, fz + 8.72), 0.0, 110, Color(0.8, 0.76, 0.64))
	title.pixel_size = 0.01

	# Atrio con fuente seca
	var fc := Vector3(-220, 0, -40)
	for i in 16:
		var a := TAU * i / 16.0
		_blk(fc + Vector3(sin(a) * 4.5, 0.35, cos(a) * 4.5), Vector3(1.85, 0.7, 0.5), m_stone_light, Vector3(0, rad_to_deg(a), 0), true)
	_cy(fc + Vector3(0, 1.2, 0), 0.8, 2.4, m_stone_light, Vector3.ZERO, 12, 1.0, true)
	_blk(fc + Vector3(-0.7, 2.8, 0), Vector3(1.6, 0.25, 2.2), m_stone_light, Vector3(0, 0, 18))
	_blk(fc + Vector3(0.7, 2.8, 0), Vector3(1.6, 0.25, 2.2), m_stone_light, Vector3(0, 0, -18))
	for q in 10:
		_chunk(fc + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), 0.15, 0.5)
	_end_zone()


func _rail(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	var basis := Basis(Vector3.UP, atan2(d.x, d.z))
	_mm_add(_ub(m_iron), Transform3D(basis * Basis.from_scale(Vector3(0.06, 0.06, l)), (a + b) * 0.5 + Vector3(0, 1.0, 0)))
	var n := int(l / 0.5)
	for k in n:
		if rng.randf() < 0.05:
			continue
		var p := a + d * (float(k) + 0.5) / float(n)
		_mm_add(_ub(m_iron), Transform3D(Basis.from_scale(Vector3(0.04, 1.0, 0.04)), p + Vector3(0, 0.5, 0)))


func _book_color() -> Color:
	var palette := [Color(0.35, 0.08, 0.06), Color(0.1, 0.16, 0.3), Color(0.12, 0.22, 0.12), Color(0.4, 0.3, 0.16),
		Color(0.22, 0.12, 0.08), Color(0.5, 0.45, 0.35), Color(0.08, 0.08, 0.1), Color(0.3, 0.2, 0.3)]
	var c: Color = palette[rng.randi() % palette.size()]
	return c * rng.randf_range(0.7, 1.2)


## Estantería con libros. `tilt` en grados sobre su eje X (≈ -86 = caída de espaldas).
func _bookshelf(pos: Vector3, yaw: float, w: float, h: float, tilt := 0.0) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(tilt), deg_to_rad(yaw), 0.0))
	var depth := 0.9
	var rows := maxi(2, int(h / 0.95))
	var rh := h / float(rows)
	var wood := _ub(m_wood_dark)
	_mm_add(wood, Transform3D(b * Basis.from_scale(Vector3(w, h, 0.06)), pos + b * Vector3(0, h * 0.5, -depth * 0.5 + 0.03)))
	for sx: float in [-0.5, 0.5]:
		_mm_add(wood, Transform3D(b * Basis.from_scale(Vector3(0.08, h, depth)), pos + b * Vector3(sx * w, h * 0.5, 0)))
	for r in rows + 1:
		_mm_add(wood, Transform3D(b * Basis.from_scale(Vector3(w, 0.06, depth)), pos + b * Vector3(0, r * rh + 0.03, 0)))
	var book := _ub(m_book)
	for r in rows:
		var x := -w * 0.5 + 0.08
		var y0 := r * rh + 0.06
		while x < w * 0.5 - 0.14:
			if rng.randf() < 0.07:
				x += rng.randf_range(0.15, 0.5)
				continue
			var bw := rng.randf_range(0.05, 0.12)
			var bh := rng.randf_range(0.55, 0.85) * (rh - 0.08)
			var bd := rng.randf_range(0.45, 0.7)
			var lean := 0.0
			if rng.randf() < 0.06:
				lean = deg_to_rad(rng.randf_range(-25, 25))
			var lp := Vector3(x + bw * 0.5, y0 + bh * 0.5, 0.05)
			_mmc_add(book, Transform3D(b * Basis(Vector3.FORWARD, lean) * Basis.from_scale(Vector3(bw, bh, bd)), pos + b * lp), _book_color())
			x += bw + 0.008
	_wc(Vector3(w, h, depth), Transform3D(b, pos + b * Vector3(0, h * 0.5, 0)))


func _book_pile(c: Vector3, n: int) -> void:
	var book := _ub(m_book)
	for q in n:
		var p := c + Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
		var s := Vector3(rng.randf_range(0.3, 0.5), rng.randf_range(0.05, 0.12), rng.randf_range(0.4, 0.65))
		p.y = rng.randf_range(0.0, 0.5) * (1.0 - Vector2(p.x - c.x, p.z - c.z).length() / 1.7) + s.y * 0.5
		_mmc_add(book, Transform3D(_rb(Vector3(rng.randf_range(-15, 15), rng.randf_range(0, 360), rng.randf_range(-15, 15))) * Basis.from_scale(s), p), _book_color())


func _floating_papers(parent: Node3D, pos: Vector3, extents: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.name = "FloatingPapers"
	p.position = pos
	p.amount = 90
	p.lifetime = 22.0
	p.preprocess = 22.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -16, -30), Vector3(60, 22, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.3, -1, 0.1)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0.05, -0.35, 0.0)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.angular_velocity_min = -60.0
	pm.angular_velocity_max = 60.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.21, 0.29)
	q.material = m_paper
	p.draw_pass_1 = q
	parent.add_child(p)


# ================================================================ cómputo

func _make_computing() -> void:
	var zone := _begin_zone("CentroDeComputo")
	var o := COMP
	var hx := 28.0
	var hz := 22.0
	var floors := 3
	var H := floors * FLOOR_H
	_reserve(Vector2(o.x, o.z + 4), 38.0)

	# Fachadas de paneles con ventanas (3 pisos), con daño en la esquina noreste
	for side in 4:
		var count := 14 if side < 2 else 11
		for k in count:
			var pos := Vector3.ZERO
			var rot := 0.0
			match side:
				0: pos = Vector3(-hx + 2.0 + k * 4.0, 0, -hz)
				1: pos = Vector3(-hx + 2.0 + k * 4.0, 0, hz)
				2:
					pos = Vector3(-hx, 0, -hz + 2.0 + k * 4.0)
					rot = PI * 0.5
				_:
					pos = Vector3(hx, 0, -hz + 2.0 + k * 4.0)
					rot = PI * 0.5
			for L in floors:
				if side == 1 and (k == 6 or k == 7) and L < 2:
					continue
				var corner := (side == 0 and k >= 11) or (side == 3 and k <= 2)
				if (corner and L == 2) or rng.randf() < 0.05:
					_chunk(o + pos + Vector3(rng.randf_range(-1, 1), L * FLOOR_H + 0.4, rng.randf_range(-1, 1)), 0.5, 1.4)
					continue
				_mm_add(mesh_panel, Transform3D(Basis(Vector3.UP, rot), o + pos + Vector3(0, L * FLOOR_H + FLOOR_H * 0.5, 0)))
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			_blk(o + Vector3(cx * hx, (H + 0.4) * 0.5, cz * hz), Vector3(0.9, H + 0.4, 0.9), m_concrete_dark)
	_wc(Vector3(hx * 2.0, H, 0.4), Transform3D(Basis.IDENTITY, o + Vector3(0, H * 0.5, -hz)))
	for s: float in [-1.0, 1.0]:
		_wc(Vector3(0.4, H, hz * 2.0), Transform3D(Basis.IDENTITY, o + Vector3(s * hx, H * 0.5, 0)))
		_wc(Vector3(hx - 4.0, H, 0.4), Transform3D(Basis.IDENTITY, o + Vector3(s * (4.0 + (hx - 4.0) * 0.5), H * 0.5, hz)))
	_wc(Vector3(8.0, H - 7.2, 0.4), Transform3D(Basis.IDENTITY, o + Vector3(0, 7.2 + (H - 7.2) * 0.5, hz)))
	_lbl(zone, "CENTRO DE CÓMPUTO", o + Vector3(0, 9.0, hz + 0.2), 0.0, 80, Color(0.75, 0.85, 0.9))

	# Techo con colapso en la esquina noreste
	for i in 14:
		for j in 11:
			var cx := -hx + 2.0 + i * 4.0
			var cz := -hz + 2.0 + j * 4.0
			if (cx > 13.0 and cz < -9.0) or rng.randf() < 0.05:
				if rng.randf() < 0.45:
					var tilt := Vector3(rng.randf_range(-50, 50), 0, rng.randf_range(-50, 50))
					_blk(o + Vector3(cx, H - 2.2, cz), Vector3(4.0, 0.35, 4.0), m_concrete, tilt)
					_rebar(o + Vector3(cx, H - 0.5, cz), 3)
				continue
			_blk(o + Vector3(cx, H + 0.17, cz), Vector3(4.02, 0.35, 4.02), m_concrete, Vector3.ZERO, true)
	_mound(o + Vector3(22, 0, -17), 7.0, 1.8)
	for k in 7:
		_mm_add(mesh_parapet, Transform3D(Basis.IDENTITY, o + Vector3(-hx + 2.0 + k * 4.0, H + 0.8, hz)))

	# Antena reticulada con baliza y antena parabólica
	var ab := o + Vector3(-16, H + 0.35, -12)
	var th := 20.0
	for lx: float in [-1.0, 1.0]:
		for lz: float in [-1.0, 1.0]:
			_rod(ab + Vector3(lx * 1.6, 0, lz * 1.6), ab + Vector3(lx * 0.3, th, lz * 0.3), 0.07, m_metal_light, 5)
	for q in 8:
		var y := 1.0 + q * 2.4
		var r := lerpf(1.6, 0.3, y / th)
		for e in 4:
			var a1 := Vector3(-r, y, -r).rotated(Vector3.UP, e * PI * 0.5)
			var a2 := Vector3(r, y, -r).rotated(Vector3.UP, e * PI * 0.5)
			_rod(ab + a1, ab + a2, 0.04, m_metal_light, 4)
	_sp(ab + Vector3(0, th + 0.4, 0), Vector3(0.5, 0.5, 0.5), m_beacon)
	_omni(zone, ab + Vector3(0, th + 0.8, 0), Color(1.0, 0.1, 0.05), 1.5, 18.0)
	var dish := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 2.6
	dm.height = 1.3
	dm.is_hemisphere = true
	dm.material = m_metal_light
	dish.mesh = dm
	dish.position = o + Vector3(10, H + 3.2, 12)
	dish.rotation_degrees = Vector3(-120, 25, 0)
	zone.add_child(dish)
	_cy(o + Vector3(10, H + 1.4, 12), 0.25, 2.8, m_metal)

	# Piso técnico
	_blk(o, Vector3(hx * 2.0, 0.06, hz * 2.0), m_raised)

	# Filas de racks de servidores
	var racks: Array = []
	for rz: float in [-19.0, -15.5]:
		var face := 0.0 if rz < -17.0 else 180.0
		var xx := -25.0
		while xx <= 25.0:
			if absf(xx) > 5.0 and not (xx > 13.0 and rz < -17.0):
				racks.append([Vector3(xx, 0, rz), face])
			xx += 0.85
	for sx: float in [-24.0, -20.5, 20.5, 24.0]:
		var face := 90.0 if sx < 0.0 else -90.0
		if absf(sx) < 22.0:
			face = -face
		var zz := -10.0
		while zz <= 17.0:
			racks.append([Vector3(sx, 0, zz), face])
			zz += 0.85
	for r in racks:
		var rp: Vector3 = r[0]
		_rack(o + rp, r[1])
	# Colisión por fila
	for rz: float in [-19.0, -15.5]:
		_wc(Vector3(20.6, 2.2, 1.1), Transform3D(Basis.IDENTITY, o + Vector3(-15.2, 1.1, rz)))
		_wc(Vector3(8.0, 2.2, 1.1), Transform3D(Basis.IDENTITY, o + Vector3(9.4, 1.1, rz)))
	_wc(Vector3(10.4, 2.2, 1.1), Transform3D(Basis.IDENTITY, o + Vector3(19.4, 1.1, -15.5)))
	for sx: float in [-24.0, -20.5, 20.5, 24.0]:
		_wc(Vector3(1.1, 2.2, 27.8), Transform3D(Basis.IDENTITY, o + Vector3(sx, 1.1, 3.6)))
	# Racks volcados en el centro (cobertura) con chispas
	var fallen := [[Vector3(-7, 0.42, 6), 30.0], [Vector3(8, 0.42, -2), -70.0], [Vector3(-3, 0.42, -7), 100.0], [Vector3(11, 0.42, 11), 15.0]]
	for f in fallen:
		var fp: Vector3 = o + f[0]
		var b := _rb(Vector3(0, f[1], 90))
		_mm_add(_ub(m_rack), Transform3D(b * Basis.from_scale(Vector3(0.8, 2.2, 1.1)), fp))
		_wc(Vector3(0.8, 2.2, 1.1), Transform3D(b, fp))
	for sp in [Vector3(-7, 1.0, 6), Vector3(8, 1.0, -2), Vector3(-20.5, 2.3, 9.0), Vector3(12.0, 2.3, -15.5)]:
		_sparks(zone, o + sp)

	# Núcleo central (mainframe) con anillos holográficos
	var core := o + Vector3(0, 0, -16)
	_cy(core + Vector3(0, 4.0, 0), 2.2, 8.0, m_rack, Vector3.ZERO, 24, 1.0, true)
	for q in 5:
		_cy(core + Vector3(0, 1.0 + q * 1.5, 0), 2.28, 0.14, m_cyan, Vector3.ZERO, 24)
	_cy(core + Vector3(0, 8.3, 0), 2.5, 0.6, m_metal, Vector3.ZERO, 24)
	for q in 8:
		var a := TAU * q / 8.0
		_rod(core + Vector3(cos(a) * 1.6, 8.5, sin(a) * 1.6), core + Vector3(cos(a) * 3.5, H, sin(a) * 3.5), 0.12, m_iron, 6)
	for q in 2:
		var torus := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 3.1 + q * 0.6
		tm.outer_radius = 3.22 + q * 0.6
		tm.rings = 48
		tm.ring_segments = 6
		tm.material = m_holo
		torus.mesh = tm
		torus.position = core + Vector3(0, 5.0 + q * 1.2, 0)
		torus.rotation_degrees = Vector3(8 - q * 16, 0, 6)
		torus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		zone.add_child(torus)
	_lbl(zone, "NÚCLEO CENTRAL", core + Vector3(0, 7.0, 2.6), 0.0, 40, Color(0.5, 0.9, 1.0), false)
	_omni(zone, core + Vector3(0, 4.0, 4.0), Color(0.2, 0.75, 1.0), 3.0, 22.0, 0.01, 2.0)
	# Luz de emergencia tenue sobre los pasillos de racks
	for lp in [Vector3(-22, 6, -6), Vector3(22, 6, -6), Vector3(-22, 6, 12), Vector3(22, 6, 12), Vector3(-12, 6, -17), Vector3(10, 6, -17)]:
		_omni(zone, o + lp, Color(0.35, 0.55, 0.9), 0.9, 13.0)

	# Cables colgantes
	for q in 60:
		var p := o + Vector3(rng.randf_range(-hx + 1, hx - 1), H, rng.randf_range(-hz + 1, hz - 1))
		if rng.randf() < 0.2:
			var end := p + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
			end.y = 0.05
			_rod(p, end, 0.035, m_tire, 4)
		else:
			_rod(p, p - Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(1.5, 5.5), rng.randf_range(-0.3, 0.3)), 0.035, m_tire, 4)
	# Paneles de luz del techo, pocos funcionan
	var lit := 0
	for i in 9:
		for j in 7:
			var p := o + Vector3(-24 + i * 6.0, H - 0.08, -18 + j * 6.0)
			var on := rng.randf() < 0.35
			_blk(p, Vector3(1.4, 0.06, 0.5), m_panel_light if on else m_glass)
			if on and lit < 7 and rng.randf() < 0.5:
				lit += 1
				_omni(zone, p - Vector3(0, 0.6, 0), Color(0.75, 0.88, 1.0), 1.4, 12.0, 0.03, 14.0)

	# Escritorios con monitores CRT junto al muro sur
	var msgs := ["ACCESO DENEGADO", "ERROR 0x0000DEAD", "¿HAY ALGUIEN AHÍ?", "SISTEMA COMPROMETIDO", "C:\\> _", "RESPALDO 3%"]
	var mi := 0
	for s: float in [-1.0, 1.0]:
		var xx := 7.0
		while xx < 25.0:
			var dp := o + Vector3(s * xx, 0, hz - 2.0)
			_blk(dp + Vector3(0, 0.75, 0), Vector3(2.4, 0.06, 1.0), m_metal_light)
			for lx: float in [-1.1, 1.1]:
				_blk(dp + Vector3(lx, 0.37, 0), Vector3(0.06, 0.74, 0.9), m_metal)
			_wc(Vector3(2.4, 0.8, 1.0), Transform3D(Basis.IDENTITY, dp + Vector3(0, 0.4, 0)))
			for mon: float in [-0.6, 0.6]:
				var mp := dp + Vector3(mon, 1.03, 0.05)
				_blk(mp, Vector3(0.55, 0.45, 0.5), m_concrete_dark)
				var working := rng.randf() < 0.55
				_blk(mp + Vector3(0, 0, -0.255), Vector3(0.45, 0.35, 0.02), m_screen if working else m_glass)
				if working and rng.randf() < 0.6:
					_lbl(zone, msgs[mi % msgs.size()], mp + Vector3(0, 0.02, -0.27), 180.0, 16, Color(0.6, 1.0, 0.7), false, 0.0035)
					mi += 1
			xx += 3.2
	# Sillas de oficina y papeles
	for q in 14:
		var p := o + Vector3(rng.randf_range(-18, 18), 0, rng.randf_range(-10, 20))
		var tip := rng.randf() < 0.4
		_cy(p + Vector3(0, 0.25, 0), 0.3, 0.06, m_metal, Vector3(90 if tip else 0, 0, 0))
		_blk(p + Vector3(0, 0.5 if not tip else 0.3, 0), Vector3(0.5, 0.08, 0.5), m_tire, Vector3(80 if tip else 0, rng.randf_range(0, 360), 0))
	for q in 120:
		var p := o + Vector3(rng.randf_range(-hx + 1, hx - 1), 0.035, rng.randf_range(-hz + 1, hz - 1))
		_mm_add(_ub(m_paper), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(0.21, 0.004, 0.29)), p))

	# Atrio exterior con monolito y autos
	var fc := Vector3(225, 0, -45)
	_blk(fc + Vector3(0, 1.3, 9.5), Vector3(8.0, 2.6, 0.8), m_concrete_dark, Vector3.ZERO, true)
	_lbl(zone, "CENTRO DE CÓMPUTO", fc + Vector3(0, 1.6, 9.92), 0.0, 52, Color(0.75, 0.85, 0.9))
	_lbl(zone, "CENTRO DE CÓMPUTO", fc + Vector3(0, 1.6, 9.08), 180.0, 52, Color(0.75, 0.85, 0.9))
	_car(zone, fc + Vector3(-5, 0, 8), 70.0, 0.0, Color(0.15, 0.2, 0.22), false)
	_car(zone, fc + Vector3(7, 0, -4), -20.0, 180.0, Color(0.5, 0.5, 0.5), true)
	_end_zone()


func _rack(pos: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	_mm_add(_ub(m_rack), Transform3D(b * Basis.from_scale(Vector3(0.8, 2.2, 1.1)), pos + Vector3(0, 1.1, 0)))
	_mm_add(_ub(m_metal), Transform3D(b * Basis.from_scale(Vector3(0.7, 2.0, 0.02)), pos + b * Vector3(0, 1.1, 0.56)))
	var led := _ub(m_led)
	var palette := [Color(0.1, 1.0, 0.3), Color(0.1, 1.0, 0.3), Color(0.1, 1.0, 0.3), Color(1.0, 0.6, 0.05), Color(1.0, 0.1, 0.05), Color(0.2, 0.6, 1.0)]
	for row in 12:
		for col in 2:
			if rng.randf() < 0.2:
				continue
			var c: Color = palette[rng.randi() % palette.size()]
			_mmc_add(led, Transform3D(b * Basis.from_scale(Vector3(0.035, 0.018, 0.012)), pos + b * Vector3(-0.27 + col * 0.07, 0.25 + row * 0.15, 0.575)), c)


func _sparks(parent: Node3D, pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = 28
	p.lifetime = 1.8
	p.explosiveness = 0.9
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(3.0, 2.4, 1.2)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	parent.add_child(p)
	_omni(parent, pos + Vector3(0, 0.3, 0), Color(0.7, 0.85, 1.0), 1.5, 5.0, 0.2, 25.0)


# ================================================================ laboratorio

func _make_lab() -> void:
	var zone := _begin_zone("Laboratorio")
	var o := LAB
	var R := 26.0
	var H := 13.0
	var N := 36
	_reserve(Vector2(o.x, o.z), R + 4.0)

	_mm_add(_uc(m_labtile, 48), Transform3D(Basis.from_scale(Vector3(R * 2.0, 0.06, R * 2.0)), o))

	# Muro circular con puerta al sur
	var seg := 2.0 * R * sin(PI / N) + 0.35
	for i in N:
		var a := TAU * (float(i) + 0.5) / N
		var dir := Vector3(sin(a), 0, cos(a))
		var rib_a := TAU * float(i) / N
		if absf(wrapf(rib_a, -PI, PI)) > 0.15:
			_blk(o + Vector3(sin(rib_a), 0, cos(rib_a)) * (R + 1.3) + Vector3(0, (H + 1.0) * 0.5, 0), Vector3(0.8, H + 1.0, 1.6), m_concrete_dark, Vector3(0, rad_to_deg(rib_a), 0))
		if absf(wrapf(a, -PI, PI)) < 0.1:
			continue
		_blk(o + dir * (R + 0.6) + Vector3(0, H * 0.5, 0), Vector3(seg, H, 1.2), m_white_lab, Vector3(0, rad_to_deg(a), 0), true)
		# Tuberías horizontales
		var a2 := TAU * (float(i) + 1.5) / N
		if absf(wrapf(a2, -PI, PI)) >= 0.1:
			for py: float in [2.5, 9.5]:
				_rod(o + dir * (R - 0.5) + Vector3(0, py, 0), o + Vector3(sin(a2), 0, cos(a2)) * (R - 0.5) + Vector3(0, py, 0), 0.18, m_metal, 8)
		if i % 2 == 0:
			_cy(o + dir * (R - 0.45) + Vector3(0, H * 0.5, 0), 0.14, H, m_metal_light, Vector3.ZERO, 8)
	_blk(o + Vector3(0, 8.0 + (H - 8.0) * 0.5, R + 0.6), Vector3(9.6, H - 8.0, 1.2), m_white_lab, Vector3.ZERO, true)
	for q in 8:
		var hm: StandardMaterial3D = m_hazard_y if q % 2 == 0 else m_hazard_k
		_blk(o + Vector3(-4.2 + q * 1.2, 7.7, R + 1.25), Vector3(1.2, 0.6, 0.1), hm, Vector3(0, 0, 35))
	_lbl(zone, "LABORATORIO DE\nBIOGENÉTICA", o + Vector3(0, 10.7, R + 1.25), 0.0, 52, Color(0.85, 0.9, 0.85))
	_lbl(zone, "PELIGRO BIOLÓGICO · NIVEL 4", o + Vector3(0, 8.85, R + 1.25), 0.0, 26, Color(0.95, 0.75, 0.1))

	# Techo en anillo con tragaluz central
	for i in N:
		if rng.randf() < 0.14:
			continue
		var a := TAU * (float(i) + 0.5) / N
		var yaw := Vector3(0, rad_to_deg(a), 0)
		var dir := Vector3(sin(a), 0, cos(a))
		_blk(o + dir * 13.25 + Vector3(0, H + 0.25, 0), Vector3(2.45, 0.5, 8.5), m_white_lab, yaw, true)
		_blk(o + dir * 22.0 + Vector3(0, H + 0.25, 0), Vector3(4.5, 0.5, 9.2), m_white_lab, yaw, true)
	for i in 24:
		var a := TAU * float(i) / 24.0
		_blk(o + Vector3(sin(a), 0, cos(a)) * 9.0 + Vector3(0, H + 0.6, 0), Vector3(2.5, 0.35, 0.35), m_metal, Vector3(0, rad_to_deg(a), 0))
	var sky := SpotLight3D.new()
	sky.position = o + Vector3(0, H + 6.0, 0)
	sky.rotation_degrees = Vector3(-90, 0, 0)
	sky.light_color = Color(0.75, 1.0, 0.85)
	sky.light_energy = 3.0
	sky.spot_range = 26.0
	sky.spot_angle = 28.0
	sky.light_volumetric_fog_energy = 3.0
	zone.add_child(sky)

	# Franja de peligro en el piso
	for i in 72:
		var a := TAU * float(i) / 72.0
		var hm: StandardMaterial3D = m_hazard_y if i % 2 == 0 else m_hazard_k
		_blk(o + Vector3(sin(a), 0, cos(a)) * 17.0 + Vector3(0, 0.035, 0), Vector3(1.48, 0.02, 0.7), hm, Vector3(0, rad_to_deg(a), 0))

	# Cápsulas de contención alrededor
	var angs := [30, 60, 90, 120, 150, 210, 240, 270, 300, 330]
	var broken := [60, 210, 300]
	var n := 1
	for ad in angs:
		var a := deg_to_rad(float(ad))
		var cp := o + Vector3(sin(a), 0, cos(a)) * 21.0
		var variant := n % 3
		_capsule(zone, cp, o, 1.0, ad in broken, variant, "ESPÉCIMEN %02d" % n, n % 4 == 0)
		n += 1
	# Cápsula gigante (vacía: lo que había adentro escapó)
	_capsule(zone, o + Vector3(0, 0, -20.0), o, 2.0, true, -1, "ESPÉCIMEN Ω-01 · CONTENCIÓN FALLIDA", false)

	# Mesas de laboratorio, camillas y monitores
	for q in 7:
		var a := rng.randf_range(0.5, TAU - 0.5)
		var r := rng.randf_range(11.0, 14.5)
		var p := o + Vector3(sin(a) * r, 0, cos(a) * r)
		var yaw := rad_to_deg(a) + 90.0
		if rng.randf() < 0.4:
			_blk(p + Vector3(0, 0.6, 0), Vector3(3.0, 1.2, 0.08), m_metal_light, Vector3(0, yaw, rng.randf_range(-10, 10)), true)
			_blk(p + Vector3(0, 0.45, 0.6), Vector3(3.0, 0.9, 0.06), m_white_lab, Vector3(80, yaw, 0))
		else:
			_blk(p + Vector3(0, 0.92, 0), Vector3(3.0, 0.06, 1.2), m_white_lab, Vector3(0, yaw, 0))
			_blk(p + Vector3(0, 0.45, 0), Vector3(2.8, 0.9, 1.0), m_metal_light, Vector3(0, yaw, 0), true)
			for e in 3:
				var bp := p + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(-1.0 + e * 1.0, 1.08, 0)
				_cy(bp, 0.08, 0.28, m_glass_clear, Vector3(0, 0, 0 if rng.randf() < 0.6 else 90))
	for q in 3:
		var p := o + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-6, 10))
		var yaw := rng.randf_range(0, 360)
		_blk(p + Vector3(0, 0.75, 0), Vector3(0.8, 0.08, 2.0), m_metal_light, Vector3(0, yaw, rng.randf_range(-6, 6)))
		_blk(p + Vector3(0, 0.82, 0), Vector3(0.7, 0.06, 1.8), m_paper, Vector3(0, yaw, 0))
	for q in 80:
		var p := o + Vector3(rng.randf_range(-R, R), 0.04, rng.randf_range(-R, R))
		if Vector2(p.x - o.x, p.z - o.z).length() > R - 1.0:
			continue
		_mm_add(_ub(m_glass_clear), Transform3D(_rb(Vector3(rng.randf_range(-90, 90), rng.randf_range(0, 360), 0)) * Basis.from_scale(Vector3(rng.randf_range(0.05, 0.3), 0.01, rng.randf_range(0.05, 0.3))), p))
	# Fluorescentes parpadeantes
	for q in 3:
		var a := TAU * (float(q) + 0.3) / 3.0
		var lp := o + Vector3(sin(a) * 18.0, H - 0.4, cos(a) * 18.0)
		_blk(lp, Vector3(2.4, 0.08, 0.3), m_panel_light, Vector3(0, rad_to_deg(a), 0))
		_omni(zone, lp - Vector3(0, 0.6, 0), Color(0.8, 1.0, 0.88), 1.6, 14.0, 0.06, 18.0)

	# Retén militar en la entrada
	var gp := Vector3(170, 0, -244)
	for s: float in [-1.0, 1.0]:
		_sandbag_wall(gp + Vector3(s * 6.5, 0, 2.0), 90.0 + s * 20.0, 6.0)
	_sandbag_wall(gp + Vector3(9.0, 0, -6.0), 0.0, 4.0)
	var tent := gp + Vector3(-8.0, 0, -5.0)
	_mm_add(_uc(m_canvas, 3), Transform3D(_rb(Vector3(0, 90, 90)) * Basis.from_scale(Vector3(4.2, 6.0, 4.2)), tent + Vector3(0, 1.05, 0)))
	_wc(Vector3(6.0, 2.0, 3.6), Transform3D(Basis.IDENTITY, tent + Vector3(0, 1.0, 0)))
	var sg := gp + Vector3(-4.2, 0, 10.0)
	_blk(sg + Vector3(0, 1.6, 0), Vector3(5.5, 1.4, 0.1), m_hazard_y)
	_cy(sg + Vector3(-2.4, 1.0, 0), 0.06, 2.0, m_iron)
	_cy(sg + Vector3(2.4, 1.0, 0), 0.06, 2.0, m_iron)
	_wc(Vector3(5.5, 2.4, 0.3), Transform3D(Basis.IDENTITY, sg + Vector3(0, 1.2, 0)))
	_lbl(zone, "ZONA DE CUARENTENA", sg + Vector3(0, 1.8, 0.06), 0.0, 44, Color(0.05, 0.05, 0.05))
	_lbl(zone, "NO PASAR", sg + Vector3(0, 1.3, 0.06), 0.0, 44, Color(0.6, 0.05, 0.03))
	_cy(gp + Vector3(6.0, 1.5, 6.0), 0.08, 3.0, m_iron)
	_blk(gp + Vector3(6.0, 3.1, 6.0), Vector3(0.9, 0.5, 0.3), m_iron, Vector3(-25, 200, 0))
	_omni(zone, gp + Vector3(5.8, 2.8, 5.4), Color(0.95, 0.97, 1.0), 2.4, 14.0, 0.01)
	for q in 6:
		var cp := gp + Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
		_cy(cp + Vector3(0, 0.45, 0), 0.32, 0.9, m_hazard_y if q % 2 == 0 else m_metal, Vector3(0 if rng.randf() < 0.6 else 90, 0, 0), 12, 1.0, true)
	_end_zone()


func _sandbag_wall(c: Vector3, yaw: float, length: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var n := int(length / 0.85)
	for row in 3:
		for k in n:
			var x := -length * 0.5 + (float(k) + 0.5 + (0.5 if row % 2 == 1 else 0.0)) * 0.85
			if x > length * 0.5:
				continue
			_sp(c + b * Vector3(x, 0.17 + row * 0.3, 0), Vector3(0.9, 0.34, 0.55), m_sandbag, Vector3(0, yaw + rng.randf_range(-8, 8), 0), 8)
	_wc(Vector3(length, 1.0, 0.7), Transform3D(b, c + Vector3(0, 0.5, 0)))


## Cápsula de contención. `s` escala, `variant` -1 = vacía.
func _capsule(zone: Node3D, pos: Vector3, look: Vector3, s: float, broken: bool, variant: int, label: String, amber: bool) -> void:
	var r := 1.2 * s
	var h := 4.4 * s
	var base_h := 0.9 * s
	var to_c := (look - pos)
	to_c.y = 0.0
	to_c = to_c.normalized()
	var yaw := rad_to_deg(atan2(to_c.x, to_c.z))
	_cy(pos + Vector3(0, base_h * 0.5, 0), r * 1.3, base_h, m_metal, Vector3.ZERO, 20)
	_cy(pos + Vector3(0, base_h + 0.02, 0), r * 1.08, 0.06, m_cyan if not broken else m_glass, Vector3.ZERO, 20)
	_cy(pos + Vector3(0, base_h + h + 0.45 * s, 0), r * 1.3, 0.9 * s, m_metal, Vector3.ZERO, 20)
	_sp(pos + Vector3(0, base_h + h + 0.9 * s, 0), Vector3(r * 1.6, r * 0.8, r * 1.6), m_metal_light, Vector3.ZERO, 16)
	# Tuberías desde la tapa hacia el muro
	for e: float in [-0.5, 0.5]:
		var side := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(e * r, 0, 0)
		var top := pos + side + Vector3(0, base_h + h + 0.9 * s, 0)
		_rod(top, top - to_c * 4.0 * s + Vector3(0, 3.0 * s, 0), 0.12 * s, m_metal, 8)
	# Soportes traseros
	for e: float in [-0.7, 0.7]:
		var off := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(e * r, 0, -r * 0.85)
		_cy(pos + off + Vector3(0, base_h + h * 0.5, 0), 0.08 * s, h, m_metal_light, Vector3.ZERO, 6)
	_lbl(zone, label, pos + Vector3(0, base_h * 0.55, 0) + to_c * (r * 1.31), yaw, int(26 * minf(s, 1.5)), Color(0.85, 0.9, 0.85))
	_wc(Vector3(r * 2.4, base_h + h + 1.0 * s, r * 2.4), Transform3D(Basis.IDENTITY, pos + Vector3(0, (base_h + h + 1.0 * s) * 0.5, 0)))
	var center := pos + Vector3(0, base_h + h * 0.5, 0)
	if not broken:
		_mm_add(_uc(m_fluid_amber if amber else m_fluid, 24), Transform3D(Basis.from_scale(Vector3(r * 2.0, h, r * 2.0)), center))
		for q in 3:
			_cy(pos + Vector3(0, base_h + h * (0.25 + q * 0.25), 0), r * 1.04, 0.08, m_metal_light, Vector3.ZERO, 20)
		if variant >= 0:
			_specimen(zone, center, yaw, s, variant, false)
		_bubbles(zone, pos + Vector3(0, base_h, 0), r, h)
		var lc := Color(1.0, 0.65, 0.2) if amber else Color(0.3, 1.0, 0.5)
		_omni(zone, pos + Vector3(0, 1.5, 0) + to_c * (r + 0.6), lc, 1.1, 7.0)
	else:
		# Vidrio roto en dientes y líquido derramado
		for q in 16:
			var a := TAU * float(q) / 16.0
			var hh := rng.randf_range(0.2, 1.0) * h * (0.35 if rng.randf() < 0.7 else 0.8)
			var sp := pos + Vector3(cos(a) * r, base_h + hh * 0.5, sin(a) * r)
			_blk(sp, Vector3(TAU * r / 16.0, hh, 0.03), m_glass_clear, Vector3(rng.randf_range(-8, 8), -rad_to_deg(a) + 90.0, rng.randf_range(-6, 6)))
		var spill_r := rng.randf_range(2.2, 3.4) * s
		_mm_add(_uc(m_spill, 24), Transform3D(Basis.from_scale(Vector3(spill_r * 2.0, 0.02, spill_r * 1.4)), pos + to_c * (r + spill_r * 0.5) + Vector3(0, 0.04, 0)))
		for q in 24:
			var gp := pos + to_c * rng.randf_range(r, r + spill_r * 1.5) + Vector3(rng.randf_range(-2, 2) * s, 0.03, rng.randf_range(-2, 2) * s)
			_mm_add(_ub(m_glass_clear), Transform3D(_rb(Vector3(0, rng.randf_range(0, 360), 0)) * Basis.from_scale(Vector3(rng.randf_range(0.1, 0.5), 0.02, rng.randf_range(0.1, 0.4))), gp))
		if variant >= 0:
			_specimen(zone, pos + to_c * (r + 1.6) + Vector3(0, 0.45 * s, 0), yaw + rng.randf_range(-40, 40), s, variant, true)
		_omni(zone, pos + Vector3(0, 1.2, 0) + to_c * (r + 1.0), Color(0.3, 1.0, 0.5), 0.9 * s, 6.0 * s, 0.05, 8.0)


## Criatura encapsulada hecha de primitivas.
func _specimen(zone: Node3D, pos: Vector3, yaw: float, s: float, variant: int, lying: bool) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees = Vector3(-80 if lying else 0, yaw, 0)
	holder.scale = Vector3.ONE * s
	zone.add_child(holder)
	var flesh: Material = m_flesh if variant != 1 else m_flesh_dark
	var sph := _us(flesh, 14)
	var cyl := _uc(flesh, 8, 0.6)
	var eye := _us(m_eye, 8)
	match variant:
		0:
			# Humanoide en posición fetal, cráneo deforme
			_spart(holder, sph, Vector3(0, 0, 0), Vector3(0.75, 1.05, 0.6), Vector3(18, 0, 0))
			_spart(holder, sph, Vector3(0, 0.78, 0.2), Vector3(0.62, 0.78, 0.66), Vector3(-20, 0, 0))
			for sx: float in [-1.0, 1.0]:
				_spart(holder, cyl, Vector3(sx * 0.38, 0.25, 0.22), Vector3(0.16, 0.7, 0.16), Vector3(-60, 0, sx * 20))
				_spart(holder, cyl, Vector3(sx * 0.3, 0.15, 0.55), Vector3(0.13, 0.6, 0.13), Vector3(-150, 0, sx * -10))
				_spart(holder, cyl, Vector3(sx * 0.22, -0.45, 0.3), Vector3(0.2, 0.75, 0.2), Vector3(-75, 0, 0))
				_spart(holder, cyl, Vector3(sx * 0.22, -0.75, 0.25), Vector3(0.16, 0.7, 0.16), Vector3(20, 0, 0))
				_spart(holder, eye, Vector3(sx * 0.15, 0.85, 0.5), Vector3(0.09, 0.09, 0.06))
			_spart(holder, _uc(m_flesh_dark, 6), Vector3(0, -0.2, -0.45), Vector3(0.06, 1.8, 0.06), Vector3(30, 0, 0))
		1:
			# Bulbo con tentáculos
			_spart(holder, sph, Vector3(0, 0.45, 0), Vector3(0.95, 1.15, 0.95))
			_spart(holder, eye, Vector3(0, 0.55, 0.44), Vector3(0.3, 0.3, 0.14))
			for q in 8:
				var a := TAU * float(q) / 8.0
				var p := Vector3(cos(a) * 0.32, 0.0, sin(a) * 0.32)
				var tilt := Vector3(rad_to_deg(sin(a)) * 0.4, 0, -rad_to_deg(cos(a)) * 0.4)
				for seg in 3:
					_spart(holder, cyl, p + Vector3(0, -0.35 - seg * 0.5, 0) * (1.0 + seg * 0.1), Vector3(0.14 - seg * 0.03, 0.55, 0.14 - seg * 0.03), tilt * (1.0 + seg * 0.8))
		_:
			# Cuerpo largo con muchos brazos
			_spart(holder, sph, Vector3(0, 0, 0), Vector3(0.5, 1.7, 0.45))
			_spart(holder, sph, Vector3(0, 1.0, 0.1), Vector3(0.36, 0.6, 0.55), Vector3(-30, 0, 0))
			_spart(holder, _ub(m_flesh_dark), Vector3(0, 0.82, 0.38), Vector3(0.2, 0.06, 0.3), Vector3(25, 0, 0))
			for q in 6:
				var sx := -1.0 if q % 2 == 0 else 1.0
				var yy := 0.5 - float(q / 2) * 0.45
				_spart(holder, cyl, Vector3(sx * 0.55, yy, 0.1), Vector3(0.07, 1.3, 0.07), Vector3(-20, 0, sx * (60 + q * 6)))
			for e in 3:
				_spart(holder, eye, Vector3(-0.1 + e * 0.1, 1.1, 0.37), Vector3(0.05, 0.05, 0.04))


func _spart(holder: Node3D, mesh: Mesh, p: Vector3, size: Vector3, rot := Vector3.ZERO) -> void:
	_mi(holder, mesh, Transform3D(_rb(rot) * Basis.from_scale(size), p))


func _bubbles(parent: Node3D, pos: Vector3, r: float, h: float) -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = 16
	p.lifetime = h / 0.9
	p.preprocess = p.lifetime
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-r, -0.5, -r), Vector3(r * 2.0, h + 1.0, r * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(r * 0.6, 0.05, r * 0.6)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0, 0.1, 0)
	pm.scale_min = 0.04
	pm.scale_max = 0.12
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = m_bubble
	p.draw_pass_1 = sm
	parent.add_child(p)


# ================================================================ arena final

func _make_final_arena() -> void:
	var zone := _begin_zone("AulaMagna")
	var o := FINAL
	var R0 := 33.0
	var K := 7
	var dr := 2.2
	var dh := 1.1
	var N := 56
	var gate_half := 0.2
	_reserve(Vector2(o.x, o.z), 52.0)

	_mm_add(_uc(m_stoneslab, 64), Transform3D(Basis.from_scale(Vector3(R0 * 2.0 + 0.5, 0.06, R0 * 2.0 + 0.5)), o))

	# Gradas en anillo (anfiteatro)
	for k in K:
		var rm := R0 + dr * (float(k) + 0.5)
		var top := dh * float(k + 1)
		var segl := 2.0 * rm * sin(PI / N) + 0.25
		for i in N:
			var a := TAU * (float(i) + 0.5) / N
			if absf(wrapf(a, -PI, PI)) < gate_half:
				continue
			var dir := Vector3(sin(a), 0, cos(a))
			var yaw := Vector3(0, rad_to_deg(a), 0)
			if k >= 3 and rng.randf() < 0.08:
				var low := top - dh * rng.randf_range(1.0, 2.5)
				_blk(o + dir * rm + Vector3(0, low * 0.5, 0), Vector3(segl, low, dr + 0.02), m_stone, yaw, true)
				_chunk(o + dir * (rm - dr) + Vector3(0, top - dh * 2.0, 0), 0.5, 1.5)
				continue
			_blk(o + dir * rm + Vector3(0, top * 0.5, 0), Vector3(segl, top, dr + 0.02), m_stone, yaw, true)
	var outer := R0 + dr * K
	var top_h := dh * K

	# Columnata sobre la última grada
	var nc := 28
	var prev_top := Vector3.INF
	for i in nc:
		var a := TAU * (float(i) + 0.5) / nc
		if absf(wrapf(a, -PI, PI)) < gate_half + 0.1:
			prev_top = Vector3.INF
			continue
		var cp := o + Vector3(sin(a), 0, cos(a)) * (outer - 1.0)
		var ch := 12.0
		if rng.randf() < 0.3:
			ch = rng.randf_range(3.0, 8.0)
			_cy(o + Vector3(sin(a), 0, cos(a)) * (outer - 5.0) + Vector3(0, top_h - dh * 2.0 + 0.9, 0), 0.9, 4.0, m_stone_light, Vector3(0, rad_to_deg(a) + 90.0, 90), 14)
		_cy(cp + Vector3(0, top_h + ch * 0.5, 0), 0.9, ch, m_stone_light, Vector3.ZERO, 14, 0.92)
		var t := cp + Vector3(0, top_h + ch, 0)
		if ch >= 12.0 and prev_top != Vector3.INF:
			var d := t - prev_top
			_blk((t + prev_top) * 0.5 + Vector3(0, 0.6, 0), Vector3(d.length() + 1.6, 1.2, 1.8), m_stone_light, Vector3(0, rad_to_deg(atan2(d.x, d.z)) + 90.0, 0))
		prev_top = t if ch >= 12.0 else Vector3.INF

	# Túnel de entrada con portón sellado
	var gz := 47.0
	for s: float in [-1.0, 1.0]:
		_blk(o + Vector3(s * 8.1, 4.6, 40.9), Vector3(3.0, 9.2, 16.2), m_stone, Vector3.ZERO, true)
	_blk(o + Vector3(0, 9.8, 41.5), Vector3(16.4, 1.4, 14.0), m_stone, Vector3.ZERO, true)
	_blk(o + Vector3(0, 11.7, 48.4), Vector3(17.0, 2.6, 1.4), m_stone_light)
	_blk(o + Vector3(0, 11.7, 33.6), Vector3(17.0, 2.6, 1.4), m_stone_light)
	_lbl(zone, "AULA MAGNA", o + Vector3(0, 11.7, 49.12), 0.0, 130, Color(0.85, 0.78, 0.6))
	_lbl(zone, "SAPIENTIA · VERITAS · TEMPESTAS", o + Vector3(0, 11.7, 32.88), 180.0, 60, Color(0.85, 0.78, 0.6))
	for s: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "GateLeaf" + ("L" if s < 0.0 else "R")
		pivot.position = o + Vector3(s * 6.55, 0, gz)
		zone.add_child(pivot)
		_box(pivot, Vector3(6.5, 9.0, 0.5), _xf(Vector3(-s * 3.25, 4.5, 0)), m_iron)
		for q in 4:
			_box(pivot, Vector3(6.5, 0.25, 0.6), _xf(Vector3(-s * 3.25, 1.2 + q * 2.2, 0)), m_bronze)
		for q in 6:
			for e in 3:
				var stud := SphereMesh.new()
				stud.radius = 0.12
				stud.height = 0.24
				stud.radial_segments = 6
				stud.rings = 3
				_mi(pivot, stud, _xf(Vector3(-s * (1.0 + e * 2.0), 0.7 + q * 1.5, 0.3)), m_gold)
		_gate_pivots.append(pivot)
	_gate_body = StaticBody3D.new()
	_gate_body.name = "FinalGateBody"
	var gcs := CollisionShape3D.new()
	var gbx := BoxShape3D.new()
	gbx.size = Vector3(13.2, 9.0, 0.8)
	gcs.shape = gbx
	_gate_body.add_child(gcs)
	_gate_body.position = o + Vector3(0, 4.5, gz)
	zone.add_child(_gate_body)
	_gate_seal = Node3D.new()
	_gate_seal.name = "Seal"
	_gate_seal.position = o + Vector3(0, 4.8, gz + 0.45)
	zone.add_child(_gate_seal)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.6
	tm.outer_radius = 1.85
	tm.rings = 32
	tm.ring_segments = 8
	tm.material = m_seal
	ring.mesh = tm
	ring.rotation_degrees = Vector3(90, 0, 0)
	_gate_seal.add_child(ring)
	for q in 3:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 3.2, 0.1)
		bm.material = m_seal
		bar.mesh = bm
		bar.rotation_degrees = Vector3(0, 0, q * 60.0)
		_gate_seal.add_child(bar)
	_lbl(_gate_seal, "Solo quien reúna las cuatro piezas de la llave\npodrá cruzar este umbral", Vector3(0, -3.0, 0.05), 0.0, 28, Color(1.0, 0.55, 0.3), false)
	_omni(_gate_seal, Vector3(0, 0, 1.2), Color(1.0, 0.3, 0.1), 2.5, 10.0, 0.0, 2.0)

	# Braseros
	for i in 6:
		var a := deg_to_rad(30.0 + i * 60.0)
		_brazier(zone, o + Vector3(sin(a), 0, cos(a)) * 29.0)
	for s: float in [-1.0, 1.0]:
		_brazier(zone, o + Vector3(s * 10.5, 0, 52.0))

	# Estatuas de catedráticos flanqueando la entrada
	_scholar_statue(o + Vector3(-15.0, 0, 55.0), 200.0, false)
	_scholar_statue(o + Vector3(15.0, 0, 55.0), 160.0, true)

	# Columnas rotas a lo largo de la avenida de acceso
	for k in 6:
		var z := -230.0 - k * 8.0
		for s: float in [-1.0, 1.0]:
			var cp := Vector3(s * 10.0, 0, z)
			_blk(cp + Vector3(0, 0.35, 0), Vector3(2.0, 0.7, 2.0), m_stone_light, Vector3.ZERO, true)
			var roll := rng.randf()
			if roll < 0.25:
				_cy(cp + Vector3(0, 1.5, 0), 0.75, 2.2, m_stone_light, Vector3.ZERO, 14, 1.0, true)
				_cy(cp + Vector3(-s * 4.5, 0.75, rng.randf_range(-2, 2)), 0.75, 7.0, m_stone_light, Vector3(0, rng.randf_range(60, 120), 90), 14, 1.0, true)
			else:
				var hh := 9.0 if roll > 0.5 else rng.randf_range(4.0, 7.0)
				_cy(cp + Vector3(0, 0.7 + hh * 0.5, 0), 0.75, hh, m_stone_light, Vector3.ZERO, 14, 0.9, true)

	# Torre del Reloj
	var tw := o + Vector3(0, 0, -64)
	_blk(tw + Vector3(0, 20, 0), Vector3(12, 40, 12), m_stone_light, Vector3.ZERO, true)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			_blk(tw + Vector3(cx * 6.2, 21, cz * 6.2), Vector3(2.0, 42, 2.0), m_stone)
	_blk(tw + Vector3(0, 44, 0), Vector3(13.5, 8, 13.5), m_stone)
	for f in 4:
		var fb := Basis(Vector3.UP, f * PI * 0.5)
		var fc := tw + fb * Vector3(0, 44, 6.8)
		_mm_add(_uc(m_clock, 32), Transform3D(fb * _rb(Vector3(90, 0, 0)) * Basis.from_scale(Vector3(9.0, 0.2, 9.0)), fc))
		_mm_add(_uc(m_bronze, 32), Transform3D(fb * _rb(Vector3(90, 0, 0)) * Basis.from_scale(Vector3(9.6, 0.12, 9.6)), fc - fb * Vector3(0, 0, 0.05)))
		for hmark in 12:
			var ha := TAU * hmark / 12.0
			_mm_add(_ub(m_iron), Transform3D(fb * Basis(Vector3.BACK, -ha) * Basis.from_scale(Vector3(0.18, 0.7, 0.1)), fc + fb * (Vector3(sin(ha), cos(ha), 0) * 3.8 + Vector3(0, 0, 0.12))))
		var a_h := deg_to_rad(-1.0)
		var a_m := deg_to_rad(-12.0)
		_mm_add(_ub(m_iron), Transform3D(fb * Basis(Vector3.BACK, a_h) * Basis.from_scale(Vector3(0.3, 2.4, 0.1)), fc + fb * (Vector3(-sin(a_h), cos(a_h), 0) * 1.1 + Vector3(0, 0, 0.18))))
		_mm_add(_ub(m_iron), Transform3D(fb * Basis(Vector3.BACK, a_m) * Basis.from_scale(Vector3(0.2, 3.4, 0.1)), fc + fb * (Vector3(-sin(a_m), cos(a_m), 0) * 1.6 + Vector3(0, 0, 0.22))))
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			if cx > 0.0 and cz > 0.0:
				_blk(tw + Vector3(cx * 5.5, 50.5, cz * 5.5), Vector3(2.2, 5.0, 2.2), m_stone_light)
				continue
			_blk(tw + Vector3(cx * 5.5, 52.5, cz * 5.5), Vector3(2.2, 9.0, 2.2), m_stone_light)
	_blk(tw + Vector3(0, 57.3, 0), Vector3(13.5, 0.8, 13.5), m_stone)
	_cy(tw + Vector3(0, 51.5, 0), 2.0, 3.0, m_bronze, Vector3.ZERO, 16, 0.55)
	_mm_add(_uc(m_iron, 4, 0.0), Transform3D(_rb(Vector3(0, 45, 0)) * Basis.from_scale(Vector3(19, 15, 19)), tw + Vector3(0, 65.2, 0)))
	_cy(tw + Vector3(0, 76.5, 0), 0.12, 8.0, m_iron, Vector3.ZERO, 6, 0.3)
	_sp(tw + Vector3(0, 80.8, 0), Vector3(0.9, 0.9, 0.9), m_beacon)
	_omni(zone, tw + Vector3(0, 81.5, 0), Color(1.0, 0.1, 0.05), 4.0, 35.0)
	_omni(zone, tw + Vector3(0, 44, 10.0), Color(1.0, 0.85, 0.6), 2.0, 16.0)
	_mound(tw + Vector3(8, 0, 8), 7.0, 2.0)
	for q in 20:
		_chunk(tw + Vector3(rng.randf_range(-10, 12), 0, rng.randf_range(-10, 12)), 0.4, 1.6)
	_end_zone()

	if not final_gate_locked:
		open_final_gate(true)


func _brazier(parent: Node3D, p: Vector3) -> void:
	_cy(p + Vector3(0, 0.7, 0), 0.3, 1.4, m_iron, Vector3.ZERO, 8, 0.7)
	_cy(p + Vector3(0, 1.6, 0), 0.9, 0.6, m_iron, Vector3.ZERO, 12, 1.0)
	_cy(p + Vector3(0, 0.08, 0), 0.7, 0.16, m_iron, Vector3.ZERO, 8)
	_wc(Vector3(1.4, 1.9, 1.4), Transform3D(Basis.IDENTITY, p + Vector3(0, 0.95, 0)))
	_fire(parent, p + Vector3(0, 1.9, 0), 0.9)


func _scholar_statue(p: Vector3, yaw: float, headless: bool) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var at := func(v: Vector3) -> Vector3: return p + b * v
	_blk(p + Vector3(0, 1.2, 0), Vector3(4.0, 2.4, 4.0), m_stone, Vector3(0, yaw, 0), true)
	_mm_add(_uc(m_stone_light, 14, 0.5), Transform3D(b * Basis.from_scale(Vector3(3.0, 6.5, 2.6)), at.call(Vector3(0, 5.65, 0))))
	_sp(at.call(Vector3(0, 8.8, 0)), Vector3(2.6, 1.3, 1.6), m_stone_light, Vector3(0, yaw, 0))
	if headless:
		_rebar(at.call(Vector3(0, 9.3, 0)), 3)
		_sp(p + Vector3(3.0, 0.6, 2.0), Vector3(1.2, 1.3, 1.2), m_stone_light)
		_mm_add(_uc(m_iron, 4, 0.0), Transform3D(_rb(Vector3(20, 45, 30)) * Basis.from_scale(Vector3(1.2, 0.5, 1.2)), p + Vector3(3.5, 0.6, 3.2)))
	else:
		_sp(at.call(Vector3(0, 9.9, 0.1)), Vector3(1.0, 1.25, 1.05), m_stone_light)
		_blk(at.call(Vector3(0, 10.65, 0.1)), Vector3(1.5, 0.12, 1.5), m_stone, Vector3(0, yaw + 45.0, 0))
	_blk(at.call(Vector3(0.7, 6.8, 1.1)), Vector3(1.6, 1.2, 0.35), m_stone, Vector3(-30, yaw, 0))
	_mm_add(_uc(m_stone_light, 8), Transform3D(b * _rb(Vector3(-60, 0, 10)) * Basis.from_scale(Vector3(0.5, 2.0, 0.5)), at.call(Vector3(0.9, 7.4, 0.5))))


# ================================================================ explanada

func _make_explanade() -> void:
	var zone := _begin_zone("Explanada")
	var c := Vector3(0, 0, -200)
	# Árbol de los Fundadores: enorme y muerto
	var th := 13.0
	_cy(c + Vector3(0, th * 0.5, 0), 1.3, th, m_wood, Vector3.ZERO, 10, 0.45, true)
	for q in 9:
		var by := rng.randf_range(th * 0.45, th * 0.95)
		var bl := rng.randf_range(4.5, 8.0)
		var bb := Basis(Vector3.UP, TAU * q / 9.0 + rng.randf_range(-0.2, 0.2)) * Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(35, 70)))
		var dir := bb * Vector3.UP
		var start := c + Vector3(0, by, 0)
		_mm_add(_uc(m_wood, 6, 0.3), Transform3D(bb * Basis.from_scale(Vector3(0.7, bl, 0.7)), start + dir * bl * 0.5))
		for e in 2:
			var sb := bb * Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(-45, 45))) * Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(-30, 30)))
			var sl := rng.randf_range(2.0, 3.5)
			var sp := start + dir * bl * rng.randf_range(0.5, 0.9)
			_mm_add(_uc(m_wood, 5, 0.25), Transform3D(sb * Basis.from_scale(Vector3(0.25, sl, 0.25)), sp + (sb * Vector3.UP) * sl * 0.5))
	for q in 7:
		var a := TAU * q / 7.0
		_blk(c + Vector3(sin(a), 0, cos(a)) * 1.6 + Vector3(0, 0.3, 0), Vector3(1.0, 0.6, 2.6), m_wood, Vector3(0, rad_to_deg(a), 0))
	# Banca circular
	for q in 20:
		var a := TAU * q / 20.0
		if rng.randf() < 0.15:
			continue
		_blk(c + Vector3(sin(a), 0, cos(a)) * 4.5 + Vector3(0, 0.25, 0), Vector3(1.5, 0.5, 0.6), m_stone_light, Vector3(0, rad_to_deg(a), 0), true)
	# Obelisco caído
	_blk(c + Vector3(13, 1.5, 6), Vector3(1.8, 3.0, 1.8), m_stone_light, Vector3.ZERO, true)
	_rebar(c + Vector3(13, 3.0, 6), 2)
	_blk(c + Vector3(17.0, 0.8, 12.0), Vector3(1.6, 1.6, 13.0), m_stone_light, Vector3(4, 25, 3), true)
	_lbl(zone, "A LOS FUNDADORES\nMCMLII", c + Vector3(13, 1.6, 6.92), 0.0, 30, Color(0.6, 0.58, 0.5))
	for q in 14:
		_chunk(c + Vector3(rng.randf_range(10, 22), 0, rng.randf_range(4, 18)), 0.2, 0.9)
	# Faroles alrededor
	for q in 8:
		var a := deg_to_rad([30.0, 60.0, 120.0, 150.0, 210.0, 240.0, 300.0, 330.0][q])
		_street_lamp(c + Vector3(sin(a), 0, cos(a)) * 24.0, rad_to_deg(a), 0 if q % 2 == 0 else 1)
	_car(zone, c + Vector3(-15, 0, 8), 120.0, 0.0, Color(0.6, 0.6, 0.6), true)
	_end_zone()


# ================================================================ estadio

func _make_stadium() -> void:
	var zone := _begin_zone("Estadio")
	var c := Vector3(-80, 0, -150)
	var fx := 32.0
	var fz := 20.0
	_reserve(Vector2(c.x, c.z), 36.0)
	_lawn(c, Vector2(fx * 2.0 + 4.0, fz * 2.0 + 4.0), 0.35, false, 0.8)
	# Líneas de cancha
	var lw := 0.15
	for s: float in [-1.0, 1.0]:
		_blk(c + Vector3(0, 0.03, s * fz), Vector3(fx * 2.0, 0.02, lw), m_line)
		_blk(c + Vector3(s * fx, 0.03, 0), Vector3(lw, 0.02, fz * 2.0), m_line)
		_blk(c + Vector3(s * (fx - 8.0), 0.03, 0), Vector3(lw, 0.02, 16.0), m_line)
		_blk(c + Vector3(s * (fx - 4.0), 0.03, 8.0), Vector3(8.0, 0.02, lw), m_line)
		_blk(c + Vector3(s * (fx - 4.0), 0.03, -8.0), Vector3(8.0, 0.02, lw), m_line)
		# Porterías (una derribada)
		var g := c + Vector3(s * fx, 0, 0)
		if s > 0.0:
			_blk(g + Vector3(0.3, 0.1, 0), Vector3(0.12, 0.12, 7.3), m_line)
			_blk(g + Vector3(1.6, 0.1, -3.6), Vector3(2.4, 0.12, 0.12), m_line, Vector3(0, 0, 70))
		else:
			for gz: float in [-3.65, 3.65]:
				_blk(g + Vector3(0, 1.22, gz), Vector3(0.12, 2.44, 0.12), m_line, Vector3.ZERO, true)
			_blk(g + Vector3(0, 2.44, 0), Vector3(0.12, 0.12, 7.4), m_line)
	_blk(c + Vector3(0, 0.03, 0), Vector3(lw, 0.02, fz * 2.0), m_line)
	for q in 32:
		var a := TAU * q / 32.0
		_blk(c + Vector3(sin(a) * 6.0, 0.03, cos(a) * 6.0), Vector3(1.2, 0.02, lw), m_line, Vector3(0, rad_to_deg(a), 0))
	# Gradas norte (completas) y sur (con dos tramos derrumbados)
	for s: float in [-1.0, 1.0]:
		for chunk in 6:
			var cx := -fx + 5.5 + chunk * 11.0
			if s > 0.0 and (chunk == 2 or chunk == 4):
				_mound(c + Vector3(cx, 0, s * (fz + 4.0)), 6.0, 1.6)
				continue
			for row in 6:
				var zz := s * (fz + 2.0 + row * 1.0)
				var hh := 0.5 * float(row + 1)
				_blk(c + Vector3(cx, hh * 0.5, zz), Vector3(11.02, hh, 1.0), m_concrete, Vector3.ZERO, row == 0)
			_wc(Vector3(11.0, 3.0, 6.0), Transform3D(Basis.IDENTITY, c + Vector3(cx, 1.5, s * (fz + 4.5))))
			_blk(c + Vector3(cx, 4.0, s * (fz + 7.6)), Vector3(11.0, 0.06, 0.06), m_iron)
		for q in 20:
			_chunk(c + Vector3(rng.randf_range(-fx, fx), 0, s * (fz + rng.randf_range(0.5, 2.0))), 0.15, 0.5)
	# Torres de iluminación (una encendida, una caída)
	var towers := [Vector3(-fx - 4, 0, -fz - 9), Vector3(fx + 4, 0, -fz - 9), Vector3(-fx - 4, 0, fz + 9), Vector3(fx + 4, 0, fz + 9)]
	for i in towers.size():
		var tp: Vector3 = c + towers[i]
		if i == 3:
			_cy(tp + Vector3(-8.0, 0.4, -6.0), 0.35, 22.0, m_iron, Vector3(0, -52, 90), 8)
			_blk(tp + Vector3(-17.0, 0.6, -13.0), Vector3(4.0, 2.5, 0.6), m_iron, Vector3(80, -52, 0))
			continue
		_cy(tp + Vector3(0, 11, 0), 0.35, 22.0, m_iron, Vector3.ZERO, 8, 0.7, true)
		var face := rad_to_deg(atan2(c.x - tp.x, c.z - tp.z))
		_blk(tp + Vector3(0, 22.5, 0), Vector3(4.0, 2.5, 0.6), m_iron, Vector3(-25, face, 0))
		var lit := i == 1
		_blk(tp + Vector3(0, 22.5, 0) + Basis(Vector3.UP, deg_to_rad(face)) * Vector3(0, 0, 0.32), Vector3(3.6, 2.1, 0.05), m_flood if lit else m_glass, Vector3(-25, face, 0))
		if lit:
			var sl := SpotLight3D.new()
			zone.add_child(sl)
			sl.look_at_from_position(tp + Vector3(0, 22, 0), c + Vector3(0, 0, 4), Vector3.UP)
			sl.light_color = Color(0.95, 0.95, 1.0)
			sl.light_energy = 6.0
			sl.spot_range = 70.0
			sl.spot_angle = 28.0
			sl.light_volumetric_fog_energy = 2.0
			sl.distance_fade_enabled = true
			sl.distance_fade_begin = 150.0
			sl.set_script(FLICKER)
			sl.set("base_energy", 6.0)
			sl.set("dropout_chance", 0.01)
			sl.set("amount", 0.05)
	# Marcador
	var sb := c + Vector3(0, 0, -fz - 14)
	for s: float in [-1.0, 1.0]:
		_blk(sb + Vector3(s * 5.0, 3.5, 0), Vector3(0.6, 7.0, 0.6), m_iron, Vector3.ZERO, true)
	_blk(sb + Vector3(0, 7.5, 0), Vector3(14.0, 4.0, 0.8), m_concrete_dark, Vector3(0, 0, 3))
	_lbl(zone, "LOCAL  0   ·   VISITA  3", sb + Vector3(0, 7.8, 0.42), 0.0, 70, Color(1.0, 0.45, 0.1), false)
	_fire(zone, c + Vector3(-12, 0.4, fz + 3.0), 1.0)
	_end_zone()


# ================================================================ estacionamiento

func _make_parking() -> void:
	var zone := _begin_zone("Estacionamiento")
	var c := Vector3(80, 0, -150)
	_reserve(Vector2(c.x, c.z), 34.0)
	_blk(c, Vector3(60, 0.06, 36), m_asphalt)
	var colors := [Color(0.5, 0.05, 0.05), Color(0.1, 0.15, 0.3), Color(0.6, 0.6, 0.62), Color(0.15, 0.15, 0.15), Color(0.7, 0.65, 0.4), Color(0.2, 0.3, 0.22)]
	for row: float in [-11.0, 11.0]:
		var x := -26.0
		while x < 27.0:
			if rng.randf() < 0.55:
				var roll := 0.0
				var r := rng.randf()
				if r < 0.1:
					roll = 180.0
				elif r < 0.18:
					roll = 90.0
				_car(zone, c + Vector3(x + rng.randf_range(-0.3, 0.3), 0, row + rng.randf_range(-0.6, 0.6)), 90.0 + rng.randf_range(-12, 12), roll, colors[rng.randi() % colors.size()], rng.randf() < 0.3)
			x += 2.8 * 2.0
	_car(zone, c + Vector3(-4, 0, 1), 35.0, 0.0, Color(0.1, 0.1, 0.1), true)
	_car(zone, c + Vector3(9, 0, -2), -150.0, 0.0, Color(0.4, 0.42, 0.45), false)
	_bus(zone, c + Vector3(20, 0, 2), -20.0)
	_fire(zone, c + Vector3(-4, 1.0, 1), 0.8)
	for q in 4:
		var lp := c + Vector3(-30.0 + q * 20.0, 0, 18.5 if q % 2 == 0 else -18.5)
		_street_lamp(lp, 0.0 if q % 2 == 0 else 180.0, 0 if q == 1 else 1)
	_end_zone()


# ================================================================ jardín

func _make_garden() -> void:
	var zone := _begin_zone("Jardin")
	var c := Vector3(0, 0, -142)
	_lawn(c + Vector3(0, 0, 1), Vector2(80, 54), 0.6, false)
	# Kiosco octagonal
	var kc := c + Vector3(0, 0, -4)
	_cy(kc + Vector3(0, 0.15, 0), 5.5, 0.3, m_stone_light, Vector3.ZERO, 8)
	for i in 8:
		var a := TAU * i / 8.0
		var p := kc + Vector3(sin(a), 0, cos(a)) * 5.0
		if i == 3:
			_cy(p + Vector3(0, 1.2, 0), 0.22, 2.0, m_iron, Vector3.ZERO, 8, 1.0, true)
			continue
		_cy(p + Vector3(0, 2.0, 0), 0.22, 3.8, m_iron, Vector3.ZERO, 8, 1.0, true)
	_mm_add(_uc(m_iron, 8, 0.0), Transform3D(_rb(Vector3(6, 0, -4)) * Basis.from_scale(Vector3(12.0, 2.6, 12.0)), kc + Vector3(0.3, 5.0, 0)))
	# Setos y árboles
	for q in 12:
		var p := c + Vector3(rng.randf_range(-38, 38), 0, rng.randf_range(-24, 26))
		if absf(p.x - c.x) < 4.0 or absf(p.z + 150.0) < 3.5:
			continue
		var hl := rng.randf_range(4, 9)
		_blk(p + Vector3(0, 0.6, 0), Vector3(hl, 1.2, 1.0), m_hedge, Vector3(0, rng.randf_range(0, 180), 0))
	for q in 22:
		var p := c + Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-26, 28))
		if absf(p.x - c.x) < 4.0 or absf(p.z + 150.0) < 3.5 or Vector2(p.x - kc.x, p.z - kc.z).length() < 7.0:
			continue
		_wtree(p, rng.randf_range(0.9, 1.3))
	for q in 6:
		var p := c + Vector3((-1.0 if q % 2 == 0 else 1.0) * 3.5, 0, -20.0 + q * 7.0)
		_bench(zone, p, 90.0 if q % 2 == 0 else -90.0, rng.randf() < 0.3)
	_reserve(Vector2(c.x, c.z), 40.0)
	_end_zone()


# ================================================================ cafetería

func _make_cafeteria() -> void:
	var zone := _begin_zone("Cafeteria")
	var c := Vector3(-124, 0, -96)
	_reserve(Vector2(c.x, c.z), 14.0)
	_blk(c, Vector3(20, 0.07, 12), m_path)
	_lbl(zone, "CAFETERÍA", Vector3(-125, 6.0, -107.8), 0.0, 90, Color(0.85, 0.5, 0.2))
	for q in 8:
		var p := c + Vector3(-7.5 + (q % 4) * 5.0, 0, -2.5 if q < 4 else 2.5)
		var down := rng.randf() < 0.3
		if down:
			_cy(p + Vector3(0, 0.6, 0), 0.6, 0.05, m_metal_light, Vector3(85, rng.randf_range(0, 360), 0), 16)
		else:
			_cy(p + Vector3(0, 0.75, 0), 0.6, 0.05, m_metal_light, Vector3.ZERO, 16)
			_cy(p + Vector3(0, 0.37, 0), 0.05, 0.74, m_metal)
			_wc(Vector3(1.0, 0.8, 1.0), Transform3D(Basis.IDENTITY, p + Vector3(0, 0.4, 0)))
		if rng.randf() < 0.5:
			var tip := rng.randf() < 0.4
			if tip:
				_mm_add(_uc(m_canvas, 8, 0.0), Transform3D(_rb(Vector3(100, rng.randf_range(0, 360), 0)) * Basis.from_scale(Vector3(2.8, 0.7, 2.8)), p + Vector3(1.2, 0.8, 0)))
				_cy(p + Vector3(0.2, 0.08, 0), 0.03, 2.4, m_metal, Vector3(0, 0, 90))
			else:
				_cy(p + Vector3(0, 1.2, 0), 0.03, 2.4, m_metal)
				_mm_add(_uc(m_canvas, 8, 0.0), Transform3D(Basis.from_scale(Vector3(2.8, 0.7, 2.8)), p + Vector3(0, 2.6, 0)))
		for e in 2:
			var cp := p + Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
			var fallen := rng.randf() < 0.35
			_blk(cp + Vector3(0, 0.45 if not fallen else 0.22, 0), Vector3(0.45, 0.05, 0.45), m_metal_light, Vector3(90 if fallen else 0, rng.randf_range(0, 360), 0))
	_end_zone()


# ================================================================ torre de agua

func _make_water_tower() -> void:
	var zone := _begin_zone("TorreDeAgua")
	var c := Vector3(125, 0, -5)
	_reserve(Vector2(c.x, c.z), 9.0)
	for lx: float in [-1.0, 1.0]:
		for lz: float in [-1.0, 1.0]:
			var bottom := c + Vector3(lx * 4.0, 0, lz * 4.0)
			var top := c + Vector3(lx * 2.6, 22.0, lz * 2.6)
			_rod(bottom, top, 0.25, m_iron, 6)
			_wc(Vector3(0.6, 22.0, 0.6), Transform3D(Basis.IDENTITY, (bottom + top) * 0.5))
	for q in 4:
		var y := 4.0 + q * 5.0
		var r := lerpf(4.0, 2.6, y / 22.0)
		for e in 4:
			var a1 := Vector3(-r, y, -r).rotated(Vector3.UP, e * PI * 0.5)
			var a2 := Vector3(r, y + 4.5, -r).rotated(Vector3.UP, e * PI * 0.5)
			_rod(c + a1, c + a2, 0.06, m_iron, 4)
	_cy(c + Vector3(0, 25.5, 0), 5.0, 7.0, m_metal_light, Vector3.ZERO, 24, 1.0, true)
	_mm_add(_uc(m_metal, 24, 0.0), Transform3D(Basis.from_scale(Vector3(10.4, 2.5, 10.4)), c + Vector3(0, 30.25, 0)))
	_lbl(zone, "UNIVERSIDAD", c + Vector3(0, 25.5, 5.02), 0.0, 120, Color(0.12, 0.2, 0.3))
	_end_zone()


# ================================================================ avenida

func _make_avenue() -> void:
	var zone := _begin_zone("Avenida")
	var colors := [Color(0.5, 0.05, 0.05), Color(0.1, 0.15, 0.3), Color(0.6, 0.6, 0.62), Color(0.15, 0.15, 0.15), Color(0.7, 0.65, 0.4)]
	for q in 18:
		var x := rng.randf_range(50, 280) * (-1.0 if q % 2 == 0 else 1.0)
		if absf(absf(x) - 160.0) < 10.0 or absf(absf(x) - 170.0) < 10.0:
			continue
		var r := rng.randf()
		var roll := 0.0
		if r < 0.12:
			roll = 180.0
		elif r < 0.22:
			roll = 90.0
		_car(zone, Vector3(x, 0, AVENUE_Z + (rng.randf_range(-5.6, -4.8) if rng.randf() < 0.6 else rng.randf_range(5.2, 5.8))), rng.randf_range(-15, 15) + (0.0 if rng.randf() < 0.5 else 180.0) + 90.0, roll, colors[rng.randi() % colors.size()], rng.randf() < 0.35)
	for q in 30:
		var x := rng.randf_range(45, 290) * (-1.0 if rng.randf() < 0.5 else 1.0)
		_chunk(Vector3(x, 0, AVENUE_Z + rng.randf_range(-6, 6)), 0.2, 0.9)
	for q in 10:
		var x := rng.randf_range(50, 280) * (-1.0 if rng.randf() < 0.5 else 1.0)
		var fallen := rng.randf() < 0.35
		_blk(Vector3(x, 0.3 if fallen else 0.42, AVENUE_Z + (rng.randf_range(-5.5, -3.8) if rng.randf() < 0.5 else rng.randf_range(4.2, 5.5))), Vector3(2.6, 0.85, 0.6), m_concrete, Vector3(90 if fallen else 0, rng.randf_range(-40, 40), 0), true)
	# Faroles a lo largo de la avenida
	var x0 := -290.0
	var k := 0
	while x0 < 290.0:
		if absf(x0) > 44.0:
			var s := 1.0 if k % 2 == 0 else -1.0
			var state := 0 if rng.randf() < 0.3 else (1 if rng.randf() < 0.7 else 2)
			_street_lamp(Vector3(x0, 0, AVENUE_Z + s * 7.2), 0.0 if s > 0.0 else 180.0, state)
		x0 += 28.0
		k += 1
	# Grieta grande con escombro cruzando la avenida
	_mound(Vector3(-95, 0, AVENUE_Z + 2.0), 6.0, 1.2)
	_mound(Vector3(240, 0, AVENUE_Z - 3.0), 5.0, 1.0)
	_end_zone()


# ================================================================ letreros

func _make_signs() -> void:
	var zone := _begin_zone("Letreros")
	_signpost(zone, Vector3(-114, 0, -4.5), 90.0, ["↑  BIBLIOTECA CENTRAL"])
	_signpost(zone, Vector3(-154, 0, -32), 0.0, ["←  BIBLIOTECA CENTRAL", "PASAJE CENTRAL · CÓMPUTO  →"])
	_signpost(zone, Vector3(-212, 0, -30), 180.0, ["←  PASAJE CENTRAL · CÓMPUTO"])
	_signpost(zone, Vector3(96, 0, -53), -90.0, ["↑  CENTRO DE CÓMPUTO"])
	_signpost(zone, Vector3(232, 0, -36), 180.0, ["AULAS NORTE · LABORATORIO  →"])
	_signpost(zone, Vector3(176, 0, -192), 0.0, ["←  AULAS NORTE · LABORATORIO"])
	_signpost(zone, Vector3(131, 0, -226), 0.0, ["LABORATORIO DE BIOGENÉTICA  →"])
	_signpost(zone, Vector3(158, 0, -236), 180.0, ["POSGRADO · AULA MAGNA  →"])
	_signpost(zone, Vector3(36, 0, -247), 90.0, ["↑  AULA MAGNA"])
	_end_zone()


func _signpost(zone: Node3D, pos: Vector3, yaw: float, lines: Array) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees = Vector3(rng.randf_range(-4, 4), yaw, rng.randf_range(-4, 4))
	zone.add_child(holder)
	var h := 2.4 + lines.size() * 0.55
	_box(holder, Vector3(0.12, h, 0.12), _xf(Vector3(0, h * 0.5, 0)), m_iron)
	var board_mat := _std(Color(0.08, 0.22, 0.14), 0.5, 0.3)
	var longest := 0
	for l in lines:
		longest = maxi(longest, String(l).length())
	var bw := maxf(2.2, longest * 0.16 + 0.5)
	for i in lines.size():
		var y := h - 0.35 - i * 0.55
		_box(holder, Vector3(bw, 0.45, 0.06), _xf(Vector3(0, y, 0)), board_mat)
		var tint := Color(0.88, 0.88, 0.82)
		var line := String(lines[i])
		for key in [["BIBLIOTECA", "biblioteca"], ["CÓMPUTO", "computo"], ["LABORATORIO", "laboratorio"], ["AULA MAGNA", "final"]]:
			if line.contains(key[0]):
				tint = ROUTE_COLORS[key[1]]
				_box(holder, Vector3(0.3, 0.3, 0.08), _xf(Vector3(-bw * 0.5 + 0.25, y, 0.01)), m_route[key[1]])
				break
		var t := Label3D.new()
		t.text = lines[i]
		t.font_size = 28
		t.pixel_size = 0.01
		t.modulate = tint
		t.shaded = true
		t.double_sided = false
		t.position = Vector3(0, y, 0.04)
		holder.add_child(t)
	_wc(Vector3(0.3, h, 0.3), Transform3D(Basis.IDENTITY, pos + Vector3(0, h * 0.5, 0)))


# ================================================================ naturaleza

func _make_nature() -> void:
	_begin_zone("Naturaleza")
	for q in 230:
		var p := _rand_free(4.0)
		if p == Vector2.INF:
			continue
		var lean := Vector3.ZERO
		if rng.randf() < 0.22:
			lean = Vector3(rng.randf_range(70, 85), rng.randf_range(0, 360), 0)
			var fdir := Vector2(sin(deg_to_rad(lean.y)), cos(deg_to_rad(lean.y)))
			for k in [3.0, 6.0, 9.5]:
				if not _is_free(p + fdir * k, 0.3):
					lean = Vector3.ZERO
		_wtree(Vector3(p.x, 0, p.y), rng.randf_range(0.8, 1.4), lean)
	for q in 700:
		var p := _rand_free(1.0, 6)
		if p == Vector2.INF:
			continue
		_chunk(Vector3(p.x, 0, p.y), 0.15, 0.9 if rng.randf() < 0.85 else 1.8)
	for q in 22:
		var p := _rand_free(5.0)
		if p == Vector2.INF:
			continue
		_mound(Vector3(p.x, 0, p.y), rng.randf_range(3.0, 6.0), rng.randf_range(0.6, 1.8))
	_end_zone()


func _wtree(p: Vector3, s: float, lean := Vector3.ZERO) -> void:
	_tree_pts.append(Vector2(p.x, p.z))
	var b := _rb(lean)
	var h := rng.randf_range(4.5, 7.5) * s
	var base := p + (Vector3(0, 0.3, 0) if lean != Vector3.ZERO else Vector3.ZERO)
	_mm_add(_uc(m_wood, 7, 0.4), Transform3D(b * Basis.from_scale(Vector3(0.55 * s, h, 0.55 * s)), base + b * Vector3(0, h * 0.5, 0)))
	for k in rng.randi_range(4, 7):
		var by := rng.randf_range(h * 0.4, h * 0.92)
		var bl := rng.randf_range(1.2, 2.8) * s
		var bb := b * Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(30, 70)))
		var dir := bb * Vector3.UP
		var start := base + b * Vector3(0, by, 0)
		_mm_add(_uc(m_wood, 5, 0.3), Transform3D(bb * Basis.from_scale(Vector3(0.16 * s, bl, 0.16 * s)), start + dir * bl * 0.5))
		if rng.randf() < 0.6:
			var sb := bb * Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(-45, 45)))
			var sl := bl * 0.6
			var sp := start + dir * bl * 0.7
			_mm_add(_uc(m_wood, 4, 0.3), Transform3D(sb * Basis.from_scale(Vector3(0.08 * s, sl, 0.08 * s)), sp + (sb * Vector3.UP) * sl * 0.5))
	if lean == Vector3.ZERO:
		_wc(Vector3(0.45 * s, h, 0.45 * s), Transform3D(Basis.IDENTITY, p + Vector3(0, h * 0.5, 0)))
	else:
		_wc(Vector3(0.5 * s, h, 0.5 * s), Transform3D(b, base + b * Vector3(0, h * 0.5, 0)))


# ================================================================ fuego, humo y marcadores

func _make_world_fx() -> void:
	var fx := _begin_zone("FuegoYHumo")
	for f in [
		[Vector3(-131.0, 0.4, 36.0), 1.0],
		[Vector3(212.0, 0.4, 41.0), 1.1],
		[Vector3(-240.0, 0.4, -150.0), 0.9],
		[Vector3(250.0, 0.4, -150.0), 1.0],
		[Vector3(-60.0, 0.4, -268.0), 0.8],
		[Vector3(140.0, 0.4, -220.0), 0.9],
	]:
		_fire(fx, f[0], f[1])
		_smoke(fx, f[0] + Vector3(0, 1.0, 0), 0.6)
	_smoke(fx, LIB + Vector3(-6, 16, -4), 1.6)
	_smoke(fx, COMP + Vector3(22, 11, -17), 1.4)
	_smoke(fx, Vector3(170, 25, -334), 1.8)
	_smoke(fx, Vector3(-380, 6, -150), 3.0)
	_smoke(fx, Vector3(360, 6, -320), 2.6)
	_smoke(fx, Vector3(-150, 6, 190), 2.4)
	_end_zone()


func _make_markers() -> void:
	var holder := Node3D.new()
	holder.name = "ArenaMarkers"
	_root.add_child(holder)
	for id in ["biblioteca", "computo", "laboratorio", "final"]:
		var d := get_arena(id)
		for key in ["center", "boss_spawn", "entrance"]:
			var m := Marker3D.new()
			m.name = "%s_%s" % [id, key]
			m.position = d[key]
			holder.add_child(m)


# ================================================================ distritos
# Facultades de ladrillo con patio (al estilo de Ciudad Universitaria), alas de
# salones, lago con malecón, fuentes, rutas de color a cada jefe, incendios.

## Color de la ruta que lleva a cada arena: línea pintada, flechas y bolardos.
const ROUTE_COLORS := {
	"biblioteca": Color(1.0, 0.72, 0.2),
	"computo": Color(0.25, 0.6, 1.0),
	"laboratorio": Color(0.35, 1.0, 0.45),
	"final": Color(1.0, 0.25, 0.15),
}
const CHALK_TEXTS := [
	"CÁLCULO II\nExamen final: viernes", "∫ x² dx = x³/3 + C", "NO HAY CLASE HOY", "TAREA: cap. 7\nej. 1 – 20",
	"¿Alguien ha visto\nal profesor?", "F = m · a", "E = mc²", "NO SALGAN\nDEL EDIFICIO", "SALÓN %d",
	"Entrega de proyectos\n— pospuesta —", "lim x→0  sen x / x = 1", "ÉL SIGUE EN LA AZOTEA", "Ética y sociedad\nTema 4",
]


func _make_district_materials() -> void:
	var ws: Shader = load("res://shaders/lake_water.gdshader")
	m_water = ShaderMaterial.new()
	m_water.shader = ws
	m_water.set_shader_parameter("noise_tex", noise_tex)
	m_water.set_shader_parameter("local_edge", true)
	m_fwater = ShaderMaterial.new()
	m_fwater.shader = ws
	m_fwater.set_shader_parameter("noise_tex", noise_tex)
	m_fwater.set_shader_parameter("deep_color", Color(0.03, 0.05, 0.05))
	m_brick = ShaderMaterial.new()
	m_brick.shader = load("res://shaders/building_panel.gdshader")
	m_brick.set_shader_parameter("noise_tex", noise_tex)
	m_brick.set_shader_parameter("wall_tint", Color(0.5, 0.21, 0.14))
	m_brick.set_shader_parameter("band_tint", Color(0.3, 0.15, 0.1))
	m_brick.set_shader_parameter("broken_ratio", 0.45)
	mesh_panel_red = _bm(Vector3(BAY, FLOOR_H, 0.3), m_brick)
	m_plaster = _concrete(Color(0.62, 0.6, 0.55), 0.15, 0.0)
	m_chalk = _std(Color(0.05, 0.13, 0.08), 0.85, 0.0)
	m_desk = _std(Color(0.33, 0.23, 0.14), 0.6, 0.0)
	m_jet = _std(Color(0.75, 0.85, 0.95, 0.55), 0.1, 0.0)
	m_jet.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_jet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_jet.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m_route.clear()
	for id in ROUTE_COLORS:
		var c: Color = ROUTE_COLORS[id]
		var m := _emit(c, 0.7)
		m.albedo_color = c * 0.75
		m_route[id] = m


## Caja en el espacio local (o, b) de un edificio.
func _lbox(o: Vector3, b: Basis, p: Vector3, size: Vector3, mat: Material, collide := false, rot := Vector3.ZERO) -> void:
	var basis := b * _rb(rot)
	_mm_add(_ub(mat), Transform3D(basis * Basis.from_scale(size), o + b * p))
	if collide:
		_wc(size, Transform3D(basis, o + b * p))


func _lpanel(o: Vector3, b: Basis, p: Vector3, rot: float) -> void:
	_mm_add(mesh_panel_red, Transform3D(b * Basis(Vector3.UP, rot), o + b * p))


## Ala de salones: `segs` tramos de 8 m. Lado local -z = fachada exterior,
## +z = pasillo abierto con columnas. En planta baja cada tramo es un salón con
## pupitres y pizarrón (se puede entrar). `passage` = tramo que es un pasaje.
func _wing(o: Vector3, yaw: float, segs: int, floors: int, passage := -1, collapse := 0.12, caps := false) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var L := segs * 8.0
	var H := floors * FLOOR_H
	for s in segs:
		var x0 := -L * 0.5 + s * 8.0
		var cx := x0 + 4.0
		var is_pass := s == passage
		_lbox(o, b, Vector3(x0, H * 0.5, 3.9), Vector3(0.5, H, 0.5), m_concrete_dark, true)
		if s == segs - 1:
			_lbox(o, b, Vector3(x0 + 8.0, H * 0.5, 3.9), Vector3(0.5, H, 0.5), m_concrete_dark, true)
		if not is_pass and rng.randf() < collapse:
			# Tramo derrumbado
			_lbox(o, b, Vector3(cx, 1.4, -0.5), Vector3(7.5, 0.3, 7.0), m_concrete, false, Vector3(rng.randf_range(-25, 25), 0, rng.randf_range(-20, 20)))
			_mound(o + b * Vector3(cx, 0, -1.0), 7.5, 1.7)
			_rebar(o + b * Vector3(cx + 2.0, 1.5, 0.0), 4)
			for k in 2:
				var hh := rng.randf_range(0.6, 2.2)
				_lbox(o, b, Vector3(cx - 2.0 + k * 4.0, hh * 0.5, -4.0), Vector3(4.0, hh, 0.3), m_concrete_dark)
			_wc(Vector3(8.0, 1.2, 0.4), Transform3D(b, o + b * Vector3(cx, 0.6, -4.0)))
			continue
		for fl in range(1, floors + 1):
			_lbox(o, b, Vector3(cx, fl * FLOOR_H, 0), Vector3(8.04, 0.3, 8.6), m_concrete)
		_wc(Vector3(8.0, 0.3, 8.6), Transform3D(b, o + b * Vector3(cx, FLOOR_H, 0)))
		_lbox(o, b, Vector3(cx, H + 0.6, -4.0), Vector3(8.0, 0.9, 0.35), m_concrete)
		_lbox(o, b, Vector3(cx, H + 0.6, 4.0), Vector3(8.0, 0.9, 0.35), m_concrete)
		for fl in floors:
			for k in 2:
				var px := cx - 2.0 + k * 4.0
				var py := fl * FLOOR_H + FLOOR_H * 0.5
				if not (fl == 0 and is_pass):
					if fl > 0 and rng.randf() < 0.07:
						_chunk(o + b * Vector3(px, fl * FLOOR_H, -4.5), 0.4, 1.2)
					else:
						_lpanel(o, b, Vector3(px, py, -4.0), 0.0)
				if fl >= 1:
					_lpanel(o, b, Vector3(px, py, 4.0), 0.0)
		_lbox(o, b, Vector3(cx, 0.0, 0.0), Vector3(8.0, 0.06, 8.0), m_labtile if not is_pass else m_path)
		if is_pass:
			continue
		_wc(Vector3(8.0, FLOOR_H, 0.4), Transform3D(b, o + b * Vector3(cx, FLOOR_H * 0.5, -4.0)))
		_classroom(o, b, yaw, x0, s == segs - 1 or s + 1 == passage, false)
	if caps:
		for sx: float in [-1.0, 1.0]:
			for fl in floors:
				for k in 2:
					_lpanel(o, b, Vector3(sx * L * 0.5, fl * FLOOR_H + FLOOR_H * 0.5, -2.0 + k * 4.0), PI * 0.5)
			_wc(Vector3(0.4, H, 8.0), Transform3D(b, o + b * Vector3(sx * L * 0.5, H * 0.5, 0)))


## Interior de un salón de 8 m en el espacio local de un ala (pasillo en +z).
func _classroom(o: Vector3, b: Basis, yaw: float, x0: float, right_wall: bool, second_door: bool) -> void:
	var cx := x0 + 4.0
	# Muro del pasillo con puerta (y una segunda puerta si el pasillo está bloqueado)
	if second_door:
		_lbox(o, b, Vector3(x0 + 0.5, FLOOR_H * 0.5, 1.0), Vector3(1.0, FLOOR_H, 0.2), m_plaster, true)
		_lbox(o, b, Vector3(x0 + 4.0, FLOOR_H * 0.5, 1.0), Vector3(2.8, FLOOR_H, 0.2), m_plaster, true)
		_lbox(o, b, Vector3(x0 + 1.8, FLOOR_H - 0.6, 1.0), Vector3(1.6, 1.2, 0.2), m_plaster)
	else:
		_lbox(o, b, Vector3(x0 + 2.7, FLOOR_H * 0.5, 1.0), Vector3(5.4, FLOOR_H, 0.2), m_plaster, true)
	_lbox(o, b, Vector3(x0 + 7.5, FLOOR_H * 0.5, 1.0), Vector3(1.0, FLOOR_H, 0.2), m_plaster, true)
	_lbox(o, b, Vector3(x0 + 6.2, FLOOR_H - 0.6, 1.0), Vector3(1.6, 1.2, 0.2), m_plaster)
	if rng.randf() < 0.5:
		_lbox(o, b, Vector3(x0 + 6.0, 1.1, 1.5), Vector3(0.9, 2.2, 0.05), m_wood, false, Vector3(0, rng.randf_range(40, 100), rng.randf_range(-8, 8)))
	# Muros divisorios
	_lbox(o, b, Vector3(x0 + 0.1, FLOOR_H * 0.5, -1.5), Vector3(0.2, FLOOR_H, 5.0), m_plaster, true)
	if right_wall:
		_lbox(o, b, Vector3(x0 + 7.9, FLOOR_H * 0.5, -1.5), Vector3(0.2, FLOOR_H, 5.0), m_plaster, true)
	# Pizarrón, escritorio y pupitres
	_lbox(o, b, Vector3(x0 + 0.24, 1.6, -1.5), Vector3(0.05, 1.2, 3.2), m_chalk)
	_lbox(o, b, Vector3(x0 + 0.29, 0.98, -1.5), Vector3(0.1, 0.05, 3.2), m_wood)
	if rng.randf() < 0.6:
		var txt: String = CHALK_TEXTS[rng.randi() % CHALK_TEXTS.size()]
		if txt.contains("%d"):
			txt = txt % rng.randi_range(101, 312)
		var lb := _lbl(w_zone, txt, o + b * Vector3(x0 + 0.28, 1.62, -1.5), yaw + 90.0, 24, Color(0.62, 0.66, 0.62), false, 0.006)
		lb.width = 480.0
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbox(o, b, Vector3(x0 + 1.5, 0.4, -3.2 if second_door else -1.5), Vector3(0.7, 0.8, 1.5), m_desk, true)
	for i in 3:
		for j in 4:
			if rng.randf() < 0.1:
				continue
			var dp := Vector3(x0 + 3.0 + i * 1.6, 0, -3.3 + j * 1.15)
			if rng.randf() < 0.25:
				_lbox(o, b, dp + Vector3(0.2, 0.25, 0), Vector3(0.9, 0.5, 0.45), m_desk, false, Vector3(90, rng.randf_range(-60, 60), 0))
				continue
			var yj := rng.randf_range(-10, 10)
			_lbox(o, b, dp + Vector3(0, 0.74, 0), Vector3(0.45, 0.04, 0.6), m_desk, false, Vector3(0, yj, 0))
			_lbox(o, b, dp + Vector3(0, 0.37, 0), Vector3(0.04, 0.72, 0.5), m_iron, false, Vector3(0, yj, 0))
			_lbox(o, b, dp + Vector3(0.45, 0.45, 0), Vector3(0.4, 0.04, 0.42), m_desk, false, Vector3(0, yj, 0))
			_lbox(o, b, dp + Vector3(0.66, 0.68, 0), Vector3(0.04, 0.45, 0.42), m_desk, false, Vector3(0, yj, 0))
	for q in 6:
		_mm_add(_ub(m_paper), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(0.21, 0.004, 0.29)), o + b * Vector3(x0 + rng.randf_range(0.5, 7.5), 0.035, rng.randf_range(-3.8, 3.8))))
	if rng.randf() < 0.3:
		_lbox(o, b, Vector3(cx, FLOOR_H - 0.6, -1.0), Vector3(1.2, 0.04, 0.6), m_concrete, false, Vector3(rng.randf_range(-50, 50), 0, rng.randf_range(-40, 40)))
	if rng.randf() < 0.16:
		_lbox(o, b, Vector3(cx, FLOOR_H - 0.12, -1.5), Vector3(1.2, 0.05, 0.3), m_panel_light)
		_omni(w_zone, o + b * Vector3(cx, FLOOR_H - 0.5, -1.5), Color(0.85, 0.92, 1.0), 1.0, 8.0, 0.05, 16.0)


## Facultad: cuatro alas de salones alrededor de un patio con fuente.
## Entradas (pasajes) en los lados local +z y -z.
func _faculty(c: Vector3, yaw: float, title: String, floors := 0) -> void:
	var zone := _begin_zone("Facultad")
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	if floors <= 0:
		floors = rng.randi_range(2, 3)
	_wing(c + b * Vector3(0, 0, -20), yaw, 7, floors, 3)
	_wing(c + b * Vector3(0, 0, 20), yaw + 180.0, 7, floors, 3)
	_wing(c + b * Vector3(24, 0, 0), yaw - 90.0, 4, floors, -1)
	_wing(c + b * Vector3(-24, 0, 0), yaw + 90.0, 4, floors, -1)
	# Patio
	_lbox(c, b, Vector3(0, 0, 0), Vector3(40, 0.06, 3.0), m_path)
	_lbox(c, b, Vector3(0, 0.002, 0), Vector3(3.0, 0.06, 32), m_path)
	_fountain(zone, c, 3.6, false)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var lc := c + b * Vector3(sx * 10.75, 0, sz * 8.75)
			var ls := Vector2(18.0, 13.6) if absf(b.x.x) > 0.5 else Vector2(13.6, 18.0)
			_lawn(lc, ls, 1.0)
			var tp := c + b * Vector3(sx * 11.0, 0, sz * 8.0)
			if rng.randf() < 0.25:
				_wtree(tp, 1.1, Vector3(82, rng.randf_range(0, 360), 0))
			else:
				_wtree(tp, rng.randf_range(1.0, 1.3))
			_bench(zone, c + b * Vector3(sx * 6.0, 0, sz * 3.2), yaw + (0.0 if sz < 0.0 else 180.0), rng.randf() < 0.3)
	for e: float in [-1.0, 1.0]:
		var face := yaw + (0.0 if e > 0.0 else 180.0)
		_lbl(zone, title, c + b * Vector3(0, 4.15, e * 24.22), face, 46, Color(0.88, 0.82, 0.66))
	_reserve(Vector2(c.x, c.z), 36.0)
	_extra_zones.append([Vector2(c.x, c.z), 30.0, title.capitalize()])
	_end_zone()


# ---------------------------------------------------------------- lago

## Lago con malecón, muelle, isla con puente y ambientación. Centro en c,
## radios A (x) y B (z). Lo construye el prefab LAGO.
func _make_lake(c: Vector3, A: float, B: float) -> void:
	var zone := _begin_zone("Lago")
	_mm_add(_uc(m_water, 64), Transform3D(Basis.from_scale(Vector3(A * 2.0 + 1.0, 0.05, B * 2.0 + 1.0)), c))
	# Isla y puente (el puente sale de la orilla norte, -z)
	var isl := c + Vector3(-A * 0.36, 0, -B * 0.39)
	var ir := minf(A, B) * 0.19
	var shore_z := c.z - B * sqrt(maxf(0.0, 1.0 - pow((isl.x - c.x) / A, 2.0)))
	var N := 96
	for i in N:
		var t0 := TAU * i / N
		var t1 := TAU * (i + 1) / N
		var tm := (t0 + t1) * 0.5
		var p0 := c + Vector3(A * cos(t0), 0, B * sin(t0))
		var p1 := c + Vector3(A * cos(t1), 0, B * sin(t1))
		var pm := (p0 + p1) * 0.5
		var nrm := Vector3(B * cos(tm), 0, A * sin(tm)).normalized()
		var d := p1 - p0
		var l := d.length()
		var bs := Basis(Vector3.UP, atan2(d.x, d.z))
		var at_pier := absf(wrapf(tm, -PI, PI)) < 1.8 / B
		var at_bridge := absf(pm.x - isl.x) < 1.9 and pm.z < c.z
		if not at_pier and not at_bridge:
			var wp := pm + nrm * 0.3
			var intact := rng.randf() > 0.07
			# Donde el barandal está arrancado el murete también se rompió y no hay
			# colisión: por ahí se puede entrar al agua (y contagiarse de la ameba).
			if intact:
				_mm_add(_ub(m_stone_light), Transform3D(bs * Basis.from_scale(Vector3(0.6, 0.7, l + 0.15)), wp + Vector3(0, 0.35, 0)))
			else:
				_mm_add(_ub(m_stone_light), Transform3D(bs * _rb(Vector3(0, 0, 8)) * Basis.from_scale(Vector3(0.6, 0.18, l * 0.5)), wp + nrm * 0.4 + Vector3(0, 0.09, 0)))
			if intact:
				_wc(Vector3(0.6, 1.6, l + 0.15), Transform3D(bs, wp + Vector3(0, 0.8, 0)))
			if intact:
				_mm_add(_ub(m_iron), Transform3D(bs * Basis.from_scale(Vector3(0.05, 0.05, l)), wp + Vector3(0, 1.25, 0)))
				_mm_add(_ub(m_iron), Transform3D(bs * Basis.from_scale(Vector3(0.04, 0.04, l)), wp + Vector3(0, 0.95, 0)))
			else:
				# Tramo de barandal arrancado, flotando
				_mm_add(_ub(m_iron), Transform3D(bs * _rb(Vector3(rng.randf_range(-20, 20), 0, 80)) * Basis.from_scale(Vector3(0.05, 0.05, l)), wp - nrm * 1.2 + Vector3(0, 0.05, 0)))
			_mm_add(_ub(m_iron), Transform3D(Basis.from_scale(Vector3(0.07, 0.6, 0.07)), p0 + nrm * 0.3 + Vector3(0, 0.98, 0)))
		# Malecón
		_mm_add(_ub(m_path), Transform3D(bs * Basis.from_scale(Vector3(7.0, 0.06, l * 1.12 + 0.3)), pm + nrm * 4.1))
		_mm_add(_ub(m_concrete_dark), Transform3D(bs * Basis.from_scale(Vector3(0.35, 0.16, l * 1.2)), pm + nrm * 7.8 + Vector3(0, 0.04, 0)))
		if i % 6 == 3:
			var phi := atan2(nrm.z, -nrm.x)
			_street_lamp(pm + nrm * 7.2, rad_to_deg(phi) - 90.0, 0 if i % 12 == 3 else 1)
		if i % 8 == 1:
			_bench(zone, pm + nrm * 6.3, rad_to_deg(atan2(-nrm.x, -nrm.z)), rng.randf() < 0.25)
		if i % 4 == 2:
			var tp := pm + nrm * rng.randf_range(10.5, 13.0)
			_wtree(tp, rng.randf_range(0.9, 1.3), Vector3(82, rng.randf_range(0, 360), 0) if rng.randf() < 0.15 else Vector3.ZERO)
	# Muelle de madera hacia el centro del lago
	var ps := c + Vector3(A + 0.6, 0, 0)
	var plen := minf(24.0, A * 0.45)
	_blk(ps + Vector3(-plen * 0.5, 0.05, 0), Vector3(plen, 0.1, 3.6), m_wood)
	for k in int(plen / 3.0) + 1:
		for sz: float in [-1.0, 1.0]:
			_cy(ps + Vector3(-k * 3.0, 0.4, sz * 1.75), 0.1, 1.2, m_wood, Vector3.ZERO, 6)
	for sz: float in [-1.0, 1.0]:
		_blk(ps + Vector3(-plen * 0.5, 1.0, sz * 1.75), Vector3(plen, 0.08, 0.08), m_wood)
		_wc(Vector3(plen, 1.6, 0.2), Transform3D(Basis.IDENTITY, ps + Vector3(-plen * 0.5, 0.8, sz * 1.85)))
	_wc(Vector3(0.2, 1.6, 3.6), Transform3D(Basis.IDENTITY, ps + Vector3(-plen - 0.1, 0.8, 0)))
	_street_lamp(ps + Vector3(-plen + 0.6, 0, 1.4), 0.0, 0)
	_lbl(zone, "MUELLE", ps + Vector3(0.4, 1.5, 0), 90.0, 40, Color(0.8, 0.75, 0.6))
	# Lanchas de pedales amarradas (una volteada)
	for k in 3:
		var bp := ps + Vector3(-4.0 - k * 4.5, 0, 3.3 * (1.0 if k % 2 == 0 else -1.0))
		var flipped := k == 2
		var by := 0.15 if not flipped else 0.1
		_blk(bp + Vector3(0, by, 0), Vector3(2.4, 0.5, 1.3), m_line if k != 1 else m_blue, Vector3(180 if flipped else 0, rng.randf_range(-15, 15), rng.randf_range(-6, 6)))
		if not flipped:
			_sp(bp + Vector3(0.9, 0.7, 0), Vector3(0.35, 0.7, 0.3), m_line, Vector3(0, 0, -20))
			_sp(bp + Vector3(1.05, 1.05, 0), Vector3(0.3, 0.25, 0.22), m_line)
			_blk(bp + Vector3(-0.3, 0.55, 0), Vector3(0.6, 0.3, 1.0), m_blue)
		_rod(bp + Vector3(0.5, 0.3, 0), bp + Vector3(0.5, 0.9, -1.6 * signf(bp.z - ps.z)), 0.01, m_canvas, 3)
	# Letrero
	var sg := c + Vector3(A + 5.5, 0, 4.5)
	_cy(sg + Vector3(0, 1.0, 0), 0.05, 2.0, m_iron)
	_blk(sg + Vector3(0, 2.0, 0), Vector3(0.08, 0.6, 1.6), m_line, Vector3(0, 0, 6))
	_lbl(zone, "PROHIBIDO NADAR", sg + Vector3(-0.06, 2.0, 0), -90.0, 26, Color(0.6, 0.05, 0.04))
	_lbl(zone, "PROHIBIDO NADAR", sg + Vector3(0.06, 2.0, 0), 90.0, 26, Color(0.6, 0.05, 0.04))
	# Puente de madera a la isla
	var b_start := Vector3(isl.x, 0, shore_z + 0.5)
	var b_end := Vector3(isl.x, 0, isl.z - ir + 0.5)
	var bl := b_end.z - b_start.z
	if bl > 2.0:
		var bm := (b_start + b_end) * 0.5
		_blk(bm + Vector3(0, 0.06, 0), Vector3(3.0, 0.12, bl + 1.0), m_wood)
		var n_posts := int(bl / 2.5) + 1
		for k in n_posts + 1:
			var z := b_start.z + bl * k / float(n_posts)
			for sx: float in [-1.0, 1.0]:
				_cy(Vector3(isl.x + sx * 1.45, 0.55, z), 0.07, 1.1, m_wood, Vector3.ZERO, 6)
		for sx: float in [-1.0, 1.0]:
			_blk(bm + Vector3(sx * 1.45, 1.05, 0), Vector3(0.08, 0.08, bl + 0.6), m_wood)
			_wc(Vector3(0.2, 1.6, bl + 1.6), Transform3D(Basis.IDENTITY, bm + Vector3(sx * 1.55, 0.8, 0)))
		_blk(b_start + Vector3(0, 2.4, -0.55), Vector3(4.6, 0.55, 0.08), m_wood_dark)
		for face: float in [0.0, 180.0]:
			_lbl(zone, "ISLA DE LOS PENSADORES", b_start + Vector3(0, 2.4, -0.55 + (0.05 if face == 0.0 else -0.05)), face, 24, Color(0.85, 0.8, 0.65))
		for sx: float in [-1.0, 1.0]:
			_cy(b_start + Vector3(sx * 1.7, 1.3, -0.55), 0.08, 2.6, m_wood_dark)
	# Isla: tierra, orilla con piedras, kiosco, árbol, banca y farol
	_mm_add(_uc(m_debris, 24), Transform3D(Basis.from_scale(Vector3(ir * 2.0, 0.1, ir * 2.0)), isl))
	_mm_add(_uc(m_lawn, 24), Transform3D(Basis.from_scale(Vector3(ir * 1.8, 0.12, ir * 1.8)), isl))
	var isl_pts: Array = []
	for q in int(ir * ir * 1.6):
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * ir * 0.88
		isl_pts.append(isl + Vector3(cos(a) * rr, 0.06, sin(a) * rr))
	_tufts(zone, isl, isl_pts)
	var ni := 28
	for i in ni:
		var a := TAU * (i + 0.5) / ni
		var dir := Vector3(cos(a), 0, sin(a))
		if dir.z < -0.9:
			continue
		_chunk(isl + dir * ir, 0.3, 0.8)
		_wc(Vector3(0.6, 1.4, TAU * ir / ni + 0.3), Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) + PI * 0.5), isl + dir * (ir + 0.2) + Vector3(0, 0.7, 0)))
	var gz := isl + Vector3(ir * 0.25, 0, ir * 0.15)
	for k in 6:
		var a := TAU * k / 6.0
		if k == 4:
			_cy(gz + Vector3(cos(a), 0, sin(a)) * 2.4 + Vector3(0, 0.9, 0), 0.12, 1.8, m_wood_dark, Vector3.ZERO, 6)
			continue
		_cy(gz + Vector3(cos(a), 0, sin(a)) * 2.4 + Vector3(0, 1.4, 0), 0.12, 2.8, m_wood_dark, Vector3.ZERO, 6, 1.0, true)
	_mm_add(_uc(m_wood_dark, 6, 0.0), Transform3D(_rb(Vector3(5, 0, -4)) * Basis.from_scale(Vector3(6.0, 1.8, 6.0)), gz + Vector3(0, 3.6, 0)))
	_bench(zone, gz + Vector3(0, 0, -0.8), 0.0, false)
	_wtree(isl + Vector3(-ir * 0.4, 0, ir * 0.3), 1.5)
	_cy(isl + Vector3(-ir * 0.2, 1.4, -ir * 0.45), 0.45, 2.8, m_stone_light, Vector3(0, 0, 10), 12, 0.9, true)
	_sp(isl + Vector3(-ir * 0.2 + 0.4, 0.3, -ir * 0.45 + 1.0), Vector3(0.8, 0.9, 0.8), m_stone_light, Vector3(60, 20, 0))
	_cy(gz + Vector3(1.6, 0.7, 1.2), 0.05, 1.4, m_iron, Vector3.ZERO, 6)
	_sp(gz + Vector3(1.6, 1.5, 1.2), Vector3(0.25, 0.3, 0.25), m_lamp_on)
	_omni(zone, gz + Vector3(1.6, 1.6, 1.2), Color(1.0, 0.65, 0.35), 1.4, 9.0, 0.02, 4.0)
	# Tules en la orilla y nenúfares
	var reed_pts: Array = []
	for cl in 26:
		var a := rng.randf() * TAU
		var k := rng.randf_range(0.86, 0.96)
		var cc := c + Vector3(cos(a) * A * k, 0, sin(a) * B * k)
		if absf(wrapf(a, -PI, PI)) < 0.12:
			continue
		for q in rng.randi_range(10, 22):
			var rp := cc + Vector3(rng.randf_range(-1.6, 1.6), 0.02, rng.randf_range(-1.6, 1.6))
			reed_pts.append(rp)
			if rng.randf() < 0.2:
				var h := rng.randf_range(1.3, 1.9)
				_rod(rp, rp + Vector3(rng.randf_range(-0.15, 0.15), h, rng.randf_range(-0.15, 0.15)), 0.012, m_hedge, 3)
				_cy(rp + Vector3(0, h - 0.1, 0), 0.04, 0.22, m_wood_dark, Vector3.ZERO, 5)
	_reeds(zone, c, reed_pts)
	for q in 70:
		var a := rng.randf() * TAU
		var k := rng.randf_range(0.55, 0.92)
		var lp := c + Vector3(cos(a) * A * k, 0.035, sin(a) * B * k)
		if lp.distance_to(isl) < ir + 1.0:
			continue
		var lr := rng.randf_range(0.25, 0.6)
		_mm_add(_uc(m_lily, 10), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(lr * 2.0, 0.01, lr * 2.0)), lp))
		if rng.randf() < 0.08:
			_sp(lp + Vector3(0, 0.08, 0), Vector3(0.14, 0.1, 0.14), m_line)
	# Restos en el agua: auto y robot medio hundidos, árbol caído, lanchas y basura
	var car_p := c + Vector3(-A * 0.55, 0, B * 0.55)
	_blk(car_p + Vector3(0, -0.1, 0), Vector3(4.3, 1.5, 1.85), m_burnt, Vector3(-12, 35, 18))
	_blk(car_p + Vector3(-0.5, 0.6, 0.2), Vector3(2.0, 0.7, 1.6), m_rdark, Vector3(-12, 35, 18))
	_cy(car_p + Vector3(1.4, 0.3, 1.0), 0.36, 0.26, m_tire, Vector3(80, 35, 0), 12)
	_humanoid(Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.BACK, 0.2), c + Vector3(A * 0.5, -0.12, -B * 0.62)), m_reye_on, {
		"head": Vector3(0, 30, 0),
		"arm_l": [Vector3(0, 0, -70), Vector3(-20, 0, 0)],
		"arm_r": [Vector3(-20, 0, 60), Vector3(-50, 0, 0)],
		"leg_l": [Vector3(-10, 0, -10), Vector3(5, 0, 0)],
		"leg_r": [Vector3(-30, 0, 10), Vector3(40, 0, 0)],
	})
	var fall_a := deg_to_rad(200.0)
	var tree_base := c + Vector3(cos(fall_a) * (A + 9.0), 0, sin(fall_a) * (B + 9.0))
	_wtree(tree_base, 1.4, Vector3(84, rad_to_deg(atan2(c.x - tree_base.x, c.z - tree_base.z)), 0))
	_blk(c + Vector3(-A * 0.4, 0.1, B * 0.33), Vector3(5.0, 1.0, 1.8), m_burnt, Vector3(25, 70, 15))
	_blk(c + Vector3(A * 0.33, 0.0, -B * 0.39), Vector3(4.0, 0.9, 1.6), m_wood, Vector3(-30, -20, 8))
	for q in 30:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.2, 0.9)
		_mm_add(_ub(m_wood if rng.randf() < 0.5 else m_debris), Transform3D(_rb(Vector3(0, rng.randf_range(0, 360), 0)) * Basis.from_scale(Vector3(rng.randf_range(0.3, 1.5), 0.08, rng.randf_range(0.2, 0.6))), c + Vector3(cos(a) * A * r, 0.04, sin(a) * B * r)))
	_lake_mist(zone, c, A, B)
	_end_zone()


## Matas altas de tule (MultiMesh propio, se oculta a distancia).
func _reeds(parent: Node3D, center: Vector3, pts: Array) -> void:
	if pts.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_tuft
	mm.instance_count = pts.size()
	for i in pts.size():
		var p: Vector3 = pts[i]
		var s := rng.randf_range(1.2, 1.8)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, s * rng.randf_range(2.8, 4.2), s)), p - center))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = center
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 140.0
	parent.add_child(mmi)


## Neblina baja que se arrastra sobre el agua.
func _lake_mist(parent: Node3D, c: Vector3, A: float, B: float) -> void:
	var p := GPUParticles3D.new()
	p.name = "Neblina"
	p.position = c + Vector3(0, 0.7, 0)
	p.amount = int(clampf(A * B / 50.0, 16.0, 70.0))
	p.lifetime = 24.0
	p.preprocess = 24.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-A - 10, -2, -B - 10), Vector3(A * 2.0 + 20, 8, B * 2.0 + 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(A * 0.75, 0.3, B * 0.75)
	pm.direction = Vector3(1, 0, 0.3)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3.ZERO
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 7.0
	pm.scale_max = 12.0
	var cg := Gradient.new()
	cg.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	cg.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	pm.color_ramp = cgt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 0.45)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.72, 0.76, 0.8)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _soft_tex(PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)]), PackedFloat32Array([0.0, 0.5, 1.0]))
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	p.draw_pass_1 = q
	parent.add_child(p)


# ---------------------------------------------------------------- fuentes

## Plaza con fuente que todavía echa agua, faroles y bancas.
func _fountain_plaza(zone: Node3D, c: Vector3, r: float) -> void:
	_mm_add(_uc(m_path, 48), Transform3D(Basis.from_scale(Vector3(r * 2.0, 0.1, r * 2.0)), c))
	_cy(c, r + 0.35, 0.22, m_concrete_dark, Vector3.ZERO, 48)
	_fountain(zone, c, minf(5.5, r * 0.45), true)
	for q in 4:
		var a := TAU * (q + 0.5) / 4.0
		_street_lamp(c + Vector3(sin(a), 0, cos(a)) * (r + 1.2), rad_to_deg(a), 0 if q % 2 == 0 else 1)
		var bp := c + Vector3(sin(a + 0.4), 0, cos(a + 0.4)) * (r - 3.0)
		_bench(zone, bp, rad_to_deg(atan2(c.x - bp.x, c.z - bp.z)), rng.randf() < 0.3)


## Fuente con tazón central. `jets` = todavía sale agua.
func _fountain(zone: Node3D, c: Vector3, r: float, jets: bool) -> void:
	var n := 28
	for i in n:
		var a := TAU * i / n
		_blk(c + Vector3(sin(a), 0, cos(a)) * r + Vector3(0, 0.35, 0), Vector3(TAU * r / n + 0.15, 0.7, 0.55), m_stone_light, Vector3(0, rad_to_deg(a), 0), true)
	_cy(c + Vector3(0, 0.2, 0), r - 0.2, 0.4, m_concrete_dark, Vector3.ZERO, 40)
	_mm_add(_uc(m_fwater, 40), Transform3D(Basis.from_scale(Vector3(r * 2.0 - 0.4, 0.04, r * 2.0 - 0.4)), c + Vector3(0, 0.42, 0)))
	var br := maxf(1.0, r * 0.36)
	_cy(c + Vector3(0, 1.1, 0), 0.55, 2.2, m_stone_light, Vector3.ZERO, 12, 0.8, true)
	_cy(c + Vector3(0, 2.4, 0), br * 0.45, 0.45, m_stone_light, Vector3.ZERO, 24, 2.2)
	_mm_add(_uc(m_fwater, 24), Transform3D(Basis.from_scale(Vector3(br * 1.9, 0.03, br * 1.9)), c + Vector3(0, 2.6, 0)))
	if jets or rng.randf() < 0.5:
		_cy(c + Vector3(0, 3.1, 0), 0.16, 1.0, m_stone_light, Vector3.ZERO, 8)
		_sp(c + Vector3(0, 3.7, 0), Vector3(0.45, 0.45, 0.45), m_bronze)
	else:
		_sp(c + Vector3(r * 0.5, 0.5, 0.3), Vector3(0.45, 0.45, 0.45), m_bronze)
		_cy(c + Vector3(r * 0.4, 0.5, -0.4), 0.16, 1.0, m_stone_light, Vector3(0, 30, 80), 8)
	if jets:
		_water_jet(zone, c + Vector3(0, 3.8, 0), 0.0)
		_water_jet(zone, c + Vector3(0, 2.6, 0), br * 0.95)


func _water_jet(parent: Node3D, pos: Vector3, ring_r: float) -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = 140 if ring_r <= 0.0 else 220
	p.lifetime = 1.1 if ring_r <= 0.0 else 0.75
	p.preprocess = 1.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	var pm := ParticleProcessMaterial.new()
	if ring_r > 0.0:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = ring_r
		pm.emission_ring_inner_radius = ring_r * 0.97
		pm.emission_ring_height = 0.02
		pm.direction = Vector3(0, -1, 0)
		pm.spread = 10.0
		pm.initial_velocity_min = 0.2
		pm.initial_velocity_max = 0.5
	else:
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 7.0
		pm.initial_velocity_min = 4.2
		pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.18)
	q.material = m_jet
	p.draw_pass_1 = q
	parent.add_child(p)


# ---------------------------------------------------------------- rutas

## Línea pintada, flechas y bolardos luminosos del color de cada arena.
func _make_routes() -> void:
	_begin_zone("Rutas")
	var routes := [
		["biblioteca", 1.0, [Vector2(-109, 0.5), Vector2(-160, 0.5), Vector2(-160, -40), Vector2(-207, -40)]],
		["computo", 1.0, [Vector2(-207, -40), Vector2(-160, -40), Vector2(-118, -40), Vector2(-96, -60), Vector2(-89, -63.5)]],
		["computo", 1.0, [Vector2(89, -63.5), Vector2(97, -60), Vector2(127, -55), Vector2(130, -48), Vector2(130, -45), Vector2(137, -43), Vector2(163, -46), Vector2(214, -45)]],
		["laboratorio", 1.0, [Vector2(214, -45), Vector2(173, -51), Vector2(159, -149), Vector2(124, -152), Vector2(115, -157), Vector2(90, -195), Vector2(78, -212)]],
		["laboratorio", 1.0, [Vector2(126, -223), Vector2(126, -230), Vector2(158, -237.5)]],
		["final", 1.0, [Vector2(164, -246), Vector2(138, -246), Vector2(126, -247), Vector2(111, -246), Vector2(107, -248), Vector2(99, -252.5)]],
		["final", 1.0, [Vector2(41, -252.5), Vector2(7, -252.5), Vector2(0, -258), Vector2(0, -276)]],
	]
	for rt in routes:
		var id: String = rt[0]
		var side: float = rt[1]
		var pts: Array = rt[2]
		var mat: StandardMaterial3D = m_route[id]
		var dist := 0.0
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var e: Vector2 = pts[i + 1]
			var dir := (e - a).normalized()
			var perp := Vector2(-dir.y, dir.x) * side
			var l := a.distance_to(e)
			var yaw := atan2(dir.x, dir.y)
			var half := _path_half_width((a + e) * 0.5)
			var t := 1.5
			while t < l - 1.5:
				var q := a + dir * t + perp * 0.9
				if q.distance_to(Vector2(170, -120)) < 8.0 or q.distance_to(Vector2(-160, -120)) < 8.0 or q.distance_to(Vector2(0, -200)) < 7.0:
					t += 5.0
					continue
				var y := 0.055
				var along := dist + t
				if fmod(along, 36.0) < 5.0:
					# Flecha (chevron) apuntando hacia la arena
					for s: float in [-1.0, 1.0]:
						var arm := dir.rotated(s * deg_to_rad(145.0))
						var ac := q + arm * 0.75
						_mm_add(_ub(mat), Transform3D(Basis(Vector3.UP, atan2(arm.x, arm.y)) * Basis.from_scale(Vector3(0.28, 0.02, 1.5)), Vector3(ac.x, y, ac.y)))
					t += 5.0
					continue
				_mm_add(_ub(mat), Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.3, 0.02, 3.0)), Vector3(q.x, y, q.y)))
				if fmod(along, 24.0) < 5.0:
					var bp := a + dir * t + perp * (half - 0.4)
					_cy(Vector3(bp.x, 0.45, bp.y), 0.13, 0.9, m_concrete_dark, Vector3.ZERO, 8)
					_cy(Vector3(bp.x, 0.97, bp.y), 0.16, 0.14, mat, Vector3.ZERO, 8)
				t += 5.0
			dist += l
	_end_zone()


func _path_half_width(p: Vector2) -> float:
	if absf(p.y - AVENUE_Z) < 7.0:
		return 6.5
	for s in _paths:
		var a: Vector2 = s[0]
		var e: Vector2 = s[1]
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, e)) < float(s[2]) * 0.5:
			return float(s[2]) * 0.5
	return 4.0


# ---------------------------------------------------------------- incendios y paradas

func _make_wrecks() -> void:
	var zone := _begin_zone("Incendios")
	var defs := [
		Vector3(-62, 0, 33.5), Vector3(86, 0, 45.5), Vector3(-205, 0, 45.5), Vector3(232, 0, 33.5),
		Vector3(-169, 0, -70), Vector3(181, 0, -95), Vector3(-120, 0, -190), Vector3(60, 0, -191),
		Vector3(11, 0, -248), Vector3(178, 0, -215), Vector3(-185, 0, -232), Vector3(-30, 0, 52),
		Vector3(140, 0, -160), Vector3(-262, 0, 33.5),
	]
	var colors := [Color(0.5, 0.05, 0.05), Color(0.1, 0.15, 0.3), Color(0.6, 0.6, 0.62), Color(0.7, 0.65, 0.4)]
	for p in defs:
		var pos: Vector3 = p
		var roll := 0.0 if rng.randf() < 0.75 else 180.0
		_car(zone, pos, rng.randf_range(0, 360), roll, colors[rng.randi() % colors.size()], true)
		var fy := 1.9 if roll > 90.0 else 1.1
		_fire(zone, pos + Vector3(0, fy, 0), rng.randf_range(0.7, 1.0))
		_smoke(zone, pos + Vector3(0, fy + 1.0, 0), 0.45)
		for q in 6:
			_chunk(pos + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)), 0.1, 0.4)
	# Paradas de autobús sobre la avenida
	for x: float in [-212.0, -100.0, 60.0, 130.0]:
		_bus_stop(zone, Vector3(x, 0, AVENUE_Z - 8.0))
	_end_zone()


func _bus_stop(zone: Node3D, p: Vector3) -> void:
	_blk(p + Vector3(0, 2.6, 0), Vector3(4.6, 0.12, 2.0), m_iron, Vector3(0, 0, rng.randf_range(-3, 6)))
	for sx: float in [-2.2, 2.2]:
		_blk(p + Vector3(sx, 1.3, -0.9), Vector3(0.1, 2.6, 0.1), m_iron, Vector3.ZERO, true)
	_blk(p + Vector3(0, 1.4, -0.9), Vector3(4.3, 2.0, 0.04), m_glass if rng.randf() < 0.5 else m_glass_clear)
	_blk(p + Vector3(0, 0.45, -0.55), Vector3(3.4, 0.08, 0.45), m_wood)
	_blk(p + Vector3(2.9, 1.4, 0.6), Vector3(0.08, 2.8, 0.08), m_iron)
	_blk(p + Vector3(2.9, 2.7, 0.6), Vector3(0.7, 0.5, 0.04), _std(Color(0.1, 0.25, 0.5), 0.5, 0.2))
	_lbl(w_zone, "PARADA\nRuta 1", p + Vector3(2.9, 2.7, 0.63), 0.0, 14, Color(0.9, 0.9, 0.9))
	_wc(Vector3(4.4, 2.6, 0.2), Transform3D(Basis.IDENTITY, p + Vector3(0, 1.3, -0.9)))


# ---------------------------------------------------------------- alamedas

## Hileras de árboles a ambos lados de los caminos principales y de la avenida;
## algunos derribados junto al camino.
func _make_alamedas() -> void:
	_begin_zone("Alamedas")
	var rows: Array = []
	for s in _paths:
		if float(s[2]) >= 7.0:
			rows.append(s)
	rows.append([Vector2(-292, AVENUE_Z), Vector2(292, AVENUE_Z), 13.0])
	for s in rows:
		var a: Vector2 = s[0]
		var e: Vector2 = s[1]
		var w: float = s[2]
		var dir := (e - a).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var l := a.distance_to(e)
		var t := 6.0
		while t < l - 4.0:
			for sd: float in [-1.0, 1.0]:
				var p := a + dir * t + perp * sd * (w * 0.5 + 4.5)
				if not _is_free(p, 1.2):
					continue
				var pos := Vector3(p.x, 0, p.y)
				if rng.randf() < 0.12:
					# Árbol derribado hacia el camino, casi paralelo a él
					var fall := rad_to_deg(atan2(dir.x, dir.y)) + (180.0 if rng.randf() < 0.5 else 0.0)
					var off := rng.randf_range(5, 25)
					var fd := Vector2(sin(deg_to_rad(fall + off)), cos(deg_to_rad(fall + off)))
					fall += off if fd.dot(perp * sd) >= 0.0 else -off
					var fdir := Vector2(sin(deg_to_rad(fall)), cos(deg_to_rad(fall)))
					var blocks := false
					for k in [2.0, 4.5, 7.0, 9.5]:
						if _on_path(p + fdir * k, 0.6) or absf(p.y + fdir.y * k - AVENUE_Z) < 7.0:
							blocks = true
					if blocks:
						_wtree(pos, rng.randf_range(1.0, 1.35))
						continue
					_wtree(pos, rng.randf_range(1.0, 1.3), Vector3(84, fall, 0))
					for q in 4:
						_chunk(pos + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), 0.1, 0.35)
				else:
					_wtree(pos, rng.randf_range(1.0, 1.35))
			t += 13.0
	_end_zone()


# ================================================================ césped y recreación
# Jardines con pasto, pasto silvestre, zonas recreativas y relleno de huecos.

var m_lawn: ShaderMaterial
var m_grass: ShaderMaterial
var mesh_tuft: ArrayMesh
var m_court_blue: ShaderMaterial
var m_court_green: ShaderMaterial
var m_clay: ShaderMaterial
var m_rubber: ShaderMaterial
var m_sand: ShaderMaterial
var m_pool_deck: ShaderMaterial
var m_pool_water: ShaderMaterial
var m_red: StandardMaterial3D
var m_yellow: StandardMaterial3D
var m_blue: StandardMaterial3D
var m_orange: StandardMaterial3D
var mesh_rim: TorusMesh
var m_tent: StandardMaterial3D
var _tree_pts: Array = []
var _skipped_sites: PackedStringArray = []


func _make_recreation_materials() -> void:
	m_lawn = ShaderMaterial.new()
	m_lawn.shader = load("res://shaders/lawn.gdshader")
	m_lawn.set_shader_parameter("noise_tex", noise_tex)
	m_grass = ShaderMaterial.new()
	m_grass.shader = load("res://shaders/grass_tuft.gdshader")
	mesh_tuft = _make_tuft_mesh()
	m_court_blue = _concrete(Color(0.16, 0.27, 0.33), 0.55, 0.0)
	m_court_green = _concrete(Color(0.17, 0.3, 0.2), 0.55, 0.0)
	m_clay = _concrete(Color(0.48, 0.24, 0.14), 0.45, 0.05)
	m_rubber = _concrete(Color(0.33, 0.12, 0.08), 0.5, 0.0)
	m_sand = _concrete(Color(0.55, 0.48, 0.36), 0.35, 0.0)
	m_pool_deck = _tile(0, Vector2(0.6, 0.6), Color(0.55, 0.57, 0.56), Color(0.62, 0.64, 0.63), Color(0.2, 0.22, 0.22), 0.04, 0.6, 0.35)
	m_pool_water = ShaderMaterial.new()
	m_pool_water.shader = load("res://shaders/lake_water.gdshader")
	m_pool_water.set_shader_parameter("noise_tex", noise_tex)
	m_pool_water.set_shader_parameter("deep_color", Color(0.04, 0.08, 0.04))
	m_red = _std(Color(0.55, 0.08, 0.06), 0.5, 0.3)
	m_yellow = _std(Color(0.7, 0.55, 0.08), 0.5, 0.3)
	m_blue = _std(Color(0.08, 0.2, 0.5), 0.5, 0.3)
	m_orange = _std(Color(0.8, 0.35, 0.08), 0.6, 0.0)
	m_tent = _std(Color(0.42, 0.42, 0.37), 0.9, 0.0)
	m_tent.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_rim = TorusMesh.new()
	mesh_rim.inner_radius = 0.21
	mesh_rim.outer_radius = 0.24
	mesh_rim.rings = 16
	mesh_rim.ring_segments = 4
	mesh_rim.material = m_orange


func _make_tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for k in 9:
		var a := r.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.12)
		var h := r.randf_range(0.22, 0.5)
		var sa := r.randf() * TAU
		var side := Vector3(cos(sa), 0, sin(sa)) * r.randf_range(0.025, 0.05)
		var lean := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.03, 0.16)
		for v in [[off - side, Vector2(0, 0)], [off + side, Vector2(1, 0)], [off + lean + Vector3(0, h, 0), Vector2(0.5, 1)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var m := st.commit()
	m.surface_set_material(0, m_grass)
	return m


## Pasto 3D en una zona: MultiMesh propio (se oculta a distancia).
func _tufts(parent: Node3D, center: Vector3, pts: Array) -> void:
	if pts.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_tuft
	mm.instance_count = pts.size()
	for i in pts.size():
		var p: Vector3 = pts[i]
		var s := rng.randf_range(0.7, 1.5)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), p - center))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = center
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 75.0
	mmi.visibility_range_end_margin = 10.0
	parent.add_child(mmi)


## Jardín de pasto podado (losa con bordillo) y matas encima.
func _lawn(c: Vector3, size: Vector2, density := 0.9, edging := true, stripes := 0.35) -> void:
	var mat := m_lawn
	if stripes != 0.35:
		mat = m_lawn.duplicate()
		mat.set_shader_parameter("stripes", stripes)
		mat.set_shader_parameter("stripe_width", 5.0)
		mat.set_shader_parameter("bald", 0.1)
	_mm_add(_ub(mat), Transform3D(Basis.from_scale(Vector3(size.x, 0.03, size.y)), c))
	if edging:
		for s: float in [-1.0, 1.0]:
			_mm_add(_ub(m_concrete), Transform3D(Basis.from_scale(Vector3(size.x + 0.3, 0.12, 0.15)), c + Vector3(0, 0.04, s * size.y * 0.5)))
			_mm_add(_ub(m_concrete), Transform3D(Basis.from_scale(Vector3(0.15, 0.12, size.y + 0.3)), c + Vector3(s * size.x * 0.5, 0.04, 0)))
	var pts: Array = []
	var n := int(size.x * size.y * density)
	for i in n:
		var p := c + Vector3(rng.randf_range(-0.5, 0.5) * (size.x - 0.6), 0.0, rng.randf_range(-0.5, 0.5) * (size.y - 0.6))
		if _on_path(Vector2(p.x, p.z), 0.4):
			continue
		pts.append(p)
	_tufts(w_zone, c, pts)


func _on_path(p: Vector2, margin: float) -> bool:
	if _prefab_local:
		return false
	for s in _paths:
		var a: Vector2 = s[0]
		var e: Vector2 = s[1]
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, e)) < float(s[2]) * 0.5 + margin:
			return true
	return false


func _site_ok(c: Vector2, size: Vector2) -> bool:
	var nx := int(size.x / 4.0) + 1
	var nz := int(size.y / 4.0) + 1
	for i in nx + 1:
		for j in nz + 1:
			var p := c + Vector2(-size.x * 0.5 + size.x * i / nx, -size.y * 0.5 + size.y * j / nz)
			if not _is_free(p, 0.5):
				return false
	return true


func _reserve_rect(c: Vector2, size: Vector2) -> void:
	_blocked_rects.append(Rect2(c - size * 0.5, size))


## Prueba los candidatos y devuelve el primero libre (o Vector3.INF).
func _pick_site(title: String, cands: Array, size: Vector2) -> Vector3:
	for cand in cands:
		var c: Vector3 = cand
		if _site_ok(Vector2(c.x, c.z), size):
			_reserve_rect(Vector2(c.x, c.z), size)
			_extra_zones.push_front([Vector2(c.x, c.z), maxf(size.x, size.y) * 0.5 + 4.0, title])
			return c
	_skipped_sites.append(title)
	return Vector3.INF


func _fence_rect(c: Vector3, size: Vector2, h: float, gap_side := 1, gap := 4.0) -> void:
	var sides := [
		[Vector3(0, 0, -size.y * 0.5), Vector3(1, 0, 0), size.x],
		[Vector3(0, 0, size.y * 0.5), Vector3(1, 0, 0), size.x],
		[Vector3(-size.x * 0.5, 0, 0), Vector3(0, 0, 1), size.y],
		[Vector3(size.x * 0.5, 0, 0), Vector3(0, 0, 1), size.y],
	]
	for si in 4:
		var mid: Vector3 = c + sides[si][0]
		var dir: Vector3 = sides[si][1]
		var l: float = sides[si][2]
		var b := Basis(Vector3.UP, atan2(dir.x, dir.z))
		var n := int(l / 3.0)
		for k in n + 1:
			var t := -l * 0.5 + l * k / n
			if si == gap_side and absf(t) < gap * 0.5:
				continue
			var leanx := 0.0 if rng.randf() > 0.1 else rng.randf_range(-25, 25)
			_mm_add(_ub(m_iron), Transform3D(_rb(Vector3(leanx, 0, 0)) * Basis.from_scale(Vector3(0.07, h, 0.07)), mid + dir * t + Vector3(0, h * 0.5, 0)))
		for part: float in [-1.0, 1.0]:
			var seg_l := (l - (gap if si == gap_side else 0.0)) * 0.5
			var sc := mid + dir * part * (l * 0.5 - seg_l * 0.5)
			if si != gap_side:
				seg_l = l * 0.5
				sc = mid + dir * part * l * 0.25
			for y: float in [h - 0.05, h * 0.5]:
				if rng.randf() < 0.12:
					continue
				_mm_add(_ub(m_iron), Transform3D(b * Basis.from_scale(Vector3(0.05, 0.05, seg_l)), sc + Vector3(0, y, 0)))
			_wc(Vector3(0.15, h, seg_l), Transform3D(b, sc + Vector3(0, h * 0.5, 0)))


func _line_rect(c: Vector3, size: Vector2, y: float, w := 0.08) -> void:
	for s: float in [-1.0, 1.0]:
		_blk(c + Vector3(0, y, s * size.y * 0.5), Vector3(size.x + w, 0.012, w), m_line)
		_blk(c + Vector3(s * size.x * 0.5, y, 0), Vector3(w, 0.012, size.y), m_line)


func _line_arc(c: Vector3, r: float, a0: float, a1: float, y: float, segs := 16) -> void:
	for i in segs:
		var a := lerpf(a0, a1, (i + 0.5) / segs)
		var l := r * absf(a1 - a0) / segs + 0.02
		_blk(c + Vector3(sin(a) * r, y, cos(a) * r), Vector3(l, 0.012, 0.08), m_line, Vector3(0, rad_to_deg(a), 0))


func _picnic_table(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	if rng.randf() < 0.2:
		_lbox(p, b, Vector3(0, 0.5, 0), Vector3(1.8, 0.06, 0.8), m_wood, true, Vector3(80, 0, 0))
		return
	_lbox(p, b, Vector3(0, 0.75, 0), Vector3(1.8, 0.06, 0.8), m_wood)
	for s: float in [-1.0, 1.0]:
		_lbox(p, b, Vector3(0, 0.45, s * 0.75), Vector3(1.8, 0.05, 0.3), m_wood)
		_lbox(p, b, Vector3(s * 0.7, 0.37, 0), Vector3(0.08, 0.74, 1.7), m_wood, false, Vector3(0, 0, s * 4))
	_wc(Vector3(1.8, 0.8, 1.8), Transform3D(b, p + Vector3(0, 0.4, 0)))


func _grill(zone: Node3D, p: Vector3, lit: bool) -> void:
	_cy(p + Vector3(0, 0.75, 0), 0.35, 0.5, m_iron, Vector3(0, 0, 90), 10)
	for s: float in [-1.0, 1.0]:
		_rod(p + Vector3(s * 0.3, 0, 0.25), p + Vector3(s * 0.2, 0.6, 0), 0.025, m_iron)
		_rod(p + Vector3(s * 0.3, 0, -0.25), p + Vector3(s * 0.2, 0.6, 0), 0.025, m_iron)
	_wc(Vector3(0.9, 1.0, 0.8), Transform3D(Basis.IDENTITY, p + Vector3(0, 0.5, 0)))
	if lit:
		_fire(zone, p + Vector3(0, 1.0, 0), 0.35)


func _trash_bin(p: Vector3) -> void:
	var tipped := rng.randf() < 0.3
	_cy(p + Vector3(0, 0.3 if tipped else 0.45, 0), 0.28, 0.9, m_metal if rng.randf() < 0.5 else m_blue, Vector3(90 if tipped else 0, rng.randf_range(0, 360), 0), 10)
	if tipped:
		for q in 5:
			_mm_add(_ub(m_paper), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(0.25, 0.01, 0.3)), p + Vector3(rng.randf_range(-1.2, 1.2), 0.04, rng.randf_range(-1.2, 1.2))))


# ---------------------------------------------------------------- parque infantil

func _make_playground(c: Vector3) -> void:
	var zone := _begin_zone("ParqueInfantil")
	_lawn(c, Vector2(40, 22), 0.6)
	_blk(c + Vector3(-6, 0.0, 0), Vector3(22, 0.08, 16), m_rubber)
	# Columpios (uno roto)
	var sw := c + Vector3(-12, 0, -3)
	for sx: float in [-3.0, 3.0]:
		for sz: float in [-1.2, 1.2]:
			_rod(sw + Vector3(sx, 0, sz), sw + Vector3(sx, 2.6, 0), 0.06, m_red)
		_wc(Vector3(0.3, 2.6, 2.4), Transform3D(Basis.IDENTITY, sw + Vector3(sx, 1.3, 0)))
	_rod(sw + Vector3(-3, 2.6, 0), sw + Vector3(3, 2.6, 0), 0.07, m_red)
	for i in 3:
		var x := -1.8 + i * 1.8
		if i == 2:
			_rod(sw + Vector3(x, 2.6, -0.2), sw + Vector3(x + 0.3, 0.5, 0.0), 0.012, m_iron, 4)
			_blk(sw + Vector3(x + 0.35, 0.45, 0.0), Vector3(0.5, 0.05, 0.25), m_tire, Vector3(0, 10, 70))
			continue
		var swing := rng.randf_range(-10, 10)
		for z: float in [-0.2, 0.2]:
			_rod(sw + Vector3(x, 2.6, z), sw + Vector3(x, 0.55, z + swing * 0.02), 0.012, m_iron, 4)
		_blk(sw + Vector3(x, 0.55, swing * 0.02), Vector3(0.5, 0.05, 0.25), m_tire)
	# Resbaladilla con un osito de peluche
	var sl := c + Vector3(-3, 0, 3)
	for sx: float in [-0.6, 0.6]:
		for sz: float in [-0.6, 0.6]:
			_cy(sl + Vector3(sx, 1.0, sz), 0.05, 2.0, m_blue, Vector3.ZERO, 6)
	_blk(sl + Vector3(0, 2.0, 0), Vector3(1.3, 0.1, 1.3), m_yellow)
	for k in 6:
		_blk(sl + Vector3(0, 0.3 + k * 0.32, -0.75), Vector3(0.9, 0.04, 0.12), m_blue)
	var slide_len := 3.8
	var ang := rad_to_deg(atan2(1.7, 3.3))
	_blk(sl + Vector3(0, 1.15, 0.65 + 1.65), Vector3(0.7, 0.06, slide_len), m_yellow, Vector3(ang, 0, 0))
	for sx: float in [-0.37, 0.37]:
		_blk(sl + Vector3(sx, 1.3, 0.65 + 1.65), Vector3(0.05, 0.25, slide_len), m_yellow, Vector3(ang, 0, 0))
	_wc(Vector3(1.4, 2.1, 1.4), Transform3D(Basis.IDENTITY, sl + Vector3(0, 1.05, 0)))
	var bear := sl + Vector3(0.1, 0.25, 4.1)
	_sp(bear, Vector3(0.3, 0.35, 0.25), m_wood_dark)
	_sp(bear + Vector3(0, 0.27, 0), Vector3(0.22, 0.22, 0.22), m_wood_dark)
	for sx: float in [-0.08, 0.08]:
		_sp(bear + Vector3(sx, 0.38, 0), Vector3(0.08, 0.08, 0.06), m_wood_dark)
	# Sube y baja
	var ss := c + Vector3(5, 0, -6)
	_blk(ss + Vector3(0, 0.3, 0), Vector3(0.3, 0.6, 0.4), m_red, Vector3.ZERO, true)
	_blk(ss + Vector3(0, 0.45, 0), Vector3(3.6, 0.08, 0.3), m_yellow, Vector3(0, 0, 12))
	# Carrusel inclinado
	var mg := c + Vector3(5, 0, 5)
	_cy(mg + Vector3(0, 0.3, 0), 1.6, 0.15, m_red, Vector3(4, 0, 6), 20, 1.0, true)
	_cy(mg + Vector3(0, 0.75, 0), 0.08, 0.9, m_iron, Vector3.ZERO, 6)
	for q in 4:
		var a := TAU * q / 4.0
		_rod(mg + Vector3(0, 1.1, 0), mg + Vector3(cos(a) * 1.4, 0.45, sin(a) * 1.4), 0.03, m_iron, 4)
	# Pasamanos (escalador)
	var jg := c + Vector3(13, 0, -2)
	for ix in 3:
		for iz in 3:
			_cy(jg + Vector3(ix * 1.5 - 1.5, 1.1, iz * 1.5 - 1.5), 0.04, 2.2, m_blue, Vector3.ZERO, 6)
	for y: float in [1.0, 2.1]:
		for i in 3:
			_rod(jg + Vector3(-1.5, y, i * 1.5 - 1.5), jg + Vector3(1.5, y, i * 1.5 - 1.5), 0.03, m_blue, 4)
			_rod(jg + Vector3(i * 1.5 - 1.5, y, -1.5), jg + Vector3(i * 1.5 - 1.5, y, 1.5), 0.03, m_blue, 4)
	_wc(Vector3(3.2, 2.2, 3.2), Transform3D(Basis.IDENTITY, jg + Vector3(0, 1.1, 0)))
	# Arenero
	var sb := c + Vector3(13, 0, 6)
	for s: float in [-1.0, 1.0]:
		_blk(sb + Vector3(0, 0.15, s * 2.0), Vector3(4.2, 0.3, 0.2), m_wood)
		_blk(sb + Vector3(s * 2.0, 0.15, 0), Vector3(0.2, 0.3, 4.2), m_wood)
	_blk(sb + Vector3(0, 0.1, 0), Vector3(3.8, 0.2, 3.8), m_sand)
	_cy(sb + Vector3(0.6, 0.3, -0.4), 0.15, 0.25, m_red, Vector3(70, 30, 0), 10, 0.75)
	for q in 4:
		_bench(zone, c + Vector3(-18.0 + q * 12.0, 0, 10.0), 180.0, rng.randf() < 0.2)
	_trash_bin(c + Vector3(-17, 0, -9))
	_trash_bin(c + Vector3(17, 0, 9))
	_street_lamp(c + Vector3(0, 0, -10.5), 0.0, 0)
	_lbl(zone, "PARQUE INFANTIL", c + Vector3(-19.5, 2.2, 0), -90.0, 50, Color(0.85, 0.6, 0.25))
	_blk(c + Vector3(-19.6, 2.2, 0), Vector3(0.1, 0.8, 4.5), m_blue)
	_cy(c + Vector3(-19.6, 1.0, -2.0), 0.06, 2.0, m_iron)
	_cy(c + Vector3(-19.6, 1.0, 2.0), 0.06, 2.0, m_iron)
	_end_zone()


# ---------------------------------------------------------------- básquetbol

func _make_basketball(c: Vector3) -> void:
	var zone := _begin_zone("Basquetbol")
	_blk(c, Vector3(30, 0.08, 34), m_concrete_dark)
	for s: float in [-1.0, 1.0]:
		var cc := c + Vector3(0, 0, s * 8.5)
		_blk(cc, Vector3(28, 0.1, 15), m_court_blue)
		var y := 0.056
		_line_rect(cc, Vector2(28, 15), y)
		_blk(cc + Vector3(0, y, 0), Vector3(0.08, 0.012, 15), m_line)
		_line_arc(cc + Vector3(0, 0, 0), 1.8, 0.0, TAU, y, 20)
		for e: float in [-1.0, 1.0]:
			var basket := cc + Vector3(e * 12.4, 0, 0)
			_line_rect(cc + Vector3(e * 11.1, 0, 0), Vector2(5.8, 4.9), y)
			_line_arc(cc + Vector3(e * 8.2, 0, 0), 1.8, 0.0, TAU, y, 16)
			var a0 := -PI * 0.5 if e > 0.0 else PI * 0.5
			_line_arc(basket, 6.75, a0 - 1.25 * e, a0 + 1.25 * e - PI * e * 0.0, y, 24)
			# Tablero y aro (uno doblado)
			var pole := cc + Vector3(e * 15.0, 0, 0)
			var bent := s > 0.0 and e > 0.0
			if bent:
				_cy(pole + Vector3(-e * 1.2, 0.9, 1.0), 0.09, 3.6, m_iron, Vector3(70, 0, 0), 8)
				_blk(pole + Vector3(-e * 1.4, 0.6, 3.0), Vector3(0.05, 1.05, 1.8), m_glass, Vector3(20, 0, 85))
				continue
			_cy(pole + Vector3(0, 1.9, 0), 0.09, 3.8, m_iron, Vector3.ZERO, 8, 1.0, true)
			_rod(pole + Vector3(0, 3.6, 0), pole + Vector3(-e * 1.9, 3.4, 0), 0.06, m_iron)
			_blk(pole + Vector3(-e * 2.0, 3.4, 0), Vector3(0.05, 1.05, 1.8), m_glass_clear)
			_blk(pole + Vector3(-e * 2.0, 3.2, 0), Vector3(0.06, 0.45, 0.6), m_line)
			_mm_add(mesh_rim, Transform3D(Basis.IDENTITY, pole + Vector3(-e * 2.25, 3.05, 0)))
	_sp(c + Vector3(3.0, 0.15, 2.0), Vector3(0.24, 0.24, 0.24), m_orange)
	_fence_rect(c, Vector2(30, 34), 3.5, 3, 5.0)
	for k in 4:
		_blk(c + Vector3(-17.2, 0.25 + k * 0.4, -9.0 + 0.0), Vector3(0.6 + k * 0.0, 0.08, 12.0), m_wood)
	_street_lamp(c + Vector3(16.5, 0, 0), 90.0, 0)
	_end_zone()


# ---------------------------------------------------------------- tenis

func _make_tennis(c: Vector3) -> void:
	var zone := _begin_zone("Tenis")
	_blk(c, Vector3(54, 0.08, 17), m_clay)
	for s: float in [-1.0, 1.0]:
		var cc := c + Vector3(s * 13.5, 0, 0)
		var y := 0.05
		_line_rect(cc, Vector2(23.8, 11.0), y)
		_line_rect(cc, Vector2(23.8, 8.2), y)
		for e: float in [-1.0, 1.0]:
			_blk(cc + Vector3(e * 6.4, y, 0), Vector3(0.08, 0.012, 8.2), m_line)
		_blk(cc + Vector3(0, y, 0), Vector3(12.8, 0.012, 0.08), m_line)
		# Red (una caída)
		for e: float in [-1.0, 1.0]:
			_cy(cc + Vector3(0, 0.55, e * 6.3), 0.05, 1.1, m_iron, Vector3.ZERO, 6, 1.0, true)
		if s > 0.0:
			_blk(cc + Vector3(0.3, 0.35, 0), Vector3(0.03, 0.9, 12.6), m_tire, Vector3(0, 0, 55))
		else:
			_blk(cc + Vector3(0, 0.5, 0), Vector3(0.03, 0.9, 12.6), m_tire)
			_blk(cc + Vector3(0, 0.96, 0), Vector3(0.05, 0.06, 12.6), m_line)
		# Silla del juez
		var ch := cc + Vector3(0, 0, 7.4)
		for sx: float in [-0.4, 0.4]:
			_rod(ch + Vector3(sx, 0, -0.3), ch + Vector3(sx * 0.6, 1.8, 0), 0.03, m_iron, 4)
			_rod(ch + Vector3(sx, 0, 0.3), ch + Vector3(sx * 0.6, 1.8, 0), 0.03, m_iron, 4)
		_blk(ch + Vector3(0, 1.85, 0), Vector3(0.6, 0.06, 0.5), m_wood)
	for q in 6:
		_sp(c + Vector3(rng.randf_range(-26, 26), 0.06, rng.randf_range(-8, 8)), Vector3(0.07, 0.07, 0.07), m_yellow, Vector3.ZERO, 6)
	_fence_rect(c, Vector2(54, 17), 3.5, 1, 4.0)
	_end_zone()


# ---------------------------------------------------------------- skatepark

func _make_skatepark(c: Vector3) -> void:
	var zone := _begin_zone("Skatepark")
	_blk(c, Vector3(54, 0.1, 18), m_concrete)
	# Rampas de cuarto de tubo en los extremos
	for e: float in [-1.0, 1.0]:
		var base := c + Vector3(e * 24.5, 0, 0)
		var R := 3.0
		for k in 6:
			var a0 := PI * 0.5 * k / 6.0
			var a1 := PI * 0.5 * (k + 1) / 6.0
			var p0 := Vector3(-e * R * cos(a0), R - R * sin(a0 + PI * 0.5) + R * (1.0 - cos(a0)) * 0.0, 0)
			p0 = Vector3(-e * (R - R * sin(a0)), R - R * cos(a0), 0)
			var p1 := Vector3(-e * (R - R * sin(a1)), R - R * cos(a1), 0)
			var mid := (p0 + p1) * 0.5
			var d := p1 - p0
			var ang := rad_to_deg(atan2(d.y, absf(d.x)))
			_blk(base + mid, Vector3(d.length() + 0.05, 0.25, 14.0), m_concrete, Vector3(0, 0, ang * e), true)
		_blk(base + Vector3(e * 1.2, 1.5, 0), Vector3(2.4, 3.0, 14.0), m_concrete_dark, Vector3.ZERO, true)
		_rod(base + Vector3(-e * 0.05, 3.05, -7), base + Vector3(-e * 0.05, 3.05, 7), 0.05, m_iron, 6)
	# Funbox central con rampas y riel
	_blk(c + Vector3(0, 0.5, 0), Vector3(6, 1.0, 4), m_concrete_dark, Vector3.ZERO, true)
	for e: float in [-1.0, 1.0]:
		_blk(c + Vector3(e * 4.4, 0.47, 0), Vector3(3.0, 0.2, 4), m_concrete, Vector3(0, 0, -e * 18.0), true)
	_rod(c + Vector3(-3, 1.05, 2.2), c + Vector3(3, 1.05, 2.2), 0.04, m_iron, 6)
	_rod(c + Vector3(-6, 0.45, -5.5), c + Vector3(6, 0.45, -5.5), 0.04, m_iron, 6)
	for x: float in [-5.5, 0.0, 5.5]:
		_rod(c + Vector3(x, 0, -5.5), c + Vector3(x, 0.45, -5.5), 0.04, m_iron, 6)
	# Grafiti
	var tags := [["NO HAY CLASES", Color(1.0, 0.3, 0.6)], ["U.N.I. SK8", Color(0.2, 0.9, 1.0)], ["¿Y EL PROFE?", Color(1.0, 0.85, 0.2)], ["AQUÍ ESTUVO RUIZ", Color(0.5, 1.0, 0.3)]]
	_lbl(zone, tags[0][0], c + Vector3(-24.5 + 2.4 - 0.02, 1.6, 4.0), 90.0, 70, tags[0][1], true)
	_lbl(zone, tags[1][0], c + Vector3(24.5 - 2.4 + 0.02, 1.6, -3.0), -90.0, 70, tags[1][1], true)
	_lbl(zone, tags[2][0], c + Vector3(0, 0.55, 2.02), 0.0, 40, tags[2][1], true)
	_lbl(zone, tags[3][0], c + Vector3(0, 0.55, -2.02), 180.0, 40, tags[3][1], true)
	for q in 3:
		_blk(c + Vector3(rng.randf_range(-15, 15), 0.11, rng.randf_range(-6, 6)), Vector3(0.8, 0.03, 0.22), m_red, Vector3(0, rng.randf_range(0, 360), 0))
	_street_lamp(c + Vector3(-10, 0, 9.5), 0.0, 1)
	_street_lamp(c + Vector3(10, 0, 9.5), 0.0, 0)
	_end_zone()


# ---------------------------------------------------------------- estacionamientos

func _make_lot(c: Vector3, size: Vector2) -> void:
	var zone := _begin_zone("EstacionamientoExtra")
	_blk(c, Vector3(size.x, 0.08, size.y), m_asphalt)
	var colors := [Color(0.5, 0.05, 0.05), Color(0.1, 0.15, 0.3), Color(0.6, 0.6, 0.62), Color(0.15, 0.15, 0.15), Color(0.7, 0.65, 0.4), Color(0.2, 0.3, 0.22)]
	var horiz := size.x > size.y
	var along := Vector3(1, 0, 0) if horiz else Vector3(0, 0, 1)
	var across := Vector3(0, 0, 1) if horiz else Vector3(1, 0, 0)
	var long_len := maxf(size.x, size.y)
	var short_len := minf(size.x, size.y)
	var base_yaw := 90.0 if horiz else 0.0
	for side: float in [-1.0, 1.0]:
		var z := -long_len * 0.5 + 2.0
		while z < long_len * 0.5 - 2.0:
			if rng.randf() < 0.6:
				var roll := 0.0
				var r := rng.randf()
				if r < 0.08:
					roll = 180.0
				elif r < 0.14:
					roll = 90.0
				var burnt := rng.randf() < 0.25
				var pos := c + across * (side * (short_len * 0.5 - 2.6) + rng.randf_range(-0.3, 0.3)) + along * z
				_car(zone, pos, base_yaw + rng.randf_range(-8, 8) + (0.0 if side > 0.0 else 180.0), roll, colors[rng.randi() % colors.size()], burnt)
				if burnt and rng.randf() < 0.3:
					_fire(zone, pos + Vector3(0, 1.1, 0), 0.6)
			z += 2.8
	var n := maxi(1, int(long_len / 25.0))
	for k in n:
		_street_lamp(c + along * (-long_len * 0.5 + (k + 0.5) * long_len / n), base_yaw + (90.0 if k % 2 == 0 else -90.0), 0 if k % 2 == 0 else 1)
	_end_zone()


# ---------------------------------------------------------------- gimnasio y picnic

func _make_park_gym(c: Vector3) -> void:
	var zone := _begin_zone("Gimnasio")
	_lawn(c, Vector2(52, 24), 0.7)
	var g := c + Vector3(-14, 0, 0)
	_blk(g, Vector3(18, 0.08, 12), m_rubber)
	# Barra de dominadas
	for sx: float in [-1.0, 1.0]:
		_cy(g + Vector3(-5 + sx, 1.2, -3), 0.06, 2.4, m_metal_light, Vector3.ZERO, 6, 1.0, true)
	_rod(g + Vector3(-6, 2.3, -3), g + Vector3(-4, 2.3, -3), 0.03, m_metal_light, 6)
	# Paralelas
	for sz: float in [-0.3, 0.3]:
		_rod(g + Vector3(0, 1.2, -3 + sz), g + Vector3(3, 1.2, -3 + sz), 0.03, m_metal_light, 6)
		for sx: float in [0.0, 3.0]:
			_rod(g + Vector3(sx, 0, -3 + sz), g + Vector3(sx, 1.2, -3 + sz), 0.04, m_metal_light, 6)
	# Pasamanos horizontales
	for sz: float in [-0.5, 0.5]:
		_rod(g + Vector3(-5, 2.2, 3 + sz), g + Vector3(3, 2.2, 3 + sz), 0.04, m_metal_light, 6)
		for sx: float in [-5.0, 3.0]:
			_rod(g + Vector3(sx, 0, 3 + sz), g + Vector3(sx, 2.2, 3 + sz), 0.05, m_metal_light, 6)
	for k in 9:
		_rod(g + Vector3(-5 + k, 2.2, 2.5), g + Vector3(-5 + k, 2.2, 3.5), 0.025, m_metal_light, 4)
	_wc(Vector3(8.2, 2.2, 1.2), Transform3D(Basis.IDENTITY, g + Vector3(-1, 1.1, 3)))
	# Banca de abdominales inclinada
	_blk(g + Vector3(6, 0.45, 0), Vector3(1.6, 0.08, 0.5), m_wood, Vector3(0, 0, 18), true)
	# Picnic
	for q in 6:
		_picnic_table(c + Vector3(6.0 + (q % 3) * 6.0, 0, -5.0 + (q / 3) * 9.0), rng.randf_range(-20, 20))
	_grill(zone, c + Vector3(22, 0, 8), true)
	_grill(zone, c + Vector3(22, 0, -8), false)
	# Palapa
	var pal := c + Vector3(12, 0, 0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_cy(pal + Vector3(sx * 2.5, 1.4, sz * 2.5), 0.12, 2.8, m_wood, Vector3.ZERO, 6, 1.0, true)
	_mm_add(_uc(m_canvas, 4, 0.0), Transform3D(_rb(Vector3(4, 45, 0)) * Basis.from_scale(Vector3(8.5, 1.6, 8.5)), pal + Vector3(0, 3.6, 0)))
	_trash_bin(c + Vector3(0, 0, 10))
	_trash_bin(c + Vector3(24, 0, 0))
	_end_zone()


func _make_picnic(c: Vector3, size: Vector2) -> void:
	var zone := _begin_zone("Picnic")
	_lawn(c, size, 0.7, false)
	var n := 8
	for q in n:
		var p := c + Vector3(-size.x * 0.5 + 4.0 + q * (size.x - 8.0) / (n - 1), 0, rng.randf_range(-3, 3))
		_picnic_table(p, rng.randf_range(-30, 30))
	_grill(zone, c + Vector3(-12, 0, 5.5), false)
	_grill(zone, c + Vector3(10, 0, -5.5), true)
	_mm_add(_uc(m_canvas, 4, 0.0), Transform3D(_rb(Vector3(0, 45, 0)) * Basis.from_scale(Vector3(7.0, 1.5, 7.0)), c + Vector3(0, 2.9, 0)))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_cy(c + Vector3(sx * 2.0, 1.1, sz * 2.0), 0.08, 2.2, m_iron, Vector3.ZERO, 6)
	_trash_bin(c + Vector3(size.x * 0.5 - 2, 0, 0))
	_trash_bin(c + Vector3(-size.x * 0.5 + 2, 0, 0))
	_end_zone()


# ---------------------------------------------------------------- foro y esculturas

func _make_theater(c: Vector3) -> void:
	var zone := _begin_zone("Foro")
	var stage := c + Vector3(0, 0, -9.0)
	_blk(stage + Vector3(0, 0.5, 0), Vector3(14, 1.0, 7), m_wood_dark, Vector3.ZERO, true)
	_blk(stage + Vector3(0, 3.6, -3.6), Vector3(16, 7.2, 0.5), m_concrete, Vector3.ZERO, true)
	for sx: float in [-1.0, 1.0]:
		_blk(stage + Vector3(sx * 7.8, 3.6, -2.0), Vector3(0.6, 7.2, 3.6), m_concrete, Vector3.ZERO, true)
		_blk(stage + Vector3(sx * 6.4, 3.5, -2.2), Vector3(2.4, 5.0, 0.08), m_red, Vector3(0, sx * 10.0, rng.randf_range(-3, 3)))
	_blk(stage + Vector3(0, 7.4, -1.6), Vector3(16, 0.4, 4.4), m_concrete, Vector3(3, 0, 0))
	_blk(stage + Vector3(3.5, 1.4, -0.5), Vector3(1.6, 0.8, 0.6), m_tire, Vector3(0, 20, 0))
	_blk(stage + Vector3(1.8, 1.1, 1.5), Vector3(1.4, 0.15, 0.5), m_tire, Vector3(0, 40, 75))
	_lbl(zone, "FORO AL AIRE LIBRE", stage + Vector3(0, 6.0, -3.33), 0.0, 60, Color(0.85, 0.8, 0.65))
	# Gradas en abanico mirando al escenario
	for k in 5:
		var r := 7.0 + k * 1.6
		var h := 0.35 * (k + 1)
		var segs := 14
		for i in segs:
			var a := lerpf(-1.15, 1.15, (i + 0.5) / segs)
			if absf(a) < 0.12:
				continue
			var p := stage + Vector3(sin(a) * r, h * 0.5, cos(a) * r)
			_blk(p, Vector3(2.0 * r * 1.15 / segs * 2.0 * 0.5 + 0.1, h, 1.6), m_stone_light, Vector3(0, rad_to_deg(a), 0), true)
	_omni(zone, stage + Vector3(0, 4.0, 3.0), Color(1.0, 0.75, 0.45), 1.2, 12.0, 0.05)
	_end_zone()


func _make_sculptures(c: Vector3) -> void:
	var zone := _begin_zone("Esculturas")
	_lawn(c, Vector2(32, 28), 0.6)
	var spots := [Vector3(-9, 0, -8), Vector3(0, 0, -9), Vector3(9, 0, -7), Vector3(-9, 0, 6), Vector3(1, 0, 4), Vector3(10, 0, 8)]
	for i in spots.size():
		var p: Vector3 = c + spots[i]
		_blk(p + Vector3(0, 0.4, 0), Vector3(2.4, 0.8, 2.4), m_stone, Vector3.ZERO, true)
		var t := p + Vector3(0, 0.8, 0)
		match i:
			0:
				for k in 4:
					_blk(t + Vector3(0, 0.5 + k * 0.9, 0), Vector3(1.2 - k * 0.2, 0.9, 1.2 - k * 0.2), m_bronze, Vector3(0, k * 22.0, k * 5.0))
			1:
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 1.3
				tm.outer_radius = 1.7
				tm.material = m_bronze
				ring.mesh = tm
				ring.position = t + Vector3(0, 1.8, 0)
				ring.rotation_degrees = Vector3(90, 30, 0)
				zone.add_child(ring)
			2:
				_blk(t + Vector3(0, 2.2, 0), Vector3(0.6, 4.6, 0.6), m_metal_light, Vector3(14, 30, 8))
			3:
				_cy(t + Vector3(0, 1.0, 0), 0.25, 2.0, m_stone_light)
				_sp(t + Vector3(0, 2.6, 0), Vector3(1.4, 1.4, 1.4), m_gold)
			4:
				# Pensador
				_sp(t + Vector3(0, 0.6, 0), Vector3(0.9, 1.2, 0.8), m_bronze)
				_sp(t + Vector3(0, 1.45, 0.25), Vector3(0.45, 0.5, 0.45), m_bronze)
				_rod(t + Vector3(0.25, 0.9, 0.3), t + Vector3(0.1, 1.3, 0.45), 0.09, m_bronze)
			_:
				# Cabeza monumental caída
				_sp(p + Vector3(2.0, 1.0, 1.5), Vector3(2.2, 2.6, 2.2), m_stone_light, Vector3(70, 30, 0))
				_cy(t + Vector3(0, 0.5, 0), 0.6, 1.0, m_stone_light)
	_bench(zone, c + Vector3(0, 0, 12), 180.0, false)
	_bench(zone, c + Vector3(-12, 0, 0), 90.0, true)
	_end_zone()


# ---------------------------------------------------------------- alberca

func _make_pool(c: Vector3) -> void:
	var zone := _begin_zone("Alberca")
	_blk(c, Vector3(30, 0.1, 22), m_pool_deck)
	var pw := 25.0
	var pd := 12.0
	for s: float in [-1.0, 1.0]:
		_blk(c + Vector3(0, 0.5, s * (pd * 0.5 + 0.2)), Vector3(pw + 0.8, 1.0, 0.4), m_white_lab, Vector3.ZERO, true)
		_blk(c + Vector3(s * (pw * 0.5 + 0.2), 0.5, 0), Vector3(0.4, 1.0, pd), m_white_lab, Vector3.ZERO, true)
	_blk(c + Vector3(0, 0.3, 0), Vector3(pw, 0.6, pd), m_labtile)
	_mm_add(_ub(m_pool_water), Transform3D(Basis.from_scale(Vector3(pw, 0.04, pd)), c + Vector3(0, 0.62, 0)))
	_wc(Vector3(pw, 1.0, pd), Transform3D(Basis.IDENTITY, c + Vector3(0, 0.5, 0)))
	for k in 3:
		var z := -pd * 0.5 + (k + 1) * pd / 4.0
		for q in 30:
			_sp(c + Vector3(-pw * 0.5 + 0.4 + q * (pw - 0.8) / 29.0, 0.64, z), Vector3(0.12, 0.08, 0.12), m_red if q % 2 == 0 else m_line, Vector3.ZERO, 6)
	# Trampolín, escalera y silla de salvavidas
	_blk(c + Vector3(-pw * 0.5 - 0.6, 0.5, 2.5), Vector3(1.0, 1.0, 0.8), m_concrete, Vector3.ZERO, true)
	_blk(c + Vector3(-pw * 0.5 + 1.2, 1.05, 2.5), Vector3(3.2, 0.08, 0.5), m_line, Vector3(0, 0, -4))
	for sz: float in [-0.3, 0.3]:
		_rod(c + Vector3(pw * 0.5 - 0.2, 0.6, -2 + sz), c + Vector3(pw * 0.5 + 0.3, 1.5, -2 + sz), 0.03, m_metal_light, 6)
	var lg := c + Vector3(0, 0, pd * 0.5 + 2.5)
	for sx: float in [-0.4, 0.4]:
		_rod(lg + Vector3(sx, 0, -0.4), lg + Vector3(sx * 0.7, 2.2, 0), 0.04, m_line, 4)
		_rod(lg + Vector3(sx, 0, 0.4), lg + Vector3(sx * 0.7, 2.2, 0), 0.04, m_line, 4)
	_blk(lg + Vector3(0, 2.25, 0), Vector3(0.7, 0.08, 0.6), m_red)
	# Camastros, uno flotando en el agua
	for q in 5:
		var p := c + Vector3(-12.0 + q * 6.0, 0, -pd * 0.5 - 2.5)
		_blk(p + Vector3(0, 0.3, 0), Vector3(0.7, 0.08, 1.9), m_line, Vector3(0, rng.randf_range(-15, 15), 8 if q == 2 else 0))
	_blk(c + Vector3(4, 0.65, 2), Vector3(0.7, 0.08, 1.9), m_line, Vector3(10, 40, 12))
	_fence_rect(c, Vector2(30, 22), 2.2, 1, 3.0)
	_lbl(zone, "ALBERCA UNIVERSITARIA · CERRADA", c + Vector3(0, 1.8, 11.08), 0.0, 36, Color(0.75, 0.85, 0.9))
	_blk(c + Vector3(0, 1.8, 11.05), Vector3(7.0, 0.6, 0.04), m_blue)
	_end_zone()


# ---------------------------------------------------------------- huerto, voleibol y futbolito

func _make_huerto(c: Vector3) -> void:
	var zone := _begin_zone("Huerto")
	_lawn(c, Vector2(36, 26), 0.5, false)
	var pts: Array = []
	for i in 4:
		for j in 2:
			var bp := c + Vector3(-12.0 + i * 5.0, 0, -7.0 + j * 5.0)
			for s: float in [-1.0, 1.0]:
				_blk(bp + Vector3(0, 0.25, s * 0.75), Vector3(3.8, 0.5, 0.1), m_wood)
				_blk(bp + Vector3(s * 1.9, 0.25, 0), Vector3(0.1, 0.5, 1.5), m_wood)
			_blk(bp + Vector3(0, 0.22, 0), Vector3(3.7, 0.44, 1.4), m_debris)
			_wc(Vector3(3.9, 0.5, 1.6), Transform3D(Basis.IDENTITY, bp + Vector3(0, 0.25, 0)))
			for q in 18:
				pts.append(bp + Vector3(rng.randf_range(-1.7, 1.7), 0.44, rng.randf_range(-0.6, 0.6)))
			if (i + j) % 2 == 0:
				for q in 5:
					var cp := bp + Vector3(-1.5 + q * 0.75, 0.44, rng.randf_range(-0.3, 0.3))
					_rod(cp, cp + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(1.2, 1.8), rng.randf_range(-0.3, 0.3)), 0.03, m_wood, 4)
	_tufts(zone, c, pts)
	# Invernadero
	var gh := c + Vector3(8.0, 0, 3.0)
	var gw := 10.0
	var gd := 6.0
	for k in 6:
		var x := -gw * 0.5 + k * gw / 5.0
		for s: float in [-1.0, 1.0]:
			_rod(gh + Vector3(x, 0, s * gd * 0.5), gh + Vector3(x, 2.4, s * gd * 0.5), 0.04, m_metal_light, 4)
			_rod(gh + Vector3(x, 2.4, s * gd * 0.5), gh + Vector3(x, 3.4, 0), 0.04, m_metal_light, 4)
	for s: float in [-1.0, 1.0]:
		for k in 5:
			if rng.randf() < 0.35:
				continue
			var x := -gw * 0.5 + (k + 0.5) * gw / 5.0
			_blk(gh + Vector3(x, 1.2, s * gd * 0.5), Vector3(gw / 5.0, 2.4, 0.03), m_glass_clear)
			_blk(gh + Vector3(x, 2.9, s * gd * 0.25), Vector3(gw / 5.0, 0.03, gd * 0.55), m_glass_clear, Vector3(-s * 18.4, 0, 0))
	_wc(Vector3(gw, 2.4, 0.1), Transform3D(Basis.IDENTITY, gh + Vector3(0, 1.2, -gd * 0.5)))
	_wc(Vector3(0.1, 2.4, gd), Transform3D(Basis.IDENTITY, gh + Vector3(gw * 0.5, 1.2, 0)))
	_blk(gh + Vector3(0, 0.8, -1.5), Vector3(gw - 1.0, 0.06, 1.0), m_wood)
	# Tinaco y espantapájaros
	_cy(c + Vector3(-15, 1.6, 9), 1.0, 1.6, m_tire, Vector3.ZERO, 16, 1.0, true)
	_cy(c + Vector3(-15, 0.4, 9), 0.9, 0.8, m_concrete_dark, Vector3.ZERO, 16)
	var sc := c + Vector3(0, 0, 8)
	_rod(sc, sc + Vector3(0, 2.2, 0), 0.05, m_wood, 4)
	_rod(sc + Vector3(-0.9, 1.7, 0), sc + Vector3(0.9, 1.7, 0), 0.04, m_wood, 4)
	_blk(sc + Vector3(0, 1.45, 0), Vector3(0.7, 0.8, 0.3), m_canvas)
	_sp(sc + Vector3(0, 2.3, 0), Vector3(0.35, 0.4, 0.35), m_sandbag)
	_mm_add(_uc(m_wood_dark, 10, 0.0), Transform3D(Basis.from_scale(Vector3(0.9, 0.35, 0.9)), sc + Vector3(0, 2.6, 0)))
	_end_zone()


func _make_volleyball(c: Vector3) -> void:
	_begin_zone("Voleibol")
	_blk(c, Vector3(24, 0.12, 16), m_sand)
	_line_rect(c, Vector2(18, 9), 0.065, 0.06)
	for s: float in [-1.0, 1.0]:
		_cy(c + Vector3(0, 1.25, s * 5.0), 0.06, 2.5, m_iron, Vector3.ZERO, 6, 1.0, true)
	_blk(c + Vector3(0, 2.1, 0), Vector3(0.03, 0.9, 10.0), m_tire, Vector3(0 if rng.randf() < 0.5 else 12, 0, 0))
	_sp(c + Vector3(-4, 0.2, 2), Vector3(0.22, 0.22, 0.22), m_line)
	_end_zone()


func _make_futbolito(c: Vector3) -> void:
	_begin_zone("Futbolito")
	_lawn(c, Vector2(40, 24), 0.5, false, 0.8)
	_line_rect(c, Vector2(36, 20), 0.04)
	_blk(c + Vector3(0, 0.04, 0), Vector3(0.08, 0.012, 20), m_line)
	_line_arc(c, 3.0, 0.0, TAU, 0.04, 20)
	for e: float in [-1.0, 1.0]:
		var g := c + Vector3(e * 18.0, 0, 0)
		for z: float in [-1.5, 1.5]:
			_cy(g + Vector3(0, 1.0, z), 0.05, 2.0, m_line, Vector3.ZERO, 6, 1.0, true)
		_rod(g + Vector3(0, 2.0, -1.5), g + Vector3(0, 2.0, 1.5), 0.05, m_line, 6)
	_fence_rect(c, Vector2(40, 24), 3.0, 0, 4.0)
	_end_zone()


# ---------------------------------------------------------------- relleno

## Llena las celdas que siguen vacías: jardincitos con bancas, mesas de picnic,
## autos abandonados, puestos ambulantes, botes de basura y faroles.
func _make_filler() -> void:
	var zone := _begin_zone("Relleno")
	var colors := [Color(0.5, 0.05, 0.05), Color(0.1, 0.15, 0.3), Color(0.6, 0.6, 0.62), Color(0.15, 0.15, 0.15), Color(0.7, 0.65, 0.4)]
	var cell := 14.0
	var x := BOUNDS.position.x + cell * 0.5
	while x < BOUNDS.end.x:
		var z := BOUNDS.position.y + cell * 0.5
		while z < BOUNDS.end.y:
			var p := Vector2(x + rng.randf_range(-3, 3), z + rng.randf_range(-3, 3))
			z += cell
			if not _is_free(p, 4.0) or _near_tree(p, 4.0):
				continue
			var pos := Vector3(p.x, 0, p.y)
			var roll := rng.randf()
			if roll < 0.14:
				# Autos abandonados
				for k in rng.randi_range(1, 2):
					var cp := pos + Vector3(rng.randf_range(-2.5, 2.5), 0, k * 3.2)
					var r := rng.randf()
					_car(zone, cp, rng.randf_range(0, 360), 180.0 if r < 0.1 else (90.0 if r < 0.18 else 0.0), colors[rng.randi() % colors.size()], rng.randf() < 0.4)
				if rng.randf() < 0.1:
					_fire(zone, pos + Vector3(0, 1.1, 0), 0.6)
			elif roll < 0.30:
				# Jardincito con banca y bote
				var sz := Vector2(rng.randf_range(6, 10), rng.randf_range(5, 8))
				_lawn(pos, sz, 0.9)
				_bench(zone, pos + Vector3(0, 0, sz.y * 0.5 - 1.0), 180.0, rng.randf() < 0.25)
				_trash_bin(pos + Vector3(sz.x * 0.5 - 1.0, 0, sz.y * 0.5 - 1.0))
			elif roll < 0.40:
				_picnic_table(pos, rng.randf_range(0, 180))
				if rng.randf() < 0.5:
					_picnic_table(pos + Vector3(3.5, 0, 1.0), rng.randf_range(0, 180))
				_trash_bin(pos + Vector3(-2.0, 0, 1.5))
			elif roll < 0.47:
				_stall(zone, pos, rng.randf_range(0, 360))
			elif roll < 0.52:
				_street_lamp(pos, rng.randf_range(0, 360), 0 if rng.randf() < 0.2 else (1 if rng.randf() < 0.6 else 2))
			elif roll < 0.58:
				_trash_bin(pos)
				for q in 6:
					_chunk(pos + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)), 0.15, 0.6)
		x += cell
	_end_zone()


func _near_tree(p: Vector2, r: float) -> bool:
	for t in _tree_pts:
		if p.distance_squared_to(t) < r * r:
			return true
	return false


## Puesto ambulante de comida con lona.
func _stall(zone: Node3D, p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var tipped := rng.randf() < 0.3
	_lbox(p, b, Vector3(0, 0.5, 0), Vector3(2.2, 1.0, 1.0), m_metal_light, true)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			if tipped and sx > 0.0:
				continue
			_lbox(p, b, Vector3(sx * 1.05, 1.25, sz * 0.75), Vector3(0.05, 2.5, 0.05), m_iron)
	var canvas: Material = [m_red, m_blue, m_yellow, m_canvas][rng.randi() % 4]
	if tipped:
		_lbox(p, b, Vector3(1.0, 1.4, 0), Vector3(2.6, 0.04, 1.9), canvas, false, Vector3(0, 0, -35))
	else:
		_lbox(p, b, Vector3(0, 2.5, 0), Vector3(2.6, 0.04, 1.9), canvas, false, Vector3(6, 0, 0))
	_lbl(zone, ["TACOS", "ELOTES", "CAFÉ", "TORTAS", "JUGOS"][rng.randi() % 5], p + b * Vector3(0, 0.7, 0.52), yaw, 30, Color(0.95, 0.9, 0.7))
	for q in 3:
		_cy(p + b * Vector3(rng.randf_range(-1.5, 1.5), 0.25, rng.randf_range(0.9, 1.6)), 0.2, 0.45, m_red, Vector3(0, 0, 90 if rng.randf() < 0.4 else 0), 8)


## Pasto silvestre en todo el terreno libre, en bloques de 40 m.
func _make_wild_grass() -> void:
	var zone := _begin_zone("PastoSilvestre")
	var chunk := 40.0
	var x := BOUNDS.position.x
	while x < BOUNDS.end.x:
		var z := BOUNDS.position.y
		while z < BOUNDS.end.y:
			var center := Vector3(x + chunk * 0.5, 0, z + chunk * 0.5)
			var pts: Array = []
			for i in int(chunk * chunk * 0.22):
				var p := Vector2(x + rng.randf() * chunk, z + rng.randf() * chunk)
				if _is_free(p, 0.6):
					pts.append(Vector3(p.x, 0, p.y))
			_tufts(zone, center, pts)
			z += chunk
		x += chunk
	_end_zone()


# ---------------------------------------------------------------- más zonas

## Memorial improvisado: muro de fotos, veladoras, flores y cruces.
func _make_memorial(c: Vector3) -> void:
	var zone := _begin_zone("Memorial")
	_lawn(c, Vector2(32, 28), 0.6, false)
	var wall := c + Vector3(0, 0, -9)
	_blk(wall + Vector3(0, 1.3, 0), Vector3(14, 2.6, 0.5), m_concrete, Vector3.ZERO, true)
	_lbl(zone, "NUNCA OLVIDAREMOS", wall + Vector3(0, 2.3, 0.27), 0.0, 48, Color(0.85, 0.82, 0.75))
	for q in 70:
		var tint := Color(rng.randf_range(0.5, 0.9), rng.randf_range(0.45, 0.85), rng.randf_range(0.4, 0.8))
		_mmc_add(_ub(m_book), Transform3D(Basis(Vector3.BACK, deg_to_rad(rng.randf_range(-12, 12))) * Basis.from_scale(Vector3(0.22, 0.28, 0.01)), wall + Vector3(rng.randf_range(-6.6, 6.6), rng.randf_range(0.3, 1.9), 0.26)), tint)
	var flame := _us(m_eye, 6)
	for q in 140:
		var p := wall + Vector3(rng.randf_range(-6.5, 6.5), 0, rng.randf_range(0.6, 3.0))
		var h := rng.randf_range(0.08, 0.2)
		_mm_add(_uc(m_paper, 8), Transform3D(Basis.from_scale(Vector3(0.08, h, 0.08)), p + Vector3(0, h * 0.5, 0)))
		if rng.randf() < 0.7:
			_mm_add(flame, Transform3D(Basis.from_scale(Vector3(0.03, 0.06, 0.03)), p + Vector3(0, h + 0.03, 0)))
	for q in 50:
		var col: Material = [m_red, m_yellow, m_line, m_orange][rng.randi() % 4]
		_sp(wall + Vector3(rng.randf_range(-6.8, 6.8), 0.06, rng.randf_range(0.3, 1.0)), Vector3(0.12, 0.08, 0.12), col, Vector3.ZERO, 6)
	_omni(zone, wall + Vector3(0, 0.6, 1.6), Color(1.0, 0.65, 0.3), 2.0, 9.0, 0.0, 8.0)
	for i in 6:
		for j in 4:
			var p := c + Vector3(-12.5 + i * 5.0, 0, 1.0 + j * 3.0)
			_blk(p + Vector3(0, 0.6, 0), Vector3(0.12, 1.2, 0.08), m_stone_light, Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)))
			_blk(p + Vector3(0, 0.9, 0), Vector3(0.6, 0.1, 0.08), m_stone_light)
	_end_zone()


## Frontones: muros altos de concreto para jugar pelota.
func _make_fronton(c: Vector3) -> void:
	var zone := _begin_zone("Fronton")
	for s: float in [-1.0, 1.0]:
		var fc := c + Vector3(s * 7.5, 0, 0)
		_blk(fc, Vector3(13, 0.1, 32), m_court_green)
		_line_rect(fc + Vector3(0, 0, 2), Vector2(12, 26), 0.056)
		_blk(fc + Vector3(0, 0.056, -4), Vector3(12, 0.012, 0.08), m_line)
		_blk(fc + Vector3(0, 5.0, -15.5), Vector3(13, 10.0, 1.0), m_concrete, Vector3.ZERO, true)
		_blk(fc + Vector3(0, 0.9, -14.95), Vector3(13, 0.06, 0.08), m_red)
		_lbl(zone, "FRONTÓN %d" % (1 if s < 0.0 else 2), fc + Vector3(0, 8.5, -14.98), 0.0, 90, Color(0.15, 0.15, 0.15))
	_blk(c + Vector3(-14.5, 4.0, -8), Vector3(1.0, 8.0, 15), m_concrete, Vector3.ZERO, true)
	if rng.randf() < 1.0:
		_blk(c + Vector3(14.5, 2.0, -11), Vector3(1.0, 4.0, 9), m_concrete, Vector3.ZERO, true)
		for q in 8:
			_chunk(c + Vector3(rng.randf_range(12, 16), 0, rng.randf_range(-6, 0)), 0.3, 1.0)
	_sp(c + Vector3(-5, 0.08, 4), Vector3(0.12, 0.12, 0.12), m_blue)
	_sp(c + Vector3(6, 0.08, -2), Vector3(0.12, 0.12, 0.12), m_blue)
	_end_zone()


func _bus_upright(zone: Node3D, p: Vector3, yaw: float, burnt: bool) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var body: Material = m_burnt if burnt else [m_yellow, m_blue, m_line][rng.randi() % 3]
	_lbox(p, b, Vector3(0, 1.75, 0), Vector3(11, 2.6, 2.6), body, true)
	_lbox(p, b, Vector3(0.6, 2.25, 0), Vector3(9.6, 0.9, 2.64), m_glass)
	_lbox(p, b, Vector3(5.52, 2.0, 0), Vector3(0.05, 1.4, 2.3), m_glass)
	for wx: float in [-3.6, 3.6]:
		for wz: float in [-1.15, 1.15]:
			_mm_add(_uc(m_tire, 12), Transform3D(b * _rb(Vector3(90, 0, 0)) * Basis.from_scale(Vector3(1.0, 0.3, 1.0)), p + b * Vector3(wx, 0.5, wz)))
	if burnt:
		_fire(zone, p + b * Vector3(-2.0, 3.2, 0), 0.9)
		_smoke(zone, p + b * Vector3(-2.0, 4.0, 0), 0.6)
	else:
		_lbl(zone, "TRANSPORTE UNIVERSITARIO", p + b * Vector3(0, 1.0, 1.32), yaw, 40, Color(0.1, 0.1, 0.1))


## Terminal de autobuses del campus.
func _make_terminal(c: Vector3) -> void:
	var zone := _begin_zone("Terminal")
	_blk(c, Vector3(54, 0.08, 18), m_asphalt)
	_blk(c + Vector3(0, 0.06, -7.0), Vector3(52, 0.12, 3.0), m_concrete)
	for k in 7:
		_cy(c + Vector3(-24 + k * 8.0, 1.6, -7.8), 0.12, 3.2, m_iron, Vector3.ZERO, 8, 1.0, true)
	_blk(c + Vector3(0, 3.25, -7.0), Vector3(52, 0.2, 4.0), m_metal, Vector3(0, 0, rng.randf_range(-2, 2)))
	for k in 6:
		_blk(c + Vector3(-20 + k * 8.0, 0.55, -7.8), Vector3(2.4, 0.08, 0.45), m_wood)
	_bus_upright(zone, c + Vector3(-15, 0, -1.5), 0.0, false)
	_bus_upright(zone, c + Vector3(2, 0, -1.8), 4.0, true)
	_bus_upright(zone, c + Vector3(17, 0, 2.5), 160.0, false)
	_lbl(zone, "TERMINAL DE AUTOBUSES", c + Vector3(0, 3.6, -4.95), 0.0, 60, Color(0.85, 0.85, 0.8))
	_street_lamp(c + Vector3(-26, 0, 7.5), 0.0, 0)
	_street_lamp(c + Vector3(26, 0, 7.5), 0.0, 1)
	_end_zone()


## Puesto de rescate abandonado con helipuerto y helicóptero estrellado.
func _make_rescue_camp(c: Vector3) -> void:
	var zone := _begin_zone("PuestoDeRescate")
	var hp := c + Vector3(-6, 0, 0)
	_cy(hp, 8.0, 0.1, m_concrete, Vector3.ZERO, 32)
	_line_arc(hp, 6.8, 0.0, TAU, 0.06, 32)
	_blk(hp + Vector3(-1.4, 0.06, 0), Vector3(0.6, 0.012, 4.0), m_line)
	_blk(hp + Vector3(1.4, 0.06, 0), Vector3(0.6, 0.012, 4.0), m_line)
	_blk(hp + Vector3(0, 0.06, 0), Vector3(2.4, 0.012, 0.6), m_line)
	# Helicóptero estrellado, de lado
	var hc := c + Vector3(8, 0, -6)
	var hb := _rb(Vector3(0, 35, 70))
	var body := _std(Color(0.18, 0.22, 0.14), 0.5, 0.4)
	_sp(hc + Vector3(0, 1.3, 0), Vector3(2.2, 2.3, 4.4), body, Vector3(0, 35, 70), 14)
	_mm_add(_ub(m_glass), Transform3D(hb * Basis.from_scale(Vector3(1.8, 1.0, 1.4)), hc + hb * Vector3(0, 0.3, 1.6) + Vector3(0, 1.3, 0)))
	var tail := hc + Vector3(0, 1.3, 0) + _rb(Vector3(0, 35, 0)) * Vector3(0, 0, -6.0)
	_rod(hc + Vector3(0, 1.3, 0) + _rb(Vector3(0, 35, 0)) * Vector3(0, 0, -1.8), tail, 0.3, body, 8)
	_blk(tail + Vector3(0, 0.6, 0), Vector3(0.15, 1.6, 0.9), body, Vector3(0, 35, 70))
	for q in 4:
		var a := q * 90.0 + 20.0
		var bend := rng.randf_range(-25, 25)
		_blk(hc + Vector3(-1.4, 1.8, 0) + _rb(Vector3(0, a, 0)) * Vector3(0, 0, 2.6), Vector3(0.35, 0.05, 5.0), m_metal, Vector3(bend, a, rng.randf_range(-15, 15)))
	_wc(Vector3(2.6, 2.6, 8.0), Transform3D(_rb(Vector3(0, 35, 0)), hc + Vector3(0, 1.3, -1.5)))
	_fire(zone, hc + Vector3(0.5, 1.5, 0.5), 1.1)
	_smoke(zone, hc + Vector3(0.5, 3.0, 0.5), 0.9)
	# Tiendas de campaña con cruz roja
	for k in 3:
		var tp := c + Vector3(-12.0 + k * 7.0, 0, 11.0)
		_mm_add(_uc(m_tent, 3), Transform3D(_rb(Vector3(0, 90, 90)) * Basis.from_scale(Vector3(4.0, 5.0, 4.0)), tp + Vector3(0, 1.0, 0)))
		_wc(Vector3(5.0, 1.9, 3.4), Transform3D(Basis.IDENTITY, tp + Vector3(0, 0.95, 0)))
		_blk(tp + Vector3(0, 0.9, 2.53), Vector3(0.9, 0.25, 0.02), m_red)
		_blk(tp + Vector3(0, 0.9, 2.53), Vector3(0.25, 0.9, 0.02), m_red)
	# Cajas de suministros, costales y radio
	for q in 10:
		var bp := c + Vector3(rng.randf_range(6, 15), 0, rng.randf_range(2, 12))
		var sz := rng.randf_range(0.6, 1.1)
		_blk(bp + Vector3(0, sz * 0.5, 0), Vector3(sz, sz, sz), m_wood, Vector3(0, rng.randf_range(0, 90), 0), true)
	_sandbag_wall(c + Vector3(-16, 0, -8), 90.0, 8.0)
	var mast := c + Vector3(14, 0, -12)
	_rod(mast, mast + Vector3(0, 9, 0), 0.08, m_metal_light, 6)
	for e in 3:
		var a := TAU * e / 3.0
		_rod(mast + Vector3(0, 8, 0), mast + Vector3(cos(a) * 4, 0, sin(a) * 4), 0.02, m_iron, 4)
	_sp(mast + Vector3(0, 9.2, 0), Vector3(0.3, 0.3, 0.3), m_beacon)
	var sg := c + Vector3(-6, 0, 9.0)
	_blk(sg + Vector3(0, 2.0, 0), Vector3(4.6, 0.9, 0.08), m_line)
	for sx: float in [-2.1, 2.1]:
		_cy(sg + Vector3(sx, 1.0, 0), 0.05, 2.0, m_iron)
	_lbl(zone, "PUESTO DE RESCATE", sg + Vector3(0, 2.0, 0.05), 0.0, 40, Color(0.75, 0.1, 0.08))
	_omni(zone, c + Vector3(-5, 3, 10), Color(0.95, 0.97, 1.0), 2.0, 14.0, 0.04)
	_end_zone()


## Mercadito de puestos ambulantes.
func _make_market(c: Vector3) -> void:
	var zone := _begin_zone("Mercadito")
	_blk(c, Vector3(32, 0.08, 28), m_path)
	for i in 4:
		for j in 3:
			if rng.randf() < 0.15:
				continue
			var p := c + Vector3(-11.0 + i * 7.3, 0, -9.0 + j * 9.0)
			_stall(zone, p, 0.0 if j % 2 == 0 else 180.0)
			for q in 6:
				var fruit: Material = [m_red, m_orange, m_yellow, m_hedge][rng.randi() % 4]
				_sp(p + Vector3(rng.randf_range(-0.9, 0.9), 1.05, rng.randf_range(-0.35, 0.35)), Vector3(0.12, 0.12, 0.12), fruit, Vector3.ZERO, 6)
	for q in 4:
		var y := 3.4 + rng.randf_range(-0.2, 0.2)
		_rod(c + Vector3(-15, y, -12 + q * 8.0), c + Vector3(15, y - 0.4, -12 + q * 8.0), 0.01, m_iron, 3)
	_picnic_table(c + Vector3(-12, 0, 12), 10.0)
	_picnic_table(c + Vector3(12, 0, 12), -15.0)
	_omni(zone, c + Vector3(0, 3.0, 0), Color(1.0, 0.8, 0.5), 1.5, 12.0, 0.03)
	_end_zone()


# ================================================================ sectores y edificios de conexión
# El campus se divide en sectores cerrados por barricadas. Solo se pasa de uno a
# otro por dentro de edificios de aulas, y cada edificio está sellado hasta
# vencer al jefe anterior (orden lineal):
#   Plaza (Catedrático) → Aulas Poniente → Sector Poniente (Biblioteca)
#   → Pasaje Central → Sector Oriente (Cómputo) → Aulas Norte
#   → Sector Noreste (Laboratorio) → Posgrado → Sector Norte (Aula Magna)

## Muros entre sectores (x, z de inicio y fin).
const SECTOR_WALLS := [
	[Vector2(-42, 92), Vector2(-42, -212)],
	[Vector2(45, 92), Vector2(45, -213.8)],
	[Vector2(-300, -212), Vector2(-42, -212)],
	[Vector2(45, -213.8), Vector2(72, -213.8)],
	[Vector2(128, -213.8), Vector2(300, -213.8)],
	[Vector2(54, -213.8), Vector2(54, -420)],
]
## Qué sello abre cada jefe.
const SEAL_FOR_BOSS := {"profesor": "aulas_poniente", "biblioteca": "pasaje_central", "computo": "aulas_norte", "laboratorio": "posgrado"}
const SEAL_TITLES := {
	"aulas_poniente": "Se abrió el Edificio de Aulas Poniente",
	"pasaje_central": "Se abrió el Pasaje Central de Aulas",
	"aulas_norte": "Se abrió el Edificio de Aulas Norte",
	"posgrado": "Se abrió el Edificio de Posgrado",
}
const SEAL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float alpha = 0.85;
void fragment() {
	vec2 uv = UV;
	float n1 = texture(noise_tex, uv * vec2(1.4, 0.8) + vec2(TIME * 0.05, -TIME * 0.12)).r;
	float n2 = texture(noise_tex, uv * vec2(2.6, 1.6) + vec2(-TIME * 0.09, -TIME * 0.2)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	float edge = smoothstep(0.0, 0.1, uv.x) * smoothstep(1.0, 0.9, uv.x) * smoothstep(0.0, 0.08, 1.0 - uv.y);
	ALBEDO = mix(vec3(0.55, 0.58, 0.62), vec3(0.95, 0.95, 1.0), n) * 1.3;
	ALPHA = clamp((0.3 + n * 0.7) * edge * alpha, 0.0, 1.0);
}
"""

var _connector_rects: Array = []
var _hall_data: Array = []
var _seals := {}
var _ring_opened := false
var m_chain: StandardMaterial3D
var m_seal_fog: ShaderMaterial


func _make_connector_materials() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 32:
		for w in 2:
			img.set_pixel((i + w) % 32, i, Color(0.6, 0.62, 0.64, 1))
			img.set_pixel((31 - i + w) % 32, i, Color(0.6, 0.62, 0.64, 1))
	var tex := ImageTexture.create_from_image(img)
	m_chain = StandardMaterial3D.new()
	m_chain.albedo_texture = tex
	m_chain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m_chain.alpha_scissor_threshold = 0.5
	m_chain.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_chain.metallic = 0.6
	m_chain.roughness = 0.5
	m_chain.uv1_scale = Vector3(16, 14, 1)
	m_seal_fog = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SEAL_SHADER
	m_seal_fog.shader = sh
	m_seal_fog.set_shader_parameter("noise_tex", noise_tex)


## Edificio de conexión: pasillo cerrado con salones a un lado. Se recorre de
## local -x a +x. doors: "start"/"end" (puertas en los extremos, al pasillo),
## "front" (tramo con puerta al lado del pasillo, +z) y "back" (tramo con puerta
## por el muro exterior del salón, -z). seal: [id, puerta] para sellar una entrada.
func _hall(id: String, title: String, o: Vector3, yaw: float, segs: int, floors: int, doors: Dictionary, seal: Array) -> void:
	var zone := _begin_zone("Conexion_" + id)
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var L := segs * 8.0
	var H := floors * FLOOR_H
	var front: int = doors.get("front", -1)
	var back: int = doors.get("back", -1)
	var kinds: Array = []
	for s in segs:
		var kind := "room"
		if segs > 5 and s % 6 == 3 and s != front and s != back:
			kind = "lobby"
		elif s > 0 and s < segs - 1 and s != front and s != back and s - 1 != front and rng.randf() < 0.2:
			kind = "detour"
		kinds.append(kind)
	for s in segs:
		var x0 := -L * 0.5 + s * 8.0
		var cx := x0 + 4.0
		var kind: String = kinds[s]
		for fl in range(1, floors + 1):
			_lbox(o, b, Vector3(cx, fl * FLOOR_H, 0), Vector3(8.04, 0.3, 8.6), m_concrete)
		_wc(Vector3(8.0, 0.3, 8.6), Transform3D(b, o + b * Vector3(cx, FLOOR_H, 0)))
		_lbox(o, b, Vector3(cx, H + 0.6, -4.0), Vector3(8.0, 0.9, 0.35), m_concrete)
		_lbox(o, b, Vector3(cx, H + 0.6, 4.0), Vector3(8.0, 0.9, 0.35), m_concrete)
		_lbox(o, b, Vector3(cx, 0.0, 0.0), Vector3(8.0, 0.06, 8.0), m_labtile)
		# Fachadas en ambos lados, todos los pisos
		for fl in floors:
			for k in 2:
				var px := cx - 2.0 + k * 4.0
				var py := fl * FLOOR_H + FLOOR_H * 0.5
				if not (fl == 0 and k == 1 and s == back):
					if fl > 0 and rng.randf() < 0.06:
						_chunk(o + b * Vector3(px, fl * FLOOR_H, -4.5), 0.4, 1.2)
					else:
						_lpanel(o, b, Vector3(px, py, -4.0), 0.0)
				if not (fl == 0 and k == 1 and s == front):
					_lpanel(o, b, Vector3(px, py, 4.0), 0.0)
		for side: float in [-1.0, 1.0]:
			var door_here := (side < 0.0 and s == back) or (side > 0.0 and s == front)
			var z := side * 4.0
			if door_here:
				_wc(Vector3(4.6, H, 0.4), Transform3D(b, o + b * Vector3(x0 + 2.3, H * 0.5, z)))
				_wc(Vector3(0.8, H, 0.4), Transform3D(b, o + b * Vector3(x0 + 7.6, H * 0.5, z)))
				_wc(Vector3(2.6, H - 2.6, 0.4), Transform3D(b, o + b * Vector3(cx + 2.0, 2.6 + (H - 2.6) * 0.5, z)))
				_lbox(o, b, Vector3(cx + 2.0, 1.3, z), Vector3(0.3, 2.6, 0.5), m_concrete_dark)
				_lbox(o, b, Vector3(cx + 2.0, 2.75, z), Vector3(2.8, 0.3, 0.5), m_concrete_dark)
				_lbox(o, b, Vector3(cx + 0.65, 1.3, z), Vector3(0.3, 2.6, 0.5), m_concrete_dark)
				_lbox(o, b, Vector3(cx + 3.35, 1.3, z), Vector3(0.3, 2.6, 0.5), m_concrete_dark)
				if side < 0.0:
					for q in 6:
						_chunk(o + b * Vector3(cx + 2.0 + rng.randf_range(-2.0, 2.0), 0, -4.0 - rng.randf_range(0.5, 2.5)), 0.2, 0.7)
			else:
				_wc(Vector3(8.0, H, 0.4), Transform3D(b, o + b * Vector3(cx, H * 0.5, z)))
		match kind:
			"lobby":
				_lobby(zone, o, b, yaw, x0)
			"detour":
				_classroom(o, b, yaw, x0, kinds[mini(s + 1, segs - 1)] == "lobby" or s == segs - 1, true)
				_mound(o + b * Vector3(cx, 0, 2.5), 3.2, 1.4)
				_lbox(o, b, Vector3(cx, 1.6, 2.3), Vector3(4.0, 0.3, 3.0), m_concrete, false, Vector3(25, 0, 12))
				_rebar(o + b * Vector3(cx + 1.0, 1.4, 2.0), 3)
				_wc(Vector3(2.4, FLOOR_H, 3.0), Transform3D(b, o + b * Vector3(cx, FLOOR_H * 0.5, 2.5)))
			_:
				_classroom(o, b, yaw, x0, s == segs - 1 or kinds[mini(s + 1, segs - 1)] == "lobby", false)
		# Iluminación del pasillo y letreros de salida
		if s % 3 == 1:
			_lbox(o, b, Vector3(cx, FLOOR_H - 0.12, 2.5), Vector3(1.4, 0.05, 0.3), m_panel_light)
			_omni(zone, o + b * Vector3(cx, FLOOR_H - 0.6, 2.5), Color(0.85, 0.92, 1.0), 1.3, 10.0, 0.04, 14.0)
		if s % 4 == 2 and kind != "lobby":
			_lbl(zone, "SALIDA  →", o + b * Vector3(cx, 2.4, 1.12), yaw, 30, Color(0.2, 1.0, 0.4), false, 0.006)
	# Extremos del edificio, con o sin puerta
	for e: float in [-1.0, 1.0]:
		var ex := e * L * 0.5
		var has_door: bool = doors.get("start" if e < 0.0 else "end", false)
		for fl in floors:
			for k in 2:
				if fl == 0 and k == 1 and has_door:
					continue
				_lpanel(o, b, Vector3(ex, fl * FLOOR_H + FLOOR_H * 0.5, -2.0 + k * 4.0), PI * 0.5)
		if has_door:
			_wc(Vector3(0.4, H, 5.1), Transform3D(b, o + b * Vector3(ex, H * 0.5, -1.45)))
			_wc(Vector3(0.4, H - 2.7, 3.0), Transform3D(b, o + b * Vector3(ex, 2.7 + (H - 2.7) * 0.5, 2.5)))
			_lbox(o, b, Vector3(ex, 2.85, 2.5), Vector3(0.5, 0.3, 3.2), m_concrete_dark)
			for zz: float in [1.05, 3.95]:
				_lbox(o, b, Vector3(ex, 1.35, zz), Vector3(0.5, 2.7, 0.3), m_concrete_dark)
			_lbox(o, b, Vector3(ex + e * 0.4, FLOOR_H + 0.9, 0.0), Vector3(0.05, 0.9, 7.0), m_concrete_dark)
			_lbl(zone, title.to_upper(), o + b * Vector3(ex + e * 0.45, FLOOR_H + 0.9, 0.0), yaw + e * 90.0, 40, Color(0.88, 0.82, 0.66))
		else:
			_wc(Vector3(0.4, H, 8.0), Transform3D(b, o + b * Vector3(ex, H * 0.5, 0)))
	# Sello en la entrada
	if not seal.is_empty():
		var which: String = seal[1]
		var sp := Vector3.ZERO
		var syaw := yaw
		var sw := 2.9
		match which:
			"start":
				sp = Vector3(-L * 0.5 - 0.35, 0, 2.5)
				syaw = yaw + 90.0
			"end":
				sp = Vector3(L * 0.5 + 0.35, 0, 2.5)
				syaw = yaw + 90.0
			"front":
				sp = Vector3(-L * 0.5 + front * 8.0 + 6.0, 0, 4.35)
				sw = 2.4
			_:
				sp = Vector3(-L * 0.5 + back * 8.0 + 6.0, 0, -4.35)
				sw = 2.4
		_seal(String(seal[0]), o + b * sp, syaw, sw)
	# Rectángulo que ocupa (para reservar terreno y abrir los muros de sector)
	var corners := [o + b * Vector3(-L * 0.5, 0, -4.2), o + b * Vector3(L * 0.5, 0, 4.2)]
	var c0: Vector3 = corners[0]
	var c1: Vector3 = corners[1]
	var r := Rect2(Vector2(minf(c0.x, c1.x), minf(c0.z, c1.z)), Vector2(absf(c1.x - c0.x), absf(c1.z - c0.z)))
	_connector_rects.append(r)
	_hall_data.append({"id": id, "title": title, "origin": o, "basis": b, "length": L})
	_blocked_rects.append(r)
	_end_zone()


## Vestíbulo: tramo abierto de lado a lado con recepción, bancas y avisos.
func _lobby(zone: Node3D, o: Vector3, b: Basis, yaw: float, x0: float) -> void:
	var cx := x0 + 4.0
	_lbox(o, b, Vector3(cx, 0.55, -2.6), Vector3(3.2, 1.1, 0.7), m_wood_dark, true)
	_lbox(o, b, Vector3(cx, 1.12, -2.6), Vector3(3.4, 0.06, 0.9), m_metal_light)
	_lbox(o, b, Vector3(x0 + 0.5, 1.0, -2.5), Vector3(0.8, 2.0, 0.9), m_red, true)
	_lbox(o, b, Vector3(x0 + 0.92, 1.3, -2.5), Vector3(0.02, 0.9, 0.6), m_screen)
	_lbox(o, b, Vector3(x0 + 7.6, 1.0, -2.0), Vector3(0.6, 2.0, 2.0), m_glass_clear, true)
	for q in 3:
		_lbox(o, b, Vector3(x0 + 7.6, 0.6 + q * 0.5, -2.0), Vector3(0.55, 0.04, 1.9), m_wood)
		_cy(o + b * Vector3(x0 + 7.6, 0.75 + q * 0.5, -2.0 + rng.randf_range(-0.6, 0.6)), 0.1, 0.25, m_gold)
	_lbox(o, b, Vector3(cx, 1.6, -3.85), Vector3(3.0, 1.4, 0.05), m_wood)
	var avisos := ["AVISO: evacuación\npor el ala norte", "Se suspenden clases\nhasta nuevo aviso", "SE BUSCA:\nDr. Hierro", "Inscripciones\nsemestre 2027-1"]
	_lbl(zone, avisos[rng.randi() % avisos.size()], o + b * Vector3(cx, 1.65, -3.8), yaw, 22, Color(0.85, 0.82, 0.72), true, 0.008)
	for k in 2:
		_lbox(o, b, Vector3(x0 + 2.0 + k * 4.0, 0.25, 2.3), Vector3(1.8, 0.08, 0.5), m_wood, false, Vector3(0, 0, 0 if rng.randf() < 0.7 else 70))
	_cy(o + b * Vector3(x0 + 1.0, 0.35, 3.2), 0.3, 0.7, m_clay, Vector3.ZERO, 10, 0.8)
	_wtree(o + b * Vector3(x0 + 1.0, 0.7, 3.2), 0.25)
	_lbox(o, b, Vector3(cx, FLOOR_H - 0.12, -1.0), Vector3(1.4, 0.05, 0.3), m_panel_light)


## Sello de niebla en una puerta. Se disipa con unseal(id).
func _seal(id: String, pos: Vector3, yaw_deg: float, width: float) -> void:
	var holder := Node3D.new()
	holder.name = "Sello_" + id
	holder.position = pos
	holder.rotation.y = deg_to_rad(yaw_deg)
	w_zone.add_child(holder)
	var fog := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, 2.9)
	fog.mesh = q
	fog.material_override = m_seal_fog.duplicate()
	fog.position = Vector3(0, 1.45, 0)
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog.name = "Fog"
	holder.add_child(fog)
	var body := StaticBody3D.new()
	body.name = "Body"
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(width + 0.4, 3.0, 0.8)
	cs.shape = bx
	cs.position = Vector3(0, 1.5, 0)
	body.add_child(cs)
	holder.add_child(body)
	var l := _omni(holder, Vector3(0, 1.4, 0), Color(0.8, 0.85, 1.0), 1.0, 5.0)
	l.name = "Light"
	for face: float in [0.0, PI]:
		var t := Label3D.new()
		t.text = "SELLADO"
		t.font_size = 26
		t.pixel_size = 0.008
		t.modulate = Color(0.95, 0.9, 0.75)
		t.double_sided = false
		t.position = Vector3(0, 3.15, 0)
		t.rotation.y = face
		holder.add_child(t)
	if not _seals.has(id):
		_seals[id] = []
	_seals[id].append(holder)


## Disipa un sello y avisa al jugador.
func unseal(id: String, announce := true) -> void:
	if not _seals.has(id):
		return
	for h in _seals[id]:
		var holder: Node3D = h
		if not is_instance_valid(holder):
			continue
		var body := holder.get_node_or_null("Body")
		if body:
			body.queue_free()
		if not is_inside_tree() or not announce:
			holder.queue_free()
			continue
		var fog: MeshInstance3D = holder.get_node("Fog")
		var mat: ShaderMaterial = fog.material_override
		var tw := create_tween().set_parallel(true)
		tw.tween_method(func(v: float): mat.set_shader_parameter("alpha", v), 0.85, 0.0, 2.5)
		tw.tween_property(holder.get_node("Light"), "light_energy", 0.0, 2.5)
		tw.chain().tween_callback(holder.queue_free)
	_seals.erase(id)
	if announce and SEAL_TITLES.has(id):
		_show_title(SEAL_TITLES[id])


func _make_connectors() -> void:
	_connector_rects.clear()
	_hall_data.clear()
	_seals.clear()
	# 1) Plaza → Sector Poniente (se abre al vencer al Catedrático)
	_hall("aulas_poniente", "Edificio de Aulas Poniente", Vector3(-68, 0, 2.5), 180.0, 10, 2, {"start": true, "end": true}, [])
	# 2) Poniente → Oriente, por detrás de la plaza
	_hall("pasaje_central", "Pasaje Central de Aulas", Vector3(0, 0, -66), 0.0, 22, 2, {"start": true, "end": true}, ["pasaje_central", "start"])
	# 3) Oriente → Noreste (entrada por el frente, salida por un salón con el muro roto)
	_hall("aulas_norte", "Edificio de Aulas Norte", Vector3(100, 0, -218), 0.0, 7, 2, {"front": 0, "back": 6}, ["aulas_norte", "front"])
	# 4) Noreste → Norte (Aula Magna)
	_hall("posgrado", "Edificio de Posgrado", Vector3(70, 0, -250), 180.0, 7, 3, {"start": true, "end": true}, ["posgrado", "start"])


## Reserva el terreno de los muros de sector (antes de colocar zonas y árboles).
func _reserve_sector_walls() -> void:
	for w in SECTOR_WALLS:
		var a: Vector2 = w[0]
		var e: Vector2 = w[1]
		var r := Rect2(Vector2(minf(a.x, e.x) - 3.0, minf(a.y, e.y) - 3.0), Vector2(absf(e.x - a.x) + 6.0, absf(e.y - a.y) + 6.0))
		_blocked_rects.append(r)


## Barricadas visibles y colisión de los muros de sector, con huecos donde
## pasan los edificios de conexión.
func _make_sector_walls() -> void:
	var zone := _begin_zone("Barricadas")
	var colors := [Color(0.5, 0.05, 0.05), Color(0.1, 0.15, 0.3), Color(0.6, 0.6, 0.62), Color(0.15, 0.15, 0.15)]
	for w in SECTOR_WALLS:
		var a: Vector2 = w[0]
		var e: Vector2 = w[1]
		var dir := (e - a).normalized()
		var l := a.distance_to(e)
		var basis := Basis(Vector3.UP, atan2(dir.x, dir.y))
		# Intervalos libres (sin edificios de conexión)
		var cuts: Array = []
		for cr in _connector_rects:
			var rr: Rect2 = (cr as Rect2).grow(0.05)
			var t0 := INF
			var t1 := -INF
			for k in 201:
				var t := l * k / 200.0
				if rr.has_point(a + dir * t):
					t0 = minf(t0, t)
					t1 = maxf(t1, t)
			if t0 <= t1:
				cuts.append([t0 + 0.3, t1 - 0.3])
		var spans: Array = [[0.0, l]]
		for ct in cuts:
			var next: Array = []
			for sp in spans:
				var s0: float = sp[0]
				var s1: float = sp[1]
				var c0: float = ct[0]
				var c1: float = ct[1]
				if c1 <= s0 or c0 >= s1:
					next.append(sp)
					continue
				if c0 > s0:
					next.append([s0, c0])
				if c1 < s1:
					next.append([c1, s1])
			spans = next
		for sp in spans:
			var s0: float = sp[0]
			var s1: float = sp[1]
			if s1 - s0 < 0.1:
				continue
			var mid := a + dir * (s0 + s1) * 0.5
			_wc(Vector3(0.8, 9.0, s1 - s0), Transform3D(basis, Vector3(mid.x, 4.5, mid.y)))
			# Malla con alambre de púas y una barricada distinta cada 4 m
			var t := s0 + 2.0
			while t < s1 - 0.5:
				var p := a + dir * t
				var pos := Vector3(p.x, 0, p.y)
				t += 4.0
				if _inside_structure(p):
					continue
				var seg_l := minf(4.0, s1 - (t - 4.0) + 2.0)
				_mm_add(_ub(m_iron), Transform3D(Basis.from_scale(Vector3(0.09, 3.9, 0.09)), pos + Vector3(0, 1.95, 0) + basis * Vector3(0, 0, -2.0)))
				_mm_add(_ub(m_chain), Transform3D(basis * Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(seg_l, 3.5, 0.01)), pos + Vector3(0, 1.75, 0)))
				for y: float in [3.6, 3.85]:
					_mm_add(_ub(m_iron), Transform3D(basis * Basis.from_scale(Vector3(0.02, 0.02, seg_l)), pos + Vector3(0, y, 0)))
				var side := basis * Vector3(1, 0, 0) * (1.0 if rng.randf() < 0.5 else -1.0)
				var roll := rng.randf()
				if roll < 0.35:
					for row in 2:
						_blk(pos + side * (0.8 + row * 0.1) + Vector3(0, 0.42 + row * 0.85, 0), Vector3(0.6, 0.85, 2.6), m_concrete, basis.get_euler() * (180.0 / PI) + Vector3(0, rng.randf_range(-8, 8), 0))
				elif roll < 0.55:
					_mound(pos + side * 1.5, 3.5, 1.3)
					for q in 4:
						_chunk(pos + side * rng.randf_range(0.5, 2.5) + basis * Vector3(0, 0, rng.randf_range(-2, 2)), 0.3, 1.0)
				elif roll < 0.68:
					_car(zone, pos + side * 2.0, rad_to_deg(atan2(dir.x, dir.y)) + 90.0 + rng.randf_range(-20, 20), 0.0 if rng.randf() < 0.7 else 180.0, colors[rng.randi() % colors.size()], rng.randf() < 0.6)
				elif roll < 0.84:
					_sandbag_wall(pos + side * 0.9, rad_to_deg(atan2(dir.x, dir.y)) + 90.0, 3.6)
	_end_zone()


func _inside_structure(p: Vector2) -> bool:
	for b in _blocked:
		if float(b[1]) >= 10.0 and p.distance_to(b[0]) < float(b[1]) - 4.0:
			return true
	for r in _connector_rects:
		if (r as Rect2).grow(1.0).has_point(p):
			return true
	return false


# ================================================================ prefabs
# Facultades, alas de salones, edificios en ruinas, zonas recreativas y fuentes
# se colocan como nodos CampusPrefab en la escena (res://prefabs/). Cada uno se
# genera en su espacio local como hijo "Generated" del nodo, así que se puede
# seleccionar, mover, girar y duplicar desde el editor 3D.

const PREFAB := preload("res://scripts/campus_prefab.gd")


func _find_prefabs() -> Array:
	var scene_root: Node = owner if owner else get_parent()
	if scene_root == null:
		return []
	var out: Array = []
	for n in scene_root.find_children("*", "Node3D", true, true):
		if n is PREFAB:
			out.append(n)
	return out


func _make_prefabs() -> void:
	for pf in _find_prefabs():
		_build_prefab(pf)


func _build_prefab(pf: Node3D) -> void:
	var content := Node3D.new()
	content.name = "Generated"
	pf.add_child(content)
	# Se genera alrededor del origen; el nodo del prefab lo coloca y lo gira.
	var saved_state := rng.state
	var saved_body := w_body
	var saved_root := _root
	var nb := _blocked.size()
	var nr := _blocked_rects.size()
	var nz := _extra_zones.size()
	var nt := _tree_pts.size()
	w_body = StaticBody3D.new()
	w_body.name = "Collision"
	content.add_child(w_body)
	_zone_parent = content
	_prefab_local = true
	rng.seed = hash(int(pf.variation) * 7919 + int(pf.kind) * 104729 + int(pf.zone) * 31 + int(pf.robot) * 13 + int(pf.vehicle) * 7 + int(pf.ruin) * 3 + 17)
	var title: String = pf.title
	var c := Vector3.ZERO
	var kind_name: String = PREFAB.Kind.keys()[pf.kind]
	match kind_name:
		"FACULTAD":
			_faculty(c, 0.0, title if title != "" else "FACULTAD", pf.floors)
		"ALA_DE_SALONES":
			_begin_zone("AlaDeSalones")
			_wing(c, 0.0, pf.segments, pf.floors, pf.passage, pf.collapse, pf.end_caps)
			if title != "":
				_lbl(w_zone, title.to_upper(), Vector3(0, 4.15, 4.4), 0.0, 40, Color(0.88, 0.82, 0.66))
			_end_zone()
		"EDIFICIO_EN_RUINAS":
			_root = content
			_building(c, 0.0, pf.bays_x, pf.bays_z, pf.floors, pf.damage)
			_root = saved_root
		"FUENTE":
			var z := _begin_zone("Fuente")
			_fountain_plaza(z, c, pf.plaza_radius)
			_end_zone()
		"VEHICULO":
			_make_vehicle(c, pf.vehicle, pf.condition, pf.paint)
		"ROBOT":
			_make_robot(c, pf.robot, pf.eyes_on, pf.sparks)
		"RUINA":
			_make_ruin(c, pf.ruin)
		"LAGO":
			_make_lake(c, pf.lake_radii.x, pf.lake_radii.y)
		_:
			_build_zone(pf, c)
	_prefab_local = false
	_zone_parent = null
	_root = saved_root
	w_body = saved_body
	rng.state = saved_state
	_blocked.resize(nb)
	_blocked_rects.resize(nr)
	_extra_zones.resize(nz)
	_tree_pts.resize(nt)
	# Huella en el mundo: árboles, pasto y relleno no la invaden
	var fp: Vector2 = pf.footprint()
	var xf := pf.global_transform
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for cx: float in [-0.5, 0.5]:
		for cz: float in [-0.5, 0.5]:
			var wp := xf * Vector3(cx * fp.x, 0, cz * fp.y)
			mn = mn.min(Vector2(wp.x, wp.z))
			mx = mx.max(Vector2(wp.x, wp.z))
	_blocked_rects.append(Rect2(mn, mx - mn))
	_warn_conflicts(pf, kind_name)
	var gp := pf.global_position
	if kind_name in ["FACULTAD", "ALA_DE_SALONES", "EDIFICIO_EN_RUINAS"]:
		_reserve(Vector2(gp.x, gp.z), minf(fp.x, fp.y) * 0.5)
	if title != "" and kind_name != "EDIFICIO_EN_RUINAS":
		_extra_zones.push_front([Vector2(gp.x, gp.z), maxf(fp.x, fp.y) * 0.5 + 4.0, title])


## Avisa (panel Output) si un prefab tapa un edificio de conexión o cruza una
## barricada entre sectores: eso puede bloquear el recorrido o abrir un atajo.
func _warn_conflicts(pf: Node3D, kind_name: String) -> void:
	if not warn_prefab_conflicts or kind_name in ["VEHICULO", "ROBOT"]:
		return
	# Rectángulo girado real (sin los márgenes de reserva)
	var half: Vector2 = pf.footprint() * 0.5 - Vector2(3.0, 3.0)
	if half.x <= 0.5 or half.y <= 0.5:
		return
	var xf := pf.global_transform
	var poly := PackedVector2Array()
	for cr: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var wp := xf * Vector3(cr.x * half.x, 0, cr.y * half.y)
		poly.append(Vector2(wp.x, wp.z))
	for c in _connector_rects:
		var r: Rect2 = c
		var rp := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		if not Geometry2D.intersect_polygons(poly, rp).is_empty():
			push_warning("⚠ '%s' se encima con un edificio de conexión: revisa que no tape el paso." % pf.name)
			return
	for w in SECTOR_WALLS:
		if not Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([w[0], w[1]]), poly).is_empty():
			push_warning("⚠ '%s' cruza una barricada entre sectores: revisa que no deje un hueco para colarse." % pf.name)
			return


func _build_zone(pf: Node3D, c: Vector3) -> void:
	var zone_name: String = PREFAB.Zone.keys()[pf.zone]
	match zone_name:
		"PARQUE_INFANTIL":
			_make_playground(c)
		"BASQUETBOL":
			_make_basketball(c)
		"TENIS":
			_make_tennis(c)
		"SKATEPARK":
			_make_skatepark(c)
		"ESTACIONAMIENTO":
			_make_lot(c, pf.area_size)
		"GIMNASIO":
			_make_park_gym(c)
		"FORO":
			_make_theater(c)
		"ESCULTURAS":
			_make_sculptures(c)
		"PICNIC":
			_make_picnic(c, pf.area_size)
		"ALBERCA":
			_make_pool(c)
		"HUERTO":
			_make_huerto(c)
		"VOLEIBOL":
			_make_volleyball(c)
		"FUTBOLITO":
			_make_futbolito(c)
		"MEMORIAL":
			_make_memorial(c)
		"FRONTONES":
			_make_fronton(c)
		"TERMINAL":
			_make_terminal(c)
		"PUESTO_DE_RESCATE":
			_make_rescue_camp(c)
		"MERCADITO":
			_make_market(c)


# ================================================================ vehículos, robots y ruinas
# Prefabs pequeños de ambientación. Se construyen en el espacio local del nodo
# (frente hacia +x en vehículos y ruinas alargadas).

var m_rshell: StandardMaterial3D
var m_rdark: StandardMaterial3D
var m_rjoint: StandardMaterial3D
var m_reye_on: ShaderMaterial
var m_reye_off: StandardMaterial3D
var m_oil: StandardMaterial3D
var m_scorch: StandardMaterial3D
var m_ember: StandardMaterial3D
var m_cable_r: StandardMaterial3D
var m_cable_y: StandardMaterial3D
var m_lily: StandardMaterial3D
var _paints := {}


func _make_decor_materials() -> void:
	m_rshell = _std(Color(0.58, 0.6, 0.62), 0.35, 0.35)
	m_rdark = _std(Color(0.05, 0.055, 0.06), 0.4, 0.8)
	m_rjoint = _std(Color(0.17, 0.18, 0.19), 0.3, 0.9)
	m_reye_on = ShaderMaterial.new()
	m_reye_on.shader = load("res://shaders/blink_led.gdshader")
	m_reye_on.set_shader_parameter("tint", Color(1.0, 0.08, 0.04))
	m_reye_on.set_shader_parameter("energy", 4.0)
	m_reye_on.set_shader_parameter("rate", 0.5)
	m_reye_on.set_shader_parameter("blink", 0.7)
	m_reye_off = _std(Color(0.06, 0.02, 0.02), 0.1, 0.5)
	m_oil = _std(Color(0.01, 0.01, 0.012), 0.04, 0.3)
	m_scorch = _std(Color(0.035, 0.03, 0.025), 0.95, 0.0)
	m_ember = _emit(Color(1.0, 0.35, 0.05), 3.0)
	m_cable_r = _std(Color(0.5, 0.05, 0.04), 0.5, 0.0)
	m_cable_y = _std(Color(0.7, 0.55, 0.05), 0.5, 0.0)
	m_lily = _std(Color(0.08, 0.16, 0.06), 0.4, 0.0)
	_paints.clear()


func _paint_mat(c: Color) -> StandardMaterial3D:
	var k := c.to_html(false)
	if not _paints.has(k):
		_paints[k] = _std(c, 0.28, 0.55)
	return _paints[k]


## Pieza transformada por T (la pose del objeto completo).
func _tbox(T: Transform3D, pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	_mm_add(_ub(mat), T * Transform3D(_rb(rot) * Basis.from_scale(size), pos))


func _tcyl(T: Transform3D, pos: Vector3, r: float, h: float, mat: Material, rot := Vector3.ZERO, segs := 10, top := 1.0) -> void:
	_mm_add(_uc(mat, segs, top), T * Transform3D(_rb(rot) * Basis.from_scale(Vector3(r * 2.0, h, r * 2.0)), pos))


func _tsph(T: Transform3D, pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	_mm_add(_us(mat, 10), T * Transform3D(_rb(rot) * Basis.from_scale(size), pos))


func _puddle(pos: Vector3, r: float, mat: Material) -> void:
	_mm_add(_uc(mat, 20), Transform3D(Basis.from_scale(Vector3(r * 2.0, 0.01, r * rng.randf_range(1.2, 1.8))), pos + Vector3(0, 0.015, 0)))


# ---------------------------------------------------------------- vehículos

func _make_vehicle(c: Vector3, type: int, cond: int, paint: Color) -> void:
	var zone := _begin_zone("Vehiculo")
	var tname: String = PREFAB.Vehicle.keys()[type]
	var cname: String = PREFAB.Condition.keys()[cond]
	var burnt := cname == "CALCINADO" or cname == "EN_LLAMAS"
	var L := 4.4
	var W := 1.85
	var bh := 0.75
	var cab_l := 2.2
	var cab_h := 0.62
	var cab_x := -0.2
	var wr := 0.36
	match tname:
		"CAMIONETA":
			L = 5.3
			W = 2.0
			bh = 0.9
			cab_l = 1.9
			cab_h = 0.78
			cab_x = 0.75
			wr = 0.42
		"AUTOBUS":
			L = 11.0
			W = 2.6
			bh = 2.6
			cab_l = 0.0
			wr = 0.5
		"AMBULANCIA":
			L = 6.0
			W = 2.1
			bh = 2.2
			cab_l = 0.0
			wr = 0.4
	var floor_y := wr + 0.02
	var total_h := floor_y + bh + cab_h
	var T := Transform3D.IDENTITY
	match cname:
		"VOLCADO":
			T = Transform3D(Basis(Vector3.RIGHT, PI) * Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(-4, 4))), Vector3(0, total_h - 0.15, 0))
		"DE_LADO":
			T = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, W * 0.5, 0))
		"DESTROZADO":
			T = Transform3D(Basis(Vector3.BACK, deg_to_rad(rng.randf_range(-3, 3))) * Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(-3, 3))), Vector3.ZERO)
		_:
			T = Transform3D(Basis.IDENTITY, Vector3(0, -0.18, 0))
	var body: Material = m_burnt if burnt else _paint_mat(paint)
	if tname == "PATRULLA" and not burnt:
		body = _paint_mat(Color(0.05, 0.06, 0.08))
	if tname == "AMBULANCIA" and not burnt:
		body = _paint_mat(Color(0.75, 0.76, 0.74))
	if tname == "AUTOBUS" and not burnt and paint == Color(0.45, 0.06, 0.05):
		body = _paint_mat(Color(0.75, 0.55, 0.08))
	var holder := Node3D.new()
	holder.transform = T
	zone.add_child(holder)
	# Carrocería
	var front_crush := cname == "DESTROZADO" and rng.randf() < 0.7
	var body_len := L - (0.5 if front_crush else 0.0)
	_tbox(T, Vector3(-(L - body_len) * 0.5, floor_y + bh * 0.5, 0), Vector3(body_len, bh, W), body)
	if front_crush:
		_tbox(T, Vector3(L * 0.5 - 0.45, floor_y + bh * 0.55, 0), Vector3(0.7, bh * 0.75, W * 0.95), body, Vector3(rng.randf_range(-15, 15), rng.randf_range(-20, 20), rng.randf_range(10, 30)))
		_tbox(T, Vector3(L * 0.5 - 0.1, floor_y + 0.15, W * 0.3), Vector3(0.12, 0.18, W * 0.9), m_iron, Vector3(0, 25, 30))
	if tname == "AUTOBUS" or tname == "AMBULANCIA":
		var gl := m_glass if not burnt else m_rdark
		var band_y := floor_y + bh * (0.72 if tname == "AUTOBUS" else 0.8)
		_tbox(T, Vector3(0.3 if tname == "AUTOBUS" else L * 0.32, band_y, 0), Vector3(L * (0.85 if tname == "AUTOBUS" else 0.3), bh * 0.3, W + 0.03), gl)
		_tbox(T, Vector3(L * 0.5 + 0.01, band_y, 0), Vector3(0.04, bh * 0.35, W * 0.85), gl)
		if tname == "AMBULANCIA" and not burnt:
			_tbox(T, Vector3(0, floor_y + bh * 0.45, 0), Vector3(L + 0.02, 0.25, W + 0.02), m_red)
			for sd: float in [-1.0, 1.0]:
				var lb := Label3D.new()
				lb.text = "AMBULANCIA"
				lb.font_size = 48
				lb.pixel_size = 0.01
				lb.modulate = Color(0.6, 0.06, 0.05)
				lb.position = Vector3(-0.4, floor_y + bh * 0.66, sd * (W * 0.5 + 0.02))
				lb.rotation.y = 0.0 if sd > 0.0 else PI
				holder.add_child(lb)
		if tname == "AUTOBUS" and not burnt:
			var sign_l := Label3D.new()
			sign_l.text = "CIUDAD UNIVERSITARIA"
			sign_l.font_size = 30
			sign_l.pixel_size = 0.01
			sign_l.modulate = Color(1.0, 0.55, 0.1)
			sign_l.shaded = false
			sign_l.position = Vector3(L * 0.5 + 0.04, floor_y + bh * 0.92, 0)
			sign_l.rotation.y = PI * 0.5
			holder.add_child(sign_l)
	else:
		# Cabina: con vidrios, o solo el esqueleto si se quemó
		var cy := floor_y + bh + cab_h * 0.5
		if burnt:
			for px: float in [-0.5, 0.5]:
				for pz: float in [-0.5, 0.5]:
					_tbox(T, Vector3(cab_x + px * cab_l * 0.9, cy, pz * W * 0.85), Vector3(0.07, cab_h, 0.07), m_burnt, Vector3(0, 0, px * 18.0))
			_tbox(T, Vector3(cab_x, floor_y + bh + cab_h - 0.03, 0), Vector3(cab_l * 0.85, 0.05, W * 0.85), m_burnt, Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)))
			_tbox(T, Vector3(cab_x, floor_y + bh + 0.1, 0), Vector3(cab_l * 0.7, 0.2, W * 0.7), m_rdark)
		else:
			_tbox(T, Vector3(cab_x, cy, 0), Vector3(cab_l, cab_h, W * 0.9), body)
			if rng.randf() < 0.75:
				_tbox(T, Vector3(cab_x, cy + 0.03, 0), Vector3(cab_l + 0.03, cab_h * 0.62, W * 0.92), m_glass)
			if tname == "CAMIONETA":
				for sd: float in [-1.0, 1.0]:
					_tbox(T, Vector3(-L * 0.25, floor_y + bh + 0.25, sd * W * 0.47), Vector3(L * 0.45, 0.5, 0.06), body)
				_tbox(T, Vector3(-L * 0.47, floor_y + bh + 0.25, 0), Vector3(0.06, 0.5, W * 0.95), body, Vector3(0, 0, -70 if rng.randf() < 0.5 else 0))
				for q in 3:
					_tbox(T, Vector3(-L * 0.3 + rng.randf_range(-0.6, 0.6), floor_y + bh + 0.22, rng.randf_range(-0.5, 0.5)), Vector3(0.5, 0.4, 0.4), m_wood, Vector3(0, rng.randf_range(0, 90), 0))
			if tname == "PATRULLA":
				for sd: float in [-1.0, 1.0]:
					_tbox(T, Vector3(0, floor_y + bh * 0.55, sd * (W * 0.5 + 0.005)), Vector3(1.8, bh * 0.6, 0.02), _paint_mat(Color(0.8, 0.8, 0.78)))
					var lb := Label3D.new()
					lb.text = "SEGURIDAD"
					lb.font_size = 26
					lb.pixel_size = 0.01
					lb.modulate = Color(0.05, 0.08, 0.2)
					lb.position = Vector3(0, floor_y + bh * 0.55, sd * (W * 0.5 + 0.03))
					lb.rotation.y = 0.0 if sd > 0.0 else PI
					holder.add_child(lb)
				_tbox(T, Vector3(cab_x, floor_y + bh + cab_h + 0.07, -0.3), Vector3(0.25, 0.12, 0.55), m_red)
				_tbox(T, Vector3(cab_x, floor_y + bh + cab_h + 0.07, 0.3), Vector3(0.25, 0.12, 0.55), m_blue)
		# Puerta abierta o arrancada
		if cname == "DESTROZADO" and rng.randf() < 0.6:
			var dz := W * 0.5 + 0.35
			_tbox(T, Vector3(cab_x + 0.7, floor_y + bh * 0.6 + 0.15, dz), Vector3(1.0, bh * 0.9, 0.06), body, Vector3(0, -48, 0))
	# Llantas
	var axles := [L * 0.32, -L * 0.32]
	if tname == "AUTOBUS":
		axles = [L * 0.36, -L * 0.3]
	for ax in axles:
		for sd: float in [-1.0, 1.0]:
			if rng.randf() < 0.15:
				continue
			if burnt:
				_tcyl(T, Vector3(ax, wr, sd * (W * 0.5 - 0.1)), wr * 0.75, 0.2, m_iron, Vector3(90, 0, 0), 10)
			else:
				var flat := 0.8 if rng.randf() < 0.3 else 1.0
				_mm_add(_uc(m_tire, 12), T * Transform3D(_rb(Vector3(90, 0, 0)) * Basis.from_scale(Vector3(wr * 2.0, 0.28, wr * 2.0 * flat)), Vector3(ax, wr * flat, sd * (W * 0.5 - 0.1))))
	# Vidrios rotos, aceite y escombro alrededor
	if not burnt:
		for q in 14:
			var gp := Vector3(rng.randf_range(-L * 0.7, L * 0.7), 0.03, rng.randf_range(-W - 1.0, W + 1.0))
			_mm_add(_ub(m_glass_clear), Transform3D(_rb(Vector3(0, rng.randf_range(0, 360), 0)) * Basis.from_scale(Vector3(rng.randf_range(0.05, 0.25), 0.01, rng.randf_range(0.05, 0.2))), gp))
	_puddle(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-0.5, 0.5)), rng.randf_range(0.8, 1.6), m_scorch if burnt else m_oil)
	for q in 5:
		_chunk(Vector3(rng.randf_range(-L * 0.6, L * 0.6), 0, rng.randf_range(-W - 1.0, W + 1.0)), 0.1, 0.35)
	if cname == "EN_LLAMAS":
		var fp: Vector3 = T * Vector3(L * 0.3, floor_y + bh + 0.1, 0)
		_fire(zone, fp, 1.0 if tname != "AUTOBUS" else 1.4)
		_smoke(zone, fp + Vector3(0, 1.2, 0), 0.6)
	elif cname == "CALCINADO" and rng.randf() < 0.5:
		_smoke(zone, T * Vector3(0, floor_y + bh, 0), 0.3)
	var hgt := floor_y + bh + cab_h
	_wc(Vector3(L, hgt, W), T * Transform3D(Basis.IDENTITY, Vector3(0, hgt * 0.5, 0)))
	_end_zone()


# ---------------------------------------------------------------- robots

## Extremidad de dos segmentos que cuelga desde `start` (pose en grados).
func _limb(T: Transform3D, start: Vector3, rot1: Vector3, l1: float, r1: float, rot2: Vector3, l2: float, r2: float, end_size: Vector3) -> void:
	var b1 := _rb(rot1)
	_mm_add(_uc(m_rjoint, 8), T * Transform3D(b1 * Basis.from_scale(Vector3(r1 * 2.0, l1, r1 * 2.0)), start + b1 * Vector3(0, -l1 * 0.5, 0)))
	_mm_add(_uc(m_rshell, 8, 0.85), T * Transform3D(b1 * Basis.from_scale(Vector3(r1 * 2.6, l1 * 0.7, r1 * 2.6)), start + b1 * Vector3(0, -l1 * 0.45, 0)))
	var j := start + b1 * Vector3(0, -l1, 0)
	_mm_add(_us(m_rdark, 8), T * Transform3D(Basis.from_scale(Vector3.ONE * r1 * 2.3), j))
	var b2 := b1 * _rb(rot2)
	_mm_add(_uc(m_rjoint, 8), T * Transform3D(b2 * Basis.from_scale(Vector3(r2 * 2.0, l2, r2 * 2.0)), j + b2 * Vector3(0, -l2 * 0.5, 0)))
	_mm_add(_uc(m_rshell, 8, 0.8), T * Transform3D(b2 * Basis.from_scale(Vector3(r2 * 2.5, l2 * 0.65, r2 * 2.5)), j + b2 * Vector3(0, -l2 * 0.4, 0)))
	_mm_add(_ub(m_rdark), T * Transform3D(b2 * Basis.from_scale(end_size), j + b2 * Vector3(0, -l2 - end_size.y * 0.4, 0)))


## Robot humanoide (de pie mide 2 m) en el marco T. pose: rotaciones en grados.
func _humanoid(T: Transform3D, eye: Material, pose: Dictionary, upper := true, lower := true) -> void:
	if upper:
		_tbox(T, Vector3(0, 1.42, 0), Vector3(0.5, 0.6, 0.3), m_rdark)
		_tbox(T, Vector3(0, 1.5, 0.155), Vector3(0.46, 0.34, 0.06), m_rshell, Vector3(-6, 0, 0))
		_tbox(T, Vector3(0, 1.3, 0.15), Vector3(0.36, 0.14, 0.05), m_rshell)
		_tbox(T, Vector3(0, 1.45, -0.2), Vector3(0.36, 0.42, 0.12), m_rjoint)
		_tcyl(T, Vector3(0, 1.78, 0), 0.06, 0.14, m_rjoint)
		var hb := _rb(pose.get("head", Vector3.ZERO))
		var hc := Vector3(0, 1.8, 0)
		_mm_add(_ub(m_rshell), T * Transform3D(hb * Basis.from_scale(Vector3(0.26, 0.28, 0.28)), hc + hb * Vector3(0, 0.15, 0)))
		_mm_add(_ub(eye), T * Transform3D(hb * Basis.from_scale(Vector3(0.21, 0.045, 0.02)), hc + hb * Vector3(0, 0.17, 0.142)))
		_mm_add(_ub(m_rdark), T * Transform3D(hb * Basis.from_scale(Vector3(0.03, 0.12, 0.03)), hc + hb * Vector3(0.1, 0.34, -0.05)))
		for sd: float in [-1.0, 1.0]:
			_tsph(T, Vector3(sd * 0.32, 1.66, 0), Vector3(0.22, 0.2, 0.22), m_rshell)
			var key := "arm_l" if sd < 0.0 else "arm_r"
			if pose.has(key):
				var a: Array = pose[key]
				_limb(T, Vector3(sd * 0.34, 1.64, 0), a[0], 0.32, 0.06, a[1], 0.3, 0.055, Vector3(0.09, 0.13, 0.06))
	if lower:
		_tbox(T, Vector3(0, 1.0, 0), Vector3(0.36, 0.22, 0.22), m_rdark)
		_tbox(T, Vector3(0, 1.0, 0.115), Vector3(0.3, 0.16, 0.02), m_rshell)
		for sd: float in [-1.0, 1.0]:
			var key := "leg_l" if sd < 0.0 else "leg_r"
			if pose.has(key):
				var lg: Array = pose[key]
				_limb(T, Vector3(sd * 0.12, 0.92, 0), lg[0], 0.45, 0.08, lg[1], 0.45, 0.07, Vector3(0.13, 0.07, 0.26))


func _cables(from: Vector3, n: int) -> void:
	var mats := [m_cable_r, m_cable_y, m_rdark, m_rjoint]
	for q in n:
		var to := from + Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0))
		to.y = 0.03
		var mid := (from + to) * 0.5 + Vector3(rng.randf_range(-0.2, 0.2), 0.1, rng.randf_range(-0.2, 0.2))
		_rod(from, mid, 0.015, mats[q % mats.size()], 4)
		_rod(mid, to, 0.015, mats[q % mats.size()], 4)


func _make_robot(c: Vector3, type: int, eyes_on: bool, sparks_on: bool) -> void:
	var zone := _begin_zone("Robot")
	var rname: String = PREFAB.Robot.keys()[type]
	var eye: Material = m_reye_on if eyes_on else m_reye_off
	var r := func(a: float, b: float) -> float: return rng.randf_range(a, b)
	match rname:
		"CENTINELA":
			# Tirado boca arriba, brazos abiertos
			var T := Transform3D(Basis(Vector3.UP, deg_to_rad(r.call(-20, 20))) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.2, 1.0))
			_humanoid(T, eye, {
				"head": Vector3(r.call(-10, 10), r.call(-40, 40), 0),
				"arm_l": [Vector3(0, 0, -r.call(40, 85)), Vector3(r.call(-60, 0), 0, 0)],
				"arm_r": [Vector3(r.call(-30, 10), 0, r.call(30, 80)), Vector3(r.call(-70, -10), 0, 0)],
				"leg_l": [Vector3(r.call(-10, 0), 0, -r.call(5, 20)), Vector3(r.call(0, 10), 0, 0)],
				"leg_r": [Vector3(r.call(-50, -20), 0, r.call(5, 15)), Vector3(r.call(40, 80), 0, 0)],
			})
			_puddle(Vector3(0, 0, 0), 0.9, m_oil)
			_wc(Vector3(0.7, 0.4, 2.0), Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0)))
			if sparks_on:
				_sparks(zone, Vector3(0.2, 0.3, -0.2))
		"PARTIDO":
			# Mitad superior boca abajo arrastrando cables; las piernas, lejos
			var T := Transform3D(Basis(Vector3.UP, deg_to_rad(r.call(-30, 30))) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.18, -1.15))
			_humanoid(T, eye, {
				"head": Vector3(r.call(10, 30), r.call(-30, 30), 0),
				"arm_l": [Vector3(r.call(-160, -120), 0, -r.call(10, 30)), Vector3(r.call(-40, 0), 0, 0)],
				"arm_r": [Vector3(r.call(-20, 10), 0, r.call(20, 50)), Vector3(r.call(-60, -20), 0, 0)],
			}, true, false)
			_cables(T * Vector3(0, 1.12, 0), 7)
			var T2 := Transform3D(Basis(Vector3.UP, deg_to_rad(r.call(0, 360))) * Basis(Vector3.BACK, PI * 0.5), Vector3(r.call(1.6, 2.2), 0.15, r.call(0.5, 1.5)))
			_humanoid(T2, eye, {
				"leg_l": [Vector3(r.call(-20, 0), 0, 0), Vector3(r.call(0, 40), 0, 0)],
				"leg_r": [Vector3(r.call(-60, -20), 0, 0), Vector3(r.call(40, 90), 0, 0)],
			}, false, true)
			_cables(T2 * Vector3(0, 1.1, 0), 4)
			_puddle(Vector3(0.6, 0, 0), 1.3, m_oil)
			_wc(Vector3(0.7, 0.4, 1.2), Transform3D(Basis.IDENTITY, Vector3(0, 0.2, -0.6)))
			if sparks_on:
				_sparks(zone, T * Vector3(0, 1.12, 0))
		"SENTADO":
			# Recargado contra algo (respaldo hacia -z), cabeza caída
			var T := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-14)), Vector3(0, -0.74, 0.1))
			_humanoid(T, eye, {
				"head": Vector3(r.call(25, 40), 0, r.call(-25, 25)),
				"arm_l": [Vector3(r.call(-10, 20), 0, -r.call(5, 20)), Vector3(r.call(-40, -10), 0, 0)],
				"arm_r": [Vector3(r.call(-50, -20), 0, r.call(5, 15)), Vector3(r.call(-70, -40), 0, 0)],
				"leg_l": [Vector3(-88, r.call(-10, 0), -r.call(5, 15)), Vector3(r.call(0, 20), 0, 0)],
				"leg_r": [Vector3(r.call(-90, -60), 0, r.call(5, 15)), Vector3(r.call(20, 60), 0, 0)],
			})
			_tbox(Transform3D.IDENTITY, Vector3(0, 0.6, -0.55), Vector3(1.4, 1.2, 0.5), m_concrete, Vector3(0, r.call(-10, 10), r.call(-4, 4)))
			_puddle(Vector3(0, 0, 0.6), 0.6, m_oil)
			_wc(Vector3(1.4, 1.2, 1.6), Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0.1)))
			if sparks_on:
				_sparks(zone, Vector3(0.25, 1.0, 0.0))
		"CANINO":
			# Robot cuadrúpedo tumbado de lado
			var T := Transform3D(Basis(Vector3.UP, deg_to_rad(r.call(0, 360))) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.22, 0))
			_tbox(T, Vector3(0, 0, 0), Vector3(1.0, 0.28, 0.42), m_rshell)
			_tbox(T, Vector3(0, 0.16, 0), Vector3(0.7, 0.06, 0.3), m_rdark)
			_tbox(T, Vector3(0.6, 0.05, 0), Vector3(0.28, 0.2, 0.26), m_rdark)
			_tbox(T, Vector3(0.75, 0.06, 0), Vector3(0.02, 0.06, 0.18), eye)
			for lx: float in [-0.4, 0.4]:
				for lz: float in [-0.2, 0.2]:
					if rng.randf() < 0.15:
						continue
					_limb(T, Vector3(lx, -0.08, lz), Vector3(r.call(-40, 40), 0, r.call(-50, 50)), 0.32, 0.05, Vector3(r.call(30, 90), 0, 0), 0.32, 0.04, Vector3(0.08, 0.05, 0.08))
			_puddle(Vector3.ZERO, 0.7, m_oil)
			_wc(Vector3(1.2, 0.5, 0.8), T * Transform3D(Basis.IDENTITY, Vector3.ZERO))
			if sparks_on:
				_sparks(zone, T * Vector3(-0.4, 0.1, 0))
		"MECH":
			_make_mech(zone, eye, sparks_on)
		"DRON":
			var T := Transform3D(Basis(Vector3.UP, deg_to_rad(r.call(0, 360))) * Basis(Vector3.BACK, deg_to_rad(r.call(15, 30))), Vector3(0, 0.3, 0))
			_tsph(T, Vector3.ZERO, Vector3(1.2, 0.42, 1.2), m_rshell)
			_tsph(T, Vector3(0, -0.2, 0.3), Vector3(0.32, 0.32, 0.32), m_rdark)
			_tsph(T, Vector3(0, -0.22, 0.44), Vector3(0.1, 0.1, 0.05), eye)
			for q in 4:
				var a := deg_to_rad(45.0 + q * 90.0)
				var dir := Vector3(cos(a), 0, sin(a))
				if q == 2:
					_tbox(Transform3D.IDENTITY, dir * 1.6 + Vector3(0, 0.05, 0), Vector3(0.9, 0.08, 0.1), m_rdark, Vector3(0, r.call(0, 360), 0))
					_tcyl(Transform3D.IDENTITY, dir * 2.0 + Vector3(0.3, 0.03, 0.2), 0.42, 0.03, m_rdark, Vector3(r.call(-10, 10), 0, r.call(-10, 10)), 14)
					continue
				_mm_add(_ub(m_rdark), T * Transform3D(Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(0.9, 0.08, 0.1)), dir * 0.7))
				_tcyl(T, dir * 1.15 + Vector3(0, 0.08, 0), 0.42, 0.03, m_rdark, Vector3(r.call(-15, 15), 0, r.call(-15, 15)), 14)
			_puddle(Vector3.ZERO, 1.5, m_scorch)
			for q in 8:
				_chunk(Vector3(r.call(-2, 2), 0, r.call(-2, 2)), 0.08, 0.3)
			_wc(Vector3(1.3, 0.6, 1.3), Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)))
			if sparks_on:
				_sparks(zone, Vector3(0, 0.5, 0))
	_end_zone()


## Mech de combate de 5 m, derribado sobre una rodilla, con un brazo arrancado.
func _make_mech(zone: Node3D, eye: Material, sparks_on: bool) -> void:
	var tilt := _rb(Vector3(rng.randf_range(14, 24), 0, rng.randf_range(-8, 8)))
	var T := Transform3D(tilt, Vector3(0, 0, 0))
	var hip := Vector3(0, 2.4, 0)
	# Torso y cabina
	_tbox(T, hip + Vector3(0, 0.9, 0), Vector3(2.6, 1.5, 2.0), m_rdark)
	_tbox(T, hip + Vector3(0, 1.0, 1.02), Vector3(2.2, 1.1, 0.1), m_rshell, Vector3(-8, 0, 0))
	_tbox(T, hip + Vector3(0, 1.75, 0.2), Vector3(1.6, 0.4, 1.4), m_rshell)
	_tbox(T, hip + Vector3(0, 1.0, 1.09), Vector3(1.0, 0.12, 0.03), eye)
	_tbox(T, hip + Vector3(0, 0.95, -1.15), Vector3(1.8, 1.0, 0.4), m_rjoint)
	for sd: float in [-1.0, 1.0]:
		_tcyl(T, hip + Vector3(sd * 0.6, 1.8, -1.0), 0.18, 0.6, m_rjoint, Vector3(70, 0, 0))
	# Piernas de rodilla invertida: la izquierda arrodillada
	var hips := [hip + Vector3(-1.0, 0.2, 0), hip + Vector3(1.0, 0.2, 0)]
	var knees := [Vector3(-1.1, 0.45, 1.3), Vector3(1.2, 1.4, 0.9)]
	var feet := [Vector3(-1.2, 0.25, -0.6), Vector3(1.3, 0.2, -0.4)]
	for i in 2:
		var hp: Vector3 = T * (hips[i] as Vector3)
		var kn: Vector3 = knees[i]
		var ft: Vector3 = feet[i]
		_rod(hp, kn, 0.32, m_rshell, 10)
		_mm_add(_us(m_rdark, 10), Transform3D(Basis.from_scale(Vector3.ONE * 0.75), kn))
		_rod(kn, ft, 0.26, m_rjoint, 10)
		_mm_add(_ub(m_rdark), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)) * Basis.from_scale(Vector3(0.9, 0.35, 1.6)), ft + Vector3(0, -0.05, 0.3)))
		_wc(Vector3(0.7, 0.7, hp.distance_to(kn)), Transform3D(Basis.looking_at((kn - hp).normalized(), Vector3.UP if absf((kn - hp).normalized().y) < 0.95 else Vector3.RIGHT), (hp + kn) * 0.5))
	# Brazo cañón que cuelga hasta el piso
	var sh: Vector3 = T * (hip + Vector3(-1.55, 1.2, 0.2))
	var hand := Vector3(-2.2, 0.3, 1.8)
	_mm_add(_us(m_rshell, 10), Transform3D(Basis.from_scale(Vector3.ONE * 0.8), sh))
	_rod(sh, hand, 0.28, m_rjoint, 10)
	_rod(hand, hand + Vector3(-0.2, 0.0, 1.8), 0.22, m_rdark, 10)
	_rod(hand + Vector3(-0.2, 0.0, 1.8), hand + Vector3(-0.2, 0.0, 2.1), 0.12, m_rdark, 10)
	# Brazo derecho arrancado, en el piso con cables
	var stump: Vector3 = T * (hip + Vector3(1.4, 1.2, 0.2))
	_cables(stump, 5)
	var arm_p := Vector3(rng.randf_range(2.6, 3.4), 0.3, rng.randf_range(-1.5, 1.5))
	_mm_add(_uc(m_rjoint, 10), Transform3D(_rb(Vector3(0, rng.randf_range(0, 180), 90)) * Basis.from_scale(Vector3(0.6, 2.4, 0.6)), arm_p))
	_mm_add(_us(m_rshell, 10), Transform3D(Basis.from_scale(Vector3.ONE * 0.75), arm_p + Vector3(0.4, 0.15, 0.6)))
	_cables(arm_p + Vector3(0.6, 0.2, 0.7), 4)
	_puddle(Vector3(0, 0, 0.5), 2.4, m_oil)
	for q in 16:
		_chunk(Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), 0.15, 0.6)
	_wc(Vector3(2.8, 2.0, 2.4), T * Transform3D(Basis.IDENTITY, hip + Vector3(0, 0.9, 0)))
	_wc(Vector3(0.8, 0.8, 2.6), Transform3D(_rb(Vector3(0, 0, 0)), arm_p))
	_smoke(zone, T * (hip + Vector3(0, 2.2, -0.8)), 0.45)
	if sparks_on:
		_sparks(zone, stump)


# ---------------------------------------------------------------- ruinas menores

func _make_ruin(c: Vector3, type: int) -> void:
	var zone := _begin_zone("Ruina")
	var rname: String = PREFAB.Ruin.keys()[type]
	match rname:
		"MURO_ROTO":
			# Fachada de dos pisos que quedó en pie
			for k in 2:
				var px := -2.0 + k * 4.0
				var floors := 2 if (k == 0 or rng.randf() < 0.5) else 1
				for fl in floors:
					_mm_add(mesh_panel, Transform3D(Basis.IDENTITY, Vector3(px, fl * FLOOR_H + FLOOR_H * 0.5, 0)))
				var top := floors * FLOOR_H
				for q in 3:
					_chunk(Vector3(px + rng.randf_range(-1.6, 1.6), top, rng.randf_range(-0.2, 0.2)), 0.3, 0.9)
				_rebar(Vector3(px + rng.randf_range(-1.5, 1.5), top, 0), 3)
			_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(-4.2, 3.0, 0), Vector3(0.6, 6.0, 0.6), m_concrete_dark, true)
			_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(-1.5, FLOOR_H + 0.15, -1.6), Vector3(3.5, 0.3, 3.0), m_concrete, false, Vector3(rng.randf_range(10, 25), 0, rng.randf_range(-8, 8)))
			for sd: float in [-1.0, 1.0]:
				_mound(Vector3(rng.randf_range(-2, 2), 0, sd * 2.2), 4.0, 1.2)
			for q in 18:
				_chunk(Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-3.5, 3.5)), 0.2, 1.0)
			_wc(Vector3(8.0, FLOOR_H * 2.0, 0.4), Transform3D(Basis.IDENTITY, Vector3(0, FLOOR_H, 0)))
		"ESCOMBROS":
			for q in 3:
				_mound(Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5)), rng.randf_range(4.5, 7.0), rng.randf_range(1.4, 2.4))
			for q in 4:
				var sp := Vector3(rng.randf_range(-3, 3), rng.randf_range(0.6, 1.6), rng.randf_range(-3, 3))
				_blk(sp, Vector3(rng.randf_range(2.5, 4.0), 0.3, rng.randf_range(1.8, 3.0)), m_concrete, Vector3(rng.randf_range(-35, 35), rng.randf_range(0, 180), rng.randf_range(-35, 35)))
				_rebar(sp, 3)
			_blk(Vector3(2.5, 0.9, 1.0), Vector3(1.4, 0.06, 0.7), m_desk, Vector3(40, 30, 10))
			_blk(Vector3(-2.0, 1.4, -1.5), Vector3(0.45, 0.05, 0.45), m_metal_light, Vector3(70, 10, 20))
			_cy(Vector3(-3.0, 0.6, 2.0), 0.25, 3.0, m_metal, Vector3(0, 30, 70))
			for q in 40:
				_chunk(Vector3(rng.randf_range(-5.5, 5.5), 0, rng.randf_range(-5.5, 5.5)), 0.15, 1.1)
			_wc(Vector3(6.0, 1.4, 6.0), Transform3D(Basis(Vector3.UP, rng.randf_range(0, 1.5)), Vector3(0, 0.7, 0)))
		"CASETA":
			var gray := m_white_lab
			_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(0, 1.25, -1.25), Vector3(2.6, 2.5, 0.15), gray, true)
			_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(-1.25, 1.25, 0), Vector3(0.15, 2.5, 2.6), gray, true)
			_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(1.25, 0.5, 0), Vector3(0.15, 1.0, 2.6), gray, true)
			_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(0.35, 0.5, 1.25), Vector3(1.9, 1.0, 0.15), gray, true)
			_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(1.25, 1.8, -0.9), Vector3(0.15, 1.4, 0.4), gray)
			_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(0.4, 2.1, 0.2), Vector3(3.0, 0.15, 3.0), m_concrete_dark, false, Vector3(18, 0, -12))
			_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(0.0, 0.42, -0.6), Vector3(1.6, 0.06, 0.6), m_desk)
			_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(0.6, 0.8, -0.85), Vector3(0.45, 0.35, 0.35), m_concrete_dark)
			for q in 10:
				_mm_add(_ub(m_glass_clear), Transform3D(_rb(Vector3(0, rng.randf_range(0, 360), 0)) * Basis.from_scale(Vector3(rng.randf_range(0.1, 0.4), 0.01, rng.randf_range(0.1, 0.3))), Vector3(rng.randf_range(1.3, 3.0), 0.03, rng.randf_range(-1.5, 1.5))))
			# Pluma de acceso caída
			_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(2.0, 0.55, 1.6), Vector3(0.3, 1.1, 0.3), m_hazard_y, true)
			for q in 6:
				_lbox(Vector3.ZERO, Basis.IDENTITY, Vector3(2.1 + q * 0.75 * 0.98, 0.25 + q * 0.06, 1.75 + q * 0.12), Vector3(0.75, 0.1, 0.1), m_red if q % 2 == 0 else m_line, false, Vector3(0, -9, -5))
			var t := _lbl(zone, "VIGILANCIA", Vector3(0, 2.35, 1.4), 0.0, 40, Color(0.75, 0.75, 0.7))
			t.rotation_degrees.z = 6.0
		"POSTE_CAIDO":
			# Poste de luz con cables, caído sobre la banqueta
			_cy(Vector3(-6.0, 0.6, 0), 0.25, 1.2, m_concrete, Vector3.ZERO, 8, 0.9, true)
			_rebar(Vector3(-6.0, 1.2, 0), 3)
			var top := Vector3(5.0, 0.3, rng.randf_range(-1.0, 1.0))
			_rod(Vector3(-5.6, 0.9, 0), top, 0.17, m_concrete, 8)
			_blk(top + Vector3(-0.3, 0.2, 0), Vector3(0.12, 0.12, 1.8), m_wood, Vector3(0, 0, 80))
			_blk(top + Vector3(-1.2, 0.35, 0.6), Vector3(0.6, 0.8, 0.6), m_metal, Vector3(30, 20, 70), true)
			_wc(Vector3(11.0, 0.5, 0.5), Transform3D(Basis(Vector3.UP, atan2(-(top.z), top.x + 5.6)), (Vector3(-5.6, 0.6, 0) + top) * 0.5))
			# Cables colgando hacia el poste que sigue en pie
			var other := Vector3(8.0, 0, -3.5)
			_cy(other + Vector3(0, 4.5, 0), 0.17, 9.0, m_concrete, Vector3(0, 0, -4), 8, 0.75, true)
			_blk(other + Vector3(0, 8.6, 0), Vector3(0.12, 0.12, 1.8), m_wood)
			for w in 3:
				var a := other + Vector3(0, 8.6, -0.8 + w * 0.8)
				var b := top + Vector3(0, 0.1, -0.6 + w * 0.6)
				var m1 := a.lerp(b, 0.4) + Vector3(0, -2.5 - w * 0.4, 0)
				var m2 := a.lerp(b, 0.75) + Vector3(0, -1.2, 0)
				m1.y = maxf(m1.y, 0.1)
				_rod(a, m1, 0.02, m_tire, 4)
				_rod(m1, m2, 0.02, m_tire, 4)
				_rod(m2, b, 0.02, m_tire, 4)
			if rng.randf() < 0.5:
				_sparks(zone, top + Vector3(0, 0.2, 0))
		"CRATER":
			_mm_add(_uc(m_scorch, 32), Transform3D(Basis.from_scale(Vector3(13.0, 0.02, 13.0)), Vector3(0, 0.025, 0)))
			_mm_add(_uc(m_debris, 24), Transform3D(Basis.from_scale(Vector3(5.0, 0.02, 5.0)), Vector3(0, 0.035, 0)))
			for i in 28:
				var a := TAU * i / 28.0 + rng.randf_range(-0.1, 0.1)
				var rr := rng.randf_range(3.2, 4.6)
				_chunk(Vector3(cos(a) * rr, rng.randf_range(0.0, 0.5), sin(a) * rr), 0.4, 1.4)
			for i in 6:
				var a := TAU * i / 6.0
				_mound(Vector3(cos(a), 0, sin(a)) * 4.0, 3.0, 0.8)
			for q in 30:
				var a := rng.randf() * TAU
				var rr := rng.randf_range(4.5, 7.0)
				_chunk(Vector3(cos(a) * rr, 0, sin(a) * rr), 0.08, 0.35)
			for q in 25:
				_sp(Vector3(rng.randf_range(-2.5, 2.5), 0.05, rng.randf_range(-2.5, 2.5)), Vector3.ONE * rng.randf_range(0.06, 0.14), m_ember, Vector3.ZERO, 6)
			_fire(zone, Vector3(0.3, 0.3, -0.4), 0.6)
			_smoke(zone, Vector3(0, 0.8, 0), 0.7)
		"BARRICADA":
			_sandbag_wall(Vector3(-3.6, 0, 0), 0.0, 3.2)
			_blk(Vector3(-0.8, 0.45, 0), Vector3(1.6, 0.9, 0.8), m_desk, Vector3(0, 8, 0))
			_blk(Vector3(-0.6, 1.0, 0.1), Vector3(1.4, 0.06, 0.7), m_desk, Vector3(0, -10, 80))
			_blk(Vector3(1.0, 0.25, 0.2), Vector3(2.0, 0.5, 0.45), m_wood_dark, Vector3(0, 12, 0))
			_blk(Vector3(1.2, 0.75, 0.1), Vector3(0.9, 2.0, 0.05), m_wood, Vector3(-75, 15, 0))
			for q in 4:
				var tp := Vector3(2.8 + (q % 2) * 0.8, 0.2 + (q / 2) * 0.32, rng.randf_range(-0.3, 0.3))
				_cy(tp, 0.38, 0.3, m_tire, Vector3(0, 0, 0), 12)
			_blk(Vector3(4.4, 0.5, 0), Vector3(0.45, 1.0, 1.0), m_metal_light, Vector3(0, 20, 90))
			for q in 3:
				_blk(Vector3(rng.randf_range(-4, 4), 0.25, rng.randf_range(0.8, 1.5)), Vector3(0.45, 0.05, 0.45), m_metal_light, Vector3(rng.randf_range(0, 90), rng.randf_range(0, 360), 0))
			_wc(Vector3(10.0, 1.3, 1.2), Transform3D(Basis.IDENTITY, Vector3(0, 0.65, 0)))
			var spray := _lbl(zone, "AQUÍ RESISTIMOS", Vector3(-3.6, 0.75, 0.4), 0.0, 42, Color(0.75, 0.08, 0.05))
			spray.rotation_degrees.z = -4.0
	_end_zone()
