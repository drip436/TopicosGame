"""Utilería de las arenas de los jefes, con desgaste horneado (como robots y armas).

  Laboratorio de Biogenética (Dr. Kessler y mutantes):
      barril_toxico, barril_azul, barril_oxidado, tanque_quimico, caja_biopeligro,
      mesa_lab, camilla
  Centro de Cómputo (ADA-7):
      rack_servidor, escritorio_pc, silla_oficina, pc_vieja, bobina_cable
  Biblioteca Central (Bibliófilo):
      mesa_lectura, fichero, carrito_libros, globo, atril
  Plaza (Catedrático de Hierro):
      pupitre, pizarron
  Aula Magna (Rector Eterno):
      butacas, podio, estandarte, candelabro
  Calles y arenas:
      auto_rojo, auto_gris, auto_azul, auto_quemado, autobus_amarillo, autobus_quemado
      (estos van a lo largo de X con el frente hacia +X)

Cada pieza tiene el origen en el piso, al centro, y el frente hacia +Y (en Godot queda
mirando a -Z). Salida: modelos/utileria/<nombre>.glb (+ texturas horneadas).

Uso:  blender -b --python arte/blender/utileria.py -- <carpeta_salida> [preview] [nombre ...]
"""
import sys
import os
import math
import random

import bpy
import bmesh

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, sphere, panel, bolts, cable, label, hazard, cloth, blob, limb

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/utileria")
PREVIEW = "preview" in argv
ONLY = [a for a in argv[1:] if a != "preview"]
os.makedirs(OUT, exist_ok=True)
R = random.Random(11)

MATS = {
    "metal": dict(base=(0.55, 0.56, 0.58), metal=1.0, rough=0.35, rust=0.5, wear=0.3, dirt=0.5, bare=(0.8, 0.8, 0.82)),
    "metal_oscuro": dict(base=(0.07, 0.075, 0.08), metal=0.7, rough=0.45, rust=0.45, wear=0.6, dirt=0.5, bare=(0.42, 0.42, 0.44)),
    "inox": dict(base=(0.66, 0.67, 0.69), metal=1.0, rough=0.22, rust=0.12, wear=0.2, dirt=0.35, bare=(0.85, 0.85, 0.87)),
    "goma": dict(base=(0.025, 0.025, 0.025), rough=0.85, rust=0.0, wear=0.15, dirt=0.3, scratches=False),
    "peligro": dict(base=(0.9, 0.68, 0.06), rough=0.55, rust=0.4, wear=0.8, dirt=0.55, bare=(0.18, 0.18, 0.18)),
    "acento": dict(base=(0.05, 0.05, 0.05), rough=0.6, rust=0.0, wear=0.2, dirt=0.2, scratches=False),
    "letra_blanca": dict(base=(0.8, 0.8, 0.76), rough=0.6, rust=0.0, wear=0.4, dirt=0.4, scratches=False),
    "pintura_amarilla": dict(base=(0.78, 0.48, 0.02), rough=0.5, rust=0.85, wear=0.8, dirt=0.7, bare=(0.3, 0.3, 0.32), streaks=0.8),
    "pintura_azul": dict(base=(0.05, 0.17, 0.45), rough=0.45, rust=0.5, wear=0.6, dirt=0.65, bare=(0.3, 0.3, 0.32), streaks=0.5),
    "oxido": dict(base=(0.2, 0.08, 0.03), metal=0.3, rough=0.85, rust=1.4, wear=0.4, dirt=0.7, bare=(0.3, 0.27, 0.25), streaks=1.0, soot=0.5),
    "pintura_blanca": dict(base=(0.75, 0.76, 0.74), rough=0.45, rust=0.5, wear=0.5, dirt=0.7, bare=(0.4, 0.4, 0.42), streaks=0.6),
    "pintura_verde": dict(base=(0.12, 0.3, 0.2), rough=0.5, rust=0.6, wear=0.7, dirt=0.6, bare=(0.35, 0.35, 0.37), streaks=0.4),
    "plastico_naranja": dict(base=(0.85, 0.3, 0.05), rough=0.5, rust=0.0, wear=0.3, dirt=0.7, bare=(0.6, 0.25, 0.08)),
    "plastico_beige": dict(base=(0.66, 0.61, 0.5), rough=0.5, rust=0.0, wear=0.25, dirt=0.75, bare=(0.55, 0.52, 0.45)),
    "plastico_negro": dict(base=(0.035, 0.035, 0.04), rough=0.4, rust=0.0, wear=0.35, dirt=0.4, bare=(0.15, 0.15, 0.16)),
    "plastico_gris": dict(base=(0.25, 0.26, 0.28), rough=0.45, rust=0.0, wear=0.3, dirt=0.5, bare=(0.4, 0.4, 0.42)),
    "epoxi": dict(base=(0.03, 0.035, 0.035), rough=0.25, rust=0.0, wear=0.5, dirt=0.4, bare=(0.12, 0.12, 0.12)),
    "laminado": dict(base=(0.5, 0.42, 0.32), rough=0.4, rust=0.0, wear=0.5, dirt=0.6, bare=(0.35, 0.3, 0.25), streaks=0.3),
    "madera": dict(base=(0.26, 0.13, 0.055), rough=0.5, rust=0.0, wear=0.6, dirt=0.6, bare=(0.4, 0.24, 0.12), streaks=0.6, engrave=0.0),
    "madera_tallada": dict(base=(0.2, 0.1, 0.045), rough=0.45, rust=0.0, wear=0.6, dirt=0.6, bare=(0.38, 0.22, 0.1), engrave=0.6, engrave_scale=14.0),
    "laton": dict(base=(0.62, 0.45, 0.18), metal=1.0, rough=0.3, rust=0.6, wear=0.3, dirt=0.6, bare=(0.85, 0.7, 0.4), engrave=0.3),
    "oro": dict(base=(0.75, 0.55, 0.2), metal=1.0, rough=0.25, rust=0.3, wear=0.3, dirt=0.4, bare=(0.95, 0.8, 0.45), engrave=0.6),
    "tela_negra": dict(base=(0.04, 0.04, 0.045), rough=0.9, rust=0.0, wear=0.2, dirt=0.5, scratches=False),
    "terciopelo": dict(base=(0.3, 0.025, 0.03), rough=0.95, rust=0.0, wear=0.4, dirt=0.6, bare=(0.18, 0.05, 0.05), scratches=False),
    "tela_vino": dict(base=(0.13, 0.008, 0.015), rough=0.9, rust=0.0, wear=0.3, dirt=0.6, bare=(0.2, 0.05, 0.05), scratches=False, soot=0.4),
    "sabana": dict(base=(0.72, 0.72, 0.68), rough=0.9, rust=0.3, wear=0.2, dirt=0.9, bare=(0.6, 0.6, 0.55), scratches=False, streaks=0.4),
    "colchon": dict(base=(0.1, 0.22, 0.25), rough=0.6, rust=0.0, wear=0.3, dirt=0.7, scratches=False),
    "papel": dict(base=(0.75, 0.71, 0.6), rough=0.9, rust=0.2, wear=0.1, dirt=0.6, scratches=False),
    "tapa_roja": dict(base=(0.35, 0.05, 0.03), rough=0.7, rust=0.0, wear=0.6, dirt=0.5, bare=(0.5, 0.35, 0.2)),
    "tapa_azul": dict(base=(0.05, 0.08, 0.25), rough=0.7, rust=0.0, wear=0.6, dirt=0.5, bare=(0.5, 0.35, 0.2)),
    "tapa_verde": dict(base=(0.05, 0.18, 0.08), rough=0.7, rust=0.0, wear=0.6, dirt=0.5, bare=(0.5, 0.35, 0.2)),
    "tapa_cafe": dict(base=(0.25, 0.13, 0.05), rough=0.7, rust=0.0, wear=0.6, dirt=0.5, bare=(0.5, 0.35, 0.2)),
    "pizarra": dict(base=(0.04, 0.12, 0.08), rough=0.85, rust=0.0, wear=0.2, dirt=0.4, scratches=True, bare=(0.3, 0.35, 0.32)),
    "tiza": dict(base=(0.8, 0.8, 0.75), rough=0.95, rust=0.0, wear=0.0, dirt=0.1, scratches=False),
    "mapa": dict(base=(0.16, 0.3, 0.28), rough=0.4, rust=0.0, wear=0.3, dirt=0.6, bare=(0.55, 0.45, 0.25), engrave=0.8, engrave_scale=5.0),
    "cera": dict(base=(0.75, 0.7, 0.58), rough=0.6, rust=0.0, wear=0.0, dirt=0.5, scratches=False, streaks=0.3),
    "cable_naranja": dict(base=(0.7, 0.25, 0.04), rough=0.5, rust=0.0, wear=0.2, dirt=0.6, scratches=False),
    "auto_rojo": dict(base=(0.32, 0.03, 0.025), metal=0.6, rough=0.28, rust=0.5, wear=0.4, dirt=0.75, bare=(0.35, 0.35, 0.37), streaks=0.4),
    "auto_gris": dict(base=(0.32, 0.33, 0.34), metal=0.7, rough=0.28, rust=0.5, wear=0.4, dirt=0.75, bare=(0.4, 0.4, 0.42), streaks=0.4),
    "auto_azul": dict(base=(0.03, 0.07, 0.16), metal=0.6, rough=0.28, rust=0.5, wear=0.4, dirt=0.75, bare=(0.35, 0.35, 0.37), streaks=0.4),
    "auto_amarillo": dict(base=(0.7, 0.45, 0.03), metal=0.3, rough=0.35, rust=0.7, wear=0.5, dirt=0.8, bare=(0.35, 0.35, 0.37), streaks=0.7),
    "quemado": dict(base=(0.035, 0.03, 0.028), metal=0.4, rough=0.8, rust=0.55, wear=0.25, dirt=0.9, bare=(0.12, 0.1, 0.09), streaks=0.5, soot=1.0),
    "tela_gris": dict(base=(0.16, 0.16, 0.17), rough=0.9, rust=0.0, wear=0.2, dirt=0.6, scratches=False),
}

EMITS = {
    "toxina": {"emit": (0.3, 0.95, 0.12), "strength": 1.8},
    "toxina_morada": {"emit": (0.7, 0.2, 1.0), "strength": 3.0},
    "pantalla": {"emit": (0.15, 0.55, 0.85), "strength": 1.6},
    "pantalla_verde": {"emit": (0.2, 0.9, 0.4), "strength": 1.4},
    "pantalla_roja": {"emit": (1.0, 0.12, 0.08), "strength": 1.6},
    "led_verde": {"emit": (0.1, 1.0, 0.3), "strength": 6.0},
    "led_azul": {"emit": (0.15, 0.6, 1.0), "strength": 6.0},
    "led_ambar": {"emit": (1.0, 0.55, 0.05), "strength": 6.0},
    "led_rojo": {"emit": (1.0, 0.08, 0.05), "strength": 6.0},
    "foco": {"emit": (1.0, 0.78, 0.45), "strength": 8.0},
    "llama": {"emit": (1.0, 0.6, 0.2), "strength": 12.0},
    "pantalla_apagada": {"flat": (0.012, 0.014, 0.016), "rough": 0.08},
    "vidrio_auto": {"flat": (0.015, 0.018, 0.02), "rough": 0.06},
    "calavera": {"flat": (0.35, 0.02, 0.02), "rough": 0.3},
}


