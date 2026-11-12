extends TestSuite
## R17 인형집 단면 보기 — 층 쌓기·벽 모양·계단·아래층 클릭 (화면 계산 FloorStack)

const APT := "res://data/buildings/apartment_15f.json"
const SUPERTALL := "res://data/buildings/supertall_52f.json"
const BASEMENT := "res://data/buildings/basement_karaoke.json"


## 예전 쌓기 방식(stack)으로 — 아래 쌓기·벽 모양 점검은 이 방식 기준
func _stack(path: String) -> FloorStack:
	var p := ViewParams.load_default()
	p.stack_mode = "stack"
	return FloorStack.new(BuildingData.from_file(path), p)


## 2026-11-12 비켜 놓기(stagger, 기본): 고른 층 + 바로 위층(맨 위층이면 바로 아래층), 위층은 건물 뒤(북)로 비켜 놓는다
func test_stagger_shows_floor_and_partner() -> void:
	var s := FloorStack.new(BuildingData.from_file(APT), ViewParams.load_default())
	assert_true(s.staggered(), "기본은 비켜 놓기")
	assert_eq([s.visible_levels(12), s.above_levels(12)], [[12] as Array[int], [13] as Array[int]], "12층: 12층 + 위로 13층")
	var top := s.order[-1]
	assert_eq([s.visible_levels(top), s.above_levels(top)], [[top, top - 1] as Array[int], [] as Array[int]], "맨 위층: 바로 아래층과 함께")
	var up := -s.offset_vec(1)
	assert_true(up.x > 0.0 and up.y < 0.0, "위층은 화면 오른쪽 위(건물 뒤 북쪽)로 비켜 있다 %s" % up)
	assert_true(-up.y > s.params.stagger_floor_px, "층 높이보다 더 위로")


func test_view_params_loaded() -> void:
	var p := ViewParams.load_default()
	assert_eq(p.floor_height_px, 220.0, "층 간격 220px (2026-11-11 사용자 결정 F01: 건물을 더 높게)")
	assert_eq([p.visible_floors_above, p.above_alpha], [2, 0.25], "위 2개 층, 반투명 0.25")
	assert_eq(p.visible_floors_below, 2, "아래 2개 층")
	assert_eq(p.below_modulate, [0.75, 0.55] as Array[float], "아래 층 밝기")
	assert_eq(p.front_wall, "open", "앞벽은 없음 — 인형집 (2026-11-12 결정)")
	assert_eq([p.front_wall_alpha, p.inner_wall_m, p.stack_mode, p.stagger_back_ratio, p.stagger_floor_px], [0.15, 2.4, "stagger", 0.3, 260.0], "앞벽 15%, 실내 벽 천장까지(F04), 비켜 놓기 B(뒤로 0.3 + 위로 260px)")
	assert_true(p.inner_wall_alpha_bottom > p.inner_wall_alpha_top and p.inner_wall_cap_alpha > 0.5, "실내 벽은 아래 진하게·위로 옅게, 흰 윗면 테두리 (2026-11-12)")
	assert_true(p.ghost_inner_wall_m < p.inner_wall_m, "위·아래 층 실내 벽은 낮게")
	assert_eq(p.wall_cut_m, 0.2, "잘린 벽 20cm")
	# 연기층 그림 (2026-11-12 사용자 결정: Kenney 연기 덩어리 구름, 윗면 옅게·앞면 진하게, 높이 눈금)
	assert_eq([p.smoke_top_alpha < p.smoke_front_alpha, p.smoke_max_puffs > 0, p.smoke_row_m, p.smoke_max_rows], [true, true, 0.4, 6], "연기 윗면은 앞면보다 옅게, 덩어리 상한, 0.4m마다 한 줄씩 겹쳐 쌓기(최대 6줄)")
	assert_eq([p.smoke_outline_below_m, p.smoke_outline_density], [1.8, 0.4], "연기층 아랫면이 1.8m 아래·짙기 0.4 이상이면 그 방 사람은 테두리로")
	assert_true(p.smoke_plume_alpha > 0.0 and p.smoke_spill_alpha > 0.0 and p.smoke_sheet_flow_mps > 0.0, "연기 기둥·넘침 그림 진하기와 퍼지는 속도")
	# 연기 진하기 하나 (2026-11-12): 커튼 천장 쪽과 윗면이 같은 값, 커튼은 아래로 갈수록 옅게
	assert_true(p.smoke_max_opacity > 0.5 and p.smoke_max_opacity < 1.0 and p.smoke_opacity_k > 0.0, "진하기 상한·두께 계수")
	assert_true(p.smoke_curtain_low > 0.0 and p.smoke_curtain_low < 1.0, "커튼 아래쪽은 천장 쪽보다 옅게")


func test_apartment_12f_shows_10_to_14() -> void:
	# 기획안 9-4·P2-1 (2026-11-10 결정 ②): 초점 층 위·아래 각 2개 층
	var s := _stack(APT)
	var shown := s.visible_levels(12)
	assert_eq(shown, [12, 11, 10] as Array[int], "12층 아래로 11·10층")
	assert_eq(s.above_levels(12), [13, 14] as Array[int], "위로 13·14층")
	assert_eq(s.above_levels(15), [] as Array[int], "꼭대기 층은 위층 없음")
	assert_eq(s.above_levels(14), [15] as Array[int], "14층 위는 15층만")
	for lv in [15, 9]:
		assert_true(not shown.has(lv) and not s.above_levels(12).has(lv), "%d층은 보이지 않음" % lv)
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
	assert_eq(st.visible_levels(4), [4, 3, 2] as Array[int], "30층은 30·29·28층")
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
	assert_eq(s.pick_level(12, below2, proj), 10, "두 층 아래(10층)")
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
