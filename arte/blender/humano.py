"""Humanos realistas para los jefes, a partir de las mallas base humanas de Blender (CC0,
arte/recursos/human_base_meshes). En vez de juntar esferas y cajas, cada jefe es un cuerpo
continuo con rostro esculpido que se ajusta a sus proporciones, con piel que se deforma
con los huesos (pesos automáticos), y encima ropa y armaduras que salen del mismo cuerpo
(se ajustan a su forma) con láminas, ribetes, grabados y detalles tecnológicos.

Flujo:
    bk.reset(); bk.define_materials(...)
    H = humano.Humano("male")                  # carga, gira (mira a +Y), sube detalle
    H.fit(objetivos, grosor, nombres)          # proporciones y esqueleto del jefe
    H.cabello("peinado"), H.barba("candado"), ...
    H.capa / H.placa / H.laminas ...           # ropa y armadura desde regiones del cuerpo
    bk.finish(...); bk.export(...)

Coordenadas de Blender, el personaje mira hacia +Y y su derecha es +X (igual que bk.py).
"""
import bpy
import bmesh
import math
import os
import random
from mathutils import Vector, Matrix, Quaternion
from mathutils.kdtree import KDTree

import bk

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "recursos", "human_base_meshes", "human_base_meshes_bundle.blend")

# Articulaciones de la malla base (hombre, ya girada para mirar a +Y), en metros.
CANON = {
    "pelvis": (0, 0, 0.95), "spine": (0, 0, 1.05), "chest": (0, 0, 1.22), "neck": (0, 0.0, 1.42),
    "head": (0, 0.01, 1.52), "head_top": (0, 0.02, 1.69),
    "shoulder_r": (0.18, 0.0, 1.36), "elbow_r": (0.28, -0.01, 1.08), "wrist_r": (0.38, 0.0, 0.85), "hand_tip_r": (0.42, 0.04, 0.71),
    "hip_r": (0.09, 0.0, 0.9), "knee_r": (0.11, 0.015, 0.47), "ankle_r": (0.11, -0.03, 0.08), "toe_r": (0.11, 0.15, 0.01),
}
for _k in list(CANON):
    if _k.endswith("_r"):
        _p = CANON[_k]
        CANON[_k[:-2] + "_l"] = (-_p[0], _p[1], _p[2])

# Huesos canónicos: (nombre, padre, articulación cabeza, articulación cola)
BONES = [
    ("pelvis", "", "pelvis", "spine"),
    ("spine", "pelvis", "spine", "chest"),
    ("chest", "spine", "chest", "neck"),
    ("neck", "chest", "neck", "head"),
    ("head", "neck", "head", "head_top"),
]
for _s in ("r", "l"):
    BONES += [
        ("upper_arm_" + _s, "chest", "shoulder_" + _s, "elbow_" + _s),
        ("forearm_" + _s, "upper_arm_" + _s, "elbow_" + _s, "wrist_" + _s),
        ("hand_" + _s, "forearm_" + _s, "wrist_" + _s, "hand_tip_" + _s),
        ("thigh_" + _s, "pelvis", "hip_" + _s, "knee_" + _s),
        ("shin_" + _s, "thigh_" + _s, "knee_" + _s, "ankle_" + _s),
        ("foot_" + _s, "shin_" + _s, "ankle_" + _s, "toe_" + _s),
    ]


