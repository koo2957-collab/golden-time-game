extends SceneTree
## 점검용 (테스트 목록에 넣지 않음): 시나리오의 한 층 단면을 찍는다
## godot --path . -s res://tests/_shot_floor.gd -- 저장폴더 시나리오경로 층(level)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = args[1]
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	world.hud.command_ui.close_all()
	var sim: SimWorld = world.sim
	sim.perception.enabled = false
	var lv := int(args[2])
	var proj = world.projection()
	var fp: Rect2i = sim.building.footprint(lv)
	world.set_view_level(lv, false)
	world.camera.zoom = Vector2(0.5, 0.5)
	world.camera.retarget(proj.bounds(sim.building), proj.to_screen(Vector2(fp.get_center())))
	for i in 40:
		await process_frame
	world.hud.command_ui.close_all()
	root.get_texture().get_image().save_png(out + "floor_%d.png" % lv)
	quit()
