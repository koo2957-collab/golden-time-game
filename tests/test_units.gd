extends TestSuite


func test_roster_loaded_as_pairs() -> void:
	var sim := make_sim()
	assert_eq(sim.units.squads.size(), 2, "출동대 2개")
	assert_eq(sim.units.crews.size(), 4, "조 4개")
	assert_eq(sim.units.firefighters.size(), 8, "대원 8명")
	for c in sim.units.crews:
		assert_true(c.partner != null, "모든 조가 2인 1조")


func test_crew_moves_and_partner_follows() -> void:
	var sim := make_sim()
	var target := Vector3i(14, 16, 1)
	sim.issue(MoveCommand.new([0] as Array[int], target))
	sim.step_ticks(300)
	var c := sim.units.get_crew(0)
	assert_eq(c.leader.cell3(), target, "조장이 목표 도착")
	assert_true(not c.leader.is_moving() and not c.partner.is_moving(), "이동 완료")
	var d := c.leader.pos.distance_to(c.partner.pos)
	assert_true(d > 0.5 and d < 1.6, "짝이 바로 옆(뒤)에 있음 (거리 %.2f)" % d)
	assert_eq(sim.command_log.entries.size(), 1, "명령 기록")
	assert_eq(sim.command_log.to_array()[0]["tick"], 0, "명령 실행 틱 기록")


func test_crew_reaches_second_floor() -> void:
	var sim := make_sim()
	sim.issue(MoveCommand.new([2] as Array[int], Vector3i(12, 17, 2)))
	sim.step_ticks(600)
	var c := sim.units.get_crew(2)
	assert_eq(c.leader.level, 2, "조장 2층 도착")
	assert_eq(c.partner.level, 2, "짝도 2층 도착")


func test_multiple_crews_get_separate_slots() -> void:
	var sim := make_sim()
	sim.issue(MoveCommand.new([0, 1, 2, 3] as Array[int], Vector3i(14, 16, 1)))
	sim.step_ticks(400)
	var cells := {}
	for c in sim.units.crews:
		cells[c.leader.cell3()] = true
	assert_eq(cells.size(), 4, "조장 4명이 서로 다른 셀에 도착")


func test_deterministic() -> void:
	var a := make_sim()
	var b := make_sim()
	for sim in [a, b]:
		sim.issue(MoveCommand.new([0, 1] as Array[int], Vector3i(24, 17, 1)))
		sim.step_ticks(37)
		sim.issue(MoveCommand.new([0] as Array[int], Vector3i(12, 6, 2)))
		sim.step_ticks(250)
	for i in a.units.firefighters.size():
		var fa := a.units.firefighters[i]
		var fb := b.units.firefighters[i]
		assert_eq(fa.pos, fb.pos, "대원 %d 위치 동일" % i)
		assert_eq(fa.level, fb.level, "대원 %d 층 동일" % i)
