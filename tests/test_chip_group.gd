extends TestSuite
## 칩 단추 묶음 (2026-11-27 사용자 결정: 지휘권 선언 양식을 왼쪽 옆 패널 + 칩으로 — 드롭다운 대신 한 번 눌러 고른다)


func test_single_choice() -> void:
	var g := ChipGroup.new().setup(["있음", "없음", "확인 중"])
	var n := [0]
	g.changed.connect(func() -> void: n[0] += 1)
	assert_eq([g.has_choice(), g.selected_text(), g.selected_index()], [false, "", -1], "처음엔 고른 것 없음")
	g.buttons()[1].button_pressed = true
	assert_eq(g.selected_text(), "없음", "누른 칩이 골라진다")
	g.buttons()[2].button_pressed = true
	assert_eq([g.selected_text(), g.buttons()[1].button_pressed], ["확인 중", false], "다른 칩을 누르면 옮겨 간다 (하나만)")
	g.buttons()[2].button_pressed = false
	assert_eq(g.has_choice(), false, "고른 칩을 다시 누르면 풀린다")
	assert_true(n[0] >= 3, "바뀔 때마다 알린다")
	g.select_text("있음")
	assert_eq(g.selected_index(), 0, "글자로 고르기")
	g.free()


func test_multi_choice() -> void:
	var g := ChipGroup.new().setup(["인명검색", "외부 방수", "배연"], true)
	g.buttons()[0].button_pressed = true
	g.buttons()[2].button_pressed = true
	assert_eq(g.picked(), ["인명검색", "배연"] as Array[String], "여럿 고르기")
	assert_eq(g.buttons()[0].text, "✓ 인명검색", "고른 칩 앞에 ✓")
	g.buttons()[0].button_pressed = false
	assert_eq([g.picked(), g.buttons()[0].text], [["배연"] as Array[String], "인명검색"], "풀면 ✓ 도 지운다")
	g.clear()
	assert_eq(g.picked().size(), 0, "모두 풀기")
	g.free()
