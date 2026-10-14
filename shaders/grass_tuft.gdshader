// Matas de pasto (MultiMesh): hojas que se mecen con el viento, más secas en
// las puntas y con variación de color por zona.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.04, 0.06, 0.025);
uniform vec3 tip_color : source_color = vec3(0.24, 0.29, 0.11);
uniform vec3 dry_color : source_color = vec3(0.34, 0.29, 0.14);
uniform float wind = 0.12;

varying float h;
varying float variation;

void vertex() {
	h = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	variation = fract(sin(dot(floor(wp.xz * 0.35), vec2(12.9898, 78.233))) * 43758.5453);
	float sway = sin(TIME * 1.6 + wp.x * 0.35 + wp.z * 0.2) + 0.4 * sin(TIME * 3.1 + wp.x * 1.3);
	VERTEX.x += sway * wind * h * h;
	VERTEX.z += sway * wind * 0.4 * h * h;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec3 tip = mix(tip_color, dry_color, variation * 0.85);
	ALBEDO = mix(base_color, tip, h);
	ROUGHNESS = 0.65;
	SPECULAR = 0.25;
}
