extends SceneTree
func medir(tag: String):
	await create_timer(1.5).timeout
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await create_timer(2.5).timeout
	var fps := (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)
	print("%-34s fps %5.1f  proc %5.1f  phys %5.1f  draws %d  prims %d" % [tag, fps, Performance.get_monitor(Performance.TIME_PROCESS) * 1000, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
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
	await create_timer(3.0).timeout
	await medir("base")
	v.enemies_enabled = false
	for e in get_nodes_in_group("enemy"):
		e.queue_free()
	await medir("sin enemigos")
	for n in ["BossFight", "LibraryFight", "ComputeFight", "LabFight", "FinalFight"]:
		var f = current_scene.find_child(n, true, false)
		if f:
			f.queue_free()
	await medir("sin jefes")
	var vp := root.get_viewport()
	var env: Environment = null
	for we in current_scene.find_children("*", "WorldEnvironment", true, false):
		env = we.environment
	if env:
		print("env: sdfgi ", env.sdfgi_enabled, " ssao ", env.ssao_enabled, " ssr ", env.ssr_enabled, " ssil ", env.ssil_enabled, " vfog ", env.volumetric_fog_enabled, " glow ", env.glow_enabled, " fog ", env.fog_enabled)
		env.volumetric_fog_enabled = false
		await medir("sin niebla volumétrica")
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.ssr_enabled = false
		env.sdfgi_enabled = false
		await medir("sin ssao/ssil/ssr/sdfgi")
	for l in current_scene.find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D:
			print("sol sombras ", l.shadow_enabled, " splits ", l.directional_shadow_mode, " max ", l.directional_shadow_max_distance)
	for l in current_scene.find_children("*", "OmniLight3D", true, false):
		l.shadow_enabled = false
	await medir("omni sin sombra")
	for l in current_scene.find_children("*", "OmniLight3D", true, false):
		l.visible = false
	await medir("sin omni")
	for p in current_scene.find_children("*", "GPUParticles3D", true, false):
		p.visible = false
	await medir("sin partículas")
	print("omni total ", current_scene.find_children("*", "OmniLight3D", true, false).size(), " spot ", current_scene.find_children("*", "SpotLight3D", true, false).size(), " particulas ", current_scene.find_children("*", "GPUParticles3D", true, false).size(), " mmi ", current_scene.find_children("*", "MultiMeshInstance3D", true, false).size(), " mi ", current_scene.find_children("*", "MeshInstance3D", true, false).size())
	quit()
