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
## 이번 틱에 관창에서 실제로 물이 나갔는가 (WaterSystem._apply_sprays). flowing 은 '방수하라는 지시'라서 방수 위치로 가는 중·
## 충수 전·다른 층·물 끊김에도 참이다 — 물줄기 그림·엄호·경계 판정은 이 값을 본다 (2026-11-24: 걸어가는 조에서 예전 자리로
## 물줄기가 계속 그려져 '사람은 앞을 보는데 물은 옆으로' 나갔다)
var spraying := false
## 경계 관창 (2026-11-24): 바깥 지상에 서서 건물의 창·외벽(target — 위층일 수 있다)으로 올려 쏜다. 건물 안으로 들어가지 않는다.
## 유리는 깨지 않는다 — 열려 있거나 깨진 창이면 물이 안으로 들어가고, 아니면 겉만 적셔 식힌다 (연소확대 방지)
var exterior := false
## 관창을 배치만 해 두었다 — 방수 위치에서 겨눈 채 잠가 두고, 겨눈 곳이 달궈지거나 불꽃이 나오면 연다 (TacticalSystem._step_exterior)
var standby := false
## 방수 위치로 이동 중 (도착하면 물을 쏘기 시작)
var approaching := false
## 보이는 화점이 없을 때 다음으로 전진 위치를 찾을 틱
var next_advance_tick := 0
## 지난 전진 시도를 시작한 칸과 잇따른 헛걸음 수 (2026-11-27): 전진을 지시했는데 제자리면(열기에 막힘·갈 길 없음) 다음 시도를 늦춘다 —
## 5초마다 방수 대형이 풀렸다 다시 서는 것을 막는다
var advance_from := Vector3i(-1, -1, -1)
var advance_fails := 0
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
## 관창을 그 자리에 놓고 떠났다 (2026-11-24 사용자 결정 — 긴급 철수·공기호흡기 교체): 호스는 깔린 그대로, 관창은 points 끝에.
## crew_id 는 놓고 간 조 (교대조가 이어받으면 그 조로 바뀐다)
var dropped := false
## 놓인 관창으로 호스를 따라 가는 중 (닿으면 다시 잡는다 — 교체 뒤 재진입 · 교대조 인수)
var to_nozzle := false
## 철수하며 호스를 거두는 중 (관창 쪽부터 걷으며 펌프차로 돌아간다. 다 거두면 수관이 없어진다)
var recovering := false
## 관창으로 가기·거두기를 시작한 틱 (정한 시간 안에 못 하면 놓인 수관으로 되돌린다)
var detach_tick := -1


## 조가 손에 들고 있는 수관인가 (놓고 갔거나 관창으로 가는 중·거두는 중이면 아니다)
func held() -> bool:
	return not dropped and not to_nozzle and not recovering


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
