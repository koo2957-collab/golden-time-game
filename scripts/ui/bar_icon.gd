class_name BarIcon
extends Control
## 아래 바 단추의 작은 그림 — 선으로 직접 그린다 (그림 파일 없음).
## kind: report(보고) · support(지원) · safety(안전) · zone(구역) · board(전술상황판) · radio(무전 기록)

var kind := ""
var color := Color("e2e8f0")


func _init(p_kind := "") -> void:
	kind = p_kind
	custom_minimum_size = Vector2(30, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	var w := 2.0
	match kind:
		"report":
			# 말풍선
			draw_rect(Rect2(c + Vector2(-12, -11), Vector2(24, 16)), color, false, w)
			draw_polyline(PackedVector2Array([c + Vector2(-6, 5), c + Vector2(-8, 12), c + Vector2(0, 5)]), color, w)
			for i in 3:
				draw_circle(c + Vector2(-6 + i * 6, -3), 1.5, color)
		"support":
			# 더하기 (추가 출동)
			draw_arc(c, 12.0, 0.0, TAU, 24, color, w)
			draw_line(c + Vector2(-7, 0), c + Vector2(7, 0), color, w + 1.0)
			draw_line(c + Vector2(0, -7), c + Vector2(0, 7), color, w + 1.0)
		"safety":
			# 방패
			draw_polyline(PackedVector2Array([c + Vector2(-10, -11), c + Vector2(10, -11), c + Vector2(10, 1),
				c + Vector2(0, 13), c + Vector2(-10, 1), c + Vector2(-10, -11)]), color, w)
			draw_line(c + Vector2(0, -6), c + Vector2(0, 2), color, w + 1.0)
			draw_circle(c + Vector2(0, 6), 1.6, color)
		"zone":
			# 깃발을 꽂은 구역
			draw_line(c + Vector2(-8, -12), c + Vector2(-8, 12), color, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -12), c + Vector2(9, -7), c + Vector2(-8, -2)]), color)
			draw_dashed_line(c + Vector2(-12, 12), c + Vector2(12, 12), color, w, 4.0)
		"board":
			# 상황판 (판 + 평면도 칸 + 화점)
			draw_rect(Rect2(c + Vector2(-13, -11), Vector2(26, 20)), color, false, w)
			draw_line(c + Vector2(-3, -11), c + Vector2(-3, 9), color, 1.5)
			draw_line(c + Vector2(-3, -1), c + Vector2(13, -1), color, 1.5)
			draw_circle(c + Vector2(5, 4), 2.5, Color("f87171"))
			draw_line(c + Vector2(-8, 9), c + Vector2(-11, 14), color, w)
			draw_line(c + Vector2(8, 9), c + Vector2(11, 14), color, w)
		"radio":
			# 무전기
			draw_rect(Rect2(c + Vector2(-6, -5), Vector2(12, 18)), color, false, w)
			draw_line(c + Vector2(-3, -5), c + Vector2(-3, -13), color, w)
			draw_line(c + Vector2(-2, 0), c + Vector2(2, 0), color, 1.5)
			draw_line(c + Vector2(-2, 4), c + Vector2(2, 4), color, 1.5)
