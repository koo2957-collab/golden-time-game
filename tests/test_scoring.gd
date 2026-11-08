extends TestSuite
## R5: 평가 배점 (기획안 8장) — 대원안전 30·인명구조 30·재산보호 10·화재진압 10·SOP 준수 20, 치명 판단 → 최대 B


func test_axis_weights() -> void:
	var data: Dictionary = JsonData.load_file(Evaluator.RULES_PATH)
	var w := {}
	for a: Dictionary in data.axes:
		w[a.id] = int(a.weight)
	assert_eq(w, {"safety": 30, "rescue": 30, "property": 10, "fire": 10, "command": 20}, "기획안 8장 배점")
	assert_eq(str(data.axes[4].name), "SOP 준수", "SOP 준수 축")
	assert_eq(str(data.card_fatal_cap), "B", "치명 판단 상한")


func test_fatal_card_caps_grade() -> void:
	assert_eq(Evaluator.grade_for(95.0, [[90, "S"], [80, "A"], [70, "B"], [60, "C"], [0, "D"]], true, "B"), ["B", true], "95점이라도 B")
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.cards.log = [{"id": "DOOR-BACKDRAFT-01", "title": "백드래프트 징후 문", "grade": "치명", "result": "answered", "sop": "SOP 210-4.5",
		"asked_tick": 0, "answered_tick": 0, "option": "즉시 문을 열고 진입", "debrief": ""}] as Array[Dictionary]
	sim.end_activity("활동 종료 선언")
	var r := Evaluator.evaluate(sim)
	assert_true(Evaluator.GRADE_ORDER.find(str(r.grade)) >= Evaluator.GRADE_ORDER.find("B"), "치명 판단이 있으면 B보다 좋을 수 없다 (%s)" % r.grade)
	var rule: Dictionary = r.rules.filter(func(x: Dictionary) -> bool: return x.id == "command.cards")[0]
	assert_eq(rule.axis, "command", "카드 판정은 SOP 준수 축")
	assert_eq(rule.score, 0.0, "치명 0점")


func test_preorder_counted_in_detail() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.cards.log = [{"grade": "최선", "result": "preordered"}, {"grade": "최선", "result": "preordered"}, {"grade": "허용", "result": "answered"}] as Array[Dictionary]
	sim.end_activity("활동 종료 선언")
	var rule: Dictionary = Evaluator.evaluate(sim).rules.filter(func(x: Dictionary) -> bool: return x.id == "command.cards")[0]
	assert_true(str(rule.detail).contains("선제지시로 질문 2건 줄임"), "선제지시 수 (%s)" % rule.detail)
	assert_true(absf(rule.score - 2.5 / 3.0) < 0.01, "선제지시 = 최선, 허용 = 0.5")
