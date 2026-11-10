shader_type canvas_item;
// 불꽃 (P15-FX). tools/bake_fx.gd가 이 셰이더로 불꽃 애니메이션 프레임을 구워 art/fx/flame.png로 저장한다.
// 게임은 구운 그림만 쓴다 (사무용 PC, 벽·대원과 깊이 순서 유지). 실시간으로 쓰지 않는다.
// phase 0~1 한 바퀴가 끊김 없이 이어지도록, 세로로 반복되는 노이즈를 위로 흘린다.

uniform float phase = 0.0;
uniform float seed = 0.0;
// 세로 반복 주기 (노이즈 격자 칸)
uniform float period = 6.0;

float hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p.x + p.y * 0.137 + seed * 17.0) * 43758.5453);
}

// 세로(y)로 period마다 반복되는 값 노이즈
float vnoise(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(vec2(i.x, mod(i.y, per)));
	float b = hash(vec2(i.x + 1.0, mod(i.y, per)));
	float c = hash(vec2(i.x, mod(i.y + 1.0, per)));
	float d = hash(vec2(i.x + 1.0, mod(i.y + 1.0, per)));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	float per = period;
	for (int k = 0; k < 5; k++) {
		v += amp * vnoise(p, per);
		p *= 2.0;
		per *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	// uv: x 0~1 가로, y 0(위)~1(아래 = 불의 뿌리)
	vec2 uv = UV;
	float h = 1.0 - uv.y;               // 바닥 0 → 위 1
	float x = (uv.x - 0.5) * 2.0;       // -1 ~ 1
	// 위로 흘러가는 노이즈 (한 바퀴 = 주기만큼)
	vec2 q = vec2(uv.x * 3.0, uv.y * period * 0.5 + phase * period);
	float n = fbm(q);
	float n2 = fbm(q * 1.7 + vec2(3.1, 0.0));
	// 불꽃 모양: 아래가 넓고 위로 갈수록 좁아지며 노이즈로 혀처럼 갈라진다
	float sway = (n2 - 0.5) * 0.55 * h;
	float width = mix(0.82, 0.04, pow(h, 0.6)) + (n - 0.5) * 0.85 * (0.3 + h);
	float body = smoothstep(width, width - 0.28, abs(x + sway));
	float top = smoothstep(1.0, 0.25, h + (n - 0.5) * 0.7);
	float bottom = smoothstep(0.0, 0.1, h);
	float a = clamp(body * top * bottom * (0.55 + n * 0.7), 0.0, 1.0);
	// 색: 뿌리 가운데만 밝은 노랑·흰색, 바깥·위는 주황 → 검붉은색
	float heat = clamp(a * (1.05 - h * 0.95) * (1.0 - abs(x + sway) * 0.7), 0.0, 1.0);
	vec3 col = mix(vec3(0.45, 0.04, 0.01), vec3(0.95, 0.30, 0.04), smoothstep(0.05, 0.35, heat));
	col = mix(col, vec3(1.0, 0.62, 0.12), smoothstep(0.35, 0.6, heat));
	col = mix(col, vec3(1.0, 0.88, 0.45), smoothstep(0.65, 0.85, heat));
	col = mix(col, vec3(1.0, 0.97, 0.85), smoothstep(0.9, 1.0, heat));
	COLOR = vec4(col, a * smoothstep(0.04, 0.3, a));
}
