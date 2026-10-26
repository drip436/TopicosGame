extends RefCounted
## Estilo de los menús: metal oscuro con neón azul (menú principal, selector de clase,
## ajustes y pausa). Todo se arma en código para que se vea igual en todas las pantallas.
##   const E := preload("res://ui/estilo.gd")
##   E.fondo(self); var b := E.boton("Continuar"); E.panel(...)

const NEON := Color(0.3, 0.8, 1.0)
const NEON_SUAVE := Color(0.3, 0.8, 1.0, 0.45)
const TEXTO := Color(0.86, 0.92, 0.98)
const TEXTO_TENUE := Color(0.55, 0.63, 0.72)
const ORO := Color(0.95, 0.8, 0.45)
const PELIGRO := Color(1.0, 0.35, 0.3)
const FUENTE := "res://Orbitron-VariableFont_wght.ttf"
const SHADER := "res://ui/fondo_metal.gdshader"

static var _fuentes := {}


## Orbitron con el grosor pedido (400 normal, 700 negrita).
static func fuente(peso := 500) -> Font:
	if _fuentes.has(peso):
		return _fuentes[peso]
	var f := FontVariation.new()
	f.base_font = load(FUENTE)
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): peso}
	_fuentes[peso] = f
	return f


## Caja de metal con borde de neón y resplandor.
static func caja(alpha := 0.92, borde := 2, brillo := 10, color_borde := NEON_SUAVE, fondo := Color(0.035, 0.045, 0.06)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(fondo.r, fondo.g, fondo.b, alpha)
	s.border_color = color_borde
	s.set_border_width_all(borde)
	s.set_corner_radius_all(3)
	s.corner_detail = 2
	s.shadow_color = Color(NEON.r, NEON.g, NEON.b, 0.18 if brillo > 0 else 0.0)
	s.shadow_size = brillo
	s.set_content_margin_all(18)
	return s


## Fondo animado de metal con neón (cubre todo el control).
static func fondo(parent: Control, fuerza := 1.0) -> ColorRect:
	var r := ColorRect.new()
	r.name = "FondoMetal"
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("neon_strength", fuerza)
	r.material = m
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	r.resized.connect(func(): m.set_shader_parameter("aspect", r.size.x / maxf(r.size.y, 1.0)))
	return r


static func etiqueta(texto: String, tam := 20, color := TEXTO, peso := 500) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_override("font", fuente(peso))
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	return l


## Título con brillo de neón.
static func titulo(texto: String, tam := 40) -> Label:
	var l := etiqueta(texto, tam, Color(0.82, 0.95, 1.0), 800)
	l.add_theme_color_override("font_outline_color", Color(NEON.r, NEON.g, NEON.b, 0.55))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_shadow_color", Color(NEON.r, NEON.g, NEON.b, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.add_theme_constant_override("shadow_outline_size", 18)
	return l


## Botón de menú: placa de metal que se ilumina de neón al pasar el mouse.
static func boton(texto: String, tam := 22, ancho := 340.0, alto := 54.0) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(ancho, alto)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", fuente(600))
	b.add_theme_font_size_override("font_size", tam)
	b.add_theme_color_override("font_color", TEXTO)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.7, 0.95, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.35, 0.4, 0.46))
	b.add_theme_color_override("font_outline_color", Color(NEON.r, NEON.g, NEON.b, 0.0))
	var normal := caja(0.88, 1, 0, Color(0.4, 0.5, 0.6, 0.45), Color(0.07, 0.08, 0.1))
	normal.border_width_left = 4
	normal.border_color = Color(0.35, 0.55, 0.7, 0.6)
	normal.set_content_margin_all(10)
	var hover := caja(0.95, 1, 14, NEON, Color(0.06, 0.13, 0.19))
	hover.border_width_left = 6
	hover.set_content_margin_all(10)
	var pressed := caja(0.98, 2, 18, NEON, Color(0.08, 0.25, 0.36))
	pressed.set_content_margin_all(10)
	var disabled := caja(0.7, 1, 0, Color(0.3, 0.33, 0.36, 0.4), Color(0.05, 0.055, 0.06))
	disabled.set_content_margin_all(10)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# El texto se separa un poco al pasar el mouse
	b.mouse_entered.connect(func():
		if not b.disabled:
			b.grab_focus())
	return b


static func panel(alpha := 0.9) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", caja(alpha))
	return p


## Línea de neón horizontal.
static func linea(ancho := 0.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(NEON.r, NEON.g, NEON.b, 0.7)
	r.custom_minimum_size = Vector2(ancho, 2)
	return r


## Barra de atributo (vida, estamina…) con relleno de neón.
static func barra(valor: float, maximo: float, color := NEON) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = maximo
	b.value = valor
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.08, 0.95)
	bg.border_color = Color(0.3, 0.4, 0.5, 0.5)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.shadow_color = Color(color.r, color.g, color.b, 0.4)
	fg.shadow_size = 4
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


## Deslizador con estilo (ajustes).
static func deslizador(minv: float, maxv: float, paso: float, valor: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = paso
	s.value = valor
	s.custom_minimum_size = Vector2(260, 26)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.1, 0.13)
	track.border_color = Color(0.3, 0.45, 0.55, 0.6)
	track.set_border_width_all(1)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(NEON.r, NEON.g, NEON.b, 0.75)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	return s


## Ventana de confirmación encima de todo: [Sí] [No]. on_si se llama al aceptar.
static func confirmar(parent: Control, texto: String, on_si: Callable, si := "Sí", no := "No") -> Control:
	var capa := ColorRect.new()
	capa.color = Color(0, 0, 0, 0.65)
	capa.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	capa.mouse_filter = Control.MOUSE_FILTER_STOP
	capa.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(capa)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	capa.add_child(c)
	var p := panel(0.97)
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	p.add_child(v)
	var l := etiqueta(texto, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	v.add_child(l)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	var bs := boton(si, 20, 180, 48)
	var bn := boton(no, 20, 180, 48)
	bs.alignment = HORIZONTAL_ALIGNMENT_CENTER
	bn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(bs)
	h.add_child(bn)
	bs.pressed.connect(func():
		capa.queue_free()
		on_si.call())
	bn.pressed.connect(capa.queue_free)
	bn.grab_focus.call_deferred()
	return capa
