extends TestSuite
## P4-1: 처음 차량은 지도 가장자리에서 한 대씩 (펌프차 먼저, 뛰어넘지 않음), 조는 차가 서면 내린다.
## 없는 장비(방화문 파괴기)는 차량 왕복 뒤에만 쓴다


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	return sim


func _until(sim: SimWorld, cond: Callable, max_s: float) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return cond.call()


func test_sequential_arrival_pump_first() -> void:
	var sim := _sim()
	sim.command.resources.arrival_drive = true
	var targets := {}
	for v in sim.units.vehicles:
		targets[v.id] = v.pos
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 5.0}))
	sim.step_ticks(1)
	var res := sim.command.resources
	assert_true(res.arriving.size() == sim.units.vehicles.size(), "모든 처음 차량이 들어온다")
	var first := sim.units.get_vehicle(int(res.arriving[0].vehicle))
	assert_true(first.is_pump(), "펌프차가 먼저")
	assert_true(int(res.arriving[1].start_tick) - int(res.arriving[0].start_tick) == 50, "5초 간격")
	assert_true(sim.units.crews.filter(func(c: Crew) -> bool: return c.leader.aboard).size() > 0, "조는 차를 타고 온다")
	assert_true(_until(sim, func() -> bool: return not res.arriving_now(), 120.0), "모두 섬")
	var arrived := sim.events.of_type("vehicle_arrived")
	assert_eq(arrived.size(), sim.units.vehicles.size(), "도착 무전")
	assert_true(str(arrived[0].vehicle).contains("펌프"), "첫 도착은 펌프차 (%s)" % arrived[0].vehicle)
	assert_true(sim.units.crews.all(func(c: Crew) -> bool: return not c.leader.aboard), "차가 서면 내린다")
	# 겹치지 않는다
	for a in sim.units.vehicles:
		for b in sim.units.vehicles:
			if a.id < b.id:
				assert_true(not sim.command.resources._blocked(a, a.pos) or a.pos.distance_to(b.pos) > 0.5, "차량 겹침 없음")


func test_blocked_vehicle_comes_from_other_end() -> void:
	var sim := _sim()
	sim.command.resources.arrival_drive = true
	var pump: Vehicle = null
	var other: Vehicle = null
	for v in sim.units.vehicles:
		if v.is_pump() and pump == null:
			pump = v
		elif other == null:
			other = v
	# 뒤차의 자리를 펌프차보다 '앞'(진행 방향)으로 → 같은 끝에서 오면 펌프차를 넘어야 한다
	other.heading = pump.heading
	other.pos = pump.pos + pump.heading * (pump.length_cells + 6.0)
	var want := other.pos
	var dir := pump.heading
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 5.0}))
	var overlapped := false
	for i in roundi(120.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if not other.away and not pump.away and sim.command.resources._blocked(other, other.pos):
			overlapped = true
		if not sim.command.resources.arriving_now():
			break
	assert_true(not overlapped, "다른 차와 겹치지 않는다 (뛰어넘지 않음)")
	assert_true(other.pos.distance_to(want) < 1.0, "반대쪽 끝에서 들어와 자리에 선다")
	assert_eq(other.heading, -dir, "마주 보는 방향")
	# 양쪽 끝이 모두 막히면 그 앞에서 서고 보고한다
	var probe := Vehicle.new()
	probe.heading = dir
	probe.length_cells = other.length_cells
	probe.width_cells = other.width_cells
	var res := sim.command.resources
	var from := res._edge_start(pump.pos, dir, probe.length_cells)
	assert_true(res._reach(probe, from, pump.pos + dir * 2.0) < (pump.pos + dir * 2.0 - from).dot(dir) - 0.5, "앞차가 있으면 그 뒤까지만 간다")


func test_breaker_fetch() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/sop213_1_apartment_3f.json")
	sim.command.resources.clear_schedule()
	sim.command.entry_order_required = false
	sim.doors.require_equipment = true
	var door: Opening = null
	for o in sim.fire.openings:
		if door == null and o.kind == Opening.Kind.DOOR and sim.building.is_fire_door(o.cells[0]):
			door = o
	assert_true(door != null, "방화문")
	door.locked = true
	door.is_open = false
	sim.doors.sync_blocking()
	var crew_id := -1
	for c in sim.units.crews:
		if crew_id < 0 and sim.units.squads[c.squad_id].type == "진압대":
			crew_id = c.id
	var c := sim.units.get_crew(crew_id)
	assert_true(not c.has_item("fire_door_breaker"), "진압대는 기본으로 파괴기가 없다")
	var cell := Vector3i(door.cells[0].x, door.cells[0].y, door.level)
	assert_true(not sim.doors.request(crew_id, cell, true, 0), "파괴기 없이는 방화문을 못 부순다")
	assert_eq(sim.events.of_type("equipment_missing").size(), 1, "장비 없음 보고")
	sim.doors.order_fetch(crew_id, "fire_door_breaker", cell, 0)
	assert_true(_until(sim, func() -> bool: return c.has_item("fire_door_breaker"), 240.0), "차량에 다녀와 챙긴다")
	assert_eq(sim.events.of_type("equipment_fetched").size(), 1, "챙김 기록")
	assert_true(sim.doors.task_of_crew(crew_id) != null, "가져온 뒤 다시 그 문 작업")
	var rescue_c: Crew = null
	for rc in sim.units.crews:
		if sim.units.squads[rc.squad_id].type == "구조대":
			rescue_c = rc
	if rescue_c:
		assert_true(rescue_c.has_item("fire_door_breaker"), "구조대는 기본으로 파괴기")
