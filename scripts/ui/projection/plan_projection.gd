class_name PlanProjection
extends ViewProjection
## 상황판(평면도) 화면: 위에서 내려다본 좌표. 높이는 무시한다.


func _init() -> void:
	pick_height_m = 0.0
	pick_radius_px = 0.6 * PlanStyle.CELL_PX


func to_screen(cell_pos: Vector2, _height_m := 0.0) -> Vector2:
	return PlanStyle.to_px(cell_pos)


func to_cell(world_pos: Vector2) -> Vector2:
	return PlanStyle.to_cell(world_pos)
