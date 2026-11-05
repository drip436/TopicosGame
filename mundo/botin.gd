extends Node3D
## Botín del campus: armas especiales, épicas y legendarias (jugador/equipo.gd, "rarity")
## en lugares fijos, dentro de COFRES o TIRADAS en el suelo (clavadas, con un haz de luz
## del color de su rareza para verlas de lejos). E abre el cofre o recoge el arma.
##
## Lo crea VidaDelCampus (world_life.gd) al armar el mundo. Lo recogido queda en
## Partida.botin (se guarda al descansar en una hoguera) y el arma pasa a Partida.armas:
## se equipa con I (menú de equipo) o en la pausa.
##
## Especiales: en la avenida y los primeros sectores. Épicas: zonas con enemigos fuertes.
## Legendarias: rincones lejanos o peligrosos, cerca de las últimas arenas.

const EQ := preload("res://jugador/equipo.gd")
const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const E := preload("res://ui/estilo.gd")

## Lugar -> arma, "cofre" o "suelo", punto aproximado (x, z), créditos extra y pista.
const LUGARES := {
	"cofre_avenida": {"arma": "sable_ethernet", "tipo": "cofre", "pos": Vector2(-33, 32), "creditos": 150,
		"pista": "Avenida Universitaria, junto a la barricada poniente"},
	"suelo_torre_agua": {"arma": "mazo_disco_duro", "tipo": "suelo", "pos": Vector2(125, -8), "creditos": 0,
		"pista": "Al pie de la Torre de Agua"},
	"suelo_residencias": {"arma": "lanza_antena", "tipo": "suelo", "pos": Vector2(-205, 60), "creditos": 0,
		"pista": "Entre las Residencias Poniente"},
	"cofre_derecho": {"arma": "estoque_compilador", "tipo": "cofre", "pos": Vector2(-219, -180), "creditos": 400,
		"pista": "Patio de la Facultad de Derecho"},
	"cofre_estadio": {"arma": "guadana_kernel", "tipo": "cofre", "pos": Vector2(-80, -150), "creditos": 400,
		"pista": "En la cancha del Estadio Universitario (cuidado con el mecha)"},
	"suelo_skatepark": {"arma": "espada_neon", "tipo": "suelo", "pos": Vector2(130, -134), "creditos": 0,
		"pista": "Clavada en el Skatepark"},
	"cofre_memorial": {"arma": "excalibyte", "tipo": "cofre", "pos": Vector2(-62, -385), "creditos": 900,
		"pista": "En el Memorial, al fondo del sector norte"},
	"cofre_laboratorio": {"arma": "martillo_singularidad", "tipo": "cofre", "pos": Vector2(215, -300), "creditos": 900,
		"pista": "Patio del Laboratorio de Biogenética"},
	"suelo_explanada": {"arma": "lanza_tesis", "tipo": "suelo", "pos": Vector2(0, -205), "creditos": 0,
		"pista": "Explanada de los Fundadores"},
	"cofre_torre": {"arma": "estoque_root", "tipo": "cofre", "pos": Vector2(148, -380), "creditos": 900,
		"pista": "Estacionamiento de la Torre, en el extremo noreste"},
}
const ALCANCE := 2.3

var vida: Node            # VidaDelCampus (para buscar lugares libres en el suelo)
var player: Node3D
var _items := {}          # id -> {"node", "tipo", "tomado", "color", "arma"}
var _cerca := ""
var _t := 0.0

# Interfaz propia (el HUD de la pelea puede estar oculto fuera de la arena)
var _ui: CanvasLayer
var _prompt: Label
var _tarjeta: PanelContainer
var _tw_tarjeta: Tween


func _ready() -> void:
	_build_ui()
	for id in LUGARES.keys():
		_crear(id)
	if player and player.has_signal("interact_pressed"):
		player.interact_pressed.connect(_on_interact)
	var partida := get_node_or_null("/root/Partida")
	if partida:
		partida.inventario_cambiado.connect(_sincronizar)


func _partida() -> Node:
	return get_node_or_null("/root/Partida")


