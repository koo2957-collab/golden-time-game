class_name EvacSystem
extends RefCounted
## 자력 대피 (SOP 212-1.2 입체적으로 발생하는 구조대상자). 시나리오에서 self_evac: true인 요구조자는
## 화재를 알아차리면(사람마다 alert_s, 없으면 evac_alert_s 뒤) 가장 가까운 바깥 출입구로 걸어 나간다.
## 나갈 길에 연기층이 머리 높이(evac_clear_m)까지 내려오고 뜨거우면(evac_hot_c) 출발하지 않고 제자리에 머물며,
## 가는 도중 막히면 그 자리에서 멈춘다(갇힘). 둘 다 구조를 기다린다.
## 밖으로 나오면 구조된 사람과 같이 다룬다 (구급 분류 대상).

var fire: FireSim
var rescue: RescueSystem
var pathfinder: Pathfinder
var events: SimEventLog
## 요구조자 id -> 남은 경로
var paths: Dictionary = {}
var trapped: Dictionary = {}
var escaped: Dictionary = {}

var _alert_ticks: int
var _clear_m: float
var _hot_c: float
var _speed: float


func _init(p_fire: FireSim, p_rescue: RescueSystem, p_pathfinder: Pathfinder, params: ParamTable, walk_speed_cells: float, p_events: SimEventLog) -> void:
	fire = p_fire
	rescue = p_rescue
	pathfinder = p_pathfinder
	events = p_events
	_alert_ticks = roundi(params.value("evac_alert_s") / SimClock.TICK_DT)
	_clear_m = params.value("evac_clear_m")
	_hot_c = params.value("evac_hot_c")
	_speed = walk_speed_cells * params.value("evac_speed_factor")


func step(dt: float, tick: int) -> void:
	for v in rescue.victims:
		if not v.self_evac or v.state != Victim.State.CONSCIOUS or v.carried_by >= 0 or escaped.has(v.id):
			continue
		var alert := roundi(v.alert_s / SimClock.TICK_DT) if v.alert_s >= 0.0 else _alert_ticks
		if tick < alert or trapped.has(v.id) and not paths.has(v.id):
			continue
		if not paths.has(v.id):
			var p := _exit_path(v)
			# 나갈 길이 이미 연기로 막혔으면 출발하지 않는다 (제자리 대피)
			if p.is_empty() or not p.all(_passable):
				_trap(v, tick)
				continue
			paths[v.id] = p
		_walk(v, dt, tick)


func _walk(v: Victim, dt: float, tick: int) -> void:
	var path: Array = paths[v.id]
	var budget := _speed * dt
	while budget > 0.0 and not path.is_empty():
		var wp: Vector3i = path[0]
		if not _passable(wp):
			_trap(v, tick)
			return
		trapped.erase(v.id)
		if wp.z != v.level:
			v.level = wp.z
			path.pop_front()
			continue
		var target := Vector2(wp.x + 0.5, wp.y + 0.5)
		var d := v.pos.distance_to(target)
		if d <= budget:
			v.pos = target
			budget -= d
			path.pop_front()
		else:
			v.pos += (target - v.pos) / d * budget
			budget = 0.0
	if fire.building.cell(v.level, floori(v.pos.x), floori(v.pos.y)) in BuildingData.OUTDOOR:
		escaped[v.id] = tick
		v.discovered = true
		v.state_at_rescue = Victim.State.CONSCIOUS
		v.state = Victim.State.RESCUED
		v.rescued_tick = tick
		events.add(tick, "victim_self_evac", {"who": v.label()})


## 연기층 아래 맑은 높이가 머리 높이보다 낮으면 지나가지 못한다
func _passable(cell: Vector3i) -> bool:
	var c := fire.compartment_at(cell.z, cell.x, cell.y)
	if c == null:
		return true
	return c.height - c.layer_depth >= _clear_m or c.t_upper < _hot_c


func _trap(v: Victim, tick: int) -> void:
	if trapped.has(v.id):
		return
	trapped[v.id] = tick
	var room := fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
	events.add(tick, "victim_trapped", {"who": v.label(), "room": room.display_name() if room else "", "crew": "현장 대원"})


## 가장 짧은 바깥 출입구 경로 (바깥 칸까지)
func _exit_path(v: Victim) -> Array:
	var start := Vector3i(floori(v.pos.x), floori(v.pos.y), v.level)
	var best: Array = []
	for o in fire.openings:
		if o.kind != Opening.Kind.DOOR or (o.room_a != Opening.OUTSIDE and o.room_b != Opening.OUTSIDE):
			continue
		var outside := _outside_of(o)
		if outside == Pathfinder.NO_CELL:
			continue
		var p := pathfinder.find_path(start, Vector3i(outside.x, outside.y, o.level))
		if not p.is_empty() and (best.is_empty() or p.size() < best.size()):
			best = p
	return best


func _outside_of(o: Opening) -> Vector2i:
	var c := o.cells[0]
	for d: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
		var n := c + d
		if fire.building.cell(o.level, n.x, n.y) in BuildingData.OUTDOOR and pathfinder.passable(o.level, n.x, n.y):
			return n
	return Pathfinder.NO_CELL
