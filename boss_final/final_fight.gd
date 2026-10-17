extends Node3D
## Controlador del enfrentamiento final en el Aula Magna.
## CampusWorld lo crea al iniciar el juego (spawn_final_boss). El portón del
## Aula Magna solo se abre con las 4 piezas de la llave que sueltan los jefes.
##
##  1. Al entrar a la arena, la niebla cierra el túnel y el Rector Eterno habla:
##     te felicita y te pregunta si ya te quieres titular o si prefieres hacer
##     tu residencia como guerrero para liberar a la universidad.
##  2. "Ya me quiero titular"  -> camina hacia ti y te condena a la tesis eterna
##     (final malo: LA TESIS INTERMINABLE).
##  3. "Haré mi residencia"    -> desenfunda la espada y empieza la pelea.
##  4. Al vencerlo suelta la TESIS; al recogerla una voz dice
##     "Has liberado al mundo de la maldición, ahora reclama tu recompensa" y el
##     juego termina (FIN). R para volver a empezar.
##  5. Si mueres: R para reintentar (sin volver a preguntar).

signal battle_started
signal phase_changed(phase: int)
signal boss_defeated
signal player_died
signal game_finished(good_ending: bool)
signal advance
signal chosen(option: int)

const BOSS_SCENE: PackedScene = preload("BossRector.tscn")
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

const SPEAKER := "Rector Eterno"

@export var boss_name: String = "El Rector Eterno, Sínodo de la Última Tesis"
@export var boss_max_health: float = 1600.0

var world: Node
var boss: CharacterBody3D
var hud: CanvasLayer
var player: Node3D
var _own_hud := false
var _fx_root: Node3D
var _minions_root: Node3D
var _fog: MeshInstance3D
var _fog_body: StaticBody3D
var _state := "setup"   # setup | waiting | dialog | choice | fight | won | thesis | ending | lost
var _center := Vector3.ZERO
var _met := false
var _thesis: Node3D
var _typing: Tween

# Interfaz de diálogo y finales
var _ui: CanvasLayer
var _font: SystemFont
var _panel: ColorRect
var _name_lbl: Label
var _text_lbl: Label
var _cont_lbl: Label
var _choices: VBoxContainer
var _fade: ColorRect
var _end_title: Label
var _end_sub: Label
var _end_hint: Label
var _sub_t := 0.0


func _ready() -> void:
	_setup.call_deferred()


func _setup() -> void:
	if world == null and get_tree().current_scene:
		world = get_tree().current_scene.find_child("CampusWorld", true, false)
	_center = WORLD.FINAL
	_fx_root = Node3D.new()
	_fx_root.name = "FX"
	add_child(_fx_root)
	_minions_root = Node3D.new()
	_minions_root.name = "IAs"
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
	_build_ui()
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
	boss.arena_radius = 27.0
	boss.health_changed.connect(func(c, m): hud.set_boss_health(c, m))
	boss.damaged.connect(func(a): hud.boss_damaged(a))
	boss.battle_started.connect(func():
		_state = "fight"
		battle_started.emit())
	boss.phase_changed.connect(func(p):
		phase_changed.emit(p)
		if p == 2:
			hud.show_hint("Se quitó la túnica: cortes de fuego y rayo, lluvia de flechas, IAs y teletransporte.\nRueda para atravesar las ondas · Si te jala, rueda para soltarte", 7.0))
	boss.said.connect(func(text, time): _subtitle(SPEAKER, text, time))
	boss.defeated.connect(_on_boss_defeated)
	boss.place_dormant(_center + Vector3(0, 0.05, -14.0), _center + Vector3(0, 0, 40))


