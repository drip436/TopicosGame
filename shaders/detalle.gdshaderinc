// Detalle de superficie en coordenadas de mundo (triplanar) con las texturas de
// texturas/ (arte/texturas/gen_texturas.py):
//   *_n.png  normales (OpenGL)       *_d.png  R color (0.5 = igual), G rugosidad, B máscara
// Quita el aspecto de "plástico": poros, grietas, juntas de mortero, rayones...

// Pesos triplanares a partir de la normal de mundo.
vec3 tri_pesos(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

// Muestra *_d.png en las tres proyecciones (v hacia arriba en las paredes).
vec4 tri_d(sampler2D t, vec3 p, vec3 w, vec2 s) {
	vec4 x = texture(t, vec2(p.z, -p.y) * s);
	vec4 y = texture(t, p.xz * s);
	vec4 z = texture(t, vec2(p.x, -p.y) * s);
	return x * w.x + y * w.y + z * w.z;
}

// Normal de mundo perturbada por *_n.png (mezcla "whiteout").
vec3 tri_n(sampler2D t, vec3 p, vec3 n, vec3 w, vec2 s, float fuerza) {
	vec3 tx = texture(t, vec2(p.z, -p.y) * s).xyz * 2.0 - 1.0;
	vec3 ty = texture(t, p.xz * s).xyz * 2.0 - 1.0;
	vec3 tz = texture(t, vec2(p.x, -p.y) * s).xyz * 2.0 - 1.0;
	tx.xy *= fuerza;
	ty.xy *= fuerza;
	tz.xy *= fuerza;
	// El verde del mapa apunta a "arriba" de la imagen (v decreciente); en el piso eso es -z
	ty.y *= -1.0;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

// Piso: perturbación (en mundo) que se suma a la normal (0, 1, 0).
vec3 piso_n(sampler2D t, vec2 p, float s, float fuerza) {
	vec3 d = texture(t, p * s).xyz * 2.0 - 1.0;
	return vec3(d.x, 0.0, -d.y) * fuerza;
}

// Bisel de baldosa/adoquín: la orilla baja hacia la junta (tf = posición dentro de la pieza).
vec3 bisel(vec2 tf, float edge_d, float ancho, float fuerza) {
	vec2 e = tf - 0.5;
	vec2 dir = abs(e.x) > abs(e.y) ? vec2(sign(e.x), 0.0) : vec2(0.0, sign(e.y));
	float b = 1.0 - smoothstep(0.0, ancho, edge_d);
	return vec3(dir.x, 0.0, dir.y) * b * fuerza;
}
