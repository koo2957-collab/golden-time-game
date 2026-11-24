extends TestSuite
## 화재진압은 호스부터 (2026-11-24 사용자·현직 소방관): 진압 지시를 받은 밖의 조는 문으로 가지 않고 자기 펌프차 후면에서
## 호스를 꺼낸 뒤 깔면서 현장으로 간다. 전에는 문을 열고 건물에 들어선 뒤에야 차로 돌아가 호스를 꺼냈다 (수관을 만드는 곳이
## 방수 시작(start_spray)뿐이었다). docs/motions.md E1 → E4 순서.


func _outside(sim: SimWorld, crew_id: int) -> Crew:
	var c := sim.units.get_crew(crew_id)
	var e: EntryPoints.Entry = sim.entries.main_entries()[0]
	for ff in c.members():
		ff.aboard = false
		ff.level = e.level
		ff.prev_level = e.level
		ff.pos = Vector2(e.outside.x, e.outside.y) + Vector2(0.5, 0.5)
		ff.prev_pos = ff.pos
		ff.path.clear()
	return c


func _types(sim: SimWorld) -> Array:
	return sim.events.entries.map(func(e: Dictionary) -> String: return str(e.type))


## 지시 창의 층 화재진압: 문 앞에 서 있던 조도 먼저 자기 차 후면으로 가서 호스를 꺼내고, 그 뒤에 진입구로 간다
func test_floor_attack_fetches_hose_before_door() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var c := _outside(sim, 0)
	var e: EntryPoints.Entry = sim.entries.main_entries()[0]
	sim.issue(CommandOrder.make("floor_mission", [0] as Array[int], e.level, Vector3i.ZERO, {"kind": "attack", "entry": e.index}))
	sim.step_ticks(1)
	var h := sim.water.hose_of_crew(0)
	assert_true(h != null and h.to_outlet and sim.water.fetching(0), "지시를 받자마자 수관 연장 — 펌프차 후면으로")
	if h == null:
		return
	var v := sim.units.get_vehicle(h.vehicle_id)
	assert_true(v != null and v.squad_id == c.squad_id, "자기 출동대의 펌프차에서 꺼낸다 (%s)" % (v.short_name if v else "없음"))
	assert_true(c.leader.is_moving() and Vector3i(c.leader.path.back()) == h.points[0], "문이 아니라 차 후면으로 간다")
	assert_true(sim.command.floor_missions.get(0, "") == "attack" and not sim.command.approach.has(0), "임무는 받았고, 진입구로는 아직 가지 않는다")
	# 꺼내는 동안: 진입구로 가지 않고 문도 건드리지 않는다
	var touched_door := false
	var went_early := false
	for i in 1200:
		if not sim.water.fetching(0):
			break
		sim.step_ticks(1)
		touched_door = touched_door or (sim.water.fetching(0) and sim.doors.task_of_crew(0) != null)
		went_early = went_early or (sim.water.fetching(0) and sim.command.approach.has(0))
	assert_true(not sim.water.fetching(0), "호스를 다 꺼냄")
	assert_true(not touched_door and not went_early, "꺼내는 동안에는 문·진입구로 가지 않는다")
	assert_true(_types(sim).has("hose_laid"), "차 후면에서 꺼냄 (보고)")
	# 다 꺼내면 깔면서 진입구로
	sim.step_ticks(3)
	assert_true(sim.command.approach.get(0, -1) == e.index, "꺼낸 뒤 고른 진입구로 간다")
	var before := h.points.size()
	sim.step_ticks(30)
	assert_true(h.points.size() > before, "호스를 깔면서 간다 (%d → %d칸)" % [before, h.points.size()])
	var order := _types(sim)
	assert_true(order.find("hose_laid") < order.find("entry_approach"), "순서: 호스 → 진입구")
	assert_true(sim.command.floor_missions.get(0, "") == "attack", "층 임무는 그대로")


## 방을 찍어 진압 지시: 호스를 꺼내 오기 전에는 문을 열러 가지 않는다
func test_room_attack_waits_for_hose_before_doors() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.tactical.set_level("입문")
	_outside(sim, 0)
	var living := sim.fire.comps.filter(func(r: Compartment) -> bool: return r.level == 1 and r.display_name().contains("거실"))
	assert_true(not living.is_empty(), "거실")
	if living.is_empty():
		return
	var mid: Vector2i = (living[0] as Compartment).rect.get_center()
	sim.issue(TacticalCommand.make("attack", [0], Vector3i(mid.x, mid.y, 1)))
	sim.step_ticks(1)
	assert_true(sim.water.fetching(0), "수관 연장부터")
	var t := sim.tactical.task_of_crew(0)
	assert_true(t != null and t.hose_wait, "진압 임무는 호스를 기다린다")
	var touched_door := false
	for i in 1200:
		if not sim.water.fetching(0):
			break
		sim.step_ticks(1)
		touched_door = touched_door or (sim.water.fetching(0) and sim.doors.task_of_crew(0) != null)
	assert_true(not touched_door, "꺼내는 동안에는 문을 열러 가지 않는다")
	assert_true(sim.events.of_type("tactical_halt").is_empty(), "기다리는 동안 '지시 바람'으로 멈추지 않는다")
	# 꺼낸 뒤에는 문을 열고(잠긴 현관은 입문 수준에서 스스로 부순다) 들어가 방수한다
	var sprayed := false
	for i in 3000:
		sim.step_ticks(1)
		var h := sim.water.hose_of_crew(0)
		if h != null and h.flowing and not h.approaching:
			sprayed = true
			break
	assert_true(sprayed, "호스를 가지고 가서 방수")
	var order := _types(sim)
	assert_true(order.find("hose_laid") >= 0 and (order.find("door_forced") < 0 or order.find("hose_laid") < order.find("door_forced")), "순서: 호스 → 문")


## 이미 호스가 있는 조는 기다리지 않고 바로 간다 / 옥내 방수구를 쓰는 층은 차에서 꺼내 가지 않는다
func test_no_wait_when_hose_ready() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	_outside(sim, 0)
	assert_true(sim.water.ensure_hose(0, 1, sim.clock.tick), "수관 연장")
	fetch_hose(sim, 0)
	var e: EntryPoints.Entry = sim.entries.main_entries()[0]
	sim.issue(CommandOrder.make("floor_mission", [0] as Array[int], e.level, Vector3i.ZERO, {"kind": "attack", "entry": e.index}))
	sim.step_ticks(1)
	assert_true(sim.command.approach.has(0) and sim.command._hose_first.is_empty(), "호스가 있으면 바로 진입구로")
	assert_true(sim.water.ensure_hose(0, 1, sim.clock.tick) and sim.water.hoses.size() == 1, "이미 있으면 새로 만들지 않는다")
	assert_true(not sim.water.uses_outlet(1), "1층은 방수구를 쓰지 않는다")
	# 검색 임무는 호스와 상관없다
	var sim2 := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	_outside(sim2, 2)
	sim2.issue(CommandOrder.make("floor_mission", [2] as Array[int], e.level, Vector3i.ZERO, {"kind": "search", "entry": e.index}))
	sim2.step_ticks(1)
	assert_true(sim2.water.hose_of_crew(2) == null and sim2.command.approach.has(2), "인명검색은 호스 없이 바로 진입구로")
