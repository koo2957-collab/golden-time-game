class_name ZoneSystem
extends RefCounted
## 구역 지정 (기획안 9-1, P10-2 ⓑ): 지휘관이 외부 지도에 찍는 안전구역·환자 집결지·진입통제선과 구급대 분류소.
##   - 안전구역: 건물 밖 사각형 (칸). 낙하물 위험구역과 겹치면 경고만 한다
##   - 환자 집결지: 안전구역 안 한 점. 구급대가 분류소를 차리면 분류소가 집결지를 대신한다
##   - 진입통제선: 두 점을 잇는 선 (표시·기록용)
## 지휘관 지정은 무전으로 나가고(CommandSystem.order_zone) 전달되면 apply_*로 적용한다.
## 화면 코드를 참조하지 않는다.

const KIND_NAMES := {"safe": "안전구역", "casualty": "환자 집결지", "line": "진입통제선", "triage": "분류소"}

var building: BuildingData
var units: UnitSystem
var falls: FallSystem
var events: SimEventLog

## 안전구역 (칸, 1층 바깥). size가 0이면 없음
var safe := Rect2i()
## 환자 집결지 (칸). x < 0이면 없음
var casualty := Vector2i(-1, -1)
## 진입통제선 두 끝 (칸 좌표). 비어 있으면 없음
var line: Array[Vector2] = []
## 구급대 분류소 (칸). x < 0이면 없음
var triage := Vector2i(-1, -1)
## 분류소를 차리는 중 {crew, cell, start_tick(도착해 설치를 시작한 틱, -1 = 가는 중)}
var triage_setup: Dictionary = {}
## 지휘소·직전대기 장소·설치 작업 (P4-4, 그리기용으로 연결)
var post: CommandPost
## 지정 기록 [{tick, kind, text}] (디브리핑)
var log: Array[Dictionary] = []

## 한 번 클릭으로 정하는 안전구역 한 변 (칸)
var default_cells := 20
var _setup_ticks := 600
var _arrive_cells := 2.0


func _init(p_building: BuildingData, p_units: UnitSystem, p_falls: FallSystem, triage_setup_s: float, safe_default_m: float, p_events: SimEventLog) -> void:
	building = p_building
	units = p_units
	falls = p_falls
	events = p_events
	_setup_ticks = roundi(triage_setup_s / SimClock.TICK_DT)
	default_cells = maxi(2, roundi(safe_default_m / building.cell_size_m))


func has_safe() -> bool:
	return safe.size.x > 0 and safe.size.y > 0


func in_safe(cell: Vector2i) -> bool:
	return has_safe() and safe.has_point(cell)


## 구조자를 옮겨 갈 곳: 분류소 > 환자 집결지 (없으면 (-1, -1))
func destination() -> Vector2i:
	return triage if triage.x >= 0 else casualty


# --- 확인 (무전 보내기 전) ---

## 한 번 클릭한 자리를 가운데로 기본 크기 안전구역 (지도 안으로 맞춘다)
func default_safe(cell: Vector2i) -> Rect2i:
	var r := Rect2i(cell - Vector2i(default_cells, default_cells) / 2, Vector2i(default_cells, default_cells))
	r.position.x = clampi(r.position.x, 0, maxi(0, building.width - r.size.x))
	r.position.y = clampi(r.position.y, 0, maxi(0, building.height - r.size.y))
	return r


## 안전구역으로 쓸 수 없는 이유 ("" = 됨). 건물(벽·바닥) 칸이 하나라도 있으면 안 된다
func safe_reject_reason(r: Rect2i) -> String:
	if r.size.x < 2 or r.size.y < 2:
		return "너무 좁음"
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not building.in_bounds(x, y):
				return "지도 밖"
			if not building.cell(1, x, y) in BuildingData.OUTDOOR:
				return "건물과 겹침 — 안전구역은 건물 밖에"
	return ""


## 외부 안전구역 기본 안내 (SOP 213-2.7.1): 건물에서 발화층 높이의 1/2 이상, 바람이 세면 건물 높이만큼 떨어뜨린다
var guide_m := 0.0
var guide_reason := ""


func set_guide(fire_level: int, top_level: int, wind_mps: float, strong_wind_mps: float, floor_m: float) -> void:
	if wind_mps >= strong_wind_mps:
		guide_m = top_level * floor_m
		guide_reason = "바람 %dm/s — 건물 높이" % roundi(wind_mps)
	else:
		guide_m = fire_level * floor_m * 0.5
		guide_reason = "발화층 높이의 1/2"


## 안내선: 건물 바닥 사각형을 guide_m만큼 넓힌 사각형 (칸)
func guide_rect() -> Rect2:
	var cells := guide_m / building.cell_size_m
	return Rect2(building.footprint(1)).grow(cells)


