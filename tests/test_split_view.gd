extends TestSuite
## 내부 화면 = 층 분리 (2026-11-14): 고른 층과 이웃 층을 화면 위아래로 떼어 모두 온전히 보인다.
## 화면 계산(FloorStack)의 층 간격만 본다 — 실제 층·칸 좌표는 건드리지 않는다. 화면은 tests/ui_split.gd

const HOUSE := "res://data/buildings/house_2f.json"


func _split_stack(lift_px := -1.0) -> FloorStack:
	var p := ViewParams.load_default()
	var b := BuildingData.from_file(HOUSE)
	if lift_px > 0.0:
		p.split_lift_px = lift_px
	return FloorStack.new(b, p)


func test_default_lift_keeps_lower_floor_clear() -> void:
	var s := _split_stack()
	var b := s.building
	var lv: int = s.order[0]
	var up: int = s.partner(lv)
	assert_true(up >= 0, "2층 주택: 1층의 짝 층은 2층")
	var off := s.upper_vec(1)
	assert_eq(off.x, 0.0, "위로만 띄운다 (뒤로 비키지 않음)")
	assert_true(off.y < 0.0, "위층은 화면 위쪽")
	# 기본 간격 (2026-11-14 사용자 결정): 위층 앞 모서리가 아래층 뒷벽 윗부분에 살짝 걸친다 — 바닥은 전혀 가리지 않고,
	# 벽은 높이의 절반 넘게 가리지 않는다. 위층 바닥의 모든 칸 모서리를 같은 화면 x 의 아래층 칸과 견준다
	var proj := IsoProjection.new()
	var fp_low := b.footprint(lv)
	var fp_up := b.footprint(up)
	var wall_m := s.params.inner_wall_m
	var worst := INF
	var worst_floor := INF
	for ux in range(fp_up.position.x, fp_up.end.x + 1):
		for uy in range(fp_up.position.y, fp_up.end.y + 1):
			var pu := proj.to_screen(Vector2(ux, uy)) + off
			for lx in range(fp_low.position.x, fp_low.end.x + 1):
				# 같은 화면 x 가 되는 아래층 칸 (x - y 가 같다)
				var ly := lx - (ux - uy)
				if ly < fp_low.position.y or ly > fp_low.end.y:
					continue
				var pl := proj.to_screen(Vector2(lx, ly), wall_m)
				worst = minf(worst, pl.y - pu.y)
				worst_floor = minf(worst_floor, proj.to_screen(Vector2(lx, ly)).y - pu.y)
	var wall_px := wall_m * IsoProjection.PX_PER_M
	assert_true(worst_floor > 0.0, "위층이 아래층 바닥을 가리지 않는다 (가장 가까운 틈 %.0fpx)" % worst_floor)
	assert_true(worst > -wall_px * 0.5, "아래층 뒷벽은 높이의 절반 넘게 가리지 않는다 (걸친 높이 %.0fpx / 벽 %.0fpx)" % [-worst, wall_px])
	assert_true(absf(s.lift_px - 874.0) < 1.0, "2층 주택 기본 간격 874px (결과 %.1f)" % s.lift_px)


func test_lift_changes_only_screen_offset() -> void:
	# 간격을 바꿔도 층 목록·짝 층·칸 계산은 그대로다 (화면 위치만 달라진다)
	var a := _split_stack(300.0)
	var b := _split_stack(900.0)
	var lv: int = a.order[0]
	assert_eq(a.partner(lv), b.partner(lv), "짝 층은 간격과 무관")
	assert_eq(a.above_levels(lv), b.above_levels(lv), "보이는 위층도 간격과 무관")
	assert_eq(a.upper_vec(1), Vector2(0, -300.0), "간격 300 → 위로 300px")
	assert_eq(b.upper_vec(1), Vector2(0, -900.0), "간격 900 → 위로 900px")
	# 맨 위층에서 보면 짝 층(아래층)은 같은 거리만큼 아래
	var top: int = a.order[-1]
	assert_eq(a.visible_levels(top), [top, lv], "2층에서는 1층이 직하층")
	assert_eq(a.offset_vec(1), Vector2(0, 300.0), "아래층은 아래로 300px")


func test_pick_level_on_lifted_floor() -> void:
	# 띄운 위층을 누르면 그 층, 제자리의 지금 층을 누르면 지금 층
	var s := _split_stack()
	var proj := IsoProjection.new()
	var lv: int = s.order[0]
	var up: int = s.partner(lv)
	var room := Vector2(s.building.footprint(up).get_center())
	assert_eq(s.pick_level(lv, proj.to_screen(room) + s.upper_vec(1), proj), up, "띄운 2층의 방을 누르면 2층")
	assert_eq(s.pick_level(lv, proj.to_screen(room), proj), lv, "제자리의 1층 방을 누르면 1층")


func test_default_is_split_view() -> void:
	# 2026-11-14: 건물 안 화면은 층 분리 하나뿐이다
	var p := ViewParams.load_default()
	assert_eq([p.stack_mode, p.stagger_back_ratio], ["stagger", 0.0], "기본은 층 분리, 뒤로 비키지 않음")
	assert_true(p.split_lift_ratio > 0.0 and p.split_step_px > 0.0 and p.split_zoom_min < RtsCamera.ZOOM_MIN, "층 분리 설정값")
