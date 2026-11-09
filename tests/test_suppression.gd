extends TestSuite
## 차량·수관·방수 검증. 보정 목표:
## - 성장기 거실 화재 → 관창 1개로 30초 안에 진화
## - 최성기 거실 1실 → 관창 1개로 1~2분 안에 진압 (타는 셀 10% 미만)

const PUMP := 0
const TANKER := 1


## 개발 시나리오 + 옆문(D면)만 열어 진입로를 만든다 (현관문은 닫힌 채: 화재 보정 조건 유지)
func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.doors.sync_blocking()
	return sim


func _living(sim: SimWorld) -> Compartment:
	return sim.fire.compartment_at(1, 12, 16)


func _burning_cells(sim: SimWorld, c: Compartment) -> int:
	var n := 0
	for i in sim.fire.grid.room_and_door_cells[c.index]:
		if sim.fire.grid.state[i] == FuelGrid.State.BURNING:
			n += 1
	return n


## 조를 거실 안 지점에 세우고 펌프차에서 수관을 연장해 거실 가운데로 방수한다.
func _attack(sim: SimWorld, crew_id: int, spot: Vector2, pattern := "straight") -> void:
	var crew := sim.units.get_crew(crew_id)
	crew.leader.pos = spot
	crew.leader.prev_pos = spot
	crew.partner.pos = spot + Vector2(1, 0)
	crew.partner.prev_pos = crew.partner.pos
	sim.issue(EquipmentCommand.make("hose", [crew_id] as Array[int], PUMP))
	var p := HoseLine.Pattern.FOG if pattern == "fog" else HoseLine.Pattern.STRAIGHT
	sim.issue(EquipmentCommand.make("spray", [crew_id] as Array[int], -1, p, Vector3i(12, 16, 1)))


## 수관 준비·결합·방수 개시(기획안 6-1)가 끝나 물이 나갈 때까지
func _wait_water(sim: SimWorld, crews: Array) -> void:
	sim.step_ticks(1)
	var until := 0
	for id in crews:
		var h := sim.water.hose_of_crew(id)
		if h:
			until = maxi(until, h.water_tick)
	if until > sim.clock.tick:
		sim.step_ticks(until - sim.clock.tick)


func test_vehicles_loaded() -> void:
	var sim := _sim()
	assert_eq(sim.units.vehicles.size(), 2, "차량 2대")
	assert_true(sim.units.vehicles[PUMP].is_pump(), "0번은 펌프차")
	assert_eq(sim.units.vehicles[TANKER].tank_l, 4000.0, "물탱크차 4,000L (기획안 5-4)")
	assert_eq(sim.building.hydrants.size(), 1, "소화전 1개")


func test_growth_fire_knocked_down_quickly() -> void:
	var sim := _sim()
	sim.step_ticks(4 * 600)
	var living := _living(sim)
	assert_true(_burning_cells(sim, living) > 0, "4분: 거실이 타고 있음")
	_attack(sim, 0, Vector2(17.5, 13.5))
	_wait_water(sim, [0])
	sim.step_ticks(300)
	assert_eq(_burning_cells(sim, living), 0, "성장기 화재 물이 나간 뒤 30초 안에 진화")
	assert_eq(sim.water.hoses.size(), 1, "수관 1개 연장됨")


func test_fully_developed_room_needs_a_minute_or_more() -> void:
	var sim := _sim()
	sim.step_ticks(8 * 600)
	var living := _living(sim)
	var before := _burning_cells(sim, living)
	assert_true(living.flashed, "8분: 거실 플래시오버 이후")
	# 최성기 거실 안에는 열기 때문에 설 수 없다: 복도에서 직사로 공격을 시작한다.
	# 최성기 거실(약 21㎡)은 필요 방수량이 약 290L/분이라 40mm 1선(275)으로는 모자라 2선으로 공격한다 (기획안 5-4, P6-1)
	for id in [0, 1]:
		var crew := sim.units.get_crew(id)
		crew.leader.pos = Vector2(26.5, 12.5 + id)
		crew.partner.pos = Vector2(27.5, 12.5 + id)
		sim.issue(EquipmentCommand.make("spray", [id] as Array[int], -1, HoseLine.Pattern.STRAIGHT, Vector3i(12, 16, 1)))
	_wait_water(sim, [0, 1])
	before = _burning_cells(sim, living)
	sim.step_ticks(200)
	var after := _burning_cells(sim, living)
	assert_true(after < before * 0.7, "2선이면 20초 안에 크게 줄어듦 (%d → %d)" % [before, after])
	sim.step_ticks(100)
	assert_true(_burning_cells(sim, living) > before * 0.1, "30초로는 진압되지 않음 (%d/%d)" % [_burning_cells(sim, living), before])
	# 복도에서는 물줄기가 닿지 않는 칸이 남는다 — 연소가 옆방(주방)으로 번진 최성기 화재는 진입해서 마저 꺼야 한다 (2026-11-10 화재 확산 보강)


