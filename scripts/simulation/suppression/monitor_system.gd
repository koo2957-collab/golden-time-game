class_name MonitorSystem
extends RefCounted
## 방수포 (기획안 P6·R11, SOP 207-1.1): 펌프차에 달린 대용량 방수포로 밖에서 창·개구부 안을 친다.
##   - 출동대의 펌프차 운전원이 조작한다. 차량에서 사거리(monitor_range_m) 안의 바깥 창·문을 겨눈다. 유리는 물줄기에 깨진다
##   - 펌프차 물탱크에서 monitor_lpm으로 물을 쓴다 (급수가 없으면 금방 바닥난다)
##   - 진입대원이 있는 화재실에 방수포를 쓰면 안 된다 (207-1.1): 그 방에 대원이 있으면 대원 안전 무전·위반 기록
##   - 굴절차(P9)도 쓴다: 전개(AerialSystem) 뒤에 물이 나오고, 닿는 높이·거리는 굴절차 제원, 물은 가까운 펌프차 탱크에서
##   - 진입대원이 있는 방이면 바로 쏘지 않고 확인을 묻는다 (질문 카드 MONITOR-CREW-01). 그래도 쏘면 열기가 진입대 쪽으로 밀린다
## 수치는 data/fire/fire_params.json (monitor_*)

class Stream:
	extends RefCounted
	var vehicle_id := -1
	var opening := -1
	var room := -1
	var crew_warned := false
	## 굴절차: 전개가 끝나 물이 나오기 시작하는 틱
	var ready_tick := 0
	var feed_warned := false


var fire: FireSim
var units: UnitSystem
var events: SimEventLog
var streams: Array[Stream] = []
## 진입대원이 있는 방에 방수포를 쏜 횟수 (SOP 207-1.1 위반)
var violations := 0

var _lpm: float
var _range_cells: float
var _radius_cells: float
var _fuel_eff: float
var _gas_eff: float
var _water_kj: float
var _crew_heat := 0.35
## 굴절차 전개·도달 판정 (SimWorld가 넣는다)
var aerial: AerialSystem


