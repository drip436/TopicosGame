"""Jugador con la armadura de su clase (jugador/class_kit.gd + jugador/player_rig.gd).

Cuerpo humano realista (malla base de Blender, ver humano.py) parecido a la foto de
referencia del jugador: piel morena, pelo negro rizado y voluminoso, lentes redondos de
armazón metálico, cara redonda y complexión robusta, playera blanca, pantalón oscuro y botas,
en pose T y con las articulaciones exactamente donde las pone player_rig.gd (BONES), así
que el esqueleto y las animaciones del juego lo mueven tal cual. Encima va la armadura de
cada clase al estilo de Elden Ring con tecnología:

  cyber     Caballero (Ciberseguridad): armadura de placas acanalada con costuras cian,
            tabardo verde con candado, yelmo con visor encendido y capa corta.
  backend   Tanque (Backend): armadura pesadísima de acero oscuro, hombreras enormes,
            yelmo cerrado con rejilla, luces naranjas de servidor y módulo a la espalda.
  frontend  Mago (Frontend): túnica larga azul con runas de código, capucha, manto de
            láminas de cuero y brazales que brillan.
  ai        Invocador (AI Dev): bata blanca larga abierta, arnés con núcleo de IA en el
            pecho, visor holográfico y botas tecnológicas.
  data      Arquero (Data Scientist): brigantina de cuero con remaches, capucha y capa
            verdes, brazales, cinturón con bolsas y carcaj con flechas.

Salida: modelos/jugador/jugador_<clase>.glb (cuerpo + armadura, con pesos por hueso).

Uso:  blender -b --python arte/blender/jugador.py -- <carpeta_salida> [preview] [clase ...]
"""
import sys
import os
import math

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
import humano
from bk import box, cyl, sphere, label, cable
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/jugador")
PREVIEW = "preview" in argv
ONLY = [a for a in argv[1:] if a != "preview"]
os.makedirs(OUT, exist_ok=True)


