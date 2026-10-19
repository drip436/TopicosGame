# Clases del jugador

La clase se elige en el selector (`Scenes/BuildSelector.tscn`: Menú → Nueva partida).
Si se abre `main.tscn` directo, se usa **Cybersecurity** (`DEFAULT` en `player_classes.gd`).

| Clase | Rol | Vida | Armas | Clic izq. | Clic der. | Q | Particularidad |
|---|---|---|---|---|---|---|---|
| Frontend Developer | Mago | 85 | Estoque + bastón tecnológico | Estoque | Lanzar hechizo | Cambiar hechizo | Barra azul de **maná**; **G** bebida energética (+60) |
| Backend Developer | Tanque | 150 | Mazo | Mazazo (área corta) | Golpe sísmico (35 estamina) | — | Recibe 30 % menos daño; lento y rodar cuesta 40 de estamina |
| AI Dev | Invocador | 95 | Tableta holográfica | Ataque de la IA | Especial de la IA | Cambiar IA | IAs tipo stand: ChatGPT, Gemini, Claude |
| Cybersecurity | Caballero | 120 | Espada + escudo | Espada | **Mantener**: cubrirse | — | Bloquea 85 % del daño de frente (gasta estamina) |
| Data Scientist | Arquero | 95 | Lanza + arco | Lanza | Flecha (infinitas) | — | La clase más rápida |

Ninguna clase mata a un jefe de un golpe: el ataque más fuerte (golpe sísmico) hace 70 y los
jefes tienen entre 1400 y 2000 de vida.

## Hechizos del Frontend (antes de cada uno aparece código flotando)

| Hechizo | Maná | Efecto |
|---|---|---|
| Bola de fuego | 18 | Proyectil guiado que explota en área |
| Rayos del cielo | 28 | 3 rayos sobre el punto apuntado |
| Flecha matemática | 14 | 3 flechas que siguen la curva de f(x) (seno, parábola o \|sin\|) |
| Lluvia de flechas | 30 | 24 flechas sobre un círculo |
| Nova arcana | 25 | Explosión de área alrededor |
| Frasco de veneno | 16 | Charco que daña durante 5 s |

El maná no se regenera solo: se recupera con **bebidas energéticas** (3, se rellenan en las hogueras).

## IAs del AI Dev (stands)

| IA | Estilo | Ataque | Especial (clic der.) |
|---|---|---|---|
| ChatGPT | Gigante de fuerza bruta | Puñetazo de área | Salto aplastante |
| Gemini | Arquero | Flecha guiada | Ráfaga de 5 flechas |
| Claude | Espadachín | Dos tajos | Ráfaga de cortes |

## Armaduras de resistencia

Están en maniquíes junto a cuatro hogueras. Se equipan **descansando en una hoguera** y
presionando **0–4**:

| Armadura | Dónde | Efecto |
|---|---|---|
| Aislante | Hoguera de la Plaza | 50 % de las veces no te electrocutan; si pasa, dura 30 % |
| Ignífuga | Hoguera de la Biblioteca | Quemaduras: 40 % de duración y mitad de daño |
| Anclaje | Hoguera del Centro de Cómputo | Atrapado: dura la mitad y recibes la mitad de daño |
| Antiveneno | Hoguera de la Fuente de las Ciencias | La barra de veneno/ameba sube al 35 %; el veneno hace 40 % de daño |

## Estados alterados

Ya no cubren al jugador: se muestran como un tinte tenue de color sobre el cuerpo y unas pocas
chispas pequeñas a su alrededor.

## Archivos

- `player_classes.gd`: datos de las clases y de las armaduras de resistencia.
- `class_kit.gd`: armaduras, armas y ataques de cada clase (lo crea `test_player.gd`).
- `player_projectile.gd`: flechas, flecha matemática, bola de fuego y veneno del jugador.
- `stand.gd`: las IAs del AI Dev.
