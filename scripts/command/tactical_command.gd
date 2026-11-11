class_name TacticalCommand
extends RefCounted
## 분대 명령칸의 고수준 명령. TacticalSystem이 SOP 순서대로 여러 행동을 이어서 실행한다.
##   attack: 진압 (target = 방 안 셀) / exterior: 외부 방수 (target = 창·개구부)
##   search: 수색 (target = 방 안 셀) / withdraw: 그 조만 철수

var tick := -1
var action := ""
var crew_ids: Array[int] = []
var target := Vector3i.ZERO
## 진입구를 거쳐 가라 (P4-2 진입 지시): 그 진입구 바깥 칸. x < 0이면 없음 (가까운 문으로)
var via := Vector3i(-1, -1, -1)


static func make(p_action: String, p_crew_ids: Array[int], p_target := Vector3i.ZERO, p_via := Vector3i(-1, -1, -1)) -> TacticalCommand:
	var c := TacticalCommand.new()
	c.action = p_action
	c.crew_ids = p_crew_ids.duplicate()
	c.target = p_target
	c.via = p_via
	return c


func execute(sim: SimWorld) -> void:
	for id in crew_ids:
		sim.rekindle.cancel(id)
		sim.gas.cancel(id)
		sim.ems.cancel(id)
		sim.falls.cancel(id)
		sim.vent.cancel(id, tick)
		sim.command.clear_floor_goal(id)
		sim.tactical.order(action, id, target, tick, via)


func to_dict() -> Dictionary:
	return {
		"type": "tactical_" + action,
		"tick": tick,
		"crews": crew_ids.duplicate(),
		"target": [target.x, target.y, target.z],
		"via": [via.x, via.y, via.z],
	}
