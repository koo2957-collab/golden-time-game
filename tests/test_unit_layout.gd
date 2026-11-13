extends TestSuite
## P2-2: 층·세대별 구조 변형과 집기 배치 (기획안 4-2-1) — 같은 뼈대, 다른 속

const APT15 := "res://data/scenarios/sop213_3_15f_day_low.json"
const BUILDING := "res://data/buildings/apartment_15f.json"


func _layout(p_seed: int, setup: Dictionary) -> UnitAssembly:
	var b := BuildingData.from_file(BUILDING)
	var raw: Dictionary = JsonData.load_file(BUILDING)
	return UnitAssembly.apply(b, raw.units, p_seed, setup)


func _mix() -> Dictionary:
	return {"mix": {"variants": {"표준": 6, "발코니확장": 2, "현관잠김": 1, "도어체크": 1, "피난막힘": 1},
		"furnishings": {"일반": 5, "노인1인": 1, "짐많음": 2, "공실": 1, "리모델링": 1}}}


func _signature(a: UnitAssembly) -> Array:
	return a.units.map(func(u: Dictionary) -> String: return "%s:%s:%s" % [u.name, u.variant, u.furnish])


func test_same_seed_same_map() -> void:
	var a := _layout(7, _mix())
	var b := _layout(7, _mix())
	var c := _layout(8, _mix())
	assert_true(a.units.size() >= 28, "15층 × 2세대 (%d세대)" % a.units.size())
	assert_eq(_signature(a), _signature(b), "같은 시드는 같은 맵")
	assert_true(_signature(a) != _signature(c), "다른 시드는 세대 변형·집기가 다름")


func test_no_setup_is_standard() -> void:
	var a := _layout(7, {})
	assert_true(a.units.all(func(u: Dictionary) -> bool: return u.variant == "표준" and u.furnish == "일반"), "설정이 없으면 모두 표준 평면 + 일반 집기 (지금까지와 같은 맵)")
	assert_eq(a.plan_diffs.size(), 0, "도면 차이 없음")


func test_overrides_win() -> void:
	var setup := _mix()
	setup["overrides"] = {"501": {"variant": "현관잠김", "furnish": "짐많음"}}
	var a := _layout(3, setup)
	var u := a.unit_named("501호")
	assert_eq([u.variant, u.furnish], ["현관잠김", "짐많음"], "교관 지정 세대가 우선")


func test_vertical_core_same_on_all_floors() -> void:
	var sim := SimWorld.from_scenario(APT15, false)
	var stair_rects := {}
	for lv in sim.building.levels():
		for r in sim.building.rooms(lv):
			if str(r.name) == "계단실":
				stair_rects[r.rect] = true
	assert_eq(stair_rects.size(), 1, "계단실 위치는 모든 층에서 같음")


func test_plan_shows_standard_only() -> void:
	var setup := {"overrides": {"601": {"variant": "발코니확장"}}}
	var sim := _sim_with(setup)
	var u := sim.unit_layout.unit_named("601호")
	assert_eq(u.variant, "발코니확장", "601호 발코니 확장")
	var found := sim.plan.diffs.filter(func(d: Dictionary) -> bool: return int(d.level) == 6 and str(d.note).contains("601호"))
	assert_eq(found.size(), 1, "도면에는 표준(벽)으로 나오고, 실제와 다른 곳으로 기록")
	# 오른쪽 세대는 좌우가 뒤집힌다
	var s2 := _sim_with({"overrides": {"602": {"variant": "발코니확장"}}})
	var d2: Array = s2.plan.diffs.filter(func(d: Dictionary) -> bool: return str(d.note).contains("602호"))
	assert_true(not d2.is_empty() and int(d2[0].cells[0].x) >= 33, "오른쪽 세대는 뒤집힌 자리 (%s)" % [d2[0].cells[0] if not d2.is_empty() else "-"])


