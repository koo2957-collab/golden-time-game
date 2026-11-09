class_name CommandSystem
extends RefCounted
## 현장지휘 계층.
## 근거: 2025 재난현장표준작전절차 (조항 번호는 이 판 기준).
##   지휘권 선언 + 최초 상황보고 (SOP 101-1.2, 2.1): 8개 항목 + 차량 진입·회차(교재 참고, 채점 안 함)를 무전으로 송신,
##                                                 그때 확인할 수 있던 사실과 비교해 기록
##   진입 명령 (102-5.2): 명령을 받은 출동대만 건물 안으로 들어간다. 지휘관은 혼자 들어가지 않는다
##   전략 (106-2): 공격·방어·병행. 바꾸면 무전으로 전파하고, 방어로 바꾸면 내부 대원을 철수시킨다
##   대원 보고 (107-1.6): 안전·요구조자·주요 사건을 무전으로 보고 (우선순위 대기열)
##   자동 감속: 위험 징후·요구조자 발견 등 중요한 사건이 생기면 1배속으로 돌아간다
##   후착대·지원 요청 (103): ResourceSystem. 대기 중인 출동대에 처음 명령하면 투입 무전이 먼저 나간다
##   단위대·통솔범위 (105): Organization. 직접 지휘가 적정을 넘으면 명령이 늦게 실행된다
##   현장 정보 (101-2.2, 102-2, 202-2)·현장지휘소 (104-1.3): SiteSurvey. 보완 보고로 상황을 다시 전파한다
##   대원 안전 (108, 109, SSG 9): SafetySystem. 긴급탈출 선언·무선 침묵·긴급탈출 지시·인원점검·RIT·현장안전담당
##   진입 금지 판단 (102-4.1): 진입 명령 때 해당하는 판단 요소를 알리고 기록한다
##   주요 의사결정 기록 (111-2.2): 선언·전략·진입·지원·긴급탈출·종료 때 그때 알던 정보를 남긴다 (디브리핑)
##   작전망 (107-3.2): 단위대 소속 출동대의 일반 보고·응답은 그 단위대 작전망으로 간다 (안전·구조대상자 보고는 지휘망)

enum Strategy { NONE, OFFENSIVE, DEFENSIVE, COMBINED }
const STRATEGY_NAMES: Array[String] = ["미선언", "공격", "방어", "병행"]
const COMMANDER := "현장지휘관"
const DISPATCH_CENTER := "119종합상황실"
## 이 사건이 생기면 1배속으로 돌아간다
const AUTO_SLOW_TYPES: Array[String] = [
	"ff_down", "mayday", "air_alarm", "victim_found", "rollover_sign", "backdraft_sign", "backdraft",
	"fgi_warning", "flashover", "rekindle", "collapse_sign", "collapse", "gas_explosion", "exposure_ignition", "jump_risk", "sign_warning", "shaft_ignition",
]
## 대원이 무전으로 보고하는 사건과 우선순위 (107-1.3). 대원 쓰러짐은 SafetySystem의 긴급탈출 선언으로 보고한다
const REPORT_PRIORITY := {
	"air_alarm": Radio.Priority.SAFETY,
	"heat_retreat": Radio.Priority.SAFETY,
	"rollover_sign": Radio.Priority.SAFETY,
	"backdraft_sign": Radio.Priority.SAFETY,
	"backdraft": Radio.Priority.SAFETY,
	"fgi_warning": Radio.Priority.SAFETY,
	"exit_blocked": Radio.Priority.SAFETY,
	"victim_found": Radio.Priority.VICTIM,
	"door_check_seen": Radio.Priority.VICTIM,
	"hose_resupply": Radio.Priority.TACTICS,
	"steam_mix": Radio.Priority.SAFETY,
	"firebrand_ignition": Radio.Priority.KEY_FACTOR,
	"flow_short": Radio.Priority.KEY_FACTOR,
	"tank_low": Radio.Priority.KEY_FACTOR,
	"below_checked": Radio.Priority.TACTICS,
	"estimate_differs": Radio.Priority.KEY_FACTOR,
	"victim_state": Radio.Priority.VICTIM,
	"rescue_pickup": Radio.Priority.VICTIM,
	"victim_rescued": Radio.Priority.VICTIM,
	"victim_recovered": Radio.Priority.VICTIM,
	"ff_rescued": Radio.Priority.VICTIM,
	"search_done": Radio.Priority.VICTIM,
	"crew_entered": Radio.Priority.KEY_FACTOR,
	"door_forced": Radio.Priority.KEY_FACTOR,
	"window_vented": Radio.Priority.KEY_FACTOR,
	"tank_empty": Radio.Priority.KEY_FACTOR,
	"squad_staged": Radio.Priority.KEY_FACTOR,
	"ember_spotted": Radio.Priority.KEY_FACTOR,
	"tactical_halt": Radio.Priority.KEY_FACTOR,
	"exposure_heating": Radio.Priority.KEY_FACTOR,
	"exposure_ignition": Radio.Priority.KEY_FACTOR,
	"collapse_sign": Radio.Priority.SAFETY,
	"collapse": Radio.Priority.SAFETY,
	"gas_explosion": Radio.Priority.SAFETY,
	"gas_shutoff": Radio.Priority.KEY_FACTOR,
	"jump_risk": Radio.Priority.SAFETY,
	"victim_jumped": Radio.Priority.SAFETY,
	"debris_zone": Radio.Priority.KEY_FACTOR,
	"debris_zone_entered": Radio.Priority.SAFETY,
	"air_mat_ready": Radio.Priority.KEY_FACTOR,
	"sign_warning": Radio.Priority.SAFETY,
	"hydrant_out": Radio.Priority.KEY_FACTOR,
	"knockdown_reported": Radio.Priority.KEY_FACTOR,
	"all_clear_declared": Radio.Priority.KEY_FACTOR,
	"end_suggested": Radio.Priority.KEY_FACTOR,
	"shuttle_depart": Radio.Priority.KEY_FACTOR,
	"shuttle_return": Radio.Priority.KEY_FACTOR,
	"sign_fall": Radio.Priority.SAFETY,
	"shaft_heat": Radio.Priority.KEY_FACTOR,
	"shaft_smoke": Radio.Priority.KEY_FACTOR,
	"shaft_ignition": Radio.Priority.KEY_FACTOR,
	"shaft_checked": Radio.Priority.KEY_FACTOR,
	"victim_trapped": Radio.Priority.KEY_FACTOR,
	"victim_self_evac": Radio.Priority.KEY_FACTOR,
	"tactical_done": Radio.Priority.TACTICS,
	"fire_found": Radio.Priority.KEY_FACTOR,
	"plan_acquired": Radio.Priority.KEY_FACTOR,
	"exit_air_low": Radio.Priority.SAFETY,
	"monitor_crew_inside": Radio.Priority.SAFETY,
	"command_unit_arrived": Radio.Priority.KEY_FACTOR,
	"command_transferred": Radio.Priority.KEY_FACTOR,
	"elevator_too_high": Radio.Priority.SAFETY,
	"crew_disoriented": Radio.Priority.SAFETY,
	"crew_reoriented": Radio.Priority.SAFETY,
	"victim_refuge": Radio.Priority.VICTIM,
	"ppv_start": Radio.Priority.KEY_FACTOR,
	"ppv_no_exhaust": Radio.Priority.KEY_FACTOR,
	"ppv_fire_push": Radio.Priority.SAFETY,
	"monitor_start": Radio.Priority.KEY_FACTOR,
	"indoor_hydrant_empty": Radio.Priority.KEY_FACTOR,
	"panel_fire_floor": Radio.Priority.KEY_FACTOR,
	"plan_diff_found": Radio.Priority.KEY_FACTOR,
	"mission_withdraw": Radio.Priority.SAFETY,
	"overhaul_done": Radio.Priority.KEY_FACTOR,
}
## 최초 상황보고 보기 (SOP 101-2.1). 연소 상황 보기는 층 수에 따라 fire_options()로 만든다.
const REPORT_OPTIONS := {
	"victims": ["있음", "없음", "확인 중"],
	"use": ["단독주택", "공동주택", "근린생활시설", "공장·창고"],
	"floors": ["1층", "2층", "3층", "4층 이상"],
	"structure": ["철근콘크리트조", "벽돌조", "목조", "철골조"],
	"hazards": ["특수현상 징후", "붕괴 우려", "위험물(가스 등)", "전기 위험"],
	"activities": ["인명검색", "내부 진입 진압", "외부 방수", "소화전 점령", "배연"],
	"support": ["불필요", "추가 출동대 요청", "대응 1단계 발령"],
	"access": ["진입·회차 가능", "진입 가능, 회차 불가", "진입 불가"],
}
const SMOKE_ONLY := "연기만 확인"
const MULTI_FLOOR_FIRE := "여러 층 화염 확인"
## 지휘 위치를 "펌프차 옆"처럼 부르는 거리 (셀)
const NEAR_VEHICLE_CELLS := 8.0

