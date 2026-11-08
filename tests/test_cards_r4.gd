extends TestSuite
## R4: 질문 카드 확장 — 기존 위험 사건을 카드로, 카드 28장, 정보 확인, 대피 방송

const NIGHT := "res://data/scenarios/sop213_2_apartment_night.json"
const APT := "res://data/scenarios/sop213_1_apartment_3f.json"
const LPG := "res://data/scenarios/sop214_3_kitchen_lpg.json"
const SHOP := "res://data/scenarios/sop212_1_commercial_kitchen.json"


func _sim(path: String) -> SimWorld:
	var sim := SimWorld.from_scenario(path)
	sim.command.resources.clear_schedule()
	return sim


func _card(sim: SimWorld, id: String) -> CardSystem.Card:
	for c in sim.cards.queue:
		if c.id == id:
			return c
	return null


func _answer(sim: SimWorld, c: CardSystem.Card, grade: String) -> void:
	for i in c.options.size():
		if c.options[i].grade == grade:
			sim.cards.answer(c.uid, i, sim.clock.tick)
			return


func test_card_set() -> void:
	var data: Dictionary = JsonData.load_file("res://data/cards/cards.json")
	assert_true(data.cards.size() >= 28, "카드 %d장 (기획안 7-3 아파트 약 30장)" % data.cards.size())
	assert_true(data.preorders.size() >= 12, "선제지시 %d종" % data.preorders.size())
	var sim := _sim(APT)
	var known := ["halt_locked", "halt_closed", "halt_backdraft", "halt_victim", "air_alarm", "knockdown", "arrival", "rollover_sign",
		"jump_risk", "exposure_heating", "shaft", "sign_warning", "debris_zone", "hydrant_out", "tank_empty", "mayday", "gas_found",
		"victim_trapped", "triage_urgent", "stair_smoke", "attack_upper", "victims_many", "first_search", "search_mark", "end_suggested"]
	for spec: Dictionary in data.cards:
		assert_true(str(spec.trigger) in known, "%s 트리거 '%s' 처리됨" % [spec.id, spec.trigger])
	sim.step_ticks(3)
	assert_true(_card(sim, "ARRIVAL-WATER-01") != null, "도착하면 예비 소방용수 카드")
	_answer(sim, _card(sim, "ARRIVAL-WATER-01"), "최선")
	sim.events.add(sim.clock.tick, "phase", {"phase": "지휘권 확립", "index": 1})
	sim.step_ticks(1)
	assert_true(_card(sim, "ARRIVAL-WATER-01") == null, "once 카드는 한 번만")


func test_jump_card_orders_air_mat() -> void:
	var sim := _sim(NIGHT)
	var v := sim.rescue.victims[0]
	sim.events.add(1, "jump_risk", {"who": v.label(), "room": "4층 402호 거실", "crew": "현장 대원"})
	sim.cards.step(0.1, 1)
	var c := _card(sim, "JUMP-01")
	assert_true(c != null and c.text.contains(v.label()), "추락 위험 카드")
	_answer(sim, c, "최선")
	assert_eq(sim.falls.setups.size(), 1, "구조대가 창 아래로 매트 설치하러 감")


func test_hydrant_card_info_check_then_shuttle() -> void:
	var sim := _sim(LPG)
	sim.events.add(1, "hydrant_out", {"vehicle": "진압1 물탱크차", "driver": "x"})
	sim.cards.step(0.1, 1)
	var c := _card(sim, "HYDRANT-OUT-01")
	assert_true(c != null, "소화전 고장 카드")
	_answer(sim, c, "허용")
	assert_true(sim.shuttle.tankers.is_empty(), "정보 확인 중에는 아직")
	assert_eq(sim.events.of_type("card_info_check").size(), 1, "정보 확인 기록")
	sim.step_ticks(roundi(31.0 / SimClock.TICK_DT))
	assert_true(not sim.shuttle.tankers.is_empty(), "30초 뒤 순환보수 지정")


func test_stair_smoke_shelter() -> void:
	var sim := _sim(SHOP)
	sim.events.add(1, "smoke", {"room": "2층 계단실"})
	sim.cards.step(0.1, 1)
	var c := _card(sim, "STAIR-SMOKE-01")
	assert_true(c != null, "계단실 연기 — 주민 안내 카드")
	_answer(sim, c, "최선")
	assert_eq(sim.evac.instruction, "shelter", "세대 안 대기 방송")
	sim.step_ticks(roundi(200.0 / SimClock.TICK_DT))
	assert_eq(sim.evac.escaped.size(), 0, "대기 안내를 받으면 연기 찬 계단으로 나서지 않음")
	var house := _sim("res://data/scenarios/sop214_1_day_living.json")
	house.events.add(1, "smoke", {"room": "1층 계단실"})
	house.cards.step(0.1, 1)
	assert_true(_card(house, "STAIR-SMOKE-01") == null, "2층 주택은 주민 방송 카드 없음")


func test_upper_attack_cards_and_rollover() -> void:
	var sim := _sim(APT)
	sim.events.add(1, "tactical_start", {"crew": "진압1 1조", "action": "진압", "room": "3층 301호 거실"})
	sim.cards.step(0.1, 1)
	assert_true(_card(sim, "STANDPIPE-01") != null and _card(sim, "STAGING-FLOOR-01") != null, "상층 진압 → 연결송수관·장비 집결 카드")
	_answer(sim, _card(sim, "STANDPIPE-01"), "최선")
	assert_true(not sim.events.of_type("fdc_connected").is_empty() or not sim.events.of_type("fdc_too_far").is_empty(), "송수구 연결 시도")
	var h := _sim("res://data/scenarios/sop214_1_day_living.json")
	h.events.add(1, "rollover_sign", {"room": "1층 거실"})
	h.cards.step(0.1, 1)
	var c := _card(h, "ROLLOVER-01")
	assert_true(c != null and c.urgency == "긴급", "롤오버 카드 (긴급)")
	assert_true(c.crew_id >= 0, "가까운 조가 묻는다")
