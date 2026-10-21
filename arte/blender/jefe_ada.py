"""Tercer jefe: "ADA-7, la Administradora del Núcleo" (boss_computo/boss_admin.gd).
Androide de casi 5 m: la mitad derecha conserva su traje sastre oscuro (rasgado,
quemado y con la credencial "ADMIN" colgando) y la piel sintética con grietas; la mitad
izquierda es un exoesqueleto de cromo rayado con pistones y cableado expuesto. La pierna
robótica izquierda (su punto débil) tiene costuras que brillan naranja. En la espalda
carga un rack de servidores abollado con luces. Los cables que cuelgan del rack, las
espadas y las armas "compiladas" siguen siendo las del código.

Materiales que el código anima (boss_skin.gd los reemplaza): "ojos" (visor), "nucleo"
(núcleo del pecho) y "debil" (costuras de la pierna izquierda).

Uso:  blender -b --python arte/blender/jefe_ada.py -- <carpeta_salida> [preview]
"""
import sys
import os
import math
import random

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, sphere, panel, bolts, cable, piston, vents, label, cloth, blob, limb

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/jefes")
PREVIEW = "preview" in argv
os.makedirs(OUT, exist_ok=True)


def G(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return (x, -z, y)


def S(x, y, z):
    """Tamaño de caja de Godot (ancho, alto, fondo) -> Blender (ancho, fondo, alto)."""
    return (x, z, y)


bk.reset(seed=303)
bk.define_materials({
    "traje": dict(base=(0.022, 0.022, 0.028), rough=0.8, rust=0.15, wear=0.75, dirt=1.0, bare=(0.12, 0.12, 0.13), scratches=False, soot=0.7, streaks=0.3),
    "blusa": dict(base=(0.4, 0.4, 0.38), rough=0.9, rust=0.3, wear=0.4, dirt=1.1, bare=(0.2, 0.19, 0.17), scratches=False, soot=0.5, streaks=0.5),
    "cromo": dict(base=(0.66, 0.68, 0.72), metal=1.0, rough=0.22, rust=0.6, wear=0.3, dirt=0.7, bare=(0.85, 0.86, 0.9), streaks=0.55, soot=0.45),
    "oscuro": dict(base=(0.05, 0.05, 0.06), metal=0.7, rough=0.45, rust=0.8, wear=0.7, dirt=0.7, bare=(0.4, 0.4, 0.42), streaks=0.4, soot=0.4),
    "metal": dict(base=(0.4, 0.4, 0.42), metal=1.0, rough=0.4, rust=0.9, wear=0.5, dirt=0.6, bare=(0.75, 0.75, 0.77)),
    "metal_oscuro": dict(base=(0.05, 0.05, 0.06), metal=0.7, rough=0.45, rust=0.8, wear=0.7, dirt=0.7, bare=(0.4, 0.4, 0.42)),
    "rack": dict(base=(0.06, 0.065, 0.075), metal=0.6, rough=0.5, rust=1.1, wear=0.8, dirt=0.9, bare=(0.4, 0.4, 0.42), streaks=0.8, soot=0.6),
    "goma": dict(base=(0.02, 0.02, 0.025), rough=0.8, rust=0.0, wear=0.2, dirt=0.4, scratches=False),
    "piel": dict(skin=True, base=(0.42, 0.3, 0.25), veins=0.12, vein_col=(0.3, 0.18, 0.2), blotch=0.35, blotch_col=(0.3, 0.2, 0.18), rough=0.45, wet=0.1, dirt=0.4),
    "pelo": dict(base=(0.015, 0.012, 0.018), rough=0.55, rust=0.0, wear=0.3, dirt=0.4, bare=(0.08, 0.07, 0.09), scratches=False),
    "cuero": dict(base=(0.02, 0.018, 0.02), rough=0.5, rust=0.0, wear=0.8, dirt=0.8, bare=(0.15, 0.13, 0.12)),
    "credencial": dict(base=(0.6, 0.6, 0.58), rough=0.4, rust=0.0, wear=0.4, dirt=0.8, bare=(0.3, 0.3, 0.3), scratches=False),
    "ojos": {"emit": (0.35, 0.85, 1.0), "strength": 6.0},
    "nucleo": {"emit": (0.3, 0.85, 1.0), "strength": 4.0},
    "debil": {"emit": (1.0, 0.45, 0.1), "strength": 3.0},
    "linea": {"emit": (0.3, 0.85, 1.0), "strength": 2.5},
    "led_v": {"emit": (0.3, 1.0, 0.4), "strength": 5.0},
    "led_r": {"emit": (1.0, 0.25, 0.2), "strength": 5.0},
})
rng = random.Random(7)

# ------------------------------------------------------------------ cadera
blob("cadera", 0.45, G(0.05, 2.25, 0), (1.0, 0.65, 0.5), bone="pelvis", mat="traje", lumps=0.03)
box("cadera_cromo", S(0.45, 0.46, 0.62), G(-0.26, 2.25, 0), bone="pelvis", mat="cromo", bevel=0.05)
cyl("cinturon", 0.48, 0.07, G(0.03, 2.43, 0), bone="pelvis", mat="cuero", verts=28, r2=0.47)
box("hebilla", (0.12, 0.03, 0.08), G(0.05, 2.43, -0.33), bone="pelvis", mat="metal", bevel=0.008)
cloth("saco_faldon", 0.55, 0.42, G(0.18, 2.42, -0.31), (4, 0, 0), bone="pelvis", mat="traje", nx=10, ny=8, tatter=0.45, holes=0.04, flare=0.04, seed=11)
cloth("saco_faldon_atras", 0.6, 0.45, G(0.12, 2.42, 0.32), (0, 0, 180), bone="pelvis", mat="traje", nx=10, ny=8, tatter=0.5, holes=0.05, seed=12)

# ------------------------------------------------------------------ piernas
# Derecha: pantalón del traje y bota
limb("muslo_r", [G(0.3, 2.2, 0), G(0.3, 1.65, -0.01), G(0.3, 1.12, 0)], [0.21, 0.19, 0.16], bone="hip_r", mat="traje", lumps=0.05)
sphere("rodilla_r", 0.16, G(0.3, 1.1, 0), bone="kn_r", mat="traje", segs=16)
limb("pierna_r", [G(0.3, 1.08, 0), G(0.3, 0.6, 0.01), G(0.3, 0.2, 0)], [0.16, 0.15, 0.13], bone="kn_r", mat="traje", lumps=0.05)
box("rasgon_pierna", (0.16, 0.03, 0.2), G(0.3, 0.75, -0.14), (8, 0, 6), bone="kn_r", mat="cromo", bevel=0.02)
box("bota_r", S(0.36, 0.22, 0.66), G(0.3, 0.06, -0.12), bone="an_r", mat="cuero", bevel=0.06)
box("tacon_r", S(0.12, 0.16, 0.12), G(0.3, -0.01, 0.15), bone="an_r", mat="cuero", bevel=0.02)
cyl("cana_bota_r", 0.15, 0.3, G(0.3, 0.22, 0), bone="an_r", mat="cuero", verts=18, r2=0.16)
# Izquierda: pierna robótica (punto débil, costuras naranjas)
sphere("cadera_l", 0.2, G(-0.3, 2.15, 0), bone="hip_l", mat="cromo", segs=18)
box("muslo_l", S(0.3, 0.95, 0.34), G(-0.3, 1.63, 0), bone="hip_l", mat="cromo", bevel=0.05)
for px in (-0.14, 0.14):
    piston("piston_muslo_l_%d" % int(px * 100), G(-0.3 + px, 2.05, -0.22), G(-0.3 + px, 1.2, -0.22), 0.045, bone="hip_l")
box("debil_muslo", S(0.08, 0.6, 0.02), G(-0.3, 1.63, -0.18), bone="hip_l", mat="debil", bevel=0.005)
for k in range(3):
    cable("cable_muslo_%d" % k, [G(-0.42, 2.0 - k * 0.05, 0.05), G(-0.47, 1.6, 0.1 + k * 0.03), G(-0.42, 1.2, 0.04)], 0.018, bone="hip_l", mat="goma" if k != 1 else "linea", sag=0.0)
sphere("rodilla_l", 0.18, G(-0.3, 1.1, 0), bone="kn_l", mat="oscuro", segs=16)
sphere("rodilla_nucleo", 0.11, G(-0.3, 1.1, -0.1), bone="kn_l", mat="debil", segs=14)
box("espinilla_l", S(0.28, 0.95, 0.32), G(-0.3, 0.6, 0), bone="kn_l", mat="cromo", bevel=0.05)
cyl("piston_pant_l", 0.05, 0.85, G(-0.3, 0.6, 0.2), bone="kn_l", mat="oscuro", verts=12)
box("debil_espinilla", S(0.07, 0.5, 0.02), G(-0.3, 0.6, -0.165), bone="kn_l", mat="debil", bevel=0.005)
box("espinilla_abollada", (0.1, 0.04, 0.12), G(-0.22, 0.4, -0.16), (10, 0, 20), bone="kn_l", mat="oscuro", bevel=0.02)
box("pie_l", S(0.36, 0.16, 0.5), G(-0.3, 0.06, -0.05), bone="an_l", mat="oscuro", bevel=0.04)
for f in range(3):
    box("garra_pie_%d" % f, S(0.08, 0.08, 0.32), G(-0.42 + f * 0.12, 0.04, -0.48), bone="an_l", mat="cromo", taper=(0.7, 0.7), bevel=0.02)

# ------------------------------------------------------------------ torso
blob("abdomen", 0.36, G(0.06, 2.75, 0), (0.95, 0.9, 0.62), bone="spine", mat="traje", lumps=0.03)
for k in range(4):
    box("costilla_cromo_%d" % k, S(0.38, 0.06, 0.48), G(-0.19, 2.55 + k * 0.14, 0), bone="spine", mat="cromo", bevel=0.02)
cyl("columna", 0.06, 0.6, G(-0.05, 2.75, 0.2), bone="spine", mat="cromo", verts=10)
# Pecho: saco rasgado del lado derecho, placa de cromo del izquierdo
blob("pecho_traje", 0.5, G(0.08, 3.45, 0), (1.0, 0.82, 0.62), bone="chest", mat="traje", lumps=0.03)
blob("pecho_cromo", 0.42, G(-0.27, 3.45, -0.02), (0.75, 1.0, 0.78), bone="chest", mat="cromo", lumps=0.02)
for k in range(4):
    box("ventila_pecho_%d" % k, S(0.42, 0.035, 0.05), G(-0.27, 3.2 + k * 0.16, -0.34), bone="chest", mat="oscuro", bevel=0.008)
box("linea_division", S(0.03, 0.75, 0.03), G(-0.02, 3.45, -0.33), bone="chest", mat="linea", bevel=0.005)
cyl("nucleo_aro", 0.17, 0.08, G(0, 3.5, -0.34), (90, 0, 0), bone="chest", mat="oscuro", verts=24)
cyl("nucleo", 0.13, 0.08, G(0, 3.5, -0.36), (90, 0, 0), bone="chest", mat="nucleo", verts=24)
# Solapa, blusa y credencial colgando
cloth("solapa", 0.28, 0.5, G(0.2, 3.85, -0.32), (10, 0, -10), bone="chest", mat="traje", nx=6, ny=8, tatter=0.25, holes=0.0, seed=13)
box("blusa_cuello", S(0.3, 0.12, 0.2), G(0.05, 3.88, -0.18), (0, 0, 0), bone="chest", mat="blusa", bevel=0.03)
cable("cordon", [G(0.1, 3.88, -0.3), G(0.22, 3.6, -0.36), G(0.25, 3.35, -0.36)], 0.012, bone="chest", mat="goma", sag=0.0)
box("credencial", S(0.14, 0.2, 0.015), G(0.25, 3.25, -0.37), (0, 0, 6), bone="chest", mat="credencial", bevel=0.01)
label("credencial_txt", "ADMIN", G(0.25, 3.2, -0.38), (90, 0, 0), size=0.04, bone="chest", mat="oscuro")
# Quemaduras y rasgones del saco
for i in range(5):
    blob("quemadura_%d" % i, 0.06, G(0.15 + rng.uniform(-0.15, 0.25), 3.1 + rng.uniform(0, 0.6), -0.33), (1.2, 1.0, 0.25), bone="chest", mat="oscuro", lumps=0.3)
# Rack de servidores abollado en la espalda
box("rack", S(0.85, 1.0, 0.5), G(0, 3.5, 0.55), bone="chest", mat="rack", bevel=0.03)
for k in range(6):
    box("rack_bahia_%d" % k, S(0.75, 0.1, 0.02), G(0, 3.13 + k * 0.15, 0.81), bone="chest", mat="oscuro", bevel=0.008)
    box("rack_led_%d" % k, S(0.04, 0.04, 0.02), G(-0.3 + (k % 3) * 0.08, 3.15 + k * 0.15, 0.82), bone="chest", mat="led_v" if k % 2 == 0 else "led_r", bevel=0.004)
    vents("rack_ventila_%d" % k, G(0.22, 3.17 + k * 0.15, 0.82), 3, 0.025, (0.2, 0.01, 0.01), bone="chest")
box("rack_abolladura", (0.2, 0.06, 0.18), G(0.25, 3.8, 0.8), (15, 10, 20), bone="chest", mat="rack", bevel=0.03)
label("rack_txt", "NUCLEO-01", G(0, 4.05, 0.81), (90, 0, 180), size=0.07, bone="chest", mat="metal")
for k in range(5):
    cyl("rack_puerto_%d" % k, 0.05, 0.06, G(-0.3 + k * 0.15, 3.25, 0.82), (90, 0, 0), bone="chest", mat="metal", verts=10)

# ------------------------------------------------------------------ cuello y cabeza
limb("cuello", [G(0.04, 3.88, 0), G(0.04, 4.0, 0), G(0.04, 4.16, 0)], [0.14, 0.13, 0.13], bone="neck", mat="piel")
cyl("cuello_cromo", 0.09, 0.32, G(-0.08, 4.02, 0), bone="neck", mat="cromo", verts=12)
for k in range(3):
    cable("cuello_cable_%d" % k, [G(-0.1 - k * 0.02, 3.9, 0.05), G(-0.14 - k * 0.02, 4.02, 0.06), G(-0.1, 4.14, 0.03)], 0.012, bone="neck", mat="goma")
blob("cara", 0.27, G(0.03, 4.47, 0), (0.88, 1.0, 1.12), bone="head", mat="piel", lumps=0.02, seed=3)
blob("craneo_cromo", 0.272, G(-0.06, 4.48, 0.0), (0.72, 1.0, 1.14), bone="head", mat="cromo", lumps=0.015, seed=4)
box("grieta_cara", S(0.02, 0.5, 0.02), G(0.0, 4.47, -0.275), bone="head", mat="linea", bevel=0.004)
for i in range(4):
    box("grieta_piel_%d" % i, (0.05, 0.008, 0.008), G(0.03 + i * 0.012, 4.38 + i * 0.05, -0.27), (0, 20 * (i % 2) - 10, 0), bone="head", mat="oscuro", bevel=0)
sphere("ojo_humano_blanco", 0.045, G(0.11, 4.53, -0.235), (1.0, 0.6, 0.65), bone="head", mat="blusa", segs=12)
sphere("ojo_humano", 0.022, G(0.11, 4.53, -0.262), bone="head", mat="oscuro", segs=10)
box("ceja", (0.1, 0.02, 0.02), G(0.11, 4.6, -0.255), (0, -8, 0), bone="head", mat="pelo", bevel=0.006)
box("visor_marco", S(0.17, 0.07, 0.04), G(-0.12, 4.53, -0.262), bone="head", mat="oscuro", bevel=0.01)
box("ojos", S(0.14, 0.035, 0.03), G(-0.12, 4.53, -0.275), bone="head", mat="ojos", bevel=0.006)
blob("nariz", 0.035, G(0.04, 4.45, -0.27), (0.7, 1.0, 1.1), bone="head", mat="piel", lumps=0.05)
box("boca", (0.11, 0.015, 0.02), G(0.06, 4.33, -0.255), bone="head", mat="oscuro", bevel=0.005)
# Melena oscura del lado humano (corte asimétrico) y cables del lado de cromo
blob("pelo", 0.25, G(0.08, 4.62, 0.04), (0.8, 0.85, 1.2), bone="head", mat="pelo", lumps=0.1, seed=5)
limb("melena", [G(0.17, 4.55, 0.1), G(0.22, 4.3, 0.16), G(0.2, 4.0, 0.18)], [0.12, 0.11, 0.05], bone="head", mat="pelo", lumps=0.15)
limb("fleco", [G(0.0, 4.72, -0.2), G(0.15, 4.68, -0.24), G(0.24, 4.52, -0.2)], [0.06, 0.06, 0.02], bone="head", mat="pelo", lumps=0.1)
for k in range(5):
    cable("cable_craneo_%d" % k, [G(-0.16 - k * 0.025, 4.6 - k * 0.04, 0.12 + k * 0.03), G(-0.24 - k * 0.02, 4.3, 0.22 + k * 0.02), G(-0.2, 3.95 - k * 0.04, 0.2)],
          0.018, bone="head", mat="goma" if k % 2 else "oscuro", sag=0.02)
bolts("tornillos_craneo", [G(-0.2, 4.62, -0.12), G(-0.24, 4.45, -0.14), G(-0.22, 4.3, -0.12)], (0, 90, 0), bone="head", r=0.018, h=0.02)

# ------------------------------------------------------------------ brazos
# Derecho: manga del saco (rota en el codo) y mano humana con la piel agrietada
sphere("hombro_r", 0.22, G(0.68, 3.75, 0), bone="sh_r", mat="traje", segs=18)
box("hombrera_r", S(0.5, 0.2, 0.55), G(0.73, 3.85, 0), bone="sh_r", mat="traje", bevel=0.08)
limb("brazo_r", [G(0.68, 3.7, 0), G(0.68, 3.25, 0.0), G(0.68, 2.82, 0)], [0.15, 0.14, 0.13], bone="sh_r", mat="traje", lumps=0.04)
cloth("manga_rota_r", 0.3, 0.16, G(0.68, 2.92, -0.14), (0, 0, 0), bone="sh_r", mat="traje", nx=8, ny=4, tatter=0.6, seed=14)
limb("antebrazo_r", [G(0.68, 2.8, 0), G(0.68, 2.35, -0.01), G(0.68, 1.92, 0)], [0.12, 0.11, 0.09], bone="el_r", mat="piel", lumps=0.04)
box("grieta_brazo", (0.03, 0.12, 0.25), G(0.76, 2.2, -0.04), bone="el_r", mat="cromo", bevel=0.01)
box("mano_r", S(0.2, 0.22, 0.24), G(0.68, 1.82, 0), bone="wr_r", mat="piel", bevel=0.05)
for f in range(3):
    limb("dedo_r_%d" % f, [G(0.62 + f * 0.06, 1.72, -0.03), G(0.62 + f * 0.06, 1.62, -0.06), G(0.62 + f * 0.06, 1.55, -0.09)], [0.028, 0.025, 0.02], bone="wr_r", mat="piel", verts=8)
# Izquierdo: exoesqueleto de cromo
sphere("hombro_l", 0.21, G(-0.68, 3.75, 0), bone="sh_l", mat="cromo", segs=18)
panel("hombrera_l", (0.5, 0.55, 0.12), G(-0.73, 3.87, 0), (0, -15, 0), bone="sh_l", mat="cromo", bevel=0.04)
box("brazo_l", S(0.2, 0.85, 0.22), G(-0.68, 3.3, 0), bone="sh_l", mat="cromo", bevel=0.04)
piston("piston_brazo_l", G(-0.68, 3.65, -0.16), G(-0.68, 2.9, -0.16), 0.04, bone="sh_l")
for k in range(3):
    cable("cable_brazo_l_%d" % k, [G(-0.8, 3.6 - k * 0.04, 0.05), G(-0.86, 3.3, 0.08 + k * 0.02), G(-0.8, 2.95, 0.04)], 0.014, bone="sh_l", mat="linea" if k == 1 else "goma", sag=0.0)
sphere("codo_l", 0.13, G(-0.68, 2.8, 0), bone="el_l", mat="linea", segs=14)
box("antebrazo_l", S(0.22, 0.82, 0.24), G(-0.68, 2.37, 0), bone="el_l", mat="cromo", bevel=0.04)
for k in range(3):
    box("anillo_ante_l_%d" % k, S(0.25, 0.04, 0.27), G(-0.68, 2.6 - k * 0.22, 0), bone="el_l", mat="oscuro", bevel=0.01)
box("mano_l", S(0.2, 0.22, 0.24), G(-0.68, 1.82, 0), bone="wr_l", mat="oscuro", bevel=0.04)
for f in range(3):
    box("dedo_l_%d" % f, S(0.05, 0.22, 0.05), G(-0.74 + f * 0.06, 1.62, -0.07), (-25, 0, 0), bone="wr_l", mat="cromo", taper=(0.6, 0.6), bevel=0.012)

# ------------------------------------------------------------------ esqueleto
B = [
    ("pelvis", "", G(0, 2.25, 0), G(0, 2.45, 0)),
    ("spine", "pelvis", G(0, 2.45, 0), G(0, 3.05, 0)),
    ("chest", "spine", G(0, 3.05, 0), G(0, 3.9, 0)),
    ("neck", "chest", G(0, 3.9, 0), G(0, 4.17, 0)),
    ("head", "neck", G(0, 4.17, 0), G(0, 4.8, 0)),
]
for side, s in (("l", -1), ("r", 1)):
    B += [
        ("hip_" + side, "pelvis", G(s * 0.3, 2.15, 0), G(s * 0.3, 1.1, 0)),
        ("kn_" + side, "hip_" + side, G(s * 0.3, 1.1, 0), G(s * 0.3, 0.1, 0)),
        ("an_" + side, "kn_" + side, G(s * 0.3, 0.1, 0), G(s * 0.3, 0.0, -0.4)),
        ("sh_" + side, "chest", G(s * 0.68, 3.75, 0), G(s * 0.68, 2.8, 0)),
        ("el_" + side, "sh_" + side, G(s * 0.68, 2.8, 0), G(s * 0.68, 1.9, 0)),
        ("wr_" + side, "el_" + side, G(s * 0.68, 1.9, 0), G(s * 0.68, 1.55, 0)),
    ]
bk.armature(B)
bk.finish("ada7", tex_size=2048, bake=True, out_dir=OUT)
if PREVIEW:
    bk.render_preview(os.path.join(OUT, "preview_ada7.png"), (2.6, 7.2, 3.2), (0, 0, 2.4))
    bk.render_preview(os.path.join(OUT, "preview_ada7_atras.png"), (-3.0, -6.4, 3.6), (0, 0, 2.6))
    bk.render_preview(os.path.join(OUT, "preview_ada7_cara.png"), (0.7, 1.9, 4.6), (0, 0, 4.4), size=(700, 700))
bk.export(os.path.join(OUT, "ada7.glb"), actions=False)
print("LISTO", OUT)
