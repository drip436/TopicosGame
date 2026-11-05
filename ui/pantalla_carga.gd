extends CanvasLayer
## Pantalla de carga con barra de porcentaje. La usa Partida (ui/partida.gd) al empezar una
## partida nueva y al continuar la guardada:
##
##     PantallaCarga.ir(get_tree(), "res://Scenes/main.tscn", "nueva")   # o "continuar"
##
## El porcentaje es real, en tres tramos:
##   0 – 70 %  carga de la escena y sus recursos en segundo plano (ResourceLoader por hilos)
##  70 – 90 %  armado del mundo: CampusWorld, hogueras, enemigos, mercader, botín (VidaDelCampus)
##  90 – 100 % restaurar el guardado (Partida.aplicar → señal "restaurada"); en partida nueva,
##             unos cuadros para que compilen los shaders y no se vea el tirón
## Mientras está en pantalla el árbol tiene el meta "cargando"; la intro del autobús espera a
## que se quite para empezar. Se cuelga de /root, así que sobrevive al cambio de escena.

const E := preload("res://ui/estilo.gd")
const SCRIPT_PROPIO := "res://ui/pantalla_carga.gd"

const CONSEJOS := [
	"Descansar en una hoguera guarda la partida y recarga tus tazas de café.",
	"Rodar en el momento justo te hace invulnerable durante un instante.",
	"Los cofres con borde dorado guardan armas legendarias. Busca los haces de luz.",
	"Pulsa I para cambiar tus armas y armaduras.",
	"El mercader acepta créditos. Los enemigos los sueltan al caer.",
	"Cada jefe guarda una pieza de la llave del Aula Magna.",
	"Atacar gasta estamina: si se vacía, quedas expuesto.",
	"Las armaduras de resistencia reducen veneno, fuego y otros estados.",
	"Si mueres, tus créditos se quedan donde caíste. Vuelve por ellos.",
]

var ruta := ""
var modo := "nueva"   # "nueva" | "continuar"

var _mostrado := 0.0   # porcentaje que se ve (0..1), suavizado
var _objetivo := 0.0   # porcentaje real
var _raiz: Control
var _barra: ProgressBar
var _brillo: ColorRect
var _pct: Label
var _estado: Label
var _consejo: Label
var _t_consejo := 0.0
var _i_consejo := 0
var _restaurada := false


## Punto de entrada: crea la pantalla y empieza a cargar `ruta_escena`.
static func ir(arbol: SceneTree, ruta_escena: String, modo_carga := "nueva") -> void:
	var p: CanvasLayer = load(SCRIPT_PROPIO).new()
	p.ruta = ruta_escena
	p.modo = modo_carga
	p.name = "PantallaCarga"
	arbol.root.add_child(p)


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_meta("cargando", true)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_construir()
	_cargar()


# ------------------------------------------------------------------ interfaz

func _construir() -> void:
	_raiz = Control.new()
	_raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_raiz.mouse_filter = Control.MOUSE_FILTER_STOP   # nada atraviesa la pantalla de carga
	add_child(_raiz)
	var negro := ColorRect.new()
	negro.color = Color(0.0, 0.0, 0.0)
	negro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_raiz.add_child(negro)
	if ResourceLoader.exists(E.SHADER):
		E.fondo(_raiz, 0.55)

	# Bloque inferior: estado, barra y porcentaje
	var caja := VBoxContainer.new()
	caja.anchor_left = 0.0
	caja.anchor_right = 1.0
	caja.anchor_top = 1.0
	caja.anchor_bottom = 1.0
	caja.offset_left = 90
	caja.offset_right = -90
	caja.offset_top = -210
	caja.offset_bottom = -70
	caja.add_theme_constant_override("separation", 12)
	_raiz.add_child(caja)

	var fila := HBoxContainer.new()
	caja.add_child(fila)
	var tit := E.titulo("CARGANDO" if modo == "nueva" else "CONTINUANDO", 30)
	tit.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(tit)
	_pct = E.etiqueta("0 %", 30, E.NEON, 800)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct.custom_minimum_size = Vector2(130, 0)
	fila.add_child(_pct)

	_barra = E.barra(0.0, 100.0, E.NEON)
	_barra.custom_minimum_size = Vector2(0, 16)
	caja.add_child(_barra)
	# Destello que recorre la parte llena de la barra
	_brillo = ColorRect.new()
	_brillo.color = Color(1, 1, 1, 0.35)
	_brillo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brillo.size = Vector2(60, 16)
	_barra.add_child(_brillo)
	_barra.clip_contents = true

	_estado = E.etiqueta("Preparando…", 17, E.TEXTO, 600)
	caja.add_child(_estado)
	_consejo = E.etiqueta("", 15, E.TEXTO_TENUE, 500)
	_consejo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caja.add_child(_consejo)
	_i_consejo = randi() % CONSEJOS.size()
	_consejo.text = "Consejo: " + CONSEJOS[_i_consejo]

	# Arriba a la izquierda: qué se está cargando
	var sub := E.etiqueta(_subtitulo(), 16, E.TEXTO_TENUE, 500)
	sub.position = Vector2(90, 60)
	_raiz.add_child(sub)


func _subtitulo() -> String:
	if modo != "continuar":
		return "Nueva partida"
	var partida := get_node_or_null("/root/Partida")
	if partida and partida.has_method("resumen"):
		var r: Dictionary = partida.resumen()
		if not r.is_empty():
			var s := "Partida guardada  ·  %s" % String(r.get("clase", ""))
			if String(r.get("hoguera", "")) != "":
				s += "  ·  %s" % String(r["hoguera"])
			return s + "  ·  %s" % String(r.get("tiempo", ""))
	return "Partida guardada"


