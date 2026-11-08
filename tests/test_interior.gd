extends TestSuite
## R7a: 임무형 내부 지휘 — 건물 안 조는 무전으로 지시, 경유지는 본 곳에만 (기획안 9-1, SOP 107 3.1⑤)


func _sim(on := true) -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	sim.command.interior.enabled = on
	return sim


## 진압1 1조를 거실(건물 안)에 둔다
func _inside(sim: SimWorld) -> Crew:
	var c := sim.units.get_crew(0)
	for i in c.members().size():
		c.members()[i].pos = Vector2(11.5 + i, 16.5)
		c.members()[i].prev_pos = c.members()[i].pos
	sim.command.entry_allowed[c.squad_id] = true
	sim.perception.update(sim.clock.tick)
	return c


## 대원이 본 적 없는 1층 실내 칸 (걸을 수 있는 칸)
func _unseen_cell(sim: SimWorld) -> Vector3i:
	var b := sim.building
	for y in b.height:
		for x in b.width:
			if sim.command.interior.indoor(1, Vector2(x, y)) and not sim.perception.is_seen(1, x, y) \
					and sim.pathfinder.nearest_walkable(1, Vector2i(x, y)) == Vector2i(x, y):
				return Vector3i(x, y, 1)
	return Vector3i(-1, -1, -1)


func _moves(sim: SimWorld) -> Array:
	return sim.command_log.entries.filter(func(c: RefCounted) -> bool: return c is MoveCommand)


func test_unseen_waypoint_rejected() -> void:
	var sim := _sim()
	_inside(sim)
	var t := _unseen_cell(sim)
	assert_true(t.x >= 0, "본 적 없는 실내 칸이 있다")
	sim.issue(MoveCommand.new([0] as Array[int], t))
	sim.step_ticks(30)
	assert_eq(_moves(sim).size(), 0, "본 적 없는 곳으로는 움직이지 않는다")
	var e := sim.events.of_type("order_unseen")
	assert_eq(e.size(), 1, "거절 기록")
	assert_true(str(e[0].reason).contains("임무"), "임무로 맡기라는 안내")
	assert_eq(sim.command.interior.rejected, 1, "거절 수")


func test_rule_off_by_default_for_engine_tests() -> void:
	var sim := _sim(false)
	_inside(sim)
	sim.issue(MoveCommand.new([0] as Array[int], _unseen_cell(sim)))
	sim.step_ticks(1)
	assert_eq(_moves(sim).size(), 1, "규칙을 끄면 바로 실행 (엔진 테스트)")


func test_inside_order_goes_by_radio_with_readback() -> void:
	var sim := _sim()
	var c := _inside(sim)
	var seen := Vector3i(floori(c.leader.pos.x), floori(c.leader.pos.y) - 1, 1)
	assert_true(sim.perception.is_seen(1, seen.x, seen.y), "옆 칸은 본 곳")
	sim.issue(MoveCommand.new([0] as Array[int], seen))
	sim.step_ticks(2)
	assert_eq(_moves(sim).size(), 0, "무전이 전달되기 전에는 실행되지 않는다")
	for i in 100:
		sim.step_ticks(1)
		if not _moves(sim).is_empty():
			break
	var waited := sim.command_log.entries.filter(func(x: RefCounted) -> bool: return x is MoveCommand)
	assert_eq(waited.size(), 1, "전달되면 실행")
	# 지시 송신 시간 (채널이 바쁘면 앞 무전을 기다린다 — 겹치면 늦어짐)
	var order: Radio.Message = sim.command.radio.history.filter(func(m: Radio.Message) -> bool: return m.body.ends_with("이동하라."))[0]
	var s := (order.end_tick - order.start_tick) * SimClock.TICK_DT
	assert_true(s >= 1.5 and s <= 4.0, "교신 2~3초 (%.1f초)" % s)
	assert_true((waited[0] as MoveCommand).tick >= order.end_tick, "송신이 끝난 뒤 실행")
	var texts := sim.command.radio.history.map(func(m: Radio.Message) -> String: return m.text())
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("진압1 1조, 현장지휘관.") and t.ends_with("거실로 이동하라.")), "지시 무전 %s" % [texts])
	sim.step_ticks(60)
	texts = sim.command.radio.history.map(func(m: Radio.Message) -> String: return m.text())
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("현장지휘관, 진압1 1조.") and t.ends_with("이동하겠음.")), "복명복창 %s" % [texts])
	assert_eq(sim.command.interior.relayed, 1, "무전 지시 수")


func test_outside_crew_is_direct() -> void:
	var sim := _sim()
	# 진압1 2조는 밖(출발 위치)에 있다
	var c := sim.units.get_crew(1)
	assert_true(not sim.command.interior.crew_inside(1), "밖에 있다")
	sim.issue(MoveCommand.new([1] as Array[int], Vector3i(floori(c.leader.pos.x) + 1, floori(c.leader.pos.y), 1)))
	sim.step_ticks(1)
	assert_eq(_moves(sim).size(), 1, "밖은 대면 지시라 바로 실행")


func test_withdraw_is_safety_priority() -> void:
	var sim := _sim()
	_inside(sim)
	var cmd := TacticalCommand.make("withdraw", [0] as Array[int])
	assert_eq(sim.command.interior.priority_of(cmd), Radio.Priority.SAFETY, "철수 지시는 대원 안전 우선순위")
	assert_eq(sim.command.interior.order_text(cmd), "즉시 철수하라.", "지시 문장")
	assert_eq(sim.command.interior.ack_text(TacticalCommand.make("attack", [0] as Array[int], Vector3i(12, 16, 1))).ends_with("진압하겠음."), true, "복명복창 문장")


func test_realism_enables_and_replay_matches() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 11)
	sim.apply_realism("훈련")
	assert_true(sim.command.interior.enabled, "난이도를 고르면(실제 게임) 켜진다")
	_inside(sim)
	sim.issue(MoveCommand.new([0] as Array[int], Vector3i(11, 15, 1)))
	sim.step_ticks(120)
	var r := Replay.begin(DEV_SCENARIO_PATH, sim.issued, 120, 11, "", "훈련")
	# 다시 하기도 같은 자리에서 시작하도록 같은 배치를 한다
	_inside(r.sim)
	while not r.step(50):
		pass
	assert_eq(r.sim.units.get_crew(0).leader.pos, sim.units.get_crew(0).leader.pos, "다시 하기 결과가 같다")
