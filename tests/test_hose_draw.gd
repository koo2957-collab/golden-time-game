extends TestSuite
## 소방호스 그리기 (HoseDraw — docs/motions.md '라. 소방호스 표현' D1·D2·D4, 2026-11-18):
## 납작한 띠 / 부푼 관을 물머리에서 나누고, 꺾이는 곳을 둥글리고, 1본마다 결합구를 둔다. 화면 없이 도형 계산만 본다.


func _hose(cells: Array) -> HoseLine:
	var h := HoseLine.new()
	for c: Vector3i in cells:
		h.points.append(c)
	return h


## ㄱ자로 꺾인 호스: 동쪽 10칸 → 남쪽 10칸
func _bent() -> HoseLine:
	var cells: Array = []
	for x in 11:
		cells.append(Vector3i(x, 0, 1))
	for y in range(1, 11):
		cells.append(Vector3i(10, y, 1))
	return _hose(cells)


func test_style_values_have_source() -> void:
	var data: Variant = JsonData.load_file(HoseDraw.PATH)
	assert_true(data is Dictionary, "설정 파일")
	for key: String in data:
		if key == "note":
			continue
		assert_true(data[key] is Dictionary and data[key].has("value") and str(data[key].get("source", "")) != "", "%s 값과 source" % key)
	var st := HoseDraw.style()
	assert_true(float(st.flat_width_m) > float(st.round_width_m), "납작한 호스가 부푼 호스보다 넓다")
	assert_true(absf(float(st.flat_width_m) / float(st.round_width_m) - PI / 2.0) < 0.1, "폭 비율 = π/2 (접힌 폭 = 지름 × π/2)")


func test_corner_is_rounded_and_length_kept() -> void:
	var h := _bent()
	var runs := HoseDraw.runs(h, 1, 1.2, 4)
	assert_eq(runs.size(), 1, "한 층에 한 조각")
	var pts: PackedVector2Array = runs[0].pts
	var dist: PackedFloat32Array = runs[0].dist
	assert_true(not pts.has(Vector2(10.5, 0.5)), "모서리 점은 둥글려 없어진다")
	assert_true(pts.size() <= 8, "일직선 위의 점은 뺀다 (%d개)" % pts.size())
	assert_eq(pts[0], Vector2(0.5, 0.5), "펌프차 쪽 끝")
	assert_eq(pts[pts.size() - 1], Vector2(10.5, 10.5), "관창 쪽 끝")
	assert_true(absf(dist[dist.size() - 1] - h.length_cells()) < 0.001, "거리는 시뮬레이션 길이와 같다")
	for k in range(1, dist.size()):
		assert_true(dist[k] > dist[k - 1], "거리는 늘기만 한다")
	for p in pts:
		assert_true(p.distance_to(Vector2(10.5, 0.5)) > 0.3, "모서리 안쪽으로 돌아간다 (%s)" % p)


func test_other_level_splits_run() -> void:
	var h := _hose([Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(2, 0, 1), Vector3i(2, 0, 2), Vector3i(3, 0, 2), Vector3i(4, 0, 2)])
	var low := HoseDraw.runs(h, 1, 1.2, 4)
	var up := HoseDraw.runs(h, 2, 1.2, 4)
	assert_eq(low.size(), 1, "1층 조각")
	assert_eq(up.size(), 1, "2층 조각")
	assert_true(absf(float(up[0].dist[0]) - 8.0) < 0.001, "2층 조각은 계단 길이(6칸)를 지난 거리에서 시작")
	assert_true(HoseDraw.runs(h, 3, 1.2, 4).is_empty(), "호스가 없는 층")


func test_water_head_splits_flat_and_round() -> void:
	var run: Dictionary = HoseDraw.runs(_bent(), 1, 1.2, 4)[0]
	var wet := HoseDraw.slice(run, -INF, 6.0)
	var dry := HoseDraw.slice(run, 6.0, INF)
	assert_eq(wet[wet.size() - 1], Vector2(6.5, 0.5), "부푼 호스는 물머리까지")
	assert_eq(dry[0], Vector2(6.5, 0.5), "납작한 호스는 물머리부터")
	assert_eq(dry[dry.size() - 1], Vector2(10.5, 10.5), "관창까지")
	assert_true(HoseDraw.slice(run, -INF, 0.0).is_empty(), "송수 전: 부푼 곳 없음")
	assert_true(HoseDraw.slice(run, 20.0, INF).is_empty(), "다 찼으면 납작한 곳 없음")
	assert_eq(HoseDraw.slice(run, -INF, 20.0).size(), run.pts.size(), "다 찼으면 전체가 부푼 호스")


