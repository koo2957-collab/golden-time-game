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
	# 현장 보기 (Space 누르고 있기): 장면이 투명해지고 화면이 그 조로
	world.hud.card_ui.set_peek(true)
	for i in 40:
		await process_frame
	await _snap(out, "dlg_card_peek")
	world.hud.card_ui.set_peek(false)
	sim.cards.queue.clear()
	await _snap(out, "dlg_none")
	# 알림 칩: 관계인 진술(말풍선) · 차량 · 위험 · 단서
	var feed = world.hud.notice_feed
	var w0 = sim.command.survey.witnesses[0] if not sim.command.survey.witnesses.is_empty() else null
	if w0:
		feed.push_event({"type": "statement", "time_s": 251, "witness": w0.label(), "question": "안에 사람이 있습니까?", "text": "할머니랑 손자가 같이 살아요"})
	var v0 = sim.units.vehicles[1]
	feed.push_event({"type": "tank_empty", "time_s": 252, "vehicle": v0.display_name(sim.units.squads[v0.squad_id].name)})
	feed.push_event({"type": "clue_found", "time_s": 254, "text": "실내등 켜짐 — 2층 방3 (A면 창)"})
	for i in 30:
		await process_frame
	await _snap(out, "notice_feed")
	# 무전: 아래 자막 줄 · 머리 위 말풍선 · 긴급 띠 (2026-11-27 사용자 결정)
	var radio = sim.command.radio
	var rc = sim.units.crews[sim.units.crews.size() - 1]
	var rname: String = sim.units.crew_name(rc)
	radio.send(Radio.Priority.TACTICS, rname, CommandSystem.COMMANDER, "1층 현관 진입 준비 완료.", sim.clock.tick)
	radio.send(Radio.Priority.SAFETY, rname, CommandSystem.COMMANDER, "공기 경보, 탈출합니다.", sim.clock.tick)
	for i in 400:
		sim.step_ticks(1)
		await process_frame
		if radio.current and radio.current.priority == Radio.Priority.SAFETY:
			break
	for i in 20:
		await process_frame
	await _snap(out, "radio_a")
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
	cu.open_all_clear()
	await _snap(out, "dlg_all_clear")
	cu.close_all()
	cu.open_role_dialog(SafetySystem.Role.RIT)
	await _snap(out, "dlg_role")
	cu.close_all()
	# 전략 변경 창은 선언 뒤에만 — 선언하고 연다
	for c in [["fire", "연기만 확인"], ["victims", "있음"], ["use", "단독주택"], ["floors", "2층"],
			["structure", "벽돌조"], ["strategy", "공격"], ["support", "불필요"], ["access", "진입 가능, 회차 불가"]]:
		cu.open_command_dialog()
		cu.set_report_choice(c[0], c[1])
	cu.submit_report()
	sim.step_ticks(5)
	cu.close_all()
	cu.open_command_dialog()
	await _snap(out, "dlg_strategy")
	cu.close_all()
	# 관계인: 지휘관을 옆에 두고 연다, 하나 묻는다
	var survey = sim.command.survey
	if not survey.witnesses.is_empty():
		var w = survey.witnesses[0]
		sim.command.commander.pos = w.pos + Vector2(1.0, 0.0)
		cu.open_witness(0)
		await _snap(out, "dlg_witness0")
		cu.ask_question("victims")
		await _snap(out, "dlg_witness1")
		cu.close_all()
	quit()
