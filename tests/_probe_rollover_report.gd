extends SceneTree
## 점검용 (테스트 목록에 넣지 않음, 2026-11-25): 실제 진행에서 롤오버 징후 보고가 나올 때 누가 어디서 봤는가.
## 사용: godot --headless --path . -s res://tests/_probe_rollover_report.gd -- [시나리오]


func _answer(sim: SimWorld) -> void:
	for card in sim.cards.queue.duplicate():
		var pick := 0
		for k in card.options.size():
			if str(card.options[k].get("grade", "")) == "최선":
				pick = k
		sim.cards.answer(card.uid, pick, sim.clock.tick)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if not args.is_empty() else "res://data/scenarios/sop214_1_day_living.json"
	var sim := SimWorld.from_scenario(path, true)
	sim.decision_pause = false
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 600:
		sim.step_ticks(1)
		_answer(sim)
	sim.command.strategy = CommandSystem.Strategy.OFFENSIVE
	var entry = null
	for e in sim.entries.list:
		if not e.neighbour:
			entry = e
			break
	for c in sim.units.crews:
		var kind := str(sim._default_mission(c))
		if kind in ["attack", "search"] and not c.leader.aboard:
			sim.issue(CommandOrder.make("floor_mission", [c.squad_id] as Array[int], entry.level, Vector3i.ZERO, {"kind": kind, "entry": entry.index}))
	var seen := 0
	for i in 6000:
		sim.step_ticks(1)
		_answer(sim)
		var ev := sim.events.of_type("rollover_sign")
		if ev.size() > seen:
			seen = ev.size()
			var e: Dictionary = ev[-1]
			var room: Compartment = null
			for c in sim.fire.comps:
				if c.display_name() == str(e.room):
					room = c
			print("t=%d 롤오버 징후 %s · 지휘관 %s" % [sim.clock.tick, e.room, sim.perception.commander.pos if sim.perception.commander else "-"])
			for c in sim.units.crews:
				var l := c.leader
				if l.aboard:
					continue
				var indoor := sim.building.cell(l.level, floori(l.pos.x), floori(l.pos.y)) not in BuildingData.OUTDOOR
				var in_room := room != null and sim.fire.compartment_at(l.level, floori(l.pos.x), floori(l.pos.y)) == room
				print("   %s 자리 %s %d층 건물 안 %s 그 방 안 %s 문 작업 %s 임무 %s" % [sim.units.crew_name(c), l.pos.snapped(Vector2(0.1, 0.1)), l.level, indoor, in_room,
					sim.doors.task_of_crew(c.id) != null, sim.tactical.mission_text(c.id)])
			if room:
				var by_crew := 0
				var by_any := 0
				for y in range(room.rect.position.y, room.rect.end.y):
					for x in range(room.rect.position.x, room.rect.end.x):
						if sim.fire.compartment_at(room.level, x, y) == room:
							by_crew += 1 if sim.perception.is_crew_visible(room.level, x, y) else 0
							by_any += 1 if sim.perception.is_visible(room.level, x, y) else 0
				print("   그 방: 대원 눈 %d칸 · 창 너머 포함 %d칸 · 연기층 %.1fm · 상부 %d℃" % [by_crew, by_any, room.layer_depth, roundi(room.t_upper)])
				for o in sim.fire.openings:
					if (o.room_a == room.index or o.room_b == room.index):
						print("     개구부 %d %s 열림 %s 깨짐 %s" % [o.index, "문" if o.kind == Opening.Kind.DOOR else "창", o.is_open, o.get("broken") if "broken" in o else "-"])
	print("끝 t=", sim.clock.tick)
	quit()
