extends TestSuite
## M5b: 후착대 도착·대기1단계·투입 (SOP 103-2.1), 지원 요청 (103-1.2), 통솔범위·단위대 (105), 작전망 (107-3.2)


## 후착대를 바로(0초) 도착하게 바꾼 시나리오
func _org_sim(keys: Array[String] = ["pump2"]) -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var res := sim.command.resources
	res.clear_schedule()
	for k in keys:
		res.schedule(k, 0)
	return sim


func _squad(sim: SimWorld, key: String) -> Squad:
	return sim.units.squad_by_key(key)


## 조건이 맞을 때까지 진행 (최대 max_s초). 맞으면 true
func _until(sim: SimWorld, cond: Callable, max_s := 60.0) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return cond.call()


## keys 출동대가 모두 대기1단계에 설 때까지 진행. 선 출동대 id (시간 안에 못 서면 빈 배열)
func _until_staged(sim: SimWorld, keys: Array[String], max_s := 60.0) -> Array[int]:
	for i in roundi(max_s / SimClock.TICK_DT):
		var ids: Array[int] = []
		for k in keys:
			var s := _squad(sim, k)
			if s and sim.command.resources.is_staged(s.id):
				ids.append(s.id)
		if ids.size() == keys.size():
			return ids
		sim.step_ticks(1)
	return []


func _radio_texts(sim: SimWorld, radio: Radio) -> Array[String]:
	var out: Array[String] = []
	for m in radio.history:
		out.append(m.text())
	return out


func _any_begins(texts: Array[String], prefix: String) -> bool:
	for t in texts:
		if t.begins_with(prefix):
			return true
	return false


func test_scenario_arrivals_are_scheduled() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var names: Array[String] = []
	for u in sim.command.resources.upcoming(0):
		names.append("%s@%d" % [u.name, roundi(u.eta_s)])
	assert_eq(names, ["진압2@180", "진압3@300"] as Array[String], "시나리오 도착표")
	assert_eq(sim.units.squads.size(), 2, "처음에는 선착대만 현장에")
	var off := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	assert_true(off.command.resources.upcoming(0).is_empty(), "지휘 규칙을 끄면 후착대도 오지 않는다")


func test_reinforcement_drives_in_and_stages() -> void:
	var sim := _org_sim()
	var res := sim.command.resources
	sim.step_ticks(1)
	var squad := _squad(sim, "pump2")
	assert_true(squad != null, "도착 시각이 되면 출동대가 생긴다")
	assert_true(res.is_en_route(squad.id), "처음에는 접근 중")
	var v := sim.units.vehicles_of_squad(squad.id)[0]
	assert_true(v.pos.x > sim.building.width, "차량은 지도 동쪽 밖에서 들어온다")
	assert_true(squad.crews.is_empty(), "차량이 서기 전에는 조가 내리지 않는다")
	assert_true(_until(sim, func() -> bool: return res.is_staged(squad.id), 30.0), "대기1단계 장소에 선다")
	assert_true(absf(v.pos.x - v.length_cells * 0.5 - 43.0) < 0.01 and absf(v.pos.y - 36.5) < 0.01,
		"첫 차량은 첫 차로 맨 앞에 선다 (결과: %s)" % v.pos)
	assert_eq(squad.crews.size(), 2, "조 2개가 내린다")
	for c in squad.crews:
		for ff in c.members():
			assert_true(sim.building.cell(1, floori(ff.pos.x), floori(ff.pos.y)) in BuildingData.OUTDOOR, "대원은 차량 옆 바깥에")
			assert_true(not v.contains(ff.pos), "차체 안에 서지 않는다")
			assert_true(ff.air_l > 0.0, "공기호흡기 충전")
	assert_eq(sim.events.of_type("squad_staged").size(), 1, "도착 보고 사건")
	_until(sim, func() -> bool: return not sim.command.radio.busy(), 30.0)
	var texts := _radio_texts(sim, sim.command.radio)
	assert_true(_any_begins(texts, "현장지휘관, 진압2. 대기1단계 장소 도착"), "출동대명·인원·위치 무전 보고 (%s)" % [texts])


