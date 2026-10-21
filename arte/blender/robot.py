"""Robot humanoide del campus (enemigo "robot" y base de los robots medianos).
Inspirado en robots industriales blindados: placas blancas gastadas, articulaciones
negras, actuadores cilíndricos en los hombros, visor y cables expuestos.

Uso:  blender -b --python arte/blender/robot.py -- <carpeta_salida> [preview]
Genera robot.glb (+ texturas horneadas) con esqueleto y animaciones:
  idle, walk, run, jab, lunge, overhead, sweep, slash, thrust, aim, hit, death
Los tiempos de impacto de cada ataque están en la sección de animaciones (y en enemy.gd).
"""
import sys
import os
import math

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, sphere, panel, bolts, cable, piston, vents, label, hazard

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/robot")
PREVIEW = "preview" in argv
os.makedirs(OUT, exist_ok=True)

bk.reset(seed=11)
bk.define_materials({
    "pintura": dict(base=(0.68, 0.68, 0.64), rough=0.55, rust=1.45, wear=1.15, dirt=1.0, bare=(0.22, 0.22, 0.24), streaks=0.95, soot=0.7),
    "metal_oscuro": dict(base=(0.08, 0.08, 0.09), metal=0.6, rough=0.55, rust=1.0, wear=0.8, dirt=0.8, bare=(0.42, 0.42, 0.44), streaks=0.6, soot=0.5),
    "metal": dict(base=(0.55, 0.55, 0.56), metal=1.0, rough=0.45, rust=1.0, wear=0.4, dirt=0.6, bare=(0.8, 0.8, 0.82), streaks=0.5),
    "goma": dict(base=(0.03, 0.03, 0.03), rough=0.85, rust=0.0, wear=0.15, dirt=0.3, scratches=False),
    "acento": dict(base=(0.8, 0.38, 0.08), rough=0.6, rust=1.0, wear=1.0, dirt=0.7, bare=(0.2, 0.2, 0.2), streaks=0.6),
    "peligro": dict(base=(0.9, 0.72, 0.1), rough=0.55, rust=0.35, wear=0.9, dirt=0.5, bare=(0.18, 0.18, 0.18)),
    "ojos": {"emit": (1.0, 0.45, 0.12), "strength": 8.0},
})

# ------------------------------------------------------------------ torso y cadera
box("pelvis", (0.34, 0.24, 0.14), (0, 0, 0.9), bone="hips", mat="metal_oscuro")
for s in (-1, 1):
    panel("cadera_placa_%d" % s, (0.1, 0.2, 0.13), (s * 0.19, 0, 0.88), (0, s * 12, 0), bone="hips", mat="pintura")
    sphere("cadera_art_%d" % s, 0.06, (s * 0.12, 0, 0.84), bone="hips", mat="metal")
panel("faldon", (0.24, 0.05, 0.12), (0, 0.13, 0.86), (-8, 0, 0), bone="hips", mat="pintura")
# Cintura expuesta: columna, pistones y cables
cyl("columna", 0.055, 0.2, (0, -0.02, 1.03), bone="spine", mat="metal_oscuro")
for k in range(4):
    cyl("vertebra_%d" % k, 0.07, 0.025, (0, -0.02, 0.96 + k * 0.045), bone="spine", mat="metal", verts=12)
for s in (-1, 1):
    piston("piston_cintura_%d" % s, (s * 0.1, 0.05, 0.95), (s * 0.12, 0.06, 1.14), 0.016, bone="spine")
cable("cable_cintura_a", [(-0.08, -0.12, 1.15), (-0.12, -0.16, 1.03), (-0.06, -0.13, 0.93)], 0.012, bone="spine", sag=0.03)
cable("cable_cintura_b", [(0.06, -0.12, 1.15), (0.13, -0.15, 1.05), (0.07, -0.12, 0.93)], 0.01, bone="spine", sag=0.04)
cable("cable_cintura_c", [(0.0, -0.13, 1.16), (0.02, -0.19, 1.04), (0.0, -0.12, 0.92)], 0.014, bone="spine", mat="acento", sag=0.02)

# Pecho: núcleo oscuro + blindaje
box("pecho_nucleo", (0.44, 0.3, 0.3), (0, 0, 1.27), bone="chest", mat="metal_oscuro")
panel("pecho_placa_a", (0.27, 0.07, 0.2), (-0.12, 0.16, 1.32), (6, 0, 2), bone="chest", mat="pintura")
panel("pecho_placa_b", (0.21, 0.07, 0.19), (0.135, 0.165, 1.315), (9, -4, -5), bone="chest", mat="pintura")
for k in range(3):
    cable("grieta_cable_%d" % k, [(0.015, 0.17, 1.4 - k * 0.05), (0.03 + k * 0.01, 0.21, 1.36 - k * 0.05), (0.02, 0.2, 1.33 - k * 0.05)], 0.005, bone="chest", mat="acento" if k == 1 else "goma")