func _init(p_fire: FireSim, p_units: UnitSystem, config: FireConfig, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	events = p_events
	var cell_m := fire.building.cell_size_m
	_lpm = config.value("monitor_lpm")
	_range_cells = config.value("monitor_range_m") / cell_m
	_radius_cells = config.value("monitor_radius_m") / cell_m
	_fuel_eff = config.value("straight_fuel_eff")
	_gas_eff = config.value("straight_gas_eff")
	_water_kj = config.value("water_cooling_kj_per_l")
	_crew_heat = config.value("monitor_crew_heat")


func stream_of(vehicle_id: int) -> Stream:
	for s in streams:
		if s.vehicle_id == vehicle_id:
			return s
	return null


## 방수포 시작: 펌프차·굴절차 + 바깥 창·문 칸. 실패하면 이유를 기록하고 false.
## 진입대원이 있는 방이면 confirmed가 아닌 한 쏘지 않고 확인 질문(monitor_crew_check)을 띄운다 (SOP 207-1.1)
func start(vehicle_id: int, target: Vector3i, tick: int, confirmed := false) -> bool:
	var v := units.get_vehicle(vehicle_id)
	if v == null or not (v.is_pump() or v.is_aerial()) or v.away:
		return false
	var o := fire.opening_at(target)
	if o == null or o.kind == Opening.Kind.STAIR or o.room_b != Opening.OUTSIDE:
		events.add(tick, "monitor_no_target", {"vehicle": _name(v)})
		return false
	var center := Vector2(o.cells[0]) + Vector2(0.5, 0.5)
	if v.is_aerial():
		var why := aerial.reach_reason(v, o.level, o.cells[0]) if aerial else "굴절차 없음"
		if why != "":
			events.add(tick, "aerial_out_of_reach", {"vehicle": _name(v), "who": "방수포", "reason": why})
			return false
	else:
		# 높이도 거리에 넣는다 (층마다 약 3m)
		var h_cells := (o.level - 1) * 3.0 / fire.building.cell_size_m
		if Vector2(v.pos.distance_to(center), h_cells).length() > _range_cells:
			events.add(tick, "monitor_too_far", {"vehicle": _name(v)})
			return false
	if not confirmed and _crew_inside(o.room_a):
		events.add(tick, "monitor_crew_check", {"vehicle": _name(v), "vehicle_id": vehicle_id, "room": fire.comps[o.room_a].display_name(),
			"target": [target.x, target.y, target.z], "aerial": v.is_aerial()})
		return false
	var ready := tick
	if v.is_aerial():
		ready = aerial.deploy(v, tick) if aerial else -1
		if ready < 0:
			return false
	stop(vehicle_id, tick, false)
	var s := Stream.new()
	s.vehicle_id = vehicle_id
	s.opening = o.index
	s.room = o.room_a
	s.ready_tick = ready
	streams.append(s)
	if o.kind == Opening.Kind.WINDOW and not o.broken:
		o.broken = true
		o.is_open = true
		events.add(tick, "window_broken", {"room": fire.comps[o.room_a].display_name()})
	events.add(tick, "monitor_start", {"vehicle": _name(v), "room": fire.comps[o.room_a].display_name()})
	return true


func stop(vehicle_id: int, tick: int, report := true) -> void:
	var s := stream_of(vehicle_id)
	if s == null:
		return
	streams.erase(s)
	if report:
		events.add(tick, "monitor_stop", {"vehicle": _name(units.get_vehicle(vehicle_id))})


func step(dt: float, tick: int) -> void:
	var grid := fire.grid
	for s in streams.duplicate():
		var v := units.get_vehicle(s.vehicle_id)
		if v == null or v.away or v.is_moving():
			streams.erase(s)
			continue
		if tick < s.ready_tick:
			continue
		# 굴절차는 가까운 펌프차 탱크에서 물을 받는다
		var src := v
		if v.is_aerial():
			src = aerial.feed_pump(v) if aerial else null
			if src == null:
				if not s.feed_warned:
					s.feed_warned = true
					events.add(tick, "aerial_no_feed", {"vehicle": _name(v)})
				continue
		var liters := minf(_lpm / 60.0 * dt, src.tank_l)
		src.tank_l -= liters
		if liters <= 0.0:
			continue
		var o: Opening = fire.openings[s.opening]
		var room: Compartment = fire.comps[s.room]
		room.cooling_kw += liters / dt * _water_kj * _gas_eff
		room.water_applied_l += liters
		room.applied_lpm += liters / dt * 60.0
		# 창 안쪽으로 물줄기가 들어가 타는 칸을 친다 (방 안 반경)
		var at := Vector2(o.cells[0]) + Vector2(0.5, 0.5)
		var cells := grid.cells_in_radius(o.level, at, _radius_cells)
		var burning: Array[int] = []
		for i in cells:
			if grid.state[i] == FuelGrid.State.BURNING:
				burning.append(i)
		var targets: Array = burning if not burning.is_empty() else Array(cells)
		var wasted := liters
		for i: int in targets:
			grid.apply_water(i, liters / targets.size(), _fuel_eff, fire.comps)
			if grid.state[i] == FuelGrid.State.BURNING:
				wasted -= liters / targets.size()
		room.water_damage_l += maxf(0.0, wasted)
		# 진입대원이 있는 방이면 위반 (SOP 207-1.1)
		if not s.crew_warned and _crew_inside(s.room):
			s.crew_warned = true
			violations += 1
			events.add(tick, "monitor_crew_inside", {"vehicle": _name(v), "room": room.display_name(), "crew": v.driver_label()})
			# 열기·수증기가 진입대 쪽으로 밀린다 (화상 위험): 그 방 대원의 열 스트레스가 오르고 연기층이 내려온다
			room.layer_depth += (room.height * 0.9 - room.layer_depth) * 0.5
			for ff in units.firefighters:
				if ff.incapacitated or ff.aboard:
					continue
				var fc := fire.compartment_at(ff.level, floori(ff.pos.x), floori(ff.pos.y))
				if fc and fc.index == s.room:
					ff.heat_stress += _crew_heat * ff.heat_factor


func _crew_inside(room: int) -> bool:
	for ff in units.firefighters:
		if ff.incapacitated or ff.aboard:
			continue
		var c := fire.compartment_at(ff.level, floori(ff.pos.x), floori(ff.pos.y))
		if c and c.index == room:
			return true
	return false


func _name(v: Vehicle) -> String:
	return "%s %s" % [units.squads[v.squad_id].name, v.short_name] if v else "방수포"
