extends TestSuite
## 다른 분대 대원끼리 같은 칸에 서지 않는다 (2026-11-24 — 같은 칸에 선 두 분대 대원 중 한 사람이 다른 사람 그림에 가려 사라져 보였다).
## 이동 지시의 도착 칸(조장 자리)을 정할 때 다른 조가 멈춰 서 있는 칸은 비워 둔다. 비울 칸이 없으면(좁은 곳) 그래도 간다

const SCENARIO := "res://data/scenarios/dev_squad_house_fire.json"
const SPOT := Vector3i(13, 24, 1)


func _settle(sim: SimWorld, c: Crew) -> void:
	for i in 3000:
		sim.step_ticks(1)
		sim.cards.queue.clear()
		if i > 5 and not c.leader.is_moving():
			var still := true
			for ff in c.list:
				if ff.is_moving():
					still = false
			if still:
				return


func test_second_crew_avoids_occupied_cell() -> void:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var a := sim.units.get_crew(0)
	var b := sim.units.get_crew(1)
	sim.issue(MoveCommand.new([a.id] as Array[int], SPOT))
	_settle(sim, a)
	assert_eq(a.leader.cell3(), SPOT, "앞 분대 조장은 그 칸에")
	sim.issue(MoveCommand.new([b.id] as Array[int], SPOT))
	_settle(sim, b)
	var taken := {}
	for ff in a.list:
		taken[ff.cell3()] = true
	assert_true(not taken.has(b.leader.cell3()), "뒤 분대 조장은 앞 분대 대원이 선 칸을 비켜 선다 (%s)" % b.leader.cell3())
	assert_true(b.leader.cell3().distance_to(SPOT) <= 3.0, "그래도 지시한 곳 가까이 (%.1f칸)" % b.leader.cell3().distance_to(SPOT))


## 한 분대 안에서는 예전처럼 (자기 조원이 선 칸은 비우지 않는다)
func test_own_crew_not_blocked() -> void:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var a := sim.units.get_crew(0)
	sim.issue(MoveCommand.new([a.id] as Array[int], SPOT))
	_settle(sim, a)
	sim.issue(MoveCommand.new([a.id] as Array[int], SPOT))
	_settle(sim, a)
	assert_eq(a.leader.cell3(), SPOT, "같은 곳으로 다시 보내도 그 칸")
