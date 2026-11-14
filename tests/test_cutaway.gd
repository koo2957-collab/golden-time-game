extends TestSuite
## 건물 안 화면 계산 (FloorStack): 내부 화면 = 층 분리 (2026-11-14 결정), 벽 모양·계단·층 고르기.
## '_stack()' 을 쓰는 것은 2026-11-14에 없앤 예전 제자리 단면의 계산 — 그리기 코드를 정리할 때 함께 지운다

const APT := "res://data/buildings/apartment_15f.json"
const SUPERTALL := "res://data/buildings/supertall_52f.json"
const BASEMENT := "res://data/buildings/basement_karaoke.json"


## 예전 쌓기 방식(stack)으로 — 아래 쌓기·벽 모양 점검은 이 방식 기준
func _stack(path: String) -> FloorStack:
	var p := ViewParams.load_default()
	p.stack_mode = "stack"
	return FloorStack.new(BuildingData.from_file(path), p)


## 내부 화면 = 층 분리 (2026-11-14 사용자 결정): 고른 층 + 직상층 + 직하층, 위아래로만 떼어 놓는다
func test_interior_shows_floor_above_and_below() -> void:
	var p := ViewParams.load_default()
	assert_eq(p.stack_mode, "stagger", "기본은 층 분리")
	var s := FloorStack.new(BuildingData.from_file(APT), p)
	assert_true(s.staggered(), "층 분리")
	assert_eq([s.visible_levels(12), s.above_levels(12)], [[12, 11] as Array[int], [13] as Array[int]], "12층: 직하층 11층 + 직상층 13층")
	var top := s.order[-1]
	assert_eq([s.visible_levels(top), s.above_levels(top)], [[top, top - 1] as Array[int], [] as Array[int]], "맨 위층: 직하층만")
	assert_eq([s.visible_levels(1), s.above_levels(1)], [[1] as Array[int], [2] as Array[int]], "1층: 직상층만 (땅 밑으로는 잇지 않음)")
	assert_eq([s.more_above(12), s.more_below(12)], [false, false], "층 분리에서는 잘린 벽을 쓰지 않는다")
	assert_true(s.lift_px > 0.0 and is_equal_approx(s.lift_px, s.split_default_lift_px()), "간격은 건물 크기로 계산")
	assert_eq([s.upper_vec(1), s.offset_vec(1)], [Vector2(0, -s.lift_px), Vector2(0, s.lift_px)], "직상층은 간격만큼 위, 직하층은 간격만큼 아래 (옆으로 비키지 않음)")
	# 층을 건너뛴 건물·지하: 이어진 층만
	var st := FloorStack.new(BuildingData.from_file(SUPERTALL), ViewParams.load_default())
	assert_eq(st.visible_levels(2), [2] as Array[int], "28층 아래 생략 층은 붙이지 않음")
	var bm := FloorStack.new(BuildingData.from_file(BASEMENT), ViewParams.load_default())
	assert_eq([bm.visible_levels(1), bm.above_levels(2)], [[1] as Array[int], [] as Array[int]], "1층과 지하층은 서로 붙이지 않음")
	# 간격을 정해 두면 그 값
	var p2 := ViewParams.load_default()
	p2.split_lift_px = 500.0
	assert_eq(FloorStack.new(BuildingData.from_file(APT), p2).lift_px, 500.0, "split_lift_px 를 주면 그 간격")


## 내부 화면에서 보이는 층은 어디든 누를 수 있다: 직상층·직하층의 방, 직하층이 땅 층이면 바깥 땅도
func test_interior_pick_any_shown_floor() -> void:
	var s := FloorStack.new(BuildingData.from_file(BUILDING_PATH), ViewParams.load_default())
	var proj := IsoProjection.new()
	var low: int = s.order[0]
	var up: int = s.order[1]
	var room := Vector2(s.building.footprint(up).get_center())
	assert_eq(s.pick_level(low, proj.to_screen(room) + s.upper_vec(1), proj), up, "1층에서: 위로 뗀 2층의 방 → 2층")
	assert_eq(s.pick_level(low, proj.to_screen(room), proj), low, "1층에서: 제자리의 1층 방 → 1층")
	assert_eq(s.pick_level(up, proj.to_screen(room) + s.offset_vec(1), proj), low, "2층에서: 아래로 뗀 1층의 방 → 1층")
	assert_eq(s.pick_level(up, proj.to_screen(Vector2(5.5, 30.5)) + s.offset_vec(1), proj), low, "2층에서: 아래 1층의 바깥 도로 → 1층 (차량·바깥 대원·구역)")
	assert_eq(s.pick_level(up, proj.to_screen(room), proj), up, "2층에서: 제자리의 2층 방 → 2층")


