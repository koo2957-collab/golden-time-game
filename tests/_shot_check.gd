extends SceneTree
## 사용자 확인용 비교 캡처 (점검용, 테스트 목록에 넣지 않음, 2026-11-17 — docs/test_guides/2026-11-17_check.md):
##   godot --path . -s res://tests/_shot_check.gd -- 저장폴더 [모드]
## 모드: all (기본) = 팀장 표시·분대 간격 0.5m/1m·임무 완료 카드와 '대기' 표시 / officer = 팀장 표시만 (옛 커밋에서 파란 띠를 찍을 때) /
##       wave = 창가 요구조자 구조 요청 (B8, 필로티 시나리오) / more = 분대가 둘일 때 A2·A3·A7~A10 / nofire = 화점을 찾지 못함 카드
## 시계를 멈추고 상태를 손으로 만든다 — 실제 진행 화면이 아니라 견본이다.


func _initialize() -> void:
	_run.call_deferred()


func _save(out: String, name: String) -> void:
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + name + ".png")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var mode: String = args[1] if args.size() > 1 else "all"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/stage1_2_piloti.json" if mode == "wave" else "res://data/scenarios/sop214_1_day_living.json"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	world.hud.command_ui.close_all()
	var sim: SimWorld = world.sim
	sim.decision_pause = false
	world.hud.card_ui.pauses = Callable()
	if world.hud.tutorial_ui:
		world.hud.tutorial_ui.visible = false
	var d = world.hud.command_ui.dispatch
	d.skip()
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 120:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	for i in 600:
		if not world.camera.locked:
			break
		await process_frame
	world.hud.command_ui.close_all()
	world.hud.card_ui.visible = false
	var sel = world.selection
	var proj = world.projection()
	if mode == "wave":
		await _wave(world, sim, out)
		quit()
		return
	if mode == "more":
		await _more(world, sim, out)
		quit()
		return
	if mode == "nofire":
		await _no_fire(world, sim, out)
		quit()
		return
	if mode == "hose":
		await _hose(world, sim, out)
		quit()
		return
	if mode == "fetch":
		await _fetch(world, sim, out)
		quit()
		return
	# 1) 팀장 표시: 4명 분대(구조대)를 크게 — 고르지 않음 / 고름
	var squad_crew: Crew = null
	for c in sim.units.crews:
		if c.list.size() >= 4 and not c.leader.aboard:
			squad_crew = c
			if sim.units.squads[c.squad_id].type == "구조대":
				break
	if squad_crew == null:
		squad_crew = sim.units.crews[0]
	var spot := squad_crew.leader.pos
	sel._set_selection([] as Array[int], [] as Array[int])
	world.camera.zoom = Vector2(2.2, 2.2)
	world.camera.position = proj.to_screen(spot, 1.0)
	root.warp_mouse(Vector2(10, 10))
	sim.clock.paused = true
	await _save(out, "A_officer")
	sel._set_selection([squad_crew.id] as Array[int], [] as Array[int])
	await _save(out, "A_officer_selected")
	sel._set_selection([] as Array[int], [] as Array[int])
	if mode == "officer":
		print("저장 ", out)
		quit()
		return
	# 2) 분대 간격: 같은 자리로 걸어가 선 모습 — 0.5m(지금) / 1m(그림만 벌린 모습 견본)
	sim.clock.paused = false
	var goal := Vector3i(floori(spot.x) + 4, floori(spot.y), squad_crew.leader.level)
	for gap: int in [sim.units.line_gap_cells, sim.units.line_gap_cells * 2]:
		sim.units.line_gap_cells = gap
		for k in 2:
			sim.units.order_move([squad_crew.id] as Array[int], goal - Vector3i(6 * (1 - k), 0, 0), sim.pathfinder)
			for i in 200:
				sim.step_ticks(2)
				sim.cards.queue.clear()
				if squad_crew.members().all(func(f: Firefighter) -> bool: return not f.is_moving()):
					break
		world.camera.position = proj.to_screen(squad_crew.leader.pos, 1.0)
		# 칸 하나 = 0.5m
		await _save(out, "B_gap_%dcm" % (gap * 50))
	sim.units.line_gap_cells = 2
	# 3) 임무 완료 카드와 '대기': 2층 검색을 마친 구조 분대
	var top: int = sim.building.levels().max()
	var room: Compartment = null
	for r in sim.fire.comps:
		if r.level == top and not sim.fire.is_exposure_comp(r):
			r.searched_tick = 0
			if room == null and r.cells.size() >= 4:
				room = r
	if room:
		var cell := sim.tactical._room_cell(room)
		for ff in squad_crew.members():
			ff.path.clear()
			ff.level = top
			ff.prev_level = top
			ff.pos = Vector2(cell.x, cell.y) + Vector2(0.5, 0.5)
			ff.prev_pos = ff.pos
		sim.cards.queue.clear()
		sim.tactical.order("search_floor", squad_crew.id, Vector3i(0, 0, top), sim.clock.tick)
		for i in 100:
			sim.step_ticks(1)
			sim.cards.queue = sim.cards.queue.filter(func(q: CardSystem.Card) -> bool: return q.id == "MISSION-DONE-01")
			if not sim.cards.queue.is_empty():
				break
		sim.clock.paused = true
		world.set_view_level(top, false)
		world.camera.zoom = Vector2(1.4, 1.4)
		world.camera.position = proj.to_screen(squad_crew.leader.pos, 1.0)
		world.hud.card_ui.visible = true
		await _save(out, "E_mission_done_card")
		world.hud.card_ui.visible = false
		await _save(out, "E_idle_tag")
	print("저장 ", out, " · 분대 ", sim.units.crew_name(squad_crew), " ", squad_crew.list.size(), "명")
	quit()


