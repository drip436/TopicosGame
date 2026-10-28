extends SceneTree
var S := "/tmp/claude-1000/-home-adr1304-Documents-topicos-game/15bac2c3-6e1d-4350-b92b-8c06cbca7e2c/scratchpad/w/"
var cam: Camera3D
func shot(n):
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(S + n + ".png")
func mirar(desde: Vector3, hacia: Vector3):
	cam.global_position = desde
	cam.look_at(hacia)
	cam.current = true
func _initialize():
	preload("res://jugador/player_classes.gd").selected = "frontend"
	change_scene_to_file("res://Scenes/main.tscn")
	var v: Node
	for i in 600:
		await physics_frame
		v = current_scene.find_child("VidaDelCampus", true, false) if current_scene else null
		if v and v.get("player"):
			break
	await create_timer(3.0).timeout
	print("paso 1")
	var p = v.player
	var P = root.get_node("Partida")
	var m: Node3D = v.get_node_or_null("Mercader")
	print("mercader: ", m != null, " en ", m.global_position if m else null)
	cam = Camera3D.new()
	cam.fov = 40
	current_scene.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 160, 0)
	sun.light_energy = 1.6
	current_scene.add_child(sun)
	# Jugador cerca del mercader (lo saluda)
	var fwd: Vector3 = -m.global_basis.z
	p.global_position = m.global_position + fwd * 2.0
	await create_timer(0.6).timeout
	print("paso 2")
	mirar(m.global_position + fwd * 2.6 + Vector3(0.6, 1.5, 0), m.global_position + Vector3(0, 1.2, 0))
	await create_timer(0.3).timeout
	print("paso 3")
	for c in current_scene.find_children("*", "CanvasLayer", true, false):
		c.visible = false
	await shot("merc_saludo")
	print("paso 4")
	await create_timer(2.5).timeout
	print("paso 5")
	await shot("merc_celular")
	print("paso 6")
	for c in current_scene.find_children("*", "CanvasLayer", true, false):
		c.visible = true
	# Tienda
	P.dar_creditos(9000)
	await create_timer(0.5).timeout
	print("paso 7")
	m.set("_near", true)
	m._on_interact()
	await create_timer(0.5).timeout
	print("paso 8")
	await shot("tienda_armas")
	print("paso 9")
	var t = root.get_children().filter(func(x): return x.get_script() and x.get_script().resource_path.ends_with("tienda.gd"))[0]
	var pe = t.find_children("*", "VBoxContainer", true, false).filter(func(x): return x.get_script() != null)[0]
	pe._cambiar("armaduras")
	await create_timer(0.3).timeout
	print("paso 10")
	await shot("tienda_armaduras")
	print("paso 11")
	print("compra rector: '", P.comprar("armadura", "rector"), "'  katana: '", P.comprar("arma", "katana_plasma"), "'  creditos ", P.creditos)
	P.equipar("armadura", "rector", p)
	P.equipar("arma", "katana_plasma", p)
	await create_timer(0.3).timeout
	print("paso 12")
	await shot("tienda_tras_compra")
	print("paso 13")
	t.cerrar()
	await create_timer(0.8).timeout
	print("paso 14")
	for c in current_scene.find_children("*", "CanvasLayer", true, false):
		c.visible = false
	p.global_position = Vector3(-60, 0.3, 46)
	await create_timer(1.0).timeout
	print("paso 15")
	var pp: Vector3 = p.global_position
	var f2: Vector3 = -p.get_node("Visual").global_basis.z
	mirar(pp + f2 * 2.4 + Vector3(0.8, 1.3, 0), pp + Vector3(0, 1.0, 0))
	await shot("jug_rector_katana")
	print("paso 16")
	p._try_attack()
	await create_timer(0.2).timeout
	print("paso 17")
	await shot("jug_ataque_katana")
	print("paso 18")
	# Ropa de la clase (mago nuevo)
	P.equipar("armadura", "", p)
	P.equipar("arma", "estoque", p)
	await create_timer(0.5).timeout
	print("paso 19")
	await shot("jug_mago")
	print("paso 20")
	mirar(pp + f2 * 1.0 + Vector3(0.25, 1.62, 0), pp + Vector3(0, 1.5, 0))
	await shot("jug_mago_cara")
	print("paso 21")
	# Créditos al matar
	var c0: int = P.creditos
	var E = load("res://mundo/enemy.gd")
	var e = E.new()
	e.type = "androide_espadas"
	e.target = p
	e.fx_parent = v
	e.place(pp + Vector3(0, 0.05, -3), 0.0)
	v.get_node("Enemigos").add_child(e)
	e.died.connect(func(_n): v._drop_credits(e))
	await create_timer(0.5).timeout
	print("paso 22")
	e.take_damage(9999.0, pp)
	await create_timer(2.5).timeout
	print("paso 23")
	print("creditos antes ", c0, " despues ", P.creditos)
	# Menú de pausa: Equipo
	for c in current_scene.find_children("*", "CanvasLayer", true, false):
		c.visible = true
	var pausa = p.get_children().filter(func(c): return c.get_script() and String(c.get_script().resource_path).ends_with("menu_pausa.gd"))[0]
	pausa.abrir()
	pausa._on_boton("equipo")
	await create_timer(0.4).timeout
	print("paso 24")
	await shot("pausa_equipo")
	print("paso 25")
	pausa.cerrar()
	quit()
