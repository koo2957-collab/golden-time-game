shader_type canvas_item;
// 비켜 놓은 위층이 아래층 대원·요구조자를 가릴 때, 그 둘레만 위층을 반투명하게 (2026-11-12 사용자 결정).
// holes: xy = 세계(캔버스) 좌표, z = 반지름. 반지름의 60% 안쪽은 min_alpha, 바깥으로 갈수록 원래대로.
// w = 0: 모든 그림을 옅게 (위층 구멍)
// w > 0: 벽만 옅게 (F04 3단계, 2026-11-12) — 대상 깊이(칸 x + y) + 1. 벽 조각은 UV.x = 1000 + 벽 깊이로 표시되어 있고,
//        대상보다 앞(깊이가 큰 쪽)에 선 벽만 wall_min_alpha 까지 옅어진다

uniform vec4 holes[16];
uniform int count = 0;
uniform float min_alpha = 0.3;
uniform float wall_min_alpha = 0.15;
// 짝 층 흑백 정도 (0 = 원래 색, 1 = 흑백)
uniform float gray = 0.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Godot 4: fragment의 COLOR는 이미 그림 색 × 꼭짓점 색이다 (다시 곱하지 않는다)
	vec4 c = COLOR;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(lum), gray);
	bool is_wall = UV.x > 500.0;
	float wall_depth = UV.x - 1000.0;
	float f = 1.0;
	for (int i = 0; i < 16; i++) {
		if (i >= count) {
			break;
		}
		float w = holes[i].w;
		float lo = min_alpha;
		if (w > 0.5) {
			// 벽만: 대상보다 앞에 선 벽
			if (!is_wall || wall_depth <= w - 1.0 + 0.25) {
				continue;
			}
			lo = wall_min_alpha;
		}
		float d = distance(world_pos, holes[i].xy);
		f = min(f, mix(lo, 1.0, smoothstep(holes[i].z * 0.6, holes[i].z, d)));
	}
	COLOR = vec4(c.rgb, c.a * f);
}
