extends Control
## Cruz de equipo estilo Dark Souls (abajo a la izquierda):
##   arriba     hechizo / IA / habilidad de la clase (Q cambia)
##   izquierda  mano izquierda (escudo, bastón, arco, tableta)
##   derecha    mano derecha (espada, estoque, mazo, lanza)
##   abajo      café (cura, R) con las tazas restantes
##   pequeña    bebidas energéticas (maná, G) — solo Frontend
## Lee el estado del jugador (grupo "player") y de su kit de clase (jugador/class_kit.gd)
## cada cuadro; si el jugador no tiene kit muestra la espada genérica.
## Los íconos se dibujan con primitivas (no hay texturas).

const S := 58.0    # lado de una ranura
const G := 4.0     # separación
const GOLD := Color(0.95, 0.78, 0.4)
const BORDER := Color(0.42, 0.36, 0.25)

## Tamaño base (sin escalar) del panel, incluida la etiqueta inferior.
const BASE_SIZE := Vector2(S * 3.0 + G * 2.0, S * 2.0 + G + 44.0)

var font: Font

var _player: Node
var _kit: Node
# ranura -> {icon, color, caption, count, key, dim, active}
var _slots := {}
var _top_text := ""
var _bottom_text := ""
var _flash := {}
var _last := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = BASE_SIZE


func _process(delta: float) -> void:
	_find_player()
	_read_state()
	for k in _flash.keys():
		_flash[k] = maxf(0.0, float(_flash[k]) - delta * 2.5)
	queue_redraw()


func _find_player() -> void:
	if is_instance_valid(_player):
		if _kit == null or not is_instance_valid(_kit):
			_kit = _find_kit(_player)
		return
	_player = get_tree().get_first_node_in_group("player")
	_kit = _find_kit(_player) if _player else null


func _find_kit(p: Node) -> Node:
	var k := p.get_node_or_null("KitDeClase")
	if k:
		return k
	if "kit" in p and p.get("kit") is Node:
		return p.get("kit")
	for c in p.get_children():
		if c.has_method("ability_text") and "class_id" in c:
			return c
	return null


func _slot(icon: String, color := Color.WHITE, caption := "", count := -1, key := "", dim := false, active := false) -> Dictionary:
	return {"icon": icon, "color": color, "caption": caption, "count": count, "key": key, "dim": dim, "active": active}


