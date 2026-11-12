class_name FloorStack
extends RefCounted
## 인형집 단면 보기에서 어느 층을 어떻게 쌓아 보일지 정한다 (R17, 화면 계산만 — 시뮬레이션과 무관).
## - 지금 층과 그 아래 층(층 번호가 이어진 것만)을 쌓는다. 위층·지붕은 숨긴다.
## - 지금 층은 화면 높이 0에 두고 아래 층을 floor_height_px씩 아래로 그린다 (지금 층의 클릭 계산이 그대로다).
## - 벽: 바깥이 북·서쪽에 붙은 외벽(뒷벽, 카메라에서 먼 쪽)은 온전하게 세워 건물 모양을 남기고,
##   앞벽(남·동)과 실내 벽은 잘린 벽(또는 숨김)이다. 외부 보기에서는 외벽이 모두 온전하다.

## GLASS: 앞 바깥벽(남·동) 천장 높이 반투명 (front_wall = "glass") / HALF: 실내 벽 허리 높이 진한 벽
## OPEN: 앞 바깥벽 없음 — 인형집 (front_wall = "open", 2026-11-12). 문은 서 있고 창은 바닥 높이로 낮게
enum Wall { FULL, CUT, HIDDEN, GLASS, HALF, OPEN }

## 앞쪽 모서리 방향 (슬래브 단면 띠를 그리는 쪽)
const EDGE_SOUTH := 1
const EDGE_EAST := 2

const WALL_CELLS: Array[int] = [BuildingData.Cell.WALL, BuildingData.Cell.WINDOW, BuildingData.Cell.DOOR]

var building: BuildingData
var params: ViewParams
## 층 번호 오름차순 level 목록
var order: Array[int] = []
## 비켜 놓기(stagger): 위층을 건물 뒤쪽(북, 칸 -y)으로 보내는 화면 거리 (가장 깊은 층 깊이 × 비율)
var _back := Vector2.ZERO


func _init(p_building: BuildingData, p_params: ViewParams = null) -> void:
	building = p_building
	params = p_params if p_params != null else ViewParams.load_default()
	order = building.levels()
	order.sort_custom(func(a: int, b: int) -> bool: return building.floor_number(a) < building.floor_number(b))
	var deepest := 0.0
	for lv in order:
		deepest = maxf(deepest, building.footprint(lv).size.y)
	# 칸 -y 한 칸 = 화면 (+HALF_W, -HALF_H): 건물 앞면(A면, 남)에서 볼 때 '뒤로'
	_back = Vector2(IsoProjection.HALF_W, -IsoProjection.HALF_H) * deepest * params.stagger_back_ratio


## 비켜 놓기 모드인가 (2026-11-12 사용자 결정)
func staggered() -> bool:
	return params.stack_mode == "stagger"


## 함께 보일 짝 층: 바로 위층, 맨 위층이면 바로 아래층 (층 번호가 이어질 때만, 땅 위·아래를 섞지 않는다). 없으면 -1
func partner(current: int) -> int:
	if not building.has_level(current):
		return -1
	var n := building.floor_number(current)
	var up := level_of_number(n + 1)
	if up >= 0 and not (n <= -1 and n + 1 >= 1):
		return up
	var down := level_of_number(n - 1)
	if down >= 0 and not (n >= 1 and n - 1 < 1):
		return down
	return -1


## 지금 층부터 아래로 보일 층 목록 (첫 칸이 지금 층). 층 번호가 하나씩 이어질 때만 아래 층을 쌓는다
## (초고층의 생략된 층, 1층 밑의 지하층은 쌓지 않는다 — 땅에 가려 보이지 않는다)
func visible_levels(current: int) -> Array[int]:
	var result: Array[int] = [current]
	if not building.has_level(current):
		return result
	if staggered():
		# 비켜 놓기: 짝 층이 아래층일 때만 (맨 위층) 아래로 하나
		var pb := partner(current)
		if pb >= 0 and building.floor_number(pb) < building.floor_number(current):
			result.append(pb)
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
	if staggered():
		var pa := partner(current)
		if pa >= 0 and building.floor_number(pa) > building.floor_number(current):
			result.append(pa)
		return result
	var n := building.floor_number(current)
	for k in range(1, params.visible_floors_above + 1):
		var up := level_of_number(n + k)
		if up < 0 or (n <= -1 and n + k >= 1):
			break
		result.append(up)
	return result


