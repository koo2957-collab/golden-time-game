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
## 지휘관의 주민 대피 방송 (SOP 213-2.4.2): "" 없음 / "shelter" 세대 안 대기·문 닫기 / "evacuate" 지금 바로 대피
var instruction := ""
## 갇힌 사람의 119 신고 대기 [{victim, due}] — 신고가 상황실을 거쳐 무전으로 들어온다
var calls: Array[Dictionary] = []
var _call_ticks := 450

var _alert_ticks: int
var _clear_m: float
var _hot_c: float
var _speed: float
## 피난안전구역 (초고층, SOP 223, R14): 이 층보다 위의 자력 대피자는 이 층 refuge_cell로 간다. -1이면 없음
var refuge_level := -1
var refuge_cell := Vector2i(-1, -1)
var _o2_slow := 18.0
var _o2_stop := 10.0
var _o2_factor := 0.5
## 대피 안내 순서 (질문 카드 EVAC-ORDER-01, SOP 213-2.4.1): "" 안내 없음 · fire_first 발화층·직상층 먼저 · bottom_up 1층부터
var priority := ""
var priority_tick := -1
var fire_level := -1
var _floor_guide_ticks := 450


func _init(p_fire: FireSim, p_rescue: RescueSystem, p_pathfinder: Pathfinder, params: ParamTable, walk_speed_cells: float, p_events: SimEventLog) -> void:
	fire = p_fire
	rescue = p_rescue
	pathfinder = p_pathfinder
	events = p_events
	_alert_ticks = roundi(params.value("evac_alert_s") / SimClock.TICK_DT)
	_clear_m = params.value("evac_clear_m")
	_hot_c = params.value("evac_hot_c")
	_speed = walk_speed_cells * params.value("evac_speed_factor")
	_o2_slow = params.value("o2_slow_pct")
	_o2_stop = params.value("o2_immobile_pct")
	_o2_factor = params.value("o2_slow_factor")
	_call_ticks = roundi(params.value("evac_call_delay_s") / SimClock.TICK_DT)
	_floor_guide_ticks = roundi(params.value("evac_floor_guide_s") / SimClock.TICK_DT)


## 대피 안내 순서를 정한다. 발화층·직상층 먼저면 그 층 주민이 곧바로 나서고,
## 1층부터면 대원이 층마다 돌며 안내하므로 위층일수록 늦게 안다
func set_priority(p: String, p_fire_level: int, tick: int) -> void:
	priority = p
	priority_tick = tick
	fire_level = p_fire_level
	events.add(tick, "evac_priority", {"order": "발화층·직상층 먼저" if p == "fire_first" else "1층부터 차례로"})


## 이 자력 대피자가 움직이기 시작하는 틱
func _alert_tick(v: Victim) -> int:
	var alert := roundi(v.alert_s / SimClock.TICK_DT) if v.alert_s >= 0.0 else _alert_ticks
	if priority_tick < 0:
		return alert
	match priority:
		"fire_first":
			if v.level == fire_level or v.level == fire_level + 1:
				return mini(alert, priority_tick)
			# 발화층·직상층을 마친 뒤 나머지 층
			return mini(alert, priority_tick + 2 * _floor_guide_ticks + absi(v.level - fire_level) * _floor_guide_ticks)
		"bottom_up":
			# 안내가 그 층에 닿아야 나선다 (스스로 알아차렸어도 위층은 늦은 안내를 기다린다)
			return maxi(alert, priority_tick + (v.level - 1) * _floor_guide_ticks)
	return alert


func step(dt: float, tick: int) -> void:
	_step_calls(tick)
	for v in rescue.victims:
		if not v.self_evac or v.state != Victim.State.CONSCIOUS or v.carried_by >= 0 or escaped.has(v.id):
			continue
		var alert := _alert_tick(v)
		if instruction == "evacuate":
			alert = 0
		# 세대 안 대기 안내를 받으면 아직 나서지 않은 사람은 그 자리에서 기다린다
		if instruction == "shelter" and not paths.has(v.id):
			continue
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
	# 산소가 부족하면 느려지고, 10% 이하면 스스로 움직이지 못한다 (교재 화재2 산소농도별 영향)
	var o2 := o2_percent(v)
	if o2 <= _o2_stop:
		return
	var budget := _speed * dt * (_o2_factor if o2 < _o2_slow else 1.0)
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
	var at_refuge := refuge_level > 0 and v.level == refuge_level and v.pos.distance_to(Vector2(refuge_cell) + Vector2(0.5, 0.5)) <= 1.5
	if at_refuge:
		events.add(tick, "victim_refuge", {"who": v.label(), "floor": fire.building.floor_name(refuge_level)})
	if at_refuge or fire.building.cell(v.level, floori(v.pos.x), floori(v.pos.y)) in BuildingData.OUTDOOR:
		escaped[v.id] = tick
		v.discovered = true
		v.state_at_rescue = Victim.State.CONSCIOUS
		v.state = Victim.State.RESCUED
		v.rescued_tick = tick
		events.add(tick, "victim_self_evac", {"who": v.label()})


## 연기층 아래 맑은 높이가 머리 높이보다 낮으면 지나가지 못한다
## 119 신고 전달: 아직 갇혀 있고 대원이 찾지 못했으면 상황실이 세대·층만 알린다 (방·정확한 위치는 대원이 찾아야 안다)
func _step_calls(tick: int) -> void:
	for c in calls.duplicate():
		if tick < int(c.due):
			continue
		calls.erase(c)
		var v := rescue.victims[int(c.victim)]
		if v.discovered or not v.alive() or not trapped.has(v.id) or escaped.has(v.id):
			continue
		var room := fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
		var name := room.display_name() if room else fire.building.floor_name(v.level)
		var unit := name.substr(0, name.find("호") + 1) if name.find("호") > 0 else fire.building.floor_name(v.level)
		events.add(tick, "victim_trapped", {"unit": unit, "level": v.level, "who": "주민", "crew": "119종합상황실"})


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
	# 아무도 보지 못한 일이다: 시뮬레이션 기록만 남기고(디브리핑), 지휘관에게는 119 신고가 상황실을 거쳐 들어온다
	events.add(tick, "evac_trapped", {"who": v.label(), "room": room.display_name() if room else ""})
	if v.phone and v.state == Victim.State.CONSCIOUS and v.age >= 10:
		calls.append({"victim": v.id, "due": tick + _call_ticks})


## 가장 짧은 바깥 출입구 경로 (바깥 칸까지)
func _exit_path(v: Victim) -> Array:
	var start := Vector3i(floori(v.pos.x), floori(v.pos.y), v.level)
	if refuge_level > 0 and v.level > refuge_level:
		return pathfinder.find_path(start, Vector3i(refuge_cell.x, refuge_cell.y, refuge_level))
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


## 요구조자가 있는 방의 산소 농도(부피 %, 연기층 안이면 상부층 기준 — 질량분율을 대기 20.9%에 비례해 바꾼다)
func o2_percent(v: Victim) -> float:
	var c := fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
	if c == null:
		return 20.9
	return 20.9 * c.y_o2 / Compartment.O2_AMBIENT_MASS
