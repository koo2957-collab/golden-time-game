class_name BoardSymbols
extends RefCounted
## 전술상황판(화이트보드) 기호 그리기 (2026-11-14). 평면도와 범례가 같은 그림을 쓴다.
## 모두 선·도형으로만 그린다 (그림 파일 없음 — 사무용 PC). 색·크기는 BoardStyle(data/ui/board_style.json).
## r = 기호 기준 크기(반지름쯤), a = 불투명도 (오래된 보고는 흐리게)


## 화점: 빨간 불꽃
static func flame(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var outer := PackedVector2Array()
	for v: Vector2 in [Vector2(0.0, -1.35), Vector2(0.5, -0.55), Vector2(0.85, 0.2), Vector2(0.6, 0.8), Vector2(0.0, 1.0),
			Vector2(-0.6, 0.8), Vector2(-0.85, 0.2), Vector2(-0.45, -0.3), Vector2(-0.3, -0.75)]:
		outer.append(p + v * r)
	ci.draw_colored_polygon(outer, col)
	var inner := PackedVector2Array()
	for v: Vector2 in [Vector2(0.0, -0.25), Vector2(0.35, 0.4), Vector2(0.0, 0.8), Vector2(-0.35, 0.4)]:
		inner.append(p + v * r)
	ci.draw_colored_polygon(inner, Color(1, 1, 1, 0.7 * col.a))


## 빗금 (화점 구획): 왼쪽 아래 → 오른쪽 위 사선을 간격마다
static func hatch(ci: CanvasItem, rect: Rect2, step: float, col: Color, width := 1.0) -> void:
	var k := step
	while k < rect.size.x + rect.size.y:
		var a := rect.position + Vector2(minf(k, rect.size.x), maxf(0.0, k - rect.size.x))
		var b := rect.position + Vector2(maxf(0.0, k - rect.size.y), minf(k, rect.size.y))
		ci.draw_line(a, b, col, width)
		k += step


## 연기: 회색 물결선 세 줄
static func smoke(ci: CanvasItem, rect: Rect2, col: Color, width := 1.5) -> void:
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return
	for k in 3:
		var y := rect.position.y + rect.size.y * float(k + 1) / 4.0
		wave(ci, Vector2(rect.position.x + 3.0, y), rect.size.x - 6.0, col, width, float(k))


## 물결선 한 줄
static func wave(ci: CanvasItem, from: Vector2, length: float, col: Color, width := 1.5, phase := 0.0) -> void:
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= length:
		pts.append(from + Vector2(x, sin(x / 4.5 + phase) * 2.5))
		x += 3.0
	if pts.size() >= 2:
		ci.draw_polyline(pts, col, width)


## 구조대상자: 사람 표시 (머리 + 몸)
static func person(ci: CanvasItem, p: Vector2, r: float, col: Color, ink: Color) -> void:
	var body := PackedVector2Array([p + Vector2(-0.6, -0.15) * r, p + Vector2(0.6, -0.15) * r, p + Vector2(0.42, 1.0) * r, p + Vector2(-0.42, 1.0) * r])
	ci.draw_colored_polygon(body, col)
	body.append(body[0])
	ci.draw_polyline(body, ink, 1.0)
	var head := p + Vector2(0.0, -0.7) * r
	ci.draw_circle(head, 0.42 * r, col)
	ci.draw_arc(head, 0.42 * r, 0.0, TAU, 16, ink, 1.0)


## 구조 완료: 체크
static func check(ci: CanvasItem, p: Vector2, r: float, col: Color, width := 3.0) -> void:
	ci.draw_polyline(PackedVector2Array([p + Vector2(-0.75, 0.0) * r, p + Vector2(-0.2, 0.6) * r, p + Vector2(0.85, -0.65) * r]), col, width)


## 검색 지시: 방에 사선 한 줄 (/)
static func slash(ci: CanvasItem, rect: Rect2, col: Color, width := 2.0) -> void:
	var r := rect.grow(-3.0)
	ci.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), col, width)


## 검색 완료: 방에 ✕
static func cross(ci: CanvasItem, rect: Rect2, col: Color, width := 2.0) -> void:
	var r := rect.grow(-3.0)
	ci.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), col, width)
	ci.draw_line(r.position, r.end, col, width)


## 위험 징후: 노란 삼각형 + 느낌표
static func hazard(ci: CanvasItem, p: Vector2, r: float, fill: Color, ink: Color) -> void:
	var tri := PackedVector2Array([p + Vector2(0.0, -1.0) * r, p + Vector2(0.95, 0.75) * r, p + Vector2(-0.95, 0.75) * r])
	ci.draw_colored_polygon(tri, fill)
	tri.append(tri[0])
	ci.draw_polyline(tri, ink, 1.5)
	ci.draw_line(p + Vector2(0.0, -0.45) * r, p + Vector2(0.0, 0.2) * r, ink, 2.0)
	ci.draw_circle(p + Vector2(0.0, 0.48) * r, 1.3, ink)


## 소화전: 원 안에 H
static func hydrant(ci: CanvasItem, p: Vector2, r: float, col: Color, board: Color) -> void:
	ci.draw_circle(p, r, board)
	ci.draw_arc(p, r, 0.0, TAU, 24, col, 2.0)
	ci.draw_line(p + Vector2(-0.4, -0.5) * r, p + Vector2(-0.4, 0.5) * r, col, 2.0)
	ci.draw_line(p + Vector2(0.4, -0.5) * r, p + Vector2(0.4, 0.5) * r, col, 2.0)
	ci.draw_line(p + Vector2(-0.4, 0.0) * r, p + Vector2(0.4, 0.0) * r, col, 2.0)


