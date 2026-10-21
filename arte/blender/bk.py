"""Kit de modelado para Blender (5.x) usado por los generadores de personajes.

Flujo de cada modelo:
  1. reset()                       escena vacía
  2. piezas: box(), cyl(), panel(), bolts(), cable()... cada pieza con `bone=`
     (hueso al que se pega de forma rígida) y `mat=` (material lógico).
  3. armature(BONES)               esqueleto
  4. finish(name)                  aplica modificadores, une todo, UV, hornea las
                                   texturas (óxido, desgaste, suciedad) y deja
                                   materiales glTF con imágenes.
  5. animate(...)                  acciones (idle, walk, attack...)
  6. export(path)                  .glb con esqueleto y animaciones

Convenciones: Z arriba, el personaje mira hacia +Y (en Godot queda mirando a -Z).
Lado derecho del personaje = +X (huesos *_r), izquierdo = -X (*_l).
"""
import bpy
import bmesh
import math
import os
import random
from mathutils import Vector, Matrix, Euler, Quaternion

PARTS = []          # objetos creados (antes de unir)
MATS = {}           # nombre lógico -> material procedural (para hornear)
ARM = None
RNG = random.Random(7)


# ---------------------------------------------------------------- escena

def reset(seed=7):
    global PARTS, MATS, ARM, RNG
    bpy.ops.wm.read_factory_settings(use_empty=True)
    PARTS = []
    MATS = {}
    ARM = None
    RNG = random.Random(seed)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    try:
        cp = bpy.context.preferences.addons["cycles"].preferences
        cp.compute_device_type = "OPTIX"
        cp.get_devices()
        for d in cp.devices:
            d.use = d.type != "CPU"
        sc.cycles.device = "GPU"
    except Exception as e:
        print("GPU no disponible:", e)
    sc.cycles.samples = 8
    sc.cycles.use_denoising = False


def _link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _obj_from_bm(name, bm):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    return _link(ob)


def _finish_part(ob, loc, rot, bone, mat, bevel, segs, smooth=True):
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    ob["bone"] = bone
    ob["mat"] = mat
    if bevel > 0:
        m = ob.modifiers.new("bisel", "BEVEL")
        m.width = bevel
        m.segments = max(segs, 3)
        m.limit_method = "ANGLE"
        m.angle_limit = math.radians(35)
        m.harden_normals = True
    for p in ob.data.polygons:
        p.use_smooth = smooth
    PARTS.append(ob)
    return ob


def box(name, size, loc, rot=(0, 0, 0), bone="root", mat="pintura", bevel=0.012, segs=2, taper=None):
    """Caja de tamaño `size`. taper=(sx, sy): escala de la cara superior (+Z)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if taper and v.co.z > 0:
            v.co.x *= taper[0]
            v.co.y *= taper[1]
    return _finish_part(_obj_from_bm(name, bm), loc, rot, bone, mat, bevel, segs)


def cyl(name, r, h, loc, rot=(0, 0, 0), bone="root", mat="metal_oscuro", verts=20, bevel=0.006, segs=2, r2=None):
    """Cilindro a lo largo de Z (r2 = radio superior, para conos truncados)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=r, radius2=r if r2 is None else r2, depth=h)
    return _finish_part(_obj_from_bm(name, bm), loc, rot, bone, mat, bevel, segs)


