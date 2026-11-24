class_name DoorSystem
extends RefCounted
## 문 개방·폐쇄·파괴.
## - 닫힌 문은 지나갈 수 없다 (길찾기에서 막힘). 조가 문 앞으로 가서 열어야 한다.
## - 잠기지 않은 문: 1명, door_open_s 초.
## - 잠긴 문: 파괴(강제 개방). 문 앞에 forcible_entry_min_people 명 이상이 있을 때만 진행, forcible_entry_s 초.
##   파괴된 문은 다시 닫을 수 없다 (SOP 202-3.3: 진입구 파괴는 현장지휘관 명령으로).
## 문 상태가 바뀌면 구획 모델의 환기 조건과 길찾기가 즉시 바뀐다.
## 창: 깨서 여는 것만 가능 (배연·상부 개방, 1명, window_break_s 초). 깨진 창은 열린 개구부가 된다.

## 문 앞에 있다고 보는 거리 (셀, 약 1.2m). 조장 바로 뒤에 선 짝도 포함되도록 잡는다.
const AT_DOOR_CELLS := 2.3

## 한 문의 작업. crews[0] = 문을 여는 분대(먼저 요청한 분대), 그 뒤 = 문 옆에서 기다리는 분대
## (2026-11-24 사용자 결정 — 전에는 두 분대가 한 문에 함께 붙어 문 앞 두 자리에 네 명이 겹쳐 그려지고 한 명씩 사라졌다)
class Task:
	var opening: Opening
	var open := true
	var crews: Array[int] = []
	var progress := 0.0
	var required := 0.0
	var waiting_people := false

	## 문을 여는 분대 (없으면 -1)
	func worker() -> int:
		return crews[0] if not crews.is_empty() else -1

	## 문 옆에서 기다리는 분대인가
	func stacked(crew_id: int) -> bool:
		return crew_id in crews and crew_id != worker()


var fire: FireSim
var units: UnitSystem
var pathfinder: Pathfinder
var events: SimEventLog
var tasks: Array[Task] = []
## (Opening, tick) : 문이 열렸을 때 (백드래프트 판정) / 닫힌 문 앞 작업을 시작할 때 (징후)
var on_door_opened := Callable()
var on_door_approach := Callable()
var window_break_s := 5.0

var _open_s: float
var _force_s: float
var _force_people: int
var _fire_door_factor: float
## 기다리는 분대가 서는 거리 (칸)
var _stack_cells: float
## 방화문 파괴기를 실었으면 0.5 (출동 준비, R10)
var fire_door_factor_scale := 1.0
## 방화문 파괴에 파괴기가 있어야 하는가 (실제 플레이, P4-1). 없으면 질문 카드 → 차량에 가서 가져온다
var require_equipment := false
## 장비 가지러 가기 [{crew, item, vehicle, door: Vector3i, phase: "go"/"get", until}]
var fetches: Array[Dictionary] = []
var _fetch_s := 10.0


