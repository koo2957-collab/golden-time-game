extends TestSuite
## 한 문에 두 분대 (2026-11-24 사용자 결정): 먼저 요청한 분대가 문을 열고, 나중 분대는 문 옆 떨어진 자리에서 기다린다.
## 사용자 보고: "구조대와 진압대가 한 문 앞에서 만나 문을 개방할 때 대원들이 사라진다" — 두 분대가 한 문 작업에 함께 붙어
## 문틈 옆 두 자리(force_a·force_b)에 네 명이 겹쳐 그려졌다.

const SCENARIO := "res://data/scenarios/dev_squad_house_fire.json"
const FRONT_DOOR := Vector3i(13, 20, 1)


## 진압 분대(조 0, 호스 꺼냄)와 구조 분대(조 1)를 잠긴 현관문으로 차례로 보내고 문 작업이 시작될 때까지 돌린다 → [sim, 진압, 구조, 문]
func _two_at_door(locked := true, rescue_first := false) -> Array:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var attack := sim.units.get_crew(0)
	var rescue := sim.units.get_crew(1)
	var door := sim.fire.opening_at(FRONT_DOOR)
	door.locked = locked
	door.is_open = false
	sim.doors.sync_blocking()
	sim.water.lay_hose(attack.id, sim.water._nearest_pump(attack.leader.pos), sim.clock.tick)
	var h := fetch_hose(sim, attack.id, false)
	if h != null:
		h.ready_tick = 1 << 30
	var order: Array[Crew] = [attack, rescue]
	if rescue_first:
		order.reverse()
	for c in order:
		sim.doors.request(c.id, FRONT_DOOR, true, sim.clock.tick)
	for i in 4000:
		var t := sim.doors.task_of_crew(order[0].id)
		if t != null and t.progress > 0.5 and not attack.leader.is_moving() and not rescue.leader.is_moving():
			break
		sim.step_ticks(1)
		sim.cards.queue.clear()
	return [sim, attack, rescue, door]


## 문을 여는 분대는 하나, 나중 분대는 문에서 door_stack_m 쯤 떨어져 기다리고 무전으로 알린다
func test_second_squad_waits_beside_door() -> void:
	var s := _two_at_door()
	var sim: SimWorld = s[0]
	var attack: Crew = s[1]
	var rescue: Crew = s[2]
	var door: Opening = s[3]
	var t := sim.doors.task_of(door)
	assert_true(t != null, "문 작업이 있다")
	if t == null:
		return
	assert_eq(t.worker(), attack.id, "먼저 요청한 진압 분대가 연다")
	assert_true(t.stacked(rescue.id), "구조 분대는 기다린다")
	assert_true(t.progress > 0.5, "문 작업이 진행된다")
	var center := FloorLayer.door_center(door)
	var stack_cells := 2.0 / sim.units.cell_size_m
	assert_true(rescue.leader.pos.distance_to(center) >= stack_cells * 0.8,
		"구조 분대 조장은 문에서 떨어져 선다 (%.1f칸)" % rescue.leader.pos.distance_to(center))
	assert_true(rescue.leader.pos.distance_to(attack.leader.pos) >= 1.5, "두 조장이 겹치지 않는다")
	var said := sim.events.of_type("door_stack")
	assert_eq(said.size(), 1, "문 옆 대기 보고 한 번")
	if not said.is_empty():
		assert_true(SimEventLog.describe_text(said[0]).contains("문 옆 대기"), "보고 문장: %s" % SimEventLog.describe_text(said[0]))


## 그림: 문을 부수는 자세는 여는 분대 두 사람만, 일곱 명 모두 서로 다른 자리에 그린다
func test_all_members_drawn_apart() -> void:
	var s := _two_at_door()
	var sim: SimWorld = s[0]
	var attack: Crew = s[1]
	var rescue: Crew = s[2]
	var sel := SelectionController.new()
	var layer := FloorLayer.new()
	layer.setup(sim, sel, IsoProjection.new())
	layer.level = FRONT_DOOR.z
	var spots: Array = []
	var forcers := {}
	for c: Crew in [attack, rescue]:
		var art := SpriteArt.crew_set(sim.units.squads[c.squad_id].type)
		for ff in c.members():
			var pose := str(layer._unit_pose(ff, c, art)[0])
			if pose in ["force_a", "force_b"]:
				forcers[ff.id] = c.id
			spots.append([ff.id, c.id, layer._shown_pos(ff, 0.0)])
	assert_eq(forcers.size(), 2, "문을 부수는 사람은 둘")
	for id in forcers:
		assert_eq(int(forcers[id]), attack.id, "문을 부수는 사람은 진압 분대")
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			var d: float = (spots[i][2] as Vector2).distance_to(spots[j][2])
			assert_true(d > 0.3, "대원 #%d(조 %d)와 #%d(조 %d)가 같은 자리에 그려진다 (%.2f칸)" % [spots[i][0], spots[i][1], spots[j][0], spots[j][1], d])
	sel.free()
	layer.free()


