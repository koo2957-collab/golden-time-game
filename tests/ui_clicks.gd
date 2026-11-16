extends SceneTree
## 좌클릭 = 보기·고르기, 우클릭 = 지시 점검 (창이 열린다, 2026-11-16 사용자 결정 — docs/decisions.md '조작'):
## 외벽 층에 올리면 노랗게(고른 것 없어도) → 좌클릭 = 그 층 내부 / 내부 화면에서 아래 바깥 대원 고르기(화면 그대로) /
## 바깥 땅 좌클릭 = 외부 보기 / 방 좌클릭은 지시가 아님 / 방·외벽 층 우클릭 = 기본 임무 / 진입구 우클릭 = 그 문으로 /
## 바깥 땅 우클릭 = 분대 이동 / 지휘관을 고르면 땅 우클릭 = 지휘관 이동 / 층 막대에 올리면 노란 테두리
## 사용: godot --path . -s res://tests/ui_clicks.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/sop213_1_apartment_3f.json"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	world.hud.command_ui.close_all()
	var sel = world.selection
	var sim: SimWorld = world.sim
	sim.perception.enabled = false
	sim.decision_pause = false
	sim.command.resources.clear_schedule()
	# 출동 장면을 넘기고 현장에 바로 세운다 (이 점검은 클릭만 본다)
	var d = world.hud.command_ui.dispatch
	for n in 60:
		d._gap = 0.0
		for i in 2:
			await process_frame
		var s: Dictionary = d.current()
		if s.is_empty():
			break
		if str(s.mode) == "multi":
			d.confirm()
		elif str(s.mode) == "select":
			d.choose(0)
			d.confirm()
		elif str(s.kind) == "preassign":
			d.confirm()
		else:
			d.choose(0)
	d.skip()
	for i in 600:
		if not d.active:
			break
		await process_frame
	var res := sim.command.resources
	res.arrival_drive = false
	res.arriving.clear()
	res.alighting.clear()
	res._riders.clear()
	for v in sim.units.vehicles:
		v.away = false
	for ff in sim.units.firefighters:
		ff.aboard = false
		ff.path.clear()
	sim.command.commander.aboard = false
	sim.preassign.clear()
	sim.tactical.tasks.clear()
	sim.rescue.searches.clear()
	for i in 600:
		if not world.camera.locked:
			break
		await process_frame
	sim.clock.paused = true
	world.hud.card_ui.visible = false
	world.hud.command_ui.close_all()
	var ground: int = sim.building.levels()[0]
	var up := ground + 1
	var proj = world.projection()
	# 구조1 분대를 첫 진입구 바깥에 세운다
	var e: EntryPoints.Entry = sim.entries.list[0]
	var squad := sim.units.squad_by_key("rescue1")
	var crew: Crew = squad.crews[0]
	for k in crew.list.size():
		var c := sim.pathfinder.nearest_walkable(ground, Vector2i(e.outside.x + k, e.outside.y + 3))
		crew.list[k].level = ground
		crew.list[k].pos = Vector2(c) + Vector2(0.5, 0.5)
		crew.list[k].prev_pos = crew.list[k].pos
	var cmd := sim.command.commander
	var cmd_cell := sim.pathfinder.nearest_walkable(ground, Vector2i(e.outside.x - 6, e.outside.y + 4))
	cmd.level = ground
	cmd.pos = Vector2(cmd_cell) + Vector2(0.5, 0.5)

	# 1) 외부 보기: 고른 것 없이 외벽 2층 띠에 올리면 노랗게, 좌클릭하면 2층 내부 화면 (선택은 그대로)
	world.set_view_level(ground, true)
	sel._set_selection([] as Array[int], [] as Array[int])
	await process_frame
	var band_pos := _band_center(world, up)
	_check("외벽 2층 띠를 찾음", band_pos.x < INF, true)
	sel._update_guide(band_pos, -1)
	_check("고른 것 없어도 외벽 층에 올리면 노란 테두리", [sel._g_floor, world.iso_view.layers[0].hover_floor], [up, up])
	sel._set_selection([crew.id] as Array[int], [] as Array[int])
	sel._update_guide(band_pos, -1)
	_check("분대를 고르면 띠 문구에 우클릭 임무", world.iso_view.layers[0].hover_text.contains("우클릭: 2층 인명검색"), true)
	var n0 := sim.issued.size()
	sel._click_select(band_pos, false, Vector2(600, 300))
	_check("외벽 2층 좌클릭 → 2층 내부 화면, 지시 없음, 선택 그대로", [world.view_level, world.exterior_view, sim.issued.size() - n0, sel.selected], [up, false, 0, [crew.id]])
	await process_frame

	# 2) 2층 내부 화면: 아래에 보이는 바깥 대원을 그려진 자리에서 고른다 (화면은 2층 그대로)
	var off: Vector2 = _offset_of(world, ground)
	_check("2층 내부 화면에 1층(바깥)이 함께 보인다", off.x < INF, true)
	sel._set_selection([] as Array[int], [] as Array[int])
	var drawn: Vector2 = proj.to_screen(crew.list[0].pos, proj.pick_height_m) + off
	sel._click_select(drawn, false, Vector2(600, 300))
	_check("내부 화면에서 바깥 대원 좌클릭 → 그 분대 선택, 화면은 2층 그대로", [sel.selected, world.view_level, world.exterior_view], [[crew.id], up, false])

	# 3) 2층 방 좌클릭은 지시가 아니다 (선택 해제만)
	var room := _room_on(sim, up)
	var room_cell := Vector2(room.rect.get_center()) if room else Vector2(-1, -1)
	if room and not sim.building.is_walkable(up, floori(room_cell.x), floori(room_cell.y)):
		room_cell = Vector2(room.cells[0]) + Vector2(0.5, 0.5)
	var room_pos: Vector2 = proj.to_screen(room_cell, 0.05)
	n0 = sim.issued.size()
	sel._click_select(room_pos, false, Vector2(600, 300))
	_check("방 좌클릭 → 지시 없음 (선택 해제)", [sim.issued.size() - n0, sel.selected], [0, []])

	# 4) 방 우클릭 → 분대 기본 임무 (구조대 = 인명검색), 밖의 분대라 진입구를 거친다
	sel._set_selection([crew.id] as Array[int], [] as Array[int])
	sel._update_guide(room_pos, -1)
	_check("분대를 고른 채 방에 올리면 방이 노랗게", sel._g_room >= 0, true)
	n0 = sim.issued.size()
	sel._right_click_at(room_pos, Vector2(600, 300))
	var tac := _issued_since(sim, n0).filter(func(c): return c is TacticalCommand)
	_check("방 우클릭 → 인명검색 지시 (진입구를 거쳐)", [tac.size(), str(tac[0].action).begins_with("search") if not tac.is_empty() else false,
		tac[0].via != Vector3i(-1, -1, -1) if not tac.is_empty() else false, tac[0].target.z if not tac.is_empty() else -1], [1, true, true, up])

	# 5) 진압대는 같은 방 우클릭이 화재진압
	var attack_crew: Crew = sim.units.squads[0].crews[0]
	for k in attack_crew.list.size():
		var c := sim.pathfinder.nearest_walkable(ground, Vector2i(e.outside.x + k, e.outside.y + 5))
		attack_crew.list[k].level = ground
		attack_crew.list[k].pos = Vector2(c) + Vector2(0.5, 0.5)
	sel._set_selection([attack_crew.id] as Array[int], [] as Array[int])
	n0 = sim.issued.size()
	sel._right_click_at(room_pos, Vector2(600, 300))
	tac = _issued_since(sim, n0).filter(func(c): return c is TacticalCommand)
	_check("진압대로 방 우클릭 → 화재진압", str(tac[0].action).begins_with("attack") if not tac.is_empty() else false, true)

	# 6) 2층 화면에서 아래 바깥 땅을 우클릭 → 분대 이동 (화면 그대로)
	sel._set_selection([crew.id] as Array[int], [] as Array[int])
	var ground_spot := _outdoor_spot(world, sim, ground, up)
	_check("2층 화면에서 누를 수 있는 바깥 땅을 찾음", ground_spot.x < INF, true)
	n0 = sim.issued.size()
	sel._right_click_at(ground_spot, Vector2(600, 300))
	var moves := _issued_since(sim, n0).filter(func(c): return c is MoveCommand)
	_check("바깥 땅 우클릭 → 분대 이동, 화면 그대로", [moves.size(), world.view_level, world.exterior_view], [1, up, false])

	# 7) 바깥 땅 좌클릭 → 외부 보기 (올리면 '외부 보기' 안내), 선택은 그대로
	sel._update_guide(ground_spot, -1)
	_check("바깥 땅에 올리면 외부 보기 안내", sel._g_view, Vector2i(ground, 1))
	sel._click_select(ground_spot, false, Vector2(600, 300))
	_check("바깥 땅 좌클릭 → 외부 보기, 선택 그대로", [world.view_level, world.exterior_view, sel.selected], [ground, true, [crew.id]])
	await process_frame

	# 8) 외부 보기: 외벽 3층 우클릭 → 3층 층 단위 인명검색
	band_pos = _band_center(world, up + 1)
	n0 = sim.issued.size()
	sel._right_click_at(band_pos, Vector2(600, 300))
	tac = _issued_since(sim, n0).filter(func(c): return c is TacticalCommand)
	_check("외벽 3층 우클릭 → 3층 층 단위 인명검색", [tac.size(), str(tac[0].action) if not tac.is_empty() else "", tac[0].target.z if not tac.is_empty() else -1], [1, "search_floor", up + 1])

	# 9) 진입구 우클릭 → 그 문으로 (진입 허가는 문 앞에서)
	for k in crew.list.size():
		var c := sim.pathfinder.nearest_walkable(ground, Vector2i(e.outside.x + k, e.outside.y + 3))
		crew.list[k].pos = Vector2(c) + Vector2(0.5, 0.5)
		crew.list[k].path.clear()
	sim.tactical.tasks.clear()
	n0 = sim.issued.size()
	sel._right_click_at(proj.to_screen(Vector2(e.door) + Vector2(0.5, 0.5)), Vector2(600, 300))
	var orders := _issued_since(sim, n0).filter(func(c): return c is CommandOrder)
	_check("진입구 우클릭 → 그 문으로 (approach)", [orders.size(), str(orders[0].action) if not orders.is_empty() else "", orders[0].value if not orders.is_empty() else -1], [1, "approach", e.index])

	# 10) 지휘관을 고르면 땅 우클릭 = 지휘관 이동. 분대를 고른 채 시킬 일이 없는 곳은 아무 지시도 없다
	sel._set_selection([] as Array[int], [] as Array[int], true)
	n0 = sim.issued.size()
	sel._right_click_at(proj.to_screen(Vector2(cmd_cell) + Vector2(2.5, 0.5)), Vector2(600, 300))
	orders = _issued_since(sim, n0).filter(func(c): return c is CommandOrder and c.action == "commander_move")
	_check("지휘관 고른 채 땅 우클릭 → 지휘관 이동", orders.size(), 1)
	# 아무것도 안 고른 채 땅 우클릭 → 아무 일도 없다 (2026-11-16 사용자 결정)
	sel._set_selection([] as Array[int], [] as Array[int])
	n0 = sim.issued.size()
	sel._right_click_at(proj.to_screen(Vector2(cmd_cell) + Vector2(4.5, 0.5)), Vector2(600, 300))
	_check("아무것도 안 고른 채 땅 우클릭 → 지시 없음 (지휘관 그대로)", sim.issued.size() - n0, 0)
	sel._set_selection([crew.id] as Array[int], [] as Array[int])
	n0 = sim.issued.size()
	sel._right_click_at(proj.to_screen(Vector2(-40, -40)), Vector2(600, 300))
	_check("분대 고른 채 지도 밖 우클릭 → 지시 없음 (지휘관도 그대로)", sim.issued.size() - n0, 0)

	# 11) 층 막대에 올리면 노란 테두리
	var fb = world.hud.floor_bar
	var row: Dictionary = fb._rows.filter(func(it): return it.kind == "floor" and it.level == up)[0]
	var mm := InputEventMouseMotion.new()
	mm.position = (row.rect as Rect2).get_center()
	fb._gui_input(mm)
	_check("층 막대 2층에 올리면 노란 테두리", fb._hover == fb._rows.find(row), true)
	await process_frame
	root.get_texture().get_image().save_png("user://shot_clicks.png")
	print("결과: %s (실패 %d)" % ["통과" if _failed == 0 else "실패", _failed])
	quit(1 if _failed > 0 else 0)


