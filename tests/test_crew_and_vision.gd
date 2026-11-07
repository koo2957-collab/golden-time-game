extends TestSuite
## M4a: 문 개방·파괴, 열기 접근 제한, 시야(정보 안개), 공기호흡기, 자세


func _sim() -> SimWorld:
	return SimWorld.from_scenario(DEV_SCENARIO_PATH, false)


func _place(sim: SimWorld, crew_id: int, at: Vector2, level := 1) -> Crew:
	var c := sim.units.get_crew(crew_id)
	c.leader.pos = at
	c.leader.prev_pos = at
	c.leader.level = level
	c.partner.pos = at + Vector2(1, 0)
	c.partner.prev_pos = c.partner.pos
	c.partner.level = level
	return c


# --- 문 ---

func test_closed_door_blocks_path() -> void:
	var sim := _sim()
	assert_true(sim.pathfinder.find_path(Vector3i(13, 22, 1), Vector3i(13, 18, 1)).is_empty(), "외부 문이 모두 닫혀 있으면 들어갈 수 없음")
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.doors.sync_blocking()
	var path := sim.pathfinder.find_path(Vector3i(13, 22, 1), Vector3i(13, 18, 1))
	assert_true(path.size() > 20, "옆문을 열면 옆문으로 돌아서 들어감 (%d칸)" % path.size())


func test_unlocked_door_opens_quickly() -> void:
	var sim := _sim()
	var side := sim.fire.opening_at(Vector3i(31, 12, 1))
	assert_true(not side.is_open and not side.locked, "옆문: 닫힘, 안 잠김")
	_place(sim, 0, Vector2(34.5, 12.5))
	sim.issue(EquipmentCommand.make("door_open", [0] as Array[int], -1, -1, Vector3i(31, 12, 1)))
	sim.step_ticks(80)
	assert_true(side.is_open, "옆문 개방 (약 3초 + 이동)")
	assert_true(not sim.pathfinder.find_path(Vector3i(34, 12, 1), Vector3i(25, 12, 1)).is_empty(), "열린 문으로 진입 가능")


func test_locked_door_needs_two_people_and_time() -> void:
	var sim := _sim()
	var front := sim.fire.opening_at(Vector3i(13, 20, 1))
	assert_true(front.locked, "현관문 잠김")
	# 한 명만 문 앞에 있으면 진행되지 않음
	var c := _place(sim, 0, Vector2(13.5, 21.5))
	c.partner.pos = Vector2(5.5, 24.5)
	c.partner.incapacitated = true
	sim.issue(EquipmentCommand.make("door_open", [0] as Array[int], -1, -1, Vector3i(13, 20, 1)))
	sim.step_ticks(900)
	assert_true(not front.is_open, "1명으로는 파괴 불가")
	assert_true(sim.doors.task_of(front).waiting_people, "인원 부족 표시")
	# 둘이 되면 파괴 (60초)
	c.partner.incapacitated = false
	c.partner.pos = Vector2(14.5, 22.5)
	sim.step_ticks(300)
	assert_true(not front.is_open, "30초로는 아직")
	sim.step_ticks(400)
	assert_true(front.is_open and front.forced and not front.locked, "60초 뒤 파괴되어 열림")
	assert_true(not sim.events.of_type("door_forced").is_empty(), "파괴 사건 기록")
	sim.issue(EquipmentCommand.make("door_close", [0] as Array[int], -1, -1, Vector3i(13, 20, 1)))
	sim.step_ticks(100)
	assert_true(front.is_open, "파괴된 문은 닫을 수 없음")


# --- 열기 ---

func test_heat_blocks_approach_to_fully_developed_room() -> void:
	var sim := _sim()
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.doors.sync_blocking()
	sim.step_ticks(8 * 600)
	var hazard := sim.conditions.hazard_kw_m2()
	assert_true(sim.conditions.heat_at(1, Vector2i(14, 16), true) > hazard, "최성기 거실 한가운데는 극한 열기")
	assert_true(sim.conditions.heat_at(1, Vector2i(5, 23), false) < 0.1, "벽 너머 마당에는 화염 복사가 오지 않음")
	_place(sim, 0, Vector2(25.5, 12.5))
	sim.issue(MoveCommand.new([0] as Array[int], Vector3i(14, 16, 1)))
	sim.step_ticks(300)
	var c := sim.units.get_crew(0)
	assert_true(sim.fire.compartment_at(1, c.leader.cell3().x, c.leader.cell3().y) != _living(sim), "거실 안으로 들어가지 못함")
	assert_true(not sim.events.of_type("heat_blocked").is_empty() or not sim.events.of_type("heat_retreat").is_empty(), "열기 접근 제한 사건")