## A7 인명검색 이동 · A8 무전 보고(서서·낮은 자세) · A9 응급처치 · A10 들것 이송 — _shot_actions.gd는 조가 4개 이상일 때만 찍는데
## 분대 편성 뒤에는 도착 직후 분대가 둘이라 빠진다. 있는 두 분대로 찍는다 (모드 more)
func _place(crew: Crew, at: Vector2, gap := Vector2(1, 0)) -> void:
	var k := 0
	for ff in crew.members():
		ff.aboard = false
		ff.level = 1
		ff.pos = at + gap * k
		ff.prev_pos = ff.pos
		ff.path.clear()
		k += 1


func _more(world, sim: SimWorld, out: String) -> void:
	sim.cards.queue.clear()
	sim.clock.paused = true
	var crews := sim.units.crews
	var a: Crew = crews[0]
	var b: Crew = crews[1] if crews.size() > 1 else crews[0]
	var proj = world.projections[world.ViewMode.ISO]
	world.camera.zoom = Vector2(2.4, 2.4)
	# A7: 검색하며 동쪽으로 걸어가는 중
	_place(b, Vector2(40.5, 35.5), Vector2(-0.8, 0))
	b.leader.prev_pos = b.leader.pos - Vector2(0.05, 0.0)
	var st := RescueSystem.SearchTask.new()
	st.crew_id = b.id
	st.level = 1
	sim.rescue.searches.append(st)
	world.camera.position = proj.to_screen(Vector2(40.0, 34.5))
	await _save(out, "shot_actions_search")
	sim.rescue.searches.clear()
	# A8: 서서 무전 / 낮은 자세 무전
	_place(a, Vector2(36.5, 30.5), Vector2(-1.2, 0))
	_place(b, Vector2(40.5, 33.5), Vector2(-1.2, 0))
	var m := Radio.Message.new()
	m.sender = sim.units.crew_name(a)
	m.receiver = "현장지휘관"
	m.body = "보고 시험"
	sim.command.radio.current = m
	world.camera.position = proj.to_screen(Vector2(38.0, 32.0))
	await _save(out, "shot_actions_radio")
	b.leader.crouched = true
	var m2 := Radio.Message.new()
	m2.sender = sim.units.crew_name(b)
	m2.receiver = "현장지휘관"
	m2.body = "보고 시험"
	m2.data = {"crew_id": b.id}
	sim.command.radio.current = m2
	await _save(out, "shot_actions_radio_low")
	sim.command.radio.current = null
	b.leader.crouched = false
	if sim.rescue.victims.is_empty():
		return
	# A2·A3: a 분대 2인 운반(서서) / b 분대 끌기(낮은 자세), 둘 다 서쪽으로
	var slots := [[a, Vector2(38.5, 30.5), false, 0], [b, Vector2(38.5, 35.5), true, 1]]
	for s: Array in slots:
		var c: Crew = s[0]
		var vi: int = s[3]
		if vi >= sim.rescue.victims.size() or c == null:
			continue
		_place(c, s[1])
		c.leader.crouched = s[2]
		var v: Victim = sim.rescue.victims[vi]
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
			l._facing[c.leader.id] = 4
	world.camera.position = proj.to_screen(Vector2(38.5, 33.0))
	await _save(out, "shot_actions_carry")
	sim.rescue.carries.clear()
	for v in sim.rescue.victims:
		v.carried_by = -1
	b.leader.crouched = false
	# A9·A10: a 분대를 잠시 구급대로 보고(그림만) 처치 / 들것 이송. b 분대는 멀리 비켜 둔다
	_place(b, Vector2(46.5, 38.5), Vector2(-1.0, 0))
	var sq: Squad = sim.units.squads[a.squad_id]
	var old_type := sq.type
	sq.type = "구급대"
	var vic: Victim = sim.rescue.victims[0]
	vic.state = Victim.State.RESCUED
	vic.carried_by = -1
	vic.level = 1
	vic.pos = Vector2(36.5, 31.5)
	_place(a, Vector2(35.8, 31.5), Vector2(0, 1.0))
	var pt := EmsSystem.Patient.new()
	pt.victim_id = vic.id
	pt.crew_id = a.id
	pt.stage = EmsSystem.Stage.TREATING
	pt.treat_start_tick = 0
	pt.treat_left = 999.0
	sim.ems.patients.append(pt)
	world.camera.position = proj.to_screen(Vector2(36.5, 31.5))
	await _save(out, "shot_actions_aid")
	pt.stage = EmsSystem.Stage.CARRYING
	vic.carried_by = a.id
	_place(a, Vector2(36.5, 31.5), Vector2(1.0, 0))
	a.leader.prev_pos = a.leader.pos - Vector2(0.05, 0.0)
	await _save(out, "shot_actions_cot")
	sim.ems.patients.erase(pt)
	vic.carried_by = -1
	sq.type = old_type
	print("저장 ", out, " · A7·A8·A9·A10")


