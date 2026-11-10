class_name TacticalSystem
extends RefCounted
## 고수준 명령 (분대 명령칸). 명령 하나에 SOP 순서대로 여러 행동이 자동으로 이어진다.
##   진압 (attack): 길의 닫힌 문 개방 → 수관 연장·접근·분무 방수 (WaterSystem) → 그 방 불이 꺼지면 방수 중지
##   외부 방수 (exterior): 밖에서 직사로 연소 확대 저지
##   수색 (search): 길의 닫힌 문 개방 → 인명검색 → 찾은 구조대상자 이송 (자동화 수준에 따라)
##   철수 (withdraw): 그 조만 가장 가까운 문 밖으로
##   층 검색·층 진압 (search_floor·attack_floor, R7): 본 적 없는 곳은 층 단위로 맡긴다 (기획안 9-1).
##     층 검색은 아직 검색하지 않은 방을 가까운 곳부터 차례로, 층 진압은 그 층에서 타는 방을 찾아 차례로 진압
##   임무 조건 (R7): 철수 잔압·화점 발견 시·요구조자 발견 시. 정해 두면 그 질문 카드 없이 그대로 한다
##   직하층 확인 (check_below, P2-2): 목표 세대 바로 아래 세대를 돌며 구조를 보고 → 위 세대의 '추정 구조'로 기록 (기획안 4-2-1, SOP 202 4.4)
## 자동 행동도 SOP 안에서만 움직인다: 백드래프트 징후가 있는 문은 열지 않고 멈춰 보고한다 (210-4.5),
## 진입 명령이 없으면 입구에서 기다린다 (102-5.2). 자동화 수준은 난이도에 따라 다르다.

enum Phase { DOORS, ACT, WORKING, DONE }
const ACTIONS := {"attack": "진압", "exterior": "외부 방수", "search": "수색", "withdraw": "철수",
	"search_floor": "층 검색", "attack_floor": "층 진압", "hold": "대기", "check_below": "직하층 확인"}
const MISSION_PATH := "res://data/command/mission_params.json"
## 난이도별 자동화 수준
const LEVELS := {
	"입문": {"doors": "all", "auto_rescue": true, "auto_stop": true},
	"중급": {"doors": "unlocked", "auto_rescue": false, "auto_stop": true},
	"상급": {"doors": "none", "auto_rescue": false, "auto_stop": false},
}


class Task:
	extends RefCounted
	var crew_id := -1
	var action := ""
	var target := Vector3i.ZERO
	var room := -1
	var doors: Array[Opening] = []
	var door_requested := false
	var phase := Phase.DOORS
	## 층 단위 임무면 그 층 (-1 = 방 하나)
	var floor := -1
	var floor_action := ""
	## 멈춰 지시를 기다리는가 (층 임무는 이어 가지 않는다)
	var halted := false
	## 주수 방법 (P10-2 결정 ②): 화점실 앞에서 카드로 묻고 고른 HoseLine.Pattern (-1 = 아직)
	var nozzle := -1
	var nozzle_asked := false
	var nozzle_wait_until := -1
	## 직하층 확인: 남은 방 (구획 index)과 위·아래 세대 이름
	var unit_rooms: Array[int] = []
	var unit_check: Dictionary = {}


var fire: FireSim
var units: UnitSystem
var water: WaterSystem
var doors_sys: DoorSystem
var rescue: RescueSystem
var safety: SafetySystem
var events: SimEventLog
var tasks: Array[Task] = []
## 질문 카드 답으로 이 조가 열어도 되는 문 {조 id: 개구부 index} (자동화 수준·징후와 상관없이)
var allowed_doors: Dictionary = {}
## 자동화 수준 이름 (입문·중급·상급)
var level_name := "입문"
var level: Dictionary = LEVELS["입문"]
## 구급 처치 후 자동 이송 여부를 자동화 수준에 맞춘다
var ems: EmsSystem
## 화점 발견 판정에 쓰는 시야
var perception: Perception
## 임무 조건 {조 id: {on_fire, on_victim, withdraw_air}} (키는 data/command/mission_params.json)
var conditions: Dictionary = {}
var mission_data: Dictionary = {}
## 화점진압 조가 화점실 앞에서 주수 방법을 질문 카드로 묻는가 (지휘 규칙을 켠 판, P10-2)
var nozzle_cards := false
var _hot_layer_c := 300.0
var _pencil_done_c := 150.0
var _nozzle_wait_ticks := 300
var _fire_radius := 5.0
var _fire_seen: Dictionary = {}  # "조:방" -> true
var _air_withdrawn: Dictionary = {}  # 조 id -> true (철수 잔압으로 철수함)
## 세대 배치 (P2-2, SimWorld가 넣는다)
var layout: UnitAssembly
## 직하층 확인으로 얻은 추정 구조 {위 세대 이름: {from: 아래 세대, variant: 아래 세대 변형, furnish, tick}} — 지휘관이 아는 정보
var unit_estimates: Dictionary = {}


