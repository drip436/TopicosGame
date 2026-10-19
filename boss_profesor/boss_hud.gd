extends CanvasLayer
## Interfaz estilo Dark Souls: barra del jefe abajo al centro con nombre y daño acumulado,
## barras de vida/estamina del jugador arriba a la izquierda y letreros
## ("ENEMIGO DERROTADO", "HAS MUERTO"). Abajo a la izquierda, la cruz de equipo
## (armas, hechizo/IA, cafés y bebidas energéticas; ver equip_slots.gd).

const EQUIP := preload("equip_slots.gd")

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
# Punto débil del jefe (barra pequeña bajo la principal)
var _part_label: Label
var _part_bg: ColorRect
var _part_fill: ColorRect
var _part_ratio := 1.0
var _part_visible := false

# Jugador
var _p_box: Control
var _hp_bg: ColorRect
var _hp_trail: ColorRect
var _hp_fill: ColorRect
var _st_bg: ColorRect
var _st_fill: ColorRect
var _flask: Label
var _equip: Control
# Maná (clase Frontend) y habilidad de la clase
var _mana_bg: ColorRect
var _mana_fill: ColorRect
var _ability: Label
var _mana := 0.0
var _mana_max := 0.0
var _drinks := 0
var _status_lbl: Label
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
var _prompt: Label
var _menu_bg: ColorRect
var _menu: Label
var _keys_lbl: Label
var _toast: Label
var _toast_t := 0.0

# Barras de acumulación (veneno, ameba...): efecto -> {box, bg, fill, label}
var _bu := {}
var _bu_data := {}
const BUILDUP_STYLE := {
	"veneno": {"name": "VENENO", "color": Color(0.4, 0.82, 0.18)},
	"ameba": {"name": "AMEBA COME-CEREBROS", "color": Color(0.92, 0.35, 0.68)},
}


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
	_part_bg = _rect(_boss_box, Color(0.05, 0.04, 0.04, 0.85))
	_part_fill = _rect(_boss_box, Color(0.95, 0.55, 0.15))
	_part_label = _label(_boss_box, "", 15, Color(0.95, 0.7, 0.4))
	_part_bg.visible = false
	_part_fill.visible = false

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
	_mana_bg = _rect(_p_box, Color(0.05, 0.04, 0.06, 0.85))
	_mana_fill = _rect(_p_box, Color(0.2, 0.45, 1.0))
	_ability = _label(_p_box, "", 16, Color(0.75, 0.85, 1.0))
	# Cafés, bebidas y habilidad se ven en la cruz de equipo
	_flask.visible = false
	_ability.visible = false
	_status_lbl = _label(_p_box, "", 18, Color(0.95, 0.95, 0.95))
	_menu_bg = _rect(_root, Color(0.02, 0.02, 0.03, 0.8))
	_menu_bg.visible = false
	_menu = _label(_root, "", 19, Color(0.92, 0.9, 0.85))
	_keys_lbl = _label(_root, "", 18, Color(0.95, 0.8, 0.45))
	_keys_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

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

	_equip = EQUIP.new()
	_equip.font = _font
	_equip.visible = false
	_root.add_child(_equip)

	_hint = _label(_root, "", 15, Color(0.85, 0.85, 0.85, 0.8))
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	_prompt = _label(_root, "", 22, Color(0.95, 0.88, 0.7))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast = _label(_root, "", 22, Color(0.95, 0.8, 0.45))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0


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


## Barra del punto débil del jefe (p. ej. "PIERNA IZQUIERDA"). ratio < 0 la oculta.
func set_boss_part(text: String, ratio: float) -> void:
	_part_visible = ratio >= 0.0
	_part_ratio = clampf(ratio, 0.0, 1.0)
	_part_label.text = text if _part_visible else ""
	_part_bg.visible = _part_visible
	_part_fill.visible = _part_visible


func boss_damaged(amount: float) -> void:
	_dmg_acc += amount
	_dmg_timer = 1.6
	_boss_dmg.text = str(int(round(_dmg_acc)))


