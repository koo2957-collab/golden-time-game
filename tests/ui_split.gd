extends SceneTree
## 두 화면 점검 — 튜토리얼 2층 주택 (창이 열린다, 2026-11-14 결정):
## 외부 화면 ↔ 내부 화면(층 분리) 단추, 고른 층이 가운데에 크게(위·아래층은 잘려 보임), 전체보기 단추(세 층이 다 들어옴),
## 기본 간격 874px, 간격을 바꿔도 대원의 실제 위치는 그대로, 보이는 층 어디든 한 번 눌러 지시
## (전체보기에서는 화면이 제자리, 평소에는 누른 층이 가운데로 미끄러져 온다), 내부 화면에서는 바깥이 흐려짐.
## 사용: godot --path . -s res://tests/ui_split.gd [-- 저장폴더]

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/tutorial_basics.json"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	world.hud.command_ui.close_all()
	var sim: SimWorld = world.sim
	# 형을 적지 않는다: IsoView 는 오토로드(EventBus)를 쓰는 스크립트에 기대어 -s 스크립트를 읽을 때는 아직 없다
	var iso = world.iso_view
	var hud = world.hud
	var sel = world.selection
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 30:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	hud.command_ui.close_all()
	hud.card_ui.visible = false
	if hud.tutorial_ui:
		hud.tutorial_ui.visible = false
	var levels: Array = sim.building.levels()
	var low: int = levels[0]
	var top: int = levels[-1]
	# 한 조는 1층, 한 조는 2층에 세운다 (실제 층·칸 좌표로)
	_place(sim, 0, low)
	_place(sim, 1, top)
	var before := _positions(sim)

	# 1) 외부 화면에서 시작
	_check("시작은 외부 화면 · 단추는 꺼짐", [world.exterior_view, hud.interior_button.button_pressed, hud._split_row.visible], [true, false, false])
	_check("외부 화면: 주변 건물 그대로", world.city.modulate.r, 1.0)
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out + "view_exterior.png")
	var ext_zoom: Vector2 = world.camera.zoom

	# 2) 내부 보기 단추 → 내부 화면 (층 분리)
	hud.interior_button.button_pressed = true
	for i in 30:
		await process_frame
	_check("내부 보기 → 내부 화면 1층", [world.exterior_view, world.view_level, hud._split_row.visible], [false, low, true])
	_check("두 층이 함께 보인다", [iso.layers[0].visible and iso.layers[0].level == low, iso.upper_layers[0].visible and iso.upper_layers[0].level == top], [true, true])
	_check("위층은 위로만 띄운다", [iso.upper_layers[0].position.x, is_equal_approx(iso.upper_layers[0].position.y, -iso.lift_px())], [0.0, true])
	_check("위층은 불투명 (투명하게 하지 않는다)", iso.upper_layers[0].modulate.a, 1.0)
	_check("기본 간격 874px — 아래층 뒷벽 윗부분에 살짝 걸친다", [roundi(iso.lift_px()), iso.lift_px() < iso.stack.split_min_lift_px()], [874, true])
	_check("내부 화면: 주변 건물은 흐리게", world.city.modulate.r < 1.0, true)
	# 평소: 고른 층이 왼쪽 정보창·위 표시줄·아래 콘솔을 뺀 영역에 꽉 차게, 위층은 위로 잘려 보인다
	var vp: Vector2 = root.get_visible_rect().size
	var area := Rect2(iso.params.split_info_width_px, 0.0, vp.x - iso.params.split_info_width_px, vp.y - hud.console.size.y)
	_check("처음은 전체보기가 아님 · 단추가 보인다", [world.interior_overview, hud.overview_button.visible, hud.overview_button.button_pressed], [false, true, false])
	_check("고른 층이 화면 영역 안에 다 들어온다", area.grow(4.0).encloses(_on_screen(iso, iso.frame_rect())), true)
	var focus_zoom: float = world.camera.zoom.x
	_check("고른 층을 크게 본다 (배율 0.6 이상)", focus_zoom >= 0.6, true)
	var up_rect: Rect2 = _on_screen(iso, iso._floor_rect(top, iso.stack.upper_vec(1)))
	_check("위층은 위로 잘려 보인다 (일부만 화면에)", [up_rect.intersects(Rect2(Vector2.ZERO, vp)), up_rect.position.y < 0.0], [true, true])
	_check("대원의 실제 위치는 그대로", _positions(sim), before)
	print("  2층 주택 내부 화면: 간격 %dpx, 고른 층 배율 %.2f" % [roundi(iso.lift_px()), focus_zoom])
	root.get_texture().get_image().save_png(out + "split_focus.png")
	# 평소 상태에서 잘려 보이는 위층을 누르면: 그 층이 고른 층이 되고 가운데로 미끄러져 온다
	var peek_cell := Vector2(sim.building.footprint(top).end) - Vector2(2.5, 2.5)
	var peek_screen: Vector2 = root.get_canvas_transform() * (world.projection().to_screen(peek_cell) + iso.stack.upper_vec(1))
	_check("위층의 보이는 부분이 화면 안에 있다", Rect2(Vector2.ZERO, vp).has_point(peek_screen), true)
	_click(peek_screen)
	await create_timer(0.6).timeout
	_check("잘려 보이는 위층을 누름 → 2층이 고른 층", world.view_level, top)
	_check("누른 층이 가운데로 온다 (화면 영역 안에 다 들어옴) · 배율 그대로", [area.grow(4.0).encloses(_on_screen(iso, iso.frame_rect())), is_equal_approx(world.camera.zoom.x, focus_zoom)], [true, true])
	world.set_view_level(low, false)
	for i in 5:
		await process_frame
	# 전체보기: 두 층(이 건물은 2층)이 다 들어오게 축소
	hud.overview_button.button_pressed = true
	for i in 10:
		await process_frame
	_check("전체보기 → 보이는 층이 모두 화면 영역 안에", [world.interior_overview, area.grow(4.0).encloses(_on_screen(iso, iso.shown_rect())), world.camera.zoom.x < focus_zoom], [true, true, true])
	root.get_texture().get_image().save_png(out + "split_on.png")

	# 3) 간격 조절
	var lift0: float = iso.lift_px()
	hud.split_gap_step.emit(-1)
	for i in 10:
		await process_frame
	_check("− → 간격 줄어듦", is_equal_approx(iso.lift_px(), lift0 - iso.params.split_step_px), true)
	hud.split_gap_step.emit(1)
	hud.split_gap_step.emit(1)
	for i in 10:
		await process_frame
	_check("+ + → 간격 늘어남", is_equal_approx(iso.lift_px(), lift0 + iso.params.split_step_px), true)
	_check("간격을 바꿔도 대원의 실제 위치는 그대로", _positions(sim), before)
	hud.split_gap_step.emit(-1)
	for i in 10:
		await process_frame

	# 4) 보이는 층 어디든 한 번에 (전체보기 — 화면은 제자리): 1층을 고른 채 2층에 선 조를 누르면 2층이 고른 층이 되고 그 조가 선택된다
	var proj = world.projection()
	var crew_up = sim.units.get_crew(1)
	var up_world: Vector2 = proj.to_screen(crew_up.leader.pos, 0.9) + iso.stack.upper_vec(1)
	var up_screen: Vector2 = root.get_canvas_transform() * up_world
	sel._set_selection([] as Array[int], [] as Array[int])
	_click(up_screen)
	for i in 5:
		await process_frame
	_check("2층의 조를 누름 → 2층이 고른 층", world.view_level, top)
	_check("같은 클릭으로 그 조가 선택된다", sel.selected, [1] as Array[int])
	var after_screen: Vector2 = root.get_canvas_transform() * proj.to_screen(crew_up.leader.pos, 0.9)
	_check("층이 바뀌어도 화면에서 제자리", up_screen.distance_to(after_screen) < 2.0, true)
	_check("2층을 고르면 1층이 직하층으로 함께", [iso.layers[0].level, iso.layers[1].visible and iso.layers[1].level == low], [top, true])
	root.get_texture().get_image().save_png(out + "split_on_f2.png")
	# 2층을 고른 채 아래 1층의 조를 누르면 1층으로
	var crew_low = sim.units.get_crew(0)
	var low_screen: Vector2 = root.get_canvas_transform() * (proj.to_screen(crew_low.leader.pos, 0.9) + iso.stack.offset_vec(1))
	_click(low_screen)
	for i in 5:
		await process_frame
	_check("1층의 조를 누름 → 1층이 고른 층 · 그 조 선택", [world.view_level, sel.selected], [low, [0] as Array[int]])
	# 1층의 조를 고른 채 2층의 방을 누르면 → 2층이 고른 층이 되고 그 방의 임무 고르기가 뜬다 (한 번에 지시)
	var room: Compartment = null
	for c in sim.fire.comps:
		if room == null and c.level == top and c.cells.size() > 8 and not sim.fire.is_exposure_comp(c):
			room = c
	@warning_ignore("integer_division")
	var rc: Vector2i = room.cells[room.cells.size() / 2]
	var room_screen: Vector2 = root.get_canvas_transform() * (proj.to_screen(Vector2(rc) + Vector2(0.5, 0.5)) + iso.stack.upper_vec(1))
	_click(room_screen)
	for i in 5:
		await process_frame
	_check("조를 고른 채 2층 방을 누름 → 2층 · 임무 고르기", [world.view_level, world.mission_ui.menu.visible or world.mission_ui.panel.visible], [top, true])
	world.mission_ui.close_menu()
	sel.cancel_mode()
	sel._set_selection([] as Array[int], [] as Array[int])

	# 5) 분리 화면에서도 시뮬레이션은 실제 좌표로 돈다
	var tick0 := sim.clock.tick
	for i in 20:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	_check("내부 화면에서도 시뮬레이션이 돈다", sim.clock.tick > tick0, true)

	# 전체보기를 끄면 다시 고른 층을 크게
	hud.overview_button.button_pressed = false
	for i in 10:
		await process_frame
	_check("전체보기 끔 → 고른 층을 크게", [world.interior_overview, is_equal_approx(world.camera.zoom.x, focus_zoom)], [false, true])

	# 6) 단추를 끄면 외부 화면, 카메라는 들어가기 전으로
	hud.interior_button.button_pressed = false
	for i in 30:
		await process_frame
	_check("끄면 외부 화면 · 전체보기 단추 숨김", [world.exterior_view, world.camera.zoom == ext_zoom, world.camera.zoom_min, world.city.modulate.r, hud.overview_button.visible], [true, true, RtsCamera.ZOOM_MIN, 1.0, false])
	root.get_texture().get_image().save_png(out + "view_exterior_again.png")
	print("결과: %s (실패 %d)" % ["통과" if _failed == 0 else "실패", _failed])
	quit(1 if _failed > 0 else 0)


