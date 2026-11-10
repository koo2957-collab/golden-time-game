extends SceneTree
## 무전 기록·팀 초상·전술상황판 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_board.gd -- 저장폴더


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
	var sim: SimWorld = world.sim
	sim.clock.paused = false
	for i in 120:
		sim.step_ticks(30)
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_hud.png")
	world.hud.board.toggle()
	world.hud.board.show_level(1)
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_board.png")
	world.hud.board.show_level(-1)
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_board_out.png")
	print("저장 ", out)
	quit()
