class_name ElevatorSystem
extends RefCounted
## 비상용승강기 (SOP 222, 기획안 4장 2-2·R13): 고층에서 대원을 승강장에서 다른 층 승강장으로 옮긴다.
##   - 화재층 2개층 아래까지만 탄다 (그 위는 계단). 화재층에 가까이 타고 오르면 대원 안전 위반으로 기록·무전
##   - 이동 시간 = 문 여닫이(door_s) + 층마다 per_floor_s
## 건물 데이터: elevator {name, cell: [x, y], per_floor_s, door_s}

var fire: FireSim
var units: UnitSystem
var pathfinder: Pathfinder
var events: SimEventLog
## 승강장 칸 (모든 층 같은 자리). x < 0이면 없음
var cell := Vector2i(-1, -1)
var name := "비상용승강기"
var _per_floor_s := 2.0
var _door_s := 10.0
## 타고 있는 조 [{crew, level, arrive_tick}]
var rides: Array[Dictionary] = []
## 화재층 2개층 아래보다 높이 탄 횟수 (SOP 222 위반)
var violations := 0


func _init(p_fire: FireSim, p_units: UnitSystem, p_pathfinder: Pathfinder, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	pathfinder = p_pathfinder
	events = p_events


func apply_building(data: Dictionary) -> void:
	var e: Dictionary = data.get("elevator", {})
	if e.has("cell"):
		cell = Vector2i(int(e.cell[0]), int(e.cell[1]))
		name = str(e.get("name", name))
		_per_floor_s = float(e.get("per_floor_s", _per_floor_s))
		_door_s = float(e.get("door_s", _door_s))


func available() -> bool:
	return cell.x >= 0


## 가장 낮은 타는 층 (실제 상태 — 승강기 운행 판정은 결과로 남긴다)
func fire_floor() -> int:
	var lowest := 999
	for i in fire.grid.burning:
		lowest = mini(lowest, fire.grid.cell_of(i).z)
	return lowest if lowest < 999 else -1


## 승강기 타기 (EquipmentCommand "elevator"): 승강장 가까이 있는 조만. 도착 층은 target_level
func ride(crew_id: int, target_level: int, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	if not available() or c == null or not fire.building.has_level(target_level):
		return false
	var at := Vector2(cell) + Vector2(0.5, 0.5)
	if c.leader.pos.distance_to(at) > 3.0 or c.leader.level == target_level:
		events.add(tick, "elevator_far", {"crew": _crew_name(c)})
		return false
	for r in rides:
		if int(r.crew) == crew_id:
			return false
	var b := fire.building
	var floors := absi(b.floor_number(target_level) - b.floor_number(c.leader.level))
	var seconds := _door_s + floors * _per_floor_s
	rides.append({"crew": crew_id, "level": target_level, "arrive_tick": tick + roundi(seconds / SimClock.TICK_DT)})
	var ff := fire_floor()
	if ff > 0 and b.floor_number(target_level) > b.floor_number(ff) - 2:
		violations += 1
		events.add(tick, "elevator_too_high", {"crew": _crew_name(c), "floor": fire.building.floor_name(target_level),
			"fire_floor": fire.building.floor_name(ff)})
	events.add(tick, "elevator_ride", {"crew": _crew_name(c), "floor": fire.building.floor_name(target_level), "seconds": roundi(seconds)})
	# 타는 동안은 그 자리에 둔다 (보이지 않게 aboard처럼)
	for m in c.members():
		m.aboard = true
	return true


func step(tick: int) -> void:
	for r in rides.duplicate():
		if tick < int(r.arrive_tick):
			continue
		rides.erase(r)
		var c := units.get_crew(int(r.crew))
		if c == null:
			continue
		var i := 0
		for m in c.members():
			m.aboard = false
			m.level = int(r.level)
			m.prev_level = m.level
			m.pos = Vector2(cell) + Vector2(0.5 + i * 0.6, 0.5)
			m.prev_pos = m.pos
			i += 1
		units.order_move([c.id] as Array[int], Vector3i(cell.x, cell.y, int(r.level)), pathfinder)
		events.add(tick, "elevator_arrived", {"crew": _crew_name(c), "floor": fire.building.floor_name(int(r.level))})


func riding(crew_id: int) -> bool:
	for r in rides:
		if int(r.crew) == crew_id:
			return true
	return false


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]
