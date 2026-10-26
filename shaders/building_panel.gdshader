// Panel de fachada de edificio universitario: concreto manchado y mojado,
// ventanas con vidrio, vidrios rotos, hollín sobre ventanas quemadas y
// alguna luz interior parpadeante. Pensado para un BoxMesh de 4 x 3.6 x 0.3.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 wall_tint : source_color = vec3(0.52, 0.50, 0.47);
uniform vec3 band_tint : source_color = vec3(0.34, 0.32, 0.30);
uniform float wetness : hint_range(0.0, 1.0) = 0.75;
uniform float broken_ratio : hint_range(0.0, 1.0) = 0.55;
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.04;
// Relieve del muro (concreto o ladrillo) y color del mortero (canal B de det_d)
uniform sampler2D det_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D det_d : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 det_scale = vec2(0.5);
uniform float det_strength = 1.0;
uniform vec3 joint_color : source_color = vec3(0.42, 0.4, 0.37);
uniform float joint_mix = 0.0;

#include "res://shaders/detalle.gdshaderinc"

varying vec3 lpos;
varying vec3 lnrm;
varying vec3 wpos;
varying vec3 origin;
varying vec3 wnrm;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	origin = MODEL_MATRIX[3].xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 key = floor(origin * 3.0);
	float h1 = hash13(key + 0.5);
	float h2 = hash13(key + 17.3);
	float h3 = hash13(key + 41.7);

	vec2 wuv = vec2(wpos.x + wpos.z, wpos.y);
	float n = texture(noise_tex, wuv * 0.25).r;
	float nf = texture(noise_tex, wuv * 1.3).r;
	float streak = texture(noise_tex, vec2(wuv.x * 0.7, wuv.y * 0.04)).r;

	vec3 col = wall_tint * (0.7 + 0.55 * n) * (0.88 + 0.24 * nf);
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	bool concrete = true;

	if (abs(lnrm.z) > 0.5) {
		float xx = lpos.x;
		float yy = lpos.y;
		float wx = 1.5;
		float wy0 = -0.7;
		float wy1 = 1.25;
		float fr = 0.07;
		if (yy < -0.85) {
			col = band_tint * (0.7 + 0.55 * n);
		}
		bool inwin = abs(xx) < wx && yy > wy0 && yy < wy1;
		bool inframe = abs(xx) < wx + fr && yy > wy0 - fr && yy < wy1 + fr;
		if (inframe && !inwin) {
			col = vec3(0.05);
			rough = 0.45;
			metal = 0.6;
			concrete = false;
		}
		if (inwin) {
			concrete = false;
			if (abs(xx) < 0.035) {
				col = vec3(0.05);
				rough = 0.45;
				metal = 0.6;
			} else {
				bool broken = h1 < broken_ratio;
				float shard = texture(noise_tex, lpos.xy * 0.9 + vec2(h2 * 13.0, h3 * 7.0)).r;
				float edge = min(wx - abs(xx), min(yy - wy0, wy1 - yy));
				if (broken && !(shard > 0.58 && edge < 0.35)) {
					col = vec3(0.01);
					rough = 1.0;
				} else {
					col = vec3(0.02, 0.025, 0.03);
					rough = 0.05;
					if (h2 < lit_ratio) {
						float fl = 0.6 + 0.4 * sin(TIME * (7.0 + h3 * 20.0) + h3 * 40.0);
						fl *= step(0.15, fract(TIME * 0.37 + h3));
						emit = vec3(1.0, 0.55, 0.25) * 1.6 * fl;
					}
				}
			}
		}
		// Hollín sobre ventanas rotas (incendio)
		if (h1 < broken_ratio && yy > wy1 && abs(xx) < wx + 0.3) {
			float s = (1.0 - smoothstep(wy1, wy1 + 0.9, yy)) * (1.0 - smoothstep(wx - 0.4, wx + 0.3, abs(xx)));
			col *= 1.0 - 0.75 * s * (0.6 + 0.4 * nf);
		}
	}

	vec3 nn = normalize(wnrm);
	vec3 tw = tri_pesos(nn);
	vec3 nw = nn;
	if (concrete) {
		vec4 dd = tri_d(det_d, wpos, tw, det_scale);
		col *= 0.55 + dd.r * 0.9;
		col = mix(col, joint_color * (0.75 + 0.5 * n), clamp(dd.b * 1.4, 0.0, 1.0) * joint_mix);
		rough = clamp(rough * (0.55 + dd.g * 0.7), 0.05, 1.0);
		nw = tri_n(det_n, wpos, nn, tw, det_scale, det_strength);
		col *= mix(1.0, 0.68, smoothstep(0.5, 0.75, streak));
		col *= mix(0.6, 1.0, smoothstep(0.0, 3.0, wpos.y));
		float wet = wetness * (0.55 + 0.45 * smoothstep(0.3, 0.7, streak));
		col *= mix(1.0, 0.62, wet);
		rough = mix(rough, 0.35, wet);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
