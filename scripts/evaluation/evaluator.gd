class_name Evaluator
extends RefCounted
## 활동이 끝난 뒤 SOP 판정·평가·디브리핑 자료를 만든다.
##   규칙 (data/sop/rules.json): 시나리오 evaluation.rules가 고른 규칙마다 check 함수로 0~1 점수와 설명을 낸다
##   근거: 2025 재난현장표준작전절차 조항·원문(sop, text) + 소방전술 원리(tactic, tactic_text)
##   축: 대원 안전 → 인명구조 → 재산 보호 → 화재 안정화 → 지휘 절차 (SOP 106-1.1② 순서 = 가중치 순서)
##   등급: S~D. 규칙의 cap 기준에 못 미치면 등급 상한 (대원 안전 108-1.2, 인명구조 최우선 214-2.1)
##   디브리핑 (113-2.1): ① 계획 ② 실제(타임라인·숨은 정보 공개) ③ 왜(판단 → 결과 → 조항) ④ 다음에는(약점·강점)
## 게임 중에는 점수를 보여 주지 않는다.

const RULES_PATH := "res://data/sop/rules.json"
const REPORT_DIR := "user://reports"
const GRADE_ORDER := ["S", "A", "B", "C", "D"]
## 잘한 점으로 보는 점수 / 고칠 점으로 보는 점수
const STRENGTH_MIN := 0.85
const WEAKNESS_MAX := 0.6
const MAX_STRENGTHS := 4
const MAX_WEAKNESSES := 3
## 타임라인에 올리는 사건
const TIMELINE_TYPES: Array[String] = [
	"ignition", "flashover", "backdraft", "command_declared", "strategy_set", "entry_ordered", "crew_entered",
	"face_seen", "site_info_found", "clue_found", "statement", "report_updated", "victim_found", "victim_rescued",
	"victim_state", "victim_recovered", "ff_down", "ff_rescued", "air_alarm", "withdraw", "squad_staged",
	"squad_committed", "support_requested", "division_set", "span_warning", "command_post", "ember_spotted",
	"overhaul_done", "rekindle", "mayday", "emergency_cleared", "evacuation_ordered", "par_done", "role_assigned",
	"rit_deployed", "entry_factors", "activity_ended",
]

var sim: SimWorld
var _params: Dictionary = {}


## 평가 결과 (디브리핑·저장용 사전)
static func evaluate(p_sim: SimWorld) -> Dictionary:
	var e := Evaluator.new()
	e.sim = p_sim
	return e._run()


## 결과를 user://reports/에 저장하고 경로를 돌려준다 (실패하면 빈 문자열)
static func save(report: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
	var path := "%s/%s_%s.json" % [REPORT_DIR, report.get("scenario_id", "scenario"), stamp]
	report["saved_at"] = Time.get_datetime_string_from_system(false, true)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(report, "  "))
	return path


func _run() -> Dictionary:
	var data: Variant = JsonData.load_file(RULES_PATH)
	if not data is Dictionary:
		return {}
	var cfg: Dictionary = sim.scenario.get("evaluation", {})
	var overrides: Dictionary = cfg.get("params", {})
	var library := {}
	for r: Dictionary in data.get("rules", []):
		library[str(r.id)] = r
	var results: Array[Dictionary] = []
	for id in cfg.get("rules", []):
		if not library.has(str(id)):
			push_error("SOP 규칙 '%s'가 rules.json에 없습니다." % id)
			continue
		var rule: Dictionary = library[str(id)]
		_params = rule.get("params", {}).duplicate()
		_params.merge(overrides.get(str(id), {}), true)
		var out: Dictionary = call("_check_" + str(rule.check))
		var res := {
			"id": rule.id, "sop": rule.sop, "title": rule.title, "axis": rule.axis, "type": rule.get("type", ""),
			"source": rule.get("source", ""), "text": rule.get("text", ""), "advice": rule.get("advice", ""),
			"tactic": rule.get("tactic", ""), "tactic_text": rule.get("tactic_text", ""),
			"cap": rule.get("cap", {}),
			"applicable": not out.is_empty(),
			"score": float(out.get("score", 0.0)),
			"detail": str(out.get("detail", "해당 없음")),
		}
		res["violated"] = not res.cap.is_empty() and res.applicable and res.score < float(res.cap.get("below", 0.5))
		results.append(res)
	var axes: Array[Dictionary] = []
	var total_w := 0.0
	var total := 0.0
	for a: Dictionary in data.get("axes", []):
		var scores: Array[float] = []
		for r in results:
			if r.axis == a.id and r.applicable:
				scores.append(r.score)
		var axis := {"id": a.id, "name": a.name, "weight": float(a.weight), "applicable": not scores.is_empty(), "score": 0.0}
		if not scores.is_empty():
			var sum := 0.0
			for s in scores:
				sum += s
			axis.score = sum / scores.size()
			total += axis.weight * axis.score
			total_w += axis.weight
		axes.append(axis)
	var points := 100.0 * total / total_w if total_w > 0.0 else 0.0
	var grade: String = grade_for(points, data.get("grades", []), false, "D")[0]
	var capped := false
	var cap_reasons: Array = []
	for r in results:
		if r.violated:
			var g := grade_for(points, data.get("grades", []), true, str(r.cap.get("grade", "C")))
			if g[1] and GRADE_ORDER.find(str(g[0])) > GRADE_ORDER.find(grade):
				grade = g[0]
			if g[1]:
				capped = true
				cap_reasons.append("%s (SOP %s) → 최고 %s" % [r.title, r.sop, r.cap.get("grade", "C")])
	return {
		"scenario_id": str(sim.scenario.get("id", "")),
		"rules_version": int(data.get("rules_version", 1)),
		"basis": str(data.get("basis", "")),
		"scenario_title": str(sim.scenario.get("title", "")),
		"seed": sim.rng_seed,
		"mode": sim.play_mode,
		"difficulty": sim.tactical.level_name,
		"end_reason": sim.end_reason,
		"end_time_s": sim.ended_tick * SimClock.TICK_DT,
		"points": snappedf(points, 0.1),
		"grade": grade,
		"capped": capped,
		"cap_reasons": cap_reasons,
		"axes": axes,
		"rules": results,
		"plan": _plan(cfg),
		"timeline": _timeline(),
		"decisions": _decisions(),
		"timeline_ticks": _timeline_ticks(),
		"replayable": sim.replayable,
		"instructor_params": InstructorSettings.changed_params(),
		"hidden": _hidden(),
		"strengths": _strengths(results),
		"weaknesses": _weaknesses(results),
	}