## 위로 k층 떨어진 층을 그리는 화면 위치 (2026-11-12 사용자 결정 B): 층 높이만큼 위 + 건물 뒤쪽(북)으로 비켜서.
## 제자리 쌓기에서도 위층은 뒤로 비킨다 (아래층은 지금 층 바로 밑 — 가려지는 칸 계산이 수직 기준)
func upper_vec(k: int) -> Vector2:
	if staggered():
		return -offset_vec(k)
	return (Vector2(0, -params.floor_height_px) + _back) * k


## 보이는 위층들 위로 층이 더 이어지는가 (잘린 벽으로 알린다, 2026-11-12). 비켜 놓기에서는 쓰지 않는다
func more_above(current: int) -> bool:
	if staggered() or not building.has_level(current):
		return false
	var cnt := above_levels(current).size()
	if cnt == 0:
		return false
	var top := building.floor_number(current) + cnt
	return level_of_number(top + 1) >= 0 and not (top <= -1 and top + 1 >= 1)


## 보이는 아래층들 아래로 층이 더 이어지는가 (땅 밑으로는 잇지 않는다)
func more_below(current: int) -> bool:
	if staggered() or not building.has_level(current):
		return false
	var cnt := visible_levels(current).size() - 1
	if cnt <= 0:
		return false
	var low := building.floor_number(current) - cnt
	return level_of_number(low - 1) >= 0 and not (low >= 1 and low - 1 < 1)


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
## 비켜 놓기: 위층을 건물 뒤로 보내는 화면 거리 (층 높이는 빼고)
func back_vec() -> Vector2:
	return _back


func offset_px(depth: int) -> float:
	return absf(offset_vec(depth).y)


## 아래로 depth층 떨어진 층을 그리는 화면 위치 (위층은 음수 depth와 같은 -offset_vec).
## 비켜 놓기: 위층은 층 높이만큼 위 + 건물 뒤쪽으로 비켜 있으므로 아래층은 그 반대쪽(앞·아래)
func offset_vec(depth: int) -> Vector2:
	if staggered():
		return -(_back + Vector2(0, -params.stagger_floor_px)) * depth
	return Vector2(0, depth * params.floor_height_px)


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
	if params.front_wall == "open":
		return Wall.OPEN if outside != 0 else Wall.HALF
	if params.front_wall == "glass":
		return Wall.GLASS if outside != 0 else Wall.HALF
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
	# 비켜 놓기: 위층이 아래층 위에 그려지므로 겹친 곳은 위층이 먼저
	if staggered():
		for k in above_levels(current).size():
			var cu := Vector2i(proj.to_cell(world_pos - upper_vec(k + 1)).floor())
			if building.cell(above_levels(current)[k], cu.x, cu.y) in BuildingData.STRUCTURE:
				return above_levels(current)[k]
	var stack := visible_levels(current)
	for depth in stack.size():
		var lv: int = stack[depth]
		var c := Vector2i(proj.to_cell(world_pos - offset_vec(depth)).floor())
		var kind := building.cell(lv, c.x, c.y)
		if kind in BuildingData.STRUCTURE:
			return lv
		# 지금 층의 바깥 땅(지상층 도로·인도)도 지금 층이다
		if depth == 0 and kind != BuildingData.Cell.VOID:
			return lv
	# 위층: 지금 층·아래층 어디에도 걸리지 않는 곳에 보이는 위층 구조 (기획안 9-4: 그 층을 누르면 그 층으로)
	var above := above_levels(current)
	for k in above.size():
		var c := Vector2i(proj.to_cell(world_pos - upper_vec(k + 1)).floor())
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
