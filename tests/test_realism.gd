extends TestSuite
## R2: 난이도 훈련·실전·악조건 (기획안 3-3, 8장)

const HOUSE := "res://data/scenarios/sop214_1_day_living.json"


func test_training_doubles_card_time() -> void:
	# 시나리오 제한 시간은 없다 (P11-1). 훈련 난이도는 질문 카드 제한시간만 2배
	var sim := SimWorld.from_scenario(HOUSE)
	sim.apply_realism("훈련")
	var real := SimWorld.from_scenario(HOUSE)
	real.apply_realism("실전")
	assert_eq(sim.cards.time_factor, real.cards.time_factor * 2.0, "훈련은 카드 시간 2배")


func test_harsh_conditions() -> void:
	var sim := SimWorld.from_scenario(HOUSE)
	var wind := sim.exposure.wind_mps
	var arrival := sim.command.resources.upcoming(0)
	sim.apply_realism("악조건")
	assert_true(sim.exposure.wind_mps >= maxf(wind * 2.0, 5.0) - 0.01, "강풍 (%.1f → %.1f m/s)" % [wind, sim.exposure.wind_mps])
	assert_eq(sim.water.hydrants_out.size(), sim.building.hydrants.size(), "소화전 모두 고장")
	assert_true(sim.shuttle.available(), "원거리 수원으로 순환보수 가능")
	var later := sim.command.resources.upcoming(0)
	assert_true(not arrival.is_empty() and later[0].eta_s >= arrival[0].eta_s * 1.4, "후착대 지연 (%.0f → %.0f초)" % [arrival[0].eta_s, later[0].eta_s])
	assert_eq(sim.events.of_type("realism").size(), 1, "난이도 기록")


func test_no_scenario_time_limit() -> void:
	# 제한 시간은 없다 (기획안 8-3, P11-1)
	for s in ScenarioLoader.list():
		if str(s.source) != "기본":
			continue
		var data: Dictionary = JsonData.load_file(s.path)
		assert_true(not data.get("evaluation", {}).has("time_limit_s"), "%s 제한 시간 없음" % s.id)


func test_replay_keeps_realism() -> void:
	var sim := SimWorld.from_scenario(HOUSE, true, 77)
	sim.apply_realism("악조건")
	sim.step_ticks(50)
	var r := Replay.begin(HOUSE, sim.issued, 50, 77, "", "악조건")
	while not r.step(100):
		pass
	assert_eq(r.sim.realism, "악조건", "다시 하기도 같은 난이도")
	assert_eq(r.sim.water.hydrants_out, sim.water.hydrants_out, "같은 조건")
	var report := Evaluator.evaluate(sim)
	assert_eq(str(report.realism), "악조건", "결과에 난이도 기록")
