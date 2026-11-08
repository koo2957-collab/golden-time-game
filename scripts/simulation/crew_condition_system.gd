class_name CrewConditionSystem
extends RefCounted
## 대원 상태: 자세, 복사열, 열 스트레스, 공기호흡기, 행동 불능, 열기에 따른 접근 제한.
## - 연기층이 서 있는 눈높이보다 내려오면 낮은 자세 (느려지고, 고온층 복사를 덜 받는다. SOP 201-3.3)
## - 복사열 = 천장 고온층 복사 + 주변 화염 복사 (kW/㎡)
## - 다음 칸이 위험 상한(heat_hazard) 이상이면 더 다가가지 않고, 지금 칸이 그러면 물러난다
## - 열 스트레스가 쌓여 1이 되거나, 건물 안에서 공기가 떨어지면 행동 불능
## - 바깥 차량 근처에 멈춰 있으면 공기호흡기 용기를 교체한다

const STEFAN_BOLTZMANN := 5.67e-11
## 화염 복사를 더할 범위 (셀)
const FLAME_RANGE_CELLS := 8.0
## 같은 조에 같은 열기 알림을 다시 띄우기까지의 틱
const HEAT_EVENT_COOLDOWN_TICKS := 100
## 물러날 곳을 찾을 때 살펴볼 최대 셀 수
const RETREAT_SEARCH_LIMIT := 600

var fire: FireSim
var units: UnitSystem
var pathfinder: Pathfinder
var events: SimEventLog

var _t_amb: float
var _cell_m: float
var _eye_stand: float
var _eye_crouch: float
var _crouch_speed: float
var _routine: float
var _hazard: float
var _stress_s: float
var _recovery_s: float
var _radiant: float
var _air_alarm: float
var _air_rest: float
var _air_search: float
var _air_work: float
var _air_heavy: float
var _air_tension: float
var _air_control: float
var _detour: float
var _walk_cells: float
## 대원의 활동 단계 (0 대기·보행, 1 수색·호스 전개, 2 방수·파괴, 3 구조·계단). SimWorld가 넣는다
var activity_of := Callable()
## 긴급탈출 상황인가 (긴장 배율). SimWorld가 넣는다
var emergency := Callable()
## 출구 칸 목록 (출구까지 필요 공기). SimWorld가 넣는다
var exits := Callable()
var _exits_now: Array = []
var _swap_s: float
## 예비 공기용기를 실었으면 0.5 (출동 준비, R10)
var swap_scale := 1.0
var _swap_range: float
var _air_full := 0.0
var _heat_event_tick: Dictionary = {}  # "종류:조" -> tick


