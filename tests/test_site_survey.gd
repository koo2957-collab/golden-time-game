extends TestSuite
## M5c: 360° 둘러보기 (SOP 101-2.2, 102-2.2), 관계인 진술 (202-1.2, 2.1), 물증 (202-2.3), 현장지휘소 (104-1.3), 보완 보고

const NEIGHBOR := 0
const RELATIVE := 1


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	return sim


func _put_commander(sim: SimWorld, at: Vector2) -> void:
	var c := sim.command.commander
	c.path.clear()
	c.pos = at
	c.prev_pos = at


func _texts(sim: SimWorld, type: String) -> Array[String]:
	var out: Array[String] = []
	for e in sim.events.of_type(type):
		out.append(SimEventLog.describe_text(e))
	return out


func test_walk_around_reveals_faces() -> void:
	var sim := _sim()
	var survey := sim.command.survey
	sim.step_ticks(1)
	assert_eq(survey.faces_seen.keys(), ["A"], "도착 위치(A면 앞)에서는 A면만 보인다")
	assert_true(not "위험물(가스 등)" in sim.command.observed_truth().hazards, "C면을 보기 전에는 LPG를 모른다")
	sim.issue(CommandOrder.make("survey"))
	sim.step_ticks(1)
	assert_true(not sim.command.commander.path.is_empty(), "둘러보기 경로")
	for i in 1200:
		if sim.command.commander.path.is_empty():
			break
		sim.step_ticks(1)
	var walk_s := sim.clock.tick * SimClock.TICK_DT
	assert_eq(survey.faces_seen.size(), 4, "한 바퀴 돌면 네 면 모두 확인")
	assert_true(walk_s > 30.0 and walk_s < 90.0, "둘러보기에는 시간이 든다 (%.0f초)" % walk_s)
	assert_true(sim.building.cell(1, floori(sim.command.commander.pos.x), floori(sim.command.commander.pos.y)) in BuildingData.OUTDOOR, "건물 밖으로만 돈다")
	assert_eq(sim.events.of_type("site_info_found").size(), 1, "C면 정보 발견")
	assert_true("위험물(가스 등)" in sim.command.observed_truth().hazards, "확인한 위험 요소는 상황보고 ④ 정답에 들어간다")


func test_lit_window_clue() -> void:
	var sim := _sim()
	sim.step_ticks(1)
	var clues := _texts(sim, "clue_found")
	assert_true(clues.size() == 1 and clues[0].contains("2층 방3"), "A면 창으로 2층 방3 실내등이 보인다 (%s)" % [clues])
	assert_true(not sim.command.survey.lit_windows().is_empty(), "불빛 나는 창")
	for o in sim.command.survey.lit_windows():
		assert_eq(sim.command.survey.face_of_opening(o), "A", "확인한 면의 창만")


func test_witness_questions() -> void:
	var sim := _sim()
	var survey := sim.command.survey
	_put_commander(sim, Vector2(12.5, 26.5))
	sim.issue(CommandOrder.make("ask", [], NEIGHBOR, Vector3i.ZERO, {"questions": ["victims"]}))
	sim.step_ticks(1)
	assert_eq(sim.events.of_type("ask_too_far").size(), 1, "멀리서는 질문할 수 없다")
	_put_commander(sim, Vector2(3.5, 25.5))
	sim.issue(CommandOrder.make("ask", [], NEIGHBOR, Vector3i.ZERO, {"questions": ["victims", "origin"]}))
	sim.step_ticks(1)
	sim.step_ticks(roundi(7.0 / SimClock.TICK_DT))
	assert_eq(sim.events.of_type("statement").size(), 0, "질문마다 시간이 든다")
	sim.step_ticks(roundi(2.0 / SimClock.TICK_DT))
	assert_eq(sim.events.of_type("statement").size(), 1, "첫 답")
	sim.step_ticks(roundi(8.0 / SimClock.TICK_DT))
	assert_eq(sim.events.of_type("statement").size(), 2, "두 번째 답")
	assert_true(survey.asking().is_empty(), "질문 끝")
	# 움직이면 끊긴다
	sim.issue(CommandOrder.make("ask", [], NEIGHBOR, Vector3i.ZERO, {"questions": ["doors"]}))
	sim.step_ticks(5)
	sim.issue(CommandOrder.make("commander_move", [], 0, Vector3i(6, 26, 1)))
	sim.step_ticks(3)
	assert_eq(sim.events.of_type("ask_cancelled").size(), 1, "지휘관이 움직이면 질문이 끊긴다")
	# 가족은 나중에 온다
	_put_commander(sim, Vector2(34.5, 25.5))
	assert_true(survey.witness_at(Vector2(35.5, 25.5), sim.clock.tick) < 0, "아직 도착 전")
	sim.step_ticks(1500)
	assert_eq(sim.events.of_type("witness_arrived").size(), 1, "가족 도착")
	_put_commander(sim, Vector2(34.5, 25.5))
	sim.issue(CommandOrder.make("ask", [], RELATIVE, Vector3i.ZERO, {"questions": ["victims", "hazards"]}))
	sim.step_ticks(1 + roundi(16.5 / SimClock.TICK_DT))
	assert_eq(survey.reported_rooms.keys(), ["1F_room1"], "진술에 나온 방 표시")
	assert_true("위험물(가스 등)" in survey.known_hazards(), "믿을 만한 진술의 위험 요소")
	assert_true(not survey.face_seen("C"), "C면을 보지 않아도 진술로 안다")
	var log_kinds: Array[String] = []
	for entry in survey.log:
		if not entry.kind in log_kinds:
			log_kinds.append(entry.kind)
	assert_true("진술" in log_kinds and "물증" in log_kinds, "현장 정보 기록 (%s)" % [log_kinds])


