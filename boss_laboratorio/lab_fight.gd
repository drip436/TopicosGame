extends Node3D
## Controlador de la pelea del cuarto jefe en el Laboratorio de Biogenética.
## CampusWorld lo crea al iniciar el juego (spawn_lab_boss); no hay que tocar
## main.tscn. Hace esto:
##  1. El Dr. Kessler trabaja en su mesa frente a la cápsula Ω-01, de espaldas.
##  2. Al entrar el jugador, la puerta se cierra con niebla, voltea y se ríe.
##  3. Fase 2 (se inyecta el suero): luces verdes de contaminación.
##  4. Al ganar: "ENEMIGO DERROTADO", mueren sus mutantes y se abre el
##     Edificio de Posgrado (y el Aula Magna si ya cayeron los otros jefes).
##  5. Al morir: "HAS MUERTO"; con R reintentas (en la última hoguera, o en
##     la entrada del edificio si no hay hogueras).

signal battle_started
signal phase_changed(phase: int)
signal boss_defeated
signal player_died

const BOSS_SCENE: PackedScene = preload("BossDoctor.tscn")
const LFX := preload("res://boss_bibliotecario/library_fx.gd")
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

@export var boss_name: String = "Doctor Viktor Kessler, el Paciente Cero"
@export var boss_max_health: float = 1450.0

var world: Node
var boss: CharacterBody3D
var hud: CanvasLayer
var player: Node3D
var _own_hud := false
var _fx_root: Node3D
var _minions_root: Node3D
var _alarm_root: Node3D
var _alarms: Array[OmniLight3D] = []
var _fog: MeshInstance3D
var _fog_body: StaticBody3D
var _state := "setup"   # setup | waiting | intro | fight | won | lost
var _center := Vector3.ZERO
var _t := 0.0


func _ready() -> void:
	_setup.call_deferred()


func _setup() -> void:
	if world == null and get_tree().current_scene:
		world = get_tree().current_scene.find_child("CampusWorld", true, false)
	_center = WORLD.LAB
	_fx_root = Node3D.new()
	_fx_root.name = "FX"
	add_child(_fx_root)
	_minions_root = Node3D.new()
	_minions_root.name = "Mutantes"
	add_child(_minions_root)
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
	_build_fog_gate()
	_spawn_boss()
	_state = "waiting"


func _spawn_boss() -> void:
	boss = BOSS_SCENE.instantiate() as CharacterBody3D
	boss.set("boss_name", boss_name)
	boss.set("max_health", boss_max_health)
	add_child(boss)
	boss.fx_parent = _fx_root
	boss.minion_parent = _minions_root
	boss.target = player
	boss.arena_center = _center
	boss.arena_radius = 18.5
	boss.health_changed.connect(func(c, m): hud.set_boss_health(c, m))
	boss.damaged.connect(func(a): hud.boss_damaged(a))
	boss.battle_started.connect(func():
		_state = "fight"
		battle_started.emit())
	boss.phase_changed.connect(_on_phase)
	boss.defeated.connect(_on_boss_defeated)
	boss.place_dormant(_center + Vector3(0, 0.05, -13.0), _center + Vector3(0, 0, -20))


func _physics_process(delta: float) -> void:
	_t += delta
	if _own_hud and player and "hp" in player:
		hud.set_player(player.hp, player.max_hp, player.stamina, player.max_stamina, player.flasks)
		if player.has_method("get_status_names"):
			hud.set_status(player.get_status_names())
		if player.has_method("get_buildups") and hud.has_method("set_buildups"):
			hud.set_buildups(player.get_buildups())
			hud.set_flask_max(player.get_max_flasks())
	if _state == "waiting" and player and is_instance_valid(player):
		var l := player.global_position - _center
		if Vector2(l.x, l.z).length() < 22.0:
			_start()
	# Luces verdes de contaminación en la fase 2
	for i in _alarms.size():
		var a := _alarms[i]
		if is_instance_valid(a):
			a.light_energy = 1.2 + 1.0 * sin(_t * 2.5 + i * 1.3)


