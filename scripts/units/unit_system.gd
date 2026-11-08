class_name UnitSystem
extends RefCounted
## 현장의 모든 출동대·조·대원을 관리하고 이동 명령을 처리한다.
## 각 객체는 id를 배열 인덱스로 쓴다.

var squads: Array[Squad] = []
var crews: Array[Crew] = []
var firefighters: Array[Firefighter] = []
var vehicles: Array[Vehicle] = []
## 보행 속도 (셀/초)
var walk_speed_cells := 2.4


## vehicle_stats: data/units/vehicles.json (차종 -> 제원)
var vehicle_stats: Dictionary = {}
var cell_size_m := 0.5


static func from_roster(roster: Dictionary, speed_cells: float, p_vehicle_stats: Dictionary = {}, p_cell_size_m := 0.5) -> UnitSystem:
	var units := UnitSystem.new()
	units.walk_speed_cells = speed_cells
	units.vehicle_stats = p_vehicle_stats
	units.cell_size_m = p_cell_size_m
	for squad_data: Dictionary in roster.get("squads", []):
		units.add_squad(squad_data)
	return units


## 출동대를 추가한다 (편성 형식은 data/units/test_roster.json).
## with_crews가 false면 조는 나중에 add_crew로 내린다 (차량을 타고 도착하는 후착대).
func add_squad(squad_data: Dictionary, with_crews := true) -> Squad:
	var squad := Squad.new()
	squad.id = squads.size()
	squad.key = str(squad_data.get("id", ""))
	squad.name = str(squad_data.get("name", ""))
	squad.type = str(squad_data.get("type", ""))
	squad.color = Color.html(str(squad_data.get("color", "#FFFFFF")))
	squads.append(squad)
	if with_crews:
		for crew_data: Dictionary in squad_data.get("crews", []):
			var spawn: Array = crew_data.get("spawn", [0, 0])
			add_crew(squad, crew_data, Vector2i(int(spawn[0]), int(spawn[1])), int(crew_data.get("level", 1)))
	for v_data: Dictionary in squad_data.get("vehicles", []):
		var type := str(v_data.get("type", ""))
		if not vehicle_stats.has(type):
			push_error("차량 제원에 '%s'가 없습니다." % type)
			continue
		var v := _make_vehicle(vehicles.size(), squad.id, type, vehicle_stats[type], v_data, cell_size_m)
		vehicles.append(v)
	return squad


## 조를 추가한다. 조장은 spawn 셀, 짝은 오른쪽 옆 셀에 선다.
func add_crew(squad: Squad, crew_data: Dictionary, spawn: Vector2i, level := 1) -> Crew:
	var crew := Crew.new()
	crew.id = crews.size()
	crew.squad_id = squad.id
	crew.number = squad.crews.size() + 1
	crew.thermal_camera = bool(crew_data.get("thermal_camera", false))
	var members: Array = crew_data.get("members", [])
	for i in members.size():
		var ff := Firefighter.new()
		ff.id = firefighters.size()
		ff.name = str(members[i].get("name", ""))
		ff.rank = str(members[i].get("rank", ""))
		ff.role = str(members[i].get("role", ""))
		ff.squad_id = squad.id
		ff.crew_id = crew.id
		ff.pos = Vector2(spawn.x + i + 0.5, spawn.y + 0.5)
		ff.prev_pos = ff.pos
		ff.level = level
		ff.prev_level = level
		firefighters.append(ff)
		if i == 0:
			crew.leader = ff
		else:
			crew.partner = ff
	squad.crews.append(crew)
	crews.append(crew)
	return crew


func vehicles_of_squad(squad_id: int) -> Array[Vehicle]:
	var out: Array[Vehicle] = []
	for v in vehicles:
		if v.squad_id == squad_id:
			out.append(v)
	return out


func squad_by_key(key: String) -> Squad:
	for s in squads:
		if s.key == key:
			return s
	return null