func _read_state() -> void:
	_slots.clear()
	_top_text = ""
	var flasks := 0
	var max_flasks := 0
	if is_instance_valid(_player):
		flasks = int(_player.get("flasks")) if "flasks" in _player else 0
		max_flasks = int(_player.call("get_max_flasks")) if _player.has_method("get_max_flasks") else flasks
	_slots["bottom"] = _slot("cafe", Color(0.85, 0.55, 0.3), "", flasks, "R", flasks <= 0)
	_bottom_text = "Café  %d / %d" % [flasks, max_flasks]

	var cls := "" if _kit == null else String(_kit.get("class_id"))
	var consts: Dictionary = _kit.get_script().get_script_constant_map() if _kit else {}
	match cls:
		"frontend":
			var spells: Array = consts.get("SPELLS", [])
			var idx := int(_kit.get("spell_idx"))
			if idx < spells.size():
				var sp: Dictionary = spells[idx]
				var mana := float(_kit.get("mana"))
				var cost := float(sp["cost"])
				_slots["top"] = _slot("spell_" + String(sp["id"]), sp["color"], "", -1, "Q", mana < cost)
				_top_text = "%s  ·  %d maná" % [sp["name"], int(cost)]
			_slots["right"] = _slot("estoque", Color(0.85, 0.87, 0.92), "Estoque")
			_slots["left"] = _slot("baston", Color(0.35, 0.8, 1.0), "Bastón")
			var drinks := int(_kit.get("drinks"))
			_slots["small"] = _slot("bebida", Color(0.35, 0.85, 1.0), "", drinks, "G", drinks <= 0)
		"backend":
			var low := is_instance_valid(_player) and float(_player.get("stamina")) < 35.0
			_slots["top"] = _slot("sismico", Color(1.0, 0.7, 0.3), "", -1, "", low)
			_top_text = "Golpe sísmico  ·  35 estamina"
			_slots["right"] = _slot("mazo", Color(0.7, 0.72, 0.78), "Mazo")
			_slots["left"] = _slot("", Color.WHITE, "Dos manos")
		"ai":
			var stands: Array = consts.get("STANDS", [])
			var idx := int(_kit.get("stand_idx"))
			var info := {}
			var st_script = consts.get("STAND")
			if st_script and idx < stands.size():
				info = (st_script as Script).get_script_constant_map().get("INFO", {}).get(stands[idx], {})
			var nm := String(info.get("name", "IA"))
			_slots["top"] = _slot("ia_" + (String(stands[idx]) if idx < stands.size() else ""), info.get("color", Color(0.6, 0.9, 1.0)), "", -1, "Q")
			_top_text = "IA: %s" % nm
			_slots["right"] = _slot("ia_ataque", info.get("color", Color(0.6, 0.9, 1.0)), nm)
			_slots["left"] = _slot("tableta", Color(0.5, 0.9, 1.0), "Tableta")
		"data":
			_slots["top"] = _slot("flechas", Color(1.0, 0.9, 0.7))
			_top_text = "Flechas  ·  ∞"
			_slots["right"] = _slot("lanza", Color(0.8, 0.82, 0.86), "Lanza")
			_slots["left"] = _slot("arco", Color(0.75, 0.55, 0.32), "Arco")
		"cyber":
			var blocking := bool(_kit.get("blocking"))
			_slots["top"] = _slot("")
			_top_text = "CUBRIÉNDOTE" if blocking else ""
			_slots["right"] = _slot("espada", Color(0.85, 0.87, 0.92), "Espada")
			_slots["left"] = _slot("escudo", Color(0.3, 0.45, 0.7), "Escudo", -1, "", false, blocking)
		_:
			_slots["top"] = _slot("")
			_slots["right"] = _slot("espada", Color(0.85, 0.87, 0.92), "Espada")
			_slots["left"] = _slot("")

	# Destello cuando cambia algo (Q, beber café...)
	for k in _slots.keys():
		var sig := "%s|%d|%s" % [_slots[k]["icon"], _slots[k]["count"], _slots[k]["active"]]
		if _last.has(k) and _last[k] != sig:
			_flash[k] = 1.0
		_last[k] = sig


# ------------------------------------------------------------------ dibujo

func _rects() -> Dictionary:
	var side_y := S * 0.4
	var side_h := S * 1.35
	return {
		"top": Rect2(S + G, 0, S, S),
		"bottom": Rect2(S + G, S + G, S, S),
		"left": Rect2(0, side_y, S, side_h),
		"right": Rect2((S + G) * 2.0, side_y, S, side_h),
		"small": Rect2((S + G) * 2.0 + S * 0.3, side_y + side_h + G, S * 0.66, S * 0.66),
	}


func _draw() -> void:
	var rects := _rects()
	for k in ["top", "left", "right", "bottom", "small"]:
		if not _slots.has(k):
			continue
		_draw_slot(rects[k], _slots[k], float(_flash.get(k, 0.0)))
	if font == null:
		return
	if _top_text != "":
		draw_string_outline(font, Vector2(0, -8), _top_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(0, -8), _top_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.92, 0.88, 0.78))
	var by := S * 2.0 + G + 26.0
	draw_string_outline(font, Vector2(0, by), _bottom_text, HORIZONTAL_ALIGNMENT_CENTER, BASE_SIZE.x, 20, 5, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(0, by), _bottom_text, HORIZONTAL_ALIGNMENT_CENTER, BASE_SIZE.x, 20, Color(0.93, 0.9, 0.82))