## 호스 꺼내기 (모드 fetch — docs/motions.md E1, 2026-11-22): 진압 분대가 펌프차 후면에서 호스를 꺼내는 동안 — 열린 후면 셔터와 꺼내는 동작.
## 후면이 화면 쪽을 보게 펌프차를 돌려 세운다 (견본 — 실제 진행에서는 차가 도착한 방향 그대로라 후면이 안 보일 수 있다)
func _fetch(world, sim: SimWorld, out: String) -> void:
	var crew: Crew = null
	for c in sim.units.crews:
		if sim._default_mission(c) == "attack" and not c.leader.aboard:
			crew = c
			break
	if crew == null:
		print("진압 분대 없음")
		return
	var pump := sim.water._nearest_pump(crew.leader.pos)
	var v := sim.units.get_vehicle(pump)
	v.heading = -v.heading
	v.prev_pos = v.pos
	sim.clock.paused = false
	if not sim.water.lay_hose(crew.id, pump, sim.clock.tick):
		print("수관 연장 실패")
		return
	var h := sim.water.hose_of_crew(crew.id)
	for i in 1200:
		if not h.to_outlet:
			break
		sim.step_ticks(1)
		sim.cards.queue.clear()
	sim.step_ticks(60)
	sim.clock.paused = true
	world.camera.zoom = Vector2(2.2, 2.2)
	world.camera.position = world.projection().to_screen(v.rear_point(1.0), 0.6)
	root.warp_mouse(Vector2(10, 10))
	await _save(out, "E_hose_fetch")
	print("저장 ", out, " · 꺼내는 중 ", h.fetch_until >= 0, " · 차 방향 ", v.heading)


