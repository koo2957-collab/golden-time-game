extends TestSuite
## R8: 도면·미니맵 — 구조는 직접 밝힌다, 관리사무소(방재실)에서 도면·수신반 발화층, 도면과 실제 차이 (기획안 9-1, SOP 235)

const APT := "res://data/scenarios/sop213_1_apartment_3f.json"


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(APT)
	sim.command.resources.clear_schedule()
	return sim


func _put(sim: SimWorld, crew_id: int, at: Vector2, level := 1) -> Crew:
	var c := sim.units.get_crew(crew_id)
	for i in c.members().size():
		var ff := c.members()[i]
		ff.pos = at + Vector2(i * 0.5, 0)
		ff.prev_pos = ff.pos
		ff.level = level
		ff.prev_level = level
	sim.perception.update(sim.clock.tick)
	return c


func test_structure_is_revealed_by_crews() -> void:
	var sim := _sim()
	assert_true(not sim.plan.known, "처음에는 도면이 없다")
	assert_true(sim.plan.structure_seen(1, 6, 13), "외벽은 밖에서 보인다")
	assert_true(not sim.plan.structure_seen(3, 20, 13), "안쪽 벽은 모른다 (3층 301호)")
	assert_true(not sim.command.interior.room_known(Vector3i(48, 7, 3)), "본 적 없는 방(302호 주방, 북쪽 창)은 층 단위")


func test_office_gives_plan_and_fire_floor() -> void:
	var sim := _sim()
	assert_true(not sim.plan.office.is_empty(), "관리사무소(방재실) 있음")
	sim.step_ticks(30)
	var cell: Vector2i = sim.plan.office.cell
	_put(sim, 0, Vector2(cell) + Vector2(0.5, 0.5))
	sim.step_ticks(roundi(30.0 / SimClock.TICK_DT))
	assert_true(not sim.plan.known, "60초 전에는 아직")
	assert_true(sim.plan.dwell_progress() > 0.3, "확인 중 진행률 (%.2f)" % sim.plan.dwell_progress())
	sim.step_ticks(roundi(35.0 / SimClock.TICK_DT))
	assert_true(sim.plan.known, "머물면 도면 확보")
	assert_true(sim.command.interior.plan_known, "도면이 있으면 방 단위 임무")
	assert_true(sim.command.interior.room_known(Vector3i(48, 7, 3)), "본 적 없는 방도 방 단위로")
	var panel := sim.events.of_type("panel_fire_floor")
	assert_eq(panel.size(), 1, "수신반 발화층 확인")
	assert_true(not panel.is_empty() and str(panel[0].floors).contains("3층"), "3층 화재 신호 (%s)" % [panel])
	var lines: Array = Evaluator.evaluate(sim).intel_lines
	assert_true(not lines.is_empty() and str(lines[0]).contains("도면 확보"), "디브리핑 기록 (%s)" % [lines])


func test_plan_differs_from_reality() -> void:
	var sim := _sim()
	assert_eq(sim.plan.plan_cell(3, 10, 17), BuildingData.Cell.WALL, "도면에는 발코니 벽")
	assert_eq(sim.building.cell(3, 10, 17), BuildingData.Cell.FLOOR, "실제로는 터져 있다")
	sim.plan.acquire("상황실", 0)
	assert_eq(sim.events.of_type("plan_acquired")[0].crew, "119종합상황실", "지휘대 도착 = 상황실에서 수신")
	assert_eq(sim.events.of_type("panel_fire_floor").size(), 0, "상황실 도면은 수신반 정보가 없다")
	_put(sim, 0, Vector2(10.5, 16.5), 3)
	sim.step_ticks(2)
	var found := sim.events.of_type("plan_diff_found")
	assert_eq(found.size(), 1, "대원이 보면 도면과 다른 곳을 발견")
	assert_true(not found.is_empty() and str(found[0].note).contains("발코니"), "무엇이 다른지")
	var lines: Array = Evaluator.evaluate(sim).intel_lines
	assert_true(lines.any(func(l: String) -> bool: return l.contains("대원이 확인함")), "디브리핑에 차이 확인")


func test_house_has_no_office() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	assert_true(sim.plan.office.is_empty(), "단독주택은 방재실이 없다 — 끝까지 도면 없이")
	sim.step_ticks(10)
	assert_true(not sim.plan.known, "도면 없음")
