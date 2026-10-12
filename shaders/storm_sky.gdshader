// Cielo de tormenta: nubes densas en movimiento, tonalidad oscura y fría,
// con soporte para destellos de relámpago (uniform `lightning`).
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.09, 0.10, 0.12);
uniform vec3 horizon_color : source_color = vec3(0.27, 0.29, 0.32);
uniform vec3 ground_color : source_color = vec3(0.06, 0.06, 0.07);
uniform vec3 cloud_dark : source_color = vec3(0.06, 0.065, 0.075);
uniform vec3 cloud_light : source_color = vec3(0.30, 0.32, 0.35);
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform float cloud_speed = 0.004;
uniform float lightning = 0.0;
uniform vec2 lightning_dir = vec2(0.6, -0.4);

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, zenith_color, smoothstep(0.0, 0.6, h));
	if (h > -0.03) {
		vec2 uv = d.xz / max(h + 0.12, 0.05);
		float t = AT_CUBEMAP_PASS ? 0.0 : TIME * cloud_speed;
		float n = texture(cloud_tex, uv * 0.08 + vec2(t, t * 0.4)).r * 0.6
			+ texture(cloud_tex, uv * 0.21 - vec2(t * 1.7, t * 0.3)).r * 0.3
			+ texture(cloud_tex, uv * 0.55 + vec2(t * 2.5, 0.0)).r * 0.1;
		float dense = smoothstep(0.35, 0.7, n);
		vec3 cl = mix(cloud_light, cloud_dark, dense);
		float hf = smoothstep(-0.03, 0.18, h);
		col = mix(col, cl, hf * 0.92);
		float dirf = pow(max(dot(normalize(d.xz + vec2(0.0001)), normalize(lightning_dir)), 0.0), 3.0);
		col += vec3(0.65, 0.70, 0.85) * lightning * (0.2 + 0.8 * dirf) * hf * (0.4 + 0.6 * n);
	} else {
		col = mix(horizon_color, ground_color, smoothstep(0.0, -0.3, h));
	}
	COLOR = col;
}
