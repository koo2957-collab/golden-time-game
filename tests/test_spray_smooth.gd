extends TestSuite
## 방수 장면을 부드럽게 (2026-11-26 사용자: 방수 중 방향을 바꾸면 대원들이 순간이동하듯 자리가 바뀌고 물줄기가 이상하게 나간다).
## 화면 없이 계산만 본다: 방향 바꾸기의 여유(깜빡임 없음)와 관창보조 자리의 미끄러짐


func _layer(sim: SimWorld) -> Array:
	var sel := SelectionController.new()
	var layer := FloorLayer.new()
	layer.setup(sim, sel, IsoProjection.new())
	layer.level = 1
	return [layer, sel]


func _free(nodes: Array) -> void:
	for n: Node in nodes:
		n.free()


func _at_deg(deg: float) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(deg)) * 5.0


## 방향은 지금 칸(±22.5°)을 여유각(spray_turn_hysteresis_deg) 넘게 벗어나야 바뀐다 — 경계를 오가며 깜빡이지 않는다
func test_spray_direction_hysteresis() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var hyst := float(HoseDraw.style().get("spray_turn_hysteresis_deg", 10.0))
	assert_true(hyst > 0.0 and hyst < 22.5, "여유각 %.0f°" % hyst)
	var o := Vector2.ZERO
	assert_eq(layer._spray_k(7, o, _at_deg(0.0)), 0, "처음 = 겨눈 쪽")
	assert_eq(layer._spray_k(7, o, _at_deg(22.5 + hyst * 0.5)), 0, "경계를 조금 넘어도 그대로")
	assert_eq(layer._spray_k(7, o, _at_deg(22.5 + hyst + 3.0)), 1, "여유각을 넘으면 바뀐다")
	assert_eq(layer._spray_k(7, o, _at_deg(22.5 - hyst * 0.5)), 1, "되돌아와도 경계 근처에서는 그대로")
	assert_eq(layer._spray_k(7, o, _at_deg(5.0)), 0, "충분히 돌아오면 바뀐다")
	assert_eq(layer._spray_k(8, o, _at_deg(90.0)), 2, "조마다 따로 기억")
	_free(nodes)


## 관창보조 자리는 새 자리로 걸어서 옮겨 간다 (순간이동 없음). 멀리 떨어진 새 자리는 바로 선다
func test_helper_spots_glide() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var a := Vector2(10.0, 10.0)
	var first := {"spots": {5: a}}
	layer._glide_spots(first)
	assert_eq(first.spots[5], a, "처음은 그 자리")
	var near := a + Vector2(1.0, 0.0)
	var next := {"spots": {5: near}}
	layer._glide_spots(next)
	var step: Vector2 = next.spots[5]
	assert_true(step.distance_to(a) < 0.5, "새 자리로 한 번에 옮기지 않는다 (%.2f칸 움직임)" % step.distance_to(a))
	var snap_cells := float(HoseDraw.style().get("spray_regroup_snap_m", 3.0)) / sim.units.cell_size_m
	var far := a + Vector2(snap_cells + 2.0, 0.0)
	var jump := {"spots": {5: far}}
	layer._glide_spots(jump)
	assert_eq(jump.spots[5], far, "멀리 떨어진 새 자리(다른 곳 방수)는 바로 선다")
	_free(nodes)
