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

## Modelos de Blender (cuerpo, armadura y armas)

Si existen, el jugador usa los modelos hechos en Blender (`arte/blender/jugador.py` y
`arte/blender/armas_jugador.py`):

- `modelos/jugador/jugador_<clase>.glb`: cuerpo humano realista parecido a la foto de
  referencia (piel morena, pelo negro rizado y voluminoso, lentes redondos de armazón
  metálico, complexión robusta, playera blanca, pantalón oscuro y botas) y la armadura de la
  clase, ya pesado a los mismos 17 huesos de `player_rig.gd` (en pose T y con las
  articulaciones en `BONES`). `player_rig.build()` lo monta en su esqueleto y
  `class_kit.gd` ya no arma la armadura de primitivas. El material `ribete` toma el color
  de la armadura de resistencia equipada.
  - Caballero: placas acanaladas con costuras cian, tabardo verde con candado, yelmo con
    visor encendido y capa corta.
  - Tanque: acero oscuro pesadísimo, hombreras enormes, yelmo con rejilla, luces naranjas y
    módulo de servidor a la espalda.
  - Mago: túnica azul larga con runas, capucha, manto de láminas y brazales.
  - AI Dev: bata blanca abierta, arnés con núcleo de IA, visor y botas tecnológicas.
  - Arquero: brigantina de cuero con remaches, capa verde (sin capucha), carcaj y bolsas.
  El AI Dev, el arquero y el mago muestran la cara con los lentes; el caballero y el tanque
  la llevan dentro del yelmo.
- `modelos/armas_jugador/*.glb`: espada, escudo, estoque, bastón (el orbe es del código),
  mazo, tableta, lanza y arco, modelados en el espacio de su pivote; reemplazan a las
  primitivas sin cambiar cómo se sostienen.

Si se borra un modelo, vuelve la versión anterior (malla de la skin + primitivas).

## Esqueleto y animaciones (`player_rig.gd`)

El modelo del jugador era una malla estática en pose T. Al aparecer se le construye un
**esqueleto de 17 huesos** y cada vértice se pesa automáticamente a sus huesos según la zona
del cuerpo (con mezcla suave en hombros, codos, muñecas, cuello, cadera y rodillas).
Las armas y la armadura van pegadas a los huesos (`BoneAttachment3D`).

Animaciones (procedurales, por capas):

- **Locomoción:** quieto con respiración, caminar y correr (zancada, rodillas, balanceo de brazos,
  inclinación del torso al correr).
- **Rodada:** voltereta encogida alrededor del centro del cuerpo (ya no gira desde los pies,
  así que no atraviesa el suelo).
- **Curar:** se lleva la taza de café a la boca (lata azul con la bebida energética); guarda el arma
  mientras bebe y puede seguir moviéndose.
- **Combos por arma** (clic izquierdo repetido; el clic se guarda si lo presionas a media animación).
  Cada golpe es una secuencia de cuadros clave (`ATTACKS`): guardia → anticipación (el arma
  atrás, el torso gira y el peso pasa al pie de atrás) → golpe que acelera, con paso al
  frente, giro de cadera y el cuerpo que baja → inercia del arma → recuperación. El impacto
  cae justo en el momento de daño de cada paso del combo.

| Clase | Arma | Combo |
|---|---|---|
| Ciberseguridad | Espada | Tajo derecho (38) → revés (40) → golpe vertical (55) |
| Frontend | Estoque | Estocada (22) → estocada (24) → estocada a fondo con zancada (34) |
| Backend | Mazo | Mazazo vertical (52) → barrido horizontal (60) |
| Data Scientist | Lanza | Estocada (30) → estocada (32) → barrido giratorio (42) |
| AI Dev | Brazo | Señala con el brazo para que su IA ataque |

- **Habilidades:** cubrirse con el escudo, lanzar hechizo con el bastón en alto, tensar el arco,
  golpe sísmico con ambos brazos, invocar con los brazos en alto.
- **Reacciones:** retroceso al recibir golpe, temblor al estar electrocutado, forcejeo al estar
  atrapado y caída al morir.

## Créditos, mercader y equipo

- **Créditos** (`Partida.creditos`): cada enemigo suelta cristales dorados al morir que vuelan
  hacia el jugador (`mundo/credito.gd`, cantidades en `equipo.gd` → `DROPS`); cada jefe suelta
  un botín grande (`BOSS_CREDITS`). Se ven abajo a la derecha del HUD y se guardan al
  descansar en una hoguera, junto con el inventario.
- **Mercader** (`mundo/mercader.gd`, modelo `modelos/jugador/mercader.glb`): está junto a la
  Hoguera de la Plaza, te saluda con la "V" y con **E** abre la tienda (`ui/tienda.gd`).
- **Catálogo** (`jugador/equipo.gd`):
  - Armas: cada una tiene un tipo (`espada`, `mazo`, `estoque`, `lanza`) que decide sus combos
    y cómo se agarra, más multiplicadores de daño y velocidad, y un efecto opcional
    (quemadura, electrocutado o veneno) que hace daño continuo al enemigo (`mundo/dot.gd`).
    Cualquier clase usa cualquier arma; la habilidad de clic derecho no cambia.
  - Armaduras: reemplazan la ropa de la clase por su modelo (`modelos/jugador/armadura_*.glb`)
    y bajan los estados alterados (duración, daño por segundo, barra de veneno, daño estando
    atrapado o probabilidad de no recibirlo) y el daño recibido.
- **Menú de equipo:** Esc → Equipo (`ui/panel_equipo.gd`, el mismo panel que usa la tienda).
- **Manos de agarre:** los modelos se generan con las manos cerradas en puño
  (`humano.curl_hands`), así el mango del arma queda dentro del puño.
