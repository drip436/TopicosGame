"""Mecha de combate abandonado que sigue funcionando (enemigo "mecha", ~5 m).
Inspirado en titanes militares: torso blindado con ojo sensor, brazo cañón doble,
brazo garra, piernas con pistones y reactor en la espalda. Muy dañado y oxidado.

Uso:  blender -b --python arte/blender/mecha.py -- <carpeta_salida> [preview]
Animaciones: idle, walk, run, sweep (impacto 0.85), stomp (0.8), aim, hit, death.
"""
import sys
import os
import math

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, sphere, panel, bolts, cable, piston, vents, label, hazard

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/mecha")
PREVIEW = "preview" in argv
os.makedirs(OUT, exist_ok=True)

bk.reset(seed=23)
bk.define_materials({
    "pintura": dict(base=(0.065, 0.08, 0.045), rough=0.62, rust=1.15, wear=1.1, dirt=0.9, bare=(0.2, 0.2, 0.21), streaks=0.9, soot=0.6),
    "metal_oscuro": dict(base=(0.05, 0.05, 0.055), metal=0.6, rough=0.55, rust=0.55, wear=0.8, dirt=0.7, bare=(0.4, 0.4, 0.42), streaks=0.45, soot=0.3),
    "metal": dict(base=(0.5, 0.5, 0.52), metal=1.0, rough=0.45, rust=0.65, wear=0.4, dirt=0.6, bare=(0.8, 0.8, 0.82), streaks=0.4),
    "goma": dict(base=(0.03, 0.03, 0.03), rough=0.85, rust=0.0, wear=0.15, dirt=0.4, scratches=False),
    "acento": dict(base=(0.85, 0.42, 0.08), rough=0.6, rust=1.0, wear=1.0, dirt=0.7, bare=(0.2, 0.2, 0.2), streaks=0.5),
    "peligro": dict(base=(0.9, 0.72, 0.1), rough=0.6, rust=0.8, wear=1.0, dirt=0.7, bare=(0.18, 0.18, 0.18)),
    "ojos": {"emit": (1.0, 0.3, 0.1), "strength": 10.0},
})

# ------------------------------------------------------------------ cadera y torso
box("pelvis", (1.3, 0.9, 0.5), (0, 0, 2.9), bone="hips", mat="metal_oscuro")
panel("pelvis_frente", (1.0, 0.12, 0.4), (0, 0.48, 2.88), (-10, 0, 0), bone="hips", mat="pintura")
hazard("aviso_pelvis", (0, 0.555, 2.8), 0.7, 0.12, 8, (-10, 0, 0), bone="hips", depth=0.01)
for s in (-1, 1):
    sphere("cadera_art_%d" % s, 0.32, (s * 0.62, 0, 2.82), bone="hips", mat="metal")
    panel("cadera_placa_%d" % s, (0.2, 0.7, 0.5), (s * 0.78, 0, 2.9), (0, s * 10, 0), bone="hips", mat="pintura")
cyl("cintura", 0.35, 0.4, (0, -0.05, 3.25), bone="spine", mat="metal_oscuro", verts=24)
for k in range(3):
    cyl("cintura_aro_%d" % k, 0.4, 0.06, (0, -0.05, 3.12 + k * 0.12), bone="spine", mat="metal", verts=24)
for s in (-1, 1):
    piston("piston_cintura_%d" % s, (s * 0.45, 0.25, 3.0), (s * 0.55, 0.3, 3.5), 0.07, bone="spine")
