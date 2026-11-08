class_name IsoProjection
extends ViewProjection
## 입체 화면 (45° 돌려 약 50° 내려다보는 정사영). 셀의 +x는 화면 오른쪽 아래, +y는 왼쪽 아래로 간다.
## 바닥 비율(HALF_H/HALF_W = sin 50°)과 높이 비율(PX_PER_M = 1m 바닥 길이 × cos 50°)을 같은 카메라로 맞춰
## 사람·차량·벽이 실제 비율로 보인다 (참고 화면: 약 50° 부감의 3/4 시점).
## 화면 아래쪽(x + y가 큰 쪽)이 보는 사람에게 가깝다.

## 셀 마름모의 가로·세로 절반 (px)
const HALF_W := 28.0
const HALF_H := 21.0
## 높이 1m의 화면 길이 (px)
const PX_PER_M := 51.0


func _init() -> void:
	pick_height_m = 0.9
	pick_radius_px = 18.0


func to_screen(cell_pos: Vector2, height_m := 0.0) -> Vector2:
	return Vector2((cell_pos.x - cell_pos.y) * HALF_W, (cell_pos.x + cell_pos.y) * HALF_H - height_m * PX_PER_M)


func to_cell_at(world_pos: Vector2, height_m: float) -> Vector2:
	return to_cell(world_pos + Vector2(0, height_m * PX_PER_M))


func to_cell(world_pos: Vector2) -> Vector2:
	var a := world_pos.x / HALF_W
	var b := world_pos.y / HALF_H
	return Vector2((a + b) * 0.5, (b - a) * 0.5)