func test_view_params_loaded() -> void:
	var p := ViewParams.load_default()
	assert_eq(p.floor_height_px, 220.0, "층 간격 220px (2026-11-11 사용자 결정 F01: 건물을 더 높게)")
	assert_eq([p.visible_floors_above, p.visible_floors_below], [1, 1], "위·아래 한 층씩만 — 더 있는 층은 잘린 벽으로 (2026-11-12)")
	assert_true(p.stub_height_ratio > 0.2 and p.stub_height_ratio <= 1.0, "잘린 벽은 층 높이보다 낮게 (2026-11-12: 0.5 → 0.9로 키움)")
	assert_eq(p.below_modulate, [0.75, 0.55] as Array[float], "아래 층 밝기")
	assert_eq(p.front_wall, "open", "앞벽은 없음 — 인형집 (2026-11-12 결정)")
	assert_eq([p.front_wall_alpha, p.inner_wall_m, p.stack_mode, p.stagger_back_ratio], [0.15, 2.4, "stagger", 0.0], "앞벽 15%, 실내 벽 천장까지(F04), 건물 안은 층 분리 — 뒤로 비키지 않고 위아래로만 (2026-11-14)")
	assert_eq([p.zoom_switch, p.split_lift_px, p.split_outdoor_darken > 0.0, p.split_city_dim < 1.0], [false, 0.0, true, true], "줌으로 안팎 전환 없음, 층 간격은 건물 크기로 계산, 내부 화면에서는 바깥을 흐리게")
	assert_true(p.ghost_line_alpha <= 0.6 and p.ghost_dash_px > 0.0 and is_equal_approx(p.ghost_body_alpha, 0.25), "다른 층은 평면도 선만(실내 벽 점선), 연기에 가려진 사람 몸 25% (2026-11-12)")
	assert_true(p.ghost_outline_px > 0.0 and p.ghost_outline_px < 3.0, "사람 테두리는 얇게 (2026-11-12)")
	assert_true(p.ghost_back_wall_alpha > 0.0 and p.ghost_back_wall_alpha < 1.0, "위층 뒷벽·왼쪽 벽은 반투명 면 (2026-11-12)")
	assert_true(p.ghost_ledge_m > 0.0 and p.ghost_ledge_m <= 2.0 and p.ghost_ledge_jag_m >= 0.0 and p.ghost_slab_m > 0.0, "위층 바닥은 뒷벽·왼쪽 벽을 따라 좁은 턱만 (지금 층 방 안을 가리지 않는 폭)")
	assert_true(p.ghost_other_fill < p.ghost_body_alpha, "다른 층 사람은 테두리만(안쪽 투명), 같은 층에서 가려진 사람은 안쪽이 비친다 (2026-11-12)")
	assert_true(p.inner_wall_alpha_bottom > p.inner_wall_alpha_top and p.inner_wall_cap_alpha > 0.5, "실내 벽은 아래 진하게·위로 옅게, 흰 윗면 테두리 (2026-11-12)")
	assert_eq(p.wall_cut_m, 0.2, "잘린 벽 20cm")
	# 연기층 그림 (2026-11-12 사용자 결정: Kenney 연기 덩어리 구름, 윗면 옅게·앞면 진하게, 높이 눈금)
	assert_eq([p.smoke_top_alpha < p.smoke_front_alpha, p.smoke_max_puffs > 0, p.smoke_row_m, p.smoke_max_rows], [true, true, 0.4, 6], "연기 윗면은 앞면보다 옅게, 덩어리 상한, 0.4m마다 한 줄씩 겹쳐 쌓기(최대 6줄)")
	assert_true(p.smoke_outline_opacity > 0.0 and p.smoke_outline_opacity < p.smoke_max_opacity, "화면에서 연기 상자에 덮인 사람은 테두리로 (진하기 기준)")
	assert_true(p.wall_fade_px > 0.0 and p.wall_fade_alpha < 0.5, "대상 앞 실내 벽은 둘레만 옅게 (2026-11-12)")
	assert_true(p.smoke_plume_alpha > 0.0 and p.smoke_spill_alpha > 0.0 and p.smoke_sheet_flow_mps > 0.0, "연기 기둥·넘침 그림 진하기와 퍼지는 속도")
	# 연기 진하기 하나 (2026-11-12): 커튼 천장 쪽과 윗면이 같은 값, 커튼은 아래로 갈수록 옅게
	assert_true(p.smoke_max_opacity > 0.5 and p.smoke_max_opacity < 1.0 and p.smoke_opacity_k > 0.0, "진하기 상한·두께 계수")
	assert_true(p.smoke_curtain_low > 0.0 and p.smoke_curtain_low < 1.0, "커튼 아래쪽은 천장 쪽보다 옅게")


