extends Node3D
## Kit de clase del jugador: armadura, armas y ataques de la clase elegida.
## Lo crea test_player.gd en _ready(). El jugador sigue manejando movimiento,
## rodadas, estamina y vida; aquí está todo lo propio de cada clase:
##   frontend  Mago: estoque (clic izq.) + bastón tecnológico. Hechizos con maná
##             (clic der.), Q cambia de hechizo, G bebe una bebida energética.
##   backend   Tanque: mazo pesado y golpe sísmico; armadura pesada (menos daño,
##             pero lento y rodar le cuesta mucho).
##   ai        Invocador: IAs tipo stand (ChatGPT, Gemini, Claude); Q cambia de IA.
##   cyber     Caballero: espada y escudo (mantén clic der. para cubrirte).
##   data      Arquero: lanza (clic izq.) y arco con flechas infinitas (clic der.).

const CLASSES := preload("player_classes.gd")
const PROJ := preload("player_projectile.gd")
const STAND := preload("stand.gd")
const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const FX := preload("res://boss_profesor/boss_fx.gd")

const SPELLS := [
	{"id": "bola_fuego", "name": "Bola de fuego", "cost": 18.0, "code": ["fuego = Hechizo.bola()", "fuego.lanzar(objetivo)"], "color": Color(1.0, 0.55, 0.2)},
	{"id": "rayos", "name": "Rayos del cielo", "cost": 28.0, "code": ["cielo.invocar(Rayo, n=3)", "rayo.caer(objetivo)"], "color": Color(0.55, 0.8, 1.0)},
	{"id": "flecha_mat", "name": "Flecha matemática", "cost": 14.0, "code": ["f(x) = %s", "flecha.seguir(f)"], "color": Color(0.4, 0.95, 1.0)},
	{"id": "lluvia", "name": "Lluvia de flechas", "cost": 30.0, "code": ["for i in range(24):", "    flecha[i].caer()"], "color": Color(1.0, 0.85, 0.45)},
	{"id": "nova", "name": "Nova arcana (área)", "cost": 25.0, "code": ["nova(radio=6)", "area.detonar()"], "color": Color(0.8, 0.5, 1.0)},
	{"id": "veneno", "name": "Frasco de veneno", "cost": 16.0, "code": ["veneno = Frasco.new()", "veneno.lanzar(objetivo)"], "color": Color(0.45, 1.0, 0.25)},
]
const STANDS := ["chatgpt", "gemini", "claude"]

var player: CharacterBody3D
var class_id := "cyber"
var cfg: Dictionary

# Maná (solo Frontend)
var max_mana := 0.0
var mana := 0.0
var drinks := 0
var max_drinks := 0
var spell_idx := 0

# AI Dev
var stand: Node3D
var stand_idx := 0
var _special_cd := 0.0

# Caballero
var blocking := false
var _shield: Node3D
var _shield_rest := Transform3D.IDENTITY

# Arquero
var _bow_cd := 0.0

# Armadura de resistencia equipada
var resist_id := ""
var meshes: Array[MeshInstance3D] = []
var _trim_mat: StandardMaterial3D
var _emblem: MeshInstance3D

var right_pivot: Node3D
var left_pivot: Node3D
var _attack_kind := "swing"
var _rmb_held := false


func setup(p: CharacterBody3D, id: String) -> void:
	player = p
	class_id = id
	cfg = CLASSES.data(id)
	name = "KitDeClase"
	if id == "frontend":
		max_mana = 100.0
		mana = max_mana
		max_drinks = 3
		drinks = max_drinks
	_build_armor()
	_build_weapons()
	if id == "ai":
		_summon_stand()


# ======================================================================
#  Ataques
# ======================================================================

## Ataque principal (clic izq.). Devuelve los datos del golpe cuerpo a cuerpo
## para que el jugador lo ejecute, o {} si la clase lo maneja sola.
func primary() -> Dictionary:
	match class_id:
		"frontend":
			_attack_kind = "thrust"
			return {"dur": 0.4, "hit_k": 0.4, "damage": 22.0, "reach": 2.9, "arc": 0.5, "stamina": 9.0}
		"backend":
			_attack_kind = "swing"
			return {"dur": 0.95, "hit_k": 0.55, "damage": 52.0, "reach": 3.3, "arc": -0.1, "stamina": 22.0, "aoe": 2.2, "shake": 0.3}
		"data":
			_attack_kind = "thrust"
			return {"dur": 0.5, "hit_k": 0.4, "damage": 30.0, "reach": 3.7, "arc": 0.6, "stamina": 12.0}
		"ai":
			if stand and is_instance_valid(stand) and not stand.busy:
				var busy: float = stand.attack(_aim_target(), _aim_point())
				return {"dur": busy, "hit_k": 2.0, "damage": 0.0, "stamina": 10.0, "no_hit": true}
			return {}
		_:
			_attack_kind = "swing"
			return {"dur": 0.55, "hit_k": 0.35, "damage": 38.0, "reach": 3.0, "arc": 0.3, "stamina": 14.0}


