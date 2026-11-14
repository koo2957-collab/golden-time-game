extends SceneTree
## 건물 두 화면 점검 (창이 열린다, 2026-11-14 결정): 15층 아파트로 외부 화면과 내부 화면(층 분리 — 고른 층·직상층·직하층),
## 다른 층 누르기(화면 제자리), '내부 보기' 단추를 확인하고,
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

	# 1) 시작: 외부 화면 — 외관 노드 하나만
	_check("시작은 외부 화면", [world.exterior_view, world.hud.interior_button.button_pressed], [true, false])
	_check("외부 화면: 맨 위 노드가 외관", [iso.layers[0].visible, iso.layers[0].exterior], [true, true])
	_check("외부 화면: 다른 층 노드는 숨김", [iso.layers[1].visible, iso.upper_layers[0].visible], [false, false])
	_out("== 시작 직후 (불이 작을 때) ==")
	await _measure("외부 화면, 1배속")

	# 2) 12층 내부 화면: 12층은 제자리, 13층은 위로, 11층은 아래로 — 세 층 모두 온전하게
	world.set_view_level(12)
	await process_frame
	var lift: float = iso.lift_px()
	_check("12층 → 내부 화면", [world.exterior_view, world.hud.interior_button.button_pressed], [false, true])
	_check("고른 층 12 + 직하층 11 + 직상층 13", [iso.shown_levels(), iso.upper_layers[0].visible, iso.upper_layers[0].level], [[12, 11] as Array[int], true, 13])
	_check("직상층은 간격만큼 위, 직하층은 간격만큼 아래 (옆으로 비키지 않음)", [iso.upper_layers[0].position, iso.layers[1].position, iso.layers[0].position], [Vector2(0, -lift), Vector2(0, lift), Vector2.ZERO])
	_check("세 층 모두 온전하게 (실루엣·잘린 벽·투명 없음)", [iso.layers[0].ghost, iso.layers[1].ghost, iso.upper_layers[0].ghost, iso.upper_layers[0].stub_above, iso.layers[1].stub_below, iso.upper_layers[0].modulate.a, iso.layers[1].modulate.a], [false, false, false, false, false, 1.0, 1.0])
	_check("이웃 층: 바탕은 흑백·조금 어둡게, 사람·불·연기는 색 겹으로", [iso.upper_layers[0].skip_live, iso.layers[1].skip_live, iso.partner_live.visible, iso.partner_live_low.visible, iso.upper_layers[0].modulate.r < 1.0], [true, true, true, true, true])
	_check("이웃 층 색 겹은 그 층 자리에", [iso.partner_live.level, iso.partner_live.position, iso.partner_live_low.level, iso.partner_live_low.position], [13, Vector2(0, -lift), 11, Vector2(0, lift)])
	_check("층끼리 가리지 않으므로 가림 표로 칸을 빼지 않는다", [iso.layers[0]._draw_mask().is_empty(), iso.layers[1]._draw_mask().is_empty()], [true, true])
	_check("12층 남쪽 앞벽은 천장 높이 반투명 (2026-11-11 결정)", iso.layers[0]._wall_height(8, 19), 2.4)
	_check("12층 북쪽 뒷벽은 천장까지", iso.layers[0]._wall_height(10, 4), 2.4)
	_check("계단이 11층에서 12층으로 이어짐 (11층 노드의 계단 디딤판 20칸)", iso.layers[1]._ramp_cells().size(), 20)
	_check("12층 바닥은 계단실 자리가 뚫림", iso.layers[0].lower_level, 11)
	_check("전환 연출 없음 (층들이 제자리에 있어야 한다)", iso.transitioning(), false)
	_check("내부 화면에서는 더 축소할 수 있고 주변 건물은 흐리게", [world.camera.zoom_min, world.city.modulate.r < 1.0], [iso.params.split_zoom_min, true])
	# 화면 맞춤: 고른 층이 화면 영역(왼쪽 정보창 오른쪽, 콘솔 위)에 꽉 차게. 전체보기를 켜면 세 층이 다 들어온다
	var vp: Vector2 = root.get_visible_rect().size
	var area := Rect2(iso.params.split_info_width_px, 0.0, vp.x - iso.params.split_info_width_px, vp.y - world.hud.console.size.y)
	var focus_zoom: float = world.camera.zoom.x
	_check("화면 맞춤: 12층이 화면 영역 안에 다 들어온다", area.grow(4.0).encloses(_on_screen(iso, iso.frame_rect())), true)
	world.hud.overview_button.button_pressed = true
	await process_frame
	_check("전체보기: 11·12·13층이 다 들어온다 (더 축소)", [area.grow(4.0).encloses(_on_screen(iso, iso.shown_rect())), world.camera.zoom.x < focus_zoom], [true, true])
	_out("  15층 아파트 내부 화면: 간격 %dpx, 고른 층 배율 %.2f, 전체보기 배율 %.2f" % [roundi(lift), focus_zoom, world.camera.zoom.x])

	# 3) (전체보기) 직하층(11층)을 누르면 11층이 고른 층이 되고, 층들은 화면에서 제자리
	var proj = world.projection()
	var cell := Vector2(30.5, 18.5)
	var lower_world: Vector2 = proj.to_screen(cell) + iso.stack.offset_vec(1)
	world.camera.position = lower_world
	world.camera.force_update_scroll()
	await process_frame
	var before_screen: Vector2 = root.get_canvas_transform() * lower_world
	_press_at(before_screen, MOUSE_BUTTON_LEFT)
	await process_frame
	_check("직하층(11층)을 누르면 11층이 고른 층", world.view_level, 11)
	_check("11층 내부 화면은 11·10층 + 위로 12층", [iso.shown_levels(), iso.upper_layers[0].level], [[11, 10] as Array[int], 12])
	var after_screen: Vector2 = root.get_canvas_transform() * proj.to_screen(cell)
	_check("층을 눌러 바꿔도 화면에서 제자리", before_screen.distance_to(after_screen) < 2.0, true)
	world.hud.overview_button.button_pressed = false
	await process_frame
	# 층 막대로 바꾸면(멀리 갈 수 있다) 그 층 + 직상층으로 화면을 옮긴다
	world.set_view_level(5)
	await process_frame
	_check("층 막대로 5층 → 5층이 화면 영역 가운데에 다 들어온다", area.grow(4.0).encloses(_on_screen(iso, iso.frame_rect())), true)

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

	# 5) '내부 보기' 단추: 켜면 내부 화면(고른 조가 건물 안에 있으면 그 층), 끄면 외부 화면 — 줌으로는 바뀌지 않는다
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
		world.camera._zoom_at(center, 1.15)
	_check("건물 위로 확대해도 외부 화면 그대로 (줌 전환 없음)", world.exterior_view, true)
	var zoom_before: Vector2 = world.camera.zoom
	world.hud.interior_button.button_pressed = true
	await process_frame
	_check("내부 보기 단추 → 내부 화면", world.exterior_view, false)
	_check("선택한 조가 있는 층(7층)으로 들어감", world.view_level, 7)
	for i in 12:
		world.camera._zoom_at(center, 1.0 / 1.15)
	_check("크게 축소해도 내부 화면 그대로", [world.exterior_view, world.camera.zoom.x >= iso.params.split_zoom_min - 0.001], [false, true])
	world.hud.interior_button.button_pressed = false
	await process_frame
	_check("내부 보기 단추 끔 → 외부 화면, 카메라는 들어가기 전으로", [world.exterior_view, world.camera.zoom == zoom_before, world.camera.zoom_min], [true, true, RtsCamera.ZOOM_MIN])

	# 스크린샷 2: 내부 화면 (발화층 3층 + 위 4층, 아래 2층. 구조가 보이게 정보 안개를 잠깐 끈다)
	world.set_view_level(3)
	sim.perception.enabled = false
	world.hud.visible = false
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
	await _measure("내부 화면 (12층 + 13·11층), 1배속")
	world.set_view_level(3)
	await _measure("내부 화면 (발화층 3층 + 4·2층), 1배속")
	sim.clock.paused = true
	await _measure("내부 화면 (3층 + 4·2층), 일시정지(그리기만)")
	sim.clock.paused = false
	# 정적인 것은 무채색, 움직이는 것만 색 (2026-11-12 사용자 결정)
	world.set_view_level(12)
	await process_frame
	var hole_mat := iso.layers[0].material as ShaderMaterial
	_check("고른 층: 바탕은 색을 빼고(사람·불 빼고), 색 겹이 따로", [iso.layers[0].skip_live, iso.current_live.visible, iso.current_live.ghost_mode, iso.current_live.level], [true, true, 4, 12])
	_check("고른 층 바탕 흑백 정도", hole_mat.get_shader_parameter("gray"), iso.params.current_gray)
	_check("위층에 구멍을 내지 않는다 (투명하게 하지 않음)", (iso.upper_layers[0].material as ShaderMaterial).get_shader_parameter("count"), 0)
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


## world 좌표 범위 → 화면 좌표 범위
func _on_screen(iso, r: Rect2) -> Rect2:
	var xf: Transform2D = iso.get_global_transform_with_canvas()
	return Rect2(xf * r.position, Vector2.ZERO).expand(xf * r.end)


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
