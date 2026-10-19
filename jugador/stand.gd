extends Node3D
## IA invocada por el AI Dev (al estilo de los stands de JoJo's): flota detrás del
## jugador y sale a atacar cuando él ataca.
##   "chatgpt"  gigante de fuerza bruta: puñetazos de área; especial: salto aplastante.
##   "gemini"   arquero: flechas guiadas; especial: ráfaga de 5 flechas.
##   "claude"   espadachín: se lanza y da dos tajos; especial: ráfaga de cortes.

const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const FX := preload("res://boss_profesor/boss_fx.gd")
const PROJ := preload("player_projectile.gd")

const INFO := {
	"chatgpt": {"name": "ChatGPT", "color": Color(0.06, 0.64, 0.5), "accent": Color(0.85, 1.0, 0.95), "scale": 1.45},
	"gemini": {"name": "Gemini", "color": Color(0.26, 0.52, 0.96), "accent": Color(0.66, 0.45, 0.95), "scale": 1.05},
	"claude": {"name": "Claude", "color": Color(0.85, 0.47, 0.34), "accent": Color(1.0, 0.85, 0.7), "scale": 1.1},
}

var kind := "claude"
var player: Node3D
var busy := false

var _root: Node3D
var J := {}
var _pose := {}
var _cur := {}
var _meshes: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D
var _acc: StandardMaterial3D
var _label: Label3D
var _t := 0.0
var _home_lerp := 10.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	_rng.randomize()
	_build()
	if player:
		global_position = _home()
	_set_pose("idle")
	LFX.puff(get_parent(), global_position + Vector3(0, 1.2, 0), _glow_col(2.5), 30, 0.25, 3.0, 0.0)
	_show_name()


func _info() -> Dictionary:
	return INFO[kind]


func _glow_col(k: float) -> Color:
	var c: Color = _info()["color"]
	return Color(c.r * k, c.g * k, c.b * k, 1)


func _home() -> Vector3:
	var fwd: Vector3 = player.get("_face_dir") if "_face_dir" in player else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	return player.global_position - fwd * 1.0 + right * 0.8 + Vector3(0, 0.35 + sin(_t * 2.0) * 0.08, 0)


func _physics_process(delta: float) -> void:
	_t += delta
	if player == null or not is_instance_valid(player):
		return
	if not busy:
		global_position = global_position.lerp(_home(), 1.0 - exp(-_home_lerp * delta))
		var fwd: Vector3 = player.get("_face_dir") if "_face_dir" in player else Vector3.FORWARD
		rotation.y = lerp_angle(rotation.y, atan2(-fwd.x, -fwd.z), 1.0 - exp(-8.0 * delta))
	for k in J.keys():
		_cur[k] = (_cur.get(k, Vector3.ZERO) as Vector3).lerp(_pose.get(k, Vector3.ZERO), 1.0 - exp(-18.0 * delta))
		(J[k] as Node3D).rotation_degrees = _cur[k]
	_mat.emission_energy_multiplier = 1.2 + sin(_t * 3.0) * 0.3


# ------------------------------------------------------------------ ataques

## Ataque normal. Devuelve cuánto tiempo queda ocupado el jugador.
func attack(target: Node3D, aim: Vector3) -> float:
	if busy:
		return 0.0
	match kind:
		"chatgpt":
			_punch(target, aim)
			return 0.45
		"gemini":
			_shoot(target, aim, 1)
			return 0.3
		_:
			_slash(target, aim)
			return 0.35


func special(target: Node3D, aim: Vector3) -> float:
	if busy:
		return 0.0
	match kind:
		"chatgpt":
			_slam(target, aim)
			return 0.7
		"gemini":
			_shoot(target, aim, 5)
			return 0.6
		_:
			_barrage(target, aim)
			return 0.6


