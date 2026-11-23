extends Node

const E := preload("res://ui/estilo.gd")
# Incluye la arena, sus accesos y el escenario que se ve detrás del jefe.
const RADIO_ESCENARIO := 90.0

var _jefe: CharacterBody3D
var _anterior: Camera3D
var _camara: Camera3D
var _rotulo: CanvasLayer
var _direccion := Vector3.BACK
var _altura := 2.0
var _duracion := 0.0
var _tiempo := 0.0
var _estructuras: Array[Node3D] = []
var _luces: Array[Light3D] = []
var _particulas: Array[GPUParticles3D] = []


func iniciar(jefe: CharacterBody3D, jugador: Node3D, centro: Vector3, nombre: String, altura: float, duracion: float) -> void:
	_jefe = jefe
	_altura = altura
	_duracion = duracion
	_limitar_decoracion(centro)
	jefe.connect("battle_started", _terminar_toma, CONNECT_ONE_SHOT)
	jefe.connect("defeated", _terminar, CONNECT_ONE_SHOT)
	if jugador and jugador.has_signal("died"):
		jugador.connect("died", _terminar, CONNECT_ONE_SHOT)
	_anterior = get_viewport().get_camera_3d()
	if not _anterior or not jugador:
		set_physics_process(false)
		set_process_input(false)
		return
	var hacia_jugador := jugador.global_position - jefe.global_position
	hacia_jugador.y = 0.0
	if hacia_jugador.length_squared() > 0.01:
		_direccion = hacia_jugador.normalized()
	_camara = Camera3D.new()
	_camara.top_level = true
	add_child(_camara)
	_actualizar_toma()
	if not _camara:
		return
	_camara.make_current()
	_rotulo = CanvasLayer.new()
	_rotulo.layer = 9
	add_child(_rotulo)
	var texto := VBoxContainer.new()
	_rotulo.add_child(texto)
	texto.anchor_left = 0.1
	texto.anchor_right = 0.9
	texto.anchor_top = 0.16
	texto.anchor_bottom = 0.16
	texto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var titulo := E.titulo(nombre, 32)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texto.add_child(titulo)
	var omitir := E.etiqueta("Enter · Volver a tu cámara", 15)
	omitir.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	omitir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texto.add_child(omitir)
	texto.modulate.a = 0.0
	create_tween().tween_property(texto, "modulate:a", 1.0, 0.3)


func _physics_process(delta: float) -> void:
	_tiempo += delta
	if _tiempo >= _duracion:
		_terminar_toma()
	else:
		_actualizar_toma()


func _actualizar_toma() -> void:
	var t := smoothstep(0.0, _duracion, _tiempo)
	var foco := _jefe.global_position + Vector3.UP * _altura
	var lateral := _direccion.rotated(Vector3.UP, lerpf(-0.24, 0.12, t))
	var destino := foco + lateral * (_altura * 2.0 + lerpf(3.0, 1.8, t)) + Vector3.UP * 0.4
	var rayo := PhysicsRayQueryParameters3D.create(foco, destino)
	rayo.exclude = [_jefe.get_rid()]
	var hit := _jefe.get_world_3d().direct_space_state.intersect_ray(rayo)
	if not hit.is_empty():
		destino = Vector3(hit.position) - (destino - foco).normalized() * 0.2
	if destino.distance_squared_to(foco) < 0.1:
		_terminar_toma()
		return
	_camara.global_position = destino
	_camara.look_at(foco)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		_terminar_toma()
		get_viewport().set_input_as_handled()


func _terminar_toma() -> void:
	set_physics_process(false)
	set_process_input(false)
	if is_instance_valid(_camara):
		if _camara.current and is_instance_valid(_anterior) and _anterior.is_inside_tree():
			_anterior.make_current()
		_camara.queue_free()
		_camara = null
	if is_instance_valid(_rotulo):
		_rotulo.queue_free()
		_rotulo = null


func _limitar_decoracion(centro: Vector3) -> void:
	for pf in get_tree().get_nodes_in_group("estructuras_campus"):
		var generado := pf.get_node_or_null("Generated") as Node3D
		if not generado or not generado.visible:
			continue
		var escala: Vector3 = pf.global_basis.get_scale().abs()
		var huella: Vector2 = pf.footprint() * Vector2(escala.x, escala.z)
		if _lejos(pf.global_position, centro, RADIO_ESCENARIO + huella.length()):
			generado.hide()
			_estructuras.append(generado)
	for luz: Light3D in get_tree().get_nodes_in_group("luces_parpadeantes"):
		if luz.is_processing() and _lejos(luz.global_position, centro, RADIO_ESCENARIO):
			luz.set_process(false)
			_luces.append(luz)
	for p: GPUParticles3D in get_tree().get_nodes_in_group("particulas_decorativas_campus"):
		if p.emitting and _lejos(p.global_position, centro, RADIO_ESCENARIO):
			p.emitting = false
			_particulas.append(p)


func _lejos(pos: Vector3, centro: Vector3, radio: float) -> bool:
	return Vector2(pos.x - centro.x, pos.z - centro.z).length_squared() > radio * radio


func _terminar() -> void:
	_terminar_toma()
	queue_free()


func _exit_tree() -> void:
	_terminar_toma()
	for n in _estructuras:
		if is_instance_valid(n):
			n.show()
	for luz in _luces:
		if is_instance_valid(luz):
			luz.set_process(true)
	for p in _particulas:
		if is_instance_valid(p):
			p.emitting = true
