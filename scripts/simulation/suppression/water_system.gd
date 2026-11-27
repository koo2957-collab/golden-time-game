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
## 방수구에 닿았다고 보는 거리 (칸) — 방수구함 앞에서 결합하는 범위, 게임 설정값
const OUTLET_REACH_CELLS := 3.0
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
var _req_per_mw: float
var _critical_per_m2: float
## 현장 작업 시간 (data fire_params task_times)
var _tt: Dictionary = {}
var _fog_mix: float
## 방수 밀림 (fire_params push_*)
var _push_fog := 0.0
var _push_straight := 0.0
var _push_vented_ratio := 0.3
var _push_min_t := 150.0
var _push_rate := 0.05
var _push_warned: Dictionary = {}
## 방수 중 전진 (fire_params advance_*)
var _advance_min_m := 1.0
var _advance_backoff_ticks := 400
## 수증기 열 균형 파괴를 알린 구획
var _steam_warned: Dictionary = {}
var _short_ticks: int
## 방수량이 모자라기 시작한 틱 (구획 index -> tick) / 보고한 구획
var _short_since: Dictionary = {}
var _short_reported: Dictionary = {}
## 잔량 25% 경고를 한 차량
var _low_warned: Dictionary = {}
const LOW_TANK_RATIO := 0.25
var _hydrant_range: float
var _supply_range: float
## 수관 시작점: 펌프차 후면에서 이만큼 뒤 (칸)
var _port_behind: float
var _drag_factor: float
## (crew_id) -> bool : 그 조가 놓인 관창을 잡으러(건물 안으로) 가도 되는가. SimWorld 가 CommandSystem.can_take_hose 로 잇는다
var take_allowed := Callable()
## 호스를 거두며 돌아가는 속도 비율 · 놓인 관창을 다시 잡는 거리 (칸)
var _recover_factor := 0.45
var _nozzle_reach := 1.5
## 관창으로 가기·거두기 시간 한도 (틱) · 거둔 것으로 보는 거리 · 다 거둔 것으로 보는 거리 (칸)
var _detach_limit := 1800
var _recover_reach := 1.5
var _recover_done := 2.0
var _damage_temp: float
var _range := {}  # Pattern -> 셀
## 물줄기를 막는 가구 높이 {Vector3i(x, y, 층): m} · 관창 높이(선 자세·낮은 자세) · 차체가 막는가 (data/fire/fire_params.json)
var _furn_h: Dictionary = {}
var _nozzle_h := 1.0
var _nozzle_low_h := 0.7
var _vehicles_block := true
## 경계 관창이 위층을 겨눌 때 층마다 치는 높이 (m — fire_params exterior_floor_height_m)
var _ext_floor_m := 3.0
## 주수 형태별 물 사용 비율 (펜슬링은 끊어 쏜다)
var _flow := {HoseLine.Pattern.STRAIGHT: 1.0, HoseLine.Pattern.FOG: 1.0}
var _cover_cells := 5.0
## 호스에 물이 차오르는 속도 (칸/초)
var _charge_cells_per_s := 0.0
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
	_req_per_mw = config.value("required_flow_lps_per_mw") * 60.0
	_critical_per_m2 = config.value("critical_flow_lpm_per_m2")
	_tt = config.params.get("task_times", {})
	_fog_mix = config.value("fog_no_vent_mix_per_s")
	_push_fog = config.value("push_fog")
	_push_straight = config.value("push_straight")
	_push_vented_ratio = config.value("push_vented_ratio")
	_push_min_t = config.value("push_min_t_c")
	_push_rate = config.value("push_rate_per_s")
	_advance_min_m = config.value("advance_min_move_m")
	_advance_backoff_ticks = roundi(float(config.value("advance_backoff_max_s")) / SimClock.TICK_DT)
	_short_ticks = roundi(config.value("flow_short_report_s") / SimClock.TICK_DT)
	_hydrant_range = config.value("hydrant_range_m") / _cell_m
	_supply_range = config.value("supply_range_m") / _cell_m
	_drag_factor = config.value("hose_drag_speed_factor")
	_recover_factor = config.value("hose_recover_speed_factor") if config.params.has("hose_recover_speed_factor") else 0.45
	_nozzle_reach = (config.value("nozzle_reach_m") if config.params.has("nozzle_reach_m") else 0.75) / _cell_m
	_detach_limit = roundi((config.value("hose_detach_limit_s") if config.params.has("hose_detach_limit_s") else 180.0) / SimClock.TICK_DT)
	_recover_reach = (config.value("hose_recover_reach_m") if config.params.has("hose_recover_reach_m") else 0.75) / _cell_m
	_recover_done = (config.value("hose_recover_done_m") if config.params.has("hose_recover_done_m") else 1.0) / _cell_m
	_port_behind = config.value("hose_port_behind_m") / _cell_m
	indoor_tank_l = p_building.indoor_tank_l
	_damage_temp = config.value("water_damage_temp_c")
	# 물줄기를 막는 가구 높이 (2026-11-24): 칸마다 그 칸 가구의 높이 {Vector3i(x, y, 층): m}
	_nozzle_h = config.value("nozzle_height_m") if config.params.has("nozzle_height_m") else 1.0
	_nozzle_low_h = config.value("nozzle_height_low_m") if config.params.has("nozzle_height_low_m") else 0.7
	_vehicles_block = config.params.has("vehicle_blocks_water") and config.value("vehicle_blocks_water") > 0.0
	_ext_floor_m = config.value("exterior_floor_height_m") if config.params.has("exterior_floor_height_m") else 3.0
	var heights: Dictionary = config.params.get("furniture_height_m", {}).get("value", {})
	for lv: int in building.levels():
		for item: Dictionary in building.furniture(lv):
			var fh := float(heights.get(str(item.get("name", "")), 0.0))
			if fh <= 0.0:
				continue
			var r: Rect2i = item.rect
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var key := Vector3i(x, y, lv)
					_furn_h[key] = maxf(fh, float(_furn_h.get(key, 0.0)))
	_range[HoseLine.Pattern.STRAIGHT] = config.value("straight_range_m") / _cell_m
	_range[HoseLine.Pattern.FOG] = config.value("fog_range_m") / _cell_m
	_radius[HoseLine.Pattern.STRAIGHT] = config.value("straight_radius_m") / _cell_m
	_radius[HoseLine.Pattern.FOG] = config.value("fog_radius_m") / _cell_m
	_fuel_eff[HoseLine.Pattern.STRAIGHT] = config.value("straight_fuel_eff")
	_fuel_eff[HoseLine.Pattern.FOG] = config.value("fog_fuel_eff")
	_gas_eff[HoseLine.Pattern.STRAIGHT] = config.value("straight_gas_eff")
	_gas_eff[HoseLine.Pattern.FOG] = config.value("fog_gas_eff")
	# 펜슬링·3D·엄호 (R11)
	for pair in [[HoseLine.Pattern.PENCIL, "pencil"], [HoseLine.Pattern.COVER, "cover"]]:
		_range[pair[0]] = config.value(pair[1] + "_range_m") / _cell_m
		_radius[pair[0]] = config.value(pair[1] + "_radius_m") / _cell_m
		_fuel_eff[pair[0]] = config.value(pair[1] + "_fuel_eff")
		_gas_eff[pair[0]] = config.value(pair[1] + "_gas_eff")
		_flow[pair[0]] = config.value(pair[1] + "_flow_factor")
	_cover_cells = config.value("cover_protect_m") / _cell_m
	# 물머리 속도 (칸/초) = 송수량 ÷ 호스 1m의 부피 (D3). 40mm면 1m에 약 1.26L, 1본 15m에 약 19L
	var liters_per_m := PI * pow(config.value("hose_diameter_mm") / 2000.0, 2.0) * 1000.0
	_charge_cells_per_s = config.value("hose_charge_lpm") / 60.0 / liters_per_m / _cell_m


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
		_start_work(v, "hydrant", hydrant, _hydrant_distance(v, hydrant) * _cell_m, tick)
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
		_start_work(t, "supply", pump_id, t.pos.distance_to(p.pos) * _cell_m, tick)
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
	# 방수구에서 멀리 있으면 (다른 층·건물 밖) 호스 가방을 들고 방수구까지 올라가서 거기서 깐다.
	# 예전에는 방수구에서 대원 위치(건물 밖)까지 호스를 깔아, 계단을 오르기도 전에 호스 길이 한계에 묶였다 (P9 봇 점검)
	if not _at_outlet(c, h):
		h.to_outlet = true
		h.points = [Vector3i(start.x, start.y, o.z)] as Array[Vector3i]
		h.ready_tick = 1 << 40
		hoses.append(h)
		units.order_move([crew_id] as Array[int], Vector3i(start.x, start.y, o.z), pathfinder)
		events.add(tick, "hose_to_outlet", {"crew": _crew_name(c), "level": building.floor_name(o.z)})
		return true
	h.points = path
	_set_hose_timing(h, c, tick, true)
	if h.length_cells() > h.max_cells:
		if report:
			events.add(tick, "hose_too_short", {"crew": _crew_name(c)})
		return false
	hoses.append(h)
	for ff in c.members():
		ff.speed_factor = _drag_factor
	events.add(tick, "hose_outlet_laid", {"crew": _crew_name(c), "level": building.floor_name(o.z), "indoor": indoor})
	return true


