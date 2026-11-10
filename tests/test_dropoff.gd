extends TestSuite
## 구조자 운반과 인계 (P10-2 ⓒ): 환자 집결지로 옮겨 인계 → 원래 임무 복귀, 집결지가 없으면 카드,
## 입구에 두면 연기·동선 방해, 처치 전 악화·관찰, START 분류 카드와 분류표 순서 자동 처치


func _sim() -> SimWorld:
	var sim := make_sim()
	open_all_doors(sim)
	sim.rescue.dropoff_enabled = true
	return sim


func _with_ems(sim: SimWorld) -> int:
	sim.units.add_squad({
		"id": "ems1", "name": "구급1", "type": "구급대",
		"vehicles": [{"type": "구급차", "spawn": [50, 36], "heading": [1, 0], "driver": {"name": "민서준", "rank": "소방교"}}],
		"crews": [{"spawn": [44, 26], "members": [
			{"name": "하은수", "rank": "소방장", "role": "구급대장"},
			{"name": "도윤아", "rank": "소방사", "role": "구급대원"}]}],
	})
	return sim.units.squads[-1].crews[0].id


## 바깥 6×6 안전구역 + 가운데 집결지
func _zones(sim: SimWorld) -> Vector2i:
	var b := sim.building
	var fp := b.footprint(1)
	for y in range(fp.end.y + 2, b.height - 6):
		for x in range(fp.position.x, b.width - 6):
			var r := Rect2i(x, y, 6, 6)
			if sim.zones.safe_reject_reason(r) == "":
				sim.zones.apply_safe(r, 0)
				sim.zones.apply_casualty(r.get_center(), 0)
				return r.get_center()
	return Vector2i(-1, -1)


## 현관 안쪽에 발견된 요구조자 하나와 그 옆 조 0
func _victim_by_door(sim: SimWorld) -> Victim:
	sim.rescue.add_victims([{"name": "환자", "age": 40, "level": 1, "cell": [13, 18]}], sim.rng)
	var v: Victim = sim.rescue.victims[-1]
	v.discovered = true
	var c := sim.units.get_crew(0)
	for i in c.members().size():
		c.members()[i].path.clear()
		c.members()[i].level = 1
		c.members()[i].pos = Vector2(13.5 + i, 17.5)
	return v


func _until(sim: SimWorld, cond: Callable, max_s: float) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return cond.call()


func _answer(sim: SimWorld, card_id: String, effect: String) -> bool:
	for c in sim.cards.queue:
		if c.id != card_id:
			continue
		for i in c.options.size():
			if str(c.options[i].effect) == effect:
				sim.issue(CommandOrder.make("card_answer", [], i, Vector3i.ZERO, {"uid": c.uid}))
				sim.step_ticks(1)
				return true
	return false


func test_carry_to_casualty_point_and_handover() -> void:
	var sim := _sim()
	var point := _zones(sim)
	assert_true(point.x >= 0, "집결지")
	var v := _victim_by_door(sim)
	sim.rescue.order_rescue(0, "victim", v.id, 0)
	assert_true(_until(sim, func() -> bool: return v.state == Victim.State.RESCUED, 240.0), "인계까지")
	assert_eq(v.dropoff, "환자 집결지", "집결지에 인계")
	assert_true(v.pos.distance_to(Vector2(point) + Vector2(0.5, 0.5)) <= 3.5, "집결지 자리 (%s)" % v.pos)
	assert_eq(sim.events.of_type("victim_handover").size(), 1, "인계 사건")
	assert_eq(sim.units.get_crew(0).leader.carry_factor, 1.0, "인계 뒤 맨몸")


