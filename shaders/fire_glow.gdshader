shader_type canvas_item;
render_mode blend_add, unshaded;
// 불빛 번짐 (P15-FX, 실시간). 타는 칸 둘레의 바닥·벽에 주황빛이 일렁인다.
// floor_layer의 자식 노드(FireGlow)가 칸마다 사각형을 그리고 (UV 0~1, 정점 색 a = 세기), 이 셰이더가 둥근 번짐과 깜빡임을 만든다.
// 덧칠(가산)이라 깊이 순서와 상관없이 자연스럽고, 픽셀마다 계산이 가벼워 사무용 PC에서도 쓴다.

uniform vec3 glow_color : source_color = vec3(1.0, 0.45, 0.12);

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 d = UV - vec2(0.5);
	// 아이소 바닥에 맞춘 납작한 타원
	float r = length(d * vec2(1.0, 1.45)) * 2.0;
	float fall = pow(clamp(1.0 - r, 0.0, 1.0), 1.8);
	// 칸마다 다른 깜빡임 (정점 색 r·g에 칸 번호를 실어 보낸다)
	float id = COLOR.r * 97.0 + COLOR.g * 13.0;
	float flick = 0.72 + 0.18 * sin(TIME * 9.0 + id * 6.1) + 0.1 * sin(TIME * 23.0 + id * 2.3) * hash(id);
	COLOR = vec4(glow_color * fall * flick * COLOR.a, 1.0);
}
