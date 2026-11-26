extends TestSuite
## M6b: 잔불정리·재발화 (SOP 202-6)


## 거실 소파가 30초 탄 뒤 물로 모두 끈 상태. 불씨가 반드시 숨도록 확률을 1로 둔다
func _doused_sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	sim.rekindle._chance = 1.0
	sim.step_ticks(300)
	assert_true(sim.fire.grid.burning.size() > 0, "소파가 탄다")
	for i in sim.fire.grid.burning.duplicate():
		sim.fire.grid.apply_water(i, 1000.0, 1.0)
	sim.step_ticks(2)
	return sim


func _living(sim: SimWorld) -> Compartment:
	for c in sim.fire.comps:
		if c.id == "1F_living":
			return c
	return null


func test_embers_rekindle_if_left() -> void:
	var sim := _doused_sim()
	var rk := sim.rekindle
	assert_true(rk.embers.size() > 0, "물로 끈 셀에 불씨가 숨는다 (%d곳)" % rk.embers.size())
	assert_eq(sim.fire.grid.burning.size(), 0, "겉으로는 꺼짐")
	assert_true(rk.spotted_cells().is_empty(), "열화상으로 보기 전에는 표시되지 않는다")
	sim.step_ticks(roundi(500.0 / SimClock.TICK_DT))
	assert_true(sim.events.of_type("rekindle").size() >= 1, "그대로 두면 재발화")
	assert_true(rk.rekindles >= 1, "재발화 기록")


