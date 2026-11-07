class_name SiteSurvey
extends RefCounted
## 현장 정보 수집과 현장지휘소 판정.
##   360° 둘러보기 (SOP 101-2.2, 102-2.2): 지휘관이 건물 면 앞에 서야 그 면을 확인한다. 면에 숨은 정보(위험 요소)가 열린다
##   관계인 진술 (101-2.2②, 202-1.2, 2.1): 가까이 가서 질문하면 질문마다 지휘관이 묶였다가 답을 듣는다
##   물증 (202-2.3.1): 확인한 면의 창으로 실내등 불빛, 열린 현관의 신발 수
##   현장지휘소 (104-1.3): 오래 머문 곳을 관찰(보이는 면)·안전(SOP 205-1.3 위험반경)·동선(차도)으로 판정
## 확인한 정보는 log에 시간순으로 쌓인다 (현장 정보 창, 디브리핑).

const QUESTIONS := {
	"victims": "안에 사람이 있습니까?",
	"origin": "불은 어디서 시작됐습니까?",
	"hazards": "가스통 같은 위험물이 있습니까?",
	"doors": "출입문은 잠겨 있습니까?",
}
const FACE_DIRS := ["south", "west", "north", "east"]

var building: BuildingData
var fire: FireSim
var units: UnitSystem
var pathfinder: Pathfinder
var resources: ResourceSystem
var commander: Firefighter
var events: SimEventLog

## 확인한 면 key -> 틱
var faces_seen: Dictionary = {}
var witnesses: Array[Witness] = []
## 진술로 구조대상자 가능성이 알려진 방 id -> 관계인 이름
var reported_rooms: Dictionary = {}
## 확인한 정보 [{tick, kind, source, text}]
var log: Array[Dictionary] = []
## 지금 위치의 현장지휘소 판정 {faces, observe, safety, distance_m, route}
var post: Dictionary = {}
## 30초 이상 머문 곳의 판정 기록 (평가용)
var post_log: Array[Dictionary] = []
## 지휘 형태 기록: 고정(머묾)·이동 시간 (초)
var fixed_s := 0.0
var moving_s := 0.0

var _face_view: float
var _min_tan: float
var _ask_range: float
var _ask_s: float
var _clue_range: float
var _post_s: float
var _floor_h: float
var _danger_ratio: float
var _caution_ratio: float
var _rect := Rect2()
var _faces_info: Array = []  # {face, text, hazard}
var _found_hazards: Array[String] = []
var _lights: Array[String] = []  # 실내등이 켜진 방 id
var _lights_found: Dictionary = {}
var _shoes: Array = []  # {door, text}
var _shoes_found: Dictionary = {}
var _ask: Dictionary = {}  # {witness, questions, remain}
var _still := 0.0
var _post_logged := false


