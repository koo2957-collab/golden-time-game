extends TestSuite
## 출동 단계의 도시 배경 (기획안 4-4, 2026-11-14): 화면을 꽉 채우는 도시 · 격자 도로망 · 안전센터와 출동 경로 ·
## 현장과 경로를 가리지 않는 건물 높이 · 밤 창문 불빛. 배치는 CityPlan, 그리기는 CityMassView.

const MAP := Vector2i(72, 40)
const ROAD_ROWS := Vector2i(28, 39)


func _plan(p_seed := 7) -> CityPlan:
	var plan := CityPlan.new()
	plan.generate(MAP, ROAD_ROWS, p_seed, 30.5)
	return plan


func test_city_params_have_source() -> void:
	var data: Dictionary = JsonData.load_file(CityPlan.PATH)
	for key: String in data:
		var entry: Variant = data[key]
		if entry is Dictionary:
			assert_true((entry as Dictionary).has("source"), "%s에 source" % key)
	assert_true(CityPlan.load_params().has("overview_width_m"), "설정을 읽는다")


func test_same_seed_same_city() -> void:
	var a := _plan(7)
	var b := _plan(7)
	var c := _plan(8)
	assert_eq(a.lots.size(), b.lots.size(), "같은 시드는 같은 건물 수")
	var same := true
	for i in a.lots.size():
		if a.lots[i].rect != b.lots[i].rect or a.lots[i].floors != b.lots[i].floors:
			same = false
	assert_true(same, "같은 시드는 같은 도시")
	var differs := a.lots.size() != c.lots.size()
	for i in mini(a.lots.size(), c.lots.size()):
		if a.lots[i].rect != c.lots[i].rect or a.lots[i].floors != c.lots[i].floors:
			differs = true
	assert_true(differs, "시드가 다르면 다른 도시")
	assert_true(a.lots.size() > 200, "건물이 충분히 많다 (%d)" % a.lots.size())


## 원경 화면(16:9와 4:3)의 네 귀퉁이·가장자리 땅이 모두 도시 안이고, 그 근처에 건물이 있다
func test_city_fills_the_overview_screen() -> void:
	var plan := _plan()
	for aspect: float in [0.5625, 0.75]:
		var hv := aspect * plan.half_u * IsoProjection.HALF_W / IsoProjection.HALF_H
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
			var du := corner.x * plan.half_u
			var dv := corner.y * hv
			var cell := plan.center + Vector2((dv + du) * 0.5, (dv - du) * 0.5)
			assert_true(Rect2(plan.bounds).has_point(cell), "화면 %s 쪽 땅이 도시 안 (화면비 %.2f)" % [corner, aspect])
			assert_true(plan.in_view(cell, 1.0), "원경에 들어오는 곳으로 센다")
			var near := false
			for lot: Dictionary in plan.lots:
				if Vector2((lot.rect as Rect2i).get_center()).distance_to(cell) < 110.0:
					near = true
					break
			assert_true(near, "화면 %s 쪽에 건물이 있다 (화면비 %.2f)" % [corner, aspect])
	# 배율: 화면 가로에 400m (1m = 79.2px)
	var zoom := plan.overview_zoom(1920.0)
	assert_true(absf(zoom - 1920.0 / (plan.num("overview_width_m") * 79.2)) < 0.001, "원경 배율 (%.4f)" % zoom)


func test_streets_site_and_station() -> void:
	var plan := _plan()
	assert_eq(plan.avenue, Vector2i(28, 40), "큰길 = 현장 앞 도로를 이은 길")
	assert_true(plan.row_streets.has(Vector2i(-12, 0)), "현장 뒤(북쪽) 길")
	assert_true(plan.col_streets.has(Vector2i(-12, 0)) and plan.col_streets.has(Vector2i(72, 84)), "현장 양옆 길")
	var clear := true
	for lot: Dictionary in plan.lots:
		var r: Rect2i = lot.rect
		if r.intersects(plan.map_rect):
			clear = false
		for s in plan.row_streets:
			if r.position.y < s.y and r.end.y > s.x:
				clear = false
		for s in plan.col_streets:
			if r.position.x < s.y and r.end.x > s.x:
				clear = false
	assert_true(clear, "건물은 현장과 길 위에 서지 않는다")
	var stations := plan.lots.filter(func(l: Dictionary) -> bool: return l.kind == "station")
	assert_eq(stations.size(), 1, "안전센터 하나")
	var st: Rect2i = plan.station.rect
	assert_true(st.end.x < 0 and st.end.y < 0, "안전센터는 현장 서북쪽 (%s)" % st)
	var overlap := plan.lots.filter(func(l: Dictionary) -> bool: return l.kind != "station" and (l.rect as Rect2i).intersects(st))
	assert_true(overlap.is_empty(), "안전센터 자리에 다른 건물이 없다")