box("torso", (2.2, 1.6, 1.4), (0, 0, 4.15), bone="chest", mat="metal_oscuro", taper=(1.05, 0.9))
panel("pecho", (1.9, 0.18, 0.9), (0, 0.82, 4.25), (5, 0, 0), bone="chest", mat="pintura", bevel=0.04)
panel("pecho_bajo", (1.5, 0.16, 0.45), (0, 0.78, 3.62), (-14, 0, 0), bone="chest", mat="pintura", bevel=0.03)
# Ojo sensor (como el de los titanes)
cyl("ojo_marco", 0.32, 0.12, (0, 0.95, 4.3), (90, 0, 0), bone="chest", mat="metal_oscuro", verts=32)
cyl("ojo_anillo", 0.26, 0.06, (0, 1.02, 4.3), (90, 0, 0), bone="chest", mat="metal", verts=32)
cyl("ojo", 0.17, 0.04, (0, 1.05, 4.3), (90, 0, 0), bone="chest", mat="ojos", verts=32)
label("serie", "MK-II  04", (-0.55, 0.93, 4.6), (95, 0, 180), size=0.16, bone="chest", mat="peligro")
label("unidad", "UNIV · SEGURIDAD", (0.0, 0.88, 3.85), (95, 0, 180), size=0.09, bone="chest", mat="metal_oscuro")
for s in (-1, 1):
    panel("costado_%d" % s, (0.18, 1.3, 1.1), (s * 1.12, 0, 4.15), bone="chest", mat="pintura", bevel=0.03)
    box("franja_%d" % s, (0.04, 0.4, 1.0), (s * 1.22, 0.4, 4.15), bone="chest", mat="acento", bevel=0.005)
    vents("ventila_%d" % s, (s * 1.22, -0.35, 4.45), 5, 0.12, (0.04, 0.5, 0.05), bone="chest")
bolts("tornillos_pecho", [(x, 0.92, z) for x in (-0.85, 0.85) for z in (3.9, 4.6)], (90, 0, 0), bone="chest", r=0.04, h=0.03)
# Impactos de bala en el blindaje
for i, (x, z) in enumerate([(0.55, 4.45), (0.7, 4.15), (-0.45, 3.95), (0.2, 3.7), (-0.75, 4.55)]):
    cyl("impacto_%d" % i, 0.045, 0.06, (x, 0.93, z), (90, 0, 0), bone="chest", mat="metal_oscuro", verts=8)
# Reactor en la espalda
box("reactor", (1.4, 0.8, 1.2), (0, -1.05, 4.15), bone="chest", mat="metal_oscuro")
panel("reactor_tapa", (1.2, 0.12, 1.0), (0, -1.5, 4.15), (0, 0, 180), bone="chest", mat="pintura", bevel=0.03)
for s in (-1, 1):
    cyl("escape_%d" % s, 0.14, 0.9, (s * 0.45, -1.3, 4.9), bone="chest", mat="metal", verts=16)
    cyl("escape_boca_%d" % s, 0.17, 0.12, (s * 0.45, -1.3, 5.35), bone="chest", mat="metal_oscuro", verts=16)
cyl("antena", 0.03, 1.2, (0.7, -0.6, 5.3), (8, 0, 0), bone="chest", mat="metal", verts=8)
cyl("antena_rota", 0.03, 0.45, (-0.7, -0.6, 5.0), (25, 30, 0), bone="chest", mat="metal", verts=8)
for k in range(5):
    cable("cable_espalda_%d" % k, [(-0.6 + k * 0.3, -1.45, 3.6), (-0.65 + k * 0.32, -1.55, 3.0 - (k % 2) * 0.3), (-0.6 + k * 0.3, -1.3, 2.6 - (k % 3) * 0.2)], 0.05, bone="chest", mat="goma" if k % 2 else "acento", sag=0.05)
# Cabeza: módulo sensor sobre el torso
box("cabeza", (0.6, 0.6, 0.35), (0, 0.2, 5.05), bone="head", mat="pintura", taper=(0.8, 0.8))
cyl("cabeza_lente", 0.1, 0.1, (0, 0.52, 5.05), (90, 0, 0), bone="head", mat="ojos", verts=16)

