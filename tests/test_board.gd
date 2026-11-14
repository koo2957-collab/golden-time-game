extends TestSuite
## P10-1: 무전 기록 패널(최신 우선·긴급 고정줄)과 전술상황판(무전 보고만 — KnowledgeBoard)


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	open_all_doors(sim)
	return sim


func _quiet(sim: SimWorld) -> void:
	sim.step_ticks(1)
	for i in 1200:
		if not sim.command.radio.busy():
			return
		sim.step_ticks(1)


func test_radio_log_newest_first_and_filters() -> void:
	var sim := _sim()
	var panel := RadioLogPanel.new()
	panel.setup(sim)
	sim.command.radio.send(Radio.Priority.TACTICS, "진압1 1조", CommandSystem.COMMANDER, "첫째 보고.", sim.clock.tick)
	_quiet(sim)
	sim.command.radio.send(Radio.Priority.SAFETY, "진압1 1조", CommandSystem.COMMANDER, "둘째 보고.", sim.clock.tick)
	_quiet(sim)
	sim.command.radio.send(Radio.Priority.TACTICS, CommandSystem.COMMANDER, "진압1", "셋째 지시.", sim.clock.tick)
	_quiet(sim)
	panel.collect()
	var rows := panel.visible_entries()
	assert_true(rows.size() >= 3, "무전 3건 (%d)" % rows.size())
	assert_true(str(rows[0].text).contains("셋째 지시"), "최신이 맨 위: %s" % rows[0].text)
	assert_true(str(rows[1].text).contains("둘째 보고"), "그다음")
	assert_eq(rows[1].color, RadioLogPanel.COLORS[Radio.Priority.SAFETY], "대원 안전은 빨강")
	assert_eq(rows[0].crew, -1, "지휘관 지시는 조가 없음")
	assert_true(int(rows[1].crew) >= 0, "조 보고는 누르면 그 조로 이동")
	panel.set_filter("긴급")
	assert_true(panel.visible_entries().all(func(e: Dictionary) -> bool: return bool(e.urgent)), "긴급 필터")
	panel.set_filter("내 지시")
	assert_true(panel.visible_entries().size() >= 1 and panel.visible_entries().all(func(e: Dictionary) -> bool: return bool(e.mine)), "내 지시 필터")
	panel.free()


func test_radio_log_keeps_200() -> void:
	var sim := _sim()
	var panel := RadioLogPanel.new()
	panel.setup(sim)
	for i in 230:
		var m := Radio.Message.new()
		m.sender = "진압1 1조"
		m.receiver = CommandSystem.COMMANDER
		m.body = "보고 %d" % i
		m.end_tick = i
		sim.command.radio.history.append(m)
	panel.collect()
	assert_eq(panel.entries.size(), RadioLogPanel.MAX_ROWS, "최대 200건")
	assert_true(str(panel.visible_entries()[0].text).contains("보고 229"), "오래된 것부터 지운다")
	panel.free()


func test_pinned_lines_clear_when_resolved() -> void:
	var sim := _sim()
	var panel := RadioLogPanel.new()
	panel.setup(sim)
	assert_true(panel.pinned_lines().is_empty(), "처음에는 없음")
	sim.command.safety.par_no_response.append(0)
	var c := sim.units.get_crew(1)
	for ff in c.members():
		ff.level = 1
		ff.pos = Vector2(13.5, 15.5)
		ff.air_alarm_logged = true
	var lines := panel.pinned_lines()
	assert_eq(lines.size(), 2, "최대 2줄 (%s)" % [lines])
	assert_true(lines[0].contains("무응답"), "무응답 고정줄")
	assert_true(lines[1].contains("잔압 경보"), "잔압 경보 고정줄")
	sim.command.safety.par_no_response.clear()
	for ff in c.members():
		ff.air_alarm_logged = false
	assert_true(panel.pinned_lines().is_empty(), "해결되면 사라진다")
	panel.free()


