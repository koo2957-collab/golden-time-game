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
const RETREAT_SEARCH_LIMIT := 1500

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
## 엄호 주수 안인가 (level, pos) -> bool. SimWorld가 넣는다 (R11)
var covered := Callable()
## 열기에 막히거나 밀려난 조가 하던 임무를 멈춘다 (crew, tick, 종류 "blocked"·"retreat") -> 멈춘 임무가 있었는가. SimWorld가 넣는다
## (2026-11-24 — 인명검색·구조가 1초마다 다시 길을 잡아 문턱에서 왔다 갔다 했고, 물러난 뒤에도 되돌아왔다)
var on_heat_stop := Callable()
var _cover_factor := 0.5
var _exits_now: Array = []
var _swap_s: float
## 예비 공기용기를 실었으면 0.5 (출동 준비, R10)
var swap_scale := 1.0
var _swap_range: float
var _air_full := 0.0
var _heat_event_tick: Dictionary = {}  # "종류:조" -> tick
## 열 스트레스가 이만큼 쌓이면 임무 없는 분대는 식힐 곳으로 물러나고 보고한다 (임무 중이면 보고만)
var _stress_retreat := 0.5
## 물러나는 조의 목적지 {crew id: 길 끝 칸}
var _retreat_goal: Dictionary = {}
## 퇴로 차단 (2026-11-25): 열기에 길이 막히기 시작한 틱 {crew id: tick} · 막힌 마지막 틱 · 고립을 보고한 조 {crew id: tick}
var _blocked_since: Dictionary = {}
var _blocked_last: Dictionary = {}
var _trapped: Dictionary = {}
var _trapped_ticks := 300
## 물러날 곳 찾기 (2026-11-25): 식은 곳을 못 찾은 틱 {crew id: tick} · 마지막 탐색의 결과 (식은 곳을 찾았는가 · 열기를 뚫는 길인가 · 지나온 칸)
var _retreat_wait: Dictionary = {}
var _cool_found := false
var _cool_through := false
var _cool_parent: Dictionary = {}
## 식은 곳이 없을 때 덜 뜨거운 곳으로 옮기는 기준 · 막혔던 길이 다시 열렸다고 보는 기준 (data/units/firefighter.json)
var _cooler_ratio := 0.5
var _reopen_ratio := 0.8


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
	_cover_factor = stats.value("cover_heat_factor")
	_stress_retreat = stats.value("heat_stress_retreat_ratio")
	# (_cell_m은 위에서 읽었다)
	_walk_cells = stats.value("walk_speed_mps") / _cell_m
	_swap_s = stats.value("scba_swap_s")
	_swap_range = stats.value("scba_swap_range_m") / _cell_m
	_air_full = stats.value("scba_air_l")
	_trapped_ticks = roundi((stats.value("trapped_report_s") if stats.params.has("trapped_report_s") else 30.0) / SimClock.TICK_DT)
	if stats.params.has("retreat_cooler_ratio"):
		_cooler_ratio = stats.value("retreat_cooler_ratio")
	if stats.params.has("path_reopen_heat_ratio"):
		_reopen_ratio = stats.value("path_reopen_heat_ratio")
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


