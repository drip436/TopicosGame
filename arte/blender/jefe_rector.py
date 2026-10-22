"""Jefe final: "El Rector Eterno" (boss_final/boss_rector.gd).

Hombre real de 2 m (malla base humana de Blender, ver humano.py): calvo, barba de candado
canosa, cejas pobladas, piel con sombra de barba. Dos modelos con el mismo esqueleto:
  rector.glb            fase 1: toga académica negra larga y gastada (dobladillo roto,
                        polvo), ribetes dorados y estola roja con insignia, capucha caída.
  rector_sin_toga.glb   fase 2: se arranca la toga; debajo lleva una armadura negra al
                        estilo de Elden Ring con tecnología: peto acanalado y grabado,
                        hombreras de láminas, gola, brazales, guanteletes, quijotes,
                        rodilleras y grebas, todo con circuitos rojos que brillan.
La espada, la vaina, el revólver y su funda siguen siendo los del código. Materiales que
anima el código: "ojos" y "circuito".

Uso:  blender -b --python arte/blender/jefe_rector.py -- <carpeta_salida> [preview] [toga|sin_toga]
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
ONLY = [a for a in argv[1:] if a != "preview"]
os.makedirs(OUT, exist_ok=True)

MATS = {
    "piel": dict(skin=True, base=(0.38, 0.25, 0.19), veins=0.15, vein_col=(0.22, 0.1, 0.12), blotch=0.45, blotch_col=(0.3, 0.16, 0.12), rough=0.42, wet=0.12, dirt=0.1, scale=3.0, tint_attr="tinte"),
    "labios": dict(skin=True, base=(0.3, 0.12, 0.1), veins=0.0, blotch=0.3, blotch_col=(0.22, 0.07, 0.06), rough=0.3, wet=0.4, dirt=0.0, scale=4.0),
    "esclera": dict(base=(0.5, 0.46, 0.42), rough=0.15, rust=0.0, wear=0.0, dirt=0.0, scratches=False),
    "barba": dict(hair=True, base=(0.02, 0.016, 0.014), tip=(0.05, 0.04, 0.035), gray=0.15, rough=0.65),
    "toga": dict(base=(0.014, 0.014, 0.02), rough=0.85, rust=0.15, wear=0.75, dirt=1.2, bare=(0.09, 0.085, 0.08), scratches=False, soot=0.5, streaks=0.35),
    "oro": dict(base=(0.55, 0.38, 0.1), metal=1.0, rough=0.35, rust=0.4, wear=0.6, dirt=0.9, bare=(0.7, 0.55, 0.25), soot=0.4, engrave=0.6, engrave_scale=30.0),
    "estola": dict(base=(0.11, 0.01, 0.014), rough=0.8, rust=0.2, wear=0.7, dirt=1.0, bare=(0.22, 0.08, 0.08), scratches=False, soot=0.4, engrave=0.3, engrave_scale=20.0),
    "tela": dict(base=(0.025, 0.025, 0.03), rough=0.85, rust=0.15, wear=0.7, dirt=1.1, bare=(0.12, 0.12, 0.12), scratches=False, soot=0.5),
    "armadura": dict(base=(0.1, 0.1, 0.11), metal=0.9, rough=0.3, rust=0.5, wear=0.6, dirt=0.8, bare=(0.55, 0.55, 0.58), streaks=0.5, soot=0.5, engrave=0.9, engrave_scale=14.0),
    "armadura_lisa": dict(base=(0.1, 0.1, 0.11), metal=0.9, rough=0.32, rust=0.5, wear=0.6, dirt=0.8, bare=(0.55, 0.55, 0.58), streaks=0.5, soot=0.5),
    "cuero": dict(base=(0.06, 0.035, 0.02), rough=0.62, rust=0.0, wear=0.9, dirt=1.0, bare=(0.2, 0.13, 0.08), soot=0.3),
    "metal": dict(base=(0.42, 0.42, 0.44), metal=1.0, rough=0.35, rust=0.7, wear=0.5, dirt=0.7, bare=(0.75, 0.75, 0.77)),
    "ojos": {"emit": (1.0, 0.85, 0.6), "strength": 3.0},
    "circuito": {"emit": (1.0, 0.15, 0.08), "strength": 2.0},
}
NAMES = {"pelvis": "pelvis", "spine": "spine", "chest": "chest", "neck": "neck", "head": "head"}
for s in ("r", "l"):
    NAMES.update({"upper_arm_" + s: "sh_" + s, "forearm_" + s: "el_" + s, "hand_" + s: "wr_" + s,
                  "thigh_" + s: "hip_" + s, "shin_" + s: "kn_" + s, "foot_" + s: "an_" + s})


def build(robed):
    bk.reset(seed=505 if robed else 506)
    bk.define_materials(MATS)
    H = humano.Humano("male", seed=5)
    T = humano.targets(scale=1.18, width=1.08, pelvis_z=1.12)
    H.fit(T, girth={"chest": (1.08, 1.04), "upper_arm_r": 1.06, "upper_arm_l": 1.06}, names=NAMES)
    H.skin_tint(shaved=0.85, bald=0.7)
    H.lips_slot()
    H.eye_mats(iris_size=0.6)
    g, mu = H.region("goatee"), H.region("mustache")
    H.hair("candado", {k: max(g.get(k, 0), mu.get(k, 0)) for k in set(g) | set(mu)}, mat="barba", offset=0.0035, noise=0.002)
    H.hair("cejas", "brows", mat="barba", offset=0.0035, noise=0.0015)

    # Ropa de abajo: camisa y pantalón tácticos, botas altas
    ropa = {}
    for rg in ("torso", "arms", "legs", "neck"):
        for k, v in H.region(rg).items():
            p = H.base_co[k]
            if p.z > 0.2 and not (abs(p.x) > 0.2 and p.z < 0.87):
                ropa[k] = max(ropa.get(k, 0.0), v)
    H.piece("ropa", ropa, offset=0.006, mat="tela", thresh=0.3, smooth=1)
    H.piece("botas", H.band("legs", -0.1, 0.32), offset=0.012, mat="cuero", thresh=0.3, smooth=2)
    H.piece("botas_pie", "feet", offset=0.012, mat="cuero", thresh=0.3, smooth=2)
    H.plate("cinturon", H.band("torso", 0.93, 0.975), offset=0.022, thick=0.01, mat="cuero", trim=None, smooth=2)

    front = lambda p, n: p.y > -0.01
    back = lambda p, n: p.y <= 0.01
    if robed:
        # Toga larga: todo el torso y los brazos, con la falda hasta los tobillos
        toga = {}
        for rg in ("torso", "arms", "neck"):
            for k, v in H.region(rg).items():
                p = H.base_co[k]
                if p.z > 0.86 and not (abs(p.x) > 0.2 and p.z < 0.98):
                    toga[k] = max(toga.get(k, 0.0), v)
        H.piece("toga", toga, offset=0.035, mat="toga", thresh=0.3, smooth=3, noise=0.004, extrude=(0.82, 0.32), tatter=(0.3, 0.18))
        # Ribetes dorados y estola roja que bajan por el frente
        for sg in (-1, 1):
            H.strap("ribete_%d" % sg, (sg * 0.075, 0.1, 1.44), (sg * 0.06, 0.1, 0.86), 0.022, region="torso", offset=0.042, mat="oro", fn=front)
            H.strap("estola_%d" % sg, (sg * 0.11, 0.1, 1.44), (sg * 0.1, 0.1, 0.9), 0.04, region="torso", offset=0.045, mat="estola", fn=front)
        # Mangas acampanadas con puño dorado
        for s, sg in (("r", 1), ("l", -1)):
            w = T["wrist_" + s]
            cyl("manga_" + s, 0.13, 0.3, (w.x, w.y, w.z + 0.17), bone="el_" + s, mat="toga", verts=24, r2=0.075)
            cyl("puno_oro_" + s, 0.135, 0.035, (w.x, w.y, w.z + 0.03), bone="el_" + s, mat="oro", verts=24, r2=0.13)
        # Capucha caída en la espalda e insignia en la estola
        H.attach(bk.blob("capucha", 0.16, (0, -0.17, T["neck"].z - 0.06), (1.3, 0.7, 0.75), bone="chest", mat="toga", lumps=0.12))
        H.attach(cyl("insignia", 0.04, 0.012, (-0.11, 0.17, 1.62), (90, 0, 0), bone="chest", mat="oro", verts=18))
    else:
        # Armadura negra grabada con circuitos rojos
        peto = H.band("torso", 1.0, 1.42)
        H.plate("peto", peto, offset=0.03, thick=0.012, mat="armadura", trim="metal", trim_r=0.005, glow="circuito", fn=front, flutes=(9.0, 0.004, 0), smooth=4)
        H.plate("espaldar", peto, offset=0.028, thick=0.01, mat="armadura", trim="metal", trim_r=0.005, glow="circuito", fn=back, smooth=4)
        H.lames("gola", H.band("neck", 1.36, 1.46), 1.36, 1.46, 2, offset=0.024, step=0.007, thick=0.007, mat="armadura_lisa", trim="metal", trim_r=0.004, smooth=3)
        H.lames("escarcela", H.band("torso", 0.84, 1.0), 0.84, 1.0, 2, offset=0.035, step=0.009, thick=0.008, mat="armadura", trim="metal", trim_r=0.004, glow="circuito", smooth=3)
        for s, sg in (("r", 1), ("l", -1)):
            sh = H.zone((sg * 0.19, 0.0, 1.38), 0.15, fn=lambda p: p.z > 1.22)
            H.lames("hombrera_" + s, sh, 1.22, 1.5, 3, rigid="upper_arm_" + s, offset=0.04, step=0.012, thick=0.01, mat="armadura", trim="metal", trim_r=0.005, glow="circuito", smooth=4)
            arms = {k: v for k, v in H.region("arms").items() if H.base_co[k].x * sg > 0}
            H.lames("brazal_" + s, H.band(arms, 0.88, 1.04), 0.88, 1.04, 3, offset=0.016, step=0.004, thick=0.007, mat="armadura", trim="metal", trim_r=0.0035, glow="circuito", smooth=3)
            hands = {k: v for k, v in H.region("hands").items() if H.base_co[k].x * sg > 0}
            H.plate("guantelete_" + s, hands, offset=0.01, thick=0.005, mat="armadura_lisa", trim=None, smooth=2)
            legs = {k: v for k, v in H.region("legs").items() if H.base_co[k].x * sg > 0}
            H.plate("quijote_" + s, H.band(legs, 0.56, 0.82), offset=0.02, thick=0.008, mat="armadura", trim="metal", trim_r=0.004, fn=lambda p, n: p.y > -0.02, smooth=3, glow="circuito")
            H.plate("rodillera_" + s, H.zone((sg * 0.11, 0.07, 0.47), 0.07, fn=lambda p: p.y > -0.02), offset=0.03, thick=0.01, mat="armadura", trim="metal", trim_r=0.004, smooth=3)
            H.plate("greba_" + s, H.band(legs, 0.14, 0.43), offset=0.03, thick=0.008, mat="armadura", trim="metal", trim_r=0.004, glow="circuito", fn=lambda p, n: p.y > -0.03, smooth=3)
        # Bolsas y hebilla en el cinturón
        cin = T["pelvis"].z - 0.0
        for k, x in enumerate((-0.16, -0.08, 0.08)):
            H.attach(bk.blob("bolsa_%d" % k, 0.04, (x, 0.16 - abs(x) * 0.4, cin - 0.04), (1.0, 0.6, 1.1), bone="pelvis", mat="cuero", lumps=0.05))
        H.attach(box("hebilla", (0.08, 0.025, 0.06), (0, 0.17, cin), bone="pelvis", mat="metal", bevel=0.006))

    name = "rector" if robed else "rector_sin_toga"
    bk.finish(name, tex_size=4096, bake=True, out_dir=OUT)
    if PREVIEW:
        bk.set_pose({})
        bk.render_preview(os.path.join(OUT, "preview_%s.png" % name), (1.5, 3.6, 1.6), (0, 0, 1.15), size=(800, 1100))
        bk.render_preview(os.path.join(OUT, "preview_%s_cara.png" % name), (0.25, 0.8, 2.05), (0, 0.04, 1.97), size=(800, 800))
    bk.export(os.path.join(OUT, name + ".glb"), actions=False)


for nm, robed in (("toga", True), ("sin_toga", False)):
    if not ONLY or nm in ONLY:
        build(robed)
print("LISTO", OUT)
