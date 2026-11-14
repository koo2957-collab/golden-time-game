extends SceneTree
## 출동 단계 도시 지도 캡처 (점검용): godot --path . -s res://tests/_shot_dispatch.gd -- 저장폴더


func _initialize() -> void:
	_run.call_deferred()


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
	world.hud.command_ui._dispatch.visible = false
	world.hud.command_ui._dispatch_real = 40.0
	world.hud.command_ui._dispatch.visible = true
	world.hud.command_ui._dispatch.modulate.a = 0.0
	var far: float = world.city.plan.overview_zoom(root.get_visible_rect().size.x)
	world.camera.zoom = Vector2(far, far)
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(world.city.plan.center)
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_dispatch%s.png" % tail)
	# 출동 진행에 따라: 막 출발 · 큰길로 꺾은 뒤 · 현장 앞
	for sec: float in [6.0, 62.0, 89.5]:
		world.hud.command_ui._dispatch_real = sec
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(out + "shot_dispatch%s_%d.png" % [tail, int(sec)])
	# 도착 뒤 현장에서 본 도시 (가장 멀리 본 외부 화면)
	world.hud.command_ui._dispatch.visible = false
	world.camera.zoom = Vector2(0.5, 0.5)
	world.camera.position = world.projections[world.ViewMode.ISO].to_screen(world.city.plan.site_center)
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_dispatch_near%s.png" % tail)
	print("quads ", world.city.quad_count, " windows ", world.city.window_count, " lamps ", world.city.lamp_count, " lots ", world.city.plan.lots.size(), " fps ", Engine.get_frames_per_second())
	var city = world.city
	print("icons ", city._icons != null, " vis ", city._icons.visible, " z ", city.z_index, " zoom ", world.camera.zoom)
	for v in world.sim.units.vehicles:
		print(v.short_name, " sq ", v.squad_id, " pos ", v.pos, " away ", v.away)
	print("저장 ", out, " 진행 ", world.hud.command_ui.dispatch_progress())
	quit()