# ------------------------------------------------------------------ brazos
for side, s in (("r", 1), ("l", -1)):
    sphere("hombro_art_" + side, 0.42, (s * 1.45, 0, 4.45), bone="upper_arm_" + side, mat="metal")
    panel("hombrera_" + side, (0.9, 1.2, 0.35), (s * 1.5, 0, 4.85), (0, s * -15, 0), bone="upper_arm_" + side, mat="pintura", bevel=0.04)
    hazard("aviso_hombro_" + side, (s * 1.5, 0.61, 4.85), 0.6, 0.18, 6, (0, 0, 0), bone="upper_arm_" + side, depth=0.01)
    box("brazo_" + side, (0.45, 0.5, 1.0), (s * 1.5, 0, 3.9), bone="upper_arm_" + side, mat="metal_oscuro")
    panel("brazo_placa_" + side, (0.55, 0.2, 0.8), (s * 1.5, 0.27, 3.95), bone="upper_arm_" + side, mat="pintura")
    piston("piston_brazo_" + side, (s * 1.25, -0.3, 4.3), (s * 1.3, -0.3, 3.4), 0.06, bone="upper_arm_" + side)
    cyl("codo_" + side, 0.3, 0.5, (s * 1.5, 0, 3.3), (0, 90, 0), bone="forearm_" + side, mat="metal_oscuro", verts=24)
    cyl("codo_aro_" + side, 0.32, 0.08, (s * 1.5, 0, 3.3), (0, 90, 0), bone="forearm_" + side, mat="acento", verts=24)
# Brazo derecho: cañón doble
box("antebrazo_r", (0.6, 0.65, 1.1), (1.5, 0.05, 2.7), bone="forearm_r", mat="pintura")
box("cargador_r", (0.4, 0.4, 0.6), (1.85, -0.1, 2.75), bone="forearm_r", mat="metal_oscuro")
cable("cinta_balas", [(1.85, -0.1, 3.05), (1.95, 0.1, 3.25), (1.7, 0.2, 3.1)], 0.05, bone="forearm_r", mat="peligro")
for k in (-1, 1):
    cyl("canon_%d" % k, 0.11, 1.0, (1.5 + k * 0.15, 0.1, 1.85), bone="hand_r", mat="metal", verts=16)
    cyl("canon_boca_%d" % k, 0.14, 0.12, (1.5 + k * 0.15, 0.1, 1.35), bone="hand_r", mat="metal_oscuro", verts=16)
    cyl("canon_aro_%d" % k, 0.13, 0.05, (1.5 + k * 0.15, 0.1, 2.05), bone="hand_r", mat="acento", verts=16)
box("canon_soporte", (0.5, 0.3, 0.25), (1.5, 0.1, 2.2), bone="hand_r", mat="metal_oscuro")
# Brazo izquierdo: garra de tres dedos
box("antebrazo_l", (0.55, 0.6, 1.0), (-1.5, 0, 2.75), bone="forearm_l", mat="pintura")
piston("piston_ante_l", (-1.25, 0.32, 3.1), (-1.28, 0.32, 2.35), 0.05, bone="forearm_l")
box("muneca_l", (0.45, 0.45, 0.3), (-1.5, 0, 2.1), bone="hand_l", mat="metal_oscuro")
for k in range(3):
    a = (k - 1) * 0.22
    box("garra_%d_a" % k, (0.13, 0.18, 0.5), (-1.5 + a, 0.12, 1.75), (20, 0, (k - 1) * 8), bone="hand_l", mat="metal", bevel=0.02)
    box("garra_%d_b" % k, (0.11, 0.15, 0.4), (-1.5 + a * 1.1, 0.27, 1.38), (45, 0, (k - 1) * 10), bone="hand_l", mat="metal_oscuro", taper=(0.4, 0.5), bevel=0.015)
cable("cable_garra", [(-1.8, -0.2, 3.0), (-1.95, -0.3, 2.4), (-1.85, -0.2, 1.95)], 0.035, bone="forearm_l", sag=0.06)

