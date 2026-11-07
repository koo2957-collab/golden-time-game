extends TestSuite
## M4b: 요구조자, 인명검색·구조, 특수현상(롤오버·플래시오버·백드래프트), 배연

const OLD := 0  # 2층 방3 노인
const CHILD := 1  # 1층 방1 아이


func _sim(all_doors_open := false) -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	if all_doors_open:
		open_all_doors(sim)
	return sim


func _place(sim: SimWorld, crew_id: int, at: Vector2, level := 1) -> Crew:
	var c := sim.units.get_crew(crew_id)
	c.leader.pos = at
	c.leader.prev_pos = at
	c.leader.level = level
	c.leader.path.clear()
	c.partner.pos = at + Vector2(1, 0)
	c.partner.prev_pos = c.partner.pos
	c.partner.level = level
	c.partner.path.clear()
	return c


func _room_of(sim: SimWorld, v: Victim) -> Compartment:
	return sim.fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))


## 거실을 밀폐 상태로 만든다 (문 닫음, 창은 깨지지 않음)
func _seal_living(sim: SimWorld) -> Compartment:
	var living := sim.fire.compartment_at(1, 12, 16)
	for oi in living.openings:
		var o := sim.fire.openings[oi]
		if o.kind == Opening.Kind.DOOR:
			o.is_open = false
		elif o.kind == Opening.Kind.WINDOW:
			o.breakable = false
	sim.doors.sync_blocking()
	return living


# --- 요구조자 ---

func test_victims_placed_in_their_rooms_deterministically() -> void:
	var a := _sim()
	var b := _sim()
	assert_eq(a.rescue.victims.size(), 2, "요구조자 2명")
	assert_eq(_room_of(a, a.rescue.victims[OLD]).display_name(), "2층 방3", "노인은 2층 방3")
	assert_eq(_room_of(a, a.rescue.victims[CHILD]).display_name(), "1층 방1", "아이는 1층 방1")
	assert_eq(a.rescue.victims[OLD].pos, b.rescue.victims[OLD].pos, "같은 시드면 같은 위치")


func test_victims_hidden_until_crew_finds_them() -> void:
	var sim := _sim()
	sim.step_ticks(30)
	for v in sim.rescue.victims:
		assert_true(not v.discovered, "%s: 창 밖에서는 바닥에 쓰러진 사람이 보이지 않음" % v.label())
	var child := sim.rescue.victims[CHILD]
	_place(sim, 2, child.pos + Vector2(-2, 0))
	sim.step_ticks(4)
	assert_true(child.discovered, "같은 방에 들어가면 발견")


func test_voice_heard_through_wall() -> void:
	var sim := _sim()
	var child := sim.rescue.victims[CHILD]
	var spot := Vector2(clampf(child.pos.x, 20.5, 30.5), 13.5)  # 방1 위쪽 복도, 벽 너머
	_place(sim, 3, spot)
	sim.step_ticks(4)
	assert_true(child.discovered, "의식 있는 요구조자의 소리는 벽 너머로 들림 (거리 %.1f셀)" % spot.distance_to(child.pos))
	var found := sim.events.of_type("victim_found")
	assert_true(not found.is_empty() and found[0].how == "소리", "발견 방법: 소리")


func test_exposure_and_flashover_kill() -> void:
	var sim := _sim()
	sim.rescue.add_victims([{"name": "거실 요구조자", "age": 50, "level": 1, "cell": [12, 15]}], sim.rng)
	var v := sim.rescue.victims[2]
	sim.step_ticks(5 * 600)
	assert_true(v.fed() > 0.0, "거실 연기·열에 노출됨 (FED %.2f)" % v.fed())
	sim.step_ticks(3 * 600)
	assert_eq(v.state, Victim.State.DEAD, "거실 플래시오버 → 사망")


func test_unattended_upstairs_victim_has_golden_time() -> void:
	var sim := _sim()
	var old := sim.rescue.victims[OLD]
	sim.step_ticks(6 * 600)
	assert_eq(old.state, Victim.State.CONSCIOUS, "6분: 아직 의식 있음")
	sim.step_ticks(9 * 600)
	assert_true(not old.alive(), "15분 동안 구조하지 않으면 생존 불가")


# --- 검색·구조 ---

func test_search_marks_room_and_finds_victim() -> void:
	var sim := _sim(true)
	_place(sim, 2, Vector2(24.5, 12.5))  # 1층 복도
	sim.issue(EquipmentCommand.make("search", [2] as Array[int], -1, -1, Vector3i(24, 17, 1)))
	sim.step_ticks(900)
	var room1 := sim.fire.compartment_at(1, 24, 17)
	assert_true(room1.searched_tick >= 0, "방1 검색 완료")
	assert_true(sim.rescue.victims[CHILD].discovered, "검색 중 아이 발견")
	assert_true(not sim.events.of_type("search_done").is_empty(), "검색 완료 사건")