def G(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


# Articulaciones de jugador/player_rig.gd (BONES), en el espacio del nodo Visual
RIG = {
    "pelvis": G(0, 0.92, 0), "spine": G(0, 1.04, 0), "chest": G(0, 1.2, 0), "neck": G(0, 1.39, 0), "head": G(0, 1.47, 0),
    "head_top": G(0, 1.69, 0),
}
for s, sg in (("r", 1), ("l", -1)):
    RIG.update({"shoulder_" + s: G(sg * 0.19, 1.3, 0), "elbow_" + s: G(sg * 0.47, 1.28, 0), "wrist_" + s: G(sg * 0.72, 1.27, 0),
                "hand_tip_" + s: G(sg * 0.86, 1.265, 0), "hip_" + s: G(sg * 0.1, 0.88, 0), "knee_" + s: G(sg * 0.1, 0.48, 0),
                "ankle_" + s: G(sg * 0.1, 0.08, 0), "toe_" + s: G(sg * 0.1, 0.0, -0.15)})
NAMES = {"pelvis": "hips", "spine": "spine", "chest": "chest", "neck": "neck", "head": "head"}
for s in ("r", "l"):
    NAMES.update({"upper_arm_" + s: "arm_" + s, "forearm_" + s: "fore_" + s, "hand_" + s: "hand_" + s,
                  "thigh_" + s: "thigh_" + s, "shin_" + s: "shin_" + s, "foot_" + s: "foot_" + s})

MATS = {
    # Cuerpo y ropa de la skin original
    # Piel morena cálida, pelo negro rizado y playera blanca (como la foto de referencia)
    "piel": dict(skin=True, base=(0.165, 0.085, 0.045), veins=0.06, vein_col=(0.16, 0.07, 0.06), blotch=0.25, blotch_col=(0.2, 0.1, 0.06), rough=0.42, wet=0.12, dirt=0.05, scale=3.0, tint_attr="tinte"),
    "labios": dict(skin=True, base=(0.13, 0.055, 0.04), veins=0.0, blotch=0.3, blotch_col=(0.22, 0.08, 0.07), rough=0.3, wet=0.4, dirt=0.0, scale=4.0),
    "esclera": dict(base=(0.5, 0.46, 0.42), rough=0.15, rust=0.0, wear=0.0, dirt=0.0, scratches=False),
    "iris": {"flat": (0.012, 0.006, 0.003), "rough": 0.08},
    "pelo": dict(hair=True, base=(0.008, 0.006, 0.006), tip=(0.03, 0.022, 0.018), rough=0.45, scale=3.0),
    "camisa": dict(base=(0.58, 0.57, 0.55), rough=0.9, rust=0.05, wear=0.2, dirt=0.4, bare=(0.5, 0.49, 0.47), scratches=False, soot=0.05),
    "lentes": dict(base=(0.12, 0.11, 0.1), metal=1.0, rough=0.25, rust=0.1, wear=0.4, dirt=0.2, bare=(0.4, 0.38, 0.35)),
    "pantalon": dict(base=(0.025, 0.028, 0.04), rough=0.88, rust=0.1, wear=0.6, dirt=0.9, bare=(0.1, 0.1, 0.12), scratches=False, soot=0.3),
    "zapato": dict(base=(0.035, 0.02, 0.012), rough=0.5, rust=0.0, wear=0.6, dirt=0.6, bare=(0.12, 0.08, 0.05)),
    # Armaduras
    "acero": dict(base=(0.55, 0.56, 0.6), metal=0.75, rough=0.3, rust=0.35, wear=0.5, dirt=0.6, bare=(0.68, 0.68, 0.7), streaks=0.35, soot=0.3, engrave=0.75, engrave_scale=16.0),
    "acero_liso": dict(base=(0.52, 0.53, 0.56), metal=0.75, rough=0.32, rust=0.35, wear=0.5, dirt=0.6, bare=(0.66, 0.66, 0.68), streaks=0.3, soot=0.3),
    "acero_oscuro": dict(base=(0.16, 0.16, 0.18), metal=0.8, rough=0.35, rust=0.5, wear=0.6, dirt=0.75, bare=(0.5, 0.5, 0.52), streaks=0.5, soot=0.5, engrave=0.8, engrave_scale=12.0),
    "ribete": dict(base=(0.6, 0.42, 0.13), metal=1.0, rough=0.3, rust=0.25, wear=0.5, dirt=0.6, bare=(0.75, 0.6, 0.3), engrave=0.4, engrave_scale=30.0),
    "malla": dict(base=(0.12, 0.12, 0.13), metal=1.0, rough=0.42, rust=0.5, wear=0.3, dirt=0.7, bare=(0.4, 0.4, 0.42), chain=1.0),
    "tabardo": dict(base=(0.03, 0.08, 0.05), rough=0.85, rust=0.15, wear=0.6, dirt=0.9, bare=(0.1, 0.14, 0.1), scratches=False, soot=0.3, engrave=0.3, engrave_scale=10.0),
    "tunica": dict(base=(0.02, 0.035, 0.1), rough=0.8, rust=0.1, wear=0.6, dirt=0.8, bare=(0.08, 0.1, 0.18), scratches=False, soot=0.3, engrave=0.35, engrave_scale=12.0),
    "bata_blanca": dict(base=(0.5, 0.52, 0.54), rough=0.85, rust=0.15, wear=0.4, dirt=0.9, bare=(0.3, 0.3, 0.32), scratches=False, soot=0.3, streaks=0.3),
    "capa_verde": dict(base=(0.04, 0.07, 0.035), rough=0.9, rust=0.15, wear=0.7, dirt=1.0, bare=(0.12, 0.13, 0.08), scratches=False, soot=0.4),
    "cuero": dict(base=(0.09, 0.05, 0.025), rough=0.6, rust=0.0, wear=0.85, dirt=0.9, bare=(0.24, 0.15, 0.08), soot=0.3, engrave=0.3, engrave_scale=18.0),
    "cuero_oscuro": dict(base=(0.03, 0.022, 0.016), rough=0.55, rust=0.0, wear=0.8, dirt=0.9, bare=(0.15, 0.11, 0.08)),
    "metal": dict(base=(0.45, 0.45, 0.47), metal=1.0, rough=0.35, rust=0.5, wear=0.5, dirt=0.6, bare=(0.75, 0.75, 0.77)),
    "metal_oscuro": dict(base=(0.05, 0.05, 0.055), metal=0.8, rough=0.45, rust=0.6, wear=0.6, dirt=0.6, bare=(0.4, 0.4, 0.42)),
    "madera": dict(base=(0.14, 0.08, 0.04), rough=0.7, rust=0.0, wear=0.5, dirt=0.6, bare=(0.3, 0.2, 0.1), scratches=False),
    "pluma": dict(base=(0.4, 0.38, 0.33), rough=0.8, rust=0.0, wear=0.2, dirt=0.4, scratches=False),
    "cian": {"emit": (0.3, 0.85, 1.0), "strength": 2.5},
    "naranja": {"emit": (1.0, 0.5, 0.1), "strength": 3.0},
    "runa": {"emit": (0.35, 0.75, 1.0), "strength": 2.5},
    "nucleo_ia": {"emit": (0.6, 0.9, 1.0), "strength": 4.0},
    "verde": {"emit": (0.4, 1.0, 0.45), "strength": 2.0},
}


def body():
    """Cuerpo, cara y ropa base (igual para todas las clases)."""
    H = humano.Humano("male", seed=7)
    T = humano.targets()
    T.update(RIG)
    # Complexión robusta y cara redonda
    H.fit(T, girth={"chest": (1.1, 1.12), "spine": (1.14, 1.2), "pelvis": (1.1, 1.1), "neck": 1.12, "head": (1.1, 1.05),
                    "upper_arm_r": 1.1, "upper_arm_l": 1.1, "forearm_r": 1.05, "forearm_l": 1.05, "thigh_r": 1.08, "thigh_l": 1.08}, names=NAMES)
    H.skin_tint(shaved=0.0, ruddy=0.5)
    H.lips_slot()
    H.eye_mats(iris_size=0.35)
    for e in H.eyes:
        e["slots"] = ["esclera", "iris"]
    return H


def clothes(H, sleeves=True, hair=True):
    camisa = {}
    for rg in ("torso", "arms", "neck"):
        for k, v in H.region(rg).items():
            p = H.base_co[k]
            if p.z < 0.84 or (rg == "neck" and p.z > 1.43):
                continue
            if rg == "arms" and (p.z < 1.18 if sleeves else True):
                continue
            camisa[k] = max(camisa.get(k, 0.0), v)
    H.piece("camisa", camisa, offset=0.008, mat="camisa", thresh=0.3, smooth=1)
    pant = {}
    for rg in ("legs", "torso"):
        for k, v in H.region(rg).items():
            if 0.1 < H.base_co[k].z < 0.97:
                pant[k] = max(pant.get(k, 0.0), v)
    H.piece("pantalon", pant, offset=0.008, mat="pantalon", thresh=0.3, smooth=1)
    # Botas: la malla se suaviza mucho para que no se marquen los dedos
    H.piece("zapatos", "feet", offset=0.02, mat="zapato", thresh=0.2, smooth=12, thick=0.006)
    H.hair("cejas", "brows", mat="pelo", offset=0.003, noise=0.0015)
    if hair:
        curly_hair(H)


def curly_hair(H, n=700):
    """Pelo negro rizado y voluminoso: una capa base y cientos de rizos (esferas aplastadas
    con bultos) repartidos sobre el cuero cabelludo, más altos arriba."""
    import bmesh
    import bpy
    import random
    H.hair("pelo_base", "scalp", mat="pelo", offset=0.024, noise=0.008, smooth=2,
           fn=None)
    rng = random.Random(21)
    scalp = [(k, w) for k, w in H.region("scalp").items() if w > 0.45]
    vs = H.body.data.vertices
    bm = bmesh.new()
    for _ in range(n):
        k, w = scalp[rng.randrange(len(scalp))]
        v = vs[k]
        top = max(0.0, (H.base_co[k].z - 1.6) / 0.09)        # más volumen arriba
        r = rng.uniform(0.009, 0.015) * (1.0 + 0.25 * top)
        c = v.co + v.normal * (0.02 + r * 0.5 + top * 0.03 + rng.uniform(0, 0.01))
        res = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=r)
        q = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
        for nv in res["verts"]:
            p = nv.co.copy()
            p = p + q * p.dot(q) * -0.35                       # aplastada en una dirección
            p *= 1.0 + 0.08 * math.sin(p.x * 300 + p.y * 200)
            nv.co = c + p
    me = bpy.data.meshes.new("rizos")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("rizos", me)
    bpy.context.scene.collection.objects.link(ob)
    for poly in me.polygons:
        poly.use_smooth = True
    ob["mat"] = "pelo"
    H.attach(ob, "pelo")


