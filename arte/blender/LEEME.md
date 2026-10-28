# Modelos 3D en Blender

Todos los modelos se generan con scripts de Python para Blender 5.x (sin abrir la interfaz).
Cada script construye el modelo pieza por pieza, le pone esqueleto, hornea las texturas de
desgaste (óxido, rayones, suciedad, venas de la piel…) y exporta un `.glb` a `modelos/`.

```
blender -b --python arte/blender/<script>.py -- <carpeta_salida> [preview]
```

`preview` además renderiza imágenes de revisión en la carpeta de salida (no las copies al
proyecto). Hornear cada modelo tarda entre 30 s y 1 min con la GPU.

## Enemigos (con animaciones propias)

| Script | Salida | Tipos de `mundo/enemy.gd` |
|---|---|---|
| `robot.py` | `modelos/robot/robot.glb` | `robot`, `robot_hacha`, `robot_espada`, `robot_laser` |
| `mecha.py` | `modelos/mecha/mecha.glb` | `mecha` |
| `androide.py` | `modelos/androide/androide.glb` | `androide_espadas`, `androide_cables`, `androide_script` |
| `mutante.py` | `modelos/mutante/mutante_{peq,med,grande}.glb` | `mutante_peq`, `mutante_med`, `mutante_grande` |
| `armas.py` | `modelos/armas/*.glb` | hacha, espada, pistola láser y hoja de androide |

Los tiempos de impacto de cada animación de ataque están en la cabecera de cada script y
en las tablas `GLB_IMPACT` / `GLB_IMPACT_BY_TYPE` de `enemy.gd`. Si cambias una
animación, actualiza los dos.

`mutante.py` y `armas.py` aceptan nombres para generar solo algunos modelos, p. ej.
`... -- modelos/mutante grande` o `... -- modelos/armas hoja_androide`.

## Jefes (cuerpos humanos realistas; siguen al esqueleto del código)

| Script | Salida | Jefe |
|---|---|---|
| `jefe_catedratico.py` | `catedratico.glb` | Catedrático de Hierro |
| `jefe_bibliofilo.py` | `bibliofilo.glb` | Bibliófilo Demente |
| `jefe_ada.py` | `ada7.glb` | ADA-7 |
| `jefe_kessler.py` | `kessler.glb`, `kessler_mutante.glb` | Dr. Kessler (fase 1 y fase 2) |
| `jefe_rector.py` | `rector.glb`, `rector_sin_toga.glb` | Rector Eterno (fase 1 y fase 2) |

(todos en `modelos/jefes/`)

Los jefes parten de las **mallas base humanas de Blender** (CC0, en
`arte/recursos/human_base_meshes/`, con `.gdignore` para que Godot no intente importar el
`.blend`). `humano.py`:

1. Carga el cuerpo realista (hombre o mujer) con su rostro esculpido.
2. Le pone un esqueleto, pesa la piel automáticamente y la deforma hasta las proporciones
   de cada jefe (`targets()`: tamaño, ancho, largo de brazos y piernas, grosor por hueso).
3. Guarda zonas del cuerpo (cuero cabelludo, cejas, bigote, piocha, barba, labios, torso,
   brazos, manos, piernas, pies) para sacar de ellas pelo, barba, ropa y armadura, que así
   quedan ajustados al cuerpo y se deforman con él.
4. Armaduras al estilo de Elden Ring con tecnología: `plate()` (placa acanalada con
   grosor, ribete en el borde y costura que brilla), `lames()` (láminas encimadas:
   hombreras, escarcelas, brazales), `strap()` (correas y bandas), `attach()` (piezas
   modeladas que se mueven con la piel) y `at()` (pasa un punto de la malla base al cuerpo
   ajustado).

En el juego, `boss_profesor/boss_skin.gd` esconde las primitivas del código, mueve las
articulaciones a donde quedaron los huesos del cuerpo realista y hace que los huesos sigan
a las articulaciones, así que los ataques y poses no cambian. Si borras un `.glb`, el jefe
vuelve a verse con sus primitivas.

Los materiales que el código anima (ojos, núcleo de ADA, pierna débil, tubo radiactivo,
circuitos del Rector) se llaman igual en Blender y `boss_skin.gd` los cambia por los del
jefe. Las armas que aparecen y desaparecen (maza, espadas compiladas, revólver…) siguen
siendo las del código.

## Jugador

| Script | Salida |
|---|---|
| `jugador.py` | `modelos/jugador/jugador_<clase>.glb` (cyber, backend, frontend, ai, data) |
| `armas_jugador.py` | `modelos/armas_jugador/*.glb` (espada, escudo, estoque, baston, mazo, tableta, lanza, arco) |

