extends SceneTree
## 출동 단계 캡처 (점검용): godot --path . -s res://tests/_shot_dispatch.gd -- 저장폴더 [시나리오 파일] [그림 이름 꼬리]
## 출동 중 장면(지령·카드·장비·조별 임무·차량 배치)과 준비판, 진행에 따른 도시 위 소방차, 도착 뒤 근경을 그림으로 남긴다


func _initialize() -> void:
	_run.call_deferred()


func _shot(out: String, name: String) -> void:
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out + name + ".png")


func _run() -> void:
	var out := "user://"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0] + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/sop214_1_day_living.json"
	# 둘째 인자 = 시나리오 파일 이름 (밤 시나리오로 창문 불빛을 볼 때), 셋째 인자 = 그림 이름 꼬리
	if args.size() >= 2:
		gm.scenario_path = "res://data/scenarios/" + args[1]
	var tail: String = args[2] if args.size() >= 3 else ""
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	var d = world.hud.command_ui.dispatch
	# 장면마다 한 장씩: 지령 → 카드 → 추가 무전 → 장비(둘 고름) → 조별 임무 → 차량 배치(하나 고름)
	var seen := {}
	for n in 60:
		d._gap = 0.0
		for i in 2:
			await process_frame
		var s: Dictionary = d.current()
		if s.is_empty():
			break
		var kind := str(s.kind)
		if str(s.mode) == "multi":
			d.choose(0)
			d.choose(3)
		elif str(s.mode) == "select":
			d.choose(1)
		if not seen.has(kind):
			seen[kind] = true
			d.real_s = d.real_total() * (0.08 + 0.12 * seen.size())
			await _shot(out, "shot_dispatch%s_scene_%s" % [tail, kind])
		if str(s.mode) == "pick":
			d.choose(0)
		else:
			d.confirm()
	# 결정을 모두 마친 뒤: 준비판만 남고 '현장 도착' 단추가 켜진다
	d.real_s = d.real_total() * 0.7
	await _shot(out, "shot_dispatch%s_done" % tail)
	# 도시만 (장면·준비판 숨김): 막 출발 · 큰길로 꺾은 뒤 · 현장 앞
	d.modulate.a = 0.0
	for f: float in [0.07, 0.69, 0.995]:
		d.real_s = d.real_total() * f
		await _shot(out, "shot_dispatch%s_%d" % [tail, int(f * 100.0)])
	d.modulate.a = 1.0
	# 도착 뒤 현장에서 본 도시 (가장 멀리 본 외부 화면)
	world.hud.command_ui.close_all()
	for i in 200:
		if not world.camera.locked:
			break
		await process_frame
	world.camera.zoom = Vector2(0.5, 0.5)
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(world.city.plan.site_center)
	await _shot(out, "shot_dispatch_near%s" % tail)
	print("장면 ", d.steps.size(), " 개 · 종류 ", seen.keys(), " · quads ", world.city.quad_count, " fps ", Engine.get_frames_per_second())
	quit()
