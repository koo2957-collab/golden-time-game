class_name PhaseSystem
extends RefCounted
## 활동 단계와 종료 체계 (SOP 111~113, 202-6, 소방전술 I 현장지휘권 확립 8단계).
##   ① 출동·도착 → ② 지휘권 확립 → ③ 진압·인명구조 → ④ 초진 → ⑤ 잔불정리·2차 검색 → ⑥ 완진 선언 → ⑦ 마무리 → ⑧ 활동 종료
##   초진: 최성기·플래시오버 구획이 없고, 새로 착화한 구획이 없고, 타는 칸이 늘지 않는 상태가 knockdown_hold_s 유지되면
##         화재 구획 가까이 있는 진압 조가 자기가 보는 방을 "초진"으로 보고한다 (보지 못한 곳의 불은 빠진다 — SOP 102-4.1 ⑥).
##   2차 검색: 초진 뒤 끝난 인명검색은 2차 검색으로 기록한다 (8단계 ⑤).
##   완진 선언: 플레이어 명령. 막지 않고, 선언 때 실제 상태(타는 칸·숨은 불씨)를 기록해 판정한다.
##   더 할 일이 없으면 종료 제안 (강제 아님, 반복은 MissionEndChecker). 제한 시간은 없다 (기획안 8-3, P11-1).

enum Phase { DISPATCH, COMMAND, OPERATIONS, KNOCKDOWN, OVERHAUL, ALL_CLEAR, CLOSE_OUT, ENDED }
const PHASE_NAMES := ["출동·도착", "지휘권 확립", "진압·인명구조", "초진", "잔불정리·2차 검색", "완진 선언", "마무리", "활동 종료"]

var fire: FireSim
var units: UnitSystem
var water: WaterSystem
var rescue: RescueSystem
var rekindle: RekindleSystem
var perception: Perception
var events: SimEventLog
var phase := Phase.DISPATCH
## 단계 -> 처음 들어간 tick
var reached: Dictionary = {Phase.DISPATCH: 0}
var knockdown_tick := -1
## 완진 선언 기록 {tick, burning, embers}
var all_clear: Dictionary = {}
## 구획 index -> 2차 검색 tick
var secondary: Dictionary = {}
var end_suggested := false

var _hold_ticks: int
var _quiet_ticks: int
var _window_start := -1
var _window_burning := 0
var _burned_count := 0
var _event_index := 0
var _quiet_since := -1


