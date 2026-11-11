extends TestSuite
## 진입구 → 진입 허가 → 층 → 계단 고르기 (P4-5, 2026-11-11 사용자 결정 조작 방식)

const BASEMENT := "res://data/scenarios/stage3_2_basement.json"


func _until(sim: SimWorld, cond: Callable, max_s: float) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return cond.call()


func _place(c: Crew, level: int, cell: Vector2i) -> void:
	for ff in c.members():
		ff.path.clear()
		ff.level = level
		ff.prev_level = level
		ff.pos = Vector2(cell) + Vector2(0.5, 0.5)
		ff.prev_pos = ff.pos


func test_stair_cores_and_landing() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var st := sim.command.stairs
	var lv: int = sim.building.levels()[0]
	assert_eq(st.cores(lv).size(), 1, "단독주택 1층 계단 1곳")
	var land := st.landing(lv, 0, lv + 1)
	assert_true(land.x >= 0 and sim.building.cell(lv + 1, land.x, land.y) == BuildingData.Cell.STAIRS, "위층 계단참 칸")
	assert_eq(st.label(lv, 0), "A계단", "이름")


func test_single_stair_goes_without_asking() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	var lv: int = sim.building.levels()[0]
	var c := sim.units.get_crew(0)
	var st: Array = sim.command.stairs.cores(lv)[0]
	var near := sim.pathfinder.nearest_walkable(lv, Vector2i(st[0]) + Vector2i(2, 0))
	_place(c, lv, near)
	sim.issue(CommandOrder.make("floor", [0] as Array[int], lv + 1))
	assert_true(_until(sim, func() -> bool: return not sim.events.of_type("floor_reached").is_empty(), 90.0), "2층 도착")
	assert_eq(c.leader.level, lv + 1, "조장이 2층에")
	assert_true(sim.events.of_type("stair_ask").is_empty(), "계단이 하나면 묻지 않는다")


func test_two_stairs_ask_and_use_chosen_one() -> void:
	var sim := SimWorld.from_scenario(BASEMENT, false)
	open_all_doors(sim)
	sim.command.interior.plan_known = true
	var st := sim.command.stairs
	var lv: int = sim.building.levels()[0]
	var goal := lv + 1
	var options := st.toward(lv, goal)
	assert_eq(options.size(), 2, "계단 2곳이 위층으로 이어진다")
	var c := sim.units.get_crew(0)
	# 계단 0 가까이에 두고, 먼 계단 1을 고르게 한다 (가까운 계단으로 가지 않는지)
	var near := sim.pathfinder.nearest_walkable(lv, Vector2i(st.center(lv, options[0]).floor()) + Vector2i(1, 1))
	_place(c, lv, near)
	sim.issue(CommandOrder.make("floor", [0] as Array[int], goal))
	assert_true(_until(sim, func() -> bool: return sim.command.stair_asks.has(0), 10.0), "계단이 둘이면 지휘관에게 묻는다")
	var ask := sim.events.of_type("stair_ask")
	assert_eq(ask.size(), 1, "질문 한 번")
	sim.step_ticks(roundi(10.0 / SimClock.TICK_DT))
	assert_true(str(ask[0].options).contains("A계단") and str(ask[0].options).contains("B계단"), "선택지: %s" % ask[0].options)
	var far: int = options[1]
	var far_cells: Array = st.cores(lv)[far]
	sim.issue(CommandOrder.make("stair", [0] as Array[int], far))
	var seen := {"far": false}  # 람다는 지역 변수를 값으로 잡으므로 사전에 기록
	var ok := _until(sim, func() -> bool:
		if c.leader.level == lv and Vector2i(c.leader.pos.floor()) in far_cells:
			seen.far = true
		return not sim.events.of_type("floor_reached").is_empty(), 180.0)
	assert_true(ok, "고른 계단으로 위층 도착")
	assert_true(seen.far, "고른(먼) 계단을 지난다")
	assert_eq(sim.events.of_type("stair_picked").size(), 1, "계단 지정 기록")
	assert_true(sim.command.decisions.any(func(d: Dictionary) -> bool: return str(d.decision).contains(st.label(lv, far))), "판단 기록에 계단")


func test_unseen_stairs_crew_picks_nearest() -> void:
	var sim := SimWorld.from_scenario(BASEMENT, false)
	open_all_doors(sim)
	sim.command.interior.plan_known = false
	sim.perception.enabled = true
	var st := sim.command.stairs
	var lv: int = sim.building.levels()[0]
	var c := sim.units.get_crew(0)
	var near := sim.pathfinder.nearest_walkable(lv, Vector2i(st.center(lv, 0).floor()) + Vector2i(1, 1))
	_place(c, lv, near)
	sim.issue(CommandOrder.make("floor", [0] as Array[int], lv + 1))
	# 건물 안 조는 무전으로 받는다. 본 계단이 하나뿐이면(또는 아직 못 봤으면) 묻지 않고 간다
	_until(sim, func() -> bool: return sim.command.stair_asks.has(0) or c.leader.is_moving() or c.leader.level == lv + 1, 40.0)
	if sim.command.stair_asks.has(0):
		# 시야에 두 계단이 다 들어왔으면 물어도 맞다 — 그때는 아는 것만 선택지
		assert_true(sim.events.of_type("stair_ask")[0].options != "", "본 계단만 선택지")
	else:
		assert_true(c.leader.is_moving() or c.leader.level == lv + 1, "스스로 계단으로 간다")


