extends TestSuite
## M7c-1: 튜토리얼 시나리오·단계 안내판

const TUTORIAL := "res://data/scenarios/tutorial_basics.json"


func _ui(sim: SimWorld) -> TutorialUi:
	var sel := SelectionController.new()
	var ui := TutorialUi.new()
	ui.setup(sim, sel, str(sim.scenario.tutorial))
	return ui


func test_tutorial_scenario_valid_and_first() -> void:
	var errors := ScenarioLoader.validate(TUTORIAL)
	assert_true(errors.is_empty(), "튜토리얼 시나리오 오류 없음 (%s)" % [errors])
	var list := ScenarioLoader.list()
	assert_eq(str(list[0].path), TUTORIAL, "시작 화면 맨 위가 튜토리얼")
	var sim := SimWorld.from_scenario(TUTORIAL)
	assert_eq(sim.rescue.victims.size(), 1, "구조대상자는 아이 한 명")


func test_steps_advance_in_order() -> void:
	var sim := SimWorld.from_scenario(TUTORIAL)
	var ui := _ui(sim)
	assert_true(ui.steps.size() >= 10, "단계 %d개" % ui.steps.size())
	ui.check()
	assert_eq(ui.index, 0, "처음에는 출동 지령 단계")
	sim.step_ticks(40)
	ui.check()
	assert_eq(str(ui.current().check), "declared", "시간이 지나면 지휘권 선언 단계")
	# 뒤 단계(진입 명령)를 먼저 해도 앞 단계가 끝나기 전에는 넘어가지 않는다
	sim.events.add(sim.clock.tick, "entry_ordered", {})
	ui.check()
	assert_eq(str(ui.current().check), "declared", "앞 단계가 먼저")
	ui.selection.free()
	ui.free()


func test_completed_steps_skip_and_finish() -> void:
	var sim := SimWorld.from_scenario(TUTORIAL)
	var ui := _ui(sim)
	var data: Dictionary = JsonData.load_file(str(sim.scenario.tutorial))
	sim.step_ticks(40)
	# 시뮬레이션 진행 없이 기록만 더한다 (무전 보고로 읽히지 않게 마지막에)
	for s: Dictionary in data.steps:
		if s.check == "event":
			sim.events.add(sim.clock.tick, str(s.event), {})
	ui.check()
	assert_eq(str(ui.current().check), "declared", "선언 전에는 멈춤")
	assert_true(not ui.finished, "아직 끝나지 않음")
	ui.selection.free()
	ui.free()
