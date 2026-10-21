"""Jefe final: "El Rector Eterno" (boss_final/boss_rector.gd).
Hombre calvo con barba de candado, del tamaño de una persona normal. Dos modelos con el
mismo esqueleto:
  rector.glb             fase 1: toga académica negra muy vieja (polvo, polillas, dobladillo
                         deshilachado), ribetes dorados deslustrados, estola y capucha caída.
  rector_sin_toga.glb    fase 2: se arranca la toga; debajo, un traje táctico oscuro con
                         peto rayado y circuitos rojos (brillan), brazales de cuero y
                         rodilleras.
La espada, la vaina, el revólver y su funda siguen siendo los del código (aparecen y
desaparecen en la pelea). Materiales que anima el código: "ojos" y "circuito".

Uso:  blender -b --python arte/blender/jefe_rector.py -- <carpeta_salida> [preview] [toga|sin_toga]
"""
import sys
import os
import math
import random

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, sphere, panel, bolts, cable, label, cloth, blob, limb

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/jefes")
PREVIEW = "preview" in argv
ONLY = [a for a in argv[1:] if a != "preview"]
os.makedirs(OUT, exist_ok=True)


def G(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return (x, -z, y)


def S(x, y, z):
    """Tamaño de caja de Godot (ancho, alto, fondo) -> Blender (ancho, fondo, alto)."""
    return (x, z, y)


MATS = {
    "toga": dict(base=(0.012, 0.012, 0.018), rough=0.85, rust=0.15, wear=0.75, dirt=1.2, bare=(0.09, 0.085, 0.08), scratches=False, soot=0.5, streaks=0.35),
    "oro": dict(base=(0.38, 0.27, 0.07), metal=1.0, rough=0.4, rust=0.45, wear=0.6, dirt=1.0, bare=(0.6, 0.48, 0.22), soot=0.5, streaks=0.4),
    "estola": dict(base=(0.08, 0.008, 0.012), rough=0.8, rust=0.2, wear=0.7, dirt=1.0, bare=(0.25, 0.1, 0.1), scratches=False, soot=0.4),
    "tela": dict(base=(0.025, 0.025, 0.03), rough=0.85, rust=0.15, wear=0.7, dirt=1.1, bare=(0.12, 0.12, 0.12), scratches=False, soot=0.5),
    "armadura": dict(base=(0.09, 0.09, 0.1), metal=0.85, rough=0.38, rust=0.7, wear=0.75, dirt=0.9, bare=(0.55, 0.55, 0.58), streaks=0.6, soot=0.5),
    "cuero": dict(base=(0.07, 0.04, 0.02), rough=0.65, rust=0.0, wear=0.9, dirt=1.0, bare=(0.2, 0.13, 0.08), soot=0.3),
    "piel": dict(skin=True, base=(0.36, 0.24, 0.18), veins=0.2, vein_col=(0.2, 0.1, 0.1), blotch=0.5, blotch_col=(0.26, 0.14, 0.1), rough=0.45, wet=0.15, dirt=0.4),
    "barba": dict(base=(0.03, 0.025, 0.022), rough=0.9, rust=0.0, wear=0.3, dirt=0.4, bare=(0.12, 0.11, 0.1), scratches=False),
    "metal": dict(base=(0.42, 0.42, 0.44), metal=1.0, rough=0.35, rust=0.7, wear=0.5, dirt=0.7, bare=(0.75, 0.75, 0.77)),
    "ojos": {"emit": (1.0, 0.85, 0.6), "strength": 3.0},
    "circuito": {"emit": (1.0, 0.15, 0.08), "strength": 2.0},
}


def build(robed):
    bk.reset(seed=505 if robed else 506)
    bk.define_materials(MATS)
    rng = random.Random(5)

    # -------------------------------------------------------------- cuerpo (debajo de la toga)
    blob("cadera", 0.25, G(0, 1.12, 0), (1.0, 0.6, 0.55), bone="pelvis", mat="tela", lumps=0.03)
    cyl("cinturon", 0.25, 0.07, G(0, 1.22, 0), bone="pelvis", mat="cuero", verts=24, r2=0.25)
    box("hebilla", (0.09, 0.025, 0.07), G(0, 1.22, -0.17), bone="pelvis", mat="oro", bevel=0.006)
    # Torso en V: pecho ancho, cintura angosta
    box("abdomen", S(0.4, 0.34, 0.26), G(0, 1.43, 0), bone="spine", mat="tela", taper=(1.12, 1.05), bevel=0.07, segs=3)
    box("torax", S(0.46, 0.44, 0.3), G(0, 1.82, 0.01), bone="chest", mat="tela", taper=(1.2, 1.05), bevel=0.09, segs=3)
    # Peto con circuitos rojos (se ve en la fase 2)
    panel("peto", (0.46, 0.06, 0.36), G(0, 1.84, -0.15), (0, 0, 0), bone="chest", mat="armadura", taper=(1.1, 1.0), bevel=0.04)
    panel("peto_bajo", (0.38, 0.05, 0.12), G(0, 1.62, -0.14), (-8, 0, 0), bone="chest", mat="armadura", bevel=0.03)
    panel("placa_abdomen", (0.34, 0.05, 0.26), G(0, 1.43, -0.135), (0, 0, 0), bone="spine", mat="armadura", bevel=0.02)
    panel("espaldar", (0.46, 0.05, 0.36), G(0, 1.84, 0.17), (0, 0, 180), bone="chest", mat="armadura", taper=(1.1, 1.0), bevel=0.04)
    for k in range(3):
        box("circuito_abdomen_%d" % k, (0.018, 0.012, 0.22), G(-0.1 + k * 0.1, 1.43, -0.163), bone="spine", mat="circuito", bevel=0.002)
    box("circuito_pecho_h", (0.3, 0.012, 0.018), G(0, 1.94, -0.183), bone="chest", mat="circuito", bevel=0.002)
    for s in (-1, 1):
        box("circuito_pecho_%d" % s, (0.018, 0.012, 0.28), G(s * 0.15, 1.82, -0.183), bone="chest", mat="circuito", bevel=0.002)
    for i in range(4):
        box("rayon_peto_%d" % i, (0.12, 0.006, 0.006), G(rng.uniform(-0.2, 0.2), rng.uniform(1.7, 1.95), -0.181), (0, rng.uniform(-40, 40), 0), bone="chest", mat="metal", bevel=0)
    # Piernas
    for side, s in (("l", -1), ("r", 1)):
        limb("muslo_" + side, [G(s * 0.13, 1.06, 0), G(s * 0.13, 0.8, -0.01), G(s * 0.13, 0.55, 0)], [0.1, 0.09, 0.075], bone="hip_" + side, mat="tela", lumps=0.05)
        limb("pierna_" + side, [G(s * 0.13, 0.55, 0), G(s * 0.13, 0.3, 0.01), G(s * 0.13, 0.08, 0)], [0.075, 0.07, 0.065], bone="kn_" + side, mat="tela", lumps=0.05)
        sphere("rodillera_" + side, 0.07, G(s * 0.13, 0.54, -0.06), (1.0, 0.7, 1.0), bone="kn_" + side, mat="armadura", segs=14)
        cyl("bota_cana_" + side, 0.085, 0.24, G(s * 0.13, 0.16, 0), bone="kn_" + side, mat="cuero", verts=16, r2=0.08)
        box("bota_" + side, S(0.15, 0.09, 0.3), G(s * 0.13, 0.03, -0.06), bone="an_" + side, mat="cuero", bevel=0.03)
    # Brazos
    for side, s in (("l", -1), ("r", 1)):
        sh, el, wr = "sh_" + side, "el_" + side, "wr_" + side
        panel("hombrera_" + side, (0.16, 0.2, 0.05), G(s * 0.42, 2.0, 0), (0, s * 28, 0), bone=sh, mat="armadura", taper=(1.0, 0.9), bevel=0.02)
        panel("hombrera2_" + side, (0.13, 0.18, 0.04), G(s * 0.47, 1.93, 0), (0, s * 50, 0), bone=sh, mat="armadura", bevel=0.015)
        limb("brazo_" + side, [G(s * 0.38, 1.96, 0), G(s * 0.38, 1.8, 0), G(s * 0.38, 1.63, 0)], [0.07, 0.065, 0.06], bone=sh, mat="tela", lumps=0.05)
        box("circuito_brazo_" + side, (0.012, 0.012, 0.28), G(s * 0.447, 1.8, 0), bone=sh, mat="circuito", bevel=0.002)
        limb("antebrazo_" + side, [G(s * 0.38, 1.62, 0), G(s * 0.38, 1.45, -0.005), G(s * 0.38, 1.29, 0)], [0.06, 0.058, 0.05], bone=el, mat="cuero", lumps=0.05)
        for k in range(3):
            cyl("correa_%s_%d" % (side, k), 0.063, 0.02, G(s * 0.38, 1.55 - k * 0.09, 0), bone=el, mat="metal", verts=14)
        box("mano_" + side, S(0.09, 0.11, 0.1), G(s * 0.38, 1.23, 0), bone=wr, mat="piel", bevel=0.025)
        for f in range(4):
            limb("dedo_%s_%d" % (side, f), [G(s * 0.38 + (f - 1.5) * 0.02, 1.18, -0.02), G(s * 0.38 + (f - 1.5) * 0.02, 1.12, -0.035)], [0.011, 0.009], bone=wr, mat="piel", verts=6)

    # -------------------------------------------------------------- cabeza: calvo con barba de candado
    limb("cuello", [G(0, 2.06, 0), G(0, 2.14, -0.005), G(0, 2.24, 0)], [0.075, 0.07, 0.07], bone="neck", mat="piel")
    blob("craneo", 0.15, G(0, 2.38, 0.005), (0.92, 1.08, 1.0), bone="head", mat="piel", lumps=0.03, seed=3)
    blob("quijada", 0.1, G(0, 2.27, -0.04), (1.15, 0.7, 1.0), bone="head", mat="piel", lumps=0.04, seed=4)
    blob("nariz", 0.03, G(0, 2.36, -0.15), (0.7, 1.0, 1.15), bone="head", mat="piel", lumps=0.08)
    for s in (-1, 1):
        blob("oreja_%d" % s, 0.035, G(s * 0.14, 2.36, 0.0), (0.4, 1.3, 1.0), bone="head", mat="piel", lumps=0.1)
        box("ceja_%d" % s, (0.075, 0.02, 0.018), G(s * 0.058, 2.425, -0.138), (0, s * 10, 0), bone="head", mat="barba", bevel=0.006)
        sphere("ojos_%d" % s, 0.012, G(s * 0.055, 2.395, -0.135), bone="head", mat="ojos", segs=10)
        box("arruga_%d" % s, (0.04, 0.004, 0.004), G(s * 0.1, 2.39, -0.115), (0, s * 25, 0), bone="head", mat="barba", bevel=0)
    # Barba de candado: bigote + piocha unidos por las comisuras
    blob("bigote", 0.05, G(0, 2.31, -0.14), (1.3, 0.35, 0.45), bone="head", mat="barba", lumps=0.15)
    for s in (-1, 1):
        limb("comisura_%d" % s, [G(s * 0.055, 2.31, -0.135), G(s * 0.057, 2.26, -0.13), G(s * 0.045, 2.22, -0.12)], [0.012, 0.012, 0.012], bone="head", mat="barba", verts=6)
    blob("piocha", 0.05, G(0, 2.21, -0.11), (1.0, 0.9, 0.8), bone="head", mat="barba", lumps=0.15)
    box("boca", (0.055, 0.008, 0.01), G(0, 2.29, -0.145), bone="head", mat="estola", bevel=0.003)

    if robed:
        # ---------------------------------------------------------- toga académica
        blob("toga_pecho", 0.37, G(0, 1.84, 0), (1.0, 0.65, 0.6), bone="chest", mat="toga", lumps=0.03, seed=9)
        blob("toga_vientre", 0.3, G(0, 1.46, 0), (1.0, 0.72, 0.65), bone="spine", mat="toga", lumps=0.03, seed=10)
        cyl("toga_cuello", 0.24, 0.12, G(0, 2.04, 0.0), bone="chest", mat="toga", verts=24, r2=0.17)
        for s in (-1, 1):
            box("ribete_%d" % s, S(0.06, 0.55, 0.02), G(s * 0.1, 1.82, -0.215), bone="chest", mat="oro", bevel=0.006)
            box("ribete_v_%d" % s, S(0.06, 0.42, 0.02), G(s * 0.1, 1.46, -0.2), bone="spine", mat="oro", bevel=0.006)
        # Estola roja con insignia y capucha caída a la espalda
        for s in (-1, 1):
            box("estola_%d" % s, S(0.07, 0.7, 0.02), G(s * 0.16, 1.75, -0.22), (0, 0, s * -6), bone="chest", mat="estola", bevel=0.008)
        cyl("insignia", 0.045, 0.012, G(-0.16, 1.95, -0.235), (90, 0, 0), bone="chest", mat="oro", verts=16)
        blob("capucha", 0.18, G(0, 2.0, 0.25), (1.3, 0.8, 0.6), bone="chest", mat="toga", lumps=0.1, seed=11)
        cloth("capucha_cola", 0.3, 0.4, G(0, 1.95, 0.32), (0, 0, 180), bone="chest", mat="toga", nx=8, ny=8, tatter=0.3, seed=12)
        # Falda de la toga: paneles que siguen a cada pierna, dobladillo deshilachado
        cloth("falda_fi", 0.36, 1.05, G(-0.14, 1.18, -0.22), (0, 0, 8), bone="pelvis", mat="toga", nx=10, ny=14, tatter=0.15, holes=0.03, flare=0.12, bone2="hip_l", blend=0.6, seed=13)
        cloth("falda_fd", 0.36, 1.05, G(0.14, 1.18, -0.22), (0, 0, -8), bone="pelvis", mat="toga", nx=10, ny=14, tatter=0.15, holes=0.03, flare=0.12, bone2="hip_r", blend=0.6, seed=14)
        cloth("falda_atras", 0.66, 1.1, G(0, 1.2, 0.2), (0, 0, 180), bone="pelvis", mat="toga", nx=16, ny=14, tatter=0.18, holes=0.03, flare=0.16, seed=15)
        for s in (-1, 1):
            cloth("falda_lado_%d" % s, 0.4, 1.05, G(s * 0.27, 1.18, 0.0), (0, 0, s * -90), bone="pelvis", mat="toga", nx=10, ny=14, tatter=0.18, holes=0.03, flare=0.14, bone2="hip_l" if s < 0 else "hip_r", blend=0.4, seed=16 + s)
        # Mangas acampanadas con puño dorado
        for side, s in (("l", -1), ("r", 1)):
            cyl("manga_sup_" + side, 0.1, 0.4, G(s * 0.38, 1.8, 0), bone="sh_" + side, mat="toga", verts=18, r2=0.13)
            cyl("manga_" + side, 0.24, 0.36, G(s * 0.38, 1.47, 0), bone="el_" + side, mat="toga", verts=22, r2=0.13)
            cyl("puno_oro_" + side, 0.25, 0.04, G(s * 0.38, 1.28, 0), bone="el_" + side, mat="oro", verts=22, r2=0.245)
            cloth("manga_jiron_" + side, 0.3, 0.12, G(s * 0.38, 1.3, -0.22), (0, 0, 0), bone="el_" + side, mat="toga", nx=8, ny=3, tatter=0.6, seed=20 + s)

    # -------------------------------------------------------------- esqueleto (= articulaciones)
    B = [
        ("pelvis", "", G(0, 1.12, 0), G(0, 1.26, 0)),
        ("spine", "pelvis", G(0, 1.26, 0), G(0, 1.62, 0)),
        ("chest", "spine", G(0, 1.62, 0), G(0, 2.08, 0)),
        ("neck", "chest", G(0, 2.08, 0), G(0, 2.22, 0)),
        ("head", "neck", G(0, 2.22, 0), G(0, 2.55, 0)),
    ]
    for side, s in (("l", -1), ("r", 1)):
        B += [
            ("hip_" + side, "pelvis", G(s * 0.13, 1.04, 0), G(s * 0.13, 0.54, 0)),
            ("kn_" + side, "hip_" + side, G(s * 0.13, 0.54, 0), G(s * 0.13, 0.06, 0)),
            ("an_" + side, "kn_" + side, G(s * 0.13, 0.06, 0), G(s * 0.13, 0.0, -0.2)),
            ("sh_" + side, "chest", G(s * 0.38, 1.98, 0), G(s * 0.38, 1.62, 0)),
            ("el_" + side, "sh_" + side, G(s * 0.38, 1.62, 0), G(s * 0.38, 1.28, 0)),
            ("wr_" + side, "el_" + side, G(s * 0.38, 1.28, 0), G(s * 0.38, 1.15, 0)),
        ]
    bk.armature(B)
    name = "rector" if robed else "rector_sin_toga"
    bk.finish(name, tex_size=2048, bake=True, out_dir=OUT)
    if PREVIEW:
        bk.render_preview(os.path.join(OUT, "preview_%s.png" % name), (1.0, 3.0, 1.4), (0, 0, 1.1))
        bk.render_preview(os.path.join(OUT, "preview_%s_cara.png" % name), (0.35, 0.9, 2.4), (0, 0, 2.33), size=(700, 700))
    bk.export(os.path.join(OUT, name + ".glb"), actions=False)


for nm, robed in (("toga", True), ("sin_toga", False)):
    if not ONLY or nm in ONLY:
        build(robed)
print("LISTO", OUT)
