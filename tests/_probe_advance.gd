extends SceneTree
## 방수 중 전진 판단 점검 (테스트 목록에 넣지 않음): godot --headless --path . -s res://tests/_probe_advance.gd
## 2026-11-27: 5초마다 방수 대형이 풀리는 원인 — 관창수가 접근(approaching)으로 바뀔 때마다 어디서 어디로 가려 했는지 적는다


func _initialize() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/sop214_1_day_living.json", true)
	sim.decision_pause = false
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 900:
		sim.step_ticks(1)
		_answer(sim)
		if i > 30 and not sim.command.resources.arriving_now() and not sim.units.crews[0].leader.aboard:
			break
	sim.command.strategy = 0
	var att: Crew = null
	for c in sim.units.crews:
		if sim.units.squads[c.squad_id].type == "진압대" and att == null:
			att = c
	sim.issue(CommandOrder.make("floor_mission", [att.id], 1, Vector3i.ZERO, {"kind": "attack", "entry": -1}))
	for c in sim.units.crews:
		if sim.units.squads[c.squad_id].type == "구조대":
			sim.issue(CommandOrder.make("floor_mission", [c.id], 1, Vector3i.ZERO, {"kind": "search", "entry": -1}))
			break
	var was := ""
	var n := 0
	for i in 2600:
		sim.step_ticks(1)
		_answer(sim)
		var h := sim.water.hose_of_crew(att.id)
		if h == null:
			continue
		var now := "방수 %s · 접근 %s · 걷는중 %s · 잡음 %s · 충수 %s" % [h.flowing, h.approaching, att.leader.is_moving(), h.held(), h.charged]
		if now != was and sim.clock.tick > 700:
			n += 1
			if n < 60:
				var task := sim.tactical.task_of_crew(att.id)
				print("t=%5.1f %s | 선두 %s 겨눔 %s 임무 %s" % [sim.clock.tick * 0.1, now, att.leader.cell3(), h.aim.snappedf(0.1),
					("%s/%s 단계 %s" % [task.action, task.floor_action, task.phase]) if task else "없음"])
		was = now
	print("전진 바뀜 %d회" % n)
	quit()


func _answer(sim: SimWorld) -> void:
	for card in sim.cards.queue.duplicate():
		var pick := 0
		for k in card.options.size():
			if str(card.options[k].get("grade", "")) == "최선":
				pick = k
		sim.cards.answer(card.uid, pick, sim.clock.tick)
