"""Primer jefe: "Catedrático de Hierro, Heraldo de la Tormenta" (boss_profesor/boss_profesor.gd).

Cuerpo humano realista (malla base de Blender, ver humano.py) dentro de una armadura de
placas al estilo de Elden Ring con tecnología: peto y espaldar acanalados y grabados,
ribetes dorados gastados, costuras eléctricas azules (es el Heraldo de la Tormenta),
hombreras de cuatro láminas, gola, escarcelas, codales, brazales y grebas articulados,
escarpes de láminas, guanteletes, cota de malla debajo, yelmo cerrado con visor de
rendija y lentes que brillan, birrete con borla, toga académica hecha jirones, núcleo de
energía en la espalda y su morral y libreta encadenada de profesor.

Se construye en el espacio del nodo "Model" del jefe (el código lo escala ×1.5). Los huesos
se llaman como las articulaciones del código y boss_skin.gd las lleva a donde quedaron.

Uso:  blender -b --python arte/blender/jefe_catedratico.py -- <carpeta_salida> [preview]
"""
import sys
import os
import math

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
import humano
from bk import box, cyl, sphere, cable, label
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/jefes")
PREVIEW = "preview" in argv
os.makedirs(OUT, exist_ok=True)

bk.reset(seed=101)
bk.define_materials({
    "acero": dict(base=(0.42, 0.43, 0.46), metal=0.85, rough=0.32, rust=0.55, wear=0.55, dirt=0.75, bare=(0.62, 0.62, 0.64), streaks=0.55, soot=0.45, engrave=0.85, engrave_scale=16.0),
    "acero_liso": dict(base=(0.38, 0.39, 0.42), metal=0.85, rough=0.36, rust=0.6, wear=0.55, dirt=0.8, bare=(0.6, 0.6, 0.62), streaks=0.5, soot=0.45),
    "oro": dict(base=(0.62, 0.42, 0.12), metal=1.0, rough=0.32, rust=0.3, wear=0.6, dirt=0.8, bare=(0.75, 0.6, 0.3), soot=0.4, engrave=0.5, engrave_scale=30.0),
    "malla": dict(base=(0.1, 0.1, 0.11), metal=1.0, rough=0.45, rust=0.7, wear=0.3, dirt=0.9, bare=(0.4, 0.4, 0.42), chain=1.0, soot=0.3),
    "toga": dict(base=(0.01, 0.01, 0.012), rough=0.85, rust=0.15, wear=0.75, dirt=1.2, bare=(0.08, 0.075, 0.07), scratches=False, soot=0.5, streaks=0.3),
    "cuero": dict(base=(0.07, 0.04, 0.02), rough=0.65, rust=0.0, wear=0.9, dirt=1.0, bare=(0.2, 0.13, 0.08), soot=0.3),
    "morral": dict(base=(0.015, 0.02, 0.045), rough=0.85, rust=0.1, wear=0.8, dirt=1.0, bare=(0.13, 0.14, 0.18), scratches=False, soot=0.3),
    "libreta": dict(base=(0.2, 0.015, 0.015), rough=0.6, rust=0.1, wear=0.9, dirt=0.8, bare=(0.35, 0.25, 0.2), soot=0.3),
    "papel": dict(base=(0.5, 0.47, 0.38), rough=0.9, rust=0.4, wear=0.3, dirt=1.0, bare=(0.3, 0.27, 0.2), scratches=False, streaks=0.6),
    "metal": dict(base=(0.4, 0.4, 0.42), metal=1.0, rough=0.4, rust=0.9, wear=0.5, dirt=0.7, bare=(0.75, 0.75, 0.77)),
    "metal_oscuro": dict(base=(0.04, 0.04, 0.045), metal=0.8, rough=0.45, rust=0.8, wear=0.7, dirt=0.7, bare=(0.4, 0.4, 0.42)),
    "goma": dict(base=(0.02, 0.02, 0.025), rough=0.8, rust=0.0, wear=0.2, dirt=0.4, scratches=False),
    "piel": dict(skin=True, base=(0.36, 0.24, 0.19), veins=0.15, vein_col=(0.2, 0.1, 0.12), blotch=0.4, blotch_col=(0.28, 0.15, 0.11), rough=0.45, wet=0.12, dirt=0.1, scale=3.0, tint_attr="tinte"),
    "esclera": dict(base=(0.5, 0.46, 0.42), rough=0.15, rust=0.0, wear=0.0, dirt=0.0, scratches=False),
    "runa": {"emit": (0.35, 0.65, 1.0), "strength": 2.0},
    "ojos": {"emit": (1.0, 0.45, 0.12), "strength": 6.0},
})

