extends SceneTree
## 연기 읽기 견본 (점검용, 테스트 목록에 넣지 않음, 2026-11-24): godot --path . -s res://tests/_shot_smoke.gd -- 저장폴더 [시나리오 이름]
## 현관문·창을 열어 둔 채 불을 키우며 외부 화면을 찍는다: 초기 → 성장기 → 최성기 → 방수 뒤(수증기).
## 화재1 p.342 '중기 이후 검은 연기', p.124 '분출속도가 약한 백색 연기', p.255 '연기의 색깔 및 수증기'

const SmokeLook := preload("res://scripts/ui/smoke_look.gd")

var world
var sim: SimWorld
var out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var scen: String = args[1] if args.size() > 1 else "dev_squad_house_fire"
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/%s.json" % scen
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	world.hud.command_ui.close_all()
	sim = world.sim
	sim.decision_pause = false
	world.hud.card_ui.pauses = Callable()
	if world.hud.tutorial_ui:
		world.hud.tutorial_ui.visible = false
	world.hud.command_ui.dispatch.skip()
	# 바깥으로 난 문·창을 연다 (연기가 나오게)
	for o in sim.fire.openings:
		if o.room_b == Opening.OUTSIDE and o.kind != Opening.Kind.STAIR:
			o.locked = false
			o.is_open = true
			if o.kind == Opening.Kind.WINDOW:
				o.broken = true
	sim.doors.sync_blocking()
	world.set_view_level(1, true)
	var fire_room := -1
	for i in sim.fire.grid.burning:
		var p := sim.fire.grid.cell_of(i)
		var comp := sim.fire.compartment_at(p.z, p.x, p.y)
		if comp:
			fire_room = comp.index
			break
	var stamps := [["1_early", 600], ["2_growth", 1800], ["3_developed", 3000]]
	for st: Array in stamps:
		while sim.clock.tick < int(st[1]):
			sim.step_ticks(10)
			sim.cards.queue.clear()
			await process_frame
		await _shot(str(st[0]), fire_room)
	# 방수: 모든 방 고온층의 열을 빼앗는다고 보고(시뮬레이션 값을 직접 넣는다) 수증기를 본다
	await _shot("4_steam", fire_room)
	# 백드래프트 징후: 바깥 문·창을 닫고 불난 방을 징후 조건(가스·산소 부족·고온)으로 — 문틈 검은 연기 맥동·창 얼룩
	for c in sim.fire.comps:
		c.cooling_kw = 0.0
	for o in sim.fire.openings:
		if o.room_b == Opening.OUTSIDE and o.kind != Opening.Kind.STAIR:
			o.is_open = false
			o.broken = false
	sim.doors.sync_blocking()
	if fire_room >= 0:
		var fc: Compartment = sim.fire.comps[fire_room]
		fc.gas = 0.2 * 1.2 * fc.volume
		fc.y_o2 = 0.23 * 10.0 / 21.0
		fc.t_upper = 500.0
	await _shot("5_backdraft", fire_room)
	quit()


func _shot(name: String, fire_room: int) -> void:
	world.camera.zoom = Vector2(1.3, 1.3)
	var b := sim.building
	var focus := Vector2(b.width * 0.5, b.height * 0.55)
	if fire_room >= 0:
		focus = Vector2(sim.fire.comps[fire_room].rect.get_center())
	world.camera.position = world.projection().to_screen(focus, 2.0)
	sim.clock.paused = true
	for i in 12:
		if name == "4_steam":
			for c in sim.fire.comps:
				c.cooling_kw = 900.0
		await process_frame
	world.hud.card_ui.visible = false
	root.get_texture().get_image().save_png(out + "smoke_%s.png" % name)
	var txt := name
	if fire_room >= 0:
		var c: Compartment = sim.fire.comps[fire_room]
		var lk := SmokeLook.look(sim.fire, c)
		txt += " · 상부층 %.0f℃ · 산소 %.3f · 가시거리 %.1fm · 색 %s · 재생 %.2f · 뻗음 %.2f · 수증기 %.2f" % [c.t_upper, c.y_o2,
			sim.fire.visibility_m(c), lk.color, lk.rate, lk.reach, lk.steam]
	print("[smoke] ", txt)
	sim.clock.paused = false
