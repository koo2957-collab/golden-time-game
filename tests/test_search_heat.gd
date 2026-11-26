extends TestSuite
## 층 인명검색이 화염·열기로 화점실에 못 들어갈 때 (2026-11-26 사용자·현직 소방관):
## 화점실을 '화염으로 미검색'으로 두고 문을 닫은 뒤 다른 실을 차례로 검색한다 — 같은 방으로 되풀이해 가지 않는다


func _living(sim: SimWorld) -> Compartment:
	for c in sim.fire.comps:
		if c.id == "1F_living":
			return c
	return null


## 거실 소파가 30초 탄 판 (화점실 = 거실)
func _burning_sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	sim.step_ticks(300)
	assert_true(sim.fire.grid.burning.size() > 0, "거실이 탄다")
	return sim


func test_heat_skip_moves_on_to_next_room() -> void:
	var sim := _burning_sim()
	var living := _living(sim)
	var tac := sim.tactical
	tac.order("search_floor", 0, Vector3i(13, 17, 1), sim.clock.tick)
	var t := tac.task_of_crew(0)
	assert_true(t != null and t.room == living.index, "층 검색은 화점실(거실)부터")
	# 거실로 가다 화염·열기에 막혔다
	tac.halt_for_heat(0, sim.clock.tick, living.display_name())
	var skipped := sim.events.of_type("search_skipped")
	assert_eq(skipped.size(), 1, "건너뛴다고 무전")
	assert_true(tac.heat_skipped.has(living.index), "거실을 건너뛴 방으로 기억")
	assert_eq(sim.events.of_type("tactical_halt").size(), 0, "지시를 기다리며 멈추지 않는다")
	var next: Variant = null
	for i in roundi(90.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		var nt := tac.task_of_crew(0)
		if nt != null and nt.room != living.index:
			next = nt
			break
	assert_true(next != null, "다음 방을 검색하러 간다")
	if next != null:
		assert_true((next as TacticalSystem.Task).floor_action == "search_floor", "층 검색을 이어 간다")
	var closed := sim.events.of_type("door_closed").size() + sim.events.of_type("door_left_open").size()
	assert_true(closed >= 1, "거실 문을 닫았거나(%d) 닫지 못했다고 알렸다" % sim.events.of_type("door_closed").size())


## 다시 검색을 시켜도 한동안·초진 전에는 그 방을 건너뛴다. 초진 뒤에는 다시 검색한다
func test_reorder_still_skips_until_knockdown() -> void:
	var sim := _burning_sim()
	var living := _living(sim)
	var tac := sim.tactical
	tac.order("search_floor", 0, Vector3i(13, 17, 1), sim.clock.tick)
	tac.halt_for_heat(0, sim.clock.tick, living.display_name())
	tac.cancel(0)
	tac.order("search_floor", 0, Vector3i(13, 17, 1), sim.clock.tick + 1)
	var t := tac.task_of_crew(0)
	assert_true(t != null and t.room != living.index, "다시 시켜도 거실은 건너뛴다")
	sim.phases.knockdown_tick = sim.clock.tick + 2
	assert_true(not tac.heat_skipping(living.index, sim.clock.tick + 3), "초진 뒤에는 다시 검색 대상")


## 실제 열기 (사용자 지적 재현): 크게 번진 거실 쪽으로 층 검색을 시키면 한 번 막힌 뒤 거실로 되풀이해 가지 않는다
func test_big_fire_does_not_loop_to_fire_room() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	sim.step_ticks(roundi(240.0 / SimClock.TICK_DT))
	var living := _living(sim)
	var tac := sim.tactical
	tac.order("search_floor", 0, Vector3i(13, 17, 1), sim.clock.tick)
	var to_living := 0
	var last_room := -2
	for i in roundi(240.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		var t := tac.task_of_crew(0)
		var r := t.room if t != null else -1
		if r != last_room and r == living.index:
			to_living += 1
		last_room = r
	var c: Crew = sim.units.crews[0]
	var downs := 0
	for ff in c.members():
		if ff.incapacitated:
			downs += 1
	assert_true(to_living <= 1, "거실로 향한 검색 %d번 (되풀이하지 않는다)" % to_living)
	assert_eq(downs, 0, "쓰러진 대원 없음")
	print("    막힘 %d · 건너뜀 %d · 문 닫음 %d · 검색 완료 보고 %s" % [sim.events.of_type("heat_blocked").size(), sim.events.of_type("search_skipped").size(),
		sim.events.of_type("door_closed").size(), str(sim.events.of_type("tactical_done").map(func(e: Dictionary) -> String: return str(e.text)))])


## 사용자 지적 재현 (튜토리얼): 복도 출입문으로 들어온 구조1이 화점실(거실)로 가다 지나치는 방1의 아이를 보면 바로 구한다
func test_search_diverts_to_seen_victim() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/sop214_1_day_living.json", false)
	sim.step_ticks(roundi(120.0 / SimClock.TICK_DT))
	var rc: Crew = null
	for c in sim.units.crews:
		if rc == null and sim.units.crew_name(c).begins_with("구조1"):
			rc = c
	var entry: EntryPoints.Entry = null
	for e: EntryPoints.Entry in sim.entries.list:
		if e.name.contains("복도"):
			entry = e
	assert_true(rc != null and entry != null, "구조1과 복도 출입문")
	for ff in rc.members():
		ff.pos = Vector2(entry.outside.x + 0.5, entry.outside.y + 0.5)
		ff.level = entry.outside.z
		ff.aboard = false
		ff.path.clear()
	sim.tactical.order("search_floor", rc.id, Vector3i(entry.outside.x, entry.outside.y, 1), sim.clock.tick)
	var found_tick := -1
	var pick_tick := -1
	for i in roundi(120.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if found_tick < 0 and not sim.events.of_type("victim_found").is_empty():
			found_tick = sim.clock.tick
		if not sim.events.of_type("rescue_pickup").is_empty():
			pick_tick = sim.clock.tick
			break
	assert_true(found_tick >= 0, "아이를 발견")
	assert_true(pick_tick >= 0, "아이를 업었다")
	if found_tick >= 0 and pick_tick >= 0:
		assert_true(pick_tick - found_tick <= roundi(20.0 / SimClock.TICK_DT), "발견하고 곧 업는다 (%.0f초 뒤)" % ((pick_tick - found_tick) * SimClock.TICK_DT))