## 점수 → 등급. 중대 위반이면 cap보다 좋은 등급을 줄 수 없다 (SOP 108-1.2). [등급, 상한 적용 여부]
static func grade_for(points: float, grades: Array, violated: bool, cap: String) -> Array:
	var grade := "D"
	for g: Array in grades:
		if points >= float(g[0]):
			grade = str(g[1])
			break
	if violated and GRADE_ORDER.find(grade) < GRADE_ORDER.find(cap):
		return [cap, true]
	return [grade, false]


# --- 판정 함수: {score, detail}. 해당 없으면 빈 사전 ---

func _check_ff_down() -> Dictionary:
	var downs := sim.events.of_type("ff_down")
	if downs.is_empty():
		return {"score": 1.0, "detail": "행동 불능 대원 없음"}
	var names: PackedStringArray = []
	for e in downs:
		names.append("%s %s(%s)" % [_t(e.tick), e.crew, e.reason])
	return {"score": 0.0, "detail": "행동 불능 %d명: %s" % [downs.size(), ", ".join(names)]}


func _check_air_exit() -> Dictionary:
	var list := sim.recorder.air_exposures
	if list.is_empty():
		return {}
	var sum := 0.0
	var worst := 0.0
	var worst_ff := -1
	for x in list:
		var end: int = x.end_tick if x.end_tick >= 0 else sim.ended_tick
		var dur: float = (end - x.start_tick) * SimClock.TICK_DT
		sum += _linear(dur, _params.good_s, _params.bad_s)
		if dur > worst:
			worst = dur
			worst_ff = x.ff
	var ff := sim.units.firefighters[worst_ff] if worst_ff >= 0 else null
	return {"score": sum / list.size(), "detail": "공기 경보 %d건, 경보 후 건물 안에 가장 오래 있던 시간 %d초%s (기준 %d초)" % [
		list.size(), roundi(worst), " — %s" % ff.name if ff else "", int(_params.good_s)]}


func _check_withdraw() -> Dictionary:
	var sets := sim.events.of_type("strategy_set").filter(func(e: Dictionary) -> bool: return e.strategy == "방어")
	if sets.is_empty():
		return {}
	var e: Dictionary = sets[0]
	var start: int = e.tick / SimRecorder.EVERY_TICKS
	var rec := sim.recorder
	for i in range(start, rec.seconds()):
		if rec.indoor[i] == 0:
			var dur := float(i - start)
			return {"score": _linear(dur, _params.good_s, _params.bad_s), "detail": "방어 전환(%s) 후 %d초 만에 내부 대원 철수 완료" % [_t(e.tick), roundi(dur)]}
	return {"score": 0.0, "detail": "방어 전환(%s) 후 끝까지 건물 안에 대원이 남음" % _t(e.tick)}


