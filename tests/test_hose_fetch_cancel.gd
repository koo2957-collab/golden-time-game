extends TestSuite
## 호스 꺼내기 취소 (2026-11-24): 펌프차 후면으로 호스를 꺼내러 가는 중이거나 꺼내는 중에 다른 지시를 받으면
## 그 호스는 거두고(차에 도로 넣은 것으로) 새 지시를 따른다. 전에는 수관을 지울 길이 없어 멈추면 1초마다 다시 펌프차로
## 끌려갔고, 꺼내는 동안은 속도 0으로 묶여 움직이지 않았다. 이미 깔기 시작한 호스는 그대로 끌고 간다.

const SCENARIO := "res://data/scenarios/dev_squad_house_fire.json"
## 현관 앞 바깥 칸
const OUTSIDE_DOOR := Vector3i(13, 22, 1)


## 진압 분대(조 0)에게 호스를 꺼내게 한다 → [sim, 조]
func _fetching() -> Array:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var crew := sim.units.get_crew(0)
	var pump := sim.water._nearest_pump(crew.leader.pos)
	assert_true(sim.water.lay_hose(crew.id, pump, sim.clock.tick), "호스 꺼내기 시작")
	return [sim, crew]


func _run_until_still(sim: SimWorld, crew: Crew, max_ticks := 3000) -> void:
	for i in max_ticks:
		sim.step_ticks(1)
		sim.cards.queue.clear()
		if i > 20 and not crew.leader.is_moving():
			break
	# 멈춘 뒤 다시 끌려가는지 보려고 3초 더
	sim.step_ticks(roundi(3.0 / SimClock.TICK_DT))


## 펌프차로 가는 중에 이동 지시 → 호스를 거두고 지시한 곳에 머문다
func test_move_while_going_to_truck() -> void:
	var s := _fetching()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var h := sim.water.hose_of_crew(crew.id)
	assert_true(h != null and h.to_outlet, "펌프차 후면으로 가는 중 (시작 자리가 차 뒤가 아니다)")
	sim.step_ticks(5)
	sim.issue(MoveCommand.new([crew.id] as Array[int], OUTSIDE_DOOR))
	_run_until_still(sim, crew)
	assert_true(sim.water.hose_of_crew(crew.id) == null, "꺼내러 가던 호스는 거뒀다")
	var d := crew.leader.pos.distance_to(Vector2(OUTSIDE_DOOR.x, OUTSIDE_DOOR.y) + Vector2(0.5, 0.5))
	assert_true(d <= 2.0, "지시한 곳에 머문다 (%.1f칸 떨어짐 — 펌프차로 끌려가지 않음)" % d)
	assert_eq(sim.events.of_type("hose_fetch_cancel").size(), 1, "호스 연장 취소 기록")


## 차 뒤에서 꺼내는 중(속도 0)에 이동 지시 → 바로 움직인다
func test_move_while_taking_out() -> void:
	var s := _fetching()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var h := sim.water.hose_of_crew(crew.id)
	for i in 3000:
		if h.fetch_until >= 0:
			break
		sim.step_ticks(1)
		sim.cards.queue.clear()
	assert_true(h.fetch_until >= 0, "차 뒤에서 꺼내는 중")
	var start := crew.leader.pos
	sim.issue(MoveCommand.new([crew.id] as Array[int], OUTSIDE_DOOR))
	sim.step_ticks(roundi(2.0 / SimClock.TICK_DT))
	assert_true(crew.leader.pos.distance_to(start) > 0.5, "꺼내던 자리에 묶이지 않고 움직인다")
	assert_true(sim.water.hose_of_crew(crew.id) == null, "호스는 거뒀다")
	for ff in crew.members():
		assert_eq(ff.speed_factor, 1.0, "대원 #%d 속도 원래대로" % ff.id)


## 꺼내러 가는 중에 층 검색 (호스가 필요 없는 임무) → 호스를 거둔다
func test_search_order_cancels_fetch() -> void:
	var s := _fetching()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	sim.step_ticks(5)
	sim.tactical.order("search_floor", crew.id, Vector3i(13, 17, 1), sim.clock.tick)
	assert_true(sim.water.hose_of_crew(crew.id) == null, "층 검색을 받으면 꺼내러 가던 호스를 거둔다")


## 꺼내러 가는 중에 진압 지시 (호스가 필요한 임무) → 꺼내던 호스를 그대로 쓴다
func test_attack_order_keeps_fetch() -> void:
	var s := _fetching()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var h := sim.water.hose_of_crew(crew.id)
	sim.step_ticks(5)
	sim.tactical.order("attack", crew.id, Vector3i(13, 17, 1), sim.clock.tick)
	assert_true(sim.water.hose_of_crew(crew.id) == h, "진압 지시는 꺼내던 호스를 그대로 쓴다")


## 이미 깔기 시작한 호스는 이동 지시를 받아도 거두지 않는다 (끌고 간다 — 놓고 가기는 다음 작업)
func test_laid_hose_not_cancelled() -> void:
	var s := _fetching()
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var h := fetch_hose(sim, crew.id, false)
	assert_true(h != null and not h.to_outlet and h.fetch_until < 0, "호스를 다 꺼냈다")
	sim.issue(MoveCommand.new([crew.id] as Array[int], OUTSIDE_DOOR))
	sim.step_ticks(10)
	assert_true(sim.water.hose_of_crew(crew.id) == h, "깔린 호스는 그대로")
	assert_eq(sim.events.of_type("hose_fetch_cancel").size(), 0, "취소 기록 없음")
