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
	if world.camera.zoom.x > 0.5:
		world.camera.zoom = world.camera.zoom * 0.35
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_dispatch.png")
	var city = world.city
	print("icons ", city._icons != null, " vis ", city._icons.visible, " z ", city.z_index, " zoom ", world.camera.zoom)
	for v in world.sim.units.vehicles:
		print(v.short_name, " sq ", v.squad_id, " pos ", v.pos, " away ", v.away)
	print("저장 ", out, " 진행 ", world.hud.command_ui.dispatch_progress())
	quit()