## 조를 그 층의 가운데쯤 걸을 수 있는 칸에 세운다
func _place(sim: SimWorld, crew_id: int, lv: int) -> void:
	var mid := Vector2i(sim.building.footprint(lv).get_center()) + Vector2i(crew_id * 3 - 2, 2)
	var cell := sim.pathfinder.nearest_walkable(lv, mid)
	for ff in sim.units.get_crew(crew_id).members():
		ff.path.clear()
		ff.aboard = false
		ff.level = lv
		ff.prev_level = lv
		ff.pos = Vector2(cell) + Vector2(0.5, 0.5) + Vector2(0.7 * (ff.id % 2), 0.0)
		ff.prev_pos = ff.pos


## world 좌표 범위 → 화면 좌표 범위
func _on_screen(iso, r: Rect2) -> Rect2:
	var xf: Transform2D = iso.get_global_transform_with_canvas()
	return Rect2(xf * r.position, Vector2.ZERO).expand(xf * r.end)


func _positions(sim: SimWorld) -> Array:
	var out: Array = []
	for ff in sim.units.firefighters:
		out.append([ff.level, ff.pos])
	return out


func _click(screen_pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = screen_pos
	root.push_input(e, true)
	var r: InputEventMouseButton = e.duplicate()
	r.pressed = false
	root.push_input(r, true)


func _check(name: String, got: Variant, want: Variant) -> void:
	if got == want:
		print("  통과  %s" % name)
	else:
		_failed += 1
		print("  실패  %s (결과: %s, 기대: %s)" % [name, got, want])
