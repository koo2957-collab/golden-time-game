extends SceneTree
## 시작 화면 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_menu.gd -- 저장경로.png


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://shot_menu.png"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0]
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 20:
		await process_frame
	print("창 크기 ", DisplayServer.window_get_size(), " 화면 ", root.get_visible_rect().size)
	root.get_texture().get_image().save_png(out)
	print("저장 ", out)
	quit()
