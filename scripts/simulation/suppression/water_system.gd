class_name WaterSystem
extends RefCounted
## 물 공급과 방수.
## - 차량: 탱크 물, 소화전 점령(계속 공급), 물탱크차 → 펌프차 급수 (SOP 200-3.1)
## - 수관: 펌프차에서 관창 조까지 깔리고, 조가 움직이면 따라 늘어난다. 적재 길이를 넘으면 더 못 간다 (SOP 208)
## - 방수: 직사(멀리, 가연물 냉각) / 분무(가까이, 고온 가스 냉각). 벽에 막히면 그 앞까지만 닿는다 (SOP 206)
## - 불이 없는 곳에 뿌린 물은 수손으로 누적된다 (SOP 205-3.1)

const EMPTY_TANK_L := 0.5
## 관창수가 물줄기를 옮기는 속도 (셀/초)
const SWEEP_CELLS_PER_S := 6.0
## 다가가서 쏠 때 사거리의 이 비율 안까지 들어간다 (끝자락에서 쏘지 않도록)
const APPROACH_RANGE_RATIO := 0.8
## 보이는 화점이 없을 때 전진할 위치를 다시 찾는 간격 (틱)
const ADVANCE_EVERY_TICKS := 50
## 차량 이동 가능 여부를 볼 때 표본 간격과 최소 이동 거리 (셀)
const VEHICLE_SAMPLE_CELLS := 0.5
const VEHICLE_MIN_MOVE_CELLS := 0.5

var building: BuildingData
var units: UnitSystem
var pathfinder: Pathfinder
var fire: FireSim
var events: SimEventLog
var hoses: Array[HoseLine] = []
## 고장(사용 불가) 소화전 index (시나리오 water.hydrants_out)
var hydrants_out: Array[int] = []
## 송수구에 연결한 펌프차 id (-1: 없음). 연결되면 층별 방수구에서 수관을 연장할 수 있다 (SOP 200-3.3.1)
var fdc_vehicle := -1
## 옥내소화전 수조에 남은 물 (ℓ). 송수구가 연결되면 펌프차 물을 쓴다 (R10)
var indoor_tank_l := 0.0
## 옥내소화전 물을 쓰는 수관의 vehicle_id
const INDOOR := -2
var _indoor_empty_logged := false
## (level, cell) -> 들어가도 되는 칸인지. 방수 위치를 고를 때 열기가 심한 칸을 피한다.
var safe_cell := Callable()

var _cell_m: float
var _water_kj: float
var _hydrant_lpm: float
var _hydrant_range: float
var _supply_range: float
var _drag_factor: float
var _damage_temp: float
var _range := {}  # Pattern -> 셀
var _radius := {}
var _fuel_eff := {}
var _gas_eff := {}


func _init(p_building: BuildingData, p_units: UnitSystem, p_pathfinder: Pathfinder, p_fire: FireSim, config: FireConfig, p_events: SimEventLog) -> void:
	building = p_building
	units = p_units
	pathfinder = p_pathfinder
	fire = p_fire
	events = p_events
	_cell_m = building.cell_size_m
	_water_kj = config.value("water_cooling_kj_per_l")
	_hydrant_lpm = config.value("hydrant_lpm")
	_hydrant_range = config.value("hydrant_range_m") / _cell_m
	_supply_range = config.value("supply_range_m") / _cell_m
	_drag_factor = config.value("hose_drag_speed_factor")
	indoor_tank_l = p_building.indoor_tank_l
	_damage_temp = config.value("water_damage_temp_c")
	_range[HoseLine.Pattern.STRAIGHT] = config.value("straight_range_m") / _cell_m
	_range[HoseLine.Pattern.FOG] = config.value("fog_range_m") / _cell_m
	_radius[HoseLine.Pattern.STRAIGHT] = config.value("straight_radius_m") / _cell_m
	_radius[HoseLine.Pattern.FOG] = config.value("fog_radius_m") / _cell_m
	_fuel_eff[HoseLine.Pattern.STRAIGHT] = config.value("straight_fuel_eff")
	_fuel_eff[HoseLine.Pattern.FOG] = config.value("fog_fuel_eff")
	_gas_eff[HoseLine.Pattern.STRAIGHT] = config.value("straight_gas_eff")
	_gas_eff[HoseLine.Pattern.FOG] = config.value("fog_gas_eff")


