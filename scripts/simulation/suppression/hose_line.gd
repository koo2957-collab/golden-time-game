class_name HoseLine
extends RefCounted
## 수관 한 줄: 펌프차에서 관창을 든 조(조장 = 관창수)까지 깔린 호스와 관창 상태.

enum Pattern { STRAIGHT, FOG, PENCIL, COVER }

const PATTERN_NAMES := {Pattern.STRAIGHT: "직사", Pattern.FOG: "분무", Pattern.PENCIL: "펜슬링·3D", Pattern.COVER: "엄호"}

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
## 물줄기가 닿는 곳(훑을 화점 또는 물이 퍼지는 자리)에 불꽃이 있던 마지막 틱 (-1 = 이번 방수에서는 아직 없음).
## 외부 방수 완료 판정에 쓴다 (TacticalSystem, 2026-11-18)
var flame_tick := -1
## 수관 준비·결합이 끝나는 틱 (기획안 6-1). 그때부터 운전원이 서서히 송수한다 (예비 송수)
var ready_tick := 0
## 물머리 위치 (펌프차 쪽 끝부터 잰 거리, 칸): 거기까지 물이 찼다. 펌프차 쪽부터 차오르며,
## 걸리는 시간 = 호스 안 부피 ÷ 송수량 (docs/motions.md D3, 2026-11-18 — 예전에는 길이와 상관없이 고정 10초)
var water_head := 0.0
## 물머리가 관창에 닿았는가 — 닿아야 방수가 된다. 한 번 찬 호스는 끌고 가도 차 있다
var charged := false
## 휴대 호스 한도를 넘어 차량에서 더 가져오는 중이면 끝나는 틱
var resupply_until := -1
var carried_loads := 1
## 수관을 시작할 곳으로 가는 중 (닿으면 거기서부터 깐다):
##   방수구 수관 = 호스 가방을 들고 방수구까지 (P9) / 펌프차 수관 = 호스를 꺼내러 펌프차 후면까지 (2026-11-21, docs/motions.md E1·D6)
var to_outlet := false
## 펌프차 후면에서 호스를 꺼내는 중이면 끝나는 틱 (-1 = 아님). 그동안 분대는 서 있다 (기획안 6-1 수관 준비 시간)
var fetch_until := -1
## 꺼내는 데 걸리는 전체 틱 (화면 진행 막대)
var fetch_ticks := 0


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
