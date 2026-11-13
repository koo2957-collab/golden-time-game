class_name MissionEndChecker
extends RefCounted
## 게임이 끝나는 조건 (기획안 8-3, P11-1). 시나리오 제한시간은 두지 않고 현장 상황으로 끝낸다.
##   작전 완료 / 조기 종료: 지휘관의 활동 종료 선언(CommandOrder "end"). 완진·연소·미검색 + 구조·인계·인원점검으로 정한다 (SimWorld.completion_gaps)
##   전소: 대원이 잡지 못한 채 불이 스스로 꺼지고(초진 없음) 화재 건물 가연물이 70% 이상 탐, 또는 화재 건물 구획이 기준 비율 이상 붕괴 → 자동 종료
##         (화재1 5쪽 소실 정도: 전소 70% 이상, 반소 30~70%, 부분소 그 밖 — 화재조사 및 보고규정 제16조)
##   전소 확실: 진압 없이 타는 구획이 모두 최성기·쇠퇴기이고 한동안 방수가 없음 → '결과 보기'로 그 자리에서 전소 확정 (남은 계산은 하지 않음, 2026-11-10 결정)
##   종료 제안: PhaseSystem의 end_suggested를 조건이 이어지는 동안 일정 간격으로 다시 알린다 (강제 종료 아님)
##   대원 사망은 종료 조건이 아니다.

const END_COMPLETE := "작전 완료"
const END_EARLY := "조기 종료"
const END_BURNOUT := "전소"
const END_INCOMPLETE := "미완료"

var fire: FireSim
var collapse: CollapseSystem
var phases: PhaseSystem
var events: SimEventLog

var _loss_ratio: float
var _half_ratio: float
var _collapse_ratio: float
var _no_water_ticks: int
var _repeat_ticks: int
var _quiet_ticks: int
## 마지막으로 방수(물이 구획에 닿음)를 본 틱과 그때의 누적 방수량
var _last_water_tick := 0
var _water_total := 0.0
var _last_suggest_tick := -1
## 조건이 처음 이어지기 시작한 틱 (종료 제안 반복용, PhaseSystem과 같은 조건)
var _quiet_since := -1


func _init(p_fire: FireSim, p_collapse: CollapseSystem, p_phases: PhaseSystem, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	collapse = p_collapse
	phases = p_phases
	events = p_events
	_loss_ratio = params.value("burnout_loss_ratio")
	_half_ratio = params.value("half_loss_ratio")
	_collapse_ratio = params.value("burnout_collapse_ratio")
	_no_water_ticks = roundi(params.value("burnout_no_water_s") / SimClock.TICK_DT)
	_repeat_ticks = roundi(params.value("end_suggest_repeat_s") / SimClock.TICK_DT)
	_quiet_ticks = roundi(params.value("end_suggest_quiet_s") / SimClock.TICK_DT)


## 매 틱. 전소면 종료 사유를 돌려준다 (없으면 "")
func step(tick: int, victims_waiting: bool) -> String:
	var water := 0.0
	for c in fire.comps:
		water += c.water_applied_l
	if water > _water_total + 0.001:
		_last_water_tick = tick
	_water_total = water
	_repeat_suggestion(tick, victims_waiting)
	if burned_out():
		return END_BURNOUT
	return ""


## 화재 건물 구획 (인접 건물 제외)
func building_comps() -> Array[Compartment]:
	var out: Array[Compartment] = []
	for c in fire.comps:
		if not fire.is_exposure_comp(c):
			out.append(c)
	return out


## 화재 건물 가연물 소실 비율 (0~1, 인접 건물 제외)
func loss_ratio() -> float:
	var init := 0.0
	var rem := 0.0
	for c in building_comps():
		init += c.fuel_initial
		rem += c.fuel_remaining
	return 1.0 - rem / init if init > 0.0 else 0.0


## 소실 정도 (화재1 5쪽): 전소 / 반소 / 부분소
func loss_class() -> String:
	var r := loss_ratio()
	if r >= _loss_ratio or collapsed_ratio() >= _collapse_ratio:
		return "전소"
	return "반소" if r >= _half_ratio else "부분소"


## 화재 건물 구획 중 붕괴한 비율 (0~1)
func collapsed_ratio() -> float:
	var comps := building_comps()
	if comps.is_empty():
		return 0.0
	var n := 0
	for c in comps:
		if collapse.collapsed.has(c.index):
			n += 1
	return float(n) / comps.size()


func _fire_out() -> bool:
	if fire.grid.burning.size() > 0:
		return false
	# 남은 미연소가스는 아주 조금씩 계속 타므로(q > 0) 가연물 칸의 연소(q_potential)로 본다
	for c in fire.comps:
		if c.q_potential > 0.0:
			return false
	return true


## 전소로 끝남: 붕괴 비율 이상, 또는 대원이 초진하지 못한 채 불이 스스로 꺼졌고 건물이 70% 이상 탐
## (불이 스스로 꺼졌어도 반소·부분소면 끝내지 않는다 — 종료 제안과 지휘관 선언으로 마친다)
func burned_out() -> bool:
	if collapsed_ratio() >= _collapse_ratio:
		return true
	if phases.knockdown_tick >= 0 or not _fire_out():
		return false
	return loss_ratio() >= _loss_ratio


## 전소 확실 ('결과 보기' 버튼): 초진 전, 불이 붙은 구획이 모두 최성기·쇠퇴기 이후이고 최성기가 하나 이상, 한동안 방수 없음
func burnout_certain(tick: int) -> bool:
	if phases.knockdown_tick >= 0 or tick - _last_water_tick < _no_water_ticks:
		return false
	var developed := false
	for c in building_comps():
		if not c.ever_burned:
			continue
		match c.stage:
			Compartment.Stage.FULLY_DEVELOPED:
				developed = true
			Compartment.Stage.DECAY, Compartment.Stage.BURNT_OUT, Compartment.Stage.EXTINGUISHED, Compartment.Stage.NONE:
				pass
			_:
				return false
	return developed


## 화재·검색만 본 종료 종류 (예전 조건). 실제 종료 종류는 SimWorld.completion_gaps()가 인원점검·인계까지 보고 정한다 (2026-11-13)
func declared_type(unsearched: int) -> String:
	if not phases.all_clear.is_empty() and fire.grid.burning.size() == 0 and unsearched == 0:
		return END_COMPLETE
	return END_EARLY


## 종료 제안을 조건이 이어지는 동안 반복 (첫 제안은 PhaseSystem)
func _repeat_suggestion(tick: int, victims_waiting: bool) -> void:
	if not phases.end_suggested or phases.phase >= PhaseSystem.Phase.ENDED:
		return
	if victims_waiting or fire.grid.burning.size() > 0:
		_quiet_since = -1
		_last_suggest_tick = -1
		return
	if _quiet_since < 0:
		_quiet_since = tick
	if _last_suggest_tick < 0:
		_last_suggest_tick = tick
		return
	if tick - _last_suggest_tick >= _repeat_ticks and tick - _quiet_since >= _quiet_ticks:
		_last_suggest_tick = tick
		events.add(tick, "end_suggested", {"crew": "상황실", "all_clear": not phases.all_clear.is_empty(), "repeat": true})
