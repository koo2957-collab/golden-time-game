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
		var v: Vehicle = night.convoy()[0]
		assert_true(v.is_pump(), "행렬 맨 앞은 선착 펌프차")
		assert_eq(night.plan.route[night.plan.route.size() - 1].y, v.pos.y, "경로 끝 = 선착 차량이 들어오는 행")
		assert_eq(night.truck_cell(0.0, 0, v), night.plan.route[0], "진행률 0 = 안전센터 앞")
		# 진행률 1 = 시뮬레이션 차량이 들어오기 시작하는 자리 (도착하면 그 자리에서 이어 들어온다)
		var stop := night.truck_cell(1.0, 0, v)
		var start := sim.command.resources.entry_start(v, v.pos, v.heading)
		assert_true(stop.is_equal_approx(start) and start.x < 0.0, "진행률 1 = 현장 차량이 출발하는 자리 (%s / %s)" % [stop, start])
		assert_true(night.truck_cell(0.5, 0, v).x < 0.0, "가는 동안은 지도 밖")
		assert_true(night.truck_distance(0.0, 1, night.convoy()[1]) < 0.0, "뒤차는 처음에 출발 전")
	day.free()
	night.free()


## 출동 4단계 (2026-11-15): 도시의 출동 행렬이 현장에 들어오는 차량으로 끊김 없이 이어진다
func test_convoy_joins_arriving_vehicles() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/sop213_1_apartment_3f.json")
	var res := sim.command.resources
	res.arrival_drive = true
	var view := CityMassView.new()
	view.setup(sim.building, IsoProjection.new(), 3, sim)
	var list := view.convoy()
	assert_eq(list.size(), sim.units.vehicles.size(), "처음 오는 차량이 모두 행렬에 (%d대)" % list.size())
	assert_true(list[0].is_pump() and list[0].squad_id == 0, "선착 펌프차가 맨 앞")
	var gap_s := float(sim._phase_params.value("arrival_gap_s"))
	# 진행률 1: 차마다 자기가 들어올 자리에서 '도착 간격 × 속도'만큼 뒤, 자기 차로에 있다
	for i in list.size():
		var v := list[i]
		var start := res.entry_start(v, v.pos, v.heading)
		var want := start - v.heading * (i * gap_s * v.speed_cells)
		assert_true(view.truck_cell(1.0, i, v).is_equal_approx(want), "%s: 도착 순간의 자리 (%s / %s)" % [v.short_name, view.truck_cell(1.0, i, v), want])
	for i in range(1, list.size()):
		assert_true(view.truck_cell(1.0, i, list[i]).x < view.truck_cell(1.0, i - 1, list[i - 1]).x - 2.0, "뒤차는 앞차 뒤에")
	# 들어올 자리에 가까워지면 그림이 실제 크기
	assert_eq(view.truck_scale(0.0), 1.0, "다 오면 실제 크기")
	assert_eq(view.truck_scale(1000.0), view.plan.num("truck_scale"), "멀리서는 크게")
	# 출동 중에 차량 배치를 고르면 그 자리의 차로로 들어간다 (아직 시뮬레이션에 넣기 전)
	var opts := Placement.options(sim)
	var far := -1
	for i in opts.size():
		if int(opts[i].vehicles[0].spawn[1]) + 0.5 != list[0].pos.y:
			far = i
	assert_true(far >= 0, "다른 차로에 세우는 배치 보기")
	var pick := [-1]
	view.placement = func() -> int: return pick[0]
	var before := view.truck_cell(1.0, 0, list[0])
	pick[0] = far
	var row := int(opts[far].vehicles[0].spawn[1]) + 0.5
	assert_eq(view.truck_cell(1.0, 0, list[0]).y, row, "고른 배치의 차로로 (%s → %.1f)" % [before, row])
	var mid := view.truck_distance(0.3, 0, list[0]) / view.plan.route_length()
	assert_true(view.truck_cell(0.3, 0, list[0]).is_equal_approx(view.plan.route_point(mid)), "차로는 길 끝에서만 바꾼다 (가는 길은 그대로)")
	# 배치를 시뮬레이션에 넣고 도착: 뒤차는 들어올 자리로 달려오다가 그 자리에서 시뮬레이션 차량이 이어받는다
	sim.issue(CommandOrder.make("placement", [], far))
	sim.step_ticks(1)
	assert_true(not sim.command.placement.is_empty(), "배치가 적용됐다")
	# 도착 순간 도시의 차들이 있던 자리 (도착한 뒤에는 차량이 출발 자리로 옮겨지므로 미리 적어 둔다)
	var last := {}
	for i in list.size():
		last[list[i].id] = view.truck_cell(1.0, i, list[i])
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": gap_s}))
	sim.step_ticks(1)
	assert_eq(float(res.arriving[0].start.y), row, "현장 차량도 그 차로에서 출발한다")
	assert_true((res.arriving[0].start as Vector2).is_equal_approx(last[list[0].id]), "맨 앞차: 도시의 차가 멈춘 자리 = 현장 차량이 출발하는 자리")
	var fol := view.followers()
	assert_eq(fol.size(), list.size() - 1, "아직 들어오지 않은 뒤차")
	for f in fol:
		var v: Vehicle = f.vehicle
		assert_true((f.pos as Vector2).distance_to(last[v.id]) < v.speed_cells * 0.35, "%s: 도착 직후 자리가 이어진다 (%.1f칸 차이)" % [v.short_name, (f.pos as Vector2).distance_to(last[v.id])])
	var second: Dictionary = res.arriving[1]
	sim.step_ticks(int(second.start_tick) - sim.clock.tick - 1)
	fol = view.followers()
	assert_true(not fol.is_empty() and (fol[0].pos as Vector2).distance_to(second.start) < list[1].speed_cells * 0.35 and float(fol[0].remain) < 2.0, "들어올 자리에 거의 닿았다")
	sim.step_ticks(2)
	assert_true(bool(second.started) and view.followers().size() == list.size() - 2, "닿으면 시뮬레이션 차량이 이어받는다")
	assert_true(sim.units.get_vehicle(int(second.vehicle)).pos.distance_to(second.start) < 2.0, "같은 자리에서 달려 들어온다")
	view.free()
