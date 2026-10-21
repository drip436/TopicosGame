"""Primer jefe: "Catedrático de Hierro" (boss_profesor/boss_profesor.gd).
Profesor con armadura de placas abollada y oxidada encima de su ropa de diario: camisa
blanca manchada y rota, jeans deslavados con la rodilla rota, morral azul marino gastado,
libreta roja encadenada a la cadera, toga académica hecha jirones y yelmo cerrado con
birrete y borla. La maza con cadena sigue siendo la del código (se electrifica).

El modelo se construye en el espacio del nodo "Model" del jefe (sin su escala de 1.5) y
cada pieza se pega al hueso que se llama como la articulación del código; en el juego
boss_skin.gd hace que los huesos sigan a las articulaciones (no hacen falta animaciones).
Coordenadas: Blender (x, y, z) = Godot (x, -z, y); el jefe mira hacia +Y.

Uso:  blender -b --python arte/blender/jefe_catedratico.py -- <carpeta_salida> [preview]
"""
import sys
import os
import math

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, sphere, panel, bolts, cable, label, cloth, blob, limb

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/jefes")
PREVIEW = "preview" in argv
os.makedirs(OUT, exist_ok=True)

bk.reset(seed=101)
bk.define_materials({
    "acero": dict(base=(0.42, 0.43, 0.45), metal=0.8, rough=0.42, rust=0.75, wear=0.45, dirt=0.8, bare=(0.62, 0.62, 0.64), streaks=0.75, soot=0.45),
    "oscuro": dict(base=(0.05, 0.05, 0.055), metal=0.7, rough=0.5, rust=0.9, wear=0.8, dirt=0.8, bare=(0.4, 0.4, 0.42), streaks=0.5, soot=0.4),
    "oro": dict(base=(0.5, 0.33, 0.08), metal=1.0, rough=0.35, rust=0.35, wear=0.6, dirt=0.8, bare=(0.75, 0.6, 0.3), soot=0.4),
    "camisa": dict(base=(0.36, 0.34, 0.27), rough=0.95, rust=0.45, wear=0.4, dirt=1.3, bare=(0.25, 0.22, 0.16), scratches=False, streaks=0.7, soot=0.45),
    "mezclilla": dict(base=(0.035, 0.06, 0.13), rough=0.92, rust=0.15, wear=0.9, dirt=1.1, bare=(0.3, 0.34, 0.4), scratches=False, soot=0.3),
    "morral": dict(base=(0.015, 0.02, 0.045), rough=0.85, rust=0.1, wear=0.8, dirt=1.0, bare=(0.13, 0.14, 0.18), scratches=False, soot=0.3),
    "toga": dict(base=(0.01, 0.01, 0.012), rough=0.85, rust=0.1, wear=0.7, dirt=1.1, bare=(0.08, 0.075, 0.07), scratches=False, soot=0.5),
    "libreta": dict(base=(0.22, 0.015, 0.015), rough=0.6, rust=0.1, wear=0.9, dirt=0.8, bare=(0.35, 0.25, 0.2), soot=0.3),
    "cuero": dict(base=(0.09, 0.05, 0.025), rough=0.7, rust=0.0, wear=0.85, dirt=0.9, bare=(0.22, 0.14, 0.08)),
    "metal": dict(base=(0.45, 0.45, 0.46), metal=1.0, rough=0.4, rust=1.0, wear=0.4, dirt=0.7, bare=(0.75, 0.75, 0.77)),
    "ojos": {"emit": (1.0, 0.45, 0.12), "strength": 6.0},
})

