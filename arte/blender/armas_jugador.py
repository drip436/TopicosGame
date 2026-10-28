"""Armas del jugador (jugador/class_kit.gd), al estilo de Elden Ring con tecnología.

Cada arma se modela en el espacio de su pivote en class_kit.gd (coordenadas de Godot
escritas con G(), igual que las primitivas que reemplaza), así se monta en la mano sin
cambiar nada del código:
  espada    Caballero: espada larga con acanaladura de datos cian y guarda en cruz.
  escudo    Caballero: escudo de cometa con candado en el umbo y circuitos cian.
  estoque   Mago: estoque de guarda de lazo con runa azul en la hoja.
  baston    Mago: bastón de madera y metal con garras que sostienen el orbe (el orbe y su
            luz son del código).
  mazo      Tanque: martillo de guerra con núcleo naranja y púa.
  tableta   AI Dev: tableta holográfica con marco metálico.
  lanza     Arquero: lanza de hoja de hoja con anillo tecnológico.
  arco      Arquero: arco recurvo de madera y metal con cuerda.

Uso:  blender -b --python arte/blender/armas_jugador.py -- <carpeta_salida> [preview] [arma ...]
"""
import sys
import os
import math

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import bk
from bk import box, cyl, sphere, panel, cable, limb, blob
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0]) if argv else os.path.abspath("modelos/armas_jugador")
PREVIEW = "preview" in argv
ONLY = [a for a in argv[1:] if a != "preview"]
os.makedirs(OUT, exist_ok=True)


