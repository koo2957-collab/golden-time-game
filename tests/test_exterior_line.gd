extends TestSuite
## 경계 관창 (2026-11-24 사용자 결정): 관창을 배치해 두고(잠근 채 겨눔) 겨눈 곳이 달궈지거나 불꽃이 나오면 열고,
## 식으면 잠그고 보고한 뒤 계속 지킨다. 바깥 지상에서 위층 창·외벽도 겨눈다 (건물 안으로 들어가지 않는다). 유리는 깨지 않는다.
## 전에는: 불꽃을 못 본 방수는 끝없이 쏴 탱크를 비웠고(275초), 위층 창을 찍으면 물이 닿지 않는데 '방수 중'으로 남거나
## 건물 안으로 들어가 안쪽에서 쐈다.


func _crew(sim: SimWorld) -> Crew:
	var c := sim.units.get_crew(0)
	var k := 0
	for ff in c.members():
		ff.path.clear()
		ff.aboard = false
		ff.level = 1
		ff.prev_level = 1
		ff.pos = Vector2(13.5 + k, 23.5)
		ff.prev_pos = ff.pos
		k += 1
	return c


## 호스를 꺼내고 자리를 잡을 때까지 돌린다
func _settle(sim: SimWorld, c: Crew) -> HoseLine:
	sim.step_ticks(1)
	fetch_hose(sim, c.id, false)
	for i in 1200:
		if not c.leader.is_moving():
			break
		sim.step_ticks(1)
	sim.step_ticks(15)
	return sim.water.hose_of_crew(c.id)


func _outside_window(sim: SimWorld, level: int) -> Opening:
	for o in sim.fire.openings:
		if o.level == level and o.kind == Opening.Kind.WINDOW and o.room_b == Opening.OUTSIDE and not sim.fire.is_exposure_comp(sim.fire.comps[o.room_a]):
			return o
	return null


func test_settings_have_source() -> void:
	var m: Dictionary = JsonData.load_file("res://data/command/mission_params.json")
	for key in ["exterior_done_s", "exterior_open_ratio", "exterior_close_ratio"]:
		assert_true(m.has(key) and str(m[key].get("source", "")) != "", "%s 값과 source" % key)
	assert_true(float(m.exterior_close_ratio.value) < float(m.exterior_open_ratio.value), "잠그는 기준이 여는 기준보다 낮다 (떨림 방지)")
	var f: Dictionary = JsonData.load_file("res://data/fire/fire_params.json")
	assert_true(f.has("exterior_floor_height_m") and str(f.exterior_floor_height_m.get("source", "")) != "", "층 높이 값과 source")


## 지상에서 위층 창을 겨눈다: 조는 건물 밖 지상에 서고, 그 창에 직사가 닿는 자리(수평 + 높이 ≤ 사거리)를 잡는다
func test_upper_floor_window_from_ground() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var c := _crew(sim)
	var win := _outside_window(sim, 2)
	assert_true(win != null, "2층 바깥 창")
	if win == null:
		return
	var cell := win.cells[0]
	sim.issue(TacticalCommand.make("exterior", [c.id] as Array[int], Vector3i(cell.x, cell.y, 2)))
	var h := _settle(sim, c)
	assert_true(h != null and h.exterior and h.target.z == 2, "경계 관창 — 2층 창을 겨눈다")
	assert_true(c.leader.level == 1 and sim.building.cell(1, floori(c.leader.pos.x), floori(c.leader.pos.y)) in BuildingData.OUTDOOR, "조는 건물 밖 지상에 선다 (%s)" % c.leader.pos)
	assert_true(sim.water.exterior_reach(c.leader.pos, 1, h.target), "그 자리에서 창에 닿는다")
	assert_true(h.standby and not h.flowing, "불꽃·가열이 없으면 잠근 채 겨눈다")
	assert_true(not win.broken, "유리는 깨지 않는다")
	# 너무 멀거나 건물 안에서는 닿지 않는다
	assert_true(not sim.water.exterior_reach(Vector2(cell) + Vector2(40.0, 0.5), 1, h.target), "사거리 밖")
	assert_true(not sim.water.exterior_reach(Vector2(14.5, 16.5), 1, h.target), "건물 안에서는 올려 쏘지 않는다")
	# 창이 깨져 불꽃이 나오면 연다 — 물이 창 안쪽에 닿는다
	win.broken = true
	win.is_open = true
	var inside := Vector3i(cell.x, cell.y, 2)
	for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if sim.fire.compartment_at(2, cell.x + d.x, cell.y + d.y) != null:
			inside = Vector3i(cell.x + d.x, cell.y + d.y, 2)
	sim.fire.ignite(inside)
	var before: float = sim.fire.grid.wet[sim.fire.grid.index(2, inside.x, inside.y)]
	var opened := false
	for i in 300:
		sim.step_ticks(1)
		if h.flowing and h.spraying:
			opened = true
			break
	assert_true(opened, "창에서 불꽃이 보이면 관창을 연다")
	sim.step_ticks(30)
	assert_true(sim.fire.grid.wet[sim.fire.grid.index(2, inside.x, inside.y)] > before, "물이 깨진 창 안쪽에 닿는다")
	assert_true(c.leader.level == 1, "그래도 건물 안으로 들어가지 않는다")


