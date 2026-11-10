extends TestSuite
## M7b-1: 인접 건물 연소 확대·경계관창·바람 (SOP 214-2.4), 가스 차단 (214-2.2), 붕괴 징후 (205-3.5, 214-2.5), 후착대 명령칸

const KITCHEN_SCENARIO := "res://data/scenarios/sop214_3_kitchen_lpg.json"


## 원천 구획을 최성기로 만들고 개구부를 연다 (화재 계산 없이 ExposureSystem만 돌린다)
func _heat(sim: SimWorld) -> ExposureSystem.Pair:
	var ex := sim.exposure
	var p: ExposureSystem.Pair = ex.pairs[0]
	var src := ex._room(p.source)
	src.stage = Compartment.Stage.FULLY_DEVELOPED
	src.q = 20000.0
	p.source.is_open = true
	return p


func _run_exposure(sim: SimWorld, seconds: int) -> void:
	for i in seconds:
		sim.exposure.step(1.0, i * 10)


func _place(sim: SimWorld, crew_id: int, at: Vector2, level := 1) -> Crew:
	var c := sim.units.get_crew(crew_id)
	for i in c.members().size():
		var ff := c.members()[i]
		ff.path.clear()
		ff.level = level
		ff.pos = at + Vector2(i * 0.5, 0)
		ff.prev_pos = ff.pos
	return c


func test_structures_and_footprint() -> void:
	var sim := make_sim()
	var b := sim.building
	assert_eq(b.structures.size(), 2, "화재 건물 + 옆집")
	assert_eq(b.footprint(1), Rect2i(8, 3, 24, 18), "건물 외곽(둘러보기 기준)은 화재 건물 그대로")
	assert_true(b.is_exposure(40, 12) and not b.is_exposure(15, 10), "옆집 칸 판정")
	assert_true(sim.exposure.has_exposure(), "마주 보는 창 짝이 있음 (%d)" % sim.exposure.pairs.size())


func test_exposure_ignites_without_cover() -> void:
	var sim := make_sim()
	var p := _heat(sim)
	_run_exposure(sim, 600)
	assert_true(not sim.events.of_type("exposure_heating").is_empty(), "가열 징후 알림")
	assert_true(not sim.events.of_type("exposure_ignition").is_empty(), "경계관창이 없으면 옆집으로 연소 확대")
	assert_true(p.target.broken, "옆집 창 파손")
	var room := sim.exposure._room(p.target)
	var lit := false
	for cell in room.cells:
		lit = lit or sim.fire.grid.state[sim.fire.grid.index(room.level, cell.x, cell.y)] == FuelGrid.State.BURNING
	assert_true(lit, "옆집 실내 착화")
	assert_true(sim.fire.is_exposure_comp(sim.exposure._room(p.target)), "옆집 구획 판정")


func test_cover_nozzle_prevents_ignition() -> void:
	var sim := make_sim()
	var p := _heat(sim)
	var h := HoseLine.new()
	h.flowing = true
	var c := p.target.cells[0]
	h.target = Vector3i(c.x, c.y, p.target.level)
	sim.water.hoses.append(h)
	_run_exposure(sim, 600)
	# 같은 원천 개구부가 다른 창도 데우므로, 경계관창이 겨냥한 창만 본다
	sim.water.hoses.clear()
	assert_true(not sim.exposure.ignited.has(p.target.index), "경계관창이 겨냥한 창에는 불이 옮겨 붙지 않음")
	assert_true(sim.exposure.dose.get(p.target.index, 0.0) < 1.0, "그 창의 가열량이 쌓이지 않음")


