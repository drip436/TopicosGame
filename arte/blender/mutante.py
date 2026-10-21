"""Especímenes mutantes del Laboratorio (enemigos "mutante_*"): bestias salvajes y torpes,
como las de Dark Souls. Piel enferma con venas, carne viva, pústulas que brillan, hueso
que atraviesa la piel y jirones de la bata de paciente del laboratorio del Dr. Kessler.

  mutante_peq     sabueso rastrero sin pelo: costillas de fuera, hocico lleno de dientes,
                  tres ojos y espinas en el lomo.
  mutante_med     ghoul encorvado: brazo izquierdo deforme con garras de hueso, el derecho
                  flaco, mandíbula colgando y bata rota.
  mutante_grande  mole de carne de 3.4 m: brazo derecho convertido en un mazo de tumores,
                  cabeza hundida entre los hombros, sacos de pus en la espalda.

Uso:  blender -b --python arte/blender/mutante.py -- <carpeta_salida> [preview] [peq|med|grande ...]
Animaciones y tiempos de impacto (también en mundo/enemy.gd):
  peq:    idle, walk, run, bite 0.4, pounce 0.55, roar, stumble, hit, death
  med:    idle, walk, run, slash 0.55 / 0.95, frenzy 0.5 / 0.8 / 1.1 / 1.4, spit 0.8, roar, stumble, hit, death
  grande: idle, walk, run, overhead 1.2, sweep 0.9, spit 1.0, roar, stumble, hit, death
"""
import sys
import os
import math
import random

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, sphere, cable, cloth, blob, limb
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/mutante")
PREVIEW = "preview" in argv
ONLY = [a for a in argv[1:] if a != "preview"]
os.makedirs(OUT, exist_ok=True)

MATS = {
    "piel": dict(skin=True, base=(0.14, 0.135, 0.085), veins=0.8, vein_col=(0.035, 0.012, 0.05), blotch=1.0, blotch_col=(0.12, 0.03, 0.045), rough=0.5, wet=0.45, dirt=1.1, scale=1.4),
    "carne": dict(skin=True, base=(0.11, 0.018, 0.016), veins=0.6, vein_col=(0.03, 0.005, 0.01), blotch=0.7, blotch_col=(0.2, 0.08, 0.03), rough=0.3, wet=0.9, dirt=0.4, scale=2.0),
    "hueso": dict(base=(0.42, 0.38, 0.28), rough=0.6, rust=0.15, wear=0.3, dirt=1.0, bare=(0.6, 0.57, 0.48), scratches=False, soot=0.4, streaks=0.5),
    "bata": dict(base=(0.32, 0.33, 0.29), rough=0.95, rust=0.35, wear=0.5, dirt=1.4, bare=(0.15, 0.14, 0.11), scratches=False, soot=0.6, streaks=0.9),
    "metal": dict(base=(0.4, 0.4, 0.42), metal=1.0, rough=0.45, rust=1.2, wear=0.4, dirt=0.8, bare=(0.7, 0.7, 0.72), streaks=0.6),
    "goma": dict(base=(0.1, 0.12, 0.1), rough=0.6, rust=0.0, wear=0.2, dirt=0.8, scratches=False),
    "pus": {"emit": (0.55, 0.9, 0.12), "strength": 1.2},
    "ojos": {"emit": (0.6, 1.0, 0.2), "strength": 7.0},
}


def start(seed):
    bk.reset(seed=seed)
    bk.define_materials(MATS)
    return random.Random(seed)


def on_blob(center, r, scale, d):
    """Punto sobre la superficie de un blob (elipsoide) en la dirección d."""
    d = Vector(d).normalized()
    return tuple(Vector(center) + Vector((d.x * r * scale[0], d.y * r * scale[1], d.z * r * scale[2])))


def pustules(prefix, center, r, scale, dirs, bone, rng, size=(0.02, 0.045)):
    for i, d in enumerate(dirs):
        p = on_blob(center, r, scale, d)
        s = rng.uniform(*size)
        # La pústula asoma de un bulto de carne hundido en la piel
        dd = Vector(d).normalized()
        sphere("%s_%d" % (prefix, i), s, tuple(Vector(p) + dd * s * 0.45), bone=bone, mat="pus", segs=10)
        blob("%s_base_%d" % (prefix, i), s * 1.25, tuple(Vector(p) - dd * s * 0.2), bone=bone, mat="carne", lumps=0.25, segs=12)


def teeth(prefix, a, b, n, size, bone, down=True, rng=None):
    a = Vector(a)
    b = Vector(b)
    for i in range(n):
        p = a.lerp(b, (i + 0.5) / n)
        s = size * (rng.uniform(0.7, 1.3) if rng else 1.0)
        rot = (180 if down else 0, rng.uniform(-15, 15) if rng else 0, 0)
        cyl("%s_%d" % (prefix, i), s * 0.35, s, tuple(p + Vector((0, 0, -s * 0.5 if down else s * 0.5))), rot, bone=bone, mat="hueso", verts=6, r2=0.0, bevel=0)


def claws(prefix, base, n, spread, length, bone, fwd=0.3, r=0.012):
    for i in range(n):
        x = base[0] + (i - (n - 1) / 2) * spread
        p0 = Vector((x, base[1], base[2]))
        p1 = p0 + Vector((0, length * fwd, -length * 0.4))
        p2 = p1 + Vector((0, length * 0.45, -length * 0.55))
        limb("%s_%d" % (prefix, i), [tuple(p0), tuple(p1), tuple(p2)], [r, r * 0.7, r * 0.15], bone=bone, mat="hueso", verts=6)


def spike(name, p, d, r, h, bone, mat="hueso"):
    """Púa cónica que sale de `p` en la dirección `d`."""
    d = Vector(d).normalized()
    rot = [math.degrees(a) for a in d.to_track_quat("Z", "Y").to_euler()]
    cyl(name, r, h, tuple(Vector(p) + d * h * 0.4), rot, bone=bone, mat=mat, verts=6, r2=0.0, bevel=0)