func _init(p_fire: FireSim, p_units: UnitSystem, p_water: WaterSystem, p_doors: DoorSystem, p_rescue: RescueSystem, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	water = p_water
	doors_sys = p_doors
	rescue = p_rescue
	events = p_events
	var data: Variant = JsonData.load_file(MISSION_PATH)
	mission_data = data if data is Dictionary else {}
	_fire_radius = float(mission_data.get("fire_found_radius_m", {}).get("value", 5.0))
	_hot_layer_c = float(mission_data.get("nozzle_hot_layer_c", {}).get("value", 300.0))
	_pencil_done_c = float(mission_data.get("nozzle_pencil_done_c", {}).get("value", 150.0))
	_nozzle_wait_ticks = roundi(float(mission_data.get("nozzle_wait_s", {}).get("value", 30.0)) / SimClock.TICK_DT)


func set_level(name: String) -> void:
	level_name = name if LEVELS.has(name) else "입문"
	level = LEVELS[level_name]
	if ems:
		ems.auto_transport = level_name == "입문"


func task_of_crew(crew_id: int) -> Task:
	for t in tasks:
		if t.crew_id == crew_id:
			return t
	return null


func cancel(crew_id: int) -> void:
	tasks = tasks.filter(func(t: Task) -> bool: return t.crew_id != crew_id)


## 고수준 명령 시작
func order(action: String, crew_id: int, target: Vector3i, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	if c == null or not ACTIONS.has(action):
		return false
	doors_sys.cancel(crew_id)
	rescue.cancel(crew_id)
	cancel(crew_id)
	if action == "withdraw":
		water.stop_spray(crew_id, tick)
		safety.withdraw_crew(c, tick, "withdraw")
		return true
	if action == "hold":
		water.stop_spray(crew_id, tick)
		units.order_move([crew_id] as Array[int], Vector3i(floori(c.leader.pos.x), floori(c.leader.pos.y), c.leader.level), safety.pathfinder)
		events.add(tick, "crew_hold", {"crew": _crew_name(c)})
		return true
	if action == "exterior":
		events.add(tick, "tactical_start", {"crew": _crew_name(c), "action": ACTIONS[action]})
		return water.start_spray(crew_id, target, HoseLine.Pattern.STRAIGHT, tick)
	if action in ["search_floor", "attack_floor"]:
		return _order_floor(action, c, target.z, tick, true)
	if action == "check_below":
		return _order_check_below(c, target, tick)
	var room := fire.compartment_at(target.z, target.x, target.y)
	if room == null:
		return false
	var t := Task.new()
	t.crew_id = crew_id
	t.action = action
	t.target = target
	t.room = room.index
	t.doors = _closed_doors_to(c, room)
	tasks.append(t)
	events.add(tick, "tactical_start", {"crew": _crew_name(c), "action": ACTIONS[action], "room": room.display_name()})
	return true


func step(tick: int) -> void:
	for t in tasks.duplicate():
		var c := units.get_crew(t.crew_id)
		if c.leader.incapacitated:
			tasks.erase(t)
			continue
		match t.phase:
			Phase.DOORS:
				_step_doors(t, c, tick)
			Phase.ACT:
				_act(t, c, tick)
			Phase.WORKING:
				_step_working(t, c, tick)
		if t.action == "search" and t.phase != Phase.DONE:
			_check_fire_found(t, c, tick)
	# 층 임무: 방 하나를 마치면 다음 방으로 (멈췄거나 구조대상자를 옮기는 중이면 이어 가지 않는다)
	var next: Array[Task] = []
	var unit_next: Array[Task] = []
	for t in tasks:
		if t.phase == Phase.DONE and not t.halted and rescue.task_of_crew(t.crew_id) == null:
			if t.floor >= 0:
				next.append(t)
			elif not t.unit_check.is_empty():
				unit_next.append(t)
	# 구조자를 옮기는 중인 층·세대 임무는 남겨 두었다가 인계 뒤 이어 간다 (원래 임무 복귀, P10-2 ⓒ)
	tasks = tasks.filter(func(t: Task) -> bool: return t.phase != Phase.DONE 		or ((t.floor >= 0 or not t.unit_check.is_empty()) and not t.halted and rescue.task_of_crew(t.crew_id) != null))
	for t in next:
		_order_floor(t.floor_action, units.get_crew(t.crew_id), t.floor, tick, false)
	for t in unit_next:
		_next_unit_room(units.get_crew(t.crew_id), t.unit_rooms, t.unit_check, tick)
	_check_air(tick)


# --- 단계 ---

func _step_doors(t: Task, c: Crew, tick: int) -> void:
	while not t.doors.is_empty() and t.doors[0].is_open:
		t.doors.pop_front()
		t.door_requested = false
	if t.doors.is_empty():
		t.phase = Phase.ACT
		return
	var o := t.doors[0]
	if t.door_requested:
		if doors_sys.task_of_crew(t.crew_id) == null and not o.is_open:
			_halt(t, c, tick, "%s을(를) 열지 못함 — 지시 바람" % _door_name(o), false, "door_failed", _door_ctx(o))
		return
	if allowed_doors.get(t.crew_id, -1) == o.index:
		allowed_doors.erase(t.crew_id)
		doors_sys.request(t.crew_id, Vector3i(o.cells[0].x, o.cells[0].y, o.level), true, tick)
		t.door_requested = true
		return
	# 자동으로 열 수 있는 문인지 (자동화 수준·잠김·백드래프트 징후)
	if level.doors == "none":
		_halt(t, c, tick, "%s 닫힘 — 문 개방 지시 바람 (E)" % _door_name(o), false, "closed", _door_ctx(o))
		return
	if o.locked and level.doors != "all":
		_halt(t, c, tick, "%s 잠김 — 진입구 개척(문 파괴) 지시 바람" % _door_name(o), false, "locked", _door_ctx(o))
		return
	if _sign_behind(o):
		_halt(t, c, tick, "%s 너머 백드래프트 징후 — 문 개방 보류, 지시 바람 (SOP 210-4.5)" % _door_name(o), true, "backdraft", _door_ctx(o))
		return
	doors_sys.request(t.crew_id, Vector3i(o.cells[0].x, o.cells[0].y, o.level), true, tick)
	t.door_requested = true
	# 문 앞에 다가가며 징후를 느끼면 바로 멈춘다
	if _sign_behind(o):
		doors_sys.cancel(t.crew_id)
		_halt(t, c, tick, "%s 너머 백드래프트 징후 — 문 개방 보류, 지시 바람 (SOP 210-4.5)" % _door_name(o), true, "backdraft", _door_ctx(o))


func _act(t: Task, c: Crew, tick: int) -> void:
	match t.action:
		"attack":
			if nozzle_cards and t.nozzle < 0:
				if not t.nozzle_asked:
					# 화점실 앞: 관창수가 상황을 보고 주수 방법을 묻는다 (기획안 9-1 표 '주수 방법', 5-4)
					t.nozzle_asked = true
					t.nozzle_wait_until = tick + _nozzle_wait_ticks
					events.add(tick, "nozzle_choice", nozzle_info(t, c))
					return
				if tick < t.nozzle_wait_until:
					return
				t.nozzle = HoseLine.Pattern.FOG
				events.add(tick, "nozzle_default", {"crew": _crew_name(c)})
			var pattern: HoseLine.Pattern = t.nozzle if t.nozzle >= 0 else HoseLine.Pattern.FOG
			if water.start_spray(t.crew_id, t.target, pattern, tick):
				t.phase = Phase.WORKING
			else:
				_halt(t, c, tick, "방수 위치를 잡을 수 없음 — 지시 바람")
		"search":
			if rescue.order_search(t.crew_id, t.target, tick):
				t.phase = Phase.WORKING
			else:
				_halt(t, c, tick, "검색을 시작할 수 없음 — 지시 바람")


func _step_working(t: Task, c: Crew, tick: int) -> void:
	match t.action:
		"attack":
			var h := water.hose_of_crew(t.crew_id)
			if h == null or not h.flowing:
				return
			# 펜슬링으로 가스층을 식혔으면 화점(연소실체)에 직사로 바꾼다 (5-4: 끄는 것은 가연물에 닿는 주수)
			if h.pattern == HoseLine.Pattern.PENCIL and t.room >= 0 and fire.comps[t.room].t_upper < _pencil_done_c:
				if water.start_spray(t.crew_id, t.target, HoseLine.Pattern.STRAIGHT, tick):
					events.add(tick, "nozzle_switch", {"crew": _crew_name(c), "room": fire.comps[t.room].display_name()})
			if level.auto_stop and not _room_burning(t.room):
				water.stop_spray(t.crew_id, tick)
				t.phase = Phase.DONE
				events.add(tick, "tactical_done", {"crew": _crew_name(c), "text": "%s 화염 진압, 방수 중지" % fire.comps[t.room].display_name()})
		"search":
			if rescue.task_of_crew(t.crew_id) is RescueSystem.SearchTask:
				return
			t.phase = Phase.DONE
			var v := _victim_in_room(t.room)
			if v == null:
				return
			if level.auto_rescue:
				if rescue.order_rescue(t.crew_id, "victim", v.id, tick):
					events.add(tick, "tactical_done", {"crew": _crew_name(c), "text": "%s 발견, 이송 시작" % v.label()})
			else:
				_halt(t, c, tick, "%s 발견 — 구조 지시 바람 (V 또는 우클릭)" % v.label(), false, "victim",
					{"victim": v.id, "victim_name": v.label(), "state": Victim.STATE_NAMES[v.state]})


# --- 도움 ---

## 조의 위치에서 목표 방까지 지나는 문 중 닫힌 것 (구획 사이 최단 경로, 거리 가중)
func _closed_doors_to(c: Crew, room: Compartment) -> Array[Opening]:
	var start_room := fire.compartment_at(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y))
	var start := start_room.index if start_room else Opening.OUTSIDE
	var out: Array[Opening] = []
	if start == room.index:
		return out
	# 다익스트라: 상태 = 구획, 비용 = 개구부 중심 사이 거리
	var dist := {start: 0.0}
	var pos := {start: c.leader.pos}
	var via := {}
	var open_set: Array[int] = [start]
	var done := {}
	while not open_set.is_empty():
		open_set.sort_custom(func(a: int, b: int) -> bool: return dist[a] < dist[b])
		var r: int = open_set.pop_front()
		if done.has(r):
			continue
		done[r] = true
		if r == room.index:
			break
		for o in fire.openings:
			if o.kind == Opening.Kind.WINDOW or (o.room_a != r and o.room_b != r):
				continue
			var nxt := o.other_side(r)
			if done.has(nxt):
				continue
			var center := _center(o)
			var d: float = dist[r] + (pos[r] as Vector2).distance_to(center) + absi(o.level - c.leader.level) * 4.0
			if not dist.has(nxt) or d < dist[nxt]:
				dist[nxt] = d
				pos[nxt] = center
				via[nxt] = [r, o]
				open_set.append(nxt)
	if not via.has(room.index):
		return out
	var cur := room.index
	var chain: Array[Opening] = []
	while cur != start:
		var step: Array = via[cur]
		chain.push_front(step[1])
		cur = step[0]
	for o in chain:
		if o.kind == Opening.Kind.DOOR and not o.is_open:
			out.append(o)
	return out


func _sign_behind(o: Opening) -> bool:
	var names: Array[String] = []
	for r in [o.room_a, o.room_b]:
		if r != Opening.OUTSIDE:
			names.append(fire.comps[r].display_name())
	for e in events.of_type("backdraft_sign"):
		if str(e.room) in names:
			return true
	return false


func _room_burning(room: int) -> bool:
	var grid := fire.grid
	for i in grid.burning:
		var p := grid.cell_of(i)
		var c := fire.compartment_at(p.z, p.x, p.y)
		if c and c.index == room:
			return true
	return false


func _victim_in_room(room: int) -> Victim:
	for v in rescue.victims:
		if not v.discovered or not v.alive() or v.carried_by >= 0:
			continue
		var c := fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
		if c and c.index == room:
			return v
	return null


## 멈춤: 무전 보고와 함께 종류(kind)·문맥을 남긴다 — 질문 카드(CardSystem)가 이 사건으로 카드를 만든다
func _halt(t: Task, c: Crew, tick: int, reason: String, safety_issue := false, kind := "", ctx: Dictionary = {}) -> void:
	t.phase = Phase.DONE
	t.halted = true
	# 층 임무면 카드 답(다시 진행)이 층 임무를 이어 가도록 층 행동을 남긴다
	var e := {"crew": _crew_name(c), "reason": reason, "safety": safety_issue, "kind": kind, "crew_id": c.id,
		"action": t.floor_action if t.floor >= 0 else t.action, "target": [t.target.x, t.target.y, t.target.z]}
	e.merge(ctx)
	events.add(tick, "tactical_halt", e)


func _door_ctx(o: Opening) -> Dictionary:
	return {"door": [o.cells[0].x, o.cells[0].y, o.level], "door_name": _door_name(o)}


## 질문 카드 답: 이 조가 다음에 만나는 그 문은 열어도 된다
func allow_door(crew_id: int, opening_index: int) -> void:
	allowed_doors[crew_id] = opening_index


func _center(o: Opening) -> Vector2:
	var s := Vector2.ZERO
	for cell in o.cells:
		s += Vector2(cell) + Vector2(0.5, 0.5)
	return s / o.cells.size()


func _door_name(o: Opening) -> String:
	var names: PackedStringArray = []
	for r in [o.room_a, o.room_b]:
		names.append(fire.comps[r].name if r != Opening.OUTSIDE else "밖")
	return "%s 문(%s)" % [fire.building.floor_name(o.level), "↔".join(names)]


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]


