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
var _air_swap_ratio := 0.5
## 공기호흡기 교체가 끝났다고 보는 공기 비율 (CommandSystem._step_air_swaps)
var air_full_ratio := 0.95
## 공기호흡기 교체로 관창을 놓고 나온 조 {crew id: {tick, resume {action, target} 또는 {}, state "out"·"back"}}.
## 교체가 끝나면 CommandSystem 이 호스를 따라 다시 들여보낸다 (_step_air_swaps)
var air_swaps: Dictionary = {}
## 철수 중인 조 {crew id: {tick, reason, goal 가려던 칸, blocked 열기에 막힘}} (2026-11-25 사용자 결정): 나가는 길이 열기에 막히면
## 식은 곳에서 기다리다가, 길이 열리면 스스로 다시 나오며 "퇴로 확보, 철수 재개"를 보고한다. 밖에 닿거나 다른 지시를 받으면 지운다.
## 전에는 막힌 뒤 철수 지시를 잊어, 길이 열려도 건물 안에 서 있다가 쓰러졌다 (튜토리얼 자동 진행)
var withdrawing: Dictionary = {}
## 막혔던 길이 다시 열렸는가 (crew, path) -> bool · 열기로 나갈 길이 없음을 알린다 (crew, tick) — CrewConditionSystem. SimWorld가 넣는다
var way_reopened := Callable()
var note_blocked := Callable()
## 그 조가 철수 말고 다른 일을 받았는가 (crew id) -> bool — 임무·층 이동·진입구 접근·방수 등. SimWorld가 넣는다
var other_duty := Callable()
var _heat_cut := false


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
	_air_swap_ratio = params.value("air_swap_ratio") if params.params.has("air_swap_ratio") else 0.5
	air_full_ratio = params.value("air_full_ratio") if params.params.has("air_full_ratio") else 0.95


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
	# 한 명 보내기로 나간 대원에게는 안전 임무를 맡기지 않는다 (RIT는 2명 이상)
	if c.solo and role != Role.NONE:
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


## 한 조를 밖으로 내보낸다. 수관을 깔고 있던 조는 (2026-11-24 사용자 결정):
##   긴급 철수(reason 이 "withdraw" 가 아님 — 긴급탈출 등): 관창을 놓고 호스를 따라 바로 밖으로 (호스는 상황이 끝난 뒤 회수)
##   공기호흡기 교체(조원 공기가 air_swap_ratio 아래이거나 경보): 관창을 놓고 호스를 따라 펌프차로 나와 교체 → 다시 들어가 잇는다
##   보통 철수: 관창을 놓은 자리부터 호스를 거두며 펌프차로 돌아온다 (시간이 걸린다)
## resume = 교체 뒤 이어 할 임무 {action, target} (TacticalSystem 이 넘긴다)
func withdraw_crew(c: Crew, tick: int, reason := "withdraw", resume: Dictionary = {}) -> void:
	var h: HoseLine = water.hose_of_crew(c.id) if water else null
	var laid := h != null and h.held() and not h.to_outlet and h.fetch_until < 0 and h.points.size() >= 2
	if not _indoor(c.leader.level, c.leader.pos) and not laid:
		return
	doors.cancel(c.id)
	rescue.cancel(c.id)
	water.stop_spray(c.id, tick)
	withdrawing.erase(c.id)
	if laid:
		if reason != "withdraw":
			water.drop_nozzle(c.id, tick)
			var out := _hose_exit(h)
			if out.x >= 0:
				var clear := _clear_of_building(out)
				units.order_move([c.id], clear, pathfinder)
				_mark_withdraw(c, tick, reason, clear)
				events.add(tick, reason, {"crew": _crew_name(c)})
				return
		elif _needs_air(c):
			water.drop_nozzle(c.id, tick)
			air_swaps[c.id] = {"tick": tick, "resume": resume, "state": "out"}
			events.add(tick, "air_swap_out", {"crew": _crew_name(c), "crew_id": c.id})
			var spot := _swap_spot(c, h)
			if spot.x >= 0:
				units.order_move([c.id], spot, pathfinder)
				_mark_withdraw(c, tick, "air_swap", spot)
				return
			# 교체할 펌프차 옆이 없다: 아래 보통 출구로 나간다
		else:
			var start := h.points[0]
			water.recover_hose(c.id, tick)
			_mark_withdraw(c, tick, reason, start)
			events.add(tick, reason, {"crew": _crew_name(c)})
			return
	if not _indoor(c.leader.level, c.leader.pos):
		return
	var exits := rescue.exit_cells()
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
	var to := _clear_of_building(best)
	units.order_move([c.id], to, pathfinder)
	_mark_withdraw(c, tick, reason, to)
	events.add(tick, reason, {"crew": _crew_name(c)})


