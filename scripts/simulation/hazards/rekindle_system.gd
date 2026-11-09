class_name RekindleSystem
extends RefCounted
## 잔불정리·재발화 (SOP 202-6).
##   불씨: 물로 끈 셀에 연료가 남아 있으면 일정 확률로 불씨(심부 화재)가 숨는다. 겉으로는 꺼진 것처럼 보인다
##   확인 (6.1): 열화상카메라를 든 조장이 그 방에 들어가면 불씨를 찾아 표시한다
##   잔불정리 (6.2): 조가 방에 들어가 정해진 시간 동안 작업하면 그 방의 불씨가 모두 없어진다
##   재발화: 불씨를 그대로 두면 정해진 시간 뒤 그 셀에 다시 불이 붙는다
## 무작위 요소는 시나리오 시드에서 따로 만든 난수만 쓴다 (다른 화재 계산의 난수 순서를 바꾸지 않는다).

class Ember:
	extends RefCounted
	var cell := -1
	var room := -1
	var rekindle_tick := 0
	var spotted := false


class OverhaulTask:
	extends RefCounted
	var crew_id := -1
	var room := -1
	var remain := 0.0


var fire: FireSim
var units: UnitSystem
var pathfinder: Pathfinder
var events: SimEventLog
var embers: Array[Ember] = []
var tasks: Array[OverhaulTask] = []
## 평가용: 생긴 불씨 수, 재발화 수, 잔불정리로 없앤 불씨 수
var embers_created := 0
var rekindles := 0
var embers_cleared := 0

var _rng := RandomNumberGenerator.new()
var _chance: float
var _min_fuel: float
var _min_ticks: int
var _max_ticks: int
var _overhaul_water := 0.0
var _overhaul_damage := 0.0
var _vent_speedup := 0.0
## 잔불정리를 마친 순서 [{room, level, tick}] (평가: 위층 → 아래층)
var overhaul_order: Array[Dictionary] = []
var _overhaul_s: float
var _prev_burning := PackedInt32Array()


func _init(p_fire: FireSim, p_units: UnitSystem, p_pathfinder: Pathfinder, params: ParamTable, p_events: SimEventLog, p_seed: int) -> void:
	fire = p_fire
	units = p_units
	pathfinder = p_pathfinder
	events = p_events
	_rng.seed = hash([p_seed, "rekindle"])
	_chance = params.value("ember_chance")
	_min_fuel = params.value("ember_min_fuel_ratio")
	_min_ticks = roundi(params.value("rekindle_min_s") / SimClock.TICK_DT)
	_max_ticks = roundi(params.value("rekindle_max_s") / SimClock.TICK_DT)
	_overhaul_water = params.value("overhaul_water_l")
	_overhaul_damage = params.value("overhaul_damage_ratio")
	_vent_speedup = params.value("rekindle_vent_speedup")
	_overhaul_s = params.value("overhaul_s")


func overhaul_seconds() -> float:
	return _overhaul_s