func test_front_door_shoes() -> void:
	var sim := _sim()
	sim.step_ticks(10)
	assert_true(_texts(sim, "clue_found").size() == 1, "잠긴 현관은 신발이 보이지 않는다")
	open_all_doors(sim)
	_put_commander(sim, Vector2(13.5, 21.5))
	sim.step_ticks(10)
	var clues := _texts(sim, "clue_found")
	assert_true(clues.size() == 2 and clues[1].contains("신발 2켤레"), "현관이 열리면 신발 수 확인 (%s)" % [clues])


func test_command_post_evaluation() -> void:
	var sim := _sim()
	var survey := sim.command.survey
	sim.step_ticks(roundi(31.0 / SimClock.TICK_DT))
	var posts := sim.events.of_type("command_post")
	assert_eq(posts.size(), 1, "30초 머문 곳을 현장지휘소로 판정")
	var p := posts[0]
	assert_eq([p.observe, p.safety, p.route], ["보통", "주의", "양호"], "A면만 보임 · 건물 높이 안 · 보도 (%s)" % [p])
	var corner := survey.evaluate_post(Vector2(36.5, 25.5), 1)
	assert_eq(corner.observe, "좋음", "모서리에서는 두 면 (%s)" % [corner])
	assert_eq(corner.faces, "A·D", "A·D면")
	assert_eq(survey.evaluate_post(Vector2(6.5, 31.5), 1).route, "방해 (차도 위)", "차도 위는 차량 동선 방해")
	assert_eq(survey.evaluate_post(Vector2(50.5, 36.5), 1).route, "방해 (대기 장소)", "대기 장소")
	assert_eq(survey.evaluate_post(Vector2(13.5, 21.5), 1).safety, "위험", "건물 바로 앞은 위험반경")
	assert_eq(survey.evaluate_post(Vector2(13.5, 34.5), 1).safety, "안전", "건물 높이(6m) 밖")
	assert_true(survey.fixed_s >= 30.0, "고정 지휘 시간 기록")


func test_update_report() -> void:
	var sim := _sim()
	var answers := {
		"fire": "연기만 확인", "victims": "있음", "use": "단독주택", "floors": "2층",
		"structure": "벽돌조", "hazards": [], "activities": ["인명검색"],
		"strategy": CommandSystem.Strategy.OFFENSIVE, "support": "불필요", "access": "진입 가능, 회차 불가",
	}
	sim.issue(CommandOrder.make("update_report", [], 0, Vector3i.ZERO, {"victims": "있음", "hazards": []}))
	sim.step_ticks(1)
	assert_true(not sim.command.radio.busy(), "선언 전에는 보완 보고 없음")
	sim.issue(CommandOrder.make("declare", [], 0, Vector3i.ZERO, answers))
	for i in 600:
		if sim.command.declared():
			break
		sim.step_ticks(1)
	sim.command.survey.faces_seen["C"] = 0
	sim.command.survey._see_face("C", sim.clock.tick)
	sim.issue(CommandOrder.make("update_report", [], 0, Vector3i.ZERO, {"victims": "있음", "hazards": ["위험물(가스 등)"]}))
	for i in 600:
		if not sim.command.report_updates.is_empty():
			break
		sim.step_ticks(1)
	var u := sim.command.report_updates
	assert_eq(u.size(), 1, "보완 보고 송신")
	assert_eq([u[0].correct, u[0].scored], [2, 2], "새로 확인한 위험 요소까지 맞게 보고")
	var last := sim.command.radio.history.filter(func(m: Radio.Message) -> bool: return m.body.begins_with("상황 보완"))
	assert_true(not last.is_empty() and last[0].body.contains("위험물(가스 등)"), "무전 본문")
