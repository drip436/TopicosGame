@tool
class_name CampusPrefab
extends Node3D
## Estructura del campus que se coloca a mano en el editor 3D: arrástrala desde
## res://prefabs/, muévela y gírala con el gizmo, duplícala con Ctrl+D y ajusta
## sus opciones en el Inspector. CampusWorld la construye donde esté este nodo
## (como hija "Generated") y, al soltarla, reacomoda árboles, pasto y relleno.
##
## Si dos copias se ven idénticas, cambia `variation`.

enum Kind { FACULTAD, ALA_DE_SALONES, EDIFICIO_EN_RUINAS, ZONA_RECREATIVA, FUENTE }
enum Zone {
	PARQUE_INFANTIL, BASQUETBOL, TENIS, SKATEPARK, ESTACIONAMIENTO, GIMNASIO,
	FORO, ESCULTURAS, PICNIC, ALBERCA, HUERTO, VOLEIBOL, FUTBOLITO, MEMORIAL,
	FRONTONES, TERMINAL, PUESTO_DE_RESCATE, MERCADITO,
}

## Tamaño (x, z) que ocupa cada zona recreativa, en metros.
const ZONE_SIZES := {
	Zone.PARQUE_INFANTIL: Vector2(40, 22), Zone.BASQUETBOL: Vector2(30, 34), Zone.TENIS: Vector2(54, 17),
	Zone.SKATEPARK: Vector2(54, 18), Zone.GIMNASIO: Vector2(52, 24), Zone.FORO: Vector2(34, 30),
	Zone.ESCULTURAS: Vector2(32, 28), Zone.ALBERCA: Vector2(30, 22), Zone.HUERTO: Vector2(36, 26),
	Zone.VOLEIBOL: Vector2(26, 18), Zone.FUTBOLITO: Vector2(40, 24), Zone.MEMORIAL: Vector2(32, 28),
	Zone.FRONTONES: Vector2(30, 34), Zone.TERMINAL: Vector2(54, 18), Zone.PUESTO_DE_RESCATE: Vector2(34, 30),
	Zone.MERCADITO: Vector2(32, 28),
}

@export var kind: Kind = Kind.FACULTAD:
	set(v):
		kind = v
		notify_property_list_changed()
		_changed()
## Nombre que aparece en la fachada y al entrar a la zona.
@export var title: String = "":
	set(v):
		title = v
		_changed()
## Cambia el daño y los detalles aleatorios de esta copia.
@export var variation: int = 0:
	set(v):
		variation = v
		_changed()

@export_group("Edificio")
@export_range(1, 4) var floors: int = 2:
	set(v):
		floors = v
		_changed()
## Ala de salones: tramos de 8 m.
@export_range(1, 30) var segments: int = 7:
	set(v):
		segments = v
		_changed()
## Ala de salones: tramo convertido en pasaje (-1 = ninguno).
@export var passage: int = -1:
	set(v):
		passage = v
		_changed()
## Ala de salones: probabilidad de tramos derrumbados.
@export_range(0.0, 1.0) var collapse: float = 0.12:
	set(v):
		collapse = v
		_changed()
## Ala de salones: cerrar los extremos con muro.
@export var end_caps: bool = true:
	set(v):
		end_caps = v
		_changed()
## Edificio en ruinas: crujías de 4 m en X y Z.
@export_range(1, 12) var bays_x: int = 5:
	set(v):
		bays_x = v
		_changed()
@export_range(1, 12) var bays_z: int = 4:
	set(v):
		bays_z = v
		_changed()
## Edificio en ruinas: qué tan destruido está.
@export_range(0.0, 1.5) var damage: float = 0.8:
	set(v):
		damage = v
		_changed()

@export_group("Zona")
@export var zone: Zone = Zone.PARQUE_INFANTIL:
	set(v):
		zone = v
		notify_property_list_changed()
		_changed()
## Estacionamiento y picnic: tamaño del área (x, z).
@export var area_size: Vector2 = Vector2(22, 60):
	set(v):
		area_size = v
		_changed()
## Fuente: radio de la plaza.
@export_range(6.0, 30.0) var plaza_radius: float = 12.0:
	set(v):
		plaza_radius = v
		_changed()

var _ready_done := false


func _ready() -> void:
	set_notify_transform(true)
	_mark_ready.call_deferred()


func _mark_ready() -> void:
	_ready_done = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_changed()


func _enter_tree() -> void:
	if _ready_done:
		_changed()


func _exit_tree() -> void:
	_changed()


func _changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	for w in get_tree().get_nodes_in_group("campus_world"):
		w.request_rebuild()


## Tamaño local (x, z) que ocupa, para que árboles y relleno no lo invadan.
func footprint() -> Vector2:
	match kind:
		Kind.FACULTAD:
			return Vector2(60, 52)
		Kind.ALA_DE_SALONES:
			return Vector2(segments * 8.0 + 2.0, 10.0)
		Kind.EDIFICIO_EN_RUINAS:
			return Vector2(bays_x * 4.0 + 6.0, bays_z * 4.0 + 6.0)
		Kind.FUENTE:
			return Vector2(plaza_radius * 2.0, plaza_radius * 2.0)
	if zone == Zone.ESTACIONAMIENTO or zone == Zone.PICNIC:
		return area_size
	return ZONE_SIZES.get(zone, Vector2(30, 30))


func _validate_property(property: Dictionary) -> void:
	var n: String = property.name
	var show := true
	match n:
		"floors":
			show = kind in [Kind.FACULTAD, Kind.ALA_DE_SALONES, Kind.EDIFICIO_EN_RUINAS]
		"segments", "passage", "collapse", "end_caps":
			show = kind == Kind.ALA_DE_SALONES
		"bays_x", "bays_z", "damage":
			show = kind == Kind.EDIFICIO_EN_RUINAS
		"zone":
			show = kind == Kind.ZONA_RECREATIVA
		"area_size":
			show = kind == Kind.ZONA_RECREATIVA and (zone == Zone.ESTACIONAMIENTO or zone == Zone.PICNIC)
		"plaza_radius":
			show = kind == Kind.FUENTE
	if not show:
		property.usage = PROPERTY_USAGE_NO_EDITOR
