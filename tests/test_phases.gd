extends TestSuite
## R1: 활동 단계·초진·완진 선언·마무리·종료 (SOP 111~113, 202-6, 소방전술 I 8단계)


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.doors.sync_blocking()
	# 지휘권 선언은 무전이 필요하므로 단계만 넘겨 둔다
	sim.phases._enter(PhaseSystem.Phase.OPERATIONS, 0)
	return sim


func _attack(sim: SimWorld) -> void:
	var crew := sim.units.get_crew(0)
	crew.leader.pos = Vector2(17.5, 13.5)
	crew.leader.prev_pos = crew.leader.pos
	crew.partner.pos = Vector2(18.5, 13.5)
	crew.partner.prev_pos = crew.partner.pos
	sim.issue(EquipmentCommand.make("hose", [0] as Array[int], 0))
	sim.issue(EquipmentCommand.make("spray", [0] as Array[int], -1, HoseLine.Pattern.FOG, Vector3i(12, 16, 1)))


func test_phases_start() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	assert_eq(sim.phases.phase, PhaseSystem.Phase.DISPATCH, "처음은 출동·도착")
	sim.step_ticks(2)
	assert_eq(sim.phases.phase, PhaseSystem.Phase.COMMAND, "도착하면 지휘권 확립 단계")


func test_knockdown_after_suppression() -> void:
	var sim := _sim()
	sim.step_ticks(4 * 600)
	_attack(sim)
	sim.step_ticks(3 * 600)
	assert_true(sim.phases.knockdown_tick >= 0, "진압 뒤 초진 판정")
	assert_eq(sim.phases.phase, PhaseSystem.Phase.OVERHAUL, "잔불정리·2차 검색 단계로")
	var e: Dictionary = sim.events.of_type("knockdown_reported")[0]
	assert_true(str(e.crew).contains("1조") and str(e.rooms).contains("거실"), "수관 조가 본 방 기준 보고 (%s)" % e)


func test_no_knockdown_without_water() -> void:
	var sim := _sim()
	sim.step_ticks(15 * 600)
	assert_eq(sim.phases.knockdown_tick, -1, "물을 쓰지 않으면 초진이 아님")


func test_secondary_search_and_all_clear_scoring() -> void:
	var sim := _sim()
	sim.step_ticks(4 * 600)
	_attack(sim)
	sim.step_ticks(3 * 600)
	# 초진 뒤 검색은 2차 검색
	var c := sim.units.get_crew(2)
	sim.rescue.order_search(c.id, Vector3i(25, 17, 1), sim.clock.tick)
	sim.step_ticks(2 * 600)
	assert_true(not sim.phases.secondary.is_empty(), "2차 검색 기록")
	# 불이 남아 있을 때 선언하면 0점, 막지는 않는다
	var sim2 := _sim()
	sim2.step_ticks(4 * 600)
	sim2.issue(CommandOrder.make("all_clear"))
	sim2.step_ticks(1)
	assert_eq(sim2.phases.phase, PhaseSystem.Phase.CLOSE_OUT, "선언은 막지 않음 → 마무리 단계")
	sim2.end_activity("활동 종료 선언")
	var rule: Dictionary = Evaluator.evaluate(sim2).rules.filter(func(r: Dictionary) -> bool: return r.id == "command.all_clear")[0]
	assert_eq(rule.score, 0.0, "연소 중 완진 선언은 0점 (%s)" % rule.detail)


func test_close_out_order() -> void:
	var sim := _sim()
	sim.end_activity("활동 종료 선언")
	var r: Dictionary = Evaluator.evaluate(sim).rules.filter(func(x: Dictionary) -> bool: return x.id == "command.close_out")[0]
	assert_eq(r.score, 0.0, "완진 선언·인원점검·감시 없이 종료")
	var sim2 := _sim()
	sim2.phases.declare_all_clear(1)
	sim2.command.order_par(2)
	sim2.step_ticks(600)
	sim2.command.set_watch("관계자에게 감시 당부", sim2.clock.tick)
	sim2.end_activity("활동 종료 선언")
	r = Evaluator.evaluate(sim2).rules.filter(func(x: Dictionary) -> bool: return x.id == "command.close_out")[0]
	assert_eq(r.score, 1.0, "완진 → 인원점검 → 감시 → 종료 (%s)" % r.detail)
	assert_eq(sim2.phases.phase, PhaseSystem.Phase.ENDED, "활동 종료 단계")


func test_end_suggestion() -> void:
	# 불도 없고 건물 안 생존자도 없으면 종료 제안
	var quiet := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	quiet.phases._enter(PhaseSystem.Phase.OPERATIONS, 0)
	# 시뮬레이션을 돌리지 않았으므로 아직 타는 칸이 없다
	for v in quiet.rescue.victims:
		v.state = Victim.State.DEAD
	quiet.phases.step(0.1, 10, true)
	quiet.phases.step(0.1, 10 + roundi(61.0 / SimClock.TICK_DT), true)
	assert_eq(quiet.events.of_type("end_suggested").size(), 1, "종료 제안")
