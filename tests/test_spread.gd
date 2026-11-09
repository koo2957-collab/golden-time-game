extends TestSuite
## 화재 확산 보강 (기획안 5-2-2, P3-1 [2], 2026-11-10): 대류(뜨거운 연기층 흐름)·문 너머 복사·최성기 화염 분출·벽·바닥 너머 전도·
## 나무 문 소손, 방화문, 쇠퇴기 끝 소진, 소실 정도(전소·반소·부분소)

const APT := "res://data/scenarios/sop213_1_apartment_3f.json"


func _house() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.doors.sync_blocking()
	return sim


func _comp(sim: SimWorld, name: String) -> Compartment:
	for c in sim.fire.comps:
		if c.display_name() == name:
			return c
	return null


func _door_between(sim: SimWorld, a: Compartment, b: Compartment) -> Opening:
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.DOOR and ((o.room_a == a.index and o.room_b == b.index) or (o.room_a == b.index and o.room_b == a.index)):
			return o
	return null


## 그 구획 칸 가운데 하나라도 착화한 첫 시각 (초, 없으면 -1)
func _first_ignition_s(sim: SimWorld, room: Compartment, limit_s: float) -> float:
	var grid := sim.fire.grid
	while sim.clock.tick * SimClock.TICK_DT < limit_s:
		sim.step_ticks(50)
		for i in grid.room_cells[room.index]:
			if grid.state[i] == FuelGrid.State.BURNING or grid.state[i] == FuelGrid.State.BURNT:
				return sim.clock.tick * SimClock.TICK_DT
	return -1.0


func test_open_door_spreads_faster_than_closed() -> void:
	# 교재: 문이 열려 있으면 연기층·화염이 넘어가 옆 공간이 빨리 위험해지고, 닫혀 있으면 훨씬 느리다 (기획안 5-2-2)
	var open_sim := _house()
	var living := _comp(open_sim, "1층 거실")
	var kitchen := _comp(open_sim, "1층 주방")
	var door := _door_between(open_sim, living, kitchen)
	assert_true(door != null, "거실-주방 문")
	door.is_open = true
	var t_open := _first_ignition_s(open_sim, kitchen, 1500.0)
	var closed_sim := _house()
	var door2 := _door_between(closed_sim, _comp(closed_sim, "1층 거실"), _comp(closed_sim, "1층 주방"))
	door2.is_open = false
	closed_sim.doors.sync_blocking()
	var t_closed := _first_ignition_s(closed_sim, _comp(closed_sim, "1층 주방"), 1500.0)
	assert_true(t_open > 0.0, "문이 열리면 주방에 불이 옮겨 붙음 (%.0f초)" % t_open)
	assert_true(t_closed < 0.0 or t_closed > t_open + 60.0, "문이 닫히면 훨씬 늦음 (열림 %.0f초 / 닫힘 %.0f초)" % [t_open, t_closed])


func test_house_left_alone_spreads_to_upper_floor() -> void:
	# 방치한 주택은 일부(거실)에서 다른 방·위층으로 번져 전소된다 (전도·대류·복사)
	var sim := _house()
	var burned_levels := {}
	var limit := roundi(3600.0 / SimClock.TICK_DT)
	while not sim.ended() and sim.clock.tick < limit:
		sim.step_ticks(200)
	for c in sim.fire.comps:
		if c.ever_burned and not sim.fire.is_exposure_comp(c):
			burned_levels[c.level] = true
	assert_true(burned_levels.has(2), "2층까지 번짐")
	assert_true(sim.mission_end.loss_ratio() >= 0.7, "건물 70%% 이상 소실 (%.0f%%)" % (sim.mission_end.loss_ratio() * 100.0))
	assert_eq(sim.mission_end.loss_class(), "전소", "소실 정도 전소 (화재1 5쪽)")
	assert_eq(sim.fire.grid.burning.size(), 0, "다 타면 꺼진다 (쇠퇴기 끝 소진)")
	assert_true(sim.events.of_type("door_burnt_through").size() >= 1, "닫힌 나무 문이 타서 뚫림")


func test_wall_conduction_by_structure() -> void:
	# 벽 너머 전도는 구조별로 다르다: 목조·패널 > 벽돌 > 철근콘크리트 (화재1 13·151쪽)
	var cfg := FireConfig.load_files("res://data/fire/fire_params.json", "res://data/materials/materials.json")
	var rc := cfg.by_structure("wall_through_heat_kw_m2k", "철근콘크리트조")
	var brick := cfg.by_structure("wall_through_heat_kw_m2k", "벽돌조")
	var wood := cfg.by_structure("wall_through_heat_kw_m2k", "목조")
	var panel := cfg.by_structure("wall_through_heat_kw_m2k", "샌드위치패널 (EPS)")
	assert_true(rc < brick and brick < wood and wood < panel, "전도 계수 RC %.4f < 벽돌 %.4f < 목조 %.4f < 패널 %.4f" % [rc, brick, wood, panel])
	assert_true(cfg.by_structure("wall_heat_tau_s", "철근콘크리트조") > cfg.by_structure("wall_heat_tau_s", "목조"), "콘크리트는 열이 늦게 전해짐")


func test_concrete_apartment_contained_on_fire_floor() -> void:
	# 콘크리트 내력벽 아파트는 세대 문이 닫혀 있으면 같은 층 다른 세대로 잘 번지지 않는다 (화재1 151쪽)
	var sim := SimWorld.from_scenario(APT, false)
	sim.step_ticks(roundi(1200.0 / SimClock.TICK_DT))
	var origin := ""
	for c in sim.fire.comps:
		if c.ever_burned and c.level == 3:
			origin = c.display_name().split(" ")[1].left(3) if c.display_name().split(" ").size() > 1 else ""
			break
	var others: Array[String] = []
	for c in sim.fire.comps:
		var n := c.display_name()
		if c.level == 3 and c.ever_burned and origin != "" and n.contains("호") and not n.contains(origin):
			others.append(n)
	assert_true(origin != "", "발화 세대 (%s)" % origin)
	assert_eq(others, [] as Array[String], "같은 층 다른 세대는 타지 않음 (20분)")


func test_fire_doors_do_not_burn() -> void:
	var sim := SimWorld.from_scenario(APT, false)
	var grid := sim.fire.grid
	var checked := 0
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.DOOR and sim.building.is_fire_door(o.cells[0]):
			checked += 1
			assert_eq(grid.state[grid.index(o.level, o.cells[0].x, o.cells[0].y)], FuelGrid.State.NONE, "방화문은 가연물이 아님")
	assert_true(checked > 0, "방화문 %d개 확인" % checked)
