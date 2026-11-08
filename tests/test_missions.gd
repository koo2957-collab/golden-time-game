extends TestSuite
## R7b: 층 단위 임무·임무 조건·화점 발견 (기획안 9-1, SOP 214-2.1, 210-3.5, 201-3.7)


func _sim(level := "입문", on := false) -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	sim.tactical.set_level(level)
	sim.command.interior.enabled = on
	return sim


func _put(sim: SimWorld, crew_id: int, at: Vector2, level := 1) -> Crew:
	var c := sim.units.get_crew(crew_id)
	for i in c.members().size():
		var ff := c.members()[i]
		ff.pos = at + Vector2(i * 0.6, 0)
		ff.prev_pos = ff.pos
		ff.level = level
		ff.prev_level = level
	sim.command.entry_allowed[c.squad_id] = true
	sim.perception.update(sim.clock.tick)
	return c


## 대원이 본 적 없는 방 (2층부터 찾는다)
func _unseen_room(sim: SimWorld) -> Compartment:
	for lv in [2, 1]:
		for room in sim.fire.comps:
			if room.level == lv and not room.cells.is_empty() and sim.perception.room_seen[room.index] == 0:
				return room
	return null


func _step_until(sim: SimWorld, cond: Callable, max_s := 120.0) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		sim.step_ticks(1)
		if cond.call():
			return true
	return false


func test_unseen_room_needs_floor_mission() -> void:
	var sim := _sim("입문", true)
	sim.perception.update(0)
	var room := _unseen_room(sim)
	assert_true(room != null, "본 적 없는 방이 있다")
	var cell: Vector2i = room.cells[0]
	sim.issue(TacticalCommand.make("search", [2] as Array[int], Vector3i(cell.x, cell.y, room.level)))
	sim.step_ticks(2)
	var e := sim.events.of_type("order_unseen")
	assert_eq(e.size(), 1, "본 적 없는 방 단위 임무는 거절")
	assert_true(not e.is_empty() and str(e[0].reason).contains("층 단위"), "층 단위로 맡기라는 안내")
	sim.command.entry_allowed[sim.units.get_crew(2).squad_id] = true
	sim.issue(TacticalCommand.make("search_floor", [2] as Array[int], Vector3i(0, 0, room.level)))
	sim.step_ticks(2)
	var starts := sim.events.of_type("tactical_start")
	assert_true(not starts.is_empty() and starts[-1].get("floor", "") == sim.building.floor_name(room.level), "층 검색 시작 (%s)" % [starts])
	sim.command.interior.plan_known = true
	assert_true(sim.command.interior.room_known(Vector3i(cell.x, cell.y, room.level)), "도면이 있으면 방 단위 가능 (R8)")


func test_floor_search_goes_room_by_room() -> void:
	var sim := _sim("입문")
	# 구조1 1조를 2층 방 하나에 둔다
	var start: Compartment = null
	for room in sim.fire.comps:
		if room.level == 2 and room.cells.size() >= 4:
			start = room
			break
	var cell: Vector2i = start.cells[start.cells.size() / 2]
	_put(sim, 2, Vector2(cell) + Vector2(0.5, 0.5), 2)
	sim.issue(TacticalCommand.make("search_floor", [2] as Array[int], Vector3i(0, 0, 2)))
	var crew_done := func() -> int:
		return sim.events.of_type("search_done").filter(func(x: Dictionary) -> bool: return x.crew == "구조1 1조").size()
	_step_until(sim, func() -> bool: return crew_done.call() >= 2 or (sim.rescue.task_of_crew(2) != null and not sim.rescue.task_of_crew(2) is RescueSystem.SearchTask), 400.0)
	assert_true(crew_done.call() >= 2 or not sim.events.of_type("victim_found").is_empty(), "방을 차례로 검색 (검색 완료 %d)" % crew_done.call())
	assert_true(not sim.events.of_type("tactical_next").is_empty() or crew_done.call() < 2, "다음 방으로 이어 감")


func test_floor_attack_finds_burning_room() -> void:
	var sim := _sim("입문")
	_put(sim, 0, Vector2(14.5, 22.5))
	sim.step_ticks(20)  # 발화 뒤
	sim.issue(TacticalCommand.make("attack_floor", [0] as Array[int], Vector3i(0, 0, 1)))
	sim.step_ticks(2)
	var fire_room := sim.fire.compartment_at(1, 12, 17)
	var starts := sim.events.of_type("tactical_start")
	assert_true(not starts.is_empty() and starts[-1].room == fire_room.display_name(), "1층에서 타는 방을 찾아 진압 (%s)" % [starts])
	sim.issue(TacticalCommand.make("attack_floor", [1] as Array[int], Vector3i(0, 0, 2)))
	sim.step_ticks(2)
	var halts := sim.events.of_type("tactical_halt").filter(func(x: Dictionary) -> bool: return x.kind == "no_fire")
	assert_eq(halts.size(), 1, "불이 없는 층은 멈추고 지시를 기다림")


