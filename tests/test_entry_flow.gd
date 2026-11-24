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


## 이웃 건물 문은 지시 창·가까운 문 고르기에서 빠진다 (2026-11-17 — 진압2가 옆집 거실 문으로 '1층'에 들어가던 버그)
func test_neighbour_door_not_used_for_floor_mission() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/sop214_1_day_living.json", false, 7)
	var nb: Array = sim.entries.list.filter(func(e: EntryPoints.Entry) -> bool: return e.neighbour)
	assert_true(not nb.is_empty(), "이 시나리오에는 옆집 문이 진입구 목록에 있다")
	assert_true(sim.entries.main_entries().all(func(e: EntryPoints.Entry) -> bool: return not e.neighbour), "불난 건물 문만")
	# 옆집 문 바로 앞에 선 분대에게 1층 임무 → 옆집 문이 아니라 불난 건물 문으로
	var e_nb: EntryPoints.Entry = nb[0]
	var c := sim.units.get_crew(0)
	for ff in c.members():
		ff.path.clear()
		ff.aboard = false
		ff.level = e_nb.level
		ff.pos = Vector2(e_nb.outside.x, e_nb.outside.y) + Vector2(0.5, 0.5)
	var near: EntryPoints.Entry = sim.command._approach_entry([0] as Array[int])
	assert_true(near != null and not near.neighbour, "옆집 문 앞에서 골라도 불난 건물 문 (%s)" % (near.name if near else "없음"))
	sim.issue(CommandOrder.make("floor_mission", [0] as Array[int], e_nb.level, Vector3i.ZERO, {"kind": "attack", "entry": -1}))
	sim.step_ticks(1)
	# 화재진압은 호스부터 (2026-11-24): 자기 펌프차 후면에서 호스를 꺼낸 뒤에 진입구로 간다
	assert_true(sim.water.fetching(0) and not sim.command.approach.has(0), "호스를 꺼내는 동안에는 진입구로 가지 않는다")
	fetch_hose(sim, 0, false)
	sim.step_ticks(2)
	var ei := int(sim.command.approach.get(0, -1))
	assert_true(ei >= 0 and not sim.entries.list[ei].neighbour, "가까운 옆집 문 대신 불난 건물 문 (%s)" % (sim.entries.list[ei].name if ei >= 0 else "없음"))
