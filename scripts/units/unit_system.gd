class_name UnitSystem
extends RefCounted
## 현장의 모든 출동대·조·대원을 관리하고 이동 명령을 처리한다.
## 각 객체는 id를 배열 인덱스로 쓴다.

const TRAITS_PATH := "res://data/units/traits.json"
static var _traits: Dictionary = {}

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
## 대원 개성 표 (한 번 읽어 둔다)
static func traits() -> Dictionary:
	if _traits.is_empty():
		var data: Variant = JsonData.load_file(TRAITS_PATH)
		_traits = data.get("traits", {}) if data is Dictionary else {}
	return _traits


## 출동대 종류별 기본 휴대 장비 (data/units/equipment.json default_items)
var default_items: Dictionary = {}


## 조 id -> 조 (합쳐서 비어 있는 조도 들어 있다 — crews 에는 활동 중인 조만)
var _crew_by_id: Dictionary = {}


func add_crew(squad: Squad, crew_data: Dictionary, spawn: Vector2i, level := 1) -> Crew:
	var crew := Crew.new()
	crew.id = _crew_by_id.size()
	_crew_by_id[crew.id] = crew
	crew.squad_id = squad.id
	crew.number = squad.crews.size() + 1
	crew.thermal_camera = bool(crew_data.get("thermal_camera", false))
	for k in default_items.get(squad.type, []):
		crew.items.append(str(k))
	for k in crew_data.get("items", []):
		if not str(k) in crew.items:
			crew.items.append(str(k))
	var members: Array = crew_data.get("members", [])
	for i in members.size():
		var ff := Firefighter.new()
		ff.id = firefighters.size()
		ff.name = str(members[i].get("name", ""))
		ff.rank = str(members[i].get("rank", ""))
		ff.role = str(members[i].get("role", ""))
		ff.officer = bool(members[i].get("officer", false))
		for t in members[i].get("traits", []):
			var spec: Dictionary = traits().get(str(t), {})
			if spec.is_empty():
				push_error("대원 개성 '%s'가 traits.json에 없습니다." % t)
				continue
			ff.traits.append(str(t))
			ff.air_factor *= float(spec.get("air", 1.0))
			ff.trait_speed *= float(spec.get("speed", 1.0))
			ff.heat_factor *= float(spec.get("heat", 1.0))
		ff.squad_id = squad.id
		ff.crew_id = crew.id
		ff.pos = Vector2(spawn.x + i + 0.5, spawn.y + 0.5)
		ff.prev_pos = ff.pos
		ff.level = level
		ff.prev_level = level
		firefighters.append(ff)
		crew.list.append(ff)
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
	v.nozzle_65_lpm = float(stats.get("nozzle_65_lpm", stats.nozzle_lpm))
	v.transfer_lpm = float(stats.transfer_lpm)
	v.hose_max_cells = float(stats.hose_sections) * float(stats.hose_section_m) / cell_size_m
	v.reach_m = float(stats.get("reach_m", 0.0))
	v.outreach_m = float(stats.get("outreach_m", 0.0))
	v.deploy_s = float(stats.get("deploy_s", 0.0))
	v.basket_mps = float(stats.get("basket_mps", 0.5))
	v.basket_load_s = float(stats.get("basket_load_s", 30.0))
	v.feed_m = float(stats.get("feed_m", 40.0))
	var d: Dictionary = v_data.get("driver", {})
	v.driver_name = str(d.get("name", ""))
	v.driver_rank = str(d.get("rank", ""))
	return v


func get_vehicle(id: int) -> Vehicle:
	return vehicles[id] if id >= 0 and id < vehicles.size() else null


func get_crew(id: int) -> Crew:
	return _crew_by_id.get(id)


## 활동 중인 조인가 (합쳐져 비어 있는 조가 아니다)
func crew_active(id: int) -> bool:
	var c := get_crew(id)
	return c != null and not c.list.is_empty()


# --- 분대 편성 (2026-11-16 결정 — docs/decisions.md '분대': 팀장 둥근 버튼) ---

