extends TestSuite
## 문 개방 때 분대 배치 (2026-11-24 사용자 결정, 화재1 p.134·215·217): 문을 여는 대원과 관창은 정면을 피해 측면.
## 관창수는 경첩 쪽(여는 사람은 손잡이 쪽)에서 문에 가장 가깝게, 관창보조·팀장은 그 뒤. 문 일을 하는 사람(여는 사람·부수는 두 사람)
## 말고는 아무도 문 정면 띠(문 폭 + 양옆 door_front_margin_m)에 서지 않는다.
## 사용자 지적: "두 명이 문을 개방할 때 팀장이나 누군가가 문 정면에 딱 붙어 있는 것은 이상하다"

const SCENARIO := "res://data/scenarios/dev_squad_house_fire.json"
const FRONT_DOOR := Vector3i(13, 20, 1)


## 진압 분대(조 0)가 호스를 가지고 현관문에서 문 일을 시작한 상태 → [sim, 조, 문]
func _at_door(locked: bool) -> Array:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var crew := sim.units.get_crew(0)
	var door := sim.fire.opening_at(FRONT_DOOR)
	door.locked = locked
	door.is_open = false
	sim.doors.sync_blocking()
	sim.water.lay_hose(crew.id, sim.water._nearest_pump(crew.leader.pos), sim.clock.tick)
	var h := fetch_hose(sim, crew.id, false)
	if h != null:
		h.ready_tick = 1 << 30
	sim.doors.request(crew.id, FRONT_DOOR, true, sim.clock.tick)
	for i in 4000:
		var t := sim.doors.task_of_crew(crew.id)
		if t != null and t.open and not t.waiting_people and t.progress > 0.3 and not crew.leader.is_moving():
			break
		sim.step_ticks(1)
		sim.cards.queue.clear()
	return [sim, crew, door]


func _check(locked: bool) -> void:
	var s := _at_door(locked)
	var sim: SimWorld = s[0]
	var crew: Crew = s[1]
	var door: Opening = s[2]
	var sel := SelectionController.new()
	var layer := FloorLayer.new()
	layer.setup(sim, sel, IsoProjection.new())
	layer.level = FRONT_DOOR.z
	var art := SpriteArt.crew_set(sim.units.squads[crew.squad_id].type)
	var tl := layer._door_team_layout(crew, art)
	assert_true(not tl.is_empty(), "문 개방 분대 배치가 있다")
	if tl.is_empty():
		sel.free()
		layer.free()
		return
	var center := FloorLayer.door_center(door)
	var facing: Vector2 = tl.facing
	var across := facing.rotated(PI / 2.0)
	var cell_m := sim.units.cell_size_m
	var band := (door.cells.size() * cell_m * 0.5 + float(HoseDraw.style().get("door_front_margin_m", 0.3))) / cell_m
	var hinge := layer._hinge_dir(facing, art)
	var lead_d := INF
	for ff in crew.members():
		var pose := str(layer._unit_pose(ff, crew, art)[0])
		var at := layer._shown_pos(ff, 0.0)
		if pose in ["force_a", "force_b", "door_open", "door_feel"]:
			continue
		var off := (at - center).dot(across)
		assert_true(absf(off) >= band - 0.05, "#%d(%s)는 문 정면 띠 밖 (옆으로 %.2f칸, 띠 %.2f칸)" % [ff.id, pose, absf(off), band])
		assert_true((at - center).dot(hinge) > 0.0, "#%d는 경첩 쪽" % ff.id)
		if ff == crew.leader:
			lead_d = at.distance_to(center)
	for ff in crew.members():
		var pose := str(layer._unit_pose(ff, crew, art)[0])
		if ff != crew.leader and not pose in ["force_a", "force_b", "door_open", "door_feel"]:
			assert_true(layer._shown_pos(ff, 0.0).distance_to(center) > lead_d, "관창수가 문 일을 하지 않는 조원 중 문에 가장 가깝다 (#%d)" % ff.id)
	assert_eq(str(layer._unit_pose(crew.leader, crew, art)[0]), "spray_ln", "관창수는 낮은 자세 방수태세")
	# 문을 확인·여는 사람은 손잡이 쪽 (경첩 반대쪽)
	var dl := layer._door_check_layout(crew, art)
	if not dl.is_empty():
		assert_true(((dl.spot as Vector2) - center).dot(hinge) < 0.0, "문을 여는 사람은 손잡이 쪽")
	sel.free()
	layer.free()


## 잠긴 문 파괴: 부수는 두 사람 말고는 문 정면 띠 밖, 관창수는 경첩 쪽 맨 앞
func test_forcing_layout() -> void:
	_check(true)


## 잠기지 않은 문 확인·개방: 여는 사람은 손잡이 쪽, 관창수는 경첩 쪽, 나머지는 그 뒤
func test_opening_layout() -> void:
	_check(false)
