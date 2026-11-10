extends TestSuite
## 주수 방법 카드 (P10-2 결정 ②): 화점진압 조가 화점실 앞에서 묻고, 고른 주수로 방수한다.
## 정답은 화점실 상태(방 전체 탐 → 직사, 가스층 뜨거움 → 펜슬링 먼저, 배기구 없이 분무 → 오답)

const LIVING := Vector3i(13, 15, 1)


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.tactical.set_level("입문")
	sim.tactical.nozzle_cards = true
	return sim


func _until(sim: SimWorld, cond: Callable, max_s: float) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return cond.call()


func _card(sim: SimWorld) -> CardSystem.Card:
	for c in sim.cards.queue:
		if c.id == "NOZZLE-01":
			return c
	return null


func _answer(sim: SimWorld, c: CardSystem.Card, effect: String) -> void:
	for i in c.options.size():
		if str(c.options[i].effect) == effect:
			sim.issue(CommandOrder.make("card_answer", [], i, Vector3i.ZERO, {"uid": c.uid}))
			sim.step_ticks(1)
			return


func test_card_before_spraying_and_chosen_pattern() -> void:
	var sim := _sim()
	sim.issue(TacticalCommand.make("attack", [0], LIVING))
	assert_true(_until(sim, func() -> bool: return _card(sim) != null, 200.0), "화점실 앞에서 주수 방법 카드")
	var c := _card(sim)
	assert_eq(c.options.size(), 4, "직사·분무·펜슬링·엄호")
	assert_true(c.text.contains("주수 방법"), "문구: %s" % c.text)
	sim.step_ticks(20)
	assert_true(sim.water.hose_of_crew(0) == null or not sim.water.hose_of_crew(0).flowing, "답하기 전에는 쏘지 않는다")
	_answer(sim, c, "nozzle_straight")
	assert_true(_until(sim, func() -> bool:
		var h := sim.water.hose_of_crew(0)
		return h != null and h.flowing, 60.0), "답하면 방수")
	assert_eq(sim.water.hose_of_crew(0).pattern, HoseLine.Pattern.STRAIGHT, "고른 주수 = 직사")


func test_no_answer_defaults_to_fog() -> void:
	var sim := _sim()
	sim.issue(TacticalCommand.make("attack", [0], LIVING))
	assert_true(_until(sim, func() -> bool: return _card(sim) != null, 200.0), "카드")
	assert_true(_until(sim, func() -> bool:
		var h := sim.water.hose_of_crew(0)
		return h != null and h.flowing, 60.0), "답이 없으면 잠시 뒤 방수 시작")
	assert_eq(sim.water.hose_of_crew(0).pattern, HoseLine.Pattern.FOG, "기본 분무")
	assert_eq(sim.events.of_type("nozzle_default").size(), 1, "지시 없어 분무 기록")


func test_hot_layer_verdict_and_pencil_switch() -> void:
	var sim := _sim()
	var room := sim.fire.compartment_at(1, LIVING.x, LIVING.y)
	var t := TacticalSystem.Task.new()
	t.crew_id = 0
	t.action = "attack"
	t.room = room.index
	t.target = LIVING
	room.t_upper = 450.0
	room.flashed = false
	var info := sim.tactical.nozzle_info(t, sim.units.get_crew(0))
	assert_true(str(info.nv).begins_with("pencil"), "가스층이 뜨거우면 펜슬링 먼저 (%s)" % info.nv)
	assert_true(str(info.state).contains("뜨거움"), "관창수가 본 상태: %s" % info.state)
	room.flashed = true
	assert_true(str(sim.tactical.nozzle_info(t, sim.units.get_crew(0)).nv).begins_with("straight"), "방 전체가 타면 직사")
