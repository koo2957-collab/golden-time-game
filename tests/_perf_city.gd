extends SceneTree
## 도시 그리기 부담 재기 (점검용): 원경·근경에서 도시를 켰을 때와 껐을 때의 프레임 시간


func _initialize() -> void:
	_run.call_deferred()


func _avg_ms(frames: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / frames


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/" + (args[0] if not args.is_empty() else "sop214_2_night_upstairs.json")
	gm.skip_menu = true
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 20:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.hud.command_ui.close_all()
	world.hud.card_ui.visible = false
	world.sim.clock.paused = true
	var far: float = world.city.plan.overview_zoom(root.get_visible_rect().size.x)
	for z: float in [far, 0.5, 0.75]:
		world.camera.zoom = Vector2(z, z)
		world.city.visible = true
		for i in 10:
			await process_frame
		var on: float = await _avg_ms(120)
		world.city.visible = false
		for i in 10:
			await process_frame
		var off: float = await _avg_ms(120)
		print("PERF zoom %.3f  city on %.2f ms  off %.2f ms  (quads %d)" % [z, on, off, world.city.quad_count])
	print("PERF adapter ", RenderingServer.get_video_adapter_name())
	quit()
