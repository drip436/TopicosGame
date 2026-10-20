extends Node3D
## Esqueleto y animaciones del jugador.
## El modelo (Modelo/modelo.glb) es una sola malla estática en pose T. Aquí:
##   1. Se crea un Skeleton3D con 17 huesos (cadera, columna, pecho, cuello, cabeza,
##      brazos, antebrazos, manos, muslos, espinillas y pies).
##   2. Se "pesa" cada vértice a sus huesos según la zona del cuerpo donde está
##      (con mezcla suave en codos, rodillas, hombros, cadera y cuello) y se arma
##      una malla con piel (skin) que se deforma con el esqueleto.
##   3. Cada cuadro se calcula la pose por capas: locomoción (quieto, caminar,
##      correr), acción (ataques y combos por arma, curar, hechizos, bloqueo,
##      disparar…) y cuerpo completo (rodada, aturdido, atrapado, muerte).
## Las armas y la armadura se pegan a los huesos con BoneAttachment3D.
##
## Convención de ángulos (grados), con el modelo mirando a -Z:
##   brazos  Vector3(adelante, giro, bajar)   bajar 0 = pose T, 80 = pegado al cuerpo
##   codo    flexión (+ dobla hacia adelante)
##   piernas x + adelante; rodilla y tobillo x
##   columna/pecho/cabeza x − se inclina hacia adelante; y gira; z ladea

const BONES := [
	["hips", "", Vector3(0, 0.92, 0)],
	["spine", "hips", Vector3(0, 1.04, 0)],
	["chest", "spine", Vector3(0, 1.2, 0)],
	["neck", "chest", Vector3(0, 1.39, 0)],
	["head", "neck", Vector3(0, 1.47, 0)],
	["arm_l", "chest", Vector3(-0.19, 1.3, 0)],
	["fore_l", "arm_l", Vector3(-0.47, 1.28, 0)],
	["hand_l", "fore_l", Vector3(-0.72, 1.27, 0)],
	["arm_r", "chest", Vector3(0.19, 1.3, 0)],
	["fore_r", "arm_r", Vector3(0.47, 1.28, 0)],
	["hand_r", "fore_r", Vector3(0.72, 1.27, 0)],
	["thigh_l", "hips", Vector3(-0.1, 0.88, 0)],
	["shin_l", "thigh_l", Vector3(-0.1, 0.48, 0)],
	["foot_l", "shin_l", Vector3(-0.1, 0.08, 0)],
	["thigh_r", "hips", Vector3(0.1, 0.88, 0)],
	["shin_r", "thigh_r", Vector3(0.1, 0.48, 0)],
	["foot_r", "shin_r", Vector3(0.1, 0.08, 0)],
]

var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var roll_pivot: Node3D
var _idx := {}
var _cur := {}           # hueso -> Vector3 (grados) actual
var _hips_y := 0.0
var _phase := 0.0
var _t := 0.0
var _attach := {}
var _held := {}          # objetos temporales en la mano (taza, lata)


# ======================================================================
#  Construcción
# ======================================================================

## Reemplaza el modelo estático por uno con esqueleto. `visual` es el nodo Visual
## del jugador y `model` la instancia del glb.
func build(visual: Node3D, model: Node3D) -> MeshInstance3D:
	name = "Rig"
	var src: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	# Transformación de la malla hasta el espacio de Visual
	var xf := Transform3D.IDENTITY
	var n: Node = src
	while n != visual and n != null:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	roll_pivot = Node3D.new()
	roll_pivot.name = "PivoteRodada"
	roll_pivot.position = Vector3(0, 0.55, 0)
	visual.add_child(roll_pivot)
	skeleton = Skeleton3D.new()
	skeleton.name = "Esqueleto"
	skeleton.position = Vector3(0, -0.55, 0)
	roll_pivot.add_child(skeleton)
	for b in BONES:
		var i := skeleton.add_bone(b[0])
		_idx[b[0]] = i
		var parent_pos := Vector3.ZERO
		if b[1] != "":
			skeleton.set_bone_parent(i, _idx[b[1]])
			parent_pos = _bone_pos(b[1])
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, (b[2] as Vector3) - parent_pos))
		_cur[b[0]] = Vector3.ZERO
	skeleton.reset_bone_poses()
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "CuerpoConPiel"
	mesh_instance.mesh = _skinned_mesh(src, xf)
	skeleton.add_child(mesh_instance)
	var skin := Skin.new()
	for b in BONES:
		skin.add_named_bind(b[0], Transform3D(Basis.IDENTITY, b[2]).affine_inverse())
	mesh_instance.skin = skin
	mesh_instance.skeleton = NodePath("..")
	model.queue_free()
	for b in BONES:
		var at := BoneAttachment3D.new()
		at.name = "En_" + b[0]
		at.bone_name = b[0]
		skeleton.add_child(at)
		_attach[b[0]] = at
	return mesh_instance


