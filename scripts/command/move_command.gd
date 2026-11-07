class_name MoveCommand
extends RefCounted
## 이동 명령. 모든 지시는 명령 객체로 만들어 기록한다 (리플레이·평가·무전 지연의 기반).

var tick := -1
var crew_ids: Array[int] = []
var target := Vector3i.ZERO


func _init(p_crew_ids: Array[int], p_target: Vector3i) -> void:
	crew_ids = p_crew_ids.duplicate()
	target = p_target


func execute(sim: SimWorld) -> void:
	for id in crew_ids:
		sim.doors.cancel(id)
	sim.units.order_move(crew_ids, target, sim.pathfinder)


func to_dict() -> Dictionary:
	return {
		"type": "move",
		"tick": tick,
		"crews": crew_ids.duplicate(),
		"target": [target.x, target.y, target.z],
	}
