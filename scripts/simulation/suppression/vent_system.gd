class_name VentSystem
extends RefCounted
## 송풍기 양압배연 (기획안 P3·R11, 소방전술 화재1 배연전술 — 양압배연): 진압대 조가 바깥 출입문 앞에 송풍기를 놓으면
## 그 문으로 바람을 넣어 같은 층의 열린 문으로 이어진 구획의 연기를 배출구(깨진·열린 창, 다른 열린 바깥 문)로 밀어낸다.
##   - 배출구가 없으면 연기가 빠지지 않는다 (배출구 먼저 확보) → "배출구 없음" 보고
##   - 바람길에 타는 구획이 있으면 불이 배출구 쪽으로 커질 수 있다 → "화점이 바람길에 있음" 경고 (배출구 위치·요구조자 확인)
##   - 송풍기를 놓은 조는 그 자리를 지킨다 (다른 명령을 주면 송풍기를 끈다)
## 수치는 data/fire/fire_params.json (ppv_*)

var fire: FireSim
var units: UnitSystem
var events: SimEventLog
## 송풍기를 놓은 바깥 문 (개구부 index, -1 = 없음)
var opening := -1
var crew_id := -1
var active := false
var _tau_s: float
var _cool_factor: float
var _o2_boost: float
var _warned_exhaust := false
var _warned_fire := false
var _pending := false


func _init(p_fire: FireSim, p_units: UnitSystem, config: FireConfig, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	events = p_events
	_tau_s = config.value("ppv_clear_tau_s")
	_cool_factor = config.value("ppv_cool_per_s")
	_o2_boost = config.value("ppv_fire_o2_boost")


## 송풍기 설치 지시 (EquipmentCommand "ppv"): 바깥 문 칸. 조가 문 밖 칸으로 가서 켠다
func order(p_crew: int, target: Vector3i, pathfinder: Pathfinder, tick: int) -> bool:
	var o := fire.opening_at(target)
	if o == null or o.kind != Opening.Kind.DOOR or o.room_b != Opening.OUTSIDE:
		events.add(tick, "ppv_no_door", {"crew": _crew_name(p_crew)})
		return false
	cancel(p_crew, tick, false)
	opening = o.index
	crew_id = p_crew
	active = false
	_pending = true
	_warned_exhaust = false
	_warned_fire = false
	var spot := _outside_cell(o)
	units.order_move([p_crew] as Array[int], Vector3i(spot.x, spot.y, o.level), pathfinder)
	return true


func cancel(p_crew: int, tick: int, report := true) -> void:
	if p_crew != crew_id or opening < 0:
		return
	if active and report:
		events.add(tick, "ppv_stop", {"crew": _crew_name(crew_id)})
	opening = -1
	crew_id = -1
	active = false
	_pending = false


func step(dt: float, tick: int) -> void:
	if opening < 0:
		return
	var o: Opening = fire.openings[opening]
	var c := units.get_crew(crew_id)
	if c == null or c.leader.incapacitated:
		cancel(crew_id, tick)
		return
	if _pending:
		var spot := _outside_cell(o)
		if c.leader.pos.distance_to(Vector2(spot) + Vector2(0.5, 0.5)) <= 1.5 and not c.leader.is_moving():
			_pending = false
			active = true
			events.add(tick, "ppv_start", {"crew": _crew_name(crew_id), "room": fire.comps[o.room_a].display_name()})
		return
	if not active or not o.is_open:
		return
	var rooms := _connected(o)
	var exhaust := _has_exhaust(rooms, o)
	if not exhaust:
		if not _warned_exhaust:
			_warned_exhaust = true
			events.add(tick, "ppv_no_exhaust", {"crew": _crew_name(crew_id)})
		return
	var k := 1.0 - exp(-dt / _tau_s)
	for r: int in rooms:
		var comp: Compartment = fire.comps[r]
		comp.soot *= 1.0 - k
		comp.layer_depth *= 1.0 - k
		comp.t_upper = maxf(comp.t_lower, comp.t_upper - (comp.t_upper - comp.t_lower) * _cool_factor * dt)
		if comp.q > 0.0:
			# 신선한 공기가 들어가 불이 배출구 쪽으로 커진다
			comp.y_o2 = minf(Compartment.O2_AMBIENT_MASS, comp.y_o2 + _o2_boost * dt)
			if not _warned_fire:
				_warned_fire = true
				events.add(tick, "ppv_fire_push", {"crew": _crew_name(crew_id), "room": comp.display_name()})


## 송풍기 문에서 같은 층의 열린 문으로 이어진 구획
func _connected(o: Opening) -> Array[int]:
	var out: Array[int] = [o.room_a]
	var i := 0
	while i < out.size():
		var r: int = out[i]
		i += 1
		for oi in fire.comps[r].openings:
			var op: Opening = fire.openings[oi]
			if op.kind != Opening.Kind.DOOR or not op.is_open or op.room_b == Opening.OUTSIDE:
				continue
			var n := op.other_side(r)
			if n != Opening.OUTSIDE and not n in out and fire.comps[n].level == o.level:
				out.append(n)
	return out


## 배출구: 바람길 구획의 깨지거나 열린 창, 또는 송풍기 문이 아닌 열린 바깥 문
func _has_exhaust(rooms: Array[int], intake: Opening) -> bool:
	for r in rooms:
		for oi in fire.comps[r].openings:
			var op: Opening = fire.openings[oi]
			if op.index == intake.index or op.room_b != Opening.OUTSIDE:
				continue
			if (op.kind == Opening.Kind.WINDOW and (op.broken or op.is_open)) or (op.kind == Opening.Kind.DOOR and op.is_open):
				return true
	return false


func _outside_cell(o: Opening) -> Vector2i:
	var c: Vector2i = o.cells[0]
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = c + d * 2
		if fire.building.in_bounds(n.x, n.y) and fire.building.cell(o.level, n.x, n.y) in BuildingData.OUTDOOR:
			return n
	return c


func _crew_name(id: int) -> String:
	var c := units.get_crew(id)
	return "%s %d조" % [units.squads[c.squad_id].name, c.number] if c else "송풍기"
