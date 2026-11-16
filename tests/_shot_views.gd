extends SceneTree
## 보기 전환 점검용 캡처 (테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_views.gd -- 저장폴더 [시나리오]
## 외부 보기 / 1층 내부 / 2층 내부 화면을 찍는다 (바깥 대원이 어디에 그려지는지 보기)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = args[1] if args.size() > 1 else "res://data/scenarios/sop213_1_apartment_3f.json"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	world.hud.command_ui.close_all()
	var sim: SimWorld = world.sim
	sim.decision_pause = false
	var d = world.hud.command_ui.dispatch
	d.skip()
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 80:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	for i in 600:
		if not world.camera.locked:
			break
		await process_frame
	world.hud.command_ui.close_all()
	world.hud.card_ui.visible = false
	var first: int = sim.building.levels()[0]
	var shots := [[first, true, "view_ext"], [first, false, "view_1f"], [first + 1, false, "view_2f"]]
	for s: Array in shots:
		world.set_view_level(int(s[0]), bool(s[1]))
		for i in 20:
			await process_frame
		root.get_texture().get_image().save_png(out + str(s[2]) + ".png")
	# 2층 내부 화면: 바깥 대원 위에 마우스 / 바깥 땅 위에 마우스
	var sel = world.selection
	var proj = world.projection()
	var off := Vector2.ZERO
	for spec: Array in world.iso_view.shown_floors():
		if int(spec[0]) == first:
			off = spec[1]
	var c := sim.units.crews[0]
	var at: Vector2 = proj.to_screen(c.leader.pos, proj.pick_height_m) + off
	root.warp_mouse(root.get_canvas_transform() * at)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "hover_crew_2f.png")
	sel._set_selection([c.id] as Array[int], [] as Array[int])
	root.warp_mouse(root.get_canvas_transform() * (at + Vector2(-120, 60)))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "hover_ground_2f.png")
	# 외부 보기: 외벽 3층에 마우스 (분대를 고른 채)
	world.set_view_level(first, true)
	for i in 10:
		await process_frame
	var layer = world.iso_view.layers[0]
	for b in layer._floor_bands():
		if int(b[0]) == first + 2:
			var s: PackedVector2Array = layer._band_polys(float(b[1]), float(b[2]))[0]
			root.warp_mouse(root.get_canvas_transform() * ((s[0] + s[1] + s[2] + s[3]) / 4.0 + layer.position))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "hover_band_ext.png")
	# 팀장 ★·선택 이중 고리 (구조대 분대를 고르고 팀장을 크게)
	for sq in sim.units.squads:
		if sq.type == "구조대" and not sq.crews.is_empty():
			var cr: Crew = sq.crews[0]
			sel._set_selection([cr.id] as Array[int], [] as Array[int])
			var o: Firefighter = cr.officer()
			if o:
				world.camera.zoom = Vector2(1.8, 1.8)
				world.camera.position = proj.to_screen(o.pos, 1.0)
	root.warp_mouse(Vector2(10, 10))
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "officer.png")
	print("저장 ", out)
	quit()