def vidrio(name, color, alpha=0.25, rough=0.05):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = tuple(color) + (1,)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Alpha"].default_value = alpha
    try:
        m.surface_render_method = "BLENDED"
    except Exception:
        m.blend_method = "BLEND"
    m["no_bake"] = True
    bk.MATS[name] = m


def start(seed=5):
    global R
    bk.reset(seed=seed)
    R = random.Random(seed * 7 + 1)
    spec = dict(MATS)
    spec.update(EMITS)
    bk.define_materials(spec)
    vidrio("vidrio", (0.75, 0.85, 0.82), 0.22)
    vidrio("vidrio_verde", (0.1, 0.45, 0.2), 0.75, 0.15)
    vidrio("vidrio_ambar", (0.45, 0.2, 0.04), 0.7, 0.1)


def finish(name, cam, target, tex=1024):
    bk.finish(name, tex_size=tex, bake=True, out_dir=OUT)
    if PREVIEW:
        bk.render_preview(os.path.join(OUT, "preview_%s.png" % name), cam, target, size=(640, 640))
    bk.export(os.path.join(OUT, name + ".glb"), actions=False)
    print("LISTO", name)


# ------------------------------------------------------------------ piezas propias

def drum(name, r, h, loc, mat, dents=4, open_top=False, segs=32):
    """Tambor con abolladuras (malla con anillos para poder deformarla)."""
    bm = bmesh.new()
    rings = 12
    vs = []
    for j in range(rings + 1):
        z = -h / 2 + h * j / rings
        row = [bm.verts.new((math.cos(2 * math.pi * i / segs) * r, math.sin(2 * math.pi * i / segs) * r, z)) for i in range(segs)]
        vs.append(row)
    for j in range(rings):
        for i in range(segs):
            bm.faces.new((vs[j][i], vs[j][(i + 1) % segs], vs[j + 1][(i + 1) % segs], vs[j + 1][i]))
    bm.faces.new(list(reversed(vs[0])))
    if not open_top:
        bm.faces.new(vs[rings])
    for _ in range(dents):
        a = R.uniform(0, 2 * math.pi)
        zc = R.uniform(-h * 0.35, h * 0.35)
        d = R.uniform(0.015, 0.045)
        rad = R.uniform(0.08, 0.16)
        for row in vs[1:-1]:
            for v in row:
                ang = math.atan2(v.co.y, v.co.x)
                da = (ang - a + math.pi) % (2 * math.pi) - math.pi
                dist = math.hypot(da * r, v.co.z - zc)
                if dist < rad:
                    k = (1 - dist / rad) ** 2 * d
                    v.co.x -= math.cos(ang) * k
                    v.co.y -= math.sin(ang) * k
    ob = bk._obj_from_bm(name, bm)
    return bk._finish_part(ob, loc, (0, 0, 0), "root", mat, 0.004, 2)


def ring(name, R0, r, loc, rot=(0, 0, 0), mat="metal", seg=32, minor=8, arc=1.0):
    """Toro (o arco si arc < 1) alrededor de Z."""
    bm = bmesh.new()
    n = seg + (1 if arc < 1 else 0)
    vs = []
    for i in range(n):
        a = 2 * math.pi * arc * i / seg
        c, s = math.cos(a), math.sin(a)
        row = []
        for k in range(minor):
            b = 2 * math.pi * k / minor
            rr = R0 + math.cos(b) * r
            row.append(bm.verts.new((c * rr, s * rr, math.sin(b) * r)))
        vs.append(row)
    for i in range(seg if arc >= 1 else n - 1):
        a, b2 = vs[i], vs[(i + 1) % n]
        for k in range(minor):
            bm.faces.new((a[k], a[(k + 1) % minor], b2[(k + 1) % minor], b2[k]))
    ob = bk._obj_from_bm(name, bm)
    return bk._finish_part(ob, loc, rot, "root", mat, 0, 0)


def tube(name, a, b, r, mat="metal", verts=12):
    """Cilindro entre dos puntos."""
    from mathutils import Vector
    a, b = Vector(a), Vector(b)
    d = b - a
    q = d.normalized().to_track_quat("Z", "Y")
    rot = [math.degrees(x) for x in q.to_euler()]
    return cyl(name, r, d.length, tuple((a + b) / 2), rot, mat=mat, verts=verts, bevel=0.0)


def wheel(name, loc, r=0.05, w=0.03, axis="x"):
    rot = (0, 90, 0) if axis == "x" else (90, 0, 0)
    cyl(name, r, w, loc, rot, mat="goma", verts=16, bevel=0.006)
    cyl(name + "_eje", r * 0.4, w * 1.1, loc, rot, mat="metal", verts=10, bevel=0.0)


def books_row(prefix, x0, x1, y, z, depth=0.22, hmin=0.18, hmax=0.3, lean=True):
    cols = ["tapa_roja", "tapa_azul", "tapa_verde", "tapa_cafe"]
    x = x0
    i = 0
    while x < x1 - 0.03:
        t = R.uniform(0.025, 0.06)
        h = R.uniform(hmin, hmax)
        tilt = R.uniform(-4, 4) if lean else 0
        if R.random() < 0.08 and x + h < x1:
            # Libro acostado
            box("%s_%d" % (prefix, i), (h, depth * 0.95, t), (x + h / 2, y, z + t / 2), mat=R.choice(cols), bevel=0.003)
            x += h + 0.01
        else:
            box("%s_%d" % (prefix, i), (t, depth, h), (x + t / 2, y, z + h / 2), (0, tilt, 0), mat=R.choice(cols), bevel=0.003)
            x += t + 0.002
        i += 1


def escurrimiento(name, a, r, z0, L, mat="toxina"):
    """Hilo de líquido que escurre por la pared de un tambor: delgado, ondulado y con gota."""
    pts, rads = [], []
    n = 7
    for i in range(n):
        t = i / (n - 1)
        aa = a + math.sin(t * 5 + a * 9) * 0.03
        rr = r * (0.92 if i == 0 else 1.0) + 0.004
        pts.append((math.cos(aa) * rr, math.sin(aa) * rr, z0 + (0.02 if i == 0 else 0) - L * t))
        rads.append(0.009 if i == 0 else 0.004 + 0.003 * math.sin(t * 7 + a) ** 2)
    rads[-1] = 0.011
    limb(name, pts, rads, mat=mat, verts=8)
    sphere(name + "_gota", 0.011, pts[-1], (1, 1, 1.4), mat=mat, segs=8)


# ================================================================ LABORATORIO

def barril_toxico():
    start(3)
    drum("cuerpo", 0.29, 0.86, (0, 0, 0.45), "pintura_amarilla", dents=5)
    for z in (0.3, 0.6):
        ring("costilla_%d" % z, 0.292, 0.012, (0, 0, z), mat="pintura_amarilla", seg=40)
    for z in (0.02, 0.88):
        ring("borde_%d" % z, 0.287, 0.014, (0, 0, z), mat="metal", seg=40)
    cyl("tapa", 0.275, 0.012, (0, 0, 0.876), mat="pintura_amarilla", verts=32, bevel=0.002)
    for p in ((0.15, 0.08), (-0.16, -0.06)):
        cyl("tapon_%s" % p[0], 0.032, 0.022, (p[0], p[1], 0.888), mat="metal", verts=12)
    # Etiqueta: banda negra con letras
    cyl("banda", 0.2935, 0.17, (0, 0, 0.45), mat="acento", verts=40, bevel=0.0)
    label("txt1", "TOXICO", (0, 0.295, 0.47), (90, 0, 180), size=0.06, depth=0.003, mat="peligro")
    label("txt2", "BIOGENETICA UNIV.", (0, 0.295, 0.405), (90, 0, 180), size=0.025, depth=0.002, mat="letra_blanca")
    label("txt3", "TOXICO", (0, -0.295, 0.47), (90, 0, 0), size=0.06, depth=0.003, mat="peligro")
    # Toxina que se derrama por el tapón y escurre
    blob("charco_tapa", 0.06, (0.15, 0.08, 0.895), (1.6, 1.2, 0.25), mat="toxina", lumps=0.4)
    for k, a in enumerate((0.42, 0.58, 0.3, 0.7)):
        escurrimiento("escurre_%d" % k, a, 0.3, 0.88, R.uniform(0.15, 0.55))
    finish("barril_toxico", (1.4, 1.6, 1.1), (0, 0, 0.45))


def barril_azul():
    start(4)
    drum("cuerpo", 0.29, 0.88, (0, 0, 0.44), "pintura_azul", dents=3)
    for z in (0.3, 0.6):
        ring("costilla_%d" % z, 0.292, 0.012, (0, 0, z), mat="pintura_azul", seg=40)
    for z in (0.01, 0.88):
        ring("borde_%d" % z, 0.287, 0.014, (0, 0, z), mat="metal", seg=40)
    for p in ((0.14, 0.1), (-0.17, -0.02)):
        cyl("tapon_%s" % p[0], 0.032, 0.03, (p[0], p[1], 0.885), mat="plastico_negro", verts=12)
    # Rombo de peligro
    box("rombo", (0.16, 0.006, 0.16), (0, 0.29, 0.5), (0, 45, 0), mat="pintura_blanca", bevel=0.002)
    box("rombo_borde", (0.17, 0.004, 0.17), (0, 0.288, 0.5), (0, 45, 0), mat="led_rojo", bevel=0.001)
    label("txt", "QUIMICO", (0, 0.296, 0.62), (90, 0, 180), size=0.045, mat="letra_blanca")
    label("num", "UN 2810", (0, 0.296, 0.5), (90, 0, 180), size=0.03, mat="acento")
    blob("goteo", 0.05, (0.14, 0.1, 0.9), (1.4, 1.2, 0.3), mat="toxina_morada", lumps=0.4)
    finish("barril_azul", (1.4, 1.6, 1.1), (0, 0, 0.45))


