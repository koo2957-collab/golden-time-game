class_name ResourceSystem
extends RefCounted
## 자원의 동원과 관리 (SOP 103).
##   후착대 도착: 시나리오 도착표(arrivals) 시각에 차량이 지도 동쪽 끝에서 들어와 대기1단계 장소에 선다
##   대기1단계 (103-2.1.1): 차량이 서면 조가 내려 기다리고, 출동대명·인원·위치를 보고한다 (squad_staged 사건)
##   투입 (2.1.2): 대기 중인 출동대는 투입 명령을 받아야 움직인다 (무전은 CommandSystem이 보낸다)
##   지원 요청 (1.2): 추가 출동대 요청·대응 1단계 발령 후 시나리오에 정한 시간 뒤 지원 출동대가 도착한다
## 선착대(시나리오 편성 roster)는 처음부터 투입된 상태이다.

enum State { EN_ROUTE, STAGED, COMMITTED }

var units: UnitSystem
var pathfinder: Pathfinder
var conditions: CrewConditionSystem
var building: BuildingData
var events: SimEventLog

## 대기1단계 장소 이름 (무전·화면 표시)
var staging_name := "대기1단계 장소"
## 요청한 지원 수준 (보기 글자). 요청 전이면 빈 문자열
var support_level := ""
var support_tick := -1

var _state: Dictionary = {}  # squad id -> State
var _roster: Dictionary = {}  # squad key -> 편성 데이터
var _support: Dictionary = {}  # 지원 수준 -> {squads, delay_s}
var _lanes: Array[Dictionary] = []  # {y, x_min}
var _gap := 1.0
var _schedule: Array[Dictionary] = []  # {tick, key, reason} (시각 순)
var _queue: Array[Dictionary] = []  # 도착 시각이 지났지만 대기 장소에 자리가 없어 기다리는 출동대
var _called: Dictionary = {}  # squad key -> true (도착표에 올랐거나 이미 도착)


func _init(p_units: UnitSystem, p_pathfinder: Pathfinder, p_conditions: CrewConditionSystem, p_building: BuildingData, p_events: SimEventLog) -> void:
	units = p_units
	pathfinder = p_pathfinder
	conditions = p_conditions
	building = p_building
	events = p_events
	for s in units.squads:
		_state[s.id] = State.COMMITTED
		_called[s.key] = true


## 시나리오의 reinforcements(편성 파일), arrivals(도착표), support(지원 요청), staging(대기 장소)을 읽는다.
func apply_scenario(data: Dictionary) -> void:
	var path := str(data.get("reinforcements", ""))
	if path != "":
		var roster: Variant = JsonData.load_file(path)
		if roster is Dictionary:
			for s: Dictionary in roster.get("squads", []):
				_roster[str(s.get("id", ""))] = s
	var staging: Dictionary = data.get("staging", {})
	staging_name = str(staging.get("name", staging_name))
	_gap = float(staging.get("gap_cells", _gap))
	for lane: Dictionary in staging.get("lanes", []):
		_lanes.append({"y": int(lane.get("y", 0)), "x_min": float(lane.get("x_min", 0))})
	for level: String in data.get("support", {}):
		var entry: Variant = data.support[level]
		if entry is Dictionary:
			_support[level] = entry
	for a: Dictionary in data.get("arrivals", []):
		_add_schedule(str(a.get("squad", "")), roundi(float(a.get("time_s", 0)) / SimClock.TICK_DT), "후착")


## 도착 예정을 모두 지운다 (지휘 절차와 상관없는 테스트용)
func clear_schedule() -> void:
	for list: Array[Dictionary] in [_schedule, _queue]:
		for entry in list:
			_called.erase(entry.key)
	_schedule.clear()
	_queue.clear()


## 출동대 도착을 예약한다 (편성 key, 도착 틱). 이미 부른 출동대면 false
func schedule(key: String, tick: int, reason := "후착") -> bool:
	return _add_schedule(key, tick, reason)


func state_of(squad_id: int) -> State:
	return _state.get(squad_id, State.COMMITTED)


func is_en_route(squad_id: int) -> bool:
	return state_of(squad_id) == State.EN_ROUTE


func is_staged(squad_id: int) -> bool:
	return state_of(squad_id) == State.STAGED


## 현장에 도착한 출동대인지 (대기 중 포함)
func on_scene(squad_id: int) -> bool:
	return state_of(squad_id) != State.EN_ROUTE


