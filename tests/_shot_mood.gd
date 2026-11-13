extends SceneTree
## 화면 분위기 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_mood.gd -- 저장폴더 시나리오경로 이름
## 그 시나리오의 시각(clock)에 맞춰 게임이 스스로 입힌 분위기를 찍는다 (낮은 약하게, 밤은 강하게).


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = args[1] if args.size() > 1 else "res://data/scenarios/tutorial_basics.json"
	gm.realism = "훈련"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	world.hud.command_ui.close_all()
	var sim: SimWorld = world.sim
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 150:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		if i % 5 == 0:
			await process_frame
	world.hud.command_ui.close_all()
	world.hud.card_ui.visible = false
	sim.clock.paused = true
	print("시각 ", sim.scenario.get("clock", ""), " · 분위기 겹 ", world.mood_rect != null)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out + "mood_%s.png" % (args[2] if args.size() > 2 else "shot")
	root.get_texture().get_image().save_png(path)
	print("저장 ", path)
	quit()
