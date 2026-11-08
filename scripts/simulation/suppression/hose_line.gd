class_name HoseLine
extends RefCounted
## 수관 한 줄: 펌프차에서 관창을 든 조(조장 = 관창수)까지 깔린 호스와 관창 상태.

enum Pattern { STRAIGHT, FOG }

const PATTERN_NAMES := {Pattern.STRAIGHT: "직사", Pattern.FOG: "분무"}

var id := 0
var vehicle_id := 0
## 연결송수관 방수구에서 연장한 수관이면 방수구 index (-1: 펌프차에서)
var outlet := -1
var crew_id := 0
## 호스가 깔린 셀 (차량 쪽 → 관창 쪽)
var points: Array[Vector3i] = []
var max_cells := 0.0
var at_limit := false

var flowing := false
## 방수 위치로 이동 중 (도착하면 물을 쏘기 시작)
var approaching := false
## 보이는 화점이 없을 때 다음으로 전진 위치를 찾을 틱
var next_advance_tick := 0
var pattern := Pattern.STRAIGHT
var target := Vector3i.ZERO
## 이번 틱에 실제로 공급된 물의 비율 (0~1, 탱크가 비면 줄어듦)
var flow_fraction := 0.0
## 관창수가 겨누고 있는 지점 (셀 좌표). 목표 방 안의 화점을 따라 훑으며 움직인다.
var aim := Vector2.ZERO
## 물이 닿는 지점 (셀 좌표)과 벽 등에 막혔는지
var impact := Vector2.ZERO
var blocked := false


func pattern_name() -> String:
	return PATTERN_NAMES[pattern]


func length_cells() -> float:
	var total := 0.0
	for k in range(1, points.size()):
		var a := points[k - 1]
		var b := points[k]
		if a.z == b.z:
			total += Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y))
		else:
			total += 6.0  # 계단 한 층 (약 3m)
	return total