## 건물에서 안전구역까지 가장 가까운 거리 (m)
func distance_from_building_m(r: Rect2i) -> float:
	var fp := building.footprint(1)
	var dx := maxi(0, maxi(fp.position.x - r.end.x, r.position.x - fp.end.x))
	var dy := maxi(0, maxi(fp.position.y - r.end.y, r.position.y - fp.end.y))
	return Vector2(dx, dy).length() * building.cell_size_m


## 낙하물 위험구역과 겹치거나 건물에 너무 가까우면 경고 문구 ("" = 괜찮음)
func safe_warning(r: Rect2i) -> String:
	if guide_m > 0.0:
		var d := distance_from_building_m(r)
		if d < guide_m:
			return "건물에서 %dm — %s(%dm) 이상 떨어뜨릴 것 (SOP 213-2.7.1)" % [roundi(d), guide_reason, roundi(guide_m)]
	if falls == null:
		return ""
	for z in falls.zones:
		if int(z.level) < 1:
			continue
		var c: Vector2 = z.center
		var nearest := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
		if nearest.distance_to(c) <= float(z.radius):
			return "낙하물 위험구역과 겹침"
	return ""


## 환자 집결지·분류소로 쓸 수 없는 이유 ("" = 됨)
func point_reject_reason(cell: Vector2i) -> String:
	if not has_safe():
		return "안전구역을 먼저 지정하세요"
	if not in_safe(cell):
		return "안전구역 안에만 놓을 수 있음"
	return ""


## "건물 남쪽" — 건물 바닥 사각형을 기준으로 방향
func where_text(p: Vector2) -> String:
	var fp := Rect2(building.footprint(1))
	var c := fp.get_center()
	var d := p - c
	var side := ""
	if absf(d.x) * fp.size.y > absf(d.y) * fp.size.x:
		side = "동쪽" if d.x > 0 else "서쪽"
	else:
		side = "남쪽" if d.y > 0 else "북쪽"
	var nearest := Vector2(clampf(p.x, fp.position.x, fp.end.x), clampf(p.y, fp.position.y, fp.end.y))
	return "건물 %s %dm" % [side, roundi(nearest.distance_to(p) * building.cell_size_m)]


# --- 적용 (무전이 전달된 뒤) ---

func apply_safe(r: Rect2i, tick: int) -> void:
	safe = r
	# 안전구역을 옮기면 밖에 남은 집결지는 무효
	if casualty.x >= 0 and not in_safe(casualty):
		casualty = Vector2i(-1, -1)
	_record(tick, "safe", where_text(Vector2(r.get_center())))


func apply_casualty(cell: Vector2i, tick: int) -> void:
	casualty = cell
	_record(tick, "casualty", where_text(Vector2(cell)))


func apply_line(a: Vector2, b: Vector2, tick: int) -> void:
	line = [a, b]
	_record(tick, "line", where_text((a + b) * 0.5))


## 구급대에게 분류소 설치 지시: 그 자리로 가서 설치 시간이 지나면 분류소가 된다
func order_triage(crew_id: int, cell: Vector2i, pathfinder: Pathfinder, tick: int) -> bool:
	var why := point_reject_reason(cell)
	if why != "":
		events.add(tick, "zone_rejected", {"kind": KIND_NAMES.triage, "reason": why})
		return false
	triage_setup = {"crew": crew_id, "cell": cell, "start_tick": -1}
	units.order_move([crew_id], Vector3i(cell.x, cell.y, 1), pathfinder)
	events.add(tick, "triage_post_order", {"crew": _crew_name(crew_id), "where": where_text(Vector2(cell))})
	return true


func step(tick: int) -> void:
	if triage_setup.is_empty():
		return
	var c := units.get_crew(int(triage_setup.crew))
	if c == null or c.leader.incapacitated:
		triage_setup = {}
		return
	var cell: Vector2i = triage_setup.cell
	if int(triage_setup.start_tick) < 0:
		if c.leader.level == 1 and c.leader.pos.distance_to(Vector2(cell) + Vector2(0.5, 0.5)) <= _arrive_cells and not c.leader.is_moving():
			triage_setup.start_tick = tick
		return
	if tick - int(triage_setup.start_tick) >= _setup_ticks:
		triage = cell
		triage_setup = {}
		_record(tick, "triage", where_text(Vector2(cell)))
		events.add(tick, "triage_post_set", {"crew": _crew_name(c.id), "where": where_text(Vector2(cell))})


## 분류소 설치 진행 (0~1, 설치 중이 아니면 -1) — 진행 막대
func triage_progress(tick: int) -> float:
	if triage_setup.is_empty() or int(triage_setup.start_tick) < 0:
		return -1.0
	return clampf(float(tick - int(triage_setup.start_tick)) / float(maxi(1, _setup_ticks)), 0.0, 1.0)


func _record(tick: int, kind: String, text: String) -> void:
	log.append({"tick": tick, "kind": kind, "text": text})


func _crew_name(crew_id: int) -> String:
	var c := units.get_crew(crew_id)
	if c == null:
		return ""
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]
