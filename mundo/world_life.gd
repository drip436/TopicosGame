extends Node3D
## VidaDelCampus: todo lo que "vive" en el campus fuera de las peleas de jefe.
##   - Hogueras antes de cada arena de jefe y en las fuentes principales.
##     E = encender / descansar (vida y cafés completos, enemigos reaparecen).
##   - Tazas de café repartidas por el mapa (+1 taza en el inventario cada una).
##   - Enemigos: 4-5 por zona (también dentro de los edificios de conexión).
##     Robots pequeños y medianos (hacha, espada o pistola láser), mechas que
##     merodean las zonas abiertas, androides (mini ADA-7) en el sector del
##     Centro de Cómputo y especímenes mutantes en el del Laboratorio (veneno). Solo existen cerca del jugador (rendimiento).
##   - Lago: meterse al agua contagia la ameba come-cerebros.
##   - Si mueres fuera de una pelea de jefe: R para volver a la última hoguera.
## CampusWorld lo crea al iniciar el juego (opción spawn_world_life); no hace
## falta tocar main.tscn. Los enemigos aparecen al vencer al primer jefe.

const ENEMY := preload("enemy.gd")
const BONFIRE := preload("bonfire.gd")
const CUP := preload("coffee_cup.gd")
const KEY := preload("key_piece.gd")
const PCLASSES := preload("res://jugador/player_classes.gd")
const EQ := preload("res://jugador/equipo.gd")
const CREDITO := preload("credito.gd")
const MERCADER := preload("mercader.gd")
const M := preload("enemy_models.gd")

## Armaduras de resistencia: dónde están (cerca de qué hoguera, por título).
const ARMOR_SPOTS := {
	"aislante": "Hoguera de la Plaza",
	"ignifuga": "Hoguera de la Biblioteca",
	"anclaje": "Hoguera del Centro de Cómputo",
	"antiveneno": "Hoguera de la Fuente de las Ciencias",
}

## Piezas de la llave que suelta cada jefe: nodo de la pelea -> [id, nombre, color].
const KEY_DROPS := {
	"BossFight": ["profesor", "Pieza del Rayo (Catedrático de Hierro)", Color(0.45, 0.75, 1.0)],
	"LibraryFight": ["biblioteca", "Pieza del Pergamino (Bibliófilo Demente)", Color(1.0, 0.55, 0.15)],
	"ComputeFight": ["computo", "Pieza del Circuito (ADA-7)", Color(0.3, 0.95, 1.0)],
	"LabFight": ["laboratorio", "Pieza del Suero (Paciente Cero)", Color(0.45, 1.0, 0.25)],
}
const WORLD := preload("res://scripts/campus_world.gd")
const LFX := preload("res://boss_bibliotecario/library_fx.gd")

@export var enemies_enabled: bool = true
## Los enemigos se crean al acercarte a esta distancia y se quitan más lejos.
@export var spawn_distance: float = 75.0
@export var despawn_distance: float = 105.0
@export var enemies_per_zone: Vector2i = Vector2i(4, 5)
## Acumulación de ameba por segundo dentro del agua (100 = contagio).
@export var amoeba_rate: float = 55.0
@export var layout_seed: int = 2024

## Zonas con enemigos: centro (x, z), radio y nombre. El tipo de enemigos
## depende del sector (mutantes en el del Laboratorio, robots en el resto).
const ENEMY_ZONES := [
	# Sector poniente (Biblioteca)
	[Vector2(-205, 60), 30.0, "Residencias Poniente"],
	[Vector2(-232, 2), 26.0, "Facultad de Ingeniería"],
	[Vector2(-163, 8), 22.0, "Alberca y Tenis"],
	[Vector2(-133, -47), 24.0, "Canchas"],
	[Vector2(-262, -80), 26.0, "Estacionamiento Poniente"],
	[Vector2(-118, -98), 16.0, "Cafetería"],
	[Vector2(-240, -132), 22.0, "Futbolito"],
	[Vector2(-155, -160), 26.0, "Filosofía y Letras"],
	[Vector2(-219, -180), 26.0, "Facultad de Derecho"],
	[Vector2(-80, -150), 32.0, "Estadio Universitario"],
	# Sector oriente (Cómputo): androides
	[Vector2(205, 60), 30.0, "Residencias Oriente"],
	[Vector2(178, -13), 26.0, "Facultad de Ciencias"],
	[Vector2(222, -18), 16.0, "Mercadito"],
	[Vector2(125, -8), 18.0, "Torre de Agua"],
	[Vector2(128, -62), 20.0, "Frontones"],
	[Vector2(120, -92), 24.0, "Facultad de Medicina"],
	[Vector2(130, -134), 20.0, "Skatepark"],
	[Vector2(80, -150), 28.0, "Estacionamiento Norte"],
	[Vector2(172, -180), 26.0, "Facultad de Química"],
	[Vector2(276, -72), 24.0, "Estacionamiento Oriente"],
	[Vector2(66, -198), 14.0, "Foro al Aire Libre"],
	# Sector del Laboratorio (mutantes)
	[Vector2(111, -251), 26.0, "Facultad de Arquitectura"],
	[Vector2(205, -236), 26.0, "Gimnasio y Rectoría"],
	[Vector2(240, -324), 24.0, "Puesto de Rescate"],
	[Vector2(266, -392), 22.0, "Voleibol de Playa"],
	[Vector2(148, -380), 24.0, "Estacionamiento Torre"],
	[Vector2(78, -352), 20.0, "Asaderos"],
	[Vector2(215, -300), 18.0, "Patio del Laboratorio"],
	# Sector norte (Aula Magna)
	[Vector2(0, -205), 24.0, "Explanada de los Fundadores"],
	[Vector2(-74, -350), 22.0, "Jardín de las Esculturas"],
	[Vector2(-62, -385), 16.0, "Memorial"],
	[Vector2(-148, -404), 20.0, "Área de Descanso"],
	[Vector2(-222, -238), 24.0, "Área de Picnic"],
	[Vector2(-130, -280), 26.0, "Bosque Norte"],
]

