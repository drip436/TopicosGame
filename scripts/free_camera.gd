extends Camera3D
## Cámara libre para recorrer el escenario.
## Clic derecho (mantener) + mouse: mirar | WASD: mover | Q/E: bajar/subir
## Shift: rápido | Rueda: cambiar velocidad | Esc: soltar el mouse

@export var speed: float = 8.0
@export var boost: float = 4.0
@export var sensitivity: float = 0.0025

var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			speed = minf(speed * 1.2, 120.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			speed = maxf(speed / 1.2, 1.0)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch - event.relative.y * sensitivity, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= global_basis.z
	if Input.is_key_pressed(KEY_S):
		dir += global_basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= global_basis.x
	if Input.is_key_pressed(KEY_D):
		dir += global_basis.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if dir != Vector3.ZERO:
		var s := speed * (boost if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		global_position += dir.normalized() * s * delta