## Animación del arma durante el ataque cuerpo a cuerpo (k de 0 a 1).
func animate_attack(k: float) -> void:
	if right_pivot == null:
		return
	if _attack_kind == "thrust":
		var t := clampf((k - 0.15) * 3.0, 0.0, 1.0)
		right_pivot.position.z = lerpf(0.35, -0.55, t) if k < 0.7 else lerpf(-0.55, 0.0, (k - 0.7) / 0.3)
		right_pivot.rotation_degrees = Vector3(-90, 0, 0)
	else:
		right_pivot.rotation_degrees = Vector3(lerpf(45.0, -115.0, clampf((k - 0.15) * 2.6, 0, 1)), 0, 0)


func rest_pose(delta: float) -> void:
	if right_pivot == null:
		return
	var rest := Vector3(-90, 0, 0) if class_id in ["frontend", "data"] else Vector3(-15, 0, 0)
	right_pivot.rotation_degrees = right_pivot.rotation_degrees.lerp(rest, 1.0 - exp(-10.0 * delta))
	right_pivot.position.z = lerpf(right_pivot.position.z, 0.0, 1.0 - exp(-10.0 * delta))


## Clic derecho presionado.
func secondary_pressed() -> void:
	_rmb_held = true
	if player.is_dead or player.call("_busy"):
		return
	match class_id:
		"frontend":
			_cast()
		"backend":
			_seismic()
		"ai":
			_stand_special()
		"data":
			_shoot_arrow()
		"cyber":
			blocking = true


func secondary_released() -> void:
	_rmb_held = false
	blocking = false


## Q: cambia de hechizo o de IA.
func cycle() -> void:
	match class_id:
		"frontend":
			spell_idx = (spell_idx + 1) % SPELLS.size()
		"ai":
			if stand and is_instance_valid(stand) and stand.busy:
				return
			stand_idx = (stand_idx + 1) % STANDS.size()
			_summon_stand()


## G: bebida energética (recupera maná).
func drink() -> void:
	if class_id != "frontend" or drinks <= 0 or mana >= max_mana or player.is_dead:
		return
	drinks -= 1
	mana = minf(max_mana, mana + 60.0)
	LFX.puff(player, player.global_position + Vector3(0, 1.2, 0), Color(0.5, 1.2, 3.0, 1), 20, 0.12, 2.0, 2.0)


## Hoguera: maná y bebidas al máximo.
func refill() -> void:
	mana = max_mana
	drinks = max_drinks


func ability_text() -> String:
	match class_id:
		"frontend":
			var s: Dictionary = SPELLS[spell_idx]
			return "Hechizo: %s  (%d maná)  ·  Q cambiar" % [s["name"], int(s["cost"])]
		"ai":
			return "IA: %s  ·  Q cambiar" % STAND.INFO[STANDS[stand_idx]]["name"]
		"cyber":
			return "Escudo: mantén clic der." + ("  ·  CUBRIÉNDOTE" if blocking else "")
		"data":
			return "Arco: clic der. (flechas infinitas)"
		"backend":
			return "Golpe sísmico: clic der. (35 estamina)"
	return ""


func process(delta: float) -> void:
	_bow_cd -= delta
	_special_cd -= delta
	if class_id == "cyber" and _shield:
		blocking = _rmb_held and not player.is_dead and player.stamina > 1.0 and not player.call("_stunned")
		var want := Transform3D(Basis(Vector3.UP, 0.0), Vector3(-0.1, 1.15, -0.42)) if blocking else _shield_rest
		_shield.transform = _shield.transform.interpolate_with(want, 1.0 - exp(-16.0 * delta))
	if class_id == "frontend" and left_pivot:
		left_pivot.rotation_degrees.z = lerpf(left_pivot.rotation_degrees.z, 0.0, 1.0 - exp(-6.0 * delta))


## Multiplicador del daño recibido (armadura y escudo).
func damage_mult(from: Variant) -> float:
	var m: float = cfg["dmg_taken"]
	if blocking and from is Vector3:
		var to: Vector3 = (from as Vector3) - player.global_position
		to.y = 0.0
		var face: Vector3 = player.get("_face_dir")
		if to.length() < 0.1 or face.dot(to.normalized()) > 0.2:
			m *= 0.15
			player.stamina = maxf(0.0, player.stamina - 18.0)
			player.set("_st_delay", 0.8)
			FX.burst(player.get_parent(), _shield.global_position, true, 16, 0.6)
			if player.stamina <= 0.0:
				blocking = false
				player.set("_stagger_t", 0.9)
	return m