func test_route_follows_streets() -> void:
	var plan := _plan()
	var route := plan.route
	assert_true(route.size() >= 3, "경로 점")
	assert_eq(route[0].x, float((plan.station.rect as Rect2i).end.x), "안전센터 앞에서 출발")
	assert_eq(route[route.size() - 1], Vector2(0.0, 30.5), "현장 지도 서쪽 끝, 차량이 들어오는 행에서 끝")
	for i in route.size() - 1:
		assert_true(is_equal_approx(route[i].x, route[i + 1].x) or is_equal_approx(route[i].y, route[i + 1].y), "길을 따라 직각으로 (%d번 구간)" % i)
	assert_true(plan.route_length() > 250.0, "달릴 거리가 있다 (%.0f칸)" % plan.route_length())
	# 안전센터 앞마당을 지난 뒤로는 늘 길 위
	var on_street := true
	for k in 101:
		var c := plan.route_point(k / 100.0)
		if c.x < float((plan.station.rect as Rect2i).end.x) + 2.5:
			continue
		var ok := false
		for s in plan.row_streets:
			if c.y >= s.x and c.y <= s.y:
				ok = true
		for s in plan.col_streets:
			if c.x >= s.x and c.x <= s.y:
				ok = true
		if not ok:
			on_street = false
	assert_true(on_street, "경로는 길 위로만 간다")
	assert_eq(plan.route_point(0.0), route[0], "진행률 0 = 출발점")
	assert_eq(plan.route_point(1.0), route[route.size() - 1], "진행률 1 = 도착점")
	assert_eq(plan.route_heading(1.0), Vector2(1, 0), "마지막에는 큰길을 따라 동쪽으로 (현장 차량과 같은 방향)")
	assert_true(plan.in_view(route[0]), "안전센터가 원경 화면 안에 있다")


## 건물 윗부분이 현장이나 출동 경로를 정해진 깊이보다 더 가리지 않는다
func test_buildings_do_not_hide_site_or_route() -> void:
	var plan := _plan()
	var floor_m := plan.num("floor_m")
	var worst := 0.0
	var capped := 0
	var tall := 0
	for lot: Dictionary in plan.lots:
		var r: Rect2i = lot.rect
		if lot.kind == "station":
			continue
		assert_true(int(lot.floors) <= plan.max_floors(r) and int(lot.floors) >= 1, "층수 제한 (%s %d층)" % [r, int(lot.floors)])
		if plan.max_floors(r) < 99:
			capped += 1
		if int(lot.floors) >= 10:
			tall += 1
		# 직접 재 본다: 윗부분이 가리는 땅(건물을 (-k, -k) 옮긴 자리)이 현장에 들어가는 깊이
		var k := int(lot.floors) * floor_m * CityPlan.SHIFT_PER_M
		var moved := Rect2(Vector2(r.position) - Vector2(k, k), Vector2(r.size))
		var hit := moved.intersection(Rect2(plan.map_rect))
		if hit.has_area():
			worst = maxf(worst, minf(hit.size.x, hit.size.y))
	assert_true(worst <= plan.num("site_cover_cells") + 0.01, "현장을 가리는 깊이 %.1f칸 (허용 %.0f칸)" % [worst, plan.num("site_cover_cells")])
	assert_true(capped > 0, "현장·경로 앞 건물은 낮춘다 (%d채)" % capped)
	assert_true(tall > 0, "다른 곳에는 높은 건물도 있다 (%d채)" % tall)
	# 큰길 바로 남쪽(경로 구간)의 건물: 윗부분이 큰길을 가리는 깊이가 허용(길 폭의 절반) 안
	var st_x := (plan.station.rect as Rect2i).end.x
	var first_row := 0
	for lot: Dictionary in plan.lots:
		var r: Rect2i = lot.rect
		if r.position.y >= plan.avenue.y and r.position.y < plan.avenue.y + 6 and r.end.x > st_x + 20 and r.position.x < 0:
			first_row += 1
			var covered := int(lot.floors) * floor_m * CityPlan.SHIFT_PER_M - (r.position.y - plan.avenue.y)
			assert_true(covered <= plan.num("route_cover_cells") + 0.01, "큰길 남쪽 첫 줄은 낮게 (%s %d층, 가림 %.1f칸)" % [r, int(lot.floors), covered])
			assert_true(int(lot.floors) <= 3, "첫 줄은 3층 이하 (%s %d층)" % [r, int(lot.floors)])
	assert_true(first_row >= 4, "경로 구간 남쪽에 건물이 있다 (%d채)" % first_row)


func test_night_windows_and_draw_budget() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var day := CityMassView.new()
	day.night = 0.0
	day.setup(sim.building, IsoProjection.new(), 3, sim)
	assert_eq([day.window_count, day.lamp_count], [0, 0], "낮에는 창문 불빛·가로등이 없다")
	assert_true(day.quad_count > 1000 and day.quad_count < 6000, "낮 그림량 (%d)" % day.quad_count)
	var night := CityMassView.new()
	night.night = 1.0
	night.setup(sim.building, IsoProjection.new(), 3, sim)
	assert_true(night.window_count > 1000, "밤에는 창문 불빛 (%d)" % night.window_count)
	assert_true(night.lamp_count > 100, "밤에는 가로등 (%d)" % night.lamp_count)
	assert_true(night.quad_count < 16000, "밤 그림량 상한 (%d)" % night.quad_count)
	assert_true(night._batches.size() <= 8, "그리기는 묶음 몇 번으로 (%d)" % night._batches.size())
	assert_eq(night.plan.lots.size(), day.plan.lots.size(), "낮과 밤은 같은 도시")
	# 켜진 창은 늘 같다 (다시 만들어도)
	var count := night.window_count
	night.build_mesh()
	assert_eq(night.window_count, count, "같은 창이 켜진다")
	# 현장 차량이 들어오는 행으로 경로가 맞춰진다
	if not sim.units.vehicles.is_empty():
		assert_eq(night.plan.route[night.plan.route.size() - 1].y, sim.units.vehicles[0].pos.y, "경로 끝 = 선착 차량이 들어오는 행")
		assert_eq(night.approach_cell(1.0, sim.units.vehicles[0].pos), sim.units.vehicles[0].pos, "진행률 1 = 차량이 설 자리")
		assert_eq(night.approach_cell(0.0, sim.units.vehicles[0].pos), night.plan.route[0], "진행률 0 = 안전센터 앞")
	day.free()
	night.free()