## Mechas vivos que merodean zonas abiertas: centro, radio de merodeo, nombre.
## (No hay Facultad de Psicología en el campus: el de humanidades merodea
## Filosofía y Letras.)
const MECH_ZONES := [
	[Vector2(-80, -150), 26.0, "Estadio Universitario"],
	[Vector2(-212, -198), 18.0, "Facultad de Derecho"],
	[Vector2(-150, -185), 18.0, "Filosofía y Letras"],
	[Vector2(80, -150), 22.0, "Estacionamiento Norte"],
	[Vector2(0, -205), 20.0, "Explanada de los Fundadores"],
]

## Tazas de café: punto aproximado (se busca un lugar libre cerca).
const CUP_SPOTS := [
	Vector2(-160, 23), Vector2(-133, -47), Vector2(-219, -180), Vector2(-80, -150), Vector2(-262, -80),
	Vector2(178, -13), Vector2(125, -5), Vector2(80, -150), Vector2(172, -180),
	Vector2(111, -251), Vector2(240, -324), Vector2(148, -380),
	Vector2(0, -200), Vector2(-74, -350), Vector2(-148, -406),
]

var world: Node
var player: Node3D
var hud: CanvasLayer
var bonfires: Array = []
var checkpoint: Node
var _records: Array = []
var _cups: Array = []
var _lakes: Array = []
var _rng := RandomNumberGenerator.new()
var _space: PhysicsDirectSpaceState3D
var _ready_done := false
var _tick := 0.0
var _prompt := ""
var _dead := false
var _respawn_ok := false
var _in_water := false
var _water_fx_t := 0.0
var _amoeba_warned := false
var _excl_rects: Array = []
var _pieces: Array = []
## Índices (en _cups) de las tazas recogidas: se guardan con la partida.
var cups_taken: Array = []
var _armor_nodes: Array = []
var armors_found: Array = []
var _menu_open := false
var _menu_bonfire: Node3D
var _enemy_root: Node3D


func _ready() -> void:
	_setup.call_deferred()


func _setup() -> void:
	for i in 3:
		await get_tree().physics_frame
	_rng.seed = layout_seed
	var scene := get_tree().current_scene
	if world == null and scene:
		world = scene.find_child("CampusWorld", true, false)
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0:
		player = ps[0]
	var bf := scene.find_child("BossFight", true, false) if scene else null
	if bf and bf.get("hud") is CanvasLayer:
		hud = bf.get("hud")
	if player == null:
		push_warning("VidaDelCampus: no hay jugador en el grupo 'player'.")
		return
	if player.has_signal("died"):
		player.died.connect(_on_player_died)
	if player.has_signal("interact_pressed"):
		player.interact_pressed.connect(_on_interact)
	_space = get_world_3d().direct_space_state
	_enemy_root = Node3D.new()
	_enemy_root.name = "Enemigos"
	add_child(_enemy_root)
	if world and world.has_method("get_lakes"):
		_lakes = world.get_lakes()
	for a in [[WORLD.LIB, Vector2(34, 28)], [WORLD.COMP, Vector2(32, 28)], [WORLD.LAB, Vector2(36, 34)], [WORLD.FINAL, Vector2(42, 52)], [Vector3.ZERO, Vector2(42, 42)]]:
		var c: Vector3 = a[0]
		var h: Vector2 = a[1]
		_excl_rects.append(Rect2(Vector2(c.x, c.z) - h, h * 2.0))
	_make_bonfires()
	_make_cups()
	_connect_key_drops()
	_make_armors()
	_make_merchant()
	if enemies_enabled:
		_make_enemy_records()
		if shop_pos != Vector3.INF:
			_records = _records.filter(func(r): return (r["pos"] as Vector3).distance_to(shop_pos) > SHOP_SAFE)
	_ready_done = true
	print("VidaDelCampus: %d hogueras, %d tazas, %d enemigos" % [bonfires.size(), _cups.size(), _records.size()])
	# Partida guardada (Continuar en el menú principal)
	var partida := get_node_or_null("/root/Partida")
	if partida:
		partida.aplicar(self)


## Tiendita del mercader (mundo/mercader.gd) en el patio de la Facultad de Ingeniería:
## puesto con toldo, mostrador, armas en exhibición, cajas y un letrero. Es zona segura
## (no aparecen enemigos a menos de SHOP_SAFE metros).
const SHOP_SPOT := Vector3(-225.0, 0.0, 7.0)
const SHOP_SAFE := 16.0
var shop_pos := Vector3.INF


