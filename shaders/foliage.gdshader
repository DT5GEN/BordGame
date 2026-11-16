shader_type spatial;
render_mode specular_disabled;
// Листва и трава: качается на ветру, снизу темнее, сверху светлее, мультяшный свет.

uniform float wind = 0.3;
uniform float dim = 1.0;
varying vec3 col;
varying float hgt;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y + 0.3, 0.0);
	VERTEX.x += sin(TIME * 1.7 + wp.x * 0.7 + wp.z * 0.5) * wind * 0.12 * h;
	VERTEX.z += cos(TIME * 1.3 + wp.z * 0.6 + wp.x * 0.3) * wind * 0.08 * h;
	vec3 c = COLOR.rgb;
	col = c;
	hgt = clamp(VERTEX.y / 0.6 + 0.5, 0.0, 1.0);
}

void fragment() {
	ALBEDO = col * dim * mix(0.74, 1.14, hgt);
	ROUGHNESS = 1.0;
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = col * dim * f * 0.10;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.1, 0.25, ndl);
	float fill = LIGHT_IS_DIRECTIONAL ? 0.42 : 0.0;
	DIFFUSE_LIGHT += (fill + (1.0 - fill) * band) * (LIGHT_IS_DIRECTIONAL ? 0.85 : 0.4) * ATTENUATION * LIGHT_COLOR / PI;
}
