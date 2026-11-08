extends TestSuite
## R13: 지휘권 이양 → 지휘대장(SOP 112), 단위지휘관 대리 처리, 비상용승강기(SOP 222), 스테이지 2-2

const HR := "res://data/scenarios/sop222_1_highrise_25f.json"


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(HR)
	return sim


func test_scenario_loads() -> void:
	var sim := _sim()
	assert_true(sim != null, "불러옴")
	assert_eq(sim.building.levels().size(), 25, "25층")
	assert_true(sim.elevator.available(), "비상용승강기")
	assert_eq(ScenarioLoader.validate(HR), PackedStringArray(), "검증")


func test_command_unit_arrives_and_transfer() -> void:
	var sim := _sim()
	sim.transfer.arrive_tick = 20
	sim.step_ticks(21)
	assert_true(sim.transfer.arrived(), "지휘대 도착")
	assert_eq(sim.events.of_type("command_unit_arrived").size(), 1, "도착 무전")
	var truth := sim.transfer.options()
	var answers := {}
	for k in CommandTransfer.ITEMS:
		answers[k] = truth[k][0]
	answers["strategy"] = truth["strategy"][1]  # 하나는 틀리게
	sim.issue(CommandOrder.make("transfer", [], 0, Vector3i.ZERO, answers))
	sim.step_ticks(2)
	assert_true(sim.transfer.transferred(), "이양")
	assert_true(absf(sim.transfer.accuracy - 5.0 / 6.0) < 0.01, "브리핑 정확도 5/6 (%.2f)" % sim.transfer.accuracy)
	assert_eq(sim.command.commander_title, "지휘대장", "지휘대장으로 계속")
	assert_true(sim.plan.known, "상황실 도면 수신 (SOP 112)")
	var rule: Array = Evaluator.evaluate(sim).rules.filter(func(r: Dictionary) -> bool: return r.id == "command.transfer")
	assert_true(not rule.is_empty() and rule[0].applicable and str(rule[0].detail).contains("전략"), "판정: 틀린 항목 (%s)" % [rule])


func test_delegated_cards_after_transfer() -> void:
	var sim := _sim()
	sim.command.org.divisions.clear()
	sim.command.org.set_division("A면", 0, [0, 1] as Array[int])
	sim.step_ticks(50)
	sim.transfer.arrive_tick = sim.clock.tick
	sim.step_ticks(1)
	sim.transfer.transfer({}, sim.clock.tick)
	assert_true(sim.transfer.delegates(0) != "", "진압1은 단위대 소속 → 단위지휘관 대리")
	sim.cards.queue.clear()
	sim.events.add(sim.clock.tick, "tactical_halt", {"crew": "진압1 1조", "crew_id": 0, "kind": "locked", "door": [27, 14, 18],
		"door_name": "18층 문", "reason": "", "safety": false, "action": "attack", "target": [10, 16, 18]})
	sim.step_ticks(2)
	var lg := sim.cards.log.filter(func(l: Dictionary) -> bool: return l.result == "delegated" and l.id == "DOOR-LOCKED-01")
	assert_eq(lg.size(), 1, "잠긴 문 카드를 단위지휘관이 처리")
	assert_eq(lg[0].grade if not lg.is_empty() else "", "최선", "대리 처리는 최선")
	assert_true(not sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.crew_id == 0), "지휘대장에게는 묻지 않는다")


func test_elevator_rule() -> void:
	var sim := _sim()
	sim.step_ticks(10)
	assert_eq(sim.elevator.fire_floor(), 18, "화재층 18층")
	var c := sim.units.get_crew(0)
	var at := Vector2(sim.elevator.cell) + Vector2(0.5, 0.5)
	for m in c.members():
		m.pos = at
		m.prev_pos = at
		m.level = 1
		m.prev_level = 1
	assert_true(sim.elevator.ride(0, 16, sim.clock.tick), "16층(화재층 -2)까지")
	assert_eq(sim.elevator.violations, 0, "규칙 안")
	sim.step_ticks(roundi(60.0 / SimClock.TICK_DT))
	assert_eq(c.leader.level, 16, "16층 도착")
	assert_true(not c.leader.aboard, "내림")
	# 다른 조가 17층까지 타면 위반
	var c2 := sim.units.get_crew(2)
	for m in c2.members():
		m.pos = at
		m.prev_pos = at
		m.level = 1
		m.prev_level = 1
	sim.elevator.ride(2, 17, sim.clock.tick)
	assert_eq(sim.elevator.violations, 1, "화재층 2개층 아래보다 높이 = 위반 (SOP 222)")
	assert_eq(sim.events.of_type("elevator_too_high").size(), 1, "대원 안전 무전")
