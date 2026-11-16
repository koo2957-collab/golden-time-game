extends TestSuite
## 분대 단위 편성 (2026-11-16 결정 — docs/decisions.md '분대'):
## 분대는 조 하나로 같이 움직인다, 팀장 = 분대 지휘관(말하는 사람, 호스는 잡지 않는다),
## 선착대장은 선착 펌프차 조수석에서 내린다, 운전석 문은 하차에 쓰지 않는다.

const SQUAD_SCENARIO := "res://data/scenarios/dev_squad_house_fire.json"
const ROSTER := "res://data/units/squad_roster.json"
const REINFORCEMENTS := "res://data/units/squad_reinforcements.json"


func _until(sim: SimWorld, cond: Callable, max_s: float) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return cond.call()


## 편성 파일만으로 출동대를 만든다 (차량 없이 — 사람 구성만 본다)
func _units(path: String) -> UnitSystem:
	var roster: Dictionary = JsonData.load_file(path)
	for s: Dictionary in roster.squads:
		s.erase("vehicles")
	return UnitSystem.from_roster(roster, 2.4)


func test_rosters_follow_squad_composition() -> void:
	var std: Dictionary = JsonData.load_file("res://data/units/crews.json").squads
	for path in [ROSTER, REINFORCEMENTS]:
		var roster: Dictionary = JsonData.load_file(path)
		for s: Dictionary in roster.squads:
			var key := str(s.type)
			assert_true(std.has(key), "%s 편성 기준 있음 (%s)" % [s.id, key])
			var crews: Array = s.get("crews", [])
			assert_true(crews.size() <= 1, "%s 분대는 조 하나 (%d)" % [s.id, crews.size()])
			if crews.is_empty() or not std.has(key):
				continue
			var members: Array = crews[0].members
			var officers := members.filter(func(m: Dictionary) -> bool: return bool(m.get("officer", false))).size()
			# 선착 펌프차 분대(pump1)는 팀장이 선착대장이라 현장에는 분대원 3명뿐
			var first_due := str(s.id) == "pump1"
			var want: int = int(std["선착대"].game_members) if first_due else int(std[key].game_members)
			assert_eq(members.size(), want, "%s 현장 인원" % s.id)
			assert_eq(officers, 0 if first_due else int(std[key].officer), "%s 팀장 수" % s.id)


func test_officer_speaks_and_workers_hold_the_hose() -> void:
	var units := _units(REINFORCEMENTS)
	var pump := units.squad_by_key("pump2").crews[0]
	assert_eq(pump.list.size(), 4, "후착 진압 분대 4명")
	assert_eq(pump.leader.role, "관창수", "선두는 관창수")
	assert_true(pump.officer() != null and pump.officer() != pump.leader, "팀장은 선두가 아니다 (옆에서 통솔)")
	assert_true(pump.speaker() == pump.officer(), "말하는 사람 = 팀장")
	assert_eq(pump.workers().size(), 3, "방수는 3명")
	assert_true(not pump.officer() in pump.workers(), "팀장은 호스를 잡지 않는다")
	assert_eq(pump.able_workers(), 3, "일할 수 있는 조원 3")
	pump.officer().incapacitated = true
	assert_true(pump.speaker() == pump.leader, "팀장이 쓰러지면 선두가 말한다")
	pump.list[1].incapacitated = true
	assert_eq(pump.able_workers(), 2, "쓰러진 조원은 뺀다")
	var rescue := units.squad_by_key("rescue2").crews[0]
	assert_true(rescue.officer() == rescue.leader, "구조 분대는 팀장이 선두")
	assert_eq(rescue.workers().size(), 4, "구조 분대는 팀장도 같이 일한다")
	var ems := units.squad_by_key("ems1").crews[0]
	assert_true(ems.officer() == null and ems.speaker() == ems.leader, "구급대는 팀장 표시 없음 — 선두가 말한다")
	# 선착 분대: 팀장이 플레이어라 현장에는 팀장이 없다
	var first := _units(ROSTER).squad_by_key("pump1").crews[0]
	assert_eq(first.list.size(), 3, "선착 진압 분대 3명")
	assert_true(first.officer() == null and first.speaker() == first.leader, "선착 분대는 관창수가 대신 보고")


func test_whole_squad_is_called_by_squad_name() -> void:
	var units := _units(ROSTER)
	var c := units.squad_by_key("pump1").crews[0]
	assert_true(units.whole_squad(c), "나누지 않은 분대")
	assert_eq(units.crew_name(c), "진압1", "분대 이름으로 부른다")
	assert_eq(units.crew_short(c), "분대", "출동대 이름 없이는 '분대'")
	assert_eq(units.ff_name(c.list[1]), "진압1 %s" % c.list[1].name, "대원 이름")
	# 예전 2인조 편성은 그대로 "진압1 1조"
	var old := _units("res://data/units/test_roster.json")
	assert_eq(old.crew_name(old.crews[0]), "진압1 1조", "나뉜 조는 조 번호까지")
	assert_eq(old.crew_short(old.crews[1]), "2조", "2조")


