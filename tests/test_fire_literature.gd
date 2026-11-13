extends TestSuite
## 문헌 대조 (2026-11-13, docs/fire_model_basis.md): 화재·연기·방수 수치가 연구 자료 범위 안에 있는지 확인한다.
## 수치를 고쳐서 범위를 벗어나면 이 테스트가 알려 준다. 범위는 문헌 값에 여유를 둔 것 — 고칠 때는 문헌을 먼저 확인할 것.
##   화재하중: Eurocode EN 1991-1-2 표 E.4 (주택 평균 780, 80% 분위 948 MJ/㎡)
##   성장·최대 열방출률: Eurocode 주택 '보통'(1MW 300초)~'빠름'(150초), Kerber 2012 (플래시오버 3:20~4:45, 방 최대 7.5MW), 교재 목조 5~6분
##   연기 CO·바닥 비율·노출량 기준: UL 2010 환기 실험, UL FSRI 2018 Fire Attack Part III
##   필요 방수량: Barnett TP 2004/1 (0.38 L/s/MW), Grimwood (2 L/min/㎡ 미만 위험)

const HOUSE := "res://data/scenarios/tutorial_basics.json"


func _burn(sim: SimWorld, seconds: float) -> void:
	for i in roundi(seconds / SimClock.TICK_DT):
		sim.fire.step(SimClock.TICK_DT, 0)


func _origin(sim: SimWorld) -> Compartment:
	var best: Compartment = null
	for c in sim.fire.comps:
		if c.ever_burned and (best == null or c.q > best.q):
			best = c
	return best


func test_fire_load_matches_eurocode_dwelling() -> void:
	var sim := SimWorld.from_scenario(HOUSE, false)
	var area := 0.0
	var mj := 0.0
	for c in sim.fire.comps:
		area += c.area
		mj += c.fuel_initial
	var density := mj / area
	assert_eq(sim.building.occupancy, "주택", "건물 용도")
	assert_true(density >= 700.0 and density <= 950.0, "주택 화재하중 %.0f MJ/㎡ (Eurocode 평균 780, 80%% 분위 948)" % density)
	assert_true(sim.fire.grid.fire_load_scale > 1.0, "생활용품을 더해 맞춤 (배율 %.1f)" % sim.fire.grid.fire_load_scale)
	# 용도가 없는 건물은 맞추지 않는다
	var tower := SimWorld.create("res://data/buildings/training_tower.json", ROSTER_PATH)
	assert_eq(tower.fire.grid.fire_load_scale, 1.0, "용도가 없으면 그대로")


func test_growth_and_peak_within_literature() -> void:
	var sim := SimWorld.from_scenario(HOUSE, false)
	var t_1mw := -1.0
	var t_flash := -1.0
	var peak := 0.0
	var room: Compartment = null
	for s in 60:
		_burn(sim, 10.0)
		room = _origin(sim)
		if room == null:
			continue
		var t := (s + 1) * 10.0
		if t_1mw < 0.0 and room.q >= 1000.0:
			t_1mw = t
		if t_flash < 0.0 and room.flashed:
			t_flash = t
		peak = maxf(peak, room.q)
	assert_true(t_1mw >= 150.0 and t_1mw <= 300.0, "1MW 도달 %d초 (Eurocode 빠름 150 ~ 보통 300초)" % int(t_1mw))
	assert_true(t_flash >= 200.0 and t_flash <= 480.0, "플래시오버 %d초 (현대 가구 실험 200초 ~ 교재 목조 5~6분에 여유)" % int(t_flash))
	assert_true(peak >= 4000.0 and peak <= 9000.0, "방 하나 최대 열방출률 %.1fMW (Kerber 실험 7.5MW)" % (peak / 1000.0))
	assert_true(peak <= room.q_max * 1.05 + 1.0, "환기 상한(1,500 × A√H)을 넘지 않는다")
	# 화재하중이 실제 수준이면 방이 금방 다 타지 않는다: 플래시오버 15분 뒤에도 최성기
	_burn(sim, 900.0)
	assert_true(room.q >= peak * 0.6, "플래시오버 뒤 15분에도 계속 탄다 (%.1fMW) — 예전에는 연료가 1/5이라 스스로 꺼졌다" % (room.q / 1000.0))


func test_smoke_co_within_ul_experiments() -> void:
	var sim := SimWorld.from_scenario(HOUSE, false)
	var hz := ParamTable.from_dict(JsonData.load_file("res://data/fire/hazard_params.json"))
	var ratio: float = hz.value("lower_layer_exposure_ratio")
	assert_true(ratio >= 0.33 and ratio <= 0.45, "바닥 30cm / 1m 높이 CO 비 %.2f (UL 2018: 0.33~0.45)" % ratio)
	assert_eq([hz.value("fed_unconscious"), hz.value("fed_death")], [1.0, 3.0], "노출량 1 = 의식 잃음, 3 = 사망 가능 (UL 2018)")
	var v: Victim = sim.rescue.victims[0]
	var room := sim.fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
	var peak_ppm := 0.0
	for s in 60:
		_burn(sim, 10.0)
		var conc := room.soot / maxf(room.layer_volume(), 0.05 * room.volume)
		peak_ppm = maxf(peak_ppm, conc * hz.value("co_per_soot") / 1.145 * 1e6)
	assert_true(peak_ppm >= 8000.0 and peak_ppm <= 45000.0, "문 열린 옆방 연기층 CO 최대 %dppm (UL: 1%% 이상 ~ 4.2%%)" % roundi(peak_ppm))


func test_required_flow_follows_heat_release() -> void:
	var sim := SimWorld.from_scenario(HOUSE, false)
	_burn(sim, 540.0)
	var room := _origin(sim)
	assert_true(room.flashed, "최성기 방")
	sim.water._update_flow_ratio(0)
	var want := 0.38 * 60.0 * room.q / 1000.0
	assert_true(absf(room.required_lpm - want * room.load_factor) < 1.0, "필요 방수량 %.0f L/분 = 0.38 L/s × %.1fMW (Barnett)" % [room.required_lpm, room.q / 1000.0])
	assert_true(room.required_lpm >= 100.0 and room.required_lpm <= 250.0, "최성기 방 하나 100~250 L/분")
	var nozzle := 0.0
	for veh in sim.units.vehicles:
		nozzle = maxf(nozzle, veh.nozzle_lpm)
	assert_true(nozzle >= 200.0 and nozzle <= 350.0, "40mm 관창 %d L/분 (영국 평균 290, 200 미만은 위험 — Grimwood)" % roundi(nozzle))
	assert_true(nozzle >= room.required_lpm, "관창 하나로 최성기 방 하나를 잡을 수 있다")
	# 타는 면적당 2 L/분 아래로는 내려가지 않는다 (Grimwood 위험선)
	assert_true(room.required_lpm >= 2.0 * room.burning_area_m2, "하한 2 L/분/㎡")
