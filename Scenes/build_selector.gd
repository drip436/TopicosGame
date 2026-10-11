extends Control

# Referencias a los nodos de la derecha
@onready var class_title: Label = $BackgroundShader/MainLayout/ContentLayout/InfoPanel/VBoxContainer/ClassTitle
@onready var class_description: Label = $BackgroundShader/MainLayout/ContentLayout/InfoPanel/VBoxContainer/ClassDescription

# Diccionario con la información de combate de cada clase
var classes_data = {
	"frontend": {
		"title": "Frontend Developer",
		"desc": "Especialista en control de masas y velocidad. Ataca a distancia manipulando el entorno visual y aplicando cegueras/alucinaciones a los enemigos."
	},
	"backend": {
		"title": "Backend Developer",
		"desc": "Tanque de alta resistencia y fuerza bruta. Soporta grandes cantidades de daño, genera escudos de datos y ejecuta ataques pesados de área."
	},
	"ai": {
		"title": "AI Dev",
		"desc": "Invocador y táctico. Despliega drones autónomos y centinelas inteligentes que atacan solos mientras predice y esquiva los patrones del enemigo."
	},
	"data": {
		"title": "Data Scientist",
		"desc": "Atacante de precisión y puntos débiles. Analiza las estadísticas de los rivales en tiempo real para asestar golpes críticos devastadores."
	},
	"cyber": {
		"title": "Cybersecurity Engineer",
		"desc": "Especialista en contraataque y debuffs. Cifra a los enemigos para inmovilizarlos, devuelve el daño recibido y anula sus habilidades."
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
	# Aquí puedes poner la lógica para cambiar de escena al juego real:
	get_tree().change_scene_to_file("res://Scenes/scenes_3d.tscn")


func _on_back_to_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/UI.tscn")
