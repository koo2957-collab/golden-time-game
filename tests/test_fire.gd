extends TestSuite
## 화재 시뮬레이션 검증. 교재(소방전술 I) 수치 범위를 기준으로 한다.

const MINUTE_TICKS := 600


func _open_run() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	return sim


func _room(sim: SimWorld, display_name: String) -> Compartment:
	for c in sim.fire.comps:
		if c.display_name() == display_name:
			return c
	return null


func _first_event(sim: SimWorld, type: String, room: String) -> Dictionary:
	for e in sim.events.of_type(type):
		if e.room == room:
			return e
	return {}


func test_layout_built_from_plan() -> void:
	var sim := _open_run()
	assert_eq(sim.fire.comps.size(), 14, "방 12개 + 옆집 2개가 구획으로 만들어짐")
	var living := _room(sim, "1층 거실")
	var kinds := {}
	for oi in living.openings:
		var o := sim.fire.openings[oi]
		kinds[o.kind_name()] = kinds.get(o.kind_name(), 0) + 1
	assert_eq(kinds.get("문", 0), 3, "거실 문 3개 (주방·복도·현관)")
	assert_eq(kinds.get("창", 0), 3, "거실 창 3개 (남쪽 2 · 서쪽 1)")
	var front := sim.fire.opening_at(Vector3i(13, 20, 1))
	assert_true(front != null and front.room_b == Opening.OUTSIDE and not front.is_open, "현관문은 외부와 연결, 처음엔 닫힘")
	var stair_found := false
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.STAIR:
			stair_found = sim.fire.comps[o.room_a].display_name() == "1층 계단실" and sim.fire.comps[o.room_b].display_name() == "2층 계단실"
	assert_true(stair_found, "1층·2층 계단실이 계단으로 연결")
	for c in sim.fire.comps:
		assert_true(c.flashover_temp >= 483.0 and c.flashover_temp <= 649.0, "%s 플래시오버 임계온도가 교재 범위 안" % c.display_name())


func test_living_room_fire_follows_textbook_stages() -> void:
	var sim := _open_run()
	var living := _room(sim, "1층 거실")
	var max_temp := 0.0
	for minute in 25:
		sim.step_ticks(MINUTE_TICKS)
		max_temp = maxf(max_temp, living.t_upper)
	var fo := _first_event(sim, "flashover", "1층 거실")
	assert_true(not fo.is_empty(), "거실 플래시오버 발생")
	if not fo.is_empty():
		var minutes: float = fo.time_s / 60.0
		assert_true(minutes >= 5.0 and minutes <= 10.0, "거실 플래시오버 5~10분 (결과 %.1f분)" % minutes)
		assert_true(fo.temp_c >= 483 and fo.temp_c <= 649, "플래시오버 온도 483~649℃")
		var smoke_2f := _first_event(sim, "smoke", "2층 복도")
		assert_true(not smoke_2f.is_empty() and smoke_2f.time_s < fo.time_s, "플래시오버 전에 연기가 2층 복도까지 확산")
	assert_true(max_temp >= 800.0 and max_temp <= 900.0, "최성기 최고 온도 800~900℃ (결과 %.0f℃)" % max_temp)
	var order: Array[String] = []
	for e in sim.events.of_type("stage"):
		if e.room == "1층 거실":
			order.append(e.to)
	assert_eq(order.slice(0, 4), ["발화기", "성장기", "플래시오버", "최성기"] as Array[String], "거실 단계 순서")
	# 2026-11-13 (P1 화재하중 Eurocode 780MJ/㎡): 가연물이 실제 수준이라 25분에는 아직 최성기 — 쇠퇴기는 그 뒤에 온다 (예전: 15분쯤 쇠퇴)
	assert_eq(living.stage, Compartment.Stage.FULLY_DEVELOPED, "25분에도 최성기 (%s)" % living.stage_name())
	# 그 뒤는 화재 계산만 돌린다 (전체를 돌리면 벽돌조 붕괴 판정으로 36분쯤 '전소'로 끝나 쇠퇴기를 못 본다)
	var extra := 0
	while living.stage != Compartment.Stage.DECAY and extra < 60:
		for i in MINUTE_TICKS:
			sim.fire.step(SimClock.TICK_DT, sim.clock.tick)
		extra += 1
	assert_eq(living.stage, Compartment.Stage.DECAY, "가연물이 줄면 쇠퇴기로 (발화 %d분, 화재1 22쪽)" % (25 + extra))
	assert_true(25 + extra >= 30, "최성기가 30분 넘게 이어진다 (%d분)" % (25 + extra))
	assert_true(not sim.events.of_type("window_broken").is_empty(), "유리창 파손 발생")


func test_sealed_room_becomes_ventilation_limited() -> void:
	var sim := _open_run()
	var living := _room(sim, "1층 거실")
	for oi in living.openings:
		var o := sim.fire.openings[oi]
		if o.kind == Opening.Kind.DOOR:
			o.is_open = false
		elif o.kind == Opening.Kind.WINDOW:
			o.breakable = false
	sim.step_ticks(MINUTE_TICKS * 10)
	assert_true(living.o2_percent() < 12.0, "밀폐된 거실 산소 12%% 미만 (결과 %.1f%%)" % living.o2_percent())
	assert_true(living.gas_percent() >= 12.5, "미연소가스가 CO 폭발하한(12.5%%) 이상 축적 (결과 %.1f%%)" % living.gas_percent())
	assert_true(living.combustion_eff < 0.2, "불꽃연소가 거의 꺼짐")
	assert_true(living.t_upper > 250.0, "고온 유지 (결과 %.0f℃)" % living.t_upper)


func test_non_fuel_cell_cannot_ignite() -> void:
	var sim := _open_run()
	assert_true(not sim.fire.ignite(Vector3i(22, 6, 1)), "불연 화장실은 착화 안 됨")
	assert_true(not sim.fire.ignite(Vector3i(5, 5, 1)), "마당은 착화 안 됨")
	assert_true(sim.fire.ignite(Vector3i(27, 17, 1)), "방1 침대는 착화됨")


func test_fire_is_deterministic() -> void:
	var a := _open_run()
	var b := _open_run()
	a.step_ticks(MINUTE_TICKS * 4)
	b.step_ticks(MINUTE_TICKS * 4)
	for i in a.fire.comps.size():
		assert_eq(a.fire.comps[i].t_upper, b.fire.comps[i].t_upper, "%s 온도 동일" % a.fire.comps[i].display_name())
	assert_eq(a.events.entries.size(), b.events.entries.size(), "사건 수 동일")
	var c := SimWorld.create(BUILDING_PATH, ROSTER_PATH, UNIT_STATS_PATH, 99)
	var differs := false
	for i in c.fire.comps.size():
		if c.fire.comps[i].flashover_temp != a.fire.comps[i].flashover_temp:
			differs = true
	assert_true(differs, "시드가 다르면 플래시오버 임계온도가 달라짐")