func _init(p_fire: FireSim, p_units: UnitSystem, p_pathfinder: Pathfinder, stats: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	pathfinder = p_pathfinder
	events = p_events
	_open_s = stats.value("door_open_s")
	_force_s = stats.value("forcible_entry_s")
	_force_people = int(stats.value("forcible_entry_min_people"))
	_fire_door_factor = stats.value("fire_door_force_factor")
	_stack_cells = stats.value("door_stack_m") / maxf(0.01, units.cell_size_m)
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


## 문 또는 창 (작업 대상)
func target_at(cell: Vector3i) -> Opening:
	var o := fire.opening_at(cell)
	return o if o and o.kind != Opening.Kind.STAIR else null


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
	var o := target_at(door_cell)
	var c := units.get_crew(crew_id)
	if o == null or c == null:
		return false
	if o.kind == Opening.Kind.WINDOW and (not open or o.broken):
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
		if o.kind == Opening.Kind.WINDOW:
			t.required = window_break_s
		else:
			t.required = (_force_s if o.locked else _open_s) if open else _open_s
			if open and o.locked and fire.building.is_fire_door(o.cells[0]) and require_equipment and not c.has_item("fire_door_breaker"):
				# 방화문 파괴기가 없다 → 묻는다 (기획안 6-1: 본인이 탑승한 차량까지 왕복 + 꺼내는 시간)
				events.add(tick, "equipment_missing", {"crew": _crew_name(c), "crew_id": crew_id, "item": "방화문 파괴기",
					"item_key": "fire_door_breaker", "door": [door_cell.x, door_cell.y, door_cell.z]})
				return false
			if open and o.locked and fire.building.is_fire_door(o.cells[0]):
				t.required *= _fire_door_factor * fire_door_factor_scale  # 방화문: 파괴기·동력절단기로 더 오래 (SOP 213-2.3)
		tasks.append(t)
		if open and o.kind == Opening.Kind.DOOR and on_door_approach.is_valid():
			on_door_approach.call(o, tick)
	var waiting := not t.crews.is_empty()
	t.crews.append(crew_id)
	# 먼저 요청한 분대가 아직 문 가까이 오지 않았으면 이 분대가 연다 — 전술 임무는 지시를 받자마자 문을 요청해
	# 멀리 있는(호스를 꺼내는 중·계단을 오르는 중) 분대가 여는 분대로 잡혔고, 먼저 온 분대가 그 분대를 하염없이 기다렸다
	if waiting and not _near_door(units.get_crew(t.worker()), o):
		_promote(t, crew_id, tick)
		return true
	if waiting:
		# 다른 분대가 이미 이 문을 연다: 문 옆 떨어진 자리에서 기다린다 (열리면 원래 임무대로 들어간다)
		var stack := _stack_spot(c, t)
		if stack != Pathfinder.NO_CELL:
			units.order_move([crew_id] as Array[int], Vector3i(stack.x, stack.y, o.level), pathfinder)
		events.add(tick, "door_stack", {"crew": _crew_name(c), "crew_id": crew_id, "worker": _crew_name(units.get_crew(t.worker())), "room": _door_name(o)})
		return true
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


## 장비 가지러 가기 (P4-1): 본인 출동대 첫 차량으로 가서 꺼내고(fetch_s, 1인이면 2배), 다시 그 문을 연다
func order_fetch(crew_id: int, item_key: String, door_cell: Vector3i, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	if c == null:
		return false
	var vs := units.vehicles_of_squad(c.squad_id)
	if vs.is_empty():
		return false
	var v := vs[0]
	cancel(crew_id)
	fetches = fetches.filter(func(f: Dictionary) -> bool: return int(f.crew) != crew_id)
	fetches.append({"crew": crew_id, "item": item_key, "vehicle": v.id, "door": door_cell, "phase": "go", "until": -1})
	_go_vehicle(c, v)
	events.add(tick, "equipment_fetch", {"crew": _crew_name(c), "vehicle": v.type})
	return true


func set_fetch_s(s: float) -> void:
	_fetch_s = s


## 차량에서 장비를 꺼내는 시간 (2인 기준, 초)
func fetch_seconds() -> float:
	return _fetch_s


func _go_vehicle(c: Crew, v: Vehicle) -> void:
	var near := pathfinder.nearest_walkable(v.level, Vector2i(v.closest_body_point(c.leader.pos).floor()))
	if near != Pathfinder.NO_CELL:
		units.order_move([c.id] as Array[int], Vector3i(near.x, near.y, v.level), pathfinder)


func _step_fetches(tick: int) -> void:
	for f in fetches.duplicate():
		var c := units.get_crew(int(f.crew))
		var v := units.get_vehicle(int(f.vehicle))
		if c == null or v == null or c.leader.incapacitated:
			fetches.erase(f)
			continue
		if f.phase == "go":
			if c.leader.level == v.level and c.leader.pos.distance_to(v.closest_body_point(c.leader.pos)) <= 2.5 and not c.leader.is_moving():
				var people: int = c.able_workers()
				f.phase = "get"
				f.until = tick + roundi(_fetch_s * (1.0 if people >= 2 else 2.0) / SimClock.TICK_DT)
			elif not c.leader.is_moving():
				_go_vehicle(c, v)
		elif tick >= int(f.until):
			fetches.erase(f)
			if not c.has_item(str(f.item)):
				c.items.append(str(f.item))
			events.add(tick, "equipment_fetched", {"crew": _crew_name(c), "item": "방화문 파괴기" if f.item == "fire_door_breaker" else str(f.item)})
			request(c.id, f.door, true, tick)


## 장비 가지러 가는 중 진행률 (0~1, 꺼내는 중만, 아니면 -1)
func fetch_progress(crew_id: int, tick: int) -> float:
	for f in fetches:
		if int(f.crew) == crew_id and f.phase == "get":
			var total := roundi(_fetch_s / SimClock.TICK_DT)
			return clampf(1.0 - float(int(f.until) - tick) / float(maxi(1, total)), 0.0, 1.0)
	return -1.0


## 분대 조장이 문 가까이(기다리는 자리 거리 + 2칸 안, 같은 층)에 와 있는가
func _near_door(c: Crew, o: Opening) -> bool:
	if c == null or c.leader.incapacitated or c.leader.level != o.level:
		return false
	return c.leader.pos.distance_to(_center(o)) <= _stack_cells + 2.0


func _center(o: Opening) -> Vector2:
	var center := Vector2.ZERO
	for cell in o.cells:
		center += Vector2(cell) + Vector2(0.5, 0.5)
	return center / maxf(1.0, o.cells.size())


## crew_id 분대를 여는 분대로 올린다: 문 앞 작업 자리로 보내고, 그때까지 여는 분대였던 분대는 문 옆 대기 자리로
func _promote(t: Task, crew_id: int, tick: int) -> void:
	var old := units.get_crew(t.worker())
	t.crews.erase(crew_id)
	t.crews.insert(0, crew_id)
	var c := units.get_crew(crew_id)
	var spot := _work_spot(c, t.opening)
	if spot != Pathfinder.NO_CELL:
		units.order_move([crew_id] as Array[int], Vector3i(spot.x, spot.y, t.opening.level), pathfinder)
	if old != null and old != c:
		var stack := _stack_spot(old, t)
		if stack != Pathfinder.NO_CELL:
			units.order_move([old.id] as Array[int], Vector3i(stack.x, stack.y, t.opening.level), pathfinder)
		events.add(tick, "door_stack", {"crew": _crew_name(old), "crew_id": old.id, "worker": _crew_name(c), "room": _door_name(t.opening)})


## 여는 분대가 아직 문 가까이 오지 않았는데 기다리는 분대가 문 가까이 멈춰 있으면 그 분대가 연다 (1초마다)
func _step_workers(tick: int) -> void:
	if tick % maxi(1, roundi(1.0 / SimClock.TICK_DT)) != 0:
		return
	for t in tasks:
		if t.crews.size() < 2 or _near_door(units.get_crew(t.worker()), t.opening):
			continue
		for id in t.crews.slice(1):
			var c := units.get_crew(id)
			if c != null and not c.leader.is_moving() and _near_door(c, t.opening):
				_promote(t, id, tick)
				break


func step(dt: float, tick: int) -> void:
	_step_fetches(tick)
	_step_workers(tick)
	for t in tasks.duplicate():
		var people := _workers_at_door(t)
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
	if o.kind == Opening.Kind.WINDOW:
		o.broken = true
		o.is_open = true
		events.add(tick, "window_vented", {"room": _door_name(o)})
		tasks.erase(t)
		return
	if t.open:
		if o.locked:
			o.locked = false
			o.forced = true
			events.add(tick, "door_forced", {"room": _door_name(o)})
		else:
			events.add(tick, "door_opened", {"opening": o.index, "kind": o.kind_name(), "room": _door_name(o)})
		o.is_open = true
		if on_door_opened.is_valid():
			on_door_opened.call(o, tick)
	else:
		if _someone_in_doorway(o):
			events.add(tick, "door_cannot_close", {"crew": _crew_name(units.get_crew(t.crews[0]))})
		else:
			o.is_open = false
			events.add(tick, "door_closed", {"opening": o.index, "kind": o.kind_name(), "room": _door_name(o)})
	for c in o.cells:
		pathfinder.set_blocked(o.level, c, not o.is_open)
	tasks.erase(t)


## 문 앞에서 일할 수 있는 대원 수: 여는 분대의 대원만 센다. 그 분대만으로 모자라면(잠긴 문 2명) 기다리는 분대가 거든다
func _workers_at_door(t: Task) -> int:
	var need := _force_people if (t.open and t.opening.locked) else 1
	var own := _people_at_door(t.opening, [t.worker()])
	return own if own >= need else _people_at_door(t.opening, t.crews)


## 문 앞(문 칸 근처)에 서 있고 움직이지 않는, 행동 가능한 대원 수 (crew_ids 를 주면 그 조들만)
func _people_at_door(o: Opening, crew_ids: Array = []) -> int:
	var n := 0
	for ff in units.firefighters:
		if ff.incapacitated or ff.level != o.level or ff.is_moving():
			continue
		if not crew_ids.is_empty() and not ff.crew_id in crew_ids:
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


## 기다리는 분대가 설 자리: 문 가운데에서 door_stack_m 쯤 떨어지고, 여는 분대(조장·작업 자리)와도 그만큼 떨어진 칸.
## 분대가 지금 있는 쪽(문 바깥·안)에서 고른다 — 길이 크게 돌아가는 칸(다른 출입구로 돌아 들어가는 곳)은 뺀다
func _stack_spot(c: Crew, t: Task) -> Vector2i:
	var o := t.opening
	var center := _center(o)
	var avoid: Array[Vector2] = []
	var w := units.get_crew(t.worker())
	if w != null:
		avoid.append(w.leader.pos)
		var ws := _work_spot(w, o)
		if ws != Pathfinder.NO_CELL:
			avoid.append(Vector2(ws) + Vector2(0.5, 0.5))
	# 먼저 와서 기다리는 다른 분대와도 겹치지 않게
	for id in t.crews:
		var other := units.get_crew(id)
		if other != null and other != c and other != w:
			var goal := other.leader.pos
			if not other.leader.path.is_empty():
				var last: Vector3i = other.leader.path[-1]
				goal = Vector2(last.x, last.y) + Vector2(0.5, 0.5)
			avoid.append(goal)
	var r := ceili(_stack_cells) + 2
	var cands: Array = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := Vector2i(floori(center.x) + dx, floori(center.y) + dy)
			if n in o.cells or not pathfinder.passable(o.level, n.x, n.y):
				continue
			var p := Vector2(n) + Vector2(0.5, 0.5)
			var d := p.distance_to(center)
			if d < _stack_cells:
				continue
			var clear := true
			for a in avoid:
				if p.distance_to(a) < _stack_cells * 0.75:
					clear = false
			if clear:
				cands.append([absf(d - _stack_cells) + p.distance_to(c.leader.pos) * 0.05, n])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var here := c.leader.cell3()
	# 문 앞까지 가는 길보다 크게 돌아가는 칸(다른 출입구로 돌아 문 반대쪽에 서는 곳)은 뺀다 — 계단으로 올라오는 분대도 쓸 수 있게
	# 곧은 거리 대신 문 앞 작업 자리까지의 길 길이와 견준다
	var limit := INF
	var ws := _work_spot(c, o)
	if ws != Pathfinder.NO_CELL:
		limit = pathfinder.find_path(here, Vector3i(ws.x, ws.y, o.level)).size() + _stack_cells * 2.0 + 6.0
	for e in cands:
		var n: Vector2i = e[1]
		var path := pathfinder.find_path(here, Vector3i(n.x, n.y, o.level))
		if not path.is_empty() and path.size() <= limit:
			return n
	return Pathfinder.NO_CELL


func _remove_crew(t: Task, crew_id: int) -> void:
	var was_worker := t.worker() == crew_id
	t.crews.erase(crew_id)
	if t.crews.is_empty():
		tasks.erase(t)
	elif was_worker:
		# 문을 열던 분대가 빠졌다: 기다리던 분대가 이어서 연다
		var next := units.get_crew(t.worker())
		if next != null:
			var spot := _work_spot(next, t.opening)
			if spot != Pathfinder.NO_CELL:
				units.order_move([next.id] as Array[int], Vector3i(spot.x, spot.y, t.opening.level), pathfinder)


func _door_name(o: Opening) -> String:
	var a := fire.comps[o.room_a].display_name()
	return a if o.room_b == Opening.OUTSIDE else "%s ↔ %s" % [a, fire.comps[o.room_b].name]


func _crew_name(c: Crew) -> String:
	return units.crew_name(c)
