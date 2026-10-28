extends Node3D
## Cristal de créditos que suelta un enemigo: salta, flota un instante y vuela hacia el
## jugador; al tocarlo suma `valor` créditos (autoload Partida).

var valor := 1
var target: Node3D
var _vel := Vector3.ZERO
var _t := 0.0
var _mesh: MeshInstance3D

static var _mat: StandardMaterial3D
static var _shape: PrismMesh


func _ready() -> void:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.albedo_color = Color(1.0, 0.85, 0.35)
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.75, 0.25)
		_mat.emission_energy_multiplier = 3.0
		_shape = PrismMesh.new()
		_shape.size = Vector3(0.09, 0.14, 0.09)
		_shape.material = _mat
	for s in [1.0, -1.0]:
		var m := MeshInstance3D.new()
		m.mesh = _shape
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.scale = Vector3(1, s, 1)
		m.position.y = 0.07 * s
		add_child(m)
	_vel = Vector3(randf_range(-2.5, 2.5), randf_range(3.5, 5.5), randf_range(-2.5, 2.5))


func _physics_process(delta: float) -> void:
	_t += delta
	rotation.y += delta * 6.0
	if _t < 0.55 or target == null or not is_instance_valid(target):
		_vel.y -= 12.0 * delta
		position += _vel * delta
		if position.y < 0.3:
			position.y = 0.3
			_vel = Vector3.ZERO
		if target == null or not is_instance_valid(target):
			if _t > 6.0:
				queue_free()
		return
	var goal := target.global_position + Vector3(0, 1.1, 0)
	var to := goal - global_position
	var speed := 6.0 + (_t - 0.55) * 22.0
	if to.length() < 0.35:
		var p := get_node_or_null("/root/Partida")
		if p:
			p.dar_creditos(valor)
		queue_free()
		return
	global_position += to.normalized() * minf(speed * delta, to.length())


## Suelta `total` créditos repartidos en varios cristales.
static func soltar(parent: Node, pos: Vector3, total: int, player: Node3D) -> void:
	if total <= 0 or parent == null:
		return
	var n := clampi(total / 12, 3, 12)
	var resto := total
	for i in n:
		var c := (load("res://mundo/credito.gd") as GDScript).new() as Node3D
		var v := total / n if i < n - 1 else resto
		resto -= v
		c.set("valor", v)
		c.set("target", player)
		parent.add_child(c)
		c.global_position = pos