## 진입구: 건물 쪽을 가리키는 화살표. tip = 화살 끝, dir = 가리키는 방향 (단위 벡터)
static func arrow(ci: CanvasItem, tip: Vector2, dir: Vector2, r: float, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	ci.draw_line(tip - dir * r * 2.3, tip - dir * r * 0.9, col, 3.0)
	ci.draw_colored_polygon(PackedVector2Array([tip, tip - dir * r + side * r * 0.7, tip - dir * r - side * r * 0.7]), col)


## 깃발 (지휘소·직전대기): p = 깃대 밑
static func flag(ci: CanvasItem, p: Vector2, h: float, col: Color, ink: Color) -> void:
	ci.draw_line(p, p - Vector2(0, h), ink, 2.0)
	ci.draw_colored_polygon(PackedVector2Array([p - Vector2(0, h), p + Vector2(h * 0.65, -h * 0.78), p - Vector2(0, h * 0.56)]), col)


## 십자 표시 (환자 집결지·분류소)
static func cross_mark(ci: CanvasItem, p: Vector2, r: float, col: Color, ink: Color, board: Color) -> void:
	var box := Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
	ci.draw_rect(box, board)
	ci.draw_rect(box, ink, false, 1.0)
	ci.draw_rect(Rect2(p - Vector2(r * 0.25, r * 0.75), Vector2(r * 0.5, r * 1.5)), col)
	ci.draw_rect(Rect2(p - Vector2(r * 0.75, r * 0.25), Vector2(r * 1.5, r * 0.5)), col)


## 점선으로 이은 선 (수관 연장만 한 것 등)
static func dashed_polyline(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float, dash := 6.0) -> void:
	for i in pts.size() - 1:
		ci.draw_dashed_line(pts[i], pts[i + 1], col, width, dash)


## 점선 네모 (구역·추정 구조)
static func dashed_rect(ci: CanvasItem, rect: Rect2, col: Color, width := 2.0, dash := 8.0) -> void:
	var c := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for k in 4:
		ci.draw_dashed_line(c[k], c[(k + 1) % 4], col, width, dash)


## 자석 명패 크기 (글자 폭 + 헬멧 색 칩 자리)
static func magnet_size(text: String, font: Font, st: BoardStyle) -> Vector2:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, st.magnet_font).x
	return Vector2(ceilf(w + st.magnet_h_px * 1.25 + 4.0), st.magnet_h_px)


## 자석 명패: 흰 바탕 + 먹 테두리 + 왼쪽 색 칩(헬멧 색·출동대 색) + 이름.
## square = 차량(네모), 아니면 조(둥근 끝). ring 색을 주면 바깥에 한 겹 더 (RIT)
static func magnet(ci: CanvasItem, rect: Rect2, text: String, chip: Color, font: Font, st: BoardStyle, a := 1.0,
		square := false, ring := Color(0, 0, 0, 0)) -> void:
	var ink := st.color("ink", a)
	var face := Color(1, 1, 1, a)
	var h := rect.size.y
	var shadow := Rect2(rect.position + Vector2(1.0, 2.0), rect.size)
	if square:
		ci.draw_rect(shadow, st.color("ink", 0.18 * a))
		ci.draw_rect(rect, face)
		ci.draw_rect(rect, ink, false, 1.5)
		var chip_box := Rect2(rect.position + Vector2(4.0, h * 0.25), Vector2(h * 0.5, h * 0.5))
		ci.draw_rect(chip_box, Color(chip, a))
		ci.draw_rect(chip_box, ink, false, 1.0)
	else:
		var rad := h * 0.5
		var left := rect.position + Vector2(rad, rad)
		var right := rect.position + Vector2(rect.size.x - rad, rad)
		var mid := Rect2(rect.position + Vector2(rad, 0.0), Vector2(rect.size.x - h, h))
		ci.draw_rect(Rect2(shadow.position + Vector2(rad, 0.0), mid.size), st.color("ink", 0.18 * a))
		ci.draw_circle(left, rad, face)
		ci.draw_circle(right, rad, face)
		ci.draw_rect(mid, face)
		ci.draw_arc(left, rad, PI * 0.5, PI * 1.5, 12, ink, 1.5)
		ci.draw_arc(right, rad, -PI * 0.5, PI * 0.5, 12, ink, 1.5)
		ci.draw_line(mid.position, Vector2(mid.end.x, mid.position.y), ink, 1.5)
		ci.draw_line(Vector2(mid.position.x, mid.end.y), mid.end, ink, 1.5)
		ci.draw_circle(left + Vector2(1.0, 0.0), h * 0.3, Color(chip, a))
		ci.draw_arc(left + Vector2(1.0, 0.0), h * 0.3, 0.0, TAU, 16, ink, 1.0)
	if ring.a > 0.0:
		ci.draw_rect(rect.grow(3.0), Color(ring, ring.a * a), false, 2.0)
	ci.draw_string(font, rect.position + Vector2(h * 1.05, h * 0.5 + st.magnet_font * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, st.magnet_font, ink)
