extends Node
## Autoload "Ajustes": opciones del juego guardadas en user://ajustes.cfg y aplicadas en
## todas las escenas (menú principal, ajustes, pausa y juego).
##   volumen        volumen general (0..1, bus Master)
##   musica         volumen de la música (0..1, bus "Musica"; el menú usa ese bus)
##   brillo         brillo de la imagen en el juego (0.5..1.5, Environment del mundo)
##   sensibilidad   sensibilidad del mouse (0.25..2.5, multiplica la del jugador)
##   fov            campo de visión de la cámara del jugador (60..100)
##   pantalla_completa, vsync, mostrar_fps

signal cambiado

const RUTA := "user://ajustes.cfg"

var valores := {
	"volumen": 0.8,
	"musica": 0.7,
	"brillo": 1.0,
	"sensibilidad": 1.0,
	"fov": 70.0,
	"pantalla_completa": false,
	"vsync": true,
	"mostrar_fps": false,
}

var _fps: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Musica") < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Musica")
		AudioServer.set_bus_send(i, "Master")
	cargar()
	# Contador de FPS en una capa propia (encima de todo)
	var capa := CanvasLayer.new()
	capa.layer = 120
	add_child(capa)
	_fps = Label.new()
	_fps.position = Vector2(12, 8)
	_fps.add_theme_font_size_override("font_size", 16)
	_fps.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	capa.add_child(_fps)
	get_tree().node_added.connect(_on_node_added)
	aplicar()


func _process(_delta: float) -> void:
	_fps.visible = bool(valores["mostrar_fps"])
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


func get_valor(k: String) -> Variant:
	return valores.get(k)


func set_valor(k: String, v: Variant) -> void:
	valores[k] = v
	aplicar()
	guardar()
	cambiado.emit()


func cargar() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(RUTA) != OK:
		return
	for k in valores.keys():
		valores[k] = cfg.get_value("ajustes", k, valores[k])


func guardar() -> void:
	var cfg := ConfigFile.new()
	for k in valores.keys():
		cfg.set_value("ajustes", k, valores[k])
	cfg.save(RUTA)


func aplicar() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(float(valores["volumen"]), 0.0001)))
	var mi := AudioServer.get_bus_index("Musica")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(float(valores["musica"]), 0.0001)))
	var fs: bool = valores["pantalla_completa"]
	var modo := DisplayServer.window_get_mode()
	if fs and modo != DisplayServer.WINDOW_MODE_FULLSCREEN and modo != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fs and (modo == DisplayServer.WINDOW_MODE_FULLSCREEN or modo == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if valores["vsync"] else DisplayServer.VSYNC_DISABLED)
	if get_tree():
		for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			_brillo(n as WorldEnvironment)
		for p in get_tree().get_nodes_in_group("player"):
			var cam = p.get("camera")
			if cam is Camera3D:
				(cam as Camera3D).fov = float(valores["fov"])


func _on_node_added(n: Node) -> void:
	if n is WorldEnvironment:
		_brillo.call_deferred(n)


func _brillo(we: WorldEnvironment) -> void:
	if not is_instance_valid(we) or we.environment == null:
		return
	var env := we.environment
	env.adjustment_enabled = true
	env.adjustment_brightness = float(valores["brillo"])