func test_couplings_every_length() -> void:
	var run: Dictionary = HoseDraw.runs(_bent(), 1, 1.2, 4)[0]
	var at := HoseDraw.couplings(run, 8.0)
	assert_eq(Array(at), [0.0, 8.0, 16.0], "0·8·16칸 (관창 쪽 끝 20칸에는 없음)")
	assert_eq(HoseDraw.point_at(run, 8.0), Vector2(8.5, 0.5), "결합구 자리")
	assert_true(HoseDraw.couplings(run, 0.0).is_empty(), "길이를 모르면 그리지 않는다")


## 동쪽으로 곧게 n칸
func _straight(n: int) -> HoseLine:
	var cells: Array = []
	for x in n + 1:
		cells.append(Vector3i(x, 0, 1))
	return _hose(cells)


## D5 여유 호스: 굽이는 옆으로만 휜다 — 거리(결합구·물머리 자리)는 그대로, 구간 밖과 구간 양 끝은 원래 자리
func test_slack_bends_sideways_and_keeps_distance() -> void:
	var raw: Dictionary = HoseDraw.runs(_straight(40), 1, 1.2, 4)[0]
	var run := HoseDraw.with_slack(raw, [[4.0, 12.0, 1.0]], 0.8, 4.0, 0.5)
	var dist: PackedFloat32Array = run.dist
	assert_eq(dist[0], 0.0, "펌프차 쪽 끝 거리")
	assert_true(absf(dist[dist.size() - 1] - 40.0) < 0.001, "관창 쪽 끝 거리 = 시뮬레이션 길이")
	for k in range(1, dist.size()):
		assert_true(dist[k] > dist[k - 1], "거리는 늘기만 한다 (%d)" % k)
	var widest := 0.0
	for k in run.pts.size():
		var p: Vector2 = run.pts[k]
		assert_true(absf(p.x - 0.5 - dist[k]) < 0.001, "앞뒤로는 옮기지 않는다 (%s)" % p)
		if dist[k] <= 4.001 or dist[k] >= 11.999:
			assert_true(absf(p.y - 0.5) < 0.001, "구간 밖·구간 양 끝은 원래 자리 (%s)" % p)
		widest = maxf(widest, absf(p.y - 0.5))
	assert_true(widest > 0.3 and widest <= 0.8001, "구간 안에서는 옆으로 휜다 (%.2f칸)" % widest)
	assert_eq(HoseDraw.couplings(run, 15.0), HoseDraw.couplings(raw, 15.0), "결합구 거리는 그대로")
	assert_eq(HoseDraw.point_at(run, 30.0), HoseDraw.point_at(raw, 30.0), "구간 밖의 결합구 자리는 그대로")
	# 팽팽하면(크기 0) 굽이가 없다
	assert_eq(HoseDraw.with_slack(raw, [[4.0, 12.0, 1.0]], 0.0, 4.0, 0.5).pts, raw.pts, "크기 0 = 곧은 호스")


func test_slack_amount_shrinks_near_limit() -> void:
	assert_eq(HoseDraw.slack_amount(50.0, 100.0, 0.3), 1.0, "남은 호스가 넉넉하면 굽이가 온전")
	assert_true(absf(HoseDraw.slack_amount(85.0, 100.0, 0.3) - 0.5) < 0.001, "남은 호스 15% = 절반")
	assert_eq(HoseDraw.slack_amount(100.0, 100.0, 0.3), 0.0, "한계 = 팽팽")
	assert_eq(HoseDraw.slack_amount(30.0, 0.0, 0.3), 1.0, "한도를 모르면 온전")


