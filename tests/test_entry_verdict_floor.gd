extends TestSuite
## 진입 허가 정답 판정 — 지시 창의 층 화재진압(floor_missions)도 진압 임무로 본다 (2026-11-24).
## 전에는 방 단위 전술 임무만 보아, 지시 창으로 보낸 진압 분대가 마른 호스(또는 호스 없이)로 들어가겠다고 해도
## '허가'가 정답이었다. 화재1·SOP: 진압 임무는 물이 찬 수관으로 진입 / 연결송수관 층은 방수구에서 결합(마른 호스 가방이 맞다)

const HOUSE := "res://data/scenarios/dev_squad_house_fire.json"
const APT := "res://data/scenarios/sop213_1_apartment_3f.json"


func _sim(path: String) -> SimWorld:
	var sim := SimWorld.from_scenario(path, false)
	sim.command.strategy = CommandSystem.Strategy.OFFENSIVE
	return sim


## 층 화재진압 + 수관 없음 → 대기 (물이 찬 수관으로 진입)
func test_floor_attack_without_hose_waits() -> void:
	var sim := _sim(HOUSE)
	var c := sim.units.get_crew(0)
	sim.command.floor_missions[c.id] = "attack"
	sim.command.floor_goals[c.id] = 1
	var v := sim.command.entry_verdict(c, sim.clock.tick)
	assert_eq(str(v.verdict), "wait", "층 화재진압인데 수관 없음 → 대기 (%s)" % v.reason)
	assert_true(str(v.reason).contains("수관"), "이유는 수관 (%s)" % v.reason)


## 층 화재진압 + 물이 찬 수관 → 수관 때문에 막지 않는다
func test_floor_attack_with_charged_hose() -> void:
	var sim := _sim(HOUSE)
	var c := sim.units.get_crew(0)
	sim.water.lay_hose(c.id, sim.water._nearest_pump(c.leader.pos), sim.clock.tick)
	var h := fetch_hose(sim, c.id, false)
	assert_true(h != null, "수관이 있다")
	if h == null:
		return
	h.charged = true
	sim.command.floor_missions[c.id] = "attack"
	sim.command.floor_goals[c.id] = 1
	var v := sim.command.entry_verdict(c, sim.clock.tick)
	assert_true(not str(v.reason).contains("수관"), "물이 찬 수관이면 수관 때문에 막지 않는다 (%s · %s)" % [v.verdict, v.reason])


## 층 검색은 수관을 보지 않는다
func test_floor_search_ignores_hose() -> void:
	var sim := _sim(HOUSE)
	var c := sim.units.get_crew(1)
	sim.command.floor_missions[c.id] = "search"
	sim.command.floor_goals[c.id] = 1
	var v := sim.command.entry_verdict(c, sim.clock.tick)
	assert_true(not str(v.reason).contains("수관"), "층 검색은 수관과 상관없다 (%s)" % v.reason)


## 연결송수관을 쓰는 층의 화재진압은 입구에서 수관이 없어도 된다 (그 층 방수구에서 결합)
func test_standpipe_floor_attack() -> void:
	var sim := _sim(APT)
	var c: Crew = null
	for cr in sim.units.crews:
		if sim._default_mission(cr) == "attack" and not cr.leader.aboard:
			c = cr
			break
	assert_true(c != null, "진압 조가 있다")
	if c == null:
		return
	var level := -1
	for lv in sim.building.levels():
		if lv > 1 and sim.building.outlet_on(lv) >= 0:
			level = lv
			break
	assert_true(level > 1, "방수구가 있는 층")
	var pump := sim.water._nearest_pump(c.leader.pos)
	sim.water.fdc_vehicle = pump
	assert_true(sim.water.uses_outlet(level), "그 층은 방수구를 쓴다")
	sim.command.floor_missions[c.id] = "attack"
	sim.command.floor_goals[c.id] = level
	var v := sim.command.entry_verdict(c, sim.clock.tick)
	assert_true(not str(v.reason).contains("수관"), "방수구 층은 입구에서 수관을 요구하지 않는다 (%s · %s)" % [v.verdict, v.reason])
