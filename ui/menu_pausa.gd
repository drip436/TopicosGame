extends CanvasLayer
## Menú de pausa (Esc durante el juego). Pausa el juego y muestra:
##   Continuar · Estado del personaje · Controles · Ajustes · Volver a la última hoguera
##   (si te atoras; no durante una pelea de jefe) · Menú principal · Salir del juego.
## Las salidas piden confirmación: lo que no se guardó desde la última hoguera se pierde.
## Lo crea el jugador (boss_profesor/test_player.gd).

const E := preload("res://ui/estilo.gd")
const AJUSTES := preload("res://ui/panel_ajustes.gd")
const CLASSES := preload("res://jugador/player_classes.gd")
const MENU := "res://Scenes/UI.tscn"

var player: Node
var abierto := false
var _raiz: Control
var _contenido: PanelContainer
var _botones := {}
var _btn_hoguera: Button
var _seccion := ""


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_raiz = Control.new()
	_raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_raiz.visible = false
	add_child(_raiz)
	# Velo oscuro sobre el juego + franja de metal a la izquierda
	var velo := ColorRect.new()
	velo.color = Color(0.0, 0.02, 0.04, 0.72)
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_raiz.add_child(velo)
	var franja := Control.new()
	franja.anchor_bottom = 1.0
	franja.offset_right = 430
	franja.clip_contents = true
	_raiz.add_child(franja)
	E.fondo(franja, 0.8)
	var borde := ColorRect.new()
	borde.color = Color(E.NEON.r, E.NEON.g, E.NEON.b, 0.8)
	borde.anchor_left = 1.0
	borde.anchor_right = 1.0
	borde.anchor_bottom = 1.0
	borde.offset_left = -2
	franja.add_child(borde)
	var col := VBoxContainer.new()
	col.position = Vector2(46, 60)
	col.add_theme_constant_override("separation", 12)
	franja.add_child(col)
	col.add_child(E.titulo("PAUSA", 44))
	var sub := E.etiqueta("", 15, E.TEXTO_TENUE)
	sub.name = "Sub"
	col.add_child(sub)
	col.add_child(E.linea(330))
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 12)
	col.add_child(sep)
	for b in [["continuar", "Continuar"], ["estado", "Estado del personaje"], ["controles", "Controles"], ["ajustes", "Ajustes"],
			["hoguera", "Volver a la hoguera"], ["menu", "Menú principal"], ["salir", "Salir del juego"]]:
		var btn := E.boton(b[1], 20, 330, 50)
		btn.pressed.connect(_on_boton.bind(b[0]))
		col.add_child(btn)
		_botones[b[0]] = btn
	_btn_hoguera = _botones["hoguera"]
	# Panel de contenido a la derecha
	_contenido = E.panel(0.9)
	_contenido.anchor_left = 0.0
	_contenido.anchor_right = 1.0
	_contenido.anchor_bottom = 1.0
	_contenido.offset_left = 480
	_contenido.offset_top = 60
	_contenido.offset_right = -60
	_contenido.offset_bottom = -60
	_raiz.add_child(_contenido)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if abierto:
			# Esc cierra primero una confirmación abierta, luego el menú
			var conf := _raiz.get_children().filter(func(c): return c is ColorRect and c.mouse_filter == Control.MOUSE_FILTER_STOP and c != _raiz.get_child(0))
			if conf.size() > 0:
				conf[-1].queue_free()
			else:
				cerrar()
		else:
			abrir()
		get_viewport().set_input_as_handled()


func abrir() -> void:
	if abierto:
		return
	abierto = true
	_raiz.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var cls: Dictionary = CLASSES.data(String(player.get("class_id"))) if player else {}
	var partida := get_node_or_null("/root/Partida")
	(_raiz.find_child("Sub", true, false) as Label).text = "%s · %s\nTiempo jugado  %s" % [cls.get("name", ""), cls.get("role", ""),
		partida.formato_tiempo(partida.tiempo) if partida else "--"]
	_btn_hoguera.disabled = _en_pelea() or player == null or bool(player.get("is_dead"))
	_mostrar("estado")
	_botones["continuar"].grab_focus.call_deferred()


func cerrar() -> void:
	abierto = false
	_raiz.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_boton(id: String) -> void:
	match id:
		"continuar":
			cerrar()
		"estado", "controles", "ajustes":
			_mostrar(id)
		"hoguera":
			E.confirmar(_raiz, "¿Volver a la última hoguera?\nÚsalo si te quedaste atorado. Los enemigos reaparecen.", _volver_hoguera)
		"menu":
			E.confirmar(_raiz, "¿Volver al menú principal?\nSe pierde lo que hayas hecho desde la última hoguera en la que descansaste.", _ir_menu)
		"salir":
			E.confirmar(_raiz, "¿Salir del juego?\nSe pierde lo que hayas hecho desde la última hoguera en la que descansaste.", func(): get_tree().quit())


func _mostrar(seccion: String) -> void:
	_seccion = seccion
	for c in _contenido.get_children():
		c.queue_free()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_contenido.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	scroll.add_child(v)
	match seccion:
		"estado":
			_estado(v)
		"controles":
			_controles(v)
		"ajustes":
			v.add_child(E.titulo("AJUSTES", 30))
			v.add_child(AJUSTES.new())


func _fila(v: VBoxContainer, a: String, b: String, color := E.TEXTO) -> void:
	var h := HBoxContainer.new()
	var l := E.etiqueta(a, 18, E.TEXTO_TENUE)
	l.custom_minimum_size = Vector2(250, 0)
	h.add_child(l)
	var r := E.etiqueta(b, 18, color, 600)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(120, 0)
	h.add_child(r)
	v.add_child(h)


