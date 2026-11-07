extends TestSuite
## M6b: 잔불정리·재발화 (SOP 202-6)


## 거실 소파가 30초 탄 뒤 물로 모두 끈 상태. 불씨가 반드시 숨도록 확률을 1로 둔다
func _doused_sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	sim.rekindle._chance = 1.0
	sim.step_ticks(300)
	assert_true(sim.fire.grid.burning.size() > 0, "소파가 탄다")
	for i in sim.fire.grid.burning.duplicate():
		sim.fire.grid.apply_water(i, 1000.0, 1.0)
	sim.step_ticks(2)
	return sim


func _living(sim: SimWorld) -> Compartment:
	for c in sim.fire.comps:
		if c.id == "1F_living":
			return c
	return null


func test_embers_rekindle_if_left() -> void:
	var sim := _doused_sim()
	var rk := sim.rekindle
	assert_true(rk.embers.size() > 0, "물로 끈 셀에 불씨가 숨는다 (%d곳)" % rk.embers.size())
	assert_eq(sim.fire.grid.burning.size(), 0, "겉으로는 꺼짐")
	assert_true(rk.spotted_cells().is_empty(), "열화상으로 보기 전에는 표시되지 않는다")
	sim.step_ticks(roundi(500.0 / SimClock.TICK_DT))
	assert_true(sim.events.of_type("rekindle").size() >= 1, "그대로 두면 재발화")
	assert_true(rk.rekindles >= 1, "재발화 기록")


func test_thermal_spot_and_overhaul() -> void:
	var sim := _doused_sim()
	var rk := sim.rekindle
	var crew := sim.units.get_crew(0)  # 진압1 1조: 열화상카메라
	assert_true(crew.thermal_camera, "열화상 조")
	for ff in crew.members():
		ff.path.clear()
		ff.pos = Vector2(14.5, 15.5)
		ff.prev_pos = ff.pos
	sim.step_ticks(10)
	assert_eq(sim.events.of_type("ember_spotted").size(), 1, "방에 들어가면 불씨를 찾는다")
	assert_eq(rk.spotted_cells().size(), rk.embers.size(), "찾은 불씨 표시")
	sim.issue(EquipmentCommand.make("overhaul", [0], -1, -1, Vector3i(14, 15, 1)))
	sim.step_ticks(roundi((rk.overhaul_seconds() + 8.0) / SimClock.TICK_DT))
	assert_eq(rk.embers.size(), 0, "잔불정리로 불씨 제거")
	assert_eq(sim.events.of_type("overhaul_done").size(), 1, "잔불정리 완료 기록")
	assert_true(_living(sim).overhauled_tick >= 0, "방에 잔불정리 표시")
	sim.step_ticks(roundi(500.0 / SimClock.TICK_DT))
	assert_eq(sim.events.of_type("rekindle").size(), 0, "재발화 없음")
	sim.end_activity("테스트")
	var r := Evaluator.evaluate(sim)
	for rule: Dictionary in r.rules:
		if rule.id == "fire.overhaul":
			assert_eq(rule.score, 1.0, "잔불정리 판정 (%s)" % rule.detail)
