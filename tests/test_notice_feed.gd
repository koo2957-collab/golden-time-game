extends TestSuite
## 위쪽 알림 칩 (2026-11-27 사용자 결정): 종류 아이콘·색, 그 자리를 알면 누르면 이동·지도 표시, 8초 뒤 사라짐


func _feed() -> Array:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var feed := NoticeFeed.new()
	feed.setup(sim)
	return [sim, feed]


func test_category_by_type() -> void:
	var r := _feed()
	var feed: NoticeFeed = r[1]
	assert_eq([feed.category_of("air_alarm"), feed.category_of("victim_found"), feed.category_of("hydrant_connected"),
		feed.category_of("statement"), feed.category_of("clue_found"), feed.category_of("door_opened")],
		["danger", "victim", "vehicle", "witness", "clue", "info"], "사건 종류마다 알림 종류")
	assert_eq([feed.category_of("radio", "대원 안전"), feed.category_of("radio", "구조대상자")], ["danger", "victim"], "무전은 우선순위로")
	assert_true(feed.color_of("danger") != feed.color_of("vehicle"), "종류마다 다른 색")
	feed.free()


func test_place_jump_and_expire() -> void:
	var r := _feed()
	var sim: SimWorld = r[0]
	var feed: NoticeFeed = r[1]
	var placed: Array = []
	var jumped: Array = []
	feed.placed.connect(func(pos: Vector2, lv: int, _c: Color, text: String, secs: float) -> void: placed.append([pos, lv, text, secs]))
	feed.jump.connect(func(pos: Vector2, lv: int) -> void: jumped.append([pos, lv]))
	# 관계인 진술: 그 관계인 자리 + 답을 말풍선으로 (더 오래)
	var w = sim.command.survey.witnesses[0]
	feed.push_event({"type": "statement", "time_s": 65, "witness": w.label(), "question": "안에 사람이 있습니까?", "text": "할머니가 안에 계세요"})
	assert_eq(placed.size(), 1, "자리를 아는 알림은 지도에 표시")
	assert_eq([placed[0][0], placed[0][2], placed[0][3]], [w.pos, "“할머니가 안에 계세요”", feed.bubble_s], "관계인 머리 위 말풍선에 답")
	feed.press(0)
	assert_eq(jumped, [[w.pos, sim.building.levels()[0]]], "칩을 누르면 그 자리로")
	# 자리를 모르는 알림: 지도 표시·이동 없음
	feed.push("둘러보기 끝", "clue")
	assert_eq([placed.size(), feed.items()[1].where.is_empty()], [1, true], "자리를 모르면 표시하지 않는다")
	feed.press(1)
	assert_eq(jumped.size(), 1, "자리를 모르면 눌러도 이동하지 않는다")
	# 차량
	var v = sim.units.vehicles[0]
	assert_eq(feed.where_of({"vehicle": v.display_name(sim.units.squads[v.squad_id].name)}).get("pos"), v.pos, "차량 이름 → 차 자리")
	# 대원 안전 무전: 보낸 조 자리
	var c0: Crew = sim.units.crews[0]
	assert_eq(feed.where_of({"type": "radio", "from": sim.units.crew_name(c0)}).get("pos"), c0.leader.pos, "무전은 보낸 조 자리")
	# 시간이 지나면 사라진다 (실제 시간 8초), 최대 개수
	for i in 6:
		feed.push("알림 %d" % i)
	assert_eq(feed.items().size(), feed.max_n, "한꺼번에 max 개까지")
	feed.step(feed.seconds - 0.5)
	assert_true(feed.items().size() == feed.max_n and feed.get_child(feed.get_child_count() - 1).modulate.a < 1.0, "사라지기 전 옅어진다")
	feed.step(1.0)
	assert_eq([feed.items().size(), feed.feed_text()], [0, ""], "8초 뒤 사라진다")
	feed.free()