func _draw_slot(r: Rect2, d: Dictionary, flash: float) -> void:
	# Marco: fondo oscuro, brillo interior arriba y borde de bronce
	draw_rect(r.grow(2), Color(0, 0, 0, 0.55))
	draw_rect(r, Color(0.07, 0.065, 0.06, 0.82))
	draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45)), Color(1, 1, 1, 0.03))
	var bc := BORDER.lerp(GOLD, flash)
	if d["active"]:
		bc = GOLD
	draw_rect(r, bc, false, 1.5 + flash)
	if flash > 0.0:
		draw_rect(r.grow(-1), Color(GOLD.r, GOLD.g, GOLD.b, 0.18 * flash))

	var icon: String = d["icon"]
	if icon != "":
		var c: Color = d["color"]
		if d["dim"]:
			c = Color(c.v * 0.45, c.v * 0.45, c.v * 0.45, 0.7)
		var ir := r
		if String(d["caption"]) != "":
			ir.size.y -= 12.0
		_draw_icon(icon, ir.grow(-ir.size.x * 0.14), c)

	if font == null:
		return
	if String(d["caption"]) != "":
		var cy := r.end.y - 4.0
		draw_string_outline(font, Vector2(r.position.x, cy), d["caption"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, 3, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(r.position.x, cy), d["caption"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, Color(0.82, 0.78, 0.68))
	if int(d["count"]) >= 0:
		var fs := 18 if r.size.x > S * 0.7 else 14
		var p := Vector2(r.position.x, r.end.y - 3.0)
		var col := Color(0.95, 0.95, 0.95) if int(d["count"]) > 0 else Color(0.85, 0.3, 0.25)
		draw_string_outline(font, p, str(d["count"]), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4.0, fs, 4, Color(0, 0, 0, 0.95))
		draw_string(font, p, str(d["count"]), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4.0, fs, col)
	if String(d["key"]) != "":
		# En la ranura pequeña la tecla va afuera, a la izquierda
		var kp := r.position + (Vector2(4, 13) if r.size.x > S * 0.8 else Vector2(-11, 12))
		draw_string_outline(font, kp, d["key"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.9))
		draw_string(font, kp, d["key"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.8, 0.55, 0.85))


# ------------------------------------------------------------------ íconos

func _draw_icon(id: String, r: Rect2, c: Color) -> void:
	var cx := r.get_center()
	var w := r.size.x
	var h := r.size.y
	var dark := c.darkened(0.55)
	var gold := Color(0.8, 0.65, 0.35, c.a)
	match id:
		"espada":
			_blade(r, 0.11, c, gold, true)
		"estoque":
			_blade(r, 0.05, c, gold, false)
		"mazo":
			var a := Vector2(cx.x + w * 0.3, r.end.y)
			var b := Vector2(cx.x - w * 0.18, r.position.y + h * 0.3)
			draw_line(a, b, Color(0.45, 0.3, 0.18, c.a), w * 0.09, true)
			_rot_rect(b, Vector2(w * 0.55, w * 0.38), -0.6, dark)
			_rot_rect(b, Vector2(w * 0.55, w * 0.38), -0.6, c, false)
			_rot_rect(b + Vector2(-w * 0.18, -w * 0.12), Vector2(w * 0.12, w * 0.42), -0.6, c)
			_rot_rect(b + Vector2(w * 0.18, w * 0.12), Vector2(w * 0.12, w * 0.42), -0.6, c)
		"lanza":
			var a := Vector2(r.position.x + w * 0.1, r.end.y)
			var b := Vector2(r.end.x - w * 0.15, r.position.y + h * 0.18)
			draw_line(a, b, Color(0.45, 0.3, 0.18, c.a), w * 0.06, true)
			var dir := (b - a).normalized()
			var n := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([b + dir * w * 0.32, b + n * w * 0.1, b - dir * w * 0.04, b - n * w * 0.1]), c)
		"escudo":
			var pts := PackedVector2Array([
				Vector2(r.position.x + w * 0.08, r.position.y + h * 0.12),
				Vector2(cx.x, r.position.y + h * 0.04),
				Vector2(r.end.x - w * 0.08, r.position.y + h * 0.12),
				Vector2(r.end.x - w * 0.12, cx.y + h * 0.15),
				Vector2(cx.x, r.end.y - h * 0.02),
				Vector2(r.position.x + w * 0.12, cx.y + h * 0.15),
			])
			draw_colored_polygon(pts, c)
			pts.append(pts[0])
			draw_polyline(pts, gold, 2.0, true)
			draw_line(Vector2(cx.x, r.position.y + h * 0.1), Vector2(cx.x, r.end.y - h * 0.1), gold, 2.5, true)
			draw_line(Vector2(r.position.x + w * 0.2, cx.y - h * 0.08), Vector2(r.end.x - w * 0.2, cx.y - h * 0.08), gold, 2.5, true)
		"baston":
			var a := Vector2(cx.x - w * 0.15, r.end.y)
			var b := Vector2(cx.x + w * 0.12, r.position.y + h * 0.22)
			draw_line(a, b, Color(0.22, 0.22, 0.26, c.a), w * 0.07, true)
			draw_circle(b, w * 0.2, Color(c.r, c.g, c.b, 0.25 * c.a))
			draw_circle(b, w * 0.12, c)
			draw_circle(b - Vector2(w * 0.03, w * 0.03), w * 0.04, Color(1, 1, 1, 0.8 * c.a))
		"arco":
			draw_arc(Vector2(cx.x - w * 0.35, cx.y), h * 0.42, -1.1, 1.1, 20, c, w * 0.08, true)
			var top := Vector2(cx.x - w * 0.35, cx.y) + Vector2(cos(-1.1), sin(-1.1)) * h * 0.42
			var bot := Vector2(cx.x - w * 0.35, cx.y) + Vector2(cos(1.1), sin(1.1)) * h * 0.42
			draw_line(top, bot, Color(0.9, 0.9, 0.85, c.a), 1.2, true)
			_arrow(Vector2(top.x - w * 0.05, cx.y), Vector2(r.end.x, cx.y), Color(0.9, 0.85, 0.7, c.a))
		"tableta":
			var tr := Rect2(cx - Vector2(w * 0.3, h * 0.38), Vector2(w * 0.6, h * 0.76))
			draw_rect(tr, Color(c.r, c.g, c.b, 0.25 * c.a))
			draw_rect(tr, c, false, 2.0)
			for i in 4:
				var y := tr.position.y + tr.size.y * (0.2 + i * 0.18)
				draw_line(Vector2(tr.position.x + w * 0.08, y), Vector2(tr.position.x + w * (0.25 + 0.08 * ((i * 7) % 3)), y), c, 2.0)
		"cafe":
			var top := r.position.y + h * 0.3
			var cup := PackedVector2Array([
				Vector2(r.position.x + w * 0.12, top), Vector2(r.end.x - w * 0.28, top),
				Vector2(r.end.x - w * 0.36, r.end.y - h * 0.08), Vector2(r.position.x + w * 0.2, r.end.y - h * 0.08),
			])
			draw_colored_polygon(cup, Color(0.92, 0.88, 0.8, c.a))
			draw_rect(Rect2(Vector2(r.position.x + w * 0.12, top), Vector2(w * 0.6, h * 0.08)), Color(0.35, 0.2, 0.1, c.a))
			draw_arc(Vector2(r.end.x - w * 0.27, top + h * 0.25), w * 0.13, -PI * 0.5, PI * 0.5, 12, Color(0.92, 0.88, 0.8, c.a), w * 0.06, true)
			draw_rect(Rect2(Vector2(r.position.x + w * 0.18, top + h * 0.22), Vector2(w * 0.44, h * 0.1)), Color(c.r, c.g, c.b, 0.8 * c.a))
			var t := Time.get_ticks_msec() * 0.004
			for i in 3:
				var x := r.position.x + w * (0.26 + i * 0.16)
				var pts := PackedVector2Array()
				for j in 6:
					var y := top - h * 0.04 - j * h * 0.045
					pts.append(Vector2(x + sin(t + j * 0.9 + i) * w * 0.035, y))
				draw_polyline(pts, Color(1, 1, 1, 0.35 * c.a), 1.5, true)
		"bebida":
			var cr := Rect2(cx - Vector2(w * 0.24, h * 0.42), Vector2(w * 0.48, h * 0.84))
			draw_rect(cr, Color(0.12, 0.14, 0.18, c.a))
			draw_rect(cr, Color(0.7, 0.72, 0.75, c.a), false, 1.5)
			draw_rect(Rect2(cr.position + Vector2(w * 0.06, -h * 0.05), Vector2(w * 0.36, h * 0.06)), Color(0.7, 0.72, 0.75, c.a))
			_bolt(cx, w * 0.28, c)
		"sismico":
			var base := Vector2(cx.x, r.end.y - h * 0.15)
			for i in 3:
				var rr := w * (0.18 + i * 0.15)
				draw_arc(base, rr, PI, TAU, 16, Color(c.r, c.g, c.b, c.a * (1.0 - i * 0.25)), 2.5, true)
			draw_line(Vector2(r.position.x, base.y), Vector2(r.end.x, base.y), dark.lightened(0.3), 2.0)
			draw_polyline(PackedVector2Array([base, base + Vector2(-w * 0.1, h * 0.08), base + Vector2(w * 0.02, h * 0.14)]), c, 1.5, true)
		"flechas":
			for i in 3:
				var off := (i - 1) * w * 0.22
				_arrow(Vector2(r.position.x + w * 0.1 + abs(off) * 0.3, cx.y + off + h * 0.2), Vector2(r.end.x - abs(off) * 0.3, cx.y + off - h * 0.2), c)
		"spell_bola_fuego":
			var t := Time.get_ticks_msec() * 0.006
			for i in 5:
				var a := 2.4 + i * 0.18
				var p := cx + Vector2(cos(a), sin(a)) * w * (0.3 + 0.05 * sin(t + i))
				draw_circle(p, w * (0.14 - i * 0.02), Color(1.0, 0.4, 0.1, 0.6 * c.a))
			draw_circle(cx + Vector2(w * 0.06, -w * 0.06), w * 0.26, Color(1.0, 0.45, 0.1, c.a))
			draw_circle(cx + Vector2(w * 0.08, -w * 0.08), w * 0.16, Color(1.0, 0.8, 0.3, c.a))
			draw_circle(cx + Vector2(w * 0.1, -w * 0.1), w * 0.07, Color(1, 1, 0.85, c.a))
		"spell_rayos":
			draw_polyline(PackedVector2Array([Vector2(r.position.x, r.position.y + h * 0.15), Vector2(r.end.x, r.position.y + h * 0.15)]), Color(0.4, 0.45, 0.55, c.a), 4.0)
			_zigzag(Vector2(cx.x - w * 0.1, r.position.y + h * 0.15), Vector2(cx.x + w * 0.05, r.end.y), c, 2.5)
			_zigzag(Vector2(r.position.x + w * 0.15, r.position.y + h * 0.15), Vector2(r.position.x + w * 0.25, cx.y + h * 0.2), c, 1.5)
			_zigzag(Vector2(r.end.x - w * 0.12, r.position.y + h * 0.15), Vector2(r.end.x - w * 0.2, cx.y + h * 0.25), c, 1.5)
		"spell_flecha_mat":
			var pts := PackedVector2Array()
			for i in 17:
				var k := i / 16.0
				pts.append(Vector2(r.position.x + k * w * 0.85, cx.y - sin(k * TAU) * h * 0.25))
			draw_polyline(pts, c, 2.0, true)
			var tip := pts[pts.size() - 1]
			_arrow(tip - Vector2(w * 0.12, -h * 0.12), tip + Vector2(w * 0.1, -h * 0.1), c)
			if font:
				draw_string(font, r.position + Vector2(0, h * 0.25), "f(x)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c)
		"spell_lluvia":
			for i in 5:
				var x := r.position.x + w * (0.1 + i * 0.2)
				var y := r.position.y + h * (0.05 + (i % 2) * 0.15)
				_arrow(Vector2(x - w * 0.08, y), Vector2(x + w * 0.04, y + h * 0.6), c)
		"spell_nova":
			var t := fmod(Time.get_ticks_msec() * 0.001, 1.0)
			for i in 3:
				var k := fmod(t + i / 3.0, 1.0)
				draw_arc(cx, w * (0.12 + k * 0.36), 0, TAU, 28, Color(c.r, c.g, c.b, c.a * (1.0 - k)), 2.0, true)
			draw_circle(cx, w * 0.12, c)
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(cx + Vector2(cos(a), sin(a)) * w * 0.16, cx + Vector2(cos(a), sin(a)) * w * 0.26, c, 1.5, true)
		"spell_veneno":
			draw_circle(cx + Vector2(0, h * 0.12), w * 0.27, Color(c.r, c.g, c.b, 0.85 * c.a))
			draw_rect(Rect2(cx + Vector2(-w * 0.08, -h * 0.38), Vector2(w * 0.16, h * 0.3)), Color(0.75, 0.85, 0.8, 0.8 * c.a))
			draw_rect(Rect2(cx + Vector2(-w * 0.11, -h * 0.44), Vector2(w * 0.22, h * 0.08)), Color(0.5, 0.35, 0.2, c.a))
			draw_circle(cx + Vector2(-w * 0.08, h * 0.05), w * 0.05, Color(1, 1, 1, 0.6 * c.a))
		"ia_ataque", "ia_chatgpt", "ia_gemini", "ia_claude", "ia_":
			_ai_icon(id, cx, minf(w, h), c)


func _blade(r: Rect2, thick: float, c: Color, gold: Color, cross: bool) -> void:
	var w := r.size.x
	var a := Vector2(r.position.x + w * 0.12, r.end.y - w * 0.12)    # pomo
	var b := Vector2(r.end.x - w * 0.06, r.position.y + w * 0.06)    # punta
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x)
	var guard := a + dir * w * 0.28
	var tw := w * thick
	draw_colored_polygon(PackedVector2Array([guard + n * tw, b - dir * w * 0.1 + n * tw * 0.8, b, b - dir * w * 0.1 - n * tw * 0.8, guard - n * tw]), c)
	draw_line(guard + dir * 2.0, b - dir * w * 0.12, c.lightened(0.4), 1.0, true)
	if cross:
		draw_line(guard + n * w * 0.2, guard - n * w * 0.2, gold, w * 0.07, true)
	else:
		draw_arc(guard, w * 0.1, 0, TAU, 14, gold, 2.0, true)
	draw_line(a, guard, Color(0.4, 0.26, 0.15, c.a), w * 0.08, true)
	draw_circle(a, w * 0.06, gold)


func _arrow(a: Vector2, b: Vector2, c: Color) -> void:
	draw_line(a, b, c, 1.6, true)
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x)
	var l := 7.0
	draw_colored_polygon(PackedVector2Array([b + dir * 2.0, b - dir * l + n * l * 0.45, b - dir * l - n * l * 0.45]), c)
	draw_line(a, a - dir * 4.0 + n * 4.0, c, 1.2, true)
	draw_line(a, a - dir * 4.0 - n * 4.0, c, 1.2, true)


