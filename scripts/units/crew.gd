class_name Crew
extends RefCounted
## 2인 1조 (SOP 201-3.7). 선택과 명령의 기본 단위이다.
## 조장(leader)이 경로를 따라가고 짝(partner)은 바로 뒤를 따른다.

var id := 0
var squad_id := 0
## 출동대 안에서의 조 번호 (1부터)
var number := 1
var leader: Firefighter
var partner: Firefighter
## 열화상카메라 휴대 (조장이 사용)
var thermal_camera := false
## 휴대 장비 키 (data/units/equipment.json — 기본 휴대 + 출동 준비판에서 챙긴 것, P4-1)
var items: Array[String] = []


func has_item(key: String) -> bool:
	return key in items


func members() -> Array[Firefighter]:
	var out: Array[Firefighter] = [leader]
	if partner:
		out.append(partner)
	return out