## 이동 전: 다음 칸이 위험하면 멈추고, 분대원 누구든 지금 칸이 위험하면 물러난다.
## 열 스트레스가 쌓인 대원이 있으면: 임무 없는 분대는 식힐 곳으로 물러나고, 임무 중이면 보고만 한다 (2026-11-17 —
## 불이 다시 커지는 동안 위험 상한 바로 아래로만 조금씩 물러나다 열 스트레스로 쓰러졌다)
func before_move(tick: int) -> void:
	for c in units.crews:
		var leader := c.leader
		if leader.incapacitated:
			# 선두가 쓰러져도 남은 조원은 뜨거운 곳으로 걸어 들어가지 않는다 (2026-11-24 — 전에는 선두가 쓰러지면 조 전체의
			# 열 검사를 건너뛰어, 길이 남아 있던 조원이 플래시오버가 난 방으로 들어가 모두 쓰러졌다)
			_guard_members(c)
			continue
		var here := Vector2i(leader.pos.floor())
		var hot := false
		var warm := false
		var stressed := false
		for ff in c.list:
			if ff.incapacitated:
				continue
			var q := heat_at(ff.level, Vector2i(ff.pos.floor()), ff.crouched)
			hot = hot or q >= _hazard
			warm = warm or q > _routine
			stressed = stressed or ff.heat_stress >= _stress_retreat
		if hot:
			# 하던 인명검색·구조를 멈춘다 — 멈추지 않으면 물러난 자리에 닿자마자 다시 불 쪽으로 간다
			_stop_task(c, tick, "retreat")
			_retreat(c, tick, "heat_retreat", true)
			continue
		if stressed and warm:
			var idle := activity_of.is_valid() and int(activity_of.call(leader)) == 0 and not leader.is_moving()
			if idle:
				_retreat(c, tick, "heat_stress_retreat")
			else:
				_heat_event(c, "heat_stress_high", tick)
		if leader.path.is_empty():
			continue
		# 다음에 밟을 칸: 길의 첫 칸이 지금 선 칸이면 그다음 칸 (order_move 가 잡은 길은 자기 칸에서 시작한다 —
		# 전에는 그 한 틱을 검사하지 않아, 다시 명령받을 때마다 한 걸음씩 들어갔다 나왔다 했다, 2026-11-24)
		var wp := leader.path[0]
		if wp.z == leader.level and Vector2i(wp.x, wp.y) == here and leader.path.size() > 1:
			wp = leader.path[1]
		if wp.z != leader.level or Vector2i(wp.x, wp.y) == here:
			continue
		if heat_at(wp.z, Vector2i(wp.x, wp.y), leader.crouched) >= _hazard:
			for ff in c.list:
				ff.path.clear()
			_heat_event(c, "heat_blocked", tick)
			_check_trapped(c, tick)
			# 인명검색·구조 중이었으면 임무를 멈추고, 문턱에 서 있지 않고 방 밖 식은 곳까지 물러나 지시를 기다린다
			# (문턱 안쪽에 서 있다가 플래시오버에 쓰러졌다). 방수하러 다가가는 조는 그대로 — 그 자리에서 쏜다
			if _stop_task(c, tick, "blocked"):
				_retreat(c, tick)


## 퇴로 차단 (2026-11-25 — 튜토리얼 자동 진행에서 2층 검색을 마치고 나오려던 구조 분대가 1층 거실(불난 방)을 지나는 길이 열기로
## 막혀 '열기 접근 불가'만 10초마다 되풀이하다 열 스트레스로 쓰러졌다. 지휘관은 고립된 줄 몰랐다):
## 건물 안의 조가 trapped_report_s 동안 줄곧 열기에 길이 막히면 '퇴로 차단 — 고립' 을 보고하고(지휘관이 엄호 방수·사다리·RIT 로
## 퇴로를 열 수 있게) 그 층의 가장 식은 곳으로 물러나 기다린다. 한 번 보고한 뒤에는 길이 다시 열려 움직일 때까지 또 보고하지 않는다
func _check_trapped(c: Crew, tick: int) -> void:
	var last := int(_blocked_last.get(c.id, -1))
	# 막힘이 잠시(보고 시간의 절반 넘게) 풀렸으면 처음부터 다시 센다 — 고립 보고도 잊는다 (다음에 또 막히면 다시 보고)
	if last < 0 or tick - last > _trapped_ticks / 2:
		_blocked_since[c.id] = tick
		_trapped.erase(c.id)
	_blocked_last[c.id] = tick
	if _trapped.has(c.id):
		return
	if tick - int(_blocked_since.get(c.id, tick)) < _trapped_ticks:
		return
	var leader := c.leader
	if fire.building.cell(leader.level, floori(leader.pos.x), floori(leader.pos.y)) in BuildingData.OUTDOOR:
		return
	_trapped[c.id] = tick
	var room := fire.compartment_at(leader.level, floori(leader.pos.x), floori(leader.pos.y))
	events.add(tick, "crew_trapped", {"crew": _crew_name(c), "crew_id": c.id, "floor": fire.building.floor_name(leader.level),
		"room": room.display_name() if room else ""})
	# 이미 문턱에서 물러나 식은 곳에서 기다리는 조는 또 옮기지 않는다 (2026-11-25 — 막힌 철수는 물러난 자리에서 길이 열리기를 기다린다)
	if not _settled(leader):
		_retreat(c, tick, "heat_retreat")


## 식은 곳에 자리를 잡았는가: 선 칸이 일상 수준 아래이고, 바로 옆에 위험한 칸(불난 방 문턱)이 없다
func _settled(ff: Firefighter) -> bool:
	var here := Vector2i(ff.pos.floor())
	if _flux_there(ff.level, here) > _routine:
		return false
	for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var n := here + d
		if pathfinder.passable(ff.level, n.x, n.y) and _flux_there(ff.level, n) >= _hazard:
			return false
	return true


