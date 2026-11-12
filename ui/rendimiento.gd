extends Node
## Ajustes de rendimiento ("modo patata"). Un solo nodo en /root (lo crea Partida al
## arrancar) que aplica el nivel elegido a TODO lo que exista o se cree después: ventana,
## luces, sombras, partículas, niebla, cámara y distancia de aparición de enemigos.
##
##     const REND := preload("res://ui/rendimiento.gd")
##     REND.iniciar(get_tree())                 # una vez, al arrancar (Partida._ready)
##     REND.poner(get_tree(), "patata")         # cambia y guarda el nivel
##     v.add_child(REND.panel(get_tree()))      # bloque de botones para un menú
##
## El nivel se guarda en user://rendimiento.cfg. La primera vez se elige solo: "baja" si la
## computadora tiene gráficos integrados, "alta" si tiene tarjeta dedicada.
## "alta" no toca nada: deja el juego tal como está hecho.

const E := preload("res://ui/estilo.gd")
const SCRIPT_PROPIO := "res://ui/rendimiento.gd"
const RUTA := "user://rendimiento.cfg"
const ORDEN := ["patata", "baja", "media", "alta"]

## escala      resolución interna del 3D (1.0 = la de la ventana)
## sol         sombras del sol / tormenta        sol_dist   hasta dónde llegan (m)
## luces_s     sombras de faroles y lámparas     luces_dist a qué distancia se apagan (m)
## part        fracción de partículas (lluvia, chispas, humo)
## niebla_vol, brillo, ssao, reflejos           efectos de pantalla
## lod         qué tan pronto se simplifican las mallas (más alto = antes)
## lejos       distancia máxima de dibujo (m)   fps  tope de cuadros (0 = sin tope)
## enemigos    a qué distancia aparecen / desaparecen los enemigos
const NIVELES := {
	"patata": {"nombre": "Patata (gráficos bajos)", "desc": "Para laptops sin tarjeta de video: mitad de resolución, sin sombras ni efectos, menos lluvia y menos enemigos activos a la vez.",
		"escala": 0.5, "sol": false, "sol_dist": 0.0, "luces_s": false, "luces_dist": 28.0, "part": 0.25,
		"niebla_vol": false, "brillo": false, "ssao": false, "reflejos": false, "lod": 4.0, "lejos": 150.0, "fps": 40,
		"atlas": 1024, "enemigos": [50.0, 70.0]},
	"baja": {"nombre": "Bajo", "desc": "Gráficos integrados recientes: resolución al 67 %, solo la sombra del sol y a corta distancia, sin efectos de pantalla.",
		"escala": 0.67, "sol": true, "sol_dist": 45.0, "luces_s": false, "luces_dist": 45.0, "part": 0.5,
		"niebla_vol": false, "brillo": false, "ssao": false, "reflejos": false, "lod": 2.5, "lejos": 220.0, "fps": 60,
		"atlas": 2048, "enemigos": [60.0, 85.0]},
	"media": {"nombre": "Medio", "desc": "Tarjeta de video modesta: resolución al 85 %, sombras del sol, brillo y niebla; sin oclusión ambiental ni reflejos.",
		"escala": 0.85, "sol": true, "sol_dist": 80.0, "luces_s": false, "luces_dist": 80.0, "part": 0.8,
		"niebla_vol": true, "brillo": true, "ssao": false, "reflejos": false, "lod": 1.5, "lejos": 320.0, "fps": 0,
		"atlas": 2048, "enemigos": [75.0, 105.0]},
	"alta": {"nombre": "Alto", "desc": "El juego tal como está hecho, con todos los efectos."},
}

var nivel := "alta"
var _t := 0.0


# ------------------------------------------------------------------ API

static func _instancia(arbol: SceneTree) -> Node:
	var n := arbol.root.get_node_or_null("Rendimiento")
	if n == null:
		n = load(SCRIPT_PROPIO).new()
		n.name = "Rendimiento"
		arbol.root.add_child.call_deferred(n)
	return n


static func iniciar(arbol: SceneTree) -> void:
	_instancia(arbol)


static func actual(arbol: SceneTree) -> String:
	return String(_instancia(arbol).get("nivel"))


static func poner(arbol: SceneTree, id: String) -> void:
	_instancia(arbol).call("cambiar", id)


