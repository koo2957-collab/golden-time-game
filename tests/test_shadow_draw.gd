extends TestSuite
## 미리 그려 넣는 그림자·음영 (ShadowDraw — 입체감 1단계, 2026-11-22):
## 건물·차량·가구의 땅 그림자(밀어 낸 사각형), 벽 아래 어두운 띠, 설정값. 화면 없이 도형 계산만 본다.


func test_style_values_have_source() -> void:
	var data: Variant = JsonData.load_file(ShadowDraw.PATH)
	assert_true(data is Dictionary, "설정 파일")
	for key: String in data:
		if key == "note":
			continue
		assert_true(data[key] is Dictionary and data[key].has("value") and str(data[key].get("source", "")) != "", "%s 값과 source" % key)
	for key: String in ["building_alpha", "vehicle_alpha", "furniture_alpha", "contact_alpha", "ao_alpha", "city_alpha"]:
		var a := ShadowDraw.num(key, -1.0)
		assert_true(a > 0.0 and a < 1.0, "%s 는 0과 1 사이 (%.2f) — 그림자 밑의 바닥·호스가 비쳐 보인다" % [key, a])
	assert_true(ShadowDraw.num("ao_shadow_m") > ShadowDraw.num("ao_lit_m"), "그늘지는 쪽 띠가 빛 받는 쪽보다 넓다")
	assert_true(ShadowDraw.num("furniture_max_m") < 0.5, "가구 그림자는 한 칸(0.5m)을 넘지 않는다 — 벽 건너 옆방으로 새지 않는다")


func test_force_turns_shadows_on_and_off() -> void:
	ShadowDraw.force(0)
	assert_true(not ShadowDraw.on(), "억지로 끔")
	ShadowDraw.force(1)
	assert_true(ShadowDraw.on(), "억지로 켬")
	ShadowDraw.force(-1)
	assert_eq(ShadowDraw.on(), bool(ShadowDraw.style().get("enabled", true)), "파일 값으로 되돌림")


func test_color_and_night_scale() -> void:
	var day := ShadowDraw.color("building_alpha", ShadowDraw.sun_scale(0.0))
	var night := ShadowDraw.color("building_alpha", ShadowDraw.sun_scale(1.0))
	assert_true(absf(day.a - ShadowDraw.num("building_alpha")) < 0.001, "낮에는 설정값 그대로")
	assert_true(night.a < day.a and night.a > 0.0, "밤에는 옅게 (%.2f < %.2f)" % [night.a, day.a])
	assert_eq(ShadowDraw.color("building_alpha", 99.0).a, 1.0, "진하기는 1을 넘지 않는다")


## 그림자는 화면에서 빛(호스와 같은 light_dir)의 반대쪽으로 뻗는다
func test_cast_dir_points_away_from_light() -> void:
	var proj := IsoProjection.new()
	var cast := ShadowDraw.cast_dir(proj)
	assert_true(absf(cast.length() - 1.0) < 0.001, "길이 1")
	var l: Variant = HoseDraw.style().get("light_dir", [-0.5, -0.85])
	var light := Vector2(float(l[0]), float(l[1]))
	var on_screen := proj.to_screen(cast) - proj.to_screen(Vector2.ZERO)
	assert_true(on_screen.dot(light) < 0.0, "화면에서 빛 반대쪽")


func test_cast_offset_scales_with_height_and_is_capped() -> void:
	var proj := IsoProjection.new()
	var cell_m := 0.5
	var low := ShadowDraw.cast_offset(proj, 2.0, cell_m)
	var high := ShadowDraw.cast_offset(proj, 4.0, cell_m)
	assert_true(absf(low.length() - 2.0 * ShadowDraw.num("sun_length_ratio") / cell_m) < 0.001, "길이 = 높이 × 비율 (칸)")
	assert_true(absf(high.length() - low.length() * 2.0) < 0.001, "높이가 두 배면 그림자도 두 배")
	var capped := ShadowDraw.cast_offset(proj, 100.0, cell_m, "building_max_m")
	assert_true(absf(capped.length() - ShadowDraw.num("building_max_m") / cell_m) < 0.001, "상한을 넘지 않는다")
	assert_eq(ShadowDraw.cast_offset(proj, -3.0, cell_m), Vector2.ZERO, "높이가 없으면 그림자도 없다")


