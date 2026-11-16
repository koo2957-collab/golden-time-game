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
## 다른 조에 합쳐져 비어 있으면 그 조 (UnitSystem.merge_squad). 이 조 id를 아직 들고 있는 곳이
## 선두를 물어도 합쳐진 조의 선두를 돌려준다 — 빈 조는 UnitSystem.crews 에 없다
var merged_into: Crew
## 선두 = 조원 첫째 (경로를 따라가는 사람)
var leader: Firefighter:
	get:
		if not list.is_empty():
			return list[0]
		return merged_into.leader if merged_into != null else null
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


## 팀장 (분대 지휘관). 없으면 null — 선착 분대는 팀장이 플레이어(선착대장)다
func officer() -> Firefighter:
	for ff in list:
		if ff.officer:
			return ff
	return null


## 무전·질문 카드로 말하는 사람: 팀장, 팀장이 없거나 쓰러졌으면 움직일 수 있는 첫 조원
func speaker() -> Firefighter:
	var o := officer()
	if o != null and not o.incapacitated:
		return o
	for ff in list:
		if not ff.incapacitated:
			return ff
	return leader


## 손으로 일하는 조원 (방수·문 개방·운반). 선두가 아닌 팀장은 옆에서 통솔하므로 뺀다 —
## 진압 분대는 관창수 + 관창보조 2명, 구조 분대는 팀장이 선두라 모두
func workers() -> Array[Firefighter]:
	var out: Array[Firefighter] = []
	for ff in list:
		if ff.officer and ff != leader:
			continue
		out.append(ff)
	return out


## 선두의 짝: 선두 다음으로 움직일 수 있는 일하는 조원 (운반의 뒷사람 등). 없으면 둘째 조원(null일 수 있다)
func mate() -> Firefighter:
	for ff in workers():
		if ff != leader and not ff.incapacitated:
			return ff
	return partner


## 둘째 짝 [앞, 뒤] — 4명 분대가 2인 1조 둘로 일할 때의 셋째·넷째 (구조대 두 짝 검색). 둘 다 움직일 수 있을 때만, 아니면 빈 배열
func second_pair() -> Array[Firefighter]:
	var out: Array[Firefighter] = []
	if list.size() >= 4 and not list[2].incapacitated and not list[3].incapacitated:
		out.append(list[2])
		out.append(list[3])
	return out


## 지금 움직일 수 있는 일하는 조원 수
func able_workers() -> int:
	var n := 0
	for ff in workers():
		if not ff.incapacitated:
			n += 1
	return n
