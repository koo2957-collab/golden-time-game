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


## 호스 끼고 걷기 (E2·E3): 관창수 뒤로 호스 길을 거슬러 간 자리 — 관창수가 칸 경계를 넘어 호스 점이 늘어도 거리가 튀지 않는다
func test_trail_follows_leader_smoothly() -> void:
	var h := _straight(10)
	var before := HoseDraw.trail(h, 1, Vector2(10.5, 0.5))
	assert_true(absf(float(before.dist[before.dist.size() - 1]) - 10.0) < 0.001, "칸 가운데에 서면 끝 거리 = 호스 길이")
	# 다음 칸 쪽으로 0.49칸: 호스 점은 아직 그대로, 끝 거리는 그만큼 늘어난다
	var mid := HoseDraw.trail(h, 1, Vector2(10.99, 0.5))
	assert_true(absf(float(mid.dist[mid.dist.size() - 1]) - 10.49) < 0.001, "걸어간 만큼 늘어남 (%.2f)" % float(mid.dist[mid.dist.size() - 1]))
	# 경계를 넘어 호스 점이 하나 늘었다 (다음 칸 가운데) — 관창수는 아직 그 가운데에 닿지 않았다
	h.points.append(Vector3i(11, 0, 1))
	var after := HoseDraw.trail(h, 1, Vector2(11.01, 0.5))
	assert_true(absf(float(after.dist[after.dist.size() - 1]) - 10.51) < 0.001, "점이 늘어도 끝 거리는 이어진다 (%.2f)" % float(after.dist[after.dist.size() - 1]))
	assert_eq(after.pts[after.pts.size() - 1], Vector2(11.01, 0.5), "끝은 관창수 자리")
	# 뒤따르는 사람 자리: 끝에서 2.2칸(1.1m) 뒤
	var spot := HoseDraw.point_at(after, float(after.dist[after.dist.size() - 1]) - 2.2)
	assert_true(spot.distance_to(Vector2(8.81, 0.5)) < 0.001, "관창수 뒤 2.2칸 (%s)" % spot)
	# 다른 층에 깔린 부분은 넣지 않는다 / 그 층에 끝이 없으면 빈 것
	var up := _hose([Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 0, 2), Vector3i(2, 0, 2), Vector3i(3, 0, 2)])
	var top := HoseDraw.trail(up, 2, Vector2(3.5, 0.5))
	assert_eq(top.pts.size(), 3, "2층에 깔린 점만")
	assert_true(absf(float(top.dist[0]) - 7.0) < 0.001, "거리는 펌프차부터 (계단 6칸 포함)")
	assert_true(HoseDraw.trail(up, 1, Vector2(1.5, 0.5)).is_empty(), "끝이 그 층에 없으면 빈 것")


## 호스 끼고 걷기: 바닥 호스는 2번 뒤에서 끝나고, 3번이 들어 올린 구간은 비운다
func test_dry_ranges_cut_for_carried_hose() -> void:
	assert_eq(HoseDraw.dry_ranges(0.0, INF, []), [[0.0, INF]], "보통: 물머리부터 끝까지")
	assert_eq(HoseDraw.dry_ranges(3.0, 20.0, []), [[3.0, 20.0]], "2번 뒤에서 끝")
	assert_eq(HoseDraw.dry_ranges(0.0, 20.0, [10.0, 14.0]), [[0.0, 10.0], [14.0, 20.0]], "들어 올린 구간은 뺀다")
	assert_eq(HoseDraw.dry_ranges(12.0, 20.0, [10.0, 14.0]), [[14.0, 20.0]], "물머리가 구간 안이면 그 뒤만")
	assert_eq(HoseDraw.dry_ranges(0.0, 12.0, [10.0, 14.0]), [[0.0, 10.0]], "끝이 구간 안이면 그 앞만")
	assert_true(HoseDraw.dry_ranges(5.0, 5.0, []).is_empty(), "그릴 것 없음")
	var st := HoseDraw.style()
	assert_true(float(st.carry_drop_m) > 0.0 and float(st.tidy_gap_front_m) > 0.0 and float(st.tidy_gap_back_m) > 0.0, "그림과 맞춘 거리 값")


