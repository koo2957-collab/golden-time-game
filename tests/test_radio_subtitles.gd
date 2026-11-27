extends TestSuite
## 무전 자막 줄 (2026-11-27 사용자 결정): 무전은 위쪽 알림 칩이 아니라 아래 자막 줄 한 곳에 — 말한 쪽 배지·이름,
## 대원이 말하면 머리 위 말풍선, 대원 안전 무전이면 긴급 띠


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.command.resources.clear_schedule()
	return sim


func test_speaker_color_and_signals() -> void:
	var sim := _sim()
	var sub := RadioSubtitles.new()
	sub.setup(sim)
	var c: Crew = sim.units.crews[0]
	var name := sim.units.crew_name(c)
	var sp := sub.speaker_of(name)
	assert_eq([sp.color, sp.crew], [sim.units.squads[c.squad_id].color, c], "조 이름 → 분대 색·그 조")
	var sq: String = sim.units.squads[c.squad_id].name
	assert_eq(sub.speaker_of(sq + " 펌프차").color, sim.units.squads[c.squad_id].color, "출동대 이름으로 시작하면 그 출동대 색 (차량 운전원)")
	assert_eq(sub.speaker_of(CommandSystem.COMMANDER).label, "지휘", "현장지휘관 배지")
	var barks: Array = []
	var urgents: Array = []
	sub.bark.connect(func(_p: Vector2, _l: int, _c: Color, t: String, _s: float) -> void: barks.append(t))
	sub.urgent.connect(func(who: String, body: String, _c: Color, _lab: String, _p: Vector2, _l: int) -> void: urgents.append([who, body]))
	sim.command.radio.send(Radio.Priority.TACTICS, name, CommandSystem.COMMANDER, "진입 준비 완료.", sim.clock.tick)
	sim.command.radio.send(Radio.Priority.SAFETY, name, CommandSystem.COMMANDER, "공기 경보, 탈출합니다.", sim.clock.tick)
	for i in 600:
		sim.step_ticks(1)
		sub.refresh()
		if barks.size() >= 2:
			break
	assert_eq(barks, ["공기 경보, 탈출합니다.", "진입 준비 완료."], "대원이 무전을 시작할 때마다 머리 위 말풍선 (대원 안전이 먼저 송신)")
	assert_eq(urgents, [[name, "공기 경보, 탈출합니다."]], "대원 안전 무전만 긴급 띠")
	assert_true(sub.lines_text().contains("공기 경보") and sub.lines_text().contains("진입 준비") and sub.lines_text().contains(name), "자막 줄에 말한 쪽 이름과 본문")
	sub.free()