# ====================================================================== PEQUEÑO
def build_peq():
    rng = start(31)
    # Cuerpo: pecho hundido con costillas de fuera, panza colgando, cadera huesuda
    blob("pecho", 0.2, (0, 0.3, 0.6), (0.82, 1.2, 0.95), bone="chest", mat="piel", lumps=0.12)
    blob("panza", 0.15, (0, -0.02, 0.52), (0.85, 1.25, 0.8), bone="hips", mat="piel", lumps=0.15)
    blob("cadera", 0.15, (0, -0.25, 0.6), (0.9, 1.0, 0.85), bone="hips", mat="piel", lumps=0.1)
    blob("herida", 0.07, (0.12, 0.22, 0.6), (0.6, 1.4, 1.0), bone="chest", mat="carne", lumps=0.2)
    for k in range(6):
        y = 0.42 - k * 0.07
        for s in (-1, 1):
            if (k + (s > 0)) % 3 == 0:
                continue
            limb("costilla_%d_%d" % (k, s), [(s * 0.05, y, 0.79), (s * 0.145, y - 0.01, 0.71), (s * 0.155, y - 0.02, 0.58)],
                 [0.009, 0.011, 0.006], bone="chest", mat="hueso", verts=6)
    # Espinas de hueso en el lomo
    for k in range(7):
        y = 0.45 - k * 0.12
        h = 0.06 + 0.05 * math.sin(k / 6 * math.pi)
        spike("espina_%d" % k, (0, y, 0.8 - abs(y - 0.1) * 0.12), (0, -0.4, 1), 0.02, h, "chest" if y > 0.05 else "hips")
    pustules("pus_lomo", (0, 0.1, 0.6), 0.2, (0.8, 1.6, 0.9), [(0.5, 0.2, 0.8), (-0.6, -0.3, 0.7), (0.7, -0.6, 0.4), (-0.4, 0.5, 0.75), (0.2, -0.9, 0.5)], "chest", rng)
    # Cuello y cabeza: hocico largo, tres ojos
    limb("cuello", [(0, 0.42, 0.66), (0, 0.55, 0.7), (0, 0.68, 0.72)], [0.09, 0.075, 0.065], bone="neck", mat="piel", lumps=0.1)
    blob("craneo", 0.1, (0, 0.76, 0.73), (0.85, 1.15, 0.75), bone="head", mat="piel", lumps=0.1)
    limb("hocico", [(0, 0.8, 0.72), (0, 0.9, 0.7), (0, 1.0, 0.68)], [0.07, 0.055, 0.04], bone="head", mat="piel", lumps=0.08)
    blob("encia_sup", 0.045, (0, 0.92, 0.66), (0.9, 2.0, 0.5), bone="head", mat="carne", lumps=0.1)
    teeth("diente_sup", (-0.03, 0.85, 0.655), (-0.025, 1.0, 0.645), 5, 0.035, "head", True, rng)
    teeth("diente_sup2", (0.03, 0.85, 0.655), (0.025, 1.0, 0.645), 5, 0.035, "head", True, rng)
    limb("mandibula", [(0, 0.78, 0.65), (0, 0.88, 0.62), (0, 0.98, 0.6)], [0.045, 0.04, 0.03], bone="jaw", mat="piel", lumps=0.1)
    blob("lengua", 0.03, (0, 0.92, 0.625), (0.8, 2.2, 0.5), bone="jaw", mat="carne")
    teeth("diente_inf", (-0.025, 0.84, 0.64), (-0.02, 0.97, 0.625), 4, 0.03, "jaw", False, rng)
    teeth("diente_inf2", (0.025, 0.84, 0.64), (0.02, 0.97, 0.625), 4, 0.03, "jaw", False, rng)
    for i, (x, y, z, r) in enumerate([(0.055, 0.84, 0.76, 0.017), (-0.055, 0.84, 0.76, 0.017), (0.07, 0.79, 0.79, 0.011)]):
        sphere("ojos_%d" % i, r, (x, y, z), bone="head", mat="ojos", segs=10)
    # Patas delanteras (largas, codos hacia atrás) y traseras (corvejón de perro)
    for side, s in (("l", -1), ("r", 1)):
        limb("pata_d_%s" % side, [(s * 0.13, 0.36, 0.56), (s * 0.15, 0.38, 0.42), (s * 0.15, 0.42, 0.3)], [0.06, 0.05, 0.035], bone="leg_f" + side, mat="piel", lumps=0.15)
        limb("cana_d_%s" % side, [(s * 0.15, 0.42, 0.3), (s * 0.15, 0.4, 0.16), (s * 0.15, 0.38, 0.06)], [0.032, 0.026, 0.024], bone="shin_f" + side, mat="piel", lumps=0.1)
        blob("mano_d_%s" % side, 0.04, (s * 0.15, 0.41, 0.035), (1.0, 1.4, 0.6), bone="paw_f" + side, mat="piel")
        claws("garra_d_%s" % side, (s * 0.15, 0.45, 0.04), 3, 0.022, 0.05, "paw_f" + side, r=0.008)
        limb("muslo_t_%s" % side, [(s * 0.12, -0.22, 0.58), (s * 0.15, -0.12, 0.45), (s * 0.15, -0.04, 0.32)], [0.075, 0.06, 0.04], bone="leg_b" + side, mat="piel", lumps=0.15)
        limb("cana_t_%s" % side, [(s * 0.15, -0.04, 0.32), (s * 0.15, -0.16, 0.22), (s * 0.15, -0.24, 0.12)], [0.035, 0.03, 0.025], bone="shin_b" + side, mat="piel", lumps=0.1)
        limb("tarso_t_%s" % side, [(s * 0.15, -0.24, 0.12), (s * 0.15, -0.22, 0.05), (s * 0.15, -0.18, 0.03)], [0.025, 0.022, 0.03], bone="paw_b" + side, mat="piel")
        claws("garra_t_%s" % side, (s * 0.15, -0.15, 0.04), 3, 0.022, 0.04, "paw_b" + side, r=0.007)
    blob("rodilla_carne", 0.035, (0.15, -0.05, 0.33), (1, 1, 1), bone="shin_br", mat="carne")
    limb("cola", [(0, -0.36, 0.62), (0, -0.5, 0.58), (0, -0.62, 0.5), (0, -0.7, 0.42)], [0.04, 0.03, 0.02, 0.008], bone="tail", mat="piel", lumps=0.2)
    # Restos de la bata y un tubo de suero clavado
    cloth("bata_jiron", 0.2, 0.18, (0.0, 0.0, 0.72), (90, 0, 90), bone="hips", mat="bata", nx=6, ny=6, tatter=0.6, holes=0.05, seed=31)
    cable("tubo_suero", [(-0.05, 0.05, 0.78), (-0.12, -0.05, 0.86), (-0.2, -0.2, 0.8), (-0.18, -0.32, 0.66)], 0.008, bone="hips", mat="goma", sag=0.02)
    cyl("aguja", 0.006, 0.06, (-0.05, 0.06, 0.76), (30, 0, 0), bone="hips", mat="metal", verts=6, bevel=0)

    B = [("root", "", (0, 0, 0), (0, 0.15, 0)),
         ("hips", "root", (0, -0.25, 0.58), (0, 0.08, 0.6)),
         ("chest", "hips", (0, 0.08, 0.6), (0, 0.42, 0.65)),
         ("neck", "chest", (0, 0.42, 0.65), (0, 0.7, 0.72)),
         ("head", "neck", (0, 0.7, 0.72), (0, 0.98, 0.7)),
         ("jaw", "head", (0, 0.77, 0.66), (0, 0.98, 0.6)),
         ("tail", "hips", (0, -0.36, 0.6), (0, -0.72, 0.42))]
    for side, s in (("l", -1), ("r", 1)):
        B += [("leg_f" + side, "chest", (s * 0.13, 0.36, 0.56), (s * 0.15, 0.42, 0.3)),
              ("shin_f" + side, "leg_f" + side, (s * 0.15, 0.42, 0.3), (s * 0.15, 0.38, 0.06)),
              ("paw_f" + side, "shin_f" + side, (s * 0.15, 0.38, 0.06), (s * 0.15, 0.48, 0.03)),
              ("leg_b" + side, "hips", (s * 0.12, -0.22, 0.58), (s * 0.15, -0.04, 0.32)),
              ("shin_b" + side, "leg_b" + side, (s * 0.15, -0.04, 0.32), (s * 0.15, -0.24, 0.12)),
              ("paw_b" + side, "shin_b" + side, (s * 0.15, -0.24, 0.12), (s * 0.15, -0.14, 0.03))]
    bk.armature(B)
    bk.finish("mutante_peq", tex_size=1024, bake=True, out_dir=OUT)

    # --- animaciones. Huesos que apuntan al frente (cadera, pecho, cuello, cabeza):
    #     X+ levanta la punta, X− la baja; Z+ gira hacia la izquierda. Patas: X+ adelante.
    READY = {"chest": (-4, 0, 0), "neck": (-12, 0, 0), "head": (-6, 0, 0), "jaw": (-8, 0, 0), "tail": (-10, 0, 0),
             "leg_fl": (8, 0, 0), "shin_fl": (-6, 0, 0), "leg_fr": (8, 0, 0), "shin_fr": (-6, 0, 0),
             "leg_bl": (-6, 0, 0), "shin_bl": (6, 0, 0), "leg_br": (-6, 0, 0), "shin_br": (6, 0, 0), "root_pos": (0, 0, -0.03)}

    def P(**kw):
        d = dict(READY)
        d.update(kw)
        return d

    def trot(ph, amp, lift, bob, head):
        s = math.sin(ph)
        c = math.cos(ph)
        s2 = math.sin(ph + math.pi)
        return P(leg_fl=(8 + s * amp, 0, 0), shin_fl=(-6 - max(0.0, c) * lift, 0, 0),
                 leg_fr=(8 + s2 * amp, 0, 0), shin_fr=(-6 - max(0.0, -c) * lift, 0, 0),
                 leg_bl=(-6 + s2 * amp, 0, 0), shin_bl=(6 + max(0.0, -c) * lift, 0, 0),
                 leg_br=(-6 + s * amp, 0, 0), shin_br=(6 + max(0.0, c) * lift, 0, 0),
                 chest=(-4 + c * 3, 0, s * 4), neck=(-12 + head, 0, -s * 6), head=(-6 - c * 4, 0, s * 5),
                 tail=(-10 + c * 10, 0, s * 25), jaw=(-15, 0, 0),
                 root_pos=(0, 0, -0.03 - abs(s) * bob))

    def gallop(ph, amp, bob):
        s = math.sin(ph)
        c = math.cos(ph)
        return P(leg_fl=(10 + s * amp, 0, 0), leg_fr=(10 + math.sin(ph + 0.4) * amp, 0, 0),
                 shin_fl=(-10 - max(0.0, c) * 50, 0, 0), shin_fr=(-10 - max(0.0, math.cos(ph + 0.4)) * 50, 0, 0),
                 leg_bl=(-8 - s * amp, 0, 0), leg_br=(-8 - math.sin(ph + 0.4) * amp, 0, 0),
                 shin_bl=(8 + max(0.0, -c) * 50, 0, 0), shin_br=(8 + max(0.0, -math.cos(ph + 0.4)) * 50, 0, 0),
                 hips=(s * 8, 0, 0), chest=(-s * 10, 0, 0), neck=(-20 + s * 8, 0, 0), head=(-4, 0, 0), jaw=(-25, 0, 0),
                 tail=(5 + c * 15, 0, 0), root_pos=(0, 0, -0.02 + s * bob))

    idle = []
    for i in range(17):
        t = i * 0.25
        b = math.sin(t / 2.0 * 2 * math.pi)
        pose = P(chest=(-4 + b * 3, 0, 0), neck=(-12 + b * 4, 0, 0), jaw=(-8 - max(0.0, b) * 10, 0, 0), tail=(-10, 0, b * 15))
        if 1.75 <= t <= 2.25:
            # Olfatea el suelo
            pose.update(neck=(-40, 0, 10), head=(-20, 0, 10), jaw=(-4, 0, 0))
        if abs(t - 3.0) < 0.01:
            # Sacude la cabeza como un perro idiota
            pose.update(neck=(-6, 0, 0), head=(0, 40, 0))
        if abs(t - 3.25) < 0.01:
            pose.update(neck=(-6, 0, 0), head=(0, -40, 0))
        idle.append((t, pose))
    bk.action("idle", idle, loop=True)
    bk.action("walk", [(i / 8 * 0.9, trot(i / 8 * 2 * math.pi, 22, 40, 0.025, 0)) for i in range(9)], loop=True)
    bk.action("run", [(i / 8 * 0.45, gallop(i / 8 * 2 * math.pi, 38, 0.06)) for i in range(9)], loop=True)
    bk.action("bite", [(0.0, P()),
                       (0.28, P(chest=(6, 0, 0), neck=(10, 0, 0), head=(14, 0, 0), jaw=(-50, 0, 0), leg_bl=(-20, 0, 0), shin_bl=(30, 0, 0), leg_br=(-20, 0, 0), shin_br=(30, 0, 0), root_pos=(0, -0.08, -0.06))),
                       (0.4, P(chest=(-12, 0, 0), neck=(-18, 0, 0), head=(-14, 0, 0), jaw=(0, 0, 0), leg_fl=(40, 0, 0), leg_fr=(35, 0, 0), leg_bl=(-30, 0, 0), leg_br=(-30, 0, 0), root_pos=(0, 0.18, -0.06))),
                       (0.55, P(chest=(-10, 0, 0), neck=(-16, 0, 25), head=(-10, 0, 30), jaw=(-5, 0, 0), leg_fl=(30, 0, 0), leg_fr=(25, 0, 0), root_pos=(0, 0.16, -0.06))),
                       (0.7, P(chest=(-10, 0, 0), neck=(-16, 0, -25), head=(-10, 0, -30), jaw=(-5, 0, 0), root_pos=(0, 0.12, -0.05))),
                       (1.0, P())])
    bk.action("pounce", [(0.0, P()),
                         (0.4, P(hips=(10, 0, 0), chest=(14, 0, 0), neck=(4, 0, 0), jaw=(-40, 0, 0), leg_fl=(-10, 0, 0), shin_fl=(-40, 0, 0), leg_fr=(-10, 0, 0), shin_fr=(-40, 0, 0),
                                  leg_bl=(30, 0, 0), shin_bl=(50, 0, 0), leg_br=(30, 0, 0), shin_br=(50, 0, 0), root_pos=(0, -0.1, -0.15))),
                         (0.55, P(hips=(-10, 0, 0), chest=(-6, 0, 0), neck=(0, 0, 0), jaw=(-55, 0, 0), leg_fl=(70, 0, 0), shin_fl=(-10, 0, 0), leg_fr=(70, 0, 0), shin_fr=(-10, 0, 0),
                                  leg_bl=(-60, 0, 0), shin_bl=(10, 0, 0), leg_br=(-60, 0, 0), shin_br=(10, 0, 0), tail=(20, 0, 0), root_pos=(0, 0.3, 0.3))),
                         (0.75, P(chest=(-20, 0, 0), neck=(-30, 0, 0), jaw=(0, 0, 0), leg_fl=(20, 0, 0), shin_fl=(-40, 0, 0), leg_fr=(20, 0, 0), shin_fr=(-40, 0, 0), root_pos=(0, 0.5, -0.05))),
                         (1.2, P())])
    bk.action("roar", [(0.0, P()),
                       (0.35, P(chest=(16, 0, 0), neck=(30, 0, 0), head=(20, 0, 0), jaw=(-60, 0, 0), leg_fl=(-15, 0, 0), leg_fr=(-15, 0, 0), root_pos=(0, -0.05, 0.04))),
                       (0.6, P(chest=(18, 0, 6), neck=(34, 0, -8), head=(24, 0, 10), jaw=(-65, 0, 0), leg_fl=(-15, 0, 0), leg_fr=(-15, 0, 0), root_pos=(0, -0.05, 0.05))),
                       (0.85, P(chest=(18, 0, -6), neck=(34, 0, 8), head=(24, 0, -10), jaw=(-62, 0, 0), leg_fl=(-15, 0, 0), leg_fr=(-15, 0, 0), root_pos=(0, -0.05, 0.05))),
                       (1.3, P())])
    # Tropiezo: se le doblan las patas delanteras y se da de hocico (después de fallar un salto)
    bk.action("stumble", [(0.0, P()),
                          (0.15, P(leg_fl=(-40, 0, 0), shin_fl=(-70, 0, 0), leg_fr=(-40, 0, 0), shin_fr=(-70, 0, 0), chest=(-20, 0, 10), neck=(-40, 0, 0), head=(-20, 0, 20), root_pos=(0, 0.05, -0.25))),
                          (0.6, P(root=(0, 30, 0), leg_fl=(-50, 0, 0), shin_fl=(-80, 0, 0), leg_fr=(-30, 0, 0), shin_fr=(-60, 0, 0), chest=(-15, 0, 10), neck=(-30, 0, 20), head=(-10, 0, 30), jaw=(-30, 0, 0), root_pos=(0, 0.05, -0.2))),
                          (0.9, P(chest=(-5, 0, 0), neck=(-10, 0, 0), head=(0, 30, 0))),
                          (1.0, P(chest=(-5, 0, 0), neck=(-10, 0, 0), head=(0, -30, 0))),
                          (1.2, P())])
    bk.action("hit", [(0.0, P()), (0.08, P(chest=(14, 0, 10), neck=(20, 0, 10), head=(20, 0, 20), jaw=(-40, 0, 0), root_pos=(0, -0.1, -0.02))), (0.5, P())])
    bk.action("death", [(0.0, P()),
                        (0.2, P(chest=(20, 0, 0), neck=(30, 0, 0), jaw=(-60, 0, 0), leg_fl=(-30, 0, 0), leg_fr=(-30, 0, 0))),
                        (0.7, P(root=(0, 88, 0), chest=(0, 0, 0), neck=(-10, 0, 20), head=(-10, 0, 20), jaw=(-40, 0, 0), leg_fl=(30, 0, 0), leg_fr=(10, 0, 0), leg_bl=(-20, 0, 0), leg_br=(-40, 0, 0), tail=(-20, 0, 20), root_pos=(-0.15, 0, -0.38))),
                        (0.85, P(root=(0, 92, 0), chest=(0, 0, 0), neck=(-14, 0, 24), head=(-14, 0, 24), jaw=(-45, 0, 0), leg_fl=(40, 0, 0), leg_fr=(20, 0, 0), leg_bl=(-10, 0, 0), leg_br=(-30, 0, 0), tail=(-20, 0, 25), root_pos=(-0.15, 0, -0.4)))])
    bk.set_pose(P())
    if PREVIEW:
        bk.render_preview(os.path.join(OUT, "preview_peq.png"), (1.6, 1.8, 1.0), (0, 0.15, 0.45), size=(900, 700))
        bk.render_preview(os.path.join(OUT, "preview_peq_salto.png"), (2.0, 0.8, 0.8), (0, 0.15, 0.5), size=(900, 700), action_name="pounce", frame=17)
    bk.set_pose({})
    bk.export(os.path.join(OUT, "mutante_peq.glb"))


