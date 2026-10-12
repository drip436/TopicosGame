@tool
extends Node3D
## Genera proceduralmente la arena del jefe: la plaza de entrada de un campus
## universitario en ruinas, con edificios destruidos alrededor, puerta de acceso
## caída, estatua rota, faroles, autos chocados, rejas, escombros y fuego.
## Funciona también dentro del editor (@tool), así que puedes ver el resultado
## sin ejecutar. Cambia `seed_value` para obtener otra variante de destrucción.

@export var seed_value: int = 2026:
	set(v):
		seed_value = v
		if is_inside_tree():
			_build()
@export var plaza_radius: float = 22.0
## Radio del muro invisible que encierra la pelea.
@export var arena_wall_radius: float = 26.0
@export_range(0.0, 1.0) var puddle_coverage: float = 0.5:
	set(v):
		puddle_coverage = v
		if m_ground:
			m_ground.set_shader_parameter("puddle_coverage", v)
## Marca esta casilla en el inspector para regenerar.
@export var rebuild_now: bool = false:
	set(v):
		if v and is_inside_tree():
			_build()

const BAY := 4.0
const FLOOR_H := 3.6

var rng := RandomNumberGenerator.new()
var _root: Node3D
var _mm := {}

var noise_tex: NoiseTexture2D
var m_ground: ShaderMaterial
var m_building: ShaderMaterial
var m_concrete: ShaderMaterial
var m_concrete_dark: ShaderMaterial
var m_rubble: ShaderMaterial
var m_stone: ShaderMaterial
var m_iron: StandardMaterial3D
var m_rebar: StandardMaterial3D
var m_bronze: StandardMaterial3D
var m_wood: StandardMaterial3D
var m_glass: StandardMaterial3D
var m_lamp_on: StandardMaterial3D
var m_burnt: StandardMaterial3D
var m_tire: StandardMaterial3D
var m_cone: StandardMaterial3D

var mesh_panel: BoxMesh
var mesh_slab: BoxMesh
var mesh_col: BoxMesh
var mesh_chunk: BoxMesh
var mesh_rock: SphereMesh
var mesh_mound: SphereMesh
var m_debris: ShaderMaterial
var mesh_rebar: CylinderMesh
var mesh_parapet: BoxMesh
var mesh_bar: BoxMesh
var mesh_rail: BoxMesh
var mesh_post: BoxMesh

const FLICKER := preload("res://scripts/flicker_light.gd")


func _ready() -> void:
	_build()


func _build() -> void:
	if _root and is_instance_valid(_root):
		_root.free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	_mm.clear()
	rng.seed = seed_value
	_make_materials()
	_make_ground()
	_make_buildings()
	_make_gate_and_fence()
	_make_statue()
	_make_lamps()
	_make_props()
	_make_arena_edge()
	_make_fires_and_smoke()
	_flush(_root)


# ---------------------------------------------------------------- materiales

func _make_materials() -> void:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.012
	fnl.fractal_octaves = 5
	fnl.seed = seed_value
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.seamless = true
	noise_tex.noise = fnl

	m_ground = ShaderMaterial.new()
	m_ground.shader = load("res://shaders/wet_ground.gdshader")
	m_ground.set_shader_parameter("noise_tex", noise_tex)
	m_ground.set_shader_parameter("plaza_radius", plaza_radius)
	m_ground.set_shader_parameter("puddle_coverage", puddle_coverage)

	m_building = ShaderMaterial.new()
	m_building.shader = load("res://shaders/building_panel.gdshader")
	m_building.set_shader_parameter("noise_tex", noise_tex)

	m_concrete = _concrete(Color(0.50, 0.48, 0.45), 0.75, 0.1)
	m_concrete_dark = _concrete(Color(0.36, 0.35, 0.34), 0.7, 0.05)
	m_rubble = _concrete(Color(0.40, 0.38, 0.36), 0.8, 0.15)
	m_debris = _concrete(Color(0.22, 0.20, 0.19), 0.6, 0.1)
	m_stone = _concrete(Color(0.55, 0.50, 0.42), 0.7, 0.25)

	m_iron = _std(Color(0.045, 0.045, 0.05), 0.35, 0.7)
	m_rebar = _std(Color(0.28, 0.13, 0.06), 0.6, 0.5)
	m_bronze = _std(Color(0.16, 0.24, 0.20), 0.4, 0.8)
	m_wood = _std(Color(0.09, 0.07, 0.055), 0.7, 0.0)
	m_glass = _std(Color(0.02, 0.025, 0.03), 0.05, 0.2)
	m_burnt = _std(Color(0.07, 0.05, 0.045), 0.6, 0.5)
	m_tire = _std(Color(0.03, 0.03, 0.03), 0.6, 0.0)
	m_cone = _std(Color(0.85, 0.28, 0.05), 0.45, 0.0)
	m_lamp_on = _std(Color(1, 0.8, 0.5), 0.3, 0.0)
	m_lamp_on.emission_enabled = true
	m_lamp_on.emission = Color(1.0, 0.62, 0.3)
	m_lamp_on.emission_energy_multiplier = 4.0

	mesh_panel = _bm(Vector3(BAY, FLOOR_H, 0.3), m_building)
	mesh_slab = _bm(Vector3(BAY + 0.02, 0.35, BAY + 0.02), m_concrete)
	mesh_col = _bm(Vector3(0.55, 1.0, 0.55), m_concrete_dark)
	mesh_chunk = _bm(Vector3.ONE, m_rubble)
	mesh_parapet = _bm(Vector3(BAY, 0.9, 0.35), m_concrete)
	mesh_rock = SphereMesh.new()
	mesh_rock.radius = 0.5
	mesh_rock.height = 1.0
	mesh_rock.radial_segments = 7
	mesh_rock.rings = 4
	mesh_rock.material = m_rubble
	mesh_mound = SphereMesh.new()
	mesh_mound.radius = 0.5
	mesh_mound.height = 1.0
	mesh_mound.radial_segments = 9
	mesh_mound.rings = 5
	mesh_mound.material = m_debris
	mesh_rebar = CylinderMesh.new()
	mesh_rebar.top_radius = 0.025
	mesh_rebar.bottom_radius = 0.025
	mesh_rebar.height = 1.0
	mesh_rebar.radial_segments = 4
	mesh_rebar.rings = 1
	mesh_rebar.material = m_rebar
	mesh_bar = _bm(Vector3(0.045, 2.3, 0.045), m_iron)
	mesh_rail = _bm(Vector3(2.5, 0.06, 0.06), m_iron)
	mesh_post = _bm(Vector3(0.2, 2.7, 0.2), m_iron)


