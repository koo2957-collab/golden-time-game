extends TestSuite
## 지휘 계층: 진입 명령 규칙, 무전 우선순위·송신 시간, 최초 상황보고 판정, 전략·철수, 자동 감속, 무전 보고


func _command_sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	open_all_doors(sim)
	return sim


func _outdoor(sim: SimWorld, ff: Firefighter) -> bool:
	return sim.building.cell(ff.level, floori(ff.pos.x), floori(ff.pos.y)) in BuildingData.OUTDOOR


## 무전 송신이 끝날 때까지 진행 (최대 max_s초). 방금 내린 명령이 실행되도록 한 틱은 먼저 진행한다.
func _until_quiet(sim: SimWorld, max_s := 120.0) -> void:
	sim.step_ticks(1)
	for i in roundi(max_s / SimClock.TICK_DT):
		if not sim.command.radio.busy():
			return
		sim.step_ticks(1)


func test_entry_requires_order() -> void:
	var sim := _command_sim()
	var living := Vector3i(13, 15, 1)
	sim.issue(MoveCommand.new([0], living))
	sim.step_ticks(200)
	var leader := sim.units.get_crew(0).leader
	assert_true(_outdoor(sim, leader), "진입 명령 전에는 건물 밖에 머문다")
	assert_true(leader.pos.distance_to(Vector2(13.5, 20.5)) < 3.0, "입구 앞까지는 간다 (결과: %s)" % leader.pos)
	assert_eq(sim.events.of_type("entry_wait").size(), 1, "진입 명령 대기 알림")
	assert_eq(sim.events.of_type("crew_entered").size(), 0, "진입 기록 없음")
	sim.issue(CommandOrder.make("entry", [0]))
	sim.step_ticks(1)
	assert_true(not sim.command.can_enter(0), "무전 송신이 끝나기 전에는 진입 허가가 아님")
	_until_quiet(sim)
	assert_true(sim.command.can_enter(0), "무전 송신 후 진입 허가")
	sim.issue(MoveCommand.new([0], living))
	sim.step_ticks(150)
	assert_true(not _outdoor(sim, leader), "진입 명령을 받은 출동대는 들어간다")
	assert_eq(sim.events.of_type("crew_entered").size(), 1, "진입 기록")
	assert_true(sim.command.can_enter(0) and not sim.command.can_enter(1), "진입 허가는 출동대별")


func test_commander_stays_outside() -> void:
	var sim := _command_sim()
	sim.issue(CommandOrder.make("commander_move", [], 0, Vector3i(13, 15, 1)))
	sim.step_ticks(200)
	assert_true(_outdoor(sim, sim.command.commander), "지휘관은 혼자 건물 안으로 들어가지 않는다")
	assert_true(sim.command.commander.pos.distance_to(Vector2(13.5, 20.5)) < 3.0, "입구 앞까지 이동")


func test_radio_priority_and_duration() -> void:
	var sim := _command_sim()
	var radio := sim.command.radio
	var long_msg := radio.send(Radio.Priority.TACTICS, "A", "B", "가".repeat(80), 0)
	sim.step_ticks(1)
	assert_true(radio.current == long_msg, "빈 채널이면 바로 송신")
	var tactics := radio.send(Radio.Priority.TACTICS, "A", "B", "짧은 전술 무전", 1)
	var safety := radio.send(Radio.Priority.SAFETY, "C", "B", "대원 안전 무전", 1)
	assert_true(long_msg.duration_s > tactics.duration_s, "긴 무전일수록 오래 걸린다")
	_until_quiet(sim)
	assert_true(safety.start_tick < tactics.start_tick, "대원 안전 무전이 먼저 나간다")
	assert_true(safety.start_tick >= long_msg.end_tick, "송신 중인 무전은 끊지 않는다")
	assert_true(sim.events.of_type("radio").size() >= 3, "무전 기록")


