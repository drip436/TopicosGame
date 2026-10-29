extends RefCounted
## Catálogo de equipo: armas y armaduras que vende el mercader, su precio en créditos y los
## créditos que suelta cada enemigo. El inventario del jugador vive en el autoload "Partida".
##
## Armas: `kind` decide el estilo de pelea (combos y forma de agarrarla):
##   espada   cortes rápidos (Caballero)          mazo   golpes pesados de área (Tanque)
##   estoque  estocadas (Mago)                     lanza  estocadas largas (Arquero)
## Cualquier clase puede usar cualquier arma; la habilidad de la clase (clic derecho) no
## cambia. `model` es modelos/armas_jugador/<model>.glb.
##
## Armaduras: reemplazan la ropa de la clase por modelos/jugador/<model>.glb y bajan los
## estados alterados (veneno, quemadura, electrocutado, atrapado):
##   dur      multiplica la duración del estado    tick  multiplica el daño por segundo
##   buildup  multiplica cuánto sube la barra       grab  daño recibido estando atrapado
##   ignore   probabilidad de no recibir el estado
## `defensa` multiplica además el daño recibido.

const WEAPONS := {
	# Armas iniciales de cada clase
	"espada": {"name": "Espada del Firewall", "kind": "espada", "model": "espada", "damage": 1.0, "speed": 1.0, "price": 0,
		"desc": "Espada larga con acanaladura de datos. Cortes equilibrados."},
	"mazo": {"name": "Martillo del Servidor", "kind": "mazo", "model": "mazo", "damage": 1.0, "speed": 1.0, "price": 0,
		"desc": "Martillo de guerra con núcleo naranja. Lento pero aplasta."},
	"estoque": {"name": "Estoque de Runa", "kind": "estoque", "model": "estoque", "damage": 1.0, "speed": 1.0, "price": 0,
		"desc": "Estoque de guarda de lazo. Estocadas rápidas."},
	"lanza": {"name": "Lanza de Datos", "kind": "lanza", "model": "lanza", "damage": 1.0, "speed": 1.0, "price": 0,
		"desc": "Lanza larga con anillo tecnológico. Mucho alcance."},
	# Del mercader
	"katana_plasma": {"name": "Katana de Plasma", "kind": "espada", "model": "katana_plasma", "damage": 1.15, "speed": 1.25, "price": 900,
		"status": "quemadura", "desc": "Hoja de plasma contenido. Muy rápida; los cortes queman."},
	"mandoble": {"name": "Mandoble del Rector", "kind": "mazo", "model": "mandoble", "damage": 1.55, "speed": 0.9, "price": 2400,
		"desc": "Espadón ceremonial de acero negro y oro. Golpes devastadores."},
	"hacha_servidor": {"name": "Hacha de Rack", "kind": "mazo", "model": "hacha_servidor", "damage": 1.3, "speed": 1.05, "price": 1300,
		"status": "electrocutado", "desc": "Hacha hecha con la puerta de un rack. Descargas eléctricas."},
	"alabarda": {"name": "Alabarda de Fibra Óptica", "kind": "lanza", "model": "alabarda", "damage": 1.3, "speed": 0.95, "price": 1500,
		"desc": "Alabarda con filo de vidrio de fibra óptica. Alcance enorme."},
	"estoque_cuantico": {"name": "Estoque Cuántico", "kind": "estoque", "model": "estoque_cuantico", "damage": 1.25, "speed": 1.2, "price": 1100,
		"status": "veneno", "desc": "Su hoja existe en dos lugares a la vez. Estocadas que envenenan."},
	"espada_cortafuegos": {"name": "Espada Cortafuegos", "kind": "espada", "model": "espada_cortafuegos", "damage": 1.35, "speed": 1.0, "price": 1700,
		"status": "quemadura", "desc": "Espada ancha al rojo vivo. Cada golpe incendia."},
}

## Arma inicial de cada clase ("" = el AI Dev pelea con sus IAs).
const CLASS_WEAPON := {"cyber": "espada", "backend": "mazo", "frontend": "estoque", "data": "lanza", "ai": ""}