func _ya_tomado(id: String) -> bool:
	var p := _partida()
	if p == null:
		return false
	return (p.botin as Array).has(id) or (p.armas as Array).has(String(LUGARES[id]["arma"]))


func _crear(id: String) -> void:
	var d: Dictionary = LUGARES[id]
	var w: Dictionary = EQ.weapon(String(d["arma"]))
	if w.is_empty():
		return
	var rz: Dictionary = EQ.RAREZAS.get(String(w.get("rarity", "especial")), EQ.RAREZAS["especial"])
	var col: Color = rz["color"]
	var c := Vector3(d["pos"].x, 0, d["pos"].y)
	var p := c
	if vida and vida.has_method("_free_near"):
		p = vida._free_near(c, 12.0, 0.9)
		if p == Vector3.INF:
			p = c
	p = _fuera_de_fuentes(p)
	p = _salir_de_cerco(p)
	p.y = maxf(p.y, 0.0)
	var tomado := _ya_tomado(id)
	var node: Node3D
	if d["tipo"] == "cofre":
		node = _cofre(col, int(rz["rank"]))
		node.position = p
		node.rotation.y = float(hash(id) % 628) / 100.0
		add_child(node)
		if tomado:
			_dejar_abierto(node)
	else:
		if tomado:
			_items[id] = {"node": null, "tipo": "suelo", "tomado": true, "color": col, "arma": d["arma"]}
			return
		node = _arma_clavada(String(d["arma"]), col, int(rz["rank"]))
		node.position = p
		node.rotation.y = float(hash(id) % 628) / 100.0
		add_child(node)
	node.name = "Botin_" + id
	_items[id] = {"node": node, "tipo": d["tipo"], "tomado": tomado, "color": col, "arma": d["arma"]}


## Respaldo por física: si el punto está rodeado por un muro bajo (el borde de una
## fuente, una jardinera…), lo saca por el lado más cercano. Lanza 12 rayos horizontales a
## la altura de la rodilla; si casi todos chocan cerca, está encerrado.
func _salir_de_cerco(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return p
	for intento in 3:
		var base := Vector3(p.x, p.y + 0.35, p.z)
		var alto := Vector3(p.x, p.y + 1.6, p.z)
		var golpes := 0
		var altos := 0
		var mejor_d := INF
		var mejor_dir := Vector3.ZERO
		for i in 12:
			var a := TAU * i / 12.0
			var dir := Vector3(cos(a), 0, sin(a))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(base, base + dir * 7.0))
			if hit.is_empty():
				continue
			var d := base.distance_to(hit["position"])
			golpes += 1
			# ¿también choca a la altura del pecho? entonces es una pared o un edificio,
			# no el borde bajo de una fuente
			var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(alto, alto + dir * (d + 0.6)))
			if not hit2.is_empty() and alto.distance_to(hit2["position"]) > 0.9:
				altos += 1
				continue
			# el pilar del centro de la fuente queda pegado: no cuenta como salida
			if d > 0.9 and d < mejor_d:
				mejor_d = d
				mejor_dir = dir
		if golpes < 10 or altos > 4 or mejor_dir == Vector3.ZERO:
			return p
		var nuevo := p + mejor_dir * (mejor_d + 1.6)
		# altura del piso afuera
		var abajo := space.intersect_ray(PhysicsRayQueryParameters3D.create(nuevo + Vector3(0, 4, 0), nuevo + Vector3(0, -4, 0)))
		nuevo.y = (abajo["position"] as Vector3).y if not abajo.is_empty() else 0.0
		print("Botín: lugar encerrado en %s, movido a %s" % [p, nuevo])
		p = nuevo
	return p


## Si el lugar cae dentro (o pegado al borde) de una fuente, lo saca al piso de afuera,
## a un paso del borde, del lado más cercano.
func _fuera_de_fuentes(p: Vector3) -> Vector3:
	var world = vida.get("world") if vida else null
	if world == null:
		var s := get_tree().current_scene
		world = s.find_child("CampusWorld", true, false) if s else null
	if world == null or not (world.get("fountains") is Array):
		return p
	for f in world.get("fountains"):
		var c: Vector3 = f[0]
		var r: float = f[1]
		var d := Vector2(p.x - c.x, p.z - c.z)
		if d.length() < r + 1.4:
			var dir := d.normalized() if d.length() > 0.05 else Vector2(1, 0)
			var q := Vector2(c.x, c.z) + dir * (r + 1.8)
			p = Vector3(q.x, 0.0, q.y)
			if vida and vida.has_method("_free_near"):
				var libre: Vector3 = vida._free_near(p, 3.0, 0.9)
				if libre != Vector3.INF and Vector2(libre.x - c.x, libre.z - c.z).length() > r + 1.2:
					p = libre
	return p