## D5: 호스는 차 가운데가 아니라 펌프차 후면 방수구(동작 패널, 2026-11-21 사용자)에서 나와 뒤 모서리를 돌아 나간다.
## 거리는 방수구 0, 원래 길에 이어진 뒤는 그대로
func test_hose_starts_at_vehicle_rear_port() -> void:
	var v := Vehicle.new()
	v.pos = Vector2(10.5, 10.5)
	v.heading = Vector2.RIGHT
	v.level = 1
	for south: bool in [true, false]:
		var cells: Array = []
		for k in 21:
			cells.append(Vector3i(10, 10 + (k if south else -k), 1))
		var h := _hose(cells)
		var lay := HoseDraw.port_of(h, v, 0.25, 1.0)
		var side := 1.0 if south else -1.0
		assert_eq(lay.port, Vector2(10.5 - v.length_cells * 0.5, 10.5 + side * v.width_cells * 0.25), "방수구 = 차 후면, 호스가 나가는 쪽 (%s)" % ("남" if south else "북"))
		assert_eq(lay.port_out, lay.port + Vector2(-1.0, 0.0), "호스는 뒤로 나온다")
		assert_eq(lay.port_corner, Vector2(10.5 - v.length_cells * 0.5 - 1.0, 10.5 + side * (v.width_cells * 0.5 + 1.0)), "뒤 모서리 바깥을 돈다")
		var run: Dictionary = HoseDraw.runs(h, 1, 1.2, 4, lay)[0]
		assert_eq(run.pts[0], lay.port, "호스는 방수구에서 시작")
		assert_eq(run.dist[0], 0.0, "방수구 거리 0")
		assert_true(absf(float(run.dist[run.dist.size() - 1]) - h.length_cells()) < 0.001, "끝 거리 = 시뮬레이션 길이")
		assert_eq(run.pts[run.pts.size() - 1], Vector2(10.5, 10.5 + side * 20.0), "관창 쪽 끝은 그대로")
		for k in range(1, run.pts.size()):
			assert_true(run.dist[k] > run.dist[k - 1], "거리는 늘기만 한다")
			assert_true(not v.contains(run.pts[k]), "차 몸통 밑을 지나지 않는다 (%s)" % run.pts[k])
		assert_true(float(run.slack_from) > 0.0 and float(run.slack_from) < 3.0, "방수구 바로 바깥부터 굽이를 둘 수 있다 (%.2f)" % float(run.slack_from))
		assert_eq(HoseDraw.point_at(run, 15.0), Vector2(10.5, 10.5 + side * 15.0), "원래 길에 이어진 뒤의 거리는 그대로")
		assert_true(HoseDraw.dist_ahead(run, float(run.slack_from), 8.0) < float(run.slack_from) + 8.0, "앞머리는 거리가 눌려 있다 — 굽이 길이는 화면 길이로 잰다")
	# 차 뒤로 곧게 나가는 호스: 방수구는 후면 가운데, 모서리를 돌지 않는다
	var back_cells: Array = []
	for k in 21:
		back_cells.append(Vector3i(10 - k, 10, 1))
	var back := HoseDraw.port_of(_hose(back_cells), v, 0.25, 1.0)
	assert_eq(back.port, Vector2(10.5 - v.length_cells * 0.5, 10.5), "뒤로 나가면 후면 가운데")
	var back_run: Dictionary = HoseDraw.runs(_hose(back_cells), 1, 1.2, 4, back)[0]
	assert_eq(back_run.pts[0], back.port, "후면에서 시작")
	assert_eq(back_run.pts[back_run.pts.size() - 1], Vector2(-9.5, 10.5), "관창 쪽 끝")
	for p: Vector2 in back_run.pts:
		assert_true(p.x <= 3.5001 and absf(p.y - 10.5) < 0.001, "차 뒤로 곧게 (%s)" % p)
	# 차 뒤에서 시작해 차를 뚫고 앞으로 가는 길 (길 찾기는 차를 피하지 않는다): 차 몸통 밑을 지나지 않고 옆을 돌아간다
	var through_cells: Array = []
	for k in 31:
		through_cells.append(Vector3i(2 + k, 10, 1))
	var through := _hose(through_cells)
	var through_lay := HoseDraw.port_of(through, v, 0.25, 1.0)
	var through_run: Dictionary = HoseDraw.runs(through, 1, 1.2, 4, through_lay)[0]
	assert_eq(through_run.pts[0], through_lay.port, "후면에서 시작")
	assert_eq(through_run.pts[through_run.pts.size() - 1], Vector2(32.5, 10.5), "관창 쪽 끝")
	assert_true(absf(float(through_run.dist[through_run.dist.size() - 1]) - through.length_cells()) < 0.001, "끝 거리 = 시뮬레이션 길이")
	for k in range(1, through_run.pts.size()):
		assert_true(through_run.dist[k] > through_run.dist[k - 1], "거리는 늘기만 한다")
	# 호스를 따라 촘촘히 짚어 본다 (점 사이의 선도 차에 걸리지 않아야 한다)
	var beside := false
	var inside := 0
	for s in 601:
		var p := HoseDraw.point_at(through_run, through.length_cells() * s / 600.0)
		if s > 0 and v.contains(p):
			inside += 1
		beside = beside or (absf(p.x - 10.5) < 3.0 and absf(p.y - 10.5) > v.width_cells * 0.5)
	assert_eq(inside, 0, "차 몸통 밑을 지나지 않는다")
	assert_true(beside, "차 옆을 따라 간다")
	# 차에서 떨어진 곳에서 시작하는 호스 (차가 자리를 옮긴 뒤): 방수구로 잇지 않는다
	var far := _hose([Vector3i(40, 10, 1), Vector3i(41, 10, 1), Vector3i(42, 10, 1)])
	assert_true(HoseDraw.port_of(far, v, 0.25, 1.0).is_empty(), "멀리서 시작하면 그대로")


