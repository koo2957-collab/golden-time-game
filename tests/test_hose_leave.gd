extends TestSuite
## 깔린 호스 다루기 (2026-11-24 사용자 결정):
##   보통 철수 = 관창을 그 자리에 놓고 호스를 거두며 펌프차로 돌아온다 (시간이 걸린다)
##   공기호흡기 교체 = 관창을 놓고 호스를 따라 나와 교체 → "교체 완료, 재진입" → 호스를 따라 들어가 관창을 잡고 하던 진압을 잇는다
##   긴급 철수 = 호스를 거두지 않고 놓아 둔 채 호스를 따라 바로 밖으로
##   교대조 인수 = 다른 조가 진압 지시를 받으면 새 호스를 꺼내지 않고 놓인 관창으로 가서 이어받는다

const SCENARIO := "res://data/scenarios/dev_squad_house_fire.json"


func _indoor(sim: SimWorld, c: Crew) -> bool:
	return not sim.building.cell(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y)) in BuildingData.OUTDOOR


## 떠 있는 질문 카드에 답한다 (진입 허가·문 개방은 진행, 아니면 최선)
func _answer(sim: SimWorld) -> void:
	for card in sim.cards.queue.duplicate():
		var pick := -1
		for i in card.options.size():
			if str(card.options[i].get("effect", "")) in ["entry_grant", "force_door", "open_door", "vent_then_open"]:
				pick = i
				break
		for i in card.options.size():
			if pick < 0 and str(card.options[i].get("grade", "")) == "최선":
				pick = i
		sim.cards.answer(card.uid, maxi(pick, 0), sim.clock.tick)


## 진압 분대(조 0)가 불난 방에 진압 지시를 받고 건물 안에서 방수할 때까지 → [sim, 조, 목표]
func _spraying() -> Array:
	var sim := SimWorld.from_scenario(SCENARIO, false)
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
		sim.cards.queue.clear()
	assert_true(target.x >= 0, "타는 칸이 있다")
	# 현관문을 미리 열어 둔다 (잠긴 문을 부수는 60초 동안 연습용 작은 불이 저절로 꺼져 진압 임무가 끝나 버린다)
	var door := sim.fire.opening_at(Vector3i(13, 20, 1))
	if door != null:
		door.locked = false
		door.is_open = true
		sim.doors.sync_blocking()
	sim.tactical.order("attack", crew.id, target, sim.clock.tick)
	for i in 12000:
		sim.step_ticks(1)
		_answer(sim)
		var h := sim.water.hose_of_crew(crew.id)
		if h != null and h.spraying and _indoor(sim, crew):
			break
	var h := sim.water.hose_of_crew(crew.id)
	assert_true(h != null and h.spraying and _indoor(sim, crew), "건물 안에서 방수 중")
	return [sim, crew, target]


func _run(sim: SimWorld, ticks: int, until: Callable) -> bool:
	for i in ticks:
		sim.step_ticks(1)
		_answer(sim)
		if until.call():
			return true
	return false


## 보통 철수: 관창을 놓은 자리부터 호스를 거두며 펌프차로 돌아오고, 다 거두면 수관이 없어진다
func test_withdraw_recovers_hose() -> void:
	var s := _spraying()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var h := sim.water.hose_of_crew(crew.id)
	if h == null:
		return
	var start := h.points[0]
	var len0 := h.points.size()
	sim.tactical.order("withdraw", crew.id, Vector3i.ZERO, sim.clock.tick)
	assert_true(h.recovering, "호스를 거두는 중")
	assert_true(not h.flowing, "관창을 잠갔다")
	for ff in crew.members():
		assert_true(ff.speed_factor < 0.8, "거두는 동안은 느리다 (%.2f)" % ff.speed_factor)
	sim.step_ticks(50)
	assert_true(h.points.size() < len0, "지나온 만큼 호스가 걷힌다 (%d → %d)" % [len0, h.points.size()])
	var done := _run(sim, 8000, func() -> bool: return sim.water.hose_of_crew(crew.id) == null)
	assert_true(done, "다 거두면 수관이 없어진다")
	assert_eq(sim.events.of_type("hose_recovered").size(), 1, "호스 회수 완료 기록")
	assert_true(not _indoor(sim, crew), "밖으로 나왔다")
	assert_true(crew.leader.cell3().distance_to(start) <= 3.0, "펌프차 후면 가까이 (%.1f칸)" % crew.leader.cell3().distance_to(start))