## 분대(조 하나, 4명)를 2인 1조 둘로 나눈다: 첫째·둘째 조원은 그대로 남고(임무·호스를 이어 간다),
## 셋째·넷째가 새 조가 된다 — 팀장이 있으면 팀장이 선두. 진압 분대 = [관창수 + 보조1] / [팀장 + 보조2].
## → 떨어져 나온 조 (나눌 수 없으면 null)
func split_squad(squad: Squad) -> Crew:
	if squad.crews.size() != 1 or squad.crews[0].list.size() != 4:
		return null
	var a := squad.crews[0]
	var b: Crew = squad.spare
	if b == null:
		b = Crew.new()
		b.id = _crew_by_id.size()
		_crew_by_id[b.id] = b
		b.squad_id = squad.id
		b.number = 2 if a.number == 1 else 1
	if squad.home.is_empty():
		for ff in a.list:
			squad.home.append(ff.id)
	squad.spare = null
	b.merged_into = null
	var moved: Array[Firefighter] = [a.list[2], a.list[3]]
	if moved[1].officer and not moved[0].officer:
		moved.reverse()
	var kept: Array[Firefighter] = [a.list[0], a.list[1]]
	a.list = kept
	b.list = moved
	b.thermal_camera = false
	b.items.clear()
	for k in default_items.get(squad.type, []):
		b.items.append(str(k))
	for ff in moved:
		ff.crew_id = b.id
		ff.path.clear()
	squad.crews.append(b)
	squad.crews.sort_custom(func(x: Crew, y: Crew) -> bool: return x.number < y.number)
	crews.append(b)
	return b


## 나뉜 두 조를 다시 한 분대로: keeper가 남고 다른 조의 조원이 들어온다 (그 조는 비워 둔다).
## home_order면 처음 편성 순서로 되돌린다 (둘 다 쉬는 채로 합칠 때) — 아니면 keeper의 조원 뒤에 붙는다 (임무 중인 조에 합류)
func merge_squad(squad: Squad, keeper: Crew, home_order: bool) -> bool:
	if squad.crews.size() != 2 or not keeper in squad.crews:
		return false
	var joiner := squad.crews[0] if squad.crews[1] == keeper else squad.crews[1]
	var all: Array[Firefighter] = keeper.list.duplicate()
	all.append_array(joiner.list)
	if home_order and not squad.home.is_empty():
		all.sort_custom(func(x: Firefighter, y: Firefighter) -> bool: return squad.home.find(x.id) < squad.home.find(y.id))
	for ff in joiner.list:
		ff.crew_id = keeper.id
	for item in joiner.items:
		if not item in keeper.items:
			keeper.items.append(item)
	keeper.thermal_camera = keeper.thermal_camera or joiner.thermal_camera
	keeper.list = all
	var none: Array[Firefighter] = []
	joiner.list = none
	joiner.merged_into = keeper
	squad.crews.erase(joiner)
	crews.erase(joiner)
	squad.spare = joiner
	return true


## 흩어진 조원을 선두 곁으로 모은다 (합친 직후). 선두는 움직이지 않는다
func gather(c: Crew, pathfinder: Pathfinder) -> void:
	var lead := c.leader
	if lead == null:
		return
	var slots := pathfinder.formation_slots(lead.level, Vector2i(lead.pos.floor()), c.list.size(), 1)
	for k in range(1, c.list.size()):
		var ff: Firefighter = c.list[k]
		if ff.incapacitated or (ff.level == lead.level and ff.pos.distance_to(lead.pos) <= 2.0):
			continue
		var cell: Vector2i = slots[mini(k, slots.size() - 1)] if not slots.is_empty() else Vector2i(lead.pos.floor())
		var path := pathfinder.find_path(ff.cell3(), Vector3i(cell.x, cell.y, lead.level))
		if not path.is_empty():
			ff.set_path(path)


func squad_of_crew(crew_id: int) -> Squad:
	var c := get_crew(crew_id)
	return squads[c.squad_id] if c else null