def barril_oxidado():
    start(6)
    drum("cuerpo", 0.29, 0.86, (0, 0, 0.43), "oxido", dents=8, open_top=True)
    drum("interior", 0.278, 0.84, (0, 0, 0.43), "oxido", dents=0, open_top=True)
    for z in (0.3, 0.6):
        ring("costilla_%d" % z, 0.292, 0.013, (0, 0, z), mat="oxido", seg=40)
    ring("borde", 0.284, 0.014, (0, 0, 0.86), mat="oxido", seg=40)
    # Lodo tóxico casi al borde, con burbujas
    cyl("lodo", 0.276, 0.02, (0, 0, 0.74), mat="toxina", verts=32, bevel=0.0)
    for k in range(6):
        a = R.uniform(0, 6.28)
        rr = R.uniform(0, 0.2)
        sphere("burbuja_%d" % k, R.uniform(0.015, 0.04), (math.cos(a) * rr, math.sin(a) * rr, 0.75), (1, 1, 0.6), mat="toxina", segs=10)
    for k, a in enumerate((0.2, 0.35)):
        escurrimiento("chorreo_%d" % k, a, 0.302, 0.86, R.uniform(0.3, 0.7))
    finish("barril_oxidado", (1.4, 1.6, 1.3), (0, 0, 0.45))


def tanque_quimico():
    start(7)
    H0, H1, r = 0.55, 2.75, 0.68
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("pata_%d_%d" % (sx, sy), (0.09, 0.09, H0 + 0.1), (sx * 0.45, sy * 0.45, (H0 + 0.1) / 2), mat="metal_oscuro")
            box("zapata_%d_%d" % (sx, sy), (0.2, 0.2, 0.02), (sx * 0.45, sy * 0.45, 0.01), mat="metal_oscuro")
    box("cruceta_a", (1.0, 0.06, 0.06), (0, 0.45, 0.25), mat="metal_oscuro")
    box("cruceta_b", (1.0, 0.06, 0.06), (0, -0.45, 0.25), mat="metal_oscuro")
    cyl("tanque", r, H1 - H0, (0, 0, (H0 + H1) / 2), mat="pintura_blanca", verts=40, bevel=0.01)
    sphere("domo", r, (0, 0, H1), (1, 1, 0.35), mat="pintura_blanca", segs=32)
    sphere("fondo", r, (0, 0, H0), (1, 1, 0.25), mat="pintura_blanca", segs=32)
    for z in (H0 + 0.25, (H0 + H1) / 2, H1 - 0.25):
        ring("aro_%d" % int(z * 100), r + 0.008, 0.018, (0, 0, z), mat="metal", seg=48)
    # Banda de peligro
    cyl("banda", r + 0.004, 0.22, (0, 0, H1 - 0.55), mat="peligro", verts=40, bevel=0.0)
    for k in range(16):
        a = 2 * math.pi * k / 16
        box("franja_%d" % k, (0.09, 0.012, 0.2), (math.cos(a) * (r + 0.008), math.sin(a) * (r + 0.008), H1 - 0.55), (0, 35, math.degrees(a) + 90), mat="acento", bevel=0.0)
    label("txt", "MUTAGENO-7", (0, r + 0.012, 1.55), (90, 0, 180), size=0.13, depth=0.004, mat="acento")
    label("txt2", "NO ABRIR - RIESGO BIOLOGICO", (0, r + 0.012, 1.38), (90, 0, 180), size=0.045, depth=0.003, mat="pintura_verde")
    # Mirilla con el líquido verde
    tube("mirilla", (0.66, 0.24, H0 + 0.3), (0.66, 0.24, H1 - 0.3), 0.035, mat="toxina")
    for z in (H0 + 0.3, H1 - 0.3):
        tube("mirilla_codo_%d" % int(z * 10), (0.66, 0.24, z), (0.6, 0.2, z), 0.04, mat="metal")
    # Válvula y manómetro
    tube("tubo_salida", (0, 0.5, H0 + 0.1), (0, 1.0, H0 + 0.1), 0.06, mat="metal")
    tube("tubo_baja", (0, 1.0, H0 + 0.1), (0, 1.0, 0.0), 0.06, mat="metal")
    ring("volante", 0.13, 0.014, (0, 0.82, H0 + 0.3), mat="led_rojo", seg=24, minor=6)
    for k in range(3):
        a = k * math.pi * 2 / 3
        tube("rayo_%d" % k, (0, 0.82, H0 + 0.3), (math.cos(a) * 0.13, 0.82, H0 + 0.3 + math.sin(a) * 0.13), 0.01, mat="metal")
    tube("vastago", (0, 0.82, H0 + 0.1), (0, 0.82, H0 + 0.3), 0.02, mat="metal")
    cyl("manometro", 0.07, 0.04, (-0.4, r - 0.12, 2.0), (90, 0, -30), mat="metal", verts=20)
    cyl("manometro_cara", 0.06, 0.005, (-0.42, r - 0.08, 2.0), (90, 0, -30), mat="pintura_blanca", verts=20, bevel=0.0)
    # Escalera
    for sx in (-0.2, 0.2):
        tube("escalera_%s" % sx, (sx, -r - 0.12, 0.0), (sx, -r - 0.12, H1 + 0.2), 0.02, mat="metal_oscuro")
    for k in range(10):
        z = 0.3 + k * 0.28
        tube("peldano_%d" % k, (-0.2, -r - 0.12, z), (0.2, -r - 0.12, z), 0.015, mat="metal_oscuro")
    # Tuberías de la tapa
    cable("tuberia_1", [(0.2, 0.0, H1 + 0.2), (0.5, 0.3, H1 + 0.5), (1.0, 0.4, H1 + 0.4), (1.3, 0.4, H1 + 0.2)], radius=0.06, mat="metal", res=10)
    cable("tuberia_2", [(-0.25, 0.1, H1 + 0.18), (-0.5, 0.2, H1 + 0.6), (-0.6, 0.5, H1 + 0.9)], radius=0.04, mat="metal_oscuro", res=10)
    cyl("brida", 0.11, 0.05, (0.2, 0.0, H1 + 0.18), mat="metal", verts=16)
    bolts("pernos", [(math.cos(a) * 0.09 + 0.2, math.sin(a) * 0.09, H1 + 0.21) for a in [k * math.pi / 3 for k in range(6)]])
    finish("tanque_quimico", (3.6, 4.2, 2.6), (0, 0, 1.5), tex=2048)


def caja_biopeligro():
    start(8)
    box("caja", (0.62, 0.44, 0.36), (0, 0, 0.18), mat="plastico_naranja", bevel=0.02)
    box("tapa", (0.66, 0.48, 0.06), (0, 0, 0.39), mat="plastico_naranja", bevel=0.015)
    for x in (-0.2, 0, 0.2):
        box("costilla_%s" % x, (0.04, 0.46, 0.3), (x, 0, 0.17), mat="plastico_naranja", bevel=0.008)
    for x in (-0.24, 0.24):
        box("cierre_%s" % x, (0.06, 0.03, 0.08), (x, 0.235, 0.33), mat="metal", bevel=0.005)
    box("asa_a", (0.03, 0.12, 0.03), (-0.33, 0, 0.3), mat="plastico_negro", bevel=0.008)
    box("asa_b", (0.03, 0.12, 0.03), (0.33, 0, 0.3), mat="plastico_negro", bevel=0.008)
    box("sticker", (0.3, 0.004, 0.16), (0, 0.222, 0.2), mat="peligro", bevel=0.001)
    label("txt", "RIESGO BIOLOGICO", (0, 0.226, 0.22), (90, 0, 180), size=0.028, mat="acento")
    label("txt2", "MUESTRAS", (0, 0.226, 0.165), (90, 0, 180), size=0.035, mat="acento")
    label("txt3", "BIO", (0, 0, 0.422), (0, 0, 180), size=0.12, depth=0.004, mat="acento")
    finish("caja_biopeligro", (1.0, 1.1, 0.9), (0, 0, 0.2))


def flask(prefix, x, y, z, s=1.0, liquid="toxina"):
    cyl(prefix + "_vidrio", 0.07 * s, 0.13 * s, (x, y, z + 0.065 * s), mat="vidrio", verts=16, bevel=0.0, r2=0.022 * s)
    cyl(prefix + "_cuello", 0.02 * s, 0.07 * s, (x, y, z + 0.165 * s), mat="vidrio", verts=12, bevel=0.0)
    cyl(prefix + "_liq", 0.062 * s, 0.07 * s, (x, y, z + 0.037 * s), mat=liquid, verts=16, bevel=0.0, r2=0.04 * s)


def mesa_lab():
    start(9)
    box("cubierta", (2.0, 0.78, 0.04), (0, 0, 0.9), mat="epoxi", bevel=0.006)
    box("mueble", (1.96, 0.7, 0.84), (0, -0.02, 0.44), mat="pintura_blanca", bevel=0.01)
    box("zoclo", (1.9, 0.6, 0.08), (0, -0.04, 0.04), mat="plastico_negro", bevel=0.005)
    for i, x in enumerate((-0.73, -0.25, 0.25, 0.73)):
        panel("cajon_%d" % i, (0.44, 0.03, 0.18), (x, 0.34, 0.74), mat="pintura_blanca", inset=0.01)
        box("jalador_%d" % i, (0.14, 0.02, 0.015), (x, 0.365, 0.76), mat="inox", bevel=0.004)
        panel("puerta_%d" % i, (0.44, 0.03, 0.52), (x, 0.34, 0.37), mat="pintura_blanca", inset=0.012)
        box("jaladorp_%d" % i, (0.015, 0.02, 0.12), (x + 0.17, 0.365, 0.5), mat="inox", bevel=0.004)
    # Repisa de reactivos
    for x in (-0.95, 0.95):
        box("poste_%s" % x, (0.04, 0.04, 0.7), (x, -0.32, 1.27), mat="inox", bevel=0.005)
    box("repisa", (1.94, 0.22, 0.025), (0, -0.28, 1.4), mat="inox", bevel=0.004)
    box("repisa2", (1.94, 0.22, 0.025), (0, -0.28, 1.6), mat="inox", bevel=0.004)
    for k in range(12):
        x = -0.85 + k * 0.155 + R.uniform(-0.02, 0.02)
        h = R.uniform(0.1, 0.17)
        m = R.choice(["vidrio_ambar", "vidrio_ambar", "vidrio"])
        zz = 1.41 if k % 2 == 0 else 1.61
        cyl("frasco_%d" % k, 0.035, h, (x, -0.28, zz + h / 2), mat=m, verts=14, bevel=0.0)
        cyl("frasco_tapa_%d" % k, 0.022, 0.025, (x, -0.28, zz + h + 0.012), mat="plastico_negro", verts=10)
    # Matraces y vasos con líquidos
    flask("matraz1", -0.6, 0.1, 0.92)
    flask("matraz2", -0.4, 0.15, 0.92, 0.8, "toxina_morada")
    flask("matraz3", 0.55, 0.0, 0.92, 1.2)
    for k, (x, y) in enumerate(((-0.15, 0.2), (0.0, 0.05))):
        cyl("vaso_%d" % k, 0.05, 0.12, (x, y, 0.98), mat="vidrio", verts=16, bevel=0.0)
        cyl("vaso_liq_%d" % k, 0.046, 0.06, (x, y, 0.95), mat="toxina", verts=16, bevel=0.0)
    # Gradilla con tubos de ensayo
    box("gradilla", (0.3, 0.08, 0.02), (0.15, 0.25, 1.0), mat="plastico_gris", bevel=0.003)
    box("gradilla_b", (0.3, 0.08, 0.02), (0.15, 0.25, 0.93), mat="plastico_gris", bevel=0.003)
    for k in range(6):
        x = 0.03 + k * 0.048
        cyl("tubo_%d" % k, 0.012, 0.13, (x, 0.25, 1.0), mat="vidrio", verts=10, bevel=0.0)
        if k % 2 == 0 or k == 3:
            cyl("tubo_liq_%d" % k, 0.011, 0.06, (x, 0.25, 0.97), mat=["toxina", "toxina_morada", "led_rojo"][k % 3], verts=10, bevel=0.0)
    # Microscopio
    box("micro_base", (0.16, 0.2, 0.03), (0.85, 0.05, 0.935), mat="pintura_blanca", bevel=0.008)
    box("micro_brazo", (0.05, 0.05, 0.26), (0.85, -0.05, 1.07), (12, 0, 0), mat="pintura_blanca", bevel=0.01)
    box("micro_platina", (0.12, 0.12, 0.012), (0.85, 0.05, 1.02), mat="metal_oscuro", bevel=0.003)
    tube("micro_tubo", (0.85, 0.04, 1.08), (0.85, -0.02, 1.27), 0.022, mat="metal_oscuro")
    tube("micro_ocular", (0.85, -0.02, 1.27), (0.85, -0.08, 1.32), 0.016, mat="plastico_negro")
    # Papeles y una mancha
    for k in range(3):
        box("hoja_%d" % k, (0.21, 0.29, 0.002), (-0.85 + k * 0.12, 0.15, 0.921), (0, 0, R.uniform(-30, 30)), mat="papel", bevel=0.0)
    blob("derrame", 0.12, (-0.2, 0.25, 0.921), (1.6, 1.0, 0.03), mat="toxina", lumps=0.4)
    finish("mesa_lab", (2.0, 2.6, 2.0), (0, 0, 0.9), tex=2048)


