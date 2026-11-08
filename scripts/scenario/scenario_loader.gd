class_name ScenarioLoader
extends RefCounted
## 시나리오 목록과 검증.
##   목록: res://data/scenarios/ (기본 제공) + user://scenarios/ (직접 추가). meta(SOP·난이도·역할·예상 시간·요약)를 읽는다
##   검증: 필수 항목, 파일 경로, 좌표가 도면 안·올바른 칸인지, 방·문·차종·출동대·규칙 id. 문제는 한글 문장으로 돌려준다

const DIRS := ["res://data/scenarios", "user://scenarios"]


## 시나리오 목록 [{path, id, title, meta, objectives, source, errors}]. meta.order, 제목 순
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dir: String in DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				out.append(info("%s/%s" % [dir, f]))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := float(a.meta.get("order", 99))
		var ob := float(b.meta.get("order", 99))
		return oa < ob or (oa == ob and str(a.title) < str(b.title)))
	return out


static func info(path: String) -> Dictionary:
	var data: Variant = JsonData.load_file(path)
	var d: Dictionary = data if data is Dictionary else {}
	return {
		"path": path,
		"id": str(d.get("id", path.get_file().get_basename())),
		"title": str(d.get("title", path.get_file())),
		"meta": d.get("meta", {}),
		"objectives": d.get("evaluation", {}).get("objectives", []),
		"source": "기본" if path.begins_with("res://") else "추가",
		"errors": validate(path),
	}