func _init(p_fire: FireSim, p_units: UnitSystem, p_pathfinder: Pathfinder, stats: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	pathfinder = p_pathfinder
	events = p_events
	_t_amb = fire.config.value("ambient_temp_c")
	_cell_m = fire.building.cell_size_m
	_eye_stand = stats.value("eye_height_standing_m")
	_eye_crouch = stats.value("eye_height_crouched_m")
	_crouch_speed = stats.value("crouch_speed_factor")
	_routine = stats.value("heat_routine_kw_m2")
	_hazard = stats.value("heat_hazard_kw_m2")
	_stress_s = stats.value("heat_stress_seconds_at_hazard")
	_recovery_s = stats.value("heat_recovery_seconds")
	_radiant = stats.value("flame_radiant_fraction")
	_air_alarm = stats.value("scba_alarm_ratio")
	_air_rest = stats.value("air_use_rest_lpm")
	_air_search = stats.value("air_use_search_lpm")
	_air_work = stats.value("air_use_work_lpm")
	_air_heavy = stats.value("air_use_heavy_lpm")
	_air_tension = stats.value("air_tension_factor")
	_air_control = stats.value("air_control_factor")
	_detour = stats.value("exit_detour_factor")
	# (_cell_m은 위에서 읽었다)
	_walk_cells = stats.value("walk_speed_mps") / _cell_m
	_swap_s = stats.value("scba_swap_s")
	_swap_range = stats.value("scba_swap_range_m") / _cell_m
	_air_full = stats.value("scba_air_l")
	for ff in units.firefighters:
		init_member(ff)


## 새로 도착한 대원의 공기호흡기를 채운다
func init_member(ff: Firefighter) -> void:
	ff.air_capacity = _air_full
	ff.air_l = _air_full


func hazard_kw_m2() -> float:
	return _hazard


## 이 셀에 선 대원이 받는 복사열 (kW/㎡)
func heat_at(level: int, cell: Vector2i, crouched: bool) -> float:
	var q := 0.0
	var c := _room_for(level, cell)
	if c:
		var eye := _eye_crouch if crouched else _eye_stand
		var tk := c.t_upper + 273.0
		var ta := _t_amb + 273.0
		var layer := STEFAN_BOLTZMANN * (tk * tk * tk * tk - ta * ta * ta * ta) * clampf(c.layer_depth / c.height, 0.0, 1.0)
		q += layer * (1.0 if eye >= c.height - c.layer_depth else 0.5)
	# 화염 복사는 벽을 통과하지 않는다: 같은 구획(문 칸이면 맞닿은 구획들)의 화염만 더한다
	var rooms := _rooms_around(level, cell)
	if rooms.is_empty():
		return q
	var grid := fire.grid
	var center := Vector2(cell) + Vector2(0.5, 0.5)
	var range_sq := FLAME_RANGE_CELLS * FLAME_RANGE_CELLS
	for i in grid.burning:
		var p := grid.cell_of(i)
		if p.z != level:
			continue
		var r: int = grid.room[i]
		if r >= 0:
			if not r in rooms:
				continue
		elif not _door_touches(grid, i, rooms):
			continue
		var dist_sq := center.distance_squared_to(Vector2(p.x + 0.5, p.y + 0.5))
		if dist_sq > range_sq:
			continue
		var d := maxf(0.5, sqrt(dist_sq) * _cell_m)
		q += grid.hrr[i] * _radiant / (4.0 * PI * d * d)
	return q


## 걸어 들어가도 되는 칸인지 (열화상·방수 위치 선정 등에 쓴다)
func safe_to_enter(level: int, cell: Vector2i) -> bool:
	return heat_at(level, cell, true) < _hazard


## 이동 전: 다음 칸이 위험하면 멈추고, 지금 칸이 위험하면 물러난다.
func before_move(tick: int) -> void:
	for c in units.crews:
		var leader := c.leader
		if leader.incapacitated:
			continue
		var here := Vector2i(leader.pos.floor())
		if heat_at(leader.level, here, leader.crouched) >= _hazard:
			_retreat(c, tick)
			continue
		if leader.path.is_empty():
			continue
		var wp := leader.path[0]
		if wp.z != leader.level or Vector2i(wp.x, wp.y) == here:
			continue
		if heat_at(wp.z, Vector2i(wp.x, wp.y), leader.crouched) >= _hazard:
			leader.path.clear()
			if c.partner:
				c.partner.path.clear()
			_heat_event(c, "heat_blocked", tick)


## 이동 후: 자세·복사열·열 스트레스·공기호흡기·용기 교체·행동 불능
func after_move(dt: float, tick: int) -> void:
	_exits_now = exits.call() if exits.is_valid() else []
	for ff in units.firefighters:
		if ff.incapacitated:
			continue
		var cell := Vector2i(ff.pos.floor())
		var room := _room_for(ff.level, cell)
		ff.crouched = room != null and room.layer_depth > room.height - _eye_stand
		ff.crouch_factor = _crouch_speed if ff.crouched else 1.0
		ff.heat_flux = heat_at(ff.level, cell, ff.crouched)
		_update_heat_stress(ff, dt)
		_update_air(ff, room != null, dt, tick)
		if ff.heat_stress >= 1.0:
			_down(ff, "열 스트레스", tick)
		elif room != null and ff.air_l <= 0.0:
			_down(ff, "공기 소진", tick)


func _update_heat_stress(ff: Firefighter, dt: float) -> void:
	if ff.heat_flux > _routine:
		ff.heat_stress += dt * ff.heat_factor * (ff.heat_flux - _routine) / (_hazard - _routine) / _stress_s
	else:
		ff.heat_stress = maxf(0.0, ff.heat_stress - dt / _recovery_s)


func _update_air(ff: Firefighter, inside: bool, dt: float, tick: int) -> void:
	if inside:
		var lpm := air_rate(ff)
		ff.air_l = maxf(0.0, ff.air_l - lpm * ff.air_factor / 60.0 * dt)
		_update_exit_air(ff, lpm, tick)
		ff.swap_timer = 0.0
		if ff.air_ratio() < _air_alarm and not ff.air_alarm_logged:
			ff.air_alarm_logged = true
			events.add(tick, "air_alarm", {"crew": _ff_name(ff), "crew_id": ff.crew_id})
		return
	# 바깥: 출구 공기 계산을 끄고, 차량 근처에 멈춰 있으면 용기 교체
	ff.exit_air_l = 0.0
	ff.exit_air_logged = false
	if ff.air_ratio() >= 0.95 or ff.is_moving() or not _near_vehicle(ff.pos):
		ff.swap_timer = 0.0
		return
	ff.swap_timer += dt
	if ff.swap_timer >= _swap_s * swap_scale:
		ff.air_l = ff.air_capacity
		ff.air_alarm_logged = false
		ff.swap_timer = 0.0
		events.add(tick, "scba_swapped", {"crew": _ff_name(ff)})


func _near_vehicle(p: Vector2) -> bool:
	for v in units.vehicles:
		if v.distance_to_body(p) <= _swap_range:
			return true
	return false


func _down(ff: Firefighter, reason: String, tick: int) -> void:
	ff.incapacitated = true
	ff.path.clear()
	events.add(tick, "ff_down", {"crew": _ff_name(ff), "reason": reason})


## 지금 칸이 위험하면 위험 상한의 60% 아래인 가장 가까운 칸으로 물러난다.
func _retreat(c: Crew, tick: int) -> void:
	var leader := c.leader
	var start := Vector2i(leader.pos.floor())
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	var head := 0
	while head < queue.size() and head < RETREAT_SEARCH_LIMIT:
		var p := queue[head]
		head += 1
		if heat_at(leader.level, p, true) < _hazard * 0.6:
			if p != start:
				units.order_move([c.id] as Array[int], Vector3i(p.x, p.y, leader.level), pathfinder)
				_heat_event(c, "heat_retreat", tick)
			return
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var n := p + d
			if not seen.has(n) and pathfinder.passable(leader.level, n.x, n.y):
				seen[n] = true
				queue.append(n)


func _heat_event(c: Crew, type: String, tick: int) -> void:
	var key := "%s:%d" % [type, c.id]
	if tick - int(_heat_event_tick.get(key, -HEAT_EVENT_COOLDOWN_TICKS)) < HEAT_EVENT_COOLDOWN_TICKS:
		return
	_heat_event_tick[key] = tick
	events.add(tick, type, {"crew": _crew_name(c)})


## 셀에서 화염 복사를 받는 구획들 (방 안이면 그 방, 문 칸이면 양쪽 방, 바깥이면 없음)
func _rooms_around(level: int, cell: Vector2i) -> PackedInt32Array:
	var c := fire.compartment_at(level, cell.x, cell.y)
	if c:
		return PackedInt32Array([c.index])
	var out := PackedInt32Array()
	if fire.building.cell(level, cell.x, cell.y) == BuildingData.Cell.DOOR:
		var o := fire.opening_at(Vector3i(cell.x, cell.y, level))
		if o:
			out.append(o.room_a)
			if o.room_b != Opening.OUTSIDE:
				out.append(o.room_b)
	return out


## 타는 문 칸이 rooms 중 하나에 맞닿아 있는지
static func _door_touches(grid: FuelGrid, i: int, rooms: PackedInt32Array) -> bool:
	for r in grid.door_rooms.get(i, PackedInt32Array()):
		if r in rooms:
			return true
	return false


## 셀이 속한 구획. 문 칸이면 맞닿은 구획 중 더 뜨거운 쪽.
func _room_for(level: int, cell: Vector2i) -> Compartment:
	var c := fire.compartment_at(level, cell.x, cell.y)
	if c:
		return c
	if fire.building.cell(level, cell.x, cell.y) != BuildingData.Cell.DOOR:
		return null
	var o := fire.opening_at(Vector3i(cell.x, cell.y, level))
	if o == null:
		return null
	var a := fire.comps[o.room_a]
	if o.room_b == Opening.OUTSIDE:
		return a
	var b := fire.comps[o.room_b]
	return a if a.t_upper >= b.t_upper else b


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]


