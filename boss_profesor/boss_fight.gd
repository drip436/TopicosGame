extends Node3D
## Controlador de la pelea. Arrastra "boss_fight.tscn" dentro de la escena de la arena
## (como hijo del nodo raíz) y listo. Esto hace:
##  1. Pone al jefe dormido en la azotea del edificio central.
##  2. Cuando el jugador entra a la plaza, cierra la entrada con niebla, el jefe ruge,
##     salta y cae en la arena. Aparece su nombre y barra de vida (estilo Dark Souls).
##  3. Fase 1 con llovizna; fase 2 con tormenta, rayos y maza eléctrica.
##  4. Al ganar: "ENEMIGO DERROTADO"; al morir: "HAS MUERTO" (R para reintentar).

signal battle_started
signal phase_changed(phase: int)
signal boss_defeated
signal player_died

@export var boss_name: String = "Catedrático de Hierro, Heraldo de la Tormenta"
@export var boss_max_health: float = 1400.0
## Crea un jugador de prueba si no hay ningún nodo en el grupo "player".
@export var spawn_test_player: bool = true
## La pelea empieza cuando el jugador está a esta distancia del centro de la plaza.
@export var trigger_distance: float = 16.0
@export var arena_center: Vector3 = Vector3.ZERO
## Punto alrededor del cual se busca la azotea más alta para el jefe.
@export var rooftop_search_center: Vector3 = Vector3(0, 0, -44)
@export var rooftop_search_size: Vector2 = Vector2(28, 8)
## Dónde aterriza el jefe (si existe un Marker3D "BossSpawn" en la escena, se usa ese).
@export var landing_point: Vector3 = Vector3(0, 0, -8)
## Niebla de jefe en la entrada (posición y ancho del portón).
@export var fog_gate_position: Vector3 = Vector3(0, 0, 23)
@export var fog_gate_width: float = 15.0
@export_range(0.0, 1.0) var rain_phase1: float = 0.15
@export_range(0.0, 1.0) var rain_phase2: float = 1.0
## Al ganar la tormenta se disipa y solo cae una que otra gota (0 = deja de llover).
@export var clear_weather_on_victory: bool = true
@export_range(0.0, 0.3) var rain_after_victory: float = 0.03

