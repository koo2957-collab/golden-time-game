extends SceneTree
## 호스 끼고 걷기 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_carry.gd -- 저장폴더
## 2026-11-26: 셋이 호스를 끼고 동쪽으로 걷는 모습 (1번 → 2번 → 3번으로 호스가 이어지고 3번 뒤에서 바닥으로)


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
	var crew: Crew = null
	for c in sim.units.crews:
		if crew == null and c.workers().size() >= 3:
			crew = c
	var at := Vector2(46.5, 33.5)
	var ws := crew.workers()
	for ff in crew.members():
		ff.aboard = false
		ff.level = 1
		ff.path.clear()
	for k in ws.size():
		ws[k].pos = at + Vector2(-1.1, 0.0) * k
		ws[k].prev_pos = ws[k].pos - Vector2(0.05, 0.0)
	var hose := HoseLine.new()
	hose.id = 900
	hose.vehicle_id = sim.units.vehicles[0].id
	hose.crew_id = crew.id
	var pts: Array[Vector3i] = []
	for x in range(30, 47):
		pts.append(Vector3i(x, 33, 1))
	hose.points = pts
	sim.water.hoses.append(hose)
	for l in world.iso_view.layers:
		l._facing[crew.leader.id] = 0
	world.camera.zoom = Vector2(2.2, 2.2)
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(at + Vector2(-1.0, 0.5))
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "carry3.png")
	print("carry3 crew ", sim.units.crew_name(crew), " workers ", ws.size())
	quit()
