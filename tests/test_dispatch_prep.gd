extends TestSuite
## P9-1 출동 준비: 상황실 요청(예비 소방용수·관계자 조치)이 현장에 반영되는가, 도착 후 임무 미리 정하기


func _card(sim: SimWorld, id: String) -> CardSystem.Card:
	for c in sim.cards.queue:
		if c.id == id:
			return c
	return null


func _answer(sim: SimWorld, card_id: String, effect: String) -> bool:
	var c := _card(sim, card_id)
	if c == null:
		return false
	for i in c.options.size():
		if str(c.options[i].effect) == effect:
			sim.issue(CommandOrder.make("card_answer", [], i, Vector3i.ZERO, {"uid": c.uid}))
			sim.step_ticks(1)
			return true
	return false


func _until(sim: SimWorld, cond: Callable, max_s: float) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return cond.call()


func test_relay_shuts_gas_and_reports_fire() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/sop214_3_kitchen_lpg.json")
	assert_true(_until(sim, func() -> bool: return _card(sim, "ARRIVAL-RELAY-01") != null, 30.0), "관계자 조치 카드")
	assert_true(sim.gas.has_gas() and sim.gas.open, "가스 열림")
	assert_true(_answer(sim, "ARRIVAL-RELAY-01", "relay_all"), "모두 요청")
	assert_true(not sim.gas.open, "도착 전에 가스 차단")
	assert_true(not sim.knowledge.fires.is_empty(), "발화 위치가 상황판에 오른다")


func test_no_request_no_effect() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/sop214_3_kitchen_lpg.json")
	_until(sim, func() -> bool: return _card(sim, "ARRIVAL-RELAY-01") != null, 30.0)
	assert_true(_answer(sim, "ARRIVAL-RELAY-01", "note"), "요청하지 않음")
	assert_true(sim.gas.open, "요청하지 않은 조치는 반영되지 않는다")
	assert_true(sim.knowledge.fires.is_empty(), "발화 위치도 모름")


func test_reserve_water_switches_hydrant() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	if sim.building.hydrants.size() < 2:
		return
	sim.command.reserve_water = true
	var pump := sim.units.vehicles[0]
	sim.water.hydrants_out.append(0)
	sim.events.add(sim.clock.tick, "hydrant_out", {"vehicle": pump.display_name(sim.units.squads[pump.squad_id].name), "driver": pump.driver_label()})
	sim.step_ticks(2)
	assert_true(_card(sim, "HYDRANT-OUT-01") == null, "예비 소방용수를 정해 두면 묻지 않는다")
	assert_eq(sim.events.of_type("reserve_hydrant").size(), 1, "다음 소화전으로")


func test_preassign_acts_on_arrival() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.issue(CommandOrder.make("preassign", [], 0, Vector3i.ZERO, {"tasks": {"0": "search", "1": "officer"}}))
	sim.step_ticks(2)
	assert_eq(sim.events.of_type("preassign_start").size(), 2, "내리자마자 시작")
	assert_true(sim.tactical.task_of_crew(0) != null, "인명검색 임무")
	sim.step_ticks(roundi(30.0 / SimClock.TICK_DT))
	assert_eq(sim.command.safety.role_of(1), SafetySystem.Role.OFFICER, "현장안전담당 지정")
