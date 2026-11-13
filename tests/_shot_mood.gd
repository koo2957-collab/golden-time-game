extends SceneTree
## 화면 분위기 시안 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_mood.gd -- 저장폴더
## 같은 장면을 지금 화면과 분위기 셰이더(shaders/mood_grade.gdshader)를 씌운 화면으로 찍는다. 게임에는 아직 넣지 않았다.


func _initialize() -> void:
	_run.call_deferred()


func _shot(path: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("저장 ", path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/tutorial_basics.json"
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
	world.set_view_level(1, false)
	sim.clock.paused = true
	await _shot(out + "mood_0_now.png")
	var layer := CanvasLayer.new()
	layer.layer = 0
	world.add_child(layer)
	world.move_child(layer, world.get_node("UI").get_index())
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mood_grade.gdshader")
	rect.material = mat
	layer.add_child(rect)
	await _shot(out + "mood_1_grade.png")
	quit()
