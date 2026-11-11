extends SceneTree
## F01 2층 주택 층 배치 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_house.gd -- 저장폴더


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/sop214_2_night_upstairs.json"
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
	var n := int(args[1]) if args.size() > 1 else 40
	for i in n:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	world.hud.command_ui.close_all()
	sim.perception.enabled = false
	# 대원 한 조를 불난 층(맨 위층) 가운데로 — 연기에 묻힌 테두리 점검
	var top_lv: int = sim.building.levels()[-1]
	var mid := Vector2i(sim.building.footprint(top_lv).get_center())
	var cell := sim.pathfinder.nearest_walkable(top_lv, mid)
	for ff in sim.units.crews[0].members():
		ff.path.clear()
		ff.level = top_lv
		ff.prev_level = top_lv
		ff.pos = Vector2(cell) + Vector2(0.5, 0.5) + Vector2(0.7 * (ff.id % 2), 0.3)
		ff.prev_pos = ff.pos
	var levels: Array = sim.building.levels()
	var proj = world.projection()
	var iso = world.iso_view if "iso_view" in world else world.get_node("IsoView")
	var fp: Rect2i = sim.building.footprint(levels[0])
	print("집 바닥 칸: ", fp)
	# 배치 후보: [이름, 뒤로 비율, 위로 px]
	var opts := [["cur", iso.params.stagger_back_ratio, iso.params.stagger_floor_px]]
	for o: Array in opts:
		iso.params.stagger_back_ratio = o[1]
		iso.params.stagger_floor_px = o[2]
		iso.stack = FloorStack.new(sim.building, iso.params)
		for node in iso.layers + iso.upper_layers + [iso.current_live, iso.partner_live]:
			node.stack = iso.stack
		for lv: int in levels:
			world.set_view_level(lv, false)
			world.camera.zoom = Vector2(0.6, 0.6)
			world.camera.retarget(proj.bounds(sim.building), proj.to_screen(Vector2(fp.get_center())) + Vector2(0, -120))
			for i in 30:
				await process_frame
			root.get_texture().get_image().save_png(out + "house_%s_f%d.png" % [o[0], lv])
			# 연기층 확대 (불난 2층)
			world.camera.zoom = Vector2(1.2, 1.2)
			world.camera.retarget(proj.bounds(sim.building), proj.to_screen(Vector2(fp.get_center())) + iso.layers[0].position)
			for i in 30:
				await process_frame
			root.get_texture().get_image().save_png(out + "house_%s_f%d_zoom.png" % [o[0], lv])
	quit()
