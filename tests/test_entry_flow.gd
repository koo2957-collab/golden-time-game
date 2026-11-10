extends TestSuite
## 진입 지시 (P4-2): 진입구(바깥 출입문)·급기측/배기측, 고른 진입구로 들어가기, 무전 문장, 문 앞 휠(선제지시)

const LIVING := Vector3i(13, 15, 1)


func _sim(level := "입문") -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.tactical.set_level(level)
	return sim


func _until(sim: SimWorld, cond: Callable, max_s: float) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return cond.call()


func test_entry_points_and_sides() -> void:
	var sim := _sim()
	assert_true(sim.entries.list.size() >= 2, "바깥 출입문이 진입구 (%d개)" % sim.entries.list.size())
	for e in sim.entries.list:
		assert_true(sim.building.cell(e.level, e.outside.x, e.outside.y) in BuildingData.OUTDOOR, "%s 바깥 칸" % e.name)
		assert_true(e.name.contains("출입문") or e.name != "", "이름: %s" % e.name)
	var e: EntryPoints.Entry = sim.entries.list[0]
	sim.exposure.wind_mps = 3.0
	# 그 문이 향한 쪽에서 바람이 불어오면 급기측, 반대면 배기측
	sim.exposure.wind_from_deg = rad_to_deg(atan2(e.outward.x, -e.outward.y))
	assert_eq(sim.entries.side(e), "급기측", "바람이 불어오는 쪽 문 = 급기측")
	sim.exposure.wind_from_deg += 180.0
	assert_eq(sim.entries.side(e), "배기측", "반대쪽 = 배기측")
	sim.exposure.wind_mps = 0.0
	assert_eq(sim.entries.side(e), "", "바람이 없으면 표시 안 함")
	assert_true(sim.entries.smoke_text(e) != "", "연기 상태 문구")


func test_mission_goes_through_chosen_entry() -> void:
	var sim := _sim()
	open_all_doors(sim)
	var c := sim.units.get_crew(0)
	# 조에서 가장 먼 진입구를 고른다 (가까운 문으로 가지 않는지)
	var far: EntryPoints.Entry = null
	for e in sim.entries.list:
		if e.level == 1 and (far == null or c.leader.pos.distance_to(Vector2(e.door)) > c.leader.pos.distance_to(Vector2(far.door))):
			far = e
	var cmd := TacticalCommand.make("search", [0] as Array[int], LIVING, far.outside)
	assert_true(sim.command.interior.order_text(cmd).contains("진입해"), "무전 문장에 진입구: %s" % sim.command.interior.order_text(cmd))
	sim.issue(cmd)
	sim.step_ticks(1)
	var routes := sim.events.of_type("entry_route")
	assert_eq(routes.size(), 1, "진입구 기록")
	assert_eq(str(routes[0].entry), far.name, "고른 진입구")
	assert_true(sim.command.decisions.any(func(d: Dictionary) -> bool: return str(d.decision).contains("진입구 " + far.name)), "판단 기록")
	var best := INF
	for i in roundi(120.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if c.leader.level == 1:
			best = minf(best, c.leader.pos.distance_to(Vector2(far.outside.x, far.outside.y) + Vector2(0.5, 0.5)))
		if sim.tactical.task_of_crew(0) and sim.tactical.task_of_crew(0).via.x < 0 and best <= 1.5:
			break
	assert_true(best <= 1.5, "고른 진입구 앞을 지난다 (가장 가까이 %.1f칸)" % best)


func test_door_wheel_skips_card() -> void:
	var sim := _sim("상급")
	var living := sim.fire.compartment_at(1, LIVING.x, LIVING.y)
	var door: Opening = null
	for o in sim.fire.openings:
		if door == null and o.kind == Opening.Kind.DOOR and o.level == 1 and not o.locked \
				and (o.room_a == living.index or o.room_b == living.index) and o.room_a >= 0 and o.room_b >= 0:
			door = o
	assert_true(door != null, "거실의 안쪽 문")
	door.is_open = false
	sim.doors.sync_blocking()
	var other := sim.fire.comps[door.room_b if door.room_a == living.index else door.room_a]
	var c := sim.units.get_crew(0)
	for ff in c.members():
		ff.path.clear()
		ff.level = 1
		ff.pos = Vector2(door.cells[0]) + Vector2(0.5, 0.5) + (Vector2(living.cells[living.cells.size() / 2]) - Vector2(door.cells[0])).normalized() * 1.5
	var specs: Array = sim.tactical.door_specs
	var side := -1
	for i in specs.size():
		if str(specs[i].id) == "door_side":
			side = i
	# 임무를 받고 문으로 가는 조에게 문 앞 휠 (카드가 뜨기 전)
	var target := other.cells[other.cells.size() / 2]
	sim.issue(TacticalCommand.make("search", [0] as Array[int], Vector3i(target.x, target.y, 1)))
	sim.step_ticks(1)
	sim.issue(EquipmentCommand.make("door_method", [0] as Array[int], -1, door.index, Vector3i(side, 0, 0)))
	assert_true(_until(sim, func() -> bool: return door.is_open, 60.0), "문 앞 휠대로 문을 연다")
	assert_true(not sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.id == "DOOR-CLOSED-01"), "그 문 질문 카드는 뜨지 않는다")
	assert_true(sim.cards.log.any(func(l: Dictionary) -> bool: return l.id == "DOOR-CLOSED-01" and l.result == "preordered"), "선제지시로 기록")


func test_door_wheel_preempts_waiting_card() -> void:
	var sim := _sim("상급")
	var living := sim.fire.compartment_at(1, LIVING.x, LIVING.y)
	var door: Opening = null
	for o in sim.fire.openings:
		if door == null and o.kind == Opening.Kind.DOOR and o.level == 1 and not o.locked \
				and (o.room_a == living.index or o.room_b == living.index) and o.room_a >= 0 and o.room_b >= 0:
			door = o
	door.is_open = false
	sim.doors.sync_blocking()
	var other := sim.fire.comps[door.room_b if door.room_a == living.index else door.room_a]
	var c := sim.units.get_crew(0)
	for ff in c.members():
		ff.path.clear()
		ff.level = 1
		ff.pos = Vector2(door.cells[0]) + Vector2(0.5, 0.5) + (Vector2(living.cells[living.cells.size() / 2]) - Vector2(door.cells[0])).normalized() * 1.5
	var target := other.cells[other.cells.size() / 2]
	sim.issue(TacticalCommand.make("search", [0] as Array[int], Vector3i(target.x, target.y, 1)))
	assert_true(_until(sim, func() -> bool: return sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.id == "DOOR-CLOSED-01"), 60.0), "닫힌 문 카드가 뜬다")
	var specs: Array = sim.tactical.door_specs
	for i in specs.size():
		if str(specs[i].id) == "door_check":
			sim.issue(EquipmentCommand.make("door_method", [0] as Array[int], -1, door.index, Vector3i(i, 0, 0)))
	sim.step_ticks(1)
	assert_true(not sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.id == "DOOR-CLOSED-01"), "휠을 고르면 카드는 사라진다")
	assert_true(_until(sim, func() -> bool: return door.is_open, 60.0), "가스 확인 시간 뒤 연다")
	assert_eq(sim.events.of_type("card_info_check").size(), 1, "확인 시간 기록")
