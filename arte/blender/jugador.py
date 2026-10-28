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
from bk import box, cyl, sphere, label, cable, limb
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
    # Mago (archimago del Frontend)
    "abrigo_mago": dict(base=(0.012, 0.016, 0.05), rough=0.75, rust=0.1, wear=0.55, dirt=0.75, bare=(0.06, 0.07, 0.14), scratches=False, soot=0.25, engrave=0.45, engrave_scale=9.0),
    "seda_mago": dict(base=(0.03, 0.05, 0.16), rough=0.6, rust=0.0, wear=0.4, dirt=0.6, bare=(0.1, 0.12, 0.25), scratches=False, engrave=0.3, engrave_scale=14.0),
    "oro": dict(base=(0.78, 0.56, 0.2), metal=0.85, rough=0.3, rust=0.2, wear=0.5, dirt=0.55, bare=(0.82, 0.66, 0.35), engrave=0.7, engrave_scale=28.0),
    "tapa_libro": dict(base=(0.18, 0.04, 0.03), rough=0.6, rust=0.0, wear=0.7, dirt=0.7, bare=(0.35, 0.2, 0.12), engrave=0.5, engrave_scale=12.0),
    "papel": dict(base=(0.62, 0.57, 0.45), rough=0.9, rust=0.2, wear=0.1, dirt=0.6, scratches=False),
    # Armaduras de resistencia (las vende el mercader)
    "acero_rojo": dict(base=(0.2, 0.035, 0.025), metal=0.75, rough=0.33, rust=0.35, wear=0.55, dirt=0.7, bare=(0.55, 0.5, 0.48), streaks=0.3, soot=0.7, engrave=0.7, engrave_scale=14.0),
    "cobre": dict(base=(0.55, 0.25, 0.12), metal=1.0, rough=0.3, rust=0.45, wear=0.4, dirt=0.6, bare=(0.85, 0.5, 0.3), engrave=0.3, engrave_scale=30.0),
    "malla_cobre": dict(base=(0.4, 0.18, 0.08), metal=1.0, rough=0.4, rust=0.4, wear=0.3, dirt=0.6, bare=(0.7, 0.4, 0.25), chain=1.0),
    "goma_negra": dict(base=(0.02, 0.02, 0.022), rough=0.7, rust=0.0, wear=0.3, dirt=0.6, bare=(0.08, 0.08, 0.08), scratches=False),
    "hazmat": dict(base=(0.6, 0.42, 0.03), rough=0.55, rust=0.3, wear=0.4, dirt=0.9, bare=(0.3, 0.25, 0.1), scratches=False, streaks=0.6, soot=0.3),
    "acero_violeta": dict(base=(0.2, 0.16, 0.28), metal=0.7, rough=0.36, rust=0.3, wear=0.5, dirt=0.6, bare=(0.45, 0.42, 0.5), engrave=0.8, engrave_scale=10.0),
    "tela_vino": dict(base=(0.11, 0.008, 0.015), rough=0.85, rust=0.0, wear=0.4, dirt=0.7, bare=(0.2, 0.05, 0.05), scratches=False, soot=0.3, engrave=0.4, engrave_scale=10.0),
    "acero_rector": dict(base=(0.2, 0.2, 0.22), metal=0.75, rough=0.34, rust=0.3, wear=0.5, dirt=0.6, bare=(0.55, 0.55, 0.57), streaks=0.3, soot=0.3, engrave=0.9, engrave_scale=14.0),
    "vidrio_verde": {"emit": (0.35, 1.0, 0.3), "strength": 1.2},
    "violeta": {"emit": (0.65, 0.3, 1.0), "strength": 3.0},
    "rojo_lava": {"emit": (1.0, 0.3, 0.05), "strength": 4.0},
    # Mercader (como la foto: chamarra gris-beige, playera azul marino, mezclilla, audífonos y gafete)
    "piel_mercader": dict(skin=True, base=(0.3, 0.165, 0.095), veins=0.05, vein_col=(0.2, 0.08, 0.06), blotch=0.3, blotch_col=(0.33, 0.14, 0.09), rough=0.42, wet=0.12, dirt=0.05, scale=3.0, tint_attr="tinte"),
    "labios_mercader": dict(skin=True, base=(0.24, 0.1, 0.075), veins=0.0, blotch=0.3, blotch_col=(0.3, 0.1, 0.08), rough=0.3, wet=0.4, dirt=0.0, scale=4.0),
    "pelo_lacio": dict(hair=True, base=(0.006, 0.005, 0.005), tip=(0.02, 0.016, 0.014), rough=0.4, scale=6.0),
    "armazon": dict(base=(0.012, 0.012, 0.014), rough=0.25, rust=0.0, wear=0.25, dirt=0.15, bare=(0.08, 0.08, 0.08), scratches=False),
    "playera_marino": dict(base=(0.014, 0.035, 0.05), rough=0.9, rust=0.0, wear=0.25, dirt=0.4, bare=(0.04, 0.07, 0.09), scratches=False),
    "chamarra": dict(base=(0.17, 0.16, 0.135), rough=0.55, rust=0.0, wear=0.3, dirt=0.55, bare=(0.24, 0.23, 0.2), scratches=False, streaks=0.15),
    "mezclilla": dict(base=(0.11, 0.17, 0.3), rough=0.85, rust=0.0, wear=0.8, dirt=0.6, bare=(0.3, 0.38, 0.5), scratches=True),
    "tenis": dict(base=(0.03, 0.03, 0.035), rough=0.6, rust=0.0, wear=0.5, dirt=0.7, bare=(0.4, 0.4, 0.4)),
    "plastico_negro": dict(base=(0.02, 0.02, 0.022), rough=0.35, rust=0.0, wear=0.3, dirt=0.3, bare=(0.12, 0.12, 0.12)),
    "liston_rojo": dict(base=(0.5, 0.02, 0.02), rough=0.7, rust=0.0, wear=0.2, dirt=0.4, scratches=False),
    "gafete": dict(base=(0.75, 0.75, 0.72), rough=0.35, rust=0.0, wear=0.1, dirt=0.3, scratches=False),
    "cian": {"emit": (0.3, 0.85, 1.0), "strength": 2.5},
    "naranja": {"emit": (1.0, 0.5, 0.1), "strength": 3.0},
    "runa": {"emit": (0.35, 0.75, 1.0), "strength": 2.5},
    "nucleo_ia": {"emit": (0.6, 0.9, 1.0), "strength": 4.0},
    "verde": {"emit": (0.4, 1.0, 0.45), "strength": 2.0},
}