# ------------------------------------------------------------------ cuerpo
H = humano.Humano("male", seed=11)
NAMES = {"pelvis": "pelvis", "spine": "spine", "chest": "chest", "head": "head",
         "upper_arm_r": "rs", "forearm_r": "re", "upper_arm_l": "ls", "forearm_l": "le",
         "thigh_r": "rh", "shin_r": "rk", "thigh_l": "lh", "shin_l": "lk"}
T = humano.targets(scale=1.0, width=1.1, pelvis_z=0.95)
H.fit(T, girth={"chest": (1.12, 1.08), "spine": (1.08, 1.05), "upper_arm_r": 1.12, "upper_arm_l": 1.12, "forearm_r": 1.1, "forearm_l": 1.1,
                "thigh_r": 1.08, "thigh_l": 1.08}, names=NAMES)
H.skin_tint(shaved=0.5, bald=0.0)
H.eye_mats(iris_size=-2.0)          # todo el ojo brilla detrás del visor

front = lambda p, n: p.y > -0.01
back = lambda p, n: p.y <= 0.01

# ------------------------------------------------------------------ cota de malla debajo
malla = {}
for rg in ("torso", "arms", "legs", "neck"):
    for k, v in H.region(rg).items():
        if H.base_co[k].z > 0.5:
            malla[k] = max(malla.get(k, 0.0), v)
H.piece("cota_malla", malla, offset=0.008, mat="malla", thresh=0.3, smooth=1)

# Botas de cuero bajo las grebas y escarpes
H.piece("botas", H.band("legs", -0.1, 0.3), offset=0.012, mat="cuero", thresh=0.2, smooth=2)
H.piece("botas_pie", "feet", offset=0.012, mat="cuero", thresh=0.2, smooth=2)

# ------------------------------------------------------------------ torso
peto = H.band("torso", 1.0, 1.42)
H.plate("peto", peto, offset=0.04, thick=0.014, fn=front, flutes=(7.0, 0.006, 0), glow="runa", smooth=4)
H.plate("espaldar", peto, offset=0.036, thick=0.012, fn=back, glow="runa", smooth=4)
H.lames("gola", H.band("neck", 1.36, 1.47), 1.36, 1.47, 2, offset=0.028, step=0.008, thick=0.008, trim_r=0.005, smooth=3)
H.lames("escarcela", H.band("torso", 0.82, 1.02), 0.82, 1.02, 3, offset=0.045, step=0.01, thick=0.01, smooth=3)
H.plate("faldar_frente", H.band("legs", 0.62, 0.84), offset=0.06, thick=0.01, fn=lambda p, n: p.y > 0.0 and abs(p.x) > 0.02, smooth=3, glow="runa")

# ------------------------------------------------------------------ brazos
for s, sg in (("r", 1), ("l", -1)):
    sh = H.zone((sg * 0.19, 0.0, 1.38), 0.16, fn=lambda p: p.z > 1.2)
    H.lames("hombrera_" + s, sh, 1.2, 1.5, 4, rigid="upper_arm_" + s, offset=0.05, step=0.014, thick=0.012, smooth=4, glow="runa")
    arms = {k: v for k, v in H.region("arms").items() if H.base_co[k].x * sg > 0}
    H.plate("brazal_" + s, H.band(arms, 1.12, 1.24), offset=0.022, thick=0.008, smooth=3)
    H.plate("codal_" + s, H.zone((sg * 0.28, -0.01, 1.08), 0.065), offset=0.032, thick=0.01, smooth=3)
    H.lames("avambrazo_" + s, H.band(arms, 0.88, 1.03), 0.88, 1.03, 3, offset=0.02, step=0.005, thick=0.008, smooth=3, trim_r=0.005)
    hands = {k: v for k, v in H.region("hands").items() if H.base_co[k].x * sg > 0}
    H.plate("guantelete_" + s, hands, offset=0.012, thick=0.006, trim=None, smooth=2, mat="acero_liso")

