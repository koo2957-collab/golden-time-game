shader_type canvas_item;
// 연기층 질감 (P15-FX). tools/bake_fx.gd가 가로·세로로 이음새 없이 반복되는 연기 노이즈를 구워 art/fx/smoke_noise.png로 저장한다.
// 게임은 이 그림을 연기층 평면에 반복해 입히고 시간에 따라 흘려 연기가 굽이치게 한다 (floor_layer._draw_smoke).

uniform float period = 8.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p.x + p.y * 0.137 + seed * 13.0) * 43758.5453);
}

// 가로·세로 모두 per마다 반복
float vnoise(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(mod(i, per));
	float b = hash(mod(i + vec2(1.0, 0.0), per));
	float c = hash(mod(i + vec2(0.0, 1.0), per));
	float d = hash(mod(i + vec2(1.0, 1.0), per));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.55;
	float per = period;
	for (int k = 0; k < 6; k++) {
		v += amp * vnoise(p, per);
		p *= 2.0;
		per *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * period;
	// 노이즈를 노이즈로 비틀어(도메인 왜곡) 연기 결을 만든다
	vec2 w = vec2(fbm(p + vec2(1.7, 9.2)), fbm(p + vec2(8.3, 2.8)));
	float n = fbm(p + w * 2.0);
	float v = smoothstep(0.25, 0.85, n);
	// 밝기 = 연기 농도 (게임에서 연기 색·투명도를 곱한다)
	COLOR = vec4(vec3(v), 1.0);
}
