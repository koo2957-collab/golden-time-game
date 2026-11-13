class_name FuelGrid
extends RefCounted
## 셀 단위 가연물. 각 셀은 가열 → 착화 → 연소 → 소진 순서로 진행한다.
## - 옆 셀의 화염과 천장 고온층의 복사열이 열량(dose)으로 쌓이고, 재질별 착화 열량을 넘으면 착화
## - 착화 후 열방출률은 ramp_s 동안 제곱으로 커지고, 연료가 20% 아래로 줄면 감소
## - 남은 연료가 처음의 burnout_fuel_fraction 아래면 다 탄 것으로 본다 (교재 쇠퇴기: 가연물을 다 쓰면 꺼진다, 화재1 22쪽).
##   열방출이 남은 연료에 비례해 줄기 때문에 이 기준이 없으면 연료가 0에 닿지 않아 영원히 '연소 중'으로 남는다
## 문 셀은 방에 속하지 않고, 양쪽 방에 열방출을 나눈다.
## 구획 밖으로의 연소 확대 (2026-11-10, 화재1 13·21·23쪽 전도·대류·복사):
## - 대류: 뜨거운 연기층이 옆 구획으로 넘어가 그 구획 고온층을 데운다 (CompartmentModel)
## - 문 너머 복사: 열린·깨진 문으로 옆 구획 고온층이 보이면, 문 가까운 칸일수록 강하게 복사열을 받는다
## - 벽·바닥 너머 전도: 구획 벽체가 상부층 온도를 천천히 따라가고(구조별 시간 상수), 벽 뒤·바로 위층의 맞닿은 칸이 열을 받는다

enum State { NONE, UNBURNED, BURNING, BURNT }

const CELL_AREA_FACTOR := 0.25  # 0.5m 셀의 면적 (m²)
const TAIL_FRACTION := 0.2
const STEFAN_BOLTZMANN := 5.67e-11  # kW/(m²·K⁴)

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
var _burnout_fraction: float
## 재질별 필요 방수량 화재하중 계수 / 끌 수 있는 방수량 비율 (기획안 5-4, P6-1)
var _load_by_mat: PackedFloat32Array
var _toxic_by_mat: PackedFloat32Array
## 칸별 성장 시간 배율 (구석 가연물은 빨리 큼, 화재1 20쪽)
var _ramp_mul: PackedFloat32Array
var _extinguish_ratio := 1.0

# 구획 밖 연소 확대
var _t_amb: float
var _spread_min_t: float
var _wall_k: float
var _wall_tau: float
var _floor_f: float
var _door_flame: float
## 문 너머 복사: [{o: Opening, src: 구획, cells, w}]
var _door_rad: Array[Dictionary] = []
## 벽·바닥 너머 전도: 열을 내는 구획 -> {cells, f(벽 1, 바닥 floor_heat_factor)}
var _cond: Dictionary = {}
## 구획 벽체 온도 (℃)
var wall_t: PackedFloat32Array
## 숨은 잔화 계수 (가구 ember, 기본 1 — 이불·매트·섬유·목재 더미가 큼, 화재1 260쪽)
var ember_factor: PackedFloat32Array
## 이번 틱에 구획 밖에서 받은 열 (kW, 칸마다) / 값을 넣은 칸
var _ext: PackedFloat32Array
var _ext_touched: PackedInt32Array
# 성능 (P14): 열을 받는 구획만 계산
var _active_min_kw_m2: float
var _steps := 0
var _active: PackedByteArray
var _room_seen: PackedInt32Array
## 지난 step 뒤 새로 불붙은 셀 (ignite가 넣는다)
var _new_burning: PackedInt32Array
## 셀을 이번 step에서 이미 계산했는지 (중복 방지, step 번호)
var _in_burning: PackedInt32Array


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
	_new_burning.append(i)
	return true


func ignite_room(room_index: int, ramp_skip: float) -> void:
	for i in room_cells[room_index]:
		if wet[i] <= 0.0:
			ignite(i, ramp_skip)