func test_board_draws_only_reported_fire() -> void:
	var sim := _sim()
	var map := BoardMap.new()
	map.setup(sim)
	var living := sim.fire.compartment_at(1, 13, 15)
	# 실제로 불이 있어도 보고가 없으면 그리지 않는다
	sim.step_ticks(roundi(120.0 / SimClock.TICK_DT))
	assert_true(map.fire_rooms(1).is_empty(), "보고 전에는 화점 없음")
	assert_true(sim.knowledge.fires.is_empty(), "KnowledgeBoard에도 없음")
	sim.events.add(sim.clock.tick, "fire_found", {"crew": "진압1 1조", "crew_id": 0, "room": living.display_name(),
		"room_cell": [13, 15, 1], "has_hose": false, "action": "attack", "target": [13, 15, 1]})
	sim.step_ticks(1)
	assert_true(map.fire_rooms(1).is_empty(), "무전이 전달되기 전에는 아직 없음")
	_quiet(sim)
	assert_eq(map.fire_rooms(1), [living.index] as Array[int], "무전으로 보고되면 그린다")
	assert_true(sim.knowledge.crews.has(0), "보고한 조의 마지막 위치")
	map.free()


# --- 화이트보드 (2026-11-14): 모양·기호는 data/ui/board_style.json ---

func test_board_style_values_have_source() -> void:
	var data: Dictionary = JsonData.load_file(BoardStyle.PATH)
	for key: String in data:
		var entry: Variant = data[key]
		if entry is Dictionary:
			assert_true((entry as Dictionary).has("source"), "%s에 source" % key)
	var st := BoardStyle.from_file(BoardStyle.PATH)
	assert_true(st.color("board").get_luminance() > 0.9, "판은 흰색 (화이트보드)")
	assert_true(st.color("ink").get_luminance() < 0.2, "선은 먹색")
	assert_eq(st.stale_s, 60.0, "오래된 보고 기준 60초")
	assert_eq(st.vehicle_label("펌프차"), "펌프", "차량 자석 짧은 이름")
	assert_eq(st.vehicle_label("없는차"), "없는차", "표에 없으면 차종 그대로")
	# 판 모양 (사용자 결정): 화면의 85%, 16:9, 도면 60% / 정보 40%, 마커 손글씨
	assert_eq(st.board_screen_ratio, 0.85, "화면의 85%")
	assert_true(absf(st.board_aspect - 16.0 / 9.0) < 0.01, "가로형 16:9")
	assert_eq(st.map_ratio, 0.6, "도면 60%")
	assert_eq(st.info_rows.size(), 3, "정보 칸 세 줄")
	assert_true(st.marker_font() is FontFile and st.marker_bold() is FontFile, "마커 글꼴 파일을 읽는다")
	assert_true(st.marker_font() != ThemeDB.fallback_font, "기본 글꼴이 아니다")
	assert_true(FileAccess.file_exists("res://art/fonts/Gaegu-OFL.txt"), "글꼴 사용 조건 문서")


func test_board_unseen_cells_are_unknown() -> void:
	var sim := _sim()
	var map := BoardMap.new()
	map.setup(sim)
	sim.perception.enabled = true
	sim.plan.known = false
	var idx := sim.fire.grid.index(1, 13, 15)
	sim.perception.seen_tick[idx] = -1
	assert_eq(map.known_cell(1, 13, 15), -1, "대원이 안 본 칸은 모른다")
	assert_eq(map.known_cell(1, -1, 0), -1, "지도 밖")
	sim.perception.seen_tick[idx] = 0
	assert_eq(map.known_cell(1, 13, 15), sim.building.cell(1, 13, 15), "본 칸은 실제 구조")
	sim.perception.seen_tick[idx] = -1
	sim.plan.known = true
	assert_eq(map.known_cell(1, 13, 15), sim.plan.plan_cell(1, 13, 15), "도면을 얻으면 도면")
	map.free()


