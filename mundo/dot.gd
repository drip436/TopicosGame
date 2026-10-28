extends Node3D
## Daño continuo sobre un enemigo o jefe por las armas con efecto (jugador/equipo.gd):
##   quemadura      fuego: 7 de daño por segundo durante 4 s
##   electrocutado  descargas: 5 por segundo durante 3 s
##   veneno         8 s a 4 por segundo
## Se pega como hijo del objetivo y llama a su take_damage(); si ya tiene el mismo efecto
## solo se renueva la duración.

const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const EFECTOS := {
	"quemadura": {"dps": 7.0, "dur": 4.0, "color": Color(2.6, 0.9, 0.2, 1)},
	"electrocutado": {"dps": 5.0, "dur": 3.0, "color": Color(0.8, 1.6, 3.0, 1)},
	"veneno": {"dps": 4.0, "dur": 8.0, "color": Color(0.7, 2.4, 0.4, 1)},
}

var effect := ""
var _left := 0.0
var _tick := 0.0


static func apply(target: Node, efecto: String) -> void:
	if not EFECTOS.has(efecto) or target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	if target.get("is_dead") == true:
		return
	var n := target.get_node_or_null("Efecto_" + efecto)
	if n == null:
		n = (load("res://mundo/dot.gd") as GDScript).new()
		n.name = "Efecto_" + efecto
		n.effect = efecto
		target.add_child(n)
	n._left = float(EFECTOS[efecto]["dur"])


func _physics_process(delta: float) -> void:
	var t := get_parent()
	if t == null or not is_instance_valid(t) or t.get("is_dead") == true:
		queue_free()
		return
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var e: Dictionary = EFECTOS[effect]
	var h: float = 1.0
	var cfg = t.get("_cfg")
	if cfg is Dictionary:
		h = float(cfg.get("height", 1.8)) * 0.6
	var pos: Vector3 = (t as Node3D).global_position + Vector3(0, h, 0)
	var fx := t.get_parent() if t.get_parent() else t
	LFX.puff(fx, pos, e["color"], 8, 0.12, 1.6, 1.5 if effect == "quemadura" else 0.0)
	t.take_damage(float(e["dps"]) * 0.5)
