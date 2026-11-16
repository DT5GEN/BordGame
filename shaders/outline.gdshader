shader_type spatial;
render_mode unshaded, cull_front;
// Обводка «вывернутой оболочкой»: толщина примерно постоянна на экране.

uniform vec4 color : source_color = vec4(0.1, 0.08, 0.1, 1.0);
uniform float box = 0.0;
uniform float width = 1.0;

void vertex() {
	vec3 dir = mix(NORMAL, normalize(VERTEX + vec3(0.00001)), box);
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(dir, 0.0)).xyz);
	float w = clamp(-vp.z * 0.0028, 0.005, 0.045) * width;
	vp.xyz += n * w;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = color.rgb;
}