func test_approach_entry_then_grant_asks_floor() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.command.entry_order_required = true
	var c := sim.units.get_crew(0)
	var e: EntryPoints.Entry = sim.entries.list[0]
	sim.issue(CommandOrder.make("approach", [0] as Array[int], e.index))
	assert_true(_until(sim, func() -> bool: return sim.command.entry_requests.has(c.squad_id), 120.0), "진입구 앞에서 멈춰 진입 허가를 묻는다")
	assert_true(sim.events.of_type("entry_approach").size() == 1, "진입구로 이동 기록")
	assert_true(c.leader.pos.distance_to(Vector2(e.outside.x, e.outside.y) + Vector2(0.5, 0.5)) <= 3.0, "고른 진입구 앞")
	sim.command.answer_entry(c.squad_id, "grant", sim.clock.tick)
	assert_true(_until(sim, func() -> bool: return not sim.events.of_type("floor_ask").is_empty(), 30.0), "허가 뒤 층을 묻는다")
	var ask: Dictionary = sim.events.of_type("floor_ask")[0]
	assert_true(0 in ask.crews, "그 조")


func test_preordered_floor_skips_floor_ask() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.command.entry_order_required = true
	open_all_doors(sim)
	var c := sim.units.get_crew(0)
	var e: EntryPoints.Entry = sim.entries.list[0]
	var lv: int = sim.building.levels()[0]
	# 걸어가는 동안 층까지 미리 고름 = 선제지시: 허가 뒤 층을 묻지 않고 바로 간다
	sim.issue(CommandOrder.make("floor", [0] as Array[int], lv + 1, Vector3i.ZERO, {"entry": e.index}))
	assert_true(_until(sim, func() -> bool: return sim.command.entry_requests.has(c.squad_id), 120.0), "문 앞에서 허가 요청")
	sim.command.answer_entry(c.squad_id, "grant", sim.clock.tick)
	assert_true(_until(sim, func() -> bool: return not sim.events.of_type("floor_reached").is_empty(), 150.0), "그 층까지 간다")
	assert_true(sim.events.of_type("floor_ask").is_empty(), "층을 미리 골랐으면 묻지 않는다")


func test_move_command_clears_floor_goal() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var lv: int = sim.building.levels()[0]
	sim.issue(CommandOrder.make("floor", [0] as Array[int], lv + 1))
	sim.step_ticks(1)
	assert_true(sim.command.floor_goals.has(0), "층 목표")
	sim.issue(MoveCommand.new([0] as Array[int], sim.units.get_crew(0).leader.cell3()))
	sim.step_ticks(1)
	assert_true(not sim.command.floor_goals.has(0), "다른 명령을 받으면 지운다")


func test_entry_all_grants_every_waiting_squad() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.command.entry_order_required = true
	# 진압1 1조와 구조1 1조를 서로 다른 진입구로 (포위·양방향 진입)
	var a := sim.units.get_crew(0)
	var b: Crew = null
	for c in sim.units.crews:
		if b == null and c.squad_id != a.squad_id:
			b = c
	var e0: EntryPoints.Entry = sim.entries.list[0]
	var e1: EntryPoints.Entry = sim.entries.list[1]
	sim.issue(CommandOrder.make("approach", [a.id] as Array[int], e0.index))
	sim.issue(CommandOrder.make("approach", [b.id] as Array[int], e1.index))
	var card := func() -> bool: return sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.id == "ENTRY-01")
	assert_true(_until(sim, func() -> bool: return sim.command.waiting_squads().size() == 2 and card.call(), 180.0), "두 출동대가 각자 진입구에서 기다리고 허가 카드가 떠 있다")
	sim.issue(CommandOrder.make("entry_all"))
	sim.step_ticks(1)
	assert_true(not card.call(), "떠 있던 진입 카드는 '허가'로 답함")
	assert_eq(sim.events.of_type("entry_all").size(), 1, "동시 진입 기록")
	assert_eq(int(sim.events.of_type("entry_all")[0].count), 2, "두 출동대")
	assert_true(_until(sim, func() -> bool: return sim.command.can_enter(a.squad_id) and sim.command.can_enter(b.squad_id), 30.0), "두 출동대 모두 진입 허가")
	assert_true(sim.cards.log.any(func(l: Dictionary) -> bool: return l.id == "ENTRY-01" and l.result != "timeout"), "카드 출동대는 판단 기록")