## 공기호흡기 교체: 관창을 놓고 나와 교체 → 호스를 따라 들어가 관창을 잡고 진압을 잇는다
func test_air_swap_and_return() -> void:
	var s := _spraying()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var h := sim.water.hose_of_crew(crew.id)
	if h == null:
		return
	for ff in crew.members():
		ff.air_l = ff.air_capacity * 0.3
	var nozzle := h.points[-1]
	var len0 := h.points.size()
	sim.tactical.order("withdraw", crew.id, Vector3i.ZERO, sim.clock.tick)
	assert_true(h.dropped, "관창을 놓았다")
	assert_true(sim.command.safety.air_swaps.has(crew.id), "교체 철수로 기록")
	assert_eq(h.points.size(), len0, "호스는 깔린 그대로")
	var out := _run(sim, 6000, func() -> bool: return not _indoor(sim, crew) and not crew.leader.is_moving())
	assert_true(out, "밖으로 나와 멈췄다")
	assert_eq(h.points[-1], nozzle, "관창은 놓은 자리에")
	var back := _run(sim, 12000, func() -> bool: return h.held() and not sim.command.safety.air_swaps.has(crew.id))
	assert_true(back, "교체 뒤 호스를 따라 들어가 관창을 다시 잡았다")
	var said := sim.events.of_type("air_swap_done")
	assert_true(not said.is_empty() and str(said[0].text).contains("재진입"), "교체 완료, 재진입 보고")
	for ff in crew.members():
		assert_true(ff.air_ratio() > 0.8, "공기를 채웠다 (%.2f)" % ff.air_ratio())
	var t := sim.tactical.task_of_crew(crew.id)
	assert_true(t != null and t.action == "attack", "하던 진압을 잇는다")


## 긴급 철수: 호스를 거두지 않고 놓아 둔 채 호스를 따라 바로 밖으로
func test_emergency_leaves_hose() -> void:
	var s := _spraying()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var h := sim.water.hose_of_crew(crew.id)
	if h == null:
		return
	var len0 := h.points.size()
	sim.command.safety.withdraw_crew(crew, sim.clock.tick, "evacuate")
	assert_true(h.dropped and not h.recovering, "호스를 놓고 거두지 않는다")
	for ff in crew.members():
		assert_eq(ff.speed_factor, 1.0, "호스에 묶이지 않고 제 빠르기로")
	var out := _run(sim, 6000, func() -> bool: return not _indoor(sim, crew) and not crew.leader.is_moving())
	assert_true(out, "밖으로 나왔다")
	assert_eq(h.points.size(), len0, "호스는 깔린 그대로 남는다")


## 긴급 탈출 뒤 외부 방수(경계 관창) 지시: 건물 안의 놓인 관창을 쓰러 들어가지 않는다 (2026-11-24 검사 A·B)
func test_exterior_does_not_reenter() -> void:
	var s := _spraying()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var target: Vector3i = s[2]
	var h := sim.water.hose_of_crew(crew.id)
	if h == null:
		return
	sim.command.safety.withdraw_crew(crew, sim.clock.tick, "evacuate")
	_run(sim, 6000, func() -> bool: return not _indoor(sim, crew) and not crew.leader.is_moving())
	sim.tactical.order("exterior", crew.id, target, sim.clock.tick)
	var other := sim.units.get_crew(1)
	sim.tactical.order("exterior", other.id, target, sim.clock.tick)
	var grabbed := false
	for i in 1500:
		sim.step_ticks(1)
		_answer(sim)
		if h.to_nozzle or h.held():
			grabbed = true
			break
	assert_true(not grabbed, "외부 방수 지시로 놓인 관창을 다시 잡으러(이어받으러) 가지 않는다")
	assert_true(sim.water.hose_of_crew(other.id) != h, "다른 조도 놓인 관창을 이어받지 않는다")
	assert_true(sim.water.hose_of_crew(crew.id) != h, "자기 조는 놓인 관창 대신 새 호스")
	assert_eq(sim.events.of_type("hose_takeover").size(), 0, "인수 기록 없음")


## 방어 전략이면 밖의 조는 놓인 관창을 이어받으러 들어가지 않는다 (진입 금지 요소 — 2026-11-24 검사 F)
func test_defensive_blocks_takeover() -> void:
	var s := _spraying()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var target: Vector3i = s[2]
	var h := sim.water.hose_of_crew(crew.id)
	if h == null:
		return
	sim.command.safety.withdraw_crew(crew, sim.clock.tick, "evacuate")
	_run(sim, 6000, func() -> bool: return not _indoor(sim, crew) and not crew.leader.is_moving())
	sim.command.strategy = CommandSystem.Strategy.DEFENSIVE
	var relief := sim.units.get_crew(1)
	sim.tactical.order("attack", relief.id, target, sim.clock.tick)
	sim.step_ticks(3)
	assert_true(sim.water.hose_of_crew(relief.id) != h, "방어 전략: 놓인 관창을 이어받지 않는다")
	assert_eq(sim.events.of_type("hose_takeover").size(), 0, "인수 기록 없음")