func _go_to(p: Vector3, t: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "global_position", p, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		rotation.y = atan2(-d.x, -d.z)


func _front_of(target: Node3D, aim: Vector3, dist: float) -> Vector3:
	var c := target.global_position if target else aim
	var from := player.global_position
	var dir := c - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var r := PROJ.target_radius(target) if target else 0.0
	return c - dir * (r + dist) + Vector3(0, 0.2, 0)


func _face(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		rotation.y = atan2(-d.x, -d.z)


func _punch(target: Node3D, aim: Vector3) -> void:
	busy = true
	var spot := _front_of(target, aim, 1.4)
	_go_to(spot, 0.18)
	_set_pose("punch_wind")
	await _w(0.22)
	_face(target.global_position if target else aim)
	_set_pose("punch")
	var hit_p := global_position + (-global_basis.z) * 1.6
	_area(hit_p, 2.6, 42.0)
	FX.burst(get_parent(), hit_p + Vector3(0, 1.0, 0), false, 20, 1.0)
	LFX.puff(get_parent(), hit_p + Vector3(0, 1.0, 0), _glow_col(2.0), 14, 0.2, 3.0, 0.0)
	_shake(0.25)
	await _w(0.35)
	_set_pose("idle")
	busy = false


func _slam(target: Node3D, aim: Vector3) -> void:
	busy = true
	var spot := _front_of(target, aim, 0.8)
	_set_pose("slam_wind")
	var start := global_position
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p := start.lerp(spot, t)
		p.y += sin(t * PI) * 3.0
		global_position = p, 0.0, 1.0, 0.5)
	await _w(0.5)
	_set_pose("slam")
	FX.shockwave(get_parent(), spot, 5.0, _info()["color"], 0.45)
	FX.burst(get_parent(), spot, false, 50, 1.8)
	_area(spot, 5.0, 60.0)
	_shake(0.5)
	await _w(0.5)
	_set_pose("idle")
	busy = false


func _shoot(target: Node3D, aim: Vector3, n: int) -> void:
	busy = true
	_set_pose("aim")
	if target:
		_face(target.global_position)
	else:
		_face(aim)
	await _w(0.18)
	for i in n:
		var p := PROJ.new()
		p.kind = "flecha"
		p.shooter = player
		p.damage = 18.0 if n == 1 else 14.0
		p.color = Color(0.6, 0.75, 1.0)
		var from := global_position + Vector3(0, 1.4, 0) + (-global_basis.z) * 0.5
		var to := (target.global_position + Vector3(0, PROJ.target_height(target) * 0.5, 0)) if target else aim + Vector3(0, 1.0, 0)
		var dir := (to - from).normalized().rotated(Vector3.UP, (i - (n - 1) * 0.5) * 0.12)
		p.velocity = dir * 40.0
		p.homing = target
		p.turn_rate = 2.5
		get_parent().add_child(p)
		p.global_position = from
		_set_pose("aim_release")
		await _w(0.09)
		_set_pose("aim")
	await _w(0.15)
	_set_pose("idle")
	busy = false


func _slash(target: Node3D, aim: Vector3) -> void:
	busy = true
	var spot := _front_of(target, aim, 1.2)
	_go_to(spot, 0.14)
	_afterimage()
	await _w(0.14)
	_face(target.global_position if target else aim)
	for i in 2:
		_set_pose("slash_a" if i == 0 else "slash_b")
		var hp := global_position + (-global_basis.z) * 1.3
		_area(hp, 2.2, 15.0)
		LFX.puff(get_parent(), hp + Vector3(0, 1.2, 0), _glow_col(2.5), 10, 0.12, 3.0, 0.0)
		await _w(0.16)
	await _w(0.15)
	_set_pose("idle")
	busy = false


## "¡ORA ORA!": ráfaga de cortes rapidísimos.
func _barrage(target: Node3D, aim: Vector3) -> void:
	busy = true
	var spot := _front_of(target, aim, 1.1)
	_go_to(spot, 0.12)
	await _w(0.12)
	_face(target.global_position if target else aim)
	for i in 9:
		_set_pose("slash_a" if i % 2 == 0 else "slash_b")
		if i % 3 == 0:
			_afterimage()
		var hp := global_position + (-global_basis.z) * 1.3
		_area(hp, 2.3, 7.0)
		LFX.puff(get_parent(), hp + Vector3(_rng.randf_range(-0.6, 0.6), 1.2 + _rng.randf_range(-0.4, 0.4), 0), _glow_col(3.0), 6, 0.1, 3.0, 0.0)
		await _w(0.09)
	await _w(0.2)
	_set_pose("idle")
	busy = false


func _area(p: Vector3, r: float, dmg: float) -> void:
	for t in PROJ.tree_targets(get_tree()):
		var tp: Vector3 = (t as Node3D).global_position
		if absf(tp.y - p.y) < 3.0 and Vector2(tp.x - p.x, tp.z - p.z).length() < r + PROJ.target_radius(t):
			t.take_damage(dmg, p)


func _shake(a: float) -> void:
	if player and player.has_method("add_camera_shake"):
		player.add_camera_shake(a)


func _w(t: float) -> Signal:
	return get_tree().create_timer(t, false, true).timeout


func _afterimage() -> void:
	for mi in _meshes:
		var c := MeshInstance3D.new()
		c.mesh = mi.mesh
		c.material_override = _acc
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().add_child(c)
		c.global_transform = mi.global_transform
		var tw := c.create_tween()
		tw.tween_property(c, "transparency", 1.0, 0.35)
		tw.tween_callback(c.queue_free)


func _show_name() -> void:
	if _label:
		_label.queue_free()
	_label = Label3D.new()
	_label.text = "「 %s 」" % String(_info()["name"]).to_upper()
	_label.font_size = 54
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = (_info()["accent"] as Color)
	_label.outline_size = 10
	_label.outline_modulate = (_info()["color"] as Color).darkened(0.5)
	_label.position = Vector3(0, 2.9 * float(_info()["scale"]), 0)
	add_child(_label)
	var tw := _label.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_label, "modulate:a", 0.0, 0.8)


