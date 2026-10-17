// LEDs de servidores, balizas y pantallas: emisivo, sin sombreado, con
// parpadeo pseudoaleatorio por instancia (usa el color de instancia del MultiMesh).
shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0);
uniform float energy = 3.0;
// 0 = siempre encendido, 1 = parpadeo completo.
uniform float blink : hint_range(0.0, 1.0) = 0.85;
uniform float rate = 3.0;

varying vec3 col;
varying float seed;

void vertex() {
	col = COLOR.rgb;
	seed = float(INSTANCE_ID) + MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 0.3;
}

void fragment() {
	float speed = rate * (0.5 + fract(seed * 0.618));
	float step_t = floor(TIME * speed + seed);
	float on = step(0.35, fract(sin(step_t * 12.9898 + seed * 78.233) * 43758.5453));
	ALBEDO = col * tint * energy * mix(1.0, mix(0.08, 1.0, on), blink);
}
