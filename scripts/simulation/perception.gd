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
## 밖에서 창을 들여다볼 수 있는 거리 (칸). 그 창이 향한 쪽에 지휘관이나 바깥 대원이 있어야 한다 (R8 — 보이는 면만)
const WINDOW_VIEW_CELLS := 40.0
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
## 이번 갱신에 그 구획 안을 '유리 너머가 아니라' 직접 본 사람: 조 id, 지휘관이면 COMMANDER_SEER, 아무도 없으면 -1 (2026-11-25).
## 롤오버처럼 천장을 직접 봐야 아는 징후에 쓴다 — 닫힌 유리창 너머로는 화염 불빛·연기만 보인다
var room_clear_by: PackedInt32Array
const COMMANDER_SEER := -2
var room_seen: PackedByteArray
var room_seen_depth: PackedFloat32Array
var room_seen_visibility: PackedFloat32Array
## 마지막으로 봤을 때 연기 선두가 간 거리 (m, 다 덮였으면 큰 값)
var room_seen_reach: PackedFloat32Array

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
var _normal: Dictionary = {}  # 개구부 index -> 바깥쪽 방향
## 이번 update에서 시선을 쏜 층 (그 층만 메우기·기록 — 성능, P14)
var _cast_levels: Dictionary = {}
## 밖에서 창으로 들여다보기는 window_view_every번에 한 번만 다시 계산하고, 그 사이에는 지난번에 보인 칸을 그대로 쓴다 (성능, P14)
var _window_every := 1
## 땅에서 이 층수 위의 창은 창 바로 안쪽(window_view_high_range_m)만 보인다 — 높은 층 방 안은 밖에서 들여다볼 수 없다
var _window_low_floors := 2
var _window_high_range := 4.0
var _window_count := 0
var _window_cells := PackedInt32Array()
## 창 들여다보기로 직접 본 구획 {구획 index: 본 사람} — 창 계산을 건너뛰는 갱신에서도 그대로 쓴다
var _window_clear: Dictionary = {}
## 이번 갱신에 보인 칸 / 열화상으로 본 칸 / 대원이 직접 본 칸 목록 (그 칸만 지우고 기록 — 성능, P14)
var _vis_list := PackedInt32Array()
var _thermal_list := PackedInt32Array()
var _crew_list := PackedInt32Array()
## 현장지휘관 (밖에서 창을 들여다보는 사람). SimWorld가 넣는다
var commander: Firefighter


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
	_window_every = maxi(1, roundi(stats.value("window_view_every")))
	_window_low_floors = roundi(stats.value("window_view_low_floors"))
	_window_high_range = stats.value("window_view_high_range_m") / _cell_m
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
			_normal[o.index] = _outward(o)
	var n := fire.comps.size()
	room_visible_now.resize(n)
	room_clear_by.resize(n)
	room_clear_by.fill(-1)
	room_seen.resize(n)
	room_seen_depth.resize(n)
	room_seen_visibility.resize(n)
	room_seen_reach.resize(n)
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


## 그 구획 안을 지금 직접(유리 너머가 아니라) 보는 사람: 조 id · COMMANDER_SEER(지휘관·바깥에서 열린 창으로) · -1(아무도 없음)
func clear_seer(c: Compartment) -> int:
	return room_clear_by[c.index]


## 천장의 롤오버가 화면에 보이는가 — 누가 그 방 안을 직접 보고 있을 때만 (닫힌 유리창 너머로는 연기만, 무전 보고와 같다)
func rollover_visible(c: Compartment) -> bool:
	return not enabled or room_clear_by[c.index] != -1


func update(tick: int) -> void:
	_cast_levels.clear()
	# 지난번에 보인 칸만 지운다 (전체 배열을 지우지 않음 — 성능, P14)
	for i in _vis_list:
		visible_now[i] = 0
	_vis_list.clear()
	for i in _thermal_list:
		thermal_now[i] = 0
	_thermal_list.clear()
	room_visible_now.fill(0)
	room_clear_by.fill(-1)
	_update_room_visibility()
	# 대원이 직접 본 칸 (눈·손 — 닫힌 유리창 너머는 빼고, _cast·_touch 가 채운다)
	for i in _crew_list:
		crew_visible_now[i] = 0
	_crew_list.clear()
	for c in units.crews:
		for ff in c.members():
			if ff.incapacitated or not _should_cast(ff):
				continue
			var eye := _eye_crouch if ff.crouched else _eye_stand
			_touch(ff.level, ff.pos, c.id)
			# 닫힌 문 칸 위(문에 붙어 선 사람)에서는 시선을 쏘지 않는다 — 첫걸음이 문 칸을 건너뛰어 문 너머 방 안이 보였다 (2026-11-25)
			if not _on_closed_door(ff):
				_cast(ff.level, ff.pos, eye, RAYS, _max_sight, false, c.id, false, true)
		if c.thermal_camera and not c.leader.incapacitated and _should_cast(c.leader):
			_cast(c.leader.level, c.leader.pos, _eye_stand, RAYS, _tic_range, true, -1, false, true)
	var crew_count := _vis_list.size()
	_window_count += 1
	if _window_count % _window_every != 0:
		for i in _window_cells:
			_see(i)
		for r: int in _window_clear:
			if room_clear_by[r] == -1:
				room_clear_by[r] = int(_window_clear[r])
	else:
		_window_clear.clear()
		_cast_windows()
		# 창으로 보인 칸 (대원 눈으로 본 칸 다음에 붙은 것)을 다음 갱신 때까지 쓴다
		_window_cells = _vis_list.slice(crew_count)
	_fill_gaps()
	_record(tick)


