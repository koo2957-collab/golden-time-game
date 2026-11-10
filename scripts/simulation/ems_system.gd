class_name EmsSystem
extends RefCounted
## 구급대 현장처치·이송·인계 (SOP 400 구급 공통, 402 중증도 분류).
##   구조된 사람(밖으로 나온 요구조자)은 환자가 된다. 구조 때 상태로 중증도를 나눈다:
##     긴급(의식 잃음) / 응급(의식은 있지만 노출이 크거나 거동 불편) / 비응급
##   처치: 구급대 조가 환자 옆에서 정해진 시간 처치한다 (400-3.2). 긴급 환자는 처치가 늦으면 사망한다
##   이송: 처치한 환자를 구급차까지 들것으로 옮겨 태우면 출발한다 (400-3.3). 정해진 시간 뒤 병원 인계 (400-3.4)
##   구급차와 함께 간 대원은 인계 후 복귀할 때까지 현장에 없다 (400-4)

enum Triage { URGENT, EMERGENT, MINOR, DELAYED }
enum Stage { WAITING, TREATING, TREATED, CARRYING, AWAY, HANDED }

const TRIAGE_NAMES := {Triage.URGENT: "긴급", Triage.EMERGENT: "응급", Triage.MINOR: "비응급", Triage.DELAYED: "지연"}
const TRIAGE_COLORS := {Triage.URGENT: Color("ef4444"), Triage.EMERGENT: Color("facc15"), Triage.MINOR: Color("22c55e"), Triage.DELAYED: Color("1f2937")}
## 자동 처치 순서 (분류표, -1 = 미분류는 응급 다음). 지연은 처치하지 않는다 (START)
const TAG_ORDER := {Triage.URGENT: 0, Triage.EMERGENT: 1, -1: 2, Triage.MINOR: 3}
const STAGE_NAMES := {
	Stage.WAITING: "처치 대기", Stage.TREATING: "처치 중", Stage.TREATED: "처치 완료",
	Stage.CARRYING: "구급차로 옮기는 중", Stage.AWAY: "이송 중", Stage.HANDED: "병원 인계",
}


class Patient:
	extends RefCounted
	var victim_id := 0
	## 실제 중증도 (START 기준, 화면에 보이지 않음): 처치 시간·악화에 쓴다
	var triage := Triage.MINOR
	## 분류한 중증도 (분류 카드 답 / 걸을 수 있으면 자동 비응급, -1 = 미분류): 자동 처치 순서·표시에 쓴다
	var tag := -1
	var tag_tick := -1
	## 분류 카드를 물었는가
	var asked := false
	## 처치 없이 지난 시간 (관찰 대원이 있으면 느리게 흐른다)
	var untreated_s := 0.0
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
## 분류소·환자 집결지 (P10-2 ⓒ): 분류소 근처에서 쉬는 구급대는 분류표 순서대로 알아서 처치한다
var zones: ZoneSystem
## 사망 판정 노출량 (RescueSystem과 같음 — '지연' 판단)
var fed_death := 1.0
## 구급차 id -> 복귀 tick
var returning: Dictionary = {}

var _treat_s: Dictionary
var _critical_s: float
var _transport_s: float
var _return_s: float
var _carry_factor: float
var _worsen_s := 900.0
var _observe_factor := 0.5
var _observe_cells := 4.0
var _start_rr := 30.0
var _start_crt := 2.0
var _urgent_fed := 0.6
var _delayed_ratio := 0.9
var _post_cells := 12.0


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
	_worsen_s = params.value("emergent_worsen_s")
	_observe_factor = params.value("observe_factor")
	var cell_m := rescue.fire.building.cell_size_m
	_observe_cells = params.value("observe_range_m") / cell_m
	_start_rr = params.value("start_rr_threshold")
	_start_crt = params.value("start_crt_s")
	_urgent_fed = params.value("start_urgent_fed")
	_delayed_ratio = params.value("start_delayed_fed_ratio")
	_post_cells = params.value("post_range_m") / cell_m


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
	p.treat_left = _treat_s.get(p.triage, _treat_s[Triage.URGENT])
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
	_auto_treat(tick)
	for p in patients:
		var v := rescue.victims[p.victim_id]
		if v.state != Victim.State.RESCUED:
			continue
		match p.stage:
			Stage.WAITING:
				_deteriorate(p, v, dt, tick)
			Stage.TREATING:
				_deteriorate(p, v, dt, tick)
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
		p.triage = start_category(v)
		patients.append(p)
		events.add(tick, "ems_triage", {"who": v.label(), "triage": triage_name(p)})
		# START 1단계: 걸을 수 있으면 비응급(녹색). 아니면 분류 카드로 묻는다 (구조자 운반을 쓰는 판만, P10-2 ⓒ)
		if not rescue.dropoff_enabled:
			continue
		if walking(v):
			p.tag = Triage.MINOR
			p.tag_tick = tick
			events.add(tick, "triage_auto", {"who": v.label()})
		else:
			p.asked = true
			events.add(tick, "triage_needed", {"who": v.label(), "victim_id": v.id, "crew_id": _asker(v), "crew": _asker_name(v),
				"clues": start_clues(v, p.triage), "verdict": ["urgent", "emergent", "minor", "delayed"][p.triage]})