func test_tank_runs_dry_without_supply() -> void:
	var sim := _sim()
	_attack(sim, 0, Vector2(17.5, 13.5))
	var pump := sim.units.vehicles[PUMP]
	# 수관 준비·결합·방수 개시(약 40초, 기획안 6-1) 뒤부터 물이 나간다
	sim.step_ticks(1)
	var start := sim.water.hose_of_crew(0).water_tick
	sim.step_ticks(start + 600 - sim.clock.tick)
	assert_true(absf(pump.tank_l - (2800.0 - 275.0)) < 2.0, "40mm 1선은 1분에 275L 사용 (결과 %.0fL)" % pump.tank_l)
	sim.step_ticks(600 * 9 + 120)
	assert_true(pump.tank_l < 1.0, "급수 없이 약 10분 11초면 탱크 소진 (기획안 5-4)")
	assert_true(not sim.events.of_type("tank_empty").is_empty(), "탱크 소진 사건 기록")
	assert_true(sim.water.hose_of_crew(0).flow_fraction < 0.01, "물이 없으면 방수 중단")


func test_tanker_supply_and_hydrant_keep_water() -> void:
	var sim := _sim()
	sim.issue(EquipmentCommand.make("supply", [], TANKER, PUMP))
	_attack(sim, 0, Vector2(17.5, 13.5))
	# 급수 연결 작업이 끝날 때까지 (현장 작업 시간, 기획안 6-1)
	sim.step_ticks(1)
	var t0 := sim.units.vehicles[TANKER]
	while not t0.work.is_empty() or t0.supply_to < 0:
		sim.step_ticks(10)
		if sim.clock.tick > 3000:
			break
	var pump := sim.units.vehicles[PUMP]
	var tanker := sim.units.vehicles[TANKER]
	var p0 := pump.tank_l
	var k0 := tanker.tank_l
	sim.step_ticks(600 * 5)
	assert_true(tanker.supply_to == PUMP, "물탱크차 급수 연결")
	# 물탱크차 급수 180L/분 < 1선 275L/분: 급수가 있어도 분당 95L씩 준다 (기획안 5-4)
	assert_true(absf((p0 - pump.tank_l) - 95.0 * 5.0) < 30.0, "급수 중 펌프차는 분당 약 95L 감소 (5분 %.0fL)" % (p0 - pump.tank_l))
	assert_true(absf((k0 - tanker.tank_l) - 180.0 * 5.0) < 30.0, "물탱크차는 분당 180L씩 보냄 (5분 %.0fL)" % (k0 - tanker.tank_l))
	# 소화전 점령: 물탱크차가 소화전 앞으로 이동해 연결
	sim.issue(EquipmentCommand.make("hydrant", [], TANKER, 0))
	sim.step_ticks(600 * 5)
	assert_eq(tanker.hydrant, 0, "물탱크차 소화전 점령")


func test_pump_with_hose_cannot_move() -> void:
	var sim := _sim()
	_attack(sim, 0, Vector2(17.5, 13.5))
	sim.step_ticks(1)
	sim.issue(EquipmentCommand.make("vehicle_move", [], PUMP, -1, Vector3i(30, 27, 1)))
	sim.step_ticks(100)
	assert_true(sim.units.vehicles[PUMP].pos.x < 12.0, "수관이 연결된 펌프차는 이동하지 않음")
	assert_true(not sim.events.of_type("vehicle_locked").is_empty(), "이동 불가 사건 기록")


func test_vehicle_reverses_instead_of_turning() -> void:
	var sim := _sim()
	var pump := sim.units.vehicles[PUMP]
	var heading := pump.heading
	sim.issue(EquipmentCommand.make("vehicle_move", [], PUMP, -1, Vector3i(2, 30, 1)))
	sim.step_ticks(1)
	assert_true(pump.reversing, "뒤쪽 목표 → 후진")
	sim.step_ticks(200)
	assert_eq(pump.heading, heading, "제자리 회전 없음 (방향 유지)")
	assert_true(not pump.reversing and not pump.is_moving(), "정지")
	var back := pump.pos.x - pump.length_cells * 0.5
	assert_true(back >= 0.0 and back < 0.6, "차체 뒤끝이 지도(차도) 끝에서 멈춤 (뒤끝 x=%.2f)" % back)


func test_vehicle_cannot_leave_road_or_slide_sideways() -> void:
	var sim := _sim()
	var pump := sim.units.vehicles[PUMP]
	var y := pump.pos.y
	sim.issue(EquipmentCommand.make("vehicle_move", [], PUMP, -1, Vector3i(8, 22, 1)))  # 뒤쪽 마당
	sim.step_ticks(100)
	assert_eq(pump.pos.y, y, "옆(마당 쪽)으로는 움직이지 않음")
	assert_true(absf(pump.pos.x - 8.5) < 0.01, "차체 축 방향 성분만큼만 이동 (x=%.2f)" % pump.pos.x)
	assert_true(sim.pathfinder.vehicle_fits(pump.footprint()), "차체가 차도 위에 있음")