def camilla():
    start(10)
    L, W, Z = 1.95, 0.66, 0.68
    for sx in (-1, 1):
        tube("larguero_%d" % sx, (-L / 2, sx * W / 2, Z), (L / 2, sx * W / 2, Z), 0.018, mat="inox")
        tube("larguero_b_%d" % sx, (-L / 2 + 0.1, sx * W / 2.3, 0.18), (L / 2 - 0.1, sx * W / 2.3, 0.18), 0.018, mat="inox")
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (L / 2 - 0.12), sy * W / 2.3
            tube("pata_%d_%d" % (sx, sy), (x, y, 0.1), (x, y * 1.1, Z), 0.02, mat="inox")
            cyl("horquilla_%d_%d" % (sx, sy), 0.02, 0.06, (x, y, 0.09), mat="metal_oscuro", verts=8)
            wheel("rueda_%d_%d" % (sx, sy), (x, y, 0.055), 0.055, 0.03, axis="y")
    box("base_colchon", (L, W, 0.03), (0, 0, Z + 0.015), mat="inox", bevel=0.005)
    box("colchon", (L - 0.05, W - 0.04, 0.1), (0, 0, Z + 0.08), mat="colchon", bevel=0.035, segs=3)
    box("respaldo", (0.6, W - 0.06, 0.08), (L / 2 - 0.38, 0, Z + 0.25), (0, -25, 0), mat="colchon", bevel=0.03, segs=3)
    cloth("sabana", 1.3, W - 0.02, (-0.25, -W / 2 + 0.01, Z + 0.142), (90, 0, 0), mat="sabana", nx=16, ny=8, tatter=0.0, holes=0.02, wave=0.012)
    cloth("sabana_cae", 1.3, 0.45, (-0.25, W / 2 - 0.0, Z + 0.142), (0, 0, 0), mat="sabana", nx=16, ny=8, tatter=0.3, holes=0.03, wave=0.02, flare=0.05)
    # Correas de sujeción (arrancadas)
    for k, x in enumerate((-0.5, 0.15, 0.6)):
        box("correa_%d" % k, (0.07, W + 0.04, 0.012), (x, 0, Z + 0.14), mat="tela_negra", bevel=0.003)
        box("hebilla_%d" % k, (0.05, 0.012, 0.06), (x, W / 2 + 0.03, Z + 0.1), mat="metal", bevel=0.003)
        box("correa_cuelga_%d" % k, (0.06, 0.008, 0.35), (x, -W / 2 - 0.03, Z - 0.05), (0, R.uniform(-15, 15), 0), mat="tela_negra", bevel=0.002)
    # Barandal y suero
    tube("barandal", (-0.6, W / 2 + 0.03, Z + 0.25), (0.6, W / 2 + 0.03, Z + 0.25), 0.012, mat="inox")
    for x in (-0.6, 0.6):
        tube("barandal_p_%s" % x, (x, W / 2 + 0.03, Z), (x, W / 2 + 0.03, Z + 0.25), 0.012, mat="inox")
    tube("poste_suero", (L / 2 - 0.05, -W / 2, Z), (L / 2 - 0.05, -W / 2, 1.95), 0.012, mat="inox")
    tube("gancho", (L / 2 - 0.15, -W / 2, 1.95), (L / 2 + 0.05, -W / 2, 1.95), 0.01, mat="inox")
    box("bolsa", (0.12, 0.04, 0.2), (L / 2 - 0.12, -W / 2, 1.82), mat="vidrio", bevel=0.02)
    box("bolsa_liq", (0.1, 0.03, 0.12), (L / 2 - 0.12, -W / 2, 1.78), mat="toxina", bevel=0.015)
    cable("venoclisis", [(L / 2 - 0.12, -W / 2, 1.7), (L / 2 - 0.2, -W / 2 + 0.1, 1.2), (0.6, 0.0, Z + 0.25)], radius=0.004, mat="vidrio", res=12)
    finish("camilla", (2.6, 2.6, 2.0), (0, 0, 0.8))


# ================================================================ CÓMPUTO

def rack_servidor():
    start(12)
    W, D, H = 0.8, 1.1, 2.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("poste_%d_%d" % (sx, sy), (0.05, 0.05, H), (sx * (W / 2 - 0.025), sy * (D / 2 - 0.025), H / 2), mat="metal_oscuro", bevel=0.004)
        panel("lateral_%d" % sx, (D - 0.06, 0.02, H - 0.12), (sx * (W / 2 - 0.01), 0, H / 2), (0, 0, 90), mat="metal_oscuro", inset=0.03)
        for k in range(6):
            box("rejilla_%d_%d" % (sx, k), (0.004, 0.5, 0.012), (sx * (W / 2 + 0.002), 0, 1.6 + k * 0.03), mat="acento", bevel=0.0)
    box("techo", (W, D, 0.06), (0, 0, H - 0.03), mat="metal_oscuro", bevel=0.006)
    box("piso", (W, D, 0.08), (0, 0, 0.04), mat="metal_oscuro", bevel=0.006)
    for k in range(12):
        box("techo_vent_%d" % k, (0.5, 0.012, 0.004), (0, -0.3 + k * 0.05, H + 0.001), mat="acento", bevel=0.0)
    # Servidores: unidades de 1U-4U con bahías, rejillas y LEDs
    z = 0.12
    u = 0.0445
    leds = ["led_verde", "led_verde", "led_verde", "led_azul", "led_ambar", "led_rojo"]
    k = 0
    while z < H - 0.2:
        n = R.choice([1, 1, 2, 2, 2, 3, 4])
        h = n * u
        if z + h > H - 0.15:
            break
        if R.random() < 0.1:
            z += h  # hueco vacío
            continue
        y = D / 2 - 0.06
        kind = R.random()
        box("srv_frente_%d" % k, (W - 0.1, 0.03, h - 0.006), (0, y, z + h / 2), mat="metal" if kind < 0.4 else "plastico_negro", bevel=0.002, segs=1)
        for e in (-1, 1):
            box("srv_asa_%d_%d" % (k, e), (0.018, 0.03, min(h - 0.01, 0.06)), (e * (W / 2 - 0.08), y + 0.02, z + h / 2), mat="inox", bevel=0.0)
        if n >= 2:
            # Bahías de disco
            nb = 8 if n == 2 else 12
            for b in range(nb):
                bx = -0.26 + b * (0.4 / nb)
                box("bahia_%d_%d" % (k, b), (0.4 / nb - 0.006, 0.012, h * 0.7), (bx + 0.02, y + 0.012, z + h * 0.5), mat="plastico_gris", bevel=0.0)
                if R.random() < 0.7:
                    box("bahia_led_%d_%d" % (k, b), (0.008, 0.006, 0.006), (bx + 0.03, y + 0.02, z + h * 0.82), mat=R.choice(leds), bevel=0.0)
        else:
            for v in range(10):
                box("ventila_%d_%d" % (k, v), (0.02, 0.008, h * 0.5), (-0.28 + v * 0.03, y + 0.012, z + h / 2), mat="acento", bevel=0.0)
        for l in range(R.randint(2, 4)):
            box("led_%d_%d" % (k, l), (0.01, 0.006, 0.006), (0.22 + l * 0.022, y + 0.013, z + h * 0.7), mat=R.choice(leds), bevel=0.0)
        z += h
        k += 1
    # Panel de parcheo con cables que cuelgan
    zp = H - 0.14
    box("parcheo", (W - 0.1, 0.03, 0.044), (0, D / 2 - 0.05, zp), mat="plastico_negro", bevel=0.003)
    cols = ["led_azul", "cable_naranja", "plastico_gris", "pintura_amarilla"]
    for c in range(9):
        x = -0.3 + c * 0.075
        drop = R.uniform(0.3, 1.2)
        cable("cable_%d" % c, [(x, D / 2 - 0.03, zp), (x + R.uniform(-0.05, 0.05), D / 2 + 0.08, zp - drop * 0.4), (x * 0.6 + R.uniform(-0.1, 0.1), D / 2 + 0.05, zp - drop)],
              radius=0.005, mat=R.choice(cols[1:]) if c % 3 else "cable_naranja", res=4)
    label("etq", "SRV-%02d" % R.randint(1, 40), (0, D / 2 - 0.02, H - 0.06), (90, 0, 180), size=0.035, mat="letra_blanca")
    finish("rack_servidor", (2.0, 3.2, 2.0), (0, 0, 1.1), tex=2048)