# ======================================================================
#  Interacción
# ======================================================================

func _physics_process(delta: float) -> void:
	_t += delta
	if player == null or not is_instance_valid(player):
		return
	var pp := player.global_position
	var mejor := ""
	var md := ALCANCE
	for id in _items:
		var it: Dictionary = _items[id]
		if it["tomado"] or it["node"] == null or not is_instance_valid(it["node"]):
			continue
		var n: Node3D = it["node"]
		var d := Vector2(n.global_position.x - pp.x, n.global_position.z - pp.z).length()
		if d < md and absf(n.global_position.y - pp.y) < 2.0:
			md = d
			mejor = id
		# Haz de luz que respira
		if it["tipo"] == "suelo":
			var haz := n.get_node_or_null("Haz") as MeshInstance3D
			if haz:
				(haz.material_override as StandardMaterial3D).albedo_color.a = 0.22 + 0.1 * sin(_t * 2.0 + hash(id) % 10)
	var muerto: bool = bool(player.get("is_dead")) or bool(player.get("input_locked"))
	if muerto:
		mejor = ""
	if mejor != _cerca:
		_cerca = mejor
		if mejor == "":
			_prompt.text = ""
		elif _items[mejor]["tipo"] == "cofre":
			_prompt.text = "E   Abrir cofre"
		else:
			_prompt.text = "E   Recoger  ·  %s" % String(EQ.weapon(String(_items[mejor]["arma"]))["name"])


func _on_interact() -> void:
	if _cerca == "" or not _items.has(_cerca):
		return
	var id := _cerca
	var it: Dictionary = _items[id]
	if it["tomado"]:
		return
	it["tomado"] = true
	_cerca = ""
	_prompt.text = ""
	if it["tipo"] == "cofre":
		_abrir_cofre(id)
	else:
		_recoger(id)


func _otorgar(id: String) -> void:
	var d: Dictionary = LUGARES[id]
	var arma := String(d["arma"])
	var p := _partida()
	if p:
		if not (p.botin as Array).has(id):
			p.botin.append(id)
		if not (p.armas as Array).has(arma):
			p.armas.append(arma)
		if int(d["creditos"]) > 0:
			p.dar_creditos(int(d["creditos"]))
		p.inventario_cambiado.emit()
	# Notificación arriba a la derecha (antes: tarjeta en medio de la pantalla)
	preload("res://ui/notificaciones.gd").arma(get_tree(), arma, int(d["creditos"]))


## Tras cargar una partida (Partida.aplicar), lo ya recogido desaparece o queda abierto.
func _sincronizar() -> void:
	for id in _items:
		var it: Dictionary = _items[id]
		if it["tomado"] or not _ya_tomado(id):
			continue
		it["tomado"] = true
		var n = it["node"]
		if n == null or not is_instance_valid(n):
			continue
		if it["tipo"] == "cofre":
			_dejar_abierto(n)
		else:
			n.queue_free()
			it["node"] = null


# ======================================================================
#  Cofres
# ======================================================================

