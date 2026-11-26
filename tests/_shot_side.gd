extends SceneTree
## 오른쪽 정보 창 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_side.gd -- 저장폴더
## 2026-11-27: 분대를 고른 상태(조·차량·지휘관)의 오른쪽 창 모습


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0] + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/sop214_1_day_living.json"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.hud.command_ui.close_all()
	world.hud.card_ui.pauses = Callable()
	world.hud.card_ui.visible = false
	var sim: SimWorld = world.sim
	var d = world.hud.command_ui.dispatch
	d.answer_rest()
	d.skip()
	for i in 900:
		if not d.active and not world.camera.locked:
			break
		await process_frame
	for i in 4000:
		if not sim.command.resources.arriving_now():
			break
		sim.step_ticks(5)
	sim.cards.queue.clear()
	world.hud.card_ui.visible = false
	var crews := sim.units.crews
	world.selection._set_selection([crews[0].id] as Array[int], [] as Array[int], false)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "side_crew.png")
	for vv in sim.units.vehicles:
		vv.away = false
	world.selection._set_selection([] as Array[int], [sim.units.vehicles[0].id] as Array[int], false)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "side_vehicle.png")
	# 화재진압을 시키고 방수할 때까지 (질문 카드는 '최선'으로 답한다)
	sim.decision_pause = false
	sim.command.strategy = CommandSystem.Strategy.OFFENSIVE
	world.mission_ui.issue_floor_mission("attack", [crews[0].id] as Array[int], 1)
	var flowing := false
	for i in 9000:
		sim.step_ticks(1)
		_answer(sim)
		var h := sim.water.hose_of_crew(crews[0].id)
		if h and h.flowing:
			flowing = true
			break
	print("flowing ", flowing, " tick ", sim.clock.tick)
	sim.step_ticks(60)
	world.hud.card_ui.visible = false
	world.selection._set_selection([crews[0].id] as Array[int], [] as Array[int], false)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "side_spray.png")
	# 다른 조를 고르고 인명검색(Q)을 누른 채 — 대상 고르는 중 깜빡임
	if crews.size() > 1:
		world.selection._set_selection([crews[1].id] as Array[int], [] as Array[int], false)
		world.selection.begin_floor_mission("search")
		for i in 12:
			await process_frame
		root.get_texture().get_image().save_png(out + "side_target.png")
	quit()


func _answer(sim: SimWorld) -> void:
	for card in sim.cards.queue.duplicate():
		var pick := 0
		for k in card.options.size():
			if str(card.options[k].get("grade", "")) == "최선":
				pick = k
		sim.cards.answer(card.uid, pick, sim.clock.tick)
