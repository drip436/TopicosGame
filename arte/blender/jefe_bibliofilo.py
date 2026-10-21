"""Segundo jefe: "Doctor Euclides Barrabás, el Bibliófilo Demente" (boss_bibliotecario).
Profesor flaco y altísimo (3.6 m) con panza: camisa de franela a cuadros rota, manchada
y desfajada, mangas arremangadas con tinta en los brazos, jeans gastados con parches y
el dobladillo deshilachado, zapatos con la suela despegada, barba canosa larga, pelo
alborotado, lentes redondos (uno estrellado) y lápices en la bolsa de la camisa.

Igual que los demás jefes: cada pieza va pegada al hueso que se llama como la
articulación del código y boss_skin.gd la hace seguir (no hacen falta animaciones).
Las posiciones se escriben en coordenadas de Godot con G(x, y, z) (el jefe mira a −Z).

Uso:  blender -b --python arte/blender/jefe_bibliofilo.py -- <carpeta_salida> [preview]
"""
import sys
import os
import math
import random

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, sphere, panel, cable, label, cloth, blob, limb

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/jefes")
PREVIEW = "preview" in argv
os.makedirs(OUT, exist_ok=True)


def G(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return (x, -z, y)


bk.reset(seed=202)
PLAID = ((0.15, 0.014, 0.011), (0.018, 0.013, 0.012), (0.3, 0.27, 0.19), 5.0)
bk.define_materials({
    "franela": dict(base=(0.15, 0.014, 0.011), rough=0.92, rust=0.45, wear=0.55, dirt=1.4, bare=(0.2, 0.17, 0.12), scratches=False, streaks=0.95, soot=0.8, plaid=PLAID),
    "mezclilla": dict(base=(0.03, 0.055, 0.12), rough=0.92, rust=0.2, wear=0.95, dirt=1.2, bare=(0.3, 0.34, 0.4), scratches=False, soot=0.35),
    "parche": dict(base=(0.09, 0.12, 0.2), rough=0.9, rust=0.1, wear=0.6, dirt=0.9, bare=(0.3, 0.32, 0.36), scratches=False),
    "cuero": dict(base=(0.07, 0.04, 0.02), rough=0.65, rust=0.0, wear=0.95, dirt=1.0, bare=(0.2, 0.13, 0.08), soot=0.3),
    "suela": dict(base=(0.03, 0.025, 0.02), rough=0.9, rust=0.0, wear=0.4, dirt=1.2, bare=(0.12, 0.1, 0.08), scratches=False),
    "piel": dict(skin=True, base=(0.33, 0.21, 0.16), veins=0.3, vein_col=(0.14, 0.07, 0.09), blotch=0.65, blotch_col=(0.18, 0.09, 0.05), rough=0.6, wet=0.12, dirt=0.5),
    "pelo": dict(base=(0.3, 0.29, 0.27), rough=0.9, rust=0.0, wear=0.3, dirt=0.8, bare=(0.45, 0.44, 0.41), scratches=False, soot=0.4),
    "unas": dict(base=(0.18, 0.15, 0.1), rough=0.5, rust=0.0, wear=0.3, dirt=1.0, bare=(0.3, 0.27, 0.2), scratches=False),
    "marco": dict(base=(0.04, 0.04, 0.04), metal=0.6, rough=0.35, rust=0.4, wear=0.6, dirt=0.5, bare=(0.4, 0.4, 0.4)),
    "vidrio": dict(base=(0.04, 0.05, 0.05), metal=0.6, rough=0.06, rust=0.0, wear=0.2, dirt=0.5, bare=(0.3, 0.3, 0.3)),
    "oro": dict(base=(0.5, 0.36, 0.1), metal=1.0, rough=0.3, rust=0.3, wear=0.5, dirt=0.6, bare=(0.7, 0.55, 0.25)),
    "lapiz": dict(base=(0.6, 0.42, 0.05), rough=0.6, rust=0.0, wear=0.8, dirt=0.6, bare=(0.45, 0.3, 0.15)),
    "papel": dict(base=(0.55, 0.52, 0.42), rough=0.9, rust=0.4, wear=0.3, dirt=1.0, bare=(0.3, 0.27, 0.2), scratches=False, streaks=0.6),
    "tinta": dict(base=(0.02, 0.03, 0.08), rough=0.4, rust=0.0, wear=0.1, dirt=0.2, scratches=False),
    "ojos": {"emit": (1.0, 0.85, 0.5), "strength": 4.0},
})
rng = random.Random(9)

# ------------------------------------------------------------------ cadera y piernas
blob("cadera", 0.24, G(0, 1.94, 0), (0.95, 0.68, 0.55), bone="pelvis", mat="mezclilla", lumps=0.05)
cyl("cinturon", 0.23, 0.07, G(0, 2.05, 0), bone="pelvis", mat="cuero", verts=24, r2=0.23)
box("hebilla", (0.09, 0.025, 0.065), G(0, 2.05, -0.17), bone="pelvis", mat="oro", bevel=0.006)
# Llavero y hojas dobladas en la bolsa trasera
cable("llavero", [G(0.18, 2.03, -0.05), G(0.22, 1.95, -0.06), G(0.2, 1.88, -0.02)], 0.006, bone="pelvis", mat="oro", sag=0.02)
box("hojas_bolsa", (0.12, 0.02, 0.14), G(-0.1, 1.94, 0.17), (0, 0, 8), bone="pelvis", mat="papel", bevel=0.004)
for side, s in (("l", -1), ("r", 1)):
    limb("muslo_" + side, [G(s * 0.13, 1.92, 0), G(s * 0.13, 1.4, -0.01), G(s * 0.13, 0.94, 0)], [0.11, 0.095, 0.085], bone="hip_" + side, mat="mezclilla", lumps=0.06)
    sphere("rodilla_" + side, 0.085, G(s * 0.13, 0.93, -0.01), bone="kn_" + side, mat="mezclilla", segs=14)
    limb("pierna_" + side, [G(s * 0.13, 0.93, 0), G(s * 0.13, 0.5, 0.01), G(s * 0.13, 0.1, 0)], [0.08, 0.075, 0.085], bone="kn_" + side, mat="mezclilla", lumps=0.06)
    # Dobladillo deshilachado
    cloth("dobladillo_" + side, 0.27, 0.07, G(s * 0.13, 0.13, -0.09), (0, 0, 0), bone="kn_" + side, mat="mezclilla", nx=10, ny=3, tatter=0.6, holes=0.0, seed=20 + s)
    # Zapato viejo: suela despegada en la punta
    box("zapato_" + side, (0.15, 0.32, 0.1), G(s * 0.13, 0.03, -0.1), bone="an_" + side, mat="cuero", bevel=0.035)
    box("suela_" + side, (0.155, 0.2, 0.025), G(s * 0.13, -0.02, -0.02), bone="an_" + side, mat="suela", bevel=0.006)
    box("suela_suelta_" + side, (0.155, 0.13, 0.022), G(s * 0.13, -0.025, -0.2), (-10 if side == "r" else -3, 0, 0), bone="an_" + side, mat="suela", bevel=0.006)
    cable("agujeta_" + side, [G(s * 0.13 - 0.04, 0.09, -0.12), G(s * 0.13 + 0.05, 0.06, -0.16), G(s * 0.13 + 0.07, 0.0, -0.13)], 0.005, bone="an_" + side, mat="pelo")
# Parches y rotos en el jean
panel("parche_rodilla", (0.12, 0.02, 0.13), G(0.13, 0.95, -0.085), (0, 0, 0), bone="kn_r", mat="parche", bevel=0.006)
box("roto_muslo", (0.09, 0.02, 0.05), G(-0.13, 1.35, -0.095), (0, 0, 10), bone="hip_l", mat="piel", bevel=0.01)

# ------------------------------------------------------------------ torso: panza y pecho angosto
blob("panza", 0.27, G(0, 2.32, -0.08), (1.0, 0.95, 1.0), bone="spine", mat="franela", lumps=0.04, segs=28)
blob("espalda", 0.22, G(0, 2.42, 0.04), (0.95, 1.2, 0.75), bone="spine", mat="franela", lumps=0.04)
blob("torso_medio", 0.24, G(0, 2.56, -0.03), (0.95, 0.8, 0.85), bone="spine", mat="franela", lumps=0.04)
blob("pecho", 0.27, G(0, 2.8, 0), (0.92, 1.15, 0.6), bone="chest", mat="franela", lumps=0.05, segs=28)
blob("hombros", 0.32, G(0, 2.98, 0), (1.0, 0.25, 0.42), bone="chest", mat="franela", lumps=0.05)
# Camisa desfajada colgando sobre el cinturón, rota y manchada
cloth("faldon_camisa", 0.5, 0.26, G(0, 2.16, -0.26), (6, 0, 0), bone="spine", mat="franela", nx=12, ny=5, tatter=0.45, holes=0.04, flare=0.05, seed=31)
cloth("faldon_atras", 0.46, 0.22, G(0, 2.18, 0.2), (0, 0, 180), bone="spine", mat="franela", nx=12, ny=5, tatter=0.5, holes=0.04, seed=32)
# Botones (falta uno) y bolsa con lápices
for k, y in enumerate((2.95, 2.78, 2.6, 2.4)):
    if k == 2:
        cable("hilo_boton", [G(0, y + 0.01, -0.33), G(0.015, y - 0.02, -0.34), G(0.005, y - 0.05, -0.33)], 0.003, bone="chest" if y > 2.55 else "spine", mat="papel")
        continue
    cyl("boton_%d" % k, 0.016, 0.01, G(0, y, -0.33 if y < 2.55 else -0.155), (90, 0, 0), bone="chest" if y > 2.55 else "spine", mat="unas", verts=10)
panel("bolsa_camisa", (0.12, 0.02, 0.13), G(-0.12, 2.85, -0.145), (0, 0, 0), bone="chest", mat="franela", bevel=0.006)
for k in range(3):
    cyl("lapiz_%d" % k, 0.008, 0.17, G(-0.15 + k * 0.025, 2.93, -0.15), (rng.uniform(-8, 8), rng.uniform(-10, 10), 0), bone="chest", mat="lapiz", verts=6)
box("mancha_tinta", (0.06, 0.01, 0.05), G(-0.12, 2.8, -0.16), bone="chest", mat="tinta", bevel=0.01)
cyl("cuello_camisa", 0.1, 0.08, G(0, 3.07, 0), bone="chest", mat="franela", verts=16, r2=0.09)
for s in (-1, 1):
    box("solapa_%d" % s, (0.1, 0.02, 0.08), G(s * 0.05, 3.05, -0.09), (0, s * 30, s * 45), bone="chest", mat="franela", bevel=0.006)

# ------------------------------------------------------------------ cabeza
limb("cuello", [G(0, 3.04, 0), G(0, 3.14, -0.01), G(0, 3.24, 0)], [0.06, 0.055, 0.06], bone="neck", mat="piel")
blob("craneo", 0.19, G(0, 3.39, 0), (0.95, 1.15, 1.0), bone="head", mat="piel", lumps=0.04, seed=4)
blob("nariz", 0.045, G(0, 3.35, -0.2), (0.7, 1.0, 1.1), bone="head", mat="piel", lumps=0.1, seed=5)
for s in (-1, 1):
    blob("oreja_%d" % s, 0.045, G(s * 0.18, 3.38, 0.0), (0.4, 1.3, 0.9), bone="head", mat="piel", lumps=0.1)
    sphere("blanco_ojo_%d" % s, 0.032, G(s * 0.072, 3.42, -0.16), bone="head", mat="papel", segs=12)
    sphere("ojos_%d" % s, 0.014, G(s * 0.072, 3.42, -0.212), bone="head", mat="ojos", segs=10)
    # Lentes redondos (el izquierdo estrellado)
    cyl("lente_aro_%d" % s, 0.055, 0.012, G(s * 0.075, 3.42, -0.2), (90, 0, 0), bone="head", mat="marco", verts=20)
    cyl("lente_%d" % s, 0.048, 0.006, G(s * 0.075, 3.42, -0.205), (90, 0, 0), bone="head", mat="vidrio", verts=20)
    box("patilla_%d" % s, (0.01, 0.2, 0.012), G(s * 0.17, 3.43, -0.1), bone="head", mat="marco", bevel=0.002)
    box("ceja_%d" % s, (0.11, 0.035, 0.04), G(s * 0.08, 3.49, -0.18), (0, s * 18, 0), bone="head", mat="pelo", bevel=0.012)
for k in range(3):
    box("grieta_lente_%d" % k, (0.06, 0.003, 0.003), G(-0.075, 3.42, -0.21), (0, k * 60 + 10, 0), bone="head", mat="papel", bevel=0)
box("puente", (0.04, 0.012, 0.012), G(0, 3.425, -0.205), bone="head", mat="marco", bevel=0.002)
# Pelo alborotado (mechones) y calva en la coronilla
for i in range(30):
    a = rng.uniform(-math.pi * 0.95, math.pi * 0.95)
    p = (math.sin(a) * 0.17, rng.uniform(3.45, 3.56), math.cos(a) * 0.15 + 0.04)
    d = (math.sin(a) * 0.9, rng.uniform(0.2, 0.9), math.cos(a) * 0.9 + 0.3)
    L = rng.uniform(0.12, 0.24)
    limb("mechon_%d" % i, [G(*p), G(p[0] + d[0] * L * 0.5, p[1] + d[1] * L * 0.5, p[2] + d[2] * L * 0.5), G(p[0] + d[0] * L, p[1] + d[1] * L - 0.03, p[2] + d[2] * L)],
         [0.022, 0.014, 0.003], bone="head", mat="pelo", verts=6)
# Barba canosa larga y bigote
blob("barba", 0.16, G(0, 3.16, -0.12), (1.05, 1.3, 0.85), bone="head", mat="pelo", lumps=0.18, seed=6)
limb("barba_larga", [G(0, 3.1, -0.15), G(0.01, 2.95, -0.19), G(-0.02, 2.82, -0.17), G(0.02, 2.72, -0.16)], [0.12, 0.09, 0.05, 0.01], bone="head", mat="pelo", lumps=0.3, verts=10)
blob("bigote", 0.06, G(0, 3.29, -0.2), (1.8, 0.5, 0.6), bone="head", mat="pelo", lumps=0.2)

# ------------------------------------------------------------------ brazos larguísimos
for side, s in (("l", -1), ("r", 1)):
    sh, el, wr = "sh_" + side, "el_" + side, "wr_" + side
    sphere("hombro_" + side, 0.095, G(s * 0.3, 2.99, 0), bone=sh, mat="franela", segs=14)
    limb("manga_" + side, [G(s * 0.3, 2.98, 0), G(s * 0.3, 2.62, 0.0), G(s * 0.3, 2.3, 0)], [0.08, 0.07, 0.075], bone=sh, mat="franela", lumps=0.08)
    cyl("arremangado_" + side, 0.085, 0.1, G(s * 0.3, 2.25, 0), bone=el, mat="franela", verts=14, r2=0.08)
    limb("antebrazo_" + side, [G(s * 0.3, 2.22, 0), G(s * 0.3, 1.9, -0.005), G(s * 0.3, 1.57, 0)], [0.05, 0.045, 0.035], bone=el, mat="piel", lumps=0.08)
    box("mano_" + side, (0.09, 0.05, 0.15), G(s * 0.3, 1.5, 0), bone=wr, mat="piel", bevel=0.02)
    for f in range(4):
        fx = s * 0.3 + (f - 1.5) * 0.02
        limb("dedo_%s_%d" % (side, f), [G(fx, 1.44, -0.01), G(fx, 1.35, -0.03), G(fx, 1.27, -0.05)], [0.011, 0.01, 0.008], bone=wr, mat="piel", verts=6)
        cyl("una_%s_%d" % (side, f), 0.008, 0.05, G(fx, 1.24, -0.06), (-35, 0, 0), bone=wr, mat="unas", verts=6, r2=0.002)
    limb("pulgar_" + side, [G(s * 0.3 - s * 0.04, 1.5, -0.03), G(s * 0.3 - s * 0.06, 1.42, -0.06)], [0.012, 0.009], bone=wr, mat="piel", verts=6)
box("tinta_brazo", (0.04, 0.05, 0.12), G(0.33, 1.85, -0.03), bone="el_r", mat="tinta", bevel=0.01)
# Manga izquierda rota en el hombro
cloth("manga_rota", 0.16, 0.14, G(-0.38, 2.95, -0.02), (0, 0, 90), bone="sh_l", mat="franela", nx=6, ny=5, tatter=0.6, seed=40)

# ------------------------------------------------------------------ esqueleto
B = [
    ("pelvis", "", G(0, 1.95, 0), G(0, 2.05, 0)),
    ("spine", "pelvis", G(0, 2.05, 0), G(0, 2.55, 0)),
    ("chest", "spine", G(0, 2.55, 0), G(0, 3.07, 0)),
    ("neck", "chest", G(0, 3.07, 0), G(0, 3.22, 0)),
    ("head", "neck", G(0, 3.22, 0), G(0, 3.6, 0)),
]
for side, s in (("l", -1), ("r", 1)):
    B += [
        ("hip_" + side, "pelvis", G(s * 0.13, 1.87, 0), G(s * 0.13, 0.93, 0)),
        ("kn_" + side, "hip_" + side, G(s * 0.13, 0.93, 0), G(s * 0.13, 0.03, 0)),
        ("an_" + side, "kn_" + side, G(s * 0.13, 0.03, 0), G(s * 0.13, 0.0, -0.25)),
        ("sh_" + side, "chest", G(s * 0.3, 2.99, 0), G(s * 0.3, 2.27, 0)),
        ("el_" + side, "sh_" + side, G(s * 0.3, 2.27, 0), G(s * 0.3, 1.57, 0)),
        ("wr_" + side, "el_" + side, G(s * 0.3, 1.57, 0), G(s * 0.3, 1.26, 0)),
    ]
bk.armature(B)
bk.finish("bibliofilo", tex_size=2048, bake=True, out_dir=OUT)
if PREVIEW:
    bk.render_preview(os.path.join(OUT, "preview_bibliofilo.png"), (1.8, 5.5, 2.6), (0, 0, 1.9))
    bk.render_preview(os.path.join(OUT, "preview_bibliofilo_atras.png"), (-2.2, -4.8, 2.8), (0, 0, 2.0))
    bk.render_preview(os.path.join(OUT, "preview_bibliofilo_cara.png"), (0.5, 1.4, 3.45), (0, 0, 3.3), size=(700, 700))
bk.export(os.path.join(OUT, "bibliofilo.glb"), actions=False)
print("LISTO", OUT)