## 외부 보기에서 그 층 외벽 띠의 가운데 (world 좌표). 없으면 (INF, INF)
func _band_center(world, lv: int) -> Vector2:
	var layer = world.iso_view.layers[0]
	for b in layer._floor_bands():
		if int(b[0]) == lv:
			var s: PackedVector2Array = layer._band_polys(float(b[1]), float(b[2]))[0]
			return (s[0] + s[1] + s[2] + s[3]) / 4.0 + layer.position
	return Vector2(INF, INF)


## 내부 화면에서 그 층이 그려진 자리 (지금 층 기준). 안 보이면 (INF, INF)
func _offset_of(world, lv: int) -> Vector2:
	var base := Vector2.ZERO
	var out := Vector2(INF, INF)
	for spec: Array in world.iso_view.shown_floors():
		if int(spec[0]) == world.view_level:
			base = spec[1]
		if int(spec[0]) == lv:
			out = spec[1]
	return out - base if out.x < INF else out


func _room_on(sim: SimWorld, lv: int) -> Compartment:
	var best: Compartment = null
	for comp in sim.fire.comps:
		if comp.level == lv and sim.command.interior.indoor(lv, Vector2(comp.rect.get_center())) and (best == null or comp.cells.size() > best.cells.size()):
			best = comp
	return best


