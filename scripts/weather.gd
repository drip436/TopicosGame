@tool
extends Node3D
## Lluvia (gotas + salpicaduras en el suelo) que sigue a la cámara activa,
## y relámpagos que iluminan el cielo y la escena.
## Conecta la señal `lightning_struck` para reproducir truenos o sacudir la cámara.

signal lightning_struck(direction: Vector2)

@export var rain_amount: int = 12000:
	set(v):
		rain_amount = v
		if rain:
			rain.amount = v
@export var splash_amount: int = 2400
@export var environment_path: NodePath
@export var sun_path: NodePath
@export var lightning_enabled: bool = true
@export var lightning_min_interval: float = 6.0
@export var lightning_max_interval: float = 16.0

var rain: GPUParticles3D
var splashes: GPUParticles3D
var droplets: GPUParticles3D

var _rng := RandomNumberGenerator.new()
var _next := 4.0
var _since := 99.0
var _last_k := 0.0
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _rain_mat: StandardMaterial3D
var _sun_base := 0.5
var _amb_base := 0.7


func _ready() -> void:
	_rng.randomize()
	_make_rain()
	_make_splashes()
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	if _sun:
		_sun_base = _sun.light_energy
	var we := get_node_or_null(environment_path) as WorldEnvironment
	if we and we.environment:
		_env = we.environment
		_amb_base = _env.ambient_light_energy
		if _env.sky and _env.sky.sky_material is ShaderMaterial:
			_sky_mat = _env.sky.sky_material


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		var cp := cam.global_position
		var fwd := -cam.global_basis.z
		fwd.y = 0.0
		var ahead := fwd.normalized() * 8.0 if fwd.length() > 0.01 else Vector3.ZERO
		rain.global_position = cp + ahead + Vector3(0, 14, 0)
		splashes.global_position = Vector3(cp.x + ahead.x, 0.04, cp.z + ahead.z)
		droplets.global_position = splashes.global_position
	_update_lightning(delta)


func _update_lightning(delta: float) -> void:
	if not lightning_enabled:
		return
	_next -= delta
	if _next <= 0.0:
		_next = _rng.randf_range(lightning_min_interval, lightning_max_interval)
		_since = 0.0
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		if _sky_mat:
			_sky_mat.set_shader_parameter("lightning_dir", dir)
		lightning_struck.emit(dir)
	_since += delta
	var t := _since
	var k := 0.0
	if t < 0.07:
		k = 1.0
	elif t < 0.14:
		k = 0.12
	elif t < 1.0:
		k = 0.85 * exp(-(t - 0.14) * 6.0)
	if k < 0.01:
		k = 0.0
	if k == 0.0 and _last_k == 0.0:
		return
	_last_k = k
	if _sky_mat:
		_sky_mat.set_shader_parameter("lightning", k * 2.5)
	if _sun:
		_sun.light_energy = _sun_base + k * 2.4
	if _env:
		_env.ambient_light_energy = _amb_base + k * 1.4
	if _rain_mat:
		_rain_mat.albedo_color = Color(0.72, 0.78, 0.88, 0.28 + k * 0.45)


func _soft_tex(colors: PackedColorArray, offsets: PackedFloat32Array, radial: bool) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture2D.new()
	t.gradient = g
	if radial:
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
	else:
		t.fill_from = Vector2(0.5, 0.0)
		t.fill_to = Vector2(0.5, 1.0)
	t.width = 32
	t.height = 64
	return t


func _make_rain() -> void:
	rain = GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = rain_amount
	rain.lifetime = 1.4
	rain.preprocess = 1.4
	rain.local_coords = false
	rain.position = Vector3(0, 14, 0)
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.visibility_aabb = AABB(Vector3(-40, -50, -40), Vector3(80, 70, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 3, 24)
	pm.direction = Vector3(0.1, -1, 0.04)
	pm.spread = 3.0
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 30.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.7)
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.albedo_color = Color(0.72, 0.78, 0.88, 0.28)
	_rain_mat.albedo_texture = _soft_tex(
		PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]),
		PackedFloat32Array([0.0, 0.7, 1.0]), false)
	_rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_mat.billboard_keep_scale = true
	_rain_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_rain_mat.distance_fade_min_distance = 0.6
	_rain_mat.distance_fade_max_distance = 4.0
	q.material = _rain_mat
	rain.draw_pass_1 = q
	add_child(rain)


func _make_splashes() -> void:
	# Anillos de impacto sobre el suelo
	splashes = GPUParticles3D.new()
	splashes.name = "RainSplashes"
	splashes.amount = splash_amount
	splashes.lifetime = 0.35
	splashes.local_coords = false
	splashes.position = Vector3(0, 0.04, 0)
	splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	splashes.visibility_aabb = AABB(Vector3(-25, -2, -25), Vector3(50, 4, 50))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 0, 18)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.15))
	sc.add_point(Vector2(1, 1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var cg := Gradient.new()
	cg.offsets = PackedFloat32Array([0.0, 1.0])
	cg.colors = PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	pm.color_ramp = cgt
	splashes.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.75, 0.8, 0.9, 1)
	m.albedo_texture = _soft_tex(
		PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]),
		PackedFloat32Array([0.0, 0.55, 0.78, 1.0]), true)
	q.material = m
	splashes.draw_pass_1 = q
	add_child(splashes)

	# Pequeñas gotas que rebotan
	droplets = GPUParticles3D.new()
	droplets.name = "RainDroplets"
	droplets.amount = splash_amount / 2
	droplets.lifetime = 0.3
	droplets.local_coords = false
	droplets.position = Vector3(0, 0.04, 0)
	droplets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	droplets.visibility_aabb = AABB(Vector3(-25, -2, -25), Vector3(50, 6, 50))
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm2.emission_box_extents = Vector3(18, 0, 18)
	pm2.direction = Vector3(0, 1, 0)
	pm2.spread = 35.0
	pm2.initial_velocity_min = 1.0
	pm2.initial_velocity_max = 2.2
	pm2.gravity = Vector3(0, -9.8, 0)
	pm2.scale_min = 0.5
	pm2.scale_max = 1.0
	droplets.process_material = pm2
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.025, 0.06)
	var m2 := StandardMaterial3D.new()
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m2.albedo_color = Color(0.8, 0.85, 0.95, 0.5)
	m2.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m2.billboard_keep_scale = true
	q2.material = m2
	droplets.draw_pass_1 = q2
	add_child(droplets)
