shader_type canvas_item;
// 화면 분위기 (2026-11-14 시안, 프로스트펑크 느낌): 전체를 차갑고 어둡게 가라앉히고, 따뜻한 색(불·경광등·방화복)만 살린다.
// 가장자리는 어둡게(비네트). 화면 전체를 한 번 읽어 색만 바꾼다 — 광원·그림자 계산 없음 (사무실 PC용)
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float desat = 0.5;
uniform vec3 tint = vec3(0.66, 0.76, 0.92);
uniform float dark = 0.7;
uniform float vignette = 0.6;
uniform float warm_boost = 1.12;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float warm = clamp((c.r - max(c.g * 0.82, c.b)) * 3.2, 0.0, 1.0);
	vec3 cold = mix(c, vec3(l), desat) * tint * dark;
	vec3 o = mix(cold, c * warm_boost, warm);
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.0, 0.9);
	float v = smoothstep(0.3, 0.95, length(d) * 1.5);
	o *= 1.0 - vignette * v;
	COLOR = vec4(o, 1.0);
}