## Bloque para un menú: una tarjeta por nivel (nombre, para qué equipo es y botón Usar).
static func panel(arbol: SceneTree) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var intro := E.etiqueta("Elige con qué calidad corre el juego. Se aplica al momento y se queda guardado.", 16, E.TEXTO_TENUE)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	var botones := {}
	var nombres := {}
	var pintar := func() -> void:
		var act := actual(arbol)
		for k in botones:
			var b: Button = botones[k]
			b.text = "EN USO" if k == act else "Usar"
			b.disabled = k == act
			(nombres[k] as Label).add_theme_color_override("font_color", E.NEON if k == act else E.TEXTO)
	for id: String in ORDEN:
		var pc := E.panel(0.75)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		pc.add_child(h)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		h.add_child(col)
		var nom := E.etiqueta(String(NIVELES[id]["nombre"]).to_upper(), 20, E.TEXTO, 700)
		col.add_child(nom)
		var d := E.etiqueta(String(NIVELES[id]["desc"]), 15, E.TEXTO_TENUE)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(300, 0)
		col.add_child(d)
		var b := E.boton("Usar", 17, 150, 42)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void:
			poner(arbol, id)
			pintar.call())
		h.add_child(b)
		botones[id] = b
		nombres[id] = nom
		v.add_child(pc)
	pintar.call()
	var nota := E.etiqueta("Si en Patata sigue lento, baja también la resolución de la ventana.", 14, E.TEXTO_TENUE)
	nota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nota)
	return v


# ------------------------------------------------------------------ interno

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(RUTA) == OK and NIVELES.has(String(cfg.get_value("rendimiento", "nivel", ""))):
		nivel = String(cfg.get_value("rendimiento", "nivel"))
	else:
		# Primera vez: gráficos integrados (o desconocidos) empiezan en "baja"
		var tipo := RenderingServer.get_video_adapter_type()
		nivel = "alta" if tipo == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU else "baja"
	print("Rendimiento: nivel '%s' (%s)" % [nivel, RenderingServer.get_video_adapter_name()])
	get_tree().node_added.connect(_on_nodo)
	_aplicar_todo()


func cambiar(id: String) -> void:
	if not NIVELES.has(id):
		return
	nivel = id
	var cfg := ConfigFile.new()
	cfg.set_value("rendimiento", "nivel", nivel)
	cfg.save(RUTA)
	_aplicar_todo()


func _process(delta: float) -> void:
	# El entorno y la cámara pueden cambiar (jefes, cinemática): se repasan cada 2 s
	_t += delta
	if _t > 2.0:
		_t = 0.0
		_ventana()
		for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			_nodo(n)
		var cam := get_viewport().get_camera_3d()
		if cam:
			_nodo(cam)


func _on_nodo(n: Node) -> void:
	if nivel == "alta":
		return
	# Solo lo que este script sabe ajustar (el campus crea miles de nodos al armarse)
	if n is Light3D or n is GPUParticles3D or n is WorldEnvironment or n is Camera3D or n is MultiMeshInstance3D or String(n.name) == "VidaDelCampus":
		_nodo.call_deferred(n)


func _aplicar_todo() -> void:
	_ventana()
	for n in get_tree().root.find_children("*", "", true, false):
		_nodo(n)


func _ventana() -> void:
	var vp := get_tree().root
	var c: Dictionary = NIVELES[nivel]
	if nivel == "alta":
		if vp.has_meta("_rend"):
			var o: Dictionary = vp.get_meta("_rend")
			vp.scaling_3d_scale = o["escala"]
			vp.scaling_3d_mode = o["modo"]
			vp.msaa_3d = o["msaa"]
			vp.screen_space_aa = o["ssaa"]
			vp.mesh_lod_threshold = o["lod"]
			vp.positional_shadow_atlas_size = o["atlas"]
			vp.use_debanding = o["deband"]
			Engine.max_fps = o["fps"]
			vp.remove_meta("_rend")
		return
	if not vp.has_meta("_rend"):
		vp.set_meta("_rend", {"escala": vp.scaling_3d_scale, "modo": vp.scaling_3d_mode, "msaa": vp.msaa_3d,
				"ssaa": vp.screen_space_aa, "lod": vp.mesh_lod_threshold, "atlas": vp.positional_shadow_atlas_size,
				"deband": vp.use_debanding, "fps": Engine.max_fps})
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(c["escala"])
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if nivel == "patata" else Viewport.SCREEN_SPACE_AA_FXAA
	vp.use_debanding = false
	vp.mesh_lod_threshold = float(c["lod"])
	vp.positional_shadow_atlas_size = int(c["atlas"]) if bool(c["luces_s"]) else 0
	RenderingServer.directional_shadow_atlas_set_size(int(c["atlas"]), true)
	Engine.max_fps = int(c["fps"])


