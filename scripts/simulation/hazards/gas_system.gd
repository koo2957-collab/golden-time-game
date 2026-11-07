class_name GasSystem
extends RefCounted
## 난방연료(가스) 차단 (SOP 214-2.2). 시나리오 site.gas: 밸브 위치, 가스레인지 칸, 구획.
##   밸브가 열려 있으면 가스레인지 칸이 꺼져도 정해진 간격으로 다시 불붙는다 (가스 화염이 계속 공급됨)
##   열린 채로 그 구획이 플래시오버에 이르면 가스 폭발: 안의 대원 행동 불능, 구획 전체 착화 (214-2.3 가스 폭발 유의)
##   조가 밸브에 가서 정해진 시간 작업하면 차단된다

var fire: FireSim
var units: UnitSystem
var pathfinder: Pathfinder
var events: SimEventLog
## 밸브 칸 (-1이면 가스 없음)
var valve := Vector2i(-1, -1)
var valve_text := "가스 밸브"
var stove := Vector3i(-1, -1, 1)
var room := -1
var open := false
var closed_tick := -1
var exploded := false
## 차단하러 간 조 id -> 남은 작업 초
var workers: Dictionary = {}

var _reignite_ticks: int
var _off_s: float
var _next_reignite := 0


func _init(p_fire: FireSim, p_units: UnitSystem, p_pathfinder: Pathfinder, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	pathfinder = p_pathfinder
	events = p_events
	_reignite_ticks = roundi(params.value("gas_reignite_s") / SimClock.TICK_DT)
	_off_s = params.value("gas_off_s")


func apply_scenario(data: Dictionary) -> void:
	var g: Dictionary = data.get("site", {}).get("gas", {})
	if g.is_empty():
		return
	var v: Array = g.get("valve", [-1, -1])
	valve = Vector2i(int(v[0]), int(v[1]))
	var s: Array = g.get("stove", [-1, -1, 1])
	stove = Vector3i(int(s[0]), int(s[1]), int(s[2]) if s.size() > 2 else 1)
	var c := fire.compartment_at(stove.z, stove.x, stove.y)
	room = c.index if c else -1
	valve_text = str(g.get("text", valve_text))
	open = true


func has_gas() -> bool:
	return valve.x >= 0


## 지휘관이 가스 시설을 알고 있는가 (면 정보·진술로 위험물(가스 등)을 확인함). 밸브 표시·우클릭에 쓴다
func known(survey: SiteSurvey) -> bool:
	if not has_gas():
		return false
	for h in survey.known_hazards():
		if h.contains("가스"):
			return true
	return false


func valve_near(cell: Vector2, radius := 1.5) -> bool:
	return has_gas() and cell.distance_to(Vector2(valve) + Vector2(0.5, 0.5)) <= radius


func order_off(crew_id: int, tick: int) -> bool:
	if not open or units.get_crew(crew_id) == null:
		return false
	var spot := pathfinder.nearest_walkable(1, valve)
	if spot == Pathfinder.NO_CELL:
		return false
	workers[crew_id] = _off_s
	units.order_move([crew_id] as Array[int], Vector3i(spot.x, spot.y, 1), pathfinder)
	events.add(tick, "gas_off_start", {"crew": _crew_name(units.get_crew(crew_id))})
	return true


func cancel(crew_id: int) -> void:
	workers.erase(crew_id)


func step(dt: float, tick: int) -> void:
	if not has_gas():
		return
	for id: int in workers.keys():
		var c := units.get_crew(id)
		if c.leader.incapacitated or c.leader.is_moving() or c.leader.pos.distance_to(Vector2(valve) + Vector2(0.5, 0.5)) > 2.0:
			continue
		workers[id] -= dt
		if workers[id] <= 0.0:
			workers.clear()
			open = false
			closed_tick = tick
			events.add(tick, "gas_shutoff", {"crew": _crew_name(c), "what": valve_text})
			break
	if not open or room < 0:
		return
	var comp := fire.comps[room]
	# 가스 화염 공급: 구획에 불이 난 적이 있으면 가스레인지 칸을 다시 붙인다
	if comp.ever_burned and tick >= _next_reignite:
		_next_reignite = tick + _reignite_ticks
		var i := fire.grid.index(stove.z, stove.x, stove.y)
		if fire.grid.state[i] == FuelGrid.State.UNBURNED:
			fire.grid.wet[i] = 0.0
			fire.grid.ignite(i, 0.5)
	if comp.flashed and not exploded:
		exploded = true
		for ff in units.firefighters:
			if ff.incapacitated:
				continue
			var r := fire.compartment_at(ff.level, floori(ff.pos.x), floori(ff.pos.y))
			if r == comp:
				ff.incapacitated = true
				ff.path.clear()
				events.add(tick, "ff_down", {"crew": "%s %s" % [_crew_name(units.get_crew(ff.crew_id)), ff.name], "reason": "가스 폭발"})
		fire.grid.ignite_room(room, 0.8)
		events.add(tick, "gas_explosion", {"room": comp.display_name(), "crew": "현장 대원"})


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]
