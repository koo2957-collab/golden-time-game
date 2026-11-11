class_name StairCores
extends RefCounted
## 계단실 (P4-5 층·계단 고르기): 층마다 이어진 계단 칸 덩어리 = 계단 하나.
## 대원이 다른 층으로 갈 때 계단이 둘 이상이면 지휘관에게 어느 계단으로 갈지 묻는다 (급기측·배기측 판단, SSG 4).

var building: BuildingData
var _cores: Dictionary = {}  # level -> Array[Array[Vector2i]]


func _init(p_building: BuildingData) -> void:
	building = p_building


## 그 층의 계단 목록 (계단마다 칸 배열)
func cores(level: int) -> Array:
	if not _cores.has(level):
		_cores[level] = _find(level)
	return _cores[level]


func _find(level: int) -> Array:
	var out: Array = []
	if not building.has_level(level):
		return out
	var seen: Dictionary = {}
	for y in building.height:
		for x in building.width:
			var start := Vector2i(x, y)
			if seen.has(start) or building.cell(level, x, y) != BuildingData.Cell.STAIRS:
				continue
			var group: Array[Vector2i] = []
			var todo: Array[Vector2i] = [start]
			seen[start] = true
			while not todo.is_empty():
				var c: Vector2i = todo.pop_back()
				group.append(c)
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n := c + d
					if not seen.has(n) and building.in_bounds(n.x, n.y) and building.cell(level, n.x, n.y) == BuildingData.Cell.STAIRS:
						seen[n] = true
						todo.append(n)
			out.append(group)
	return out


## 계단의 가운데 (칸 좌표)
func center(level: int, index: int) -> Vector2:
	var cells: Array = cores(level)[index]
	var sum := Vector2.ZERO
	for c: Vector2i in cells:
		sum += Vector2(c) + Vector2(0.5, 0.5)
	return sum / maxf(1.0, cells.size())


## 칸이 속한 계단 (없으면 -1)
func core_at(level: int, cell: Vector2i) -> int:
	var list := cores(level)
	for i in list.size():
		if cell in list[i]:
			return i
	return -1


## from 층의 계단 index가 to 층으로 이어지는가 (사이의 모든 층에 같은 자리 계단 칸이 있다)
func reaches(from_level: int, index: int, to_level: int) -> bool:
	return landing(from_level, index, to_level).x >= 0


## from 층 계단 index로 올라가거나 내려가 닿는 to 층의 계단 칸 (못 가면 (-1, -1))
func landing(from_level: int, index: int, to_level: int) -> Vector2i:
	var cells: Array = cores(from_level)[index]
	var step := 1 if to_level > from_level else -1
	var column: Array[Vector2i] = []
	for c: Vector2i in cells:
		column.append(c)
	var lv := from_level
	while lv != to_level:
		var nxt: Array[Vector2i] = []
		for c in column:
			if building.cell(lv + step, c.x, c.y) == BuildingData.Cell.STAIRS:
				nxt.append(c)
		if nxt.is_empty():
			return Vector2i(-1, -1)
		# 다음 층의 같은 계단 덩어리 전체로 넓힌다 (층마다 계단참 모양이 달라도)
		var core := core_at(lv + step, nxt[0])
		column.clear()
		for c: Vector2i in cores(lv + step)[core]:
			column.append(c)
		lv += step
	var mid := Vector2.ZERO
	for c in column:
		mid += Vector2(c)
	mid /= maxf(1.0, column.size())
	var best := column[0]
	for c in column:
		if Vector2(c).distance_to(mid) < Vector2(best).distance_to(mid):
			best = c
	return best


## from 층에서 to 층으로 이어지는 계단 index 목록
func toward(from_level: int, to_level: int) -> Array[int]:
	var out: Array[int] = []
	for i in cores(from_level).size():
		if reaches(from_level, i, to_level):
			out.append(i)
	return out


## 계단 이름: A계단·B계단 … (그 층 안에서 왼쪽 위부터)
func label(level: int, index: int) -> String:
	return "%s계단" % char(65 + index) if index < 26 else "계단 %d" % (index + 1)


## 바람 기준 위치: 건물 가운데에서 바람이 불어오는 쪽이면 급기측 (EntryPoints.side와 같은 기준). 바람이 없으면 ""
func side(level: int, index: int, exposure: ExposureSystem) -> String:
	if exposure == null or exposure.wind_mps <= 0.0:
		return ""
	var fp := building.footprint(level)
	var rel := center(level, index) - (Vector2(fp.position) + Vector2(fp.size) * 0.5)
	if rel.length() < 0.5:
		return "중앙"
	var rad := deg_to_rad(exposure.wind_from_deg)
	var d := rel.normalized().dot(Vector2(sin(rad), -cos(rad)))
	if d > 0.3:
		return "급기측"
	if d < -0.3:
		return "배기측"
	return "측면"