func test_apartment_12f_shows_11_to_13_and_stubs() -> void:
	# 2026-11-12 사용자 결정: 지금 층 위·아래 한 층씩만, 더 있는 층은 잘린 벽으로 알린다 (예전: 각 2개 층)
	var s := _stack(APT)
	var shown := s.visible_levels(12)
	assert_eq(shown, [12, 11] as Array[int], "12층 아래로 11층")
	assert_eq(s.above_levels(12), [13] as Array[int], "위로 13층")
	assert_eq(s.above_levels(15), [] as Array[int], "꼭대기 층은 위층 없음")
	assert_eq(s.above_levels(14), [15] as Array[int], "14층 위는 15층만")
	for lv in [14, 10]:
		assert_true(not shown.has(lv) and not s.above_levels(12).has(lv), "%d층은 보이지 않음" % lv)
	assert_eq([s.more_above(12), s.more_below(12)], [true, true], "12층: 위(14층~)·아래(10층~)로 더 있다")
	assert_eq([s.more_above(14), s.more_above(15)], [false, false], "14층 위는 15층뿐, 꼭대기는 위가 없다")
	assert_eq([s.more_below(2), s.more_below(1), s.more_below(3)], [false, false, true], "2층 아래는 1층뿐(땅 밑으로는 잇지 않음), 3층은 1층이 더 있다")
	assert_eq(s.depth_of(12, 11), 1, "11층은 한 층 아래")
	assert_eq(s.modulate_for(0), 1.0, "지금 층은 밝게")
	assert_eq(s.modulate_for(1), 0.75, "한 층 아래 0.75")
	assert_eq(s.modulate_for(2), 0.55, "두 층 아래 0.55")
	assert_eq(s.offset_px(2), 440.0, "두 층 아래는 440px 아래에 (220 × 2)")
	assert_eq(s.visible_levels(2), [2, 1] as Array[int], "2층은 2·1층")
	assert_eq(s.visible_levels(1), [1] as Array[int], "1층은 혼자")


func test_supertall_and_basement_do_not_stack_across_gaps() -> void:
	var st := _stack(SUPERTALL)
	# index 2 = 28층: 27층은 생략된 층이라 쌓지 않는다
	assert_eq(st.visible_levels(2), [2] as Array[int], "28층 아래 생략 층은 쌓지 않음")
	assert_eq(st.visible_levels(4), [4, 3] as Array[int], "30층은 30·29층")
	assert_eq([st.more_below(4), st.more_below(3)], [true, false], "30층 아래로 28층이 더 있고, 29층 아래 28층 밑은 생략 층이라 잇지 않음")
	assert_eq(st.order, [1, 2, 3, 4, 5, 6, 7, 8] as Array[int], "층 번호 순서")
	var bm := _stack(BASEMENT)
	assert_eq(bm.order, [2, 1] as Array[int], "지하1층(index 2)이 1층보다 아래")
	assert_eq(bm.visible_levels(1), [1] as Array[int], "1층 밑의 지하층은 땅에 가려 쌓지 않음")
	assert_eq(bm.visible_levels(2), [2] as Array[int], "지하1층은 혼자")