func test_vehicles_do_not_overlap() -> void:
	var sim := _sim()
	var pump := sim.units.vehicles[PUMP]
	var tanker := sim.units.vehicles[TANKER]
	sim.issue(EquipmentCommand.make("vehicle_move", [], PUMP, -1, Vector3i(34, 30, 1)))
	sim.step_ticks(300)
	assert_true(Geometry2D.intersect_polygons(pump.footprint(), tanker.footprint()).is_empty(), "앞 차량과 겹치지 않음")
	var gap := (tanker.pos.x - tanker.length_cells * 0.5) - (pump.pos.x + pump.length_cells * 0.5)
	assert_true(gap >= 0.0 and gap < 0.6, "앞 차량 바로 뒤에서 멈춤 (간격 %.2f셀)" % gap)


func test_spray_auto_hose_and_approach() -> void:
	var sim := _sim()
	sim.step_ticks(4 * 600)
	var crew := sim.units.get_crew(0)  # 마당, 수관 없음
	assert_true(sim.water.hose_of_crew(0) == null, "처음엔 수관 없음")
	sim.issue(EquipmentCommand.make("spray", [0] as Array[int], -1, HoseLine.Pattern.STRAIGHT, Vector3i(12, 16, 1)))
	sim.step_ticks(1)
	var h := sim.water.hose_of_crew(0)
	assert_true(h != null and h.vehicle_id == PUMP, "가장 가까운 펌프차에서 수관 자동 연장")
	assert_true(h.approaching and crew.leader.is_moving(), "목표가 벽에 가려 있어 방수 위치로 이동")
	var tank_before := sim.units.vehicles[PUMP].tank_l
	sim.step_ticks(5)
	assert_eq(sim.units.vehicles[PUMP].tank_l, tank_before, "이동 중에는 물을 쓰지 않음")
	sim.step_ticks(600)
	assert_true(not h.approaching and not h.blocked, "도착 후 막힘 없이 방수")
	assert_eq(_burning_cells(sim, _living(sim)), 0, "거실 진화")


func test_hose_length_limits_movement() -> void:
	var sim := _sim()
	var pump := sim.units.vehicles[PUMP]
	pump.hose_max_cells = 30.0  # 15m
	sim.issue(EquipmentCommand.make("hose", [0] as Array[int], PUMP))
	sim.step_ticks(1)
	assert_eq(sim.water.hoses.size(), 1, "가까운 조는 수관 연장")
	sim.issue(MoveCommand.new([0] as Array[int], Vector3i(12, 6, 2)))
	sim.step_ticks(600)
	var h := sim.water.hose_of_crew(0)
	assert_true(h.length_cells() <= 30.0, "수관 길이는 한계를 넘지 않음 (%.1f셀)" % h.length_cells())
	assert_true(h.at_limit, "수관 길이 한계 도달")
	assert_eq(sim.units.get_crew(0).leader.level, 1, "2층까지 가지 못함")


func test_water_does_not_pass_walls() -> void:
	var sim := _sim()
	sim.fire.ignite(Vector3i(27, 17, 1))  # 방1 침대
	sim.step_ticks(1200)
	var room1 := sim.fire.compartment_at(1, 25, 17)
	var crew := sim.units.get_crew(0)
	crew.leader.pos = Vector2(24.5, 12.5)  # 복도, 방1과 벽으로 막힘
	crew.partner.pos = Vector2(25.5, 12.5)
	sim.issue(EquipmentCommand.make("hose", [0] as Array[int], PUMP))
	# 다가가기 없이 막힌 곳을 겨누는 상황을 직접 만든다
	sim.step_ticks(1)
	var h := sim.water.hose_of_crew(0)
	h.target = Vector3i(27, 17, 1)
	h.aim = Vector2(27.5, 17.5)
	h.flowing = true
	h.next_advance_tick = 1 << 30  # 이 테스트에서는 '진압하며 전진'을 끈다
	h.water_tick = sim.clock.tick
	h.ready_tick = sim.clock.tick
	sim.step_ticks(50)
	assert_true(h.blocked, "벽에 막힘")
	assert_true(h.impact.y < 14.0, "물은 벽 앞(복도)에 떨어짐")
	assert_eq(room1.water_applied_l, 0.0, "방1에는 물이 들어가지 않음")


func test_water_damage_after_fire_out() -> void:
	var sim := _sim()
	sim.step_ticks(4 * 600)
	_attack(sim, 0, Vector2(17.5, 13.5))
	sim.step_ticks(300)
	var living := _living(sim)
	var damage_at_out := living.water_damage_l
	sim.step_ticks(1200)
	assert_true(living.water_damage_l > damage_at_out + 100.0, "진화 후에도 계속 방수하면 수손 증가")
	assert_eq(living.stage, Compartment.Stage.EXTINGUISHED, "거실 단계: 진화")
