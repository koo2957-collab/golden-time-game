extends TestSuite
## 명령판의 분대 명령이 게임에서 실제로 동작하는가 (2026-11-26 사용자: "대원들의 명령과 행동이 게임에서 동작이 되는지도 확인해줘").
## 화면(명령판·우클릭)이 내는 것과 같은 명령 객체를 내고, 정해진 시간 안에 대원이 그 일을 시작하는지
## (임무·무전 사건·상태 변화)를 본다. 명령마다 새 판으로 — 서로 영향을 주지 않게

const TUTORIAL := "res://data/scenarios/sop214_1_day_living.json"
const SQUADS := "res://data/scenarios/dev_squad_house_fire.json"


## 모든 분대를 차에서 내려 펌프차 옆 바깥에 세운 판
func _ready_sim(path := TUTORIAL) -> SimWorld:
	var sim := SimWorld.from_scenario(path, false)
	sim.step_ticks(5)
	# 차량은 모두 현장에 (도착 연출 없이)
	for v in sim.units.vehicles:
		v.away = false
	# 대원은 펌프차 옆 바깥 길에 (진입구 바로 안쪽에 세우면 건물 안으로 친다)
	var at := Vector2i(sim.units.vehicles[0].pos.floor())
	var ground := sim.building.levels()[0]
	var k := 0
	for c in sim.units.crews:
		for ff in c.members():
			var cell := sim.pathfinder.nearest_walkable(ground, at + Vector2i(k % 6 - 3, -2 - k / 6))
			ff.aboard = false
			ff.level = ground
			ff.pos = Vector2(cell) + Vector2(0.5, 0.5)
			ff.prev_pos = ff.pos
			ff.path.clear()
			k += 1
	sim.step_ticks(1)
	return sim


func _crew_of_type(sim: SimWorld, type: String) -> Crew:
	for c in sim.units.crews:
		if sim.units.squads[c.squad_id].type == type and c.workers().size() >= 2:
			return c
	return null


