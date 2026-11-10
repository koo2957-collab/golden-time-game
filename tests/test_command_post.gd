extends TestSuite
## P4-4: 지휘소·후착대 임무 받기 (기획안 9-1-1, SOP 101-2.1⑤·101-3·103-2.1·104-1.3)


func _sim(keys: Array[String] = ["pump2"]) -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var res := sim.command.resources
	res.clear_schedule()
	for k in keys:
		res.schedule(k, 0)
	return sim


func _until(sim: SimWorld, cond: Callable, max_s := 60.0) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return cond.call()


## 출동대가 도착해 대기할 때까지 (도착하면서 만들어진다)
func _staged(sim: SimWorld, key: String, max_s := 90.0) -> Squad:
	_until(sim, func() -> bool:
		var s := sim.units.squad_by_key(key)
		return s != null and sim.command.resources.is_staged(s.id), max_s)
	return sim.units.squad_by_key(key)


func _asks(sim: SimWorld, squad: String) -> int:
	var n := 0
	for m in sim.command.radio.history:
		if m.sender == squad and m.body.contains("임무 주십시오"):
			n += 1
	return n


## 지휘권 선언 (지휘 위치 = cell)
func _declare(sim: SimWorld, cell: Vector2i) -> void:
	sim.issue(CommandOrder.make("declare", [], 0, Vector3i.ZERO, {"strategy": CommandSystem.Strategy.OFFENSIVE, "post": [cell.x, cell.y]}))
	_until(sim, func() -> bool: return sim.command.declared(), 60.0)


## 건물에서 떨어진 안전한 바깥 칸 (지휘소 후보)
func _safe_cell(sim: SimWorld) -> Vector2i:
	return sim.command.post.safer_post() if sim.command.post.has_post() else _first_safe(sim)


func _first_safe(sim: SimWorld) -> Vector2i:
	var b := sim.building
	for y in range(b.height - 1, 0, -1):
		for x in range(0, b.width):
			if sim.pathfinder.passable(1, x, y) and b.cell(1, x, y) in BuildingData.OUTDOOR:
				var ev := sim.command.survey.evaluate_post(Vector2(x, y) + Vector2(0.5, 0.5), 1)
				if ev.safety != "위험" and ev.route == "양호":
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_no_post_squad_waits_by_vehicle_and_keeps_asking() -> void:
	var sim := _sim()
	var squad := _staged(sim, "pump2")
	assert_true(squad != null, "후착대 도착")
	var start := squad.crews[0].leader.pos
	sim.step_ticks(roundi(130.0 / SimClock.TICK_DT))
	assert_true(_asks(sim, squad.name) >= 2, "지휘소가 없으면 차 옆에서 계속 '임무 주십시오' (%d번)" % _asks(sim, squad.name))
	assert_true(squad.crews[0].leader.pos.distance_to(start) < 1.0, "차 옆에서 기다린다")
	assert_eq(sim.command.post.mode, CommandPost.Mode.MOBILE, "지휘소 전에는 이동지휘")


func test_declared_post_queues_squads_and_fixed_mode() -> void:
	var sim := _sim()
	var cell := _first_safe(sim)
	_declare(sim, cell)
	assert_true(sim.command.post.has_post(), "선언과 함께 지휘소")
	assert_true(_until(sim, func() -> bool: return sim.command.post.mode == CommandPost.Mode.FIXED, 60.0), "지휘관이 지휘소에 가면 고정지휘")
	var squad := _staged(sim, "pump2")
	assert_true(squad != null, "후착대 도착")
	var post := Vector2(cell) + Vector2(0.5, 0.5)
	assert_true(_until(sim, func() -> bool: return squad.crews[0].leader.pos.distance_to(post) <= 4.0 and not squad.crews[0].leader.is_moving(), 90.0), "지휘소로 걸어와 줄을 선다")
	assert_true(_until(sim, func() -> bool: return _asks(sim, squad.name) >= 1, 30.0), "지휘소 도착 후 '임무 주십시오'")
	sim.step_ticks(roundi(90.0 / SimClock.TICK_DT))
	var at_post := 0
	for m in sim.command.radio.history:
		if m.sender == squad.name and m.body.contains("지휘소 도착"):
			at_post += 1
	assert_eq(at_post, 1, "지휘소에서는 한 번만 묻는다")
	# 임무를 주면 대기 시간 기록
	sim.issue(MoveCommand.new([squad.crews[0].id] as Array[int], Vector3i(cell.x, cell.y - 3, 1)))
	assert_true(_until(sim, func() -> bool: return not sim.events.of_type("squad_wait").is_empty(), 30.0), "대기 시간 기록")
	var w := sim.command.post.wait_summary(sim.clock.tick)
	assert_true(int(w.total_s) > 60, "임무 대기 총 %d초" % int(w.total_s))


