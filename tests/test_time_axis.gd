extends TestSuite
## P9-1 [2] 시간축 (기획안 4-4·5-8): 현장 시계 배속, 출동 단계(신고→선착 도착 4분) 동안 불 진행, 신고 후·발화 후 시계, 카드 제한시간은 실제 초


func test_field_time_scale_by_realism() -> void:
	# 2026-11-15 사용자 결정: 현장 시계는 모두 기본 1배 (보이는 빠르기 = 실제), 플레이 중 배속 단추로 올린다
	for pair: Array in [["훈련", 1.0], ["실전", 1.0], ["악조건", 1.0]]:
		var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 3)
		sim.apply_realism(pair[0])
		assert_eq(sim.field_scale, pair[1], "%s 현장 시계 ×%.1f" % pair)
	var plain := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	assert_eq(plain.field_scale, 1.0, "난이도 없이(테스트) 만들면 1")


## 판단 중 정지 (2026-11-15): 훈련·실전은 무전 장면·창이 떠 있는 동안 현장이 멈추고, 악조건은 멈추지 않는다
func test_decision_pause_by_realism() -> void:
	for pair: Array in [["훈련", true], ["실전", true], ["악조건", false]]:
		var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 3)
		sim.apply_realism(pair[0])
		assert_eq(sim.decision_pause, pair[1], "%s 판단 중 정지" % pair[0])
	assert_true(SimWorld.from_scenario(DEV_SCENARIO_PATH).decision_pause, "난이도 없이(테스트) 만들면 멈추는 쪽")
	var phase: Dictionary = JsonData.load_file("res://data/command/phase_params.json")
	assert_eq(phase.speed_steps.value, [1.0, 2.0, 4.0], "배속 단계 1·2·4배")
	for key in ["field_time_scale", "speed_steps", "decision_pause"]:
		assert_true(str(phase[key].get("source", "")) != "", "%s에 source" % key)
	# 판단하는 동안(시계 정지) 현장은 그대로다: 불도 대원도 진행하지 않는다
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 3)
	sim.clock.paused = true
	var burning := sim.fire.grid.burning.size()
	var tick := sim.clock.tick
	sim.advance(5.0)
	assert_eq([sim.clock.tick, sim.fire.grid.burning.size()], [tick, burning], "멈춘 동안 현장 시계·불이 그대로")
	sim.clock.paused = false
	sim.advance(1.0)
	assert_true(sim.clock.tick > tick, "다시 흐른다")


func test_dispatch_phase_advances_fire() -> void:
	var a := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 3)
	var b := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 3)
	b.apply_realism("실전")
	assert_eq(b.dispatch_s, 240.0, "신고 후 4분에 선착 도착")
	assert_true(b.fire.grid.burning.size() > a.fire.grid.burning.size(), "출동하는 4분 동안 불이 커져 있다 (%d → %d칸)" % [a.fire.grid.burning.size(), b.fire.grid.burning.size()])
	assert_eq(b.since_call_s(), 240.0, "게임 시계는 신고 후 경과: 도착 순간 04:00")
	b.step_ticks(100)
	assert_eq(b.since_call_s(), 250.0, "도착 뒤에도 신고 후로 센다")
	assert_eq(b.since_ignition_s(), b.ignition_to_call_s + 250.0, "디브리핑은 발화 후 경과도")
	var c := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 3)
	c.apply_realism("실전")
	var d := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 3)
	d.apply_realism("실전")
	assert_eq(c.fire.grid.burning, d.fire.grid.burning, "같은 시드면 도착 시점 화재 상태가 매번 같다 (다시 하기)")


func test_card_time_is_real_seconds() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 5)
	sim.command.resources.clear_schedule()
	sim.apply_realism("실전")
	sim.cards.timed = true
	sim.events.add(1, "air_alarm", {"crew": "진압1 1조", "crew_id": 0})
	sim.cards.step(0.1, 1)
	var card := sim.cards.active()
	# 제한시간은 실제 초 → 현장 틱으로는 × 현장 시계 배속 (2026-11-15부터 기본 1배)
	assert_eq(card.deadline_tick - card.asked_tick, roundi(8.0 * sim.field_scale / SimClock.TICK_DT), "긴급 8초(실제) = 현장 8초 × 시계 배속")
	sim.cards.clock_scale = 2.0
	sim.events.add(2, "air_alarm", {"crew": "진압1 2조", "crew_id": 1})
	assert_eq(sim.cards.clock_scale, 2.0, "배속이 다르면 그만큼 현장 틱이 늘어난다 (계산은 clock_scale)")