func test_wind_factor() -> void:
	var sim := make_sim()
	var ex := sim.exposure
	ex.apply_scenario({"wind": {"from_deg": 270, "speed_mps": 4}})  # 서풍: 동쪽 옆집이 풍하
	var down := ex.pairs[0].wind
	ex.apply_scenario({"wind": {"from_deg": 90, "speed_mps": 4}})  # 동풍: 옆집이 풍상
	var up := ex.pairs[0].wind
	ex.apply_scenario({})
	assert_true(down > 1.0 and up < 1.0, "풍하는 강해지고 풍상은 약해짐 (%.2f / %.2f)" % [down, up])
	assert_eq(ex.pairs[0].wind, 1.0, "바람 없으면 1")


func test_gas_shutoff() -> void:
	var sim := SimWorld.from_scenario(KITCHEN_SCENARIO)
	sim.command.resources.clear_schedule()
	var g := sim.gas
	assert_true(g.has_gas() and g.open, "③ 시나리오 LPG 밸브 열림")
	assert_true(not g.known(sim.command.survey), "처음에는 모름 (C면·진술로 확인)")
	_place(sim, 0, Vector2(g.valve) + Vector2(1.5, 0.5))
	assert_true(g.order_off(0, sim.clock.tick), "차단 명령")
	sim.step_ticks(roundi(40.0 / SimClock.TICK_DT))
	assert_true(not g.open, "밸브 차단됨")
	assert_eq(sim.events.of_type("gas_shutoff").size(), 1, "차단 기록")


func test_gas_explosion_when_open() -> void:
	var sim := SimWorld.from_scenario(KITCHEN_SCENARIO)
	var g := sim.gas
	var comp := sim.fire.comps[g.room]
	comp.ever_burned = true
	comp.flashed = true
	g.step(0.1, 1)
	assert_true(g.exploded, "밸브가 열린 채 플래시오버 → 가스 폭발")
	assert_eq(sim.events.of_type("gas_explosion").size(), 1, "폭발 기록")


func test_collapse_sign_and_collapse() -> void:
	var sim := make_sim()
	var col := sim.collapse
	assert_true(col.enabled, "벽돌조 주택은 붕괴 판정")
	var comp := sim.fire.compartment_at(1, 15, 12)
	comp.stage = Compartment.Stage.FULLY_DEVELOPED
	var crew := _place(sim, 0, Vector2(comp.rect.get_center()) + Vector2(0.5, 0.5))
	for i in 610:
		col.step(1.0, i * 10)
	assert_true(col.first_sign_tick() >= 0, "붕괴 징후 먼저")
	assert_true(col.first_sign_tick() < sim.events.of_type("collapse")[0].tick, "징후 → 붕괴 순서")
	assert_true(crew.leader.incapacitated, "붕괴 구획 안 대원 행동 불능")


func test_late_squad_card_and_rules() -> void:
	# 출동대별 명령칸은 명령 카드 하나로 합쳤다 (P10-2): 포위 진압·경계관창·교차 탐색·방수포·승강기는 팀 카드 안에 있다
	# 방수포는 차량 카드, 비상용승강기는 승강장 앞 우클릭 (P10-2 결정 ②)
	var card := CommandCard.new()
	for id in ["attack", "exterior", "search_auto", "withdraw"]:
		assert_true(id in card.all_ids("team"), "팀 명령 카드에 %s" % id)
	assert_true("vehicle_monitor" in card.all_ids("vehicle"), "차량 카드에 방수포")
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	assert_eq(sim.units.squads[0].arrival, "선착", "처음부터 현장 = 선착")
	var n := sim.units.squads.size()
	for i in 600:
		sim.step_ticks(10)
		if sim.units.squads.size() > n:
			break
	assert_true(sim.units.squads.size() > n, "후착대 도착")
	assert_eq(sim.units.squads[-1].arrival, "후착", "나중에 도착한 출동대 = 후착")
	var rules: Dictionary = JsonData.load_file(Evaluator.RULES_PATH)
	var have: Array = []
	for r: Dictionary in rules.rules:
		have.append(r.id)
	for id in ["property.exposure", "property.gas", "safety.collapse"]:
		assert_true(id in have, "규칙 %s" % id)