## 급수 호스(소화전·물탱크차)가 차에 붙는 자리: 펌프차는 후면 보수구 — 호스가 오는 쪽 끝, 그 밖의 차는 가장 가까운 차체 둘레
func test_supply_hose_connects_at_pump_rear() -> void:
	var pump := Vehicle.new()
	pump.pos = Vector2(10.5, 10.5)
	pump.heading = Vector2.RIGHT
	pump.nozzle_lpm = 275.0
	var ratio := float(HoseDraw.style().intake_across_ratio)
	assert_true(ratio > 0.0 and ratio <= 0.5, "보수구는 후면 폭 안에")
	for south: bool in [true, false]:
		var side := 1.0 if south else -1.0
		# 차 옆, 앞쪽에 있는 소화전
		var hydrant := Vector2(14.5, 10.5 + side * 5.0)
		var at := HoseDraw.intake_point(pump, hydrant)
		assert_eq(at, Vector2(10.5 - pump.length_cells * 0.5, 10.5 + side * pump.width_cells * ratio), "후면, 소화전 쪽 끝 (%s)" % ("남" if south else "북"))
		# 호스는 차 뒤로 돌아 후면에 붙는다 — 차 몸통 밑을 지나지 않는다 (차에 붙는 끝점은 뺀다)
		var route := HoseDraw.supply_route(pump, hydrant, 0.5)
		assert_eq(route[0], hydrant, "소화전에서 시작")
		assert_eq(route[route.size() - 1], at, "후면 보수구에서 끝")
		var inside := 0
		for k in range(1, route.size()):
			for s in range(1, 20):
				if pump.contains(route[k - 1].lerp(route[k], s / 20.0)):
					inside += 1
		assert_eq(inside, 0, "급수 호스가 차 몸통을 지나지 않는다")
	# 물탱크차(관창 없음)는 예전처럼 가장 가까운 차체 둘레
	var tanker := Vehicle.new()
	tanker.pos = Vector2(-10.5, 10.5)
	tanker.heading = Vector2.RIGHT
	var into := HoseDraw.intake_point(pump, tanker.pos)
	assert_eq(into, Vector2(3.5, 10.5), "뒤에 선 물탱크차에서 오면 후면 가운데")
	assert_eq(HoseDraw.intake_point(tanker, into), tanker.closest_body_point(into), "물탱크차 쪽은 가장 가까운 곳 (앞머리)")
	assert_eq(HoseDraw.supply_route(pump, Vector2(-3.5, 10.5), 0.5), PackedVector2Array([Vector2(-3.5, 10.5), into]), "걸리는 것이 없으면 곧게")
	# 물탱크차가 펌프차 앞에 서 있으면: 급수 호스는 펌프차 몸통을 뚫지 않고 옆을 돌아 후면으로 간다
	var ahead := Vector2(20.5, 10.5)
	var around := HoseDraw.supply_route(pump, ahead, 0.5)
	assert_true(around.size() >= 4, "돌아가는 길 (%d점)" % around.size())
	assert_eq(around[0], ahead, "급수하는 차 쪽 끝")
	assert_eq(around[around.size() - 1], Vector2(3.5, 10.5), "받는 쪽 끝은 펌프차 후면")
	var under := 0
	for k in range(1, around.size()):
		for s in range(1, 20):
			if pump.contains(around[k - 1].lerp(around[k], s / 20.0)):
				under += 1
	assert_eq(under, 0, "펌프차 몸통 밑을 지나지 않는다")
	# 굴려 펴는 중: 길의 앞부분만
	var half := HoseDraw.cut(around, 0.5)
	assert_eq(half[0], ahead, "펴기 시작한 곳")
	var full_len := 0.0
	var half_len := 0.0
	for k in range(1, around.size()):
		full_len += around[k - 1].distance_to(around[k])
	for k in range(1, half.size()):
		half_len += half[k - 1].distance_to(half[k])
	assert_true(absf(half_len - full_len * 0.5) < 0.001, "절반만 폈다 (%.1f / %.1f칸)" % [half_len, full_len])
	assert_eq(HoseDraw.cut(around, 1.0), around, "다 폈다")
	# 실제 화면에 그리는 선: 소화전을 점령한 펌프차
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var v: Vehicle = null
	for cand in sim.units.vehicles:
		if cand.is_pump() and v == null:
			v = cand
	assert_true(v != null and not sim.building.hydrants.is_empty(), "펌프차와 소화전")
	v.hydrant = 0
	var lines := UnitsView.supply_lines(sim)
	assert_eq(lines.size(), 1, "급수 호스 한 줄")
	var end: Vector2 = lines[0][lines[0].size() - 1]
	assert_eq(lines[0][0], Vector2(sim.building.hydrants[0]) + Vector2(0.5, 0.5), "소화전에서 시작")
	assert_true(absf((end - v.pos).dot(v.heading) + v.length_cells * 0.5) < 0.001, "차 쪽 끝은 후면")