# ------------------------------------------------------------------ piernas
for s, sg in (("r", 1), ("l", -1)):
    legs = {k: v for k, v in H.region("legs").items() if H.base_co[k].x * sg > 0}
    H.plate("quijote_" + s, H.band(legs, 0.55, 0.8), offset=0.026, thick=0.01, fn=lambda p, n: p.y > -0.03, smooth=3)
    H.plate("rodillera_" + s, H.zone((sg * 0.11, 0.07, 0.47), 0.075, fn=lambda p: p.y > -0.02), offset=0.034, thick=0.012, smooth=3, glow="runa")
    H.plate("greba_" + s, H.band(legs, 0.08, 0.43), offset=0.022, thick=0.01, smooth=3, glow="runa")
    feet = {k: v for k, v in H.region("feet").items() if H.base_co[k].x * sg > 0}
    H.plate("escarpe_" + s, feet, offset=0.016, thick=0.008, smooth=2, thresh=0.25, trim_r=0.004)
    H.plate("escarpe_punta_" + s, H.band(feet, 0.07, 0.2, axis=1), offset=0.028, thick=0.008, smooth=2, thresh=0.25, trim_r=0.004, fn=lambda p, n: p.z > 0.02)

# ------------------------------------------------------------------ yelmo cerrado con visor
def visor(p, n):
    if p.y > 0.05 and 1.556 < p.z < 1.578:
        return False                     # rendija del visor
    return True


H.plate("yelmo", H.zone((0, 0.02, 1.565), 0.15, fn=lambda p: p.z > 1.43), offset=0.03, thick=0.01, fn=visor, smooth=4)
H.plate("yelmo_frontal", H.zone((0, 0.02, 1.565), 0.16, fn=lambda p: 1.588 < p.z < 1.612 and p.y > -0.06), offset=0.045, thick=0.01, mat="oro", trim=None, smooth=2)
H.plate("yelmo_carrillera_r", H.zone((0.06, 0.08, 1.5), 0.05), offset=0.043, thick=0.008, smooth=2, trim_r=0.004)
H.plate("yelmo_carrillera_l", H.zone((-0.06, 0.08, 1.5), 0.05), offset=0.043, thick=0.008, smooth=2, trim_r=0.004)
top = T["head_top"]
# Cresta del yelmo y birrete gastado con borla
box("cresta", (0.03, 0.26, 0.05), (0, 0.0, top.z + 0.03), bone="head", mat="oro", bevel=0.008)
box("birrete", (0.47, 0.47, 0.03), (0, 0, top.z + 0.07), (2, -1, 4), bone="head", mat="toga", bevel=0.006)
cyl("birrete_base", 0.08, 0.06, (0, 0, top.z + 0.04), bone="head", mat="toga", verts=18)
sphere("birrete_boton", 0.027, (0, 0, top.z + 0.09), bone="head", mat="oro", segs=10)
cyl("borla_cordon", 0.008, 0.2, (0.2, 0.2, top.z - 0.03), (0, -6, 0), bone="head", mat="oro", verts=6, bevel=0)
cyl("borla", 0.035, 0.08, (0.21, 0.2, top.z - 0.15), bone="head", mat="oro", verts=10, r2=0.015)

# ------------------------------------------------------------------ toga académica hecha jirones
toga = {k: v for k, v in H.region("torso").items() if H.base_co[k].y < -0.03 and H.base_co[k].z > 1.1}
H.piece("toga", toga, offset=0.07, mat="toga", thresh=0.3, smooth=3, noise=0.006, extrude=(0.95, 0.18), tatter=(0.45, 0.35))