def body(mercader=False):
    """Cuerpo, cara y ropa base (igual para todas las clases). Las manos quedan cerradas
    en puño de agarre (humano.curl_hands) para que las armas no floten junto a la palma."""
    H = humano.Humano("male", seed=7)
    H.curl_hands()
    T = humano.targets()
    T.update(RIG)
    if mercader:
        # Más robusto y de cara más redonda que el jugador
        H.fit(T, girth={"chest": (1.14, 1.18), "spine": (1.22, 1.3), "pelvis": (1.14, 1.16), "neck": 1.18, "head": (1.13, 1.08),
                        "upper_arm_r": 1.14, "upper_arm_l": 1.14, "forearm_r": 1.08, "forearm_l": 1.08, "thigh_r": 1.12, "thigh_l": 1.12}, names=NAMES)
        H.skin_tint(shaved=0.0, ruddy=0.4)
        H.lips_slot(skin="piel_mercader", lips="labios_mercader")
        H.eye_mats(iris_size=0.35)
        for e in H.eyes:
            e["slots"] = ["esclera", "iris"]
        return H
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


def gold_line(H, name, pts, r=0.007, mat="oro"):
    """Ribete/bordado (tubo) que pasa por puntos de la malla base y se mueve con la piel."""
    q = [Vector(H.at(p)) for p in pts]
    H.attach(cable(name, [tuple(v) for v in q], r, mat=mat))