func _physics_process(delta: float) -> void:
	if _own_hud and player and "hp" in player:
		hud.set_player(player.hp, player.max_hp, player.stamina, player.max_stamina, player.flasks)
		if player.has_method("get_status_names"):
			hud.set_status(player.get_status_names())
	if _state == "waiting" and player and is_instance_valid(player) and not player.is_dead:
		var l := player.global_position - _center
		if Vector2(l.x, l.z).length() < 24.0:
			_begin_encounter()
	if _state == "thesis" and _thesis and is_instance_valid(_thesis) and player:
		_thesis.get_child(0).rotation.y += delta * 1.2
		var d := Vector2(_thesis.global_position.x - player.global_position.x, _thesis.global_position.z - player.global_position.z).length()
		if d < 1.6:
			_take_thesis()
	if _sub_t > 0.0:
		_sub_t -= delta
		if _sub_t <= 0.0 and _state in ["fight", "won", "lost"]:
			_panel.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E, KEY_SPACE, KEY_ENTER:
				if _state == "dialog":
					_on_advance()
					get_viewport().set_input_as_handled()
			KEY_1, KEY_KP_1:
				if _state == "choice":
					chosen.emit(1)
					get_viewport().set_input_as_handled()
			KEY_2, KEY_KP_2:
				if _state == "choice":
					chosen.emit(2)
					get_viewport().set_input_as_handled()
			KEY_R:
				if _state == "ending":
					get_tree().reload_current_scene()
				elif _state == "lost":
					_retry()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _state == "dialog":
		_on_advance()


func _on_advance() -> void:
	if _typing and _typing.is_running():
		_typing.kill()
		_text_lbl.visible_ratio = 1.0
		return
	advance.emit()


# ======================================================================
#  Encuentro y diálogo
# ======================================================================

func _lock(on: bool) -> void:
	if player and "input_locked" in player:
		player.input_locked = on
	if hud and hud.has_method("set_hud_visible"):
		hud.set_hud_visible(not on)


func _begin_encounter() -> void:
	_state = "dialog"
	_close_fog_gate()
	_lock(true)
	boss.start_talk()
	boss.face_target()
	if _met:
		await _say(SPEAKER, "¿Otra vez tú? Bien… tu residencia continúa.")
		_start_fight()
		return
	_met = true
	await get_tree().create_timer(0.8).timeout
	boss.gesture("open_arms")
	await _say(SPEAKER, "Vaya… lograste venir hasta aquí.")
	await _say(SPEAKER, "Venciste a los guardianes de esta universidad y reuniste la llave. Te felicito: muy pocos llegan tan lejos.")
	boss.gesture("talk")
	await _say(SPEAKER, "Has demostrado que eres digno de titularte de esta universidad.")
	boss.gesture("point")
	await _say(SPEAKER, "Pero antes dime… ¿ya te quieres titular de la carrera?\n¿O prefieres esperarte a hacer tu residencia como guerrero para liberar a la universidad?", false)
	var option: int = await _ask(["Ya me quiero titular.", "Esperaré: haré mi residencia como guerrero."])
	if option == 1:
		await _bad_ending()
	else:
		await _say(SPEAKER, "Entonces… demuéstralo.")
		_start_fight()


## Muestra una línea con efecto de máquina de escribir. Si wait es true, espera a E/clic.
func _say(speaker: String, text: String, wait := true) -> void:
	_panel.visible = true
	_name_lbl.text = speaker
	_text_lbl.text = text
	_text_lbl.visible_ratio = 0.0
	_cont_lbl.visible = wait
	if _typing:
		_typing.kill()
	var dur := maxf(0.4, text.length() * 0.028)
	_typing = create_tween()
	_typing.tween_property(_text_lbl, "visible_ratio", 1.0, dur)
	if wait:
		await advance
	else:
		# Por tiempo (saltar el texto con E no debe congelar el diálogo)
		await get_tree().create_timer(dur).timeout
		_text_lbl.visible_ratio = 1.0


func _subtitle(speaker: String, text: String, time: float) -> void:
	_panel.visible = true
	_cont_lbl.visible = false
	_name_lbl.text = speaker
	_text_lbl.text = text
	_text_lbl.visible_ratio = 0.0
	if _typing:
		_typing.kill()
	_typing = create_tween()
	_typing.tween_property(_text_lbl, "visible_ratio", 1.0, maxf(0.3, text.length() * 0.025))
	_sub_t = time


