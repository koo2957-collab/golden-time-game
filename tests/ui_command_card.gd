extends SceneTree
## P10-2 명령 카드 점검 (창이 열린다): 원형 메뉴와 명령 카드 항목·단축키 일치, 선택 해제 → 카드 숨김,
## 하위 칸 펼치기·Esc 뒤로, 예전 동작 단축키 없음, 좌클릭 → 원형 메뉴.
## G3: 지휘관 명령 칸 (보고·지원·안전·구역 — 항상 보임, 한 번에 누름, 때가 됐다고 나타나지 않음)
## 사용: godot --path . -s res://tests/ui_command_card.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/sop214_1_day_living.json"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.hud.command_ui.close_all()
	var sel = world.selection
	var sim: SimWorld = world.sim
	var card: CommandCard = world.hud.card
	var sets := CommandCard.load_sets()
	var hud = world.hud
	var cui = hud.command_ui
	var board: Dictionary = hud.board_buttons
	# 선택 없음 = 명령 카드 숨김. 지휘관 명령은 늘 보이는 지휘관 명령 칸에 (G3)
	sel._set_selection([] as Array[int], [] as Array[int])
	await process_frame
	_check("선택 없음 → 세트 없음 · 카드 숨김", [card.set_name, hud._command_panel.visible], ["", false])
	_check("지휘관 세트는 없다 (명령 칸으로 옮김)", sets.has("commander"), false)
	world._press_card("Q")
	_check("선택 없이 Q → 아무 일 없음", [card.parent, cui.any_dialog_open()], ["", false])
	# 지휘관 명령: 아래 바에 네 묶음 단추, 누르면 그 세부 명령이 단추 위에 펼쳐진다 (2026-11-14 결정)
	var groups := CommandCard.load_board()
	_check("네 묶음", groups.map(func(g): return str(g.label)), ["보고", "지원", "안전", "구역"])
	_check("네 묶음 단추가 처음부터 아래 바에 보인다 · 세부 명령은 접혀 있다",
		[groups.all(func(g): return hud.board_groups[str(g.id)].is_visible_in_tree()), hud.board_group_open, board["declare"].is_visible_in_tree()], [true, "", false])
	var missing: Array = []
	var off_place: Array = []
	for g in groups:
		var gid := str(g.id)
		hud.board_groups[gid].button_pressed = true
		await process_frame
		for it in g.items:
			if not board[str(it.id)].is_visible_in_tree():
				missing.append(it.id)
		var fly: Rect2 = hud._flyouts[gid].get_global_rect()
		if hud.board_group_open != gid or fly.end.y > hud.console.position.y or not hud.get_rect().encloses(fly):
			off_place.append(gid)
	_check("묶음을 누르면 그 세부 명령이 모두 보인다", missing, [])
	_check("펼친 목록은 아래 바 위, 화면 안 · 한 번에 하나만", [off_place, hud._flyouts["report"].visible], [[], false])
	root.get_texture().get_image().save_png("user://ui_board_open.png")
	# 목록 밖(지도)을 누르면 닫힌다
	var away := InputEventMouseButton.new()
	away.button_index = MOUSE_BUTTON_LEFT
	away.pressed = true
	away.position = Vector2(700, 400)
	root.push_input(away, true)
	var away_up: InputEventMouseButton = away.duplicate()
	away_up.pressed = false
	root.push_input(away_up, true)
	await process_frame
	_check("목록 밖을 누르면 닫힌다", hud.board_group_open, "")
	sel._set_selection([] as Array[int], [] as Array[int])
	_check("완진 선언·지휘권 이양도 처음부터 누를 수 있다 (때가 돼야 나타나지 않는다)",
		[board["all_clear"].disabled, board["transfer"].disabled, board["end"].disabled], [false, false, false])
	_check("아래 바가 화면 안에 있다", hud.get_rect().encloses(hud.console.get_rect()), true)
	root.get_texture().get_image().save_png("user://ui_board.png")
	# 보고: 선언 전에는 보완 보고가 없다(알림), 선언 양식, 선언 뒤에는 선언 단추가 흐려진다
	board["update_report"].pressed.emit()
	_check("선언 전 보완 보고 → 창 없음", cui.any_dialog_open(), false)
	board["strategy"].pressed.emit()
	_check("선언 전 전략 변경 → 최초 상황보고 양식 (전략은 그 보고의 항목)", cui.report_visible(), true)
	cui.close_all()
	board["declare"].pressed.emit()
	_check("지휘권 선언·보고 → 상황보고 양식", cui.report_visible(), true)
	cui.close_all()
	# 일찍 눌러도 막지 않는다: 초진 전 완진 선언 창이 열리고 확인 목록이 '초진 보고 없음'을 보여 준다
	board["all_clear"].pressed.emit()
	_check("초진 전 완진 선언 → 창이 열린다", [cui.all_clear_visible(), cui.all_clear_checklist().begins_with("✗ 초진 보고")], [true, true])
	cui.close_all()
	# 할 수 없는 일: 지휘대가 오기 전 이양은 창이 열리지 않는다 (넘겨받을 사람이 없다)
	board["transfer"].pressed.emit()
	_check("지휘대 도착 전 이양 → 창 없음", cui.any_dialog_open(), false)
	# 안전: RIT 지정 → 조를 누르면 무전으로 지정, 다시 누르면 해제
	board["rit"].pressed.emit()
	_check("RIT 지정 → 조 고르는 창", cui.role_visible(), true)
	var rit_crew: int = cui.role_crews()[-1]
	cui.pick_role_crew(rit_crew)
	sim.clock.paused = false
	for i in 600:
		if sim.command.safety.role_of(rit_crew) == SafetySystem.Role.RIT:
			break
		sim.step_ticks(1)
	_check("조 누름 → RIT 지정 (무전 뒤)", [cui.role_visible(), sim.command.safety.role_of(rit_crew)], [false, SafetySystem.Role.RIT])
	board["rit"].pressed.emit()
	cui.pick_role_crew(rit_crew)
	sim.clock.paused = false
	for i in 600:
		if sim.command.safety.role_of(rit_crew) == SafetySystem.Role.NONE:
			break
		sim.step_ticks(1)
	_check("맡은 조를 다시 누름 → 해제", sim.command.safety.role_of(rit_crew), SafetySystem.Role.NONE)
	board["officer"].pressed.emit()
	_check("안전담당 지정 → 조 고르는 창", cui.role_visible(), true)
	cui.close_all()
	sim.clock.paused = false
	# 지원: 한 번 요청하면 그 단추만 흐려진다
	board["support_more"].pressed.emit()
	for i in 600:
		if sim.command.resources.support_level != "":
			break
		sim.step_ticks(1)
	hud._refresh_selection()
	_check("추가 출동대 요청 → 요청됨 · 단추 흐림", [sim.command.resources.support_level, board["support_more"].disabled, board["response_1"].disabled], ["추가 출동대 요청", true, false])
	# 구역 (P10-2 ⓑ): 안전구역 → 끌기 → 무전 → 지정, 환자 집결지 클릭
	board["zone_safe"].pressed.emit()
	_check("구역 ▸ 안전구역 → 안전구역 모드", sel.mode, sel.Mode.ZONE_SAFE)
	var zr := Rect2i()
	var fp := sim.building.footprint(1)
	for y in range(fp.end.y + 2, sim.building.height - 8):
		for x in range(fp.position.x, sim.building.width - 8):
			if zr.size.x == 0 and sim.zones.safe_reject_reason(Rect2i(x, y, 8, 8)) == "":
				zr = Rect2i(x, y, 8, 8)
	var proj = sel.projection
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	sel._zone_click(down, proj.to_screen(Vector2(zr.position) + Vector2(0.5, 0.5)))
	var up: InputEventMouseButton = down.duplicate()
	up.pressed = false
	sel._zone_click(up, proj.to_screen(Vector2(zr.end) - Vector2(0.5, 0.5)))
	# 무전 뒤 조가 가서 설치한다 (P4-4: 설치 시간, 빈 조가 없으면 운전원이 60초 뒤) — 넉넉히 5분
	for i in 3000:
		if sim.zones.has_safe():
			break
		sim.step_ticks(1)
	_check("끌기 → 안전구역 지정 (무전·설치 후)", sim.zones.safe, zr)
	board["zone_casualty"].pressed.emit()
	_check("구역 ▸ 환자 집결지 → 환자 집결지 모드", sel.mode, sel.Mode.ZONE_CASUALTY)
	sel._complete_mode(proj.to_screen(Vector2(zr.get_center())))
	sel.cancel_mode()
	for i in 3000:
		if sim.zones.casualty.x >= 0:
			break
		sim.step_ticks(1)
	_check("클릭 → 환자 집결지", sim.zones.casualty, zr.get_center())
	_check("상황판 구역 줄", world.hud.command_ui.zones_text().begins_with("안전구역 ✓ · 환자 집결지 ✓"), true)
	world.camera.retarget(proj.bounds(sim.building), proj.to_screen(Vector2(zr.get_center())))
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png("user://ui_zones.png")
	# 팀 선택 → 팀 세트 (조 클릭은 고르기만 — 원형 메뉴 없음, P4-5)
	var crew_id := 0
	sel._set_selection([crew_id] as Array[int], [] as Array[int])
	await process_frame
	_check("팀 선택 → 팀 세트 · 카드 보임(오른쪽 정보 창) · 지휘관 명령 묶음도 그대로", [card.set_name, hud._command_panel.is_visible_in_tree(), hud.side_panel.visible, hud.board_groups["report"].is_visible_in_tree()], ["team", true, true, true])
	_check("정보 창과 아래 바가 함께 화면 안에", [hud.get_rect().encloses(hud.console.get_rect()), hud.get_rect().encloses(hud.side_panel.get_rect())], [true, true])
	root.get_texture().get_image().save_png("user://ui_board_team.png")
	_check("팀 4칸 — 임무(인명검색·화재진압)는 층 우클릭 지시 창으로 (2026-11-17)", _labels(card), ["Q 경계", "W 배연", "A 대기", "S 철수"])
	_check("조를 골라도 메뉴가 뜨지 않는다", world.mission_ui.menu.visible, false)
	# A 대기(하위 칸만) → 명령 카드가 하위 칸으로
	world._press_card("A")
	await process_frame
	_check("A 대기 → 하위 칸", [card.parent, _labels(card)[0]], ["standby", "Q 그 자리 대기"])
	_check("A 대기 → S 방수 중지 칸", _labels(card).has("S 방수 중지"), true)
	world._press_card("BACK")
	_check("고르기를 끝내면 첫 칸", card.parent, "")
	# 층 우클릭 → 지시 창: 진압대는 화재진압, 가까운 진입구 → 지시하면 그 문을 거쳐 층 단위 화재진압
	# 차에 탄 분대에게는 지시가 나가지 않는다 (2026-11-17) — 내린 것으로 둔다
	for ff in sim.units.get_crew(crew_id).members():
		ff.aboard = false
	var ent = sim.entries.list[0]
	var mui = world.mission_ui
	var n_issued := sim.issued.size()
	sel.order_floor(ent.level, Vector2(600, 300))
	await process_frame
	_check("층 우클릭 → 지시 창 (화재진압·가까운 진입구)", [mui.order.visible, mui.order_kind, mui.order_entry >= 0], [true, "attack", true])
	var chosen: EntryPoints.Entry = sim.entries.list[mui.order_entry]
	mui.confirm_order()
	var fm := sim.issued.slice(n_issued).filter(func(x): return x.command is CommandOrder and x.command.action == "floor_mission")
	var tcmd = fm.back().command if not fm.is_empty() else null
	_check("지시 → 고른 진입구로 가는 층 단위 화재진압", [str(tcmd.answers.kind) if tcmd else "", int(tcmd.answers.entry) if tcmd else -2], ["attack", chosen.index])
	# 건물 안 조: 시킬 일이 없는 곳을 우클릭하면 아무 지시도 없다 (지휘관도 그대로). 문 앞 목록은 없앴다 (2026-11-17)
	var inner: Opening = null
	for o in sim.fire.openings:
		if inner == null and o.kind == Opening.Kind.DOOR and o.level == 1 and o.room_a >= 0 and o.room_b >= 0:
			inner = o
	var cin := sim.units.get_crew(crew_id)
	sim.tactical.cancel(crew_id)
	for ff in cin.members():
		ff.path.clear()
		ff.level = 1
		ff.pos = Vector2(inner.cells[0]) + Vector2(0.5, 1.5) if sim.building.is_walkable(1, inner.cells[0].x, inner.cells[0].y + 1) else Vector2(inner.cells[0]) + Vector2(1.5, 0.5)
	world.set_view_level(1, false)
	await process_frame
	var n2 := sim.issued.size()
	sel._issue_right_click(sel.projection.to_screen(Vector2(-30.5, -30.5)))
	var after: Array = sim.issued.slice(n2)
	_check("건물 안 조 고른 채 시킬 일 없는 곳 우클릭 → 지시 없음 (지휘관 이동도 없음)", after.size(), 0)
	_check("건물 안 조 = 건물 안", sim.command.interior.crew_inside(crew_id), true)
	sel._right_click_at(sel.projection.to_screen(Vector2(inner.cells[0]) + Vector2(0.5, 0.5), 1.0), Vector2(700, 400))
	await process_frame
	_check("곁의 문 우클릭 → 문 목록 대신 그 층 지시 창 (건물 안이라 진입구 줄 없음)", [mui.menu.visible, mui.order.visible, mui.order_entries.is_empty()], [false, true, true])
	mui.close_order()
	sel.cancel_mode()
	await process_frame
	# 상황 행동 우클릭 (P10-2 결정 ②): 창 → 깨서 열기, 초진 뒤 불 없는 방에 화점진압 → 잔불정리
	var win: Opening = null
	for o in sim.fire.openings:
		if win == null and o.kind == Opening.Kind.WINDOW and o.level == 1 and not o.broken and not o.is_open:
			win = o
	if win:
		sel._set_selection([0] as Array[int], [] as Array[int])
		world.mission_ui.close_menu()
		var n_before := sim.issued.size()
		var wc := Vector2(win.cells[0]) + Vector2(0.5, 0.5)
		# 밖의 분대 우클릭 대상 (진압1 1조는 앞 점검에서 건물 안에 세웠으므로 대상 판정만 바로 부른다)
		sel._issue_target_click(sel.projection.to_screen(wc, 1.2))
		var last_cmd = sim.issued[-1].command if sim.issued.size() > n_before else null
		_check("창 우클릭 → 깨서 열기", last_cmd != null and str(last_cmd.action) == "door_open" and Vector2i(last_cmd.target.x, last_cmd.target.y) == win.cells[0], true)
	var quiet_room: Compartment = null
	for room in sim.fire.comps:
		if quiet_room == null and room.level == 1 and room.cells.size() > 4 and not sim.fire.is_exposure_comp(room):
			var burning := false
			for c in room.cells:
				if sim.fire.grid.state[sim.fire.grid.index(1, c.x, c.y)] == FuelGrid.State.BURNING:
					burning = true
			if not burning:
				quiet_room = room
	if quiet_room:
		# 지시 창의 화재진압은 초진 뒤 그 층에 보이는 불이 없으면 잔불정리로 바뀐다 (층 단위, 2026-11-17)
		var g := sim.fire.grid
		var qc: Vector2i = quiet_room.cells[quiet_room.cells.size() / 2]
		g.fuel[g.index(1, qc.x, qc.y)] = g.fuel0[g.index(1, qc.x, qc.y)] * 0.5
		_check("초진 전에는 화재진압 그대로", sel.overhaul_target(1), Vector3i(-1, -1, -1))
		var burning_before := g.burning.duplicate()
		for i in burning_before:
			g.apply_water(i, 1000.0, 1.0)
		sim.phases.knockdown_tick = sim.clock.tick
		_check("초진 뒤 그 층에 불이 없으면 화재진압 → 잔불정리 (탄 방)", sel.overhaul_target(1).z, 1)
		sim.phases.knockdown_tick = -1
	# 단축키 이벤트로도 같다
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_S
	ev.keycode = KEY_S
	ev.pressed = true
	_check("S 키 = cmd_s", world._card_key(ev), "S")
	# 예전 동작 단축키는 없다
	var old_keys := ["cmd_entry", "cmd_straight", "cmd_fog", "cmd_hose", "cmd_par", "cmd_report"]
	_check("예전 단축키 없음", old_keys.filter(func(a: String) -> bool: return InputMap.has_action(a)), [])
	# 차량 → 차량 세트 (펌프차는 방수포, 물탱크차만 순환보수)
	sel._set_selection([] as Array[int], [0] as Array[int])
	await process_frame
	_check("차량 선택 → 차량 세트", card.set_name, "vehicle")
	_check("펌프차: 방수포 칸 사용", world.hud._card_buttons[1].disabled, not sim.units.get_vehicle(0).is_pump())
	# 선택 해제 → 카드 숨김
	sel._set_selection([] as Array[int], [] as Array[int])
	await process_frame
	_check("선택 해제 → 카드 숨김", [card.set_name, hud._command_panel.visible], ["", false])
	print("결과: %s (실패 %d)" % ["통과" if _failed == 0 else "실패", _failed])
	quit(1 if _failed > 0 else 0)


func _labels(card: CommandCard) -> Array:
	var out: Array = []
	var slots := card.slots()
	for i in slots.size():
		if not slots[i].is_empty():
			out.append("%s %s" % [CommandCard.KEYS[i], str(slots[i].label)])
	return out


func _check(name: String, got: Variant, want: Variant) -> void:
	if got == want:
		print("  통과  %s" % name)
	else:
		_failed += 1
		print("  실패  %s (결과: %s, 기대: %s)" % [name, got, want])
