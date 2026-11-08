extends SceneTree
## 성능 측정 (기획안 P14 "벤치마크", R15). 사무용 PC에서 실행해 결과를 교관에게 보낸다.
##   1) 시뮬레이션: 모든 정식 시나리오를 화면 없이 30초(300틱) 돌려 1틱 평균·최대 ms (10Hz라 100ms 미만이어야 실시간)
##   2) 화면(창이 있을 때만): 15층 아파트 시나리오를 입체 화면으로 20초 돌려 평균 fps (기준 30fps 이상)
## 사용:
##   GODOT --headless --path . -s res://tests/benchmark.gd        (시뮬레이션만)
##   GODOT --path . -s res://tests/benchmark.gd                   (시뮬레이션 + 화면)
## 결과는 화면에 찍고 user://benchmark.txt에도 저장한다.

const SIM_TICKS := 300
const RENDER_SCENARIO := "res://data/scenarios/sop213_3_15f_day_low.json"
const RENDER_SECONDS := 20.0

var _lines: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _out(s: String) -> void:
	print(s)
	_lines.append(s)


func _run() -> void:
	_out("== 성능 측정 (%s, %s) ==" % [Time.get_datetime_string_from_system(false, true), OS.get_processor_name()])
	_out("CPU 코어 %d · 메모리 %.1fGB · 렌더러 %s" % [OS.get_processor_count(), OS.get_memory_info().get("physical", 0) / 1073741824.0,
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "")])
	_out("[시뮬레이션] 시나리오별 1틱(0.1초) 계산 시간 — 100ms 미만이면 실시간, 30ms 미만이면 여유")
	var worst := 0.0
	for s in ScenarioLoader.list():
		if str(s.id) == "dev_house_fire" or str(s.source) != "기본":
			continue
		var sim := SimWorld.from_scenario(s.path)
		if sim == null:
			_out("  %s: 불러오지 못함" % s.id)
			continue
		sim.step_ticks(10)
		var total := 0.0
		var peak := 0.0
		for i in SIM_TICKS:
			var t0 := Time.get_ticks_usec()
			sim.step_ticks(1)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			total += ms
			peak = maxf(peak, ms)
		var avg := total / SIM_TICKS
		worst = maxf(worst, avg)
		_out("  %-32s 평균 %5.1fms · 최대 %5.1fms  %s" % [s.title, avg, peak, "여유" if avg < 30.0 else ("실시간" if avg < 100.0 else "느림")])
	_out("  가장 무거운 시나리오 평균 %.1fms → %s" % [worst, "통과" if worst < 100.0 else "저사양 PC에서 느려질 수 있음"])
	if DisplayServer.get_name() != "headless":
		await _render_benchmark()
	var f := FileAccess.open("user://benchmark.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
		_out("결과 저장: %s" % ProjectSettings.globalize_path("user://benchmark.txt"))
	quit(0)


## 화면 측정: 실제 메인 씬으로 시나리오를 띄워 입체 화면 fps를 잰다
func _render_benchmark() -> void:
	# 자동로드는 -s 실행에서 이름으로 컴파일되지 않으므로 노드로 찾는다
	var gm = root.get_node_or_null("GameManager")
	if gm == null:
		_out("[화면] GameManager 없음")
		return
	gm.scenario_path = RENDER_SCENARIO
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node_or_null("Main/World")
	if world == null:
		_out("[화면] 메인 씬을 띄우지 못함")
		return
	world.camera.edge_scroll = false
	world.confine_mouse(false)
	world.hud.command_ui.close_all()
	world.sim.clock.paused = false
	var frames := 0
	var t0 := Time.get_ticks_msec()
	var slowest := 0.0
	var last := t0
	while Time.get_ticks_msec() - t0 < RENDER_SECONDS * 1000.0:
		await process_frame
		frames += 1
		var now := Time.get_ticks_msec()
		slowest = maxf(slowest, now - last)
		last = now
	var fps := frames / ((Time.get_ticks_msec() - t0) / 1000.0)
	_out("[화면] 15층 아파트 입체 화면 %d초: 평균 %.1ffps · 가장 긴 프레임 %.0fms → %s" % [int(RENDER_SECONDS), fps, slowest,
		"통과(30fps 이상)" if fps >= 29.0 else "30fps 미만 — 화면 설정에서 30fps 상한·HD 해상도 권장"])
