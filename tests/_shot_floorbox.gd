extends SceneTree
## 층 가리키기 테두리 캡처 (점검용): godot --path . -s res://tests/_shot_floorbox.gd -- 저장폴더
## 2026-11-26: 내부 화면에서 분대를 고르고 지금 층(1층)을 가리킨 상태 — 바닥선 대신 외벽 상자 테두리


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
	sim.clock.paused = true
	world.iso_view.show_view(1, false, false)
	for i in 30:
		await process_frame
	world.selection._set_selection([sim.units.crews[0].id] as Array[int], [] as Array[int], false)
	# 마우스 위치로 가리킴을 다시 정하지 않게 멈춘 뒤 '1층을 가리킴'을 넣는다
	world.selection.set_process(false)
	world.selection._g_room = world.selection.level
	world.selection.queue_redraw()
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "floorbox.png")
	print("floorbox level ", world.selection.level)
	quit()