## 달궈지면 열고, 식으면 잠그고 보고한 뒤 계속 지킨다 — 잠가 둔 동안은 물을 쓰지 않는다
func test_opens_when_heated_and_closes_when_cool() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var c := _crew(sim)
	assert_true(not sim.exposure.pairs.is_empty(), "인접 건물 창 (연소확대 대상)")
	if sim.exposure.pairs.is_empty():
		return
	var win: Opening = sim.exposure.pairs[0].target
	var cell := win.cells[0]
	sim.issue(TacticalCommand.make("exterior", [c.id] as Array[int], Vector3i(cell.x, cell.y, win.level)))
	var h := _settle(sim, c)
	assert_true(h != null and h.standby and not h.flowing, "배치: 잠근 채 겨눈다")
	var tank := sim.units.get_vehicle(h.vehicle_id).tank_l
	sim.step_ticks(300)
	assert_true(absf(sim.units.get_vehicle(h.vehicle_id).tank_l - tank) < 0.01, "잠가 둔 동안 물을 쓰지 않는다")
	# 창이 달궈진다 (착화 기준의 절반)
	sim.exposure.dose[win.index] = sim.exposure._ignite * 0.5
	var opened := false
	for i in 50:
		sim.step_ticks(1)
		if h.flowing:
			opened = true
			break
	assert_true(opened, "달궈지면 관창을 연다")
	assert_true(sim.events.of_type("exterior_post").any(func(e: Dictionary) -> bool: return str(e.text).contains("개방") and str(e.text).contains("가열")), "개방 보고")
	# 다 식혔다 (실제로는 경계 관창이 가열량을 깎는다 — 여기서는 바로 0으로)
	sim.step_ticks(20)
	assert_true(h.spraying and not win.broken, "유리를 깨지 않고 겉을 적신다")
	sim.exposure.dose[win.index] = 0.0
	var closed := false
	for i in 400:
		sim.step_ticks(1)
		if h.standby and not h.flowing:
			closed = true
			break
	assert_true(closed, "식으면 관창을 잠근다")
	assert_true(sim.events.of_type("exterior_post").any(func(e: Dictionary) -> bool: return str(e.text).contains("잠금")), "잠금 보고")
	assert_true(sim.tactical._exterior.has(c.id) and sim.events.of_type("tactical_done").is_empty(), "임무는 끝나지 않는다 — 계속 지킨다")
	# 다시 달궈지면 다시 연다 (보고는 처음 한 번씩만 — 되풀이는 기록만)
	var posts := sim.events.of_type("exterior_post").size()
	sim.exposure.dose[win.index] = sim.exposure._ignite * 0.5
	var again := false
	for i in 50:
		sim.step_ticks(1)
		if h.flowing:
			again = true
			break
	assert_true(again, "다시 달궈지면 다시 연다")
	assert_eq(sim.events.of_type("exterior_post").size(), posts, "되풀이 개방은 무전으로 알리지 않는다")
	assert_true(not sim.events.of_type("exterior_cycle").is_empty(), "기록에는 남는다")


## 경계 관창이 실제로 물을 뿌릴 때만 그 창을 지킨 것으로 친다 (잠가 둔 동안은 달궈진다)
func test_only_spraying_protects() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	if sim.exposure.pairs.is_empty():
		assert_true(false, "인접 건물 창")
		return
	var p: ExposureSystem.Pair = sim.exposure.pairs[0]
	var h := HoseLine.new()
	var cell := p.target.cells[0]
	h.target = Vector3i(cell.x, cell.y, p.target.level)
	h.flowing = true
	sim.water.hoses.append(h)
	assert_true(not sim.exposure._protected(p), "방수 지시만으로는 지킨 것이 아니다")
	h.spraying = true
	assert_true(sim.exposure._protected(p), "물이 나가면 지킨다")
	sim.water.hoses.clear()
