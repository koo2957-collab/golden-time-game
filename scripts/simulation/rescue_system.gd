class_name RescueSystem
extends RefCounted
## 요구조자, 인명검색, 구조(운반).
## - 배치: 시나리오가 정한 방 안의 인명검색 중점지역(침대 옆·창가·출입구·구석) 중 시드로 정한다 (SOP 202-4)
## - 생존: 호흡 높이의 연기(독성)·열 노출량(FED)이 쌓여 1이면 의식 잃음, fed_death면 사망
##   쓰러져 있으면 바닥 가까이(연기층 아래)라 덜 노출되지만, 연기층이 바닥까지 내려오면 급격히 나빠진다
## - 발견: 대원 시야(눈)·열화상카메라·소리(의식 있을 때, 벽 너머 포함)
## - 인명검색: 방의 벽을 따라 지점을 돌며 살핀다. 끝나면 검색 완료 표시 (SOP 202-4.5, 212-2.1)
## - 구조: 2인이 업고 가장 가까운 바깥(지상)으로 나간다 (SOP 203-1.3). 수관을 든 조는 구조할 수 없다

## 요구조자를 업으러 다가갈 때 거리 (셀)
const PICKUP_RANGE := 1.6
## 검색 지점 간격 (셀)
const SEARCH_SPACING := 3
## 나갈 길이 없을 때 다시 찾는 간격 (틱)
const EXIT_RETRY_TICKS := 30

class SearchTask:
	var crew_id := 0
	var room := 0
	var waypoints: Array[Vector2i] = []
	var next := 0
	var level := 1


class CarryTask:
	var crew_id := 0
	## "victim" 또는 "ff"(쓰러진 대원)
	var kind := "victim"
	var target_id := 0
	var carrying := false
	## 출구로 자동 이동 중인지 (지휘관이 다른 곳으로 보내면 false)
	var auto_exit := true
	var next_exit_try := 0


var fire: FireSim
var units: UnitSystem
var pathfinder: Pathfinder
var perception: Perception
var events: SimEventLog
var victims: Array[Victim] = []
var searches: Array[SearchTask] = []
var carries: Array[CarryTask] = []
## 수관을 든 조는 구조할 수 없다 (WaterSystem으로 확인)
var water: WaterSystem

var _cell_m: float
var _co_per_soot: float
var _fed_div: float
var _heat_a: float
var _heat_b: float
var _heat_min: float
var _fed_unconscious: float
var _fed_death: float
var _lying_h: float
var _carried_h: float
var _lower_ratio: float
var _voice_cells: float
var _carry_factor: float


