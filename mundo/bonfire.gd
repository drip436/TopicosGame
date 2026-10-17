extends Node3D
## Hoguera del café: punto de descanso y de reaparición.
## Acércate y presiona E: se enciende (la primera vez) y descansas:
## recuperas toda la vida, se rellenan los cafés, se quitan los estados alterados
## y los enemigos del campus vuelven a aparecer. Si mueres fuera de una pelea de
## jefe, reapareces en la última hoguera donde descansaste.
## VidaDelCampus (world_life.gd) coloca las del campus; también puedes arrastrar
## Hoguera.tscn a la escena para poner más.

const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const M := preload("enemy_models.gd")

@export var title: String = "Hoguera"
@export var lit_on_start: bool = false

var is_lit := false
var _fire: Node3D
var _ember_light: OmniLight3D
var _steam: GPUParticles3D
var _d := {"meshes": [], "J": {}, "eyes": []}


func _ready() -> void:
	add_to_group("hoguera")
	_build()
	if lit_on_start:
		light(true)


## Punto donde reaparece el jugador (a un lado de la hoguera).
func respawn_point() -> Vector3:
	return global_position + global_basis * Vector3(0, 0.2, 2.2)


func light(instant := false) -> void:
	if is_lit:
		return
	is_lit = true
	_fire = LFX.fire(self, global_position + Vector3(0, 0.15, 0), 0.38, true)
	_steam.emitting = true
	_ember_light.light_energy = 0.0
	if not instant:
		LFX.puff(self, global_position + Vector3(0, 0.5, 0), Color(3.0, 1.5, 0.5, 1), 40, 0.25, 5.0, 2.0)


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(title)
	var stone := M.mat(Color(0.38, 0.37, 0.35), 0.9)
	var ash := M.mat(Color(0.09, 0.085, 0.08), 1.0)
	var wood := M.mat(Color(0.26, 0.17, 0.1), 0.9)
	var charred := M.mat(Color(0.07, 0.05, 0.04), 1.0, 0.0, Color(1.0, 0.3, 0.05), 0.6)
	var iron := M.mat(Color(0.15, 0.15, 0.16), 0.5, 0.8)
	var enamel := M.mat(Color(0.12, 0.25, 0.45), 0.3, 0.2)
	M.cyl(_d, self, 0.75, 0.04, Vector3(0, 0.02, 0), ash)
	for i in 10:
		var a := TAU * i / 10.0 + rng.randf_range(-0.1, 0.1)
		M.sph(_d, self, Vector3(rng.randf_range(0.26, 0.36), rng.randf_range(0.16, 0.24), rng.randf_range(0.22, 0.3)),
			Vector3(cos(a) * 0.8, 0.08, sin(a) * 0.8), stone, Vector3(0, rad_to_deg(-a), 0))
	# Leños en tipi
	for i in 5:
		var a := TAU * i / 5.0
		var h := Node3D.new()
		h.rotation = Vector3(0, -a, 0)
		add_child(h)
		M.cyl(_d, h, 0.06, 0.95, Vector3(0.24, 0.32, 0), wood if i % 2 == 0 else charred, Vector3(0, 0, 32))
	M.cyl(_d, self, 0.07, 1.0, Vector3(0, 0.08, 0.3), charred, Vector3(0, 30, 90))
	# Trípode con cafetera de peltre colgando
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var foot := Vector3(cos(a) * 0.62, 0.0, sin(a) * 0.62)
		var top := Vector3(0, 1.45, 0)
		var mid := (foot + top) * 0.5
		var rod := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.018
		cm.height = foot.distance_to(top)
		cm.radial_segments = 5
		cm.material = iron
		rod.mesh = cm
		add_child(rod)
		rod.position = mid
		rod.look_at_from_position(mid, top, Vector3.FORWARD if absf((top - foot).normalized().dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT)
		rod.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	M.cyl(_d, self, 0.008, 0.45, Vector3(0, 1.22, 0), iron)
	var pot := Node3D.new()
	pot.position = Vector3(0, 0.82, 0)
	add_child(pot)
	M.cyl(_d, pot, 0.13, 0.24, Vector3(0, 0.0, 0), enamel)
	M.cyl(_d, pot, 0.09, 0.06, Vector3(0, 0.15, 0), enamel)
	M.sph(_d, pot, Vector3(0.05, 0.05, 0.05), Vector3(0, 0.2, 0), iron)
	M.cone(_d, pot, 0.035, 0.16, Vector3(0, 0.03, -0.17), enamel, Vector3(-55, 0, 0))
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.07
	tm.outer_radius = 0.085
	tm.rings = 10
	tm.ring_segments = 5
	tm.material = iron
	handle.mesh = tm
	handle.position = Vector3(0, 0.0, 0.14)
	handle.rotation_degrees = Vector3(0, 0, 90)
	pot.add_child(handle)
	# Brasas cuando está apagada
	_ember_light = OmniLight3D.new()
	_ember_light.light_color = Color(1.0, 0.4, 0.12)
	_ember_light.light_energy = 0.5
	_ember_light.omni_range = 2.5
	_ember_light.position = Vector3(0, 0.25, 0)
	add_child(_ember_light)
	M.sph(_d, self, Vector3(0.35, 0.05, 0.35), Vector3(0, 0.05, 0), M.mat(Color(0.2, 0.05, 0.02), 1.0, 0.0, Color(1.0, 0.3, 0.05), 1.5))
	# Vapor de la cafetera
	_steam = GPUParticles3D.new()
	_steam.amount = 10
	_steam.lifetime = 2.0
	_steam.emitting = false
	_steam.position = Vector3(0, 0.88, -0.24)
	_steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, -0.3)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, 0.2, 0)
	pm.scale_min = 0.12
	pm.scale_max = 0.3
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(0.9, 0.9, 0.9, 0.35), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_steam.process_material = pm
	var q := QuadMesh.new()
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.albedo_texture = LFX.soft_tex()
	q.material = qm
	_steam.draw_pass_1 = q
	add_child(_steam)
	for mi in _d["meshes"]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