def monitor(prefix, x, y, z, yaw, mat_screen):
    from mathutils import Vector, Matrix
    rz = math.radians(yaw)

    def P(dx, dy, dz):
        return (x + dx * math.cos(rz) - dy * math.sin(rz), y + dx * math.sin(rz) + dy * math.cos(rz), z + dz)
    box(prefix + "_base", (0.22, 0.17, 0.015), P(0, -0.02, 0.008), (0, 0, yaw), mat="plastico_negro", bevel=0.006)
    box(prefix + "_cuello", (0.05, 0.03, 0.2), P(0, -0.05, 0.11), (0, 0, yaw), mat="plastico_negro", bevel=0.006)
    box(prefix + "_marco", (0.56, 0.035, 0.34), P(0, -0.02, 0.33), (0, 0, yaw), mat="plastico_negro", bevel=0.006)
    box(prefix + "_pantalla", (0.53, 0.004, 0.31), P(0, -0.002, 0.335), (0, 0, yaw), mat=mat_screen, bevel=0.0)


def escritorio_pc():
    start(13)
    box("cubierta", (1.6, 0.8, 0.035), (0, 0, 0.74), mat="laminado", bevel=0.004)
    box("canto", (1.6, 0.012, 0.035), (0, 0.405, 0.74), mat="plastico_negro", bevel=0.002)
    for sx in (-1, 1):
        box("pata_%d" % sx, (0.06, 0.7, 0.04), (sx * 0.74, 0, 0.02), mat="metal_oscuro", bevel=0.005)
        box("columna_%d" % sx, (0.06, 0.06, 0.7), (sx * 0.74, 0, 0.37), mat="metal_oscuro", bevel=0.005)
    panel("faldon", (1.4, 0.015, 0.35), (0, -0.33, 0.52), mat="metal_oscuro", inset=0.01)
    monitor("mon1", -0.33, -0.18, 0.758, 12, "pantalla")
    monitor("mon2", 0.33, -0.18, 0.758, -12, R.choice(["pantalla_roja", "pantalla_apagada"]))
    # Teclado con teclas
    box("teclado", (0.44, 0.15, 0.022), (0, 0.18, 0.769), (3, 0, 0), mat="plastico_negro", bevel=0.005)
    for r in range(4):
        for c in range(14):
            box("tecla_%d_%d" % (r, c), (0.024, 0.024, 0.01), (-0.195 + c * 0.03, 0.13 + r * 0.03, 0.783 - r * 0.0015), mat="plastico_gris", bevel=0.003)
    box("espacio", (0.17, 0.024, 0.01), (0, 0.24, 0.781), mat="plastico_gris", bevel=0.003)
    sphere("mouse", 0.035, (0.32, 0.2, 0.765), (0.75, 1.1, 0.45), mat="plastico_negro", segs=14)
    # Gabinete bajo el escritorio
    box("gabinete", (0.2, 0.46, 0.44), (0.55, 0.05, 0.24), mat="plastico_negro", bevel=0.008)
    panel("gab_frente", (0.19, 0.02, 0.42), (0.55, 0.285, 0.24), mat="metal_oscuro", inset=0.008)
    box("gab_boton", (0.025, 0.01, 0.025), (0.55, 0.3, 0.42), mat="led_azul", bevel=0.003)
    for k in range(8):
        box("gab_vent_%d" % k, (0.12, 0.004, 0.008), (0.55, 0.296, 0.12 + k * 0.02), mat="acento", bevel=0.0)
    # Cables
    cable("cable_m1", [(-0.33, -0.25, 0.85), (-0.3, -0.38, 0.6), (0.3, -0.3, 0.1), (0.55, -0.18, 0.2)], radius=0.006, mat="plastico_negro")
    cable("cable_m2", [(0.33, -0.25, 0.85), (0.4, -0.38, 0.55), (0.52, -0.2, 0.25)], radius=0.006, mat="plastico_negro")
    # Taza, papeles, notas
    cyl("taza", 0.04, 0.095, (-0.62, 0.15, 0.806), mat="pintura_blanca", verts=16)
    ring("taza_asa", 0.025, 0.007, (-0.665, 0.15, 0.806), (90, 0, 0), mat="pintura_blanca", seg=12, minor=6)
    for k in range(4):
        box("hoja_%d" % k, (0.21, 0.29, 0.002), (0.6 + R.uniform(-0.05, 0.05), 0.15, 0.759 + k * 0.002), (0, 0, R.uniform(-25, 25)), mat="papel", bevel=0.0)
    box("nota", (0.07, 0.002, 0.07), (-0.55, -0.20, 0.95), (0, 0, 12), mat="pintura_amarilla", bevel=0.0)
    finish("escritorio_pc", (1.7, 2.1, 1.7), (0, 0, 0.75), tex=2048)


def silla_oficina():
    start(14)
    for k in range(5):
        a = math.radians(k * 72 + 18)
        tube("brazo_%d" % k, (0, 0, 0.1), (math.cos(a) * 0.32, math.sin(a) * 0.32, 0.07), 0.022, mat="plastico_negro")
        sphere("rodaja_%d" % k, 0.03, (math.cos(a) * 0.32, math.sin(a) * 0.32, 0.035), (0.8, 1.2, 1), mat="plastico_negro", segs=12)
    cyl("piston", 0.03, 0.3, (0, 0, 0.25), mat="inox", verts=14)
    cyl("funda", 0.04, 0.12, (0, 0, 0.15), mat="plastico_negro", verts=14)
    box("mecanismo", (0.22, 0.24, 0.05), (0, 0, 0.42), mat="metal_oscuro", bevel=0.01)
    box("asiento", (0.48, 0.48, 0.08), (0, 0.02, 0.48), mat="tela_negra", bevel=0.035, segs=3)
    tube("barra_resp", (0, -0.22, 0.45), (0, -0.27, 0.62), 0.022, mat="metal_oscuro")
    box("respaldo", (0.44, 0.06, 0.55), (0, -0.28, 0.9), (-8, 0, 0), mat="tela_negra", bevel=0.03, segs=3)
    box("respaldo_marco", (0.46, 0.03, 0.57), (0, -0.31, 0.9), (-8, 0, 0), mat="plastico_negro", bevel=0.012)
    for sx in (-1, 1):
        tube("descansa_%d" % sx, (sx * 0.24, -0.05, 0.47), (sx * 0.26, -0.05, 0.66), 0.018, mat="plastico_negro")
        box("descansa_top_%d" % sx, (0.06, 0.26, 0.03), (sx * 0.26, 0.0, 0.67), mat="plastico_negro", bevel=0.012)
    finish("silla_oficina", (1.3, 1.4, 1.2), (0, 0, 0.55))


def pc_vieja():
    start(15)
    # Monitor CRT sobre el gabinete horizontal
    box("gabinete", (0.44, 0.42, 0.14), (0, 0, 0.07), mat="plastico_beige", bevel=0.008)
    box("disquetera", (0.12, 0.01, 0.015), (-0.08, 0.212, 0.09), mat="acento", bevel=0.0)
    box("cd", (0.16, 0.01, 0.035), (0.1, 0.212, 0.09), mat="plastico_beige", bevel=0.003)
    box("power", (0.02, 0.01, 0.02), (0.18, 0.212, 0.04), mat="led_verde", bevel=0.002)
    box("crt_frente", (0.42, 0.06, 0.36), (0, 0.11, 0.33), mat="plastico_beige", bevel=0.02)
    box("crt_cuerpo", (0.38, 0.32, 0.32), (0, -0.07, 0.32), mat="plastico_beige", bevel=0.02, taper=None)
    box("crt_cola", (0.26, 0.14, 0.2), (0, -0.25, 0.31), mat="plastico_beige", bevel=0.02)
    sphere("crt_pantalla", 0.2, (0, 0.11, 0.335), (0.85, 0.12, 0.7), mat="pantalla_verde" if R.random() < 0.5 else "pantalla_apagada", segs=20)
    box("crt_marco_int", (0.36, 0.01, 0.29), (0, 0.137, 0.335), mat="plastico_gris", bevel=0.01)
    for k in range(6):
        box("crt_vent_%d" % k, (0.18, 0.004, 0.006), (0, -0.322, 0.27 + k * 0.025), mat="acento", bevel=0.0)
    cable("cable", [(0, -0.3, 0.3), (0.1, -0.45, 0.15), (0.25, -0.4, 0.02)], radius=0.007, mat="plastico_negro")
    finish("pc_vieja", (1.0, 1.2, 0.9), (0, 0, 0.3))


def bobina_cable():
    start(16)
    for sx in (-1, 1):
        cyl("disco_%d" % sx, 0.5, 0.05, (sx * 0.25, 0, 0.5), (0, 90, 0), mat="madera", verts=32, bevel=0.008)
        for k in range(6):
            a = k * math.pi / 3
            bolts("tornillo_%d_%d" % (sx, k), [(sx * 0.278, math.cos(a) * 0.22, 0.5 + math.sin(a) * 0.22)], (0, 90, 0))
    cyl("nucleo", 0.18, 0.46, (0, 0, 0.5), (0, 90, 0), mat="madera", verts=24)
    cyl("cable_enrollado", 0.38, 0.44, (0, 0, 0.5), (0, 90, 0), mat="cable_naranja", verts=40, bevel=0.02)
    for k in range(9):
        ring("vuelta_%d" % k, 0.38, 0.018, (-0.2 + k * 0.05, 0, 0.5), (0, 90, 0), mat="cable_naranja", seg=40, minor=6)
    cable("punta", [(0.1, 0.38, 0.5), (0.3, 0.6, 0.3), (0.6, 0.7, 0.02), (1.0, 0.6, 0.02)], radius=0.018, mat="cable_naranja")
    finish("bobina_cable", (1.6, 1.8, 1.2), (0, 0, 0.45))


# ================================================================ BIBLIOTECA

def turned_leg(prefix, x, y, h, r=0.04):
    zs = [0, 0.08, 0.12, h * 0.4, h * 0.5, h * 0.6, h - 0.12, h - 0.08, h]
    rs = [r * 0.8, r, r * 1.3, r * 0.75, r * 1.15, r * 0.75, r, r * 1.2, r * 1.2]
    limb(prefix, [(x, y, z) for z in zs], rs, mat="madera", verts=12)


def lamp(prefix, x, y, z):
    cyl(prefix + "_base", 0.08, 0.025, (x, y, z + 0.012), mat="laton", verts=20)
    tube(prefix + "_tallo", (x, y, z), (x, y - 0.04, z + 0.36), 0.01, mat="laton")
    cyl(prefix + "_pantalla", 0.075, 0.34, (x, y, z + 0.38), (0, 90, 0), mat="vidrio_verde", verts=20, bevel=0.0)
    cyl(prefix + "_foco", 0.025, 0.25, (x, y, z + 0.37), (0, 90, 0), mat="foco", verts=10, bevel=0.0)
    tube(prefix + "_cadena", (x + 0.06, y + 0.02, z + 0.33), (x + 0.06, y + 0.04, z + 0.2), 0.003, mat="laton")


