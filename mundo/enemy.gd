extends CharacterBody3D
## Enemigo común del campus (no es jefe). El tipo se elige con `type`:
##   "robot"           robot vigilante pequeño: puñetazos y embestidas.
##   "robot_hacha"     robot mediano con hacha gigante: hachazo y barrido lentos y fuertes.
##   "robot_espada"    robot mediano con espada: combo de dos tajos y estocada.
##   "robot_laser"     robot mediano con pistola láser: dispara ráfagas a distancia.
##   "mecha"           mecha gigante que merodea zonas abiertas: barrido, pisotón y cañón.
##   "androide_espadas" androide caballero (Cómputo) con dos hojas: combo triple,
##                     estocada y "compilar" (arma de luz para un tajo enorme).
##   "androide_cables"  androide con cables de servidor: latigazo eléctrico a distancia
##                     y pulso alrededor de él (electrocuta).
##   "androide_script"  androide que lanza scripts: rayos, sello mágico y armas que caen.
##   Los androides son versiones pequeñas de ADA-7 y no tienen puntos ciegos: si te
##   quedas detrás o pegado, sueltan un pulso eléctrico.
##   "mutante_peq"     sabueso rastrero, rápido: mordidas y saltos (veneno).
##   "mutante_med"     ghoul encorvado con garras: zarpazos, frenesí y escupitajo (veneno).
##   "mutante_grande"  mole de carne: aplastón de área, manotazo, escupitajos y embestida.
## Los mutantes llenan la barra de VENENO del jugador al golpearlo. Son bestias salvajes
## y torpes: rugen al verte (y despiertan a los demás), a veces se quedan olfateando,
## se tropiezan si fallan un salto o un frenesí, y la mole se estrella si embiste una pared.
## Lo crea y lo reinicia "VidaDelCampus" (world_life.gd), pero también puedes
## instanciar Enemigo.tscn a mano en cualquier escena y elegir el tipo.

signal died(enemy: Node)

const MODELS := preload("enemy_models.gd")

## Modelos hechos en Blender (arte/blender/*.py → modelos/*.glb), con esqueleto y
## animaciones. Si el archivo no existe se usa el modelo procedural de enemy_models.gd.
##   tipo -> [ruta, escala, tinte de la pintura, arma ("" = sin arma)]
const GLB_MODELS := {
	"robot": ["res://modelos/robot/robot.glb", 0.88, Color(1, 1, 1), ""],
	"robot_hacha": ["res://modelos/robot/robot.glb", 1.28, Color(1.0, 0.68, 0.32), "hacha"],
	"robot_espada": ["res://modelos/robot/robot.glb", 1.25, Color(0.6, 0.7, 0.88), "espada"],
	"robot_laser": ["res://modelos/robot/robot.glb", 1.25, Color(0.5, 0.52, 0.56), "laser"],
	"mecha": ["res://modelos/mecha/mecha.glb", 1.0, Color(1, 1, 1), ""],
	"androide_espadas": ["res://modelos/androide/androide.glb", 1.2, Color(1, 1, 1), "dual"],
	"androide_cables": ["res://modelos/androide/androide.glb", 1.2, Color(0.82, 0.92, 1.0), ""],
	"androide_script": ["res://modelos/androide/androide.glb", 1.16, Color(0.95, 0.85, 1.0), ""],
	"mutante_peq": ["res://modelos/mutante/mutante_peq.glb", 1.0, Color(1, 1, 1), ""],
	"mutante_med": ["res://modelos/mutante/mutante_med.glb", 1.12, Color(1, 1, 1), ""],
	"mutante_grande": ["res://modelos/mutante/mutante_grande.glb", 1.15, Color(1, 1, 1), ""],
}
## Velocidad (m/s) a la que corresponden las animaciones de caminar y correr de cada modelo.
const GLB_LOCO := {"mecha": [1.8, 3.0], "androide": [1.25, 2.9], "mutante_peq": [0.95, 3.2], "mutante_med": [1.15, 3.6], "mutante_grande": [1.0, 2.6]}
## Armas hechas en Blender (modelos/armas). Se modelan a lo largo de −Y con el filo hacia −Z.
const GLB_WEAPONS := {"hacha": "res://modelos/armas/hacha.glb", "espada": "res://modelos/armas/espada.glb", "laser": "res://modelos/armas/pistola_laser.glb",
	"dual": "res://modelos/armas/hoja_androide.glb"}
## Animación del modelo para cada pose de ataque.
## Segundo de cada animación en el que cae el golpe (ver arte/blender/robot.py).
const GLB_IMPACT := {"jab": 0.62, "lunge": 0.6, "overhead": 0.78, "sweep": 0.72, "slash": 0.5, "thrust": 0.6,
	"dual": 0.45, "compile": 1.3, "lash": 0.55, "cast": 0.7, "pulse": 0.6}
const GLB_IMPACT_BY_TYPE := {"mecha": {"sweep": 0.85, "stomp": 0.8},
	"mutante_peq": {"bite": 0.4, "pounce": 0.55},
	"mutante_med": {"slash": 0.55, "frenzy": 0.5, "spit": 0.8},
	"mutante_grande": {"overhead": 1.2, "sweep": 0.9, "spit": 1.0}}
## Rugido de las bestias (no hace daño: despierta a los mutantes cercanos y deja un hueco para pegarles).
const ROAR := {"id": "rugido", "kind": "roar", "wind": 0.35, "dur": 1.6, "pose": "roar", "min": 0.0, "max": 99.0, "w": 0}
const GLB_ATTACK_ANIM := {"jab": "jab", "overhead": "overhead", "sweep": "sweep", "slash": "slash", "thrust": "thrust", "aim": "aim", "stomp": "overhead", "spit": "jab", "bite": "jab", "pounce": "lunge"}
## Código que flota alrededor de los androides al lanzar cada ataque (como ADA-7).
const SPELL_CODE := {
	"rayos": ["hechizo.electricidad()", "for p in objetivos:", "    rayo(p)"],
	"sello": ["hechizo.magia()", "sello = Area.new(r=3)", "sello.estallar()"],
	"lluvia": ["for arma in arsenal:", "    arma.caer_sobre(jugador)"],
	"lash": ["cables.azotar(objetivo)", "voltaje = 220"],
	"compile": ["compilar(EspadaGrande)", "arma.daño = 9999", "arma.equipar(mano_der)"],
	"death": ["Segmentation fault", "(core dumped)", "proceso terminado"],
}
const BOLT := preload("enemy_bolt.gd")
const LFX := preload("res://boss_bibliotecario/library_fx.gd")
const FX := preload("res://boss_profesor/boss_fx.gd")

enum State { IDLE, WANDER, CHASE, ATTACK, STAGGER, RETURN, DEAD }

