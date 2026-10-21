"""Androide del Centro de Cómputo (enemigos "androide_*"): caballeros caídos mitad
humanos, mitad máquina, hechos a imagen de ADA-7. La mitad derecha conserva piel
sintética (rasgada, con el metal asomando), la izquierda es cromo: brazo esquelético
con un manojo de cables de servidor y pierna robótica. Llevan coraza de hierro oxidado,
hombrera, tabardo y capa en jirones, medio yelmo y un mini rack de servidores a la espalda.

Uso:  blender -b --python arte/blender/androide.py -- <carpeta_salida> [preview]
Genera androide.glb (+ texturas) con esqueleto y animaciones:
  idle, walk, run, dual, thrust, compile, lash, cast, pulse, hit, death
Tiempos de impacto: dual 0.45 / 0.83 / 1.21 · thrust 0.6 · compile 1.3 · lash 0.55 ·
cast 0.7 · pulse 0.6 (están también en mundo/enemy.gd).
"""
import sys
import os
import math

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, sphere, panel, bolts, cable, piston, vents, label, cloth, blob, limb

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/androide")
PREVIEW = "preview" in argv
os.makedirs(OUT, exist_ok=True)

bk.reset(seed=23)
bk.define_materials({
    "armadura": dict(base=(0.17, 0.17, 0.18), metal=0.9, rough=0.5, rust=1.35, wear=0.95, dirt=0.9, bare=(0.55, 0.55, 0.57), streaks=0.85, soot=0.6),
    "cromo": dict(base=(0.72, 0.73, 0.75), metal=1.0, rough=0.24, rust=0.75, wear=0.35, dirt=0.75, bare=(0.9, 0.9, 0.92), streaks=0.65, soot=0.45),
    "metal_oscuro": dict(base=(0.06, 0.06, 0.07), metal=0.6, rough=0.55, rust=1.0, wear=0.8, dirt=0.8, bare=(0.42, 0.42, 0.44), streaks=0.5, soot=0.5),
    "metal": dict(base=(0.5, 0.5, 0.52), metal=1.0, rough=0.42, rust=1.0, wear=0.4, dirt=0.6, bare=(0.8, 0.8, 0.82), streaks=0.4),
    "goma": dict(base=(0.03, 0.03, 0.03), rough=0.85, rust=0.0, wear=0.15, dirt=0.3, scratches=False),
    "cable_e": dict(base=(0.05, 0.22, 0.3), rough=0.6, rust=0.0, wear=0.4, dirt=0.4, bare=(0.4, 0.42, 0.4), scratches=False),
    "tela": dict(base=(0.025, 0.06, 0.065), rough=0.92, rust=0.25, wear=0.7, dirt=1.25, bare=(0.12, 0.11, 0.08), scratches=False, soot=0.6, streaks=0.4),
    "tela_osc": dict(base=(0.07, 0.065, 0.055), rough=0.95, rust=0.1, wear=0.6, dirt=1.1, bare=(0.22, 0.2, 0.16), scratches=False, soot=0.4),
    "cuero": dict(base=(0.15, 0.085, 0.045), rough=0.72, rust=0.0, wear=0.85, dirt=0.9, bare=(0.3, 0.2, 0.12), soot=0.3),
    "acento": dict(base=(0.55, 0.62, 0.6), rough=0.6, rust=0.6, wear=0.9, dirt=0.8, bare=(0.2, 0.2, 0.2), scratches=False),
    "piel": dict(skin=True, base=(0.19, 0.15, 0.135), veins=0.45, vein_col=(0.05, 0.07, 0.09), blotch=0.75, blotch_col=(0.09, 0.06, 0.05), rough=0.6, wet=0.1, dirt=1.0),
    "ojos": {"emit": (0.3, 0.9, 1.0), "strength": 8.0},
    "nucleo": {"emit": (0.25, 0.85, 1.0), "strength": 5.0},
    "led": {"emit": (0.3, 1.0, 0.45), "strength": 6.0},
})

# ------------------------------------------------------------------ cadera, cinturón, tabardo
box("pelvis", (0.3, 0.2, 0.14), (0, 0, 0.9), bone="hips", mat="metal_oscuro")
cyl("cinturon", 0.18, 0.06, (0, 0, 0.95), bone="hips", mat="cuero", verts=24, bevel=0.004)
box("hebilla", (0.07, 0.02, 0.055), (0, 0.18, 0.95), bone="hips", mat="metal", bevel=0.004)
box("bolsa_r", (0.08, 0.05, 0.09), (0.15, 0.12, 0.9), (0, 0, -20), bone="hips", mat="cuero")
box("bolsa_l", (0.06, 0.05, 0.08), (-0.16, 0.1, 0.9), (0, 0, 25), bone="hips", mat="cuero")
for s in (-1, 1):
    panel("escarcela_%d" % s, (0.14, 0.04, 0.15), (s * 0.15, 0.08, 0.86), (-8, s * 20, 0), bone="hips", mat="armadura", taper=(1.0, 1.2))
    sphere("cadera_art_%d" % s, 0.055, (s * 0.11, 0, 0.84), bone="hips", mat="metal")
