"""
Cascos de las armaduras del jugador (modelos/jugador/cascos/*.glb).
Blender 4.x / 5.x:  blender --background --python cascos.py -- <carpeta_salida> [casco ...]

Cada casco es una pieza aparte, centrada en el CENTRO DE LA CABEZA (origen), con el frente
hacia +Y de Blender (= -Z en Godot, hacia donde mira el jugador). En Godot se pega al hueso
"head" (ver jugador/player_rig.gd → attach_helmet).

  corintio   Armadura Cortafuegos     casco corintio cerrado, cresta de crin y brasas
  celada     Traje de Faraday         celada con visera de rendija, bandas de cobre y bobinas
  hazmat     Armadura Hazmat Bio-7    almete con respirador y filtros brillantes
  gran_yelmo Ancla Gravitacional      gran yelmo con visera en cruz y runas moradas
  rector     Rector Caído             yelmo ornamentado con filigrana dorada y cota de malla
  caballero  (clases / sin armadura)  bacinete con visera en punta, sobrio
"""
import bpy, bmesh, math, sys, os, random
from mathutils import Vector, Euler, Matrix

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = args[0] if args else "/tmp/cascos"
SOLO = args[1:]
os.makedirs(OUT, exist_ok=True)

# Medidas de la cabeza del jugador (m): semiejes del cráneo alrededor del origen
CAB = Vector((0.096, 0.11, 0.104))

_mats = {}
_imgs = {}


# ================================================================== utilidades
def limpiar():
    _mats.clear()
    _imgs.clear()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for col in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.curves):
        for x in list(col):
            if x.users == 0:
                col.remove(x)


def _ruido_img(nombre, base, var=0.08, rayas=0.25, tam=256, semilla=1, patron=None):
    """Textura de color con variación (manchas), rayones finos y bordes gastados."""
    key = (nombre, base, var, rayas, patron)
    if key in _imgs:
        return _imgs[key]
    rnd = random.Random(semilla)
    img = bpy.data.images.new(nombre, tam, tam, alpha=False)
    # ruido de valor por octavas (sin numpy para no depender de nada)
    def capa(n):
        g = [[rnd.random() for _ in range(n + 1)] for _ in range(n + 1)]
        def f(x, y):
            fx, fy = x * n, y * n
            ix, iy = int(fx) % n, int(fy) % n
            tx, ty = fx - int(fx), fy - int(fy)
            tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
            a = g[iy][ix] * (1 - tx) + g[iy][ix + 1] * tx
            b = g[iy + 1][ix] * (1 - tx) + g[iy + 1][ix + 1] * tx
            return a * (1 - ty) + b * ty
        return f
    octs = [(capa(4), 0.5), (capa(12), 0.3), (capa(40), 0.2)]
    px = [0.0] * (tam * tam * 4)
    rayones = []
    for _ in range(int(140 * rayas)):
        x0, y0 = rnd.random() * tam, rnd.random() * tam
        ang = rnd.random() * math.pi
        largo = 6 + rnd.random() * 40
        rayones.append((x0, y0, math.cos(ang), math.sin(ang), largo, 0.15 + rnd.random() * 0.25))
    raya = [0.0] * (tam * tam)
    for (x0, y0, dx, dy, largo, k) in rayones:
        for s in range(int(largo)):
            xi, yi = int(x0 + dx * s) % tam, int(y0 + dy * s) % tam
            raya[yi * tam + xi] = max(raya[yi * tam + xi], k)
    for y in range(tam):
        for x in range(tam):
            u, v = x / tam, y / tam
            n = sum(f(u, v) * w for f, w in octs) - 0.5
            m = 1.0 + n * var * 2.0 + raya[y * tam + x] * 0.6
            if patron:
                m *= patron(x, y, tam)
            i = (y * tam + x) * 4
            px[i] = min(1.0, base[0] * m)
            px[i + 1] = min(1.0, base[1] * m)
            px[i + 2] = min(1.0, base[2] * m)
            px[i + 3] = 1.0
    img.pixels = px
    img.pack()
    _imgs[key] = img
    return img


