class_name InstructorSettings
extends RefCounted
## 교관 설정 (user://instructor.json). 교관이 시작 화면의 '교관 설정'에서 바꾼다.
##   weekly: 이번 주 훈련 시나리오 {scenario: id, note}
##   params: 수치 덮어쓰기 {표 이름: {키: 값}} — 표는 TABLES (화재 위험·구급·대원 안전)
##   defaults: 시작 화면 기본값 {mode, difficulty}
## 실제 게임(world)에서만 켠다 (active). 자동 테스트는 늘 기본 수치로 돈다.

const PATH := "user://instructor.json"
## 표 이름 -> [화면 이름, 기본 수치 파일]
const TABLES := {
	"hazard": ["화재 위험 (인접 건물·가스·붕괴·재발화)", "res://data/fire/hazard_params.json"],
	"ems": ["구급 (처치·이송)", "res://data/units/ems_params.json"],
	"safety": ["대원 안전 (긴급탈출·안전담당)", "res://data/command/safety_params.json"],
}

## true면 SimWorld가 params 덮어쓰기를 쓴다 (게임 화면에서만 켠다)
static var active := false


static func load_settings() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var data: Variant = JsonData.load_file(PATH)
	return data if data is Dictionary else {}


static func save_settings(data: Dictionary) -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	return true


## 기본 수치 표에 교관 덮어쓰기를 적용한 사본 (active가 아니면 그대로)
static func apply(table: String, data: Dictionary) -> Dictionary:
	if not active:
		return data
	var over: Dictionary = load_settings().get("params", {}).get(table, {})
	if over.is_empty():
		return data
	var out := data.duplicate(true)
	for key: String in over:
		if out.has(key) and out[key] is Dictionary:
			out[key]["value"] = float(over[key])
	return out


## 기본값과 다른 수치 목록 ["표.키=값"] (결과 파일에 남긴다)
static func changed_params() -> Array[String]:
	var out: Array[String] = []
	if not active:
		return out
	var params: Dictionary = load_settings().get("params", {})
	for table: String in params:
		for key: String in params[table]:
			out.append("%s.%s=%s" % [table, key, params[table][key]])
	return out


static func weekly() -> Dictionary:
	return load_settings().get("weekly", {})
