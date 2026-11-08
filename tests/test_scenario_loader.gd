extends TestSuite
## M6b: 시나리오 목록·검증, 시나리오별 장비, 판마다 다른 변형

const BAD_PATH := "user://scenarios/_test_broken.json"


func test_list_and_validate_builtin() -> void:
	var list := ScenarioLoader.list()
	var ids: Array[String] = []
	for s in list:
		if s.source == "기본":
			ids.append(s.id)
			assert_eq(s.errors, PackedStringArray(), "검증 통과: %s" % s.title)
	assert_eq(ids, ["tutorial_basics", "sop214_1_day_living", "sop214_2_night_upstairs", "sop214_3_kitchen_lpg", "sop214_4_alley", "sop213_1_apartment_3f", "sop213_2_apartment_night", "sop212_1_commercial_kitchen", "sop213_3_15f_day_low", "sop213_4_15f_night_mid", "sop213_5_15f_winter_high", "dev_house_fire"] as Array[String], "meta.order 순서 (튜토리얼이 맨 위)")
	assert_eq(str(list[0].meta.difficulty), "튜토리얼", "튜토리얼 표시")
	assert_eq(str(list[1].meta.difficulty), "입문", "난이도 표시")
	assert_true(list[1].objectives.size() >= 3, "학습 목표")


func test_broken_scenario_errors() -> void:
	DirAccess.make_dir_recursive_absolute("user://scenarios")
	var d: Dictionary = JsonData.load_file(DEV_SCENARIO_PATH)
	d.fire.ignitions = [{"level": 1, "cell": [2, 2], "time_s": 0}]
	d.victims[0].room = "없는방"
	d.evaluation.rules.append("없는.규칙")
	d.site.witnesses[0].pos = [8, 10]  # 벽
	d.erase("dispatch")
	var f := FileAccess.open(BAD_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var errors := ScenarioLoader.validate(BAD_PATH)
	assert_true("\n".join(errors).contains("필수 항목 'dispatch'"), "필수 항목 누락 (%s)" % errors)
	d["dispatch"] = {"title": "x", "lines": []}
	f = FileAccess.open(BAD_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	errors = ScenarioLoader.validate(BAD_PATH)
	var text := "\n".join(errors)
	assert_true(text.contains("발화 지점") and text.contains("방 안이 아닙니다"), "발화 지점이 마당")
	assert_true(text.contains("'없는방'"), "없는 방")
	assert_true(text.contains("'없는.규칙'"), "없는 규칙")
	assert_true(text.contains("관계인") and text.contains("걸을 수 있는 칸이 아닙니다"), "관계인 위치가 벽 안")
	var found := false
	for s in ScenarioLoader.list():
		if s.path == BAD_PATH:
			found = true
			assert_eq(s.source, "추가", "user:// 시나리오는 '추가'")
			assert_true(not s.errors.is_empty(), "목록에서도 오류 표시")
	assert_true(found, "추가 시나리오 폴더도 읽는다")
	DirAccess.remove_absolute(BAD_PATH)
	f = FileAccess.open("user://scenarios/_test_bad_json.json", FileAccess.WRITE)
	f.store_string("{ \"id\": ")
	f.close()
	assert_true(str(ScenarioLoader.validate("user://scenarios/_test_bad_json.json")).contains("JSON 형식"), "JSON 형식 오류")
	DirAccess.remove_absolute("user://scenarios/_test_bad_json.json")


func test_vehicle_override() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/sop214_3_kitchen_lpg.json")
	assert_eq(sim.units.vehicles[0].tank_capacity, 2400.0, "시나리오가 펌프차 탱크를 덮어쓴다")
	assert_eq(sim.units.vehicles[1].tank_capacity, 10000.0, "다른 차종은 기본 제원")
	var dev := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	assert_eq(dev.units.vehicles[0].tank_capacity, 3000.0, "덮어쓰지 않으면 기본 제원")


func test_random_seed_variation() -> void:
	var path := "res://data/scenarios/sop214_2_night_upstairs.json"
	var rooms := {}
	for s in 12:
		var sim := SimWorld.from_scenario(path, true, s * 7919)
		var v := sim.rescue.victims[1]
		var room := sim.fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
		rooms[room.id] = true
		assert_eq(sim.rng_seed, s * 7919, "쓴 시드 기록")
	assert_true(rooms.size() == 2, "판마다 딸의 위치가 후보 방 사이에서 바뀐다 (%s)" % [rooms.keys()])
	var a := SimWorld.from_scenario(path, true, 42)
	var b := SimWorld.from_scenario(path, true, 42)
	assert_eq(a.rescue.victims[1].pos, b.rescue.victims[1].pos, "같은 시드면 같은 위치 (다시 하기)")