def glasses(H, lens=None):
    """Lentes redondos de armazón metálico delgado."""
    for sg in (-1, 1):
        c = Vector(H.at((sg * 0.034, 0.142, 1.568)))
        ring = [c + Vector((math.cos(a) * 0.024, 0.0, math.sin(a) * 0.022)) for a in [i / 20 * math.tau for i in range(20)]]
        H._tube("lente_aro_%d" % sg, ring, 0.0017, "lentes", cyclic=True, relax=0)
        if lens:
            H.attach(cyl("lente_%d" % sg, 0.023, 0.002, (c.x, c.y + 0.001, c.z), (90, 0, 0), bone="head", mat=lens, verts=20, bevel=0))
        # Patilla hacia la oreja
        t0 = c + Vector((sg * 0.024, 0, 0.002))
        t1 = Vector(H.at((sg * 0.074, 0.06, 1.575)))
        t2 = Vector(H.at((sg * 0.076, 0.0, 1.56)))
        H._tube("patilla_%d" % sg, [t0, t0.lerp(t1, 0.5), t1, t2], 0.0015, "lentes", relax=0)
    b0 = Vector(H.at((-0.011, 0.146, 1.57)))
    b1 = Vector(H.at((0.011, 0.146, 1.57)))
    H._tube("puente", [b0, (b0 + b1) / 2 + Vector((0, 0.004, 0.004)), b1], 0.0016, "lentes", relax=0)


