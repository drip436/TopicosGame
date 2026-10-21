"""Cuarto jefe: "Dr. Viktor Kessler, el Paciente Cero" (boss_laboratorio/boss_doctor.gd).
Dos modelos con el mismo esqueleto:
  kessler.glb           el científico: viejo enorme y musculoso (estilo Conquest), pelo
                        blanco peinado hacia atrás, cara llena de cicatrices, un ojo
                        muerto que brilla, traje negro gastado y bata de laboratorio rota,
                        quemada por químicos y manchada; cinturón con frascos de suero.
  kessler_mutante.glb   después de inyectarse (fase 2, el código lo escala al doble): piel
                        verde enferma, carne que revienta el traje, espinas de hueso en
                        hombros y espalda, pústulas, brazo izquierdo deforme con garras,
                        tumor en la cabeza, mandíbula desencajada y la bata en jirones.
El tubo radiactivo y la pistola láser van en ambos. Materiales que anima el código:
"ojos" (ojo muerto) y "tubo" (brillo del tubo radiactivo).

Uso:  blender -b --python arte/blender/jefe_kessler.py -- <carpeta_salida> [preview] [humano|mutante]
"""
import sys
import os
import math
import random

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, sphere, panel, bolts, cable, label, cloth, blob, limb
from mathutils import Vector

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
    "traje": dict(base=(0.018, 0.018, 0.02), rough=0.75, rust=0.2, wear=0.8, dirt=1.1, bare=(0.1, 0.1, 0.1), scratches=False, soot=0.6, streaks=0.4),
    "bata": dict(base=(0.34, 0.34, 0.3), rough=0.9, rust=0.7, wear=0.5, dirt=1.6, bare=(0.22, 0.2, 0.15), scratches=False, soot=0.75, streaks=1.0),
    "camisa": dict(base=(0.35, 0.36, 0.33), rough=0.9, rust=0.4, wear=0.4, dirt=1.1, bare=(0.2, 0.19, 0.16), scratches=False, soot=0.4),
    "corbata": dict(base=(0.12, 0.01, 0.015), rough=0.7, rust=0.1, wear=0.6, dirt=0.8, bare=(0.2, 0.08, 0.08), scratches=False),
    "cuero": dict(base=(0.03, 0.022, 0.016), rough=0.55, rust=0.0, wear=0.9, dirt=1.1, bare=(0.15, 0.11, 0.08), soot=0.3),
    "piel": dict(skin=True, base=(0.36, 0.25, 0.2), veins=0.3, vein_col=(0.2, 0.08, 0.1), blotch=0.6, blotch_col=(0.28, 0.12, 0.1), rough=0.55, wet=0.15, dirt=0.5),
    "cicatriz": dict(skin=True, base=(0.3, 0.12, 0.11), veins=0.2, vein_col=(0.15, 0.04, 0.05), blotch=0.5, blotch_col=(0.2, 0.06, 0.06), rough=0.4, wet=0.3, dirt=0.3),
    "pelo": dict(base=(0.42, 0.42, 0.4), rough=0.6, rust=0.0, wear=0.3, dirt=0.5, bare=(0.8, 0.8, 0.78), scratches=False),
    "metal": dict(base=(0.42, 0.43, 0.45), metal=1.0, rough=0.35, rust=0.9, wear=0.5, dirt=0.7, bare=(0.75, 0.75, 0.77), streaks=0.6),
    "metal_oscuro": dict(base=(0.05, 0.05, 0.055), metal=0.7, rough=0.45, rust=0.8, wear=0.7, dirt=0.7, bare=(0.4, 0.4, 0.42), streaks=0.4),
    "peligro": dict(base=(0.75, 0.6, 0.05), rough=0.55, rust=0.35, wear=0.9, dirt=0.6, bare=(0.18, 0.18, 0.18)),
    "vidrio": dict(base=(0.3, 0.35, 0.32), metal=0.3, rough=0.1, rust=0.0, wear=0.3, dirt=0.6, bare=(0.6, 0.6, 0.6)),
    "piel_mut": dict(skin=True, base=(0.12, 0.15, 0.08), veins=0.9, vein_col=(0.03, 0.06, 0.015), blotch=0.9, blotch_col=(0.14, 0.04, 0.05), rough=0.45, wet=0.5, dirt=0.8, scale=1.2),
    "carne": dict(skin=True, base=(0.12, 0.02, 0.018), veins=0.6, vein_col=(0.04, 0.005, 0.01), blotch=0.7, blotch_col=(0.18, 0.08, 0.03), rough=0.3, wet=0.9, dirt=0.4, scale=2.0),
    "hueso": dict(base=(0.45, 0.42, 0.32), rough=0.6, rust=0.15, wear=0.3, dirt=1.0, bare=(0.62, 0.6, 0.5), scratches=False, soot=0.4, streaks=0.5),
    "pus": {"emit": (0.5, 1.0, 0.18), "strength": 1.6},
    "suero": {"emit": (0.4, 1.0, 0.2), "strength": 3.0},
    "tubo": {"emit": (0.4, 1.0, 0.2), "strength": 3.0},
    "boca": {"emit": (0.4, 1.0, 0.15), "strength": 2.0},
    "ojos": {"emit": (0.85, 0.95, 0.85), "strength": 4.0},
}