## 호스 끼고 걷기 그림이 묶음에 들어 있고, 2·3번의 자리(1번 뒤)가 적혀 있다
func test_hose_carry_art_baked() -> void:
	var art := SpriteArt.get_set(str(SpriteArt.config().get("crew", "")))
	assert_true(art != null, "대원 그림 묶음")
	if art == null:
		return
	assert_eq(art.frames("hose_carry_a"), 8, "1번 관창수: 걷기 한 주기 8장")
	assert_eq(art.frames("hose_carry_b"), 8, "2번 관창보조: 8장")
	assert_eq(art.frames("hose_tidy"), 16, "3번: 낮은 자세 걷기 16장")
	assert_true(float(art.stand("hose_carry_b").get("fwd_m", 0.0)) < -0.5, "2번은 1번 뒤 (%s)" % art.stand("hose_carry_b"))
	assert_true(float(art.stand("hose_tidy").get("fwd_m", 0.0)) < float(art.stand("hose_carry_b").get("fwd_m", 0.0)) - 1.0, "3번은 2번의 호스가 바닥에 닿은 뒤쪽 (%s)" % art.stand("hose_tidy"))
	# 호스 꺼내기 (E1, 2026-11-22 사용자가 블렌더에서 확인): 1번·2번이 차 후면 앞에 나란히
	assert_eq(art.frames("hose_fetch_a"), 12, "꺼내기 1번: 12장")
	assert_eq(art.frames("hose_fetch_b"), 12, "꺼내기 2번: 12장")
	assert_true(absf(float(art.stand("hose_fetch_b").get("right_m", 0.0))) > 0.4 and absf(float(art.stand("hose_fetch_b").get("fwd_m", 0.0))) < 0.1,
		"2번은 1번 옆에 나란히 (%s)" % art.stand("hose_fetch_b"))
	var fps: Dictionary = SpriteArt.config().get("fps", {})
	for anim: String in ["hose_fetch_a", "hose_fetch_b", "hose_carry_a", "hose_carry_b", "hose_tidy"]:
		assert_true(float(fps.get(anim, 0.0)) > 0.0, "%s 초당 장 수" % anim)
	var st := HoseDraw.style()
	assert_true(float(st.fetch_stand_m) > 0.3 and float(st.shutter_top_m) > float(st.shutter_bottom_m), "꺼낼 때 서는 거리·열린 셔터 높이")


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
	# 물탱크차도 후면에서 호스가 나온다 (2026-11-21 사용자). 물을 싣지 않는 차는 가장 가까운 차체 둘레
	var tanker := Vehicle.new()
	tanker.pos = Vector2(-10.5, 10.5)
	tanker.heading = Vector2.RIGHT
	tanker.transfer_lpm = 180.0
	var into := HoseDraw.intake_point(pump, tanker.rear_point())
	assert_eq(into, Vector2(3.5, 10.5), "뒤에 선 물탱크차에서 오면 후면 가운데")
	assert_eq(HoseDraw.intake_point(tanker, into), Vector2(-17.5, 10.5), "물탱크차 쪽도 후면")
	var plain := Vehicle.new()
	plain.pos = Vector2(-10.5, 10.5)
	plain.heading = Vector2.RIGHT
	assert_eq(HoseDraw.intake_point(plain, into), plain.closest_body_point(into), "물을 싣지 않는 차는 가장 가까운 곳")
	# 물탱크차 → 펌프차: 물탱크차 후면에서 나와 물탱크차를 돌아 펌프차 후면으로 — 어느 차 몸통도 지나지 않는다
	for place: Vector2 in [Vector2(-10.5, 10.5), Vector2(30.5, 10.5), Vector2(10.5, 20.5)]:
		tanker.pos = place
		for facing: Vector2 in [Vector2.RIGHT, Vector2.LEFT]:
			tanker.heading = facing
			var between := HoseDraw.supply_between(tanker, pump, 0.5)
			var what := "물탱크차 %s·%s" % [place, "→" if facing == Vector2.RIGHT else "←"]
			assert_true(absf((between[0] - tanker.pos).dot(tanker.heading) + tanker.length_cells * 0.5) < 0.001, "물탱크차 후면에서 시작 (%s)" % what)
			assert_true(absf((between[between.size() - 1] - pump.pos).dot(pump.heading) + pump.length_cells * 0.5) < 0.001, "펌프차 후면에서 끝 (%s)" % what)
			var hit := 0
			for k in range(1, between.size()):
				for s in range(1, 20):
					var q := between[k - 1].lerp(between[k], s / 20.0)
					if pump.contains(q) or tanker.contains(q):
						hit += 1
			assert_eq(hit, 0, "두 차의 몸통을 지나지 않는다 (%s)" % what)
	tanker.pos = Vector2(-10.5, 10.5)
	tanker.heading = Vector2.RIGHT
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
	# 차 후면에서 호스를 꺼내 서 있던 자리까지 깔아 온 상태로 (2026-11-21부터 호스는 한 번에 생기지 않는다)
	var h := fetch_hose(sim, 0)
	assert_true(h.length_cells() > 2.0, "서 있던 자리까지 깔린 호스 (%.1f칸)" % h.length_cells())
	assert_eq(h.water_head, 0.0, "연장 직후: 납작")
	sim.step_ticks(maxi(0, h.ready_tick - sim.clock.tick) + 5)
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