def G(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return (x, -z, y)


def S(x, y, z):
    """Tamaño de caja de Godot (x, y, z) -> Blender (x, z, y)."""
    return (x, z, y)


MATS = {
    "acero": dict(base=(0.55, 0.56, 0.6), metal=1.0, rough=0.22, rust=0.2, wear=0.4, dirt=0.4, bare=(0.85, 0.85, 0.87), engrave=0.6, engrave_scale=40.0),
    "acero_liso": dict(base=(0.6, 0.61, 0.64), metal=1.0, rough=0.18, rust=0.15, wear=0.35, dirt=0.35, bare=(0.88, 0.88, 0.9)),
    "acero_oscuro": dict(base=(0.08, 0.08, 0.09), metal=0.9, rough=0.35, rust=0.4, wear=0.6, dirt=0.6, bare=(0.5, 0.5, 0.52), engrave=0.7, engrave_scale=20.0),
    "oro": dict(base=(0.62, 0.43, 0.13), metal=1.0, rough=0.28, rust=0.2, wear=0.5, dirt=0.5, bare=(0.8, 0.65, 0.35), engrave=0.5, engrave_scale=40.0),
    "cuero": dict(base=(0.06, 0.035, 0.02), rough=0.6, rust=0.0, wear=0.8, dirt=0.8, bare=(0.2, 0.13, 0.08)),
    "madera": dict(base=(0.1, 0.055, 0.03), rough=0.65, rust=0.0, wear=0.5, dirt=0.6, bare=(0.25, 0.16, 0.09), scratches=False, engrave=0.35, engrave_scale=14.0),
    "escudo": dict(base=(0.04, 0.07, 0.14), metal=0.6, rough=0.4, rust=0.3, wear=0.6, dirt=0.6, bare=(0.5, 0.5, 0.52), engrave=0.6, engrave_scale=10.0),
    "cuerda": dict(base=(0.5, 0.47, 0.4), rough=0.9, rust=0.0, wear=0.2, dirt=0.4, scratches=False),
    "cian": {"emit": (0.3, 0.85, 1.0), "strength": 3.0},
    "runa": {"emit": (0.35, 0.75, 1.0), "strength": 3.0},
    "naranja": {"emit": (1.0, 0.5, 0.1), "strength": 3.5},
    "pantalla": {"emit": (0.45, 0.85, 1.0), "strength": 1.6},
    "plasma": {"emit": (1.0, 0.35, 0.85), "strength": 5.0},
    "lava": {"emit": (1.0, 0.35, 0.05), "strength": 5.0},
    "violeta": {"emit": (0.65, 0.35, 1.0), "strength": 4.0},
    "hielo": {"emit": (0.55, 0.9, 1.0), "strength": 4.0},
    "acero_negro": dict(base=(0.03, 0.03, 0.035), metal=0.9, rough=0.28, rust=0.3, wear=0.5, dirt=0.5, bare=(0.4, 0.4, 0.42), engrave=0.8, engrave_scale=24.0),
    "rojo_oscuro": dict(base=(0.12, 0.02, 0.015), metal=0.8, rough=0.3, rust=0.4, wear=0.5, dirt=0.6, bare=(0.4, 0.3, 0.28), soot=0.6),
    "seda_negra": dict(base=(0.02, 0.02, 0.025), rough=0.8, rust=0.0, wear=0.3, dirt=0.4, scratches=False),
    "rack": dict(base=(0.05, 0.055, 0.06), metal=0.7, rough=0.4, rust=0.4, wear=0.6, dirt=0.6, bare=(0.4, 0.4, 0.42)),
}


def start(seed):
    bk.reset(seed=seed)
    bk.define_materials(MATS)


def finish(name, cam, tgt):
    bk.finish(name, tex_size=1024, bake=True, out_dir=OUT)
    if PREVIEW:
        bk.render_preview(os.path.join(OUT, "preview_%s.png" % name), cam, tgt, size=(700, 900))
    bk.export(os.path.join(OUT, name + ".glb"), actions=False)


def blade(prefix, base, tip, width, thick, axis_w, mat="acero", fuller=None, taper=0.25):
    """Hoja con filo biselado (malla propia): base y tip en Blender, ancho a lo largo de axis_w."""
    import bmesh
    import bpy
    base, tip = Vector(base), Vector(tip)
    d = (tip - base)
    L = d.length
    dn = d.normalized()
    w = Vector(axis_w).normalized()
    t = dn.cross(w).normalized()
    bm = bmesh.new()
    rings = []
    n = 12
    for i in range(n + 1):
        u = i / n
        p = base + d * u
        ww = width * (1.0 - u * (1 - taper)) if u < 0.88 else width * taper * (1.0 - (u - 0.88) / 0.12) + 0.001
        ring = [bm.verts.new(p + w * ww * 0.5), bm.verts.new(p + t * thick * 0.5), bm.verts.new(p - w * ww * 0.5), bm.verts.new(p - t * thick * 0.5)]
        rings.append(ring)
    for i in range(n):
        for j in range(4):
            a, b = rings[i][j], rings[i][(j + 1) % 4]
            c, e = rings[i + 1][(j + 1) % 4], rings[i + 1][j]
            bm.faces.new((a, b, c, e))
    bm.faces.new(list(reversed(rings[0])))
    tipv = bm.verts.new(tip + dn * 0.01)
    for j in range(4):
        bm.faces.new((rings[n][j], rings[n][(j + 1) % 4], tipv))
    me = bpy.data.meshes.new(prefix)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(prefix, me)
    bpy.context.scene.collection.objects.link(ob)
    ob["bone"] = "root"
    ob["mat"] = mat
    bk.PARTS.append(ob)
    if fuller:
        for sgn in (-1, 1):
            a = base + d * 0.05 + t * sgn * thick * 0.52
            b = base + d * 0.8 + t * sgn * thick * 0.52
            mid = (a + b) / 2
            rot = [math.degrees(x) for x in dn.to_track_quat("Z", "Y").to_euler()]
            cyl(prefix + "_canal_%d" % sgn, 0.004, (b - a).length, tuple(mid), rot, mat=fuller, verts=6, bevel=0)
    return ob


def espada():
    start(1)
    # Empuñadura (y −0.08..0.08), guarda en y 0.1, hoja hasta y 1.08 (filo hacia ±z)
    cyl("empunadura", 0.022, 0.16, G(0, 0.0, 0), mat="cuero", verts=12)
    for k in range(5):
        cyl("tira_%d" % k, 0.025, 0.018, G(0, -0.06 + k * 0.03, 0), (0, 0, k * 20), mat="cuero", verts=12)
    sphere("pomo", 0.035, G(0, -0.11, 0), (1, 1, 0.8), mat="oro", segs=14)
    box("guarda", S(0.06, 0.04, 0.3), G(0, 0.1, 0), mat="oro", bevel=0.008)
    for s in (-1, 1):
        sphere("guarda_punta_%d" % s, 0.025, G(0, 0.1, s * 0.16), mat="oro", segs=12)
    cyl("guarda_gema", 0.016, 0.07, G(0, 0.1, 0), (0, 90, 0), mat="cian", verts=12)
    blade("hoja", G(0, 0.12, 0), G(0, 1.08, 0), 0.075, 0.014, (0, 1, 0), mat="acero", fuller="cian", taper=0.45)
    finish("espada", (0.9, 1.4, 0.7), G(0, 0.5, 0))


def escudo():
    start(2)
    # Cara al frente = −z de Godot (+y de Blender); 0.6 × 0.72
    import bmesh
    import bpy
    bm = bmesh.new()
    pts = []
    for i in range(24):
        a = i / 24 * math.tau
        x = math.sin(a) * 0.3
        y = math.cos(a) * 0.36
        if y < 0:
            y *= 1.0 + 0.35 * (1 - abs(math.sin(a)))        # punta de cometa abajo
        pts.append(bm.verts.new((x, 0.0, y)))
    f = bm.faces.new(pts)
    bmesh.ops.triangulate(bm, faces=[f])
    me = bpy.data.meshes.new("escudo")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("escudo", me)
    bpy.context.scene.collection.objects.link(ob)
    m = ob.modifiers.new("grosor", "SOLIDIFY")
    m.thickness = 0.04
    m.offset = 0.0
    sd = ob.modifiers.new("sub", "SUBSURF")
    sd.levels = 1
    ob["bone"] = "root"
    ob["mat"] = "escudo"
    bk.PARTS.append(ob)
    # Abombado: curva el escudo hacia el frente
    for v in me.vertices:
        v.co.y += 0.06 * (1 - (v.co.x / 0.3) ** 2)
    ring = [Vector((math.sin(i / 24 * math.tau) * 0.3, 0.0, math.cos(i / 24 * math.tau) * 0.36)) for i in range(24)]
    for p in ring:
        if p.z < 0:
            p.z *= 1.0 + 0.35 * (1 - abs(p.x / 0.3))
        p.y += 0.06 * (1 - (p.x / 0.3) ** 2) + 0.022
    cu = bpy.data.curves.new("borde", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 0.014
    sp = cu.splines.new("POLY")
    sp.points.add(len(ring) - 1)
    for i, p in enumerate(ring):
        sp.points[i].co = (p.x, p.y, p.z, 1)
    sp.use_cyclic_u = True
    bo = bpy.data.objects.new("borde", cu)
    bpy.context.scene.collection.objects.link(bo)
    bpy.context.view_layer.objects.active = bo
    bo.select_set(True)
    bpy.ops.object.convert(target="MESH")
    bo = bpy.context.view_layer.objects.active
    bo["bone"] = "root"
    bo["mat"] = "oro"
    bk.PARTS.append(bo)
    # Umbo con candado y circuitos cian
    sphere("umbo", 0.08, (0, 0.09, 0.02), (1, 0.5, 1), mat="acero_oscuro", segs=20)
    box("candado", (0.06, 0.03, 0.055), (0, 0.13, 0.0), mat="oro", bevel=0.008)
    cyl("candado_arco", 0.022, 0.014, (0, 0.13, 0.045), (0, 90, 0), mat="oro", verts=16)
    for sx in (-1, 1):
        for k in range(3):
            box("circuito_%d_%d" % (sx, k), (0.004, 0.006, 0.18 - k * 0.04), (sx * (0.12 + k * 0.04), 0.075 - abs(sx * (0.12 + k * 0.04)) * 0.1, -0.08 + k * 0.02), mat="cian", bevel=0)
    box("correa", (0.05, 0.02, 0.4), (0, -0.03, 0), mat="cuero", bevel=0.005)
    finish("escudo", (0.7, 1.2, 0.3), (0, 0, 0))


def estoque():
    start(3)
    # Empuñadura en z 0.04 (Godot), guarda en z −0.05, hoja hasta z −1.06
    cyl("empunadura", 0.018, 0.14, G(0, 0, 0.04), (90, 0, 0), mat="cuero", verts=12)
    sphere("pomo", 0.03, G(0, 0, 0.13), mat="oro", segs=12)
    cyl("cazoleta", 0.055, 0.012, G(0, 0, -0.05), (90, 0, 0), mat="oro", verts=24, r2=0.05)
    # Guarda de lazo (barras curvas)
    for k in range(3):
        cable("lazo_%d" % k, [G(0, 0.0, 0.08), G(0.05 + k * 0.012, -0.02, 0.02), G(0.03, 0.0, -0.05)], 0.005, mat="oro", sag=0.0)
    blade("hoja", G(0, 0, -0.06), G(0, 0, -1.06), 0.022, 0.01, G(1, 0, 0), mat="acero_liso", fuller="runa", taper=0.5)
    finish("estoque", (0.9, 0.8, 0.5), G(0, 0, -0.45))


def baston():
    start(4)
    # Asta de y −0.6 a 0.9; el orbe del código queda en y 0.96
    limb("asta", [G(0, -0.6, 0), G(0.005, 0.0, 0.003), G(0, 0.5, 0), G(0, 0.86, 0)], [0.022, 0.027, 0.025, 0.03], mat="madera", verts=10, lumps=0.15)
    for k, y in enumerate((-0.55, -0.2, 0.25, 0.6)):
        cyl("anillo_%d" % k, 0.032, 0.03, G(0, y, 0), mat="oro", verts=14)
        cyl("anillo_runa_%d" % k, 0.033, 0.006, G(0, y, 0), mat="runa", verts=14, bevel=0)
    cyl("cuello", 0.045, 0.08, G(0, 0.84, 0), mat="acero_oscuro", verts=16, r2=0.055)
    for k in range(4):
        a = k / 4 * math.tau
        limb("garra_%d" % k, [G(math.cos(a) * 0.04, 0.86, math.sin(a) * 0.04), G(math.cos(a) * 0.1, 0.94, math.sin(a) * 0.1), G(math.cos(a) * 0.07, 1.04, math.sin(a) * 0.07)],
             [0.012, 0.009, 0.003], mat="oro", verts=6)
    cable("cable_baston", [G(0.03, 0.8, 0), G(0.05, 0.6, 0.02), G(0.03, 0.4, 0.01)], 0.006, mat="acero_oscuro", sag=0.0)
    finish("baston", (1.2, 1.6, 1.0), G(0, 0.4, 0))


def mazo():
    start(5)
    # Mango y −0.08..0.92; cabeza en y 0.98 a lo largo de z (caras en z ±0.24)
    cyl("mango", 0.032, 1.0, G(0, 0.42, 0), mat="acero_oscuro", verts=12)
    for k in range(6):
        cyl("cinta_%d" % k, 0.036, 0.025, G(0, -0.05 + k * 0.035, 0), (0, 0, k * 15), mat="cuero", verts=12)
    sphere("pomo", 0.045, G(0, -0.1, 0), mat="acero", segs=12)
    box("cabeza", S(0.26, 0.26, 0.36), G(0, 0.98, 0), mat="acero_oscuro", bevel=0.03, segs=3)
    for s in (-1, 1):
        cyl("cara_%d" % s, 0.15, 0.1, G(0, 0.98, s * 0.21), (90, 0, 0), mat="acero", verts=8, r2=0.14, bevel=0.01)
        for k in range(3):
            box("ventila_%d_%d" % (s, k), S(0.006, 0.12, 0.05), G(s * 0.132, 0.98, -0.06 + k * 0.06), mat="naranja", bevel=0)
    cyl("nucleo", 0.06, 0.27, G(0, 0.98, 0), (0, 90, 0), mat="naranja", verts=16)
    cyl("pua", 0.04, 0.16, G(0, 1.16, 0), mat="acero", verts=8, r2=0.0, bevel=0)
    for s in (-1, 1):
        box("refuerzo_%d" % s, S(0.04, 0.3, 0.04), G(s * 0.03, 0.76, 0), mat="oro", bevel=0.006)
    finish("mazo", (1.2, 1.6, 1.2), G(0, 0.6, 0))


def tableta():
    start(6)
    # Placa en (0, 0.1, −0.1), inclinada −30° en x (Godot): 0.24 × 0.32
    box("marco", (0.24, 0.022, 0.32), (0, 0, 0), mat="acero_oscuro", bevel=0.012)
    box("pantalla", (0.21, 0.004, 0.28), (0, 0.012, 0), mat="pantalla", bevel=0.002)
    for k in range(5):
        box("linea_%d" % k, (0.15 - k * 0.02, 0.003, 0.006), (-0.02, 0.0145, 0.09 - k * 0.04), mat="cian", bevel=0)
    for sx in (-1, 1):
        box("asa_%d" % sx, (0.02, 0.03, 0.18), (sx * 0.13, -0.005, 0), mat="oro", bevel=0.005)
    # Coloca todo en su lugar del pivote (Godot: posición (0, 0.1, −0.1), giro −30° en x)
    from mathutils import Matrix
    T = Matrix.Translation(Vector(G(0, 0.1, -0.1))) @ Matrix.Rotation(math.radians(-30), 4, "X")
    for ob in bk.PARTS:
        ob.matrix_world = T @ ob.matrix_world
    finish("tableta", (0.6, 0.8, 0.4), G(0, 0.1, -0.1))


def lanza():
    start(7)
    # Asta a lo largo de z (Godot) de 0.5 a −1.4; punta en −1.55 hacia −z
    cyl("asta", 0.022, 1.9, G(0, 0, -0.45), (90, 0, 0), mat="madera", verts=10)
    for k in range(4):
        cyl("tira_%d" % k, 0.026, 0.03, G(0, 0, 0.1 - k * 0.05), (90, 0, 0), mat="cuero", verts=10)
    cyl("anillo", 0.035, 0.06, G(0, 0, -1.38), (90, 0, 0), mat="acero_oscuro", verts=14)
    cyl("anillo_luz", 0.036, 0.012, G(0, 0, -1.38), (90, 0, 0), mat="cian", verts=14, bevel=0)
    blade("punta", G(0, 0, -1.4), G(0, 0, -1.72), 0.07, 0.014, G(1, 0, 0), mat="acero", fuller="cian", taper=0.6)
    cyl("regaton", 0.025, 0.06, G(0, 0, 0.52), (90, 0, 0), mat="acero", verts=10, r2=0.012)
    finish("lanza", (1.6, 1.4, 0.6), G(0, 0, -0.6))


def arco():
    start(8)
    # Brazos en el plano yz (Godot): puntas en y ±0.6, el centro adelantado
    pts = []
    for k in range(13):
        a = math.radians(-60 + k * 10)
        pts.append(G(0, math.sin(a) * 0.62, -math.cos(a) * 0.25 + 0.15))
    radii = [0.012 + 0.018 * (1 - abs(k - 6) / 6) for k in range(13)]
    limb("brazos", pts, radii, mat="madera", verts=8)
    for s in (-1, 1):
        a = math.radians(60 * s)
        tip = Vector(G(0, math.sin(a) * 0.62, -math.cos(a) * 0.25 + 0.15))
        limb("recurva_%d" % s, [tuple(tip), tuple(tip + Vector(G(0, s * 0.05, -0.04)))], [0.012, 0.006], mat="acero", verts=6)
    box("empunadura", S(0.05, 0.14, 0.05), G(0, 0, -0.1), mat="cuero", bevel=0.01)
    box("placa", S(0.02, 0.22, 0.03), G(0.025, 0, -0.1), mat="acero_oscuro", bevel=0.005)
    box("mira", S(0.008, 0.08, 0.008), G(0.037, 0.02, -0.1), mat="cian", bevel=0)
    t1 = Vector(G(0, math.sin(math.radians(60)) * 0.62, -math.cos(math.radians(60)) * 0.25 + 0.15))
    t2 = Vector(G(0, -math.sin(math.radians(60)) * 0.62, -math.cos(math.radians(60)) * 0.25 + 0.15))
    cable("cuerda", [tuple(t1), tuple((t1 + t2) / 2), tuple(t2)], 0.003, mat="cuerda", sag=0.0)
    finish("arco", (1.4, 0.6, 0.4), G(0, 0, 0))


# ---------------------------------------------------------------- armas del mercader

def katana_plasma():
    start(11)
    # Tipo espada: empuñadura en y −0.18..0.1, tsuba en y 0.12, hoja hasta y 1.1 (filo hacia +z)
    cyl("tsuka", 0.021, 0.28, G(0, -0.04, 0), mat="seda_negra", verts=12)
    for k in range(8):
        box("ito_%d" % k, S(0.046, 0.012, 0.046), G(0, -0.15 + k * 0.034, 0), (0, 45, 0), mat="acero_oscuro", bevel=0.004)
    cyl("kashira", 0.024, 0.03, G(0, -0.19, 0), mat="oro", verts=12)
    cyl("tsuba", 0.06, 0.012, G(0, 0.11, 0), mat="oro", verts=24, bevel=0.003)
    cyl("tsuba_anillo", 0.062, 0.006, G(0, 0.11, 0), mat="plasma", verts=24, bevel=0)
    cyl("habaki", 0.02, 0.04, G(0, 0.14, 0), mat="oro", verts=10)
    # Hoja ligeramente curva: tramos con su filo de plasma
    prev = Vector(G(0, 0.15, 0))
    for k in range(6):
        t = (k + 1) / 6
        cur = Vector(G(0, 0.15 + t * 0.95, 0.06 * t * t))
        blade("hoja_%d" % k, tuple(prev), tuple(cur), 0.045 - t * 0.012, 0.009, G(0, 0, 1), mat="acero_liso", taper=0.85 if k < 5 else 0.1)
        prev = cur
    cable("filo_plasma", [G(0, 0.16, -0.024), G(0, 0.6, -0.012), G(0, 1.08, 0.04)], 0.004, mat="plasma", sag=0.0)
    finish("katana_plasma", (1.0, 1.4, 0.7), G(0, 0.5, 0))


def espada_cortafuegos():
    start(12)
    cyl("empunadura", 0.024, 0.2, G(0, -0.02, 0), mat="cuero", verts=12)
    sphere("pomo", 0.04, G(0, -0.15, 0), (1, 1, 0.8), mat="acero_negro", segs=14)
    box("guarda", S(0.07, 0.06, 0.36), G(0, 0.11, 0), mat="acero_negro", bevel=0.01)
    for k in range(4):
        box("rejilla_%d" % k, S(0.072, 0.008, 0.25), G(0, 0.09 + k * 0.012, 0), mat="lava", bevel=0)
    blade("hoja", G(0, 0.14, 0), G(0, 1.12, 0), 0.12, 0.018, (0, 1, 0), mat="rojo_oscuro", fuller="lava", taper=0.5)
    for k in range(5):
        box("grieta_%d" % k, S(0.005, 0.1, 0.02), G(0, 0.3 + k * 0.16, (-1) ** k * 0.025), (0, 0, (-1) ** k * 25), mat="lava", bevel=0)
    finish("espada_cortafuegos", (1.0, 1.4, 0.7), G(0, 0.5, 0))


def mandoble():
    start(13)
    # Tipo mazo (se agarra igual que el martillo): mango y −0.15..0.25, hoja hasta y 1.65
    cyl("empunadura", 0.026, 0.42, G(0, 0.04, 0), mat="cuero", verts=12)
    for k in range(7):
        cyl("tira_%d" % k, 0.029, 0.018, G(0, -0.12 + k * 0.05, 0), (0, 0, k * 18), mat="oro", verts=12)
    sphere("pomo", 0.05, G(0, -0.2, 0), (1, 1, 1.2), mat="oro", segs=16)
    box("guarda", S(0.08, 0.07, 0.5), G(0, 0.28, 0), mat="oro", bevel=0.015)
    for sgn in (-1, 1):
        limb("guarda_cuerno_%d" % sgn, [G(0, 0.28, sgn * 0.24), G(0, 0.34, sgn * 0.3), G(0, 0.42, sgn * 0.29)], [0.03, 0.02, 0.006], mat="oro", verts=8)
    cyl("gema", 0.03, 0.09, G(0, 0.28, 0), (0, 90, 0), mat="naranja", verts=14)
    blade("hoja", G(0, 0.31, 0), G(0, 1.65, 0), 0.15, 0.022, (0, 1, 0), mat="acero_negro", fuller="oro", taper=0.55)
    finish("mandoble", (1.6, 2.0, 1.2), G(0, 0.8, 0))


def hacha_servidor():
    start(14)
    # Tipo mazo: mango y −0.08..0.95; cabeza (puerta de rack) en y 0.82 hacia −z
    cyl("mango", 0.03, 1.05, G(0, 0.42, 0), mat="acero_oscuro", verts=12)
    for k in range(5):
        cyl("cinta_%d" % k, 0.034, 0.025, G(0, -0.04 + k * 0.035, 0), (0, 0, k * 15), mat="cuero", verts=12)
    box("cabeza", S(0.05, 0.32, 0.36), G(0, 0.82, -0.17), mat="rack", bevel=0.012)
    for k in range(6):
        box("ventila_%d" % k, S(0.054, 0.012, 0.2), G(0, 0.72 + k * 0.035, -0.15), mat="acero_oscuro", bevel=0)
    for k in range(4):
        box("led_%d" % k, S(0.056, 0.012, 0.012), G(0, 0.7 + k * 0.05, -0.3), mat="hielo" if k % 2 else "cian", bevel=0)
    blade("filo", G(0, 0.66, -0.36), G(0, 0.98, -0.36), 0.05, 0.03, G(0, 0, 1), mat="acero_liso", taper=0.9)
    cable("rayo", [G(0, 0.66, -0.38), G(0, 0.78, -0.4), G(0, 0.86, -0.37), G(0, 0.98, -0.39)], 0.004, mat="hielo", sag=0.0)
    box("contrapeso", S(0.06, 0.12, 0.1), G(0, 0.82, 0.06), mat="acero_oscuro", bevel=0.01)
    finish("hacha_servidor", (1.2, 1.6, 1.2), G(0, 0.6, 0))


def alabarda():
    start(15)
    # Tipo lanza: asta a lo largo de −z (Godot) de 0.5 a −1.6; cabeza en −1.6..−2.05
    cyl("asta", 0.022, 2.1, G(0, 0, -0.55), (90, 0, 0), mat="acero_oscuro", verts=10)
    for k in range(5):
        cyl("tira_%d" % k, 0.026, 0.03, G(0, 0, 0.1 - k * 0.05), (90, 0, 0), mat="cuero", verts=10)
    for k in range(3):
        cable("fibra_%d" % k, [G(0.024 * math.cos(k * 2.1), 0.024 * math.sin(k * 2.1), 0.3), G(0.026 * math.cos(k * 2.1 + 1), 0.026 * math.sin(k * 2.1 + 1), -0.6), G(0.024 * math.cos(k * 2.1 + 2), 0.024 * math.sin(k * 2.1 + 2), -1.55)],
              0.0035, mat="hielo" if k != 1 else "plasma", sag=0.0)
    cyl("cubo", 0.04, 0.12, G(0, 0, -1.6), (90, 0, 0), mat="acero", verts=14)
    blade("punta", G(0, 0, -1.66), G(0, 0, -2.08), 0.07, 0.014, G(1, 0, 0), mat="acero_liso", fuller="hielo", taper=0.5)
    # Hoja de hacha a un lado y pico al otro
    box("hacha", S(0.012, 0.26, 0.22), G(0, 0.13, -1.72), mat="acero", bevel=0.01)
    blade("filo_hacha", G(0, 0.26, -1.6), G(0, 0.26, -1.86), 0.04, 0.014, G(0, 1, 0), mat="acero_liso", taper=0.9)
    limb("pico", [G(0, -0.02, -1.7), G(0, -0.14, -1.72), G(0, -0.22, -1.66)], [0.02, 0.012, 0.002], mat="acero", verts=6)
    cyl("regaton", 0.025, 0.06, G(0, 0, 0.52), (90, 0, 0), mat="acero", verts=10, r2=0.012)
    finish("alabarda", (1.8, 1.6, 0.8), G(0, 0, -0.8))


def estoque_cuantico():
    start(16)
    # Tipo estoque: empuñadura en z 0.04, cazoleta en −0.05, hoja hasta −1.1
    cyl("empunadura", 0.018, 0.14, G(0, 0, 0.04), (90, 0, 0), mat="seda_negra", verts=12)
    sphere("pomo", 0.032, G(0, 0, 0.13), mat="violeta", segs=12)
    sphere("cazoleta", 0.065, G(0, 0, -0.06), (1, 1, 0.45), mat="oro", segs=20)
    for k in range(4):
        a = k / 4 * math.tau
        cable("lazo_%d" % k, [G(0.06 * math.cos(a), 0.06 * math.sin(a), -0.05), G(0.04 * math.cos(a + 0.6), 0.04 * math.sin(a + 0.6), 0.04), G(0, 0, 0.1)], 0.004, mat="oro", sag=0.0)
    blade("hoja", G(0, 0, -0.08), G(0, 0, -1.1), 0.02, 0.008, G(1, 0, 0), mat="acero_liso", fuller="violeta", taper=0.5)
    # Hoja "fantasma" desplazada (superposición cuántica)
    blade("fantasma", G(0.03, 0.02, -0.15), G(0.04, 0.03, -1.05), 0.012, 0.004, G(1, 0, 0), mat="violeta", taper=0.4)
    for k in range(5):
        sphere("particula_%d" % k, 0.008, G(0.05 * math.sin(k * 1.7), 0.04 * math.cos(k * 1.3), -0.25 - k * 0.17), mat="violeta", segs=6)
    finish("estoque_cuantico", (0.9, 0.8, 0.5), G(0, 0, -0.45))


for name, fn in (("katana_plasma", katana_plasma), ("espada_cortafuegos", espada_cortafuegos), ("mandoble", mandoble),
                 ("hacha_servidor", hacha_servidor), ("alabarda", alabarda), ("estoque_cuantico", estoque_cuantico)):
    if not ONLY or name in ONLY:
        fn()

for name, fn in (("espada", espada), ("escudo", escudo), ("estoque", estoque), ("baston", baston), ("mazo", mazo),
                 ("tableta", tableta), ("lanza", lanza), ("arco", arco)):
    if not ONLY or name in ONLY:
        fn()
print("LISTO", OUT)