func _check_command_post() -> Dictionary:
	var posts := sim.command.survey.post_log
	if posts.is_empty():
		return {}
	var sum := 0.0
	var parts: PackedStringArray = []
	for p in posts:
		var o: float = {"좋음": 1.0, "보통": 0.6}.get(p.observe, 0.2)
		var s: float = {"안전": 1.0, "주의": 0.6}.get(p.safety, 0.0)
		var r := 1.0 if p.route == "양호" else 0.0
		sum += (o + s + r) / 3.0
		parts.append("%s 관찰 %s · 안전 %s(%.1fm) · 동선 %s" % [_t(p.tick), p.observe, p.safety, p.distance_m, p.route])
	return {"score": sum / posts.size(), "detail": "; ".join(parts)}


func _check_survival() -> Dictionary:
	var victims := sim.rescue.victims
	if victims.is_empty():
		return {}
	var sum := 0.0
	var parts: PackedStringArray = []
	for v in victims:
		var s := 0.0
		if v.state == Victim.State.RESCUED:
			s = 1.0 if v.state_at_rescue == Victim.State.CONSCIOUS else float(_params.unconscious)
		sum += s
		parts.append("%s %s" % [v.label(), _victim_outcome(v)])
	return {"score": sum / victims.size(), "detail": ", ".join(parts)}


func _check_rescue_time() -> Dictionary:
	var victims := sim.rescue.victims
	if victims.is_empty():
		return {}
	var sum := 0.0
	var parts: PackedStringArray = []
	for v in victims:
		if v.state == Victim.State.RESCUED:
			var t := v.rescued_tick * SimClock.TICK_DT
			sum += _linear(t, _params.good_s, _params.bad_s)
			parts.append("%s %s" % [v.label(), _t(v.rescued_tick)])
		else:
			parts.append("%s 구조 못함" % v.label())
	return {"score": sum / victims.size(), "detail": "%s (기준 %d분 안)" % [", ".join(parts), int(_params.good_s / 60)]}


## 선착 차량 배치 (SOP 200-3.1.1): 시나리오에 배치 보기가 있을 때만
func _check_placement() -> Dictionary:
	if Placement.options(sim).is_empty():
		return {}
	var p := sim.command.placement
	if p.is_empty():
		return {"score": 0.5, "detail": "배치를 고르지 않음 (편성 기본 위치)"}
	return {"score": float(p.score), "detail": "%s — %s" % [p.name, p.feedback]}


## 구조 후 응급처치 (SOP 400-3.2, 402): 구조된 환자마다 구조 → 처치 시작 시간. 긴급 환자 처치 지연 사망은 0점
func _check_ems_treat() -> Dictionary:
	var ems := sim.ems
	if ems.patients.is_empty():
		return {}
	var sum := 0.0
	var parts: PackedStringArray = []
	for p in ems.patients:
		var v := sim.rescue.victims[p.victim_id]
		if v.state == Victim.State.DEAD:
			parts.append("%s(%s) 처치 지연으로 사망" % [v.label(), ems.triage_name(p)])
			continue
		if p.treat_start_tick < 0:
			parts.append("%s(%s) 처치 못함" % [v.label(), ems.triage_name(p)])
			continue
		var wait := (p.treat_start_tick - v.rescued_tick) * SimClock.TICK_DT
		var good: float = _params.good_s if p.triage == EmsSystem.Triage.URGENT else _params.good_s * 2.0
		sum += _linear(wait, good, _params.bad_s)
		parts.append("%s(%s) 구조 %d초 뒤 처치" % [v.label(), ems.triage_name(p), roundi(wait)])
	return {"score": sum / ems.patients.size(), "detail": ", ".join(parts)}


## 처치 후 이송 (SOP 400-3.3·3.4): 구조 → 이송 출발 시간
func _check_ems_transport() -> Dictionary:
	var ems := sim.ems
	if ems.patients.is_empty():
		return {}
	var sum := 0.0
	var parts: PackedStringArray = []
	for p in ems.patients:
		var v := sim.rescue.victims[p.victim_id]
		if p.depart_tick < 0:
			parts.append("%s 이송 못함" % v.label())
			continue
		var t := (p.depart_tick - v.rescued_tick) * SimClock.TICK_DT
		sum += _linear(t, _params.good_s, _params.bad_s)
		parts.append("%s 구조 %d분 %02d초 뒤 이송 출발%s" % [v.label(), roundi(t) / 60, roundi(t) % 60, " · %s 병원 인계" % _t(p.handover_tick) if p.handover_tick >= 0 else ""])
	return {"score": sum / ems.patients.size(), "detail": ", ".join(parts)}


