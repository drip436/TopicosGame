extends SceneTree
var S := "/tmp/claude-1000/-home-adr1304-Documents-topicos-game/15bac2c3-6e1d-4350-b92b-8c06cbca7e2c/scratchpad/w/"
var cam: Camera3D
var p
func shot(n, ang := 30.0):
	var pp: Vector3 = p.global_position
	var vis: Node3D = p.get_node("Visual")
	var fwd: Vector3 = -vis.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized().rotated(Vector3.UP, deg_to_rad(ang))
	cam.global_position = pp + fwd * 2.3 + Vector3(0, 1.4, 0)
	cam.look_at(pp + Vector3(0, 1.0, 0))
	cam.current = true
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(S + n + ".png")
func _initialize():
	var cls: String = OS.get_cmdline_user_args()[0]
	preload("res://jugador/player_classes.gd").selected = cls
	change_scene_to_file("res://Scenes/main.tscn")
	var v: Node
	for i in 600:
		await physics_frame
		v = current_scene.find_child("VidaDelCampus", true, false) if current_scene else null
		if v and v.get("player"):
			break
	p = v.player
	await create_timer(2.0).timeout
	p.global_position = Vector3(-60, 0.3, 46)
	await create_timer(1.5).timeout
	for h in current_scene.find_children("*", "CanvasLayer", true, false):
		h.visible = false
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 150, 0)
	sun.light_energy = 2.0
	current_scene.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 45
	current_scene.add_child(cam)
	await shot(cls + "_reposo", 35)
	await shot(cls + "_reposo_lado", 100)
	p._try_attack()
	for k in 3:
		await create_timer(0.15).timeout
		await shot(cls + "_ataque%d" % k, 60)
	quit()
