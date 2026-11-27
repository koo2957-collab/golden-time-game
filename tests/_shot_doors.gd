extends SceneTree
## 문·창 지금 모습 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_doors.gd -- 저장폴더 [시나리오 경로]
## 2026-11-27: 문·창 그림 작업 전에 외부·내부 화면의 지금 모습을 남긴다 (열린 문·닫힌 문·잠긴 문·깨진 창)


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
	for i in 3000:
		if not sim.command.resources.arriving_now():
			break
		sim.step_ticks(5)
	sim.cards.queue.clear()
	world.hud.command_ui.close_all()
	world.hud.card_ui.visible = false
	sim.perception.enabled = false
	sim.clock.paused = true
	# 1층 바깥 문 하나는 열고, 창 하나는 깬다 — 상태별 모습
	var lv: int = sim.building.levels()[0]
	var outer: Array = []
	var wins: Array = []
	for o in sim.fire.openings:
		if o.level != lv:
			continue
		if o.kind == Opening.Kind.WINDOW:
			wins.append(o)
		elif o.kind != Opening.Kind.STAIR:
			outer.append(o)
	if wins.size() > 1:
		wins[1].broken = true
	if outer.size() > 1:
		outer[1].is_open = true
	var proj = world.projection()
	var c: Vector2 = proj.to_screen(Vector2(sim.building.footprint(lv).get_center()), 1.0)
	world.camera.zoom = Vector2(1.3, 1.3)
	world.camera.position = c
	await _snap(out, "door_ext")
	world.set_view_level(lv, false)
	world.camera.zoom = Vector2(1.3, 1.3)
	world.camera.position = c
	await _snap(out, "door_int")
	world.camera.zoom = Vector2(2.4, 2.4)
	await _snap(out, "door_int_zoom")
	quit()
