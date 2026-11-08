class_name Firefighter
extends RefCounted
## 대원 한 명. 위치는 셀 단위 좌표(셀 중심 = 정수 + 0.5)이다.

var id := 0
var name := ""
var rank := ""
var role := ""
var squad_id := 0
var crew_id := 0

var pos := Vector2.ZERO
var level := 1
## 직전 틱의 위치 (화면 보간용)
var prev_pos := Vector2.ZERO
var prev_level := 1
var path: Array[Vector3i] = []
## 이동 속도 배율 (수관을 끌면 느려지는 등)
var speed_factor := 1.0
## 자세 (연기층이 내려오면 낮은 자세: 느려지고 시선이 낮아진다)
var crouched := false
var crouch_factor := 1.0
## 요구조자·쓰러진 대원을 업고 있으면 느려진다
var carry_factor := 1.0

## 공기호흡기 잔량 / 용량 (L)
var air_l := 2040.0
var air_capacity := 2040.0
## 열 스트레스 (0~1, 1이면 행동 불능)
var heat_stress := 0.0
## 지금 받는 복사열 (kW/㎡)
var heat_flux := 0.0
## 행동 불능 (공기 소진·열 스트레스 한계)
var incapacitated := false
## 개성 (data/units/traits.json): 공기 소모·걷는 속도·열 스트레스 배율
var traits: Array[String] = []
var air_factor := 1.0
var trait_speed := 1.0
var heat_factor := 1.0
## 구급차에 타고 현장을 떠나 있음 (화면·선택에서 빠진다)
var aboard := false
var air_alarm_logged := false
## 출구까지 필요 공기(ℓ) — 건물 안에서만 계산 (R9)
var exit_air_l := 0.0
## "퇴각 건의"를 보고했는가 (밖에 나오면 다시 false)
var exit_air_logged := false
## 공기호흡기 교체 진행 시간 (초)
var swap_timer := 0.0


func air_ratio() -> float:
	return air_l / air_capacity if air_capacity > 0.0 else 0.0


func cell3() -> Vector3i:
	return Vector3i(floori(pos.x), floori(pos.y), level)


func is_moving() -> bool:
	return not path.is_empty()


func set_path(p_path: Array[Vector3i]) -> void:
	path = p_path.duplicate()


## 한 틱 동안 경로를 따라 이동한다. 경로의 층이 바뀌는 지점(계단)에서는 층을 전환한다.
func step(dt: float, speed_cells: float) -> void:
	prev_pos = pos
	prev_level = level
	if incapacitated:
		path.clear()
		return
	var budget := speed_cells * speed_factor * trait_speed * crouch_factor * carry_factor * dt
	while budget > 0.0 and not path.is_empty():
		var wp := path[0]
		if wp.z != level:
			level = wp.z
			path.pop_front()
			continue
		var target := Vector2(wp.x + 0.5, wp.y + 0.5)
		var d := pos.distance_to(target)
		if d <= budget:
			pos = target
			budget -= d
			path.pop_front()
		else:
			pos += (target - pos) / d * budget
			budget = 0.0