def sphere(name, r, loc, scale=(1, 1, 1), bone="root", mat="metal_oscuro", segs=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(8, segs // 2), radius=r)
    for v in bm.verts:
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
    return _finish_part(_obj_from_bm(name, bm), loc, (0, 0, 0), bone, mat, 0, 0)


def panel(name, size, loc, rot=(0, 0, 0), bone="root", mat="pintura", inset=0.012, depth=0.004, bevel=0.018, taper=None):
    """Placa de blindaje con borde biselado y una línea de panel hundida en su cara frontal (+Y)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if taper and v.co.y > 0:
            v.co.x *= taper[0]
            v.co.z *= taper[1]
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    front = [f for f in bm.faces if f.normal.y > 0.9]
    r = bmesh.ops.inset_individual(bm, faces=front, thickness=inset, depth=0.0)
    r2 = bmesh.ops.inset_individual(bm, faces=front, thickness=0.004, depth=-depth)
    return _finish_part(_obj_from_bm(name, bm), loc, rot, bone, mat, bevel, 2)


def bolts(prefix, positions, normal_rot=(0, 0, 0), bone="root", r=0.009, h=0.008):
    for i, p in enumerate(positions):
        cyl("%s_%d" % (prefix, i), r, h, p, normal_rot, bone=bone, mat="metal", verts=6, bevel=0.002, segs=1)


def vents(prefix, origin, count, spacing, size, rot=(0, 0, 0), bone="root"):
    for i in range(count):
        o = Vector(origin) + Vector((0, 0, -i * spacing))
        box("%s_%d" % (prefix, i), size, tuple(o), rot, bone=bone, mat="metal_oscuro", bevel=0.002, segs=1)


def cable(name, pts, radius=0.012, bone="root", mat="goma", sag=0.0, res=8):
    """Cable como curva con grosor. pts: lista de puntos; sag: cuánto cuelga en medio."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 2
    cu.resolution_u = res
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(pts) - 1)
    n = len(pts)
    for i, p in enumerate(pts):
        bp = sp.bezier_points[i]
        t = i / max(1, n - 1)
        co = Vector(p) + Vector((0, 0, -sag * math.sin(t * math.pi)))
        bp.co = co
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new(name, cu)
    _link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.view_layer.objects.active
    ob.select_set(False)
    ob["bone"] = bone
    ob["mat"] = mat
    for p in ob.data.polygons:
        p.use_smooth = True
    PARTS.append(ob)
    return ob


def label(name, text, loc, rot=(90, 0, 0), size=0.05, depth=0.002, bone="root", mat="acento"):
    """Rótulo de texto en relieve (número de serie, avisos)."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = text
    cu.size = size
    cu.extrude = depth
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new(name, cu)
    _link(ob)
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.view_layer.objects.active
    ob.select_set(False)
    ob["bone"] = bone
    ob["mat"] = mat
    PARTS.append(ob)
    return ob


def hazard(prefix, center, width, height, n, rot=(0, 0, 0), bone="root", depth=0.003):
    """Franjas diagonales de peligro (amarillo/negro) sobre una placa."""
    for i in range(n):
        x = center[0] - width * 0.5 + (i + 0.5) * width / n
        box("%s_%d" % (prefix, i), (width / n * 0.45, depth, height), (x, center[1], center[2]), (rot[0], rot[1] + 35, rot[2]), bone=bone, mat="peligro" if i % 2 == 0 else "metal_oscuro", bevel=0.001, segs=1)


def piston(name, a, b, r=0.018, bone="root"):
    """Pistón hidráulico entre dos puntos (camisa oscura + vástago metálico)."""
    a = Vector(a)
    b = Vector(b)
    d = b - a
    L = d.length
    q = d.normalized().to_track_quat("Z", "Y")
    rot = [math.degrees(x) for x in q.to_euler()]
    mid1 = a + d * 0.3
    mid2 = a + d * 0.72
    cyl(name + "_camisa", r, L * 0.6, tuple(mid1), rot, bone=bone, mat="metal_oscuro", verts=12)
    cyl(name + "_vastago", r * 0.55, L * 0.5, tuple(mid2), rot, bone=bone, mat="metal", verts=10)


def cloth(name, width, height, loc, rot=(0, 0, 0), bone="root", mat="tela", nx=14, ny=12, tatter=0.35, holes=0.04,
          wave=0.02, flare=0.0, thick=0.008, bone2=None, blend=0.0, seed=None):
    """Tela rasgada (tabardo, capa, bata, túnica): plano de `width` x `height` que cuelga
    hacia −Z desde `loc` (borde superior) con la cara al frente (+Y). El borde de abajo
    queda en jirones (`tatter` = largo máximo de los cortes, en fracción de la altura) y
    con agujeros (`holes` = probabilidad por cuadro). `flare` abre la tela hacia +Y abajo.
    bone2/blend: la parte baja sigue a otro hueso (p. ej. el muslo) para que se mueva."""
    rng = random.Random(seed if seed is not None else RNG.random())
    bm = bmesh.new()
    verts = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            u = i / nx
            v = j / ny
            x = (u - 0.5) * width
            z = -v * height
            y = math.sin(u * math.pi * 3.0 + v * 2.0) * wave + flare * v * v
            row.append(bm.verts.new((x, y, z)))
        verts.append(row)
    cut = []
    for i in range(nx):
        c = rng.random() * tatter
        if rng.random() < 0.3:
            c *= 0.3
        cut.append(1.0 - c)
    for j in range(ny):
        for i in range(nx):
            v = (j + 0.5) / ny
            if v > cut[i]:
                continue
            if j > 1 and rng.random() < holes:
                continue
            bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    # Jirones: los vértices del borde se mueven un poco al azar
    for v in bm.verts:
        if v.is_boundary and v.co.z < -height * 0.15:
            v.co.x += (rng.random() - 0.5) * width / nx * 0.6
            v.co.z += (rng.random() - 0.5) * height / ny * 0.8
    ob = _obj_from_bm(name, bm)
    m = ob.modifiers.new("grosor", "SOLIDIFY")
    m.thickness = thick
    m.offset = 0.0
    ob["cloth_h"] = height
    if bone2:
        ob["bone2"] = bone2
        ob["blend"] = blend
    return _finish_part(ob, loc, rot, bone, mat, 0, 0)


def blob(name, r, loc, scale=(1, 1, 1), bone="root", mat="piel", lumps=0.25, segs=24, seed=None):
    """Masa orgánica deforme (músculo, tumor, cabeza): esfera con bultos de ruido."""
    rng = random.Random(seed if seed is not None else RNG.random())
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(8, segs // 2), radius=r)
    ph = [rng.random() * 6.28 for _ in range(6)]
    fq = [rng.uniform(2.0, 4.5) for _ in range(3)]
    for v in bm.verts:
        n = v.co.normalized()
        d = (math.sin(n.x * fq[0] + ph[0]) * math.sin(n.y * fq[1] + ph[1]) * math.sin(n.z * fq[2] + ph[2])
             + 0.5 * math.sin(n.x * fq[1] * 2 + ph[3]) * math.sin(n.z * fq[0] * 2 + ph[4]))
        v.co = v.co * (1.0 + d * lumps)
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
    return _finish_part(_obj_from_bm(name, bm), loc, (0, 0, 0), bone, mat, 0, 0)


def limb(name, pts, radii, bone="root", mat="piel", verts=14, lumps=0.0, seed=None):
    """Tubo orgánico que pasa por `pts` con radio variable `radii` (brazos, patas, colas)."""
    rng = random.Random(seed if seed is not None else RNG.random())
    bm = bmesh.new()
    rings = []
    pts = [Vector(p) for p in pts]
    q = None
    d_prev = None
    for k, p in enumerate(pts):
        d = (pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]).normalized()
        # Marco transportado a lo largo del tubo (sin giros bruscos entre anillos)
        if q is None:
            q = d.to_track_quat("Z", "Y")
        else:
            q = d_prev.rotation_difference(d) @ q
        d_prev = d
        ring = []
        for i in range(verts):
            a = i / verts * 2 * math.pi
            rr = radii[k] * (1.0 + (rng.random() - 0.5) * lumps)
            ring.append(bm.verts.new(p + q @ Vector((math.cos(a) * rr, math.sin(a) * rr, 0))))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(verts):
            a, b = rings[k][i], rings[k][(i + 1) % verts]
            c, d = rings[k + 1][(i + 1) % verts], rings[k + 1][i]
            bm.faces.new((a, b, c, d))
    for ring, p in ((rings[0], pts[0]), (rings[-1], pts[-1])):
        c = bm.verts.new(p)
        for i in range(verts):
            try:
                bm.faces.new((ring[i], ring[(i + 1) % verts], c))
            except ValueError:
                pass
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _finish_part(_obj_from_bm(name, bm), (0, 0, 0), (0, 0, 0), bone, mat, 0, 0)


# ---------------------------------------------------------------- materiales

def _mix(nt, a, b, fac, kind="MIX"):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = kind
    nt.links.new(fac, m.inputs[0])
    if isinstance(a, (tuple, list)):
        m.inputs[6].default_value = a
    else:
        nt.links.new(a, m.inputs[6])
    if isinstance(b, (tuple, list)):
        m.inputs[7].default_value = b
    else:
        nt.links.new(b, m.inputs[7])
    return m.outputs[2]


def _val_mix(nt, a, b, fac):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "FLOAT"
    nt.links.new(fac, m.inputs[0])
    if isinstance(a, (int, float)):
        m.inputs[2].default_value = a
    else:
        nt.links.new(a, m.inputs[2])
    if isinstance(b, (int, float)):
        m.inputs[3].default_value = b
    else:
        nt.links.new(b, m.inputs[3])
    return m.outputs[0]


def _ramp(nt, src, stops):
    r = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(src, r.inputs[0])
    els = r.color_ramp.elements
    els[0].position = stops[0][0]
    els[0].color = stops[0][1]
    els[1].position = stops[-1][0]
    els[1].color = stops[-1][1]
    for pos, col in stops[1:-1]:
        e = els.new(pos)
        e.color = col
    return r.outputs[0]


def _plaid(nt, tc, plaid):
    """Tela a cuadros: (color base, color oscuro, color de línea, cuadros por metro)."""
    base, dark, line, scale = plaid
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])

    def band(axis, width, offset=0.0):
        m = nt.nodes.new("ShaderNodeMath")
        m.operation = "MULTIPLY_ADD"
        m.inputs[1].default_value = scale
        m.inputs[2].default_value = offset
        nt.links.new(sep.outputs[axis], m.inputs[0])
        f = nt.nodes.new("ShaderNodeMath")
        f.operation = "FRACT"
        nt.links.new(m.outputs[0], f.inputs[0])
        lt = nt.nodes.new("ShaderNodeMath")
        lt.operation = "LESS_THAN"
        lt.inputs[1].default_value = width
        nt.links.new(f.outputs[0], lt.inputs[0])
        return lt.outputs[0]

    bx, bz = band("X", 0.38), band("Z", 0.38)
    lx, lz = band("X", 0.05, 0.4), band("Z", 0.05, 0.4)
    either = nt.nodes.new("ShaderNodeMath")
    either.operation = "MAXIMUM"
    nt.links.new(bx, either.inputs[0])
    nt.links.new(bz, either.inputs[1])
    both = nt.nodes.new("ShaderNodeMath")
    both.operation = "MULTIPLY"
    nt.links.new(bx, both.inputs[0])
    nt.links.new(bz, both.inputs[1])
    lines = nt.nodes.new("ShaderNodeMath")
    lines.operation = "MAXIMUM"
    nt.links.new(lx, lines.inputs[0])
    nt.links.new(lz, lines.inputs[1])
    mid = tuple(base[i] * 0.45 + dark[i] * 0.55 for i in range(3)) + (1,)
    col = _mix(nt, tuple(base) + (1,), mid, either.outputs[0])
    col = _mix(nt, col, tuple(dark) + (1,), both.outputs[0])
    lw = nt.nodes.new("ShaderNodeMath")
    lw.operation = "MULTIPLY"
    lw.inputs[1].default_value = 0.7
    nt.links.new(lines.outputs[0], lw.inputs[0])
    return _mix(nt, col, tuple(line) + (1,), lw.outputs[0])


def worn_material(name, base, metal=0.0, rough=0.55, rust=0.5, wear=0.6, dirt=0.5, emissive=None, scratches=True, bare=(0.16, 0.16, 0.17), streaks=0.0, soot=0.0, plaid=None):
    """Material procedural (solo Cycles, para hornear): pintura/metal con desgaste en
    bordes, óxido en cavidades y manchas, suciedad abajo y rayones."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    # Bordes: diferencia entre la normal real y la normal biselada
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = 0.006
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    nt.links.new(bev.outputs[0], dot.inputs[0])
    nt.links.new(geo.outputs["Normal"], dot.inputs[1])
    edge = nt.nodes.new("ShaderNodeMath")
    edge.operation = "SUBTRACT"
    edge.inputs[0].default_value = 1.0
    nt.links.new(dot.outputs["Value"], edge.inputs[1])
    edge_m = nt.nodes.new("ShaderNodeMath")
    edge_m.operation = "MULTIPLY"
    edge_m.use_clamp = True
    edge_m.inputs[1].default_value = 25.0
    nt.links.new(edge.outputs[0], edge_m.inputs[0])
    # Ruido para romper el desgaste
    n1 = nt.nodes.new("ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 18.0
    n1.inputs["Detail"].default_value = 8.0
    nt.links.new(tc.outputs["Object"], n1.inputs["Vector"])
    wear_mask = nt.nodes.new("ShaderNodeMath")
    wear_mask.operation = "MULTIPLY"
    wear_mask.use_clamp = True
    nt.links.new(edge_m.outputs[0], wear_mask.inputs[0])
    wr = _ramp(nt, n1.outputs["Fac"], [(0.35, (0, 0, 0, 1)), (0.6, (wear * 1.6, 0, 0, 1))])
    nt.links.new(wr, wear_mask.inputs[1])
    # Óxido: cavidades (AO) + manchas grandes
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples = 8
    ao.inputs["Distance"].default_value = 0.05
    cav = _ramp(nt, ao.outputs["AO"], [(0.45, (1, 1, 1, 1)), (0.85, (0, 0, 0, 1))])
    n2 = nt.nodes.new("ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 4.0
    n2.inputs["Detail"].default_value = 12.0
    n2.inputs["Roughness"].default_value = 0.7
    nt.links.new(tc.outputs["Object"], n2.inputs["Vector"])
    patches = _ramp(nt, n2.outputs["Fac"], [(0.6 - rust * 0.08, (0, 0, 0, 1)), (0.7 - rust * 0.08, (0.85, 0.85, 0.85, 1))])
    rust_m = nt.nodes.new("ShaderNodeMath")
    rust_m.operation = "MAXIMUM"
    nt.links.new(patches, rust_m.inputs[0])
    cav_s = nt.nodes.new("ShaderNodeMath")
    cav_s.operation = "MULTIPLY"
    cav_s.inputs[1].default_value = rust * 0.8
    nt.links.new(cav, cav_s.inputs[0])
    nt.links.new(cav_s.outputs[0], rust_m.inputs[1])
    rust_amt = nt.nodes.new("ShaderNodeMath")
    rust_amt.operation = "MULTIPLY"
    rust_amt.use_clamp = True
    rust_amt.inputs[1].default_value = rust * 1.1
    nt.links.new(rust_m.outputs[0], rust_amt.inputs[0])
    n3 = nt.nodes.new("ShaderNodeTexNoise")
    n3.inputs["Scale"].default_value = 60.0
    n3.inputs["Detail"].default_value = 4.0
    nt.links.new(tc.outputs["Object"], n3.inputs["Vector"])
    # (colores lineales: el óxido real es oscuro; con valores altos se ve color durazno)
    rust_col = _ramp(nt, n3.outputs["Fac"], [(0.3, (0.1, 0.035, 0.012, 1)), (0.55, (0.22, 0.075, 0.022, 1)), (0.75, (0.34, 0.14, 0.045, 1))])
    # Suciedad: más abajo, más sucio (posición Z en espacio de objeto padre)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    dirt_g = _ramp(nt, sep.outputs["Z"], [(0.0, (dirt, 0, 0, 1)), (0.7, (0, 0, 0, 1))])
    # Rayones
    sc_mask = None
    if scratches:
        wv = nt.nodes.new("ShaderNodeTexWave")
        wv.wave_type = "BANDS"
        wv.inputs["Scale"].default_value = 30.0
        wv.inputs["Distortion"].default_value = 20.0
        wv.inputs["Detail"].default_value = 6.0
        nt.links.new(tc.outputs["Object"], wv.inputs["Vector"])
        sc_mask = _ramp(nt, wv.outputs["Fac"], [(0.0, (1, 1, 1, 1)), (0.04, (0, 0, 0, 1))])
    # Composición del color
    bare = tuple(bare) + (1,)
    base_col = _plaid(nt, tc, plaid) if plaid else tuple(base) + (1,)
    col = _mix(nt, base_col, bare, wear_mask.outputs[0])
    if sc_mask is not None:
        scs = nt.nodes.new("ShaderNodeMath")
        scs.operation = "MULTIPLY"
        scs.inputs[1].default_value = 0.35 * wear
        nt.links.new(sc_mask, scs.inputs[0])
        col = _mix(nt, col, bare, scs.outputs[0])
    col = _mix(nt, col, rust_col, rust_amt.outputs[0])
    # Chorreaduras de óxido: ruido estirado en vertical
    streak_out = None
    if streaks > 0.0:
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (14.0, 14.0, 1.2)
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        ns = nt.nodes.new("ShaderNodeTexNoise")
        ns.inputs["Scale"].default_value = 3.0
        ns.inputs["Detail"].default_value = 6.0
        nt.links.new(mp.outputs[0], ns.inputs["Vector"])
        st = _ramp(nt, ns.outputs["Fac"], [(0.55, (0, 0, 0, 1)), (0.68, (streaks, 0, 0, 1))])
        col = _mix(nt, col, (0.17, 0.06, 0.018, 1), st)
        streak_out = st
    # Hollín y quemaduras: manchas oscuras grandes
    if soot > 0.0:
        nso = nt.nodes.new("ShaderNodeTexNoise")
        nso.inputs["Scale"].default_value = 2.2
        nso.inputs["Detail"].default_value = 10.0
        nso.inputs["Roughness"].default_value = 0.75
        nt.links.new(tc.outputs["Object"], nso.inputs["Vector"])
        sm = _ramp(nt, nso.outputs["Fac"], [(0.58, (0, 0, 0, 1)), (0.72, (soot, 0, 0, 1))])
        col = _mix(nt, col, (0.03, 0.025, 0.02, 1), sm)
    col = _mix(nt, col, (0.12, 0.09, 0.06, 1), dirt_g)
    nt.links.new(col, bsdf.inputs["Base Color"])
    # Rugosidad / metalicidad
    r1 = _val_mix(nt, rough, 0.35, wear_mask.outputs[0])
    r2 = _val_mix(nt, r1, 0.9, rust_amt.outputs[0])
    nt.links.new(r2, bsdf.inputs["Roughness"])
    mt = _val_mix(nt, metal, 1.0, wear_mask.outputs[0])
    mt2 = _val_mix(nt, mt, 0.0, rust_amt.outputs[0])
    nt.links.new(mt2, bsdf.inputs["Metallic"])
    # Relieve: abolladuras y rayones
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    nt.links.new(n3.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bev.outputs[0], bump.inputs["Normal"])
    nt.links.new(bump.outputs[0], bsdf.inputs["Normal"])
    if emissive:
        bsdf.inputs["Emission Color"].default_value = tuple(emissive) + (1,)
        bsdf.inputs["Emission Strength"].default_value = 4.0
    m["metal_val"] = metal
    return m


def skin_material(name, base, veins=0.6, vein_col=(0.18, 0.05, 0.12), blotch=0.5, blotch_col=(0.35, 0.12, 0.1),
                  rough=0.5, wet=0.4, dirt=0.4, scale=1.0, sheen_col=None):
    """Piel orgánica (mutantes, rostros, la piel sintética de los androides): venas
    (Voronoi distorsionado), manchas, cavidades oscuras, partes húmedas y relieve."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    # Venas: bordes de Voronoi con coordenadas torcidas por ruido
    nd = nt.nodes.new("ShaderNodeTexNoise")
    nd.inputs["Scale"].default_value = 3.0 * scale
    nd.inputs["Detail"].default_value = 4.0
    mixv = nt.nodes.new("ShaderNodeVectorMath")
    mixv.operation = "MULTIPLY_ADD"
    nt.links.new(nd.outputs["Color"], mixv.inputs[0])
    mixv.inputs[1].default_value = (0.35, 0.35, 0.35)
    nt.links.new(tc.outputs["Object"], mixv.inputs[2])
    vo = nt.nodes.new("ShaderNodeTexVoronoi")
    vo.feature = "DISTANCE_TO_EDGE"
    vo.inputs["Scale"].default_value = 7.0 * scale
    nt.links.new(mixv.outputs[0], vo.inputs["Vector"])
    # (máscaras en gris: un color (v, 0, 0) usado como factor solo pesa v/3)
    vmask = _ramp(nt, vo.outputs["Distance"], [(0.0, (veins, veins, veins, 1)), (0.04, (0, 0, 0, 1))])
    # Manchas grandes (moretones, necrosis)
    nb = nt.nodes.new("ShaderNodeTexNoise")
    nb.inputs["Scale"].default_value = 2.5 * scale
    nb.inputs["Detail"].default_value = 8.0
    nb.inputs["Roughness"].default_value = 0.65
    nt.links.new(tc.outputs["Object"], nb.inputs["Vector"])
    bmask = _ramp(nt, nb.outputs["Fac"], [(0.48, (0, 0, 0, 1)), (0.66, (blotch, blotch, blotch, 1))])
    # Variación de tono a gran escala (zonas amarillentas / grisáceas)
    nt2 = nt.nodes.new("ShaderNodeTexNoise")
    nt2.inputs["Scale"].default_value = 1.2 * scale
    nt2.inputs["Detail"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], nt2.inputs["Vector"])
    tone = _ramp(nt, nt2.outputs["Fac"], [(0.35, (0, 0, 0, 1)), (0.65, (0.8, 0.8, 0.8, 1))])
    # Poros / textura fina
    nf = nt.nodes.new("ShaderNodeTexNoise")
    nf.inputs["Scale"].default_value = 90.0 * scale
    nf.inputs["Detail"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], nf.inputs["Vector"])
    fine = _ramp(nt, nf.outputs["Fac"], [(0.3, (0.85, 0.85, 0.85, 1)), (0.7, (1.1, 1.1, 1.1, 1))])
    # Cavidades
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples = 8
    ao.inputs["Distance"].default_value = 0.06
    cav = _ramp(nt, ao.outputs["AO"], [(0.35, (0.7, 0.7, 0.7, 1)), (0.85, (0, 0, 0, 1))])
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    dirt_g = _ramp(nt, sep.outputs["Z"], [(0.0, (dirt * 0.6, dirt * 0.6, dirt * 0.6, 1)), (0.6, (0, 0, 0, 1))])
    col = _mix(nt, tuple(base) + (1,), fine, nf.outputs["Fac"], "MULTIPLY")
    alt = (base[0] * 1.35, base[1] * 1.15, base[2] * 0.65, 1)
    col = _mix(nt, col, alt, tone)
    col = _mix(nt, col, tuple(blotch_col) + (1,), bmask)
    col = _mix(nt, col, tuple(vein_col) + (1,), vmask)
    col = _mix(nt, col, (0.05, 0.03, 0.03, 1), cav)
    col = _mix(nt, col, (0.1, 0.08, 0.05, 1), dirt_g)
    nt.links.new(col, bsdf.inputs["Base Color"])
    # Partes húmedas (brillan)
    nw = nt.nodes.new("ShaderNodeTexNoise")
    nw.inputs["Scale"].default_value = 5.0 * scale
    nt.links.new(tc.outputs["Object"], nw.inputs["Vector"])
    wmask = _ramp(nt, nw.outputs["Fac"], [(0.5, (0, 0, 0, 1)), (0.62, (wet, wet, wet, 1))])
    r1 = _val_mix(nt, rough, 0.18, wmask)
    nt.links.new(r1, bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    # Relieve: venas abultadas + poros
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.45
    hsum = nt.nodes.new("ShaderNodeMath")
    hsum.operation = "ADD"
    nt.links.new(vmask, hsum.inputs[0])
    hs2 = nt.nodes.new("ShaderNodeMath")
    hs2.operation = "MULTIPLY"
    hs2.inputs[1].default_value = 0.3
    nt.links.new(nf.outputs["Fac"], hs2.inputs[0])
    nt.links.new(hs2.outputs[0], hsum.inputs[1])
    nt.links.new(hsum.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], bsdf.inputs["Normal"])
    m["metal_val"] = 0.0
    return m


def define_materials(spec):
    """spec: nombre lógico -> kwargs de worn_material (o {'emit': color})."""
    for k, v in spec.items():
        if "emit" in v:
            m = bpy.data.materials.new(k)
            m.use_nodes = True
            b = m.node_tree.nodes["Principled BSDF"]
            b.inputs["Base Color"].default_value = tuple(v["emit"]) + (1,)
            b.inputs["Emission Color"].default_value = tuple(v["emit"]) + (1,)
            b.inputs["Emission Strength"].default_value = v.get("strength", 6.0)
            m["no_bake"] = True
            MATS[k] = m
        elif v.get("skin"):
            kw = dict(v)
            kw.pop("skin")
            MATS[k] = skin_material(k, **kw)
        else:
            MATS[k] = worn_material(k, **v)


# ---------------------------------------------------------------- esqueleto

def armature(bones):
    """bones: lista de (nombre, padre, cabeza, cola). Devuelve el objeto armadura."""
    global ARM
    arm = bpy.data.armatures.new("Esqueleto")
    ob = bpy.data.objects.new("Esqueleto", arm)
    _link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    for n, parent, head, tail in bones:
        eb = arm.edit_bones.new(n)
        eb.head = head
        eb.tail = tail
        eb.roll = 0.0
        if parent:
            eb.parent = arm.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    ARM = ob
    return ob


# ---------------------------------------------------------------- unir y hornear

def finish(name, tex_size=2048, bake=True, out_dir=None):
    """Aplica modificadores, une todas las piezas en una malla con piel rígida,
    desenvuelve UV, hornea las texturas y asigna materiales finales."""
    ctx = bpy.context
    for ob in PARTS:
        ctx.view_layer.objects.active = ob
        for mod in list(ob.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=mod.name)
            except Exception as e:
                print("modificador", ob.name, e)
        bone = ob["bone"]
        vg = ob.vertex_groups.new(name=bone)
        if "bone2" in ob and ob["bone2"] != bone:
            # Tela: arriba sigue a `bone`, abajo se mezcla con `bone2`
            vg2 = ob.vertex_groups.get(ob["bone2"]) or ob.vertex_groups.new(name=ob["bone2"])
            h = max(float(ob.get("cloth_h", 1.0)), 0.01)
            for v in ob.data.vertices:
                t = min(1.0, max(0.0, -v.co.z / h))
                w2 = float(ob["blend"]) * t * t * (3 - 2 * t)
                vg.add([v.index], 1.0 - w2, "REPLACE")
                if w2 > 0.001:
                    vg2.add([v.index], w2, "REPLACE")
        else:
            vg.add(range(len(ob.data.vertices)), 1.0, "REPLACE")
        mat = MATS[ob["mat"]]
        ob.data.materials.clear()
        ob.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in PARTS:
        ob.select_set(True)
    ctx.view_layer.objects.active = PARTS[0]
    bpy.ops.object.join()
    body = ctx.view_layer.objects.active
    body.name = name
    body.data.name = name
    # Transformaciones aplicadas
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # UV
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0)
    bpy.ops.uv.pack_islands(margin=0.003, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    if bake:
        _bake(body, name, tex_size, out_dir)
    if ARM:
        body.parent = ARM
        mod = body.modifiers.new("Armature", "ARMATURE")
        mod.object = ARM
    return body


def _bake(body, name, size, out_dir):
    out_dir = out_dir or bpy.path.abspath("//")
    imgs = {}
    for ch in ("color", "rough", "metal", "normal"):
        img = bpy.data.images.new("%s_%s" % (name, ch), size, size, alpha=False, float_buffer=False)
        if ch == "normal":
            img.colorspace_settings.name = "Non-Color"
            img.generated_color = (0.5, 0.5, 1.0, 1.0)
        elif ch != "color":
            img.colorspace_settings.name = "Non-Color"
        imgs[ch] = img
    bakeable = [m for m in body.data.materials if not m.get("no_bake")]
    targets = {}
    for m in bakeable:
        n = m.node_tree.nodes.new("ShaderNodeTexImage")
        targets[m.name] = n
    sc = bpy.context.scene
    sc.render.bake.margin = 6
    sc.render.bake.use_selected_to_active = False
    bpy.context.view_layer.objects.active = body
    body.select_set(True)

    def bake_ch(ch, btype, pass_filter=None):
        for m in bakeable:
            n = targets[m.name]
            n.image = imgs[ch]
            for x in m.node_tree.nodes:
                x.select = False
            n.select = True
            m.node_tree.nodes.active = n
        kw = {"type": btype}
        if pass_filter:
            kw["pass_filter"] = pass_filter
        bpy.ops.object.bake(**kw)

    sc.cycles.samples = 16
    bake_ch("color", "DIFFUSE", {"COLOR"})
    bake_ch("rough", "ROUGHNESS")
    bake_ch("normal", "NORMAL")
    # Metalicidad: se pasa por emisión temporalmente
    saved = {}
    for m in bakeable:
        nt = m.node_tree
        bsdf = next(x for x in nt.nodes if x.type == "BSDF_PRINCIPLED")
        out = next(x for x in nt.nodes if x.type == "OUTPUT_MATERIAL")
        em = nt.nodes.new("ShaderNodeEmission")
        link = bsdf.inputs["Metallic"].links
        if link:
            nt.links.new(link[0].from_socket, em.inputs[0])
        else:
            v = bsdf.inputs["Metallic"].default_value
            em.inputs[0].default_value = (v, v, v, 1)
        saved[m.name] = (out.inputs[0].links[0].from_socket, em)
        nt.links.new(em.outputs[0], out.inputs[0])
    bake_ch("metal", "EMIT")
    for ch, img in imgs.items():
        img.filepath_raw = os.path.join(out_dir, "%s_%s.png" % (name, ch))
        img.file_format = "PNG"
        img.save()
    # Materiales finales (glTF): todas las piezas comparten las texturas horneadas
    final = bpy.data.materials.new(name + "_mat")
    final.use_nodes = True
    nt = final.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexImage"); tc.image = imgs["color"]
    tr = nt.nodes.new("ShaderNodeTexImage"); tr.image = imgs["rough"]
    tm = nt.nodes.new("ShaderNodeTexImage"); tm.image = imgs["metal"]
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = imgs["normal"]
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tc.outputs[0], b.inputs["Base Color"])
    sr = nt.nodes.new("ShaderNodeSeparateColor"); nt.links.new(tr.outputs[0], sr.inputs[0]); nt.links.new(sr.outputs[0], b.inputs["Roughness"])
    sm = nt.nodes.new("ShaderNodeSeparateColor"); nt.links.new(tm.outputs[0], sm.inputs[0]); nt.links.new(sm.outputs[0], b.inputs["Metallic"])
    nt.links.new(tn.outputs[0], nm.inputs["Color"])
    nt.links.new(nm.outputs[0], b.inputs["Normal"])
    mats = body.data.materials
    for i, m in enumerate(list(mats)):
        if not m.get("no_bake"):
            mats[i] = final


# ---------------------------------------------------------------- animación

def _bone_rest_q(pb):
    return pb.bone.matrix_local.to_quaternion()


def set_pose(pose):
    """pose: hueso -> (x, y, z) grados en ejes del armazón (rotación alrededor de la
    cabeza del hueso, compuesta como en una cadena FK). 'root_pos' mueve la raíz."""
    for pb in ARM.pose.bones:
        pb.rotation_mode = "QUATERNION"
        e = pose.get(pb.name, (0, 0, 0))
        R = Euler([math.radians(a) for a in e], "XYZ").to_quaternion()
        rest = _bone_rest_q(pb)
        pb.rotation_quaternion = rest.inverted() @ R @ rest
        pb.location = (0, 0, 0)
    if "root_pos" in pose and "root" in ARM.pose.bones:
        rp = Vector(pose["root_pos"])
        pb = ARM.pose.bones["root"]
        pb.location = pb.bone.matrix_local.to_3x3().inverted() @ rp


def key_pose(frame):
    for pb in ARM.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def action(name, keys, fps=30, loop=False):
    """keys: lista de (segundo, pose). Crea la acción y la deja guardada."""
    ARM.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ARM.animation_data.action = act
    for t, pose in keys:
        set_pose(pose)
        key_pose(int(round(t * fps)) + 1)
    if loop:
        act["loop"] = True
    ARM.animation_data.action = None
    return act


def export(path, actions=True):
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.scene.render.fps = 30
    kw = dict(filepath=path, export_format="GLB", use_selection=False, export_apply=False,
              export_animations=actions, export_animation_mode="ACTIONS", export_yup=True,
              export_image_format="AUTO", export_force_sampling=True, export_optimize_animation_size=True)
    bpy.ops.export_scene.gltf(**kw)


def render_preview(path, cam_loc, target, size=(900, 1100), action_name=None, frame=1):
    """Vista previa con Cycles (para revisar el modelo antes de exportar)."""
    sc = bpy.context.scene
    if action_name:
        ARM.animation_data_create()
        ARM.animation_data.action = bpy.data.actions[action_name]
    sc.frame_set(frame)
    cam = bpy.data.objects.get("CamPrev")
    if cam is None:
        cam = bpy.data.objects.new("CamPrev", bpy.data.cameras.new("CamPrev"))
        _link(cam)
        lights = [((3, -2, 4), 350), ((-3, 2, 3), 150), ((0, 4, 2), 220)]
        for i, (loc, e) in enumerate(lights):
            l = bpy.data.objects.new("Luz%d" % i, bpy.data.lights.new("Luz%d" % i, "AREA"))
            l.data.energy = e
            l.data.size = 3
            l.location = loc
            l.rotation_euler = (Vector((0, 0, 1)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
            _link(l)
        w = bpy.data.worlds.new("Mundo")
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs[0].default_value = (0.25, 0.27, 0.3, 1)
        sc.world = w
    cam.location = cam_loc
    cam.rotation_euler = (Vector(target) - Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 50
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    if action_name:
        ARM.animation_data.action = None