func _make_merchant() -> void:
	var c := SHOP_SPOT
	if world and world.has_method("get_prefabs_of_kind"):
		for f in world.get_prefabs_of_kind("FACULTAD"):
			if String(f.get("title")).to_upper().contains("INGENIER"):
				var fn := f as Node3D
				c = fn.global_position + fn.global_basis * Vector3(7.0, 0, 5.0)
	var p := _free_near(c, 6.0, 2.2)
	if p == Vector3.INF:
		p = c
	p.y = 0.0
	shop_pos = p
	var shop := Node3D.new()
	shop.name = "Tiendita"
	shop.position = p
	add_child(shop)
	# El puesto mira hacia el centro del patio
	var to := (c - Vector3(7.0, 0, 5.0)) - p
	to.y = 0.0
	if to.length() < 0.5:
		to = Vector3(0, 0, 1)
	shop.rotation.y = atan2(to.x, to.z)
	_build_stall(shop)
	var m := MERCADER.new()
	m.name = "Mercader"
	m.player = player
	m.hud = hud
	m.position = Vector3(0, 0, -0.9)
	m.rotation.y = PI
	shop.add_child(m)


func _build_stall(shop: Node3D) -> void:
	var wood := M.mat(Color(0.32, 0.2, 0.11), 0.7)
	var metal := M.mat(Color(0.25, 0.26, 0.28), 0.4, 0.7)
	var cloth := M.mat(Color(0.55, 0.12, 0.1), 0.85)
	var cloth2 := M.mat(Color(0.85, 0.75, 0.55), 0.85)
	var d := {"meshes": [], "J": {}, "eyes": []}
	# Mostrador (frente hacia +z local)
	M.box(d, shop, Vector3(2.6, 0.95, 0.6), Vector3(0, 0.475, 0.2), wood)
	M.box(d, shop, Vector3(2.7, 0.06, 0.7), Vector3(0, 0.98, 0.2), metal)
	# Postes y toldo a rayas
	for sx: float in [-1.4, 1.4]:
		for sz: float in [-1.6, 0.5]:
			M.box(d, shop, Vector3(0.08, 2.5, 0.08), Vector3(sx, 1.25, sz), metal)
	for k in 7:
		var x := -1.35 + k * 0.45
		M.box(d, shop, Vector3(0.45, 0.04, 2.5), Vector3(x, 2.55, -0.55), cloth if k % 2 == 0 else cloth2, Vector3(-8, 0, 0))
		M.box(d, shop, Vector3(0.45, 0.3, 0.03), Vector3(x, 2.4, 0.72), cloth if k % 2 == 0 else cloth2)
	# Repisa trasera con armas en exhibición
	M.box(d, shop, Vector3(2.6, 0.06, 0.4), Vector3(0, 1.3, -1.5), wood)
	M.box(d, shop, Vector3(2.6, 1.6, 0.06), Vector3(0, 1.1, -1.72), wood)
	var armas := ["katana_plasma", "espada_cortafuegos", "alabarda", "mandoble", "hacha_servidor"]
	for i in armas.size():
		var path := "res://modelos/armas_jugador/%s.glb" % armas[i]
		if not ResourceLoader.exists(path):
			continue
		var w: Node3D = (load(path) as PackedScene).instantiate()
		shop.add_child(w)
		var x := -1.0 + i * 0.5
		if armas[i] == "alabarda":
			# Va a lo largo de −z: se para vertical
			w.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90)), Vector3(x, 0.6, -1.62))
		else:
			w.transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(8 - i * 4)), Vector3(x, 0.35, -1.6))
		for mi in w.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cajas, un frasco de pociones y bolsas de créditos sobre el mostrador
	for k in 3:
		M.box(d, shop, Vector3(0.5, 0.45, 0.45), Vector3(1.9 + (k % 2) * 0.1, 0.225 + (k / 2) * 0.45, -0.6 + k * 0.5), wood, Vector3(0, k * 17, 0))
	M.cyl(d, shop, 0.08, 0.22, Vector3(-0.8, 1.12, 0.25), LFX.emissive(Color(0.35, 0.8, 1.0), 1.5))
	M.cyl(d, shop, 0.07, 0.18, Vector3(-0.55, 1.1, 0.3), LFX.emissive(Color(1.0, 0.4, 0.8), 1.5))
	M.sph(d, shop, Vector3(0.16, 0.14, 0.16), Vector3(0.7, 1.08, 0.25), M.mat(Color(0.6, 0.45, 0.2), 0.8))
	for k in 6:
		M.box(d, shop, Vector3(0.05, 0.08, 0.05), Vector3(0.45 + k * 0.05, 1.05, 0.35), LFX.emissive(Color(1.0, 0.8, 0.3), 2.0), Vector3(45, 45, 0))
	# Letrero y luz cálida
	M.box(d, shop, Vector3(2.2, 0.5, 0.06), Vector3(0, 3.0, 0.74), wood)
	var l3 := Label3D.new()
	l3.text = "TIENDITA DEL INGE"
	l3.font_size = 64
	l3.outline_size = 12
	l3.modulate = Color(1.0, 0.86, 0.45)
	l3.position = Vector3(0, 3.02, 0.78)
	shop.add_child(l3)
	var l4 := Label3D.new()
	l4.text = "armas · armaduras · hechizos   ◆ solo créditos"
	l4.font_size = 26
	l4.outline_size = 8
	l4.modulate = Color(0.85, 0.9, 1.0)
	l4.position = Vector3(0, 2.84, 0.78)
	shop.add_child(l4)
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.75, 0.45)
	luz.light_energy = 2.2
	luz.omni_range = 7.0
	luz.position = Vector3(0, 2.2, -0.2)
	shop.add_child(luz)
	# Colisión del mostrador y de la repisa
	var body := StaticBody3D.new()
	for box in [[Vector3(2.7, 1.0, 0.7), Vector3(0, 0.5, 0.2)], [Vector3(2.6, 1.9, 0.5), Vector3(0, 0.95, -1.6)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box[0]
		cs.shape = bs
		cs.position = box[1]
		body.add_child(cs)
	shop.add_child(body)


# ======================================================================
#  Colocación
# ======================================================================

func _sector(p: Vector3) -> String:
	if p.x < -42.0 and p.z > -212.0:
		return "poniente"
	if p.x > 45.0 and p.z > -213.8:
		return "oriente"
	if p.x > 54.0 and p.z <= -213.8:
		return "noreste"
	if absf(p.x) < 45.0 and p.z > -60.0:
		return "plaza"
	return "norte"


func _in_lake(p: Vector3, margin: float) -> bool:
	for lk in _lakes:
		var n: Node3D = lk["node"]
		if not is_instance_valid(n):
			continue
		var lp := n.global_transform.affine_inverse() * p
		var r: Vector2 = lk["radii"] + Vector2(margin, margin)
		if pow(lp.x / r.x, 2.0) + pow(lp.z / r.y, 2.0) < 1.0:
			return true
	return false


## ¿Cabe algo de radio `clearance` parado en el suelo en (x, z)?
## Devuelve la posición en el suelo o Vector3.INF.
func _spot(p: Vector3, clearance: float, indoor: bool) -> Vector3:
	var top := 2.4 if indoor else 45.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, top, p.z), Vector3(p.x, -3.0, p.z))
	var hit := _space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.INF
	var g: Vector3 = hit["position"]
	if g.y < -0.8 or g.y > 0.9:
		return Vector3.INF
	var h := maxf(1.9, clearance * 2.0 + 0.2)
	var cap := CapsuleShape3D.new()
	cap.radius = clearance
	cap.height = h
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, g + Vector3(0, h * 0.5 + 0.15, 0))
	if player is CollisionObject3D:
		sq.exclude = [(player as CollisionObject3D).get_rid()]
	if not _space.intersect_shape(sq, 1).is_empty():
		return Vector3.INF
	return g


