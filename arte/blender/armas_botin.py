"""
Armas de botín (especiales, épicas y legendarias) para modelos/armas_jugador/.
Blender 4.x / 5.x:  blender --background --python armas_botin.py -- <carpeta_salida>

Convenciones (las mismas que class_kit.gd):
  - El mango (donde va la mano) está en el origen.
  - espada y mazo: la hoja/cabeza apunta a +Z de Blender  (= +Y en Godot).
  - estoque y lanza: la punta apunta a +Y de Blender      (= -Z en Godot).
"""
import bpy, math, sys, os
from mathutils import Vector, Euler

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp/armas"
os.makedirs(OUT, exist_ok=True)

_mats = {}

RAREZA = {
    "especial": (0.25, 0.6, 1.0),
    "epica": (0.72, 0.3, 1.0),
    "legendaria": (1.0, 0.72, 0.22),
}


def limpiar():
    _mats.clear()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for b in (bpy.data.meshes, bpy.data.materials):
        for x in list(b):
            if x.users == 0:
                b.remove(x)


def mat(nombre, color, rough=0.35, metal=0.0, emit=0.0):
    key = (nombre, color, rough, metal, emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(nombre)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit > 0:
        p.inputs["Emission Color"].default_value = (*color, 1)
        p.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


def _fin(o, m, rot=(0, 0, 0)):
    o.rotation_euler = Euler([math.radians(a) for a in rot])
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return o


def box(size, pos, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(location=pos)
    o = bpy.context.active_object
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(m)
    o.rotation_euler = Euler([math.radians(a) for a in rot])
    return o


def cyl(r1, r2, h, pos, m, rot=(0, 0, 0), v=16):
    bpy.ops.mesh.primitive_cone_add(vertices=v, radius1=r1, radius2=r2, depth=h, location=pos)
    return _fin(bpy.context.active_object, m, rot)


def sph(r, pos, m, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=pos, segments=20, ring_count=12)
    o = bpy.context.active_object
    o.scale = scale
    return _fin(o, m)


def toro(R, r, pos, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=pos, major_segments=32, minor_segments=8)
    return _fin(bpy.context.active_object, m, rot)


def hoja(largo, ancho, grueso, base, m, eje="z", punta=0.18, curva=0.0):
    """Hoja con filo en punta (prisma afilado). eje z: crece hacia +Z; eje y: hacia +Y."""
    import bmesh
    me = bpy.data.meshes.new("hoja")
    bm = bmesh.new()
    n = 8
    vs = []
    for i in range(n + 1):
        t = i / n
        h = t * largo
        w = ancho * (1.0 if t < 1 - punta else max(0.02, (1 - t) / punta))
        off = curva * (t * t) * largo
        anillo = [(-w / 2 + off, 0), (0 + off, grueso / 2), (w / 2 + off, 0), (0 + off, -grueso / 2)]
        fila = []
        for (a, b) in anillo:
            if eje == "z":
                fila.append(bm.verts.new((a, b, base + h)))
            else:
                fila.append(bm.verts.new((a, base + h, b)))
        vs.append(fila)
    for i in range(n):
        for k in range(4):
            a, b = vs[i][k], vs[i][(k + 1) % 4]
            c, d = vs[i + 1][(k + 1) % 4], vs[i + 1][k]
            bm.faces.new((a, b, c, d))
    bm.faces.new(list(reversed(vs[0])))
    bm.faces.new(vs[-1])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("hoja", me)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    o.data.materials.append(m)
    return o


def exportar(nombre):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = nombre
    bpy.ops.object.shade_smooth_by_angle() if hasattr(bpy.ops.object, "shade_smooth_by_angle") else None
    path = os.path.join(OUT, nombre + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True)
    print("exportado", path)


# ------------------------------------------------------------------ materiales base
ACERO = lambda: mat("acero", (0.72, 0.74, 0.78), 0.22, 0.95)
NEGRO = lambda: mat("negro", (0.05, 0.05, 0.06), 0.4, 0.7)
CUERO = lambda: mat("cuero", (0.16, 0.09, 0.05), 0.75)
ORO = lambda: mat("oro", (1.0, 0.72, 0.28), 0.25, 1.0)
COBRE = lambda: mat("cobre", (0.85, 0.45, 0.25), 0.3, 1.0)


def glow(rareza, k=4.0, col=None):
    return mat("brillo_" + rareza + str(k) + str(col), col or RAREZA[rareza], 0.3, 0.0, k)


def mango_vertical(largo=0.2, m=None):
    cyl(0.028, 0.03, largo, (0, 0, 0), m or CUERO())
    for i in range(3):
        toro(0.031, 0.006, (0, 0, -largo / 2 + 0.03 + i * (largo - 0.06) / 2), NEGRO())


def mango_frontal(largo=0.16, m=None):
    cyl(0.026, 0.028, largo, (0, 0, 0), m or CUERO(), rot=(90, 0, 0))


# ================================================================== ESPECIALES
def sable_ethernet():
    limpiar()
    r = "especial"
    mango_vertical(0.2, mat("cable", (0.1, 0.35, 0.8), 0.5))
    # guarda: conector RJ45 transparente con pines dorados
    box((0.2, 0.07, 0.07), (0, 0, 0.13), mat("rj45", (0.75, 0.85, 0.95), 0.1, 0.0))
    for i in range(8):
        box((0.008, 0.075, 0.02), (-0.07 + i * 0.02, 0, 0.16), ORO())
    hoja(0.88, 0.065, 0.016, 0.17, ACERO(), "z", 0.2, curva=0.09)
    box((0.006, 0.02, 0.6), (0.012, 0, 0.5), glow(r, 3.0))
    cyl(0.035, 0.02, 0.05, (0, 0, -0.13), NEGRO())
    exportar("sable_ethernet")


def mazo_disco_duro():
    limpiar()
    r = "especial"
    cyl(0.032, 0.034, 1.0, (0, 0, 0.42), NEGRO())
    for z in (0.02, 0.1, 0.18):
        toro(0.036, 0.007, (0, 0, z), CUERO())
    # carcasa del disco con el plato y el brazo de lectura
    box((0.42, 0.3, 0.07), (0, 0, 1.02), mat("carcasa", (0.55, 0.57, 0.6), 0.3, 0.9), rot=(90, 0, 0))
    cyl(0.12, 0.12, 0.012, (0, -0.04, 1.02), mat("plato", (0.85, 0.87, 0.9), 0.05, 1.0), rot=(90, 0, 0), v=32)
    cyl(0.025, 0.025, 0.02, (0, -0.05, 1.02), glow(r, 4.0), rot=(90, 0, 0))
    box((0.16, 0.012, 0.02), (0.09, -0.05, 1.08), ORO(), rot=(0, 25, 0))
    for sx in (-1, 1):
        box((0.04, 0.32, 0.32), (sx * 0.23, 0, 1.02), NEGRO())
    exportar("mazo_disco_duro")


def lanza_antena():
    limpiar()
    r = "especial"
    cyl(0.024, 0.024, 2.0, (0, -0.4, 0), mat("fibra", (0.2, 0.22, 0.26), 0.4, 0.6), rot=(90, 0, 0))
    for y in (-1.2, -0.6, 0.2):
        toro(0.03, 0.007, (0, y, 0), COBRE(), rot=(90, 0, 0))
    # antena 5G: mástil, anillos de señal y punta brillante
    cyl(0.035, 0.012, 0.32, (0, 0.76, 0), ACERO(), rot=(-90, 0, 0))
    for i, y in enumerate((0.66, 0.75, 0.84)):
        toro(0.07 - i * 0.015, 0.006, (0, y, 0), glow(r, 3.0), rot=(90, 0, 0))
    hoja(0.28, 0.07, 0.018, 0.9, ACERO(), "y", 0.6)
    sph(0.03, (0, 0.92, 0), glow(r, 6.0))
    exportar("lanza_antena")


# ================================================================== ÉPICAS
def estoque_compilador():
    limpiar()
    r = "epica"
    mango_frontal(0.16, mat("grip_morado", (0.18, 0.08, 0.25), 0.6))
    # guarda en forma de < >
    for sx in (-1, 1):
        box((0.12, 0.02, 0.05), (sx * 0.06, -0.07, 0), mat("guarda", (0.25, 0.25, 0.3), 0.25, 0.9), rot=(0, 0, sx * 35))
        box((0.12, 0.02, 0.05), (sx * 0.06, -0.11, 0), mat("guarda", (0.25, 0.25, 0.3), 0.25, 0.9), rot=(0, 0, -sx * 35))
    hoja(1.02, 0.03, 0.014, -0.09 + 0.12, ACERO(), "y", 0.25)
    for i in range(7):   # runas de código
        box((0.034, 0.012 + (i % 3) * 0.01, 0.016), (0, 0.15 + i * 0.12, 0), glow(r, 4.0))
    sph(0.04, (0, 0.11, 0), glow(r, 2.0))
    exportar("estoque_compilador")


def guadana_kernel():
    limpiar()
    r = "epica"
    cyl(0.03, 0.03, 1.5, (0, 0, 0.55), mat("asta", (0.12, 0.1, 0.14), 0.5, 0.5))
    for z in (0.0, 0.1, 1.15):
        toro(0.034, 0.008, (0, 0, z), ORO())
    # hoja curva hecha de segmentos, con filo rojo-morado brillante
    base = Vector((0, 0, 1.28))
    for i in range(9):
        a = math.radians(-10 - i * 13)
        p = base + Vector((math.cos(a) * 0.12 * i * 0.6 + 0.05, 0, math.sin(-a) * 0.03 * i))
        box((0.13, 0.016, 0.1 - i * 0.008), (p.x + 0.06, 0, p.z - i * 0.012), mat("hoja_guadana", (0.2, 0.2, 0.24), 0.2, 0.95), rot=(0, -12 - i * 7, 0))
        box((0.13, 0.02, 0.012), (p.x + 0.06, 0, p.z - i * 0.012 - 0.05 + i * 0.004), glow(r, 5.0, (1.0, 0.25, 0.6)), rot=(0, -12 - i * 7, 0))
    sph(0.06, (0, 0, 1.32), glow(r, 4.0))
    exportar("guadana_kernel")


def espada_neon():
    limpiar()
    r = "epica"
    mango_vertical(0.2, NEGRO())
    box((0.34, 0.06, 0.05), (0, 0, 0.13), NEGRO())
    for sx in (-1, 1):
        box((0.08, 0.04, 0.12), (sx * 0.2, 0, 0.17), glow(r, 3.0), rot=(0, sx * 30, 0))
    hoja(0.95, 0.11, 0.02, 0.16, mat("hoja_oscura", (0.08, 0.06, 0.1), 0.15, 0.9), "z", 0.18)
    for sx in (-1, 1):   # bordes de neón
        box((0.008, 0.024, 0.74), (sx * 0.053, 0, 0.53), glow(r, 6.0, (1.0, 0.3, 0.9)))
    box((0.014, 0.024, 0.6), (0, 0, 0.5), glow(r, 4.0))
    sph(0.035, (0, 0, -0.13), glow(r, 4.0))
    exportar("espada_neon")


# ================================================================== LEGENDARIAS
def excalibyte():
    limpiar()
    r = "legendaria"
    mango_vertical(0.22, mat("grip_azul", (0.06, 0.1, 0.3), 0.6))
    # guarda con alas
    box((0.42, 0.06, 0.05), (0, 0, 0.14), ORO())
    for sx in (-1, 1):
        for k in range(3):
            box((0.1, 0.02, 0.03), (sx * (0.22 + k * 0.05), 0, 0.16 + k * 0.03), ORO(), rot=(0, sx * (20 + k * 12), 0))
    sph(0.04, (0, -0.03, 0.14), mat("gema_azul", (0.2, 0.55, 1.0), 0.05, 0.0, 6.0))
    hoja(1.02, 0.085, 0.02, 0.17, ACERO(), "z", 0.15)
    box((0.016, 0.024, 0.78), (0, 0, 0.56), glow(r, 5.0))   # acanaladura de oro
    for i in range(6):
        box((0.04, 0.026, 0.008), (0, 0, 0.25 + i * 0.12), glow(r, 3.0))
    sph(0.05, (0, 0, -0.14), ORO())
    exportar("excalibyte")


def martillo_singularidad():
    limpiar()
    r = "legendaria"
    cyl(0.034, 0.036, 1.05, (0, 0, 0.42), NEGRO())
    for z in (0.0, 0.1, 0.85):
        toro(0.04, 0.009, (0, 0, z), ORO())
    # núcleo negro (singularidad) dentro de anillos dorados cruzados
    sph(0.15, (0, 0, 1.05), mat("vacio", (0.0, 0.0, 0.0), 0.05, 0.0))
    sph(0.17, (0, 0, 1.05), glow(r, 1.5, (0.55, 0.3, 1.0)), (1, 1, 1))
    for rot in ((90, 0, 0), (0, 90, 0), (45, 45, 0)):
        toro(0.24, 0.018, (0, 0, 1.05), ORO(), rot=rot)
    for sx in (-1, 1):
        cyl(0.11, 0.13, 0.12, (sx * 0.3, 0, 1.05), ORO(), rot=(0, 90, 0))
        cyl(0.08, 0.08, 0.02, (sx * 0.37, 0, 1.05), glow(r, 5.0), rot=(0, 90, 0))
    exportar("martillo_singularidad")


def lanza_tesis():
    limpiar()
    r = "legendaria"
    cyl(0.026, 0.026, 2.1, (0, -0.4, 0), mat("asta_blanca", (0.88, 0.86, 0.8), 0.4, 0.2), rot=(90, 0, 0))
    for y in (-1.3, -0.7, 0.0, 0.5):
        toro(0.032, 0.008, (0, y, 0), ORO(), rot=(90, 0, 0))
    # pergamino enrollado (la tesis) y punta en llamas
    cyl(0.04, 0.04, 0.2, (0, 0.58, 0.07), mat("papel", (0.95, 0.9, 0.75), 0.8), rot=(0, 0, 90))
    box((0.18, 0.004, 0.22), (0, 0.58, -0.04), mat("papel", (0.95, 0.9, 0.75), 0.8))
    cyl(0.05, 0.025, 0.1, (0, 0.72, 0), ORO(), rot=(-90, 0, 0))
    hoja(0.42, 0.09, 0.02, 0.76, ACERO(), "y", 0.55)
    box((0.012, 0.3, 0.024), (0, 0.92, 0), glow(r, 5.0, (1.0, 0.45, 0.1)))
    exportar("lanza_tesis")


def estoque_root():
    limpiar()
    r = "legendaria"
    mango_frontal(0.17, NEGRO())
    # guarda en forma de llave
    toro(0.06, 0.012, (0, -0.1, 0), ORO(), rot=(0, 0, 0))
    for k in range(3):
        box((0.02, 0.02, 0.03 + k * 0.01), (0.03 + k * 0.025, -0.1, -0.06), ORO())
    hoja(1.05, 0.032, 0.015, 0.02, mat("hoja_negra", (0.03, 0.04, 0.03), 0.15, 0.9), "y", 0.22)
    for i in range(9):   # caracteres de terminal en verde
        box((0.036, 0.014, 0.017), (0, 0.1 + i * 0.1, 0), glow(r, 5.0, (0.2, 1.0, 0.35)))
    sph(0.035, (0, -0.1, 0), glow(r, 6.0))
    exportar("estoque_root")


for f in (sable_ethernet, mazo_disco_duro, lanza_antena, estoque_compilador, guadana_kernel,
          espada_neon, excalibyte, martillo_singularidad, lanza_tesis, estoque_root):
    f()
print("LISTO")
