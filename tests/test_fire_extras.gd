extends TestSuite
## P3-1 보강: 비화·굴뚝효과·수직 연기 속도·열 균형 파괴·연기 독성·재발화 가속·잔화정리 수손·순서 (기획안 5-2-2·5-3·5-9)

const APT15 := "res://data/scenarios/sop213_3_15f_day_low.json"


func _house() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.doors.sync_blocking()
	return sim


func _room(sim: SimWorld, name: String) -> Compartment:
	for c in sim.fire.comps:
		if c.display_name() == name:
			return c
	return null


func test_firebrands_only_in_strong_wind() -> void:
	for wind in [3.0, 9.0]:
		var sim := _house()
		# 인접 건물 쪽으로 부는 바람 방향을 고른다 (풍하측)
		var best_deg := 0.0
		var best := -1.0
		for deg in [0.0, 90.0, 180.0, 270.0]:
			sim.exposure.apply_scenario({"wind": {"from_deg": deg, "speed_mps": wind}})
			for pr in sim.exposure.pairs:
				if not pr.vertical and pr.wind > best:
					best = pr.wind
					best_deg = deg
		sim.exposure.apply_scenario({"wind": {"from_deg": best_deg, "speed_mps": wind}})
		sim.exposure._brand_chance = 30.0  # 확률을 크게 해 결과를 빨리 본다
		# 인접 건물 쪽 창이 있는 2층 방4가 최성기가 되는 30분까지 본다
		sim.step_ticks(roundi(1800.0 / SimClock.TICK_DT))
		var n := sim.events.of_type("firebrand_ignition").size()
		if wind < 5.0:
			assert_eq(n, 0, "풍속 %.0fm/s(5 미만)에서는 비화 없음" % wind)
		else:
			assert_true(n >= 1, "풍속 %.0fm/s에서는 풍하측 인접 건물에 비화 (%d건)" % [wind, n])


func test_stack_effect_by_season() -> void:
	var sim := SimWorld.from_scenario(APT15, false)
	sim.fire.apply_season("겨울")
	var winter := sim.fire.model.stack_factor
	sim.fire.apply_season("여름")
	var summer := sim.fire.model.stack_factor
	sim.fire.apply_season("")
	assert_true(winter > 1.5, "겨울 15층: 굴뚝효과로 상승 기류 강함 (×%.2f)" % winter)
	assert_true(summer < 1.0 and summer >= 0.3, "여름: 약해짐 (×%.2f)" % summer)
	assert_eq(sim.fire.model.stack_factor, 1.0, "계절 없음 = 1")


func test_stair_smoke_rises_fast_and_fills_from_top() -> void:
	# 교재: 수직 2~3m/s, 계단 초기 약 1.5m/s → 중기 3~4m/s (화재2 330쪽), 계단실은 위층부터 찬다 (SOP 223 1.3)
	var sim := SimWorld.from_scenario(APT15, false)
	var stair := {}
	for c in sim.fire.comps:
		if c.display_name().contains("계단실"):
			stair[c.level] = c
	var arrive := {}
	var filled := {}
	for k in 9000:
		sim.step_ticks(1)
		for lv: int in stair:
			var c: Compartment = stair[lv]
			if not arrive.has(lv) and c.layer_depth > 0.02:
				arrive[lv] = sim.clock.tick * SimClock.TICK_DT
			if not filled.has(lv) and c.layer_depth > 0.3:
				filled[lv] = sim.clock.tick * SimClock.TICK_DT
		if filled.has(12):
			break
	assert_true(arrive.has(5) and arrive.has(14), "연기가 계단으로 올라감")
	var speed := (14 - 5) * 2.8 / maxf(0.1, float(arrive[14]) - float(arrive[5]))
	assert_true(speed >= 1.0 and speed <= 6.0, "계단 연기 선두 속도 %.1fm/s (교재 1.5~4, 굴뚝효과 5 이상)" % speed)
	assert_true(filled.has(15) and filled.has(14) and filled[15] < filled[14], "꼭대기(15층) 계단부터 찬다 (15층 %.0f초 / 14층 %s)" % [filled.get(15, -1.0), filled.get(14, "-")])


