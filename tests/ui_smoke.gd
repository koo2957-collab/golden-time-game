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
	# 지도 조작 점검: 오른쪽 무전 기록·팀 초상 줄이 클릭 자리를 가리지 않게 숨긴다 (두 패널은 test_board·ui_command_card에서 점검)
	world.hud.radio_log.visible = false
	world.hud.team_strip.visible = false
	# 실제 마우스 위치가 화면 가장자리면 카메라가 흘러가므로 조작 점검에서는 끈다
	world.camera.edge_scroll = false
	world.confine_mouse(false)
	# 무전 장면(2026-11-14)은 훈련 방식에서 화면 가운데를 막고 시간을 멈춘다 — 조작 점검에서는 끈다 (장면은 ui_radio에서 점검)
	world.hud.card_ui.pauses = Callable()
	world.hud.card_ui.visible = false
	# 앞부분 조작 점검은 직접 지휘 규칙으로 본다. 임무형 내부 지휘(R7)는 뒤에서 따로 점검
	world.sim.command.interior.enabled = false
	var sim: SimWorld = world.sim
	# EventBus(autoload)를 쓰는 UI 스크립트는 타입으로 참조하지 않는다
	# (-s 실행 시 autoload 등록 전에 컴파일되어 실패하기 때문)
	var sel = world.selection
	var u := sim.units
	var cui = world.hud.command_ui

	# 출동 중 장면 (2026-11-14): 차가 달리는 동안 결정을 하나씩 → 모두 마치면 Enter로 현장 도착
	_check("출동 중 장면 표시", cui.dispatch_visible(), true)
	_check("출동 중에는 현장 시계가 멈춰 있다", sim.clock.paused, true)
	# 출동 단계 원경 (2026-11-14): 도시 전체가 한 화면에 꽉 차고, 도착할 때까지 카메라는 고정
	var city_plan = world.city.plan
	var view_size := Vector2(root.get_visible_rect().size)
	var far: float = city_plan.overview_zoom(view_size.x)
	_check("출동 단계: 도시 전체가 한 화면에 들어오는 원경 · 카메라 고정", [absf(world.camera.zoom.x - far) < 0.0005, world.camera.locked], [true, true])
	var corners_in := true
	for corner: Vector2 in [Vector2.ZERO, Vector2(view_size.x, 0), Vector2(0, view_size.y), view_size]:
		var at: Vector2 = world.camera.position + (corner - view_size * 0.5) / world.camera.zoom.x
		var cell: Vector2 = world.projections[world.ViewMode.ISO].to_cell(at)
		if not Rect2(city_plan.bounds).has_point(cell):
			corners_in = false
	_check("화면 네 귀퉁이까지 도시가 깔려 있다", corners_in, true)
	_check("안전센터가 화면 안에 있다", Rect2(Vector2.ZERO, view_size).has_point(
		(world.projections[world.ViewMode.ISO].to_screen(Vector2(city_plan.station.rect.get_center())) - world.camera.position) * world.camera.zoom.x + view_size * 0.5), true)
	var dsp = cui.dispatch
	for i in 90:
		if not dsp.current().is_empty():
			break
		await process_frame
	await process_frame
	var site_x: float = (world.projections[world.ViewMode.ISO].to_screen(city_plan.site_center).x - world.camera.position.x) * world.camera.zoom.x + view_size.x * 0.5
	_check("장면은 오른쪽, 준비판은 왼쪽 — 가운데의 현장·출동 경로를 가리지 않는다",
		[dsp._scene.visible, dsp._scene.position.x + 100.0 > site_x, dsp._prep.visible, dsp._prep.position.x + dsp._prep.size.x < site_x - 200.0], [true, true, true, true])
	_check("첫 장면 = 출동 지령 (한 번에 한 장면)", [str(dsp.current().kind), dsp._buttons.size(), dsp._count.text], ["brief", 1, "1 / %d" % dsp.steps.size()])
	_key(KEY_ENTER)
	_check("Enter = 지령 수신 (도착이 아니다)", [dsp.index, cui.dispatch_visible()], [1, true])
	for i in 90:
		if not dsp.current().is_empty():
			break
		await process_frame
	await process_frame
	_check("다음 장면 = 상황실 요청 카드", [str(dsp.current().kind), dsp._buttons.size()], ["card", 3])
	# 뒤 점검에 영향이 없게: 카드는 효과 없는 답, 장비는 챙기지 않음, 조별 임무는 '지시를 기다려라'
	_key(KEY_1 + _quiet_option(dsp.current()))
	_check("숫자키로 고른다 · 준비판에 고른 것이 남는다", [dsp.index, dsp._step_rows[1].text.begins_with("✓")], [2, true])
	_check("결정이 남아 있으면 '현장 도착'이 꺼져 있다", [dsp._go.disabled, dsp.done()], [true, false])
	while not dsp.done():
		dsp._gap = 0.0
		var step: Dictionary = dsp.current()
		if str(step.mode) == "pick":
			dsp.choose(_quiet_option(step))
		else:
			if str(step.mode) == "select":
				dsp.choose(0)
			dsp.confirm()
	await process_frame
	_check("결정을 모두 마치면 '현장 도착'이 켜진다", [dsp._go.disabled, dsp.done(), cui.dispatch_visible()], [false, true, true])
	_key(KEY_ENTER)
	_check("Enter → 남은 길을 건너뛴다 (차는 계속 보인다)", [dsp.skipping, cui.dispatch_progress() >= 0.0], [true, true])
	for i in 600:
		if not cui.dispatch_visible():
			break
		await process_frame
	_check("현장 도착", cui.dispatch_visible(), false)
	_check("도착하면 현장 시계가 흐른다", sim.clock.paused, false)
	for i in 30:
		if not sim.cards.dispatch_answers.is_empty():
			break
		await process_frame
	_check("출동 중 결정이 명령으로 내려간다 (장비·카드·임무 없음)", [sim.events.of_type("loadout").size(), sim.cards.dispatch_answers.size(), sim.preassign.size()], [1, 2, 0])
	# 도착 확대가 끝날 때까지 기다린다 (그동안 카메라는 고정)
	for i in 400:
		if not world.camera.locked:
			break
		await process_frame
	_check("도착하면 현장으로 확대되고 카메라가 풀린다", [world.camera.locked, absf(world.camera.zoom.x - world.START_ZOOM[world.ViewMode.ISO]) < 0.001], [false, true])
	# 처음 차량은 한 대씩 들어오고 조는 차가 서면 내린다 (P4-1)
	sim.step_ticks(1)
	_check("차량이 지도 가장자리에서 들어온다", sim.command.resources.arriving.size() > 0, true)
	_until(func() -> bool: return not sim.command.resources.arriving_now(), 1500)
	_check("모두 도착·하차", sim.units.crews.filter(func(c): return c.leader.aboard and sim.command.resources.on_scene(c.squad_id)).is_empty(), true)

	_check("기본 화면은 입체", world.view_mode, world.ViewMode.ISO)
	# M·Tab = 전술상황판 (P10-1). 평면 보기 점검은 보기 전환을 직접 부른다
	_key(KEY_M)
	await process_frame
	_check("M → 전술상황판 열림", world.hud.board.visible, true)
	# 화이트보드 (2026-11-14): 화면의 85%쯤 · 가로형 16:9 · 도면 60% / 정보 칸 40% · 마커 글씨
	await process_frame
	var wb = world.hud.board
	var wb_style = wb.style
	var screen := Vector2(root.get_visible_rect().size)
	var wb_size: Vector2 = wb.frame.size
	var fits: float = minf(screen.x, screen.y * wb_style.board_aspect) * wb_style.board_screen_ratio
	_check("상황판은 화면의 85%쯤 (16:9로 맞춤)", absf(wb_size.x - fits) <= 3.0, true)
	_check("상황판은 가로형 16:9", absf(wb_size.x / wb_size.y - 16.0 / 9.0) < 0.02, true)
	var map_share: float = wb.map_cell.size.x / (wb.map_cell.size.x + wb.info_cell.size.x)
	_check("도면 60% · 정보 칸 40%", absf(map_share - 0.6) < 0.03, true)
	wb.refresh_text()
	_check("정보 칸: 전략·우선순위·구조대상자·출동 정보", [wb._entry.text.contains("전략"), wb._receo.text.contains("R 구조"),
		wb._status.text.contains("요구조자"), wb._dispatch.text != ""], [true, true, true, true])
	_check("판 위 글씨는 마커 글꼴", [wb._entry.get_theme_font("font") == wb_style.marker_font(), wb_style.marker_font() is FontFile], [true, true])
	_key(KEY_TAB)
	await process_frame
	_check("Tab → 전술상황판 닫힘", world.hud.board.visible, false)
	world.set_view_mode(world.ViewMode.PLAN)
	_check("평면 보기", world.view_mode, world.ViewMode.PLAN)

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

	# 도착 때 뜨는 질문 카드가 클릭 자리를 가리지 않게 비운다 (카드는 test_cards·ui_command_card에서 점검)
	sim.cards.queue.clear()
	await process_frame
	# 진입 명령 전 (P4-5): 밖의 조를 고르면 진입구가 노랗게 → 진입구 클릭 → 그 문 앞에서 멈춰 허가를 묻는다
	var lead0 := u.get_crew(0).leader
	_click(lead0.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_check("밖의 조 선택 → 안내 흐름 (진입구 노랗게)", [sel._guiding(), sel._outside_crews()], [true, [0]])
	var front_entry: EntryPoints.Entry = sim.entries.nearest(Vector2(13.5, 20.5), 1, 3.0)
	_click(Vector2(front_entry.door) + Vector2(0.5, 0.5), MOUSE_BUTTON_LEFT)
	_check("진입구 클릭 → 선택은 그대로", sel.selected, [0])
	sim.step_ticks(150)
	_check("진입구 클릭 → 그 문으로 (진입구로 가는 조)", int(sim.command.approach.get(0, -1)), front_entry.index)
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
	cui.open_info_dialog()
	_check("현장 정보 버튼 → 현장 정보 창", cui.info_visible(), true)
	cui._close(cui._info)
	# 지휘관 명령 칸 (G3): 조를 안 고르면 명령 카드는 숨고, 지휘관 명령 칸은 늘 보인다. 보고 ▸ 지휘권 선언·보고 → 양식
	var hud_board: Dictionary = world.hud.board_buttons
	_check("지휘관 선택 → 명령 카드 숨김 · 지휘관 명령 칸 보임", [world.hud.card.set_name, world.hud._command_panel.visible, world.hud.board_groups["report"].is_visible_in_tree()], ["", false, true])
	_key(KEY_Q)
	_check("고른 조가 없으면 Q 키는 아무 일도 하지 않는다", cui.any_dialog_open(), false)
	hud_board["declare"].pressed.emit()
	_check("보고 ▸ 지휘권 선언·보고 → 상황보고 양식", cui._report.visible, true)
	_check("양식이 떠 있는 동안 일시정지", sim.clock.paused, true)
	for choice in [["fire", "연기만 확인"], ["victims", "있음"], ["use", "단독주택"], ["floors", "2층"],
			["structure", "벽돌조"], ["strategy", "공격"], ["support", "불필요"], ["access", "진입 가능, 회차 불가"]]:
		cui.set_report_choice(choice[0], choice[1])
	cui.submit_report()
	_check("송신하면 양식 닫힘·시간 진행", [cui._report.visible, sim.clock.paused], [false, false])
	sim.step_ticks(400)
	_check("지휘권 선언", sim.command.declared(), true)
	# 진입 허가 요청 카드 (P10-2): 입구에서 멈춘 진압1이 무전으로 요청 → 카드에서 허가 (숫자키)
	# 카드 시간이 지났으면 대원이 잠시 뒤 다시 묻는다 — 카드가 뜰 때까지
	_until(func() -> bool: return sim.cards.queue.any(func(q): return q.id == "ENTRY-01"), 900)
	var entry_card = null
	for qc in sim.cards.queue:
		if qc.id == "ENTRY-01":
			entry_card = qc
	_check("입구에서 진입 허가 요청 카드", entry_card != null, true)
	if entry_card:
		await process_frame
		_check("카드가 화면 맨 앞", sim.cards.active() == entry_card, true)
		for i in entry_card.options.size():
			if str(entry_card.options[i].effect) == "entry_grant":
				_key(KEY_1 + i)
	# 구조1은 다시 하기용 진입 명령으로 (카드 흐름은 tests/test_entry_request.gd)
	sim.issue(CommandOrder.make("entry", [1]))
	_until(func() -> bool: return sim.command.can_enter(0) and sim.command.can_enter(1), 1500)
	_check("카드 허가 → 진압1·구조1 진입 허가", [sim.command.can_enter(0), sim.command.can_enter(1)], [true, true])
	for ff in u.get_crew(0).members():
		ff.path.clear()
	lead0.pos = Vector2(10.5, 23.5)
	u.get_crew(0).partner.pos = Vector2(11.5, 23.5)

	# 상황판 화면
	_click(u.get_crew(0).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_check("클릭 선택", sel.selected, [0])
	_click(u.get_crew(2).partner.pos, MOUSE_BUTTON_LEFT, false, true, true)
	_check("Shift 추가 (짝 클릭 → 조 선택)", sel.selected, [0, 2])
	# 빈 곳 = 건물 밖 땅 (건물 안 방은 진입을 지시한 조를 고른 채 누르면 임무 고르기, P4-5)
	_click(_empty_spot(), MOUSE_BUTTON_LEFT)
	_check("빈 곳 클릭 → 해제", sel.selected, [])
	_drag(Vector2(9, 22), Vector2(23, 24))
	_check("드래그 범위 선택", sel.selected, [0, 1, 2, 3])
	_click(u.get_crew(3).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_click(u.get_crew(3).leader.pos, MOUSE_BUTTON_LEFT, true, false, true)
	_check("더블클릭 → 출동대 전체", sel.selected, [2, 3])
	_click(_empty_spot(), MOUSE_BUTTON_LEFT)
	# 질문 카드가 떠 있으면 1~4는 카드 답이 먼저다 — 카드가 없을 때 누른다
	while sim.cards.active() != null:
		sim.cards.queue.clear()
		await process_frame
	await process_frame
	_key(KEY_1)
	_check("숫자 1 → 팀 초상 줄 첫 팀 (P10-1)", sel.selected, [world.hud.team_strip.crews()[0]])
	_key(KEY_3)
	_check("숫자 3 → 셋째 팀", sel.selected, [world.hud.team_strip.crews()[2]])

	# R16: 시작은 외부 보기. PgUp 순서는 외부 보기 → 1층 단면 → 2층
	_check("시작은 외부 보기", [world.view_level, world.exterior_view, world.iso_view.exterior], [1, true, true])
	_key(KEY_PAGEUP)
	_check("PgUp → 1층 단면", [world.view_level, world.exterior_view], [1, false])
	_key(KEY_PAGEUP)
	_check("PgUp → 2층", world.view_level, 2)
	var n_moves := sim.command_log.entries.filter(func(c): return c is MoveCommand).size()
	_click(Vector2(13.5, 17.5), MOUSE_BUTTON_RIGHT)
	sim.step_ticks(1)
	_check("조를 고른 채 땅 우클릭 → 지휘관 이동 (대원 이동 명령 없음)", [sim.command_log.entries[-1] is CommandOrder and sim.command_log.entries[-1].action == "commander_move",
		sim.command_log.entries.filter(func(c): return c is MoveCommand).size()], [true, n_moves])
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
	world.set_view_mode(world.ViewMode.ISO)
	_check("외부 보기(입체)에서 카메라가 외관 높이까지", world.camera.bounds.position.y < world.projection().bounds(sim.building).position.y, true)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("user://smoke_exterior.png")
	world.set_view_mode(world.ViewMode.PLAN)
	_key(KEY_PAGEUP)
	_check("외부 보기에서 PgUp → 1층 단면", [world.view_level, world.exterior_view], [1, false])
	_drag(Vector2(9, 22), Vector2(15, 24))
	_check("진압1 범위 선택", sel.selected, [0, 1])
	# 목표 칸이 하단 콘솔·카드 뒤에 가리지 않게 화면 가운데로
	world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(Vector2(13.5, 15.5)))
	await process_frame
	# 방 클릭 → 임무 고르기 (P4-5): 화재진압·인명검색·직하층 확인·조건 바꾸기
	_click(Vector2(13.5, 15.5), MOUSE_BUTTON_LEFT)
	await process_frame
	var mui0 = world.mission_ui
	_check("조를 고른 채 방 클릭 → 임무 고르기", [mui0.menu.visible, mui0.menu_ids], [true, ["attack", "search", "check_below", "panel"]])
	var n_iss := sim.issued.size()
	mui0.pick("search")
	var tac = sim.issued.slice(n_iss).filter(func(x): return x.command is TacticalCommand)
	_check("인명검색 지시 → 진압1 (거실)", [str(tac[0].command.action).begins_with("search") if not tac.is_empty() else false, tac[0].command.crew_ids if not tac.is_empty() else []], [true, [0, 1]])
	_check("고르면 목록 닫힘", mui0.menu.visible, false)
	sim.step_ticks(700)

	# 차량·수관·방수 (상황판) — 펌프차가 콘솔 뒤에 가리지 않게 화면 가운데로
	world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(sim.units.vehicles[0].pos))
	await process_frame
	_click(sim.units.vehicles[0].pos, MOUSE_BUTTON_LEFT)
	_check("펌프차 클릭 선택", sel.selected_vehicles, [0])
	# 입구에 두 조가 겹쳐 서 있으면 다른 조가 잡힌다 (P4-3 겹침 순환) — 2조를 옆으로 비킨다
	for ff in u.get_crew(1).members():
		ff.path.clear()
	u.get_crew(1).leader.pos = Vector2(8.5, 24.5)
	u.get_crew(1).partner.pos = Vector2(9.5, 24.5)
	# 진압1 1조는 앞의 인명검색 지시로 현관문을 지나는 중 — 임무를 거두고 바깥 빈 땅에 세운다 (클릭 점검용)
	sim.tactical.cancel(0)
	for ff in u.get_crew(0).members():
		ff.path.clear()
	u.get_crew(0).leader.pos = Vector2(10.5, 23.5)
	u.get_crew(0).partner.pos = Vector2(11.5, 23.5)
	await process_frame
	_click(u.get_crew(0).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_check("조 클릭 → 고르기만 (원형 메뉴 없음, P4-5)", [sel.selected, world.mission_ui.menu.visible], [[0], false])
	# 예전 동작 칸(수관·직사·분무)은 없다 — 수관은 펌프차 우클릭, 주수 방법은 화점실 앞 카드 (P10-2 결정 ②)
	_key(KEY_W)
	var want_mode = sel.Mode.ENTRY_POINT if sim.command.interior.enabled and not sim.command.interior.crew_inside(0) else sel.Mode.ATTACK
	_check("W → (밖의 조면) 진입구 고르기 (P4-2)", [world.hud.card.parent, sel.mode], ["", want_mode])
	sel.cancel_mode()
	_click(sim.units.vehicles[0].pos, MOUSE_BUTTON_RIGHT)
	# 수관 준비·연장에는 현장 작업 시간이 걸린다 (P4-1)
	_until(func() -> bool: return sim.water.hose_of_crew(0) != null, 1200)
	_check("펌프차 우클릭 → 수관 연장", sim.water.hose_of_crew(0) != null, true)
	sim.issue(EquipmentCommand.make("spray", [0] as Array[int], -1, HoseLine.Pattern.FOG, Vector3i(12, 16, 1)))
	_until(func() -> bool: return sim.water.hose_of_crew(0).flowing, 300)
	_check("방수 중", sim.water.hose_of_crew(0).flowing, true)
	_key(KEY_A)
	_key(KEY_S)
	sim.step_ticks(1)
	_check("A 대기 → S 방수 중지", sim.water.hose_of_crew(0).flowing, false)
	sim.issue(EquipmentCommand.make("spray", [0] as Array[int], -1, HoseLine.Pattern.FOG, Vector3i(12, 16, 1)))
	_until(func() -> bool: return sim.water.hose_of_crew(0).flowing, 300)
	_click(Vector2(14.5, 15.5), MOUSE_BUTTON_RIGHT)
	sim.step_ticks(1)
	_check("방수 중 땅 우클릭 → 지휘관 이동, 방수는 계속 (P4-5: 대원 땅 이동 없음)", [sim.command_log.entries[-1] is CommandOrder, sim.water.hose_of_crew(0).flowing], [true, true])
	sim.issue(EquipmentCommand.make("stop", [0] as Array[int]))
	sel._set_selection([1] as Array[int], [] as Array[int])
	_click(sim.units.vehicles[0].pos, MOUSE_BUTTON_RIGHT)
	_until(func() -> bool: return sim.water.hose_of_crew(1) != null, 1200)
	_check("펌프차 우클릭 → 그 펌프차에서 수관 연장", sim.water.hose_of_crew(1) != null, true)
	_click(sim.units.vehicles[1].pos, MOUSE_BUTTON_LEFT)
	_click(sim.units.vehicles[0].pos, MOUSE_BUTTON_RIGHT)
	# 급수 연결은 수관 연장·결합 작업 시간이 걸린다 (P4-1)
	_until(func() -> bool: return sim.units.vehicles[1].supply_to == 0, 1200)
	_check("물탱크차 → 펌프차 우클릭 → 급수", sim.units.vehicles[1].supply_to, 0)

	# 앞의 땅 우클릭으로 지휘관이 현관까지 걸어왔다 — 대원 클릭 점검을 위해 제자리로 (지휘관 클릭이 대원보다 먼저 잡힌다)
	_park_commander()
	# 진압1 2조 (위쪽 알림 줄에 가리지 않게 화면 가운데로)
	world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(u.get_crew(1).leader.pos))
	await process_frame
	_click(u.get_crew(1).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	await _mission(KEY_Q, Vector2(24.5, 17.5))
	_check("Q → 진입구 → 목표 → 임무 창 → 인명검색 (P4-2)", sel.mode, sel.Mode.NONE)
	sim.step_ticks(1)
	var searches := sim.command_log.entries.filter(func(c): return c is TacticalCommand and str(c.action).begins_with("search"))
	_check("방 클릭 → 인명검색 임무", searches.size() >= 1, true)

	# 지휘관 명령 칸 지원 ▸ 단위대 지정 → 단위대 창. 조를 고른 채로 눌러도 된다 (칸은 늘 보인다)
	sel._set_selection([1] as Array[int], [] as Array[int])
	_check("조를 고르면 명령 카드가 나오고 지휘관 명령 칸도 그대로 보인다", [world.hud._command_panel.visible, world.hud.board_groups["support"].is_visible_in_tree()], [true, true])
	hud_board["org"].pressed.emit()
	sel._set_selection([] as Array[int], [] as Array[int])
	_check("지원 ▸ 단위대 지정 → 단위대 창", [cui.org_visible(), sim.clock.paused], [true, true])
	cui.assign_division("A면", 0, [1] as Array[int])
	_check("단위대 지정하면 창 닫힘", [cui.org_visible(), sim.clock.paused], [false, false])
	sim.step_ticks(200)
	_check("A면 단위대 지정 (진압1 대장, 구조1)", sim.command.org.division_named("A면").squads if sim.command.org.division_named("A면") else [], [0, 1])

	# 실제 플레이에서는 배속 키를 막고 현장 시계 배속으로 고정 (P9-1)
	var field_speed: float = sim.clock.speed
	_key(KEY_F2)
	_check("F2 → 배속 바뀌지 않음 (현장 시계 고정)", sim.clock.speed, field_speed)
	_key(KEY_SPACE)
	_check("Space → 일시정지", sim.clock.paused, true)

	# 입체 화면
	world.set_view_mode(world.ViewMode.ISO)
	_check("입체", world.view_mode, world.ViewMode.ISO)
	await process_frame
	world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(u.get_crew(1).leader.pos))
	await process_frame
	_click(u.get_crew(1).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	_check("입체: 클릭 선택", sel.selected, [1])
	world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(Vector2(24.5, 17.5)))
	await process_frame
	_click(Vector2(24.5, 17.5), MOUSE_BUTTON_RIGHT)
	sim.step_ticks(1)
	var last = sim.command_log.entries[-1]
	_park_commander()
	_check("입체: 땅 우클릭 → 지휘관 이동 (P4-5)", last is CommandOrder and last.action == "commander_move", true)
	if last is CommandOrder:
		_check("입체: 지휘관 목표 셀", Vector2i(last.target.x, last.target.y), Vector2i(24, 17))

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
	_until(func() -> bool: return tanker.hydrant == 0, 1500)
	_check("입체: 소화전 점령", tanker.hydrant, 0)
	await process_frame
	await process_frame
	_check("알림 표시", world.hud._notice_label.text.contains("소화전 점령"), true)

	# 명령 카드 (P10-2): 진압대·구조대 같은 팀 카드 — W 화점진압, Q 인명검색 (팀 초상 줄에 가리지 않게 가운데로)
	world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(u.get_crew(1).leader.pos))
	await process_frame
	_click(u.get_crew(1).leader.pos, MOUSE_BUTTON_LEFT, false, false, true)
	await process_frame
	_check("팀 명령 카드 (진압대)", world.hud.card.set_name, "team")
	await _mission(KEY_W, Vector2(24.5, 17.5))
	sim.step_ticks(1)
	# 구조1 1조는 화재 상황에 따라 2층에 못 갔을 수 있으므로 팀 카드처럼 바로 고른다
	sel._set_selection([2] as Array[int], [] as Array[int])
	await process_frame
	_check("팀 명령 카드 (구조대도 같음)", world.hud.card.set_name, "team")
	await _mission(KEY_Q, Vector2(24.5, 17.5))
	sim.step_ticks(1)
	var tacts := sim.command_log.entries.filter(func(c): return c is TacticalCommand)
	_check("진압대 → 진압, 구조대 → 수색", tacts.slice(-2).map(func(c): return c.action), ["attack", "search"])
	_check("RECEO 상태판", cui._receo_label.text.contains("R 구조"), true)
	# 지휘관 명령 칸 안전 ▸ RIT 지정 → 조 누르기, 안전 ▸ 인원 점검
	hud_board["rit"].pressed.emit()
	_check("안전 ▸ RIT 지정 → 조 고르는 창", [cui.role_visible(), cui.role_crews().has(3)], [true, true])
	cui.pick_role_crew(3)
	_check("조를 누르면 창 닫힘", cui.role_visible(), false)
	sel._set_selection([] as Array[int], [] as Array[int])
	hud_board["par"].pressed.emit()
	sim.clock.paused = false
	sim.step_ticks(300)
	_check("RIT 지정 (구조1 2조)", sim.command.safety.role_of(3), SafetySystem.Role.RIT)
	_check("지휘관 R → 인원 점검", sim.command.safety.par_log.size() >= 1, true)
	# R7a 임무형 내부 지휘: 건물 안 조는 본 곳에만 경유지, 지시는 무전으로 전달
	sim.command.interior.enabled = true
	var inside_id := -1
	for c in u.crews:
		if sim.command.interior.crew_inside(c.id) and not c.leader.incapacitated:
			inside_id = c.id
			break
	if inside_id < 0:
		# 불 상황에 따라 아직 아무도 못 들어갔으면 진압1 1조를 현관 안에 둔다 (이 아래는 내부 조작 점검)
		for ff in u.get_crew(0).members():
			ff.path.clear()
			ff.level = 1
			ff.pos = Vector2(13.5, 19.5)
		sim.perception.update(sim.clock.tick)
		inside_id = 0
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
			_check("내부 조: 지도 우클릭 이동은 막힌다 (P4-2)", sim.command_log.entries.filter(func(c): return c is MoveCommand).size(), moves_before)
			_check("땅 우클릭은 지휘관 이동 (P4-5)", sim.command_log.entries[-1] is CommandOrder and sim.command_log.entries[-1].action == "commander_move", true)
		var here := u.get_crew(inside_id).leader.pos
		world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(here))
		await process_frame
		# 이동은 A 대기 ▸ E 여기로 (본 곳에만, 무전으로 전달)
		sel._set_selection([inside_id] as Array[int])
		sel.begin_mode(sel.Mode.WAYPOINT)
		_click(here, MOUSE_BUTTON_LEFT)
		sim.step_ticks(1)
		var radio := sim.command.radio
		# 즉시 지시(훈련)면 이미 전달되어 기록에, 악조건이면 아직 줄에
		var sent := radio.queue.any(func(m): return m.body.ends_with("이동하라.")) or (radio.current != null and radio.current.body.ends_with("이동하라.")) or radio.history.any(func(m): return m.body.ends_with("이동하라."))
		_check("내부 조: 여기로(경유지) → 무전 지시", sent, true)
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
			await _mission(KEY_W, rc, 2)
			sim.step_ticks(1)
			var lt = sim.command_log.entries.filter(func(c): return c is TacticalCommand)
			_check("본 적 없는 방 W → 층 진압", lt[-1].action if not lt.is_empty() else "", "attack_floor")
			world.set_view_level(1)
	# 건물 안 조 (P4-5): 좌클릭은 고르기만, 명령은 명령 카드 단축키 — A 대기 → W 보고 요청·Q 대기
	var mui = world.mission_ui
	if inside_id >= 0:
		var lv2 := u.get_crew(inside_id).leader.level
		world.set_view_level(lv2)
		var here2 := u.get_crew(inside_id).leader.pos
		world.camera.retarget(world.projection().bounds(sim.building), world.projection().to_screen(here2))
		await process_frame
		_click(here2, MOUSE_BUTTON_LEFT, false, false, true)
		await process_frame
		_check("건물 안 조 좌클릭 → 고르기만", [sel.selected, mui.menu.visible], [[inside_id], false])
		_key(KEY_A)
		_check("A 대기 → 하위 칸", str(world.hud.card.parent), "standby")
		_key(KEY_W)
		sim.step_ticks(1)
		var asked := sim.command.radio.queue.any(func(m): return m.body.contains("상황 보고하라")) or (sim.command.radio.current != null and sim.command.radio.current.body.contains("상황 보고하라")) or sim.command.radio.history.any(func(m): return m.body.contains("상황 보고하라"))
		_check("보고 요청 무전", asked, true)
		_key(KEY_A)
		_key(KEY_Q)
		var held := sim.issued.filter(func(x): return x.command is TacticalCommand and x.command.action == "hold")
		_check("대기 지시", held.size(), 1)
	# 팀 카드(진입대원 통제표, 전술상황판 왼쪽 열)를 상황판 평면도의 방에 끌어다 놓기 → 임무 창 (P10-1)
	_check("팀 카드", cui._team_buttons.size() >= 4, true)
	var card_id := 2
	var card_btn: Button = cui._team_buttons.get(card_id)
	var room1 := sim.fire.compartment_at(1, 24, 17)
	if card_btn and room1:
		var board = world.hud.board
		board.toggle()
		board.show_level(1)
		await process_frame
		await process_frame
		var drop := Vector2(room1.cells[room1.cells.size() / 2]) + Vector2(0.5, 0.5)
		var from := card_btn.get_global_rect().get_center()
		var to: Vector2 = board.map.get_global_rect().position + board.map.to_px(drop)
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
		board.toggle()
	# R15 성능 표시 (F12)
	_key(KEY_F12)
	await process_frame
	await process_frame
	_check("F12 → 성능 표시", world.hud.perf_visible() and world.hud._perf.text.contains("fps"), true)
	_key(KEY_F12)
	# 미니맵은 없앴다 (2026-11-14 결정) — 도면 확보는 방 단위 임무와 전술상황판으로 드러난다
	_check("미니맵 없음", world.hud.minimap == null, true)
	sim.plan.acquire("상황실", sim.clock.tick)
	_check("도면 → 방 단위 임무", sim.command.interior.plan_known, true)
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
	# 제한시간은 없앴다 (P11-1). 시계는 신고 후 시간 (P9-1)
	_check("신고 후 시계 표시", world.hud.clock_label.text.contains("신고 후"), true)
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