func test_no_point_card_then_entrance() -> void:
	var sim := _sim()
	var v := _victim_by_door(sim)
	sim.rescue.order_rescue(0, "victim", v.id, sim.clock.tick)
	assert_true(_until(sim, func() -> bool: return not sim.events.of_type("rescue_no_point").is_empty(), 120.0), "집결지가 없으면 입구에서 묻는다")
	assert_true(_until(sim, func() -> bool: return sim.cards.queue.any(func(c: CardSystem.Card) -> bool: return c.id == "RESCUE-DROPOFF-01"), 5.0), "구조자 둘 곳 카드")
	assert_eq(v.carried_by, 0, "답을 기다리는 동안 업고 있다")
	assert_true(_answer(sim, "RESCUE-DROPOFF-01", "dropoff_entrance"), "입구에 두고 복귀 고름")
	assert_true(_until(sim, func() -> bool: return v.state == Victim.State.RESCUED, 10.0), "내려놓음")
	assert_eq([v.dropoff, v.left_at_entrance], ["입구", true], "입구에 둔 사람")
	var w: float = sim.pathfinder._grids[1].get_point_weight_scale(Vector2i(v.pos.floor()))
	assert_true(w > 1.0, "진입 동선 방해 (길찾기 비용 %.1f)" % w)
	var before := v.fed()
	# 현관 안쪽 방에 연기를 채운다 (문으로 새어 나온다)
	var hall := sim.fire.compartment_at(1, 13, 19)
	for i in 120:
		hall.soot = hall.volume * 0.02
		sim.step_ticks(10)

	assert_true(v.fed() > before, "입구에서 연기를 계속 마신다 (%.3f → %.3f)" % [before, v.fed()])
	var drop_rule: Array = Evaluator.evaluate(sim).rules.filter(func(r: Dictionary) -> bool: return r.id == "rescue.dropoff")
	assert_true(drop_rule.is_empty() or drop_rule[0].score == 0.0, "인계 장소 평가 0점")
	assert_true(sim.cards.log.any(func(l: Dictionary) -> bool: return l.id == "RESCUE-DROPOFF-01" and l.grade == "오답"), "카드 기록 오답 (감점)")


func test_wait_option_opens_zone_prompt() -> void:
	var sim := _sim()
	var v := _victim_by_door(sim)
	sim.rescue.order_rescue(0, "victim", v.id, 0)
	_until(sim, func() -> bool: return sim.cards.queue.any(func(c: CardSystem.Card) -> bool: return c.id == "RESCUE-DROPOFF-01"), 120.0)
	assert_true(_answer(sim, "RESCUE-DROPOFF-01", "dropoff_wait"), "집결지 지정 고름")
	assert_true(sim.rescue.zone_prompt, "화면이 구역 지정 모드를 연다")
	sim.step_ticks(50)
	assert_eq(v.carried_by, 0, "집결지가 생길 때까지 기다린다")
	_zones(sim)
	assert_true(_until(sim, func() -> bool: return v.state == Victim.State.RESCUED, 120.0), "집결지가 생기면 옮겨 인계")
	assert_eq(v.dropoff, "환자 집결지", "집결지")


func test_floor_search_resumes_after_handover() -> void:
	var sim := _sim()
	_zones(sim)
	sim.tactical.set_level("입문")
	var v := _victim_by_door(sim)
	v.discovered = false
	sim.tactical.order("search_floor", 0, Vector3i(13, 17, 1), 0)
	assert_true(_until(sim, func() -> bool: return v.dropoff != "", 400.0), "검색 중 발견 → 구조 → 인계 (%s)" % v.dropoff)
	assert_eq(v.dropoff, "환자 집결지", "집결지 인계")
	assert_true(_until(sim, func() -> bool: return sim.tactical.task_of_crew(0) != null, 30.0), "인계 뒤 원래 층 검색 임무로 복귀")


