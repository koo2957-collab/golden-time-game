extends TestSuite
## R17 인형집 단면 보기 — 층 쌓기·벽 모양·계단·아래층 클릭 (화면 계산 FloorStack)

const APT := "res://data/buildings/apartment_15f.json"
const SUPERTALL := "res://data/buildings/supertall_52f.json"
const BASEMENT := "res://data/buildings/basement_karaoke.json"


func _stack(path: String) -> FloorStack:
	return FloorStack.new(BuildingData.from_file(path), ViewParams.load_default())


func test_view_params_loaded() -> void:
	var p := ViewParams.load_default()
	assert_eq(p.floor_height_px, 143.0, "층 높이 143px (2.8m 실제 비율)")
	assert_eq(p.visible_floors_below, 2, "아래 2개 층")
	assert_eq(p.below_modulate, [0.75, 0.55] as Array[float], "아래 층 밝기")
	assert_eq(p.front_wall, "cut", "앞벽은 잘린 벽")
	assert_eq(p.wall_cut_m, 0.2, "잘린 벽 20cm")


func test_apartment_12f_shows_12_11_10_only() -> void:
	var s := _stack(APT)
	var shown := s.visible_levels(12)
	assert_eq(shown, [12, 11, 10] as Array[int], "12층을 고르면 12·11·10층만")
	for lv in [13, 14, 15]:
		assert_true(not shown.has(lv), "%d층은 보이지 않음" % lv)
		assert_eq(s.depth_of(12, lv), -1, "%d층 깊이 없음" % lv)
	assert_eq(s.depth_of(12, 11), 1, "11층은 한 층 아래")
	assert_eq(s.modulate_for(0), 1.0, "지금 층은 밝게")
	assert_eq(s.modulate_for(1), 0.75, "한 층 아래 0.75")
	assert_eq(s.modulate_for(2), 0.55, "두 층 아래 0.55")
	assert_eq(s.offset_px(2), 286.0, "두 층 아래는 286px 아래에")
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
	assert_eq(s.wall_kind(12, 8, 19), FloorStack.Wall.CUT, "남쪽 외벽은 앞벽 — 잘린 벽")
	assert_eq(s.wall_kind(12, 10, 19), FloorStack.Wall.CUT, "남쪽 창도 잘린 벽")
	assert_eq(s.wall_kind(12, 53, 10), FloorStack.Wall.CUT, "동쪽 외벽은 앞벽 — 잘린 벽")
	assert_eq(s.wall_kind(12, 53, 19), FloorStack.Wall.CUT, "남동 모서리는 잘린 벽")
	assert_eq(s.wall_kind(12, 6, 19), FloorStack.Wall.FULL, "남서 모서리 기둥은 건물 모양을 남김")
	assert_eq(s.wall_kind(12, 20, 12), FloorStack.Wall.CUT, "실내 벽은 잘린 벽")
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