func _concrete(c: Color, wet: float, moss: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/wet_concrete.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex)
	m.set_shader_parameter("tint", c)
	m.set_shader_parameter("wetness", wet)
	m.set_shader_parameter("moss", moss)
	return m


func _std(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _bm(size: Vector3, mat: Material) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	return b


# ------------------------------------------------------------------ helpers

func _xf(pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_scale(scl), pos)


func _rand_rot() -> Vector3:
	return Vector3(rng.randf_range(-180, 180), rng.randf_range(-180, 180), rng.randf_range(-180, 180))


func _mi(parent: Node, mesh: Mesh, xf: Transform3D, mat: Material = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.transform = xf
	if mat:
		m.material_override = mat
	parent.add_child(m)
	return m


func _box(parent: Node, size: Vector3, xf: Transform3D, mat: Material, collide := false) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var m := _mi(parent, b, xf, mat)
	if collide:
		_collider(parent, size, xf)
	return m


func _cyl(parent: Node, r_top: float, r_bot: float, h: float, xf: Transform3D, mat: Material, segs := 10) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return _mi(parent, c, xf, mat)


func _collider(parent: Node, size: Vector3, xf: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.transform = xf
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)


func _mm_add(mesh: Mesh, xf: Transform3D) -> void:
	var k := mesh.get_instance_id()
	if not _mm.has(k):
		_mm[k] = {"mesh": mesh, "xf": []}
	_mm[k]["xf"].append(xf)


## Vuelca las instancias acumuladas como MultiMeshes hijos de `parent`.
func _flush(parent: Node3D) -> void:
	for k in _mm:
		var d: Dictionary = _mm[k]
		var arr: Array = d["xf"]
		if arr.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = d["mesh"]
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		parent.add_child(mmi)
	_mm.clear()


func _rebar(at: Vector3, n: int) -> void:
	for k in n:
		var length := rng.randf_range(0.5, 1.6)
		var dir := Vector3(rng.randf_range(-0.7, 0.7), 1.0, rng.randf_range(-0.7, 0.7)).normalized()
		var b := Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(1, length, 1))
		var off := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		_mm_add(mesh_rebar, Transform3D(b, at + off + dir * length * 0.5))


func _chunk(p: Vector3, smin: float, smax: float) -> void:
	var s := Vector3(rng.randf_range(smin, smax), rng.randf_range(smin, smax) * 0.6, rng.randf_range(smin, smax))
	var mesh: Mesh = mesh_rock if rng.randf() < 0.3 else mesh_chunk
	_mm_add(mesh, _xf(p + Vector3(0, s.y * 0.2, 0), _rand_rot(), s))


func _mound(p: Vector3, w: float, h: float) -> void:
	for q in int(w * 1.5):
		var o := Vector3(rng.randf_range(-0.4, 0.4) * w, 0, rng.randf_range(-0.4, 0.4) * w)
		var fall := 1.0 - o.length() / (w * 0.6)
		_chunk(p + o + Vector3(0, maxf(fall, 0.0) * h * 0.8, 0), 0.3, 1.2)
	_mm_add(mesh_mound, _xf(p, Vector3(0, rng.randf_range(0, 360), 0), Vector3(w * rng.randf_range(0.8, 1.2), h * 2.0, w * rng.randf_range(0.8, 1.2))))


# -------------------------------------------------------------------- suelo

func _make_ground() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600, 1600)
	pm.material = m_ground
	var g := _mi(_root, pm, Transform3D.IDENTITY)
	g.name = "Ground"
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	_root.add_child(body)


# --------------------------------------------------------------- edificios