# --- 조회 ---

func hose_of_crew(crew_id: int) -> HoseLine:
	for h in hoses:
		if h.crew_id == crew_id:
			return h
	return null


func hoses_of_vehicle(vehicle_id: int) -> Array[HoseLine]:
	var out: Array[HoseLine] = []
	for h in hoses:
		if h.vehicle_id == vehicle_id:
			out.append(h)
	return out


## p(셀 좌표) 근처의 소화전 index. 없으면 -1.
func hydrant_near(p: Vector2, radius := 1.2) -> int:
	for k in building.hydrants.size():
		if (Vector2(building.hydrants[k]) + Vector2(0.5, 0.5)).distance_to(p) <= radius:
			return k
	return -1


func vehicle_at(p: Vector2) -> int:
	for v in units.vehicles:
		if not v.away and v.contains(p):
			return v.id
	return -1


func range_cells(pattern: HoseLine.Pattern) -> float:
	return _range[pattern]


func radius_cells(pattern: HoseLine.Pattern) -> float:
	return _radius[pattern]


# --- 명령 ---

## 차량 이동: 목표 지점을 차체 축에 투영해 그만큼 전진(앞쪽) 또는 후진(뒤쪽)한다.
## 차체가 차도를 벗어나거나 다른 차량과 겹치기 직전에서 멈춘다. 수관이 연결된 펌프차는 움직일 수 없다.
func order_vehicle_move(vehicle_id: int, target: Vector2i, tick: int) -> bool:
	var v := units.get_vehicle(vehicle_id)
	if v == null:
		return false
	if not hoses_of_vehicle(vehicle_id).is_empty():
		events.add(tick, "vehicle_locked", {"vehicle": _name(v), "driver": v.driver_label()})
		return false
	var along := (Vector2(target) + Vector2(0.5, 0.5) - v.pos).dot(v.heading)
	var reach := _clear_distance(v, along)
	if absf(reach) < VEHICLE_MIN_MOVE_CELLS:
		if absf(along) >= VEHICLE_MIN_MOVE_CELLS:
			events.add(tick, "vehicle_blocked", {"vehicle": _name(v), "driver": v.driver_label()})
		return false
	v.drive(reach)
	v.pending_hydrant = -1
	v.pending_supply = -1
	_disconnect(v, tick)
	return true


## 차체 축 방향으로 along(셀)만큼 갈 때, 실제로 갈 수 있는 거리
func _clear_distance(v: Vehicle, along: float) -> float:
	var dir := signf(along)
	var best := 0.0
	var s := 0.0
	while absf(s) + VEHICLE_SAMPLE_CELLS <= absf(along):
		s += dir * VEHICLE_SAMPLE_CELLS
		if not _vehicle_can_be_at(v, v.pos + v.heading * s):
			return best
		best = s
	if _vehicle_can_be_at(v, v.pos + v.heading * along):
		best = along
	return best


## 차량이 center에 설 수 있는가 (차도 안, 다른 차량과 겹치지 않음)
func vehicle_can_be_at(v: Vehicle, center: Vector2) -> bool:
	return _vehicle_can_be_at(v, center)


func _vehicle_can_be_at(v: Vehicle, center: Vector2) -> bool:
	var body := v.footprint(center)
	if not pathfinder.vehicle_fits(body):
		return false
	for other in units.vehicles:
		if other != v and not Geometry2D.intersect_polygons(body, other.footprint()).is_empty():
			return false
	return true


## 소화전 점령: 가까우면 바로 연결, 멀면 소화전 앞 도로로 이동한 뒤 연결
func connect_hydrant(vehicle_id: int, hydrant: int, tick: int) -> void:
	var v := units.get_vehicle(vehicle_id)
	if v == null or hydrant < 0 or hydrant >= building.hydrants.size():
		return
	if _hydrant_distance(v, hydrant) <= _hydrant_range:
		_connect_hydrant_now(v, hydrant, tick)
		return
	if order_vehicle_move(vehicle_id, building.hydrants[hydrant], tick):
		v.pending_hydrant = hydrant