## 대기1단계 장소 (차로마다 셀 좌표 사각형, 화면 표시용)
func staging_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for lane in _lanes:
		out.append(Rect2(lane.x_min, lane.y + 0.5 - 2.5, building.width - lane.x_min, 5.0))
	return out


func support_options() -> Array[String]:
	var out: Array[String] = []
	out.assign(_support.keys())
	return out


## 도착 예정 (아직 지도에 나타나지 않은 출동대): [{name, eta_s, reason}]
func upcoming(tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pending: Array[Dictionary] = _queue.duplicate()
	pending.append_array(_schedule)
	for s in pending:
		var data: Dictionary = _roster.get(s.key, {})
		out.append({"name": str(data.get("name", s.key)), "eta_s": maxf(0.0, (s.tick - tick) * SimClock.TICK_DT), "reason": s.reason})
	return out


## 지원 요청. 아직 부르지 않은 출동대만 출동시킨다. 출동시킨 출동대 이름 목록을 돌려준다.
func request_support(level: String, tick: int) -> PackedStringArray:
	var names: PackedStringArray = []
	if not _support.has(level):
		return names
	support_level = level
	if support_tick < 0:
		support_tick = tick
	var entry: Dictionary = _support[level]
	var due := tick + roundi(float(entry.get("delay_s", 0)) / SimClock.TICK_DT)
	for key in entry.get("squads", []):
		if _add_schedule(str(key), due, "지원"):
			names.append(str(_roster[str(key)].get("name", key)))
	events.add(tick, "support_requested", {"level": level})
	if not names.is_empty():
		events.add(tick, "squad_dispatched", {"reason": "지원", "squads": "·".join(names), "eta_s": (due - tick) * SimClock.TICK_DT})
	return names


## 대기 해제 (투입 무전이 전달된 뒤 CommandSystem이 부른다)
func commit(squad_id: int, tick: int) -> void:
	if state_of(squad_id) != State.STAGED:
		return
	_state[squad_id] = State.COMMITTED
	events.add(tick, "squad_committed", {"squad": units.squads[squad_id].name})


## 이동 뒤: 도착 시각이 된 출동대를 들여보내고, 대기 장소에 선 출동대의 조를 내린다.
func step(tick: int) -> void:
	while not _schedule.is_empty() and _schedule[0].tick <= tick:
		_queue.append(_schedule.pop_front())
	while not _queue.is_empty():
		if not _try_enter(_queue[0], tick):
			break
		_queue.pop_front()
	for squad in units.squads:
		if state_of(squad.id) == State.EN_ROUTE and _all_stopped(squad.id):
			_dismount(squad, tick)


# --- 내부 ---

func _add_schedule(key: String, tick: int, reason: String) -> bool:
	if key == "" or _called.has(key):
		return false
	if not _roster.has(key):
		push_error("후착대 편성에 '%s'가 없습니다." % key)
		return false
	_called[key] = true
	var entry := {"tick": tick, "key": key, "reason": reason}
	var i := 0
	while i < _schedule.size() and _schedule[i].tick <= tick:
		i += 1
	_schedule.insert(i, entry)
	return true


## 출동대의 모든 차량이 대기 장소에 설 자리가 있으면 들여보낸다.
func _try_enter(entry: Dictionary, tick: int) -> bool:
	var data: Dictionary = _roster[entry.key]
	var plan := _plan_stops(data.get("vehicles", []))
	if plan.size() < data.get("vehicles", []).size():
		if not entry.get("full_logged", false):
			entry["full_logged"] = true
			events.add(tick, "staging_full", {"squad": str(data.get("name", ""))})
		return false
	var squad := units.add_squad(data, false)
	squad.arrival = "후착"
	_state[squad.id] = State.EN_ROUTE
	var vehicles := units.vehicles_of_squad(squad.id)
	# 같은 차로에 이미 들어오는 차량이 있으면 그 뒤에서 출발한다
	var lane_tail: Dictionary = {}
	for i in vehicles.size():
		var v := vehicles[i]
		var stop: Vector2 = plan[i]
		if not lane_tail.has(stop.y):
			var tail := 0.0
			for r in _lane_obstacles(stop.y, v.width_cells, false):
				tail = maxf(tail, r.end.x)
			lane_tail[stop.y] = tail
		var start_x := maxf(building.width + v.length_cells * 0.5, lane_tail[stop.y] + v.length_cells * 0.5 + _gap)
		lane_tail[stop.y] = start_x + v.length_cells * 0.5
		v.heading = Vector2.LEFT
		v.pos = Vector2(start_x, stop.y)
		v.prev_pos = v.pos
		v.drive(start_x - stop.x)
	events.add(tick, "squad_arriving", {"squad": squad.name, "reason": entry.reason})
	return true


## 차량마다 설 자리 (차체 중심). 앞에서부터 차례로 채운다. 자리가 없는 차량부터는 빠진다.
func _plan_stops(vehicle_list: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var taken: Array[Rect2] = []  # 이번 계획에서 이미 잡은 자리
	for v_data: Dictionary in vehicle_list:
		var stats: Dictionary = units.vehicle_stats.get(str(v_data.get("type", "")), {})
		if stats.is_empty():
			continue
		var length := float(stats.length_m) / units.cell_size_m
		var width := float(stats.width_m) / units.cell_size_m
		var found := false
		for lane in _lanes:
			var y: float = lane.y + 0.5
			var front: float = lane.x_min
			var blocks := _lane_obstacles(y, width)
			for t in taken:
				if absf(t.get_center().y - y) < 0.01:
					blocks.append(t)
			for r in blocks:
				if r.end.x + _gap > front:
					front = r.end.x + _gap
			if front + length > building.width:
				continue
			var center := Vector2(front + length * 0.5, y)
			var probe := Vehicle.new()
			probe.heading = Vector2.LEFT
			probe.length_cells = length
			probe.width_cells = width
			if not pathfinder.vehicle_fits(probe.footprint(center)):
				continue
			out.append(center)
			taken.append(Rect2(front, y - width * 0.5, length, width))
			found = true
			break
		if not found:
			break
	return out


## 차로 띠(y ± 폭/2)에 걸친 차량의 범위. at_goal이면 움직이는 차량은 멈출 자리로 본다
## (설 자리 계산용. 지금 자리는 곧 비므로 빼고, 출발 위치는 at_goal = false로 따로 구한다)
func _lane_obstacles(y: float, width: float, at_goal := true) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for v in units.vehicles:
		var fp := v.footprint(v.goal if v.moving and at_goal else v.pos)
		var r := Rect2(fp[0], Vector2.ZERO)
		for p in fp:
			r = r.expand(p)
		if r.position.y < y + width * 0.5 and r.end.y > y - width * 0.5:
			out.append(r)
	return out


func _all_stopped(squad_id: int) -> bool:
	for v in units.vehicles_of_squad(squad_id):
		if v.moving:
			return false
	return true


## 첫 차량 옆(보도 쪽)에 조를 내린다.
func _dismount(squad: Squad, tick: int) -> void:
	var data: Dictionary = _roster.get(squad.key, {})
	var vehicles := units.vehicles_of_squad(squad.id)
	var people := 0
	var level := building.levels()[0]
	var crews: Array = data.get("crews", [])
	for i in crews.size():
		var spawn := Vector2i(roundi(vehicles[0].pos.x) - 3 + i * 3, 0) if not vehicles.is_empty() else Vector2i.ZERO
		if not vehicles.is_empty():
			spawn.y = floori(vehicles[0].pos.y - vehicles[0].width_cells * 0.5) - 1
		spawn = _free_cell(level, spawn)
		var crew := units.add_crew(squad, crews[i], spawn, level)
		for ff in crew.members():
			conditions.init_member(ff)
			people += 1
	_state[squad.id] = State.STAGED
	var kinds: PackedStringArray = []
	for v in vehicles:
		kinds.append(v.type)
	events.add(tick, "squad_staged", {
		"squad": squad.name,
		"people": people,
		"vehicles": "·".join(kinds) if not kinds.is_empty() else "차량 없음",
		"place": staging_name,
	})


## 조장·짝이 설 수 있는 가까운 칸 (걸을 수 있고 차체 밖)
func _free_cell(level: int, want: Vector2i) -> Vector2i:
	for r in 6:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := want + Vector2i(dx, dy)
				if _standable(level, c) and _standable(level, c + Vector2i.RIGHT):
					return c
	return want


func _standable(level: int, c: Vector2i) -> bool:
	if not pathfinder.passable(level, c.x, c.y):
		return false
	var p := Vector2(c) + Vector2(0.5, 0.5)
	for v in units.vehicles:
		if v.contains(p):
			return false
	return true
