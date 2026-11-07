extends TestSuite


func test_ticks_at_normal_speed() -> void:
	var clock := SimClock.new()
	assert_eq(clock.consume(0.35), 3, "0.35초 → 3틱")
	assert_eq(clock.consume(0.05), 1, "남은 0.05초와 합쳐 1틱")


func test_speed_multiplier() -> void:
	var clock := SimClock.new()
	clock.speed = 4.0
	assert_eq(clock.consume(0.5), SimClock.MAX_TICKS_PER_FRAME, "4배속 0.5초 → 20틱이지만 프레임당 상한 적용")
	clock = SimClock.new()
	clock.speed = 2.0
	assert_eq(clock.consume(0.25), 5, "2배속 0.25초 → 5틱")


func test_paused() -> void:
	var clock := SimClock.new()
	clock.paused = true
	assert_eq(clock.consume(1.0), 0, "일시정지 중에는 틱이 진행되지 않음")
