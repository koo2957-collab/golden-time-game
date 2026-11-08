extends TestSuite
## M8a: 선착 차량 배치 선택 (SOP 200-3.1.1)

const SCENARIOS := ["res://data/scenarios/sop214_1_day_living.json", "res://data/scenarios/sop214_2_night_upstairs.json",
	"res://data/scenarios/sop214_3_kitchen_lpg.json", "res://data/scenarios/tutorial_basics.json"]


func test_all_options_fit_on_road() -> void:
	for path in SCENARIOS:
		var opts: Array = SimWorld.from_scenario(path).scenario.approach.options
		for i in opts.size():
			var sim := SimWorld.from_scenario(path)
			assert_true(Placement.apply(sim, i, 0), "%s 배치 %d 적용" % [path.get_file(), i])
			assert_eq(int(sim.command.placement.moved), opts[i].vehicles.size(), "%s '%s' 모든 차량이 도로에 겹치지 않고 섬" % [path.get_file(), opts[i].name])


func test_placement_command_and_rule() -> void:
	var sim := SimWorld.from_scenario(SCENARIOS[0])
	sim.issue(CommandOrder.make("placement", [], 0))
	sim.step_ticks(1)
	var pump := sim.units.vehicles[0]
	assert_eq(pump.pos, Vector2(20.5, 30.5), "정면 배치")
	assert_true(not Placement.apply(sim, 1, 1), "한 번만 고른다")
	assert_eq(sim.events.of_type("placement").size(), 1, "배치 기록")
	var report := Evaluator.evaluate(sim)
	var rule: Dictionary = report.rules.filter(func(r: Dictionary) -> bool: return r.id == "fire.placement")[0]
	assert_eq(rule.score, 0.4, "정면 배치는 감점")
	assert_true(str(rule.detail).contains("낙하물"), "이유 설명")


func test_late_placement_rejected_and_dev_unaffected() -> void:
	var sim := SimWorld.from_scenario(SCENARIOS[0])
	sim.step_ticks(Placement.MAX_TICK + 1)
	assert_true(not Placement.apply(sim, 1, sim.clock.tick), "도착 직후에만 고를 수 있음")
	var dev := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	assert_true(Placement.options(dev).is_empty(), "개발용 시나리오는 배치 보기 없음")
	var report := Evaluator.evaluate(dev)
	assert_true(report.rules.all(func(r: Dictionary) -> bool: return r.id != "fire.placement"), "규칙도 없음")
