extends SceneTree
## 그림자·음영(입체감 1단계, 2026-11-22) 그리기 부담 재기 (점검용, 테스트 목록에 넣지 않음):
##   godot --path . -s res://tests/_perf_shadow.gd [-- 시나리오.json]
## 같은 장면을 그림자를 끄고·켜고 번갈아 세 번씩 재어 프레임 시간(ms) 평균을 견준다 (수직동기·프레임 상한 끔).
## 외부 화면(가까이·멀리)과 1층 내부 화면에서 잰다. 시계는 멈춘다 — 시뮬레이션 계산은 빠지고 그리기만 남는다

const FRAMES := 240
const ROUNDS := 3


func _initialize() -> void:
	_run.call_deferred()


func _avg_ms(frames: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / frames


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/" + (args[0] if not args.is_empty() else "sop214_1_day_living.json")
	gm.skip_menu = true
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	world.hud.command_ui.close_all()
	var sim: SimWorld = world.sim
	sim.decision_pause = false
	world.hud.card_ui.pauses = Callable()
	if world.hud.tutorial_ui:
		world.hud.tutorial_ui.visible = false
	world.hud.command_ui.dispatch.skip()
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 120:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	for i in 600:
		if not world.camera.locked:
			break
		await process_frame
	world.hud.command_ui.close_all()
	world.hud.card_ui.visible = false
	sim.clock.paused = true
	sim.perception.enabled = false
	var first: int = sim.building.levels()[0]
	var fp := sim.building.footprint(first)
	var views: Array = [["외부 화면 가까이 (배율 1.0)", true, 1.0], ["외부 화면 멀리 (배율 0.35, 도시 포함)", true, 0.35], ["1층 내부 화면 (배율 0.9)", false, 0.9]]
	print("PERF 그림자·음영 — ", gm.scenario_path.get_file(), " · 차량 ", sim.units.vehicles.size(), "대 · 대원 ", sim.units.firefighters.size(), "명 · ", FRAMES, "프레임 × ", ROUNDS, "회")
	for view: Array in views:
		world.set_view_level(first, bool(view[1]))
		for i in 10:
			await process_frame
		world.camera.zoom = Vector2(float(view[2]), float(view[2]))
		world.camera.position = world.projection().to_screen(Vector2(fp.get_center()), 1.0)
		var sum := [0.0, 0.0]
		for r in ROUNDS:
			for state: int in [0, 1]:
				ShadowDraw.force(state)
				world.city.build_mesh()
				world.city.queue_redraw()
				for i in 20:
					await process_frame
				sum[state] += await _avg_ms(FRAMES)
		var off: float = sum[0] / ROUNDS
		var on: float = sum[1] / ROUNDS
		print("PERF %-34s 끔 %.3f ms (%.0f fps) · 켬 %.3f ms (%.0f fps) · 차이 %+.3f ms (%+.1f%%)" % [view[0], off, 1000.0 / off, on, 1000.0 / on, on - off, (on - off) / off * 100.0])
	ShadowDraw.force(-1)
	print("PERF 도시 사각형 ", world.city.quad_count, " · 그래픽 ", RenderingServer.get_video_adapter_name())
	quit()