# ------------------------------------------------------------------ cintura (pelvis)
cyl("escarcela", 0.29, 0.24, (0, 0, 0.93), bone="pelvis", mat="acero", verts=28, r2=0.27, bevel=0.01)
cyl("cinturon", 0.3, 0.06, (0, 0, 1.05), bone="pelvis", mat="cuero", verts=28, bevel=0.004)
box("hebilla", (0.1, 0.03, 0.08), (0, 0.24, 1.05), bone="pelvis", mat="oro", bevel=0.006)
for s in (-1, 1):
    for k in range(2):
        panel("faldon_%d_%d" % (s, k), (0.2, 0.035, 0.14), (s * 0.15, 0.2 + k * 0.01, 0.8 - k * 0.11), (-12 - k * 4, 0, s * -8), bone="pelvis", mat="acero", bevel=0.012)
    panel("faldon_lado_%d" % s, (0.035, 0.2, 0.26), (s * 0.3, 0.0, 0.76), (0, s * 10, 0), bone="pelvis", mat="acero", bevel=0.012)
    box("faldon_borde_%d" % s, (0.21, 0.04, 0.02), (s * 0.15, 0.22, 0.73), (-12, 0, s * -8), bone="pelvis", mat="oro", bevel=0.004)
# Faldón de camisa colgando por delante
cloth("camisa_faldon", 0.26, 0.6, (0, 0.24, 0.98), (-6, 0, 0), bone="pelvis", mat="camisa", nx=8, ny=12, tatter=0.35, holes=0.04, flare=0.05, seed=3)
# Libreta roja encadenada a la cadera izquierda
box("libreta", (0.06, 0.2, 0.26), (-0.37, -0.02, 0.83), (0, 0, 8), bone="pelvis", mat="libreta", bevel=0.008)
box("libreta_hojas", (0.05, 0.19, 0.24), (-0.365, -0.02, 0.83), (0, 0, 8), bone="pelvis", mat="camisa", bevel=0.004)
for k in range(4):
    cyl("cadena_lib_%d" % k, 0.018, 0.012, (-0.33 + k * 0.012, 0.06, 0.96 - k * 0.035), (90 if k % 2 else 0, 0, 0), bone="pelvis", mat="oscuro", verts=8, bevel=0)
# Morral cruzado en la cadera derecha (gastado, con la tapa caída)
box("morral", (0.13, 0.34, 0.3), (0.38, -0.06, 0.93), (0, 0, -6), bone="pelvis", mat="morral", bevel=0.03)
box("morral_tapa", (0.14, 0.345, 0.13), (0.385, -0.06, 1.04), (0, 0, -6), bone="pelvis", mat="morral", bevel=0.02)
box("morral_hebilla", (0.02, 0.04, 0.04), (0.455, -0.06, 0.98), bone="pelvis", mat="oro", bevel=0.004)
box("morral_parche", (0.015, 0.1, 0.08), (0.45, 0.04, 0.88), (0, 0, -6), bone="pelvis", mat="cuero", bevel=0.004)

# ------------------------------------------------------------------ piernas
for side, s in (("l", -1), ("r", 1)):
    h = side + "h"
    k = side + "k"
    limb("muslo_" + side, [(s * 0.15, 0, 0.9), (s * 0.15, -0.01, 0.68), (s * 0.15, 0, 0.47)], [0.12, 0.115, 0.105], bone=h, mat="mezclilla", lumps=0.05)
    panel("quijote_" + side, (0.24, 0.07, 0.34), (s * 0.15, 0.06, 0.7), (-3, 0, 0), bone=h, mat="acero", taper=(1.0, 1.0), bevel=0.03)
    panel("quijote_lado_" + side, (0.05, 0.18, 0.28), (s * 0.27, 0.0, 0.7), (0, 0, 0), bone=h, mat="acero", bevel=0.02)
    box("quijote_borde_" + side, (0.25, 0.03, 0.025), (s * 0.15, 0.1, 0.54), bone=h, mat="oro", bevel=0.004)
    # Rodillera y pierna
    sphere("rodillera_" + side, 0.1, (s * 0.15, 0.07, 0.46), (1.15, 0.85, 1.0), bone=k, mat="acero", segs=16)
    cyl("rodillera_aleta_" + side, 0.07, 0.02, (s * 0.15 + s * 0.09, 0.04, 0.46), (0, 90, 0), bone=k, mat="oro", verts=14)
    limb("pierna_" + side, [(s * 0.15, 0, 0.44), (s * 0.15, -0.01, 0.25), (s * 0.15, 0, 0.08)], [0.1, 0.095, 0.085], bone=k, mat="mezclilla", lumps=0.06)
    panel("greba_" + side, (0.2, 0.12, 0.34), (s * 0.15, 0.04, 0.25), (-2, 0, 0), bone=k, mat="acero", bevel=0.035)
    box("bota_" + side, (0.19, 0.36, 0.1), (s * 0.15, 0.07, 0.05), bone=k, mat="oscuro", bevel=0.03)
    panel("escarpe_" + side, (0.17, 0.14, 0.07), (s * 0.15, 0.2, 0.08), (22, 0, 0), bone=k, mat="acero", bevel=0.02)
