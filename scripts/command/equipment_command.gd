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
##   overhaul:     잔불정리 (crew_ids, target = 방 안 셀, SOP 202-6)
##   shuttle:      물탱크차 순환보수 지정·해제 (vehicle_id, SOP 200-3.1.1.3)
##   fdc:          송수구 연결 (vehicle_id = 펌프차, SOP 200-3.3.1)
##   hose_outlet:  방수구에서 수관 연장 (crew_ids, other = 방수구 index)
##   air_mat:      공기안전매트 설치 (crew_ids 중 첫 구조대 조, target = 1층 바닥 칸, SOP 213-2.4.3)
##   gas_off:      가스 밸브 차단 (crew_ids 중 첫 조, SOP 214-2.2)
##   ems_treat:    구급대 응급처치 (crew_ids 중 첫 조, other = 요구조자 id, SOP 400-3.2)
##   ems_transport: 처치한 환자 이송 (crew_ids 중 첫 조, other = 요구조자 id, SOP 400-3.3)
##   monitor:      방수포 (vehicle_id = 펌프차, target = 바깥 창·문 칸, SOP 207-1.1) / monitor_stop: 방수포 중지
##   lifeline:     라이트라인 설치 (crew_ids 중 첫 조, target = 끝 칸, SOP 217)
##   elevator:     비상용승강기 (crew_ids, other = 내릴 층, SOP 222)
##   ppv:          송풍기 양압배연 (crew_ids 중 첫 조, target = 바깥 문 칸) / ppv_stop: 송풍기 끄기

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
		"fdc":
			w.connect_fdc(vehicle_id, tick)
		"shuttle":
			sim.shuttle.toggle(vehicle_id, tick)
		"lifeline":
			if not crew_ids.is_empty():
				sim.tactical.cancel(crew_ids[0])
				sim.lifeline.lay(crew_ids[0], target, tick)
		"elevator":
			for id in crew_ids:
				sim.tactical.cancel(id)
				sim.elevator.ride(id, other, tick)
		"monitor":
			sim.monitors.start(vehicle_id, target, tick)
		"monitor_stop":
			sim.monitors.stop(vehicle_id, tick)
		"ppv":
			if not crew_ids.is_empty():
				sim.doors.cancel(crew_ids[0])
				sim.rescue.cancel(crew_ids[0])
				sim.tactical.cancel(crew_ids[0])
				sim.vent.order(crew_ids[0], target, sim.pathfinder, tick)
		"ppv_stop":
			for id in crew_ids:
				sim.vent.cancel(id, tick)
		"hose_outlet":
			for id in crew_ids:
				w.lay_hose_outlet(id, other, tick)
		"spray":
			for id in crew_ids:
				sim.doors.cancel(id)
				sim.rescue.cancel(id)
				sim.rekindle.cancel(id)
				sim.tactical.cancel(id)
				w.start_spray(id, target, other as HoseLine.Pattern, tick)
		"door_open", "door_close":
			for id in crew_ids:
				sim.rescue.cancel(id)
				sim.rekindle.cancel(id)
				sim.tactical.cancel(id)
				sim.doors.request(id, target, action == "door_open", tick)
		"search":
			for id in crew_ids:
				sim.doors.cancel(id)
				sim.rekindle.cancel(id)
				sim.tactical.cancel(id)
				sim.rescue.order_search(id, target, tick)
		"rescue", "rescue_ff":
			for id in crew_ids:
				sim.doors.cancel(id)
				sim.tactical.cancel(id)
				if sim.rescue.order_rescue(id, "victim" if action == "rescue" else "ff", other, tick):
					break
		"overhaul":
			for id in crew_ids:
				sim.doors.cancel(id)
				sim.tactical.cancel(id)
				sim.rescue.cancel(id)
				sim.rekindle.order_overhaul(id, target, tick)
		"air_mat":
			for id in crew_ids:
				sim.doors.cancel(id)
				sim.rescue.cancel(id)
				sim.tactical.cancel(id)
				if sim.falls.order_mat(id, Vector2i(target.x, target.y), tick):
					break
		"gas_off":
			for id in crew_ids:
				sim.doors.cancel(id)
				sim.rescue.cancel(id)
				sim.tactical.cancel(id)
				if sim.gas.order_off(id, tick):
					break
		"triage_post":
			if not crew_ids.is_empty():
				sim.zones.order_triage(crew_ids[0], Vector2i(target.x, target.y), sim.pathfinder, tick)
		"ems_treat", "ems_transport":
			for id in crew_ids:
				sim.doors.cancel(id)
				sim.rescue.cancel(id)
				sim.tactical.cancel(id)
				var ok := sim.ems.order_treat(id, other, tick) if action == "ems_treat" else sim.ems.order_transport(id, other, tick)
				if ok:
					break
		"stop":
			for id in crew_ids:
				sim.tactical.cancel(id)
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