func _check_search_order() -> Dictionary:
	var origin := _origin_room()
	var searched: Array[Compartment] = []
	for c in sim.fire.comps:
		if c.searched_tick >= 0:
			searched.append(c)
	if searched.is_empty():
		return {} if sim.rescue.victims.is_empty() else {"score": 0.0, "detail": "인명검색을 하지 않음"}
	if origin == null or searched.size() < 2:
		return {}  # 한 곳만 검색하면 순서를 판정할 수 없다
	searched.sort_custom(func(a: Compartment, b: Compartment) -> bool: return a.searched_tick < b.searched_tick)
	var reported := sim.command.survey.reported_rooms
	var order: Array[Compartment] = []
	for c in searched:
		if not reported.has(c.id):  # 위치가 알려진 구조대상자 방은 예외
			order.append(c)
	var names: PackedStringArray = []
	for c in searched:
		names.append("%s(%s)" % [c.display_name(), _category_name(_category(c, origin))])
	var pairs := 0
	var inversions := 0
	for i in order.size():
		for j in range(i + 1, order.size()):
			pairs += 1
			if _category(order[i], origin) > _category(order[j], origin):
				inversions += 1
	var score := 1.0 - float(inversions) / pairs if pairs > 0 else 1.0
	return {"score": score, "detail": "검색 순서: %s%s" % [" → ".join(names), " (순서 어긋남 %d건)" % inversions if inversions > 0 else ""]}


func _check_spread() -> Dictionary:
	var origin := _origin_room()
	var spread: PackedStringArray = []
	var flashed: PackedStringArray = []
	for c in sim.fire.comps:
		if c.ever_burned and c != origin and not sim.fire.is_exposure_comp(c):
			spread.append(c.display_name())
		if c.flashed:
			flashed.append(c.display_name())
	var bad := float(_params.get("bad_rooms", 4))
	var detail := "화점실 밖으로 번진 구획 %d곳%s" % [spread.size(), ": " + ", ".join(spread) if not spread.is_empty() else ""]
	if not flashed.is_empty():
		detail += " · 플래시오버: " + ", ".join(flashed)
	return {"score": clampf(1.0 - spread.size() / bad, 0.0, 1.0), "detail": detail}


## 인접 건물 연소 확대 방지 (SOP 214-2.4): 가열이 시작되지 않았으면 해당 없음
func _check_exposure() -> Dictionary:
	var ex := sim.exposure
	if not ex.has_exposure() or ex.peak < float(_params.get("min_ratio", 0.2)):
		return {}
	var name := ex.exposure_name()
	if not ex.ignited.is_empty():
		var e: Dictionary = sim.events.of_type("exposure_ignition")[0]
		return {"score": 0.0, "detail": "%s %s으로 연소 확대 — 경계관창을 두지 않음" % [_t(e.tick), e.target]}
	var pct := roundi(ex.peak * 100.0)
	if ex.protected_tick < 0:
		return {"score": 0.3, "detail": "%s 외벽 가열 최고 %d%% — 경계관창 없이 불이 옮겨 붙지 않았을 뿐" % [name, pct]}
	return {"score": clampf(1.0 - maxf(0.0, ex.peak - 0.4) / 0.6, 0.4, 1.0),
		"detail": "%s 외벽 가열 최고 %d%% · 경계관창 %s부터" % [name, pct, _t(ex.protected_tick)]}


## 가스 차단 (SOP 214-2.2): 가스 시설이 없으면 해당 없음
func _check_gas() -> Dictionary:
	var g := sim.gas
	if not g.has_gas():
		return {}
	if g.exploded:
		return {"score": 0.0, "detail": "밸브가 열린 채 가스 폭발 (%s)" % g.valve_text}
	if g.closed_tick < 0:
		return {"score": 0.1, "detail": "%s를 끝까지 차단하지 않음" % g.valve_text}
	var t := g.closed_tick * SimClock.TICK_DT
	return {"score": _linear(t, _params.good_s, _params.bad_s), "detail": "%s 차단 %s (기준 %d분 이내)" % [g.valve_text, _t(g.closed_tick), int(_params.good_s / 60)]}


## 붕괴 징후 후 철수 (SOP 205-3.5, 214-2.5): 징후가 없으면 해당 없음
func _check_collapse() -> Dictionary:
	var first := sim.collapse.first_sign_tick()
	if first < 0:
		return {}
	for e in sim.events.of_type("ff_down"):
		if e.reason == "붕괴":
			return {"score": 0.0, "detail": "붕괴 징후(%s) 뒤 철수하지 않아 대원이 붕괴에 휘말림" % _t(first)}
	var start: int = first / SimRecorder.EVERY_TICKS
	var rec := sim.recorder
	for i in range(start, rec.seconds()):
		if rec.indoor[i] == 0:
			var dur := float(i - start)
			return {"score": _linear(dur, _params.good_s, _params.bad_s), "detail": "붕괴 징후(%s) 후 %d초 만에 내부 대원 철수" % [_t(first), roundi(dur)]}
	return {"score": 0.0, "detail": "붕괴 징후(%s) 후에도 건물 안에 대원이 남음" % _t(first)}


func _check_water_damage() -> Dictionary:
	var total := 0.0
	for c in sim.fire.comps:
		total += c.water_damage_l
	return {"score": _linear(total, _params.good_l, _params.bad_l), "detail": "수손 물량 약 %dL (기준 %dL 이하)" % [roundi(total), int(_params.good_l)]}


