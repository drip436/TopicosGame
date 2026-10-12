extends Light3D
## Parpadeo para faroles dañados y fogatas.

@export var base_energy: float = 2.0
@export var speed: float = 3.0
@export var amount: float = 0.18
## Probabilidad por cuadro de que la luz se apague un instante (falla eléctrica).
@export var dropout_chance: float = 0.01

var _t := 0.0
var _off := 0.0
var _seed := 0.0


func _ready() -> void:
	_seed = randf() * 100.0
	light_energy = base_energy


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta * speed
	if _off > 0.0:
		_off -= delta
		light_energy = base_energy * 0.05
		return
	if randf() < dropout_chance:
		_off = randf_range(0.04, 0.35)
	var n := sin(_t + _seed) * 0.5 + sin(_t * 2.7 + _seed * 1.3) * 0.3 + sin(_t * 7.1) * 0.2
	light_energy = base_energy * (1.0 + n * amount)
