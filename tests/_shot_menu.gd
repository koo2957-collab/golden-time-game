extends SceneTree
## 시작 화면 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_menu.gd -- 저장폴더


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.skip_menu = false
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png(out + "menu.png")
	quit()
