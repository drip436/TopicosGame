extends Control
# Lista para asignar las 3 canciones en el Inspector
@export var canciones: Array[AudioStream] = []

@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer

func _ready() -> void:
	if canciones.size() > 0:
		# Selecciona una canción al azar
		var indice_aleatorio = randi() % canciones.size()
		
		# Asigna la canción elegida y la reproduce
		audio_player.stream = canciones[indice_aleatorio]
		audio_player.play()
	else:
		print("Asigna las canciones en el Inspector del nodo Control.")

# Called when the node enters the scene tree for the first time.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_continue_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/scenes_3d.tscn")


func _on_new_game_buttom_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/BuildSelector.tscn")


func _on_settings_buttom_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Settings.tscn")


func _on_exit_buttom_pressed() -> void:
	get_tree().quit()
