extends SceneTree
## 선택 외곽선·차량에 가려진 대원 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_marks.gd -- 저장폴더
## 2026-11-26: 한 분대는 고르고(노란 몸 외곽선), 다른 분대는 펌프차 바로 뒤에 세운다(출동대 색 실루엣)


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
	var crews := sim.units.crews
	for vv in sim.units.vehicles:
		vv.away = false
	var v: Vehicle = sim.units.vehicles[0]
	var behind := v.pos - Vector2(1.2, 1.2)
	var k := 0
	for ff in crews[1].members():
		ff.aboard = false
		ff.level = 1
		ff.path.clear()
		ff.pos = behind + Vector2(0.6, -0.6) * k
		ff.prev_pos = ff.pos
		k += 1
	k = 0
	var at := v.pos + Vector2(3.5, 2.5)
	for ff in crews[0].members():
		ff.aboard = false
		ff.level = 1
		ff.path.clear()
		ff.pos = at + Vector2(-0.8, 0.4) * k
		ff.prev_pos = ff.pos
		k += 1
	world.selection._set_selection([crews[0].id] as Array[int], [] as Array[int], false)
	world.camera.zoom = Vector2(2.0, 2.0)
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(v.pos + Vector2(1.0, 1.0))
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "marks.png")
	print("marks vehicle ", v.short_name, " at ", v.pos)
	quit()
