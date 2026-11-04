"""
Autobús urbano piso bajo (estilo Circuito Metropolitano) CON INTERIOR, para Blender 4.x / 5.x
y exportación a Godot (.glb).

Uso: Blender > Scripting > abrir > Run Script
     o: blender --background --python autobus_metropolitano.py -- [salida.glb]

Ejes (Blender): frente +X, lado derecho/puertas -Y, arriba +Z, suelo en Z=0.
En Godot queda: frente +X, puertas +Z, arriba +Y (sin girar nada).

Nodos que usa la intro de Godot:
  PuertaDel_A / PuertaDel_B   hojas de la puerta delantera
  PuertaTra_A / PuertaTra_B   hojas de la puerta trasera
  Rueda_DI / Rueda_DD / Rueda_TI / Rueda_TD   ruedas (giran sobre su eje)
"""
import bpy, bmesh, math, sys
from mathutils import Vector

L, W = 12.0, 2.55
Z0, Z1 = 0.28, 3.40          # base y techo de la carrocería
WALL = 0.06
FLOOR = 0.38                 # piso interior (bus_floor_height en Godot)
WHEEL_R, WHEEL_W = 0.50, 0.30
FRONT_AXLE, REAR_AXLE = 3.55, -2.45
FRONT_DOOR, REAR_DOOR, DOOR_W = 4.95, 0.15, 1.24
DOOR_TOP = 2.72
WIN_Z0, WIN_Z1 = 1.35, 2.60

# ---------------------------------------------------------------- limpieza
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()
for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.curves):
    for b in list(block):
        if b.users == 0:
            block.remove(b)
col = bpy.data.collections.new("Autobus_Metropolitano")
bpy.context.scene.collection.children.link(col)


def link(o):
    for c in list(o.users_collection):
        c.objects.unlink(o)
    col.objects.link(o)
    return o


