extends RefCounted
## Efectos visuales del segundo jefe: fuego, humo, brasas, polvo de gis,
## estallido de hojas y texturas procedurales (camisa de cuadros, mezclilla).

const FLICKER := preload("res://scripts/flicker_light.gd")


static func soft_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## Textura de camisa a cuadros (rojo, negro y líneas claras).
static func plaid_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var base := Color(0.52, 0.07, 0.06)
	var dark := Color(0.08, 0.05, 0.05)
	var line := Color(0.75, 0.7, 0.55)
	for y in n:
		for x in n:
			var c := base
			var bx := (x % 32) < 12
			var by := (y % 32) < 12
			if bx and by:
				c = dark
			elif bx or by:
				c = base.lerp(dark, 0.55)
			if x % 32 == 20 or y % 32 == 20:
				c = c.lerp(line, 0.7)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func plaid_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = plaid_texture()
	m.uv1_scale = Vector3(3, 3, 3)
	m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m


static func denim_material() -> StandardMaterial3D:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for y in n:
		for x in n:
			var twill := 0.06 if (x + y) % 4 < 2 else -0.04
			var v := rng.randf_range(-0.04, 0.04) + twill
			img.set_pixel(x, y, Color(0.16 + v, 0.24 + v, 0.4 + v))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_scale = Vector3(4, 6, 4)
	m.roughness = 0.95
	return m


static func emissive(c: Color, energy: float, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _particles(parent: Node, pos: Vector3, amount: int, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	return p


static func _quad(size: Vector2, color: Color, additive: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = soft_tex()
	m.albedo_color = color
	q.material = m
	return q


static func _ramp(colors: PackedColorArray, offsets: PackedFloat32Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Fogata; si `light` es true agrega una luz parpadeante.
static func fire(parent: Node, pos: Vector3, size := 1.0, light := true) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Fuego"
	parent.add_child(holder)
	holder.global_position = pos
	var p := _particles(holder, pos, int(42 * size) + 8, 0.9)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5 * size
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.8
	pm.gravity = Vector3(0, 1.0, 0)
	pm.scale_min = 0.6 * size
	pm.scale_max = 1.2 * size
	pm.color_ramp = _ramp(PackedColorArray([Color(1, 0.85, 0.4, 1), Color(1, 0.4, 0.08, 0.8), Color(0.3, 0.05, 0.0, 0)]), PackedFloat32Array([0.0, 0.35, 1.0]))
	p.process_material = pm
	p.draw_pass_1 = _quad(Vector2(0.9, 1.2), Color(2.5, 2.5, 2.5, 1), true)
	if light:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.5, 0.18)
		l.light_energy = 2.6 * size
		l.omni_range = 9.0 * size
		l.position = Vector3(0, 1.0, 0)
		l.set_script(FLICKER)
		l.set("base_energy", 2.6 * size)
		l.set("speed", 9.0)
		l.set("dropout_chance", 0.0)
		holder.add_child(l)
	return holder


static func smoke(parent: Node, pos: Vector3, size := 1.0) -> GPUParticles3D:
	var p := _particles(parent, pos, int(20 * size) + 6, 8.0)
	p.preprocess = 4.0
	p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.8 * size
	pm.direction = Vector3(0.1, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0.2, 0.3, 0)
	pm.scale_min = 2.0 * size
	pm.scale_max = 4.0 * size
	pm.color_ramp = _ramp(PackedColorArray([Color(0.1, 0.09, 0.08, 0), Color(0.12, 0.11, 0.1, 0.5), Color(0.2, 0.2, 0.2, 0)]), PackedFloat32Array([0.0, 0.2, 1.0]))
	p.process_material = pm
	var q := _quad(Vector2(1, 1), Color(1, 1, 1, 1), false)
	(q.material as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	p.draw_pass_1 = q
	return p


## Brasas que flotan por una zona (caja de `extents`).
static func embers(parent: Node, pos: Vector3, extents: Vector3, amount := 120) -> GPUParticles3D:
	var p := _particles(parent, pos, amount, 5.0)
	p.preprocess = 3.0
	p.visibility_aabb = AABB(-extents - Vector3(4, 4, 4), extents * 2.0 + Vector3(8, 12, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.25, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.3
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color_ramp = _ramp(PackedColorArray([Color(1, 0.7, 0.3, 0), Color(1, 0.5, 0.15, 1), Color(1, 0.3, 0.05, 0)]), PackedFloat32Array([0.0, 0.2, 1.0]))
	p.process_material = pm
	# Brasas diminutas: el tamaño va en el quad (no en scale) y brillo moderado
	p.draw_pass_1 = _quad(Vector2(0.035, 0.035), Color(1.6, 1.1, 0.6, 1), true)
	return p


## Estallido único de partículas (polvo de gis, hojas o chispas de fuego).
static func puff(parent: Node, pos: Vector3, color: Color, amount := 24, size := 0.25, speed := 3.0, grav := -6.0) -> void:
	var p := _particles(parent, pos, amount, 0.9)
	p.one_shot = true
	p.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, grav, 0)
	pm.scale_min = size * 0.5
	pm.scale_max = size
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.color_ramp = _ramp(PackedColorArray([color, Color(color.r, color.g, color.b, 0)]), PackedFloat32Array([0.0, 1.0]))
	p.process_material = pm
	p.draw_pass_1 = _quad(Vector2(1, 1), Color(1, 1, 1, 1), color.r > 1.0)
	p.emitting = true
	var t := parent.get_tree().create_timer(1.5)
	t.timeout.connect(p.queue_free)


## Hojas de papel que salen volando (libro que choca).
static func paper_burst(parent: Node, pos: Vector3, amount := 10) -> void:
	var p := _particles(parent, pos, amount, 1.6)
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, -2.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.angular_velocity_min = -300.0
	pm.angular_velocity_max = 300.0
	pm.scale_min = 0.8
	pm.scale_max = 1.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.27)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.82, 0.72)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.draw_pass_1 = q
	p.emitting = true
	var t := parent.get_tree().create_timer(2.0)
	t.timeout.connect(p.queue_free)
