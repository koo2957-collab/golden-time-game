extends TestSuite
## M9b: 물탱크차 순환보수 (SOP 200-3.1.1.3)

const PATH := "res://data/scenarios/sop214_3_kitchen_lpg.json"


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(PATH)
	sim.command.resources.clear_schedule()
	return sim


func _vehicles(sim: SimWorld) -> Array:
	var pump: Vehicle = null
	var tank: Vehicle = null
	for v in sim.units.vehicles_of_squad(0):
		if v.is_pump():
			pump = v
		elif v.transfer_lpm > 0.0:
			tank = v
	return [pump, tank]


func test_hydrant_out() -> void:
	var sim := _sim()
	assert_eq(sim.water.hydrants_out, [0] as Array[int], "③ 소화전 고장")
	var tank: Vehicle = _vehicles(sim)[1]
	sim.water._connect_hydrant_now(tank, 0, 1)
	assert_eq(tank.hydrant, -1, "고장 소화전은 점령되지 않음")
	assert_eq(sim.events.of_type("hydrant_out").size(), 1, "고장 무전")


func test_shuttle_cycle() -> void:
	var sim := _sim()
	var vs := _vehicles(sim)
	var pump: Vehicle = vs[0]
	var tank: Vehicle = vs[1]
	assert_true(sim.shuttle.available(), "원거리 수원 있음")
	assert_true(not sim.shuttle.toggle(pump.id, 0), "펌프차는 순환보수 대상 아님")
	sim.issue(EquipmentCommand.make("shuttle", [], tank.id))
	sim.step_ticks(roundi(60.0 / SimClock.TICK_DT))
	assert_true(sim.shuttle.tankers.has(tank.id), "순환보수 지정")
	assert_eq(tank.supply_to, pump.id, "펌프차에 급수 연결")
	# 탱크를 거의 비우면 원거리 수원으로 떠난다
	tank.tank_l = tank.tank_capacity * 0.05
	sim.step_ticks(2)
	assert_true(tank.away, "급수하러 출발 (현장 없음)")
	assert_eq(tank.supply_to, -1, "급수 끊김")
	var eta: int = sim.events.of_type("shuttle_depart")[0].eta_s
	assert_true(eta > 300 and eta < 800, "왕복 300초 + 급수 시간 (%d초)" % eta)
	sim.step_ticks(roundi((eta + 5) / SimClock.TICK_DT))
	assert_true(not tank.away, "복귀")
	assert_true(tank.tank_l > tank.tank_capacity * 0.9, "가득 채워 옴")
	sim.step_ticks(roundi(30.0 / SimClock.TICK_DT))
	assert_eq(tank.supply_to, pump.id, "다시 펌프차에 급수")
	assert_eq(sim.shuttle.trips(), 1, "왕복 1회")


func test_shuttle_rule() -> void:
	var sim := _sim()
	var rule: Dictionary = Evaluator.evaluate(sim).rules.filter(func(r: Dictionary) -> bool: return r.id == "fire.shuttle")[0]
	assert_true(rule.applicable and rule.score < 0.5, "지시하지 않으면 낮은 점수 (%s)" % rule.detail)
	sim.shuttle.toggle(_vehicles(sim)[1].id, 1)
	sim.step_ticks(10)
	rule = Evaluator.evaluate(sim).rules.filter(func(r: Dictionary) -> bool: return r.id == "fire.shuttle")[0]
	assert_eq(rule.score, 1.0, "지시하고 물이 끊기지 않으면 만점")
	var house := SimWorld.from_scenario("res://data/scenarios/sop214_1_day_living.json")
	assert_true(not house.shuttle.available(), "다른 시나리오는 순환보수 없음")
