class_name FuelGrid
extends RefCounted
## 셀 단위 가연물. 각 셀은 가열 → 착화 → 연소 → 소진 순서로 진행한다.
## - 옆 셀의 화염과 천장 고온층의 복사열이 열량(dose)으로 쌓이고, 재질별 착화 열량을 넘으면 착화
## - 착화 후 열방출률은 ramp_s 동안 제곱으로 커지고, 연료가 20% 아래로 줄면 감소
## 문 셀은 방에 속하지 않고, 양쪽 방에 열방출을 나눈다.

enum State { NONE, UNBURNED, BURNING, BURNT }

const CELL_AREA_FACTOR := 0.25  # 0.5m 셀의 면적 (m²)
const TAIL_FRACTION := 0.2

var width := 0
var height := 0
var levels: Array[int] = []

var state: PackedByteArray
var mat: PackedInt32Array
var fuel: PackedFloat32Array
var fuel0: PackedFloat32Array
var dose: PackedFloat32Array
var burn_t: PackedFloat32Array
var hrr: PackedFloat32Array
## 방수로 셀에 남은 물 (L). 마를 때까지 다시 가열되지 않는다.
var wet: PackedFloat32Array
## 타는 셀이 방수로 빼앗긴 열 (MJ). 기준을 넘으면 꺼진다.
var suppress: PackedFloat32Array
var room: PackedInt32Array
var fuel_cells: PackedInt32Array
## 지금 타고 있는 셀 (매 틱 갱신)
var burning: PackedInt32Array
## 구획별 셀 목록
var room_cells: Array[PackedInt32Array] = []
## 구획별 셀 + 그 구획에 맞닿은 문 셀 (방수 대상 탐색용)
var room_and_door_cells: Array[PackedInt32Array] = []
## 문 셀 -> 맞닿은 구획들
var door_rooms: Dictionary = {}

var mat_names: Array[String] = []
var _peak: PackedFloat32Array
var _ramp: PackedFloat32Array
var _ignition: PackedFloat32Array
var _soot_yield: PackedFloat32Array
var _flame_spread: PackedFloat32Array
var _neighbors: Array[PackedInt32Array] = []
var _neighbor_w: Array[PackedFloat32Array] = []

var _k_adj: float
var _diag_w: float
var _cooling: float
var _smolder: float
var _fuel_heat: float
var _water_kj: float
var _extinguish_s: float
var _extinguish_min: float


static func build(building: BuildingData, config: FireConfig, comps: Array[Compartment], openings: Array[Opening], room_map: Dictionary) -> FuelGrid:
	var g := FuelGrid.new()
	g._setup(building, config, comps, openings, room_map)
	return g


func index(level: int, x: int, y: int) -> int:
	return (levels.find(level) * height + y) * width + x


@warning_ignore("integer_division")
func cell_of(i: int) -> Vector3i:
	var per_level := width * height
	var li := i / per_level
	var r := i % per_level
	return Vector3i(r % width, r / width, levels[li])


func material_name(i: int) -> String:
	return mat_names[mat[i]] if mat[i] >= 0 else ""


func peak_kw(i: int) -> float:
	return _peak[mat[i]] if mat[i] >= 0 else 0.0


## 셀에 불을 붙인다. ramp_skip은 연소 성장 단계를 건너뛸 비율 (플래시오버 동시 착화용).
func ignite(i: int, ramp_skip := 0.0) -> bool:
	if state[i] != State.UNBURNED:
		return false
	state[i] = State.BURNING
	burn_t[i] = _ramp[mat[i]] * ramp_skip
	return true


func ignite_room(room_index: int, ramp_skip: float) -> void:
	for i in room_cells[room_index]:
		if wet[i] <= 0.0:
			ignite(i, ramp_skip)