func _make_buildings() -> void:
	# posición, giro, bahías X, bahías Z, pisos, severidad del daño
	var defs := [
		[Vector3(0, 0, -48), 0.0, 8, 4, 5, 0.75],     # Rectoría / Biblioteca central
		[Vector3(-44, 0, -34), 20.0, 5, 4, 4, 1.0],   # Facultad (noroeste)
		[Vector3(44, 0, -30), -15.0, 6, 3, 6, 0.65],  # Torre de laboratorios
		[Vector3(-50, 0, 6), 90.0, 7, 3, 3, 0.9],     # Aulas oeste
		[Vector3(48, 0, 10), -85.0, 5, 4, 4, 1.1],    # Auditorio este
		[Vector3(-18, 0, -88), 0.0, 6, 4, 8, 0.5],
		[Vector3(32, 0, -82), 10.0, 4, 4, 7, 0.85],
		[Vector3(-80, 0, -40), 75.0, 5, 4, 5, 0.7],
		[Vector3(82, 0, -44), -70.0, 5, 3, 6, 0.9],
		[Vector3(-86, 0, 22), 90.0, 4, 4, 4, 0.8],
		[Vector3(88, 0, 24), -90.0, 4, 3, 5, 0.6],
		[Vector3(-48, 0, 72), 0.0, 6, 3, 4, 0.9],
		[Vector3(46, 0, 70), 5.0, 5, 3, 3, 1.0],
	]
	for d in defs:
		_building(d[0], d[1], d[2], d[3], d[4], d[5])


