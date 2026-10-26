// Piso de baldosas en coordenadas de mundo para el campus: adoquines de los
// caminos, mármol de la biblioteca, piso técnico del centro de cómputo, azulejo
// del laboratorio, losas radiales del Aula Magna y cajones del estacionamiento.
// Incluye suciedad, baldosas rotas, charcos y ondas de lluvia.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// 0 = rejilla, 1 = ajedrez, 2 = hiladas (ladrillo), 3 = radial alrededor de `center`
uniform int pattern = 0;
uniform vec2 tile_size = vec2(1.0, 1.0);
uniform vec3 color_a : source_color = vec3(0.4, 0.39, 0.37);
uniform vec3 color_b : source_color = vec3(0.3, 0.29, 0.28);
uniform vec3 grout_color : source_color = vec3(0.08, 0.08, 0.08);
uniform float grout_width = 0.04;
// Brillo en las juntas (piso técnico) o en los anillos grabados (patrón radial).
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float glow_energy = 0.0;
uniform vec2 center = vec2(0.0);
uniform float dirt : hint_range(0.0, 1.0) = 0.4;
uniform float broken : hint_range(0.0, 1.0) = 0.06;
uniform float wetness : hint_range(0.0, 1.0) = 0.6;
uniform float puddle_coverage : hint_range(0.0, 1.0) = 0.35;
uniform float rain_intensity : hint_range(0.0, 2.0) = 1.0;
// Relieve (texturas/concreto_*.png): poros, desgaste y bisel de cada baldosa
uniform sampler2D det_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D det_d : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float det_scale = 0.5;
uniform float det_strength = 0.8;
uniform float bevel = 0.5;

#include "res://shaders/detalle.gdshaderinc"

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec2 ripple_layer(vec2 uv, float t) {
	vec2 cell = floor(uv);
	vec2 n = vec2(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 d = uv - (c + hash22(c));
			float dist = length(d);
			float ph = fract(t + hash12(c * 1.37));
			float k = dist - ph * 0.9;
			float w = sin(k * 31.0) * exp(-k * k * 90.0) * (1.0 - ph) * (1.0 - ph);
			n += (d / max(dist, 0.0001)) * w;
		}
	}
	return n;
}

void fragment() {
	vec2 p = wpos.xz;
	float n2 = texture(noise_tex, p * 0.07).r;
	float n3 = texture(noise_tex, p * 0.55).r;

	vec2 tuv;
	float ring_glow = 0.0;
	if (pattern == 3) {
		vec2 d = p - center;
		float r = length(d);
		float ri = floor(r / tile_size.y);
		float segs = max(6.0, floor(6.2831853 * (ri + 0.5) * tile_size.y / tile_size.x));
		tuv = vec2((atan(d.y, d.x) / 6.2831853 + 0.5) * segs, r / tile_size.y);
		float rf = fract(r / tile_size.y);
		float inlay = step(mod(ri, 4.0), 0.5) * (1.0 - smoothstep(0.0, 0.06, abs(rf - 0.5)));
		ring_glow = inlay * step(1.0, ri);
	} else {
		tuv = p / tile_size;
		if (pattern == 2) {
			tuv.x += 0.5 * mod(floor(tuv.y), 2.0);
		}
	}
	vec2 tid = floor(tuv);
	vec2 tf = fract(tuv);
	float edge_d = min(min(tf.x, 1.0 - tf.x), min(tf.y, 1.0 - tf.y));
	float grout = 1.0 - smoothstep(0.0, grout_width, edge_d);
	float th = hash12(tid + 3.7);

	vec3 tile;
	if (pattern == 1) {
		tile = mix(color_a, color_b, mod(tid.x + tid.y, 2.0));
	} else {
		tile = mix(color_a, color_b, th);
	}
	tile *= (0.82 + 0.36 * n3) * (0.92 + 0.16 * th);
	float miss = step(th, broken);
	tile = mix(tile, vec3(0.1, 0.085, 0.07) * (0.7 + 0.6 * n3), miss);
	float grime = smoothstep(0.35, 0.8, n2) * dirt;
	tile *= 1.0 - grime * 0.55;
	vec4 dd = texture(det_d, p * det_scale);
	tile *= 0.35 + dd.r * 1.3;
	vec3 base = mix(tile, grout_color, grout * (1.0 - miss));

	float crack = (1.0 - smoothstep(0.0, 0.012, abs(texture(noise_tex, p * 0.06 + vec2(9.0, 2.0)).r - 0.5))) * dirt;
	base *= 1.0 - crack * 0.6;

	float pm = texture(noise_tex, p * 0.05 + vec2(3.1, 7.7)).r + (n3 - 0.5) * 0.12 + miss * 0.25;
	float thr = mix(0.85, 0.4, puddle_coverage);
	float puddle = smoothstep(thr, thr + 0.035, pm);
	float damp = smoothstep(thr - 0.12, thr, pm);
	vec2 rip = (ripple_layer(p * 2.2, TIME * 1.3) * 0.6 + ripple_layer(p * 3.7 + 13.0, TIME * 1.7 + 0.3) * 0.4) * rain_intensity;

	vec3 col = base * mix(1.0, 0.6, wetness);
	col = mix(col, base * 0.25 + vec3(0.008, 0.01, 0.013), puddle);
	float rough = mix(0.85, 0.4, wetness);
	rough = mix(rough, 0.95, grout * 0.4);
	rough = mix(rough, 0.25, damp * 0.6 * wetness);
	rough = mix(rough, 0.03, puddle);

	vec2 bump = vec2(n3 - 0.5) * 0.14 * (1.0 - puddle) + rip * 0.3 * puddle;
	vec3 nw = vec3(-bump.x, 1.0, -bump.y);
	float seco = 1.0 - puddle;
	nw += piso_n(det_n, p, det_scale, det_strength * seco);
	if (pattern != 3) {
		vec2 ts = tf * tile_size;
		float ed = min(min(ts.x, tile_size.x - ts.x), min(ts.y, tile_size.y - ts.y));
		nw += bisel(tf, ed, 0.05, bevel) * (1.0 - miss) * seco;
		// Cada baldosa queda un poco chueca
		nw += vec3(hash12(tid + 9.1) - 0.5, 0.0, hash12(tid + 4.3) - 0.5) * 0.08 * seco;
	}
	nw = normalize(nw);
	rough = mix(rough, rough * (0.6 + dd.g * 0.6), seco);

	float pulse = 0.7 + 0.3 * sin(TIME * 1.7 + (p.x + p.y) * 0.15);
	vec3 glow = glow_color * glow_energy * pulse * (grout * (1.0 - miss) * step(float(pattern), 2.5) + ring_glow);
	glow *= 1.0 - grime * 0.7;

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	EMISSION = glow;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