## 사각형 바닥을 대각선으로 밀면 빛 반대쪽 두 변에서만 사각형이 나오고, 바닥 자리와 겹치지 않는다
func test_sweep_quads_only_on_far_sides() -> void:
	var base := ShadowDraw.rect_points(Rect2(0, 0, 4, 2))
	var quads := ShadowDraw.sweep_quads(base, Vector2(1, 1))
	assert_eq(quads.size(), 2, "동쪽·남쪽 변")
	var area := 0.0
	for q in quads:
		area += _area(q)
		var mid := (q[0] + q[1] + q[2] + q[3]) / 4.0
		assert_true(not Rect2(0, 0, 4, 2).has_point(mid), "바닥 자리 바깥")
	# 민 모양의 넓이 − 바닥 넓이 = 4×1 + 2×1 (겹치지 않으므로 합이 꼭 맞는다)
	assert_true(absf(area - 6.0) < 0.001, "넓이 6 (%.3f) — 사각형끼리 겹치지 않는다" % area)
	assert_eq(ShadowDraw.sweep_quads(base, Vector2(2, 0)).size(), 1, "동쪽으로만 밀면 한 변")
	assert_true(ShadowDraw.sweep_quads(base, Vector2.ZERO).is_empty(), "밀지 않으면 없음")
	assert_true(ShadowDraw.sweep_quads(PackedVector2Array([Vector2.ZERO, Vector2.ONE]), Vector2(1, 1)).is_empty(), "면이 아니면 없음")


## 점 순서가 거꾸로(시계 반대)여도 같은 결과
func test_sweep_quads_ignore_winding() -> void:
	var base := ShadowDraw.rect_points(Rect2(0, 0, 4, 2))
	var back := base.duplicate()
	back.reverse()
	assert_eq(ShadowDraw.sweep_quads(back, Vector2(1, 1)).size(), ShadowDraw.sweep_quads(base, Vector2(1, 1)).size(), "변 수가 같다")


func test_sweep_hull_covers_base_and_shadow() -> void:
	var base := ShadowDraw.rect_points(Rect2(0, 0, 4, 2))
	var hull := ShadowDraw.sweep_hull(base, Vector2(1, 1))
	assert_eq(hull.size(), 6, "육각형 (첫 점을 되풀이하지 않는다)")
	assert_true(absf(_area(hull) - 14.0) < 0.001, "넓이 = 바닥 8 + 그림자 6 (%.3f)" % _area(hull))
	for p in [Vector2(0.1, 0.1), Vector2(4.9, 2.9), Vector2(2, 1)]:
		assert_true(Geometry2D.is_point_in_polygon(p, hull), "%s 포함" % p)
	assert_true(not Geometry2D.is_point_in_polygon(Vector2(4.8, 0.2), hull), "빛 쪽 모서리 바깥은 비어 있다")


## 벽 아래 띠: 그늘지는 쪽은 넓고 진하게, 빛 받는 쪽은 좁고 옅게. 띠를 낸 두 면이 만나는 모서리에는 부채
func test_box_bands_shadow_side_is_wider_and_darker() -> void:
	var cast := Vector2(1, 0)
	var all := ShadowDraw.WEST | ShadowDraw.NORTH | ShadowDraw.EAST | ShadowDraw.SOUTH
	var list := ShadowDraw.box_bands(Rect2(2, 3, 1, 1), all, cast, 0.9, 0.4, 0.5, 0.4)
	var bands := list.filter(func(d: Dictionary) -> bool: return not d.has("fan"))
	var fans := list.filter(func(d: Dictionary) -> bool: return d.has("fan"))
	assert_eq(bands.size(), 4, "네 면")
	assert_eq(fans.size(), 4, "네 모서리")
	var by_side := {}
	for d: Dictionary in bands:
		by_side[int(d.side)] = d
	assert_true(absf(float(by_side[2].w) - 0.9) < 0.001 and absf(float(by_side[2].alpha) - 0.5) < 0.001, "동쪽(그늘) 띠: 넓고 진하다")
	assert_true(absf(float(by_side[0].w) - 0.4) < 0.001 and absf(float(by_side[0].alpha) - 0.2) < 0.001, "서쪽(빛) 띠: 좁고 옅다")
	assert_eq(float(by_side[2].at), 3.0, "동쪽 면의 자리")
	assert_eq(float(by_side[1].at), 3.0, "북쪽 면의 자리")
	# 한쪽 면만: 띠 하나, 부채 없음
	var one := ShadowDraw.box_bands(Rect2(2, 3, 1, 1), ShadowDraw.EAST, cast, 0.9, 0.4, 0.5, 0.4)
	assert_eq(one.size(), 1, "한 면만")
	# 마주 보는 두 면: 만나는 모서리가 없다
	var two := ShadowDraw.box_bands(Rect2(2, 3, 1, 1), ShadowDraw.WEST | ShadowDraw.EAST, cast, 0.9, 0.4, 0.5, 0.4)
	assert_eq(two.size(), 2, "마주 보는 두 면 — 부채 없음")
	assert_true(ShadowDraw.box_bands(Rect2(2, 3, 1, 1), 0, cast, 0.9, 0.4, 0.5, 0.4).is_empty(), "면이 없으면 없음")