func _building(origin: Vector3, yaw: float, nx: int, nz: int, floors: int, severity: float) -> void:
	var holder := Node3D.new()
	holder.name = "Building_%d" % _root.get_child_count()
	holder.position = origin
	holder.rotation.y = deg_to_rad(yaw)
	_root.add_child(holder)

	var hx := nx * BAY * 0.5
	var hz := nz * BAY * 0.5

	# Mapa de alturas: un punto de colapso cerca de un borde.
	var cc := Vector2(rng.randf_range(0, nx - 1), rng.randf_range(0, nz - 1))
	if rng.randf() < 0.5:
		cc.x = 0.0 if rng.randf() < 0.5 else float(nx - 1)
	else:
		cc.y = 0.0 if rng.randf() < 0.5 else float(nz - 1)
	var radius := maxf(nx, nz) * rng.randf_range(0.55, 0.95)
	var H := []
	for i in nx:
		var column := []
		for j in nz:
			var d := Vector2(i, j).distance_to(cc)
			var loss := clampf(1.0 - d / radius, 0.0, 1.0) * floors * severity
			loss += rng.randf_range(0.0, 1.3) * severity
			column.append(clampi(floors - int(round(loss)), 0, floors))
		H.append(column)

	var cell := func(i: int, j: int) -> Vector3:
		return Vector3((i + 0.5) * BAY - hx, 0.0, (j + 0.5) * BAY - hz)

	# Losas de piso, losas colgantes y escombro interior.
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in nx:
		for j in nz:
			var h: int = H[i][j]
			var c: Vector3 = cell.call(i, j)
			for L in range(0, h + 1):
				if L > 0 and L < h and rng.randf() < 0.06:
					continue
				var tilt := Vector3.ZERO
				if L == h and h < floors and L > 0:
					tilt = Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
				_mm_add(mesh_slab, _xf(c + Vector3(0, L * FLOOR_H, 0), tilt))
			if h < floors and rng.randf() < 0.7:
				var start := rng.randi() % 4
				for k in 4:
					var dd: Vector2i = dirs[(start + k) % 4]
					var ni := i + dd.x
					var nj := j + dd.y
					if ni < 0 or nj < 0 or ni >= nx or nj >= nz:
						continue
					if H[ni][nj] <= h:
						continue
					var dir3 := Vector3(dd.x, 0, dd.y)
					var hinge := c + dir3 * BAY * 0.5 + Vector3(0, (h + 1) * FLOOR_H, 0)
					var axis := dir3.cross(Vector3.UP).normalized()
					var b := Basis(axis, deg_to_rad(rng.randf_range(25, 65)))
					_mm_add(mesh_slab, Transform3D(b, hinge + b * (-dir3 * BAY * 0.5)))
					_rebar(hinge, 3)
					break
			var miss := floors - h
			if miss > 0:
				if miss >= 2 and rng.randf() < 0.85:
					_mound(c, BAY * rng.randf_range(1.0, 1.4), miss * rng.randf_range(0.45, 0.7))
				var perimeter := i == 0 or j == 0 or i == nx - 1 or j == nz - 1
				var spill := Vector3(c.x, 0, c.z).normalized()
				for k in miss * 5 + 2:
					var p := c + Vector3(rng.randf_range(-BAY * 0.7, BAY * 0.7), 0, rng.randf_range(-BAY * 0.7, BAY * 0.7))
					if perimeter:
						p += spill * rng.randf_range(0.0, 6.0)
					p.y = rng.randf_range(0.0, miss * 0.35)
					_chunk(p, 0.3, 1.7)
					if rng.randf() < 0.15:
						_rebar(p, 2)

	# Fachadas (paneles con ventanas) en los 4 lados.
	for side in 4:
		var count := nx if side < 2 else nz
		for k in count:
			var ci: int
			var cj: int
			var pos: Vector3
			var rot := 0.0
			var out: Vector3
			match side:
				0:
					ci = k; cj = 0; pos = Vector3(cell.call(k, 0).x, 0, -hz); out = Vector3(0, 0, -1)
				1:
					ci = k; cj = nz - 1; pos = Vector3(cell.call(k, 0).x, 0, hz); out = Vector3(0, 0, 1)
				2:
					ci = 0; cj = k; pos = Vector3(-hx, 0, cell.call(0, k).z); rot = PI / 2; out = Vector3(-1, 0, 0)
				_:
					ci = nx - 1; cj = k; pos = Vector3(hx, 0, cell.call(0, k).z); rot = PI / 2; out = Vector3(1, 0, 0)
			var h: int = H[ci][cj]
			var wb := Basis(Vector3.UP, rot)
			var tangent := wb * Vector3.RIGHT
			for L in h:
				var p_miss := 0.05 + 0.3 * severity * float(L) / floors
				if L == h - 1 and h < floors:
					p_miss += 0.3
				var ppos := pos + Vector3(0, L * FLOOR_H + FLOOR_H * 0.5, 0)
				if rng.randf() < p_miss:
					if rng.randf() < 0.6:
						var s := Vector3(rng.randf_range(0.8, 3.6), rng.randf_range(0.3, 1.1), 0.3)
						var cp := pos + tangent * rng.randf_range(-1.0, 1.0) * (BAY - s.x) * 0.5 + Vector3(0, L * FLOOR_H + s.y * 0.5, 0)
						_mm_add(mesh_chunk, Transform3D(wb * Basis.from_scale(s), cp))
					if L > 0 and rng.randf() < 0.3:
						var fp := pos + out * rng.randf_range(2.2, 5.0) + tangent * rng.randf_range(-1.5, 1.5) + Vector3(0, 0.2, 0)
						var fb := wb * Basis(Vector3.RIGHT, deg_to_rad(90 + rng.randf_range(-12, 12))) * Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(-20, 20)))
						_mm_add(mesh_panel, Transform3D(fb, fp))
					for q in 2:
						_chunk(pos + out * rng.randf_range(0.5, 4.0) + tangent * rng.randf_range(-2, 2), 0.3, 1.0)
				else:
					_mm_add(mesh_panel, Transform3D(wb, ppos))
			if h < floors and rng.randf() < 0.75:
				var s2 := Vector3(rng.randf_range(0.8, BAY), rng.randf_range(0.4, 2.2), 0.3)
				var jp := pos + tangent * rng.randf_range(-1.0, 1.0) * (BAY - s2.x) * 0.5 + Vector3(0, h * FLOOR_H + s2.y * 0.5, 0)
				_mm_add(mesh_chunk, Transform3D(wb * Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(-12, 12))) * Basis.from_scale(s2), jp))
			if h == floors:
				_mm_add(mesh_parapet, Transform3D(wb, pos + Vector3(0, floors * FLOOR_H + 0.45, 0)))

	# Columnas estructurales (rotas con varilla expuesta donde hubo colapso).
	for a in nx + 1:
		for b in nz + 1:
			var hmax := 0
			for di in [-1, 0]:
				for dj in [-1, 0]:
					var ii: int = a + di
					var jj: int = b + dj
					if ii >= 0 and ii < nx and jj >= 0 and jj < nz:
						hmax = maxi(hmax, H[ii][jj])
			var vpos := Vector3(a * BAY - hx, 0, b * BAY - hz)
			var stub := 0.0
			if hmax < floors:
				stub = rng.randf_range(0.4, 2.6)
			var total := hmax * FLOOR_H + stub
			if total > 0.05:
				_mm_add(mesh_col, Transform3D(Basis.from_scale(Vector3(1, total, 1)), vpos + Vector3(0, total * 0.5, 0)))
			if stub > 0.0:
				_rebar(vpos + Vector3(0, total, 0), rng.randi_range(2, 4))

	# Colisión simplificada por celda.
	var body := StaticBody3D.new()
	body.name = "Collision"
	holder.add_child(body)
	for i in nx:
		for j in nz:
			var h: int = H[i][j]
			if h <= 0:
				continue
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(BAY, h * FLOOR_H, BAY)
			cs.shape = shape
			cs.position = cell.call(i, j) + Vector3(0, h * FLOOR_H * 0.5, 0)
			body.add_child(cs)

	_flush(holder)


# ------------------------------------------------------ puerta y reja