func _check_extinguish() -> Dictionary:
	var rec := sim.recorder
	if rec.seconds() == 0:
		return {}
	if rec.burning[rec.seconds() - 1] > 0 or sim.fire.grid.burning.size() > 0:
		return {"score": 0.0, "detail": "활동 종료 때 아직 연소 중 (완진 못함)"}
	var last := -1
	for i in rec.seconds():
		if rec.burning[i] > 0:
			last = i
	var t := float(last + 1)
	return {"score": _linear(t, _params.good_s, _params.bad_s), "detail": "완진 %s (기준 %d분)" % [_t(roundi(t / SimClock.TICK_DT)), int(_params.good_s / 60)]}


func _check_overhaul() -> Dictionary:
	var rk := sim.rekindle
	if rk.embers_created == 0:
		return {}
	var left := rk.embers.size()
	if rk.rekindles > 0:
		return {"score": 0.0, "detail": "재발화 %d건 — 숨은 불씨를 정리하지 못함" % rk.rekindles}
	var score := float(rk.embers_cleared) / (rk.embers_cleared + left) if rk.embers_cleared + left > 0 else 1.0
	return {"score": score, "detail": "숨은 불씨 %d곳 중 잔불정리로 %d곳 제거, 종료 때 %d곳 남음" % [rk.embers_created, rk.embers_cleared, left]}


func _check_rit() -> Dictionary:
	var first := _first_entry_tick()
	if first < 0:
		return {}
	var assigned := -1
	for r in sim.command.safety.role_log:
		if r.role == SafetySystem.Role.RIT:
			assigned = r.tick
			break
	if assigned < 0:
		return {"score": 0.0, "detail": "RIT를 편성하지 않음 (첫 진입 %s)" % _t(first)}
	if assigned <= first:
		return {"score": 1.0, "detail": "첫 진입(%s) 전 %s에 RIT 편성" % [_t(first), _t(assigned)]}
	var late := (assigned - first) * SimClock.TICK_DT
	return {"score": 0.6 if late <= float(_params.late_s) else 0.3, "detail": "첫 진입(%s) 뒤 %d초 지나 RIT 편성 (%s)" % [_t(first), roundi(late), _t(assigned)]}


func _check_emergency() -> Dictionary:
	var safety := sim.command.safety
	if safety.mayday_log.is_empty() and safety.evacuation_log.is_empty():
		return {}
	var scores: Array[float] = []
	var parts: PackedStringArray = []
	for m in safety.mayday_log:
		var t0: int = m.tick
		var resp := -1
		for c in sim.command_log.entries:
			if c is EquipmentCommand and c.action == "rescue_ff" and c.tick >= t0:
				resp = c.tick
				break
		for d in safety.rit_deploy_log:
			if d.tick >= t0 and (resp < 0 or d.tick < resp):
				resp = d.tick
		if resp < 0:
			scores.append(0.0)
			parts.append("%s 긴급탈출 선언 — 구출 투입 없음" % _t(t0))
		else:
			var dt := (resp - t0) * SimClock.TICK_DT
			scores.append(_linear(dt, _params.rescue_good_s, _params.rescue_bad_s))
			parts.append("%s 긴급탈출 선언 — %d초 뒤 구출 투입" % [_t(t0), roundi(dt)])
	for t0 in safety.evacuation_log:
		var par := -1
		for p in safety.par_log:
			if p.tick >= t0:
				par = p.tick
				break
		if par < 0:
			scores.append(0.0)
			parts.append("%s 긴급탈출 지시 — 인원점검 없음" % _t(t0))
		else:
			var dt := (par - t0) * SimClock.TICK_DT
			scores.append(_linear(dt, _params.par_good_s, _params.par_bad_s))
			parts.append("%s 긴급탈출 지시 — %d초 뒤 인원점검" % [_t(t0), roundi(dt)])
	var sum := 0.0
	for x in scores:
		sum += x
	return {"score": sum / scores.size(), "detail": "; ".join(parts)}


func _check_officer() -> Dictionary:
	var first := _first_entry_tick()
	if first < 0:
		return {}
	for r in sim.command.safety.role_log:
		if r.role == SafetySystem.Role.OFFICER:
			if r.tick <= first:
				return {"score": 1.0, "detail": "첫 진입 전 %s에 현장안전담당 지정" % _t(r.tick)}
			return {"score": 0.5, "detail": "첫 진입(%s) 뒤 %s에 현장안전담당 지정" % [_t(first), _t(r.tick)]}
	return {"score": 0.0, "detail": "현장안전담당을 지정하지 않음"}


