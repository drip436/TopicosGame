"""Tercer jefe: "ADA-7, la Administradora del Núcleo" (boss_computo/boss_admin.gd).

Mujer de 4 m hecha con la malla base femenina de Blender (ver humano.py). La mitad
derecha conserva su piel y un traje sastre oscuro rasgado y quemado, con la credencial
"ADMIN"; la mitad izquierda está cubierta por placas de cromo grabadas con líneas de datos
cian, al estilo de Elden Ring con tecnología: media máscara con visor, hombrera de
láminas, brazal y guantelete, y la pierna robótica (su punto débil) con costuras naranjas
que brillan más cuanto más se daña. Lleva el núcleo encendido en el pecho y un rack de
servidores abollado a la espalda. Los cables, espadas y armas compiladas son del código.

Materiales que anima el código: "ojos" (visor), "nucleo" y "debil".

Uso:  blender -b --python arte/blender/jefe_ada.py -- <carpeta_salida> [preview]
"""
import sys
import os
import math

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
import humano
from bk import box, cyl, sphere, label, vents

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/jefes")
PREVIEW = "preview" in argv
os.makedirs(OUT, exist_ok=True)

bk.reset(seed=303)
bk.define_materials({
    "piel": dict(skin=True, base=(0.42, 0.3, 0.25), veins=0.1, vein_col=(0.3, 0.18, 0.2), blotch=0.3, blotch_col=(0.32, 0.2, 0.17), rough=0.42, wet=0.1, dirt=0.1, scale=3.0, tint_attr="tinte"),
    "labios": dict(skin=True, base=(0.3, 0.12, 0.12), veins=0.0, blotch=0.3, blotch_col=(0.22, 0.07, 0.07), rough=0.3, wet=0.4, dirt=0.0, scale=4.0),
    "esclera": dict(base=(0.5, 0.46, 0.42), rough=0.15, rust=0.0, wear=0.0, dirt=0.0, scratches=False),
    "iris": dict(base=(0.08, 0.05, 0.03), rough=0.1, rust=0.0, wear=0.0, dirt=0.0, scratches=False),
    "pelo": dict(hair=True, base=(0.012, 0.01, 0.014), tip=(0.04, 0.035, 0.045), rough=0.45),
    "traje": dict(base=(0.022, 0.022, 0.028), rough=0.8, rust=0.15, wear=0.75, dirt=1.0, bare=(0.12, 0.12, 0.13), scratches=False, soot=0.8, streaks=0.3),
    "blusa": dict(base=(0.38, 0.38, 0.36), rough=0.9, rust=0.3, wear=0.4, dirt=1.1, bare=(0.2, 0.19, 0.17), scratches=False, soot=0.5, streaks=0.5),
    "cromo": dict(base=(0.62, 0.64, 0.68), metal=1.0, rough=0.2, rust=0.45, wear=0.3, dirt=0.6, bare=(0.85, 0.86, 0.9), streaks=0.5, soot=0.4, engrave=0.75, engrave_scale=12.0),
    "cromo_liso": dict(base=(0.62, 0.64, 0.68), metal=1.0, rough=0.22, rust=0.45, wear=0.3, dirt=0.6, bare=(0.85, 0.86, 0.9), streaks=0.5, soot=0.4),
    "metal_oscuro": dict(base=(0.05, 0.05, 0.06), metal=0.75, rough=0.45, rust=0.8, wear=0.7, dirt=0.7, bare=(0.4, 0.4, 0.42)),
    "metal": dict(base=(0.4, 0.4, 0.42), metal=1.0, rough=0.4, rust=0.9, wear=0.5, dirt=0.6, bare=(0.75, 0.75, 0.77)),
    "rack": dict(base=(0.06, 0.065, 0.075), metal=0.6, rough=0.5, rust=1.1, wear=0.8, dirt=0.9, bare=(0.4, 0.4, 0.42), streaks=0.8, soot=0.6),
    "cuero": dict(base=(0.02, 0.018, 0.02), rough=0.5, rust=0.0, wear=0.8, dirt=0.8, bare=(0.15, 0.13, 0.12)),
    "credencial": dict(base=(0.6, 0.6, 0.58), rough=0.4, rust=0.0, wear=0.4, dirt=0.8, bare=(0.3, 0.3, 0.3), scratches=False),
    "ojos": {"emit": (0.35, 0.85, 1.0), "strength": 6.0},
    "nucleo": {"emit": (0.3, 0.85, 1.0), "strength": 4.0},
    "debil": {"emit": (1.0, 0.45, 0.1), "strength": 3.0},
    "linea": {"emit": (0.3, 0.85, 1.0), "strength": 2.0},
    "led_v": {"emit": (0.3, 1.0, 0.4), "strength": 5.0},
    "led_r": {"emit": (1.0, 0.25, 0.2), "strength": 5.0},
})
NAMES = {"pelvis": "pelvis", "spine": "spine", "chest": "chest", "neck": "neck", "head": "head"}
for s in ("r", "l"):
    NAMES.update({"upper_arm_" + s: "sh_" + s, "forearm_" + s: "el_" + s, "hand_" + s: "wr_" + s,
                  "thigh_" + s: "hip_" + s, "shin_" + s: "kn_" + s, "foot_" + s: "an_" + s})

