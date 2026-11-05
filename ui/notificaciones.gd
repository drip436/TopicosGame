extends CanvasLayer
## Notificaciones en la esquina superior derecha (armas y armaduras obtenidas, etc.).
## No necesita autoload: la primera llamada crea el nodo en /root y se reutiliza.
##
##     const NOTIF := preload("res://ui/notificaciones.gd")
##     NOTIF.arma(get_tree(), "excalibyte", 900)      # arma (créditos extra opcionales)
##     NOTIF.armadura(get_tree(), "faraday")          # armadura
##     NOTIF.aviso(get_tree(), "TÍTULO", "Nombre", "detalle", Color.WHITE)   # genérica
##
## Se apilan hacia abajo (máximo 4 a la vez), entran deslizándose desde la derecha y se
## van solas a los pocos segundos. No pausan el juego ni roban el ratón.

const E := preload("res://ui/estilo.gd")
const EQUIPO := preload("res://jugador/equipo.gd")
const SCRIPT_PROPIO := "res://ui/notificaciones.gd"

const ANCHO := 380.0
const MARGEN := Vector2(24, 24)
const SEPARACION := 10.0
const DURACION := 5.0
const MAX_VISIBLES := 4

var _caja: Control
var _activas: Array[Control] = []
var _cola: Array[Dictionary] = []


# ------------------------------------------------------------------ API

static func _instancia(arbol: SceneTree) -> CanvasLayer:
	var n := arbol.root.get_node_or_null("Notificaciones")
	if n == null:
		n = load(SCRIPT_PROPIO).new()
		n.name = "Notificaciones"
		arbol.root.add_child(n)
	return n


static func aviso(arbol: SceneTree, titulo: String, nombre: String, detalle := "", color := E.NEON, icono := "info", pie := "") -> void:
	if arbol == null:
		return
	_instancia(arbol).call("_encolar", {"titulo": titulo, "nombre": nombre, "detalle": detalle, "color": color, "icono": icono, "pie": pie})


static func arma(arbol: SceneTree, id: String, creditos := 0) -> void:
	var w: Dictionary = EQUIPO.weapon(id)
	if w.is_empty():
		return
	var titulo := "ARMA OBTENIDA"
	var color := E.NEON
	var rz: Dictionary = EQUIPO.RAREZAS.get(String(w.get("rarity", "")), {})
	if not rz.is_empty():
		titulo += "  ·  " + String(rz["name"]).to_upper()
		color = rz["color"]
	var kinds := {"espada": "Espada", "mazo": "Pesada", "estoque": "Estoque", "lanza": "Lanza"}
	var det := "%s  ·  Daño ×%.2f  ·  Vel. ×%.2f" % [kinds.get(w.get("kind", ""), String(w.get("kind", ""))), float(w.get("damage", 1.0)), float(w.get("speed", 1.0))]
	if w.has("status"):
		det += "  ·  " + EQUIPO.status_text(String(w["status"]))
	var pie := "I  para equipar"
	if creditos > 0:
		pie = "+ ◆ %d créditos   ·   %s" % [creditos, pie]
	aviso(arbol, titulo, String(w["name"]), det, color, "arma", pie)


static func armadura(arbol: SceneTree, id: String) -> void:
	var a: Dictionary = EQUIPO.armor(id)
	if a.is_empty():
		return
	var color: Color = a.get("color", E.NEON)
	var partes: Array[String] = []
	if a.has("defensa"):
		partes.append("Daño recibido −%d %%" % roundi((1.0 - float(a["defensa"])) * 100))
	var r: Dictionary = a.get("resist", {})
	for eff in r.keys():
		partes.append("Resiste " + EQUIPO.status_text(String(eff)).to_lower())
	aviso(arbol, "ARMADURA OBTENIDA", String(a["name"]), "  ·  ".join(partes), color, "armadura", "I  para equipar")


# ------------------------------------------------------------------ interno

func _ready() -> void:
	layer = 120   # encima del HUD y de los menús
	process_mode = Node.PROCESS_MODE_ALWAYS
	_caja = Control.new()
	_caja.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caja)


func _encolar(d: Dictionary) -> void:
	if _activas.size() >= MAX_VISIBLES:
		_cola.append(d)
		return
	_mostrar(d)


