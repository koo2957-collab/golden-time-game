class_name Victim
extends RefCounted
## 요구조자. 연기(독성)와 열 노출량이 쌓이면 의식을 잃고, 더 쌓이면 사망한다.
## 발견되기 전에는 지휘관 화면에 나타나지 않는다.

enum State { CONSCIOUS, UNCONSCIOUS, DEAD, RESCUED }

const STATE_NAMES := {
	State.CONSCIOUS: "의식 있음",
	State.UNCONSCIOUS: "의식 잃음",
	State.DEAD: "사망",
	State.RESCUED: "구조됨",
}

var id := 0
var name := ""
var age := 0
var mobility := ""
var level := 1
var pos := Vector2.ZERO
var state := State.CONSCIOUS
## 독성·열 노출량 (FED). 합이 1이면 의식 잃음
var fed_toxic := 0.0
var fed_heat := 0.0
var discovered := false
var discovered_tick := -1
## 업고 있는 조 (-1: 없음)
var carried_by := -1
## 구조될 때의 상태 (의식 있음·의식 잃음)
var state_at_rescue := State.CONSCIOUS
var rescued_tick := -1
## 구조해 내려놓은 곳 (P10-2 ⓒ): "환자 집결지"·"분류소"·"구급차 옆"·"입구"·"" (예전 방식: 출구 밖)
var dropoff := ""
## 입구에 두고 온 사람: 문으로 나오는 연기를 계속 마신다
var left_at_entrance := false
## 구조한 조 (분류 카드를 묻는 조)
var rescued_by := -1
## 창가에서 뛰어내릴 수 있는 사람 (시나리오 window: true, SOP 213-2.4.3)
var jumper := false
## 119에 전화할 수 있는가 (시나리오 victims[].phone, 기본 true). 의식이 있어야 건다
var phone := true
## 창에서 떨어졌음 (매트 착지 포함)
var fell := false
## 걸어서 스스로 대피할 수 있는 사람 (시나리오 self_evac: true, SOP 212-1.2)
var self_evac := false
## 화재를 알아차리는 시간 (초, 음수면 기본값 evac_alert_s)
var alert_s := -1.0


func fed() -> float:
	return fed_toxic + fed_heat


func alive() -> bool:
	return state == State.CONSCIOUS or state == State.UNCONSCIOUS


func state_name() -> String:
	if state == State.RESCUED:
		return "구조됨 (%s)" % STATE_NAMES[state_at_rescue]
	return STATE_NAMES[state]


func label() -> String:
	return "%s(%d)" % [name, age]