## 띠 사각형: 앞의 두 점은 벽에 붙고(진함), 뒤의 두 점은 폭만큼 바깥(투명)
func test_band_quad_goes_outward() -> void:
	var list := ShadowDraw.box_bands(Rect2(2, 3, 1, 1), ShadowDraw.EAST | ShadowDraw.NORTH, Vector2(1, 0), 0.9, 0.4, 0.5, 0.4)
	for d: Dictionary in list:
		if d.has("fan"):
			var fan: PackedVector2Array = d.fan
			assert_eq(fan[0], Vector2(3, 3), "부채의 첫 점은 북동 모서리")
			assert_true(not Rect2(2, 3, 1, 1).has_point(fan[2]), "대각선 끝은 상자 바깥")
			continue
		var q := ShadowDraw.band_quad(d)
		if int(d.side) == 2:
			assert_eq(q[0], Vector2(3, 3), "동쪽 띠 벽 쪽 시작")
			assert_eq(q[1], Vector2(3, 4), "동쪽 띠 벽 쪽 끝")
			assert_true(absf(q[2].x - 3.9) < 0.001 and absf(q[3].x - 3.9) < 0.001, "동쪽으로 폭만큼")
		else:
			assert_eq(q[0], Vector2(2, 3), "북쪽 띠 벽 쪽 시작")
			assert_true(absf(q[2].y - 2.6) < 0.001, "북쪽으로 폭만큼")


## 한 줄로 이어진 벽 칸들의 띠는 하나로 합친다 (그리는 양을 줄인다). 떨어져 있으면 따로
func test_merge_bands_joins_a_straight_wall() -> void:
	var cast := Vector2(0, 1)
	var list: Array[Dictionary] = []
	for x in 5:
		list.append_array(ShadowDraw.box_bands(Rect2(x, 0, 1, 1), ShadowDraw.SOUTH, cast, 0.9, 0.4, 0.5, 0.4))
	list.append_array(ShadowDraw.box_bands(Rect2(8, 0, 1, 1), ShadowDraw.SOUTH, cast, 0.9, 0.4, 0.5, 0.4))
	var merged := ShadowDraw.merge_bands(list)
	assert_eq(merged.size(), 2, "이어진 다섯 칸 = 하나, 떨어진 한 칸 = 하나")
	var long: Dictionary = merged[0] if float(merged[0].a) < float(merged[1].a) else merged[1]
	assert_eq(float(long.a), 0.0, "긴 띠 시작")
	assert_eq(float(long.b), 5.0, "긴 띠 끝")
	# 부채는 그대로 남는다
	var corner := ShadowDraw.box_bands(Rect2(0, 0, 1, 1), ShadowDraw.SOUTH | ShadowDraw.EAST, Vector2(1, 1).normalized(), 0.9, 0.4, 0.5, 0.4)
	assert_eq(ShadowDraw.merge_bands(corner).filter(func(d: Dictionary) -> bool: return d.has("fan")).size(), 1, "부채는 합치지 않는다")


## 배경 도시: 그림자를 켜면 한 번 만들어 두는 그림에 사각형이 더 들어가고, 끄면 예전과 같다 (저사양 모드에서는 넣지 않는다)
func test_city_mesh_gets_shadows_only_when_on() -> void:
	var sim := make_sim()
	var was := DisplaySettings.low_spec
	DisplaySettings.low_spec = false
	var off := _city_quads(sim, 0)
	var on := _city_quads(sim, 1)
	assert_true(on > off, "켜면 그림자 사각형이 더 들어간다 (%d > %d)" % [on, off])
	assert_true(on - off <= 2 * _city_lots(sim), "건물 하나에 사각형 둘까지 (%d개 더)" % (on - off))
	DisplaySettings.low_spec = true
	assert_eq(_city_quads(sim, 1), _city_quads(sim, 0), "저사양 모드에서는 그림자를 넣지 않는다")
	DisplaySettings.low_spec = was
	ShadowDraw.force(-1)


func _area(pts: PackedVector2Array) -> float:
	var sum := 0.0
	for k in pts.size():
		sum += pts[k].cross(pts[(k + 1) % pts.size()])
	return absf(sum) * 0.5


## 그림자를 끄고(0) 켜고(1) 만든 도시 그림의 사각형 수
func _city_quads(sim: SimWorld, state: int) -> int:
	ShadowDraw.force(state)
	var view := CityMassView.new()
	view.setup(sim.building, IsoProjection.new(), 3, sim)
	var count := view.quad_count
	view.free()
	return count


func _city_lots(sim: SimWorld) -> int:
	var view := CityMassView.new()
	view.setup(sim.building, IsoProjection.new(), 3, sim)
	var count := view.plan.lots.size()
	view.free()
	return count
