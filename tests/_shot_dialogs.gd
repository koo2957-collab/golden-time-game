extends SceneTree
## 지휘 창·무전 카드 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_dialogs.gd -- 저장폴더
## 2026-11-27: 지휘권 선언 창이 바깥 화면을 가리는 모습, 창·카드 모양이 서로 다른지 비교


func _initialize() -> void:
	_run.call_deferred()


func _snap(out: String, name: String) -> void:
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png(out + name + ".png")


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
	await _snap(out, "dlg_dispatch")
	var cu = world.hud.command_ui
	var d = cu.dispatch
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
	cu.close_all()
	# 무전 카드 (대기열 맨 앞)
	for i in 600:
		if not sim.cards.queue.is_empty():
			break
		sim.step_ticks(2)
	world.hud.card_ui.visible = true
	await _snap(out, "dlg_card")
	sim.cards.queue.clear()
	await _snap(out, "dlg_none")
	cu.open_command_dialog()
	await _snap(out, "dlg_report")
	cu.close_all()
	cu.open_update_dialog()
	await _snap(out, "dlg_update")
	cu.close_all()
	cu.open_info_dialog()
	await _snap(out, "dlg_info")
	cu.close_all()
	cu.open_org_dialog()
	await _snap(out, "dlg_org")
	cu.close_all()
	cu.open_end_confirm()
	await _snap(out, "dlg_end")
	cu.close_all()
	quit()