def mat(nombre, color, rough=0.35, metal=0.0, emit=0.0, tex=True, patron=None, var=0.08, rayas=0.25):
    key = (nombre, color, rough, metal, emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(nombre)
    m.use_nodes = True
    m.use_backface_culling = False
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = rough
    # metal < 1: en escenas oscuras sin reflejos el metal puro se ve negro
    p.inputs["Metallic"].default_value = min(metal, 0.78)
    if tex and emit <= 0:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = _ruido_img(nombre + "_tex", color, var, rayas, semilla=hash(nombre) & 0xffff, patron=patron)
        nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
    else:
        p.inputs["Base Color"].default_value = (*color, 1)
    if emit > 0:
        p.inputs["Emission Color"].default_value = (*color, 1)
        p.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


def _activo(o):
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.selected_objects:
        x.select_set(False)
    o.select_set(True)
    return o


def _obj(nombre, me, m):
    o = bpy.data.objects.new(nombre, me)
    bpy.context.collection.objects.link(o)
    if m:
        o.data.materials.append(m)
    return _activo(o)


def mod_solid(o, grosor, sub=1, bisel=0.0):
    s = o.modifiers.new("solid", "SOLIDIFY")
    s.thickness = grosor
    s.offset = -1.0
    s.use_even_offset = True
    if bisel > 0:
        b = o.modifiers.new("bisel", "BEVEL")
        b.width = bisel
        b.segments = 2
        b.limit_method = 'ANGLE'
    if sub:
        d = o.modifiers.new("sub", "SUBSURF")
        d.levels = sub
        d.render_levels = sub
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def caparazon(nombre, m, radio, mascara=None, us=72, vs=44, e0=-75.0, e1=90.0, grosor=0.007, sub=0, uv_rep=(3, 2)):
    """Cáscara del casco: superficie en coordenadas (azimut a, elevación e) en grados.
    a = 0 al frente (+Y), 90 a la derecha (+X); e = 0 a la altura de los ojos.
    radio(a, e) -> Vector (punto) ;  mascara(a, e) -> True = quitar esa cara (abertura)."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    vs_grid = []
    for j in range(vs + 1):
        e = e0 + (e1 - e0) * j / vs
        fila = []
        for i in range(us):
            a = -180.0 + 360.0 * i / us
            fila.append(bm.verts.new(radio(a, e)))
        vs_grid.append(fila)
    for j in range(vs):
        for i in range(us):
            i2 = (i + 1) % us
            ac = -180.0 + 360.0 * (i + 0.5) / us
            ec = e0 + (e1 - e0) * (j + 0.5) / vs
            if mascara and mascara(ac, ec):
                continue
            if j == vs - 1 and e1 >= 89.9:
                # casquete: triángulo hacia el polo
                f = bm.faces.new((vs_grid[j][i], vs_grid[j][i2], vs_grid[j + 1][i]))
            else:
                f = bm.faces.new((vs_grid[j][i], vs_grid[j][i2], vs_grid[j + 1][i2], vs_grid[j + 1][i]))
            for k, l in enumerate(f.loops):
                ii = [i, i2, i2, i][k] if len(f.loops) == 4 else [i, i2, i][k]
                jj = [j, j, j + 1, j + 1][k] if len(f.loops) == 4 else [j, j, j + 1][k]
                uu = (ii if ii != 0 or k in (0, 3) else us) / us
                l[uvl].uv = (uu * uv_rep[0], jj / vs * uv_rep[1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    # quitar vértices sueltos
    for v in [v for v in bm.verts if not v.link_faces]:
        bm.verts.remove(v)
    bm.normal_update()
    me = bpy.data.meshes.new(nombre)
    bm.to_mesh(me)
    bm.free()
    o = _obj(nombre, me, m)
    # normales hacia afuera
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return mod_solid(o, grosor, sub)


def _sp(c, n):
    return math.copysign(abs(c) ** (2.0 / n), c)


def esf(a, e, r, n=2.5, m=2.2):
    """Punto de un superelipsoide de semiejes r en (azimut, elevación): n > 2 hace la
    cúpula más plana y llena (nada de "huevo"), m > 2 hace la planta más cuadrada."""
    ar, er = math.radians(a), math.radians(e)
    ce, se = _sp(math.cos(er), n), _sp(math.sin(er), n)
    return Vector((r.x * ce * _sp(math.sin(ar), m), r.y * ce * _sp(math.cos(ar), m), r.z * se))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def tubo(nombre, puntos, r, m, sub=1, perfil=8, r_fin=None, cerrado=False):
    """Tubo/cordón a lo largo de una curva (bordes, filigrana, crestas)."""
    cu = bpy.data.curves.new(nombre, "CURVE")
    cu.dimensions = '3D'
    cu.bevel_depth = r
    cu.bevel_resolution = 1
    cu.use_fill_caps = True
    sp = cu.splines.new('POLY' if len(puntos) < 3 else 'NURBS')
    sp.points.add(len(puntos) - 1)
    for i, p in enumerate(puntos):
        sp.points[i].co = (p[0], p[1], p[2], 1)
        if r_fin is not None:
            t = i / max(1, len(puntos) - 1)
            sp.points[i].radius = 1.0 + (r_fin / r - 1.0) * t
    if sp.type == 'NURBS':
        sp.use_endpoint_u = not cerrado
        sp.use_cyclic_u = cerrado
        sp.order_u = 4 if len(puntos) >= 4 else 3
    cu.resolution_u = 3
    o = bpy.data.objects.new(nombre, cu)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(m)
    _activo(o)
    bpy.ops.object.convert(target='MESH')
    o = bpy.context.active_object
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def anillo_en(caparazon_r, e, r, m, a0=-180, a1=180, n=48, off=0.0, nombre="borde"):
    pts = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        p = caparazon_r(a, e)
        pts.append(p * (1.0 + off))
    return tubo(nombre, pts, r, m, cerrado=(a0 == -180 and a1 == 180))


def remaches(caparazon_r, posiciones, r, m, off=0.004):
    for (a, e) in posiciones:
        p = caparazon_r(a, e)
        n = p.normalized()
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=p + n * off, segments=10, ring_count=6)
        o = bpy.context.active_object
        o.scale = (1, 1, 1)
        o.data.materials.append(m)
        bpy.ops.object.shade_smooth()


def caja(size, pos, m, rot=(0, 0, 0), bisel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=pos)
    o = bpy.context.active_object
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    o.rotation_euler = Euler([math.radians(x) for x in rot])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(m)
    if bisel:
        b = o.modifiers.new("b", "BEVEL")
        b.width = bisel
        b.segments = 2
    return o


def cil(r1, r2, h, pos, m, rot=(0, 0, 0), v=20, bisel=0.0):
    bpy.ops.mesh.primitive_cone_add(vertices=v, radius1=r1, radius2=r2, depth=h, location=pos)
    o = bpy.context.active_object
    o.rotation_euler = Euler([math.radians(x) for x in rot])
    o.data.materials.append(m)
    if bisel:
        b = o.modifiers.new("b", "BEVEL")
        b.width = bisel
        b.segments = 2
        b.limit_method = 'ANGLE'
    bpy.ops.object.shade_smooth()
    return o


def toro(R, r, pos, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=pos, major_segments=36, minor_segments=10)
    o = bpy.context.active_object
    o.rotation_euler = Euler([math.radians(x) for x in rot])
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return o


def crin(base_pts, largo, m, mechones=140, semilla=3, ancho=0.012, caida=0.5):
    """Cresta de crin de caballo: muchos mechones finos (tiras curvas que se adelgazan)."""
    rnd = random.Random(semilla)
    bm = bmesh.new()
    nb = len(base_pts)
    for k in range(mechones):
        t = rnd.random()
        fi = t * (nb - 1)
        i0 = int(fi)
        i1 = min(nb - 1, i0 + 1)
        p = base_pts[i0].lerp(base_pts[i1], fi - i0)
        # dirección: hacia arriba, cayendo hacia atrás (−Y) más al final de la cresta
        dirv = Vector((rnd.uniform(-0.25, 0.25), -caida * (0.3 + t) + rnd.uniform(-0.15, 0.15), 1.0)).normalized()
        L = largo * rnd.uniform(0.75, 1.15) * (0.75 + 0.5 * math.sin(math.pi * t))
        segs = 5
        lado = Vector((1, 0, 0))
        filas = []
        for s in range(segs + 1):
            u = s / segs
            q = p + dirv * (L * u) + Vector((0, -L * 0.55 * u * u, -L * 0.25 * u * u))
            w = ancho * (1.0 - 0.85 * u) * rnd.uniform(0.7, 1.2)
            filas.append((bm.verts.new(q - lado * w), bm.verts.new(q + lado * w)))
        for s in range(segs):
            bm.faces.new((filas[s][0], filas[s][1], filas[s + 1][1], filas[s + 1][0]))
    me = bpy.data.meshes.new("crin")
    bm.to_mesh(me)
    bm.free()
    o = _obj("crin", me, m)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def exportar(nombre):
    bpy.ops.object.select_all(action='SELECT')
    for o in bpy.context.selected_objects:
        if o.type == 'MESH':
            _activo(o)
            for md in list(o.modifiers):
                try:
                    bpy.ops.object.modifier_apply(modifier=md.name)
                except Exception:
                    pass
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active = [o for o in bpy.context.selected_objects if o.type == 'MESH'][0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "Casco_" + nombre
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    path = os.path.join(OUT, "casco_" + nombre + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True)
    print("exportado %s  (%d triángulos)" % (path, tris))


# ================================================================== CASCOS

def casco_corintio():
    """Cortafuegos: casco corintio cerrado de acero ennegrecido, cresta de crin negra,
    rendijas de los ojos con brasas y vetas de lava finas."""
    limpiar()
    acero = mat("acero_tiznado", (0.11, 0.105, 0.1), 0.38, 0.95, var=0.12, rayas=0.5)
    bronce = mat("bronce_oscuro", (0.32, 0.2, 0.1), 0.35, 1.0)
    brasa = mat("brasa", (1.0, 0.35, 0.06), 0.5, 0.0, emit=6.0)
    pelo = mat("crin", (0.018, 0.016, 0.015), 0.95, 0.0, var=0.25, rayas=0.0)
    R = CAB + Vector((0.026, 0.03, 0.03))

    def radio(a, e):
        p = esf(a, e, R)
        fr = max(0.0, math.cos(math.radians(a)))          # 1 al frente
        # baja hasta la barbilla al frente y se abre en la nuca
        if e < 0:
            k = smooth(-e / 75.0)
            p.z -= k * 0.035 * fr
            p.y += k * 0.025 * fr                           # mejillas hacia adelante (perfil del corintio)
            back = max(0.0, -math.cos(math.radians(a)))
            p.y -= back * k * 0.03                          # faldón de la nuca
            p.x *= 1.0 + k * 0.12 * (1 - fr)
        # arista del protector nasal
        if abs(a) < 14 and -40 < e < 20:
            p.y += 0.012 * (1 - abs(a) / 14) * smooth((20 - e) / 25)
        # cejas marcadas
        if 0 < e < 16 and abs(a) < 65:
            p += p.normalized() * 0.006 * math.sin(math.pi * e / 16)
        return p

    def abertura(a, e):
        aa = abs(a)
        # ojos almendrados
        ojo = (13 < aa < 52) and (-11 + (aa - 13) * 0.08 < e < 6 - (aa - 13) * 0.1)
        # ranura vertical bajo el protector nasal (boca)
        boca = aa < 7.5 + max(0, (-e - 30) * 0.25) and e < -26
        # unión ojo-boca (la "T" del corintio)
        union = 9 < aa < 16 and -30 < e < -6
        return ojo or boca or union

    caparazon("cuenco", acero, radio, abertura, us=96, vs=56, e0=-72, grosor=0.006)
    # bordes reforzados: alrededor de la boca y del cuello
    anillo_en(radio, -71.5, 0.0045, bronce, nombre="borde_cuello")
    # vetas de lava finas en las mejillas
    for sd in (-1, 1):
        pts = [radio(sd * a, e) * 1.012 for (a, e) in ((58, -10), (60, -25), (55, -42), (48, -58))]
        tubo("veta", pts, 0.0018, brasa)
        pts = [radio(sd * a, e) * 1.012 for (a, e) in ((75, 5), (80, -15), (78, -35))]
        tubo("veta", pts, 0.0014, brasa)
    # soporte de la cresta (aleta de bronce) y la crin
    base = []
    for i in range(14):
        e = 40 + (90 - 40) * min(1, i / 6) if i <= 6 else 90
        a = 0 if i <= 6 else 180
        if i > 6:
            e = 90 - (i - 6) * 7.5
        base.append(radio(a, e) * 1.03)
    tubo("soporte_cresta", base, 0.007, bronce)
    crin(base, 0.17, pelo, mechones=260, ancho=0.01, caida=0.55)
    # cola de crin que cae por la nuca
    cola = [radio(180, e) * 1.04 for e in (30, 10, -10, -30)]
    crin(cola, 0.09, pelo, mechones=60, semilla=9, ancho=0.008, caida=1.4)
    exportar("corintio")


def casco_celada():
    """Faraday: celada (sallet) con cola larga, visera de rendija con brillo azul,
    bandas de cobre remachadas y pequeñas bobinas en las sienes."""
    limpiar()
    acero = mat("acero_pavonado", (0.32, 0.34, 0.38), 0.22, 1.0, var=0.06, rayas=0.35)
    cobre = mat("cobre", (0.85, 0.45, 0.25), 0.3, 1.0, var=0.12)
    goma = mat("goma", (0.05, 0.05, 0.055), 0.85, 0.0, rayas=0.0)
    luz = mat("descarga", (0.35, 0.75, 1.0), 0.4, 0.0, emit=7.0)
    R = CAB + Vector((0.024, 0.026, 0.03))

    def radio(a, e):
        p = esf(a, e, R)
        back = max(0.0, -math.cos(math.radians(a)))
        if e < 0:
            k = smooth(-e / 45.0)
            # la cola de la celada: se alarga hacia atrás y abajo
            p.y -= back * back * k * 0.11
            p.z += back * k * 0.02
            p.x *= 1.0 + k * 0.1
        # arista central (cresta baja)
        if abs(a) < 6 or abs(abs(a) - 180) < 6:
            if e > 10:
                p += p.normalized() * 0.006 * (1 - min(abs(a), abs(abs(a) - 180)) / 6)
        return p

    def abertura(a, e):
        # rendija de visión
        return abs(a) < 62 and -3.0 < e < 3.0

    caparazon("celada", acero, radio, abertura, us=96, vs=52, e0=-48, grosor=0.006)
    anillo_en(radio, -47.5, 0.004, cobre, nombre="borde")
    # brillo dentro de la rendija
    pts = [radio(a, 0) * 0.97 for a in range(-58, 60, 6)]
    tubo("brillo", pts, 0.004, luz)
    # bandas de cobre (de frente a nuca) con remaches
    pts = [radio(0 if e <= 90 else 180, e) * 1.015 for e in range(6, 91, 6)] + [radio(180, e) * 1.015 for e in range(84, -45, -8)]
    tubo("banda_c", pts, 0.0045, cobre)
    remaches(radio, [(a, -38) for a in range(-160, 161, 20) if abs(a) > 70], 0.0035, cobre)
    # bevor (protección de barbilla y cuello) bajo la visera
    def r_bevor(a, e):
        p = esf(a, e, CAB + Vector((0.03, 0.034, 0.02)))
        p.y += 0.004
        p.z -= 0.006
        p.x *= 1.0 - 0.15 * smooth(-e / 80.0)
        return p
    caparazon("bevor", acero, r_bevor, lambda a, e: abs(a) > 100, us=72, vs=20, e0=-80, e1=-6, grosor=0.006)
    anillo_en(r_bevor, -6.5, 0.0035, cobre, a0=-100, a1=100, n=40, nombre="borde_bevor")
    # bobinas en las sienes
    for sd in (-1, 1):
        p = radio(sd * 90, 18)
        n = p.normalized()
        rot = (0, 90 * sd, 0)
        cil(0.015, 0.015, 0.022, p + n * 0.008, goma, rot=rot)
        for k in range(4):
            toro(0.016, 0.0028, p + n * (0.0 + k * 0.005), cobre, rot=rot)
        cil(0.007, 0.002, 0.012, p + n * 0.024, luz, rot=rot)
    exportar("celada")


def casco_hazmat():
    """Hazmat Bio-7: almete redondeado con visera de rejilla, respirador en la boca y dos
    filtros laterales con luz verde."""
    limpiar()
    acero = mat("pintura_oliva", (0.2, 0.22, 0.15), 0.55, 0.35, var=0.16, rayas=0.9)
    goma = mat("goma", (0.06, 0.07, 0.06), 0.8, 0.0, rayas=0.0)
    amarillo = mat("pintura_aviso", (0.55, 0.4, 0.04), 0.6, 0.2, var=0.2, rayas=1.0)
    metal = mat("acero_gastado", (0.42, 0.42, 0.4), 0.3, 1.0, var=0.1, rayas=0.6)
    verde = mat("filtro_brillo", (0.4, 1.0, 0.25), 0.4, 0.0, emit=4.0)
    R = CAB + Vector((0.026, 0.03, 0.028))

    def radio(a, e):
        p = esf(a, e, R)
        fr = max(0.0, math.cos(math.radians(a)))
        if e < 0:
            k = smooth(-e / 70.0)
            p.y += fr * k * 0.02
            p.z -= fr * k * 0.02
        return p

    def abertura(a, e):
        # visor ancho (luego lleva rejilla)
        return abs(a) < 44 and -4 < e < 9

    caparazon("almete", acero, radio, abertura, us=96, vs=52, e0=-70, grosor=0.006)
    anillo_en(radio, -69.5, 0.004, goma, nombre="borde")
    # marco del visor y barrotes
    pts = [radio(a, 9.5) * 1.006 for a in range(-46, 47, 4)] + [radio(a, -4.5) * 1.006 for a in range(46, -47, -4)]
    tubo("marco", pts + [pts[0]], 0.0035, metal)
    for a in range(-36, 37, 9):
        tubo("barrote", [radio(a, -4) * 1.0, radio(a, 2.5) * 1.004, radio(a, 9) * 1.0], 0.0018, metal)
    # vidrio ahumado detrás de la rejilla
    def r_vidrio(a, e):
        return radio(a, e) * 0.965
    caparazon("vidrio", mat("vidrio", (0.05, 0.16, 0.08), 0.05, 0.3, emit=0.25, tex=False), r_vidrio, lambda a, e: not (abs(a) < 46 and -6 < e < 11), us=64, vs=16, e0=-8, e1=13, grosor=0.002, sub=0)
    # respirador: hocico con rejilla de agujeros
    boca = radio(0, -38)
    cil(0.036, 0.028, 0.04, boca + Vector((0, 0.012, 0)), goma, rot=(-80, 0, 0), bisel=0.004)
    cil(0.03, 0.03, 0.008, boca + Vector((0, 0.034, -0.003)), metal, rot=(-80, 0, 0))
    for k in range(6):
        ang = k * 60
        q = boca + Vector((math.cos(math.radians(ang)) * 0.016, 0.039, math.sin(math.radians(ang)) * 0.016 - 0.003))
        cil(0.0035, 0.0035, 0.004, q, mat("negro", (0.01, 0.01, 0.01), 0.9, 0.0, tex=False), rot=(-80, 0, 0), v=10)
    # filtros laterales
    for sd in (-1, 1):
        p = radio(sd * 52, -38)
        n = p.normalized()
        c = p + n * 0.02 + Vector((0, 0.012, 0))
        o = cil(0.019, 0.019, 0.034, c, metal, rot=(0, 0, 0), bisel=0.003)
        o.rotation_euler = n.to_track_quat('Z', 'Y').to_euler()
        o2 = cil(0.014, 0.014, 0.005, c + n * 0.018, verde)
        o2.rotation_euler = n.to_track_quat('Z', 'Y').to_euler()
        for k in range(3):
            t = toro(0.02, 0.0028, c + n * (-0.011 + k * 0.009), goma)
            t.rotation_euler = n.to_track_quat('Z', 'Y').to_euler()
    # franjas de aviso en la coronilla
    for a in (-22, 22):
        tubo("franja", [radio(a, e) * 1.008 for e in range(20, 88, 8)], 0.004, amarillo)
    remaches(radio, [(a, e) for a in (-75, -60, 60, 75) for e in (-20, 0, 25)], 0.004, metal)
    exportar("hazmat")


def casco_gran_yelmo():
    """Ancla Gravitacional: gran yelmo pesado, cerrado, con visera en cruz, respiraderos
    y runas moradas; corona de puntas bajas."""
    limpiar()
    hierro = mat("hierro_viejo", (0.16, 0.15, 0.18), 0.45, 0.95, var=0.16, rayas=0.8)
    plata = mat("plata_oscura", (0.42, 0.42, 0.46), 0.3, 1.0, var=0.1, rayas=0.5)
    runa = mat("runa", (0.7, 0.4, 1.0), 0.4, 0.0, emit=7.0)
    R = CAB + Vector((0.03, 0.032, 0.035))

    def radio(a, e):
        p = esf(a, e, R)
        # más cilíndrico abajo (yelmo), cúpula arriba
        if e < 30:
            k = smooth((30 - e) / 100)
            r_xy = math.hypot(p.x, p.y)
            if r_xy > 1e-6:
                cyl_r = Vector((R.x * math.sin(math.radians(a)), R.y * math.cos(math.radians(a)), 0)).length * 0.98
                s = (r_xy * (1 - k) + cyl_r * k) / r_xy
                p.x *= s
                p.y *= s
            p.z = R.z * math.sin(math.radians(e)) * (1 - 0.25 * k) - 0.02 * k
        # quilla vertical al frente
        if abs(a) < 10:
            p.y += 0.013 * (1 - abs(a) / 10)
        return p

    def abertura(a, e):
        aa = abs(a)
        ojos = 8 < aa < 55 and -1.5 < e < 3.5
        return ojos

    caparazon("yelmo", hierro, radio, abertura, us=96, vs=56, e0=-78, grosor=0.007)
    anillo_en(radio, -77.5, 0.005, plata, nombre="borde")
    # cruz: barra vertical de plata y respiraderos
    tubo("cruz_v", [radio(0, e) * 1.012 for e in range(-70, 60, 8)], 0.006, plata)
    tubo("cruz_h", [radio(a, -4) * 1.01 for a in range(-58, 59, 6)], 0.0045, plata)
    tubo("cruz_h2", [radio(a, 6) * 1.01 for a in range(-58, 59, 6)], 0.0045, plata)
    for sd in (-1, 1):
        for k in range(5):
            a = sd * (20 + k * 7)
            p = radio(a, -30)
            n = p.normalized()
            o = caja((0.006, 0.006, 0.03), p + n * 0.001, mat("negro", (0.01, 0.01, 0.01), 0.9, 0.0, tex=False))
            o.rotation_euler = n.to_track_quat('Y', 'Z').to_euler()
    # runas: anillo de marcas brillantes en la frente
    for k in range(9):
        a = -48 + k * 12
        p = radio(a, 24) * 1.006
        n = p.normalized()
        o = caja((0.004, 0.003, 0.016 if k % 2 else 0.01), p, runa)
        o.rotation_euler = n.to_track_quat('Y', 'Z').to_euler()
    anillo_en(radio, 16, 0.003, plata, nombre="aro_runas")
    anillo_en(radio, 32, 0.003, plata, nombre="aro_runas2")
    # corona: aro superior con almenas bajas
    anillo_en(radio, 58, 0.005, plata, nombre="aro_corona")
    for k in range(12):
        a = -180 + k * 30
        p = radio(a, 60) * 1.0
        n = p.normalized()
        o = caja((0.022, 0.008, 0.02), p + n * 0.003 + Vector((0, 0, 0.008)), plata, bisel=0.002)
        o.rotation_euler = n.to_track_quat('Y', 'Z').to_euler()
    exportar("gran_yelmo")


def casco_rector():
    """Rector Caído: yelmo alto y ornamentado (estilo caballero de leyenda), con visera de
    cota de malla, filigrana dorada en relieve, cresta labrada y aventail de malla."""
    limpiar()
    plata = mat("plata_gastada", (0.45, 0.45, 0.47), 0.32, 1.0, var=0.14, rayas=0.8)
    oro = mat("oro_viejo", (0.7, 0.5, 0.2), 0.35, 1.0, var=0.15, rayas=0.5)

    def malla_patron(x, y, tam):
        # anillos de cota de malla
        cx = (x % 8) - 3.5
        cy = (y % 6) - 2.5 + (2.0 if (x // 8) % 2 else 0.0)
        cy = ((cy + 3) % 6) - 3
        r = math.hypot(cx, cy * 1.2)
        return 1.25 if 2.0 < r < 3.4 else 0.35
    malla = mat("cota_malla", (0.36, 0.36, 0.38), 0.5, 1.0, patron=malla_patron, var=0.08, rayas=0.0)
    R = CAB + Vector((0.024, 0.028, 0.03))

    def radio(a, e):
        p = esf(a, e, R)
        # yelmo alto y apuntado arriba
        if e > 20:
            k = smooth((e - 20) / 70)
            p.z += k * 0.022
            p.x *= 1 - 0.08 * k
        # quilla central labrada
        if abs(a) < 8 and e > -10:
            p += p.normalized() * 0.008 * (1 - abs(a) / 8)
        return p

    def abertura(a, e):
        # la cara (ojos a barbilla) es una ventana grande cubierta por malla
        return abs(a) < 50 and -60 < e < 12

    caparazon("yelmo", plata, radio, abertura, us=96, vs=56, e0=-60, grosor=0.006)
    # bordes dorados de la ventana
    pts = [radio(a, 12.5) * 1.008 for a in range(-52, 53, 4)]
    tubo("ceja", pts, 0.004, oro)
    for sd in (-1, 1):
        tubo("lado_cara", [radio(sd * 51, e) * 1.008 for e in range(12, -61, -6)], 0.0035, oro)
    anillo_en(radio, -59.5, 0.004, oro, nombre="borde")
    # visera de malla (se ve la oscuridad detrás)
    def r_malla(a, e):
        p = radio(a, e) * 0.985
        p.y += 0.004
        return p
    caparazon("visera_malla", malla, r_malla, lambda a, e: abs(a) > 54, us=48, vs=24, e0=-62, e1=14, grosor=0.002, sub=1, uv_rep=(3, 2.5))
    # filigrana dorada en relieve: espirales simétricas en los lados y frente
    for sd in (-1, 1):
        for (a0, e0, s) in ((65, 30, 1.0), (95, 5, 0.8), (120, 40, 0.9), (70, -30, 0.7)):
            pts = []
            for i in range(26):
                t = i / 25
                ang = t * 3.2 * math.pi
                rr = 14 * s * (1 - t * 0.85)
                pts.append(radio(sd * (a0 + math.cos(ang) * rr), e0 + math.sin(ang) * rr) * 1.01)
            tubo("filigrana", pts, 0.0022, oro, r_fin=0.0012)
        # hojas que suben por la frente
        for k in range(4):
            pts = [radio(sd * (10 + k * 3 + t * 22), 18 + k * 12 + t * 14) * 1.01 for t in (0, 0.33, 0.66, 1)]
            tubo("hoja", pts, 0.0025, oro, r_fin=0.0008)
    # cresta labrada (aleta alta) de frente a nuca
    cresta = []
    for i in range(18):
        t = i / 17
        a = 0 if t < 0.5 else 180
        e = 30 + t * 120 if t < 0.5 else 150 - t * 120
        e = min(e, 90)
        cresta.append(radio(a, e) * (1.02 + 0.06 * math.sin(math.pi * t)))
    tubo("cresta", cresta, 0.006, plata)
    tubo("cresta_oro", [p * 1.012 for p in cresta], 0.0028, oro)
    # aventail: faldón de malla que cae sobre el cuello y los hombros
    def r_avent(a, e):
        p = esf(a, -60, R) * 1.0
        k = (e + 60) / -40.0    # 0 en el borde del yelmo, 1 al final
        q = Vector((p.x * (1 + 0.3 * k), p.y * (1 + 0.25 * k), p.z - 0.065 * k))
        q += Vector((q.x, q.y, 0)).normalized() * 0.004 * math.sin(math.radians(a) * 18) * k   # pliegues
        return q
    caparazon("aventail", malla, r_avent, None, us=96, vs=10, e0=-100, e1=-60, grosor=0.003, sub=1, uv_rep=(9, 1.2))
    remaches(radio, [(a, -52) for a in range(-180, 180, 20) if abs(a) > 55], 0.004, oro)
    exportar("rector")


def casco_caballero():
    """Clases sin armadura de resistencia: bacinete sobrio con visera en punta
    ("pico de gorrión") y respiraderos."""
    limpiar()
    acero = mat("acero", (0.4, 0.41, 0.43), 0.3, 1.0, var=0.12, rayas=0.8)
    cuero = mat("cuero", (0.16, 0.09, 0.05), 0.75, 0.0)
    R = CAB + Vector((0.024, 0.026, 0.03))

    def radio(a, e):
        p = esf(a, e, R)
        # cúpula apuntada
        if e > 40:
            p.z += smooth((e - 40) / 50) * 0.022
        return p

    def abertura(a, e):
        return abs(a) < 60 and -55 < e < 20   # cara abierta: la cubre la visera

    caparazon("bacinete", acero, radio, abertura, us=96, vs=52, e0=-60, grosor=0.006)
    anillo_en(radio, -59.5, 0.004, cuero, nombre="borde")

    # visera en punta
    def r_visera(a, e):
        p = esf(a, e, R + Vector((0.008, 0.012, 0.004)))
        fr = max(0.0, math.cos(math.radians(a)))
        p.y += fr ** 3 * 0.055 * (1 - abs(e + 15) / 45) ** 1.5 if abs(e + 15) < 45 else 0.0
        return p
    caparazon("visera", acero, r_visera,
              lambda a, e: abs(a) > 66 or (abs(a) < 52 and -1.5 < e < 2.5),
              us=96, vs=30, e0=-58, e1=22, grosor=0.006)
    remaches(radio, [(-64, -15), (64, -15)], 0.008, acero)
    for sd in (-1, 1):
        for k in range(5):
            a = sd * (8 + k * 6)
            q = r_visera(a, -25)
            n = q.normalized()
            o = caja((0.004, 0.006, 0.014), q, mat("negro", (0.01, 0.01, 0.01), 0.9, 0.0, tex=False))
            o.rotation_euler = n.to_track_quat('Y', 'Z').to_euler()
    exportar("caballero")


CASCOS = {
    "corintio": casco_corintio,
    "celada": casco_celada,
    "hazmat": casco_hazmat,
    "gran_yelmo": casco_gran_yelmo,
    "rector": casco_rector,
    "caballero": casco_caballero,
}

for nombre, fn in CASCOS.items():
    if SOLO and nombre not in SOLO:
        continue
    fn()