## 소방호스 그림 (모드 hose — docs/motions.md D1·D2·D4): 진압 분대가 펌프차에서 현관 앞까지 수관을 깔고,
## 물이 차기 전(납작한 띠)과 찬 뒤(통통한 관)를 같은 자리에서 찍는다
func _hose(world, sim: SimWorld, out: String) -> void:
	var crew: Crew = null
	for c in sim.units.crews:
		if sim._default_mission(c) == "attack" and not c.leader.aboard:
			crew = c
			break
	if crew == null:
		print("진압 분대 없음")
		return
	sim.clock.paused = false
	var pump := sim.water._nearest_pump(crew.leader.pos)
	if sim.water.hose_of_crew(crew.id) == null and not sim.water.lay_hose(crew.id, pump, sim.clock.tick):
		print("수관 연장 실패")
		return
	var h := sim.water.hose_of_crew(crew.id)
	# 호스는 한 번에 생기지 않는다 (E1·D6, 2026-11-21): 분대가 펌프차 후면으로 가서 꺼내는 동안(수관 준비 20초) 한 장
	for i in 1200:
		if not h.to_outlet:
			break
		sim.step_ticks(1)
		sim.cards.queue.clear()
	if h.fetch_until >= 0:
		sim.step_ticks(60)
		sim.clock.paused = true
		world.camera.zoom = Vector2(2.0, 2.0)
		world.camera.position = world.projection().to_screen(Vector2(h.points[0].x, h.points[0].y) + Vector2(4, 0), 0.0)
		root.warp_mouse(Vector2(10, 10))
		await _save(out, "D_hose_fetch")
		sim.clock.paused = false
	for i in 600:
		if h.fetch_until < 0:
			break
		sim.step_ticks(1)
		sim.cards.queue.clear()
	# 건물에 가리지 않게 길을 따라 동쪽으로 35m쯤 간 뒤 건물 쪽으로 꺾는다 (둘째 결합구와 꺾인 곳이 탁 트인 곳에 보이게)
	var start := h.points[0]
	var leg_no := 0
	for leg: Vector2i in [Vector2i(start.x + 40, start.y + 3), Vector2i(start.x + 44, start.y - 3), Vector2i(start.x + 58, start.y - 3), Vector2i(start.x + 58, start.y + 4)]:
		var goal := sim.pathfinder.nearest_walkable(1, leg)
		sim.units.order_move([crew.id] as Array[int], Vector3i(goal.x, goal.y, 1), sim.pathfinder)
		for i in 600:
			sim.step_ticks(2)
			sim.cards.queue.clear()
			if not crew.leader.is_moving():
				break
			# 호스 끼고 걷기 (E2·E3, 2026-11-21): 첫 구간을 걷는 중·모퉁이를 돈 뒤에 한 장씩 (물이 차기 전)
			if (leg_no == 0 and i == 45) or (leg_no == 1 and i == 14):
				h.charged = false
				h.water_head = 0.0
				sim.clock.paused = true
				world.camera.zoom = Vector2(2.4, 2.4)
				world.camera.position = world.projection().to_screen(crew.leader.pos - Vector2(3.5, 0.0), 0.0)
				root.warp_mouse(Vector2(10, 10))
				await _save(out, "D_hose_carry_%d" % leg_no)
				sim.clock.paused = false
		leg_no += 1
	sim.clock.paused = true
	# 수관 양 끝의 가운데를 화면 가운데에
	var a := h.points[0]
	var b := h.points[h.points.size() - 1]
	var mid := (Vector2(a.x, a.y) + Vector2(b.x, b.y)) * 0.5
	print("수관 ", a, " → ", b, " · 관창수 ", crew.leader.pos)
	# 가까이 볼 곳: 둘째 결합구 (2본 = 30m 지점, 호스가 그보다 짧으면 첫 결합구)
	var run: Dictionary = HoseDraw.runs(h, 1, 1.2, 4)[0]
	var one := sim.water.hose_length_cells()
	var joint_d := one * 2.0 if h.length_cells() > one * 2.0 + 4.0 else one
	var joint := HoseDraw.point_at(run, joint_d)
	world.camera.zoom = Vector2(1.0, 1.0)
	world.camera.position = world.projection().to_screen(mid, 0.0)
	root.warp_mouse(Vector2(10, 10))
	h.charged = false
	h.water_head = 0.0
	await _save(out, "D_hose_flat")
	# 물이 반쯤 찬 모습 (D3): 물머리 앞은 부풀고 뒤는 납작
	h.water_head = h.length_cells() * 0.5
	await _save(out, "D_hose_filling")
	h.water_head = h.length_cells()
	await _save(out, "D_hose_round")
	world.camera.zoom = Vector2(3.0, 3.0)
	world.camera.position = world.projection().to_screen(joint, 0.0)
	await _save(out, "D_hose_round_close")
	# 물머리가 결합구를 막 지난 모습
	h.water_head = joint_d + 3.0
	await _save(out, "D_hose_filling_close")
	h.water_head = 0.0
	await _save(out, "D_hose_flat_close")
	print("저장 ", out, " · 수관 ", snappedf(h.length_cells() * sim.building.cell_size_m, 0.1), "m · 점 ", h.points.size())
	# 여유 호스 (D5): 이 호스는 길 쪽(화면 앞쪽) 옆면 방수구에서 나온다 — 방수구 옆 굽이를 가까이
	var near := HoseDraw.layout(h, sim.units.get_vehicle(h.vehicle_id), sim.building)
	if near.has("port"):
		world.camera.zoom = Vector2(2.5, 2.5)
		world.camera.position = world.projection().to_screen(near.port_out + Vector2(4, 2), 0.0)
		await _save(out, "D_hose_port_flat")
		h.water_head = h.length_cells()
		await _save(out, "D_hose_port_round")
	await _hose_slack(world, sim, h, out)


