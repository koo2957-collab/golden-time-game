class_name EquipmentCommand
extends RefCounted
## 차량·수관·방수 명령. action에 따라 WaterSystem의 해당 동작을 실행한다.
##   vehicle_move: 차량 이동 (target)
##   hydrant:      소화전 점령 (vehicle_id, other = 소화전 index)
##   supply:       물탱크차 급수 (vehicle_id = 물탱크차, other = 펌프차)
##   hose:         수관 연장 (crew_ids, vehicle_id = 펌프차)
##   spray:        방수 시작 (crew_ids, target, other = HoseLine.Pattern: 0 직사 / 1 분무)
##                 수관이 없으면 가까운 펌프차에서 자동 연장, 사거리 밖이면 다가가서 쏜다
##   stop:         방수 중지 (crew_ids)
##   door_open / door_close: 문 개방(잠긴 문은 파괴) / 폐쇄 (crew_ids, target = 문 셀). 창이면 깨서 배연
##   search:       인명검색 (crew_ids, target = 방 안 셀)
##   rescue / rescue_ff: 요구조자(other = 요구조자 id) / 쓰러진 대원(other = 대원 id) 구조 (crew_ids 중 첫 조)

var tick := -1
var action := ""
var crew_ids: Array[int] = []
var vehicle_id := -1
var other := -1
var target := Vector3i.ZERO


static func make(p_action: String, p_crew_ids: Array[int] = [], p_vehicle_id := -1, p_other := -1, p_target := Vector3i.ZERO) -> EquipmentCommand:
	var c := EquipmentCommand.new()
	c.action = p_action
	c.crew_ids = p_crew_ids.duplicate()
	c.vehicle_id = p_vehicle_id
	c.other = p_other
	c.target = p_target
	return c


func execute(sim: SimWorld) -> void:
	var w := sim.water
	match action:
		"vehicle_move":
			w.order_vehicle_move(vehicle_id, Vector2i(target.x, target.y), tick)
		"hydrant":
			w.connect_hydrant(vehicle_id, other, tick)
		"supply":
			w.connect_supply(vehicle_id, other, tick)
		"hose":
			for id in crew_ids:
				w.lay_hose(id, vehicle_id, tick)
		"spray":
			for id in crew_ids:
				sim.doors.cancel(id)
				sim.rescue.cancel(id)
				w.start_spray(id, target, other as HoseLine.Pattern, tick)
		"door_open", "door_close":
			for id in crew_ids:
				sim.rescue.cancel(id)
				sim.doors.request(id, target, action == "door_open", tick)
		"search":
			for id in crew_ids:
				sim.doors.cancel(id)
				sim.rescue.order_search(id, target, tick)
		"rescue", "rescue_ff":
			for id in crew_ids:
				sim.doors.cancel(id)
				if sim.rescue.order_rescue(id, "victim" if action == "rescue" else "ff", other, tick):
					break
		"stop":
			for id in crew_ids:
				w.stop_spray(id, tick)


func to_dict() -> Dictionary:
	return {
		"type": action,
		"tick": tick,
		"crews": crew_ids.duplicate(),
		"vehicle": vehicle_id,
		"other": other,
		"target": [target.x, target.y, target.z],
	}