## 그림 속 호스의 끝 자리 (data/ui/hose_ends.json — tools/blender/hose_ends.py가 장면에서 잰 값, 2026-11-24):
## 뒤 사람의 호스 앞 끝은 앞사람 호스의 뒤 끝과 같은 곳이다 (구울 때의 자리에 서면 한 줄로 이어진다)
func test_baked_hose_ends_meet_in_line() -> void:
	var data: Variant = JsonData.load_file(HoseDraw.ENDS_PATH)
	assert_true(data is Dictionary and str(data.get("source", "")) != "" and data.get("ends") is Dictionary, "끝 자리 파일과 source")
	var art := SpriteArt.get_set(str(SpriteArt.config().get("crew", "")))
	assert_true(art != null, "대원 그림 묶음")
	if art == null:
		return
	var cell_m := 0.5
	for names: Array in [["spray_n", "spray_h1", "spray_h2"], ["spray_n", "spray_h"], ["spray_ln", "spray_lh1", "spray_lh2"], ["spray_ln", "spray_lh"]]:
		var facing := Vector2.RIGHT
		for i in range(1, names.size()):
			var back: Variant = HoseDraw.end_of(names[i - 1], "back")
			var front: Variant = HoseDraw.end_of(names[i], "front")
			assert_true(back != null and front != null, "%s 뒤 끝 · %s 앞 끝" % [names[i - 1], names[i]])
			if back == null or front == null:
				continue
			var a := HoseDraw.end_spot(FloorLayer.stand_spot(Vector2.ZERO, facing, art.stand(names[i - 1]), cell_m), facing, back, cell_m)
			var b := HoseDraw.end_spot(FloorLayer.stand_spot(Vector2.ZERO, facing, art.stand(names[i]), cell_m), facing, front, cell_m)
			assert_true(a.distance_to(b) * cell_m < 0.03 and absf((back as Vector3).z - (front as Vector3).z) < 0.03,
				"%s → %s 호스가 이어진다 (%.3fm)" % [names[i - 1], names[i], a.distance_to(b) * cell_m])
		var tail: Variant = HoseDraw.end_of(names[names.size() - 1], "back")
		assert_true(tail != null and (tail as Vector3).z < 0.1 and (tail as Vector3).x < 0.0, "맨 뒤 사람의 호스는 등 뒤 바닥에서 끝난다 (%s)" % names[names.size() - 1])
	assert_true(HoseDraw.end_of("spray_n", "front") == null, "관창수는 호스 조각이 없다 (관창 결합구만)")
	var st := HoseDraw.style()
	assert_true(float(st.join_length_m) > 0.0 and float(st.chain_near_m) > 0.0 and float(st.sprite_hose_width_m) > 0.0 and float(st.sprite_flat_width_m) > 0.0, "이음 설정값")


