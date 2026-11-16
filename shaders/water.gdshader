shader_type spatial;
render_mode specular_schlick_ggx;
// Мультяшная вода: две полосы цвета, бегущие блики-сеточки, светлее к горизонту.

uniform vec4 deep : source_color = vec4(0.07, 0.26, 0.46, 1.0);
uniform vec4 shallow : source_color = vec4(0.18, 0.48, 0.66, 1.0);
uniform float darkness = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 1.3 + wpos.x * 0.9) * 0.025 + cos(TIME * 1.0 + wpos.z * 0.8) * 0.025;
}

void fragment() {
	float w = sin(wpos.x * 1.3 + TIME * 0.9 + sin(wpos.z * 0.8) * 1.2) * sin(wpos.z * 1.5 - TIME * 0.7 + sin(wpos.x * 0.6) * 1.1);
	float band = smoothstep(-0.15, 0.15, w);
	vec3 c = mix(deep.rgb, shallow.rgb, 0.3 + 0.5 * band);
	// сеточка бликов: две бегущие волны, блик там, где они пересекаются
	float a = abs(sin(wpos.x * 1.5 + wpos.z * 0.7 + TIME * 1.1 + sin(wpos.z * 1.7 + TIME * 0.5)));
	float b = abs(sin(wpos.z * 1.6 - wpos.x * 0.6 - TIME * 0.9 + sin(wpos.x * 1.5 - TIME * 0.4)));
	float foam = smoothstep(0.09, 0.0, min(a, b)) * 0.4;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	c = mix(c, vec3(0.85, 0.95, 1.0), foam * (1.0 - darkness * 0.7));
	c = mix(c, shallow.rgb * 1.25 + vec3(0.1), fres * 0.55);
	ALBEDO = c * (1.0 - darkness * 0.6);
	ROUGHNESS = 0.3;
	SPECULAR = 0.35;
	EMISSION = vec3(foam) * 0.08 * (1.0 - darkness);
}