## 지휘관을 처음 자리(건물 앞 왼쪽 아래)에 세운다 — 땅 우클릭 점검 뒤 대원과 겹치지 않게
func _park_commander() -> void:
	var c: Firefighter = _world.sim.command.commander
	c.path.clear()
	c.pos = Vector2(6.5, 26.5)
	c.prev_pos = c.pos
	c.level = 1
	c.prev_level = 1


## 화면에 보이는 빈 바깥 땅 (대원·차량·지휘관·진입구·관계인에서 떨어진 곳) — 선택 해제 클릭용
func _empty_spot() -> Vector2:
	var sim: SimWorld = _world.sim
	# 화면 가운데 (위쪽 알림 줄·아래 콘솔·오른쪽 패널은 클릭을 먹는다)
	var vr: Rect2 = _world.get_viewport().get_visible_rect()
	var area := Rect2(vr.size.x * 0.15, vr.size.y * 0.3, vr.size.x * 0.55, vr.size.y * 0.35)
	var b := sim.building
	for y in range(2, b.height - 2):
		for x in range(2, b.width - 2):
			var c := Vector2(x + 0.5, y + 0.5)
			if not b.cell(1, x, y) in BuildingData.OUTDOOR or not area.has_point(_screen(c, false)) or _ui_covers(root, _screen(c, false)):
				continue
			var near := false
			for cr in sim.units.crews:
				for ff in cr.members():
					near = near or ff.pos.distance_to(c) < 3.0
			for v in sim.units.vehicles:
				near = near or v.pos.distance_to(c) < 5.0
			for e in sim.entries.list:
				near = near or Vector2(e.door).distance_to(c) < 5.0
			for w in sim.command.survey.witnesses:
				near = near or w.pos.distance_to(c) < 3.0
			near = near or sim.command.commander.pos.distance_to(c) < 3.0
			if not near:
				return c
	return Vector2(30, 20)