func is_blocking() -> bool:
	return blocking


# ----------------------------------------------------------------- apuntar

## Objetivo: el fijado (Tab), o el más cercano frente al jugador.
func _aim_target(max_d := 32.0) -> Node3D:
	var f = player.get("_focus_target")
	if player.get("_locked") and f and is_instance_valid(f):
		return f
	var best: Node3D = null
	var best_s := INF
	var face: Vector3 = player.get("_face_dir")
	var cam_fwd: Vector3 = -player.camera.global_basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	for t in PROJ.tree_targets(get_tree()):
		var to: Vector3 = (t as Node3D).global_position - player.global_position
		to.y = 0.0
		var d := to.length()
		if d > max_d or d < 0.1:
			continue
		var align := maxf(cam_fwd.dot(to / d), face.dot(to / d))
		if align < 0.6:
			continue
		var score := d * (2.0 - align)
		if score < best_s:
			best_s = score
			best = t
	return best


## Punto al que apunta la cámara (o el objetivo).
func _aim_point() -> Vector3:
	var t := _aim_target()
	if t:
		return t.global_position
	var cam: Camera3D = player.camera
	var from: Vector3 = cam.global_position
	var dir: Vector3 = -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 40.0)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	var p := player.global_position + Vector3(dir.x, 0, dir.z).normalized() * 14.0
	return p


func _chest() -> Vector3:
	return (player.global_position as Vector3) + Vector3(0, 1.25, 0)


func _face_towards(p: Vector3) -> void:
	var to: Vector3 = p - player.global_position
	to.y = 0.0
	if to.length() > 0.1:
		player.set("_face_dir", to.normalized())


# ======================================================================
#  Frontend: hechizos
# ======================================================================

func _cast() -> void:
	var s: Dictionary = SPELLS[spell_idx]
	if mana < float(s["cost"]):
		_code(["ERROR: maná insuficiente"], Color(1.0, 0.3, 0.25))
		return
	mana -= float(s["cost"])
	var target := _aim_target()
	var aim := _aim_point()
	_face_towards(aim)
	player.set("_attack_t", 0.0)
	player.set("_cast_t", 0.65)       # ocupado lanzando (no se puede atacar)
	left_pivot.rotation_degrees.z = -60.0
	var lines: Array = (s["code"] as Array).duplicate()
	var formula := ""
	if s["id"] == "flecha_mat":
		formula = ["2·sin(x)", "x·(d−x)/d", "1.5·|sin(2x)|"][randi() % 3]
		lines[0] = String(lines[0]) % formula
	_code(lines, s["color"])
	await get_tree().create_timer(0.35, false).timeout
	if player.is_dead:
		return
	var tip := _staff_tip()
	LFX.puff(player.get_parent(), tip, Color(s["color"].r * 3.0, s["color"].g * 3.0, s["color"].b * 3.0, 1), 14, 0.15, 3.0, 0.0)
	match s["id"]:
		"bola_fuego":
			var p := PROJ.new()
			p.kind = "bola_fuego"
			p.shooter = player
			p.damage = 38.0
			p.aoe = 2.6
			var to := (target.global_position + Vector3(0, PROJ.target_height(target) * 0.5, 0)) if target else aim + Vector3(0, 0.8, 0)
			p.velocity = (to - tip).normalized() * 22.0
			p.homing = target
			p.turn_rate = 2.0
			player.get_parent().add_child(p)
			p.global_position = tip
		"rayos":
			_spell_lightning(aim)
		"flecha_mat":
			_spell_math_arrows(target, aim, formula)
		"lluvia":
			_spell_arrow_rain(aim)
		"nova":
			_spell_nova()
		"veneno":
			var p := PROJ.new()
			p.kind = "veneno"
			p.shooter = player
			p.damage = 7.0
			p.aoe = 3.0
			p.gravity = 14.0
			var to := aim
			var flat := Vector2(to.x - tip.x, to.z - tip.z).length()
			var t := clampf(flat / 14.0, 0.4, 1.3)
			var v := (to - tip) / t
			v.y += 0.5 * 14.0 * t
			p.velocity = v
			player.get_parent().add_child(p)
			p.global_position = tip


func _staff_tip() -> Vector3:
	if left_pivot:
		var orb := left_pivot.get_node_or_null("Orbe") as Node3D
		if orb:
			return orb.global_position
	return _chest() + Vector3(0, 0.5, 0)


