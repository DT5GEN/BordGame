shader_type spatial;
render_mode specular_disabled;

uniform float wind = 0.3;
uniform float dim = 1.0;
varying vec3 col;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y + 0.3, 0.0);
	VERTEX.x += sin(TIME * 1.7 + wp.x * 0.7 + wp.z * 0.5) * wind * 0.12 * h;
	VERTEX.z += cos(TIME * 1.3 + wp.z * 0.6 + wp.x * 0.3) * wind * 0.08 * h;
	col = COLOR.rgb;
}

void fragment() {
	ALBEDO = col * dim;
	ROUGHNESS = 1.0;
}