## 층 단위 잔불정리 (2026-11-16): 한 방을 마치면 같은 층의 다음 탄 방으로, 남은 방이 없으면 층 완료 보고
func test_floor_overhaul_continues_room_by_room() -> void:
	var sim := _doused_sim()
	var rk := sim.rekindle
	var living := _living(sim)
	# 같은 층의 다른 방 하나에도 탄 자리를 만든다 (가구가 탄 것처럼)
	var other: Compartment = null
	for c in sim.fire.comps:
		if other == null and c.level == 1 and c != living and c.cells.size() >= 4 and not sim.fire.is_exposure_comp(c):
			other = c
	assert_true(other != null, "1층에 다른 방이 있다")
	var g := sim.fire.grid
	var oc: Vector2i = other.cells[0]
	g.state[g.index(1, oc.x, oc.y)] = FuelGrid.State.BURNT
	var first: Vector3i = rk.next_floor_room(1, Vector2(14.5, 15.5))
	assert_true(first.x >= 0, "탄 방이 있다")
	sim.issue(EquipmentCommand.make("overhaul", [0], -1, 1, first))
	var both := func() -> bool: return living.overhauled_tick >= 0 and other.overhauled_tick >= 0
	for i in roundi(400.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if both.call():
			break
	assert_true(both.call(), "한 번 지시로 그 층의 탄 방 둘 다 잔불정리 (거실 %d, %s %d)" % [living.overhauled_tick, other.display_name(), other.overhauled_tick])
	sim.step_ticks(2)
	var done := sim.events.of_type("tactical_done").filter(func(e: Dictionary) -> bool: return str(e.text).contains("잔불정리 완료"))
	assert_eq(done.size(), 1, "층 잔불정리 완료 보고")
	assert_eq(rk.next_floor_room(1, Vector2.ZERO), Vector3i(-1, -1, -1), "남은 방 없음")


## 지시 창 화재진압 (floor_mission): 초진 뒤 그 층에 보이는 불이 없으면 층에 닿았을 때 층 잔불정리로 바뀐다
## (2026-11-17 — 전에는 화면 쪽에서 바로 잔불정리 명령을 내려 진입구·진입 허가를 건너뛰었다)
func test_floor_mission_attack_becomes_overhaul_after_knockdown() -> void:
	var sim := _doused_sim()
	sim.perception.enabled = false
	sim.phases.knockdown_tick = sim.clock.tick
	assert_true(sim.floor_overhaul_target(1, Vector2(14.5, 15.5)).x >= 0, "잔불정리할 방이 있다")
	sim.issue(CommandOrder.make("floor_mission", [0] as Array[int], 1, Vector3i.ZERO, {"kind": "attack", "entry": -1}))
	var started := false
	for i in roundi(120.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if not sim.events.of_type("overhaul_start").is_empty():
			started = true
			break
	assert_true(started, "층에 닿자 잔불정리 시작")
	assert_true(sim.rekindle.tasks.any(func(t: RekindleSystem.OverhaulTask) -> bool: return t.crew_id == 0 and t.floor == 1), "층 단위 잔불정리 작업")
	var attack := sim.events.of_type("tactical_start").filter(func(e: Dictionary) -> bool: return str(e.get("action", "")) == "진압")
	assert_eq(attack.size(), 0, "화재진압(방수)으로 시작하지 않는다")
	# 불이 보이면 그대로 화재진압
	var sim2 := _doused_sim()
	assert_eq(sim2.floor_overhaul_target(1, Vector2.ZERO), Vector3i(-1, -1, -1), "초진 전에는 잔불정리 아님")


func test_thermal_spot_and_overhaul() -> void:
	var sim := _doused_sim()
	var rk := sim.rekindle
	var crew := sim.units.get_crew(0)  # 진압1 1조: 열화상카메라
	assert_true(crew.thermal_camera, "열화상 조")
	for ff in crew.members():
		ff.path.clear()
		ff.pos = Vector2(14.5, 15.5)
		ff.prev_pos = ff.pos
	sim.step_ticks(10)
	assert_eq(sim.events.of_type("ember_spotted").size(), 1, "방에 들어가면 불씨를 찾는다")
	assert_eq(rk.spotted_cells().size(), rk.embers.size(), "찾은 불씨 표시")
	sim.issue(EquipmentCommand.make("overhaul", [0], -1, -1, Vector3i(14, 15, 1)))
	sim.step_ticks(roundi((rk.overhaul_seconds() + 8.0) / SimClock.TICK_DT))
	assert_eq(rk.embers.size(), 0, "잔불정리로 불씨 제거")
	assert_eq(sim.events.of_type("overhaul_done").size(), 1, "잔불정리 완료 기록")
	assert_true(_living(sim).overhauled_tick >= 0, "방에 잔불정리 표시")
	sim.step_ticks(roundi(500.0 / SimClock.TICK_DT))
	assert_eq(sim.events.of_type("rekindle").size(), 0, "재발화 없음")
	sim.end_activity("테스트")
	var r := Evaluator.evaluate(sim)
	for rule: Dictionary in r.rules:
		if rule.id == "fire.overhaul":
			assert_eq(rule.score, 1.0, "잔불정리 판정 (%s)" % rule.detail)


## 거실이 아무에게도 보이지 않게: 대원은 모두 차에 태우고, 지휘관은 창 관찰 거리(Perception.WINDOW_VIEW_CELLS) 밖으로
func _everyone_away(sim: SimWorld) -> void:
	for ff in sim.units.firefighters:
		ff.pos = Vector2(1.5, 1.5)
		ff.level = 1
		ff.path.clear()
		ff.aboard = true
	sim.command.commander.pos = Vector2(-Perception.WINDOW_VIEW_CELLS, -Perception.WINDOW_VIEW_CELLS)
	# 창 너머 시야는 몇 번에 한 번만 다시 계산한다 — 옛 시야가 남지 않게 여러 번
	for i in 12:
		sim.perception.update(sim.clock.tick)


## 재발화 보고 (2026-11-26, 기획안 5-9 '화점 재발생 보고', 원칙 7):
## 아무도 보지 못한 재발화는 알려지지 않고, 누군가 그 방의 불을 보면 그 조가 무전으로 보고한다 → 상황판 화점
func test_rekindle_reported_only_when_seen() -> void:
	var sim := _doused_sim()
	var rk := sim.rekindle
	var living := _living(sim)
	assert_true(rk.embers.size() > 0, "불씨가 숨었다")
	_everyone_away(sim)
	assert_true(not sim.perception.room_visible(living), "거실을 보는 사람이 없다")
	for e in rk.embers:
		e.rekindle_tick = sim.clock.tick + 1
	for i in 10:
		sim.step_ticks(1)
		_everyone_away(sim)
	assert_true(sim.events.of_type("rekindle").size() >= 1, "재발화가 났다")
	assert_eq(sim.events.of_type("rekindle_found").size(), 0, "아무도 못 봤으면 보고 없음")
	assert_true(not sim.knowledge.fires.has(living.index), "상황판에도 없다")
	assert_true(rk.unseen.has(living.index), "보지 못한 재발화로 기억한다")
	# 진압1 이 거실로 들어온다
	var c: Crew = sim.units.crews[0]
	var mid := Vector2(living.rect.get_center()) + Vector2(0.5, 0.5)
	for ff in c.members():
		ff.pos = mid
		ff.level = living.level
		ff.aboard = false
	for i in 120:
		sim.step_ticks(1)
		if not sim.events.of_type("rekindle_found").is_empty():
			break
	var found := sim.events.of_type("rekindle_found")
	assert_eq(found.size(), 1, "들어가서 보면 한 번 보고")
	if found.is_empty():
		return
	assert_eq(int(found[0].crew_id), c.id, "본 조가 보고한다")
	assert_eq(str(found[0].room), living.display_name(), "그 방")
	assert_true(not rk.unseen.has(living.index), "보고한 재발화는 잊는다")
	# 무전이 전달되면 상황판에 화점으로
	for i in roundi(30.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if sim.knowledge.fires.has(living.index):
			break
	assert_true(sim.knowledge.fires.has(living.index), "무전이 닿으면 상황판에 그 방 화점")


## 보고 전에 불이 저절로 꺼진 재발화는 잊는다 (보고하지 않는다)
func test_unseen_rekindle_forgotten_if_it_goes_out() -> void:
	var sim := _doused_sim()
	var rk := sim.rekindle
	var living := _living(sim)
	_everyone_away(sim)
	for e in rk.embers:
		e.rekindle_tick = sim.clock.tick + 1
	for i in 10:
		sim.step_ticks(1)
		_everyone_away(sim)
	assert_true(rk.unseen.has(living.index), "보지 못한 재발화")
	for i in sim.fire.grid.burning.duplicate():
		sim.fire.grid.apply_water(i, 1000.0, 1.0)
	for i in 10:
		sim.step_ticks(1)
		_everyone_away(sim)
	assert_true(not rk.unseen.has(living.index), "꺼지면 잊는다")
	assert_eq(sim.events.of_type("rekindle_found").size(), 0, "보고 없음")


## 거실 말고 1층 다른 방 하나에도 탄 자리를 만든다
func _burn_other_room(sim: SimWorld, living: Compartment) -> Compartment:
	var other: Compartment = null
	for c in sim.fire.comps:
		if other == null and c.level == 1 and c != living and c.cells.size() >= 4 and not sim.fire.is_exposure_comp(c):
			other = c
	var g := sim.fire.grid
	var oc: Vector2i = other.cells[0]
	g.state[g.index(1, oc.x, oc.y)] = FuelGrid.State.BURNT
	return other


## 재발화 감시 (2026-11-26, 기획안 5-9): 그 층의 탄 방을 차례로 돌며 머문다
func test_watch_rotates_burnt_rooms() -> void:
	var sim := _doused_sim()
	var rk := sim.rekindle
	var living := _living(sim)
	var other := _burn_other_room(sim, living)
	var rooms := rk.watch_rooms(1)
	assert_true(living in rooms and other in rooms, "감시할 탄 방 = 거실·%s (%d곳)" % [other.display_name(), rooms.size()])
	assert_true(rk.order_watch(0, 1, sim.clock.tick), "감시를 맡는다")
	assert_eq(sim.events.of_type("watch_start").size(), 1, "감시 시작 기록")
	assert_true(rk.watch_of_crew(0) != null, "감시 중")
	assert_true(not sim.squad_idle(0), "감시 중인 분대는 대기가 아니다")
	var w := rk.watch_of_crew(0)
	var both := func() -> bool: return w.visited.has(living.index) and w.visited.has(other.index)
	for i in roundi(400.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if both.call():
			break
	assert_true(both.call(), "두 방을 모두 들렀다 (%s)" % str(w.visited))
	rk.cancel(0)
	assert_true(rk.watch_of_crew(0) == null, "다른 지시를 받으면 감시를 그만둔다")


## 감시 분대가 머무는 방에서 재발화하면 바로 그 분대가 보고한다
func test_watch_crew_reports_rekindle() -> void:
	var sim := _doused_sim()
	var rk := sim.rekindle
	var living := _living(sim)
	_everyone_away(sim)
	var c: Crew = sim.units.crews[0]
	var mid := Vector2(living.rect.get_center()) + Vector2(0.5, 0.5)
	for ff in c.members():
		ff.pos = mid
		ff.level = 1
		ff.aboard = false
	assert_true(rk.order_watch(c.id, 1, sim.clock.tick), "거실 층 감시")
	for e in rk.embers:
		e.rekindle_tick = sim.clock.tick + 20
	for i in roundi(60.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if not sim.events.of_type("rekindle_found").is_empty():
			break
	var found := sim.events.of_type("rekindle_found")
	assert_eq(found.size(), 1, "재발화를 보고했다")
	if found.is_empty():
		return
	assert_eq(int(found[0].crew_id), c.id, "감시 분대가 보고")
	assert_true(int(found[0].since_s) <= 2, "곧바로 (%d초 뒤)" % int(found[0].since_s))


## 지시 창의 '재발화 감시' (층 임무 watch): 그 층에 닿으면 감시가 시작되고, 새 층 임무를 받으면 그만둔다
func test_floor_mission_watch() -> void:
	var sim := _doused_sim()
	var rk := sim.rekindle
	var living := _living(sim)
	var c: Crew = sim.units.crews[0]
	var mid := Vector2(living.rect.get_center()) + Vector2(0.5, 0.5)
	for ff in c.members():
		ff.pos = mid
		ff.level = 1
		ff.path.clear()
		ff.aboard = false
	sim.issue(CommandOrder.make("floor_mission", [c.id], 1, Vector3i.ZERO, {"kind": "watch", "entry": -1}))
	# 건물 안 분대에는 무전으로 지시한다 — 무전이 밀려 있으면 닿는 데 시간이 걸린다
	for i in roundi(60.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if rk.watch_of_crew(c.id) != null:
			break
	assert_true(rk.watch_of_crew(c.id) != null, "층에 닿으면 감시 시작")
	sim.issue(CommandOrder.make("floor_mission", [c.id], 1, Vector3i.ZERO, {"kind": "search", "entry": -1}))
	for i in roundi(60.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if rk.watch_of_crew(c.id) == null:
			break
	assert_true(rk.watch_of_crew(c.id) == null, "새 층 임무를 받으면 감시를 그만둔다")


## 불씨가 잘 숨는 곳 (2026-11-26, 기획안 5-9 ③): 재질마다 기본 배율 (data/materials ember) — 가구 항목의 ember 가 있으면 그 값
func test_ember_factor_by_material() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var g := sim.fire.grid
	var seen := {}
	for i in g.mat.size():
		var name := g.material_name(i)
		if name != "" and not seen.has(name):
			seen[name] = g.ember_factor[i]
	assert_true(seen.has("내장재"), "내장재 칸이 있다 (%s)" % str(seen))
	assert_true(float(seen.get("내장재", 1.0)) < 1.0, "바닥·벽 마감재는 불씨가 덜 숨는다 (%.2f)" % float(seen.get("내장재", 1.0)))
	for soft in ["침대", "소파"]:
		if seen.has(soft):
			assert_true(float(seen[soft]) > 1.0, "%s 는 불씨가 잘 숨는다 (%.2f)" % [soft, float(seen[soft])])
	var cfg := FireConfig.load_files(SimWorld.FIRE_PARAMS_PATH, SimWorld.MATERIALS_PATH)
	for m: String in cfg.materials:
		assert_true((cfg.materials[m] as Dictionary).has("ember"), "재질 %s 에 ember" % m)