## cond 가 될 때까지 진행 (최대 seconds). 됐으면 true
func _until(sim: SimWorld, cond: Callable, seconds: float) -> bool:
	for i in roundi(seconds / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return bool(cond.call())


func _events_of(sim: SimWorld, type: String, crew_id := -1) -> Array:
	return sim.events.of_type(type).filter(func(e: Dictionary) -> bool:
		return crew_id < 0 or int(e.get("crew_id", crew_id)) == crew_id or str(e.get("crew", "")).begins_with(sim.units.crew_name(sim.units.get_crew(crew_id)).split(" ")[0]))


# --- 임무 (Q W E R) ---

func test_q_search_floor() -> void:
	var sim := _ready_sim()
	var c := _crew_of_type(sim, "구조대")
	sim.issue(CommandOrder.make("floor_mission", [c.id], 1, Vector3i.ZERO, {"kind": "search", "entry": -1}))
	assert_true(_until(sim, func() -> bool: return sim.rescue.task_of_crew(c.id) is RescueSystem.SearchTask, 120.0),
		"Q 인명검색 → 2분 안에 방 검색 시작 (사건: %s)" % str(sim.events.entries.slice(-5).map(func(e: Dictionary) -> String: return str(e.type))))


func test_w_attack_floor() -> void:
	var sim := _ready_sim()
	var c := _crew_of_type(sim, "진압대")
	sim.issue(CommandOrder.make("floor_mission", [c.id], 1, Vector3i.ZERO, {"kind": "attack", "entry": -1}))
	assert_true(_until(sim, func() -> bool: return sim.water.held_hose(c.id) != null, 60.0), "W 화재진압 → 호스를 꺼낸다")
	var spraying := func() -> bool:
		var h := sim.water.held_hose(c.id)
		return h != null and h.flowing
	assert_true(_until(sim, spraying, 300.0), "W 화재진압 → 5분 안에 방수 시작")
	# D ▸ 방수 중지 (명령판 대기 하위 칸)
	sim.issue(EquipmentCommand.make("stop", [c.id] as Array[int]))
	sim.step_ticks(2)
	assert_true(not spraying.call(), "D ▸ 방수 중지 → 멈춘다")


func test_e_check_below() -> void:
	var sim := _ready_sim("res://data/scenarios/sop213_1_apartment_3f.json")
	var c := _crew_of_type(sim, "구조대")
	if c == null or sim.tactical.layout == null or sim.tactical.layout.units.is_empty():
		assert_true(true, "세대 배치가 없는 시나리오 — 건너뜀")
		return
	var lv := sim.fire_floor_reported() if sim.fire_floor_reported() > 1 else 2
	var fires: Dictionary = sim.tactical._fire_rooms(lv)
	var target := Vector3i(-1, -1, -1)
	for idx: int in fires:
		target = Vector3i(sim.fire.comps[idx].cells[0].x, sim.fire.comps[idx].cells[0].y, lv)
	if target.x < 0:
		var mid := Vector2i(sim.building.footprint(lv).get_center())
		target = Vector3i(mid.x, mid.y, lv)
	sim.issue(TacticalCommand.make("check_below", [c.id] as Array[int], target))
	assert_true(_until(sim, func() -> bool: return not _events_of(sim, "tactical_start", c.id).is_empty(), 30.0), "E 직하층 확인 → 임무 시작")


func test_r_watch_after_all_clear() -> void:
	var sim := _ready_sim()
	var c := _crew_of_type(sim, "진압대")
	sim.step_ticks(roundi(60.0 / SimClock.TICK_DT))
	# 거실 불을 끄고 완진 선언 상태로
	for i in sim.fire.grid.burning.duplicate():
		sim.fire.grid.apply_water(i, 1000.0, 1.0)
	sim.step_ticks(2)
	sim.phases.phase = PhaseSystem.Phase.OPERATIONS
	assert_true(sim.phases.declare_all_clear(sim.clock.tick), "완진 선언")
	sim.issue(CommandOrder.make("floor_mission", [c.id], 1, Vector3i.ZERO, {"kind": "watch", "entry": -1}))
	assert_true(_until(sim, func() -> bool: return sim.rekindle.watch_of_crew(c.id) != null, 180.0), "R 재발화 감시 → 3분 안에 감시 시작")


# --- 행동 (A S D F) ---

func test_a_exterior() -> void:
	var sim := _ready_sim()
	var c := _crew_of_type(sim, "진압대")
	var win: Opening = null
	for o in sim.fire.openings:
		if win == null and o.kind == Opening.Kind.WINDOW and o.level == 1 and o.room_b == Opening.OUTSIDE:
			win = o
	sim.issue(TacticalCommand.make("exterior", [c.id] as Array[int], Vector3i(win.cells[0].x, win.cells[0].y, 1)))
	var placed := func() -> bool:
		var h := sim.water.held_hose(c.id)
		return not sim.events.of_type("exterior_post").is_empty() or not sim.events.of_type("exterior_cycle").is_empty() or (h != null and h.flowing)
	assert_true(_until(sim, placed, 300.0), "A 경계 → 5분 안에 관창 배치·방수")


func test_s_ppv() -> void:
	var sim := _ready_sim()
	var c := _crew_of_type(sim, "진압대")
	var e: EntryPoints.Entry = sim.entries.list[0]
	sim.issue(EquipmentCommand.make("ppv", [c.id] as Array[int], -1, -1, Vector3i(e.door.x, e.door.y, e.outside.z)))
	var answered := func() -> bool:
		for t in ["ppv_start", "ppv_no_exhaust", "ppv_exhaust_order", "ppv_exhaust_none", "ppv_no_door"]:
			if not sim.events.of_type(t).is_empty():
				return true
		return false
	assert_true(_until(sim, answered, 180.0), "S 배연 → 송풍기 설치 또는 배기구 없음 알림 (%s)" % str(sim.events.entries.slice(-4).map(func(x: Dictionary) -> String: return str(x.type))))


func test_d_hold_and_report() -> void:
	var sim := _ready_sim()
	var c := _crew_of_type(sim, "구조대")
	sim.issue(CommandOrder.make("floor_mission", [c.id], 1, Vector3i.ZERO, {"kind": "search", "entry": -1}))
	_until(sim, func() -> bool: return sim.rescue.task_of_crew(c.id) != null or sim.tactical.task_of_crew(c.id) != null, 120.0)
	sim.issue(TacticalCommand.make("hold", [c.id] as Array[int]))
	sim.step_ticks(5)
	assert_true(sim.tactical.task_of_crew(c.id) == null and sim.rescue.task_of_crew(c.id) == null, "D ▸ 그 자리 대기 → 하던 임무를 멈춘다")
	sim.issue(CommandOrder.make("report_request", [], 0, Vector3i.ZERO, {"crews": [c.id]}))
	var heard := func() -> bool:
		return sim.command.radio.history.any(func(m: Radio.Message) -> bool: return m.body.contains("보고")) \
			or sim.command.radio.queue.any(func(m: Radio.Message) -> bool: return m.body.contains("보고"))
	assert_true(_until(sim, heard, 30.0), "D ▸ 보고 요청 → 무전")


func test_f_withdraw() -> void:
	var sim := _ready_sim()
	var c := _crew_of_type(sim, "구조대")
	sim.issue(CommandOrder.make("floor_mission", [c.id], 1, Vector3i.ZERO, {"kind": "search", "entry": -1}))
	_until(sim, func() -> bool: return sim.command.interior.crew_inside(c.id), 120.0)
	assert_true(sim.command.interior.crew_inside(c.id), "철수 점검 준비: 건물 안에 들어갔다")
	sim.issue(TacticalCommand.make("withdraw", [c.id] as Array[int]))
	assert_true(_until(sim, func() -> bool: return not sim.command.interior.crew_inside(c.id), 180.0), "F 철수 → 3분 안에 건물 밖")


# --- 편성 (Z X C V) ---

func test_z_x_split_and_merge() -> void:
	var sim := _ready_sim(SQUADS)
	var squad_id := -1
	for s in sim.units.squads:
		if squad_id < 0 and sim.regroup_reason(s.id, true) == "":
			squad_id = s.id
	assert_true(squad_id >= 0, "나눌 수 있는 4명 분대")
	if squad_id < 0:
		return
	sim.issue(CommandOrder.make("regroup", [squad_id] as Array[int], 1))
	assert_true(_until(sim, func() -> bool: return sim.units.squads[squad_id].crews.size() == 2, 60.0), "Z 나누기 → 두 조")
	sim.issue(CommandOrder.make("regroup", [squad_id] as Array[int], 0))
	assert_true(_until(sim, func() -> bool: return sim.units.squads[squad_id].crews.size() == 1, 60.0), "X 합치기 → 한 분대")


func test_c_v_detach_and_recall() -> void:
	var sim := _ready_sim(SQUADS)
	var squad_id := -1
	var task := ""
	for s in sim.units.squads:
		for spec: Dictionary in sim.solo_specs():
			if squad_id < 0 and sim.solo_reason(s.id, str(spec.id)) == "":
				squad_id = s.id
				task = str(spec.id)
	assert_true(squad_id >= 0, "한 명 보낼 수 있는 분대·임무 (%s)" % task)
	if squad_id < 0:
		return
	sim.issue(CommandOrder.make("solo", [squad_id] as Array[int], 0, Vector3i.ZERO, {"task": task}))
	assert_true(_until(sim, func() -> bool: return sim.units.solo_of(sim.units.squads[squad_id]) != null, 60.0), "C 한 명 보내기 (%s) → 한 명이 나간다" % task)
	sim.issue(CommandOrder.make("recall", [squad_id] as Array[int]))
	assert_true(_until(sim, func() -> bool: return sim.units.solo_of(sim.units.squads[squad_id]) == null, 300.0), "V 복귀 → 분대로 돌아온다")


# --- 우클릭 상황 행동 ---

func test_rightclick_pump_hose() -> void:
	var sim := _ready_sim()
	var c := _crew_of_type(sim, "진압대")
	var pump := sim.water._nearest_pump(c.leader.pos)
	sim.water.lay_hose(c.id, pump, sim.clock.tick)
	var h := fetch_hose(sim, c.id)
	assert_true(h != null and h.points.size() >= 2, "펌프차 우클릭 → 후면에서 호스를 꺼내 연장")


func test_rightclick_door_open() -> void:
	var sim := _ready_sim()
	var c := _crew_of_type(sim, "구조대")
	var e: EntryPoints.Entry = sim.entries.list[0]
	var door := sim.fire.opening_at(Vector3i(e.door.x, e.door.y, e.outside.z))
	door.is_open = false
	door.locked = false
	sim.doors.sync_blocking()
	sim.doors.request(c.id, Vector3i(e.door.x, e.door.y, e.outside.z), true, sim.clock.tick)
	assert_true(_until(sim, func() -> bool: return door.is_open, 120.0), "문 우클릭 → 2분 안에 연다")