def archimago(H, torso):
    """Mago (Frontend): archimago al estilo de los hechiceros de Raya Lucaria con
    tecnología. Túnica de seda hasta el piso, abrigo largo abierto con bordados de oro,
    collar alto, manto de láminas con runas de código, capucha puntiaguda con una corona
    de cristales que brillan, faja ancha con tomos encadenados y guantes de cuero."""
    # Túnica interior de seda hasta los tobillos
    tun = {}
    for rg in ("torso", "arms", "neck"):
        for k, v in H.region(rg).items():
            p = H.base_co[k]
            if p.z > 0.86 and not (rg == "arms" and p.z < 1.0):
                tun[k] = max(tun.get(k, 0.0), v)
    H.piece("tunica", tun, offset=0.026, mat="seda_mago", thresh=0.3, smooth=9, noise=0.002, extrude=(0.8, 0.22), tatter=(0.05, 0.08))
    # Abrigo largo abierto por delante (mangas acampanadas hasta el codo)
    ab = {}
    for rg in ("torso", "arms", "neck"):
        for k, v in H.region(rg).items():
            p = H.base_co[k]
            if p.z < 0.9 or (rg == "arms" and p.z < 1.06):
                continue
            if abs(p.x) < 0.075 and p.y > 0.02 and p.z < 1.42:
                continue
            ab[k] = max(ab.get(k, 0.0), v)
    H.piece("abrigo", ab, offset=0.042, mat="abrigo_mago", thresh=0.3, smooth=7, noise=0.003, extrude=(0.86, 0.42), tatter=(0.16, 0.18))
    # Bordados de oro en la orilla del abrigo y runas que brillan
    for sg in (-1, 1):
        gold_line(H, "orilla_%d" % sg, [(sg * 0.08, 0.15, 1.4), (sg * 0.085, 0.165, 1.2), (sg * 0.095, 0.16, 1.0), (sg * 0.12, 0.2, 0.62), (sg * 0.15, 0.26, 0.2)], 0.008)
        gold_line(H, "orilla_runa_%d" % sg, [(sg * 0.1, 0.152, 1.36), (sg * 0.105, 0.162, 1.18), (sg * 0.115, 0.158, 1.0), (sg * 0.14, 0.2, 0.62), (sg * 0.17, 0.26, 0.24)], 0.0035, mat="runa")
    # Collar alto abierto (estilo hechicero), con ribete de oro
    col = H.zone((0, 0.0, 1.43), 0.13, fn=lambda p: 1.36 < p.z < 1.52 and not (p.y > 0.05 and abs(p.x) < 0.05))
    H.plate("collar", col, offset=0.05, thick=0.01, mat="abrigo_mago", trim="oro", trim_r=0.006, glow="runa", smooth=3)
    # Manto de láminas de cuero sobre los hombros con runas, y una capa corta rasgada
    H.lames("manto", H.zone((0, 0.0, 1.38), 0.27, fn=lambda p: p.z > 1.24 and abs(p.x) < 0.31), 1.24, 1.46, 3, offset=0.05, step=0.012, thick=0.009,
            mat="abrigo_mago", trim="oro", trim_r=0.006, glow="runa", smooth=4)
    capa = {k: v for k, v in H.region("torso").items() if H.base_co[k].y < -0.02 and H.base_co[k].z > 1.18}
    H.piece("capa", capa, offset=0.07, mat="seda_mago", thresh=0.3, smooth=3, noise=0.005, extrude=(0.42, 0.18), tatter=(0.28, 0.3))
    # Estola bordada sobre el pecho (cubre la túnica entre las orillas del abrigo)
    H.plate("estola", H.band("torso", 0.97, 1.4), offset=0.06, thick=0.008, mat="seda_mago", trim="oro", trim_r=0.005, glow="runa",
            fn=lambda p, n: p.y > 0.02 and abs(p.x) < 0.1, smooth=14)
    # Tabardo central con el símbolo </>
    H.strap("tabardo", (0, 0.13, 1.02), (0, 0.13, 0.62), 0.12, region=None, offset=0.06, mat="seda_mago", fn=lambda p, n: p.y > 0.0 and abs(p.x) < 0.08)
    e = H.at((0, 0.17, 0.84))
    H.attach(label("simbolo", "</>", (e[0], e[1] + 0.05, e[2]), (90, 0, 180), size=0.07, depth=0.004, bone="pelvis", mat="oro"))
    # Faja ancha con hebilla y tomos encadenados
    H.plate("faja", H.band("torso", 0.9, 0.99), offset=0.045, thick=0.01, mat="cuero", trim="oro", trim_r=0.005, smooth=2)
    b = H.at((0, 0.16, 0.95))
    H.attach(cyl("hebilla", 0.04, 0.02, (b[0], b[1] + 0.05, b[2]), (90, 0, 0), bone="pelvis", mat="oro", verts=20))
    H.attach(cyl("hebilla_gema", 0.018, 0.024, (b[0], b[1] + 0.055, b[2]), (90, 0, 0), bone="pelvis", mat="runa", verts=14))
    for k, (x, y) in enumerate(((-0.17, 0.08), (0.18, 0.02))):
        q = H.at((x, y, 0.8))
        H.attach(box("tomo_%d" % k, (0.04, 0.13, 0.17), (q[0] + (0.05 if x > 0 else -0.05), q[1], q[2]), (0, 0, 8 if x > 0 else -8), bone="pelvis", mat="tapa_libro", bevel=0.008))
        H.attach(box("tomo_hojas_%d" % k, (0.042, 0.115, 0.155), (q[0] + (0.05 if x > 0 else -0.05), q[1] + 0.008, q[2]), (0, 0, 8 if x > 0 else -8), bone="pelvis", mat="papel", bevel=0.002))
        H.attach(box("tomo_esquina_%d" % k, (0.045, 0.03, 0.03), (q[0] + (0.05 if x > 0 else -0.05), q[1] + 0.06, q[2] + 0.075), bone="pelvis", mat="oro", bevel=0.004))
        top = H.at((x * 0.8, 0.1, 0.93))
        H.attach(cable("cadena_%d" % k, [top, ((top[0] + q[0]) / 2, (top[1] + q[1]) / 2 + 0.02, (top[2] + q[2]) / 2 + 0.06), (q[0] + (0.05 if x > 0 else -0.05), q[1], q[2] + 0.09)], 0.004, mat="oro"))
    # Brazales y guantes
    for s_, sg in (("r", 1), ("l", -1)):
        H.lames("brazal_" + s_, H.band(by_side(H, "arms", sg), 0.88, 1.05), 0.88, 1.05, 3, offset=0.022, step=0.004, thick=0.006, mat="abrigo_mago", trim="oro", trim_r=0.004, glow="runa", smooth=3)
        H.plate("guante_" + s_, by_side(H, "hands", sg), offset=0.008, thick=0.004, mat="cuero_oscuro", trim=None, smooth=2)
        H.plate("bota_" + s_, H.band(by_side(H, "legs", sg), 0.06, 0.36), offset=0.022, thick=0.006, mat="cuero_oscuro", trim="oro", trim_r=0.003, smooth=3)
    # Capucha honda y amplia con punta caída hacia atrás
    hd = H.zone((0, 0.0, 1.57), 0.18, fn=lambda p: p.z > 1.41 and not (p.y > 0.05 and p.z < 1.63 and abs(p.x) < 0.085))
    H.piece("capucha", hd, offset=0.05, mat="abrigo_mago", thresh=0.3, smooth=7, noise=0.003)
    t0 = H.at((0, -0.08, 1.72))
    t1 = H.at((0, -0.19, 1.66))
    t2 = H.at((0.02, -0.27, 1.5))
    H.attach(limb("capucha_punta", [t0, t1, t2], [0.075, 0.045, 0.012], mat="abrigo_mago", verts=12))
    # Corona de cristales sobre la capucha, a la altura de la frente
    ring = []
    for k in range(18):
        a_ = -math.pi * 0.62 + k / 17 * math.pi * 1.24
        ring.append((math.sin(a_) * 0.15, math.cos(a_) * 0.152 + 0.012, 1.645 + 0.01 * math.cos(a_)))
    gold_line(H, "corona", ring, 0.007)
    for k, a_ in enumerate((-0.6, -0.3, 0.0, 0.3, 0.6)):
        base = H.at((math.sin(a_) * 0.15, math.cos(a_) * 0.154 + 0.012, 1.65))
        h = 0.085 if k == 2 else 0.05
        H.attach(cyl("cristal_%d" % k, 0.011, h, (base[0], base[1] + 0.006, base[2] + h * 0.5), (-10 * math.cos(a_), 0, -a_ * 20), bone="head", mat="runa", verts=6, r2=0.0, bevel=0))
    glasses(H)


