extends SceneTree
## 문·창 모습 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_doors.gd -- 저장폴더 [시나리오 경로]
## 2026-11-27: 문·창 그림 (시안 mock_doors) — 1층 바깥 문을 닫힘·잠김·열림·파괴로, 창을 멀쩡·깨짐·열림으로 바꿔 외부·내부 화면을 찍는다.
## 연기·불이 가리지 않게 도착 직후(시간을 거의 돌리지 않고) 찍는다


func _initialize() -> void:
	_run.call_deferred()


func _snap(out: String, name: String) -> void:
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out + name + ".png")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = args[1] if args.size() > 1 else "res://data/scenarios/sop214_1_day_living.json"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	var d = world.hud.command_ui.dispatch
	d.answer_rest()
	d.skip()
	for i in 900:
		if not d.active and not world.camera.locked:
			break
		await process_frame
	var sim: SimWorld = world.sim
	sim.cards.queue.clear()
	world.hud.command_ui.close_all()
	world.hud.card_ui.visible = false
	sim.perception.enabled = false
	sim.clock.paused = true
	var lv: int = sim.building.levels()[0]
	var outer: Array = []
	var inner: Array = []
	var wins: Array = []
	for o in sim.fire.openings:
		if o.level != lv:
			continue
		if o.kind == Opening.Kind.WINDOW:
			wins.append(o)
		elif o.kind == Opening.Kind.DOOR:
			if o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE:
				outer.append(o)
			else:
				inner.append(o)
	# 앞쪽(남·동 — 화면에 보이는 면)부터: 바깥 문 첫째 잠김, 둘째 파괴, 셋째 열림 / 창 둘째 깨짐, 셋째 열림
	var front := func(p: Opening, q: Opening) -> bool: return p.center().x + p.center().y > q.center().x + q.center().y
	outer.sort_custom(front)
	wins.sort_custom(front)
	inner.sort_custom(front)
	for k in outer.size():
		var o = outer[k]
		o.is_open = k == 1 or k == 2
		o.locked = k == 0
		o.forced = k == 1
	if inner.size() > 1:
		inner[0].is_open = false
		inner[1].is_open = true
	if wins.size() > 1:
		wins[1].broken = true
		wins[1].is_open = true
	if wins.size() > 2:
		wins[2].is_open = true
	print("바깥 문 %d · 실내 문 %d · 창 %d" % [outer.size(), inner.size(), wins.size()])
	var proj = world.projection()
	var c: Vector2 = proj.to_screen(Vector2(sim.building.footprint(lv).get_center()), 1.0)
	world.camera.zoom = Vector2(1.3, 1.3)
	world.camera.position = c
	await _snap(out, "door_ext")
	if not outer.is_empty():
		world.camera.zoom = Vector2(3.0, 3.0)
		world.camera.position = proj.to_screen(outer[0].center(), 1.0)
		await _snap(out, "door_ext_zoom")
	for k in [1, 2]:
		if wins.size() > k:
			world.camera.zoom = Vector2(2.6, 2.6)
			world.camera.position = proj.to_screen(wins[k].center(), 1.5)
			await _snap(out, "win_ext_%d" % k)
	# 내부 화면은 연기가 문을 가리지 않게 (점검 사진만): 층 연기를 걷는다
	for comp in sim.fire.comps:
		comp.layer_depth = 0.0
		comp.soot = 0.0
		comp.smoke_reach_m = 0.0
		comp.smoke_full_m = 0.0
	world.set_view_level(lv, false)
	world.camera.zoom = Vector2(1.6, 1.6)
	world.camera.position = c
	await _snap(out, "door_int")
	if not inner.is_empty():
		world.camera.zoom = Vector2(3.0, 3.0)
		world.camera.position = proj.to_screen(inner[0].center(), 1.0)
		await _snap(out, "door_int_zoom")
	# 방화문이 있으면 그 문도 (아파트 현관)
	for o in inner + outer:
		if sim.building.door_kind(o.cells, o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE) == "fire":
			o.is_open = false
			world.camera.zoom = Vector2(3.0, 3.0)
			world.camera.position = proj.to_screen(o.center(), 1.0)
			await _snap(out, "door_fire_zoom")
			break
	quit()