## 교체 철수 뒤 밖에서 다른 지시(대기)를 받으면 교체가 끝나도 스스로 다시 들어가지 않는다 (2026-11-24 검사 G)
func test_hold_after_swap_forgets_return() -> void:
	var s := _spraying()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var h := sim.water.hose_of_crew(crew.id)
	if h == null:
		return
	for ff in crew.members():
		ff.air_l = ff.air_capacity * 0.3
	sim.tactical.order("withdraw", crew.id, Vector3i.ZERO, sim.clock.tick)
	_run(sim, 6000, func() -> bool: return not _indoor(sim, crew) and not crew.leader.is_moving())
	sim.tactical.order("hold", crew.id, Vector3i.ZERO, sim.clock.tick)
	assert_true(not sim.command.safety.air_swaps.has(crew.id), "대기 지시로 '교체 뒤 돌아가기'를 잊었다")
	var went_in := _run(sim, 4000, func() -> bool: return _indoor(sim, crew))
	assert_true(not went_in, "교체가 끝나도 다시 들어가지 않는다")
	assert_true(sim.water.hose_of_crew(crew.id) == null, "놓고 간 관창의 주인이 풀렸다")


## 관창을 놓은 조가 다른(호스가 필요 없는) 임무를 받으면 '수관을 든 조'가 아니다 — 구조 등을 받을 수 있다 (2026-11-24 검사 C)
func test_dropped_crew_is_free() -> void:
	var s := _spraying()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var h := sim.water.hose_of_crew(crew.id)
	if h == null:
		return
	sim.command.safety.withdraw_crew(crew, sim.clock.tick, "evacuate")
	assert_true(sim.water.held_hose(crew.id) == null, "관창을 놓은 조는 수관을 들고 있지 않다")
	sim.issue(MoveCommand.new([crew.id] as Array[int], Vector3i(13, 24, 1)))
	sim.step_ticks(2)
	assert_true(sim.water.hose_of_crew(crew.id) == null, "이동 지시로 놓인 관창의 주인이 풀렸다")
	assert_true(h.dropped and h.crew_id == -1, "수관은 놓인 채 남는다 (다른 조가 이어받을 수 있게)")


## 이어받으러 가던 조장이 쓰러지면 수관은 놓인 상태로 돌아가 다른 조가 이어받을 수 있다 (2026-11-24 검사 E)
func test_abandon_when_leader_down() -> void:
	var s := _spraying()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var target: Vector3i = s[2]
	var h := sim.water.hose_of_crew(crew.id)
	if h == null:
		return
	sim.command.safety.withdraw_crew(crew, sim.clock.tick, "evacuate")
	_run(sim, 6000, func() -> bool: return not _indoor(sim, crew) and not crew.leader.is_moving())
	var relief := sim.units.get_crew(1)
	sim.tactical.order("attack", relief.id, target, sim.clock.tick)
	sim.step_ticks(3)
	assert_true(h.to_nozzle and h.crew_id == relief.id, "교대조가 관창으로 가는 중")
	relief.leader.incapacitated = true
	sim.step_ticks(3)
	assert_true(h.dropped and not h.to_nozzle and h.crew_id == -1, "조장이 쓰러지면 놓인 수관으로 돌아간다")
	assert_eq(sim.events.of_type("hose_abandoned").size(), 1, "그만둔 기록")


## 교대조 인수: 놓인 관창이 있으면 다른 조가 진압 지시를 받았을 때 그 호스를 따라가 이어받는다
func test_relief_takes_over() -> void:
	var s := _spraying()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var target: Vector3i = s[2]
	var h := sim.water.hose_of_crew(crew.id)
	if h == null:
		return
	sim.command.safety.withdraw_crew(crew, sim.clock.tick, "evacuate")
	_run(sim, 6000, func() -> bool: return not _indoor(sim, crew) and not crew.leader.is_moving())
	var relief := sim.units.get_crew(1)
	var hoses0 := sim.water.hoses.size()
	sim.tactical.order("attack", relief.id, target, sim.clock.tick)
	# 수관은 임무를 받은 다음 틱에 챙긴다 (TacticalSystem.step — 화재진압은 호스부터)
	sim.step_ticks(3)
	assert_true(sim.water.hose_of_crew(relief.id) == h, "새 호스가 아니라 놓인 호스를 이어받는다")
	assert_eq(sim.water.hoses.size(), hoses0, "호스 수가 늘지 않는다")
	assert_eq(sim.events.of_type("hose_takeover").size(), 1, "관창 인수 기록")
	var got := _run(sim, 12000, func() -> bool: return h.held())
	assert_true(got, "교대조가 관창을 잡았다")
	assert_true(sim.water.hose_of_crew(crew.id) == null, "처음 조는 이제 호스가 없다")
