class_name CommandPost
extends RefCounted
## 지휘소와 후착대 임무 받기 (P4-4, 기획안 9-1-1, SOP 101-2.1⑤·101-3·103-2.1·104-1.3).
##   지휘 방식: 이동지휘(MOBILE, 시작) / 고정지휘(FIXED). 지휘권 선언 때 지휘 위치(지휘소)를 정하면 지휘관이 그 반경 안에 있는 동안 고정지휘.
##     지휘소를 떠나면 이동지휘: 전술상황판 갱신이 늦고, 일상 보고(전략·전술 무전) 일부를 놓친다. 안전·구조대상자 무전은 놓치지 않는다.
##   후착대: 도착 보고 뒤 지휘소가 없으면 차 옆에서 기다리며 주기적으로 "임무 주십시오", 지휘소(또는 직전대기 장소)가 있으면 그리로 와서 줄을 선다.
##     지휘관이 지휘소를 떠나면 줄 선(임무 없는) 출동대는 지휘관을 따라 모인다. 도착부터 첫 임무까지 기다린 시간을 기록한다.
##   구역 설치: 안전구역·환자 집결지·진입통제선은 지휘관이 지도에 찍고, 가까운 임무 없는 조가 가서 설치한다(작업 시간).
## 시뮬레이션 코드 (화면 참조 없음). 수치는 data/command/radio_params.json

enum Mode { MOBILE, FIXED }
const MODE_NAMES := {Mode.MOBILE: "이동지휘", Mode.FIXED: "고정지휘"}

var command: CommandSystem
var units: UnitSystem
var pathfinder: Pathfinder
var events: SimEventLog
var mode := Mode.MOBILE
## 지휘소 칸 (x < 0 = 아직 없음)
var post := Vector2i(-1, -1)
## 직전대기 장소 (SOP 103-2.1.3, 선택). 정하면 후착대가 지휘소 대신 이곳에 모인다
var forward := Vector2i(-1, -1)
## 지휘소 지정 기록 [{tick, cell, eval, why}]
var log: Array[Dictionary] = []
## 출동대별 대기 {squad id: {staged: tick, committed: tick, place}}
var waits: Dictionary = {}
## 구역 설치 작업 [{kind, answers, target, crew, start, done}]
var jobs: Array[Dictionary] = []
## 무전 지연 대기열 [[message, release tick]] (이동지휘 중 상황판 갱신 지연)
var _delayed: Array = []
var _deliver := Callable()
var _radius := 8.0
var _delay_ticks := 150
var _miss := 0.25
var _ask_ticks := 600
var _follow := 12.0
var _install_ticks := 300
var _driver_ticks := 600
var _asked: Dictionary = {}  # squad id -> 마지막으로 임무를 물은 틱
var _queued: Dictionary = {}  # squad id -> 줄 선 장소 칸 (지휘소·직전대기·지휘관 곁)
var _no_crew_logged: Dictionary = {}  # job index -> true
var _was_mode := Mode.MOBILE


func _init(p_command: CommandSystem, p_units: UnitSystem, p_pathfinder: Pathfinder, params: ParamTable, p_events: SimEventLog, cell_m: float) -> void:
	command = p_command
	units = p_units
	pathfinder = p_pathfinder
	events = p_events
	_radius = params.value("post_radius_m") / cell_m
	_delay_ticks = roundi(params.value("mobile_board_delay_s") / SimClock.TICK_DT)
	_miss = params.value("mobile_miss_ratio")
	_ask_ticks = roundi(params.value("post_ask_s") / SimClock.TICK_DT)
	_follow = params.value("follow_dist_m") / cell_m
	_install_ticks = roundi(params.value("zone_install_s") / SimClock.TICK_DT)
	_driver_ticks = roundi(params.value("zone_driver_fallback_s") / SimClock.TICK_DT)


func has_post() -> bool:
	return post.x >= 0


## 이동지휘라서 상황판 갱신이 늦고 일상 보고를 놓치는가 (지휘소를 정한 뒤 떠났을 때만)
func penalized() -> bool:
	return has_post() and mode == Mode.MOBILE