func _ff_name(ff: Firefighter) -> String:
	return "%s %d조 %s" % [units.squads[ff.squad_id].name, units.get_crew(ff.crew_id).number, ff.name]


# --- 호흡량·출구까지 필요 공기 (R9, 기획안 5-6) ---

## 분당 호흡량: 활동 4단계 × 긴장(고열·긴급탈출) × 호흡조절(경보 뒤)
func air_rate(ff: Firefighter) -> float:
	var level := int(activity_of.call(ff)) if activity_of.is_valid() else (1 if ff.is_moving() else 0)
	var lpm: float = [_air_rest, _air_search, _air_work, _air_heavy][clampi(level, 0, 3)]
	if ff.heat_flux >= _hazard * 0.5 or (emergency.is_valid() and bool(emergency.call())):
		lpm *= _air_tension
	if ff.air_alarm_logged:
		lpm *= _air_control
	return lpm


## 출구까지 필요 공기(ℓ): 가장 가까운 출구까지(직선 × 우회 배율, 층마다 계단 6칸) 지금 호흡량으로 걸어 나가는 동안 쓰는 양.
## 남은 공기에서 이만큼 쓰면 경보 압력 아래로 내려가면 "퇴각 건의"를 보고한다 (기획안 5-6, 교재: 탈출경로가 길면 경보 전에 나와야)
func _update_exit_air(ff: Firefighter, lpm: float, tick: int) -> void:
	var best := INF
	for e: Vector3i in _exits_now:
		var d := ff.pos.distance_to(Vector2(e.x + 0.5, e.y + 0.5)) * _detour + absi(e.z - ff.level) * 6.0
		best = minf(best, d)
	if best == INF:
		return
	var seconds := best / maxf(0.1, _walk_cells * ff.crouch_factor)
	ff.exit_air_l = lpm * seconds / 60.0
	var alarm_l := ff.air_capacity * _air_alarm
	if not ff.exit_air_logged and not ff.air_alarm_logged and ff.air_l - ff.exit_air_l <= alarm_l:
		ff.exit_air_logged = true
		events.add(tick, "exit_air_low", {"crew": _ff_name(ff), "crew_id": ff.crew_id,
			"need_bar": roundi(ff.exit_air_l / ff.air_capacity * 300.0), "air_bar": roundi(ff.air_ratio() * 300.0)})
