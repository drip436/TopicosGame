extends CharacterBody3D
## Segundo jefe: "Doctor Euclides Barrabás, el Bibliófilo Demente".
## Profesor flaco y altísimo, con panza, barba canosa, extremidades largas,
## camisa de cuadros y pantalón de mezclilla. Vive en la Biblioteca Central.
##   Fase 1: lanza libros, hace llover libros, escribe fórmulas en los pizarrones
##           (de cada fórmula salen flechas que recorren la curva escrita) y ataca
##           con rasguños desesperados; si te atrapa, te sujeta y te rasguña.
##   Fase 2 (al 50 %): la biblioteca arde, flotan hojas sobre él; se agarra la
##           cabeza de dolor y las hojas disparan flechas que te persiguen. Las
##           fórmulas ahora son de fuego y dejan quemadura.
## El modelo es procedural. Los pizarrones los entrega el controlador (library_fight.gd).

signal health_changed(current: float, maximum: float)
signal damaged(amount: float)
signal battle_started
signal phase_changed(phase: int)
signal defeated

const PROJ := preload("library_projectile.gd")
const LFX := preload("library_fx.gd")
const FX := preload("res://boss_profesor/boss_fx.gd")

@export var boss_name: String = "Doctor Euclides Barrabás, el Bibliófilo Demente"
@export var max_health: float = 1600.0
@export_range(0.1, 0.9) var phase2_threshold: float = 0.5
@export var move_speed: float = 3.3
@export var damage_multiplier: float = 1.0

enum State { DORMANT, INTRO, FIGHT, BUSY, TRANSITION, DEAD }

var state: int = State.DORMANT
var phase := 1
var health := 0.0
var target: Node3D
var fx_parent: Node
## Pizarrones: [{pos, fwd, side, label: Label3D, graph: MeshInstance3D}]
var boards: Array = []
## Centro y medio tamaño (x, z) del área donde se mueve.
var arena_center := Vector3.ZERO
var arena_half := Vector2(26, 18)

# --- modelo
var model: Node3D
var J := {}
var _meshes: Array[MeshInstance3D] = []
var m_skin: StandardMaterial3D
var m_eye: StandardMaterial3D
var m_flash: StandardMaterial3D
var papers: Array[MeshInstance3D] = []
var paper_holder: Node3D
var m_paper: StandardMaterial3D

# --- poses
var poses := {}
var _from := {}
var _to := {}
var _cur := {}
var _pose_t := 1.0
var _pose_dur := 0.3
var _walk_phase := 0.0
var _walk_amt := 0.0
var _scribble := 0.0
var _pain := 0.0
var _anim_t := 0.0

# --- control
var _rng := RandomNumberGenerator.new()
var _attack_id := 0
var _cooldown := 1.2
var _tracking := 1.0
var _lunge := Vector3.ZERO
var _kinematic := false
var _flash := 0.0
var _papers_cd := 4.0
var _grab_cd := 3.0
var _board_cd := 2.0
var _last: Array[String] = []
var _hit_once := false
var _papers_ready := false


func _ready() -> void:
	_rng.randomize()
	add_to_group("boss")
	add_to_group("enemy")
	health = max_health
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.6
		cap.height = 3.4
		cs.shape = cap
		cs.position = Vector3(0, 1.7, 0)
		add_child(cs)
	_build_model()
	_define_poses()
	_cur = poses["write"].duplicate()
	_from = _cur.duplicate()
	_to = _cur.duplicate()


# =====================================================================
#  API
# =====================================================================

## De espaldas, escribiendo en un pizarrón, hasta que llega el jugador.
func place_dormant(pos: Vector3, look_point: Vector3) -> void:
	global_position = pos
	_face_instant(look_point)
	state = State.DORMANT
	_pose("write", 0.2)