## 물탱크차 → 펌프차 급수: 가까우면 바로 연결, 멀면 펌프차 쪽으로 이동한 뒤 연결
func connect_supply(tanker_id: int, pump_id: int, tick: int) -> void:
	var t := units.get_vehicle(tanker_id)
	var p := units.get_vehicle(pump_id)
	if t == null or p == null or t == p or t.transfer_lpm <= 0.0 or not p.is_pump():
		return
	if t.pos.distance_to(p.pos) <= _supply_range:
		_connect_supply_now(t, p, tick)
		return
	# 펌프차 쪽으로 가다 차체가 닿기 직전에서 멈춘다
	if order_vehicle_move(tanker_id, p.cell(), tick):
		t.pending_supply = pump_id


## 송수구 연결: 펌프차가 송수구 가까이(소화전 연결 거리의 1.5배, 수관 한 본 안) 있으면 연결한다
func connect_fdc(vehicle_id: int, tick: int) -> bool:
	var v := units.get_vehicle(vehicle_id)
	if v == null or not v.is_pump() or not building.has_standpipe():
		return false
	if v.distance_to_body(Vector2(building.fdc) + Vector2(0.5, 0.5)) > _hydrant_range * 1.5:
		events.add(tick, "fdc_too_far", {"vehicle": _name(v), "driver": v.driver_label()})
		return false
	fdc_vehicle = vehicle_id
	events.add(tick, "fdc_connected", {"vehicle": _name(v), "driver": v.driver_label()})
	return true


## 방수구에서 수관 연장: 송수구에 연결된 펌프차의 물을 쓴다. 수관 길이는 방수구 적재분(outlet_hose_m)
func lay_hose_outlet(crew_id: int, outlet: int, tick: int, report := true) -> bool:
	var c := units.get_crew(crew_id)
	if c == null or outlet < 0 or outlet >= building.outlets.size() or hose_of_crew(crew_id) != null:
		return false
	# 송수구가 연결되지 않았어도 옥내소화전 수조에 물이 있으면 쓴다 (SOP 235)
	var indoor := fdc_vehicle < 0 and building.indoor_lpm > 0.0 and indoor_tank_l > 0.0
	if fdc_vehicle < 0 and not indoor:
		if report:
			events.add(tick, "fdc_not_connected", {"crew": _crew_name(c)})
		return false
	var o := building.outlets[outlet]
	var start := pathfinder.nearest_walkable(o.z, Vector2i(o.x, o.y))
	var path := pathfinder.find_path(Vector3i(start.x, start.y, o.z), c.leader.cell3())
	if path.is_empty():
		return false
	var h := HoseLine.new()
	h.id = hoses.size()
	h.vehicle_id = INDOOR if indoor else fdc_vehicle
	h.crew_id = crew_id
	h.outlet = outlet
	h.max_cells = building.outlet_hose_m / _cell_m
	h.points = path
	if h.length_cells() > h.max_cells:
		if report:
			events.add(tick, "hose_too_short", {"crew": _crew_name(c)})
		return false
	hoses.append(h)
	for ff in c.members():
		ff.speed_factor = _drag_factor
	events.add(tick, "hose_outlet_laid", {"crew": _crew_name(c), "level": building.floor_name(o.z), "indoor": indoor})
	return true


