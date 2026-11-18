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


## 시뮬레이션: 방수 개시 전에는 물머리 0, 뒤에는 호스 끝 (화면이 납작 → 부푼 호스로 바꾼다)
func test_sim_water_head_and_length() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	assert_true(sim.water.hose_length_cells() > 0.0, "1본 길이 (칸)")
	assert_true(sim.water.lay_hose(0, 0, 0), "수관 연장")
	var h := sim.water.hose_of_crew(0)
	assert_eq(sim.water.water_head_cells(h, h.water_tick - 1), 0.0, "방수 개시 전: 납작")
	assert_true(absf(sim.water.water_head_cells(h, h.water_tick) - h.length_cells()) < 0.001, "방수 개시 뒤: 끝까지 참")
