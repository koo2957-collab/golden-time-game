class_name CrewGrowth
extends RefCounted
## 대원 성장 (기획안 6-2, R12): 판을 마칠 때마다 대원(이름 기준)에게 경험치가 쌓여 신임 → 일반 → 숙련 → 고참.
## 단계마다 공기 소모·열 스트레스 배율이 달라진다 (data/units/growth.json). 기록은 user://crew_growth.json.
## 판을 시작할 때 SimWorld.apply_growth로 적용하고, 그 값은 다시 하기에도 그대로 넘긴다 (결정론 유지).

const DATA_PATH := "res://data/units/growth.json"
const SAVE_PATH := "user://crew_growth.json"


static func data() -> Dictionary:
	var d: Variant = JsonData.load_file(DATA_PATH)
	return d if d is Dictionary else {}


## 저장된 경험치 {대원 이름: xp}
static func load_xp(path := SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


static func save_xp(xp: Dictionary, path := SAVE_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(xp, "  "))


## 경험치 → 단계 {name, xp, air, heat}
static func level_of(xp: float) -> Dictionary:
	var levels: Array = data().get("levels", [])
	var out: Dictionary = levels[0] if not levels.is_empty() else {"name": "일반", "air": 1.0, "heat": 1.0}
	for l: Dictionary in levels:
		if xp >= float(l.xp):
			out = l
	return out


## 대원 이름의 경험치 (기록이 없으면 start_xp = 일반)
static func xp_of(xp: Dictionary, name: String) -> float:
	return float(xp.get(name, data().get("start_xp", 3)))


## 판이 끝나면 경험치를 준다. 바뀐 내용을 사람이 읽는 줄로 돌려준다
static func award(sim: SimWorld, report: Dictionary, path := SAVE_PATH) -> Array:
	var xp := load_xp(path)
	var rule: Dictionary = data().get("award", {})
	var rescuers: Array[String] = []
	for e in sim.events.of_type("victim_rescued"):
		rescuers.append(str(e.get("by", "")))
	var good := str(report.get("grade", "D")) in ["S", "A", "B"]
	var lines: Array = []
	for c in sim.units.crews:
		var crew_name := "%s %d조" % [sim.units.squads[c.squad_id].name, c.number]
		for ff in c.members():
			if ff.incapacitated:
				continue
			var gain := float(rule.get("played", 1))
			if crew_name in rescuers:
				gain += float(rule.get("rescued", 1))
			if good:
				gain += float(rule.get("grade_b_or_better", 1))
			var before := xp_of(xp, ff.name)
			var after := before + gain
			xp[ff.name] = after
			var l0 := str(level_of(before).name)
			var l1 := str(level_of(after).name)
			lines.append("%s %s(%s) +%d → 경험치 %d%s" % [crew_name, ff.name, l0, roundi(gain), roundi(after), "  ★ %s 승급" % l1 if l1 != l0 else ""])
	save_xp(xp, path)
	return lines
