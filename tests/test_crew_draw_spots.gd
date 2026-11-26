extends TestSuite
## 대원을 그리는 자리 (FloorLayer._shown_pos, 2026-11-24): 자세(_unit_pose)와 같은 배치에서 나와야 하고,
## 연기에 묻힌 대원의 테두리(_draw_smoke_outlines)도 몸을 그리는 그 자리에 그려야 한다.
## 사용자 보고: "문을 개방하고 있을 때 한 명이 방수태세를 하고 있으면 다른 대원들의 모습이 사라진다 ·
## 화재진압할 때도 대원들이 사라지는데 선택 원은 그대로 있다." 화면 없이 자리·자세 계산만 본다.

const SCENARIO := "res://data/scenarios/dev_squad_house_fire.json"
const FRONT_DOOR := Vector3i(13, 20, 1)


## 화면 없이 쓰는 층 그림 노드 [층 그림, 선택] — 끝나면 _free 로 지운다
func _layer(sim: SimWorld) -> Array:
	var sel := SelectionController.new()
	var layer := FloorLayer.new()
	layer.setup(sim, sel, IsoProjection.new())
	layer.level = FRONT_DOOR.z
	return [layer, sel]


func _free(nodes: Array) -> void:
	for n: Node in nodes:
		n.free()


## 호스(물이 차기 전)를 가진 진압 분대가 현관문 앞에서 문 작업을 하는 상태. locked = 잠긴 문 파괴, 아니면 확인 후 개방.
## → [sim, 조, 문]
func _crew_at_door(locked: bool) -> Array:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var crew := sim.units.get_crew(0)
	var door := sim.fire.opening_at(FRONT_DOOR)
	door.locked = locked
	door.is_open = false
	sim.doors.sync_blocking()
	sim.water.lay_hose(crew.id, sim.water._nearest_pump(crew.leader.pos), sim.clock.tick)
	var h := fetch_hose(sim, crew.id, false)
	if h != null:
		# 문 작업을 하는 동안 호스에 물이 차지 않게 (끼고 걷기 배치가 살아 있는 동안을 본다)
		h.ready_tick = 1 << 30
	sim.doors.request(crew.id, FRONT_DOOR, true, sim.clock.tick)
	for i in 4000:
		var t := sim.doors.task_of_crew(crew.id)
		if t != null and t.open and not t.waiting_people and t.progress > 0.3 and not crew.leader.is_moving():
			break
		sim.step_ticks(1)
		sim.cards.queue.clear()
	return [sim, crew, door]


## 잠긴 문 파괴 (A1) + 문 앞 방수태세 (E4): 문을 부수는 두 조원은 문틈 옆에, 관창수는 방수태세 자리에 그린다.
## 전에는 호스 끼고 걷기 배치가 먼저 걸려, 부수는 자세를 한 채 호스 길 위(문에서 몇 칸 뒤 — 펌프차 쪽)에 그려졌다
func test_door_forcers_drawn_at_door_with_hose() -> void:
	var s := _crew_at_door(true)
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var door: Opening = s[2]
	var h := sim.water.hose_of_crew(crew.id)
	var dt := sim.doors.task_of_crew(crew.id)
	assert_true(crew.workers().size() >= 3, "일하는 조원 3명 분대")
	assert_true(h != null and not h.charged and h.fetch_until < 0, "꺼낸 호스에 아직 물이 차지 않았다")
	assert_true(dt != null and door.locked, "잠긴 문을 부수는 중")
	if h == null or dt == null:
		return
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var art := SpriteArt.crew_set(sim.units.squads[crew.squad_id].type)
	assert_true(not layer._hose_carry_layout(crew, art).is_empty(), "호스 끼고 걷기 배치가 살아 있는 상태 (이것보다 문 작업이 먼저여야 한다)")
	var center := FloorLayer.door_center(door)
	var lay := layer._force_layout(dt, crew, art)
	var forcers := 0
	for ff in crew.members():
		var pose := layer._unit_pose(ff, crew, art)
		var at := layer._shown_pos(ff, 0.0)
		if str(pose[0]) in ["force_a", "force_b"]:
			forcers += 1
			assert_true(at.is_equal_approx(lay.spots[ff.id]), "%s 자세의 조원은 문틈 옆 자리에 (그린 자리 %s · 문틈 옆 %s)" % [pose[0], at, lay.spots[ff.id]])
			assert_true(at.distance_to(center) < 2.5, "문 앞에 있다 (문에서 %.1f칸)" % at.distance_to(center))
	assert_eq(forcers, 2, "두 조원이 문을 부순다")
	var ready := layer._door_ready_layout(crew, art)
	assert_true(not ready.is_empty(), "관창수는 문 앞 방수태세")
	if not ready.is_empty():
		assert_eq(str(layer._unit_pose(crew.leader, crew, art)[0]), "spray_ln", "방수태세 자세")
		assert_true(layer._shown_pos(crew.leader, 0.0).is_equal_approx(ready.spot), "방수태세 자리에 그린다")
	_free(nodes)