## 셀에 물을 뿌린다. 타는 셀이면 열을 빼앗고 기준을 넘으면 끈다. 꺼지면 true.
## 그 방 방수량 비율(실제 ÷ 필요)이 모자라면 끄지 못하고 젖기만 한다 — 성장만 느려진다 (기획안 5-4, P6-1)
func apply_water(i: int, liters: float, efficiency: float, comps: Array[Compartment] = []) -> bool:
	wet[i] += liters
	if state[i] != State.BURNING:
		dose[i] = 0.0
		return false
	suppress[i] += liters * _water_kj * efficiency / 1000.0
	var need := maxf(_extinguish_min, hrr[i] * _extinguish_s / 1000.0)
	if not comps.is_empty() and _flow_ratio(i, comps) < _extinguish_ratio:
		suppress[i] = minf(suppress[i], need * 0.9)
		return false
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
	_steps += 1
	# 1) 타는 셀: 열방출률과 연료 소모 (지난 틱에 타던 셀 + 그 뒤 새로 붙은 셀만 — 성능, P14)
	for c in comps:
		c.q_potential = 0.0
		c.soot_rate = 0.0
		c.burning_area_m2 = 0.0
		c.load_factor = 1.0
	_active.fill(0)
	var live := burning
	live.append_array(_new_burning)
	_new_burning.clear()
	burning = PackedInt32Array()
	for i in live:
		if state[i] != State.BURNING or _in_burning[i] == _steps:
			continue
		_in_burning[i] = _steps
		var m := mat[i]
		burn_t[i] += dt
		var ramp := minf(1.0, pow(burn_t[i] / (_ramp[m] * _ramp_mul[i]), 2.0))
		var tail := minf(1.0, fuel[i] / (fuel0[i] * TAIL_FRACTION))
		hrr[i] = _peak[m] * ramp * tail
		var eff := _eff(i, comps)
		var used := hrr[i] * dt / 1000.0 * (_smolder + (1.0 - _smolder) * eff)
		if fuel[i] - used <= fuel0[i] * _burnout_fraction:
			used = fuel[i]
		fuel[i] -= used
		var share := _rooms_of(i)
		var part := 1.0 / maxf(1.0, share.size())
		for r in share:
			comps[r].fuel_remaining -= used * part
			_active[r] = 1
		if fuel[i] <= 0.0:
			fuel[i] = 0.0
			hrr[i] = 0.0
			state[i] = State.BURNT
			continue
		burning.append(i)
		for r in share:
			var c := comps[r]
			c.burning_area_m2 += CELL_AREA_FACTOR * part
			c.load_factor = maxf(c.load_factor, _load_by_mat[m])
			c.toxicity = maxf(c.toxicity, _toxic_by_mat[m])
			c.q_potential += hrr[i] * part
			c.soot_rate += hrr[i] * part / _fuel_heat * _soot_yield[m]
	# 2) 타지 않은 셀: 옆 화염 + 고온층 복사열 + 구획 밖에서 온 열(문 너머 복사·벽 너머 전도) 누적 → 착화
	#    열을 받는 구획(타는 셀이 있거나, 고온층 복사가 기준 이상이거나, 구획 밖 열을 받는 구획)만 계산한다.
	#    빠진 구획의 셀이 받는 열은 착화 열량의 10분의 1에도 못 미쳐 착화를 놓치지 않는다 (성능, P14)
	_external_heat(dt, comps)
	var radiation := PackedFloat32Array()
	radiation.resize(comps.size())
	for c in comps:
		var kw_m2 := model.layer_radiation_kw_m2(c)
		radiation[c.index] = kw_m2 * CELL_AREA_FACTOR
		if kw_m2 >= _active_min_kw_m2:
			_active[c.index] = 1
	for r in comps.size():
		if _active[r] == 0:
			continue
		# 쉬던 구획: 쉬는 동안의 열량 식음을 한 번에 적용
		var gap := _steps - _room_seen[r]
		_room_seen[r] = _steps
		var decay := pow(1.0 - _cooling * dt, gap - 1) if gap > 1 else 1.0
		for i in room_cells[r]:
			if state[i] == State.UNBURNED:
				if decay < 1.0:
					dose[i] *= decay
				_heat_cell(i, dt, comps, radiation)
	for i: int in door_rooms:
		if state[i] == State.UNBURNED:
			_heat_cell(i, dt, comps, radiation)


