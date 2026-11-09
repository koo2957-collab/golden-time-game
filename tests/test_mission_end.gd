extends TestSuite
## P11-1: 종료 조건 (기획안 8-3) — 제한 시간 없음, 전소 자동 종료·결과 보기, 작전 완료·조기 종료, 종료 제안 반복, 미완료 기록, 프로필


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.fire.opening_at(Vector3i(31, 12, 1)).is_open = true
	sim.doors.sync_blocking()
	sim.phases._enter(PhaseSystem.Phase.OPERATIONS, 0)
	return sim


func test_burnout_ends_by_itself() -> void:
	# 방수 없이 방치하면 불이 스스로 다 타서 꺼지고 '전소'로 자동 종료 (기획안 8-3)
	var sim := _sim()
	var certain_tick := -1
	var limit := roundi(3.0 * 3600.0 / SimClock.TICK_DT)
	while not sim.ended() and sim.clock.tick < limit:
		sim.step_ticks(100)
		if certain_tick < 0 and sim.mission_end.burnout_certain(sim.clock.tick):
			certain_tick = sim.clock.tick
	assert_true(sim.ended(), "현장 시간 3시간 안에 끝남 (%d초)" % roundi(sim.clock.tick * SimClock.TICK_DT))
	assert_eq(sim.end_type, MissionEndChecker.END_BURNOUT, "전소 (%s)" % sim.end_reason)
	assert_true(certain_tick >= 0 and certain_tick < sim.ended_tick, "끝나기 전에 '전소 확실'(결과 보기)이 먼저 뜸")
	var r := Evaluator.evaluate(sim)
	for a: Dictionary in r.axes:
		if a.id in ["property", "fire"]:
			assert_eq([a.applicable, a.score], [true, 0.0], "전소면 %s 0점" % a.name)
	assert_eq([r.end_type, r.result], [MissionEndChecker.END_BURNOUT, "완료"], "결과에 종료 종류")


func test_burnout_rules() -> void:
	var sim := _sim()
	var me := sim.mission_end
	var comps := me.building_comps()
	assert_true(not me.burned_out(), "처음에는 전소 아님")
	assert_eq(me.loss_class(), "부분소", "처음은 부분소")
	# 건물 가연물 80% 소실, 불은 꺼짐 → 전소 (화재1 5쪽: 70% 이상)
	for c in comps:
		c.ever_burned = true
		c.fuel_remaining = c.fuel_initial * 0.2
	assert_true(me.burned_out(), "70% 넘게 타고 불이 꺼지면 전소")
	assert_eq(me.loss_class(), "전소", "소실 정도 전소")
	for c in comps:
		c.fuel_remaining = c.fuel_initial * 0.5
	assert_true(not me.burned_out(), "50%만 탔으면 끝내지 않음")
	assert_eq(me.loss_class(), "반소", "소실 정도 반소 (30~70%)")
	for c in comps:
		c.fuel_remaining = c.fuel_initial * 0.1
	sim.phases.knockdown_tick = 5
	assert_true(not me.burned_out(), "대원이 초진했으면 전소로 끝내지 않음")
	sim.phases.knockdown_tick = -1
	for c in comps:
		c.fuel_remaining = c.fuel_initial
	for i in ceili(comps.size() * 0.5):
		sim.collapse.collapsed[comps[i].index] = true
	assert_true(me.burned_out(), "화재 건물 구획 절반 붕괴 → 전소")


func test_declared_complete_vs_early() -> void:
	var sim := _sim()
	sim.step_ticks(roundi(120.0 / SimClock.TICK_DT))
	assert_true(not sim.unsearched_rooms().is_empty(), "불이 난 뒤 검색 전에는 발화층에 미검색 구역이 있음")
	assert_eq(sim.mission_end.declared_type(sim.unsearched_rooms().size()), MissionEndChecker.END_EARLY, "완진 전 선언은 조기 종료")
	# 완진 뒤, 타는 칸 없고 미검색 구역 없음 → 작전 완료
	sim.phases.declare_all_clear(sim.clock.tick)
	for c in sim.fire.comps:
		c.searched_tick = 10
	# 진압이 끝난 상태로 만든다 (타는 칸 없음)
	for i in sim.fire.grid.burning:
		sim.fire.grid.state[i] = FuelGrid.State.UNBURNED
	sim.fire.grid.burning.clear()
	assert_eq(sim.unsearched_rooms().size(), 0, "모두 검색")
	sim.end_activity("활동 종료 선언")
	assert_eq(sim.end_type, MissionEndChecker.END_COMPLETE, "작전 완료")


