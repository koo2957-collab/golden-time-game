extends SceneTree
## F01 단면 보기 다른 층 실루엣 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_ghost.gd -- 저장폴더
## 아파트 4층을 보면서: 아래 3층(불난 방 벽 주황)·2층, 위 5층은 벽 선만, 다른 층 대원은 노란 테두리


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/sop213_1_apartment_3f.json"
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
	for i in 50:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	world.hud.command_ui.close_all()
	# 불이 보이게(아는 불), 대원 둘을 2층·4층 계단 곁에
	sim.perception.enabled = false
	var st := sim.command.stairs
	for spec in [[0, 2], [1, 4], [2, 3]]:
		var c := sim.units.crews[spec[0]]
		var lv: int = spec[1]
		var cell := sim.pathfinder.nearest_walkable(lv, Vector2i(st.center(lv, 0).floor()) + Vector2i(3, 0))
		for ff in c.members():
			ff.path.clear()
			ff.level = lv
			ff.prev_level = lv
			ff.pos = Vector2(cell) + Vector2(0.5, 0.5) + Vector2(0.6 * (ff.id % 2), 0)
			ff.prev_pos = ff.pos
	world.set_view_level(4, false)
	var proj = world.projection()
	world.camera.zoom = Vector2(0.55, 0.55)
	world.camera.retarget(proj.bounds(sim.building), proj.to_screen(Vector2(sim.building.footprint(4).get_center())))
	for i in 40:
		await process_frame
	root.get_texture().get_image().save_png(out + "ghost_view4.png")
	world.camera.zoom = Vector2(1.1, 1.1)
	world.camera.retarget(proj.bounds(sim.building), proj.to_screen(st.center(4, 0)))
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png(out + "ghost_zoom.png")
	print("저장 ", out)
	quit()
