extends TestSuite
## 롤오버는 천장을 직접 본 사람만 안다 (2026-11-25 사용자 지적: 밖에서 현관문을 여는 조가 옆 거실 창 너머로 롤오버를 보고했다).
## - 닫힌 유리창 너머는 '유리 너머' — 보이기는 하지만(화염·연기) 직접 본 것으로 치지 않는다 (요구조자 발견·롤오버)
## - 문이 열려 그 방 안을 직접 본 조가 무전하고 카드를 받는다 (가장 가까운 조가 아니라)
## - 지휘관만 봤으면 무전·카드 없이 상황판에 바로
## - 닫힌 문 칸 위에 서도 문 너머 방 안을 '손으로 안다'고 하지 않는다

const SCENARIO := "res://data/scenarios/sop214_1_day_living.json"


## 1층 거실 현관문(바깥으로 난 문)과 그 바깥 칸
func _front(sim: SimWorld) -> Array:
	for o in sim.fire.openings:
		if o.kind != Opening.Kind.DOOR or o.room_b != Opening.OUTSIDE:
			continue
		var room := sim.fire.comps[o.room_a]
		if not room.display_name().contains("거실") or room.display_name().contains("옆집"):
			continue
		var dc := o.cells[0]
		for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var p := dc + n
			if sim.building.cell(o.level, p.x, p.y) in BuildingData.OUTDOOR:
				return [o, room, p]
	return []


## 조 하나만 현관 앞(바깥)에 세우고 나머지는 차에 태운다
func _setup() -> Array:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var f := _front(sim)
	var o: Opening = f[0]
	o.is_open = false
	var crew := sim.units.crews[0]
	for c in sim.units.crews:
		for ff in c.members():
			ff.aboard = c != crew
			ff.level = o.level
			ff.pos = Vector2(f[2]) + Vector2(0.5, 0.5)
			ff.prev_pos = ff.pos
			ff.path.clear()
	return [sim, o, f[1], crew]


## 그 방의 칸들
func _cells(sim: SimWorld, room: Compartment) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(room.rect.position.y, room.rect.end.y):
		for x in range(room.rect.position.x, room.rect.end.x):
			if sim.fire.compartment_at(room.level, x, y) == room:
				out.append(Vector2i(x, y))
	return out


func _heat(room: Compartment) -> void:
	room.flashed = false
	room.t_upper = room.flashover_temp - 50.0
	room.layer_depth = 1.0


func test_glass_is_not_direct_sight() -> void:
	var s := _setup()
	var sim: SimWorld = s[0]
	var room: Compartment = s[2]
	# 창 들여다보기는 몇 번에 한 번 계산한다 (window_view_every)
	for k in 4:
		sim.perception.update(sim.clock.tick + k)
	var glass := 0
	var direct := 0
	for cell in _cells(sim, room):
		glass += 1 if sim.perception.is_visible(room.level, cell.x, cell.y) else 0
		direct += 1 if sim.perception.is_crew_visible(room.level, cell.x, cell.y) else 0
	assert_true(glass > 0, "닫힌 창 너머로 거실이 보이기는 한다 (%d칸 · %s · 문 %d · 조장 %s · 칸 %d)" % [glass, room.display_name(), (s[1] as Opening).index, (s[3] as Crew).leader.pos, _cells(sim, room).size()])
	assert_eq(direct, 0, "닫힌 창 너머는 대원이 직접 본 칸이 아니다")
	assert_eq(sim.perception.clear_seer(room), -1, "거실 안을 직접 본 사람이 없다")


func test_no_rollover_report_through_closed_door() -> void:
	var s := _setup()
	var sim: SimWorld = s[0]
	var room: Compartment = s[2]
	_heat(room)
	sim.perception.update(sim.clock.tick)
	sim.hazards._update_rollover(room, sim.clock.tick)
	assert_eq(sim.events.of_type("rollover_sign").size(), 0, "문이 닫혀 있으면 밖의 조는 롤오버를 보고하지 않는다")
	assert_eq(sim.perception.rollover_visible(room), false, "화면에도 롤오버를 그리지 않는다")


func test_crew_that_sees_reports() -> void:
	var s := _setup()
	var sim: SimWorld = s[0]
	var o: Opening = s[1]
	var room: Compartment = s[2]
	var crew: Crew = s[3]
	_heat(room)
	sim.perception.update(sim.clock.tick)
	sim.hazards._update_rollover(room, sim.clock.tick)
	# 문을 연다 → 그 조가 천장을 본다
	o.is_open = true
	sim.perception.update(sim.clock.tick + 1)
	sim.hazards._update_rollover(room, sim.clock.tick + 1)
	var said := sim.events.of_type("rollover_sign")
	assert_eq(said.size(), 1, "문을 열자 한 번 보고")
	if not said.is_empty():
		assert_eq(int(said[0].get("crew_id", -1)), crew.id, "본 조가 보고한다")
		assert_eq(str(said[0].get("crew", "")), sim.units.crew_name(crew), "무전 이름도 그 조")
	# 이미 알린 롤오버는 다시 알리지 않는다
	sim.perception.update(sim.clock.tick + 2)
	sim.hazards._update_rollover(room, sim.clock.tick + 2)
	assert_eq(sim.events.of_type("rollover_sign").size(), 1, "같은 롤오버는 한 번만")


func test_commander_only_goes_to_board() -> void:
	var s := _setup()
	var sim: SimWorld = s[0]
	var room: Compartment = s[2]
	var e := {"type": "rollover_sign", "tick": 0, "room": room.display_name(), "crew": "지휘관", "seen_by_commander": true}
	var radio := sim.command.radio
	var before := radio.queue.size() + radio.history.size() + (1 if radio.current else 0)
	sim.command._report(e, 0)
	assert_eq(radio.queue.size() + radio.history.size() + (1 if radio.current else 0), before, "무전으로 보내지 않는다")
	assert_true(sim.knowledge.hazards.any(func(h: Dictionary) -> bool: return str(h.get("kind", "")) == "롤오버"), "상황판에 롤오버가 오른다")
	assert_eq(sim.cards._trigger_of(e), "", "카드도 없다")


func test_touch_does_not_pass_closed_door() -> void:
	var s := _setup()
	var sim: SimWorld = s[0]
	var o: Opening = s[1]
	var room: Compartment = s[2]
	var crew: Crew = s[3]
	# 문 칸 위에 선다 (문은 닫힘)
	for ff in crew.members():
		ff.pos = Vector2(o.cells[0]) + Vector2(0.5, 0.5)
		ff.prev_pos = ff.pos
	sim.perception.update(sim.clock.tick)
	var touched := 0
	for cell in _cells(sim, room):
		touched += 1 if sim.perception.is_crew_visible(room.level, cell.x, cell.y) else 0
	assert_eq(touched, 0, "닫힌 문 너머 방 안은 만져서 알지 못한다")
