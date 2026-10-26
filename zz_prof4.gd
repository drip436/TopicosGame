extends SceneTree
func medir(tag: String):
	await create_timer(1.5).timeout
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await create_timer(2.5).timeout
	var fps := (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)
	print("%-34s fps %5.1f  draws %d  prims %d" % [tag, fps, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
func _initialize():
	change_scene_to_file("res://Scenes/main.tscn")
	var v: Node
	for i in 600:
		await physics_frame
		v = current_scene.find_child("VidaDelCampus", true, false) if current_scene else null
		if v and v.get("player"):
			break
	var p: Node3D = v.player
	await create_timer(12.0).timeout
	await medir("plaza base 1")
	await medir("plaza base 2")
	for c in current_scene.find_children("*", "CanvasLayer", true, false) + root.get_children().filter(func(x): return x is CanvasLayer):
		if not c.visible:
			continue
		var info := ""
		for ch in c.find_children("*", "CanvasItem", true, false):
			if ch.material is ShaderMaterial or (ch is Control and ch.visible and ch.get("texture") != null):
				info += " %s(%s)" % [ch.name, ch.get_class()]
		c.visible = false
		await medir("sin " + str(c.get_path()).right(40))
		print("   contenido:", info, " script ", c.get_script().resource_path if c.get_script() else "")
		c.visible = true
	quit()
