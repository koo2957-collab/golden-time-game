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


# --- 하차 동작 (출동 4단계, 2026-11-15 사용자 결정): 각자 문으로 내려 모이는 자리까지 걸어간다 ---

func test_door_config() -> void:
	var data: Dictionary = JsonData.load_file(ResourceSystem.DISMOUNT_PATH)
	for key: String in data:
		var entry: Variant = data[key]
		if entry is Dictionary:
			assert_true((entry as Dictionary).has("source"), "%s에 source" % key)
	var seats: Array = ResourceSystem.door_specs("펌프차").map(func(d: Dictionary) -> String: return str(d.seat))
	assert_eq(seats.size(), 4, "펌프차 문 넷")
	for want in ["운전석", "조수석", "뒷자리 운전석 쪽", "뒷자리 조수석 쪽"]:
		assert_true(seats.has(want), "문: %s" % want)
	assert_eq(ResourceSystem.door_specs("없는차").size(), 4, "표에 없는 차종은 기본 문")
	# 동쪽을 보는 차: 운전석 = 왼쪽(북, y가 작다)·앞쪽, 조수석 = 오른쪽(남)·앞쪽, 뒷자리는 그 뒤. 모두 차체 밖
	var v := Vehicle.new()
	v.type = "펌프차"
	v.pos = Vector2(20.5, 20.5)
	v.heading = Vector2.RIGHT
	var at := {}
	for d: Dictionary in ResourceSystem.door_specs(v.type):
		at[str(d.seat)] = ResourceSystem.door_point(v, d)
		assert_true(not v.contains(at[str(d.seat)]) and v.distance_to_body(at[str(d.seat)]) < 1.5, "%s 문 앞은 차체 바로 밖" % d.seat)
	assert_true(at["운전석"].y < v.pos.y and at["조수석"].y > v.pos.y, "운전석은 왼쪽, 조수석은 오른쪽")
	assert_true(at["운전석"].x > at["뒷자리 운전석 쪽"].x and at["뒷자리 운전석 쪽"].x > v.pos.x, "앞문이 뒷문보다 앞, 둘 다 차 앞쪽(운전실)")
	# 차가 돌면 문도 같이 돈다
	v.heading = Vector2.LEFT
	var flipped := ResourceSystem.door_point(v, ResourceSystem.door_specs(v.type)[0])
	assert_true(flipped.y < v.pos.y and flipped.x < v.pos.x, "서쪽을 보면 조수석이 북쪽·서쪽 (%s)" % flipped)


func test_crews_alight_from_own_doors_and_walk() -> void:
	var sim := _sim()
	var res := sim.command.resources
	res.arrival_drive = true
	var spots := {}
	for c in sim.units.crews:
		spots[c.id] = c.leader.pos
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 5.0}))
	assert_true(_until(sim, func() -> bool: return not res.alighting.is_empty(), 120.0), "차가 서면 내리기 시작한다")
	var first: Firefighter = sim.units.firefighters[int(res.alighting[0].ff)]
	var v := sim.units.vehicles_of_squad(first.squad_id)[0]
	var riders: Array[Firefighter] = []
	var ticks := {}
	for a in res.alighting:
		var ff: Firefighter = sim.units.firefighters[int(a.ff)]
		if ff.squad_id == v.squad_id:
			riders.append(ff)
			ticks[ff.id] = int(a.tick)
	assert_true(riders.size() >= 2, "그 차에 탄 대원 (%d명)" % riders.size())
	var cells := {}
	var sides := {}
	for ff in riders:
		assert_true(ff.aboard, "내리기 전에는 탄 채로")
		assert_true(not v.contains(ff.pos) and v.distance_to_body(ff.pos) <= 2.5, "문 앞 자리 = 차체 바로 옆 (%.1f칸)" % v.distance_to_body(ff.pos))
		cells[ff.cell3()] = true
		sides[signf((ff.pos - v.pos).dot(Vector2(-v.heading.y, v.heading.x)))] = true
	assert_eq(cells.size(), riders.size(), "각자 다른 문")
	if riders.size() >= 3:
		assert_true(sides.has(1.0) and sides.has(-1.0), "운전석 쪽·조수석 쪽 문을 모두 쓴다")
	for c in sim.units.squads[v.squad_id].crews:
		if c.partner and ticks.has(c.leader.id):
			assert_eq(ticks[c.leader.id], ticks[c.partner.id], "한 조는 같이 내린다")
	# 내리면 문 앞에 나타나 모이는 자리까지 걸어간다 (순간 이동이 아니다)
	var door_pos := riders[0].pos
	assert_true(_until(sim, func() -> bool: return not riders[0].aboard, 5.0), "곧 내린다")
	assert_true(riders[0].pos.distance_to(door_pos) < 1.5, "내린 자리는 문 앞")
	assert_true(_until(sim, func() -> bool: return not res.arriving_now(), 120.0), "모두 내림")
	assert_true(_until(sim, func() -> bool: return sim.units.firefighters.all(func(f: Firefighter) -> bool: return not f.is_moving()), 60.0), "걸어서 모인다")
	for c in sim.units.crews:
		assert_true(c.leader.pos.distance_to(spots[c.id]) < 0.6, "%d조 조장은 모이는 자리에 (%.1f칸)" % [c.number, c.leader.pos.distance_to(spots[c.id])])
		if c.partner:
			assert_true(c.partner.pos.distance_to(spots[c.id] + Vector2(1, 0)) < 0.6, "짝은 그 옆에")


