extends Node
## Autoload "Partida": guardado de la partida. Solo se guarda al DESCANSAR EN UNA HOGUERA
## (VidaDelCampus llama a guardar()). "Continuar" en el menú principal carga main.tscn y,
## cuando el mundo está listo, aplicar() deja todo como estaba:
##   clase, hoguera donde descansaste (ahí apareces), hogueras encendidas, jefes vencidos
##   (sus peleas ya no empiezan y sus sellos/puertas quedan abiertos), piezas de la llave
##   (y el portón del Aula Magna si están las 4), tazas de café recogidas y cuántas cargas,
##   armaduras de resistencia encontradas y la equipada, y el tiempo jugado.

signal guardada

const RUTA := "user://partida.json"
const MAIN := "res://Scenes/main.tscn"
const CLASSES := preload("res://jugador/player_classes.gd")

## Peleas de jefe: nodo -> id del jefe (el mismo que usa CampusWorld) y pieza de llave.
const PELEAS := {
	"BossFight": "profesor",
	"LibraryFight": "biblioteca",
	"ComputeFight": "computo",
	"LabFight": "laboratorio",
}

## true cuando se entra con "Continuar" (la escena debe restaurar el guardado).
var pendiente := false
## Segundos jugados (se suman mientras hay un jugador en la escena y no está en pausa).
var tiempo := 0.0
var _datos := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	if get_tree().get_first_node_in_group("player") != null:
		tiempo += delta


func hay_partida() -> bool:
	return FileAccess.file_exists(RUTA)


## Resumen para el menú principal: {clase, hoguera, tiempo, fecha, jefes, llaves}.
func resumen() -> Dictionary:
	var d := leer()
	if d.is_empty():
		return {}
	var c: Dictionary = CLASSES.data(String(d.get("clase", "")))
	return {
		"clase": "%s (%s)" % [c["name"], c["role"]],
		"hoguera": String(d.get("hoguera", "")),
		"tiempo": formato_tiempo(float(d.get("tiempo", 0.0))),
		"fecha": String(d.get("fecha", "")),
		"jefes": (d.get("jefes", []) as Array).size(),
		"llaves": (d.get("llaves", []) as Array).size(),
	}


static func formato_tiempo(s: float) -> String:
	var t := int(s)
	return "%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]


func leer() -> Dictionary:
	if not hay_partida():
		return {}
	var f := FileAccess.open(RUTA, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func borrar() -> void:
	if hay_partida():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUTA))


## Nueva partida: el guardado anterior se reemplaza la primera vez que descanses.
func nueva(clase: String) -> void:
	pendiente = false
	tiempo = 0.0
	CLASSES.selected = clase
	get_tree().change_scene_to_file(MAIN)


## Continuar: carga la escena del juego con la clase guardada y luego restaura.
func continuar() -> bool:
	_datos = leer()
	if _datos.is_empty():
		return false
	CLASSES.selected = String(_datos.get("clase", CLASSES.DEFAULT))
	tiempo = float(_datos.get("tiempo", 0.0))
	pendiente = true
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN)
	return true


## Guarda el estado actual. `vida` es VidaDelCampus (world_life.gd).
func guardar(vida: Node) -> void:
	var scene := get_tree().current_scene
	var player = vida.get("player")
	var world = vida.get("world")
	if scene == null or player == null:
		return
	var jefes: Array = []
	for fight_name in PELEAS.keys():
		var f := scene.find_child(fight_name, true, false)
		if f and String(f.get("_state")) == "won":
			jefes.append(PELEAS[fight_name])
	if world and world.get("_defeated") is Dictionary:
		for id in (world.get("_defeated") as Dictionary).keys():
			if not jefes.has(id):
				jefes.append(id)
	var hogueras: Array = []
	for b in vida.get("bonfires"):
		if is_instance_valid(b) and b.is_lit:
			hogueras.append(String(b.title))
	var cp = vida.get("checkpoint")
	var kit = player.get("kit")
	var d := {
		"version": 1,
		"clase": String(player.get("class_id")),
		"hoguera": String(cp.title) if cp and is_instance_valid(cp) else "",
		"hogueras": hogueras,
		"jefes": jefes,
		"llaves": (world.get("key_pieces") as Dictionary).keys() if world and world.get("key_pieces") is Dictionary else [],
		"tazas_max": int(player.get_max_flasks()) if player.has_method("get_max_flasks") else 4,
		"tazas_tomadas": vida.get("cups_taken"),
		"armaduras": vida.get("armors_found"),
		"armadura": String(kit.resist_id) if kit else "",
		"tiempo": tiempo,
		"fecha": Time.get_datetime_string_from_system(false, true),
	}
	var f := FileAccess.open(RUTA, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "  "))
		guardada.emit()


## La llama VidaDelCampus al terminar de armar el mundo. Restaura si se entró con Continuar.
func aplicar(vida: Node) -> void:
	if not pendiente:
		return
	pendiente = false
	var d := _datos if not _datos.is_empty() else leer()
	if d.is_empty():
		return
	var scene := get_tree().current_scene
	var player = vida.get("player")
	var world = vida.get("world")
	# Espera a que las peleas terminen de prepararse
	for i in 120:
		var listo := true
		for fight_name in PELEAS.keys():
			var f := scene.find_child(fight_name, true, false)
			if f and String(f.get("_state")) == "setup":
				listo = false
		if listo:
			break
		await get_tree().physics_frame
	var jefes: Array = d.get("jefes", [])
	var llaves: Array = d.get("llaves", [])
	# Jefes vencidos
	for fight_name in PELEAS.keys():
		var id: String = PELEAS[fight_name]
		if not jefes.has(id):
			continue
		var f := scene.find_child(fight_name, true, false)
		if f and f.has_method("restore_won"):
			f.restore_won()
		if id == "profesor" and world and world.has_method("restore_first_boss"):
			world.restore_first_boss()
		elif world and world.has_method("register_boss_defeated"):
			world.register_boss_defeated(id)
		# Si venciste al jefe pero no recogiste su pieza, vuelve a estar en su arena
		if not llaves.has(id) and vida.has_method("restore_key_drop"):
			vida.restore_key_drop(fight_name)
	# Piezas de la llave
	var n := 0
	for id in llaves:
		if world and world.has_method("add_key_piece"):
			n = world.add_key_piece(String(id))
	var hud = vida.get("hud")
	if hud and hud.has_method("set_keys") and n > 0:
		hud.set_keys(n, 4)
	# Hogueras, tazas y armaduras
	if vida.has_method("restore_state"):
		vida.restore_state(d)
	if player:
		if player.has_method("add_flask_capacity") and player.has_method("get_max_flasks"):
			var extra := int(d.get("tazas_max", 4)) - int(player.get_max_flasks())
			if extra > 0:
				player.add_flask_capacity(extra)
		if player.has_method("rest"):
			player.rest()
		var kit = player.get("kit")
		var arm := String(d.get("armadura", ""))
		if kit and arm != "":
			kit.set_resist_armor(arm)
	if hud and hud.has_method("toast"):
		hud.toast("Partida cargada  ·  %s" % String(d.get("hoguera", "")), 4.0)
