extends TestSuite
## R12: 디브리핑 확장 — 인쇄용 보고서·CSV(기획안 8-1 ⑤), 대원 성장(6-2), 리플레이 보기(명령 없이 기록대로)

const TMP := "user://test_r12"


func _finished_sim() -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.step_ticks(50)
	sim.end_activity("test")
	return sim


func test_html_and_csv() -> void:
	var sim := _finished_sim()
	var report := Evaluator.evaluate(sim)
	var html := ReportExport.html(report)
	assert_true(html.contains("<html") and html.contains("5축 점수") and html.contains("판정 항목"), "인쇄용 HTML")
	assert_true(html.contains("window.print()"), "인쇄·PDF 버튼")
	var line := ReportExport.csv_line(report)
	assert_true(line.contains(str(report.grade)) and line.split(",").size() >= 11, "CSV 한 줄 (%s)" % line)
	DirAccess.make_dir_recursive_absolute(TMP)
	var path := ReportExport.save(report, TMP)
	assert_true(FileAccess.file_exists(path), "HTML 저장")
	ReportExport.save(report, TMP)
	var csv := FileAccess.get_file_as_string(TMP + "/" + ReportExport.CSV_NAME)
	assert_eq(csv.split("\n", false).size(), 3, "머리줄 + 두 판")
	for f in DirAccess.get_files_at(TMP):
		DirAccess.remove_absolute(TMP + "/" + f)


func test_crew_growth() -> void:
	var path := TMP + "_growth.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	assert_eq(str(CrewGrowth.level_of(0).name), "신임", "0 = 신임")
	assert_eq(str(CrewGrowth.level_of(3).name), "일반", "3 = 일반")
	assert_eq(str(CrewGrowth.level_of(15).name), "고참", "15 = 고참")
	var sim := _finished_sim()
	var report := Evaluator.evaluate(sim)
	var lines := CrewGrowth.award(sim, report, path)
	assert_true(not lines.is_empty(), "판을 마치면 경험치 (%s)" % [lines])
	var xp := CrewGrowth.load_xp(path)
	assert_true(float(xp.get("김도현", 0)) >= 4.0, "기본 3 + 참가 1 이상")
	# 고참으로 시작하면 공기를 덜 쓴다
	var sim2 := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var ff := sim2.units.get_crew(0).leader
	var before := ff.air_factor
	sim2.apply_growth({ff.name: 20})
	assert_eq(ff.grade, "고참", "고참")
	assert_true(ff.air_factor < before, "고참은 공기를 덜 쓴다")
	DirAccess.remove_absolute(path)


func test_view_only_replay_ignores_commands() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	sim.view_only = true
	sim.issue(MoveCommand.new([0] as Array[int], Vector3i(20, 23, 1)))
	sim.step_ticks(2)
	assert_eq(sim.command_log.entries.size(), 0, "리플레이 보기는 플레이어 명령을 받지 않는다")
	sim.issue_replay(MoveCommand.new([0] as Array[int], Vector3i(20, 23, 1)))
	sim.step_ticks(2)
	assert_eq(sim.command_log.entries.size(), 1, "기록된 명령은 넣는다")


func test_replay_keeps_growth() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, true, 5)
	sim.apply_growth({"김도현": 20})
	sim.step_ticks(30)
	var r := Replay.begin(DEV_SCENARIO_PATH, sim.issued, 30, 5, "", "", sim.growth)
	while not r.step(50):
		pass
	assert_eq(r.sim.units.get_crew(0).leader.grade, "고참", "다시 하기에도 같은 성장")
