class_name FireSim
extends RefCounted
## 화재 시뮬레이션 통합. 도면에서 구획·개구부를 만들고, 매 틱 연료 격자와 구획 모델을 진행한 뒤
## 유리창 파손·플래시오버·단계 변화 같은 사건을 판정해 기록한다.

## 플래시오버 단계로 표시하는 시간 (초)
const FLASHOVER_DISPLAY_S := 10.0
## 이 가시거리 아래로 떨어지면 '연기 유입'으로 기록 (m)
const SMOKE_EVENT_VISIBILITY_M := 5.0

var building: BuildingData
var config: FireConfig
var events: SimEventLog
var comps: Array[Compartment] = []
var openings: Array[Opening] = []
var grid: FuelGrid
var model: CompartmentModel
## 층 -> PackedInt32Array (셀 -> 구획 index, 없으면 -1)
var room_map: Dictionary = {}

var _scheduled: Array[Dictionary] = []
var _incipient_kw: float
var _window_break: float
var _fo_ramp_skip: float
var _visibility_coeff: float


func _init(p_building: BuildingData, p_config: FireConfig, rng: RandomNumberGenerator, p_events: SimEventLog) -> void:
	building = p_building
	config = p_config
	events = p_events
	_incipient_kw = config.value("incipient_max_kw")
	_window_break = config.value("window_break_temp_c")
	_fo_ramp_skip = config.value("flashover_ramp_fraction")
	_visibility_coeff = config.value("visibility_coeff_m2_kg")
	_build_compartments()
	_build_openings()
	var fo := config.range_of("flashover_temp_c")
	# 인접 건물 구획은 따로 뽑는다: 인접 건물이 있어도 화재 건물·요구조자의 시드 결과가 같다
	var ex_rng := RandomNumberGenerator.new()
	ex_rng.seed = hash(rng.seed + 7919)
	for c in comps:
		c.flashover_temp = (ex_rng if is_exposure_comp(c) else rng).randf_range(fo.x, fo.y)
	grid = FuelGrid.build(building, config, comps, openings, room_map)
	model = CompartmentModel.new(comps, openings, config)


## 굴뚝효과 (기획안 5-3-2): 계절과 건물 층수로 계단·승강로 상승 기류 배율을 정한다
func apply_season(season: String) -> void:
	var entry: Dictionary = config.params.get("stack_effect_per_10_floors", {})
	var per10 := float(entry.get("by_season", {}).get(season, 0.0)) if season != "" else 0.0
	var floors := 0
	for lv in building.levels():
		if building.floor_number(lv) >= 1:
			floors += 1
	model.stack_factor = maxf(0.3, 1.0 + per10 * floors / 10.0)


## 시나리오의 fire 항목: 발화 일정, 문 열림/닫힘
func apply_scenario(fire_data: Dictionary) -> void:
	for ign: Dictionary in fire_data.get("ignitions", []):
		var cell: Array = ign.get("cell", [0, 0])
		schedule_ignition(Vector3i(int(cell[0]), int(cell[1]), int(ign.get("level", 1))), float(ign.get("time_s", 0.0)))
	for entry: Array in fire_data.get("doors_closed", []):
		_set_door_by_cell(entry, false)
	for entry: Array in fire_data.get("doors_open", []):
		_set_door_by_cell(entry, true)
	for entry: Array in fire_data.get("doors_locked", []):
		_set_door_by_cell(entry, false)
		var o := opening_at(Vector3i(int(entry[0]), int(entry[1]), int(entry[2]) if entry.size() > 2 else 1))
		if o and o.kind == Opening.Kind.DOOR:
			o.locked = true


func schedule_ignition(cell: Vector3i, time_s: float) -> void:
	_scheduled.append({"cell": cell, "tick": roundi(time_s / SimClock.TICK_DT)})


## 해당 셀에 불을 붙인다. 가연물이 없으면 false.
func ignite(cell: Vector3i, tick := 0) -> bool:
	if not building.has_level(cell.z) or not building.in_bounds(cell.x, cell.y):
		return false
	var i := grid.index(cell.z, cell.x, cell.y)
	if not grid.ignite(i):
		return false
	var c := compartment_at(cell.z, cell.x, cell.y)
	events.add(tick, "ignition", {
		"room": c.display_name() if c else "",
		"cell": [cell.x, cell.y, cell.z],
		"material": grid.material_name(i),
	})
	return true


func step(dt: float, tick: int) -> void:
	for s in _scheduled.duplicate():
		if s.tick <= tick:
			ignite(s.cell, tick)
			_scheduled.erase(s)
	grid.step(dt, comps, model)
	_start_fire_fronts()
	model.step(dt)
	_check_windows(tick)
	_check_doors_burnt(tick)
	_check_flashover(tick)
	_update_stages(tick)
	_check_smoke(tick)


