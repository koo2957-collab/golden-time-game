class_name TacticalCommand
extends RefCounted
## 분대 명령칸의 고수준 명령. TacticalSystem이 SOP 순서대로 여러 행동을 이어서 실행한다.
##   attack: 진압 (target = 방 안 셀) / exterior: 외부 방수 (target = 창·개구부)
##   search: 수색 (target = 방 안 셀) / withdraw: 그 조만 철수

var tick := -1
var action := ""
var crew_ids: Array[int] = []
var target := Vector3i.ZERO


static func make(p_action: String, p_crew_ids: Array[int], p_target := Vector3i.ZERO) -> TacticalCommand:
	var c := TacticalCommand.new()
	c.action = p_action
	c.crew_ids = p_crew_ids.duplicate()
	c.target = p_target
	return c


func execute(sim: SimWorld) -> void:
	for id in crew_ids:
		sim.rekindle.cancel(id)
		sim.gas.cancel(id)
		sim.ems.cancel(id)
		sim.tactical.order(action, id, target, tick)


func to_dict() -> Dictionary:
	return {
		"type": "tactical_" + action,
		"tick": tick,
		"crews": crew_ids.duplicate(),
		"target": [target.x, target.y, target.z],
	}