func set_player(hp: float, hp_max: float, st: float, st_max: float, flasks: int) -> void:
	_p_box.visible = true
	_equip.visible = true
	var r := clampf(hp / maxf(hp_max, 1.0), 0.0, 1.0)
	if r < _p_hp:
		_hurt.color.a = 0.35
	_p_hp = r
	_p_hp_max = hp_max
	_p_st = clampf(st / maxf(st_max, 1.0), 0.0, 1.0)
	_flask.text = "Café  x%d" % flasks
	if _flask_max > 0:
		_flask.text = "Café  %d / %d" % [flasks, _flask_max]
	if _mana_max > 0.0:
		_flask.text += "   ·   Energéticas  x%d" % _drinks


## Barra de maná (azul, bajo la vida). maximum 0 = la clase no usa maná.
func set_mana(current: float, maximum: float, drinks: int) -> void:
	_mana = current
	_mana_max = maximum
	_drinks = drinks


## Texto de la habilidad de la clase (hechizo actual, IA invocada...).
func set_ability(text: String) -> void:
	_ability.text = text


var _flask_max := 0

## Muestra "Café x/máx" en lugar de solo "x".
func set_flask_max(n: int) -> void:
	_flask_max = n


## Barras de acumulación de estados (ver test_player.get_buildups()).
func set_buildups(data: Dictionary) -> void:
	_bu_data = data
	for k in data.keys():
		if not _bu.has(k) and BUILDUP_STYLE.has(k):
			var st: Dictionary = BUILDUP_STYLE[k]
			var bg := _rect(_p_box, Color(0.05, 0.04, 0.04, 0.85))
			var fill := _rect(_p_box, st["color"])
			var lbl := _label(_p_box, st["name"], 15, (st["color"] as Color).lightened(0.3))
			_bu[k] = {"bg": bg, "fill": fill, "label": lbl}
	for k in _bu.keys():
		var vis := data.has(k)
		for n in _bu[k].values():
			(n as CanvasItem).visible = vis


## Menú de texto (armaduras en la hoguera). Texto vacío lo oculta.
func show_menu(text: String) -> void:
	_menu.text = text
	_menu_bg.visible = text != ""


## Piezas de la llave del Aula Magna (arriba a la derecha).
func set_keys(have: int, total: int) -> void:
	_keys_lbl.text = "" if have <= 0 else "Llave del Aula Magna  %d / %d" % [have, total]


## Oculta (o vuelve a mostrar) todo el HUD: diálogos y finales.
func set_hud_visible(v: bool) -> void:
	_root.visible = v


## Texto de interacción en el centro inferior ("E  Descansar").
func show_prompt(text: String) -> void:
	_prompt.text = text


## Mensaje breve (taza recogida, hoguera encendida...).
func toast(text: String, time: float = 3.0) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_t = time


