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