func _check_entry_judgment() -> Dictionary:
	var checks := sim.command.entry_checks
	if checks.is_empty():
		return {}
	var risky := 0
	var parts: PackedStringArray = []
	for c in checks:
		var f: PackedStringArray = c.factors
		var sign := false
		for x in f:
			if x.begins_with("⑧"):
				sign = true
		if sign:
			risky += 1
		parts.append("%s %s 진입 명령%s" % [_t(c.tick), c.squad, " — " + " · ".join(f) if not f.is_empty() else " — 해당 요소 없음"])
	return {"score": maxf(0.0, 1.0 - 0.5 * risky), "detail": "; ".join(parts)}


func _check_water_supply() -> Dictionary:
	var squads := sim.units.squads
	if squads.is_empty() or sim.building.hydrants.is_empty():
		return {}
	var tanker: Vehicle = null
	for v in sim.units.vehicles_of_squad(0):
		if v.transfer_lpm > 0.0:
			tanker = v
	if tanker == null:
		return {}
	var name := tanker.display_name(squads[0].name)
	var supply := -1
	var hydrant := -1
	for e in sim.events.of_type("supply_connected"):
		if e.vehicle == name and supply < 0:
			supply = e.tick
	for e in sim.events.of_type("hydrant_connected"):
		if e.vehicle == name and hydrant < 0:
			hydrant = e.tick
	var a := _linear(supply * SimClock.TICK_DT, _params.good_s, _params.bad_s) if supply >= 0 else 0.0
	var b := _linear(hydrant * SimClock.TICK_DT, _params.good_s, _params.bad_s) if hydrant >= 0 else 0.0
	return {"score": (a + b) / 2.0, "detail": "%s — 펌프차 급수 %s, 소화전 점령 %s (기준 %d분 안)" % [
		name, _t(supply) if supply >= 0 else "안 함", _t(hydrant) if hydrant >= 0 else "안 함", int(_params.good_s / 60)]}


func _check_watch() -> Dictionary:
	var rk := sim.rekindle
	var out := sim.fire.grid.burning.size() == 0
	if not out:
		return {}
	var w := sim.command.watch
	if w != "":
		return {"score": 1.0, "detail": "재발화 감시: %s" % w}
	if rk.embers.is_empty():
		return {"score": 0.5, "detail": "감시를 지정하지 않음 (남은 불씨는 없음)"}
	return {"score": 0.0, "detail": "불씨 %d곳이 남았는데 감시를 지정하지 않음" % rk.embers.size()}


func _check_par_end() -> Dictionary:
	if _first_entry_tick() < 0:
		return {}
	var rec := sim.recorder
	var last_inside := -1
	for i in rec.seconds():
		if rec.indoor[i] > 0:
			last_inside = i
	var last_tick := (last_inside + 1) * SimRecorder.EVERY_TICKS
	var pars := sim.command.safety.par_log
	if pars.is_empty():
		return {"score": 0.0, "detail": "인원점검을 하지 않음"}
	var final: Dictionary = pars[-1]
	if last_inside >= rec.seconds() - 1:
		return {"score": 0.2, "detail": "종료 때 아직 건물 안에 대원이 있음 (마지막 인원점검 %s)" % _t(final.tick)}
	if final.tick >= last_tick:
		return {"score": 1.0, "detail": "대원이 모두 나온 뒤 %s 인원점검%s" % [_t(final.tick), "" if final.missing == 0 else " (미확인 %d명)" % final.missing]}
	return {"score": 0.4, "detail": "마지막 인원점검(%s)이 대원이 모두 나오기(%s) 전" % [_t(final.tick), _t(last_tick)]}


func _check_declare_time() -> Dictionary:
	var cmd := sim.command
	if not cmd.declared():
		return {"score": 0.0, "detail": "지휘권을 선언하지 않음"}
	var t := cmd.command_tick * SimClock.TICK_DT
	return {"score": _linear(t, _params.good_s, _params.bad_s), "detail": "지휘권 선언 %s (기준 %d분 안)" % [_t(cmd.command_tick), int(_params.good_s / 60)]}


func _check_report_accuracy() -> Dictionary:
	var cmd := sim.command
	if cmd.report.is_empty():
		return {"score": 0.0, "detail": "최초 상황보고를 하지 않음"}
	var correct := 0
	var scored := 0
	var wrong: PackedStringArray = []
	for it: Dictionary in cmd.report.items:
		if not it.scored or it.name == "전략":
			continue
		scored += 1
		if it.correct:
			correct += 1
		else:
			wrong.append("%s: '%s' → 확인 가능했던 사실 '%s'" % [it.name, it.answer, it.truth])
	var detail := "%d/%d 항목 일치" % [correct, scored]
	if not wrong.is_empty():
		detail += " — " + "; ".join(wrong)
	return {"score": float(correct) / scored if scored > 0 else 0.0, "detail": detail}


func _check_strategy_fit() -> Dictionary:
	var cmd := sim.command
	if cmd.report.is_empty():
		return {"score": 0.0, "detail": "전략을 선언하지 않음"}
	for it: Dictionary in cmd.report.items:
		if it.name == "전략":
			return {"score": 1.0 if it.correct else 0.0, "detail": "선언한 전략 '%s', 그때 상황에 맞는 전략 '%s'" % [it.answer, it.truth]}
	return {}


