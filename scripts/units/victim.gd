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
## 창가에서 뛰어내릴 수 있는 사람 (시나리오 window: true, SOP 213-2.4.3)
var jumper := false
## 창에서 떨어졌음 (매트 착지 포함)
var fell := false


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