func dismiss() -> void:
	LFX.puff(get_parent(), global_position + Vector3(0, 1.2, 0), _glow_col(2.5), 24, 0.2, 3.0, 0.0)
	queue_free()


# ------------------------------------------------------------------ modelo

func _set_pose(n: String) -> void:
	var P := {
		"idle": {"sh_l": Vector3(10, 0, -20), "sh_r": Vector3(10, 0, 20), "el_l": Vector3(30, 0, 0), "el_r": Vector3(30, 0, 0), "torso": Vector3(-5, 0, 0)},
		"punch_wind": {"sh_r": Vector3(-30, 0, 30), "el_r": Vector3(110, 0, 0), "sh_l": Vector3(60, 0, -20), "el_l": Vector3(80, 0, 0), "torso": Vector3(5, -30, 0)},
		"punch": {"sh_r": Vector3(90, 0, 0), "el_r": Vector3(0, 0, 0), "sh_l": Vector3(30, 0, -30), "el_l": Vector3(90, 0, 0), "torso": Vector3(-15, 25, 0)},
		"slam_wind": {"sh_l": Vector3(170, 0, -15), "sh_r": Vector3(170, 0, 15), "el_l": Vector3(20, 0, 0), "el_r": Vector3(20, 0, 0), "torso": Vector3(10, 0, 0)},
		"slam": {"sh_l": Vector3(70, 0, -5), "sh_r": Vector3(70, 0, 5), "torso": Vector3(-30, 0, 0)},
		"aim": {"sh_l": Vector3(90, 0, 0), "el_l": Vector3(0, 0, 0), "sh_r": Vector3(85, 0, -30), "el_r": Vector3(110, 0, 0), "torso": Vector3(0, 20, 0)},
		"aim_release": {"sh_l": Vector3(92, 0, 0), "sh_r": Vector3(70, 0, 30), "el_r": Vector3(30, 0, 0), "torso": Vector3(0, 20, 0)},
		"slash_a": {"sh_r": Vector3(60, 0, -50), "el_r": Vector3(5, 0, 0), "torso": Vector3(-10, 40, 0), "sh_l": Vector3(20, 0, -40)},
		"slash_b": {"sh_r": Vector3(140, 0, 50), "el_r": Vector3(20, 0, 0), "torso": Vector3(0, -40, 0), "sh_l": Vector3(30, 0, -20)},
	}
	_pose = P.get(n, P["idle"])


