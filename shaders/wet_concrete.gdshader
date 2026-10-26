// Concreto/piedra mojada en coordenadas de mundo (triplanar), para losas,
// columnas, escombros y utilería. Las caras superiores quedan más brillantes
// (agua acumulada) y la base más sucia.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.48, 0.46, 0.43);
uniform float wetness : hint_range(0.0, 1.0) = 0.75;
uniform float scale = 0.35;
uniform float moss : hint_range(0.0, 1.0) = 0.15;
// Relieve (texturas/*_n.png y *_d.png): concreto, yeso, ladrillo...
uniform sampler2D det_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D det_d : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 det_scale = vec2(0.5);
uniform float det_strength = 1.0;
// Color de las juntas/mortero (canal B de det_d); 0 = sin juntas
uniform vec3 joint_color : source_color = vec3(0.45, 0.43, 0.4);
uniform float joint_mix = 0.0;

#include "res://shaders/detalle.gdshaderinc"

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri(vec3 p, vec3 w, float s) {
	return texture(noise_tex, p.yz * s).r * w.x + texture(noise_tex, p.xz * s).r * w.y + texture(noise_tex, p.xy * s).r * w.z;
}

void fragment() {
	vec3 w = abs(wnrm);
	w /= (w.x + w.y + w.z);
	float n = tri(wpos, w, scale);
	float nf = tri(wpos, w, scale * 4.1);
	float streak = texture(noise_tex, vec2((wpos.x + wpos.z) * 0.9, wpos.y * 0.05)).r * (1.0 - w.y);

	vec3 nn = normalize(wnrm);
	vec3 tw = tri_pesos(nn);
	vec4 dd = tri_d(det_d, wpos, tw, det_scale);
	vec3 col = tint * (0.65 + 0.6 * n) * (0.85 + 0.3 * nf);
	col *= 0.55 + dd.r * 0.9;
	col = mix(col, joint_color * (0.7 + 0.6 * nf), clamp(dd.b * 1.5, 0.0, 1.0) * joint_mix);
	col *= mix(1.0, 0.7, smoothstep(0.45, 0.7, streak));
	col *= mix(0.55, 1.0, smoothstep(0.0, 2.0, wpos.y));
	float up = smoothstep(0.6, 0.95, wnrm.y);
	col = mix(col, col * vec3(0.55, 0.7, 0.45), moss * up * smoothstep(0.5, 0.7, n));

	float wet = wetness * mix(0.55, 1.0, up);
	col *= mix(1.0, 0.6, wet);
	float rough = mix(0.9, 0.3, wet);
	rough = mix(rough, 0.12, up * wetness * smoothstep(0.55, 0.7, nf));

	rough = clamp(rough * (0.55 + dd.g * 0.7), 0.04, 1.0);
	float plano = up * wetness * smoothstep(0.55, 0.7, nf);  // agua estancada: lisa

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(tri_n(det_n, wpos, nn, tw, det_scale, det_strength * (1.0 - plano)), 0.0)).xyz);
}
