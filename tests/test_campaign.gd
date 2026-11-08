extends TestSuite
## M7c-3: 대원 개성, 캠페인 뼈대


func _e(id: String, grade: String) -> Dictionary:
	return {"scenario_id": id, "grade": grade}


func test_traits_apply() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var squad := sim.units.add_squad({"id": "t", "name": "시험", "type": "진압대", "crews": [{"spawn": [44, 26], "members": [
		{"name": "가", "rank": "소방장", "traits": ["베테랑"]},
		{"name": "나", "rank": "소방사", "traits": ["신참"]}]}]})
	var c := squad.crews[0]
	assert_eq(c.leader.traits, ["베테랑"] as Array[String], "개성 기록")
	assert_true(c.leader.air_factor < 1.0 and c.partner.air_factor > 1.0, "베테랑은 공기를 덜, 신참은 더 쓴다")
	assert_true(c.partner.heat_factor > 1.0, "신참은 열에 약함")
	# 같은 곳에 같은 시간 있으면 신참이 공기를 더 쓴다
	for ff in c.members():
		ff.pos = Vector2(15.5, 10.5)
		ff.prev_pos = ff.pos
	sim.step_ticks(600)
	assert_true(c.partner.air_l < c.leader.air_l, "공기 잔량 차이 (%.0f / %.0f)" % [c.leader.air_l, c.partner.air_l])


func test_reinforcements_have_traits() -> void:
	var data: Dictionary = JsonData.load_file("res://data/units/dev_reinforcements.json")
	var n := 0
	for s: Dictionary in data.squads:
		for c: Dictionary in s.crews:
			for m: Dictionary in c.members:
				for t in m.get("traits", []):
					assert_true(UnitSystem.traits().has(t), "개성 '%s' 정의됨" % t)
					n += 1
	assert_true(n >= 5, "후착대에 개성 있는 대원 %d명" % n)


func test_campaign_progress() -> void:
	var p := Campaign.progress([] as Array[Dictionary])
	assert_true(p.size() >= 4, "장 %d개" % p.size())
	assert_eq(p[0].status, Campaign.Status.OPEN, "처음에는 1장만 도전 가능")
	assert_eq(p[1].status, Campaign.Status.LOCKED, "2장 잠김")
	p = Campaign.progress([_e("tutorial_basics", "D"), _e("sop214_1_day_living", "D")] as Array[Dictionary])
	assert_eq(p[0].status, Campaign.Status.DONE, "튜토리얼은 끝내면 완료")
	assert_eq(p[1].status, Campaign.Status.OPEN, "2장은 C 미만이면 아직 도전 중")
	p = Campaign.progress([_e("tutorial_basics", "D"), _e("sop214_1_day_living", "D"), _e("sop214_1_day_living", "B")] as Array[Dictionary])
	assert_eq(p[1].grades.sop214_1_day_living, "B", "최고 등급")
	assert_eq(p[1].status, Campaign.Status.DONE, "B면 2장 완료")
	assert_eq(p[2].status, Campaign.Status.OPEN, "3장 열림")
	for ch: Dictionary in p:
		if ch.chapter.scenarios.is_empty():
			assert_eq(ch.status, Campaign.Status.SOON, "시나리오 없는 장은 준비 중")
	assert_eq(p.size(), 8, "8장 (고층 아파트·지휘권 이양 포함)")
	var ids := {}
	for s in ScenarioLoader.list():
		ids[str(s.id)] = true
	for ch: Dictionary in Campaign.chapters():
		for id in ch.scenarios:
			assert_true(ids.has(str(id)), "캠페인 시나리오 %s 존재" % id)