func _spell_lightning(c: Vector3) -> void:
	var spots: Array[Vector3] = [c]
	for i in 2:
		var a := randf() * TAU
		spots.append(c + Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 3.0))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for s in spots:
		var ring := FX.ground_ring(player.get_parent(), s, 2.4, Color(0.55, 0.8, 1.0), 2.0)
		var tw := ring.create_tween()
		tw.tween_interval(0.45)
		tw.tween_callback(func():
			FX.spawn_bolt(player.get_parent(), s + Vector3(randf_range(-2, 2), 25.0, randf_range(-2, 2)), s, rng, 0.3)
			FX.scorch(player.get_parent(), s, 1.5, true)
			_area(s, 2.4, 30.0)
			ring.queue_free())
		await get_tree().create_timer(0.15, false).timeout


func _spell_math_arrows(target: Node3D, aim: Vector3, formula: String) -> void:
	var dest := target.global_position if target else aim
	var origin := _chest()
	var fwd := dest - origin
	fwd.y = 0.0
	var dist := maxf(4.0, fwd.length())
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var fns := []
	match formula:
		"2·sin(x)":
			fns = [func(s): return 2.0 * sin(s / dist * TAU), func(s): return -2.0 * sin(s / dist * TAU), func(s): return 1.2 * sin(s / dist * TAU * 2.0)]
		"x·(d−x)/d":
			fns = [func(s): return 3.0 * s * (dist - s) / (dist * dist) * 2.0, func(s): return -3.0 * s * (dist - s) / (dist * dist) * 2.0, func(s): return 0.0]
		_:
			fns = [func(s): return 1.5 * absf(sin(s / dist * TAU)), func(s): return -1.5 * absf(sin(s / dist * TAU)), func(s): return 0.8 * sin(s / dist * PI * 3.0)]
	var lbl := Label3D.new()
	lbl.text = "f(x) = " + formula
	lbl.font_size = 48
	lbl.pixel_size = 0.006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.4, 0.95, 1.0)
	lbl.outline_size = 8
	player.get_parent().add_child(lbl)
	lbl.global_position = origin + fwd * 1.5 + Vector3(0, 1.0, 0)
	var tw := lbl.create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(lbl.queue_free)
	for f in fns:
		var p := PROJ.new()
		p.kind = "flecha_mat"
		p.shooter = player
		p.damage = 20.0
		p.path_origin = origin + Vector3(0, -0.2, 0)
		p.path_fwd = fwd
		p.path_side = side
		p.path_fn = f
		p.path_max = dist
		p.speed = 22.0
		player.get_parent().add_child(p)
		await get_tree().create_timer(0.08, false).timeout


func _spell_arrow_rain(c: Vector3) -> void:
	var r := 4.5
	var parent := player.get_parent()
	var ring := FX.ground_ring(parent, c, r, Color(1.0, 0.85, 0.45), 2.0)
	await get_tree().create_timer(0.6, false).timeout
	for i in 24:
		var a := randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * sqrt(randf()) * r
		var arrow := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.04
		cm.height = 1.0
		cm.material = LFX.emissive(Color(1.0, 0.85, 0.45), 1.8)
		arrow.mesh = cm
		arrow.rotation_degrees = Vector3(180, 0, 0)
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(arrow)
		arrow.global_position = p + Vector3(0, 14, 0)
		var tw := arrow.create_tween()
		tw.tween_property(arrow, "global_position", p + Vector3(0, 0.4, 0), 0.22).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			LFX.puff(parent, p + Vector3(0, 0.1, 0), Color(2.0, 1.6, 0.8, 1), 4, 0.1, 1.5, -4.0)
			_area(p, 1.3, 7.0))
		tw.tween_interval(0.8)
		tw.tween_property(arrow, "scale", Vector3.ONE * 0.01, 0.2)
		tw.tween_callback(arrow.queue_free)
		if i % 3 == 0:
			await get_tree().create_timer(0.05, false).timeout
	if is_instance_valid(ring):
		ring.queue_free()


func _spell_nova() -> void:
	var c: Vector3 = player.global_position
	FX.shockwave(player.get_parent(), c, 6.0, Color(0.8, 0.5, 1.0), 0.45)
	LFX.puff(player.get_parent(), c + Vector3(0, 0.6, 0), Color(1.8, 1.0, 3.0, 1), 40, 0.3, 7.0, 0.0)
	_area(c, 6.0, 40.0)
	player.add_camera_shake(0.3)


