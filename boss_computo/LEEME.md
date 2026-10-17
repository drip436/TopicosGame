# Tercer jefe: ADA-7, la Administradora del Núcleo

Humanoide mitad androide de casi 5 m (como un mecha) que pelea en el **Centro de Cómputo**.
La mitad derecha es humana y la izquierda de cromo; lleva un rack de servidores en la espalda
del que cuelgan cables eléctricos. Pelea con **dos espadas**.

## Cómo se activa

No hay que tocar `main.tscn`: `CampusWorld` crea `ComputeFight.tscn` al jugar
(opción `spawn_compute_boss` en el inspector de CampusWorld).

1. ADA-7 está conectada al Núcleo Central, de espaldas a la entrada.
2. Al entrar, la puerta se cierra con niebla; se desconecta, voltea y ruge.
3. Al ganar se abre el **Edificio de Aulas Norte** (`register_boss_defeated("computo")`).
4. Si mueres: **R** para reintentar desde la última hoguera donde descansaste.

## Punto débil: la pierna robótica izquierda

- Los golpes dados **junto a su pierna izquierda** hacen ×1.5 de daño y van rompiendo la pierna
  (barra naranja "PIERNA IZQUIERDA" bajo la vida del jefe). El núcleo de la rodilla brilla más
  conforme se daña.
- En el resto del cuerpo el daño es ×0.6.
- Al romperse la pierna (o al bajar al 45 % de vida) empieza la fase 2.

## Ataques

| Fase | Ataque | Notas |
|---|---|---|
| 1 | Combo de espadas dobles (2–3 tajos) | Con embestida corta |
| 1 | Estocada doble | Embestida larga en línea recta |
| 1 | Latigazos de cables de servidor | Eléctricos; pueden electrocutar |
| 1 | **Scripts**: compila un arma en su mano | Código flotando + holograma; dura 1–2 ataques |
| 1 | · Espada grande | Tajo enorme de casi 300° |
| 1 | · Hacha | Hachazo que abre una grieta en línea recta |
| 1 | · Maza | Dos golpes al suelo con onda de choque |
| 1 | · Martillo de guerra | Salta y cae sobre ti (área grande) |
| 1 y 2 | Hechizo de **electricidad** | Rayos del techo sobre círculos de aviso |
| 1 y 2 | Hechizo de **fuego** | Anillo que se expande: ruédalo; deja quemadura |
| 1 y 2 | Hechizo de **magia** | Círculos que te persiguen y estallan |
| 2 | Golpe doble | Se levanta en los brazos y golpea el suelo |
| 2 | Embestida arrastrándose | Se arrastra rapidísimo y remata con área |
| 2 | Tormenta de cables | Varios latigazos alrededor tuyo |
| 2 | Lluvia de armas | Scripts que dejan caer armas sobre ti |

## Sin puntos ciegos

Quedarse detrás de ella o pegado a la pierna débil no es seguro:

- Si te quedas **detrás** (~1 s): gira con las espadas (360°), barre con los cables en círculo o pisa.
- Si te quedas **pegado a la pierna** (~2 s): pulso electromagnético que te empuja, pisotón o giro.
- En fase 2 responde igual con barrido de cables, pulso y golpe doble.

La idea es pegarle a la pierna y salir, no quedarse ahí.

## Archivos

- `boss_admin.gd` / `BossAdmin.tscn`: jefe (modelo, poses, IA, ataques).
- `compute_fight.gd` / `ComputeFight.tscn`: controlador (niebla, HUD, alarmas de fase 2, reintento).
- Barra del punto débil: `set_boss_part()` en `boss_profesor/boss_hud.gd`.
