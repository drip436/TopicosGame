# Segundo jefe: Doctor Euclides Barrabás, el Bibliófilo Demente

Profesor flaco y alto, con panza, barba canosa, brazos y dedos largos, camisa de
cuadros y pantalón de mezclilla. Está loco. Pelea en la **Biblioteca Central** del campus.

## Cómo se activa

No hay que tocar `main.tscn`. `CampusWorld` crea `LibraryFight.tscn` al iniciar el juego
(opción `spawn_library_boss` en el inspector de CampusWorld; desactívala si no quieres el jefe).

1. El jefe espera de espaldas, escribiendo en un pizarrón.
2. Al entrar a la sala, la puerta se cierra con niebla, voltea y grita.
3. Al ganar se abre el **Pasaje Central** (`register_boss_defeated("biblioteca")`).
4. Si mueres: "HAS MUERTO" y con **R** reintentas en la entrada de la biblioteca.

## Ataques

| Fase | Ataque | Cómo esquivarlo |
|---|---|---|
| 1 y 2 | Lanza libros en arco (ráfagas de 1 a 3) | Moverse de lado o rodar |
| 1 y 2 | Lluvia de libros: marca círculos en el suelo y caen libros del techo | Salirse del círculo |
| 1 y 2 | **Pizarrón**: corre a un pizarrón, escribe una fórmula (recta, seno, parábola, valor absoluto) y dibuja su gráfica; de la gráfica salen flechas que siguen la forma de la función | Leer la curva y rodar en el momento |
| 1 y 2 | Rasguños rápidos a corta distancia | Rodar hacia atrás |
| 1 y 2 | **Agarre**: se lanza; si te atrapa te rasguña 5 veces de forma desesperada (estado *atrapado*) | Rodar cuando abre los brazos |
| 2 | **Hojas de papel**: flotan sobre él y disparan flechas mágicas guiadas; mientras, se agarra la cabeza con dolor | Rodar a último momento; es la ventana para pegarle |
| 2 | Las flechas del pizarrón son **de fuego**: dejan *quemadura* (1 de daño cada 0.5 s durante 5 s) | — |

En la fase 2 la biblioteca se incendia poco a poco (fuego, humo y brasas).

## Estados alterados del jugador (`test_player.gd`)

- `apply_status(nombre, segundos)`, `clear_status`, `has_status`, `get_status_names`.
- `electrocutado` (2 s, no te puedes mover): probabilidad baja (`electrocute_chance = 0.2`)
  en los golpes eléctricos del **primer jefe** y en sus rayos.
- `quemadura` (5 s, daño progresivo).
- `atrapado` (mientras el Bibliófilo te sujeta).
- El HUD muestra los estados activos bajo la barra de vida.

## Archivos

- `boss_bibliotecario.gd` / `BossBibliotecario.tscn`: jefe (modelo, poses, IA, ataques).
- `library_fight.gd` / `LibraryFight.tscn`: controlador (niebla, HUD, incendio, reintento).
- `library_projectile.gd`: libros, flechas por función y flechas guiadas.
- `library_fx.gd`: texturas de cuadros/mezclilla, fuego, humo, brasas, papeles.
- Los pizarrones están en `scripts/campus_world.gd` (`LIB_BOARDS` y `_make_library`).