# Rodilla izquierda: el jean roto deja ver la rodilla de metal sin placa
box("jean_roto", (0.12, 0.02, 0.08), (-0.15, 0.1, 0.4), (10, 0, 0), bone="lk", mat="camisa", bevel=0.01)

# ------------------------------------------------------------------ torso
cyl("abdomen", 0.31, 0.3, (0, 0, 1.17), bone="spine", mat="oscuro", verts=28, r2=0.27, bevel=0.01)
for i in range(3):
    cyl("lama_%d" % i, 0.32 - i * 0.01, 0.06, (0, 0.0, 1.07 + i * 0.09), bone="spine", mat="acero", verts=28, r2=0.3 - i * 0.01, bevel=0.008)
# Peto abollado
blob("peto", 0.37, (0, 0.0, 1.43), (1.18, 0.86, 0.95), bone="chest", mat="acero", lumps=0.035, segs=32, seed=5)
box("peto_cresta", (0.04, 0.05, 0.42), (0, 0.31, 1.44), (-4, 0, 0), bone="chest", mat="oro", bevel=0.008)
box("peto_borde", (0.52, 0.05, 0.05), (0, 0.27, 1.23), (10, 0, 0), bone="chest", mat="oro", bevel=0.008)
for i, (x, z, r) in enumerate([(0.15, 1.5, 0.05), (-0.18, 1.38, 0.04), (0.08, 1.3, 0.035)]):
    sphere("abolladura_%d" % i, r, (x, 0.315, z), (1, 0.4, 1), bone="chest", mat="oscuro", segs=10)
bolts("remaches_peto", [(x, 0.29, z) for x in (-0.28, 0.28) for z in (1.32, 1.52)], (90, 0, 0), bone="chest", r=0.016, h=0.014)
cyl("gola", 0.2, 0.14, (0, 0, 1.71), bone="chest", mat="acero", verts=24, r2=0.18, bevel=0.01)
cyl("cuello_camisa", 0.17, 0.07, (0, 0, 1.79), bone="chest", mat="camisa", verts=20, r2=0.165, bevel=0.004)
# Correa del morral cruzando el pecho
box("correa_frente", (0.07, 0.025, 0.86), (0.0, 0.33, 1.39), (8, 38, 0), bone="chest", mat="morral", bevel=0.004)
box("correa_atras", (0.07, 0.025, 0.6), (0.05, -0.33, 1.41), (-8, -38, 0), bone="chest", mat="morral", bevel=0.004)
# Toga académica: capa hecha jirones
cloth("toga", 0.75, 1.3, (0, -0.3, 1.65), (0, 0, 180), bone="cape", mat="toga", nx=18, ny=18, tatter=0.4, holes=0.05, wave=0.03, flare=0.12, seed=7)
# Cuello de la toga sobre los hombros
cyl("toga_cuello", 0.3, 0.08, (0, -0.05, 1.68), bone="chest", mat="toga", verts=24, r2=0.24, bevel=0.01)