# ====================================================================== MEDIANO (ghoul)
def build_med():
    rng = start(37)
    # Torso flaco y encorvado (el encorvado lo da la pose), costillas marcadas y bata rota
    blob("pelvis", 0.13, (0, 0, 0.92), (1.1, 0.8, 0.8), bone="hips", mat="piel", lumps=0.1)
    blob("vientre", 0.12, (0, 0.02, 1.08), (1.0, 0.75, 1.0), bone="spine", mat="piel", lumps=0.12)
    blob("torax", 0.2, (0, 0.0, 1.32), (1.2, 0.82, 1.0), bone="chest", mat="piel", lumps=0.12)
    blob("joroba", 0.2, (-0.06, -0.12, 1.43), (1.15, 0.85, 0.95), bone="chest", mat="piel", lumps=0.3)
    blob("trapecio_l", 0.12, (-0.18, -0.02, 1.47), (1.1, 1.0, 0.8), bone="chest", mat="piel", lumps=0.25)
    blob("herida_pecho", 0.06, (0.08, 0.12, 1.3), (1.0, 0.5, 1.5), bone="chest", mat="carne", lumps=0.2)
    for k in range(4):
        for s in (-1, 1):
            z = 1.36 - k * 0.07
            limb("costilla_%d_%d" % (k, s), [(s * 0.03, 0.13, z), (s * 0.13, 0.11, z - 0.02), (s * 0.19, 0.0, z - 0.04)], [0.009, 0.011, 0.008], bone="chest", mat="hueso", verts=6)
    for k in range(5):
        spike("vertebra_%d" % k, (0, -0.13 - k * 0.005, 1.5 - k * 0.09), (0, -1, 0.3), 0.024, 0.07, "chest" if k < 3 else "spine")
    pustules("pus_espalda", (-0.06, -0.12, 1.43), 0.2, (1.15, 0.85, 0.95), [(-0.5, -0.6, 0.6), (0.3, -0.8, 0.4), (-0.8, -0.3, 0.2), (0.0, -0.7, 0.7), (0.6, -0.5, -0.2)], "chest", rng)
    cloth("bata_frente", 0.36, 0.55, (0, 0.1, 1.2), (0, 0, 0), bone="spine", mat="bata", nx=10, ny=12, tatter=0.45, holes=0.06, flare=0.05, bone2="hips", blend=0.8, seed=41)
    cloth("bata_atras", 0.42, 0.62, (0, -0.2, 1.4), (0, 0, 180), bone="chest", mat="bata", nx=10, ny=14, tatter=0.5, holes=0.06, flare=0.04, bone2="hips", blend=0.85, seed=42)
    # Cuello largo, cabeza calva deforme, mandíbula colgando
    limb("cuello", [(0, 0.0, 1.46), (0, 0.04, 1.55), (0, 0.06, 1.62)], [0.06, 0.05, 0.05], bone="neck", mat="piel", lumps=0.15)
    blob("craneo", 0.11, (0, 0.06, 1.72), (0.9, 1.05, 1.1), bone="head", mat="piel", lumps=0.18)
    blob("tumor_cabeza", 0.05, (-0.07, 0.02, 1.8), (1, 1, 1), bone="head", mat="carne", lumps=0.3)
    for i, (x, z, r) in enumerate([(0.04, 1.73, 0.016), (-0.035, 1.735, 0.012)]):
        sphere("ojos_%d" % i, r, (x, 0.155, z), bone="head", mat="ojos", segs=10)
    blob("encia", 0.05, (0, 0.13, 1.66), (1.2, 0.7, 0.5), bone="head", mat="carne")
    teeth("diente_sup", (-0.045, 0.15, 1.65), (0.045, 0.15, 1.65), 7, 0.03, "head", True, rng)
    blob("mandibula", 0.06, (0, 0.12, 1.6), (1.1, 0.9, 0.55), bone="jaw", mat="piel", lumps=0.15)
    teeth("diente_inf", (-0.04, 0.16, 1.61), (0.04, 0.16, 1.61), 6, 0.025, "jaw", False, rng)
    blob("lengua", 0.03, (0, 0.17, 1.6), (0.9, 1.6, 0.4), bone="jaw", mat="carne")
    # Brazo izquierdo deforme: músculo hinchado, hueso que atraviesa la piel, garras largas
    limb("hombro_l", [(-0.2, 0, 1.45), (-0.28, 0, 1.44), (-0.32, 0, 1.38)], [0.1, 0.11, 0.1], bone="upper_arm_l", mat="piel", lumps=0.2)
    limb("brazo_l", [(-0.32, 0, 1.4), (-0.36, 0.0, 1.22), (-0.38, 0, 1.05)], [0.1, 0.11, 0.085], bone="upper_arm_l", mat="piel", lumps=0.25)
    blob("biceps_carne", 0.07, (-0.38, 0.06, 1.24), (0.8, 0.8, 1.3), bone="upper_arm_l", mat="carne", lumps=0.3)
    cyl("hueso_sale_l", 0.018, 0.14, (-0.42, -0.05, 1.18), (0, -35, 0), bone="upper_arm_l", mat="hueso", verts=6, r2=0.006, bevel=0)
    limb("antebrazo_l", [(-0.38, 0, 1.04), (-0.4, 0.02, 0.85), (-0.41, 0.03, 0.68)], [0.085, 0.08, 0.06], bone="forearm_l", mat="piel", lumps=0.25)
    pustules("pus_brazo", (-0.4, 0.02, 0.86), 0.08, (1, 1, 2), [(-1, 0.3, 0.2), (-0.7, -0.6, -0.3), (-0.6, 0.6, -0.5)], "forearm_l", rng, size=(0.015, 0.03))
    blob("mano_l", 0.06, (-0.41, 0.04, 0.62), (1.1, 0.8, 1.0), bone="hand_l", mat="piel", lumps=0.15)
    claws("garra_l", (-0.41, 0.07, 0.6), 4, 0.03, 0.2, "hand_l", fwd=0.15, r=0.014)
    # Brazo derecho flaco y largo
    limb("brazo_r", [(0.2, 0, 1.45), (0.26, 0, 1.25), (0.29, 0, 1.06)], [0.05, 0.042, 0.038], bone="upper_arm_r", mat="piel", lumps=0.1)
    limb("antebrazo_r", [(0.29, 0, 1.05), (0.3, 0.01, 0.86), (0.31, 0.02, 0.7)], [0.036, 0.032, 0.028], bone="forearm_r", mat="piel", lumps=0.1)
    blob("mano_r", 0.035, (0.31, 0.03, 0.66), (1, 0.7, 1.2), bone="hand_r", mat="piel")
    claws("garra_r", (0.31, 0.05, 0.64), 4, 0.018, 0.1, "hand_r", fwd=0.15, r=0.008)
    cable("tubo_brazo", [(0.27, 0.03, 0.95), (0.33, 0.1, 0.82), (0.36, 0.05, 0.6), (0.34, 0.0, 0.45)], 0.007, bone="forearm_r", mat="goma", sag=0.0)
    # Piernas en cuclillas, pies con garras
    for side, s in (("l", -1), ("r", 1)):
        limb("muslo_" + side, [(s * 0.1, 0, 0.9), (s * 0.12, 0.02, 0.7), (s * 0.13, 0.0, 0.5)], [0.095, 0.085, 0.06], bone="thigh_" + side, mat="piel", lumps=0.18)
        limb("pierna_" + side, [(s * 0.13, 0, 0.49), (s * 0.13, -0.03, 0.3), (s * 0.13, 0, 0.1)], [0.06, 0.055, 0.035], bone="shin_" + side, mat="piel", lumps=0.18)
        limb("pie_" + side, [(s * 0.13, -0.03, 0.08), (s * 0.13, 0.06, 0.04), (s * 0.13, 0.14, 0.03)], [0.04, 0.04, 0.03], bone="foot_" + side, mat="piel", lumps=0.1)
        claws("garra_pie_" + side, (s * 0.13, 0.15, 0.04), 3, 0.025, 0.05, "foot_" + side, r=0.008)
    blob("rodilla_carne", 0.04, (-0.13, 0.04, 0.5), (1, 1, 1), bone="shin_l", mat="carne", lumps=0.3)
    cloth("calzon", 0.32, 0.18, (0, 0.0, 0.98), (0, 0, 0), bone="hips", mat="bata", nx=8, ny=5, tatter=0.5, holes=0.05, seed=43)

    B = [("root", "", (0, 0, 0), (0, 0.15, 0)),
         ("hips", "root", (0, 0, 0.9), (0, 0, 1.02)),
         ("spine", "hips", (0, 0, 1.02), (0, 0, 1.18)),
         ("chest", "spine", (0, 0, 1.18), (0, 0, 1.46)),
         ("neck", "chest", (0, 0, 1.46), (0, 0.05, 1.62)),
         ("head", "neck", (0, 0.05, 1.62), (0, 0.06, 1.82)),
         ("jaw", "head", (0, 0.05, 1.64), (0, 0.16, 1.6))]
    for side, s in (("r", 1), ("l", -1)):
        big = 1.0 if side == "r" else 1.1
        B += [("upper_arm_" + side, "chest", (s * 0.2, 0, 1.44), (s * 0.29 * big, 0, 1.05)),
              ("forearm_" + side, "upper_arm_" + side, (s * 0.29 * big, 0, 1.05), (s * 0.31 * big, 0.02, 0.68)),
              ("hand_" + side, "forearm_" + side, (s * 0.31 * big, 0.02, 0.68), (s * 0.31 * big, 0.06, 0.45)),
              ("thigh_" + side, "hips", (s * 0.1, 0, 0.9), (s * 0.13, 0, 0.5)),
              ("shin_" + side, "thigh_" + side, (s * 0.13, 0, 0.5), (s * 0.13, 0, 0.09)),
              ("foot_" + side, "shin_" + side, (s * 0.13, 0, 0.09), (s * 0.13, 0.15, 0.03))]
    bk.armature(B)
    bk.finish("mutante_med", tex_size=2048, bake=True, out_dir=OUT)

    # Encorvado: columna y pecho muy adelante, cabeza levantada para ver, rodillas dobladas,
    # brazos colgando por delante (el deforme casi toca el suelo).
    READY = {"spine": (-28, 0, 4), "chest": (-32, 0, 6), "neck": (45, 0, 0), "head": (22, 0, -12), "jaw": (-14, 0, 0),
             "upper_arm_l": (34, 14, 0), "forearm_l": (14, 0, 0), "hand_l": (10, 0, 0),
             "upper_arm_r": (26, -8, 0), "forearm_r": (30, 0, 0), "hand_r": (20, 0, 0),
             "thigh_r": (38, 0, 4), "shin_r": (-55, 0, 0), "foot_r": (18, 0, 0),
             "thigh_l": (30, 0, -4), "shin_l": (-48, 0, 0), "foot_l": (16, 0, 0), "root_pos": (0, -0.04, -0.12)}

    def P(**kw):
        d = dict(READY)
        d.update(kw)
        return d

    def lurch(ph, amp, knee, arm, bob, sway):
        """Paso torpe: bambolea el cuerpo de lado y arrastra el brazo pesado."""
        s = math.sin(ph)
        c = math.cos(ph)
        return P(thigh_r=(38 + s * amp, 0, 4), shin_r=(-55 - max(0.0, c) * knee, 0, 0),
                 thigh_l=(30 - s * amp, 0, -4), shin_l=(-48 - max(0.0, -c) * knee, 0, 0),
                 spine=(-28, s * sway, 4), chest=(-32, 0, 6 - s * 10), neck=(45, 0, s * 8), head=(22, -s * sway, -12),
                 upper_arm_l=(34 + s * arm * 0.4, 14, 0), forearm_l=(14, 0, 0),
                 upper_arm_r=(26 - s * arm, -8, 0), forearm_r=(30 + s * arm * 0.5, 0, 0), jaw=(-14 - abs(s) * 8, 0, 0),
                 root_pos=(0, -0.04, -0.12 - abs(c) * bob))

    def run_pose(ph):
        """Corre a cuatro patas apoyando el brazo deforme como una bestia."""
        s = math.sin(ph)
        c = math.cos(ph)
        return P(spine=(-40, 0, 0), chest=(-35 + s * 8, 0, s * 6), neck=(55, 0, 0), head=(20, 0, 0), jaw=(-25, 0, 0),
                 upper_arm_l=(60 + s * 45, 18, 0), forearm_l=(-10 + max(0.0, c) * 40, 0, 0),
                 upper_arm_r=(50 - s * 40, -10, 0), forearm_r=(10 + max(0.0, -c) * 40, 0, 0),
                 thigh_r=(50 - s * 40, 0, 4), shin_r=(-70 - max(0.0, -c) * 40, 0, 0),
                 thigh_l=(50 + s * 40, 0, -4), shin_l=(-70 - max(0.0, c) * 40, 0, 0),
                 root_pos=(0, -0.05, -0.28 + abs(s) * 0.08))

    idle = []
    for i in range(13):
        t = i * 0.25
        b = math.sin(t / 1.5 * 2 * math.pi)
        pose = P(chest=(-32 + b * 4, 0, 6), head=(22 - b * 4, 0, -12), jaw=(-14 - max(0.0, b) * 14, 0, 0), upper_arm_l=(34 + b * 3, 14, 0))
        if abs(t - 1.5) < 0.01:
            pose.update(head=(10, 0, 45), neck=(28, 0, 15), upper_arm_r=(50, -20, 0), forearm_r=(80, 0, 0))
        if abs(t - 1.75) < 0.01:
            pose.update(head=(10, 0, -35), neck=(28, 0, -10))
        idle.append((t, pose))
    bk.action("idle", idle, loop=True)
    bk.action("walk", [(i / 8 * 1.2, lurch(i / 8 * 2 * math.pi, 26, 30, 20, 0.04, 8)) for i in range(9)], loop=True)
    bk.action("run", [(i / 8 * 0.55, run_pose(i / 8 * 2 * math.pi)) for i in range(9)], loop=True)
    # Zarpazos: el brazo deforme sube por detrás y cae en diagonal; luego un revés torpe
    bk.action("slash", [(0.0, P()),
                        (0.4, P(upper_arm_l=(150, 50, 0), forearm_l=(40, 0, 0), chest=(-10, 0, 35), spine=(-14, 0, 12), head=(20, 0, -20), jaw=(-40, 0, 0), thigh_l=(20, 0, 0), root_pos=(0, -0.06, -0.1))),
                        (0.55, P(upper_arm_l=(30, -20, 0), forearm_l=(10, 0, 0), chest=(-40, 0, -30), spine=(-30, 0, -10), head=(26, 0, 10), jaw=(-30, 0, 0), thigh_l=(60, 0, 0), shin_l=(-60, 0, 0), thigh_r=(10, 0, 0), root_pos=(0, 0.18, -0.2))),
                        (0.78, P(upper_arm_l=(70, -50, 0), forearm_l=(30, 0, 0), upper_arm_r=(120, -60, 0), forearm_r=(30, 0, 0), chest=(-30, 0, -40), spine=(-26, 0, -12), head=(26, 0, 20), root_pos=(0, 0.2, -0.18))),
                        (0.95, P(upper_arm_r=(40, 40, 0), forearm_r=(10, 0, 0), upper_arm_l=(40, 20, 0), chest=(-38, 0, 30), spine=(-28, 0, 10), head=(26, 0, -14), thigh_r=(60, 0, 0), shin_r=(-60, 0, 0), root_pos=(0, 0.34, -0.2))),
                        (1.3, P(upper_arm_r=(30, 50, 0), upper_arm_l=(40, 20, 0), chest=(-42, 0, 34), spine=(-30, 0, 10), head=(20, 0, -20), jaw=(-40, 0, 0), root_pos=(0, 0.36, -0.22))),
                        (1.8, P())])
    # Frenesí: cuatro zarpazos alternados, cada vez más descontrolados
    fr = [(0.0, P())]
    for i, t in enumerate((0.5, 0.8, 1.1, 1.4)):
        arm = "upper_arm_l" if i % 2 == 0 else "upper_arm_r"
        other = "upper_arm_r" if i % 2 == 0 else "upper_arm_l"
        sgn = 1 if i % 2 == 0 else -1
        fr.append((t - 0.14, P(**{arm: (150, 40 * sgn, 0), other: (40, -10 * sgn, 0)}, chest=(-12, 0, 30 * sgn), spine=(-18, 0, 10 * sgn), jaw=(-50, 0, 0), head=(26, 0, -15 * sgn), root_pos=(0, 0.1 * i, -0.12))))
        fr.append((t, P(**{arm: (30, -30 * sgn, 0), other: (80, -20 * sgn, 0)}, chest=(-42, 0, -30 * sgn), spine=(-30, 0, -10 * sgn), jaw=(-30, 0, 0), head=(30, 0, 15 * sgn), thigh_r=(50, 0, 0), root_pos=(0, 0.1 * i + 0.12, -0.18))))
    fr.append((1.75, P(chest=(-45, 0, 0), spine=(-34, 0, 0), head=(5, 0, 0), jaw=(-50, 0, 0), upper_arm_l=(20, 20, 0), upper_arm_r=(20, -20, 0), root_pos=(0, 0.5, -0.2))))
    fr.append((2.2, P()))
    bk.action("frenzy", fr)
    bk.action("spit", [(0.0, P()),
                       (0.55, P(chest=(-5, 0, 0), spine=(-10, 0, 0), neck=(10, 0, 0), head=(-10, 0, 0), jaw=(-5, 0, 0), root_pos=(0, -0.08, -0.08))),
                       (0.8, P(chest=(-38, 0, 0), spine=(-28, 0, 0), neck=(45, 0, 0), head=(20, 0, 0), jaw=(-60, 0, 0), root_pos=(0, 0.1, -0.14))),
                       (1.0, P(chest=(-36, 0, 0), spine=(-28, 0, 0), neck=(45, 0, 0), head=(20, 0, 0), jaw=(-55, 0, 0), root_pos=(0, 0.1, -0.14))),
                       (1.4, P())])
    bk.action("roar", [(0.0, P()),
                       (0.4, P(spine=(0, 0, 0), chest=(10, 0, 0), neck=(20, 0, 0), head=(30, 0, 0), jaw=(-70, 0, 0), upper_arm_l=(40, 60, 0), forearm_l=(40, 0, 0), upper_arm_r=(40, -60, 0), forearm_r=(40, 0, 0), thigh_r=(20, 0, 4), thigh_l=(14, 0, -4), shin_r=(-30, 0, 0), shin_l=(-26, 0, 0), root_pos=(0, 0, -0.04))),
                       (0.8, P(spine=(2, 0, 0), chest=(14, 0, 6), neck=(22, 0, -8), head=(32, 0, 10), jaw=(-72, 0, 0), upper_arm_l=(45, 65, 0), forearm_l=(50, 0, 0), upper_arm_r=(45, -65, 0), forearm_r=(50, 0, 0), thigh_r=(20, 0, 4), thigh_l=(14, 0, -4), shin_r=(-30, 0, 0), shin_l=(-26, 0, 0), root_pos=(0, 0, -0.04))),
                       (1.2, P(spine=(2, 0, 0), chest=(14, 0, -6), neck=(22, 0, 8), head=(32, 0, -10), jaw=(-70, 0, 0), upper_arm_l=(45, 65, 0), forearm_l=(50, 0, 0), upper_arm_r=(45, -65, 0), forearm_r=(50, 0, 0), thigh_r=(20, 0, 4), thigh_l=(14, 0, -4), shin_r=(-30, 0, 0), shin_l=(-26, 0, 0), root_pos=(0, 0, -0.04))),
                       (1.7, P())])
    bk.action("stumble", [(0.0, P()),
                          (0.2, P(spine=(-50, 0, 15), chest=(-30, 0, 10), head=(40, 0, 20), upper_arm_l=(90, 40, 0), upper_arm_r=(80, -40, 0), thigh_r=(70, 0, 0), shin_r=(-100, 0, 0), root_pos=(0, 0.2, -0.35))),
                          (0.6, P(spine=(-60, 0, 20), chest=(-30, 0, 10), head=(40, 0, 30), upper_arm_l=(110, 40, 0), forearm_l=(-20, 0, 0), upper_arm_r=(100, -40, 0), thigh_r=(80, 0, 0), shin_r=(-120, 0, 0), thigh_l=(70, 0, 0), shin_l=(-110, 0, 0), root_pos=(0, 0.25, -0.45))),
                          (1.0, P(spine=(-40, 0, 10), head=(30, 0, -30))),
                          (1.3, P())])
    bk.action("hit", [(0.0, P()), (0.08, P(spine=(-5, 0, 10), chest=(0, 0, 14), head=(40, 0, 30), jaw=(-50, 0, 0), upper_arm_l=(10, 40, 0), upper_arm_r=(10, -40, 0), root_pos=(0, -0.14, -0.1))), (0.55, P())])
    bk.action("death", [(0.0, P()),
                        (0.2, P(spine=(0, 0, 0), chest=(10, 0, 0), head=(40, 0, 0), jaw=(-70, 0, 0), upper_arm_l=(40, 60, 0), upper_arm_r=(40, -60, 0))),
                        (0.7, P(spine=(-30, 0, 10), chest=(-20, 0, 0), head=(10, 0, 30), jaw=(-50, 0, 0), thigh_r=(85, 0, 0), shin_r=(-120, 0, 0), thigh_l=(80, 0, 0), shin_l=(-115, 0, 0), foot_r=(40, 0, 0), foot_l=(40, 0, 0), root_pos=(0, 0.05, -0.5))),
                        (1.2, P(root=(-84, 0, 0), spine=(-6, 0, 10), chest=(0, 0, 0), head=(30, 0, 40), jaw=(-40, 0, 0), upper_arm_l=(150, 50, 0), upper_arm_r=(100, -60, 0), thigh_r=(20, 0, 0), shin_r=(-40, 0, 0), thigh_l=(10, 0, 0), shin_l=(-30, 0, 0), root_pos=(0, 0.1, 0.12))),
                        (1.35, P(root=(-88, 0, 0), spine=(-4, 0, 10), head=(30, 0, 44), jaw=(-45, 0, 0), upper_arm_l=(155, 55, 0), upper_arm_r=(105, -65, 0), thigh_r=(18, 0, 0), shin_r=(-36, 0, 0), thigh_l=(8, 0, 0), shin_l=(-28, 0, 0), root_pos=(0, 0.1, 0.11)))])
    bk.set_pose(P())
    if PREVIEW:
        bk.render_preview(os.path.join(OUT, "preview_med.png"), (1.4, 2.8, 1.4), (0, 0, 0.95))
        bk.render_preview(os.path.join(OUT, "preview_med_atras.png"), (-1.8, -2.4, 1.6), (0, 0, 1.0))
        bk.render_preview(os.path.join(OUT, "preview_med_garra.png"), (2.4, 1.6, 1.3), (0, 0, 1.0), action_name="slash", frame=13)
    bk.set_pose({})
    bk.export(os.path.join(OUT, "mutante_med.glb"))


