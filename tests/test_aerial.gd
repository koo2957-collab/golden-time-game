extends TestSuite
## P9: 굴절차 — 후착 도착, 전개, 바스켓 구조(닿는 높이·거리), 진입대가 있는 방 방수포 확인 카드, 추락 위험 카드 변형

const APT15 := "res://data/scenarios/sop213_3_15f_day_low.json"


## 굴절차가 도착할 때까지 돌린다 (후착 240초)
func _arrived() -> SimWorld:
	var sim := SimWorld.from_scenario(APT15)
	for i in 400:
		sim.step_ticks(10)
		if _aerial(sim) and not sim.command.resources.is_en_route(_aerial(sim).squad_id) and not _aerial(sim).is_moving():
			break
	return sim


func _aerial(sim: SimWorld) -> Vehicle:
	for v in sim.units.vehicles:
		if v.is_aerial():
			return v
	return null


## 그 층의 바깥 창 하나와 창 바로 안쪽 칸, 창 밖 3칸 땅
func _window(sim: SimWorld, lv: int) -> Dictionary:
	for o in sim.fire.openings:
		if o.kind != Opening.Kind.WINDOW or o.room_b != Opening.OUTSIDE or o.level != lv:
			continue
		var w: Vector2i = o.cells[0]
		for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var out := w + d * 4
			var inside := w - d
			if sim.building.in_bounds(out.x, out.y) and sim.building.cell(1, out.x, out.y) in BuildingData.OUTDOOR \
					and sim.fire.compartment_at(lv, inside.x, inside.y) != null:
				return {"opening": o, "inside": inside, "out": out}
	return {}


## 굴절차를 그 창 밖에 세운다 (테스트용으로 바로 옮김)
func _park(sim: SimWorld, v: Vehicle, out: Vector2i) -> void:
	v.pos = Vector2(out) + Vector2(0.5, 0.5)
	v.prev_pos = v.pos
	v.goal = v.pos
	v.moving = false


func _victim_at(sim: SimWorld, lv: int, cell: Vector2i) -> Victim:
	sim.rescue.add_victims([{"name": "주민", "age": 40, "level": lv, "cell": [cell.x, cell.y]}], sim.rng)
	var v: Victim = sim.rescue.victims[-1]
	v.discovered = true
	return v


func test_aerial_arrives_and_basket_rescue() -> void:
	var sim := _arrived()
	var av := _aerial(sim)
	assert_true(av != null, "후착 굴절차가 현장에 온다")
	assert_true(av.reach_m > 20.0 and av.deploy_s > 0.0, "제원: 작업 높이 %dm, 전개 %d초" % [roundi(av.reach_m), roundi(av.deploy_s)])
	var w := _window(sim, 4)
	assert_true(not w.is_empty(), "4층 바깥 창")
	_park(sim, av, w.out)
	var vic := _victim_at(sim, 4, w.inside)
	sim.issue(EquipmentCommand.make("basket", [], av.id, vic.id))
	sim.step_ticks(1)
	assert_eq(sim.events.of_type("aerial_rescue_start").size(), 1, "바스켓 구조 시작")
	assert_true(sim.falls.held.has(vic.id), "바스켓이 오는 동안 뛰어내리지 않고 기다림")
	assert_eq(sim.events.of_type("aerial_deploying").size(), 1, "첫 사용은 전개부터")
	# 전개 180 + (오르내리기 10.5m/0.6 × 2) + 태우기 30 ≈ 245초
	sim.step_ticks(roundi(200.0 / SimClock.TICK_DT))
	assert_true(vic.state != Victim.State.RESCUED, "아직 바스켓이 내려오는 중")
	sim.step_ticks(roundi(80.0 / SimClock.TICK_DT))
	assert_eq(vic.state, Victim.State.RESCUED, "바스켓으로 구조")
	assert_eq(vic.level, 1, "땅으로 내려옴")
	assert_eq(vic.dropoff, "굴절차", "구조 방법 기록")


