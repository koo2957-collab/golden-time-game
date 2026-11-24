extends SceneTree
## 가려진 대원 표시 방식 견본 (점검용, 테스트 목록에 넣지 않음, 2026-11-24):
##   godot --path . -s res://tests/_shot_ghost_style.gd -- 저장폴더
## 같은 장면(연기 찬 1층에서 방수하는 진압대 + 검색하는 구조대)을 네 방식으로 찍는다:
##   outline = 노란 테두리(지금) · silhouette = 출동대 색 실루엣 · badge = 머리 위 표식만 · mix = 실루엣 + 표식


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0] + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/dev_squad_house_fire.json"
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
	sim.decision_pause = false
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
	TestSuite.open_all_doors(sim)
	sim.step_ticks(2400)
	var fire_crew: Crew = null
	var rescue_crew: Crew = null
	for c in sim.units.crews:
		for ff in c.members():
			ff.aboard = false
		var type := str(sim.units.squads[c.squad_id].type)
		if type == "구조대" and rescue_crew == null:
			rescue_crew = c
		elif type == "진압대" and fire_crew == null:
			fire_crew = c
	# 진압대: 복도에 세우고 호스를 쥐여 준 뒤 거실 화재진압 / 구조대: 방1 검색
	for k in fire_crew.members().size():
		var ff: Firefighter = fire_crew.members()[k]
		ff.pos = Vector2(24.5 + k, 12.5)
		ff.prev_pos = ff.pos
		ff.level = 1
		ff.prev_level = 1
		ff.path.clear()
	sim.water.ensure_hose(fire_crew.id, 1, sim.clock.tick)
	TestSuite.fetch_hose(sim, fire_crew.id)
	sim.issue(TacticalCommand.make("attack", [fire_crew.id] as Array[int], Vector3i(14, 16, 1)))
	if rescue_crew:
		for k in rescue_crew.members().size():
			var ff: Firefighter = rescue_crew.members()[k]
			ff.pos = Vector2(28.5, 12.5)
			ff.prev_pos = ff.pos
			ff.level = 1
			ff.prev_level = 1
			ff.path.clear()
		sim.issue(TacticalCommand.make("search", [rescue_crew.id] as Array[int], Vector3i(27, 17, 1)))
	for i in 900:
		sim.step_ticks(1)
		for c in sim.cards.queue.duplicate():
			var best := 0
			for k in c.options.size():
				if c.options[k].grade == "최선":
					best = k
			sim.issue(CommandOrder.make("card_answer", [], best, Vector3i.ZERO, {"uid": c.uid}))
		var h := sim.water.hose_of_crew(fire_crew.id)
		if h != null and h.spraying and i > 150:
			break
	sim.cards.queue.clear()
	world.hud.card_ui.visible = false
	sim.clock.paused = true
	world.set_view_level(1)
	for i in 6:
		await process_frame
	world.camera.zoom = Vector2(2.0, 2.0)
	var mid := fire_crew.leader.pos
	if rescue_crew:
		mid = (mid + rescue_crew.leader.pos) * 0.5
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(mid) + Vector2(0, -40)
	print("fire crew at ", fire_crew.leader.pos, " rescue at ", rescue_crew.leader.pos if rescue_crew else Vector2.ZERO)
	var styles: PackedStringArray = (args[1] if args.size() > 1 else "outline,silhouette,badge,mix").split(",")
	for style: String in styles:
		for l in world.iso_view.layers:
			l.stack.params.ghost_style = style
			l.queue_redraw()
		for i in 10:
			await process_frame
		root.get_texture().get_image().save_png(out + "ghost_%s.png" % style)
	quit()
