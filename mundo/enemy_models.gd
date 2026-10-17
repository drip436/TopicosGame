extends RefCounted
## Modelos procedurales de los enemigos del campus. Cada constructor devuelve:
##   {"root": Node3D, "J": {nombre: Node3D articulación}, "eyes": [materiales de ojos],
##    "meshes": [MeshInstance3D], "kind": "biped" | "quad" | "mech"}
## Las articulaciones se animan desde enemy.gd (el brazo cuelga hacia -Y; girar
## +X lo levanta hacia adelante, y el modelo mira hacia -Z).

static var _unit_box: BoxMesh
static var _unit_sph: SphereMesh
static var _unit_cyl: CylinderMesh
static var _unit_cone: CylinderMesh
static var _mats := {}


# ------------------------------------------------------------------ utilidades

static func mat(c: Color, rough := 0.6, metal := 0.0, emit := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%.2f" % [c.to_html(), rough, metal, emit.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


## Material de ojos: uno nuevo por enemigo (cambia de color al detectarte).
static func eye_mat(c: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _meshes() -> void:
	if _unit_box:
		return
	_unit_box = BoxMesh.new()
	_unit_sph = SphereMesh.new()
	_unit_sph.radius = 0.5
	_unit_sph.height = 1.0
	_unit_sph.radial_segments = 12
	_unit_sph.rings = 6
	_unit_cyl = CylinderMesh.new()
	_unit_cyl.top_radius = 0.5
	_unit_cyl.bottom_radius = 0.5
	_unit_cyl.height = 1.0
	_unit_cyl.radial_segments = 10
	_unit_cyl.rings = 1
	_unit_cone = CylinderMesh.new()
	_unit_cone.top_radius = 0.0
	_unit_cone.bottom_radius = 0.5
	_unit_cone.height = 1.0
	_unit_cone.radial_segments = 8
	_unit_cone.rings = 1


static func _add(d: Dictionary, parent: Node3D, mesh: Mesh, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = size
	parent.add_child(mi)
	d["meshes"].append(mi)
	return mi


static func box(d: Dictionary, parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	_meshes()
	return _add(d, parent, _unit_box, size, pos, m, rot)


static func sph(d: Dictionary, parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	_meshes()
	return _add(d, parent, _unit_sph, size, pos, m, rot)


static func cyl(d: Dictionary, parent: Node3D, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	_meshes()
	return _add(d, parent, _unit_cyl, Vector3(r * 2.0, h, r * 2.0), pos, m, rot)


static func cone(d: Dictionary, parent: Node3D, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	_meshes()
	return _add(d, parent, _unit_cone, Vector3(r * 2.0, h, r * 2.0), pos, m, rot)


static func joint(d: Dictionary, parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = n
	j.position = pos
	parent.add_child(j)
	d["J"][n] = j
	return j


static func _new(kind: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "Modelo"
	return {"root": root, "J": {}, "eyes": [], "meshes": [], "kind": kind}


# ------------------------------------------------------------------ robots

## Robot humanoide. s = escala; weapon: "", "hacha", "espada", "laser".
static func robot(s: float, weapon: String, rng: RandomNumberGenerator) -> Dictionary:
	var d := _new("biped")
	var shells := [Color(0.42, 0.44, 0.46), Color(0.55, 0.5, 0.38), Color(0.3, 0.33, 0.38), Color(0.6, 0.6, 0.58)]
	var shell := mat(shells[rng.randi() % shells.size()].darkened(rng.randf_range(0.0, 0.2)), 0.5, 0.6)
	var dark := mat(Color(0.1, 0.1, 0.11), 0.6, 0.5)
	var joint_m := mat(Color(0.2, 0.2, 0.22), 0.4, 0.8)
	var accent := mat(Color(0.75, 0.55, 0.1) if weapon == "" else Color(0.6, 0.08, 0.06), 0.5, 0.3)
	var eye := eye_mat(Color(1.0, 0.6, 0.15), 2.5)
	d["eyes"].append(eye)
	var R: Node3D = d["root"]
	var hip := joint(d, R, "hip", Vector3(0, 0.75 * s, 0))
	var torso := joint(d, hip, "torso", Vector3(0, 0.05 * s, 0))
	var heavy := weapon != ""
	var tw := (0.62 if not heavy else 0.78) * s
	box(d, torso, Vector3(tw, 0.55 * s, 0.44 * s), Vector3(0, 0.32 * s, 0), shell)
	box(d, torso, Vector3(tw * 0.7, 0.2 * s, 0.4 * s), Vector3(0, 0.02 * s, 0), dark)
	box(d, torso, Vector3(tw * 0.5, 0.18 * s, 0.05 * s), Vector3(0, 0.38 * s, -0.23 * s), accent)
	# Núcleo brillante en el pecho
	cyl(d, torso, 0.07 * s, 0.04 * s, Vector3(0, 0.28 * s, -0.235 * s), eye, Vector3(90, 0, 0))
	if heavy:
		for sx: float in [-1.0, 1.0]:
			box(d, torso, Vector3(0.3 * s, 0.14 * s, 0.4 * s), Vector3(sx * tw * 0.55, 0.62 * s, 0), accent, Vector3(0, 0, sx * -12))
	var head := joint(d, torso, "head", Vector3(0, 0.62 * s, 0))
	box(d, head, Vector3(0.36 * s, 0.28 * s, 0.34 * s), Vector3(0, 0.15 * s, 0), shell)
	box(d, head, Vector3(0.3 * s, 0.07 * s, 0.04 * s), Vector3(0, 0.17 * s, -0.17 * s), eye)
	cyl(d, head, 0.012 * s, 0.25 * s, Vector3(0.12 * s, 0.4 * s, 0.05 * s), dark)
	sph(d, head, Vector3.ONE * 0.05 * s, Vector3(0.12 * s, 0.53 * s, 0.05 * s), eye)
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var arm := joint(d, torso, "arm_" + side, Vector3(sx * (tw * 0.5 + 0.08 * s), 0.5 * s, 0))
		sph(d, arm, Vector3.ONE * 0.17 * s, Vector3.ZERO, joint_m)
		box(d, arm, Vector3(0.14 * s, 0.38 * s, 0.14 * s), Vector3(0, -0.2 * s, 0), shell)
		var fore := joint(d, arm, "fore_" + side, Vector3(0, -0.4 * s, 0))
		sph(d, fore, Vector3.ONE * 0.13 * s, Vector3.ZERO, joint_m)
		box(d, fore, Vector3(0.16 * s, 0.34 * s, 0.16 * s), Vector3(0, -0.18 * s, 0), shell)
		var hand := joint(d, fore, "hand_" + side, Vector3(0, -0.38 * s, 0))
		box(d, hand, Vector3(0.12 * s, 0.1 * s, 0.12 * s), Vector3(0, -0.02 * s, 0), dark)
		for k in 2:
			box(d, hand, Vector3(0.03 * s, 0.12 * s, 0.03 * s), Vector3((k - 0.5) * 0.06 * s, -0.1 * s, -0.04 * s), dark, Vector3(20, 0, 0))
		var leg := joint(d, hip, "leg_" + side, Vector3(sx * 0.17 * s, 0, 0))
		box(d, leg, Vector3(0.17 * s, 0.38 * s, 0.17 * s), Vector3(0, -0.19 * s, 0), shell)
		var shin := joint(d, leg, "shin_" + side, Vector3(0, -0.38 * s, 0))
		sph(d, shin, Vector3.ONE * 0.13 * s, Vector3.ZERO, joint_m)
		box(d, shin, Vector3(0.15 * s, 0.34 * s, 0.15 * s), Vector3(0, -0.18 * s, 0), shell)
		box(d, shin, Vector3(0.18 * s, 0.06 * s, 0.3 * s), Vector3(0, -0.36 * s, -0.05 * s), dark)
	var hand_r: Node3D = d["J"]["hand_r"]
	match weapon:
		"hacha":
			# El arma sigue la línea del brazo (-Y de la mano)
			var w := joint(d, hand_r, "weapon", Vector3(0, -0.04 * s, 0))
			cyl(d, w, 0.04 * s, 1.9 * s, Vector3(0, -0.7 * s, 0), mat(Color(0.25, 0.18, 0.12), 0.8))
			var blade := mat(Color(0.55, 0.56, 0.58), 0.35, 0.85)
			box(d, w, Vector3(0.06 * s, 0.7 * s, 0.75 * s), Vector3(0, -1.35 * s, -0.42 * s), blade)
			box(d, w, Vector3(0.07 * s, 0.8 * s, 0.07 * s), Vector3(0, -1.35 * s, -0.8 * s), mat(Color(0.85, 0.85, 0.82), 0.2, 0.9))
			box(d, w, Vector3(0.12 * s, 0.3 * s, 0.22 * s), Vector3(0, -1.35 * s, 0), dark)
		"espada":
			var w := joint(d, hand_r, "weapon", Vector3(0, -0.04 * s, 0))
			box(d, w, Vector3(0.4 * s, 0.07 * s, 0.09 * s), Vector3(0, -0.06 * s, 0), dark)
			box(d, w, Vector3(0.05 * s, 1.5 * s, 0.13 * s), Vector3(0, -0.85 * s, 0), mat(Color(0.7, 0.72, 0.76), 0.25, 0.9))
			var edge := eye_mat(Color(0.4, 0.8, 1.0), 2.0)
			box(d, w, Vector3(0.02 * s, 1.45 * s, 0.03 * s), Vector3(0, -0.85 * s, -0.07 * s), edge)
			d["eyes"].append(edge)
		"laser":
			var w := joint(d, hand_r, "weapon", Vector3(0, -0.04 * s, 0))
			box(d, w, Vector3(0.13 * s, 0.5 * s, 0.17 * s), Vector3(0, -0.18 * s, 0), dark)
			box(d, w, Vector3(0.08 * s, 0.2 * s, 0.1 * s), Vector3(0, -0.05 * s, 0.12 * s), dark)
			cyl(d, w, 0.045 * s, 0.35 * s, Vector3(0, -0.55 * s, 0), joint_m)
			var muzzle := eye_mat(Color(1.0, 0.2, 0.15), 3.0)
			cyl(d, w, 0.036 * s, 0.03 * s, Vector3(0, -0.73 * s, 0), muzzle)
			d["eyes"].append(muzzle)
			joint(d, w, "muzzle", Vector3(0, -0.78 * s, 0))
	return d


## Mecha de combate gigante (unos 5 m).
static func mech(rng: RandomNumberGenerator) -> Dictionary:
	var d := _new("mech")
	var s := 1.0
	var paint: Color = [Color(0.35, 0.38, 0.3), Color(0.5, 0.42, 0.25), Color(0.32, 0.34, 0.4)][rng.randi() % 3]
	var shell := mat(paint, 0.55, 0.55)
	var dark := mat(Color(0.09, 0.09, 0.1), 0.6, 0.6)
	var steel := mat(Color(0.4, 0.4, 0.42), 0.35, 0.85)
	var hazard := mat(Color(0.85, 0.65, 0.1), 0.5, 0.2)
	var eye := eye_mat(Color(1.0, 0.25, 0.1), 4.0)
	d["eyes"].append(eye)
	var R: Node3D = d["root"]
	var hip := joint(d, R, "hip", Vector3(0, 2.4, 0))
	box(d, hip, Vector3(1.4, 0.5, 1.0), Vector3.ZERO, dark)
	var torso := joint(d, hip, "torso", Vector3(0, 0.3, 0))
	box(d, torso, Vector3(2.4, 1.5, 1.9), Vector3(0, 0.85, 0.1), shell)
	box(d, torso, Vector3(1.8, 0.5, 0.2), Vector3(0, 1.1, -0.86), dark)
	box(d, torso, Vector3(1.6, 0.16, 0.06), Vector3(0, 1.12, -0.97), eye)
	box(d, torso, Vector3(2.5, 0.2, 2.0), Vector3(0, 1.65, 0.1), hazard)
	box(d, torso, Vector3(1.2, 0.9, 0.8), Vector3(0, 0.9, 1.25), dark)
	for k in 3:
		cyl(d, torso, 0.12, 1.0, Vector3(-0.4 + k * 0.4, 1.6, 1.4), steel)
	joint(d, torso, "head", Vector3(0, 1.7, -0.2))
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var arm := joint(d, torso, "arm_" + side, Vector3(sx * 1.45, 1.2, 0))
		sph(d, arm, Vector3.ONE * 0.7, Vector3.ZERO, steel)
		box(d, arm, Vector3(0.9, 0.6, 1.0), Vector3(sx * 0.15, 0.25, 0), shell)
		box(d, arm, Vector3(0.45, 1.1, 0.45), Vector3(0, -0.6, 0), dark)
		var fore := joint(d, arm, "fore_" + side, Vector3(0, -1.2, 0))
		sph(d, fore, Vector3.ONE * 0.5, Vector3.ZERO, steel)
		var hand := joint(d, fore, "hand_" + side, Vector3(0, -1.3, 0))
		if side == "r":
			# Cañón doble
			box(d, fore, Vector3(0.7, 1.3, 0.7), Vector3(0, -0.65, 0), shell)
			for k in 2:
				cyl(d, hand, 0.13, 0.9, Vector3((k - 0.5) * 0.3, -0.3, 0), steel)
			var muzzle := eye_mat(Color(1.0, 0.5, 0.15), 3.0)
			for k in 2:
				cyl(d, hand, 0.09, 0.05, Vector3((k - 0.5) * 0.3, -0.77, 0), muzzle)
			d["eyes"].append(muzzle)
			joint(d, hand, "muzzle", Vector3(0, -0.85, 0))
		else:
			box(d, fore, Vector3(0.6, 1.2, 0.6), Vector3(0, -0.6, 0), shell)
			for k in 3:
				var claw := joint(d, hand, "claw%d" % k, Vector3((k - 1) * 0.22, 0, 0))
				box(d, claw, Vector3(0.12, 0.7, 0.18), Vector3(0, -0.3, -0.08), steel, Vector3(15, 0, (k - 1) * 10))
		var leg := joint(d, hip, "leg_" + side, Vector3(sx * 0.75, -0.1, 0))
		sph(d, leg, Vector3.ONE * 0.6, Vector3.ZERO, steel)
		box(d, leg, Vector3(0.55, 1.2, 0.6), Vector3(0, -0.6, 0), shell)
		var shin := joint(d, leg, "shin_" + side, Vector3(0, -1.2, 0))
		sph(d, shin, Vector3.ONE * 0.5, Vector3.ZERO, steel)
		box(d, shin, Vector3(0.5, 1.05, 0.55), Vector3(0, -0.5, 0.05), dark)
		box(d, shin, Vector3(0.9, 0.22, 1.3), Vector3(0, -1.08, -0.15), shell)
		box(d, shin, Vector3(0.95, 0.06, 0.1), Vector3(0, -1.0, -0.82), hazard)
	return d


# ------------------------------------------------------------------ mutantes

static func _flesh(rng: RandomNumberGenerator) -> Array:
	var tones := [Color(0.62, 0.38, 0.4), Color(0.5, 0.42, 0.36), Color(0.55, 0.5, 0.42), Color(0.42, 0.3, 0.38)]
	var t: Color = tones[rng.randi() % tones.size()]
	return [mat(t, 0.45, 0.0, t.darkened(0.6), 0.2), mat(t.darkened(0.45), 0.5), mat(Color(0.86, 0.82, 0.7), 0.4)]


static func _pustules(d: Dictionary, parent: Node3D, n: int, center: Vector3, ext: Vector3, size: float, glow: Material, rng: RandomNumberGenerator) -> void:
	for i in n:
		var p := center + Vector3(rng.randf_range(-ext.x, ext.x), rng.randf_range(-ext.y, ext.y), rng.randf_range(-ext.z, ext.z))
		sph(d, parent, Vector3.ONE * size * rng.randf_range(0.6, 1.3), p, glow)


## Mutante pequeño: rastrero de cuatro patas.
static func mutant_small(rng: RandomNumberGenerator) -> Dictionary:
	var d := _new("quad")
	var f := _flesh(rng)
	var skin: Material = f[0]
	var dark: Material = f[1]
	var bone: Material = f[2]
	var glow := eye_mat(Color(0.45, 1.0, 0.2), 2.5)
	d["eyes"].append(glow)
	var R: Node3D = d["root"]
	var hip := joint(d, R, "hip", Vector3(0, 0.5, 0))
	var torso := joint(d, hip, "torso", Vector3.ZERO)
	sph(d, torso, Vector3(0.55, 0.4, 0.95), Vector3(0, 0.05, 0), skin)
	sph(d, torso, Vector3(0.4, 0.3, 0.5), Vector3(0, 0.15, 0.25), dark)
	_pustules(d, torso, 5, Vector3(0, 0.2, 0.1), Vector3(0.18, 0.06, 0.3), 0.12, glow, rng)
	var head := joint(d, torso, "head", Vector3(0, 0.08, -0.5))
	sph(d, head, Vector3(0.36, 0.3, 0.4), Vector3(0, 0, -0.1), skin)
	var jaw := joint(d, head, "jaw", Vector3(0, -0.06, -0.05))
	sph(d, jaw, Vector3(0.3, 0.12, 0.32), Vector3(0, -0.05, -0.14), dark)
	for k in 4:
		cone(d, head, 0.025, 0.1, Vector3(-0.09 + k * 0.06, -0.06, -0.27), bone, Vector3(180, 0, 0))
	for k in 3:
		sph(d, head, Vector3.ONE * 0.06, Vector3(-0.08 + k * 0.08, 0.1, -0.24), glow)
	for leg in [["fl", -1, -1], ["fr", 1, -1], ["bl", -1, 1], ["br", 1, 1]]:
		var sx: float = leg[1]
		var sz: float = leg[2]
		var j := joint(d, torso, "leg_" + leg[0], Vector3(sx * 0.22, 0.0, sz * 0.3))
		box(d, j, Vector3(0.08, 0.36, 0.08), Vector3(sx * 0.12, 0.0, 0), skin, Vector3(0, 0, sx * -60))
		var sh := joint(d, j, "shin_" + leg[0], Vector3(sx * 0.27, 0.1, 0))
		box(d, sh, Vector3(0.06, 0.6, 0.06), Vector3(0, -0.28, 0), dark, Vector3(0, 0, sx * 12))
		cone(d, sh, 0.04, 0.12, Vector3(sx * 0.06, -0.6, 0), bone, Vector3(180, 0, 0))
	return d


## Mutante mediano: encorvado, brazos larguísimos con garras.
static func mutant_medium(rng: RandomNumberGenerator) -> Dictionary:
	var d := _new("biped")
	var f := _flesh(rng)
	var skin: Material = f[0]
	var dark: Material = f[1]
	var bone: Material = f[2]
	var glow := eye_mat(Color(0.45, 1.0, 0.2), 2.5)
	d["eyes"].append(glow)
	var R: Node3D = d["root"]
	var hip := joint(d, R, "hip", Vector3(0, 0.95, 0))
	sph(d, hip, Vector3(0.5, 0.35, 0.4), Vector3.ZERO, dark)
	var torso := joint(d, hip, "torso", Vector3(0, 0.1, 0))
	torso.rotation_degrees.x = 0.0
	var spine := Node3D.new()
	spine.rotation_degrees = Vector3(-28, 0, 0)
	torso.add_child(spine)
	sph(d, spine, Vector3(0.7, 0.85, 0.55), Vector3(0, 0.45, 0), skin)
	sph(d, spine, Vector3(0.5, 0.45, 0.5), Vector3(0.12, 0.6, 0.18), dark)
	_pustules(d, spine, 7, Vector3(0, 0.55, 0.2), Vector3(0.25, 0.3, 0.1), 0.14, glow, rng)
	for k in 4:
		cone(d, spine, 0.04, 0.18, Vector3(0, 0.3 + k * 0.17, 0.27), bone, Vector3(-60, 0, 0))
	var head := joint(d, torso, "head", Vector3(0, 0.75, -0.45))
	sph(d, head, Vector3(0.36, 0.34, 0.4), Vector3.ZERO, skin)
	var jaw := joint(d, head, "jaw", Vector3(0, -0.08, -0.05))
	sph(d, jaw, Vector3(0.32, 0.14, 0.36), Vector3(0, -0.06, -0.08), dark)
	for k in 5:
		cone(d, head, 0.025, 0.12, Vector3(-0.1 + k * 0.05, -0.1, -0.2), bone, Vector3(180, 0, 0))
	sph(d, head, Vector3.ONE * 0.08, Vector3(-0.08, 0.06, -0.18), glow)
	sph(d, head, Vector3.ONE * 0.05, Vector3(0.09, 0.08, -0.17), glow)
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var arm := joint(d, torso, "arm_" + side, Vector3(sx * 0.4, 0.6, -0.25))
		sph(d, arm, Vector3.ONE * 0.22, Vector3.ZERO, skin)
		box(d, arm, Vector3(0.13, 0.6, 0.13), Vector3(0, -0.3, 0), skin)
		var fore := joint(d, arm, "fore_" + side, Vector3(0, -0.6, 0))
		box(d, fore, Vector3(0.11, 0.65, 0.11), Vector3(0, -0.32, 0), dark)
		var hand := joint(d, fore, "hand_" + side, Vector3(0, -0.66, 0))
		for k in 3:
			cone(d, hand, 0.03, 0.32, Vector3((k - 1) * 0.06, -0.15, -0.03), bone, Vector3(180 - 15, 0, (k - 1) * 12))
		var leg := joint(d, hip, "leg_" + side, Vector3(sx * 0.2, 0, 0))
		box(d, leg, Vector3(0.18, 0.5, 0.18), Vector3(0, -0.25, 0), skin)
		var shin := joint(d, leg, "shin_" + side, Vector3(0, -0.5, 0))
		box(d, shin, Vector3(0.14, 0.45, 0.14), Vector3(0, -0.22, 0.04), dark)
		box(d, shin, Vector3(0.2, 0.06, 0.32), Vector3(0, -0.45, -0.06), dark)
	return d


## Mutante grande: mole de carne con un brazo gigante y sacos de veneno.
static func mutant_large(rng: RandomNumberGenerator) -> Dictionary:
	var d := _new("biped")
	var f := _flesh(rng)
	var skin: Material = f[0]
	var dark: Material = f[1]
	var bone: Material = f[2]
	var glow := eye_mat(Color(0.45, 1.0, 0.2), 2.5)
	d["eyes"].append(glow)
	var sac := mat(Color(0.35, 0.75, 0.15), 0.2, 0.0, Color(0.4, 1.0, 0.15), 1.4)
	var R: Node3D = d["root"]
	var hip := joint(d, R, "hip", Vector3(0, 1.25, 0))
	sph(d, hip, Vector3(1.2, 0.7, 0.9), Vector3.ZERO, dark)
	var torso := joint(d, hip, "torso", Vector3(0, 0.2, 0))
	sph(d, torso, Vector3(1.9, 1.7, 1.45), Vector3(0, 0.85, 0.05), skin)
	sph(d, torso, Vector3(1.1, 0.8, 0.9), Vector3(-0.3, 1.25, 0.45), dark)
	for k in 3:
		sph(d, torso, Vector3.ONE * rng.randf_range(0.45, 0.6), Vector3(-0.45 + k * 0.45, 1.45, 0.65), sac)
	_pustules(d, torso, 10, Vector3(0, 0.9, -0.3), Vector3(0.7, 0.6, 0.3), 0.16, glow, rng)
	for k in 5:
		cone(d, torso, 0.07, 0.35, Vector3(-0.6 + k * 0.3, 1.7, 0.2), bone, Vector3(-30, 0, 0))
	var head := joint(d, torso, "head", Vector3(0, 1.55, -0.65))
	sph(d, head, Vector3(0.5, 0.45, 0.5), Vector3.ZERO, skin)
	var jaw := joint(d, head, "jaw", Vector3(0, -0.12, -0.05))
	sph(d, jaw, Vector3(0.5, 0.2, 0.45), Vector3(0, -0.06, -0.1), dark)
	for k in 6:
		cone(d, jaw, 0.035, 0.15, Vector3(-0.15 + k * 0.06, 0.04, -0.28), bone)
	sph(d, head, Vector3.ONE * 0.1, Vector3(-0.12, 0.08, -0.22), glow)
	sph(d, head, Vector3.ONE * 0.1, Vector3(0.12, 0.08, -0.22), glow)
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var big: bool = side == "r"
		var k := 1.6 if big else 1.0
		var arm := joint(d, torso, "arm_" + side, Vector3(sx * 0.95, 1.2, -0.1))
		sph(d, arm, Vector3.ONE * 0.55 * k, Vector3.ZERO, skin)
		sph(d, arm, Vector3(0.35, 0.8, 0.35) * k, Vector3(0, -0.45 * k, 0), skin)
		var fore := joint(d, arm, "fore_" + side, Vector3(0, -0.85 * k, 0))
		sph(d, fore, Vector3(0.42, 0.95, 0.42) * k, Vector3(0, -0.45 * k, 0), dark)
		var hand := joint(d, fore, "hand_" + side, Vector3(0, -0.95 * k, 0))
		sph(d, hand, Vector3.ONE * 0.45 * k, Vector3.ZERO, dark)
		for c in 3:
			cone(d, hand, 0.05 * k, 0.3 * k, Vector3((c - 1) * 0.12 * k, -0.25 * k, -0.08), bone, Vector3(165, 0, (c - 1) * 15))
		if big:
			_pustules(d, fore, 4, Vector3(0, -0.4 * k, 0), Vector3(0.2, 0.3, 0.2) * k, 0.14, glow, rng)
		var leg := joint(d, hip, "leg_" + side, Vector3(sx * 0.45, 0, 0))
		sph(d, leg, Vector3(0.5, 0.75, 0.5), Vector3(0, -0.35, 0), skin)
		var shin := joint(d, leg, "shin_" + side, Vector3(0, -0.7, 0))
		sph(d, shin, Vector3(0.42, 0.6, 0.42), Vector3(0, -0.25, 0), dark)
		box(d, shin, Vector3(0.45, 0.14, 0.6), Vector3(0, -0.5, -0.1), dark)
	return d
