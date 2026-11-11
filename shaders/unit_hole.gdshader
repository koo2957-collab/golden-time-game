shader_type canvas_item;
// 비켜 놓은 위층이 아래층 대원·요구조자를 가릴 때, 그 둘레만 위층을 반투명하게 (2026-11-12 사용자 결정).
// holes: xy = 세계(캔버스) 좌표, z = 반지름. 반지름의 60% 안쪽은 min_alpha, 바깥으로 갈수록 원래대로.

uniform vec4 holes[16];
uniform int count = 0;
uniform float min_alpha = 0.3;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Godot 4: fragment의 COLOR는 이미 그림 색 × 꼭짓점 색이다 (다시 곱하지 않는다)
	vec4 c = COLOR;
	float f = 1.0;
	for (int i = 0; i < 16; i++) {
		if (i >= count) {
			break;
		}
		float d = distance(world_pos, holes[i].xy);
		f = min(f, mix(min_alpha, 1.0, smoothstep(holes[i].z * 0.6, holes[i].z, d)));
	}
	COLOR = vec4(c.rgb, c.a * f);
}