func _start() -> void:
	_state = "intro"
	_close_fog_gate()
	hud.show_boss(boss_name)
	hud.set_boss_health(boss.health, boss.max_health)
	hud.show_hint("Es escurridizo: se esconde detrás de sus mutantes y huye si te acercas.\nInterrúmpelo cuando experimente (se cura) · Los frascos y charcos llenan la barra de VENENO", 10.0)
	boss.begin_intro()


func _unhandled_input(event: InputEvent) -> void:
	if _state == "lost" and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_retry()


func _on_phase(p: int) -> void:
	if p == 2:
		_alarm_root = Node3D.new()
		_alarm_root.name = "Alarmas"
		add_child(_alarm_root)
		for lp in [Vector3(-14, 7, -10), Vector3(14, 7, -10), Vector3(-14, 7, 10), Vector3(14, 7, 10), Vector3(0, 9, 0)]:
			var l := OmniLight3D.new()
			l.light_color = Color(0.45, 1.0, 0.25)
			l.omni_range = 16.0
			l.light_energy = 0.0
			_alarm_root.add_child(l)
			l.global_position = _center + lp
			_alarms.append(l)
		LFX.embers(_alarm_root, _center + Vector3(0, 3, 0), Vector3(18, 3, 18), 90)
		if player and player.has_method("add_camera_shake"):
			player.add_camera_shake(0.4)
		hud.show_hint("Se inyectó su suero: ahora es un mutante gigante. Si te agarra, te estampa contra la pared.", 6.0)
	phase_changed.emit(p)


func _clear_alarms() -> void:
	_alarms.clear()
	if _alarm_root:
		_alarm_root.queue_free()
		_alarm_root = null


func _on_boss_defeated() -> void:
	_state = "won"
	hud.hide_boss(2.0)
	await get_tree().create_timer(2.2).timeout
	hud.show_banner("ENEMIGO DERROTADO", Color(0.92, 0.78, 0.38), "", 5.0)
	await get_tree().create_timer(3.0).timeout
	_open_fog_gate()
	for a in _alarms:
		if is_instance_valid(a):
			var tw := a.create_tween()
			tw.tween_property(a, "light_energy", 0.0, 2.0)
	_alarms.clear()
	if world and world.has_method("register_boss_defeated"):
		world.register_boss_defeated("laboratorio")
	boss_defeated.emit()


func _on_player_died() -> void:
	if _state != "fight" and _state != "intro":
		return
	_state = "lost"
	if boss:
		boss.target = null
	for m in _minions_root.get_children():
		m.set("target", null)
	await get_tree().create_timer(1.2).timeout
	hud.show_banner("HAS MUERTO", Color(0.62, 0.05, 0.04), "Presiona R para reintentar", 0.0)
	player_died.emit()


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
	for c in _minions_root.get_children():
		c.queue_free()
	_clear_alarms()
	_open_fog_gate()
	var pos := _center + Vector3(0, 0.2, 33)
	var yaw := 0.0
	var life := get_tree().current_scene.find_child("VidaDelCampus", true, false) if get_tree().current_scene else null
	if life:
		var cp = life.get("checkpoint")
		if cp and is_instance_valid(cp) and cp.has_method("respawn_point"):
			pos = cp.respawn_point()
			var to: Vector3 = cp.global_position - pos
			yaw = atan2(-to.x, -to.z)
		if life.has_method("respawn_enemies"):
			life.respawn_enemies()
	if player and player.has_method("revive"):
		player.revive(pos, yaw)
	await get_tree().physics_frame
	_spawn_boss()
	_state = "waiting"


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
	q.size = Vector2(6.4, 7.8)
	_fog = MeshInstance3D.new()
	_fog.mesh = q
	_fog.material_override = m
	_fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog.visible = false
	add_child(_fog)
	_fog.global_position = _center + Vector3(0, 3.9, 26.4)
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
		bx.size = Vector3(7.0, 8.0, 0.8)
		cs.shape = bx
		_fog_body.add_child(cs)
		add_child(_fog_body)
		_fog_body.global_position = _center + Vector3(0, 4.0, 26.6)


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
