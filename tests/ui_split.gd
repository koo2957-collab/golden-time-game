extends SceneTree
## 층 분리 보기 시험 화면 점검 (창이 열린다): 단추로 켜고 끄기, 두 층이 함께 온전하게 보임, 위층이 아래층을 가리지 않음,
## 간격을 바꿔도 대원의 실제 위치는 그대로, 층을 바꿔도 화면에서 제자리, 끄면 지금 표준 화면으로.
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
	_check("단추가 보인다 (층이 이어진 건물)", hud.split_button.visible, true)
	_check("처음에는 꺼져 있다 (지금 표준 화면)", [iso.split, iso.stack.staggered()], [false, false])
	world.set_view_level(low, false)
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png(out + "split_off.png")
	# 켜기
	hud.split_button.button_pressed = true
	for i in 30:
		await process_frame
	_check("켜면 층 분리 보기", [iso.split, hud._split_row.visible], [true, true])
	_check("두 층이 함께 보인다", [iso.layers[0].visible and iso.layers[0].level == low, iso.upper_layers[0].visible and iso.upper_layers[0].level == top], [true, true])
	_check("위층은 위로만 띄운다", [iso.upper_layers[0].position.x, is_equal_approx(iso.upper_layers[0].position.y, -iso.split_lift_px)], [0.0, true])
	_check("위층은 불투명 (투명하게 하지 않는다)", iso.upper_layers[0].modulate.a, 1.0)
	_check("기본 간격 874px — 아래층 뒷벽 윗부분에 살짝 걸친다", [roundi(iso.split_lift_px), iso.split_lift_px < iso.stack.split_min_lift_px()], [874, true])
	var vp: Vector2 = root.get_visible_rect().size
	var r: Rect2 = iso.split_rect()
	var xf: Transform2D = iso.get_global_transform_with_canvas()
	var a: Vector2 = xf * r.position
	var b: Vector2 = xf * r.end
	_check("두 층이 화면 안에 들어온다 (콘솔 위)", a.y >= 0.0 and b.y <= vp.y - hud.console.size.y + 4.0 and a.x >= 0.0 and b.x <= vp.x, true)
	_check("대원의 실제 위치는 그대로", _positions(sim), before)
	root.get_texture().get_image().save_png(out + "split_on.png")
	# 간격 조절
	var lift0: float = iso.split_lift_px
	hud.split_gap_step.emit(-1)
	for i in 10:
		await process_frame
	_check("− → 간격 줄어듦", is_equal_approx(iso.split_lift_px, lift0 - iso.params.split_step_px), true)
	hud.split_gap_step.emit(1)
	hud.split_gap_step.emit(1)
	for i in 10:
		await process_frame
	_check("+ + → 간격 늘어남", is_equal_approx(iso.split_lift_px, lift0 + iso.params.split_step_px), true)
	_check("간격을 바꿔도 대원의 실제 위치는 그대로", _positions(sim), before)
	hud.split_gap_step.emit(-1)
	for i in 10:
		await process_frame
	# 층 바꾸기: 2층이 지금 층이 되어도 두 층은 화면에서 제자리
	var corner: Vector2 = world.projection().to_screen(Vector2(sim.building.footprint(top).position))
	var top_before: Vector2 = iso.get_global_transform_with_canvas() * (iso.upper_layers[0].position + corner)
	world.set_view_level(top, false)
	for i in 30:
		await process_frame
	var top_after: Vector2 = iso.get_global_transform_with_canvas() * (iso.layers[0].position + corner)
	_check("2층을 고르면 2층이 지금 층, 1층이 짝 층", [iso.layers[0].level, iso.layers[1].visible and iso.layers[1].level == low], [top, true])
	_check("층을 바꿔도 화면에서 제자리", top_before.distance_to(top_after) < 2.0, true)
	root.get_texture().get_image().save_png(out + "split_on_f2.png")
	# 분리 보기에서도 시뮬레이션은 실제 좌표로 돈다 (화면 위치와 무관)
	world.set_view_level(low, false)
	for i in 10:
		await process_frame
	var tick0 := sim.clock.tick
	for i in 20:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	_check("분리 보기에서도 시뮬레이션이 돈다", sim.clock.tick > tick0, true)
	# 끄기
	hud.split_button.button_pressed = false
	for i in 30:
		await process_frame
	_check("끄면 지금 표준 화면으로", [iso.split, iso.stack.staggered(), iso.params.stack_mode, world.camera.zoom_min], [false, false, "stack", RtsCamera.ZOOM_MIN])
	root.get_texture().get_image().save_png(out + "split_off_again.png")
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


func _positions(sim: SimWorld) -> Array:
	var out: Array = []
	for ff in sim.units.firefighters:
		out.append([ff.level, ff.pos])
	return out


func _check(name: String, got: Variant, want: Variant) -> void:
	if got == want:
		print("  통과  %s" % name)
	else:
		_failed += 1
		print("  실패  %s (결과: %s, 기대: %s)" % [name, got, want])