const BOSS := preload("boss_profesor.gd")
const HUD := preload("boss_hud.gd")
const PLAYER := preload("test_player.gd")

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float alpha = 0.0;
void fragment() {
	vec2 uv = UV;
	float n1 = texture(noise_tex, uv * vec2(1.4, 0.8) + vec2(TIME * 0.05, -TIME * 0.12)).r;
	float n2 = texture(noise_tex, uv * vec2(2.6, 1.6) + vec2(-TIME * 0.09, -TIME * 0.2)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	float edge = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x) * smoothstep(0.0, 0.08, 1.0 - uv.y);
	ALBEDO = mix(vec3(0.55, 0.58, 0.62), vec3(0.95, 0.95, 1.0), n) * 1.3;
	ALPHA = clamp((0.25 + n * 0.75) * edge * alpha, 0.0, 1.0);
}
"""

var boss: CharacterBody3D
var hud: CanvasLayer
var player: Node3D
var weather: Node
var arena: Node
var _fog: MeshInstance3D
var _fog_body: StaticBody3D
var _state := "setup"   # setup | waiting | intro | fight | won | lost
var _intro_requested := false


func _ready() -> void:
	arena = get_parent() if get_parent() else self
	_setup.call_deferred()


func _setup() -> void:
	weather = _find_by_name(get_tree().current_scene, "Weather")
	var bs := _find_by_name(get_tree().current_scene, "BossSpawn")
	if bs is Node3D:
		landing_point = (bs as Node3D).global_position

	hud = CanvasLayer.new()
	hud.set_script(HUD)
	add_child(hud)

	# Jugador
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	elif spawn_test_player:
		player = CharacterBody3D.new()
		player.set_script(PLAYER)
		player.name = "TestPlayer"
		var ps := _find_by_name(get_tree().current_scene, "PlayerSpawn")
		var spawn := Vector3(0, 0.2, 20)
		var yaw := 0.0
		if ps is Node3D:
			spawn = (ps as Node3D).global_position + Vector3(0, 0.2, 2.0)
			yaw = (ps as Node3D).global_rotation.y
		arena.add_child(player)
		player.global_position = spawn
		player.rotation.y = yaw
		_disable_other_cameras()
		hud.show_hint("WASD mover · Shift correr · Espacio rodar\nClic izq. atacar · Clic medio / Tab fijar objetivo\nF beber café (curar) · Esc soltar mouse")
	if player and player.has_signal("died"):
		player.died.connect(_on_player_died)

	# Jefe
	boss = CharacterBody3D.new()
	boss.set_script(BOSS)
	boss.name = "BossProfesor"
	boss.set("boss_name", boss_name)
	boss.set("max_health", boss_max_health)
	arena.add_child(boss)
	boss.weather = weather
	boss.fx_parent = arena
	boss.target = player
	boss.health_changed.connect(func(c, m): hud.set_boss_health(c, m))
	boss.damaged.connect(func(a): hud.boss_damaged(a))
	boss.intro_landed.connect(func(): hud.show_boss(boss_name))
	boss.battle_started.connect(func():
		_state = "fight"
		battle_started.emit())
	boss.phase_changed.connect(_on_phase)
	boss.defeated.connect(_on_boss_defeated)
	boss.global_position = rooftop_search_center + Vector3(0, 40, 0)

	_build_fog_gate()
	if weather and weather.has_method("set_storm"):
		weather.set_storm(rain_phase1, 0.5)

	await get_tree().physics_frame
	await get_tree().physics_frame
	var roof := _find_rooftop()
	boss.place_dormant(roof, arena_center)
	_state = "waiting"
	if _intro_requested:
		start_fight()


## Empieza la pelea manualmente (por ejemplo, desde tu propia cinemática).
func start_fight() -> void:
	if _state == "setup":
		_intro_requested = true
		return
	if _state != "waiting":
		return
	_state = "intro"
	_close_fog_gate()
	boss.begin_intro(landing_point)


func _physics_process(_delta: float) -> void:
	if player and hud and "hp" in player:
		hud.set_player(player.hp, player.max_hp, player.stamina, player.max_stamina, player.flasks)
	if _state == "waiting" and player:
		var d := Vector2(player.global_position.x - arena_center.x, player.global_position.z - arena_center.z).length()
		if d < trigger_distance:
			start_fight()


func _unhandled_input(event: InputEvent) -> void:
	if _state == "lost" and event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()


func _on_phase(p: int) -> void:
	if p == 2 and weather and weather.has_method("set_storm"):
		weather.set_storm(rain_phase2, 4.0)
	phase_changed.emit(p)


func _on_boss_defeated() -> void:
	_state = "won"
	hud.hide_boss(2.0)
	await get_tree().create_timer(2.2).timeout
	hud.show_banner("ENEMIGO DERROTADO", Color(0.92, 0.78, 0.38), "", 5.0)
	if weather and clear_weather_on_victory and weather.has_method("calm"):
		weather.calm(12.0, rain_after_victory)
	elif weather and weather.has_method("set_storm"):
		weather.set_storm(rain_phase1, 10.0)
	await get_tree().create_timer(4.0).timeout
	_open_fog_gate()
	boss_defeated.emit()


func _on_player_died() -> void:
	if _state == "won":
		return
	_state = "lost"
	boss.target = null
	await get_tree().create_timer(1.2).timeout
	hud.show_banner("HAS MUERTO", Color(0.62, 0.05, 0.04), "Presiona R para reintentar", 0.0)
	player_died.emit()


# ------------------------------------------------------------- utilidades

func _find_by_name(root: Node, n: String) -> Node:
	if root == null:
		return null
	if root.name == n:
		return root
	return root.find_child(n, true, false)


func _disable_other_cameras() -> void:
	for c in get_tree().current_scene.find_children("*", "Camera3D", true, false):
		if player.is_ancestor_of(c):
			continue
		c.set_process(false)
		c.set_process_unhandled_input(false)
		c.current = false


func _find_rooftop() -> Vector3:
	var space := get_world_3d().direct_space_state
	var best := rooftop_search_center
	var best_score := -INF
	var exclude: Array[RID] = [boss.get_rid()]
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	for ix in range(-3, 4):
		for iz in range(-1, 2):
			var p := rooftop_search_center + Vector3(ix * rooftop_search_size.x / 6.0, 0, iz * rooftop_search_size.y / 2.0)
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 80, 0), p + Vector3(0, -1, 0))
			q.exclude = exclude
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var h: float = hit["position"].y
			var score := h - absf(p.x - arena_center.x) * 0.25 + iz * 0.5
			if score > best_score:
				best_score = score
				best = hit["position"]
	return best + Vector3(0, 0.05, 0)


func _build_fog_gate() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.noise = noise
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FOG_SHADER
	m.shader = sh
	m.set_shader_parameter("noise_tex", nt)
	var q := QuadMesh.new()
	q.size = Vector2(fog_gate_width, 7.5)
	_fog = MeshInstance3D.new()
	_fog.mesh = q
	_fog.material_override = m
	_fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog.visible = false
	arena.add_child(_fog)
	_fog.global_position = fog_gate_position + Vector3(0, 3.75, 0)
	var light := OmniLight3D.new()
	light.light_color = Color(0.85, 0.88, 1.0)
	light.light_energy = 0.0
	light.omni_range = 9.0
	light.name = "FogLight"
	light.position = Vector3(0, 0, -1.0)
	_fog.add_child(light)


func _close_fog_gate() -> void:
	_fog.visible = true
	var m: ShaderMaterial = _fog.material_override
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v): m.set_shader_parameter("alpha", v), 0.0, 0.85, 1.5)
	tw.tween_property(_fog.get_node("FogLight"), "light_energy", 1.2, 1.5)
	_fog_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(fog_gate_width, 8, 0.8)
	cs.shape = bx
	_fog_body.add_child(cs)
	arena.add_child(_fog_body)
	_fog_body.global_position = fog_gate_position + Vector3(0, 4, 0)


func _open_fog_gate() -> void:
	if _fog_body:
		_fog_body.queue_free()
	var m: ShaderMaterial = _fog.material_override
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("alpha", v), 0.85, 0.0, 2.0)
	tw.parallel().tween_property(_fog.get_node("FogLight"), "light_energy", 0.0, 2.0)
	tw.tween_callback(func(): _fog.visible = false)