## 수관 연장: 펌프차에서 조장(관창수) 위치까지 호스를 깐다.
func lay_hose(crew_id: int, vehicle_id: int, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	var v := units.get_vehicle(vehicle_id)
	if c == null or v == null or not v.is_pump() or hose_of_crew(crew_id) != null:
		return false
	var start := pathfinder.nearest_walkable(v.level, v.cell())
	var path := pathfinder.find_path(Vector3i(start.x, start.y, v.level), c.leader.cell3())
	if path.is_empty():
		return false
	var h := HoseLine.new()
	h.id = hoses.size()
	h.vehicle_id = vehicle_id
	h.crew_id = crew_id
	h.max_cells = v.hose_max_cells
	h.points = path
	if h.length_cells() > h.max_cells:
		events.add(tick, "hose_too_short", {"crew": _crew_name(c)})
		return false
	hoses.append(h)
	for ff in c.members():
		ff.speed_factor = _drag_factor
	events.add(tick, "hose_laid", {"crew": _crew_name(c), "vehicle": _name(v)})
	return true


## 방수 시작. 수관이 없으면 가장 가까운 펌프차에서 자동으로 연장하고,
## 목표가 사거리 밖이거나 벽에 가려 있으면 물줄기가 닿는 위치까지 먼저 이동한다.
func start_spray(crew_id: int, target: Vector3i, pattern: HoseLine.Pattern, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	if c == null:
		return false
	var h := hose_of_crew(crew_id)
	if h == null:
		# 연결송수관이 살아 있고 목표 층에 방수구가 있으면 방수구에서, 아니면 가장 가까운 펌프차에서
		var standpipe_ok := fdc_vehicle >= 0 or (building.indoor_lpm > 0.0 and indoor_tank_l > 0.0)
		var outlet := building.outlet_on(target.z) if standpipe_ok and target.z > 1 else -1
		if outlet < 0 or not lay_hose_outlet(crew_id, outlet, tick, false):
			var pump := _nearest_pump(c.leader.pos)
			if pump < 0 or not lay_hose(crew_id, pump, tick):
				return false
		h = hose_of_crew(crew_id)
	h.pattern = pattern
	h.target = target
	h.aim = Vector2(target.x + 0.5, target.y + 0.5)
	h.approaching = false
	h.next_advance_tick = tick
	var goal := Vector2(target.x + 0.5, target.y + 0.5)
	if not _can_spray_to(c.leader.pos, c.leader.level, goal, target.z, pattern):
		var spot := _approach_cell(c, goal, target.z, pattern)
		if spot == Pathfinder.NO_CELL:
			events.add(tick, "spray_unreachable", {"crew": _crew_name(c)})
			return false
		units.order_move([crew_id] as Array[int], Vector3i(spot.x, spot.y, target.z), pathfinder)
		h.approaching = true
	h.flowing = true
	events.add(tick, "spray_start", {"crew": _crew_name(c), "pattern": h.pattern_name()})
	return true


func stop_spray(crew_id: int, tick: int) -> void:
	var h := hose_of_crew(crew_id)
	if h and h.flowing:
		h.flowing = false
		h.approaching = false
		h.flow_fraction = 0.0
		events.add(tick, "spray_stop", {"crew": _crew_name(units.get_crew(crew_id))})


func _nearest_pump(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for v in units.vehicles:
		if v.is_pump() and v.distance_to_body(p) < best_d:
			best_d = v.distance_to_body(p)
			best = v.id
	return best


## 이 위치에서 target까지 물줄기가 막히지 않고 닿는지 (사거리의 APPROACH_RANGE_RATIO 안)
func _can_spray_to(pos: Vector2, level: int, target: Vector2, target_level: int, pattern: HoseLine.Pattern) -> bool:
	if level != target_level:
		return false
	if pos.distance_to(target) > _range[pattern] * APPROACH_RANGE_RATIO:
		return false
	return not _trace(level, pos, target, _range[pattern]).blocked


## target에 물줄기가 닿고 열기가 견딜 만한 위치 중 조장에게서 가장 가까운 셀. 없으면 NO_CELL.
func _approach_cell(c: Crew, target: Vector2, level: int, pattern: HoseLine.Pattern) -> Vector2i:
	var r := ceili(_range[pattern] * APPROACH_RANGE_RATIO)
	var center := Vector2i(target.floor())
	var candidates: Array[Vector2i] = []
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			if not pathfinder.passable(level, x, y) or not _can_spray_to(p, level, target, level, pattern):
				continue
			if safe_cell.is_valid() and not safe_cell.call(level, Vector2i(x, y)):
				continue
			candidates.append(Vector2i(x, y))
	var from := c.leader.pos
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return from.distance_squared_to(Vector2(a) + Vector2(0.5, 0.5)) < from.distance_squared_to(Vector2(b) + Vector2(0.5, 0.5)))
	for cell in candidates:
		if not pathfinder.find_path(c.leader.cell3(), Vector3i(cell.x, cell.y, level)).is_empty():
			return cell
	return Pathfinder.NO_CELL


## 지금 위치에서 보이는 화점이 없는데 목표 방에 불이 남아 있으면,
## 남은 화점 중 가장 가까운 곳이 보이는 (열기가 견딜 만한) 위치로 전진한다.
func _advance(h: HoseLine, c: Crew, tick: int) -> void:
	if tick < h.next_advance_tick:
		return
	h.next_advance_tick = tick + ADVANCE_EVERY_TICKS
	var room := fire.compartment_at(h.target.z, h.target.x, h.target.y)
	if room == null:
		return
	var grid := fire.grid
	var from := c.leader.pos
	var nearest := Vector2.INF
	for i in grid.room_and_door_cells[room.index]:
		if grid.state[i] != FuelGrid.State.BURNING:
			continue
		var p := grid.cell_of(i)
		var q := Vector2(p.x + 0.5, p.y + 0.5)
		if from.distance_squared_to(q) < from.distance_squared_to(nearest):
			nearest = q
	if nearest == Vector2.INF:
		return
	var spot := _approach_cell(c, nearest, h.target.z, h.pattern)
	if spot == Pathfinder.NO_CELL or Vector3i(spot.x, spot.y, h.target.z) == c.leader.cell3():
		return
	units.order_move([c.id] as Array[int], Vector3i(spot.x, spot.y, h.target.z), pathfinder)
	h.approaching = true


# --- 매 틱 ---

func step(dt: float, tick: int) -> void:
	for c in fire.comps:
		c.cooling_kw = 0.0
	_update_pending(tick)
	_update_hoses(tick)
	_update_supply(dt, tick)
	_apply_sprays(dt, tick)


func _update_pending(tick: int) -> void:
	for v in units.vehicles:
		if v.is_moving():
			continue
		if v.pending_hydrant >= 0:
			var hy := v.pending_hydrant
			v.pending_hydrant = -1
			if _hydrant_distance(v, hy) <= _hydrant_range:
				_connect_hydrant_now(v, hy, tick)
		if v.pending_supply >= 0:
			var p := units.get_vehicle(v.pending_supply)
			v.pending_supply = -1
			if p and v.pos.distance_to(p.pos) <= _supply_range:
				_connect_supply_now(v, p, tick)


## 조가 움직인 만큼 호스를 늘리거나(되돌아오면 줄이고), 적재 길이를 넘으면 조를 멈춘다.
func _update_hoses(tick: int) -> void:
	for h in hoses:
		var c := units.get_crew(h.crew_id)
		var leader := c.leader
		var cell := leader.cell3()
		var last := h.points[-1]
		if cell == last:
			continue
		if h.points.size() >= 2 and cell == h.points[-2]:
			h.points.pop_back()
		else:
			var seg := pathfinder.find_path(last, cell)
			for k in range(1, seg.size()):
				h.points.append(seg[k])
		if h.length_cells() <= h.max_cells:
			h.at_limit = false
			continue
		while h.points.size() > 1 and h.length_cells() > h.max_cells:
			h.points.pop_back()
		var end := h.points[-1]
		leader.pos = Vector2(end.x + 0.5, end.y + 0.5)
		leader.level = end.z
		leader.path.clear()
		if c.partner:
			c.partner.path.clear()
		if not h.at_limit:
			h.at_limit = true
			events.add(tick, "hose_limit", {"crew": _crew_name(c)})


func _update_supply(dt: float, tick: int) -> void:
	var minutes := dt / 60.0
	# 물탱크차 → 펌프차
	for t in units.vehicles:
		if t.supply_to < 0:
			continue
		var p := units.get_vehicle(t.supply_to)
		var amount := minf(t.transfer_lpm * minutes, minf(t.tank_l, p.tank_capacity - p.tank_l))
		t.tank_l -= amount
		p.tank_l += amount
	# 소화전 → 차량 (탱크를 채운다)
	for v in units.vehicles:
		if v.hydrant >= 0:
			v.tank_l = minf(v.tank_capacity, v.tank_l + _hydrant_lpm * minutes)
	# 펌프차 → 관창
	for v in units.vehicles:
		if not v.is_pump():
			continue
		var flowing: Array[HoseLine] = []
		for h in hoses_of_vehicle(v.id):
			if h.flowing and not h.approaching:
				flowing.append(h)
		if flowing.is_empty():
			continue
		var demand := v.nozzle_lpm * minutes * flowing.size()
		var used := minf(demand, v.tank_l)
		v.tank_l -= used
		var fraction := used / demand
		for h in flowing:
			h.flow_fraction = fraction
		if v.tank_l <= EMPTY_TANK_L and not v.tank_empty_logged:
			v.tank_empty_logged = true
			events.add(tick, "tank_empty", {"vehicle": _name(v)})
		elif v.tank_l > EMPTY_TANK_L * 100.0:
			v.tank_empty_logged = false
	_update_indoor(minutes, tick)


func _apply_sprays(dt: float, tick: int) -> void:
	var grid := fire.grid
	for h in hoses:
		if not h.flowing:
			continue
		var leader := units.get_crew(h.crew_id).leader
		if leader.incapacitated:
			continue
		# 방수 위치로 가는 중에는 쏘지 않는다. 도착하면(또는 수관 길이에 걸려 멈추면) 다음 틱부터 물이 나온다
		if h.approaching:
			if not leader.is_moving():
				h.approaching = false
			continue
		if h.flow_fraction <= 0.0:
			continue
		if leader.level != h.target.z:
			h.blocked = true
			continue
		if not _sweep(h, leader, dt):
			_advance(h, units.get_crew(h.crew_id), tick)
		var trace := _trace(leader.level, leader.pos, h.aim, _range[h.pattern])
		h.impact = trace.impact
		h.blocked = trace.blocked
		var v := units.get_vehicle(h.vehicle_id)
		var lpm := v.nozzle_lpm if v else building.indoor_lpm
		var liters := lpm / 60.0 * dt * h.flow_fraction
		var impact_cell := Vector2i(h.impact.floor())
		var comp := fire.compartment_at(leader.level, impact_cell.x, impact_cell.y)
		if comp:
			comp.cooling_kw += liters / dt * _water_kj * _gas_eff[h.pattern]
			comp.water_applied_l += liters
		# 타는 셀에 물이 먼저 가도록 열방출률로 가중
		var cells := grid.cells_in_radius(leader.level, h.impact, _radius[h.pattern])
		var weights := PackedFloat32Array()
		var total_w := 0.0
		for i in cells:
			var w := 0.2 + (grid.hrr[i] if grid.state[i] == FuelGrid.State.BURNING else 0.0)
			weights.append(w)
			total_w += w
		var wasted := liters
		for k in cells.size():
			var i := cells[k]
			var share := liters * weights[k] / total_w
			var was_burning := grid.state[i] == FuelGrid.State.BURNING
			grid.apply_water(i, share, _fuel_eff[h.pattern])
			if was_burning:
				wasted -= share
		if comp and comp.t_upper < _damage_temp:
			comp.water_damage_l += maxf(0.0, wasted)


## 관창수가 물줄기를 훑는다: 목표 지점이 속한 방 안에서, 사거리 안이고 물줄기가 닿는 타는 셀 중
## 지금 겨눈 곳에서 가장 가까운 곳으로 겨냥을 옮긴다. 타는 곳이 없으면 목표 지점으로 돌아간다.
## 겨눌 화점을 찾았으면 true.
func _sweep(h: HoseLine, leader: Firefighter, dt: float) -> bool:
	var grid := fire.grid
	var target := Vector2(h.target.x + 0.5, h.target.y + 0.5)
	var goal := target
	var found := false
	var room := fire.compartment_at(h.target.z, h.target.x, h.target.y)
	if room:
		var best_d := INF
		for i in grid.room_and_door_cells[room.index]:
			if grid.state[i] != FuelGrid.State.BURNING:
				continue
			var c := grid.cell_of(i)
			var p := Vector2(c.x + 0.5, c.y + 0.5)
			if leader.pos.distance_to(p) > _range[h.pattern]:
				continue
			var d := h.aim.distance_squared_to(p)
			if d < best_d and not _trace(leader.level, leader.pos, p, _range[h.pattern]).blocked:
				best_d = d
				goal = p
				found = true
	h.aim = h.aim.move_toward(goal, SWEEP_CELLS_PER_S * dt)
	return found


## from에서 to 방향으로 물줄기를 보낸다. 벽·닫힌 문·깨지지 않은 창에 막히면 그 앞에서 멈춘다.
func _trace(level: int, from: Vector2, to: Vector2, max_cells: float) -> Dictionary:
	var dir := to - from
	var dist := minf(dir.length(), max_cells)
	if dist < 0.01:
		return {"impact": from, "blocked": false}
	dir = dir.normalized()
	var last := from
	var goal_cell := Vector2i(to.floor())
	var t := 0.25
	while t <= dist:
		var p := from + dir * t
		var c := Vector2i(p.floor())
		if not _water_passes(level, c):
			# 겨눈 곳이 바로 그 문·창이면 표면에는 물이 닿는다
			if c == goal_cell:
				return {"impact": p, "blocked": false}
			return {"impact": last, "blocked": true}
		last = p
		t += 0.25
	return {"impact": from + dir * dist, "blocked": false}


func _water_passes(level: int, c: Vector2i) -> bool:
	var t := building.cell(level, c.x, c.y)
	match t:
		BuildingData.Cell.WALL, BuildingData.Cell.VOID:
			return false
		BuildingData.Cell.DOOR, BuildingData.Cell.WINDOW:
			var o := fire.opening_at(Vector3i(c.x, c.y, level))
			return o != null and o.is_open
	return true


## 소화전에서 차체 옆면까지의 거리 (흡수관은 차체 옆에 연결한다)
func _hydrant_distance(v: Vehicle, hydrant: int) -> float:
	return v.distance_to_body(Vector2(building.hydrants[hydrant]) + Vector2(0.5, 0.5))


func _connect_hydrant_now(v: Vehicle, hydrant: int, tick: int) -> void:
	if hydrant in hydrants_out:
		events.add(tick, "hydrant_out", {"vehicle": _name(v), "driver": v.driver_label()})
		return
	v.hydrant = hydrant
	events.add(tick, "hydrant_connected", {"vehicle": _name(v), "driver": v.driver_label()})


func _connect_supply_now(t: Vehicle, p: Vehicle, tick: int) -> void:
	t.supply_to = p.id
	events.add(tick, "supply_connected", {"vehicle": _name(t), "to": _name(p), "driver": t.driver_label()})


func _disconnect(v: Vehicle, tick: int) -> void:
	if v.hydrant >= 0:
		v.hydrant = -1
		events.add(tick, "hydrant_disconnected", {"vehicle": _name(v)})
	if v.supply_to >= 0:
		v.supply_to = -1
	for t in units.vehicles:
		if t.supply_to == v.id:
			t.supply_to = -1


func _name(v: Vehicle) -> String:
	return v.display_name(units.squads[v.squad_id].name)


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]


## 옥내소화전 수관: 건물 수조에서 물을 쓴다. 송수구가 연결되면 그 펌프차로 옮겨 탄다 (SOP 235, R10)
func _update_indoor(minutes: float, tick: int) -> void:
	var flowing: Array[HoseLine] = []
	for h in hoses:
		if h.vehicle_id != INDOOR:
			continue
		if fdc_vehicle >= 0:
			h.vehicle_id = fdc_vehicle
			continue
		if h.flowing and not h.approaching:
			flowing.append(h)
	if flowing.is_empty():
		return
	var demand := building.indoor_lpm * minutes * flowing.size()
	var used := minf(demand, indoor_tank_l)
	indoor_tank_l -= used
	for h in flowing:
		h.flow_fraction = used / demand
	if indoor_tank_l <= EMPTY_TANK_L and not _indoor_empty_logged:
		_indoor_empty_logged = true
		events.add(tick, "indoor_hydrant_empty", {"crew": _crew_name(units.get_crew(flowing[0].crew_id))})
