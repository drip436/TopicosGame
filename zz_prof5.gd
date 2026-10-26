extends SceneTree
func medir(tag: String):
	await create_timer(1.0).timeout
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await create_timer(2.0).timeout
	var fps := (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)
	print("%-30s fps %5.1f  draws %d  prims %d  objs %d" % [tag, fps, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
func _initialize():
	change_scene_to_file("res://Scenes/main.tscn")
	var v: Node
	for i in 600:
		await physics_frame
		v = current_scene.find_child("VidaDelCampus", true, false) if current_scene else null
		if v and v.get("player"):
			break
	v.world._explore = true
	v.player.global_position = Vector3(-232, 0.3, 2)
	await create_timer(12.0).timeout
	await medir("base")
	var sun: DirectionalLight3D = current_scene.find_child("StormLight", true, false)
	sun.directional_shadow_max_distance = 80
	await medir("sombra sol 80 m")
	sun.shadow_enabled = false
	await medir("sin sombra sol")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160
	var mmis := current_scene.find_children("*", "MultiMeshInstance3D", true, false)
	var mis := current_scene.find_children("*", "MeshInstance3D", true, false)
	print("mmi ", mmis.size(), " mi ", mis.size())
	for m in mis:
		m.visible = false
	await medir("sin MeshInstance3D")
	for m in mis:
		m.visible = true
	for m in mmis:
		m.visible = false
	await medir("sin MultiMesh")
	for m in mmis:
		m.visible = true
	for e in get_nodes_in_group("enemy"):
		e.visible = false
	await medir("enemigos ocultos")
	quit()
