shader_type canvas_item;

uniform vec4 base : source_color = vec4(0.95, 0.87, 0.69, 1.0);
uniform vec4 edge : source_color = vec4(0.50, 0.32, 0.15, 1.0);
uniform float light = 1.0;
uniform vec2 candle = vec2(-0.08, 0.95);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 uv = UV;
	float n = fbm(uv * vec2(7.0, 10.0));
	float n2 = fbm(uv * vec2(60.0, 45.0));
	vec2 d = min(uv, 1.0 - uv);
	float e = min(d.x * 1.2, d.y * 3.0);
	float ragged = e + (fbm(uv * 25.0) - 0.5) * 0.035;
	float alpha = smoothstep(0.0, 0.01, ragged);
	float burn = 1.0 - smoothstep(0.0, 0.10, ragged);
	vec3 c = base.rgb * (0.86 + 0.22 * n) - vec3(0.05) * n2;
	float stain = smoothstep(0.62, 0.75, fbm(uv * 4.0 + 3.7));
	c = mix(c, c * vec3(0.85, 0.75, 0.6), stain * 0.5);
	c = mix(c, edge.rgb, burn * 0.9);
	float l = 1.0 - clamp(distance(uv * vec2(1.4, 1.0), candle * vec2(1.4, 1.0)) * 0.55, 0.0, 1.0);
	c *= mix(0.62, 1.12, l) * light;
	c += vec3(0.10, 0.05, 0.0) * l * light;
	COLOR = vec4(c, alpha * COLOR.a);
}
