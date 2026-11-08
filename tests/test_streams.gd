extends TestSuite
## R11: 주수 확장(펜슬링·3D·엄호·방수포)과 송풍기 양압배연 (기획안 P3·P6, SOP 210-10.4, 203-2.1, 207-1.1, 소방전술 화재1 배연전술)


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	sim.command.entry_order_required = false
	# 현관(잠김)을 열어 수관이 들어갈 수 있게
	for c in [Vector3i(13, 20, 1), Vector3i(14, 20, 1)]:
		var o := sim.fire.opening_at(c)
		if o:
			o.locked = false
			o.is_open = true
	sim.doors.sync_blocking()
	return sim


func _put(sim: SimWorld, crew_id: int, at: Vector2, level := 1) -> Crew:
	var c := sim.units.get_crew(crew_id)
	for i in c.members().size():
		var ff := c.members()[i]
		ff.pos = at + Vector2(i * 0.6, 0)
		ff.prev_pos = ff.pos
		ff.level = level
		ff.prev_level = level
	return c


## 거실 앞에서 지정한 주수 형태로 방수하고 펌프차 물이 얼마나 줄었는지
func _water_used(pattern: HoseLine.Pattern) -> float:
	var sim := _sim()
	_put(sim, 0, Vector2(13.5, 18.5))
	sim.water.lay_hose(0, 0, 0)
	var before := sim.units.get_vehicle(0).tank_l
	sim.water.start_spray(0, Vector3i(12, 16, 1), pattern, 0)
	sim.step_ticks(100)
	return before - sim.units.get_vehicle(0).tank_l


func test_pencil_uses_less_water() -> void:
	var fog := _water_used(HoseLine.Pattern.FOG)
	var pencil := _water_used(HoseLine.Pattern.PENCIL)
	assert_true(fog > 0.0, "분무 물 사용 (%.0fℓ)" % fog)
	assert_true(pencil < fog * 0.5 and pencil > 0.0, "펜슬링은 물을 적게 쓴다 (%.0f < %.0f)" % [pencil, fog])
	assert_eq(HoseLine.PATTERN_NAMES[HoseLine.Pattern.PENCIL], "펜슬링·3D", "이름")


func test_cover_reduces_heat() -> void:
	var sim := _sim()
	sim.step_ticks(600)  # 불이 자라게
	_put(sim, 0, Vector2(13.5, 17.5))
	_put(sim, 1, Vector2(14.5, 18.5))
	sim.step_ticks(1)
	var bare := sim.units.get_crew(1).leader.heat_flux
	sim.water.lay_hose(0, 0, sim.clock.tick)
	sim.water.start_spray(0, Vector3i(12, 16, 1), HoseLine.Pattern.COVER, sim.clock.tick)
	sim.step_ticks(3)
	assert_true(sim.water.is_covered(1, sim.units.get_crew(1).leader.pos), "옆 조는 엄호 막 안")
	var ff := sim.units.get_crew(1).leader
	var raw := sim.conditions.heat_at(1, Vector2i(ff.pos.floor()), ff.crouched)
	assert_true(raw <= 0.0 or ff.heat_flux < raw * 0.6, "복사열이 줄어든다 (%.2f → %.2f, 전 %.2f)" % [raw, ff.heat_flux, bare])


func test_monitor_window() -> void:
	var sim := _sim()
	sim.step_ticks(300)
	var v := sim.units.get_vehicle(0)
	assert_true(not sim.monitors.start(0, Vector3i(12, 16, 1), sim.clock.tick), "창·문이 아니면 쏘지 않는다")
	var before := v.tank_l
	assert_true(sim.monitors.start(0, Vector3i(10, 20, 1), sim.clock.tick), "거실 남쪽 창으로 방수포")
	var win := sim.fire.opening_at(Vector3i(10, 20, 1))
	assert_true(win.broken, "물줄기로 유리가 깨진다")
	sim.step_ticks(20)
	assert_true(v.tank_l < before, "펌프차 물을 크게 쓴다 (%.0f → %.0f)" % [before, v.tank_l])
	assert_eq(sim.monitors.violations, 0, "진입대원이 없으면 위반 아님")
	# 그 방에 대원이 들어가 있으면 SOP 207-1.1 위반
	_put(sim, 0, Vector2(11.5, 16.5))
	sim.step_ticks(2)
	assert_eq(sim.monitors.violations, 1, "진입대원이 있는 방에 방수포 = 위반")
	assert_eq(sim.events.of_type("monitor_crew_inside").size(), 1, "대원 안전 무전")
	sim.monitors.stop(0, sim.clock.tick)
	assert_eq(sim.monitors.streams.size(), 0, "중지")


func test_monitor_range() -> void:
	var sim := _sim()
	var v := sim.units.get_vehicle(0)
	v.pos = Vector2(70, 38)
	assert_true(not sim.monitors.start(0, Vector3i(10, 20, 1), 0), "사거리 밖")
	assert_eq(sim.events.of_type("monitor_too_far").size(), 1, "사거리 밖 알림")


func test_ppv_needs_exhaust_and_clears_smoke() -> void:
	var sim := _sim()
	sim.step_ticks(600)
	# 현관은 다시 닫아 배출구가 없게 한다
	for c in [Vector3i(13, 20, 1), Vector3i(14, 20, 1)]:
		var fo := sim.fire.opening_at(c)
		if fo:
			fo.is_open = false
	for op in sim.fire.openings:
		if op.kind == Opening.Kind.WINDOW and op.level == 1:
			op.broken = false
			op.is_open = false
	# 옆문(D면, 잠기지 않음)을 열고 그 앞에 송풍기
	var door := sim.fire.opening_at(Vector3i(31, 12, 1))
	assert_true(door != null and door.room_b == Opening.OUTSIDE, "옆문은 바깥 문")
	door.is_open = true
	door.locked = false
	sim.doors.sync_blocking()
	_put(sim, 2, Vector2(33.5, 12.5))
	assert_true(sim.vent.order(2, Vector3i(31, 12, 1), sim.pathfinder, sim.clock.tick), "송풍기 지시")
	sim.step_ticks(60)
	assert_true(sim.vent.active, "문 앞에서 가동")
	var no_exhaust := sim.events.of_type("ppv_no_exhaust").size()
	var room := sim.fire.comps[door.room_a]
	# 바람길 구획의 창을 깨 배출구를 만든다
	var vent_win: Opening = null
	for r in sim.vent._connected(door):
		for oi in sim.fire.comps[r].openings:
			var op: Opening = sim.fire.openings[oi]
			if op.kind == Opening.Kind.WINDOW and op.room_b == Opening.OUTSIDE:
				vent_win = op
	assert_eq(no_exhaust, 1, "배출구가 없으면 알린다")
	if vent_win:
		vent_win.broken = true
		vent_win.is_open = true
		room.soot = maxf(room.soot, 1.0)
		var before := room.soot
		sim.step_ticks(100)
		assert_true(room.soot < before, "배출구가 있으면 연기가 빠진다 (%.2f → %.2f)" % [before, room.soot])
	# 다른 명령을 주면 송풍기를 끈다
	sim.issue(MoveCommand.new([2] as Array[int], Vector3i(36, 23, 1)))
	sim.step_ticks(1)
	assert_true(sim.vent.opening < 0, "다른 명령 → 송풍기 끔")
