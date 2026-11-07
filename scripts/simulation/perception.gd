class_name Perception
extends RefCounted
## 지휘관이 아는 것 (정보 안개).
## 건물 밖은 늘 보인다. 건물 안은 대원이 지금 보고 있거나, 밖에서 창·열린 문으로 보이는 곳만 보인다.
## 한 번 본 곳은 마지막으로 확인한 상태(화염·그을음·연기층)를 기억한다.
##
## 시선 계산: 관찰자에서 사방으로 시선을 쏘고, 지나가는 칸마다 그 칸의 가시거리만큼 "흐림"을 쌓는다.
## - 흐림 1까지: 형체가 보인다 (그 칸을 본 것으로 기록)
## - 흐림 flame_glow_factor까지: 화염 불빛만 보인다 (타는 칸만 기록)
## - 벽·닫힌 문은 시선을 막고, 창은 투명하다 (열화상은 유리를 통과하지 못한다)
## 가시거리는 그을음 농도로 구하며, 눈높이가 연기층 안이면 상부층, 아래면 하부층(더 맑음) 값을 쓴다.
## 랜턴은 짙은 연기 속에서 거의 도움이 되지 않는다 (flashlight_bonus_m만큼만 늘어남).
## 열화상카메라를 가진 조의 조장은 연기와 상관없이 thermal_camera_range_m 안을 본다.

const RAYS := 40
const STEP_CELLS := 0.5
## 대원 바로 옆(손이 닿는 범위)은 연기와 상관없이 안다 (셀)
const TOUCH_CELLS := 1
## 창·열린 문으로 밖에서 들여다볼 때 시선 수와 최대 거리 (셀)
const WINDOW_RAYS := 20
const WINDOW_RANGE_CELLS := 12.0
## 바깥 대원은 건물에서 이 거리(셀) 안에 있을 때만 시선을 계산한다 (바깥은 늘 보이므로)
const OUTDOOR_CAST_MARGIN := 3
const OUTDOOR_VISIBILITY_M := 30.0
const FILL_MIN_NEIGHBORS := 6

var enabled := true
var fire: FireSim
var units: UnitSystem
var building: BuildingData

## 칸별 (fire.grid.index 기준)
var visible_now: PackedByteArray
## 대원이 직접 본 칸 (창 밖에서 들여다본 것은 제외). 요구조자 발견에 쓴다
var crew_visible_now: PackedByteArray
var thermal_now: PackedByteArray
var seen_tick: PackedInt32Array
var seen_burning: PackedByteArray
var seen_burnt: PackedByteArray
## 구획별
var room_visible_now: PackedByteArray
var room_seen: PackedByteArray
var room_seen_depth: PackedFloat32Array
var room_seen_visibility: PackedFloat32Array

var _eye_stand: float
var _eye_crouch: float
var _flashlight: float
var _lower_factor: float
var _glow: float
var _max_sight: float
var _tic_range: float
var _extinction: float
var _cell_m: float
var _w: int
var _per_level: int
## 층별 미리 계산한 표 (fire.grid.index 기준)
var _type: PackedByteArray
var _room: PackedInt32Array
var _opening: PackedInt32Array  # 문·창 칸 -> 개구부 index, 아니면 -1
var _outdoor_vis_cells: float
## 구획별 가시거리 (셀): 눈높이가 연기층 안 / 아래
var _vis_upper: PackedFloat32Array
var _vis_lower: PackedFloat32Array
var _cast_area: Dictionary = {}  # level -> Rect2i (바깥 대원이 시선을 계산하는 범위)
var _exterior: Array[Opening] = []


