extends Control
## Menú principal. Conserva el video de fondo, el título y la música de UI.tscn, y arma
## encima el menú con el estilo de metal y neón (ui/estilo.gd):
##   Continuar      (solo si hay partida guardada: la carga donde la dejaste)
##   Nueva partida  (va al selector de clase)
##   Ajustes · Salir
# Lista para asignar las canciones en el Inspector (se elige una al azar)
@export var canciones: Array[AudioStream] = []

const E := preload("res://ui/estilo.gd")

@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer

var _info: Label
var _continuar: Button


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# La escena traía la raíz desplazada 2300 px y los hijos compensándolo: se acomoda todo
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var video := get_node_or_null("VideoStreamPlayer") as Control
	if video:
		video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var old := get_node_or_null("VBoxContainer") as Control
	if old:
		old.visible = false
	# Velo oscuro y franja de metal a la izquierda
	var velo := ColorRect.new()
	velo.color = Color(0.0, 0.02, 0.05, 0.35)
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(velo)
	var franja := Control.new()
	franja.anchor_bottom = 1.0
	franja.offset_right = 470
	franja.clip_contents = true
	add_child(franja)
	var fondo := E.fondo(franja, 0.9)
	fondo.modulate.a = 0.92
	var borde := ColorRect.new()
	borde.color = Color(E.NEON.r, E.NEON.g, E.NEON.b, 0.85)
	borde.anchor_left = 1.0
	borde.anchor_right = 1.0
	borde.anchor_bottom = 1.0
	borde.offset_left = -2
	franja.add_child(borde)
	# Título del juego (la imagen) arriba de la franja
	var title := get_node_or_null("TextureRect") as TextureRect
	if title:
		title.reparent(franja)
		title.rotation = 0.0
		title.scale = Vector2.ONE
		title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title.anchor_left = 0.0
		title.anchor_right = 1.0
		title.anchor_top = 0.0
		title.anchor_bottom = 0.0
		title.offset_left = 20
		title.offset_right = -20
		title.offset_top = 30
		title.offset_bottom = 230
	var col := VBoxContainer.new()
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = 60
	col.offset_top = 260
	col.offset_right = 420
	col.offset_bottom = -40
	col.add_theme_constant_override("separation", 14)
	franja.add_child(col)
	var partida := get_node_or_null("/root/Partida")
	_continuar = E.boton("Continuar", 24)
	_continuar.pressed.connect(_on_continue_button_pressed)
	col.add_child(_continuar)
	_info = E.etiqueta("", 14, E.TEXTO_TENUE)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info)
	var nueva := E.boton("Nueva partida", 24)
	nueva.pressed.connect(_on_new_game_buttom_pressed)
	col.add_child(nueva)
	var ajustes := E.boton("Ajustes", 24)
	ajustes.pressed.connect(_on_settings_buttom_pressed)
	col.add_child(ajustes)
	var salir := E.boton("Salir", 24)
	salir.pressed.connect(_on_exit_buttom_pressed)
	col.add_child(salir)
	var ver := E.etiqueta("Esc · Volver   ·   TopicosGame", 12, E.TEXTO_TENUE)
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 60
	ver.offset_top = -34
	franja.add_child(ver)
	var r: Dictionary = partida.resumen() if partida else {}
	if r.is_empty():
		_continuar.disabled = true
		_info.text = "Sin partida guardada · descansa en una hoguera para guardar"
		nueva.grab_focus.call_deferred()
	else:
		_info.text = "%s\n%s · %s\nJefes vencidos %d · Piezas de llave %d/4" % [r["clase"], r["hoguera"], r["tiempo"], r["jefes"], r["llaves"]]
		_continuar.grab_focus.call_deferred()
	# Música (en el bus Música, para que la controle Ajustes)
	audio_player.volume_db = -6.0
	if AudioServer.get_bus_index("Musica") >= 0:
		audio_player.bus = "Musica"
	if canciones.size() > 0:
		audio_player.stream = canciones[randi() % canciones.size()]
		audio_player.play()


func _on_continue_button_pressed() -> void:
	var partida := get_node_or_null("/root/Partida")
	if partida == null or not partida.continuar():
		_info.text = "No se pudo cargar la partida guardada."


func _on_new_game_buttom_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/BuildSelector.tscn")


func _on_settings_buttom_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Settings.tscn")


func _on_exit_buttom_pressed() -> void:
	E.confirmar(self, "¿Salir del juego?", func(): get_tree().quit())
