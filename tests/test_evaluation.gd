extends TestSuite
## M6a: 활동 종료, SOP 판정 규칙, 평가·등급 상한, 디브리핑 자료, 결과 저장


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	return sim


func _rule(report: Dictionary, id: String) -> Dictionary:
	for r: Dictionary in report.rules:
		if r.id == id:
			return r
	return {}


func test_rule_library_matches_scenario() -> void:
	var data: Dictionary = JsonData.load_file(Evaluator.RULES_PATH)
	var ids := {}
	var e := Evaluator.new()
	for r: Dictionary in data.rules:
		ids[r.id] = true
		assert_true(e.has_method("_check_" + str(r.check)), "판정 함수 있음: %s" % r.check)
		assert_true(str(r.text) != "" and str(r.sop) != "", "조항 원문·번호: %s" % r.id)
	var scenario: Dictionary = JsonData.load_file(DEV_SCENARIO_PATH)
	for id in scenario.evaluation.rules:
		assert_true(ids.has(id), "시나리오 규칙이 라이브러리에 있음: %s" % id)
	var w := 0.0
	for a: Dictionary in data.axes:
		w += float(a.weight)
	assert_eq(w, 100.0, "축 가중치 합 100")


func test_end_order_and_time_limit() -> void:
	var sim := _sim()
	sim.issue(CommandOrder.make("end"))
	sim.step_ticks(1)
	assert_true(sim.ended(), "활동 종료 선언")
	var t := sim.clock.tick
	sim.step_ticks(10)
	assert_eq(sim.clock.tick, t, "종료 후에는 시뮬레이션이 멈춘다")
	var sim2 := _sim()
	sim2.time_limit_tick = 20
	sim2.step_ticks(30)
	assert_eq([sim2.ended(), sim2.end_reason, sim2.ended_tick], [true, "제한 시간 종료", 20], "제한 시간이 지나면 자동 종료")


func test_early_end_report() -> void:
	var sim := _sim()
	sim.step_ticks(600)
	sim.end_activity("활동 종료 선언")
	var r := Evaluator.evaluate(sim)
	assert_eq(r.rules.size(), 27, "규칙 27개 판정 (R1 종료 체계 3개 포함)")
	assert_eq(_rule(r, "safety.ff_down").score, 1.0, "행동 불능 없음")
	assert_eq(_rule(r, "command.declare").score, 0.0, "선언하지 않으면 0점")
	assert_eq(_rule(r, "fire.extinguish").score, 0.0, "연소 중 종료면 완진 0점")
	assert_true(_rule(r, "rescue.survival").score < 0.01, "구조 못함")
	assert_true(not _rule(r, "safety.withdraw").applicable, "방어 전환이 없으면 해당 없음")
	assert_true(r.grade == "D", "일찍 끝내면 낮은 등급 (%s, %.1f점)" % [r.grade, r.points])
	assert_true(_rule(r, "rescue.survival").violated, "아무도 구조하지 못하면 등급 상한 대상 (SOP 214-2.1)")
	assert_true(r.strengths.size() >= 1, "잘한 점은 반드시 하나 이상 (SOP 113-3.1)")
	assert_true(r.weaknesses.size() >= 1 and r.weaknesses.size() <= 3, "고칠 점 1~3개")
	assert_true(str(r.weaknesses[0].advice) != "", "다음 행동 제안")
	assert_true(r.hidden.victims.size() == 2 and str(r.hidden.victims[0]).contains("실제 위치"), "구조대상자 실제 위치 공개")
	var wrong: Array = r.hidden.statements.filter(func(x: String) -> bool: return x.contains("틀림"))
	assert_eq(wrong.size(), 1, "틀린 진술 공개")
	assert_true(r.timeline.size() >= 2, "타임라인")
	assert_eq(r.plan.declared, "선언하지 않음", "① 계획")


func test_checks_with_state() -> void:
	var sim := _sim()
	sim.step_ticks(20)
	# 2층 방을 1층 거실보다 먼저 검색한 것으로 만든다 → 순서 어긋남
	var living: Compartment
	var upper: Compartment
	for c in sim.fire.comps:
		if c.id == "1F_living":
			living = c
		elif c.id == "2F_room2":
			upper = c
	upper.searched_tick = 5
	living.searched_tick = 10
	var v := sim.rescue.victims[1]
	v.state = Victim.State.RESCUED
	v.state_at_rescue = Victim.State.CONSCIOUS
	v.rescued_tick = 15
	sim.end_activity("테스트")
	var r := Evaluator.evaluate(sim)
	var order := _rule(r, "rescue.search_order")
	assert_eq(order.score, 0.0, "직상층을 화점실보다 먼저 검색하면 순서 위반 (%s)" % order.detail)
	assert_true(not _rule(r, "rescue.survival").violated, "구조 50%는 상한 기준(50% 미만)에 걸리지 않는다")
	assert_true(str(order.detail).contains("거실(화점실)"), "범주 표시")
	assert_eq(_rule(r, "rescue.survival").score, 0.5, "2명 중 1명 의식 있는 상태로 구조")
	assert_eq(_rule(r, "rescue.time").score, 0.5, "구조 시간 (1명 기준 안, 1명 못함)")


func test_grade_cap() -> void:
	var grades := [[90, "S"], [80, "A"], [70, "B"], [60, "C"], [0, "D"]]
	assert_eq(Evaluator.grade_for(92.0, grades, false, "C"), ["S", false], "92점 S")
	assert_eq(Evaluator.grade_for(92.0, grades, true, "C"), ["C", true], "중대 안전 위반이면 C 상한 (SOP 108-1.2)")
	assert_eq(Evaluator.grade_for(40.0, grades, true, "C"), ["D", false], "상한보다 낮으면 그대로")
	var sim := _sim()
	sim.events.add(5, "ff_down", {"crew": "진압1 1조 김도현", "reason": "공기 소진"})
	sim.end_activity("테스트")
	var r := Evaluator.evaluate(sim)
	assert_true(_rule(r, "safety.ff_down").violated, "중대 위반 표시")
	assert_true(Evaluator.GRADE_ORDER.find(r.grade) >= Evaluator.GRADE_ORDER.find("C"), "C보다 좋은 등급이 아니다 (%s)" % r.grade)
	assert_eq(r.weaknesses[0].title, "대원 행동 불능 없음", "상한 규칙 위반이 고칠 점 맨 앞")


func test_save_report() -> void:
	var sim := _sim()
	sim.end_activity("테스트")
	var r := Evaluator.evaluate(sim)
	var path := Evaluator.save(r)
	assert_true(path.begins_with("user://reports/dev_house_fire_"), "저장 경로 (%s)" % path)
	var back: Variant = JsonData.load_file(path)
	assert_true(back is Dictionary and back.grade == r.grade, "다시 읽을 수 있음")
	DirAccess.remove_absolute(path)