const ARMORS := {
	"ignifuga": {"name": "Armadura Cortafuegos", "model": "armadura_ignifuga", "price": 1200, "defensa": 0.9, "color": Color(1.0, 0.45, 0.12),
		"resist": {"quemadura": {"dur": 0.3, "tick": 0.35}},
		"desc": "Acero rojo tiznado con rejillas de lava. Las quemaduras casi no te afectan."},
	"aislante": {"name": "Traje de Faraday", "model": "armadura_aislante", "price": 1200, "defensa": 0.92, "color": Color(0.45, 0.75, 1.0),
		"resist": {"electrocutado": {"dur": 0.3, "ignore": 0.5}},
		"desc": "Malla de cobre y placas de goma con bobinas. La mitad de las descargas no te tocan."},
	"antiveneno": {"name": "Armadura Hazmat Bio-7", "model": "armadura_antiveneno", "price": 1200, "defensa": 0.95, "color": Color(0.4, 0.95, 0.25),
		"resist": {"veneno": {"buildup": 0.35, "dur": 0.6, "tick": 0.4}, "ameba": {"buildup": 0.5}},
		"desc": "Traje de contención con máscara de gas y tanques de aire. El veneno apenas te entra."},
	"anclaje": {"name": "Armadura del Ancla Gravitacional", "model": "armadura_anclaje", "price": 1400, "defensa": 0.85, "color": Color(0.7, 0.45, 1.0),
		"resist": {"atrapado": {"dur": 0.45, "grab": 0.45}},
		"desc": "Acero violeta con núcleos de gravedad. Si te atrapan, te sueltan rápido y dañan poco."},
	"rector": {"name": "Armadura del Rector Caído", "model": "armadura_rector", "price": 3200, "defensa": 0.78, "color": Color(1.0, 0.75, 0.3),
		"resist": {"veneno": {"buildup": 0.7, "tick": 0.7}, "quemadura": {"dur": 0.7, "tick": 0.7}, "electrocutado": {"dur": 0.7, "ignore": 0.2}, "atrapado": {"dur": 0.7, "grab": 0.7}},
		"desc": "Armadura negra y oro de un rector olvidado. Protege de todo un poco y mucho del daño."},
}

## Hechizos del Mago (ids de SPELLS en class_kit.gd). Se lanzan con clic derecho y Q cambia
## entre los que ya aprendiste. Los iniciales vienen con la clase; el resto los vende el
## mercader. Solo el Mago (Frontend) tiene maná para lanzarlos.
const STARTER_SPELLS := ["bola_fuego", "flecha_mat"]
const SPELLS := {
	"bola_fuego": {"name": "Bola de fuego", "price": 0, "desc": "Proyectil de fuego que estalla al impactar."},
	"flecha_mat": {"name": "Flecha matemática", "price": 0, "desc": "Flecha que sigue una función (seno, parábola...) hasta el objetivo."},
	"veneno": {"name": "Frasco de veneno", "price": 600, "desc": "Lanza un frasco que deja un charco tóxico: daño continuo."},
	"nova": {"name": "Nova arcana", "price": 750, "desc": "Explosión de área alrededor del mago. Ideal si te rodean."},
	"rayos": {"name": "Rayos del cielo", "price": 950, "desc": "Invoca tres rayos que caen sobre el objetivo."},
	"lluvia": {"name": "Lluvia de flechas", "price": 1200, "desc": "24 flechas de luz caen sobre la zona del objetivo."},
}

## Créditos que suelta cada enemigo al morir: [mínimo, máximo].
const DROPS := {
	"robot": [12, 20], "robot_hacha": [20, 30], "robot_espada": [20, 30], "robot_laser": [22, 32],
	"androide_espadas": [35, 50], "androide_cables": [35, 50], "androide_script": [40, 55],
	"mutante_peq": [12, 18], "mutante_med": [30, 45], "mutante_grande": [110, 150], "mecha": [180, 240],
}
## Créditos por vencer a cada jefe.
const BOSS_CREDITS := {"profesor": 1200, "biblioteca": 1800, "computo": 2400, "laboratorio": 3000, "final": 5000}


static func weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, {})


static func armor(id: String) -> Dictionary:
	return ARMORS.get(id, {})


static func status_text(effect: String) -> String:
	match effect:
		"quemadura":
			return "Quemadura"
		"electrocutado":
			return "Electrocutado"
		"veneno":
			return "Veneno"
		"atrapado":
			return "Atrapado"
		"ameba":
			return "Ameba"
	return effect.capitalize()