# ------------------------------------------------------------------ piernas
for side, s in (("r", 1), ("l", -1)):
    box("muslo_" + side, (0.5, 0.55, 1.1), (s * 0.62, 0.05, 2.15), (-8, 0, 0), bone="thigh_" + side, mat="metal_oscuro")
    if side == "r":
        panel("muslo_placa_" + side, (0.6, 0.18, 0.95), (s * 0.62, 0.35, 2.2), (-8, 0, 0), bone="thigh_" + side, mat="pintura")
    else:
        # Placa arrancada: pistones y cables al aire
        for k in range(2):
            piston("muslo_piston_%d" % k, (s * (0.5 + k * 0.25), 0.35, 2.65), (s * (0.52 + k * 0.25), 0.4, 1.7), 0.05, bone="thigh_" + side)
        box("muslo_resto_" + side, (0.3, 0.12, 0.25), (s * 0.75, 0.38, 2.55), (-8, 20, 10), bone="thigh_" + side, mat="pintura")
        for k in range(3):
            cable("muslo_cable_%d" % k, [(s * (0.45 + k * 0.12), 0.32, 2.5), (s * (0.5 + k * 0.1), 0.48, 2.1), (s * (0.45 + k * 0.12), 0.35, 1.7)], 0.025, bone="thigh_" + side, mat="acento" if k == 1 else "goma", sag=0.03)
    cyl("rodilla_" + side, 0.3, 0.6, (s * 0.62, 0.15, 1.5), (0, 90, 0), bone="shin_" + side, mat="metal_oscuro", verts=24)
    panel("rodillera_" + side, (0.55, 0.22, 0.45), (s * 0.62, 0.42, 1.55), (12, 0, 0), bone="shin_" + side, mat="pintura")
    box("espinilla_" + side, (0.45, 0.5, 1.1), (s * 0.62, 0.05, 0.9), (6, 0, 0), bone="shin_" + side, mat="pintura")
    box("espinilla_franja_" + side, (0.47, 0.52, 0.08), (s * 0.62, 0.05, 1.2), (6, 0, 0), bone="shin_" + side, mat="acento", bevel=0.005)
    piston("piston_pierna_" + side, (s * 0.62, -0.32, 1.45), (s * 0.62, -0.25, 0.45), 0.07, bone="shin_" + side)
    box("tobillo_" + side, (0.4, 0.4, 0.3), (s * 0.62, 0, 0.35), bone="foot_" + side, mat="metal_oscuro")
    box("pie_" + side, (0.7, 1.1, 0.24), (s * 0.62, 0.2, 0.12), bone="foot_" + side, mat="metal_oscuro")
    panel("pie_placa_" + side, (0.6, 0.45, 0.16), (s * 0.62, 0.55, 0.2), (12, 0, 0), bone="foot_" + side, mat="pintura")
    for k in range(3):
        box("dedo_pie_%s_%d" % (side, k), (0.16, 0.3, 0.14), (s * 0.62 + (k - 1) * 0.22, 0.8, 0.08), (0, 0, 0), bone="foot_" + side, mat="metal", bevel=0.02)

# ------------------------------------------------------------------ esqueleto
B = [
    ("root", "", (0, 0, 0), (0, 0.5, 0)),
    ("hips", "root", (0, 0, 2.8), (0, 0, 3.05)),
    ("spine", "hips", (0, 0, 3.05), (0, 0, 3.45)),
    ("chest", "spine", (0, 0, 3.45), (0, 0, 4.9)),
    ("head", "chest", (0, 0.1, 4.9), (0, 0.1, 5.3)),
]
for side, s in (("r", 1), ("l", -1)):
    B += [
        ("upper_arm_" + side, "chest", (s * 1.45, 0, 4.45), (s * 1.5, 0, 3.32)),
        ("forearm_" + side, "upper_arm_" + side, (s * 1.5, 0, 3.3), (s * 1.5, 0, 2.25)),
        ("hand_" + side, "forearm_" + side, (s * 1.5, 0, 2.22), (s * 1.5, 0, 1.4)),
        ("thigh_" + side, "hips", (s * 0.62, 0, 2.78), (s * 0.62, 0.15, 1.52)),
        ("shin_" + side, "thigh_" + side, (s * 0.62, 0.15, 1.5), (s * 0.62, 0, 0.38)),
        ("foot_" + side, "shin_" + side, (s * 0.62, 0, 0.36), (s * 0.62, 0.7, 0.1)),
    ]
bk.armature(B)
# Boca del cañón (punto de disparo), pegada al hueso de la mano derecha
import bpy
mz = bpy.data.objects.new("muzzle", None)
bpy.context.scene.collection.objects.link(mz)
mz.location = (1.5, 0.1, 1.25)
body = bk.finish("mecha", tex_size=2048, bake=True, out_dir=OUT)
mz.parent = bk.ARM
mz.parent_type = "BONE"
mz.parent_bone = "hand_r"
mz.matrix_world = __import__("mathutils").Matrix.Translation((1.5, 0.1, 1.25))