## 조에게 잔불정리를 시킨다 (cell이 속한 방). 방이 아니면 false
func order_overhaul(crew_id: int, cell: Vector3i, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	var room := fire.compartment_at(cell.z, cell.x, cell.y)
	if c == null or room == null:
		return false
	cancel(crew_id)
	var t := OverhaulTask.new()
	t.crew_id = crew_id
	t.room = room.index
	t.remain = _overhaul_s
	tasks.append(t)
	var spot := pathfinder.nearest_walkable(cell.z, Vector2i(cell.x, cell.y))
	if spot != Pathfinder.NO_CELL:
		units.order_move([crew_id] as Array[int], Vector3i(spot.x, spot.y, cell.z), pathfinder)
	events.add(tick, "overhaul_start", {"crew": _crew_name(c), "room": room.display_name()})
	return true


func cancel(crew_id: int) -> void:
	tasks = tasks.filter(func(t: OverhaulTask) -> bool: return t.crew_id != crew_id)


func task_of_crew(crew_id: int) -> OverhaulTask:
	for t in tasks:
		if t.crew_id == crew_id:
			return t
	return null


## 찾아서 표시된 불씨 셀 (화면 표시용)
func spotted_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for e in embers:
		if e.spotted:
			out.append(fire.grid.cell_of(e.cell))
	return out


## 화재 계산 뒤: 물로 꺼진 셀에 불씨, 불씨 확인, 잔불정리 진행, 재발화
func step(dt: float, tick: int) -> void:
	var grid := fire.grid
	for i in _prev_burning:
		if grid.state[i] == FuelGrid.State.UNBURNED and grid.fuel[i] >= grid.fuel0[i] * _min_fuel and _rng.randf() < minf(1.0, _chance * grid.ember_factor[i]):
			_add_ember(i, tick)
	_prev_burning = grid.burning.duplicate()
	_spot(tick)
	_step_tasks(dt, tick)
	for e in embers.duplicate():
		# 환기(바깥으로 열린 창·문)로 산소가 들어오면 재발화가 빨라진다 (기획안 5-9)
		if _vent_speedup > 0.0 and e.room >= 0 and _vented(fire.comps[e.room]):
			e.rekindle_tick -= roundi(_vent_speedup)
		if tick < e.rekindle_tick:
			continue
		embers.erase(e)
		if grid.state[e.cell] != FuelGrid.State.UNBURNED:
			continue
		grid.wet[e.cell] = 0.0
		if grid.ignite(e.cell):
			rekindles += 1
			events.add(tick, "rekindle", {"room": fire.comps[e.room].display_name() if e.room >= 0 else ""})


func _add_ember(i: int, tick: int) -> void:
	for e in embers:
		if e.cell == i:
			return
	var e := Ember.new()
	e.cell = i
	var p := fire.grid.cell_of(i)
	var room := fire.compartment_at(p.z, p.x, p.y)
	e.room = room.index if room else -1
	e.rekindle_tick = tick + _rng.randi_range(_min_ticks, _max_ticks)
	embers.append(e)
	embers_created += 1


## 열화상카메라를 든 조장이 방 안에 있으면 그 방의 불씨를 찾는다 (6.1)
func _spot(tick: int) -> void:
	if embers.is_empty() or tick % 5 != 0:
		return
	for c in units.crews:
		if not c.thermal_camera or c.leader.incapacitated:
			continue
		var room := fire.compartment_at(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y))
		if room == null:
			continue
		var found := 0
		for e in embers:
			if e.room == room.index and not e.spotted:
				e.spotted = true
				found += 1
		if found > 0:
			events.add(tick, "ember_spotted", {"crew": _crew_name(c), "room": room.display_name(), "count": found})


func _step_tasks(dt: float, tick: int) -> void:
	for t in tasks.duplicate():
		var c := units.get_crew(t.crew_id)
		var lead := c.leader
		if lead.incapacitated:
			tasks.erase(t)
			continue
		var room := fire.compartment_at(lead.level, floori(lead.pos.x), floori(lead.pos.y))
		if room == null or room.index != t.room or lead.is_moving():
			continue
		t.remain -= dt
		if t.remain > SimClock.EPSILON:
			continue
		tasks.erase(t)
		var n := 0
		for e in embers.duplicate():
			if e.room == t.room:
				embers.erase(e)
				n += 1
		embers_cleared += n
		fire.comps[t.room].overhauled_tick = tick
		# 감압 주수 물 → 수손 (과잉주수 지양, 화재1 262쪽)
		fire.comps[t.room].water_applied_l += _overhaul_water
		fire.comps[t.room].water_damage_l += _overhaul_water * _overhaul_damage
		overhaul_order.append({"room": room.display_name(), "level": room.level, "tick": tick})
		events.add(tick, "overhaul_done", {"crew": _crew_name(c), "room": room.display_name(), "embers": n})


func _vented(c: Compartment) -> bool:
	for oi in c.openings:
		var o: Opening = fire.openings[oi]
		if (o.is_open or o.broken) and (o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE):
			return true
	return false


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]
