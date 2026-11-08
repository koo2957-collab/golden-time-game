class_name LifelineSystem
extends RefCounted
## 라이트라인·방향감각 상실 (SOP 217 지하층, 기획안 4장 3-2·R14): 시계가 거의 없는 곳(가시거리 dark_vis_m 미만)에서
## 라이트라인(유도 로프·조명선) 가까이 있지 않은 조는 disorient_s가 지나면 방향감각을 잃고 멈춘다(대원 안전 무전).
## 라이트라인에 닿거나 다른 조가 가까이 오면 다시 움직인다. 시나리오 lifeline: true일 때만 (지하층 스테이지).

var enabled := false
var fire: FireSim
var units: UnitSystem
var pathfinder: Pathfinder
var events: SimEventLog
## 라이트라인 칸 {Vector3i: true}
var cells: Dictionary = {}
## 방향감각을 잃은 조 {조 id: tick}
var disoriented: Dictionary = {}
var _dark_s: Dictionary = {}
var _dark_vis_m := 1.0
var _disorient_s := 90.0


func _init(p_fire: FireSim, p_units: UnitSystem, p_pathfinder: Pathfinder, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	pathfinder = p_pathfinder
	events = p_events
	_dark_vis_m = params.value("lifeline_dark_vis_m")
	_disorient_s = params.value("lifeline_disorient_s")


## 라이트라인 설치 (EquipmentCommand "lifeline"): 조가 지금 있는 곳에서 목표 칸까지의 길을 따라 깐다
func lay(crew_id: int, target: Vector3i, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	if c == null:
		return false
	var path := pathfinder.find_path(c.leader.cell3(), target)
	if path.is_empty():
		return false
	for p in path:
		cells[p] = true
	events.add(tick, "lifeline_laid", {"crew": _crew_name(c), "length_m": roundi(path.size() * fire.building.cell_size_m)})
	units.order_move([crew_id] as Array[int], target, pathfinder)
	return true


func near_line(level: int, pos: Vector2) -> bool:
	var c := Vector2i(pos.floor())
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if cells.has(Vector3i(c.x + dx, c.y + dy, level)):
				return true
	return false


func step(dt: float, tick: int) -> void:
	if not enabled:
		return
	for c in units.crews:
		var ff := c.leader
		if ff.incapacitated or ff.aboard:
			continue
		var room := fire.compartment_at(ff.level, floori(ff.pos.x), floori(ff.pos.y))
		var dark := room != null and fire.visibility_m(room) < _dark_vis_m
		if disoriented.has(c.id):
			if near_line(ff.level, ff.pos) or _helper_near(c):
				disoriented.erase(c.id)
				_dark_s.erase(c.id)
				events.add(tick, "crew_reoriented", {"crew": _crew_name(c)})
			elif ff.is_moving():
				units.order_move([c.id] as Array[int], ff.cell3(), pathfinder)
			continue
		if dark and not near_line(ff.level, ff.pos):
			_dark_s[c.id] = float(_dark_s.get(c.id, 0.0)) + dt
			if float(_dark_s[c.id]) >= _disorient_s:
				disoriented[c.id] = tick
				units.order_move([c.id] as Array[int], ff.cell3(), pathfinder)
				events.add(tick, "crew_disoriented", {"crew": _crew_name(c), "crew_id": c.id, "room": room.display_name()})
		else:
			_dark_s.erase(c.id)


func _helper_near(c: Crew) -> bool:
	for o in units.crews:
		if o.id == c.id or disoriented.has(o.id) or o.leader.incapacitated or o.leader.level != c.leader.level:
			continue
		if o.leader.pos.distance_to(c.leader.pos) <= 2.0:
			return true
	return false


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]
