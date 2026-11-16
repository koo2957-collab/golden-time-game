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
		# 간격 line_gap_cells칸 (1m, 2026-11-17)마다 한 사람 — 대각선 길이면 조금 더 멀다
		var gap: int = sim.units.line_gap_cells
		assert_true(ff.pos.distance_to(c.leader.pos) <= float(i * gap) * 1.5 + 0.1, "%d번째는 선두 뒤 %d칸 안 (%.1f)" % [i + 1, i * gap, ff.pos.distance_to(c.leader.pos)])
		if i > 0:
			assert_true(ff.pos.distance_to(c.list[i - 1].pos) >= float(gap) * 0.9, "%d번째는 앞사람과 %d칸쯤 떨어진다 (%.1f)" % [i + 1, gap, ff.pos.distance_to(c.list[i - 1].pos)])
	assert_eq(cells.size(), 4, "줄지어 선다 — 겹치지 않음")


## 구조1 분대(4명)를 2층에서 가장 큰 방에 세우고 그 방 검색을 시킨다. second_pair가 false면 넷째 조원을 쓰러뜨려 한 짝만 돌게 한다.
## → [검색에 걸린 틱 (-1 = 못 끝냄), 두 짝으로 나눴는가, 첫째·둘째 짝 앞사람이 가장 멀어진 거리(칸)]
func _search_big_room(second_pair: bool) -> Array:
	var sim := SimWorld.from_scenario(SQUAD_SCENARIO)
	sim.command.resources.clear_schedule()
	sim.tactical.set_level("입문")
	sim.command.interior.enabled = false
	var room: Compartment = null
	for r in sim.fire.comps:
		if r.level == 2 and (room == null or r.cells.size() > room.cells.size()):
			room = r
	@warning_ignore("integer_division")
	var cell: Vector2i = room.cells[room.cells.size() / 2]
	var c := sim.units.squad_by_key("rescue1").crews[0]
	for ff in c.list:
		ff.pos = Vector2(cell) + Vector2(0.5, 0.5)
		ff.prev_pos = ff.pos
		ff.level = 2
		ff.prev_level = 2
	sim.command.entry_allowed[c.squad_id] = true
	if not second_pair:
		c.list[3].incapacitated = true
	assert_true(sim.rescue.order_search(c.id, Vector3i(cell.x, cell.y, 2), sim.clock.tick), "검색 시작")
	var task: RescueSystem.SearchTask = sim.rescue.task_of_crew(c.id)
	var split := false
	var apart := 0.0
	var done := -1
	for i in roundi(240.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		split = split or task.split
		apart = maxf(apart, c.list[0].pos.distance_to(c.list[2].pos))
		if room.searched_tick >= 0 and sim.rescue.task_of_crew(c.id) == null:
			done = i
			break
	return [done, split, apart]


func test_rescue_squad_searches_room_in_two_pairs() -> void:
	var two := _search_big_room(true)
	var one := _search_big_room(false)
	assert_true(int(two[0]) >= 0, "두 짝 검색을 끝낸다")
	assert_true(bool(two[1]), "방에 들어서면 남은 지점을 두 짝이 나눈다")
	assert_true(float(two[2]) > 2.0, "두 짝이 서로 다른 쪽을 돈다 (가장 멀어진 거리 %.1f칸)" % float(two[2]))
	assert_true(int(one[0]) >= 0 and not bool(one[1]), "한 사람이 쓰러지면 나누지 않고 한 짝이 다 돈다")
	assert_true(int(two[0]) < int(one[0]), "두 짝이면 더 빨리 끝난다 (%d틱 < %d틱)" % [int(two[0]), int(one[0])])


func test_mate_and_second_pair() -> void:
	var units := _units(REINFORCEMENTS)
	var pump := units.squad_by_key("pump2").crews[0]
	assert_true(pump.mate() == pump.list[1], "선두의 짝 = 다음 일하는 조원")
	pump.list[1].incapacitated = true
	assert_true(pump.mate() == pump.list[2], "쓰러지면 그다음 조원이 짝")
	assert_true(pump.mate() != pump.officer(), "진압 팀장은 드는 사람이 아니다")
	var rescue := units.squad_by_key("rescue2").crews[0]
	assert_eq(rescue.second_pair().size(), 2, "4명 분대는 둘째 짝이 있다")
	rescue.list[3].incapacitated = true
	assert_true(rescue.second_pair().is_empty(), "한 사람이 쓰러지면 둘째 짝 없음")
	var first := _units(ROSTER).squad_by_key("pump1").crews[0]
	assert_true(first.second_pair().is_empty(), "3명 분대는 둘째 짝 없음")


func test_split_pairs_by_role() -> void:
	var units := _units(REINFORCEMENTS)
	# 진압: [관창수 + 보조1] / [팀장 + 보조2] — 팀장이 둘째 조의 선두
	var pump := units.squad_by_key("pump2")
	var officer := pump.crews[0].officer()
	var made := units.split_squad(pump)
	assert_true(made != null and pump.crews.size() == 2, "두 조가 된다")
	assert_eq(pump.crews[0].leader.role, "관창수", "1조 선두는 관창수 (수관·임무를 이어 간다)")
	assert_eq(pump.crews[0].list.size(), 2, "1조 2명")
	assert_true(made.leader == officer and made.list.size() == 2, "2조 선두는 팀장")
	assert_eq(units.crew_name(made), "진압2 2조", "나뉜 조는 조 번호로 부른다")
	assert_true(units.get_crew(made.id) == made and made in units.crews, "새 조도 조 목록에")
	assert_true(made.list.all(func(ff: Firefighter) -> bool: return ff.crew_id == made.id), "대원의 조 번호도 바뀐다")
	# 3명 분대와 이미 나뉜 분대는 나눌 수 없다
	assert_true(units.split_squad(pump) == null, "이미 나뉜 분대")
	assert_true(_units(ROSTER).split_squad(_units(ROSTER).squad_by_key("pump1")) == null, "3명 분대는 나누지 않는다")
	# 합치면 처음 순서로, 비운 조는 조 목록에서 빠진다 — 그 id를 물어도 선두는 합쳐진 조의 선두
	assert_true(units.merge_squad(pump, pump.crews[0], true), "합치기")
	var whole := pump.crews[0]
	assert_eq(whole.list.size(), 4, "다시 4명")
	assert_true(whole.leader.role == "관창수" and whole.list[3] == officer, "처음 편성 순서로")
	assert_eq(units.crew_name(whole), "진압2", "다시 분대 이름으로")
	assert_true(not made in units.crews and not units.crew_active(made.id), "비운 조는 활동 목록에 없다")
	assert_true(units.get_crew(made.id).leader == whole.leader, "비운 조의 선두 = 합쳐진 조의 선두 (안전)")
	# 다시 나누면 같은 조 id를 쓴다
	var again := units.split_squad(pump)
	assert_true(again == made and again.id == made.id, "같은 조를 되살린다")
	# 일하는 조에 합류하면 그 조의 조원 뒤에 붙는다 (팀장 조가 남는 경우 팀장이 선두)
	assert_true(units.merge_squad(pump, again, false), "2조에 1조가 합류")
	assert_true(pump.crews[0] == again and again.leader == officer and again.list.size() == 4, "남은 조의 선두 그대로")


func test_regroup_order_by_radio() -> void:
	var sim := SimWorld.from_scenario(SQUAD_SCENARIO)
	sim.command.resources.clear_schedule()
	var squad := sim.units.squad_by_key("rescue1")
	var whole := squad.crews[0]
	# 3명 분대는 거절 (이유를 기록)
	var pump := sim.units.squad_by_key("pump1")
	sim.issue(CommandOrder.make("regroup", [pump.id] as Array[int], 1))
	sim.step_ticks(2)
	var no := sim.events.of_type("regroup_rejected")
	assert_true(no.size() == 1 and str(no[0].reason).contains("4명"), "3명 분대는 나눌 수 없다고 알린다 (%s)" % [no])
	# 나누기: 무전이 닿아야 바뀐다
	sim.issue(CommandOrder.make("regroup", [squad.id] as Array[int], 1))
	sim.step_ticks(1)
	assert_eq(squad.crews.size(), 1, "지시가 닿기 전에는 그대로")
	assert_true(_until(sim, func() -> bool: return squad.crews.size() == 2, 60.0), "무전이 닿으면 두 조")
	assert_eq(sim.events.of_type("squad_split").size(), 1, "나누기 기록")
	var second := squad.crews[1]
	assert_true(squad.crews[0] == whole and whole.officer() != null, "구조 1조에 팀장")
	assert_eq(sim.units.crew_name(second), "구조1 2조", "2조")
	# 2조만 따로 움직인다
	var at := whole.leader.pos
	var cell := sim.pathfinder.nearest_walkable(1, Vector2i(28, 26))
	sim.units.order_move([second.id] as Array[int], Vector3i(cell.x, cell.y, 1), sim.pathfinder)
	assert_true(_until(sim, func() -> bool: return not second.leader.is_moving() and second.leader.pos.distance_to(at) > 4.0, 60.0), "2조가 따로 간다")
	assert_true(whole.leader.pos.distance_to(at) < 0.1, "1조는 그 자리에")
	# 두 조 모두 일하면 합칠 수 없다
	sim.command.safety.roles[whole.id] = SafetySystem.Role.RIT
	sim.command.safety.roles[second.id] = SafetySystem.Role.OFFICER
	assert_true(sim.regroup_reason(squad.id, false).contains("모두 임무 중"), "둘 다 임무 중이면 합치기 불가")
	sim.command.safety.roles.erase(whole.id)
	sim.command.safety.roles.erase(second.id)
	# 합치기: 흩어진 조원이 선두 곁으로 모인다
	sim.issue(CommandOrder.make("regroup", [squad.id] as Array[int], 0))
	assert_true(_until(sim, func() -> bool: return squad.crews.size() == 1, 60.0), "다시 한 분대")
	assert_true(squad.crews[0] == whole and whole.list.size() == 4, "1조가 남고 4명")
	assert_true(not sim.units.crew_active(second.id), "2조는 비었다")
	assert_true(_until(sim, func() -> bool: return whole.list.all(func(ff: Firefighter) -> bool: return not ff.is_moving() and ff.pos.distance_to(whole.leader.pos) <= 3.0), 60.0), "선두 곁으로 모인다")
	assert_eq(sim.events.of_type("squad_merged").size(), 1, "합치기 기록")
	# 비운 조 id가 남아 있어도 진행에 문제없다
	sim.step_ticks(50)
	assert_eq(sim.units.crew_name(whole), "구조1", "분대 이름")


## 한 명 보내기 지시를 내리고 그 1인 조가 생길 때까지 기다린다 → 1인 조 (없으면 null)
func _send_solo(sim: SimWorld, squad: Squad, task: String) -> Crew:
	sim.issue(CommandOrder.make("solo", [squad.id] as Array[int], 0, Vector3i.ZERO, {"task": task}))
	_until(sim, func() -> bool: return sim.units.solo_of(squad) != null, 60.0)
	return sim.units.solo_of(squad)


func test_solo_water_help_and_return() -> void:
	var sim := SimWorld.from_scenario(SQUAD_SCENARIO)
	sim.command.resources.clear_schedule()
	var squad := sim.units.squad_by_key("pump1")
	var main := squad.crews[0]
	var who: Firefighter = sim.units.detach_candidate(main)
	assert_true(who == main.list[2] and who.role == "관창보조", "나갈 사람 = 마지막 조원(관창보조2)")
	# 물탱크차가 혼자 소화전을 점령하기 시작한다
	var tanker: Vehicle = null
	for v in sim.units.vehicles:
		if v.type == "물탱크차":
			tanker = v
	tanker.pos = Vector2(sim.building.hydrants[0]) + Vector2(0.5, 2.0)
	sim.water.connect_hydrant(tanker.id, 0, 0)
	assert_eq(int(tanker.work.people), 1, "운전원 혼자 시작")
	var alone_s := float(tanker.work.remain)
	var solo := _send_solo(sim, squad, "water_help")
	assert_true(solo != null and solo.solo and solo.list.size() == 1 and solo.leader == who, "한 명이 떨어져 나간다")
	assert_eq(main.list.size(), 2, "분대에는 2명이 남는다")
	assert_eq(sim.units.crew_name(solo), "진압1 %s 대원" % who.name, "나간 대원 이름")
	assert_eq(sim.units.crew_name(main), "진압1", "남은 분대는 그대로 분대 이름")
	assert_eq(sim.solo_label(solo.id), "급수 지원", "이름표에 맡은 임무")
	# 나간 대원에게는 직접 명령할 수 없다
	sim.issue(MoveCommand.new([solo.id] as Array[int], Vector3i(8, 26, 1)))
	sim.step_ticks(2)
	assert_eq(sim.events.of_type("solo_order_rejected").size(), 1, "나간 대원에게 내린 명령은 거절")
	# 또 한 명은 보낼 수 없다 (이미 나가 있고, 남은 조는 2명)
	assert_true(sim.solo_reason(squad.id, "water_help") != "", "한 번에 한 명만")
	# 차 옆에 닿으면 그때부터 둘이서 — 남은 시간이 절반
	assert_true(_until(sim, func() -> bool: return tanker.work.is_empty() or int(tanker.work.people) == 2, 120.0), "차에 닿아 돕는다")
	assert_eq(sim.events.of_type("work_helped").size(), 1, "도움 기록")
	var started := sim.clock.tick
	assert_true(_until(sim, func() -> bool: return tanker.work.is_empty(), alone_s), "혼자 할 때보다 빨리 끝난다 (%d틱)" % (sim.clock.tick - started))
	assert_eq(tanker.hydrant, 0, "소화전 연결")
	# 일이 끝나면 스스로 돌아와 합류한다
	assert_true(_until(sim, func() -> bool: return sim.units.solo_of(squad) == null, 120.0), "스스로 복귀")
	assert_true(main.list.size() == 3 and main.list[2] == who and who.crew_id == main.id, "제자리로 돌아온다")
	assert_true(not sim.units.crew_active(solo.id) and sim.solos.is_empty(), "1인 조는 비었다")
	assert_eq(sim.events.of_type("solo_back").size(), 1, "복귀 기록")


func test_solo_only_from_outside_and_three_people() -> void:
	var sim := SimWorld.from_scenario(SQUAD_SCENARIO)
	sim.command.resources.clear_schedule()
	var pump := sim.units.squad_by_key("pump1")
	var rescue := sim.units.squad_by_key("rescue1")
	# 주택에는 방재실이 없다
	assert_true(sim.solo_reason(pump.id, "office").contains("방재실"), "방재실 없는 건물 (%s)" % sim.solo_reason(pump.id, "office"))
	# 구조대는 방화문 파괴기를 이미 가지고 있다
	assert_true(sim.solo_reason(rescue.id, "fetch").contains("이미"), "이미 가진 장비")
	assert_eq(sim.solo_reason(pump.id, "fetch"), "", "진압 분대는 가져올 수 있다")
	# 분대가 건물 안에 있으면 한 명을 보낼 수 없다 (2인 1조)
	var room: Compartment = null
	for r in sim.fire.comps:
		if r.level == 2 and (room == null or r.cells.size() > room.cells.size()):
			room = r
	@warning_ignore("integer_division")
	var cell: Vector2i = room.cells[room.cells.size() / 2]
	var at := pump.crews[0].leader.pos
	for ff in pump.crews[0].list:
		ff.pos = Vector2(cell) + Vector2(0.5, 0.5)
		ff.level = 2
	assert_true(sim.solo_reason(pump.id, "fetch").contains("건물 안"), "건물 안의 분대")
	sim.issue(CommandOrder.make("solo", [pump.id] as Array[int], 0, Vector3i.ZERO, {"task": "fetch"}))
	sim.step_ticks(2)
	assert_true(sim.events.of_type("solo_rejected").size() == 1 and sim.units.solo_of(pump) == null, "거절하고 이유를 알린다")
	for ff in pump.crews[0].list:
		ff.pos = at
		ff.level = 1
	# 나뉜 2명 조에서는 보낼 수 없다
	sim.units.split_squad(rescue)
	assert_true(sim.solo_reason(rescue.id, "water_help").contains("2명"), "2명 조")
	# 한 명이 나가 있으면 나누기·합치기도 안 된다
	sim.units.merge_squad(rescue, rescue.crews[0], true)
	var solo := _send_solo(sim, rescue, "water_help")
	assert_true(solo != null, "4명 분대에서 한 명")
	assert_true(sim.regroup_reason(rescue.id, true).contains("나가 있음"), "한 명이 나가 있으면 나누지 않는다")
	# 복귀 지시
	sim.issue(CommandOrder.make("recall", [rescue.id] as Array[int]))
	assert_true(_until(sim, func() -> bool: return sim.units.solo_of(rescue) == null, 120.0), "복귀 지시로 돌아온다")
	assert_eq(rescue.crews[0].list.size(), 4, "다시 4명")


func test_solo_fetches_equipment_for_the_squad() -> void:
	var sim := SimWorld.from_scenario(SQUAD_SCENARIO)
	sim.command.resources.clear_schedule()
	var squad := sim.units.squad_by_key("pump1")
	var main := squad.crews[0]
	assert_true(not main.has_item("fire_door_breaker"), "진압 분대는 방화문 파괴기가 없다")
	var solo := _send_solo(sim, squad, "fetch")
	assert_true(solo != null, "한 명이 가지러 간다")
	assert_true(_until(sim, func() -> bool: return sim.units.solo_of(squad) == null, 240.0), "가져와서 합류")
	assert_true(main.has_item("fire_door_breaker"), "분대가 방화문 파괴기를 갖는다")
	assert_eq(main.list.size(), 3, "다시 3명")
	var back := sim.events.of_type("solo_back")
	assert_true(back.size() == 1 and str(back[0].item) != "", "전달 기록 (%s)" % [back])


## 팀장(분대 지휘관)만 머리 위 ★ 표시 대상 (2026-11-17 — 헬멧 띠 대신). 분대마다 팀장은 한 명
func test_officer_marked_once_per_squad() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/dev_squad_house_fire.json")
	for squad in sim.units.squads:
		var officers := 0
		for c in squad.crews:
			for ff in c.list:
				if ff.officer:
					officers += 1
		assert_true(officers <= 1, "%s 팀장 %d명" % [squad.name, officers])
	assert_true(PlanStyle.OFFICER_STAR.a > 0.0, "★ 색")


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