# ------------------------------------------------------------------ animaciones
# Pasos pesados: el cuerpo baja al apoyar y el torso se balancea.
READY = {"spine": (-4, 0, 0), "chest": (-3, 0, 0), "upper_arm_r": (25, -6, 0), "forearm_r": (35, 0, 0),
         "upper_arm_l": (12, 6, 0), "forearm_l": (25, 0, 0), "thigh_r": (8, 0, 0), "shin_r": (-14, 0, 0),
         "thigh_l": (8, 0, 0), "shin_l": (-14, 0, 0), "foot_r": (6, 0, 0), "foot_l": (6, 0, 0), "root_pos": (0, 0, -0.08)}


def P(**kw):
    d = dict(READY)
    for k, v in kw.items():
        d[k] = v
    return d


def step_pose(ph, amp, knee, arm, bob, sway):
    s = math.sin(ph)
    c = math.cos(ph)
    return P(thigh_r=(8 + s * amp, 0, 0), thigh_l=(8 - s * amp, 0, 0),
             shin_r=(-14 - max(0.0, c) * knee, 0, 0), shin_l=(-14 - max(0.0, -c) * knee, 0, 0),
             foot_r=(6 + max(0.0, -s) * 10, 0, 0), foot_l=(6 + max(0.0, s) * 10, 0, 0),
             upper_arm_r=(25 - s * arm, -6, 0), upper_arm_l=(12 + s * arm, 6, 0),
             spine=(-4, 0, s * sway), chest=(-3 + abs(c) * 2, 0, -s * sway * 1.5), head=(0, 0, s * 6),
             root_pos=(0, 0, -0.08 - (1.0 - abs(c)) * bob))


bk.action("idle", [(t, P(chest=(-3 + math.sin(t * math.pi) * 1.5, 0, math.sin(t * math.pi * 0.5) * 3), head=(0, 0, math.sin(t * math.pi * 0.5) * 25),
                         upper_arm_r=(25 + math.sin(t * math.pi) * 2, -6, 0))) for t in (0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0)], loop=True)
bk.action("walk", [(i / 8.0 * 1.8, step_pose(i / 8.0 * 2 * math.pi, 22, 30, 8, 0.12, 5)) for i in range(9)], loop=True)
bk.action("run", [(i / 8.0 * 1.25, step_pose(i / 8.0 * 2 * math.pi, 32, 50, 16, 0.2, 7)) for i in range(9)], loop=True)
# Barrido con la garra (impacto 0.85)
bk.action("sweep", [
    (0.0, P()),
    (0.6, P(upper_arm_l=(75, 55, 0), forearm_l=(20, 0, 0), chest=(0, 0, 45), spine=(0, 0, 15), head=(0, 0, -25), thigh_r=(20, 0, 0), shin_r=(-30, 0, 0), root_pos=(0, -0.1, -0.15))),
    (0.75, P(upper_arm_l=(78, 58, 0), forearm_l=(22, 0, 0), chest=(0, 0, 50), spine=(0, 0, 17), head=(0, 0, -28), thigh_r=(20, 0, 0), shin_r=(-30, 0, 0), root_pos=(0, -0.1, -0.16))),
    (0.85, P(upper_arm_l=(80, -20, 0), forearm_l=(5, 0, 0), chest=(-8, 0, -50), spine=(-4, 0, -18), head=(0, 0, 15), thigh_l=(28, 0, 0), shin_l=(-30, 0, 0), root_pos=(0, 0.3, -0.2))),
    (1.1, P(upper_arm_l=(70, -40, 0), forearm_l=(10, 0, 0), chest=(-10, 0, -65), spine=(-6, 0, -22), head=(0, 0, 20), thigh_l=(28, 0, 0), shin_l=(-32, 0, 0), root_pos=(0, 0.32, -0.22))),
    (1.9, P()),
])
# Pisotón (impacto 0.8): levanta la pierna, se balancea y la deja caer
bk.action("stomp", [
    (0.0, P()),
    (0.55, P(thigh_r=(70, 0, 0), shin_r=(-75, 0, 0), foot_r=(20, 0, 0), chest=(8, 0, 0), spine=(4, 0, 0), upper_arm_r=(10, -30, 0), upper_arm_l=(5, 30, 0), root_pos=(0, -0.1, 0.05))),
    (0.7, P(thigh_r=(74, 0, 0), shin_r=(-78, 0, 0), foot_r=(22, 0, 0), chest=(10, 0, 0), spine=(5, 0, 0), upper_arm_r=(8, -32, 0), upper_arm_l=(3, 32, 0), root_pos=(0, -0.1, 0.07))),
    (0.8, P(thigh_r=(25, 0, 0), shin_r=(-10, 0, 0), foot_r=(-5, 0, 0), chest=(-12, 0, 0), spine=(-6, 0, 0), upper_arm_r=(30, -15, 0), upper_arm_l=(20, 15, 0), root_pos=(0, 0.35, -0.25))),
    (1.15, P(thigh_r=(25, 0, 0), shin_r=(-14, 0, 0), chest=(-14, 0, 0), spine=(-6, 0, 0), root_pos=(0, 0.35, -0.28))),
    (1.9, P()),
])
# Cañón: apunta, dispara con retroceso (bucle)
bk.action("aim", [(0.0, P(upper_arm_r=(88, -4, 0), forearm_r=(4, 0, 0), chest=(0, 0, 12), spine=(0, 0, 4))),
                  (0.06, P(upper_arm_r=(97, -4, 0), forearm_r=(-6, 0, 0), chest=(4, 0, 12), spine=(2, 0, 4), root_pos=(0, -0.05, -0.08))),
                  (0.16, P(upper_arm_r=(88, -4, 0), forearm_r=(4, 0, 0), chest=(0, 0, 12), spine=(0, 0, 4)))], loop=True)