## Estados alterados del jugador ("electrocutado", "quemadura", "atrapado").
func set_status(names: Array) -> void:
	if names.is_empty():
		_status_lbl.text = ""
		return
	var parts: Array[String] = []
	for n in names:
		parts.append(String(n).to_upper())
	_status_lbl.text = "  ·  ".join(parts)
	var c := Color(0.95, 0.95, 0.95)
	if "electrocutado" in names:
		c = Color(0.55, 0.8, 1.0)
	elif "quemadura" in names:
		c = Color(1.0, 0.55, 0.2)
	elif "atrapado" in names:
		c = Color(0.9, 0.3, 0.25)
	_status_lbl.add_theme_color_override("font_color", c)


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
	if _part_visible:
		var pw2 := bw * 0.3
		_part_label.position = Vector2(bx, by + 14)
		_part_label.size = Vector2(bw, 20)
		_part_bg.position = Vector2(bx + bw - pw2 - 2, by + 18)
		_part_bg.size = Vector2(pw2 + 4, 9)
		_part_fill.position = Vector2(bx + bw - pw2, by + 20)
		_part_fill.size = Vector2(pw2 * _part_ratio, 5)
		_part_fill.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.01) if _part_ratio < 0.3 else 1.0
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
	var off := 0.0
	var has_mana := _mana_max > 0.0
	_mana_bg.visible = has_mana
	_mana_fill.visible = has_mana
	if has_mana:
		_mana_bg.position = Vector2(38, 56)
		_mana_bg.size = Vector2(pw * 0.9 + 4, 12)
		_mana_fill.position = Vector2(40, 58)
		_mana_fill.size = Vector2(pw * 0.9 * clampf(_mana / _mana_max, 0.0, 1.0), 8)
		off = 16.0
	_st_bg.position = Vector2(38, 58 + off)
	_st_bg.size = Vector2(pw * 0.8 + 4, 10)
	_st_fill.position = Vector2(40, 60 + off)
	_st_fill.size = Vector2(pw * 0.8 * _p_st, 6)
	_flask.position = Vector2(40, 74 + off)
	_flask.size = Vector2(520, 30)
	_ability.position = Vector2(40, 100 + off)
	_ability.size = Vector2(620, 24)
	if _ability.visible and _ability.text != "":
		off += 22.0
	_status_lbl.position = Vector2(40, 100 + off)
	_status_lbl.size = Vector2(420, 26)
	var row := 0
	for k in BUILDUP_STYLE.keys():
		if not _bu.has(k) or not _bu_data.has(k):
			continue
		var d: Dictionary = _bu_data[k]
		var y := 132.0 + off + row * 34.0
		var bw2 := 200.0
		var b: Dictionary = _bu[k]
		(b["label"] as Label).position = Vector2(40, y - 4)
		(b["label"] as Label).size = Vector2(300, 20)
		var active: float = d["active"]
		(b["label"] as Label).text = BUILDUP_STYLE[k]["name"] + ("  %ds" % ceili(active) if active > 0.0 else "")
		(b["bg"] as ColorRect).position = Vector2(38, y + 16)
		(b["bg"] as ColorRect).size = Vector2(bw2 + 4, 10)
		(b["fill"] as ColorRect).position = Vector2(40, y + 18)
		(b["fill"] as ColorRect).size = Vector2(bw2 * clampf(float(d["value"]), 0.0, 1.0), 6)
		var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012) if active > 0.0 else 1.0
		(b["fill"] as ColorRect).modulate.a = blink
		row += 1
	_menu.position = Vector2(vs.x - 500, vs.y * 0.32)
	_menu.size = Vector2(460, 300)
	_menu_bg.position = _menu.position - Vector2(16, 12)
	_menu_bg.size = Vector2(480, _menu.get_line_count() * 28 + 24)
	_keys_lbl.position = Vector2(vs.x - 440, 34)
	_keys_lbl.size = Vector2(400, 26)
	_prompt.position = Vector2(0, vs.y - 190)
	_prompt.size = Vector2(vs.x, 34)
	_toast.position = Vector2(0, vs.y * 0.22)
	_toast.size = Vector2(vs.x, 34)
	_toast_t -= delta
	if _toast_t <= 0.0:
		_toast.modulate.a = maxf(0.0, _toast.modulate.a - delta * 1.5)

	# Letrero
	_banner_band.position = Vector2(0, vs.y * 0.5 - 75)
	_banner_band.size = Vector2(vs.x, 150)
	_banner_label.position = Vector2(0, vs.y * 0.5 - 60)
	_banner_label.size = Vector2(vs.x, 100)
	_sub_label.position = Vector2(0, vs.y * 0.5 + 38)
	_sub_label.size = Vector2(vs.x, 30)
	# Cruz de equipo abajo a la izquierda (sin tapar la barra del jefe)
	var es := clampf(vs.y / 720.0, 0.85, 1.6)
	es = minf(es, (vs.x * 0.19 - 34.0) / EQUIP.BASE_SIZE.x)
	_equip.scale = Vector2.ONE * es
	_equip.position = Vector2(28, vs.y - 18.0 - EQUIP.BASE_SIZE.y * es)
	_hint.position = Vector2(20, _equip.position.y - 36.0 - 130.0)
	_hint.size = Vector2(600, 130)