# ------------------------------------------------------------------ brazos
for side, s in (("l", -1), ("r", 1)):
    sh = side + "s"
    el = side + "e"
    # Hombrera en capas
    blob("hombrera_" + side, 0.22, (s * 0.47, 0, 1.6), (1.1, 1.15, 0.85), bone=sh, mat="acero", lumps=0.03, segs=24)
    panel("hombrera2_" + side, (0.2, 0.42, 0.05), (s * 0.6, 0, 1.47), (0, s * 55, 0), bone=sh, mat="acero", taper=(1.0, 0.85), bevel=0.02)
    panel("hombrera3_" + side, (0.16, 0.38, 0.045), (s * 0.63, 0, 1.38), (0, s * 70, 0), bone=sh, mat="acero", taper=(1.0, 0.85), bevel=0.02)
    box("hombrera_borde_" + side, (0.05, 0.3, 0.05), (s * 0.58, 0, 1.69), (0, s * -30, 0), bone=sh, mat="oro", bevel=0.008)
    bolts("hombrera_rem_" + side, [(s * 0.47, y, 1.77) for y in (-0.1, 0.1)], (0, 0, 0), bone=sh, r=0.014, h=0.014)
    # Manga de la camisa (sucia, rota en el codo) y brazal
    limb("manga_" + side, [(s * 0.43, 0, 1.5), (s * 0.43, 0, 1.36), (s * 0.43, 0, 1.24)], [0.095, 0.09, 0.085], bone=sh, mat="camisa", lumps=0.12)
    cyl("brazal_" + side, 0.1, 0.16, (s * 0.43, 0, 1.32), bone=sh, mat="acero", verts=18, r2=0.095, bevel=0.01)
    sphere("codera_" + side, 0.085, (s * 0.43, -0.03, 1.24), (1, 1.1, 1), bone=el, mat="oro", segs=12)
    cyl("antebrazo_" + side, 0.088, 0.26, (s * 0.43, 0, 1.1), bone=el, mat="acero", verts=18, r2=0.075, bevel=0.01)
    cyl("puno_" + side, 0.11, 0.07, (s * 0.43, 0, 0.99), bone=el, mat="acero", verts=18, r2=0.085, bevel=0.008)
    box("guantelete_" + side, (0.13, 0.13, 0.15), (s * 0.43, 0.01, 0.91), bone=el, mat="oscuro", bevel=0.025)
    for f in range(4):
        box("dedo_%s_%d" % (side, f), (0.025, 0.04, 0.06), (s * 0.43 + (f - 1.5) * 0.03, 0.06, 0.85), (20, 0, 0), bone=el, mat="acero", bevel=0.006)
    cable("hilo_" + side, [(s * 0.47, 0.05, 1.3), (s * 0.5, 0.06, 1.25), (s * 0.48, 0.04, 1.2)], 0.004, bone=sh, mat="camisa")
# Mango de la maza en la mano derecha
cyl("mango", 0.032, 0.62, (0.43, 0, 0.69), bone="re", mat="cuero", verts=10, r2=0.035)
for k in range(5):
    cyl("mango_cinta_%d" % k, 0.037, 0.03, (0.43, 0, 0.88 - k * 0.07), (0, 0, k * 15), bone="re", mat="oscuro", verts=10)
sphere("mango_pomo", 0.05, (0.43, 0, 1.01), bone="re", mat="oro", segs=10)
cyl("mango_anillo", 0.05, 0.06, (0.43, 0, 0.38), bone="re", mat="oro", verts=12)

