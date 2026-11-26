extends TestSuite
## 오른쪽 정보 창 (2026-11-27 사용자 결정): 대원 이름 대신 대원1·2·3 + 임무, 운전원 · 차량 종류,
## 지금 수행 중인 명령 판정(명령 칸 노란 테두리), 회색 칸 이유

const TUTORIAL := "res://data/scenarios/sop214_1_day_living.json"
const SQUADS := "res://data/scenarios/dev_squad_house_fire.json"


func _sim(path := TUTORIAL) -> SimWorld:
	var sim := SimWorld.from_scenario(path, false)
	sim.step_ticks(5)
	for v in sim.units.vehicles:
		v.away = false
	for ff in sim.units.firefighters:
		ff.aboard = false
	return sim


func _squad_of_type(sim: SimWorld, type: String) -> Squad:
	for s in sim.units.squads:
		if s.type == type and not s.crews.is_empty():
			return s
	return null


func test_member_numbers_and_roles() -> void:
	var sim := _sim(SQUADS)
	var model := SelectionModel.new(sim)
	var att := _squad_of_type(sim, "진압대")
	var c := att.crews[0]
	var labels: Array = []
	for ff in c.members():
		labels.append(model.member_label(ff, c))
	# 선두(관창을 잡는 사람)는 관창수, 나머지 일하는 대원은 관창보조, 팀장은 번호 없이 "팀장"
	var lead := model.member_label(c.leader, c)
	assert_eq(lead[1], "관창수", "진압대 선두 = 관창수")
	assert_true(lead[0].begins_with("대원"), "선두는 대원 번호: %s" % lead[0])
	var nums: Array = []
	for i in c.list.size():
		var ff := c.list[i]
		var l := model.member_label(ff, c)
		if ff.officer:
			assert_eq(l[0], "팀장", "팀장은 번호 없이")
		elif ff != c.leader:
			assert_eq(l[1], "관창보조", "선두가 아닌 진압대원 = 관창보조")
		if not ff.officer:
			nums.append(l[0])
	assert_true(nums.has("대원1") and nums.has("대원2"), "대원1·대원2 번호: %s" % [nums])
	var ems := _squad_of_type(sim, "구급대")
	if ems != null:
		var ec := ems.crews[0]
		var roles: Array = []
		for ff in ec.members():
			roles.append(model.member_label(ff, ec)[1])
		assert_true(roles.has("주처치자"), "구급대 = 주처치자: %s" % [roles])
		if ec.list.size() > 1:
			assert_true(roles.has("보조처치자"), "구급대 = 보조처치자: %s" % [roles])
	var res := _squad_of_type(sim, "구조대")
	if res != null:
		for ff in res.crews[0].members():
			if not ff.officer:
				assert_eq(model.member_label(ff, res.crews[0])[1], "구조대원", "구조대원")


func test_names_only_in_tooltip() -> void:
	var sim := _sim()
	var model := SelectionModel.new(sim)
	var c := sim.units.crews[0]
	var m := model.build([c.id] as Array[int], [] as Array[int], false, null)
	assert_true(not m.is_empty(), "조를 고르면 모델이 있다")
	var member: Dictionary = m.groups[0].members[0]
	assert_true(not str(member.num).contains(c.leader.name) and not str(member.role).contains(c.leader.name), "창에 이름이 보이지 않는다")
	assert_true(str(member.tip).contains(c.leader.name), "이름은 툴팁에")
	assert_true(float(member.air) > 0.9, "공기 막대 값")


func test_vehicle_driver_row() -> void:
	var sim := _sim()
	var model := SelectionModel.new(sim)
	var v := sim.units.vehicles[0]
	var m := model.build([] as Array[int], [v.id] as Array[int], false, null)
	var row: Dictionary = m.groups[0].members[0]
	assert_eq(str(row.num), "운전원 · %s" % v.type, "운전원 · 차량 종류")
	assert_true(not str(row.num).contains(v.driver_name) or v.driver_name == "", "운전원 이름은 창에 없다")
	if v.tank_capacity > 0.0:
		assert_true(m.bars.any(func(b: Dictionary) -> bool: return str(b.label) == "물탱크"), "물탱크 막대")


func test_crew_command_hold_and_clear() -> void:
	var sim := _sim()
	var c := sim.units.crews[0]
	assert_eq(sim.crew_command(c.id), "", "처음엔 수행 중 명령 없음")
	sim.issue(TacticalCommand.make("hold", [c.id] as Array[int]))
	sim.step_ticks(3)
	assert_eq(sim.crew_command(c.id), "hold", "대기 → hold (D 칸 노란 테두리)")
	var to := Vector3i(floori(c.leader.pos.x), floori(c.leader.pos.y), c.leader.level)
	sim.issue(MoveCommand.new([c.id] as Array[int], to))
	sim.step_ticks(3)
	assert_eq(sim.crew_command(c.id), "", "다른 지시(이동)를 받으면 대기 표시가 꺼진다")


func test_crew_command_floor_mission() -> void:
	var sim := _sim()
	var c := sim.units.crews[0]
	sim.issue(CommandOrder.make("floor_mission", [c.id], 1, Vector3i.ZERO, {"kind": "attack", "entry": -1}))
	sim.step_ticks(5)
	assert_eq(sim.crew_command(c.id), "attack", "화재진압을 받으면 attack (호스 꺼내는 중에도)")


func test_card_reasons() -> void:
	var card := CommandCard.new()
	assert_eq(card.reason({"id": "x", "need": "later"}), "다음 작업에서 쓸 수 있습니다", "나중 칸 이유")
	card.reason_fn = func(it: Dictionary) -> String: return "이유" if str(it.id) == "watch" else ""
	assert_eq(card.reason({"id": "watch"}), "이유", "reason_fn 이유")
	card.state_fn = func(it: Dictionary) -> int: return CmdButton.STATE_ACTIVE if str(it.id) == "attack" else 0
	assert_eq(card.state({"id": "attack"}), CmdButton.STATE_ACTIVE, "state_fn 수행 중")
	assert_eq(card.state({}), 0, "빈 칸은 상태 없음")