## 타지 않은 셀 하나: 받은 열 누적 → 착화
func _heat_cell(i: int, dt: float, comps: Array[Compartment], radiation: PackedFloat32Array) -> void:
	var q_flame := 0.0
	var nb := _neighbors[i]
	var w := _neighbor_w[i]
	for k in nb.size():
		var n := nb[k]
		if state[n] == State.BURNING:
			q_flame += _k_adj * w[k] * hrr[n] * _eff(n, comps)
	var q_in := _cell_radiation(i, radiation) + _ext[i] + q_flame * _flame_spread[mat[i]]
	# 젖은 셀은 받은 열로 물부터 증발시킨다
	if wet[i] > 0.0:
		wet[i] = maxf(0.0, wet[i] - q_in * dt / _water_kj)
		return
	dose[i] = dose[i] * (1.0 - _cooling * dt) + q_in * dt
	if dose[i] >= _ignition[mat[i]]:
		ignite(i)


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
	_burnout_fraction = config.value("burnout_fuel_fraction")
	_t_amb = config.value("ambient_temp_c")
	_spread_min_t = config.value("spread_min_temp_c")
	_wall_k = config.by_structure("wall_through_heat_kw_m2k", building.structure)
	_wall_tau = config.by_structure("wall_heat_tau_s", building.structure)
	_floor_f = config.value("floor_heat_factor")
	_door_flame = config.value("door_flame_kw_m2")

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
	var lf: Dictionary = config.params.get("required_flow_load_factor", {})
	for n in mat_names:
		_load_by_mat.append(float(lf.get("by_material", {}).get(n, lf.get("value", 1.0))))
		_toxic_by_mat.append(float(config.materials[n].get("toxic", 1.0)))
	_extinguish_ratio = config.value("flow_ratio_extinguish")

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
	ember_factor.resize(total)
	ember_factor.fill(1.0)
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
						ember_factor[i] = float(item.get("ember", 1.0))
	# 문
	for o in openings:
		if o.kind != Opening.Kind.DOOR or not config.has_material("문"):
			continue
		var sides := PackedInt32Array([o.room_a])
		if o.room_b != Opening.OUTSIDE:
			sides.append(o.room_b)
		for cell in o.cells:
			# 방화문(철재)은 타지 않는다 — 아파트 현관문·계단실 문 (화재1 151쪽: 문이 닫혀 있으면 세대 밖으로 잘 번지지 않음)
			if building.is_fire_door(cell):
				continue
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
	_scale_fire_load(building, config, comps)
	for i in fuel_cells:
		_link_neighbors(i)
	# 구석(벽 두 면 이상에 붙은) 가연물 칸
	var corner := config.value("corner_ramp_factor")
	_ramp_mul.resize(total)
	_ramp_mul.fill(1.0)
	for i in fuel_cells:
		var p := cell_of(i)
		var walls := 0
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			if building.cell(p.z, p.x + d.x, p.y + d.y) == BuildingData.Cell.WALL:
				walls += 1
		if walls >= 2:
			_ramp_mul[i] = corner
	for c in comps:
		c.fuel_initial = 0.0
	for i in fuel_cells:
		var share := _rooms_of(i)
		for r in share:
			comps[r].fuel_initial += fuel0[i] / float(share.size())
	for c in comps:
		c.fuel_remaining = c.fuel_initial
	_ext.resize(total)
	_in_burning.resize(total)
	_active.resize(comps.size())
	_room_seen.resize(comps.size())
	_active_min_kw_m2 = config.value("cell_active_min_kw_m2")
	wall_t.resize(comps.size())
	wall_t.fill(_t_amb)
	_setup_door_radiation(openings, config)
	_setup_conduction(building)


## 문마다 양쪽 구획의 가까운 가연물 칸과 세기 (거리 d → 1 / (1 + (d/d0)²))
func _setup_door_radiation(openings: Array[Opening], config: FireConfig) -> void:
	var reach := config.value("door_radiation_range_m") / 0.5
	var d0 := config.value("door_radiation_d0_m") / 0.5
	for o in openings:
		if o.kind != Opening.Kind.DOOR or o.room_b == Opening.OUTSIDE or o.cells.is_empty():
			continue
		var center := Vector2.ZERO
		for cell in o.cells:
			center += Vector2(cell) + Vector2(0.5, 0.5)
		center /= o.cells.size()
		for side: Array in [[o.room_a, o.room_b], [o.room_b, o.room_a]]:
			var cells := PackedInt32Array()
			var w := PackedFloat32Array()
			for i in room_cells[side[1]]:
				var p := cell_of(i)
				var d := (Vector2(p.x, p.y) + Vector2(0.5, 0.5)).distance_to(center)
				if d <= reach:
					cells.append(i)
					w.append(1.0 / (1.0 + (d / d0) * (d / d0)))
			if not cells.is_empty():
				_door_rad.append({"o": o, "src": side[0], "cells": cells, "w": w})


## 벽 뒤(같은 층, 벽 칸을 사이에 둔 다른 구획)와 바로 아래층 구획에 맞닿은 칸
func _setup_conduction(building: BuildingData) -> void:
	var lists := {}
	for i in fuel_cells:
		var b := room[i]
		if b < 0:
			continue
		var p := cell_of(i)
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			for k in range(1, 4):
				var x := p.x + dir.x * k
				var y := p.y + dir.y * k
				if x < 0 or y < 0 or x >= width or y >= height:
					break
				var n := index(p.z, x, y)
				if room[n] == b:
					break
				if room[n] >= 0:
					if k >= 2:
						_add_cond(lists, room[n], i, 1.0)
					break
				if building.cell(p.z, x, y) != BuildingData.Cell.WALL:
					break
		var li := levels.find(p.z)
		if li > 0 and levels[li - 1] == p.z - 1:
			var below := room[index(p.z - 1, p.x, p.y)]
			if below >= 0:
				_add_cond(lists, below, i, _floor_f)
	_cond = lists


