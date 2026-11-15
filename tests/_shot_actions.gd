extends SceneTree
## 동작 그림 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_actions.gd -- 저장폴더
## 2026-11-15: 방수 자세·물줄기 굵기, 문 개방(만능도끼), 2인 운반(사지운반법), 1인 운반(끌기)을 한 화면에 세워 놓고 찍는다.
## 시계를 멈추고 상태를 손으로 만들어 넣는다 — 실제 진행 화면이 아니라 동작 견본이다.


func _initialize() -> void:
	_run.call_deferred()


func _place(crew: Crew, at: Vector2, gap := Vector2(1, 0)) -> void:
	var k := 0
	for ff in crew.members():
		ff.aboard = false
		ff.level = 1
		ff.pos = at + gap * k
		ff.prev_pos = ff.pos
		ff.path.clear()
		k += 1


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
	# 출동 장면을 끝내고(원경 → 현장 확대) 차량이 다 들어올 때까지 기다린 뒤 멈춘다
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
	for v in sim.units.vehicles:
		v.away = false
	var crews := sim.units.crews
	var road_y := 31.5
	# 1) 방수: 1조 조장이 동쪽으로 직사
	_place(crews[0], Vector2(46.5, road_y + 2.0), Vector2(-1.2, 0.6))
	var hose := HoseLine.new()
	hose.id = 900
	hose.vehicle_id = sim.units.vehicles[0].id
	hose.crew_id = crews[0].id
	hose.flowing = true
	hose.flow_fraction = 1.0
	hose.pattern = HoseLine.Pattern.STRAIGHT
	hose.aim = Vector2(57.5, road_y + 2.0)
	hose.impact = Vector2(57.5, road_y + 2.0)
	sim.water.hoses.append(hose)
	# 2) 문 개방: 2조가 건물 정면의 잠긴 문 앞에서
	var door: Opening = null
	var door_at := Vector2(13.0, 21.0)
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.DOOR and o.level == 1 and o.room_b == Opening.OUTSIDE and not o.cells.is_empty():
			door = o
	if door and crews.size() > 1:
		door.locked = true
		door.is_open = false
		var dc := Vector2(door.cells[0]) + Vector2(0.5, 0.5)
		door_at = dc
		_place(crews[1], dc + Vector2(-0.6, 1.6), Vector2(1.3, 0.2))
		var task := DoorSystem.Task.new()
		task.opening = door
		task.open = true
		task.crews = [crews[1].id] as Array[int]
		task.required = 60.0
		task.progress = 25.0
		sim.doors.tasks.append(task)
	# 3) 2인 운반(사지운반법): 3조가 서쪽으로 / 4) 끌기: 4조(낮은 자세)가 서쪽으로
	var layer = world.iso_view.current_live if world.iso_view.current_live else world.iso_view.layers[0]
	var slots := [[2, Vector2(38.5, 30.5), false], [3, Vector2(38.5, 35.5), true]]
	for s: Array in slots:
		var idx: int = s[0]
		if idx >= crews.size() or idx - 2 >= sim.rescue.victims.size():
			continue
		var c: Crew = crews[idx]
		_place(c, s[1])
		c.leader.crouched = s[2]
		var v: Victim = sim.rescue.victims[idx - 2]
		v.discovered = true
		v.level = 1
		v.pos = c.leader.pos
		v.carried_by = c.id
		var t := RescueSystem.CarryTask.new()
		t.crew_id = c.id
		t.kind = "victim"
		t.target_id = v.id
		t.carrying = true
		sim.rescue.carries.append(t)
		for l in world.iso_view.layers:
			l._facing[c.leader.id] = 4  # 서쪽으로 가는 중
	world.camera.zoom = Vector2(1.25, 1.25)
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(Vector2(26.0, 30.0))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_actions.png")
	# 가까이: 방수·문 개방 / 운반
	world.camera.zoom = Vector2(2.4, 2.4)
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(Vector2(50.5, 33.5))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_actions_spray.png")
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(door_at + Vector2(0.5, 1.0))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_actions_door.png")
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(Vector2(38.5, 33.0))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_actions_carry.png")
	# 낮은 자세 방수 (A5): 1조 조장이 낮은 자세로
	crews[0].leader.crouched = true
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(Vector2(50.5, 33.5))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_actions_spray_low.png")
	crews[0].leader.crouched = false
	print("저장 ", out, " · 조 ", crews.size(), " · 구조대상자 ", sim.rescue.victims.size(), " · 문 ", door != null, " · 층 그림 ", layer != null)
	quit()