def open_book(prefix, x, y, z, yaw=0, s=1.0):
    for sx in (-1, 1):
        box(prefix + "_pag_%d" % sx, (0.17 * s, 0.24 * s, 0.025 * s), (x + sx * 0.085 * s, y, z + 0.014 * s), (0, sx * 6, yaw), mat="papel", bevel=0.004)
        box(prefix + "_tapa_%d" % sx, (0.18 * s, 0.25 * s, 0.006 * s), (x + sx * 0.09 * s, y, z + 0.002), (0, sx * 6, yaw), mat="tapa_roja", bevel=0.002)


def mesa_lectura():
    start(20)
    L, W, H = 2.4, 1.0, 0.76
    box("cubierta", (L, W, 0.05), (0, 0, H - 0.025), mat="madera", bevel=0.012)
    box("canto", (L + 0.03, W + 0.03, 0.02), (0, 0, H - 0.06), mat="madera_tallada", bevel=0.006)
    for sx in (-1, 1):
        for sy in (-1, 1):
            turned_leg("pata_%d_%d" % (sx, sy), sx * (L / 2 - 0.12), sy * (W / 2 - 0.1), H - 0.07)
    for sy in (-1, 1):
        box("faldon_%d" % sy, (L - 0.3, 0.03, 0.1), (0, sy * (W / 2 - 0.1), H - 0.12), mat="madera_tallada", bevel=0.004)
    box("travesano", (L - 0.3, 0.05, 0.04), (0, 0, 0.15), mat="madera", bevel=0.006)
    lamp("lampara1", -0.6, 0.0, H)
    lamp("lampara2", 0.6, 0.0, H)
    open_book("libro1", -0.6, 0.3, H, 5)
    open_book("libro2", 0.55, -0.3, H, 180)
    cols = ["tapa_roja", "tapa_azul", "tapa_verde", "tapa_cafe"]
    z = H
    for k in range(6):
        t = R.uniform(0.03, 0.06)
        box("pila_%d" % k, (0.22 + R.uniform(-0.03, 0.03), 0.3, t), (0.05, 0.25, z + t / 2), (0, 0, R.uniform(-12, 12)), mat=R.choice(cols), bevel=0.004)
        z += t
    for k in range(3):
        box("hoja_%d" % k, (0.21, 0.29, 0.002), (-0.15 + k * 0.1, -0.25, H + 0.002 + k * 0.001), (0, 0, R.uniform(-40, 40)), mat="papel", bevel=0.0)
    cyl("tintero", 0.03, 0.05, (0.25, -0.05, H + 0.025), mat="vidrio_ambar", verts=12, bevel=0.0)
    tube("pluma", (0.25, -0.05, H + 0.04), (0.3, -0.02, H + 0.18), 0.004, mat="tapa_cafe")
    finish("mesa_lectura", (2.4, 2.8, 2.1), (0, 0, 0.8), tex=2048)


def fichero():
    start(21)
    W, D, H = 0.95, 0.5, 1.3
    box("cuerpo", (W, D, H - 0.12), (0, 0, 0.1 + (H - 0.12) / 2), mat="madera", bevel=0.01)
    box("zoclo", (W + 0.04, D + 0.04, 0.1), (0, 0, 0.05), mat="madera_tallada", bevel=0.01)
    box("cornisa", (W + 0.06, D + 0.06, 0.05), (0, 0, H - 0.0), mat="madera_tallada", bevel=0.012)
    cols, rows = 5, 8
    cw, rh = (W - 0.08) / cols, (H - 0.3) / rows
    open_one = (2, 3)
    for c in range(cols):
        for r in range(rows):
            x = -W / 2 + 0.04 + cw * (c + 0.5)
            z = 0.16 + rh * (r + 0.5)
            pull = 0.28 if (c, r) == open_one else (0.03 if R.random() < 0.1 else 0.0)
            y = D / 2 + 0.01 + pull
            panel("cajon_%d_%d" % (c, r), (cw - 0.012, 0.025, rh - 0.012), (x, y, z), mat="madera", inset=0.008, depth=0.003)
            box("porta_%d_%d" % (c, r), (0.07, 0.006, 0.03), (x, y + 0.016, z + 0.02), mat="laton", bevel=0.002)
            box("etq_%d_%d" % (c, r), (0.06, 0.004, 0.022), (x, y + 0.017, z + 0.02), mat="papel", bevel=0.0)
            cyl("jalador_%d_%d" % (c, r), 0.012, 0.02, (x, y + 0.02, z - 0.02), (90, 0, 0), mat="laton", verts=10)
            if (c, r) == open_one:
                box("cajon_lado_a", (0.01, 0.3, rh - 0.03), (x - cw / 2 + 0.01, y - 0.16, z), mat="madera", bevel=0.002)
                box("cajon_lado_b", (0.01, 0.3, rh - 0.03), (x + cw / 2 - 0.01, y - 0.16, z), mat="madera", bevel=0.002)
                for k in range(14):
                    box("ficha_%d" % k, (cw - 0.04, 0.003, rh * 0.75), (x, y - 0.04 - k * 0.018, z + R.uniform(-0.01, 0.01)), (R.uniform(-10, 10), 0, 0), mat="papel", bevel=0.0)
    finish("fichero", (1.7, 2.0, 1.6), (0, 0, 0.7))


def carrito_libros():
    start(22)
    L, W = 0.9, 0.42
    for sx in (-1, 1):
        box("lado_%d" % sx, (0.03, W, 0.95), (sx * L / 2, 0, 0.55), mat="madera", bevel=0.006)
    for k, z in enumerate((0.15, 0.48, 0.8)):
        box("repisa_%d" % k, (L, W, 0.025), (0, 0, z), (8 if k == 2 else 0, 0, 0), mat="madera", bevel=0.004)
        books_row("libros_%d" % k, -L / 2 + 0.03, L / 2 - 0.03, 0, z + 0.013, depth=0.2, hmin=0.17, hmax=0.27)
    tube("asa", (-L / 2 - 0.05, -0.15, 0.95), (-L / 2 - 0.05, 0.15, 0.95), 0.015, mat="metal")
    for sx in (-1, 1):
        for sy in (-1, 1):
            wheel("rueda_%d_%d" % (sx, sy), (sx * (L / 2 - 0.05), sy * (W / 2 - 0.05), 0.04), 0.04, 0.025, axis="x")
    finish("carrito_libros", (1.5, 1.7, 1.3), (0, 0, 0.5))


def globo():
    start(23)
    for k in range(3):
        a = math.radians(k * 120 + 30)
        limb("pata_%d" % k, [(math.cos(a) * 0.3, math.sin(a) * 0.3, 0.0), (math.cos(a) * 0.22, math.sin(a) * 0.22, 0.25), (math.cos(a) * 0.12, math.sin(a) * 0.12, 0.45)],
             [0.025, 0.03, 0.03], mat="madera", verts=10)
    cyl("aro_base", 0.36, 0.04, (0, 0, 0.47), mat="madera_tallada", verts=32, bevel=0.006)
    ring("horizonte", 0.36, 0.015, (0, 0, 0.6), mat="laton", seg=48)
    ring("meridiano", 0.33, 0.012, (0, 0, 0.82), (90, 23, 0), mat="laton", seg=48, minor=6, arc=0.75)
    sphere("esfera", 0.3, (0, 0, 0.82), mat="mapa", segs=32)
    tube("eje", (0, 0, 0.47), (0, 0, 0.55), 0.02, mat="laton")
    finish("globo", (1.3, 1.5, 1.3), (0, 0, 0.6))


def atril():
    start(24)
    box("base", (0.55, 0.45, 0.06), (0, 0, 0.03), mat="madera_tallada", bevel=0.012)
    limb("columna", [(0, 0, 0.06), (0, 0, 0.3), (0, 0, 0.5), (0, 0, 0.8), (0, 0, 1.0)], [0.08, 0.05, 0.07, 0.05, 0.06], mat="madera", verts=14)
    box("caja", (0.6, 0.45, 0.12), (0, 0, 1.08), (-18, 0, 0), mat="madera_tallada", bevel=0.01)
    box("tope", (0.6, 0.03, 0.04), (0, 0.24, 1.0), (-18, 0, 0), mat="madera", bevel=0.006)
    # Libro gigante abierto
    for sx in (-1, 1):
        box("pags_%d" % sx, (0.27, 0.38, 0.05), (sx * 0.14, 0, 1.16), (-18, sx * 7, 0), mat="papel", bevel=0.01)
        box("tapa_%d" % sx, (0.28, 0.4, 0.012), (sx * 0.145, 0.0, 1.135), (-18, sx * 7, 0), mat="tapa_roja", bevel=0.004)
    cloth("cinta", 0.03, 0.3, (0.0, 0.18, 1.18), (0, 0, 0), mat="tela_vino", nx=2, ny=6, tatter=0.1, holes=0.0)
    finish("atril", (1.3, 1.5, 1.6), (0, 0, 0.8))


# ================================================================ PLAZA (profesor)

def pupitre():
    start(30)
    for sx in (-1, 1):
        tube("pata_d_%d" % sx, (sx * 0.2, 0.2, 0.0), (sx * 0.2, 0.18, 0.44), 0.012, mat="metal_oscuro")
        tube("pata_t_%d" % sx, (sx * 0.2, -0.2, 0.0), (sx * 0.2, -0.18, 0.44), 0.012, mat="metal_oscuro")
        tube("patin_%d" % sx, (sx * 0.2, 0.2, 0.01), (sx * 0.2, -0.2, 0.01), 0.012, mat="metal_oscuro")
        tube("resp_%d" % sx, (sx * 0.18, -0.2, 0.44), (sx * 0.18, -0.26, 0.85), 0.012, mat="metal_oscuro")
    box("asiento", (0.42, 0.42, 0.02), (0, 0, 0.45), mat="laminado", bevel=0.006)
    box("respaldo", (0.4, 0.02, 0.2), (0, -0.25, 0.75), (-8, 0, 0), mat="laminado", bevel=0.006)
    tube("brazo", (0.2, -0.1, 0.44), (0.25, 0.15, 0.72), 0.012, mat="metal_oscuro")
    box("paleta", (0.3, 0.48, 0.018), (0.12, 0.2, 0.73), mat="laminado", bevel=0.006)
    box("rejilla", (0.36, 0.3, 0.01), (0, 0, 0.2), mat="metal_oscuro", bevel=0.002)
    label("grafiti", "AYUDA", (0.12, 0.2, 0.74), (0, 0, 15), size=0.05, depth=0.001, mat="acento")
    finish("pupitre", (1.2, 1.4, 1.2), (0, 0, 0.5))