## 불이 붙어 연기를 내기 시작한 방: 타는 칸 가운데(불 위)에서 연기 선두가 출발한다 (기획안 5-3-1)
func _start_fire_fronts() -> void:
	var need := false
	for c in comps:
		if c.q_potential > 0.0 and not c.smoke_started() and c.layer_depth < 0.005:
			need = true
			break
	if not need:
		return
	var sums := {}
	for i in grid.burning:
		var c3 := grid.cell_of(i)
		var comp := compartment_at(c3.z, c3.x, c3.y)
		if comp:
			var acc: Array = sums.get(comp.index, [Vector2.ZERO, 0])
			sums[comp.index] = [acc[0] + Vector2(c3.x, c3.y) + Vector2(0.5, 0.5), int(acc[1]) + 1]
	for c in comps:
		if c.q_potential > 0.0 and not c.smoke_started() and c.layer_depth < 0.005:
			var acc: Array = sums.get(c.index, [Vector2(c.rect.get_center()), 1])
			c.start_smoke_front(acc[0] / float(acc[1]))


func compartment_at(level: int, x: int, y: int) -> Compartment:
	if not room_map.has(level) or not building.in_bounds(x, y):
		return null
	var ci: int = room_map[level][y * building.width + x]
	return comps[ci] if ci >= 0 else null


## 인접 건물(연소 확대 대상)의 구획인가
func is_exposure_comp(c: Compartment) -> bool:
	return c != null and building.is_exposure(c.rect.position.x, c.rect.position.y)


func opening_at(cell: Vector3i) -> Opening:
	for o in openings:
		if o.level == cell.z and Vector2i(cell.x, cell.y) in o.cells:
			return o
	return null


func set_opening_open(o: Opening, open: bool, tick := 0) -> void:
	if o.is_open == open:
		return
	o.is_open = open
	events.add(tick, "door_opened" if open else "door_closed", {"opening": o.index, "kind": o.kind_name()})


func visibility_m(c: Compartment) -> float:
	return c.visibility_m(_visibility_coeff)


func _set_door_by_cell(entry: Array, open: bool) -> void:
	var o := opening_at(Vector3i(int(entry[0]), int(entry[1]), int(entry[2]) if entry.size() > 2 else 1))
	if o and o.kind == Opening.Kind.DOOR:
		o.is_open = open


func _build_compartments() -> void:
	var cs := building.cell_size_m
	var ceiling := config.value("ceiling_height_m")
	for level in building.levels():
		var map := PackedInt32Array()
		map.resize(building.width * building.height)
		map.fill(-1)
		for room in building.rooms(level):
			var c := Compartment.new()
			c.index = comps.size()
			c.id = room.id
			c.name = room.name
			c.level = level
			c.rect = room.rect
			c.height = ceiling
			for y in range(c.rect.position.y, c.rect.end.y):
				for x in range(c.rect.position.x, c.rect.end.x):
					var t := building.cell(level, x, y)
					if t == BuildingData.Cell.FLOOR or t == BuildingData.Cell.STAIRS:
						c.cells.append(Vector2i(x, y))
						map[y * building.width + x] = c.index
			c.area = c.cells.size() * cs * cs
			c.cell_m = cs
			c.volume = c.area * c.height
			c.surface = 2.0 * c.area + 2.0 * (c.rect.size.x + c.rect.size.y) * cs * c.height
			comps.append(c)
		room_map[level] = map


func _build_openings() -> void:
	var cs := building.cell_size_m
	for level in building.levels():
		for kind in [BuildingData.Cell.DOOR, BuildingData.Cell.WINDOW]:
			for group in _cell_groups(level, kind):
				var sides := _group_sides(level, group)
				var rooms: Array = sides.rooms
				var o := Opening.new()
				o.level = level
				o.cells.assign(group)
				if rooms.size() == 2:
					o.room_a = rooms[0]
					o.room_b = rooms[1]
				elif rooms.size() == 1 and sides.outside:
					o.room_a = rooms[0]
				else:
					continue
				if kind == BuildingData.Cell.DOOR:
					o.kind = Opening.Kind.DOOR
					o.width = maxf(group.size() * cs, config.value("min_door_width_m"))
					o.sill = 0.0
					o.top = config.value("door_height_m")
					o.is_open = o.room_b != Opening.OUTSIDE  # 외부 출입문은 처음에 닫힘
				else:
					o.kind = Opening.Kind.WINDOW
					o.width = group.size() * cs
					o.sill = config.value("window_sill_m")
					o.top = config.value("window_top_m")
					o.is_open = false
				_add_opening(o)
		# 계단: 아래층 계단실 ↔ 위층 계단실
		if building.has_level(level + 1):
			var pairs := {}
			for link in building.stair_links(level):
				var lower := compartment_at(level, link.x, link.y)
				var upper := compartment_at(level + 1, link.x, link.y)
				if lower and upper:
					var key := Vector2i(lower.index, upper.index)
					if not pairs.has(key):
						pairs[key] = []
					pairs[key].append(link)
			for key: Vector2i in pairs:
				var o := Opening.new()
				o.kind = Opening.Kind.STAIR
				o.level = level
				o.cells.assign(pairs[key])
				o.room_a = key.x
				o.room_b = key.y
				o.area = o.cells.size() * cs * cs
				o.is_open = true
				_add_opening(o)


