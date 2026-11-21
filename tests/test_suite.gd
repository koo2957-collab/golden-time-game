class_name TestSuite
extends RefCounted
## 테스트 파일의 기반 클래스. test_로 시작하는 메서드가 각각 하나의 테스트이다.

const BUILDING_PATH := "res://data/buildings/house_2f.json"
const ROSTER_PATH := "res://data/units/test_roster.json"
const UNIT_STATS_PATH := "res://data/units/firefighter.json"
const DEV_SCENARIO_PATH := "res://data/scenarios/dev_house_fire.json"

var failures: PackedStringArray = []


func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func assert_eq(actual: Variant, expected: Variant, msg: String) -> void:
	if actual != expected:
		failures.append("%s (결과: %s, 기대: %s)" % [msg, actual, expected])


func make_sim() -> SimWorld:
	return open_all_doors(SimWorld.create(BUILDING_PATH, ROSTER_PATH, UNIT_STATS_PATH))


## 수관 연장을 지시한 조를 펌프차 후면(수관 시작 칸)에 세우고 호스를 다 꺼낼 때까지 돌린다.
## 2026-11-21부터 수관은 서 있는 자리에 한 번에 생기지 않는다 — 차 후면으로 가서 꺼내고(준비 시간 동안 서 있다) 깔면서 간다.
## back: 끝나면 조를 원래 자리로 되돌려 거기까지 호스가 깔린 상태로 만든다 ('서 있는 자리까지 깔린 호스'가 필요한 테스트용).
## 방수를 지시해 둔 조는 back = false로 — 꺼낸 뒤 스스로 방수 위치로 간다
static func fetch_hose(sim: SimWorld, crew_id: int, back := true) -> HoseLine:
	fetch_hoses(sim, [crew_id], back)
	return sim.water.hose_of_crew(crew_id)


## 여러 조가 같이 호스를 꺼낸다 (fetch_hose와 같다 — 걸리는 시간은 한 번의 준비 시간)
static func fetch_hoses(sim: SimWorld, crew_ids: Array, back := true) -> void:
	var was: Dictionary = {}
	var waiting: Array[HoseLine] = []
	for id: int in crew_ids:
		var h := sim.water.hose_of_crew(id)
		var c := sim.units.get_crew(id)
		if h == null or c == null or h.outlet >= 0:
			continue
		waiting.append(h)
		for ff in c.members():
			was[ff] = [ff.pos, ff.level]
			if h.to_outlet:
				var s := h.points[0]
				ff.pos = Vector2(s.x + 0.5, s.y + 0.5)
				ff.prev_pos = ff.pos
				ff.level = s.z
				ff.prev_level = s.z
				ff.path.clear()
	for i in 1200:
		var done := true
		for h in waiting:
			if h.to_outlet or h.fetch_until >= 0:
				done = false
		if done:
			break
		sim.step_ticks(1)
	if back and not waiting.is_empty():
		for ff: Firefighter in was:
			ff.pos = was[ff][0]
			ff.prev_pos = ff.pos
			ff.level = was[ff][1]
			ff.prev_level = ff.level
			ff.path.clear()
		sim.step_ticks(1)


## 문 규칙과 상관없는 테스트용: 모든 문을 열고 잠금을 푼다
static func open_all_doors(sim: SimWorld) -> SimWorld:
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.DOOR:
			o.is_open = true
			o.locked = false
	sim.doors.sync_blocking()
	return sim
