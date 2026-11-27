extends TestSuite
## 문 종류 (2026-11-27 사용자 결정 — 문창 그림): 건물 JSON door_kinds > fire_doors = 방화문 > 바깥 문 = 철문 > 실내 = 목재문


func test_rule_and_override() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var b := sim.building
	var outer: Opening = null
	var inner: Opening = null
	for o in sim.fire.openings:
		if o.kind != Opening.Kind.DOOR:
			continue
		if o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE:
			outer = o if outer == null else outer
		else:
			inner = o if inner == null else inner
	assert_true(outer != null and inner != null, "바깥 문·실내 문이 있다")
	assert_eq(b.door_kind(outer.cells, true), "steel", "바깥으로 난 문 = 현관 철문")
	assert_eq(b.door_kind(inner.cells, false), "wood", "실내 문 = 목재문")
	b.fire_doors.append(inner.cells[0])
	assert_eq(b.door_kind(inner.cells, false), "fire", "fire_doors 칸 = 방화문")
	b.door_kinds[inner.cells[0]] = "wood"
	assert_eq(b.door_kind(inner.cells, false), "wood", "건물 JSON door_kinds 가 먼저")


func test_apartment_fire_doors() -> void:
	var b := BuildingData.from_file("res://data/buildings/apartment_15f.json")
	assert_true(not b.fire_doors.is_empty(), "아파트에 방화문 칸이 있다")
	var cells: Array[Vector2i] = [b.fire_doors[0]]
	assert_eq(b.door_kind(cells, false), "fire", "아파트 현관 방화문")


func test_skin_has_door_colors() -> void:
	var skin := TileSkin.load_default()
	for k in ["door_steel", "door_fire", "door_wood", "door_frame", "door_handle", "fire_sign", "lock_mark", "window_frame", "glass_shard"]:
		assert_true(skin.color(k, Color.MAGENTA) != Color.MAGENTA, "색 표에 %s" % k)
