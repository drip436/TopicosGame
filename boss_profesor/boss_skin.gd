extends Node
## Viste a un jefe con su modelo de Blender (modelos/jefes/*.glb, ver arte/blender/jefe_*.py).
##
## Los jefes se animan desde su código moviendo articulaciones (Node3D) con primitivas
## pegadas. Este nodo esconde esas primitivas y hace que cada hueso del modelo de Blender
## siga a la articulación que se llama igual, así que los ataques, fases y poses no
## cambian. Si el .glb no existe, el jefe se queda con su modelo procedural.
##
## Uso (al final de _build_model del jefe):
##   skin = BOSS_SKIN.apply(self, model, joints, "res://modelos/jefes/x.glb", {"ojos": m_eye}, [nodos_que_no_se_esconden])
## `mats` cambia los materiales del modelo por los del jefe (por nombre), para que los
## brillos que el código anima (ojos, núcleo, punto débil...) sigan funcionando.
## `fit` (por defecto sí) mueve las articulaciones del código a donde quedaron los huesos
## del modelo (los cuerpos realistas tienen otras proporciones que las primitivas), y
## `attach` = {nodo: "hueso"} pone otros nodos (p. ej. la mano que sostiene el arma) en la
## cabeza de ese hueso.

const SELF := "res://boss_profesor/boss_skin.gd"

var scene: Node3D
var skeleton: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var hidden: Array[MeshInstance3D] = []
var _bones: Array = []      # [hueso, articulación, desfase, padre, reposo local]
var _overlay: StandardMaterial3D
var _mats := {}
var _hidden_bones := {}


## Carga el modelo bajo `model_root` (el mismo nodo del que cuelgan las articulaciones)
## y devuelve el nodo PielBlender, o null si no hay modelo.
static func apply(boss: Node, model_root: Node3D, joints: Dictionary, path: String, mats: Dictionary = {}, keep: Array = [], fit := true, attach: Dictionary = {}) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var s: Node = (load(SELF) as GDScript).new()
	s.name = "PielBlender"
	boss.add_child(s)
	s.setup(model_root, joints, path, mats, keep, fit, attach)
	return s


func setup(model_root: Node3D, joints: Dictionary, path: String, mats: Dictionary, keep: Array, fit := false, attach: Dictionary = {}) -> void:
	process_priority = 100
	_mats = mats
	# Primitivas del modelo procedural: no se ven ni dan sombra (se quedan para la lógica)
	for n in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.has_meta("piel_blender"):
			continue   # malla de otro modelo de Blender del mismo jefe
		var kept := false
		for k in keep:
			if k != null and (k == mi or (k as Node).is_ancestor_of(mi)):
				kept = true
				break
		if not kept:
			mi.layers = 0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hidden.append(mi)
	scene = (load(path) as PackedScene).instantiate()
	scene.name = "ModeloBlender"
	model_root.add_child(scene)
	skeleton = scene.find_children("*", "Skeleton3D", true, false)[0]
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		meshes.append(mi)
		mi.set_meta("piel_blender", true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m and _mats.has(m.resource_name):
				mi.set_surface_override_material(si, _mats[m.resource_name])
	if fit:
		_fit_joints(joints, attach)
	# Desfase de cada hueso respecto a su articulación, medido en reposo
	var inv := skeleton.global_transform.affine_inverse()
	var order: Array = []
	for b in skeleton.get_bone_count():
		var depth := 0
		var p := skeleton.get_bone_parent(b)
		while p >= 0:
			depth += 1
			p = skeleton.get_bone_parent(p)
		order.append([depth, b])
	order.sort()
	for o in order:
		var b: int = o[1]
		var j: Node3D = joints.get(skeleton.get_bone_name(b))
		var off := Transform3D.IDENTITY
		if j:
			off = (inv * j.global_transform).affine_inverse() * skeleton.get_bone_global_rest(b)
		_bones.append([b, j, off, skeleton.get_bone_parent(b), skeleton.get_bone_rest(b)])
	sync()


## Lleva cada articulación (y los nodos de `attach`) a la cabeza de su hueso, de padres a hijos.
func _fit_joints(joints: Dictionary, attach: Dictionary) -> void:
	var order: Array = []
	for b in skeleton.get_bone_count():
		var depth := 0
		var p := skeleton.get_bone_parent(b)
		while p >= 0:
			depth += 1
			p = skeleton.get_bone_parent(p)
		order.append([depth, b])
	order.sort()
	for o in order:
		var b: int = o[1]
		var j: Node3D = joints.get(skeleton.get_bone_name(b))
		if j:
			j.global_position = skeleton.global_transform * skeleton.get_bone_global_rest(b).origin
	for node in attach:
		var b := skeleton.find_bone(String(attach[node]))
		if b >= 0 and node is Node3D:
			(node as Node3D).global_position = skeleton.global_transform * skeleton.get_bone_global_rest(b).origin


func _process(_delta: float) -> void:
	sync()


## Copia la pose de las articulaciones a los huesos.
func sync() -> void:
	if skeleton == null or not skeleton.is_inside_tree():
		return
	var inv := skeleton.global_transform.affine_inverse()
	var glob := {}
	for e in _bones:
		var b: int = e[0]
		var parent: int = e[3]
		var g: Transform3D
		if e[1] != null and is_instance_valid(e[1]):
			g = inv * (e[1] as Node3D).global_transform * (e[2] as Transform3D)
		elif parent >= 0:
			g = (glob[parent] as Transform3D) * (e[4] as Transform3D)
		else:
			g = e[4]
		if _hidden_bones.has(b):
			g = g.scaled_local(Vector3.ONE * 0.001)
		glob[b] = g
		var local: Transform3D = g if parent < 0 else (glob[parent] as Transform3D).affine_inverse() * g
		skeleton.set_bone_pose_position(b, local.origin)
		skeleton.set_bone_pose_rotation(b, local.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(b, local.basis.get_scale())


## Muestra u oculta todo el modelo (p. ej. para cambiarlo por el de la segunda fase).
func set_visible(on: bool) -> void:
	scene.visible = on
	set_process(on)


## Esconde partes del modelo (encogiendo esos huesos y sus hijos), p. ej. la pierna
## que ADA-7 pierde en la fase 2.
func hide_bones(names: Array) -> void:
	for n in names:
		var b := skeleton.find_bone(String(n))
		if b < 0:
			continue
		for c in skeleton.get_bone_count():
			var p := c
			while p >= 0 and p != b:
				p = skeleton.get_bone_parent(p)
			if p == b:
				_hidden_bones[c] = true


## Destello blanco al recibir daño (0 = nada, 1 = máximo).
func flash(amount: float) -> void:
	if _overlay == null:
		_overlay = StandardMaterial3D.new()
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.albedo_color = Color(1, 0.95, 0.9, clampf(amount, 0.0, 1.0) * 0.45)
	for mi in meshes:
		mi.material_overlay = _overlay if amount > 0.01 else null


## Tinte de todo el modelo (p. ej. la piel verde del Dr. Kessler en fase 2).
func set_tint(c: Color) -> void:
	for mi in meshes:
		for si in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(si)
			if m == null:
				m = mi.mesh.surface_get_material(si)
				if m is StandardMaterial3D and m.resource_name != "ojos":
					m = (m as StandardMaterial3D).duplicate()
					mi.set_surface_override_material(si, m)
				else:
					continue
			if m is StandardMaterial3D and not _mats.values().has(m) and m.resource_name != "ojos":
				(m as StandardMaterial3D).albedo_color = c
