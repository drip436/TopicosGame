extends Node3D
## Proyectiles del jugador (dañan a enemigos y jefes, nunca al jugador):
##   "flecha"      flecha recta (arquero / IA Gemini / lluvia de flechas).
##   "flecha_mat"  flecha que sigue la curva de una función matemática hasta el objetivo.
##   "bola_fuego"  bola de fuego que explota en área.
##   "veneno"      frasco que cae en arco y deja un charco venenoso que daña por segundos.

const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const FX := preload("res://boss_profesor/boss_fx.gd")

var kind := "flecha"
var shooter: Node3D
var damage := 16.0
var velocity := Vector3.ZERO
var gravity := 0.0
var life := 3.0
var aoe := 0.0
var color := Color(0.85, 0.95, 1.0)
var homing: Node3D
var turn_rate := 3.0

# Flecha matemática: posición = origen + adelante·s + lado·f(s)
var path_origin := Vector3.ZERO
var path_fwd := Vector3.FORWARD
var path_side := Vector3.RIGHT
var path_fn: Callable
var path_s := 0.0
var path_max := 30.0
var speed := 20.0

var _vis: Node3D
var _age := 0.0
var _done := false
var _fx_t := 0.0


func _ready() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	match kind:
		"bola_fuego":
			var core := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.28
			sm.height = 0.56
			sm.material = LFX.emissive(Color(1.0, 0.55, 0.15), 4.0)
			core.mesh = sm
			_vis.add_child(core)
			var halo := MeshInstance3D.new()
			var hm := SphereMesh.new()
			hm.radius = 0.5
			hm.height = 1.0
			hm.material = LFX.emissive(Color(1.0, 0.3, 0.05), 2.0, 0.3)
			halo.mesh = hm
			_vis.add_child(halo)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.5, 0.15)
			l.light_energy = 2.0
			l.omni_range = 5.0
			_vis.add_child(l)
		"veneno":
			var glass := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.06
			cm.bottom_radius = 0.1
			cm.height = 0.24
			cm.material = LFX.emissive(Color(0.4, 1.0, 0.2), 2.0, 0.85)
			glass.mesh = cm
			_vis.add_child(glass)
		_:
			var col := color if kind == "flecha" else Color(0.4, 0.9, 1.0)
			var shaft := MeshInstance3D.new()
			var sc := CylinderMesh.new()
			sc.top_radius = 0.02
			sc.bottom_radius = 0.02
			sc.height = 1.0
			sc.radial_segments = 6
			sc.material = LFX.emissive(col, 1.4)
			shaft.mesh = sc
			shaft.rotation_degrees = Vector3(-90, 0, 0)
			_vis.add_child(shaft)
			var head := MeshInstance3D.new()
			var hc := CylinderMesh.new()
			hc.top_radius = 0.0
			hc.bottom_radius = 0.07
			hc.height = 0.24
			hc.radial_segments = 4
			hc.material = LFX.emissive(col, 2.4)
			head.mesh = hc
			head.rotation_degrees = Vector3(-90, 45, 0)
			head.position = Vector3(0, 0, -0.6)
			_vis.add_child(head)
			_vis.add_child(LFX.streak(col, 1.8, 0.12, 1.2))
	for c in _vis.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if kind == "flecha_mat":
		global_position = _path_point(0.0)


