extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_continue_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/scenes_3d.tscn")


func _on_new_game_buttom_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/scenes_3d.tscn")


func _on_settings_buttom_pressed() -> void:
	pass # Funcion de opciones


func _on_exit_buttom_pressed() -> void:
	get_tree().quit()
