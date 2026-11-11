extends TestSuite
## 즉시 지시 (2026-11-11 사용자 결정 ③): 훈련·실전은 지휘관 지시가 바로 실행되고 무전 문장은 기록에 남는다.
## 대원 보고는 그대로 줄을 선다. 악조건은 예전처럼 무전이 끝나야 실행.


func _inside_crew(sim: SimWorld) -> Crew:
	open_all_doors(sim)
	sim.command.interior.enabled = true
	sim.command.interior.plan_known = true
	var c := sim.units.get_crew(0)
	for ff in c.members():
		ff.path.clear()
		ff.level = 1
		ff.pos = Vector2(13.5, 17.5)
		ff.prev_pos = ff.pos
	return c


func _ticks_until_moving(sim: SimWorld, c: Crew, max_ticks: int) -> int:
	for i in max_ticks:
		if c.leader.is_moving():
			return i
		sim.step_ticks(1)
	return max_ticks


func test_realism_sets_order_mode() -> void:
	for spec in [["훈련", true, false], ["실전", true, true], ["악조건", false, true]]:
		var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
		sim.apply_realism(spec[0])
		assert_eq([sim.command.radio.instant_orders, sim.command.org.span_delay], [spec[1], spec[2]], "%s: 즉시 지시·통솔범위 지연" % spec[0])


func test_instant_order_moves_inside_crew_at_once() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.command.set_order_mode(true, false)
	var c := _inside_crew(sim)
	sim.issue(MoveCommand.new([0] as Array[int], Vector3i(24, 17, 1)))
	var n := _ticks_until_moving(sim, c, 100)
	assert_true(n <= 3, "건물 안 조도 바로 움직인다 (%d틱)" % n)
	var radios := sim.events.of_type("radio")
	assert_true(radios.any(func(e: Dictionary) -> bool: return str(e.text).contains("이동하라")), "지시 무전 문장은 기록에 남는다")
	assert_true(radios.any(func(e: Dictionary) -> bool: return str(e.text).begins_with("현장지휘관")), "복명복창도 바로 기록")
	var r := sim.command.radio
	var waiting: Array = r.queue.duplicate()
	if r.current:
		waiting.append(r.current)
	assert_true(not waiting.any(func(m: Radio.Message) -> bool: return m.mine or m.body.contains("하겠")), "지시·복명복창은 채널에 줄 서지 않는다 (줄에는 보고만)")


func test_harsh_mode_waits_for_radio() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.command.set_order_mode(false, true)
	var c := _inside_crew(sim)
	sim.issue(MoveCommand.new([0] as Array[int], Vector3i(24, 17, 1)))
	var n := _ticks_until_moving(sim, c, 300)
	assert_true(n >= roundi(2.0 / SimClock.TICK_DT), "악조건: 무전이 끝나야 움직인다 (%d틱)" % n)


func test_reports_still_queue() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.command.set_order_mode(true, false)
	sim.command.radio.send(Radio.Priority.TACTICS, "진압1 1조", CommandSystem.COMMANDER, "1층 거실 연기 짙음.", sim.clock.tick)
	assert_true(sim.command.radio.busy(), "대원 보고는 채널에 줄을 선다 (보고된 정보만 상황판에)")


func test_entry_request_card_comes_right_away() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.command.set_order_mode(true, false)
	sim.command.entry_order_required = true
	var c := sim.units.get_crew(0)
	var e: EntryPoints.Entry = sim.entries.list[0]
	sim.issue(CommandOrder.make("approach", [0] as Array[int], e.index))
	var arrived := -1
	var carded := -1
	for i in roundi(150.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if arrived < 0 and not c.leader.is_moving() and c.leader.pos.distance_to(Vector2(e.outside.x, e.outside.y) + Vector2(0.5, 0.5)) < 3.0:
			arrived = i
		if carded < 0 and sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.id == "ENTRY-01"):
			carded = i
			break
	assert_true(arrived >= 0 and carded >= 0, "문 앞 도착 → 진입 허가 카드")
	assert_true(carded - arrived <= roundi(2.0 / SimClock.TICK_DT), "도착하고 2초 안에 카드 (%d틱)" % (carded - arrived))
