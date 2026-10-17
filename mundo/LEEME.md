# Vida del campus: enemigos, hogueras, tazas de café y el lago

Todo se crea solo al jugar: `CampusWorld` instancia `VidaDelCampus.tscn`
(opción `spawn_world_life` en el inspector de CampusWorld). No hace falta tocar `main.tscn`.
Los enemigos empiezan a aparecer al vencer al primer jefe.

## Controles nuevos

| Tecla | Acción |
|---|---|
| **E** | Encender / descansar en una hoguera |
| **R** | Beber café (curar). Si mueres fuera de una pelea de jefe: volver a la última hoguera |

## Hogueras

- Antes de cada arena de jefe (Plaza, Biblioteca, Centro de Cómputo, Laboratorio, Aula Magna)
  y junto a cada fuente del campus (prefabs `Fuente`).
- Descansar: vida completa, cafés rellenos, sin estados alterados, y **los enemigos reaparecen**.
- La última hoguera donde descansaste es tu punto de reaparición.
- Para poner más: arrastra `Hoguera.tscn` a la escena y cambia `title`.

## Tazas de café

- 15 repartidas por el campus + 1 dentro de cada edificio de conexión.
- Cada una suma **+1 café** al inventario (el HUD muestra `Café actual / máximo`).
- Para poner más: arrastra `TazaDeCafe.tscn` a la escena.

## Enemigos (`enemy.gd`)

Hay 4–5 por zona (`ENEMY_ZONES` en `world_life.gd`) y también dentro de los edificios de
conexión. Solo existen los que están a menos de 75 m del jugador (rendimiento).

| Tipo | Dónde | Ataques |
|---|---|---|
| `robot` | Todo el campus | Puñetazo, embestida |
| `robot_hacha` | Todo el campus | Hachazo lento y fuerte, barrido |
| `robot_espada` | Todo el campus | Combo de dos tajos, estocada |
| `robot_laser` | Todo el campus | Ráfagas de láser a distancia, culatazo |
| `mecha` | Estadio, Derecho, Filosofía y Letras, Estac. Norte, Explanada | Barrido, pisotón de área, cañón |
| `mutante_peq` | Sector del Laboratorio | Mordida, salto (veneno) |
| `mutante_med` | Sector del Laboratorio | Zarpazos, escupitajo (veneno) |
| `mutante_grande` | Sector del Laboratorio | Aplastón de área, manotazo, escupitajos (veneno) |

- Los robots pequeños se aturden con cada golpe; los medianos cada 2; mechas y mutantes grandes nunca.
- Tab / clic medio fija al enemigo más cercano.
- Para poner uno a mano: arrastra `Enemigo.tscn` y elige `type` y `wander_radius`.

## Barra de afecto (estados que se acumulan)

Aparece bajo la vida del jugador cuando algo la llena:

- **VENENO** (mutantes): al llenarse, 15 s perdiendo 1 de vida cada 0.6 s.
- **AMEBA COME-CEREBROS** (agua del lago): se llena en ~2 s dentro del agua; luego
  10 s perdiendo 3 de vida cada 0.3 s (casi mortal), y no baja mientras sigas en el agua.
  Se entra al lago por los tramos de barandal arrancado del malecón.

La barra baja sola si dejas de recibir acumulación; descansar en una hoguera la vacía.

## Piezas de la llave del Aula Magna

Cada jefe (Catedrático, Bibliófilo, ADA-7 y Kessler) suelta una **pieza de amuleto** donde cae.
Al recoger las 4 se abre el portón del Aula Magna, donde espera el jefe final
(ver `boss_final/LEEME.md`). El HUD muestra cuántas llevas arriba a la derecha.