func _zigzag(a: Vector2, b: Vector2, c: Color, width: float) -> void:
	var pts := PackedVector2Array([a])
	var n := Vector2(-(b - a).normalized().y, (b - a).normalized().x)
	for i in range(1, 5):
		var amp := (b - a).length() * 0.09
		pts.append(a.lerp(b, i / 5.0) + n * (amp if i % 2 == 0 else -amp))
	pts.append(b)
	draw_polyline(pts, Color(c.r, c.g, c.b, 0.25 * c.a), width * 2.2, true)
	draw_polyline(pts, c, width, true)


func _bolt(cx: Vector2, s: float, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		cx + Vector2(0.15, -1.0) * s, cx + Vector2(-0.45, 0.1) * s, cx + Vector2(-0.02, 0.1) * s,
		cx + Vector2(-0.18, 1.0) * s, cx + Vector2(0.45, -0.15) * s, cx + Vector2(0.03, -0.15) * s,
	]), c)


func _rot_rect(center: Vector2, sz: Vector2, ang: float, c: Color, filled := true) -> void:
	var hx := Vector2(cos(ang), sin(ang)) * sz.x * 0.5
	var hy := Vector2(-sin(ang), cos(ang)) * sz.y * 0.5
	var pts := PackedVector2Array([center - hx - hy, center + hx - hy, center + hx + hy, center - hx + hy])
	if filled:
		draw_colored_polygon(pts, c)
	else:
		pts.append(pts[0])
		draw_polyline(pts, c.lightened(0.3), 1.5, true)