## 지휘소를 정한다 (선언·지휘소 옮기기·이양). 지휘관이 멀면 걸어간다. 위치가 위험하면 post_danger 사건 (카드)
func set_post(cell: Vector2i, tick: int, why: String) -> void:
	var c := pathfinder.nearest_walkable(1, cell)
	if c == Pathfinder.NO_CELL:
		return
	post = c
	var ev := command.survey.evaluate_post(Vector2(c) + Vector2(0.5, 0.5), 1) if command.survey else {}
	log.append({"tick": tick, "cell": c, "eval": ev, "why": why})
	if command.commander.level != 1 or command.commander.pos.distance_to(Vector2(c) + Vector2(0.5, 0.5)) > _radius * 0.5:
		command.move_commander(Vector3i(c.x, c.y, 1))
	var where := command.zones.where_text(Vector2(c)) if command.zones else ""
	events.add(tick, "command_post_set", {"where": where, "why": why, "observe": ev.get("observe", ""), "safety": ev.get("safety", ""),
		"route": ev.get("route", ""), "distance_m": ev.get("distance_m", 0.0), "danger_m": ev.get("danger_m", 0.0)})
	if str(ev.get("safety", "")) == "위험":
		events.add(tick, "post_danger", {"where": where, "distance_m": ev.get("distance_m", 0.0), "danger_m": ev.get("danger_m", 0.0), "crew": "현장안전담당"})
	# 이미 도착해 기다리는 출동대는 새 지휘소로 모인다
	_queued.clear()


func set_forward(cell: Vector2i, tick: int) -> void:
	var c := pathfinder.nearest_walkable(1, cell)
	if c == Pathfinder.NO_CELL:
		return
	forward = c
	_queued.clear()
	events.add(tick, "forward_set", {"where": command.zones.where_text(Vector2(c)) if command.zones else ""})


## 위험반경 밖에서 관찰이 되는 가장 가까운 지휘소 후보 (낙하물 경고 카드의 '옮긴다')
func safer_post() -> Vector2i:
	var b := command.fire.building
	var best := Vector2i(-1, -1)
	var best_d := INF
	for y in range(0, b.height, 2):
		for x in range(0, b.width, 2):
			if not pathfinder.passable(1, x, y) or not b.cell(1, x, y) in BuildingData.OUTDOOR:
				continue
			var ev := command.survey.evaluate_post(Vector2(x, y) + Vector2(0.5, 0.5), 1)
			if ev.safety == "위험" or ev.observe == "나쁨" or ev.route != "양호":
				continue
			var d := Vector2(x, y).distance_to(Vector2(post))
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best


# --- 무전: 상황판 갱신 지연·일상 보고 놓침 ---

## Radio.on_delivered 자리에 넣는다. 원래 받을 곳(상황판)은 deliver
func wrap(deliver: Callable) -> Callable:
	_deliver = deliver
	return _on_delivered


func _on_delivered(m: Radio.Message, tick: int) -> void:
	if not penalized() or m.mine:
		_deliver.call(m, tick)
		return
	if m.priority == Radio.Priority.TACTICS and _missed(m):
		m.missed = true
		events.add(tick, "radio_missed", {"sender": m.sender})
		return
	_delayed.append([m, tick + _delay_ticks])


## 놓칠지 (무전 번호로 정해 다시 하기에서도 같다)
func _missed(m: Radio.Message) -> bool:
	return float((m.seq * 2654435761) % 1000) / 1000.0 < _miss


# --- 틱 ---

func step(tick: int) -> void:
	_step_mode(tick)
	for d in _delayed.duplicate():
		if tick >= int(d[1]) or not penalized():
			_delayed.erase(d)
			_deliver.call(d[0], tick)
	if tick % 5 == 0:
		_step_squads(tick)
		_step_jobs(tick)


func _step_mode(tick: int) -> void:
	if not has_post():
		mode = Mode.MOBILE
		return
	var c := command.commander
	var inside := c.level == 1 and c.pos.distance_to(Vector2(post) + Vector2(0.5, 0.5)) <= _radius
	mode = Mode.FIXED if inside else Mode.MOBILE
	if mode != _was_mode:
		_was_mode = mode
		events.add(tick, "command_mode", {"mode": MODE_NAMES[mode]})
		_queued.clear()


