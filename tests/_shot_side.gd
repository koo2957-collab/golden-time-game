extends SceneTree
## 오른쪽 정보 창 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_side.gd -- 저장폴더
## 2026-11-27: 분대를 고른 상태(조·차량·지휘관)의 오른쪽 창 모습


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
	var crews := sim.units.crews
	world.selection._set_selection([crews[0].id] as Array[int], [] as Array[int], false)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "side_crew.png")
	# 클릭 표시(고리 + 글 · 빨간 X)와 문 강조
	for ff in crews[0].members():
		ff.aboard = false
	var proj = world.projections[world.ViewMode.ISO]
	var sel = world.selection
	var door: Opening = null
	for o in sim.fire.openings:
		if o.kind != Opening.Kind.WINDOW and not o.is_open and o.level == 1 and (o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE):
			door = o
	var dpos: Vector2 = proj.to_screen(Vector2(door.cells[0]) + Vector2(0.5, 0.5), 1.0)
	world.camera.zoom = Vector2(1.6, 1.6)
	world.camera.position = dpos
	for i in 6:
		await process_frame
	# 창문 위에 마우스를 올린다 (우클릭 대상 강조)
	var win: Opening = null
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.WINDOW and not o.broken and not o.is_open and o.level == 1:
			if win == null or proj.to_screen(Vector2(o.cells[0]), 1.5).distance_to(dpos) < proj.to_screen(Vector2(win.cells[0]), 1.5).distance_to(dpos):
				win = o
	var wpos: Vector2 = proj.to_screen(Vector2(win.cells[0]) + Vector2(0.5, 0.5), 1.5)
	var screen: Vector2 = world.selection.get_canvas_transform() * wpos
	root.warp_mouse(screen)
	Input.parse_input_event(_motion(screen))
	for i in 4:
		await process_frame
	sel.ping(dpos + Vector2(40, 150), "인명검색 → 1층", "order")
	sel.ping(dpos + Vector2(-160, 190), "", "move")
	sel.ping(dpos + Vector2(190, 170), "", "bad")
	for i in 5:
		await process_frame
	print("hover obj ", sel._g_obj.get("kind", "없음"), " ", sel._g_obj.get("text", ""))
	root.get_texture().get_image().save_png(out + "ping.png")
	# 아래 바: 묶음을 펼친 모습 (보고 · 안전 · 구역)
	world.selection._set_selection([] as Array[int], [] as Array[int], true)
	for gid in ["report", "safety", "zone"]:
		world.hud.open_board_group(gid)
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png(out + "bar_%s.png" % gid)
	world.hud.open_board_group("")
	for vv in sim.units.vehicles:
		vv.away = false
	world.selection._set_selection([] as Array[int], [sim.units.vehicles[0].id] as Array[int], false)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "side_vehicle.png")
	# 화재진압을 시키고 방수할 때까지 (질문 카드는 '최선'으로 답한다)
	sim.decision_pause = false
	sim.command.strategy = CommandSystem.Strategy.OFFENSIVE
	world.mission_ui.issue_floor_mission("attack", [crews[0].id] as Array[int], 1)
	var flowing := false
	for i in 9000:
		sim.step_ticks(1)
		_answer(sim)
		var h := sim.water.hose_of_crew(crews[0].id)
		if h and h.flowing:
			flowing = true
			break
	print("flowing ", flowing, " tick ", sim.clock.tick)
	sim.step_ticks(60)
	world.hud.card_ui.visible = false
	world.selection._set_selection([crews[0].id] as Array[int], [] as Array[int], false)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "side_spray.png")
	# 다른 조를 고르고 인명검색(Q)을 누른 채 — 대상 고르는 중 깜빡임
	if crews.size() > 1:
		world.selection._set_selection([crews[1].id] as Array[int], [] as Array[int], false)
		world.selection.begin_floor_mission("search")
		for i in 12:
			await process_frame
		root.get_texture().get_image().save_png(out + "side_target.png")
	quit()


func _motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	return e


func _answer(sim: SimWorld) -> void:
	for card in sim.cards.queue.duplicate():
		var pick := 0
		for k in card.options.size():
			if str(card.options[k].get("grade", "")) == "최선":
				pick = k
		sim.cards.answer(card.uid, pick, sim.clock.tick)
