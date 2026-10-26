extends Node3D
## Controlador de la pelea del segundo jefe en la Biblioteca Central.
## CampusWorld lo crea al iniciar el juego (spawn_library_boss), así que no hay
## que tocar main.tscn. Hace esto:
##  1. El Bibliófilo Demente espera de espaldas, escribiendo en un pizarrón.
##  2. Al entrar el jugador a la sala, la puerta se cierra con niebla, el jefe
##     voltea y grita; aparecen su nombre y su barra de vida.
##  3. Fase 2: la biblioteca empieza a arder (fuego, humo y brasas).
##  4. Al ganar: "ENEMIGO DERROTADO" y se abre el Pasaje Central (sello del campus).
##  5. Al morir: "HAS MUERTO"; con R reintentas en la entrada de la biblioteca,
##     sin reiniciar el juego.

signal battle_started
signal phase_changed(phase: int)
signal boss_defeated
signal player_died

const BOSS_SCENE: PackedScene = preload("BossBibliotecario.tscn")
const LFX := preload("library_fx.gd")
const HUD := preload("res://boss_profesor/boss_hud.gd")
const WORLD := preload("res://scripts/campus_world.gd")

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

@export var boss_name: String = "Doctor Euclides Barrabás, el Bibliófilo Demente"
@export var boss_max_health: float = 1600.0

var world: Node
var boss: CharacterBody3D
var hud: CanvasLayer
var player: Node3D
var boards: Array = []
var _own_hud := false
var _fx_root: Node3D
var _fires: Node3D
var _fog: MeshInstance3D
var _fog_body: StaticBody3D
var _state := "setup"   # setup | waiting | intro | fight | won | lost
var _center := Vector3.ZERO
var _fire_spots: Array[Vector3] = []
var _fire_t := 0.0
var _fires_lit := 0


func _ready() -> void:
	_setup.call_deferred()


func _setup() -> void:
	if world == null and get_tree().current_scene:
		world = get_tree().current_scene.find_child("CampusWorld", true, false)
	_center = WORLD.LIB
	_fx_root = Node3D.new()
	_fx_root.name = "FX"
	add_child(_fx_root)
	# Reutiliza el HUD de la primera pelea (si existe) para no duplicar barras
	var bf := get_tree().current_scene.find_child("BossFight", true, false) if get_tree().current_scene else null
	if bf and bf.get("hud") is CanvasLayer:
		hud = bf.get("hud")
	else:
		hud = CanvasLayer.new()
		hud.set_script(HUD)
		add_child(hud)
		_own_hud = true
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		if player.has_signal("died"):
			player.died.connect(_on_player_died)
	_build_boards()
	_build_fog_gate()
	_build_fire_spots()
	_spawn_boss()
	_state = "waiting"


func _spawn_boss() -> void:
	boss = BOSS_SCENE.instantiate() as CharacterBody3D
	boss.set("boss_name", boss_name)
	boss.set("max_health", boss_max_health)
	add_child(boss)
	boss.fx_parent = _fx_root
	boss.target = player
	boss.boards = boards
	boss.arena_center = _center + Vector3(0, 0, 1)
	boss.arena_half = Vector2(25.0, 17.0)
	boss.health_changed.connect(func(c, m): hud.set_boss_health(c, m))
	boss.damaged.connect(func(a): hud.boss_damaged(a))
	boss.battle_started.connect(func():
		_state = "fight"
		battle_started.emit())
	boss.phase_changed.connect(_on_phase)
	boss.defeated.connect(_on_boss_defeated)
	var b0: Dictionary = boards[0]
	var spot: Vector3 = (b0["pos"] as Vector3) + (b0["fwd"] as Vector3) * 1.4
	boss.place_dormant(Vector3(spot.x, 0.05, spot.z), b0["pos"])