static func _make_vehicle(id: int, squad_id: int, type: String, stats: Dictionary, v_data: Dictionary, cell_size_m: float) -> Vehicle:
	var v := Vehicle.new()
	v.id = id
	v.squad_id = squad_id
	v.type = type
	v.short_name = str(stats.get("short", type))
	v.color = Color.html(str(stats.get("color", "#888888")))
	var spawn: Array = v_data.get("spawn", [0, 0])
	v.pos = Vector2(int(spawn[0]) + 0.5, int(spawn[1]) + 0.5)
	v.prev_pos = v.pos
	v.goal = v.pos
	var heading: Array = v_data.get("heading", [1, 0])
	v.heading = Vector2(float(heading[0]), float(heading[1])).normalized()
	v.length_cells = float(stats.length_m) / cell_size_m
	v.width_cells = float(stats.width_m) / cell_size_m
	v.height_m = float(stats.height_m)
	v.speed_cells = float(stats.speed_mps) / cell_size_m
	v.tank_capacity = float(stats.tank_l)
	v.tank_l = v.tank_capacity
	v.nozzle_lpm = float(stats.nozzle_lpm)
	v.transfer_lpm = float(stats.transfer_lpm)
	v.hose_max_cells = float(stats.hose_sections) * float(stats.hose_section_m) / cell_size_m
	var d: Dictionary = v_data.get("driver", {})
	v.driver_name = str(d.get("name", ""))
	v.driver_rank = str(d.get("rank", ""))
	return v


func get_vehicle(id: int) -> Vehicle:
	return vehicles[id] if id >= 0 and id < vehicles.size() else null


func get_crew(id: int) -> Crew:
	return crews[id] if id >= 0 and id < crews.size() else null


func squad_of_crew(crew_id: int) -> Squad:
	var c := get_crew(crew_id)
	return squads[c.squad_id] if c else null


func step(dt: float) -> void:
	for ff in firefighters:
		ff.step(dt, walk_speed_cells)
	for v in vehicles:
		v.step(dt)


## 여러 조를 target 주변으로 이동시킨다. 목표에 가까운 조부터 가까운 도착 지점을 배정한다.
func order_move(crew_ids: Array[int], target: Vector3i, pathfinder: Pathfinder) -> void:
	var targets: Array[Crew] = []
	for crew_id in crew_ids:
		var c := get_crew(crew_id)
		if c:
			targets.append(c)
	if targets.is_empty():
		return
	var goal2 := Vector2(target.x + 0.5, target.y + 0.5)
	var dist := func(c: Crew) -> float:
		return c.leader.pos.distance_squared_to(goal2) + absi(c.leader.level - target.z) * 10000.0
	targets.sort_custom(func(a: Crew, b: Crew) -> bool:
		var da: float = dist.call(a)
		var db: float = dist.call(b)
		return da < db or (da == db and a.id < b.id))
	var slots := pathfinder.formation_slots(target.z, Vector2i(target.x, target.y), targets.size())
	if slots.is_empty():
		return
	for i in targets.size():
		var slot := slots[i % slots.size()]
		_route_crew(targets[i], Vector3i(slot.x, slot.y, target.z), pathfinder)


## 조장은 goal까지, 짝은 조장 경로를 따라 한 칸 뒤까지 이동한다.
func _route_crew(c: Crew, goal: Vector3i, pathfinder: Pathfinder) -> void:
	var lead_path := pathfinder.find_path(c.leader.cell3(), goal)
	if lead_path.is_empty():
		return
	c.leader.set_path(lead_path)
	if c.partner == null or lead_path.size() < 2:
		return
	var trail := pathfinder.find_path(c.partner.cell3(), lead_path[0])
	if trail.is_empty():
		trail = pathfinder.find_path(c.partner.cell3(), lead_path[-2])
	else:
		trail.append_array(lead_path.slice(1, lead_path.size() - 1))
	if not trail.is_empty():
		c.partner.set_path(trail)