panel("abdomen_placa", (0.32, 0.06, 0.1), (0, 0.15, 1.15), (-6, 0, 0), bone="chest", mat="pintura")
for s in (-1, 1):
    panel("pecho_lado_%d" % s, (0.07, 0.28, 0.24), (s * 0.24, 0.0, 1.27), (0, 0, 0), bone="chest", mat="pintura")
    box("franja_%d" % s, (0.012, 0.06, 0.16), (s * 0.276, 0.06, 1.27), bone="chest", mat="acento", bevel=0.002)
    box("yugo_%d" % s, (0.14, 0.22, 0.06), (s * 0.2, 0, 1.43), (0, s * -10, 0), bone="chest", mat="metal_oscuro")
box("cuello_base", (0.2, 0.18, 0.05), (0, 0, 1.44), bone="chest", mat="metal_oscuro")
# Detalles del pecho: collar, rejilla central, número de serie y avisos
panel("collar", (0.36, 0.06, 0.07), (0, 0.15, 1.42), (25, 0, 0), bone="chest", mat="pintura")
vents("rejilla", (0, 0.205, 1.36), 4, 0.022, (0.12, 0.006, 0.008), bone="chest")
label("serie", "U-07", (0.16, 0.2, 1.24), (96, 0, 180), size=0.045, bone="chest", mat="metal_oscuro")
hazard("aviso_abdomen", (0, 0.183, 1.15), 0.22, 0.045, 6, (-6, 0, 0), bone="chest")
hazard("aviso_mochila", (0, -0.293, 1.2), 0.22, 0.04, 6, (0, 0, 0), bone="chest")
bolts("tornillos_pecho", [(x, 0.198, z) for x in (-0.21, 0.21) for z in (1.25, 1.39)], (90, 0, 0), bone="chest")
# Mochila con ventilas y cables
box("mochila", (0.34, 0.12, 0.26), (0, -0.2, 1.28), bone="chest", mat="metal_oscuro")
panel("mochila_tapa", (0.28, 0.04, 0.2), (0, -0.27, 1.29), (0, 0, 180), bone="chest", mat="pintura")
vents("ventila", (0, -0.29, 1.36), 5, 0.035, (0.2, 0.01, 0.012), bone="chest")
cable("cable_mochila", [(0.12, -0.25, 1.36), (0.22, -0.24, 1.42), (0.28, -0.1, 1.42)], 0.012, bone="chest", sag=0.0)
cable("cable_mochila2", [(-0.12, -0.25, 1.36), (-0.22, -0.24, 1.42), (-0.28, -0.1, 1.42)], 0.012, bone="chest", sag=0.0)

# ------------------------------------------------------------------ cuello y cabeza
cyl("cuello", 0.038, 0.1, (0, 0, 1.49), bone="neck", mat="metal")
for s in (-1, 1):
    piston("piston_cuello_%d" % s, (s * 0.06, 0.02, 1.45), (s * 0.05, 0.03, 1.53), 0.01, bone="neck")
box("casco", (0.17, 0.21, 0.15), (0, 0.01, 1.6), bone="head", mat="pintura", taper=(0.8, 0.85))
box("casco_cresta", (0.05, 0.2, 0.04), (0, 0.0, 1.69), bone="head", mat="pintura")
for s in (-1, 1):
    panel("casco_lado_%d" % s, (0.03, 0.17, 0.11), (s * 0.085, 0.0, 1.61), (0, 0, 0), bone="head", mat="pintura", bevel=0.01)
box("visor_marco", (0.17, 0.03, 0.085), (0, 0.1, 1.6), (-8, 0, 0), bone="head", mat="pintura", bevel=0.008)
box("visor", (0.15, 0.04, 0.07), (0, 0.11, 1.6), (-8, 0, 0), bone="head", mat="metal_oscuro")
box("ojos", (0.12, 0.012, 0.018), (0, 0.133, 1.605), (-8, 0, 0), bone="head", mat="ojos", bevel=0.002)
box("mandibula", (0.12, 0.08, 0.04), (0, 0.07, 1.53), bone="head", mat="metal_oscuro")
for s in (-1, 1):
    cyl("oreja_%d" % s, 0.035, 0.03, (s * 0.095, 0.0, 1.6), (0, 90, 0), bone="head", mat="metal_oscuro", verts=16)
    cyl("oreja_anillo_%d" % s, 0.025, 0.035, (s * 0.1, 0.0, 1.6), (0, 90, 0), bone="head", mat="acento", verts=16)
cyl("antena", 0.006, 0.08, (0.06, -0.06, 1.7), (-10, 0, 0), bone="head", mat="metal", verts=6)
cyl("antena_doblada", 0.006, 0.09, (0.09, -0.08, 1.77), (-20, 55, 0), bone="head", mat="metal", verts=6)

