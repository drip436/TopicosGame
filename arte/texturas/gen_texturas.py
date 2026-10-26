"""Genera las texturas de detalle (sin costuras) de los materiales del campus.

    python3 arte/texturas/gen_texturas.py [carpeta_salida]     (por defecto: texturas/)

Por cada material sale:
  <nombre>_n.png   mapa de normales (formato OpenGL, el de Godot)
  <nombre>_d.png   R = detalle de color (0.5 = sin cambio), G = rugosidad,
                   B = máscara (juntas/mortero/óxido según el material)

Los shaders del mundo (shaders/*.gdshader) las proyectan en coordenadas de mundo
(triplanar), así que no necesitan UV. El ruido se genera filtrando ruido blanco en el
espacio de frecuencias, que es periódico: la textura se repite sin costuras.
"""
import os
import sys
import numpy as np
from PIL import Image

N = 1024
RNG = np.random.default_rng(2026)
_fx = np.fft.fftfreq(N)[None, :]
_fy = np.fft.fftfreq(N)[:, None]
_FR = np.sqrt(_fx ** 2 + _fy ** 2)


def banda(f0, f1, aniso=(1.0, 1.0)):
    """Ruido periódico con frecuencias entre f0 y f1 (ciclos por imagen), normalizado 0..1."""
    fr = np.sqrt((_fx * N * aniso[0]) ** 2 + (_fy * N * aniso[1]) ** 2)
    filt = np.exp(-((np.log(fr + 1e-6) - np.log(np.sqrt(f0 * f1))) ** 2) / (2 * (np.log(f1 / f0) / 2 + 0.3) ** 2))
    filt[0, 0] = 0
    w = RNG.standard_normal((N, N))
    r = np.real(np.fft.ifft2(np.fft.fft2(w) * filt))
    r -= r.min()
    return r / r.max()


def fbm(f0, octavas, gan=0.5, aniso=(1.0, 1.0)):
    out = np.zeros((N, N))
    a = 1.0
    tot = 0.0
    f = f0
    for _ in range(octavas):
        out += banda(f, f * 2, aniso) * a
        tot += a
        a *= gan
        f *= 2
    return out / tot