front = lambda p, n: p.y > -0.01
back = lambda p, n: p.y <= 0.01


def by_side(H, name, sg):
    return {k: v for k, v in H.region(name).items() if H.base_co[k].x * sg > 0}


def plates_limbs(H, mat, trim, glow, heavy=1.0, trim_r=0.006):
    """Brazos y piernas de placas (común al caballero y al tanque)."""
    for s, sg in (("r", 1), ("l", -1)):
        sh = H.zone((sg * 0.19, 0.0, 1.38), 0.15 + 0.02 * (heavy - 1), fn=lambda p: p.z > 1.2)
        H.lames("hombrera_" + s, sh, 1.2, 1.5, 3 + int(heavy > 1.2), rigid="upper_arm_" + s, offset=0.04 * heavy, step=0.012 * heavy, thick=0.01, mat=mat,
                trim=trim, trim_r=trim_r, glow=glow, smooth=4)
        arms = by_side(H, "arms", sg)
        H.plate("brazal_" + s, H.band(arms, 1.12, 1.24), offset=0.018 * heavy, thick=0.007, mat=mat, trim=trim, trim_r=trim_r * 0.7, smooth=3)
        H.plate("codal_" + s, H.zone((sg * 0.28, -0.01, 1.08), 0.06), offset=0.026 * heavy, thick=0.008, mat=mat, trim=trim, trim_r=trim_r * 0.7, smooth=3)
        H.lames("avambrazo_" + s, H.band(arms, 0.88, 1.04), 0.88, 1.04, 3, offset=0.016 * heavy, step=0.004, thick=0.007, mat=mat, trim=trim, trim_r=trim_r * 0.6, glow=glow, smooth=3)
        H.plate("guantelete_" + s, by_side(H, "hands", sg), offset=0.01, thick=0.005, mat="acero_liso" if mat == "acero" else mat, trim=None, smooth=2)
        legs = by_side(H, "legs", sg)
        H.plate("quijote_" + s, H.band(legs, 0.55, 0.82), offset=0.022 * heavy, thick=0.008, mat=mat, trim=trim, trim_r=trim_r * 0.7, fn=lambda p, n: p.y > -0.03, smooth=3)
        H.plate("rodillera_" + s, H.zone((sg * 0.11, 0.07, 0.47), 0.07, fn=lambda p: p.y > -0.02), offset=0.03 * heavy, thick=0.01, mat=mat, trim=trim, trim_r=trim_r * 0.7, glow=glow, smooth=3)
        H.plate("greba_" + s, H.band(legs, 0.1, 0.43), offset=0.024 * heavy, thick=0.008, mat=mat, trim=trim, trim_r=trim_r * 0.7, glow=glow, smooth=3)
        feet = by_side(H, "feet", sg)
        H.plate("escarpe_" + s, feet, offset=0.02, thick=0.007, mat=mat, trim=trim, trim_r=trim_r * 0.5, thresh=0.25, smooth=2)


