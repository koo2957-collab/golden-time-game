extends TestSuite
## P4-1: 현장 작업 = 모습 + 시간 (기획안 6-1 표): 소화전 점령·급수 연결 시간(1인 2배), 호스 본 수, 수관 준비·방수 개시, 휴대 한도


func _house() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.doors.sync_blocking()
	return sim


func _away(sim: SimWorld) -> void:
	for c in sim.units.crews:
		c.leader.pos = Vector2(60, 2)
		c.leader.prev_pos = c.leader.pos
		if c.partner:
			c.partner.pos = Vector2(61, 2)
			c.partner.prev_pos = c.partner.pos


func test_hydrant_time_two_people_half() -> void:
	var sim := _house()
	var v := sim.units.vehicles[1]
	_away(sim)
	sim.water._start_work(v, "hydrant", 0, 30.0, 0)
	var alone := float(v.work.total)
	assert_eq(int(v.work.lengths), 3, "30m → 호스 3본 (30÷15 올림 + 여유 1)")
	assert_eq(alone, (20.0 + 3 * 15.0 + 2 * 5.0) * 2.0, "혼자: (점령 20 + 3본×15 + 결합 2×5) × 2 = %.0f초" % alone)
	var c := sim.units.get_crew(0)
	c.leader.pos = v.pos + Vector2(0, v.width_cells * 0.5 + 1.0)
	c.leader.prev_pos = c.leader.pos
	sim.water._start_work(v, "hydrant", 0, 30.0, 0)
	assert_eq(float(v.work.total), alone * 0.5, "옆에 쉬는 조가 도우면 2인 = 절반")
	sim.water._start_work(v, "hydrant", 0, 45.0, 0)
	assert_true(float(v.work.total) > alone * 0.5, "45m는 30m보다 오래 걸림")


func test_hydrant_connects_after_work() -> void:
	var sim := _house()
	var tanker := sim.units.vehicles[1]
	_away(sim)
	tanker.pos = Vector2(sim.building.hydrants[0]) + Vector2(0.5, 2.0)
	tanker.prev_pos = tanker.pos
	sim.water.connect_hydrant(tanker.id, 0, 0)
	assert_true(not tanker.work.is_empty() and tanker.hydrant < 0, "바로 연결되지 않고 점령 작업 시작")
	var total := float(tanker.work.total)
	sim.step_ticks(roundi((total - 2.0) / SimClock.TICK_DT))
	assert_true(tanker.hydrant < 0, "작업이 끝나기 전에는 급수 없음")
	sim.step_ticks(roundi(4.0 / SimClock.TICK_DT))
	assert_eq(tanker.hydrant, 0, "작업이 끝나면 소화전 연결")


func test_hose_prep_and_water_start() -> void:
	var sim := _house()
	var crew := sim.units.get_crew(0)
	crew.leader.pos = Vector2(17.5, 13.5)
	crew.leader.prev_pos = crew.leader.pos
	crew.partner.pos = Vector2(18.5, 13.5)
	crew.partner.prev_pos = crew.partner.pos
	sim.issue(EquipmentCommand.make("hose", [0] as Array[int], 0))
	sim.issue(EquipmentCommand.make("spray", [0] as Array[int], -1, HoseLine.Pattern.FOG, Vector3i(12, 16, 1)))
	sim.step_ticks(1)
	var h := sim.water.hose_of_crew(0)
	assert_true(h != null, "수관 연장")
	var ready := roundi((20.0 + 2 * 5.0) / SimClock.TICK_DT)
	assert_eq(h.ready_tick - 0, ready, "수관 준비 20 + 결합 2×5초 뒤부터 송수")
	var pump := sim.units.vehicles[0]
	var tank0 := pump.tank_l
	sim.step_ticks(ready - sim.clock.tick)
	assert_eq(h.water_head, 0.0, "준비가 끝나기 전에는 물이 들어가지 않는다")
	assert_true(not h.charged, "충수 전")
	assert_eq(pump.tank_l, tank0, "물이 나오기 전에는 탱크가 줄지 않음")
	# 예비 송수 (2026-11-18): 물머리가 펌프차 쪽부터 나아가 관창에 닿아야 물이 나간다. 걸리는 시간 = 호스 안 부피 ÷ 송수량
	sim.step_ticks(10)
	assert_true(h.water_head > 0.0 and h.water_head < h.length_cells(), "차오르는 중 (%.1f / %.1f칸)" % [h.water_head, h.length_cells()])
	var meters := h.length_cells() * sim.building.cell_size_m
	var liters := meters * PI * 0.02 * 0.02 * 1000.0
	var fill_s := liters / 200.0 * 60.0
	assert_true(absf(sim.water.charge_seconds(h.length_cells()) - fill_s) < 0.05, "충수 시간 = 부피(40mm, %.0fL) ÷ 분당 200L = %.1f초" % [liters, fill_s])
	sim.step_ticks(ceili(fill_s / SimClock.TICK_DT))
	assert_true(h.charged, "물머리가 관창에 닿음")
	assert_eq(sim.events.of_type("hose_charged").size(), 1, "수관 충수 완료 보고 (한 번)")
	assert_true(absf(crew.leader.speed_factor - 0.8) < 0.01, "수관을 끄는 조는 0.8배 속도")


func test_hose_carry_limit_resupply() -> void:
	var sim := _house()
	var crew := sim.units.get_crew(0)
	sim.issue(EquipmentCommand.make("hose", [0] as Array[int], 0))
	sim.step_ticks(1)
	var h := sim.water.hose_of_crew(0)
	# 2인 × 2본 × 15m = 60m를 넘게 끌고 간다
	units_far(sim, crew, h)
	sim.step_ticks(5)
	assert_true(sim.events.of_type("hose_resupply").size() >= 1, "휴대 한도(1인 2본)를 넘으면 '호스가 모자랍니다'")
	assert_true(h.resupply_until > sim.clock.tick and crew.leader.speed_factor == 0.0, "차량에서 더 가져올 동안 멈춤")


func units_far(sim: SimWorld, crew: Crew, h: HoseLine) -> void:
	var limit := 2 * 2 * 15.0 / sim.building.cell_size_m
	while h.length_cells() <= limit + 2.0:
		var last := h.points[-1]
		h.points.append(Vector3i(last.x + 1, last.y, last.z))
	crew.leader.pos = Vector2(h.points[-1].x + 0.5, h.points[-1].y + 0.5)
