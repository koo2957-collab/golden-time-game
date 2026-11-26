extends TestSuite
## 방수 장면을 부드럽게 (2026-11-26 사용자: 방수 중 방향을 바꾸면 대원들이 순간이동하듯 자리가 바뀌고 물줄기가 이상하게 나간다).
## 화면 없이 계산만 본다: 방향 바꾸기의 여유(깜빡임 없음)와 관창보조 자리의 미끄러짐


func _layer(sim: SimWorld) -> Array:
	var sel := SelectionController.new()
	var layer := FloorLayer.new()
	layer.setup(sim, sel, IsoProjection.new())
	layer.level = 1
	return [layer, sel]


func _free(nodes: Array) -> void:
	for n: Node in nodes:
		n.free()


func _at_deg(deg: float) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(deg)) * 5.0


## 방향은 지금 칸(±22.5°)을 여유각(spray_turn_hysteresis_deg) 넘게 벗어나야 바뀐다 — 경계를 오가며 깜빡이지 않는다
func test_spray_direction_hysteresis() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var hyst := float(HoseDraw.style().get("spray_turn_hysteresis_deg", 10.0))
	assert_true(hyst > 0.0 and hyst < 22.5, "여유각 %.0f°" % hyst)
	var o := Vector2.ZERO
	assert_eq(layer._spray_k(7, o, _at_deg(0.0)), 0, "처음 = 겨눈 쪽")
	assert_eq(layer._spray_k(7, o, _at_deg(22.5 + hyst * 0.5)), 0, "경계를 조금 넘어도 그대로")
	assert_eq(layer._spray_k(7, o, _at_deg(22.5 + hyst + 3.0)), 1, "여유각을 넘으면 바뀐다")
	assert_eq(layer._spray_k(7, o, _at_deg(22.5 - hyst * 0.5)), 1, "되돌아와도 경계 근처에서는 그대로")
	assert_eq(layer._spray_k(7, o, _at_deg(5.0)), 0, "충분히 돌아오면 바뀐다")
	assert_eq(layer._spray_k(8, o, _at_deg(90.0)), 2, "조마다 따로 기억")
	_free(nodes)


## 관창보조 자리는 새 자리로 걸어서 옮겨 간다 (순간이동 없음). 멀리 떨어진 새 자리는 바로 선다
func test_helper_spots_glide() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var a := Vector2(10.0, 10.0)
	var first := {"spots": {5: a}}
	layer._glide_spots(first)
	assert_eq(first.spots[5], a, "처음은 그 자리")
	var near := a + Vector2(1.0, 0.0)
	var next := {"spots": {5: near}}
	layer._glide_spots(next)
	var step: Vector2 = next.spots[5]
	assert_true(step.distance_to(a) < 0.5, "새 자리로 한 번에 옮기지 않는다 (%.2f칸 움직임)" % step.distance_to(a))
	var snap_cells := float(HoseDraw.style().get("spray_regroup_snap_m", 3.0)) / sim.units.cell_size_m
	var far := a + Vector2(snap_cells + 2.0, 0.0)
	var jump := {"spots": {5: far}}
	layer._glide_spots(jump)
	assert_eq(jump.spots[5], far, "멀리 떨어진 새 자리(다른 곳 방수)는 바로 선다")
	_free(nodes)


## 호스 끼고 걷기 (2026-11-26 사용자: 깔고 가다 방향을 바꾸면 이랬다저랬다 순간이동): 대각선 계단 모양 길(칸마다 동·남 번갈아)을
## 따라 걸어도 1번 방향이 칸마다 바뀌지 않고, 2번은 깔린 호스 길 위에 선다
func test_hose_carry_direction_steady_on_zigzag() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var art := SpriteArt.get_set(str(SpriteArt.config().get("crew", "")))
	var crew := sim.units.get_crew(0)
	var ws := crew.workers()
	assert_true(art != null and ws.size() >= 2, "그림 묶음 · 일하는 조원 2명 이상")
	var hose := HoseLine.new()
	hose.id = 902
	hose.vehicle_id = sim.units.vehicles[0].id
	hose.crew_id = crew.id
	sim.water.hoses.append(hose)
	var pts: Array[Vector3i] = []
	var at := Vector2i(30, 30)
	for i in 20:
		pts.append(Vector3i(at.x, at.y, 1))
		at += Vector2i(1, 0) if i % 2 == 0 else Vector2i(0, 1)
	for ff in crew.members():
		ff.aboard = false
		ff.level = 1
		ff.prev_level = 1
		ff.crouched = false
	var ks: Array[int] = []
	for n in range(8, pts.size()):
		hose.points = pts.slice(0, n + 1)
		var p := Vector2(pts[n].x + 0.5, pts[n].y + 0.5)
		crew.leader.prev_pos = Vector2(pts[n - 1].x + 0.5, pts[n - 1].y + 0.5)
		crew.leader.pos = p
		var lay := layer._hose_carry_layout(crew, art)
		assert_true(not lay.is_empty(), "호스 끼고 걷기 배치 (%d칸째)" % n)
		if lay.is_empty():
			break
		ks.append(int(lay.k))
		if lay.spots.has(ws[1].id):
			var s2: Vector2 = lay.spots[ws[1].id]
			var near := INF
			for q in hose.points:
				near = minf(near, s2.distance_to(Vector2(q.x + 0.5, q.y + 0.5)))
			assert_true(near < 0.75, "2번은 깔린 호스 길 위 (%.2f칸 떨어짐)" % near)
	var changes := 0
	for i in range(1, ks.size()):
		if ks[i] != ks[i - 1]:
			changes += 1
	assert_true(changes <= 1, "대각선 길에서 방향이 칸마다 바뀌지 않는다 (%s)" % str(ks))
	_free(nodes)


## 펌프 조작 (2026-11-26, SOP 206-1.1): 펌프차 호스가 충수되면 운전원이 차 후면 조작반 곁에 서서 건물 쪽을 본다. 물을 안 보내면 없다
func test_pump_operator_stands_at_rear_while_pumping() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var pump: Vehicle = null
	for v in sim.units.vehicles:
		if pump == null and v.is_pump():
			pump = v
	pump.away = false
	assert_true(layer._driver_layout(pump).is_empty(), "물을 보내지 않으면 운전원은 차 안")
	var hose := HoseLine.new()
	hose.id = 903
	hose.vehicle_id = pump.id
	hose.crew_id = 0
	hose.charged = true
	hose.points = [Vector3i(1, 1, 1), Vector3i(2, 1, 1)] as Array[Vector3i]
	sim.water.hoses.append(hose)
	var dl := layer._driver_layout(pump)
	assert_true(dl.has("driver"), "충수된 호스가 있으면 운전원이 내려 있다")
	if dl.has("driver"):
		var at: Vector2 = dl.driver.pos
		assert_true(at.distance_to(pump.rear_point()) < 2.0, "차 후면 곁 (%s, 후면 %s)" % [at, pump.rear_point()])
		assert_true(not pump.contains(at), "차 몸통 밖")
	_free(nodes)