func _check_survey() -> Dictionary:
	var survey := sim.command.survey
	var total := survey.face_keys().size()
	var seen := survey.faces_seen.size()
	var score := 0.6 * seen / maxf(1.0, total)
	var known := survey.known_hazards()
	var reported: Array[String] = []
	if not sim.command.report.is_empty():
		for it: Dictionary in sim.command.report.items:
			if it.name == "위험 요소":
				for h in str(it.answer).split(", "):
					reported.append(h)
	for u in sim.command.report_updates:
		for it: Dictionary in u.items:
			if it.name == "위험 요소":
				for h in str(it.answer).split(", "):
					reported.append(h)
	var missing: PackedStringArray = []
	for h in known:
		if not h in reported:
			missing.append(h)
	if known.is_empty():
		score += 0.4 * seen / maxf(1.0, total)
	elif missing.is_empty():
		score += 0.4
	var detail := "확인한 면 %d/%d" % [seen, total]
	if not known.is_empty():
		detail += " · 확인한 위험 요소 %s %s" % [", ".join(PackedStringArray(known)), "보고함" if missing.is_empty() else "보고 안 함 (보완 보고 필요)"]
	return {"score": score, "detail": detail}


func _check_witness_check() -> Dictionary:
	var misleading: PackedStringArray = []
	for w in sim.command.survey.witnesses:
		for q: String in w.asked:
			var st: Dictionary = w.statements[q]
			if not bool(st.get("reliable", true)):
				misleading.append("%s: \"%s\"" % [w.label(), st.get("text", "")])
	if misleading.is_empty():
		return {}
	var all_found := true
	for v in sim.rescue.victims:
		if not v.discovered:
			all_found = false
	return {"score": 1.0 if all_found else 0.0, "detail": "틀린 진술을 들음 — %s. %s" % [
		"; ".join(misleading), "그래도 구조대상자를 모두 찾음" if all_found else "찾지 못한 구조대상자가 남음"]}


func _check_span() -> Dictionary:
	var rec := sim.recorder
	var ideal := sim.command.org.span_ideal
	var over := 0
	var peak := 0
	for i in rec.seconds():
		peak = maxi(peak, rec.direct[i])
		if rec.direct[i] > ideal:
			over += 1
	if peak <= ideal:
		return {}
	return {"score": _linear(over, _params.good_s, _params.bad_s), "detail": "직접 지휘가 적정(%d)을 넘은 시간 %d초, 최대 %d" % [ideal, over, peak]}


# --- 디브리핑 자료 ---

## ① 무엇을 계획했나
func _plan(cfg: Dictionary) -> Dictionary:
	var cmd := sim.command
	var items: Array = []
	if not cmd.report.is_empty():
		for it: Dictionary in cmd.report.items:
			items.append({"no": it.no, "name": it.name, "answer": it.answer, "truth": it.truth, "scored": it.scored, "correct": it.correct})
	var org: PackedStringArray = []
	for e in sim.events.of_type("division_set"):
		org.append("%s %s 단위대 (지휘 %s, 소속 %s)" % [_t(e.tick), e.division, e.supervisor, e.squads])
	var strategies: PackedStringArray = []
	for e in sim.events.of_type("strategy_set"):
		strategies.append("%s %s" % [_t(e.tick), e.strategy])
	return {
		"objectives": cfg.get("objectives", []),
		"end_state": str(cfg.get("end_state", "")),
		"declared": "%s (%s 전략)" % [_t(cmd.command_tick), CommandSystem.STRATEGY_NAMES[cmd.report.get("strategy_answer", 0)]] if cmd.declared() else "선언하지 않음",
		"report_items": items,
		"strategy_changes": Array(strategies),
		"organization": Array(org),
		"support": "%s %s" % [_t(cmd.resources.support_tick), cmd.resources.support_level] if cmd.resources.support_level != "" else "요청하지 않음",
	}


## ② 실제로 무슨 일이: 주요 사건
func _timeline() -> Array:
	var out: Array = []
	for e in sim.events.entries:
		if e.type in TIMELINE_TYPES:
			out.append(SimEventLog.describe(e))
	return out


## 주요 의사결정과 그때 알던 정보 (SOP 111-2.2)
func _decisions() -> Array:
	var out: Array = []
	for d in sim.command.decisions:
		out.append({"time": _t(d.tick), "decision": d.decision, "context": d.context})
	return out


func _first_entry_tick() -> int:
	var e := sim.events.of_type("crew_entered")
	return int(e[0].tick) if not e.is_empty() else -1


func _timeline_ticks() -> Array:
	var out: Array = []
	for e in sim.events.entries:
		if e.type in TIMELINE_TYPES:
			out.append(e.tick)
	return out


