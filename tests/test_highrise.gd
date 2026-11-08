extends TestSuite
## R10: 스테이지 2-1 — 15층 아파트, 옥내소화전(SOP 235), 출동 준비(적재 장비), 늦은 신고(미리 탄 불)

const A := "res://data/scenarios/sop213_3_15f_day_low.json"
const B := "res://data/scenarios/sop213_4_15f_night_mid.json"
const C := "res://data/scenarios/sop213_5_15f_winter_high.json"


func test_three_scenarios_load() -> void:
	for p in [A, B, C]:
		var sim := SimWorld.from_scenario(p)
		assert_true(sim != null, "%s 불러옴" % p)
		if sim == null:
			continue
		assert_eq(sim.building.levels().size(), 15, "15층")
		assert_true(sim.building.indoor_lpm > 0.0 and sim.water.indoor_tank_l > 0.0, "옥내소화전")
		var errors := ScenarioLoader.validate(p)
		assert_eq(errors, PackedStringArray(), "시나리오 검증 (%s)" % p)


func test_step_speed_15_floors() -> void:
	var sim := SimWorld.from_scenario(A)
	sim.step_ticks(10)
	var t0 := Time.get_ticks_usec()
	sim.step_ticks(100)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 100.0
	print("    15층 1틱 평균 %.1fms" % ms)
	assert_true(ms < 100.0, "15층도 10Hz로 돌 수 있다 (1틱 %.1fms)" % ms)


func test_indoor_hydrant_without_fdc() -> void:
	var sim := SimWorld.from_scenario(A)
	sim.command.resources.clear_schedule()
	var c := sim.units.get_crew(0)
	var o: Vector3i = sim.building.outlets[2]  # 3층 방수구
	for i in c.members().size():
		c.members()[i].pos = Vector2(o.x + 0.5, o.y - 1.5 + i)
		c.members()[i].prev_pos = c.members()[i].pos
		c.members()[i].level = o.z
		c.members()[i].prev_level = o.z
	assert_eq(sim.water.fdc_vehicle, -1, "송수구 미연결")
	assert_true(sim.water.lay_hose_outlet(0, 2, 0), "옥내소화전에서 수관 연장")
	var h := sim.water.hose_of_crew(0)
	assert_eq(h.vehicle_id, WaterSystem.INDOOR, "건물 수조 물")
	var before := sim.water.indoor_tank_l
	sim.water.start_spray(0, Vector3i(o.x, o.y - 3, o.z), HoseLine.Pattern.FOG, 0)
	sim.step_ticks(50)
	assert_true(sim.water.indoor_tank_l < before, "수조가 줄어든다 (%.0f → %.0f)" % [before, sim.water.indoor_tank_l])
	# 송수구가 연결되면 그 펌프차 물로 옮겨 탄다
	sim.water.fdc_vehicle = 0
	sim.step_ticks(2)
	assert_eq(h.vehicle_id, 0, "송수구 연결 뒤에는 펌프차 물")


func test_indoor_tank_runs_out() -> void:
	var sim := SimWorld.from_scenario(A)
	sim.water.indoor_tank_l = 1.0
	var c := sim.units.get_crew(0)
	var o: Vector3i = sim.building.outlets[2]
	for i in c.members().size():
		c.members()[i].pos = Vector2(o.x + 0.5, o.y - 1.5 + i)
		c.members()[i].prev_pos = c.members()[i].pos
		c.members()[i].level = o.z
		c.members()[i].prev_level = o.z
	sim.water.lay_hose_outlet(0, 2, 0)
	sim.water.start_spray(0, Vector3i(o.x, o.y - 3, o.z), HoseLine.Pattern.FOG, 0)
	sim.step_ticks(30)
	assert_eq(sim.events.of_type("indoor_hydrant_empty").size(), 1, "수조 소진 보고 → 송수구 연결 필요")


func test_preburn() -> void:
	var sim := SimWorld.from_scenario(B)
	var room := sim.fire.compartment_at(8, 20, 7)
	assert_true(room.t_upper > 60.0, "늦게 신고: 도착 때 이미 뜨겁다 (%.0f℃)" % room.t_upper)
	assert_true(room.y_o2 < Compartment.O2_AMBIENT_MASS * 0.9, "닫힌 방이라 산소가 줄었다 — 백드래프트 조건 (%.3f)" % room.y_o2)
	assert_eq(sim.clock.tick, 0, "시계는 0에서 시작")


func test_loadout() -> void:
	var sim := SimWorld.from_scenario(A)
	var thermal := sim.units.crews.filter(func(c: Crew) -> bool: return c.thermal_camera).size()
	var hose := sim.building.outlet_hose_m
	sim.issue(CommandOrder.make("loadout", [], 0, Vector3i.ZERO, {"items": ["thermal_extra", "fire_door_breaker", "high_rise_pack", "spare_cylinders"]}))
	sim.step_ticks(1)
	assert_eq(sim.loadout.size(), 3, "최대 3개")
	assert_eq(sim.units.crews.filter(func(c: Crew) -> bool: return c.thermal_camera).size(), thermal + 1, "열화상카메라 +1")
	assert_eq(sim.doors.fire_door_factor_scale, 0.5, "방화문 파괴기")
	assert_eq(sim.building.outlet_hose_m, hose + 15.0, "고층 호스팩")
	assert_eq(sim.conditions.swap_scale, 1.0, "4번째는 싣지 못함")
	assert_eq(sim.events.of_type("loadout").size(), 1, "기록")
	sim.issue(CommandOrder.make("loadout", [], 0, Vector3i.ZERO, {"items": ["air_mat"]}))
	sim.step_ticks(1)
	assert_eq(sim.loadout.size(), 3, "한 번만 정한다")