## 열기 때문에 하던 임무를 멈춘다 (SimWorld가 넣은 on_heat_stop) — 멈춘 임무가 있었는가
func _stop_task(c: Crew, tick: int, kind: String) -> bool:
	return on_heat_stop.is_valid() and bool(on_heat_stop.call(c, tick, kind))


## 선두가 쓰러진 조의 남은 조원: 다음 칸이 위험하면 멈추고, 지금 칸이 위험하면 방 밖 식은 곳으로 저마다 물러난다
func _guard_members(c: Crew) -> void:
	for ff in c.list:
		if ff.incapacitated:
			continue
		var here := Vector2i(ff.pos.floor())
		if heat_at(ff.level, here, ff.crouched) >= _hazard:
			if ff.path.is_empty() or not safe_to_enter(ff.path.back().z, Vector2i(ff.path.back().x, ff.path.back().y)):
				var to := _cool_cell(ff.level, here, 0)
				if to.x >= 0 and to != here:
					ff.set_path(_cool_path(ff.cell3(), to, ff.crouched))
			continue
		if ff.path.is_empty():
			continue
		var wp := ff.path[0]
		if wp.z == ff.level and Vector2i(wp.x, wp.y) == here and ff.path.size() > 1:
			wp = ff.path[1]
		if wp.z == ff.level and Vector2i(wp.x, wp.y) != here and heat_at(wp.z, Vector2i(wp.x, wp.y), ff.crouched) >= _hazard:
			# 문턱에 서 있지 않고 방 밖 식은 곳까지 물러난다 (문턱에 서 있다가 플래시오버에 쓰러졌다)
			ff.path.clear()
			var back := _cool_cell(ff.level, here, 0)
			if back.x >= 0 and back != here:
				ff.set_path(_cool_path(ff.cell3(), back, ff.crouched))


## 이동 후: 자세·복사열·열 스트레스·공기호흡기·용기 교체·행동 불능
func after_move(dt: float, tick: int) -> void:
	_exits_now = exits.call() if exits.is_valid() else []
	for ff in units.firefighters:
		if ff.incapacitated:
			continue
		var cell := Vector2i(ff.pos.floor())
		var room := _room_for(ff.level, cell)
		ff.crouched = _crouch_in(room)
		ff.crouch_factor = _crouch_speed if ff.crouched else 1.0
		ff.heat_flux = heat_at(ff.level, cell, ff.crouched)
		if covered.is_valid() and ff.heat_flux > 0.0 and bool(covered.call(ff.level, ff.pos)):
			ff.heat_flux *= _cover_factor
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
## 그 방에서 대원이 낮은 자세를 하는가 (연기층이 서 있는 눈높이보다 내려옴)
func _crouch_in(room: Compartment) -> bool:
	return room != null and room.layer_depth > room.height - _eye_stand


## 그 칸에 가서 서면 받을 복사열 — 그 자리의 자세(연기층에 따라 서거나 낮춤)로 본다
func _flux_there(level: int, cell: Vector2i) -> float:
	return heat_at(level, cell, _crouch_in(_room_for(level, cell)))