def suave(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def desenfocar(h, sigma):
    """Desenfoque gaussiano periódico."""
    g = np.exp(-2 * np.pi ** 2 * sigma ** 2 * _FR ** 2)
    return np.real(np.fft.ifft2(np.fft.fft2(h) * g))


def manchas(n, rmin, rmax, prof=1.0):
    """Huecos/bultos circulares periódicos (poros, abolladuras)."""
    h = np.zeros((N, N))
    yy, xx = np.mgrid[0:N, 0:N]
    for _ in range(n):
        cx, cy = RNG.uniform(0, N, 2)
        r = RNG.uniform(rmin, rmax)
        dx = (xx - cx + N / 2) % N - N / 2
        dy = (yy - cy + N / 2) % N - N / 2
        d = np.sqrt(dx * dx + dy * dy) / r
        h += np.clip(1 - d * d, 0, 1) ** 1.5 * prof * RNG.uniform(0.5, 1.0)
    return h


def grietas(f, ancho, umbral=0.5):
    """Líneas finas tipo grieta: cruce por 0.5 de un ruido de banda baja."""
    n = fbm(f, 3, 0.45)
    d = np.abs(n - umbral)
    return 1 - suave(d, 0, ancho)


def rayones(n, largo, ancho=1.2, angulo=None):
    h = np.zeros((N, N))
    for _ in range(n):
        x, y = RNG.uniform(0, N, 2)
        a = RNG.uniform(0, np.pi) if angulo is None else angulo + RNG.normal(0, 0.25)
        L = RNG.uniform(largo * 0.3, largo)
        k = int(L)
        for i in range(k):
            px = int(x + np.cos(a) * i) % N
            py = int(y + np.sin(a) * i) % N
            for o in range(-int(ancho), int(ancho) + 1):
                h[(py + o) % N, px] = max(h[(py + o) % N, px], 1 - abs(o) / (ancho + 0.5))
    return h


def normales(h, fuerza):
    """Mapa de normales a partir de la altura (diferencias periódicas)."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * fuerza
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * fuerza
    nx, ny, nz = -dx, dy, np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5


def guardar(out, nombre, h, fuerza, color, rug, mask):
    nm = normales(h, fuerza)
    Image.fromarray((np.clip(nm, 0, 1) * 255).astype(np.uint8)).save(os.path.join(out, nombre + "_n.png"))
    d = np.stack([np.clip(color, 0, 1), np.clip(rug, 0, 1), np.clip(mask, 0, 1)], -1)
    Image.fromarray((d * 255).astype(np.uint8)).save(os.path.join(out, nombre + "_d.png"))
    print("ok", nombre)


# ---------------------------------------------------------------- materiales
# Escala de referencia: la textura de concreto cubre 2 m, ladrillo 1.2 x 1.2 m, etc.
# (la escala real la ponen los shaders).

def concreto(out):
    base = fbm(3, 6, 0.55)
    grano = banda(180, 400)
    poros = manchas(900, 1.5, 4.5)
    agregado = manchas(500, 3, 8, 0.4)
    grieta = grietas(2, 0.006) * suave(fbm(2, 2), 0.45, 0.7)
    h = base * 1.0 + grano * 0.25 - poros * 0.6 + agregado * 0.25 - grieta * 1.4
    color = 0.5 + (base - 0.5) * 0.45 + (grano - 0.5) * 0.12 - poros * 0.18 - grieta * 0.3 + (fbm(4, 4) - 0.5) * 0.25
    rug = 0.75 + (grano - 0.5) * 0.3 - (base - 0.5) * 0.2
    mask = np.clip(poros * 0.6 + grieta, 0, 1)
    guardar(out, "concreto", h, 9.0, color, rug, mask)


def ladrillo(out):
    """Hiladas: 8 por textura en alto (7.5 cm) y 4 ladrillos por fila (aparejo a soga)."""
    yy, xx = np.mgrid[0:N, 0:N].astype(float)
    filas = 16
    hf = N / filas
    fila = np.floor(yy / hf)
    off = (fila % 2) * 0.5
    u = xx / (N / 4) + off
    bid = np.floor(u) + fila * 7.0
    fu = u - np.floor(u)
    fv = (yy / hf) - fila
    junta_u = np.minimum(fu, 1 - fu) * (N / 4)
    junta_v = np.minimum(fv, 1 - fv) * hf
    dj = np.minimum(junta_u, junta_v)
    mortero = 1 - suave(dj, 3.5, 6.5)
    # Variación por ladrillo
    tabla = RNG.uniform(0, 1, 4096)
    var = tabla[(bid.astype(int) * 13 + 7) % 4096]
    var2 = tabla[(bid.astype(int) * 29 + 3) % 4096]
    ruido = fbm(6, 5, 0.55)
    grano = banda(150, 380)
    desport = suave(fbm(10, 3) + (1 - suave(dj, 3, 22)) * 0.5, 0.78, 0.86)  # bordes despostillados
    bombeo = suave(dj, 3, 14) * 0.4
    h = bombeo + ruido * 0.25 + grano * 0.12 - desport * 0.5 - mortero * 0.6 + var2 * 0.1
    color = 0.5 + (var - 0.5) * 0.35 + (ruido - 0.5) * 0.25 + (grano - 0.5) * 0.08 - desport * 0.1
    color = np.where(mortero > 0.5, 0.55 + (grano - 0.5) * 0.2, color)
    rug = 0.8 + (grano - 0.5) * 0.2 + mortero * 0.1
    guardar(out, "ladrillo", h, 7.0, color, rug, np.clip(mortero + desport * 0.5, 0, 1))


def metal(out):
    base = fbm(3, 5, 0.5)
    cepillado = fbm(2, 6, 0.6, aniso=(0.04, 1.0))
    ray = rayones(420, 160, 0.8)
    abolla = desenfocar(manchas(40, 18, 60), 4)
    oxido = suave(fbm(3, 6, 0.6) + manchas(160, 3, 14, 0.4), 0.62, 0.78)
    picado = manchas(1400, 0.8, 2.2) * oxido
    h = cepillado * 0.25 + base * 0.3 - abolla * 0.6 - ray * 0.25 - picado * 0.5 + oxido * 0.15
    color = 0.5 + (base - 0.5) * 0.3 + (cepillado - 0.5) * 0.12 + ray * 0.12 - oxido * 0.2
    rug = 0.38 + (cepillado - 0.5) * 0.25 - ray * 0.15 + oxido * 0.5
    guardar(out, "metal", h, 6.0, color, rug, oxido)


def madera(out):
    veta = fbm(3, 6, 0.6, aniso=(0.06, 1.0))
    anillos = np.sin(veta * 60.0) * 0.5 + 0.5
    nudos = desenfocar(manchas(10, 8, 22), 2)
    poro = banda(200, 450, aniso=(0.15, 1.0))
    yy = np.mgrid[0:N, 0:N][0]
    junta = (yy % (N // 6)) < 3
    h = anillos * 0.35 + poro * 0.2 - junta * 1.0 + nudos * 0.4
    color = 0.5 + (anillos - 0.5) * 0.3 + (veta - 0.5) * 0.3 - nudos * 0.25 - junta * 0.3
    rug = 0.65 + (poro - 0.5) * 0.25
    guardar(out, "madera", h, 5.0, color, rug, junta * 1.0)


def yeso(out):
    base = fbm(4, 5, 0.5)
    grano = banda(120, 300)
    descasc = suave(fbm(3, 5, 0.6), 0.66, 0.7)
    mancha = suave(fbm(2, 4, 0.6, aniso=(1.0, 0.25)), 0.55, 0.85)  # escurrimientos verticales
    h = base * 0.4 + grano * 0.15 - descasc * 0.5
    color = 0.52 + (base - 0.5) * 0.15 + (grano - 0.5) * 0.06 - mancha * 0.22 - descasc * 0.12
    rug = 0.85 + (grano - 0.5) * 0.15
    guardar(out, "yeso", h, 5.0, color, rug, descasc)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "texturas"
    os.makedirs(out, exist_ok=True)
    pedidos = sys.argv[2:] or ["concreto", "ladrillo", "metal", "madera", "yeso"]
    for p in pedidos:
        globals()[p](out)
