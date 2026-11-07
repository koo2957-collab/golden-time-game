class_name ViewProjection
extends RefCounted
## 셀 좌표(x, y)와 높이(m) ↔ 월드 화면 좌표 변환.
## 상황판(평면도)과 입체(아이소메트릭) 화면이 각각 구현하고, 선택·이동·카메라는 이것만 사용한다.

## 대원을 클릭으로 고를 때 기준이 되는 높이 (m)와 허용 반경 (px)
var pick_height_m := 0.0
var pick_radius_px := 14.0


func to_screen(_cell_pos: Vector2, _height_m := 0.0) -> Vector2:
	return Vector2.ZERO


## 화면 좌표를 바닥 높이의 셀 좌표로 되돌린다.
func to_cell(_world_pos: Vector2) -> Vector2:
	return Vector2.ZERO


## 화면 좌표를 높이 height_m인 면 위의 셀 좌표로 되돌린다 (입체 화면에서 차량 지붕을 클릭할 때 등).
func to_cell_at(world_pos: Vector2, _height_m: float) -> Vector2:
	return to_cell(world_pos)


## 건물 전체가 화면에서 차지하는 범위 (카메라 이동 제한용)
func bounds(building: BuildingData) -> Rect2:
	var corners: Array[Vector2] = [
		Vector2(0, 0), Vector2(building.width, 0),
		Vector2(0, building.height), Vector2(building.width, building.height),
	]
	var rect := Rect2(to_screen(corners[0]), Vector2.ZERO)
	for c in corners:
		rect = rect.expand(to_screen(c)).expand(to_screen(c, 2.4))
	return rect