# ------------------------------------------------------------------ accesorios (se mueven con la piel)
cin = T["pelvis"].z + 0.08
H.plate("cinturon", H.band("torso", 0.94, 0.985), offset=0.062, thick=0.01, mat="cuero", trim=None, smooth=2)
H.attach(box("hebilla", (0.1, 0.03, 0.08), (0, 0.24, cin), bone="pelvis", mat="oro", bevel=0.006))
H.attach(box("libreta", (0.06, 0.2, 0.26), (-0.34, -0.02, cin - 0.18), (0, 0, 8), bone="pelvis", mat="libreta", bevel=0.008))
H.attach(box("libreta_hojas", (0.05, 0.19, 0.24), (-0.335, -0.02, cin - 0.18), (0, 0, 8), bone="pelvis", mat="papel", bevel=0.004))
for k in range(5):
    H.attach(cyl("cadena_%d" % k, 0.018, 0.01, (-0.3 + k * 0.01, 0.07, cin - 0.03 - k * 0.03), (90 if k % 2 else 0, 0, 0), bone="pelvis", mat="metal_oscuro", verts=8, bevel=0))
H.attach(bk.blob("morral", 0.17, (0.33, -0.05, cin - 0.1), (0.42, 1.0, 0.85), bone="pelvis", mat="morral", lumps=0.06))
H.attach(bk.cloth("morral_tapa", 0.32, 0.16, (0.405, -0.05, cin + 0.02), (0, 0, 90), bone="pelvis", mat="morral", nx=8, ny=4, tatter=0.2, holes=0.0, flare=0.02))
H.attach(box("morral_hebilla", (0.015, 0.04, 0.04), (0.405, -0.05, cin - 0.06), bone="pelvis", mat="oro", bevel=0.004))
H.strap("correa", (-0.17, 0, 1.4), (0.17, 0, 0.98), 0.055, region="torso", offset=0.062, mat="morral")
# Núcleo de energía en la espalda con bobinas y cables al yelmo
H.attach(cyl("nucleo", 0.07, 0.3, (0, -0.25, 1.28), bone="chest", mat="metal_oscuro", verts=20))
for k in range(4):
    H.attach(cyl("bobina_%d" % k, 0.078, 0.02, (0, -0.25, 1.17 + k * 0.07), bone="chest", mat="runa", verts=20, bevel=0))
for s in (-1, 1):
    H.attach(cable("cable_yelmo_%d" % s, [(s * 0.05, -0.27, 1.43), (s * 0.08, -0.22, 1.52), (s * 0.08, -0.12, 1.55)], 0.012, bone="chest", mat="goma"))
# Mango de la maza en la mano derecha (la cadena y la bola son del código)
w = T["wrist_r"]
cyl("mango", 0.032, 0.62, (w.x, w.y + 0.03, w.z - 0.24), bone="re", mat="cuero", verts=10, r2=0.035)
for k in range(5):
    cyl("mango_cinta_%d" % k, 0.037, 0.03, (w.x, w.y + 0.03, w.z - 0.05 - k * 0.07), (0, 0, k * 15), bone="re", mat="metal_oscuro", verts=10)
sphere("mango_pomo", 0.05, (w.x, w.y + 0.03, w.z + 0.08), bone="re", mat="oro", segs=10)
cyl("mango_anillo", 0.05, 0.06, (w.x, w.y + 0.03, w.z - 0.55), bone="re", mat="oro", verts=12)

bk.finish("catedratico", tex_size=4096, bake=True, out_dir=OUT)
if PREVIEW:
    bk.set_pose({})
    bk.render_preview(os.path.join(OUT, "preview_catedratico.png"), (1.4, 3.2, 1.5), (0, 0, 1.0), size=(800, 1100))
    bk.render_preview(os.path.join(OUT, "preview_catedratico_atras.png"), (-1.6, -2.9, 1.7), (0, 0, 1.05), size=(800, 1100))
    bk.render_preview(os.path.join(OUT, "preview_catedratico_detalle.png"), (0.7, 1.2, 1.5), (0.1, 0, 1.3), size=(900, 900))
bk.export(os.path.join(OUT, "catedratico.glb"), actions=False)
print("LISTO", OUT)
