"""Armas de los enemigos: hacha, espada y pistola láser de los robots medianos y la hoja
de los androides (con desgaste y óxido).
Cada arma se modela con el agarre en el origen, extendiéndose hacia −Z (abajo) y con el
filo/boca hacia +Y (al frente). En Godot quedan a lo largo de −Y con el filo hacia −Z,
que es como se pegan al hueso de la mano.

Uso:  blender -b --python arte/blender/armas.py -- <carpeta_salida> [preview] [arma ...]
(sin nombres de arma se generan todas: hacha, espada, pistola_laser, hoja_androide)
"""
import sys
import os
import math

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, panel, bolts, cable, label, hazard

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/armas")
PREVIEW = "preview" in argv
# Si se nombran armas en la línea de comandos solo se generan esas
ONLY = [a for a in argv[1:] if a != "preview"]
os.makedirs(OUT, exist_ok=True)

MATS = {
    "metal": dict(base=(0.6, 0.6, 0.62), metal=1.0, rough=0.32, rust=0.55, wear=0.3, dirt=0.45, bare=(0.8, 0.8, 0.82)),
    "acero": dict(base=(0.55, 0.56, 0.58), metal=1.0, rough=0.3, rust=0.55, wear=0.4, dirt=0.4, bare=(0.85, 0.85, 0.87)),
    "metal_oscuro": dict(base=(0.08, 0.08, 0.09), metal=0.65, rough=0.45, rust=0.5, wear=0.7, dirt=0.5, bare=(0.42, 0.42, 0.44)),
    "pintura": dict(base=(0.75, 0.2, 0.1), rough=0.5, rust=0.8, wear=0.95, dirt=0.6, bare=(0.3, 0.3, 0.32)),
    "goma": dict(base=(0.03, 0.03, 0.03), rough=0.85, rust=0.0, wear=0.15, dirt=0.3, scratches=False),
    "cinta": dict(base=(0.12, 0.12, 0.1), rough=0.9, rust=0.0, wear=0.3, dirt=0.5, scratches=False),
    "peligro": dict(base=(0.9, 0.72, 0.1), rough=0.55, rust=0.35, wear=0.9, dirt=0.5, bare=(0.18, 0.18, 0.18)),
}


def start():
    bk.reset(seed=5)
    spec = dict(MATS)
    spec["filo"] = {"emit": (0.35, 0.8, 1.0), "strength": 5.0}
    spec["boca"] = {"emit": (1.0, 0.25, 0.15), "strength": 6.0}
    bk.define_materials(spec)


def muzzle(loc):
    import bpy
    e = bpy.data.objects.new("muzzle", None)
    bpy.context.scene.collection.objects.link(e)
    e.location = loc


def finish(name, cam, target):
    body = bk.finish(name, tex_size=1024, bake=True, out_dir=OUT)
    if PREVIEW:
        bk.render_preview(os.path.join(OUT, "preview_%s.png" % name), cam, target, size=(700, 900))
    bk.export(os.path.join(OUT, name + ".glb"), actions=False)


# ------------------------------------------------------------------ hacha
def hacha():
    start()
    cyl("mango", 0.028, 1.6, (0, 0, -0.8), mat="acero", verts=12)
    for k in range(5):
        cyl("cinta_%d" % k, 0.032, 0.06, (0, 0, -0.06 - k * 0.07), (0, 0, k * 13), mat="cinta", verts=12)
    cyl("pomo", 0.04, 0.05, (0, 0, 0.03), mat="metal_oscuro", verts=12)
    box("cabeza_nucleo", (0.07, 0.16, 0.26), (0, 0.0, -1.48), mat="metal_oscuro")
    panel("hoja", (0.035, 0.46, 0.5), (0, 0.27, -1.48), (90, 0, 0), mat="pintura", taper=(1.0, 1.35))
    box("filo_hacha", (0.022, 0.05, 0.62), (0, 0.5, -1.48), mat="acero", bevel=0.006)
    box("pico", (0.045, 0.24, 0.07), (0, -0.16, -1.48), (0, 0, 0), mat="acero", taper=(0.3, 0.3))
    bolts("tornillos_hacha", [(0.04, y, z) for y in (0.08, 0.18) for z in (-1.4, -1.56)], (0, 90, 0), r=0.012)
    label("rotulo_hacha", "EMERGENCIA", (0.02, 0.24, -1.33), (90, 0, 90), size=0.045, mat="metal_oscuro")
    finish("hacha", (1.4, 1.2, -0.6), (0, 0.15, -0.9))