## IAs: cabeza de robot con el color de la IA; ChatGPT nudo, Gemini estrella, Claude destello.
func _ai_icon(id: String, cx: Vector2, s: float, c: Color) -> void:
	draw_circle(cx, s * 0.42, Color(c.r, c.g, c.b, 0.22 * c.a))
	draw_arc(cx, s * 0.42, 0, TAU, 32, c, 2.0, true)
	match id:
		"ia_gemini":
			var pts := PackedVector2Array()
			for i in 16:
				var a := TAU * i / 16.0
				var rr := s * (0.32 if i % 4 == 0 else 0.08)
				pts.append(cx + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(pts, c.lightened(0.3))
		"ia_claude":
			for i in 8:
				var a := TAU * i / 8.0 + 0.2
				draw_line(cx, cx + Vector2(cos(a), sin(a)) * s * (0.3 if i % 2 == 0 else 0.2), c.lightened(0.35), s * 0.07, true)
		"ia_chatgpt":
			for i in 6:
				var a := TAU * i / 6.0
				draw_arc(cx + Vector2(cos(a), sin(a)) * s * 0.1, s * 0.16, a, a + PI * 0.9, 10, c.lightened(0.35), 2.0, true)
		_:
			# Ataque de la IA: puño de energía
			draw_circle(cx, s * 0.18, c.lightened(0.3))
			for i in 6:
				var a := TAU * i / 6.0
				draw_line(cx + Vector2(cos(a), sin(a)) * s * 0.22, cx + Vector2(cos(a), sin(a)) * s * 0.34, c.lightened(0.3), 2.0, true)
