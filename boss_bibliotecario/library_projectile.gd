extends Node3D
## Proyectil del Bibliófilo Demente:
##   BOOK       libro lanzado en arco (o que cae del techo en la lluvia de libros).
##   PATH_ARROW flecha que recorre la curva de la fórmula escrita en un pizarrón:
##              posición = origen + adelante·s + lado·f(s).
##   HOMING     flecha mágica que sale de una hoja y persigue al jugador.
## Si `burn` es true el golpe deja quemadura. Rodar (invulnerabilidad) la esquiva.

const LFX := preload("library_fx.gd")

enum Kind { BOOK, PATH_ARROW, HOMING }

var kind: int = Kind.BOOK
var target: Node3D
var boss: Node3D
var damage := 10.0
var burn := false
var speed := 13.0
var life := 6.0
var hit_radius := 0.75

# Libro
var velocity := Vector3.ZERO
var gravity := 16.0
var land_radius := 0.0       # > 0: daña en área al tocar el suelo (lluvia de libros)
var book_color := Color(0.4, 0.1, 0.08)

# Flecha por función
var path_origin := Vector3.ZERO
var path_fwd := Vector3.FORWARD
var path_side := Vector3.RIGHT
var path_fn: Callable
var path_s := 0.0
var path_max := 36.0
var path_y := 1.25

# Flecha guiada
var turn_rate := 2.6
var dir := Vector3.FORWARD

var _vis: Node3D
var _spin := Vector3.ZERO
var _done := false
var _age := 0.0


func _ready() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	match kind:
		Kind.BOOK:
			_build_book()
		Kind.PATH_ARROW:
			_build_arrow(burn)
		_:
			_build_magic()
	if kind == Kind.PATH_ARROW:
		global_position = _path_point(path_s)


func _build_book() -> void:
	var cover := StandardMaterial3D.new()
	cover.albedo_color = book_color
	cover.roughness = 0.7
	var pages := StandardMaterial3D.new()
	pages.albedo_color = Color(0.85, 0.82, 0.7)
	var c := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.34, 0.09, 0.26)
	bm.material = cover
	c.mesh = bm
	_vis.add_child(c)
	var p := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.31, 0.07, 0.25)
	pb.material = pages
	p.mesh = pb
	p.position = Vector3(0.02, 0, 0.01)
	_vis.add_child(p)
	_spin = Vector3(randf_range(-9, 9), randf_range(-6, 6), randf_range(-9, 9))


func _build_arrow(fire: bool) -> void:
	var col := Color(1.0, 0.45, 0.1) if fire else Color(0.85, 0.95, 1.0)
	var m := LFX.emissive(col, 3.5 if fire else 2.2)
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = 1.0
	cm.radial_segments = 6
	cm.material = m
	shaft.mesh = cm
	shaft.rotation_degrees = Vector3(-90, 0, 0)
	_vis.add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0
	hm.bottom_radius = 0.11
	hm.height = 0.3
	hm.radial_segments = 6
	hm.material = m
	head.mesh = hm
	head.rotation_degrees = Vector3(-90, 0, 0)
	head.position = Vector3(0, 0, -0.62)
	_vis.add_child(head)
	for k in 2:
		var f := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(0.22 if k == 0 else 0.02, 0.02 if k == 0 else 0.22, 0.18)
		fb.material = m
		f.mesh = fb
		f.position = Vector3(0, 0, 0.42)
		_vis.add_child(f)
	_trail(col, fire)


func _build_magic() -> void:
	var col := Color(0.35, 0.75, 1.0)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = LFX.emissive(Color(0.75, 0.92, 1.0), 6.0)
	core.mesh = sm
	core.scale = Vector3(0.12, 0.12, 0.7)
	_vis.add_child(core)
	var glow := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.5
	gm.height = 1.0
	gm.radial_segments = 8
	gm.rings = 4
	gm.material = LFX.emissive(col, 3.0, 0.35)
	glow.mesh = gm
	glow.scale = Vector3(0.32, 0.32, 1.1)
	_vis.add_child(glow)
	_trail(col, false)


