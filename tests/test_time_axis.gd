extends TestSuite
## P9-1 [2] 시간축 (기획안 4-4·5-8): 현장 시계 배속, 출동 단계(신고→선착 도착 4분) 동안 불 진행, 신고 후·발화 후 시계, 카드 제한시간은 실제 초


func test_field_time_scale_by_realism() -> void:
	for pair: Array in [["훈련", 1.5], ["실전", 2.0], ["악조건", 2.5]]:
		var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 3)
		sim.apply_realism(pair[0])
		assert_eq(sim.field_scale, pair[1], "%s 현장 시계 ×%.1f" % pair)
	var plain := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	assert_eq(plain.field_scale, 1.0, "난이도 없이(테스트) 만들면 1")


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
	assert_eq(card.deadline_tick - card.asked_tick, roundi(8.0 * 2.0 / SimClock.TICK_DT), "긴급 8초(실제) = 현장 16초 (×2 시계)")
