extends VBoxContainer
## Lista de armas y armaduras con sus estadísticas.
##   modo "equipo"  (menú de pausa): lo que tienes; botón Equipar.
##   modo "tienda"  (mercader): todo lo que vende; botones Comprar y Equipar.
## El inventario y los créditos están en el autoload Partida (ui/partida.gd).

const E := preload("res://ui/estilo.gd")
const EQUIPO := preload("res://jugador/equipo.gd")
const ORO := Color(1.0, 0.84, 0.42)

var modo := "equipo"
var player: Node
var _pestana := "armas"
var _lista: VBoxContainer
var _creditos: Label
var _aviso: Label
var _tabs := {}


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	add_child(top)
	for t in [["armas", "Armas"], ["armaduras", "Armaduras"]]:
		var b := E.boton(t[1], 18, 190, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.toggle_mode = true
		b.pressed.connect(_cambiar.bind(t[0]))
		top.add_child(b)
		_tabs[t[0]] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_creditos = E.etiqueta("", 22, ORO, 700)
	_creditos.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_creditos)
	add_child(E.linea())
	_aviso = E.etiqueta("", 16, E.PELIGRO, 600)
	add_child(_aviso)
	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 10)
	add_child(_lista)
	var p := get_node_or_null("/root/Partida")
	if p:
		p.inventario_cambiado.connect(_refrescar)
		p.creditos_cambiados.connect(func(_t, _g): _refrescar())
	_cambiar("armas")


func _cambiar(t: String) -> void:
	_pestana = t
	for k in _tabs:
		(_tabs[k] as Button).set_pressed_no_signal(k == t)
	_aviso.text = ""
	_refrescar()


func _refrescar() -> void:
	if not is_inside_tree():
		return
	var p := get_node_or_null("/root/Partida")
	if p == null:
		return
	_creditos.text = "◆ %s créditos" % _miles(int(p.creditos))
	for c in _lista.get_children():
		c.queue_free()
	if _pestana == "armas":
		var ids: Array = EQUIPO.WEAPONS.keys() if modo == "tienda" else p.armas
		for id in ids:
			var w: Dictionary = EQUIPO.WEAPONS[id]
			if modo == "tienda" and int(w["price"]) <= 0:
				continue
			_tarjeta("arma", id, w, p.armas.has(id), String(p.arma) == id)
		if modo == "equipo" and player and String(player.get("class_id")) == "ai":
			_tarjeta_simple("arma", "", "Sin arma (pelean tus IAs)", "El clic izquierdo vuelve a ordenar ataques a tu IA.", String(p.arma) == "")
		if ids.is_empty():
			_lista.add_child(E.etiqueta("No tienes armas. El mercader vende varias.", 17, E.TEXTO_TENUE))
	else:
		if modo == "equipo":
			_tarjeta_simple("armadura", "", "Ropa de la clase", "La armadura con la que empezaste. Sin resistencias extra.", String(p.armadura) == "")
		var ids: Array = EQUIPO.ARMORS.keys() if modo == "tienda" else p.armaduras
		for id in ids:
			_tarjeta("armadura", id, EQUIPO.ARMORS[id], p.armaduras.has(id), String(p.armadura) == id)
		if ids.is_empty() and modo == "equipo":
			_lista.add_child(E.etiqueta("Todavía no tienes armaduras: cómpralas al mercader o encuéntralas en el campus.", 17, E.TEXTO_TENUE))


func _tarjeta(tipo: String, id: String, d: Dictionary, tiene: bool, puesto: bool) -> void:
	var pc := E.panel(0.75)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	pc.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	var nombre := E.etiqueta(String(d["name"]).to_upper(), 20, ORO if puesto else E.TEXTO, 700)
	v.add_child(nombre)
	var st := E.etiqueta(_stats(tipo, d), 15, E.NEON, 600)
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(st)
	var ds := E.etiqueta(String(d["desc"]), 15, E.TEXTO_TENUE)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.custom_minimum_size = Vector2(260, 0)
	v.add_child(ds)
	var b := VBoxContainer.new()
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_theme_constant_override("separation", 8)
	h.add_child(b)
	if modo == "tienda" and not tiene:
		var precio := E.etiqueta("◆ %s" % _miles(int(d["price"])), 18, ORO, 700)
		precio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(precio)
		var comprar := E.boton("Comprar", 17, 150, 42)
		comprar.alignment = HORIZONTAL_ALIGNMENT_CENTER
		comprar.pressed.connect(_comprar.bind(tipo, id))
		b.add_child(comprar)
	elif puesto:
		var eq := E.etiqueta("EQUIPADO", 16, ORO, 700)
		eq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		eq.custom_minimum_size = Vector2(150, 0)
		b.add_child(eq)
	else:
		var equipar := E.boton("Equipar", 17, 150, 42)
		equipar.alignment = HORIZONTAL_ALIGNMENT_CENTER
		equipar.pressed.connect(_equipar.bind(tipo, id))
		b.add_child(equipar)
	_lista.add_child(pc)


func _tarjeta_simple(tipo: String, id: String, nombre: String, desc: String, puesto: bool) -> void:
	_tarjeta(tipo, id, {"name": nombre, "desc": desc, "price": 0, "kind": "", "resist": {}}, true, puesto)


func _stats(tipo: String, d: Dictionary) -> String:
	if tipo == "arma":
		if String(d.get("kind", "")) == "":
			return ""
		var kinds := {"espada": "Espada (cortes)", "mazo": "Pesada (golpes de área)", "estoque": "Estoque (estocadas)", "lanza": "Lanza (alcance)"}
		var s := "%s  ·  Daño ×%.2f  ·  Velocidad ×%.2f" % [kinds.get(d["kind"], d["kind"]), float(d.get("damage", 1.0)), float(d.get("speed", 1.0))]
		if d.has("status"):
			s += "  ·  Efecto: " + EQUIPO.status_text(String(d["status"]))
		return s
	var r: Dictionary = d.get("resist", {})
	if r.is_empty():
		return ""
	var parts: Array[String] = ["Daño recibido −%d %%" % roundi((1.0 - float(d.get("defensa", 1.0))) * 100)]
	for eff in r.keys():
		var m: Dictionary = r[eff]
		var best := 1.0
		for k in m.keys():
			if k != "ignore":
				best = minf(best, float(m[k]))
		var txt := "%s −%d %%" % [EQUIPO.status_text(eff), roundi((1.0 - best) * 100)]
		if m.has("ignore"):
			txt += " (%d %% inmune)" % roundi(float(m["ignore"]) * 100)
		parts.append(txt)
	return "  ·  ".join(parts)


func _comprar(tipo: String, id: String) -> void:
	var p := get_node_or_null("/root/Partida")
	var err: String = p.comprar(tipo, id)
	if err != "":
		_aviso.text = err
		return
	_aviso.text = ""
	# Lo recién comprado se equipa de una vez
	p.equipar(tipo, id, player)


func _equipar(tipo: String, id: String) -> void:
	var p := get_node_or_null("/root/Partida")
	p.equipar(tipo, id, player)


static func _miles(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out
