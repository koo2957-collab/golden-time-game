extends SceneTree
## P10-2 명령 카드 점검 (창이 열린다): 원형 메뉴와 명령 카드 항목·단축키 일치, 선택 해제 → 지휘관 세트,
## 하위 칸 펼치기·Esc 뒤로, 예전 동작 단축키 없음, 좌클릭 → 원형 메뉴
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
	# 선택 없음 = 지휘관 명령
	sel._set_selection([] as Array[int], [] as Array[int])
	await process_frame
	_check("선택 없음 → 지휘관 세트", card.set_name, "commander")
	_check("지휘관 6칸", _labels(card), _expected(sets.commander))
	_check("카드 버튼 글자 = Q 전략 변경", world.hud._card_buttons[0].text.begins_with("Q  전략 변경"), true)
	# 지휘관 Q → 하위 칸 (실행 없이 펼침), Esc 뒤로
	world._press_card("Q")
	_check("Q 전략 변경 → 하위 칸", card.parent, "strategy_menu")
	_check("하위 칸 이름", _labels(card), ["Q 선언·전략", "W 선제지시"])
	world._press_card("BACK")
	_check("뒤로 → 첫 칸", card.parent, "")
	# 구역 지정 (P10-2 ⓑ): A 구역 지정 → Q 안전구역 → 끌기 → 무전 → 지정, W 환자 집결지 클릭
	world._press_card("A")
	world._press_card("Q")
	_check("A → Q → 안전구역 모드", sel.mode, sel.Mode.ZONE_SAFE)
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
	for i in 600:
		if sim.zones.has_safe():
			break
		sim.step_ticks(1)
	_check("끌기 → 안전구역 지정 (무전 후)", sim.zones.safe, zr)
	world._press_card("A")
	world._press_card("W")
	_check("A → W → 환자 집결지 모드", sel.mode, sel.Mode.ZONE_CASUALTY)
	sel._complete_mode(proj.to_screen(Vector2(zr.get_center())))
	sel.cancel_mode()
	for i in 600:
		if sim.zones.casualty.x >= 0:
			break
		sim.step_ticks(1)
	_check("클릭 → 환자 집결지", sim.zones.casualty, zr.get_center())
	_check("상황판 구역 줄", world.hud.command_ui.zones_text().begins_with("안전구역 ✓ · 환자 집결지 ✓"), true)
	world.camera.retarget(proj.bounds(sim.building), proj.to_screen(Vector2(zr.get_center())))
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png("user://ui_zones.png")
	# 팀 선택 → 팀 세트, 원형 메뉴 = 명령 카드
	var crew_id := 0
	sel._set_selection([crew_id] as Array[int], [] as Array[int])
	await process_frame
	_check("팀 선택 → 팀 세트", card.set_name, "team")
	_check("팀 6칸 (기획안 9-1)", _labels(card), ["Q 인명검색", "W 화점진압", "E 경계", "R 배연", "A 대기", "S 철수"])
	sel.crew_menu.emit(crew_id, Vector2(600, 400))
	await process_frame
	var radial = world.mission_ui.radial
	_check("조 클릭 → 원형 메뉴", radial.visible, true)
	var radial_labels: Array = []
	for it: Dictionary in radial.items:
		radial_labels.append(str(it.label))
	_check("원형 메뉴 항목·단축키 = 명령 카드", radial_labels, _labels(card))
	# 원형 메뉴에서 A 대기(하위 칸만) → 그 자리에서 하위 메뉴
	radial.pick("A")
	await process_frame
	_check("원형 메뉴 A 대기 → 하위 칸", card.parent, "standby")
	_check("원형 메뉴가 하위 칸으로 다시 열림", radial.visible and str(radial.items[0].label) == "Q 그 자리 대기", true)
	radial.close()
	world._press_card("BACK")
	# W 화점진압: 대상 고르기 + 세부 동작 칸
	world._press_card("W")
	_check("W → 화점진압 대상 고르기", sel.mode, sel.Mode.ATTACK)
	_check("W → 하위 칸 없음 (주수 방법은 카드로, P10-2 결정 ②)", card.parent, "")
	sel.cancel_mode()
	await process_frame
	world._press_card("A")
	_check("A 대기 → S 방수 중지 칸", _labels(card).has("S 방수 중지"), true)
	world._press_card("BACK")
	_check("고르기를 끝내면 첫 칸", card.parent, "")
	# 상황 행동 우클릭 (P10-2 결정 ②): 창 → 깨서 열기, 초진 뒤 불 없는 방에 화점진압 → 잔불정리
	var win: Opening = null
	for o in sim.fire.openings:
		if win == null and o.kind == Opening.Kind.WINDOW and o.level == 1 and not o.broken and not o.is_open:
			win = o
	if win:
		sel._set_selection([0] as Array[int], [] as Array[int])
		world.mission_ui.radial.close()
		var n_before := sim.issued.size()
		var wc := Vector2(win.cells[0]) + Vector2(0.5, 0.5)
		sel._issue_crew_right_click(sel.projection.to_screen(wc, 1.2))
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
		var qc: Vector2i = quiet_room.cells[quiet_room.cells.size() / 2]
		_check("초진 전에는 화점진압", sel._overhaul_room(Vector3i(qc.x, qc.y, 1)), false)
		sim.phases.knockdown_tick = sim.clock.tick
		_check("초진 뒤 불 없는 방에 화점진압 → 잔불정리", sel._overhaul_room(Vector3i(qc.x, qc.y, 1)), true)
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
	# 선택 해제 → 다시 지휘관
	sel._set_selection([] as Array[int], [] as Array[int])
	await process_frame
	_check("선택 해제 → 지휘관 세트", card.set_name, "commander")
	print("결과: %s (실패 %d)" % ["통과" if _failed == 0 else "실패", _failed])
	quit(1 if _failed > 0 else 0)


func _labels(card: CommandCard) -> Array:
	var out: Array = []
	var slots := card.slots()
	for i in slots.size():
		if not slots[i].is_empty():
			out.append("%s %s" % [CommandCard.KEYS[i], str(slots[i].label)])
	return out


func _expected(list: Array) -> Array:
	var out: Array = []
	for it: Dictionary in list:
		out.append("%s %s" % [str(it.key), str(it.label)])
	return out


func _check(name: String, got: Variant, want: Variant) -> void:
	if got == want:
		print("  통과  %s" % name)
	else:
		_failed += 1
		print("  실패  %s (결과: %s, 기대: %s)" % [name, got, want])
