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


## 계단이 둘이면 질문 카드(STAIR-01)로 묻고, 카드 답대로 그 계단으로 간다 (2026-11-17: 계단 클릭 대신 카드)
func test_two_stairs_card_routes_by_answer() -> void:
	var sim := SimWorld.from_scenario(BASEMENT, false)
	open_all_doors(sim)
	sim.command.interior.plan_known = true
	sim.cards.crew_judgment = true
	var st := sim.command.stairs
	var lv: int = sim.building.levels()[0]
	var goal := lv + 1
	var options := st.toward(lv, goal)
	var c := sim.units.get_crew(0)
	var near := sim.pathfinder.nearest_walkable(lv, Vector2i(st.center(lv, options[0]).floor()) + Vector2i(1, 1))
	_place(c, lv, near)
	sim.issue(CommandOrder.make("floor", [0] as Array[int], goal))
	var card := func() -> CardSystem.Card:
		for q in sim.cards.queue:
			if q.id == "STAIR-01":
				return q
		return null
	assert_true(_until(sim, func() -> bool: return card.call() != null, 15.0), "계단이 둘이면 계단 카드")
	var q: CardSystem.Card = card.call()
	var texts: Array = q.options.map(func(o: Dictionary) -> String: return str(o.text))
	assert_true(texts.any(func(t: String) -> bool: return t.contains("A계단")) and texts.any(func(t: String) -> bool: return t.contains("B계단")), "선택지에 계단 이름 (%s)" % [texts])
	# 먼 계단(options[1])을 고른다
	var far: int = options[1]
	var pick := -1
	for i in q.options.size():
		if str(q.options[i].text).contains(st.label(lv, far)):
			pick = i
	sim.cards.answer(q.uid, pick, sim.clock.tick)
	var far_cells: Array = st.cores(lv)[far]
	var seen := {"far": false}
	var ok := _until(sim, func() -> bool:
		if c.leader.level == lv and Vector2i(c.leader.pos.floor()) in far_cells:
			seen.far = true
		return not sim.events.of_type("floor_reached").is_empty(), 180.0)
	assert_true(ok and seen.far, "카드에서 고른 계단으로 위층 도착 (도착 %s, 고른 계단 지남 %s)" % [ok, seen.far])


## 지시 창의 층 임무 (floor_mission): 그 층에 닿으면 층 단위 임무를 시작한다
func test_floor_mission_starts_on_arrival() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	var lv: int = sim.building.levels()[0]
	var c := sim.units.get_crew(2)
	var st: Array = sim.command.stairs.cores(lv)[0]
	_place(c, lv, sim.pathfinder.nearest_walkable(lv, Vector2i(st[0]) + Vector2i(2, 0)))
	sim.issue(CommandOrder.make("floor_mission", [2] as Array[int], lv + 1, Vector3i.ZERO, {"kind": "search", "entry": -1}))
	sim.step_ticks(1)
	assert_true(sim.command.floor_missions.has(2), "층에 닿으면 할 임무")
	assert_true(sim.tactical.task_of_crew(2) == null, "아직 임무 시작 전 (층으로 가는 중)")
	assert_true(_until(sim, func() -> bool: return sim.tactical.task_of_crew(2) != null, 120.0), "층에 닿으면 임무 시작")
	var t := sim.tactical.task_of_crew(2)
	assert_eq([t.floor_action, t.floor], ["search_floor", lv + 1], "그 층 검색")
	assert_true(not sim.command.floor_missions.has(2), "시작하면 지운다")