func _mostrar(d: Dictionary) -> void:
	var col: Color = d["color"]
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := E.caja(0.93, 0, 14, Color(col.r, col.g, col.b, 0.9))
	sb.border_width_left = 4
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_right = 1
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(ANCHO, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)

	var ic := _Icono.new()
	ic.tipo = String(d["icono"])
	ic.color = col
	ic.custom_minimum_size = Vector2(46, 46)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(E.etiqueta(String(d["titulo"]), 11, col, 800))
	var nom := E.etiqueta(String(d["nombre"]).to_upper(), 18, E.TEXTO, 800)
	nom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nom)
	if String(d["detalle"]) != "":
		var det := E.etiqueta(String(d["detalle"]), 11, E.TEXTO_TENUE, 500)
		det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(det)
	if String(d["pie"]) != "":
		v.add_child(E.etiqueta(String(d["pie"]), 11, E.ORO, 700))
	for c in v.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Barra de tiempo restante
	var barra := ColorRect.new()
	barra.color = Color(col.r, col.g, col.b, 0.7)
	var ancho_barra := ANCHO - 46.0 - 12.0 - 29.0
	barra.custom_minimum_size = Vector2(ancho_barra, 2)
	barra.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(barra)

	_caja.add_child(p)
	_activas.append(p)
	p.modulate.a = 0.0
	await get_tree().process_frame   # que calcule su alto
	if not is_instance_valid(p):
		return
	p.size = Vector2(ANCHO, p.get_combined_minimum_size().y)
	var destino := _x_destino()
	p.position = Vector2(destino + ANCHO * 0.6, _y_para(p))
	_reacomodar()
	var tw := p.create_tween().set_parallel(true)
	tw.tween_property(p, "position:x", destino, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	_sonido()
	barra.create_tween().tween_property(barra, "custom_minimum_size:x", 0.0, DURACION)
	await get_tree().create_timer(DURACION, true, false, true).timeout
	if not is_instance_valid(p):
		return
	var sal := p.create_tween().set_parallel(true)
	sal.tween_property(p, "position:x", destino + ANCHO * 0.5, 0.3).set_ease(Tween.EASE_IN)
	sal.tween_property(p, "modulate:a", 0.0, 0.3)
	await sal.finished
	_activas.erase(p)
	p.queue_free()
	_reacomodar()
	if not _cola.is_empty():
		_mostrar(_cola.pop_front())


func _x_destino() -> float:
	return get_viewport().get_visible_rect().size.x - MARGEN.x - ANCHO


func _y_para(p: Control) -> float:
	var y := MARGEN.y
	for a in _activas:
		if a == p:
			break
		if is_instance_valid(a):
			y += a.size.y + SEPARACION
	return y


## Las de abajo suben cuando se va una de arriba.
func _reacomodar() -> void:
	for a in _activas:
		if is_instance_valid(a):
			a.create_tween().tween_property(a, "position:y", _y_para(a), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Un "ding" corto sintetizado (no hace falta archivo de audio).
func _sonido() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.5
	var pl := AudioStreamPlayer.new()
	pl.stream = gen
	pl.volume_db = -14.0
	add_child(pl)
	pl.play()
	var pb := pl.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb:
		var n := int(gen.mix_rate * 0.32)
		for i in mini(n, pb.get_frames_available()):
			var t := i / gen.mix_rate
			var f := 880.0 if t < 0.09 else 1320.0
			var s := sin(TAU * f * t) * exp(-t * 9.0) * 0.6
			pb.push_frame(Vector2(s, s))
	get_tree().create_timer(0.6, true, false, true).timeout.connect(pl.queue_free)


## Iconito dibujado a mano (espada, escudo o "i").
class _Icono extends Control:
	var tipo := "info"
	var color := Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size
		var c := s * 0.5
		draw_circle(c, s.x * 0.5, Color(color.r, color.g, color.b, 0.16))
		draw_arc(c, s.x * 0.5 - 1.0, 0.0, TAU, 32, Color(color.r, color.g, color.b, 0.8), 1.5, true)
		match tipo:
			"arma":
				var a := c + Vector2(-s.x * 0.22, s.y * 0.22)
				var b := c + Vector2(s.x * 0.24, -s.y * 0.24)
				draw_line(a, b, color, 3.0, true)                               # hoja
				var g := c + Vector2(-s.x * 0.12, s.y * 0.12)
				draw_line(g + Vector2(-6, -6), g + Vector2(6, 6), color, 3.0, true)   # guarda
				draw_line(a, a + Vector2(-5, 5), color.lightened(0.3), 4.0, true)    # pomo
			"armadura":
				var w := s.x * 0.26
				var pts := PackedVector2Array([c + Vector2(-w, -w * 1.05), c + Vector2(w, -w * 1.05), c + Vector2(w, w * 0.15), c + Vector2(0, w * 1.15), c + Vector2(-w, w * 0.15)])
				draw_colored_polygon(pts, Color(color.r, color.g, color.b, 0.35))
				pts.append(pts[0])
				draw_polyline(pts, color, 2.0, true)
			_:
				draw_line(c + Vector2(0, -2), c + Vector2(0, s.y * 0.2), color, 3.0, true)
				draw_circle(c + Vector2(0, -s.y * 0.17), 2.5, color)