const TYPES := {
	"robot": {"hp": 60.0, "walk": 1.6, "run": 4.4, "radius": 0.42, "height": 1.5, "sight": 15.0, "poise": 0.0, "turn": 8.0,
		"attacks": [
			{"id": "puñetazo", "wind": 0.45, "dur": 0.95, "reach": 1.8, "arc": 0.4, "dmg": 8.0, "lunge": 3.0, "min": 0.0, "max": 2.1, "pose": "jab", "w": 3},
			{"id": "embestida", "wind": 0.6, "dur": 1.45, "reach": 2.0, "arc": 0.3, "dmg": 10.0, "lunge": 9.0, "min": 2.4, "max": 5.5, "pose": "jab", "w": 2}]},
	"robot_hacha": {"hp": 150.0, "walk": 1.3, "run": 3.1, "radius": 0.6, "height": 2.3, "sight": 16.0, "poise": 75.0, "turn": 5.0,
		"attacks": [
			{"id": "hachazo", "wind": 1.0, "dur": 2.5, "reach": 3.3, "arc": 0.5, "dmg": 22.0, "lunge": 2.5, "min": 0.0, "max": 3.1, "pose": "overhead", "w": 3},
			{"id": "barrido", "wind": 0.8, "dur": 1.9, "reach": 3.4, "arc": -0.3, "dmg": 16.0, "lunge": 1.5, "min": 0.0, "max": 3.1, "pose": "sweep", "w": 2}]},
	"robot_espada": {"hp": 130.0, "walk": 1.5, "run": 3.8, "radius": 0.55, "height": 2.2, "sight": 16.0, "poise": 60.0, "turn": 6.5,
		"attacks": [
			{"id": "tajos", "wind": 0.5, "dur": 1.75, "reach": 2.8, "arc": 0.3, "dmg": 12.0, "lunge": 4.0, "min": 0.0, "max": 2.6, "pose": "slash", "hits": 2, "gap": 0.45, "w": 3},
			{"id": "estocada", "wind": 0.75, "dur": 1.75, "reach": 3.3, "arc": 0.6, "dmg": 15.0, "lunge": 10.0, "min": 2.8, "max": 6.5, "pose": "thrust", "w": 2}]},
	"robot_laser": {"hp": 100.0, "walk": 1.5, "run": 3.6, "radius": 0.5, "height": 2.2, "sight": 20.0, "poise": 55.0, "turn": 6.0, "keep_away": 8.0,
		"attacks": [
			{"id": "ráfaga", "kind": "shoot", "wind": 0.7, "dur": 1.7, "dmg": 11.0, "shots": 3, "gap": 0.22, "min": 4.0, "max": 22.0, "pose": "aim", "speed": 24.0, "w": 4},
			{"id": "culatazo", "wind": 0.5, "dur": 1.0, "reach": 2.0, "arc": 0.4, "dmg": 9.0, "lunge": 3.0, "min": 0.0, "max": 2.4, "pose": "jab", "w": 3}]},
	"mecha": {"hp": 650.0, "walk": 2.0, "run": 3.1, "radius": 1.5, "height": 5.0, "sight": 28.0, "poise": 99999.0, "turn": 2.2, "wander": 24.0,
		"attacks": [
			{"id": "barrido", "wind": 1.1, "dur": 2.1, "reach": 5.8, "arc": -0.2, "dmg": 26.0, "lunge": 1.0, "min": 0.0, "max": 5.3, "pose": "sweep", "w": 3},
			{"id": "pisotón", "kind": "aoe", "wind": 1.2, "dur": 2.0, "radius": 6.0, "dmg": 24.0, "min": 0.0, "max": 4.5, "pose": "stomp", "w": 3},
			{"id": "cañón", "kind": "shoot", "wind": 1.0, "dur": 2.4, "dmg": 14.0, "shots": 6, "gap": 0.14, "min": 7.0, "max": 32.0, "pose": "aim", "speed": 30.0, "size": 2.0, "w": 4}]},
	# Androides del Centro de Cómputo (mini ADA-7). "electric" = probabilidad de electrocutar,
	# "cd" = enfriamiento propio del ataque, "behind" = solo si el jugador está detrás o pegado.
	"androide_espadas": {"hp": 125.0, "walk": 1.6, "run": 4.0, "radius": 0.45, "height": 2.1, "sight": 17.0, "poise": 55.0, "turn": 6.5, "android": true,
		"attacks": [
			{"id": "tajos dobles", "wind": 0.45, "dur": 2.0, "reach": 2.6, "arc": 0.2, "dmg": 9.0, "lunge": 3.5, "min": 0.0, "max": 2.5, "pose": "dual", "hits": 3, "gap": 0.38, "w": 4},
			{"id": "estocada", "wind": 0.6, "dur": 1.45, "reach": 3.0, "arc": 0.6, "dmg": 14.0, "lunge": 11.0, "min": 2.6, "max": 6.5, "pose": "thrust", "w": 2},
			{"id": "compilar", "kind": "compile", "wind": 1.3, "dur": 2.2, "reach": 3.9, "arc": -0.15, "dmg": 19.0, "lunge": 3.0, "min": 0.0, "max": 3.6, "pose": "compile", "cd": 9.0, "w": 2},
			{"id": "pulso", "kind": "aoe", "wind": 0.6, "dur": 1.4, "radius": 3.0, "dmg": 10.0, "electric": 0.5, "min": 0.0, "max": 2.6, "pose": "pulse", "behind": true, "cd": 4.0, "w": 6}]},
	"androide_cables": {"hp": 110.0, "walk": 1.6, "run": 3.9, "radius": 0.45, "height": 2.1, "sight": 18.0, "poise": 50.0, "turn": 6.0, "keep_away": 5.0, "android": true,
		"attacks": [
			{"id": "latigazo", "kind": "lash", "wind": 0.55, "dur": 1.4, "reach": 7.5, "dmg": 12.0, "electric": 0.35, "min": 1.5, "max": 7.2, "pose": "lash", "w": 4},
			{"id": "latigazo doble", "kind": "lash", "wind": 0.55, "dur": 1.4, "reach": 7.5, "dmg": 10.0, "electric": 0.3, "shots": 2, "min": 2.5, "max": 7.2, "pose": "lash", "cd": 5.0, "w": 2},
			{"id": "pulso", "kind": "aoe", "wind": 0.6, "dur": 1.4, "radius": 3.4, "dmg": 12.0, "electric": 0.5, "min": 0.0, "max": 2.6, "pose": "pulse", "w": 3}]},
	"androide_script": {"hp": 95.0, "walk": 1.5, "run": 3.6, "radius": 0.45, "height": 2.0, "sight": 21.0, "poise": 45.0, "turn": 6.0, "keep_away": 9.0, "android": true,
		"attacks": [
			{"id": "rayos", "kind": "spell", "spell": "rayos", "wind": 0.7, "dur": 1.9, "dmg": 13.0, "electric": 0.4, "min": 2.5, "max": 19.0, "pose": "cast", "cd": 3.0, "w": 3},
			{"id": "sello", "kind": "spell", "spell": "sello", "wind": 0.7, "dur": 1.8, "dmg": 17.0, "min": 2.5, "max": 19.0, "pose": "cast", "cd": 3.0, "w": 3},
			{"id": "lluvia de armas", "kind": "spell", "spell": "lluvia", "wind": 0.7, "dur": 2.1, "dmg": 15.0, "min": 3.0, "max": 19.0, "pose": "cast", "cd": 7.0, "w": 2},
			{"id": "pulso", "kind": "aoe", "wind": 0.6, "dur": 1.4, "radius": 3.0, "dmg": 10.0, "electric": 0.5, "min": 0.0, "max": 2.6, "pose": "pulse", "w": 4}]},
	"mutante_peq": {"hp": 45.0, "walk": 1.5, "run": 5.4, "radius": 0.4, "height": 0.9, "sight": 13.0, "poise": 0.0, "turn": 9.0, "mutant": true,
		"attacks": [
			{"id": "mordida", "wind": 0.4, "dur": 0.95, "reach": 1.6, "arc": 0.4, "dmg": 6.0, "buildup": 20.0, "lunge": 5.0, "min": 0.0, "max": 2.0, "pose": "bite", "w": 3},
			{"id": "salto", "wind": 0.55, "dur": 1.25, "reach": 2.0, "arc": 0.3, "dmg": 8.0, "buildup": 26.0, "lunge": 11.0, "min": 2.5, "max": 7.0, "pose": "pounce", "tumble": 0.55, "w": 2}]},
	"mutante_med": {"hp": 140.0, "walk": 1.4, "run": 4.2, "radius": 0.55, "height": 2.0, "sight": 15.0, "poise": 60.0, "turn": 6.0, "mutant": true,
		"attacks": [
			{"id": "zarpazos", "wind": 0.55, "dur": 1.6, "reach": 2.7, "arc": 0.3, "dmg": 11.0, "buildup": 22.0, "lunge": 4.0, "min": 0.0, "max": 2.6, "pose": "slash", "hits": 2, "gap": 0.4, "w": 3},
			{"id": "frenesí", "wind": 0.5, "dur": 2.2, "reach": 2.5, "arc": 0.2, "dmg": 7.0, "buildup": 12.0, "lunge": 3.5, "min": 0.0, "max": 3.0, "pose": "frenzy", "hits": 4, "gap": 0.3, "tumble": 0.45, "cd": 6.0, "w": 2},
			{"id": "escupitajo", "kind": "spit", "wind": 0.8, "dur": 1.4, "dmg": 8.0, "buildup": 30.0, "shots": 1, "min": 4.5, "max": 14.0, "pose": "spit", "w": 2}]},
	"mutante_grande": {"hp": 480.0, "walk": 1.3, "run": 2.9, "radius": 1.1, "height": 3.4, "sight": 18.0, "poise": 99999.0, "turn": 3.2, "mutant": true,
		"attacks": [
			{"id": "aplastón", "kind": "aoe", "wind": 1.2, "dur": 2.0, "radius": 4.8, "dmg": 22.0, "buildup": 35.0, "min": 0.0, "max": 4.0, "pose": "overhead", "w": 3},
			{"id": "manotazo", "wind": 0.9, "dur": 1.8, "reach": 4.3, "arc": -0.1, "dmg": 20.0, "buildup": 28.0, "lunge": 2.0, "min": 0.0, "max": 4.0, "pose": "sweep", "w": 3},
			{"id": "embestida", "kind": "charge", "wind": 0.9, "dur": 2.4, "reach": 1.6, "dmg": 22.0, "buildup": 20.0, "speed": 8.5, "min": 5.0, "max": 16.0, "pose": "roar", "cd": 7.0, "w": 3},
			{"id": "escupitajos", "kind": "spit", "wind": 1.0, "dur": 1.7, "dmg": 10.0, "buildup": 30.0, "shots": 3, "gap": 0.18, "min": 5.0, "max": 16.0, "pose": "spit", "size": 1.6, "w": 2}]},
}

