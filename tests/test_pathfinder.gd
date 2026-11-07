extends TestSuite


func _check_path(b: BuildingData, path: Array[Vector3i], label: String) -> void:
	for i in path.size():
		var p := path[i]
		assert_true(b.is_walkable(p.z, p.x, p.y), "%s: %s 는 걸을 수 있는 셀" % [label, p])
		if i > 0:
			var q := path[i - 1]
			var step := maxi(absi(p.x - q.x), absi(p.y - q.y))
			if p.z != q.z:
				assert_eq(Vector2i(p.x, p.y), Vector2i(q.x, q.y), "%s: 층 이동은 같은 위치(계단)에서" % label)
				assert_eq(b.cell(q.z, q.x, q.y), BuildingData.Cell.STAIRS, "%s: 층 이동 지점은 계단" % label)
			else:
				assert_eq(step, 1, "%s: %s→%s 는 인접 셀" % [label, q, p])


func test_path_from_road_to_living_room() -> void:
	var b := BuildingData.from_file(BUILDING_PATH)
	var pf := Pathfinder.new(b)
	var path := pf.find_path(Vector3i(10, 26, 1), Vector3i(12, 15, 1))
	assert_true(not path.is_empty(), "도로 → 거실 경로 존재")
	assert_eq(path[-1], Vector3i(12, 15, 1), "목표 도착")
	_check_path(b, path, "도로→거실")
	var through_door := false
	for p in path:
		if b.cell(p.z, p.x, p.y) == BuildingData.Cell.DOOR:
			through_door = true
	assert_true(through_door, "문을 통과함")


func test_path_to_second_floor_uses_stairs() -> void:
	var b := BuildingData.from_file(BUILDING_PATH)
	var pf := Pathfinder.new(b)
	var path := pf.find_path(Vector3i(10, 26, 1), Vector3i(12, 17, 2))
	assert_true(not path.is_empty(), "도로 → 2층 방3 경로 존재")
	assert_eq(path[-1], Vector3i(12, 17, 2), "2층 목표 도착")
	_check_path(b, path, "도로→2층")


func test_unreachable_returns_empty() -> void:
	var b := BuildingData.from_file(BUILDING_PATH)
	var pf := Pathfinder.new(b)
	assert_true(pf.find_path(Vector3i(10, 26, 1), Vector3i(8, 3, 1)).is_empty(), "벽으로는 경로 없음")
	assert_true(pf.find_path(Vector3i(10, 26, 1), Vector3i(0, 0, 2)).is_empty(), "2층 빈 공간으로는 경로 없음")


func test_nearest_walkable() -> void:
	var b := BuildingData.from_file(BUILDING_PATH)
	var pf := Pathfinder.new(b)
	var c := pf.nearest_walkable(1, Vector2i(19, 15))
	assert_true(b.is_walkable(1, c.x, c.y), "벽 클릭 시 가까운 바닥 셀")
	assert_eq(pf.nearest_walkable(2, Vector2i(0, 0)), Pathfinder.NO_CELL, "주변에 바닥이 없으면 NO_CELL")


func test_formation_slots_are_spaced() -> void:
	var b := BuildingData.from_file(BUILDING_PATH)
	var pf := Pathfinder.new(b)
	var slots := pf.formation_slots(1, Vector2i(14, 16), 4)
	assert_eq(slots.size(), 4, "4개 슬롯")
	for i in slots.size():
		assert_true(b.room_at(1, slots[i].x, slots[i].y).get("name") == "거실", "슬롯이 같은 방(거실) 안에 있음")
		for j in range(i + 1, slots.size()):
			var d := maxi(absi(slots[i].x - slots[j].x), absi(slots[i].y - slots[j].y))
			assert_true(d >= 2, "슬롯 간격 2셀 이상")
