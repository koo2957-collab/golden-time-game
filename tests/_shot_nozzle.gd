extends SceneTree
## 바닥에 놓인 관창 견본 (점검용, 테스트 목록에 넣지 않음, 2026-11-25): godot --path . -s res://tests/_shot_nozzle.gd -- 저장폴더
## 관창을 놓고 떠난 수관(dropped)을 바깥 땅에 깔아 두고 호스가 오는 방향 넷(동·남·서·북)과 물이 찬 것·안 찬 것을 찍는다.
## 시계를 멈추고 상태를 손으로 만든다 — 실제 진행 화면이 아니라 견본이다.


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
	var crew: Crew = sim.units.crews[0]
	var end_cell := Vector2i(46, 33)
	var hose := HoseLine.new()
	hose.id = 901
	hose.vehicle_id = sim.units.vehicles[0].id
	hose.crew_id = crew.id
	hose.dropped = true
	sim.water.hoses.append(hose)
	# 조는 멀리 비켜 세운다 (관창을 놓고 떠났다)
	for ff in crew.members():
		ff.aboard = false
		ff.level = 1
		ff.pos = Vector2(end_cell) + Vector2(-6.0, -8.0)
		ff.prev_pos = ff.pos
		ff.path.clear()
	world.camera.zoom = Vector2(3.0, 3.0)
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(Vector2(end_cell) + Vector2(0.5, 0.5))
	var dirs := {"from_west": Vector2i(-1, 0), "from_north": Vector2i(0, -1), "from_east": Vector2i(1, 0), "from_south": Vector2i(0, 1), "from_nw": Vector2i(-1, -1)}
	for name: String in dirs:
		var step: Vector2i = dirs[name]
		hose.points.clear()
		for s in range(8, -1, -1):
			var c := end_cell + step * s
			hose.points.append(Vector3i(c.x, c.y, 1))
		for wet in [false, true]:
			hose.charged = wet
			hose.water_head = 9999.0 if wet else 0.0
			for i in 6:
				await process_frame
			root.get_texture().get_image().save_png(out + "nozzle_%s%s.png" % [name, "_wet" if wet else "_dry"])
	print("찍음")
	quit()