def helm(H, mat, trim, visor_mat, grille=False, offset=0.028):
    def cut(p, n):
        return not (p.y > 0.05 and 1.556 < p.z < 1.578)
    H.plate("yelmo", H.zone((0, 0.02, 1.565), 0.16, fn=lambda p: p.z > 1.42), offset=offset, thick=0.009, mat=mat, trim=trim, trim_r=0.005, fn=cut, smooth=4)
    v = H.at((0, 0.12, 1.567))
    H.attach(box("visor", (0.13, 0.03, 0.012), (v[0], v[1] + offset * 0.6, v[2]), bone="head", mat=visor_mat, bevel=0.004))
    if grille:
        for k in range(4):
            g = H.at((0, 0.13, 1.5 - k * 0.018))
            H.attach(box("rejilla_%d" % k, (0.08, 0.015, 0.006), (g[0], g[1] + offset, g[2]), bone="head", mat="metal_oscuro", bevel=0.002))
    c = H.at((0, 0.0, 1.69))
    H.attach(box("cresta", (0.025, 0.24, 0.035), (c[0], c[1], c[2] + offset), bone="head", mat=trim, bevel=0.006))


def hood(H, mat, extra=0.0):
    hd = H.zone((0, 0.0, 1.57), 0.17, fn=lambda p: p.z > 1.42 and not (p.y > 0.06 and p.z < 1.62))
    H.piece("capucha", hd, offset=0.03 + extra, mat=mat, thresh=0.3, smooth=3, noise=0.004)