func _bone_pos(n: String) -> Vector3:
	for b in BONES:
		if b[0] == n:
			return b[2]
	return Vector3.ZERO


## Copia la malla horneando su transformación y agrega huesos y pesos por vértice.
func _skinned_mesh(src: MeshInstance3D, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	var mesh := src.mesh
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(verts.size() * 4)
		weights.resize(verts.size() * 4)
		var nb := xf.basis.inverse().transposed()
		for i in verts.size():
			var p := xf * verts[i]
			verts[i] = p
			if norms.size() > i:
				norms[i] = (nb * norms[i]).normalized()
			var w := _weights_for(p)
			var k := 0
			for bn in w.keys():
				if k >= 4:
					break
				bones[i * 4 + k] = _idx[bn]
				weights[i * 4 + k] = w[bn]
				k += 1
		arr[Mesh.ARRAY_VERTEX] = verts
		if norms.size() > 0:
			arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TANGENT] = null
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, mesh.surface_get_material(s) if mesh.surface_get_material(s) else src.get_active_material(s))
	return out


## Mezcla suave entre dos huesos alrededor de un corte (ancho `w`).
static func _blend(v: float, cut: float, w: float, a: String, b: String) -> Dictionary:
	var t := clampf((v - (cut - w)) / (2.0 * w), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	if t <= 0.0:
		return {a: 1.0}
	if t >= 1.0:
		return {b: 1.0}
	return {a: 1.0 - t, b: t}


## Huesos y pesos de un vértice según su posición (pose T, mirando a -Z).
func _weights_for(p: Vector3) -> Dictionary:
	var ax := absf(p.x)
	var side := "r" if p.x > 0.0 else "l"
	# Brazos (horizontales, a la altura de los hombros)
	if ax > 0.17 and p.y > 1.08:
		if ax < 0.24:
			var w := _blend(ax, 0.205, 0.035, "chest", "arm_" + side)
			return w
		if ax < 0.6:
			return _blend(ax, 0.47, 0.05, "arm_" + side, "fore_" + side)
		return _blend(ax, 0.715, 0.03, "fore_" + side, "hand_" + side)
	# Cabeza y cuello
	if p.y > 1.36:
		return _blend(p.y, 1.45, 0.04, "neck", "head") if p.y < 1.5 else {"head": 1.0}
	if p.y > 1.12:
		return _blend(p.y, 1.36, 0.03, "chest", "neck") if p.y > 1.33 else _blend(p.y, 1.12, 0.05, "spine", "chest")
	if p.y > 0.93:
		return _blend(p.y, 0.99, 0.05, "hips", "spine")
	# Piernas
	if p.y > 0.8 and ax < 0.05:
		return {"hips": 1.0}
	if p.y > 0.82:
		return _blend(p.y, 0.86, 0.05, "thigh_" + side, "hips")
	if p.y > 0.12:
		return _blend(p.y, 0.48, 0.05, "shin_" + side, "thigh_" + side)
	return _blend(p.y, 0.1, 0.03, "foot_" + side, "shin_" + side)


## Pega un nodo (arma, pieza de armadura) al hueso más cercano a su posición,
## conservando cómo se ve en la pose de reposo.
func attach_by_position(node: Node3D, bone := "") -> void:
	if bone == "":
		var w := _weights_for(node.position)
		var best := 0.0
		for bn in w.keys():
			if float(w[bn]) > best:
				best = w[bn]
				bone = bn
	var at: BoneAttachment3D = _attach[bone]
	# El espacio del esqueleto coincide con el de Visual (pivote +0.55, esqueleto −0.55)
	var rest := Transform3D(Basis.IDENTITY, _bone_pos(bone))
	var local := rest.affine_inverse() * node.transform
	node.get_parent().remove_child(node)
	at.add_child(node)
	node.transform = local


## Pega un arma a una mano u otro hueso y la orienta para que, en la pose
## `ref_pose`, su eje `axis` (en el espacio del arma) apunte hacia `world_dir`.
## `up_hint` fija hacia dónde mira la cara del arma (filo, cara del escudo…).
func attach_weapon(node: Node3D, bone: String, axis: Vector3, world_dir: Vector3, ref_pose: Dictionary, offset := Vector3.ZERO, face_axis := Vector3.ZERO, face_dir := Vector3.ZERO) -> void:
	var hb := _global_basis(ref_pose, bone)
	# Rotación (en espacio de Visual) que lleva el eje del arma a la dirección pedida
	var q := Quaternion(axis.normalized(), world_dir.normalized())
	var want := Basis(q)
	if face_axis != Vector3.ZERO:
		# Gira alrededor del eje para que la cara apunte lo más posible a face_dir
		var cur_face := want * face_axis.normalized()
		var d := world_dir.normalized()
		var fd := (face_dir - d * face_dir.dot(d)).normalized()
		var cf := (cur_face - d * cur_face.dot(d)).normalized()
		if fd.length() > 0.01 and cf.length() > 0.01:
			var ang := cf.signed_angle_to(fd, d)
			want = Basis(d, ang) * want
	node.get_parent().remove_child(node)
	_attach[bone].add_child(node)
	node.transform = Transform3D(hb.inverse() * want, offset)


## Base global de un hueso en una pose dada (cinemática directa; los reposos no rotan).
func _global_basis(d: Dictionary, bone: String) -> Basis:
	var conv := pose(_merge(_merge({}, RELAX), d))
	var chain: Array = []
	var n := bone
	while n != "":
		chain.push_front(n)
		var parent := ""
		for b in BONES:
			if b[0] == n:
				parent = b[1]
		n = parent
	var basis := Basis.IDENTITY
	for c in chain:
		var e: Vector3 = conv.get(c, Vector3.ZERO)
		basis = basis * Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
	return basis


func attachment(bone: String) -> BoneAttachment3D:
	return _attach.get(bone)


# ======================================================================
#  Poses
# ======================================================================

## Convierte una pose en grados "intuitivos" a rotaciones por hueso.
static func pose(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		var v: Vector3 = d[k]
		match k:
			"arm_r":
				out[k] = Vector3(v.x, v.y, -v.z)
			"arm_l":
				out[k] = Vector3(v.x, -v.y, v.z)
			"fore_r":
				out[k] = Vector3(0, v.x, 0)
			"fore_l":
				out[k] = Vector3(0, -v.x, 0)
			"hand_r":
				out[k] = Vector3(v.x, v.y, -v.z)
			"hand_l":
				out[k] = Vector3(v.x, -v.y, v.z)
			_:
				out[k] = v
	return out


const RELAX := {"arm_l": Vector3(0, 0, 78), "arm_r": Vector3(0, 0, 78), "fore_l": Vector3(14, 0, 0), "fore_r": Vector3(14, 0, 0)}
## Mano derecha lista con el arma al frente.
const READY := {"arm_r": Vector3(25, 0, 68), "fore_r": Vector3(70, 0, 0), "hand_r": Vector3(0, 0, -10),
	"arm_l": Vector3(10, 0, 74), "fore_l": Vector3(30, 0, 0)}

## Ataques: [preparación, golpe] por tipo de arma y paso del combo.
const ATTACKS := {
	"espada_1": [{"arm_r": Vector3(60, -40, 20), "fore_r": Vector3(100, 0, 0), "chest": Vector3(0, 35, 0), "spine": Vector3(0, 15, 0)},
		{"arm_r": Vector3(75, 30, 45), "fore_r": Vector3(10, 0, 0), "chest": Vector3(-8, -40, 0), "spine": Vector3(0, -15, 0), "thigh_r": Vector3(20, 0, 0), "shin_r": Vector3(-25, 0, 0)}],
	"espada_2": [{"arm_r": Vector3(70, 40, 70), "fore_r": Vector3(110, 0, 0), "chest": Vector3(0, -40, 0)},
		{"arm_r": Vector3(80, -30, 20), "fore_r": Vector3(10, 0, 0), "chest": Vector3(-6, 35, 0), "thigh_l": Vector3(20, 0, 0), "shin_l": Vector3(-25, 0, 0)}],
	"espada_3": [{"arm_r": Vector3(165, 0, 40), "fore_r": Vector3(40, 0, 0), "chest": Vector3(12, 0, 0), "arm_l": Vector3(140, 0, 50), "fore_l": Vector3(40, 0, 0)},
		{"arm_r": Vector3(55, 0, 70), "fore_r": Vector3(0, 0, 0), "chest": Vector3(-28, 0, 0), "spine": Vector3(-10, 0, 0), "arm_l": Vector3(20, 0, 70), "thigh_r": Vector3(45, 0, 0), "shin_r": Vector3(-50, 0, 0), "thigh_l": Vector3(-20, 0, 0)}],
	"estoque_1": [{"arm_r": Vector3(30, 0, 75), "fore_r": Vector3(120, 0, 0), "chest": Vector3(0, 30, 0)},
		{"arm_r": Vector3(85, 0, 82), "fore_r": Vector3(0, 0, 0), "chest": Vector3(-6, -20, 0), "thigh_r": Vector3(25, 0, 0), "shin_r": Vector3(-25, 0, 0)}],
	"estoque_2": [{"arm_r": Vector3(40, 0, 60), "fore_r": Vector3(110, 0, 0), "chest": Vector3(0, 20, 0)},
		{"arm_r": Vector3(95, 0, 70), "fore_r": Vector3(0, 0, 0), "chest": Vector3(-8, -25, 0), "thigh_r": Vector3(25, 0, 0), "shin_r": Vector3(-25, 0, 0)}],
	"estoque_3": [{"arm_r": Vector3(20, 0, 80), "fore_r": Vector3(130, 0, 0), "chest": Vector3(5, 40, 0), "thigh_l": Vector3(30, 0, 0), "shin_l": Vector3(-50, 0, 0)},
		{"arm_r": Vector3(88, 0, 85), "fore_r": Vector3(0, 0, 0), "chest": Vector3(-15, -30, 0), "spine": Vector3(-10, 0, 0), "thigh_r": Vector3(60, 0, 0), "shin_r": Vector3(-40, 0, 0), "thigh_l": Vector3(-35, 0, 0), "shin_l": Vector3(-20, 0, 0)}],
	"mazo_1": [{"arm_r": Vector3(170, 0, 30), "fore_r": Vector3(60, 0, 0), "arm_l": Vector3(150, 0, 40), "fore_l": Vector3(70, 0, 0), "chest": Vector3(15, 0, 0)},
		{"arm_r": Vector3(45, 0, 70), "fore_r": Vector3(5, 0, 0), "arm_l": Vector3(40, 0, 60), "chest": Vector3(-35, 0, 0), "spine": Vector3(-12, 0, 0), "thigh_r": Vector3(40, 0, 0), "shin_r": Vector3(-55, 0, 0), "thigh_l": Vector3(-15, 0, 0)}],
	"mazo_2": [{"arm_r": Vector3(60, -60, 10), "fore_r": Vector3(40, 0, 0), "chest": Vector3(0, 70, 0), "spine": Vector3(0, 25, 0)},
		{"arm_r": Vector3(70, 50, 30), "fore_r": Vector3(5, 0, 0), "chest": Vector3(-10, -70, 0), "spine": Vector3(0, -25, 0), "thigh_l": Vector3(25, 0, 0), "shin_l": Vector3(-35, 0, 0)}],
	"lanza_1": [{"arm_r": Vector3(20, 0, 80), "fore_r": Vector3(110, 0, 0), "arm_l": Vector3(50, 0, 60), "fore_l": Vector3(80, 0, 0), "chest": Vector3(0, 35, 0)},
		{"arm_r": Vector3(85, 0, 85), "fore_r": Vector3(0, 0, 0), "arm_l": Vector3(80, 0, 50), "fore_l": Vector3(20, 0, 0), "chest": Vector3(-8, -10, 0), "thigh_r": Vector3(30, 0, 0), "shin_r": Vector3(-30, 0, 0)}],
	"lanza_2": [{"arm_r": Vector3(30, 0, 70), "fore_r": Vector3(100, 0, 0), "chest": Vector3(0, 25, 0)},
		{"arm_r": Vector3(95, 0, 80), "fore_r": Vector3(0, 0, 0), "chest": Vector3(-10, -15, 0), "thigh_l": Vector3(30, 0, 0), "shin_l": Vector3(-30, 0, 0)}],
	"lanza_3": [{"arm_r": Vector3(70, -50, 20), "fore_r": Vector3(30, 0, 0), "chest": Vector3(0, 80, 0), "spine": Vector3(0, 30, 0), "arm_l": Vector3(60, 0, 30)},
		{"arm_r": Vector3(80, 50, 10), "fore_r": Vector3(0, 0, 0), "chest": Vector3(-5, -90, 0), "spine": Vector3(0, -30, 0), "arm_l": Vector3(30, 0, 60), "thigh_r": Vector3(25, 0, 0)}],
	"brazo_1": [{"arm_r": Vector3(30, 0, 70), "fore_r": Vector3(110, 0, 0), "chest": Vector3(0, 25, 0)},
		{"arm_r": Vector3(90, 0, 80), "fore_r": Vector3(0, 0, 0), "hand_r": Vector3(0, 0, -20), "chest": Vector3(-5, -20, 0)}],
}

## Otras acciones (pose única que se mezcla con la locomoción).
const ACTIONS := {
	"curar": {"arm_r": Vector3(55, 0, 30), "fore_r": Vector3(150, 0, 0), "hand_r": Vector3(-30, 0, 0), "head": Vector3(20, 0, 0), "neck": Vector3(10, 0, 0)},
	"bloquear": {"arm_l": Vector3(70, -20, 55), "fore_l": Vector3(95, 0, 0), "hand_l": Vector3(0, 0, 0), "chest": Vector3(-6, 15, 0), "arm_r": Vector3(30, 0, 65), "fore_r": Vector3(80, 0, 0)},
	"hechizo": {"arm_l": Vector3(110, 0, 50), "fore_l": Vector3(25, 0, 0), "arm_r": Vector3(80, 20, 45), "fore_r": Vector3(40, 0, 0), "chest": Vector3(6, 0, 0), "head": Vector3(8, 0, 0)},
	"arco": {"arm_l": Vector3(88, 0, 82), "fore_l": Vector3(0, 0, 0), "arm_r": Vector3(88, -10, 75), "fore_r": Vector3(150, 0, 0), "chest": Vector3(0, -25, 0), "head": Vector3(0, 20, 0)},
	"sismico": {"arm_r": Vector3(170, 0, 20), "fore_r": Vector3(30, 0, 0), "arm_l": Vector3(165, 0, 25), "fore_l": Vector3(30, 0, 0), "chest": Vector3(12, 0, 0)},
	"sismico_golpe": {"arm_r": Vector3(40, 0, 60), "fore_r": Vector3(0, 0, 0), "arm_l": Vector3(40, 0, 60), "chest": Vector3(-40, 0, 0), "spine": Vector3(-15, 0, 0), "thigh_r": Vector3(50, 0, 0), "shin_r": Vector3(-70, 0, 0), "thigh_l": Vector3(-10, 0, 0), "shin_l": Vector3(-40, 0, 0)},
	"ordenar": {"arm_r": Vector3(92, 0, 80), "fore_r": Vector3(0, 0, 0), "hand_r": Vector3(0, 0, -25), "chest": Vector3(0, -15, 0), "arm_l": Vector3(20, 0, 70), "fore_l": Vector3(60, 0, 0)},
	"ordenar_especial": {"arm_r": Vector3(160, 0, 30), "fore_r": Vector3(10, 0, 0), "arm_l": Vector3(160, 0, 30), "fore_l": Vector3(10, 0, 0), "chest": Vector3(10, 0, 0), "head": Vector3(15, 0, 0)},
}

const ROLL := {"thigh_l": Vector3(115, 0, 0), "thigh_r": Vector3(115, 0, 0), "shin_l": Vector3(-140, 0, 0), "shin_r": Vector3(-140, 0, 0),
	"spine": Vector3(-35, 0, 0), "chest": Vector3(-35, 0, 0), "head": Vector3(-35, 0, 0), "neck": Vector3(-10, 0, 0),
	"arm_l": Vector3(70, 0, 60), "arm_r": Vector3(70, 0, 60), "fore_l": Vector3(110, 0, 0), "fore_r": Vector3(110, 0, 0)}
const STAGGER := {"chest": Vector3(18, 0, 6), "head": Vector3(20, 0, 0), "spine": Vector3(8, 0, 0), "arm_l": Vector3(-20, 0, 50), "arm_r": Vector3(-20, 0, 50), "fore_l": Vector3(40, 0, 0), "fore_r": Vector3(40, 0, 0)}
const SHOCK := {"arm_l": Vector3(0, 0, 25), "arm_r": Vector3(0, 0, 25), "fore_l": Vector3(30, 0, 0), "fore_r": Vector3(30, 0, 0), "head": Vector3(15, 0, 0), "chest": Vector3(10, 0, 0)}
const GRABBED := {"arm_l": Vector3(150, 0, 20), "arm_r": Vector3(150, 0, 20), "fore_l": Vector3(60, 0, 0), "fore_r": Vector3(60, 0, 0), "thigh_l": Vector3(30, 0, 0), "shin_l": Vector3(-40, 0, 0), "thigh_r": Vector3(-10, 0, 0), "shin_r": Vector3(-30, 0, 0), "head": Vector3(10, 0, 0)}
const DEAD := {"arm_l": Vector3(-20, 0, 15), "arm_r": Vector3(-30, 0, 20), "fore_l": Vector3(20, 0, 0), "fore_r": Vector3(10, 0, 0), "head": Vector3(15, 30, 0), "thigh_l": Vector3(10, 0, -8), "thigh_r": Vector3(-5, 0, 6), "shin_l": Vector3(-20, 0, 0)}


# ======================================================================
#  Animación por cuadro
# ======================================================================

## st: estado del jugador (ver test_player._rig_state()).
func animate(delta: float, st: Dictionary) -> void:
	_t += delta
	var target := {}
	var speed: float = st.get("speed", 0.0)
	var run: bool = st.get("run", false)
	var hold: bool = st.get("hold", true)
	# --- Locomoción
	var amt := clampf(speed / 5.0, 0.0, 1.6)
	_phase += delta * (4.2 + speed * 1.15) if speed > 0.1 else delta * 1.5
	var s := sin(_phase)
	var c := cos(_phase)
	var leg := 30.0 * amt if not run else 46.0
	var arm := 22.0 * amt if not run else 42.0
	target = _merge(target, RELAX)
	if hold:
		target = _merge(target, READY)
	target["thigh_l"] = Vector3(s * leg, 0, 0)
	target["thigh_r"] = Vector3(-s * leg, 0, 0)
	target["shin_l"] = Vector3(-maxf(0.0, -c) * leg * 1.6 - 4.0 * amt, 0, 0)
	target["shin_r"] = Vector3(-maxf(0.0, c) * leg * 1.6 - 4.0 * amt, 0, 0)
	target["foot_l"] = Vector3(maxf(0.0, s) * 10.0 * amt, 0, 0)
	target["foot_r"] = Vector3(maxf(0.0, -s) * 10.0 * amt, 0, 0)
	var lean := -14.0 if run else -4.0 * amt
	target["spine"] = Vector3(lean, s * 6.0 * amt, 0)
	target["chest"] = Vector3(0, -s * 8.0 * amt, 0)
	target["head"] = Vector3(-lean * 0.6, s * 3.0 * amt, 0)
	_add(target, "arm_l", Vector3(-s * arm, 0, 0))
	if not hold:
		_add(target, "arm_r", Vector3(s * arm, 0, 0))
	if run:
		_add(target, "fore_l", Vector3(60, 0, 0))
		if not hold:
			_add(target, "fore_r", Vector3(60, 0, 0))
	# Respiración en reposo
	if speed < 0.1:
		_add(target, "chest", Vector3(sin(_t * 1.8) * 2.0, 0, 0))
		_add(target, "arm_l", Vector3(0, 0, sin(_t * 1.8) * 1.5))
	var hips_y := -absf(c) * 0.035 * amt - (0.06 if run else 0.0)
	# --- Acción (parte superior del cuerpo)
	var act: String = st.get("action", "")
	var k: float = st.get("k", 0.0)
	if ATTACKS.has(act):
		var pair: Array = ATTACKS[act]
		var wind: Dictionary = pair[0]
		var hit: Dictionary = pair[1]
		var hit_k: float = st.get("hit_k", 0.4)
		var a := smoothstep(0.0, hit_k * 0.8, k)
		var b := smoothstep(hit_k * 0.75, hit_k * 1.1, k)
		var r := smoothstep(0.75, 1.0, k)
		var p := _lerp_pose(_lerp_pose(_merge({}, target), wind, a), hit, b)
		target = _lerp_pose(p, target, r)
		hips_y -= 0.05 * b * (1.0 - r)
	elif ACTIONS.has(act):
		var w: float = st.get("w", 1.0)
		target = _lerp_pose(target, ACTIONS[act], w)
	# --- Cuerpo completo
	var roll: float = st.get("roll", -1.0)
	var rot_x := 0.0
	var lift := 0.0
	if roll >= 0.0:
		var tuck := sin(clampf(roll, 0.0, 1.0) * PI)
		target = _lerp_pose(target, ROLL, clampf(tuck * 1.6, 0.0, 1.0))
		rot_x = -roll * TAU
		hips_y -= 0.12 * tuck
		lift = 0.3 * tuck
	if st.get("stagger", false):
		target = _lerp_pose(target, STAGGER, 0.8)
	if st.get("shock", false):
		target = _lerp_pose(target, SHOCK, 1.0)
		for bn in ["arm_l", "arm_r", "fore_l", "fore_r", "head", "chest"]:
			_add(target, bn, Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12)))
	if st.get("grabbed", false):
		target = _lerp_pose(target, GRABBED, 1.0)
		_add(target, "thigh_l", Vector3(sin(_t * 14.0) * 25.0, 0, 0))
		_add(target, "thigh_r", Vector3(-sin(_t * 14.0) * 25.0, 0, 0))
	if st.get("dead", false):
		target = _merge(_merge({}, RELAX), DEAD)
	# --- Aplicar (más rápido en acciones)
	var rate := 26.0 if act != "" or roll >= 0.0 else 14.0
	var f := 1.0 - exp(-rate * delta)
	for b in BONES:
		var n: String = b[0]
		var want: Vector3 = target.get(n, Vector3.ZERO)
		_cur[n] = (_cur[n] as Vector3).lerp(want, f)
	var conv := pose(_cur)
	for n in conv.keys():
		var e: Vector3 = conv[n]
		skeleton.set_bone_pose_rotation(_idx[n], Quaternion(Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))))
	_hips_y = lerpf(_hips_y, hips_y, 1.0 - exp(-14.0 * delta))
	skeleton.set_bone_pose_position(_idx["hips"], Vector3(0, 0.92 + _hips_y, 0))
	roll_pivot.rotation.x = rot_x
	# Al rodar el centro de giro sube un poco para no atravesar el suelo
	roll_pivot.position.y = 0.55 + lift
	skeleton.position.y = -0.55


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	for k in b.keys():
		a[k] = b[k]
	return a


