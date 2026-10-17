extends RefCounted
## Efectos visuales del jefe: rayos, ondas de choque, polvo, chispas y quemaduras.
## Todo se genera por código (sin texturas externas) para que la carpeta sea autocontenida.

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(0.5, 0.75, 1.0, 1.0);
uniform float energy = 2.0;
uniform float progress = 0.0;     // 0..1 relleno del aviso
uniform float ring_width = 0.06;
uniform float fill_alpha = 0.25;
uniform float alpha = 1.0;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	if (r > 1.0) discard;
	float ring = smoothstep(1.0 - ring_width * 2.0, 1.0 - ring_width, r) * (1.0 - smoothstep(1.0 - ring_width * 0.5, 1.0, r));
	float fill = step(r, progress) * fill_alpha * (0.6 + 0.4 * r);
	float inner = (1.0 - smoothstep(progress - 0.04, progress, r)) * step(0.02, progress) * smoothstep(progress - 0.12, progress, r) * 0.8;
	float a = clamp(ring + fill + inner, 0.0, 1.0) * alpha;
	ALBEDO = color.rgb * energy * a;
}
"""

const SCORCH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float alpha = 1.0;
uniform float glow = 1.0;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float ang = atan(uv.y, uv.x);
	float rays = 0.75 + 0.25 * sin(ang * 9.0) * sin(ang * 5.0 + 1.3);
	float a = (1.0 - smoothstep(0.2 * rays, 1.0 * rays, r)) * alpha;
	vec3 hot = vec3(0.4, 0.7, 1.0) * 3.0 * glow * (1.0 - smoothstep(0.0, 0.35, r));
	ALBEDO = mix(vec3(0.01), hot, clamp(glow, 0.0, 1.0) * (1.0 - smoothstep(0.0, 0.35, r)));
	ALPHA = a * 0.9;
}
"""

static var _ring_shader: Shader
static var _scorch_shader: Shader
static var _bolt_mat: StandardMaterial3D
static var _bolt_core_mat: StandardMaterial3D


static func ring_shader() -> Shader:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER
	return _ring_shader


static func bolt_material(core: bool = false) -> StandardMaterial3D:
	if _bolt_mat == null:
		_bolt_mat = StandardMaterial3D.new()
		_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bolt_mat.albedo_color = Color(0.35, 0.55, 1.0, 1.0) * 0.9
		_bolt_mat.vertex_color_use_as_albedo = true
		_bolt_core_mat = _bolt_mat.duplicate()
		_bolt_core_mat.albedo_color = Color(0.85, 0.92, 1.0, 1.0) * 2.5
	return _bolt_core_mat if core else _bolt_mat


## Genera una línea quebrada (rayo) entre a y b.
static func jagged_points(a: Vector3, b: Vector3, segments: int, jitter: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var dir := (b - a)
	var side1 := dir.cross(Vector3.UP if absf(dir.normalized().y) < 0.9 else Vector3.RIGHT).normalized()
	var side2 := dir.cross(side1).normalized()
	for i in segments + 1:
		var t := float(i) / segments
		var p := a.lerp(b, t)
		if i > 0 and i < segments:
			var j := jitter * sin(t * PI)
			p += side1 * rng.randf_range(-j, j) + side2 * rng.randf_range(-j, j)
		pts.append(p)
	return pts


## Construye una malla de "cinta en cruz" (dos planos perpendiculares por segmento)
## para que el rayo se vea desde cualquier ángulo.
static func ribbon_mesh(paths: Array, widths: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in paths.size():
		var pts: PackedVector3Array = paths[k]
		var w: float = widths[k]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var d := (b - a).normalized()
			var p1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
			var p2 := d.cross(p1).normalized()
			var fade := 1.0 - float(i) / pts.size() * 0.3
			for p in [p1, p2]:
				var o: Vector3 = p * w * 0.5
				var c := Color(1, 1, 1, fade)
				st.set_color(c); st.add_vertex(a - o)
				st.set_color(c); st.add_vertex(a + o)
				st.set_color(c); st.add_vertex(b + o)
				st.set_color(c); st.add_vertex(a - o)
				st.set_color(c); st.add_vertex(b + o)
				st.set_color(c); st.add_vertex(b - o)
	return st.commit()


## Rayo completo desde el cielo hasta `ground` (con ramificaciones).
static func spawn_bolt(parent: Node, top: Vector3, ground: Vector3, rng: RandomNumberGenerator, width: float = 0.35) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var main := jagged_points(top, ground, 26, (top - ground).length() * 0.06, rng)
	var paths := [main]
	var widths := [width]
	for b in rng.randi_range(3, 5):
		var idx := rng.randi_range(3, main.size() - 6)
		var start := main[idx]
		var len := rng.randf_range(4.0, 12.0)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1.4, -0.3), rng.randf_range(-1, 1)).normalized()
		paths.append(jagged_points(start, start + dir * len, 8, len * 0.12, rng))
		widths.append(width * 0.35)
	var glow := MeshInstance3D.new()
	glow.mesh = ribbon_mesh(paths, widths.map(func(x): return x * 2.2))
	glow.material_override = bolt_material(false)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	var core := MeshInstance3D.new()
	core.mesh = ribbon_mesh(paths, widths)
	core.material_override = bolt_material(true)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var light := OmniLight3D.new()
	light.position = ground + Vector3(0, 3, 0)
	light.light_color = Color(0.7, 0.8, 1.0)
	light.light_energy = 10.0
	light.omni_range = 28.0
	light.shadow_enabled = true
	root.add_child(light)
	# Parpadeo: visible / oculto / visible y desvanece
	var tw := root.create_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(func(): root.visible = false)
	tw.tween_interval(0.05)
	tw.tween_callback(func(): root.visible = true)
	tw.tween_property(light, "light_energy", 0.0, 0.3)
	tw.parallel().tween_property(glow, "transparency", 1.0, 0.3)
	tw.parallel().tween_property(core, "transparency", 1.0, 0.3)
	tw.tween_callback(root.queue_free)
	return root