var fire: FireSim
var units: UnitSystem
var pathfinder: Pathfinder
## 임무 이름 (보고 요청 답에 쓴다)
var tactical: TacticalSystem
var rescue: RescueSystem
var water: WaterSystem
var doors: DoorSystem
var perception: Perception
var clock: SimClock
var events: SimEventLog
## 지휘망
var radio: Radio
var resources: ResourceSystem
var org: Organization
var survey: SiteSurvey
var safety: SafetySystem
## 임무형 내부 지휘: 건물 안 조에게는 무전으로, 경유지는 본 곳에만 (기획안 9-1, R7)
var interior: InteriorOrders
## 주요 의사결정과 그때 알던 정보 [{tick, decision, context}] (SOP 111-2.2)
var decisions: Array[Dictionary] = []
## 진입 명령 때의 진입 금지 판단 요소 [{tick, squad, factors}] (SOP 102-4.1)
var entry_checks: Array[Dictionary] = []
## 활동 종료 때 지정한 감시 (202-6.5): 출동대 이름 / "관계자 감시 당부" / ""
var watch := ""

## 진입 명령 규칙을 적용할지 (시나리오 = 적용, 지휘 규칙과 무관한 테스트 = 끔)
var entry_order_required := false
## 중요한 사건에 자동 감속할지
var auto_slow := true
## 현장지휘관 (선착대장). 출동대 목록에는 없고 이 계층이 움직인다.
var commander := Firefighter.new()
var commander_title := "선착대장"
## 진입 명령을 받은 출동대 (squad id -> true)
var entry_allowed: Dictionary = {}
var strategy := Strategy.NONE
## 지휘권 선언(최초 상황보고 송신 완료) 틱. 선언 전이면 -1
var command_tick := -1
## 최초 상황보고 내용과 판정. 송신 전이면 빈 사전
var report: Dictionary = {}
## 상황 보완 보고 (101-2.2①) 판정 기록 [{tick, items, correct, scored}]
var report_updates: Array[Dictionary] = []
## 출동 지령 (시나리오 dispatch)
var dispatch: Dictionary = {}
## 선착 차량 배치 결과 (Placement.apply, SOP 200-3.1.1). 비어 있으면 고르지 않음
var placement: Dictionary = {}
## 상황보고 정답 중 도면으로 알 수 없는 것 (시나리오 report_truth: use, vehicle_access, hazards)
var report_truth: Dictionary = {}

var _report_repeat_ticks: int
var _entry_wait_ticks: int
var _events_seen := 0
var _pending_strategy := -1
var _entry_pending: Dictionary = {}  # squad id -> true
var _declaring := false
var _inside: Dictionary = {}  # crew id -> 건물 안에 있었는지
var _last_report: Dictionary = {}  # "종류:보낸 쪽" -> tick
## 조가 마지막으로 무전 보고한 틱 {조 이름: tick} (팀 카드 "마지막 보고 후 경과", 기획안 9-2)
var last_report_tick: Dictionary = {}
var _entry_wait_tick: Dictionary = {}  # crew id -> tick
var _held: Array[Dictionary] = []  # 실행을 미룬 명령 {cmd, wait: 투입을 기다리는 출동대, release: 실행 틱}
var _commit_pending: Dictionary = {}  # squad id -> true (투입 무전 송신 중)
var _span_level := 0  # 0 적정 이하, 1 적정 초과, 2 한계 초과


