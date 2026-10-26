// Suelo mojado de la arena: plaza de adoquines, asfalto, pasto muerto,
// grietas, quemaduras de batalla y charcos con ondas de lluvia animadas.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float plaza_radius = 22.0;
uniform float road_z = 38.0;
uniform float puddle_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float rain_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.85;
// Relieve de concreto (texturas/concreto_*.png)
uniform sampler2D det_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D det_d : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float det_scale = 0.45;
uniform float det_strength = 1.0;

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

// Ondas circulares de gotas de lluvia (gradiente aproximado de la altura).
vec2 ripple_layer(vec2 uv, float t) {
	vec2 cell = floor(uv);
	vec2 n = vec2(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 center = c + hash22(c);
			float ph = fract(t + hash12(c * 1.37));
			vec2 d = uv - center;
			float dist = length(d);
			float k = dist - ph * 0.9;
			float fade = (1.0 - ph) * (1.0 - ph);
			float w = sin(k * 31.0) * exp(-k * k * 90.0) * fade;
			n += (d / max(dist, 0.0001)) * w;
		}
	}
	return n;
}

void fragment() {
	vec2 p = wpos.xz;
	float r = length(p);
	float n2 = texture(noise_tex, p * 0.11).r;
	float n3 = texture(noise_tex, p * 0.6).r;

	// --- Regiones ---
	float plaza = 1.0 - smoothstep(plaza_radius - 0.05, plaza_radius + 0.05, r);
	float walk = step(abs(p.x), 7.0) * step(-41.0, p.y) * step(p.y, 32.0);
	plaza = max(plaza, walk);
	float road = (1.0 - smoothstep(5.6, 6.0, abs(p.y - road_z))) * (1.0 - plaza);

	// --- Adoquines de la plaza ---
	vec2 tuv = p / 1.2;
	vec2 tid = floor(tuv);
	vec2 tf = fract(tuv);
	float edge_d = min(min(tf.x, 1.0 - tf.x), min(tf.y, 1.0 - tf.y));
	float grout = 1.0 - smoothstep(0.0, 0.045, edge_d);
	float th = hash12(tid);
	vec3 tile_col = mix(vec3(0.34, 0.33, 0.31), vec3(0.46, 0.44, 0.40), th) * (0.8 + 0.4 * n3);
	float ring_outer = step(plaza_radius - 1.4, r) * step(r, plaza_radius);
	float ring_mid = step(5.4, r) * step(r, 6.4);
	float ring_in = step(1.1, r) * step(r, 1.5);
	float rings = max(max(ring_outer, ring_mid), ring_in);
	tile_col = mix(tile_col, vec3(0.20, 0.19, 0.20) * (0.8 + 0.4 * n3), rings);
	tile_col = mix(tile_col, vec3(0.10, 0.10, 0.10), grout * 0.85);
	float missing = step(th, 0.05) * (1.0 - rings);
	tile_col = mix(tile_col, vec3(0.11, 0.09, 0.07) * (0.7 + 0.6 * n3), missing);

	// --- Asfalto con líneas pintadas desgastadas ---
	vec3 asph = vec3(0.11, 0.11, 0.12) * (0.75 + 0.5 * n3) * (0.9 + 0.2 * n2);
	float dz = abs(p.y - road_z);
	float center_line = (1.0 - smoothstep(0.08, 0.12, dz)) * step(0.5, fract(p.x / 6.0));
	float side_line = 1.0 - smoothstep(0.06, 0.1, abs(dz - 5.1));
	float paint_wear = smoothstep(0.3, 0.6, n2);
	asph = mix(asph, vec3(0.55, 0.45, 0.14) * 0.7, center_line * paint_wear);
	asph = mix(asph, vec3(0.6, 0.6, 0.58) * 0.6, side_line * paint_wear);

	// --- Pasto muerto / lodo ---
	vec3 grass = mix(vec3(0.10, 0.12, 0.06), vec3(0.15, 0.12, 0.08), smoothstep(0.35, 0.65, n2)) * (0.8 + 0.4 * n3);

	vec3 base = mix(grass, asph, road);
	base = mix(base, tile_col, plaza);
	vec4 dd = texture(det_d, p * det_scale);
	base *= mix(1.0, 0.35 + dd.r * 1.3, max(plaza, road));

	// --- Grietas y quemaduras de batalla ---
	float cr1 = 1.0 - smoothstep(0.0, 0.012, abs(texture(noise_tex, p * 0.05).r - 0.5));
	float cr2 = 1.0 - smoothstep(0.0, 0.01, abs(texture(noise_tex, p * 0.13 + vec2(5.0, 9.0)).r - 0.5));
	float crack = max(cr1, cr2 * 0.7) * max(plaza, road);
	base *= 1.0 - crack * 0.65;
	float scorch = smoothstep(0.66, 0.8, texture(noise_tex, p * 0.03 + vec2(17.3, 4.1)).r) * plaza;
	base *= 1.0 - scorch * 0.6 * (0.7 + 0.3 * n3);

	// --- Charcos ---
	float pm = texture(noise_tex, p * 0.045 + vec2(3.1, 7.7)).r + (n3 - 0.5) * 0.12;
	pm += missing * 0.25 + grout * plaza * 0.04 + (1.0 - plaza) * (1.0 - road) * 0.05;
	float thr = mix(0.85, 0.38, puddle_coverage);
	float puddle = smoothstep(thr, thr + 0.035, pm);
	float damp = smoothstep(thr - 0.12, thr, pm);

	vec2 rip = ripple_layer(p * 2.2, TIME * 1.3) * 0.6 + ripple_layer(p * 3.7 + 13.0, TIME * 1.7 + 0.3) * 0.4;
	rip *= rain_intensity;

	vec3 col = base * mix(1.0, 0.55, wetness);
	col = mix(col, base * 0.22 + vec3(0.008, 0.01, 0.013), puddle);

	float rough = mix(0.9, 0.45, wetness);
	rough = mix(rough, 0.95, grout * plaza * 0.5);
	rough = mix(rough, 0.25, damp * 0.6);
	rough = mix(rough, 0.03, puddle);

	vec2 bump = vec2(n3 - 0.5) * 0.18 * (1.0 - puddle) + rip * 0.32 * puddle;
	vec3 nw = vec3(-bump.x, 1.0, -bump.y);
	float seco = 1.0 - puddle;
	nw += piso_n(det_n, p, det_scale, det_strength * max(plaza, road) * seco);
	nw += bisel(tf, edge_d, 0.12, 0.55) * plaza * (1.0 - missing) * seco;
	nw = normalize(nw);
	rough = mix(rough, rough * (0.6 + dd.g * 0.6), seco);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