# Tabardo en dos franjas: cada una sigue a su muslo para no atravesar las piernas
cloth("tabardo_r", 0.17, 0.62, (0.085, 0.17, 0.97), (0, 0, 0), bone="hips", mat="tela", nx=8, ny=12, tatter=0.22, holes=0.015, flare=0.06, bone2="thigh_r", blend=0.75, seed=3)
cloth("tabardo_l", 0.17, 0.58, (-0.085, 0.17, 0.97), (0, 0, 0), bone="hips", mat="tela", nx=8, ny=12, tatter=0.28, holes=0.015, flare=0.06, bone2="thigh_l", blend=0.75, seed=4)
cloth("tabardo_atras", 0.32, 0.55, (0, -0.15, 0.97), (0, 0, 180), bone="hips", mat="tela", nx=12, ny=12, tatter=0.3, holes=0.02, flare=0.05, seed=5)
label("emblema", "</>", (0.0, 0.185, 0.86), (90, 0, 0), size=0.07, bone="hips", mat="acento")

# ------------------------------------------------------------------ columna expuesta
cyl("columna", 0.05, 0.2, (0, -0.03, 1.03), bone="spine", mat="cromo")
for k in range(4):
    cyl("vertebra_%d" % k, 0.065, 0.022, (0, -0.03, 0.96 + k * 0.045), bone="spine", mat="metal", verts=12)
cable("cable_cintura_a", [(-0.07, -0.1, 1.15), (-0.12, -0.13, 1.03), (-0.05, -0.1, 0.94)], 0.011, bone="spine", mat="cable_e", sag=0.03)
cable("cable_cintura_b", [(0.06, -0.1, 1.15), (0.12, -0.12, 1.05), (0.07, -0.1, 0.94)], 0.01, bone="spine", sag=0.03)
# Abdomen: piel sintética del lado derecho, cromo del izquierdo
blob("abdomen_piel", 0.1, (0.05, 0.03, 1.06), (1.0, 0.85, 1.05), bone="spine", mat="piel", lumps=0.05, seed=1)
blob("abdomen_cromo", 0.095, (-0.05, 0.03, 1.06), (1.0, 0.85, 1.05), bone="spine", mat="cromo", lumps=0.03, seed=2)

# ------------------------------------------------------------------ pecho: coraza, hombrera, rack
blob("torax", 0.17, (0, -0.02, 1.27), (1.05, 0.72, 1.0), bone="chest", mat="metal_oscuro", lumps=0.02, seed=21)
sphere("coraza", 0.18, (0, 0.035, 1.28), (1.06, 0.68, 0.98), bone="chest", mat="armadura", segs=24)
box("coraza_quilla", (0.03, 0.03, 0.28), (0, 0.155, 1.28), (4, 0, 0), bone="chest", mat="armadura", bevel=0.01)
panel("coraza_baja", (0.3, 0.07, 0.09), (0, 0.1, 1.11), (-12, 0, 0), bone="chest", mat="armadura", taper=(0.9, 1.0))
# Grieta en la coraza con el núcleo encendido
box("grieta", (0.03, 0.03, 0.12), (-0.07, 0.15, 1.3), (0, 0, 18), bone="chest", mat="metal_oscuro", bevel=0.003)
box("nucleo", (0.018, 0.02, 0.09), (-0.07, 0.162, 1.3), (0, 0, 18), bone="chest", mat="nucleo", bevel=0.002)
bolts("remaches", [(x, 0.13, z) for x in (-0.13, 0.13) for z in (1.22, 1.34)], (90, 0, 0), bone="chest")
cyl("gorguera", 0.1, 0.07, (0, 0.0, 1.43), bone="chest", mat="armadura", verts=20, r2=0.075, bevel=0.01)
# Mini rack de servidores (como el de ADA-7) con luces y cables colgando
box("rack", (0.26, 0.1, 0.3), (0, -0.22, 1.3), bone="chest", mat="metal_oscuro")
for k in range(4):
    box("rack_bahia_%d" % k, (0.22, 0.012, 0.05), (0, -0.276, 1.4 - k * 0.065), bone="chest", mat="metal", bevel=0.003)
    box("rack_led_%d" % k, (0.012, 0.008, 0.012), (0.08 - (k % 2) * 0.03, -0.284, 1.4 - k * 0.065), bone="chest", mat="led", bevel=0.001)
for k in range(5):
    sx = -0.1 + k * 0.05
    cable("rack_cable_%d" % k, [(sx, -0.27, 1.17), (sx + 0.02 * (k - 2), -0.3, 1.02), (sx * 1.3, -0.28, 0.9 - k * 0.02)], 0.009,
          bone="chest", mat="cable_e" if k % 2 else "goma", sag=0.02)
# Capa en jirones colgando de los hombros
cloth("capa", 0.42, 0.85, (0, -0.29, 1.45), (0, 0, 180), bone="chest", mat="tela", nx=16, ny=16, tatter=0.35, holes=0.025, wave=0.025, flare=0.14, seed=7)
# Hombrera izquierda grande (lado de cromo)
panel("hombrera_l", (0.22, 0.28, 0.07), (-0.33, 0, 1.47), (0, 22, 0), bone="upper_arm_l", mat="armadura", bevel=0.025)
panel("hombrera_l2", (0.19, 0.24, 0.05), (-0.37, 0, 1.41), (0, 40, 0), bone="upper_arm_l", mat="armadura")
panel("hombrera_l3", (0.15, 0.2, 0.04), (-0.4, 0, 1.35), (0, 58, 0), bone="upper_arm_l", mat="armadura")
bolts("hombrera_rem", [(-0.33, 0.1, 1.5), (-0.33, -0.1, 1.5)], (0, 22, 0), bone="upper_arm_l")
# Hombro derecho: tela rota del jubón sobre la piel
cloth("manga_r", 0.2, 0.2, (0.33, 0.0, 1.47), (0, -60, 90), bone="upper_arm_r", mat="tela_osc", nx=6, ny=6, tatter=0.5, holes=0.0, seed=9)

