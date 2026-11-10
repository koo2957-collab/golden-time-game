extends SceneTree
## P15 구운 그림 캡처 (점검용, 테스트 목록에 넣지 않음): godot --path . -s res://tests/_shot_sprites.gd -- 저장폴더 [시나리오]
## 차량·대원·지휘관이 보이는 바깥 화면과, 대원이 들어간 1층 단면을 찍는다. 그림 켬/끔 비교도 한 장씩.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0] + "/"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = args[1] if args.size() > 1 else "res://data/scenarios/sop214_1_day_living.json"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.hud.command_ui.close_all()
	var sim: SimWorld = world.sim
	sim.command.entry_order_required = false
	# 질문 카드는 모두 첫 답으로 넘기고, 차량이 도착하게 한다
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 60:
		sim.step_ticks(10)
		for c in sim.cards.queue.duplicate():
			sim.issue(CommandOrder.make("card_answer", [], 0, Vector3i.ZERO, {"uid": c.uid}))
		await process_frame
	# 대원 몇 조를 건물 쪽으로 움직이고 하나는 방수
	var target := Vector3i(sim.building.footprint(1).get_center().x, sim.building.footprint(1).get_center().y, 1)
	for c in sim.units.crews:
		if c.id % 2 == 0:
			sim.issue(MoveCommand.new([c.id] as Array[int], target))
	sim.clock.paused = false
	for i in 40:
		sim.step_ticks(5)
		for c in sim.cards.queue.duplicate():
			sim.issue(CommandOrder.make("card_answer", [], 0, Vector3i.ZERO, {"uid": c.uid}))
		await process_frame
	world.hud.command_ui.close_all()
	await process_frame
	root.get_texture().get_image().save_png(out + "shot_sprites.png")
	SpriteArt._config["enabled"] = false
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_shapes.png")
	SpriteArt._config["enabled"] = true
	# 단면: 정보 안개를 끄고 1층 실내 (가구·요구조자)
	sim.perception.enabled = false
	for v in sim.rescue.victims:
		v.discovered = true
	world.set_view_level(sim.fire_floor_reported())
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png(out + "shot_interior.png")
	# 불이 난 방 가까이 (불꽃·연기·불빛 확인)
	var hot: Compartment = null
	for comp in sim.fire.comps:
		if comp.level == sim.fire_floor_reported() and (hot == null or comp.q > hot.q):
			hot = comp
	if hot:
		world.camera.zoom = Vector2(1.6, 1.6)
		world.camera.retarget(world._view_bounds(), world.projection().to_screen(Vector2(hot.rect.get_center())))
		for i in 8:
			await process_frame
		root.get_texture().get_image().save_png(out + "shot_fire.png")
	print("저장 ", out)
	quit()
