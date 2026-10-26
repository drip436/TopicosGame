extends Control
## Selector de clase (Nueva partida), al estilo de la creación de personaje de Dark Souls:
## lista de clases a la izquierda, el personaje en 3D con la armadura y armas de la clase
## al centro (gira solo; arrástralo con el mouse para girarlo) y sus atributos a la derecha.
## Fondo de metal con neón azul (ui/estilo.gd). Flechas ↑/↓ cambian de clase, Enter
## comienza y Esc vuelve al menú.

const E := preload("res://ui/estilo.gd")
const CLASSES := preload("res://jugador/player_classes.gd")
const RIG := preload("res://jugador/player_rig.gd")
const PLAYER_MODEL := "res://Modelo/modelo.glb"
const ORDEN := ["cyber", "backend", "frontend", "ai", "data"]

## Texto de cada clase (lo que se ve a la derecha).
const INFO := {
	"frontend": {"desc": "Lanza hechizos escribiendo código: bolas de fuego, rayos del cielo, lluvia de flechas, flechas que siguen funciones matemáticas, nova de área y frascos de veneno. Gasta maná (barra azul) que recupera con bebidas energéticas.",
		"armas": "Estoque · Bastón tecnológico", "habilidad": "Hechizos (6) · Bebida energética"},
	"backend": {"desc": "Armadura pesadísima que reduce el daño y un mazo de guerra con golpe sísmico de área. Lento: rodar para esquivar le cuesta mucha estamina.",
		"armas": "Martillo de guerra", "habilidad": "Golpe sísmico"},
	"ai": {"desc": "Pelea junto a sus IAs al estilo de los stands: ChatGPT (gigante de fuerza bruta), Gemini (arquera) y Claude (espadachín). Q cambia de IA y el clic derecho usa su especial.",
		"armas": "Tableta holográfica", "habilidad": "Invocar IA · Ataque especial"},
	"data": {"desc": "La clase más rápida. Flechas infinitas a distancia y una lanza para el cuerpo a cuerpo, con armadura ligera de cuero.",
		"armas": "Lanza · Arco recurvo", "habilidad": "Disparo de flecha"},
	"cyber": {"desc": "Caballero de placas. Espada larga y escudo: mantén el clic derecho para cubrirte y bloquear casi todo el daño de frente.",
		"armas": "Espada larga · Escudo de cometa", "habilidad": "Bloquear con el escudo"},
}

## Armas de cada clase: [modelo, hueso, eje del arma, dirección, desplazamiento, eje de la cara, dirección de la cara]
## (los mismos montajes que jugador/class_kit.gd).
const ARMAS := {
	"frontend": [["estoque", "hand_r", Vector3(0, 0, -1), Vector3(0, -0.15, -1), Vector3(0.07, 0, 0), Vector3.ZERO, Vector3.ZERO],
		["baston", "hand_l", Vector3(0, 1, 0), Vector3(0, 1, -0.15), Vector3(-0.07, 0, 0), Vector3.ZERO, Vector3.ZERO]],
	"backend": [["mazo", "hand_r", Vector3(0, 1, 0), Vector3(0, 0.5, -0.85), Vector3(0.07, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)]],
	"ai": [["tableta", "hand_l", Vector3(0, 1, 0), Vector3(0, 0.6, -0.8), Vector3(-0.07, 0, 0), Vector3.ZERO, Vector3.ZERO]],
	"data": [["lanza", "hand_r", Vector3(0, 0, -1), Vector3(0, 0.05, -1), Vector3(0.07, 0, 0), Vector3.ZERO, Vector3.ZERO],
		["arco", "hand_l", Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(-0.07, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)]],
	"cyber": [["espada", "hand_r", Vector3(0, 1, 0), Vector3(0, 0.6, -0.8), Vector3(0.07, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
		["escudo", "fore_l", Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(-0.13, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]],
}

var current_selected_class := ""
var _botones := {}
var _vp: SubViewport
var _escenario: Node3D
var _giro: Node3D
var _rig: Node
var _visual: Node3D
var _arrastre := false
## Giro que el jugador le dio arrastrando (se suma al balanceo suave).
var _giro_usuario := 0.0
var _t := 0.0
var _nombre: Label
var _rol: Label
var _desc: Label
var _stats: VBoxContainer
var _armas: Label
var _hab: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Precarga de los modelos de todas las clases en segundo plano
	for c in ORDEN:
		var p := RIG.CLASS_MODEL % c
		if ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p)
	E.fondo(self)
	_armar_escenario()
	_armar_interfaz()
	_seleccionar(CLASSES.selected if CLASSES.CLASSES.has(CLASSES.selected) else "cyber")


# ----------------------------------------------------------------- 3D
func _armar_escenario() -> void:
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.anchor_left = 0.25
	cont.anchor_right = 0.66
	cont.anchor_top = 0.08
	cont.anchor_bottom = 0.9
	cont.mouse_filter = Control.MOUSE_FILTER_STOP
	cont.gui_input.connect(_input_modelo)
	add_child(cont)
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	cont.add_child(_vp)
	_escenario = Node3D.new()
	_vp.add_child(_escenario)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.46)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_escenario.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.1, 5.3)
	_escenario.add_child(cam)
	cam.look_at(Vector3(0, 0.92, 0))
	# Luz principal cálida, relleno frío y contraluces de neón azul
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 25, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	_escenario.add_child(key)
	for x in [-1.6, 1.6]:
		var rim := OmniLight3D.new()
		rim.position = Vector3(x, 1.6, -1.4)
		rim.light_color = E.NEON
		rim.light_energy = 3.0
		rim.omni_range = 4.0
		_escenario.add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.5, 1.0, 2.5)
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.light_energy = 0.8
	fill.omni_range = 6.0
	_escenario.add_child(fill)
	# Pedestal de metal con anillos de neón
	var ped := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.75
	cm.bottom_radius = 0.85
	cm.height = 0.16
	cm.radial_segments = 48
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.18, 0.2, 0.23)
	metal.metallic = 0.9
	metal.roughness = 0.3
	cm.material = metal
	ped.mesh = cm
	ped.position = Vector3(0, -0.08, 0)
	_escenario.add_child(ped)
	for r in [[0.79, 0.0, 0.012], [0.55, 0.002, 0.006]]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r[0] - r[2]
		tm.outer_radius = r[0] + r[2]
		tm.rings = 64
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(0.45, 0.9, 1.0) * 1.6
		tm.material = glow
		ring.mesh = tm
		ring.position = Vector3(0, r[1], 0)
		_escenario.add_child(ring)
	var halo := OmniLight3D.new()
	halo.position = Vector3(0, 0.1, 0)
	halo.light_color = E.NEON
	halo.light_energy = 1.5
	halo.omni_range = 1.6
	_escenario.add_child(halo)
	_giro = Node3D.new()
	_giro.rotation_degrees.y = 200.0
	_escenario.add_child(_giro)


