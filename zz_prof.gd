extends SceneTree
# Recorre el mapa con el jugador y mide FPS y tiempos.
var PTS := {
	"plaza": Vector3(0, 0.3, 10), "res_poniente": Vector3(-205, 0.3, 60), "ingenieria": Vector3(-232, 0.3, 2),
	"cafeteria": Vector3(-118, 0.3, -98), "estadio": Vector3(-80, 0.3, -150), "derecho": Vector3(-219, 0.3, -180),
	"res_oriente": Vector3(205, 0.3, 60), "ciencias": Vector3(178, 0.3, -13), "medicina": Vector3(120, 0.3, -92),
	"est_norte": Vector3(80, 0.3, -150), "quimica": Vector3(172, 0.3, -180), "arquitectura": Vector3(111, 0.3, -251),
	"gimnasio": Vector3(205, 0.3, -236), "rescate": Vector3(240, 0.3, -324), "explanada": Vector3(0, 0.3, -205),
	"bosque": Vector3(-130, 0.3, -280), "computo": Vector3(225, 0.3, -70), "lab": Vector3(170, 0.3, -260),
}
func _initialize():
	change_scene_to_file("res://Scenes/main.tscn")
	var v: Node
	for i in 600:
		await physics_frame
		v = current_scene.find_child("VidaDelCampus", true, false) if current_scene else null
		if v and v.get("player"):
			break
	var w = v.world
	w._explore = true
	var p: Node3D = v.player
	await create_timer(10.0).timeout
	var only := OS.get_cmdline_user_args()
	for k in PTS:
		if only.size() > 0 and not only.has(k):
			continue
		p.global_position = PTS[k]
		p.set("velocity", Vector3.ZERO)
		await create_timer(5.0).timeout
		var f0 := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_msec()
		await create_timer(2.0).timeout
		var fps := (Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)
		print("%-13s fps %5.1f  proc %5.1fms  phys %5.1fms  draws %5d  prims %8d  enem %3d  luces %d  nodos %d" % [k, fps,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			get_nodes_in_group("enemy").size(), 0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	quit()