# ---------------------------------------------------------------- armaduras del mercader

def horn(H, name, base, tip, r0, mat):
    b = Vector(H.at(base))
    t = Vector(H.at(tip))
    m = b.lerp(t, 0.5) + Vector((0, 0, 0.05))
    H.attach(limb(name, [b, m, t], [r0, r0 * 0.6, 0.004], mat=mat, verts=10))


def armadura(aid, H, torso):
    """Armaduras de resistencia que vende el mercader (reemplazan la ropa de la clase)."""
    H.piece("subtraje", {k: v for k, v in H.region("torso").items()}, offset=0.012, mat="malla" if aid != "aislante" else "malla_cobre", thresh=0.3, smooth=1)
    if aid == "ignifuga":
        # Cortafuegos: acero rojo oscuro tiznado, rejillas de lava y yelmo con cuernos
        H.plate("peto", torso, offset=0.045, thick=0.014, mat="acero_rojo", trim="metal_oscuro", trim_r=0.007, glow="rojo_lava", fn=front, flutes=(6.0, 0.006, 0), smooth=4)
        H.plate("espaldar", torso, offset=0.042, thick=0.012, mat="acero_rojo", trim="metal_oscuro", trim_r=0.007, glow="rojo_lava", fn=back, smooth=4)
        H.lames("escarcela", H.band("torso", 0.8, 1.0), 0.8, 1.0, 3, offset=0.05, step=0.01, thick=0.009, mat="acero_rojo", trim="metal_oscuro", trim_r=0.005, glow="rojo_lava", smooth=3)
        plates_limbs(H, "acero_rojo", "metal_oscuro", "rojo_lava", heavy=1.25)
        helm(H, "acero_rojo", "metal_oscuro", "rojo_lava", grille=True, offset=0.032)
        for sg in (-1, 1):
            horn(H, "cuerno_%d" % sg, (sg * 0.08, 0.02, 1.68), (sg * 0.22, -0.02, 1.86), 0.03, "metal_oscuro")
            v = H.at((sg * 0.12, -0.12, 1.25))
            for k in range(3):
                H.attach(box("rejilla_%d_%d" % (sg, k), (0.06, 0.01, 0.012), (v[0], v[1] - 0.05, v[2] - 0.05 + k * 0.04), bone="chest", mat="rojo_lava", bevel=0.002))
        capa = {k: v for k, v in H.region("torso").items() if H.base_co[k].y < -0.03 and H.base_co[k].z > 1.15}
        H.piece("capa", capa, offset=0.07, mat="tela_vino", thresh=0.3, smooth=3, noise=0.005, extrude=(0.6, 0.16), tatter=(0.35, 0.3))
    elif aid == "aislante":
        # Traje de Faraday: malla de cobre, placas de goma aislante, bobinas y pararrayos
        H.plate("peto", torso, offset=0.04, thick=0.012, mat="goma_negra", trim="cobre", trim_r=0.007, glow="cian", fn=front, smooth=5)
        H.plate("espaldar", torso, offset=0.038, thick=0.012, mat="goma_negra", trim="cobre", trim_r=0.007, fn=back, smooth=5)
        plates_limbs(H, "goma_negra", "cobre", "cian", heavy=1.05)
        helm(H, "goma_negra", "cobre", "cian", offset=0.03)
        for sg in (-1, 1):
            c = H.at((sg * 0.2, 0.0, 1.45))
            for k in range(5):
                H.attach(cyl("bobina_%d_%d" % (sg, k), 0.05 - k * 0.006, 0.014, (c[0], c[1], c[2] + 0.06 + k * 0.022), bone="upper_arm_" + ("r" if sg > 0 else "l"), mat="cobre", verts=18, bevel=0.003))
            r = H.at((sg * 0.09, -0.17, 1.3))
            H.attach(cyl("pararrayos_%d" % sg, 0.012, 0.5, (r[0], r[1] - 0.04, r[2] + 0.25), bone="chest", mat="cobre", verts=8))
            H.attach(sphere("esfera_%d" % sg, 0.035, (r[0], r[1] - 0.04, r[2] + 0.52), bone="chest", mat="cian", segs=12))
        q = H.at((0, 0.16, 1.22))
        H.attach(cyl("nucleo", 0.04, 0.02, (q[0], q[1] + 0.05, q[2]), (90, 0, 0), bone="chest", mat="cian", verts=20))
    elif aid == "antiveneno":
        # Hazmat Bio-7: traje amarillo de goma con placas, máscara de gas y tanques
        hz = {}
        for rg in ("torso", "arms", "legs", "neck"):
            for k, v in H.region(rg).items():
                hz[k] = max(hz.get(k, 0.0), v)
        H.piece("hazmat", hz, offset=0.036, mat="hazmat", thresh=0.3, smooth=10, noise=0.004)
        H.plate("peto", torso, offset=0.055, thick=0.01, mat="acero_liso", trim="metal_oscuro", trim_r=0.006, glow="vidrio_verde", fn=lambda p, n: p.y > 0.04 and abs(p.x) < 0.15, smooth=4)
        for s_, sg in (("r", 1), ("l", -1)):
            H.plate("guante_" + s_, by_side(H, "hands", sg), offset=0.012, thick=0.005, mat="goma_negra", trim=None, smooth=2)
            H.plate("bota_" + s_, H.band(by_side(H, "legs", sg), 0.06, 0.4), offset=0.04, thick=0.008, mat="goma_negra", trim=None, smooth=3)
            H.plate("rodillera_" + s_, H.zone((sg * 0.11, 0.07, 0.47), 0.07, fn=lambda p: p.y > -0.02), offset=0.05, thick=0.01, mat="acero_liso", trim="metal_oscuro", trim_r=0.004, smooth=3)
        hood(H, "hazmat", extra=0.01)
        v = H.at((0, 0.14, 1.56))
        H.attach(box("visor", (0.15, 0.03, 0.08), (v[0], v[1] + 0.04, v[2] + 0.01), bone="head", mat="vidrio_verde", bevel=0.02))
        H.attach(cyl("mascara", 0.045, 0.06, (v[0], v[1] + 0.06, v[2] - 0.06), (90, 0, 0), bone="head", mat="goma_negra", verts=16))
        for sg in (-1, 1):
            H.attach(cyl("filtro_%d" % sg, 0.03, 0.05, (v[0] + sg * 0.06, v[1] + 0.06, v[2] - 0.08), (70, 0, sg * 30), bone="head", mat="metal_oscuro", verts=16))
        t = H.at((0, -0.17, 1.15))
        for sg in (-1, 1):
            H.attach(cyl("tanque_%d" % sg, 0.06, 0.42, (t[0] + sg * 0.075, t[1] - 0.06, t[2]), bone="chest", mat="acero_liso", verts=18))
            H.attach(cyl("tanque_luz_%d" % sg, 0.061, 0.04, (t[0] + sg * 0.075, t[1] - 0.06, t[2] + 0.05), bone="chest", mat="vidrio_verde", verts=18, bevel=0))
            H.attach(cable("manguera_%d" % sg, [(t[0] + sg * 0.075, t[1] - 0.06, t[2] + 0.22), (sg * 0.12, 0.0, 1.5), (v[0] + sg * 0.06, v[1] + 0.05, v[2] - 0.1)], 0.012, mat="goma_negra"))
        e = H.at((0, 0.2, 1.25))
        H.attach(label("bio", "BIO-7", (e[0], e[1] + 0.06, e[2]), (90, 0, 180), size=0.05, depth=0.003, bone="chest", mat="metal_oscuro"))
    elif aid == "anclaje":
        # Ancla gravitacional: acero violeta, botas enormes y núcleos de gravedad
        H.plate("peto", torso, offset=0.05, thick=0.015, mat="acero_violeta", trim="metal", trim_r=0.008, glow="violeta", fn=front, flutes=(4.0, 0.008, 0), smooth=4)
        H.plate("espaldar", torso, offset=0.048, thick=0.014, mat="acero_violeta", trim="metal", trim_r=0.008, fn=back, smooth=4)
        H.lames("escarcela", H.band("torso", 0.8, 1.0), 0.8, 1.0, 3, offset=0.055, step=0.01, thick=0.01, mat="acero_violeta", trim="metal", trim_r=0.005, glow="violeta", smooth=3)
        plates_limbs(H, "acero_violeta", "metal", "violeta", heavy=1.4)
        helm(H, "acero_violeta", "metal", "violeta", offset=0.034)
        for s_, sg in (("r", 1), ("l", -1)):
            f = H.at((sg * 0.1, 0.05, 0.1))
            H.attach(box("bota_grav_" + s_, (0.15, 0.3, 0.12), (f[0], f[1] + 0.02, f[2] - 0.02), bone="shin_" + s_, mat="acero_violeta", bevel=0.03))
            H.attach(cyl("nucleo_pie_" + s_, 0.035, 0.02, (f[0] + sg * 0.08, f[1], f[2]), (0, 90, 0), bone="shin_" + s_, mat="violeta", verts=16))
        q = H.at((0, 0.2, 1.2))
        H.attach(cyl("ancla_aro", 0.06, 0.02, (q[0], q[1] + 0.06, q[2] + 0.06), (90, 0, 0), bone="chest", mat="metal", verts=20))
        H.attach(box("ancla_asta", (0.02, 0.015, 0.16), (q[0], q[1] + 0.065, q[2] - 0.02), bone="chest", mat="metal", bevel=0.004))
        H.attach(cyl("ancla_brazo", 0.012, 0.16, (q[0], q[1] + 0.065, q[2] - 0.09), (0, 90, 0), bone="chest", mat="metal", verts=10))
        for k in range(10):
            a = k / 10 * math.tau
            p = H.at((math.sin(a) * 0.19, math.cos(a) * 0.15, 0.93))
            H.attach(sphere("cadena_%d" % k, 0.016, p, (1, 1, 0.6), bone="pelvis", mat="metal", segs=8))
    else:  # rector
        # Rector Caído: caballero negro y oro con grabados, tabardo vino y corona en el yelmo
        H.plate("peto", torso, offset=0.04, thick=0.013, mat="acero_rector", trim="oro", trim_r=0.008, glow="naranja", fn=front, flutes=(9.0, 0.005, 0), smooth=4)
        H.plate("espaldar", torso, offset=0.038, thick=0.012, mat="acero_rector", trim="oro", trim_r=0.008, fn=back, smooth=4)
        H.lames("gola", H.band("neck", 1.36, 1.46), 1.36, 1.46, 2, offset=0.03, step=0.007, thick=0.007, mat="acero_rector", trim="oro", trim_r=0.004, smooth=3)
        H.lames("escarcela", H.band("torso", 0.82, 1.0), 0.82, 1.0, 3, offset=0.045, step=0.01, thick=0.009, mat="acero_rector", trim="oro", trim_r=0.005, smooth=3)
        plates_limbs(H, "acero_rector", "oro", "naranja", heavy=1.2, trim_r=0.007)
        helm(H, "acero_rector", "oro", "naranja", offset=0.03)
        for k in range(7):
            a = -0.9 + k * 0.3
            b = H.at((math.sin(a) * 0.13, math.cos(a) * 0.12, 1.72))
            h = 0.08 if k == 3 else 0.05
            H.attach(cyl("pua_corona_%d" % k, 0.012, h, (b[0], b[1], b[2] + h * 0.5), bone="head", mat="oro", verts=6, r2=0.0, bevel=0))
        H.strap("tabardo", (0, 0.13, 1.05), (0, 0.13, 0.45), 0.17, region=None, offset=0.07, mat="tela_vino", fn=lambda p, n: p.y > 0.0 and abs(p.x) < 0.1)
        e = H.at((0, 0.17, 0.8))
        H.attach(cyl("escudo_tabardo", 0.05, 0.006, (e[0], e[1] + 0.07, e[2]), (90, 0, 0), bone="pelvis", mat="oro", verts=24))
        capa = {k: v for k, v in H.region("torso").items() if H.base_co[k].y < -0.03 and H.base_co[k].z > 1.1}
        H.piece("capa", capa, offset=0.07, mat="tela_vino", thresh=0.3, smooth=3, noise=0.004, extrude=(0.85, 0.3), tatter=(0.2, 0.2))
        for sg in (-1, 1):
            b = H.at((sg * 0.2, 0.0, 1.47))
            H.attach(sphere("broche_%d" % sg, 0.03, b, (1, 1, 0.6), bone="chest", mat="oro", segs=12))


