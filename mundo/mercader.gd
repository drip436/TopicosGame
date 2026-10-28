extends Node3D
## El mercader del campus (modelo de arte/blender/jugador.py → mercader.glb, hecho a
## partir de la foto de referencia). Vende armas y armaduras a cambio de créditos.
## Lo crea VidaDelCampus cerca de la Hoguera de la Plaza.
##   - Respira y mira al jugador cuando está cerca; al acercarte la primera vez te saluda
##     con la "V" de la foto (la otra mano como si sostuviera el celular).
##   - E (a menos de 2.6 m) abre la tienda (ui/tienda.gd).

const RIG := preload("res://jugador/player_rig.gd")
const MODEL := "res://modelos/jugador/mercader.glb"
const TIENDA := preload("res://ui/tienda.gd")

const SALUDOS := [
	"¡Qué onda! ¿Traes créditos? Tengo cosas bien chidas.",
	"Pásale, pásale. Armaduras, armas... todo de primera.",
	"¿Otra vez tú? Me caes bien, te hago precio... no, la verdad no.",
	"Esas cosas allá afuera sueltan créditos. Tráelos para acá.",
]

var player: Node3D
var hud: Node
var _visual: Node3D
var _rig: Node
var _greet_t := 0.0
var _greeted := false
var _near := false
var _tienda: CanvasLayer
var _yaw := 0.0
var _label: Label3D


func _ready() -> void:
	add_to_group("mercader")
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if ResourceLoader.exists(MODEL):
		var model: Node3D = (load(MODEL) as PackedScene).instantiate()
		_visual.add_child(model)
		_rig = RIG.new()
		add_child(_rig)
		_rig.build(_visual, model, "", MODEL)
	# Colisión (no se le puede atravesar)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	body.add_child(cs)
	add_child(body)
	_label = Label3D.new()
	_label.text = "MERCADER"
	_label.font_size = 42
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.86, 0.45)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.15, 0)
	_label.no_depth_test = false
	_label.visible = false
	add_child(_label)
	_yaw = rotation.y
	if player and player.has_signal("interact_pressed"):
		player.interact_pressed.connect(_on_interact)


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var to := player.global_position - global_position
	to.y = 0.0
	var d := to.length()
	# Mira al jugador cuando está cerca
	if d < 9.0 and d > 0.1:
		var want := atan2(-to.x, -to.z) - rotation.y
		_visual.rotation.y = lerp_angle(_visual.rotation.y, want, 1.0 - exp(-4.0 * delta))
	if d < 7.0 and not _greeted:
		_greeted = true
		_greet_t = 2.4
		if hud and hud.has_method("toast"):
			hud.toast("Mercader: " + SALUDOS[randi() % SALUDOS.size()], 4.0)
	elif d > 16.0:
		_greeted = false
	_greet_t -= delta
	if _rig and _rig.skeleton:
		_rig.animate(delta, {"speed": 0.0, "hold": false, "action": "saludo_v" if _greet_t > 0.0 else "celular", "w": 1.0})
	_label.visible = d < 10.0
	var near := d < 2.6 and not bool(player.get("is_dead"))
	if near != _near:
		_near = near
		if hud and hud.has_method("show_prompt"):
			hud.show_prompt("E  Comerciar con el mercader" if near else "")


func _on_interact() -> void:
	if not _near or (_tienda and is_instance_valid(_tienda)):
		return
	_greet_t = 1.6
	_tienda = TIENDA.new()
	_tienda.player = player
	get_tree().root.add_child(_tienda)