func _ask(options: Array) -> int:
	_state = "choice"
	for c in _choices.get_children():
		c.queue_free()
	for i in options.size():
		var b := Button.new()
		b.text = "  %d.  %s" % [i + 1, options[i]]
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 46)
		var n := i + 1
		b.pressed.connect(func(): chosen.emit(n))
		_choices.add_child(b)
	_choices.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var option: int = await chosen
	_choices.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_state = "dialog"
	return option


func _start_fight() -> void:
	_panel.visible = false
	_lock(false)
	_state = "intro"
	hud.show_boss(boss_name)
	hud.set_boss_health(boss.health, boss.max_health)
	hud.show_hint("Pelea con mucha destreza: esquiva tus golpes y contraataca. Si te alejas, te dispara con su revólver.", 8.0)
	boss.begin_fight()


# ======================================================================
#  Final malo: la tesis interminable
# ======================================================================

func _bad_ending() -> void:
	boss.walk_to_player()
	await _say(SPEAKER, "Muy bien… has escogido el buen camino.")
	await _say(SPEAKER, "El camino que cambiará el mundo.")
	await _say(SPEAKER, "El camino donde harás la tesis que cambiará el mundo…")
	# Papeles y hojas empiezan a arremolinarse alrededor del jugador
	for i in 6:
		LFX.paper_burst(_fx_root, player.global_position + Vector3(0, 1.0 + i * 0.3, 0), 18)
	await _say(SPEAKER, "…una tesis que jamás podrás terminar.")
	_panel.visible = false
	for i in 8:
		LFX.paper_burst(_fx_root, player.global_position + Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)), 24)
		await get_tree().create_timer(0.2).timeout
	_show_ending(false)


# ======================================================================
#  Victoria, tesis y final
# ======================================================================

func _on_boss_defeated() -> void:
	_state = "won"
	hud.hide_boss(2.0)
	await get_tree().create_timer(3.2).timeout
	hud.show_banner("ENEMIGO DERROTADO", Color(0.92, 0.78, 0.38), "", 4.0)
	_open_fog_gate()
	boss.collision_layer = 0
	var p := boss.global_position + (-boss.global_basis.z) * 1.6
	p.y = _center.y
	_spawn_thesis(p)
	boss_defeated.emit()
	await get_tree().create_timer(2.5).timeout
	if _state == "thesis" and hud.has_method("toast"):
		hud.toast("El Rector dejó caer su TESIS. Recógela.", 6.0)


