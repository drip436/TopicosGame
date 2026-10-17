# Jefe 1: Catedrático de Hierro

## Cómo meterlo a tu proyecto (la forma más fácil)
1. Con Godot abierto, arrastra la carpeta `boss_profesor` desde tu explorador de archivos
   al panel **Sistema de archivos** de Godot, encima de `res://`. Godot copia los archivos solo.
   Tiene que quedar como `res://boss_profesor/...`, al mismo nivel que `scripts` y `shaders`.
2. Reemplaza `res://scripts/weather.gd` por el `weather.gd` que viene en el zip.
   Así la lluvia pasa de llovizna a tormenta en la fase 2.
3. Abre la escena de la arena (`main.tscn`) y arrastra `boss_profesor/boss_fight.tscn`
   encima del nodo raíz del panel **Escena**.
4. Guarda y pulsa F6.

## Cómo funciona la pelea
- El jefe espera de pie en la azotea del edificio central.
- Cuando el jugador entra a la plaza, la entrada se cierra con niebla. El jefe ruge, cae un
  relámpago, salta y aterriza en la arena. En ese momento aparecen su nombre y su barra de vida.
- **Fase 1 (llovizna):** golpe vertical, barrido giratorio, lanzamiento de cadena y salto aplastante.
- **Fase 2 (al 50 % de vida):** se arrodilla, llama a la tormenta y un rayo carga su maza.
  Sus golpes sueltan ondas eléctricas que puedes esquivar rodando, invoca rayos (los círculos
  azules marcan dónde caen) y además caen rayos al azar sobre ti.
- Si ganas, aparece "ENEMIGO DERROTADO", la tormenta se calma y la niebla se abre.
- Si mueres, aparece "HAS MUERTO" y con R reintentas.

## Usar tu propio personaje
En el Inspector de `BossFight`, desmarca `spawn_test_player`. Tu jugador necesita:
- Estar en el grupo **"player"**.
- Tener `func take_damage(cantidad: float, desde: Vector3)` (el jefe la llama al golpearte).
- Opcional: `func add_camera_shake(fuerza: float)` y `var is_dead: bool`.

Para dañar al jefe, usa `get_tree().get_first_node_in_group("boss").take_damage(cantidad)`.

## Señales para conectar música, sonidos o cinemáticas
`BossFight` emite `battle_started`, `phase_changed(fase)`, `boss_defeated` y `player_died`.
También puedes iniciar la pelea a mano con `start_fight()`.

## Ajustes en el Inspector de BossFight
Nombre del jefe, vida, distancia que activa la pelea, cantidad de lluvia por fase y punto de aterrizaje.