# ---------------------------------------------------------------- mercader

def rect_glasses(H):
    """Lentes rectangulares de armazón grueso negro (como en la foto)."""
    for sg in (-1, 1):
        c = Vector(H.at((sg * 0.035, 0.146, 1.568)))
        w, h, r = 0.026, 0.017, 0.006
        pts = []
        for cx, cz, a0 in ((w - r, h - r, 0), (-w + r, h - r, 90), (-w + r, -h + r, 180), (w - r, -h + r, 270)):
            for k in range(4):
                a = math.radians(a0 + k * 30)
                pts.append(c + Vector((cx + math.cos(a) * r, 0.0, cz + math.sin(a) * r)))
        H._tube("lente_aro_%d" % sg, pts, 0.0034, "armazon", cyclic=True, relax=0)
        t0 = c + Vector((sg * 0.027, -0.002, 0.012))
        t1 = Vector(H.at((sg * 0.078, 0.06, 1.578)))
        t2 = Vector(H.at((sg * 0.08, 0.0, 1.56)))
        H._tube("patilla_%d" % sg, [t0, t0.lerp(t1, 0.5), t1, t2], 0.0028, "armazon", relax=0)
    b0 = Vector(H.at((-0.009, 0.15, 1.575)))
    b1 = Vector(H.at((0.009, 0.15, 1.575)))
    H._tube("puente", [b0, (b0 + b1) / 2 + Vector((0, 0.003, 0.003)), b1], 0.003, "armazon", relax=0)


