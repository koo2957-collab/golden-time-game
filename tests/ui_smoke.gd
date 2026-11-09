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
	# 배속·일시정지 조작을 확인하므로 훈련 난이도로 시작한다 (실전·악조건은 1배속 고정)
	menu._realism.select(0)
	_key(KEY_ENTER)
	await process_frame
	await process_frame
	await process_frame
	var world = root.get_node("Main/World")
	_world = world
	# 실제 마우스 위치가 화면 가장자리면 카메라가 흘러가므로 조작 점검에서는 끈다
	world.camera.edge_scroll = false
	world.confine_mouse(false)
	# 앞부분 조작 점검은 직접 지휘 규칙으로 본다. 임무형 내부 지휘(R7)는 뒤에서 따로 점검
	world.sim.command.interior.enabled = false
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
	_key(KEY_M)
	_check("M → 상황판", world.view_mode, world.ViewMode.PLAN)

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
	_click(Vector2(30, 20), MOUSE_BUTTON_LEFT)
	_check("빈 곳 클릭 → 지휘관 선택 해제", sel.commander_selected, false)
	var cpos := sim.command.commander.pos
	_drag(cpos - Vector2(1.5, 0.5), cpos + Vector2(1.5, 0.5))
	_check("현장지휘관 드래그 선택", sel.commander_selected, true)
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

	# R16: 시작은 외부 보기. PgUp 순서는 외부 보기 → 1층 단면 → 2층
	_check("시작은 외부 보기", [world.view_level, world.exterior_view, world.iso_view.exterior], [1, true, true])
	_key(KEY_PAGEUP)
	_check("PgUp → 1층 단면", [world.view_level, world.exterior_view], [1, false])
	_key(KEY_PAGEUP)
	_check("PgUp → 2층", world.view_level, 2)
	_click(Vector2(13.5, 17.5), MOUSE_BUTTON_RIGHT)
	_key(KEY_PAGEDOWN)
	_check("PgDn → 1층", [world.view_level, world.exterior_view], [1, false])
	# R16 층 막대(입면도): 층 칸 클릭 → 그 층 단면, 외부 띠 클릭 → 외부 보기, 막대 위 휠 → 한 칸씩
	var fb = world.hud.floor_bar
	_check("층 막대: 2개 층 + 외부 띠", fb._rows.size(), 3)
	var row2: Dictionary = fb._rows.filter(func(it): return it.kind == "floor" and it.level == 2)[0]
	var ground: Dictionary = fb._rows.filter(func(it): return it.kind == "ground")[0]
	_press_at(fb.get_global_rect().position + row2.rect.get_center(), MOUSE_BUTTON_LEFT)
	_check("층 막대 클릭 → 2층", world.view_level, 2)
	_press_at(fb.get_global_rect().position + row2.rect.get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	_check("층 막대 휠 아래 → 1층 단면", [world.view_level, world.exterior_view], [1, false])
	_press_at(fb.get_global_rect().position + ground.rect.get_center(), MOUSE_BUTTON_LEFT)
	_check("층 막대 외부 띠 → 외부 보기", [world.view_level, world.exterior_view], [1, true])
	# 여기까지는 상황판(평면) 화면이므로 입체로 바꿔 외관을 본 뒤 되돌린다
	_key(KEY_M)
	_check("외부 보기(입체)에서 카메라가 외관 높이까지", world.camera.bounds.position.y < world.projection().bounds(sim.building).position.y, true)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("user://smoke_exterior.png")
	_key(KEY_M)
	_key(KEY_PAGEUP)
	_check("외부 보기에서 PgUp → 1층 단면", [world.view_level, world.exterior_view], [1, false])
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
	_key(KEY_M)
	_check("M → 입체", world.view_mode, world.ViewMode.ISO)
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
	# 소화전이 하단 콘솔 뒤에 가리지 않게 화면 가운데로 (콘솔은 지도 클릭을 막는다)
	world.camera.retarget(proj.bounds(sim.building), proj.to_screen(hydrant_top))
	await process_frame
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
	# R7a 임무형 내부 지휘: 건물 안 조는 본 곳에만 경유지, 지시는 무전으로 전달
	sim.command.interior.enabled = true
	var inside_id := -1
	for c in u.crews:
		if sim.command.interior.crew_inside(c.id) and not c.leader.incapacitated:
			inside_id = c.id
			break
	_check("건물 안 조가 있다", inside_id >= 0, true)
	if inside_id >= 0:
		sel._set_selection([inside_id] as Array[int])
		var unseen := Vector2(-1, -1)
		var lv := u.get_crew(inside_id).leader.level
		for y in sim.building.height:
			for x in sim.building.width:
				if unseen.x < 0 and sim.command.interior.indoor(lv, Vector2(x, y)) and not sim.perception.is_seen(lv, x, y) 						and sim.pathfinder.nearest_walkable(lv, Vector2i(x, y)) == Vector2i(x, y):
					unseen = Vector2(x + 0.5, y + 0.5)
		world.set_view_level(lv)
		if unseen.x >= 0:
			world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(unseen))
			await process_frame
			var moves_before := sim.command_log.entries.filter(func(c): return c is MoveCommand).size()
			_click(unseen, MOUSE_BUTTON_RIGHT)
			sim.step_ticks(2)
			await process_frame
			await process_frame
			_check("내부 조: 본 적 없는 곳 우클릭 → 거절", sim.command_log.entries.filter(func(c): return c is MoveCommand).size(), moves_before)
			_check("거절 알림", world.hud._notice_label.text.contains("본 적 없는"), true)
		var here := u.get_crew(inside_id).leader.pos
		world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(here))
		await process_frame
		_click(here, MOUSE_BUTTON_RIGHT)
		sim.step_ticks(1)
		var radio := sim.command.radio
		var sent := radio.queue.any(func(m): return m.body.ends_with("이동하라.")) or (radio.current != null and radio.current.body.ends_with("이동하라."))
		_check("내부 조: 본 곳 우클릭 → 무전 지시", sent, true)
	# 본 적 없는 방에 W(주 임무) → 층 단위 임무로 바뀐다
	var room2: Compartment = null
	for room in sim.fire.comps:
		if room.level == 2 and room.cells.size() >= 4 and sim.perception.room_seen[room.index] == 0:
			room2 = room
			break
	if room2:
		var out_id := -1
		for c in u.crews:
			if not sim.command.interior.crew_inside(c.id) and not c.leader.incapacitated and sim.units.squad_of_crew(c.id).type == "진압대":
				out_id = c.id
				break
		if out_id >= 0:
			sel._set_selection([out_id] as Array[int])
			world.set_view_level(2)
			var rc := Vector2(room2.cells[room2.cells.size() / 2]) + Vector2(0.5, 0.5)
			world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(rc))
			await process_frame
			_key(KEY_W)
			_click(rc, MOUSE_BUTTON_LEFT)
			sim.step_ticks(1)
			var lt = sim.command_log.entries.filter(func(c): return c is TacticalCommand)
			_check("본 적 없는 방 W → 층 진압", lt[-1].action if not lt.is_empty() else "", "attack_floor")
			world.set_view_level(1)
	# R7c 원형 메뉴: 건물 안 조 우클릭 → 메뉴 → 보고 요청·대기
	var mui = world.mission_ui
	if inside_id >= 0:
		var lv2 := u.get_crew(inside_id).leader.level
		world.set_view_level(lv2)
		var here2 := u.get_crew(inside_id).leader.pos
		world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(here2))
		await process_frame
		_click(here2, MOUSE_BUTTON_RIGHT, false, false, true)
		await process_frame
		_check("건물 안 조 우클릭 → 원형 메뉴", mui.radial.visible, true)
		_check("원형 메뉴 6항목", mui.radial.items.size(), 6)
		# 항목을 실제로 클릭 (보고 요청 = 5번째)
		var e2 := InputEventMouseButton.new()
		e2.button_index = MOUSE_BUTTON_LEFT
		e2.pressed = true
		e2.position = mui.radial.item_position(4)
		root.push_input(e2, true)
		await process_frame
		_check("메뉴 클릭 → 닫힘", mui.radial.visible, false)
		sim.step_ticks(1)
		var asked := sim.command.radio.queue.any(func(m): return m.body.contains("상황 보고하라")) or (sim.command.radio.current != null and sim.command.radio.current.body.contains("상황 보고하라"))
		_check("보고 요청 무전", asked, true)
		mui.open_crew_menu(inside_id, Vector2(600, 400))
		mui.radial.pick("hold")
		var held := sim.issued.filter(func(x): return x.command is TacticalCommand and x.command.action == "hold")
		_check("대기 지시", held.size(), 1)
	# R7c 팀 카드: 상황판에 조마다 카드, 끌어다 지도에 놓기 → 임무 창 → 인명 검색 + 임무 조건
	_check("팀 카드", cui._team_buttons.size() >= 4, true)
	var card_id := 2
	var card_btn: Button = cui._team_buttons.get(card_id)
	var room1 := sim.fire.compartment_at(1, 24, 17)
	if card_btn and room1:
		world.set_view_level(1)
		var drop := Vector2(room1.cells[room1.cells.size() / 2]) + Vector2(0.5, 0.5)
		world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(drop))
		await process_frame
		var from := card_btn.get_global_rect().get_center()
		var to := _screen(drop)
		var pr := InputEventMouseButton.new()
		pr.button_index = MOUSE_BUTTON_LEFT
		pr.pressed = true
		pr.position = from
		pr.global_position = from
		root.push_input(pr, true)
		var mv := InputEventMouseMotion.new()
		mv.position = to
		mv.global_position = to
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mv, true)
		var rl: InputEventMouseButton = pr.duplicate()
		rl.pressed = false
		rl.position = to
		rl.global_position = to
		root.push_input(rl, true)
		await process_frame
		_check("팀 카드 끌어다 놓기 → 임무 창", mui.panel.visible, true)
		mui._opts["on_victim"].select(1)
		mui.assign("search")
		var conds := sim.issued.filter(func(x): return x.command is CommandOrder and x.command.action == "mission_conditions")
		var miss := sim.issued.filter(func(x): return x.command is TacticalCommand and x.command.action.begins_with("search") and x.command.crew_ids == [card_id])
		_check("임무 조건 + 인명 검색", [conds.size() >= 1, miss.size() >= 1], [true, true])
		sim.step_ticks(1)
		_check("조건 기록", sim.tactical.condition_text(card_id).contains("즉시 구조"), true)
	# R15 성능 표시 (F12)
	_key(KEY_F12)
	await process_frame
	await process_frame
	_check("F12 → 성능 표시", world.hud.perf_visible() and world.hud._perf.text.contains("fps"), true)
	_key(KEY_F12)
	# R8 → R16 미니맵: 바깥 배치도는 처음부터, 건물 안 평면도는 도면 뒤. 누르기·끌기로 화면 이동, 화면 범위 표시
	var mm = world.hud.minimap
	_check("건물 안 평면도 잠김 (도면 없음)", mm.unlocked(), false)
	_check("미니맵 화면 범위 (모서리 4개)", mm.view_corners.call().size(), 4)
	await process_frame
	root.get_texture().get_image().save_png("user://smoke_minimap_noplan.png")
	var cam_before: Vector2 = world.camera.position
	var mc := InputEventMouseButton.new()
	mc.button_index = MOUSE_BUTTON_LEFT
	mc.pressed = true
	mc.position = mm.get_global_rect().position + mm.size * Vector2(0.8, 0.5)
	root.push_input(mc, true)
	await process_frame
	_check("도면 전에도 미니맵 클릭 → 화면 이동", world.camera.position != cam_before, true)
	cam_before = world.camera.position
	var mmove := InputEventMouseMotion.new()
	mmove.button_mask = MOUSE_BUTTON_MASK_LEFT
	mmove.position = mm.get_global_rect().position + mm.size * Vector2(0.3, 0.5)
	root.push_input(mmove, true)
	var mup: InputEventMouseButton = mc.duplicate()
	mup.pressed = false
	mup.position = mmove.position
	root.push_input(mup, true)
	await process_frame
	_check("미니맵 끌기 → 화면 따라 이동", world.camera.position != cam_before, true)
	sim.plan.acquire("상황실", sim.clock.tick)
	_check("도면 → 미니맵 평면도 열림", mm.unlocked(), true)
	_check("도면 → 방 단위 임무", sim.command.interior.plan_known, true)
	mm.queue_redraw()
	world.hud.command_ui.toggle_board()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("user://smoke_minimap_plan.png")
	world.hud.command_ui.toggle_board()
	# R13 지휘권 이양: 지휘대 도착 → 브리핑 창 → 이양 → 지휘대장
	sim.transfer.unit = {"name": "점검용 지휘대", "chief": {"name": "한도윤", "rank": "소방령", "title": "지휘대장"}}
	sim.transfer.arrive_tick = sim.clock.tick + 1
	sim.step_ticks(2)
	for i in 30:
		await process_frame
		if cui.transfer_visible():
			break
	_check("지휘대 도착 → 이양 브리핑 창", cui.transfer_visible(), true)
	if cui.transfer_visible():
		cui.pick_transfer_truth()
		cui.confirm_transfer()
		sim.step_ticks(2)
		_check("이양 → 지휘대장", [sim.transfer.transferred(), sim.command.commander_title], [true, "지휘대장"])
		_check("브리핑 정확도 100%", sim.transfer.accuracy, 1.0)
	sim.command.interior.enabled = false
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
	# R12: 보고서 저장(인쇄용 HTML·CSV)·리플레이 보기 버튼
	_check("디브리핑 결과 보관", world._last_report.is_empty(), false)
	var html_path := ReportExport.save(world._last_report, "user://smoke_export")
	_check("인쇄용 보고서 저장", FileAccess.file_exists(html_path), true)
	for f in DirAccess.get_files_at("user://smoke_export"):
		DirAccess.remove_absolute("user://smoke_export/" + f)
	var labels: Array = []
	var stack: Array = [world.hud.debrief]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Button:
			labels.append(n.text)
		stack.append_array(n.get_children())
	_check("리플레이 보기 버튼", labels.has("이 시점부터 리플레이 보기"), true)

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


## 화면 좌표에서 버튼 누르고 떼기 (HUD 조작용)
func _press_at(screen_pos: Vector2, button: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = screen_pos
	root.push_input(e, true)
	var r: InputEventMouseButton = e.duplicate()
	r.pressed = false
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
