extends TestSuite
## R9: 수치 정비 — CO 교재 표(화재2 표 4-11), 호흡량 4단계·긴장 배율·호흡조절, 공기호흡기 41분, 산소 영향, 출구까지 필요 공기 (기획안 5-5·5-6)


func _table() -> Array:
	var data: Dictionary = JsonData.load_file("res://data/fire/hazard_params.json")
	return data.co_death_table.value


func test_co_table_points() -> void:
	var t := _table()
	assert_true(absf(RescueSystem.co_death_minutes(1600, t) - 120.0) < 0.01, "1,600ppm 120분")
	assert_true(absf(RescueSystem.co_death_minutes(3200, t) - 30.0) < 0.01, "3,200ppm 30분")
	assert_true(absf(RescueSystem.co_death_minutes(6400, t) - 20.0) < 0.01, "6,400ppm 20분")
	assert_true(absf(RescueSystem.co_death_minutes(12800, t) - 2.0) < 0.01, "12,800ppm 2분")
	var mid := RescueSystem.co_death_minutes(2263, t)
	assert_true(mid > 55.0 and mid < 65.0, "사이는 로그 보간 (2,263ppm ≈ 60분: %.1f)" % mid)
	assert_true(RescueSystem.co_death_minutes(800, t) > 120.0, "낮은 농도는 더 오래")
	assert_true(RescueSystem.co_death_minutes(50000, t) >= 0.5, "아주 높아도 최소 30초")


func test_3200ppm_30min_is_death() -> void:
	# 기획안 테스트: 3,200ppm에 30분 노출 시 사망 (노출량 = 사망 노출량)
	var t := _table()
	var fed := 0.0
	for i in 30 * 60:
		fed += 3.0 * 1.0 / 60.0 / RescueSystem.co_death_minutes(3200, t)
	assert_true(absf(fed - 3.0) < 0.01, "30분에 사망 노출량 (%.3f)" % fed)
	# 공학식(비교용)은 3,200ppm에서 더 빨리 쓰러뜨린다 — 교재 기준으로 바꾼 이유를 기록으로 남긴다
	var purser_death_min := 3.0 / RescueSystem.purser_rate(3200, 35000)
	assert_true(purser_death_min < 30.0, "공학식은 %.1f분 (교재 30분)" % purser_death_min)


func test_breathing_levels() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var ff := sim.units.get_crew(0).leader
	ff.heat_flux = 0.0
	assert_eq(sim.conditions.air_rate(ff), 40.0, "대기 40ℓ/분")
	# 공기호흡기 6.8ℓ·300bar, 경보 55bar → 40ℓ/분이면 약 41분 (화재1 표 1-19)
	var minutes := ff.air_capacity * (1.0 - 0.183) / 40.0
	assert_true(minutes > 41.0 and minutes < 42.5, "사용 가능 시간 약 41분 (%.1f)" % minutes)
	sim.conditions.activity_of = func(_f: Firefighter) -> int: return 1
	assert_eq(sim.conditions.air_rate(ff), 55.0, "수색·호스 전개 55")
	sim.conditions.activity_of = func(_f: Firefighter) -> int: return 2
	assert_eq(sim.conditions.air_rate(ff), 65.0, "방수·파괴 65")
	sim.conditions.activity_of = func(_f: Firefighter) -> int: return 3
	assert_eq(sim.conditions.air_rate(ff), 80.0, "구조·계단 80")
	ff.heat_flux = 100.0
	assert_true(absf(sim.conditions.air_rate(ff) - 104.0) < 0.01, "긴장(고열) ×1.3")
	ff.heat_flux = 0.0
	ff.air_alarm_logged = true
	assert_true(absf(sim.conditions.air_rate(ff) - 64.0) < 0.01, "경보 뒤 호흡조절 ×0.8")