def pizarron():
    start(31)
    W, H = 1.8, 1.1
    for sx in (-1, 1):
        tube("poste_%d" % sx, (sx * (W / 2 + 0.05), 0, 0.08), (sx * (W / 2 + 0.05), 0, 1.95), 0.022, mat="metal")
        tube("pie_%d" % sx, (sx * (W / 2 + 0.05), -0.3, 0.08), (sx * (W / 2 + 0.05), 0.3, 0.08), 0.022, mat="metal")
        for sy in (-1, 1):
            wheel("rueda_%d_%d" % (sx, sy), (sx * (W / 2 + 0.05), sy * 0.3, 0.04), 0.04, 0.025, axis="x")
    box("marco", (W + 0.06, 0.05, H + 0.06), (0, 0, 1.35), mat="metal", bevel=0.008)
    box("pizarra", (W, 0.055, H), (0, 0, 1.35), mat="pizarra", bevel=0.004)
    box("bandeja", (W, 0.08, 0.02), (0, 0.06, 0.79), mat="metal", bevel=0.004)
    for k in range(3):
        cyl("gis_%d" % k, 0.006, 0.07, (-0.5 + k * 0.2, 0.07, 0.806), (0, 90, R.uniform(-20, 20)), mat="tiza", verts=8, bevel=0.0)
    box("borrador", (0.14, 0.05, 0.035), (0.4, 0.07, 0.815), mat="madera", bevel=0.006)
    label("t1", "EXAMEN FINAL", (-0.25, 0.03, 1.72), (90, 0, 180), size=0.12, depth=0.0015, mat="tiza")
    label("t2", "lim  f(x) = ?", (-0.4, 0.03, 1.5), (90, 0, 180), size=0.08, depth=0.0015, mat="tiza")
    label("t3", "x -> 0", (-0.55, 0.03, 1.4), (90, 0, 180), size=0.05, depth=0.0015, mat="tiza")
    label("t4", "NADIE APRUEBA", (0.0, 0.03, 1.05), (90, 6, 180), size=0.1, depth=0.0015, mat="led_rojo")
    label("t5", "dy/dx = -k y", (0.45, 0.03, 1.38), (90, 0, 180), size=0.06, depth=0.0015, mat="tiza")
    finish("pizarron", (2.0, 2.8, 1.9), (0, 0, 1.2))


# ================================================================ AULA MAGNA (rector)

def butacas():
    start(40)
    n, pitch = 4, 0.58
    x0 = -(n - 1) * pitch / 2
    for k in range(n + 1):
        x = x0 + (k - 0.5) * pitch
        box("costado_%d" % k, (0.06, 0.62, 0.62), (x, -0.02, 0.31), mat="metal_oscuro", bevel=0.015)
        box("costado_orn_%d" % k, (0.065, 0.3, 0.25), (x, 0.05, 0.38), mat="oro", bevel=0.006)
        box("brazo_%d" % k, (0.07, 0.45, 0.04), (x, 0.05, 0.64), mat="madera", bevel=0.012)
    for k in range(n):
        x = x0 + k * pitch
        folded = R.random() < 0.4
        if folded:
            box("asiento_%d" % k, (0.48, 0.1, 0.42), (x, 0.08, 0.5), (-10, 0, 0), mat="terciopelo", bevel=0.04, segs=3)
        else:
            box("asiento_%d" % k, (0.48, 0.46, 0.1), (x, 0.08, 0.42), (-4, 0, 0), mat="terciopelo", bevel=0.04, segs=3)
        box("respaldo_%d" % k, (0.5, 0.1, 0.66), (x, -0.25, 0.82), (-12, 0, 0), mat="terciopelo", bevel=0.045, segs=3)
        box("respaldo_tras_%d" % k, (0.52, 0.04, 0.68), (x, -0.31, 0.82), (-12, 0, 0), mat="madera_tallada", bevel=0.012)
        box("placa_%d" % k, (0.06, 0.005, 0.03), (x, 0.09 if folded else 0.31, 0.38), mat="laton", bevel=0.002)
        if R.random() < 0.35:
            # Tapiz rasgado
            blob("relleno_%d" % k, 0.07, (x + 0.08, -0.19, 0.95), (1.2, 0.6, 0.8), mat="papel", lumps=0.5)
    finish("butacas", (2.4, 3.2, 1.8), (0, 0, 0.6), tex=2048)


def podio():
    start(41)
    box("base", (1.0, 0.7, 0.1), (0, 0, 0.05), mat="madera_tallada", bevel=0.015)
    box("cuerpo", (0.9, 0.6, 1.0), (0, 0, 0.6), mat="madera", bevel=0.01, taper=(1.05, 1.0))
    for sx in (-1, 1):
        limb("columna_%d" % sx, [(sx * 0.42, 0.3, 0.1), (sx * 0.42, 0.3, 0.6), (sx * 0.42, 0.3, 1.1)], [0.05, 0.04, 0.05], mat="madera_tallada", verts=12)
    panel("frente", (0.66, 0.03, 0.7), (0, 0.31, 0.6), mat="madera_tallada", inset=0.03)
    cyl("escudo", 0.17, 0.03, (0, 0.34, 0.7), (90, 0, 0), mat="oro", verts=32)
    ring("escudo_aro", 0.18, 0.012, (0, 0.35, 0.7), (90, 0, 0), mat="oro", seg=40, minor=6)
    label("lema", "UNIVERSITAS", (0, 0.36, 0.45), (90, 0, 180), size=0.06, depth=0.004, mat="oro")
    label("ano", "MCMXII", (0, 0.36, 0.7), (90, 0, 180), size=0.05, depth=0.004, mat="acento")
    box("atril", (0.8, 0.5, 0.05), (0, 0.0, 1.15), (-15, 0, 0), mat="madera_tallada", bevel=0.012)
    box("tope", (0.8, 0.03, 0.05), (0, 0.24, 1.1), (-15, 0, 0), mat="madera", bevel=0.006)
    cable("micro_cuello", [(0.25, -0.05, 1.18), (0.27, 0.05, 1.35), (0.22, 0.2, 1.42)], radius=0.008, mat="metal_oscuro")
    sphere("micro", 0.025, (0.21, 0.22, 1.43), (1, 1.6, 1), mat="metal", segs=12)
    for sx in (-1, 1):
        box("hoja_%d" % sx, (0.21, 0.29, 0.003), (sx * 0.13, 0.0, 1.18), (-15, 0, sx * 5), mat="papel", bevel=0.0)
    finish("podio", (1.8, 2.2, 1.8), (0, 0, 0.8))


def estandarte():
    start(42)
    box("pie", (0.5, 0.5, 0.06), (0, 0, 0.03), mat="metal_oscuro", bevel=0.012)
    tube("asta", (0, 0, 0.06), (0, 0, 3.4), 0.03, mat="laton")
    sphere("remate", 0.07, (0, 0, 3.45), (1, 1, 1.3), mat="oro", segs=14)
    tube("travesano", (-0.55, 0.04, 3.2), (0.55, 0.04, 3.2), 0.02, mat="laton")
    for sx in (-1, 1):
        sphere("remate_t_%d" % sx, 0.03, (sx * 0.57, 0.04, 3.2), mat="oro", segs=10)
    cloth("bandera", 1.0, 2.2, (0, 0.06, 3.19), (0, 0, 0), mat="tela_vino", nx=14, ny=18, tatter=0.25, holes=0.03, wave=0.03, flare=0.05)
    cyl("emblema", 0.22, 0.012, (0, 0.11, 2.45), (90, 0, 0), mat="oro", verts=32, bevel=0.0)
    ring("emblema_aro", 0.25, 0.012, (0, 0.11, 2.45), (90, 0, 0), mat="oro", seg=40, minor=6)
    label("lema", "LUX ET VERITAS", (0, 0.125, 1.95), (90, 0, 180), size=0.075, depth=0.002, mat="oro")
    box("franja", (0.98, 0.01, 0.05), (0, 0.075, 3.08), mat="oro", bevel=0.0)
    finish("estandarte", (2.6, 3.6, 2.4), (0, 0, 1.9))


def candelabro():
    start(43)
    for k in range(3):
        a = math.radians(k * 120)
        limb("pie_%d" % k, [(math.cos(a) * 0.28, math.sin(a) * 0.28, 0.0), (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.1), (0, 0, 0.18)], [0.03, 0.03, 0.04], mat="laton", verts=10)
    limb("fuste", [(0, 0, 0.15), (0, 0, 0.4), (0, 0, 0.55), (0, 0, 0.9), (0, 0, 1.2), (0, 0, 1.45)], [0.05, 0.03, 0.06, 0.025, 0.04, 0.03], mat="laton", verts=14)
    for k in range(5):
        a = math.radians(k * 72)
        cx, cy = math.cos(a) * 0.32, math.sin(a) * 0.32
        cable("brazo_%d" % k, [(0, 0, 1.4), (cx * 0.5, cy * 0.5, 1.35), (cx, cy, 1.48)], radius=0.015, mat="laton", res=8)
        cyl("plato_%d" % k, 0.05, 0.015, (cx, cy, 1.5), mat="laton", verts=14)
        h = R.uniform(0.08, 0.22)
        cyl("vela_%d" % k, 0.022, h, (cx, cy, 1.51 + h / 2), mat="cera", verts=12, bevel=0.003)
        limb("cera_%d" % k, [(cx + 0.02, cy, 1.51 + h), (cx + 0.024, cy, 1.51 + h * 0.6), (cx + 0.03, cy, 1.5)], [0.006, 0.007, 0.01], mat="cera", verts=6)
        sphere("llama_%d" % k, 0.012, (cx, cy, 1.51 + h + 0.025), (1, 1, 2.2), mat="llama", segs=8)
    h = 0.25
    cyl("vela_c", 0.025, h, (0, 0, 1.47 + h / 2), mat="cera", verts=12)
    sphere("llama_c", 0.014, (0, 0, 1.47 + h + 0.03), (1, 1, 2.2), mat="llama", segs=8)
    finish("candelabro", (1.4, 1.8, 1.8), (0, 0, 1.0))


# ================================================================ VEHÍCULOS (calles y arenas)

def extrude_profile(name, prof, width, loc, mat, taper_z=None, taper=1.0, bevel=0.05):
    """Perfil lateral (x, z) extruido a lo ancho (y). taper: escala en y arriba de taper_z."""
    bm = bmesh.new()
    a = [bm.verts.new((x, -width / 2, z)) for x, z in prof]
    b = [bm.verts.new((x, width / 2, z)) for x, z in prof]
    n = len(prof)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    if taper_z is not None:
        for v in bm.verts:
            if v.co.z > taper_z:
                v.co.y *= taper
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = bk._obj_from_bm(name, bm)
    return bk._finish_part(ob, loc, (0, 0, 0), "root", mat, bevel, 3)


