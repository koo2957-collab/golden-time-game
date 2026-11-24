extends SceneTree
## 경계 관창 견본 (점검용, 테스트 목록에 넣지 않음, 2026-11-24): godot --path . -s res://tests/_shot_exterior.gd -- 저장폴더
## 진압1이 지상에서 2층 창을 겨눠 올려 쏘는 모습 (외부 화면) — ① 배치(잠근 채) ② 창에서 불꽃이 나와 개방


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
	for v in sim.units.vehicles:
		v.away = false
	var crew: Crew = sim.units.crews[0]
	for ff in crew.members():
		ff.aboard = false
	# 보는 쪽(남·동)으로 난 2층 바깥 창
	var win: Opening = null
	for o in sim.fire.openings:
		if o.level != 2 or o.kind != Opening.Kind.WINDOW or o.room_b != Opening.OUTSIDE or sim.fire.is_exposure_comp(sim.fire.comps[o.room_a]):
			continue
		var c0 := o.cells[0]
		if sim.building.cell(2, c0.x, c0.y + 1) in BuildingData.OUTDOOR or sim.building.cell(2, c0.x + 1, c0.y) in BuildingData.OUTDOOR:
			win = o
			break
	if win == null:
		print("2층 남·동 창 없음")
		quit()
		return
	var cell := win.cells[0]
	sim.issue(TacticalCommand.make("exterior", [crew.id] as Array[int], Vector3i(cell.x, cell.y, 2)))
	sim.step_ticks(1)
	TestSuite.fetch_hose(sim, crew.id, false)
	for i in 1200:
		if not crew.leader.is_moving():
			break
		sim.step_ticks(1)
	sim.step_ticks(20)
	var h := sim.water.hose_of_crew(crew.id)
	print("standby=", h.standby, " flowing=", h.flowing, " exterior=", h.exterior, " pos=", crew.leader.pos, " target=", h.target)
	world.camera.zoom = Vector2(1.6, 1.6)
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(Vector2(cell) + Vector2(1.0, 4.0)) + Vector2(0, -120)
	sim.clock.paused = true
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "exterior_1_standby.png")
	sim.clock.paused = false
	win.broken = true
	win.is_open = true
	for dd: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]:
		if sim.fire.compartment_at(2, cell.x + dd.x, cell.y + dd.y) != null:
			sim.fire.ignite(Vector3i(cell.x + dd.x, cell.y + dd.y, 2))
			break
	for i in 400:
		sim.step_ticks(1)
		if h.spraying:
			break
	sim.step_ticks(10)
	print("after: flowing=", h.flowing, " spraying=", h.spraying, " impact=", h.impact)
	sim.clock.paused = true
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "exterior_2_open.png")
	quit()
