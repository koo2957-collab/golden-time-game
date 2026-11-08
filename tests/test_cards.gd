extends TestSuite
## R3: 질문 카드 엔진 (기획안 3-3, 7장, P7)


func _sim(level := "중급") -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	sim.tactical.set_level(level)
	return sim


## 진압1 1조를 현관 앞에 두고 거실 진압을 시킨다 (현관은 잠김 → 중급은 멈추고 카드)
func _attack_locked_door(sim: SimWorld) -> void:
	var c := sim.units.get_crew(0)
	for i in c.members().size():
		c.members()[i].pos = Vector2(13.5 + i, 22.5)
		c.members()[i].prev_pos = c.members()[i].pos
	sim.command.entry_allowed[c.squad_id] = true
	sim.issue(TacticalCommand.make("attack", [0] as Array[int], Vector3i(12, 16, 1)))


func _step_until_card(sim: SimWorld, max_s := 60.0) -> CardSystem.Card:
	for i in roundi(max_s / SimClock.TICK_DT):
		sim.step_ticks(1)
		if sim.cards.active():
			return sim.cards.active()
	return null


func test_cards_load() -> void:
	var data: Dictionary = JsonData.load_file("res://data/cards/cards.json")
	assert_true(data.cards.size() >= 6, "카드 %d장" % data.cards.size())
	for spec: Dictionary in data.cards:
		var grades := (spec.options as Array).map(func(o: Dictionary) -> String: return o.grade)
		assert_true("최선" in grades, "%s 최선 선택지" % spec.id)
		assert_true(not (spec.get("sop_ref", []) as Array).is_empty(), "%s SOP 근거" % spec.id)


func test_locked_door_card_and_answer() -> void:
	var sim := _sim()
	_attack_locked_door(sim)
	var c := _step_until_card(sim)
	assert_true(c != null and c.id == "DOOR-LOCKED-01", "잠긴 문 카드")
	assert_true(c.text.contains("잠겨"), "문구 채움 (%s)" % c.text)
	assert_eq(sim.events.of_type("card_asked").filter(func(e: Dictionary) -> bool: return e.title == "잠긴 문").size(), 1, "질문 기록")
	# 최선 선택지(강제 개방)를 고르면 문 파괴 작업이 시작된다
	var best := -1
	for i in c.options.size():
		if c.options[i].grade == "최선":
			best = i
	sim.issue(CommandOrder.make("card_answer", [], best, Vector3i.ZERO, {"uid": c.uid}))
	sim.step_ticks(30)
	assert_true(not sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.id == "DOOR-LOCKED-01"), "답하면 사라짐")
	assert_eq(sim.cards.log.filter(func(l: Dictionary) -> bool: return l.id == "DOOR-LOCKED-01")[0].grade, "최선", "결정 기록")
	assert_true(sim.doors.task_of(sim.fire.opening_at(Vector3i(13, 20, 1))) != null, "문 파괴 시작 (결과는 시뮬레이션이)")


func test_timeout_leaves_crew_waiting() -> void:
	var sim := _sim()
	_attack_locked_door(sim)
	var c := _step_until_card(sim)
	assert_true(c != null, "카드")
	sim.step_ticks(roundi(13.0 / SimClock.TICK_DT))
	assert_true(not sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.id == "DOOR-LOCKED-01"), "중요 12초 지나면 사라짐")
	assert_eq(sim.cards.log.filter(func(l: Dictionary) -> bool: return l.id == "DOOR-LOCKED-01")[0].result, "timeout", "미응답 기록")
	assert_true(sim.doors.task_of(sim.fire.opening_at(Vector3i(13, 20, 1))) == null, "안전한 기본값 없음 — 문은 그대로")


func test_preorder_skips_card() -> void:
	var sim := _sim()
	sim.issue(CommandOrder.make("preorder", [], 1, Vector3i.ZERO, {"key": "force_locked"}))
	_attack_locked_door(sim)
	sim.step_ticks(roundi(40.0 / SimClock.TICK_DT))
	assert_true(not sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.id == "DOOR-LOCKED-01"), "선제지시가 있으면 카드가 뜨지 않음")
	var lg: Dictionary = sim.cards.log.filter(func(l: Dictionary) -> bool: return l.id == "DOOR-LOCKED-01")[0]
	assert_eq(lg.result, "preordered", "선제지시로 기록")
	assert_eq(lg.grade, "최선", "최선으로 처리")
	assert_true(sim.doors.task_of(sim.fire.opening_at(Vector3i(13, 20, 1))) != null or sim.fire.opening_at(Vector3i(13, 20, 1)).is_open, "바로 파괴 개방")


func test_queue_priority_and_overflow() -> void:
	var sim := _sim()
	var cs := sim.cards
	# 사건을 직접 넣어 대기열을 확인한다 (일반 → 긴급 → 중요 → 일반)
	sim.events.add(1, "knockdown_reported", {"crew": "진압1 1조", "crew_id": 0, "rooms": "거실"})
	sim.events.add(1, "air_alarm", {"crew": "진압1 2조", "crew_id": 1})
	sim.events.add(1, "tactical_halt", {"crew": "구조1 1조", "crew_id": 2, "kind": "victim", "victim_name": "아이(7)", "state": "의식 있음", "reason": "", "safety": false})
	sim.events.add(1, "tactical_halt", {"crew": "구조1 2조", "crew_id": 3, "kind": "closed", "door_name": "방1 문", "reason": "", "safety": false})
	cs.step(0.1, 1)
	assert_eq(cs.queue.size(), 3, "최대 3장")
	assert_eq(cs.active().urgency, "긴급", "긴급 카드가 맨 앞")
	assert_true(cs.log.filter(func(e: Dictionary) -> bool: return e.result == "overflow").size() >= 1, "만장이면 대기 중으로 밀림")
	assert_true(sim.events.of_type("card_overflow").size() >= 1, "대기 중 기록")


func test_training_doubles_time_and_replay_same() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 5)
	sim.command.resources.clear_schedule()
	sim.apply_realism("훈련")
	sim.events.add(1, "air_alarm", {"crew": "진압1 1조", "crew_id": 0})
	sim.cards.step(0.1, 1)
	var c := sim.cards.active()
	assert_eq(c.deadline_tick - c.asked_tick, roundi(16.0 / SimClock.TICK_DT), "훈련은 긴급 8초 × 2")
	var a := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 5)
	var b := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 5)
	for s in [a, b]:
		s.events.add(1, "tactical_halt", {"crew": "x", "crew_id": 0, "kind": "locked", "door_name": "현관", "reason": "", "safety": false})
		s.cards.step(0.1, 1)
	assert_eq(a.cards.active().options.map(func(o: Dictionary) -> String: return o.text),
		b.cards.active().options.map(func(o: Dictionary) -> String: return o.text), "선택지 섞는 순서는 시드로 같다")


func test_card_rule() -> void:
	var sim := _sim()
	sim.cards.log = [{"grade": "최선", "result": "answered"}, {"grade": "", "result": "timeout"}, {"grade": "최선", "result": "preordered"}] as Array[Dictionary]
	sim.end_activity("활동 종료 선언")
	var r: Dictionary = Evaluator.evaluate(sim).rules.filter(func(x: Dictionary) -> bool: return x.id == "command.cards")[0]
	assert_true(r.applicable and absf(r.score - 2.0 / 3.0) < 0.01, "카드 정답률 (최선·미응답·선제지시) %s" % r.detail)
