extends TestSuite
## M7b-2: 구급대 중증도 분류·응급처치·이송·병원 인계·복귀 (SOP 400, 402), 운전원


func _sim() -> SimWorld:
	var sim := make_sim()
	sim.units.add_squad({
		"id": "ems1", "name": "구급1", "type": "구급대",
		"vehicles": [{"type": "구급차", "spawn": [50, 36], "heading": [1, 0], "driver": {"name": "민서준", "rank": "소방교"}}],
		"crews": [{"spawn": [44, 26], "members": [
			{"name": "하은수", "rank": "소방장", "role": "구급대장"},
			{"name": "도윤아", "rank": "소방사", "role": "구급대원"}]}],
	})
	return sim


## 밖에 구조된 사람 하나를 만든다
func _rescued(sim: SimWorld, state := Victim.State.UNCONSCIOUS) -> Victim:
	sim.rescue.add_victims([{"name": "환자", "age": 40, "level": 1, "cell": [36, 24]}], sim.rng)
	var v: Victim = sim.rescue.victims[-1]
	v.discovered = true
	v.state_at_rescue = state
	v.state = Victim.State.RESCUED
	v.rescued_tick = sim.clock.tick
	sim.step_ticks(1)
	return v


func _ems_crew(sim: SimWorld) -> int:
	return sim.units.squads[-1].crews[0].id


func _seconds(sim: SimWorld, s: float) -> void:
	sim.step_ticks(roundi(s / SimClock.TICK_DT))


func test_triage() -> void:
	var sim := _sim()
	var a := _rescued(sim, Victim.State.UNCONSCIOUS)
	var b := _rescued(sim, Victim.State.CONSCIOUS)
	assert_eq(sim.ems.patients.size(), 2, "구조된 사람은 환자로 등록")
	assert_eq(sim.ems.patient_of(a.id).triage, EmsSystem.Triage.URGENT, "의식 잃음 = 긴급")
	assert_eq(sim.ems.patient_of(b.id).triage, EmsSystem.Triage.MINOR, "의식 있고 노출 적음 = 비응급")
	assert_eq(sim.events.of_type("ems_triage").size(), 2, "분류 기록")
	assert_eq(sim.ems.waiting_count(), 2, "처치 대기 2명")


func test_treat_transport_handover_return() -> void:
	var sim := _sim()
	var v := _rescued(sim)
	var crew := _ems_crew(sim)
	assert_true(sim.ems.order_treat(crew, v.id, sim.clock.tick), "처치 지시")
	_seconds(sim, 240.0)
	var p := sim.ems.patient_of(v.id)
	assert_true(p.treat_start_tick >= 0, "환자에게 가서 처치 시작")
	assert_true(p.treated_tick >= 0, "180초 처치 완료")
	assert_true(p.stage in [EmsSystem.Stage.CARRYING, EmsSystem.Stage.AWAY], "입문: 처치 후 자동 이송 (%s)" % EmsSystem.STAGE_NAMES[p.stage])
	_seconds(sim, 120.0)
	assert_eq(p.stage, EmsSystem.Stage.AWAY, "구급차에 태워 출발")
	var amb := sim.units.vehicles[-1]
	assert_true(amb.away, "구급차는 현장을 떠남")
	assert_true(sim.units.get_crew(crew).leader.aboard, "구급대원도 함께 감")
	assert_true(sim.events.of_type("ems_depart")[0].driver.contains("민서준"), "운전원이 운전")
	_seconds(sim, 610.0)
	assert_eq(p.stage, EmsSystem.Stage.HANDED, "병원 인계")
	_seconds(sim, 610.0)
	assert_true(not amb.away and not sim.units.get_crew(crew).leader.aboard, "인계 후 복귀")
	assert_eq(sim.events.of_type("ems_returned").size(), 1, "복귀 기록")


func test_urgent_dies_without_treatment() -> void:
	var sim := _sim()
	var v := _rescued(sim)
	_seconds(sim, 430.0)
	assert_eq(v.state, Victim.State.DEAD, "긴급 환자는 처치가 늦으면 사망")
	var minor := _rescued(sim, Victim.State.CONSCIOUS)
	_seconds(sim, 600.0)
	assert_eq(minor.state, Victim.State.RESCUED, "비응급 환자는 기다려도 사망하지 않음")


func test_manual_transport_at_intermediate() -> void:
	var sim := _sim()
	sim.tactical.set_level("중급")
	var v := _rescued(sim, Victim.State.CONSCIOUS)
	var crew := _ems_crew(sim)
	sim.issue(EquipmentCommand.make("ems_treat", [crew] as Array[int], -1, v.id))
	_seconds(sim, 150.0)
	var p := sim.ems.patient_of(v.id)
	assert_eq(p.stage, EmsSystem.Stage.TREATED, "중급: 처치 후 이송 지시를 기다림")
	assert_true(SimEventLog.describe(sim.events.of_type("ems_treated")[0]).contains("이송 지시 바람"), "보고")
	sim.issue(EquipmentCommand.make("ems_transport", [crew] as Array[int], -1, v.id))
	_seconds(sim, 120.0)
	assert_eq(p.stage, EmsSystem.Stage.AWAY, "이송 지시 후 출발")


func test_only_ems_treats_and_move_cancels() -> void:
	var sim := _sim()
	var v := _rescued(sim)
	assert_true(not sim.ems.order_treat(0, v.id, 0), "구급대가 아닌 조는 처치 명령 불가")
	var crew := _ems_crew(sim)
	sim.ems.order_treat(crew, v.id, 0)
	sim.issue(MoveCommand.new([crew] as Array[int], Vector3i(44, 26, 1)))
	sim.step_ticks(2)
	assert_eq(sim.ems.patient_of(v.id).stage, EmsSystem.Stage.WAITING, "이동 명령을 받으면 처치 취소 → 다시 대기")


func test_driver_and_data() -> void:
	var sim := _sim()
	assert_eq(sim.units.vehicles[0].driver_label(), "소방장 김기현", "펌프차 운전원")
	assert_true(CommandCard.load_sets().has("ems"), "구급대 명령 카드 (P10-2)")
	var sc := SimWorld.from_scenario("res://data/scenarios/sop214_1_day_living.json")
	assert_true(sc.ems.hospital.contains("병원"), "시나리오 이송 병원")
	var rules: Array = sc.scenario.evaluation.rules
	assert_true("rescue.ems_treat" in rules and "rescue.ems_transport" in rules, "처치·이송 판정")
	var arrivals: Array = sc.scenario.arrivals
	assert_true(arrivals.any(func(a: Dictionary) -> bool: return a.squad == "ems1"), "구급1 출동")