func test_staged_squad_needs_commit_radio() -> void:
	var sim := _org_sim()
	var res := sim.command.resources
	var squad := sim.units.squads[_until_staged(sim, ["pump2"] as Array[String])[0]]
	_until(sim, func() -> bool: return not sim.command.radio.busy(), 30.0)
	var crew := squad.crews[0]
	var start := crew.leader.pos
	sim.issue(MoveCommand.new([crew.id], Vector3i(40, 26, 1)))
	sim.step_ticks(5)
	assert_true(sim.command.commit_pending(squad.id), "투입 무전 송신 중")
	assert_true(crew.leader.pos.distance_to(start) < 0.01, "투입 무전이 전달되기 전에는 움직이지 않는다")
	assert_true(_until(sim, func() -> bool: return not res.is_staged(squad.id), 30.0), "투입 무전 후 대기 해제")
	sim.step_ticks(30)
	assert_true(crew.leader.pos.distance_to(start) > 1.0, "미뤄 둔 이동 명령 실행")
	assert_eq(sim.events.of_type("squad_committed").size(), 1, "투입 기록")
	var texts := _radio_texts(sim, sim.command.radio)
	assert_true(_any_begins(texts, "진압2, 현장지휘관. 대기 해제, 현장 투입하라."), "투입 무전 (%s)" % [texts])


func test_order_to_en_route_squad_is_dropped() -> void:
	var sim := _org_sim()
	sim.step_ticks(1)
	var squad := _squad(sim, "pump2")
	var v := sim.units.vehicles_of_squad(squad.id)[0]
	sim.issue(EquipmentCommand.make("vehicle_move", [], v.id, -1, Vector3i(20, 36, 1)))
	sim.step_ticks(1)
	assert_eq(sim.events.of_type("order_en_route").size(), 1, "도착 전 명령은 받지 않는다")
	assert_true(not sim.command.commit_pending(squad.id), "투입 무전도 없음")


func test_staging_full_waits() -> void:
	# 차로 두 개에 펌프차 5대(각 14칸)·물탱크차 1대를 다 세울 수 없다
	var sim := _org_sim(["pump2", "pump3", "pump4", "rescue2", "pump5"] as Array[String])
	var res := sim.command.resources
	sim.step_ticks(300)
	assert_true(sim.events.of_type("staging_full").size() >= 1, "자리가 없으면 진입로에서 대기")
	assert_true(not res.upcoming(sim.clock.tick).is_empty(), "들어오지 못한 출동대는 도착 예정에 남는다")
	for a in sim.units.vehicles:
		for b in sim.units.vehicles:
			if a != b:
				assert_true(Geometry2D.intersect_polygons(a.footprint(), b.footprint()).is_empty(), "차량끼리 겹치지 않는다")


func test_support_request() -> void:
	var sim := _org_sim([] as Array[String])
	var res := sim.command.resources
	sim.issue(CommandOrder.make("support", [], 0, Vector3i.ZERO, {"level": "추가 출동대 요청"}))
	sim.step_ticks(1)
	assert_true(res.upcoming(sim.clock.tick).is_empty(), "무전이 전달되기 전에는 출동하지 않는다")
	_until(sim, func() -> bool: return not sim.command.radio.busy(), 30.0)
	var names: Array[String] = []
	for u in res.upcoming(sim.clock.tick):
		names.append(u.name)
	assert_eq(names, ["진압4", "구조2"] as Array[String], "지원 출동대")
	assert_eq(res.support_level, "추가 출동대 요청", "요청 수준 기록")
	# 대응 1단계로 올리면 아직 부르지 않은 출동대만 더 온다
	sim.issue(CommandOrder.make("support", [], 0, Vector3i.ZERO, {"level": "대응 1단계 발령"}))
	sim.step_ticks(1)
	_until(sim, func() -> bool: return not sim.command.radio.busy(), 30.0)
	assert_eq(res.upcoming(sim.clock.tick).size(), 3, "진압5 추가")
	assert_eq(sim.events.of_type("squad_dispatched").size(), 2, "출동 기록")


func test_support_from_initial_report() -> void:
	var sim := _org_sim([] as Array[String])
	var answers := {
		"fire": "연기만 확인", "victims": "있음", "use": "단독주택", "floors": "2층",
		"structure": "벽돌조", "hazards": [], "activities": ["인명검색"],
		"strategy": CommandSystem.Strategy.OFFENSIVE, "support": "추가 출동대 요청", "access": "진입 가능, 회차 불가",
	}
	sim.issue(CommandOrder.make("declare", [], 0, Vector3i.ZERO, answers))
	_until(sim, func() -> bool: return sim.command.declared(), 60.0)
	assert_eq(sim.command.resources.upcoming(sim.clock.tick).size(), 2, "최초 상황보고 ⑧ 지원 요청으로 출동")
	assert_eq(sim.command.arrived_text(), "진압1·구조1", "① 도착 출동대는 현장에 있는 출동대만")