## 방수하는 조의 자리 (2026-11-24 사용자 — 꺾이는 곳에서도 세 명이 일렬로 서던 것):
## 곧은 곳은 구울 때의 자리 그대로, 벽에 막히거나 호스가 꺾인 곳에서는 뒤 사람이 호스가 온 쪽으로 틀어 서고 호스 끝끼리 닿는다
func test_spray_chain_turns_at_bends() -> void:
	var art := SpriteArt.get_set(str(SpriteArt.config().get("crew", "")))
	if art == null:
		assert_true(false, "대원 그림 묶음")
		return
	var cell_m := 0.5
	var names: Array = ["spray_n", "spray_h1", "spray_h2"]
	var stands := {}
	for n: String in names:
		stands[n] = art.stand(n)
	var lead := Vector2(20.5, 10.5)
	var open := func(_from: Vector2, _to: Vector2) -> bool: return true
	# ① 호스가 뒤(서쪽)에서 곧게 온다 — 동쪽으로 방수: 구울 때의 자리 그대로 일렬
	var west := _hose([Vector3i(5, 10, 1), Vector3i(20, 10, 1)])
	var straight := HoseDraw.chain_spots(lead, 0, names, stands, cell_m, HoseDraw.trail(west, 1, lead), open, 1.2)
	assert_eq(straight.ks, [0, 0, 0] as Array[int], "곧은 곳: 모두 같은 방향")
	for i in 3:
		assert_true((straight.spots[i] as Vector2).distance_to(FloorLayer.stand_spot(lead, Vector2.RIGHT, art.stand(names[i]), cell_m)) < 0.001, "곧은 곳: %s 는 구울 때의 자리" % names[i])
	assert_true(straight.has("tail") and float(straight.tail.pos.x) < float(straight.spots[2].x) and float(straight.tail.h_m) < 0.1, "바닥 호스가 닿을 곳 = 3번 뒤 바닥")
	# ② 호스가 남쪽에서 와서 관창수 자리에서 꺾인다 — 2번은 관창수 바로 뒤 그대로, 3번은 남쪽(호스가 온 쪽)으로 틀어 선다
	var south := _hose([Vector3i(20, 30, 1), Vector3i(20, 10, 1)])
	var bent := HoseDraw.chain_spots(lead, 0, names, stands, cell_m, HoseDraw.trail(south, 1, lead), open, 1.2)
	assert_eq(int(bent.ks[1]), 0, "2번은 관창수 바로 뒤 (반동을 받친다)")
	assert_true((bent.spots[1] as Vector2).distance_to(straight.spots[1]) < 0.001, "2번 자리는 그대로")
	assert_true(int(bent.ks[2]) != 0 and float(bent.spots[2].y) > float(bent.spots[1].y) + 0.5, "3번은 남쪽으로 틀어 선다 (방향 %d, %s)" % [int(bent.ks[2]), bent.spots[2]])
	var f3 := Vector2.RIGHT.rotated(int(bent.ks[2]) * PI / 4.0)
	var joint := HoseDraw.end_spot(bent.spots[1], Vector2.RIGHT, HoseDraw.end_of("spray_h1", "back"), cell_m)
	var front3 := HoseDraw.end_spot(bent.spots[2], f3, HoseDraw.end_of("spray_h2", "front"), cell_m)
	assert_true(joint.distance_to(front3) < 0.001, "3번 호스의 앞 끝이 2번 호스의 뒤 끝에 닿는다")
	assert_true((bent.tail.dir as Vector2).distance_to(f3) < 0.001 and float(bent.tail.pos.y) > float(bent.spots[2].y), "바닥 호스는 3번 뒤(남쪽)에서 닿는다")
	# ③ 관창수 바로 뒤가 벽이다 — 2번도 틀어 선다 (벽을 뚫고 서지 않는다)
	var wall := func(_from: Vector2, to: Vector2) -> bool: return to.x >= 19.5
	var blocked := HoseDraw.chain_spots(lead, 0, names, stands, cell_m, HoseDraw.trail(south, 1, lead), wall, 1.2)
	for i in 3:
		assert_true(float(blocked.spots[i].x) >= 19.5, "%s 는 벽 안에 서지 않는다 (%s)" % [names[i], blocked.spots[i]])
	assert_true(int(blocked.ks[1]) != 0, "2번도 방향을 튼다")
	var f2 := Vector2.RIGHT.rotated(int(blocked.ks[1]) * PI / 4.0)
	assert_true(HoseDraw.end_spot(blocked.spots[1], f2, HoseDraw.end_of("spray_h1", "front"), cell_m).distance_to(
		HoseDraw.end_spot(lead, Vector2.RIGHT, HoseDraw.end_of("spray_n", "back"), cell_m)) < 0.001, "2번 호스의 앞 끝이 관창 결합구에 닿는다")
	# ④ 갈 곳이 없으면 (사방이 막힘) 예전처럼 곧게 — 사람이 사라지지 않는다
	var none := func(_from: Vector2, _to: Vector2) -> bool: return false
	var stuck := HoseDraw.chain_spots(lead, 0, names, stands, cell_m, HoseDraw.trail(south, 1, lead), none, 1.2)
	assert_eq(stuck.spots.size(), 3, "세 명 모두 자리가 있다")
	assert_eq(stuck.ks, [0, 0, 0] as Array[int], "막히면 곧게")


