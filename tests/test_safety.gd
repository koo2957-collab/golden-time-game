extends TestSuite
## M6.5: 2025 SOP 정합화 — 긴급탈출(109)·무선 침묵·RIT(SSG 9)·현장안전담당(108-1.4)·인원점검·진입 금지 판단(102-4.1)·8항목 보고


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	open_all_doors(sim)
	return sim


func _quiet(sim: SimWorld, max_s := 90.0) -> void:
	sim.step_ticks(1)
	for i in roundi(max_s / SimClock.TICK_DT):
		if not sim.command.radio.busy():
			return
		sim.step_ticks(1)


func _place(sim: SimWorld, crew_id: int, at: Vector2, level := 1) -> Crew:
	var c := sim.units.get_crew(crew_id)
	for i in c.members().size():
		var ff := c.members()[i]
		ff.path.clear()
		ff.level = level
		ff.pos = at + Vector2(i, 0)
		ff.prev_pos = ff.pos
	return c


func _texts(sim: SimWorld) -> Array[String]:
	var out: Array[String] = []
	for m in sim.command.radio.history:
		out.append(m.text())
	return out


func _has(texts: Array[String], part: String) -> bool:
	for t in texts:
		if t.contains(part):
			return true
	return false


func test_mayday_and_radio_silence() -> void:
	var sim := _sim()
	var c := _place(sim, 0, Vector2(13.5, 15.5))
	_quiet(sim)
	c.partner.incapacitated = true
	sim.step_ticks(1)
	assert_true(sim.command.safety.emergency(), "대원이 쓰러지면 긴급탈출 상황")
	assert_eq(sim.events.of_type("mayday").size(), 1, "긴급탈출 선언 기록")
	sim.events.add(sim.clock.tick, "door_forced", {"room": "현관", "crew": "구조1 1조"})
	_quiet(sim)
	var texts := _texts(sim)
	assert_true(_has(texts, "긴급탈출, 긴급탈출, 긴급탈출"), "같은 조가 긴급탈출 3회 송신 (%s)" % [texts])
	assert_true(not _has(texts, "잠긴 문 파괴"), "긴급탈출 중 일반 보고는 무선 침묵")
	assert_true(sim.command.safety.suppressed_reports >= 1, "멈춘 보고 수")
	# 쓰러진 대원을 밖으로 옮기면 해제
	c.partner.pos = Vector2(13.5, 23.5)
	sim.step_ticks(2)
	assert_true(not sim.command.safety.emergency(), "건물 안에 쓰러진 대원이 없으면 해제")
	assert_eq(sim.events.of_type("emergency_cleared").size(), 1, "해제 기록")


func test_silent_crew_counts_as_emergency() -> void:
	var sim := _sim()
	var c := _place(sim, 0, Vector2(13.5, 15.5))
	_quiet(sim)
	c.leader.incapacitated = true
	c.partner.incapacitated = true
	_quiet(sim)
	var e: Dictionary = sim.events.of_type("mayday")[0]
	assert_true(e.silent, "조 전원이 쓰러지면 무응답 (109-1.1)")
	assert_true(_has(_texts(sim), "무전 응답 없음, 긴급탈출 상황"), "지휘관이 긴급탈출 상황을 전파")


func test_rit_reserved_and_deployed() -> void:
	var sim := _sim()
	var cmd := sim.command
	sim.issue(CommandOrder.make("entry", [0, 1]))
	sim.issue(CommandOrder.make("role", [3], SafetySystem.Role.RIT))
	_quiet(sim)
	assert_eq(cmd.safety.role_of(3), SafetySystem.Role.RIT, "구조1 2조 RIT 지정")
	var rit := sim.units.get_crew(3)
	sim.issue(MoveCommand.new([3], Vector3i(13, 15, 1)))
	sim.step_ticks(150)
	assert_true(sim.building.cell(1, floori(rit.leader.pos.x), floori(rit.leader.pos.y)) in BuildingData.OUTDOOR, "RIT는 진입 허가가 있어도 밖에 머문다")
	sim.issue(EquipmentCommand.make("search", [3], -1, -1, Vector3i(24, 17, 1)))
	sim.step_ticks(1)
	assert_eq(sim.events.of_type("role_reserved").size(), 1, "RIT에는 다른 임무를 주지 않는다 (SSG 9 1.2.2)")
	# 긴급탈출 상황 → 구출 명령은 투입
	var c := _place(sim, 0, Vector2(13.5, 15.5))
	c.partner.incapacitated = true
	sim.step_ticks(2)
	sim.issue(EquipmentCommand.make("rescue_ff", [3], -1, c.partner.id))
	sim.step_ticks(2)
	assert_true(cmd.safety.deployed.has(3), "긴급탈출 상황에서 RIT 투입")
	assert_eq(sim.events.of_type("rit_deployed").size(), 1, "투입 기록 (추가 RIT 지정 안내)")
	sim.step_ticks(150)
	assert_true(sim.events.of_type("rescue_pickup").size() >= 1, "투입된 RIT가 들어가 쓰러진 대원을 확보한다")


