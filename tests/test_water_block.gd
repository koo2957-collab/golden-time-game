extends TestSuite
## 물줄기는 벽·닫힌 문·안 깨진 창을 넘지 않는다 — 퍼지는 물까지 (2026-11-24 사용자: "물줄기는 벽을 통과하지 못해야 하는데
## 물리적으로 잘 맞는지 의문"). 직사의 줄기는 전에도 벽 앞에서 멈췄지만, 맞은 곳 둘레로 퍼지는 물은 가림 없이 나눠져
## 분무·엄호 주수가 벽 뒤를 적셨고, 벽·문·창 칸을 직접 겨누면 그 뒤의 불에 물이 닿았다.
## 그리고 관창에서 실제로 물이 나간 틱만 표시한다 (HoseLine.spraying) — 다른 지시를 받으면 관창을 잠근다.

const ROOM1_BED := Vector3i(27, 17, 1)


## 방1 침대에 불을 붙이고 2분 뒤, 진압1 1조를 복도(방1과 벽으로 막힌 곳)에 세워 호스를 쥐여 준다
func _corridor_crew() -> Array:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	# 옆문은 열고 (호스가 복도까지 들어올 길), 방1 문(24, 14 — 조장 바로 남쪽)은 닫는다
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.fire.opening_at(Vector3i(24, 14, 1)).is_open = false
	sim.doors.sync_blocking()
	sim.fire.ignite(ROOM1_BED)
	sim.step_ticks(1200)
	var crew := sim.units.get_crew(0)
	for k in crew.members().size():
		var ff: Firefighter = crew.members()[k]
		ff.pos = Vector2(24.5 + k, 12.5)
		ff.prev_pos = ff.pos
		ff.level = 1
		ff.prev_level = 1
		ff.path.clear()
	sim.water.ensure_hose(0, 1, sim.clock.tick)
	var h := fetch_hose(sim, 0)
	h.charged = true
	h.ready_tick = sim.clock.tick
	h.next_advance_tick = 1 << 30  # 이 테스트에서는 '진압하며 전진'을 끈다
	return [sim, h]


func _aim(h: HoseLine, at: Vector2, pattern: HoseLine.Pattern) -> void:
	h.target = Vector3i(floori(at.x), floori(at.y), 1)
	h.aim = at
	h.pattern = pattern
	h.flowing = true
	h.approaching = false


## 방1(벽 뒤)의 연료 칸에 닿은 물 (L)
func _wet_in_room1(sim: SimWorld) -> float:
	var room := sim.fire.compartment_at(1, 25, 17)
	var total := 0.0
	for i in sim.fire.grid.room_cells[room.index]:
		total += sim.fire.grid.wet[i]
	return total


## 벽 뒤 방 안을 겨눈 분무·엄호 주수: 물은 벽 앞에 떨어지고 벽 뒤 칸은 젖지 않는다
func test_fog_and_cover_do_not_wet_behind_wall() -> void:
	for pattern: HoseLine.Pattern in [HoseLine.Pattern.FOG, HoseLine.Pattern.COVER, HoseLine.Pattern.STRAIGHT]:
		var made := _corridor_crew()
		var sim: SimWorld = made[0]
		var h: HoseLine = made[1]
		var before := _wet_in_room1(sim)
		_aim(h, Vector2(25.5, 15.5), pattern)
		sim.step_ticks(100)
		assert_true(h.spraying, "%s: 물이 나가고 있다" % h.pattern_name())
		assert_true(h.blocked and h.impact.y < 14.0, "%s: 벽 앞(복도)에서 막힌다 (%s)" % [h.pattern_name(), h.impact])
		assert_true(_wet_in_room1(sim) - before < 0.01, "%s: 벽 뒤 방은 젖지 않는다 (%.2fL)" % [h.pattern_name(), _wet_in_room1(sim) - before])


## 벽 칸을 직접 겨눠도 물은 벽 겉에만 닿는다 (전에는 벽 속까지 들어가 그 뒤 불에 물이 닿았다)
func test_aiming_at_wall_cell_does_not_reach_behind() -> void:
	var made := _corridor_crew()
	var sim: SimWorld = made[0]
	var h: HoseLine = made[1]
	# 복도와 방1 사이의 벽 칸 (방1 문 옆)
	var wall := Vector2i(26, 14)
	assert_true(sim.building.cell(1, wall.x, wall.y) == BuildingData.Cell.WALL, "복도 남쪽 벽")
	var before := _wet_in_room1(sim)
	_aim(h, Vector2(wall) + Vector2(0.5, 0.5), HoseLine.Pattern.STRAIGHT)
	sim.step_ticks(100)
	assert_true(_wet_in_room1(sim) - before < 0.01, "벽 뒤 방은 젖지 않는다 (%.2fL)" % (_wet_in_room1(sim) - before))


