extends Node3D
## Un rayo del jefe: muestra un aviso en el suelo, espera `delay` y cae desde el cielo.
## Daña a todo lo que esté en el grupo "player" dentro de `radius`.

const FX := preload("boss_fx.gd")

signal struck(pos: Vector3)

var radius := 2.6
var delay := 1.2
var damage := 30.0
var weather: Node = null
var _t := 0.0
var _ring: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _done := false


func _ready() -> void:
	_rng.randomize()
	_ring = FX.ground_ring(self, global_position, radius, Color(0.45, 0.7, 1.0), 2.2)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var k := clampf(_t / delay, 0.0, 1.0)
	var m: ShaderMaterial = _ring.material_override
	m.set_shader_parameter("progress", k)
	m.set_shader_parameter("energy", 1.5 + 2.5 * k + sin(_t * 30.0) * 0.5 * k)
	if _t >= delay:
		_strike()


func _strike() -> void:
	_done = true
	var ground := global_position
	var top := ground + Vector3(_rng.randf_range(-12, 12), 70, _rng.randf_range(-12, 12))
	var holder := get_parent()
	FX.spawn_bolt(holder, top, ground, _rng, 0.4)
	FX.scorch(holder, ground, radius * 1.1, true)
	FX.burst(holder, ground + Vector3(0, 0.3, 0), true, 60, 1.2)
	FX.shockwave(holder, ground, radius * 1.6, Color(0.5, 0.75, 1.0), 0.35)
	if weather and weather.has_method("flash"):
		var d := Vector2(top.x - ground.x, top.z - ground.z)
		weather.flash(d.normalized() if d.length() > 0.1 else Vector2.RIGHT)
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node3D:
			var flat := Vector2(p.global_position.x - ground.x, p.global_position.z - ground.z)
			if flat.length() <= radius and p.has_method("take_damage"):
				p.take_damage(damage, ground)
			if p.has_method("add_camera_shake"):
				var dist: float = p.global_position.distance_to(ground)
				p.add_camera_shake(clampf(1.0 - dist / 30.0, 0.15, 1.0) * 0.6)
	struck.emit(ground)
	_ring.queue_free()
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(queue_free)