## 조장이 수관을 시작할 곳 가까이(같은 층 OUTLET_REACH_CELLS 안)에 있는가 — 방수구 수관은 방수구, 펌프차 수관은 차 후면(첫 칸)
func _at_outlet(c: Crew, h: HoseLine) -> bool:
	var o := building.outlets[h.outlet] if h.outlet >= 0 else h.points[0]
	return c.leader.level == o.z and c.leader.pos.distance_to(Vector2(o.x, o.y) + Vector2(0.5, 0.5)) <= OUTLET_REACH_CELLS


## 수관을 시작할 곳에 닿았다: 거기서부터 수관을 깔고(결합·충수 시간 시작) 방수 위치로 간다.
## 방수구 = 호스 가방을 풀어 결합 / 펌프차 후면 = 호스를 꺼낸다 (그동안 서 있다 — _begin_fetch)
func _connect_at_outlet(h: HoseLine, c: Crew, tick: int) -> void:
	h.to_outlet = false
	var start := h.points[0]
	var path := pathfinder.find_path(start, c.leader.cell3())
	h.points = path if not path.is_empty() else [start] as Array[Vector3i]
	_set_hose_timing(h, c, tick, h.outlet >= 0)
	for ff in c.members():
		ff.speed_factor = _drag_factor
	if h.outlet >= 0:
		events.add(tick, "hose_outlet_laid", {"crew": _crew_name(c), "level": building.floor_name(start.z), "indoor": h.vehicle_id == INDOOR})
	else:
		_begin_fetch(h, c, tick)
		events.add(tick, "hose_laid", {"crew": _crew_name(c), "vehicle": _name(units.get_vehicle(h.vehicle_id))})
	# 방수 지시를 받고 꺼내 왔다: 방수 위치로 간다. 닿는 자리가 없으면(다른 층의 창 등) 방수를 접는다 —
	# 전에는 접지 않아 차 뒤에 선 채 '방수 중'으로 남아 탱크 물만 비웠다 (2026-11-24)
	if (h.flowing or h.standby) and not _approach(h, c, tick):
		stop_spray(c.id, tick)


## 펌프차 후면에서 호스를 꺼낸다 (docs/motions.md E1): 수관 준비 시간(crew_hose_prep_s, 혼자면 2배) 동안 분대가 서 있고,
## 끝나면 깔면서 간다 (_update_hoses). 결합 시간은 그 뒤 걸으면서 흐른다 (ready_tick = 준비 + 결합)
func _begin_fetch(h: HoseLine, c: Crew, tick: int) -> void:
	var prep := float(_tt.get("crew_hose_prep_s", 20.0)) * (2.0 if c.able_workers() <= 1 else 1.0)
	h.fetch_ticks = roundi(prep / SimClock.TICK_DT)
	h.fetch_until = tick + h.fetch_ticks
	for ff in c.members():
		ff.speed_factor = 0.0


## 수관이 시작하는 칸: 펌프차 후면 방수구 바로 뒤 (2026-11-21 — 예전에는 차 가운데)
func hose_start_cell(v: Vehicle) -> Vector2i:
	var rear: Vector2 = v.rear_point(_port_behind)
	var cell := pathfinder.nearest_walkable(v.level, Vector2i(floori(rear.x), floori(rear.y)))
	# 차 뒤가 지도 밖이면 차 자리에서
	return cell if cell != Pathfinder.NO_CELL else pathfinder.nearest_walkable(v.level, v.cell())