func test_board_search_marks() -> void:
	var sim := _sim()
	var map := BoardMap.new()
	map.setup(sim)
	sim.perception.enabled = false
	assert_true(map.search_ordered_rooms(1).is_empty(), "검색 지시 전에는 사선 없음")
	var living := sim.fire.compartment_at(1, 13, 15)
	var one := TacticalSystem.Task.new()
	one.crew_id = 0
	one.action = "search"
	one.room = living.index
	sim.tactical.tasks.append(one)
	assert_eq(map.search_ordered_rooms(1), [living.index] as Array[int], "방 하나 검색 지시 → 그 방에 사선")
	assert_true(map.search_ordered_rooms(2).is_empty(), "다른 층에는 없음")
	sim.knowledge.searched[living.index] = sim.clock.tick
	assert_true(map.search_ordered_rooms(1).is_empty(), "검색 완료 보고가 오면 사선 대신 ✕")
	# 층 검색: 그 층에서 구조를 아는 방 모두 (완료 보고된 방은 뺀다)
	sim.tactical.tasks.clear()
	var floor_task := TacticalSystem.Task.new()
	floor_task.crew_id = 0
	floor_task.action = "search"
	floor_task.floor = 1
	floor_task.floor_action = "search_floor"
	sim.tactical.tasks.append(floor_task)
	var rooms := map.search_ordered_rooms(1)
	assert_true(rooms.size() >= 2, "층 검색 → 여러 방 (%d)" % rooms.size())
	assert_true(not rooms.has(living.index), "완료 보고된 방은 빠진다")
	assert_true(rooms.all(func(i: int) -> bool: return sim.fire.comps[i].level == 1), "그 층 방만")
	map.free()


func test_board_crew_magnets() -> void:
	var sim := _sim()
	var map := BoardMap.new()
	map.setup(sim)
	map.size = Vector2(800, 600)
	map.level = -1
	# 차량 자석이 조 자석을 밀어내지 않게 치워 두고 본다 (차량은 아래에서 따로)
	for v in sim.units.vehicles:
		v.away = true
	var a := sim.units.get_crew(0)
	var b := sim.units.get_crew(1)
	for c: Crew in [a, b]:
		for ff in c.members():
			ff.aboard = false
			ff.level = 1
			ff.pos = Vector2(6.5, 30.5)
	assert_eq(map.crew_label(a), "%s-%d" % [sim.units.squads[a.squad_id].name, a.number], "자석 이름은 출동대-조 번호")
	var magnets := map.crew_magnets(map.draw_level())
	assert_true(magnets.has(a.id) and magnets.has(b.id), "밖에 있는 조는 자석이 있다")
	var ra: Rect2 = magnets[a.id]
	var rb: Rect2 = magnets[b.id]
	assert_true(ra.has_point(map.to_px(Vector2(6.5, 30.5))), "자석은 조 자리에")
	assert_true(not ra.intersects(rb), "같은 자리의 자석은 겹치지 않게 비킨다")
	assert_eq(map.crew_at(ra.get_center()), a.id, "자석을 누르면 그 조")
	assert_eq(map.crew_at(rb.get_center()), b.id, "비켜 놓인 자석도")
	assert_eq(map.crew_at(Vector2(790, 10)), -1, "빈 곳")
	sim.command.safety.roles[a.id] = SafetySystem.Role.RIT
	assert_true(map.crew_label(a).ends_with(" RIT"), "RIT는 이름 뒤에 표시")
	# 건물 안인데 보고가 없으면 자석이 없다 (보고된 것만)
	for ff in a.members():
		ff.pos = Vector2(13.5, 15.5)
	if sim.command.interior.crew_inside(a.id):
		sim.knowledge.crews.erase(a.id)
		assert_true(not map.crew_magnets(1).has(a.id), "안에 있고 보고가 없으면 판에 없다")
	if not sim.units.vehicles.is_empty():
		var v: Vehicle = sim.units.vehicles[0]
		v.away = false
		assert_true(map.vehicle_magnets().has(v.id), "현장에 있는 차량은 자석")
		assert_eq(map.vehicle_text(v), "%s %s" % [sim.units.squads[v.squad_id].name, map.style.vehicle_label(v.type)], "차량 자석 글")
		v.away = true
		assert_true(not map.vehicle_magnets().has(v.id), "떠난 차량은 없음")
	map.free()


func test_board_legend_matches_view() -> void:
	var sim := _sim()
	var map := BoardMap.new()
	map.setup(sim)
	map.level = -1
	var outside := map.legend_items()
	assert_true(outside.has("vehicle") and outside.has("hydrant") and not outside.has("fire"), "외부 판 범례")
	map.level = 1
	var inside := map.legend_items()
	assert_true(inside.has("fire") and inside.has("searched") and inside.has("search_ordered") and not inside.has("vehicle"), "내부 층 범례")
	for id in outside + inside:
		assert_true(BoardMap.LEGEND.has(id), "범례 글: %s" % id)
	assert_eq(map.age_text(sim.clock.tick), "0초 전", "방금 보고")
	assert_eq(map.age_text(-1), "", "보고 없음")
	map.free()
