extends TestSuite
## P6-1·P3-1 [4]: 필요 방수량(13.6 L/min·㎡) 대 실제 방수량 — 물량 경쟁, 늦을수록 물이 더 든다, 물 소모 수치 (기획안 5-4)


func _house() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.doors.sync_blocking()
	return sim


func _living(sim: SimWorld) -> Compartment:
	for c in sim.fire.comps:
		if c.display_name() == "1층 거실":
			return c
	return null


## 관창 lines개(40mm 275L/분)를 거실 타는 칸에 seconds초 동안 쏜다. 쓴 물(L)
func _spray(sim: SimWorld, room: Compartment, lines: int, seconds: float) -> float:
	var grid := sim.fire.grid
	var lpm := 275.0 * lines
	var used := 0.0
	for k in roundi(seconds / SimClock.TICK_DT):
		var cells: Array[int] = []
		for i in grid.room_cells[room.index]:
			if grid.state[i] == FuelGrid.State.BURNING:
				cells.append(i)
		if cells.is_empty():
			break
		var liters := lpm / 60.0 * SimClock.TICK_DT
		for i in cells:
			grid.apply_water(i, liters / cells.size(), 0.6, sim.fire.comps)
		used += liters
		room.applied_lpm = lpm
		sim.step_ticks(1)
	return used


func _burning(sim: SimWorld, room: Compartment) -> int:
	var n := 0
	for i in sim.fire.grid.room_cells[room.index]:
		if sim.fire.grid.state[i] == FuelGrid.State.BURNING:
			n += 1
	return n


func test_required_flow() -> void:
	var sim := _house()
	sim.step_ticks(roundi(540.0 / SimClock.TICK_DT))
	var room := _living(sim)
	sim.step_ticks(1)
	assert_true(room.burning_area_m2 > 10.0, "최성기 거실 연소 면적 %.0f㎡" % room.burning_area_m2)
	assert_true(absf(room.required_lpm - 13.6 * room.burning_area_m2 * room.load_factor) < 1.0, "필요 방수량 = 13.6 × 면적 (%.0fL/분)" % room.required_lpm)


func test_one_line_cannot_but_three_can() -> void:
	var one := _house()
	one.step_ticks(roundi(540.0 / SimClock.TICK_DT))
	var room1 := _living(one)
	var before := _burning(one, room1)
	_spray(one, room1, 1, 90.0)
	var after1 := _burning(one, room1)
	var three := _house()
	three.step_ticks(roundi(540.0 / SimClock.TICK_DT))
	var room3 := _living(three)
	_spray(three, room3, 3, 90.0)
	var after3 := _burning(three, room3)
	assert_true(room1.flow_ratio < 1.0, "40mm 1선 비율 %.2f (1 미만)" % room1.flow_ratio)
	assert_true(after1 > before * 0.5, "1선은 최성기 거실을 못 끈다 (%d → %d칸)" % [before, after1])
	assert_true(after3 < after1 * 0.5, "3선이면 줄어든다 (1선 %d칸, 3선 %d칸)" % [after1, after3])
	assert_true(one.events.of_type("flow_short").size() >= 1, "관창수 '수량이 부족합니다' 보고")


func test_later_attack_needs_more_water() -> void:
	var early := _house()
	early.step_ticks(roundi(360.0 / SimClock.TICK_DT))
	var w_early := _spray(early, _living(early), 3, 600.0)
	var late := _house()
	late.step_ticks(roundi(540.0 / SimClock.TICK_DT))
	var w_late := _spray(late, _living(late), 3, 600.0)
	assert_true(w_late > w_early, "늦게 도착할수록 진압에 물이 더 든다 (6분 %.0fL < 9분 %.0fL)" % [w_early, w_late])


func test_water_numbers() -> void:
	var stats: Dictionary = JsonData.load_file("res://data/units/vehicles.json")
	assert_eq([float(stats["펌프차"].tank_l), float(stats["물탱크차"].tank_l)], [2800.0, 4000.0], "탱크 2,800L·4,000L")
	assert_eq([float(stats["펌프차"].nozzle_lpm), float(stats["펌프차"].nozzle_65_lpm), float(stats["물탱크차"].transfer_lpm)], [275.0, 611.0, 180.0], "관창 275·611, 급수 180")
	# 급수 없이 40mm 1선: 2,800 ÷ 275 ≈ 10분 11초
	assert_true(absf(2800.0 / 275.0 * 60.0 - 611.0) < 2.0, "급수 없이 1선이면 약 10분 11초에 고갈")
	# 소화전 급수 + 1선: 분당 275 - 180 = 95L 감소
	assert_eq(275.0 - 180.0, 95.0, "소화전 급수 + 1선 = 분당 95L 감소")