func _poner_modelo(cls: String) -> void:
	if _visual:
		_visual.queue_free()
	if _rig:
		_rig.queue_free()
	_visual = Node3D.new()
	_giro.add_child(_visual)
	var model: Node3D = (load(PLAYER_MODEL) as PackedScene).instantiate()
	model.rotation_degrees = Vector3(0, 180, 0)
	model.scale = Vector3.ONE * 1.55
	_visual.add_child(model)
	_rig = RIG.new()
	_escenario.add_child(_rig)
	_rig.build(_visual, model, cls)
	var pose_lista: Dictionary = RIG.READY
	for a in ARMAS.get(cls, []):
		var path := "res://modelos/armas_jugador/%s.glb" % a[0]
		if not ResourceLoader.exists(path):
			continue
		var w: Node3D = (load(path) as PackedScene).instantiate()
		_visual.add_child(w)
		_rig.attach_weapon(w, a[1], a[2], a[3], pose_lista, a[4], a[5], a[6])
		if a[0] == "baston":
			# El orbe del bastón (en el juego lo pone el código)
			var orb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.08
			sm.height = 0.16
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.albedo_color = Color(0.5, 0.95, 1.0) * 2.0
			sm.material = gm
			orb.mesh = sm
			orb.position = Vector3(0, 0.96, 0)
			w.add_child(orb)
	if cls == "ai":
		var t := TorusMesh.new()
		t.inner_radius = 0.17
		t.outer_radius = 0.19
		var hm := StandardMaterial3D.new()
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.albedo_color = Color(0.6, 0.9, 1.0) * 1.8
		t.material = hm
		var h := MeshInstance3D.new()
		h.mesh = t
		h.position = Vector3(0, 0.35, 0)
		_rig.attachment("head").add_child(h)


func _process(delta: float) -> void:
	if _rig and is_instance_valid(_rig) and _rig.skeleton:
		_rig.animate(delta, {"speed": 0.0, "hold": true})
	if not _arrastre:
		_t += delta
	# De frente (3/4) con un balanceo suave, como en la creación de personaje de Dark Souls
	_giro.rotation.y = deg_to_rad(195.0 + 28.0 * sin(_t * 0.7)) + _giro_usuario


