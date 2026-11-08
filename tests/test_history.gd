extends TestSuite
## M7c-2: 내 기록·익명 집계 (SOP 113-3.1.6), 교관 설정 수치 덮어쓰기

const DIR := "user://_test_reports"
const EXPORT := "user://_test_export"


func _write(name: String, scenario: String, grade: String, points: float, safety: float, weak_title: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var r := {
		"scenario_id": scenario, "scenario_title": scenario + " 제목", "mode": "평가", "difficulty": "입문",
		"grade": grade, "points": points, "saved_at": name,
		"axes": [{"id": "safety", "applicable": true, "score": safety}, {"id": "rescue", "applicable": false, "score": 0.0}],
		"weaknesses": [{"title": weak_title, "sop": "109"}],
	}
	var f := FileAccess.open("%s/%s.json" % [DIR, name], FileAccess.WRITE)
	f.store_string(JSON.stringify(r))


func _clean() -> void:
	for d in [DIR, EXPORT]:
		if DirAccess.dir_exists_absolute(d):
			for f in DirAccess.get_files_at(d):
				DirAccess.remove_absolute(d + "/" + f)


func test_entries_growth_aggregate() -> void:
	_clean()
	_write("a1", "s1", "C", 62.0, 0.4, "긴급탈출")
	_write("a2", "s1", "B", 72.0, 0.6, "긴급탈출")
	_write("a3", "s2", "A", 85.0, 0.9, "RIT")
	var list := PlayHistory.entries(DIR)
	assert_eq(list.size(), 3, "결과 3판")
	assert_eq(str(list[0].saved_at), "a1", "오래된 것부터")
	assert_true(not list[0].axes.has("rescue"), "해당 없는 축은 빼고")
	var g := PlayHistory.growth(list, 1)
	assert_eq(g.safety, [0.4, 0.9], "처음 → 최근 성장")
	var agg := PlayHistory.aggregate(list)
	assert_eq(agg.scenarios.size(), 2, "시나리오별 집계")
	var s1: Dictionary = agg.scenarios.filter(func(s: Dictionary) -> bool: return s.scenario_id == "s1")[0]
	assert_eq(s1.plays, 2, "판 수")
	assert_eq(s1.grades.B, 1, "등급 분포")
	assert_eq(s1.avg_points, 67.0, "평균 점수")
	assert_true(str(s1.common_weaknesses[0]).contains("2회"), "자주 나온 고칠 점")
	var text := JSON.stringify(agg)
	assert_true(not text.contains("a1") and not text.contains("saved_at"), "개인별 기록(날짜) 없음")
	var path := PlayHistory.export_aggregate(list, EXPORT)
	assert_true(FileAccess.file_exists(path), "집계 JSON 내보냄")
	assert_true(FileAccess.file_exists(path.replace(".json", ".csv")), "CSV도 내보냄")
	_clean()


func test_history_text() -> void:
	var t := HistoryUi.text_for([] as Array[Dictionary])
	assert_true(t.contains("아직"), "기록 없음 안내")


func test_instructor_overrides_only_when_active() -> void:
	var data: Dictionary = JsonData.load_file("res://data/units/ems_params.json")
	var had := FileAccess.file_exists(InstructorSettings.PATH)
	var backup: Dictionary = InstructorSettings.load_settings()
	InstructorSettings.save_settings({"params": {"ems": {"transport_s": 300.0}}})
	InstructorSettings.active = false
	assert_eq(float(InstructorSettings.apply("ems", data).transport_s.value), 600.0, "테스트·기본 실행은 기본 수치")
	InstructorSettings.active = true
	var applied := InstructorSettings.apply("ems", data)
	assert_eq(float(applied.transport_s.value), 300.0, "게임에서는 교관 수치")
	assert_eq(float(data.transport_s.value), 600.0, "원본 표는 그대로")
	assert_eq(InstructorSettings.changed_params(), ["ems.transport_s=300.0"] as Array[String], "바뀐 수치 기록")
	var sim := make_sim()
	assert_true(sim.ems != null, "덮어쓴 표로도 시뮬레이션 생성")
	InstructorSettings.active = false
	if had:
		InstructorSettings.save_settings(backup)
	else:
		DirAccess.remove_absolute(InstructorSettings.PATH)