## 구조 분대(호스 없음)가 먼저 와서 문을 부술 때: 선두는 문틈 옆 두 조원 사이가 아니라 물러난 자리에 그린다.
## 전에는 선두가 문 앞 작업 칸(실제 자리)에 그대로 그려져 문을 부수는 조원과 겹쳤다
func test_rescue_opens_leader_steps_back() -> void:
	var s := _two_at_door(true, true)
	var sim: SimWorld = s[0]
	var attack: Crew = s[1]
	var rescue: Crew = s[2]
	var door: Opening = s[3]
	var t := sim.doors.task_of(door)
	assert_true(t != null and t.worker() == rescue.id and t.stacked(attack.id), "구조 분대가 열고 진압 분대는 기다린다")
	var sel := SelectionController.new()
	var layer := FloorLayer.new()
	layer.setup(sim, sel, IsoProjection.new())
	layer.level = FRONT_DOOR.z
	var art := SpriteArt.crew_set(sim.units.squads[rescue.squad_id].type)
	var lead_at := layer._shown_pos(rescue.leader, 0.0)
	var forcers := 0
	for ff in rescue.members():
		if ff != rescue.leader and str(layer._unit_pose(ff, rescue, art)[0]) in ["force_a", "force_b"]:
			forcers += 1
			var d := lead_at.distance_to(layer._shown_pos(ff, 0.0))
			assert_true(d > 0.9, "선두와 문을 부수는 #%d 가 겹치지 않는다 (%.2f칸)" % [ff.id, d])
	assert_eq(forcers, 2, "구조 분대 두 사람이 문을 부순다")
	assert_true(lead_at.distance_to(FloorLayer.door_center(door)) < 3.5, "선두는 문 가까이에서 기다린다")
	sel.free()
	layer.free()


## 문을 열던 분대가 다른 지시로 빠지면 기다리던 분대가 이어서 열어 끝낸다
func test_waiting_squad_takes_over() -> void:
	var s := _two_at_door()
	var sim: SimWorld = s[0]
	var attack: Crew = s[1]
	var rescue: Crew = s[2]
	var door: Opening = s[3]
	sim.doors.cancel(attack.id)
	var t := sim.doors.task_of(door)
	assert_true(t != null and t.worker() == rescue.id, "구조 분대가 여는 분대가 된다")
	for i in 6000:
		if door.is_open:
			break
		sim.step_ticks(1)
		sim.cards.queue.clear()
	assert_true(door.is_open and door.forced, "구조 분대가 문을 부숴 열었다")


## 잠기지 않은 문도 한 분대만 연다 (확인 후 개방)
func test_unlocked_door_one_opener() -> void:
	var s := _two_at_door(false)
	var sim: SimWorld = s[0]
	var attack: Crew = s[1]
	var rescue: Crew = s[2]
	var sel := SelectionController.new()
	var layer := FloorLayer.new()
	layer.setup(sim, sel, IsoProjection.new())
	layer.level = FRONT_DOOR.z
	var rart := SpriteArt.crew_set(sim.units.squads[rescue.squad_id].type)
	var dl := layer._door_check_layout(rescue, rart)
	assert_true(dl.is_empty() or sim.cards.checking_door(rescue.id) != null, "기다리는 구조 분대는 문 여는 자세가 아니다")
	for ff in rescue.members():
		assert_true(str(layer._unit_pose(ff, rescue, rart)[0]) != "door_open", "구조 분대 #%d 문 여는 자세 아님" % ff.id)
	sel.free()
	layer.free()