# --- 층 단위 임무 (R7) ---

## 층 임무의 다음 방을 맡긴다. first: 처음 받은 명령 (아니면 방 하나를 마친 뒤)
func _order_floor(action: String, c: Crew, lv: int, tick: int, first: bool) -> bool:
	var floor_name := fire.building.floor_name(lv)
	var room := _next_floor_room(c, action, lv)
	if room == null:
		if action == "attack_floor" and first:
			events.add(tick, "tactical_halt", {"crew": _crew_name(c), "reason": "%s 화점을 찾지 못함 — 지시 바람" % floor_name,
				"safety": false, "kind": "no_fire", "crew_id": c.id, "action": action, "target": [0, 0, lv]})
		else:
			events.add(tick, "tactical_done", {"crew": _crew_name(c),
				"text": "%s %s 완료" % [floor_name, "검색" if action == "search_floor" else "화점 진압"]})
		return not first or action == "search_floor"
	var t := Task.new()
	t.crew_id = c.id
	t.action = "search" if action == "search_floor" else "attack"
	t.floor = lv
	t.floor_action = action
	t.room = room.index
	t.target = _room_cell(room)
	t.doors = _closed_doors_to(c, room)
	tasks.append(t)
	if first:
		# 카드 트리거(첫 검색·상층 진압)가 방 하나 명령과 같게 보도록 행동 이름은 수색·진압
		events.add(tick, "tactical_start", {"crew": _crew_name(c), "action": ACTIONS[t.action], "room": room.display_name(),
			"floor": floor_name})
	else:
		events.add(tick, "tactical_next", {"crew": _crew_name(c), "room": room.display_name()})
	return true


