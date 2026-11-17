extends TestSuite
## 임무 완료 → 다음 지시 카드 (MISSION-DONE-01, 2026-11-17 사용자 결정): 임무를 마친 분대가 할 일 없이 서 있으면
## 완료 보고 뒤 철수·대기·다음 임무를 묻는다. 초진 뒤 받은 층 검색은 2차 검색이다.

const CARD := "MISSION-DONE-01"


func _until(sim: SimWorld, cond: Callable, max_s: float) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return cond.call()


func _place(c: Crew, level: int, cell: Vector2i) -> void:
	for ff in c.members():
		ff.path.clear()
		ff.level = level
		ff.prev_level = level
		ff.pos = Vector2(cell) + Vector2(0.5, 0.5)
		ff.prev_pos = ff.pos


## 기본 임무가 인명검색인 분대 (구조대)
func _search_crew(sim: SimWorld) -> Crew:
	for c in sim.units.crews:
		if sim._default_mission(c) == "search":
			return c
	return sim.units.get_crew(0)


## 그 층 화재 건물의 방 하나 가운데에 세운다
func _place_inside(sim: SimWorld, c: Crew, lv: int) -> void:
	for r in sim.fire.comps:
		if r.level == lv and not sim.fire.is_exposure_comp(r) and r.cells.size() >= 4:
			var cell := sim.tactical._room_cell(r)
			_place(c, lv, Vector2i(cell.x, cell.y))
			return


func _card(sim: SimWorld, id: int) -> CardSystem.Card:
	for q in sim.cards.queue:
		if q.id == CARD and q.crew_id == id:
			return q
	return null


func _option(q: CardSystem.Card, effect: String) -> int:
	for i in q.options.size():
		if str(q.options[i].get("effect", "")) == effect:
			return i
	return -1


func _mark_searched(sim: SimWorld, lv: int) -> void:
	for r in sim.fire.comps:
		if r.level == lv and not sim.fire.is_exposure_comp(r):
			r.searched_tick = 0


## 층 검색을 마치면 완료 보고 뒤 다음 지시를 묻고, '다음 임무'를 고르면 그 층 임무를 받는다
func test_floor_done_asks_next_order() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	var lv: int = sim.building.levels()[0]
	var top: int = sim.building.levels().max()
	assert_true(top > lv, "2층 이상 건물")
	var c := _search_crew(sim)
	_place_inside(sim, c, top)
	_mark_searched(sim, top)
	sim.tactical.order("search_floor", c.id, Vector3i(0, 0, top), sim.clock.tick)
	assert_true(sim.events.of_type("tactical_done").any(func(e: Dictionary) -> bool: return bool(e.get("final", false))), "층 검색 완료 보고 (임무 끝 표시)")
	assert_true(_until(sim, func() -> bool: return _card(sim, c.id) != null, 10.0), "잠시 뒤 다음 지시 카드")
	assert_true(sim.squad_idle(c.id), "할 일 없이 서 있음 (화면 '대기')")
	var q := _card(sim, c.id)
	var texts: Array = q.options.map(func(o: Dictionary) -> String: return str(o.text))
	assert_true(q.text.contains("검색 완료") and q.text.contains("공기"), "완료 내용과 공기 (%s)" % q.text)
	assert_true(_option(q, "withdraw") >= 0 and _option(q, "stand_by") >= 0 and _option(q, "next_task") >= 0, "철수·대기·다음 임무 (%s)" % [texts])
	assert_true(str(q.options[_option(q, "next_task")].text).contains("인명검색"), "다음 임무는 검색하지 않은 층 검색 (%s)" % [texts])
	assert_eq(str(q.options[_option(q, "next_task")].grade), "최선", "공기가 넉넉하면 다음 임무가 최선")
	sim.cards.answer(q.uid, _option(q, "next_task"), sim.clock.tick)
	assert_eq(str(sim.command.floor_missions.get(c.id, "")), "search", "그 층 검색 임무를 받는다")
	sim.step_ticks(roundi(6.0 / SimClock.TICK_DT))
	assert_true(_card(sim, c.id) == null, "다시 묻지 않는다")


## 공기가 절반 아래면 밖으로 나와 공기를 채우는 것이 최선. '현 위치 대기'는 그 자리에 선다
func test_air_low_prefers_withdraw() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	var top: int = sim.building.levels().max()
	var c := _search_crew(sim)
	_place_inside(sim, c, top)
	_mark_searched(sim, top)
	for ff in c.members():
		ff.air_l = ff.air_capacity * 0.3
	sim.tactical.order("search_floor", c.id, Vector3i(0, 0, top), sim.clock.tick)
	assert_true(_until(sim, func() -> bool: return _card(sim, c.id) != null, 10.0), "다음 지시 카드")
	var q := _card(sim, c.id)
	assert_eq(str(q.options[_option(q, "withdraw")].grade), "최선", "공기 부족 → 철수가 최선")
	assert_eq(str(q.options[_option(q, "next_task")].grade), "오답", "공기 부족인데 다음 임무는 오답")
	sim.cards.answer(q.uid, _option(q, "stand_by"), sim.clock.tick)
	assert_true(not sim.events.of_type("crew_hold").is_empty(), "현 위치 대기 보고")


