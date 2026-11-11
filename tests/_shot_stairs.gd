extends SceneTree
## P4-5 계단 고르기 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_stairs.gd -- 저장폴더
## 계단이 둘인 지하 노래방: 안의 조에게 지하 1층 → 대원이 묻는다 → 두 계단이 노랗게 (급기측·배기측)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/stage3_2_basement.json"
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
	for i in 40:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	world.hud.command_ui.close_all()
	for o in sim.fire.openings:
		o.is_open = true
	sim.doors.sync_blocking()
	sim.command.interior.plan_known = true
	sim.exposure.wind_mps = 3.0
	var st := sim.command.stairs
	var lv: int = sim.building.levels()[0]
	var c := sim.units.crews[0]
	var near := sim.pathfinder.nearest_walkable(lv, Vector2i(((st.center(lv, 0) + st.center(lv, 1)) * 0.5).floor()))
	for ff in c.members():
		ff.path.clear()
		ff.level = lv
		ff.pos = Vector2(near) + Vector2(0.5, 0.5)
	world.selection._set_selection([c.id] as Array[int], [] as Array[int])
	sim.issue(CommandOrder.make("floor", [c.id] as Array[int], lv + 1))
	for i in 300:
		sim.step_ticks(1)
		if sim.command.stair_asks.has(c.id):
			break
		if i % 10 == 0:
			await process_frame
	for i in 6:
		await process_frame
	var proj = world.projection()
	world.camera.zoom = Vector2(0.9, 0.9)
	world.camera.retarget(proj.bounds(sim.building), proj.to_screen((st.center(lv, 0) + st.center(lv, 1)) * 0.5))
	root.warp_mouse(root.get_canvas_transform() * proj.to_screen(st.center(lv, 1), 0.05))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "stairs_ask.png")
	print("묻는 중 ", sim.command.stair_asks.has(c.id), " 저장 ", out)
	quit()
