extends TestSuite
## R2: 난이도 훈련·실전·악조건 (기획안 3-3, 8장)

const HOUSE := "res://data/scenarios/sop214_1_day_living.json"


func test_training_doubles_time_limit() -> void:
	var sim := SimWorld.from_scenario(HOUSE)
	var base := sim.time_limit_tick
	assert_eq(base, roundi(1500.0 / SimClock.TICK_DT), "실전 기준 제한 시간 25분")
	sim.apply_realism("훈련")
	assert_eq(sim.time_limit_tick, base * 2, "훈련은 2배")
	var real := SimWorld.from_scenario(HOUSE)
	real.apply_realism("실전")
	assert_eq(real.time_limit_tick, base, "실전은 그대로")


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


func test_all_scenarios_25_to_30_min() -> void:
	for s in ScenarioLoader.list():
		if str(s.id) == "dev_house_fire" or str(s.source) != "기본":
			continue
		var data: Dictionary = JsonData.load_file(s.path)
		var lim := float(data.evaluation.time_limit_s)
		assert_true(lim >= 1500.0 and lim <= 1800.0, "%s 제한 시간 25~30분 (%d초)" % [s.id, lim])


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
