extends TestSuite
## 물줄기는 관창보다 높은 가구·차체에서 멈춘다 (2026-11-24 사용자: "화염이 가구에 있다면 가구에서 물줄기가 멈춰야 하는데
## 물리 엔진이 잘 작동되는지 의문"). 전에는 가구·차량을 그대로 통과했다 (같은 방 가구 횡단 16줄 중 멈춘 것 0줄).
## 높이는 data/fire/fire_params.json furniture_height_m (장롱 2.1 · 침대 0.45 …), 관창 높이 nozzle_height_m(1.0)·낮은 자세 0.7.
## 방1(25~31, 15~19): 침대 26~29 × 16~18, 장롱 x=20 (y 15~18)

const S := HoseLine.Pattern.STRAIGHT


func _force(sim: SimWorld, pos: Vector2, target: Vector3i) -> HoseLine:
	var crew := sim.units.get_crew(0)
	crew.leader.pos = pos
	crew.leader.prev_pos = pos
	crew.partner.pos = pos + Vector2(0, 1)
	crew.partner.prev_pos = crew.partner.pos
	sim.water.ensure_hose(0, 1, sim.clock.tick)
	var h := fetch_hose(sim, 0)
	crew.leader.pos = pos
	crew.leader.prev_pos = pos
	crew.leader.path.clear()
	h.pattern = S
	h.target = target
	h.aim = Vector2(target.x + 0.5, target.y + 0.5)
	h.flowing = true
	h.approaching = false
	h.next_advance_tick = 1 << 30
	h.charged = true
	h.ready_tick = sim.clock.tick
	return h


func _wet(sim: SimWorld, cells: Array) -> float:
	var total := 0.0
	for c: Vector2i in cells:
		total += sim.fire.grid.wet[sim.fire.grid.index(1, c.x, c.y)]
	return total


func test_height_table_has_source() -> void:
	var data: Variant = JsonData.load_file("res://data/fire/fire_params.json")
	for key in ["nozzle_height_m", "nozzle_height_low_m", "furniture_height_m", "vehicle_blocks_water"]:
		assert_true(data.has(key) and str(data[key].get("source", "")) != "", "%s 값과 source" % key)
	var h: Dictionary = data.furniture_height_m.value
	assert_true(float(h["장롱"]) > float(data.nozzle_height_m.value) and float(h["침대"]) < float(data.nozzle_height_low_m.value), "장롱은 관창보다 높고 침대는 낮은 자세 관창보다도 낮다")


## 장롱(관창보다 높다)을 사이에 두고 그 뒤를 겨누면 물은 장롱 겉에서 멈춘다 — 타는 장롱이면 장롱에 물이 간다
func test_tall_furniture_stops_stream() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	# 방1 문(24, 14)을 지나 방 안에 선 관창수가 장롱(x 20) 너머 서쪽 벽 쪽을 겨눈다 — 같은 줄(y 17)
	var ward := sim.building.furniture(1).filter(func(f: Dictionary) -> bool: return str(f.name) == "장롱")
	assert_true(not ward.is_empty(), "1층에 장롱이 있다")
	if ward.is_empty():
		return
	var r: Rect2i = ward[0].rect
	var row := r.position.y + r.size.y / 2
	var behind := Vector3i(r.position.x - 2, row, 1)
	var start := Vector2(r.end.x + 4.5, row + 0.5)
	if not sim.pathfinder.passable(1, floori(start.x), floori(start.y)) or sim.fire.compartment_at(1, behind.x, behind.y) == null:
		# 이 집 배치에서 장롱 앞뒤가 방이 아니면 다른 줄을 쓴다
		start = Vector2(r.end.x + 2.5, row + 0.5)
	var h := _force(sim, start, behind)
	sim.step_ticks(30)
	assert_true(h.spraying, "물이 나간다")
	assert_true(Vector2i(h.impact.floor()).x >= r.position.x and Vector2i(h.impact.floor()).x < r.end.x, "물은 장롱 칸에서 멈춘다 (impact %s, 장롱 x %d~%d)" % [h.impact, r.position.x, r.end.x - 1])
	assert_true(h.blocked, "장롱 너머는 막힘")
	var ward_cells: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			ward_cells.append(Vector2i(x, y))
	assert_true(_wet(sim, ward_cells) > 1.0, "장롱 겉이 젖는다 (%.1fL)" % _wet(sim, ward_cells))
	# 장롱을 직접 겨누면 막힌 것이 아니다 (타는 장롱에 물이 닿는다)
	h.target = Vector3i(r.position.x, row, 1)
	h.aim = Vector2(r.position.x + 0.5, row + 0.5)
	sim.step_ticks(10)
	assert_true(not h.blocked, "장롱 자체를 겨누면 닿는다")


## 침대(관창보다 낮다)는 넘어간다 — 그 너머를 겨누면 거기에 닿는다
func test_low_furniture_does_not_stop_stream() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	var beds := sim.building.furniture(1).filter(func(f: Dictionary) -> bool: return str(f.name) == "침대" and (f.rect as Rect2i).has_point(Vector2i(27, 17)))
	assert_true(not beds.is_empty(), "방1에 침대가 있다")
	if beds.is_empty():
		return
	var r: Rect2i = beds[0].rect
	var row := r.position.y + r.size.y / 2
	# 침대 동쪽에서 침대 너머 서쪽(침대 바로 옆 바닥)을 겨눈다
	var start := Vector2(r.end.x + 0.5, row + 0.5)
	var beyond := Vector3i(r.position.x - 1, row, 1)
	assert_true(sim.pathfinder.passable(1, floori(start.x), floori(start.y)), "침대 옆에 설 자리")
	var h := _force(sim, start, beyond)
	sim.step_ticks(30)
	assert_true(not h.blocked and Vector2i(h.impact.floor()) == Vector2i(beyond.x, beyond.y), "침대는 넘어간다 (impact %s)" % h.impact)
	# 낮은 자세(관창 0.7m)여도 침대(0.45m)는 넘어간다
	sim.units.get_crew(0).leader.crouched = true
	sim.step_ticks(10)
	assert_true(not h.blocked, "낮은 자세에서도 침대는 넘어간다")


## 바깥에 선 소방차 차체는 물줄기를 막는다
func test_vehicle_body_stops_stream() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var v := sim.units.get_vehicle(0)
	var fp := v.footprint()
	var center := v.pos
	# 차를 사이에 두고 맞은편에 서서 차 너머를 겨눈다 (차의 옆 방향으로)
	var side := (fp[3] - fp[0]).normalized()
	var width := fp[0].distance_to(fp[3])
	var start := center - side * (width * 0.5 + 2.0)
	var beyond := center + side * (width * 0.5 + 2.0)
	if not sim.pathfinder.passable(1, floori(start.x), floori(start.y)):
		var t := start
		start = beyond
		beyond = t
	var h := _force(sim, start, Vector3i(floori(beyond.x), floori(beyond.y), 1))
	sim.step_ticks(20)
	assert_true(h.blocked and Geometry2D.is_point_in_polygon(h.impact, fp), "차체에서 멈춘다 (impact %s)" % h.impact)
