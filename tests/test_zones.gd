extends TestSuite
## 구역 지정 (P10-2 ⓑ): 안전구역(건물 밖만, 낙하물 구역 경고)·환자 집결지(안전구역 안만)·진입통제선·구급대 분류소


func _sim() -> SimWorld:
	var sim := make_sim()
	sim.units.add_squad({
		"id": "ems1", "name": "구급1", "type": "구급대",
		"vehicles": [{"type": "구급차", "spawn": [50, 36], "heading": [1, 0], "driver": {"name": "민서준", "rank": "소방교"}}],
		"crews": [{"spawn": [44, 26], "members": [
			{"name": "하은수", "rank": "소방장", "role": "구급대장"},
			{"name": "도윤아", "rank": "소방사", "role": "구급대원"}]}],
	})
	return sim


## 무전이 다 나갈 때까지
func _quiet(sim: SimWorld) -> void:
	sim.step_ticks(1)
	for i in 1200:
		if not sim.command.radio.busy():
			return
		sim.step_ticks(1)


## 건물에서 떨어진 바깥 칸으로만 된 6×6 사각형 (지도에서 찾는다)
func _outdoor_rect(sim: SimWorld) -> Rect2i:
	var b := sim.building
	var fp := b.footprint(1)
	for y in range(fp.end.y + 2, b.height - 6):
		for x in range(fp.position.x, b.width - 6):
			var r := Rect2i(x, y, 6, 6)
			if sim.zones.safe_reject_reason(r) == "":
				return r
	return Rect2i()


## 구역 지정 무전 → 대원이 가서 설치(P4-4)까지 기다린다
func _zone(sim: SimWorld, answers: Dictionary) -> void:
	sim.issue(CommandOrder.make("zone", [], 0, Vector3i.ZERO, answers))
	_quiet(sim)
	for i in roundi(150.0 / SimClock.TICK_DT):
		if sim.command.post.jobs.is_empty():
			break
		sim.step_ticks(1)


func test_safe_zone_outside_only() -> void:
	var sim := _sim()
	var fp := sim.building.footprint(1)
	_zone(sim, {"kind": "safe", "rect": [fp.position.x, fp.position.y, 6, 6]})
	assert_true(not sim.zones.has_safe(), "건물과 겹치면 안전구역이 아니다")
	assert_eq(sim.events.of_type("zone_rejected").size(), 1, "거절 알림")
	var r := _outdoor_rect(sim)
	assert_true(r.size.x > 0, "바깥 사각형 찾음")
	_zone(sim, {"kind": "safe", "rect": [r.position.x, r.position.y, r.size.x, r.size.y]})
	assert_eq(sim.zones.safe, r, "안전구역 지정 (무전 전달 후)")
	assert_eq(sim.events.of_type("zone_set").size(), 1, "지정 사건")
	assert_true(sim.command.decisions.any(func(d: Dictionary) -> bool: return str(d.decision).begins_with("안전구역 지정")), "판단 기록")
	assert_true(sim.command.radio.history.any(func(m: Radio.Message) -> bool: return m.body.begins_with("안전구역 지정")), "무전으로 전파")


func test_casualty_point_only_inside_safe_zone() -> void:
	var sim := _sim()
	var r := _outdoor_rect(sim)
	_zone(sim, {"kind": "casualty", "cell": [r.position.x + 1, r.position.y + 1]})
	assert_eq(sim.zones.casualty, Vector2i(-1, -1), "안전구역이 없으면 집결지를 못 놓는다")
	_zone(sim, {"kind": "safe", "rect": [r.position.x, r.position.y, r.size.x, r.size.y]})
	_zone(sim, {"kind": "casualty", "cell": [r.end.x + 3, r.end.y + 3]})
	assert_eq(sim.zones.casualty, Vector2i(-1, -1), "안전구역 밖에는 못 놓는다")
	assert_eq(sim.events.of_type("zone_rejected").size(), 2, "두 번 거절")
	var inside := r.position + Vector2i(2, 2)
	_zone(sim, {"kind": "casualty", "cell": [inside.x, inside.y]})
	assert_eq(sim.zones.casualty, inside, "안전구역 안 집결지")
	assert_eq(sim.zones.destination(), inside, "구조자 옮길 곳 = 집결지")


func test_line_and_debris_warning() -> void:
	var sim := _sim()
	var r := _outdoor_rect(sim)
	sim.falls.zones.append({"center": Vector2(r.get_center()), "radius": 3.0, "level": 3, "tick": 0})
	_zone(sim, {"kind": "safe", "rect": [r.position.x, r.position.y, r.size.x, r.size.y]})
	assert_eq(sim.events.of_type("zone_warning").size(), 1, "낙하물 위험구역과 겹치면 경고")
	assert_true(sim.zones.has_safe(), "경고만 하고 지정은 된다")
	_zone(sim, {"kind": "line", "a": [2, 2], "b": [12, 2]})
	assert_eq(sim.zones.line.size(), 2, "진입통제선")


func test_triage_post_replaces_casualty_point() -> void:
	var sim := _sim()
	var r := _outdoor_rect(sim)
	_zone(sim, {"kind": "safe", "rect": [r.position.x, r.position.y, r.size.x, r.size.y]})
	_zone(sim, {"kind": "casualty", "cell": [r.position.x + 1, r.position.y + 1]})
	var ems := sim.units.squads[-1].crews[0].id
	var post := r.position + Vector2i(4, 4)
	sim.issue(EquipmentCommand.make("triage_post", [ems], -1, -1, Vector3i(post.x, post.y, 1)))
	sim.step_ticks(1)
	assert_eq(sim.events.of_type("triage_post_order").size(), 1, "분류소 설치 지시")
	assert_eq(sim.zones.triage, Vector2i(-1, -1), "가서 차리기 전에는 아직 없다")
	for i in roundi(300.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		if sim.zones.triage.x >= 0:
			break
	assert_eq(sim.zones.triage, post, "도착 후 설치 시간이 지나면 분류소")
	assert_eq(sim.zones.destination(), post, "분류소가 집결지를 대신한다")
	# 안전구역 밖 분류소는 거절
	sim.issue(EquipmentCommand.make("triage_post", [ems], -1, -1, Vector3i(r.end.x + 5, r.end.y + 5, 1)))
	sim.step_ticks(1)
	assert_eq(sim.events.of_type("zone_rejected").size(), 1, "안전구역 밖 분류소 거절")