func test_basket_out_of_reach() -> void:
	var sim := _arrived()
	var av := _aerial(sim)
	var w := _window(sim, 13)
	_park(sim, av, w.out)
	var vic := _victim_at(sim, 13, w.inside)
	assert_true(not sim.aerial.order_rescue(av.id, vic.id, sim.clock.tick), "13층(37.5m)은 27m급 굴절차가 닿지 않음")
	var e := sim.events.of_type("aerial_out_of_reach")
	assert_true(not e.is_empty() and str(e[-1].reason).contains("높이"), "이유: 높이")
	# 낮은 층이라도 차가 멀면 닿지 않는다
	var w4 := _window(sim, 4)
	var dir: Vector2i = (w4.out - w4.inside) / maxi(1, (w4.out - w4.inside).length())
	var far := ceili((av.outreach_m + 5.0) / sim.building.cell_size_m + av.length_cells)
	_park(sim, av, w4.out + dir * far)
	var vic4 := _victim_at(sim, 4, w4.inside)
	assert_true(not sim.aerial.order_rescue(av.id, vic4.id, sim.clock.tick), "수평 거리 초과")


func test_monitor_crew_check_card() -> void:
	var sim := _arrived()
	var av := _aerial(sim)
	var w := _window(sim, 3)
	_park(sim, av, w.out)
	# 그 창이 있는 방 안에 진입대
	var c0 := sim.units.crews[0]
	for ff in c0.members():
		ff.level = 3
		ff.pos = Vector2(w.inside) + Vector2(0.5, 0.5)
		ff.path.clear()
	var o: Opening = w.opening
	var target := Vector3i(o.cells[0].x, o.cells[0].y, o.level)
	sim.issue(EquipmentCommand.make("monitor", [], av.id, -1, target))
	sim.step_ticks(2)
	assert_true(sim.monitors.stream_of(av.id) == null, "진입대가 있으면 바로 쏘지 않는다")
	var card: CardSystem.Card = null
	for c in sim.cards.queue:
		if c.id == "MONITOR-CREW-01":
			card = c
	assert_true(card != null, "방수포 확인 카드 (SOP 207-1.1)")
	for i in card.options.size():
		if card.options[i].grade == "오답":
			sim.cards.answer(card.uid, i, sim.clock.tick)
	assert_true(sim.monitors.stream_of(av.id) != null, "즉시 방수를 고르면 쏜다 (전개 뒤 물)")
	var before := c0.leader.heat_stress
	sim.step_ticks(roundi((av.deploy_s + 5.0) / SimClock.TICK_DT))
	assert_true(sim.monitors.violations >= 1, "위반 기록")
	assert_true(c0.leader.heat_stress > before or c0.leader.incapacitated, "열기가 진입대 쪽으로 (열 스트레스 %.2f → %.2f)" % [before, c0.leader.heat_stress])


func test_jump_card_offers_basket_when_aerial_on_scene() -> void:
	var sim := _arrived()
	var w := _window(sim, 4)
	_park(sim, _aerial(sim), w.out)
	var vic := _victim_at(sim, 4, w.inside)
	sim.events.add(sim.clock.tick, "jump_risk", {"who": vic.label(), "room": "", "crew": "현장 대원"})
	sim.cards.step(0.1, sim.clock.tick)
	var card: CardSystem.Card = null
	for c in sim.cards.queue:
		if c.id == "JUMP-01":
			card = c
	assert_true(card != null and card.text.contains("굴절차"), "굴절차가 있으면 바스켓 선택지가 있는 변형")
	for i in card.options.size():
		if card.options[i].grade == "최선":
			assert_eq(str(card.options[i].effect), "aerial_rescue", "최선 = 바스켓 + 확성기")
			sim.cards.answer(card.uid, i, sim.clock.tick)
	assert_true(sim.falls.held.has(vic.id), "바스켓 구조 시작")