func _estado(v: VBoxContainer) -> void:
	v.add_child(E.titulo("ESTADO DEL PERSONAJE", 30))
	if player == null:
		return
	var cls: Dictionary = CLASSES.data(String(player.get("class_id")))
	_fila(v, "Clase", "%s  ·  %s" % [cls["name"], cls["role"]], E.NEON)
	v.add_child(E.linea())
	var hp := float(player.get("hp"))
	var mhp := float(player.get("max_hp"))
	_fila(v, "Vida", "%d / %d" % [hp, mhp])
	v.add_child(E.barra(hp, mhp, Color(0.85, 0.15, 0.12)))
	var st := float(player.get("stamina"))
	var mst := float(player.get("max_stamina"))
	_fila(v, "Estamina", "%d / %d" % [st, mst])
	v.add_child(E.barra(st, mst, Color(0.25, 0.75, 0.3)))
	var kit = player.get("kit")
	if kit and float(kit.get("max_mana")) > 0.0:
		_fila(v, "Maná", "%d / %d   ·   bebidas %d" % [float(kit.get("mana")), float(kit.get("max_mana")), int(kit.get("drinks"))])
		v.add_child(E.barra(float(kit.get("mana")), float(kit.get("max_mana")), Color(0.25, 0.5, 1.0)))
	var mx: int = player.get_max_flasks() if player.has_method("get_max_flasks") else 4
	_fila(v, "Cafés (curación)", "%d / %d" % [int(player.get("flasks")), mx])
	_fila(v, "Armadura", "%s  ·  recibes %d %% del daño" % [String(cls["armor"]).capitalize(), roundi(float(cls["dmg_taken"]) * 100)])
	var res := "Ninguna"
	if kit and String(kit.get("resist_id")) != "":
		res = CLASSES.RESIST_ARMORS[String(kit.get("resist_id"))]["name"]
	_fila(v, "Armadura de resistencia", res)
	_fila(v, "Velocidad", "%.1f m/s caminando · %.1f m/s corriendo" % [float(cls["walk"]), float(cls["run"])])
	v.add_child(E.linea())
	var world := get_tree().current_scene.find_child("CampusWorld", true, false) if get_tree().current_scene else null
	var piezas := 0
	if world and world.get("key_pieces") is Dictionary:
		piezas = (world.get("key_pieces") as Dictionary).size()
	_fila(v, "Piezas de la llave del Aula Magna", "%d / 4" % piezas, E.ORO)
	var jefes: Array = []
	var nombres := {"BossFight": "Catedrático de Hierro", "LibraryFight": "Bibliófilo Demente", "ComputeFight": "ADA-7", "LabFight": "Dr. Kessler", "FinalFight": "Rector Eterno"}
	for f in nombres.keys():
		var n := get_tree().current_scene.find_child(f, true, false) if get_tree().current_scene else null
		if n and String(n.get("_state")) in ["won", "thesis", "ending"]:
			jefes.append(nombres[f])
	_fila(v, "Jefes vencidos", ", ".join(jefes) if jefes.size() > 0 else "Ninguno todavía")
	var vida := get_tree().current_scene.find_child("VidaDelCampus", true, false) if get_tree().current_scene else null
	if vida:
		var lit := 0
		for b in vida.get("bonfires"):
			if is_instance_valid(b) and b.is_lit:
				lit += 1
		var cp = vida.get("checkpoint")
		_fila(v, "Hogueras encendidas", "%d / %d" % [lit, (vida.get("bonfires") as Array).size()])
		_fila(v, "Última hoguera", String(cp.title) if cp and is_instance_valid(cp) else "—")
	var partida := get_node_or_null("/root/Partida")
	if partida and partida.hay_partida():
		var r: Dictionary = partida.resumen()
		_fila(v, "Partida guardada", "%s  ·  %s" % [r.get("hoguera", ""), r.get("fecha", "")], E.TEXTO_TENUE)


func _controles(v: VBoxContainer) -> void:
	v.add_child(E.titulo("CONTROLES", 30))
	var cls: Dictionary = CLASSES.data(String(player.get("class_id"))) if player else CLASSES.data()
	for c in [["WASD", "Moverse"], ["Shift", "Correr"], ["Espacio", "Rodar (esquivar)"], ["Clic izquierdo", "Atacar (repite para el combo)"],
			["Clic derecho", "Habilidad de la clase"], ["Rueda / Tab", "Fijar objetivo"], ["R / F", "Beber café (curar)"],
			["E", "Encender / descansar en hoguera (guarda la partida)"], ["Q", "Cambiar hechizo / IA"], ["G", "Bebida energética (maná)"],
			["0 – 4", "Equipar armadura de resistencia en la hoguera"], ["Esc", "Pausa"]]:
		_fila(v, c[0], c[1])
	v.add_child(E.linea())
	v.add_child(E.etiqueta("Tu clase: %s" % cls["name"], 18, E.NEON, 600))
	var l := E.etiqueta(String(cls["controls"]).replace(" · ", "\n"), 17)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)


func _en_pelea() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	for f in ["BossFight", "LibraryFight", "ComputeFight", "LabFight", "FinalFight"]:
		var n := scene.find_child(f, true, false)
		if n and String(n.get("_state")) in ["intro", "fight", "dialog", "choice"]:
			return true
	return false


func _volver_hoguera() -> void:
	var vida := get_tree().current_scene.find_child("VidaDelCampus", true, false)
	cerrar()
	if vida and vida.has_method("_respawn"):
		vida._respawn()


func _ir_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU)
