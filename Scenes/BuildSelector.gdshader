shader_type canvas_item;

uniform float scanline_count : hint_range(0.0, 1000.0) = 500.0;
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.02;

void fragment() {
	vec2 uv = UV;
	
	// Efecto Glitch leve basado en el tiempo
	float time = TIME * 8.0;
	float glitch = step(0.97, sin(time + uv.y * 15.0)) * glitch_intensity;
	uv.x += glitch;

	// Color base de la terminal (Ciberpunk: azul oscuro / verdoso muy sutil)
	vec4 base_color = vec4(0.01, 0.03, 0.05, 0.95);

	// Líneas de escaneo (Scanlines)
	float scanline = sin(uv.y * scanline_count * 3.14159 * 2.0);
	base_color.rgb -= vec3(clamp(scanline * 0.04, 0.0, 1.0));

	// Viñeta opcional para oscurecer los bordes
	vec2 center = uv - 0.5;
	float vignette = 1.0 - dot(center, center) * 1.5;
	base_color.rgb *= clamp(vignette, 0.4, 1.0);

	COLOR = base_color;
}