# ------------------------------------------------------------------ cabeza: yelmo cerrado con birrete
cyl("yelmo", 0.18, 0.34, (0, 0, 1.96), bone="head", mat="acero", verts=28, r2=0.165, bevel=0.012)
sphere("yelmo_cupula", 0.165, (0, 0, 2.13), (1, 1.08, 0.5), bone="head", mat="acero", segs=24)
box("yelmo_cresta", (0.03, 0.05, 0.3), (0, 0.18, 1.99), bone="head", mat="oro", bevel=0.006)
box("visera_ranura", (0.3, 0.04, 0.035), (0, 0.178, 1.99), bone="head", mat="oscuro", bevel=0.004)
box("yelmo_borde", (0.34, 0.36, 0.03), (0, 0, 1.81), bone="head", mat="oro", bevel=0.006)
for s in (-1, 1):
    # "Lentes": rendijas redondas que brillan
    cyl("lente_aro_%d" % s, 0.042, 0.025, (s * 0.065, 0.178, 1.99), (90, 0, 0), bone="head", mat="oscuro", verts=16)
    cyl("ojos_%d" % s, 0.028, 0.02, (s * 0.065, 0.186, 1.99), (90, 0, 0), bone="head", mat="ojos", verts=14, bevel=0)
    for k in range(3):
        box("respiradero_%d_%d" % (s, k), (0.012, 0.025, 0.05), (s * (0.04 + k * 0.025), 0.183, 1.89), bone="head", mat="oscuro", bevel=0.002)
sphere("abolladura_yelmo", 0.04, (0.12, 0.13, 2.07), (1, 0.5, 1), bone="head", mat="oscuro", segs=10)
# Birrete torcido y gastado
cyl("birrete_base", 0.07, 0.05, (0, 0, 2.18), bone="head", mat="toga", verts=16)
box("birrete", (0.47, 0.47, 0.035), (0, 0, 2.205), (2, -1, 4), bone="head", mat="toga", bevel=0.006)
sphere("birrete_boton", 0.027, (0, 0, 2.23), bone="head", mat="oro", segs=10)
cyl("borla_cordon", 0.008, 0.2, (0.2, 0.2, 2.11), (0, -6, 0), bone="tassel", mat="oro", verts=6, bevel=0)
cyl("borla", 0.035, 0.08, (0.21, 0.2, 1.99), bone="tassel", mat="oro", verts=10, r2=0.015)

# ------------------------------------------------------------------ esqueleto (= articulaciones del código)
B = [
    ("pelvis", "", (0, 0, 0.95), (0, 0, 1.02)),
    ("spine", "pelvis", (0, 0, 1.02), (0, 0, 1.29)),
    ("chest", "spine", (0, 0, 1.29), (0, 0, 1.79)),
    ("head", "chest", (0, 0, 1.79), (0, 0, 2.2)),
    ("tassel", "head", (0.2, 0.2, 2.21), (0.2, 0.2, 2.0)),
    ("cape", "chest", (0, -0.3, 1.65), (0, -0.3, 0.6)),
]
for side, s in (("l", -1), ("r", 1)):
    B += [
        (side + "s", "chest", (s * 0.43, 0, 1.56), (s * 0.43, 0, 1.24)),
        (side + "e", side + "s", (s * 0.43, 0, 1.24), (s * 0.43, 0, 0.91)),
        (side + "h", "pelvis", (s * 0.15, 0, 0.89), (s * 0.15, 0, 0.46)),
        (side + "k", side + "h", (s * 0.15, 0, 0.46), (s * 0.15, 0, 0.0)),
    ]
bk.armature(B)
bk.finish("catedratico", tex_size=2048, bake=True, out_dir=OUT)
if PREVIEW:
    bk.render_preview(os.path.join(OUT, "preview_catedratico.png"), (1.6, 3.6, 1.8), (0, 0, 1.2))
    bk.render_preview(os.path.join(OUT, "preview_catedratico_atras.png"), (-2.0, -3.2, 2.0), (0, 0, 1.3))
    bk.render_preview(os.path.join(OUT, "preview_catedratico_cara.png"), (0.5, 1.2, 2.1), (0, 0, 1.9), size=(700, 700))
bk.export(os.path.join(OUT, "catedratico.glb"), actions=False)
print("LISTO", OUT)
