extends SceneTree
## 헤드리스 테스트 실행기.
## 사용: godot --headless --path . -s res://tests/run_tests.gd [-- 이름 일부]
## 이름 일부를 주면 파일 이름이나 테스트 이름에 그 글자가 들어간 것만 실행한다.

const TEST_DIR := "res://tests/"


func _initialize() -> void:
	var passed := 0
	var failed := 0
	var args := OS.get_cmdline_user_args()
	var filter := args[0] if not args.is_empty() else ""
	for file in DirAccess.get_files_at(TEST_DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_suite.gd":
			continue
		var script: GDScript = load(TEST_DIR + file)
		for method in script.get_script_method_list():
			var method_name: String = method.name
			if not method_name.begins_with("test_"):
				continue
			if filter != "" and not (filter in file or filter in method_name):
				continue
			print("  실행  %s :: %s" % [file, method_name])
			var suite: TestSuite = script.new()
			suite.call(method_name)
			if suite.failures.is_empty():
				passed += 1
				print("  통과  %s :: %s" % [file, method_name])
			else:
				failed += 1
				print("  실패  %s :: %s" % [file, method_name])
				for f in suite.failures:
					print("        - " + f)
	print("결과: %d 통과, %d 실패" % [passed, failed])
	quit(1 if failed > 0 else 0)