## 셀에 물을 뿌린다. 타는 셀이면 열을 빼앗고 기준을 넘으면 끈다. 꺼지면 true.
func apply_water(i: int, liters: float, efficiency: float) -> bool:
	wet[i] += liters
	if state[i] != State.BURNING:
		dose[i] = 0.0
		return false
	suppress[i] += liters * _water_kj * efficiency / 1000.0
	var need := maxf(_extinguish_min, hrr[i] * _extinguish_s / 1000.0)
	if suppress[i] < need:
		return false
	state[i] = State.UNBURNED
	hrr[i] = 0.0
	dose[i] = 0.0
	burn_t[i] = 0.0
	suppress[i] = 0.0
	return true


## center(셀 좌표) 반경 radius 안의 가연물 셀
func cells_in_radius(level: int, center: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r := ceili(radius)
	var c := Vector2i(center.floor())
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if x < 0 or y < 0 or x >= width or y >= height:
				continue
			if Vector2(x + 0.5, y + 0.5).distance_to(center) > radius:
				continue
			var i := index(level, x, y)
			if state[i] != State.NONE:
				out.append(i)
	return out


func step(dt: float, comps: Array[Compartment], model: CompartmentModel) -> void:
	# 1) 타는 셀: 열방출률과 연료 소모
	for i in fuel_cells:
		if state[i] != State.BURNING:
			continue
		var m := mat[i]
		burn_t[i] += dt
		var ramp := minf(1.0, pow(burn_t[i] / _ramp[m], 2.0))
		var tail := minf(1.0, fuel[i] / (fuel0[i] * TAIL_FRACTION))
		hrr[i] = _peak[m] * ramp * tail
		var eff := _eff(i, comps)
		fuel[i] -= hrr[i] * dt / 1000.0 * (_smolder + (1.0 - _smolder) * eff)
		if fuel[i] <= 0.0:
			fuel[i] = 0.0
			hrr[i] = 0.0
			state[i] = State.BURNT
	# 2) 타지 않은 셀: 옆 화염 + 고온층 복사열 누적 → 착화
	var radiation := PackedFloat32Array()
	radiation.resize(comps.size())
	for c in comps:
		radiation[c.index] = model.layer_radiation_kw_m2(c) * CELL_AREA_FACTOR
	for i in fuel_cells:
		if state[i] != State.UNBURNED:
			continue
		var q_flame := 0.0
		var nb := _neighbors[i]
		var w := _neighbor_w[i]
		for k in nb.size():
			var n := nb[k]
			if state[n] == State.BURNING:
				q_flame += _k_adj * w[k] * hrr[n] * _eff(n, comps)
		var q_in := _cell_radiation(i, radiation) + q_flame * _flame_spread[mat[i]]
		# 젖은 셀은 받은 열로 물부터 증발시킨다
		if wet[i] > 0.0:
			wet[i] = maxf(0.0, wet[i] - q_in * dt / _water_kj)
			continue
		dose[i] = dose[i] * (1.0 - _cooling * dt) + q_in * dt
		if dose[i] >= _ignition[mat[i]]:
			ignite(i)
	# 3) 구획별 합계, 타는 셀 목록
	burning.clear()
	for c in comps:
		c.q_potential = 0.0
		c.soot_rate = 0.0
		c.fuel_remaining = 0.0
	for i in fuel_cells:
		if state[i] == State.BURNING:
			burning.append(i)
		var share := _rooms_of(i)
		if share.is_empty():
			continue
		var part := 1.0 / share.size()
		for r in share:
			var c := comps[r]
			c.fuel_remaining += fuel[i] * part
			if state[i] == State.BURNING:
				c.q_potential += hrr[i] * part
				c.soot_rate += hrr[i] * part / _fuel_heat * _soot_yield[mat[i]]


func _setup(building: BuildingData, config: FireConfig, comps: Array[Compartment], openings: Array[Opening], room_map: Dictionary) -> void:
	width = building.width
	height = building.height
	levels = building.levels()
	_k_adj = config.value("neighbor_heat_ratio")
	_diag_w = config.value("diagonal_heat_weight")
	_cooling = config.value("heat_dose_cooling_per_s")
	_smolder = config.value("smolder_consumption_ratio")
	_fuel_heat = config.value("fuel_heat_kj_kg")
	_water_kj = config.value("water_cooling_kj_per_l")
	_extinguish_s = config.value("extinguish_heat_seconds")
	_extinguish_min = config.value("extinguish_min_mj")

	var names: Array = config.materials.keys()
	names.sort()
	mat_names.assign(names)
	for n in mat_names:
		var m: Dictionary = config.materials[n]
		_peak.append(float(m.peak_kw))
		_ramp.append(float(m.ramp_s))
		_ignition.append(float(m.ignition_kj))
		_soot_yield.append(float(m.soot_yield))
		_flame_spread.append(float(m.get("flame_spread", 1.0)))

	var total := width * height * levels.size()
	state.resize(total)
	mat.resize(total)
	mat.fill(-1)
	fuel.resize(total)
	fuel0.resize(total)
	dose.resize(total)
	burn_t.resize(total)
	hrr.resize(total)
	wet.resize(total)
	suppress.resize(total)
	room.resize(total)
	room.fill(-1)
	_neighbors.resize(total)
	_neighbor_w.resize(total)
	room_cells.resize(comps.size())

	# 방 내장재
	for c in comps:
		var lining := _lining_of(building, c)
		for cell in c.cells:
			var i := index(c.level, cell.x, cell.y)
			room[i] = c.index
			if lining != "":
				_set_material(i, lining, config)
	# 가구
	for level in levels:
		for item in building.furniture(level):
			var r: Rect2i = item.rect
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var i := index(level, x, y)
					if room[i] >= 0 and config.has_material(item.material):
						_set_material(i, item.material, config)
	# 문
	for o in openings:
		if o.kind != Opening.Kind.DOOR or not config.has_material("문"):
			continue
		var sides := PackedInt32Array([o.room_a])
		if o.room_b != Opening.OUTSIDE:
			sides.append(o.room_b)
		for cell in o.cells:
			var i := index(o.level, cell.x, cell.y)
			_set_material(i, "문", config)
			door_rooms[i] = sides

	for i in total:
		if state[i] == State.UNBURNED:
			fuel_cells.append(i)
			if room[i] >= 0:
				room_cells[room[i]].append(i)
	room_and_door_cells.resize(comps.size())
	for r in comps.size():
		room_and_door_cells[r] = room_cells[r].duplicate()
	for i: int in door_rooms:
		for r in door_rooms[i]:
			room_and_door_cells[r].append(i)
	for i in fuel_cells:
		_link_neighbors(i)
	for c in comps:
		c.fuel_initial = 0.0
	for i in fuel_cells:
		var share := _rooms_of(i)
		for r in share:
			comps[r].fuel_initial += fuel0[i] / float(share.size())
	for c in comps:
		c.fuel_remaining = c.fuel_initial


func _lining_of(building: BuildingData, c: Compartment) -> String:
	for r in building.rooms(c.level):
		if r.id == c.id and r.lining != "":
			return r.lining if r.lining != "불연" else ""
	return "내장재"


func _set_material(i: int, material_name: String, config: FireConfig) -> void:
	var mi := mat_names.find(material_name)
	if mi < 0:
		return
	mat[i] = mi
	state[i] = State.UNBURNED
	fuel[i] = float(config.materials[material_name].fuel_mj)
	fuel0[i] = fuel[i]


func _link_neighbors(i: int) -> void:
	var c := cell_of(i)
	var nb := PackedInt32Array()
	var w := PackedFloat32Array()
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= width or y >= height:
				continue
			var n := index(c.z, x, y)
			if state[n] == State.NONE:
				continue
			nb.append(n)
			w.append(1.0 if dx == 0 or dy == 0 else _diag_w)
	_neighbors[i] = nb
	_neighbor_w[i] = w


func _rooms_of(i: int) -> PackedInt32Array:
	if room[i] >= 0:
		return PackedInt32Array([room[i]])
	return door_rooms.get(i, PackedInt32Array())


func _eff(i: int, comps: Array[Compartment]) -> float:
	var best := 0.0
	for r in _rooms_of(i):
		best = maxf(best, comps[r].combustion_eff)
	return best


func _cell_radiation(i: int, radiation: PackedFloat32Array) -> float:
	var best := 0.0
	for r in _rooms_of(i):
		best = maxf(best, radiation[r])
	return best
