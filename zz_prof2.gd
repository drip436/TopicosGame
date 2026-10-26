extends SceneTree
func medir(tag: String):
	await create_timer(1.5).timeout
	var acc := 0.0
	for i in 30:
		await process_frame
		acc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000
	print("%-28s proc %.1f ms  fps %d" % [tag, acc / 30.0, Engine.get_frames_per_second()])
func _initialize():
	change_scene_to_file("res://Scenes/main.tscn")
	var v: Node
	for i in 600:
		await physics_frame
		v = current_scene.find_child("VidaDelCampus", true, false) if current_scene else null
		if v and v.get("player"):
			break
	v.world._explore = true
	v.player.global_position = Vector3(-118, 0.3, -98)
	await create_timer(4.0).timeout
	await medir("base")
	var groups := {}
	for n in current_scene.find_children("*", "", true, false):
		var s = n.get_script()
		if s and n.is_processing():
			var k: String = s.resource_path.get_file() if s.resource_path != "" else "anon"
			groups[k] = groups.get(k, []) + [n]
	for k in groups:
		print("  ", k, ": ", groups[k].size())
	for k in groups:
		for n in groups[k]:
			n.set_process(false)
		await medir("sin _process de " + k)
		for n in groups[k]:
			n.set_process(true)
	quit()