func _spawn_thesis(p: Vector3) -> void:
	_thesis = Node3D.new()
	_thesis.name = "Tesis"
	_fx_root.add_child(_thesis)
	_thesis.global_position = p
	var book := Node3D.new()
	book.position = Vector3(0, 1.1, 0)
	_thesis.add_child(book)
	var cover := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.56, 0.1)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.45, 0.06, 0.06)
	cm.roughness = 0.6
	bm.material = cm
	cover.mesh = bm
	book.add_child(cover)
	var pages := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.4, 0.54, 0.085)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.95, 0.92, 0.8)
	pm.material = pmat
	pages.mesh = pm
	pages.position = Vector3(0.012, 0, 0)
	book.add_child(pages)
	for face: float in [0.0, 180.0]:
		var l := Label3D.new()
		l.text = "TESIS\n\nLa liberación\nde la universidad"
		l.font_size = 40
		l.pixel_size = 0.0028
		l.modulate = Color(1.0, 0.85, 0.4)
		l.outline_size = 0
		l.position = Vector3(0, 0.02, -0.052 if face == 0.0 else 0.052)
		l.rotation_degrees = Vector3(0, face, 0)
		book.add_child(l)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = 2.0
	light.omni_range = 6.0
	light.position = Vector3(0, 1.2, 0)
	_thesis.add_child(light)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.5
	cyl.height = 8.0
	cyl.material = LFX.emissive(Color(1.0, 0.85, 0.45), 1.0, 0.12)
	beam.mesh = cyl
	beam.position = Vector3(0, 4.0, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_thesis.add_child(beam)
	LFX.puff(_fx_root, p + Vector3(0, 1.1, 0), Color(3.0, 2.4, 1.2, 1), 50, 0.2, 4.0, 0.0)
	_state = "thesis"


func _take_thesis() -> void:
	_state = "dialog"
	LFX.puff(_fx_root, _thesis.global_position + Vector3(0, 1.1, 0), Color(3.0, 2.4, 1.2, 1), 60, 0.25, 5.0, -2.0)
	_thesis.queue_free()
	_lock(true)
	if player and player.has_method("add_camera_shake"):
		player.add_camera_shake(0.2)
	# El cielo se despeja por completo
	var weather := get_tree().current_scene.find_child("Weather", true, false)
	if weather and weather.has_method("calm"):
		weather.calm(6.0, 0.0)
	await get_tree().create_timer(1.0).timeout
	_cont_lbl.visible = false
	await _say("Una voz", "Has liberado al mundo de la maldición…", false)
	await get_tree().create_timer(1.6).timeout
	await _say("Una voz", "Has liberado al mundo de la maldición…\nahora reclama tu recompensa.", false)
	await get_tree().create_timer(3.0).timeout
	_panel.visible = false
	_show_ending(true)


func _show_ending(good: bool) -> void:
	_state = "ending"
	_lock(true)
	_panel.visible = false
	_fade.visible = true
	_fade.color = Color(1.0, 0.96, 0.86, 0.0) if good else Color(0, 0, 0, 0.0)
	var col := Color(0.3, 0.22, 0.1) if good else Color(0.85, 0.2, 0.15)
	_end_title.add_theme_color_override("font_color", col)
	_end_sub.add_theme_color_override("font_color", col.darkened(0.1) if good else Color(0.8, 0.78, 0.75))
	_end_hint.add_theme_color_override("font_color", Color(0.4, 0.35, 0.3) if good else Color(0.6, 0.6, 0.6))
	if good:
		_end_title.text = "FIN"
		_end_sub.text = "Liberaste a la universidad de la maldición y tu tesis está completa.\nTe titulaste como guerrero.\n\nGracias por jugar."
	else:
		_end_title.text = "FINAL: LA TESIS INTERMINABLE"
		_end_sub.text = "Te titulaste… o eso creíste.\nPasan los años y sigues corrigiendo el capítulo uno.\nLa universidad sigue maldita."
	_end_hint.text = "Presiona R para volver a empezar"
	for l in [_end_title, _end_sub, _end_hint]:
		(l as Label).modulate.a = 0.0
		(l as Label).visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 2.5)
	tw.tween_property(_end_title, "modulate:a", 1.0, 1.5)
	tw.tween_property(_end_sub, "modulate:a", 1.0, 1.5)
	tw.tween_property(_end_hint, "modulate:a", 1.0, 1.0)
	game_finished.emit(good)


# ======================================================================
#  Muerte y reintento
# ======================================================================

func _on_player_died() -> void:
	if _state != "fight" and _state != "intro":
		return
	_state = "lost"
	if boss:
		boss.target = null
	await get_tree().create_timer(1.2).timeout
	hud.show_banner("HAS MUERTO", Color(0.62, 0.05, 0.04), "Presiona R para reintentar", 0.0)
	player_died.emit()


func _retry() -> void:
	_state = "setup"
	_panel.visible = false
	hud.hide_boss(0.0)
	var banner := hud.get("_banner") as Control
	if banner:
		banner.modulate.a = 0.0
	if boss:
		boss.clear_minions()
		boss.queue_free()
	for c in _fx_root.get_children():
		c.queue_free()
	for c in _minions_root.get_children():
		c.queue_free()
	_open_fog_gate()
	var pos := _center + Vector3(0, 0.2, 55)
	var yaw := 0.0
	var life := get_tree().current_scene.find_child("VidaDelCampus", true, false) if get_tree().current_scene else null
	if life:
		var cp = life.get("checkpoint")
		if cp and is_instance_valid(cp) and cp.has_method("respawn_point"):
			pos = cp.respawn_point()
			var to: Vector3 = cp.global_position - pos
			yaw = atan2(-to.x, -to.z)
	if player and player.has_method("revive"):
		player.revive(pos, yaw)
	await get_tree().physics_frame
	_spawn_boss()
	_state = "waiting"


