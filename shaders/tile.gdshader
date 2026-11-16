shader_type spatial;
render_mode specular_disabled;
// Клетка поля: мягкий шов по краю, лёгкие пятна травы, земляные бока.

varying vec3 lp;
varying vec3 ln;
varying vec3 wp;
varying vec3 col;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 c = COLOR.rgb;
	vec3 lin = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	col = mix(c, lin, 0.4);
}

void fragment() {
	vec3 c = col;
	if (ln.y > 0.5) {
		float e = max(abs(lp.x), abs(lp.z));
		c *= 1.0 - smoothstep(0.40, 0.5, e) * 0.15;
		c *= 1.0 + smoothstep(0.34, 0.0, e) * 0.035;
		float n = sin(wp.x * 3.1 + sin(wp.z * 2.3) * 1.7) * sin(wp.z * 2.7 + sin(wp.x * 1.9) * 1.3);
		c *= 1.0 + n * 0.035;
	} else {
		// бок клетки: сверху полоска цвета клетки, ниже — земля, к низу темнее
		float h = lp.y + 0.5;
		vec3 earth = mix(vec3(0.20, 0.13, 0.08), vec3(0.33, 0.22, 0.13), h);
		float top = smoothstep(0.90, 0.97, h);
		c = mix(mix(earth, c, 0.25), c * 0.82, top);
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = smoothstep(0.0, 0.35, ndl);
	float fill = LIGHT_IS_DIRECTIONAL ? 0.28 : 0.0;
	DIFFUSE_LIGHT += (fill + (1.0 - fill) * band) * (LIGHT_IS_DIRECTIONAL ? 0.86 : 0.4) * ATTENUATION * LIGHT_COLOR / PI;
}
