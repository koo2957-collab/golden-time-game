class_name ShaftSystem
extends RefCounted
## 배관 샤프트를 통한 수직 연소 확대 (SOP 212-2.3). 건물 shafts: 층마다 같은 자리의 샤프트 구획.
##   아래층 샤프트 옆 구획이 최성기·플래시오버면 그 층 샤프트에 불·연기가 들어가고(shaft_heat),
##   shaft_rise_s 뒤 위층 샤프트로 오르며(shaft_smoke), 다시 shaft_spread_s 뒤 위층 샤프트 옆 구획에 불이 붙는다(shaft_ignition).
##   어느 층이든 대원이 그 층 샤프트 안에 들어가 확인하거나 방수가 샤프트에 닿으면 그 층에서 멈춘다(shaft_checked).

var fire: FireSim
var units: UnitSystem
var water: WaterSystem
var events: SimEventLog
## 층 -> 샤프트 구획
var shaft_rooms: Dictionary = {}
## 층 -> 그 층 샤프트에 불·연기가 든 tick
var hot: Dictionary = {}
## 층 -> 확인(차단)한 tick
var checked: Dictionary = {}
## 층 -> 위층 구획에 불이 옮겨 붙은 tick
var ignited: Dictionary = {}

var _rise_ticks: int
var _spread_ticks: int


func _init(p_fire: FireSim, p_units: UnitSystem, p_water: WaterSystem, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	water = p_water
	events = p_events
	_rise_ticks = roundi(params.value("shaft_rise_s") / SimClock.TICK_DT)
	_spread_ticks = roundi(params.value("shaft_spread_s") / SimClock.TICK_DT)
	for sh in fire.building.shafts:
		var r: Rect2i = sh.rect
		for lv: int in sh.levels:
			var c := fire.compartment_at(lv, r.position.x, r.position.y)
			if c:
				shaft_rooms[lv] = c


func has_shaft() -> bool:
	return not shaft_rooms.is_empty()


func step(_dt: float, tick: int) -> void:
	if shaft_rooms.is_empty():
		return
	var levels: Array = shaft_rooms.keys()
	levels.sort()
	for lv: int in levels:
		var sh: Compartment = shaft_rooms[lv]
		if not checked.has(lv) and _being_checked(sh):
			checked[lv] = tick
			events.add(tick, "shaft_checked", {"floor": fire.building.floor_name(lv), "crew": "현장 대원"})
		if checked.has(lv):
			continue
		if not hot.has(lv):
			var below_hot: bool = hot.has(lv - 1) and not checked.has(lv - 1) and tick - int(hot[lv - 1]) >= _rise_ticks
			if _neighbor_burning(sh) or below_hot:
				hot[lv] = tick
				events.add(tick, "shaft_heat" if not below_hot else "shaft_smoke", {"floor": fire.building.floor_name(lv), "crew": "현장 대원"})
			continue
		# 아래층에서 올라온 불이 위층 샤프트 옆 구획으로
		if hot.has(lv - 1) and not ignited.has(lv) and tick - int(hot[lv]) >= _spread_ticks:
			ignited[lv] = tick
			var room := _ignite_next_to(sh)
			events.add(tick, "shaft_ignition", {"room": room.display_name() if room else fire.building.floor_name(lv), "crew": "현장 대원"})


## 샤프트 옆(벽 너머) 구획 중 최성기·플래시오버인 것이 있는가
func _neighbor_burning(sh: Compartment) -> bool:
	for c in _neighbors(sh):
		if c.flashed or c.stage == Compartment.Stage.FULLY_DEVELOPED:
			return true
	return false


func _neighbors(sh: Compartment) -> Array[Compartment]:
	var out: Array[Compartment] = []
	var r := sh.rect.grow(2)
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			var c := fire.compartment_at(sh.level, x, y)
			if c and c != sh and not c in out and fire.building.cell(sh.level, x, y) == BuildingData.Cell.FLOOR:
				out.append(c)
	return out


## 대원이 샤프트 안에 있거나, 흐르는 방수가 샤프트에 닿는가
func _being_checked(sh: Compartment) -> bool:
	for ff in units.firefighters:
		if not ff.incapacitated and not ff.aboard and fire.compartment_at(ff.level, floori(ff.pos.x), floori(ff.pos.y)) == sh:
			return true
	for h in water.hoses:
		if h.flowing and fire.compartment_at(h.target.z, h.target.x, h.target.y) == sh:
			return true
	return false


## 샤프트 옆 구획 중 가연물이 있는 가장 큰 방의 샤프트 쪽 칸에 불을 붙인다
func _ignite_next_to(sh: Compartment) -> Compartment:
	var best_room: Compartment = null
	var best := -1
	var best_d := INF
	var center := Vector2(sh.rect.get_center())
	for c in _neighbors(sh):
		if c.name == "복도":
			continue
		for cell in c.cells:
			var i := fire.grid.index(c.level, cell.x, cell.y)
			if fire.grid.state[i] != FuelGrid.State.UNBURNED:
				continue
			var d := center.distance_to(Vector2(cell))
			if d < best_d:
				best_d = d
				best = i
				best_room = c
	if best >= 0:
		fire.grid.ignite(best, 0.5)
	return best_room
