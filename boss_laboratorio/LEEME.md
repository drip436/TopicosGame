# Cuarto jefe: Doctor Viktor Kessler, el Paciente Cero

Científico loco del **Laboratorio de Biogenética** que experimentaba con humanos… y consigo mismo.
Apariencia inspirada en Conquest (Invincible): viejo enorme y musculoso, pelo blanco peinado hacia
atrás, cara llena de cicatrices, un ojo muerto que brilla, traje negro y bata de laboratorio rota.

**Armas:** un **tubo radiactivo** (cuerpo a cuerpo) y una **pistola láser** (a distancia).

## Cómo se activa

No hay que tocar `main.tscn`: `CampusWorld` crea `LabFight.tscn` al jugar
(opción `spawn_lab_boss` en el inspector de CampusWorld).

1. Trabaja en su mesa frente a la cápsula Ω-01, de espaldas a la entrada.
2. Al entrar, la puerta se cierra con niebla, voltea y se ríe.
3. Al ganar mueren sus mutantes y se abre el **Edificio de Posgrado**
   (`register_boss_defeated("laboratorio")`), y el Aula Magna si ya cayeron los otros jefes.
4. Si mueres: **R** para reintentar desde la última hoguera.

## Fase 1: el científico escurridizo

| Ataque | Notas |
|---|---|
| Frascos de veneno (1–3) | Caen sobre un círculo de aviso: daño en área + **charco** que llena la barra de VENENO |
| Pistola láser | Ráfagas de 4 disparos verdes |
| Tubo radiactivo | Dos golpes; también acumulan veneno |
| Invocar mutantes | Saca 3 mutantes pequeños sin dejar de trabajar |
| Experimento | Se queda trabajando 3.5 s: **si no lo interrumpes, se cura** (un golpe lo interrumpe) |
| Horda | Bomba de humo, **6–8 mutantes** y se esconde: se vuelve casi invisible hasta que la horda cae |
| Escape | Si te le pegas, salta hacia atrás con humo (a veces deja un frasco de trampa) |

## Fase 2 (al 50 %): el mutante

Se inyecta su suero en el cuello, convulsiona y crece al doble (unos 5.5 m): piel verde, pústulas
brillantes, espinas de hueso y la bata hecha jirones.

| Ataque | Notas |
|---|---|
| Barriles de toxinas | Explosión grande + charco de veneno |
| **Agarre** | Si te atrapa, te levanta y **te estampa contra la pared** (daño fuerte) |
| Aplastar con el tubo | Golpe de área |
| Barrido con el tubo | Muy amplio |
| Rayo láser | Primero apunta (línea verde) y luego barre la sala con un rayo continuo |
| Horda | De vez en cuando sigue llamando mutantes |

## Archivos

- `boss_doctor.gd` / `BossDoctor.tscn`: jefe (modelo, transformación, IA, ataques, charcos).
- `lab_fight.gd` / `LabFight.tscn`: controlador (niebla, HUD, luces verdes en fase 2, reintento).
- Los mutantes invocados son los mismos `mutante_peq` de `mundo/enemy.gd`.
