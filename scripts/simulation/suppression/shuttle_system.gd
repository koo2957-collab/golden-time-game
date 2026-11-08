class_name ShuttleSystem
extends RefCounted
## 물탱크차 순환보수 (SOP 200-3.1.1.3: 수원 확보가 어려우면 현장지휘관이 물탱크차의 순환보수 전술을 지시한다).
## 시나리오 water: {hydrants_out: [고장 소화전 index], shuttle: {name, round_trip_s, fill_lpm}}.
##   순환보수로 지정한 물탱크차는 펌프차에 급수하다가 탱크가 low_ratio 아래로 떨어지면 원거리 수원으로 떠나고,
##   왕복 시간 + 급수 시간 뒤 가득 채워 돌아와 같은 펌프차에 다시 급수한다. 떠나 있는 동안은 화면·선택에서 빠진다.

const LOW_RATIO := 0.1

var units: UnitSystem
var water: WaterSystem
var events: SimEventLog
var source_name := ""
var round_trip_s := 0.0
var fill_lpm := 1500.0
## 차량 id -> {pump, home: Vector2, heading: Vector2, away_until: tick(-1이면 현장), trips}
var tankers: Dictionary = {}


func _init(p_units: UnitSystem, p_water: WaterSystem, p_events: SimEventLog) -> void:
	units = p_units
	water = p_water
	events = p_events


func apply_scenario(data: Dictionary) -> void:
	var w: Dictionary = data.get("water", {})
	for i in w.get("hydrants_out", []):
		water.hydrants_out.append(int(i))
	var s: Dictionary = w.get("shuttle", {})
	if not s.is_empty():
		source_name = str(s.get("name", "원거리 수원"))
		round_trip_s = float(s.get("round_trip_s", 360.0))
		fill_lpm = float(s.get("fill_lpm", 1500.0))


func available() -> bool:
	return round_trip_s > 0.0


## 순환보수 지정·해제 (물탱크차만). 급수 중인 펌프차가 없으면 가장 가까운 펌프차를 맡는다
func toggle(vehicle_id: int, tick: int) -> bool:
	var v := units.get_vehicle(vehicle_id)
	if v == null or v.transfer_lpm <= 0.0 or not available():
		return false
	if tankers.has(vehicle_id):
		if int(tankers[vehicle_id].away_until) >= 0:
			return false  # 다녀오는 중에는 해제하지 않는다
		tankers.erase(vehicle_id)
		events.add(tick, "shuttle_off", {"vehicle": _name(v), "driver": v.driver_label()})
		return true
	var pump := v.supply_to
	if pump < 0:
		var best := INF
		for p in units.vehicles:
			if p.is_pump() and not p.away and p.pos.distance_to(v.pos) < best:
				best = p.pos.distance_to(v.pos)
				pump = p.id
	if pump < 0:
		return false
	tankers[vehicle_id] = {"pump": pump, "home": v.pos, "heading": v.heading, "away_until": -1, "trips": 0}
	if v.supply_to < 0:
		water.connect_supply(vehicle_id, pump, tick)
	events.add(tick, "shuttle_on", {"vehicle": _name(v), "driver": v.driver_label(), "source": source_name})
	return true


func trips() -> int:
	var n := 0
	for id: int in tankers:
		n += int(tankers[id].trips)
	return n


func step(_dt: float, tick: int) -> void:
	for id: int in tankers.keys():
		var v := units.get_vehicle(id)
		var t: Dictionary = tankers[id]
		if int(t.away_until) < 0:
			if v.supply_to >= 0 and v.tank_l <= v.tank_capacity * LOW_RATIO:
				_depart(v, t, tick)
		elif tick >= int(t.away_until):
			_return(v, t, tick)


func _depart(v: Vehicle, t: Dictionary, tick: int) -> void:
	v.supply_to = -1
	v.away = true
	v.moving = false
	var fill_s := (v.tank_capacity - v.tank_l) / fill_lpm * 60.0
	t.away_until = tick + roundi((round_trip_s + fill_s) / SimClock.TICK_DT)
	events.add(tick, "shuttle_depart", {"vehicle": _name(v), "driver": v.driver_label(), "source": source_name,
		"eta_s": roundi(round_trip_s + fill_s)})


func _return(v: Vehicle, t: Dictionary, tick: int) -> void:
	v.away = false
	v.tank_l = v.tank_capacity
	v.tank_empty_logged = false
	v.heading = t.heading
	# 비운 사이 자리가 막혔으면 가까운 데까지만 (자리는 그대로 비워 두는 것이 원칙)
	if water.vehicle_can_be_at(v, t.home):
		v.pos = t.home
	v.prev_pos = v.pos
	v.goal = v.pos
	t.away_until = -1
	t.trips = int(t.trips) + 1
	events.add(tick, "shuttle_return", {"vehicle": _name(v), "driver": v.driver_label()})
	water.connect_supply(v.id, int(t.pump), tick)


func _name(v: Vehicle) -> String:
	return v.display_name(units.squads[v.squad_id].name)
