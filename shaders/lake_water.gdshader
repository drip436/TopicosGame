// Agua del lago y de las fuentes: oscura y reflejante, con oleaje suave,
// ondas de lluvia y una capa de lama en las orillas (elipse center/radii).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.015, 0.03, 0.035);
uniform vec3 shallow_color : source_color = vec3(0.04, 0.07, 0.065);
uniform vec3 scum_color : source_color = vec3(0.07, 0.08, 0.045);
uniform vec2 center = vec2(0.0);
uniform vec2 radii = vec2(1000.0);
uniform float rain_intensity : hint_range(0.0, 2.0) = 1.0;

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
	float n1 = texture(noise_tex, p * 0.02 + vec2(TIME * 0.004, TIME * 0.003)).r;
	float n2 = texture(noise_tex, p * 0.05 - vec2(TIME * 0.006, -TIME * 0.002)).r;
	vec2 waves = vec2(n1 - 0.5, n2 - 0.5) * 0.3;
	vec2 rip = ripple_layer(p * 1.6, TIME * 1.2) * rain_intensity * 0.45;
	vec3 nw = normalize(vec3(-(waves.x + rip.x), 1.0, -(waves.y + rip.y)));

	float e = length((p - center) / radii);
	float scum = smoothstep(0.82, 1.0, e) * smoothstep(0.5, 0.68, texture(noise_tex, p * 0.12).r);
	vec3 col = mix(deep_color, shallow_color, smoothstep(0.55, 1.0, e));
	col = mix(col, scum_color, scum * 0.85);

	ALBEDO = col;
	ROUGHNESS = mix(0.03, 0.7, scum);
	SPECULAR = 0.8;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