## 내부 화면(지금 층 up)에서 아래 땅 층의 바깥 땅으로 잡히는 자리 (world 좌표). 대원·차량과 떨어진 곳
func _outdoor_spot(world, sim: SimWorld, ground: int, _up: int) -> Vector2:
	var proj = world.projection()
	var off := _offset_of(world, ground)
	if off.x == INF:
		return Vector2(INF, INF)
	for y in range(sim.building.height - 1, 0, -1):
		for x in range(1, sim.building.width - 1):
			if not sim.building.cell(ground, x, y) in BuildingData.OUTDOOR or not sim.building.is_walkable(ground, x, y):
				continue
			var p: Vector2 = proj.to_screen(Vector2(x, y) + Vector2(0.5, 0.5)) + off
			var t: Vector2i = world._view_target(p)
			if t == Vector2i(ground, 1) and world.selection._crew_at(p) < 0 and world.selection._vehicle_at(p) < 0:
				return p
	return Vector2(INF, INF)


func _issued_since(sim: SimWorld, n: int) -> Array:
	var out: Array = []
	for i in range(n, sim.issued.size()):
		out.append(sim.issued[i].command)
	return out


func _check(label: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s  %s%s" % ["통과" if ok else "실패", label, "" if ok else "  (결과: %s, 기대: %s)" % [actual, expected]])
