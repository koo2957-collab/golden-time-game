extends SceneTree
## P4-3 대원 클릭 판정 점검 (창이 열린다): 그림 가장자리·두 대원 사이·줌아웃·겹친 두 조 번갈아·자석
## 사용: godot --path . -s res://tests/ui_pick.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/sop214_1_day_living.json"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.hud.command_ui.close_all()
	var sel = world.selection
	var sim: SimWorld = world.sim
	sim.perception.enabled = false
	var c0 := sim.units.get_crew(0)
	var c1 := sim.units.get_crew(1)
	var proj = world.projection()
	var lv: int = sel.level
	for c in [c0, c1]:
		c.leader.level = lv
		c.partner.level = lv
	c0.leader.pos = Vector2(10.5, 30.5)
	c0.partner.pos = Vector2(13.5, 30.5)
	c1.leader.pos = Vector2(40.5, 30.5)
	c1.partner.pos = Vector2(41.5, 30.5)
	var xf: Transform2D = sel.get_canvas_transform()
	var feet: Vector2 = xf * proj.to_screen(c0.leader.pos, proj.pick_height_m)
	var inv := xf.affine_inverse()
	_check("발밑 클릭 → 조", sel._crew_at(inv * feet), 0)
	_check("머리 쪽(위 40px) 클릭 → 조", sel._crew_at(inv * (feet - Vector2(0, 40))), 0)
	_check("옆 가장자리(22px) → 조", sel._crew_at(inv * (feet + Vector2(22, -10))), 0)
	var mid: Vector2 = (feet + xf * proj.to_screen(c0.partner.pos, proj.pick_height_m)) * 0.5
	_check("두 대원 사이 → 팀", sel._crew_at(inv * mid), 0)
	_check("자석: 타원 밖이지만 발에서 25px → 가장 가까운 조", sel._crew_at(inv * (feet + Vector2(0, 25))), 0)
	_check("빈 곳은 없음", sel._crew_at(inv * (feet + Vector2(300, 300))), -1)
	# 줌아웃해도 화면 기준 판정 유지
	world.camera.zoom = Vector2(0.5, 0.5)
	await process_frame
	xf = sel.get_canvas_transform()
	inv = xf.affine_inverse()
	feet = xf * proj.to_screen(c0.leader.pos, proj.pick_height_m)
	_check("줌아웃: 머리 쪽(위 40px) → 조 (판정 48×64px 유지)", sel._crew_at(inv * (feet - Vector2(0, 40))), 0)
	# 겹친 두 조: 다시 누르면 번갈아
	c1.leader.pos = c0.leader.pos + Vector2(0.2, 0)
	c1.partner.pos = c0.partner.pos + Vector2(0.2, 0)
	var p: Vector2 = inv * feet
	var a: int = sel._crew_at(p)
	sel._set_selection([a] as Array[int], [] as Array[int])
	var b: int = sel._crew_at(p)
	var c: int = sel._crew_at(p)
	_check("겹친 두 조: 선택 안 된 조가 우선, 다시 누르면 다음 조", [a != b, c == a], [true, true])
	print("결과: %s (실패 %d)" % ["통과" if _failed == 0 else "실패", _failed])
	quit(1 if _failed > 0 else 0)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s  %s%s" % ["통과" if ok else "실패", label, "" if ok else "  (결과: %s, 기대: %s)" % [actual, expected]])