func _excluded(p: Vector3) -> bool:
	var p2 := Vector2(p.x, p.z)
	for r in _excl_rects:
		if (r as Rect2).has_point(p2):
			return true
	return false


## Busca un lugar libre en anillos alrededor de `p`.
func _free_near(p: Vector3, max_r: float, clearance: float, indoor := false) -> Vector3:
	var ring := 0
	while ring * 1.5 <= max_r:
		var r := ring * 1.5
		var n := maxi(1, int(TAU * r / 1.5))
		for i in n:
			var a := TAU * i / n + ring * 0.7
			var c := p + Vector3(cos(a) * r, 0, sin(a) * r)
			if _in_lake(c, 3.0):
				continue
			var g := _spot(c, clearance, indoor)
			if g != Vector3.INF:
				return g
		ring += 1
	return Vector3.INF


func _make_bonfires() -> void:
	var spots: Array = [
		[Vector3(5, 0, 20), "Hoguera de la Plaza"],
		[WORLD.LIB + Vector3(6, 0, 31), "Hoguera de la Biblioteca"],
		[WORLD.COMP + Vector3(6, 0, 30), "Hoguera del Centro de Cómputo"],
		[WORLD.LAB + Vector3(6, 0, 34), "Hoguera del Laboratorio"],
		[WORLD.FINAL + Vector3(7, 0, 55), "Hoguera del Aula Magna"],
	]
	if world and world.has_method("get_prefabs_of_kind"):
		for f in world.get_prefabs_of_kind("FUENTE"):
			var fn := f as Node3D
			var r: float = f.get("plaza_radius") if f.get("plaza_radius") else 10.0
			spots.append([fn.global_position + fn.global_basis * Vector3(0, 0, r * 0.62), "Hoguera de la " + String(f.get("title")) if String(f.get("title")) != "" else "Hoguera de la Fuente"])
	for s in spots:
		var p: Vector3 = s[0]
		var g := _free_near(p, 8.0, 1.3)
		if g == Vector3.INF:
			g = p
		var b := BONFIRE.new()
		b.title = s[1]
		b.name = String(s[1]).replace(" ", "")
		b.position = g
		add_child(b)
		bonfires.append(b)
	# Manuales (Hoguera.tscn arrastradas a la escena)
	for n in get_tree().get_nodes_in_group("hoguera"):
		if not bonfires.has(n):
			bonfires.append(n)
	# La de la plaza ya está encendida: es el primer punto de reaparición
	if bonfires.size() > 0:
		checkpoint = bonfires[0]
		bonfires[0].light(true)


func _make_cups() -> void:
	var spots: Array = []
	for c in CUP_SPOTS:
		spots.append([Vector3(c.x, 0, c.y), false])
	# Una en cada edificio de conexión (a media altura del pasillo)
	if world and world.has_method("get_connector_halls"):
		for h in world.get_connector_halls():
			var o: Vector3 = h["origin"]
			var b: Basis = h["basis"]
			var L: float = h["length"]
			spots.append([o + b * Vector3(L * 0.18, 0, 2.5), true])
	for s in spots:
		var g := _free_near(s[0], 14.0, 0.5, s[1])
		if g == Vector3.INF:
			continue
		var cup := CUP.new()
		cup.position = g
		add_child(cup)
		_cups.append(cup)
	# Manuales (TazaDeCafe.tscn arrastradas a la escena)
	for n in get_tree().get_nodes_in_group("taza_cafe"):
		if not _cups.has(n):
			_cups.append(n)


func _pool(sector: String) -> String:
	match sector:
		"noreste":
			return "mutantes"
		"oriente":
			return "androides"
	return "robots"