func test_rescue_victim_to_outside() -> void:
	var sim := _sim(true)
	var child := sim.rescue.victims[CHILD]
	_place(sim, 2, child.pos + Vector2(-2, 0))
	sim.step_ticks(4)
	sim.issue(EquipmentCommand.make("rescue", [2] as Array[int], -1, CHILD))
	sim.step_ticks(30)
	assert_true(child.carried_by == 2, "구조1 1조가 업음")
	assert_eq(sim.units.get_crew(2).leader.carry_factor, 0.5, "업으면 느려짐")
	sim.step_ticks(900)
	assert_eq(child.state, Victim.State.RESCUED, "바깥으로 이송 → 구조 완료")
	assert_eq(child.state_at_rescue, Victim.State.CONSCIOUS, "의식 있는 상태로 구조")
	assert_eq(sim.units.get_crew(2).leader.carry_factor, 1.0, "내려놓으면 원래 속도")


func test_hose_crew_cannot_rescue() -> void:
	var sim := _sim(true)
	var child := sim.rescue.victims[CHILD]
	child.discovered = true
	sim.issue(EquipmentCommand.make("hose", [0] as Array[int], 0))
	sim.step_ticks(1)
	sim.issue(EquipmentCommand.make("rescue", [0] as Array[int], -1, CHILD))
	sim.step_ticks(1)
	assert_true(sim.rescue.carries.is_empty(), "수관 조는 구조 작업을 받지 않음")
	assert_true(not sim.events.of_type("rescue_hose_crew").is_empty(), "다른 조 투입 안내")


func test_rescue_downed_firefighter() -> void:
	var sim := _sim(true)
	var down := _place(sim, 1, Vector2(24.5, 12.5)).leader
	down.incapacitated = true
	_place(sim, 3, Vector2(27.5, 12.5))
	sim.issue(EquipmentCommand.make("rescue_ff", [3] as Array[int], -1, down.id))
	sim.step_ticks(900)
	assert_true(not sim.events.of_type("ff_rescued").is_empty(), "쓰러진 대원 구출 완료")
	assert_true(sim.building.cell(1, floori(down.pos.x), floori(down.pos.y)) in BuildingData.OUTDOOR, "바깥으로 이송됨")


# --- 특수현상 ---

func test_rollover_sign_before_flashover() -> void:
	var sim := _sim()
	sim.step_ticks(9 * 600)
	var signs := sim.events.of_type("rollover_sign").filter(func(e: Dictionary) -> bool: return e.room == "1층 거실")
	var fo := sim.events.of_type("flashover").filter(func(e: Dictionary) -> bool: return e.room == "1층 거실")
	assert_true(not signs.is_empty() and not fo.is_empty(), "롤오버 징후와 플래시오버 모두 발생")
	if not signs.is_empty() and not fo.is_empty():
		assert_true(signs[0].time_s < fo[0].time_s, "징후가 먼저 (%.0f초 → %.0f초)" % [signs[0].time_s, fo[0].time_s])


func test_flashover_downs_crew_inside() -> void:
	var probe := _sim()
	probe.step_ticks(9 * 600)
	var fo_tick: int = probe.events.of_type("flashover")[0].tick
	var sim := _sim()
	sim.step_ticks(fo_tick - 1)
	var c := _place(sim, 1, Vector2(15.5, 14.5))
	sim.step_ticks(3)
	assert_true(c.leader.incapacitated, "플래시오버 순간 방 안 대원 행동 불능")


func test_backdraft_sign_and_blast_on_opening_sealed_room() -> void:
	var sim := _sim()
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	var living := _seal_living(sim)
	sim.step_ticks(10 * 600)
	assert_true(living.gas_percent() >= 12.5, "밀폐 거실에 미연소가스 축적 (%.1f%%)" % living.gas_percent())
	var c := _place(sim, 2, Vector2(21.5, 12.5))  # 복도, 거실 문 앞
	sim.issue(EquipmentCommand.make("door_open", [2] as Array[int], -1, -1, Vector3i(19, 12, 1)))
	sim.step_ticks(2)
	assert_true(not sim.events.of_type("backdraft_sign").is_empty(), "문 앞 작업 시작 시 백드래프트 징후")
	sim.step_ticks(100)
	assert_true(not sim.events.of_type("backdraft").is_empty(), "문을 열자 백드래프트")
	assert_true(c.leader.incapacitated, "문 앞 대원 행동 불능")


func test_window_venting_does_not_cause_backdraft() -> void:
	var sim := _sim()
	var living := _seal_living(sim)
	sim.step_ticks(10 * 600)
	var gas_before := living.gas_percent()
	_place(sim, 2, Vector2(10.5, 22.5))  # 거실 남쪽 창 밖 마당
	sim.issue(EquipmentCommand.make("door_open", [2] as Array[int], -1, -1, Vector3i(10, 20, 1)))
	sim.step_ticks(100)
	var window := sim.fire.opening_at(Vector3i(10, 20, 1))
	assert_true(window.broken and window.is_open, "창 파괴 (배연)")
	assert_true(not sim.events.of_type("window_vented").is_empty(), "배연 사건")
	assert_true(sim.events.of_type("backdraft").is_empty(), "창(상부) 개방은 백드래프트를 일으키지 않음")
	sim.step_ticks(300)
	assert_true(living.gas_percent() < gas_before, "미연소가스 감소 (%.1f%% → %.1f%%)" % [gas_before, living.gas_percent()])