# ------------------------------------------------------------------ brazos
for side, s in (("r", 1), ("l", -1)):
    # Actuador del hombro
    cyl("hombro_act_" + side, 0.1, 0.12, (s * 0.33, 0, 1.34), (0, 90, 0), bone="upper_arm_" + side, mat="metal_oscuro", verts=28)
    cyl("hombro_tapa_" + side, 0.075, 0.03, (s * 0.4, 0, 1.34), (0, 90, 0), bone="upper_arm_" + side, mat="metal", verts=28)
    cyl("hombro_anillo_" + side, 0.105, 0.02, (s * 0.37, 0, 1.34), (0, 90, 0), bone="upper_arm_" + side, mat="acento", verts=28)
    if side == "r":
        panel("hombrera_" + side, (0.2, 0.26, 0.06), (s * 0.35, 0, 1.45), (0, s * -18, 0), bone="upper_arm_" + side, mat="pintura")
        panel("hombrera2_" + side, (0.16, 0.22, 0.04), (s * 0.38, 0, 1.41), (0, s * -35, 0), bone="upper_arm_" + side, mat="pintura")
        label("rotulo_hombro", "SEC", (s * 0.37, 0.135, 1.44), (90, 0, 180), size=0.04, bone="upper_arm_" + side, mat="metal_oscuro")
    else:
        # Hombrera arrancada: quedan cables cortados
        for k in range(4):
            cable("cable_roto_%d" % k, [(s * 0.3, -0.05 + k * 0.03, 1.42), (s * (0.36 + k * 0.02), -0.06 + k * 0.04, 1.49 + k * 0.01), (s * (0.4 + k * 0.03), -0.02 + k * 0.03, 1.47 - k * 0.02)],
                  0.006, bone="upper_arm_" + side, mat="acento" if k % 2 else "goma")
        box("hombrera_rota_" + side, (0.08, 0.1, 0.04), (s * 0.33, 0.06, 1.43), (20, s * -30, 15), bone="upper_arm_" + side, mat="pintura")
    # Brazo
    box("brazo_nucleo_" + side, (0.08, 0.09, 0.26), (s * 0.37, 0, 1.17), bone="upper_arm_" + side, mat="metal_oscuro")
    panel("brazo_placa_" + side, (0.11, 0.07, 0.2), (s * 0.375, 0.04, 1.17), bone="upper_arm_" + side, mat="pintura")
    piston("piston_brazo_" + side, (s * 0.33, -0.05, 1.25), (s * 0.36, -0.05, 1.04), 0.012, bone="upper_arm_" + side)
    # Codo
    cyl("codo_" + side, 0.055, 0.11, (s * 0.375, 0, 1.02), (0, 90, 0), bone="forearm_" + side, mat="metal_oscuro", verts=20)
    cyl("codo_anillo_" + side, 0.06, 0.02, (s * 0.375, 0, 1.02), (0, 90, 0), bone="forearm_" + side, mat="metal", verts=20)
    # Antebrazo
    box("antebrazo_nucleo_" + side, (0.08, 0.08, 0.24), (s * 0.38, -0.01, 0.88), bone="forearm_" + side, mat="metal_oscuro")
    panel("antebrazo_placa_" + side, (0.12, 0.1, 0.2), (s * 0.385, 0.02, 0.89), bone="forearm_" + side, mat="pintura", )
    box("antebrazo_franja_" + side, (0.125, 0.105, 0.02), (s * 0.385, 0.02, 0.96), bone="forearm_" + side, mat="acento", bevel=0.003)
    bolts("tornillos_ante_" + side, [(s * 0.385, 0.073, 0.82), (s * 0.385, 0.073, 0.95)], (90, 0, 0), bone="forearm_" + side)
    # Mano
    box("palma_" + side, (0.075, 0.05, 0.085), (s * 0.385, 0.0, 0.7), bone="hand_" + side, mat="metal_oscuro")
    for f in range(4):
        fx = s * 0.385 + (f - 1.5) * 0.019
        box("dedo_%s_%d_a" % (side, f), (0.016, 0.022, 0.04), (fx, 0.01, 0.635), (10, 0, 0), bone="hand_" + side, mat="metal", bevel=0.003)
        box("dedo_%s_%d_b" % (side, f), (0.014, 0.02, 0.035), (fx, 0.022, 0.6), (30, 0, 0), bone="hand_" + side, mat="metal_oscuro", bevel=0.003)
    box("pulgar_" + side, (0.016, 0.02, 0.045), (s * 0.355, 0.035, 0.68), (40, 0, s * 20), bone="hand_" + side, mat="metal", bevel=0.003)

# Cable suelto colgando del antebrazo izquierdo
cable("cable_suelto", [(-0.42, -0.04, 0.95), (-0.47, -0.06, 0.82), (-0.45, -0.02, 0.72), (-0.47, 0.0, 0.66)], 0.008, bone="forearm_l", sag=0.02)

