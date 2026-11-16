extends SceneTree
## 분대 편성 둥근 버튼 점검 (창이 열린다, 2026-11-16 결정 — docs/decisions.md '분대'):
## 첫 클릭은 선택만 → 이미 고른 분대의 팀장을 다시 누르면 둥근 버튼 → 나누기 → 2조의 팀장이 아닌 대원은 메뉴 없음 → 합치기.
## 선착 분대는 고른 지휘관을 다시 누른다.
## 사용: godot --path . -s res://tests/ui_squad.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/dev_squad_house_fire.json"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.hud.command_ui.close_all()
	var sel = world.selection
	var ui = world.mission_ui
	var sim: SimWorld = world.sim
	sim.perception.enabled = false
	sim.command.resources.clear_schedule()
	# 질문 카드가 떠도 현장이 멈추지 않게 (판단 중 정지를 끈다) — 도착·무전이 끝까지 진행되어야 한다
	sim.decision_pause = false
	# 출동 중 장면을 마치고 현장에 도착해 모두 내릴 때까지 기다린다 (도시 원경에서는 대원이 한 점에 겹친다)
	var d = world.hud.command_ui.dispatch
	for n in 60:
		d._gap = 0.0
		for i in 2:
			await process_frame
		var s: Dictionary = d.current()
		if s.is_empty():
			break
		if str(s.mode) == "multi":
			d.confirm()
		elif str(s.mode) == "select":
			d.choose(0)
			d.confirm()
		elif str(s.kind) == "preassign":
			# 도착 후 임무는 정하지 않는다 (도착하자마자 움직이면 클릭 점검이 빗나간다)
			d.confirm()
		else:
			d.choose(0)
	d.skip()
	for i in 600:
		if not d.active:
			break
		await process_frame
	# 도착 연출은 기다리지 않고 바로 현장에 세운다 (이 점검은 둥근 버튼만 본다)
	var res := sim.command.resources
	res.arrival_drive = false
	res.arriving.clear()
	res.alighting.clear()
	res._riders.clear()
	for v in sim.units.vehicles:
		v.away = false
	for ff in sim.units.firefighters:
		ff.aboard = false
		ff.path.clear()
	sim.command.commander.aboard = false
	sim.preassign.clear()
	sim.tactical.tasks.clear()
	sim.rescue.searches.clear()
	sim.clock.paused = false
	# 도착 확대 연출이 끝날 때까지 — 화면이 움직이는 중에 클릭 좌표를 계산하면 빗나간다
	for i in 600:
		if not world.camera.locked:
			break
		await process_frame
	for i in 5:
		await process_frame
	world.hud.card_ui.visible = false
	world.hud.command_ui.close_all()
	var proj = sel.projection
	var lv: int = sel.level
	world.camera.zoom = Vector2(1.0, 1.0)
	world.camera.position = proj.to_screen(Vector2(36.0, 38.0))
	var squad := sim.units.squad_by_key("rescue1")
	var crew := squad.crews[0]
	for i in crew.list.size():
		crew.list[i].level = lv
		crew.list[i].pos = Vector2(30.5 + i * 3.0, 36.5)
		crew.list[i].prev_pos = crew.list[i].pos
	await process_frame
	var officer: Firefighter = crew.officer()
	var member: Firefighter = crew.list[2]
	var xf: Transform2D = sel.get_canvas_transform()
	var inv := xf.affine_inverse()
	var o_screen: Vector2 = xf * proj.to_screen(officer.pos, proj.pick_height_m)
	var m_screen: Vector2 = xf * proj.to_screen(member.pos, proj.pick_height_m)
	# 첫 클릭은 선택만
	sel._click_select(inv * o_screen, false, o_screen)
	_check("팀장 첫 클릭 → 분대 선택만", [sel.selected.duplicate(), ui.radial.visible], [[crew.id], false])
	# 이미 고른 분대의 대원(팀장이 아님)을 다시 눌러도 메뉴는 없다
	sel._click_select(inv * m_screen, false, m_screen)
	_check("팀장이 아닌 대원을 다시 눌러도 둥근 버튼 없음", ui.radial.visible, false)
	# 팀장을 다시 누르면 둥근 버튼
	sel._click_select(inv * o_screen, false, o_screen)
	_check("고른 분대의 팀장을 다시 누르면 둥근 버튼", ui.radial.visible, true)
	_check("항목: 나누기 · 한 명 보내기 · 복귀", ui.radial_ids.duplicate(), ["split", "detach", "recall"])
	_check("한 명 보내기는 켜짐, 복귀는 회색(나간 대원 없음)", ui.radial.items.size() == 3 and ui.radial.items[1].enabled and not ui.radial.items[2].enabled, true)
	await process_frame
	root.get_texture().get_image().save_png("user://shot_squad_wheel.png")
	_check("나누기 고르기", ui.radial.pick("split"), true)
	for i in 600:
		if squad.crews.size() == 2:
			break
		await process_frame
	_check("무전이 닿으면 두 조", squad.crews.size(), 2)
	_check("이름: 구조1 1조 / 구조1 2조", [sim.units.crew_name(squad.crews[0]), sim.units.crew_name(squad.crews[1])], ["구조1 1조", "구조1 2조"])
	# 나뉜 뒤: 팀장 조를 고르고 팀장을 다시 누르면 '합치기' (기다리는 동안 도착 연출이 자리를 옮겼을 수 있어 다시 세운다)
	var all: Array[Firefighter] = []
	for c in squad.crews:
		all.append_array(c.list)
	for i in all.size():
		all[i].level = lv
		all[i].pos = Vector2(30.5 + i * 3.0, 36.5)
		all[i].prev_pos = all[i].pos
		all[i].path.clear()
	await process_frame
	xf = sel.get_canvas_transform()
	inv = xf.affine_inverse()
	o_screen = xf * proj.to_screen(officer.pos, proj.pick_height_m)
	sel._set_selection([crew.id] as Array[int], [] as Array[int])
	await process_frame
	sel._click_select(inv * o_screen, false, o_screen)
	_check("나뉜 뒤 항목: 합치기 · 한 명 보내기 · 복귀", ui.radial_ids.duplicate(), ["merge", "detach", "recall"])
	_check("합치기 고르기", ui.radial.pick("merge"), true)
	for i in 600:
		if squad.crews.size() == 1:
			break
		await process_frame
	_check("다시 한 분대 (4명)", [squad.crews.size(), squad.crews[0].list.size()], [1, 4])
	# 선착 분대: 지휘관을 고른 뒤 다시 누르면 자기 분대(진압1)의 둥근 버튼 — 3명이라 나누기는 회색
	var cmd := sim.command.commander
	cmd.level = lv
	cmd.pos = Vector2(30.5, 44.5)
	cmd.prev_pos = cmd.pos
	await process_frame
	var c_world: Vector2 = proj.to_screen(cmd.pos, proj.pick_height_m)
	var c_screen: Vector2 = xf * c_world
	sel._click_select(c_world, false, c_screen)
	_check("지휘관 첫 클릭 → 선택만", [sel.commander_selected, ui.radial.visible], [true, false])
	sel._click_select(c_world, false, c_screen)
	_check("고른 지휘관을 다시 누르면 선착 분대 둥근 버튼", [ui.radial.visible, ui.radial.title.begins_with(sim.units.squads[0].name)], [true, true])
	_check("3명 분대는 나누기 회색", not ui.radial.items.is_empty() and not ui.radial.items[0].enabled, true)
	ui.radial.close()
	# 한 명 보내기: 둥근 버튼 → 임무 목록 → 급수 지원 → 한 명이 떨어져 나간다 → 복귀
	all.clear()
	all.append_array(squad.crews[0].list)
	for i in all.size():
		all[i].level = lv
		all[i].pos = Vector2(30.5 + i * 3.0, 36.5)
		all[i].prev_pos = all[i].pos
		all[i].path.clear()
	await process_frame
	xf = sel.get_canvas_transform()
	inv = xf.affine_inverse()
	o_screen = xf * proj.to_screen(officer.pos, proj.pick_height_m)
	sel._set_selection([crew.id] as Array[int], [] as Array[int])
	await process_frame
	sel._click_select(inv * o_screen, false, o_screen)
	_check("한 명 보내기 고르면 임무 목록", [ui.radial.pick("detach"), ui.menu.visible, ui.menu_ids.duplicate()], [true, true, ["water_help", "office", "fetch"]])
	ui.pick("water_help")
	for i in 600:
		if sim.units.solo_of(squad) != null:
			break
		await process_frame
	var solo: Crew = sim.units.solo_of(squad)
	_check("한 명이 나간다 (분대 3명 + 1명)", [solo != null, squad.crews[0].list.size()], [true, 3])
	if solo != null:
		var s_world: Vector2 = proj.to_screen(solo.leader.pos, proj.pick_height_m)
		_check("나간 대원은 고를 수 없다", sel.crews_under(s_world).has(solo.id), false)
		_check("팀 초상 줄에 없다", world.hud.team_strip.crews().has(solo.id), false)
		await process_frame
		xf = sel.get_canvas_transform()
		inv = xf.affine_inverse()
		o_screen = xf * proj.to_screen(officer.pos, proj.pick_height_m)
		sel._set_selection([crew.id] as Array[int], [] as Array[int])
		await process_frame
		sel._click_select(inv * o_screen, false, o_screen)
		_check("나가 있으면 복귀가 켜지고 한 명 보내기는 회색", ui.radial.items.size() == 3 and not ui.radial.items[1].enabled and ui.radial.items[2].enabled, true)
		_check("복귀 고르기", ui.radial.pick("recall"), true)
		for i in 3000:
			if sim.units.solo_of(squad) == null:
				break
			await process_frame
		_check("분대로 돌아온다 (4명)", [sim.units.solo_of(squad) == null, squad.crews[0].list.size()], [true, 4])
	print("결과: %s (실패 %d)" % ["통과" if _failed == 0 else "실패", _failed])
	quit(1 if _failed > 0 else 0)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s  %s%s" % ["통과" if ok else "실패", label, "" if ok else "  (결과: %s, 기대: %s)" % [actual, expected]])