## 수관 연장: 분대가 펌프차 후면으로 가서 호스를 꺼내고(준비 시간 동안 서 있다), 거기서부터 깔면서 간다
## (2026-11-21, docs/motions.md E1·D6 — 예전에는 대원이 서 있는 자리까지 호스가 한 번에 생겼다).
## 이미 차 후면에 있으면 바로 꺼내기 시작한다
func lay_hose(crew_id: int, vehicle_id: int, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	var v := units.get_vehicle(vehicle_id)
	if c == null or v == null or not v.is_pump() or hose_of_crew(crew_id) != null:
		return false
	var start := hose_start_cell(v)
	var start3 := Vector3i(start.x, start.y, v.level)
	if pathfinder.find_path(start3, c.leader.cell3()).is_empty():
		return false
	var h := HoseLine.new()
	h.id = hoses.size()
	h.vehicle_id = vehicle_id
	h.crew_id = crew_id
	h.max_cells = v.hose_max_cells
	h.points = [start3] as Array[Vector3i]
	hoses.append(h)
	if _at_outlet(c, h):
		_connect_at_outlet(h, c, tick)
		return true
	h.to_outlet = true
	h.ready_tick = 1 << 40
	units.order_move([crew_id] as Array[int], start3, pathfinder)
	events.add(tick, "hose_fetch", {"crew": _crew_name(c), "vehicle": _name(v)})
	return true


## 목표 층에서 쓸 수관이 옥내 방수구(연결송수관·옥내소화전)에서 나오는가 — 그러면 그 층에 올라가서 결합한다 (차에서 꺼내 가지 않는다)
func uses_outlet(target_level: int) -> bool:
	var standpipe_ok := fdc_vehicle >= 0 or (building.indoor_lpm > 0.0 and indoor_tank_l > 0.0)
	return standpipe_ok and target_level > 1 and building.outlet_on(target_level) >= 0


## 수관이 없으면 연장을 시작한다: 목표 층에 쓸 방수구가 있으면 방수구에서, 아니면 펌프차 후면에서 꺼낸다
## (자기 출동대의 펌프차 먼저, 없으면 가장 가까운 펌프차 — 2026-11-24 사용자·현직 소방관: 진압 지시를 받으면 본인 차량에서 호스를 챙겨 간다).
## 이미 수관이 있으면 그대로 true. 연장을 시작할 수 없으면 false
## take = 놓인 관창을 다시 잡거나 이어받아도 되는가 (건물 안이거나 진입 허가를 받았고 진입 금지 요소가 없을 때 — 부르는 쪽이 정한다).
## 경계 관창(외부 방수)은 false: 건물 안 관창을 쓰러 들어가지 않고 새 호스를 꺼낸다 (2026-11-24 검사: 긴급 탈출 뒤 외부 방수 지시에
## 대원이 건물 안으로 다시 들어갔다)
func ensure_hose(crew_id: int, target_level: int, tick: int, take := true) -> bool:
	var c := units.get_crew(crew_id)
	if c == null:
		return false
	# 건물 밖의 조는 진입 허가를 받았고 진입 금지 요소가 없을 때만 건물 안 관창을 잡으러 간다 (CommandSystem.can_take_hose)
	if take and take_allowed.is_valid() and not bool(take_allowed.call(crew_id)):
		take = false
	var mine := hose_of_crew(crew_id)
	if mine != null and mine.dropped and not mine.to_nozzle and not take:
		# 놓고 간 관창을 쓰지 않는다: 주인을 풀고 새 호스를 꺼낸다
		release_dropped(crew_id)
		mine = null
	if mine != null:
		# 놓고 간 관창이 있으면 호스를 따라 다시 잡으러 간다 / 거두는 중이었으면 거두기를 멈추고 관창 쪽으로 다시 간다
		if mine.dropped and not mine.to_nozzle:
			return_to_nozzle(crew_id, tick)
		elif mine.recovering:
			mine.recovering = false
			mine.detach_tick = -1
			for ff in c.members():
				ff.speed_factor = _drag_factor
		return true
	# 교대조 인수 (2026-11-24 사용자 결정): 다른 조가 놓고 간 관창이 있으면 새 호스를 꺼내지 않고 그 호스를 따라가 이어받는다
	if take and take_over(crew_id, target_level, tick):
		return true
	if uses_outlet(target_level) and lay_hose_outlet(crew_id, building.outlet_on(target_level), tick, false):
		return true
	var pump := _own_pump(c)
	if pump >= 0 and lay_hose(crew_id, pump, tick):
		return true
	var near := _nearest_pump(c.leader.pos)
	return near >= 0 and near != pump and lay_hose(crew_id, near, tick)


## 펌프차 후면에서 호스를 꺼내는 중인가 (후면으로 가는 중이거나 꺼내느라 서 있는 중) — 끝나야 현장으로 간다
func fetching(crew_id: int) -> bool:
	var h := hose_of_crew(crew_id)
	if h != null and h.to_nozzle:
		# 놓인 관창으로 호스를 따라 가는 중 (교체 뒤 재진입·교대조 인수) — 잡아야 현장으로 간다
		return true
	return h != null and h.outlet < 0 and (h.to_outlet or h.fetch_until >= 0)


## 아직 깔기 전의 수관을 거둔다 — 펌프차 후면으로 가는 중 · 차 뒤에서 꺼내는 중 · 방수구로 호스 가방을 들고 가는 중에
## 다른 지시(이동·검색·구조·대기 등 호스가 필요 없는 일)를 받았다. 호스는 차(가방)에 도로 넣은 것으로 친다.
## 2026-11-24 — 전에는 지울 길이 없어, 다른 곳으로 보내도 멈추면 1초마다 다시 펌프차로 끌려갔고(_update_hoses),
## 꺼내는 동안은 속도 0으로 묶여 아예 움직이지 않았다. 이미 깔기 시작한 수관은 그대로 둔다 (false)
func cancel_fetch(crew_id: int, tick: int) -> bool:
	var h := hose_of_crew(crew_id)
	if h != null and (h.to_nozzle or h.recovering):
		# 놓인 관창으로 가던 중·호스를 거두던 중에 다른 지시: 호스는 거기 놓아 둔다 (다시 잡으러 오거나 교대조가 이어받는다)
		h.to_nozzle = false
		h.recovering = false
		h.dropped = true
		h.approaching = false
		h.flowing = false
		h.standby = false
		# 제한 시간은 다시 잡으러 갈 때 새로 센다 (안 지우면 한참 뒤 다시 갈 때 가자마자 '못 감'으로 끝난다)
		h.detach_tick = -1
		var dc := units.get_crew(crew_id)
		if dc != null:
			for ff in dc.members():
				ff.speed_factor = 1.0
		return true
	if h == null or not (h.to_outlet or h.fetch_until >= 0):
		return false
	hoses.erase(h)
	var c := units.get_crew(crew_id)
	if c != null:
		for ff in c.members():
			ff.speed_factor = 1.0
		events.add(tick, "hose_fetch_cancel", {"crew": _crew_name(c), "crew_id": crew_id})
	return true


## 열기에 길이 막혔다 (2026-11-25, SimWorld._on_heat_stop): 호스를 거두던 조·놓인 관창으로 가던 조는 수관을 그 자리에 놓아 둔다
## (긴급 철수와 같은 처리 — 수관은 놓인 채 남아 다시 잡으러 오거나 다른 조가 이어받는다).
## 전에는 멈출 때마다 1초 뒤 다시 길을 잡아(_update_detached) 열기를 피해 물러나지 못했고, 불난 방 문턱에 선 채 열 스트레스로 쓰러졌다.
## 놓았으면 "recover"(거두던 중) · "nozzle"(관창으로 가던 중), 해당 없으면 ""
func leave_for_heat(crew_id: int, tick: int) -> String:
	var h := hose_of_crew(crew_id)
	if h == null or not (h.recovering or h.to_nozzle):
		return ""
	var kind := "recover" if h.recovering else "nozzle"
	h.to_nozzle = false
	h.recovering = false
	h.dropped = true
	h.approaching = false
	h.flowing = false
	h.standby = false
	h.detach_tick = -1
	var c := units.get_crew(crew_id)
	if c != null:
		for ff in c.members():
			ff.speed_factor = 1.0
		if kind == "recover":
			events.add(tick, "hose_left_heat", {"crew": _crew_name(c), "crew_id": crew_id})
	return kind


## 조가 손에 들고 있는 수관 (놓고 갔거나 관창으로 가는 중·거두는 중이면 null) — 그림·방수 배치는 이것을 본다
func held_hose(crew_id: int) -> HoseLine:
	var h := hose_of_crew(crew_id)
	return h if h != null and h.held() else null


## 그 조가 놓고 간 수관의 주인을 푼다 (다른 임무를 받았다 — 2026-11-24 검사): 그 조는 이제 '수관을 가진 조'가 아니라
## 구조·새 호스 등을 받을 수 있고, 놓인 수관은 다른 조가 이어받는다. 풀었으면 true
func release_dropped(crew_id: int) -> bool:
	var h := hose_of_crew(crew_id)
	if h == null or not h.dropped or h.to_nozzle:
		return false
	h.crew_id = -1
	return true


## 깔린 수관인가 (꺼내러 가는 중·꺼내는 중이 아니다)
func _laid(h: HoseLine) -> bool:
	return h != null and not h.to_outlet and h.fetch_until < 0


## 관창을 그 자리에 놓고 떠난다 (2026-11-24 사용자 결정 — 긴급 철수·공기호흡기 교체): 관창을 잠그고, 호스는 깔린 그대로 둔다.
## 조는 호스에서 풀려 제 빠르기로 움직인다. 깔린 수관이 없으면 false
func drop_nozzle(crew_id: int, tick: int) -> bool:
	var h := hose_of_crew(crew_id)
	if not _laid(h) or not h.held():
		return false
	stop_spray(crew_id, tick)
	h.approaching = false
	h.dropped = true
	var c := units.get_crew(crew_id)
	for ff in c.members():
		ff.speed_factor = 1.0
	var end := h.points[-1]
	events.add(tick, "nozzle_dropped", {"crew": _crew_name(c), "crew_id": crew_id, "level": building.floor_name(end.z)})
	return true


## 철수하며 호스를 거둔다 (2026-11-24 사용자 결정 — 방수 뒤 철수 명령): 관창을 놓은 자리부터 호스를 접어 들며 펌프차(방수구)로
## 돌아간다 (hose_recover_speed_factor). 다 거두면 수관이 없어진다 (_update_hoses). 깔린 수관이 없으면 false
func recover_hose(crew_id: int, tick: int) -> bool:
	var h := hose_of_crew(crew_id)
	if not _laid(h) or h.recovering:
		return false
	stop_spray(crew_id, tick)
	h.dropped = false
	h.to_nozzle = false
	h.recovering = true
	h.approaching = false
	var c := units.get_crew(crew_id)
	for ff in c.members():
		ff.speed_factor = _recover_factor
	units.order_move([crew_id] as Array[int], h.points[0], pathfinder)
	events.add(tick, "hose_recover", {"crew": _crew_name(c), "crew_id": crew_id})
	return true


## 놓인 관창으로 호스를 따라 간다 (교체 뒤 재진입). 닿으면 다시 잡는다 (_update_hoses → nozzle_picked_up)
func return_to_nozzle(crew_id: int, tick: int) -> bool:
	var h := hose_of_crew(crew_id)
	if h == null or not h.dropped:
		return false
	h.to_nozzle = true
	units.order_move([crew_id] as Array[int], h.points[-1], pathfinder)
	events.add(tick, "nozzle_return", {"crew": _crew_name(units.get_crew(crew_id)), "crew_id": crew_id})
	return true


## 놓인(아무도 다시 잡으러 가지 않는) 수관을 다른 조가 이어받는다 (교대조 인수, 2026-11-24 사용자 결정).
## 목표 층에 관창이 놓인 수관을 먼저, 없으면 가장 가까운 것. 이어받으면 그 조가 호스를 따라 관창으로 간다
func take_over(crew_id: int, target_level: int, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	if c == null or hose_of_crew(crew_id) != null:
		return false
	var best: HoseLine = null
	var best_d := INF
	for h in hoses:
		if not h.dropped or h.to_nozzle or h.recovering:
			continue
		var end := h.points[-1]
		var d := c.leader.pos.distance_to(Vector2(end.x, end.y)) + (0.0 if end.z == target_level else 1000.0)
		if d < best_d:
			best_d = d
			best = h
	if best == null:
		return false
	var from := units.get_crew(best.crew_id)
	best.crew_id = crew_id
	best.to_nozzle = true
	units.order_move([crew_id] as Array[int], best.points[-1], pathfinder)
	events.add(tick, "hose_takeover", {"crew": _crew_name(c), "crew_id": crew_id, "from": _crew_name(from) if from != null else "",
		"level": building.floor_name(best.points[-1].z)})
	return true


## 놓인 관창 처리 (_update_hoses): 다시 잡으러 가는 조가 닿았으면 잡고, 거두는 조는 지나온 만큼 호스를 걷는다.
## 수관을 지웠으면 true (그 수관은 더 보지 않는다)
func _update_detached(h: HoseLine, c: Crew, tick: int) -> bool:
	var leader := c.leader
	if h.detach_tick < 0:
		h.detach_tick = tick
	# 조장이 쓰러졌거나 정한 시간 안에 못 했으면(길이 막힘) 그만두고 놓인 수관으로 되돌린다 — 다른 조가 이어받을 수 있게 (2026-11-24 검사)
	if leader.incapacitated or tick - h.detach_tick > _detach_limit:
		h.to_nozzle = false
		h.recovering = false
		h.dropped = true
		h.approaching = false
		h.flowing = false
		h.standby = false
		h.detach_tick = -1
		for ff in c.members():
			ff.speed_factor = 1.0
		h.crew_id = -1
		events.add(tick, "hose_abandoned", {"crew": _crew_name(c), "crew_id": c.id})
		return false
	if h.to_nozzle:
		var end := h.points[-1]
		if leader.level == end.z and leader.pos.distance_to(Vector2(end.x, end.y) + Vector2(0.5, 0.5)) <= _nozzle_reach + 0.5:
			h.detach_tick = -1
			h.to_nozzle = false
			h.dropped = false
			for ff in c.members():
				ff.speed_factor = _drag_factor
			events.add(tick, "nozzle_picked_up", {"crew": _crew_name(c), "crew_id": c.id})
			# 방수 지시를 받고 잡으러 왔다: 방수 위치로 간다 (닿는 자리가 없으면 방수를 접는다)
			if (h.flowing or h.standby) and not _approach(h, c, tick):
				stop_spray(c.id, tick)
		elif not leader.is_moving() and not leader.incapacitated and tick % roundi(1.0 / SimClock.TICK_DT) == 0:
			units.order_move([c.id] as Array[int], end, pathfinder)
		return false
	if h.recovering:
		# 조장 가까이(같은 층 1.5칸 안)의 가장 앞쪽(펌프차 쪽) 점까지만 남긴다 — 지나온 호스는 거둔 것
		var here := leader.cell3()
		for k in h.points.size():
			var p := h.points[k]
			if p.z == here.z and Vector2(p.x, p.y).distance_to(Vector2(here.x, here.y)) <= _recover_reach:
				if k + 1 < h.points.size():
					h.points.resize(k + 1)
				break
		if h.points.size() <= 1 or (not leader.is_moving() and leader.cell3().distance_to(h.points[0]) <= _recover_done):
			hoses.erase(h)
			for ff in c.members():
				ff.speed_factor = 1.0
			events.add(tick, "hose_recovered", {"crew": _crew_name(c), "crew_id": c.id})
			return true
		if not leader.is_moving() and not leader.incapacitated and tick % roundi(1.0 / SimClock.TICK_DT) == 0:
			units.order_move([c.id] as Array[int], h.points[0], pathfinder)
		return false
	return false


## 그 조의 출동대 펌프차 (여러 대면 가장 가까운 것). 없으면 -1
func _own_pump(c: Crew) -> int:
	var best := -1
	var best_d := INF
	for v in units.vehicles_of_squad(c.squad_id):
		if v.is_pump() and v.distance_to_body(c.leader.pos) < best_d:
			best_d = v.distance_to_body(c.leader.pos)
			best = v.id
	return best


## 방수 시작. 수관이 없으면 펌프차(자기 차 먼저)에서 자동으로 연장하고,
## 목표가 사거리 밖이거나 벽에 가려 있으면 물줄기가 닿는 위치까지 먼저 이동한다.
## exterior = 경계 관창: 바깥 지상에서 건물의 창·외벽(위층일 수 있다)으로 올려 쏜다 — 건물 안으로 들어가지 않는다.
## standby = 관창을 배치만 한다 (방수 위치로 가서 겨눈 채 잠가 둔다 — 불이 다가오면 TacticalSystem이 연다)
## take = 놓인 관창을 다시 잡거나 이어받아도 되는가 (외부 방수 임무는 false — 건물 안 관창을 쓰러 들어가지 않는다)
func start_spray(crew_id: int, target: Vector3i, pattern: HoseLine.Pattern, tick: int, exterior := false, standby := false, take := true) -> bool:
	var c := units.get_crew(crew_id)
	if c == null:
		return false
	# 경계 관창은 옥내 방수구가 아니라 차에서 끌어온다 (밖에 선다)
	if not ensure_hose(crew_id, c.leader.level if exterior else target.z, tick, take and not exterior):
		return false
	var h := hose_of_crew(crew_id)
	h.pattern = pattern
	h.target = target
	h.aim = Vector2(target.x + 0.5, target.y + 0.5)
	h.approaching = false
	h.next_advance_tick = tick
	h.flame_tick = -1
	h.exterior = exterior
	h.standby = standby
	if h.to_outlet or h.to_nozzle:
		# 아직 방수구로 가는 중 / 놓인 관창으로 가는 중: 닿아서 연결(잡은) 뒤 방수 위치로 간다
		h.approaching = true
	elif not _approach(h, c, tick):
		h.exterior = false
		h.standby = false
		return false
	if standby:
		h.flowing = false
		h.flow_fraction = 0.0
		return true
	h.flowing = true
	events.add(tick, "spray_start", {"crew": _crew_name(c), "pattern": h.pattern_name()})
	return true


## 목표에 물이 닿지 않으면 닿는 위치로 이동시킨다. 그런 위치가 없으면 false
func _approach(h: HoseLine, c: Crew, tick: int) -> bool:
	var goal := Vector2(h.target.x + 0.5, h.target.y + 0.5)
	h.approaching = false
	if h.exterior:
		if exterior_reach(c.leader.pos, c.leader.level, h.target):
			return true
		var out := _exterior_cell(c, h.target)
		if out == Pathfinder.NO_CELL:
			events.add(tick, "spray_unreachable", {"crew": _crew_name(c)})
			return false
		units.order_move([c.id] as Array[int], Vector3i(out.x, out.y, c.leader.level), pathfinder)
		h.approaching = true
		return true
	if _can_spray_to(c.leader.pos, c.leader.level, goal, h.target.z, h.pattern):
		return true
	var spot := _approach_cell(c, goal, h.target.z, h.pattern)
	if spot == Pathfinder.NO_CELL:
		events.add(tick, "spray_unreachable", {"crew": _crew_name(c)})
		return false
	units.order_move([c.id] as Array[int], Vector3i(spot.x, spot.y, h.target.z), pathfinder)
	h.approaching = true
	return true


## 경계 관창이 겨눌 곳: 찍은 칸 가까이(2.5칸)에 바깥으로 난 창·문이 있으면 그 칸 (그 층), 없으면 찍은 칸 그대로
func exterior_target(target: Vector3i) -> Vector3i:
	var at := Vector2(target.x + 0.5, target.y + 0.5)
	var best := target
	var best_d := 2.5
	for o in fire.openings:
		if o.level != target.z or o.kind == Opening.Kind.STAIR or o.room_b != Opening.OUTSIDE:
			continue
		for cell in o.cells:
			var d := at.distance_to(Vector2(cell) + Vector2(0.5, 0.5))
			if d < best_d:
				best_d = d
				best = Vector3i(cell.x, cell.y, o.level)
	return best


## 바깥 지상의 pos(층 level)에서 건물의 target(창·외벽 — 위층일 수 있다)까지 직사가 닿는가:
## 수평 거리와 높이(층마다 exterior_floor_height_m)를 합친 거리가 사거리 안이고, 지상에서 그 벽면까지 가리는 것(다른 건물·차)이 없다
func exterior_reach(pos: Vector2, level: int, target: Vector3i) -> bool:
	if not building.cell(level, floori(pos.x), floori(pos.y)) in BuildingData.OUTDOOR:
		return false
	var goal := Vector2(target.x + 0.5, target.y + 0.5)
	var rise := absf(building.floor_number(target.z) - building.floor_number(level)) * _ext_floor_m / _cell_m
	var flat := pos.distance_to(goal)
	if Vector2(flat, rise).length() > _range[HoseLine.Pattern.STRAIGHT] * APPROACH_RANGE_RATIO:
		return false
	# 너무 바짝 붙으면 위로 쏠 수 없다 (높이의 절반은 물러선다)
	if flat < rise * 0.5:
		return false
	var tr := _trace(level, pos, goal, INF, _nozzle_h)
	return (tr.impact as Vector2).distance_to(goal) <= 1.5


## 경계 관창을 놓을 자리: 그 벽면에 직사가 닿는 바깥 칸 가운데 조에서 가장 가까운 곳 (길이 있는 곳)
func _exterior_cell(c: Crew, target: Vector3i) -> Vector2i:
	var level := c.leader.level
	var r := ceili(_range[HoseLine.Pattern.STRAIGHT] * APPROACH_RANGE_RATIO)
	var candidates: Array[Vector2i] = []
	for y in range(target.y - r, target.y + r + 1):
		for x in range(target.x - r, target.x + r + 1):
			if not pathfinder.passable(level, x, y) or not exterior_reach(Vector2(x + 0.5, y + 0.5), level, target):
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


## 겨눈 곳(target)에 불꽃이 있는가 (관창을 잠가 둔 채로도 본다): 경계 관창(exterior)은 열렸거나 깨진 창 안쪽,
## 그 밖에는 겨눈 곳 둘레(직사가 퍼지는 반경)의 타는 칸
func flames_at(target: Vector3i, exterior: bool) -> bool:
	var grid := fire.grid
	var goal := Vector2(target.x + 0.5, target.y + 0.5)
	var cell := Vector2i(target.x, target.y)
	if exterior:
		var o := fire.opening_at(target)
		if o == null or not (o.is_open or o.broken):
			return false
	for i in _reachable_cells(target.z, goal, cell, grid.cells_in_radius(target.z, goal, _radius[HoseLine.Pattern.STRAIGHT])):
		if grid.state[i] == FuelGrid.State.BURNING:
			return true
	return false


## 관창을 잠그고 그 자리에서 계속 지킨다 (경계 관창: 식었다 — 다시 달궈지면 TacticalSystem이 연다)
func hold_nozzle(crew_id: int, tick: int) -> void:
	var h := hose_of_crew(crew_id)
	if h == null:
		return
	if h.flowing:
		h.flowing = false
		h.flow_fraction = 0.0
		events.add(tick, "spray_stop", {"crew": _crew_name(units.get_crew(crew_id))})
	h.approaching = false
	h.spraying = false
	h.standby = true


## 호스 1본 길이 (칸) — 화면의 결합구 간격
func hose_length_cells() -> float:
	return float(_tt.get("hose_length_m", 15.0)) / _cell_m


## 호스가 다 차는 데 걸리는 시간 (초) = 호스 안 부피 ÷ 송수량. length_cells: 호스 길이 (칸)
func charge_seconds(length_cells: float) -> float:
	return length_cells / _charge_cells_per_s if _charge_cells_per_s > 0.0 else 0.0


## 예비 송수 (화재1 제4장 제9절 "호스 연장이 끝나기 직전부터 서서히 송수", docs/motions.md D3):
## 수관 준비·결합이 끝나면 운전원이 스스로 송수한다. 물머리가 펌프차 쪽부터 나아가 관창에 닿으면 충수 완료를 보고한다.
## 한 번 찬 호스는 끌고 가도 차 있다. 물을 줄 곳(탱크·옥내 수조)이 비었으면 차오르지 않는다.
## 호스를 채우는 물(40mm 1본 약 19L)은 탱크 잔량에서 빼지 않는다 (탱크 2,800L에 견주어 작다 — 단순화)
func _update_charge(dt: float, tick: int) -> void:
	for h in hoses:
		if h.to_outlet:
			continue
		var length := h.length_cells()
		if h.charged:
			h.water_head = length
			continue
		h.water_head = minf(h.water_head, length)
		if tick < h.ready_tick or not _source_has_water(h):
			continue
		h.water_head = minf(length, h.water_head + _charge_cells_per_s * dt)
		if h.water_head >= length - SimClock.EPSILON:
			h.charged = true
			var c := units.get_crew(h.crew_id)
			events.add(tick, "hose_charged", {"crew": _crew_name(c), "crew_id": c.id,
				"lengths": ceili(length / maxf(0.01, hose_length_cells()) - 0.01), "meters": roundi(length * _cell_m)})


## 그 수관에 물을 줄 곳에 물이 있는가 (펌프차 탱크 또는 옥내소화전 수조)
func _source_has_water(h: HoseLine) -> bool:
	if h.vehicle_id == INDOOR:
		return indoor_tank_l > 0.0
	var v := units.get_vehicle(h.vehicle_id)
	return v != null and v.tank_l > EMPTY_TANK_L


func stop_spray(crew_id: int, tick: int) -> void:
	var h := hose_of_crew(crew_id)
	if h:
		# 경계 관창 배치도 푼다 (다른 지시를 받았다)
		h.standby = false
		h.exterior = false
		h.spraying = false
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
	return not _trace(level, pos, target, _range[pattern], _nozzle_h).blocked


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
	# 지난번 전진이 헛걸음이었나 (지시한 그 칸에 그대로 서 있다 — 열기에 막혔거나 갈 길이 없었다): 다음 시도를 점점 늦춘다.
	# 2026-11-27 사용자: 방수 중 대원들이 왔다갔다 한다 — 5초마다 전진을 지시했다가 한 틱 만에 풀려 방수 대형이 무너졌다
	if h.advance_from.x >= 0:
		h.advance_fails = h.advance_fails + 1 if c.leader.cell3() == h.advance_from else 0
		h.advance_from = Vector3i(-1, -1, -1)
	h.next_advance_tick = tick + mini(ADVANCE_EVERY_TICKS * (1 + h.advance_fails * 2), _advance_backoff_ticks)
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
	# 같은 방 안에서 한두 걸음 옮기는 것뿐이면 그 자리에서 계속 쏜다 (대형을 풀지 않는다).
	# 밖에서 문턱을 넘는 걸음·다른 방으로 넘어가는 걸음은 짧아도 막지 않는다 (2026-11-27 — 현관 밖 진압 분대가 들어가지 못했다)
	var here := c.leader.cell3()
	var crossing := building.cell(here.z, here.x, here.y) in BuildingData.OUTDOOR \
		or fire.compartment_at(here.z, here.x, here.y) != fire.compartment_at(h.target.z, spot.x, spot.y)
	if not crossing and (Vector2(spot) + Vector2(0.5, 0.5)).distance_to(from) * fire.building.cell_size_m < _advance_min_m:
		return
	h.advance_from = c.leader.cell3()
	units.order_move([c.id] as Array[int], Vector3i(spot.x, spot.y, h.target.z), pathfinder)
	# 갈 길이 없으면 접근 상태로 바꾸지 않는다 (한 틱 풀렸다 돌아오는 깜빡임을 막는다)
	if c.leader.path.is_empty():
		return
	h.approaching = true


# --- 매 틱 ---

func step(dt: float, tick: int) -> void:
	_update_flow_ratio(tick)
	_step_work(dt, tick)
	for c in fire.comps:
		c.cooling_kw = 0.0
		c.applied_lpm = 0.0
	_update_pending(tick)
	_update_hoses(tick)
	_update_charge(dt, tick)
	_update_supply(dt, tick)
	_apply_sprays(dt, tick)


## 관창 방수량 (L/분): 건물 밖에서 쏘면 65mm, 안이면 40mm (기획안 5-4). 옥내소화전은 건물 설비 값
func hose_lpm(h: HoseLine, v: Vehicle) -> float:
	if v == null:
		return building.indoor_lpm
	var leader := units.get_crew(h.crew_id).leader
	if building.cell(leader.level, floori(leader.pos.x), floori(leader.pos.y)) in BuildingData.OUTDOOR:
		return v.nozzle_65_lpm
	return v.nozzle_lpm


## 방마다 필요 방수량과 실제 방수량 비율 (지난 틱에 닿은 물 기준). 모자란 상태가 이어지면 관창수 보고 (기획안 5-4)
## 필요 방수량 (2026-11-13 사용자 결정 P2): 그 방 열방출률 1MW당 0.38 L/s (Barnett TP 2004/1), 타는 면적당 2 L/min 아래로는 내려가지 않는다 (Grimwood)
func _update_flow_ratio(tick: int) -> void:
	for c in fire.comps:
		c.required_lpm = maxf(_req_per_mw * c.q / 1000.0, _critical_per_m2 * c.burning_area_m2) * c.load_factor if c.burning_area_m2 > 0.0 else 0.0
		c.flow_ratio = c.applied_lpm / c.required_lpm if c.required_lpm > 0.0 else (10.0 if c.applied_lpm > 0.0 else 0.0)
		if c.applied_lpm > 0.0 and c.required_lpm > 0.0 and c.flow_ratio < 1.0:
			if not _short_since.has(c.index):
				_short_since[c.index] = tick
			elif tick - int(_short_since[c.index]) >= _short_ticks and not _short_reported.has(c.index):
				_short_reported[c.index] = true
				events.add(tick, "flow_short", {"room": c.display_name(), "crew": _nozzle_crew(c), "required": roundi(c.required_lpm),
					"applied": roundi(c.applied_lpm), "ratio": snappedf(c.flow_ratio, 0.01)})
		else:
			_short_since.erase(c.index)
			if c.flow_ratio >= 1.0 or c.burning_area_m2 <= 0.0:
				_short_reported.erase(c.index)


## 바깥으로 열린(깨진) 창·문이 있는 방인가 (배기구)
## 방수 밀림 (2026-11-26 사용자: 방수하면 화염이 다른 문·문틈으로 다른 방·복도로 번져야 하는데 그런 경우가 없다 —
## SOP 206-2.5·2.6 "작은 개구부로 주수 시 화염·연기 분출", "한쪽 개구부에서 방수하면 다른 쪽으로 화염·연기 분출"):
## 고온층이 뜨거운 방(push_min_t 이상)에 쏘면, 쏘는 쪽 개구부(조장에 가장 가까운 개구부)를 뺀 다른 열린 개구부로
## 고온층의 연기·열 일부가 옆 방으로 밀려간다. 분무가 직사보다 크다. 바깥으로 열린 배기구가 있으면 대부분 밖으로 빠져
## 집 안쪽으로는 push_vented_ratio 만큼만. 밀린 쪽 문 너머 칸은 복사열이 (1 + k) 배 (FuelGrid.spray_push) — 착화가 빨라진다.
## 처음 밀릴 때 쏘는 조가 무전한다
func _push_gases(h: HoseLine, leader: Firefighter, comp: Compartment, dt: float, tick: int) -> void:
	if comp.t_upper < _push_min_t:
		return
	var k := _push_fog if h.pattern == HoseLine.Pattern.FOG else _push_straight
	if k <= 0.0:
		return
	# 쏘는 쪽 개구부: 조장에 가장 가까운 그 방의 개구부
	var from: Opening = null
	for oi in comp.openings:
		var o: Opening = fire.openings[oi]
		if from == null or _opening_center(o).distance_to(leader.pos) < _opening_center(from).distance_to(leader.pos):
			from = o
	var vented := false
	for oi in comp.openings:
		var o: Opening = fire.openings[oi]
		if o != from and (o.is_open or o.broken) and (o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE):
			vented = true
	if vented:
		k *= _push_vented_ratio
	fire.grid.spray_push[comp.index] = {"from": from.index if from != null else -1, "k": k}
	var pushed: PackedStringArray = []
	for oi in comp.openings:
		var o: Opening = fire.openings[oi]
		if o == from or not (o.is_open or o.broken):
			continue
		var other := o.room_b if o.room_a == comp.index else o.room_a
		if other < 0:
			continue
		var n: Compartment = fire.comps[other]
		# 고온층의 연기와 열 일부가 넘어간다 (초당 k × push_rate_per_s)
		var f := minf(0.5, k * _push_rate * dt)
		var soot := comp.soot * f
		comp.soot -= soot
		n.soot += soot
		n.t_upper += (comp.t_upper - n.t_upper) * f
		if n.t_upper > comp.t_upper:
			n.t_upper = comp.t_upper
		pushed.append(n.display_name())
	if not pushed.is_empty() and not _push_warned.has(comp.index):
		_push_warned[comp.index] = true
		events.add(tick, "spray_push", {"crew": _crew_name(units.get_crew(h.crew_id)), "crew_id": h.crew_id, "room": comp.display_name(),
			"to": ", ".join(pushed), "vented": vented})


func _opening_center(o: Opening) -> Vector2:
	var s := Vector2.ZERO
	for c in o.cells:
		s += Vector2(c) + Vector2(0.5, 0.5)
	return s / maxf(1.0, o.cells.size())


func _vented(c: Compartment) -> bool:
	for oi in c.openings:
		var o: Opening = fire.openings[oi]
		if (o.is_open or o.broken) and (o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE):
			return true
	return false


func _nozzle_crew(c: Compartment) -> String:
	for h in hoses:
		if h.flowing:
			var cc := units.get_crew(h.crew_id)
			var cell := Vector2i(h.impact.floor())
			if fire.compartment_at(cc.leader.level, cell.x, cell.y) == c:
				return _crew_name(cc)
	return "관창수"


# --- 현장 작업 시간 (기획안 6-1, P4-1) ---

## 운전원 작업 시작: 소화전 점령·물탱크차 급수·송수구 연결. 시간 = 점령 + 호스 본 수 × 1본 연장 + 결합 × 2 (2인 기준, 혼자면 2배)
func _start_work(v: Vehicle, kind: String, target: int, dist_m: float, tick: int) -> void:
	var lengths := ceili(maxf(dist_m, 0.1) / float(_tt.get("hose_length_m", 15.0))) + 1
	var base := float(_tt.get("hose_length_s", 15.0)) * lengths + float(_tt.get("coupling_s", 5.0)) * 2.0
	if kind == "hydrant":
		base += float(_tt.get("hydrant_occupy_s", 20.0))
	var helper := _helper_crew(v)
	var people := 2 if helper >= 0 else 1
	var total := base * (2.0 if people == 1 else 1.0)
	var labels := {"hydrant": "소화전 점령", "supply": "급수 연결", "fdc": "송수구 연결"}
	v.work = {"kind": kind, "label": labels.get(kind, kind), "target": target, "remain": total, "total": total, "people": people, "lengths": lengths, "helper": helper}
	events.add(tick, "work_start", {"vehicle": _name(v), "work": labels.get(kind, kind), "seconds": roundi(total), "people": people, "lengths": lengths, "driver": v.driver_label()})


## 차량 옆(helper_radius_m)에 쉬고 있는 조가 있으면 2인 작업
func _helper_near(v: Vehicle) -> bool:
	return _helper_crew(v) >= 0


## 2인 작업을 도울 조 (차량 옆에서 쉬고 있는 조, 없으면 -1). 화면은 그 조의 조장이 차 쪽 결합을 하는 모습으로 그린다
func _helper_crew(v: Vehicle) -> int:
	var r := float(_tt.get("helper_radius_m", 4.0)) / _cell_m
	for c in units.crews:
		if c.leader.incapacitated or c.leader.aboard or c.leader.is_moving() or held_hose(c.id) != null:
			continue
		if c.leader.level == v.level and v.distance_to_body(c.leader.pos) <= r:
			return c.id
	return -1


func _step_work(dt: float, tick: int) -> void:
	for v in units.vehicles:
		if v.work.is_empty():
			continue
		if v.is_moving():
			v.work = {}
			continue
		# 혼자 하던 중에 도울 대원이 차 옆에 오면 그때부터 둘이서 — 남은 시간이 절반 (한 명 보내기 '급수 지원', 2026-11-16)
		if int(v.work.get("people", 1)) == 1 and int(v.work.get("helper", -1)) < 0:
			var helper := _helper_crew(v)
			if helper >= 0:
				v.work.people = 2
				v.work.helper = helper
				v.work.remain = float(v.work.remain) * 0.5
				v.work.total = float(v.work.total) * 0.5
				events.add(tick, "work_helped", {"vehicle": _name(v), "work": str(v.work.label), "crew": _crew_name(units.get_crew(helper)), "driver": v.driver_label()})
		v.work.remain = float(v.work.remain) - dt
		if float(v.work.remain) > SimClock.EPSILON:
			continue
		var w := v.work
		v.work = {}
		match str(w.kind):
			"hydrant":
				_connect_hydrant_now(v, int(w.target), tick)
			"supply":
				var p := units.get_vehicle(int(w.target))
				if p:
					_connect_supply_now(v, p, tick)


## 수관 준비 + 결합, 방수 개시(운전원이 압력을 올림) 시각 (2인 기준 — 조는 2인)
func _set_hose_timing(h: HoseLine, c: Crew, tick: int, outlet: bool) -> void:
	var prep := float(_tt.get("coupling_s", 5.0)) * (2.0 if not outlet else 1.0)
	if not outlet:
		prep += float(_tt.get("crew_hose_prep_s", 20.0))
	else:
		prep += float(_tt.get("crew_hose_prep_s", 20.0)) * 0.5  # 방수구 함의 호스·관창은 가까이 있다
	# 혼자면 2배. 3명 이상이어도 더 빨라지지 않는다 (교재 수치 없음 — 2026-11-16 결정)
	if c.able_workers() <= 1:
		prep *= 2.0
	h.ready_tick = tick + roundi(prep / SimClock.TICK_DT)
	# 준비가 끝나면 운전원이 서서히 송수한다 — 물머리가 관창에 닿을 때까지는 방수가 안 된다 (_update_charge)
	h.water_head = 0.0
	h.charged = false
	h.carried_loads = 1


## 작업 진행률 (0~1, 화면 진행 막대). 없으면 -1
func work_progress(v: Vehicle) -> float:
	if v.work.is_empty():
		return -1.0
	return 1.0 - float(v.work.remain) / maxf(0.1, float(v.work.total))


func _update_pending(tick: int) -> void:
	for v in units.vehicles:
		if v.is_moving():
			continue
		if v.pending_hydrant >= 0:
			var hy := v.pending_hydrant
			v.pending_hydrant = -1
			if _hydrant_distance(v, hy) <= _hydrant_range:
				_start_work(v, "hydrant", hy, _hydrant_distance(v, hy) * _cell_m, tick)
		if v.pending_supply >= 0:
			var p := units.get_vehicle(v.pending_supply)
			v.pending_supply = -1
			if p and v.pos.distance_to(p.pos) <= _supply_range:
				_start_work(v, "supply", p.id, v.pos.distance_to(p.pos) * _cell_m, tick)


## 조가 움직인 만큼 호스를 늘리거나(되돌아오면 줄이고), 적재 길이를 넘으면 조를 멈춘다.
## 휴대 한도(1인 2본)를 넘으면 차량에서 더 가져올 동안 멈춘다 (기획안 6-1)
func _update_hoses(tick: int) -> void:
	for h: HoseLine in hoses.duplicate():
		# 관창을 놓고 간 수관은 그대로 둔다 (주인이 풀린 수관은 crew_id -1). 다시 잡으러 가는 중·거두는 중은 따로 (2026-11-24)
		if h.dropped and not h.to_nozzle:
			continue
		var c := units.get_crew(h.crew_id)
		if c == null:
			continue
		var leader := c.leader
		if h.to_nozzle or h.recovering:
			_update_detached(h, c, tick)
			continue
		if h.to_outlet:
			# 수관을 시작할 곳(방수구·펌프차 후면)으로 가는 중: 닿으면 연결, 멈췄는데 못 닿았으면 1초마다 다시 길을 찾는다 (입구 대기 뒤 등)
			if _at_outlet(c, h):
				_connect_at_outlet(h, c, tick)
			elif not leader.is_moving() and not leader.incapacitated and tick % roundi(1.0 / SimClock.TICK_DT) == 0:
				units.order_move([c.id] as Array[int], h.points[0], pathfinder)
			continue
		if h.fetch_until >= 0:
			# 펌프차 후면에서 호스를 꺼내는 중: 서 있다. 끝나면 깔면서 간다
			if tick < h.fetch_until:
				continue
			h.fetch_until = -1
			for ff in c.members():
				ff.speed_factor = _drag_factor
		if h.resupply_until >= 0 and tick >= h.resupply_until:
			h.resupply_until = -1
			for ff in c.members():
				ff.speed_factor = _drag_factor
		if h.outlet < 0 and h.resupply_until < 0:
			# 한 사람이 들 수 있는 본 수 × 일하는 조원 수 (분대 3명이면 그만큼 더 들고 간다)
			var people := maxi(1, c.able_workers())
			var load_cells := people * float(_tt.get("carry_lengths_per_person", 2.0)) * float(_tt.get("hose_length_m", 15.0)) / _cell_m
			if load_cells > 0.0 and h.length_cells() > load_cells * h.carried_loads:
				h.carried_loads += 1
				h.resupply_until = tick + roundi(float(_tt.get("resupply_s", 30.0)) / SimClock.TICK_DT)
				for ff in c.members():
					ff.speed_factor = 0.0
				events.add(tick, "hose_resupply", {"crew": _crew_name(c), "crew_id": c.id, "lengths": roundi(h.length_cells() * _cell_m / float(_tt.get("hose_length_m", 15.0)))})
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
		for ff in c.list:
			ff.path.clear()
		if not h.at_limit:
			h.at_limit = true
			events.add(tick, "hose_limit", {"crew": _crew_name(c), "crew_id": c.id})


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
			# 관창수가 목표와 다른 층에 있으면 관창을 열지 않는다 — 물도 줄지 않는다 (2026-11-24: 닿지 않는데 탱크만 비었다)
			if h.flowing and not h.approaching and h.charged and tick >= h.resupply_until \
					and (h.exterior or units.get_crew(h.crew_id).leader.level == h.target.z):
				flowing.append(h)
		if flowing.is_empty():
			continue
		var demand := 0.0
		for h in flowing:
			demand += hose_lpm(h, v) * minutes * float(_flow.get(h.pattern, 1.0))
		var used := minf(demand, v.tank_l)
		v.tank_l -= used
		var fraction := used / demand
		for h in flowing:
			h.flow_fraction = fraction
		if v.tank_l <= v.tank_capacity * LOW_TANK_RATIO and not _low_warned.has(v.id):
			_low_warned[v.id] = true
			events.add(tick, "tank_low", {"vehicle": _name(v), "crew": "%s 운전원" % _name(v), "percent": roundi(v.tank_l / v.tank_capacity * 100.0)})
		elif v.tank_l > v.tank_capacity * 0.5:
			_low_warned.erase(v.id)
		if v.tank_l <= EMPTY_TANK_L and not v.tank_empty_logged:
			v.tank_empty_logged = true
			events.add(tick, "tank_empty", {"vehicle": _name(v)})
		elif v.tank_l > EMPTY_TANK_L * 100.0:
			v.tank_empty_logged = false
	_update_indoor(minutes, tick)


## 경계 관창의 방수 (2026-11-24): 바깥 지상에서 겨눈 창·외벽(위층일 수 있다)에 물이 맞는다.
## 열렸거나 깨진 창이면 물이 안으로 들어가 창 안쪽을 적시고 그 방을 식힌다. 닫힌 창·외벽이면 겉만 적신다 —
## 유리는 깨지 않는다. 겉을 적셔 달궈지는 것을 막는 효과는 ExposureSystem이 spraying 으로 본다
func _spray_exterior(h: HoseLine, leader: Firefighter, dt: float, tick: int) -> void:
	var grid := fire.grid
	var goal := Vector2(h.target.x + 0.5, h.target.y + 0.5)
	h.aim = goal
	h.impact = goal
	if not exterior_reach(leader.pos, leader.level, h.target):
		h.blocked = true
		return
	h.blocked = false
	h.spraying = true
	var o := fire.opening_at(h.target)
	if o == null or not (o.is_open or o.broken):
		return
	var v := units.get_vehicle(h.vehicle_id)
	var liters := hose_lpm(h, v) / 60.0 * dt * h.flow_fraction * float(_flow.get(h.pattern, 1.0))
	var room: Compartment = fire.comps[o.room_a] if o.room_a >= 0 and o.room_a < fire.comps.size() else null
	if room:
		room.cooling_kw += liters / dt * _water_kj * _gas_eff[h.pattern]
		room.water_applied_l += liters
		room.applied_lpm += liters / dt * 60.0
	var cell := Vector2i(h.target.x, h.target.y)
	var cells := _reachable_cells(h.target.z, goal, cell, grid.cells_in_radius(h.target.z, goal, _radius[h.pattern]))
	var total_w := 0.0
	var weights := PackedFloat32Array()
	for i in cells:
		var w := 0.2 + (grid.hrr[i] if grid.state[i] == FuelGrid.State.BURNING else 0.0)
		weights.append(w)
		total_w += w
	for k in cells.size():
		var i := cells[k]
		var was_burning := grid.state[i] == FuelGrid.State.BURNING
		grid.apply_water(i, liters * weights[k] / total_w, _fuel_eff[h.pattern], fire.comps)
		if was_burning:
			h.flame_tick = tick


func _apply_sprays(dt: float, tick: int) -> void:
	var grid := fire.grid
	grid.spray_push.clear()
	for h in hoses:
		# spraying = 이번 틱에 실제로 물이 나갔는가 — 아래 관문을 다 지나야 참 (그림·엄호·경계 판정이 본다)
		h.spraying = false
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
		if h.flow_fraction <= 0.0 or not h.charged or tick < h.resupply_until:
			continue
		if h.exterior:
			_spray_exterior(h, leader, dt, tick)
			continue
		if leader.level != h.target.z:
			h.blocked = true
			continue
		if _sweep(h, leader, dt):
			h.flame_tick = tick
		else:
			_advance(h, units.get_crew(h.crew_id), tick)
			# 더 다가가려고 걷기 시작했으면 이번 틱에는 쏘지 않는다
			if h.approaching:
				continue
		var trace := _trace(leader.level, leader.pos, h.aim, _range[h.pattern], nozzle_height(leader))
		h.impact = trace.impact
		h.blocked = trace.blocked
		h.spraying = true
		var v := units.get_vehicle(h.vehicle_id)
		var lpm := hose_lpm(h, v)
		var liters := lpm / 60.0 * dt * h.flow_fraction * float(_flow.get(h.pattern, 1.0))
		var impact_cell := Vector2i(h.impact.floor())
		var comp := fire.compartment_at(leader.level, impact_cell.x, impact_cell.y)
		if comp:
			comp.cooling_kw += liters / dt * _water_kj * _gas_eff[h.pattern]
			comp.water_applied_l += liters
			comp.applied_lpm += liters / dt * 60.0
			_push_gases(h, leader, comp, dt, tick)
			# 배기구 없는 방에 분무: 수증기가 고온층과 섞여 뜨거운 가스가 바닥까지 내려온다 (화재1 34쪽)
			if h.pattern == HoseLine.Pattern.FOG and comp.t_upper > 200.0 and not _vented(comp):
				comp.layer_depth += (comp.height * 0.9 - comp.layer_depth) * minf(1.0, _fog_mix * dt)
				if not _steam_warned.has(comp.index):
					_steam_warned[comp.index] = true
					events.add(tick, "steam_mix", {"room": comp.display_name(), "crew": _crew_name(units.get_crew(h.crew_id))})
		elif grid.door_rooms.has(grid.index(leader.level, impact_cell.x, impact_cell.y)):
			# 문 칸에 맞은 물은 그 문이 붙은 방에 닿은 것으로 센다. 문 칸은 어느 구획에도 들지 않아 예전에는 방수량이 0으로 잡혔고,
			# 그래서 타는 문은 아무리 쏴도 '방수량 부족'으로 꺼지지 않았다 (2026-11-13 고침: 현관문이 다 탈 때까지 진압조가 입구에 묶였다)
			for r: int in grid.door_rooms[grid.index(leader.level, impact_cell.x, impact_cell.y)]:
				if r >= 0:
					fire.comps[r].applied_lpm += liters / dt * 60.0
					fire.comps[r].water_applied_l += liters
		# 타는 셀에 물이 먼저 가도록 열방출률로 가중.
		# 퍼지는 물은 벽·닫힌 문·안 깨진 창을 넘지 않는다 (2026-11-24 — 전에는 맞은 곳 둘레의 칸을 가림 없이 적셔
		# 분무·엄호 주수가 벽 뒤를 적셨고, 벽·문·창 칸을 겨누면 그 뒤 불에 물이 닿았다)
		var cells := _reachable_cells(leader.level, trace.origin, impact_cell, grid.cells_in_radius(leader.level, h.impact, _radius[h.pattern]))
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
			grid.apply_water(i, share, _fuel_eff[h.pattern], fire.comps)
			if was_burning:
				wasted -= share
				h.flame_tick = tick
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
			if d < best_d and not _trace(leader.level, leader.pos, p, _range[h.pattern], nozzle_height(leader)).blocked:
				best_d = d
				goal = p
				found = true
	if not found and room:
		# 목표 방의 불이 보이지 않으면, 가는 길에 있는(목표보다 가까운) 보이는 불부터 끈다 — 진압하며 전진 (화재1 '연소 중인 곳을
		# 제압하며 화점으로'). 2026-11-24: 퍼지는 물이 벽을 넘지 않게 고치자, 복도에 번진 불 때문에 전진하지 못하고
		# 벽만 쏘고 서 있었다 (전에는 벽 너머로 복도 불을 식혀 나아갔다)
		var reach := leader.pos.distance_to(target)
		var best_d := INF
		for i in grid.burning:
			var c := grid.cell_of(i)
			if c.z != leader.level:
				continue
			var p := Vector2(c.x + 0.5, c.y + 0.5)
			var d := leader.pos.distance_to(p)
			if d > _range[h.pattern] or d >= reach or d >= best_d:
				continue
			if not _trace(leader.level, leader.pos, p, _range[h.pattern], nozzle_height(leader)).blocked:
				best_d = d
				goal = p
				found = true
	h.aim = h.aim.move_toward(goal, SWEEP_CELLS_PER_S * dt)
	return found


## from에서 to 방향으로 물줄기를 보낸다. 벽·닫힌 문·깨지지 않은 창에 막히면 그 앞에서 멈춘다.
## nozzle_h > 0 이면 그 높이 이상의 가구·바깥 차량 차체에도 막힌다 (2026-11-24) — 물은 그 가구·차 겉에 닿는다
## (타는 장롱이면 거기에 물이 간다). 관창보다 낮은 가구(침대·탁자)는 넘어간다. 0 이면 가구·차량은 보지 않는다 (퍼지는 물).
## origin = 물이 퍼지기 시작하는 곳: 표면(벽·문·창·가구)에 맞았으면 그 바로 앞(쏘는 쪽)의 점, 아니면 맞은 곳 —
## 퍼지는 물이 그 표면 뒤로 넘어가지 않게 하는 데 쓴다 (_reachable_cells)
func _trace(level: int, from: Vector2, to: Vector2, max_cells: float, nozzle_h := 0.0) -> Dictionary:
	var dir := to - from
	var dist := minf(dir.length(), max_cells)
	if dist < 0.01:
		return {"impact": from, "blocked": false, "origin": from}
	dir = dir.normalized()
	var last := from
	var goal_cell := Vector2i(to.floor())
	var start_cell := Vector2i(from.floor())
	var t := 0.25
	while t <= dist:
		var p := from + dir * t
		var c := Vector2i(p.floor())
		if not _water_passes(level, c):
			# 겨눈 곳이 바로 그 벽·문·창이면 표면에는 물이 닿는다 (그 뒤로는 가지 않는다)
			if c == goal_cell:
				return {"impact": p, "blocked": false, "origin": last}
			return {"impact": last, "blocked": true, "origin": last}
		if nozzle_h > 0.0 and c != start_cell and _stops_stream(level, c, p, nozzle_h):
			# 키 큰 가구·차체: 물은 그 겉(이 칸)에 닿는다. 겨눈 곳이 그것이면 막힌 것이 아니다
			return {"impact": p, "blocked": c != goal_cell, "origin": last}
		last = p
		t += 0.25
	var end := from + dir * dist
	return {"impact": end, "blocked": false, "origin": end}


## 이 칸(점 p)에서 관창 높이 nozzle_h 의 물줄기가 멈추는가: 그 높이 이상의 가구, 또는 바깥에 선 차량 차체
func _stops_stream(level: int, c: Vector2i, p: Vector2, nozzle_h: float) -> bool:
	if float(_furn_h.get(Vector3i(c.x, c.y, level), 0.0)) >= nozzle_h:
		return true
	if _vehicles_block and building.cell(level, c.x, c.y) in BuildingData.OUTDOOR:
		for v in units.vehicles:
			if v.level == level and not v.away and v.height_m >= nozzle_h and Geometry2D.is_point_in_polygon(p, v.footprint()):
				return true
	return false


## 관창 높이 (m): 낮은 자세면 낮다
func nozzle_height(ff: Firefighter) -> float:
	return _nozzle_low_h if ff != null and ff.crouched else _nozzle_h


## 맞은 곳 둘레의 칸들(cells — 연료 격자 번호) 가운데 물이 실제로 닿는 칸: origin(물이 퍼지기 시작하는 곳)에서 곧게 닿는 칸과
## 물이 직접 맞은 칸(impact_cell — 타는 문이면 그 문). 벽·닫힌 문·안 깨진 창 뒤의 칸은 뺀다
func _reachable_cells(level: int, origin: Vector2, impact_cell: Vector2i, cells: PackedInt32Array) -> PackedInt32Array:
	var grid := fire.grid
	var out := PackedInt32Array()
	var origin_cell := Vector2i(origin.floor())
	for i in cells:
		var c := grid.cell_of(i)
		var cell := Vector2i(c.x, c.y)
		if cell == impact_cell or cell == origin_cell:
			out.append(i)
			continue
		if not _trace(level, origin, Vector2(cell.x + 0.5, cell.y + 0.5), INF).blocked:
			out.append(i)
	return out


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
	return units.crew_name(c)


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


## 엄호 주수 안에 있는가: 같은 층에서 엄호 관창(방수 중)과 cover_protect_m 안 (SOP 203-2.1, R11)
func is_covered(level: int, pos: Vector2) -> bool:
	for h in hoses:
		if h.pattern != HoseLine.Pattern.COVER or not h.flowing or h.approaching or h.flow_fraction <= 0.0:
			continue
		var leader := units.get_crew(h.crew_id).leader
		if leader.level == level and leader.pos.distance_to(pos) <= _cover_cells:
			return true
	return false