## 물러날 곳: 열 스트레스가 쌓이지 않는 곳(일상 복사열 아래)이 가까이 있으면 그리로, 없으면 위험 상한의 0.6 아래.
## (전에는 0.6 아래 첫 칸으로만 물러나 스트레스가 계속 쌓였다)
## urgent = 지금 선 칸이 위험 상한 이상 (뜨거운 칸을 뚫고라도 나간다 · 곧바로 다시 찾는다)
func _retreat(c: Crew, tick: int, event_type := "heat_retreat", urgent := false) -> void:
	var leader := c.leader
	# 이미 물러나는 중이면 그대로 간다 — 틱마다 다시 명령하면 걸음을 떼기 전에 길이 새로 잡혀 제자리에 선 채
	# 쓰러졌다 (2026-11-17 골목 주택 재발화)
	if not leader.path.is_empty() and _retreat_goal.get(c.id, Vector3i(-1, -1, -1)) == leader.path.back():
		return
	# 식은 곳에 닿지 못해 덜 뜨거운 곳에서 버티는 조는 틱마다 다시 찾지 않는다 (2026-11-25): 선 칸이 위험하면 1초, 아니면 알림 간격마다
	var since := tick - int(_retreat_wait.get(c.id, -HEAT_EVENT_COOLDOWN_TICKS))
	if since < (roundi(1.0 / SimClock.TICK_DT) if urgent else HEAT_EVENT_COOLDOWN_TICKS):
		return
	var start := Vector2i(leader.pos.floor())
	# 다른 조가 서 있는 칸은 고르지 않는다 (같은 칸에 두 분대가 겹쳐 서지 않게)
	var taken := {}
	for other in units.crews:
		if other == c:
			continue
		for ff in other.list:
			if not ff.incapacitated and ff.level == leader.level and not ff.is_moving():
				taken[Vector2i(ff.pos.floor())] = true
	var target := _cool_cell(leader.level, start, (c.list.size() - 1) * units.line_gap_cells, taken)
	if _cool_found:
		_retreat_wait.erase(c.id)
	else:
		_retreat_wait[c.id] = tick
	if target.x < 0 or target == start:
		return
	units.route_along(c, _cool_path(leader.cell3(), target, leader.crouched), pathfinder)
	if not leader.path.is_empty():
		_retreat_goal[c.id] = leader.path.back()
	_heat_event(c, event_type, tick)


## start 에서 걸어서 닿는 가장 가까운 식은 칸 (없으면 (-1, -1)).
## 지금 있는 방을 벗어난다 — 가까운 '식은 칸'이 불난 방 문턱이면 뒤따르는 짝이 방 안에 남아 플래시오버에 쓰러졌다.
## trail = 뒤따르는 대원 수만큼(줄 간격) 더 가서 설 칸 수 · taken = 고르지 않을 칸 (다른 조가 선 칸)
##
## 뜨거운 칸(위험 상한 이상)은 밟지 않고 닿는 곳에서 고른다 (2026-11-25 — 전에는 걸음 수만 보고 골라, 불난 거실 건너 현관 밖을 고르고는
## 그 길의 첫 칸이 뜨거워 매 틱 막혔다. 뒤쪽 복도·방에 식은 칸이 200칸 넘게 있었는데도 5~7kW/㎡ 자리에 선 채 열 스트레스로 쓰러졌다).
## 그렇게 닿는 식은 칸이 없으면 닿는 곳 중 가장 덜 뜨거운 칸 (지금 자리보다 뚜렷이 식을 때만 — retreat_cooler_ratio).
## 뜨거운 칸을 밟지 않고는 한 걸음도 못 떼는데 선 칸이 위험 상한 이상이면 예전처럼 열기를 가리지 않고 찾는다 (뚫고라도 나가야 한다).
## 찾은 길은 _cool_path 로 꺼낸다. 열 스트레스가 쌓이지 않는 곳을 찾았으면 _cool_found
func _cool_cell(level: int, start: Vector2i, trail: int, taken: Dictionary = {}) -> Vector2i:
	_cool_through = false
	var safe := _search_cool(level, start, trail, taken, false)
	_cool_found = safe[0].x >= 0
	if _cool_found:
		return safe[0]
	if safe[1].x >= 0 or _flux_there(level, start) < _hazard:
		return safe[1]
	var any := _search_cool(level, start, trail, taken, true)
	_cool_found = any[0].x >= 0
	var pick := any[0] if _cool_found else any[1]
	_cool_through = pick.x >= 0
	return pick