# ---------------------------------------------------------------- materiales
def mat(name, color, rough=0.4, metal=0.0, emit=None, strength=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit:
        p.inputs["Emission Color"].default_value = (*emit, 1)
        p.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        p.inputs["Alpha"].default_value = alpha
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = 'BLENDED'
        else:
            m.blend_method = 'BLEND'
    return m


M_BLUE   = mat("Carroceria_Azul", (0.02, 0.18, 0.62), 0.25, 0.15)
M_INNER  = mat("Interior_Paredes", (0.62, 0.64, 0.66), 0.6)
M_GLASS  = mat("Vidrio", (0.05, 0.07, 0.09), 0.05, 0.3, alpha=0.32)
M_DOORGL = mat("Vidrio_Puerta", (0.03, 0.04, 0.05), 0.05, 0.3, alpha=0.5)
M_BLACK  = mat("Negro_Mate", (0.01, 0.01, 0.01), 0.7)
M_FLOOR  = mat("Piso_Interior", (0.09, 0.09, 0.1), 0.85)
M_SEAT   = mat("Asiento_Tela", (0.03, 0.09, 0.32), 0.9)
M_SEATSH = mat("Asiento_Casco", (0.2, 0.21, 0.23), 0.5)
M_POLE   = mat("Tubo_Amarillo", (0.95, 0.65, 0.02), 0.35, 0.3)
M_CEIL_L = mat("Luz_Techo", (1, 1, 1), 0.3, 0, (1, 0.95, 0.85), 4.0)
M_TIRE   = mat("Llanta", (0.015, 0.015, 0.015), 0.9)
M_RIM    = mat("Rin", (0.75, 0.75, 0.78), 0.25, 1.0)
M_GREY   = mat("Gris", (0.25, 0.27, 0.3), 0.5, 0.2)
M_LIGHT  = mat("Faro", (1, 1, 1), 0.1, 0, (1, 0.98, 0.9), 3.0)
M_TAIL   = mat("Calavera", (0.6, 0.0, 0.0), 0.2, 0, (1, 0.05, 0.02), 2.0)
M_AMBER  = mat("Direccional", (1, 0.45, 0.0), 0.2, 0, (1, 0.45, 0), 1.5)
M_SIGN   = mat("Letrero_LED", (1, 0.6, 0.1), 0.3, 0, (1, 0.55, 0.08), 6.0)
M_WHITE  = mat("Blanco", (0.95, 0.95, 0.95), 0.4)


def make_swirl_texture(w=1024, h=256):
    img = bpy.data.images.new("Librea_Remolinos", w, h, alpha=True)
    px = [0.0] * (w * h * 4)
    cell, k = 64, 3.2
    for y in range(h):
        for x in range(w):
            fx = x / w
            cx, cy = (x % cell) - cell / 2, (y % cell) - cell / 2
            r = math.hypot(cx, cy)
            a = math.atan2(cy, cx)
            d = (r - k * (a + math.pi)) % (k * 2 * math.pi)
            line = min(d, k * 2 * math.pi - d)
            if line < 2.2 and r < cell * 0.45:
                fade = 1.0 if fx < 0.7 else max(0.0, 1 - (fx - 0.7) / 0.3)
                if fade > 0.5:
                    i = (y * w + x) * 4
                    px[i:i + 4] = (0.55, 0.78, 1.0, 1.0)
    img.pixels = px
    img.pack()
    return img


def livery_mat():
    m = bpy.data.materials.new("Librea_Lateral")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.3
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = make_swirl_texture()
    nt.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    # recorte alfa (glTF: alphaMode MASK)
    cmp_ = nt.nodes.new("ShaderNodeMath")
    cmp_.operation = 'ROUND'
    nt.links.new(tex.outputs["Alpha"], cmp_.inputs[0])
    nt.links.new(cmp_.outputs[0], p.inputs["Alpha"])
    if hasattr(m, "surface_render_method"):
        m.surface_render_method = 'DITHERED'
    else:
        m.blend_method = 'CLIP'
    return m


M_LIVERY = livery_mat()


# ---------------------------------------------------------------- utilidades
def box(name, center, size, material, bevel=0.0, segs=3, apply=True):
    bpy.ops.mesh.primitive_cube_add(location=center)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if material:
        o.data.materials.append(material)
    if bevel:
        b = o.modifiers.new("Bevel", 'BEVEL')
        b.width = bevel
        b.segments = segs
        b.limit_method = 'ANGLE'
        if apply:
            bpy.ops.object.modifier_apply(modifier="Bevel")
        bpy.ops.object.shade_smooth_by_angle() if hasattr(bpy.ops.object, "shade_smooth_by_angle") else bpy.ops.object.shade_smooth()
    return link(o)


def span(name, x0, x1, y0, y1, z0, z1, material, bevel=0.0):
    return box(name, ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
               (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)), material, bevel)