def build(mutant):
    bk.reset(seed=404 if not mutant else 405)
    bk.define_materials(MATS)
    rng = random.Random(4 if not mutant else 5)
    skin = "piel_mut" if mutant else "piel"

    # -------------------------------------------------------------- cadera y piernas
    blob("cadera", 0.33, G(0, 1.28, 0), (1.0, 0.55, 0.65), bone="pelvis", mat="traje", lumps=0.03)
    cyl("cinturon", 0.33, 0.07, G(0, 1.4, 0), bone="pelvis", mat="cuero", verts=28, r2=0.33)
    box("hebilla", (0.09, 0.03, 0.07), G(0, 1.4, -0.21), bone="pelvis", mat="metal", bevel=0.006)
    for k in range(4):
        x = -0.28 + k * 0.08
        box("frasco_porta_%d" % k, (0.06, 0.05, 0.12), G(x, 1.36, -0.18 + abs(x) * 0.3), bone="pelvis", mat="cuero", bevel=0.01)
        if not (mutant and k % 2):
            cyl("frasco_%d" % k, 0.022, 0.12, G(x, 1.43, -0.19 + abs(x) * 0.3), bone="pelvis", mat="suero", verts=10)
    for side, s in (("l", -1), ("r", 1)):
        limb("muslo_" + side, [G(s * 0.2, 1.22, 0), G(s * 0.2, 0.9, -0.01), G(s * 0.2, 0.6, 0)], [0.17, 0.155, 0.12], bone="hip_" + side, mat="traje", lumps=0.05)
        limb("pierna_" + side, [G(s * 0.2, 0.6, 0), G(s * 0.2, 0.32, 0.01), G(s * 0.2, 0.12, 0)], [0.12, 0.115, 0.11], bone="kn_" + side, mat="traje", lumps=0.05)
        cyl("cana_bota_" + side, 0.13, 0.26, G(s * 0.2, 0.17, 0), bone="kn_" + side, mat="cuero", verts=18, r2=0.125)
        box("bota_" + side, S(0.25, 0.13, 0.44), G(s * 0.2, -0.02, -0.08), bone="an_" + side, mat="cuero", bevel=0.05)
        box("suela_" + side, S(0.26, 0.03, 0.45), G(s * 0.2, -0.08, -0.08), bone="an_" + side, mat="metal_oscuro", bevel=0.01)
    box("rasgon_pantalon", (0.1, 0.03, 0.12), G(-0.2, 0.85, -0.15), (6, 0, 15), bone="hip_l", mat=skin, bevel=0.02)

    # -------------------------------------------------------------- torso de luchador
    blob("abdomen", 0.32, G(0, 1.64, 0), (1.0, 0.75, 0.68), bone="spine", mat="traje", lumps=0.03)
    blob("torax", 0.5, G(0, 2.12, 0), (1.0, 0.7, 0.58), bone="chest", mat="traje", lumps=0.03)
    for s in (-1, 1):
        blob("pectoral_%d" % s, 0.24, G(s * 0.22, 2.16, -0.16), (1.0, 0.8, 0.65), bone="chest", mat="traje", lumps=0.03)
    blob("trapecio", 0.32, G(0, 2.42, 0.03), (1.0, 0.55, 0.8), bone="chest", mat="traje", lumps=0.04)
    # Camisa y corbata floja (el mutante ya las reventó)
    if not mutant:
        box("camisa", S(0.22, 0.5, 0.04), G(0, 2.22, -0.3), (-6, 0, 0), bone="chest", mat="camisa", bevel=0.02)
        box("corbata", S(0.08, 0.42, 0.03), G(0.03, 2.2, -0.32), (-6, 0, -6), bone="chest", mat="corbata", taper=(0.6, 1.0), bevel=0.01)
        box("nudo", S(0.08, 0.06, 0.05), G(0.02, 2.42, -0.3), bone="chest", mat="corbata", bevel=0.012)
    # Bata de laboratorio: entera y manchada (humano) o en jirones (mutante)
    tat = 0.6 if mutant else 0.3
    hol = 0.12 if mutant else 0.03
    cloth("bata_izq", 0.38, 1.25 if not mutant else 0.9, G(-0.36, 2.2, -0.31), (0, 0, 3), bone="chest", mat="bata", nx=8, ny=14, tatter=tat, holes=hol, flare=0.06, bone2="hip_l", blend=0.6, seed=41)
    cloth("bata_der", 0.38, 1.25 if not mutant else 0.85, G(0.36, 2.2, -0.31), (0, 0, -3), bone="chest", mat="bata", nx=8, ny=14, tatter=tat, holes=hol, flare=0.06, bone2="hip_r", blend=0.6, seed=42)
    cloth("bata_atras", 1.05, 1.45 if not mutant else 1.0, G(0, 2.3, 0.32), (0, 0, 180), bone="chest", mat="bata", nx=16, ny=16, tatter=tat + 0.05, holes=hol, flare=0.1, seed=43)
    for s in (-1, 1):
        cloth("bata_lado_%d" % s, 0.5, 1.15 if not mutant else 0.7, G(s * 0.53, 2.18, 0.0), (0, 0, s * -90), bone="chest", mat="bata", nx=8, ny=12, tatter=tat, holes=hol, seed=44 + s)
        box("solapa_%d" % s, S(0.12, 0.45, 0.03), G(s * 0.2, 2.28, -0.33), (-8, 0, s * -16), bone="chest", mat="bata", bevel=0.01)
    if not mutant:
        panel("gafete", (0.1, 0.02, 0.13), G(-0.32, 2.18, -0.34), (0, 0, 0), bone="chest", mat="bata", bevel=0.006)
        label("gafete_txt", "DR. KESSLER", G(-0.32, 2.2, -0.355), (90, 0, 0), size=0.018, bone="chest", mat="metal_oscuro")
        box("radiacion", (0.07, 0.015, 0.07), G(-0.32, 2.1, -0.35), (0, 45, 0), bone="chest", mat="peligro", bevel=0.004)
        for k in range(3):
            cyl("pluma_%d" % k, 0.01, 0.15, G(0.3 + k * 0.025, 2.3, -0.34), bone="chest", mat="metal_oscuro" if k else "metal", verts=6)
    # Quemaduras de químicos en la bata
    for i in range(6):
        blob("quemadura_%d" % i, 0.07, G(rng.uniform(-0.45, 0.45), rng.uniform(1.2, 2.1), -0.33), (1.3, 1.0, 0.2), bone="chest", mat="metal_oscuro", lumps=0.4)

    # -------------------------------------------------------------- cuello y cabeza
    limb("cuello", [G(0, 2.48, 0), G(0, 2.6, -0.01), G(0, 2.74, 0)], [0.17, 0.16, 0.16], bone="neck", mat=skin)
    blob("craneo", 0.2, G(0, 2.93, 0.0), (0.95, 1.05, 1.05), bone="head", mat=skin, lumps=0.03, seed=8)
    blob("mandibula", 0.17, G(0, 2.8, -0.05), (1.08, 0.72, 1.05), bone="head", mat=skin, lumps=0.05, seed=9)
    blob("ceno", 0.16, G(0, 3.0, -0.12), (1.1, 0.35, 0.55), bone="head", mat=skin, lumps=0.05, seed=10)
    for s2 in (-1, 1):
        blob("oreja_%d" % s2, 0.045, G(s2 * 0.19, 2.92, 0.02), (0.45, 1.3, 1.0), bone="head", mat=skin, lumps=0.15)
    blob("nariz", 0.045, G(0, 2.93, -0.21), (0.8, 1.0, 1.2), bone="head", mat=skin, lumps=0.15)
    for (x, y, ln, rot) in ((-0.07, 2.92, 0.2, 18), (0.06, 2.85, 0.11, -78), (0.11, 3.0, 0.12, -25), (-0.09, 2.8, 0.08, 90)):
        box("cicatriz_%d" % int(x * 100), (0.02, 0.008, ln), G(x, y, -0.208), (0, -rot, 0), bone="head", mat="cicatriz", bevel=0.003)
    box("ojo_vivo", (0.06, 0.02, 0.025), G(0.085, 2.97, -0.2), bone="head", mat="metal_oscuro", bevel=0.006)
    box("ojos", (0.075, 0.02, 0.032), G(-0.085, 2.97, -0.205), bone="head", mat="ojos", bevel=0.006)
    box("boca", (0.13, 0.02, 0.018), G(0, 2.81, -0.21), bone="head", mat="cicatriz", bevel=0.005)
    # Pelo blanco peinado hacia atrás y barba corta
    blob("pelo", 0.21, G(0, 3.08, 0.06), (1.0, 0.55, 1.15), bone="head", mat="pelo", lumps=0.08)
    limb("copete", [G(0, 3.08, -0.15), G(0, 3.14, 0.0), G(0, 3.08, 0.2), G(0, 2.95, 0.26)], [0.1, 0.16, 0.15, 0.08], bone="head", mat="pelo", lumps=0.1)
    blob("barba", 0.13, G(0, 2.74, -0.13), (1.15, 0.6, 0.7), bone="head", mat="pelo", lumps=0.2, seed=11)
    blob("bigote", 0.06, G(0, 2.86, -0.205), (1.6, 0.35, 0.5), bone="head", mat="pelo", lumps=0.2, seed=12)

    # -------------------------------------------------------------- brazos gruesos
    for side, s in (("l", -1), ("r", 1)):
        sh, el, wr = "sh_" + side, "el_" + side, "wr_" + side
        blob("deltoide_" + side, 0.22, G(s * 0.6, 2.32, 0), (1.0, 0.9, 1.0), bone=sh, mat="bata" if not mutant else "traje", lumps=0.04)
        limb("brazo_" + side, [G(s * 0.6, 2.25, 0), G(s * 0.6, 2.0, 0.0), G(s * 0.6, 1.74, 0)], [0.16, 0.15, 0.12], bone=sh, mat="bata" if not mutant else "traje", lumps=0.06)
        limb("antebrazo_" + side, [G(s * 0.6, 1.74, 0), G(s * 0.6, 1.45, -0.01), G(s * 0.6, 1.18, 0)], [0.13, 0.12, 0.09], bone=el, mat=skin, lumps=0.06)
        if not mutant:
            cyl("puno_bata_" + side, 0.135, 0.18, G(s * 0.6, 1.68, 0), bone=el, mat="bata", verts=18, r2=0.13)
        box("mano_" + side, S(0.17, 0.2, 0.19), G(s * 0.6, 1.07, 0), bone=wr, mat=skin, bevel=0.05)
        for f in range(4):
            limb("dedo_%s_%d" % (side, f), [G(s * 0.6 + (f - 1.5) * 0.04, 1.0, -0.04), G(s * 0.6 + (f - 1.5) * 0.04, 0.93, -0.07)], [0.022, 0.019], bone=wr, mat=skin, verts=8)
    # Tubo radiactivo (derecha)
    cyl("tubo", 0.07, 1.3, G(0.6, 0.45, 0), bone="wr_r", mat="tubo", verts=16)
    for (y, h) in ((0.98, 0.16), (-0.18, 0.16)):
        cyl("tubo_tapa_%d" % int(y * 10), 0.1, h, G(0.6, y, 0), bone="wr_r", mat="metal", verts=16)
    for k in range(3):
        cyl("tubo_anillo_%d" % k, 0.085, 0.04, G(0.6, 0.7 - k * 0.3, 0), bone="wr_r", mat="metal_oscuro", verts=16)
    hazard_y = 0.98
    box("tubo_aviso", (0.03, 0.2, 0.08), G(0.6, hazard_y, -0.1), bone="wr_r", mat="peligro", bevel=0.004)
    # Pistola láser (izquierda)
    box("pistola", S(0.12, 0.36, 0.17), G(-0.6, 0.89, 0), bone="wr_l", mat="metal_oscuro", bevel=0.02)
    box("pistola_mango", S(0.08, 0.14, 0.2), G(-0.6, 1.01, 0.12), bone="wr_l", mat="cuero", bevel=0.015)
    cyl("pistola_canon", 0.04, 0.26, G(-0.6, 0.61, 0), bone="wr_l", mat="metal", verts=14)
    for k in range(3):
        cyl("pistola_bobina_%d" % k, 0.055, 0.02, G(-0.6, 0.7 - k * 0.05, 0), bone="wr_l", mat="metal_oscuro", verts=14)
    cyl("pistola_boca", 0.03, 0.03, G(-0.6, 0.47, 0), bone="wr_l", mat="suero", verts=12)

    if mutant:
        # ---------------------------------------------------------- mutación
        # Carne que revienta el traje por delante y por la espalda
        for k in range(6):
            blob("carne_pecho_%d" % k, rng.uniform(0.12, 0.18), G(rng.uniform(-0.35, 0.35), rng.uniform(1.95, 2.35), -0.27), (1.0, 0.9, 0.55), bone="chest", mat="piel_mut", lumps=0.3)
        for k in range(8):
            sphere("pus_pecho_%d" % k, rng.uniform(0.035, 0.06), G(rng.uniform(-0.4, 0.4), rng.uniform(1.9, 2.4), -0.33), bone="chest", mat="pus", segs=10)
        blob("carne_abdomen", 0.2, G(0.05, 1.62, -0.22), (1.3, 0.9, 0.6), bone="spine", mat="carne", lumps=0.35)
        for k in range(4):
            sphere("pus_abdomen_%d" % k, rng.uniform(0.03, 0.05), G(rng.uniform(-0.25, 0.25), rng.uniform(1.5, 1.75), -0.3), bone="spine", mat="pus", segs=10)
        blob("joroba", 0.3, G(0, 2.25, 0.35), (1.1, 1.0, 0.7), bone="chest", mat="piel_mut", lumps=0.3)
        for k in range(7):
            p = Vector(G(rng.uniform(-0.3, 0.3), 2.0 + k * 0.08, 0.45))
            d = Vector(G(rng.uniform(-0.3, 0.3), 0.35, 1.0)).normalized()
            rot = [math.degrees(a) for a in d.to_track_quat("Z", "Y").to_euler()]
            cyl("espina_espalda_%d" % k, 0.05, 0.35 - k * 0.02, tuple(p + d * 0.12), rot, bone="chest", mat="hueso", verts=6, r2=0.0, bevel=0)
        for k in range(6):
            sphere("pus_espalda_%d" % k, rng.uniform(0.05, 0.1), G(rng.uniform(-0.4, 0.4), rng.uniform(1.9, 2.5), 0.45), bone="chest", mat="pus", segs=12)
        # Hombros: el izquierdo hinchado y espinas en ambos
        blob("hombro_hinchado", 0.26, G(-0.65, 2.42, 0), (1.0, 0.85, 0.95), bone="sh_l", mat="piel_mut", lumps=0.3)
        for side, s in (("l", -1), ("r", 1)):
            for k in range(3):
                p = Vector(G(s * (0.62 + k * 0.06), 2.5, -0.08 + k * 0.08))
                d = Vector(G(s * (0.4 + k * 0.2), 1.0, 0.1 * k)).normalized()
                rot = [math.degrees(a) for a in d.to_track_quat("Z", "Y").to_euler()]
                cyl("espina_hombro_%s_%d" % (side, k), 0.05, 0.38 - k * 0.06, tuple(p + d * 0.15), rot, bone="sh_" + side, mat="hueso", verts=6, r2=0.0, bevel=0)
        # Brazo derecho con venas que brillan; antebrazo izquierdo deforme con garras
        blob("biceps_mut", 0.2, G(0.6, 1.47, 0), (0.95, 1.5, 0.95), bone="el_r", mat="piel_mut", lumps=0.2)
        for k in range(3):
            cable("vena_%d" % k, [G(0.52 + k * 0.08, 1.7, -0.14), G(0.55 + k * 0.06, 1.47, -0.19), G(0.53 + k * 0.07, 1.25, -0.13)], 0.012, bone="el_r", mat="pus")
        blob("antebrazo_deforme", 0.2, G(-0.6, 1.42, 0), (1.0, 1.35, 1.0), bone="el_l", mat="piel_mut", lumps=0.35)
        sphere("pus_antebrazo", 0.06, G(-0.72, 1.47, -0.1), bone="el_l", mat="pus", segs=10)
        for k in range(3):
            p = Vector(G(-0.65 + k * 0.05, 0.95, -0.1))
            cyl("garra_%d" % k, 0.025, 0.25, tuple(p + Vector((0, 0.05, -0.1))), (-160, 0, 0), bone="wr_l", mat="hueso", verts=6, r2=0.0, bevel=0)
        # Tumor en la cabeza, cara llena de pústulas y mandíbula desencajada con colmillos
        blob("tumor_cabeza", 0.14, G(0.12, 3.14, 0.05), (1.0, 0.8, 1.0), bone="head", mat="piel_mut", lumps=0.35)
        sphere("pus_tumor", 0.04, G(0.18, 3.18, -0.03), bone="head", mat="pus", segs=10)
        for k in range(3):
            sphere("pus_cara_%d" % k, 0.018, G(rng.uniform(-0.14, 0.14), rng.uniform(2.82, 3.02), -0.205), bone="head", mat="pus", segs=8)
        box("boca_abierta", S(0.26, 0.08, 0.06), G(0, 2.72, -0.19), (12, 0, 0), bone="head", mat="boca", bevel=0.02)
        box("quijada_baja", S(0.34, 0.1, 0.26), G(0, 2.66, -0.1), (15, 0, 0), bone="head", mat="piel_mut", bevel=0.04)
        for k in range(5):
            cyl("colmillo_%d" % k, 0.018, 0.08, G(-0.12 + k * 0.06, 2.73, -0.22), bone="head", mat="hueso", verts=6, r2=0.0, bevel=0)

    # -------------------------------------------------------------- esqueleto (= articulaciones)
    B = [
        ("pelvis", "", G(0, 1.28, 0), G(0, 1.44, 0)),
        ("spine", "pelvis", G(0, 1.44, 0), G(0, 1.84, 0)),
        ("chest", "spine", G(0, 1.84, 0), G(0, 2.5, 0)),
        ("neck", "chest", G(0, 2.5, 0), G(0, 2.72, 0)),
        ("head", "neck", G(0, 2.72, 0), G(0, 3.15, 0)),
    ]
    for side, s in (("l", -1), ("r", 1)):
        B += [
            ("hip_" + side, "pelvis", G(s * 0.2, 1.2, 0), G(s * 0.2, 0.6, 0)),
            ("kn_" + side, "hip_" + side, G(s * 0.2, 0.6, 0), G(s * 0.2, 0.02, 0)),
            ("an_" + side, "kn_" + side, G(s * 0.2, 0.02, 0), G(s * 0.2, -0.05, -0.3)),
            ("sh_" + side, "chest", G(s * 0.6, 2.32, 0), G(s * 0.6, 1.72, 0)),
            ("el_" + side, "sh_" + side, G(s * 0.6, 1.72, 0), G(s * 0.6, 1.16, 0)),
            ("wr_" + side, "el_" + side, G(s * 0.6, 1.16, 0), G(s * 0.6, 0.9, 0)),
        ]
    bk.armature(B)
    name = "kessler_mutante" if mutant else "kessler"
    bk.finish(name, tex_size=2048, bake=True, out_dir=OUT)
    if PREVIEW:
        bk.render_preview(os.path.join(OUT, "preview_%s.png" % name), (1.8, 5.0, 2.2), (0, 0, 1.7))
        bk.render_preview(os.path.join(OUT, "preview_%s_cara.png" % name), (0.5, 1.4, 3.0), (0, 0, 2.85), size=(700, 700))
    bk.export(os.path.join(OUT, name + ".glb"), actions=False)


for nm, mut in (("humano", False), ("mutante", True)):
    if not ONLY or nm in ONLY:
        build(mut)
print("LISTO", OUT)