func _make_gate_and_fence() -> void:
	var g := Node3D.new()
	g.name = "CampusGate"
	_root.add_child(g)
	var z := 23.0

	for sx in [-1.0, 1.0]:
		_box(g, Vector3(2.2, 8.5, 2.2), _xf(Vector3(sx * 8.5, 4.25, z)), m_stone, true)
		_box(g, Vector3(2.6, 0.6, 2.6), _xf(Vector3(sx * 8.5, 0.3, z)), m_concrete_dark)
	_box(g, Vector3(2.8, 0.5, 2.8), _xf(Vector3(-8.5, 8.75, z)), m_stone)
	# Remate derecho caído al suelo
	_box(g, Vector3(2.8, 0.5, 2.8), _xf(Vector3(10.6, 0.5, z - 2.0), Vector3(25, 40, 15)), m_stone, true)

	# Dintel izquierdo aún en pie, en voladizo y hundido
	var left := Node3D.new()
	left.transform = _xf(Vector3(-5.0, 8.1, z), Vector3(0, 0, -3))
	g.add_child(left)
	_box(left, Vector3(9.4, 1.4, 1.3), Transform3D.IDENTITY, m_stone, true)
	_sign_text(left, "UNIVERSI", Vector3(0.6, 0.0, 0.67), false)
	_sign_text(left, "UNIVERSI", Vector3(-0.6, 0.0, -0.67), true)
	_rebar(left.position + Vector3(4.7, 0, 0), 4)

	# Dintel derecho caído en diagonal, recargado en el pilar
	var a := Vector3(7.3, 3.4, z - 0.4)
	var b := Vector3(-0.2, 0.55, z - 3.6)
	var dir := (b - a).normalized()
	var right := Node3D.new()
	right.transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, dir)), (a + b) * 0.5)
	g.add_child(right)
	var length := a.distance_to(b)
	_box(right, Vector3(length, 1.4, 1.3), Transform3D.IDENTITY, m_stone, true)
	_sign_text(right, "DAD", Vector3(-length * 0.28, 0.0, 0.67), false)
	_rebar(b, 3)
	for k in 10:
		_chunk(b + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)), 0.2, 0.8)

	# Reja perimetral de hierro a ambos lados
	for sx in [-1.0, 1.0]:
		_fence(sx * 9.7, sx * 40.0, z)


func _sign_text(parent: Node3D, text: String, pos: Vector3, back: bool) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 110
	l.pixel_size = 0.01
	l.modulate = Color(0.78, 0.74, 0.62)
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = pos
	if back:
		l.rotation.y = PI
	parent.add_child(l)


func _fence(x0: float, x1: float, z: float) -> void:
	var sgn := signf(x1 - x0)
	var n := int(absf(x1 - x0) / 2.5)
	for s in n:
		var sx0 := x0 + sgn * s * 2.5
		_mm_add(mesh_post, _xf(Vector3(sx0, 1.35, z)))
		if rng.randf() < 0.12:
			continue
		var tilt := 0.0 if rng.randf() < 0.6 else rng.randf_range(-40.0, 25.0)
		var b := Basis(Vector3.RIGHT, deg_to_rad(tilt))
		var base := Vector3(sx0 + sgn * 1.25, 0, z)
		_mm_add(mesh_rail, Transform3D(b, base + b * Vector3(0, 0.35, 0)))
		_mm_add(mesh_rail, Transform3D(b, base + b * Vector3(0, 2.1, 0)))
		for t in 13:
			if rng.randf() < 0.08:
				continue
			var bend := Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(-4, 4)))
			_mm_add(mesh_bar, Transform3D(b * bend, base + b * Vector3(-1.2 + t * 0.2, 1.15, 0)))


# ---------------------------------------------------------------- estatua

func _make_statue() -> void:
	var s := Node3D.new()
	s.name = "BrokenStatue"
	s.position = Vector3(0, 0, -18.5)
	_root.add_child(s)
	_box(s, Vector3(4.4, 0.5, 4.4), _xf(Vector3(0, 0.25, 0)), m_concrete_dark, true)
	_box(s, Vector3(3.6, 2.4, 3.6), _xf(Vector3(0, 1.7, 0)), m_stone, true)
	_cyl(s, 0.42, 0.5, 2.3, _xf(Vector3(-0.6, 4.05, 0), Vector3(0, 0, 4)), m_bronze)
	_cyl(s, 0.38, 0.5, 1.4, _xf(Vector3(0.6, 3.6, 0.1), Vector3(-6, 0, -3)), m_bronze)
	_rebar(s.position + Vector3(0.6, 4.3, 0.1), 2)
	# Torso caído
	_cyl(s, 0.85, 0.95, 2.9, _xf(Vector3(3.6, 0.9, 3.0), Vector3(0, 35, 90)), m_bronze)
	_cyl(s, 0.28, 0.25, 2.0, _xf(Vector3(5.4, 0.3, 1.9), Vector3(0, -20, 85)), m_bronze)
	var head := SphereMesh.new()
	head.radius = 0.55
	head.height = 1.1
	_mi(s, head, _xf(Vector3(6.2, 0.5, 4.6)), m_bronze)
	_collider(s, Vector3(3.0, 1.8, 1.8), _xf(Vector3(3.6, 0.9, 3.0), Vector3(0, 35, 0)))
	var plaque := Label3D.new()
	plaque.text = "ALMA MATER\nMCMLII"
	plaque.font_size = 40
	plaque.pixel_size = 0.01
	plaque.modulate = Color(0.55, 0.6, 0.5)
	plaque.shaded = true
	plaque.double_sided = false
	plaque.position = Vector3(0, 1.8, 1.82)
	s.add_child(plaque)
	for k in 14:
		_chunk(s.position + Vector3(rng.randf_range(-3, 6), 0, rng.randf_range(-2, 5)), 0.15, 0.6)


# ---------------------------------------------------------------- faroles

func _make_lamps() -> void:
	var holder := Node3D.new()
	holder.name = "Lamps"
	_root.add_child(holder)
	var states := [0, 2, 0, 1, 3, 0, 1, 0]
	var angles := [30.0, 70.0, 110.0, 150.0, 210.0, 250.0, 290.0, 330.0]
	for k in angles.size():
		var a: float = deg_to_rad(angles[k])
		var pos := Vector3(sin(a), 0, cos(a)) * 23.2
		_lamp(holder, pos, states[k])


