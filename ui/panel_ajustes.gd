extends VBoxContainer
## Panel de ajustes (lo usan la pantalla de Ajustes del menú principal y el menú de pausa).
## Cada control cambia el autoload "Ajustes" al momento y se guarda en disco.

const E := preload("res://ui/estilo.gd")

var _filas := {}


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var aj := get_node_or_null("/root/Ajustes")
	if aj == null:
		add_child(E.etiqueta("(Falta el autoload Ajustes)", 18, E.PELIGRO))
		return
	_seccion("AUDIO")
	_slider(aj, "volumen", "Volumen general", 0.0, 1.0, 0.01, func(v): return "%d %%" % roundi(v * 100))
	_slider(aj, "musica", "Música", 0.0, 1.0, 0.01, func(v): return "%d %%" % roundi(v * 100))
	_seccion("IMAGEN")
	_slider(aj, "brillo", "Brillo", 0.5, 1.5, 0.01, func(v): return "%d %%" % roundi(v * 100))
	_slider(aj, "fov", "Campo de visión", 60.0, 100.0, 1.0, func(v): return "%d°" % roundi(v))
	_toggle(aj, "pantalla_completa", "Pantalla completa")
	_toggle(aj, "vsync", "Sincronización vertical (VSync)")
	_toggle(aj, "mostrar_fps", "Mostrar FPS")
	_seccion("CONTROLES")
	_slider(aj, "sensibilidad", "Sensibilidad del mouse", 0.25, 2.5, 0.05, func(v): return "%.2f×" % v)
	var r := E.boton("Restablecer valores", 16, 260, 42)
	r.alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.pressed.connect(func():
		var defs := {"volumen": 0.8, "musica": 0.7, "brillo": 1.0, "sensibilidad": 1.0, "fov": 70.0, "pantalla_completa": false, "vsync": true, "mostrar_fps": false}
		for k in defs.keys():
			aj.valores[k] = defs[k]
		aj.aplicar()
		aj.guardar()
		_refrescar(aj))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(r)
	add_child(h)


func _seccion(t: String) -> void:
	var l := E.etiqueta(t, 15, E.NEON, 700)
	add_child(l)
	add_child(E.linea())


func _slider(aj: Node, k: String, texto: String, a: float, b: float, paso: float, fmt: Callable) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := E.etiqueta(texto, 18)
	l.custom_minimum_size = Vector2(240, 0)
	h.add_child(l)
	var s := E.deslizador(a, b, paso, float(aj.get_valor(k)))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(s)
	var v := E.etiqueta(fmt.call(s.value), 18, E.NEON)
	v.custom_minimum_size = Vector2(80, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	s.value_changed.connect(func(x):
		v.text = fmt.call(x)
		aj.set_valor(k, x))
	add_child(h)
	_filas[k] = [s, v, fmt]


func _toggle(aj: Node, k: String, texto: String) -> void:
	var h := HBoxContainer.new()
	var l := E.etiqueta(texto, 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = bool(aj.get_valor(k))
	c.add_theme_font_override("font", E.fuente(600))
	c.add_theme_font_size_override("font_size", 16)
	c.text = "Sí" if c.button_pressed else "No"
	c.add_theme_color_override("font_color", E.NEON if c.button_pressed else E.TEXTO_TENUE)
	c.toggled.connect(func(on):
		c.text = "Sí" if on else "No"
		c.add_theme_color_override("font_color", E.NEON if on else E.TEXTO_TENUE)
		aj.set_valor(k, on))
	h.add_child(c)
	add_child(h)
	_filas[k] = [c]


func _refrescar(aj: Node) -> void:
	for k in _filas.keys():
		var f: Array = _filas[k]
		if f[0] is HSlider:
			(f[0] as HSlider).set_value_no_signal(float(aj.get_valor(k)))
			(f[1] as Label).text = (f[2] as Callable).call(float(aj.get_valor(k)))
		else:
			(f[0] as CheckButton).set_pressed_no_signal(bool(aj.get_valor(k)))
			(f[0] as CheckButton).text = "Sí" if aj.get_valor(k) else "No"
