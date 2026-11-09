class_name Vehicle
extends RefCounted
## 소방 차량 (펌프차·물탱크차). 위치는 차량 중심의 셀 좌표이다.
## 제자리에서 돌지 않는다: 차체 방향(heading) 그대로 전진·후진만 한다.
## 회전반경을 고려한 방향 전환은 교차로가 있는 지도에서 추가한다 (M8).

## 후진 속도 비율
const REVERSE_SPEED_FACTOR := 0.6

var id := 0
var type := ""
var short_name := ""
var squad_id := 0
var color := Color.WHITE

var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var level := 1
## 차량 앞쪽 방향 (셀 좌표계 단위 벡터)
var heading := Vector2.RIGHT
## 이동 목표 (차체 축 위의 점)
var goal := Vector2.ZERO
var moving := false
var reversing := false
var speed_cells := 5.0

## 차체 크기 (셀)
var length_cells := 14.0
var width_cells := 4.8
var height_m := 3.0

var tank_l := 0.0
var tank_capacity := 0.0
var nozzle_lpm := 0.0
## 65mm 관창(외부 방수) 방수량 (기획안 5-4)
var nozzle_65_lpm := 0.0
var transfer_lpm := 0.0
var hose_max_cells := 0.0

## 연결된 소화전 / 급수 중인 펌프차 (-1: 없음)
var hydrant := -1
var supply_to := -1
## 이동이 끝나면 연결할 대상
var pending_hydrant := -1
var pending_supply := -1
var tank_empty_logged := false
## 운전원 작업 (기획안 6-1 현장 작업 시간): {kind: hydrant|supply|fdc, label, remain, total, target, people}. 비어 있으면 없음
var work: Dictionary = {}
## 운전원 (기관원). 차량 명령은 운전원에게 내리는 지시다
var driver_name := ""
var driver_rank := ""
## 환자 이송 등으로 현장을 떠나 있음 (화면·선택에서 빠진다)
var away := false


func driver_label() -> String:
	return "%s %s" % [driver_rank, driver_name] if driver_name != "" else "운전원"


func display_name(squad_name: String) -> String:
	return "%s %s" % [squad_name, type]


func is_pump() -> bool:
	return nozzle_lpm > 0.0


func is_moving() -> bool:
	return moving


func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


## 차체 축 방향으로 distance(셀)만큼 이동을 시작한다. 음수면 후진.
func drive(distance: float) -> void:
	goal = pos + heading * distance
	reversing = distance < 0.0
	moving = absf(distance) > 0.001


func step(dt: float) -> void:
	prev_pos = pos
	if not moving:
		return
	var speed := speed_cells * (REVERSE_SPEED_FACTOR if reversing else 1.0)
	pos = pos.move_toward(goal, speed * dt)
	if pos.distance_to(goal) < 0.001:
		pos = goal
		moving = false
		reversing = false


## 차체 바닥의 네 모서리 (셀 좌표). 뒤-왼, 앞-왼, 앞-오, 뒤-오 순서.
func footprint(at: Vector2 = pos) -> PackedVector2Array:
	var f := heading * length_cells * 0.5
	var s := Vector2(-heading.y, heading.x) * width_cells * 0.5
	return PackedVector2Array([at - f - s, at + f - s, at + f + s, at - f + s])


func contains(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, footprint())


## 차체 바깥 둘레까지의 거리 (안에 있으면 0)
func distance_to_body(p: Vector2) -> float:
	if contains(p):
		return 0.0
	return p.distance_to(closest_body_point(p))


## p에서 가장 가까운 차체 둘레 위의 점
func closest_body_point(p: Vector2, at: Vector2 = pos) -> Vector2:
	var fp := footprint(at)
	var best := fp[0]
	for k in 4:
		var q := Geometry2D.get_closest_point_to_segment(p, fp[k], fp[(k + 1) % 4])
		if p.distance_squared_to(q) < p.distance_squared_to(best):
			best = q
	return best
