"""Segundo jefe: "Doctor Euclides Barrabás, el Bibliófilo Demente" (boss_bibliotecario).

Anciano altísimo (3.5 m), flaco y con panza, hecho con la malla base humana de Blender
(ver humano.py): pelo canoso alborotado, barba larga, cejas pobladas, lentes redondos (uno
estrellado), camisa de franela a cuadros rota, manchada, desfajada y arremangada, jeans
gastados con el dobladillo deshilachado, cinturón, zapatos viejos y lápices en la bolsa.

Uso:  blender -b --python arte/blender/jefe_bibliofilo.py -- <carpeta_salida> [preview]
"""
import sys
import os
import math

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
import humano
from bk import box, cyl, sphere

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/jefes")
PREVIEW = "preview" in argv
os.makedirs(OUT, exist_ok=True)

PLAID = ((0.15, 0.014, 0.011), (0.018, 0.013, 0.012), (0.3, 0.27, 0.19), 9.0)
bk.reset(seed=202)
bk.define_materials({
    "piel": dict(skin=True, base=(0.36, 0.24, 0.19), veins=0.35, vein_col=(0.2, 0.1, 0.12), blotch=0.7, blotch_col=(0.24, 0.12, 0.08), rough=0.5, wet=0.1, dirt=0.2, scale=3.0, tint_attr="tinte"),
    "labios": dict(skin=True, base=(0.28, 0.12, 0.1), veins=0.0, blotch=0.3, blotch_col=(0.2, 0.07, 0.06), rough=0.3, wet=0.4, dirt=0.0, scale=4.0),
    "esclera": dict(base=(0.5, 0.46, 0.4), rough=0.15, rust=0.0, wear=0.0, dirt=0.0, scratches=False),
    "pelo": dict(hair=True, base=(0.2, 0.19, 0.18), tip=(0.4, 0.39, 0.36), gray=0.3, rough=0.6),
    "franela": dict(base=(0.15, 0.014, 0.011), rough=0.92, rust=0.45, wear=0.55, dirt=1.4, bare=(0.2, 0.17, 0.12), scratches=False, streaks=0.95, soot=0.8, plaid=PLAID),
    "mezclilla": dict(base=(0.03, 0.055, 0.12), rough=0.92, rust=0.2, wear=0.95, dirt=1.2, bare=(0.3, 0.34, 0.4), scratches=False, soot=0.35),
    "parche": dict(base=(0.09, 0.12, 0.2), rough=0.9, rust=0.1, wear=0.6, dirt=0.9, bare=(0.3, 0.32, 0.36), scratches=False),
    "cuero": dict(base=(0.07, 0.04, 0.02), rough=0.65, rust=0.0, wear=0.95, dirt=1.0, bare=(0.2, 0.13, 0.08), soot=0.3),
    "marco": dict(base=(0.04, 0.04, 0.04), metal=0.6, rough=0.35, rust=0.4, wear=0.6, dirt=0.5, bare=(0.4, 0.4, 0.4)),
    "vidrio": dict(base=(0.04, 0.05, 0.05), metal=0.6, rough=0.06, rust=0.0, wear=0.2, dirt=0.5, bare=(0.3, 0.3, 0.3)),
    "oro": dict(base=(0.5, 0.36, 0.1), metal=1.0, rough=0.3, rust=0.3, wear=0.5, dirt=0.6, bare=(0.7, 0.55, 0.25)),
    "lapiz": dict(base=(0.6, 0.42, 0.05), rough=0.6, rust=0.0, wear=0.8, dirt=0.6, bare=(0.45, 0.3, 0.15)),
    "ojos": {"emit": (1.0, 0.85, 0.5), "strength": 3.0},
})

NAMES = {"pelvis": "pelvis", "spine": "spine", "chest": "chest", "neck": "neck", "head": "head"}
for s in ("r", "l"):
    NAMES.update({"upper_arm_" + s: "sh_" + s, "forearm_" + s: "el_" + s, "hand_" + s: "wr_" + s,
                  "thigh_" + s: "hip_" + s, "shin_" + s: "kn_" + s, "foot_" + s: "an_" + s})

H = humano.Humano("male", seed=2)
T = humano.targets(scale=1.85, width=0.92, arms=1.12, neck=1.15, pelvis_z=1.95, arm_drop=17.0)
H.fit(T, girth={"spine": (1.18, 1.75), "pelvis": (1.05, 1.2), "chest": (0.92, 0.95),
                "upper_arm_r": 0.72, "upper_arm_l": 0.72, "forearm_r": 0.75, "forearm_l": 0.75, "hand_r": 0.85, "hand_l": 0.85,
                "thigh_r": 0.72, "thigh_l": 0.72, "shin_r": 0.75, "shin_l": 0.75, "neck": 0.85}, names=NAMES)