func _init(p_fire: FireSim, p_units: UnitSystem, p_pathfinder: Pathfinder, p_resources: ResourceSystem, p_commander: Firefighter, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	building = p_fire.building
	units = p_units
	pathfinder = p_pathfinder
	resources = p_resources
	commander = p_commander
	events = p_events
	var cell_m := building.cell_size_m
	_face_view = params.value("face_view_m") / cell_m
	_min_tan = tan(deg_to_rad(params.value("face_min_angle_deg")))
	_ask_range = params.value("ask_range_m") / cell_m
	_ask_s = params.value("ask_s")
	_clue_range = params.value("clue_range_m") / cell_m
	_post_s = params.value("post_stationary_s")
	_floor_h = params.value("floor_height_m")
	_danger_ratio = params.value("danger_ratio")
	_caution_ratio = params.value("caution_ratio")
	_rect = Rect2(building.footprint(building.levels()[0]))


## 시나리오 site: faces(면 정보), lights(실내등), shoes(현관 신발), witnesses(관계인)
func apply_scenario(data: Dictionary) -> void:
	var site: Dictionary = data.get("site", {})
	_faces_info = site.get("faces", [])
	for r in site.get("lights", []):
		_lights.append(str(r))
	_shoes = site.get("shoes", [])
	var list: Array = site.get("witnesses", [])
	for i in list.size():
		witnesses.append(Witness.from_dict(i, list[i]))


# --- 상태 ---

func face_seen(face: String) -> bool:
	return faces_seen.has(face)


## 건물 면 key 목록 (A, B, C, D)
func face_keys() -> Array[String]:
	var out: Array[String] = []
	for key: String in ["A", "B", "C", "D"]:
		if building.faces.has(key):
			out.append(key)
	return out


## p(셀 좌표, 1층 바깥)에서 보이는 면: 면 바깥쪽에서 face_view 안, 바라보는 각도가 face_min_angle 이상
func faces_visible_from(p: Vector2) -> Array[String]:
	var out: Array[String] = []
	var r := _rect
	var lat_x := maxf(0.0, maxf(r.position.x - p.x, p.x - r.end.x))
	var lat_y := maxf(0.0, maxf(r.position.y - p.y, p.y - r.end.y))
	for key in face_keys():
		var perp := 0.0
		var lateral := 0.0
		match building.faces[key]:
			"south":
				perp = p.y - r.end.y
				lateral = lat_x
			"north":
				perp = r.position.y - p.y
				lateral = lat_x
			"west":
				perp = r.position.x - p.x
				lateral = lat_y
			"east":
				perp = p.x - r.end.x
				lateral = lat_y
		if perp > 0.0 and perp >= _min_tan * lateral and Vector2(perp, lateral).length() <= _face_view:
			out.append(key)
	return out


## 확인한 위험 요소 (면 정보 + 믿을 만한 진술). 상황보고 ④ 정답에 쓴다
func known_hazards() -> Array[String]:
	return _found_hazards.duplicate()


## 불빛이 보이는 창 (실내등이 켜진 방의 창 중 확인한 면에 있는 것)
func lit_windows() -> Array[Opening]:
	var out: Array[Opening] = []
	for o in fire.openings:
		if o.kind != Opening.Kind.WINDOW:
			continue
		var room := _inside_room(o)
		if room and room.id in _lights and face_seen(face_of_opening(o)):
			out.append(o)
	return out


## 바깥 창·문이 있는 면 key (바깥으로 통하지 않으면 빈 문자열)
func face_of_opening(o: Opening) -> String:
	if o.room_a != Opening.OUTSIDE and o.room_b != Opening.OUTSIDE:
		return ""
	var r := Rect2(building.footprint(o.level))
	var c: Vector2i = o.cells[0]
	var dir := ""
	if c.y == int(r.end.y) - 1:
		dir = "south"
	elif c.y == int(r.position.y):
		dir = "north"
	elif c.x == int(r.position.x):
		dir = "west"
	elif c.x == int(r.end.x) - 1:
		dir = "east"
	for key: String in building.faces:
		if building.faces[key] == dir:
			return key
	return ""


func witness_at(p: Vector2, tick: int, radius := 0.8) -> int:
	for w in witnesses:
		if w.present(tick) and w.pos.distance_to(p) <= radius:
			return w.index
	return -1


func in_ask_range(witness: int) -> bool:
	return witness >= 0 and witness < witnesses.size() and commander.level == building.levels()[0] \
		and commander.pos.distance_to(witnesses[witness].pos) <= _ask_range


## 질문 하나에 걸리는 시간 (초)
func ask_seconds() -> float:
	return _ask_s


## 질문 중이면 {witness, questions, remain}
func asking() -> Dictionary:
	return _ask


# --- 명령 ---

## 지휘관이 건물 둘레를 한 바퀴 돈다 (가까운 모서리부터 시계 방향, 출발한 모서리로 돌아온다)
func walk_around() -> bool:
	if commander.level != building.levels()[0]:
		return false
	var off := 3.0
	var r := _rect.grow(off)
	var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var start := 0
	for i in corners.size():
		if commander.pos.distance_to(corners[i]) < commander.pos.distance_to(corners[start]):
			start = i
	var path: Array[Vector3i] = []
	var from := commander.cell3()
	for k in corners.size() + 1:
		var c := corners[(start + k) % corners.size()]
		var cell := pathfinder.nearest_walkable(from.z, Vector2i(floori(c.x), floori(c.y)))
		if cell == Pathfinder.NO_CELL:
			continue
		var to := Vector3i(cell.x, cell.y, from.z)
		var seg := pathfinder.find_path(from, to)
		if seg.is_empty() and from != to:
			return false
		path.append_array(seg)
		from = to
	if path.is_empty():
		return false
	_cancel_ask(-1)
	commander.set_path(path)
	return true


## 관계인에게 질문 (questions: QUESTIONS key 배열). 가까이 있어야 한다.
func ask(witness: int, questions: Array, tick: int) -> bool:
	if witness < 0 or witness >= witnesses.size() or not witnesses[witness].present(tick):
		return false
	if not in_ask_range(witness):
		events.add(tick, "ask_too_far", {"witness": witnesses[witness].label()})
		return false
	var qs: Array[String] = []
	for q in questions:
		if QUESTIONS.has(str(q)) and witnesses[witness].statements.has(str(q)):
			qs.append(str(q))
	if qs.is_empty():
		return false
	commander.path.clear()
	_ask = {"witness": witness, "questions": qs, "remain": _ask_s}
	return true


# --- 틱 ---

func step(dt: float, tick: int) -> void:
	for w in witnesses:
		if w.arrive_tick > 0 and w.arrive_tick == tick:
			events.add(tick, "witness_arrived", {"witness": w.label()})
	_step_ask(dt, tick)
	var outdoors := building.cell(commander.level, floori(commander.pos.x), floori(commander.pos.y)) in BuildingData.OUTDOOR
	if outdoors and commander.level == building.levels()[0]:
		for key in faces_visible_from(commander.pos):
			if not faces_seen.has(key):
				_see_face(key, tick)
	if tick % 5 == 0:
		_check_shoes(tick)
	_step_post(dt, tick)


func _see_face(key: String, tick: int) -> void:
	faces_seen[key] = tick
	events.add(tick, "face_seen", {"face": key, "count": faces_seen.size(), "total": face_keys().size()})
	_add_log(tick, "둘러보기", "현장지휘관", "%s면 확인" % key)
	for info: Dictionary in _faces_info:
		if str(info.get("face", "")) == key:
			var text := str(info.get("text", ""))
			events.add(tick, "site_info_found", {"face": key, "text": text})
			_add_log(tick, "위험 요소" if info.has("hazard") else "현장 정보", "%s면" % key, text)
			_add_hazard(str(info.get("hazard", "")))
	# 그 면의 창으로 보이는 실내등
	for o in fire.openings:
		if o.kind != Opening.Kind.WINDOW or face_of_opening(o) != key:
			continue
		var room := _inside_room(o)
		if room and room.id in _lights and not _lights_found.has(room.id):
			_lights_found[room.id] = true
			var text := "실내등 켜짐 — %s %s (%s면 창)" % [building.floor_name(room.level), room.name, key]
			events.add(tick, "clue_found", {"text": text})
			_add_log(tick, "물증", "%s면" % key, text)


func _step_ask(dt: float, tick: int) -> void:
	if _ask.is_empty():
		return
	if not commander.path.is_empty():
		_cancel_ask(tick)
		return
	_ask.remain -= dt
	if _ask.remain > SimClock.EPSILON:
		return
	var w := witnesses[_ask.witness]
	var q: String = _ask.questions.pop_front()
	var st: Dictionary = w.statements[q]
	w.asked[q] = tick
	var text := str(st.get("text", ""))
	events.add(tick, "statement", {"witness": w.label(), "question": QUESTIONS[q], "text": text})
	_add_log(tick, "진술", w.label(), "%s → \"%s\"" % [QUESTIONS[q], text])
	for room_id in st.get("rooms", []):
		reported_rooms[str(room_id)] = w.name
	if bool(st.get("reliable", true)):
		_add_hazard(str(st.get("hazard", "")))
	if _ask.questions.is_empty():
		_ask = {}
	else:
		_ask.remain = _ask_s


func _cancel_ask(tick: int) -> void:
	if _ask.is_empty():
		return
	if tick >= 0:
		events.add(tick, "ask_cancelled", {"witness": witnesses[_ask.witness].label()})
	_ask = {}


func _check_shoes(tick: int) -> void:
	for i in _shoes.size():
		if _shoes_found.has(i):
			continue
		var d: Array = _shoes[i].get("door", [0, 0, 1])
		var o := fire.opening_at(Vector3i(int(d[0]), int(d[1]), int(d[2])))
		if o == null or not o.is_open:
			continue
		var at := Vector2(int(d[0]) + 0.5, int(d[1]) + 0.5)
		var near := commander.level == o.level and commander.pos.distance_to(at) <= _clue_range
		for ff in units.firefighters:
			if ff.level == o.level and not ff.incapacitated and ff.pos.distance_to(at) <= _clue_range:
				near = true
		if near:
			_shoes_found[i] = true
			var text := str(_shoes[i].get("text", ""))
			events.add(tick, "clue_found", {"text": text})
			_add_log(tick, "물증", "현관", text)


## 현장지휘소 판정: 머문 지 post_stationary_s가 지나면 기록한다
func _step_post(dt: float, tick: int) -> void:
	if commander.path.is_empty():
		_still += dt
		fixed_s += dt
	else:
		_still = 0.0
		moving_s += dt
		_post_logged = false
	if tick % 10 == 0:
		post = evaluate_post(commander.pos, commander.level)
	if _still >= _post_s and not _post_logged:
		_post_logged = true
		var entry := post.duplicate()
		entry["tick"] = tick
		post_log.append(entry)
		events.add(tick, "command_post", entry)


## 위치 p의 현장지휘소 판정 (104-1.3 ①관찰 ②안전 ③동선)
func evaluate_post(p: Vector2, level: int) -> Dictionary:
	var cell_m := building.cell_size_m
	var indoor := not building.cell(level, floori(p.x), floori(p.y)) in BuildingData.OUTDOOR
	var faces := faces_visible_from(p) if not indoor and level == building.levels()[0] else ([] as Array[String])
	var observe := "나쁨"
	if faces.size() >= 2:
		observe = "좋음"
	elif faces.size() == 1:
		observe = "보통"
	var dx := maxf(0.0, maxf(_rect.position.x - p.x, p.x - _rect.end.x))
	var dy := maxf(0.0, maxf(_rect.position.y - p.y, p.y - _rect.end.y))
	var dist_m := sqrt(dx * dx + dy * dy) * cell_m
	var height_m := building.levels().size() * _floor_h
	var danger_m := fire_floor_level() * _floor_h * _danger_ratio
	var safety := "안전"
	if indoor or dist_m < danger_m:
		safety = "위험"
	elif dist_m < height_m * _caution_ratio:
		safety = "주의"
	var route := "양호"
	if building.cell(level, floori(p.x), floori(p.y)) == BuildingData.Cell.ROAD:
		route = "방해 (차도 위)"
	for r in resources.staging_rects():
		if r.has_point(p):
			route = "방해 (대기 장소)"
	return {
		"faces": "·".join(PackedStringArray(faces)),
		"observe": observe,
		"safety": safety,
		"distance_m": snappedf(dist_m, 0.1),
		"danger_m": danger_m,
		"caution_m": height_m * _caution_ratio,
		"route": route,
	}


## 발화층: 불이 난 구획 중 가장 높은 층 (불이 없으면 1층)
func fire_floor_level() -> int:
	var top := building.levels()[0]
	for c in fire.comps:
		if c.stage != Compartment.Stage.NONE:
			top = maxi(top, c.level)
	return top


# --- 도움 ---

func _inside_room(o: Opening) -> Compartment:
	var i := o.room_a if o.room_a != Opening.OUTSIDE else o.room_b
	return fire.comps[i] if i >= 0 and i < fire.comps.size() else null


func _add_hazard(h: String) -> void:
	if h != "" and not h in _found_hazards:
		_found_hazards.append(h)
		_found_hazards.sort()


func _add_log(tick: int, kind: String, source: String, text: String) -> void:
	log.append({"tick": tick, "kind": kind, "source": source, "text": text})
