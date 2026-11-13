extends SceneTree
## 점검용 (테스트 목록에 넣지 않음, G1): 튜토리얼을 '안내판 문구대로만 하는 플레이어'로 끝까지 돌려
## 단계마다 걸린 시간·막힌 곳·무전·대원 상태를 찍는다. 화면 없이 명령만 낸다.
## 인자: [mode]  best = 카드에 늘 최선 / none = 카드에 답하지 않음 / idle = 아무 명령도 안 함

const TUTORIAL := "res://data/scenarios/tutorial_basics.json"
## 단계 하나에 기다리는 최대 현장 시간 (초) — 점검 설정값
const STEP_LIMIT_S := 420.0
const STATUS_EVERY_S := 20.0

var sim: SimWorld
var mode := "best"
var steps: Array = []
var _printed := 0
var _acted := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		mode = args[0]
	var data: Dictionary = JsonData.load_file(TUTORIAL)
	sim = SimWorld.from_scenario(TUTORIAL)
	var d := str(data.get("meta", {}).get("difficulty", "입문"))
	sim.tactical.set_level(d if TacticalSystem.LEVELS.has(d) else "입문")
	sim.apply_realism("훈련")
	print("자동화 수준 %s · 난이도 훈련 · 배속 %.1f · 출동 %ds" % [sim.tactical.level_name, sim.field_scale, int(sim.dispatch_s)])
	sim.issue(CommandOrder.make("placement", [], int(data.get("approach", {}).get("default", 0))))
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 5.0}))
	steps = JsonData.load_file(str(data.tutorial)).steps
	_roster()
	if mode == "idle":
		_run_idle()
	else:
		_run()
	_summary()
	quit()


func _roster() -> void:
	for s in sim.units.squads:
		var ids := PackedStringArray()
		for c in s.crews:
			ids.append("조%d(%s·%s)" % [c.id, c.leader.name, c.partner.name if c.partner else "-"])
		print("출동대 %d %s [%s·%s] %s" % [s.id, s.name, s.type, s.arrival, ", ".join(ids)])
	for v in sim.units.vehicles:
		print("차량 %d %s" % [v.id, v.type])
	for i in sim.entries.list.size():
		var e: EntryPoints.Entry = sim.entries.list[i]
		print("진입구 %d %s 문%s" % [i, e.name, str(e.door)])


func _t() -> float:
	return sim.clock.tick * SimClock.TICK_DT


func _stamp() -> String:
	var t := int(_t())
	return "%02d:%02d" % [t / 60, t % 60]


func _flush_events() -> void:
	var all: Array = sim.events.entries if "entries" in sim.events else []
	while _printed < all.size():
		var e: Dictionary = all[_printed]
		_printed += 1
		if str(e.type) in ["radio", "smoke", "victim_state"]:
			continue
		var text := SimEventLog.describe_text(e)
		print("   %s [%s] %s" % [_stamp(), e.type, text if text != "" else str(e).substr(0, 160)])


func _status() -> void:
	var rows := PackedStringArray()
	for c in sim.units.crews:
		var ff := c.leader
		var t := sim.tactical.task_of_crew(c.id)
		var room := sim.fire.compartment_at(ff.level, floori(ff.pos.x), floori(ff.pos.y))
		var where := "차 안" if ff.aboard else (room.display_name() if room else "밖")
		var what := "임무 없음"
		if t:
			what = "%s·%s%s" % [t.action, ["문", "행동", "작업", "끝"][t.phase], "·멈춤" if t.halted else ""]
		rows.append("조%d %s(%d,%d) %s%s 공기%d%%" % [c.id, where, floori(ff.pos.x), floori(ff.pos.y), what, " 이동" if ff.is_moving() else "", roundi(ff.air_ratio() * 100)])
	var burning: int = sim.fire.grid.burning.size()
	var vs := PackedStringArray()
	for v in sim.rescue.victims:
		vs.append("%s:%s" % [v.name, v.state_name()])
	print(" ▷ %s 불칸 %d · 소실 %d%% · %s · 카드 %d | %s" % [_stamp(), burning, roundi(sim.mission_end.loss_ratio() * 100), ",".join(vs), sim.cards.queue.size(), " / ".join(rows)])


func _done(step: Dictionary) -> bool:
	match str(step.get("check", "")):
		"time":
			return _t() >= float(step.get("s", 5))
		"declared":
			return sim.command.declared()
		"selected":
			return true
		"faces":
			return sim.command.survey.faces_seen.size() >= int(step.get("count", 2))
		"rit":
			return not sim.command.safety.crews_with(SafetySystem.Role.RIT).is_empty()
		"event":
			return not sim.events.of_type(str(step.get("event", ""))).is_empty()
		"ended":
			return sim.ended_tick >= 0
	return false


func _crew_of_type(type: String, nth := 0) -> int:
	var k := 0
	for s in sim.units.squads:
		if s.type == type and sim.command.resources.on_scene(s.id):
			for c in s.crews:
				if k == nth:
					return c.id
				k += 1
	return -1


