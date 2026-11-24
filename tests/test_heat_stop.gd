extends TestSuite
## 열기로 진입할 수 없으면 인명검색·구조를 멈추고 물러나 보고한다 (2026-11-24 사용자: "화염이 많아 진입이 불가능하면 자동으로
## 후퇴해야 하는데 그 자리에서 왔다 갔다 한다"). 전에는 검색·구조가 1초마다(구조는 틱마다) 다시 길을 잡고 열 규칙이 그 길을 지워
## 문턱에서 떨었고, 물러나도 임무가 남아 되돌아갔고, 보고도 없었다. 문턱 안쪽에 서 있다가 플래시오버에 쓰러지기도 했다.

const SCN := "res://data/scenarios/dev_squad_house_fire.json"
const LIVING := Vector3i(14, 16, 1)


## 6분 탄 집의 복도에 구조대를 한 줄로 세운다 (거실은 플래시오버 직전)
func _burning_house() -> Array:
	var sim := SimWorld.from_scenario(SCN, false)
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.doors.sync_blocking()
	sim.step_ticks(3600)
	var crew: Crew = null
	for c in sim.units.crews:
		if sim.units.squads[c.squad_id].type == "구조대":
			crew = c
	for k in crew.list.size():
		var ff: Firefighter = crew.list[k]
		ff.pos = Vector2(27.5 + k, 12.5)
		if not sim.pathfinder.passable(1, floori(ff.pos.x), floori(ff.pos.y)):
			ff.pos = Vector2(27.5, 12.5)
		ff.prev_pos = ff.pos
		ff.level = 1
		ff.prev_level = 1
		ff.path.clear()
	return [sim, crew]


## seconds 동안 돌리며 대원마다 걷는 방향이 뒤집힌 횟수를 센다
func _flips(sim: SimWorld, crew: Crew, seconds: float) -> Array[int]:
	var last_pos: Array[Vector2] = []
	var last_dir: Array[Vector2] = []
	var flips: Array[int] = []
	for ff in crew.list:
		last_pos.append(ff.pos)
		last_dir.append(Vector2.ZERO)
		flips.append(0)
	for i in roundi(seconds / SimClock.TICK_DT):
		sim.step_ticks(1)
		for k in crew.list.size():
			var d: Vector2 = crew.list[k].pos - last_pos[k]
			last_pos[k] = crew.list[k].pos
			if d.length() < 0.001:
				continue
			if last_dir[k] != Vector2.ZERO and d.normalized().dot(last_dir[k]) < -0.5:
				flips[k] += 1
			last_dir[k] = d.normalized()
	return flips


func _halts(sim: SimWorld) -> Array:
	return sim.events.of_type("tactical_halt").filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "heat")


## 불난 방 인명검색: 문턱에서 떨지 않고, 임무를 멈추고 방 밖으로 물러나 한 번 보고한 뒤 기다린다
func test_search_into_burning_room_stops_and_reports() -> void:
	var made := _burning_house()
	var sim: SimWorld = made[0]
	var crew: Crew = made[1]
	var living := sim.fire.compartment_at(1, 12, 16)
	assert_true(sim.conditions.heat_at(1, Vector2i(LIVING.x, LIVING.y), true) >= 10.0, "거실은 들어갈 수 없을 만큼 뜨겁다")
	sim.issue(TacticalCommand.make("search", [crew.id] as Array[int], LIVING))
	var flips := _flips(sim, crew, 90.0)
	assert_true(flips.max() <= 2, "제자리에서 왔다 갔다 하지 않는다 (방향 뒤집힘 %s — 전에는 1인당 30번 넘게)" % [flips])
	var halts := _halts(sim)
	assert_eq(halts.size(), 1, "진입 불가를 한 번 보고한다")
	if not halts.is_empty():
		assert_true(str(halts[0].reason).contains("진입 불가") and str(halts[0].reason).contains("거실") and bool(halts[0].safety), "보고 내용 (%s)" % halts[0].reason)
	assert_true(sim.rescue.task_of_crew(crew.id) == null, "검색 임무를 멈췄다 (스스로 다시 들어가지 않는다)")
	var t := sim.tactical.task_of_crew(crew.id)
	assert_true(t == null or t.halted, "임무는 지시를 기다린다")
	for ff in crew.list:
		assert_true(not ff.incapacitated, "아무도 쓰러지지 않는다")
		assert_true(sim.fire.compartment_at(ff.level, floori(ff.pos.x), floori(ff.pos.y)) != living, "모두 불난 방 밖에 있다 (%s)" % ff.pos)
		assert_true(sim.conditions.heat_at(ff.level, Vector2i(ff.pos.floor()), ff.crouched) < 10.0, "위험하지 않은 곳에 선다")
	assert_true(not crew.leader.is_moving(), "물러난 자리에서 멈춰 있다")
	# 더 기다려도 되돌아가지 않는다 (전에는 약 21초마다 다시 들어갔다)
	var again := _flips(sim, crew, 40.0)
	assert_true(again.max() <= 1 and _halts(sim).size() == 1 and sim.rescue.task_of_crew(crew.id) == null, "되돌아가지 않고 보고도 되풀이하지 않는다 (%s)" % [again])


## 불난 방 안의 구조대상자를 데리러 가라는 지시도 같다 (전에는 틱마다 다시 길을 잡아 50초에 200번 넘게 떨었다)
func test_rescue_into_burning_room_stops() -> void:
	var made := _burning_house()
	var sim: SimWorld = made[0]
	var crew: Crew = made[1]
	var v: Victim = sim.rescue.victims[1]
	v.pos = Vector2(LIVING.x + 0.5, LIVING.y + 0.5)
	v.level = 1
	v.discovered = true
	sim.issue(EquipmentCommand.make("rescue", [crew.id] as Array[int], -1, v.id))
	var flips := _flips(sim, crew, 60.0)
	assert_true(flips.max() <= 2, "제자리에서 떨지 않는다 (방향 뒤집힘 %s)" % [flips])
	assert_true(sim.rescue.task_of_crew(crew.id) == null, "구조 임무를 멈췄다")
	assert_eq(_halts(sim).size(), 1, "진입 불가를 한 번 보고한다")
	for ff in crew.list:
		assert_true(not ff.incapacitated, "아무도 쓰러지지 않는다")


## 선두가 쓰러져도 남은 조원은 뜨거운 칸으로 걸어 들어가지 않는다
func test_members_do_not_walk_into_fire_when_leader_down() -> void:
	var made := _burning_house()
	var sim: SimWorld = made[0]
	var crew: Crew = made[1]
	crew.leader.incapacitated = true
	var mate: Firefighter = crew.list[1]
	var path := sim.pathfinder.find_path(mate.cell3(), LIVING)
	assert_true(path.size() > 3, "거실까지의 길")
	mate.set_path(path)
	for i in 600:
		sim.step_ticks(1)
	assert_true(not mate.incapacitated, "조원은 쓰러지지 않는다")
	assert_true(sim.conditions.heat_at(mate.level, Vector2i(mate.pos.floor()), mate.crouched) < 10.0, "위험한 칸 앞에서 멈췄다 (%s)" % mate.pos)