# ------------------------------------------------------------------ piernas
for side, s in (("r", 1), ("l", -1)):
    cyl("muslo_nucleo_" + side, 0.06, 0.34, (s * 0.12, 0, 0.66), bone="thigh_" + side, mat="metal_oscuro", verts=16)
    panel("muslo_placa_" + side, (0.15, 0.06, 0.26), (s * 0.12, 0.065, 0.67), (-3, 0, 0), bone="thigh_" + side, mat="pintura")
    panel("muslo_lado_" + side, (0.04, 0.12, 0.22), (s * 0.19, 0.0, 0.67), bone="thigh_" + side, mat="pintura")
    piston("piston_muslo_" + side, (s * 0.12, -0.07, 0.8), (s * 0.12, -0.07, 0.52), 0.015, bone="thigh_" + side)
    cyl("rodilla_" + side, 0.06, 0.13, (s * 0.12, 0, 0.47), (0, 90, 0), bone="shin_" + side, mat="metal_oscuro", verts=20)
    panel("rodillera_" + side, (0.12, 0.05, 0.1), (s * 0.12, 0.07, 0.47), (8, 0, 0), bone="shin_" + side, mat="pintura")
    box("espinilla_nucleo_" + side, (0.08, 0.09, 0.32), (s * 0.12, -0.01, 0.27), bone="shin_" + side, mat="metal_oscuro")
    if side == "r":
        panel("espinilla_placa_" + side, (0.13, 0.08, 0.28), (s * 0.12, 0.04, 0.28), (-2, 0, 0), bone="shin_" + side, mat="pintura")
        for k in range(3):
            cable("rodilla_cable_%d" % k, [(s * (0.07 + k * 0.03), 0.04, 0.53), (s * (0.05 + k * 0.035), 0.09, 0.45), (s * (0.08 + k * 0.02), 0.06, 0.38)], 0.006, bone="shin_" + side, mat="goma", sag=0.01)
    else:
        # Placa arrancada: quedan los soportes y el cableado expuesto
        box("espinilla_soporte_" + side, (0.11, 0.02, 0.04), (s * 0.12, 0.04, 0.4), bone="shin_" + side, mat="metal")
        box("espinilla_resto_" + side, (0.06, 0.05, 0.08), (s * 0.15, 0.05, 0.16), (0, 0, 20), bone="shin_" + side, mat="pintura")
        for k in range(4):
            cable("espinilla_cable_%d" % k, [(s * (0.09 + k * 0.02), 0.03, 0.42), (s * (0.08 + k * 0.022), 0.06, 0.28), (s * (0.1 + k * 0.015), 0.03, 0.14)], 0.006, bone="shin_" + side, mat="acento" if k % 2 else "goma", sag=0.0)
    box("espinilla_franja_" + side, (0.135, 0.085, 0.02), (s * 0.12, 0.04, 0.37), bone="shin_" + side, mat="acento", bevel=0.003)
    piston("piston_pantorrilla_" + side, (s * 0.12, -0.08, 0.42), (s * 0.12, -0.07, 0.14), 0.014, bone="shin_" + side)
    box("tobillo_" + side, (0.08, 0.08, 0.05), (s * 0.12, 0, 0.1), bone="foot_" + side, mat="metal_oscuro")
    box("pie_" + side, (0.13, 0.24, 0.06), (s * 0.12, 0.04, 0.035), bone="foot_" + side, mat="metal_oscuro")
    panel("pie_punta_" + side, (0.12, 0.08, 0.05), (s * 0.12, 0.13, 0.05), (10, 0, 0), bone="foot_" + side, mat="pintura")

# ------------------------------------------------------------------ esqueleto
B = [
    ("root", "", (0, 0, 0), (0, 0.15, 0)),
    ("hips", "root", (0, 0, 0.88), (0, 0, 1.0)),
    ("spine", "hips", (0, 0, 1.0), (0, 0, 1.12)),
    ("chest", "spine", (0, 0, 1.12), (0, 0, 1.42)),
    ("neck", "chest", (0, 0, 1.42), (0, 0, 1.5)),
    ("head", "neck", (0, 0, 1.5), (0, 0, 1.7)),
]
for side, s in (("r", 1), ("l", -1)):
    B += [
        ("upper_arm_" + side, "chest", (s * 0.34, 0, 1.34), (s * 0.375, 0, 1.03)),
        ("forearm_" + side, "upper_arm_" + side, (s * 0.375, 0, 1.02), (s * 0.385, 0, 0.75)),
        ("hand_" + side, "forearm_" + side, (s * 0.385, 0, 0.74), (s * 0.385, 0, 0.6)),
        ("thigh_" + side, "hips", (s * 0.12, 0, 0.86), (s * 0.12, 0, 0.48)),
        ("shin_" + side, "thigh_" + side, (s * 0.12, 0, 0.47), (s * 0.12, 0, 0.09)),
        ("foot_" + side, "shin_" + side, (s * 0.12, 0, 0.09), (s * 0.12, 0.17, 0.03)),
    ]
bk.armature(B)
body = bk.finish("robot", tex_size=2048, bake=True, out_dir=OUT)

