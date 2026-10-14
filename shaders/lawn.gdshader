// Césped de jardines y canchas: verde apagado y húmedo, franjas de podado,
// calvas de tierra y charcos. En coordenadas de mundo.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.11, 0.15, 0.06);
uniform vec3 grass_b : source_color = vec3(0.22, 0.23, 0.1);
uniform vec3 dirt_color : source_color = vec3(0.11, 0.085, 0.055);
uniform float stripes : hint_range(0.0, 1.0) = 0.35;
uniform float stripe_width = 4.0;
uniform float bald : hint_range(0.0, 1.0) = 0.3;
uniform float wetness : hint_range(0.0, 1.0) = 0.6;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = texture(noise_tex, p * 0.05).r;
	float n2 = texture(noise_tex, p * 0.4).r;
	float n3 = texture(noise_tex, p * 2.3).r;
	vec3 col = mix(grass_a, grass_b, smoothstep(0.3, 0.7, n1)) * (0.75 + 0.5 * n2) * (0.85 + 0.3 * n3);
	float st = step(0.5, fract(p.x / (2.0 * stripe_width)));
	col *= 1.0 + (st - 0.5) * 0.22 * stripes;
	float b = smoothstep(0.66 - bald * 0.2, 0.76 - bald * 0.2, texture(noise_tex, p * 0.09 + vec2(7.0, 3.0)).r);
	col = mix(col, dirt_color * (0.7 + 0.6 * n3), b);
	float puddle = smoothstep(0.78, 0.82, texture(noise_tex, p * 0.045 + vec2(3.1, 7.7)).r) * wetness;
	col *= 1.0 - 0.6 * puddle;
	vec2 bump = vec2(n3 - 0.5, n2 - 0.5) * 0.35 * (1.0 - puddle);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.08, puddle);
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-bump.x, 1.0, -bump.y)), 0.0)).xyz);
}