func _physics_process(_delta: float) -> void:
	if _own_hud and player and "hp" in player:
		hud.set_player(player.hp, player.max_hp, player.stamina, player.max_stamina, player.flasks)
		if player.has_method("get_status_names"):
			hud.set_status(player.get_status_names())
		if player.has_method("get_buildups") and hud.has_method("set_buildups"):
			hud.set_buildups(player.get_buildups())
			hud.set_flask_max(player.get_max_flasks())
	if _state == "waiting" and player and is_instance_valid(player):
		var l := player.global_position - _center
		if absf(l.x) < 27.0 and l.z > -20.0 and l.z < 18.5:
			_start()
	if _state == "fight" and boss and boss.phase == 2:
		_fire_t -= _delta
		if _fire_t <= 0.0 and _fires_lit < _fire_spots.size():
			_fire_t = 1.6
			_light_fire(_fires_lit)
			_fires_lit += 1


func _start() -> void:
	_state = "intro"
	_close_fog_gate()
	hud.show_boss(boss_name)
	hud.set_boss_health(boss.health, boss.max_health)
	hud.show_hint("Las flechas siguen la curva de la fórmula escrita en el pizarrón.\nRueda (Espacio) para esquivarlas · Si te atrapa, te rasguña sin piedad", 9.0)
	boss.begin_intro()


func _unhandled_input(event: InputEvent) -> void:
	if _state == "lost" and event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_retry()


func _on_phase(p: int) -> void:
	if p == 2:
		_fire_t = 0.0
		for i in 3:
			_light_fire(_fires_lit)
			_fires_lit += 1
		LFX.embers(_fires, _center + Vector3(0, 4, 0), Vector3(24, 3, 18), 110)
		for sp in [Vector3(-24, 9, -14), Vector3(22, 9, 10), Vector3(0, 12, -18)]:
			LFX.smoke(_fires, _center + sp, 1.6)
		if player and player.has_method("add_camera_shake"):
			player.add_camera_shake(0.4)
	phase_changed.emit(p)


func _on_boss_defeated() -> void:
	_state = "won"
	hud.hide_boss(2.0)
	await get_tree().create_timer(2.2).timeout
	hud.show_banner("ENEMIGO DERROTADO", Color(0.92, 0.78, 0.38), "", 5.0)
	await get_tree().create_timer(3.0).timeout
	_open_fog_gate()
	# Las llamas se apagan poco a poco
	if _fires:
		for f in _fires.get_children():
			if f is GPUParticles3D:
				(f as GPUParticles3D).emitting = false
	if world and world.has_method("register_boss_defeated"):
		world.register_boss_defeated("biblioteca")
	boss_defeated.emit()


func _on_player_died() -> void:
	if _state != "fight" and _state != "intro":
		return
	_state = "lost"
	if boss:
		boss.target = null
	await get_tree().create_timer(1.2).timeout
	hud.show_banner("HAS MUERTO", Color(0.62, 0.05, 0.04), "Presiona R para reintentar", 0.0)
	player_died.emit()


## Reintento: el jugador revive en la entrada y el jefe vuelve a empezar.
func _retry() -> void:
	_state = "setup"
	hud.hide_boss(0.0)
	var banner := hud.get("_banner") as Control
	if banner:
		banner.modulate.a = 0.0
	if boss:
		boss.queue_free()
	for c in _fx_root.get_children():
		c.queue_free()
	if _fires:
		_fires.queue_free()
		_fires = null
	_fires_lit = 0
	for b in boards:
		(b["label"] as Label3D).text = ""
		(b["graph"] as MeshInstance3D).mesh = null
	_open_fog_gate()
	if player and player.has_method("revive"):
		player.revive(_center + Vector3(0, 0.2, 32), 0.0)
	await get_tree().physics_frame
	_build_fire_spots()
	_spawn_boss()
	_state = "waiting"


# ------------------------------------------------------------- pizarrones

