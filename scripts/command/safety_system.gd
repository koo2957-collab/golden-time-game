class_name SafetySystem
extends RefCounted
## 대원 안전 지휘 (2025 SOP 108·109, SSG 9).
##   긴급탈출 선언 (109-1.2): 대원이 쓰러지면 같은 조가 "긴급탈출"을 3회 송신한다. 조 전원이 쓰러지면 무응답으로 본다 (109-1.1)
##   무선 침묵 (109-1.2.3): 긴급탈출 상황에서는 대원 안전·구조대상자 외의 보고를 멈춘다 (CommandSystem이 확인)
##   긴급탈출 지시 (SSG 9 2.1.7, 109-1.3): 현장지휘관이 전 대원을 건물 밖으로 탈출시킨다
##   인원점검 (109-1.3, 200-4.1): 출동대·단위대별로 인원·장비 이상 유무를 무전으로 보고받는다
##   신속동료구조팀 RIT (SSG 9): 미리 지정한 조는 다른 임무를 받지 않고 밖에서 대기하다가 긴급탈출 상황에만 투입된다
##   현장안전담당 (108-1.4, 201-3.8, 214-2.5): 지정한 조는 밖에서 진입 대원 상태를 확인하고 공기가 부족해지기 전에 알린다

enum Role { NONE, RIT, OFFICER }
const ROLE_NAMES: Array[String] = ["", "신속동료구조팀(RIT)", "현장안전담당"]

var fire: FireSim
var units: UnitSystem
var pathfinder: Pathfinder
var rescue: RescueSystem
var water: WaterSystem
var doors: DoorSystem
var events: SimEventLog
## 지휘망 (CommandSystem.radio와 같은 채널)
var radio: Radio
var org: Organization
var resources: ResourceSystem
## 진입 허가 (CommandSystem.entry_allowed와 같은 사전 — 긴급탈출 지시 때 비운다)
var entry_allowed: Dictionary

## crew id -> Role
var roles: Dictionary = {}
## 투입된 RIT (crew id -> 투입 틱)
var deployed: Dictionary = {}
## 긴급탈출 상황 중인지, 시작 틱 (-1: 아님)
var emergency_tick := -1
## 평가용 기록
var mayday_log: Array[Dictionary] = []  # {tick, crew, cause, silent}
var evacuation_log: Array[int] = []  # 긴급탈출 지시가 전달된 틱
var par_log: Array[Dictionary] = []  # {tick, missing, indoor}
## 인원 점검에 정한 시간 안에 응답하지 않은 조 (P10-2: 무전 패널 맨 위 빨간 줄). 응답하거나 구출되면 빠진다
var par_no_response: Array[int] = []
var role_log: Array[Dictionary] = []  # {tick, crew, role}
var rit_deploy_log: Array[Dictionary] = []  # {tick, crew}
var suppressed_reports := 0
## 진입 금지 판단 요소(102-4.1 ⑧)를 '지금 있음'으로 보는 틱 수
var factor_recent_ticks := 1200

var _repeat: int
var _officer_ratio: float
var _officer_every: int
var _mayday_done: Dictionary = {}  # ff id -> true
var _officer_warned: Dictionary = {}  # ff id -> true
var _role_pending: Dictionary = {}  # crew id -> Role
var _par_deadline := -1
var _par_expect: Dictionary = {}  # crew id -> true (아직 응답하지 않은 조)
var _par_response_ticks := 600