func _init(p_fire: FireSim, p_units: UnitSystem, stats: ParamTable) -> void:
	fire = p_fire
	units = p_units
	building = fire.building
	_cell_m = building.cell_size_m
	_eye_stand = stats.value("eye_height_standing_m")
	_eye_crouch = stats.value("eye_height_crouched_m")
	_flashlight = stats.value("flashlight_bonus_m")
	_lower_factor = stats.value("lower_layer_visibility_factor")
	_glow = stats.value("flame_glow_factor")
	_max_sight = stats.value("max_sight_m") / _cell_m
	_tic_range = stats.value("thermal_camera_range_m") / _cell_m
	_extinction = fire.config.value("visibility_coeff_m2_kg")
	_outdoor_vis_cells = OUTDOOR_VISIBILITY_M / _cell_m
	_w = building.width
	_per_level = building.width * building.height
	var total := _per_level * building.levels().size()
	visible_now.resize(total)
	crew_visible_now.resize(total)
	thermal_now.resize(total)
	seen_tick.resize(total)
	seen_tick.fill(-1)
	seen_burning.resize(total)
	seen_burnt.resize(total)
	_type.resize(total)
	_room.resize(total)
	_opening.resize(total)
	_opening.fill(-1)
	for level in building.levels():
		var map: PackedInt32Array = fire.room_map[level]
		for y in building.height:
			for x in building.width:
				var i := fire.grid.index(level, x, y)
				_type[i] = building.cell(level, x, y)
				_room[i] = map[y * _w + x]
		var fp := building.footprint(level)
		_cast_area[level] = fp.grow(OUTDOOR_CAST_MARGIN)
	for o in fire.openings:
		if o.kind != Opening.Kind.STAIR:
			for c in o.cells:
				_opening[fire.grid.index(o.level, c.x, c.y)] = o.index
		if o.room_b == Opening.OUTSIDE and o.kind != Opening.Kind.STAIR:
			_exterior.append(o)
	var n := fire.comps.size()
	room_visible_now.resize(n)
	room_seen.resize(n)
	room_seen_depth.resize(n)
	room_seen_visibility.resize(n)
	_vis_upper.resize(n)
	_vis_lower.resize(n)


## 지금 보이는 칸인지 (정보 안개가 꺼져 있거나 건물 밖이면 항상 true)
func is_visible(level: int, x: int, y: int) -> bool:
	if not enabled or building.cell(level, x, y) in BuildingData.OUTDOOR:
		return true
	return visible_now[fire.grid.index(level, x, y)] == 1


func is_seen(level: int, x: int, y: int) -> bool:
	if not enabled or building.cell(level, x, y) in BuildingData.OUTDOOR:
		return true
	return seen_tick[fire.grid.index(level, x, y)] >= 0


## 대원이 직접(눈·손) 확인하고 있는 칸인지
func is_crew_visible(level: int, x: int, y: int) -> bool:
	if not enabled:
		return true
	return crew_visible_now[fire.grid.index(level, x, y)] == 1


func is_thermal_visible(level: int, x: int, y: int) -> bool:
	if not enabled:
		return true
	return thermal_now[fire.grid.index(level, x, y)] == 1


func room_visible(c: Compartment) -> bool:
	return not enabled or room_visible_now[c.index] == 1


func update(tick: int) -> void:
	visible_now.fill(0)
	thermal_now.fill(0)
	room_visible_now.fill(0)
	_update_room_visibility()
	for c in units.crews:
		for ff in c.members():
			if ff.incapacitated or not _should_cast(ff):
				continue
			var eye := _eye_crouch if ff.crouched else _eye_stand
			_touch(ff.level, ff.pos)
			_cast(ff.level, ff.pos, eye, RAYS, _max_sight, false)
		if c.thermal_camera and not c.leader.incapacitated and _should_cast(c.leader):
			_cast(c.leader.level, c.leader.pos, _eye_stand, RAYS, _tic_range, true)
	crew_visible_now = visible_now.duplicate()
	# 밖에서 창·열린 문으로 들여다보기 (지휘관·바깥 대원). 화염·연기는 보이지만 바닥에 쓰러진 사람은 보이지 않는다
	for o in _exterior:
		if o.kind == Opening.Kind.DOOR and not o.is_open:
			continue
		var center := Vector2.ZERO
		for cell in o.cells:
			center += Vector2(cell) + Vector2(0.5, 0.5)
		_cast(o.level, center / o.cells.size(), _eye_stand, WINDOW_RAYS, WINDOW_RANGE_CELLS, false)
	_fill_gaps()
	_record(tick)


## 시선 사이로 빠진 칸 메우기: 실내에서 안 보이는 칸인데 주변 8칸 중 FILL_MIN_NEIGHBORS 칸 이상 보이면 보이는 것으로 한다
func _fill_gaps() -> void:
	var fill := PackedInt32Array()
	var h := building.height
	for li in building.levels().size():
		var base := li * _per_level
		for y in range(1, h - 1):
			for x in range(1, _w - 1):
				var i := base + y * _w + x
				if visible_now[i] == 1 or (_room[i] < 0 and _type[i] != BuildingData.Cell.DOOR):
					continue
				# 벽·창 이웃은 보이는 것으로 센다 (벽에 붙은 칸도 메워지도록)
				var n := 0
				var seen_any := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var j := i + dy * _w + dx
						if visible_now[j] == 1:
							n += 1
							seen_any = true
						elif _type[j] == BuildingData.Cell.WALL or _type[j] == BuildingData.Cell.WINDOW:
							n += 1
				if seen_any and n >= FILL_MIN_NEIGHBORS:
					fill.append(i)
	for i in fill:
		visible_now[i] = 1


