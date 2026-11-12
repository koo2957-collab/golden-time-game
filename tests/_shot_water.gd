extends SceneTree
## 점검용 (테스트 목록에 넣지 않음): 물줄기 그림 — 한 조는 직사, 한 조는 분무로 쏘는 장면을 찍는다
## godot --path . -s res://tests/_shot_water.gd -- 저장폴더


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/tutorial_basics.json"
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
	for i in 12:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	world.hud.command_ui.close_all()
	sim.perception.enabled = false
	sim.clock.paused = true
	# 두 조를 1층 실내에 세우고 수관을 깔아 물을 쏘는 상태로 만든다 (그림 점검용 — 시뮬레이션 규칙을 건너뛴다)
	var spots := [[Vector2(16.5, 16.5), Vector2(12.5, 12.5), HoseLine.Pattern.STRAIGHT], [Vector2(22.5, 16.5), Vector2(26.5, 12.5), HoseLine.Pattern.FOG]]
	for k in 2:
		var crew: Crew = sim.units.crews[k]
		var members := crew.members()
		for i in members.size():
			var ff: Firefighter = members[i]
			ff.path.clear()
			ff.level = 1
			ff.prev_level = 1
			ff.pos = spots[k][0] + Vector2(0.6 * i, 0.4 * i)
			ff.prev_pos = ff.pos
		var h := HoseLine.new()
		h.id = sim.water.hoses.size()
		h.vehicle_id = sim.units.vehicles[0].id
		h.crew_id = crew.id
		h.points = [crew.leader.cell3()] as Array[Vector3i]
		sim.water.hoses.append(h)
		h.flowing = true
		h.approaching = false
		h.flow_fraction = 1.0
		h.pattern = spots[k][2]
		h.aim = spots[k][1]
		h.impact = spots[k][1]
	var proj = world.projection()
	world.set_view_level(1, false)
	world.camera.zoom = Vector2(1.3, 1.3)
	world.camera.retarget(proj.bounds(sim.building), proj.to_screen(Vector2(19.5, 14.5)))
	for i in 30:
		await process_frame
	world.hud.command_ui.close_all()
	root.get_texture().get_image().save_png(out + "water.png")
	quit()