static func _add(d: Dictionary, k: String, v: Vector3) -> void:
	d[k] = (d.get(k, Vector3.ZERO) as Vector3) + v


static func _lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := a.duplicate()
	for k in b.keys():
		out[k] = (a.get(k, Vector3.ZERO) as Vector3).lerp(b[k], t)
	return out


# ======================================================================
#  Objetos en la mano (taza al curar, lata de bebida energética)
# ======================================================================

func show_held(kind: String, time: float) -> void:
	if _held.has(kind) and is_instance_valid(_held[kind]):
		_held[kind].queue_free()
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var m := StandardMaterial3D.new()
	if kind == "taza":
		cm.top_radius = 0.05
		cm.bottom_radius = 0.045
		cm.height = 0.1
		m.albedo_color = Color(0.93, 0.9, 0.84)
	else:
		cm.top_radius = 0.035
		cm.bottom_radius = 0.035
		cm.height = 0.13
		m.albedo_color = Color(0.15, 0.35, 0.95)
		m.metallic = 0.8
		m.roughness = 0.3
	cm.material = m
	mi.mesh = cm
	n.add_child(mi)
	n.position = Vector3(0.06, 0, -0.05)
	_attach["hand_r"].add_child(n)
	_held[kind] = n
	var tw := n.create_tween()
	tw.tween_interval(time)
	tw.tween_callback(n.queue_free)
