class_name Crew
extends RefCounted
## 조. 선택과 명령의 기본 단위이다.
## 분대가 조 하나로 같이 움직이거나(3~4명), 2인 1조로 나뉜다 (2026-11-16 결정 — docs/decisions.md '분대').
## 교재의 2인 1조(SOP 201-3.7)는 "혼자 들어가지 마라"는 최소 기준이라 조원은 1~4명이 될 수 있다.
## 선두(leader)가 경로를 따라가고 나머지는 그 뒤를 줄지어 따른다.

var id := 0
var squad_id := 0
## 출동대 안에서의 조 번호 (1부터)
var number := 1
## 조원 (선두부터). 예전 편성은 [조장, 짝]
var list: Array[Firefighter] = []
## 선두 = 조원 첫째 (경로를 따라가는 사람)
var leader: Firefighter:
	get:
		return list[0] if not list.is_empty() else null
## 짝 = 조원 둘째 (없으면 null). 예전 2인 1조 코드가 쓴다
var partner: Firefighter:
	get:
		return list[1] if list.size() > 1 else null
## 열화상카메라 휴대 (조장이 사용)
var thermal_camera := false
## 휴대 장비 키 (data/units/equipment.json — 기본 휴대 + 출동 준비판에서 챙긴 것, P4-1)
var items: Array[String] = []


func has_item(key: String) -> bool:
	return key in items


func members() -> Array[Firefighter]:
	return list.duplicate()
