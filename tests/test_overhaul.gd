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


## 층 단위 잔불정리 (2026-11-16): 한 방을 마치면 같은 층의 다음 탄 방으로, 남은 방이 없으면 층 완료 보고
func test_floor_overhaul_continues_room_by_room() -> void:
	var sim := _doused_sim()
	var rk := sim.rekindle
	var living := _living(sim)
	# 같은 층의 다른 방 하나에도 탄 자리를 만든다 (가구가 탄 것처럼)
	var other: Compartment = null
	for c in sim.fire.comps:
		if other == null and c.level == 1 and c != living and c.cells.size() >= 4 and not sim.fire.is_exposure_comp(c):
			other = c
	assert_true(other != null, "1층에 다른 방이 있다")
	var g := sim.fire.grid
	var oc: Vector2i = other.cells[0]
	g.state[g.index(1, oc.x, oc.y)] = FuelGrid.State.BURNT
	var first: Vector3i = rk.next_floor_room(1, Vector2(14.5, 15.5))
	assert_true(first.x >= 0, "탄 방이 있다")
	sim.issue(EquipmentCommand.make("overhaul", [0], -1, 1, first))
	var both := func() -> bool: return living.overhauled_tick >= 0 and other.overhauled_tick >= 0
	for i in roundi(400.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if both.call():
			break
	assert_true(both.call(), "한 번 지시로 그 층의 탄 방 둘 다 잔불정리 (거실 %d, %s %d)" % [living.overhauled_tick, other.display_name(), other.overhauled_tick])
	sim.step_ticks(2)
	var done := sim.events.of_type("tactical_done").filter(func(e: Dictionary) -> bool: return str(e.text).contains("잔불정리 완료"))
	assert_eq(done.size(), 1, "층 잔불정리 완료 보고")
	assert_eq(rk.next_floor_room(1, Vector2.ZERO), Vector3i(-1, -1, -1), "남은 방 없음")


## 지시 창 화재진압 (floor_mission): 초진 뒤 그 층에 보이는 불이 없으면 층에 닿았을 때 층 잔불정리로 바뀐다
## (2026-11-17 — 전에는 화면 쪽에서 바로 잔불정리 명령을 내려 진입구·진입 허가를 건너뛰었다)
func test_floor_mission_attack_becomes_overhaul_after_knockdown() -> void:
	var sim := _doused_sim()
	sim.perception.enabled = false
	sim.phases.knockdown_tick = sim.clock.tick
	assert_true(sim.floor_overhaul_target(1, Vector2(14.5, 15.5)).x >= 0, "잔불정리할 방이 있다")
	sim.issue(CommandOrder.make("floor_mission", [0] as Array[int], 1, Vector3i.ZERO, {"kind": "attack", "entry": -1}))
	var started := false
	for i in roundi(120.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if not sim.events.of_type("overhaul_start").is_empty():
			started = true
			break
	assert_true(started, "층에 닿자 잔불정리 시작")
	assert_true(sim.rekindle.tasks.any(func(t: RekindleSystem.OverhaulTask) -> bool: return t.crew_id == 0 and t.floor == 1), "층 단위 잔불정리 작업")
	var attack := sim.events.of_type("tactical_start").filter(func(e: Dictionary) -> bool: return str(e.get("action", "")) == "진압")
	assert_eq(attack.size(), 0, "화재진압(방수)으로 시작하지 않는다")
	# 불이 보이면 그대로 화재진압
	var sim2 := _doused_sim()
	assert_eq(sim2.floor_overhaul_target(1, Vector2.ZERO), Vector3i(-1, -1, -1), "초진 전에는 잔불정리 아님")


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