## 후착대: 도착(대기) → 줄서기·임무 묻기, 투입되면 대기 시간 기록
func _step_squads(tick: int) -> void:
	var res := command.resources
	var queued_crews: Array[Crew] = []
	for s in units.squads:
		var state := res.state_of(s.id)
		if state == ResourceSystem.State.STAGED:
			if not waits.has(s.id):
				waits[s.id] = {"squad": s.name, "staged": tick, "committed": -1}
			for cr in s.crews:
				if not cr.leader.incapacitated and command.tactical.task_of_crew(cr.id) == null and not busy(cr.id):
					queued_crews.append(cr)
			_ask(s, tick)
		elif state == ResourceSystem.State.COMMITTED and waits.has(s.id) and int(waits[s.id].committed) < 0:
			waits[s.id].committed = tick
			var wait_s := (tick - int(waits[s.id].staged)) * SimClock.TICK_DT
			command.decide(tick, "%s 임무 받기까지 대기 %d초" % [s.name, roundi(wait_s)])
			events.add(tick, "squad_wait", {"squad": s.name, "wait_s": roundi(wait_s)})
	# 모일 곳: 직전대기 장소 > 지휘소(고정지휘) > 지휘관 곁(지휘소를 떠남). 지휘소가 없으면 차 옆 그대로
	var place := Vector2i(-1, -1)
	if forward.x >= 0:
		place = forward
	elif has_post() and mode == Mode.FIXED:
		place = post
	elif has_post():
		place = Vector2i(command.commander.pos.floor())
	if place.x < 0 or queued_crews.is_empty():
		return
	var slots := pathfinder.formation_slots(1, pathfinder.nearest_walkable(1, place), queued_crews.size() + 1)
	if slots.size() > 1:
		slots.remove_at(0)  # 가운데 칸은 지휘관 자리
	for i in queued_crews.size():
		var cr := queued_crews[i]
		if slots.is_empty():
			break
		var slot: Vector2i = slots[mini(i, slots.size() - 1)]
		var at := Vector2(slot) + Vector2(0.5, 0.5)
		var far := cr.leader.level != 1 or cr.leader.pos.distance_to(at) > (1.5 if place != Vector2i(command.commander.pos.floor()) else _follow)
		if far and not cr.leader.is_moving():
			units.order_move([cr.id] as Array[int], Vector3i(slot.x, slot.y, 1), pathfinder)
		_queued[cr.squad_id] = place


## 임무 주십시오: 지휘소·직전대기에 도착하면 한 번, 지휘소가 없으면 차 옆에서 주기적으로 (무전이 붐빈다)
func _ask(s: Squad, tick: int) -> void:
	var last: int = _asked.get(s.id, -1)
	var people := 0
	for cr in s.crews:
		people += cr.members().size()
	if people == 0:
		return
	var arrived_at := ""
	if forward.x >= 0 or has_post():
		var place := forward if forward.x >= 0 else post
		var lead := s.crews[0].leader
		if lead.level == 1 and lead.pos.distance_to(Vector2(place) + Vector2(0.5, 0.5)) <= 4.0 and not lead.is_moving():
			arrived_at = "직전대기 장소" if forward.x >= 0 else "지휘소"
		if arrived_at == "" or last >= 0 and str(waits.get(s.id, {}).get("asked_at", "")) == arrived_at:
			return
		waits[s.id]["asked_at"] = arrived_at
	elif last >= 0 and tick - last < _ask_ticks:
		return
	_asked[s.id] = tick
	var where := "%s 도착" % arrived_at if arrived_at != "" else "차량 옆 대기 중"
	command.radio.send(Radio.Priority.TACTICS, s.name, CommandSystem.COMMANDER, "%s %d명, %s. 임무 주십시오." % [s.name, people, where], tick)


# --- 구역 설치 ---

## 무전으로 정한 구역을 설치하러 갈 조를 정한다. 설치가 끝나면 command.apply_zone
func install(kind: String, answers: Dictionary, tick: int) -> void:
	var target := Vector2i(-1, -1)
	match kind:
		"safe":
			var r: Array = answers.rect
			target = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).get_center()
		"casualty":
			target = Vector2i(int(answers.cell[0]), int(answers.cell[1]))
		"line":
			target = Vector2i(((Vector2(float(answers.a[0]), float(answers.a[1])) + Vector2(float(answers.b[0]), float(answers.b[1]))) * 0.5).floor())
	jobs.append({"kind": kind, "answers": answers, "target": target, "crew": -1, "start": -1, "asked": tick})


