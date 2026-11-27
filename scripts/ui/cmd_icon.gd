class_name CmdIcon
extends RefCounted
## 명령·상태 아이콘 — 선으로 직접 그린다 (그림 파일 없음, 사무실 PC에서도 가볍다). 2026-11-27.
## 좌표는 아이콘 상자 안 -1..1 로 쓰고 크기에 맞춰 늘린다. 모르는 종류는 빈 원.
##   명령: data/commands.json 의 id (search·attack·…·vehicle_basket·water_help·office·fetch)
##   상태: crouch·down·thermal·veteran·flame·hose·water·door·warn·pin·tank·hydrant·clock·person·eye·tool


static func draw(ci: CanvasItem, kind: String, c: Vector2, size: float, col: Color) -> void:
	var r := size * 0.5
	var w := maxf(1.5, size / 13.0)
	var p := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * r
	match kind:
		"search":
			ci.draw_arc(p.call(-0.18, -0.18), r * 0.5, 0.0, TAU, 28, col, w, true)
			ci.draw_line(p.call(0.18, 0.18), p.call(0.75, 0.75), col, w * 1.6, true)
		"attack":
			# 관창 + 퍼지는 물
			ci.draw_colored_polygon(PackedVector2Array([p.call(-0.95, -0.3), p.call(-0.25, -0.17), p.call(-0.25, 0.17), p.call(-0.95, 0.3)]), col)
			ci.draw_rect(Rect2(p.call(-0.25, -0.1), Vector2(r * 0.15, r * 0.2)), col)
			for a in [-0.42, 0.0, 0.42]:
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(p.call(-0.05, 0.0) + d * r * 0.08, p.call(-0.05, 0.0) + d * r * 0.78, col, w, true)
				ci.draw_circle(p.call(-0.05, 0.0) + d * r * 0.97, w * 0.75, col)
		"stop":
			ci.draw_arc(c, r * 0.75, 0.0, TAU, 28, col, w, true)
			ci.draw_line(p.call(-0.53, 0.53), p.call(0.53, -0.53), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(-0.3, -0.12), p.call(0.3, -0.12), p.call(0.3, 0.12), p.call(-0.3, 0.12)]), col)
		"check_below":
			ci.draw_line(p.call(-0.85, -0.55), p.call(0.85, -0.55), col, w, true)
			ci.draw_line(p.call(0.0, -0.3), p.call(0.0, 0.75), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(-0.35, 0.4), p.call(0.0, 0.78), p.call(0.35, 0.4)]), col, w, true)
			ci.draw_line(p.call(-0.85, 0.9), p.call(0.85, 0.9), col, w * 0.7, true)
		"watch", "eye":
			_eye(ci, c, r, w, col)
		"observe":
			ci.draw_arc(p.call(-0.42, 0.15), r * 0.36, 0.0, TAU, 20, col, w, true)
			ci.draw_arc(p.call(0.42, 0.15), r * 0.36, 0.0, TAU, 20, col, w, true)
			ci.draw_line(p.call(-0.42, -0.21), p.call(-0.25, -0.6), col, w, true)
			ci.draw_line(p.call(0.42, -0.21), p.call(0.25, -0.6), col, w, true)
			ci.draw_line(p.call(-0.1, 0.0), p.call(0.1, 0.0), col, w, true)
		"exterior":
			# 방패 (경계 — 번짐 막기)
			ci.draw_polyline(PackedVector2Array([p.call(-0.7, -0.75), p.call(0.7, -0.75), p.call(0.7, 0.05), p.call(0.0, 0.85),
				p.call(-0.7, 0.05), p.call(-0.7, -0.75)]), col, w, true)
			ci.draw_line(p.call(-0.35, -0.2), p.call(0.35, -0.2), col, w, true)
			ci.draw_line(p.call(-0.25, 0.15), p.call(0.25, 0.15), col, w, true)
		"ppv":
			ci.draw_arc(c, r * 0.85, 0.0, TAU, 28, col, w * 0.8, true)
			for i in 3:
				var a := i * TAU / 3.0
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				ci.draw_colored_polygon(PackedVector2Array([c + d * r * 0.12, c + d * r * 0.68 + n * r * 0.25, c + d * r * 0.68 - n * r * 0.05]), col)
			ci.draw_circle(c, r * 0.12, col)
		"standby", "hold":
			ci.draw_rect(Rect2(p.call(-0.5, -0.65), Vector2(r * 0.32, r * 1.3)), col)
			ci.draw_rect(Rect2(p.call(0.18, -0.65), Vector2(r * 0.32, r * 1.3)), col)
		"withdraw":
			ci.draw_polyline(PackedVector2Array([p.call(0.1, -0.85), p.call(-0.75, -0.85), p.call(-0.75, 0.85), p.call(0.1, 0.85)]), col, w, true)
			ci.draw_line(p.call(-0.3, 0.0), p.call(0.85, 0.0), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.5, -0.35), p.call(0.88, 0.0), p.call(0.5, 0.35)]), col, w, true)
		"split":
			ci.draw_line(p.call(-0.85, 0.0), p.call(-0.15, 0.0), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(-0.15, 0.0), p.call(0.35, -0.55), p.call(0.85, -0.55)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(-0.15, 0.0), p.call(0.35, 0.55), p.call(0.85, 0.55)]), col, w, true)
			ci.draw_circle(p.call(0.85, -0.55), w * 1.3, col)
			ci.draw_circle(p.call(0.85, 0.55), w * 1.3, col)
		"merge":
			ci.draw_polyline(PackedVector2Array([p.call(-0.85, -0.55), p.call(-0.35, -0.55), p.call(0.15, 0.0)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(-0.85, 0.55), p.call(-0.35, 0.55), p.call(0.15, 0.0)]), col, w, true)
			ci.draw_line(p.call(0.15, 0.0), p.call(0.85, 0.0), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.55, -0.3), p.call(0.87, 0.0), p.call(0.55, 0.3)]), col, w, true)
		"detach":
			_person(ci, p.call(-0.3, 0.0), r * 0.85, col)
			ci.draw_line(p.call(0.2, 0.1), p.call(0.88, 0.1), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.6, -0.18), p.call(0.9, 0.1), p.call(0.6, 0.38)]), col, w, true)
		"recall":
			ci.draw_arc(c, r * 0.65, -PI * 0.15, PI * 1.35, 26, col, w, true)
			var e := c + Vector2(cos(-PI * 0.15), sin(-PI * 0.15)) * r * 0.65
			ci.draw_colored_polygon(PackedVector2Array([e + Vector2(-r * 0.3, -r * 0.08), e + Vector2(r * 0.22, -r * 0.3), e + Vector2(r * 0.12, r * 0.22)]), col)
		"report":
			ci.draw_rect(Rect2(p.call(-0.8, -0.7), Vector2(r * 1.6, r * 1.05)), col, false, w)
			ci.draw_polyline(PackedVector2Array([p.call(-0.45, 0.35), p.call(-0.6, 0.85), p.call(0.0, 0.35)]), col, w, true)
			for i in 3:
				ci.draw_circle(p.call(-0.4 + i * 0.4, -0.18), w * 0.9, col)
		"waypoint":
			for i in 3:
				ci.draw_circle(p.call(-0.8 + i * 0.35, 0.6 - i * 0.2), w * 0.8, col)
			ci.draw_line(p.call(0.35, 0.85), p.call(0.35, -0.85), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.35, -0.85), p.call(0.9, -0.6), p.call(0.35, -0.35)]), col)
		"support":
			_person(ci, p.call(-0.25, 0.0), r * 0.85, col)
			ci.draw_line(p.call(0.45, -0.2), p.call(0.95, -0.2), col, w, true)
			ci.draw_line(p.call(0.7, -0.45), p.call(0.7, 0.05), col, w, true)
		"triage_post":
			ci.draw_polyline(PackedVector2Array([p.call(-0.9, 0.8), p.call(0.0, -0.8), p.call(0.9, 0.8), p.call(-0.9, 0.8)]), col, w, true)
			ci.draw_line(p.call(0.0, 0.05), p.call(0.0, 0.6), col, w * 1.2, true)
			ci.draw_line(p.call(-0.27, 0.32), p.call(0.27, 0.32), col, w * 1.2, true)
		"treat":
			ci.draw_rect(Rect2(p.call(-0.25, -0.8), Vector2(r * 0.5, r * 1.6)), col)
			ci.draw_rect(Rect2(p.call(-0.8, -0.25), Vector2(r * 1.6, r * 0.5)), col)
		"transport":
			ci.draw_rect(Rect2(p.call(-0.9, -0.45), Vector2(r * 1.2, r * 0.9)), col, false, w)
			ci.draw_polyline(PackedVector2Array([p.call(0.3, -0.2), p.call(0.65, -0.2), p.call(0.9, 0.1), p.call(0.9, 0.45), p.call(0.3, 0.45)]), col, w, true)
			ci.draw_circle(p.call(-0.5, 0.55), r * 0.17, col)
			ci.draw_circle(p.call(0.55, 0.55), r * 0.17, col)
			ci.draw_line(p.call(-0.3, -0.05), p.call(-0.3, 0.25), col, w * 0.8)
			ci.draw_line(p.call(-0.45, 0.1), p.call(-0.15, 0.1), col, w * 0.8)
		"vehicle_connect", "hydrant":
			ci.draw_rect(Rect2(p.call(-0.55, -0.35), Vector2(r * 0.6, r * 1.15)), col, false, w)
			ci.draw_arc(p.call(-0.25, -0.35), r * 0.3, PI, TAU, 12, col, w, true)
			ci.draw_line(p.call(-0.85, 0.85), p.call(0.35, 0.85), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.05, 0.15), p.call(0.5, 0.15), p.call(0.5, -0.5), p.call(0.9, -0.5)]), col, w, true)
		"vehicle_monitor":
			ci.draw_rect(Rect2(p.call(-0.85, 0.45), Vector2(r * 0.9, r * 0.4)), col)
			ci.draw_line(p.call(-0.4, 0.45), p.call(0.15, -0.15), col, w * 1.5, true)
			ci.draw_arc(p.call(0.2, -0.2), r * 0.6, -PI * 0.55, -PI * 0.05, 10, col, w * 0.8, true)
			ci.draw_arc(p.call(0.2, -0.2), r * 0.85, -PI * 0.5, -PI * 0.1, 10, col, w * 0.8, true)
		"shuttle":
			ci.draw_line(p.call(-0.8, -0.35), p.call(0.8, -0.35), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.45, -0.65), p.call(0.82, -0.35), p.call(0.45, -0.05)]), col, w, true)
			ci.draw_line(p.call(0.8, 0.35), p.call(-0.8, 0.35), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(-0.45, 0.05), p.call(-0.82, 0.35), p.call(-0.45, 0.65)]), col, w, true)
		"vehicle_move", "pin":
			if kind == "pin":
				ci.draw_arc(p.call(0.0, -0.3), r * 0.45, 0.0, TAU, 20, col, w, true)
				ci.draw_polyline(PackedVector2Array([p.call(-0.4, -0.1), p.call(0.0, 0.85), p.call(0.4, -0.1)]), col, w, true)
			else:
				for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					var n := Vector2(-d.y, d.x)
					ci.draw_line(c + d * r * 0.2, c + d * r * 0.85, col, w, true)
					ci.draw_colored_polygon(PackedVector2Array([c + d * r * 0.95, c + d * r * 0.6 + n * r * 0.25, c + d * r * 0.6 - n * r * 0.25]), col)
		"vehicle_basket":
			ci.draw_line(p.call(-0.85, 0.85), p.call(0.45, -0.45), col, w, true)
			ci.draw_line(p.call(-0.6, 0.95), p.call(0.6, -0.25), col, w, true)
			ci.draw_rect(Rect2(p.call(0.3, -0.9), Vector2(r * 0.6, r * 0.45)), col, false, w)
		"water_help", "water":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.0, -0.9), p.call(0.55, 0.15), p.call(0.45, 0.55), p.call(0.0, 0.85),
				p.call(-0.45, 0.55), p.call(-0.55, 0.15)]), col)
		"office":
			ci.draw_rect(Rect2(p.call(-0.6, -0.5), Vector2(r * 1.2, r * 1.35)), col, false, w)
			for i in 2:
				for j in 2:
					ci.draw_rect(Rect2(p.call(-0.38 + i * 0.45, -0.25 + j * 0.45), Vector2(r * 0.3, r * 0.25)), col)
			ci.draw_line(p.call(0.0, -0.5), p.call(0.0, -0.9), col, w, true)
			ci.draw_arc(p.call(0.0, -0.9), r * 0.18, PI * 1.1, PI * 1.9, 8, col, w * 0.7)
		"fetch", "tool":
			ci.draw_rect(Rect2(p.call(-0.85, -0.2), Vector2(r * 1.7, r * 0.95)), col, false, w)
			ci.draw_polyline(PackedVector2Array([p.call(-0.3, -0.2), p.call(-0.3, -0.55), p.call(0.3, -0.55), p.call(0.3, -0.2)]), col, w, true)
			ci.draw_line(p.call(-0.85, 0.2), p.call(0.85, 0.2), col, w * 0.7)
		"crouch":
			# 낮은 자세: 웅크린 사람
			ci.draw_circle(p.call(0.25, -0.55), r * 0.22, col)
			ci.draw_polyline(PackedVector2Array([p.call(0.15, -0.3), p.call(-0.35, 0.1), p.call(0.15, 0.35), p.call(-0.1, 0.85)]), col, w * 1.2, true)
			ci.draw_line(p.call(-0.35, 0.1), p.call(-0.6, 0.85), col, w * 1.2, true)
		"down":
			_person(ci, c, r, col)
			ci.draw_line(p.call(-0.85, -0.85), p.call(0.85, 0.85), DANGER_X, w * 1.2, true)
		"person":
			_person(ci, c, r, col)
		"thermal":
			ci.draw_rect(Rect2(p.call(-0.85, -0.45), Vector2(r * 1.3, r * 0.95)), col, false, w)
			ci.draw_circle(p.call(-0.2, 0.02), r * 0.25, col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.45, -0.25), p.call(0.9, -0.5), p.call(0.9, 0.45), p.call(0.45, 0.25)]), col)
		"veteran":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + i * PI / 5.0
				var rr := r * (0.9 if i % 2 == 0 else 0.4)
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, col)
		"flame":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.0, -0.95), p.call(0.35, -0.35), p.call(0.6, 0.15), p.call(0.5, 0.6),
				p.call(0.0, 0.9), p.call(-0.5, 0.6), p.call(-0.6, 0.15), p.call(-0.2, -0.2)]), col)
		"hose":
			ci.draw_arc(c, r * 0.75, 0.0, TAU, 24, col, w, true)
			ci.draw_arc(c, r * 0.4, 0.0, TAU, 18, col, w, true)
			ci.draw_line(p.call(0.75, 0.0), p.call(0.95, 0.85), col, w, true)
		"door":
			ci.draw_rect(Rect2(p.call(-0.6, -0.9), Vector2(r * 1.2, r * 1.8)), col, false, w)
			ci.draw_circle(p.call(0.3, 0.05), w, col)
		"warn":
			ci.draw_polyline(PackedVector2Array([p.call(0.0, -0.9), p.call(0.9, 0.75), p.call(-0.9, 0.75), p.call(0.0, -0.9)]), col, w, true)
			ci.draw_line(p.call(0.0, -0.3), p.call(0.0, 0.2), col, w * 1.2)
			ci.draw_circle(p.call(0.0, 0.45), w * 0.8, col)
		"tank":
			ci.draw_rect(Rect2(p.call(-0.85, -0.5), Vector2(r * 1.7, r * 1.15)), col, false, w)
			ci.draw_line(p.call(-0.85, 0.15), p.call(0.85, 0.15), col, w * 0.7)
			ci.draw_circle(p.call(-0.45, 0.85), r * 0.15, col)
			ci.draw_circle(p.call(0.45, 0.85), r * 0.15, col)
		"clock":
			ci.draw_arc(c, r * 0.8, 0.0, TAU, 26, col, w, true)
			ci.draw_line(c, p.call(0.0, -0.5), col, w, true)
			ci.draw_line(c, p.call(0.4, 0.15), col, w, true)
		# --- 지휘관 명령 (아래 바, 2026-11-27) ---
		"radio":
			ci.draw_rect(Rect2(p.call(-0.4, -0.35), Vector2(r * 0.8, r * 1.25)), col, false, w)
			ci.draw_line(p.call(-0.2, -0.35), p.call(-0.2, -0.95), col, w, true)
			ci.draw_line(p.call(-0.15, 0.0), p.call(0.15, 0.0), col, w * 0.8)
			ci.draw_line(p.call(-0.15, 0.3), p.call(0.15, 0.3), col, w * 0.8)
			ci.draw_arc(p.call(-0.2, -0.95), r * 0.5, -PI * 0.3, PI * 0.1, 8, col, w * 0.7, true)
		"board":
			ci.draw_rect(Rect2(p.call(-0.9, -0.75), Vector2(r * 1.8, r * 1.3)), col, false, w)
			ci.draw_line(p.call(-0.2, -0.75), p.call(-0.2, 0.55), col, w * 0.7)
			ci.draw_line(p.call(-0.2, -0.1), p.call(0.9, -0.1), col, w * 0.7)
			ci.draw_circle(p.call(0.35, 0.22), r * 0.15, DANGER_X)
			ci.draw_line(p.call(-0.55, 0.55), p.call(-0.75, 0.95), col, w, true)
			ci.draw_line(p.call(0.55, 0.55), p.call(0.75, 0.95), col, w, true)
		"safety":
			ci.draw_polyline(PackedVector2Array([p.call(-0.7, -0.75), p.call(0.7, -0.75), p.call(0.7, 0.05), p.call(0.0, 0.85),
				p.call(-0.7, 0.05), p.call(-0.7, -0.75)]), col, w, true)
			ci.draw_line(p.call(0.0, -0.45), p.call(0.0, 0.1), col, w * 1.3, true)
			ci.draw_circle(p.call(0.0, 0.38), w * 0.85, col)
		"zone":
			ci.draw_line(p.call(-0.55, -0.85), p.call(-0.55, 0.8), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(-0.55, -0.85), p.call(0.65, -0.5), p.call(-0.55, -0.15)]), col)
			ci.draw_dashed_line(p.call(-0.9, 0.82), p.call(0.9, 0.82), col, w, r * 0.28)
		"declare":
			# 확성기 (지휘권 선언·보고)
			ci.draw_polyline(PackedVector2Array([p.call(-0.85, -0.2), p.call(-0.35, -0.2), p.call(0.3, -0.65), p.call(0.3, 0.65),
				p.call(-0.35, 0.2), p.call(-0.85, 0.2), p.call(-0.85, -0.2)]), col, w, true)
			ci.draw_arc(p.call(0.3, 0.0), r * 0.35, -PI * 0.35, PI * 0.35, 8, col, w * 0.8, true)
			ci.draw_arc(p.call(0.3, 0.0), r * 0.62, -PI * 0.3, PI * 0.3, 8, col, w * 0.8, true)
		"update_report":
			ci.draw_rect(Rect2(p.call(-0.65, -0.85), Vector2(r * 1.05, r * 1.6)), col, false, w)
			for i in 3:
				ci.draw_line(p.call(-0.4, -0.5 + i * 0.38), p.call(0.15, -0.5 + i * 0.38), col, w * 0.7)
			ci.draw_line(p.call(0.4, 0.5), p.call(0.95, 0.5), col, w * 1.2, true)
			ci.draw_line(p.call(0.675, 0.22), p.call(0.675, 0.78), col, w * 1.2, true)
		"strategy":
			# 나침반 (전략 방향)
			ci.draw_arc(c, r * 0.82, 0.0, TAU, 28, col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.45, -0.45), p.call(0.12, 0.12), p.call(-0.12, -0.12)]), col)
			ci.draw_polyline(PackedVector2Array([p.call(-0.45, 0.45), p.call(0.12, 0.12), p.call(-0.12, -0.12), p.call(-0.45, 0.45)]), col, w * 0.7, true)
		"all_clear":
			ci.draw_arc(c, r * 0.82, 0.0, TAU, 28, col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(-0.4, 0.02), p.call(-0.1, 0.35), p.call(0.45, -0.3)]), col, w * 1.4, true)
		"transfer":
			_person(ci, p.call(-0.6, 0.0), r * 0.7, col)
			_person(ci, p.call(0.6, 0.0), r * 0.7, col)
			ci.draw_line(p.call(-0.2, -0.65), p.call(0.25, -0.65), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.05, -0.85), p.call(0.28, -0.65), p.call(0.05, -0.45)]), col, w, true)
		"end":
			# 깃발 (활동 종료)
			ci.draw_line(p.call(-0.6, -0.85), p.call(-0.6, 0.9), col, w, true)
			ci.draw_rect(Rect2(p.call(-0.6, -0.8), Vector2(r * 1.3, r * 0.85)), col, false, w)
			ci.draw_rect(Rect2(p.call(-0.6, -0.8), Vector2(r * 0.65, r * 0.425)), col)
			ci.draw_rect(Rect2(p.call(0.05, -0.375), Vector2(r * 0.65, r * 0.425)), col)
		"support_more":
			ci.draw_rect(Rect2(p.call(-0.9, -0.15), Vector2(r * 1.05, r * 0.7)), col, false, w)
			ci.draw_polyline(PackedVector2Array([p.call(0.15, 0.05), p.call(0.5, 0.05), p.call(0.75, 0.3), p.call(0.75, 0.55), p.call(0.15, 0.55)]), col, w, true)
			ci.draw_circle(p.call(-0.55, 0.65), r * 0.15, col)
			ci.draw_circle(p.call(0.45, 0.65), r * 0.15, col)
			ci.draw_line(p.call(0.3, -0.6), p.call(0.9, -0.6), col, w * 1.2, true)
			ci.draw_line(p.call(0.6, -0.9), p.call(0.6, -0.3), col, w * 1.2, true)
		"response_1":
			# 경광등
			ci.draw_rect(Rect2(p.call(-0.65, 0.45), Vector2(r * 1.3, r * 0.3)), col)
			ci.draw_arc(p.call(0.0, 0.4), r * 0.5, PI, TAU, 14, col, w, true)
			ci.draw_line(p.call(-0.5, 0.4), p.call(0.5, 0.4), col, w)
			for a in [-PI * 0.5, -PI * 0.22, -PI * 0.78]:
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(p.call(0.0, 0.4) + d * r * 0.72, p.call(0.0, 0.4) + d * r * 1.1, col, w, true)
		"org":
			ci.draw_rect(Rect2(p.call(-0.3, -0.85), Vector2(r * 0.6, r * 0.45)), col)
			ci.draw_line(p.call(0.0, -0.4), p.call(0.0, 0.0), col, w)
			ci.draw_line(p.call(-0.68, 0.0), p.call(0.68, 0.0), col, w)
			for x in [-0.68, 0.0, 0.68]:
				ci.draw_line(p.call(x, 0.0), p.call(x, 0.35), col, w)
				ci.draw_rect(Rect2(p.call(x - 0.22, 0.35), Vector2(r * 0.44, r * 0.45)), col, false, w)
		"rit":
			# 구명환 (신속동료구조팀)
			ci.draw_arc(c, r * 0.82, 0.0, TAU, 28, col, w, true)
			ci.draw_arc(c, r * 0.38, 0.0, TAU, 18, col, w, true)
			for i in 4:
				var a := PI * 0.25 + i * PI * 0.5
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * r * 0.38, c + d * r * 0.82, col, w * 1.6, true)
		"officer":
			# 방패 + 확인 (현장안전담당)
			ci.draw_polyline(PackedVector2Array([p.call(-0.7, -0.75), p.call(0.7, -0.75), p.call(0.7, 0.05), p.call(0.0, 0.85),
				p.call(-0.7, 0.05), p.call(-0.7, -0.75)]), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(-0.32, -0.08), p.call(-0.05, 0.22), p.call(0.38, -0.32)]), col, w * 1.3, true)
		"par":
			# 점검표 (인원 점검)
			ci.draw_rect(Rect2(p.call(-0.65, -0.7), Vector2(r * 1.3, r * 1.6)), col, false, w)
			ci.draw_rect(Rect2(p.call(-0.25, -0.9), Vector2(r * 0.5, r * 0.3)), col)
			for i in 3:
				var y := -0.25 + i * 0.4
				ci.draw_circle(p.call(-0.38, y), w * 0.8, col)
				ci.draw_line(p.call(-0.15, y), p.call(0.42, y), col, w * 0.8)
		"withdraw_all":
			ci.draw_polyline(PackedVector2Array([p.call(-0.1, -0.85), p.call(-0.85, -0.85), p.call(-0.85, 0.85), p.call(-0.1, 0.85)]), col, w, true)
			for x in [-0.25, 0.3]:
				ci.draw_polyline(PackedVector2Array([p.call(x, -0.42), p.call(x + 0.45, 0.0), p.call(x, 0.42)]), col, w * 1.3, true)
		"evacuate":
			# 경보 (긴급탈출)
			ci.draw_polyline(PackedVector2Array([p.call(0.0, -0.9), p.call(0.9, 0.75), p.call(-0.9, 0.75), p.call(0.0, -0.9)]), col, w * 1.3, true)
			ci.draw_line(p.call(0.0, -0.35), p.call(0.0, 0.2), col, w * 1.5, true)
			ci.draw_circle(p.call(0.0, 0.48), w, col)
		"zone_safe":
			_dashed_box(ci, c, r, w, col)
			ci.draw_polyline(PackedVector2Array([p.call(-0.38, 0.02), p.call(-0.08, 0.35), p.call(0.42, -0.32)]), col, w * 1.3, true)
		"zone_casualty":
			_dashed_box(ci, c, r, w, col)
			ci.draw_line(p.call(0.0, -0.42), p.call(0.0, 0.42), col, w * 1.8)
			ci.draw_line(p.call(-0.42, 0.0), p.call(0.42, 0.0), col, w * 1.8)
		"zone_line":
			ci.draw_line(p.call(-0.8, -0.5), p.call(-0.8, 0.8), col, w * 1.2, true)
			ci.draw_line(p.call(0.8, -0.5), p.call(0.8, 0.8), col, w * 1.2, true)
			ci.draw_dashed_line(p.call(-0.8, -0.3), p.call(0.8, -0.3), col, w * 1.3, r * 0.3)
			ci.draw_dashed_line(p.call(-0.8, 0.15), p.call(0.8, 0.15), col, w * 1.3, r * 0.3)
		"zone_post":
			# 천막 + 깃발 (지휘소)
			ci.draw_polyline(PackedVector2Array([p.call(-0.9, 0.8), p.call(0.0, -0.3), p.call(0.9, 0.8), p.call(-0.9, 0.8)]), col, w, true)
			ci.draw_line(p.call(0.0, -0.3), p.call(0.0, -0.95), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.0, -0.95), p.call(0.5, -0.78), p.call(0.0, -0.6)]), col)
			ci.draw_polyline(PackedVector2Array([p.call(-0.2, 0.8), p.call(0.0, 0.3), p.call(0.2, 0.8)]), col, w * 0.8, true)
		"zone_forward":
			ci.draw_line(p.call(-0.75, -0.85), p.call(-0.75, 0.85), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(-0.75, -0.85), p.call(0.1, -0.55), p.call(-0.75, -0.25)]), col)
			ci.draw_line(p.call(-0.3, 0.35), p.call(0.85, 0.35), col, w, true)
			ci.draw_polyline(PackedVector2Array([p.call(0.5, 0.05), p.call(0.88, 0.35), p.call(0.5, 0.65)]), col, w, true)
		"info":
			ci.draw_arc(c, r * 0.82, 0.0, TAU, 28, col, w, true)
			ci.draw_circle(p.call(0.0, -0.4), w * 0.95, col)
			ci.draw_line(p.call(0.0, -0.1), p.call(0.0, 0.45), col, w * 1.4, true)
		"help":
			ci.draw_arc(c, r * 0.82, 0.0, TAU, 28, col, w, true)
			ci.draw_arc(p.call(0.0, -0.22), r * 0.25, PI, PI * 2.45, 12, col, w * 1.2, true)
			ci.draw_line(p.call(0.08, 0.0), p.call(0.0, 0.2), col, w * 1.2, true)
			ci.draw_circle(p.call(0.0, 0.48), w * 0.9, col)
		"survey":
			# 건물 둘레 한 바퀴
			ci.draw_rect(Rect2(p.call(-0.28, -0.28), Vector2(r * 0.56, r * 0.56)), col)
			ci.draw_arc(c, r * 0.78, -PI * 0.35, PI * 1.4, 26, col, w, true)
			var e := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * r * 0.78
			ci.draw_colored_polygon(PackedVector2Array([e + Vector2(-r * 0.32, -r * 0.02), e + Vector2(r * 0.12, -r * 0.34), e + Vector2(r * 0.14, r * 0.2)]), col)
		_:
			ci.draw_arc(c, r * 0.6, 0.0, TAU, 20, col, w, true)