func _input_modelo(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_arrastre = event.pressed
	elif event is InputEventMouseMotion and _arrastre:
		_giro_usuario += event.relative.x * 0.01


# ----------------------------------------------------------------- 2D
func _armar_interfaz() -> void:
	var t := E.titulo("ELIGE TU CLASE", 40)
	t.position = Vector2(56, 26)
	add_child(t)
	var st := E.etiqueta("Cada clase tiene su armadura, sus armas y su forma de pelear", 15, E.TEXTO_TENUE)
	st.position = Vector2(60, 84)
	add_child(st)
	# Lista de clases
	var lista := VBoxContainer.new()
	lista.anchor_left = 0.0
	lista.anchor_right = 0.25
	lista.anchor_top = 0.0
	lista.anchor_bottom = 1.0
	lista.offset_left = 56
	lista.offset_top = 130
	lista.offset_bottom = -110
	lista.add_theme_constant_override("separation", 12)
	add_child(lista)
	for c in ORDEN:
		var d: Dictionary = CLASSES.CLASSES[c]
		var b := E.boton("%s\n%s" % [d["name"], String(d["role"]).to_upper()], 18, 0, 74)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.pressed.connect(_seleccionar.bind(c))
		lista.add_child(b)
		_botones[c] = b
	# Panel de información
	var p := E.panel(0.86)
	p.anchor_left = 0.67
	p.anchor_right = 1.0
	p.anchor_top = 0.0
	p.anchor_bottom = 1.0
	p.offset_top = 40
	p.offset_right = -46
	p.offset_bottom = -110
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	_nombre = E.titulo("", 28)
	_nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_nombre)
	_rol = E.etiqueta("", 18, E.NEON, 700)
	v.add_child(_rol)
	v.add_child(E.linea())
	_desc = E.etiqueta("", 15)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(200, 0)
	v.add_child(_desc)
	v.add_child(E.linea())
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 6)
	v.add_child(_stats)
	v.add_child(E.linea())
	_armas = E.etiqueta("", 15)
	_armas.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_armas)
	_hab = E.etiqueta("", 15)
	_hab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hab)
	# Botones de abajo
	var h := HBoxContainer.new()
	h.anchor_left = 0.0
	h.anchor_right = 1.0
	h.anchor_top = 1.0
	h.anchor_bottom = 1.0
	h.offset_top = -86
	h.offset_bottom = -26
	h.offset_left = 56
	h.offset_right = -46
	h.add_theme_constant_override("separation", 20)
	add_child(h)
	var volver := E.boton("Volver", 20, 220, 52)
	volver.alignment = HORIZONTAL_ALIGNMENT_CENTER
	volver.pressed.connect(_on_back_to_menu_pressed)
	h.add_child(volver)
	var hint := E.etiqueta("Arrastra el personaje para girarlo  ·  ↑ ↓ cambiar clase", 13, E.TEXTO_TENUE)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(hint)
	var ok := E.boton("Comenzar", 22, 280, 52)
	ok.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ok.add_theme_color_override("font_color", E.ORO)
	ok.pressed.connect(_on_confirm_button_pressed)
	h.add_child(ok)


func _stat(nombre: String, valor: float, maximo: float, texto: String) -> void:
	var h := HBoxContainer.new()
	var l := E.etiqueta(nombre, 15, E.TEXTO_TENUE)
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	var b := E.barra(valor, maximo)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	var t := E.etiqueta(texto, 15, E.TEXTO, 600)
	t.custom_minimum_size = Vector2(64, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(t)
	_stats.add_child(h)


func _seleccionar(cls: String) -> void:
	current_selected_class = cls
	_t = 0.0
	_giro_usuario = 0.0
	for c in _botones.keys():
		(_botones[c] as Button).set_pressed_no_signal(c == cls)
	var d: Dictionary = CLASSES.CLASSES[cls]
	var info: Dictionary = INFO[cls]
	_nombre.text = String(d["name"]).to_upper()
	_rol.text = String(d["role"]).to_upper()
	_desc.text = info["desc"]
	for c in _stats.get_children():
		c.queue_free()
	_stat("Vida", float(d["hp"]), 150.0, str(int(d["hp"])))
	_stat("Defensa", 1.0 - float(d["dmg_taken"]) + 0.15, 0.45, "%d %%" % roundi((1.0 - float(d["dmg_taken"])) * 100))
	_stat("Velocidad", float(d["run"]), 9.6, "%.1f" % float(d["run"]))
	_stat("Rodar", 50.0 - float(d["roll_cost"]), 35.0, "%d est." % roundi(float(d["roll_cost"])))
	_armas.text = "ARMAS   %s\nARMADURA   %s" % [info["armas"], String(d["armor"]).capitalize()]
	_hab.text = "HABILIDAD   %s" % info["habilidad"]
	_poner_modelo(cls)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var i := ORDEN.find(current_selected_class)
	match event.keycode:
		KEY_UP, KEY_W:
			_seleccionar(ORDEN[(i - 1 + ORDEN.size()) % ORDEN.size()])
		KEY_DOWN, KEY_S:
			_seleccionar(ORDEN[(i + 1) % ORDEN.size()])
		KEY_ENTER, KEY_KP_ENTER:
			_on_confirm_button_pressed()
		KEY_ESCAPE:
			_on_back_to_menu_pressed()


func _on_confirm_button_pressed() -> void:
	var partida := get_node_or_null("/root/Partida")
	var empezar := func():
		if partida:
			partida.nueva(current_selected_class)
		else:
			CLASSES.selected = current_selected_class
			get_tree().change_scene_to_file("res://Scenes/main.tscn")
	if partida and partida.hay_partida():
		E.confirmar(self, "¿Comenzar una partida nueva?\nTu partida guardada se reemplazará la primera vez que descanses en una hoguera.", empezar, "Comenzar", "Cancelar")
	else:
		empezar.call()


func _on_back_to_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/UI.tscn")