func _trail(col: Color, fire: bool) -> void:
	var p := GPUParticles3D.new()
	p.amount = 24 if fire else 16
	p.lifetime = 0.45
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1 if fire else 0, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.8 if fire else 0.2
	pm.gravity = Vector3(0, 1.5 if fire else 0.0, 0)
	pm.scale_min = 0.15
	pm.scale_max = 0.35 if fire else 0.25
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(col.r * 2.5, col.g * 2.5, col.b * 2.5, 0.9), Color(col.r, col.g, col.b, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = LFX.soft_tex()
	q.material = m
	p.draw_pass_1 = q
	add_child(p)


func _path_point(s: float) -> Vector3:
	var lat: float = path_fn.call(s) if path_fn.is_valid() else 0.0
	return path_origin + path_fwd * s + path_side * clampf(lat, -14.0, 14.0) + Vector3(0, path_y, 0)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age > life:
		_finish(false)
		return
	var prev := global_position
	var next := prev
	match kind:
		Kind.BOOK:
			velocity.y -= gravity * delta
			next = prev + velocity * delta
			_vis.rotation += _spin * delta
		Kind.PATH_ARROW:
			path_s += speed * delta
			if path_s > path_max:
				_finish(false)
				return
			next = _path_point(path_s)
			var ahead := _path_point(path_s + 0.4)
			if ahead.distance_to(next) > 0.01:
				_vis.look_at(ahead, Vector3.UP)
		_:
			if _valid_target():
				var to := (target.global_position + Vector3(0, 1.0, 0) - prev).normalized()
				var ang := dir.angle_to(to)
				if ang > 0.001:
					dir = dir.slerp(to, minf(1.0, turn_rate * delta / ang)).normalized()
			speed = minf(speed + 6.0 * delta, 22.0)
			next = prev + dir * speed * delta
			if absf(dir.y) < 0.99:
				_vis.look_at(next + dir, Vector3.UP)
	# Choque con escenario
	if kind != Kind.PATH_ARROW or path_s > 1.0:
		var q := PhysicsRayQueryParameters3D.create(prev, next)
		var excl: Array[RID] = []
		if target is CollisionObject3D:
			excl.append((target as CollisionObject3D).get_rid())
		if boss is CollisionObject3D:
			excl.append((boss as CollisionObject3D).get_rid())
		q.exclude = excl
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and (hit["collider"] is StaticBody3D):
			global_position = hit["position"]
			_finish(false)
			return
	global_position = next
	if kind == Kind.BOOK and global_position.y < 0.12:
		global_position.y = 0.12
		if land_radius > 0.0 and _valid_target():
			var flat := Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z)
			if flat.length() < land_radius:
				_hit()
				return
		_finish(false)
		return
	if _valid_target():
		var c := target.global_position + Vector3(0, 1.0, 0)
		if c.distance_to(global_position) < hit_radius + 0.35:
			if "_iframes" in target and float(target.get("_iframes")) > 0.0:
				return
			_hit()


func _valid_target() -> bool:
	return target != null and is_instance_valid(target) and not ("is_dead" in target and target.is_dead)


func _hit() -> void:
	var before: float = float(target.get("hp")) if "hp" in target else 0.0
	if target.has_method("take_damage"):
		target.take_damage(damage, global_position)
	if burn and target.has_method("apply_status") and "hp" in target and float(target.get("hp")) < before:
		target.apply_status("quemadura", 5.0)
	if target.has_method("add_camera_shake"):
		target.add_camera_shake(0.18)
	_finish(true)


func _finish(_hit_player: bool) -> void:
	_done = true
	var parent := get_parent()
	if parent:
		match kind:
			Kind.BOOK:
				LFX.paper_burst(parent, global_position, 8)
			Kind.PATH_ARROW:
				if burn:
					LFX.puff(parent, global_position, Color(3.0, 1.2, 0.3, 1), 18, 0.35, 3.0, 1.0)
				else:
					LFX.puff(parent, global_position, Color(0.9, 0.92, 0.95, 0.9), 14, 0.3, 2.0, -3.0)
			_:
				LFX.puff(parent, global_position, Color(1.2, 2.2, 3.0, 1), 16, 0.3, 2.5, 0.0)
	queue_free()
