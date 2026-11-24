extends SceneTree
## 점검용 (테스트 목록에 넣지 않음): 진압 지시 뒤 진압 분대가 어디서 멈추는지 적는다
## 사용: godot --headless --path . -s res://tests/_probe_hose_leave.gd


func _initialize() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/dev_squad_house_fire.json", false)
	sim.tactical.set_level("입문")
	sim.command.strategy = CommandSystem.Strategy.OFFENSIVE
	var crew := sim.units.get_crew(0)
	var target := Vector3i(-1, -1, -1)
	for k in 6000:
		for i in sim.fire.grid.burning:
			target = sim.fire.grid.cell_of(i)
			break
		if target.x >= 0:
			break
		sim.step_ticks(1)
	print("불 시작 tick=", sim.clock.tick, " 목표=", target, " 조장=", crew.leader.cell3(), " 탑승=", crew.leader.aboard)
	print("order=", sim.tactical.order("attack", crew.id, target, sim.clock.tick))
	var last := ""
	for i in 12000:
		sim.step_ticks(1)
		for card in sim.cards.queue.duplicate():
			var pick := 0
			for k in card.options.size():
				if str(card.options[k].get("grade", "")) == "최선":
					pick = k
			print("  카드 ", card.id, " → ", card.options[pick].get("text", ""))
			sim.cards.answer(card.uid, pick, sim.clock.tick)
		var h := sim.water.hose_of_crew(crew.id)
		var t := sim.tactical.task_of_crew(crew.id)
		var s := "hose=%s task=%s pos=%s moving=%s" % [
			"없음" if h == null else "to_outlet=%s fetch=%d flow=%s spray=%s appr=%s charged=%s pts=%d" % [h.to_outlet, h.fetch_until, h.flowing, h.spraying, h.approaching, h.charged, h.points.size()],
			"없음" if t == null else "%s phase=%d halted=%s doors=%d" % [t.action, t.phase, t.halted, t.doors.size()],
			crew.leader.cell3(), crew.leader.is_moving()]
		if s != last and i % 20 == 0:
			last = s
			print("t=", sim.clock.tick, " ", s)
	for e in sim.events.entries.slice(-25):
		print("  사건 ", e.tick, " ", SimEventLog.describe_text(e))
	quit()