func _init(p_fire: FireSim, p_units: UnitSystem, p_pathfinder: Pathfinder, p_rescue: RescueSystem, p_water: WaterSystem, p_doors: DoorSystem, p_perception: Perception, p_clock: SimClock, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	pathfinder = p_pathfinder
	rescue = p_rescue
	water = p_water
	doors = p_doors
	perception = p_perception
	clock = p_clock
	events = p_events
	radio = Radio.new(params, p_events)
	org = Organization.new(params, p_events)
	interior = InteriorOrders.new(p_fire, p_units, p_perception)
	_report_repeat_ticks = roundi(params.value("report_repeat_s") / SimClock.TICK_DT)
	_entry_wait_ticks = roundi(params.value("entry_wait_repeat_s") / SimClock.TICK_DT)
	commander.id = -1
	commander.squad_id = -1
	commander.crew_id = -1
	commander.name = "현장지휘관"
	for c in units.crews:
		_inside[c.id] = _indoor(c.leader.level, c.leader.pos)


## 시나리오의 command(지휘관), dispatch(출동 지령), report_truth를 읽는다.
func apply_scenario(data: Dictionary) -> void:
	dispatch = data.get("dispatch", {})
	report_truth = data.get("report_truth", {})
	var cmd: Dictionary = data.get("commander", {})
	commander.name = str(cmd.get("name", commander.name))
	commander.rank = str(cmd.get("rank", ""))
	commander_title = str(cmd.get("title", commander_title))
	var spawn: Array = cmd.get("spawn", [])
	if spawn.size() >= 2:
		commander.pos = Vector2(int(spawn[0]) + 0.5, int(spawn[1]) + 0.5)
		commander.prev_pos = commander.pos
		commander.level = int(cmd.get("level", 1))
		commander.prev_level = commander.level
	entry_order_required = bool(data.get("entry_order_required", true))
	resources.apply_scenario(data)
	survey.apply_scenario(data)


func declared() -> bool:
	return command_tick >= 0


func is_declaring() -> bool:
	return _declaring


func entry_pending(squad_id: int) -> bool:
	return _entry_pending.has(squad_id)


func can_enter(squad_id: int) -> bool:
	return not entry_order_required or entry_allowed.has(squad_id)


## 명령이 전달되기 전의 전략 변경까지 반영한 전략
func effective_strategy() -> Strategy:
	return _pending_strategy as Strategy if _pending_strategy >= 0 else strategy


# --- 틱 단계 ---

## 이동 전: 진입 명령을 받지 않은 대원·지휘관은 건물 입구 앞에서 멈춘다.
func before_move(tick: int) -> void:
	_gate(commander)
	# 투입되지 않은 RIT·현장안전담당은 진입 허가와 상관없이 밖에 머문다
	for c in units.crews:
		if safety.reserved(c.id):
			for ff in c.members():
				_gate(ff)
	if not entry_order_required:
		return
	for c in units.crews:
		if entry_allowed.has(c.squad_id) or safety.deployed.has(c.id) or safety.reserved(c.id):
			continue
		var stopped := false
		for ff in c.members():
			if _gate(ff):
				stopped = true
		if stopped:
			var last: int = _entry_wait_tick.get(c.id, -_entry_wait_ticks)
			if tick - last >= _entry_wait_ticks:
				_entry_wait_tick[c.id] = tick
				events.add(tick, "entry_wait", {"crew": _crew_name(c)})


func after_move(dt: float, tick: int) -> void:
	commander.step(dt, units.walk_speed_cells)
	survey.step(dt, tick)
	resources.step(tick)
	for c in units.crews:
		var inside := _indoor(c.leader.level, c.leader.pos)
		if inside and not _inside.get(c.id, false):
			events.add(tick, "crew_entered", {"crew": _crew_name(c), "floor": fire.building.floor_name(c.leader.level)})
		_inside[c.id] = inside


## 사건을 보고 무전·자동 감속으로 바꾸고 무전 채널을 진행한다.
func step(dt: float, tick: int) -> void:
	var entries := events.entries
	while _events_seen < entries.size():
		var e := entries[_events_seen]
		_events_seen += 1
		if auto_slow and e.type in AUTO_SLOW_TYPES and clock.speed > 1.0:
			clock.speed = 1.0
			events.add(tick, "auto_slow", {"reason": SimEventLog.describe_text(e)})
		if REPORT_PRIORITY.has(e.type):
			_report(e, tick)
	safety.step(tick)
	_check_span(tick)
	radio.step(dt, tick)
	org.step(dt, tick)


## 이번 틱에 실행할 명령을 고른다 (SimWorld가 명령 실행 전에 부른다).
##   아직 도착하지 않은 출동대에 내린 명령은 버린다
##   대기 중인 출동대에 내린 명령은 투입 무전이 전달될 때까지 미룬다
##   통솔범위를 넘었으면 직접 지휘하는 출동대에 내린 명령을 늦게 실행한다
func gate(commands: Array, tick: int) -> Array:
	var ready: Array = []
	var still: Array[Dictionary] = []
	for h in _held:
		if h.wait.is_empty() and tick >= h.release and not h.get("radio", false):
			ready.append(h.cmd)
		else:
			still.append(h)
	_held = still
	var direct := direct_count()
	for cmd in commands:
		if not _role_allows(cmd, tick):
			continue
		var why := interior.reject_reason(cmd)
		if why != "":
			interior.rejected += 1
			events.add(tick, "order_unseen", {"crew": interior.receiver_of(cmd), "reason": why})
			continue
		var squads := _order_squads(cmd)
		if squads.is_empty():
			ready.append(cmd)
			continue
		var away: PackedStringArray = []
		var staged: Array[int] = []
		for id in squads:
			if resources.is_en_route(id):
				away.append(units.squads[id].name)
			elif resources.is_staged(id):
				staged.append(id)
		if not away.is_empty():
			events.add(tick, "order_en_route", {"squad": "·".join(away)})
			continue
		if not staged.is_empty():
			for id in staged:
				_commit(id, tick)
			_held.append({"cmd": cmd, "wait": staged, "release": tick})
			continue
		var delay := org.order_delay_s(squads, direct)
		if delay > 0.0:
			org.delayed_orders += 1
		if interior.needs_radio(cmd):
			# 건물 안 조: 지휘망으로 지시가 전달된 뒤 실행 (교신·복명복창, 기획안 9-1)
			var h := {"cmd": cmd, "wait": [] as Array[int], "release": tick + roundi(delay / SimClock.TICK_DT), "radio": true}
			_held.append(h)
			interior.relayed += 1
			radio.send(interior.priority_of(cmd), COMMANDER, interior.receiver_of(cmd), interior.order_text(cmd), tick, _on_interior_received.bind(h))
			continue
		if delay > 0.0:
			_held.append({"cmd": cmd, "wait": [] as Array[int], "release": tick + roundi(delay / SimClock.TICK_DT)})
			continue
		ready.append(cmd)
	return ready


## 내부 지시가 전달됨: 다음 틱에 실행하고 조가 복명복창한다
func _on_interior_received(tick: int, h: Dictionary) -> void:
	h.radio = false
	radio.send(interior.priority_of(h.cmd), interior.receiver_of(h.cmd), COMMANDER, interior.ack_text(h.cmd), tick)


## RIT·현장안전담당은 다른 임무를 받지 않는다 (SSG 9 1.2.2). 밖에서 자리를 옮기는 이동은 된다.
## 긴급탈출 상황에서 RIT에 내린 명령은 투입으로 본다.
func _role_allows(cmd: RefCounted, tick: int) -> bool:
	var crew_ids: Array[int] = []
	if cmd is MoveCommand or cmd is EquipmentCommand or cmd is TacticalCommand:
		crew_ids = cmd.crew_ids
	for id in crew_ids:
		var role := safety.role_of(id)
		if role == SafetySystem.Role.NONE or safety.deployed.has(id):
			continue
		if role == SafetySystem.Role.RIT and safety.emergency():
			safety.deploy(id, tick)
			_decide(tick, "RIT 투입 — %s" % _crew_name(units.get_crew(id)))
			continue
		if cmd is MoveCommand:
			continue
		events.add(tick, "role_reserved", {"crew": _crew_name(units.get_crew(id)), "role": SafetySystem.ROLE_NAMES[role]})
		return false
	return true


## 현장지휘관이 직접 지휘하는 수 (단위대 + 단위대에 속하지 않은 현장 출동대)
func direct_count() -> int:
	return org.direct_count(units.squads.size(), resources.on_scene)


## 지금 직접 지휘하는 출동대에 명령하면 늦어지는 시간 (초)
func span_delay_s() -> float:
	return maxf(0.0, direct_count() - org.span_ideal) * org.delay_per_excess_s


## 실행을 기다리는 명령 수 (투입 대기 + 통솔범위 지연)
func held_count() -> int:
	return _held.size()


func commit_pending(squad_id: int) -> bool:
	return _commit_pending.has(squad_id)


# --- 명령 ---

## 지휘권 선언 + 최초 상황보고. answers: fire, victims, use, floors, structure, hazards(배열),
## activities(배열), strategy(Strategy), support, access
func declare(answers: Dictionary, tick: int) -> bool:
	if declared() or _declaring:
		return false
	_declaring = true
	var s: Strategy = int(answers.get("strategy", Strategy.OFFENSIVE)) as Strategy
	_pending_strategy = s
	report = grade_report(answers)
	report["submitted_tick"] = tick
	report["support_answer"] = str(answers.get("support", ""))
	_decide(tick, "지휘권 선언, %s 전략" % STRATEGY_NAMES[s])
	radio.send(Radio.Priority.KEY_FACTOR, COMMANDER, "%s, 각 출동대" % DISPATCH_CENTER, _report_text(answers), tick, _on_declared)
	return true


## 출동대에 내부 진입 명령. 방어 전략이면 받아들이지 않는다.
func order_entry(squad_id: int, tick: int) -> bool:
	if squad_id < 0 or squad_id >= units.squads.size():
		return false
	var squad := units.squads[squad_id]
	if effective_strategy() == Strategy.DEFENSIVE:
		events.add(tick, "entry_rejected", {"squad": squad.name, "reason": "방어 전략에서는 내부 진입 명령을 내릴 수 없음"})
		return false
	if entry_allowed.has(squad_id) or _entry_pending.has(squad_id):
		return false
	_entry_pending[squad_id] = true
	var factors := entry_factors(tick)
	entry_checks.append({"tick": tick, "squad": squad.name, "factors": factors})
	if not factors.is_empty():
		events.add(tick, "entry_factors", {"squad": squad.name, "factors": " · ".join(factors)})
	_decide(tick, "%s 내부 진입 명령" % squad.name)
	var d := org.division_of(squad_id)
	if d:
		radio.send(Radio.Priority.TACTICS, COMMANDER, _division_call(d), "%s 내부 진입하라." % squad.name, tick, _on_entry_received.bind(squad_id))
	else:
		radio.send(Radio.Priority.TACTICS, COMMANDER, squad.name, "내부 진입하라.", tick, _on_entry_received.bind(squad_id))
	return true


## 전략 변경을 전 대원에게 전파. 방어로 바꾸면 내부 대원 철수 (대원 안전 우선순위).
func order_strategy(s: Strategy, tick: int) -> bool:
	if s == Strategy.NONE or s == effective_strategy():
		return false
	_pending_strategy = s
	_decide(tick, "전략 변경 → %s" % STRATEGY_NAMES[s])
	var body := "전략을 %s(으)로 변경한다." % STRATEGY_NAMES[s]
	var priority := Radio.Priority.TACTICS
	if s == Strategy.DEFENSIVE:
		body = "전략을 방어로 변경한다. 내부 대원은 전원 밖으로 철수하라."
		priority = Radio.Priority.SAFETY
	radio.send(priority, COMMANDER, "전 대원", body, tick, _on_strategy_received.bind(s))
	return true


## 상황 보완 보고 (SOP 101-2.2①): 둘러보기·진술로 알게 된 구조대상자·위험 요소를 다시 전파한다.
## answers: victims, hazards(배열). 그때까지 확인할 수 있던 사실과 비교해 기록한다.
func update_report(answers: Dictionary, tick: int) -> bool:
	if not declared():
		return false
	var truth := observed_truth()
	var hazards: Array[String] = []
	for h in answers.get("hazards", []):
		hazards.append(str(h))
	hazards.sort()
	var hz_text := ", ".join(PackedStringArray(hazards)) if not hazards.is_empty() else "없음"
	var items: Array[Dictionary] = [
		_item(2, "구조대상자", answers.get("victims", ""), truth.victims),
		_item(4, "위험 요소", hz_text, ", ".join(PackedStringArray(truth.hazards)) if not truth.hazards.is_empty() else "없음"),
	]
	var correct := 0
	for it in items:
		if it.correct:
			correct += 1
	var entry := {"tick": tick, "items": items, "correct": correct, "scored": items.size()}
	var body := "상황 보완. 구조대상자 %s. 위험 요소 %s. %s 전략 유지." % [answers.get("victims", ""), hz_text, STRATEGY_NAMES[effective_strategy()]]
	radio.send(Radio.Priority.KEY_FACTOR, COMMANDER, "%s, 각 출동대" % DISPATCH_CENTER, body, tick, _on_update_sent.bind(entry))
	return true


func _on_update_sent(tick: int, entry: Dictionary) -> void:
	entry["sent_tick"] = tick
	report_updates.append(entry)
	events.add(tick, "report_updated", {"correct": entry.correct, "scored": entry.scored})


## 지원 요청 (SOP 103-1.2). level: 지원 수준 보기 글자 (시나리오 support)
func order_support(level: String, tick: int) -> bool:
	if not resources.support_options().has(level) or resources.support_level == level:
		return false
	_decide(tick, "지원 요청 — %s" % level)
	radio.send(Radio.Priority.KEY_FACTOR, COMMANDER, DISPATCH_CENTER, "%s." % level, tick, _on_support_received.bind(level))
	return true


## 긴급탈출 지시 (SSG 9 2.1.7, SOP 109-1.3): 전 대원 즉시 탈출, 진입 허가 취소
func order_evacuation(tick: int) -> void:
	_decide(tick, "긴급탈출 지시")
	_entry_pending.clear()
	safety.order_evacuation(COMMANDER, tick)


## 인원점검 (SOP 109-1.3, 200-4.1)
func order_par(tick: int) -> void:
	safety.order_par(COMMANDER, tick)


## 조에 RIT·현장안전담당 임무를 맡기거나 해제한다 (SSG 9, SOP 108-1.4)
func order_role(crew_id: int, role: int, tick: int) -> bool:
	if role != SafetySystem.Role.NONE:
		_decide(tick, "%s 지정 — %s" % [SafetySystem.ROLE_NAMES[role], _crew_name(units.get_crew(crew_id))])
	return safety.order_role(crew_id, role as SafetySystem.Role, COMMANDER, tick)


## 활동 종료 때 감시 지정 (202-6.5)
func set_watch(value: String, tick: int) -> void:
	watch = value
	_decide(tick, "활동 종료 — 재발화 감시: %s" % (value if value != "" else "지정 안 함"))


## 진입 금지 판단 요소 중 지금 해당하는 것 (SOP 102-4.1). 진입 명령 때 알리고 기록한다
func entry_factors(tick: int) -> PackedStringArray:
	var out: PackedStringArray = []
	var signs: PackedStringArray = []
	for t in ["rollover_sign", "backdraft_sign", "fgi_warning"]:
		for e in events.of_type(t):
			if tick - int(e.tick) <= safety.factor_recent_ticks and not str(e.room) in signs:
				signs.append(str(e.room))
	if not signs.is_empty():
		out.append("⑧ 특수현상 징후 (%s)" % ", ".join(signs))
	var b := fire.building
	var levels := b.levels()
	for level in levels:
		if level < levels[-1]:
			for y in b.height:
				var found := false
				for x in b.width:
					if _seen_burning(level, x, y):
						found = true
						break
				if found:
					out.append("② 화재 상층부 임무 가능 (%s 화재)" % b.floor_name(level))
					break
			if out.size() > 0 and out[-1].begins_with("②"):
				break
	if not survey.known_hazards().is_empty():
		out.append("⑨ 위험 정보 (%s)" % ", ".join(PackedStringArray(survey.known_hazards())))
	var collapse: PackedStringArray = []
	for e in events.of_type("collapse_sign"):
		collapse.append(str(e.room))
	if not collapse.is_empty():
		out.append("⑨ 붕괴 징후 (%s)" % ", ".join(collapse))
	if _victim_truth() == "있음":
		out.append("⑩ 구조대상자 내부 존재")
	return out


## 주요 의사결정과 그때 알던 정보를 기록한다 (SOP 111-2.2 주요 의사결정 근거)
func _decide(tick: int, what: String) -> void:
	var t := observed_truth()
	var hz: Array = t.hazards
	decisions.append({
		"tick": tick,
		"decision": what,
		"context": "연소 %s · 구조대상자 %s · 위험 요소 %s · 둘러보기 %d/%d면 · 직접 지휘 %d" % [
			t.fire, t.victims, ", ".join(PackedStringArray(hz)) if not hz.is_empty() else "없음",
			survey.faces_seen.size(), survey.face_keys().size(), direct_count()],
	})


## 단위대 지정 (SOP 105-3.1): 단위지휘관(supervisor 출동대장)·소속 출동대·작전망을 통지한다
func order_division(name: String, supervisor: int, squads: Array[int], tick: int) -> bool:
	if supervisor < 0 or supervisor >= units.squads.size() or not resources.on_scene(supervisor):
		return false
	var members: Array[int] = [supervisor]
	for s in squads:
		if s != supervisor and s >= 0 and s < units.squads.size() and resources.on_scene(s):
			members.append(s)
	var names: PackedStringArray = []
	for s in members:
		names.append(units.squads[s].name)
	var body := "%s 대장을 %s 지휘관으로 지정한다. 소속 %s." % [units.squads[supervisor].name, name, "·".join(names)]
	radio.send(Radio.Priority.TACTICS, COMMANDER, units.squads[supervisor].name, body, tick, _on_division_received.bind(name, supervisor, members))
	return true


func order_division_clear(name: String, tick: int) -> bool:
	var d := org.division_named(name)
	if d == null:
		return false
	radio.send(Radio.Priority.TACTICS, COMMANDER, _division_call(d), "%s 단위대를 해제한다. 소속 출동대는 현장지휘관 직접 지휘." % name, tick, _on_division_cleared.bind(name))
	return true


func move_commander(target: Vector3i) -> void:
	var cell := pathfinder.nearest_walkable(target.z, Vector2i(target.x, target.y))
	if cell == Pathfinder.NO_CELL:
		return
	var path := pathfinder.find_path(commander.cell3(), Vector3i(cell.x, cell.y, target.z))
	if not path.is_empty():
		commander.set_path(path)


# --- 무전 수신 처리 ---

func _on_declared(tick: int) -> void:
	_declaring = false
	command_tick = tick
	strategy = report.get("strategy_answer", Strategy.OFFENSIVE)
	_pending_strategy = -1
	var support := str(report.get("support_answer", ""))
	events.add(tick, "command_declared", {
		"strategy": STRATEGY_NAMES[strategy],
		"correct": report.correct,
		"scored": report.scored,
	})
	var body := "지휘권 선언과 최초 상황보고 수신."
	if resources.support_options().has(support):
		var names := resources.request_support(support, tick)
		if not names.is_empty():
			body += " %s 지원 출동." % "·".join(names)
	radio.send(Radio.Priority.TACTICS, DISPATCH_CENTER, COMMANDER, body, tick)


func _on_entry_received(tick: int, squad_id: int) -> void:
	_entry_pending.erase(squad_id)
	if effective_strategy() == Strategy.DEFENSIVE:
		return
	entry_allowed[squad_id] = true
	var squad := units.squads[squad_id]
	events.add(tick, "entry_ordered", {
		"squad": squad.name,
		"before_command": not declared(),
		"strategy": STRATEGY_NAMES[strategy],
	})
	var d := org.division_of(squad_id)
	if d:
		d.radio.send(Radio.Priority.TACTICS, squad.name, _division_call(d), "내부 진입 지시 수신, 진입하겠음.", tick)
	else:
		radio.send(Radio.Priority.TACTICS, squad.name, COMMANDER, "내부 진입 명령 수신, 진입하겠음.", tick)


func _on_strategy_received(tick: int, s: Strategy) -> void:
	if _pending_strategy == s:
		_pending_strategy = -1
	strategy = s
	events.add(tick, "strategy_set", {"strategy": STRATEGY_NAMES[s]})
	if s == Strategy.DEFENSIVE:
		entry_allowed.clear()
		_entry_pending.clear()
		safety.withdraw_all(tick)
	# 직접 지휘하는 출동대는 각자, 단위대는 단위지휘관이 한 번 응답한다
	for d in org.divisions:
		radio.send(Radio.Priority.TACTICS, _division_call(d), COMMANDER, "%s 전략 수신, 단위대 전파하겠음." % STRATEGY_NAMES[s], tick)
	for squad in units.squads:
		if resources.on_scene(squad.id) and org.division_of(squad.id) == null:
			radio.send(Radio.Priority.TACTICS, squad.name, COMMANDER, "%s 전략 수신." % STRATEGY_NAMES[s], tick)


func _on_support_received(tick: int, level: String) -> void:
	var names := resources.request_support(level, tick)
	var body := "%s 수신." % level
	if not names.is_empty():
		body += " %s 출동." % "·".join(names)
	radio.send(Radio.Priority.TACTICS, DISPATCH_CENTER, COMMANDER, body, tick)


func _on_division_received(tick: int, name: String, supervisor: int, members: Array[int]) -> void:
	var d := org.set_division(name, supervisor, members)
	var names: PackedStringArray = []
	for s in d.squads:
		names.append(units.squads[s].name)
	events.add(tick, "division_set", {
		"division": name,
		"supervisor": units.squads[supervisor].name,
		"squads": "·".join(names),
		"channel": d.radio.channel,
	})
	radio.send(Radio.Priority.TACTICS, _division_call(d), COMMANDER, "%s 지휘 임무 수신. %s 사용." % [name, d.radio.channel], tick)


func _on_division_cleared(tick: int, name: String) -> void:
	if org.clear_division(name):
		events.add(tick, "division_cleared", {"division": name})


## 대기 중인 출동대 투입 (SOP 103-2.1.2). 무전이 전달되면 미뤄 둔 명령을 실행한다.
func _commit(squad_id: int, tick: int) -> void:
	if _commit_pending.has(squad_id):
		return
	_commit_pending[squad_id] = true
	radio.send(Radio.Priority.TACTICS, COMMANDER, units.squads[squad_id].name, "대기 해제, 현장 투입하라.", tick, _on_commit_received.bind(squad_id))


func _on_commit_received(tick: int, squad_id: int) -> void:
	_commit_pending.erase(squad_id)
	resources.commit(squad_id, tick)
	for h in _held:
		h.wait.erase(squad_id)
	radio.send(Radio.Priority.TACTICS, units.squads[squad_id].name, COMMANDER, "투입 명령 수신.", tick)


func _check_span(tick: int) -> void:
	var n := direct_count()
	var level := 2 if n > org.span_max else (1 if n > org.span_ideal else 0)
	if level > _span_level:
		events.add(tick, "span_warning", {
			"level": "한계 초과" if level == 2 else "적정 초과",
			"count": n, "ideal": org.span_ideal, "max": org.span_max,
		})
	_span_level = level


func _report(e: Dictionary, tick: int) -> void:
	var sender := str(e.get("crew", e.get("vehicle", e.get("squad", ""))))
	if sender == "":
		sender = "진입 대원"
	var key := "%s:%s" % [e.type, sender]
	var last: int = _last_report.get(key, -_report_repeat_ticks)
	if tick - last < _report_repeat_ticks:
		return
	_last_report[key] = tick
	last_report_tick[sender] = tick
	# "… — 진압1 1조"처럼 보낸 쪽 이름으로 끝나는 문장은 이름을 뺀다 (무전 앞에 이미 나온다)
	var body := SimEventLog.describe_text(e).trim_suffix(" — " + sender)
	var priority: Radio.Priority = REPORT_PRIORITY[e.type]
	# 긴급탈출 상황에서는 대원 안전·구조대상자 외의 무전을 멈춘다 (109-1.2.3 무선 침묵)
	if safety.emergency() and priority > Radio.Priority.VICTIM:
		safety.suppressed_reports += 1
		return
	var d := org.division_of(_squad_of_sender(sender))
	# 단위대 소속이면 대원 안전·구조대상자 외의 보고는 단위지휘관에게 작전망으로
	if d and priority > Radio.Priority.VICTIM:
		d.radio.send(priority, sender, _division_call(d), body + ".", tick)
	else:
		radio.send(priority, sender, COMMANDER, body + ".", tick)


# --- 최초 상황보고 ---

## 연소 상황 보기: 연기만 확인 / 층별 화염 확인 / 여러 층 화염 확인
func fire_options() -> Array[String]:
	var out: Array[String] = [SMOKE_ONLY]
	for level in fire.building.levels():
		out.append("%s 화염 확인" % fire.building.floor_name(level))
	out.append(MULTI_FLOOR_FIRE)
	return out


## 지금까지 현장에서 확인할 수 있었던 사실 (보이지 않은 것은 "확인 중"이 정답).
func observed_truth() -> Dictionary:
	var b := fire.building
	var fire_levels: Array[int] = []
	for level in b.levels():
		var found := false
		for y in b.height:
			for x in b.width:
				if _seen_burning(level, x, y):
					found = true
					break
			if found:
				break
		if found:
			fire_levels.append(level)
	var fire_text := SMOKE_ONLY
	if fire_levels.size() == 1:
		fire_text = "%s 화염 확인" % b.floor_name(fire_levels[0])
	elif fire_levels.size() > 1:
		fire_text = MULTI_FLOOR_FIRE
	var hazards: Array[String] = []
	if not events.of_type("rollover_sign").is_empty() or not events.of_type("backdraft_sign").is_empty():
		hazards.append("특수현상 징후")
	for h in report_truth.get("hazards", []):
		if not str(h) in hazards:
			hazards.append(str(h))
	for h in survey.known_hazards():
		if not h in hazards:
			hazards.append(h)
	hazards.sort()
	var n := b.levels().size()
	return {
		"fire": fire_text,
		"victims": _victim_truth(),
		"use": str(report_truth.get("use", "")),
		"floors": "%d층" % n if n < 4 else "4층 이상",
		"structure": b.structure,
		"hazards": hazards,
		"access": str(report_truth.get("vehicle_access", "")),
		"strategy": recommended_strategy(),
	}


## 추천 전략 (추정 기준): 플래시오버 전이면 공격, 이후에는 구조대상자 가능성이 있으면 병행, 없으면 방어
func recommended_strategy() -> Strategy:
	var developed := false
	for c in fire.comps:
		if c.flashed:
			developed = true
	if not developed:
		return Strategy.OFFENSIVE
	return Strategy.COMBINED if _victim_truth() == "있음" else Strategy.DEFENSIVE


## 상황보고 답을 확인 가능한 사실과 비교한다. 정답이 없는 항목(활동 계획 등)은 기록만 한다.
func grade_report(answers: Dictionary) -> Dictionary:
	var truth := observed_truth()
	var items: Array[Dictionary] = []
	items.append(_item(1, "도착 출동대", arrived_text(), null))
	items.append(_item(2, "연소 상황", answers.get("fire", ""), truth.fire))
	items.append(_item(2, "구조대상자", answers.get("victims", ""), truth.victims))
	items.append(_item(3, "건물 용도", answers.get("use", ""), truth.use if truth.use != "" else null))
	items.append(_item(3, "층수", answers.get("floors", ""), truth.floors))
	items.append(_item(3, "건축 구조", answers.get("structure", ""), truth.structure))
	var hazards: Array[String] = []
	for h in answers.get("hazards", []):
		hazards.append(str(h))
	hazards.sort()
	items.append(_item(4, "위험 요소", ", ".join(PackedStringArray(hazards)) if not hazards.is_empty() else "없음",
		", ".join(PackedStringArray(truth.hazards)) if not truth.hazards.is_empty() else "없음"))
	items.append(_item(5, "지휘권 선언", "%s %s, %s" % [commander_title, commander.name, commander_position_text()], null))
	var acts: Array = answers.get("activities", [])
	items.append(_item(6, "소방 활동", ", ".join(PackedStringArray(acts)) if not acts.is_empty() else "없음", null))
	var s := int(answers.get("strategy", Strategy.OFFENSIVE))
	items.append(_item(7, "전략", STRATEGY_NAMES[s], STRATEGY_NAMES[truth.strategy]))
	items.append(_item(8, "지원 요청", answers.get("support", ""), null))
	# 2025 SOP 101-2.1은 8개 항목이다. 차량 진입·회차는 교재(이전 판) 항목이라 참고로만 남긴다
	items.append(_item(9, "차량 진입·회차 (참고)", answers.get("access", ""), null))
	var correct := 0
	var scored := 0
	for it in items:
		if it.scored:
			scored += 1
			if it.correct:
				correct += 1
	return {"items": items, "correct": correct, "scored": scored, "strategy_answer": s}


func arrived_text() -> String:
	var names: PackedStringArray = []
	for squad in units.squads:
		if resources.on_scene(squad.id):
			names.append(squad.name)
	return "·".join(names)


## 지휘 위치: 건물 방면(SOP 105-2.2) + 가까운 차량. 예: "A면 펌프차 옆"
func commander_position_text() -> String:
	var b := fire.building
	var rect := b.footprint(b.levels()[0])
	var p := commander.pos
	var dx := p.x - clampf(p.x, rect.position.x, rect.end.x)
	var dy := p.y - clampf(p.y, rect.position.y, rect.end.y)
	var dir := ""
	if absf(dy) >= absf(dx):
		dir = "south" if dy > 0 else "north"
	else:
		dir = "east" if dx > 0 else "west"
	var face := ""
	for key: String in b.faces:
		if b.faces[key] == dir:
			face = "%s면" % key
	if _indoor(commander.level, p):
		face = "건물 내부"
	var text := face
	var best_d := NEAR_VEHICLE_CELLS
	for v in units.vehicles:
		var d := v.pos.distance_to(p)
		if d < best_d:
			best_d = d
			text = "%s %s 옆" % [face, v.short_name]
	return text


## 구조대상자 가능성 (확인한 정보 기준: 있음 / 없음 / 확인 중)
func victim_truth() -> String:
	return _victim_truth()


func _victim_truth() -> String:
	if bool(dispatch.get("reported_victims", false)):
		return "있음"
	for v in rescue.victims:
		if v.discovered:
			return "있음"
	for c in fire.comps:
		if c.searched_tick < 0 and not fire.is_exposure_comp(c):
			return "확인 중"
	return "없음"


func _report_text(a: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append("%s 현장 도착." % arrived_text())
	parts.append("%s %s %s, %s." % [a.get("floors", ""), a.get("structure", ""), a.get("use", ""), a.get("fire", "")])
	parts.append("구조대상자 %s." % a.get("victims", ""))
	var hz: Array = a.get("hazards", [])
	parts.append("위험 요소 %s." % (", ".join(PackedStringArray(hz)) if not hz.is_empty() else "없음"))
	parts.append("%s %s, %s에서 지휘권 선언." % [commander_title, commander.name, commander_position_text()])
	var acts: Array = a.get("activities", [])
	if not acts.is_empty():
		parts.append("%s 실시." % ", ".join(PackedStringArray(acts)))
	parts.append("%s 전략." % STRATEGY_NAMES[int(a.get("strategy", Strategy.OFFENSIVE))])
	parts.append("지원 %s." % a.get("support", ""))
	parts.append("차량 %s." % a.get("access", ""))
	return " ".join(parts)


static func _item(no: int, name: String, answer: Variant, truth: Variant) -> Dictionary:
	var scored := truth != null
	return {
		"no": no,
		"name": name,
		"answer": str(answer),
		"truth": str(truth) if scored else "",
		"scored": scored,
		"correct": scored and str(answer) == str(truth),
	}


# --- 도움 함수 ---

## 건물 밖에 있는 대원이 건물 안으로 들어가려 하면 입구 앞에서 경로를 자른다. 잘랐으면 true.
func _gate(ff: Firefighter) -> bool:
	if ff.path.is_empty() or _indoor(ff.level, ff.pos):
		return false
	for i in ff.path.size():
		var wp := ff.path[i]
		if _indoor(wp.z, Vector2(wp.x, wp.y)):
			ff.path.resize(i)
			return true
	return false


## 대원이 불타는 것을 본 적이 있는 칸인지 (정보 안개가 꺼져 있으면 실제 상태)
func _seen_burning(level: int, x: int, y: int) -> bool:
	var i := fire.grid.index(level, x, y)
	if not perception.enabled:
		return fire.grid.state[i] == FuelGrid.State.BURNING
	return perception.seen_burning[i] == 1


func _indoor(level: int, p: Vector2) -> bool:
	return not fire.building.cell(level, floori(p.x), floori(p.y)) in BuildingData.OUTDOOR


## 명령을 받는 출동대 (투입·통솔범위 판정용). 지휘 명령(선언·전략·지휘관 이동 등)은 빈 배열.
func _order_squads(cmd: RefCounted) -> Array[int]:
	var out: Array[int] = []
	var crew_ids: Array[int] = []
	if cmd is MoveCommand or cmd is TacticalCommand:
		crew_ids = cmd.crew_ids
	elif cmd is EquipmentCommand:
		crew_ids = cmd.crew_ids
		if cmd.action in ["vehicle_move", "hydrant", "supply"]:
			var v := units.get_vehicle(cmd.vehicle_id)
			if v:
				out.append(v.squad_id)
	elif cmd is CommandOrder and cmd.action == "entry":
		out.assign(cmd.squad_ids)
	for id in crew_ids:
		var c := units.get_crew(id)
		if c and not c.squad_id in out:
			out.append(c.squad_id)
	return out


## "진압1 1조", "진압1 펌프차", "진압1" → 진압1의 id (없으면 -1)
func _squad_of_sender(sender: String) -> int:
	for squad in units.squads:
		if sender == squad.name or sender.begins_with(squad.name + " "):
			return squad.id
	return -1


func _division_call(d: Organization.Division) -> String:
	return "%s 지휘관" % d.name


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]


# --- 보고 요청 (원형 메뉴, R7c) ---

## 지휘관이 조에게 상황 보고를 요청한다 (SOP 107-1.6). 요청이 전달되면 조가 위치·임무·공기를 보고한다
func request_report(crew_ids: Array, tick: int) -> void:
	for id in crew_ids:
		var c := units.get_crew(int(id))
		if c == null or c.leader.incapacitated:
			continue
		radio.send(Radio.Priority.TACTICS, COMMANDER, _crew_name(c), "현재 위치와 상황 보고하라.", tick, _on_report_requested.bind(c.id))


func _on_report_requested(tick: int, crew_id: int) -> void:
	var c := units.get_crew(crew_id)
	if c == null or c.leader.incapacitated:
		return
	var name := _crew_name(c)
	var room := fire.compartment_at(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y))
	var where := room.display_name() if room else ("%s 외부" % fire.building.floor_name(c.leader.level) if c.leader.level > 1 else "건물 밖")
	var air := 1.0
	for ff in c.members():
		air = minf(air, ff.air_ratio())
	var task := tactical.mission_text(crew_id) if tactical else ""
	var parts: PackedStringArray = ["현재 %s" % where, "임무 %s" % (task if task != "" else "없음(대기)"), "공기 %d%%" % roundi(air * 100.0)]
	if room and room.soot / maxf(room.layer_volume(), 0.05 * room.volume) > 0.02:
		parts.append("짙은 연기")
	last_report_tick[name] = tick
	radio.send(Radio.Priority.TACTICS, name, COMMANDER, ", ".join(parts) + ".", tick)
	events.add(tick, "crew_report", {"crew": name, "text": ", ".join(parts)})
