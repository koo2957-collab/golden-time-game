extends TestSuite
## M8b-2: 상층 연소 확대(213-1.1), 창가 주민 추락·공기안전매트(213-2.4.3), 낙하물 안전구역(213-2.7.1)

const NIGHT := "res://data/scenarios/sop213_2_apartment_night.json"


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(NIGHT)
	sim.command.resources.clear_schedule()
	return sim


func _rescue_crew(sim: SimWorld) -> Crew:
	for c in sim.units.crews:
		if sim.units.squads[c.squad_id].type == "구조대":
			return c
	return null


func _jumper_room_burning(sim: SimWorld) -> Victim:
	var v := sim.rescue.victims[0]
	var room := sim.fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
	room.ever_burned = true
	sim.falls.step(0.1, 0)
	return v


func test_vertical_exposure_pairs() -> void:
	var sim := _sim()
	var vertical := sim.exposure.pairs.filter(func(p: ExposureSystem.Pair) -> bool: return p.vertical)
	assert_true(vertical.size() > 0, "아파트는 아래층 창 → 위층 창 짝 (%d)" % vertical.size())
	assert_eq(sim.exposure.label(), "상층 세대", "표시 이름")
	var house := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	assert_true(house.exposure.pairs.all(func(p: ExposureSystem.Pair) -> bool: return not p.vertical), "단독주택은 상층 짝 없음")
	assert_true(not house.falls.enabled(), "2층 주택은 추락·낙하물 판정 없음")


func test_jump_without_mat_dies() -> void:
	var sim := _sim()
	var v := _jumper_room_burning(sim)
	assert_true(sim.falls.warned.has(v.id), "방에 불이 붙으면 뛰어내리려 함 징후")
	assert_eq(sim.events.of_type("jump_risk").size(), 1, "징후 무전")
	sim.falls.step(0.1, roundi(250.0 / SimClock.TICK_DT))
	assert_eq(v.state, Victim.State.DEAD, "매트 없이 4층에서 추락 → 사망")
	assert_eq(v.level, 1, "바닥으로")


func test_jump_onto_mat_survives() -> void:
	var sim := _sim()
	var v := sim.rescue.victims[0]
	sim.falls.mats.append(sim.falls.ground_below(v))
	_jumper_room_burning(sim)
	sim.falls.step(0.1, roundi(250.0 / SimClock.TICK_DT))
	assert_eq(v.state, Victim.State.RESCUED, "매트에 떨어지면 구조됨")
	assert_true(v.fell, "추락 표시")
	sim.ems.step(0.1, 2500)
	assert_eq(sim.ems.patient_of(v.id).triage, EmsSystem.Triage.EMERGENT, "추락 환자는 응급 이상")
	var rule: Dictionary = Evaluator.evaluate(sim).rules.filter(func(r: Dictionary) -> bool: return r.id == "rescue.air_mat")[0]
	assert_eq(rule.score, 1.0, "매트 판정 만점")


func test_air_mat_setup() -> void:
	var sim := _sim()
	var below := sim.falls.ground_below(sim.rescue.victims[0])
	assert_true(not sim.falls.order_mat(0, Vector2i(below), 0), "진압대는 매트를 설치하지 않음")
	var c := _rescue_crew(sim)
	sim.issue(EquipmentCommand.make("air_mat", [c.id] as Array[int], -1, -1, Vector3i(floori(below.x), floori(below.y), 1)))
	sim.step_ticks(roundi(150.0 / SimClock.TICK_DT))
	assert_eq(sim.falls.mats.size(), 1, "구조대가 가서 매트 설치")
	assert_true(sim.falls.mat_near(below), "창 아래에 매트")


func test_debris_zone() -> void:
	var sim := _sim()
	var o: Opening = null
	for op in sim.fire.openings:
		if op.kind == Opening.Kind.WINDOW and op.level == 4 and (op.room_a == Opening.OUTSIDE or op.room_b == Opening.OUTSIDE):
			o = op
			break
	o.broken = true
	sim.falls.step(0.1, 1)
	assert_eq(sim.falls.zones.size(), 1, "4층 창 파손 → 낙하물 구역")
	var z: Dictionary = sim.falls.zones[0]
	assert_eq(snappedf(z.radius * sim.building.cell_size_m, 0.1), 6.0, "반경 = 4층 높이(12m)의 1/2")
	var c := sim.units.get_crew(0)
	for ff in c.members():
		ff.path.clear()
		ff.level = 1
		ff.pos = z.center
		ff.prev_pos = ff.pos
	for i in 20:
		sim.falls.step(0.5, 2 + i)
	assert_true(sim.falls.zone_seconds >= 9.0, "구역 안 체류 시간 (%.1f)" % sim.falls.zone_seconds)
	assert_eq(sim.events.of_type("debris_zone_entered").size(), 1, "진입 경고 한 번")
