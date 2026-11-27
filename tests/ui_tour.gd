extends SceneTree
## 시나리오 한 판 둘러보기 (창이 열린다, 2026-11-17 — 기능 전체 버그 찾기용):
## 출동 장면 → 도착 → 분대마다 지시 창으로 층 임무(진입구·진입 허가·계단 카드) → 모든 층 내부·외부 보기 →
## 전술상황판 → 질문 카드는 최선으로 답하며 현장 시간 진행 → 활동 종료 → 디브리핑.
## 오류(SCRIPT ERROR)는 표준 오류로 나오므로 시나리오마다 따로 돌려 가린다.
## 사용: godot --path . -s res://tests/ui_tour.gd -- res://data/scenarios/xxx.json [현장 분]

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if not args.is_empty() else "res://data/scenarios/sop213_1_apartment_3f.json"
	var minutes: float = float(args[1]) if args.size() > 1 else 8.0
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = path
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	var sim: SimWorld = world.sim
	_check("시나리오를 불러옴 (%s)" % path.get_file(), sim != null, true)
	if sim == null:
		_finish()
		return
	sim.decision_pause = false
	world.hud.card_ui.pauses = Callable()
	if world.hud.tutorial_ui:
		world.hud.tutorial_ui.visible = false
	# 1) 출동 장면: 고를 것은 첫 선택지로 넘긴다
	var d = world.hud.command_ui.dispatch
	for n in 80:
		d._gap = 0.0
		for i in 2:
			await process_frame
		var s: Dictionary = d.current()
		if s.is_empty():
			break
		if str(s.mode) == "multi":
			d.confirm()
		elif str(s.mode) == "select" or str(s.kind) == "preassign":
			d.choose(0)
			d.confirm()
		else:
			d.choose(0)
	d.skip()
	for i in 900:
		if not d.active:
			break
		await process_frame
	_check("출동 장면이 끝남", d.active, false)
	# 도착할 때까지 (현장 시간을 빠르게)
	sim.clock.speed = 4.0
	for i in 600:
		_answer_cards(sim)
		if not sim.command.resources.arriving.is_empty() or not sim.command.resources.alighting.is_empty() or sim.command.commander.aboard:
			sim.step_ticks(5)
			await process_frame
		else:
			break
	for i in 300:
		if not world.camera.locked:
			break
		await process_frame
	world.hud.command_ui.close_all()
	print("  도착 뒤 %d초 · 타는 칸 %d · 끝남 %s (%s)" % [roundi(sim.clock.tick * SimClock.TICK_DT), sim.fire.grid.burning.size(), sim.ended(), str(sim.end_type)])
	for e in sim.events.entries:
		if str(e.type) in ["tactical_done", "tactical_halt", "card_answered", "card_asked", "crew_decided", "door_task_start", "equipment_missing", "spray_start", "knockdown_reported", "fire_out", "crew_withdraw"]:
			print("  ▷ ", e)
	for c in sim.units.crews:
		var t = sim.tactical.task_of_crew(c.id)
		var h = sim.water.hose_of_crew(c.id)
		print("  ◦ %s %s 걷는 중 %s 길 %d · 전술 %s · 문 작업 %s · 수관 %s · 진입 대기 %s · 허가 %s" % [sim.units.crew_name(c), c.leader.pos, c.leader.is_moving(), c.leader.path.size(),
			("%s 단계%d 문%d 멈춤%s" % [t.action, t.phase, t.doors.size(), t.halted]) if t else "-", sim.doors.task_of_crew(c.id) != null,
			("충수%s 흐름%s" % [h.charged if "charged" in h else "?", h.flowing]) if h else "-", sim.command._entry_waiting.has(c.id), sim.command.can_enter(c.squad_id)])
	# 2) 보기: 외부 → 층마다 내부 → 외부. 층마다 외벽 띠·바깥 땅 위 노란 안내도 한 번씩
	var sel = world.selection
	var ground: int = sim.building.levels()[0]
	world.set_view_level(ground, true)
	await process_frame
	for lv in sim.building.levels():
		world.set_view_level(lv, false)
		for i in 2:
			await process_frame
		sel._update_guide(world.camera.position, -1)
	world.set_view_level(ground, true)
	await process_frame
	# 3) 분대마다 지시 창으로 층 임무 (진압대 → 발화층 화재진압, 구조대 → 발화층 인명검색). 구급대는 건물 안 임무 없음
	var fire_lv := _fire_level(sim)
	var mui = world.mission_ui
	var ordered := 0
	# 출동대가 4개 이상이면 RIT부터 (SSG 9 — 없으면 진입 허가의 정답이 '대기'): 마지막 진압·구조 분대
	var rit := -1
	if sim.units.squads.size() >= 4:
		for c in sim.units.crews:
			if not c.solo and not c.leader.aboard and sel.default_kind(c.id) != "":
				rit = c.id
		if rit >= 0:
			sim.issue(CommandOrder.make("role", [rit] as Array[int], SafetySystem.Role.RIT))
			sim.step_ticks(2)
	for c in sim.units.crews:
		if c.solo or c.leader.aboard or c.leader.incapacitated or c.id == rit:
			continue
		sel._set_selection([c.id] as Array[int], [] as Array[int])
		if sel.default_kind(c.id) == "":
			continue
		var n0 := sim.issued.size()
		sel.order_floor(fire_lv, Vector2(600, 300))
		await process_frame
		# 층 우클릭 = 지시 창 없이 그 분대의 기본 임무를 바로 (2026-11-26 사용자 결정)
		if mui.order.visible:
			mui.confirm_order()
		if sim.issued.size() > n0:
			ordered += 1
	_check("층을 우클릭해 층 임무를 줬다 (%d개 분대)" % ordered, ordered > 0, true)
	print("  발화층 %d · 명령 기록 마지막 %s" % [fire_lv, sim.issued.slice(-ordered).map(func(x): return "%s %s" % [x.command.get_class(), str(x.command.get("action"))])])
	sim.step_ticks(5)
	for e in sim.events.entries.slice(-20):
		if str(e.type).contains("reject") or str(e.type).contains("delay") or str(e.type).contains("span") or str(e.type).contains("entry") or str(e.type).contains("floor"):
			print("  ◇ ", e)
	sel._set_selection([] as Array[int], [] as Array[int])
	# 4) 전술상황판 열고 닫기
	world.hud.board.toggle()
	for i in 3:
		await process_frame
	world.hud.board.toggle()
	await process_frame
	# 5) 현장 시간 진행: 질문 카드는 최선으로 (진입 허가·계단 등). 화면은 발화층 내부
	world.set_view_level(fire_lv, false)
	var end_tick := sim.clock.tick + roundi(minutes * 60.0 / SimClock.TICK_DT)
	var answered := 0
	while sim.clock.tick < end_tick and not sim.ended():
		answered += _answer_cards(sim)
		sim.step_ticks(20)
		await process_frame
	var entered := sim.events.of_type("crew_entered").size()
	# 분대 상태 (진입이 안 될 때 원인 보기)
	for c in sim.units.crews:
		if c.solo:
			continue
		print("  · %s 위치 %s %d층 걷는 중 %s · 진입구 %d · 층 목표 %d · 층 임무 '%s' · 진입 허가 %s · 임무 %s" % [sim.units.crew_name(c), c.leader.pos, c.leader.level,
			c.leader.is_moving(), int(sim.command.approach.get(c.id, -1)), int(sim.command.floor_goals.get(c.id, -1)), str(sim.command.floor_missions.get(c.id, "")),
			sim.command.can_enter(c.squad_id), sim.tactical.mission_text(c.id)])
	for e in sim.events.entries:
		if str(e.type) in ["entry_approach", "entry_request", "entry_wait", "floor_reached", "tactical_start", "tactical_halt", "floor_unreachable", "preassign_start", "hose_laid", "card_answered", "crew_entered", "squad_staged", "vehicle_arrived", "ff_down", "mayday", "air_alarm", "heat_retreat", "withdraw", "heat_stress_retreat", "heat_stress_high", "heat_blocked", "crew_trapped", "hose_left_heat", "withdraw_resume", "hose_abandoned", "air_swap_out", "air_swap_done", "hose_recover", "nozzle_dropped", "door_stack",
				"spray_start", "spray_stop", "tactical_done", "tactical_next", "rekindle", "card_asked", "knockdown_reported"] \
				and (int(e.tick) < 4000 or str(e.type) != "entry_request"):
			print("  > ", e)
	print("  자동화 수준 ", sim.tactical.level_name, " · 난이도 ", sim.realism, " · 진입 명령 규칙 ", sim.command.entry_order_required)
	# 밖에서(문·창 너머) 화점을 잡으면 들어가지 않아도 된다 (실전에서 출동 중 정한 화재진압이 그렇다)
	var knocked := sim.events.of_type("tactical_done").any(func(e: Dictionary) -> bool: return str(e.text).contains("진압"))
	# 샌드위치패널 창고처럼 방어 전략으로 지켜보다 전소로 끝나는 시나리오도 있다 (지시 전에 끝남)
	var burnt_out := sim.ended() and str(sim.end_type) == "전소"
	_check("대원이 들어갔거나 화점을 잡았다 (진입 %d회 · 카드 %d장 답함)" % [entered, answered], entered > 0 or knocked or burnt_out, true)
	var started := sim.events.of_type("tactical_start").size()
	_check("층 임무가 시작됐다 (%d건)" % started, started > 0 or burnt_out, true)
	# 6) 활동 종료 → 디브리핑
	if not sim.ended():
		var cui = world.hud.command_ui
		cui.open_end_confirm()
		cui.confirm_end()
	for i in 30:
		sim.step_ticks(1)
		await process_frame
		if world.hud.debrief.visible:
			break
	_check("디브리핑", world.hud.debrief.visible, true)
	var report: Dictionary = world._last_report
	_check("평가 규칙이 나온다 (%d개)" % report.get("rules", []).size(), report.get("rules", []).size() > 0, true)
	_finish()


