class_name DoorSystem
extends RefCounted
## 문 개방·폐쇄·파괴.
## - 닫힌 문은 지나갈 수 없다 (길찾기에서 막힘). 조가 문 앞으로 가서 열어야 한다.
## - 잠기지 않은 문: 1명, door_open_s 초.
## - 잠긴 문: 파괴(강제 개방). 문 앞에 forcible_entry_min_people 명 이상이 있을 때만 진행, forcible_entry_s 초.
##   파괴된 문은 다시 닫을 수 없다 (SOP 202-3.3: 진입구 파괴는 현장지휘관 명령으로).
## 문 상태가 바뀌면 구획 모델의 환기 조건과 길찾기가 즉시 바뀐다.

## 문 앞에 있다고 보는 거리 (셀, 약 1.2m). 조장 바로 뒤에 선 짝도 포함되도록 잡는다.
const AT_DOOR_CELLS := 2.3

class Task:
	var opening: Opening
	var open := true
	var crews: Array[int] = []
	var progress := 0.0
	var required := 0.0
	var waiting_people := false


var fire: FireSim
var units: UnitSystem
var pathfinder: Pathfinder
var events: SimEventLog
var tasks: Array[Task] = []

var _open_s: float
var _force_s: float
var _force_people: int


func _init(p_fire: FireSim, p_units: UnitSystem, p_pathfinder: Pathfinder, stats: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	pathfinder = p_pathfinder
	events = p_events
	_open_s = stats.value("door_open_s")
	_force_s = stats.value("forcible_entry_s")
	_force_people = int(stats.value("forcible_entry_min_people"))
	sync_blocking()


## 모든 문 상태를 길찾기에 반영한다 (닫힌 문 = 막힘)
func sync_blocking() -> void:
	for o in fire.openings:
		if o.kind == Opening.Kind.DOOR:
			for c in o.cells:
				pathfinder.set_blocked(o.level, c, not o.is_open)


func door_at(cell: Vector3i) -> Opening:
	var o := fire.opening_at(cell)
	return o if o and o.kind == Opening.Kind.DOOR else null


func task_of(o: Opening) -> Task:
	for t in tasks:
		if t.opening == o:
			return t
	return null


func task_of_crew(crew_id: int) -> Task:
	for t in tasks:
		if crew_id in t.crews:
			return t
	return null


## 조에게 문을 열거나(open=true) 닫게 한다. 같은 문에 이미 작업이 있으면 그 작업을 돕는다.
func request(crew_id: int, door_cell: Vector3i, open: bool, tick: int) -> bool:
	var o := door_at(door_cell)
	var c := units.get_crew(crew_id)
	if o == null or c == null:
		return false
	if o.is_open == open and task_of(o) == null:
		return false
	if not open and o.forced:
		events.add(tick, "door_cannot_close", {"crew": _crew_name(c)})
		return false
	cancel(crew_id)
	var t := task_of(o)
	if t == null:
		t = Task.new()
		t.opening = o
		t.open = open
		t.required = (_force_s if o.locked else _open_s) if open else _open_s
		tasks.append(t)
	t.crews.append(crew_id)
	var spot := _work_spot(c, o)
	if spot == Pathfinder.NO_CELL:
		events.add(tick, "door_unreachable", {"crew": _crew_name(c)})
		_remove_crew(t, crew_id)
		return false
	units.order_move([crew_id] as Array[int], Vector3i(spot.x, spot.y, o.level), pathfinder)
	return true


## 다른 명령을 받으면 문 작업에서 빠진다
func cancel(crew_id: int) -> void:
	var t := task_of_crew(crew_id)
	if t:
		_remove_crew(t, crew_id)


func step(dt: float, tick: int) -> void:
	for t in tasks.duplicate():
		var people := _people_at_door(t.opening)
		var need := _force_people if (t.open and t.opening.locked) else 1
		if people <= 0:
			continue
		t.waiting_people = people < need
		if t.waiting_people:
			continue
		t.progress += dt
		if t.progress >= t.required:
			_finish(t, tick)


func _finish(t: Task, tick: int) -> void:
	var o := t.opening
	if t.open:
		if o.locked:
			o.locked = false
			o.forced = true
			events.add(tick, "door_forced", {"room": _door_name(o)})
		else:
			events.add(tick, "door_opened", {"opening": o.index, "kind": o.kind_name(), "room": _door_name(o)})
		o.is_open = true
	else:
		if _someone_in_doorway(o):
			events.add(tick, "door_cannot_close", {"crew": _crew_name(units.get_crew(t.crews[0]))})
		else:
			o.is_open = false
			events.add(tick, "door_closed", {"opening": o.index, "kind": o.kind_name(), "room": _door_name(o)})
	for c in o.cells:
		pathfinder.set_blocked(o.level, c, not o.is_open)
	tasks.erase(t)


## 문 앞(문 칸 근처)에 서 있고 움직이지 않는, 행동 가능한 대원 수
func _people_at_door(o: Opening) -> int:
	var n := 0
	for ff in units.firefighters:
		if ff.incapacitated or ff.level != o.level or ff.is_moving():
			continue
		for c in o.cells:
			if ff.pos.distance_to(Vector2(c) + Vector2(0.5, 0.5)) <= AT_DOOR_CELLS:
				n += 1
				break
	return n


func _someone_in_doorway(o: Opening) -> bool:
	for ff in units.firefighters:
		if ff.level == o.level and Vector2i(ff.pos.floor()) in o.cells:
			return true
	return false


## 조장이 설 작업 위치: 문 칸에 맞닿은 지나갈 수 있는 셀 중 조장에게서 길이 이어지는 가장 가까운 곳
func _work_spot(c: Crew, o: Opening) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for cell in o.cells:
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var n := cell + d
			if not n in o.cells and not n in candidates and pathfinder.passable(o.level, n.x, n.y):
				candidates.append(n)
	var from := c.leader.pos
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return from.distance_squared_to(Vector2(a)) < from.distance_squared_to(Vector2(b)))
	var here := c.leader.cell3()
	for n in candidates:
		if Vector3i(n.x, n.y, o.level) == here:
			return n
		if not pathfinder.find_path(here, Vector3i(n.x, n.y, o.level)).is_empty():
			return n
	return Pathfinder.NO_CELL


func _remove_crew(t: Task, crew_id: int) -> void:
	t.crews.erase(crew_id)
	if t.crews.is_empty():
		tasks.erase(t)


func _door_name(o: Opening) -> String:
	var a := fire.comps[o.room_a].display_name()
	return a if o.room_b == Opening.OUTSIDE else "%s ↔ %s" % [a, fire.comps[o.room_b].name]


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]
