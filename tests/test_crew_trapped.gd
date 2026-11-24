extends TestSuite
## 퇴로 차단 — 고립 보고 (2026-11-25): 건물 안의 조가 trapped_report_s 동안 줄곧 열기에 길이 막히면 '퇴로 차단' 을 한 번 보고한다.
## 튜토리얼 자동 진행에서 2층 검색을 마친 구조 분대가 불난 1층 거실을 지나는 길이 막혀 '열기 접근 불가'만 되풀이하다 쓰러졌고,
## 지휘관은 고립된 줄 몰랐다 (SOP 109 대원 고립 — 엄호 방수·사다리·RIT 로 퇴로를 열 수 있게 알린다)

const SCENARIO := "res://data/scenarios/dev_squad_house_fire.json"


func _inside_crew() -> Array:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var c := sim.units.get_crew(1)
	for ff in c.list:
		ff.pos = Vector2(13.5, 16.5)
		ff.prev_pos = ff.pos
		ff.level = 1
		ff.path.clear()
	return [sim, c]


func test_report_after_blocked_long() -> void:
	var s := _inside_crew()
	var sim: SimWorld = s[0]
	var c: Crew = s[1]
	var limit := roundi(30.0 / SimClock.TICK_DT)
	# 막힘이 이어지는 동안 (틱마다 막힘)
	for t in range(0, limit - 10):
		sim.conditions._check_trapped(c, t)
	assert_eq(sim.events.of_type("crew_trapped").size(), 0, "보고 시간 전에는 보고하지 않는다")
	for t in range(limit - 10, limit + 50):
		sim.conditions._check_trapped(c, t)
	var said := sim.events.of_type("crew_trapped")
	assert_eq(said.size(), 1, "한 번 보고")
	if not said.is_empty():
		var text := SimEventLog.describe_text(said[0])
		assert_true(text.contains("퇴로 차단"), "보고 문장: %s" % text)


func test_reset_after_path_opens() -> void:
	var s := _inside_crew()
	var sim: SimWorld = s[0]
	var c: Crew = s[1]
	var limit := roundi(30.0 / SimClock.TICK_DT)
	for t in range(0, limit + 5):
		sim.conditions._check_trapped(c, t)
	assert_eq(sim.events.of_type("crew_trapped").size(), 1, "첫 고립 보고")
	# 길이 한동안 열렸다가(막힘 없음) 다시 오래 막히면 다시 보고한다
	var t0 := limit + 5 + limit
	for t in range(t0, t0 + limit + 5):
		sim.conditions._check_trapped(c, t)
	assert_eq(sim.events.of_type("crew_trapped").size(), 2, "다시 막히면 다시 보고")


func test_outdoor_not_trapped() -> void:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var c := sim.units.get_crew(1)
	for t in range(0, roundi(40.0 / SimClock.TICK_DT)):
		sim.conditions._check_trapped(c, t)
	assert_eq(sim.events.of_type("crew_trapped").size(), 0, "건물 밖이면 고립이 아니다")