func test_squad_walks_in_line() -> void:
	var sim := SimWorld.from_scenario(SQUAD_SCENARIO)
	sim.command.resources.clear_schedule()
	var c := sim.units.squad_by_key("rescue1").crews[0]
	assert_eq(c.list.size(), 4, "구조 분대 4명")
	var cell := sim.pathfinder.nearest_walkable(1, Vector2i(28, 26))
	var goal := Vector3i(cell.x, cell.y, 1)
	sim.units.order_move([c.id] as Array[int], goal, sim.pathfinder)
	for ff in c.list:
		assert_true(ff.is_moving(), "%s도 같이 움직인다" % ff.name)
	assert_true(_until(sim, func() -> bool: return c.list.all(func(f: Firefighter) -> bool: return not f.is_moving()), 60.0), "모두 도착")
	assert_true(c.leader.cell3() == goal, "선두는 목표 칸에")
	var cells := {}
	for i in c.list.size():
		var ff := c.list[i]
		cells[ff.cell3()] = true
		assert_true(ff.pos.distance_to(c.leader.pos) <= float(i) * 1.5 + 0.1, "%d번째는 선두 뒤 %d칸 안 (%.1f)" % [i + 1, i, ff.pos.distance_to(c.leader.pos)])
	assert_eq(cells.size(), 4, "줄지어 선다 — 겹치지 않음")


func test_commander_alights_from_passenger_door() -> void:
	var sim := SimWorld.from_scenario(SQUAD_SCENARIO)
	var res := sim.command.resources
	res.clear_schedule()
	res.arrival_drive = true
	var cmd := sim.command.commander
	var post := cmd.pos
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 5.0}))
	sim.step_ticks(1)
	assert_true(cmd.aboard, "선착대장은 현장에 먼저 와 있지 않다 — 선착 펌프차를 타고 온다")
	# 타고 있는 동안에는 이동 지시를 받지 않는다
	sim.issue(CommandOrder.make("commander_move", [], 0, Vector3i(8, 26, 1)))
	sim.step_ticks(1)
	assert_true(not cmd.is_moving(), "차 안에서는 움직이지 않는다")
	var is_cmd := func(a: Dictionary) -> bool: return int(a.ff) == ResourceSystem.COMMANDER_ID
	assert_true(_until(sim, func() -> bool: return res.alighting.any(is_cmd), 120.0), "선착 펌프차가 서면 내린다")
	var v := res.first_pump()
	var side := Vector2(-v.heading.y, v.heading.x)
	var doors := ResourceSystem.rider_doors(v.type)
	assert_true(doors.all(func(d: Dictionary) -> bool: return str(d.seat) != "운전석"), "운전석 문은 하차에 쓰지 않는다")
	assert_eq(str(doors[0].seat), "조수석", "첫째 문 = 조수석 (팀장 자리)")
	assert_true(cmd.pos.distance_to(ResourceSystem.door_point(v, doors[0])) <= 1.5, "선착대장은 조수석 문 앞 (%.1f칸)" % cmd.pos.distance_to(ResourceSystem.door_point(v, doors[0])))
	# 분대원 3명은 뒷자리 문으로 — 운전석(앞·왼쪽) 자리에는 아무도 없다
	var crew := sim.units.squad_by_key("pump1").crews[0]
	for ff in crew.list:
		assert_true(ff.aboard, "분대원도 탄 채로 문 앞에")
		var rel := ff.pos - v.pos
		var front_left := rel.dot(side) < 0.0 and rel.dot(v.heading) > v.length_cells * 0.21
		assert_true(not front_left, "%s는 운전석 문으로 내리지 않는다" % ff.name)
		assert_true(rel.dot(v.heading) < v.length_cells * 0.21, "%s는 뒷자리 문 (조수석은 선착대장)" % ff.name)
	assert_true(_until(sim, func() -> bool: return not res.arriving_now(), 120.0), "모두 내림")
	assert_true(not cmd.aboard, "선착대장도 내렸다")
	assert_true(_until(sim, func() -> bool: return not cmd.is_moving() and cmd.pos.distance_to(post) < 0.6, 60.0), "지휘 자리까지 걸어간다 (%.1f칸)" % cmd.pos.distance_to(post))
	# 내린 뒤에는 이동 지시를 받는다
	sim.issue(CommandOrder.make("commander_move", [], 0, Vector3i(8, 26, 1)))
	sim.step_ticks(2)
	assert_true(cmd.is_moving(), "내린 뒤에는 움직인다")


func test_late_squad_officer_takes_passenger_door() -> void:
	var sim := SimWorld.from_scenario(SQUAD_SCENARIO)
	var res := sim.command.resources
	assert_true(_until(sim, func() -> bool: return not sim.events.of_type("squad_staged").is_empty(), 400.0), "후착 분대가 대기 장소에 선다")
	var squad := sim.units.squads[sim.units.squads.size() - 1]
	assert_eq(squad.crews.size(), 1, "후착 분대도 조 하나")
	var c := squad.crews[0]
	assert_eq(sim.units.crew_name(c), squad.name, "분대 이름으로 부른다")
	var v := sim.units.vehicles_of_squad(squad.id)[0]
	var doors := ResourceSystem.rider_doors(v.type)
	var o := c.officer()
	assert_true(o != null, "팀장 있음")
	assert_true(o.aboard and o.pos.distance_to(ResourceSystem.door_point(v, doors[0])) <= 1.5, "팀장은 조수석 문 앞")
	assert_true(_until(sim, func() -> bool: return res.alighting.is_empty(), 10.0), "곧 내린다")
	assert_true(_until(sim, func() -> bool: return c.list.all(func(f: Firefighter) -> bool: return not f.is_moving()), 30.0), "차 옆에 모인다")
	for ff in c.list:
		assert_true(not ff.aboard and not v.contains(ff.pos), "%s 내림 · 차체 밖" % ff.name)
