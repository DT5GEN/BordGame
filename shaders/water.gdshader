shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 deep : source_color = vec4(0.07, 0.26, 0.46, 1.0);
uniform vec4 shallow : source_color = vec4(0.18, 0.48, 0.66, 1.0);
uniform float darkness = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 1.3 + wpos.x * 0.9) * 0.025 + cos(TIME * 1.0 + wpos.z * 0.8) * 0.025;
}

void fragment() {
	float w = sin(wpos.x * 2.1 + TIME * 1.4) * sin(wpos.z * 2.4 - TIME * 1.1);
	float w2 = sin(wpos.x * 5.3 - TIME * 2.0 + wpos.z * 3.1);
	vec3 c = mix(deep.rgb, shallow.rgb, 0.45 + 0.35 * w);
	float sparkle = smoothstep(0.86, 1.0, w * 0.6 + w2 * 0.4);
	ALBEDO = c * (1.0 - darkness * 0.6);
	ROUGHNESS = 0.22;
	SPECULAR = 0.45;
	EMISSION = vec3(sparkle) * 0.12 * (1.0 - darkness);
}