func test_apartment_12f_wall_shapes() -> void:
	var s := _stack(APT)
	assert_eq(s.wall_kind(12, 10, 4), FloorStack.Wall.FULL, "북쪽 외벽(창)은 뒷벽 — 온전")
	assert_eq(s.wall_kind(12, 6, 10), FloorStack.Wall.FULL, "서쪽 외벽은 뒷벽 — 온전")
	assert_eq(s.wall_kind(12, 8, 19), FloorStack.Wall.OPEN, "남쪽 외벽은 앞벽 — 인형집이라 없음 (2026-11-12)")
	assert_eq(s.wall_kind(12, 10, 19), FloorStack.Wall.OPEN, "남쪽 창 자리도 앞벽 (창은 바닥 높이로 낮게)")
	assert_eq(s.wall_kind(12, 53, 10), FloorStack.Wall.OPEN, "동쪽 외벽은 앞벽 — 없음")
	assert_eq(s.wall_kind(12, 53, 19), FloorStack.Wall.OPEN, "남동 모서리도 없음")
	assert_eq(s.wall_kind(12, 6, 19), FloorStack.Wall.FULL, "남서 모서리 기둥은 건물 모양을 남김")
	assert_eq(s.wall_kind(12, 20, 12), FloorStack.Wall.HALF, "실내 벽은 허리 높이 (위로 갈수록 투명)")
	assert_eq(s.wall_kind(12, 15, 15), FloorStack.Wall.HIDDEN, "바닥은 벽이 아님")
	assert_true(s.is_back_wall(12, 10, 4) and not s.is_back_wall(12, 8, 19), "뒷벽·앞벽 구분")
	# 외부 보기는 외벽이 모두 닫힌다
	assert_eq(s.wall_kind(12, 8, 19, true), FloorStack.Wall.FULL, "외부 보기: 남쪽 외벽 온전")
	assert_eq(s.wall_kind(12, 53, 10, true), FloorStack.Wall.FULL, "외부 보기: 동쪽 외벽 온전")
	# 슬래브 단면 띠는 남·동 모서리에
	assert_eq(s.front_edge(12, 8, 19), FloorStack.EDGE_SOUTH, "남쪽 모서리")
	assert_eq(s.front_edge(12, 53, 10), FloorStack.EDGE_EAST, "동쪽 모서리")
	assert_eq(s.front_edge(12, 53, 19), FloorStack.EDGE_SOUTH | FloorStack.EDGE_EAST, "남동 모서리는 두 방향")
	assert_eq(s.front_edge(12, 10, 4), 0, "북쪽은 앞 모서리가 아님")


func test_hidden_front_wall_option() -> void:
	var p := ViewParams.load_default()
	p.front_wall = "hidden"
	var s := FloorStack.new(BuildingData.from_file(APT), p)
	assert_eq(s.wall_kind(12, 8, 19), FloorStack.Wall.HIDDEN, "숨김 설정이면 앞벽을 숨긴다")
	assert_eq(s.wall_kind(12, 10, 4), FloorStack.Wall.FULL, "뒷벽은 그대로")


func test_stairs_link_between_floors() -> void:
	var s := _stack(APT)
	var links := s.stair_links_between(11, 12)
	assert_eq(links.size(), 20, "11~12층 계단실 4×5칸이 이어짐")
	assert_true(links.has(Vector2i(28, 5)) and links.has(Vector2i(31, 9)), "계단실 위치")
	assert_eq(s.stair_links_between(10, 11).size(), 20, "10~11층도 이어짐")


func test_pick_lower_floor_changes_level() -> void:
	var s := _stack(APT)
	var proj := IsoProjection.new()
	# 지금 층(12층) 바닥을 누르면 12층
	assert_eq(s.pick_level(12, proj.to_screen(Vector2(15.5, 15.5)), proj), 12, "12층 바닥")
	# 11층의 남쪽 앞 띠: 12층 바닥 밖(아래)으로 보이는 곳
	var below := proj.to_screen(Vector2(30.5, 18.5)) + Vector2(0, s.offset_px(1))
	assert_eq(s.pick_level(12, below, proj), 11, "아래층(11층)이 보이는 곳을 누르면 11층")
	var below2 := proj.to_screen(Vector2(30.5, 18.5)) + Vector2(0, s.offset_px(2))
	assert_eq(s.pick_level(12, below2, proj), 12, "두 층 아래(10층)는 보이지 않으므로 고를 수 없다 (2026-11-12: 아래 한 층만) — 층 막대·PgDn으로")
	# 아무 층도 없는 곳은 지금 층
	assert_eq(s.pick_level(12, proj.to_screen(Vector2(65, 35)), proj), 12, "빈 곳은 지금 층")
	# 지상층의 도로는 지금 층
	var hs := _stack(BUILDING_PATH)
	assert_eq(hs.pick_level(1, proj.to_screen(Vector2(5.5, 30.5)), proj), 1, "1층 바깥 도로")


