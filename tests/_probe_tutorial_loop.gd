extends SceneTree
## 점검용 (테스트 목록에 넣지 않음, 2026-11-25): 튜토리얼에서 철수한 구조 분대가 10초마다 불난 거실 쪽으로 다시 길을 잡다
## 열기에 막히는 것을 누가 시키는지 찾는다. 사용: godot --headless --path . -s res://tests/_probe_tutorial_loop.gd


func _answer(sim: SimWorld) -> void:
	for card in sim.cards.queue.duplicate():
		var pick := -1
		for k in card.options.size():
			if str(card.options[k].get("effect", "")) in ["entry_grant", "force_door", "open_door", "vent_then_open"]:
				pick = k
				break
		for k in card.options.size():
			if pick < 0 and str(card.options[k].get("grade", "")) == "최선":
				pick = k
		pick = maxi(pick, 0)
		print("  t=", sim.clock.tick, " 카드 ", card.crew_id, " ", card.id, " → ", str(card.options[pick].get("text", "")).left(28))
		sim.cards.answer(card.uid, pick, sim.clock.tick)


func _initialize() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/tutorial_basics.json", true)
	sim.decision_pause = false
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 600:
		sim.step_ticks(1)
		_answer(sim)
	sim.command.strategy = CommandSystem.Strategy.OFFENSIVE
	var entry = null
	for e in sim.entries.list:
		if e.level == 1 and not e.neighbour:
			entry = e
			break
	for c in sim.units.crews:
		var kind := str(sim._default_mission(c))
		if kind in ["attack", "search"] and not c.leader.aboard:
			sim.issue(CommandOrder.make("floor_mission", [c.squad_id] as Array[int], 1, Vector3i.ZERO, {"kind": kind, "entry": entry.index}))
			print("지시 ", sim.units.crew_name(c), " ", kind)
	var watch := sim.units.get_crew(1)
	var last_path := ""
	for i in 9000:
		sim.step_ticks(1)
		_answer(sim)
		var p := watch.leader.path
		var goal := "-" if p.is_empty() else str(p.back())
		if goal != last_path:
			last_path = goal
			var t := sim.tactical.task_of_crew(watch.id)
			var rt = sim.rescue.task_of_crew(watch.id)
			print("t=%d %s 자리=%s 길끝=%s 전술=%s 구조=%s 층목표=%s 접근=%s 층임무=%s 열스트레스=%.2f" % [sim.clock.tick, sim.units.crew_name(watch),
				watch.leader.cell3(), goal, "-" if t == null else "%s/p%d" % [t.action, t.phase], "-" if rt == null else rt.get_class(),
				sim.command.floor_goals.get(watch.id, "-"), sim.command.approach.has(watch.id), sim.command.floor_missions.get(watch.id, "-"),
				watch.leader.heat_stress])
		if watch.leader.incapacitated:
			print("쓰러짐 t=", sim.clock.tick)
			break
	quit()