func _pick_type(pool: String, big_used: bool) -> String:
	var r := _rng.randf()
	if pool == "mutantes":
		if r < 0.55:
			return "mutante_peq"
		if r < 0.88 or big_used:
			return "mutante_med"
		return "mutante_grande"
	if pool == "androides":
		if r < 0.45:
			return "androide_espadas"
		if r < 0.75:
			return "androide_cables"
		return "androide_script"
	if r < 0.7:
		return "robot"
	return ["robot_hacha", "robot_espada", "robot_laser"][_rng.randi() % 3]


func _clearance(t: String) -> float:
	match t:
		"mecha":
			return 2.2
		"mutante_grande":
			return 1.2
		"robot":
			return 0.5
		"mutante_peq":
			return 0.45
	return 0.7


func _far_from_bonfires(p: Vector3, d: float) -> bool:
	for b in bonfires:
		if (b as Node3D).global_position.distance_to(p) < d:
			return false
	return true


func _add_record(t: String, p: Vector3, wander: float, zone: String) -> void:
	_records.append({"type": t, "pos": p, "yaw": _rng.randf() * TAU, "wander": wander, "alive": true, "node": null, "zone": zone})


func _make_enemy_records() -> void:
	for z in ENEMY_ZONES:
		var c2: Vector2 = z[0]
		var c := Vector3(c2.x, 0, c2.y)
		var sec := _sector(c)
		if sec == "plaza":
			continue
		var pool := _pool(sec)
		var count := _rng.randi_range(enemies_per_zone.x, enemies_per_zone.y)
		var placed: Array = []
		var big := false
		for i in count:
			var t := _pick_type(pool, big)
			if t == "mutante_grande":
				big = true
			var p := _sample(c, float(z[1]), _clearance(t), sec, placed)
			if p != Vector3.INF:
				placed.append(p)
				_add_record(t, p, minf(8.0, float(z[1]) * 0.4), z[2])
	for z in MECH_ZONES:
		var c2: Vector2 = z[0]
		var c := Vector3(c2.x, 0, c2.y)
		var p := _sample(c, float(z[1]), 2.2, _sector(c), [])
		if p != Vector3.INF:
			_add_record("mecha", p, float(z[1]), z[2])
	# Dentro de los edificios de conexión
	if world and world.has_method("get_connector_halls"):
		for h in world.get_connector_halls():
			var o: Vector3 = h["origin"]
			var b: Basis = h["basis"]
			var L: float = h["length"]
			var sec := _sector(o)
			var pool := _pool(sec if sec != "plaza" and sec != "norte" else "poniente")
			if h["id"] == "posgrado" or h["id"] == "aulas_norte":
				pool = "mutantes"
			var n := 5 if L > 100.0 else 4
			for i in n:
				var t := _pick_type(pool, true)
				if pool != "androides" and t != "robot" and t != "mutante_peq" and _rng.randf() < 0.5:
					t = "robot" if pool == "robots" else "mutante_peq"
				for tries in 12:
					var x := lerpf(-L * 0.5 + 6.0, L * 0.5 - 6.0, (i + 0.5) / n) + _rng.randf_range(-3.0, 3.0)
					var zl := 2.5 if _rng.randf() < 0.65 else -1.8
					var g := _spot(o + b * Vector3(x, 0, zl), _clearance(t), true)
					if g != Vector3.INF:
						_add_record(t, g, 2.5, String(h["title"]))
						break


func _sample(c: Vector3, radius: float, clearance: float, sec: String, placed: Array) -> Vector3:
	for tries in 40:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * radius
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r)
		if _sector(p) != sec or _excluded(p) or _in_lake(p, 4.0) or not _far_from_bonfires(p, 16.0):
			continue
		var ok := true
		for q in placed:
			if (q as Vector3).distance_to(p) < 3.5:
				ok = false
				break
		if not ok:
			continue
		var g := _spot(p, clearance, false)
		if g != Vector3.INF:
			return g
	return Vector3.INF


