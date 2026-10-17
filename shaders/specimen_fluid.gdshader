// Líquido de contención para las cápsulas del laboratorio: translúcido,
// brillante, con corrientes, burbujas y borde fresnel. Para un cilindro.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 fluid_color : source_color = vec3(0.25, 0.95, 0.45);
uniform float glow = 1.4;
uniform float opacity : hint_range(0.0, 1.0) = 0.5;

varying vec3 lpos;
varying vec3 origin;

void vertex() {
	lpos = VERTEX;
	origin = MODEL_MATRIX[3].xyz;
}

void fragment() {
	float ang = atan(lpos.z, lpos.x) / 6.2831853 + 0.5;
	vec2 base_uv = vec2(ang + origin.x * 0.13, lpos.y);
	float n = texture(noise_tex, vec2(base_uv.x * 1.5, base_uv.y * 0.6 - TIME * 0.05)).r;
	float b1 = texture(noise_tex, vec2(base_uv.x * 6.0, base_uv.y * 2.2 - TIME * 0.45)).r;
	float bubbles = smoothstep(0.74, 0.8, b1);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float bottom = 1.0 - smoothstep(-0.5, 0.0, lpos.y);

	vec3 c = fluid_color * (0.55 + 0.7 * n);
	ALBEDO = c * 0.25;
	EMISSION = c * glow * (0.45 + 0.55 * n + bottom * 0.6) + vec3(0.7, 1.0, 0.8) * bubbles * 0.6;
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	ALPHA = clamp(opacity + fres * 0.4 + bubbles * 0.25, 0.0, 0.95);
}
