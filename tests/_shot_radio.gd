extends SceneTree
## 무전 장면 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_radio.gd -- 저장폴더 [실전]
## 튜토리얼에서 진압1 1조에게 거실 화재진압을 지시하고, 진입 허가 요청 무전이 뜬 화면과 답한 직후 화면을 찍는다.


func _initialize() -> void:
	_run.call_deferred()


func _shot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("저장 ", path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/tutorial_basics.json"
	gm.realism = "실전" if "실전" in args else "훈련"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	world.hud.command_ui.close_all()
	var sim: SimWorld = world.sim
	sim.clock.paused = false
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	sim.issue(CommandOrder.make("declare", [], 0, Vector3i.ZERO, {
		"fire": "연기만 확인", "victims": "있음", "use": "단독주택", "floors": "2층", "structure": "벽돌조", "hazards": [],
		"activities": ["인명검색", "내부 진입 진압"], "strategy": CommandSystem.Strategy.OFFENSIVE, "support": "불필요", "access": "진입 가능, 회차 불가"}))
	for i in 30:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	world.hud.command_ui.close_all()
	world.set_view_level(1, false)
	sim.issue(TacticalCommand.make("attack", [0] as Array[int], Vector3i(12, 17, 1)))
	# 진입 허가 요청 무전이 뜰 때까지 (다른 무전은 최선으로 답해 넘긴다)
	var card_ui = world.hud.card_ui
	var found := false
	for i in 4000:
		sim.step_ticks(2)
		var c := sim.cards.active()
		if c != null:
			if c.id == ("NOZZLE-01" if "judgment" in args else CommandOrder.ENTRY_CARD):
				found = true
				break
			var best := 0
			for k in c.options.size():
				if str(c.options[k].get("grade", "")) == "최선":
					best = k
			sim.issue(CommandOrder.make("card_answer", [], best, Vector3i.ZERO, {"uid": c.uid}))
		if i % 20 == 0:
			await process_frame
	print("진입 허가 무전: ", found, " · 현장 시간 ", roundi(sim.clock.tick * SimClock.TICK_DT), "초")
	for i in 20:
		await process_frame
	print("장면 열림 ", card_ui.scene_open(), " · 시간 멈춤 ", sim.clock.paused, " · 방식 ", sim.realism)
	if "judgment" in args:
		await _shot(out + "judgment_scene.png")
		quit()
		return
	await _shot(out + "radio_1_scene.png")
	var t0 := sim.clock.tick
	for i in 30:
		await process_frame
	print("장면이 떠 있는 동안 흐른 틱: ", sim.clock.tick - t0)
	# '진입 허가'를 고른다
	var c2: CardSystem.Card = card_ui.current()
	var pick := 0
	for k in c2.options.size():
		if str(c2.options[k].get("effect", "")) == "entry_grant":
			pick = k
	card_ui.choose(pick)
	for i in 30:
		await process_frame
	print("답한 뒤: 장면 열림 ", card_ui.scene_open(), " · 시간 멈춤 ", sim.clock.paused, " · 진입 명령 ", sim.events.of_type("entry_ordered").size())
	await _shot(out + "radio_2_after.png")
	quit()
