extends Node3D
## Pieza de la llave del Aula Magna: un fragmento de amuleto dorado con una gema.
## La suelta cada jefe al morir (VidaDelCampus la coloca). Al pasar encima se recoge
## y CampusWorld.add_key_piece() cuenta cuántas llevas; con las 4 se abre el portón.

const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const M := preload("enemy_models.gd")

signal picked(piece: Node3D)

## Identificador del jefe que la soltó ("profesor", "biblioteca", "computo", "laboratorio").
@export var piece_id: String = "profesor"
@export var title: String = "Pieza del Amuleto"
@export var gem_color: Color = Color(0.4, 0.75, 1.0)

var taken := false
var _holder: Node3D
var _t := 0.0
var _d := {"meshes": [], "J": {}, "eyes": []}


func _ready() -> void:
	add_to_group("pieza_llave")
	_holder = Node3D.new()
	_holder.position.y = 1.2
	add_child(_holder)
	var gold := M.mat(Color(0.95, 0.75, 0.3), 0.25, 0.9, Color(0.9, 0.6, 0.2), 0.4)
	var gem := LFX.emissive(gem_color, 3.0)
	# Fragmento de medallón: un cuarto de disco con borde y una gema
	var piv := Node3D.new()
	_holder.add_child(piv)
	for k in 5:
		var a := deg_to_rad(-45.0 + k * 22.5)
		M.box(_d, piv, Vector3(0.09, 0.32, 0.05), Vector3(sin(a) * 0.22, cos(a) * 0.22, 0), gold, Vector3(0, 0, -rad_to_deg(a)))
	M.box(_d, piv, Vector3(0.05, 0.36, 0.05), Vector3(-0.13, 0.12, 0), gold, Vector3(0, 0, 45))
	M.box(_d, piv, Vector3(0.05, 0.36, 0.05), Vector3(0.13, 0.12, 0), gold, Vector3(0, 0, -45))
	M.sph(_d, piv, Vector3(0.14, 0.14, 0.08), Vector3(0, 0.2, 0.03), gem)
	M.cyl(_d, piv, 0.03, 0.06, Vector3(0, 0.38, 0), gold, Vector3(90, 0, 0))
	var l := OmniLight3D.new()
	l.light_color = gem_color
	l.light_energy = 1.4
	l.omni_range = 5.0
	_holder.add_child(l)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.3
	cm.height = 5.0
	cm.material = LFX.emissive(gem_color, 0.8, 0.12)
	beam.mesh = cm
	beam.position = Vector3(0, 2.5, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	LFX.puff(self, global_position + Vector3(0, 1.2, 0), Color(gem_color.r * 2.5, gem_color.g * 2.5, gem_color.b * 2.5, 1), 30, 0.2, 3.0, 0.0)
	for mi in _d["meshes"]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	_t += delta
	_holder.rotation.y += delta * 1.5
	_holder.position.y = 1.2 + sin(_t * 2.0) * 0.1


func take() -> void:
	if taken:
		return
	taken = true
	picked.emit(self)
	LFX.puff(get_parent(), global_position + Vector3(0, 1.2, 0), Color(gem_color.r * 2.5, gem_color.g * 2.5, gem_color.b * 2.5, 1), 40, 0.2, 4.0, -2.0)
	queue_free()