## 직하층 확인: 목표 세대 바로 아래 세대의 방을 차례로 돈다
func _order_check_below(c: Crew, target: Vector3i, tick: int) -> bool:
	if layout == null:
		return false
	var above := layout.unit_at(target.z, Vector2i(target.x, target.y))
	var below := layout.unit_below(above) if not above.is_empty() else {}
	if below.is_empty():
		events.add(tick, "tactical_halt", {"crew": _crew_name(c), "reason": "직하층 세대가 없음 — 지시 바람", "safety": false,
			"kind": "no_unit", "crew_id": c.id, "action": "check_below", "target": [target.x, target.y, target.z]})
		return false
	var rooms: Array[int] = []
	for room in fire.comps:
		if room.level == int(below.level) and room.display_name().contains(str(below.name)) and not room.cells.is_empty():
			rooms.append(room.index)
	events.add(tick, "tactical_start", {"crew": _crew_name(c), "action": ACTIONS["check_below"], "room": str(below.name)})
	_next_unit_room(c, rooms, {"above": str(above.name), "below": str(below.name), "start": tick}, tick)
	return true


func _next_unit_room(c: Crew, rooms: Array[int], check: Dictionary, tick: int) -> void:
	if rooms.is_empty():
		var below := layout.unit_named(str(check.below))
		unit_estimates[check.above] = {"from": check.below, "variant": below.get("variant", ""), "furnish": below.get("furnish", ""), "tick": tick}
		events.add(tick, "below_checked", {"crew": _crew_name(c), "above": check.above, "below": check.below,
			"text": "%s 확인 — %s도 같은 구조로 추정" % [check.below, check.above]})
		return
	var rest := rooms.duplicate()
	var room := fire.comps[rest.pop_front()]
	var t := Task.new()
	t.crew_id = c.id
	t.action = "search"
	t.room = room.index
	t.target = _room_cell(room)
	t.doors = _closed_doors_to(c, room)
	t.unit_rooms = rest
	t.unit_check = check
	tasks.append(t)


