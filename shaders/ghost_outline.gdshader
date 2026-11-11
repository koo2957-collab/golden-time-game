shader_type canvas_item;
// 단면 보기의 다른 층 사람 (2026-11-11 사용자 결정, F01): 그림의 바깥 테두리만 그리는 색(대원 노랑·요구조자 빨강)으로.
// 그린 색(COLOR = 그릴 때 준 modulate)의 알파가 진하기. 안쪽은 아주 옅게 채워 형체가 읽히게 한다.

uniform float thickness = 3.0;
uniform float fill = 0.12;

// 그릴 때 준 색(modulate)만 — fragment의 COLOR는 그림 색이 곱해져 있다
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	vec2 px = TEXTURE_PIXEL_SIZE * thickness;
	float m = 0.0;
	m = max(m, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	m = max(m, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	m = max(m, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	m = max(m, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	m = max(m, texture(TEXTURE, UV + px).a);
	m = max(m, texture(TEXTURE, UV - px).a);
	m = max(m, texture(TEXTURE, UV + vec2(px.x, -px.y)).a);
	m = max(m, texture(TEXTURE, UV + vec2(-px.x, px.y)).a);
	// 바깥 테두리를 진하게 (두 번 눌러 또렷하게)
	float edge = clamp((m - a) * 2.0, 0.0, 1.0);
	COLOR = vec4(tint.rgb, clamp(edge + a * fill, 0.0, 1.0) * tint.a);
}