## Poses de ataque: [preparación, golpe]; cada una es articulación -> grados.
const POSES := {
	"jab": [{"arm_r": Vector3(-40, 0, 0), "fore_r": Vector3(80, 0, 0), "torso": Vector3(0, -25, 0)},
		{"arm_r": Vector3(88, 0, 0), "fore_r": Vector3(5, 0, 0), "torso": Vector3(-10, 20, 0)}],
	"overhead": [{"arm_r": Vector3(170, 0, 0), "arm_l": Vector3(160, 0, 0), "torso": Vector3(12, 0, 0), "fore_r": Vector3(20, 0, 0)},
		{"arm_r": Vector3(55, 0, 0), "arm_l": Vector3(50, 0, 0), "torso": Vector3(-22, 0, 0)}],
	"sweep": [{"torso": Vector3(0, -75, 0), "arm_r": Vector3(80, 0, 35)},
		{"torso": Vector3(-5, 75, 0), "arm_r": Vector3(80, 0, 35)}],
	"slash": [{"arm_r": Vector3(150, 0, -25), "torso": Vector3(0, -30, 0), "arm_l": Vector3(40, 0, 20)},
		{"arm_r": Vector3(35, 0, 30), "torso": Vector3(-12, 30, 0), "arm_l": Vector3(70, 0, -20)}],
	"thrust": [{"arm_r": Vector3(-20, 0, 0), "fore_r": Vector3(100, 0, 0), "torso": Vector3(0, -30, 0)},
		{"arm_r": Vector3(92, 0, 0), "fore_r": Vector3(0, 0, 0), "torso": Vector3(-12, 15, 0)}],
	"aim": [{"arm_r": Vector3(88, 0, 0), "fore_r": Vector3(2, 0, 0), "torso": Vector3(0, 10, 0)},
		{"arm_r": Vector3(95, 0, 0), "fore_r": Vector3(-5, 0, 0), "torso": Vector3(4, 10, 0)}],
	"stomp": [{"leg_r": Vector3(55, 0, 0), "shin_r": Vector3(-55, 0, 0), "torso": Vector3(8, 0, 0), "arm_l": Vector3(30, 0, -20), "arm_r": Vector3(30, 0, 20)},
		{"leg_r": Vector3(-5, 0, 0), "torso": Vector3(-10, 0, 0), "arm_l": Vector3(0, 0, -30), "arm_r": Vector3(0, 0, 30)}],
	"spit": [{"head": Vector3(35, 0, 0), "jaw": Vector3(-10, 0, 0), "torso": Vector3(14, 0, 0)},
		{"head": Vector3(-15, 0, 0), "jaw": Vector3(-40, 0, 0), "torso": Vector3(-14, 0, 0)}],
	"bite": [{"torso": Vector3(18, 0, 0), "jaw": Vector3(-30, 0, 0)},
		{"torso": Vector3(-14, 0, 0), "jaw": Vector3(5, 0, 0)}],
	"pounce": [{"torso": Vector3(-10, 0, 0), "hip": Vector3(0, 0, 0), "jaw": Vector3(-20, 0, 0)},
		{"torso": Vector3(22, 0, 0), "jaw": Vector3(-40, 0, 0)}],
	"stagger": [{"torso": Vector3(22, 0, 0), "head": Vector3(25, 0, 0), "arm_l": Vector3(40, 0, -35), "arm_r": Vector3(40, 0, 35)},
		{"torso": Vector3(22, 0, 0)}],
}