func _lamp(parent: Node3D, pos: Vector3, state: int) -> void:
	var l := Node3D.new()
	l.position = pos
	var d := -pos.normalized()
	var yaw := atan2(-d.z, d.x)
	l.rotation = Vector3(0, yaw, 0)
	if state == 2:
		l.rotation = Vector3(deg_to_rad(rng.randf_range(16, 28)), yaw, 0)
	elif state == 3:
		l.rotation = Vector3(deg_to_rad(84), yaw, 0)
		l.position.y = 0.12
	parent.add_child(l)
	_cyl(l, 0.16, 0.22, 0.6, _xf(Vector3(0, 0.3, 0)), m_iron)
	_cyl(l, 0.07, 0.1, 6.0, _xf(Vector3(0, 3.0, 0)), m_iron, 8)
	_box(l, Vector3(1.4, 0.08, 0.08), _xf(Vector3(0.65, 5.9, 0)), m_iron)
	_box(l, Vector3(0.6, 0.18, 0.32), _xf(Vector3(1.25, 5.8, 0)), m_iron)
	_box(l, Vector3(0.5, 0.04, 0.26), _xf(Vector3(1.25, 5.69, 0)), m_lamp_on if state == 0 else m_glass)
	if state == 0:
		var light := OmniLight3D.new()
		light.position = Vector3(1.25, 5.4, 0)
		light.light_color = Color(1.0, 0.62, 0.32)
		light.light_energy = 2.4
		light.omni_range = 14.0
		light.omni_attenuation = 1.4
		light.light_volumetric_fog_energy = 2.0
		light.set_script(FLICKER)
		light.set("base_energy", 2.4)
		light.set("dropout_chance", 0.004 if rng.randf() < 0.5 else 0.03)
		l.add_child(light)
	if state != 3:
		_collider(l, Vector3(0.4, 6.0, 0.4), _xf(Vector3(0, 3.0, 0)))


# -------------------------------------------------- autos, bancas, árboles

func _make_props() -> void:
	var p := Node3D.new()
	p.name = "Props"
	_root.add_child(p)

	# Autos dentro de la arena (cobertura) y sobre la avenida
	_car(p, Vector3(-14.5, 0, 7.0), 35.0, 0.0, Color(0.1, 0.18, 0.28), true)
	_car(p, Vector3(15.5, 0, -6.5), -60.0, 90.0, Color(0.5, 0.48, 0.45), false)
	_car(p, Vector3(-12.0, 0, 37.0), 8.0, 0.0, Color(0.45, 0.08, 0.06), false)
	_car(p, Vector3(5.5, 0, 40.5), 160.0, 180.0, Color(0.25, 0.27, 0.3), false)
	_car(p, Vector3(22.0, 0, 36.0), 170.0, 0.0, Color(0.2, 0.2, 0.2), true)
	_car(p, Vector3(-28.0, 0, 39.5), -15.0, 0.0, Color(0.6, 0.55, 0.3), true)
	_bus(p, Vector3(36.0, 0, 40.5), 12.0)

	# Bancas
	for ang in [50.0, 130.0, 230.0, 310.0]:
		var a := deg_to_rad(ang)
		var pos := Vector3(sin(a), 0, cos(a)) * 20.4
		_bench(p, pos, rad_to_deg(atan2(pos.x, pos.z)), rng.randf() < 0.4)

	# Jardineras con árboles muertos
	for ang in [90.0, 130.0, 170.0, 190.0, 230.0, 270.0]:
		var a := deg_to_rad(ang + rng.randf_range(-6, 6))
		var pos := Vector3(sin(a), 0, cos(a)) * 25.0
		_box(p, Vector3(2.4, 0.6, 2.4), _xf(pos + Vector3(0, 0.3, 0), Vector3(0, ang, 0)), m_concrete, true)
		_tree(p, pos + Vector3(0, 0.55, 0), Vector3.ZERO)
	# Árbol caído hacia dentro de la arena
	_tree(p, Vector3(-17.0, 0.3, -14.0), Vector3(84, 40, 0))
	_collider(p, Vector3(0.6, 0.6, 5.5), _xf(Vector3(-15.4, 0.4, -12.6), Vector3(0, 40, 0)))

	# Losas grandes caídas dentro de la arena (cobertura)
	_box(p, Vector3(6.0, 0.4, 4.0), _xf(Vector3(-9.0, 1.3, -13.5), Vector3(0, 25, 28)), m_concrete, true)
	_box(p, Vector3(5.0, 0.4, 3.5), _xf(Vector3(12.0, 1.0, 12.5), Vector3(0, -40, -22)), m_concrete, true)
	_rebar(Vector3(-11.6, 0.2, -14.6), 4)
	_rebar(Vector3(14.2, 0.1, 13.8), 3)

	# Barreras de concreto y conos
	for k in 9:
		var bp := Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(31.5, 44))
		if absf(bp.x) < 3.0:
			bp.x += 6.0
		var fallen := rng.randf() < 0.3
		_box(p, Vector3(2.6, 0.85, 0.6), _xf(bp + Vector3(0, 0.3 if fallen else 0.42, 0), Vector3(0 if not fallen else 90, rng.randf_range(-40, 40), 0)), m_concrete, true)
	for k in 8:
		var cp := Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(32, 44))
		var down := rng.randf() < 0.5
		_cyl(p, 0.03, 0.22, 0.75, _xf(cp + Vector3(0, 0.2 if down else 0.375, 0), Vector3(90 if down else 0, rng.randf_range(0, 360), 0)), m_cone, 8)

	# Señal direccional doblada
	var sg := Node3D.new()
	sg.position = Vector3(12.0, 0, 26.0)
	sg.rotation_degrees = Vector3(14, -20, 6)
	p.add_child(sg)
	_box(sg, Vector3(0.12, 3.2, 0.12), _xf(Vector3(0, 1.6, 0)), m_iron)
	_box(sg, Vector3(2.6, 0.6, 0.06), _xf(Vector3(0.9, 2.8, 0)), _std(Color(0.08, 0.22, 0.14), 0.5, 0.3))
	var t := Label3D.new()
	t.text = "FAC. DE INGENIERÍA  →"
	t.font_size = 26
	t.pixel_size = 0.01
	t.modulate = Color(0.85, 0.85, 0.8)
	t.shaded = true
	t.position = Vector3(0.9, 2.8, 0.04)
	sg.add_child(t)

	# Escombros pequeños por toda la plaza
	for k in 90:
		var a := rng.randf() * TAU
		var r := rng.randf_range(3.0, 21.5)
		_chunk(Vector3(sin(a) * r, 0, cos(a) * r), 0.12, 0.45)
	for k in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(15.0, 21.0)
		_chunk(Vector3(sin(a) * r, 0, cos(a) * r), 0.7, 1.5)