func test_walks_around_the_vehicle() -> void:
	var sim := _sim()
	var res := sim.command.resources
	var v := sim.units.vehicles[0]
	var side := Vector2(-v.heading.y, v.heading.x)
	var from := v.pos - side * (v.width_cells * 0.5 + 1.0)
	var across := v.pos + side * (v.width_cells * 0.5 + 3.0)
	var around := res._around(v, 1, from, across)
	assert_eq(around.size(), 2, "반대쪽으로 갈 때는 차 끝을 돌아간다")
	for c in around:
		assert_true(not v.contains(Vector2(c) + Vector2(0.5, 0.5)), "돌아가는 칸은 차체 밖")
	assert_true(absf((Vector2(around[0]) + Vector2(0.5, 0.5) - v.pos).dot(v.heading)) > v.length_cells * 0.5, "차 길이 밖으로 돈다")
	assert_true((Vector2(around[0]) - v.pos).dot(side) < 0.0 and (Vector2(around[1]) - v.pos).dot(side) > 0.0, "내린 쪽 → 반대쪽")
	assert_true(res._around(v, 1, from, from - side * 4.0).is_empty(), "같은 쪽이면 곧장")


func test_late_squad_alights_from_doors() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var res := sim.command.resources
	assert_true(_until(sim, func() -> bool: return not sim.events.of_type("squad_staged").is_empty(), 400.0), "후착대가 대기 장소에 선다")
	var squad := sim.units.squads[sim.units.squads.size() - 1]
	assert_true(not squad.crews.is_empty() and not res.alighting.is_empty(), "조가 내리기 시작한다")
	var v := sim.units.vehicles_of_squad(squad.id)[0]
	var want := {}
	for c in squad.crews:
		assert_true(c.leader.aboard and v.distance_to_body(c.leader.pos) <= 2.5, "내리기 전: 탄 채로 문 앞")
	for a in res.alighting:
		want[int(a.ff)] = a.dest
	assert_true(_until(sim, func() -> bool: return res.alighting.is_empty(), 10.0), "곧 내린다")
	assert_true(_until(sim, func() -> bool: return squad.crews.all(func(c: Crew) -> bool: return not c.leader.is_moving() and (c.partner == null or not c.partner.is_moving())), 30.0), "차 옆에 모인다")
	for c in squad.crews:
		assert_true(not c.leader.aboard and c.leader.pos.distance_to(want[c.leader.id]) < 0.6, "%d조는 모이는 자리에" % c.number)
		assert_true(not v.contains(c.leader.pos), "차체 밖")
