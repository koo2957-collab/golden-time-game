extends TestSuite
## M8b-1: 아파트화재 (SOP 213) — 5층 계단식 아파트, 연결송수관(200-3.3.1), 현관 방화문 파괴(213-2.3)

const APT := "res://data/scenarios/sop213_1_apartment_3f.json"


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(APT)
	sim.command.resources.clear_schedule()
	return sim


func _place(sim: SimWorld, crew_id: int, at: Vector2, level: int) -> Crew:
	var c := sim.units.get_crew(crew_id)
	for i in c.members().size():
		var ff := c.members()[i]
		ff.path.clear()
		ff.level = level
		ff.pos = at + Vector2(i, 0)
		ff.prev_pos = ff.pos
	return c


func test_building_and_scenario() -> void:
	assert_eq(ScenarioLoader.validate(APT), PackedStringArray(), "시나리오 검증")
	var sim := _sim()
	var b := sim.building
	assert_eq(b.levels().size(), 5, "5층")
	assert_true(b.has_standpipe() and b.outlets.size() == 5, "송수구 + 층별 방수구")
	assert_true(b.is_fire_door(Vector2i(27, 14)), "현관 방화문")
	assert_eq(b.footprint(1), Rect2i(6, 4, 48, 16), "건물 외곽")
	var names := sim.fire.comps.map(func(c: Compartment) -> String: return c.display_name())
	assert_true("3층 301호 거실" in names and "5층 계단실" in names, "세대·계단실 구획 (%s)" % [names.slice(0, 5)])
	assert_eq(sim.command.observed_truth().floors, "4층 이상", "층수 정답")


func test_fire_door_takes_longer() -> void:
	var sim := _sim()
	var c := _place(sim, 0, Vector2(29.5, 14.5), 4)
	sim.doors.request(c.id, Vector3i(27, 14, 4), true, 0)
	var apt_door := sim.doors.task_of(sim.fire.opening_at(Vector3i(27, 14, 4)))
	var house := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	house.doors.request(0, Vector3i(13, 20, 1), true, 0)
	var house_door := house.doors.task_of(house.fire.opening_at(Vector3i(13, 20, 1)))
	assert_true(apt_door != null and house_door != null, "파괴 작업 시작")
	assert_eq(apt_door.required, house_door.required * 2.0, "방화문은 2배")


func test_fdc_and_outlet_hose() -> void:
	var sim := _sim()
	var w := sim.water
	assert_true(not w.connect_fdc(0, 0), "기본 위치(서쪽)에서는 송수구가 멀다")
	assert_true(Placement.apply(sim, 1, 0), "건너편 차로 배치")
	assert_true(w.connect_fdc(0, 0), "송수구 연결")
	var c := _place(sim, 0, Vector2(29.5, 15.5), 3)
	assert_true(w.start_spray(c.id, Vector3i(12, 15, 3), HoseLine.Pattern.FOG, 1), "3층 방수 시작")
	var h := w.hose_of_crew(c.id)
	assert_eq(h.outlet, 2, "3층 방수구에서 수관")
	assert_eq(h.vehicle_id, 0, "물은 송수구에 연결한 펌프차에서")
	var tank := sim.units.vehicles[0].tank_l
	sim.step_ticks(300)
	assert_true(sim.units.vehicles[0].tank_l < tank, "펌프차 물이 줄어든다")
	var rule: Dictionary = Evaluator.evaluate(sim).rules.filter(func(r: Dictionary) -> bool: return r.id == "fire.standpipe")[0]
	assert_eq(rule.score, 1.0, "연결송수관 활용 판정")


func test_without_fdc_falls_back_to_pump() -> void:
	var sim := _sim()
	var c := _place(sim, 0, Vector2(29.5, 15.5), 3)
	assert_true(not sim.water.lay_hose_outlet(c.id, 2, 0), "송수구 미연결이면 방수구 사용 불가")
	assert_eq(sim.events.of_type("fdc_not_connected").size(), 1, "보고")
	sim.water.start_spray(c.id, Vector3i(12, 15, 3), HoseLine.Pattern.FOG, 1)
	var h := sim.water.hose_of_crew(c.id)
	assert_true(h == null or h.outlet < 0, "펌프차 수관으로 (또는 길이 부족)")
