extends Control
## Pantalla de Ajustes del menú principal: fondo de metal con neón y el panel de ajustes
## compartido con el menú de pausa (ui/panel_ajustes.gd). Todo se guarda solo.

const E := preload("res://ui/estilo.gd")
const AJUSTES := preload("res://ui/panel_ajustes.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	E.fondo(self)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var p := E.panel(0.9)
	p.custom_minimum_size = Vector2(820, 0)
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	v.add_child(E.titulo("AJUSTES", 40))
	v.add_child(E.linea())
	v.add_child(AJUSTES.new())
	var volver := E.boton("Volver al menú", 20, 260, 48)
	volver.alignment = HORIZONTAL_ALIGNMENT_CENTER
	volver.pressed.connect(_on_button_pressed)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(volver)
	v.add_child(h)
	volver.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_button_pressed()


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/UI.tscn")