## 분대가 조 하나로 같이 움직이는가 (나누지 않은 분대)
func whole_squad(c: Crew) -> bool:
	return squads[c.squad_id].crews.size() == 1


## 조 이름 — 무전·기록·화면이 모두 이것을 쓴다: 나누지 않은 분대는 "진압2", 나뉜 조는 "진압1 1조"
func crew_name(c: Crew) -> String:
	if whole_squad(c):
		return squads[c.squad_id].name
	return "%s %s" % [squads[c.squad_id].name, crew_short(c)]


## 출동대 이름 없이: "1조" (나누지 않은 분대는 "분대")
func crew_short(c: Crew) -> String:
	return "분대" if whole_squad(c) else "%d조" % c.number


## 대원 이름: "진압1 1조 이준호"
func ff_name(ff: Firefighter) -> String:
	return "%s %s" % [crew_name(get_crew(ff.crew_id)), ff.name]


func step(dt: float) -> void:
	for ff in firefighters:
		ff.step(dt, walk_speed_cells)
	for v in vehicles:
		v.step(dt)


## 여러 조를 target 주변으로 이동시킨다. 목표에 가까운 조부터 가까운 도착 지점을 배정한다.
## via: 지나갈 칸 (고른 계단 등). x < 0이면 가장 짧은 길
## outdoor: 건물 밖으로만 (고른 진입구로 둘러 가기)
func order_move(crew_ids: Array[int], target: Vector3i, pathfinder: Pathfinder, via := Vector3i(-1, -1, -1), outdoor := false) -> void:
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
		_route_crew(targets[i], Vector3i(slot.x, slot.y, target.z), pathfinder, via, outdoor)


## 두 사람만 따로 보낸다 (분대 안의 2인 1조 — 구조대 두 짝 검색): lead는 goal까지, mate는 그 경로를 따라 한 칸 뒤까지.
## 길이 없으면 false
func route_pair(lead: Firefighter, mate: Firefighter, goal: Vector3i, pathfinder: Pathfinder) -> bool:
	var path := pathfinder.find_path(lead.cell3(), goal)
	if path.is_empty():
		return false
	lead.set_path(path)
	if mate == null or path.size() < 2:
		return true
	var trail := pathfinder.find_path(mate.cell3(), path[0])
	if trail.is_empty():
		trail = pathfinder.find_path(mate.cell3(), path[-2])
	else:
		trail.append_array(path.slice(1, path.size() - 1))
	if not trail.is_empty():
		mate.set_path(trail)
	return true


## 조장은 goal까지(via가 있으면 그 칸을 거쳐), 짝은 조장 경로를 따라 한 칸 뒤까지 이동한다.
func _route_crew(c: Crew, goal: Vector3i, pathfinder: Pathfinder, via := Vector3i(-1, -1, -1), outdoor := false) -> void:
	var lead_path := pathfinder.find_path_outdoors(c.leader.cell3(), goal) if outdoor else pathfinder.find_path(c.leader.cell3(), goal)
	if via.x >= 0 and via != c.leader.cell3():
		var first := pathfinder.find_path(c.leader.cell3(), via)
		var second := pathfinder.find_path(via, goal)
		if not first.is_empty() and not second.is_empty():
			first.append_array(second.slice(1))
			lead_path = first
	if lead_path.is_empty():
		return
	c.leader.set_path(lead_path)
	# 뒤따르는 조원: k번째는 선두 경로의 끝에서 k칸 앞까지 (줄지어 선다). 경로가 그보다 짧으면 제자리
	for k in range(1, c.list.size()):
		var ff: Firefighter = c.list[k]
		var end := lead_path.size() - 1 - k
		if end < 0:
			break
		var trail := pathfinder.find_path_outdoors(ff.cell3(), lead_path[0]) if outdoor else pathfinder.find_path(ff.cell3(), lead_path[0])
		if trail.is_empty():
			trail = pathfinder.find_path(ff.cell3(), lead_path[end])
		else:
			trail.append_array(lead_path.slice(1, end + 1))
		if not trail.is_empty():
			ff.set_path(trail)