## 문 확인 후 개방 (B1) + 문 앞 방수태세: 문을 여는 조원은 문 옆 자리에 그린다 (호스 길 위 자리가 아니라)
func test_door_opener_drawn_at_door_with_hose() -> void:
	var s := _crew_at_door(false)
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var door: Opening = s[2]
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var art := SpriteArt.crew_set(sim.units.squads[crew.squad_id].type)
	var dl := layer._door_check_layout(crew, art)
	assert_true(not dl.is_empty(), "문을 여는 중")
	if not dl.is_empty():
		var opener: Firefighter = null
		for ff in crew.members():
			if ff.id == int(dl.opener):
				opener = ff
		assert_true(opener != null and opener != crew.leader, "문은 관창수가 아닌 조원이 연다")
		if opener != null:
			assert_eq(str(layer._unit_pose(opener, crew, art)[0]), "door_open", "문 여는 자세")
			var at := layer._shown_pos(opener, 0.0)
			assert_true(at.is_equal_approx(dl.spot), "문 여는 조원은 문 옆 자리에 (그린 자리 %s · 문 옆 %s)" % [at, dl.spot])
			assert_true(at.distance_to(FloorLayer.door_center(door)) < 2.5, "문 앞에 있다")
	_free(nodes)


## 연기에 묻힌 대원 테두리는 몸을 그리는 자리에 그린다 — 문 앞 방수태세처럼 배치 자리가 실제 자리와 다를 때도.
## 전에는 실제 자리로 판정하고 그려서, 몸은 연기에 묻혀 안 보이고 테두리는 딴 곳에 뜨거나 아예 없었다 (선택 원만 남았다)
func test_smoke_outline_at_drawn_position() -> void:
	var s := _crew_at_door(false)
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var lead := crew.leader
	var drawn := layer._shown_pos(lead, 0.0)
	assert_true(drawn.distance_to(lead.pos) > 0.5, "방수태세 자리는 실제 자리와 다르다 (%.1f칸)" % drawn.distance_to(lead.pos))
	# 그린 자리의 몸(가슴 높이)만 덮는 작은 연기 윤곽: 실제 자리는 그 밖이다
	var c := layer.proj.to_screen(drawn, 1.0)
	var around_drawn: Array[PackedVector2Array] = [PackedVector2Array([c + Vector2(-6, -6), c + Vector2(6, -6), c + Vector2(6, 6), c + Vector2(-6, 6)])]
	assert_true(not layer._in_hulls(layer.proj.to_screen(lead.pos, 1.0), around_drawn), "실제 자리는 이 연기 밖")
	var found := false
	for it: Array in layer._outline_crew(false, {}, around_drawn, 0.0):
		if it[0] == lead:
			found = true
			assert_true((it[2] as Vector2).is_equal_approx(drawn), "테두리 자리 = 몸을 그리는 자리 (%s · %s)" % [it[2], drawn])
	assert_true(found, "그린 자리가 연기에 덮이면 테두리를 그린다")
	# 반대로 실제 자리만 덮는 연기: 몸은 거기 없으니 테두리도 없다
	var p := layer.proj.to_screen(lead.pos, 1.0)
	var around_sim: Array[PackedVector2Array] = [PackedVector2Array([p + Vector2(-6, -6), p + Vector2(6, -6), p + Vector2(6, 6), p + Vector2(-6, 6)])]
	for it: Array in layer._outline_crew(false, {}, around_sim, 0.0):
		assert_true(it[0] != lead, "몸이 없는 실제 자리에는 테두리를 그리지 않는다")
	# 연기 윤곽이 없으면(다른 층 사람 테두리) 그 층 사람 모두, 그리는 자리로
	var all := layer._outline_crew(false, {}, [] as Array[PackedVector2Array], 0.0)
	var mine := 0
	for it: Array in all:
		if it[1] == crew:
			mine += 1
			assert_true((it[2] as Vector2).is_equal_approx(layer._shown_pos(it[0], 0.0)), "테두리 자리 = 그리는 자리")
	assert_eq(mine, crew.members().size(), "조원 모두")
	_free(nodes)