## 구역을 설치하러 가는(설치 중인) 조인가 — 다른 자동 행동이 이 조를 쓰지 않게
func busy(crew_id: int) -> bool:
	for j in jobs:
		if crew_id >= 0 and int(j.crew) == crew_id:
			return true
	return false


func _step_jobs(tick: int) -> void:
	for j in jobs.duplicate():
		# 운전원이 설치 중 (임무 없는 조가 오래 없었음)
		if int(j.crew) == -2:
			if tick - int(j.start) >= _install_ticks:
				jobs.erase(j)
				command.apply_zone(j.kind, j.answers, tick)
			continue
		var c := units.get_crew(int(j.crew)) if int(j.crew) >= 0 else null
		# 맡은 조가 다른 임무를 받았거나 쓰러졌으면 다시 고른다
		if c and (c.leader.incapacitated or command.tactical.task_of_crew(c.id) != null or command.rescue.task_of_crew(c.id) != null):
			j.crew = -1
			j.start = -1
			c = null
		if c == null:
			var pick := _free_crew(j.target)
			if pick < 0 and tick - int(j.asked) >= _driver_ticks:
				j.crew = -2
				j.start = tick
				events.add(tick, "zone_install_go", {"kind": ZoneSystem.KIND_NAMES.get(j.kind, j.kind), "crew": "가까운 차량 운전원"})
				continue
			if pick < 0:
				if not _no_crew_logged.has(j.hash()):
					_no_crew_logged[j.hash()] = true
					events.add(tick, "zone_no_crew", {"kind": ZoneSystem.KIND_NAMES.get(j.kind, j.kind)})
				continue
			j.crew = pick
			c = units.get_crew(pick)
			var spot := pathfinder.nearest_walkable(1, j.target)
			units.order_move([pick] as Array[int], Vector3i(spot.x, spot.y, 1), pathfinder)
			events.add(tick, "zone_install_go", {"kind": ZoneSystem.KIND_NAMES.get(j.kind, j.kind), "crew": "%s %d조" % [units.squads[c.squad_id].name, c.number]})
			continue
		var at := Vector2(j.target) + Vector2(0.5, 0.5)
		if int(j.start) < 0:
			if c.leader.level == 1 and c.leader.pos.distance_to(at) <= 2.5 and not c.leader.is_moving():
				j.start = tick
			elif not c.leader.is_moving():
				var spot := pathfinder.nearest_walkable(1, j.target)
				units.order_move([c.id] as Array[int], Vector3i(spot.x, spot.y, 1), pathfinder)
			continue
		if tick - int(j.start) >= _install_ticks:
			jobs.erase(j)
			command.apply_zone(j.kind, j.answers, tick)


func install_progress(j: Dictionary, tick: int) -> float:
	if int(j.start) < 0:
		return 0.0
	return clampf(float(tick - int(j.start)) / maxf(1.0, _install_ticks), 0.0, 1.0)


## 구역을 설치할 수 있는 가까운 조: 현장에 있고 임무·운반·수관이 없고, 밖에 있으며 RIT·안전담당·구급대가 아닌 조
func _free_crew(target: Vector2i) -> int:
	var best := -1
	var best_d := INF
	for cr in units.crews:
		var s := units.squads[cr.squad_id]
		if not command.resources.on_scene(s.id) or cr.leader.aboard or cr.leader.incapacitated or s.type == "구급대":
			continue
		if command.tactical.task_of_crew(cr.id) != null or command.rescue.task_of_crew(cr.id) != null or command.water.hose_of_crew(cr.id) != null:
			continue
		if command.safety.reserved(cr.id) or busy(cr.id) or command.interior.crew_inside(cr.id):
			continue
		var d := cr.leader.pos.distance_to(Vector2(target))
		if d < best_d:
			best_d = d
			best = cr.id
	return best


## 디브리핑: 후착대 임무 대기 총시간 (초)과 출동대별 줄
func wait_summary(tick: int) -> Dictionary:
	var total := 0.0
	var parts: PackedStringArray = []
	for id: int in waits:
		var w: Dictionary = waits[id]
		var end: int = int(w.committed) if int(w.committed) >= 0 else tick
		var s := (end - int(w.staged)) * SimClock.TICK_DT
		total += s
		parts.append("%s %d초%s" % [w.squad, roundi(s), "" if int(w.committed) >= 0 else " (끝까지 임무 없음)"])
	return {"total_s": roundi(total), "detail": ", ".join(parts)}
