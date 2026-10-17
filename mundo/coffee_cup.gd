extends Node3D
## Taza de café coleccionable: al pasar encima, el jugador gana una taza más en
## su inventario (más curaciones; las hogueras las rellenan todas).
## Brilla y echa vapor para que se vea de lejos.

const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const M := preload("enemy_models.gd")

signal picked(cup: Node3D)

var taken := false
var _holder: Node3D
var _t := 0.0
var _d := {"meshes": [], "J": {}, "eyes": []}


func _ready() -> void:
	add_to_group("taza_cafe")
	_t = randf() * 10.0
	_holder = Node3D.new()
	add_child(_holder)
	var ceramic := M.mat(Color(0.93, 0.9, 0.84), 0.25)
	var coffee := M.mat(Color(0.18, 0.09, 0.04), 0.1, 0.0, Color(0.5, 0.25, 0.05), 0.3)
	var glow := Color(1.0, 0.75, 0.35)
	M.cyl(_d, _holder, 0.16, 0.02, Vector3(0, 0.0, 0), ceramic)
	M.cyl(_d, _holder, 0.1, 0.14, Vector3(0, 0.08, 0), ceramic)
	M.cyl(_d, _holder, 0.085, 0.01, Vector3(0, 0.148, 0), coffee)
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.035
	tm.outer_radius = 0.055
	tm.rings = 10
	tm.ring_segments = 6
	tm.material = ceramic
	handle.mesh = tm
	handle.position = Vector3(0.11, 0.08, 0)
	handle.rotation_degrees = Vector3(90, 0, 0)
	_holder.add_child(handle)
	_holder.position.y = 0.9
	_holder.scale = Vector3.ONE * 1.6
	# Halo y columna de luz tenue
	var aura := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.material = LFX.emissive(glow, 0.5, 0.08)
	aura.mesh = sm
	aura.scale = Vector3.ONE * 0.6
	aura.position = Vector3(0, 0.95, 0)
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(aura)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.18
	cm.height = 3.2
	cm.material = LFX.emissive(glow, 0.6, 0.07)
	beam.mesh = cm
	beam.position = Vector3(0, 1.6, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var l := OmniLight3D.new()
	l.light_color = glow
	l.light_energy = 0.9
	l.omni_range = 3.5
	l.position = Vector3(0, 1.1, 0)
	l.distance_fade_enabled = true
	l.distance_fade_begin = 60.0
	l.distance_fade_length = 20.0
	add_child(l)
	var steam := _steam()
	steam.position = Vector3(0, 1.15, 0)
	for mi in _d["meshes"]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _steam() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 6
	p.lifetime = 1.6
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.08
	pm.scale_max = 0.18
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.albedo_texture = LFX.soft_tex()
	q.material = qm
	p.draw_pass_1 = q
	add_child(p)
	return p


func _process(delta: float) -> void:
	_t += delta
	_holder.rotation.y += delta * 1.2
	_holder.position.y = 0.9 + sin(_t * 2.0) * 0.08


## Lo recoge el jugador (lo llama VidaDelCampus al pasar encima).
func take() -> void:
	if taken:
		return
	taken = true
	picked.emit(self)
	LFX.puff(get_parent(), global_position + Vector3(0, 1.0, 0), Color(2.5, 1.8, 0.8, 1), 30, 0.18, 3.0, -2.0)
	queue_free()
