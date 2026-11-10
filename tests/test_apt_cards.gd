extends TestSuite
## P9: 기획안 7-3 아파트 카드 중 없던 5장 — 물탱크차 첫 조치·대피 세대 순서·화점 못 찾음·RIT 다른 임무·송풍기 배기구

const APT15 := "res://data/scenarios/sop213_3_15f_day_low.json"
const APT3 := "res://data/scenarios/sop213_1_apartment_3f.json"


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


func _tanker(sim: SimWorld) -> Vehicle:
	for v in sim.units.vehicles:
		if v.transfer_lpm > 0.0:
			return v
	return null


func test_tanker_first_action() -> void:
	var sim := _sim(APT15)
	var tk := _tanker(sim)
	assert_true(tk != null, "선착 물탱크차가 있다")
	var name := tk.display_name(sim.units.squads[tk.squad_id].name)
	sim.events.add(1, "vehicle_arrived", {"vehicle": name, "driver": tk.driver_label(), "squad": sim.units.squads[tk.squad_id].name})
	sim.cards.step(0.1, 1)
	var c := _card(sim, "TANKER-FIRST-01")
	assert_true(c != null and c.text.contains("물탱크차"), "물탱크차가 서면 운전원이 첫 조치를 묻는다")
	_answer(sim, c, "최선")
	sim.step_ticks(roundi(120.0 / SimClock.TICK_DT))
	assert_true(tk.supply_to >= 0 or tk.pending_supply >= 0 or not tk.work.is_empty(), "펌프차 급수 연결 (supply_to %d)" % tk.supply_to)
	# 오답: 연결 없이 대기
	var sim2 := _sim(APT15)
	var tk2 := _tanker(sim2)
	sim2.events.add(1, "vehicle_arrived", {"vehicle": tk2.display_name(sim2.units.squads[tk2.squad_id].name), "driver": "", "squad": ""})
	sim2.cards.step(0.1, 1)
	_answer(sim2, _card(sim2, "TANKER-FIRST-01"), "오답")
	sim2.step_ticks(roundi(120.0 / SimClock.TICK_DT))
	assert_eq(tk2.supply_to, -1, "오답이면 급수 연결 없음")
	assert_eq(sim2.events.of_type("tanker_idle").size(), 1, "대기 기록")


func test_evac_order_card_and_effect() -> void:
	var sim := _sim(APT15)
	sim.events.add(1, "strategy_set", {"strategy": "공격"})
	sim.cards.step(0.1, 1)
	var c := _card(sim, "EVAC-ORDER-01")
	assert_true(c != null and c.text.contains("%d층" % sim.fire_floor_reported()), "5층 이상 공동주택: 전략 뒤 대피 순서 카드 (%s)" % (c.text if c else "없음"))
	_answer(sim, c, "최선")
	assert_eq(sim.evac.priority, "fire_first", "발화층·직상층 먼저")
	# 안내 시각: 발화층·직상층 주민은 곧바로, 1층부터면 위층일수록 늦다
	var v := Victim.new()
	v.self_evac = true
	v.alert_s = 300.0
	v.level = sim.fire_floor_reported() + 1
	assert_true(sim.evac._alert_tick(v) <= 1, "직상층 주민은 안내 즉시 나선다")
	sim.evac.set_priority("bottom_up", sim.fire_floor_reported(), 0)
	v.level = 10
	assert_true(sim.evac._alert_tick(v) > roundi(300.0 / SimClock.TICK_DT), "1층부터면 10층 주민은 스스로 알아챘어도 안내를 늦게 받는다")
	# 저층(3층) 아파트에서는 묻지 않는다
	var low := _sim(APT3)
	low.events.add(1, "strategy_set", {"strategy": "공격"})
	low.cards.step(0.1, 1)
	assert_true(_card(low, "EVAC-ORDER-01") == null, "5층 미만이면 묻지 않음")