## Armaduras de resistencia en maniquíes junto a algunas hogueras.
func _make_armors() -> void:
	for id in ARMOR_SPOTS.keys():
		var near: Node3D = null
		for b in bonfires:
			if is_instance_valid(b) and String(b.title) == ARMOR_SPOTS[id]:
				near = b
		if near == null:
			continue
		var g := Vector3.INF
		for k in 8:
			var a := TAU * k / 8.0 + 0.6
			g = _free_near(near.global_position + Vector3(cos(a), 0, sin(a)) * 4.0, 3.0, 0.6)
			if g != Vector3.INF:
				break
		if g == Vector3.INF:
			continue
		var info: Dictionary = EQ.ARMORS[id]
		var n := Node3D.new()
		n.name = "Armadura_" + id
		n.set_meta("armor_id", id)
		n.position = g
		add_child(n)
		var d := {"meshes": [], "J": {}, "eyes": []}
		var wood := M.mat(Color(0.3, 0.2, 0.12), 0.8)
		var col: Color = info["color"]
		var plate := M.mat(col.darkened(0.25), 0.35, 0.7, col, 0.5)
		M.cyl(d, n, 0.04, 1.3, Vector3(0, 0.65, 0), wood)
		M.cyl(d, n, 0.3, 0.05, Vector3(0, 0.03, 0), wood)
		M.box(d, n, Vector3(0.5, 0.5, 0.32), Vector3(0, 1.25, 0), plate)
		for sx: float in [-1.0, 1.0]:
			M.sph(d, n, Vector3(0.24, 0.16, 0.26), Vector3(sx * 0.3, 1.47, 0), plate)
		M.sph(d, n, Vector3(0.28, 0.32, 0.3), Vector3(0, 1.72, 0), plate)
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 1.2
		l.omni_range = 4.0
		l.position = Vector3(0, 1.5, 0)
		n.add_child(l)
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.35
		cm.height = 5.0
		cm.material = LFX.emissive(col, 0.7, 0.1)
		beam.mesh = cm
		beam.position = Vector3(0, 2.5, 0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(beam)
		_armor_nodes.append(n)


func _update_armors() -> void:
	for n in _armor_nodes:
		if not is_instance_valid(n):
			continue
		var d := Vector2(n.global_position.x - player.global_position.x, n.global_position.z - player.global_position.z).length()
		if d < 1.8:
			var id: String = n.get_meta("armor_id")
			armors_found.append(id)
			var partida := get_node_or_null("/root/Partida")
			if partida and not partida.armaduras.has(id):
				partida.armaduras.append(id)
				partida.inventario_cambiado.emit()
			var info: Dictionary = EQ.ARMORS[id]
			LFX.puff(self, n.global_position + Vector3(0, 1.3, 0), Color(info["color"].r * 2.5, info["color"].g * 2.5, info["color"].b * 2.5, 1), 40, 0.2, 4.0, -2.0)
			n.queue_free()
			if hud:
				hud.show_banner(String(info["name"]).to_upper(), info["color"], "%s\nEquípala en el menú de pausa (Esc → Equipo)." % info["desc"], 3.5)
	if _menu_open and (_menu_bonfire == null or not is_instance_valid(_menu_bonfire) or _menu_bonfire.global_position.distance_to(player.global_position) > 3.5 or player.is_dead):
		_close_menu()


func _open_menu(_b: Node3D) -> void:
	# Las armaduras ahora se cambian en el menú de pausa (Esc → Equipo)
	pass


func _refresh_menu() -> void:
	var cur: String = player.kit.resist_id if "kit" in player and player.kit else ""
	var lines := ["ARMADURA DE RESISTENCIA  (teclas)", ""]
	lines.append("[0]  Ninguna" + ("   ◀" if cur == "" else ""))
	var i := 1
	for id in PCLASSES.RESIST_ARMORS.keys():
		var info: Dictionary = PCLASSES.RESIST_ARMORS[id]
		if armors_found.has(id):
			lines.append("[%d]  %s%s" % [i, info["name"], "   ◀" if cur == id else ""])
		else:
			lines.append("[%d]  ???" % i)
		i += 1
	lines.append("")
	lines.append("Aléjate para cerrar")
	hud.show_menu("\n".join(lines))


func _close_menu() -> void:
	_menu_open = false
	if hud and hud.has_method("show_menu"):
		hud.show_menu("")


func _equip_from_key(n: int) -> void:
	if not ("kit" in player) or player.kit == null:
		return
	if n == 0:
		player.kit.set_resist_armor("")
	else:
		var ids := PCLASSES.RESIST_ARMORS.keys()
		if n - 1 < ids.size() and armors_found.has(ids[n - 1]):
			player.kit.set_resist_armor(ids[n - 1])
			LFX.puff(self, player.global_position + Vector3(0, 1.2, 0), Color(2.0, 2.0, 2.0, 1), 20, 0.15, 2.0, 0.0)
	_refresh_menu()


# ======================================================================
#  Partida guardada
# ======================================================================

## Deja hogueras, tazas y armaduras como en el guardado y pone al jugador en su hoguera.
func restore_state(d: Dictionary) -> void:
	var lit: Array = d.get("hogueras", [])
	var spot := String(d.get("hoguera", ""))
	for b in bonfires:
		if not is_instance_valid(b):
			continue
		if lit.has(String(b.title)):
			b.light(true)
		if String(b.title) == spot:
			checkpoint = b
	for i in d.get("tazas_tomadas", []):
		var k := int(i)
		if k >= 0 and k < _cups.size() and is_instance_valid(_cups[k]):
			cups_taken.append(k)
			_cups[k].taken = true
			_cups[k].queue_free()
	for id in d.get("armaduras", []):
		if not armors_found.has(id):
			armors_found.append(id)
	for n in _armor_nodes:
		if is_instance_valid(n) and armors_found.has(String(n.get_meta("armor_id"))):
			n.queue_free()
	if checkpoint and is_instance_valid(checkpoint) and player:
		var pos: Vector3 = checkpoint.respawn_point()
		var to: Vector3 = checkpoint.global_position - pos
		if player.has_method("revive"):
			player.revive(pos, atan2(-to.x, -to.z))
		else:
			player.global_position = pos


## Jefe vencido cuya pieza no se recogió antes de guardar: la pieza espera en su arena.
func restore_key_drop(fight_name: String) -> void:
	if not KEY_DROPS.has(fight_name):
		return
	var f := get_tree().current_scene.find_child(fight_name, true, false)
	var pos := Vector3.ZERO
	if f:
		var c = f.get("_center")
		if c is Vector3 and c != Vector3.ZERO:
			pos = c
		elif f.get("arena_center") is Vector3:
			pos = f.get("arena_center")
	var info: Array = KEY_DROPS[fight_name]
	var k := KEY.new()
	k.piece_id = info[0]
	k.title = info[1]
	k.gem_color = info[2]
	k.position = pos + Vector3(0, 0.05, 2.0)
	add_child(k)
	_pieces.append(k)


## Cada jefe suelta una pieza de la llave donde cae.
func _connect_key_drops() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for fight_name in KEY_DROPS.keys():
		var f := scene.find_child(fight_name, true, false)
		if f and f.has_signal("boss_defeated"):
			f.connect("boss_defeated", _drop_key.bind(f, fight_name))


## Créditos que suelta un enemigo al morir (jugador/equipo.gd DROPS).
func _drop_credits(e: Node3D) -> void:
	if not is_instance_valid(e) or player == null:
		return
	var r: Array = EQ.DROPS.get(String(e.get("type")), [10, 15])
	CREDITO.soltar(self, e.global_position + Vector3(0, 1.0, 0), _rng.randi_range(int(r[0]), int(r[1])), player)


func _drop_key(fight: Node, fight_name: String) -> void:
	var info: Array = KEY_DROPS[fight_name]
	# Botín de créditos del jefe
	var bb = fight.get("boss")
	var bp: Vector3 = (bb as Node3D).global_position if bb != null and is_instance_valid(bb) else player.global_position
	CREDITO.soltar(self, bp + Vector3(0, 1.5, 0), int(EQ.BOSS_CREDITS.get(info[0], 1000)), player)
	var pos := Vector3.INF
	var b = fight.get("boss")
	if b != null and is_instance_valid(b):
		pos = (b as Node3D).global_position
		# El cadáver ya no bloquea al jugador (sigue apoyado en el suelo)
		if b is CollisionObject3D:
			(b as CollisionObject3D).collision_layer = 0
		# La pieza cae del lado del jugador, fuera del cuerpo del jefe
		var to := player.global_position - pos
		to.y = 0.0
		var r: float = 2.5
		var cs := (b as Node).get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs and cs.shape is CapsuleShape3D:
			r = (cs.shape as CapsuleShape3D).radius + 1.8
		pos += (to.normalized() if to.length() > 0.1 else Vector3(0, 0, 1)) * r
	if pos == Vector3.INF:
		pos = player.global_position + Vector3(0, 0, -3)
	# Al nivel del suelo
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 3, 0), pos + Vector3(0, -6, 0))
	var excl: Array[RID] = []
	if b is CollisionObject3D:
		excl.append((b as CollisionObject3D).get_rid())
	if player is CollisionObject3D:
		excl.append((player as CollisionObject3D).get_rid())
	q.exclude = excl
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		pos = hit["position"]
	var k := KEY.new()
	k.piece_id = info[0]
	k.title = info[1]
	k.gem_color = info[2]
	k.position = pos
	add_child(k)
	_pieces.append(k)
	if hud and hud.has_method("toast"):
		hud.toast("El jefe soltó algo brillante…", 4.0)