# ====================================================================== GRANDE (mole)
def build_grande():
    rng = start(43)
    # Torso descomunal, panza colgante, cabeza hundida entre los hombros
    blob("pelvis", 0.32, (0, 0, 1.25), (1.1, 0.85, 0.8), bone="hips", mat="piel", lumps=0.12)
    blob("panza", 0.36, (0, 0.12, 1.45), (1.05, 0.95, 0.95), bone="spine", mat="piel", lumps=0.15)
    blob("torso", 0.55, (0, 0.0, 2.05), (1.25, 0.85, 0.9), bone="chest", mat="piel", lumps=0.14)
    blob("trapecio_r", 0.3, (0.38, -0.05, 2.4), (1.1, 1.0, 0.9), bone="chest", mat="piel", lumps=0.18)
    blob("trapecio_l", 0.24, (-0.36, -0.05, 2.35), (1.0, 1.0, 0.9), bone="chest", mat="piel", lumps=0.18)
    blob("carne_pecho", 0.18, (0.2, 0.42, 2.0), (1.2, 0.5, 1.4), bone="chest", mat="carne", lumps=0.25)
    blob("carne_panza", 0.14, (-0.15, 0.45, 1.5), (1.3, 0.5, 1.0), bone="spine", mat="carne", lumps=0.3)
    # Sacos de pus en la espalda
    for i, (x, z, r) in enumerate([(0.25, 2.3, 0.15), (-0.2, 2.15, 0.12), (0.05, 1.95, 0.13), (0.35, 1.9, 0.1), (-0.3, 2.4, 0.1)]):
        blob("saco_base_%d" % i, r * 1.15, (x, -0.36 - r * 0.2, z), (1, 0.7, 1.1), bone="chest", mat="carne", lumps=0.2, segs=16)
        sphere("saco_%d" % i, r * 0.7, (x, -0.4 - r * 0.55, z), (1, 0.8, 1.1), bone="chest", mat="pus", segs=14)
    pustules("pus_torso", (0, 0.0, 2.05), 0.55, (1.25, 0.85, 0.9), [(0.7, 0.5, 0.2), (-0.6, 0.6, -0.2), (0.9, 0.2, -0.4), (-0.8, 0.3, 0.4), (0.2, 0.8, -0.5)], "chest", rng, size=(0.03, 0.06))
    # Varillas de metal y tubos clavados (restos del laboratorio)
    cyl("varilla_a", 0.015, 0.7, (0.1, -0.3, 2.25), (-40, 20, 0), bone="chest", mat="metal", verts=6)
    cyl("varilla_b", 0.012, 0.5, (-0.3, -0.25, 2.0), (-30, -35, 0), bone="chest", mat="metal", verts=6)
    for k in range(3):
        cable("tubo_%d" % k, [(-0.2 + k * 0.15, -0.35, 2.4), (-0.3 + k * 0.2, -0.55, 2.1), (-0.25 + k * 0.18, -0.5, 1.7)], 0.014, bone="chest", mat="goma", sag=0.05)
    cloth("bata_jirones", 0.9, 0.9, (0, -0.4, 2.55), (0, 0, 180), bone="chest", mat="bata", nx=16, ny=14, tatter=0.6, holes=0.08, flare=0.25, wave=0.04, seed=47)
    cloth("bata_frente", 0.5, 0.45, (0.25, 0.44, 2.3), (0, 0, -15), bone="chest", mat="bata", nx=10, ny=8, tatter=0.6, holes=0.07, flare=0.1, seed=48)
    # Cabeza pequeña, mandíbula enorme, ojos ciegos y uno que brilla
    limb("cuello", [(0, 0.15, 2.45), (0, 0.3, 2.52), (0, 0.38, 2.55)], [0.2, 0.17, 0.15], bone="neck", mat="piel", lumps=0.15)
    blob("cabeza", 0.16, (0, 0.45, 2.62), (0.95, 1.0, 0.95), bone="head", mat="piel", lumps=0.2)
    sphere("ojos", 0.025, (0.07, 0.6, 2.66), bone="head", mat="ojos", segs=10)
    sphere("ojo_ciego", 0.022, (-0.07, 0.6, 2.67), bone="head", mat="hueso", segs=10)
    blob("mandibula", 0.15, (0, 0.52, 2.48), (1.1, 0.95, 0.6), bone="jaw", mat="piel", lumps=0.15)
    teeth("diente_inf", (-0.1, 0.65, 2.52), (0.1, 0.65, 2.52), 8, 0.06, "jaw", False, rng)
    teeth("diente_sup", (-0.09, 0.6, 2.56), (0.09, 0.6, 2.56), 7, 0.045, "head", True, rng)
    # Brazo derecho: mazo de tumores y hueso que arrastra
    limb("hombro_r", [(0.55, 0, 2.35), (0.7, 0, 2.25), (0.78, 0, 2.05)], [0.3, 0.3, 0.26], bone="upper_arm_r", mat="piel", lumps=0.2)
    limb("brazo_r", [(0.78, 0, 2.1), (0.84, 0.02, 1.8), (0.88, 0.02, 1.5)], [0.26, 0.24, 0.22], bone="upper_arm_r", mat="piel", lumps=0.25)
    limb("antebrazo_r", [(0.88, 0.02, 1.5), (0.92, 0.05, 1.15), (0.95, 0.05, 0.8)], [0.24, 0.3, 0.32], bone="forearm_r", mat="piel", lumps=0.3)
    blob("mazo", 0.38, (0.96, 0.06, 0.6), (1.0, 1.0, 1.1), bone="hand_r", mat="piel", lumps=0.35)
    blob("mazo_carne", 0.2, (1.1, 0.25, 0.55), (1.0, 1.0, 1.0), bone="hand_r", mat="carne", lumps=0.35)
    for i in range(6):
        a = i / 6 * math.tau
        p = on_blob((0.96, 0.06, 0.6), 0.38, (1, 1, 1.1), (math.cos(a), math.sin(a), -0.3))
        spike("pua_%d" % i, p, (math.cos(a), math.sin(a), -0.3), 0.045, 0.24, "hand_r")
    pustules("pus_mazo", (0.96, 0.06, 0.6), 0.38, (1, 1, 1.1), [(0.3, 0.9, 0.3), (-0.7, 0.6, 0.0), (0.2, -0.8, 0.4), (0.8, -0.2, -0.3)], "hand_r", rng, size=(0.04, 0.07))
    # Brazo izquierdo atrofiado
    limb("brazo_l", [(-0.55, 0, 2.3), (-0.6, 0.05, 2.0), (-0.6, 0.1, 1.75)], [0.12, 0.1, 0.08], bone="upper_arm_l", mat="piel", lumps=0.2)
    limb("antebrazo_l", [(-0.6, 0.1, 1.75), (-0.58, 0.18, 1.55), (-0.55, 0.22, 1.4)], [0.08, 0.07, 0.06], bone="forearm_l", mat="piel", lumps=0.2)
    blob("mano_l", 0.07, (-0.55, 0.25, 1.33), (1, 0.8, 1.1), bone="hand_l", mat="piel")
    claws("garra_l", (-0.55, 0.28, 1.3), 3, 0.04, 0.1, "hand_l", r=0.016)
    # Piernas cortas y gruesas
    for side, s in (("l", -1), ("r", 1)):
        limb("muslo_" + side, [(s * 0.3, 0, 1.25), (s * 0.33, 0.04, 0.95), (s * 0.34, 0.02, 0.7)], [0.26, 0.24, 0.18], bone="thigh_" + side, mat="piel", lumps=0.15)
        limb("pierna_" + side, [(s * 0.34, 0.02, 0.7), (s * 0.34, -0.02, 0.4), (s * 0.34, 0, 0.14)], [0.18, 0.17, 0.14], bone="shin_" + side, mat="piel", lumps=0.15)
        blob("pie_" + side, 0.16, (s * 0.34, 0.1, 0.08), (1.0, 1.5, 0.55), bone="foot_" + side, mat="piel", lumps=0.1)
        claws("una_" + side, (s * 0.34, 0.32, 0.09), 3, 0.07, 0.08, "foot_" + side, r=0.025)
    blob("rodilla_carne", 0.09, (0.34, 0.15, 0.7), (1, 1, 1), bone="shin_r", mat="carne", lumps=0.3)

    B = [("root", "", (0, 0, 0), (0, 0.3, 0)),
         ("hips", "root", (0, 0, 1.25), (0, 0, 1.45)),
         ("spine", "hips", (0, 0, 1.45), (0, 0, 1.75)),
         ("chest", "spine", (0, 0, 1.75), (0, 0, 2.4)),
         ("neck", "chest", (0, 0.12, 2.4), (0, 0.35, 2.55)),
         ("head", "neck", (0, 0.35, 2.55), (0, 0.45, 2.8)),
         ("jaw", "head", (0, 0.4, 2.55), (0, 0.65, 2.45)),
         ("upper_arm_r", "chest", (0.55, 0, 2.35), (0.88, 0.02, 1.5)),
         ("forearm_r", "upper_arm_r", (0.88, 0.02, 1.5), (0.95, 0.05, 0.85)),
         ("hand_r", "forearm_r", (0.95, 0.05, 0.85), (0.96, 0.06, 0.3)),
         ("upper_arm_l", "chest", (-0.55, 0, 2.3), (-0.6, 0.1, 1.75)),
         ("forearm_l", "upper_arm_l", (-0.6, 0.1, 1.75), (-0.55, 0.22, 1.4)),
         ("hand_l", "forearm_l", (-0.55, 0.22, 1.4), (-0.55, 0.28, 1.25))]
    for side, s in (("r", 1), ("l", -1)):
        B += [("thigh_" + side, "hips", (s * 0.3, 0, 1.25), (s * 0.34, 0, 0.7)),
              ("shin_" + side, "thigh_" + side, (s * 0.34, 0, 0.7), (s * 0.34, 0, 0.14)),
              ("foot_" + side, "shin_" + side, (s * 0.34, 0, 0.14), (s * 0.34, 0.3, 0.06))]
    bk.armature(B)
    bk.finish("mutante_grande", tex_size=2048, bake=True, out_dir=OUT)

    READY = {"spine": (-12, 0, 0), "chest": (-14, 0, -4), "neck": (14, 0, 0), "head": (6, 0, 0), "jaw": (-10, 0, 0),
             "upper_arm_r": (10, -6, 0), "forearm_r": (16, 0, 0), "upper_arm_l": (20, 10, 0), "forearm_l": (40, 0, 0),
             "thigh_r": (16, 0, 6), "shin_r": (-22, 0, 0), "foot_r": (6, 0, 0), "thigh_l": (12, 0, -6), "shin_l": (-18, 0, 0), "foot_l": (6, 0, 0),
             "root_pos": (0, 0, -0.06)}

    def P(**kw):
        d = dict(READY)
        d.update(kw)
        return d

    def stomp(ph, amp, knee, bob, sway):
        s = math.sin(ph)
        c = math.cos(ph)
        return P(thigh_r=(16 + s * amp, 0, 6), shin_r=(-22 - max(0.0, c) * knee, 0, 0),
                 thigh_l=(12 - s * amp, 0, -6), shin_l=(-18 - max(0.0, -c) * knee, 0, 0),
                 hips=(0, s * sway, 0), spine=(-12, 0, s * 6), chest=(-14, 0, -4 - s * 8), head=(6, 0, s * 6),
                 upper_arm_r=(10 - s * 8, -6, 0), upper_arm_l=(20 + s * 12, 10, 0),
                 root_pos=(s * 0.04, 0, -0.06 - abs(c) * bob))

    idle = []
    for i in range(17):
        t = i * 0.25
        b = math.sin(t / 2.0 * 2 * math.pi)
        idle.append((t, P(chest=(-14 + b * 4, 0, -4), spine=(-12 - b * 2, 0, 0), head=(6 - b * 3, 0, 0), jaw=(-10 - max(0.0, b) * 12, 0, 0),
                          upper_arm_r=(10 - b * 3, -6, 0), root_pos=(0, 0, -0.06 + b * 0.02))))
    bk.action("idle", idle, loop=True)
    bk.action("walk", [(i / 8 * 1.5, stomp(i / 8 * 2 * math.pi, 20, 26, 0.06, 6)) for i in range(9)], loop=True)
    bk.action("run", [(i / 8 * 0.95, stomp(i / 8 * 2 * math.pi, 34, 44, 0.12, 10)) for i in range(9)], loop=True)
    # Aplastón: levanta el mazo con las dos manos por encima de la cabeza y lo deja caer
    bk.action("overhead", [(0.0, P()),
                           (0.5, P(upper_arm_r=(120, -10, 0), forearm_r=(40, 0, 0), upper_arm_l=(100, 20, 0), forearm_l=(60, 0, 0), chest=(4, 0, 0), spine=(0, 0, 0), head=(20, 0, 0), jaw=(-40, 0, 0), root_pos=(0, -0.05, -0.04))),
                           (1.0, P(upper_arm_r=(170, 0, 0), forearm_r=(30, 0, 0), upper_arm_l=(160, 20, 0), forearm_l=(50, 0, 0), chest=(14, 0, 0), spine=(6, 0, 0), head=(26, 0, 0), jaw=(-55, 0, 0), thigh_l=(-5, 0, -6), root_pos=(0, -0.1, -0.02))),
                           (1.2, P(upper_arm_r=(50, -5, 0), forearm_r=(4, 0, 0), upper_arm_l=(40, 10, 0), forearm_l=(20, 0, 0), chest=(-40, 0, 0), spine=(-26, 0, 0), head=(0, 0, 0), jaw=(-20, 0, 0), thigh_r=(40, 0, 6), shin_r=(-50, 0, 0), thigh_l=(-10, 0, -6), root_pos=(0, 0.3, -0.25))),
                           (1.8, P(upper_arm_r=(46, -5, 0), forearm_r=(4, 0, 0), upper_arm_l=(36, 10, 0), forearm_l=(20, 0, 0), chest=(-42, 0, 0), spine=(-28, 0, 0), head=(4, 0, 0), jaw=(-30, 0, 0), thigh_r=(40, 0, 6), shin_r=(-52, 0, 0), thigh_l=(-10, 0, -6), root_pos=(0, 0.3, -0.27))),
                           (2.3, P())])
    # Manotazo: barre de derecha a izquierda con el mazo y se pasa de vueltas
    bk.action("sweep", [(0.0, P()),
                        (0.7, P(upper_arm_r=(70, -60, 0), forearm_r=(20, 0, 0), chest=(-6, 0, -50), spine=(-8, 0, -20), head=(10, 0, 30), jaw=(-40, 0, 0), thigh_l=(20, 0, -6), root_pos=(0, -0.05, -0.08))),
                        (0.9, P(upper_arm_r=(80, 30, 0), forearm_r=(10, 0, 0), chest=(-18, 0, 45), spine=(-14, 0, 20), head=(6, 0, -25), jaw=(-30, 0, 0), thigh_r=(35, 0, 6), shin_r=(-40, 0, 0), root_pos=(0, 0.2, -0.12))),
                        (1.2, P(upper_arm_r=(60, 60, 0), forearm_r=(20, 0, 0), chest=(-20, 0, 65), spine=(-16, 0, 26), head=(6, 0, -30), jaw=(-35, 0, 0), thigh_r=(35, 0, 6), shin_r=(-42, 0, 0), root_pos=(0, 0.22, -0.14))),
                        (1.8, P())])
    bk.action("spit", [(0.0, P()),
                       (0.7, P(chest=(4, 0, 0), spine=(-2, 0, 0), neck=(-10, 0, 0), head=(-10, 0, 0), jaw=(-5, 0, 0), root_pos=(0, -0.1, -0.08))),
                       (1.0, P(chest=(-30, 0, 0), spine=(-20, 0, 0), neck=(30, 0, 0), head=(20, 0, 0), jaw=(-60, 0, 0), root_pos=(0, 0.12, -0.12))),
                       (1.6, P())])
    bk.action("roar", [(0.0, P()),
                       (0.5, P(spine=(4, 0, 0), chest=(16, 0, 0), neck=(26, 0, 0), head=(30, 0, 0), jaw=(-70, 0, 0), upper_arm_r=(60, -60, 0), forearm_r=(30, 0, 0), upper_arm_l=(60, 60, 0), forearm_l=(60, 0, 0), root_pos=(0, 0, -0.02))),
                       (1.0, P(spine=(6, 0, 0), chest=(18, 0, 8), neck=(28, 0, -10), head=(32, 0, 10), jaw=(-72, 0, 0), upper_arm_r=(70, -65, 0), forearm_r=(30, 0, 0), upper_arm_l=(70, 65, 0), forearm_l=(70, 0, 0), root_pos=(0, 0, -0.02))),
                       (1.5, P(spine=(6, 0, 0), chest=(18, 0, -8), neck=(28, 0, 10), head=(32, 0, -10), jaw=(-72, 0, 0), upper_arm_r=(70, -65, 0), forearm_r=(30, 0, 0), upper_arm_l=(70, 65, 0), forearm_l=(70, 0, 0), root_pos=(0, 0, -0.02))),
                       (2.0, P())])
    # Se estrella (después de una embestida contra la pared): se sacude la cabeza aturdido
    bk.action("stumble", [(0.0, P()),
                          (0.15, P(spine=(10, 0, 0), chest=(20, 0, 10), head=(30, 0, 20), jaw=(-50, 0, 0), upper_arm_r=(-20, -30, 0), upper_arm_l=(-10, 40, 0), thigh_r=(-10, 0, 6), root_pos=(0, -0.3, -0.05))),
                          (0.6, P(spine=(-10, 0, 0), chest=(-10, 0, 0), head=(-10, 0, 40), neck=(10, 0, 20), jaw=(-30, 0, 0), thigh_r=(40, 0, 6), shin_r=(-60, 0, 0), thigh_l=(30, 0, -6), shin_l=(-50, 0, 0), root_pos=(0, -0.2, -0.2))),
                          (0.9, P(head=(-10, 0, -40), neck=(10, 0, -20), thigh_r=(40, 0, 6), shin_r=(-60, 0, 0), thigh_l=(30, 0, -6), shin_l=(-50, 0, 0), root_pos=(0, -0.1, -0.2))),
                          (1.2, P(head=(-10, 0, 40), neck=(10, 0, 20), root_pos=(0, -0.05, -0.12))),
                          (1.6, P())])
    bk.action("hit", [(0.0, P()), (0.1, P(chest=(10, 0, 10), head=(20, 0, 20), jaw=(-40, 0, 0), root_pos=(0, -0.15, -0.06))), (0.6, P())])
    bk.action("death", [(0.0, P()),
                        (0.3, P(chest=(20, 0, 0), neck=(30, 0, 0), head=(30, 0, 0), jaw=(-70, 0, 0), upper_arm_r=(60, -60, 0), upper_arm_l=(60, 60, 0))),
                        (0.9, P(spine=(-25, 0, 10), chest=(-20, 0, 0), head=(-10, 0, 20), jaw=(-40, 0, 0), upper_arm_r=(20, -20, 0), thigh_r=(80, 0, 0), shin_r=(-110, 0, 0), thigh_l=(75, 0, 0), shin_l=(-105, 0, 0), root_pos=(0, 0.1, -0.7))),
                        (1.5, P(root=(-80, 0, 0), spine=(-6, 0, 10), chest=(0, 0, 0), head=(0, 0, 30), jaw=(-30, 0, 0), upper_arm_r=(140, -40, 0), upper_arm_l=(120, 50, 0), thigh_r=(20, 0, 0), shin_r=(-40, 0, 0), thigh_l=(10, 0, 0), shin_l=(-30, 0, 0), root_pos=(0, 0.2, 0.3))),
                        (1.7, P(root=(-84, 0, 0), spine=(-4, 0, 10), head=(0, 0, 32), jaw=(-34, 0, 0), upper_arm_r=(145, -42, 0), upper_arm_l=(125, 52, 0), thigh_r=(18, 0, 0), shin_r=(-36, 0, 0), thigh_l=(8, 0, 0), shin_l=(-28, 0, 0), root_pos=(0, 0.2, 0.28)))])
    bk.set_pose(P())
    if PREVIEW:
        bk.render_preview(os.path.join(OUT, "preview_grande.png"), (2.6, 5.0, 2.4), (0, 0, 1.6))
        bk.render_preview(os.path.join(OUT, "preview_grande_atras.png"), (-3.0, -4.4, 2.8), (0, 0, 1.7))
        bk.render_preview(os.path.join(OUT, "preview_grande_golpe.png"), (4.0, 2.0, 2.2), (0, 0, 1.5), action_name="overhead", frame=31)
    bk.set_pose({})
    bk.export(os.path.join(OUT, "mutante_grande.glb"))


for name, fn in (("peq", build_peq), ("med", build_med), ("grande", build_grande)):
    if not ONLY or name in ONLY:
        fn()
print("LISTO", OUT)