def targets(scale=1.0, width=1.0, legs=1.0, arms=1.0, neck=1.0, head=1.0, pelvis_z=None, move=None, arm_drop=15.0):
    """Articulaciones objetivo a partir de las de la malla base.
    scale: tamaño general; width: ancho de hombros y caderas; legs/arms/neck: largo de cada
    parte; pelvis_z: altura fija de la cadera (para que coincida con la del código del jefe).
    move: {articulación: (dx, dy, dz)} ajustes finos (ya en metros del jefe)."""
    c = {k: Vector(v) for k, v in CANON.items()}
    t = {}
    t["pelvis"] = c["pelvis"] * scale
    t["spine"] = c["spine"] * scale
    t["chest"] = c["chest"] * scale
    t["neck"] = t["chest"] + (c["neck"] - c["chest"]) * scale
    t["head"] = t["neck"] + (c["head"] - c["neck"]) * scale * neck
    t["head_top"] = t["head"] + (c["head_top"] - c["head"]) * scale * head
    for s in ("r", "l"):
        sh = c["shoulder_" + s]
        t["shoulder_" + s] = Vector((sh.x * width, sh.y, 0)) * scale + Vector((0, 0, t["chest"].z + (sh.z - c["chest"].z) * scale))
        for a, b in (("shoulder", "elbow"), ("elbow", "wrist"), ("wrist", "hand_tip")):
            t[b + "_" + s] = t[a + "_" + s] + (c[b + "_" + s] - c[a + "_" + s]) * scale * arms
        hp = c["hip_" + s]
        t["hip_" + s] = Vector((hp.x * width, hp.y, 0)) * scale + Vector((0, 0, t["pelvis"].z + (hp.z - c["pelvis"].z) * scale))
        for a, b in (("hip", "knee"), ("knee", "ankle")):
            t[b + "_" + s] = t[a + "_" + s] + (c[b + "_" + s] - c[a + "_" + s]) * scale * legs
        t["toe_" + s] = t["ankle_" + s] + (c["toe_" + s] - c["ankle_" + s]) * scale
    # Brazos más pegados al cuerpo que en la pose A de la base (el código los cuelga rectos)
    for s, sg in (("r", 1), ("l", -1)):
        sh = t["shoulder_" + s]
        rot = Matrix.Rotation(math.radians(arm_drop) * sg, 3, "Y")
        for b in ("elbow", "wrist", "hand_tip"):
            t[b + "_" + s] = sh + rot @ (t[b + "_" + s] - sh)
    # Cadera a la altura pedida: estira o encoge las piernas, no mueve los pies del suelo
    if pelvis_z is not None:
        dz = pelvis_z - t["pelvis"].z
        for k in t:
            if not any(k.startswith(p) for p in ("knee", "ankle", "toe")):
                t[k] = t[k] + Vector((0, 0, dz))
        for s in ("r", "l"):
            # las rodillas quedan a la mitad entre cadera y tobillo, como en la base
            h, a = t["hip_" + s], t["ankle_" + s]
            f = (c["hip_" + s].z - c["knee_" + s].z) / (c["hip_" + s].z - c["ankle_" + s].z)
            t["knee_" + s] = h.lerp(a, f) + Vector((0, c["knee_" + s].y * scale, 0))
    if move:
        for k, d in move.items():
            t[k] = t[k] + Vector(d)
    return t


def _link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _select_only(*obs, active=None):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or obs[0]