func _update_key_pieces() -> void:
	for k in _pieces:
		if not is_instance_valid(k) or k.taken:
			continue
		var d := Vector2(k.global_position.x - player.global_position.x, k.global_position.z - player.global_position.z).length()
		if d < 2.2 and absf(k.global_position.y - player.global_position.y) < 2.5:
			k.take()
			var n := 1
			var total := 4
			if world and world.has_method("add_key_piece"):
				n = world.add_key_piece(k.piece_id)
				total = int(world.get("KEY_PIECES_NEEDED")) if world.get("KEY_PIECES_NEEDED") else 4
			if hud:
				if hud.has_method("set_keys"):
					hud.set_keys(n, total)
				hud.show_banner("PIEZA DE LA LLAVE", Color(0.95, 0.78, 0.38), "%s  ·  %d / %d" % [k.title, n, total], 3.0)
				if n >= total and hud.has_method("toast"):
					hud.toast("La llave está completa: el portón del AULA MAGNA se abrió", 7.0)


# ======================================================================
#  Juego
# ======================================================================

func _active() -> bool:
	return world == null or bool(world.get("_explore"))


func _physics_process(delta: float) -> void:
	if not _ready_done or player == null or not is_instance_valid(player):
		return
	_update_lake(delta)
	_update_pickups()
	_update_key_pieces()
	_update_armors()
	_update_prompt()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.4
	if not _active() or not enemies_enabled:
		return
	var pp := player.global_position
	for rec in _records:
		var node = rec["node"]
		if node != null and not is_instance_valid(node):
			rec["node"] = null
			node = null
		if not rec["alive"]:
			continue
		var d := pp.distance_to(rec["pos"])
		if node == null and d < spawn_distance:
			_spawn(rec)
		elif node != null and d > despawn_distance and (node as Node3D).global_position.distance_to(pp) > despawn_distance:
			node.queue_free()
			rec["node"] = null


func _spawn(rec: Dictionary) -> void:
	var e := ENEMY.new()
	e.type = rec["type"]
	e.wander_radius = rec["wander"]
	e.target = player
	e.fx_parent = self
	e.place(rec["pos"] + Vector3(0, 0.05, 0), rec["yaw"])
	e.died.connect(func(_n):
		rec["alive"] = false
		_drop_credits(e))
	_enemy_root.add_child(e)
	rec["node"] = e


## Todos los enemigos vuelven a su lugar (descansar o reaparecer).
func respawn_enemies() -> void:
	for rec in _records:
		var node = rec["node"]
		if node != null and is_instance_valid(node):
			node.queue_free()
		rec["node"] = null
		rec["alive"] = true
	_tick = 0.0


func _nearest_bonfire(max_d: float) -> Node:
	var best: Node = null
	var bd := max_d
	for b in bonfires:
		if not is_instance_valid(b):
			continue
		var d := (b as Node3D).global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = b
	return best


func _update_prompt() -> void:
	var text := ""
	if not _dead and not player.is_dead:
		var b = _nearest_bonfire(2.8)
		if b:
			text = ("E  Descansar  ·  " if b.is_lit else "E  Encender  ·  ") + String(b.title)
	if text != _prompt:
		_prompt = text
		if hud and hud.has_method("show_prompt"):
			hud.show_prompt(text)