## Guarda el valor original de una propiedad (una vez) y devuelve el diccionario.
func _orig(n: Node, props: Array) -> Dictionary:
	var o: Dictionary = n.get_meta("_rend") if n.has_meta("_rend") else {}
	for p: String in props:
		if not o.has(p):
			o[p] = n.get(p)
	n.set_meta("_rend", o)
	return o


func _restaurar(n: Object) -> void:
	if not n.has_meta("_rend"):
		return
	var o: Dictionary = n.get_meta("_rend")
	for p in o:
		n.set(p, o[p])
	n.remove_meta("_rend")


func _nodo(n: Node) -> void:
	if not is_instance_valid(n):
		return
	var alta := nivel == "alta"
	var c: Dictionary = NIVELES[nivel]
	if n is DirectionalLight3D:
		if alta:
			_restaurar(n)
			return
		var o := _orig(n, ["shadow_enabled", "directional_shadow_max_distance", "directional_shadow_mode"])
		var l := n as DirectionalLight3D
		l.shadow_enabled = bool(o["shadow_enabled"]) and bool(c["sol"])
		if bool(c["sol"]):
			l.directional_shadow_max_distance = minf(float(o["directional_shadow_max_distance"]), float(c["sol_dist"]))
			if nivel == "baja":
				l.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	elif n is OmniLight3D or n is SpotLight3D:
		if alta:
			_restaurar(n)
			return
		var o := _orig(n, ["shadow_enabled", "distance_fade_enabled", "distance_fade_begin", "distance_fade_length"])
		var l := n as Light3D
		l.shadow_enabled = bool(o["shadow_enabled"]) and bool(c["luces_s"])
		l.distance_fade_enabled = true
		var d := float(c["luces_dist"])
		if bool(o["distance_fade_enabled"]):
			d = minf(d, float(o["distance_fade_begin"]))
		l.distance_fade_begin = d
		l.distance_fade_length = 8.0
	elif n is GPUParticles3D:
		if alta:
			_restaurar(n)
			return
		_orig(n, ["amount_ratio"])
		(n as GPUParticles3D).amount_ratio = float(c["part"])
	elif n is WorldEnvironment:
		var env := (n as WorldEnvironment).environment
		if env == null:
			return
		if alta:
			_restaurar(env)
			return
		var o: Dictionary = env.get_meta("_rend") if env.has_meta("_rend") else {}
		for p: String in ["ssao_enabled", "ssil_enabled", "sdfgi_enabled", "ssr_enabled", "glow_enabled", "volumetric_fog_enabled"]:
			if not o.has(p):
				o[p] = env.get(p)
		env.set_meta("_rend", o)
		env.ssao_enabled = bool(o["ssao_enabled"]) and bool(c["ssao"])
		env.ssil_enabled = false
		env.sdfgi_enabled = false
		env.ssr_enabled = bool(o["ssr_enabled"]) and bool(c["reflejos"])
		env.glow_enabled = bool(o["glow_enabled"]) and bool(c["brillo"])
		env.volumetric_fog_enabled = bool(o["volumetric_fog_enabled"]) and bool(c["niebla_vol"])
	elif n is Camera3D:
		if alta:
			_restaurar(n)
			return
		var o := _orig(n, ["far"])
		(n as Camera3D).far = minf(float(o["far"]), float(c["lejos"]))
	elif n is MultiMeshInstance3D:
		# Sin sombra del sol no hace falta que la utilería instanciada proyecte sombra
		if alta or bool(c["sol"]):
			_restaurar(n)
		else:
			_orig(n, ["cast_shadow"])
			(n as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif String(n.name) == "VidaDelCampus":
		if alta:
			_restaurar(n)
			return
		var o := _orig(n, ["spawn_distance", "despawn_distance"])
		if o["spawn_distance"] != null:
			n.set("spawn_distance", minf(float(o["spawn_distance"]), float(c["enemigos"][0])))
			n.set("despawn_distance", minf(float(o["despawn_distance"]), float(c["enemigos"][1])))