## 처치를 받기 전 악화 (처치를 시작하면 멈춘다): 응급은 emergent_worsen_s 뒤 긴급으로, 긴급은 처치가 늦으면 사망.
## 곁에 대원이 서 있으면(구조자 관찰) 시간이 observe_factor만큼 느리게 흐른다 (P10-2 ⓒ, 게임 설정값)
func _deteriorate(p: Patient, v: Victim, dt: float, tick: int) -> void:
	if p.treat_start_tick >= 0 or p.triage in [Triage.MINOR, Triage.DELAYED]:
		return
	p.untreated_s += dt * (_observe_factor if observed(v) else 1.0)
	if p.triage == Triage.EMERGENT:
		if p.untreated_s >= _worsen_s:
			p.triage = Triage.URGENT
			p.untreated_s = 0.0
			v.state_at_rescue = Victim.State.UNCONSCIOUS
			events.add(tick, "victim_state", {"who": v.label(), "state": "상태 악화 (긴급)", "reason": "처치 지연"})
		return
	if p.untreated_s >= _critical_s:
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


# --- START 분류 (P10-2 ⓒ, 교재: 구급 START) ---

## 걸을 수 있는가 (START 1단계): 의식이 있고 노출이 적고 다치지 않았고 거동이 불편하지 않음
func walking(v: Victim) -> bool:
	return v.state_at_rescue == Victim.State.CONSCIOUS and v.fed() < 0.3 and not v.fell and not v.mobility.contains("불편") and v.age < 75


## 실제 중증도: 숨을 쉬지 않음 → 지연, 의식 없음·호흡 빠름(노출 큼) → 긴급, 걷지 못함 → 응급, 걸음 → 비응급
func start_category(v: Victim) -> int:
	if v.state_at_rescue == Victim.State.UNCONSCIOUS and v.fed() >= fed_death * _delayed_ratio:
		return Triage.DELAYED
	if v.state_at_rescue == Victim.State.UNCONSCIOUS or v.fed() >= _urgent_fed:
		return Triage.URGENT
	if walking(v):
		return Triage.MINOR
	return Triage.EMERGENT


## 분류 카드에 보이는 단서 (실제 중증도에서 만든다. 기준 호흡 30회·재충혈 2초는 교재)
func start_clues(v: Victim, category: int) -> String:
	var rr_hi := roundi(_start_rr) + 4
	match category:
		Triage.DELAYED:
			return "호흡 없음 — 기도를 열어도 숨을 쉬지 않음. 요골맥박 없음"
		Triage.URGENT:
			if v.state_at_rescue == Victim.State.UNCONSCIOUS:
				return "의식 없음, 호흡 %d회/분, 요골맥박 약함, 지시를 따르지 못함" % rr_hi
			return "호흡 %d회/분, 모세혈관 재충혈 %.0f초, 묻는 말에 겨우 대답" % [rr_hi - 2, _start_crt + 1.0]
		Triage.EMERGENT:
			return "걷지 못함, 호흡 %d회/분, 요골맥박 있음, 모세혈관 재충혈 %.1f초, 지시를 따름" % [roundi(_start_rr) - 8, _start_crt - 0.5]
	return "걸을 수 있음"


## 분류 카드 답 (CardSystem effect tag_urgent·tag_emergent·tag_minor·tag_delayed)
func set_tag(victim_id: int, tag: int, tick: int) -> void:
	var p := patient_of(victim_id)
	if p == null:
		return
	p.tag = tag
	p.tag_tick = tick
	events.add(tick, "triage_tagged", {"who": rescue.victims[victim_id].label(), "tag": TRIAGE_NAMES[tag]})


func tag_name(p: Patient) -> String:
	return TRIAGE_NAMES[p.tag] if p.tag >= 0 else "미분류"


## 화면에 보이는 분류 (실제 중증도는 숨긴다): 분류 카드를 쓰는 판은 고른 분류표, 아니면 예전처럼 자동 분류
func shown_name(p: Patient) -> String:
	return tag_name(p) if rescue.dropoff_enabled else triage_name(p)


func shown_color(p: Patient) -> Color:
	if not rescue.dropoff_enabled:
		return TRIAGE_COLORS[p.triage]
	return TRIAGE_COLORS[p.tag] if p.tag >= 0 else Color("94a3b8")


## 곁에 대원(조장)이 멈춰 서 있는가 — 구조자 관찰
func observed(v: Victim) -> bool:
	for c in units.crews:
		if c.leader.incapacitated or c.leader.aboard or c.leader.level != v.level or c.leader.is_moving():
			continue
		if c.leader.pos.distance_to(v.pos) <= _observe_cells:
			return true
	return false


## 분류 카드를 묻는 조: 현장 구급대 > 구조한 조
func _asker(v: Victim) -> int:
	for c in units.crews:
		if is_ems_crew(c.id) and not c.leader.aboard and not c.leader.incapacitated:
			return c.id
	return v.rescued_by


func _asker_name(v: Victim) -> String:
	var c := units.get_crew(_asker(v))
	return _crew_name(c) if c else "현장 대원"


## 분류소·집결지 근처에서 쉬는 구급대는 분류표 순서(긴급 → 응급 → 미분류 → 비응급, 지연 제외)로 알아서 처치한다
func _auto_treat(tick: int) -> void:
	if zones == null or zones.destination().x < 0:
		return
	var post := Vector2(zones.destination()) + Vector2(0.5, 0.5)
	for c in units.crews:
		if not is_ems_crew(c.id) or c.leader.aboard or c.leader.incapacitated or c.leader.is_moving():
			continue
		if patient_of_crew(c.id) != null or c.leader.pos.distance_to(post) > _post_cells:
			continue
		var best: Patient = null
		for p in patients:
			if p.stage != Stage.WAITING or not on_scene(p) or p.tag == Triage.DELAYED:
				continue
			if rescue.victims[p.victim_id].pos.distance_to(post) > _post_cells:
				continue
			if best == null or int(TAG_ORDER[p.tag]) < int(TAG_ORDER[best.tag]):
				best = p
		if best:
			order_treat(c.id, best.victim_id, tick)


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
