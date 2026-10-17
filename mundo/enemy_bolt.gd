extends Node3D
## Proyectil de enemigos comunes:
##   "laser"  disparo recto de los robots con pistola y de los mechas.
##   "spit"   escupitajo venenoso de los mutantes (vuela en arco, acumula veneno).
## Rodar (invulnerabilidad) lo esquiva; choca con el escenario.

const LFX := preload("res://boss_bibliotecario/library_fx.gd")

var kind := "laser"
var target: Node3D
var shooter: Node
var damage := 10.0
var buildup := 0.0
var velocity := Vector3.ZERO
var gravity := 0.0
var life := 3.0
var size := 1.0
var color := Color(1.0, 0.2, 0.15)

var _age := 0.0
var _vis: Node3D
var _done := false


func _ready() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	if kind == "laser":
		var core := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035 * size
		cm.bottom_radius = 0.035 * size
		cm.height = 0.9 * size
		cm.radial_segments = 6
		cm.material = LFX.emissive(color.lightened(0.5), 3.5)
		core.mesh = cm
		core.rotation_degrees = Vector3(-90, 0, 0)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(core)
		_vis.add_child(LFX.streak(color, 1.8 * size, 0.16 * size, 2.0))
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = 0.7
		l.omni_range = 3.0
		_vis.add_child(l)
	else:
		var glob := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16 * size
		sm.height = 0.3 * size
		sm.radial_segments = 10
		sm.rings = 5
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.75, 0.12)
		m.roughness = 0.15
		m.emission_enabled = true
		m.emission = Color(0.4, 1.0, 0.15)
		m.emission_energy_multiplier = 1.6
		sm.material = m
		glob.mesh = sm
		glob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vis.add_child(glob)
		_vis.add_child(LFX.streak(Color(0.4, 0.9, 0.15), 0.9 * size, 0.22 * size, 1.0))
	_orient()


func _orient() -> void:
	if velocity.length() > 0.01 and absf(velocity.normalized().y) < 0.99:
		_vis.look_at(global_position + velocity, Vector3.UP)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age > life:
		_finish()
		return
	velocity.y -= gravity * delta
	var prev := global_position
	var next := prev + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(prev, next)
	var excl: Array[RID] = []
	if shooter is CollisionObject3D:
		excl.append((shooter as CollisionObject3D).get_rid())
	if target is CollisionObject3D:
		excl.append((target as CollisionObject3D).get_rid())
	q.exclude = excl
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] is StaticBody3D:
		global_position = hit["position"]
		_finish()
		return
	global_position = next
	_orient()
	if next.y < -0.2:
		_finish()
		return
	if target and is_instance_valid(target) and not ("is_dead" in target and target.is_dead):
		var c := target.global_position + Vector3(0, 1.0, 0)
		if c.distance_to(next) < 0.75 + 0.15 * size:
			if "_iframes" in target and float(target.get("_iframes")) > 0.0:
				return
			var before: float = float(target.get("hp")) if "hp" in target else 0.0
			if target.has_method("take_damage"):
				target.take_damage(damage, global_position)
			if buildup > 0.0 and target.has_method("add_buildup") and "hp" in target and float(target.get("hp")) < before:
				target.add_buildup("veneno", buildup)
			_finish()


func _finish() -> void:
	_done = true
	var parent := get_parent()
	if parent:
		if kind == "laser":
			LFX.puff(parent, global_position, Color(color.r * 2.5, color.g * 2.5, color.b * 2.5, 1), 12, 0.12, 3.0, 0.0)
		else:
			LFX.puff(parent, global_position, Color(0.5, 1.4, 0.2, 0.9), 16, 0.22, 2.2, -6.0)
	queue_free()