# ------------------------------------------------------------------ animaciones
# Ejes del armazón: X+ adelanta un hueso que cuelga (brazo, pierna); en huesos
# que apuntan hacia arriba (columna, pecho, cuello) X− inclina hacia adelante.
# Brazo derecho hacia afuera: Y−; izquierdo: Y+. Z gira el torso.
# Tiempos de impacto (segundos, antes de escalar en Godot):
#   jab 0.62 · lunge 0.6 · overhead 0.78 · sweep 0.72 · slash 0.5 y 0.95 · thrust 0.6
# Robot cansado y dañado: encorvado, cabeza caída, brazo izquierdo sin fuerza.
READY = {"spine": (-10, 0, 4), "chest": (-8, 0, 0), "neck": (-10, 0, 0), "head": (-14, 0, 8),
         "upper_arm_r": (18, -8, 0), "forearm_r": (42, 0, 0),
         "upper_arm_l": (4, 4, 0), "forearm_l": (10, 0, 0), "hand_l": (8, 0, 0),
         "thigh_r": (6, 0, 0), "shin_r": (-10, 0, 0), "thigh_l": (2, 0, 0), "shin_l": (-6, 0, 0),
         "root_pos": (0, 0, -0.025)}


def P(**kw):
    d = dict(READY)
    for k, v in kw.items():
        d[k] = v
    return d


def limp_pose(ph, amp, knee, arm, lean, bob):
    """Caminata cojeando: la pierna izquierda (dañada) casi no dobla y se arrastra."""
    s = math.sin(ph)
    c = math.cos(ph)
    return P(thigh_r=(s * amp, 0, 0), thigh_l=(-s * amp * 0.55, 0, 2),
             shin_r=(-max(0.0, c) * knee - 8, 0, 0), shin_l=(-max(0.0, -c) * knee * 0.3 - 4, 0, 0),
             foot_r=(max(0.0, -s) * 14, 0, 0), foot_l=(18 + max(0.0, s) * 6, 0, 0),
             upper_arm_r=(18 - s * arm, -8, 0), forearm_r=(42 + arm * 0.5, 0, 0),
             upper_arm_l=(4 + s * arm * 0.3, 4, 0), forearm_l=(10, 0, 0),
             spine=(lean, 0, 4 + s * 8), chest=(-8, 0, -s * 9), neck=(-10, 0, 0), head=(-14 - lean * 0.3, 0, 8 - s * 5),
             root_pos=(0, 0, -0.025 - abs(c) * bob - max(0.0, -s) * bob * 1.2))


def idle_keys():
    keys = []
    for i in range(13):
        t = i * 0.25
        b = math.sin(t / 1.5 * 2 * math.pi)
        pose = P(chest=(-8 + b * 4, 0, 0), spine=(-10 - b * 1.5, 0, 4), head=(-14 + b * 3, 0, 8),
                 upper_arm_r=(18 - b * 2, -8, 0), upper_arm_l=(4 + b * 2, 4, 0))
        if abs(t - 2.25) < 0.01:
            # Tirón de falla: la cabeza y el brazo roto se sacuden
            pose["head"] = (-5, 0, 32)
            pose["upper_arm_l"] = (25, 20, 0)
            pose["forearm_l"] = (45, 0, 0)
        keys.append((t, pose))
    return keys


bk.action("idle", idle_keys(), loop=True)
bk.action("walk", [(i / 8.0 * 1.2, limp_pose(i / 8.0 * 2 * math.pi, 24, 50, 14, -12, 0.035)) for i in range(9)], loop=True)
bk.action("run", [(i / 8.0 * 0.8, limp_pose(i / 8.0 * 2 * math.pi, 38, 75, 30, -22, 0.06)) for i in range(9)], loop=True)

# --- Puñetazo cansado (robot pequeño): se echa atrás, duda y lanza el golpe con el cuerpo
bk.action("jab", [
    (0.0, P()),
    (0.35, P(upper_arm_r=(-40, -12, 0), forearm_r=(105, 0, 0), chest=(4, 0, -30), spine=(4, 0, -10), thigh_l=(18, 0, 0), shin_l=(-20, 0, 0), root_pos=(0, -0.06, -0.04))),
    (0.5, P(upper_arm_r=(-44, -12, 0), forearm_r=(108, 0, 0), chest=(6, 0, -32), spine=(4, 0, -10), thigh_l=(18, 0, 0), shin_l=(-20, 0, 0), root_pos=(0, -0.07, -0.05))),
    (0.62, P(upper_arm_r=(88, -4, 0), forearm_r=(4, 0, 0), chest=(-14, 0, 26), spine=(-12, 0, 10), thigh_r=(28, 0, 0), shin_r=(-24, 0, 0), thigh_l=(-12, 0, 0), root_pos=(0, 0.14, -0.06))),
    (0.82, P(upper_arm_r=(70, -4, 0), forearm_r=(14, 0, 0), chest=(-20, 0, 30), spine=(-16, 0, 10), head=(-22, 0, 12), thigh_r=(28, 0, 0), shin_r=(-26, 0, 0), root_pos=(0, 0.16, -0.08))),
    (1.35, P()),
])
# --- Embestida: se agacha, salta encima con los brazos por delante y trastabilla
bk.action("lunge", [
    (0.0, P()),
    (0.45, P(spine=(-25, 0, 0), chest=(-15, 0, 0), upper_arm_r=(-30, -20, 0), upper_arm_l=(-25, 20, 0), thigh_r=(55, 0, 0), shin_r=(-90, 0, 0), thigh_l=(45, 0, 0), shin_l=(-85, 0, 0), foot_r=(30, 0, 0), foot_l=(30, 0, 0), root_pos=(0, -0.05, -0.2))),
    (0.6, P(spine=(-35, 0, 0), chest=(-10, 0, 0), head=(5, 0, 0), upper_arm_r=(85, -15, 0), forearm_r=(20, 0, 0), upper_arm_l=(80, 15, 0), forearm_l=(20, 0, 0), thigh_r=(40, 0, 0), shin_r=(-20, 0, 0), thigh_l=(-35, 0, 0), shin_l=(-30, 0, 0), root_pos=(0, 0.45, -0.05))),
    (0.85, P(spine=(-38, 0, 8), chest=(-12, 0, 0), head=(-25, 0, 15), upper_arm_r=(50, -20, 0), upper_arm_l=(40, 30, 0), thigh_r=(45, 0, 0), shin_r=(-50, 0, 0), thigh_l=(-20, 0, 0), shin_l=(-20, 0, 0), root_pos=(0, 0.5, -0.14))),
    (1.45, P()),
])

