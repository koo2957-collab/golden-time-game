extends SceneTree
## R17 건물 두 모습 점검 (창이 열린다). 15층 아파트로 외부 보기·인형집 단면·아래층 클릭·줌 전환·전환 연출을 확인하고,
## 스크린샷 2장(docs/ref/cutaway_exterior.png, cutaway_interior.png)과 화면 프레임 측정 결과를 남긴다.
## 사용: godot --path . -s res://tests/ui_cutaway.gd

const SCENARIO := "res://data/scenarios/sop213_3_15f_day_low.json"
const MEASURE_S := 8.0

var _failed := 0
var _world
var _lines: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = SCENARIO
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	_world = world
	world.camera.edge_scroll = false
	world.confine_mouse(false)
	world.hud.command_ui.close_all()
	var sim: SimWorld = world.sim
	var iso = world.iso_view
	var b := sim.building
	var ground: int = b.levels()[0]
	# 이 점검은 예전 쌓기 방식(위·아래 여러 층) 기준. 비켜 놓기(기본, 2026-11-12)는 맨 끝에서 따로
	iso.params.stack_mode = "stack"

	# 1) 시작: 외부 보기 — 외관 노드 하나만
	_check("시작은 외부 보기", world.exterior_view, true)
	_check("외부 보기: 맨 위 노드가 외관", [iso.layers[0].visible, iso.layers[0].exterior], [true, true])
	_check("외부 보기: 아래층 노드는 숨김", [iso.layers[1].visible, iso.layers[2].visible], [false, false])
	_out("== 시작 직후 (불이 작을 때) ==")
	await _measure("외부 보기, 1배속")

	# 2) 12층 단면: 아래 11·10층 + 위 13·14층(반투명), 15층 이상은 없음
	world.set_view_level(12)
	await process_frame
	_check("12층 → 단면 보기", world.exterior_view, false)
	_check("12층을 고르면 12·11·10층만", iso.shown_levels(), [12, 11, 10] as Array[int])
	var shown_levels: Array = []
	for layer in iso.layers:
		if layer.visible:
			shown_levels.append(layer.level)
	_check("보이는 층 노드 12·11·10", shown_levels, [12, 11, 10])
	_check("15층 이상은 그리지 않음 (위로 2개 층까지)", shown_levels.any(func(lv: int) -> bool: return lv >= 15), false)
	# F01 (2026-11-11): 다른 층은 실루엣(벽 선·사람 테두리)만 — 흐리게 하지 않고 ghost로 그린다
	_check("아래층은 220px씩 아래·실루엣", [iso.layers[0].ghost, iso.layers[1].position.y, iso.layers[1].ghost, iso.layers[2].ghost], [false, 220.0, true, true])
	_check("위층 13·14층은 220px씩 위에 실루엣", [iso.upper_layers[0].visible, iso.upper_layers[0].level, iso.upper_layers[1].level, iso.upper_layers[0].position.y, iso.upper_layers[0].ghost], [true, 13, 14, -220.0, true])
	_check("12층 남쪽 앞벽은 천장 높이 반투명 (2026-11-11 결정)", iso.layers[0]._wall_height(8, 19), 2.4)
	# 2026-11-12: 지금 층은 위층(계단 디딤판용 upper_level)이 있어도 가림 표로 칸을 빼지 않는다 — 뒷벽이 사라졌던 결함
	_check("지금 층은 위층이 있어도 모든 칸을 그린다", [iso.layers[0].upper_level, iso.layers[0]._draw_mask().is_empty()], [13, true])
	_check("12층 북쪽 뒷벽은 천장까지", iso.layers[0]._wall_height(10, 4), 2.4)
	_check("계단이 11층에서 12층으로 이어짐 (11층 노드의 계단 디딤판 20칸)", iso.layers[1]._ramp_cells().size(), 20)
	_check("12층 바닥은 계단실 자리가 뚫림", iso.layers[0].lower_level, 11)
	_check("층 이동 전환 연출 중", iso.transitioning(), true)
	await create_timer(0.5).timeout
	_check("전환 연출은 0.3초 뒤 끝남", iso.transitioning(), false)

	# 3) 아래층(11층)이 보이는 곳을 누르면 11층이 지금 층이 된다
	var proj = world.projection()
	var lower_world: Vector2 = proj.to_screen(Vector2(30.5, 18.5)) + Vector2(0, iso.stack.offset_px(1))
	world.camera.position = lower_world
	await process_frame
	await process_frame
	_press_at(root.get_canvas_transform() * lower_world, MOUSE_BUTTON_LEFT)
	await process_frame
	_check("아래층(11층)을 누르면 11층이 지금 층", world.view_level, 11)
	_check("11층 단면은 11·10·9층", iso.shown_levels(), [11, 10, 9] as Array[int])
	_check("내려갈 때는 위층 잔상이 위로 사라짐", iso.ghost.visible, true)
	await create_timer(0.5).timeout
	_check("잔상은 연출 뒤 숨김", iso.ghost.visible, false)

	# 4) 외부 보기 + 창 상태 표시 (불이 커진 뒤)
	sim.step_ticks(3400)
	world.set_view_level(ground, true)
	await create_timer(0.5).timeout
	var top = iso.layers[0]
	top._update_fire_rooms()
	var flame := 0
	var broken := 0
	for lv in top._ext_windows:
		for w: Dictionary in top._ext_windows[lv]:
			var o: Opening = w.o
			if o.broken:
				broken += 1
				if top._fire_rooms.has(o.room_a):
					flame += 1
	_check("외부 보기로 돌아옴 (외벽 닫힘)", [world.exterior_view, top.exterior, iso.layers[1].visible], [true, true, false])
	_check("깨진 창 표시 자리", broken > 0, true)
	_check("화염 분출 창 (불난 방의 깨진 창)", flame > 0, true)
	_check("실내 불빛 창 색", top._facade_glass(sim.fire.openings[0]) is Color, true)
	# 창가의 사람: 구조대상자를 5층 남쪽 창가로 옮기면 그 창에 사람이 보인다
	var w5: Dictionary = {}
	for w: Dictionary in top._ext_windows.get(5, []):
		if w.face == "S":
			w5 = w
			break
	var victim: Victim = sim.rescue.victims[0]
	var old_pos := victim.pos
	var old_level := victim.level
	victim.level = 5
	victim.pos = Vector2(w5.o.cells[0]) + Vector2(0.5, -0.5)
	victim.discovered = true
	_check("창가·발코니의 사람 표시", top._victim_at_window(w5.o) == victim, true)

	# 스크린샷 1: 외부
	var fp := Rect2(top.shell_rect())
	world.hud.visible = false
	world.camera.zoom = Vector2(0.55, 0.55)
	world.camera.position = proj.to_screen(fp.get_center(), iso.shell_top_m() * 0.45)
	await create_timer(0.4).timeout
	_save_shot("res://docs/ref/cutaway_exterior.png")
	victim.level = old_level
	victim.pos = old_pos

	# 5) 줌 전환: 건물 위로 확대 → 단면, 크게 축소 → 외부
	world.hud.visible = true
	world.camera.zoom = Vector2(0.75, 0.75)
	world.camera.position = proj.to_screen(fp.get_center(), iso.shell_top_m() * 0.3)
	await process_frame
	var center: Vector2 = root.get_visible_rect().size / 2.0
	var crew := sim.units.crews[0]
	crew.leader.level = 7
	crew.leader.pos = Vector2(15.5, 15.5)
	world.selection._set_selection([crew.id] as Array[int])
	for i in 6:
		if not world.exterior_view:
			break
		world.camera._zoom_at(center, 1.15)
	_check("건물 위로 확대 → 단면", world.exterior_view, false)
	_check("선택한 조가 있는 층(7층)으로 들어감", world.view_level, 7)
	for i in 10:
		if world.exterior_view:
			break
		world.camera._zoom_at(center, 1.0 / 1.15)
	_check("크게 축소 → 외부 보기", world.exterior_view, true)
	_check("외부 보기로 나올 때 배율 0.6 이하", world.camera.zoom.x <= 0.6 + 0.001, true)

	# 스크린샷 2: 내부 단면 (발화층 3층 — 2층·1층이 아래로 쌓인다. 구조가 보이게 정보 안개를 잠깐 끈다)
	world.set_view_level(3)
	sim.perception.enabled = false
	world.hud.visible = false
	world.camera.zoom = Vector2(0.62, 0.62)
	world.camera.position = proj.to_screen(Vector2(30, 16)) + Vector2(0, 90)
	await create_timer(0.6).timeout
	_save_shot("res://docs/ref/cutaway_interior.png")
	sim.perception.enabled = true
	world.hud.visible = true

	# 6) 프레임 측정: 불이 크게 번진 뒤(약 6분) 게임 1배속, 그리고 같은 장면을 일시정지해 그리기만
	_out("== R17 화면 프레임 측정 (%s, %s) ==" % [OS.get_processor_name(), RenderingServer.get_video_adapter_name()])
	world.camera.zoom = Vector2(0.75, 0.75)
	world.set_view_level(ground, true)
	world.camera.position = proj.to_screen(fp.get_center(), iso.shell_top_m() * 0.4)
	await _measure("외부 보기 (15층 외관), 1배속")
	sim.clock.paused = true
	await _measure("외부 보기, 일시정지(그리기만)")
	sim.clock.paused = false
	world.set_view_level(12)
	world.camera.position = proj.to_screen(Vector2(30, 12)) + Vector2(0, 100)
	await _measure("단면 보기 (12·11·10층), 1배속")
	world.set_view_level(3)
	world.camera.position = proj.to_screen(Vector2(30, 12)) + Vector2(0, 100)
	await _measure("단면 보기 (발화층 3·2·1층), 1배속")
	sim.clock.paused = true
	await _measure("단면 보기 (3·2·1층), 일시정지(그리기만)")
	sim.clock.paused = false
	# 비켜 놓기 (기본, 2026-11-12): 고른 층 + 바로 위층만, 둘 다 온전하게, 위층은 뒤(오른쪽 위)로
	iso.params.stack_mode = "stagger"
	world.set_view_level(12)
	await process_frame
	_check("비켜 놓기: 12층 + 위로 13층만", [iso.shown_levels(), iso.upper_layers[0].visible, iso.upper_layers[0].level, iso.upper_layers[1].visible], [[12] as Array[int], true, 13, false])
	_check("비켜 놓기: 두 층 모두 온전하게 (실루엣 아님)", [iso.layers[0].ghost, iso.upper_layers[0].ghost], [false, false])
	_check("비켜 놓기: 위층은 건물 뒤(오른쪽 위)로", iso.upper_layers[0].position, -iso.stack.offset_vec(1))
	# 정적인 것은 무채색, 움직이는 것만 색 (2026-11-12 사용자 결정)
	var hole_mat := iso.layers[0].material as ShaderMaterial
	_check("지금 층: 바탕은 색을 빼고(사람·불 빼고), 색 겹이 따로", [iso.layers[0].skip_live, iso.current_live.visible, iso.current_live.ghost_mode, iso.current_live.level], [true, true, 4, 12])
	_check("지금 층 바탕 흑백 정도", hole_mat.get_shader_parameter("gray"), iso.params.current_gray)
	_check("짝 위층: 불투명, 지금 층보다 어둡게", [iso.upper_layers[0].modulate.a, iso.upper_layers[0].modulate.r < 1.0], [1.0, true])
	await _measure("비켜 놓기 (12·13층), 1배속")
	var f := FileAccess.open("user://cutaway_fps.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines) + "\n")
	print("건물 화면 점검: " + ("모두 통과" if _failed == 0 else "%d개 실패" % _failed))
	quit(1 if _failed > 0 else 0)


func _measure(label: String) -> void:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 30:
		await process_frame
	var frames := 0
	var gpu := 0.0
	var process_ms := 0.0
	var sim_ms := 0.0
	var slowest := 0.0
	var t0 := Time.get_ticks_msec()
	var last := t0
	while Time.get_ticks_msec() - t0 < MEASURE_S * 1000.0:
		await process_frame
		frames += 1
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		sim_ms += _world._sim_ms
		var now := Time.get_ticks_msec()
		slowest = maxf(slowest, now - last)
		last = now
	var fps := frames / ((Time.get_ticks_msec() - t0) / 1000.0)
	_out("  %s: 평균 %.1ffps · 프레임 처리(스크립트·그리기 명령) %.1fms · 시뮬레이션(틱당) %.1fms · GPU %.1fms · 가장 긴 프레임 %.0fms → %s" % [
		label, fps, process_ms / frames, sim_ms / frames, gpu / frames, slowest,
		"60fps 목표 통과" if fps >= 58.0 else ("30fps 이상" if fps >= 29.0 else "느림")])


func _save_shot(res_path: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(res_path)
	var err := img.save_png(path)
	_check("스크린샷 저장 " + res_path.get_file(), err, OK)


func _out(s: String) -> void:
	print(s)
	_lines.append(s)


func _press_at(screen_pos: Vector2, button: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = screen_pos
	root.push_input(e, true)
	var r: InputEventMouseButton = e.duplicate()
	r.pressed = false
	root.push_input(r, true)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("  통과  " + label)
	else:
		_failed += 1
		print("  실패  %s (결과: %s, 기대: %s)" % [label, actual, expected])
