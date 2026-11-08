extends TestSuite
## M9a: 일반 건축물화재 (SOP 212) — 자력 대피·갇힘(1.2), 배관 샤프트(2.3), 간판 낙하(1.4)

const PATH := "res://data/scenarios/sop212_1_commercial_kitchen.json"


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(PATH)
	sim.command.resources.clear_schedule()
	return sim


func _room(sim: SimWorld, level: int, name: String) -> Compartment:
	for c in sim.fire.comps:
		if c.level == level and c.name == name:
			return c
	return null


func test_building_and_scenario() -> void:
	assert_eq(ScenarioLoader.validate(PATH), PackedStringArray(), "시나리오 검증")
	var sim := _sim()
	assert_eq(sim.building.levels().size(), 3, "3층")
	assert_eq(sim.shafts.shaft_rooms.size(), 3, "층마다 샤프트 구획")
	assert_eq(sim.building.signs.size(), 1, "2층 간판")
	assert_eq(sim.rescue.victims.filter(func(v: Victim) -> bool: return v.self_evac).size(), 5, "자력 대피 가능 5명")


func test_self_evac_escapes_when_clear() -> void:
	var sim := _sim()
	sim.step_ticks(roundi(200.0 / SimClock.TICK_DT))
	var out := sim.evac.escaped.size()
	assert_true(out >= 3, "연기가 차기 전에 알아차린 사람은 스스로 나옴 (%d명)" % out)
	var v := sim.rescue.victims[sim.evac.escaped.keys()[0]]
	assert_eq(v.state, Victim.State.RESCUED, "나온 사람은 구조된 것과 같이")
	sim.step_ticks(1)
	assert_true(sim.ems.patient_of(v.id) != null, "구급 분류 대상")


func test_trapped_when_corridor_smoky() -> void:
	var sim := _sim()
	var hall := _room(sim, 1, "복도")
	for v in sim.rescue.victims:
		v.alert_s = 0.0
	hall.layer_depth = hall.height - 0.5
	hall.t_upper = 200.0
	sim.evac.step(0.1, 1)
	assert_eq(sim.evac.escaped.size(), 0, "1층 복도에 연기가 차 있으면 아무도 못 나감")
	assert_eq(sim.evac.trapped.size(), 5, "제자리에서 구조를 기다림")
	assert_eq(sim.events.of_type("victim_trapped").size(), 5, "갇힘 무전")


func test_shaft_spreads_and_check_stops() -> void:
	var sim := _sim()
	var kitchen := _room(sim, 1, "식당 주방")
	kitchen.stage = Compartment.Stage.FULLY_DEVELOPED
	var sh := sim.shafts
	sh.step(0.1, 0)
	assert_true(sh.hot.has(1), "주방 최성기 → 1층 샤프트 유입")
	sh.step(0.1, roundi(190.0 / SimClock.TICK_DT))
	assert_true(sh.hot.has(2), "3분 뒤 2층 샤프트로")
	sh.step(0.1, roundi(440.0 / SimClock.TICK_DT))
	assert_true(sh.ignited.has(2), "다시 4분 뒤 2층 옆 구획에 불")
	# 확인하면 그 층에서 멈춘다
	var sim2 := _sim()
	_room(sim2, 1, "식당 주방").stage = Compartment.Stage.FULLY_DEVELOPED
	sim2.shafts.step(0.1, 0)
	var c := sim2.units.get_crew(0)
	var ps2: Compartment = sim2.shafts.shaft_rooms[2]
	for ff in c.members():
		ff.level = 2
		ff.pos = Vector2(ps2.rect.get_center()) + Vector2(0.5, 0.5)
	sim2.shafts.step(0.1, 10)
	assert_true(sim2.shafts.checked.has(2), "2층 샤프트 확인")
	sim2.shafts.step(0.1, roundi(900.0 / SimClock.TICK_DT))
	assert_true(sim2.shafts.ignited.is_empty(), "확인한 층에서는 번지지 않음")
	var rule: Dictionary = Evaluator.evaluate(sim2).rules.filter(func(r: Dictionary) -> bool: return r.id == "fire.shaft")[0]
	assert_true(rule.score > 0.9, "샤프트 확인 판정 (%s)" % rule.detail)


func test_sign_falls_on_crew() -> void:
	var sim := _sim()
	var sg: Dictionary = sim.building.signs[0]
	var o: Opening = null
	for op in sim.fire.openings:
		if op.kind == Opening.Kind.WINDOW and op.level == 2 and sim.falls._sign_covers(sg.rect, op.cells[0]):
			o = op
			break
	assert_true(o != null, "간판 뒤 창")
	o.broken = true
	sim.falls.step(0.1, 1)
	assert_eq(sim.events.of_type("sign_warning").size(), 1, "간판 낙하 경고")
	var c := sim.units.get_crew(0)
	var below := Vector2(Rect2i(sg.rect).get_center()) + Vector2(0, 2)
	for ff in c.members():
		ff.path.clear()
		ff.level = 1
		ff.pos = below
	sim.falls.step(0.1, roundi(100.0 / SimClock.TICK_DT))
	assert_eq(sim.events.of_type("sign_fall").size(), 1, "간판 낙하")
	assert_true(c.leader.incapacitated, "아래에 있던 대원 행동 불능")
	assert_true(sim.events.of_type("ff_down").any(func(e: Dictionary) -> bool: return e.reason == "간판 낙하"), "원인 기록")
