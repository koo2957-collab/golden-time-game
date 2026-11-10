class_name PlanIntel
extends RefCounted
## 도면과 구조 정보 (기획안 9-1 "도면과 미니맵", R8).
##   - 처음에는 도면이 없다. 외벽은 밖에서 보이므로 알고, 건물 안 벽·문·가구는 대원이 본 곳만 안다 ("구조는 직접 밝힌다").
##   - 대원(조)을 관리사무소·방재실로 보내 정해진 시간 머물면 그 동의 평면도를 얻고, 수신반에서 발화층을 확인한다 (SOP 235).
##     그만큼 현장 인력이 빠지므로 언제 보낼지가 판단이다.
##   - 지휘대가 도착하면 상황실에서 도면이 들어온다 (SOP 112) — acquire("상황실")로 받는다 (R13 지휘권 이양).
##   - 도면을 얻으면 미니맵이 열리고, 본 적 없는 방에도 방 단위 임무를 줄 수 있다 (InteriorOrders.plan_known).
##   - 도면과 실제가 다른 곳(발코니 확장·불법 구획·막힌 통로)은 도면에 다르게 그리고, 대원이 실제로 보면 발견으로 기록한다 (디브리핑).
## 건물 데이터: plan_office {name, cell: [x, y], level, dwell_s, note}, plan_diffs [{level, cells: [[x, y]…], plan: "wall"|"open", note}]

const OFFICE_RADIUS := 1.6

var fire: FireSim
var units: UnitSystem
var perception: Perception
var interior: InteriorOrders
var events: SimEventLog

var known := false
var source := ""
var acquired_tick := -1
## 관리사무소·방재실 {name, cell: Vector2i, level, dwell_s}. 비어 있으면 없음 (단독주택 등)
var office: Dictionary = {}
## 도면과 실제가 다른 곳 [{level, cells: Array[Vector2i], plan, note}]
var diffs: Array[Dictionary] = []
## 대원이 실제로 확인한 차이 (diffs index)
var found_diffs: Array[int] = []
## 도면을 얻을 때 수신반으로 확인한 발화층 이름 (없으면 "")
var panel_floors := ""

var _dwell: Dictionary = {}  # 조 id -> 초
var _exterior: Dictionary = {}  # Vector3i -> true (외벽·외부 창·문)
var _plan_override: Dictionary = {}  # Vector3i -> BuildingData.Cell (도면에만 다르게 그린 칸)


func _init(p_fire: FireSim, p_units: UnitSystem, p_perception: Perception, p_interior: InteriorOrders, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	perception = p_perception
	interior = p_interior
	events = p_events
	_find_exterior()


## 건물 JSON의 plan_office·plan_diffs를 읽는다
func apply_building(data: Dictionary) -> void:
	var o: Dictionary = data.get("plan_office", {})
	if o.has("cell"):
		office = {"name": str(o.get("name", "관리사무소(방재실)")), "cell": Vector2i(int(o.cell[0]), int(o.cell[1])),
			"level": int(o.get("level", 1)), "dwell_s": float(o.get("dwell_s", 60.0))}
	for d: Dictionary in data.get("plan_diffs", []):
		var cells: Array[Vector2i] = []
		for c in d.get("cells", []):
			cells.append(Vector2i(int(c[0]), int(c[1])))
		var lv := int(d.get("level", 1))
		var kind := str(d.get("plan", "wall"))
		diffs.append({"level": lv, "cells": cells, "plan": kind, "note": str(d.get("note", ""))})
		for c in cells:
			_plan_override[Vector3i(c.x, c.y, lv)] = BuildingData.Cell.WALL if kind == "wall" else BuildingData.Cell.FLOOR


func step(dt: float, tick: int) -> void:
	if not known and not office.is_empty():
		var at: Vector2 = Vector2(office.cell) + Vector2(0.5, 0.5)
		for c in units.crews:
			var ff := c.leader
			if ff.incapacitated or ff.aboard or ff.level != int(office.level) or ff.pos.distance_to(at) > OFFICE_RADIUS:
				_dwell.erase(c.id)
				continue
			_dwell[c.id] = float(_dwell.get(c.id, 0.0)) + dt
			if float(_dwell[c.id]) >= float(office.dwell_s):
				acquire(str(office.name), tick, "%s %d조" % [units.squads[c.squad_id].name, c.number])
				break
	if perception.enabled:
		for i in diffs.size():
			if i in found_diffs:
				continue
			for cell: Vector2i in diffs[i].cells:
				if perception.is_crew_visible(int(diffs[i].level), cell.x, cell.y):
					found_diffs.append(i)
					events.add(tick, "plan_diff_found", {"note": diffs[i].note, "floor": fire.building.floor_name(int(diffs[i].level)),
						"known": known})
					break


## 도면을 얻는다. 방재실이면 수신반으로 발화층도 확인한다 (SOP 235). by: 보고하는 쪽 (조 이름, 없으면 상황실)
func acquire(p_source: String, tick: int, by := "") -> void:
	if known:
		return
	known = true
	source = p_source
	acquired_tick = tick
	if interior:
		interior.plan_known = true
	var sender := by if by != "" else "119종합상황실"
	events.add(tick, "plan_acquired", {"source": p_source, "crew": sender})
	if not office.is_empty() and p_source.begins_with(str(office.name)):
		var floors: PackedStringArray = []
		for lv in fire.building.levels():
			for i in fire.grid.burning:
				if fire.grid.cell_of(i).z == lv:
					floors.append(fire.building.floor_name(lv))
					break
		panel_floors = "·".join(floors)
		events.add(tick, "panel_fire_floor", {"floors": panel_floors if panel_floors != "" else "없음", "crew": sender})


## 관리사무소에 머문 진행 비율 (0~1, 가장 오래 머문 조 기준). 화면 표시용
func dwell_progress() -> float:
	if office.is_empty():
		return 0.0
	var best := 0.0
	for id in _dwell:
		best = maxf(best, float(_dwell[id]))
	return clampf(best / float(office.dwell_s), 0.0, 1.0)


## 이 칸의 구조(벽·문·창·가구)를 지휘관이 아는가: 정보 안개가 꺼져 있거나, 외벽이거나, 대원이 봤다
func structure_seen(level: int, x: int, y: int) -> bool:
	if not perception.enabled:
		return true
	return _exterior.has(Vector3i(x, y, level)) or perception.is_seen(level, x, y)


## 도면에 그려진 칸 종류 (실제와 다른 곳은 도면 쪽)
func plan_cell(level: int, x: int, y: int) -> int:
	return _plan_override.get(Vector3i(x, y, level), fire.building.cell(level, x, y))


## 밖과 맞닿은 벽·창·문 = 외벽 (밖에서 보인다)
func _find_exterior() -> void:
	var b := fire.building
	for lv in b.levels():
		for y in b.height:
			for x in b.width:
				var t := b.cell(lv, x, y)
				if not t in [BuildingData.Cell.WALL, BuildingData.Cell.WINDOW, BuildingData.Cell.DOOR]:
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or ny < 0 or nx >= b.width or ny >= b.height or b.cell(lv, nx, ny) in BuildingData.OUTDOOR:
						_exterior[Vector3i(x, y, lv)] = true
						break