## 층 검색: 아직 검색하지 않은 방 / 층 진압: 타는 방 — 조에게서 가까운 곳부터
func _next_floor_room(c: Crew, action: String, lv: int) -> Compartment:
	var best: Compartment = null
	var best_d := INF
	for room in fire.comps:
		if room.level != lv or room.cells.is_empty():
			continue
		if action == "search_floor" and room.searched_tick >= 0:
			continue
		if action == "attack_floor" and not _room_burning(room.index):
			continue
		var d := c.leader.pos.distance_to(Vector2(room.rect.get_center())) + absi(lv - c.leader.level) * 8.0
		if d < best_d:
			best_d = d
			best = room
	return best


## 방 가운데에 가까운 칸
func _room_cell(room: Compartment) -> Vector3i:
	var center := Vector2(room.rect.get_center())
	var best: Vector2i = room.cells[0]
	for cell in room.cells:
		if Vector2(cell).distance_to(center) < Vector2(best).distance_to(center):
			best = cell
	return Vector3i(best.x, best.y, room.level)


# --- 임무 조건 (R7) ---

## 조건 지정 (CommandOrder "mission_conditions"). 빈 값은 그 항목을 바꾸지 않는다
func set_conditions(crew_ids: Array, cond: Dictionary, tick: int) -> void:
	for id in crew_ids:
		var c := units.get_crew(int(id))
		if c == null:
			continue
		var cur: Dictionary = conditions.get(c.id, {"on_fire": "ask", "on_victim": "ask", "withdraw_air": "alarm"})
		for k in ["on_fire", "on_victim", "withdraw_air"]:
			if str(cond.get(k, "")) != "":
				cur[k] = str(cond[k])
		conditions[c.id] = cur
		events.add(tick, "mission_conditions", {"crew": _crew_name(c), "text": condition_text(c.id)})