`jugador.py` usa `humano.py` con las articulaciones exactas de `jugador/player_rig.gd`
(pose T), así que el esqueleto y las animaciones del juego lo mueven tal cual. Ambos
scripts aceptan nombres para generar solo algunos modelos (`... -- modelos/jugador cyber`).

## Librería (`bk.py`)

- Piezas: `box`, `cyl`, `sphere`, `panel` (placa con línea de panel), `bolts`, `vents`,
  `cable`, `piston`, `label`, `hazard`, `cloth` (tela rasgada que puede seguir a dos
  huesos), `blob` (masa orgánica), `limb` (tubo orgánico de radio variable).
- Materiales: `worn_material` (pintura/metal con desgaste en bordes, óxido, chorreaduras,
  hollín, suciedad, grabado ornamental `engrave`, cota de malla `chain` y tela a cuadros),
  `skin_material` (piel con venas, moretones, poros, zonas húmedas y tinte por zonas) y
  `hair_material` (mechones, raíces y canas). Los colores son lineales: valores bajos (≈0.1–0.4).
- `finish` une todo, hace UV y hornea color/rugosidad/metal/normal; `action` crea
  animaciones; `export` saca el `.glb`.

## Utilería de las arenas y vehículos (`utileria.py`)

```
blender -b --python arte/blender/utileria.py -- modelos/utileria [preview] [nombre ...]
```

Modelos estáticos con desgaste horneado, origen en el piso y frente hacia +Y (en Godot
miran a −Z; los vehículos van a lo largo de X con el frente hacia +X):

| Zona | Modelos |
|---|---|
| Laboratorio (Dr. Kessler) | `barril_toxico`, `barril_azul`, `barril_oxidado`, `tanque_quimico`, `caja_biopeligro`, `mesa_lab`, `camilla` |
| Centro de Cómputo (ADA-7) | `rack_servidor`, `escritorio_pc`, `silla_oficina`, `pc_vieja`, `bobina_cable` |
| Biblioteca (Bibliófilo) | `mesa_lectura`, `fichero`, `carrito_libros`, `globo`, `atril` |
| Plaza (Catedrático) | `pupitre`, `pizarron` (y `atril`) |
| Aula Magna (Rector) | `butacas`, `podio`, `estandarte`, `candelabro` |
| Calles | `auto_rojo`, `auto_gris`, `auto_azul`, `auto_quemado`, `autobus_amarillo`, `autobus_quemado` |

En el juego se colocan con `_prop(nombre, posición, giro, colisión, volcado)` de
`scripts/arena_generator.gd` (se dibujan con MultiMesh). Después de exportar, borra los
`*_color/_metal/_normal/_rough.png` sueltos que deja el horneado (el .glb ya los trae
dentro); **no** borres los `<nombre>_<nombre>_*.png`, que son los que extrae Godot.

## Texturas de relieve del escenario (`arte/texturas/gen_texturas.py`)

```
python3 arte/texturas/gen_texturas.py texturas
```

Genera `texturas/{concreto,ladrillo,metal,madera,yeso}_{n,d}.png` (sin costuras): normales,
y en `_d` color (R), rugosidad (G) y juntas/mortero (B). Los shaders del mundo las
proyectan en coordenadas de mundo (`shaders/detalle.gdshaderinc`) y los materiales las
reciben con `_relieve(material, tipo, repeticiones_por_metro)`. Las fachadas usan además
`_facade_mesh()`: ventanas hundidas, alféizar, dintel, moldura de entrepiso y pilastras.

## Jugador: armaduras del mercader y mercader (`jugador.py`)

Además de las 5 clases, `jugador.py` genera las armaduras que vende el mercader
(`armadura_ignifuga`, `armadura_aislante`, `armadura_antiveneno`, `armadura_anclaje`,
`armadura_rector`) y al **mercader** (`mercader.glb`, a partir de la foto de referencia: pelo
lacio con fleco, lentes rectangulares, chamarra rompevientos, playera azul marino, mezclilla,
audífonos al cuello y gafete con listón rojo). Todos comparten el esqueleto de
`jugador/player_rig.gd`, con las manos cerradas en puño (`humano.curl_hands`).

```
blender -b --python arte/blender/jugador.py -- modelos/jugador [preview] [frontend | armadura_rector | mercader ...]
TEX=1024 ...   # resolución de las texturas horneadas (por defecto 4096 las clases, 2048 lo demás)
```

`armas_jugador.py` incluye las armas del mercader: `katana_plasma`, `espada_cortafuegos`,
`mandoble`, `hacha_servidor`, `alabarda` y `estoque_cuantico`.

**Ojo:** no hornees mientras Godot u otro Blender usan la GPU: si se llena la memoria el
horneado puede salir negro sin dar error. `bk.py` lo detecta y repite el horneado en CPU.
Después de importar en Godot, pon las texturas extraídas en *VRAM Compressed*
(`compress/mode=2`); sin compresión llenan la memoria de video.