const DANGER_X := Color("f87171")


static func _dashed_box(ci: CanvasItem, c: Vector2, r: float, w: float, col: Color) -> void:
	var a := c + Vector2(-0.85, -0.85) * r
	var b := c + Vector2(0.85, -0.85) * r
	var d := c + Vector2(0.85, 0.85) * r
	var e := c + Vector2(-0.85, 0.85) * r
	for seg: Array in [[a, b], [b, d], [d, e], [e, a]]:
		ci.draw_dashed_line(seg[0], seg[1], col, w, r * 0.3)


static func _eye(ci: CanvasItem, c: Vector2, r: float, w: float, col: Color) -> void:
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in 13:
		var t := -1.0 + i / 6.0
		top.append(c + Vector2(t * r * 0.9, -(1.0 - t * t) * r * 0.55))
		bot.append(c + Vector2(t * r * 0.9, (1.0 - t * t) * r * 0.55))
	ci.draw_polyline(top, col, w, true)
	ci.draw_polyline(bot, col, w, true)
	ci.draw_circle(c, r * 0.25, col)


static func _person(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(0, -r * 0.5), r * 0.26, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.45, r * 0.85), c + Vector2(-r * 0.38, -r * 0.05),
		c + Vector2(0, -r * 0.18), c + Vector2(r * 0.38, -r * 0.05), c + Vector2(r * 0.45, r * 0.85)]), col)
