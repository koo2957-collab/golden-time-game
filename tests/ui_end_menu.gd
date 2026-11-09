extends SceneTree
## P11-1 화면 점검 (창이 열린다): Esc 게임 메뉴(멈춤·가림·확인 창), 창 닫기(X) 확인 창, 임무 포기 → 미완료 디브리핑,
## 중간에 나가면 미완료 기록 저장, 시작 화면의 게임 종료·프로필.
## 사용: godot --path . -s res://tests/ui_end_menu.gd

const SCENARIO := "res://data/scenarios/sop214_1_day_living.json"

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = SCENARIO
	gm.skip_menu = true
	var main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.camera.edge_scroll = false
	world.confine_mouse(false)
	world.hud.command_ui.close_all()
	var sim: SimWorld = world.sim
	sim.realism = "실전"

	# 1) Esc → 게임 메뉴, 게임이 멈춘다
	sim.step_ticks(20)
	var t0 := sim.clock.tick
	_key(KEY_ESCAPE)
	await process_frame
	_check("Esc → 게임 메뉴", world.game_menu.is_open(), true)
	_check("메뉴가 열리면 게임이 멈춤 (트리 일시정지)", paused, true)
	_check("메뉴 7항목 (진행 중)", world.game_menu._items.values().filter(func(b: Button) -> bool: return b.visible).size(), 7)
	for i in 20:
		await process_frame
	_check("멈춘 동안 시뮬레이션 진행 없음", sim.clock.tick, t0)
	_check("일시정지 횟수 기록", sim.pause_count, 1)
	_check("지도·카드를 가리는 막", world.game_menu._shade.visible and world.game_menu._shade.color.a >= 0.8, true)
	# 처음부터 다시 → 확인 창 → 취소
	world.game_menu.choose("restart")
	_check("처음부터 다시는 확인 창", world.game_menu.confirm_id(), "restart")
	world.game_menu.cancel_confirm()
	_check("취소하면 메뉴로", [world.game_menu.confirm_id(), world.game_menu._main.visible], ["", true])
	# Esc 한 번 더 → 계속하기
	_key(KEY_ESCAPE)
	await process_frame
	_check("Esc로 메뉴 닫힘", [world.game_menu.is_open(), paused], [false, false])

	# 2) 창 닫기(X) → 게임 종료 확인 창, 취소하면 게임 계속
	main.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await process_frame
	_check("X → 게임 종료 확인 창", world.game_menu.confirm_id(), "quit")
	_check("확인 창이 떠도 게임은 멈춤", paused, true)
	world.game_menu.cancel_confirm()
	await process_frame
	_check("취소하면 메뉴 없이 게임 계속", [world.game_menu.is_open(), paused], [false, false])
	var t1 := sim.clock.tick
	for i in 30:
		await process_frame
	_check("게임이 다시 흐름", sim.clock.tick > t1, true)

	# 3) 중간에 나가면 '미완료'로 저장
	var path: String = world.save_incomplete("메인 메뉴로 나감 (점검)")
	_check("미완료 기록 파일 저장", path != "" and FileAccess.file_exists(path), true)
	var mine := PlayHistory.entries().filter(func(e: Dictionary) -> bool: return path.ends_with(str(e.file)))
	_check("내 기록에 미완료로 들어감", mine.size() == 1 and mine[0].incomplete, true)
	if path != "":
		DirAccess.remove_absolute(path)

	# 4) 임무 포기 → 미완료 디브리핑 (새 판)
	main = await _new_main(true)
	world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.hud.command_ui.close_all()
	world.sim.step_ticks(20)
	world.open_game_menu()
	world.game_menu.choose("abandon")
	_check("임무 포기는 확인 창", world.game_menu.confirm_id(), "abandon")
	world.game_menu._accept("abandon")
	for i in 5:
		await process_frame
	_check("임무 포기 → 디브리핑", world.hud.debrief.visible, true)
	_check("디브리핑에 미완료 표시", [str(world._last_report.get("result", "")), str(world._last_report.get("end_reason", ""))], ["미완료", "임무 포기"])
	var saved := Evaluator.REPORT_DIR
	for f in DirAccess.get_files_at(saved):
		var r: Variant = JsonData.load_file(saved + "/" + f)
		if r is Dictionary and str(r.get("end_reason", "")) == "임무 포기" and str(r.get("result", "")) == "미완료":
			DirAccess.remove_absolute(saved + "/" + f)

	# 5) 시작 화면: 게임 종료 버튼과 확인 창, 프로필 줄
	main = await _new_main(false)
	var menu = null
	for c in main.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("scenario_menu.gd"):
			menu = c
	_check("시작 화면", menu != null, true)
	if menu:
		menu.quit_requested.emit()
		await process_frame
		_check("시작 화면 게임 종료 → 확인 창", main.quit_menu.confirm_id(), "quit")
		main.quit_menu.cancel_confirm()
		_check("취소하면 시작 화면으로", [main.quit_menu.is_open(), paused], [false, false])
		_check("프로필 줄", menu._profile_label.text.begins_with("교육생"), true)

	print("결과: %s (실패 %d)" % ["통과" if _failed == 0 else "실패", _failed])
	quit(1 if _failed > 0 else 0)


## 메인 씬을 새로 붙인다 (자동 점검에서는 current_scene이 없어 reload_current_scene을 쓸 수 없다)
func _new_main(skip_menu: bool) -> Node:
	var old := root.get_node_or_null("Main")
	if old:
		root.remove_child(old)
		old.queue_free()
	paused = false
	var gm = root.get_node_or_null("GameManager")
	gm.skip_menu = skip_menu
	var m = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(m)
	for i in 10:
		await process_frame
	return m


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	root.push_input(e)
	var up := e.duplicate()
	up.pressed = false
	root.push_input(up)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s  %s%s" % ["통과" if ok else "실패", label, "" if ok else "  (결과: %s, 기대: %s)" % [actual, expected]])