func _area(p: Vector3, r: float, dmg: float) -> void:
	for t in PROJ.tree_targets(get_tree()):
		var tp: Vector3 = (t as Node3D).global_position
		if absf(tp.y - p.y) < 3.0 and Vector2(tp.x - p.x, tp.z - p.z).length() < r + PROJ.target_radius(t):
			t.take_damage(dmg, p)


## Código flotando antes de cada hechizo.
func _code(lines: Array, col: Color) -> void:
	var pos: Vector3 = player.global_position + Vector3(0, 2.0, 0)
	for i in lines.size():
		var l := Label3D.new()
		l.text = String(lines[i])
		l.font_size = 40
		l.pixel_size = 0.004
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = col
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.outline_size = 8
		l.shaded = false
		player.get_parent().add_child(l)
		var a := TAU * i / maxf(1.0, lines.size()) + randf() * 0.5
		var start := pos + Vector3(cos(a) * 0.6, i * 0.22, sin(a) * 0.6)
		l.global_position = start
		l.modulate.a = 0.0
		var tw := l.create_tween()
		tw.tween_interval(i * 0.06)
		tw.tween_property(l, "modulate:a", 1.0, 0.1)
		tw.parallel().tween_property(l, "global_position", start + Vector3(0, 0.8, 0), 1.2)
		tw.tween_property(l, "modulate:a", 0.0, 0.3)
		tw.tween_callback(l.queue_free)


# ======================================================================
#  Backend / AI / Data
# ======================================================================

## Golpe sísmico: área alrededor (no basta para matar a un jefe de un golpe).
func _seismic() -> void:
	if player.stamina < 35.0:
		return
	player.stamina -= 35.0
	player.set("_st_delay", 1.0)
	player.set("_cast_t", 1.1)
	right_pivot.rotation_degrees = Vector3(60, 0, 0)
	var tw := right_pivot.create_tween()
	tw.tween_property(right_pivot, "rotation_degrees:x", -120.0, 0.25).set_delay(0.45)
	await get_tree().create_timer(0.7, false).timeout
	if player.is_dead:
		return
	var c: Vector3 = player.global_position + player.get("_face_dir") * 1.2
	FX.shockwave(player.get_parent(), c, 3.8, Color(1.0, 0.7, 0.3), 0.45)
	FX.burst(player.get_parent(), c, false, 40, 1.4)
	_area(c, 3.8, 70.0)
	player.add_camera_shake(0.45)


func _summon_stand() -> void:
	if stand and is_instance_valid(stand):
		stand.dismiss()
	stand = STAND.new()
	stand.kind = STANDS[stand_idx]
	stand.player = player
	player.get_parent().add_child.call_deferred(stand)


func _stand_special() -> void:
	if stand == null or not is_instance_valid(stand) or stand.busy or _special_cd > 0.0 or player.stamina < 30.0:
		return
	player.stamina -= 30.0
	player.set("_st_delay", 0.8)
	_special_cd = 2.5
	var busy: float = stand.special(_aim_target(), _aim_point())
	player.set("_cast_t", busy)


func _shoot_arrow() -> void:
	if _bow_cd > 0.0 or player.stamina < 5.0:
		return
	_bow_cd = 0.42
	player.stamina -= 5.0
	player.set("_st_delay", 0.4)
	var target := _aim_target(40.0)
	var aim := _aim_point()
	_face_towards(aim)
	var from: Vector3 = _chest() + player.get("_face_dir") * 0.5
	var to := (target.global_position + Vector3(0, PROJ.target_height(target) * 0.5, 0)) if target else aim + Vector3(0, 1.0, 0)
	var p := PROJ.new()
	p.kind = "flecha"
	p.shooter = player
	p.damage = 17.0
	p.color = Color(1.0, 0.9, 0.7)
	p.velocity = (to - from).normalized() * 45.0
	p.homing = target
	p.turn_rate = 1.5
	player.get_parent().add_child(p)
	p.global_position = from
	if left_pivot:
		left_pivot.rotation_degrees.x = 15.0
		var tw := left_pivot.create_tween()
		tw.tween_property(left_pivot, "rotation_degrees:x", 0.0, 0.2)


# ======================================================================
#  Armaduras y armas
# ======================================================================

