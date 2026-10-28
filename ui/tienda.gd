extends CanvasLayer
## Tienda del mercader: armas y armaduras a cambio de créditos (ui/panel_equipo.gd en
## modo "tienda"). Pausa el juego mientras está abierta; Esc o "Salir" la cierran.

const E := preload("res://ui/estilo.gd")
const PANEL := preload("res://ui/panel_equipo.gd")

var player: Node


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var raiz := Control.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)
	var velo := ColorRect.new()
	velo.color = Color(0.0, 0.02, 0.04, 0.7)
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(velo)
	var p := E.panel(0.94)
	p.anchor_right = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = 120
	p.offset_right = -120
	p.offset_top = 50
	p.offset_bottom = -50
	raiz.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var cab := HBoxContainer.new()
	v.add_child(cab)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(tv)
	tv.add_child(E.titulo("EL MERCADER", 34))
	tv.add_child(E.etiqueta("\"Todo se paga en créditos, carnal. Los bichos de allá afuera los sueltan al morir.\"", 16, E.TEXTO_TENUE))
	var salir := E.boton("Salir  (Esc)", 18, 200, 46)
	salir.alignment = HORIZONTAL_ALIGNMENT_CENTER
	salir.pressed.connect(cerrar)
	cab.add_child(salir)
	v.add_child(E.linea())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var pe: VBoxContainer = PANEL.new()
	pe.modo = "tienda"
	pe.player = player
	pe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pe)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cerrar()


func cerrar() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