func _init(p_fire: FireSim, p_units: UnitSystem, p_pathfinder: Pathfinder, p_perception: Perception, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	pathfinder = p_pathfinder
	perception = p_perception
	events = p_events
	_cell_m = fire.building.cell_size_m
	_co_per_soot = params.value("co_per_soot")
	_fed_div = params.value("fed_co_divisor")
	_heat_a = params.value("heat_incap_a")
	_heat_b = params.value("heat_incap_b")
	_heat_min = params.value("heat_exposure_min_c")
	_fed_unconscious = params.value("fed_unconscious")
	_fed_death = params.value("fed_death")
	_lying_h = params.value("lying_breath_height_m")
	_carried_h = params.value("carried_breath_height_m")
	_lower_ratio = params.value("lower_layer_exposure_ratio")
	_voice_cells = params.value("voice_range_m") / _cell_m
	_carry_factor = params.value("carry_speed_factor")


# --- 배치 ---

## 시나리오의 victims 목록으로 요구조자를 배치한다
func add_victims(list: Array, rng: RandomNumberGenerator) -> void:
	for data: Dictionary in list:
		var v := Victim.new()
		v.id = victims.size()
		v.name = str(data.get("name", "요구조자"))
		v.age = int(data.get("age", 0))
		v.mobility = str(data.get("mobility", ""))
		v.level = int(data.get("level", 1))
		if data.has("cell"):
			var c: Array = data.cell
			v.pos = Vector2(int(c[0]) + 0.5, int(c[1]) + 0.5)
		else:
			var cell := _pick_spot(v.level, str(data.get("room", "")), rng)
			v.pos = Vector2(cell) + Vector2(0.5, 0.5)
		victims.append(v)


## 방 안 인명검색 중점지역에 가중치를 두어 위치를 고른다 (SOP 202-4)
func _pick_spot(level: int, room_id: String, rng: RandomNumberGenerator) -> Vector2i:
	var b := fire.building
	var room: Compartment = null
	for c in fire.comps:
		if c.level == level and c.id == room_id:
			room = c
	if room == null:
		push_error("요구조자 방 '%s'를 찾을 수 없습니다." % room_id)
		return Vector2i.ZERO
	var beds := {}
	for item in b.furniture(level):
		if item.name == "침대":
			var r: Rect2i = item.rect
			for y in range(r.position.y - 1, r.end.y + 1):
				for x in range(r.position.x - 1, r.end.x + 1):
					beds[Vector2i(x, y)] = true
	var cells: Array[Vector2i] = []
	var weights: Array[float] = []
	var total := 0.0
	for cell in room.cells:
		if b.cell(level, cell.x, cell.y) != BuildingData.Cell.FLOOR:
			continue
		var w := 0.5
		if beds.has(cell):
			w = 3.0
		var walls := 0
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var t := b.cell(level, cell.x + d.x, cell.y + d.y)
			if t == BuildingData.Cell.WINDOW or t == BuildingData.Cell.DOOR:
				w = maxf(w, 2.0)
			if t == BuildingData.Cell.WALL or t == BuildingData.Cell.WINDOW:
				walls += 1
		if walls >= 2:
			w = maxf(w, 2.0)
		cells.append(cell)
		weights.append(w)
		total += w
	var pick := rng.randf() * total
	for k in cells.size():
		pick -= weights[k]
		if pick <= 0.0:
			return cells[k]
	return cells[-1]


# --- 조회 ---

## p(셀 좌표) 근처의 발견된 요구조자 (구조되지 않은). 없으면 -1.
func victim_near(level: int, p: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius
	for v in victims:
		if not v.discovered or v.level != level or v.state == Victim.State.RESCUED or v.carried_by >= 0:
			continue
		var d := v.pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = v.id
	return best


func downed_ff_near(level: int, p: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius
	for ff in units.firefighters:
		if not ff.incapacitated or ff.level != level or _carried_ff(ff.id):
			continue
		var d := ff.pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = ff.id
	return best


func task_of_crew(crew_id: int) -> RefCounted:
	for t in searches:
		if t.crew_id == crew_id:
			return t
	for t in carries:
		if t.crew_id == crew_id:
			return t
	return null


# --- 명령 ---

## 인명검색: 클릭한 셀이 속한 방을 벽을 따라 훑는다
func order_search(crew_id: int, cell: Vector3i, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	var room := fire.compartment_at(cell.z, cell.x, cell.y)
	if c == null or room == null or _busy_carrying(crew_id):
		return false
	cancel(crew_id)
	var t := SearchTask.new()
	t.crew_id = crew_id
	t.room = room.index
	t.level = room.level
	t.waypoints = _search_route(room, c.leader.pos)
	searches.append(t)
	_go(c, t.waypoints[0], t.level)
	events.add(tick, "search_start", {"crew": _crew_name(c), "room": room.display_name()})
	return true


## 구조: 요구조자(kind = "victim") 또는 쓰러진 대원(kind = "ff")을 업으러 간다
func order_rescue(crew_id: int, kind: String, target_id: int, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	if c == null or _busy_carrying(crew_id):
		return false
	# 2인이 업어야 하므로 두 명 모두 움직일 수 있어야 한다
	for member in c.members():
		if member.incapacitated:
			return false
	if c.partner == null:
		return false
	if water and water.hose_of_crew(crew_id) != null:
		events.add(tick, "rescue_hose_crew", {"crew": _crew_name(c)})
		return false
	var target_pos: Vector2
	var target_level: int
	if kind == "victim":
		var v := victims[target_id]
		if not v.discovered or not v.alive() or v.carried_by >= 0:
			return false
		target_pos = v.pos
		target_level = v.level
	else:
		var ff := units.firefighters[target_id]
		if not ff.incapacitated or _carried_ff(target_id):
			return false
		target_pos = ff.pos
		target_level = ff.level
	cancel(crew_id)
	var t := CarryTask.new()
	t.crew_id = crew_id
	t.kind = kind
	t.target_id = target_id
	carries.append(t)
	_go(c, Vector2i(target_pos.floor()), target_level)
	return true


## 다른 명령을 받으면 검색과 '업으러 가는 중'은 취소한다. 이미 업고 있으면 계속 업고 간다 (자동 출구 이동만 끔).
func cancel(crew_id: int) -> void:
	for t in searches.duplicate():
		if t.crew_id == crew_id:
			searches.erase(t)
	for t in carries.duplicate():
		if t.crew_id == crew_id:
			if t.carrying:
				t.auto_exit = false
			else:
				carries.erase(t)


# --- 매 틱 ---

## 이동 후: 업은 사람 따라오기, 업기, 출구 도착(구조 완료), 검색 진행
func step_after_move(_dt: float, tick: int) -> void:
	for t in carries.duplicate():
		_step_carry(t, tick)
	for t in searches.duplicate():
		_step_search(t, tick)


## 화재 계산 후: 노출량, 발견
func step_after_fire(dt: float, tick: int) -> void:
	for v in victims:
		if v.alive():
			_expose(v, dt, tick)
		if not v.discovered and v.state != Victim.State.RESCUED:
			_check_discovery(v, tick)


## 요구조자가 있는 방에 플래시오버가 나면 생존할 수 없다 (교재 제2장 제5절)
func on_flashover(room: Compartment, tick: int) -> void:
	for v in victims:
		if v.alive() and v.carried_by < 0 and v.level == room.level and fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y)) == room:
			_set_state(v, Victim.State.DEAD, tick, "플래시오버")


func _step_carry(t: CarryTask, tick: int) -> void:
	var c := units.get_crew(t.crew_id)
	if c.leader.incapacitated or (c.partner and c.partner.incapacitated):
		_drop(t)
		return
	if not t.carrying:
		var target := _target_pos(t)
		if c.leader.level == int(target.z) and c.leader.pos.distance_to(Vector2(target.x, target.y)) <= PICKUP_RANGE and not c.leader.is_moving():
			t.carrying = true
			for ff in c.members():
				ff.carry_factor = _carry_factor
			if t.kind == "victim":
				victims[t.target_id].carried_by = t.crew_id
			events.add(tick, "rescue_pickup", {"crew": _crew_name(c), "who": _target_name(t)})
			_go_exit(t, c, tick)
		elif not c.leader.is_moving():
			# 길이 막혔거나 도착이 어긋나면 다시 다가간다
			_go(c, Vector2i(Vector2(target.x, target.y).floor()), int(target.z))
		return
	# 업고 가는 중: 업힌 사람이 조장을 따라온다
	if t.kind == "victim":
		var v := victims[t.target_id]
		v.pos = c.leader.pos
		v.level = c.leader.level
	else:
		var ff := units.firefighters[t.target_id]
		ff.pos = c.leader.pos + Vector2(0.3, 0.3)
		ff.prev_pos = ff.pos
		ff.level = c.leader.level
	if _is_outdoor(c.leader.level, Vector2i(c.leader.pos.floor())):
		_complete(t, c, tick)
	elif t.auto_exit and not c.leader.is_moving() and tick >= t.next_exit_try:
		_go_exit(t, c, tick)


func _complete(t: CarryTask, c: Crew, tick: int) -> void:
	for ff in c.members():
		ff.carry_factor = 1.0
	carries.erase(t)
	if t.kind == "victim":
		var v := victims[t.target_id]
		v.carried_by = -1
		if v.alive():
			v.state_at_rescue = v.state
			v.state = Victim.State.RESCUED
			v.rescued_tick = tick
			events.add(tick, "victim_rescued", {"who": v.label(), "state": Victim.STATE_NAMES[v.state_at_rescue]})
		else:
			events.add(tick, "victim_recovered", {"who": v.label()})
	else:
		events.add(tick, "ff_rescued", {"who": _target_name(t)})


func _drop(t: CarryTask) -> void:
	var c := units.get_crew(t.crew_id)
	for ff in c.members():
		ff.carry_factor = 1.0
	if t.kind == "victim":
		victims[t.target_id].carried_by = -1
	carries.erase(t)


## 가장 가까운 바깥 출구(열린 외부 문 밖 칸)로 간다
func _go_exit(t: CarryTask, c: Crew, tick: int) -> void:
	var exits := _exit_cells()
	var best: Array[Vector3i] = []
	for e in exits:
		var path := pathfinder.find_path(c.leader.cell3(), e)
		if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
			best = path
	if best.is_empty():
		t.next_exit_try = tick + EXIT_RETRY_TICKS
		if tick % 300 == 0 or t.next_exit_try == tick + EXIT_RETRY_TICKS:
			events.add(tick, "exit_blocked", {"crew": _crew_name(c)})
		return
	var goal := best[-1]
	units.order_move([c.id] as Array[int], goal, pathfinder)


## 열린 외부 문 바로 바깥 칸들 (구조 이송·철수 목적지)
func exit_cells() -> Array[Vector3i]:
	return _exit_cells()


func _exit_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var b := fire.building
	for o in fire.openings:
		if o.kind != Opening.Kind.DOOR or o.room_b != Opening.OUTSIDE or not o.is_open:
			continue
		for cell in o.cells:
			for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
				var n := cell + d
				if b.cell(o.level, n.x, n.y) in BuildingData.OUTDOOR and pathfinder.passable(o.level, n.x, n.y):
					out.append(Vector3i(n.x, n.y, o.level))
	return out


func _step_search(t: SearchTask, tick: int) -> void:
	var c := units.get_crew(t.crew_id)
	if c.leader.incapacitated:
		searches.erase(t)
		return
	if c.leader.is_moving():
		return
	t.next += 1
	if t.next < t.waypoints.size():
		_go(c, t.waypoints[t.next], t.level)
		return
	var room := fire.comps[t.room]
	room.searched_tick = tick
	searches.erase(t)
	events.add(tick, "search_done", {"crew": _crew_name(c), "room": room.display_name()})


## 방 둘레(벽에 붙은 칸)를 조장에게서 가까운 곳부터 한 바퀴, SEARCH_SPACING 간격으로 돈다. 마지막에 방 가운데.
func _search_route(room: Compartment, from: Vector2) -> Array[Vector2i]:
	var b := fire.building
	var center := Vector2.ZERO
	for cell in room.cells:
		center += Vector2(cell) + Vector2(0.5, 0.5)
	center /= room.cells.size()
	var edge: Array[Vector2i] = []
	for cell in room.cells:
		if not pathfinder.passable(room.level, cell.x, cell.y):
			continue
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			if fire.compartment_at(room.level, cell.x + d.x, cell.y + d.y) != room:
				edge.append(cell)
				break
	edge.sort_custom(func(a: Vector2i, c: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5) - center).angle() < (Vector2(c) + Vector2(0.5, 0.5) - center).angle())
	# 조장에게서 가장 가까운 칸부터 시작
	var start := 0
	for k in edge.size():
		if from.distance_squared_to(Vector2(edge[k])) < from.distance_squared_to(Vector2(edge[start])):
			start = k
	var route: Array[Vector2i] = []
	for k in range(0, edge.size(), SEARCH_SPACING):
		route.append(edge[(start + k) % edge.size()])
	var mid := Vector2i(center.floor())
	if pathfinder.passable(room.level, mid.x, mid.y):
		route.append(mid)
	if route.is_empty():
		route.append(room.cells[0])
	return route


func _go(c: Crew, cell: Vector2i, level: int) -> void:
	units.order_move([c.id] as Array[int], Vector3i(cell.x, cell.y, level), pathfinder)


# --- 노출·발견 ---

func _expose(v: Victim, dt: float, tick: int) -> void:
	var cell := Vector2i(v.pos.floor())
	var c := fire.compartment_at(v.level, cell.x, cell.y)
	if c == null:
		return
	var breath := _carried_h if v.carried_by >= 0 else _lying_h
	var in_layer := breath >= c.height - c.layer_depth
	var conc := c.soot / maxf(c.layer_volume(), 0.05 * c.volume)
	if not in_layer:
		conc *= _lower_ratio
	var co_ppm := conc * _co_per_soot / 1.145 * 1e6
	if co_ppm > 1.0:
		v.fed_toxic += pow(co_ppm, 1.036) / _fed_div * dt / 60.0
	var temp := c.t_upper if in_layer else c.t_lower
	if temp > _heat_min:
		v.fed_heat += dt / 60.0 / exp(_heat_a - _heat_b * temp)
	if v.fed() >= _fed_death:
		_set_state(v, Victim.State.DEAD, tick, "연기·열 노출")
	elif v.fed() >= _fed_unconscious and v.state == Victim.State.CONSCIOUS:
		_set_state(v, Victim.State.UNCONSCIOUS, tick, "연기·열 노출")


func _set_state(v: Victim, state: Victim.State, tick: int, reason: String) -> void:
	v.state = state
	# 발견 전에 일어난 일은 지휘관이 모른다: 발견된 요구조자만 알림
	if v.discovered:
		events.add(tick, "victim_state", {"who": v.label(), "state": Victim.STATE_NAMES[state], "reason": reason})


func _check_discovery(v: Victim, tick: int) -> void:
	var how := ""
	var cx := floori(v.pos.x)
	var cy := floori(v.pos.y)
	if perception.is_crew_visible(v.level, cx, cy):
		how = "육안"
	elif perception.is_thermal_visible(v.level, cx, cy):
		how = "열화상"
	elif v.state == Victim.State.CONSCIOUS and _at_window(v) and perception.is_visible(v.level, cx, cy):
		how = "창가 목격"  # 창가에서 구조를 요청하는 사람은 밖에서 보인다 (SOP 202-2.2)
	elif v.state == Victim.State.CONSCIOUS:
		for ff in units.firefighters:
			if not ff.incapacitated and ff.level == v.level and ff.pos.distance_to(v.pos) <= _voice_cells:
				how = "소리"
				break
	if how == "":
		return
	v.discovered = true
	v.discovered_tick = tick
	var room := fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
	events.add(tick, "victim_found", {
		"who": v.label(), "how": how, "state": Victim.STATE_NAMES[v.state],
		"room": room.display_name() if room else "",
	})


# --- 도우미 ---

func _at_window(v: Victim) -> bool:
	var c := Vector2i(v.pos.floor())
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if fire.building.cell(v.level, c.x + dx, c.y + dy) == BuildingData.Cell.WINDOW:
				return true
	return false


func _target_pos(t: CarryTask) -> Vector3:
	if t.kind == "victim":
		var v := victims[t.target_id]
		return Vector3(v.pos.x, v.pos.y, v.level)
	var ff := units.firefighters[t.target_id]
	return Vector3(ff.pos.x, ff.pos.y, ff.level)


func _target_name(t: CarryTask) -> String:
	if t.kind == "victim":
		return victims[t.target_id].label()
	var ff := units.firefighters[t.target_id]
	return "%s %s" % [units.squads[ff.squad_id].name, ff.name]


func _carried_ff(ff_id: int) -> bool:
	for t in carries:
		if t.kind == "ff" and t.target_id == ff_id and t.carrying:
			return true
	return false


func _busy_carrying(crew_id: int) -> bool:
	for t in carries:
		if t.crew_id == crew_id and t.carrying:
			return true
	return false


func _is_outdoor(level: int, cell: Vector2i) -> bool:
	return fire.building.cell(level, cell.x, cell.y) in BuildingData.OUTDOOR


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]
