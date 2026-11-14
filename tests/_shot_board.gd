extends SceneTree
## 전술상황판(화이트보드) 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_board.gd -- 저장폴더
## 기호가 모두 보이도록 보고 내용(KnowledgeBoard)을 손으로 채운다 — 실제 진행 화면이 아니라 기호 견본이다.


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
	# 무전 장면이 상황판을 가리지 않게 끈다
	world.hud.card_ui.pauses = Callable()
	world.hud.card_ui.visible = false
	var sim: SimWorld = world.sim
	sim.clock.paused = false
	for i in 60:
		sim.step_ticks(30)
	world.hud.card_ui.visible = false
	var tick := sim.clock.tick
	var kb := sim.knowledge
	# 1층 방들을 가까운 순서로: 앞의 몇 개만 '본 곳'으로
	var rooms: Array = sim.fire.comps.filter(func(c: Compartment) -> bool: return c.level == 1 and not c.cells.is_empty() and c.name != "")
	var seen_n := maxi(3, rooms.size() - 2)
	for i in mini(seen_n, rooms.size()):
		var c: Compartment = rooms[i]
		var r := c.rect.grow(1)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if x >= 0 and y >= 0 and x < sim.building.width and y < sim.building.height:
					sim.perception.seen_tick[sim.fire.grid.index(1, x, y)] = tick
	var living := sim.fire.compartment_at(1, 13, 15)
	if living:
		kb.fires[living.index] = tick
		kb.smoky[living.index] = tick
		kb.hazards.append({"kind": "롤오버 징후", "room": living.index, "pos": Vector2(living.rect.position) + Vector2(2, 2), "level": 1, "tick": tick})
	var others: Array = rooms.filter(func(c: Compartment) -> bool: return c != living)
	if others.size() >= 1:
		kb.smoky[others[0].index] = tick - 2000
		kb.searched[others[0].index] = tick
	if others.size() >= 2:
		var c: Compartment = others[1]
		var v := sim.rescue.victims[0] if not sim.rescue.victims.is_empty() else null
		if v:
			kb.victims[v.id] = {"state": "보고", "pos": Vector2(c.rect.get_center()), "level": 1, "tick": tick}
		if sim.rescue.victims.size() >= 2:
			kb.victims[sim.rescue.victims[1].id] = {"state": "구조", "pos": Vector2(2.5, 2.5) + Vector2(sim.building.footprint(1).position) - Vector2(6, 0), "level": 1, "tick": tick}
	# 검색 지시 (층 검색)
	var task := TacticalSystem.Task.new()
	task.crew_id = 1
	task.action = "search"
	task.floor = 1
	task.floor_action = "search_floor"
	sim.tactical.tasks.append(task)
	# 조 둘을 안으로: 하나는 방금 보고, 하나는 2분 전 보고
	if living and sim.units.crews.size() >= 2:
		for k in 2:
			var crew: Crew = sim.units.crews[k]
			var room: Compartment = living if k == 0 else others[0]
			var at := Vector2(room.cells[room.cells.size() / 2]) + Vector2(0.5, 0.5)
			for ff in crew.members():
				ff.aboard = false
				ff.level = 1
				ff.pos = at
			kb.crews[crew.id] = {"pos": at + Vector2(0, 2 if k == 0 else 0), "level": 1, "tick": tick if k == 0 else tick - roundi(130.0 / SimClock.TICK_DT)}
	# 차량은 도착한 것으로, 펌프차는 소화전 점령
	for v in sim.units.vehicles:
		v.away = false
	if not sim.units.vehicles.is_empty() and not sim.building.hydrants.is_empty():
		sim.units.vehicles[0].hydrant = 0
	world.hud.board.toggle()
	world.hud.board.show_level(1)
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_board_in.png")
	world.hud.board.show_level(2)
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_board_2f.png")
	world.hud.board.show_level(-1)
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_board_out.png")
	print("저장 ", out)
	quit()
