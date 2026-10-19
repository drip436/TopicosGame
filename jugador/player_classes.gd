extends RefCounted
## Clases del jugador y armaduras de resistencia.
## La clase la elige el selector de builds (Scenes/build_selector.gd) y se guarda
## en `selected`; el jugador (test_player.gd) la lee al aparecer.
## Si se entra directo a main.tscn sin pasar por el selector, se usa `DEFAULT`.

const DEFAULT := "cyber"

## Clase elegida (se conserva al reiniciar la escena).
static var selected: String = ""

## Estadísticas y controles de cada clase.
##   hp, walk/run: velocidad, roll_*: rodada, dmg_taken: daño recibido (armadura),
##   resist: multiplicadores de estados (veneno, quemadura, electrocutado, atrapado).
const CLASSES := {
	"frontend": {
		"name": "Frontend Developer", "role": "Mago",
		"hp": 85.0, "walk": 5.2, "run": 8.0,
		"roll_cost": 20.0, "roll_speed": 10.5, "roll_time": 0.6, "roll_iframes": 0.42,
		"dmg_taken": 1.0, "armor": "ligera",
		"controls": "Clic izq. estoque · Clic der. lanzar hechizo · Q cambiar hechizo · G bebida energética (maná)",
	},
	"backend": {
		"name": "Backend Developer", "role": "Tanque",
		"hp": 150.0, "walk": 3.9, "run": 5.8,
		"roll_cost": 40.0, "roll_speed": 6.0, "roll_time": 0.75, "roll_iframes": 0.28,
		"dmg_taken": 0.7, "armor": "pesada",
		"controls": "Clic izq. mazo · Clic der. golpe sísmico (área) · Armadura pesada: rodar cuesta mucho",
	},
	"ai": {
		"name": "AI Dev", "role": "Invocador",
		"hp": 95.0, "walk": 5.2, "run": 8.0,
		"roll_cost": 20.0, "roll_speed": 10.5, "roll_time": 0.6, "roll_iframes": 0.42,
		"dmg_taken": 1.0, "armor": "ligera",
		"controls": "Clic izq. ataque de la IA · Clic der. ataque especial · Q cambiar IA (ChatGPT / Gemini / Claude)",
	},
	"cyber": {
		"name": "Cybersecurity Engineer", "role": "Caballero",
		"hp": 120.0, "walk": 5.0, "run": 7.6,
		"roll_cost": 22.0, "roll_speed": 10.0, "roll_time": 0.6, "roll_iframes": 0.4,
		"dmg_taken": 0.9, "armor": "básica",
		"controls": "Clic izq. espada · Mantén clic der. para cubrirte con el escudo",
	},
	"data": {
		"name": "Data Scientist", "role": "Arquero",
		"hp": 95.0, "walk": 6.3, "run": 9.6,
		"roll_cost": 18.0, "roll_speed": 11.5, "roll_time": 0.55, "roll_iframes": 0.42,
		"dmg_taken": 0.95, "armor": "básica",
		"controls": "Clic izq. lanza · Clic der. disparar flecha (infinitas) · Más rápido que las demás clases",
	},
}

## Armaduras de resistencia: se encuentran en el campus y se equipan en una hoguera.
##   buildup: cuánto sube la barra (veneno/ameba), dur: duración del estado,
##   tick: daño por tick del estado, grab: daño recibido mientras estás atrapado.
const RESIST_ARMORS := {
	"antiveneno": {"name": "Armadura Antiveneno", "color": Color(0.4, 0.9, 0.25), "effect": "veneno",
		"buildup": 0.35, "dur": 0.6, "tick": 0.4, "desc": "La barra de VENENO sube mucho menos y el veneno hace poco daño."},
	"ignifuga": {"name": "Armadura Ignífuga", "color": Color(1.0, 0.5, 0.15), "effect": "quemadura",
		"dur": 0.4, "tick": 0.5, "desc": "Las quemaduras duran menos y hacen la mitad de daño."},
	"aislante": {"name": "Armadura Aislante", "color": Color(0.45, 0.75, 1.0), "effect": "electrocutado",
		"dur": 0.3, "ignore": 0.5, "desc": "La mitad de las veces no te electrocutan y, si pasa, dura muy poco."},
	"anclaje": {"name": "Armadura de Anclaje", "color": Color(0.75, 0.7, 0.6), "effect": "atrapado",
		"dur": 0.5, "grab": 0.5, "desc": "Si te atrapan, te sueltan antes y recibes la mitad del daño."},
}


static func current() -> String:
	return selected if CLASSES.has(selected) else DEFAULT


static func data(id: String = "") -> Dictionary:
	return CLASSES.get(id if id != "" else current(), CLASSES[DEFAULT])