## 떠 있는 질문 카드에 최선으로 답한다 (없으면 첫 선택지). 답한 수
func _answer_cards(sim: SimWorld) -> int:
	var n := 0
	for k in 4:
		var c: CardSystem.Card = sim.cards.active()
		if c == null:
			break
		var pick := 0
		for i in c.options.size():
			if str(c.options[i].get("grade", "")) == "최선":
				pick = i
		if not sim.cards.answer(c.uid, pick, sim.clock.tick):
			sim.cards.queue.erase(c)
		n += 1
	return n


## 불이 난 층 (발화 사건의 방, 없으면 가장 낮은 층)
func _fire_level(sim: SimWorld) -> int:
	var ign := sim.events.of_type("ignition")
	if not ign.is_empty():
		for c in sim.fire.comps:
			if c.display_name() == str(ign[0].get("room", "")):
				return c.level
	for i in sim.fire.grid.burning:
		return sim.fire.grid.cell_of(i).z
	return sim.building.levels()[0]


func _finish() -> void:
	print("결과: %s (실패 %d)" % ["통과" if _failed == 0 else "실패", _failed])
	quit(1 if _failed > 0 else 0)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	var ok: bool = actual == expected
	if not ok:
		_failed += 1
	print("%s  %s%s" % ["통과" if ok else "실패", label, "" if ok else "  (결과: %s, 기대: %s)" % [actual, expected]])