def build(cls):
    bk.reset(seed=900 + hash(cls) % 100)
    bk.define_materials(MATS)
    H = body()
    helmeted = cls in ("cyber", "backend")
    hooded = cls == "frontend"
    clothes(H, hair=not (helmeted or hooded))
    torso = H.band("torso", 1.0, 1.42)

    if cls == "cyber":
        H.piece("cota", {k: v for k, v in H.region("torso").items()}, offset=0.014, mat="malla", thresh=0.3, smooth=1)
        H.plate("peto", torso, offset=0.035, thick=0.012, mat="acero", trim="ribete", glow="cian", fn=front, flutes=(7.0, 0.005, 0), smooth=4)
        H.plate("espaldar", torso, offset=0.032, thick=0.01, mat="acero", trim="ribete", glow="cian", fn=back, smooth=4)
        H.lames("gola", H.band("neck", 1.36, 1.46), 1.36, 1.46, 2, offset=0.026, step=0.007, thick=0.007, mat="acero", trim="ribete", trim_r=0.004, smooth=3)
        H.lames("escarcela", H.band("torso", 0.84, 1.0), 0.84, 1.0, 2, offset=0.04, step=0.009, thick=0.008, mat="acero", trim="ribete", trim_r=0.004, smooth=3)
        plates_limbs(H, "acero", "ribete", "cian")
        H.strap("tabardo", (0, 0.13, 1.0), (0, 0.13, 0.5), 0.15, region=None, offset=0.07, mat="tabardo", fn=lambda p, n: p.y > 0.0 and abs(p.x) < 0.09)
        e = H.at((0, 0.16, 0.86))
        H.attach(box("candado", (0.05, 0.02, 0.045), (e[0], e[1] + 0.06, e[2]), bone="pelvis", mat="ribete", bevel=0.008))
        H.attach(cyl("candado_arco", 0.017, 0.012, (e[0], e[1] + 0.06, e[2] + 0.035), (0, 90, 0), bone="pelvis", mat="ribete", verts=14))
        capa = {k: v for k, v in H.region("torso").items() if H.base_co[k].y < -0.03 and H.base_co[k].z > 1.15}
        H.piece("capa", capa, offset=0.06, mat="tabardo", thresh=0.3, smooth=3, noise=0.004, extrude=(0.55, 0.12), tatter=(0.25, 0.2))
        helm(H, "acero", "ribete", "cian")
    elif cls == "backend":
        H.piece("cota", {k: v for k, v in H.region("torso").items()}, offset=0.016, mat="malla", thresh=0.3, smooth=1, extrude=(0.12, 0.05))
        H.plate("peto", torso, offset=0.05, thick=0.016, mat="acero_oscuro", trim="ribete", trim_r=0.008, glow="naranja", fn=front, flutes=(5.0, 0.007, 0), smooth=4)
        H.plate("espaldar", torso, offset=0.045, thick=0.014, mat="acero_oscuro", trim="ribete", trim_r=0.008, fn=back, smooth=4)
        H.lames("gola", H.band("neck", 1.34, 1.47), 1.34, 1.47, 3, offset=0.034, step=0.008, thick=0.009, mat="acero_oscuro", trim="ribete", trim_r=0.005, smooth=3)
        H.lames("escarcela", H.band("torso", 0.82, 1.0), 0.82, 1.0, 3, offset=0.05, step=0.01, thick=0.01, mat="acero_oscuro", trim="ribete", trim_r=0.005, glow="naranja", smooth=3)
        plates_limbs(H, "acero_oscuro", "ribete", "naranja", heavy=1.45, trim_r=0.007)
        helm(H, "acero_oscuro", "ribete", "naranja", grille=True, offset=0.034)
        # Módulo de servidor a la espalda con luces
        r = H.at((0, -0.16, 1.22))
        H.attach(box("modulo", (0.3, 0.12, 0.34), r, bone="chest", mat="metal_oscuro", bevel=0.02))
        for k in range(4):
            H.attach(box("bahia_%d" % k, (0.24, 0.01, 0.04), (r[0], r[1] - 0.065, r[2] - 0.11 + k * 0.07), bone="chest", mat="metal", bevel=0.004))
            H.attach(box("led_%d" % k, (0.018, 0.008, 0.018), (r[0] + 0.09, r[1] - 0.072, r[2] - 0.11 + k * 0.07), bone="chest", mat="naranja" if k % 2 else "verde", bevel=0.002))
        for sg in (-1, 1):
            H.attach(cable("cable_%d" % sg, [(r[0] + sg * 0.1, r[1] - 0.04, r[2] + 0.17), (sg * 0.15, r[1] + 0.05, r[2] + 0.22), (sg * 0.17, r[1] + 0.12, r[2] + 0.12)], 0.012, bone="chest", mat="cuero_oscuro"))
    elif cls == "frontend":
        tun = {}
        for rg in ("torso", "arms", "neck"):
            for k, v in H.region(rg).items():
                p = H.base_co[k]
                if p.z > 0.86 and not (rg == "arms" and p.z < 1.0):
                    tun[k] = max(tun.get(k, 0.0), v)
        H.piece("tunica", tun, offset=0.022, mat="tunica", thresh=0.3, smooth=3, noise=0.003, extrude=(0.72, 0.3), tatter=(0.2, 0.15))
        for sg in (-1, 1):
            H.strap("runa_%d" % sg, (sg * 0.07, 0.12, 1.42), (sg * 0.06, 0.12, 0.86), 0.018, region="torso", offset=0.03, mat="runa", fn=front)
        H.lames("manto", H.zone((0, 0.0, 1.38), 0.26, fn=lambda p: p.z > 1.25 and abs(p.x) < 0.3), 1.25, 1.46, 3, offset=0.04, step=0.01, thick=0.008, mat="cuero", trim="ribete", trim_r=0.004, glow="runa", smooth=3)
        for s, sg in (("r", 1), ("l", -1)):
            H.lames("brazal_" + s, H.band(by_side(H, "arms", sg), 0.88, 1.03), 0.88, 1.03, 2, offset=0.018, step=0.004, thick=0.006, mat="cuero", trim="ribete", trim_r=0.004, glow="runa", smooth=3)
        H.plate("cinturon", H.band("torso", 0.94, 0.985), offset=0.03, thick=0.008, mat="cuero", trim="ribete", trim_r=0.004, smooth=2)
        hood(H, "tunica")
        v = H.at((0, 0.13, 1.567))
        glasses(H)
    elif cls == "ai":
        bata = {}
        for rg in ("torso", "arms"):
            for k, v in H.region(rg).items():
                p = H.base_co[k]
                if p.z > 0.86 and not (rg == "arms" and p.z < 0.98) and not (abs(p.x) < 0.06 and p.y > 0.0):
                    bata[k] = max(bata.get(k, 0.0), v)
        H.piece("bata", bata, offset=0.022, mat="bata_blanca", thresh=0.3, smooth=3, noise=0.003, extrude=(0.4, 0.14), tatter=(0.1, 0.1))
        for sg in (-1, 1):
            H.strap("arnes_%d" % sg, (sg * 0.15, 0.0, 1.42), (-sg * 0.1, 0.1, 1.0), 0.03, region="torso", offset=0.034, mat="cuero_oscuro")
        c = H.at((0, 0.12, 1.25))
        H.attach(cyl("nucleo_aro", 0.045, 0.025, (c[0], c[1] + 0.035, c[2]), (90, 0, 0), bone="chest", mat="metal_oscuro", verts=28))
        H.attach(cyl("nucleo", 0.032, 0.028, (c[0], c[1] + 0.04, c[2]), (90, 0, 0), bone="chest", mat="nucleo_ia", verts=28))
        for k in range(6):
            a = k / 6 * math.tau
            H.attach(box("nucleo_diente_%d" % k, (0.012, 0.012, 0.02), (c[0] + math.cos(a) * 0.05, c[1] + 0.04, c[2] + math.sin(a) * 0.05), bone="chest", mat="metal", bevel=0.002))
        v = H.at((0, 0.13, 1.567))
        glasses(H)
        for s, sg in (("r", 1), ("l", -1)):
            H.plate("bota_tec_" + s, H.band(by_side(H, "legs", sg), 0.08, 0.36), offset=0.022, thick=0.007, mat="metal_oscuro", trim="ribete", trim_r=0.004, glow="cian", smooth=3)
            H.plate("guante_" + s, by_side(H, "hands", sg), offset=0.008, thick=0.004, mat="cuero_oscuro", trim=None, smooth=2)
    else:  # data
        H.plate("brigantina", torso, offset=0.022, thick=0.01, mat="cuero", trim="cuero_oscuro", trim_r=0.005, smooth=3)
        for k in range(28):
            p = H.at((((k % 7) - 3) * 0.045, 0.14, 1.06 + (k // 7) * 0.09))
            H.attach(sphere("remache_%d" % k, 0.006, (p[0], p[1] + 0.03, p[2]), bone="chest", mat="metal", segs=8))
        capa = {k: v for k, v in H.region("torso").items() if H.base_co[k].y < -0.02 and H.base_co[k].z > 1.15}
        H.piece("capa", capa, offset=0.05, mat="capa_verde", thresh=0.3, smooth=3, noise=0.005, extrude=(0.5, 0.14), tatter=(0.3, 0.35))
        glasses(H)
        H.plate("cinturon", H.band("torso", 0.93, 0.98), offset=0.028, thick=0.008, mat="cuero_oscuro", trim="metal", trim_r=0.003, smooth=2)
        for k, x in enumerate((-0.14, -0.07, 0.1)):
            p = H.at((x, 0.13 - abs(x) * 0.3, 0.92))
            H.attach(bk.blob("bolsa_%d" % k, 0.035, (p[0], p[1] + 0.03, p[2]), (1.0, 0.6, 1.1), bone="pelvis", mat="cuero", lumps=0.06))
        for s, sg in (("r", 1), ("l", -1)):
            H.plate("brazal_" + s, H.band(by_side(H, "arms", sg), 0.87, 1.04), offset=0.016, thick=0.007, mat="cuero", trim="cuero_oscuro", trim_r=0.003, smooth=3)
            H.plate("guante_" + s, by_side(H, "hands", sg), offset=0.008, thick=0.004, mat="cuero_oscuro", trim=None, smooth=2)
            H.plate("bota_" + s, H.band(by_side(H, "legs", sg), 0.08, 0.38), offset=0.02, thick=0.006, mat="cuero", trim="cuero_oscuro", trim_r=0.004, smooth=3)
        # Carcaj con flechas
        q = H.at((0.06, -0.16, 1.2))
        H.attach(cyl("carcaj", 0.055, 0.5, (q[0], q[1] - 0.04, q[2]), (0, -20, 0), bone="chest", mat="cuero", verts=16))
        for k in range(5):
            dx = (k - 2) * 0.012
            H.attach(cyl("flecha_%d" % k, 0.004, 0.35, (q[0] + 0.09 + dx, q[1] - 0.04, q[2] + 0.32), (0, -20, 0), bone="chest", mat="madera", verts=6))
            H.attach(box("pluma_%d" % k, (0.004, 0.025, 0.05), (q[0] + 0.15 + dx, q[1] - 0.04, q[2] + 0.48), (0, -20, 0), bone="chest", mat="pluma", bevel=0.001))

    name = "jugador_" + cls
    bk.finish(name, tex_size=4096, bake=True, out_dir=OUT)
    if PREVIEW:
        bk.set_pose({})
        bk.render_preview(os.path.join(OUT, "preview_%s.png" % name), (1.6, 3.8, 1.5), (0, 0, 1.0), size=(800, 1000))
        bk.render_preview(os.path.join(OUT, "preview_%s_atras.png" % name), (-1.6, -3.6, 1.6), (0, 0, 1.0), size=(800, 1000))
        bk.render_preview(os.path.join(OUT, "preview_%s_cara.png" % name), (0.25, 0.75, 1.62), (0, 0.03, 1.55), size=(800, 800))
    bk.export(os.path.join(OUT, name + ".glb"), actions=False)


for c in ("cyber", "backend", "frontend", "ai", "data"):
    if not ONLY or c in ONLY:
        build(c)
print("LISTO", OUT)
