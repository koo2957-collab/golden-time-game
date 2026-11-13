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


func test_no_time_limit_crew_waits_and_calls_again() -> void:
	# 2026-11-14 사용자 결정: 제한 시간 없음 — 답할 때까지 남고, 그 조는 기다리며 다시 부른다 (예전: 중요 12초 뒤 사라짐)
	var sim := _sim()
	_attack_locked_door(sim)
	var c := _step_until_card(sim)
	assert_true(c != null, "카드")
	assert_true(not sim.cards.timed and c.deadline_tick < 0, "제한 시간 없음")
	sim.step_ticks(roundi(90.0 / SimClock.TICK_DT))
	assert_true(sim.cards.queue.has(c), "90초가 지나도 남아 있다")
	assert_true(sim.events.of_type("card_timeout").is_empty(), "시간 초과 없음")
	assert_true(sim.events.of_type("radio_recall").size() >= 2, "기다리는 조가 다시 부른다 (%d번)" % sim.events.of_type("radio_recall").size())
	assert_true(sim.doors.task_of(sim.fire.opening_at(Vector3i(13, 20, 1))) == null, "답하기 전에는 움직이지 않는다 — 문은 그대로")
	# 늦게라도 답하면 그대로 실행된다
	sim.issue(CommandOrder.make("card_answer", [], 0, Vector3i.ZERO, {"uid": c.uid}))
	sim.step_ticks(2)
	assert_true(not sim.cards.queue.has(c), "답하면 닫힌다")


func test_time_limit_still_works_when_enabled() -> void:
	# 제한 시간을 켜면(card_params time_limit_enabled) 예전처럼 사라진다
	var sim := _sim()
	sim.cards.timed = true
	_attack_locked_door(sim)
	var c := _step_until_card(sim)
	assert_true(c != null and c.deadline_tick > 0, "제한 시간 있음")
	sim.step_ticks(roundi(13.0 / SimClock.TICK_DT))
	assert_true(not sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.id == "DOOR-LOCKED-01"), "중요 12초 지나면 사라짐")
	assert_eq(sim.cards.log.filter(func(l: Dictionary) -> bool: return l.id == "DOOR-LOCKED-01")[0].result, "timeout", "미응답 기록")


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
	# 2026-11-14: 제한 시간이 없어져 뒤의 무전은 버려지지 않고 차례를 기다린다 (예전: 최대 3장, 넘치면 버림)
	assert_true(cs.queue.size() >= 4, "무전이 모두 차례를 기다린다 (%d건)" % cs.queue.size())
	assert_eq(cs.active().urgency, "긴급", "긴급 무전이 맨 앞")
	assert_true(sim.events.of_type("card_overflow").is_empty(), "버려지는 무전 없음")


func test_training_doubles_time_and_replay_same() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 5)
	sim.command.resources.clear_schedule()
	sim.apply_realism("훈련")
	sim.cards.timed = true
	sim.events.add(1, "air_alarm", {"crew": "진압1 1조", "crew_id": 0})
	sim.cards.step(0.1, 1)
	var c := sim.cards.active()
	# 제한시간은 실제 초 (훈련 2배), 현장 시계가 1.5배로 흐르므로 현장 틱으로는 × 1.5 (기획안 5-8)
	assert_eq(c.deadline_tick - c.asked_tick, roundi(16.0 * sim.field_scale / SimClock.TICK_DT), "훈련은 긴급 8초 × 2 (실제 초)")
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


func test_crew_judgment_scene_and_auto() -> void:
	# 2026-11-14: 대원이 스스로 판단할 일(잠긴 문 등)은 조장의 판단 장면 — 켜면 플레이어가 조장으로서 고르고, 끄면 대원이 SOP대로 알아서 한다
	var data: Dictionary = JsonData.load_file("res://data/cards/cards.json")
	var judged: Array = (data.cards as Array).filter(func(c: Dictionary) -> bool: return str(c.get("scene", "")) == "judgment")
	assert_true(judged.size() >= 10, "판단 장면 카드 %d장" % judged.size())
	for spec: Dictionary in judged:
		assert_true(str(spec.get("monologue", "")) != "", "%s 속말" % spec.id)
	var entry: Dictionary = (data.cards as Array).filter(func(c: Dictionary) -> bool: return c.id == "ENTRY-01")[0]
	assert_true(not entry.has("scene"), "진입 허가 요청은 지휘관에게 오는 무전")
	# 켬: 장면이 뜨고, 고르면 지휘관의 지시가 아니라 그 조의 판단으로 기록된다
	var sim := _sim()
	_attack_locked_door(sim)
	var c := _step_until_card(sim)
	assert_true(c != null and c.id == "DOOR-LOCKED-01", "잠긴 문 장면")
	if c == null:
		return
	assert_true(c.judgment() and c.monologue.contains("잠겨 있다"), "조장의 판단 장면과 속말: %s" % c.monologue)
	sim.issue(CommandOrder.make("card_answer", [], 0, Vector3i.ZERO, {"uid": c.uid}))
	sim.step_ticks(2)
	assert_eq([sim.events.of_type("crew_decided").size(), sim.events.of_type("card_answered").size()], [1, 0], "조의 판단으로 기록")
	assert_eq(str(sim.cards.log[-1].scene), "judgment", "기록에 장면 종류")
	# 끔: 장면 없이 대원이 최선을 고른 것처럼 움직이고 보고만 한다
	var auto := _sim()
	auto.cards.crew_judgment = false
	_attack_locked_door(auto)
	for i in roundi(60.0 / SimClock.TICK_DT):
		auto.step_ticks(1)
		if not auto.events.of_type("crew_decided").is_empty():
			break
	assert_true(auto.cards.active() == null or not auto.cards.active().judgment(), "판단 장면이 뜨지 않는다")
	var done := auto.events.of_type("crew_decided")
	assert_eq(done.size(), 1, "대원이 알아서 판단하고 보고")
	if not done.is_empty():
		assert_true(bool(done[0].get("auto", false)), "자동 판단 표시")
		assert_eq([str(auto.cards.log[-1].result), str(auto.cards.log[-1].grade)], ["crew_auto", "최선"], "SOP대로(최선)")