func _path_point(s: float) -> Vector3:
	var lat: float = path_fn.call(s) if path_fn.is_valid() else 0.0
	return path_origin + path_fwd * s + path_side * lat


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age > life:
		_finish()
		return
	var prev := global_position
	var next := prev
	if kind == "flecha_mat":
		path_s += speed * delta
		if path_s > path_max + 4.0:
			_finish()
			return
		next = _path_point(path_s)
		var ahead := _path_point(path_s + 0.4)
		if ahead.distance_to(next) > 0.01:
			_vis.look_at(ahead, Vector3.UP)
	else:
		if homing and is_instance_valid(homing) and not _is_dead(homing):
			var to := (homing.global_position + Vector3(0, 1.2, 0) - prev).normalized()
			var v := velocity.length()
			var dir := velocity.normalized().slerp(to, minf(1.0, turn_rate * delta))
			velocity = dir * v
		velocity.y -= gravity * delta
		next = prev + velocity * delta
		if velocity.length() > 0.1 and absf(velocity.normalized().y) < 0.99:
			_vis.look_at(next + velocity, Vector3.UP)
		if kind == "veneno":
			_vis.rotation += Vector3(7, 3, 5) * delta
	if kind == "bola_fuego":
		_fx_t -= delta
		if _fx_t <= 0.0:
			_fx_t = 0.04
			LFX.puff(get_parent(), prev, Color(3.0, 1.2, 0.3, 1), 3, 0.3, 1.0, 1.5)
	# Escenario
	var q := PhysicsRayQueryParameters3D.create(prev, next)
	if shooter is CollisionObject3D:
		q.exclude = [(shooter as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] is StaticBody3D:
		global_position = hit["position"]
		_impact(null)
		return
	global_position = next
	if next.y < -0.5:
		_impact(null)
		return
	# Enemigos
	for t in _targets():
		if _touches(t, next):
			_impact(t)
			return


func _targets() -> Array:
	if shooter and shooter.has_method("_targets"):
		return shooter._targets()
	var out: Array = []
	for g in ["boss", "enemy"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and not out.has(n) and not _is_dead(n):
				out.append(n)
	return out


func _is_dead(n: Node) -> bool:
	if not is_instance_valid(n):
		return true
	if "is_dead" in n and n.get("is_dead"):
		return true
	return n.is_in_group("boss") and "state" in n and n.get("state") in [5, 6]


## Enemigos y jefes vivos (sin depender de que el proyectil siga existiendo).
static func tree_targets(tree: SceneTree) -> Array:
	var out: Array = []
	for g in ["boss", "enemy"]:
		for n in tree.get_nodes_in_group(g):
			if not (n is Node3D) or out.has(n) or not is_instance_valid(n):
				continue
			if "is_dead" in n and n.get("is_dead"):
				continue
			if n.is_in_group("boss") and "state" in n and n.get("state") in [0, 5, 6]:
				continue
			out.append(n)
	return out


static func target_height(t: Node3D) -> float:
	if t.is_in_group("boss"):
		var cs := t.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs and cs.shape is CapsuleShape3D:
			return (cs.shape as CapsuleShape3D).height
		return 3.0
	if "_cfg" in t:
		return float((t.get("_cfg") as Dictionary).get("height", 1.8))
	return 1.8


static func target_radius(t: Node3D) -> float:
	if "hit_radius" in t:
		return float(t.get("hit_radius"))
	var cs := t.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs and cs.shape is CapsuleShape3D:
		return (cs.shape as CapsuleShape3D).radius
	return 0.6


func _touches(t: Node3D, p: Vector3) -> bool:
	var tp := t.global_position
	if p.y < tp.y - 0.3 or p.y > tp.y + target_height(t) + 0.3:
		return false
	return Vector2(p.x - tp.x, p.z - tp.z).length() < target_radius(t) + 0.45


func _impact(t: Node3D) -> void:
	_done = true
	var parent := get_parent()
	var p := global_position
	match kind:
		"bola_fuego":
			FX.shockwave(parent, p, maxf(aoe, 2.0), Color(1.0, 0.5, 0.15), 0.35)
			LFX.puff(parent, p, Color(3.0, 1.4, 0.3, 1), 30, 0.4, 5.0, 1.0)
			_area(p, maxf(aoe, 2.5), damage)
		"veneno":
			var ground := p
			ground.y = maxf(0.0, p.y - 0.2)
			LFX.puff(parent, ground + Vector3(0, 0.3, 0), Color(0.6, 1.8, 0.3, 1), 24, 0.3, 4.0, 1.0)
			_puddle(parent, ground)
		_:
			if t:
				t.take_damage(damage, p)
			LFX.puff(parent, p, Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 0.9), 8, 0.12, 2.0, -3.0)
	queue_free()


func _area(p: Vector3, r: float, dmg: float) -> void:
	for t in _targets():
		var tp: Vector3 = (t as Node3D).global_position
		if absf(tp.y - p.y) < 3.0 + target_height(t) * 0.5 and Vector2(tp.x - p.x, tp.z - p.z).length() < r + target_radius(t):
			t.take_damage(dmg, p)


## Charco venenoso: daña a lo que esté dentro durante unos segundos.
func _puddle(parent: Node, p: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.03
	cm.material = LFX.emissive(Color(0.3, 0.9, 0.12), 1.2, 0.6)
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = p + Vector3(0, 0.05, 0)
	var r := maxf(aoe, 3.0)
	mi.scale = Vector3(r, 1, r)
	var tree := get_tree()
	var dmg := damage
	var ticks := 10
	var tw := mi.create_tween()
	for i in ticks:
		tw.tween_interval(0.5)
		tw.tween_callback(func():
			if not is_instance_valid(mi):
				return
			LFX.puff(parent, p + Vector3(randf_range(-r, r) * 0.6, 0.2, randf_range(-r, r) * 0.6), Color(0.5, 1.5, 0.25, 0.8), 4, 0.15, 1.0, 1.0)
			for t in tree_targets(tree):
				var tp: Vector3 = (t as Node3D).global_position
				if absf(tp.y - p.y) < 2.5 and Vector2(tp.x - p.x, tp.z - p.z).length() < r + target_radius(t):
					t.take_damage(dmg, p))
	tw.tween_property(mi, "scale", Vector3(0.05, 1, 0.05), 0.5)
	tw.tween_callback(mi.queue_free)


func _finish() -> void:
	_done = true
	queue_free()
