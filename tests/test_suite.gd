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


## 문 규칙과 상관없는 테스트용: 모든 문을 열고 잠금을 푼다
static func open_all_doors(sim: SimWorld) -> SimWorld:
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.DOOR:
			o.is_open = true
			o.locked = false
	sim.doors.sync_blocking()
	return sim
