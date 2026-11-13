extends SceneTree
## 무전 장면 점검 (창이 열린다, 2026-11-14): 진입 허가 요청 무전이 화면 가운데에 말하는 사람과 함께 뜨는지,
## 훈련 방식은 그동안 시간이 멈추고 고른 직후 등급 한 줄이 뜨는지, 실전 방식은 멈추지 않고 등급을 보여 주지 않는지.
## 사용: godot --path . -s res://tests/ui_radio.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _play("훈련")
	await _play("실전")
	print("결과: %s (실패 %d)" % ["통과" if _failed == 0 else "실패", _failed])
	quit(1 if _failed > 0 else 0)


func _play(realism: String) -> void:
	print("── %s ──" % realism)
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/tutorial_basics.json"
	gm.realism = realism
	gm.skip_menu = true
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var world = main.get_node("World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	world.hud.command_ui.close_all()
	var sim: SimWorld = world.sim
	sim.clock.paused = false
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 30:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	world.hud.command_ui.close_all()
	sim.clock.paused = false
	sim.issue(TacticalCommand.make("attack", [0] as Array[int], Vector3i(12, 17, 1)))
	var ui = world.hud.card_ui
	var found := false
	for i in 4000:
		sim.step_ticks(2)
		var c := sim.cards.active()
		if c != null:
			if c.id == CommandOrder.ENTRY_CARD:
				found = true
				break
			# 다른 무전은 최선으로 답해 넘긴다
			var best := 0
			for k in c.options.size():
				if str(c.options[k].get("grade", "")) == "최선":
					best = k
			sim.issue(CommandOrder.make("card_answer", [], best, Vector3i.ZERO, {"uid": c.uid}))
		if i % 25 == 0:
			await process_frame
	_check("진입 허가 요청 무전이 온다", found, true)
	for i in 10:
		await process_frame
	var card: CardSystem.Card = ui.current()
	if card == null:
		_check("무전 장면이 뜬다", false, true)
		main.free()
		return
	_check("무전 장면이 뜬다", [ui.scene_open(), ui._panel.visible], [true, true])
	var sp: Dictionary = ui.speaker(sim, card)
	var leader_name: String = sim.units.get_crew(card.crew_id).leader.name
	_check("말하는 사람: 진압1 1조 조장", str(sp.name).begins_with("진압1 1조") and str(sp.name).contains(leader_name), true)
	_check("말하는 사람 그림 (진압대)", [str(sp.portrait), ui._portrait.texture != null], ["res://art/portraits/crew_fire.png", true])
	_check("무전 내용에서 이름표를 뗀다", [ui._text.text.contains("진압1 1조:"), ui._text.text.contains("진입 허가 요청")], [false, true])
	var cx: float = ui.size.x * 0.5
	_check("화면 정가운데 (먹물 바탕 장면)", absf(ui._panel.position.x + ui._panel.size.x * ui._panel.scale.x * 0.5 - cx) < 4.0 and ui._panel.position.y >= 20.0, true)
	_check("선택 단추가 선택지 수만큼", ui._buttons.filter(func(b): return b.visible).size(), card.options.size())
	var t0 := sim.clock.tick
	for i in 20:
		await process_frame
	var pick := 0
	for k in card.options.size():
		if str(card.options[k].get("effect", "")) == "entry_grant":
			pick = k
	if realism == "훈련":
		_check("훈련: 장면이 떠 있는 동안 시간이 멈추고 뒤 화면 조작을 막는다", [sim.clock.paused, sim.clock.tick - t0, ui._shade.mouse_filter == Control.MOUSE_FILTER_STOP], [true, 0, true])
	else:
		_check("실전: 멈추지 않고 뒤 화면 조작 가능", [sim.clock.paused, sim.clock.tick > t0, ui._shade.mouse_filter == Control.MOUSE_FILTER_IGNORE], [false, true, true])
		# 제한 시간 없음 (2026-11-14): 오래 두어도 장면이 사라지지 않는다
		sim.step_ticks(roundi(60.0 / SimClock.TICK_DT))
		for i in 5:
			await process_frame
		_check("실전: 1분을 두어도 장면이 남아 있다", [ui.current() != null and ui.current().uid == card.uid, card.deadline_tick < 0], [true, true])
	if ui.current() == null:
		_check("아직 떠 있다", false, true)
		main.free()
		return
	var want: String = ui.feedback_text(card, pick)
	ui.choose(pick)
	_check("고르면 바로 장면이 닫힌다", ui.current() == null, true)
	for i in 20:
		await process_frame
	_check("답이 실행된다 (진입 명령)", sim.events.of_type("entry_ordered").size() >= 1, true)
	_check("장면이 닫히고 시간이 다시 흐른다", [ui.scene_open(), sim.clock.paused], [false, false])
	if realism == "훈련":
		_check("훈련: 고른 직후 등급 한 줄", [ui._feedback_box.visible, ui._feedback.text == want, want.contains("—")], [true, true, true])
	else:
		_check("실전: 등급을 보여 주지 않는다", ui._feedback_box.visible, false)
	main.free()
	for i in 5:
		await process_frame


func _check(name: String, got: Variant, want: Variant) -> void:
	if got == want:
		print("  통과  %s" % name)
	else:
		_failed += 1
		print("  실패  %s (결과: %s, 기대: %s)" % [name, got, want])