const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
instance uniform float ratio = 1.0;
instance uniform float trail = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV;
	bool border = uv.x < 0.015 || uv.x > 0.985 || uv.y < 0.14 || uv.y > 0.86;
	vec3 c = vec3(0.04, 0.03, 0.03);
	if (uv.x < trail) c = vec3(0.8, 0.65, 0.3);
	if (uv.x < ratio) c = vec3(0.6, 0.07, 0.05);
	ALBEDO = border ? vec3(0.0) : c;
	ALPHA = 0.9;
}
"""
static var _bar_shader: Shader

@export_enum("robot", "robot_hacha", "robot_espada", "robot_laser", "mecha", "androide_espadas", "androide_cables", "androide_script", "mutante_peq", "mutante_med", "mutante_grande") var type: String = "robot"
## Radio en el que pasea o merodea alrededor de su punto de inicio.
@export var wander_radius: float = 6.0

var home := Vector3.ZERO
var target: Node3D
var fx_parent: Node
var max_hp := 60.0
var hp := 60.0
var is_dead := false
var hit_radius := 0.5
var state: int = State.IDLE

var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _model: Dictionary
var J := {}
var _cur := {}
var _pose := {}
var _pose_rate := 10.0
var _walk_ph := 0.0
var _walk_amt := 0.0
var _t := 0.0
var _cd := 1.0
var _atk: Dictionary
var _atk_t := 0.0
var _hit_idx := 0
var _shot_idx := 0
var _poise_acc := 0.0
var _wander_to := Vector3.ZERO
var _wander_wait := 0.0
var _sight_t := 0.0
var _seen := false
var _steer := 0.0
var _steer_t := 0.0
var _stuck_t := 0.0
var _flash_t := 0.0
var _overlay: StandardMaterial3D
var _bar: MeshInstance3D
var _bar_t := 0.0
var _trail := 1.0
var _aggro_color := Color(1.0, 0.15, 0.1)
var _idle_color := Color(1.0, 0.6, 0.15)
var _placed := false
var _atk_cd := {}
var _landed := false
var _stagger_dur := 0.55
var _stumble := false
var _feral_t := 4.0
var _distract_t := 0.0
var _cd_stamp := 0
var _lash_dir := Vector3.ZERO


func _ready() -> void:
	_rng.randomize()
	_cfg = TYPES.get(type, TYPES["robot"])
	max_hp = _cfg["hp"]
	hp = max_hp
	hit_radius = _cfg["radius"]
	if _cfg.has("wander"):
		wander_radius = maxf(wander_radius, _cfg["wander"])
	add_to_group("enemy")
	if not _placed:
		home = global_position
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = _cfg["radius"]
	cap.height = maxf(_cfg["height"], cap.radius * 2.0 + 0.1)
	cs.shape = cap
	cs.position = Vector3(0, cap.height * 0.5, 0)
	add_child(cs)
	_build_model()
	_build_bar()
	_wander_to = home
	_wander_wait = _rng.randf_range(0.5, 3.0)
	if target == null:
		var ps := get_tree().get_nodes_in_group("player")
		if ps.size() > 0:
			target = ps[0]
	if fx_parent == null:
		fx_parent = get_parent()


## Lo usa VidaDelCampus antes de agregarlo al árbol.
func place(pos: Vector3, yaw: float) -> void:
	home = pos
	position = pos
	rotation.y = yaw
	_placed = true


func _build_model() -> void:
	if _cfg.get("android", false):
		_idle_color = Color(0.3, 0.9, 1.0)
		_aggro_color = Color(1.0, 0.22, 0.3)
	if GLB_MODELS.has(type) and ResourceLoader.exists(GLB_MODELS[type][0]):
		_build_glb_model()
		return
	match type:
		"robot":
			_model = MODELS.robot(1.0, "", _rng)
		"robot_hacha":
			_model = MODELS.robot(1.45, "hacha", _rng)
		"robot_espada":
			_model = MODELS.robot(1.4, "espada", _rng)
		"robot_laser":
			_model = MODELS.robot(1.4, "laser", _rng)
		"mecha":
			_model = MODELS.mech(_rng)
		"mutante_peq":
			_model = MODELS.mutant_small(_rng)
		"mutante_med":
			_model = MODELS.mutant_medium(_rng)
		_:
			_model = MODELS.mutant_large(_rng)
	if _cfg.get("mutant", false):
		_aggro_color = Color(0.7, 1.0, 0.2)
		_idle_color = Color(0.45, 1.0, 0.2)
	add_child(_model["root"])
	J = _model["J"]
	for k in J.keys():
		_cur[k] = Vector3.ZERO
	_overlay = StandardMaterial3D.new()
	_overlay.albedo_color = Color(1, 1, 1, 0.45)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.emission_enabled = true
	_overlay.emission = Color(1, 0.9, 0.8)
	_overlay.emission_energy_multiplier = 1.5
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Sombras solo en los grandes (rendimiento)
	var shadows: bool = type in ["mecha", "mutante_grande"]
	for mi in _model["meshes"]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_set_eyes(false)


## Modelo de Blender: escena glTF con esqueleto (Skeleton3D) y AnimationPlayer.
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _weapon_r: Node3D
var _anim_cur := ""
var _glb_speed := 1.0


func _build_glb_model() -> void:
	var info: Array = GLB_MODELS[type]
	var scene: Node3D = (load(info[0]) as PackedScene).instantiate()
	var root := Node3D.new()
	root.name = "Modelo"
	root.scale = Vector3.ONE * float(info[1])
	root.add_child(scene)
	add_child(root)
	_model = {"root": root, "J": {}, "eyes": [], "meshes": [], "kind": "glb"}
	J = {}
	_anim = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var sks := scene.find_children("*", "Skeleton3D", true, false)
	if sks.size() > 0:
		_skel = sks[0]
	for a in ["idle", "walk", "run", "aim"]:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	var tint: Color = info[2]
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		_model["meshes"].append(m3)
		for si in m3.mesh.get_surface_count():
			var mat := m3.mesh.surface_get_material(si)
			if mat == null:
				continue
			if mat.resource_name == "ojos":
				var em := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				em.emission_enabled = true
				m3.set_surface_override_material(si, em)
				_model["eyes"].append(em)
			elif tint != Color(1, 1, 1):
				var tm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				tm.albedo_color = tint
				m3.set_surface_override_material(si, tm)
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Boca de disparo incluida en el modelo (cañón del mecha)
	var own_mz := scene.find_child("muzzle", true, false)
	if own_mz:
		J["muzzle"] = own_mz
	# Arma en la mano derecha
	var weapon: String = info[3]
	if weapon != "" and GLB_WEAPONS.has(weapon) and ResourceLoader.exists(GLB_WEAPONS[weapon]) and _skel:
		_weapon_r = _attach_glb(GLB_WEAPONS[weapon], "hand_r")
		if weapon == "dual":
			_attach_glb(GLB_WEAPONS[weapon], "hand_l")
	elif weapon != "":
		var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
		var proc := MODELS.robot(1.0, weapon, _rng)
		var w: Node3D = proc["J"].get("weapon")
		if w:
			var at := BoneAttachment3D.new()
			at.bone_name = "hand_r"
			sk.add_child(at)
			w.get_parent().remove_child(w)
			at.add_child(w)
			# En reposo el arma queda en la línea del brazo (hacia abajo) con el filo al frente
			var hb := sk.get_bone_global_rest(sk.find_bone("hand_r")).basis.orthonormalized()
			w.transform = Transform3D(hb.inverse(), Vector3(0, 0.07, 0))
			if proc["J"].has("muzzle"):
				J["muzzle"] = proc["J"]["muzzle"]
			for mi in w.find_children("*", "MeshInstance3D", true, false):
				_model["meshes"].append(mi)
			for em in proc["eyes"]:
				if w.is_ancestor_of(_find_owner_mesh(w, em)):
					_model["eyes"].append(em)
		(proc["root"] as Node).queue_free()
	_overlay = StandardMaterial3D.new()
	_overlay.albedo_color = Color(1, 1, 1, 0.45)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.emission_enabled = true
	_overlay.emission = Color(1, 0.9, 0.8)
	_overlay.emission_energy_multiplier = 1.5
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_set_eyes(false)
	_play("idle", 0.0, 1.0)


## Pega una escena .glb (arma) al hueso de la mano: en reposo queda a lo largo del
## brazo (hacia abajo) con el filo al frente.
func _attach_glb(path: String, bone: String, holo := false) -> Node3D:
	var at := BoneAttachment3D.new()
	at.bone_name = bone
	_skel.add_child(at)
	var w: Node3D = (load(path) as PackedScene).instantiate()
	at.add_child(w)
	var hb := _skel.get_bone_global_rest(_skel.find_bone(bone)).basis.orthonormalized()
	w.transform = Transform3D(hb.inverse(), Vector3(0, 0.06, 0))
	var mz := w.find_child("muzzle", true, false)
	if mz:
		J["muzzle"] = mz
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if holo:
			m3.material_override = holo_material()
			m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			_model["meshes"].append(m3)
			m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return w


func _find_owner_mesh(root: Node, mat: Material) -> Node:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override == mat:
			return mi
	return self


func _play(anim: String, blend: float, speed: float) -> void:
	if _anim == null or not _anim.has_animation(anim):
		return
	if anim != _anim_cur:
		_anim.play(anim, blend, speed)
		_anim_cur = anim
	else:
		_anim.speed_scale = speed
		_anim.set_speed_scale(speed)


var _spark_t := 2.0
var _blink_t := 0.0


## Robot dañado: chispas del hombro arrancado y visor que parpadea.
func _glb_damage_fx(delta: float) -> void:
	var android: bool = _cfg.get("android", false)
	if not type.begins_with("robot") and not android:
		return
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = _rng.randf_range(1.2, 4.0) * (1.6 if android else 1.0)
		if _skel and fx_parent:
			var p := _hand_pos("neck" if android else "upper_arm_l")
			FX.burst(fx_parent, p + Vector3(0, 0.1, 0), true, 10, 0.35)
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_t = _rng.randf_range(0.5, 3.0)
		for m in _model["eyes"]:
			(m as StandardMaterial3D).emission_energy_multiplier = 0.2


## Animaciones del modelo de Blender según el estado.
func _update_glb_anim() -> void:
	_glb_damage_fx(get_physics_process_delta_time())
	match state:
		State.STAGGER:
			_play("stumble" if _stumble and _anim.has_animation("stumble") else "hit", 0.06, 1.0)
		State.ATTACK:
			var pose_name: String = _atk.get("pose", "jab")
			var a: String = pose_name if _anim.has_animation(pose_name) else GLB_ATTACK_ANIM.get(pose_name, "jab")
			if pose_name == "jab" and float(_atk.get("lunge", 0.0)) >= 8.0:
				a = "lunge"
			# Se escala la animación para que su impacto coincida con el golpe del ataque
			var imp: float = GLB_IMPACT_BY_TYPE.get(type, {}).get(a, GLB_IMPACT.get(a, 0.5))
			var spd := 1.0 if a in ["aim", "roar"] else imp / maxf(float(_atk.get("wind", 0.5)), 0.1)
			if _atk.get("kind", "") == "charge" and _atk_t >= float(_atk["wind"]):
				a = "run"
				spd = 1.5
			if _anim_cur != a:
				_play(a, 0.08, spd)
		_:
			var v := Vector2(velocity.x, velocity.z).length() / maxf(_model["root"].scale.x, 0.1)
			var refs: Array = GLB_LOCO.get(type, GLB_LOCO.get(type.get_slice("_", 0), [1.4, 4.2]))
			if v < 0.25:
				_play("idle", 0.25, 1.0)
			elif v < (refs[0] + refs[1]) * 0.5:
				if _anim_cur != "walk":
					_play("walk", 0.2, v / refs[0])
				_anim.speed_scale = clampf(v / refs[0], 0.4, 2.0)
			else:
				if _anim_cur != "run":
					_play("run", 0.2, v / refs[1])
				_anim.speed_scale = clampf(v / refs[1], 0.6, 1.8)


func _build_bar() -> void:
	if _bar_shader == null:
		_bar_shader = Shader.new()
		_bar_shader.code = BAR_SHADER
	var m := ShaderMaterial.new()
	m.shader = _bar_shader
	var q := QuadMesh.new()
	var w := clampf(float(_cfg["height"]) * 0.55, 0.8, 2.4)
	q.size = Vector2(w, w * 0.09)
	_bar = MeshInstance3D.new()
	_bar.mesh = q
	_bar.material_override = m
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.position = Vector3(0, float(_cfg["height"]) + 0.45, 0)
	_bar.visible = false
	add_child(_bar)


func _set_eyes(aggro: bool) -> void:
	for m in _model["eyes"]:
		var sm := m as StandardMaterial3D
		var c := _aggro_color if aggro else _idle_color
		sm.albedo_color = c
		sm.emission = c


# ======================================================================
#  Daño
# ======================================================================

func take_damage(amount: float, from_pos: Variant = null) -> void:
	if is_dead:
		return
	hp -= amount
	_flash_t = 0.12
	_bar_t = 5.0
	var center := global_position + Vector3(0, float(_cfg["height"]) * 0.6, 0)
	if fx_parent:
		if _cfg.get("mutant", false):
			LFX.puff(fx_parent, center, Color(0.5, 1.2, 0.2, 0.9), 14, 0.18, 3.0, -7.0)
		else:
			FX.burst(fx_parent, center, true, 18, 0.6)
	if hp <= 0.0:
		_die()
		return
	if state in [State.IDLE, State.WANDER, State.RETURN]:
		_aggro()
	var poise: float = _cfg["poise"]
	_poise_acc += amount
	if poise <= 0.0 or _poise_acc >= poise:
		_poise_acc = 0.0
		_start_stagger(0.55, false)
		if from_pos is Vector3:
			var away: Vector3 = global_position - from_pos
			away.y = 0.0
			velocity = away.normalized() * 4.0 if away.length() > 0.01 else Vector3.ZERO


func _die() -> void:
	is_dead = true
	state = State.DEAD
	remove_from_group("enemy")
	_bar.visible = false
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
	for m in _model["eyes"]:
		(m as StandardMaterial3D).emission_energy_multiplier = 0.0
		(m as StandardMaterial3D).albedo_color = Color(0.1, 0.1, 0.1)
	var root: Node3D = _model["root"]
	var tw := create_tween()
	if _model["kind"] == "glb":
		_anim.speed_scale = 1.0
		_anim.play("death", 0.1)
		_anim_cur = "death"
		tw.tween_interval(1.3)
	elif _model["kind"] == "quad":
		tw.tween_property(root, "rotation_degrees:z", 170.0, 0.5).set_trans(Tween.TRANS_BACK)
		tw.parallel().tween_property(root, "position:y", 0.5, 0.5)
	elif type == "mecha":
		tw.tween_property(root, "rotation_degrees:x", -12.0, 0.6)
		tw.tween_property(root, "position:y", -1.6, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(root, "rotation_degrees:z", 14.0, 0.8)
	else:
		tw.tween_property(root, "rotation_degrees:x", 84.0, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(root, "position:y", float(_cfg["radius"]) * 0.6, 0.7)
	if fx_parent:
		var c := global_position + Vector3(0, float(_cfg["height"]) * 0.5, 0)
		if _cfg.get("mutant", false):
			LFX.puff(fx_parent, c, Color(0.45, 1.1, 0.2, 0.9), 40, 0.35, 4.0, -6.0)
		else:
			FX.burst(fx_parent, c, true, 50, 1.2 if type == "mecha" else 0.8)
			if _cfg.get("android", false):
				_code_burst(c + Vector3(0, 0.6, 0), SPELL_CODE["death"], Color(1.0, 0.35, 0.35))
			if type == "mecha":
				LFX.fire(fx_parent, global_position + Vector3(0, 1.2, 0), 1.3, true)
				LFX.smoke(fx_parent, global_position + Vector3(0, 3.0, 0), 1.2)
			else:
				LFX.puff(fx_parent, c, Color(0.25, 0.25, 0.25, 0.8), 14, 0.5, 1.5, 1.0)
	died.emit(self)
	tw.tween_interval(6.0)
	tw.tween_property(root, "scale", Vector3.ONE * 0.01, 1.0)
	tw.tween_callback(queue_free)


# ======================================================================
#  IA
# ======================================================================

func _physics_process(delta: float) -> void:
	_update_visuals(delta)
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= 25.0 * delta
	else:
		velocity.y = -0.5
	var tgt_ok: bool = target != null and is_instance_valid(target) and not ("is_dead" in target and target.is_dead)
	var dist := INF
	if tgt_ok:
		dist = global_position.distance_to(target.global_position)
	_cd -= delta
	_t += delta
	var move := Vector3.ZERO
	var speed := 0.0
	match state:
		State.IDLE, State.WANDER:
			if tgt_ok and dist < float(_cfg["sight"]) and _can_see(delta):
				_aggro()
			else:
				_wander_wait -= delta
				if state == State.IDLE and _wander_wait <= 0.0:
					var a := _rng.randf() * TAU
					var r := sqrt(_rng.randf()) * wander_radius
					_wander_to = home + Vector3(cos(a) * r, 0, sin(a) * r)
					state = State.WANDER
				if state == State.WANDER:
					var to := _wander_to - global_position
					to.y = 0.0
					if to.length() < 0.8 or _t > 12.0:
						state = State.IDLE
						_t = 0.0
						_wander_wait = _rng.randf_range(2.0, 5.0) if type != "mecha" else _rng.randf_range(0.5, 2.0)
					else:
						move = to.normalized()
						speed = float(_cfg["walk"])
		State.CHASE:
			if not tgt_ok or global_position.distance_to(home) > wander_radius + 30.0 or dist > float(_cfg["sight"]) * 2.4:
				_lose_target()
			elif _distract_t > 0.0:
				# Bestia idiota: se queda olfateando / temblando unos instantes
				_distract_t -= delta
				rotation.y += sin(_t * 7.0) * delta * 1.5
			else:
				var to := target.global_position - global_position
				to.y = 0.0
				var dir := to.normalized()
				if _cfg.get("mutant", false):
					_feral_t -= delta
					if _feral_t <= 0.0:
						_feral_t = _rng.randf_range(5.0, 10.0)
						var r := _rng.randf()
						if r < 0.3 and dist > 3.0:
							_start_attack(ROAR)
							return
						elif r < 0.5:
							_distract_t = _rng.randf_range(0.7, 1.4)
				var a := _choose_attack(dist) if _cd <= 0.0 else {}
				if not a.is_empty():
					_start_attack(a)
				else:
					var keep: float = _cfg.get("keep_away", 0.0)
					if keep > 0.0 and dist < keep * 0.55:
						move = -dir
						speed = float(_cfg["walk"]) * 1.2
					elif keep > 0.0 and dist < keep:
						move = dir.cross(Vector3.UP) * (1.0 if int(_t) % 6 < 3 else -1.0)
						speed = float(_cfg["walk"])
					elif dist > float(_cfg["radius"]) + 1.2:
						move = dir
						speed = float(_cfg["run"]) if dist > 3.5 else float(_cfg["walk"]) * 1.3
					_turn_to(dir, delta, 1.0)
		State.ATTACK:
			_process_attack(delta)
		State.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
			if _t > _stagger_dur:
				state = State.CHASE
				_pose = {}
				_pose_rate = 8.0
				_cd = _rng.randf_range(0.2, 0.6)
		State.RETURN:
			var to := home - global_position
			to.y = 0.0
			hp = minf(max_hp, hp + max_hp * 0.25 * delta)
			if to.length() < 1.5:
				state = State.IDLE
				_t = 0.0
				_wander_wait = 1.0
				_set_eyes(false)
			else:
				move = to.normalized()
				speed = float(_cfg["run"])
				if tgt_ok and dist < float(_cfg["sight"]) * 0.6 and _can_see(delta) and global_position.distance_to(home) < wander_radius + 20.0:
					_aggro()
	if state != State.ATTACK and state != State.STAGGER:
		if move != Vector3.ZERO:
			move = _avoid(move, delta)
			if state != State.CHASE:
				_turn_to(move, delta, 0.7)
		velocity.x = move.x * speed
		velocity.z = move.z * speed
	_walk_amt = move_toward(_walk_amt, clampf(Vector2(velocity.x, velocity.z).length() / maxf(float(_cfg["run"]), 0.1), 0.0, 1.0), delta * 4.0)
	move_and_slide()


func _aggro() -> void:
	if state == State.DEAD:
		return
	var was_calm := state in [State.IDLE, State.WANDER]
	state = State.CHASE
	_t = 0.0
	_cd = maxf(_cd, _rng.randf_range(0.3, 0.9))
	_set_eyes(true)
	# Las bestias suelen rugir al descubrir al jugador
	if was_calm and _cfg.get("mutant", false) and _model.get("kind", "") == "glb" and _rng.randf() < 0.5:
		_start_attack(ROAR)


func _start_stagger(dur: float, stumble: bool) -> void:
	state = State.STAGGER
	_t = 0.0
	_stagger_dur = dur
	_stumble = stumble
	_pose = POSES["stagger"][0]
	_pose_rate = 16.0


## Rugido: despierta a los mutantes cercanos (no hace daño).
func _roar() -> void:
	if fx_parent:
		var h := _hand_pos("head")
		LFX.puff(fx_parent, h + (-global_basis.z) * 0.4, Color(0.5, 0.9, 0.3, 0.5), 18, 0.35, 2.5, -1.0)
	if target and target.has_method("add_camera_shake") and global_position.distance_to(target.global_position) < 14.0:
		target.add_camera_shake(0.12 if type != "mutante_grande" else 0.25)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e != self and e is CharacterBody3D and e.get("_cfg") and (e._cfg as Dictionary).get("mutant", false):
			if e.state in [State.IDLE, State.WANDER, State.RETURN] and (e as Node3D).global_position.distance_to(global_position) < 18.0:
				e.target = target
				e.state = State.CHASE
				e._set_eyes(true)


## La mole se estrella contra una pared al embestir: queda aturdida y se lastima.
func _crash() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if fx_parent:
		var p := global_position + (-global_basis.z) * float(_cfg["radius"]) + Vector3(0, 1.2, 0)
		LFX.puff(fx_parent, p, Color(0.5, 0.47, 0.42, 0.8), 30, 0.5, 4.0, 2.0)
		FX.shockwave(fx_parent, global_position + Vector3(0, 0.1, 0), 3.0, Color(0.6, 0.55, 0.45), 0.4)
	if target and target.has_method("add_camera_shake") and global_position.distance_to(target.global_position) < 20.0:
		target.add_camera_shake(0.3)
	hp = maxf(1.0, hp - max_hp * 0.06)
	_bar_t = 5.0
	_start_stagger(2.2, true)


func _lose_target() -> void:
	state = State.RETURN
	_t = 0.0
	_pose = {}
	_set_eyes(false)


func _can_see(delta: float) -> bool:
	_sight_t -= delta
	if _sight_t > 0.0:
		return _seen
	_sight_t = 0.3
	var eye := global_position + Vector3(0, float(_cfg["height"]) * 0.85, 0)
	var q := PhysicsRayQueryParameters3D.create(eye, target.global_position + Vector3(0, 1.2, 0))
	var excl: Array[RID] = [get_rid()]
	if target is CollisionObject3D:
		excl.append((target as CollisionObject3D).get_rid())
	q.exclude = excl
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_seen = hit.is_empty() or not (hit["collider"] is StaticBody3D)
	return _seen


## Si choca con una pared, rodea el obstáculo girando un rato hacia un lado.
func _avoid(dir: Vector3, delta: float) -> Vector3:
	_steer_t -= delta
	var horiz := Vector2(velocity.x, velocity.z).length()
	if is_on_wall() and horiz < 0.6:
		_stuck_t += delta
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta)
	if _stuck_t > 0.25 and _steer_t <= 0.0:
		_steer = deg_to_rad(75.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_steer_t = _rng.randf_range(0.7, 1.4)
		_stuck_t = 0.0
	if _steer_t > 0.0:
		return dir.rotated(Vector3.UP, _steer)
	return dir


func _turn_to(dir: Vector3, delta: float, factor: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-float(_cfg["turn"]) * factor * delta))


# ======================================================================
#  Ataques
# ======================================================================

func _choose_attack(dist: float) -> Dictionary:
	var opts: Array = []
	var total := 0
	var behind := false
	if target and is_instance_valid(target):
		var to := (target.global_position - global_position) * Vector3(1, 0, 1)
		behind = to.length() < 2.6 and (-global_basis.z).dot(to.normalized()) < -0.2
	for k in _atk_cd.keys():
		_atk_cd[k] = float(_atk_cd[k]) - (Time.get_ticks_msec() - _cd_stamp) / 1000.0
	_cd_stamp = Time.get_ticks_msec()
	for a in _cfg["attacks"]:
		if float(_atk_cd.get(a["id"], 0.0)) > 0.0:
			continue
		if a.get("behind", false) and not behind:
			continue
		if dist >= float(a["min"]) and dist <= float(a["max"]):
			opts.append(a)
			total += int(a["w"]) * (3 if behind and a.get("kind", "") == "aoe" else 1)
	if opts.is_empty():
		return {}
	var r := _rng.randi_range(1, total)
	for a in opts:
		r -= int(a["w"]) * (3 if behind and a.get("kind", "") == "aoe" else 1)
		if r <= 0:
			return a
	return opts[0]


func _start_attack(a: Dictionary) -> void:
	state = State.ATTACK
	_atk = a
	_atk_t = 0.0
	_hit_idx = 0
	_shot_idx = 0
	_landed = false
	_pose = _pose_of(a, 0)
	_pose_rate = 1.0 / maxf(float(a["wind"]) * 0.45, 0.05)
	if a.has("cd"):
		_atk_cd[a["id"]] = float(a["cd"])
	match a.get("kind", "melee"):
		"compile":
			_compile_weapon(a)
		"spell", "lash":
			if _cfg.get("android", false):
				var lines: Array = SPELL_CODE.get(a.get("spell", "lash"), ["cables.azotar(objetivo)"])
				_code_burst(_hand_pos("hand_l") + Vector3(0, 0.4, 0), lines, Color(0.45, 1.0, 0.6) if a.get("spell", "") != "rayos" else Color(0.5, 0.8, 1.0))
	velocity.x = 0.0
	velocity.z = 0.0


func _process_attack(delta: float) -> void:
	_atk_t += delta
	var a := _atk
	var wind: float = a["wind"]
	var kind: String = a.get("kind", "melee")
	var tgt_ok: bool = target != null and is_instance_valid(target) and not ("is_dead" in target and target.is_dead)
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	if _atk_t < wind:
		# Preparación: sigue al jugador con la mirada (telegrafiado)
		if tgt_ok:
			var to := target.global_position - global_position
			to.y = 0.0
			_turn_to(to.normalized(), delta, 0.9 if kind != "shoot" else 1.4)
		var k := _atk_t / wind
		if k > 0.7 and int(_atk_t * 20.0) % 2 == 0:
			_flash_eyes()
		if k < 0.8 and tgt_ok:
			_lash_dir = (target.global_position - global_position) * Vector3(1, 0, 1)
	else:
		match kind:
			"melee", "compile":
				var hits: int = a.get("hits", 1)
				var gap: float = a.get("gap", 0.4)
				var hit_t := wind + _hit_idx * gap
				if _hit_idx < hits and _atk_t >= hit_t:
					_pose = _pose_of(a, 1 if _hit_idx % 2 == 0 else 0)
					_pose_rate = 22.0
					var lunge: float = a.get("lunge", 0.0)
					velocity.x = fwd.x * lunge
					velocity.z = fwd.z * lunge
					_hit_idx += 1
					_melee_check(a, fwd)
				elif _atk_t < hit_t - gap + 0.15:
					var lunge2: float = a.get("lunge", 0.0)
					velocity.x = fwd.x * lunge2
					velocity.z = fwd.z * lunge2
			"lash":
				var shots: int = a.get("shots", 1)
				if _hit_idx < shots and _atk_t >= wind + _hit_idx * 0.45:
					_hit_idx += 1
					_lash(a)
			"spell":
				if _hit_idx == 0:
					_hit_idx = 1
					_cast_spell(a)
			"roar":
				if _hit_idx == 0:
					_hit_idx = 1
					_roar()
			"charge":
				# Embestida a lo bruto: casi no corrige el rumbo y si choca con una pared se aturde
				if tgt_ok:
					var to := target.global_position - global_position
					to.y = 0.0
					_turn_to(to.normalized(), delta, 0.12)
				var spd: float = a.get("speed", 8.0)
				velocity.x = fwd.x * spd
				velocity.z = fwd.z * spd
				if _hit_idx == 0 and tgt_ok:
					var d := global_position.distance_to(target.global_position)
					if d < float(a["reach"]) + float(_cfg["radius"]):
						_hit_idx = 1
						_damage_target(a)
						if target.has_method("add_camera_shake"):
							target.add_camera_shake(0.35)
				if _atk_t > wind + 0.25 and is_on_wall():
					_crash()
					return
			"aoe":
				if _hit_idx == 0:
					_hit_idx = 1
					_pose = _pose_of(a, 1)
					_pose_rate = 22.0
					_aoe(a)
			"shoot", "spit":
				var shots: int = a.get("shots", 1)
				var gap: float = a.get("gap", 0.2)
				if _shot_idx == 0:
					_pose = _pose_of(a, 1)
					_pose_rate = 16.0
				if _shot_idx < shots and _atk_t >= wind + _shot_idx * gap:
					_shot_idx += 1
					if tgt_ok:
						if kind == "shoot":
							_shoot(a)
						else:
							_spit(a)
				if tgt_ok and kind == "shoot":
					var to := target.global_position - global_position
					to.y = 0.0
					_turn_to(to.normalized(), delta, 0.6)
	if _atk_t >= float(a["dur"]):
		state = State.CHASE
		_pose = {}
		_pose_rate = 6.0
		if kind == "charge":
			velocity.x = 0.0
			velocity.z = 0.0
		# Las bestias torpes: si fallan el salto o el frenesí, se tropiezan
		if not _landed and _rng.randf() < float(a.get("tumble", 0.0)):
			_start_stagger(1.25, true)
			return
		_cd = _rng.randf_range(0.6, 1.6) * (1.6 if type in ["mecha", "mutante_grande"] else 1.0)
		if kind == "shoot":
			_cd += _rng.randf_range(0.8, 1.6)


func _melee_check(a: Dictionary, fwd: Vector3) -> void:
	if target == null or not is_instance_valid(target):
		return
	var to := target.global_position - global_position
	if absf(to.y) > 2.5:
		return
	to.y = 0.0
	var reach: float = a["reach"]
	if to.length() < reach + 0.4 and (to.length() < 0.8 or fwd.dot(to.normalized()) > float(a["arc"])):
		_damage_target(a)


func _aoe(a: Dictionary) -> void:
	var r: float = a["radius"]
	var col := Color(0.45, 1.0, 0.2) if _cfg.get("mutant", false) else Color(1.0, 0.55, 0.2)
	var center := global_position + (-global_basis.z) * (float(_cfg["radius"]) * 0.8)
	if _cfg.get("android", false):
		# Pulso eléctrico centrado en el androide (castiga quedarse detrás)
		col = Color(0.4, 0.8, 1.0)
		center = global_position
		if fx_parent:
			for i in 6:
				var ang := TAU * i / 6.0 + _rng.randf() * 0.5
				_arc(global_position + Vector3(0, 1.3, 0), global_position + Vector3(cos(ang) * r, 0.2, sin(ang) * r), 0.1)
	center.y = global_position.y
	if fx_parent:
		FX.shockwave(fx_parent, center + Vector3(0, 0.1, 0), r, col, 0.5)
		LFX.puff(fx_parent, center + Vector3(0, 0.3, 0), Color(0.45, 0.42, 0.38, 0.8), 30, 0.6, 5.0, 2.0)
	if target and target.has_method("add_camera_shake") and global_position.distance_to(target.global_position) < r * 3.0:
		target.add_camera_shake(0.35 if type == "mecha" else 0.25)
	if target == null or not is_instance_valid(target):
		return
	var to := target.global_position - center
	if absf(to.y) < 2.0 and Vector2(to.x, to.z).length() < r:
		_damage_target(a)


func _damage_target(a: Dictionary) -> void:
	if not target.has_method("take_damage"):
		return
	var before: float = float(target.get("hp")) if "hp" in target else 0.0
	target.take_damage(float(a["dmg"]), global_position)
	var landed: bool = "hp" in target and float(target.get("hp")) < before
	_landed = _landed or landed
	var bu: float = a.get("buildup", 0.0)
	if bu > 0.0 and target.has_method("add_buildup") and landed:
		target.add_buildup("veneno", bu)
	if landed and _rng.randf() < float(a.get("electric", 0.0)) and target.has_method("apply_status"):
		target.apply_status("electrocutado", 1.6)


func _muzzle_pos() -> Vector3:
	var m: Node3D = J.get("muzzle")
	if m:
		return m.global_position
	var h: Node3D = J.get("head")
	if h:
		return h.global_position + (-global_basis.z) * 0.4
	return global_position + Vector3(0, float(_cfg["height"]) * 0.8, 0)


func _shoot(a: Dictionary) -> void:
	var from := _muzzle_pos()
	var aim := target.global_position + Vector3(0, 1.0, 0)
	aim += Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.2, 0.3), _rng.randf_range(-0.4, 0.4))
	var b := BOLT.new()
	b.kind = "laser"
	b.target = target
	b.shooter = self
	b.damage = a["dmg"]
	b.size = a.get("size", 1.0)
	b.color = Color(1.0, 0.45, 0.12) if type == "mecha" else Color(1.0, 0.18, 0.12)
	b.velocity = (aim - from).normalized() * float(a.get("speed", 24.0))
	b.life = 2.5
	(fx_parent if fx_parent else get_parent()).add_child(b)
	b.global_position = from
	if fx_parent:
		LFX.puff(fx_parent, from, Color(2.5, 0.8, 0.4, 1), 6, 0.12, 2.0, 0.0)


func _spit(a: Dictionary) -> void:
	var from := _muzzle_pos()
	var aim := target.global_position + Vector3(_rng.randf_range(-0.8, 0.8), 0.9, _rng.randf_range(-0.8, 0.8))
	var g := 12.0
	var flat := Vector2(aim.x - from.x, aim.z - from.z).length()
	var t := clampf(flat / 13.0, 0.45, 1.3)
	var v := (aim - from) / t
	v.y += 0.5 * g * t
	var b := BOLT.new()
	b.kind = "spit"
	b.target = target
	b.shooter = self
	b.damage = a["dmg"]
	b.buildup = a.get("buildup", 0.0)
	b.size = a.get("size", 1.0)
	b.velocity = v
	b.gravity = g
	b.life = 3.0
	(fx_parent if fx_parent else get_parent()).add_child(b)
	b.global_position = from


# ======================================================================
#  Androides: scripts, cables y hechizos (versiones pequeñas de ADA-7)
# ======================================================================

static var _holo_mat: StandardMaterial3D


static func holo_material() -> StandardMaterial3D:
	if _holo_mat == null:
		_holo_mat = StandardMaterial3D.new()
		_holo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_holo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_holo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_holo_mat.albedo_color = Color(0.35, 1.0, 0.55, 0.6)
	return _holo_mat


func _pose_of(a: Dictionary, i: int) -> Dictionary:
	return (POSES.get(a["pose"], POSES["jab"]) as Array)[i]


## Posición de un hueso del modelo de Blender (o el centro del cuerpo si no hay).
func _hand_pos(bone: String) -> Vector3:
	if _skel:
		var bi := _skel.find_bone(bone)
		if bi >= 0:
			return _skel.global_transform * _skel.get_bone_global_pose(bi).origin
	return global_position + Vector3(0, float(_cfg["height"]) * 0.6, 0)


## "Compilar": una espada grande de luz se arma en su mano mientras levanta el brazo.
func _compile_weapon(a: Dictionary) -> void:
	_code_burst(_hand_pos("hand_r") + Vector3(0, 0.5, 0), SPELL_CODE["compile"], Color(0.45, 1.0, 0.6))
	if _skel == null or not ResourceLoader.exists(GLB_WEAPONS["espada"]):
		return
	var w := _attach_glb(GLB_WEAPONS["espada"], "hand_r", true)
	if _weapon_r:
		_weapon_r.visible = false
	w.scale = Vector3.ONE * 0.05
	var at := w.get_parent()
	var tw := w.create_tween()
	tw.tween_property(w, "scale", Vector3.ONE * 1.5, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(0.1, float(a["dur"]) - 1.1))
	tw.tween_property(w, "scale", Vector3.ONE * 0.01, 0.3)
	tw.tween_callback(func():
		if _weapon_r:
			_weapon_r.visible = true
		at.queue_free())
	if fx_parent:
		LFX.puff(fx_parent, _hand_pos("hand_r"), Color(0.6, 2.0, 1.0, 1), 20, 0.12, 2.5, 0.0)


## Latigazo con los cables de servidor: un arco eléctrico en línea recta hasta su
## alcance, en la dirección que tenía el jugador al final de la preparación.
func _lash(a: Dictionary) -> void:
	var reach: float = a["reach"]
	var tgt_ok: bool = target != null and is_instance_valid(target)
	if _hit_idx > 1 and tgt_ok:
		_lash_dir = (target.global_position - global_position) * Vector3(1, 0, 1)
	var dir := _lash_dir.normalized() if _lash_dir.length() > 0.1 else -global_basis.z
	var base := global_position + Vector3(0, 1.0, 0)
	var end := base + dir * reach
	var from := _hand_pos("hand_l")
	for i in 2:
		_arc(from, end + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.2), _rng.randf_range(-0.3, 0.3)), 0.09 - i * 0.04)
	if fx_parent:
		LFX.puff(fx_parent, end, Color(0.8, 1.6, 2.6, 1), 14, 0.12, 4.0, 0.0)
	if tgt_ok:
		var p := target.global_position + Vector3(0, 0.9, 0)
		var q := Geometry3D.get_closest_point_to_segment(p, base, end)
		if q.distance_to(p) < 1.0:
			_damage_target(a)


## Arco eléctrico corto (látigos y pulsos). Se dibuja en coordenadas globales.
func _arc(a: Vector3, b: Vector3, width: float) -> void:
	if fx_parent == null:
		return
	var pts := FX.jagged_points(a, b, 14, a.distance_to(b) * 0.05, _rng)
	var core := MeshInstance3D.new()
	core.top_level = true
	core.mesh = FX.ribbon_mesh([pts], [width * 0.5])
	core.material_override = FX.bolt_material(true)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := MeshInstance3D.new()
	glow.mesh = FX.ribbon_mesh([pts], [width * 1.4])
	glow.material_override = FX.bolt_material(false)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.add_child(glow)
	fx_parent.add_child(core)
	core.global_transform = Transform3D.IDENTITY
	var tw := core.create_tween()
	tw.tween_interval(0.07)
	tw.tween_property(core, "transparency", 1.0, 0.2)
	tw.parallel().tween_property(glow, "transparency", 1.0, 0.2)
	tw.tween_callback(core.queue_free)


## Hechizos del androide de scripts. Todo lo que pasa después vive en fx_parent
## (funciones estáticas), así sigue funcionando aunque el androide muera o desaparezca.
func _cast_spell(a: Dictionary) -> void:
	if fx_parent == null or target == null or not is_instance_valid(target):
		return
	var tp := target.global_position
	var lead := Vector3.ZERO
	if "velocity" in target:
		lead = (target.velocity as Vector3) * Vector3(0.5, 0, 0.5)
	var dmg: float = a["dmg"]
	var el: float = a.get("electric", 0.0)
	match a.get("spell", "rayos"):
		"rayos":
			var spots: Array = [tp + lead * 0.6]
			for i in 2:
				spots.append(tp + Vector3(_rng.randf_range(-3.5, 3.5), 0, _rng.randf_range(-3.5, 3.5)))
			for i in spots.size():
				_strike(fx_parent, spots[i], 1.8, 0.95 + i * 0.12, dmg, el, target, "rayo")
		"sello":
			_strike(fx_parent, tp + lead, 2.8, 1.1, dmg, 0.0, target, "sello")
		"lluvia":
			_strike(fx_parent, tp + lead * 0.5, 1.9, 1.0, dmg, 0.0, target, "arma")
			_strike(fx_parent, tp + lead * 1.2 + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5)), 1.9, 1.45, dmg, 0.0, target, "arma")


static func _strike(parent: Node, pos: Vector3, radius: float, delay: float, dmg: float, electric: float, tgt: Node3D, kind: String) -> void:
	var col := {"rayo": Color(0.5, 0.8, 1.0), "sello": Color(0.75, 0.35, 1.0), "arma": Color(0.45, 1.0, 0.6)}[kind] as Color
	var ring := FX.ground_ring(parent, pos, radius, col, 2.2)
	var m: ShaderMaterial = ring.material_override
	var tw := ring.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("progress", v), 0.0, 1.0, delay)
	if kind == "arma":
		var path: String = GLB_WEAPONS["hacha"] if randf() < 0.5 else GLB_WEAPONS["espada"]
		if ResourceLoader.exists(path):
			var w: Node3D = (load(path) as PackedScene).instantiate()
			parent.add_child(w)
			for mi in w.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = holo_material()
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Cae con la punta hacia abajo (el arma se modela a lo largo de −Y)
			w.global_position = pos + Vector3(0, 10.0, 0)
			w.rotation = Vector3(0, randf() * TAU, 0)
			w.scale = Vector3.ONE * 1.4
			var wt := w.create_tween()
			wt.tween_interval(maxf(0.0, delay - 0.25))
			wt.tween_property(w, "global_position", pos + Vector3(0, 2.0, 0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			wt.tween_interval(0.8)
			wt.tween_property(w, "scale", Vector3.ONE * 0.01, 0.35)
			wt.tween_callback(w.queue_free)
	tw.tween_callback(func(): _strike_hit(parent, pos, radius, dmg, electric, tgt, kind, col))
	tw.tween_property(ring, "transparency", 1.0, 0.25)
	tw.tween_callback(ring.queue_free)


static func _strike_hit(parent: Node, pos: Vector3, radius: float, dmg: float, electric: float, tgt: Node3D, kind: String, col: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	match kind:
		"rayo":
			FX.spawn_bolt(parent, pos + Vector3(rng.randf_range(-1, 1), 11.0, rng.randf_range(-1, 1)), pos, rng, 0.22)
			FX.scorch(parent, pos, radius * 0.8, true)
		"sello":
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = radius * 0.5
			cm.bottom_radius = radius
			cm.height = 7.0
			cm.material = LFX.emissive(col, 1.6, 0.32)
			mi.mesh = cm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
			mi.global_position = pos + Vector3(0, 3.5, 0)
			mi.scale = Vector3(0.2, 1, 0.2)
			var tw := mi.create_tween()
			tw.tween_property(mi, "scale", Vector3.ONE, 0.12)
			tw.tween_property(mi, "scale", Vector3(0.01, 1.2, 0.01), 0.4)
			tw.tween_callback(mi.queue_free)
			LFX.puff(parent, pos + Vector3(0, 0.5, 0), Color(1.8, 0.8, 3.0, 1), 24, 0.22, 5.0, 0.0)
		_:
			FX.burst(parent, pos, false, 20, 0.8)
			LFX.puff(parent, pos + Vector3(0, 0.4, 0), Color(0.6, 2.0, 1.0, 1), 16, 0.18, 4.0, 0.0)
	if tgt == null or not is_instance_valid(tgt) or ("is_dead" in tgt and tgt.is_dead):
		return
	var to := tgt.global_position - pos
	if absf(to.y) < 2.2 and Vector2(to.x, to.z).length() < radius and tgt.has_method("take_damage"):
		var before: float = float(tgt.get("hp")) if "hp" in tgt else 0.0
		tgt.take_damage(dmg, pos)
		if electric > 0.0 and randf() < electric and "hp" in tgt and float(tgt.get("hp")) < before and tgt.has_method("apply_status"):
			tgt.apply_status("electrocutado", 1.6)


## Líneas de código flotando en espiral (los "scripts" de ADA-7, en pequeño).
func _code_burst(pos: Vector3, lines: Array, col: Color) -> void:
	if fx_parent == null:
		return
	for i in mini(lines.size(), 2):
		var l := Label3D.new()
		l.text = String(lines[i])
		l.font_size = 32
		l.pixel_size = 0.0035
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = col
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.outline_size = 8
		l.shaded = false
		fx_parent.add_child(l)
		var ang := TAU * i / maxf(1.0, lines.size()) + _rng.randf() * 0.5
		var start := pos + Vector3(cos(ang) * 0.7, i * 0.28, sin(ang) * 0.7)
		l.global_position = start
		l.modulate.a = 0.0
		var tw := l.create_tween()
		tw.tween_interval(i * 0.1)
		tw.tween_property(l, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(l, "global_position", start + Vector3(cos(ang + 1.2) * 0.4, 0.9, sin(ang + 1.2) * 0.4), 1.3)
		tw.tween_property(l, "modulate:a", 0.0, 0.4)
		tw.tween_callback(l.queue_free)


func _flash_eyes() -> void:
	for m in _model["eyes"]:
		(m as StandardMaterial3D).emission_energy_multiplier = 7.0


# ======================================================================
#  Animación
# ======================================================================

func _update_visuals(delta: float) -> void:
	# Destello al recibir daño
	if _flash_t > 0.0:
		_flash_t -= delta
		var on := _flash_t > 0.0
		for mi in _model["meshes"]:
			(mi as MeshInstance3D).material_overlay = _overlay if on else null
	if not is_dead:
		for m in _model["eyes"]:
			var sm := m as StandardMaterial3D
			sm.emission_energy_multiplier = move_toward(sm.emission_energy_multiplier, 3.0, delta * 12.0)
	# Barra de vida flotante
	_bar_t -= delta
	_trail = move_toward(_trail, hp / max_hp, delta * 0.5) if _trail > hp / max_hp else hp / max_hp
	_bar.visible = not is_dead and (_bar_t > 0.0 or state == State.CHASE or state == State.ATTACK) and hp < max_hp
	if _bar.visible:
		_bar.set_instance_shader_parameter("ratio", clampf(hp / max_hp, 0.0, 1.0))
		_bar.set_instance_shader_parameter("trail", clampf(_trail, 0.0, 1.0))
	if is_dead:
		return
	if _model["kind"] == "glb":
		_update_glb_anim()
		return
	# Poses + caminata procedural
	_walk_ph += delta * lerpf(4.0, 9.5, _walk_amt) * (0.55 if type == "mecha" else 1.0)
	var sw := sin(_walk_ph)
	var amp := _walk_amt * (32.0 if _model["kind"] != "mech" else 22.0)
	var k := 1.0 - exp(-_pose_rate * delta)
	for n in J.keys():
		var tgt: Vector3 = _pose.get(n, Vector3.ZERO)
		_cur[n] = (_cur[n] as Vector3).lerp(tgt, k)
		var r: Vector3 = _cur[n]
		match _model["kind"]:
			"quad":
				if n == "leg_fl" or n == "leg_br":
					r.y += sw * amp
				elif n == "leg_fr" or n == "leg_bl":
					r.y -= sw * amp
				elif n.begins_with("shin_"):
					r.z += absf(sw) * amp * 0.5 * (1.0 if n.ends_with("l") else -1.0)
				elif n == "torso":
					r.z += sw * amp * 0.1
			_:
				match n:
					"leg_l":
						r.x += sw * amp
					"leg_r":
						r.x -= sw * amp
					"shin_l":
						r.x -= maxf(0.0, -cos(_walk_ph)) * amp * 0.9
					"shin_r":
						r.x -= maxf(0.0, cos(_walk_ph)) * amp * 0.9
					"arm_l":
						r.x -= sw * amp * 0.6
					"arm_r":
						if not _pose.has("arm_r"):
							r.x += sw * amp * 0.6
					"torso":
						r.y += sw * amp * 0.12
		(J[n] as Node3D).rotation_degrees = r
	# Balanceo del cuerpo al caminar / respirar
	var hip: Node3D = J.get("hip")
	if hip:
		var base := hip.position
		base.y = (hip.get_meta("y0") if hip.has_meta("y0") else base.y)
		if not hip.has_meta("y0"):
			hip.set_meta("y0", base.y)
		var bob := absf(cos(_walk_ph)) * 0.06 * _walk_amt * float(_cfg["height"]) * 0.5
		bob += sin(Time.get_ticks_msec() * 0.003) * 0.01 * float(_cfg["height"])
		hip.position.y = base.y + bob


## Revive y vuelve a su punto de inicio (al descansar en una hoguera).
func reset_to_home() -> void:
	if is_dead:
		return
	hp = max_hp
	global_position = home
	velocity = Vector3.ZERO
	state = State.IDLE
	_pose = {}
	_set_eyes(false)