# --- Hachazo a dos manos (como el hacha del Caballero Negro): levanta lento, sostiene,
#     cae de golpe con un paso largo, el hacha se queda clavada y la saca con esfuerzo.
TWO_HAND_HIGH = dict(upper_arm_r=(172, -6, 0), forearm_r=(28, 0, 0), upper_arm_l=(166, -22, 0), forearm_l=(40, 0, 0))
bk.action("overhead", [
    (0.0, P()),
    (0.25, P(upper_arm_r=(80, -8, 0), forearm_r=(60, 0, 0), upper_arm_l=(70, -25, 0), forearm_l=(70, 0, 0), chest=(-4, 0, 0))),
    (0.55, P(**TWO_HAND_HIGH, spine=(8, 0, 0), chest=(14, 0, 0), head=(4, 0, 0), thigh_l=(-12, 0, 0), thigh_r=(14, 0, 0), shin_r=(-14, 0, 0), root_pos=(0, -0.08, -0.02))),
    (0.7, P(upper_arm_r=(176, -6, 0), forearm_r=(30, 0, 0), upper_arm_l=(170, -22, 0), forearm_l=(42, 0, 0), spine=(10, 0, 0), chest=(16, 0, 0), head=(6, 0, 0), thigh_l=(-12, 0, 0), thigh_r=(14, 0, 0), shin_r=(-14, 0, 0), root_pos=(0, -0.09, -0.02))),
    (0.78, P(upper_arm_r=(42, -4, 0), forearm_r=(4, 0, 0), upper_arm_l=(40, -28, 0), forearm_l=(20, 0, 0), spine=(-20, 0, 0), chest=(-32, 0, 0), head=(-10, 0, 0), thigh_r=(52, 0, 0), shin_r=(-58, 0, 0), thigh_l=(-24, 0, 0), shin_l=(-12, 0, 0), root_pos=(0, 0.3, -0.16))),
    (1.2, P(upper_arm_r=(38, -4, 0), forearm_r=(2, 0, 0), upper_arm_l=(36, -28, 0), forearm_l=(18, 0, 0), spine=(-24, 0, 0), chest=(-34, 0, 0), head=(-18, 0, 6), thigh_r=(52, 0, 0), shin_r=(-60, 0, 0), thigh_l=(-24, 0, 0), shin_l=(-12, 0, 0), root_pos=(0, 0.3, -0.18))),
    (1.55, P(upper_arm_r=(62, -6, 0), forearm_r=(30, 0, 0), upper_arm_l=(55, -25, 0), forearm_l=(40, 0, 0), spine=(-6, 0, 0), chest=(-8, 0, 0), head=(-12, 0, 0), thigh_r=(30, 0, 0), shin_r=(-30, 0, 0), root_pos=(0, 0.2, -0.08))),
    (2.0, P()),
])
# --- Barrido horizontal a dos manos: gira el torso hacia atrás, barre y se pasa de largo
bk.action("sweep", [
    (0.0, P()),
    (0.5, P(upper_arm_r=(80, -45, 0), forearm_r=(20, 0, 0), upper_arm_l=(70, -10, 0), forearm_l=(50, 0, 0), spine=(-6, 0, -30), chest=(0, 0, -60), head=(-6, 0, 35), thigh_l=(-14, 0, 0), thigh_r=(16, 0, 0), root_pos=(0, -0.05, -0.06))),
    (0.62, P(upper_arm_r=(82, -48, 0), forearm_r=(22, 0, 0), upper_arm_l=(72, -10, 0), forearm_l=(52, 0, 0), spine=(-6, 0, -34), chest=(0, 0, -66), head=(-6, 0, 38), thigh_l=(-14, 0, 0), thigh_r=(16, 0, 0), root_pos=(0, -0.05, -0.07))),
    (0.72, P(upper_arm_r=(85, -10, 0), forearm_r=(5, 0, 0), upper_arm_l=(75, -30, 0), forearm_l=(25, 0, 0), spine=(-14, 0, 30), chest=(-8, 0, 55), head=(-10, 0, -20), thigh_r=(35, 0, 0), shin_r=(-30, 0, 0), thigh_l=(-15, 0, 0), root_pos=(0, 0.18, -0.1))),
    (0.92, P(upper_arm_r=(70, 15, 0), forearm_r=(10, 0, 0), upper_arm_l=(60, -40, 0), forearm_l=(20, 0, 0), spine=(-18, 0, 40), chest=(-10, 0, 75), head=(-14, 0, -25), thigh_r=(35, 0, 0), shin_r=(-32, 0, 0), root_pos=(0, 0.2, -0.12))),
    (1.6, P()),
])
# --- Combo de espada (como los caballeros de Balder): tajo diagonal, revés con paso y pausa
bk.action("slash", [
    (0.0, P()),
    (0.3, P(upper_arm_r=(150, -42, 0), forearm_r=(35, 0, 0), upper_arm_l=(40, 22, 0), forearm_l=(40, 0, 0), spine=(0, 0, -15), chest=(4, 0, -35), head=(-8, 0, 20), thigh_l=(-12, 0, 0), root_pos=(0, -0.06, -0.03))),
    (0.42, P(upper_arm_r=(155, -44, 0), forearm_r=(36, 0, 0), upper_arm_l=(40, 22, 0), forearm_l=(40, 0, 0), spine=(0, 0, -16), chest=(6, 0, -38), head=(-8, 0, 20), thigh_l=(-12, 0, 0), root_pos=(0, -0.06, -0.03))),
    (0.5, P(upper_arm_r=(40, 28, 0), forearm_r=(8, 0, 0), upper_arm_l=(55, 10, 0), forearm_l=(30, 0, 0), spine=(-14, 0, 14), chest=(-14, 0, 34), head=(-14, 0, -10), thigh_r=(30, 0, 0), shin_r=(-30, 0, 0), thigh_l=(-14, 0, 0), root_pos=(0, 0.16, -0.08))),
    (0.66, P(upper_arm_r=(25, 40, 0), forearm_r=(15, 0, 0), spine=(-16, 0, 18), chest=(-16, 0, 42), head=(-16, 0, -12), thigh_r=(30, 0, 0), shin_r=(-32, 0, 0), root_pos=(0, 0.18, -0.09))),
    (0.84, P(upper_arm_r=(105, 48, 0), forearm_r=(40, 0, 0), spine=(-6, 0, 20), chest=(0, 0, 48), head=(-10, 0, -20), thigh_r=(20, 0, 0), shin_r=(-20, 0, 0), root_pos=(0, 0.18, -0.05))),
    (0.95, P(upper_arm_r=(70, -50, 0), forearm_r=(6, 0, 0), upper_arm_l=(30, 25, 0), spine=(-14, 0, -16), chest=(-12, 0, -42), head=(-12, 0, 18), thigh_l=(32, 0, 0), shin_l=(-30, 0, 0), thigh_r=(-12, 0, 0), root_pos=(0, 0.34, -0.09))),
    (1.15, P(upper_arm_r=(55, -60, 0), forearm_r=(12, 0, 0), spine=(-18, 0, -20), chest=(-14, 0, -50), head=(-18, 0, 20), thigh_l=(32, 0, 0), shin_l=(-32, 0, 0), root_pos=(0, 0.36, -0.1))),
    (1.75, P()),
])
# --- Estocada: se recoge, carga el peso atrás y se lanza con una zancada larga
bk.action("thrust", [
    (0.0, P()),
    (0.4, P(upper_arm_r=(-30, -12, 0), forearm_r=(112, 0, 0), upper_arm_l=(50, 20, 0), forearm_l=(60, 0, 0), spine=(-6, 0, -18), chest=(0, 0, -40), thigh_l=(30, 0, 0), shin_l=(-40, 0, 0), thigh_r=(-10, 0, 0), shin_r=(-30, 0, 0), root_pos=(0, -0.1, -0.1))),
    (0.5, P(upper_arm_r=(-34, -12, 0), forearm_r=(116, 0, 0), upper_arm_l=(50, 20, 0), forearm_l=(60, 0, 0), spine=(-6, 0, -20), chest=(0, 0, -42), thigh_l=(30, 0, 0), shin_l=(-42, 0, 0), thigh_r=(-10, 0, 0), shin_r=(-32, 0, 0), root_pos=(0, -0.1, -0.11))),
    (0.6, P(upper_arm_r=(92, -2, 0), forearm_r=(0, 0, 0), upper_arm_l=(-30, 30, 0), forearm_l=(20, 0, 0), spine=(-20, 0, 12), chest=(-14, 0, 22), head=(-6, 0, 0), thigh_r=(58, 0, 0), shin_r=(-42, 0, 0), thigh_l=(-36, 0, 0), shin_l=(-14, 0, 0), root_pos=(0, 0.45, -0.14))),
    (0.88, P(upper_arm_r=(88, -2, 0), forearm_r=(4, 0, 0), upper_arm_l=(-25, 30, 0), spine=(-24, 0, 12), chest=(-16, 0, 22), head=(-14, 0, 6), thigh_r=(58, 0, 0), shin_r=(-46, 0, 0), thigh_l=(-36, 0, 0), shin_l=(-14, 0, 0), root_pos=(0, 0.47, -0.16))),
    (1.45, P()),
])
bk.action("aim", [(0.0, P(upper_arm_r=(86, -2, 0), forearm_r=(4, 0, 0), chest=(-4, 0, 10), head=(-6, 0, -8))),
                  (0.08, P(upper_arm_r=(96, -2, 0), forearm_r=(-6, 0, 0), chest=(0, 0, 10), head=(-6, 0, -8), root_pos=(0, -0.03, -0.025))),
                  (0.3, P(upper_arm_r=(86, -2, 0), forearm_r=(4, 0, 0), chest=(-4, 0, 10), head=(-6, 0, -8)))], loop=True)
