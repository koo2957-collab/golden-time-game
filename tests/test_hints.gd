extends TestSuite
## M7a: 교육 모드 힌트 (data/sop/hints.json) — 트리거, 한 번만, 대기열, 평가 모드에서는 꺼짐


func _hint(sim: SimWorld, on: bool) -> HintUi:
	var h := HintUi.new()
	h.setup(sim, on)
	return h


func test_hint_data_valid() -> void:
	var data: Dictionary = JsonData.load_file(HintUi.HINTS_PATH)
	var ids := {}
	for h: Dictionary in data.hints:
		for key in ["id", "trigger", "sop", "title", "text", "why", "advice"]:
			assert_true(str(h.get(key, "")) != "", "%s: %s 있음" % [h.get("id", "?"), key])
		assert_true(not ids.has(h.trigger), "트리거 중복 없음: %s" % h.trigger)
		ids[h.trigger] = true
	assert_true(ids.size() >= 12, "힌트 %d종" % ids.size())


func test_triggers_once_and_queue() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	var h := _hint(sim, true)
	var opened: Array[bool] = []
	h.dialog_changed.connect(func(o: bool) -> void: opened.append(o))
	h._check()
	assert_true(not h.visible_hint(), "처음에는 힌트 없음")
	sim.step_ticks(610)
	h._check()
	assert_true(h.visible_hint() and h.shown.has("declare_delay"), "1분 동안 지휘권 미선언 → 힌트")
	assert_eq(opened, [true] as Array[bool], "힌트가 뜨면 게임을 멈춘다")
	sim.issue(CommandOrder.make("entry", [0]))
	sim.step_ticks(80)
	h._check()
	assert_true(h.shown.has("entry_without_rit"), "RIT 없이 진입 → 다음 힌트 대기")
	h.close_hint()
	assert_true(h.visible_hint(), "대기 중인 힌트를 이어서 보여 준다")
	h.close_hint()
	assert_true(not h.visible_hint(), "모두 닫음")
	assert_eq(opened[-1], false, "닫으면 게임 재개")
	h._check()
	assert_true(not h.visible_hint(), "같은 힌트는 한 번만")
	h.free()


func test_disabled_in_evaluation_mode() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.step_ticks(610)
	var h := _hint(sim, false)
	h._process(1.0)
	assert_true(not h.visible_hint() and h.shown.is_empty(), "평가 모드에서는 힌트 없음")
	h.on_end_dialog()
	assert_true(h.shown.is_empty(), "종료 힌트도 없음")
	h.free()


func test_end_without_par_hint() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var h := _hint(sim, true)
	h.on_end_dialog()
	assert_true(h.shown.has("end_without_par"), "인원점검 없이 종료하려 하면 힌트")
	h.free()
