extends SceneTree
## P4-5 안내 흐름 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_guide.gd -- 저장폴더 [시나리오]
## 밖의 조 선택 → 진입구 노랗게 / 외부 보기 층 띠 노랗게 / 층 단면 방 노랗게 / 임무 고르기 목록


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
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 60:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	world.hud.command_ui.close_all()
	var sel = world.selection
	var c := sim.units.crews[0]
	sel._set_selection([c.id] as Array[int], [] as Array[int])
	world.set_view_level(sim.building.levels()[0], true)
	var e: EntryPoints.Entry = sim.entries.list[0]
	var proj = world.projection()
	world.camera.zoom = Vector2(1.0, 1.0)
	world.camera.retarget(proj.bounds(sim.building), proj.to_screen(Vector2(e.door)))
	for i in 4:
		await process_frame
	# 1) 진입구 위에 마우스
	root.warp_mouse(root.get_canvas_transform() * proj.to_screen(Vector2(e.door) + Vector2(0.5, 0.5), 1.0))
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out + "guide_1_entry.png")
	# 2) 외부 보기 3층 띠 위에 마우스
	var layer = world.iso_view.layers[0]
	var target_lv := sim.building.levels()[0] + 2
	var band: Array = []
	for b in layer._floor_bands():
		if int(b[0]) == target_lv:
			band = b
	if not band.is_empty():
		var polys: Array = layer._band_polys(float(band[1]), float(band[2]))
		var s: PackedVector2Array = polys[0]
		var mid := (s[0] + s[1] + s[2] + s[3]) / 4.0
		world.camera.retarget(proj.bounds(sim.building), mid)
		for i in 3:
			await process_frame
		root.warp_mouse(root.get_canvas_transform() * (mid + layer.position))
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(out + "guide_2_floor.png")
	# 3) 그 층 단면: 진입을 지시한 조라 방이 노랗게
	sim.issue(CommandOrder.make("floor", [c.id] as Array[int], target_lv, Vector3i.ZERO, {"entry": e.index}))
	sim.step_ticks(2)
	sim.perception.enabled = false
	world.set_view_level(target_lv, false)
	var room: Compartment = null
	for comp in sim.fire.comps:
		if comp.level == target_lv and comp.cells.size() > 12 and room == null:
			room = comp
	if room:
		var rc := Vector2(room.rect.get_center())
		world.camera.retarget(proj.bounds(sim.building), proj.to_screen(rc))
		for i in 3:
			await process_frame
		root.warp_mouse(root.get_canvas_transform() * proj.to_screen(rc, 0.05))
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(out + "guide_3_room.png")
		world.mission_ui.open_room_menu([c.id] as Array[int], Vector3i(int(rc.x), int(rc.y), target_lv), e.outside, root.get_canvas_transform() * proj.to_screen(rc, 0.05))
		for i in 3:
			await process_frame
		root.get_texture().get_image().save_png(out + "guide_4_menu.png")
	print("저장 ", out)
	quit()