H = humano.Humano("female", seed=3)
T = humano.targets(scale=2.37, width=1.18, pelvis_z=2.25)
H.fit(T, girth={"chest": (1.25, 1.15), "spine": (1.18, 1.1), "pelvis": (1.12, 1.1), "neck": 1.1,
                "upper_arm_r": 1.25, "upper_arm_l": 1.35, "forearm_r": 1.22, "forearm_l": 1.3,
                "thigh_r": 1.22, "thigh_l": 1.3, "shin_r": 1.18, "shin_l": 1.28}, names=NAMES)
H.skin_tint(shaved=0.0)
H.lips_slot()
H.eye_mats(iris_size=0.55)
H.eyes[0]["slots"] = ["esclera", "iris"]           # ojo humano (derecho); el izquierdo es el visor

left = lambda p, n: p.x < -0.004
right = lambda p, n: p.x >= -0.004

# ------------------------------------------------------------------ cabeza: media máscara y melena
H.plate("mascara", H.zone((0, 0.02, 1.565), 0.15, fn=lambda p: p.z > 1.43 and p.x < -0.004), offset=0.006, thick=0.006, mat="cromo_liso", trim="metal_oscuro", trim_r=0.003, glow="linea", glow_r=0.0018, smooth=2)
v = H.at((-0.034, 0.15, 1.572))
H.attach(box("visor_marco", (0.05, 0.02, 0.02), v, bone="head", mat="metal_oscuro", bevel=0.004))
H.attach(box("visor", (0.042, 0.022, 0.011), (v[0], v[1] + 0.004, v[2]), bone="head", mat="ojos", bevel=0.003))
pelo = {k: w for k, w in H.region("scalp").items() if H.base_co[k].x > -0.04}
H.hair("pelo", pelo, mat="pelo", offset=0.014, noise=0.004, smooth=2, extrude=(0.09, 0.05))

# ------------------------------------------------------------------ traje sastre (mitad humana y torso)
traje = {}
for rg in ("torso", "arms", "legs", "neck"):
    for k, w in H.region(rg).items():
        p = H.base_co[k]
        if p.z < 0.2 or (abs(p.x) > 0.2 and p.z < 0.98):
            continue
        if p.x < -0.004 and (rg in ("arms", "legs") or p.z < 0.98):
            continue                      # el brazo y la pierna izquierdos son de cromo
        traje[k] = max(traje.get(k, 0.0), w)
H.piece("traje", traje, offset=0.01, mat="traje", thresh=0.3, smooth=2, tatter=None)
saco = {k: w for k, w in H.region("torso").items() if H.base_co[k].z > 0.95 and H.base_co[k].x > -0.004}
H.piece("saco", saco, offset=0.022, mat="traje", thresh=0.3, smooth=3, extrude=(0.16, 0.06), tatter=(0.14, 0.45))
H.strap("blusa", (0.03, 0.12, 1.42), (0.03, 0.12, 1.25), 0.07, region="torso", offset=0.026, mat="blusa", fn=lambda p, n: p.y > 0.03)
H.piece("bota_r", {k: w for k, w in H.band("legs", -0.1, 0.32).items() if H.base_co[k].x > 0}, offset=0.012, mat="cuero", thresh=0.2, smooth=2)
H.piece("bota_r_pie", {k: w for k, w in H.region("feet").items() if H.base_co[k].x > 0}, offset=0.012, mat="cuero", thresh=0.2, smooth=2)