func _car(parent: Node3D, pos: Vector3, yaw: float, roll: float, color: Color, burnt: bool) -> void:
	var c := Node3D.new()
	c.position = pos
	if roll >= 170.0:
		c.position.y = 1.7
	elif roll >= 80.0:
		c.position.y = 0.92
	c.rotation_degrees = Vector3(roll, yaw, 0)
	parent.add_child(c)
	var body_mat: Material = m_burnt if burnt else _std(color, 0.25, 0.6)
	_box(c, Vector3(4.3, 0.8, 1.85), _xf(Vector3(0, 0.68, 0)), body_mat)
	_box(c, Vector3(2.3, 0.62, 1.65), _xf(Vector3(-0.25, 1.38, 0), Vector3(0, 0, 0)), m_burnt if burnt else body_mat)
	_box(c, Vector3(2.32, 0.42, 1.67), _xf(Vector3(-0.25, 1.4, 0)), m_glass)
	for wx in [-1.38, 1.38]:
		for wz in [-0.86, 0.86]:
			if burnt and rng.randf() < 0.3:
				continue
			_cyl(c, 0.38, 0.38, 0.28, _xf(Vector3(wx, 0.38, wz), Vector3(90, 0, 0)), m_tire, 12)
	_collider(c, Vector3(4.3, 1.7, 1.9), _xf(Vector3(0, 0.85, 0)))


func _bus(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var b := Node3D.new()
	b.position = pos + Vector3(0, 1.35, 0)
	b.rotation_degrees = Vector3(90, yaw, 0)
	parent.add_child(b)
	_box(b, Vector3(11.0, 3.0, 2.6), _xf(Vector3(0, 1.6, 0)), _std(Color(0.55, 0.42, 0.1), 0.35, 0.5))
	_box(b, Vector3(9.0, 0.9, 2.62), _xf(Vector3(0.6, 2.3, 0)), m_glass)
	_collider(b, Vector3(11.0, 3.0, 2.6), _xf(Vector3(0, 1.6, 0)))


func _bench(parent: Node3D, pos: Vector3, yaw: float, knocked: bool) -> void:
	var b := Node3D.new()
	b.position = pos
	b.rotation_degrees = Vector3(0 if not knocked else -80, yaw + rng.randf_range(-10, 10), 0)
	if knocked:
		b.position.y = 0.3
	parent.add_child(b)
	_box(b, Vector3(2.0, 0.08, 0.55), _xf(Vector3(0, 0.45, 0)), m_wood)
	_box(b, Vector3(2.0, 0.45, 0.06), _xf(Vector3(0, 0.75, -0.28), Vector3(-12, 0, 0)), m_wood)
	for lx in [-0.85, 0.85]:
		_box(b, Vector3(0.08, 0.45, 0.5), _xf(Vector3(lx, 0.22, 0)), m_iron)


func _tree(parent: Node3D, pos: Vector3, rot: Vector3) -> void:
	var t := Node3D.new()
	t.position = pos
	t.rotation_degrees = rot
	parent.add_child(t)
	var h := rng.randf_range(4.5, 6.5)
	_cyl(t, 0.12, 0.28, h, _xf(Vector3(0, h * 0.5, 0), Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))), m_wood, 7)
	for k in rng.randi_range(4, 6):
		var by := rng.randf_range(h * 0.45, h * 0.9)
		var bl := rng.randf_range(1.2, 2.6)
		var ang := rng.randf_range(0, 360)
		var b := Basis(Vector3.UP, deg_to_rad(ang)) * Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(35, 65)))
		var dir := b * Vector3.UP
		_mi(t, _branch_mesh(bl), Transform3D(b, Vector3(0, by, 0) + dir * bl * 0.5), m_wood)


