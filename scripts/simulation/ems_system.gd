class_name EmsSystem
extends RefCounted
## 구급대 현장처치·이송·인계 (SOP 400 구급 공통, 402 중증도 분류).
##   구조된 사람(밖으로 나온 요구조자)은 환자가 된다. 구조 때 상태로 중증도를 나눈다:
##     긴급(의식 잃음) / 응급(의식은 있지만 노출이 크거나 거동 불편) / 비응급
##   처치: 구급대 조가 환자 옆에서 정해진 시간 처치한다 (400-3.2). 긴급 환자는 처치가 늦으면 사망한다
##   이송: 처치한 환자를 구급차까지 들것으로 옮겨 태우면 출발한다 (400-3.3). 정해진 시간 뒤 병원 인계 (400-3.4)
##   구급차와 함께 간 대원은 인계 후 복귀할 때까지 현장에 없다 (400-4)

enum Triage { URGENT, EMERGENT, MINOR }
enum Stage { WAITING, TREATING, TREATED, CARRYING, AWAY, HANDED }

const TRIAGE_NAMES := {Triage.URGENT: "긴급", Triage.EMERGENT: "응급", Triage.MINOR: "비응급"}
const TRIAGE_COLORS := {Triage.URGENT: Color("ef4444"), Triage.EMERGENT: Color("facc15"), Triage.MINOR: Color("22c55e")}
const STAGE_NAMES := {
	Stage.WAITING: "처치 대기", Stage.TREATING: "처치 중", Stage.TREATED: "처치 완료",
	Stage.CARRYING: "구급차로 옮기는 중", Stage.AWAY: "이송 중", Stage.HANDED: "병원 인계",
}


class Patient:
	extends RefCounted
	var victim_id := 0
	var triage := Triage.MINOR
	var stage := Stage.WAITING
	var crew_id := -1
	var treat_left := 0.0
	var treat_start_tick := -1
	var treated_tick := -1
	var depart_tick := -1
	var handover_tick := -1
	var vehicle_id := -1
	## 이송이 끝나면 처치 완료 후 자동으로 이송할지 (입문 자동화)
	var auto_transport := false


var units: UnitSystem
var rescue: RescueSystem
var pathfinder: Pathfinder
var events: SimEventLog
var patients: Array[Patient] = []
## 처치 완료 뒤 자동 이송 (TacticalSystem 자동화 수준 입문이면 true)
var auto_transport := true
var hospital := "인근 응급의료기관"
## 구급차 id -> 복귀 tick
var returning: Dictionary = {}

var _treat_s: Dictionary
var _critical_s: float
var _transport_s: float
var _return_s: float
var _carry_factor: float


func _init(p_units: UnitSystem, p_rescue: RescueSystem, p_pathfinder: Pathfinder, params: ParamTable, p_events: SimEventLog) -> void:
	units = p_units
	rescue = p_rescue
	pathfinder = p_pathfinder
	events = p_events
	_treat_s = {
		Triage.URGENT: params.value("treat_urgent_s"),
		Triage.EMERGENT: params.value("treat_emergent_s"),
		Triage.MINOR: params.value("treat_minor_s"),
	}
	_critical_s = params.value("urgent_untreated_death_s")
	_transport_s = params.value("transport_s")
	_return_s = params.value("return_s")
	_carry_factor = params.value("stretcher_speed_factor")


func apply_scenario(data: Dictionary) -> void:
	hospital = str(data.get("ems", {}).get("hospital", hospital))


func is_ems_crew(crew_id: int) -> bool:
	var s := units.squad_of_crew(crew_id)
	return s != null and s.type == "구급대"


func patient_of(victim_id: int) -> Patient:
	for p in patients:
		if p.victim_id == victim_id:
			return p
	return null


## 그 조가 맡은 환자 (없으면 null)
func patient_of_crew(crew_id: int) -> Patient:
	for p in patients:
		if p.crew_id == crew_id and p.stage in [Stage.TREATING, Stage.TREATED, Stage.CARRYING]:
			return p
	return null


func waiting_count() -> int:
	var n := 0
	for p in patients:
		if p.stage == Stage.WAITING and rescue.victims[p.victim_id].state == Victim.State.RESCUED:
			n += 1
	return n