## 밖에서 창·열린 문으로 들여다보기 (지휘관·바깥 대원). 화염·연기는 보이지만 바닥에 쓰러진 사람은 보이지 않는다
func _cast_windows() -> void:
	var watchers := _outside_watchers()
	var ground := building.levels()[0]
	for lv in building.levels():
		if building.floor_number(lv) >= 1:
			ground = lv
			break
	for o in _exterior:
		if o.kind == Opening.Kind.DOOR and not o.is_open:
			continue
		var center := Vector2.ZERO
		for cell in o.cells:
			center += Vector2(cell) + Vector2(0.5, 0.5)
		center /= o.cells.size()
		# 그 창이 향한 쪽에 보는 사람이 있어야 들여다볼 수 있다 (반대편 면은 둘러봐야 안다). 가장 가까운 사람이 본 것으로 한다
		var n: Vector2 = _normal.get(o.index, Vector2.ZERO)
		var watched := watchers.is_empty() and commander == null
		var who := -1
		var best := INF
		for w: Array in watchers:
			var d: Vector2 = (w[0] as Vector2) - center
			if d.length() <= WINDOW_VIEW_CELLS and (n == Vector2.ZERO or d.dot(n) > 0.5) and d.length() < best:
				watched = true
				best = d.length()
				who = int(w[1])
		# 닫힌 유리창 너머는 화염 불빛·연기만 — 방 안을 '직접 본' 것으로 치지 않는다 (열린 창·깨진 창·열린 문은 직접 본다)
		var glass := o.kind == Opening.Kind.WINDOW and not o.is_open
		if watched:
			if o.level - ground < _window_low_floors:
				_cast(o.level, center, _eye_stand, WINDOW_RAYS, WINDOW_RANGE_CELLS, false, who, glass)
			else:
				_cast(o.level, center, _eye_stand, WINDOW_RAYS / 2, _window_high_range, false, who, glass)


func _see(i: int) -> void:
	if visible_now[i] == 0:
		visible_now[i] = 1
		_vis_list.append(i)


## 시선 사이로 빠진 칸 메우기: 실내에서 안 보이는 칸인데 주변 8칸 중 FILL_MIN_NEIGHBORS 칸 이상 보이면 보이는 것으로 한다
## 보인 칸의 이웃만 살핀다 (성능, P14)
func _fill_gaps() -> void:
	var fill := PackedInt32Array()
	var checked := {}
	var w := _w
	var h := building.height
	for v in _vis_list.duplicate():
		var vy := (v % _per_level) / w
		var vx := v % w
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var x := vx + ox
				var y := vy + oy
				if x < 1 or y < 1 or x >= w - 1 or y >= h - 1:
					continue
				var i := v + oy * w + ox
				if checked.has(i) or visible_now[i] == 1 or (_room[i] < 0 and _type[i] != BuildingData.Cell.DOOR):
					continue
				checked[i] = true
				# 벽·창 이웃은 보이는 것으로 센다 (벽에 붙은 칸도 메워지도록)
				var n := 0
				var seen_any := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var j := i + dy * w + dx
						if visible_now[j] == 1:
							n += 1
							seen_any = true
						elif _type[j] == BuildingData.Cell.WALL or _type[j] == BuildingData.Cell.WINDOW:
							n += 1
				if seen_any and n >= FILL_MIN_NEIGHBORS:
					fill.append(i)
	for i in fill:
		_see(i)


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
	for i in _vis_list:
		seen_tick[i] = tick
		var st := grid.state[i]
		seen_burning[i] = 1 if st == FuelGrid.State.BURNING else 0
		seen_burnt[i] = 1 if st == FuelGrid.State.BURNT else 0
		var r := _room[i]
		if r >= 0:
			room_visible_now[r] = 1
	for c in fire.comps:
		if room_visible_now[c.index] == 1:
			room_seen[c.index] = 1
			room_seen_depth[c.index] = c.layer_depth
			room_seen_visibility[c.index] = fire.visibility_m(c)
			room_seen_reach[c.index] = 1.0e6 if c.smoke_covered() else c.smoke_reach_m


func _on_closed_door(ff: Firefighter) -> bool:
	var c := Vector2i(ff.pos.floor())
	if not building.in_bounds(c.x, c.y):
		return false
	var oi := _opening[fire.grid.index(ff.level, c.x, c.y)]
	return oi >= 0 and _type[fire.grid.index(ff.level, c.x, c.y)] == BuildingData.Cell.DOOR and not fire.openings[oi].is_open