func test_leaving_post_is_mobile_with_delayed_board_and_missed_reports() -> void:
	var sim := _sim([])
	var cell := _first_safe(sim)
	_declare(sim, cell)
	_until(sim, func() -> bool: return sim.command.post.mode == CommandPost.Mode.FIXED, 60.0)
	sim.command.move_commander(Vector3i(cell.x, maxi(0, cell.y - 14), 1))
	assert_true(_until(sim, func() -> bool: return sim.command.post.mode == CommandPost.Mode.MOBILE, 30.0), "지휘소를 떠나면 이동지휘")
	assert_true(sim.command.post.penalized(), "상황판 갱신 지연·일상 보고 놓침")
	# 대원 보고: 위험 보고는 늦게 오르고, 일상 보고는 일부 놓친다
	var c0 := sim.units.crews[0]
	var name := "%s %d조" % [sim.units.squads[c0.squad_id].name, c0.number]
	var before := sim.knowledge.crews.has(c0.id)
	var missed := 0
	for i in 12:
		var m := sim.command.radio.send(Radio.Priority.TACTICS, name, CommandSystem.COMMANDER, "보고 %d" % i, sim.clock.tick)
		_until(sim, func() -> bool: return m.end_tick >= 0, 30.0)
		if m.missed:
			missed += 1
	assert_true(missed > 0 and missed < 12, "일상 보고 12건 중 %d건 놓침" % missed)
	var safety := sim.command.radio.send(Radio.Priority.SAFETY, name, CommandSystem.COMMANDER, "안전 보고", sim.clock.tick)
	_until(sim, func() -> bool: return safety.end_tick >= 0, 30.0)
	assert_true(not safety.missed, "대원 안전 무전은 놓치지 않는다")
	assert_true(not sim.command.post._delayed.is_empty() or before, "상황판 반영이 늦어진다 (대기열)")
	assert_true(not sim.events.of_type("command_mode").is_empty(), "지휘 방식 바뀜 기록")


func test_post_in_debris_radius_raises_card_and_moves() -> void:
	var sim := _sim([])
	var fp := sim.building.footprint(1)
	var near := sim.pathfinder.nearest_walkable(1, Vector2i(fp.get_center().x, fp.end.y + 1))
	_declare(sim, near)
	assert_true(not sim.events.of_type("post_danger").is_empty(), "건물에 붙은 지휘소: 낙하물 위험 경고 (SOP 104-1.3)")
	sim.step_ticks(2)
	var card: CardSystem.Card = null
	for c in sim.cards.queue:
		if c.id == "POST-DANGER-01":
			card = c
	assert_true(card != null, "지휘소 위치 카드")
	for i in card.options.size():
		if card.options[i].grade == "최선":
			sim.cards.answer(card.uid, i, sim.clock.tick)
	var ev := sim.command.survey.evaluate_post(Vector2(sim.command.post.post) + Vector2(0.5, 0.5), 1)
	assert_true(ev.safety != "위험", "위험반경 밖으로 옮김 (%s, %sm)" % [ev.safety, ev.distance_m])
	assert_true(sim.command.post.log.size() >= 2, "지휘소 기록 2번")


func test_zone_installed_by_crew_after_work_time() -> void:
	var sim := _sim([])
	sim.command.entry_order_required = false
	var b := sim.building
	var fp := b.footprint(1)
	var r := Rect2i()
	for y in range(fp.end.y + 2, b.height - 6):
		for x in range(fp.position.x, b.width - 6):
			if r.size.x == 0 and sim.zones.safe_reject_reason(Rect2i(x, y, 6, 6)) == "":
				r = Rect2i(x, y, 6, 6)
	sim.issue(CommandOrder.make("zone", [], 0, Vector3i.ZERO, {"kind": "safe", "rect": [r.position.x, r.position.y, r.size.x, r.size.y]}))
	assert_true(_until(sim, func() -> bool: return not sim.command.post.jobs.is_empty(), 30.0), "무전이 가면 설치 작업")
	sim.step_ticks(10)
	assert_true(not sim.zones.has_safe(), "무전만으로는 생기지 않는다 — 대원이 가서 설치")
	assert_eq(sim.command.post.jobs.size(), 1, "설치 작업")
	assert_true(not sim.events.of_type("zone_install_go").is_empty(), "가까운 임무 없는 조가 설치하러 감")
	assert_true(_until(sim, func() -> bool: return sim.zones.has_safe(), 120.0), "도착 + 설치 시간 뒤 안전구역")
	assert_eq(sim.command.post.jobs.size(), 0, "작업 끝")