H.skin_tint(shaved=0.0)
H.lips_slot()
H.eye_mats(iris_size=0.55)

# ------------------------------------------------------------------ pelo, barba larga y cejas
H.hair("pelo", "scalp", mat="pelo", offset=0.02, noise=0.016, smooth=1)
beard = {}
for rg in ("beard", "goatee", "mustache"):
    for k, v in H.region(rg).items():
        beard[k] = max(beard.get(k, 0.0), v)
H.hair("barba", beard, mat="pelo", offset=0.012, noise=0.008, extrude=(0.22, -0.25))
H.hair("cejas", "brows", mat="pelo", offset=0.008, noise=0.006)

# ------------------------------------------------------------------ ropa
camisa = {}
for rg in ("torso", "arms", "neck"):
    for k, v in H.region(rg).items():
        p = H.base_co[k]
        if p.z > 0.86 and not (abs(p.x) > 0.2 and p.z < 1.02) and p.z < 1.44:
            camisa[k] = max(camisa.get(k, 0.0), v)
H.piece("camisa", camisa, offset=0.012, mat="franela", thresh=0.3, smooth=2, noise=0.002, extrude=(0.07, 0.03), tatter=(0.06, 0.4))
for s, sg in (("r", 1), ("l", -1)):
    H.strap("arremangado_" + s, (sg * 0.24, 0, 1.03), (sg * 0.26, 0, 1.06), 0.06, region="arms", offset=0.022, mat="franela")
jeans = {}
for rg in ("legs", "torso"):
    for k, v in H.region(rg).items():
        p = H.base_co[k]
        if 0.12 < p.z < 0.98:
            jeans[k] = max(jeans.get(k, 0.0), v)
H.piece("jeans", jeans, offset=0.01, mat="mezclilla", thresh=0.3, smooth=1, tatter=None)
H.piece("dobladillo", H.band("legs", 0.1, 0.16), offset=0.016, mat="mezclilla", thresh=0.3, smooth=1, extrude=(0.03, 0.05), tatter=(0.04, 0.6))
H.plate("parche_rodilla", H.zone((0.11, 0.06, 0.47), 0.04, fn=lambda p: p.y > 0.02), offset=0.016, thick=0.004, mat="parche", trim=None, smooth=2)
H.piece("zapatos", "feet", offset=0.014, mat="cuero", thresh=0.2, smooth=2)
H.plate("cinturon", H.band("torso", 0.94, 0.98), offset=0.02, thick=0.008, mat="cuero", trim=None, smooth=2)

# ------------------------------------------------------------------ lentes redondos (uno estrellado) y lápices
for sg in (-1, 1):
    c = H.at((sg * 0.034, 0.145, 1.567))
    H.attach(cyl("lente_aro_%d" % sg, 0.03, 0.006, c, (90, 0, 0), bone="head", mat="marco", verts=24))
    H.attach(cyl("lente_%d" % sg, 0.026, 0.003, (c[0], c[1] + 0.002, c[2]), (90, 0, 0), bone="head", mat="vidrio", verts=24))
    t = H.at((sg * 0.075, 0.08, 1.57))
    H.attach(box("patilla_%d" % sg, (0.006, 0.12, 0.006), t, bone="head", mat="marco", bevel=0.001))
b = H.at((0, 0.15, 1.57))
H.attach(box("puente", (0.02, 0.006, 0.006), b, bone="head", mat="marco", bevel=0.001))
for k in range(3):
    p = H.at((-0.1 + k * 0.012, 0.11, 1.3))
    H.attach(cyl("lapiz_%d" % k, 0.007, 0.13, p, (k * 6 - 6, 0, 0), bone="chest", mat="lapiz", verts=6))

bk.finish("bibliofilo", tex_size=4096, bake=True, out_dir=OUT)
if PREVIEW:
    bk.set_pose({})
    bk.render_preview(os.path.join(OUT, "preview_bibliofilo.png"), (2.2, 6.0, 2.4), (0, 0, 1.8), size=(800, 1100))
    bk.render_preview(os.path.join(OUT, "preview_bibliofilo_cara.png"), (0.5, 1.4, 3.3), (0, 0.08, 3.15), size=(800, 800))
bk.export(os.path.join(OUT, "bibliofilo.glb"), actions=False)
print("LISTO", OUT)