## 화면 점 위에 마우스를 받는 보이는 UI가 있는가 (그러면 지도 클릭이 닿지 않는다)
func _ui_covers(n: Node, pos: Vector2) -> bool:
	if n is CanvasItem and not n.is_visible_in_tree():
		return false
	if n is Control and n.mouse_filter != Control.MOUSE_FILTER_IGNORE and n.get_global_rect().has_point(pos) and not n is SubViewportContainer:
		# 전체 화면을 덮는 투명 바탕(지도 위 HUD 뿌리)은 클릭을 넘긴다
		if n.get_global_rect().size.x < 1800.0:
			return true
	for ch in n.get_children():
		if _ui_covers(ch, pos):
			return true
	return false


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


## 진입 지시 4단계 (P4-2): 임무 키 → (밖의 조면) 진입구 → 목표 클릭 → 임무 창 '지시'(Enter)
func _mission(key: Key, target: Vector2, lv := 1) -> void:
	var sel = _world.selection
	_key(key)
	if sel.mode == sel.Mode.ENTRY_POINT:
		var e = _world.sim.entries.list[0]
		sel._pick_entry(sel.projection.to_screen(Vector2(e.door) + Vector2(0.5, 0.5)))
	if _world.view_level != lv or _world.exterior_view:
		_world.set_view_level(lv, false)
	_world.camera.retarget(_world.projection().bounds(_world.sim.building), _world.projection().to_screen(target))
	await process_frame
	_click(target, MOUSE_BUTTON_LEFT)
	await process_frame
	var k := InputEventKey.new()
	k.keycode = KEY_ENTER
	k.pressed = true
	root.push_input(k, true)
	await process_frame


## 조건이 될 때까지 시뮬레이션을 진행 (최대 max_ticks)
func _until(cond: Callable, max_ticks: int) -> void:
	for i in max_ticks:
		if cond.call():
			return
		_world.sim.step_ticks(1)


## 출동 중 장면에서 현장에 영향을 주지 않는 보기: 카드는 효과가 note 인 것, 조별 임무는 '지시를 기다려라'(임무 키 없음), 그 밖에는 첫 보기
func _quiet_option(step: Dictionary) -> int:
	var opts: Array = step.options
	for i in opts.size():
		if str(step.kind) == "card" and str(step.spec.options[int(opts[i].value)].get("effect", "")) == "note":
			return i
		if str(step.kind) == "preassign" and str(opts[i].value) == "":
			return i
	return 0


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