# ------------------------------------------------------------------ cuello y cabeza
limb("cuello", [(0, 0.0, 1.43), (0, 0.01, 1.5), (0, 0.02, 1.54)], [0.05, 0.045, 0.045], bone="neck", mat="piel")
for k in range(3):
    cable("cuello_cable_%d" % k, [(-0.03 - k * 0.01, -0.02, 1.44), (-0.05 - k * 0.008, 0.0, 1.5), (-0.04, 0.0, 1.55)], 0.006, bone="neck", mat="cable_e" if k == 1 else "goma")
blob("craneo", 0.1, (0, 0.01, 1.62), (0.92, 1.05, 1.15), bone="head", mat="piel", lumps=0.04, seed=11)
blob("mandibula", 0.07, (0, 0.04, 1.565), (0.95, 1.0, 0.65), bone="head", mat="piel", lumps=0.05, seed=12)
blob("nariz", 0.02, (0.01, 0.105, 1.61), (0.7, 1.0, 1.3), bone="head", mat="piel", lumps=0.05, seed=13)
# Media cara de cromo (izquierda) con el ojo encendido
blob("cara_cromo", 0.098, (-0.03, 0.02, 1.615), (0.75, 1.05, 1.12), bone="head", mat="cromo", lumps=0.02, seed=14)
box("cromo_borde", (0.012, 0.15, 0.2), (-0.012, 0.03, 1.615), (0, 0, 6), bone="head", mat="metal", bevel=0.004)
cyl("ojo_cuenca", 0.024, 0.02, (-0.042, 0.09, 1.632), (90, 0, 0), bone="head", mat="metal_oscuro", verts=14)
sphere("ojos", 0.016, (-0.042, 0.1, 1.632), bone="head", mat="ojos", segs=12)
sphere("ojo_humano", 0.013, (0.04, 0.092, 1.634), bone="head", mat="metal_oscuro", segs=10)
box("ceja_cicatriz", (0.04, 0.008, 0.008), (0.042, 0.095, 1.655), (0, 0, -12), bone="head", mat="piel", bevel=0.002)
for k in range(3):
    cable("mejilla_cable_%d" % k, [(-0.01, 0.085, 1.6 - k * 0.012), (0.01, 0.09, 1.585 - k * 0.012), (0.03, 0.08, 1.57 - k * 0.012)], 0.003, bone="head", mat="goma")
# Medio yelmo oxidado (deja la cara a la vista) y un jirón de tela atrás
sphere("yelmo", 0.112, (0, -0.012, 1.67), (1.0, 1.1, 0.72), bone="head", mat="armadura", segs=22)
box("yelmo_nuca", (0.2, 0.08, 0.05), (0, -0.1, 1.62), (30, 0, 0), bone="head", mat="armadura", bevel=0.012)
box("yelmo_cresta", (0.018, 0.2, 0.035), (0, -0.01, 1.745), bone="head", mat="armadura", bevel=0.008)
cloth("yelmo_tela", 0.16, 0.3, (0, -0.11, 1.66), (0, 0, 180), bone="head", mat="tela", nx=5, ny=8, tatter=0.5, holes=0.0, seed=15)
box("yelmo_abolladura", (0.05, 0.03, 0.04), (0.08, 0.06, 1.7), (20, 10, 30), bone="head", mat="armadura", bevel=0.01)

# ------------------------------------------------------------------ brazo derecho (humano)
limb("brazo_r", [(0.31, 0, 1.4), (0.34, 0, 1.22), (0.365, 0, 1.04)], [0.06, 0.052, 0.045], bone="upper_arm_r", mat="piel", lumps=0.08)
limb("antebrazo_r", [(0.37, 0, 1.03), (0.38, 0.0, 0.88), (0.385, 0, 0.76)], [0.045, 0.04, 0.032], bone="forearm_r", mat="piel", lumps=0.08)
# Desgarro en la piel: asoma el hueso de metal
cyl("hueso_r", 0.014, 0.12, (0.395, 0.03, 0.9), (4, 0, 0), bone="forearm_r", mat="cromo", verts=8)
cable("tendon_r", [(0.39, 0.035, 0.96), (0.4, 0.045, 0.9), (0.39, 0.035, 0.84)], 0.004, bone="forearm_r", mat="cable_e")
panel("brazal_r", (0.1, 0.1, 0.13), (0.383, 0.0, 0.83), (0, 0, 0), bone="forearm_r", mat="armadura", bevel=0.02)
cyl("codera_r", 0.05, 0.08, (0.368, -0.01, 1.03), (0, 90, 0), bone="forearm_r", mat="armadura", verts=14)
box("mano_r", (0.06, 0.045, 0.08), (0.385, 0.0, 0.7), bone="hand_r", mat="cuero")
for f in range(4):
    fx = 0.385 + (f - 1.5) * 0.016
    limb("dedo_r_%d" % f, [(fx, 0.01, 0.66), (fx, 0.025, 0.625), (fx, 0.03, 0.6)], [0.009, 0.008, 0.007], bone="hand_r", mat="cuero", verts=6)
limb("pulgar_r", [(0.36, 0.03, 0.69), (0.35, 0.05, 0.66)], [0.01, 0.008], bone="hand_r", mat="cuero", verts=6)