## 손이 닿는 칸 (연기와 상관없이 안다). who = 그 대원의 조 id.
## 닫힌 문 칸 위에 서 있으면 문 너머는 만질 수 없다 — 제 칸만 (2026-11-25: 문 칸 위에서 닫힌 문 너머 방 안을 '안다'고 했다)
func _touch(level: int, pos: Vector2, who := -1) -> void:
	_cast_levels[level] = true
	var c := Vector2i(pos.floor())
	var own := fire.grid.index(level, c.x, c.y) if building.in_bounds(c.x, c.y) else -1
	var r := 0 if own >= 0 and _opening[own] >= 0 and not fire.openings[_opening[own]].is_open else TOUCH_CELLS
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if building.in_bounds(x, y):
				var i := fire.grid.index(level, x, y)
				if _type[i] != BuildingData.Cell.WALL:
					_see(i)
					_see_clear(i, who, true)


## 유리 너머가 아니라 직접 본 칸: eyes 면 대원이 직접 본 칸(crew_visible)으로, who 가 있으면 그 구획을 직접 본 사람으로 적는다
func _see_clear(i: int, who: int, eyes: bool, from_window := false) -> void:
	if eyes and crew_visible_now[i] == 0:
		crew_visible_now[i] = 1
		_crew_list.append(i)
	var r := _room[i]
	if who != -1 and r >= 0 and room_clear_by[r] == -1:
		room_clear_by[r] = who
		if from_window:
			_window_clear[r] = who


## 사방으로 시선을 쏜다. thermal이면 연기를 무시하고 거리로만 제한한다.
## who = 보는 사람 (조 id · COMMANDER_SEER · -1 모름), glass = 닫힌 유리창에서 시작한다 (창 들여다보기),
## eyes = 대원 자신의 눈이다 (직접 본 칸 crew_visible 로 적는다). 닫힌 유리창을 지나면 그 뒤는 '유리 너머'다 —
## 보이기는 하지만(화염·연기) 직접 본 것으로 치지 않는다 (2026-11-25: 현관 앞 대원이 옆 거실 창 너머로 천장 롤오버를 보고했다)
func _cast(level: int, origin: Vector2, eye: float, rays: int, max_cells: float, thermal: bool, who := -1, glass := false, eyes := false) -> void:
	_cast_levels[level] = true
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
		var through := glass
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
					# 연기 선두가 아직 안 온 곳은 맑다
					if not c.smoke_reaches(Vector2(px, py)):
						vis = _outdoor_vis_cells
					else:
						vis = _vis_upper[r] if eye >= c.height - c.shown_layer_depth() else _vis_lower[r]
				elif type == BuildingData.Cell.DOOR or type == BuildingData.Cell.WINDOW:
					vis = 2.0
				haze += STEP_CELLS / vis
			if i == last:
				if haze > _glow:
					break
				continue
			last = i
			if thermal:
				if thermal_now[i] == 0:
					thermal_now[i] = 1
					_thermal_list.append(i)
				if state[i] == FuelGrid.State.BURNING:
					_see(i)
					if eyes:
						_see_clear(i, -1, true)
			elif haze <= 1.0:
				_see(i)
				if not through:
					_see_clear(i, who, eyes, not eyes)
			elif haze <= _glow:
				if state[i] == FuelGrid.State.BURNING:
					_see(i)
					if not through and eyes:
						_see_clear(i, -1, true)
			else:
				break
			# 닫힌 문은 시선을 막는다. 깨지지 않은 유리창은 눈에는 투명하지만 열화상(원적외선)은 통과하지 못한다
			var oi := _opening[i]
			if oi >= 0 and not openings[oi].is_open:
				if type == BuildingData.Cell.DOOR or thermal:
					break
				through = true


## 밖에서 보는 사람: 현장지휘관 + 건물 밖에 내린 대원. [[위치, 누구 (조 id · 지휘관 COMMANDER_SEER)]]
func _outside_watchers() -> Array[Array]:
	var out: Array[Array] = []
	if commander:
		out.append([commander.pos, COMMANDER_SEER])
	for c in units.crews:
		for ff in c.members():
			if ff.incapacitated or ff.aboard:
				continue
			if building.cell(ff.level, floori(ff.pos.x), floori(ff.pos.y)) in BuildingData.OUTDOOR:
				out.append([ff.pos, c.id])
	return out


## 바깥쪽 방향: 개구부 칸 옆에서 밖(빈 공간·마당·도로)인 쪽
func _outward(o: Opening) -> Vector2:
	var sum := Vector2.ZERO
	for c in o.cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = c.x + d.x
			var ny: int = c.y + d.y
			if not building.in_bounds(nx, ny) or building.cell(o.level, nx, ny) in BuildingData.OUTDOOR:
				sum += Vector2(d)
	return sum.normalized()