## 여유 호스 (D5, 2026-11-21): 펌프차에서 불난 건물 출입문 안까지 곧장 깐 호스 — 옆면 방수구에서 나와
## 방수구 옆과 건물 조금 앞에 굽이를 둔다. 남은 호스가 없으면 굽이가 펴진다
func _hose_slack(world, sim: SimWorld, h: HoseLine, out: String) -> void:
	var v := sim.units.get_vehicle(h.vehicle_id)
	var door := Vector2i(-1, -1)
	var out_dir := Vector2i.ZERO
	for e in sim.entries.list:
		# 굽이 두 곳이 다 보이게 먼 쪽 출입문으로
		if e.level == v.level and not e.neighbour and (door.x < 0 or v.pos.distance_to(Vector2(e.door)) > v.pos.distance_to(Vector2(door))):
			door = Vector2i(e.door)
			out_dir = Vector2i(Vector2(e.outward).normalized().round())
	if door.x < 0:
		print("출입문 없음")
		return
	var front := sim.pathfinder.nearest_walkable(v.level, door + out_dir * 2)
	var path := sim.pathfinder.find_path(h.points[0], Vector3i(front.x, front.y, v.level))
	if path.size() < 2:
		print("문 앞까지 길 없음")
		return
	h.points = path
	for step: Vector2i in [door + out_dir, door, door - out_dir]:
		if Vector2i(h.points[-1].x, h.points[-1].y) != step:
			h.points.append(Vector3i(step.x, step.y, v.level))
	var crew := sim.units.get_crew(h.crew_id)
	crew.leader.pos = Vector2(h.points[-1].x + 0.5, h.points[-1].y + 0.5)
	h.max_cells = maxf(h.max_cells, h.length_cells() * 2.0)
	var lay := HoseDraw.layout(h, v, sim.building)
	var entry := HoseDraw.entry_dist(h, sim.building)
	var run: Dictionary = HoseDraw.runs(h, v.level, 1.2, 4, lay)[0]
	var before_door := HoseDraw.point_at(run, entry - 6.0)
	var a := h.points[0]
	var b := h.points[h.points.size() - 1]
	print("여유 호스: 수관 ", snappedf(h.length_cells() * sim.building.cell_size_m, 0.1), "m · 방수구 ", lay.get("port", "없음"), " · 건물 진입 ", snappedf(entry, 0.1), "칸")
	h.water_head = h.length_cells()
	world.camera.zoom = Vector2(1.5, 1.5)
	world.camera.position = world.projection().to_screen((Vector2(a.x, a.y) + Vector2(b.x, b.y)) * 0.5, 0.0)
	await _save(out, "D_hose_slack")
	world.camera.zoom = Vector2(3.0, 3.0)
	if lay.has("port"):
		world.camera.position = world.projection().to_screen(lay.port_out, 0.0)
		await _save(out, "D_hose_slack_port")
		h.water_head = 0.0
		await _save(out, "D_hose_slack_port_flat")
		h.water_head = h.length_cells()
	world.camera.position = world.projection().to_screen(before_door, 0.0)
	await _save(out, "D_hose_slack_door")
	# 호스를 다 썼을 때: 굽이가 펴져 팽팽하다
	h.max_cells = h.length_cells()
	if lay.has("port"):
		world.camera.position = world.projection().to_screen(lay.port_out, 0.0)
		await _save(out, "D_hose_taut_port")
	world.camera.position = world.projection().to_screen(before_door, 0.0)
	await _save(out, "D_hose_taut_door")
	# 평면 화면: 방수구가 차 뒤편(건물 쪽)이라 입체 화면에서는 차에 가린다 — 위에서 본 모습으로 굽이 두 곳을 같이
	h.max_cells = h.length_cells() * 2.0
	world.set_view_mode(1)
	world.camera.zoom = Vector2(2.0, 2.0)
	world.camera.position = world.projection().to_screen((Vector2(a.x, a.y) + Vector2(b.x, b.y)) * 0.5)
	await _save(out, "D_hose_slack_plan")
	h.max_cells = h.length_cells()
	await _save(out, "D_hose_taut_plan")
	# 급수 호스 (2026-11-21): 물탱크차에서 펌프차 후면 보수구로 — 펌프차 몸통에 걸리면 돌아간다
	h.max_cells = h.length_cells() * 2.0
	for t in sim.units.vehicles:
		if t.transfer_lpm > 0.0 and t.id != v.id and not t.away:
			t.supply_to = v.id
			break
	world.camera.zoom = Vector2(1.5, 1.5)
	world.camera.position = world.projection().to_screen(v.pos + v.heading * v.length_cells * 0.5)
	await _save(out, "D_supply_plan")
	world.set_view_mode(0)
	world.camera.zoom = Vector2(1.5, 1.5)
	world.camera.position = world.projection().to_screen(v.pos, 0.0)
	await _save(out, "D_supply")