## Círculo plano en el suelo (avisos y ondas). Devuelve el MeshInstance3D.
static func ground_ring(parent: Node, pos: Vector3, radius: float, color: Color, energy: float = 2.0) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	q.orientation = PlaneMesh.FACE_Y
	var m := ShaderMaterial.new()
	m.shader = ring_shader()
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.05, 0)
	mi.scale = Vector3(radius, 1, radius)
	return mi


## Onda expansiva visual (anillo que crece y se desvanece).
static func shockwave(parent: Node, pos: Vector3, radius: float, color: Color, time: float = 0.5) -> void:
	var mi := ground_ring(parent, pos, 0.3, color, 3.0)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("ring_width", 0.12)
	m.set_shader_parameter("fill_alpha", 0.0)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1, radius), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v): m.set_shader_parameter("alpha", v), 1.0, 0.0, time)
	tw.chain().tween_callback(mi.queue_free)


## Marca de quemadura en el suelo que se desvanece lentamente.
static func scorch(parent: Node, pos: Vector3, radius: float, electric: bool = true) -> void:
	if _scorch_shader == null:
		_scorch_shader = Shader.new()
		_scorch_shader.code = SCORCH_SHADER
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	q.orientation = PlaneMesh.FACE_Y
	var m := ShaderMaterial.new()
	m.shader = _scorch_shader
	m.set_shader_parameter("glow", 1.0 if electric else 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.y = randf() * TAU
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.03, 0)
	mi.scale = Vector3(radius, 1, radius)
	var tw := mi.create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("glow", v), 1.0 if electric else 0.0, 0.0, 1.2)
	tw.tween_interval(6.0)
	tw.tween_method(func(v): m.set_shader_parameter("alpha", v), 1.0, 0.0, 3.0)
	tw.tween_callback(mi.queue_free)


static func _soft_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


## Ráfaga de partículas única (polvo de impacto o chispas).
static func burst(parent: Node, pos: Vector3, sparks: bool, amount: int = 40, size: float = 1.0) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.6 if sparks else 1.6
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4 * size
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0 if sparks else 70.0
	pm.initial_velocity_min = (5.0 if sparks else 2.0) * size
	pm.initial_velocity_max = (11.0 if sparks else 5.0) * size
	pm.gravity = Vector3(0, -14, 0) if sparks else Vector3(0, -1.0, 0)
	pm.damping_min = 0.0 if sparks else 2.0
	pm.damping_max = 0.5 if sparks else 3.0
	pm.scale_min = 0.6 if sparks else 0.8 * size
	pm.scale_max = 1.0 if sparks else 1.8 * size
	var cg := Gradient.new()
	if sparks:
		cg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.5, 0.75, 1, 1), Color(0.3, 0.5, 1, 0)])
	else:
		cg.colors = PackedColorArray([Color(0.25, 0.24, 0.23, 0.0), Color(0.3, 0.29, 0.28, 0.6), Color(0.3, 0.3, 0.3, 0)])
	cg.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	pm.color_ramp = cgt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1) if not sparks else Vector2(0.06, 0.18) * size
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex()
	if sparks:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(3, 3, 3, 1)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	else:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.5)
	tw.tween_callback(p.queue_free)