# ------------------------------------------------------------------ brazo izquierdo (cromo + cables)
cyl("hombro_l", 0.07, 0.1, (-0.32, 0, 1.36), (0, 90, 0), bone="upper_arm_l", mat="metal_oscuro", verts=20)
cyl("humero_l", 0.026, 0.3, (-0.35, 0, 1.19), (0, -5, 0), bone="upper_arm_l", mat="cromo", verts=12)
piston("piston_brazo_l", (-0.31, -0.04, 1.32), (-0.35, -0.04, 1.06), 0.013, bone="upper_arm_l")
piston("piston_brazo_l2", (-0.39, 0.03, 1.3), (-0.37, 0.03, 1.07), 0.01, bone="upper_arm_l")
cyl("codo_l", 0.045, 0.09, (-0.37, 0, 1.02), (0, 90, 0), bone="forearm_l", mat="metal_oscuro", verts=16)
cyl("radio_l", 0.018, 0.26, (-0.38, 0.02, 0.88), bone="forearm_l", mat="cromo", verts=10)
cyl("cubito_l", 0.016, 0.26, (-0.385, -0.02, 0.88), bone="forearm_l", mat="cromo", verts=10)
for k in range(3):
    cyl("anillo_ante_l_%d" % k, 0.04, 0.02, (-0.383, 0, 0.96 - k * 0.08), bone="forearm_l", mat="metal", verts=14)
# Manojo de cables de servidor enrollado al antebrazo (sus "látigos")
for k in range(5):
    a = k * 1.25
    cable("cables_ante_%d" % k, [(-0.383 + math.cos(a) * 0.045, math.sin(a) * 0.045, 0.98), (-0.383 + math.cos(a + 1.5) * 0.05, math.sin(a + 1.5) * 0.05, 0.88),
                                (-0.383 + math.cos(a + 3.0) * 0.045, math.sin(a + 3.0) * 0.045, 0.78), (-0.4 + k * 0.01, -0.02 + k * 0.01, 0.6 - k * 0.04)],
          0.007, bone="forearm_l", mat="cable_e" if k % 2 == 0 else "goma", sag=0.0)
box("palma_l", (0.06, 0.04, 0.06), (-0.385, 0, 0.71), bone="hand_l", mat="cromo", bevel=0.006)
for f in range(4):
    fx = -0.385 + (f - 1.5) * 0.017
    cyl("garra_l_%d_a" % f, 0.007, 0.05, (fx, 0.008, 0.655), (8, 0, 0), bone="hand_l", mat="cromo", verts=6)
    cyl("garra_l_%d_b" % f, 0.006, 0.045, (fx, 0.018, 0.61), (25, 0, 0), bone="hand_l", mat="metal_oscuro", verts=6, r2=0.002)
cyl("garra_pulgar_l", 0.007, 0.05, (-0.355, 0.03, 0.68), (40, 0, -20), bone="hand_l", mat="cromo", verts=6)

# ------------------------------------------------------------------ pierna derecha (humana, con armadura)
limb("muslo_r", [(0.11, 0, 0.88), (0.115, 0.01, 0.68), (0.12, 0.0, 0.5)], [0.075, 0.066, 0.055], bone="thigh_r", mat="tela_osc", lumps=0.1)
panel("quijote_r", (0.12, 0.05, 0.2), (0.115, 0.06, 0.7), (-4, 0, 0), bone="thigh_r", mat="armadura")
sphere("rodillera_r", 0.06, (0.12, 0.04, 0.47), (1.0, 0.9, 1.0), bone="shin_r", mat="armadura", segs=14)
limb("pantorrilla_r", [(0.12, 0, 0.46), (0.12, -0.01, 0.3), (0.12, 0, 0.14)], [0.052, 0.05, 0.04], bone="shin_r", mat="tela_osc", lumps=0.1)
panel("greba_r", (0.11, 0.08, 0.26), (0.12, 0.03, 0.28), (-2, 0, 0), bone="shin_r", mat="armadura", bevel=0.025)
box("bota_r", (0.11, 0.22, 0.09), (0.12, 0.04, 0.045), bone="foot_r", mat="cuero", bevel=0.02)
box("bota_cana_r", (0.1, 0.11, 0.08), (0.12, 0.0, 0.12), bone="foot_r", mat="cuero", bevel=0.015)

# ------------------------------------------------------------------ pierna izquierda (robótica)
cyl("cadera_l_act", 0.06, 0.09, (-0.12, 0, 0.84), (0, 90, 0), bone="thigh_l", mat="metal_oscuro", verts=18)
cyl("femur_l", 0.032, 0.34, (-0.12, 0, 0.66), bone="thigh_l", mat="cromo", verts=12)
piston("piston_muslo_l", (-0.12, 0.06, 0.8), (-0.12, 0.05, 0.52), 0.016, bone="thigh_l")
piston("piston_muslo_l2", (-0.17, -0.03, 0.8), (-0.15, -0.03, 0.52), 0.012, bone="thigh_l")
cloth("pernera_rota_l", 0.16, 0.14, (-0.12, 0.0, 0.86), (0, 0, 0), bone="thigh_l", mat="tela_osc", nx=6, ny=5, tatter=0.6, seed=17)
cyl("rodilla_l", 0.05, 0.12, (-0.12, 0, 0.47), (0, 90, 0), bone="shin_l", mat="metal_oscuro", verts=18)
cyl("rodilla_tapa_l", 0.035, 0.13, (-0.12, 0, 0.47), (0, 90, 0), bone="shin_l", mat="cromo", verts=18)
cyl("tibia_l", 0.026, 0.34, (-0.12, 0.0, 0.28), bone="shin_l", mat="cromo", verts=12)
piston("piston_pant_l", (-0.12, -0.06, 0.44), (-0.12, -0.05, 0.14), 0.014, bone="shin_l")
for k in range(3):
    cable("pierna_cable_%d" % k, [(-0.09 - k * 0.015, 0.03, 0.44), (-0.08 - k * 0.02, 0.06, 0.3), (-0.1, 0.03, 0.16)], 0.006, bone="shin_l", mat="cable_e" if k == 1 else "goma", sag=0.0)
