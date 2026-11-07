class_name Pathfinder
extends RefCounted
## 셀 격자 길찾기. 층마다 AStarGrid2D를 두고, 다른 층으로 갈 때는 계단을 거친다.
## 경로는 Vector3i(x, y, 층) 목록이다.

const NO_CELL := Vector2i(-1, -1)
## 대형 슬롯 탐색 시 살펴볼 최대 셀 수
const FORMATION_SEARCH_LIMIT := 400

var _building: BuildingData
var _grids: Dictionary = {}  # level -> AStarGrid2D
## 닫힌 문 등으로 일시적으로 막힌 셀 (Vector3i -> true)
var _blocked: Dictionary = {}
## 차체 바닥이 차도 위에 있는지 볼 때 표본을 찍는 간격 (셀)
const VEHICLE_SAMPLE_CELLS := 0.5


func _init(building: BuildingData) -> void:
	_building = building
	for level in building.levels():
		var grid := AStarGrid2D.new()
		grid.region = Rect2i(0, 0, building.width, building.height)
		grid.cell_size = Vector2.ONE
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.update()
		for y in building.height:
			for x in building.width:
				if not building.is_walkable(level, x, y):
					grid.set_point_solid(Vector2i(x, y))
		_grids[level] = grid


## 셀을 막거나 연다 (닫힌 문). 원래 걸을 수 없는 셀은 무시한다.
func set_blocked(level: int, cell: Vector2i, blocked: bool) -> void:
	if not _building.is_walkable(level, cell.x, cell.y) or not _grids.has(level):
		return
	var key := Vector3i(cell.x, cell.y, level)
	if blocked:
		_blocked[key] = true
	else:
		_blocked.erase(key)
	_grids[level].set_point_solid(cell, blocked)


## 지금 지나갈 수 있는 셀인지 (도면상 걸을 수 있고, 닫힌 문으로 막히지 않음)
func passable(level: int, x: int, y: int) -> bool:
	return _building.is_walkable(level, x, y) and not _blocked.has(Vector3i(x, y, level))


## 차체 바닥(네 모서리, 셀 좌표)이 전부 가장 아래층 차도 위에 있는지
func vehicle_fits(corners: PackedVector2Array) -> bool:
	var ground := _building.levels()[0]
	var along := corners[1] - corners[0]
	var across := corners[3] - corners[0]
	var n_along := maxi(1, ceili(along.length() / VEHICLE_SAMPLE_CELLS))
	var n_across := maxi(1, ceili(across.length() / VEHICLE_SAMPLE_CELLS))
	for i in n_along + 1:
		for j in n_across + 1:
			var p := corners[0] + along * (float(i) / n_along) + across * (float(j) / n_across)
			# 모서리가 셀 경계에 걸친 경우 안쪽 셀로 판정
			p = p.lerp(corners[0] + along * 0.5 + across * 0.5, 0.001)
			if _building.cell(ground, floori(p.x), floori(p.y)) != BuildingData.Cell.ROAD:
				return false
	return true


## start에서 goal까지의 경로. 도달할 수 없으면 빈 배열.
func find_path(start: Vector3i, goal: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var cur := start
	while cur.z != goal.z:
		var next_level := cur.z + signi(goal.z - cur.z)
		var best: Array[Vector3i] = []
		var best_cost := INF
		for stair in _building.stair_links(mini(cur.z, next_level)):
			var seg := _floor_path(cur.z, Vector2i(cur.x, cur.y), stair)
			if seg.is_empty():
				continue
			var cost := seg.size() + Vector2(stair).distance_to(Vector2(goal.x, goal.y))
			if cost < best_cost:
				best_cost = cost
				best = seg
		if best.is_empty():
			return []
		_append(result, best)
		cur = Vector3i(best[-1].x, best[-1].y, next_level)
		result.append(cur)
	var last := _floor_path(cur.z, Vector2i(cur.x, cur.y), Vector2i(goal.x, goal.y))
	if last.is_empty():
		return []
	_append(result, last)
	return result


## cell이 걸을 수 없는 곳이면 가장 가까운 걸을 수 있는 셀을 찾는다. 없으면 NO_CELL.
func nearest_walkable(level: int, cell: Vector2i, max_radius := 6) -> Vector2i:
	if passable(level, cell.x, cell.y):
		return cell
	for r in range(1, max_radius + 1):
		var best := NO_CELL
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := cell + Vector2i(dx, dy)
				var d := Vector2(dx, dy).length_squared()
				if d < best_d and passable(level, c.x, c.y):
					best = c
					best_d = d
		if best != NO_CELL:
			return best
	return NO_CELL


## target 주변에서 서로 spacing 셀 이상 떨어진 도착 지점 count개를 찾는다.
## 벽을 넘지 않도록 걸을 수 있는 셀만 따라 너비 우선으로 탐색한다.
func formation_slots(level: int, target: Vector2i, count: int, spacing := 2) -> Array[Vector2i]:
	var slots: Array[Vector2i] = []
	if not passable(level, target.x, target.y):
		return slots
	var queue: Array[Vector2i] = [target]
	var visited := {target: true}
	var head := 0
	while head < queue.size() and slots.size() < count and head < FORMATION_SEARCH_LIMIT:
		var c := queue[head]
		head += 1
		var free := true
		for s in slots:
			if maxi(absi(s.x - c.x), absi(s.y - c.y)) < spacing:
				free = false
				break
		if free:
			slots.append(c)
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var n := c + d
			if not visited.has(n) and passable(level, n.x, n.y):
				visited[n] = true
				queue.append(n)
	return slots


func _floor_path(level: int, from: Vector2i, to: Vector2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var grid: AStarGrid2D = _grids.get(level)
	if grid == null or not grid.is_in_boundsv(from) or not grid.is_in_boundsv(to):
		return out
	if grid.is_point_solid(from) or grid.is_point_solid(to):
		return out
	for p in grid.get_id_path(from, to):
		out.append(Vector3i(p.x, p.y, level))
	return out


static func _append(result: Array[Vector3i], seg: Array[Vector3i]) -> void:
	var start := 1 if not result.is_empty() and result[-1] == seg[0] else 0
	for i in range(start, seg.size()):
		result.append(seg[i])