func _mat(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mi(p, bm, pos, m, rot)


func _sph(p: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	var mi := _mi(p, sm, pos, m, Vector3.ZERO)
	mi.scale = size
	return mi


func _cyl(p: Node3D, r1: float, r2: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r2
	cm.height = h
	cm.radial_segments = 12
	return _mi(p, cm, pos, m, rot)


func _mi(p: Node3D, mesh: Mesh, pos: Vector3, m: Material, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	p.add_child(mi)
	meshes.append(mi)
	return mi


## Armadura según la clase. El modelo está en pose T: cabeza ~1.55 m, torso
## 0.9–1.3 m, brazos horizontales con las manos en x = ±0.78.
func _build_armor() -> void:
	var v: Node3D = player.get("_visual")
	var root := Node3D.new()
	root.name = "Armadura"
	v.add_child(root)
	_trim_mat = _mat(Color(0.75, 0.62, 0.35), 0.35, 0.8)
	match class_id:
		"backend":
			var steel := _mat(Color(0.32, 0.34, 0.38), 0.35, 0.85)
			var dark := _mat(Color(0.14, 0.14, 0.16), 0.5, 0.6)
			_box(root, Vector3(0.52, 0.5, 0.42), Vector3(0, 1.12, 0), steel)
			_box(root, Vector3(0.5, 0.2, 0.4), Vector3(0, 0.84, 0), dark)
			for sx: float in [-1.0, 1.0]:
				_sph(root, Vector3(0.36, 0.26, 0.4), Vector3(sx * 0.32, 1.36, 0), steel)
				_box(root, Vector3(0.3, 0.07, 0.42), Vector3(sx * 0.32, 1.47, 0), _trim_mat, Vector3(0, 0, sx * -18))
				_box(root, Vector3(0.24, 0.17, 0.17), Vector3(sx * 0.6, 1.27, 0), steel)
				_box(root, Vector3(0.17, 0.5, 0.2), Vector3(sx * 0.1, 0.42, 0), steel)
				_box(root, Vector3(0.2, 0.12, 0.3), Vector3(sx * 0.1, 0.06, -0.04), dark)
			_box(root, Vector3(0.3, 0.34, 0.32), Vector3(0, 1.56, 0), steel)
			_box(root, Vector3(0.24, 0.03, 0.02), Vector3(0, 1.57, -0.165), _mat(Color(0.05, 0.05, 0.05)))
			_box(root, Vector3(0.04, 0.12, 0.34), Vector3(0, 1.76, 0), _trim_mat)
		"frontend":
			var cloth := _mat(Color(0.12, 0.16, 0.28), 0.7)
			var glow := LFX.emissive(Color(0.35, 0.8, 1.0), 2.0)
			_box(root, Vector3(0.46, 0.44, 0.34), Vector3(0, 1.12, 0), cloth)
			_box(root, Vector3(0.02, 0.4, 0.02), Vector3(0.1, 1.12, -0.175), glow)
			_box(root, Vector3(0.02, 0.4, 0.02), Vector3(-0.1, 1.12, -0.175), glow)
			_box(root, Vector3(0.5, 0.9, 0.04), Vector3(0, 1.0, 0.2), cloth, Vector3(8, 0, 0))   # capa
			_cyl(root, 0.12, 0.17, 0.12, Vector3(0, 1.72, 0.02), cloth)                   # capucha
			_box(root, Vector3(0.24, 0.05, 0.04), Vector3(0, 1.57, -0.15), glow)          # visor
			for sx: float in [-1.0, 1.0]:
				_sph(root, Vector3(0.2, 0.14, 0.22), Vector3(sx * 0.27, 1.35, 0), cloth)
		"ai":
			var coat := _mat(Color(0.62, 0.65, 0.7), 0.7)
			var glow := LFX.emissive(Color(0.6, 0.9, 1.0), 1.6)
			_box(root, Vector3(0.46, 0.44, 0.34), Vector3(0, 1.12, 0), coat)
			# Faldones de la bata abiertos por delante
			for sx: float in [-1.0, 1.0]:
				_box(root, Vector3(0.18, 0.55, 0.04), Vector3(sx * 0.15, 0.66, -0.16), coat, Vector3(0, 0, sx * 4))
				_box(root, Vector3(0.04, 0.55, 0.3), Vector3(sx * 0.23, 0.66, 0.0), coat)
			_box(root, Vector3(0.46, 0.55, 0.04), Vector3(0, 0.66, 0.16), coat)
			_box(root, Vector3(0.3, 0.04, 0.02), Vector3(0, 1.25, -0.175), glow)
			_box(root, Vector3(0.26, 0.05, 0.05), Vector3(0, 1.58, -0.14), _mat(Color(0.05, 0.05, 0.08), 0.2, 0.5))
			# Halo de datos sobre la cabeza
			var t := TorusMesh.new()
			t.inner_radius = 0.17
			t.outer_radius = 0.19
			t.material = glow
			var halo := MeshInstance3D.new()
			halo.mesh = t
			halo.position = Vector3(0, 1.82, 0)
			root.add_child(halo)
		"cyber":
			var steel := _mat(Color(0.62, 0.64, 0.68), 0.3, 0.85)
			var cloth := _mat(Color(0.12, 0.2, 0.14), 0.7)
			_box(root, Vector3(0.48, 0.46, 0.36), Vector3(0, 1.12, 0), steel)
			_box(root, Vector3(0.46, 0.22, 0.34), Vector3(0, 0.82, 0), cloth)
			for sx: float in [-1.0, 1.0]:
				_sph(root, Vector3(0.24, 0.16, 0.26), Vector3(sx * 0.28, 1.35, 0), steel)
				_box(root, Vector3(0.14, 0.4, 0.16), Vector3(sx * 0.1, 0.38, 0), steel)
			_sph(root, Vector3(0.3, 0.34, 0.32), Vector3(0, 1.56, 0), steel)
			_box(root, Vector3(0.22, 0.03, 0.02), Vector3(0, 1.57, -0.16), _mat(Color(0.05, 0.05, 0.05)))
			_box(root, Vector3(0.03, 0.14, 0.3), Vector3(0, 1.74, 0), cloth)
		_:
			var leather := _mat(Color(0.35, 0.24, 0.14), 0.75)
			var cloth := _mat(Color(0.2, 0.3, 0.2), 0.75)
			_box(root, Vector3(0.44, 0.42, 0.33), Vector3(0, 1.12, 0), leather)
			_box(root, Vector3(0.06, 0.5, 0.03), Vector3(0.05, 1.1, -0.17), cloth, Vector3(0, 0, 35))
			_cyl(root, 0.13, 0.17, 0.14, Vector3(0, 1.7, 0.03), cloth)
			# Carcaj con flechas
			_cyl(root, 0.07, 0.07, 0.6, Vector3(0.12, 1.2, 0.22), leather, Vector3(0, 0, -20))
			for k in 4:
				_cyl(root, 0.008, 0.008, 0.3, Vector3(0.18 + k * 0.015, 1.55, 0.22), _mat(Color(0.8, 0.75, 0.6)), Vector3(0, 0, -20))
	# Emblema de la armadura de resistencia (oculto hasta equipar una)
	var em := SphereMesh.new()
	em.radius = 0.5
	em.height = 1.0
	_emblem = MeshInstance3D.new()
	_emblem.mesh = em
	_emblem.scale = Vector3(0.1, 0.1, 0.05)
	_emblem.position = Vector3(0, 1.22, -0.24)
	_emblem.visible = false
	root.add_child(_emblem)
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _build_weapons() -> void:
	var v: Node3D = player.get("_visual")
	# Quita la espada genérica del jugador
	var old: Node3D = player.get("_sword_pivot")
	if old:
		old.queue_free()
	right_pivot = Node3D.new()
	right_pivot.name = "ArmaDerecha"
	right_pivot.position = Vector3(0.78, 1.27, 0)
	v.add_child(right_pivot)
	left_pivot = Node3D.new()
	left_pivot.name = "ArmaIzquierda"
	left_pivot.position = Vector3(-0.78, 1.27, 0)
	v.add_child(left_pivot)
	var steel := _mat(Color(0.75, 0.77, 0.82), 0.2, 0.9)
	var dark := _mat(Color(0.12, 0.12, 0.14), 0.5, 0.6)
	var grip := _mat(Color(0.25, 0.16, 0.1), 0.8)
	match class_id:
		"frontend":
			# Estoque (hacia adelante) y bastón tecnológico
			_box(right_pivot, Vector3(0.06, 0.06, 0.14), Vector3(0, 0, 0.04), grip)
			_cyl(right_pivot, 0.07, 0.07, 0.02, Vector3(0, 0, -0.05), _trim_mat, Vector3(90, 0, 0))
			_box(right_pivot, Vector3(0.018, 0.018, 1.0), Vector3(0, 0, -0.56), steel)
			right_pivot.rotation_degrees = Vector3(-90, 0, 0)
			_cyl(left_pivot, 0.025, 0.03, 1.5, Vector3(0, 0.15, 0), dark)
			_cyl(left_pivot, 0.05, 0.05, 0.12, Vector3(0, 0.82, 0), _trim_mat)
			var orb := _sph(left_pivot, Vector3.ONE * 0.16, Vector3(0, 0.96, 0), LFX.emissive(Color(0.35, 0.8, 1.0), 3.0))
			orb.name = "Orbe"
			for k in 3:
				_box(left_pivot, Vector3(0.02, 0.2, 0.02), Vector3(cos(TAU * k / 3.0) * 0.1, 0.94, sin(TAU * k / 3.0) * 0.1), _trim_mat, Vector3(0, 0, 15))
			var l := OmniLight3D.new()
			l.light_color = Color(0.35, 0.8, 1.0)
			l.light_energy = 0.8
			l.omni_range = 3.0
			l.position = Vector3(0, 0.96, 0)
			left_pivot.add_child(l)
		"backend":
			# Mazo pesado
			_cyl(right_pivot, 0.035, 0.035, 1.0, Vector3(0, 0.42, 0), grip)
			_box(right_pivot, Vector3(0.3, 0.3, 0.46), Vector3(0, 0.98, 0), dark)
			_box(right_pivot, Vector3(0.32, 0.32, 0.06), Vector3(0, 0.98, -0.24), steel)
			_box(right_pivot, Vector3(0.32, 0.32, 0.06), Vector3(0, 0.98, 0.24), steel)
			right_pivot.rotation_degrees = Vector3(-15, 0, 0)
		"ai":
			# Tableta holográfica en la mano izquierda
			_box(left_pivot, Vector3(0.24, 0.32, 0.02), Vector3(0, 0.1, -0.1), LFX.emissive(Color(0.5, 0.9, 1.0), 1.5, 0.6), Vector3(-30, 0, 0))
		"cyber":
			# Espada y escudo
			_box(right_pivot, Vector3(0.05, 0.16, 0.05), Vector3(0, 0.0, 0), grip)
			_box(right_pivot, Vector3(0.26, 0.04, 0.06), Vector3(0, 0.1, 0), _trim_mat)
			_box(right_pivot, Vector3(0.05, 0.95, 0.09), Vector3(0, 0.6, 0), steel)
			right_pivot.rotation_degrees = Vector3(-15, 0, 0)
			_shield = Node3D.new()
			_shield.name = "Escudo"
			v.add_child(_shield)
			_shield_rest = Transform3D(Basis(Vector3.UP, deg_to_rad(90)), Vector3(-0.66, 1.2, 0.0))
			_shield.transform = _shield_rest
			_box(_shield, Vector3(0.6, 0.72, 0.06), Vector3.ZERO, _mat(Color(0.2, 0.3, 0.45), 0.5, 0.4))
			_box(_shield, Vector3(0.66, 0.06, 0.07), Vector3(0, 0.33, 0), _trim_mat)
			_box(_shield, Vector3(0.66, 0.06, 0.07), Vector3(0, -0.33, 0), _trim_mat)
			_box(_shield, Vector3(0.08, 0.5, 0.08), Vector3(0, 0, -0.03), _trim_mat)
			_box(_shield, Vector3(0.36, 0.08, 0.08), Vector3(0, 0.08, -0.03), _trim_mat)
		_:
			# Lanza (hacia adelante) y arco
			_cyl(right_pivot, 0.025, 0.025, 1.9, Vector3(0, 0, -0.45), grip, Vector3(90, 0, 0))
			_cyl(right_pivot, 0.0, 0.06, 0.32, Vector3(0, 0, -1.55), steel, Vector3(-90, 0, 0))
			right_pivot.rotation_degrees = Vector3(-90, 0, 0)
			for k in 7:
				var a := deg_to_rad(-60.0 + k * 20.0)
				_box(left_pivot, Vector3(0.04, 0.22, 0.04), Vector3(0, sin(a) * 0.6, -cos(a) * 0.25 + 0.15), grip, Vector3(rad_to_deg(a), 0, 0))
			_cyl(left_pivot, 0.004, 0.004, 1.15, Vector3(0, 0, 0.17), _mat(Color(0.9, 0.9, 0.85)))
	player.set("_sword_pivot", right_pivot)
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Equipa una armadura de resistencia ("" = ninguna): cambia los ribetes de color.
func set_resist_armor(id: String) -> void:
	resist_id = id
	if id == "" or not CLASSES.RESIST_ARMORS.has(id):
		_trim_mat.albedo_color = Color(0.75, 0.62, 0.35)
		_trim_mat.emission_enabled = false
		_emblem.visible = false
		return
	var c: Color = CLASSES.RESIST_ARMORS[id]["color"]
	_trim_mat.albedo_color = c
	_trim_mat.emission_enabled = true
	_trim_mat.emission = c
	_trim_mat.emission_energy_multiplier = 0.6
	_emblem.material_override = LFX.emissive(c, 2.5)
	_emblem.visible = true


## Multiplicadores de resistencia de la armadura equipada.
func resist(effect: String, key: String) -> float:
	if resist_id == "":
		return 1.0
	var a: Dictionary = CLASSES.RESIST_ARMORS[resist_id]
	var eff: String = a["effect"]
	if eff == effect or (eff == "veneno" and effect == "ameba" and key == "buildup"):
		return float(a.get(key, 1.0))
	return 1.0