func _mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _caja(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Cofre con tapa articulada ("Tapa"). Madera y herrajes según la rareza:
## especial = madera y hierro, épica = madera oscura y plata, legendaria = ébano y oro.
func _cofre(col: Color, rank: int) -> Node3D:
	var root := Node3D.new()
	var maderas := [Color(0.32, 0.18, 0.09), Color(0.14, 0.08, 0.12), Color(0.06, 0.05, 0.05)]
	var metales := [Color(0.36, 0.38, 0.42), Color(0.7, 0.71, 0.78), Color(1.0, 0.74, 0.3)]
	var madera := _mat(maderas[clampi(rank - 1, 0, 2)], 0.8)
	var metal := _mat(metales[clampi(rank - 1, 0, 2)], 0.3, 0.9)
	var brillo := LFX.emissive(col, 3.0)
	_caja(root, Vector3(1.0, 0.5, 0.62), Vector3(0, 0.27, 0), madera)
	_caja(root, Vector3(1.05, 0.06, 0.67), Vector3(0, 0.03, 0), metal)
	for x in [-0.38, 0.38]:
		_caja(root, Vector3(0.07, 0.52, 0.65), Vector3(x, 0.27, 0), metal)
	for x in [-0.5, 0.5]:
		_caja(root, Vector3(0.04, 0.52, 0.65), Vector3(x, 0.27, 0), metal)
	# Tapa: gira sobre la bisagra trasera (frente del cofre = -Z)
	var tapa := Node3D.new()
	tapa.name = "Tapa"
	tapa.position = Vector3(0, 0.52, 0.31)
	root.add_child(tapa)
	_caja(tapa, Vector3(1.0, 0.12, 0.62), Vector3(0, 0.06, -0.31), madera)
	var bombe := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.31
	cm.bottom_radius = 0.31
	cm.height = 1.0
	bombe.mesh = cm
	bombe.material_override = madera
	bombe.rotation.z = PI * 0.5
	bombe.scale = Vector3(1, 1, 0.42)
	bombe.position = Vector3(0, 0.12, -0.31)
	tapa.add_child(bombe)
	for x in [-0.38, 0.38]:
		var banda := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.325
		bc.bottom_radius = 0.325
		bc.height = 0.075
		banda.mesh = bc
		banda.material_override = metal
		banda.rotation.z = PI * 0.5
		banda.scale = Vector3(1, 1, 0.45)
		banda.position = Vector3(x, 0.12, -0.31)
		tapa.add_child(banda)
	# Cerradura con gema del color de la rareza
	_caja(tapa, Vector3(0.18, 0.2, 0.04), Vector3(0, -0.02, -0.635), metal)
	var gema := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 0.04
	gs.height = 0.08
	gema.mesh = gs
	gema.material_override = brillo
	gema.position = Vector3(0, -0.02, -0.665)
	tapa.add_child(gema)
	# Interior que brilla al abrir
	_caja(root, Vector3(0.9, 0.04, 0.52), Vector3(0, 0.5, 0), LFX.emissive(col, 0.8))
	var luz := OmniLight3D.new()
	luz.name = "Luz"
	luz.light_color = col
	luz.light_energy = 0.5 + 0.3 * rank
	luz.omni_range = 2.5 + rank
	luz.position = Vector3(0, 0.9, -0.2)
	luz.shadow_enabled = false
	root.add_child(luz)
	if rank >= 3:
		root.add_child(_chispas(col, 14, 1.2))
	# Colisión
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.05, 0.75, 0.67)
	cs.shape = bs
	cs.position = Vector3(0, 0.37, 0)
	body.add_child(cs)
	root.add_child(body)
	return root


func _dejar_abierto(cofre: Node3D) -> void:
	var tapa := cofre.get_node_or_null("Tapa") as Node3D
	if tapa:
		tapa.rotation.x = 1.95
	var luz := cofre.get_node_or_null("Luz") as OmniLight3D
	if luz:
		luz.light_energy = 0.0
	for c in cofre.get_children():
		if c is GPUParticles3D:
			(c as GPUParticles3D).emitting = false