func _build_boards() -> void:
	boards.clear()
	for bd in WORLD.LIB_BOARDS:
		var yaw := deg_to_rad(float(bd[1]))
		var bb := Basis(Vector3.UP, yaw)
		var pos: Vector3 = _center + (bd[0] as Vector3)
		var fwd := bb * Vector3(0, 0, 1)
		var side := bb * Vector3(1, 0, 0)
		var holder := Node3D.new()
		holder.name = "Pizarron"
		holder.transform = Transform3D(bb, pos + Vector3(0, 1.6, 0) + fwd * 0.045)
		add_child(holder)
		var label := Label3D.new()
		label.font_size = 64
		label.pixel_size = 0.0045
		label.modulate = Color(0.92, 0.94, 0.9)
		label.outline_size = 0
		label.shaded = false
		label.double_sided = false
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.width = 400.0
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.position = Vector3(-1.85, 0.6, 0)
		label.text = ""
		holder.add_child(label)
		var graph := MeshInstance3D.new()
		graph.position = Vector3(-0.05, -0.25, 0)
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(0.9, 0.92, 0.9)
		gm.emission_enabled = true
		gm.emission = gm.albedo_color
		gm.emission_energy_multiplier = 0.4
		gm.cull_mode = BaseMaterial3D.CULL_DISABLED
		graph.material_override = gm
		graph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(graph)
		boards.append({"pos": pos, "fwd": fwd, "side": side, "label": label, "graph": graph, "graph_mat": gm})


# ------------------------------------------------------------- fuego

func _build_fire_spots() -> void:
	_fires = Node3D.new()
	_fires.name = "Incendio"
	add_child(_fires)
	_fire_spots.clear()
	for p in [Vector3(-28, 0, -12), Vector3(28, 0, 8), Vector3(-14, 0, -20.5), Vector3(14, 0, -20.5),
			Vector3(-28, 0, 10), Vector3(22, 0, -12), Vector3(-22, 0, 12), Vector3(28, 0, -16),
			Vector3(0, 0, -20.5), Vector3(-25, 0, -2), Vector3(22, 0, 14), Vector3(-7, 0.5, 8.5),
			Vector3(9.5, 0.5, -6.5), Vector3(-26, 7.4, -19), Vector3(20, 7.4, -19), Vector3(-28, 7.4, 4)]:
		_fire_spots.append(_center + p)


func _light_fire(i: int) -> void:
	if i >= _fire_spots.size() or _fires == null:
		return
	var p: Vector3 = _fire_spots[i]
	LFX.fire(_fires, p + Vector3(0, 0.3, 0), 1.2 if i % 3 == 0 else 0.9, i < 7)
	LFX.puff(_fires, p + Vector3(0, 1.0, 0), Color(3.0, 1.4, 0.4, 1), 20, 0.4, 3.5, 1.5)


# ------------------------------------------------------------- niebla

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
	q.size = Vector2(10.5, 8.0)
	_fog = MeshInstance3D.new()
	_fog.mesh = q
	_fog.material_override = m
	_fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog.visible = false
	add_child(_fog)
	_fog.global_position = _center + Vector3(0, 4.0, 23.3)
	var light := OmniLight3D.new()
	light.name = "FogLight"
	light.light_color = Color(0.85, 0.88, 1.0)
	light.light_energy = 0.0
	light.omni_range = 9.0
	light.position = Vector3(0, 0, -1.0)
	_fog.add_child(light)


func _close_fog_gate() -> void:
	_fog.visible = true
	var m: ShaderMaterial = _fog.material_override
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha", v), 0.0, 0.85, 1.5)
	tw.tween_property(_fog.get_node("FogLight"), "light_energy", 1.2, 1.5)
	if _fog_body == null:
		_fog_body = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(11.0, 8.0, 0.8)
		cs.shape = bx
		_fog_body.add_child(cs)
		add_child(_fog_body)
		_fog_body.global_position = _center + Vector3(0, 4.0, 23.3)


func _open_fog_gate() -> void:
	if _fog_body:
		_fog_body.queue_free()
		_fog_body = null
	if not _fog.visible:
		return
	var m: ShaderMaterial = _fog.material_override
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha", v), 0.85, 0.0, 2.0)
	tw.parallel().tween_property(_fog.get_node("FogLight"), "light_energy", 0.0, 2.0)
	tw.tween_callback(func(): _fog.visible = false)


## Partida cargada: este jefe ya fue vencido. No aparece y su arena queda abierta.
func restore_won() -> void:
	_state = "won"
	if boss and is_instance_valid(boss):
		boss.queue_free()
	boss = null
	_open_fog_gate()