## 문제 목록 (없으면 빈 배열)
static func validate(path: String) -> PackedStringArray:
	var e: PackedStringArray = []
	if not FileAccess.file_exists(path):
		e.append("파일이 없습니다: %s" % path)
		return e
	var data: Variant = JsonData.load_file(path)
	if not data is Dictionary:
		e.append("JSON 형식이 올바르지 않습니다 (쉼표·따옴표·괄호를 확인하세요).")
		return e
	var d: Dictionary = data
	for key in ["id", "title", "building", "roster", "dispatch", "commander", "fire"]:
		if not d.has(key):
			e.append("필수 항목 '%s'가 없습니다." % key)
	if not e.is_empty():
		return e
	var b := BuildingData.from_file(str(d.building))
	if b == null:
		e.append("건물 도면을 불러올 수 없습니다: %s" % d.building)
		return e
	var room_ids := {}
	for level in b.levels():
		for r in b.rooms(level):
			room_ids[str(r.id)] = level
	var vehicle_stats: Dictionary = JsonData.load_file(SimWorld.VEHICLES_PATH)
	for type: String in d.get("vehicles", {}):
		vehicle_stats[type] = vehicle_stats.get(type, {})
	# 편성
	var roster: Variant = JsonData.load_file(str(d.roster))
	if not roster is Dictionary or roster.get("squads", []).is_empty():
		e.append("출동대 편성을 불러올 수 없거나 출동대가 없습니다: %s" % d.roster)
	else:
		for s: Dictionary in roster.squads:
			_check_squad(e, b, s, vehicle_stats, true)
	if d.has("tutorial"):
		var t: Variant = JsonData.load_file(str(d.tutorial))
		if not t is Dictionary or not t.get("steps", null) is Array:
			e.append("튜토리얼 단계 파일을 불러올 수 없습니다: %s" % d.tutorial)
	var reinf := {}
	if d.has("reinforcements"):
		var r: Variant = JsonData.load_file(str(d.reinforcements))
		if not r is Dictionary:
			e.append("후착대 편성을 불러올 수 없습니다: %s" % d.reinforcements)
		else:
			for s: Dictionary in r.get("squads", []):
				reinf[str(s.get("id", ""))] = true
				_check_squad(e, b, s, vehicle_stats, false)
	for a: Dictionary in d.get("arrivals", []):
		if not reinf.has(str(a.get("squad", ""))):
			e.append("도착표의 출동대 '%s'가 후착대 편성에 없습니다." % a.get("squad", ""))
	for level_name: String in d.get("support", {}):
		var entry: Variant = d.support[level_name]
		if entry is Dictionary:
			for k in entry.get("squads", []):
				if not reinf.has(str(k)):
					e.append("지원 요청 '%s'의 출동대 '%s'가 후착대 편성에 없습니다." % [level_name, k])
	# 지휘관·화재·문·요구조자
	var spawn: Array = d.commander.get("spawn", [])
	if spawn.size() < 2 or not b.is_walkable(int(d.commander.get("level", 1)), int(spawn[0]), int(spawn[1])):
		e.append("현장지휘관 위치(commander.spawn)가 걸을 수 있는 칸이 아닙니다.")
	var ign: Array = d.fire.get("ignitions", [])
	if ign.is_empty():
		e.append("발화 지점(fire.ignitions)이 없습니다.")
	for i: Dictionary in ign:
		var c: Array = i.get("cell", [])
		var lv := int(i.get("level", 1))
		if c.size() < 2 or not b.has_level(lv) or b.room_at(lv, int(c[0]), int(c[1])).is_empty():
			e.append("발화 지점 %s(%d층)이 방 안이 아닙니다." % [c, lv])
	for key in ["doors_locked", "doors_closed", "doors_open"]:
		for c: Array in d.fire.get(key, []):
			var t := b.cell(int(c[2]) if c.size() > 2 else 1, int(c[0]), int(c[1]))
			if t != BuildingData.Cell.DOOR and t != BuildingData.Cell.WINDOW:
				e.append("fire.%s의 %s는 문·창이 아닙니다." % [key, c])
	for v: Dictionary in d.get("victims", []):
		var rooms: Array = v.get("rooms", [v.get("room", "")]) if not v.has("cell") else []
		for r in rooms:
			if not room_ids.has(str(r)):
				e.append("요구조자 '%s'의 방 '%s'가 도면에 없습니다." % [v.get("name", ""), r])
	# 현장 정보
	var site: Dictionary = d.get("site", {})
	for f: Dictionary in site.get("faces", []):
		if not b.faces.has(str(f.get("face", ""))):
			e.append("면 정보의 면 '%s'가 도면에 없습니다 (A·B·C·D)." % f.get("face", ""))
	for r in site.get("lights", []):
		if not room_ids.has(str(r)):
			e.append("실내등 방 '%s'가 도면에 없습니다." % r)
	for s: Dictionary in site.get("shoes", []):
		var c: Array = s.get("door", [0, 0, 1])
		if b.cell(int(c[2]), int(c[0]), int(c[1])) != BuildingData.Cell.DOOR:
			e.append("신발 단서의 문 %s가 문이 아닙니다." % [c])
	for w: Dictionary in site.get("witnesses", []):
		var p: Array = w.get("pos", [])
		if p.size() < 2 or not b.is_walkable(b.levels()[0], int(p[0]), int(p[1])):
			e.append("관계인 '%s'의 위치가 걸을 수 있는 칸이 아닙니다." % w.get("name", ""))
		for q: String in w.get("statements", {}):
			if not SiteSurvey.QUESTIONS.has(q):
				e.append("관계인 '%s'의 질문 '%s'는 없는 질문입니다 (victims·origin·hazards·doors)." % [w.get("name", ""), q])
			for r in w.statements[q].get("rooms", []):
				if not room_ids.has(str(r)):
					e.append("진술의 방 '%s'가 도면에 없습니다." % r)
	for lane: Dictionary in d.get("staging", {}).get("lanes", []):
		if int(lane.get("y", -1)) < 0 or int(lane.get("y", -1)) >= b.height or float(lane.get("x_min", 0)) >= b.width:
			e.append("대기 장소 차로 %s가 도면 밖입니다." % lane)
	# 평가
	var ev: Dictionary = d.get("evaluation", {})
	if not ev.is_empty():
		var rules: Variant = JsonData.load_file(Evaluator.RULES_PATH)
		var ids := {}
		if rules is Dictionary:
			for r: Dictionary in rules.get("rules", []):
				ids[str(r.id)] = true
		for id in ev.get("rules", []):
			if not ids.has(str(id)):
				e.append("평가 규칙 '%s'가 data/sop/rules.json에 없습니다." % id)
		if float(ev.get("time_limit_s", 1)) <= 0.0:
			e.append("제한 시간(evaluation.time_limit_s)은 0보다 커야 합니다.")
	return e


static func _check_squad(e: PackedStringArray, b: BuildingData, s: Dictionary, vehicle_stats: Dictionary, need_spawn: bool) -> void:
	var name := str(s.get("name", s.get("id", "?")))
	if s.get("crews", []).is_empty():
		e.append("출동대 '%s'에 조가 없습니다." % name)
	for v: Dictionary in s.get("vehicles", []):
		if not vehicle_stats.has(str(v.get("type", ""))):
			e.append("출동대 '%s'의 차종 '%s'가 차량 제원에 없습니다." % [name, v.get("type", "")])
		if need_spawn:
			var p: Array = v.get("spawn", [])
			if p.size() < 2 or not b.in_bounds(int(p[0]), int(p[1])):
				e.append("출동대 '%s'의 차량 위치가 도면 밖입니다." % name)
	if need_spawn:
		for c: Dictionary in s.get("crews", []):
			var p: Array = c.get("spawn", [])
			if p.size() < 2 or not b.is_walkable(int(c.get("level", 1)), int(p[0]), int(p[1])):
				e.append("출동대 '%s'의 조 위치 %s가 걸을 수 있는 칸이 아닙니다." % [name, p])