def straight_hair(H):
    """Pelo negro lacio y abundante, con fleco que cae sobre la frente hacia un lado."""
    import random
    rng = random.Random(5)
    H.hair("pelo_base", "scalp", mat="pelo_lacio", offset=0.03, noise=0.004, smooth=3)
    # Fleco: mechones desde la línea del pelo hasta casi las cejas, peinados hacia la derecha
    for k in range(24):
        x = -0.072 + k * 0.0062 + rng.uniform(-0.003, 0.003)
        top = (x, 0.1, 1.69)
        mid = (x + 0.012, 0.15, 1.645)
        end = (x + 0.022 + rng.uniform(-0.004, 0.006), 0.162, 1.605 + rng.uniform(-0.008, 0.01))
        pts = [Vector(H.at(top)), Vector(H.at(mid)) + Vector((0, 0.012, 0)), Vector(H.at(end)) + Vector((0, 0.012, 0))]
        H.attach(limb("fleco_%d" % k, pts, [0.009, 0.0065, 0.002], mat="pelo_lacio", verts=6))
    # Mechones peinados hacia atrás y a los lados, pegados al cráneo (volumen sin picos):
    # salen de vértices reales del cuero cabelludo y siguen su superficie
    vs = H.body.data.vertices
    scalp = [k for k, w in H.region("scalp").items() if w > 0.6 and H.base_co[k].z > 1.62 and H.base_co[k].y < 0.08]
    for k in range(40):
        v = vs[scalp[rng.randrange(len(scalp))]]
        nrm = v.normal.normalized()
        d = Vector((rng.uniform(-0.3, 0.3) + v.co.x * 4.0, -0.8, -0.35))
        d = (d - nrm * d.dot(nrm)).normalized()
        p0 = v.co + nrm * 0.03
        p1 = p0 + d * rng.uniform(0.04, 0.065) - nrm * 0.006
        H.attach(limb("mechon_%d" % k, [p0, p0.lerp(p1, 0.5) + nrm * 0.004, p1], [0.014, 0.011, 0.004], mat="pelo_lacio", verts=6))
    for sg in (-1, 1):
        for k in range(8):
            z = 1.6 - k * 0.012
            p0 = Vector(H.at((sg * 0.085, 0.02 - k * 0.012, 1.66)))
            p1 = Vector(H.at((sg * 0.092, 0.03 - k * 0.012, z - 0.03)))
            H.attach(limb("patilla_pelo_%d_%d" % (sg, k), [p0, p0.lerp(p1, 0.5) + Vector((sg * 0.006, 0, 0)), p1], [0.01, 0.008, 0.003], mat="pelo_lacio", verts=6))


