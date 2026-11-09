class_name Campaign
extends RefCounted
## 캠페인 뼈대 (data/campaign/campaign.json). 장마다 시나리오를 묶고, 앞 장을 min_grade 이상으로
## 끝내면 다음 장이 열린다. 진행은 내 기록(결과 파일)의 최고 등급으로 계산한다.

const PATH := "res://data/campaign/campaign.json"
## 좋은 등급부터
const GRADE_ORDER := ["S", "A", "B", "C", "D"]

enum Status { DONE, OPEN, LOCKED, SOON }
const STATUS_NAMES := {Status.DONE: "완료", Status.OPEN: "도전 가능", Status.LOCKED: "잠김", Status.SOON: "준비 중"}


static func chapters() -> Array:
	var data: Variant = JsonData.load_file(PATH)
	return data.get("chapters", []) if data is Dictionary else []


## 시나리오 id -> 최고 등급
static func best_grades(list: Array[Dictionary]) -> Dictionary:
	var best := {}
	for e in list:
		if e.get("incomplete", false):
			continue  # 미완료 판은 진행에 넣지 않는다 (P11-1)
		var id: String = e.scenario_id
		if not best.has(id) or GRADE_ORDER.find(e.grade) < GRADE_ORDER.find(best[id]):
			best[id] = e.grade
	return best


static func passed(grade: String, min_grade: String) -> bool:
	return grade != "" and GRADE_ORDER.find(grade) <= GRADE_ORDER.find(min_grade)


## 장별 진행 [{chapter, status, grades{시나리오 id: 최고 등급 또는 ""}}]
static func progress(list: Array[Dictionary]) -> Array[Dictionary]:
	var best := best_grades(list)
	var out: Array[Dictionary] = []
	var prev_done := true
	for ch: Dictionary in chapters():
		var ids: Array = ch.get("scenarios", [])
		var grades := {}
		var all_passed := not ids.is_empty()
		for id in ids:
			grades[str(id)] = str(best.get(str(id), ""))
			if not passed(grades[str(id)], str(ch.get("min_grade", "C"))):
				all_passed = false
		var status := Status.LOCKED
		if ids.is_empty():
			status = Status.SOON
		elif all_passed:
			status = Status.DONE
		elif prev_done:
			status = Status.OPEN
		out.append({"chapter": ch, "status": status, "grades": grades})
		prev_done = status == Status.DONE
	return out


## 캠페인 순서에서 이 시나리오 다음 시나리오 id (없으면 "") — 디브리핑 '다음 스테이지' (기획안 8-4, P11-1)
static func next_id(current: String) -> String:
	var ids: Array[String] = []
	for ch: Dictionary in chapters():
		for id in ch.get("scenarios", []):
			ids.append(str(id))
	var i := ids.find(current)
	return ids[i + 1] if i >= 0 and i + 1 < ids.size() else ""


## 다음 시나리오 파일 경로 (없거나 오류가 있으면 "")
static func next_path(current: String) -> String:
	var id := next_id(current)
	if id == "":
		return ""
	for s: Dictionary in ScenarioLoader.list():
		if str(s.id) == id and s.errors.is_empty():
			return str(s.path)
	return ""