func _add_opening(o: Opening) -> void:
	o.index = openings.size()
	openings.append(o)
	comps[o.room_a].openings.append(o.index)
	if o.room_b != Opening.OUTSIDE:
		comps[o.room_b].openings.append(o.index)


## 같은 종류의 셀이 상하좌우로 이어진 묶음 (예: 2칸짜리 현관문)
func _cell_groups(level: int, kind: int) -> Array[Array]:
	var groups: Array[Array] = []
	var seen := {}
	for y in building.height:
		for x in building.width:
			var start := Vector2i(x, y)
			if seen.has(start) or building.cell(level, x, y) != kind:
				continue
			var group: Array[Vector2i] = []
			var queue: Array[Vector2i] = [start]
			seen[start] = true
			while not queue.is_empty():
				var c: Vector2i = queue.pop_front()
				group.append(c)
				for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
					var n := c + d
					if not seen.has(n) and building.cell(level, n.x, n.y) == kind:
						seen[n] = true
						queue.append(n)
			groups.append(group)
	return groups


## 개구부 묶음의 양쪽: 맞닿은 구획들과 외부 여부
func _group_sides(level: int, group: Array) -> Dictionary:
	var rooms: Array[int] = []
	var outside := false
	for cell: Vector2i in group:
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var n: Vector2i = cell + d
			if n in group:
				continue
			var t := building.cell(level, n.x, n.y)
			if t == BuildingData.Cell.FLOOR or t == BuildingData.Cell.STAIRS:
				var c := compartment_at(level, n.x, n.y)
				if c and not c.index in rooms:
					rooms.append(c.index)
			elif t in BuildingData.OUTDOOR:
				outside = true
	rooms.sort()
	return {"rooms": rooms, "outside": outside}


func _check_windows(tick: int) -> void:
	for o in openings:
		if o.kind != Opening.Kind.WINDOW or o.broken or not o.breakable:
			continue
		var c := comps[o.room_a]
		if c.t_upper >= _window_break and c.height - c.layer_depth < o.top:
			o.broken = true
			o.is_open = true
			events.add(tick, "window_broken", {"room": c.display_name(), "opening": o.index})


## 닫힌 나무 문이 다 타면 뚫린 것으로 본다 → 그 너머로 연기·불이 넘어간다 (방화문은 타지 않아 해당 없음)
func _check_doors_burnt(tick: int) -> void:
	for o in openings:
		if o.kind != Opening.Kind.DOOR or o.is_open or o.broken or o.cells.is_empty():
			continue
		var all_burnt := true
		for cell in o.cells:
			if grid.state[grid.index(o.level, cell.x, cell.y)] != FuelGrid.State.BURNT:
				all_burnt = false
				break
		if all_burnt:
			o.broken = true
			o.is_open = true
			events.add(tick, "door_burnt_through", {"opening": o.index, "level": o.level})


func _check_flashover(tick: int) -> void:
	for c in comps:
		if c.flashed or c.t_upper < c.flashover_temp:
			continue
		c.flashed = true
		c.flashover_tick = tick
		grid.ignite_room(c.index, _fo_ramp_skip)
		events.add(tick, "flashover", {"room": c.display_name(), "temp_c": snappedf(c.t_upper, 1.0)})


func _update_stages(tick: int) -> void:
	for c in comps:
		var burning := c.q_potential > 0.5
		if burning:
			c.ever_burned = true
		var s := c.stage
		if not burning:
			if not c.ever_burned:
				s = Compartment.Stage.NONE
			elif c.water_applied_l > 0.0 and c.fuel_fraction() > 0.3:
				s = Compartment.Stage.EXTINGUISHED
			else:
				s = Compartment.Stage.BURNT_OUT
		elif c.flashed:
			if (tick - c.flashover_tick) * SimClock.TICK_DT < FLASHOVER_DISPLAY_S:
				s = Compartment.Stage.FLASHOVER
			elif c.fuel_fraction() < 0.3 or c.q < 0.4 * c.q_max:
				s = Compartment.Stage.DECAY
			else:
				s = Compartment.Stage.FULLY_DEVELOPED
		elif c.stage == Compartment.Stage.GROWTH or c.stage == Compartment.Stage.DECAY:
			var fading := c.q < 0.5 * c.q_max and c.fuel_fraction() < 0.5
			s = Compartment.Stage.DECAY if fading else Compartment.Stage.GROWTH
		else:
			s = Compartment.Stage.GROWTH if c.q_potential >= _incipient_kw else Compartment.Stage.INCIPIENT
		if s != c.stage:
			events.add(tick, "stage", {"room": c.display_name(), "from": c.stage_name(), "to": Compartment.STAGE_NAMES[s]})
			c.stage = s


func _check_smoke(tick: int) -> void:
	for c in comps:
		if not c.smoke_logged and visibility_m(c) < SMOKE_EVENT_VISIBILITY_M:
			c.smoke_logged = true
			events.add(tick, "smoke", {"room": c.display_name()})