func test_initial_report_grading() -> void:
	var sim := _command_sim()
	var answers := {
		"fire": "연기만 확인", "victims": "있음", "use": "단독주택", "floors": "2층",
		"structure": "벽돌조", "hazards": [], "activities": ["인명검색", "내부 진입 진압"],
		"strategy": CommandSystem.Strategy.OFFENSIVE, "support": "불필요", "access": "진입 가능, 회차 불가",
	}
	sim.issue(CommandOrder.make("declare", [], 0, Vector3i.ZERO, answers))
	sim.step_ticks(2)
	assert_true(sim.command.is_declaring() and not sim.command.declared(), "송신 중에는 아직 선언 전")
	_until_quiet(sim)
	assert_true(sim.command.declared(), "송신이 끝나면 지휘권 선언")
	assert_eq(sim.command.strategy, CommandSystem.Strategy.OFFENSIVE, "전략 적용")
	var r := sim.command.report
	assert_eq(r.correct, r.scored, "확인한 사실대로 보고하면 모두 일치 (%s)" % [r.items])
	assert_eq(sim.events.of_type("command_declared").size(), 1, "선언 기록")
	# 같은 상황에서 틀린 보고
	var sim2 := _command_sim()
	answers["victims"] = "없음"
	answers["fire"] = "2층 화염 확인"
	answers["structure"] = "목조"
	var r2 := sim2.command.grade_report(answers)
	assert_eq(r2.scored - r2.correct, 3, "틀린 항목 3개")


func test_defensive_strategy_withdraws_and_blocks_entry() -> void:
	var sim := _command_sim()
	sim.issue(CommandOrder.make("entry", [0]))
	_until_quiet(sim)
	sim.issue(MoveCommand.new([0], Vector3i(13, 15, 1)))
	sim.step_ticks(150)
	var leader := sim.units.get_crew(0).leader
	assert_true(not _outdoor(sim, leader), "진입한 상태")
	sim.issue(CommandOrder.make("strategy", [], CommandSystem.Strategy.DEFENSIVE))
	sim.step_ticks(1)
	sim.issue(CommandOrder.make("entry", [1]))
	_until_quiet(sim)
	assert_eq(sim.command.strategy, CommandSystem.Strategy.DEFENSIVE, "방어 전략 전파")
	assert_true(not sim.command.can_enter(0), "방어 전략이면 진입 허가 취소")
	assert_true(not sim.command.can_enter(1), "방어 전략 중 진입 명령은 받지 않음")
	assert_eq(sim.events.of_type("entry_rejected").size(), 1, "진입 명령 불가 기록")
	sim.step_ticks(200)
	assert_true(_outdoor(sim, leader), "내부 대원 철수")
	assert_true(sim.events.of_type("withdraw").size() >= 1, "철수 기록")


func test_auto_slow_and_reports() -> void:
	var sim := _command_sim()
	sim.clock.speed = 4.0
	sim.events.add(0, "victim_found", {"how": "소리", "who": "아이(7세)", "room": "방1", "state": "의식 있음"})
	sim.events.add(0, "air_alarm", {"crew": "진압1 1조"})
	sim.step_ticks(1)
	assert_eq(sim.clock.speed, 1.0, "중요한 사건이면 1배속")
	assert_eq(sim.events.of_type("auto_slow").size(), 1, "자동 감속 기록 (한 번만)")
	_until_quiet(sim)
	var texts: Array[String] = []
	var order: Array[String] = []
	for m in sim.command.radio.history:
		texts.append(m.text())
		order.append(Radio.PRIORITY_NAMES[m.priority])
	assert_eq(texts.size(), 2, "두 사건 모두 무전 보고 (%s)" % [texts])
	assert_true(texts[0].begins_with("현장지휘관, 진압1 1조."), "보고는 받는 쪽, 보내는 쪽 순 (%s)" % texts[0])
	assert_eq(order, ["대원 안전", "구조대상자"] as Array[String], "대원 안전 보고가 먼저")
	# 같은 내용은 반복 보고하지 않는다
	sim.events.add(sim.clock.tick, "air_alarm", {"crew": "진압1 1조"})
	sim.step_ticks(1)
	assert_true(not sim.command.radio.busy(), "같은 보고 반복 안 함")
