shader_type spatial;
render_mode specular_disabled;
// Мультяшный материал: мягкая ступенька света, контровой свет по краю.

uniform vec4 albedo : source_color = vec4(1.0);
uniform float rim = 0.16;
uniform float flash = 0.0;

void fragment() {
	ALBEDO = mix(albedo.rgb, vec3(1.0), flash);
	ROUGHNESS = 1.0;
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	EMISSION = mix(albedo.rgb, vec3(1.0), 0.35) * f * rim + vec3(flash * 0.6);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(-0.06, 0.16, ndl);
	// у солнца теневая сторона не проваливается в серое: часть света остаётся как тёплый «заполняющий»
	float fill = LIGHT_IS_DIRECTIONAL ? 0.5 : 0.0;
	float k = fill + (1.0 - fill) * (0.84 * band + 0.16 * smoothstep(0.5, 0.7, ndl));
	vec3 tint = mix(vec3(1.0, 0.82, 0.8), vec3(1.0), band);
	DIFFUSE_LIGHT += k * (LIGHT_IS_DIRECTIONAL ? 0.8 : 0.42) * tint * ATTENUATION * LIGHT_COLOR / PI;
}