func test_activity_from_sim() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	sim.command.entry_order_required = false
	var ff := sim.units.get_crew(0).leader
	assert_eq(sim.activity_level(ff), 0, "서 있으면 0")
	sim.issue(MoveCommand.new([0] as Array[int], Vector3i(20, 23, 1)))
	sim.step_ticks(3)
	assert_eq(sim.activity_level(ff), 1, "걸으면 1")


func test_exit_air_warning() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	sim.doors.sync_blocking()
	var c := sim.units.get_crew(0)
	for i in c.members().size():
		c.members()[i].pos = Vector2(11.5 + i, 16.5)
		c.members()[i].prev_pos = c.members()[i].pos
	# 출구(열린 현관)가 있어야 계산한다: 옆문(D면) 열기
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.DOOR and o.room_b == Opening.OUTSIDE and not o.locked:
			o.is_open = true
	sim.doors.sync_blocking()
	sim.step_ticks(2)
	var ff := c.leader
	assert_true(ff.exit_air_l > 0.0, "출구까지 필요 공기 계산 (%.1fℓ)" % ff.exit_air_l)
	# 경보 바로 위로 공기를 낮추면 출구까지 가는 동안 경보 아래로 내려간다 → 퇴각 건의
	for m in c.members():
		m.air_l = m.air_capacity * 0.183 + ff.exit_air_l * 0.5
	sim.step_ticks(2)
	var e := sim.events.of_type("exit_air_low")
	assert_true(not e.is_empty(), "퇴각 건의 보고")
	assert_true(not e.is_empty() and int(e[0].need_bar) >= 1, "필요 bar 기록")


func test_low_oxygen_stops_self_evac() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var v := sim.rescue.victims[0]
	var room := sim.fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
	room.y_o2 = Compartment.O2_AMBIENT_MASS * 9.0 / 20.9
	assert_true(sim.evac.o2_percent(v) <= 10.0, "산소 9%%")
	v.self_evac = true
	v.alert_s = 0.0
	var before := v.pos
	sim.evac.paths[v.id] = [Vector3i(floori(v.pos.x) + 1, floori(v.pos.y), v.level)]
	sim.evac._walk(v, 1.0, 1)
	assert_eq(v.pos, before, "산소 10%% 이하면 스스로 움직이지 못한다")
	room.y_o2 = Compartment.O2_AMBIENT_MASS * 15.0 / 20.9
	sim.evac._walk(v, 1.0, 1)
	var moved := v.pos.distance_to(before)
	room.y_o2 = Compartment.O2_AMBIENT_MASS
	var before2 := v.pos
	sim.evac.paths[v.id] = [Vector3i(floori(v.pos.x) + 3, floori(v.pos.y), v.level)]
	sim.evac._walk(v, 1.0, 1)
	var moved2 := v.pos.distance_to(before2)
	assert_true(moved > 0.0 and moved < moved2, "18%% 아래는 느리게 (%.2f < %.2f)" % [moved, moved2])


func test_rosters_follow_standard_crews() -> void:
	# 출동 편성 (기획안 6-1, data/units/crews.json): 분대원 수가 게임 편성 기준을 넘지 않고 2인 1조로 묶인다
	var std: Dictionary = JsonData.load_file("res://data/units/crews.json").squads
	for path in ["res://data/units/test_roster.json", "res://data/units/dev_reinforcements.json"]:
		var roster: Dictionary = JsonData.load_file(path)
		for s: Dictionary in roster.squads:
			var key := str(s.type)
			assert_true(std.has(key), "%s 편성 기준 있음 (%s)" % [s.id, key])
			var members := 0
			for c: Dictionary in s.get("crews", []):
				assert_eq((c.members as Array).size(), 2, "%s 2인 1조" % s.id)
				members += (c.members as Array).size()
			if std.has(key):
				assert_true(members <= int(std[key].game_members), "%s 분대원 %d명 ≤ %d" % [s.id, members, int(std[key].game_members)])