def auto(name, paint, burnt=False):
    """Sedán abandonado, a lo largo de X (frente hacia +X), origen en el piso."""
    start(50 + len(name))
    body = "quemado" if burnt else paint
    W = 1.82
    extrude_profile("carroceria", [(-2.15, 0.33), (2.12, 0.33), (2.17, 0.62), (2.05, 0.82), (1.05, 0.93), (0.5, 0.98),
                                   (-1.7, 0.98), (-2.08, 0.92), (-2.2, 0.62)], W, (0, 0, 0), body, bevel=0.07)
    # Cabina: vidrios oscuros (sin vidrio si se quemó) con techo y pilares de lámina
    cab = [(0.48, 0.97), (-0.12, 1.5), (-1.12, 1.5), (-1.68, 0.97)]
    if not burnt:
        extrude_profile("vidrios", cab, W * 0.84, (0, 0, 0), "vidrio_auto", bevel=0.03)
    box("techo", (1.06, W * 0.82, 0.05), (-0.62, 0, 1.51), mat=body, bevel=0.02)
    for sy in (-1, 1):
        y = sy * W * 0.42
        tube("pilar_a_%d" % sy, (0.48, y, 0.97), (-0.12, y * 0.97, 1.5), 0.035, mat=body)
        tube("pilar_b_%d" % sy, (-0.6, y, 0.97), (-0.6, y * 0.97, 1.5), 0.04, mat=body)
        tube("pilar_c_%d" % sy, (-1.68, y, 0.97), (-1.12, y * 0.97, 1.5), 0.05, mat=body)
        # Puertas, manijas, espejo y molduras
        for x in (0.45, -0.62, -1.6):
            box("junta_%d_%s" % (sy, x), (0.01, 0.01, 0.55), (x, sy * (W / 2 + 0.002), 0.66), mat="acento", bevel=0.0)
        for x in (0.1, -1.0):
            box("manija_%d_%s" % (sy, x), (0.14, 0.02, 0.03), (x, sy * (W / 2 + 0.01), 0.86), mat="metal_oscuro" if burnt else "inox", bevel=0.006)
        box("espejo_%d" % sy, (0.1, 0.14, 0.08), (0.4, sy * (W / 2 + 0.08), 1.0), mat=body, bevel=0.02)
        box("moldura_%d" % sy, (3.6, 0.02, 0.05), (0, sy * (W / 2 + 0.005), 0.42), mat="plastico_negro", bevel=0.006)
    # Defensas, faros, calaveras y placas
    box("defensa_d", (0.14, W + 0.04, 0.2), (2.17, 0, 0.42), mat="plastico_negro", bevel=0.04)
    box("defensa_t", (0.14, W + 0.04, 0.2), (-2.2, 0, 0.42), mat="plastico_negro", bevel=0.04)
    box("parrilla", (0.04, 0.8, 0.14), (2.17, 0, 0.66), mat="metal_oscuro", bevel=0.01)
    for sy in (-1, 1):
        box("faro_%d" % sy, (0.06, 0.38, 0.12), (2.13, sy * 0.66, 0.7), mat="metal_oscuro" if burnt else "inox", bevel=0.02)
        box("calavera_%d" % sy, (0.06, 0.4, 0.14), (-2.17, sy * 0.64, 0.74), mat="acento" if burnt else "calavera", bevel=0.02)
    box("placa_d", (0.02, 0.4, 0.13), (2.25, 0, 0.42), mat="pintura_blanca", bevel=0.004)
    box("placa_t", (0.02, 0.4, 0.13), (-2.28, 0, 0.6), mat="pintura_blanca", bevel=0.004)
    label("placa_txt", "UNV-%03d" % R.randint(100, 999), (-2.295, 0, 0.6), (90, 0, -90), size=0.07, mat="acento")
    # Ruedas: llanta y rin (el quemado solo conserva los rines)
    for x in (1.38, -1.4):
        for sy in (-1, 1):
            y = sy * 0.8
            if burnt:
                cyl("rin_%s_%d" % (x, sy), 0.25, 0.2, (x, y, 0.26), (90, 0, 0), mat="quemado", verts=18)
            else:
                cyl("llanta_%s_%d" % (x, sy), 0.34, 0.24, (x, y, 0.34), (90, 0, 0), mat="goma", verts=24, bevel=0.05)
                cyl("rin_%s_%d" % (x, sy), 0.21, 0.25, (x, y, 0.34), (90, 0, 0), mat="metal", verts=18, bevel=0.01)
            box("salpicadera_%s_%d" % (x, sy), (0.95, 0.06, 0.06), (x, sy * (W / 2 - 0.01), 0.72), mat=body, bevel=0.025)
    box("chasis", (4.0, W - 0.2, 0.12), (0, 0, 0.3), mat="metal_oscuro", bevel=0.01)
    if burnt:
        # Interior calcinado visible
        for x in (0.0, -1.1):
            box("asiento_%s" % x, (0.5, 1.4, 0.45), (x, 0, 0.9), mat="quemado", bevel=0.05)
        box("volante", (0.05, 0.35, 0.35), (0.25, 0.4, 1.1), (0, -25, 0), mat="quemado", bevel=0.02)
    finish(name, (5.5, 5.0, 3.0), (0, 0, 0.8), tex=2048)


def autobus(name, paint, burnt=False):
    """Autobús universitario a lo largo de X (frente hacia +X), origen en el piso."""
    start(70 + len(name))
    body = "quemado" if burnt else paint
    L, W = 11.0, 2.55
    extrude_profile("caja", [(-L / 2, 0.45), (L / 2, 0.45), (L / 2 + 0.05, 1.2), (L / 2 - 0.1, 3.1), (-L / 2 + 0.05, 3.15), (-L / 2, 1.2)], W, (0, 0, 0), body, bevel=0.12)
    for sy in (-1, 1):
        y = sy * (W / 2 + 0.005)
        if not burnt:
            box("ventanas_%d" % sy, (L - 2.4, 0.02, 0.95), (-0.3, y, 2.25), mat="vidrio_auto", bevel=0.0)
        else:
            box("ventanas_%d" % sy, (L - 2.4, 0.02, 0.95), (-0.3, y, 2.25), mat="acento", bevel=0.0)
        for k in range(9):
            box("parante_%d_%d" % (sy, k), (0.1, 0.03, 0.95), (-L / 2 + 1.0 + k * 1.05, y, 2.25), mat=body, bevel=0.0)
        box("franja_%d" % sy, (L - 0.4, 0.02, 0.18), (0, y, 1.45), mat="pintura_blanca" if not burnt else "quemado", bevel=0.0)
        box("faldon_%d" % sy, (L - 0.3, 0.03, 0.2), (0, y, 0.55), mat="plastico_negro", bevel=0.01)
        if not burnt:
            label("rotulo_%d" % sy, "TRANSPORTE UNIVERSITARIO", (-0.8, y + sy * 0.012, 1.05), (90, 0, 180 if sy > 0 else 0), size=0.28, depth=0.004, mat="acento")
    # Puerta (lado derecho, -Y), parabrisas y luces
    box("puerta", (1.0, 0.03, 2.2), (L / 2 - 1.4, -(W / 2 + 0.01), 1.6), mat="vidrio_auto" if not burnt else "acento", bevel=0.0)
    box("parabrisas", (0.03, W - 0.3, 1.25), (L / 2 + 0.0, 0, 2.15), (0, -6, 0), mat="vidrio_auto" if not burnt else "acento", bevel=0.0)
    box("letrero", (0.03, 1.6, 0.25), (L / 2 - 0.08, 0, 2.95), mat="acento", bevel=0.0)
    if not burnt:
        label("ruta", "RUTA CAMPUS", (L / 2 - 0.05, 0, 2.95), (90, 0, 90), size=0.16, mat="led_ambar")
    for sy in (-1, 1):
        box("faro_%d" % sy, (0.05, 0.4, 0.2), (L / 2 + 0.03, sy * 0.85, 0.85), mat="inox", bevel=0.02)
        box("calavera_%d" % sy, (0.05, 0.25, 0.4), (-L / 2 - 0.02, sy * 1.0, 1.2), mat="calavera", bevel=0.02)
    box("defensa_d", (0.15, W, 0.25), (L / 2 + 0.06, 0, 0.55), mat="plastico_negro", bevel=0.04)
    box("defensa_t", (0.15, W, 0.25), (-L / 2 - 0.06, 0, 0.55), mat="plastico_negro", bevel=0.04)
    box("techo_ac", (2.2, 1.4, 0.25), (-1.0, 0, 3.25), mat="pintura_blanca" if not burnt else "quemado", bevel=0.05)
    for x in (L / 2 - 2.1, -L / 2 + 2.3):
        for sy in (-1, 1):
            if burnt:
                cyl("rin_%s_%d" % (x, sy), 0.36, 0.25, (x, sy * 1.05, 0.38), (90, 0, 0), mat="quemado", verts=18)
            else:
                cyl("llanta_%s_%d" % (x, sy), 0.5, 0.3, (x, sy * 1.05, 0.5), (90, 0, 0), mat="goma", verts=24, bevel=0.06)
                cyl("rin_%s_%d" % (x, sy), 0.3, 0.31, (x, sy * 1.05, 0.5), (90, 0, 0), mat="metal", verts=18, bevel=0.01)
    finish(name, (14.0, 12.0, 6.0), (0, 0, 1.6), tex=2048)


def auto_rojo():
    auto("auto_rojo", "auto_rojo")


def auto_gris():
    auto("auto_gris", "auto_gris")


def auto_azul():
    auto("auto_azul", "auto_azul")


def auto_quemado():
    auto("auto_quemado", "auto_gris", burnt=True)


def autobus_amarillo():
    autobus("autobus_amarillo", "auto_amarillo")


def autobus_quemado():
    autobus("autobus_quemado", "auto_amarillo", burnt=True)


TODOS = ["barril_toxico", "barril_azul", "barril_oxidado", "tanque_quimico", "caja_biopeligro", "mesa_lab", "camilla",
         "rack_servidor", "escritorio_pc", "silla_oficina", "pc_vieja", "bobina_cable",
         "mesa_lectura", "fichero", "carrito_libros", "globo", "atril",
         "pupitre", "pizarron", "butacas", "podio", "estandarte", "candelabro",
         "auto_rojo", "auto_gris", "auto_azul", "auto_quemado", "autobus_amarillo", "autobus_quemado"]

for n in (ONLY or TODOS):
    globals()[n]()