## 안내판 문구대로 한 번 행동한다 (단계마다 한 번, ems는 올 때까지 다시)
func _act(i: int, step: Dictionary) -> void:
	if _acted.has(i):
		return
	var done := true
	var fire_cell := Vector3i(12, 17, 1)
	var v: Victim = sim.rescue.victims[0]
	match str(step.title):
		"지휘권 선언 · 최초 상황보고":
			sim.issue(CommandOrder.make("declare", [], 0, Vector3i.ZERO, {
				"fire": "연기만 확인", "victims": "있음", "use": "단독주택", "floors": "2층", "structure": "벽돌조", "hazards": [],
				"activities": ["인명검색", "내부 진입 진압"], "strategy": CommandSystem.Strategy.OFFENSIVE, "support": "불필요", "access": "진입 가능, 회차 불가"}))
		"360° 둘러보기":
			sim.issue(CommandOrder.make("survey"))
		"RIT 지정":
			sim.issue(CommandOrder.make("role", [_crew_of_type("진압대", 1)] as Array[int], SafetySystem.Role.RIT))
		"화점진압 지시 · 진입 허가":
			sim.issue(TacticalCommand.make("attack", [_crew_of_type("진압대", 0)] as Array[int], fire_cell))
		"인명검색 (구조대)":
			sim.issue(TacticalCommand.make("search", [_crew_of_type("구조대", 0)] as Array[int], Vector3i(floori(v.pos.x), floori(v.pos.y), v.level)))
		"구급대 처치":
			var ems := _crew_of_type("구급대", 0)
			if ems < 0 or v.state != Victim.State.RESCUED:
				done = false
			else:
				sim.issue(EquipmentCommand.make("ems_treat", [ems] as Array[int], -1, v.id))
		"잔불정리·2차 검색":
			sim.issue(EquipmentCommand.make("overhaul", [_crew_of_type("진압대", 0)] as Array[int], -1, -1, fire_cell))
			sim.issue(TacticalCommand.make("search", [_crew_of_type("구조대", 0)] as Array[int], fire_cell))
		"완진 선언":
			sim.issue(CommandOrder.make("all_clear"))
		"인원점검":
			sim.issue(CommandOrder.make("par"))
		"복귀 보고 · 활동 종료":
			sim.issue(CommandOrder.make("end", [], 0, Vector3i.ZERO, {"watch": "감시조"}))
	if done:
		_acted[i] = true
		print(" ● %s 플레이어 행동: %s" % [_stamp(), step.title])


func _answer_cards() -> void:
	if mode != "best":
		return
	for c in sim.cards.queue.duplicate():
		var best := 0
		for k in c.options.size():
			if str(c.options[k].get("grade", "")) == "최선":
				best = k
		print(" ◆ %s 카드 [%s] %s → %s" % [_stamp(), c.id, str(c.spec.get("title", "")), str(c.options[best].get("text", "")).substr(0, 50)])
		sim.issue(CommandOrder.make("card_answer", [], best, Vector3i.ZERO, {"uid": c.uid}))


var _results: Array = []


func _run() -> void:
	var next_status := 0.0
	for i in steps.size():
		var step: Dictionary = steps[i]
		var start := _t()
		print("\n━━ 단계 %d: %s (%s) ━━" % [i + 1, step.title, step.get("event", step.check)])
		var ok := false
		while _t() - start < STEP_LIMIT_S:
			if _done(step):
				ok = true
				break
			if sim.ended():
				break
			_act(i, step)
			sim.step_ticks(10)
			_answer_cards()
			_flush_events()
			if _t() >= next_status:
				next_status = _t() + STATUS_EVERY_S
				_status()
		_flush_events()
		_status()
		_results.append({"n": i + 1, "title": step.title, "ok": ok, "s": _t() - start, "at": _t()})
		print("  → %s (%d초 걸림)" % ["완료" if ok else "✗ 넘어가지 못함", roundi(_t() - start)])
		if sim.ended() and not ok:
			print("  게임이 끝남: %s" % str(sim.end_reason if "end_reason" in sim else ""))
			break


## 아무것도 하지 않으면 어떻게 되는가 (목표·실패 점검)
func _run_idle() -> void:
	var next_status := 0.0
	while _t() < 1800.0 and not sim.ended():
		sim.step_ticks(10)
		_flush_events()
		if _t() >= next_status:
			next_status = _t() + 60.0
			_status()
	print("끝: ended=%s t=%s" % [sim.ended(), _stamp()])


func _summary() -> void:
	print("\n═══ 요약 (%s) ═══" % mode)
	for r: Dictionary in _results:
		print("%2d %s %-28s %4d초 (누적 %s)" % [r.n, "○" if r.ok else "✗", r.title, roundi(r.s), "%02d:%02d" % [int(r.at) / 60, int(r.at) % 60]])
	for v in sim.rescue.victims:
		print("구조대상자 %s: %s (구조 시 %s)" % [v.name, v.state_name(), str(v.state_at_rescue)])
	print("소실 %d%% (%s) · 종료 %s" % [roundi(sim.mission_end.loss_ratio() * 100), sim.mission_end.loss_class(), sim.ended()])
	var halts := sim.events.of_type("tactical_halt")
	print("대원 멈춤(지시 바람) %d번" % halts.size())
	for h in halts:
		print("   %s %s: %s" % [SimEventLog.describe(h).substr(0, 5), h.get("crew", ""), h.get("reason", "")])
