extends SceneTree
## 방수 장면 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_spray.gd -- 저장폴더
## 2026-11-26: 조준 각도를 0° → 15° → 30° → 45° → 60° 로 바꿔 가며 찍는다 — 관창 방향으로 나가 휘는 물줄기,
## 방향 바꾸기의 여유각(30°에서는 아직 0번 방향, 45°에서 1번), 관창보조가 걸어서 옮겨 가는 모습(바꾼 직후·0.6초 뒤)


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
	var at := Vector2(46.5, 33.5)
	var k := 0
	for ff in crew.members():
		ff.aboard = false
		ff.level = 1
		ff.pos = at + Vector2(-1.2, 0.0) * k
		ff.prev_pos = ff.pos
		ff.path.clear()
		k += 1
	var hose := HoseLine.new()
	hose.id = 900
	hose.vehicle_id = sim.units.vehicles[0].id
	hose.crew_id = crew.id
	hose.flowing = true
	hose.spraying = true
	hose.charged = true
	hose.flow_fraction = 1.0
	hose.pattern = HoseLine.Pattern.STRAIGHT
	hose.points = [Vector3i(40, 33, 1), Vector3i(44, 33, 1), Vector3i(46, 33, 1)] as Array[Vector3i]
	sim.water.hoses.append(hose)
	world.camera.zoom = Vector2(2.2, 2.2)
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(at + Vector2(3.0, 1.5))
	for deg in [0, 15, 30, 45, 60]:
		var aim := at + Vector2.RIGHT.rotated(deg_to_rad(float(deg))) * 8.0
		hose.aim = aim
		hose.impact = aim
		for i in 2:
			await process_frame
		root.get_texture().get_image().save_png(out + "spray_%02d_now.png" % deg)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 600:
			await process_frame
		root.get_texture().get_image().save_png(out + "spray_%02d_later.png" % deg)
		print("spray %d° 방향 %d" % [deg, int(world.iso_view.layers[0]._facing.get(-100000 - crew.id, -1))])
	quit()
