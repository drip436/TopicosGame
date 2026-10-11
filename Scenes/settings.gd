extends Control

#Llama al slider del volumen
@onready var volume_slider: HSlider = $VolumeHSlider
#Llama al checkbox
@onready var fullscreen_checkbox: CheckBox = $FullScreenCheckBox

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
# Cargar valores actuales al abrir el menú
	var bus_index = AudioServer.get_bus_index("Master")
	volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus_index))
	
	# Verificar si la ventana está en modo pantalla completa
	var current_mode = DisplayServer.window_get_mode()
	fullscreen_checkbox.button_pressed = (current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_volume_h_slider_value_changed(value: float) -> void:
	var bus_index = AudioServer.get_bus_index("Master")
	# Convertimos el valor lineal (0.0 a 1.0) a decibelios (dB)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))


func _on_brightness_h_slider_value_changed(_value: float) -> void:
	pass


func _on_full_screen_check_box_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/UI.tscn")