box("tobillo_l", (0.07, 0.07, 0.05), (-0.12, 0, 0.1), bone="foot_l", mat="metal_oscuro")
for k in range(3):
    box("pie_garra_l_%d" % k, (0.03, 0.17, 0.04), (-0.12 + (k - 1) * 0.04, 0.08, 0.03), (0, 0, (k - 1) * -12), bone="foot_l", mat="cromo", taper=(0.7, 0.7), bevel=0.008)
box("pie_talon_l", (0.04, 0.07, 0.04), (-0.12, -0.06, 0.03), bone="foot_l", mat="cromo", bevel=0.008)

# ------------------------------------------------------------------ esqueleto
B = [
    ("root", "", (0, 0, 0), (0, 0.15, 0)),
    ("hips", "root", (0, 0, 0.88), (0, 0, 1.0)),
    ("spine", "hips", (0, 0, 1.0), (0, 0, 1.12)),
    ("chest", "spine", (0, 0, 1.12), (0, 0, 1.42)),
    ("neck", "chest", (0, 0, 1.42), (0, 0, 1.52)),
    ("head", "neck", (0, 0, 1.52), (0, 0, 1.72)),
]
for side, s in (("r", 1), ("l", -1)):
    B += [
        ("upper_arm_" + side, "chest", (s * 0.33, 0, 1.38), (s * 0.365, 0, 1.03)),
        ("forearm_" + side, "upper_arm_" + side, (s * 0.37, 0, 1.03), (s * 0.385, 0, 0.75)),
        ("hand_" + side, "forearm_" + side, (s * 0.385, 0, 0.74), (s * 0.385, 0, 0.6)),
        ("thigh_" + side, "hips", (s * 0.12, 0, 0.86), (s * 0.12, 0, 0.48)),
        ("shin_" + side, "thigh_" + side, (s * 0.12, 0, 0.47), (s * 0.12, 0, 0.09)),
        ("foot_" + side, "shin_" + side, (s * 0.12, 0, 0.09), (s * 0.12, 0.17, 0.03)),
    ]
bk.armature(B)
body = bk.finish("androide", tex_size=2048, bake=True, out_dir=OUT)

# ------------------------------------------------------------------ animaciones
# Mismos ejes que robot.py: X+ adelanta brazos y piernas; X− en columna/pecho inclina
# hacia adelante; brazo derecho afuera Y−, izquierdo Y+; Z gira el torso.
# Guardia de caballero caído: hombros caídos, cabeza ladeada, los dos brazos al frente.
READY = {"spine": (-6, 0, 0), "chest": (-6, 0, 6), "neck": (-6, 0, 0), "head": (-10, 0, -10),
         "upper_arm_r": (26, -10, 0), "forearm_r": (48, 0, 0), "hand_r": (-10, 0, 0),
         "upper_arm_l": (20, 12, 0), "forearm_l": (40, 0, 0), "hand_l": (10, 0, 0),
         "thigh_r": (10, 0, 0), "shin_r": (-14, 0, 0), "foot_r": (4, 0, 0), "thigh_l": (-6, 0, 0), "shin_l": (-8, 0, 0), "foot_l": (8, 0, 0),
         "root_pos": (0, 0, -0.03)}


def P(**kw):
    d = dict(READY)
    d.update(kw)
    return d


def gait(ph, amp, knee, arm, lean, bob):
    """Paso de caballero: la pierna humana dobla, la robótica va rígida y golpea el suelo."""
    s = math.sin(ph)
    c = math.cos(ph)
    return P(thigh_r=(s * amp, 0, 0), thigh_l=(-s * amp * 0.85, 0, 0),
             shin_r=(-max(0.0, c) * knee - 6, 0, 0), shin_l=(-max(0.0, -c) * knee * 0.55 - 4, 0, 0),
             foot_r=(max(0.0, -s) * 12, 0, 0), foot_l=(max(0.0, s) * 8, 0, 0),
             upper_arm_r=(26 - s * arm, -10, 0), upper_arm_l=(20 + s * arm, 12, 0),
             spine=(lean, 0, s * 6), chest=(-6, 0, 6 - s * 8), head=(-10, 0, -10 + s * 4),
             root_pos=(0, 0, -0.03 - abs(c) * bob))


def idle_keys():
    keys = []
    for i in range(13):
        t = i * 0.25
        b = math.sin(t / 1.5 * 2 * math.pi)
        pose = P(chest=(-6 + b * 3, 0, 6), head=(-10 + b * 2, 0, -10), upper_arm_r=(26 - b * 2, -10, 0), upper_arm_l=(20 + b * 2, 12, 0))
        if abs(t - 1.75) < 0.01:
            # Falla del sistema: la cabeza se sacude hacia el lado de cromo
            pose["head"] = (4, 0, 40)
            pose["neck"] = (-2, 0, 10)
            pose["hand_l"] = (50, 0, 0)
        if abs(t - 2.0) < 0.01:
            pose["head"] = (-12, 0, -14)
        keys.append((t, pose))
    return keys