## ② 숨은 정보 공개: 구조대상자 실제 위치·결과, 진술의 진위, 면 정보, 구획별 화재
func _hidden() -> Dictionary:
	var victims: Array = []
	for v in sim.rescue.victims:
		var room := sim.fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
		victims.append("%s — 실제 위치 %s · %s%s" % [v.label(), room.display_name() if room else "?",
			"발견 %s · " % _t(v.discovered_tick) if v.discovered else "", _victim_outcome(v)])
	var statements: Array = []
	for w in sim.command.survey.witnesses:
		for q: String in w.statements:
			var st: Dictionary = w.statements[q]
			var heard := w.asked.has(q)
			statements.append("%s %s: \"%s\" — %s%s" % [w.label(), "(들음)" if heard else "(묻지 않음)", st.get("text", ""),
				"사실" if bool(st.get("reliable", true)) else "틀림", " (%s)" % st.note if st.has("note") else ""])
	var rooms: Array = []
	for c in sim.fire.comps:
		if c.ever_burned:
			rooms.append("%s — %s%s" % [c.display_name(), c.stage_name(), ", 플래시오버 %s" % _t(c.flashover_tick) if c.flashed else ""])
	var faces: Array = []
	for info: Dictionary in sim.scenario.get("site", {}).get("faces", []):
		var key := str(info.get("face", ""))
		faces.append("%s면: %s — %s" % [key, info.get("text", ""), "확인함" if sim.command.survey.face_seen(key) else "확인 못함"])
	return {"victims": victims, "statements": statements, "fire_rooms": rooms, "faces": faces}


## ④ 잘한 점: 기준 이상인 규칙. 없으면 가장 나은 규칙 하나 (SOP 113-3.1 칭찬 필수)
func _strengths(results: Array[Dictionary]) -> Array:
	var good := results.filter(func(r: Dictionary) -> bool: return r.applicable and r.score >= STRENGTH_MIN)
	if good.is_empty():
		var best: Dictionary = {}
		for r in results:
			if r.applicable and (best.is_empty() or r.score > best.score):
				best = r
		if not best.is_empty():
			good = [best]
	var out: Array = []
	for r: Dictionary in good.slice(0, MAX_STRENGTHS):
		out.append({"sop": r.sop, "title": r.title, "detail": r.detail})
	return out


## ④ 고칠 점: 점수가 낮은 규칙부터 (고칠 수 있는 항목, 조항과 다음 행동)
func _weaknesses(results: Array[Dictionary]) -> Array:
	var bad := results.filter(func(r: Dictionary) -> bool: return r.applicable and r.score < WEAKNESS_MAX)
	bad.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.violated and not b.violated) or (a.violated == b.violated and a.score < b.score))
	var out: Array = []
	for r: Dictionary in bad.slice(0, MAX_WEAKNESSES):
		out.append({"sop": r.sop, "title": r.title, "detail": r.detail, "advice": r.advice})
	return out


# --- 도움 ---

func _origin_room() -> Compartment:
	var ign := sim.events.of_type("ignition")
	if ign.is_empty():
		return null
	for c in sim.fire.comps:
		if c.display_name() == ign[0].room:
			return c
	return null


## 진입 우선순위 범주 (SOP 202-3.1.2): 0 화점실, 1 인근실, 2 연소층, 3 화점직상층, 4 화점상층, 5 화점하층
func _category(c: Compartment, origin: Compartment) -> int:
	if c == origin:
		return 0
	if c.level == origin.level:
		for oi in c.openings:
			var o := sim.fire.openings[oi]
			if o.kind == Opening.Kind.DOOR and (o.room_a == origin.index or o.room_b == origin.index):
				return 1
		return 2
	if c.level == origin.level + 1:
		return 3
	return 4 if c.level > origin.level else 5


static func _category_name(cat: int) -> String:
	return ["화점실", "인근실", "연소층", "직상층", "상층", "하층"][cat]


func _victim_outcome(v: Victim) -> String:
	match v.state:
		Victim.State.RESCUED:
			var p := sim.ems.patient_of(v.id)
			var ems_text := ""
			if p:
				ems_text = " · %s · %s" % [sim.ems.triage_name(p), EmsSystem.STAGE_NAMES[p.stage]]
			return "%s 구조 (%s)%s" % [_t(v.rescued_tick), Victim.STATE_NAMES[v.state_at_rescue], ems_text]
		Victim.State.DEAD:
			return "사망"
	return "발견했지만 구조 못함" if v.discovered else "발견 못함"


static func _linear(value: float, good: float, bad: float) -> float:
	if value <= good:
		return 1.0
	if value >= bad:
		return 0.0
	return 1.0 - (value - good) / (bad - good)


static func _t(tick: int) -> String:
	if tick < 0:
		return "--:--"
	var s := int(tick * SimClock.TICK_DT)
	return "%02d:%02d" % [floori(s / 60.0), s % 60]
