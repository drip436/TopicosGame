extends Control

# Referencias a los nodos de la derecha
@onready var class_title: Label = $BackgroundShader/MainLayout/ContentLayout/InfoPanel/VBoxContainer/ClassTitle
@onready var class_description: Label = $BackgroundShader/MainLayout/ContentLayout/InfoPanel/VBoxContainer/ClassDescription

# Diccionario con la información de combate de cada clase
var classes_data = {
	"frontend": {
		"title": "Frontend Developer",
		"desc": "Mago. Lanza hechizos a distancia escribiendo código: bolas de fuego, rayos del cielo, lluvia de flechas, flechas que siguen funciones matemáticas, nova de área y frascos de veneno. Usa maná (barra azul) que recarga con bebidas energéticas. Armas: bastón tecnológico y estoque."
	},
	"backend": {
		"title": "Backend Developer",
		"desc": "Tanque. Armadura pesada que reduce el daño y un mazo con golpe sísmico de área. A cambio es lento y rodar para esquivar le cuesta mucha estamina."
	},
	"ai": {
		"title": "AI Dev",
		"desc": "Invocador. Pelea con IAs al estilo de los stands: ChatGPT (gigante de fuerza bruta), Gemini (arquero) y Claude (espadachín). Q cambia de IA; clic derecho usa su ataque especial."
	},
	"data": {
		"title": "Data Scientist",
		"desc": "Arquero. Flechas infinitas a distancia y una lanza para el cuerpo a cuerpo. Armadura básica pero es la clase más rápida."
	},
	"cyber": {
		"title": "Cybersecurity Engineer",
		"desc": "Caballero. Espada y escudo con armadura básica: mantén clic derecho para cubrirte y bloquear los golpes de frente."
	}
}

var current_selected_class: String = ""

func _ready() -> void:
	# Seleccionar Frontend por defecto al iniciar la pantalla
	_on_btn_frontend_pressed()

func _on_btn_frontend_pressed() -> void:
	current_selected_class = "frontend"
	class_title.text = classes_data["frontend"]["title"]
	class_description.text = classes_data["frontend"]["desc"]

func _on_btn_backend_pressed() -> void:
	current_selected_class = "backend"
	class_title.text = classes_data["backend"]["title"]
	class_description.text = classes_data["backend"]["desc"]

func _on_btn_ai_dev_pressed() -> void:
	current_selected_class = "ai"
	class_title.text = classes_data["ai"]["title"]
	class_description.text = classes_data["ai"]["desc"]

func _on_btn_data_scientist_pressed() -> void:
	current_selected_class = "data"
	class_title.text = classes_data["data"]["title"]
	class_description.text = classes_data["data"]["desc"]

func _on_btn_cibersegurity_pressed() -> void:
	current_selected_class = "cyber"
	class_title.text = classes_data["cyber"]["title"]
	class_description.text = classes_data["cyber"]["desc"]

func _on_confirm_button_pressed() -> void:
	print("¡Build confirmada! Clase elegida: ", current_selected_class)
	preload("res://jugador/player_classes.gd").selected = current_selected_class
	# Aquí puedes poner la lógica para cambiar de escena al juego real:
	get_tree().change_scene_to_file("res://Scenes/main.tscn")


func _on_back_to_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/UI.tscn")