bk.action("idle", idle_keys(), loop=True)
bk.action("walk", [(i / 8.0 * 1.1, gait(i / 8.0 * 2 * math.pi, 26, 52, 14, -8, 0.03)) for i in range(9)], loop=True)
bk.action("run", [(i / 8.0 * 0.72, gait(i / 8.0 * 2 * math.pi, 42, 80, 30, -20, 0.06)) for i in range(9)], loop=True)

# --- Combo de dos hojas: diagonal derecha, revés izquierdo y tajo cruzado a dos manos
bk.action("dual", [
    (0.0, P()),
    (0.3, P(upper_arm_r=(150, -40, 0), forearm_r=(40, 0, 0), upper_arm_l=(40, 30, 0), forearm_l=(60, 0, 0), chest=(4, 0, -32), spine=(0, 0, -10), head=(-6, 0, 16), thigh_l=(-12, 0, 0), root_pos=(0, -0.05, -0.04))),
    (0.45, P(upper_arm_r=(40, 30, 0), forearm_r=(8, 0, 0), upper_arm_l=(30, 25, 0), forearm_l=(40, 0, 0), chest=(-14, 0, 30), spine=(-12, 0, 10), head=(-12, 0, -8), thigh_r=(30, 0, 0), shin_r=(-28, 0, 0), thigh_l=(-14, 0, 0), root_pos=(0, 0.14, -0.07))),
    (0.66, P(upper_arm_r=(40, 30, 0), forearm_r=(30, 0, 0), upper_arm_l=(130, 50, 0), forearm_l=(40, 0, 0), chest=(-6, 0, 40), spine=(-8, 0, 12), head=(-10, 0, -20), thigh_r=(30, 0, 0), shin_r=(-28, 0, 0), root_pos=(0, 0.16, -0.06))),
    (0.83, P(upper_arm_r=(30, 20, 0), forearm_r=(30, 0, 0), upper_arm_l=(50, -30, 0), forearm_l=(8, 0, 0), chest=(-14, 0, -32), spine=(-12, 0, -10), head=(-12, 0, 14), thigh_l=(30, 0, 0), shin_l=(-26, 0, 0), thigh_r=(-12, 0, 0), root_pos=(0, 0.3, -0.07))),
    (1.05, P(upper_arm_r=(165, -20, 0), forearm_r=(30, 0, 0), upper_arm_l=(160, 20, 0), forearm_l=(30, 0, 0), chest=(10, 0, 0), spine=(6, 0, 0), head=(0, 0, 0), thigh_l=(20, 0, 0), shin_l=(-20, 0, 0), root_pos=(0, 0.3, -0.06))),
    (1.21, P(upper_arm_r=(50, 25, 0), forearm_r=(4, 0, 0), upper_arm_l=(50, -25, 0), forearm_l=(4, 0, 0), chest=(-30, 0, 0), spine=(-20, 0, 0), head=(-10, 0, 0), thigh_r=(48, 0, 0), shin_r=(-55, 0, 0), thigh_l=(-24, 0, 0), shin_l=(-12, 0, 0), root_pos=(0, 0.5, -0.16))),
    (1.55, P(upper_arm_r=(45, 25, 0), forearm_r=(10, 0, 0), upper_arm_l=(45, -25, 0), forearm_l=(10, 0, 0), chest=(-32, 0, 0), spine=(-22, 0, 0), head=(-20, 0, 8), thigh_r=(48, 0, 0), shin_r=(-58, 0, 0), thigh_l=(-24, 0, 0), shin_l=(-12, 0, 0), root_pos=(0, 0.5, -0.18))),
    (2.0, P()),
])
# --- Estocada doble: recoge las dos hojas a la cadera y se lanza
bk.action("thrust", [
    (0.0, P()),
    (0.42, P(upper_arm_r=(-30, -10, 0), forearm_r=(110, 0, 0), upper_arm_l=(-28, 10, 0), forearm_l=(110, 0, 0), chest=(4, 0, 0), spine=(-4, 0, 0), thigh_r=(-10, 0, 0), shin_r=(-30, 0, 0), thigh_l=(34, 0, 0), shin_l=(-44, 0, 0), root_pos=(0, -0.1, -0.1))),
    (0.5, P(upper_arm_r=(-32, -10, 0), forearm_r=(112, 0, 0), upper_arm_l=(-30, 10, 0), forearm_l=(112, 0, 0), chest=(6, 0, 0), spine=(-4, 0, 0), thigh_r=(-10, 0, 0), shin_r=(-32, 0, 0), thigh_l=(34, 0, 0), shin_l=(-46, 0, 0), root_pos=(0, -0.11, -0.11))),
    (0.6, P(upper_arm_r=(90, 4, 0), forearm_r=(0, 0, 0), upper_arm_l=(88, -4, 0), forearm_l=(0, 0, 0), chest=(-16, 0, 0), spine=(-20, 0, 0), head=(-4, 0, 0), thigh_r=(58, 0, 0), shin_r=(-44, 0, 0), thigh_l=(-36, 0, 0), shin_l=(-14, 0, 0), root_pos=(0, 0.45, -0.14))),
    (0.9, P(upper_arm_r=(86, 4, 0), forearm_r=(6, 0, 0), upper_arm_l=(84, -4, 0), forearm_l=(6, 0, 0), chest=(-18, 0, 0), spine=(-24, 0, 0), head=(-14, 0, 6), thigh_r=(58, 0, 0), shin_r=(-48, 0, 0), thigh_l=(-36, 0, 0), shin_l=(-14, 0, 0), root_pos=(0, 0.47, -0.16))),
    (1.45, P()),
])
# --- Compilar: levanta la mano derecha mientras el código arma una espada de luz y
#     la deja caer en un tajo enorme a dos manos (versión pequeña del "script" de ADA-7)
bk.action("compile", [
    (0.0, P()),
    (0.35, P(upper_arm_r=(120, -30, 0), forearm_r=(20, 0, 0), hand_r=(-30, 0, 0), upper_arm_l=(10, 30, 0), forearm_l=(70, 0, 0), chest=(4, 0, -10), head=(10, 0, 0))),
    (0.9, P(upper_arm_r=(160, -20, 0), forearm_r=(10, 0, 0), hand_r=(-20, 0, 0), upper_arm_l=(10, 30, 0), forearm_l=(70, 0, 0), chest=(10, 0, -12), spine=(6, 0, 0), head=(16, 0, 0), root_pos=(0, 0, -0.01))),
    (1.15, P(upper_arm_r=(176, -6, 0), forearm_r=(28, 0, 0), upper_arm_l=(168, 14, 0), forearm_l=(36, 0, 0), chest=(14, 0, 0), spine=(8, 0, 0), head=(6, 0, 0), thigh_r=(14, 0, 0), shin_r=(-14, 0, 0), root_pos=(0, -0.08, -0.03))),
    (1.3, P(upper_arm_r=(40, -6, 0), forearm_r=(4, 0, 0), upper_arm_l=(38, 10, 0), forearm_l=(14, 0, 0), chest=(-34, 0, 0), spine=(-20, 0, 0), head=(-10, 0, 0), thigh_r=(52, 0, 0), shin_r=(-58, 0, 0), thigh_l=(-24, 0, 0), shin_l=(-12, 0, 0), root_pos=(0, 0.3, -0.17))),
    (1.75, P(upper_arm_r=(36, -6, 0), forearm_r=(4, 0, 0), upper_arm_l=(34, 10, 0), forearm_l=(14, 0, 0), chest=(-36, 0, 0), spine=(-24, 0, 0), head=(-18, 0, 6), thigh_r=(52, 0, 0), shin_r=(-60, 0, 0), thigh_l=(-24, 0, 0), shin_l=(-12, 0, 0), root_pos=(0, 0.3, -0.19))),
    (2.2, P()),
])
# --- Latigazo: el brazo de cromo se echa atrás y lanza los cables de servidor
bk.action("lash", [
    (0.0, P()),
    (0.4, P(upper_arm_l=(-50, 40, 0), forearm_l=(60, 0, 0), hand_l=(30, 0, 0), chest=(4, 0, 30), spine=(0, 0, 10), head=(-6, 0, -16), thigh_r=(16, 0, 0), thigh_l=(-12, 0, 0), root_pos=(0, -0.04, -0.04))),
    (0.48, P(upper_arm_l=(-56, 42, 0), forearm_l=(64, 0, 0), hand_l=(32, 0, 0), chest=(6, 0, 34), spine=(0, 0, 12), head=(-6, 0, -18), thigh_r=(16, 0, 0), thigh_l=(-12, 0, 0), root_pos=(0, -0.04, -0.05))),
    (0.55, P(upper_arm_l=(95, -10, 0), forearm_l=(4, 0, 0), hand_l=(-10, 0, 0), chest=(-12, 0, -30), spine=(-10, 0, -10), head=(-10, 0, 10), thigh_l=(26, 0, 0), shin_l=(-24, 0, 0), thigh_r=(-10, 0, 0), root_pos=(0, 0.12, -0.06))),
    (0.85, P(upper_arm_l=(70, -20, 0), forearm_l=(10, 0, 0), chest=(-14, 0, -38), spine=(-12, 0, -12), head=(-12, 0, 12), thigh_l=(26, 0, 0), shin_l=(-26, 0, 0), thigh_r=(-10, 0, 0), root_pos=(0, 0.13, -0.07))),
    (1.4, P()),
])
# --- Hechizo: la garra de cromo apunta al frente, la otra mano al pecho (círculos de código)
bk.action("cast", [
    (0.0, P()),
    (0.45, P(upper_arm_l=(70, 30, 0), forearm_l=(60, 0, 0), hand_l=(-20, 0, 0), upper_arm_r=(30, -10, 0), forearm_r=(100, 0, 0), chest=(6, 0, 10), head=(6, 0, 0), root_pos=(0, 0, -0.05))),
    (0.7, P(upper_arm_l=(100, 10, 0), forearm_l=(4, 0, 0), hand_l=(-50, 0, 0), upper_arm_r=(30, -10, 0), forearm_r=(105, 0, 0), chest=(-6, 0, 16), spine=(-4, 0, 0), head=(-4, 0, 0), thigh_l=(20, 0, 0), shin_l=(-18, 0, 0), root_pos=(0, 0.06, -0.06))),
    (1.2, P(upper_arm_l=(98, 10, 0), forearm_l=(6, 0, 0), hand_l=(-45, 0, 0), upper_arm_r=(30, -10, 0), forearm_r=(105, 0, 0), chest=(-6, 0, 16), spine=(-4, 0, 0), head=(-6, 0, 0), thigh_l=(20, 0, 0), shin_l=(-18, 0, 0), root_pos=(0, 0.06, -0.06))),
    (1.7, P()),
])
# --- Pulso: se encoge con los brazos cruzados y los abre de golpe (descarga eléctrica)
bk.action("pulse", [
    (0.0, P()),
    (0.45, P(upper_arm_r=(60, 30, 0), forearm_r=(110, 0, 0), upper_arm_l=(60, -30, 0), forearm_l=(110, 0, 0), chest=(14, 0, 0), spine=(10, 0, 0), head=(20, 0, 0), thigh_r=(40, 0, 0), shin_r=(-70, 0, 0), thigh_l=(35, 0, 0), shin_l=(-65, 0, 0), root_pos=(0, -0.04, -0.16))),
    (0.6, P(upper_arm_r=(60, -90, 0), forearm_r=(10, 0, 0), upper_arm_l=(60, 90, 0), forearm_l=(10, 0, 0), chest=(-16, 0, 0), spine=(-6, 0, 0), head=(-20, 0, 0), thigh_r=(-6, 0, 6), thigh_l=(-6, 0, -6), root_pos=(0, 0, 0.02))),
    (0.9, P(upper_arm_r=(50, -80, 0), forearm_r=(15, 0, 0), upper_arm_l=(50, 80, 0), forearm_l=(15, 0, 0), chest=(-14, 0, 0), head=(-16, 0, 0), root_pos=(0, 0, 0.0))),
    (1.4, P()),
])
bk.action("hit", [(0.0, P()),
                  (0.08, P(spine=(14, 0, 10), chest=(24, 0, 12), head=(30, 0, -18), upper_arm_r=(-20, -35, 0), upper_arm_l=(-15, 40, 0), forearm_l=(60, 0, 0), thigh_r=(-12, 0, 0), shin_l=(-25, 0, 0), root_pos=(0, -0.14, -0.05))),
                  (0.3, P(spine=(6, 0, 6), chest=(10, 0, 8), head=(14, 0, 20), root_pos=(0, -0.16, -0.06))),
                  (0.65, P())])
