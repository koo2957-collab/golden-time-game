extends TestSuite
## M9c: 골목 안 주택 — 진입·회차 판단 (SOP 101-2.1 ⑨, 200-3.1.1)

const PATH := "res://data/scenarios/sop214_4_alley.json"


func test_scenario_and_map() -> void:
	assert_eq(ScenarioLoader.validate(PATH), PackedStringArray(), "시나리오 검증")
	var sim := SimWorld.from_scenario(PATH)
	assert_eq(sim.command.observed_truth().access, "진입 가능, 회차 불가", "상황보고 ⑨ 정답")
	assert_eq(sim.building.cell(1, 35, 10), BuildingData.Cell.ROAD, "골목은 차도")
	assert_eq(sim.building.cell(1, 20, 22), BuildingData.Cell.WALL, "앞마당 담장")
	assert_true(sim.pathfinder.find_path(Vector3i(20, 23, 1), Vector3i(20, 21, 1)).size() > 20, "큰길에서 앞마당은 골목으로 돌아서 간다")


func test_all_options_fit() -> void:
	var opts: Array = SimWorld.from_scenario(PATH).scenario.approach.options
	for i in opts.size():
		var sim := SimWorld.from_scenario(PATH)
		Placement.apply(sim, i, 0)
		assert_eq(int(sim.command.placement.moved), 2, "'%s' 차량 2대가 섬" % opts[i].name)


func test_alley_pump_can_only_reverse_out() -> void:
	var sim := SimWorld.from_scenario(PATH)
	sim.command.resources.clear_schedule()
	Placement.apply(sim, 1, 0)
	var pump := sim.units.vehicles[0]
	assert_eq(pump.heading, Vector2(0, -1), "골목 안쪽을 보고 섬")
	assert_true(sim.water.order_vehicle_move(pump.id, Vector2i(35, 31), 1), "큰길 쪽으로 이동 명령")
	assert_true(pump.reversing, "돌릴 수 없어 후진으로만 나온다")
	sim.step_ticks(roundi(60.0 / SimClock.TICK_DT))
	assert_true(pump.pos.y > 25.0, "후진으로 큰길까지 (y %.1f)" % pump.pos.y)
	var report := Evaluator.evaluate(sim)
	var rule: Dictionary = report.rules.filter(func(r: Dictionary) -> bool: return r.id == "fire.placement")[0]
	assert_eq(rule.score, 0.5, "골목 진입 배치 판정")
	assert_true(str(rule.detail).contains("회차"), "회차 언급")