func _abrir_cofre(id: String) -> void:
	var it: Dictionary = _items[id]
	var cofre: Node3D = it["node"]
	var col: Color = it["color"]
	var tapa := cofre.get_node("Tapa") as Node3D
	var luz := cofre.get_node("Luz") as OmniLight3D
	var tw := create_tween()
	tw.tween_property(tapa, "rotation:x", 1.95, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(luz, "light_energy", 5.0, 0.35)
	tw.tween_property(luz, "light_energy", 0.0, 2.2)
	LFX.puff(self, cofre.global_position + Vector3(0, 0.7, 0), Color(col.r * 2.5, col.g * 2.5, col.b * 2.5, 1), 36, 0.14, 3.0, -1.5)
	if player and player.has_method("add_camera_shake"):
		player.add_camera_shake(0.15)
	# El arma sale flotando del cofre, gira y se guarda en el inventario
	var arma := _modelo(String(it["arma"]), true)
	cofre.add_child(arma)
	arma.position = Vector3(0, 0.35, 0)
	var tw2 := create_tween()
	tw2.tween_interval(0.25)
	tw2.tween_property(arma, "position:y", 1.55, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw2.parallel().tween_property(arma, "rotation:y", TAU * 2.0, 1.6)
	tw2.tween_callback(_otorgar.bind(id))
	tw2.tween_property(arma, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw2.tween_callback(arma.queue_free)
	for c in cofre.get_children():
		if c is GPUParticles3D:
			(c as GPUParticles3D).emitting = false


# ======================================================================
#  Armas tiradas
# ======================================================================

## Modelo del arma (modelos/armas_jugador/<model>.glb). `vertical`: con la punta hacia
## arriba (para mostrarla); si no, en la orientación de la mano.
func _modelo(arma: String, vertical: bool) -> Node3D:
	var holder := Node3D.new()
	var w: Dictionary = EQ.weapon(arma)
	var path := "res://modelos/armas_jugador/%s.glb" % String(w.get("model", arma))
	if ResourceLoader.exists(path):
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		# estoque y lanza apuntan a -Z: se paran girando 90° en X
		if vertical and String(w.get("kind", "")) in ["estoque", "lanza"]:
			inst.rotation.x = PI * 0.5
	else:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 1.0, 0.04)
		b.mesh = bm
		b.position.y = 0.5
		holder.add_child(b)
	return holder


## Arma clavada en el suelo con haz de luz, anillo y chispas del color de su rareza.
func _arma_clavada(arma: String, col: Color, rank: int) -> Node3D:
	var root := Node3D.new()
	var w: Dictionary = EQ.weapon(arma)
	var kind := String(w.get("kind", "espada"))
	var inclin := Node3D.new()
	inclin.name = "Inclin"
	inclin.rotation = Vector3(0.12, 0, 0.22)
	root.add_child(inclin)
	var m := _modelo(arma, false)
	m.name = "Modelo"
	inclin.add_child(m)
	match kind:
		"espada":
			m.rotation.x = PI          # hoja hacia abajo, empuñadura arriba
			m.position.y = 0.85
		"mazo":
			m.rotation.x = PI          # la cabeza en el suelo, el mango arriba
			m.position.y = 1.08
		_:
			m.rotation.x = -PI * 0.5   # estoque y lanza: punta hacia abajo
			m.position.y = 0.95 if kind == "estoque" else 1.05
	# Haz de luz visible de lejos
	var haz := MeshInstance3D.new()
	haz.name = "Haz"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.18 + 0.05 * rank
	cm.height = 6.0 + 2.0 * rank
	cm.radial_segments = 16
	haz.mesh = cm
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.albedo_color = Color(col.r, col.g, col.b, 0.28)
	haz.material_override = hm
	haz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	haz.position.y = cm.height * 0.5
	root.add_child(haz)
	# Anillo en el suelo
	var anillo := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.62
	anillo.mesh = tm
	anillo.material_override = LFX.emissive(col, 2.0)
	anillo.position.y = 0.03
	anillo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(anillo)
	var luz := OmniLight3D.new()
	luz.light_color = col
	luz.light_energy = 1.2 + 0.4 * rank
	luz.omni_range = 4.0 + rank
	luz.position.y = 1.0
	root.add_child(luz)
	root.add_child(_chispas(col, 8 + 4 * rank, 0.7))
	return root


func _chispas(col: Color, n: int, r: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = n
	p.lifetime = 1.6
	p.position.y = 0.3
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = r
	pm.emission_ring_inner_radius = r * 0.6
	pm.emission_ring_height = 0.1
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3.ZERO
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.albedo_color = Color(col.r * 2.0, col.g * 2.0, col.b * 2.0, 0.9)
	q.material = qm
	p.draw_pass_1 = q
	return p


func _recoger(id: String) -> void:
	var it: Dictionary = _items[id]
	var root: Node3D = it["node"]
	var col: Color = it["color"]
	var m := root.get_node_or_null("Inclin/Modelo") as Node3D
	LFX.puff(self, root.global_position + Vector3(0, 1.0, 0), Color(col.r * 2.5, col.g * 2.5, col.b * 2.5, 1), 30, 0.14, 2.5, -1.0)
	var tw := create_tween()
	for c in root.get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			tw.parallel().tween_property(c, "scale", Vector3(0.01, 1.0, 0.01), 0.6)
		elif c is OmniLight3D:
			tw.parallel().tween_property(c, "light_energy", 0.0, 0.6)
		elif c is GPUParticles3D:
			(c as GPUParticles3D).emitting = false
	if m:
		tw.parallel().tween_property(m, "position:y", m.position.y + 0.8, 0.6).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(m, "scale", Vector3.ONE * 0.01, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(_otorgar.bind(id))
	tw.tween_callback(root.queue_free)
	it["node"] = null


# ======================================================================
#  Interfaz: aviso "E" y tarjeta de arma obtenida
# ======================================================================

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 12
	add_child(_ui)
	var raiz := Control.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(raiz)
	_prompt = E.etiqueta("", 22, E.TEXTO, 700)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_top = -190
	_prompt.offset_bottom = -150
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(_prompt)
	_tarjeta = E.panel(0.94)
	_tarjeta.anchor_left = 0.5
	_tarjeta.anchor_right = 0.5
	_tarjeta.offset_left = -330
	_tarjeta.offset_right = 330
	_tarjeta.offset_top = 90
	_tarjeta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tarjeta.modulate.a = 0.0
	raiz.add_child(_tarjeta)


func _mostrar_tarjeta(arma: String, creditos: int) -> void:
	var w: Dictionary = EQ.weapon(arma)
	var rz: Dictionary = EQ.RAREZAS.get(String(w.get("rarity", "especial")), EQ.RAREZAS["especial"])
	var col: Color = rz["color"]
	for c in _tarjeta.get_children():
		c.queue_free()
	_tarjeta.add_theme_stylebox_override("panel", E.caja(0.95, 3, 22, Color(col.r, col.g, col.b, 0.95)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tarjeta.add_child(v)
	var t := E.etiqueta("ARMA OBTENIDA  ·  " + String(rz["name"]).to_upper(), 15, col, 800)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var nombre := E.etiqueta(String(w["name"]).to_upper(), 30, col, 800)
	nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nombre.add_theme_color_override("font_outline_color", Color(col.r, col.g, col.b, 0.4))
	nombre.add_theme_constant_override("outline_size", 6)
	v.add_child(nombre)
	var kinds := {"espada": "Espada", "mazo": "Pesada", "estoque": "Estoque", "lanza": "Lanza"}
	var st := "%s  ·  Daño ×%.2f  ·  Velocidad ×%.2f" % [kinds.get(w["kind"], w["kind"]), float(w["damage"]), float(w["speed"])]
	if w.has("status"):
		st += "  ·  " + EQ.status_text(String(w["status"]))
	var sl := E.etiqueta(st, 16, E.NEON, 600)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sl)
	var ds := E.etiqueta(String(w["desc"]), 15, E.TEXTO_TENUE)
	ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.custom_minimum_size = Vector2(600, 0)
	v.add_child(ds)
	var pie := "Pulsa  I  para equiparla"
	if creditos > 0:
		pie = "+ ◆ %d créditos   ·   %s" % [creditos, pie]
	var pl := E.etiqueta(pie, 16, E.ORO, 700)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pl)
	if _tw_tarjeta and _tw_tarjeta.is_valid():
		_tw_tarjeta.kill()
	_tarjeta.modulate.a = 0.0
	_tw_tarjeta = create_tween()
	_tw_tarjeta.tween_property(_tarjeta, "modulate:a", 1.0, 0.35)
	_tw_tarjeta.tween_interval(4.5)
	_tw_tarjeta.tween_property(_tarjeta, "modulate:a", 0.0, 0.8)
