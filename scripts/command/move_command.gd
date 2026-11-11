class_name MoveCommand
extends RefCounted
## 이동 명령. 모든 지시는 명령 객체로 만들어 기록한다 (리플레이·평가·무전 지연의 기반).

var tick := -1
var crew_ids: Array[int] = []
var target := Vector3i.ZERO
## 지나갈 칸 (지휘관이 고른 계단). x < 0이면 가장 짧은 길
var via := Vector3i(-1, -1, -1)


func _init(p_crew_ids: Array[int], p_target: Vector3i, p_via := Vector3i(-1, -1, -1)) -> void:
	crew_ids = p_crew_ids.duplicate()
	target = p_target
	via = p_via


func execute(sim: SimWorld) -> void:
	for id in crew_ids:
		sim.doors.cancel(id)
		sim.rescue.cancel(id)
		sim.rekindle.cancel(id)
		sim.tactical.cancel(id)
		sim.gas.cancel(id)
		sim.ems.cancel(id)
		sim.falls.cancel(id)
		sim.vent.cancel(id, tick)
		sim.command.clear_floor_goal(id)
	sim.units.order_move(crew_ids, target, sim.pathfinder, via)


func to_dict() -> Dictionary:
	return {
		"type": "move",
		"tick": tick,
		"crews": crew_ids.duplicate(),
		"target": [target.x, target.y, target.z],
		"via": [via.x, via.y, via.z],
	}
