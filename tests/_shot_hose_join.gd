extends SceneTree
## 호스 이음·꺾인 곳 자리 견본 (점검용, 테스트 목록에 넣지 않음, 2026-11-24): godot --path . -s res://tests/_shot_hose_join.gd -- 저장폴더
## 방수하는 3인 분대를 길 위에 세워 놓고 찍는다 — ① 호스가 곧게 온 경우 ② 호스가 옆(남쪽)에서 와 꺾인 경우 ③ 반대쪽(북쪽)에서 온 경우,
## 각각 서서·낮은 자세. 바닥 호스가 그림 속 호스의 끝에 닿는지, 꺾인 곳에서 3번이 좌우로 서는지 본다.
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
	for v in sim.units.vehicles:
		v.away = false
	# 3명이 일하는 조를 찾는다 (진압 분대)
	var crew: Crew = null
	for c in sim.units.crews:
		if c.workers().size() >= 3:
			crew = c
			break
	if crew == null:
		crew = sim.units.crews[0]
	print("workers: ", crew.workers().size())
	var lead_cell := Vector2i(46, 33)
	var hose := HoseLine.new()
	hose.id = 900
	hose.vehicle_id = sim.units.vehicles[0].id
	hose.crew_id = crew.id
	hose.flowing = true
	hose.spraying = true
	hose.flow_fraction = 1.0
	hose.charged = true
	hose.water_head = 9999.0
	hose.pattern = HoseLine.Pattern.STRAIGHT
	hose.aim = Vector2(57.5, 33.5)
	hose.impact = hose.aim
	sim.water.hoses.append(hose)
	for ff in crew.members():
		ff.aboard = false
		ff.level = 1
		ff.pos = Vector2(lead_cell) + Vector2(0.5, 0.5)
		ff.prev_pos = ff.pos
		ff.path.clear()
	# 팀장(호스를 잡지 않는 사람)은 옆으로 비켜 세운다
	for ff in crew.members():
		if ff not in crew.workers():
			ff.pos += Vector2(-2.0, -4.0)
			ff.prev_pos = ff.pos
	var cases := {
		"1_straight": [Vector2i(-1, 0), 14],
		"2_from_south": [Vector2i(0, 1), 10],
		"3_from_north": [Vector2i(0, -1), 10],
	}
	world.camera.zoom = Vector2(2.4, 2.4)
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(Vector2(lead_cell) + Vector2(-1.0, 0.5))
	for name: String in cases:
		var step: Vector2i = cases[name][0]
		hose.points.clear()
		# 호스는 멀리서 관창수까지: 마지막 구간이 step 방향에서 온다 (그 앞은 서쪽에서)
		var n: int = cases[name][1]
		var corner := lead_cell + step * 4 if step.x == 0 else lead_cell
		for x in range(corner.x - n, corner.x):
			hose.points.append(Vector3i(x, corner.y, 1))
		var c := corner
		while c != lead_cell:
			hose.points.append(Vector3i(c.x, c.y, 1))
			c -= step
		hose.points.append(Vector3i(lead_cell.x, lead_cell.y, 1))
		for low in [false, true]:
			crew.leader.crouched = low
			for i in 6:
				await process_frame
			root.get_texture().get_image().save_png(out + "join_%s%s.png" % [name, "_low" if low else ""])
	# ④ 건물 안: 문을 지나 방에 들어선 뒤 옆으로 틀어 방수 — 호스는 문에서 오고, 관창수 바로 뒤는 방 안쪽이다
	sim.perception.enabled = false
	world.set_view_level(1)
	# 자리를 보려는 것이라 연기를 걷어 낸다
	for comp in sim.fire.comps:
		comp.layer_depth = 0.0
		comp.soot = 0.0
		comp.smoke_reach_m = 0.0
		comp.smoke_full_m = 0.0
	for i in 4:
		await process_frame
	world.camera.zoom = Vector2(2.4, 2.4)
	var b := sim.building
	var shot := 0
	for o in sim.fire.openings:
		if o.kind != Opening.Kind.DOOR or o.level != 1 or o.cells.is_empty() or o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE:
			continue
		o.is_open = true
		var dc := o.cells[0]
		for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			# 문에서 n 쪽으로 3칸, 반대쪽으로 5칸이 걸을 수 있고, 들어선 자리에서 옆(perp)으로 4칸이 트여 있는 곳
			var ok := true
			for s in range(-5, 4):
				ok = ok and b.is_walkable(1, dc.x + n.x * s, dc.y + n.y * s)
			var perp := Vector2i(-n.y, n.x)
			var at := dc + n * 3
			var side := 0
			for sg: int in [1, -1]:
				var free := true
				for s in range(1, 5):
					free = free and b.is_walkable(1, at.x + perp.x * sg * s, at.y + perp.y * sg * s)
				if free:
					side = sg
			if not ok or side == 0:
				continue
			hose.points.clear()
			for s in range(-5, 4):
				hose.points.append(Vector3i(dc.x + n.x * s, dc.y + n.y * s, 1))
			for ff in crew.workers():
				ff.pos = Vector2(at) + Vector2(0.5, 0.5)
				ff.prev_pos = ff.pos
			hose.aim = Vector2(at) + Vector2(0.5, 0.5) + Vector2(perp * side) * 8.0
			hose.impact = Vector2(at) + Vector2(0.5, 0.5) + Vector2(perp * side) * 3.5
			world.camera.position = world.projections[world.ViewMode.ISO].to_screen(Vector2(at) + Vector2(0.5, 0.5))
			for low in [false, true]:
				crew.leader.crouched = low
				for i in 6:
					await process_frame
				root.get_texture().get_image().save_png(out + "join_4_indoor_%d%s.png" % [shot, "_low" if low else ""])
			shot += 1
			break
		if shot >= 2:
			break
	quit()
