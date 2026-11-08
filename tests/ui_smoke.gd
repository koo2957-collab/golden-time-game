extends SceneTree
## 조작 통합 점검. 실제 메인 씬에 마우스·키 입력을 넣어 선택·이동·층 전환·배속을 확인한다.
## 렌더링이 필요하므로 창이 잠깐 열린다 (--headless 없이 실행).
## 사용: godot --path . -s res://tests/ui_smoke.gd

var _failed := 0
var _world


func _initialize() -> void:
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	# 시작 화면: 시나리오 목록 → 개발용 시나리오 시작
	var menu = root.get_node("Main/Menu")
	_check("시작 화면 표시", menu != null, true)
	var dev := -1
	for i in menu.scenarios.size():
		if menu.scenarios[i].path.ends_with("dev_house_fire.json"):
			dev = i
	_check("시나리오 목록에 개발용 시나리오", dev >= 0, true)
	for s in menu.scenarios:
		_check("시나리오 검증 통과: %s" % s.title, s.errors, PackedStringArray())
	menu.select(dev)
	_key(KEY_ENTER)
	await process_frame
	await process_frame
	await process_frame
	var world = root.get_node("Main/World")
	_world = world
	var sim: SimWorld = world.sim
	# EventBus(autoload)를 쓰는 UI 스크립트는 타입으로 참조하지 않는다
	# (-s 실행 시 autoload 등록 전에 컴파일되어 실패하기 때문)
	var sel = world.selection
	var u := sim.units
	var cui = world.hud.command_ui

	# 출동 지령 창 → Enter로 현장 도착
	_check("출동 지령 창 표시", cui.dispatch_visible(), true)
	_check("지령 창이 떠 있는 동안 일시정지", sim.clock.paused, true)
	_key(KEY_ENTER)
	_check("Enter → 현장 도착", cui.dispatch_visible(), false)
	_check("지령 창을 닫으면 시간 진행", sim.clock.paused, false)

	_check("기본 화면은 입체", world.view_mode, world.ViewMode.ISO)
	_key(KEY_TAB)
	_check("Tab → 상황판", world.view_mode, world.ViewMode.PLAN)

	# 닫힌(잠긴) 현관문 우클릭 → 문 파괴 작업 시작
	_click(u.get_crew(3).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_click(Vector2(13.5, 20.5), MOUSE_BUTTON_RIGHT)
	sim.step_ticks(1)
	var front := sim.fire.opening_at(Vector3i(13, 20, 1))
	_check("잠긴 문 우클릭 → 문 작업 시작", sim.doors.task_of(front) != null, true)
	_click(Vector2(30, 20), MOUSE_BUTTON_LEFT)
	# 이후 항목은 문 규칙과 상관없는 조작 확인이므로 문을 모두 연다
	sim.doors.cancel(3)
	TestSuite.open_all_doors(sim)
	sim.units.get_crew(3).leader.path.clear()
	sim.units.get_crew(3).partner.path.clear()
	sim.units.get_crew(3).leader.pos = Vector2(20.5, 23.5)
	sim.units.get_crew(3).partner.pos = Vector2(21.5, 23.5)

	# 진입 명령 전: 건물 안으로 이동 명령 → 입구 앞에서 멈춤
	var lead0 := u.get_crew(0).leader
	_click(lead0.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_click(Vector2(13.5, 15.5), MOUSE_BUTTON_RIGHT)
	sim.step_ticks(150)
	_check("진입 명령 전에는 입구 앞에서 멈춤", sim.building.cell(1, floori(lead0.pos.x), floori(lead0.pos.y)) in BuildingData.OUTDOOR, true)
	# 현장지휘관 선택·이동
	_click(sim.command.commander.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_check("현장지휘관 클릭 선택", sel.commander_selected, true)
	_click(Vector2(8.5, 26.5), MOUSE_BUTTON_RIGHT)
	sim.step_ticks(1)
	_check("지휘관 우클릭 이동", sim.command_log.entries[-1] is CommandOrder, true)
	# 관계인 클릭 → 진술 창 → 질문
	_click(sim.command.survey.witnesses[0].pos, MOUSE_BUTTON_LEFT, false, false, true)
	_check("관계인 클릭 → 진술 창", cui.witness_visible(), true)
	cui.ask_witness(["victims"] as Array[String])
	_check("질문하면 창 닫힘", cui.witness_visible(), false)
	sim.step_ticks(100)
	_check("진술 들음", sim.events.of_type("statement").size(), 1)
	_key(KEY_F)
	_check("F → 현장 정보 창", cui.info_visible(), true)
	cui._close(cui._info)
	# C → 지휘권 선언·최초 상황보고 양식
	_key(KEY_C)
	_check("C → 상황보고 양식", cui._report.visible, true)
	_check("양식이 떠 있는 동안 일시정지", sim.clock.paused, true)
	for choice in [["fire", "연기만 확인"], ["victims", "있음"], ["use", "단독주택"], ["floors", "2층"],
			["structure", "벽돌조"], ["strategy", "공격"], ["support", "불필요"], ["access", "진입 가능, 회차 불가"]]:
		cui.set_report_choice(choice[0], choice[1])
	cui.submit_report()
	_check("송신하면 양식 닫힘·시간 진행", [cui._report.visible, sim.clock.paused], [false, false])
	sim.step_ticks(400)
	_check("지휘권 선언", sim.command.declared(), true)
	# R → 선택한 조의 출동대에 진입 명령
	_click(lead0.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_click(u.get_crew(2).leader.pos, MOUSE_BUTTON_LEFT, false, true, true)
	_key(KEY_R)
	sim.step_ticks(300)
	_check("R → 진압1·구조1 진입 허가", [sim.command.can_enter(0), sim.command.can_enter(1)], [true, true])
	for ff in u.get_crew(0).members():
		ff.path.clear()
	lead0.pos = Vector2(10.5, 23.5)
	u.get_crew(0).partner.pos = Vector2(11.5, 23.5)

	# 상황판 화면
	_click(u.get_crew(0).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_check("클릭 선택", sel.selected, [0])
	_click(u.get_crew(2).partner.pos, MOUSE_BUTTON_LEFT, false, true, true)
	_check("Shift 추가 (짝 클릭 → 조 선택)", sel.selected, [0, 2])
	_click(Vector2(30, 20), MOUSE_BUTTON_LEFT)
	_check("빈 곳 클릭 → 해제", sel.selected, [])
	_drag(Vector2(9, 22), Vector2(23, 24))
	_check("드래그 범위 선택", sel.selected, [0, 1, 2, 3])
	_click(u.get_crew(3).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_click(u.get_crew(3).leader.pos, MOUSE_BUTTON_LEFT, true, false, true)
	_check("더블클릭 → 출동대 전체", sel.selected, [2, 3])
	_key(KEY_1, true)
	_click(Vector2(30, 20), MOUSE_BUTTON_LEFT)
	_key(KEY_1)
	_check("Ctrl+1 지정 후 1 호출", sel.selected, [2, 3])

	_key(KEY_PAGEUP)
	_check("PgUp → 2층", world.view_level, 2)
	_click(Vector2(13.5, 17.5), MOUSE_BUTTON_RIGHT)
	_key(KEY_PAGEDOWN)
	_check("PgDn → 1층", world.view_level, 1)
	_drag(Vector2(9, 22), Vector2(15, 24))
	_check("진압1 범위 선택", sel.selected, [0, 1])
	_click(Vector2(13.5, 15.5), MOUSE_BUTTON_RIGHT)
	await process_frame
	sim.step_ticks(700)
	_check("이동 명령 3건 기록 (진입 점검 1건 포함)", sim.command_log.entries.filter(func(c): return c is MoveCommand).size(), 3)
	_check("구조1 1조장 2층 도착", u.get_crew(2).leader.level, 2)
	var c0 := u.get_crew(0).leader.cell3()
	_check("진압1 1조장 거실 도착", sim.building.room_at(1, c0.x, c0.y).get("name"), "거실")

	# 차량·수관·방수 (상황판)
	_click(sim.units.vehicles[0].pos, MOUSE_BUTTON_LEFT)
	_check("펌프차 클릭 선택", sel.selected_vehicles, [0])
	_click(u.get_crew(0).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_key(KEY_H)
	_check("H → 수관 연장 모드", sel.mode, sel.Mode.HOSE)
	_click(sim.units.vehicles[0].pos, MOUSE_BUTTON_LEFT)
	sim.step_ticks(1)
	_check("펌프차 클릭 → 수관 연장", sim.water.hose_of_crew(0) != null, true)
	_key(KEY_A)
	_check("A → 직사 방수 모드", sel.mode, sel.Mode.STRAIGHT)
	_click(Vector2(12.5, 16.5), MOUSE_BUTTON_LEFT)
	sim.step_ticks(1)
	_check("목표 클릭 → 방수 시작(직사)", sim.water.hose_of_crew(0).flowing, true)
	_key(KEY_S)
	_click(Vector2(12.5, 16.5), MOUSE_BUTTON_LEFT)
	sim.step_ticks(1)
	_check("S → 분무로 다시 지정", sim.water.hose_of_crew(0).pattern, HoseLine.Pattern.FOG)
	_key(KEY_D)
	sim.step_ticks(1)
	_check("D → 방수 중지", sim.water.hose_of_crew(0).flowing, false)
	_key(KEY_A)
	_click(Vector2(12.5, 16.5), MOUSE_BUTTON_LEFT)
	sim.step_ticks(1)
	_click(Vector2(14.5, 15.5), MOUSE_BUTTON_RIGHT)
	sim.step_ticks(1)
	_check("방수 중 우클릭 이동 → 자동 방수 중지", sim.water.hose_of_crew(0).flowing, false)
	_click(u.get_crew(1).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_click(sim.units.vehicles[0].pos, MOUSE_BUTTON_RIGHT)
	sim.step_ticks(1)
	_check("펌프차 우클릭 → 그 펌프차에서 수관 연장", sim.water.hose_of_crew(1) != null, true)
	_click(sim.units.vehicles[1].pos, MOUSE_BUTTON_LEFT)
	_click(sim.units.vehicles[0].pos, MOUSE_BUTTON_RIGHT)
	sim.step_ticks(1)
	_check("물탱크차 → 펌프차 우클릭 → 급수", sim.units.vehicles[1].supply_to, 0)

	_click(u.get_crew(1).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)  # 1층 거실의 진압1 2조
	_key(KEY_Q)
	_check("Q → 인명검색 모드", sel.mode, sel.Mode.SEARCH)
	_click(Vector2(24.5, 17.5), MOUSE_BUTTON_LEFT)
	sim.step_ticks(1)
	_check("방 클릭 → 검색 시작", sim.rescue.searches.size(), 1)

	# O → 조직·지원 창, 단위대 지정
	_key(KEY_O)
	_check("O → 조직·지원 창", [cui.org_visible(), sim.clock.paused], [true, true])
	cui.assign_division("A면", 0, [1] as Array[int])
	_check("단위대 지정하면 창 닫힘", [cui.org_visible(), sim.clock.paused], [false, false])
	sim.step_ticks(200)
	_check("A면 단위대 지정 (진압1 대장, 구조1)", sim.command.org.division_named("A면").squads if sim.command.org.division_named("A면") else [], [0, 1])

	_key(KEY_F2)
	_check("F2 → 2배속", sim.clock.speed, 2.0)
	_key(KEY_SPACE)
	_check("Space → 일시정지", sim.clock.paused, true)

	# 입체 화면
	_key(KEY_TAB)
	_check("Tab → 입체", world.view_mode, world.ViewMode.ISO)
	await process_frame
	_click(u.get_crew(1).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_check("입체: 클릭 선택", sel.selected, [1])
	_click(Vector2(24.5, 17.5), MOUSE_BUTTON_RIGHT)
	sim.step_ticks(1)
	var last = sim.command_log.entries[-1]
	_check("입체: 우클릭 이동 명령", last is MoveCommand, true)
	if last is MoveCommand:
		var target: Vector3i = last.target
		_check("입체: 이동 목표 셀", Vector2i(target.x, target.y), Vector2i(24, 17))

	# 입체: 물탱크차 선택 → 소화전 기둥 윗부분 우클릭 → 이동 후 점령, 알림 표시
	var tanker := sim.units.vehicles[1]
	tanker.supply_to = -1
	_click(tanker.pos, MOUSE_BUTTON_LEFT)
	_check("입체: 물탱크차 선택", sel.selected_vehicles, [1])
	var hydrant_top := Vector2(sim.building.hydrants[0]) + Vector2(0.5, 0.5)
	var proj = world.projection()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.position = root.get_canvas_transform() * proj.to_screen(hydrant_top, 0.7)
	root.push_input(e, true)
	sim.clock.paused = false
	sim.step_ticks(400)
	_check("입체: 소화전 점령", tanker.hydrant, 0)
	await process_frame
	await process_frame
	_check("알림 표시", world.hud._notice_label.text.contains("소화전 점령"), true)

	# 분대 명령칸: W(주 임무) → 방 클릭 → 진압대는 진압, 구조대는 수색
	_click(u.get_crew(1).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	await process_frame
	_check("명령칸 표시 (진압대)", world.hud._card_type, "진압대")
	_key(KEY_W)
	_check("W → 주 임무 모드", sel.mode, sel.Mode.PRIMARY)
	_click(Vector2(24.5, 17.5), MOUSE_BUTTON_LEFT)
	sim.step_ticks(1)
	_key(KEY_PAGEUP)
	_click(u.get_crew(2).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	await process_frame
	_check("명령칸 표시 (구조대)", world.hud._card_type, "구조대")
	_key(KEY_W)
	_click(Vector2(24.5, 17.5), MOUSE_BUTTON_LEFT)
	sim.step_ticks(1)
	_key(KEY_PAGEDOWN)
	var tacts := sim.command_log.entries.filter(func(c): return c is TacticalCommand)
	_check("진압대 → 진압, 구조대 → 수색", tacts.map(func(c): return c.action), ["attack", "search"])
	_check("RECEO 상태판", cui._receo_label.text.contains("R 구조"), true)
	# 안전 임무 지정(RIT)·인원점검(P)
	cui.assign_role(3, SafetySystem.Role.RIT)
	_key(KEY_P)
	sim.clock.paused = false
	sim.step_ticks(300)
	_check("RIT 지정 (구조1 2조)", sim.command.safety.role_of(3), SafetySystem.Role.RIT)
	_check("P → 인원점검", sim.command.safety.par_log.size() >= 1, true)
	# 활동 단계 표시줄·남은 시간 (R1)
	_check("단계 표시줄", world.hud.phase_bar.text.contains("완진 선언"), true)
	_check("남은 시간 표시", world.hud.clock_label.text.contains("남은"), true)
	# 완진 선언 창 → 선언 (불이 남아 있어도 막지 않음) → 마무리 단계
	cui.open_all_clear()
	_check("완진 선언 창 (확인 목록)", cui.all_clear_checklist().contains("초진 보고"), true)
	cui.confirm_all_clear()
	sim.step_ticks(2)
	_check("완진 선언 → 마무리 단계", sim.phases.phase, PhaseSystem.Phase.CLOSE_OUT)
	# 활동 종료 선언 (감시: 관계자에게 당부) → 디브리핑
	cui.open_end_confirm()
	cui.set_end_watch(1)
	cui.confirm_end()
	sim.clock.paused = false
	sim.step_ticks(1)
	await process_frame
	await process_frame
	_check("활동 종료 → 디브리핑 표시", world.hud.debrief.visible, true)
	_check("디브리핑 4단계 탭", world.hud.debrief.tab_count(), 4)
	_check("디브리핑 중에는 무전 패널 숨김", cui._radio_panel.visible, false)
	_check("다시 하기 시점 목록", world.hud.debrief.moment_count() > 3, true)
	_check("종료 때 감시 지정 기록", sim.command.watch, "관계자에게 감시 당부")

	print("조작 점검: %s" % ("모두 통과" if _failed == 0 else "%d건 실패" % _failed))
	quit(1 if _failed > 0 else 0)


## on_unit이면 대원을 고르는 높이(입체 화면에서는 몸통)를 기준으로 화면 좌표를 구한다.
func _screen(cell: Vector2, on_unit := false) -> Vector2:
	var proj = _world.projection()
	return root.get_canvas_transform() * proj.to_screen(cell, proj.pick_height_m if on_unit else 0.0)


func _click(cell: Vector2, button: MouseButton, double := false, shift := false, on_unit := false) -> void:
	var pos := _screen(cell, on_unit)
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = pos
	e.double_click = double
	e.shift_pressed = shift
	root.push_input(e, true)
	var r: InputEventMouseButton = e.duplicate()
	r.pressed = false
	r.double_click = false
	root.push_input(r, true)


func _drag(from_cell: Vector2, to_cell: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = _screen(from_cell)
	root.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = _screen(to_cell)
	root.push_input(motion, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	release.position = motion.position
	root.push_input(release, true)


func _key(keycode: Key, ctrl := false) -> void:
	var k := InputEventKey.new()
	k.keycode = keycode
	k.physical_keycode = keycode
	k.ctrl_pressed = ctrl
	k.pressed = true
	root.push_input(k, true)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("  통과  " + label)
	else:
		_failed += 1
		print("  실패  %s (결과: %s, 기대: %s)" % [label, actual, expected])