func test_crouch_in_smoke_slows_movement() -> void:
	var sim := _sim()
	sim.step_ticks(4 * 600)
	var c := _place(sim, 0, Vector2(25.5, 12.5))  # 연기 찬 복도
	sim.step_ticks(1)
	assert_true(c.leader.crouched, "연기층이 내려온 복도에서는 낮은 자세")
	assert_eq(c.leader.crouch_factor, 0.5, "낮은 자세 속도 절반")


# --- 공기호흡기 ---

func test_scba_consumption_alarm_and_swap() -> void:
	var sim := _sim()
	var c := _place(sim, 0, Vector2(25.5, 6.5))  # 화장실 (건물 안)
	var ff := c.leader
	sim.step_ticks(600)
	assert_true(absf(ff.air_l - (2040.0 - 40.0)) < 1.0, "건물 안 가만히: 분당 40L (결과 %.0fL)" % ff.air_l)
	ff.air_l = ff.air_capacity * 0.17
	sim.step_ticks(100)
	assert_true(not sim.events.of_type("air_alarm").is_empty(), "잔량 18% 아래로 경보")
	# 바깥 차량 옆에서 교체
	_place(sim, 0, Vector2(10.5, 26.5))
	sim.step_ticks(650)
	assert_eq(ff.air_l, ff.air_capacity, "차량 옆에서 60초 뒤 용기 교체")
	# 건물 안에서 다 떨어지면 행동 불능
	_place(sim, 0, Vector2(25.5, 6.5))
	ff.air_l = 1.0
	sim.step_ticks(20)
	assert_true(ff.incapacitated, "공기 소진 → 행동 불능")


# --- 시야 ---

func test_info_fog_hides_unvisited_rooms() -> void:
	var sim := _sim()
	sim.step_ticks(30)
	var p := sim.perception
	assert_true(p.is_visible(1, 5, 23), "건물 밖은 보임")
	assert_true(p.is_visible(1, 25, 17), "방1은 창으로 밖에서 들여다보임")
	assert_true(not p.is_seen(1, 25, 12), "창 없는 복도는 아무도 안 가면 모름")
	_place(sim, 2, Vector2(24.5, 12.5))
	sim.step_ticks(3)
	assert_true(p.is_visible(1, 25, 12), "대원이 들어가면 보임")
	_place(sim, 2, Vector2(5.5, 23.5))
	sim.step_ticks(3)
	assert_true(not p.is_visible(1, 25, 12) and p.is_seen(1, 25, 12), "나오면 '본 적 있음'으로 남음")


func test_smoke_limits_sight_and_thermal_camera_sees_through() -> void:
	var sim := _sim()
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.doors.sync_blocking()
	sim.step_ticks(5 * 600)
	var p := sim.perception
	# 열화상카메라 조들은 길 건너로 보내 두고 (깨진 창으로 들여다보지 않게),
	# 열화상카메라 없는 조 (진압1 2조)를 짙은 연기 거실 문 앞에 세운다
	_place(sim, 0, Vector2(2.5, 38.5))
	_place(sim, 2, Vector2(6.5, 38.5))
	_place(sim, 1, Vector2(17.5, 12.5))
	sim.step_ticks(3)
	assert_true(not p.is_visible(1, 10, 18) or sim.fire.grid.state[sim.fire.grid.index(1, 10, 18)] == FuelGrid.State.BURNING, "짙은 연기 속 먼 바닥(형체)은 보이지 않음")
	var burning_seen := false
	for i in sim.fire.grid.burning:
		var cc := sim.fire.grid.cell_of(i)
		if cc.z == 1 and sim.fire.compartment_at(1, cc.x, cc.y) == _living(sim) and p.is_visible(1, cc.x, cc.y):
			burning_seen = true
	assert_true(burning_seen, "화염 불빛은 연기 속에서도 일부 보임")
	assert_true(not p.is_thermal_visible(1, 12, 17), "열화상카메라 없는 조는 열화상 정보 없음")
	# 열화상카메라 조 (진압1 1조)
	_place(sim, 0, Vector2(17.5, 13.5))
	sim.step_ticks(3)
	assert_true(p.is_thermal_visible(1, 12, 17), "열화상카메라는 연기 너머를 봄")


func test_walls_block_sight() -> void:
	var sim := _sim()
	_place(sim, 2, Vector2(24.5, 12.5))  # 복도
	sim.step_ticks(3)
	assert_true(sim.perception.is_visible(1, 28, 12), "같은 복도는 보임")
	assert_true(not sim.perception.is_visible(1, 29, 5), "벽 너머 계단실 안쪽은 안 보임")


func _living(sim: SimWorld) -> Compartment:
	return sim.fire.compartment_at(1, 12, 16)
