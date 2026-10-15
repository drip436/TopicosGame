@tool
extends Node3D
## Lluvia (gotas + salpicaduras en el suelo) que sigue a la cámara activa,
## y relámpagos que iluminan el cielo y la escena.
## Conecta la señal `lightning_struck` para reproducir truenos o sacudir la cámara.

signal lightning_struck(direction: Vector2)

@export var rain_amount: int = 7000:
	set(v):
		rain_amount = v
		if rain:
			rain.amount = v
@export var splash_amount: int = 1200
@export var environment_path: NodePath
@export var sun_path: NodePath
@export var lightning_enabled: bool = true
@export var lightning_min_interval: float = 6.0
@export var lightning_max_interval: float = 16.0

@export_group("Cielo despejado (tras el primer jefe)")
## Al llamar calm() el cielo pasa de tormenta oscura a nublado gris claro.
@export var calm_zenith: Color = Color(0.52, 0.55, 0.59)
@export var calm_horizon: Color = Color(0.74, 0.76, 0.78)
@export var calm_ground: Color = Color(0.2, 0.2, 0.21)
@export var calm_cloud_dark: Color = Color(0.45, 0.47, 0.5)
@export var calm_cloud_light: Color = Color(0.86, 0.87, 0.89)
@export var calm_fog_color: Color = Color(0.66, 0.69, 0.73)
@export var calm_sun_color: Color = Color(0.93, 0.93, 0.9)
@export var calm_sun_energy: float = 1.15
@export var calm_ambient_color: Color = Color(0.7, 0.72, 0.76)
@export var calm_ambient_energy: float = 1.1
@export_group("")

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
var _storm_tween: Tween
var _cover_t := 0.0
var _covered := false


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
		_cover_t -= delta
		if _cover_t <= 0.0:
			_cover_t = 0.25
			_update_cover(cp)
	_update_lightning(delta)


## Cambia la intensidad de la tormenta de forma gradual.
## level: 0 = llovizna, 1 = tormenta fuerte. Lo usa el jefe al cambiar de fase.
func set_storm(level: float, duration: float = 3.0) -> void:
	level = clampf(level, 0.0, 1.0)
	var tw := _new_storm_tween()
	tw.tween_property(rain, "amount_ratio", lerpf(0.12, 1.0, level), duration)
	tw.tween_property(splashes, "amount_ratio", lerpf(0.15, 1.0, level), duration)
	tw.tween_property(droplets, "amount_ratio", lerpf(0.15, 1.0, level), duration)
	lightning_enabled = level > 0.5
	lightning_min_interval = lerpf(10.0, 3.0, level)
	lightning_max_interval = lerpf(20.0, 7.0, level)
	_next = minf(_next, 1.0)


## La tormenta se disipa: deja de llover (solo caen gotas sueltas), ya no hay
## relámpagos y la niebla se aclara un poco. Se usa al derrotar al primer jefe.
## drizzle: proporción de lluvia que queda (0 = nada, 0.03 = una que otra gota).
func calm(duration: float = 12.0, drizzle: float = 0.03) -> void:
	lightning_enabled = false
	var tw := _new_storm_tween()
	tw.tween_property(rain, "amount_ratio", drizzle, duration)
	tw.tween_property(splashes, "amount_ratio", drizzle * 1.5, duration)
	tw.tween_property(droplets, "amount_ratio", drizzle, duration)
	if _env:
		tw.tween_property(_env, "fog_density", _env.fog_density * 0.45, duration)
		tw.tween_property(_env, "volumetric_fog_density", _env.volumetric_fog_density * 0.5, duration)
		tw.tween_property(_env, "fog_light_color", calm_fog_color, duration)
		tw.tween_property(_env, "fog_light_energy", 1.0, duration)
		tw.tween_property(_env, "volumetric_fog_albedo", calm_fog_color.lightened(0.15), duration)
		tw.tween_property(_env, "ambient_light_color", calm_ambient_color, duration)
		tw.tween_property(_env, "ambient_light_energy", calm_ambient_energy, duration)
		tw.tween_property(self, "_amb_base", calm_ambient_energy, duration)
		tw.tween_property(_env, "adjustment_saturation", 0.85, duration)
	if _sun:
		tw.tween_property(_sun, "light_color", calm_sun_color, duration)
		tw.tween_property(_sun, "light_energy", calm_sun_energy, duration)
		tw.tween_property(self, "_sun_base", calm_sun_energy, duration)
	if _sky_mat:
		tw.tween_property(_sky_mat, "shader_parameter/cloud_speed", 0.0025, duration)
		for pair in [["zenith_color", calm_zenith], ["horizon_color", calm_horizon], ["ground_color", calm_ground],
				["cloud_dark", calm_cloud_dark], ["cloud_light", calm_cloud_light]]:
			tw.tween_method(_set_sky.bind(pair[0], _sky_color(pair[0]), pair[1]), 0.0, 1.0, duration)


## El shader usa vec3, así que se interpola a mano entre dos colores.
func _set_sky(t: float, param: String, from: Color, to: Color) -> void:
	_sky_mat.set_shader_parameter(param, from.lerp(to, t))


func _sky_color(param: String) -> Color:
	var v = _sky_mat.get_shader_parameter(param)
	if v is Color:
		return v
	if v is Vector3:
		return Color(v.x, v.y, v.z)
	return Color(0.3, 0.3, 0.3)


func _new_storm_tween() -> Tween:
	if _storm_tween and _storm_tween.is_valid():
		_storm_tween.kill()
	_storm_tween = create_tween().set_parallel(true)
	return _storm_tween


## Bajo un techo (biblioteca, centro de cómputo, túneles...) no se dibuja la lluvia.
func _update_cover(cam_pos: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(cam_pos, cam_pos + Vector3(0, 40, 0))
	var exclude: Array[RID] = []
	for g in ["player", "boss"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is CollisionObject3D:
				exclude.append((n as CollisionObject3D).get_rid())
	q.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var covered := not hit.is_empty() and hit["collider"] is StaticBody3D
	if covered == _covered:
		return
	_covered = covered
	rain.emitting = not covered
	splashes.emitting = not covered
	droplets.emitting = not covered


## Destello de relámpago inmediato (cielo + escena). Lo usan los rayos del jefe.
func flash(direction: Vector2 = Vector2.ZERO) -> void:
	_since = 0.0
	if _sky_mat and direction != Vector2.ZERO:
		_sky_mat.set_shader_parameter("lightning_dir", direction)


func _update_lightning(delta: float) -> void:
	_next -= delta
	if lightning_enabled and _next <= 0.0:
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
