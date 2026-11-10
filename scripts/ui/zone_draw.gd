class_name ZoneDraw
extends RefCounted
## 구역 지정 그리기 (P10-2 ⓑ): 입체 화면·평면 화면·미니맵이 같이 쓴다.
## to_screen: 칸 좌표(Vector2) → 그 화면 좌표. 글자는 font_size가 0이면 쓰지 않는다 (미니맵)
## 입체 화면은 땅(면·선)을 먼저, 표시(십자·이름)는 차량·대원에 가리지 않게 맨 위에 따로 그린다


static func draw(ci: CanvasItem, zones: ZoneSystem, to_screen: Callable, font_size := 13, tick := 0) -> void:
	draw_ground(ci, zones, to_screen, font_size)
	draw_marks(ci, zones, to_screen, font_size, tick)


## 안전구역 면·테두리, 진입통제선
static func draw_ground(ci: CanvasItem, zones: ZoneSystem, to_screen: Callable, font_size := 13) -> void:
	if zones == null:
		return
	# 안전구역을 정하기 전: 건물에서 떨어뜨릴 거리 안내선 (SOP 213-2.7.1)
	if not zones.has_safe() and zones.guide_m > 0.0:
		var g := zones.guide_rect()
		var gp := PackedVector2Array([to_screen.call(g.position), to_screen.call(Vector2(g.end.x, g.position.y)),
			to_screen.call(g.end), to_screen.call(Vector2(g.position.x, g.end.y)), to_screen.call(g.position)])
		for i in 4:
			ci.draw_dashed_line(gp[i], gp[i + 1], Color(PlanStyle.SAFE_ZONE, 0.55), 1.5, 8.0)
		if font_size > 0:
			ci.draw_string(PlanStyle.font(), gp[0] + Vector2(4, -4), "안전구역은 이 선 밖 (%s %dm)" % [zones.guide_reason, roundi(zones.guide_m)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2, Color(PlanStyle.SAFE_ZONE, 0.8))
	if zones.has_safe():
		var r := Rect2(zones.safe)
		var pts := PackedVector2Array([to_screen.call(r.position), to_screen.call(Vector2(r.end.x, r.position.y)),
			to_screen.call(r.end), to_screen.call(Vector2(r.position.x, r.end.y))])
		ci.draw_colored_polygon(pts, Color(PlanStyle.SAFE_ZONE, 0.14))
		pts.append(pts[0])
		ci.draw_polyline(pts, PlanStyle.SAFE_ZONE, 2.0)
	if zones.line.size() == 2:
		ci.draw_dashed_line(to_screen.call(zones.line[0]), to_screen.call(zones.line[1]), PlanStyle.CONTROL_LINE, 3.0, 10.0)


## 이름·환자 집결지·분류소 표시
static func draw_marks(ci: CanvasItem, zones: ZoneSystem, to_screen: Callable, font_size := 13, tick := 0) -> void:
	if zones == null:
		return
	var font := PlanStyle.font()
	if zones.has_safe() and font_size > 0:
		var r := Rect2(zones.safe)
		ci.draw_string(font, to_screen.call(Vector2(r.position.x + 0.5, r.position.y + 1.5)), "안전구역", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, PlanStyle.SAFE_ZONE.lightened(0.3))
	if zones.line.size() == 2 and font_size > 0:
		ci.draw_string(font, to_screen.call(zones.line[0]) + Vector2(-50, -6), "진입통제선", HORIZONTAL_ALIGNMENT_CENTER, 100, font_size, PlanStyle.CONTROL_LINE)
	if zones.casualty.x >= 0 and zones.triage.x < 0:
		_marker(ci, to_screen.call(Vector2(zones.casualty) + Vector2(0.5, 0.5)), PlanStyle.CASUALTY_POINT, "환자 집결지" if font_size > 0 else "", font_size)
	if zones.triage.x >= 0:
		_marker(ci, to_screen.call(Vector2(zones.triage) + Vector2(0.5, 0.5)), PlanStyle.TRIAGE_POST, "분류소" if font_size > 0 else "", font_size)
	elif not zones.triage_setup.is_empty():
		var c: Vector2 = to_screen.call(Vector2(zones.triage_setup.cell) + Vector2(0.5, 0.5))
		var prog := zones.triage_progress(tick)
		ci.draw_arc(c, 9.0, 0.0, TAU, 20, Color(PlanStyle.TRIAGE_POST, 0.5), 2.0)
		if prog >= 0.0:
			ci.draw_arc(c, 9.0, -PI / 2.0, -PI / 2.0 + TAU * prog, 20, PlanStyle.TRIAGE_POST, 3.0)
		if font_size > 0:
			ci.draw_string(font, c + Vector2(-60, -14), "분류소 설치 중", HORIZONTAL_ALIGNMENT_CENTER, 120, font_size, PlanStyle.TRIAGE_POST)


## 흰 바탕 십자 표시 + 이름
static func _marker(ci: CanvasItem, c: Vector2, color: Color, label: String, font_size: int) -> void:
	var s := 10.0 if font_size > 0 else 3.0
	ci.draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), Color.WHITE)
	ci.draw_rect(Rect2(c - Vector2(s * 0.3, s * 0.85), Vector2(s * 0.6, s * 1.7)), color)
	ci.draw_rect(Rect2(c - Vector2(s * 0.85, s * 0.3), Vector2(s * 1.7, s * 0.6)), color)
	if label != "":
		ci.draw_string(PlanStyle.font(), c + Vector2(-60, -s - 4.0), label, HORIZONTAL_ALIGNMENT_CENTER, 120, font_size, color.lightened(0.3))