## D5 시뮬레이션: 펌프차에서 건물 안까지 깐 호스 — 방수구에서 시작, 방수구 옆과 건물 앞에 굽이, 문은 곧게 지나고, 팽팽하면 편다
func test_layout_slack_at_port_and_before_building() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	assert_true(sim.water.lay_hose(0, 0, 0), "수관 연장")
	var h := sim.water.hose_of_crew(0)
	var v := sim.units.get_vehicle(h.vehicle_id)
	var b := sim.building
	# 호스 길이는 펌프차 후면 방수구 바로 뒤에서부터 잰다 (2026-11-21 — 예전에는 차 가운데)
	var first := Vector2(h.points[0].x + 0.5, h.points[0].y + 0.5)
	assert_true(not v.contains(first) and first.distance_to(v.rear_point()) <= 2.0, "수관은 차 후면 바로 뒤에서 시작 (%s, 후면 %s)" % [first, v.rear_point()])
	assert_eq(Vector2i(h.points[0].x, h.points[0].y), sim.water.hose_start_cell(v), "시작 칸")
	# 불난 건물 출입문 바로 앞까지 길을 찾고, 문과 그 안쪽 한 칸을 이어 건물 안까지 깐 호스를 만든다 (문이 닫혀 있어도 되게)
	var door := Vector2i(-1, -1)
	var out_dir := Vector2i.ZERO
	for e in sim.entries.list:
		if e.level == v.level and not e.neighbour and door.x < 0:
			door = Vector2i(e.door)
			out_dir = Vector2i(Vector2(e.outward).normalized().round())
	assert_true(door.x >= 0 and out_dir != Vector2i.ZERO, "출입문")
	var front := sim.pathfinder.nearest_walkable(v.level, door + out_dir * 2)
	h.points = sim.pathfinder.find_path(h.points[0], Vector3i(front.x, front.y, v.level))
	assert_true(h.points.size() > 10, "문 앞까지 길 (%d칸)" % h.points.size())
	for step: Vector2i in [door + out_dir, door, door - out_dir]:
		if Vector2i(h.points[-1].x, h.points[-1].y) != step:
			h.points.append(Vector3i(step.x, step.y, v.level))
	h.max_cells = h.length_cells() * 2.0
	var cell_m := b.cell_size_m
	var entry := HoseDraw.entry_dist(h, b)
	assert_true(entry > 0.0 and entry <= h.length_cells(), "건물에 들어서는 거리 (%.1f칸)" % entry)
	var lay := HoseDraw.layout(h, v, b)
	assert_true(lay.has("port") and absf((lay.port - v.pos).dot(v.heading) + v.length_cells * 0.5) < 0.01 and not v.contains(lay.port_out), "방수구는 차 후면에")
	assert_eq(float(lay.amount), 1.0, "남은 호스가 넉넉 = 굽이 온전")
	var plain: Dictionary = HoseDraw.runs(h, v.level, float(HoseDraw.style().corner_radius_m) / cell_m, int(HoseDraw.style().corner_steps), lay)[0]
	var run: Dictionary = HoseDraw.shaped_runs(h, v.level, cell_m, lay)[0]
	var windows := HoseDraw.slack_windows(plain, lay, cell_m)
	assert_eq(windows.size(), 2, "굽이 두 곳 — 방수구 옆·건물 앞")
	assert_true(float(windows[1][1]) < entry and float(windows[1][0]) >= float(windows[0][1]), "건물 앞 굽이는 들어서기 전에 끝나고 방수구 옆 굽이와 겹치지 않는다")
	assert_true(run.pts.size() > plain.pts.size(), "굽이만큼 점이 늘어남")
	assert_true(absf(float(run.dist[run.dist.size() - 1]) - h.length_cells()) < 0.001, "끝 거리 = 시뮬레이션 길이")
	assert_true(HoseDraw.point_at(run, entry).distance_to(HoseDraw.point_at(plain, entry)) < 0.001, "건물에 들어서는 곳은 곧게 지난다")
	for w: Array in windows:
		var bent := 0.0
		for s in 41:
			var d := lerpf(float(w[0]), float(w[1]), s / 40.0)
			bent = maxf(bent, HoseDraw.point_at(run, d).distance_to(HoseDraw.point_at(plain, d)))
		assert_true(bent > 0.3, "굽이에서 옆으로 벗어남 (%.1f~%.1f칸 구간, %.2f칸)" % [float(w[0]), float(w[1]), bent])
	# 호스를 다 썼으면 팽팽하다 — 굽이 없이 곧은 길
	h.max_cells = h.length_cells()
	var taut := HoseDraw.layout(h, v, b)
	assert_eq(float(taut.amount), 0.0, "한계 = 팽팽")
	assert_eq(HoseDraw.shaped_runs(h, v.level, cell_m, taut)[0].pts, plain.pts, "팽팽하면 곧은 호스")