def mercader():
    """Mercader del campus, como la foto de referencia: joven robusto de cara redonda, piel
    morena clara, pelo negro lacio con fleco, lentes rectangulares de armazón negro grueso,
    playera azul marino, chamarra rompevientos gris-beige larga y abierta con capucha,
    mezclilla clara, audífonos negros colgando del cuello y gafete con listón rojo."""
    bk.reset(seed=4242)
    bk.define_materials(MATS)
    H = body(mercader=True)
    # Playera azul marino de manga corta
    camisa = {}
    for rg in ("torso", "arms", "neck"):
        for k, v in H.region(rg).items():
            p = H.base_co[k]
            if p.z < 0.84 or (rg == "neck" and p.z > 1.43) or (rg == "arms" and p.z < 1.18):
                continue
            camisa[k] = max(camisa.get(k, 0.0), v)
    H.piece("playera", camisa, offset=0.016, mat="playera_marino", thresh=0.3, smooth=8)
    pant = {}
    for rg in ("legs", "torso"):
        for k, v in H.region(rg).items():
            if 0.1 < H.base_co[k].z < 0.97:
                pant[k] = max(pant.get(k, 0.0), v)
    H.piece("mezclilla", pant, offset=0.03, mat="mezclilla", thresh=0.3, smooth=10, noise=0.003)
    H.piece("tenis", "feet", offset=0.022, mat="tenis", thresh=0.2, smooth=12, thick=0.006)
    # Chamarra larga abierta (hasta medio muslo), mangas completas
    ch = {}
    for rg in ("torso", "arms", "neck"):
        for k, v in H.region(rg).items():
            p = H.base_co[k]
            if p.z < 0.84 or (rg == "arms" and p.z < 0.9) or (rg == "neck" and p.z > 1.47):
                continue
            if abs(p.x) < 0.085 and p.y > 0.02 and p.z < 1.4:
                continue
            ch[k] = max(ch.get(k, 0.0), v)
    H.piece("chamarra", ch, offset=0.04, mat="chamarra", thresh=0.3, smooth=9, noise=0.004, extrude=(0.3, 0.1))
    for sg in (-1, 1):
        gold_line(H, "cierre_%d" % sg, [(sg * 0.088, 0.15, 1.39), (sg * 0.092, 0.165, 1.2), (sg * 0.1, 0.16, 0.98), (sg * 0.12, 0.17, 0.62)], 0.006, mat="plastico_negro")
        pk = H.at((sg * 0.13, 0.13, 0.86))
        H.attach(box("bolsa_%d" % sg, (0.13, 0.012, 0.02), (pk[0], pk[1] + 0.05, pk[2]), (0, 0, sg * -20), bone="pelvis", mat="plastico_negro", bevel=0.004))
    # Capucha caída en la espalda
    c = H.at((0, -0.12, 1.42))
    H.attach(bk.blob("capucha", 0.1, (c[0], c[1] - 0.05, c[2]), (1.5, 0.6, 0.7), bone="chest", mat="chamarra", lumps=0.12))
    H.hair("cejas", "brows", mat="pelo_lacio", offset=0.003, noise=0.0015)
    straight_hair(H)
    rect_glasses(H)
    # Audífonos negros colgando del cuello (diadema por detrás, copas en las clavículas)
    cups = []
    for sg in (-1, 1):
        q = Vector(H.at((sg * 0.085, 0.08, 1.38)))
        cups.append(q)
        H.attach(cyl("copa_%d" % sg, 0.045, 0.03, (q[0], q[1] + 0.03, q[2] + 0.02), (60, 0, sg * 35), bone="chest", mat="plastico_negro", verts=20, bevel=0.01))
        H.attach(cyl("cojin_%d" % sg, 0.038, 0.018, (q[0] - sg * 0.006, q[1] + 0.012, q[2] + 0.03), (60, 0, sg * 35), bone="chest", mat="tenis", verts=20, bevel=0.006))
    back = Vector(H.at((0, -0.08, 1.45)))
    H.attach(cable("diadema", [cups[0] + Vector((0, 0.01, 0.05)), Vector(H.at((-0.09, -0.03, 1.45))), back, Vector(H.at((0.09, -0.03, 1.45))), cups[1] + Vector((0, 0.01, 0.05))], 0.009, mat="plastico_negro"))
    # Gafete con listón rojo
    g = Vector(H.at((0, 0.17, 1.06)))
    for sg in (-1, 1):
        H.attach(cable("liston_%d" % sg, [Vector(H.at((sg * 0.06, 0.02, 1.43))), Vector(H.at((sg * 0.05, 0.14, 1.3))), g + Vector((sg * 0.006, 0.03, 0.08))], 0.006, mat="liston_rojo"))
    H.attach(box("gafete", (0.075, 0.004, 0.105), (g[0], g[1] + 0.035, g[2]), bone="chest", mat="gafete", bevel=0.003))
    H.attach(label("gafete_txt", "MERCADER", (g[0], g[1] + 0.038, g[2] + 0.02), (90, 0, 180), size=0.012, depth=0.0005, bone="chest", mat="plastico_negro"))
    for i in range(5):
        for j in range(5):
            if (i * 3 + j * 7) % 3 != 0:
                H.attach(box("qr_%d_%d" % (i, j), (0.004, 0.0008, 0.004), (g[0] + 0.012 + i * 0.004, g[1] + 0.0375, g[2] - 0.035 + j * 0.004), bone="chest", mat="plastico_negro", bevel=0))
    for i, col in enumerate(("cian", "naranja", "verde")):
        H.attach(box("hex_%d" % i, (0.008, 0.0008, 0.008), (g[0] - 0.025 + i * 0.01, g[1] + 0.0375, g[2] - 0.03), bone="chest", mat=col, bevel=0))
    name = "mercader"
    bk.finish(name, tex_size=int(os.environ.get("TEX", "2048")), bake=True, out_dir=OUT)
    if PREVIEW:
        bk.set_pose({})
        bk.render_preview(os.path.join(OUT, "preview_mercader.png"), (1.6, 3.8, 1.5), (0, 0, 1.0), size=(800, 1000))
        bk.render_preview(os.path.join(OUT, "preview_mercader_cara.png"), (0.25, 0.75, 1.62), (0, 0.03, 1.55), size=(800, 800))
    bk.export(os.path.join(OUT, name + ".glb"), actions=False)