func test_fire_not_found_report() -> void:
	var sim := _sim(APT15)
	sim.tactical._fire_lost_ticks = 50
	sim.tactical._fire_lost_vis_m = 1000.0  # 시계 조건을 늘 참으로
	var c0 := sim.units.crews[0]
	# 조를 발화층 세대 안에 두고 화점진압 임무 (물을 대지 못한 채)
	var lv := sim.fire_floor_reported()
	var room: Compartment = null
	for comp in sim.fire.comps:
		if comp.level == lv and comp.display_name().contains("방"):
			room = comp
			break
	var cell: Vector2i = room.cells[0]
	for ff in c0.members():
		ff.level = lv
		ff.pos = Vector2(cell) + Vector2(0.5, 0.5)
		ff.path.clear()
	sim.tactical._attack_since[c0.id] = 0
	var t := TacticalSystem.Task.new()
	t.crew_id = c0.id
	t.action = "attack"
	t.room = room.index
	t.phase = TacticalSystem.Phase.WORKING
	sim.tactical.tasks.append(t)
	sim.tactical._check_fire_lost(100)
	var e := sim.events.of_type("fire_not_found")
	assert_eq(e.size(), 1, "화점 못 찾음 보고")
	sim.cards.step(0.1, 100)
	var c := _card(sim, "FIRE-LOST-01")
	assert_true(c != null and c.urgency == "긴급", "긴급 카드")
	_answer(sim, c, "최선")
	assert_true(sim.tactical.task_of_crew(c0.id) == null or sim.tactical.task_of_crew(c0.id).action != "attack", "철수 지시")
	sim.tactical._check_fire_lost(200)
	assert_eq(sim.events.of_type("fire_not_found").size(), 1, "한 번만 보고")


func test_rit_help_card() -> void:
	var sim := _sim(APT15)
	var rit := sim.units.crews[3].id
	sim.command.safety.roles[rit] = SafetySystem.Role.RIT
	var hose_crew := sim.units.crews[0]
	sim.events.add(1, "hose_resupply", {"crew": "진압1 1조", "crew_id": hose_crew.id, "lengths": 4})
	sim.cards.step(0.1, 1)
	var c := _card(sim, "RIT-HELP-01")
	assert_true(c != null and c.text.contains("RIT"), "대기 RIT가 있으면 묻는다")
	_answer(sim, c, "오답")
	assert_true(sim.command.safety.crews_with(SafetySystem.Role.RIT).is_empty(), "돕게 하면 RIT가 없어진다")
	assert_eq(sim.events.of_type("rit_misused").size(), 1, "위반 기록")
	# RIT가 없으면 묻지 않는다
	var sim2 := _sim(APT15)
	sim2.events.add(1, "hose_limit", {"crew": "진압1 1조", "crew_id": 0})
	sim2.cards.step(0.1, 1)
	assert_true(_card(sim2, "RIT-HELP-01") == null, "RIT 없으면 카드 없음")


func test_ppv_exhaust_card() -> void:
	var sim := _sim(APT3)
	# 1층 바깥 출입문에 송풍기
	var door: Opening = null
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.DOOR and o.room_b == Opening.OUTSIDE and o.level == 1:
			door = o
			break
	assert_true(door != null, "바깥 출입문")
	var c0 := sim.units.crews[0]
	sim.vent.order(c0.id, Vector3i(door.cells[0].x, door.cells[0].y, 1), sim.pathfinder, 0)
	sim.events.add(1, "ppv_no_exhaust", {"crew": "진압1 1조", "crew_id": c0.id})
	sim.cards.step(0.1, 1)
	var c := _card(sim, "PPV-EXHAUST-01")
	assert_true(c != null, "배기구 없으면 송풍기 카드")
	_answer(sim, c, "오답")
	assert_true(sim.vent.forced, "그대로 가동 → 연기는 안 빠지고 불만 커지는 상태")
	var sim2 := _sim(APT3)
	sim2.vent.order(c0.id, Vector3i(door.cells[0].x, door.cells[0].y, 1), sim2.pathfinder, 0)
	sim2.events.add(1, "ppv_no_exhaust", {"crew": "진압1 1조", "crew_id": c0.id})
	sim2.cards.step(0.1, 1)
	_answer(sim2, _card(sim2, "PPV-EXHAUST-01"), "최선")
	var w := sim2.vent.exhaust_window()
	assert_true(sim2.events.of_type("ppv_exhaust_order").size() + sim2.events.of_type("ppv_exhaust_none").size() == 1, "배기구 확보 지시 (창 %s)" % (w != null))
