class_name PlayHistory
extends RefCounted
## 개인 성장 기록과 익명 집계 (SOP 113-3.1.6: 평가는 지도·개선 용도로만, 직원 간 순위 경쟁 없음).
## 결과 파일(user://reports/*.json, Evaluator.save)을 읽어 내 기록을 보여 주고,
## 이름·순위 없이 시나리오별 통계만 묶어 내보낸다 (교관이 모아 훈련 계획에 쓴다).

const EXPORT_DIR := "user://export"
const GRADES := ["S", "A", "B", "C", "D"]


## 결과 목록 (오래된 것부터). 각 항목: {file, saved_at, scenario_id, title, mode, difficulty, grade, points, axes{id: score}, weak[]}
static func entries(dir := Evaluator.REPORT_DIR) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f: String in files:
		if not f.ends_with(".json"):
			continue
		var r: Variant = JsonData.load_file(dir + "/" + f)
		if not r is Dictionary or not r.has("grade"):
			continue
		var axes := {}
		for a: Dictionary in r.get("axes", []):
			if a.get("applicable", false):
				axes[str(a.id)] = float(a.score)
		var weak: Array = []
		for w: Dictionary in r.get("weaknesses", []):
			weak.append("%s (SOP %s)" % [w.get("title", ""), w.get("sop", "")])
		out.append({
			"file": f, "saved_at": str(r.get("saved_at", f.get_basename().right(15))),
			"scenario_id": str(r.get("scenario_id", "")), "title": str(r.get("scenario_title", "")),
			"mode": str(r.get("mode", "")), "difficulty": str(r.get("difficulty", "")),
			"grade": str(r.grade), "points": float(r.get("points", 0.0)), "axes": axes, "weak": weak,
		})
	return out


## 축별 성장: 처음 n판 평균 → 최근 n판 평균 {축 id: [처음, 최근]}
static func growth(list: Array[Dictionary], n := 3) -> Dictionary:
	var out := {}
	if list.is_empty():
		return out
	var first := list.slice(0, n)
	var last := list.slice(maxi(0, list.size() - n))
	for e in list:
		for id: String in e.axes:
			out[id] = [_avg(first, id), _avg(last, id)]
	return out


## 익명 집계: 시나리오별 판 수·등급 분포·축 평균·자주 나온 고칠 점. 이름·날짜별 개인 기록은 넣지 않는다
static func aggregate(list: Array[Dictionary]) -> Dictionary:
	var by: Dictionary = {}
	for e in list:
		var id: String = e.scenario_id
		if not by.has(id):
			var grades := {}
			for g in GRADES:
				grades[g] = 0
			by[id] = {"title": e.title, "plays": 0, "grades": grades, "axes": {}, "weak": {}, "points_sum": 0.0}
		var s: Dictionary = by[id]
		s.plays += 1
		s.points_sum += e.points
		s.grades[e.grade] = int(s.grades.get(e.grade, 0)) + 1
		for a: String in e.axes:
			var acc: Array = s.axes.get(a, [0.0, 0])
			s.axes[a] = [acc[0] + e.axes[a], acc[1] + 1]
		for w: String in e.weak:
			s.weak[w] = int(s.weak.get(w, 0)) + 1
	var scenarios: Array = []
	for id: String in by:
		var s: Dictionary = by[id]
		var axes := {}
		for a: String in s.axes:
			axes[a] = snappedf(s.axes[a][0] / s.axes[a][1], 0.01)
		var weak: Array = s.weak.keys()
		weak.sort_custom(func(x: String, y: String) -> bool: return s.weak[x] > s.weak[y])
		scenarios.append({
			"scenario_id": id, "title": s.title, "plays": s.plays, "grades": s.grades,
			"avg_points": snappedf(s.points_sum / s.plays, 0.1), "avg_axes": axes,
			"common_weaknesses": weak.slice(0, 3).map(func(w: String) -> String: return "%s — %d회" % [w, s.weak[w]]),
		})
	return {
		"note": "익명 집계 (SOP 113-3.1.6: 지도·개선 용도로만, 직원 간 순위 비교 금지). 이름·개인별 기록 없음",
		"rules_basis": "2025 재난현장표준작전절차",
		"scenarios": scenarios,
	}


## 익명 집계를 JSON과 CSV로 내보내고 JSON 경로를 돌려준다
static func export_aggregate(list: Array[Dictionary], dir := EXPORT_DIR) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var agg := aggregate(list)
	var stamp := Time.get_date_string_from_system().replace("-", "")
	var path := "%s/aggregate_%s.json" % [dir, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(agg, "  "))
	f.close()
	var csv := FileAccess.open("%s/aggregate_%s.csv" % [dir, stamp], FileAccess.WRITE)
	if csv:
		csv.store_line("scenario_id,title,plays,S,A,B,C,D,avg_points")
		for s: Dictionary in agg.scenarios:
			csv.store_line("%s,\"%s\",%d,%d,%d,%d,%d,%d,%.1f" % [s.scenario_id, s.title, s.plays,
				s.grades.S, s.grades.A, s.grades.B, s.grades.C, s.grades.D, s.avg_points])
	return path


static func _avg(list: Array, id: String) -> float:
	var sum := 0.0
	var n := 0
	for e: Dictionary in list:
		if e.axes.has(id):
			sum += e.axes[id]
			n += 1
	return sum / n if n > 0 else -1.0