## "경보 울리면 철수 · 화점: 문 닫고 보고 · 요구조자: 즉시 구조"
func condition_text(crew_id: int) -> String:
	var cur: Dictionary = conditions.get(crew_id, {})
	if cur.is_empty():
		return ""
	var parts: PackedStringArray = []
	for pair in [["withdraw_air_options", "withdraw_air"], ["on_fire_options", "on_fire"], ["on_victim_options", "on_victim"]]:
		var o := _option(pair[0], str(cur.get(pair[1], "")))
		if not o.is_empty() and str(o.get("key", "")) != "ask":
			parts.append(str(o.get("label", "")))
	return " · ".join(parts)


func _option(group: String, key: String) -> Dictionary:
	for o: Dictionary in mission_data.get(group, []):
		if str(o.get("key", "")) == key:
			return o
	return {}


## 이 조의 임무 조건이 이 카드에 정한 행동 ("" = 카드로 묻는다)
func condition_effect(crew_id: int, card_id: String) -> String:
	var cur: Dictionary = conditions.get(crew_id, {})
	if cur.is_empty():
		return ""
	match card_id:
		"VICTIM-FOUND-01":
			return str(_option("on_victim_options", str(cur.get("on_victim", "ask"))).get("effect", ""))
		"FIRE-FOUND-01":
			return str(_option("on_fire_options", str(cur.get("on_fire", "ask"))).get("effect", ""))
		"AIR-ALARM-01":
			# 철수 잔압을 정해 두었으면 경보에는 바로 철수 (201-3.7)
			return "withdraw"
	return ""


func _withdraw_ratio(crew_id: int) -> float:
	var cur: Dictionary = conditions.get(crew_id, {})
	return float(_option("withdraw_air_options", str(cur.get("withdraw_air", "alarm"))).get("ratio", 0.0))