bk.action("hit", [(0.0, P()), (0.12, P(chest=(12, 0, 8), spine=(6, 0, 4), head=(0, 0, -20), root_pos=(0, -0.15, -0.1))), (0.6, P())])
# Muerte: falla una pierna, cae de rodillas y se desploma hacia el frente
bk.action("death", [
    (0.0, P()),
    (0.4, P(thigh_l=(60, 0, 0), shin_l=(-100, 0, 0), chest=(8, 0, -10), spine=(0, 0, -8), head=(0, 0, 30), upper_arm_r=(-10, -35, 0), upper_arm_l=(-10, 35, 0), root_pos=(0, 0, -0.6))),
    (0.9, P(thigh_l=(80, 0, 0), shin_l=(-120, 0, 0), thigh_r=(75, 0, 0), shin_r=(-115, 0, 0), chest=(-20, 0, -6), spine=(-10, 0, -4), head=(0, 0, 40), upper_arm_r=(30, -20, 0), upper_arm_l=(20, 20, 0), root_pos=(0, 0.2, -1.25))),
    (1.6, P(root=(-70, 0, 0), thigh_l=(40, 0, 0), shin_l=(-60, 0, 0), thigh_r=(35, 0, 0), shin_r=(-55, 0, 0), chest=(-10, 0, 0), head=(0, 0, 45), upper_arm_r=(140, -40, 0), upper_arm_l=(130, 40, 0), root_pos=(0, 0.6, 0.4))),
    (1.8, P(root=(-74, 0, 0), thigh_l=(40, 0, 0), shin_l=(-60, 0, 0), thigh_r=(35, 0, 0), shin_r=(-55, 0, 0), chest=(-8, 0, 0), head=(0, 0, 45), upper_arm_r=(145, -42, 0), upper_arm_l=(135, 42, 0), root_pos=(0, 0.6, 0.38))),
])

bk.set_pose(P())
if PREVIEW:
    bk.render_preview(os.path.join(OUT, "preview_front.png"), (5.0, 9.5, 4.0), (0, 0, 2.8), size=(900, 1100))
    bk.render_preview(os.path.join(OUT, "preview_back.png"), (-6.0, -8.5, 4.5), (0, 0, 3.0), size=(900, 1100))
    bk.render_preview(os.path.join(OUT, "preview_stomp.png"), (8.5, 3.0, 3.5), (0, 0, 2.6), size=(900, 1100), action_name="stomp", frame=22)
bk.set_pose({})
bk.export(os.path.join(OUT, "mecha.glb"))
print("LISTO", OUT)