func _process(delta: float) -> void:
	# El número sube suave hacia el progreso real (nunca baja)
	_mostrado = move_toward(_mostrado, _objetivo, delta * maxf(0.6, (_objetivo - _mostrado) * 4.0))
	var v := _mostrado * 100.0
	_barra.value = v
	_pct.text = "%d %%" % int(floor(v))
	var lleno := _barra.size.x * _mostrado
	_brillo.position.x = fmod(Time.get_ticks_msec() / 1000.0 * 260.0, maxf(lleno + 60.0, 1.0)) - 60.0
	_brillo.visible = lleno > 8.0
	_t_consejo += delta
	if _t_consejo > 5.5:
		_t_consejo = 0.0
		_i_consejo = (_i_consejo + 1) % CONSEJOS.size()
		_consejo.text = "Consejo: " + CONSEJOS[_i_consejo]


func _poner(p: float, texto := "") -> void:
	_objetivo = maxf(_objetivo, clampf(p, 0.0, 1.0))
	if texto != "":
		_estado.text = texto


func _frame() -> void:
	await get_tree().process_frame


# ------------------------------------------------------------------ carga

func _cargar() -> void:
	await _frame()   # que la pantalla se dibuje antes de empezar

	# --- 1. Escena y recursos en segundo plano (0 – 70 %)
	_poner(0.02, "Cargando el campus…")
	var escena: PackedScene = null
	# Si la escena ya está en memoria (p. ej. volviste al menú y le diste Continuar), no
	# hace falta el hilo: se toma de la caché.
	if ResourceLoader.has_cached(ruta):
		escena = ResourceLoader.load(ruta, "PackedScene")
	# Carga en segundo plano SIN sub-hilos (con sub-hilos Godot a veces se traba en
	# algunos recursos y la barra se queda congelada).
	elif ResourceLoader.load_threaded_request(ruta, "PackedScene", false) == OK:
		var prog := []
		var ultimo := -1.0
		var quieto := 0.0
		while true:
			var st := ResourceLoader.load_threaded_get_status(ruta, prog)
			if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var f: float = prog[0] if prog.size() > 0 else 0.0
				_poner(0.02 + f * 0.68, "Cargando modelos y texturas…" if f > 0.35 else "Cargando el campus…")
				# Vigilante: si el progreso no se mueve en 6 s, se carga de forma directa
				if absf(f - ultimo) > 0.0005:
					ultimo = f
					quieto = 0.0
				else:
					quieto += get_process_delta_time()
					if quieto > 6.0:
						push_warning("PantallaCarga: la carga en segundo plano no avanza; se carga directo.")
						_poner(0.0, "Cargando (modo directo)…")
						await _frame()
						escena = ResourceLoader.load(ruta, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
						break
				await _frame()
			elif st == ResourceLoader.THREAD_LOAD_LOADED:
				escena = ResourceLoader.load_threaded_get(ruta)
				break
			else:
				break
	if escena == null:
		push_warning("PantallaCarga: falló la carga en segundo plano; se carga directo.")
		escena = load(ruta)
	_poner(0.70, "Construyendo el campus…")
	# Deja ver el 70 % antes del tirón de instanciar la escena
	while _mostrado < 0.69:
		await _frame()
	await _frame()

	# --- 2. Cambiar de escena y esperar a que el mundo esté armado (70 – 90 %)
	var partida := get_node_or_null("/root/Partida")
	if partida and partida.has_signal("restaurada") and not partida.restaurada.is_connected(_on_restaurada):
		partida.restaurada.connect(_on_restaurada)
	get_tree().change_scene_to_packed(escena)
	await _frame()
	await _frame()
	_poner(0.76, "Encendiendo hogueras…")
	var t := 0.0
	while t < 15.0:
		var vida := _vida()
		if vida and bool(vida.get("_ready_done")):
			break
		if vida == null and t > 3.0:   # escena sin VidaDelCampus: no hay nada que esperar
			break
		if t > 0.4:
			_poner(0.76 + 0.12 * (1.0 - exp(-t * 0.8)), "Despertando a los enemigos…" if t > 1.0 else "")
		t += get_process_delta_time()
		await _frame()
	_poner(0.90, "Colocando el botín…")

	# --- 3. Restaurar la partida guardada / calentar shaders (90 – 100 %)
	if modo == "continuar":
		_poner(0.91, "Restaurando tu partida…")
		t = 0.0
		while not _restaurada and t < 10.0 and _vida() != null:
			_poner(0.91 + 0.07 * (1.0 - exp(-t * 1.2)))
			t += get_process_delta_time()
			await _frame()
	else:
		_poner(0.92, "Preparando la llegada…")
		for i in 12:   # unos cuadros con todo cargado: compila shaders sin que se note en la intro
			_poner(0.92 + 0.06 * i / 12.0)
			await _frame()
	_poner(1.0, "Listo")
	while _mostrado < 0.999:
		await _frame()
	await get_tree().create_timer(0.35, true, false, true).timeout

	# --- Salida
	if get_tree().has_meta("cargando"):
		get_tree().remove_meta("cargando")
	if not get_tree().has_meta("intro_activa") or modo == "continuar":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var tw := create_tween()
	tw.tween_property(_raiz, "modulate:a", 0.0, 0.6)
	await tw.finished
	queue_free()


func _vida() -> Node:
	var s := get_tree().current_scene
	return s.find_child("VidaDelCampus", true, false) if s else null


func _on_restaurada() -> void:
	_restaurada = true
