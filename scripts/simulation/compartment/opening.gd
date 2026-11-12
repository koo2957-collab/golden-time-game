class_name Opening
extends RefCounted
## 구획 사이 또는 구획과 외부 사이의 개구부 (문·창·계단).

enum Kind { DOOR, WINDOW, STAIR }

const OUTSIDE := -1

var index := 0
var kind := Kind.DOOR
var level := 1
var cells: Array[Vector2i] = []
var room_a := OUTSIDE
var room_b := OUTSIDE
var width := 0.0
## 바닥에서 개구부 하단·상단까지의 높이 (m)
var sill := 0.0
var top := 0.0
## 계단 개구부 면적 (m²)
var area := 0.0
var is_open := true
var broken := false
## 창이 열에 깨질 수 있는지 (방범창·강화유리 등은 false)
var breakable := true
## 잠긴 문 (파괴해야 열린다) / 파괴된 문 (다시 닫을 수 없다)
var locked := false
var forced := false
## 도어체크가 걸려 있다 (세대 변형, P2-2) — 안에 사람이 있다는 단서
var door_check := false


var _center := Vector2(-1, -1)


## 개구부 가운데 (셀 좌표)
func center() -> Vector2:
	if _center.x < 0.0 and not cells.is_empty():
		var s := Vector2.ZERO
		for c in cells:
			s += Vector2(c) + Vector2(0.5, 0.5)
		_center = s / cells.size()
	return _center


func height() -> float:
	return top - sill


## 개구 인자 A√H. 계단은 수직 개구부이므로 면적을 그대로 쓴다.
func ah() -> float:
	if kind == Kind.STAIR:
		return area
	return width * height() * sqrt(height())


## 닫힌 문은 틈새 누설값을 쓴다. 깨지지 않은 창은 막힌 것으로 본다.
func effective_ah(closed_leak: float) -> float:
	if is_open:
		return ah()
	return closed_leak if kind == Kind.DOOR else 0.0


func other_side(room: int) -> int:
	return room_b if room == room_a else room_a


func kind_name() -> String:
	return ["문", "창", "계단"][kind]