# ------------------------------------------------------------------ placas de cromo (mitad izquierda)
H.plate("pecho_cromo", H.band("torso", 0.98, 1.42), offset=0.03, thick=0.008, mat="cromo", trim="metal_oscuro", trim_r=0.004, glow="linea", fn=lambda p, n: p.x < -0.01, smooth=3)
sh = H.zone((-0.19, 0.0, 1.38), 0.15, fn=lambda p: p.z > 1.22)
H.lames("hombrera_l", sh, 1.22, 1.5, 3, rigid="upper_arm_l", offset=0.03, step=0.01, thick=0.008, mat="cromo", trim="metal_oscuro", trim_r=0.004, glow="linea", smooth=3)
arm_l = {k: w for k, w in H.region("arms").items() if H.base_co[k].x < 0}
H.piece("brazo_cromo", arm_l, offset=0.004, mat="cromo_liso", thresh=0.3, smooth=1)
H.lames("brazal_l", H.band(arm_l, 0.86, 1.06), 0.86, 1.06, 3, offset=0.016, step=0.004, thick=0.006, mat="cromo", trim="metal_oscuro", trim_r=0.003, glow="linea", smooth=3)
H.plate("codal_l", H.zone((-0.28, -0.01, 1.08), 0.06), offset=0.02, thick=0.008, mat="metal_oscuro", trim="cromo_liso", trim_r=0.003, smooth=2)
leg_l = {k: w for k, w in H.region("legs").items() if H.base_co[k].x < 0}
H.piece("pierna_cromo", leg_l, offset=0.004, mat="cromo_liso", thresh=0.3, smooth=1)
H.piece("pie_cromo", {k: w for k, w in H.region("feet").items() if H.base_co[k].x < 0}, offset=0.008, mat="cromo_liso", thresh=0.2, smooth=2)
# Pierna débil: placas con costuras naranjas
H.plate("quijote_l", H.band(leg_l, 0.55, 0.85), offset=0.018, thick=0.008, mat="cromo", trim="metal_oscuro", trim_r=0.004, glow="debil", glow_r=0.003, smooth=3)
H.plate("rodillera_l", H.zone((-0.11, 0.07, 0.47), 0.07, fn=lambda p: p.y > -0.02), offset=0.024, thick=0.01, mat="metal_oscuro", trim="cromo_liso", trim_r=0.003, glow="debil", smooth=2)
H.plate("greba_l", H.band(leg_l, 0.12, 0.43), offset=0.016, thick=0.008, mat="cromo", trim="metal_oscuro", trim_r=0.004, glow="debil", glow_r=0.003, fn=lambda p, n: p.y > -0.03, smooth=3)

# ------------------------------------------------------------------ núcleo, credencial y rack de servidores
c = H.at((0.0, 0.12, 1.3))
H.attach(cyl("nucleo_aro", 0.035, 0.03, c, (90, 0, 0), bone="chest", mat="metal_oscuro", verts=28))
H.attach(cyl("nucleo", 0.026, 0.034, (c[0], c[1] + 0.006, c[2]), (90, 0, 0), bone="chest", mat="nucleo", verts=28))
b = H.at((0.09, 0.115, 1.2))
H.attach(box("credencial", (0.035, 0.006, 0.05), b, bone="chest", mat="credencial", bevel=0.003))
H.attach(label("credencial_txt", "ADMIN", (b[0], b[1] + 0.004, b[2] - 0.008), (90, 0, 0), size=0.011, bone="chest", mat="metal_oscuro"))
r = H.at((0.0, -0.16, 1.25))
sc = 2.37
H.attach(box("rack", (0.36 * sc / 2, 0.21 * sc / 2, 0.42 * sc / 2), r, bone="chest", mat="rack", bevel=0.03))
for k in range(6):
    z = r[2] - 0.19 + k * 0.075
    H.attach(box("bahia_%d" % k, (0.36, 0.012, 0.05), (r[0], r[1] - 0.13, z), bone="chest", mat="metal_oscuro", bevel=0.006))
    H.attach(box("led_%d" % k, (0.02, 0.01, 0.02), (r[0] - 0.13 + (k % 3) * 0.04, r[1] - 0.138, z), bone="chest", mat="led_v" if k % 2 == 0 else "led_r", bevel=0.003))
for k in range(5):
    H.attach(cyl("puerto_%d" % k, 0.022, 0.03, (r[0] - 0.14 + k * 0.07, r[1] - 0.135, r[2] - 0.24), (90, 0, 0), bone="chest", mat="metal", verts=10))

bk.finish("ada7", tex_size=4096, bake=True, out_dir=OUT)
if PREVIEW:
    bk.set_pose({})
    bk.render_preview(os.path.join(OUT, "preview_ada7.png"), (2.8, 7.4, 3.0), (0, 0, 2.1), size=(800, 1100))
    bk.render_preview(os.path.join(OUT, "preview_ada7_atras.png"), (-3.0, -6.8, 3.4), (0, 0, 2.2), size=(800, 1100))
    bk.render_preview(os.path.join(OUT, "preview_ada7_cara.png"), (0.6, 1.8, 3.95), (0, 0.1, 3.75), size=(800, 800))
bk.export(os.path.join(OUT, "ada7.glb"), actions=False)
print("LISTO", OUT)
