extends TestSuite
## 지휘관 명령 칸 (G3, 2026-11-14 결정): 보고·지원·안전·구역 네 묶음을 모두 펼쳐 한 번에 누른다.
## 데이터(data/commands.json commander_board)와 실행 코드(world.gd)가 맞는지 본다. 화면은 tests/ui_command_card.gd

const WORLD_SRC := "res://scripts/world.gd"


func test_board_has_four_groups() -> void:
	var groups := CommandCard.load_board()
	var labels: Array = groups.map(func(g: Dictionary) -> String: return str(g.label))
	assert_eq(labels, ["보고", "지원", "안전", "구역"], "네 묶음 순서")
	for g in groups:
		assert_true((g.get("items", []) as Array).size() >= 1, "%s 묶음에 명령이 있다" % g.label)
		for it: Dictionary in g.items:
			assert_true(str(it.get("label", "")) != "" and str(it.get("hint", "")) != "", "%s: 이름과 설명" % it.get("id", "?"))
			assert_true(not it.has("sub") and not it.has("key"), "%s: 2단 메뉴·단축키 없음" % it.id)


func test_board_ids_unique_and_complete() -> void:
	var ids := CommandCard.board_ids()
	var seen := {}
	for id in ids:
		assert_true(not seen.has(id), "명령 id 중복 없음: %s" % id)
		seen[id] = true
	# 예전 2단 메뉴에 있던 지휘관 명령이 모두 한 번에 누르는 단추로 있다 (선제지시만 뺐다)
	for id in ["declare", "update_report", "strategy", "all_clear", "transfer", "end",
			"support_more", "response_1", "org", "rit", "officer", "par", "withdraw_all", "evacuate",
			"zone_safe", "zone_casualty", "zone_line", "zone_post", "zone_forward"]:
		assert_true(seen.has(id), "명령 칸에 %s" % id)
	assert_true(not seen.has("preorder"), "선제지시는 명령 칸에 없다")


func test_every_board_command_is_handled() -> void:
	# 단추마다 world.gd 의 지휘관 명령 처리에 갈래가 있어야 한다 (눌러도 아무 일 없는 단추 방지)
	var src := FileAccess.get_file_as_string(WORLD_SRC)
	var from := src.find("func _commander_command")
	var body := src.substr(from, src.find("\nfunc ", from + 1) - from)
	assert_true(from >= 0 and body.length() > 0, "world.gd 에 지휘관 명령 처리")
	var ids := CommandCard.board_ids()
	for it in CommandCard.load_tools():
		ids.append(str(it.id))
	for id in ids:
		assert_true(body.contains("\"%s\":" % id), "world.gd 가 %s 를 처리한다" % id)


func test_no_commander_card_set() -> void:
	# 지휘관 명령은 명령 카드(Q W E R A S) 세트가 아니다: 아무것도 안 고르면 빈 카드
	assert_true(not CommandCard.load_sets().has("commander"), "commander 세트 없음")
	var card := CommandCard.new()
	assert_eq(card.set_name, "", "처음에는 세트 없음")
	assert_eq(card.slots().filter(func(s: Dictionary) -> bool: return not s.is_empty()).size(), 0, "빈 6칸")
	assert_eq(card.press("Q"), "", "세트 없이 Q → 실행할 것 없음")
	card.set_target("team")
	assert_eq(card.slots().filter(func(s: Dictionary) -> bool: return not s.is_empty()).size(), 6, "팀 6칸")
