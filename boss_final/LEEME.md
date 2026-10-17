# Jefe final: El Rector Eterno, Sínodo de la Última Tesis

Pelón, con barba de candado y túnica académica con ribetes dorados. Espera en el **Aula Magna**.

## Cómo se llega

El portón del Aula Magna solo se abre con las **4 piezas de la llave**: cada jefe anterior
suelta una al morir (Catedrático, Bibliófilo, ADA-7 y Kessler). Se recogen pasando encima;
el HUD muestra `Llave del Aula Magna  n / 4` arriba a la derecha.

## El encuentro

Al entrar a la arena la niebla cierra el túnel y el Rector habla (E / clic para avanzar):

> Vaya… lograste venir hasta aquí. Te felicito… Has demostrado que eres digno de titularte.
> ¿Ya te quieres titular de la carrera, o prefieres esperarte a hacer tu residencia como
> guerrero para liberar a la universidad?

Se elige con el mouse o con las teclas **1** / **2**:

1. **"Ya me quiero titular."** → camina hacia ti: *"Muy bien… has escogido el buen camino, el
   camino que cambiará el mundo, el camino donde harás la tesis que cambiará el mundo… una tesis
   que jamás podrás terminar."* → **Final malo: LA TESIS INTERMINABLE**.
2. **"Esperaré: haré mi residencia como guerrero."** → *"Entonces… demuéstralo."* Desenfunda la
   espada con una mano y empieza la pelea.

Si mueres y reintentas, ya no vuelve a preguntar.

## La pelea

| Fase | Ataque |
|---|---|
| 1 y 2 | Combos desesperados de 3–5 tajos, estocada que cruza el espacio, giro de 360° |
| 1 y 2 | **Esquiva tus golpes** con una estela y contraataca |
| 1 y 2 | **Revólver** cuando te alejas (ráfagas de 3–6 tiros) |
| 1 y 2 | Hechizos de área: nova arcana, círculos que te persiguen, anillo de fuego |
| 2 | **Corte de fuego** (onda que deja quemadura) y **corte de rayo** (puede electrocutar) |
| 2 | **Lluvia de flechas** sobre un círculo alrededor tuyo |
| 2 | **Código**: compila 5 espadas espectrales que te lanza, o un hechizo |
| 2 | **Invoca 1–2 IAs** holográficas (espada y láser) |
| 2 | **Manipula el espacio**: se teletransporta a tu espalda, y te jala hacia su espada |

Fase 2: al vaciarle la vida, se arrodilla, **se quita la túnica**, su **espada brilla en rojo** y
su vida **se vuelve a llenar**.

## El final

Al vencerlo suelta la **TESIS**. Al recogerla, una voz dice:
*"Has liberado al mundo de la maldición… ahora reclama tu recompensa."*
El cielo se despeja y aparece la pantalla de **FIN**. **R** vuelve a empezar.

## Archivos

- `boss_rector.gd` / `BossRector.tscn`: jefe (modelo, túnica, espada, revólver, IA, ataques).
- `final_fight.gd` / `FinalFight.tscn`: diálogo, elección, finales, tesis, niebla, reintento.
- Piezas de la llave: `mundo/key_piece.gd` (las coloca `mundo/world_life.gd`) y
  `add_key_piece()` en `scripts/campus_world.gd`.