class Humano:
    def __init__(self, sex="male", level=2, ratio=0.42, seed=1):
        self.rng = random.Random(seed)
        name = "GEO-body_%s_realistic" % sex
        with bpy.data.libraries.load(BASE) as (src, dst):
            dst.objects = [n for n in src.objects if n.startswith(name)]
        body = None
        self.eyes = []
        for o in dst.objects:
            _link(o)
        bpy.context.view_layer.update()
        body = bpy.data.objects[name]
        origin = body.matrix_world.translation.copy()
        rz = Matrix.Rotation(math.pi, 4, "Z")      # la base mira a −Y
        if sex == "female":
            # La base femenina mide 1.64 m: se lleva a 1.69 m para que coincida con las
            # articulaciones y zonas medidas en la masculina
            rz = rz @ Matrix.Scale(1.69 / 1.64, 4)
        for o in dst.objects:
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = rz @ Matrix.Translation(-origin) @ mw
            if o != body:
                self.eyes.append(o)
        self.body = body
        _select_only(body)
        for m in list(body.modifiers):
            if m.type == "MULTIRES":
                m.levels = level
                m.render_levels = level
                bpy.ops.object.modifier_apply(modifier=m.name)
        if ratio < 1.0:
            d = body.modifiers.new("dec", "DECIMATE")
            d.ratio = ratio
            d.use_symmetry = True
            d.symmetry_axis = "X"
            bpy.ops.object.modifier_apply(modifier="dec")
        for o in [body] + self.eyes:
            _select_only(o)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            for p in o.data.polygons:
                p.use_smooth = True
        self.base_co = [v.co.copy() for v in body.data.vertices]
        self._regions()
        self.arm = None

    # ------------------------------------------------------------------ manos
    def curl_hands(self, radius=0.022, max_angle=1.65, knuckle=1.05, thumb=0.45, sides=("r", "l")):
        """Cierra las manos en puño de agarre (antes de fit). En la malla base las manos
        cuelgan con la palma hacia el cuerpo y los dedos abiertos en abanico: la mano se
        corta a la altura de los nudillos, cada dedo (pedazo conectado de la malla) se dobla
        en arco hacia la palma sobre su propio eje y el pulgar se cierra un poco. Así el
        mango del arma pasa por el hueco del puño en vez de flotar junto a una mano abierta."""
        hands = self.region("hands")
        me = self.body.data
        vs = me.vertices
        self._orig_hand = {k: self.base_co[k].copy() for k in hands}
        nbr = {}
        for e in me.edges:
            a_, b_ = e.vertices
            nbr.setdefault(a_, []).append(b_)
            nbr.setdefault(b_, []).append(a_)
        for s in sides:
            sg = 1.0 if s == "r" else -1.0
            idx = [k for k, w in hands.items() if w > 0.2 and self.base_co[k].x * sg > 0.3]
            if not idx:
                continue
            co = {k: self.base_co[k].copy() for k in idx}
            wr = [co[k] for k in idx if co[k].z > 0.835]
            tip = [co[k] for k in idx if co[k].z < 0.735]
            if not wr or not tip:
                continue
            W = sum(wr, Vector()) / len(wr)
            T = sum(tip, Vector()) / len(tip)
            f = (T - W).normalized()
            n = Vector((-sg, 0.0, 0.0))
            n = (n - f * n.dot(f)).normalized()
            L = (T - W).dot(f)
            # 1) Flexión en los nudillos: todo lo que pasa de t_k gira hacia la palma, con
            #    una rampa suave que cruza la membrana entre los dedos (sin romper la malla)
            t_k = L * 0.36
            axis = f.cross(n).normalized()
            u0 = sum((co[k] - W).dot(n) for k in idx) / len(idx)
            P0 = W + f * t_k + n * u0
            for k in idx:
                t = (co[k] - W).dot(f)
                if t <= t_k:
                    continue
                x = min(1.0, (t - t_k) / 0.025)
                ang = knuckle * x * x * (3 - 2 * x)
                p = P0 + Matrix.Rotation(ang, 3, axis) @ (co[k] - P0)
                co[k] = p
                vs[k].co = p
                self.base_co[k] = p.copy()
            # 2) Cada dedo se curva sobre su propio eje. Se busca el corte más cercano a los
            #    nudillos donde los dedos ya quedan separados (al menos 4 pedazos)
            comps = []
            for frac in (0.5, 0.54, 0.58, 0.62, 0.66, 0.7, 0.74):
                t_cut = L * frac
                cut = {k for k in idx if (self._orig_hand.get(k, co[k]) - W).dot(f) > t_cut}
                seen = set()
                comps = []
                for k in cut:
                    if k in seen:
                        continue
                    stack = [k]
                    seen.add(k)
                    comp = []
                    while stack:
                        c = stack.pop()
                        comp.append(c)
                        for m in nbr.get(c, []):
                            if m in cut and m not in seen:
                                seen.add(m)
                                stack.append(m)
                    if len(comp) > 20:
                        comps.append(comp)
                if len(comps) >= 4:
                    break
            if not comps:
                continue
            # El pulgar es el pedazo más adelantado (+Y)
            thumb_i = max(range(len(comps)), key=lambda i: sum(co[k].y for k in comps[i]) / len(comps[i]))
            for i, comp in enumerate(comps):
                pts = [co[k] for k in comp]
                tmin = min((p - W).dot(f) for p in pts)
                base = [p for p in pts if (p - W).dot(f) < tmin + 0.008]
                B = sum(base, Vector()) / len(base)
                far = sorted(pts, key=lambda p: -(p - B).length)[:max(3, len(pts) // 12)]
                F = sum(far, Vector()) / len(far)
                fi = (F - B).normalized()
                # Se sigue doblando en el mismo sentido que en los nudillos
                ni = axis.cross(fi).normalized()
                bend = thumb if i == thumb_i else 1.0
                R = radius * (1.6 if i == thumb_i else 1.0)
                amax = max_angle * bend
                for k in comp:
                    d = co[k] - B
                    s_ = max(0.0, d.dot(fi))
                    u = d.dot(ni)
                    side = d - fi * d.dot(fi) - ni * u
                    a = min(s_ / R, amax)
                    r = R - u
                    pos = B + fi * (r * math.sin(a)) + ni * (R - r * math.cos(a)) + side
                    rest = s_ - a * R
                    if rest > 0:
                        pos += (fi * math.cos(a) + ni * math.sin(a)) * rest
                    vs[k].co = pos
                    self.base_co[k] = pos.copy()
        me.update()
        self._kd = None

    # ------------------------------------------------------------------ regiones
    def _regions(self):
        """Zonas del cuerpo base guardadas como grupos de vértices R_* (pesos 0..1): se
        conservan al ajustar las proporciones y sirven para pelo, barba, ropa..."""
        me = self.body.data
        groups = {}

        def g(name):
            if name not in groups:
                groups[name] = self.body.vertex_groups.new(name="R_" + name)
            return groups[name]

        def sm(e0, e1, x):
            t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
            return t * t * (3 - 2 * t)

        for v in me.vertices:
            p = v.co
            n = v.normal
            hx, hy = p.x, p.y - 0.02
            r = math.hypot(hx, hy) or 1e-6
            dy = hy / r
            w = {}
            if p.z > 1.42:
                # Cuero cabelludo (línea del pelo: alta al frente, baja atrás)
                hl = 1.55 + (0.085 * dy if dy > 0 else 0.08 * dy)
                w["scalp"] = sm(hl - 0.004, hl + 0.012, p.z) * sm(1.44, 1.47, p.z)
                front = sm(0.25, 0.6, n.y)
                ax = abs(p.x)
                def ell(cx, cz, rx, rz):
                    return 1.0 - sm(0.7, 1.0, math.hypot((ax - cx) / rx, (p.z - cz) / rz))
                # Cejas en arco (más gruesas adentro, se afinan hacia afuera)
                bz = 1.585 + 0.004 * math.cos((ax - 0.035) * 60.0)
                w["brows"] = (1.0 - sm(0.7, 1.0, math.hypot((ax - 0.037) / 0.026, (p.z - bz) / (0.0062 - (ax - 0.02) * 0.06)))) * front * (1 - sm(0.06, 0.066, ax))
                w["lips"] = (1 - sm(0.02, 0.028, ax)) * sm(1.487, 1.492, p.z) * (1 - sm(1.51, 1.515, p.z)) * sm(0.5, 0.8, n.y)
                # Bigote en arco sobre el labio y piocha en la barbilla, unidos por las comisuras
                mz = 1.516 - 22.0 * ax * ax
                w["mustache"] = (1.0 - sm(0.7, 1.0, math.hypot(ax / 0.04, (p.z - mz) / 0.0075))) * front
                w["goatee"] = max(ell(0.0, 1.452, 0.03, 0.03), ell(0.031, 1.488, 0.0075, 0.024)) * front
                w["beard"] = sm(1.415, 1.43, p.z) * (1 - sm(1.535, 1.55, p.z)) * sm(-0.35, -0.1, dy) * (1 - w["lips"])
                w["face"] = sm(0.1, 0.5, dy) * sm(1.43, 1.45, p.z) * (1 - sm(1.62, 1.64, p.z))
            if p.z < 1.47:
                w["torso"] = sm(0.8, 0.86, p.z) * (1 - sm(1.42, 1.45, p.z)) * (1 - sm(0.17, 0.2, abs(p.x)))
            w["arms"] = sm(0.17, 0.21, abs(p.x)) * sm(0.6, 0.62, p.z) * (1 - sm(1.45, 1.48, p.z))
            w["forearms"] = w["arms"] * (1 - sm(1.05, 1.1, p.z))
            w["hands"] = w["arms"] * (1 - sm(0.84, 0.87, p.z))
            # (los pies de la base apuntan hacia afuera: llegan hasta |x| = 0.27)
            lim = 0.3 if p.z < 0.18 else (0.25 if p.z < 0.95 else 0.2)
            w["legs"] = (1 - sm(0.86, 0.92, p.z)) * (1 - sm(lim - 0.03, lim, abs(p.x)))
            w["feet"] = (1 - sm(0.1, 0.13, p.z)) * (1 - sm(0.28, 0.3, abs(p.x)))
            w["neck"] = sm(1.36, 1.4, p.z) * (1 - sm(1.46, 1.5, p.z)) * (1 - sm(0.09, 0.12, abs(p.x)))
            for k, val in w.items():
                if val > 0.001:
                    g(k).add([v.index], val, "REPLACE")

    def region(self, name):
        vg = self.body.vertex_groups.get("R_" + name)
        out = {}
        if vg is None:
            return out
        for v in self.body.data.vertices:
            for ge in v.groups:
                if ge.group == vg.index:
                    out[v.index] = ge.weight
        return out

    # ------------------------------------------------------------------ rostro
    def skin_tint(self, shaved=0.0, bald=0.0, ruddy=1.0, sockets=1.0, extra=None):
        """Pinta el atributo "tinte" de la piel: labios, mejillas y nariz rojizas, ojeras,
        sombra de barba rasurada y del cuero cabelludo rapado. extra: [(región, color)]."""
        me = self.body.data
        ca = me.color_attributes.get("tinte") or me.color_attributes.new("tinte", "FLOAT_COLOR", "POINT")
        regs = {k: self.region(k) for k in ("lips", "beard", "goatee", "mustache", "scalp", "face", "brows")}
        cheek_c = Vector((0.0, 0.09, 1.53))
        for v in me.vertices:
            p = self.base_co[v.index]
            c = Vector((1.0, 1.0, 1.0))
            f = regs["face"].get(v.index, 0.0)
            # Mejillas, nariz y orejas más rojizas
            for cx in (-0.045, 0.045):
                d = (p - Vector((cx, cheek_c.y, cheek_c.z))).length
                c = c.lerp(Vector((1.08, 0.86, 0.84)), max(0.0, 1 - d / 0.03) * 0.6 * ruddy * f)
            dn = (p - Vector((0, 0.13, 1.525))).length
            c = c.lerp(Vector((1.1, 0.84, 0.82)), max(0.0, 1 - dn / 0.025) * 0.6 * ruddy)
            # Ojeras / párpados más oscuros
            for ex in (-0.034, 0.034):
                d = math.hypot(p.x - ex, (p.z - 1.562) * 1.4)
                if p.y > 0.06:
                    c = c.lerp(Vector((0.72, 0.62, 0.62)), max(0.0, 1 - d / 0.022) * 0.7 * sockets)
            c = c.lerp(Vector((1.0, 0.62, 0.6)), regs["lips"].get(v.index, 0.0) * 0.85)
            sh = max(regs["beard"].get(v.index, 0.0), regs["goatee"].get(v.index, 0.0), regs["mustache"].get(v.index, 0.0))
            c = c.lerp(Vector((0.72, 0.74, 0.76)), sh * shaved)
            c = c.lerp(Vector((0.86, 0.85, 0.86)), regs["scalp"].get(v.index, 0.0) * bald)
            if extra:
                for rg, col in extra:
                    c = c.lerp(Vector(col), (rg if isinstance(rg, dict) else self.region(rg)).get(v.index, 0.0))
            ca.data[v.index].color = (c.x, c.y, c.z, 1.0)
        return ca

    def lips_slot(self, skin="piel", lips="labios"):
        w = self.region("lips")
        me = self.body.data
        for poly in me.polygons:
            a = sum(w.get(i, 0.0) for i in poly.vertices) / len(poly.vertices)
            poly.material_index = 1 if a > 0.5 else 0
        self.body["slots"] = [skin, lips]

    def eye_mats(self, white="esclera", iris="ojos", iris_size=0.55):
        """Iris y pupila (material `iris`, el que brilla en los jefes) en el frente del ojo."""
        for e in self.eyes:
            me = e.data
            c = sum((v.co for v in me.vertices), Vector()) / len(me.vertices)
            r = max((v.co - c).length for v in me.vertices)
            for poly in me.polygons:
                p = poly.center - c
                poly.material_index = 1 if p.y > r * iris_size else 0
            e["slots"] = [white, iris]

    def hair(self, name, region, mat="pelo", offset=0.006, noise=0.004, thresh=0.15, smooth=1, thick=0.0, fn=None, extrude=None):
        """Pelo, barba o cejas: casco de la región inflado con ruido (mechones); se afina en
        las orillas para fundirse con la piel."""
        return self.piece(name, region, offset=offset, thick=thick, mat=mat, thresh=thresh, smooth=smooth, noise=noise, fn=fn, extrude=extrude, taper=True)

    # ------------------------------------------------------------------ armaduras
    def zone(self, center, radius, fn=None, soft=0.25):
        """Región esférica en coordenadas de la malla BASE (antes de ajustar): útil para
        hombreras, rodilleras, etc. Devuelve {vértice: peso}."""
        c = Vector(center)
        out = {}
        for i, p in enumerate(self.base_co):
            d = (p - c).length
            if d < radius and (fn is None or fn(p)):
                out[i] = min(1.0, (radius - d) / (radius * soft))
        return out

    def band(self, region, lo, hi, axis=2):
        """Parte de una región entre dos alturas (u otro eje) de la malla base."""
        w = region if isinstance(region, dict) else self.region(region)
        return {i: v for i, v in w.items() if lo <= self.base_co[i][axis] < hi}

    def plate(self, name, region, offset=0.03, thick=0.012, mat="acero", trim="oro", trim_r=0.008, glow=None, glow_r=0.0022,
              flutes=None, smooth=3, thresh=0.5, fn=None, bevel=0.004, extrude=None, noise=0.0, rigid=None):
        """Placa de armadura ajustada al cuerpo: casco de la región inflado `offset`, con
        grosor, bordes biselados, ribete en todo el borde (`trim`) y, si se pide, una costura
        tecnológica que brilla un poco hacia adentro del borde (`glow`, material emisivo).
        flutes=(cantidad, profundidad, eje 0/2): acanaladuras como en las armaduras góticas."""
        ob = self.piece(name, region, offset=offset, mat=mat, thresh=thresh, smooth=smooth, fn=fn, extrude=extrude, noise=noise)
        if rigid:
            self._rigid(ob, rigid)
        if flutes:
            n, depth, ax = flutes
            me = ob.data
            me.calc_normals_split() if hasattr(me, "calc_normals_split") else None
            for v in me.vertices:
                v.co += v.normal * depth * abs(math.sin(v.co[ax] * n * math.pi))
        loops = self._boundary_loops(ob)
        if thick > 0:
            m = ob.modifiers.new("grosor", "SOLIDIFY")
            m.thickness = thick
            m.offset = 1.0
            m.use_rim = True
        for k, (pts, nrm) in enumerate(loops):
            if trim and len(pts) > 3:
                t = self._tube("%s_ribete_%d" % (name, k), [p + n * thick * 0.5 for p, n in zip(pts, nrm)], trim_r, trim, cyclic=True)
                if rigid:
                    self._rigid(t, rigid)
            if glow and len(pts) > 24 and k == 0:
                inner = self._inset(ob, pts, nrm, 0.03)
                t = self._tube("%s_costura_%d" % (name, k), [p + n * (thick + 0.0015) for p, n in zip(inner, nrm)], glow_r, glow, cyclic=True)
                if rigid:
                    self._rigid(t, rigid)
        return ob

    def _rigid(self, ob, bone):
        """La pieza sigue solo a un hueso (canónico o del jefe), sin estirarse."""
        bone = self.names.get(bone, bone)
        for vg in list(ob.vertex_groups):
            ob.vertex_groups.remove(vg)
        vg = ob.vertex_groups.new(name=bone)
        vg.add(range(len(ob.data.vertices)), 1.0, "REPLACE")

    def lames(self, name, region, lo, hi, n, axis=2, gap=0.012, offset=0.03, step=0.008, overlap_down=True, glow_first=True, **kw):
        """Láminas articuladas: la región se corta en `n` bandas entre lo y hi (eje de la
        base) y cada una queda un poco más afuera que la anterior, encimadas como escamas."""
        w = region if isinstance(region, dict) else self.region(region)
        h = (hi - lo) / n
        out = []
        for i in range(n):
            a = lo + i * h
            b = a + h + gap * 0.5
            sub = {k: v for k, v in w.items() if a - gap * 0.5 <= self.base_co[k][axis] < b}
            k = (n - 1 - i) if overlap_down else i
            kw2 = dict(kw)
            if glow_first and k != n - 1:
                kw2["glow"] = None          # solo la lámina de encima lleva costura
            out.append(self.plate("%s_%d" % (name, i), sub, offset=offset + k * step, **kw2))
        return out

    def strap(self, name, a, b, width, region=None, offset=0.05, mat="cuero", thick=0.008, trim=None, fn=None):
        """Correa o banda que se ajusta al cuerpo: vértices a menos de width/2 de la línea a-b
        (coordenadas de la base)."""
        a, b = Vector(a), Vector(b)
        ab = b - a
        w = {}
        allowed = None if region is None else (region if isinstance(region, dict) else self.region(region))
        for i, p in enumerate(self.base_co):
            if allowed is not None and i not in allowed:
                continue
            t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
            d = (a + ab * t - p)
            # distancia sin contar la profundidad (la correa envuelve el cuerpo)
            d = math.hypot(d.x, d.z) if abs(ab.y) < abs(ab.length) * 0.5 else d.length
            if d < width * 0.5:
                w[i] = 1.0
        return self.plate(name, w, offset=offset, thick=thick, mat=mat, trim=trim, smooth=2, fn=fn)

    def _boundary_loops(self, ob):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.normal_update()
        edges = [e for e in bm.edges if e.is_boundary]
        adj = {}
        for e in edges:
            a, b = e.verts
            adj.setdefault(a, []).append(b)
            adj.setdefault(b, []).append(a)
        seen = set()
        loops = []
        for start in list(adj.keys()):
            if start in seen:
                continue
            chain = [start]
            seen.add(start)
            cur = start
            while True:
                nxt = [v for v in adj[cur] if v not in seen]
                if not nxt:
                    break
                cur = nxt[0]
                seen.add(cur)
                chain.append(cur)
            if len(chain) > 3:
                loops.append(([v.co.copy() for v in chain], [v.normal.copy() for v in chain]))
        bm.free()
        return loops

    def _inset(self, ob, pts, nrm, dist):
        """Puntos del borde movidos `dist` hacia el centro de la placa (sobre la superficie)."""
        c = sum(pts, Vector()) / len(pts)
        out = []
        for p, n in zip(pts, nrm):
            d = (c - p)
            d = d - n * d.dot(n)
            out.append(p + d.normalized() * dist if d.length > 1e-6 else p)
        return out

    def _tube(self, name, pts, r, mat, cyclic=False, relax=6):
        # Suaviza el recorrido (los bordes de las regiones son dentados)
        n = len(pts)
        for _ in range(relax):
            pts = [(pts[(i - 1) % n] + pts[i] * 2 + pts[(i + 1) % n]) * 0.25 if (cyclic or 0 < i < n - 1) else pts[i] for i in range(n)]
        cu = bpy.data.curves.new(name, "CURVE")
        cu.dimensions = "3D"
        cu.bevel_depth = r
        cu.bevel_resolution = 1
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, p in enumerate(pts):
            sp.points[i].co = (p.x, p.y, p.z, 1)
        sp.use_cyclic_u = cyclic
        ob = bpy.data.objects.new(name, cu)
        _link(ob)
        _select_only(ob)
        bpy.ops.object.convert(target="MESH")
        ob = bpy.context.view_layer.objects.active
        for poly in ob.data.polygons:
            poly.use_smooth = True
        self.weights_from_body(ob)
        self._as_part(ob, mat)
        return ob

    def at(self, p):
        """Punto de la malla BASE llevado a donde quedó en el cuerpo ajustado (sigue el
        desplazamiento de los vértices cercanos). Para colocar accesorios."""
        if getattr(self, "_kd", None) is None:
            self._kd = KDTree(len(self.base_co))
            for i, c in enumerate(self.base_co):
                self._kd.insert(c, i)
            self._kd.balance()
        p = Vector(p)
        vs = self.body.data.vertices
        acc = Vector()
        wsum = 0.0
        for co, i, d in self._kd.find_n(p, 8):
            w = 1.0 / (d + 1e-4)
            acc += (vs[i].co - self.base_co[i]) * w
            wsum += w
        # La escala local se toma de la distancia al vecino más cercano
        return tuple(p + acc / wsum)

    def attach(self, ob, mat=None):
        """Pieza modelada con bk (box, cyl...) que debe moverse con la piel (pesos del cuerpo)."""
        if ob in bk.PARTS:
            bk.PARTS.remove(ob)
        _select_only(ob)
        for m in list(ob.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        self.weights_from_body(ob)
        self._as_part(ob, mat or ob.get("mat", "acero"))
        return ob

    # ------------------------------------------------------------------ esqueleto y proporciones
    def fit(self, tgt, girth=None, names=None, extra_bones=None):
        """Pone el esqueleto en las articulaciones de la base, pesa la piel y la deforma hasta
        las articulaciones objetivo `tgt` (de targets()). girth: hueso -> (ancho, fondo) o un
        número, para engrosar o adelgazar. names: hueso canónico -> nombre del jefe (las
        articulaciones de su código). extra_bones: [(nombre, padre, cabeza, cola)] ya en
        coordenadas finales (capas, borlas...)."""
        girth = girth or {}
        names = names or {}
        spec = [(n, p, CANON[h], CANON[t]) for n, p, h, t in BONES]
        arm = bk.armature(spec)
        for b in arm.data.bones:
            b.inherit_scale = "NONE"
        self.arm = arm
        # Pesos automáticos (los ojos van rígidos a la cabeza)
        _select_only(self.body, arm, active=arm)
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
        for e in self.eyes:
            vg = e.vertex_groups.new(name="head")
            vg.add(range(len(e.data.vertices)), 1.0, "REPLACE")
            e.parent = arm
            mod = e.modifiers.new("Armature", "ARMATURE")
            mod.object = arm
        # Pose que lleva cada hueso a su objetivo
        bk.set_pose({})
        order = [n for n, _, _, _ in BONES]
        tgt_bone = {n: (tgt[h], tgt[t]) for n, _, h, t in BONES}
        for n in order:
            pb = arm.pose.bones[n]
            rest = pb.bone.matrix_local
            head, tail = tgt_bone[n]
            d = (tail - head)
            rest_y = rest.to_3x3().col[1].normalized()
            q = rest_y.rotation_difference(d.normalized())
            rot = q.to_matrix() @ rest.to_3x3().normalized()
            gx = girth.get(n, 1.0)
            if isinstance(gx, (int, float)):
                gx = (gx, gx)
            sy = d.length / max(pb.bone.length, 1e-6)
            m = Matrix.Translation(head) @ rot.to_4x4() @ Matrix.Diagonal((gx[0], sy, gx[1], 1.0))
            pb.matrix = m
            bpy.context.view_layer.update()
        # Aplica la pose como forma y como reposo
        for o in [self.body] + self.eyes:
            _select_only(o)
            bpy.ops.object.modifier_apply(modifier=o.modifiers[0].name)
        _select_only(arm)
        bpy.ops.object.mode_set(mode="POSE")
        bpy.ops.pose.armature_apply(selected=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        # Escala de los huesos aplicada: quita la escala que quedó en el reposo
        # Nombres del jefe
        for canon, boss in names.items():
            if canon in arm.data.bones:
                arm.data.bones[canon].name = boss
                for o in [self.body] + self.eyes:
                    vg = o.vertex_groups.get(canon)
                    if vg:
                        vg.name = boss
        if extra_bones:
            bpy.context.view_layer.objects.active = arm
            bpy.ops.object.mode_set(mode="EDIT")
            for n, parent, h, t in extra_bones:
                eb = arm.data.edit_bones.new(n)
                eb.head = h
                eb.tail = t
                eb.parent = arm.data.edit_bones[parent]
            bpy.ops.object.mode_set(mode="OBJECT")
        self.names = names
        # Partes listas para bk.finish (conservan sus grupos de vértices)
        self._as_part(self.body, "piel")
        for e in self.eyes:
            self._as_part(e, "esclera")
        return arm

    def bone(self, canon):
        return self.names.get(canon, canon)

    def _as_part(self, ob, mat, slots=None):
        for m in list(ob.modifiers):
            if m.type == "ARMATURE":
                ob.modifiers.remove(m)
        ob.parent = None
        ob["skinned"] = True
        ob["mat"] = mat
        if slots:
            ob["slots"] = slots
        bk.PARTS.append(ob)

    # ------------------------------------------------------------------ utilidades de malla
    def piece(self, name, region, offset=0.01, thick=0.0, mat="tela", thresh=0.5, smooth=2, noise=0.0, fn=None, extrude=None, taper=False, tatter=None):
        """Copia de una región del cuerpo, inflada `offset` hacia afuera (ropa, placas).
        fn(co, normal) -> bool permite recortar más. extrude: (dz, ensanche) estira el
        borde de abajo hacia abajo (faldones, batas, togas)."""
        w = region if isinstance(region, dict) else self.region(region)
        ob = self.body.copy()
        ob.data = self.body.data.copy()
        ob.name = name
        _link(ob)
        for k in [k for k in ob.keys()]:
            del ob[k]
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.verts.ensure_lookup_table()
        wl = bm.verts.layers.float.new("peso_region")
        for v in bm.verts:
            v[wl] = w.get(v.index, 0.0)
        kill = [v for v in bm.verts if w.get(v.index, 0.0) < thresh or (fn and not fn(self.base_co[v.index], v.normal))]
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
        for f in bm.faces:
            f.material_index = 0
        # Quita astillas: caras sueltas del borde y vértices con una sola cara
        for _ in range(2):
            thin = [v for v in bm.verts if len(v.link_faces) <= 1]
            bmesh.ops.delete(bm, geom=thin, context="VERTS")
        bnd = [v for v in bm.verts if v.is_boundary]
        for _ in range(3):
            bmesh.ops.smooth_vert(bm, verts=bnd, factor=0.6, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        bm.normal_update()
        for _ in range(smooth):
            bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        bm.normal_update()
        nrm = {v: v.normal.copy() for v in bm.verts}
        for v in bm.verts:
            o = offset
            if taper:
                o *= min(1.0, max(0.0, (v[wl] - thresh) / max(1e-4, 1.0 - thresh)) ** 0.5)
            if noise:
                o += (math.sin(v.co.x * 61) * math.sin(v.co.y * 53) * math.sin(v.co.z * 47)) * noise
            v.co += nrm[v] * o
        if extrude:
            dz, flare = extrude
            edges = [e for e in bm.edges if e.is_boundary and min(e.verts[0].co.z, e.verts[1].co.z) < self._low_z(bm) + 0.06]
            r = bmesh.ops.extrude_edge_only(bm, edges=edges)
            nv = [g for g in r["geom"] if isinstance(g, bmesh.types.BMVert)]
            cx = sum(v.co.x for v in nv) / max(1, len(nv))
            cy = sum(v.co.y for v in nv) / max(1, len(nv))
            for v in nv:
                out = Vector((v.co.x - cx, v.co.y - cy, 0))
                v.co += Vector((0, 0, -dz)) + out * flare
        if tatter:
            # Jirones: se pierden caras al azar cerca del borde de abajo (más cuanto más abajo)
            h, amount = tatter
            low = self._low_z(bm)
            bm.faces.ensure_lookup_table()
            dead = []
            for f in bm.faces:
                c = f.calc_center_median()
                k = 1.0 - (c.z - low) / h
                if k > 0 and self.rng.random() < k * amount + 0.25 * k * math.sin(c.x * 40.0 + c.y * 30.0):
                    dead.append(f)
            bmesh.ops.delete(bm, geom=dead, context="FACES")
            loose = [v for v in bm.verts if not v.link_faces]
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bm.to_mesh(ob.data)
        bm.free()
        if thick > 0:
            m = ob.modifiers.new("grosor", "SOLIDIFY")
            m.thickness = thick
            m.offset = 1.0
        self._as_part(ob, mat)
        return ob

    @staticmethod
    def _low_z(bm):
        return min(v.co.z for v in bm.verts)

    def weights_from_body(self, ob):
        """Copia los pesos de la piel al objeto (el más cercano), para que se mueva con ella."""
        bones = [b.name for b in self.arm.data.bones]
        for b in bones:
            if ob.vertex_groups.get(b) is None:
                ob.vertex_groups.new(name=b)
        m = ob.modifiers.new("pesos", "DATA_TRANSFER")
        m.object = self.body
        m.use_vert_data = True
        m.data_types_verts = {"VGROUP_WEIGHTS"}
        m.vert_mapping = "POLYINTERP_NEAREST"
        m.layers_vgroup_select_src = "ALL"
        m.layers_vgroup_select_dst = "NAME"
        _select_only(ob)
        bpy.ops.object.modifier_apply(modifier="pesos")
        for vg in list(ob.vertex_groups):
            if vg.name.startswith("R_"):
                ob.vertex_groups.remove(vg)
        ob["skinned"] = True
        ob.parent = None


def clean_regions(obs):
    for ob in obs:
        for vg in list(ob.vertex_groups):
            if vg.name.startswith("R_"):
                ob.vertex_groups.remove(vg)
