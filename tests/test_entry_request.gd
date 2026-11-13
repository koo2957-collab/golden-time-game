extends TestSuite
## 진입 허가 요청 (P10-2, 사용자 제안): 입구에서 멈춘 출동대가 무전으로 묻고, 질문 카드로 허가·대기·금지.
## 정답은 그때 상황(방어 전략·징후 → 금지, 공기·수관·RIT → 대기, 그 밖 → 허가), 디브리핑 '진입 통제'로 채점

const LIVING := Vector3i(13, 15, 1)


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	open_all_doors(sim)
	return sim


## 조 0을 거실로 보내 진입 허가 요청 카드가 뜰 때까지 진행. 카드 (없으면 null)
func _ask(sim: SimWorld, max_s := 60.0) -> CardSystem.Card:
	sim.issue(MoveCommand.new([0], LIVING))
	for i in roundi(max_s / SimClock.TICK_DT):
		sim.step_ticks(1)
		for c in sim.cards.queue:
			if c.id == "ENTRY-01":
				return c
	return null


## 카드의 선택지 중 effect가 같은 것을 고른다
func _answer(sim: SimWorld, c: CardSystem.Card, effect: String) -> void:
	for i in c.options.size():
		if str(c.options[i].effect) == effect:
			sim.issue(CommandOrder.make("card_answer", [], i, Vector3i.ZERO, {"uid": c.uid}))
			sim.step_ticks(1)
			return
	assert_true(false, "선택지 %s 없음" % effect)


func _rule(sim: SimWorld) -> Dictionary:
	return Evaluator.evaluate(sim).rules.filter(func(r: Dictionary) -> bool: return r.id == "safety.entry_judgment")[0]


func test_request_card_and_grant() -> void:
	var sim := _sim()
	var c := _ask(sim)
	assert_true(c != null, "입구에 오면 진입 허가 요청 카드")
	assert_eq(str(c.ctx.verdict), "grant", "준비 완료·위험 없음 → 허가가 정답 (%s)" % c.ctx.get("reason", ""))
	assert_true(c.text.contains("진입 허가 요청"), "카드 문구: %s" % c.text)
	assert_eq(c.options.size(), 3, "허가·대기·금지")
	assert_true(sim.events.of_type("entry_request").size() == 1, "무전이 끝난 뒤 한 번 요청")
	assert_true(not sim.command.can_enter(0), "답하기 전에는 들어가지 않는다")
	_answer(sim, c, "entry_grant")
	for i in 600:
		sim.step_ticks(1)
		if sim.command.can_enter(0):
			break
	assert_true(sim.command.can_enter(0), "허가 무전이 닿으면 진입 허가")
	var last: Dictionary = sim.command.entry_checks[-1]
	assert_eq(str(last.answer), "grant", "고른 답 기록")
	assert_eq(_rule(sim).score, 1.0, "정답이면 진입 통제 만점")


func test_wait_then_asks_again() -> void:
	var sim := _sim()
	var c := _ask(sim)
	_answer(sim, c, "entry_wait")
	assert_eq(sim.command.entry_checks[-1].answer, "wait", "대기 기록")
	assert_true(_rule(sim).score < 1.0 and _rule(sim).score > 0.0, "준비됐는데 대기 → 절반 (%s)" % _rule(sim).detail)
	sim.step_ticks(roundi(10.0 / SimClock.TICK_DT))
	assert_eq(sim.events.of_type("entry_request").size(), 1, "조건이 그대로면 바로 다시 묻지 않는다")
	sim.step_ticks(roundi(40.0 / SimClock.TICK_DT))
	assert_eq(sim.events.of_type("entry_request").size(), 2, "정한 시간이 지나면 다시 요청")


func test_low_air_wait_is_correct() -> void:
	var sim := _sim()
	for ff in sim.units.get_crew(0).members():
		ff.air_l = ff.air_capacity * 0.5
	var c := _ask(sim)
	assert_eq(str(c.ctx.verdict), "wait", "공기가 부족하면 대기가 정답 (%s)" % c.ctx.get("reason", ""))
	_answer(sim, c, "entry_grant")
	assert_eq(_rule(sim).score, 0.0, "그래도 허가하면 오답")
	assert_true(_rule(sim).detail.contains("정답: 대기"), "디브리핑에 정답과 근거: %s" % _rule(sim).detail)


func test_defensive_deny_cancels_and_stays_out() -> void:
	var sim := _sim()
	sim.command.strategy = CommandSystem.Strategy.DEFENSIVE
	var c := _ask(sim)
	assert_eq(str(c.ctx.verdict), "deny", "방어 전략이면 금지가 정답")
	_answer(sim, c, "entry_deny")
	assert_eq(sim.events.of_type("entry_denied").size(), 1, "진입 금지 사건")
	sim.step_ticks(roundi(60.0 / SimClock.TICK_DT))
	var leader := sim.units.get_crew(0).leader
	assert_true(sim.building.cell(leader.level, floori(leader.pos.x), floori(leader.pos.y)) in BuildingData.OUTDOOR, "밖에 머문다")
	assert_eq(sim.events.of_type("entry_request").size(), 1, "금지 뒤에는 다시 묻지 않는다")
	assert_eq(_rule(sim).score, 1.0, "정답")


func test_timeout_asks_again() -> void:
	# 제한 시간을 켰을 때의 동작 (2026-11-14부터 기본은 제한 시간 없음 — 답할 때까지 남는다)
	var sim := _sim()
	sim.cards.timed = true
	var c := _ask(sim)
	assert_true(c != null, "카드")
	sim.step_ticks(c.deadline_tick - sim.clock.tick + 1)
	assert_true(not sim.cards.queue.has(c), "답하지 않으면 카드가 사라진다")
	assert_true(sim.command.entry_requests.is_empty(), "요청을 비운다")
	sim.step_ticks(roundi(35.0 / SimClock.TICK_DT))
	assert_true(sim.events.of_type("entry_request").size() >= 2, "잠시 뒤 다시 요청")