func _m(c: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m


func _part(parent: Node3D, mesh: Mesh, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	mi.rotation_degrees = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


func _joint(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	J[n] = j
	return j


func _build() -> void:
	var info := _info()
	var col: Color = info["color"]
	var acc: Color = info["accent"]
	_mat = _m(col, 0.82, 1.2)
	_acc = _m(acc, 0.6, 2.5)
	var dark := _m(col.darkened(0.55), 0.85, 0.4)
	var box := BoxMesh.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	var s: float = info["scale"]
	_root = Node3D.new()
	_root.scale = Vector3.ONE * s
	add_child(_root)
	var big := kind == "chatgpt"
	var torso := _joint(_root, "torso", Vector3(0, 1.0, 0))
	_part(torso, box, Vector3(0.62 if big else 0.42, 0.62, 0.32 if big else 0.24), Vector3(0, 0.3, 0), _mat)
	_part(torso, box, Vector3(0.4 if big else 0.3, 0.3, 0.26 if big else 0.2), Vector3(0, -0.08, 0), dark)
	# El cuerpo se desvanece hacia abajo, como un espíritu
	_part(torso, cyl, Vector3(0.36 if big else 0.26, 0.6, 0.26 if big else 0.2), Vector3(0, -0.45, 0), _m(col, 0.35, 1.5))
	_part(torso, cyl, Vector3(0.2, 0.4, 0.15), Vector3(0, -0.9, 0), _m(col, 0.15, 1.5))
	var head := _joint(torso, "head", Vector3(0, 0.72, 0))
	_part(head, sph, Vector3(0.32, 0.36, 0.32) * (0.8 if big else 1.0), Vector3(0, 0.12, 0), _mat)
	_part(head, box, Vector3(0.26, 0.06, 0.04), Vector3(0, 0.14, -0.15), _acc)
	# Emblema en el pecho
	var em := Node3D.new()
	em.position = Vector3(0, 0.35, -0.17 if big else -0.13)
	torso.add_child(em)
	match kind:
		"chatgpt":
			for i in 6:
				_part(em, box, Vector3(0.05, 0.2, 0.02), Vector3(cos(TAU * i / 6.0) * 0.08, sin(TAU * i / 6.0) * 0.08, 0), _acc, Vector3(0, 0, rad_to_deg(TAU * i / 6.0) + 30))
			# Pelo/cresta de gigante
			_part(head, box, Vector3(0.12, 0.14, 0.3), Vector3(0, 0.3, 0.02), dark)
		"gemini":
			_part(em, box, Vector3(0.05, 0.26, 0.02), Vector3.ZERO, _acc)
			_part(em, box, Vector3(0.26, 0.05, 0.02), Vector3.ZERO, _acc)
			_part(em, box, Vector3(0.1, 0.1, 0.02), Vector3.ZERO, _acc, Vector3(0, 0, 45))
			_part(head, box, Vector3(0.36, 0.08, 0.36), Vector3(0, 0.3, 0), _m(acc, 0.85, 1.0))
		_:
			for i in 8:
				_part(em, box, Vector3(0.03, 0.22, 0.02), Vector3.ZERO, _acc, Vector3(0, 0, i * 22.5))
			_part(head, box, Vector3(0.3, 0.1, 0.3), Vector3(0, 0.3, 0.02), dark)
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var w := 0.5 if big else 0.3
		var sh := _joint(torso, "sh_" + side, Vector3(sx * (w * 0.75 + 0.06), 0.52, 0))
		_part(sh, sph, Vector3.ONE * (0.32 if big else 0.18), Vector3.ZERO, _mat)
		_part(sh, box, Vector3(0.2 if big else 0.11, 0.42, 0.2 if big else 0.11), Vector3(0, -0.22, 0), _mat)
		var el := _joint(sh, "el_" + side, Vector3(0, -0.44, 0))
		_part(el, box, Vector3(0.18 if big else 0.1, 0.4, 0.18 if big else 0.1), Vector3(0, -0.2, 0), dark)
		var hand := Node3D.new()
		hand.position = Vector3(0, -0.44, 0)
		el.add_child(hand)
		_part(hand, sph, Vector3.ONE * (0.32 if big else 0.13), Vector3.ZERO, _mat if big else dark)
		if kind == "claude" and side == "r":
			# Katana de luz
			_part(hand, box, Vector3(0.18, 0.04, 0.06), Vector3(0, -0.05, 0), dark)
			_part(hand, box, Vector3(0.03, 1.15, 0.06), Vector3(0, -0.65, 0), _acc)
		if kind == "gemini" and side == "l":
			# Arco
			for k in 5:
				var a := deg_to_rad(-60.0 + k * 30.0)
				_part(hand, box, Vector3(0.03, 0.32, 0.03), Vector3(0, sin(a) * 0.55, -cos(a) * 0.3 + 0.2), _acc, Vector3(rad_to_deg(a), 0, 0))