func _init(p_fire: FireSim, p_units: UnitSystem, p_water: WaterSystem, p_rescue: RescueSystem, p_rekindle: RekindleSystem,
		p_perception: Perception, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	water = p_water
	rescue = p_rescue
	rekindle = p_rekindle
	perception = p_perception
	events = p_events
	_hold_ticks = roundi(params.value("knockdown_hold_s") / SimClock.TICK_DT)
	_quiet_ticks = roundi(params.value("end_suggest_quiet_s") / SimClock.TICK_DT)


func reached_tick(p: Phase) -> int:
	return int(reached.get(p, -1))


## 완진 선언 (CommandOrder "all_clear"). 한 번만. 선언 때의 실제 상태를 기록한다
func declare_all_clear(tick: int) -> bool:
	if not all_clear.is_empty() or phase < Phase.OPERATIONS:
		return false
	all_clear = {"tick": tick, "burning": fire.grid.burning.size(), "embers": rekindle.embers.size()}
	_enter(Phase.ALL_CLEAR, tick)
	events.add(tick, "all_clear_declared", {"crew": "현장지휘관"})
	_enter(Phase.CLOSE_OUT, tick)
	return true


func on_ended(tick: int) -> void:
	_enter(Phase.ENDED, tick)


func step(_dt: float, tick: int, declared: bool) -> void:
	if phase == Phase.DISPATCH and tick >= 1:
		_enter(Phase.COMMAND, tick)
	if phase == Phase.COMMAND and declared:
		_enter(Phase.OPERATIONS, tick)
	if knockdown_tick < 0 and phase >= Phase.OPERATIONS:
		_check_knockdown(tick)
	_scan_searches()
	_check_nothing_left(tick)


# --- 초진 ---

func _check_knockdown(tick: int) -> void:
	var burning := fire.grid.burning.size()
	var burned := 0
	var developed := false
	var water_used := 0.0
	for c in fire.comps:
		if c.ever_burned:
			burned += 1
		if (c.stage == Compartment.Stage.FULLY_DEVELOPED or c.stage == Compartment.Stage.FLASHOVER) and c.q > 0.0:
			developed = true
		water_used += c.water_applied_l
	# 진압으로 잡은 불만 초진 (물을 쓰지 않고 저절로 줄어든 것은 아님)
	if developed or burned > _burned_count or water_used <= 0.0 or _window_start < 0 or burning > _window_burning:
		_window_start = tick
		_window_burning = burning
		_burned_count = burned
		return
	_window_burning = mini(_window_burning, burning)
	if tick - _window_start >= _hold_ticks:
		knockdown_tick = tick
		_enter(Phase.KNOCKDOWN, tick)
		_report_knockdown(tick)
		_enter(Phase.OVERHAUL, tick)


## 화재 구획 가까이 있는 진압 조(수관을 가진 조)가 자기가 보는 방 기준으로 보고
func _report_knockdown(tick: int) -> void:
	var reporter: Crew = null
	for h in water.hoses:
		var c := units.get_crew(h.crew_id)
		if c and not c.leader.incapacitated and not c.leader.aboard:
			reporter = c
			if h.flowing:
				break
	var rooms: PackedStringArray = []
	if reporter:
		var here := fire.compartment_at(reporter.leader.level, floori(reporter.leader.pos.x), floori(reporter.leader.pos.y))
		var h := water.hose_of_crew(reporter.id)
		var target := fire.compartment_at(h.target.z, h.target.x, h.target.y) if h else null
		for c in [target, here]:
			if c and c.ever_burned and not c.display_name() in rooms:
				rooms.append(c.display_name())
	var name := "%s %d조" % [units.squads[reporter.squad_id].name, reporter.number] if reporter else "현장 대원"
	var e := {"crew": name, "rooms": ", ".join(rooms) if not rooms.is_empty() else "화점", "crew_id": reporter.id if reporter else -1}
	var h2 := water.hose_of_crew(reporter.id) if reporter else null
	if h2:
		e["room_cell"] = [h2.target.x, h2.target.y, h2.target.z]
	events.add(tick, "knockdown_reported", e)


# --- 2차 검색 ---

func _scan_searches() -> void:
	var list := events.entries
	while _event_index < list.size():
		var e: Dictionary = list[_event_index]
		_event_index += 1
		if e.type != "search_done" or knockdown_tick < 0 or int(e.tick) < knockdown_tick:
			continue
		for c in fire.comps:
			if c.display_name() == e.room and not secondary.has(c.index):
				secondary[c.index] = int(e.tick)
				events.add(int(e.tick), "secondary_search_done", {"room": e.room, "crew": e.crew})


## 2차 검색 대상 (화재 건물 구획, 인접 건물 제외)
func search_targets() -> Array[Compartment]:
	var out: Array[Compartment] = []
	for c in fire.comps:
		if not fire.is_exposure_comp(c):
			out.append(c)
	return out


# --- 종료 제안 ---


## 살아 있는 구조대상자가 건물 안에 없고 타는 칸이 없는 상태가 이어지면 한 번 종료를 제안한다
func _check_nothing_left(tick: int) -> void:
	if end_suggested or phase < Phase.OPERATIONS or phase >= Phase.ENDED:
		return
	var waiting := false
	for v in rescue.victims:
		if v.alive():
			waiting = true
	if waiting or fire.grid.burning.size() > 0:
		_quiet_since = -1
		return
	if _quiet_since < 0:
		_quiet_since = tick
	elif tick - _quiet_since >= _quiet_ticks:
		end_suggested = true
		events.add(tick, "end_suggested", {"crew": "상황실", "all_clear": not all_clear.is_empty()})


func _enter(p: Phase, tick: int) -> void:
	if p <= phase and reached.has(p):
		return
	phase = p
	if not reached.has(p):
		reached[p] = tick
		events.add(tick, "phase", {"phase": PHASE_NAMES[p], "index": p})