func test_smoke_spills_from_fuller_room_and_outside() -> void:
	# F04 (2026-11-12): 개구부 윗부분으로 흘러나오는 연기 (Blender 플립북) — 연기층 아랫면이 인방보다 낮을 때만,
	# 방 사이 문은 연기가 더 찬 방 → 덜 찬 방으로, 나오는 방에서 멀어지는 축 방향
	var sim := SimWorld.from_scenario("res://data/scenarios/sop214_2_night_upstairs.json")
	var fire := sim.fire
	for c in fire.comps:
		c.layer_depth = 0.0
		c.soot = 0.0
	var inner: Opening = null
	var outer: Opening = null
	for o in fire.openings:
		if not o.cells.is_empty() and o.room_a != Opening.OUTSIDE:
			if o.room_b != Opening.OUTSIDE and inner == null:
				inner = o
			elif o.room_b == Opening.OUTSIDE and outer == null:
				outer = o
	assert_true(inner != null and outer != null, "방 사이 개구부와 바깥 개구부가 있음")
	inner.is_open = true
	outer.is_open = true
	assert_eq(FloorLayer.smoke_spills(sim, inner.level).size(), 0, "연기가 없으면 넘치지 않음")
	# 방 사이: room_b 쪽에 연기를 채운다 → room_b 에서 room_a 로
	var full := fire.comps[inner.room_b]
	full.layer_depth = full.height - (inner.top - 0.5)
	full.soot = 0.5
	var found := false
	var mid := Vector2.ZERO
	for cell in inner.cells:
		mid += (Vector2(cell) + Vector2(0.5, 0.5)) / inner.cells.size()
	for s in FloorLayer.smoke_spills(sim, inner.level):
		var at: Vector2 = s[0]
		if bool(s[4]) and int(s[5]) == inner.room_b and at.is_equal_approx(mid):
			found = true
			assert_eq(int(s[6]), inner.room_a, "덜 찬 방으로")
			var d: Vector2 = s[2]
			assert_eq(absf(d.x) + absf(d.y), 1.0, "축 방향 단위")
			var ahead := fire.compartment_at(inner.level, inner.cells[0].x + int(d.x), inner.cells[0].y + int(d.y))
			assert_true(ahead != full, "연기가 나오는 방 반대쪽으로")
	assert_true(found, "연기가 더 찬 방에서 문 위로 넘친다")
	# 바깥: 그 방 연기층이 인방보다 낮으면 밖으로
	var room := fire.comps[outer.room_a]
	room.layer_depth = room.height - (outer.top - 0.3)
	room.soot = 0.5
	var out_found := false
	for s in FloorLayer.smoke_spills(sim, outer.level):
		if not bool(s[4]) and int(s[5]) == outer.room_a:
			out_found = true
	assert_true(out_found, "바깥 창·문으로 넘친다")


func test_mood_follows_scenario_clock() -> void:
	# 2026-11-14: 화면 분위기는 시나리오 시각에 따라 — 낮은 약하게, 밤은 강하게, 새벽·저녁은 그 사이
	var p := ViewParams.load_default()
	assert_true(p.mood_enabled, "화면 분위기 켜짐")
	assert_eq([ViewParams.clock_hour("14:20") > 14.3 and ViewParams.clock_hour("14:20") < 14.4, ViewParams.clock_hour("03:05") < 3.1, ViewParams.clock_hour("")], [true, true, 12.0], "시각 읽기 (없으면 낮 12시)")
	assert_eq([p.night_factor(14.3), p.night_factor(3.0), p.night_factor(23.5)], [0.0, 1.0, 1.0], "낮 0 · 밤 1")
	var dusk := p.night_factor(18.5)
	assert_true(dusk > 0.2 and dusk < 0.8, "저녁은 그 사이 (%.2f)" % dusk)
	var day := p.mood_at(14.3)
	var night := p.mood_at(3.0)
	assert_true(float(day.dark) > 0.85 and float(day.desat) < 0.3, "낮은 약하게 (밝기 %.2f)" % float(day.dark))
	assert_true(float(night.dark) < 0.8 and float(night.vignette) > float(day.vignette), "밤은 어둡고 가장자리가 더 어둡다")
	# 모든 시나리오에 시각이 있다
	for path: String in DirAccess.get_files_at("res://data/scenarios"):
		if path.ends_with(".json"):
			var d: Dictionary = JsonData.load_file("res://data/scenarios/" + path)
			assert_true(str(d.get("clock", "")).contains(":"), "%s 시각(clock)" % path)