func test_start_card_and_tag_order() -> void:
	var sim := _sim()
	var ems := _with_ems(sim)
	var point := _zones(sim)
	# 실제 긴급(의식 없음)·응급(걷지 못함)·비응급(걸음) 세 사람을 집결지에
	var people: Array[Victim] = []
	for spec: Array in [[Victim.State.UNCONSCIOUS, 0.4, ""], [Victim.State.CONSCIOUS, 0.35, ""], [Victim.State.CONSCIOUS, 0.0, ""]]:
		sim.rescue.add_victims([{"name": "환자%d" % people.size(), "age": 40, "level": 1, "cell": [point.x, point.y]}], sim.rng)
		var v: Victim = sim.rescue.victims[-1]
		v.discovered = true
		v.fed_toxic = spec[1]
		v.state_at_rescue = spec[0]
		v.state = Victim.State.RESCUED
		v.rescued_tick = 0
		v.dropoff = "환자 집결지"
		people.append(v)
	sim.step_ticks(2)
	var urgent := sim.ems.patient_of(people[0].id)
	var emergent := sim.ems.patient_of(people[1].id)
	var minor := sim.ems.patient_of(people[2].id)
	assert_eq([urgent.triage, emergent.triage, minor.triage], [EmsSystem.Triage.URGENT, EmsSystem.Triage.EMERGENT, EmsSystem.Triage.MINOR], "실제 중증도 (START)")
	assert_eq(minor.tag, EmsSystem.Triage.MINOR, "걸을 수 있으면 자동 비응급")
	var cards := sim.cards.queue.filter(func(c: CardSystem.Card) -> bool: return c.id == "START-01")
	assert_eq(cards.size(), 2, "걷지 못하는 두 사람은 분류 카드")
	assert_true(cards[0].text.contains("호흡"), "단서: %s" % cards[0].text)
	assert_eq(cards[0].options.size(), 4, "긴급·응급·비응급·지연")
	# 긴급을 비응급으로 잘못, 응급은 맞게
	for c: CardSystem.Card in cards:
		var want := "tag_minor" if int(c.ctx.victim_id) == people[0].id else "tag_emergent"
		for i in c.options.size():
			if str(c.options[i].effect) == want:
				sim.issue(CommandOrder.make("card_answer", [], i, Vector3i.ZERO, {"uid": c.uid}))
	sim.step_ticks(2)
	assert_eq([urgent.tag, emergent.tag], [EmsSystem.Triage.MINOR, EmsSystem.Triage.EMERGENT], "고른 분류")
	# 구급대가 집결지 옆에서 쉬면 분류표 순서대로 — 잘못 분류한 긴급 환자는 뒤로 밀린다
	for ff in sim.units.get_crew(ems).members():
		ff.path.clear()
		ff.pos = Vector2(point) + Vector2(1.5, 0.5)
	sim.step_ticks(2)
	assert_eq(emergent.stage, EmsSystem.Stage.TREATING, "분류표 순서: 응급 먼저")
	assert_eq(urgent.stage, EmsSystem.Stage.WAITING, "긴급인데 비응급으로 분류 → 대기")
	var ev := Evaluator.new()
	ev.sim = sim
	var tri: Dictionary = ev._check_triage()
	assert_eq(tri.score, 0.5, "두 명 중 한 명 맞음")
	assert_true(str(tri.detail).contains("실제 긴급 · 분류 비응급 (틀림)"), "사람마다 실제·분류: %s" % tri.detail)


func test_deterioration_and_observer() -> void:
	var sim := _sim()
	var point := _zones(sim)
	var made: Array[Victim] = []
	for k in 2:
		sim.rescue.add_victims([{"name": "환자%d" % k, "age": 40, "level": 1, "cell": [point.x + k * 30, point.y]}], sim.rng)
		var v: Victim = sim.rescue.victims[-1]
		v.discovered = true
		v.fed_toxic = 0.35
		v.state_at_rescue = Victim.State.CONSCIOUS
		v.state = Victim.State.RESCUED
		v.rescued_tick = 0
		made.append(v)
	# 첫 사람 곁에 조 1이 서 있다 (구조자 관찰)
	var c := sim.units.get_crew(1)
	for ff in c.members():
		ff.path.clear()
		ff.level = 1
		ff.pos = made[0].pos + Vector2(1, 0)
	sim.step_ticks(roundi(100.0 / SimClock.TICK_DT))
	var watched := sim.ems.patient_of(made[0].id)
	var alone := sim.ems.patient_of(made[1].id)
	assert_true(sim.ems.observed(made[0]), "곁에 대원 = 관찰")
	assert_true(alone.untreated_s > 95.0 and watched.untreated_s < alone.untreated_s * 0.6,
		"관찰하면 악화가 느리다 (%.0f초 / %.0f초)" % [watched.untreated_s, alone.untreated_s])