func test_span_of_control_delay_and_division() -> void:
	var sim := _org_sim(["pump2", "pump3"] as Array[String])
	var cmd := sim.command
	cmd.org.span_ideal = 3  # 출동대 4개로 초과 상황을 만든다
	var ids := _until_staged(sim, ["pump2", "pump3"] as Array[String])
	assert_eq(ids.size(), 2, "두 출동대 모두 대기")
	var p2 := ids[0]
	var p3 := ids[1]
	assert_eq(cmd.direct_count(), 4, "직접 지휘 = 선착 2 + 대기 2")
	assert_eq(sim.events.of_type("span_warning").size(), 1, "통솔범위 경고")
	_until(sim, func() -> bool: return not cmd.radio.busy(), 60.0)
	var crew := sim.units.get_crew(0)
	sim.issue(MoveCommand.new([crew.id], Vector3i(4, 24, 1)))
	sim.step_ticks(2)
	assert_eq(cmd.held_count(), 1, "통솔범위를 넘으면 명령이 늦게 실행된다")
	sim.step_ticks(roundi(cmd.org.delay_per_excess_s / SimClock.TICK_DT))
	assert_eq(cmd.held_count(), 0, "지연 (%.0f초) 뒤 실행" % cmd.org.delay_per_excess_s)
	assert_true(not crew.leader.path.is_empty() or crew.leader.pos.distance_to(Vector2(10.5, 23.5)) > 0.5, "이동 시작")
	# 진압2 대장을 A면 지휘관으로, 진압3을 소속으로
	sim.issue(CommandOrder.make("division", [p3], p2, Vector3i.ZERO, {"name": "A면"}))
	_until(sim, func() -> bool: return cmd.org.division_named("A면") != null, 60.0)
	assert_eq(cmd.direct_count(), 3, "단위대는 하나로 센다")
	assert_eq(sim.events.of_type("division_set").size(), 1, "단위대 지정 기록")
	_until(sim, func() -> bool: return not cmd.radio.busy(), 60.0)
	sim.issue(MoveCommand.new([crew.id], Vector3i(6, 24, 1)))
	sim.step_ticks(2)
	assert_eq(cmd.held_count(), 0, "적정 이하로 줄면 지연 없음")
	assert_true(cmd.org.delayed_orders == 1, "지연된 명령 수 기록")


func test_division_radio_channel() -> void:
	var sim := _org_sim(["pump2"] as Array[String])
	var cmd := sim.command
	var p2 := _until_staged(sim, ["pump2"] as Array[String])[0]
	sim.issue(CommandOrder.make("division", [0], p2, Vector3i.ZERO, {"name": "D면"}))
	_until(sim, func() -> bool: return cmd.org.division_named("D면") != null, 60.0)
	_until(sim, func() -> bool: return not cmd.radio.busy(), 60.0)
	var d := cmd.org.division_named("D면")
	assert_eq(d.squads, [p2, 0] as Array[int], "단위지휘관 출동대 + 소속 출동대")
	var before := cmd.radio.history.size()
	sim.events.add(sim.clock.tick, "door_forced", {"room": "현관", "crew": "진압1 1조"})
	sim.events.add(sim.clock.tick, "air_alarm", {"crew": "진압1 2조"})
	sim.step_ticks(1)
	_until(sim, func() -> bool: return not cmd.radio.busy() and not d.radio.busy(), 60.0)
	var op := _radio_texts(sim, d.radio)
	assert_true(_any_begins(op, "D면 지휘관, 진압1 1조. 잠긴 문 파괴"), "일반 보고는 작전망으로 단위지휘관에게 (%s)" % [op])
	var main := _radio_texts(sim, cmd.radio).slice(before)
	assert_true(_any_begins(main, "현장지휘관, 진압1 2조. 공기호흡기 경보"), "대원 안전 보고는 지휘망으로 (%s)" % [main])
	assert_true(not _any_begins(main, "현장지휘관, 진압1 1조. 잠긴 문"), "지휘망에는 일반 보고가 없다")
	# 전략 전파: 단위대는 단위지휘관이 한 번만 응답한다
	before = cmd.radio.history.size()
	sim.issue(CommandOrder.make("strategy", [], CommandSystem.Strategy.COMBINED))
	sim.step_ticks(1)
	_until(sim, func() -> bool: return not cmd.radio.busy(), 60.0)
	var acks := _radio_texts(sim, cmd.radio).slice(before + 1)
	assert_eq(acks.size(), 2, "응답 2건: D면 지휘관 + 구조1 (%s)" % [acks])
	assert_true(_any_begins(acks, "현장지휘관, D면 지휘관."), "단위지휘관 응답")
	# 해제
	sim.issue(CommandOrder.make("division_clear", [], 0, Vector3i.ZERO, {"name": "D면"}))
	_until(sim, func() -> bool: return cmd.org.division_named("D면") == null, 60.0)
	assert_eq(cmd.direct_count(), 3, "해제하면 다시 직접 지휘")