## 열린 문으로는 물이 들어간다 (막는 것만 막는다)
func test_water_passes_open_door() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	open_all_doors(sim)
	sim.fire.ignite(ROOM1_BED)
	sim.step_ticks(1200)
	var before := _wet_in_room1(sim)
	sim.issue(TacticalCommand.make("attack", [0] as Array[int], ROOM1_BED))
	sim.step_ticks(1)
	fetch_hose(sim, 0, false)
	var wet := false
	for i in 3000:
		sim.step_ticks(1)
		if _wet_in_room1(sim) - before > 5.0:
			wet = true
			break
	assert_true(wet, "문으로 들어가 방 안에 물이 닿는다")


## 관창에서 실제로 물이 나간 틱만 spraying — 다른 층을 겨누면 물도 나가지 않고 탱크도 줄지 않는다
func test_spraying_only_when_water_leaves_nozzle() -> void:
	var made := _corridor_crew()
	var sim: SimWorld = made[0]
	var h: HoseLine = made[1]
	assert_true(not h.spraying, "방수 지시 전")
	_aim(h, Vector2(25.5, 15.5), HoseLine.Pattern.STRAIGHT)
	sim.step_ticks(20)
	assert_true(h.spraying, "방수 중")
	# 다른 층을 겨눈다: 닿지 않는다 — 물이 나간 것으로 치지 않고 탱크도 그대로
	h.target = Vector3i(25, 15, 2)
	sim.step_ticks(5)
	var v := sim.units.get_vehicle(h.vehicle_id)
	var tank := v.tank_l
	sim.step_ticks(100)
	assert_true(not h.spraying and h.blocked, "다른 층: 물이 나가지 않는다")
	assert_true(absf(v.tank_l - tank) < 0.01, "닿지 않는 방수에 탱크 물이 줄지 않는다 (%.1f → %.1fL)" % [tank, v.tank_l])
	# 방수 위치로 가는 중에도 아니다
	h.target = Vector3i(25, 15, 1)
	h.approaching = true
	sim.units.order_move([0] as Array[int], Vector3i(28, 12, 1), sim.pathfinder)
	sim.step_ticks(3)
	assert_true(not h.spraying, "걸어가는 중에는 물이 나가지 않는다")


## 방수하던 조에게 이동·다른 임무를 시키면 관창을 잠근다 (전에는 예전 목표로 계속 방수했다)
func test_new_order_closes_nozzle() -> void:
	var made := _corridor_crew()
	var sim: SimWorld = made[0]
	var h: HoseLine = made[1]
	_aim(h, Vector2(25.5, 15.5), HoseLine.Pattern.STRAIGHT)
	sim.step_ticks(20)
	assert_true(h.flowing and h.spraying, "방수 중")
	sim.issue(MoveCommand.new([0] as Array[int], Vector3i(28, 12, 1)))
	sim.step_ticks(2)
	assert_true(not h.flowing and not h.spraying, "이동 명령: 관창을 잠근다")
	assert_true(not sim.events.of_type("spray_stop").is_empty(), "방수 중지 보고")
	_aim(h, Vector2(25.5, 15.5), HoseLine.Pattern.STRAIGHT)
	sim.step_ticks(20)
	assert_true(h.spraying, "다시 방수")
	sim.issue(TacticalCommand.make("search", [0] as Array[int], Vector3i(12, 16, 1)))
	sim.step_ticks(2)
	assert_true(not h.flowing and not h.spraying, "다른 임무(검색): 관창을 잠근다")


## 닫힌 문 칸을 겨누면 문 겉에는 물이 닿지만 (타는 문은 끌 수 있어야 한다 — 2026-11-13) 문 뒤 방은 젖지 않는다
func test_aiming_at_closed_door_wets_door_only() -> void:
	var made := _corridor_crew()
	var sim: SimWorld = made[0]
	var h: HoseLine = made[1]
	var door := sim.fire.opening_at(Vector3i(24, 14, 1))
	assert_true(door != null and not door.is_open, "방1 문은 닫혀 있다")
	var before := _wet_in_room1(sim)
	var door_i := sim.fire.grid.index(1, 24, 14)
	var door_before: float = sim.fire.grid.wet[door_i]
	_aim(h, Vector2(24.5, 14.5), HoseLine.Pattern.FOG)
	sim.step_ticks(100)
	assert_true(not h.blocked, "문 겉에는 닿는다")
	assert_true(sim.fire.grid.wet[door_i] > door_before, "문 칸은 젖는다")
	assert_true(_wet_in_room1(sim) - before < 0.01, "문 뒤 방은 젖지 않는다 (%.2fL)" % (_wet_in_room1(sim) - before))