def cyl(name, loc, r, depth, rot, material, verts=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    return link(o)


def text(name, body, loc, rot, size, material):
    bpy.ops.object.text_add(location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.body = body
    o.data.size = size
    o.data.align_x = 'CENTER'
    o.data.align_y = 'CENTER'
    o.data.extrude = 0.002
    o.data.materials.append(material)
    link(o)
    bpy.ops.object.convert(target='MESH')   # el texto viaja como malla en el .glb
    return bpy.context.active_object


def boolean(target, cutters, op='DIFFERENCE'):
    bpy.context.view_layer.objects.active = target
    for i, c in enumerate(cutters):
        m = target.modifiers.new(f"B{i}", 'BOOLEAN')
        m.object = c
        m.operation = op
        m.solver = 'EXACT'
        if hasattr(m, "material_mode"):
            m.material_mode = 'TRANSFER'
        bpy.ops.object.modifier_apply(modifier=m.name)


def parent(child, par):
    child.parent = par
    child.matrix_parent_inverse = par.matrix_world.inverted()


def delete(objs):
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)


# ================================================================= CARROCERÍA
shell = span("Carroceria", -L / 2, L / 2, -W / 2, W / 2, Z0, Z1, M_BLUE, bevel=0.14)
inner = span("tmp_interior", -L / 2 + WALL, L / 2 - WALL, -W / 2 + WALL, W / 2 - WALL,
             -0.5, Z1 - WALL, M_INNER, bevel=0.08)

cut = []
yo = W / 2 + 0.3
# ventanas izquierda (+Y)
for i, (a, b) in enumerate([(-5.6, -4.3), (-4.2, -2.9), (-2.8, -1.5), (-1.4, -0.1), (0.0, 1.3),
                            (1.4, 2.7), (2.8, 4.1), (4.2, 5.5)]):
    cut.append(span(f"tmp_vi{i}", a, b, 0.0, yo, WIN_Z0, WIN_Z1, M_BLACK))
# ventanas derecha (-Y), sin las zonas de puertas
right_windows = [(-5.6, -4.3), (-4.2, -2.9), (-2.8, -1.5), (-1.4, -0.65), (0.95, 2.1), (2.2, 3.3), (3.4, 4.15)]
for i, (a, b) in enumerate(right_windows):
    cut.append(span(f"tmp_vd{i}", a, b, -yo, 0.0, WIN_Z0, WIN_Z1, M_BLACK))
# huecos de puertas
for i, cx in enumerate([FRONT_DOOR, REAR_DOOR]):
    cut.append(span(f"tmp_pu{i}", cx - DOOR_W / 2, cx + DOOR_W / 2, -yo, 0.0, Z0 - 0.1, DOOR_TOP, M_BLACK))
# parabrisas y ventana trasera
cut.append(span("tmp_parabrisas", L / 2 - 0.3, L / 2 + 0.3, -1.12, 1.12, 1.05, 3.02, M_BLACK))
cut.append(span("tmp_trasera", -L / 2 - 0.3, -L / 2 + 0.3, -0.95, 0.95, 1.6, 2.6, M_BLACK))
# pasos de rueda
arches = []
for ax in (FRONT_AXLE, REAR_AXLE):
    arches.append(cyl(f"tmp_arco{ax}", (ax, 0, WHEEL_R + 0.02), WHEEL_R + 0.12, W + 0.6,
                      (math.radians(90), 0, 0), M_BLACK, 48))

boolean(shell, [inner] + cut + arches)
delete([inner] + cut)

# piso interior (también recortado por los arcos)
floor = span("Piso", -L / 2 + 0.05, L / 2 - 0.05, -W / 2 + 0.03, W / 2 - 0.03, Z0, FLOOR, M_FLOOR)
boolean(floor, arches)
delete(arches)

# librea de remolinos (solo mitad trasera)
for s, side in ((-1, "Der"), (1, "Izq")):
    bpy.ops.mesh.primitive_plane_add(location=(-3.45, s * (W / 2 + 0.004), 0.88),
                                     rotation=(math.radians(90 if s < 0 else -90), 0, 0))
    p = bpy.context.active_object
    p.name = f"Librea_{side}"
    p.scale = (2.45, 0.42, 1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    p.data.materials.append(M_LIVERY)
    link(p)
    c = cyl("tmp_c", (REAR_AXLE, 0, WHEEL_R + 0.02), WHEEL_R + 0.12, W + 0.6, (math.radians(90), 0, 0), M_BLACK)
    boolean(p, [c])
    delete([c])

# techo
span("AireAcondicionado", 0.0, 3.2, -0.95, 0.95, Z1 - 0.02, Z1 + 0.34, M_BLUE, bevel=0.12)
span("CarenadoTecho", -5.7, -2.9, -1.1, 1.1, Z1 - 0.02, Z1 + 0.22, M_BLUE, bevel=0.09)

# ================================================================= VIDRIOS
gy = W / 2 - WALL / 2
for i, (a, b) in enumerate([(-5.6, -4.3), (-4.2, -2.9), (-2.8, -1.5), (-1.4, -0.1), (0.0, 1.3),
                            (1.4, 2.7), (2.8, 4.1), (4.2, 5.5)]):
    span(f"Vidrio_I{i}", a, b, gy - 0.01, gy + 0.01, WIN_Z0, WIN_Z1, M_GLASS)
for i, (a, b) in enumerate(right_windows):
    span(f"Vidrio_D{i}", a, b, -gy - 0.01, -gy + 0.01, WIN_Z0, WIN_Z1, M_GLASS)
span("Parabrisas", L / 2 - 0.04, L / 2 - 0.02, -1.12, 1.12, 1.05, 3.02, M_GLASS)
span("VidrioTrasero", -L / 2 + 0.02, -L / 2 + 0.04, -0.95, 0.95, 1.6, 2.6, M_GLASS)

# ================================================================= PUERTAS
dy = -W / 2 - 0.005
for tag, cx in (("Del", FRONT_DOOR), ("Tra", REAR_DOOR)):
    for k, side in (("A", -1), ("B", 1)):
        x = cx + side * DOOR_W / 4
        zc = (FLOOR + DOOR_TOP - 0.02) / 2
        h = DOOR_TOP - 0.02 - FLOOR
        leaf = box(f"Puerta{tag}_{k}", (x, dy, zc), (DOOR_W / 2 - 0.02, 0.03, h), M_DOORGL)
        fw = DOOR_W / 2 - 0.02
        frames = [
            box("m", (x, dy - 0.004, FLOOR + 0.04), (fw, 0.035, 0.08), M_BLACK),
            box("m", (x, dy - 0.004, DOOR_TOP - 0.06), (fw, 0.035, 0.08), M_BLACK),
            box("m", (x - fw / 2 + 0.03, dy - 0.004, zc), (0.06, 0.035, h), M_BLACK),
            box("m", (x + fw / 2 - 0.03, dy - 0.004, zc), (0.06, 0.035, h), M_BLACK),
            box("m", (x, dy - 0.004, FLOOR + 0.95), (fw, 0.035, 0.05), M_BLACK),
        ]
        for j, f in enumerate(frames):
            f.name = f"Puerta{tag}_{k}_marco{j}"
            parent(f, leaf)
    # borde amarillo del escalón
    span(f"Escalon_{tag}", cx - DOOR_W / 2, cx + DOOR_W / 2, -W / 2 + 0.03, -W / 2 + 0.12,
         FLOOR - 0.005, FLOOR + 0.004, M_POLE)

# ================================================================= INTERIOR
IW = W / 2 - WALL
# pasos de rueda interiores
for ax in (FRONT_AXLE, REAR_AXLE):
    for s in (1, -1):
        y0, y1 = s * IW, s * 0.6
        span(f"CajaRueda_{ax}_{s}", ax - 0.72, ax + 0.72, min(y0, y1), max(y0, y1), Z0, 1.18, M_SEATSH, bevel=0.03)


def seat(name, x, y, z=FLOOR, facing=1):
    c = box(f"{name}_cojin", (x, y, z + 0.44), (0.44, 0.42, 0.09), M_SEAT, bevel=0.02)
    b = box(f"{name}_respaldo", (x - facing * 0.2, y, z + 0.76), (0.07, 0.42, 0.56), M_SEAT, bevel=0.02)
    leg = box(f"{name}_base", (x, y, z + 0.2), (0.3, 0.06, 0.4), M_SEATSH)
    return c, b, leg


def on_wheel(x):
    return any(abs(x - ax) < 0.75 for ax in (FRONT_AXLE, REAR_AXLE))


ys = (0.995, 0.565)
n = 0
for x in [-4.9 + 0.8 * i for i in range(12)]:
    z = FLOOR + 0.8 if on_wheel(x) else FLOOR
    for y in ys:                                    # lado izquierdo
        seat(f"Asiento{n}", x, y, z); n += 1
    if -1.2 < x < 1.35 or x > 3.9:                  # zonas de puertas (lado derecho)
        continue
    for y in ys:
        seat(f"Asiento{n}", x, -y, z); n += 1
for y in (-1.0, -0.5, 0.0, 0.5, 1.0):               # banca trasera
    seat(f"Banca{n}", -5.55, y, FLOOR + 0.3); n += 1
span("BancaTarima", -5.94, -5.25, -IW, IW, FLOOR, FLOOR + 0.3, M_SEATSH)

# tubos
for i, (x, y) in enumerate([(-4.5, 0.36), (-2.9, -0.36), (-1.3, 0.36), (1.5, -0.36), (3.1, 0.36),
                            (-0.6, -1.0), (0.9, -1.0), (4.25, -1.0), (5.62, -1.0), (2.3, 0.36)]):
    cyl(f"Tubo_V{i}", (x, y, (FLOOR + Z1 - WALL) / 2), 0.022, Z1 - WALL - FLOOR, (0, 0, 0), M_POLE, 12)
for s in (1, -1):
    cyl(f"Tubo_H{s}", (-0.5, s * 0.36, 2.5), 0.02, 10.0, (0, math.radians(90), 0), M_POLE, 12)
# luces de techo
for s in (1, -1):
    span(f"LuzTecho_{s}", -5.5, 5.0, s * 0.7, s * 0.82, Z1 - WALL - 0.03, Z1 - WALL, M_CEIL_L)

# puesto del conductor (lado izquierdo, +Y)
seat("Conductor", 5.15, 0.68)
span("Tablero", 5.55, L / 2 - WALL, -IW, IW, FLOOR, 1.12, M_BLACK, bevel=0.03)
bpy.ops.mesh.primitive_torus_add(major_radius=0.2, minor_radius=0.025, location=(5.42, 0.68, 1.28),
                                 rotation=(0, math.radians(-60), 0))
vol = bpy.context.active_object
vol.name = "Volante"
vol.data.materials.append(M_BLACK)
link(vol)
span("Mampara", 4.68, 4.71, 0.3, IW, FLOOR, 1.75, M_GLASS)
span("Mampara_Base", 4.68, 4.72, 0.3, IW, FLOOR, 1.0, M_SEATSH)
span("Validador", 5.3, 5.5, -0.15, 0.05, FLOOR, 1.25, M_GREY, bevel=0.02)

# ================================================================= EXTERIOR
fx = L / 2
span("LetreroMarco", fx - 0.02, fx + 0.04, -1.05, 1.05, 3.04, 3.34, M_BLACK)
text("Letrero_Ruta", "METROPOLITANO", (fx + 0.045, 0, 3.19), (math.radians(90), 0, math.radians(90)), 0.22, M_SIGN)
text("Numero_Frente", "CH 001", (fx + 0.005, 0.75, 0.9), (math.radians(90), 0, math.radians(90)), 0.10, M_BLACK)
span("Defensa", fx - 0.05, fx + 0.1, -W / 2 + 0.02, W / 2 - 0.02, 0.25, 0.6, M_BLACK, bevel=0.04)
for s in (1, -1):
    box(f"Faro_{s}", (fx + 0.005, s * 0.95, 0.8), (0.04, 0.42, 0.14), M_LIGHT, bevel=0.02)
    box(f"Direccional_{s}", (fx + 0.005, s * 1.12, 0.95), (0.04, 0.12, 0.06), M_AMBER)
    box(f"EspejoBrazoA_{s}", (fx + 0.2, s * (W / 2 - 0.05), 3.2), (0.45, 0.05, 0.05), M_BLACK)
    box(f"EspejoBrazoB_{s}", (fx + 0.4, s * (W / 2 + 0.07), 3.2), (0.05, 0.3, 0.05), M_BLACK)
    box(f"EspejoBrazoC_{s}", (fx + 0.4, s * (W / 2 + 0.2), 3.0), (0.05, 0.05, 0.4), M_BLACK)
    box(f"Espejo_{s}", (fx + 0.4, s * (W / 2 + 0.2), 2.6), (0.07, 0.24, 0.48), M_BLACK, bevel=0.03)
rx = -L / 2
span("RejillaMotor", rx - 0.02, rx + 0.01, -0.9, 0.9, 0.85, 1.45, M_GREY)
span("DefensaTrasera", rx - 0.08, rx + 0.05, -W / 2 + 0.02, W / 2 - 0.02, 0.25, 0.55, M_BLACK, bevel=0.04)
for s in (1, -1):
    box(f"Calavera_{s}", (rx - 0.005, s * 1.1, 1.3), (0.04, 0.16, 0.6), M_TAIL, bevel=0.02)
text("Numero_Trasero", "CH 001", (rx - 0.01, 0, 2.85), (math.radians(90), 0, math.radians(-90)), 0.16, M_WHITE)
text("Letrero_Lateral", "METROP", (3.75, -(W / 2 + 0.008), 2.45), (math.radians(90), 0, 0), 0.14, M_SIGN)
text("Numero_Lateral_D", "CH 001", (3.8, -(W / 2 + 0.01), 1.1), (math.radians(90), 0, 0), 0.12, M_WHITE)
text("Numero_Lateral_I", "CH 001", (3.8, W / 2 + 0.01, 1.1), (math.radians(90), 0, math.radians(180)), 0.12, M_WHITE)

# ================================================================= RUEDAS
for ax, tag_ax, dual in ((FRONT_AXLE, "D", False), (REAR_AXLE, "T", True)):
    for s, tag_s in ((1, "I"), (-1, "D")):
        y = s * (W / 2 - WHEEL_W / 2 - 0.04)
        bpy.ops.object.empty_add(type='PLAIN_AXES', location=(ax, y, WHEEL_R))
        hub = link(bpy.context.active_object)
        hub.name = f"Rueda_{tag_ax}{tag_s}"
        parts = [
            cyl("llanta", (ax, y, WHEEL_R), WHEEL_R, WHEEL_W, (math.radians(90), 0, 0), M_TIRE, 40),
            cyl("rin", (ax, y + s * (WHEEL_W / 2 + 0.002), WHEEL_R), WHEEL_R * 0.58, 0.02, (math.radians(90), 0, 0), M_RIM, 32),
            cyl("maza", (ax, y + s * (WHEEL_W / 2 + 0.015), WHEEL_R), WHEEL_R * 0.2, 0.04, (math.radians(90), 0, 0), M_GREY, 16),
        ]
        # birlos: hacen visible el giro
        for b in range(6):
            a = b * math.tau / 6
            parts.append(cyl("birlo", (ax + math.cos(a) * 0.17, y + s * (WHEEL_W / 2 + 0.03), WHEEL_R + math.sin(a) * 0.17),
                             0.025, 0.03, (math.radians(90), 0, 0), M_GREY, 8))
        if dual:
            parts.append(cyl("llanta_int", (ax, y - s * (WHEEL_W + 0.02), WHEEL_R), WHEEL_R, WHEEL_W,
                             (math.radians(90), 0, 0), M_TIRE, 40))
        for j, p in enumerate(parts):
            p.name = f"{hub.name}_{p.name}{j}"
            parent(p, hub)

# ================================================================= RAÍZ
bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
root = link(bpy.context.active_object)
root.name = "Autobus"
for o in col.objects:
    if o is not root and o.parent is None:
        parent(o, root)

# ================================================================= EXPORTAR
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if argv:
    bpy.ops.object.select_all(action='DESELECT')
    for o in col.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=argv[0], export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True)
    print("Exportado:", argv[0])
print("Autobús con interior creado.")
