class_name FloorStack
extends RefCounted
## 인형집 단면 보기에서 어느 층을 어떻게 쌓아 보일지 정한다 (R17, 화면 계산만 — 시뮬레이션과 무관).
## - 지금 층과 그 아래 층(층 번호가 이어진 것만)을 쌓는다. 위층·지붕은 숨긴다.
## - 지금 층은 화면 높이 0에 두고 아래 층을 floor_height_px씩 아래로 그린다 (지금 층의 클릭 계산이 그대로다).
## - 벽: 바깥이 북·서쪽에 붙은 외벽(뒷벽, 카메라에서 먼 쪽)은 온전하게 세워 건물 모양을 남기고,
##   앞벽(남·동)과 실내 벽은 잘린 벽(또는 숨김)이다. 외부 보기에서는 외벽이 모두 온전하다.

enum Wall { FULL, CUT, HIDDEN }

## 앞쪽 모서리 방향 (슬래브 단면 띠를 그리는 쪽)
const EDGE_SOUTH := 1
const EDGE_EAST := 2

const WALL_CELLS: Array[int] = [BuildingData.Cell.WALL, BuildingData.Cell.WINDOW, BuildingData.Cell.DOOR]

var building: BuildingData
var params: ViewParams
## 층 번호 오름차순 level 목록
var order: Array[int] = []


func _init(p_building: BuildingData, p_params: ViewParams = null) -> void:
	building = p_building
	params = p_params if p_params != null else ViewParams.load_default()
	order = building.levels()
	order.sort_custom(func(a: int, b: int) -> bool: return building.floor_number(a) < building.floor_number(b))


## 지금 층부터 아래로 보일 층 목록 (첫 칸이 지금 층). 층 번호가 하나씩 이어질 때만 아래 층을 쌓는다
## (초고층의 생략된 층, 1층 밑의 지하층은 쌓지 않는다 — 땅에 가려 보이지 않는다)
func visible_levels(current: int) -> Array[int]:
	var result: Array[int] = [current]
	if not building.has_level(current):
		return result
	var n := building.floor_number(current)
	for depth in range(1, params.visible_floors_below + 1):
		var below := level_of_number(n - depth)
		if below < 0 or (n >= 1 and n - depth < 1):
			break
		result.append(below)
	return result


## 지금 층 위로 보일 층 목록 (가까운 층부터, 기획안 9-4: 위·아래 각 2개 층). 층 번호가 이어질 때만
func above_levels(current: int) -> Array[int]:
	var result: Array[int] = []
	if not building.has_level(current):
		return result
	var n := building.floor_number(current)
	for k in range(1, params.visible_floors_above + 1):
		var up := level_of_number(n + k)
		if up < 0 or (n <= -1 and n + k >= 1):
			break
		result.append(up)
	return result


## 층 번호로 level을 찾는다. 없으면 -1
func level_of_number(number: int) -> int:
	for lv in order:
		if building.floor_number(lv) == number:
			return lv
	return -1


## 지금 층에서 몇 층 아래인가 (0 = 지금 층). 보이지 않는 층은 -1
func depth_of(current: int, lv: int) -> int:
	return visible_levels(current).find(lv)


## 층의 화면 밝기 (지금 층 1.0, 아래로 갈수록 어둡게)
func modulate_for(depth: int) -> float:
	if depth <= 0:
		return 1.0
	if params.below_modulate.is_empty():
		return 1.0
	return params.below_modulate[mini(depth, params.below_modulate.size()) - 1]


## 층을 화면에서 아래로 내려 그리는 거리 (px)
func offset_px(depth: int) -> float:
	return depth * params.floor_height_px


## 벽 칸의 모양. exterior면 외부 보기(외벽 모두 온전)
func wall_kind(lv: int, x: int, y: int, exterior := false) -> int:
	if not building.cell(lv, x, y) in WALL_CELLS:
		return Wall.HIDDEN
	var outside := _outside_dirs(lv, x, y)
	if exterior and outside != 0:
		return Wall.FULL
	# 북(1)·서(2)에 바깥이 붙은 벽 = 뒷벽
	if outside & 3:
		return Wall.FULL
	return Wall.HIDDEN if params.front_wall == "hidden" else Wall.CUT


## 바깥에 닿은 뒷벽(북·서)인가
func is_back_wall(lv: int, x: int, y: int) -> bool:
	return building.cell(lv, x, y) in WALL_CELLS and (_outside_dirs(lv, x, y) & 3) != 0


## 앞쪽(남·동)이 바깥에 닿은 구조물 칸이면 그 방향 (EDGE_SOUTH | EDGE_EAST). 슬래브 단면 띠를 그릴 곳
func front_edge(lv: int, x: int, y: int) -> int:
	if not building.cell(lv, x, y) in BuildingData.STRUCTURE:
		return 0
	var outside := _outside_dirs(lv, x, y)
	var edge := 0
	if outside & 4:
		edge |= EDGE_SOUTH
	if outside & 8:
		edge |= EDGE_EAST
	return edge


## lower 층과 upper 층이 같은 자리에 모두 계단인 칸 (계단이 층 사이로 이어지는 곳)
func stair_links_between(lower: int, upper: int) -> Array[Vector2i]:
	var links: Array[Vector2i] = []
	if not (building.has_level(lower) and building.has_level(upper)):
		return links
	for y in building.height:
		for x in building.width:
			if building.cell(lower, x, y) == BuildingData.Cell.STAIRS and building.cell(upper, x, y) == BuildingData.Cell.STAIRS:
				links.append(Vector2i(x, y))
	return links


## 화면 위치(world_pos)를 눌렀을 때 맞은 층. 위층 바닥이 아래층을 가리므로 지금 층부터 본다.
## 아무 층에도 맞지 않으면 지금 층
func pick_level(current: int, world_pos: Vector2, proj: ViewProjection) -> int:
	var stack := visible_levels(current)
	for depth in stack.size():
		var lv: int = stack[depth]
		var c := Vector2i(proj.to_cell(world_pos - Vector2(0, offset_px(depth))).floor())
		var kind := building.cell(lv, c.x, c.y)
		if kind in BuildingData.STRUCTURE:
			return lv
		# 지금 층의 바깥 땅(지상층 도로·인도)도 지금 층이다
		if depth == 0 and kind != BuildingData.Cell.VOID:
			return lv
	# 위층: 지금 층·아래층 어디에도 걸리지 않는 곳에 보이는 위층 구조 (기획안 9-4: 그 층을 누르면 그 층으로)
	var above := above_levels(current)
	for k in above.size():
		var c := Vector2i(proj.to_cell(world_pos + Vector2(0, offset_px(k + 1))).floor())
		if building.cell(above[k], c.x, c.y) in BuildingData.STRUCTURE:
			return above[k]
	return current


## 바깥(OUTDOOR) 칸이 붙은 방향 비트: 북 1, 서 2, 남 4, 동 8
func _outside_dirs(lv: int, x: int, y: int) -> int:
	var bits := 0
	if building.cell(lv, x, y - 1) in BuildingData.OUTDOOR:
		bits |= 1
	if building.cell(lv, x - 1, y) in BuildingData.OUTDOOR:
		bits |= 2
	if building.cell(lv, x, y + 1) in BuildingData.OUTDOOR:
		bits |= 4
	if building.cell(lv, x + 1, y) in BuildingData.OUTDOOR:
		bits |= 8
	return bits