func _branch_mesh(length: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.025
	c.bottom_radius = 0.08
	c.height = length
	c.radial_segments = 5
	c.rings = 1
	return c


# ------------------------------------------------ borde de la arena

func _make_arena_edge() -> void:
	# Montículos de escombro que cierran visualmente la arena
	for k in 26:
		var a := rng.randf_range(0.0, TAU)
		if absf(wrapf(a, -PI, PI)) < 0.55:
			continue
		var r := rng.randf_range(27.0, 32.0)
		var c := Vector3(sin(a) * r, 0, cos(a) * r)
		_mound(c, rng.randf_range(3.0, 6.0), rng.randf_range(0.8, 2.2))
		for q in 8:
			_chunk(c + Vector3(rng.randf_range(-3, 3), rng.randf_range(0, 1.2), rng.randf_range(-3, 3)), 0.3, 1.4)
		if rng.randf() < 0.3:
			_rebar(c + Vector3(0, 1.0, 0), 3)

	# Muro invisible circular que encierra la pelea
	var walls := StaticBody3D.new()
	walls.name = "ArenaBounds"
	_root.add_child(walls)
	var n := 40
	var seg := 2.0 * arena_wall_radius * sin(PI / n) + 0.6
	for i in n:
		var a := TAU * i / n
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(seg, 14.0, 1.0)
		cs.shape = shape
		cs.transform = Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0, cos(a)) * (arena_wall_radius + 0.5) + Vector3(0, 7, 0))
		walls.add_child(cs)

	var probe := ReflectionProbe.new()
	probe.name = "PlazaReflections"
	probe.position = Vector3(0, 6, 0)
	probe.size = Vector3(90, 30, 90)
	probe.box_projection = false
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.8
	_root.add_child(probe)


# -------------------------------------------------------- fuego y humo

func _make_fires_and_smoke() -> void:
	var fx := Node3D.new()
	fx.name = "FireAndSmoke"
	_root.add_child(fx)
	for f in [
		[Vector3(-38.5, 0.5, -28.0), 1.0],
		[Vector3(9.0, 0.4, -41.0), 1.3],
		[Vector3(43.0, 0.4, 5.0), 0.9],
		[Vector3(22.0, 1.1, 36.0), 0.8],
	]:
		_fire(fx, f[0], f[1])
		_smoke(fx, f[0] + Vector3(0, 1.0, 0), 0.6)
	_smoke(fx, Vector3(-30, 4, -100), 2.2)
	_smoke(fx, Vector3(62, 4, -62), 1.8)
	_smoke(fx, Vector3(-70, 4, 45), 1.5)


func _soft_tex(colors: PackedColorArray, offsets: PackedFloat32Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _fire(parent: Node3D, pos: Vector3, size: float) -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = int(48 * size)
	p.lifetime = 0.9
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5 * size
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0.3, 1.0, 0)
	pm.scale_min = 0.5 * size
	pm.scale_max = 1.1 * size
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var cg := Gradient.new()
	cg.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	cg.colors = PackedColorArray([Color(1.0, 0.85, 0.4, 1), Color(1.0, 0.4, 0.08, 0.8), Color(0.4, 0.05, 0.0, 0)])
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	pm.color_ramp = cgt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 1.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _soft_tex(PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)]), PackedFloat32Array([0.0, 1.0]))
	m.albedo_color = Color(2.5, 2.5, 2.5, 1)
	q.material = m
	p.draw_pass_1 = q
	parent.add_child(p)

	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 1.0, 0)
	light.light_color = Color(1.0, 0.45, 0.15)
	light.light_energy = 3.0 * size
	light.omni_range = 9.0 * size
	light.light_volumetric_fog_energy = 3.0
	light.set_script(FLICKER)
	light.set("base_energy", 3.0 * size)
	light.set("speed", 9.0)
	light.set("dropout_chance", 0.0)
	parent.add_child(light)


func _smoke(parent: Node3D, pos: Vector3, size: float) -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = int(36 * size) + 10
	p.lifetime = 12.0
	p.preprocess = 12.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 90, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.0 * size
	pm.direction = Vector3(0.25, 1, 0.1)
	pm.spread = 10.0
	pm.initial_velocity_min = 2.0 * size
	pm.initial_velocity_max = 3.0 * size
	pm.gravity = Vector3(0.35, 0.15, 0.1)
	pm.damping_min = 0.1
	pm.damping_max = 0.2
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 3.0 * size
	pm.scale_max = 5.0 * size
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var cg := Gradient.new()
	cg.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	cg.colors = PackedColorArray([Color(0.1, 0.09, 0.09, 0), Color(0.1, 0.1, 0.1, 0.55), Color(0.16, 0.17, 0.18, 0.3), Color(0.2, 0.21, 0.22, 0)])
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	pm.color_ramp = cgt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _soft_tex(PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)]), PackedFloat32Array([0.0, 0.45, 1.0]))
	m.roughness = 1.0
	q.material = m
	p.draw_pass_1 = q
	parent.add_child(p)
