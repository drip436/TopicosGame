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

## Jefes (sin animaciones: siguen al esqueleto del código)

| Script | Salida | Jefe |
|---|---|---|
| `jefe_catedratico.py` | `catedratico.glb` | Catedrático de Hierro |
| `jefe_bibliofilo.py` | `bibliofilo.glb` | Bibliófilo Demente |
| `jefe_ada.py` | `ada7.glb` | ADA-7 |
| `jefe_kessler.py` | `kessler.glb`, `kessler_mutante.glb` | Dr. Kessler (fase 1 y fase 2) |
| `jefe_rector.py` | `rector.glb`, `rector_sin_toga.glb` | Rector Eterno (fase 1 y fase 2) |

(todos en `modelos/jefes/`)

Los jefes se animan desde su código moviendo articulaciones. Cada pieza del modelo de
Blender se pega al hueso que se llama igual que la articulación, y
`boss_profesor/boss_skin.gd` hace que los huesos sigan a las articulaciones. Por eso las
posiciones de los jefes se escriben en coordenadas de Godot con `G(x, y, z)`: tienen que
coincidir con las del modelo procedural. Si borras un `.glb`, el jefe vuelve a verse con
sus primitivas.

Los materiales que el código anima (ojos, núcleo de ADA, pierna débil, tubo radiactivo,
circuitos del Rector) se llaman igual en Blender y `boss_skin.gd` los cambia por los del
jefe. Las armas que aparecen y desaparecen (maza, espadas compiladas, revólver…) siguen
siendo las del código.

## Librería (`bk.py`)

- Piezas: `box`, `cyl`, `sphere`, `panel` (placa con línea de panel), `bolts`, `vents`,
  `cable`, `piston`, `label`, `hazard`, `cloth` (tela rasgada que puede seguir a dos
  huesos), `blob` (masa orgánica), `limb` (tubo orgánico de radio variable).
- Materiales: `worn_material` (pintura/metal con desgaste en bordes, óxido, chorreaduras,
  hollín, suciedad y opción de tela a cuadros) y `skin_material` (piel con venas,
  moretones, poros y zonas húmedas). Los colores son lineales: valores bajos (≈0.1–0.4).
- `finish` une todo, hace UV y hornea color/rugosidad/metal/normal; `action` crea
  animaciones; `export` saca el `.glb`.