## 철수 잔압: 건물 안에서 조의 가장 낮은 공기가 기준 아래로 내려가면 질문 없이 철수
func _check_air(tick: int) -> void:
	for id: int in conditions:
		var ratio := _withdraw_ratio(id)
		var c := units.get_crew(id)
		if ratio <= 0.0 or c == null or c.leader.incapacitated:
			continue
		var inside := not fire.building.cell(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y)) in BuildingData.OUTDOOR
		if _air_withdrawn.has(id):
			if not inside:
				_air_withdrawn.erase(id)
			continue
		var low := 1.0
		for ff in c.members():
			low = minf(low, ff.air_ratio())
		if inside and low <= ratio:
			_air_withdrawn[id] = true
			cancel(id)
			water.stop_spray(id, tick)
			safety.withdraw_crew(c, tick, "withdraw")
			events.add(tick, "mission_withdraw", {"crew": _crew_name(c), "crew_id": id, "percent": roundi(low * 100.0)})


## 검색 중인 조가 가까이에서 타는 칸을 보면 화점 발견 보고 (방마다 한 번). 질문 카드 FIRE-FOUND-01
func _check_fire_found(t: Task, c: Crew, tick: int) -> void:
	if perception == null:
		return
	var grid := fire.grid
	var lv := c.leader.level
	for i in grid.burning:
		var p := grid.cell_of(i)
		if p.z != lv or Vector2(p.x + 0.5, p.y + 0.5).distance_to(c.leader.pos) > _fire_radius:
			continue
		if not perception.is_visible(lv, p.x, p.y):
			continue
		var room := fire.compartment_at(lv, p.x, p.y)
		if room == null:
			continue
		var key := "%d:%d" % [c.id, room.index]
		if _fire_seen.has(key):
			continue
		_fire_seen[key] = true
		events.add(tick, "fire_found", {"crew": _crew_name(c), "crew_id": c.id, "room": room.display_name(),
			"room_cell": [p.x, p.y, lv], "has_hose": water.hose_of_crew(c.id) != null,
			"action": t.floor_action if t.floor >= 0 else t.action, "target": [t.target.x, t.target.y, t.target.z]})
		return


## 주수 방법 카드 문맥: 관창수가 본 화점실 상태와 (보이지 않는) 정답
##   방 전체가 탐(플래시오버) → 직사, 천장 가스층이 뜨거움 → 펜슬링·3D 먼저, 그 밖 → 직사(화점)
##   배기구가 없으면 분무는 수증기로 열기가 내려와 오답 (기획안 5-4)
func nozzle_info(t: Task, c: Crew) -> Dictionary:
	var room: Compartment = fire.comps[t.room] if t.room >= 0 else fire.compartment_at(t.target.z, t.target.x, t.target.y)
	var vent := false
	var hot := false
	var flashed := false
	var temp := 0
	var name := ""
	if room:
		name = room.display_name()
		flashed = room.flashed
		temp = roundi(room.t_upper)
		hot = room.t_upper >= _hot_layer_c
		for o in fire.openings:
			if (o.room_a == room.index or o.room_b == room.index) and (o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE) and (o.is_open or o.broken):
				vent = true
	var verdict := "straight" if flashed or not hot else "pencil"
	var state := "방 전체가 타고 있음" if flashed else ("천장 연기층이 뜨거움 (약 %d℃)" % temp if hot else "화염이 보임, 연기층은 견딜 만함")
	return {"crew_id": c.id, "crew": _crew_name(c), "room": name, "state": state, "vent": "배기구 있음" if vent else "배기구 없음",
		"nv": "%s_%s" % [verdict, "vent" if vent else "novent"]}


## 주수 방법 카드 답 (CardSystem effect nozzle_straight·fog·pencil·cover)
func set_nozzle(crew_id: int, pattern: int) -> void:
	var t := task_of_crew(crew_id)
	if t and t.action == "attack":
		t.nozzle = pattern


## 팀 카드·상황 보고용 임무 이름: "층 검색 (2층 방1)" / "진압 (1층 거실)" / ""
func mission_text(crew_id: int) -> String:
	var t := task_of_crew(crew_id)
	if t == null:
		return ""
	var room := fire.comps[t.room].display_name() if t.room >= 0 else ""
	return "%s%s" % [ACTIONS.get(t.floor_action if t.floor >= 0 else t.action, t.action), " (%s)" % room if room != "" else ""]
