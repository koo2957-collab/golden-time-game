extends SceneTree
## 도착 연출 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_arrival.gd -- 저장폴더 [시나리오 파일] [배치 보기 번호]
## 출동 4단계 (2026-11-15): 도시의 출동 행렬 → 현장 차량 진입 → 각자 문으로 하차 → 모이는 자리까지 걸어감을 그림으로 남긴다


func _initialize() -> void:
	_run.call_deferred()


func _shot(out: String, name: String) -> void:
	for i in 2:
		await process_frame
	root.get_texture().get_image().save_png(out + name + ".png")


func _run() -> void:
	var out := "user://"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0] + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/" + (args[1] if args.size() >= 2 else "sop214_1_day_living.json")
	var pick: int = int(args[2]) if args.size() >= 3 else 0
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	var sim: SimWorld = world.sim
	var d = world.hud.command_ui.dispatch
	# 결정을 모두 마친다 (차량 배치는 고른 보기로)
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
			d.choose(pick)
			d.confirm()
		else:
			d.choose((s.options as Array).size() - 1 if str(s.kind) == "preassign" else 0)
	# 무전 장면이 화면을 가리지 않게
	world.hud.card_ui.visible = false
	d.modulate.a = 0.0
	# 현장 앞에 거의 다 왔을 때 (행렬이 자기 차로에 줄지어 있다)
	d.real_s = d.real_total() * 0.97
	await _shot(out, "shot_arrival_1_convoy")
	# 도착: 남은 길을 건너뛴다
	d.skip()
	for i in 600:
		if not d.active:
			break
		await process_frame
	# 도착한 바로 그 프레임 (아직 차량이 들어오기 전 — 행렬이 그대로 보여야 한다)
	root.get_texture().get_image().save_png(out + "shot_arrival_2a_gap.png")
	for i in 8:
		await process_frame
	await _shot(out, "shot_arrival_2_handoff")
	# 확대가 끝난 뒤: 맨 앞차는 들어오는 중, 뒤차는 지도 밖에서 달려오는 중
	for i in 400:
		if not world.camera.locked:
			break
		await process_frame
	world.hud.card_ui.visible = false
	await _shot(out, "shot_arrival_3_enter")
	# 첫 차가 서서 내리기 시작할 때
	var res := sim.command.resources
	for i in 3000:
		if not res.alighting.is_empty():
			break
		await process_frame
	var first: Firefighter = sim.units.firefighters[int(res.alighting[0].ff)] if not res.alighting.is_empty() else null
	for i in 600:
		if first == null or not first.aboard:
			break
		await process_frame
	world.hud.card_ui.visible = false
	if first:
		# 내리는 차를 화면 가운데에 크게
		var v := sim.units.vehicles_of_squad(first.squad_id)[0]
		world.camera.zoom = Vector2(1.3, 1.3)
		world.camera.position = world.projections[world.ViewMode.ISO].to_screen(v.pos)
	await _shot(out, "shot_arrival_4_doors")
	for i in 40:
		await process_frame
	world.hud.card_ui.visible = false
	await _shot(out, "shot_arrival_5_walk")
	for i in 3000:
		if not res.arriving_now() and sim.units.firefighters.all(func(f: Firefighter) -> bool: return not f.is_moving()):
			break
		await process_frame
	world.hud.card_ui.visible = false
	await _shot(out, "shot_arrival_6_gathered")
	print("저장 ", out, " · 차량 ", sim.units.vehicles.size(), " · 배치 ", sim.command.placement.get("name", "(기본)"))
	quit()