## 바닥 호스를 그림 속 호스의 끝으로 잇는 곡선: 끝 점에 닿고, 직각으로 꺾이지 않는다
func test_tail_curve_is_smooth() -> void:
	var a := Vector2(0, 0)
	var tail := Vector2(2, 2)
	var pts := HoseDraw.tail_curve(a, Vector2.RIGHT, tail, Vector2.DOWN, 8)
	assert_eq(pts.size(), 8, "점 수")
	assert_true(pts[pts.size() - 1].distance_to(tail) < 0.001, "끝 점에 닿는다")
	var all := PackedVector2Array([a])
	all.append_array(pts)
	var worst := 0.0
	for i in range(1, all.size() - 1):
		worst = maxf(worst, absf((all[i] - all[i - 1]).angle_to(all[i + 1] - all[i])))
	assert_true(worst < deg_to_rad(35.0), "마디마다 조금씩만 꺾인다 (가장 큰 각 %.0f°)" % rad_to_deg(worst))
	assert_true(absf((all[1] - all[0]).angle_to(Vector2.RIGHT)) < 0.35, "떠나는 방향 = 바닥 호스가 가던 방향")
	assert_true(absf((all[all.size() - 1] - all[all.size() - 2]).angle_to(Vector2.DOWN)) < 0.35, "닿는 방향 = 그림 속 호스 방향")
	# 가늘어지는 조각: 이은 뒤쪽만 나뉘고 끝으로 갈수록 좁다
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0), Vector2(30, 5), Vector2(40, 10)])
	var pieces := HoseDraw._pieces(line, line, 3, 8.0, 4.0)
	assert_eq(pieces.size(), 3, "제 굵기 한 줄 + 이은 구간 둘")
	assert_true(float(pieces[0][2]) == 8.0 and float(pieces[1][2]) < 8.0 and float(pieces[2][2]) < float(pieces[1][2]) and float(pieces[2][2]) > 4.0 - 0.001, "끝으로 갈수록 가늘다")
	assert_eq(HoseDraw._pieces(line, line, 0, 8.0, 4.0).size(), 1, "잇지 않으면 한 줄")
