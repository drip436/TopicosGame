"""Cuarto jefe: "Dr. Viktor Kessler, el Paciente Cero" (boss_laboratorio/boss_doctor.gd).

Viejo enorme y musculoso (estilo Conquest) hecho con la malla base humana de Blender
(ver humano.py): pelo blanco peinado hacia atrás, barba corta canosa, cara con cicatrices
y un ojo muerto que brilla. Lleva traje negro gastado, camisa y corbata floja, una bata de
laboratorio abierta, rota y manchada de químicos, botas y cinturón con frascos de suero;
en las manos el tubo radiactivo y la pistola láser.

Dos modelos con el mismo esqueleto:
  kessler.glb           el científico (fase 1)
  kessler_mutante.glb   tras inyectarse (fase 2, el código lo escala ×2): piel verde enferma,
                        carne que revienta el traje, espinas de hueso en hombros y espalda,
                        pústulas, garras, tumor en la cabeza y la bata hecha jirones.
Materiales que anima el código: "ojos" (ojo muerto) y "tubo" (brillo del tubo).

Uso:  blender -b --python arte/blender/jefe_kessler.py -- <carpeta_salida> [preview] [humano|mutante]
"""
import sys
import os
import math
import random

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
import humano
from bk import box, cyl, sphere
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/jefes")
PREVIEW = "preview" in argv
ONLY = [a for a in argv[1:] if a != "preview"]
os.makedirs(OUT, exist_ok=True)

MATS = {
    "piel": dict(skin=True, base=(0.37, 0.25, 0.2), veins=0.3, vein_col=(0.2, 0.08, 0.1), blotch=0.6, blotch_col=(0.28, 0.13, 0.1), rough=0.48, wet=0.12, dirt=0.15, scale=3.0, tint_attr="tinte"),
    "piel_mut": dict(skin=True, base=(0.13, 0.16, 0.085), veins=0.9, vein_col=(0.03, 0.06, 0.015), blotch=0.9, blotch_col=(0.14, 0.04, 0.05), rough=0.42, wet=0.5, dirt=0.4, scale=2.0, tint_attr="tinte"),
    "labios": dict(skin=True, base=(0.28, 0.11, 0.1), veins=0.0, blotch=0.3, blotch_col=(0.2, 0.07, 0.06), rough=0.3, wet=0.4, dirt=0.0, scale=4.0),
    "carne": dict(skin=True, base=(0.12, 0.02, 0.018), veins=0.6, vein_col=(0.04, 0.005, 0.01), blotch=0.7, blotch_col=(0.18, 0.08, 0.03), rough=0.3, wet=0.9, dirt=0.4, scale=3.0),
    "esclera": dict(base=(0.5, 0.46, 0.42), rough=0.15, rust=0.0, wear=0.0, dirt=0.0, scratches=False),
    "iris": dict(base=(0.05, 0.08, 0.12), rough=0.1, rust=0.0, wear=0.0, dirt=0.0, scratches=False),
    "pelo": dict(hair=True, base=(0.2, 0.2, 0.19), tip=(0.42, 0.42, 0.4), rough=0.5, gray=0.2),
    "traje": dict(base=(0.018, 0.018, 0.02), rough=0.75, rust=0.2, wear=0.8, dirt=1.1, bare=(0.1, 0.1, 0.1), scratches=False, soot=0.6, streaks=0.4),
    "bata": dict(base=(0.36, 0.36, 0.32), rough=0.9, rust=0.75, wear=0.5, dirt=1.6, bare=(0.22, 0.2, 0.15), scratches=False, soot=0.75, streaks=1.0),
    "camisa": dict(base=(0.3, 0.31, 0.28), rough=0.9, rust=0.4, wear=0.4, dirt=1.1, bare=(0.2, 0.19, 0.16), scratches=False, soot=0.4),
    "corbata": dict(base=(0.1, 0.01, 0.014), rough=0.7, rust=0.1, wear=0.6, dirt=0.8, bare=(0.2, 0.08, 0.08), scratches=False),
    "cuero": dict(base=(0.03, 0.022, 0.016), rough=0.55, rust=0.0, wear=0.9, dirt=1.1, bare=(0.15, 0.11, 0.08), soot=0.3),
    "metal": dict(base=(0.42, 0.43, 0.45), metal=1.0, rough=0.35, rust=0.9, wear=0.5, dirt=0.7, bare=(0.75, 0.75, 0.77), streaks=0.6),
    "metal_oscuro": dict(base=(0.05, 0.05, 0.055), metal=0.8, rough=0.45, rust=0.8, wear=0.7, dirt=0.7, bare=(0.4, 0.4, 0.42), streaks=0.4),
    "peligro": dict(base=(0.75, 0.6, 0.05), rough=0.55, rust=0.35, wear=0.9, dirt=0.6, bare=(0.18, 0.18, 0.18)),
    "hueso": dict(base=(0.45, 0.42, 0.32), rough=0.6, rust=0.15, wear=0.3, dirt=1.0, bare=(0.62, 0.6, 0.5), scratches=False, soot=0.4, streaks=0.5),
    "pus": {"emit": (0.5, 1.0, 0.18), "strength": 1.4},
    "suero": {"emit": (0.4, 1.0, 0.2), "strength": 3.0},
    "tubo": {"emit": (0.4, 1.0, 0.2), "strength": 3.0},
    "ojos": {"emit": (0.85, 0.95, 0.85), "strength": 4.0},
}
NAMES = {"pelvis": "pelvis", "spine": "spine", "chest": "chest", "neck": "neck", "head": "head"}
for s in ("r", "l"):
    NAMES.update({"upper_arm_" + s: "sh_" + s, "forearm_" + s: "el_" + s, "hand_" + s: "wr_" + s,
                  "thigh_" + s: "hip_" + s, "shin_" + s: "kn_" + s, "foot_" + s: "an_" + s})