func begin_intro() -> void:
	if state != State.DORMANT:
		return
	state = State.INTRO
	_kinematic = true
	_scribble = 0.0
	_pose("idle", 0.6)
	await _w(0.8)
	if _valid_target():
		var t0 := rotation.y
		var d := target.global_position - global_position
		var want := atan2(-d.x, -d.z)
		var tw := create_tween()
		tw.tween_method(func(v: float): rotation.y = lerp_angle(t0, want, v), 0.0, 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	await _w(1.3)
	_pose("scream", 0.35)
	_set_eyes(Color(1.0, 0.3, 0.1), 5.0)
	_shake(0.35)
	FX.shockwave(fx_parent, global_position, 8.0, Color(0.9, 0.9, 0.85), 0.6)
	LFX.paper_burst(fx_parent, global_position + Vector3(0, 3.0, 0), 30)
	await _w(1.4)
	_pose("idle", 0.5)
	await _w(0.5)
	_kinematic = false
	state = State.FIGHT
	_cooldown = 0.8
	battle_started.emit()


func take_damage(amount: float, _from_pos: Variant = null) -> void:
	if state in [State.DORMANT, State.INTRO, State.TRANSITION, State.DEAD]:
		return
	health -= amount
	_flash = 1.0
	damaged.emit(amount)
	if phase == 1 and health <= max_health * phase2_threshold:
		health = max_health * phase2_threshold
		health_changed.emit(health, max_health)
		_start_phase2()
		return
	if health <= 0.0:
		health = 0.0
		health_changed.emit(health, max_health)
		_die()
		return
	health_changed.emit(health, max_health)


func debug_force_phase2() -> void:
	if phase == 1 and state != State.DEAD:
		health = max_health * phase2_threshold
		health_changed.emit(health, max_health)
		_start_phase2()


# =====================================================================
#  Bucle
# =====================================================================

func _physics_process(delta: float) -> void:
	_anim_t += delta
	if not _kinematic:
		_update_movement(delta)
	else:
		velocity = Vector3.ZERO
	_update_pose(delta)
	_update_papers(delta)
	_flash = maxf(0.0, _flash - delta * 5.0)
	m_flash.emission_energy_multiplier = _flash * 2.5
	for m in _meshes:
		m.material_overlay = m_flash if _flash > 0.01 else null
	if state == State.FIGHT:
		_think(delta)
	if phase == 2:
		_papers_cd -= delta
	_grab_cd -= delta
	_board_cd -= delta


func _update_movement(delta: float) -> void:
	var desired := Vector3.ZERO
	if state == State.FIGHT and _valid_target():
		var to := target.global_position - global_position
		to.y = 0.0
		_turn_toward(target.global_position, delta, 1.0)
		if to.length() > 2.8:
			desired = to.normalized() * move_speed * (1.22 if phase == 2 else 1.0)
	elif state == State.BUSY and _valid_target():
		_turn_toward(target.global_position, delta, _tracking)
	desired += _lunge
	_lunge = _lunge.move_toward(Vector3.ZERO, 16.0 * delta)
	velocity.x = desired.x
	velocity.z = desired.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - 30.0 * delta
	move_and_slide()
	var flat := Vector2(velocity.x, velocity.z).length()
	_walk_amt = move_toward(_walk_amt, clampf(flat / move_speed, 0.0, 1.3), delta * 4.0)
	_walk_phase += delta * flat * 1.15


func _turn_toward(p: Vector3, delta: float, factor: float) -> void:
	if factor <= 0.0:
		return
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	rotation.y = rotate_toward(rotation.y, atan2(-d.x, -d.z), deg_to_rad(160.0 if phase == 1 else 220.0) * factor * delta)


func _face_instant(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		rotation.y = atan2(-d.x, -d.z)


# =====================================================================
#  IA
# =====================================================================

func _think(delta: float) -> void:
	if not _valid_target():
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var d := _flat(target.global_position, global_position)
	var pick := ""
	if phase == 2 and _papers_cd <= 0.0 and _rng.randf() < 0.6:
		pick = "papers"
	elif d < 3.6:
		pick = _weighted({"scratch": 58, "grab": 24 if _grab_cd <= 0.0 else 0, "board": 10 if _board_cd <= 0.0 else 0, "books": 8})
	elif d < 11.0:
		pick = _weighted({"books": 32, "grab": 26 if _grab_cd <= 0.0 else 0, "board": 30 if _board_cd <= 0.0 else 0, "scratch": 12})
	else:
		pick = _weighted({"board": 42 if _board_cd <= 0.0 else 0, "books": 30, "rain": 22, "grab": 6})
	if pick == "":
		_cooldown = 0.4
		return
	if _last.size() >= 2 and _last[-1] == pick and _last[-2] == pick:
		pick = "books" if pick != "books" else "board"
	_last.append(pick)
	if _last.size() > 4:
		_last.pop_front()
	state = State.BUSY
	_attack_id += 1
	var id := _attack_id
	match pick:
		"scratch": _atk_scratch(id)
		"grab": _atk_grab(id)
		"board": _atk_board(id)
		"books": _atk_books(id)
		"rain": _atk_rain(id)
		"papers": _atk_papers(id)


func _weighted(options: Dictionary) -> String:
	var total := 0
	for k in options:
		total += int(options[k])
	if total <= 0:
		return ""
	var r := _rng.randi_range(0, total - 1)
	for k in options:
		r -= int(options[k])
		if r < 0:
			return k
	return ""


func _end(id: int, recovery: float) -> void:
	if id != _attack_id or state in [State.DEAD, State.TRANSITION]:
		return
	_kinematic = false
	_scribble = 0.0
	_pain = 0.0
	state = State.FIGHT
	_cooldown = recovery * (0.7 if phase == 2 else 1.0)
	_tracking = 1.0
	_pose("idle", 0.4)


func _x(id: int) -> bool:
	return id != _attack_id or state in [State.DEAD, State.TRANSITION]


func _sp() -> float:
	return 0.8 if phase == 2 else 1.0


# ---- Rasguños desesperados (2 a 4 golpes seguidos)
func _atk_scratch(id: int) -> void:
	var hits := _rng.randi_range(2, 3) + (1 if phase == 2 else 0)
	for i in hits:
		var side := "l" if i % 2 == 0 else "r"
		_tracking = 1.0
		_pose("scratch_wind_" + side, 0.22 * _sp())
		await _w(0.3 * _sp())
		if _x(id): return
		_tracking = 0.25
		_lunge = -global_basis.z * 7.0
		_pose("scratch_" + side, 0.1)
		await _w(0.1)
		if _x(id): return
		_melee(2.9, 7.0, 0.2)
		await _w(0.18 * _sp())
		if _x(id): return
	await _w(0.6 * _sp())
	_end(id, _rng.randf_range(0.6, 1.0))


# ---- Agarre: se lanza; si te atrapa, te sujeta y te rasguña
func _atk_grab(id: int) -> void:
	_grab_cd = _rng.randf_range(7.0, 10.0)
	_tracking = 1.0
	_pose("grab_wind", 0.4)
	_set_eyes(Color(1.0, 0.2, 0.1), 6.0)
	await _w(0.7 * _sp())
	if _x(id) or not _valid_target(): return
	_pose("grab_dash", 0.12)
	_tracking = 0.15
	var dir := target.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	var t := 0.0
	var caught := false
	while t < 0.55:
		await get_tree().physics_frame
		if _x(id): return
		var dt := get_physics_process_delta_time()
		t += dt
		_lunge = dir * 15.0
		if _valid_target() and _flat(target.global_position, global_position) < 2.1:
			var invul: bool = "_iframes" in target and float(target.get("_iframes")) > 0.0
			if not invul:
				caught = true
				break
	_lunge = Vector3.ZERO
	if not caught:
		_pose("stagger", 0.3)
		await _w(1.0 * _sp())
		_end(id, 0.5)
		return
	# Atrapado
	if target.has_method("apply_status"):
		target.apply_status("atrapado", 2.6)
	_kinematic = true
	_pose("hold", 0.15)
	_shake(0.3)
	for i in 5:
		if _x(id) or not _valid_target(): break
		target.global_position = global_position - global_basis.z * 1.3
		_pose("scratch_l" if i % 2 == 0 else "scratch_r", 0.08)
		_hit(3.0, global_position, true)
		LFX.puff(fx_parent, target.global_position + Vector3(0, 1.2, 0), Color(0.6, 0.05, 0.03, 0.9), 10, 0.2, 2.0, -5.0)
		await _w(0.3)
		_pose("hold", 0.08)
		await _w(0.12)
	if _x(id): return
	_pose("throw", 0.15)
	if _valid_target():
		if target.has_method("clear_status"):
			target.clear_status("atrapado")
		_hit(6.0, global_position, true)
	_kinematic = false
	await _w(1.0 * _sp())
	_end(id, 0.8)


# ---- Escribe una fórmula en un pizarrón; de ella salen flechas
func _atk_board(id: int) -> void:
	_board_cd = _rng.randf_range(5.0, 8.0) * _sp()
	var b := _pick_board()
	if b.is_empty():
		_end(id, 0.3)
		return
	var stand: Vector3 = b["pos"] + b["fwd"] * 1.4
	stand.y = global_position.y
	_face_instant(stand)
	_pose("dash", 0.12)
	_kinematic = true
	var dist := global_position.distance_to(stand)
	var tw := create_tween()
	tw.tween_property(self, "global_position", stand, clampf(dist / 15.0, 0.15, 1.2))
	await tw.finished
	if _x(id): return
	_face_instant(stand - (b["fwd"] as Vector3))
	_pose("write", 0.25)
	_scribble = 1.0
	var fire := phase == 2
	var f := _make_formula(b, fire)
	var label: Label3D = b["label"]
	label.modulate = Color(1.0, 0.55, 0.2) if fire else Color(0.92, 0.94, 0.9)
	if b.has("graph_mat"):
		var gm: StandardMaterial3D = b["graph_mat"]
		gm.albedo_color = Color(1.0, 0.5, 0.15) if fire else Color(0.9, 0.92, 0.9)
		gm.emission = gm.albedo_color
		gm.emission_energy_multiplier = 1.8 if fire else 0.4
	var text: String = f["text"]
	var write_time := 1.1 * _sp()
	var n := text.length()
	for i in n + 1:
		label.text = text.substr(0, i)
		_draw_graph(b, f, float(i) / maxf(n, 1))
		if i % 3 == 0:
			LFX.puff(fx_parent, global_position + Vector3(0, 2.9, 0) - global_basis.z * 0.9, Color(0.9, 0.9, 0.9, 0.6), 4, 0.12, 0.6, -1.0)
		await _w(write_time / maxf(n, 1))
		if _x(id): return
	_scribble = 0.0
	_pose("scream", 0.2)
	_kinematic = false
	label.modulate = Color(2.2, 1.0, 0.35) if fire else Color(1.6, 1.8, 2.0)
	await _w(0.25)
	if _x(id): return
	# Flechas siguiendo la curva
	var count := 7 if phase == 1 else 10
	var lines: Array = f["lines"]
	for i in count:
		for fn in lines:
			_spawn_path_arrow(b, fn, fire)
		await _w(0.16 if lines.size() == 1 else 0.3)
		if _x(id): break
	_fade_board(b)
	if _x(id): return
	_pose("idle", 0.3)
	await _w(0.4)
	_end(id, _rng.randf_range(0.3, 0.7))


# ---- Lanza libros
func _atk_books(id: int) -> void:
	_tracking = 1.0
	_pose("throw_wind", 0.35 * _sp())
	await _w(0.45 * _sp())
	if _x(id) or not _valid_target(): return
	var n := 3 if phase == 1 else 5
	for i in n:
		_pose("throw", 0.1)
		var hand := global_position + Vector3(0, 3.0, 0) + global_basis.x * 0.6
		var aim := target.global_position
		if target is CharacterBody3D:
			aim += (target as CharacterBody3D).velocity * 0.4
		var side := global_basis.x * (float(i) - (n - 1) * 0.5) * 1.6
		_throw_book(hand, aim + side + Vector3(0, 1.0, 0), 0.75, 13.0)
		await _w(0.16)
		if _x(id): return
		_pose("throw_wind", 0.1)
		await _w(0.08)
	_pose("idle", 0.4)
	await _w(0.5 * _sp())
	_end(id, _rng.randf_range(0.5, 0.9))


# ---- Lluvia de libros (círculos en el suelo)
func _atk_rain(id: int) -> void:
	_pose("scream", 0.35)
	await _w(0.4)
	if _x(id) or not _valid_target(): return
	var spots: Array[Vector3] = []
	var rings: Array = []
	var n := 6 if phase == 1 else 9
	for i in n:
		var p := target.global_position
		if i > 0:
			p += Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
		p = _clamp(p)
		spots.append(p)
		rings.append(FX.ground_ring(fx_parent, p, 1.5, Color(1.0, 0.75, 0.3), 2.0))
	await _w(1.05)
	for p in spots:
		for k in 3:
			var b := PROJ.new()
			b.kind = PROJ.Kind.BOOK
			b.target = target
			b.boss = self
			b.damage = 15.0 * damage_multiplier
			b.land_radius = 1.4
			b.book_color = _book_color()
			b.velocity = Vector3(_rng.randf_range(-0.5, 0.5), -6.0, _rng.randf_range(-0.5, 0.5))
			b.position = p + Vector3(_rng.randf_range(-0.6, 0.6), 9.0 + k * 1.2, _rng.randf_range(-0.6, 0.6))
			fx_parent.add_child(b)
		await _w(0.08)
	for r in rings:
		if is_instance_valid(r):
			(r as Node).queue_free()
	await _w(0.8)
	_end(id, 0.6)


# ---- Fase 2: se agarra la cabeza; las hojas disparan flechas guiadas
func _atk_papers(id: int) -> void:
	_papers_cd = _rng.randf_range(8.0, 11.0)
	_tracking = 0.3
	_pose("head_pain", 0.3)
	_pain = 1.0
	_set_eyes(Color(1.0, 0.25, 0.08), 7.0)
	var tw := create_tween()
	tw.tween_property(m_paper, "emission_energy_multiplier", 4.0, 0.8)
	await _w(0.9)
	if _x(id): return
	for p in papers:
		if _x(id): return
		if not _valid_target():
			break
		var a := PROJ.new()
		a.kind = PROJ.Kind.HOMING
		a.target = target
		a.boss = self
		a.damage = 11.0 * damage_multiplier
		a.speed = 7.0
		a.turn_rate = 2.4
		a.life = 5.0
		var start := p.global_position
		a.dir = ((start - global_position) * Vector3(1, 0, 1)).normalized() * 0.6 + Vector3(0, 0.6, 0)
		a.dir = a.dir.normalized()
		a.position = start
		fx_parent.add_child(a)
		p.visible = false
		LFX.puff(fx_parent, start, Color(1.2, 2.2, 3.0, 1), 8, 0.2, 1.5, 0.0)
		_shake(0.06)
		await _w(0.22)
	await _w(0.6)
	_pain = 0.0
	m_paper.emission_energy_multiplier = 0.6
	_end(id, 0.6)
	await _w(3.0)
	for p in papers:
		p.visible = phase == 2 and state != State.DEAD


# ---- Cambio de fase
func _start_phase2() -> void:
	state = State.TRANSITION
	_attack_id += 1
	_kinematic = true
	_lunge = Vector3.ZERO
	_scribble = 0.0
	_pose("head_pain", 0.4)
	_pain = 1.0
	await _w(1.8)
	if state == State.DEAD: return
	_pain = 0.0
	_pose("scream", 0.35)
	_set_eyes(Color(1.0, 0.35, 0.05), 8.0)
	_shake(0.7)
	phase = 2
	phase_changed.emit(2)
	FX.shockwave(fx_parent, global_position, 12.0, Color(1.0, 0.5, 0.15), 0.7)
	LFX.paper_burst(fx_parent, global_position + Vector3(0, 3.2, 0), 40)
	if _valid_target() and _flat(target.global_position, global_position) < 6.0:
		_hit(12.0, global_position, false)
	paper_holder.visible = true
	for p in papers:
		p.visible = true
	await _w(1.6)
	if state == State.DEAD: return
	_pose("idle", 0.5)
	await _w(0.4)
	_kinematic = false
	_papers_cd = 2.0
	_board_cd = 0.5
	state = State.FIGHT
	_cooldown = 0.3


func _die() -> void:
	state = State.DEAD
	_attack_id += 1
	_kinematic = true
	_lunge = Vector3.ZERO
	_scribble = 0.0
	_pain = 0.0
	_pose("kneel", 0.7)
	defeated.emit()
	for p in papers:
		var tw := create_tween()
		tw.tween_property(p, "global_position", p.global_position * Vector3(1, 0, 1) + Vector3(0, 0.05, 0), 1.6).set_trans(Tween.TRANS_BOUNCE)
	await _w(1.6)
	var tw2 := create_tween()
	tw2.tween_property(model, "rotation_degrees:x", 82.0, 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw2.parallel().tween_property(model, "position:y", 0.35, 1.2)
	tw2.tween_method(func(v: float): m_eye.emission_energy_multiplier = v, 5.0, 0.0, 2.0)


# =====================================================================
#  Pizarrones y fórmulas
# =====================================================================

func _pick_board() -> Dictionary:
	if boards.is_empty() or not _valid_target():
		return {}
	var best := {}
	var best_score := -INF
	for b in boards:
		var to: Vector3 = target.global_position - (b["pos"] as Vector3)
		to.y = 0.0
		var facing: float = (b["fwd"] as Vector3).dot(to.normalized())
		if facing < 0.25:
			continue
		var score: float = facing * 10.0 - _flat(b["pos"], global_position) * 0.3 + _rng.randf() * 4.0
		if score > best_score:
			best_score = score
			best = b
	return best


func _fmt(v: float) -> String:
	var s := "%.1f" % absf(v)
	return ("− " if v < 0.0 else "+ ") + s


## Elige una función y la ajusta para que su curva pase por donde está el jugador.
func _make_formula(b: Dictionary, fire: bool) -> Dictionary:
	var rel: Vector3 = target.global_position - (b["pos"] as Vector3)
	var sp := maxf((b["fwd"] as Vector3).dot(rel), 4.0)
	var lp := (b["side"] as Vector3).dot(rel)
	var kinds := ["linea", "seno", "parabola", "absoluto", "constantes"]
	if fire:
		kinds.append("seno")
		kinds.append("parabola")
	var k: String = kinds[_rng.randi() % kinds.size()]
	match k:
		"linea":
			var m := clampf(lp / sp, -1.3, 1.3)
			return {"text": "y = %.1fx" % m, "lines": [func(s: float) -> float: return m * s], "plot": func(s: float) -> float: return m * s}
		"seno":
			var A := 2.5 if not fire else 3.2
			var kk := 0.45
			var c := lp - A * sin(kk * sp)
			var fn := func(s: float) -> float: return A * sin(kk * s) + c
			return {"text": "y = %.1f·sen(%.2fx) %s" % [A, kk, _fmt(c)], "lines": [fn], "plot": fn}
		"parabola":
			var a := 0.06 * (1.0 if _rng.randf() < 0.5 else -1.0)
			var h := sp
			var c2 := lp
			var fn2 := func(s: float) -> float: return a * (s - h) * (s - h) + c2
			return {"text": "y = %.2f(x − %.0f)² %s" % [a, h, _fmt(c2)], "lines": [fn2], "plot": fn2}
		"absoluto":
			var h2 := sp
			var c3 := lp
			var slope := 0.8 * (1.0 if _rng.randf() < 0.5 else -1.0)
			var fn3 := func(s: float) -> float: return slope * absf(s - h2) + c3
			return {"text": "y = %s|x − %.0f| %s" % ["" if slope > 0 else "−", h2, _fmt(c3)], "lines": [fn3], "plot": fn3}
		_:
			var cs := [lp - 4.0, lp, lp + 4.0]
			var fns := []
			for cc in cs:
				var v: float = cc
				fns.append(func(_s: float) -> float: return v)
			return {"text": "y = {%.0f, %.0f, %.0f}" % cs, "lines": fns, "plot": func(_s: float) -> float: return lp}


func _spawn_path_arrow(b: Dictionary, fn: Callable, fire: bool) -> void:
	var a := PROJ.new()
	a.kind = PROJ.Kind.PATH_ARROW
	a.target = target
	a.boss = self
	a.burn = fire
	a.damage = (8.0 if fire else 12.0) * damage_multiplier
	a.speed = 13.0 if phase == 1 else 16.0
	a.path_origin = (b["pos"] as Vector3) * Vector3(1, 0, 1) + (b["fwd"] as Vector3) * 0.6
	a.path_fwd = b["fwd"]
	a.path_side = b["side"]
	a.path_fn = fn
	a.path_y = 1.25
	a.path_max = 38.0
	fx_parent.add_child(a)


## Dibuja la gráfica de la función en la mitad derecha del pizarrón.
func _draw_graph(b: Dictionary, f: Dictionary, k: float) -> void:
	var gmi: MeshInstance3D = b["graph"]
	var im := ImmediateMesh.new()
	var plot: Callable = f["plot"]
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# ejes
	_seg(im, Vector2(0.0, 0.0), Vector2(1.8, 0.0), 0.012)
	_seg(im, Vector2(0.0, -0.8), Vector2(0.0, 0.8), 0.012)
	var steps := int(40 * k)
	var prev := Vector2.ZERO
	for i in steps + 1:
		var s := 30.0 * float(i) / 40.0
		var p := Vector2(s / 30.0 * 1.8, clampf(float(plot.call(s)) / 10.0, -0.8, 0.8))
		if i > 0:
			_seg(im, prev, p, 0.022)
		prev = p
	im.surface_end()
	gmi.mesh = im


func _seg(im: ImmediateMesh, a: Vector2, b: Vector2, w: float) -> void:
	var d := (b - a)
	if d.length() < 0.0001:
		return
	var n := Vector2(-d.y, d.x).normalized() * w
	var A := Vector3(a.x + n.x, a.y + n.y, 0)
	var B := Vector3(a.x - n.x, a.y - n.y, 0)
	var C := Vector3(b.x - n.x, b.y - n.y, 0)
	var D := Vector3(b.x + n.x, b.y + n.y, 0)
	for v in [A, B, C, A, C, D]:
		im.surface_set_normal(Vector3(0, 0, 1))
		im.surface_add_vertex(v)


func _fade_board(b: Dictionary) -> void:
	var label: Label3D = b["label"]
	var gmi: MeshInstance3D = b["graph"]
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(label, "modulate:a", 0.0, 1.5)
	tw.tween_callback(func():
		label.text = ""
		label.modulate.a = 1.0
		gmi.mesh = null)


# =====================================================================
#  Combate
# =====================================================================

func _valid_target() -> bool:
	return target != null and is_instance_valid(target) and not ("is_dead" in target and target.is_dead)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _clamp(p: Vector3) -> Vector3:
	var l := p - arena_center
	l.x = clampf(l.x, -arena_half.x, arena_half.x)
	l.z = clampf(l.z, -arena_half.y, arena_half.y)
	return Vector3(arena_center.x + l.x, arena_center.y, arena_center.z + l.z)


func _hit(dmg: float, from: Vector3, ignore_iframes: bool) -> void:
	if not _valid_target() or not target.has_method("take_damage"):
		return
	if ignore_iframes and "_iframes" in target:
		target.set("_iframes", 0.0)
	target.take_damage(dmg * damage_multiplier, from)


func _melee(reach: float, dmg: float, shake: float) -> void:
	if not _valid_target():
		return
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() < reach and (-global_basis.z).dot(to.normalized()) > 0.25:
		_hit(dmg, global_position, false)
		LFX.puff(fx_parent, target.global_position + Vector3(0, 1.2, 0), Color(0.6, 0.05, 0.03, 0.9), 10, 0.2, 2.0, -5.0)
		_shake(shake)


func _throw_book(from: Vector3, to: Vector3, t: float, g: float) -> void:
	var b := PROJ.new()
	b.kind = PROJ.Kind.BOOK
	b.target = target
	b.boss = self
	b.damage = 12.0 * damage_multiplier
	b.gravity = g
	b.book_color = _book_color()
	b.velocity = (to - from) / t + Vector3(0, 0.5 * g * t, 0)
	b.position = from
	fx_parent.add_child(b)


func _book_color() -> Color:
	var cs := [Color(0.4, 0.08, 0.06), Color(0.1, 0.16, 0.32), Color(0.12, 0.24, 0.12), Color(0.45, 0.32, 0.12), Color(0.18, 0.1, 0.2)]
	return cs[_rng.randi() % cs.size()]


func _shake(a: float) -> void:
	if _valid_target() and target.has_method("add_camera_shake"):
		target.add_camera_shake(a)


func _w(t: float) -> Signal:
	return get_tree().create_timer(t, false, true).timeout


# =====================================================================
#  Modelo
# =====================================================================

func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation_degrees = rot
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


func _joint(parent: Node3D, key: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = key
	j.position = pos
	parent.add_child(j)
	J[key] = j
	return j


func _box() -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	return b


func _cyl(top := 0.5, segs := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = 0.5
	c.height = 1.0
	c.radial_segments = segs
	c.rings = 1
	return c


func _sph(segs := 14) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = segs
	s.rings = segs / 2
	return s


func _build_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var plaid := LFX.plaid_material()
	var denim := LFX.denim_material()
	m_skin = _mat(Color(0.72, 0.56, 0.47), 0.6)
	var hair := _mat(Color(0.78, 0.78, 0.76), 0.9)
	var leather := _mat(Color(0.2, 0.12, 0.07), 0.6)
	var nails := _mat(Color(0.25, 0.22, 0.18), 0.4)
	var glass_frame := _mat(Color(0.08, 0.08, 0.08), 0.3, 0.6)
	m_eye = LFX.emissive(Color(1.0, 0.85, 0.5), 1.2)
	m_flash = LFX.emissive(Color(1.0, 0.15, 0.08), 0.0, 0.4)
	var box := _box()
	var cyl := _cyl(0.45)
	var limb := _cyl(0.85)
	var sph := _sph()

	var pelvis := _joint(model, "pelvis", Vector3(0, 1.95, 0))
	_part(pelvis, box, denim, Vector3(0, -0.02, 0), Vector3(0.44, 0.24, 0.3))
	_part(pelvis, box, leather, Vector3(0, 0.1, 0), Vector3(0.48, 0.07, 0.34))
	_part(pelvis, box, _mat(Color(0.75, 0.6, 0.25), 0.3, 0.9), Vector3(0, 0.1, -0.175), Vector3(0.1, 0.07, 0.02))
	# Piernas largas
	for sd: float in [-1.0, 1.0]:
		var s := "l" if sd < 0.0 else "r"
		var hip := _joint(pelvis, "hip_" + s, Vector3(sd * 0.13, -0.08, 0))
		_part(hip, limb, denim, Vector3(0, -0.47, 0), Vector3(0.2, 0.94, 0.2))
		var knee := _joint(hip, "kn_" + s, Vector3(0, -0.94, 0))
		_part(knee, sph, denim, Vector3.ZERO, Vector3(0.17, 0.17, 0.17))
		_part(knee, limb, denim, Vector3(0, -0.45, 0), Vector3(0.16, 0.9, 0.16))
		var ankle := _joint(knee, "an_" + s, Vector3(0, -0.9, 0))
		_part(ankle, box, leather, Vector3(0, -0.04, -0.09), Vector3(0.15, 0.1, 0.36))
	# Torso: panza y pecho angosto
	var spine := _joint(pelvis, "spine", Vector3(0, 0.1, 0))
	_part(spine, sph, plaid, Vector3(0, 0.25, -0.08), Vector3(0.52, 0.52, 0.52))
	_part(spine, box, plaid, Vector3(0, 0.3, 0.03), Vector3(0.4, 0.45, 0.3))
	var chest := _joint(spine, "chest", Vector3(0, 0.5, 0))
	_part(chest, box, plaid, Vector3(0, 0.22, 0), Vector3(0.48, 0.5, 0.28))
	_part(chest, box, plaid, Vector3(0, 0.46, 0), Vector3(0.62, 0.1, 0.26))
	_part(chest, box, _mat(Color(0.75, 0.72, 0.62)), Vector3(0, 0.48, -0.1), Vector3(0.18, 0.08, 0.1), Vector3(0, 0, 45))
	var neck := _joint(chest, "neck", Vector3(0, 0.52, 0))
	_part(neck, cyl, m_skin, Vector3(0, 0.07, 0), Vector3(0.12, 0.16, 0.12))
	var head := _joint(neck, "head", Vector3(0, 0.15, 0))
	_part(head, sph, m_skin, Vector3(0, 0.16, 0), Vector3(0.36, 0.44, 0.38))
	_part(head, sph, m_skin, Vector3(0, 0.13, -0.2), Vector3(0.08, 0.12, 0.09))
	for sd: float in [-1.0, 1.0]:
		_part(head, sph, _mat(Color(0.95, 0.93, 0.88)), Vector3(sd * 0.075, 0.2, -0.165), Vector3(0.07, 0.06, 0.04))
		_part(head, sph, m_eye, Vector3(sd * 0.075, 0.2, -0.185), Vector3(0.03, 0.03, 0.02))
		_part(head, box, glass_frame, Vector3(sd * 0.075, 0.2, -0.19), Vector3(0.11, 0.09, 0.01))
		_part(head, box, hair, Vector3(sd * 0.08, 0.27, -0.18), Vector3(0.12, 0.035, 0.04), Vector3(0, 0, sd * -15))
		_part(head, box, glass_frame, Vector3(sd * 0.17, 0.2, -0.08), Vector3(0.01, 0.015, 0.2))
	_part(head, box, glass_frame, Vector3(0, 0.205, -0.19), Vector3(0.04, 0.012, 0.01))
	# Pelo alborotado
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 5
	for i in 14:
		var a := hrng.randf_range(-PI * 0.9, PI * 0.9)
		var p := Vector3(sin(a) * 0.19, hrng.randf_range(0.25, 0.4), cos(a) * 0.17 + 0.03)
		_part(head, _cyl(0.0, 5), hair, p, Vector3(0.08, hrng.randf_range(0.18, 0.32), 0.08), Vector3(hrng.randf_range(-40, 40) + 20, 0, -rad_to_deg(a) * 0.5 + hrng.randf_range(-30, 30)))
	# Barba canosa larga
	_part(head, sph, hair, Vector3(0, -0.06, -0.12), Vector3(0.34, 0.42, 0.26))
	_part(head, _cyl(0.0, 8), hair, Vector3(0, -0.36, -0.13), Vector3(0.26, 0.4, 0.2), Vector3(180, 0, 0))
	_part(head, box, hair, Vector3(0, 0.08, -0.2), Vector3(0.2, 0.04, 0.05))
	# Brazos larguísimos
	for sd: float in [-1.0, 1.0]:
		var s := "l" if sd < 0.0 else "r"
		var sh := _joint(chest, "sh_" + s, Vector3(sd * 0.3, 0.44, 0))
		_part(sh, sph, plaid, Vector3.ZERO, Vector3(0.18, 0.18, 0.18))
		_part(sh, limb, plaid, Vector3(0, -0.36, 0), Vector3(0.14, 0.72, 0.14))
		var el := _joint(sh, "el_" + s, Vector3(0, -0.72, 0))
		_part(el, cyl, plaid, Vector3(0, -0.04, 0), Vector3(0.15, 0.1, 0.15))
		_part(el, limb, m_skin, Vector3(0, -0.36, 0), Vector3(0.1, 0.7, 0.1))
		var wr := _joint(el, "wr_" + s, Vector3(0, -0.7, 0))
		_part(wr, box, m_skin, Vector3(0, -0.07, 0), Vector3(0.09, 0.15, 0.05))
		for f in 4:
			var fx := -0.03 + f * 0.02
			_part(wr, box, m_skin, Vector3(fx, -0.22, -0.02), Vector3(0.016, 0.16, 0.018), Vector3(-15, 0, 0))
			_part(wr, box, nails, Vector3(fx, -0.31, -0.045), Vector3(0.014, 0.05, 0.012), Vector3(-35, 0, 0))
	# Hojas que flotan sobre él en la fase 2
	paper_holder = Node3D.new()
	paper_holder.position = Vector3(0, 4.2, 0)
	paper_holder.visible = false
	add_child(paper_holder)
	m_paper = LFX.emissive(Color(0.65, 0.85, 1.0), 0.6)
	m_paper.albedo_color = Color(0.9, 0.88, 0.8)
	m_paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.32, 0.44)
	for i in 8:
		var p := MeshInstance3D.new()
		p.mesh = q
		p.material_override = m_paper
		p.visible = false
		paper_holder.add_child(p)
		papers.append(p)


func _set_eyes(c: Color, energy: float) -> void:
	m_eye.emission = c
	m_eye.emission_energy_multiplier = energy


func _update_papers(delta: float) -> void:
	if not paper_holder.visible:
		return
	paper_holder.rotation.y += delta * (0.9 + _pain * 2.5)
	for i in papers.size():
		var a := TAU * i / papers.size()
		var p := papers[i]
		p.position = Vector3(cos(a) * 1.7, sin(_anim_t * 2.0 + i) * 0.25, sin(a) * 1.7)
		p.rotation = Vector3(sin(_anim_t + i) * 0.4, -a + PI * 0.5, cos(_anim_t * 1.3 + i) * 0.3)


# =====================================================================
#  Poses
# =====================================================================

func _P(d: Dictionary) -> Dictionary:
	var keys := ["spine", "chest", "neck", "head", "sh_l", "el_l", "wr_l", "sh_r", "el_r", "wr_r", "hip_l", "kn_l", "an_l", "hip_r", "kn_r", "an_r"]
	var out := {"root_y": float(d.get("root_y", 0.0))}
	for k in keys:
		out[k] = d.get(k, Vector3.ZERO)
	return out


func _define_poses() -> void:
	poses["idle"] = _P({"chest": Vector3(-14, 0, 0), "neck": Vector3(-14, 0, 0), "head": Vector3(-4, 0, 8), "sh_l": Vector3(10, 0, -10), "el_l": Vector3(20, 0, 0), "sh_r": Vector3(10, 0, 10), "el_r": Vector3(25, 0, 0), "kn_l": Vector3(-6, 0, 0), "kn_r": Vector3(-6, 0, 0), "hip_l": Vector3(4, 0, 0), "hip_r": Vector3(4, 0, 0)})
	poses["write"] = _P({"chest": Vector3(-6, -18, 0), "head": Vector3(-6, -10, 0), "sh_r": Vector3(140, 0, 18), "el_r": Vector3(45, 0, 0), "wr_r": Vector3(-20, 0, 0), "sh_l": Vector3(25, 0, -18), "el_l": Vector3(70, 0, 0)})
	poses["dash"] = _P({"chest": Vector3(-40, 0, 0), "head": Vector3(25, 0, 0), "sh_l": Vector3(-50, 0, -20), "sh_r": Vector3(-50, 0, 20), "el_l": Vector3(20, 0, 0), "el_r": Vector3(20, 0, 0), "hip_l": Vector3(45, 0, 0), "kn_l": Vector3(-40, 0, 0), "hip_r": Vector3(-25, 0, 0), "kn_r": Vector3(-60, 0, 0)})
	poses["throw_wind"] = _P({"chest": Vector3(10, 40, 0), "sh_r": Vector3(-70, 0, 45), "el_r": Vector3(70, 0, 0), "sh_l": Vector3(60, 0, -25), "hip_r": Vector3(-10, 0, 0), "hip_l": Vector3(20, 0, 0), "kn_l": Vector3(-20, 0, 0)})
	poses["throw"] = _P({"chest": Vector3(-22, -30, 0), "sh_r": Vector3(125, 0, 10), "el_r": Vector3(8, 0, 0), "sh_l": Vector3(-20, 0, -30), "hip_l": Vector3(25, 0, 0), "kn_l": Vector3(-25, 0, 0)})
	poses["scratch_wind_l"] = _P({"chest": Vector3(6, 32, 0), "sh_l": Vector3(110, 0, -70), "el_l": Vector3(95, 0, 0), "wr_l": Vector3(-30, 0, 0), "sh_r": Vector3(40, 0, 30), "el_r": Vector3(40, 0, 0), "kn_l": Vector3(-20, 0, 0), "kn_r": Vector3(-20, 0, 0)})
	poses["scratch_l"] = _P({"chest": Vector3(-28, -32, 0), "head": Vector3(10, 0, 0), "sh_l": Vector3(70, 0, 40), "el_l": Vector3(10, 0, 0), "sh_r": Vector3(30, 0, 25), "hip_l": Vector3(30, 0, 0), "kn_l": Vector3(-30, 0, 0)})
	poses["scratch_wind_r"] = _P({"chest": Vector3(6, -32, 0), "sh_r": Vector3(110, 0, 70), "el_r": Vector3(95, 0, 0), "wr_r": Vector3(-30, 0, 0), "sh_l": Vector3(40, 0, -30), "el_l": Vector3(40, 0, 0), "kn_l": Vector3(-20, 0, 0), "kn_r": Vector3(-20, 0, 0)})
	poses["scratch_r"] = _P({"chest": Vector3(-28, 32, 0), "head": Vector3(10, 0, 0), "sh_r": Vector3(70, 0, -40), "el_r": Vector3(10, 0, 0), "sh_l": Vector3(30, 0, -25), "hip_r": Vector3(30, 0, 0), "kn_r": Vector3(-30, 0, 0)})
	poses["grab_wind"] = _P({"root_y": -0.35, "chest": Vector3(-32, 0, 0), "head": Vector3(30, 0, 0), "sh_l": Vector3(60, 0, -75), "sh_r": Vector3(60, 0, 75), "el_l": Vector3(45, 0, 0), "el_r": Vector3(45, 0, 0), "hip_l": Vector3(50, 0, 0), "hip_r": Vector3(50, 0, 0), "kn_l": Vector3(-80, 0, 0), "kn_r": Vector3(-80, 0, 0), "an_l": Vector3(30, 0, 0), "an_r": Vector3(30, 0, 0)})
	poses["grab_dash"] = _P({"chest": Vector3(-48, 0, 0), "head": Vector3(35, 0, 0), "sh_l": Vector3(100, 0, -22), "sh_r": Vector3(100, 0, 22), "el_l": Vector3(12, 0, 0), "el_r": Vector3(12, 0, 0), "hip_l": Vector3(45, 0, 0), "kn_l": Vector3(-25, 0, 0), "hip_r": Vector3(-35, 0, 0), "kn_r": Vector3(-55, 0, 0)})
	poses["hold"] = _P({"chest": Vector3(-22, 0, 0), "head": Vector3(-10, 0, 0), "sh_l": Vector3(85, 0, -12), "sh_r": Vector3(85, 0, 12), "el_l": Vector3(45, 0, 0), "el_r": Vector3(45, 0, 0), "kn_l": Vector3(-15, 0, 0), "kn_r": Vector3(-15, 0, 0)})
	poses["head_pain"] = _P({"root_y": -0.15, "chest": Vector3(-34, 0, 0), "neck": Vector3(-20, 0, 0), "head": Vector3(-25, 0, 15), "sh_l": Vector3(150, 0, -38), "el_l": Vector3(135, 0, 0), "sh_r": Vector3(150, 0, 38), "el_r": Vector3(135, 0, 0), "kn_l": Vector3(-25, 0, 0), "kn_r": Vector3(-25, 0, 0), "hip_l": Vector3(15, 0, 0), "hip_r": Vector3(15, 0, 0)})
	poses["scream"] = _P({"chest": Vector3(18, 0, 0), "neck": Vector3(10, 0, 0), "head": Vector3(25, 0, 0), "sh_l": Vector3(25, 0, -100), "sh_r": Vector3(25, 0, 100), "el_l": Vector3(35, 0, 0), "el_r": Vector3(35, 0, 0)})
	poses["stagger"] = _P({"chest": Vector3(15, 0, 10), "head": Vector3(20, 0, 0), "sh_l": Vector3(-20, 0, -40), "sh_r": Vector3(-10, 0, 40), "hip_l": Vector3(-15, 0, 0), "kn_r": Vector3(-30, 0, 0)})
	poses["kneel"] = _P({"root_y": -0.85, "chest": Vector3(-30, 0, 0), "head": Vector3(-30, 0, 0), "sh_l": Vector3(30, 0, -10), "sh_r": Vector3(30, 0, 10), "el_l": Vector3(30, 0, 0), "el_r": Vector3(30, 0, 0), "hip_l": Vector3(85, 0, 0), "kn_l": Vector3(-95, 0, 0), "hip_r": Vector3(-10, 0, 0), "kn_r": Vector3(-115, 0, 0)})


func _pose(name: String, dur: float) -> void:
	if not poses.has(name):
		return
	_from = _cur.duplicate()
	_to = poses[name]
	_pose_t = 0.0
	_pose_dur = maxf(dur, 0.01)


func _update_pose(delta: float) -> void:
	_pose_t = minf(1.0, _pose_t + delta / _pose_dur)
	var k := smoothstep(0.0, 1.0, _pose_t)
	for key in _to:
		if key == "root_y":
			_cur[key] = lerpf(float(_from.get(key, 0.0)), float(_to[key]), k)
		else:
			_cur[key] = (_from.get(key, Vector3.ZERO) as Vector3).lerp(_to[key], k)
	var w := _walk_amt
	var sw := sin(_walk_phase * 3.0)
	for key in _cur:
		if key == "root_y":
			continue
		var r: Vector3 = _cur[key]
		match key:
			"hip_l": r.x += sw * 28.0 * w
			"hip_r": r.x -= sw * 28.0 * w
			"kn_l": r.x -= maxf(0.0, -sw) * 40.0 * w
			"kn_r": r.x -= maxf(0.0, sw) * 40.0 * w
			"sh_l": r.x -= sw * 22.0 * w
			"sh_r": r.x += sw * 22.0 * w
			"el_r":
				r.x += sin(_anim_t * 28.0) * 25.0 * _scribble
			"sh_r":
				pass
		if _pain > 0.0 and key in ["head", "chest", "neck"]:
			r += Vector3(randf_range(-6, 6), randf_range(-8, 8), randf_range(-6, 6)) * _pain
		(J[key] as Node3D).rotation_degrees = r
	if _scribble > 0.0:
		(J["sh_r"] as Node3D).rotation_degrees.z += sin(_anim_t * 11.0) * 10.0 * _scribble
	(J["pelvis"] as Node3D).position.y = 1.95 + float(_cur.get("root_y", 0.0)) + absf(sin(_walk_phase * 3.0)) * 0.05 * w