## 시뮬레이션: 물머리가 펌프차 쪽부터 나아가고(그 앞은 부푼 호스, 뒤는 납작한 호스), 한 번 찬 호스는 끌고 가도 차 있다
func test_sim_water_head_advances() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	assert_true(sim.water.hose_length_cells() > 0.0, "1본 길이 (칸)")
	assert_true(sim.water.lay_hose(0, 0, 0), "수관 연장")
	var h := sim.water.hose_of_crew(0)
	assert_eq(h.water_head, 0.0, "연장 직후: 납작")
	sim.step_ticks(h.ready_tick - sim.clock.tick + 5)
	var early := h.water_head
	assert_true(early > 0.0, "준비가 끝나면 물이 들어가기 시작")
	for i in 3000:
		if h.charged:
			break
		sim.step_ticks(1)
	assert_true(h.charged and absf(h.water_head - h.length_cells()) < 0.001, "끝까지 참")
	# 찬 호스를 끌고 더 간다
	var lead := sim.units.get_crew(0).leader
	var goal := sim.pathfinder.nearest_walkable(lead.level, Vector2i(floori(lead.pos.x) + 8, floori(lead.pos.y)))
	var before := h.length_cells()
	sim.units.order_move([0] as Array[int], Vector3i(goal.x, goal.y, lead.level), sim.pathfinder)
	sim.step_ticks(100)
	assert_true(h.length_cells() > before, "호스가 늘어남 (%.1f → %.1f칸)" % [before, h.length_cells()])
	assert_true(h.charged and absf(h.water_head - h.length_cells()) < 0.001, "끌고 가도 차 있다")
	assert_eq(sim.events.of_type("hose_charged").size(), 1, "충수 완료 보고는 한 번")
