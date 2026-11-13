extends TestSuite
## 층 분리 보기 (시험 화면, 2026-11-14): 지금 층과 짝 층을 화면 위아래로 떼어 둘 다 온전히 보인다.
## 화면 계산(FloorStack)만 본다 — 실제 층·칸 좌표는 건드리지 않는다. 화면은 tests/ui_split.gd

const HOUSE := "res://data/buildings/house_2f.json"


func _split_stack(lift_px := -1.0) -> FloorStack:
	var p := ViewParams.load_default()
	var b := BuildingData.from_file(HOUSE)
	var base := FloorStack.new(b, p)
	p.stack_mode = "stagger"
	p.stagger_back_ratio = 0.0
	p.stagger_floor_px = lift_px if lift_px > 0.0 else base.split_default_lift_px()
	return FloorStack.new(b, p)


func test_default_lift_clears_lower_floor() -> void:
	var s := _split_stack()
	var b := s.building
	var lv: int = s.order[0]
	var up: int = s.partner(lv)
	assert_true(up >= 0, "2층 주택: 1층의 짝 층은 2층")
	var off := s.upper_vec(1)
	assert_eq(off.x, 0.0, "위로만 띄운다 (뒤로 비키지 않음)")
	assert_true(off.y < 0.0, "위층은 화면 위쪽")
	# 위층 바닥의 모든 칸 모서리가, 같은 화면 x 에서 아래층 벽 꼭대기보다 위에 있어야 한다 (가리지 않는다)
	var proj := IsoProjection.new()
	var fp_low := b.footprint(lv)
	var fp_up := b.footprint(up)
	var wall_m := s.params.inner_wall_m
	var worst := INF
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
	assert_true(worst > 0.0, "위층 바닥이 아래층(벽 꼭대기까지)을 가리지 않는다 (가장 가까운 틈 %.0fpx)" % worst)


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
	assert_eq(a.visible_levels(top), [top, lv], "2층에서는 1층이 짝 층")
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


func test_default_settings_untouched() -> void:
	# 시험 화면은 단추로만 켠다: 기본 설정은 지금 표준(제자리 쌓기) 그대로
	var p := ViewParams.load_default()
	assert_eq(p.stack_mode, "stack", "기본은 제자리 쌓기")
	assert_true(p.split_lift_ratio > 0.0 and p.split_step_px > 0.0 and p.split_zoom_min < RtsCamera.ZOOM_MIN, "층 분리 보기 설정값")