## 바깥 대원은 건물 근처에 있을 때만 계산한다 (바깥은 늘 보이고, 창 안쪽은 창 관찰로 처리)
func _should_cast(ff: Firefighter) -> bool:
	var i := fire.grid.index(ff.level, floori(ff.pos.x), floori(ff.pos.y))
	if _room[i] >= 0 or _type[i] == BuildingData.Cell.DOOR:
		return true
	return (_cast_area[ff.level] as Rect2i).has_point(Vector2i(ff.pos.floor()))


func _update_room_visibility() -> void:
	for c in fire.comps:
		var layer_vol := maxf(c.layer_volume(), 0.05 * c.volume)
		var conc := c.soot / layer_vol
		var vis := 30.0 if conc <= 1e-9 else minf(30.0, 3.0 / (_extinction * conc))
		_vis_upper[c.index] = maxf(0.05, (vis + _flashlight) / _cell_m)
		_vis_lower[c.index] = maxf(0.05, (minf(30.0, vis * _lower_factor) + _flashlight) / _cell_m)


func _record(tick: int) -> void:
	var grid := fire.grid
	for i in visible_now.size():
		if visible_now[i] == 0:
			continue
		seen_tick[i] = tick
		var s := grid.state[i]
		seen_burning[i] = 1 if s == FuelGrid.State.BURNING else 0
		seen_burnt[i] = 1 if s == FuelGrid.State.BURNT else 0
		var r := _room[i]
		if r >= 0:
			room_visible_now[r] = 1
	for c in fire.comps:
		if room_visible_now[c.index] == 1:
			room_seen[c.index] = 1
			room_seen_depth[c.index] = c.layer_depth
			room_seen_visibility[c.index] = fire.visibility_m(c)


func _touch(level: int, pos: Vector2) -> void:
	var c := Vector2i(pos.floor())
	for y in range(c.y - TOUCH_CELLS, c.y + TOUCH_CELLS + 1):
		for x in range(c.x - TOUCH_CELLS, c.x + TOUCH_CELLS + 1):
			if building.in_bounds(x, y):
				var i := fire.grid.index(level, x, y)
				if _type[i] != BuildingData.Cell.WALL:
					visible_now[i] = 1


## 사방으로 시선을 쏜다. thermal이면 연기를 무시하고 거리로만 제한한다.
func _cast(level: int, origin: Vector2, eye: float, rays: int, max_cells: float, thermal: bool) -> void:
	var state := fire.grid.state
	var openings := fire.openings
	var base := fire.grid.index(level, 0, 0)
	var h := building.height
	for k in rays:
		var ang := TAU * k / rays
		var dx := cos(ang) * STEP_CELLS
		var dy := sin(ang) * STEP_CELLS
		var px := origin.x
		var py := origin.y
		var haze := 0.0
		var last := -1
		var steps := int(max_cells / STEP_CELLS)
		for s in steps:
			px += dx
			py += dy
			var cx := floori(px)
			var cy := floori(py)
			if cx < 0 or cy < 0 or cx >= _w or cy >= h:
				break
			var i := base + cy * _w + cx
			var type := _type[i]
			if type == BuildingData.Cell.WALL or type == BuildingData.Cell.VOID:
				break
			if not thermal:
				var r := _room[i]
				var vis := _outdoor_vis_cells
				if r >= 0:
					var c := fire.comps[r]
					vis = _vis_upper[r] if eye >= c.height - c.layer_depth else _vis_lower[r]
				elif type == BuildingData.Cell.DOOR or type == BuildingData.Cell.WINDOW:
					vis = 2.0
				haze += STEP_CELLS / vis
			if i == last:
				if haze > _glow:
					break
				continue
			last = i
			if thermal:
				thermal_now[i] = 1
				if state[i] == FuelGrid.State.BURNING:
					visible_now[i] = 1
			elif haze <= 1.0:
				visible_now[i] = 1
			elif haze <= _glow:
				if state[i] == FuelGrid.State.BURNING:
					visible_now[i] = 1
			else:
				break
			# 닫힌 문은 시선을 막는다. 깨지지 않은 유리창은 눈에는 투명하지만 열화상(원적외선)은 통과하지 못한다
			var oi := _opening[i]
			if oi >= 0 and not openings[oi].is_open:
				if type == BuildingData.Cell.DOOR or thermal:
					break