# ------------------------------------------------------------------ espada
def espada():
    start()
    cyl("empunadura", 0.026, 0.26, (0, 0, -0.03), mat="cinta", verts=12)
    cyl("pomo", 0.04, 0.05, (0, 0, 0.12), mat="metal_oscuro", verts=10)
    box("guarda", (0.06, 0.3, 0.05), (0, 0, -0.18), mat="metal_oscuro")
    bolts("tornillos_guarda", [(0.032, y, -0.18) for y in (-0.1, 0.1)], (0, 90, 0), r=0.01)
    panel("hoja", (0.018, 0.13, 1.25), (0, 0.0, -0.84), (0, 0, 0), mat="acero", inset=0.01, taper=(1.0, 1.0))
    box("punta", (0.018, 0.13, 0.16), (0, 0.0, -1.53), (0, 0, 0), mat="acero", taper=(0.2, 0.05))
    box("filo", (0.02, 0.012, 1.2), (0, 0.067, -0.86), mat="filo", bevel=0.002)
    for k in range(7):
        box("sierra_%d" % k, (0.016, 0.03, 0.03), (0, -0.075, -0.4 - k * 0.12), (45, 0, 0), mat="acero", bevel=0.002)
    cable("cable_espada", [(0, -0.05, -0.2), (0.03, -0.12, -0.12), (0.02, -0.06, -0.02)], 0.008, sag=0.0)
    finish("espada", (1.3, 1.0, -0.5), (0, 0.0, -0.75))


# ------------------------------------------------------------------ pistola láser
def pistola_laser():
    start()
    box("mango", (0.05, 0.07, 0.16), (0, -0.04, -0.02), (25, 0, 0), mat="goma")
    box("cuerpo", (0.09, 0.12, 0.26), (0, 0.02, -0.2), mat="metal_oscuro")
    panel("tapa", (0.095, 0.08, 0.2), (0, 0.06, -0.2), (0, 0, 0), mat="pintura")
    for k in range(4):
        cyl("bobina_%d" % k, 0.05, 0.02, (0, 0.02, -0.36 - k * 0.04), mat="acero", verts=16)
    cyl("canon", 0.03, 0.2, (0, 0.02, -0.46), mat="metal_oscuro", verts=14)
    cyl("boca_aro", 0.036, 0.02, (0, 0.02, -0.565), mat="acero", verts=14)
    cyl("boca", 0.024, 0.012, (0, 0.02, -0.578), mat="boca", verts=14)
    box("bateria", (0.07, 0.06, 0.1), (0, -0.07, -0.18), mat="peligro")
    cable("cable_pistola", [(0, -0.09, -0.13), (0.06, -0.14, -0.2), (0.0, -0.08, -0.28)], 0.008, sag=0.02)
    muzzle((0, 0.02, -0.6))
    finish("pistola_laser", (0.7, 0.6, -0.1), (0, 0.0, -0.28))


# ------------------------------------------------------------------ hoja de androide
def hoja_androide():
    """Espada de caballero de los androides: hoja recta mellada con canal de datos cian
    (como las espadas dobles de ADA-7), guarda en cruz oxidada y empuñadura de cuero."""
    start()
    cyl("empunadura", 0.022, 0.2, (0, 0, -0.02), mat="cinta", verts=10)
    for k in range(4):
        cyl("tira_%d" % k, 0.025, 0.025, (0, 0, 0.05 - k * 0.045), (0, 0, k * 20), mat="cinta", verts=10)
    cyl("pomo", 0.033, 0.04, (0, 0, 0.1), mat="metal_oscuro", verts=8)
    box("guarda", (0.05, 0.26, 0.04), (0, 0, -0.14), mat="metal_oscuro", taper=(1.0, 0.8))
    for s in (-1, 1):
        box("guarda_punta_%d" % s, (0.04, 0.05, 0.05), (0, s * 0.13, -0.15), (s * 25, 0, 0), mat="metal_oscuro")
    panel("hoja", (0.016, 0.085, 0.95), (0, 0.0, -0.64), (0, 0, 0), mat="acero", inset=0.008, taper=(1.0, 1.0))
    box("punta", (0.016, 0.085, 0.14), (0, 0.0, -1.18), (0, 0, 0), mat="acero", taper=(0.15, 0.05))
    box("canal", (0.019, 0.012, 0.8), (0, 0.0, -0.6), mat="filo", bevel=0.002)
    # Mellas en el filo
    for k in range(4):
        box("mella_%d" % k, (0.02, 0.02, 0.025), (0, 0.045, -0.4 - k * 0.19), (45, 0, 0), mat="metal_oscuro", bevel=0.001)
    cable("cable_hoja", [(0, 0.02, -0.16), (0.03, 0.06, -0.08), (0.02, 0.03, 0.0)], 0.006, sag=0.0)
    finish("hoja_androide", (1.0, 0.8, -0.4), (0, 0.0, -0.6))


for fn in (hacha, espada, pistola_laser, hoja_androide):
    if not ONLY or fn.__name__ in ONLY:
        fn()
print("LISTO", OUT)