# Cicatrices de la cara (segmentos en coordenadas de la malla base, cara hacia +Y)
SCARS = [((0.05, 0.11, 1.61), (0.02, 0.12, 1.5)), ((-0.05, 0.11, 1.52), (-0.015, 0.13, 1.5)), ((0.06, 0.1, 1.48), (0.02, 0.12, 1.45))]


def scar_region(H, width=0.0035):
    out = {}
    for i, p in enumerate(H.base_co):
        if p.z < 1.42 or p.y < 0.04:
            continue
        for a, b in SCARS:
            a, b = Vector(a), Vector(b)
            ab = b - a
            t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
            d = math.hypot(*(a + ab * t - p).xz)
            if d < width:
                out[i] = max(out.get(i, 0.0), 1.0 - d / width)
    return out


def build(mutant):
    bk.reset(seed=404 if not mutant else 405)
    bk.define_materials(MATS)
    rng = random.Random(4)
    H = humano.Humano("male", seed=4)
    T = humano.targets(scale=1.35, width=1.22, pelvis_z=1.28)
    g = 1.15 if mutant else 1.0
    H.fit(T, girth={"chest": (1.3 * g, 1.2 * g), "spine": (1.22 * g, 1.18 * g), "pelvis": (1.12, 1.1), "neck": 1.35, "head": 1.04,
                    "upper_arm_r": 1.45 * g, "upper_arm_l": 1.5 * g, "forearm_r": 1.38 * g, "forearm_l": 1.5 * g,
                    "thigh_r": 1.22, "thigh_l": 1.22, "shin_r": 1.15, "shin_l": 1.15}, names=NAMES)
    skin = "piel_mut" if mutant else "piel"
    H.skin_tint(shaved=0.4, extra=[(scar_region(H), (0.7, 0.45, 0.45))])
    H.lips_slot(skin=skin)
    H.body["mat"] = skin
    H.eye_mats(iris_size=0.55)
    H.eyes[0]["slots"] = ["esclera", "iris"]          # ojo derecho normal; el izquierdo, muerto y brillante
    # Pelo blanco peinado hacia atrás, barba corta y cejas pobladas
    H.hair("pelo", "scalp", mat="pelo", offset=0.01, noise=0.006, smooth=1)
    beard = {}
    for rg in ("beard", "goatee", "mustache"):
        for k, v in H.region(rg).items():
            beard[k] = max(beard.get(k, 0.0), v)
    H.hair("barba", beard, mat="pelo", offset=0.006, noise=0.003)
    H.hair("cejas", "brows", mat="pelo", offset=0.005, noise=0.003)

    # -------------------------------------------------------------- ropa
    hole = (lambda p, n: not (abs(p.x) < 0.11 and p.y > 0.0 and 1.12 < p.z < 1.38)) if mutant else None
    traje = {}
    for rg in ("torso", "arms", "legs", "neck"):
        for k, v in H.region(rg).items():
            p = H.base_co[k]
            if p.z > 0.25 and not (abs(p.x) > 0.2 and p.z < 0.9):
                traje[k] = max(traje.get(k, 0.0), v)
    H.piece("traje", traje, offset=0.008, mat="traje", thresh=0.3, smooth=1, fn=hole, tatter=None)
    if not mutant:
        H.strap("camisa", (0, 0.12, 1.42), (0, 0.12, 1.0), 0.09, region="torso", offset=0.014, mat="camisa", fn=lambda p, n: p.y > 0.03)
        H.strap("corbata", (0.005, 0.12, 1.4), (0.02, 0.12, 1.08), 0.035, region="torso", offset=0.022, mat="corbata", fn=lambda p, n: p.y > 0.03)
    H.piece("botas", H.band("legs", -0.1, 0.3), offset=0.014, mat="cuero", thresh=0.3, smooth=2)
    H.piece("botas_pie", "feet", offset=0.014, mat="cuero", thresh=0.3, smooth=2)
    H.plate("cinturon", H.band("torso", 0.93, 0.975), offset=0.024, thick=0.01, mat="cuero", trim=None, smooth=2)
    # Bata abierta por delante, hasta las rodillas, rota y manchada
    bata = {}
    for rg in ("torso", "arms"):
        for k, v in H.region(rg).items():
            p = H.base_co[k]
            if p.z > 0.86 and not (abs(p.x) > 0.2 and p.z < 0.93) and not (abs(p.x) < 0.07 and p.y > 0.0):
                bata[k] = max(bata.get(k, 0.0), v)
    H.piece("bata", bata, offset=0.03, mat="bata", thresh=0.3, smooth=3, noise=0.004, extrude=(0.42 if not mutant else 0.3, 0.12),
            tatter=(0.25, 0.25) if not mutant else (0.5, 0.6))
    # Frascos de suero en el cinturón
    for k in range(4):
        a = -0.9 + k * 0.6
        x, y, z = H.at((math.sin(a) * 0.16, math.cos(a) * 0.13, 0.94))
        H.attach(cyl("porta_%d" % k, 0.03, 0.1, (x, y, z - 0.03), bone="pelvis", mat="cuero", verts=12))
        if not (mutant and k % 2):
            H.attach(cyl("frasco_%d" % k, 0.024, 0.13, (x, y, z + 0.04), bone="pelvis", mat="suero", verts=12))
    # Tubo radiactivo (derecha) y pistola láser (izquierda)
    wr, wl = T["wrist_r"], T["wrist_l"]
    cyl("tubo", 0.07, 1.3, (wr.x, wr.y + 0.03, wr.z - 0.71), bone="wr_r", mat="tubo", verts=18)
    for (dz, h) in ((-0.06, 0.16), (-1.34, 0.16)):
        cyl("tubo_tapa_%d" % int(-dz * 10), 0.1, h, (wr.x, wr.y + 0.03, wr.z + dz), bone="wr_r", mat="metal", verts=18)
    for k in range(3):
        cyl("tubo_anillo_%d" % k, 0.085, 0.04, (wr.x, wr.y + 0.03, wr.z - 0.35 - k * 0.3), bone="wr_r", mat="metal_oscuro", verts=18)
    box("tubo_aviso", (0.03, 0.08, 0.2), (wr.x, wr.y + 0.13, wr.z - 0.06), bone="wr_r", mat="peligro", bevel=0.004)
    box("pistola", (0.12, 0.17, 0.36), (wl.x, wl.y + 0.03, wl.z - 0.27), bone="wr_l", mat="metal_oscuro", bevel=0.03)
    box("pistola_mango", (0.08, 0.2, 0.14), (wl.x, wl.y - 0.09, wl.z - 0.15), (20, 0, 0), bone="wr_l", mat="cuero", bevel=0.02)
    cyl("pistola_canon", 0.04, 0.26, (wl.x, wl.y + 0.03, wl.z - 0.55), bone="wr_l", mat="metal", verts=16)
    for k in range(3):
        cyl("pistola_bobina_%d" % k, 0.055, 0.02, (wl.x, wl.y + 0.03, wl.z - 0.44 - k * 0.05), bone="wr_l", mat="metal_oscuro", verts=16)
    cyl("pistola_boca", 0.03, 0.03, (wl.x, wl.y + 0.03, wl.z - 0.69), bone="wr_l", mat="suero", verts=14)

    if mutant:
        # Carne que revienta el traje, joroba, espinas, pústulas, tumor y garras
        for k in range(7):
            p = H.at((rng.uniform(-0.1, 0.1), 0.13, rng.uniform(1.15, 1.36)))
            H.attach(bk.blob("carne_%d" % k, rng.uniform(0.05, 0.08), p, (1.0, 0.7, 1.0), bone="chest", mat="piel_mut", lumps=0.35))
        for k in range(10):
            p = H.at((rng.uniform(-0.13, 0.13), 0.15, rng.uniform(1.1, 1.38)))
            H.attach(sphere("pus_pecho_%d" % k, rng.uniform(0.012, 0.022), p, bone="chest", mat="pus", segs=10))
        H.attach(bk.blob("joroba", 0.18, H.at((0, -0.12, 1.28)), (1.3, 0.8, 1.0), bone="chest", mat="piel_mut", lumps=0.35))
        for k in range(7):
            p = Vector(H.at((rng.uniform(-0.12, 0.12), -0.2, 1.2 + k * 0.035)))
            d = Vector((rng.uniform(-0.3, 0.3), -1.0, 0.35)).normalized()
            rot = [math.degrees(a) for a in d.to_track_quat("Z", "Y").to_euler()]
            H.attach(cyl("espina_%d" % k, 0.022, 0.16 - k * 0.008, tuple(p + d * 0.06), rot, bone="chest", mat="hueso", verts=7, r2=0.0, bevel=0))
        for s, sg in (("r", 1), ("l", -1)):
            for k in range(3):
                p = Vector(H.at((sg * (0.2 + k * 0.03), -0.02 + k * 0.03, 1.42)))
                d = Vector((sg * (0.4 + k * 0.2), 0.1 * k, 1.0)).normalized()
                rot = [math.degrees(a) for a in d.to_track_quat("Z", "Y").to_euler()]
                H.attach(cyl("espina_hombro_%s_%d" % (s, k), 0.025, 0.17 - k * 0.03, tuple(p + d * 0.07), rot, bone="chest", mat="hueso", verts=7, r2=0.0, bevel=0))
        for k in range(12):
            p = H.at((rng.uniform(-0.15, 0.15), -0.17, rng.uniform(1.05, 1.4)))
            H.attach(sphere("pus_espalda_%d" % k, rng.uniform(0.015, 0.03), p, bone="chest", mat="pus", segs=10))
        H.attach(bk.blob("hombro_hinchado", 0.12, H.at((-0.22, 0.0, 1.38)), (1.0, 0.9, 0.9), bone="chest", mat="piel_mut", lumps=0.35))
        H.attach(bk.blob("tumor", 0.06, H.at((0.05, -0.02, 1.68)), (1.0, 0.9, 0.8), bone="head", mat="piel_mut", lumps=0.4))
        for k in range(3):
            H.attach(sphere("pus_cara_%d" % k, 0.008, H.at((rng.uniform(-0.05, 0.05), 0.125, rng.uniform(1.47, 1.6))), bone="head", mat="pus", segs=8))
        for k in range(3):
            p = H.at((-0.4 + k * 0.012, 0.05, 0.72))
            cyl("garra_%d" % k, 0.012, 0.12, p, (-150, 0, 0), bone="wr_l", mat="hueso", verts=6, r2=0.0, bevel=0)

    name = "kessler_mutante" if mutant else "kessler"
    bk.finish(name, tex_size=4096, bake=True, out_dir=OUT)
    if PREVIEW:
        bk.set_pose({})
        bk.render_preview(os.path.join(OUT, "preview_%s.png" % name), (1.7, 4.4, 1.9), (0, 0, 1.35), size=(800, 1100))
        bk.render_preview(os.path.join(OUT, "preview_%s_cara.png" % name), (0.3, 1.0, 2.45), (0, 0.05, 2.35), size=(800, 800))
    bk.export(os.path.join(OUT, name + ".glb"), actions=False)


for nm, mut in (("humano", False), ("mutante", True)):
    if not ONLY or nm in ONLY:
        build(mut)
print("LISTO", OUT)