## 임무가 이어지면(층 임무의 다음 방·새 명령) 묻지 않는다. 밖에 있고 할 일도 없으면 묻지 않는다
func test_no_card_when_busy_or_nothing_left_outside() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	var lv: int = sim.building.levels()[0]
	var c := _search_crew(sim)
	_place_inside(sim, c, lv)
	sim.tactical.order("search_floor", c.id, Vector3i(0, 0, lv), sim.clock.tick)
	sim.events.add(sim.clock.tick, "tactical_done", {"crew": sim.units.crew_name(c), "text": "시험", "crew_id": c.id, "final": true})
	sim.step_ticks(roundi(5.0 / SimClock.TICK_DT))
	assert_true(_card(sim, c.id) == null, "다른 임무 중이면 묻지 않는다")
	# 밖에 서 있고 검색할 곳도 없다
	sim.tactical.cancel(c.id)
	sim.rescue.cancel(c.id)
	for l in sim.building.levels():
		_mark_searched(sim, l)
	var e: EntryPoints.Entry = sim.entries.main_entries()[0]
	_place(c, e.level, Vector2i(e.outside.x, e.outside.y))
	sim.events.add(sim.clock.tick, "tactical_done", {"crew": sim.units.crew_name(c), "text": "시험", "crew_id": c.id, "final": true})
	sim.step_ticks(roundi(5.0 / SimClock.TICK_DT))
	assert_true(sim.next_task(c.id).is_empty(), "다음 임무 없음")
	assert_true(_card(sim, c.id) == null, "밖에서 할 일이 없으면 묻지 않는다")


## 화점 진압 완료를 보고받은 층은 마지막 모습이 '타는 중'이어도 다음 임무로 화재진압을 권하지 않는다.
## 그 뒤 그 층 화점 발견(또는 재발화) 보고가 오면 다시 권한다 (2026-11-17 화면 점검: 주방 화재에서 끈 직후 같은 층 화재진압 → '화점을 찾지 못함')
func test_cleared_floor_not_suggested_for_attack() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var lv: int = sim.building.levels()[0]
	var c: Crew = null
	for cr in sim.units.crews:
		if sim._default_mission(cr) == "attack":
			c = cr
			break
	assert_true(c != null, "진압 분대")
	_place_inside(sim, c, lv)
	var room: Compartment = null
	for r in sim.fire.comps:
		if r.level == lv and not sim.fire.is_exposure_comp(r) and r.cells.size() >= 4:
			room = r
			break
	var i := sim.fire.grid.index(lv, room.cells[0].x, room.cells[0].y)
	sim.perception.seen_tick[i] = 0
	sim.perception.seen_burning[i] = 1
	assert_eq(str(sim.next_task(c.id).get("kind", "")), "attack", "타는 것을 본 층 → 화재진압")
	sim.events.add(10, "tactical_done", {"crew": sim.units.crew_name(c), "text": "1층 화점 진압 완료", "crew_id": c.id, "final": true, "mission": "attack", "level": lv})
	var after: Dictionary = sim.next_task(c.id)
	assert_true(not (str(after.get("kind", "")) == "attack" and int(after.get("level", -1)) == lv), "진압 완료를 보고받은 층은 화재진압으로 권하지 않는다 (%s)" % after)
	sim.events.add(20, "fire_found", {"crew": "구조1", "room": room.display_name()})
	assert_eq(str(sim.next_task(c.id).get("kind", "")), "attack", "그 뒤 화점 발견 보고 → 다시 화재진압")


## 초진 뒤에 받은 층 검색은 2차 검색 — 초진 전에 검색한 방도 다시 본다 (전에는 바로 '검색 완료'로 끝났다)
func test_floor_search_after_knockdown_is_secondary() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var lv: int = sim.building.levels()[0]
	var c := _search_crew(sim)
	_place_inside(sim, c, lv)
	for r in sim.fire.comps:
		if r.level == lv and not sim.fire.is_exposure_comp(r):
			r.searched_tick = 5
	assert_true(sim.tactical._next_floor_room(c, "search_floor", lv) == null, "초진 전: 검색한 방은 건너뛴다")
	sim.phases.knockdown_tick = 10
	sim.tactical._search_since[c.id] = 20
	assert_true(sim.tactical._next_floor_room(c, "search_floor", lv) != null, "초진 뒤 받은 검색: 다시 본다 (2차 검색)")
	assert_true(str(sim.next_task(c.id).get("text", "")).contains("2차 검색"), "다음 임무 글도 2차 검색")
	sim.tactical._search_since[c.id] = 0
	assert_true(sim.tactical._next_floor_room(c, "search_floor", lv) == null, "초진 전에 받은 검색은 그대로 이어서 끝낸다")