## 밖에 있는 환자 중 p(셀 좌표)에서 radius 안에 가장 가까운 환자 victim id (-1: 없음)
func patient_near(p: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius
	for pt in patients:
		var v := rescue.victims[pt.victim_id]
		if not on_scene(pt) or v.carried_by >= 0:
			continue
		var d := v.pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = v.id
	return best


## 현장에 보이는 환자인가 (이송 전, 사망 전)
func on_scene(p: Patient) -> bool:
	return p.stage in [Stage.WAITING, Stage.TREATING, Stage.TREATED, Stage.CARRYING] and rescue.victims[p.victim_id].state == Victim.State.RESCUED


func triage_name(p: Patient) -> String:
	return TRIAGE_NAMES[p.triage]


## 처치 명령: 구급대 조가 환자에게 가서 처치한다
func order_treat(crew_id: int, victim_id: int, tick: int) -> bool:
	var p := patient_of(victim_id)
	var c := units.get_crew(crew_id)
	if p == null or c == null or not is_ems_crew(crew_id) or not on_scene(p) or p.stage != Stage.WAITING:
		return false
	cancel(crew_id)
	p.crew_id = crew_id
	p.stage = Stage.TREATING
	p.treat_left = _treat_s[p.triage]
	p.auto_transport = auto_transport
	_go_near(c, rescue.victims[victim_id].pos)
	events.add(tick, "ems_treat_order", {"crew": _crew_name(c), "who": rescue.victims[victim_id].label(), "triage": triage_name(p)})
	return true


## 이송 명령: 처치한 환자를 그 출동대의 구급차로 옮겨 태운다
func order_transport(crew_id: int, victim_id: int, tick: int) -> bool:
	var p := patient_of(victim_id)
	var c := units.get_crew(crew_id)
	if p == null or c == null or not is_ems_crew(crew_id) or p.stage != Stage.TREATED:
		return false
	var amb := _ambulance_of(c.squad_id)
	if amb == null:
		events.add(tick, "ems_no_ambulance", {"crew": _crew_name(c)})
		return false
	if p.crew_id != crew_id:
		cancel(crew_id)
	p.crew_id = crew_id
	_start_carry(p, c, amb, tick)
	return true


## 다른 명령을 받으면 처치·이송을 그만둔다 (처치 중이면 환자는 다시 처치 대기)
func cancel(crew_id: int) -> void:
	for p in patients:
		if p.crew_id != crew_id:
			continue
		match p.stage:
			Stage.TREATING:
				p.stage = Stage.WAITING
				p.crew_id = -1
			Stage.CARRYING:
				p.stage = Stage.TREATED
				rescue.victims[p.victim_id].carried_by = -1
				for ff in units.get_crew(crew_id).members():
					ff.carry_factor = 1.0
			Stage.TREATED:
				p.crew_id = -1


func step(dt: float, tick: int) -> void:
	_admit(tick)
	for p in patients:
		var v := rescue.victims[p.victim_id]
		if v.state != Victim.State.RESCUED:
			continue
		match p.stage:
			Stage.WAITING:
				_deteriorate(p, v, tick)
			Stage.TREATING:
				_deteriorate(p, v, tick)
				if v.state == Victim.State.RESCUED:
					_step_treat(p, v, dt, tick)
			Stage.CARRYING:
				_step_carry(p, v, tick)
			Stage.AWAY:
				if p.handover_tick < 0 and tick >= p.depart_tick + roundi(_transport_s / SimClock.TICK_DT):
					p.stage = Stage.HANDED
					p.handover_tick = tick
					events.add(tick, "ems_handover", {"who": v.label(), "hospital": hospital, "triage": triage_name(p)})
	for vid: int in returning.keys():
		if tick >= returning[vid]:
			_return(units.get_vehicle(vid), tick)
			returning.erase(vid)


# --- 내부 ---

## 새로 구조된 사람을 환자로 등록하고 중증도를 나눈다 (402 중증도 분류)
func _admit(tick: int) -> void:
	for v in rescue.victims:
		if v.state != Victim.State.RESCUED or patient_of(v.id) != null:
			continue
		var p := Patient.new()
		p.victim_id = v.id
		if v.state_at_rescue == Victim.State.UNCONSCIOUS:
			p.triage = Triage.URGENT
		elif v.fed() >= 0.3 or v.mobility.contains("불편") or v.age >= 75:
			p.triage = Triage.EMERGENT
		patients.append(p)
		events.add(tick, "ems_triage", {"who": v.label(), "triage": triage_name(p)})


## 긴급 환자는 처치가 늦으면 사망한다 (처치를 시작하면 멈춘다)
func _deteriorate(p: Patient, v: Victim, tick: int) -> void:
	if p.triage != Triage.URGENT or p.treat_start_tick >= 0:
		return
	if (tick - v.rescued_tick) * SimClock.TICK_DT >= _critical_s:
		v.state = Victim.State.DEAD
		events.add(tick, "victim_state", {"who": v.label(), "state": Victim.STATE_NAMES[Victim.State.DEAD], "reason": "구조 후 응급처치 지연"})


func _step_treat(p: Patient, v: Victim, dt: float, tick: int) -> void:
	var c := units.get_crew(p.crew_id)
	if c.leader.incapacitated:
		cancel(p.crew_id)
		return
	if c.leader.is_moving():
		return
	if c.leader.pos.distance_to(v.pos) > 2.0:
		_go_near(c, v.pos)
		return
	if p.treat_start_tick < 0:
		p.treat_start_tick = tick
		events.add(tick, "ems_treat_start", {"crew": _crew_name(c), "who": v.label(), "triage": triage_name(p)})
	p.treat_left -= dt
	if p.treat_left > 0.0:
		return
	p.stage = Stage.TREATED
	p.treated_tick = tick
	events.add(tick, "ems_treated", {"crew": _crew_name(c), "who": v.label(), "triage": triage_name(p), "auto": p.auto_transport})
	if p.auto_transport:
		var amb := _ambulance_of(c.squad_id)
		if amb:
			_start_carry(p, c, amb, tick)


func _start_carry(p: Patient, c: Crew, amb: Vehicle, tick: int) -> void:
	var v := rescue.victims[p.victim_id]
	p.stage = Stage.CARRYING
	p.vehicle_id = amb.id
	v.carried_by = c.id
	for ff in c.members():
		ff.carry_factor = _carry_factor
	_go_near(c, amb.closest_body_point(c.leader.pos))
	events.add(tick, "ems_carry", {"crew": _crew_name(c), "who": v.label()})


func _step_carry(p: Patient, v: Victim, tick: int) -> void:
	var c := units.get_crew(p.crew_id)
	var amb := units.get_vehicle(p.vehicle_id)
	v.pos = c.leader.pos
	if c.leader.pos.distance_to(amb.closest_body_point(c.leader.pos)) <= 3.0:
		_depart(p, v, c, amb, tick)
	elif not c.leader.is_moving():
		_go_near(c, amb.closest_body_point(c.leader.pos))


## 환자를 태우고 출발: 구급차와 그 조는 인계 후 복귀할 때까지 현장에 없다
func _depart(p: Patient, v: Victim, c: Crew, amb: Vehicle, tick: int) -> void:
	v.carried_by = -1
	p.stage = Stage.AWAY
	p.depart_tick = tick
	amb.away = true
	amb.moving = false
	for ff in c.members():
		ff.carry_factor = 1.0
		ff.aboard = true
		ff.path.clear()
		ff.pos = amb.pos
		ff.prev_pos = ff.pos
	returning[amb.id] = tick + roundi((_transport_s + _return_s) / SimClock.TICK_DT)
	events.add(tick, "ems_depart", {"crew": _crew_name(c), "who": v.label(), "triage": triage_name(p), "hospital": hospital, "driver": amb.driver_label()})


func _return(amb: Vehicle, tick: int) -> void:
	amb.away = false
	var squad := units.squads[amb.squad_id]
	for c in squad.crews:
		for i in c.members().size():
			var ff := c.members()[i]
			if ff.aboard:
				ff.aboard = false
				var spot := pathfinder.nearest_walkable(1, Vector2i((amb.pos + Vector2(0, 3 + i)).floor()))
				if spot != Pathfinder.NO_CELL:
					ff.pos = Vector2(spot) + Vector2(0.5, 0.5)
				ff.prev_pos = ff.pos
	events.add(tick, "ems_returned", {"squad": squad.name})


func _go_near(c: Crew, p: Vector2) -> void:
	var spot := pathfinder.nearest_walkable(1, Vector2i(p.floor()))
	if spot != Pathfinder.NO_CELL:
		units.order_move([c.id] as Array[int], Vector3i(spot.x, spot.y, 1), pathfinder)


func _ambulance_of(squad_id: int) -> Vehicle:
	for v in units.vehicles_of_squad(squad_id):
		if v.type == "구급차" and not v.away:
			return v
	return null


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]
