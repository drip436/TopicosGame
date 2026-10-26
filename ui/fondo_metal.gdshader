shader_type canvas_item;
// Fondo de metal oscuro cepillado con placas, remaches, rejilla hexagonal tenue,
// líneas de neón azul que recorren las juntas y viñeta.

uniform vec4 neon : source_color = vec4(0.25, 0.75, 1.0, 1.0);
uniform float plates = 6.0;
uniform float neon_strength = 1.0;
uniform float aspect = 1.777;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float hexgrid(vec2 p) {
	p.x *= 1.1547;
	p.y += mod(floor(p.x), 2.0) * 0.5;
	p = abs(fract(p) - 0.5);
	return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	// Metal cepillado: ruido estirado en horizontal
	float brushed = noise(vec2(p.x * 3.0, p.y * 420.0)) * 0.5 + noise(vec2(p.x * 1.5, p.y * 160.0)) * 0.5;
	vec3 col = mix(vec3(0.045, 0.05, 0.06), vec3(0.11, 0.12, 0.14), brushed);
	col *= 0.85 + 0.3 * noise(p * 3.0);
	// Placas y juntas
	vec2 g = p * vec2(plates * 0.55, plates);
	vec2 fp = fract(g);
	float seam = min(min(fp.x, 1.0 - fp.x) * 0.55, min(fp.y, 1.0 - fp.y));
	float seam_line = 1.0 - smoothstep(0.0, 0.018, seam);
	col *= 1.0 - seam_line * 0.55;
	col += vec3(0.05) * smoothstep(0.02, 0.0, abs(seam - 0.025));
	// Remaches en las esquinas de cada placa
	vec2 cr = min(fp, 1.0 - fp);
	float rivet = 1.0 - smoothstep(0.012, 0.02, length(cr - vec2(0.05)));
	col += vec3(0.16, 0.17, 0.19) * rivet;
	// Rejilla hexagonal tenue
	float hx = hexgrid(p * 22.0);
	col += neon.rgb * 0.035 * (1.0 - smoothstep(0.0, 0.06, hx));
	// Neón que recorre las juntas horizontales
	float row = floor(g.y);
	float pulse = fract(p.x * 0.25 - TIME * (0.08 + 0.05 * hash(vec2(row, 3.0))) + hash(vec2(row, 7.0)));
	float trail = smoothstep(0.0, 0.25, pulse) * smoothstep(0.3, 0.25, pulse);
	float hline = 1.0 - smoothstep(0.0, 0.006, abs(fp.y - 0.0));
	col += neon.rgb * hline * (0.25 + 1.6 * trail) * neon_strength;
	// Brillo de neón difuso desde abajo y viñeta
	col += neon.rgb * 0.08 * smoothstep(0.55, 1.0, uv.y);
	vec2 c = uv - 0.5;
	col *= clamp(1.15 - dot(c, c) * 1.6, 0.0, 1.0);
	// Líneas de barrido muy sutiles
	col *= 0.96 + 0.04 * sin(uv.y * 900.0);
	COLOR = vec4(col, 1.0);
}