# --- Muerte: falla del sistema, cae de rodillas sacudiéndose y se desploma de lado
bk.action("death", [
    (0.0, P()),
    (0.12, P(chest=(20, 0, 14), head=(30, 0, 30), upper_arm_r=(-20, -40, 0), upper_arm_l=(-10, 50, 0))),
    (0.3, P(chest=(10, 0, -14), head=(10, 0, -30), upper_arm_r=(10, -30, 0), upper_arm_l=(20, 30, 0))),
    (0.6, P(spine=(-18, 0, 6), chest=(-8, 0, 0), head=(-30, 0, 25), upper_arm_r=(15, -10, 0), upper_arm_l=(5, 15, 0), forearm_l=(5, 0, 0),
             thigh_r=(80, 0, 0), shin_r=(-110, 0, 0), thigh_l=(72, 0, 0), shin_l=(-105, 0, 0), foot_r=(40, 0, 0), foot_l=(40, 0, 0), root_pos=(0, 0.05, -0.42))),
    (0.8, P(spine=(-22, 0, 10), chest=(-12, 0, 0), head=(-10, 0, 45), upper_arm_r=(10, -10, 0), upper_arm_l=(5, 15, 0),
             thigh_r=(84, 0, 0), shin_r=(-114, 0, 0), thigh_l=(76, 0, 0), shin_l=(-110, 0, 0), foot_r=(40, 0, 0), foot_l=(40, 0, 0), root_pos=(0, 0.05, -0.45))),
    (1.3, P(root=(0, -84, 0), spine=(-4, 0, 6), chest=(0, 0, 0), head=(-10, 0, 30), upper_arm_r=(40, -60, 0), upper_arm_l=(60, 40, 0), forearm_r=(30, 0, 0),
            thigh_r=(40, 0, 0), shin_r=(-60, 0, 0), thigh_l=(20, 0, 0), shin_l=(-40, 0, 0), root_pos=(0.12, 0.0, 0.14))),
    (1.45, P(root=(0, -88, 0), spine=(-2, 0, 6), head=(-6, 0, 34), upper_arm_r=(42, -64, 0), upper_arm_l=(64, 44, 0), forearm_r=(28, 0, 0),
             thigh_r=(38, 0, 0), shin_r=(-58, 0, 0), thigh_l=(18, 0, 0), shin_l=(-38, 0, 0), root_pos=(0.13, 0.0, 0.13))),
])

bk.set_pose(P())
if PREVIEW:
    bk.render_preview(os.path.join(OUT, "preview_front.png"), (1.2, 2.9, 1.35), (0, 0, 1.0))
    bk.render_preview(os.path.join(OUT, "preview_back.png"), (-1.6, -2.6, 1.5), (0, 0, 1.0))
    bk.render_preview(os.path.join(OUT, "preview_cara.png"), (0.35, 0.9, 1.65), (0, 0, 1.6), size=(700, 700))
    bk.render_preview(os.path.join(OUT, "preview_dual.png"), (2.4, 1.8, 1.2), (0, 0, 1.0), action_name="dual", frame=32)
bk.set_pose({})
bk.export(os.path.join(OUT, "androide.glb"))
print("LISTO", OUT)