bk.action("hit", [(0.0, P()),
                  (0.08, P(spine=(14, 0, 10), chest=(24, 0, 12), head=(28, 0, -15), upper_arm_r=(-25, -35, 0), upper_arm_l=(-15, 40, 0), forearm_l=(40, 0, 0), thigh_r=(-12, 0, 0), shin_l=(-25, 0, 0), root_pos=(0, -0.14, -0.04))),
                  (0.3, P(spine=(6, 0, 6), chest=(10, 0, 8), head=(10, 0, -8), root_pos=(0, -0.16, -0.06))),
                  (0.65, P())])
# --- Muerte: se le doblan las rodillas, queda de rodillas un instante y cae de frente
bk.action("death", [
    (0.0, P()),
    (0.15, P(chest=(20, 0, 10), head=(30, 0, -20), upper_arm_r=(-20, -30, 0), upper_arm_l=(-10, 40, 0))),
    (0.5, P(spine=(-20, 0, 6), chest=(-10, 0, 0), head=(-35, 0, 15), upper_arm_r=(20, -10, 0), upper_arm_l=(10, 15, 0), forearm_l=(5, 0, 0),
             thigh_r=(80, 0, 0), shin_r=(-110, 0, 0), thigh_l=(70, 0, 0), shin_l=(-105, 0, 0), foot_r=(40, 0, 0), foot_l=(40, 0, 0), root_pos=(0, 0.05, -0.42))),
    (0.85, P(spine=(-28, 0, 10), chest=(-16, 0, 0), head=(-45, 0, 20), upper_arm_r=(10, -10, 0), upper_arm_l=(5, 15, 0),
             thigh_r=(85, 0, 0), shin_r=(-115, 0, 0), thigh_l=(78, 0, 0), shin_l=(-112, 0, 0), foot_r=(40, 0, 0), foot_l=(40, 0, 0), root_pos=(0, 0.05, -0.45))),
    (1.3, P(root=(-82, 0, 0), spine=(-6, 0, 6), chest=(0, 0, 0), head=(-10, 0, 35), upper_arm_r=(160, -40, 0), upper_arm_l=(150, 50, 0), forearm_r=(20, 0, 0),
            thigh_r=(20, 0, 0), shin_r=(-40, 0, 0), thigh_l=(10, 0, 0), shin_l=(-30, 0, 0), root_pos=(0, 0.1, 0.12))),
    (1.45, P(root=(-86, 0, 0), spine=(-4, 0, 6), head=(-6, 0, 38), upper_arm_r=(165, -45, 0), upper_arm_l=(155, 55, 0), forearm_r=(15, 0, 0),
             thigh_r=(18, 0, 0), shin_r=(-36, 0, 0), thigh_l=(8, 0, 0), shin_l=(-28, 0, 0), root_pos=(0, 0.1, 0.11))),
])

bk.set_pose(P())
if PREVIEW:
    bk.render_preview(os.path.join(OUT, "preview_front.png"), (1.3, 3.0, 1.35), (0, 0, 0.95))
    bk.render_preview(os.path.join(OUT, "preview_back.png"), (-1.8, -2.4, 1.6), (0, 0, 1.0))
    bk.render_preview(os.path.join(OUT, "preview_overhead.png"), (2.6, 1.6, 1.2), (0, 0, 1.0), action_name="overhead", frame=18)
    bk.render_preview(os.path.join(OUT, "preview_overhead_golpe.png"), (2.6, 1.6, 1.2), (0, 0, 1.0), action_name="overhead", frame=25)
bk.set_pose({})
bk.export(os.path.join(OUT, "robot.glb"))
print("LISTO", OUT)
