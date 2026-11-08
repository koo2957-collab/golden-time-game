extends TestSuite
## R14: 기획안 4장 나머지 스테이지 — 0 훈련탑, 1-2 필로티, 3-1 전통시장, 3-2 지하층, 3-3 물류창고, 4-1 초고층

const STAGES := {
	"0": "res://data/scenarios/stage0_training_tower.json",
	"1-2": "res://data/scenarios/stage1_2_piloti.json",
	"3-1": "res://data/scenarios/stage3_1_market.json",
	"3-2": "res://data/scenarios/stage3_2_basement.json",
	"3-3": "res://data/scenarios/stage3_3_warehouse.json",
	"4-1": "res://data/scenarios/stage4_1_supertall.json",
}


func test_all_stages_load_and_run() -> void:
	for stage: String in STAGES:
		var p: String = STAGES[stage]
		assert_eq(ScenarioLoader.validate(p), PackedStringArray(), "%s 검증" % stage)
		var sim := SimWorld.from_scenario(p)
		assert_true(sim != null, "%s 불러옴" % stage)
		if sim == null:
			continue
		sim.step_ticks(100)
		assert_true(not sim.fire.grid.burning.is_empty(), "%s 불이 탄다" % stage)
		assert_eq(str(sim.scenario.meta.stage), stage, "스테이지 표시")


func test_stage_cards_only_in_their_stage() -> void:
	var sim := SimWorld.from_scenario(STAGES["3-3"])
	sim.events.add(1, "phase", {"index": 1, "name": "도착"})
	sim.step_ticks(2)
	var asked := sim.cards.queue.map(func(q: CardSystem.Card) -> String: return q.id)
	assert_true("WAREHOUSE-01" in asked, "창고 스테이지에서 진입 판단 카드 (%s)" % [asked])
	assert_true(not "PILOTI-01" in asked, "다른 스테이지 카드는 묻지 않는다")
	var house := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	house.events.add(1, "phase", {"index": 1, "name": "도착"})
	house.step_ticks(2)
	assert_true(not house.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.spec.has("stages")), "일반 시나리오에는 스테이지 카드가 없다")


func test_piloti_facade_speeds_vertical_spread() -> void:
	var sim := SimWorld.from_scenario(STAGES["1-2"])
	assert_eq(sim.building.facade_factor, 2.5, "가연성 외장재 배율")
	assert_true(sim.exposure.pairs.any(func(p) -> bool: return p.vertical), "필로티 → 위층 창 수직 확대 쌍")


func test_warehouse_panel_collapse_enabled() -> void:
	var sim := SimWorld.from_scenario(STAGES["3-3"])
	assert_true(sim.collapse.enabled, "샌드위치패널 붕괴")
	var room := sim.fire.compartment_at(1, 36, 10)
	assert_true(room.t_upper > 60.0, "도착 때 이미 뜨겁다 (%.0f℃)" % room.t_upper)


func test_basement_disorientation_and_lifeline() -> void:
	var sim := SimWorld.from_scenario(STAGES["3-2"])
	assert_true(sim.lifeline.enabled, "지하층 라이트라인 규칙")
	var c := sim.units.get_crew(2)
	var room := sim.fire.compartment_at(2, 30, 13)
	room.soot = 50.0
	room.layer_depth = room.height
	for m in c.members():
		m.pos = Vector2(30.5, 13.5)
		m.prev_pos = m.pos
		m.level = 2
		m.prev_level = 2
	assert_true(sim.fire.visibility_m(room) < 1.0, "시계 0 (%.2fm)" % sim.fire.visibility_m(room))
	sim.lifeline.step(95.0, 10)
	assert_true(sim.lifeline.disoriented.has(2), "라이트라인 없이 오래 있으면 방향감각 상실")
	assert_eq(sim.events.of_type("crew_disoriented").size(), 1, "대원 안전 무전")
	sim.lifeline.cells[Vector3i(30, 13, 2)] = true
	sim.lifeline.step(0.1, 11)
	assert_true(not sim.lifeline.disoriented.has(2), "라이트라인에 닿으면 방향을 되찾는다")
	# 라이트라인을 깔고 있으면 길을 잃지 않는다
	var c2 := sim.units.get_crew(3)
	for m in c2.members():
		m.pos = Vector2(28.5, 13.5)
		m.prev_pos = m.pos
		m.level = 2
		m.prev_level = 2
	sim.lifeline.cells[Vector3i(28, 13, 2)] = true
	sim.lifeline.step(200.0, 12)
	assert_true(not sim.lifeline.disoriented.has(3), "라이트라인 옆은 괜찮다")


func test_supertall_refuge_and_real_floors() -> void:
	var sim := SimWorld.from_scenario(STAGES["4-1"])
	assert_eq(sim.building.floor_number(4), 30, "index 4 = 30층")
	assert_eq(sim.building.floor_name(4), "30층", "층 이름")
	assert_eq(sim.evac.refuge_level, 4, "피난안전구역")
	# 33층 근무자는 피난안전구역으로 내려간다
	var v := sim.rescue.victims[0]
	var path := sim.evac._exit_path(v)
	assert_true(not path.is_empty() and (path[-1] as Vector3i).z == 4, "피난안전구역(30층)으로 가는 길")
	# 승강기: 1층 → 30층(32층 화재 -2)은 규칙 안, 31층은 위반
	sim.step_ticks(5)
	var c := sim.units.get_crew(0)
	var at := Vector2(sim.elevator.cell) + Vector2(0.5, 0.5)
	for m in c.members():
		m.pos = at
		m.prev_pos = at
		m.level = 1
		m.prev_level = 1
	assert_true(sim.elevator.ride(0, 4, sim.clock.tick), "30층까지")
	assert_eq(sim.elevator.violations, 0, "규칙 안")
	assert_true(int(sim.events.of_type("elevator_ride")[0].seconds) >= 50, "실제 층 수로 시간 (29개층)")