# ======================================================================
#  Interfaz
# ======================================================================

func _label(parent: Control, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_ui() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Cormorant Garamond", "Garamond", "Georgia", "Times New Roman", "serif"])
	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	root.add_child(_fade)
	_panel = ColorRect.new()
	_panel.color = Color(0.02, 0.02, 0.03, 0.82)
	_panel.anchor_left = 0.12
	_panel.anchor_right = 0.88
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -240
	_panel.offset_bottom = -40
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	root.add_child(_panel)
	var line := ColorRect.new()
	line.color = Color(0.85, 0.7, 0.35, 0.8)
	line.anchor_right = 1.0
	line.offset_bottom = 2
	_panel.add_child(line)
	_name_lbl = _label(_panel, 26, Color(0.95, 0.78, 0.4))
	_name_lbl.position = Vector2(28, 16)
	_text_lbl = _label(_panel, 25, Color(0.93, 0.92, 0.88))
	_text_lbl.anchor_right = 1.0
	_text_lbl.offset_left = 28
	_text_lbl.offset_right = -28
	_text_lbl.offset_top = 58
	_text_lbl.offset_bottom = 170
	_text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cont_lbl = _label(_panel, 16, Color(0.7, 0.7, 0.7))
	_cont_lbl.text = "E / Clic  ·  continuar"
	_cont_lbl.anchor_left = 1.0
	_cont_lbl.anchor_right = 1.0
	_cont_lbl.anchor_top = 1.0
	_cont_lbl.anchor_bottom = 1.0
	_cont_lbl.offset_left = -260
	_cont_lbl.offset_right = -24
	_cont_lbl.offset_top = -34
	_cont_lbl.offset_bottom = -8
	_cont_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_choices = VBoxContainer.new()
	_choices.anchor_left = 0.3
	_choices.anchor_right = 0.7
	_choices.anchor_top = 0.42
	_choices.anchor_bottom = 0.62
	_choices.add_theme_constant_override("separation", 14)
	_choices.visible = false
	root.add_child(_choices)
	_end_title = _label(root, 64, Color.WHITE)
	_end_title.anchor_right = 1.0
	_end_title.anchor_top = 0.3
	_end_title.anchor_bottom = 0.3
	_end_title.offset_bottom = 90
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_sub = _label(root, 26, Color.WHITE)
	_end_sub.anchor_right = 1.0
	_end_sub.anchor_top = 0.45
	_end_sub.anchor_bottom = 0.45
	_end_sub.offset_bottom = 200
	_end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_hint = _label(root, 18, Color.WHITE)
	_end_hint.anchor_right = 1.0
	_end_hint.anchor_top = 0.85
	_end_hint.anchor_bottom = 0.85
	_end_hint.offset_bottom = 30
	_end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for l in [_end_title, _end_sub, _end_hint]:
		(l as Label).visible = false


# ======================================================================
#  Niebla del túnel
# ======================================================================

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
	q.size = Vector2(13.4, 9.4)
	_fog = MeshInstance3D.new()
	_fog.mesh = q
	_fog.material_override = m
	_fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog.visible = false
	add_child(_fog)
	_fog.global_position = _center + Vector3(0, 4.7, 34.2)
	var light := OmniLight3D.new()
	light.name = "FogLight"
	light.light_color = Color(0.85, 0.88, 1.0)
	light.light_energy = 0.0
	light.omni_range = 10.0
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
		bx.size = Vector3(13.6, 9.6, 0.8)
		cs.shape = bx
		_fog_body.add_child(cs)
		add_child(_fog_body)
		_fog_body.global_position = _center + Vector3(0, 4.8, 34.4)


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