## 화점을 찾지 못함 카드 (FIRE-NONE-01, 모드 nofire): 진압 분대를 불이 없는 맨 위층에 세우고 그 층 화재진압을 지시한다
func _no_fire(world, sim: SimWorld, out: String) -> void:
	var top: int = sim.building.levels().max()
	var crew: Crew = null
	for c in sim.units.crews:
		if sim._default_mission(c) == "attack" and not c.leader.aboard:
			crew = c
			break
	var room: Compartment = null
	for r in sim.fire.comps:
		if r.level == top and not sim.fire.is_exposure_comp(r) and r.cells.size() >= 4:
			room = r
			break
	if crew == null or room == null:
		print("진압 분대 또는 맨 위층 방 없음")
		return
	var cell := sim.tactical._room_cell(room)
	for ff in crew.members():
		ff.path.clear()
		ff.level = top
		ff.prev_level = top
		ff.pos = Vector2(cell.x, cell.y) + Vector2(0.5, 0.5)
		ff.prev_pos = ff.pos
	sim.cards.queue.clear()
	sim.tactical.order("attack_floor", crew.id, Vector3i(0, 0, top), sim.clock.tick)
	for i in 20:
		sim.step_ticks(1)
		sim.cards.queue = sim.cards.queue.filter(func(q: CardSystem.Card) -> bool: return q.id == "FIRE-NONE-01")
		if not sim.cards.queue.is_empty():
			break
	sim.clock.paused = true
	world.set_view_level(top, false)
	world.camera.zoom = Vector2(1.4, 1.4)
	world.camera.position = world.projection().to_screen(crew.leader.pos, 1.0)
	world.hud.card_ui.visible = true
	await _save(out, "E_no_fire_card")
	for q in sim.cards.queue:
		print("카드: ", q.text, " / ", q.options.map(func(o: Dictionary) -> String: return "%s(%s)" % [o.text, o.grade]))
	print("저장 ", out, " · 화점을 찾지 못함 카드 ", sim.cards.queue.size(), "장")


## 창가 요구조자 (B8): 그 층 내부 보기에서 요구조자를 크게
func _wave(world, sim: SimWorld, out: String) -> void:
	for v in sim.rescue.victims:
		if v.jumper:
			v.discovered = true
			world.set_view_level(v.level, false)
			for i in 10:
				await process_frame
			var lay = world.iso_view.current_live if world.iso_view.current_live else world.iso_view.layers[0]
			world.camera.zoom = Vector2(2.4, 2.4)
			world.camera.position = lay.proj.to_screen(v.pos, 1.0) if "proj" in lay else world.camera.position
			sim.clock.paused = true
			await _save(out, "M_B8_wave")
			print("저장 ", out, " · 창가 요구조자 ", v.label())
			return
	print("창가 요구조자 없음")
