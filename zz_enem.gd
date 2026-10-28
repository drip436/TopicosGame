extends SceneTree
var S := "/tmp/claude-1000/-home-adr1304-Documents-topicos-game/15bac2c3-6e1d-4350-b92b-8c06cbca7e2c/scratchpad/w/"
func _initialize():
	change_scene_to_file("res://Scenes/main.tscn")
	var v: Node
	for i in 600:
		await physics_frame
		v = current_scene.find_child("VidaDelCampus", true, false) if current_scene else null
		if v and v.get("player"):
			break
	var p = v.player
	p.global_position = Vector3(0, 0.2, 30)
	await create_timer(2.0).timeout
	for h in current_scene.find_children("*", "CanvasLayer", true, false):
		h.visible = false
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 160, 0)
	sun.light_energy = 2.0
	current_scene.add_child(sun)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	var cam := Camera3D.new()
	cam.fov = 40
	current_scene.add_child(cam)
	cam.current = true
	var E = load("res://mundo/enemy.gd")
	var types := ["robot_hacha", "robot_espada", "robot_laser", "androide_espadas"]
	var base := Vector3(30, 0, 30)
	for t in types:
		var e = E.new()
		e.type = t
		e.wander_radius = 0.0
		e.target = p
		e.fx_parent = v
		e.place(base + Vector3(0, 0.05, 0), 0.0)
		v.add_child(e)
		await create_timer(0.8).timeout
		var big := 2.4 if t in ["mecha", "mutante_grande"] else 1.0
		cam.global_position = base + Vector3(1.8, 1.4, -2.6) * big
		cam.look_at(base + Vector3(0, 1.0 * big, 0))
		await create_timer(0.3).timeout
		cam.current = true
		await process_frame
		root.get_texture().get_image().save_png(S + "e_" + t + ".png")
		var vis := 0
		for mi in e.find_children("*", "MeshInstance3D", true, false):
			if mi.is_visible_in_tree():
				vis += 1
		print(t, " mallas visibles ", vis, " glb ", e.get("_skel") != null)
		e.queue_free()
		await process_frame
	quit()