func test_cluttered_unit_burns_more_and_walks_slower() -> void:
	var sim := _sim_with({"overrides": {"701": {"furnish": "짐많음"}, "702": {"furnish": "일반"}}})
	var fuel_701 := 0.0
	var fuel_702 := 0.0
	for c in sim.fire.comps:
		if c.display_name().contains("701호"):
			fuel_701 += c.fuel_initial
		elif c.display_name().contains("702호"):
			fuel_702 += c.fuel_initial
	# 2026-11-13 (P1): 생활용품은 용도별 화재하중에 맞춰 함께 늘고 쌓아 둔 짐(적재물)은 그대로라 차이 비율이 줄었다 (예전 1.15배 이상)
	assert_true(fuel_701 > fuel_702 * 1.05, "짐 많은 세대 가연물이 큼 (%.0f MJ > %.0f MJ)" % [fuel_701, fuel_702])
	var block := 0
	for item in sim.building.furniture(7):
		if str(item.get("unit", "")) == "701호" and str(item.get("pass", "")) == "block":
			block += 1
	assert_true(block >= 5, "짐 많은 세대는 막힌 칸이 많음 (%d)" % block)
	var lone := _sim_with({"overrides": {"701": {"furnish": "노인1인"}}})
	var hide_cells := 0
	for item in lone.building.furniture(7):
		if str(item.get("unit", "")) == "701호" and float(item.get("hide", 0.0)) > 0.0:
			hide_cells += 1
	assert_true(hide_cells >= 2, "숨는 곳 가중치(장롱·이불·침대)")


func test_front_door_states() -> void:
	var sim := _sim_with({"overrides": {"901": {"variant": "현관잠김"}, "902": {"variant": "도어체크"}}})
	var u1 := sim.unit_layout.unit_named("901호")
	var u2 := sim.unit_layout.unit_named("902호")
	var o1 := sim.fire.opening_at(Vector3i(u1.front_door.x, u1.front_door.y, 9))
	var o2 := sim.fire.opening_at(Vector3i(u2.front_door.x, u2.front_door.y, 9))
	assert_true(o1 != null and o1.locked and not o1.is_open, "현관문 잠김 → 파괴 필요")
	assert_true(o2 != null and o2.door_check, "도어체크 문")
	sim.perception.enabled = false
	sim.step_ticks(SimWorld.PERCEPTION_EVERY_TICKS + 1)
	var seen := sim.events.of_type("door_check_seen")
	assert_true(seen.any(func(e: Dictionary) -> bool: return str(e.unit) == "902호"), "대원이 도어체크를 보면 '안에 사람이 있을 수 있다' 보고")


func test_check_below_estimate_and_difference() -> void:
	var sim := _sim_with({"overrides": {"1101": {"variant": "발코니확장"}, "1001": {"variant": "표준"}}})
	var above := sim.unit_layout.unit_named("1101호")
	var target := Vector3i((above.rect as Rect2i).get_center().x, (above.rect as Rect2i).get_center().y, 11)
	var ok := sim.tactical.order("check_below", 0, target, 0)
	assert_true(ok, "직하층 확인 임무")
	var t := sim.tactical.task_of_crew(0)
	assert_true(t != null and str(t.unit_check.below) == "1001호", "바로 아래 1001호를 돈다")
	# 아래 세대를 다 돌았다고 보고 마무리
	sim.tactical._next_unit_room(sim.units.get_crew(0), [] as Array[int], t.unit_check, 10)
	assert_true(sim.tactical.unit_estimates.has("1101호"), "1101호 추정 구조 = 1001호 (상황판 점선)")
	assert_eq(sim.events.of_type("below_checked").size(), 1, "직하층 확인 기록 (DecisionLog)")
	sim.perception.enabled = false
	sim.step_ticks(SimWorld.PERCEPTION_EVERY_TICKS + 1)
	var diff := sim.events.of_type("estimate_differs")
	assert_true(diff.any(func(e: Dictionary) -> bool: return str(e.unit) == "1101호"), "들어가 보니 다르면 '구조가 다릅니다' 보고")


func test_load_time() -> void:
	var t0 := Time.get_ticks_msec()
	var sim := SimWorld.from_scenario(APT15)
	var ms := Time.get_ticks_msec() - t0
	assert_true(sim != null, "15층 동 로드")
	print("    15층 동 로드 %d ms (세대 %d개 조립)" % [ms, sim.unit_layout.units.size()])


func _sim_with(setup: Dictionary) -> SimWorld:
	var data: Dictionary = JsonData.load_file(APT15)
	return SimWorld.create(str(data.building), str(data.roster), SimWorld.DEFAULT_UNIT_STATS_PATH, int(data.seed), {}, setup)
