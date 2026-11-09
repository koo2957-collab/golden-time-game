extends SceneTree
## 헤드리스 테스트 실행기.
## 사용: godot --headless --path . -s res://tests/run_tests.gd [-- 이름 일부[,이름 일부...]]
## 이름 일부를 주면 파일 이름이나 테스트 이름에 그 글자가 들어간 것만 실행한다.
## 쉼표로 여러 개를 주면 하나라도 들어간 것을 실행한다 (예: -- test_cards,test_missions).
## .gd까지 쓰면 그 파일만 정확히 고른다 (예: -- test_building.gd).
## 끝에 파일별 걸린 시간(느린 순)과 실패 목록을 보여 준다.

const TEST_DIR := "res://tests/"


func _initialize() -> void:
	var passed := 0
	var failed := 0
	var failed_names: Array[String] = []
	var file_ms: Dictionary = {}
	var args := OS.get_cmdline_user_args()
	var filters: Array[String] = []
	if not args.is_empty():
		for part in args[0].split(",", false):
			var f := part.strip_edges()
			if f != "":
				filters.append(f)
	var start_all := Time.get_ticks_msec()
	for file in DirAccess.get_files_at(TEST_DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_suite.gd":
			continue
		var script: GDScript = load(TEST_DIR + file)
		for method in script.get_script_method_list():
			var method_name: String = method.name
			if not method_name.begins_with("test_"):
				continue
			if not _matches(filters, file, method_name):
				continue
			print("  실행  %s :: %s" % [file, method_name])
			var t0 := Time.get_ticks_msec()
			var suite: TestSuite = script.new()
			suite.call(method_name)
			file_ms[file] = int(file_ms.get(file, 0)) + Time.get_ticks_msec() - t0
			if suite.failures.is_empty():
				passed += 1
				print("  통과  %s :: %s" % [file, method_name])
			else:
				failed += 1
				failed_names.append("%s :: %s" % [file, method_name])
				print("  실패  %s :: %s" % [file, method_name])
				for f in suite.failures:
					print("        - " + f)
	_print_times(file_ms, Time.get_ticks_msec() - start_all)
	if not failed_names.is_empty():
		print("실패한 테스트:")
		for n in failed_names:
			print("  - " + n)
	if passed + failed == 0:
		print("경고: 조건에 맞는 테스트가 없다 (%s)" % ", ".join(filters))
	print("결과: %d 통과, %d 실패" % [passed, failed])
	quit(1 if failed > 0 else 0)


## 조건이 없으면 모두, 있으면 하나라도 파일·테스트 이름에 들어가면 실행한다.
func _matches(filters: Array[String], file: String, method_name: String) -> bool:
	if filters.is_empty():
		return true
	for f in filters:
		if f.ends_with(".gd"):
			if f == file:
				return true
		elif f in file or f in method_name:
			return true
	return false


func _print_times(file_ms: Dictionary, total_ms: int) -> void:
	var files: Array = file_ms.keys()
	files.sort_custom(func(a, b): return int(file_ms[a]) > int(file_ms[b]))
	print("파일별 시간 (느린 순):")
	for file in files:
		print("  %7.1f초  %s" % [float(file_ms[file]) / 1000.0, file])
	print("전체 %.1f초" % (float(total_ms) / 1000.0))
