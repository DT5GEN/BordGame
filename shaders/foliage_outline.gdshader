shader_type spatial;
render_mode unshaded, cull_front;
// Обводка листвы: качается так же, как сама листва.

uniform float wind = 0.3;
uniform float dim = 1.0;
varying vec3 col;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y + 0.3, 0.0);
	VERTEX.x += sin(TIME * 1.7 + wp.x * 0.7 + wp.z * 0.5) * wind * 0.12 * h;
	VERTEX.z += cos(TIME * 1.3 + wp.z * 0.6 + wp.x * 0.3) * wind * 0.08 * h;
	col = COLOR.rgb * 0.3;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vp.xyz += n * clamp(-vp.z * 0.0026, 0.005, 0.04);
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = col * dim;
}
