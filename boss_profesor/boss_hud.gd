extends CanvasLayer
## Interfaz estilo Dark Souls: barra del jefe abajo al centro con nombre y daño acumulado,
## barras de vida/estamina del jugador arriba a la izquierda y letreros
## ("ENEMIGO DERROTADO", "HAS MUERTO").

var _font: SystemFont
var _root: Control

# Jefe
var _boss_box: Control
var _boss_name: Label
var _boss_dmg: Label
var _boss_bg: ColorRect
var _boss_trail: ColorRect
var _boss_fill: ColorRect
var _boss_ratio := 1.0
var _trail_ratio := 1.0
var _trail_wait := 0.0
var _dmg_acc := 0.0
var _dmg_timer := 0.0

# Jugador
var _p_box: Control
var _hp_bg: ColorRect
var _hp_trail: ColorRect
var _hp_fill: ColorRect
var _st_bg: ColorRect
var _st_fill: ColorRect
var _flask: Label
var _p_hp := 1.0
var _p_trail := 1.0
var _p_st := 1.0
var _p_hp_max := 100.0

# Letrero
var _banner: Control
var _banner_band: TextureRect
var _banner_label: Label
var _sub_label: Label
var _hint: Label
var _hurt: ColorRect


func _ready() -> void:
	layer = 10
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Optimus Princeps", "Cormorant Garamond", "Garamond", "Georgia", "Times New Roman", "serif"])
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_hurt = ColorRect.new()
	_hurt.color = Color(0.6, 0.0, 0.0, 0.0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hurt)

	# --- Barra del jefe
	_boss_box = Control.new()
	_boss_box.modulate.a = 0.0
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_boss_box)
	_boss_name = _label(_boss_box, "", 26, Color(0.92, 0.9, 0.84))
	_boss_dmg = _label(_boss_box, "", 22, Color(0.95, 0.95, 0.95))
	_boss_dmg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boss_bg = _rect(_boss_box, Color(0.05, 0.04, 0.04, 0.85))
	_boss_trail = _rect(_boss_box, Color(0.85, 0.7, 0.35))
	_boss_fill = _rect(_boss_box, Color(0.55, 0.06, 0.05))

	# --- Jugador
	_p_box = Control.new()
	_p_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_p_box.visible = false
	_root.add_child(_p_box)
	_hp_bg = _rect(_p_box, Color(0.05, 0.04, 0.04, 0.85))
	_hp_trail = _rect(_p_box, Color(0.85, 0.7, 0.35))
	_hp_fill = _rect(_p_box, Color(0.62, 0.08, 0.06))
	_st_bg = _rect(_p_box, Color(0.05, 0.04, 0.04, 0.85))
	_st_fill = _rect(_p_box, Color(0.18, 0.5, 0.2))
	_flask = _label(_p_box, "", 20, Color(0.95, 0.75, 0.35))

	# --- Letrero
	_banner = Control.new()
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.75), Color(0, 0, 0, 0.75), Color(0, 0, 0, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(0, 0.5)
	gt.fill_from = Vector2(0.5, 0)
	gt.fill_to = Vector2(0.5, 1)
	_banner_band = TextureRect.new()
	_banner_band.texture = gt
	_banner_band.stretch_mode = TextureRect.STRETCH_SCALE
	_banner_band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner.add_child(_banner_band)
	_banner_label = _label(_banner, "", 78, Color(0.9, 0.75, 0.35))
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_label = _label(_banner, "", 22, Color(0.8, 0.8, 0.8))
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_hint = _label(_root, "", 15, Color(0.85, 0.85, 0.85, 0.8))
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


func _label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _rect(parent: Control, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


# ------------------------------------------------------------------ API

func show_boss(name: String) -> void:
	_boss_name.text = name
	var tw := create_tween()
	tw.tween_property(_boss_box, "modulate:a", 1.0, 1.2)


func hide_boss(delay: float = 0.0) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(_boss_box, "modulate:a", 0.0, 1.5)


func set_boss_health(current: float, maximum: float) -> void:
	var r := clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	if r < _boss_ratio:
		_trail_wait = 0.8
	_boss_ratio = r


func boss_damaged(amount: float) -> void:
	_dmg_acc += amount
	_dmg_timer = 1.6
	_boss_dmg.text = str(int(round(_dmg_acc)))


func set_player(hp: float, hp_max: float, st: float, st_max: float, flasks: int) -> void:
	_p_box.visible = true
	var r := clampf(hp / maxf(hp_max, 1.0), 0.0, 1.0)
	if r < _p_hp:
		_hurt.color.a = 0.35
	_p_hp = r
	_p_hp_max = hp_max
	_p_st = clampf(st / maxf(st_max, 1.0), 0.0, 1.0)
	_flask.text = "Café  x%d" % flasks


func show_banner(text: String, color: Color, sub: String = "", hold: float = 4.0) -> void:
	_banner_label.text = text
	_banner_label.add_theme_color_override("font_color", color)
	_sub_label.text = sub
	_banner.scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 1.4)
	if hold > 0.0:
		tw.tween_interval(hold)
		tw.tween_property(_banner, "modulate:a", 0.0, 1.5)


func show_hint(text: String, time: float = 14.0) -> void:
	_hint.text = text
	_hint.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(time)
	tw.tween_property(_hint, "modulate:a", 0.0, 2.0)


# --------------------------------------------------------------- layout

func _process(delta: float) -> void:
	var vs := _root.get_viewport_rect().size
	_hurt.size = vs
	_hurt.color.a = maxf(0.0, _hurt.color.a - delta * 1.2)

	# Barra del jefe
	var bw := vs.x * 0.62
	var bx := (vs.x - bw) * 0.5
	var by := vs.y - 70.0
	_boss_name.position = Vector2(bx, by - 38)
	_boss_name.size = Vector2(bw, 34)
	_boss_dmg.position = Vector2(bx, by - 36)
	_boss_dmg.size = Vector2(bw, 34)
	_boss_bg.position = Vector2(bx - 2, by - 2)
	_boss_bg.size = Vector2(bw + 4, 14)
	_trail_wait -= delta
	if _trail_wait <= 0.0:
		_trail_ratio = move_toward(_trail_ratio, _boss_ratio, delta * 0.35)
	_trail_ratio = maxf(_trail_ratio, _boss_ratio)
	_boss_trail.position = Vector2(bx, by)
	_boss_trail.size = Vector2(bw * _trail_ratio, 10)
	_boss_fill.position = Vector2(bx, by)
	_boss_fill.size = Vector2(bw * _boss_ratio, 10)
	_dmg_timer -= delta
	if _dmg_timer <= 0.0 and _dmg_acc > 0.0:
		_dmg_acc = 0.0
		_boss_dmg.text = ""

	# Jugador
	var pw := clampf(_p_hp_max * 3.2, 200.0, 520.0)
	_hp_bg.position = Vector2(38, 38)
	_hp_bg.size = Vector2(pw + 4, 14)
	_p_trail = move_toward(_p_trail, _p_hp, delta * 0.4)
	_p_trail = maxf(_p_trail, _p_hp)
	_hp_trail.position = Vector2(40, 40)
	_hp_trail.size = Vector2(pw * _p_trail, 10)
	_hp_fill.position = Vector2(40, 40)
	_hp_fill.size = Vector2(pw * _p_hp, 10)
	_st_bg.position = Vector2(38, 58)
	_st_bg.size = Vector2(pw * 0.8 + 4, 10)
	_st_fill.position = Vector2(40, 60)
	_st_fill.size = Vector2(pw * 0.8 * _p_st, 6)
	_flask.position = Vector2(40, 74)
	_flask.size = Vector2(200, 30)

	# Letrero
	_banner_band.position = Vector2(0, vs.y * 0.5 - 75)
	_banner_band.size = Vector2(vs.x, 150)
	_banner_label.position = Vector2(0, vs.y * 0.5 - 60)
	_banner_label.size = Vector2(vs.x, 100)
	_sub_label.position = Vector2(0, vs.y * 0.5 + 38)
	_sub_label.size = Vector2(vs.x, 30)
	_hint.position = Vector2(20, vs.y - 150)
	_hint.size = Vector2(600, 130)