func _init(p_fire: FireSim, p_units: UnitSystem, p_pathfinder: Pathfinder, p_rescue: RescueSystem, p_water: WaterSystem, p_doors: DoorSystem, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	pathfinder = p_pathfinder
	rescue = p_rescue
	water = p_water
	doors = p_doors
	events = p_events
	_repeat = roundi(params.value("mayday_repeat"))
	_officer_ratio = params.value("officer_air_ratio")
	_officer_every = maxi(1, roundi(params.value("officer_check_s") / SimClock.TICK_DT))
	factor_recent_ticks = roundi(params.value("entry_factor_recent_s") / SimClock.TICK_DT)
	_par_response_ticks = roundi(params.value("par_response_s") / SimClock.TICK_DT)


func emergency() -> bool:
	return emergency_tick >= 0


func role_of(crew_id: int) -> Role:
	return roles.get(crew_id, Role.NONE)


func role_pending(crew_id: int) -> bool:
	return _role_pending.has(crew_id)


## 밖에 머물러야 하는 조 (투입되지 않은 RIT, 현장안전담당)
func reserved(crew_id: int) -> bool:
	var r := role_of(crew_id)
	return r == Role.OFFICER or (r == Role.RIT and not deployed.has(crew_id))


func crews_with(role: Role) -> Array[int]:
	var out: Array[int] = []
	for id: int in roles:
		if roles[id] == role:
			out.append(id)
	out.sort()
	return out


func officer() -> int:
	var list := crews_with(Role.OFFICER)
	return list[0] if not list.is_empty() else -1


# --- 명령 ---

## 조에 안전 임무를 맡긴다 (무전). OFFICER는 한 조만, NONE이면 임무 해제
func order_role(crew_id: int, role: Role, sender: String, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	if c == null or role_of(crew_id) == role or _role_pending.has(crew_id):
		return false
	_role_pending[crew_id] = role
	var body := "%s 임무 해제, 원래 임무로 복귀하라." % ROLE_NAMES[role_of(crew_id)] if role == Role.NONE \
		else "%s로 지정한다. 다른 임무는 맡지 말고 지휘소 부근에서 대기하라." % ROLE_NAMES[role]
	if role == Role.OFFICER:
		body = "현장안전담당으로 지정한다. 진입 대원 상태와 위험요인을 확인하고 보고하라."
	radio.send(Radio.Priority.TACTICS, sender, _crew_name(c), body, tick, _on_role_received.bind(crew_id, role))
	return true


## 긴급탈출 지시: 전 대원 즉시 건물 밖으로 (대원 안전 우선순위)
func order_evacuation(sender: String, tick: int) -> void:
	var calls := ", ".join(PackedStringArray(_repeat_word()))
	radio.send(Radio.Priority.SAFETY, sender, "전 대원", "%s. 전 대원 즉시 건물 밖으로 탈출하라." % calls, tick, _on_evacuation_sent)


## 인원점검 지시: 출동대(단위대)별 인원·장비 이상 유무 보고
func order_par(sender: String, tick: int) -> void:
	radio.send(Radio.Priority.SAFETY if emergency() or not evacuation_log.is_empty() else Radio.Priority.TACTICS,
		sender, "각 출동대", "인원·장비 이상 유무 보고하라.", tick, _on_par_sent.bind(sender))


## RIT 투입 (긴급탈출 상황에서만). 투입하면 진입 제한이 풀린다
func deploy(crew_id: int, tick: int) -> bool:
	if role_of(crew_id) != Role.RIT or deployed.has(crew_id) or not emergency():
		return false
	deployed[crew_id] = tick
	rit_deploy_log.append({"tick": tick, "crew": crew_id})
	events.add(tick, "rit_deployed", {"crew": _crew_name(units.get_crew(crew_id)), "remaining": crews_with(Role.RIT).size() - deployed.size()})
	return true


## 건물 안의 조를 가장 가까운 열린 외부 문 밖으로 내보낸다 (운반 중인 조는 하던 대로 나온다)
func withdraw_all(tick: int, reason := "withdraw") -> void:
	for c in units.crews:
		if not _indoor(c.leader.level, c.leader.pos) or rescue.task_of_crew(c.id) is RescueSystem.CarryTask:
			continue
		withdraw_crew(c, tick, reason)


## 한 조를 가장 가까운 열린 외부 문 밖으로 내보낸다
func withdraw_crew(c: Crew, tick: int, reason := "withdraw") -> void:
	if not _indoor(c.leader.level, c.leader.pos):
		return
	var exits := rescue.exit_cells()
	doors.cancel(c.id)
	rescue.cancel(c.id)
	water.stop_spray(c.id, tick)
	var best := Vector3i(-1, -1, -1)
	var best_d := INF
	for e in exits:
		var d := c.leader.pos.distance_to(Vector2(e.x, e.y)) + absi(e.z - c.leader.level) * 100.0
		if d < best_d:
			best_d = d
			best = e
	if best.x < 0:
		events.add(tick, "exit_blocked", {"crew": _crew_name(c)})
		return
	units.order_move([c.id], _clear_of_building(best), pathfinder)
	events.add(tick, reason, {"crew": _crew_name(c)})


## 문 밖 칸에서 건물 반대쪽으로 몇 칸 더 나간 곳 (조장 뒤를 따르는 짝까지 완전히 밖에 서도록)
func _clear_of_building(exit: Vector3i) -> Vector3i:
	var rect := Rect2(fire.building.footprint(exit.z))
	var p := Vector2(exit.x, exit.y) + Vector2(0.5, 0.5)
	var away := (p - rect.get_center())
	away = Vector2(signf(away.x), 0.0) if absf(away.x) / rect.size.x > absf(away.y) / rect.size.y else Vector2(0.0, signf(away.y))
	for k in [3, 2, 1]:
		var q := Vector2i(exit.x, exit.y) + Vector2i(away * k)
		if pathfinder.passable(exit.z, q.x, q.y) and fire.building.cell(exit.z, q.x, q.y) in BuildingData.OUTDOOR:
			return Vector3i(q.x, q.y, exit.z)
	return exit


# --- 틱 ---

func step(tick: int) -> void:
	_check_mayday(tick)
	if emergency() and not _any_down_inside():
		emergency_tick = -1
		events.add(tick, "emergency_cleared", {})
		radio.send(Radio.Priority.SAFETY, CommandSystem.COMMANDER, CommandSystem.DISPATCH_CENTER, "대원 구출 완료, 긴급탈출 상황 해제.", tick)
	if tick % _officer_every == 0:
		_officer_check(tick)
	_check_par_deadline(tick)


## 쓰러진 대원이 생기면 같은 조가 긴급탈출을 선언한다. 조 전원이 쓰러졌으면 무응답 (109-1.1)
func _check_mayday(tick: int) -> void:
	for ff in units.firefighters:
		if not ff.incapacitated or _mayday_done.has(ff.id) or not _indoor(ff.level, ff.pos):
			continue
		_mayday_done[ff.id] = true
		var c := units.get_crew(ff.crew_id)
		var mate: Firefighter = null
		for m in c.members():
			if m != ff and not m.incapacitated:
				mate = m
		var room := fire.compartment_at(ff.level, floori(ff.pos.x), floori(ff.pos.y))
		var where := room.display_name() if room else fire.building.floor_name(ff.level)
		var silent := mate == null
		var started := not emergency()
		if started:
			emergency_tick = tick
			_silence_queue()
		mayday_log.append({"tick": tick, "crew": c.id, "cause": "대원 쓰러짐", "silent": silent})
		events.add(tick, "mayday", {"crew": _crew_name(c), "who": ff.name, "where": where, "silent": silent})
		if silent:
			radio.send(Radio.Priority.SAFETY, CommandSystem.COMMANDER, "전 대원",
				"%s 무전 응답 없음, 긴급탈출 상황. 위치 %s. 전 출동대 무선 침묵." % [_crew_name(c), where], tick)
		else:
			radio.send(Radio.Priority.SAFETY, _crew_name(c), CommandSystem.COMMANDER,
				"%s. %s 쓰러짐, 위치 %s. 구출 지원 필요." % [", ".join(PackedStringArray(_repeat_word())), ff.name, where], tick)


## 현장안전담당: 건물 안 대원의 공기가 기준 아래로 내려가면 경보 전에 알린다
func _officer_check(tick: int) -> void:
	var o := officer()
	if o < 0:
		return
	var oc := units.get_crew(o)
	if oc.leader.incapacitated or _indoor(oc.leader.level, oc.leader.pos):
		return
	for ff in units.firefighters:
		if ff.crew_id == o or _officer_warned.has(ff.id) or ff.incapacitated or not _indoor(ff.level, ff.pos):
			continue
		if ff.air_ratio() < _officer_ratio:
			_officer_warned[ff.id] = true
			var c := units.get_crew(ff.crew_id)
			events.add(tick, "officer_warning", {"crew": _crew_name(c), "who": ff.name, "air": roundi(ff.air_ratio() * 100.0)})
			radio.send(Radio.Priority.SAFETY, "현장안전담당", CommandSystem.COMMANDER,
				"%s %s 공기 %d%%, 교대·탈출 준비 필요." % [_crew_name(c), ff.name, roundi(ff.air_ratio() * 100.0)], tick)


# --- 무전 수신 ---

func _on_role_received(tick: int, crew_id: int, role: Role) -> void:
	_role_pending.erase(crew_id)
	var c := units.get_crew(crew_id)
	if role == Role.OFFICER:
		for id in crews_with(Role.OFFICER):
			roles.erase(id)
	if role == Role.NONE:
		roles.erase(crew_id)
		deployed.erase(crew_id)
	else:
		roles[crew_id] = role
		deployed.erase(crew_id)
		# 건물 안에 있었으면 하던 일을 멈추고 밖으로 나온다
		if _indoor(c.leader.level, c.leader.pos):
			doors.cancel(crew_id)
			rescue.cancel(crew_id)
			water.stop_spray(crew_id, tick)
			var exits := rescue.exit_cells()
			if not exits.is_empty():
				units.order_move([crew_id] as Array[int], exits[0], pathfinder)
	role_log.append({"tick": tick, "crew": crew_id, "role": role})
	events.add(tick, "role_assigned", {"crew": _crew_name(c), "role": ROLE_NAMES[role] if role != Role.NONE else "임무 해제"})
	radio.send(Radio.Priority.TACTICS, _crew_name(c), CommandSystem.COMMANDER, "%s 수신." % (ROLE_NAMES[role] if role != Role.NONE else "임무 해제"), tick)


func _on_evacuation_sent(tick: int) -> void:
	evacuation_log.append(tick)
	entry_allowed.clear()
	events.add(tick, "evacuation_ordered", {})
	withdraw_all(tick, "evacuate")


## 인원 점검 (SOP 109-1.3): 단위대는 단위지휘관이 묶어서, 나머지 출동대는 각자 차례로 보고한다.
## 건물 안 조는 위치·공기 잔량을 덧붙인다 (P10-2). 조원이 모두 쓰러진 조는 응답하지 못하고,
## 정한 시간(par_response_s) 안에 응답이 없는 조는 무응답으로 올린다 (무전 패널 긴급 줄)
func _on_par_sent(tick: int, _sender: String) -> void:
	var missing := 0
	var indoor := 0
	_par_expect.clear()
	_par_deadline = tick + _par_response_ticks
	var groups: Array = []
	for d in org.divisions:
		groups.append(["%s 지휘관" % d.name, d.squads])
	for s in units.squads:
		if resources.on_scene(s.id) and org.division_of(s.id) == null:
			groups.append([s.name, [s.id]])
	for g: Array in groups:
		var total := 0
		var down := 0
		var inside := 0
		var where: PackedStringArray = []
		var answering: Array[int] = []
		for sid: int in g[1]:
			for c in units.squads[sid].crews:
				_par_expect[c.id] = true
				var able := false
				for ff in c.members():
					total += 1
					if ff.incapacitated:
						down += 1
					else:
						able = true
						if _indoor(ff.level, ff.pos):
							inside += 1
				if able:
					answering.append(c.id)
					if _indoor(c.leader.level, c.leader.pos):
						where.append(_crew_where(c))
		missing += down
		indoor += inside
		var body := "인원 %d명 이상 없음, 장비 이상 없음." % total
		var pr := Radio.Priority.TACTICS
		if down > 0 or inside > 0:
			body = "%d명 중 %d명 확인." % [total, total - down - inside]
			if inside > 0:
				body += " 건물 안 %d명 — %s." % [inside, ", ".join(where)]
			if down > 0:
				body += " 미확인(행동 불능) %d명." % down
				pr = Radio.Priority.SAFETY
		radio.send(pr, str(g[0]), CommandSystem.COMMANDER, body, tick, _on_par_answered.bind(answering))
	par_log.append({"tick": tick, "missing": missing, "indoor": indoor})
	events.add(tick, "par_done", {"missing": missing, "indoor": indoor})


## "1조 2층 거실 공기 72%·65%"
func _crew_where(c: Crew) -> String:
	var room := fire.compartment_at(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y))
	var air: PackedStringArray = []
	for ff in c.members():
		air.append("%d%%" % roundi(ff.air_ratio() * 100.0))
	return "%d조 %s 공기 %s" % [c.number, room.display_name() if room else fire.building.floor_name(c.leader.level), "·".join(air)]


func _on_par_answered(_tick: int, crew_ids: Array[int]) -> void:
	for id in crew_ids:
		_par_expect.erase(id)
		par_no_response.erase(id)


## 인원 점검 응답 시간이 지났는데 응답하지 않은 조 → 무응답 (대원 안전 무전·긴급 줄)
func _check_par_deadline(tick: int) -> void:
	# 무응답이던 조가 구출되거나 다시 움직이면 줄에서 뺀다
	for id in par_no_response.duplicate():
		var c := units.get_crew(id)
		if c == null or not c.leader.incapacitated or not _indoor(c.leader.level, c.leader.pos):
			par_no_response.erase(id)
	if _par_deadline < 0 or tick < _par_deadline:
		return
	_par_deadline = -1
	for id: int in _par_expect:
		var c := units.get_crew(id)
		if c == null or par_no_response.has(id):
			continue
		par_no_response.append(id)
		events.add(tick, "par_no_response", {"crew": _crew_name(c), "where": fire.building.floor_name(c.leader.level)})
	_par_expect.clear()


# --- 도움 ---

## 무선 침묵 (109-1.2.3): 대기 중인 대원의 일반 보고를 비운다. 지휘관의 명령·대원 안전·구조대상자 무전은 남긴다
func _silence_queue() -> void:
	var keep: Array[Radio.Message] = []
	for m in radio.queue:
		if m.priority <= Radio.Priority.VICTIM or m.sender == CommandSystem.COMMANDER or m.on_sent.is_valid():
			keep.append(m)
		else:
			suppressed_reports += 1
	radio.queue = keep

func _repeat_word() -> Array:
	var out: Array = []
	for i in _repeat:
		out.append("긴급탈출")
	return out


func _any_down_inside() -> bool:
	for ff in units.firefighters:
		if ff.incapacitated and _indoor(ff.level, ff.pos):
			return true
	return false


func _indoor(level: int, p: Vector2) -> bool:
	return not fire.building.cell(level, floori(p.x), floori(p.y)) in BuildingData.OUTDOOR


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]