func test_victim_condition_answers_card() -> void:
	var sim := _sim("중급")
	sim.issue(CommandOrder.make("mission_conditions", [], 0, Vector3i.ZERO, {"crews": [2], "on_victim": "rescue"}))
	sim.step_ticks(1)
	assert_true(sim.tactical.condition_text(2).contains("즉시 구조"), "조건 문장 (%s)" % sim.tactical.condition_text(2))
	sim.events.add(sim.clock.tick, "tactical_halt", {"crew": "구조1 1조", "crew_id": 2, "kind": "victim", "victim": 1, "victim_name": "아이(7)",
		"state": "의식 있음", "reason": "", "safety": false})
	sim.step_ticks(2)
	assert_true(not sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.id == "VICTIM-FOUND-01"), "카드 없이 처리")
	var lg := sim.cards.log.filter(func(l: Dictionary) -> bool: return l.id == "VICTIM-FOUND-01")
	assert_eq(lg.size(), 1, "결정 기록")
	assert_eq([lg[0].result, lg[0].grade], ["condition", "최선"], "임무 조건 · 최선")
	# 위치 보고 후 대기는 SOP 214-2.1(즉시 구조)과 다르다 → 오답
	sim.issue(CommandOrder.make("mission_conditions", [], 0, Vector3i.ZERO, {"crews": [3], "on_victim": "report"}))
	sim.step_ticks(1)
	sim.events.add(sim.clock.tick, "tactical_halt", {"crew": "구조1 2조", "crew_id": 3, "kind": "victim", "victim": 0, "victim_name": "노인(78)",
		"state": "의식 있음", "reason": "", "safety": false})
	sim.step_ticks(2)
	lg = sim.cards.log.filter(func(l: Dictionary) -> bool: return l.id == "VICTIM-FOUND-01")
	assert_eq(lg[-1].grade, "오답", "위치 보고 후 대기는 오답")


func test_fire_found_reported_and_card() -> void:
	var sim := _sim("중급")
	_put(sim, 2, Vector2(14.5, 17.5))
	sim.issue(TacticalCommand.make("search", [2] as Array[int], Vector3i(14, 17, 1)))
	var found := _step_until(sim, func() -> bool: return not sim.events.of_type("fire_found").is_empty(), 30.0)
	assert_true(found, "검색 중 가까이에서 화점을 보면 보고")
	if not found:
		return
	var e: Dictionary = sim.events.of_type("fire_found")[0]
	assert_eq(e.crew_id, 2, "보고한 조")
	sim.step_ticks(2)
	var card := sim.cards.queue.filter(func(q: CardSystem.Card) -> bool: return q.id == "FIRE-FOUND-01")
	assert_eq(card.size(), 1, "화점 발견 카드")
	assert_eq(sim.events.of_type("fire_found").size(), 1, "같은 방은 한 번만")


func test_fire_condition_closes_door_and_resumes() -> void:
	var sim := _sim("중급")
	sim.issue(CommandOrder.make("mission_conditions", [], 0, Vector3i.ZERO, {"crews": [2], "on_fire": "close"}))
	sim.step_ticks(1)
	sim.events.add(sim.clock.tick, "fire_found", {"crew": "구조1 1조", "crew_id": 2, "room": sim.fire.compartment_at(1, 12, 17).display_name(),
		"room_cell": [12, 17, 1], "has_hose": false, "action": "search_floor", "target": [0, 0, 1]})
	sim.step_ticks(2)
	var lg := sim.cards.log.filter(func(l: Dictionary) -> bool: return l.id == "FIRE-FOUND-01")
	assert_eq(lg.size(), 1, "카드 없이 처리")
	assert_eq([lg[0].result, lg[0].grade], ["condition", "최선"], "문 닫고 검색 계속 = 최선")
	# 수관이 없는 조에게 '즉시 진압' 조건은 맞는 선택지가 없어 카드로 묻는다
	sim.issue(CommandOrder.make("mission_conditions", [], 0, Vector3i.ZERO, {"crews": [3], "on_fire": "attack"}))
	sim.step_ticks(1)
	sim.cards.queue.clear()  # 도착 카드 등으로 대기열이 차 있지 않게
	sim.events.add(sim.clock.tick, "fire_found", {"crew": "구조1 2조", "crew_id": 3, "room": "1층 거실",
		"room_cell": [12, 17, 1], "has_hose": false, "action": "search", "target": [12, 17, 1]})
	sim.step_ticks(2)
	assert_true(sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.id == "FIRE-FOUND-01" and q.crew_id == 3), "맞는 행동이 없으면 묻는다")


func test_withdraw_air_condition() -> void:
	var sim := _sim("중급")
	var c := _put(sim, 0, Vector2(11.5, 16.5))
	sim.issue(CommandOrder.make("mission_conditions", [], 0, Vector3i.ZERO, {"crews": [0], "withdraw_air": "half"}))
	sim.step_ticks(1)
	for ff in c.members():
		ff.air_l = ff.air_capacity * 0.45
	sim.step_ticks(2)
	var w := sim.events.of_type("mission_withdraw")
	assert_eq(w.size(), 1, "절반 아래로 내려가면 질문 없이 철수")
	assert_true(not w.is_empty() and int(w[0].percent) <= 50, "공기 % 기록")
	sim.step_ticks(20)
	assert_eq(sim.events.of_type("mission_withdraw").size(), 1, "한 번만")
	# 경보 카드도 조건대로 바로 철수 (201-3.7)
	assert_eq(sim.tactical.condition_effect(0, "AIR-ALARM-01"), "withdraw", "경보에는 바로 철수")


func test_floor_order_text() -> void:
	var sim := _sim()
	assert_eq(sim.command.interior.order_text(TacticalCommand.make("search_floor", [2] as Array[int], Vector3i(0, 0, 2))), "2층 검색하라.", "층 검색 무전")
	assert_eq(sim.command.interior.ack_text(TacticalCommand.make("attack_floor", [0] as Array[int], Vector3i(0, 0, 1))), "1층 진압하겠음.", "층 진압 복명복창")
