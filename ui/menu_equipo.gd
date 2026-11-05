extends CanvasLayer
## Menú de equipo (tecla I): cambiar armas, armaduras y hechizos que ya tienes, con las
## rarezas del botín. Usa ui/panel_equipo.gd en modo "equipo" (el mismo de la pausa).
## Pausa el juego mientras está abierto; I o Esc lo cierran. Lo abre ui/menu_pausa.gd.

const E := preload("res://ui/estilo.gd")
const PANEL := preload("res://ui/panel_equipo.gd")
const EQUIPO := preload("res://jugador/equipo.gd")

var player: Node
var _resumen: Label


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var raiz := Control.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(raiz)
	var velo := ColorRect.new()
	velo.color = Color(0.0, 0.02, 0.04, 0.72)
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
	tv.add_child(E.titulo("EQUIPO", 34))
	_resumen = E.etiqueta("", 16, E.TEXTO_TENUE)
	tv.add_child(_resumen)
	var salir := E.boton("Cerrar  (I / Esc)", 18, 230, 46)
	salir.alignment = HORIZONTAL_ALIGNMENT_CENTER
	salir.pressed.connect(cerrar)
	cab.add_child(salir)
	v.add_child(E.linea())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var pe: VBoxContainer = PANEL.new()
	pe.modo = "equipo"
	pe.player = player
	pe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pe)
	var partida := get_node_or_null("/root/Partida")
	if partida:
		partida.inventario_cambiado.connect(_actualizar_resumen)
	_actualizar_resumen()


## "Arma: Excalibyte · Armadura: Traje de Faraday · Botín 3 / 10"
func _actualizar_resumen() -> void:
	var partida := get_node_or_null("/root/Partida")
	if partida == null or _resumen == null:
		return
	var arma: String = EQUIPO.weapon(String(partida.arma)).get("name", "Tus IAs") if String(partida.arma) != "" else "Tus IAs"
	var armadura: String = EQUIPO.armor(String(partida.armadura)).get("name", "Ropa de la clase") if String(partida.armadura) != "" else "Ropa de la clase"
	var total := 0
	var tienes := 0
	for id in EQUIPO.WEAPONS.keys():
		if EQUIPO.rarity_rank(id) > 0:
			total += 1
			if (partida.armas as Array).has(id):
				tienes += 1
	_resumen.text = "Arma: %s   ·   Armadura: %s   ·   Botín encontrado: %d / %d" % [arma, armadura, tienes, total]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_I]:
		get_viewport().set_input_as_handled()
		cerrar()


func cerrar() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