## 건물 안에서 철수를 시작한 조를 적어 둔다 (열기에 막히면 길이 열릴 때 다시 잇는다 — step_withdrawing)
func _mark_withdraw(c: Crew, tick: int, reason: String, goal: Vector3i) -> void:
	if _indoor(c.leader.level, c.leader.pos):
		withdrawing[c.id] = {"tick": tick, "reason": reason, "goal": goal, "blocked": false}


## 새 지시를 받았다: '교체 뒤 관창으로 돌아가기'와 '막힌 철수 다시 잇기'를 잊는다
func forget_return(crew_id: int) -> void:
	air_swaps.erase(crew_id)
	withdrawing.erase(crew_id)


## 철수하던 조가 열기에 길이 막혔다 (SimWorld._on_heat_stop): 식은 곳으로 물러나 길이 열리기를 기다린다. 철수 중이었으면 true
func withdraw_blocked(crew_id: int) -> bool:
	if not withdrawing.has(crew_id):
		return false
	withdrawing[crew_id].blocked = true
	return true


## 철수 중인 조 (2026-11-25): 건물 안에 멈춰 서 있으면 1초마다 열기에 막히지 않는 나갈 길을 찾아 다시 보낸다.
## 열기에 막혔다가 다시 나서면 "퇴로 확보, 철수 재개" 보고. 나갈 길이 열기로 모두 막혀 있으면 퇴로 차단 시간을 이어 센다 (고립 보고).
## 대원이 움직인 바로 뒤에 본다 (CommandSystem.after_move — 열기에 막혀 멈추는 판단과 같은 틱의 불 상태로)
func step_withdrawing(tick: int) -> void:
	if withdrawing.is_empty():
		return
	for id: int in withdrawing.keys():
		var c := units.get_crew(id)
		var w: Dictionary = withdrawing[id]
		if c == null or c.leader.incapacitated or (other_duty.is_valid() and bool(other_duty.call(id))):
			withdrawing.erase(id)
			continue
		var leader := c.leader
		var h: HoseLine = water.hose_of_crew(id) if water else null
		# 걷는 중이거나 호스를 거두며 나오는 중(WaterSystem 이 길을 잡는다)이면 그대로 둔다
		if leader.is_moving() or (h != null and h.recovering):
			continue
		var goal: Vector3i = w.goal
		if not _indoor(leader.level, leader.pos):
			# 밖으로 나왔다. 공기호흡기 교체는 다른 문으로 나왔어도 펌프차 옆까지 간다 (거기서 교체한다)
			withdrawing.erase(id)
			if str(w.reason) == "air_swap" and leader.cell3().distance_to(goal) > 2.0:
				units.order_move([id] as Array[int], goal, pathfinder)
			continue
		if tick % roundi(1.0 / SimClock.TICK_DT) != 0:
			continue
		var to := _way_out(c, goal)
		if to.x < 0:
			if _heat_cut:
				w.blocked = true
				if note_blocked.is_valid():
					note_blocked.call(c, tick)
			continue
		units.order_move([id] as Array[int], to, pathfinder)
		if bool(w.blocked):
			w.blocked = false
			events.add(tick, "withdraw_resume", {"crew": _crew_name(c), "crew_id": id})


