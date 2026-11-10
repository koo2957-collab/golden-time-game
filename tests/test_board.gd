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