func _add_cond(lists: Dictionary, src: int, cell: int, f: float) -> void:
	if not lists.has(src):
		lists[src] = {"cells": PackedInt32Array(), "f": PackedFloat32Array()}
	lists[src].cells.append(cell)
	lists[src].f.append(f)


## 이번 틱에 구획 밖에서 칸으로 들어오는 열 (kW): 문 너머 복사 + 벽·바닥 너머 전도
func _external_heat(dt: float, comps: Array[Compartment]) -> void:
	for i in _ext_touched:
		_ext[i] = 0.0
	_ext_touched.clear()
	var ta := _t_amb + 273.0
	for e in _door_rad:
		var o: Opening = e.o
		if not (o.is_open or o.broken):
			continue
		var s := comps[int(e.src)]
		if s.t_upper < _spread_min_t:
			continue
		# 문 높이 가운데 연기층이 덮은 비율만큼 고온층이 보인다
		var cover := clampf((o.top - (s.height - s.layer_depth)) / maxf(o.top - o.sill, 0.1), 0.0, 1.0)
		var tk := s.t_upper + 273.0
		var flux_m2 := STEFAN_BOLTZMANN * (tk * tk * tk * tk - ta * ta * ta * ta) * cover
		# 최성기 구획: 화염과 연소가스가 문 밖으로 분출해 문 가까운 가연물을 직접 가열 (화재1 21쪽)
		if s.flashed and s.stage == Compartment.Stage.FULLY_DEVELOPED:
			flux_m2 += _door_flame
		if flux_m2 <= 0.0:
			continue
		var flux := flux_m2 * CELL_AREA_FACTOR
		var cells: PackedInt32Array = e.cells
		var w: PackedFloat32Array = e.w
		for k in cells.size():
			_ext[cells[k]] += flux * w[k]
		_ext_touched.append_array(cells)
		_active[room[cells[0]]] = 1
	var rate := minf(1.0, dt / maxf(_wall_tau, 1.0))
	for c in comps:
		wall_t[c.index] += (c.t_upper - wall_t[c.index]) * rate
	for src: int in _cond:
		var d_t := wall_t[src] - _t_amb
		if d_t < _spread_min_t - _t_amb:
			continue
		var q := _wall_k * d_t * CELL_AREA_FACTOR
		var cells: PackedInt32Array = _cond[src].cells
		var f: PackedFloat32Array = _cond[src].f
		for k in cells.size():
			_ext[cells[k]] += q * f[k]
			_active[room[cells[k]]] = 1
		_ext_touched.append_array(cells)


## 화재하중 맞추기 (2026-11-13 사용자 결정 P1, Eurocode EN 1991-1-2 표 E.4): 건물 용도의 면적당 화재하중(MJ/㎡)이 되도록
## 방 안 생활용품·내장재(재질의 contents) 칸의 연료를 같은 비율로 늘린다. 가구 하나하나의 열량에는 옷·책·이불 같은
## 생활용품이 빠져 있기 때문이다. 최대 열방출률·착화는 그대로라 타는 시간만 길어진다. 줄이지는 않는다 (배율 1 이상)
var fire_load_scale := 1.0


func _scale_fire_load(building: BuildingData, config: FireConfig, comps: Array[Compartment]) -> void:
	var target := config.by_occupancy("fire_load_mj_m2", building.occupancy)
	if target <= 0.0:
		return
	var area := 0.0
	for c in comps:
		area += c.area
	var fixed := 0.0
	var scalable := 0.0
	var cells := PackedInt32Array()
	for r in room_cells.size():
		for i in room_cells[r]:
			if bool(config.materials[mat_names[mat[i]]].get("contents", false)):
				scalable += fuel0[i]
				cells.append(i)
			else:
				fixed += fuel0[i]
	if scalable <= 0.0 or area <= 0.0:
		return
	fire_load_scale = maxf(1.0, (target * area - fixed) / scalable)
	for i in cells:
		fuel[i] *= fire_load_scale
		fuel0[i] = fuel[i]


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


func _flow_ratio(i: int, comps: Array[Compartment]) -> float:
	var best := 0.0
	for r in _rooms_of(i):
		best = maxf(best, comps[r].flow_ratio)
	return best


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