func test_evacuation_and_par() -> void:
	var sim := _sim()
	var cmd := sim.command
	sim.issue(CommandOrder.make("entry", [0]))
	_quiet(sim)
	_place(sim, 0, Vector2(13.5, 15.5))
	sim.issue(CommandOrder.make("evacuate"))
	_quiet(sim)
	assert_eq(sim.events.of_type("evacuation_ordered").size(), 1, "긴급탈출 지시 전파")
	assert_true(_has(_texts(sim), "전 대원 즉시 건물 밖으로 탈출하라"), "지시 무전")
	assert_true(cmd.entry_allowed.is_empty(), "진입 허가 취소")
	assert_true(sim.events.of_type("evacuate").size() >= 1, "내부 조 탈출 시작")
	sim.step_ticks(200)
	sim.issue(CommandOrder.make("par"))
	_quiet(sim)
	var par: Dictionary = sim.events.of_type("par_done")[0]
	assert_eq([par.indoor, par.missing], [0, 0], "탈출 후 인원점검 이상 없음")
	assert_true(_has(_texts(sim), "인원 4명 이상 없음, 장비 이상 없음"), "출동대별 보고")


func test_officer_warns_low_air() -> void:
	var sim := _sim()
	sim.issue(CommandOrder.make("role", [2], SafetySystem.Role.OFFICER))
	_quiet(sim)
	assert_eq(sim.command.safety.officer(), 2, "구조1 1조 현장안전담당")
	var c := _place(sim, 0, Vector2(13.5, 15.5))
	c.leader.air_l = c.leader.air_capacity * 0.35
	sim.step_ticks(60)
	assert_eq(sim.events.of_type("officer_warning").size(), 1, "공기 부족을 경보 전에 알림")
	_quiet(sim)
	assert_true(_has(_texts(sim), "현장지휘관, 현장안전담당."), "현장안전담당 무전")


func test_entry_factors_and_report_items() -> void:
	var sim := _sim()
	sim.step_ticks(5)
	sim.events.add(sim.clock.tick, "rollover_sign", {"room": "1층 거실"})
	sim.issue(CommandOrder.make("entry", [1]))
	sim.step_ticks(1)
	var f: Array = sim.events.of_type("entry_factors")
	assert_eq(f.size(), 1, "진입 금지 판단 요소 알림 (102-4.1)")
	assert_true(str(f[0].factors).contains("⑧ 특수현상 징후") and str(f[0].factors).contains("⑩ 구조대상자"), "해당 요소 (%s)" % f[0].factors)
	assert_eq(sim.command.entry_checks.size(), 1, "진입 판단 기록")
	assert_true(sim.command.decisions.size() >= 1 and str(sim.command.decisions[-1].context).contains("구조대상자"), "주요 의사결정과 그때 알던 정보 (111-2.2)")
	var r := sim.command.grade_report({"access": "진입 불가"})
	var last: Dictionary = r.items[-1]
	assert_true(not last.scored, "차량 진입·회차는 2025 SOP 8항목 밖 — 채점 안 함")


func test_safety_rules_in_evaluation() -> void:
	var sim := _sim()
	sim.issue(CommandOrder.make("role", [3], SafetySystem.Role.RIT))
	sim.issue(CommandOrder.make("entry", [0]))
	_quiet(sim)
	_place(sim, 0, Vector2(13.5, 15.5))
	sim.step_ticks(20)
	_place(sim, 0, Vector2(10.5, 23.5))
	sim.step_ticks(20)
	sim.issue(CommandOrder.make("par"))
	_quiet(sim)
	sim.issue(CommandOrder.make("end", [], 0, Vector3i.ZERO, {"watch": "관계자 감시 당부"}))
	sim.step_ticks(1)
	var r := Evaluator.evaluate(sim)
	var by := {}
	for rule: Dictionary in r.rules:
		by[rule.id] = rule
	assert_eq(by["safety.rit"].score, 1.0, "첫 진입 전 RIT 편성 (%s)" % by["safety.rit"].detail)
	assert_eq(by["safety.officer"].score, 0.0, "현장안전담당 없음")
	assert_eq(by["command.par_end"].score, 1.0, "모두 나온 뒤 인원점검 (%s)" % by["command.par_end"].detail)
	assert_true(not by["safety.emergency"].applicable, "긴급탈출이 없으면 해당 없음")
	assert_true(str(by["safety.rit"].tactic).contains("SSG 9"), "소방전술 근거 함께 표기")
	assert_eq(r.rules_version, 2, "규칙 판 기록")
	assert_true(r.decisions.size() >= 2, "의사결정 기록")
