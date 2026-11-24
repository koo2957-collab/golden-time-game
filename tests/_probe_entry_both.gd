extends SceneTree
## 점검용 (테스트 목록에 넣지 않음): 진압·구조 두 분대를 지시 창 층 임무로 같은 진입구에 보냈을 때 어디서 멈추는지
## 사용: godot --headless --path . -s res://tests/_probe_entry_both.gd


func _initialize() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/dev_squad_house_fire.json", true)
	sim.decision_pause = false
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 1500:
		sim.step_ticks(1)
		sim.cards.queue.clear()
	var attack := sim.units.get_crew(0)
	var rescue := sim.units.get_crew(1)
	var entry = null
	for e in sim.entries.list:
		if e.level == 1 and not e.neighbour and (entry == null or attack.leader.pos.distance_to(Vector2(e.door)) < attack.leader.pos.distance_to(Vector2(entry.door))):
			entry = e
	print("진입구 ", entry.index, " 문 ", entry.door, " 밖 ", entry.outside, " 전략 ", sim.command.strategy)
	sim.issue(CommandOrder.make("floor_mission", [rescue.squad_id] as Array[int], 1, Vector3i.ZERO, {"kind": "search", "entry": entry.index}))
	sim.issue(CommandOrder.make("floor_mission", [attack.squad_id] as Array[int], 1, Vector3i.ZERO, {"kind": "attack", "entry": entry.index}))
	var last := ""
	for i in 9000:
		sim.step_ticks(1)
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
			print("  t=", sim.clock.tick, " 카드 ", card.id, " → ", str(card.options[pick].get("text", "")).left(30), " (", card.options[pick].get("effect", ""), ")")
			sim.cards.answer(card.uid, pick, sim.clock.tick)
		var s := ""
		for c: Crew in [attack, rescue]:
			var dt := sim.doors.task_of_crew(c.id)
			var tk := sim.tactical.task_of_crew(c.id)
			s += "[%s task=%s %s mv=%s door=%s appr=%s fm=%s allowed=%s] " % [sim.units.crew_name(c),
				"-" if tk == null else "%s/p%d/h%s" % [tk.action, tk.phase, tk.halted], c.leader.cell3(), c.leader.is_moving(),
				"없음" if dt == null else ("대기" if dt.stacked(c.id) else "엶 %.0f/%.0f" % [dt.progress, dt.required]),
				sim.command.approach.has(c.id), sim.command.floor_missions.get(c.id, "-"), sim.command.entry_allowed.has(c.squad_id)]
		if s != last and i % 10 == 0:
			last = s
			print("t=", sim.clock.tick, " ", s)
	for e in sim.events.entries.slice(-30):
		print("  사건 ", e.tick, " ", SimEventLog.describe_text(e))
	quit()