## _cool_cell 의 탐색 한 번 → [식은 칸, 차선] (없으면 (-1, -1)).
## through_heat = 뜨거운 칸도 지나간다 (차선: 위험 상한의 0.6 아래 첫 칸). 아니면 뜨거운 칸은 밟지 않는다 (차선: 닿는 곳 중 가장 덜 뜨거운 칸)
func _search_cool(level: int, start: Vector2i, trail: int, taken: Dictionary, through_heat: bool) -> Array[Vector2i]:
	var here_room := fire.compartment_at(level, start.x, start.y)
	var queue: Array[Vector2i] = [start]
	var depth := {start: 0}
	var flux := {}
	var head := 0
	var fallback := Vector2i(-1, -1)
	var target := Vector2i(-1, -1)
	var first_ok := -1
	var coolest := start
	var coolest_q := INF
	var here_q := _flux_there(level, start)
	_cool_parent = {}
	while head < queue.size() and head < RETREAT_SEARCH_LIMIT:
		var p := queue[head]
		head += 1
		# 늘 낮은 자세로 보면 연기층이 높아 서는 방에서 '식은 칸'을 잘못 골라 한 칸씩만 물러나다 쓰러졌다 (2026-11-17)
		var q: float = flux[p] if flux.has(p) else _flux_there(level, p)
		var free := not taken.has(p)
		var room := fire.compartment_at(level, p.x, p.y)
		if free and q <= _routine and (here_room == null or room != here_room):
			target = p
			if first_ok < 0:
				first_ok = int(depth[p])
			if int(depth[p]) >= first_ok + trail:
				break
		if through_heat:
			if free and fallback.x < 0 and q < _hazard * 0.6:
				fallback = p
		elif free and q < coolest_q:
			coolest_q = q
			coolest = p
		var pose := _crouch_in(_room_for(level, p))
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var n := p + d
			if depth.has(n) or not pathfinder.passable(level, n.x, n.y):
				continue
			if not through_heat:
				# 걸어 들어갈 때의 자세(지금 칸의 연기층)와 그 칸에 선 뒤의 자세 둘 다로 본다 — before_move 가 막는 기준과 같게
				var there := _crouch_in(_room_for(level, n))
				var qn := heat_at(level, n, there)
				flux[n] = qn
				if qn >= _hazard or (pose != there and heat_at(level, n, pose) >= _hazard):
					continue
			depth[n] = int(depth[p]) + 1
			_cool_parent[n] = p
			queue.append(n)
	if not through_heat:
		# 지금 자리보다 뚜렷이 식은 곳일 때만 옮긴다 (일상 수준을 넘는 열이 retreat_cooler_ratio 아래로 줄어야)
		var gain := here_q >= _hazard or maxf(0.0, coolest_q - _routine) <= maxf(0.0, here_q - _routine) * _cooler_ratio
		fallback = coolest if coolest != start and gain else Vector2i(-1, -1)
	return [target, fallback]


## from 에서 _cool_cell 이 고른 칸까지의 길: 가장 짧은 길이 뜨거운 칸을 지나지 않으면 그 길, 지나면 찾을 때 지나온(뜨거운 칸을 피한) 길
func _cool_path(from: Vector3i, to: Vector2i, crouched: bool) -> Array[Vector3i]:
	var path := pathfinder.find_path(from, Vector3i(to.x, to.y, from.z))
	if _cool_through or (not path.is_empty() and route_clear(path, crouched)):
		return path
	var out: Array[Vector3i] = []
	var p := to
	while _cool_parent.has(p):
		out.push_front(Vector3i(p.x, p.y, from.z))
		p = _cool_parent[p]
	if out.is_empty() or p != Vector2i(from.x, from.y):
		return path
	out.push_front(from)
	return out


## 이 길을 걸어도 열기에 막히지 않는가 (before_move 가 막는 기준과 같다): 칸마다 걸어 들어갈 때의 자세와 그 칸에 선 뒤의 자세로 본
## 복사열이 위험 상한 아래. path[0] 은 지금 선 칸. ratio = 여유 (1 미만이면 더 엄격하게)
func route_clear(path: Array[Vector3i], crouched: bool, ratio := 1.0) -> bool:
	var limit := _hazard * ratio
	var pose := crouched
	for k in range(1, path.size()):
		var p := path[k]
		var cell := Vector2i(p.x, p.y)
		var there := _crouch_in(_room_for(p.z, cell))
		if heat_at(p.z, cell, there) >= limit or (pose != there and heat_at(p.z, cell, pose) >= limit):
			return false
		pose = there
	return true


## 막혔던 길이 다시 열렸는가 (SafetySystem — 열기에 막혀 멈춘 철수를 다시 잇는다): 위험 상한의 path_reopen_heat_ratio 아래여야
## 열렸다고 본다 (상한 바로 아래에서 나섰다가 몇 걸음 만에 다시 막히지 않게)
func way_reopened(c: Crew, path: Array[Vector3i]) -> bool:
	return not path.is_empty() and route_clear(path, c.leader.crouched, _reopen_ratio)


## 열기로 나갈 길이 없다 (SafetySystem — 식은 곳에서 기다리는 철수 조): 퇴로 차단 시간을 이어 센다
func note_blocked(c: Crew, tick: int) -> void:
	_check_trapped(c, tick)


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
	return units.crew_name(c)


func _ff_name(ff: Firefighter) -> String:
	return units.ff_name(ff)


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