## 방수 줄 (2026-11-26 사용자 결정 — 2026-11-24 의 '꺾인 곳에서 3번이 호스 정리'를 대신함): 호스가 어느 쪽에서 오든
## 셋 다 관창수 뒤에 한 줄로, 관창수와 같은 쪽을 보고 선다. 3번도 오가지 않고 방수 자세로 있다 (마주 보지 않는다)
func test_spray_line_always_behind_nozzle() -> void:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var crew := sim.units.get_crew(0)
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var art := SpriteArt.get_set(str(SpriteArt.config().get("crew", "")))
	var workers := crew.workers()
	assert_true(art != null and workers.size() >= 3, "그림 묶음 · 일하는 조원 3명")
	if art == null or workers.size() < 3:
		_free(nodes)
		return
	# 사방이 트인 빈 터를 찾는다 (서쪽 14칸 · 남쪽 14칸 · 동쪽 4칸이 모두 걸을 수 있는 곳)
	var b := sim.building
	var at := Vector2i(-1, -1)
	for y in range(4, b.height - 16):
		for x in range(16, b.width - 6):
			var free := true
			for yy in range(y - 3, y + 15):
				for xx in range(x - 15, x + 5):
					free = free and b.is_walkable(1, xx, yy)
					if not free:
						break
				if not free:
					break
			if free:
				at = Vector2i(x, y)
				break
		if at.x >= 0:
			break
	assert_true(at.x >= 0, "빈 터")
	if at.x < 0:
		_free(nodes)
		return
	var hose := HoseLine.new()
	hose.id = 900
	hose.vehicle_id = sim.units.vehicles[0].id
	hose.crew_id = crew.id
	hose.flowing = true
	hose.spraying = true
	hose.charged = true
	hose.water_head = 9999.0
	hose.aim = Vector2(at) + Vector2(8.5, 0.5)
	sim.water.hoses.append(hose)
	for ff in crew.members():
		ff.aboard = false
		ff.level = 1
		ff.prev_level = 1
		ff.pos = Vector2(at) + Vector2(0.5, 0.5)
		ff.prev_pos = ff.pos
		ff.path.clear()
	var cell_m := sim.units.cell_size_m
	var facing := Vector2.RIGHT.rotated(0.0)
	for came_from: String in ["south", "west"]:
		hose.points.clear()
		if came_from == "south":
			for y in range(at.y + 14, at.y - 1, -1):
				hose.points.append(Vector3i(at.x, y, 1))
		else:
			for x in range(at.x - 14, at.x + 1):
				hose.points.append(Vector3i(x, at.y, 1))
		layer._spray_cache.clear()
		layer._facing.clear()
		var sl := layer._spray_layout(crew, art, 0.0)
		assert_eq(int(sl.k), 0, "%s: 관창수는 겨눈 동쪽" % came_from)
		assert_eq(str(sl.anims.get(workers[1].id, "")), "spray_h1", "%s: 2번 방수 자세" % came_from)
		assert_eq(str(sl.anims.get(workers[2].id, "")), "spray_h2", "%s: 3번도 방수 자세 (호스 정리로 오가지 않는다)" % came_from)
		assert_true(not sl.has("walk"), "%s: 아무도 오가지 않는다" % came_from)
		var p0: Vector2 = sl.spots[workers[0].id]
		for i in [1, 2]:
			var p: Vector2 = sl.spots[workers[i].id]
			assert_eq(int(sl.ks.get(workers[i].id, -1)), 0, "%s: %d번은 관창수와 같은 쪽을 본다" % [came_from, i + 1])
			assert_true((p - p0).dot(facing) < -0.3 / cell_m, "%s: %d번은 관창수 뒤에 있다 (%s)" % [came_from, i + 1, p - p0])
	_free(nodes)


## 건물 안 방수는 낮은 자세 (2026-11-26 사용자: 농연 속 내부 방수를 서서 했다)
func test_indoor_spray_kneels() -> void:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var crew := sim.units.get_crew(0)
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var art := SpriteArt.get_set(str(SpriteArt.config().get("crew", "")))
	var room: Compartment = null
	for c in sim.fire.comps:
		if room == null and c.level == 1 and c.cells.size() >= 12 and not sim.fire.is_exposure_comp(c):
			room = c
	var cell: Vector2i = room.cells[room.cells.size() / 2]
	var hose := HoseLine.new()
	hose.id = 901
	hose.vehicle_id = sim.units.vehicles[0].id
	hose.crew_id = crew.id
	hose.flowing = true
	hose.spraying = true
	hose.charged = true
	hose.aim = Vector2(cell) + Vector2(3.5, 0.5)
	hose.points = [Vector3i(cell.x - 4, cell.y, 1), Vector3i(cell.x, cell.y, 1)] as Array[Vector3i]
	sim.water.hoses.append(hose)
	for ff in crew.members():
		ff.aboard = false
		ff.level = 1
		ff.pos = Vector2(cell) + Vector2(0.5, 0.5)
		ff.prev_pos = ff.pos
		ff.path.clear()
		ff.crouched = false
	var sl := layer._spray_layout(crew, art, 0.0)
	assert_eq(str(sl.anims.get(crew.leader.id, "")), "spray_ln", "관창수는 무릎 꿇고 방수 (연기가 낮지 않아도 건물 안)")
	_free(nodes)