func test_crew_death_does_not_end() -> void:
	var sim := _sim()
	sim.units.firefighters[0].incapacitated = true
	sim.step_ticks(50)
	assert_true(not sim.ended(), "대원이 쓰러져도 게임은 계속")


func test_end_suggestion_repeats() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.phases._enter(PhaseSystem.Phase.OPERATIONS, 0)
	for v in sim.rescue.victims:
		v.state = Victim.State.DEAD
	var me := sim.mission_end
	var t := 10
	sim.phases.step(0.1, t, true)
	t += roundi(61.0 / SimClock.TICK_DT)
	sim.phases.step(0.1, t, true)
	assert_eq(sim.events.of_type("end_suggested").size(), 1, "첫 종료 제안")
	me.step(t, false)
	me.step(t + roundi(299.0 / SimClock.TICK_DT), false)
	assert_eq(sim.events.of_type("end_suggested").size(), 1, "5분 안에는 다시 알리지 않음")
	me.step(t + roundi(301.0 / SimClock.TICK_DT), false)
	assert_eq(sim.events.of_type("end_suggested").size(), 2, "5분 뒤 다시 알림 (강제 종료 아님)")
	assert_true(not sim.ended(), "알림만, 종료는 지휘관이")


func test_incomplete_record() -> void:
	var dir := "user://test_reports_incomplete"
	DirAccess.make_dir_recursive_absolute(dir)
	var sim := _sim()
	sim.step_ticks(20)
	sim.end_activity("임무 포기", MissionEndChecker.END_INCOMPLETE)
	var r := Evaluator.evaluate(sim)
	assert_eq(r.result, "미완료", "미완료 기록")
	var f := FileAccess.open(dir + "/a_incomplete.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(r))
	f.close()
	var done := r.duplicate(true)
	done["result"] = "완료"
	done["grade"] = "A"
	f = FileAccess.open(dir + "/b_done.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(done))
	f.close()
	var list := PlayHistory.entries(dir)
	assert_eq(list.size(), 2, "두 판 모두 목록에")
	assert_eq([list[0].incomplete, list[1].incomplete], [true, false], "미완료 표시")
	assert_eq(PlayHistory.completed(list).size(), 1, "성장·집계에는 끝낸 판만")
	assert_eq(PlayHistory.aggregate(list).scenarios[0].plays, 1, "익명 집계에 미완료 제외")
	var incomplete_only: Array[Dictionary] = [list[0]]
	incomplete_only[0]["grade"] = "S"
	assert_true(Campaign.best_grades(incomplete_only).is_empty(), "캠페인 진행에 미완료 제외")
	assert_true(HistoryUi.text_for(list).contains("미완료"), "내 기록 화면에 미완료")
	var line := ReportExport.csv_line(r)
	assert_true(line.contains("\"미완료\""), "CSV에 결과 열")
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + name)
	DirAccess.remove_absolute(dir)


func test_profile_and_next_stage() -> void:
	var path := "user://test_profile.json"
	assert_true(not Profile.has_profile(path + ".none"), "처음에는 프로필 없음")
	assert_true(Profile.save_profile(" 홍길동 ", "가상119안전센터", path), "저장")
	assert_eq(Profile.load_profile(path), {"name": "홍길동", "unit": "가상119안전센터"}, "이름·소속")
	assert_eq(Profile.text(Profile.load_profile(path)), "홍길동 · 가상119안전센터", "화면 한 줄")
	DirAccess.remove_absolute(path)
	var chapters := Campaign.chapters()
	var first := str(chapters[0].scenarios[0])
	var second := str(chapters[1].scenarios[0])
	assert_eq(Campaign.next_id(first), second, "캠페인 다음 스테이지")
	assert_true(Campaign.next_path(first).ends_with(second + ".json"), "다음 스테이지 파일")
	var last_ch: Dictionary = chapters[-1]
	assert_eq(Campaign.next_id(str(last_ch.scenarios[-1])), "", "마지막 다음은 없음")