func test_fog_without_vent_brings_heat_down() -> void:
	# 배기구 없는 방 상부층에 분무 → 수증기로 열 균형이 깨져 뜨거운 가스가 내려온다 (화재1 34쪽)
	var sim := _house()  # 옆문(복도 출입문)만 열어 수관이 들어갈 길을 낸다 — 거실 자체의 배기구는 아님
	var living := _room(sim, "1층 거실")
	# 창이 열에 깨지지 않게 막아 배기구 없는 방으로 둔다
	for oi in living.openings:
		var o: Opening = sim.fire.openings[oi]
		if o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE:
			o.is_open = false
			o.breakable = false
	sim.step_ticks(roundi(300.0 / SimClock.TICK_DT))
	assert_true(not sim.water._vented(living), "거실에 바깥으로 열린 창·문 없음")
	var crew := sim.units.get_crew(0)
	crew.leader.pos = Vector2(17.5, 13.5)
	crew.partner.pos = Vector2(18.5, 13.5)
	var depth0 := living.layer_depth
	sim.issue(EquipmentCommand.make("hose", [0] as Array[int], 0))
	sim.issue(EquipmentCommand.make("spray", [0] as Array[int], -1, HoseLine.Pattern.FOG, Vector3i(12, 16, 1)))
	var deepest := depth0
	var hot_when_hit := 0.0
	for k in 600:
		sim.step_ticks(1)
		deepest = maxf(deepest, living.layer_depth)
		if sim.events.of_type("steam_mix").size() >= 1 and hot_when_hit == 0.0:
			hot_when_hit = living.t_upper
	assert_true(sim.events.of_type("steam_mix").size() >= 1, "수증기 열기 경고 무전")
	assert_true(deepest > depth0 + 0.2, "분무하는 동안 뜨거운 연기층이 바닥 쪽으로 내려옴 (%.2f → 최대 %.2fm)" % [depth0, deepest])


func test_smoke_toxicity_from_materials() -> void:
	var sim := _house()
	sim.step_ticks(roundi(240.0 / SimClock.TICK_DT))
	var living := _room(sim, "1층 거실")
	assert_true(living.toxicity >= 1.5, "우레탄 소파가 타면 연기 독성 증가 (×%.1f, 화재2 표 4-12)" % living.toxicity)
	sim.step_ticks(roundi(240.0 / SimClock.TICK_DT))
	var hall := _room(sim, "1층 복도")
	assert_true(hall.toxicity >= 1.5, "독성 연기가 복도로 옮겨 감 (×%.1f)" % hall.toxicity)


func test_rekindle_faster_with_ventilation_and_overhaul_water() -> void:
	var sim := _house()
	var rk := sim.rekindle
	var living := _room(sim, "1층 거실")
	var cell := living.cells[0]
	var i := sim.fire.grid.index(1, cell.x, cell.y)
	rk._add_ember(i, 0)
	var e = rk.embers[0]
	var t0: int = e.rekindle_tick
	# 거실 창을 열어 산소가 들어오게 한다
	for oi in living.openings:
		var o: Opening = sim.fire.openings[oi]
		if o.room_b == Opening.OUTSIDE or o.room_a == Opening.OUTSIDE:
			o.is_open = true
	sim.step_ticks(100)
	assert_true(e.rekindle_tick < t0 - 50, "환기되는 방은 재발화가 빨라짐 (%d → %d틱)" % [t0, e.rekindle_tick])
	# 잔불정리 물은 수손으로 들어간다
	var dmg := living.water_damage_l
	var crew := sim.units.get_crew(0)
	crew.leader.pos = Vector2(cell) + Vector2(0.5, 0.5)
	crew.leader.prev_pos = crew.leader.pos
	assert_true(rk.order_overhaul(0, Vector3i(cell.x, cell.y, 1), sim.clock.tick), "잔불정리 지시")
	sim.step_ticks(roundi((rk.overhaul_seconds() + 5.0) / SimClock.TICK_DT))
	assert_true(living.water_damage_l > dmg, "잔불정리 물 → 수손 (%.0f → %.0fL)" % [dmg, living.water_damage_l])
	assert_eq(rk.overhaul_order.size(), 1, "잔화정리 순서 기록")


func test_pvc_shaft_raises_toxicity() -> void:
	# PVC 배관 샤프트로 위층에 번지면 염화수소로 연기 독성이 커진다 (화재1 제4장 제10절)
	var sim := SimWorld.from_scenario("res://data/scenarios/sop212_1_commercial_kitchen.json", false)
	assert_true(sim.shafts.pvc, "근린상가 PS는 PVC 배관")
	var levels: Array = sim.shafts.shaft_rooms.keys()
	levels.sort()
	var lv: int = levels[1]
	sim.shafts.hot[levels[0]] = 0
	sim.shafts.step(0.1, sim.shafts._rise_ticks + 1)
	var sh: Compartment = sim.shafts.shaft_rooms[lv]
	assert_true(sh.toxicity >= 1.5, "%d층 샤프트 연기 독성 ×%.1f" % [lv, sh.toxicity])