## 열기에 막히지 않고 밖으로 나가는 길의 끝 칸: 처음 가려던 곳 먼저, 아니면 가까운 열린 출구부터. 없으면 (-1, -1, -1).
## _heat_cut = 길은 있는데 열기에 막힌 것이 있었다 (길이 아예 없는 것 — 닫힌 문 등 — 과 가른다)
func _way_out(c: Crew, goal: Vector3i) -> Vector3i:
	_heat_cut = false
	var from := c.leader.cell3()
	var exits := rescue.exit_cells()
	exits.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return from.distance_squared_to(a) + absi(a.z - from.z) * 10000.0 < from.distance_squared_to(b) + absi(b.z - from.z) * 10000.0)
	var list: Array[Vector3i] = []
	if goal.x >= 0:
		list.append(goal)
	for e in exits:
		var out := _clear_of_building(e)
		if not out in list:
			list.append(out)
	for to in list:
		var path := pathfinder.find_path(from, to)
		if path.is_empty():
			continue
		if not way_reopened.is_valid() or bool(way_reopened.call(c, path)):
			return to
		_heat_cut = true
	return Vector3i(-1, -1, -1)


## 공기호흡기를 바꿔야 하는가: 조원 누구든 공기가 air_swap_ratio 아래이거나 공기 경보가 울렸다
func _needs_air(c: Crew) -> bool:
	for ff in c.members():
		if ff.incapacitated:
			continue
		if ff.air_alarm_logged or ff.air_ratio() < _air_swap_ratio:
			return true
	return false


## 공기호흡기를 바꾸러 가는 자리: 그 수관을 대 준 펌프차 옆 (펌프차 수관은 호스 시작점 = 차 후면).
## 방수구(건물 안)에서 깐 수관이면 가장 가까운 펌프차 옆
func _swap_spot(c: Crew, h: HoseLine) -> Vector3i:
	if h.outlet < 0:
		return h.points[0]
	var best: Vehicle = null
	var best_d := INF
	for v in units.vehicles:
		if v.is_pump() and v.distance_to_body(c.leader.pos) < best_d:
			best_d = v.distance_to_body(c.leader.pos)
			best = v
	# 펌프차가 없거나 옆에 설 자리가 없으면 (-1): 보통 출구로 나간다 — 건물 안 방수구로 가면 교체가 끝나지 않는다 (2026-11-24 검사)
	if best == null:
		return Vector3i(-1, -1, -1)
	var near := pathfinder.nearest_walkable(best.level, Vector2i(best.closest_body_point(c.leader.pos).floor()))
	return Vector3i(near.x, near.y, best.level) if near != Pathfinder.NO_CELL else Vector3i(-1, -1, -1)


## 호스를 따라 나가는 출구: 관창 쪽에서 펌프차 쪽으로 호스를 거슬러 가다 처음 만나는 바깥 칸 (진입한 문 바로 밖).
## 바깥 칸이 없으면 (-1, -1, -1)
func _hose_exit(h: HoseLine) -> Vector3i:
	for k in range(h.points.size() - 1, -1, -1):
		var p := h.points[k]
		if not _indoor(p.z, Vector2(p.x, p.y) + Vector2(0.5, 0.5)):
			return p
	return Vector3i(-1, -1, -1)


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
		# 역할(RIT 등)을 받은 조는 교체 뒤 관창으로 돌아가지 않고, 놓고 간 관창은 주인을 푼다 (2026-11-24 검사)
		forget_return(crew_id)
		water.release_dropped(crew_id)
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
	return "%s %s 공기 %s" % [units.crew_short(c), room.display_name() if room else fire.building.floor_name(c.leader.level), "·".join(air)]


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
	return units.crew_name(c)