ARMADURAS = ("ignifuga", "aislante", "antiveneno", "anclaje", "rector")


def build(cls):
    bk.reset(seed=900 + hash(cls) % 100)
    bk.define_materials(MATS)
    H = body()
    aid = cls[len("armadura_"):] if cls.startswith("armadura_") else ""
    helmeted = cls in ("cyber", "backend") or aid in ("ignifuga", "aislante", "anclaje", "rector")
    hooded = cls == "frontend" or aid == "antiveneno"
    clothes(H, hair=not (helmeted or hooded))
    torso = H.band("torso", 1.0, 1.42)
    if aid:
        armadura(aid, H, torso)

    if aid:
        pass
    elif cls == "cyber":
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
        archimago(H, torso)
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

    name = cls if aid else "jugador_" + cls
    bk.finish(name, tex_size=int(os.environ.get("TEX", "2048" if aid else "4096")), bake=True, out_dir=OUT)
    if PREVIEW:
        bk.set_pose({})
        bk.render_preview(os.path.join(OUT, "preview_%s.png" % name), (1.6, 3.8, 1.5), (0, 0, 1.0), size=(800, 1000))
        bk.render_preview(os.path.join(OUT, "preview_%s_atras.png" % name), (-1.6, -3.6, 1.6), (0, 0, 1.0), size=(800, 1000))
        bk.render_preview(os.path.join(OUT, "preview_%s_cara.png" % name), (0.25, 0.75, 1.62), (0, 0.03, 1.55), size=(800, 800))
    bk.export(os.path.join(OUT, name + ".glb"), actions=False)


for c in ("cyber", "backend", "frontend", "ai", "data") + tuple("armadura_" + a for a in ARMADURAS):
    if not ONLY or c in ONLY:
        build(c)
if not ONLY or "mercader" in ONLY:
    mercader()
print("LISTO", OUT)