func _on_interact() -> void:
	if _dead:
		return
	var b = _nearest_bonfire(2.8)
	if b == null:
		return
	var first: bool = not b.is_lit
	b.light()
	checkpoint = b
	if player.has_method("rest"):
		player.rest()
	_open_menu(b)
	respawn_enemies()
	if hud and hud.has_method("toast"):
		if first:
			hud.toast("HOGUERA ENCENDIDA  —  " + String(b.title), 4.0)
		else:
			hud.toast("Descansaste. Los enemigos han vuelto.", 3.5)
	if hud and hud.has_method("show_banner") and first:
		hud.show_banner("HOGUERA ENCENDIDA", Color(0.95, 0.65, 0.3), "", 2.0)
	# Solo se guarda la partida al descansar en una hoguera
	var partida := get_node_or_null("/root/Partida")
	if partida:
		partida.guardar(self)
		if hud and hud.has_method("toast"):
			get_tree().create_timer(1.2).timeout.connect(func(): hud.toast("Partida guardada", 2.5))


func _update_pickups() -> void:
	if player.is_dead:
		return
	for cup in _cups:
		if not is_instance_valid(cup) or cup.taken:
			continue
		var d := Vector2(cup.global_position.x - player.global_position.x, cup.global_position.z - player.global_position.z).length()
		if d < 1.3 and absf(cup.global_position.y - player.global_position.y) < 2.0:
			cups_taken.append(_cups.find(cup))
			cup.take()
			if player.has_method("add_flask_capacity"):
				player.add_flask_capacity(1)
			if hud and hud.has_method("toast"):
				var mx: int = player.get_max_flasks() if player.has_method("get_max_flasks") else 0
				hud.toast("Encontraste una taza de café  ·  ahora llevas %d" % mx, 3.5)


func _update_lake(delta: float) -> void:
	var was := _in_water
	_in_water = false
	if player.is_dead or _lakes.is_empty():
		return
	var p := player.global_position
	for lk in _lakes:
		var n: Node3D = lk["node"]
		if not is_instance_valid(n):
			continue
		var lp := n.global_transform.affine_inverse() * p
		var A: float = lk["radii"].x
		var B: float = lk["radii"].y
		if pow(lp.x / A, 2.0) + pow(lp.z / B, 2.0) >= 0.985:
			continue
		# Isla, puente y muelle (secos)
		var isl := Vector3(-A * 0.36, 0, -B * 0.39)
		var ir := minf(A, B) * 0.19
		if Vector2(lp.x - isl.x, lp.z - isl.z).length() < ir + 0.6:
			continue
		if absf(lp.x - isl.x) < 2.0 and lp.z < isl.z:
			continue
		var plen := minf(24.0, A * 0.45)
		if lp.x > A + 0.6 - plen - 0.6 and absf(lp.z) < 2.0:
			continue
		if lp.y > 0.05:
			continue
		_in_water = true
		break
	if not _in_water:
		return
	if player.has_method("add_buildup"):
		if player.has_method("has_status") and player.has_status("ameba"):
			player.apply_status("ameba", 10.0)
		else:
			player.add_buildup("ameba", amoeba_rate * delta)
	if not was and hud and hud.has_method("toast"):
		hud.toast("PROHIBIDO NADAR  ·  El agua está infestada de amebas come-cerebros" if not _amoeba_warned else "¡Sal del agua!", 4.0)
		_amoeba_warned = true
	_water_fx_t -= delta
	if _water_fx_t <= 0.0:
		_water_fx_t = 0.25
		LFX.puff(self, p + Vector3(0, 0.35, 0), Color(0.7, 0.85, 0.9, 0.6), 6, 0.2, 1.5, -4.0)


# ======================================================================
#  Muerte y reaparición
# ======================================================================

## Mientras hay una pelea de jefe, ella se encarga de la muerte del jugador.
func _boss_fight_handles_death() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var bf := scene.find_child("BossFight", true, false)
	if bf and String(bf.get("_state")) != "won":
		return true
	for fight_name in ["LibraryFight", "ComputeFight", "LabFight", "FinalFight"]:
		var f := scene.find_child(fight_name, true, false)
		if f and String(f.get("_state")) in ["intro", "fight", "lost"]:
			return true
	return false


func _on_player_died() -> void:
	if _boss_fight_handles_death():
		return
	_dead = true
	_respawn_ok = false
	await get_tree().create_timer(1.4).timeout
	if hud and hud.has_method("show_banner"):
		hud.show_banner("HAS MUERTO", Color(0.62, 0.05, 0.04), "Presiona R para volver a la última hoguera", 0.0)
	_respawn_ok = true


func _unhandled_input(event: InputEvent) -> void:
	if _menu_open and event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k >= KEY_0 and k <= KEY_4:
			_equip_from_key(k - KEY_0)
			get_viewport().set_input_as_handled()
			return
	if _dead and _respawn_ok and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_respawn()


func _respawn() -> void:
	_dead = false
	_respawn_ok = false
	if hud:
		var banner := hud.get("_banner") as Control
		if banner:
			banner.modulate.a = 0.0
	var pos := Vector3(0, 0.2, 20)
	var yaw := 0.0
	if checkpoint and is_instance_valid(checkpoint):
		pos = checkpoint.respawn_point()
		var to: Vector3 = checkpoint.global_position - pos
		yaw = atan2(-to.x, -to.z)
	respawn_enemies()
	if player.has_method("revive"):
		player.revive(pos, yaw)