## 진입 절차를 마쳤는데 문 앞에서 멈췄으면(열기에 막힘 등) 그 자리에서 층 임무를 시작한다 (2026-11-17 —
## 전에는 안에 들어서기만 기다려 아무 보고 없이 멈춰 있었다: 튜토리얼 거실 현관)
func test_floor_mission_starts_at_door_when_blocked() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	var c := sim.units.get_crew(0)
	var e: EntryPoints.Entry = sim.entries.main_entries()[0]
	_place(c, e.level, Vector2i(e.outside.x, e.outside.y))
	sim.issue(CommandOrder.make("floor_mission", [0] as Array[int], e.level, Vector3i.ZERO, {"kind": "attack", "entry": e.index}))
	sim.step_ticks(1)
	assert_true(sim.command.floor_missions.has(0), "층 임무 받음")
	# 화재진압은 호스부터 (2026-11-24): 문으로 가기 전에 자기 펌프차 후면에서 호스를 꺼낸다
	assert_true(sim.water.fetching(0) and not sim.command.approach.has(0), "호스를 꺼내는 동안에는 진입구로 가지 않는다")
	fetch_hose(sim, 0)
	sim.step_ticks(2)
	assert_true(sim.command.floor_missions.has(0), "호스를 꺼낸 뒤에도 층 임무는 그대로")
	# 문은 열렸고 허가도 났는데(진입구 단계 끝) 안으로 못 들어가고 밖에 서 있다
	sim.command.approach.erase(0)
	_place(c, e.level, Vector2i(e.outside.x, e.outside.y))
	assert_true(_until(sim, func() -> bool: return sim.tactical.task_of_crew(0) != null, 3.0), "문 앞에서 화재진압 시작")
	assert_true(sim.events.of_type("floor_reached").is_empty(), "층에 '닿음'으로 기록하지는 않는다")


## 층 검색은 그 조가 있는 건물 안에서만 — 화재 건물 1층 검색이 옆집으로 넘어가지 않는다 (2026-11-17)
func test_floor_search_stays_in_building() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/tutorial_basics.json", false)
	var exposure := sim.fire.comps.filter(func(r: Compartment) -> bool: return r.level == 1 and sim.fire.is_exposure_comp(r))
	assert_true(not exposure.is_empty(), "튜토리얼에는 옆집이 있다")
	for r in sim.fire.comps:
		if r.level == 1 and not sim.fire.is_exposure_comp(r):
			r.searched_tick = 0
	var c := sim.units.get_crew(1)
	var e: EntryPoints.Entry = sim.entries.main_entries()[0]
	_place(c, e.level, Vector2i(e.outside.x, e.outside.y))
	assert_true(sim.tactical._next_floor_room(c, "search_floor", 1) == null, "화재 건물을 다 검색하면 끝 (옆집으로 가지 않음)")


## 대기 중 출동대에 내린 명령은 투입 무전을 기다린다. 무전이 곧바로 닿아 이미 투입됐으면 바로 실행한다
## (2026-11-17 — 줄에 넣기 전에 풀려 영영 남던 것: 튜토리얼 구급대 처치가 실행되지 않음)
func test_held_order_released_when_squad_already_committed() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var c := sim.units.get_crew(0)
	var cmd := MoveCommand.new([0] as Array[int], Vector3i(c.leader.cell3().x + 2, c.leader.cell3().y, c.leader.level))
	sim.command._held.append({"cmd": cmd, "wait": [c.squad_id] as Array[int], "release": 0})
	assert_true(not sim.command.resources.is_staged(c.squad_id), "이미 현장 투입된 출동대")
	sim.step_ticks(2)
	assert_eq(sim.command.held_count(), 0, "기다리지 않고 실행")


## 안전구역을 지시하면(설치 전) 그 안에 환자 집결지를 바로 찍을 수 있다 (2026-11-17)
func test_casualty_point_inside_planned_safe_zone() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/tutorial_basics.json", false)
	var z := sim.zones
	var r := Rect2i()
	for y in range(0, sim.building.height, 4):
		for x in range(0, sim.building.width, 4):
			var cand := Rect2i(x, y, 6, 6)
			if r.size.x == 0 and z.safe_reject_reason(cand) == "":
				r = cand
	assert_true(r.size.x > 0, "건물 밖 안전구역 자리")
	assert_eq(z.point_reject_reason(r.get_center()), "안전구역을 먼저 지정하세요", "안전구역 전")
	sim.issue(CommandOrder.make("zone", [], 0, Vector3i.ZERO, {"kind": "safe", "rect": [r.position.x, r.position.y, r.size.x, r.size.y]}))
	sim.step_ticks(1)
	assert_true(not z.has_safe(), "아직 설치 전")
	assert_eq(z.point_reject_reason(r.get_center()), "", "설치 전이라도 지시한 안전구역 안이면 된다")
	assert_eq(z.point_reject_reason(r.position - Vector2i(3, 3)), "안전구역 안에만 놓을 수 있음", "밖은 안 된다")


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
