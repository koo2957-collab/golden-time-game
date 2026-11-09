extends TestSuite
## M9d: 시나리오 편집기 데이터 (ScenarioDraft)

const BASE := "res://data/scenarios/sop214_1_day_living.json"


func _clean(d: ScenarioDraft) -> void:
	if d and d.path != "" and FileAccess.file_exists(d.path):
		DirAccess.remove_absolute(d.path)


func test_copy_edit_save_validate() -> void:
	var d := ScenarioDraft.from_base(BASE)
	assert_true(d != null and str(d.data.id).begins_with("custom_"), "사본 id")
	assert_true(str(d.data.title).begins_with("(사본)"), "사본 제목")
	d.set_title("교관 훈련 — 2층 방 화재")
	d.set_summary("2층 방2에서 시작하는 화재")
	d.set_dispatch_lines(PackedStringArray(["대상: 2층 단독주택", "", "신고 내용: 2층 창에서 연기"]))
	assert_eq(d.dispatch_lines().size(), 2, "빈 줄은 빼고 저장")
	d.set_random_seed(true)
	assert_eq(d.add_ignition(2, Vector2i(12, 6)), "", "2층 방2 발화점")
	assert_true(d.add_ignition(1, Vector2i(2, 2)) != "", "바깥 칸은 발화점이 될 수 없음")
	assert_eq(d.add_victim(2, Vector2i(14, 17), "학생", 15, ScenarioDraft.MOBILITY[0], false, true), "", "구조대상자 추가")
	assert_true(d.add_victim(2, Vector2i(8, 6), "x", 1, "") != "", "벽 칸은 안 됨")
	assert_eq(d.move_witness(0, Vector2i(4, 25)), "", "관계인 이동")
	var errors := d.save()
	assert_eq(errors, PackedStringArray(), "저장 후 검증 통과 (%s)" % [errors])
	var listed := ScenarioLoader.list().filter(func(s: Dictionary) -> bool: return s.path == d.path)
	assert_eq(listed.size(), 1, "시작 화면 목록에 추가")
	assert_eq(str(listed[0].source), "추가", "사용자 시나리오 표시")
	var sim := SimWorld.from_scenario(d.path)
	assert_true(sim != null and sim.rescue.victims[-1].self_evac, "그대로 실행됨")
	_clean(d)


func test_remove_and_reopen() -> void:
	var d := ScenarioDraft.from_base(BASE)
	var n := d.ignitions().size()
	d.add_ignition(1, Vector2i(25, 17))
	assert_eq(d.ignitions().size(), n + 1, "추가")
	assert_true(d.remove_near(1, Vector2i(26, 17)), "가까운 항목 지우기")
	assert_eq(d.ignitions().size(), n, "지워짐")
	d.save()
	var again := ScenarioDraft.open(d.path)
	assert_eq(str(again.data.id), str(d.data.id), "다시 열기")
	assert_eq(again.path, d.path, "같은 파일에 저장")
	_clean(d)


func test_broken_draft_reports_errors() -> void:
	var d := ScenarioDraft.from_base(BASE)
	d.data.fire.ignitions = []
	d.data.victims = [{"name": "x", "age": 1, "level": 1, "room": "없는방"}]
	var errors := d.save()
	assert_true(not errors.is_empty(), "잘못된 사본은 한글 오류 (%s)" % [errors])
	_clean(d)
