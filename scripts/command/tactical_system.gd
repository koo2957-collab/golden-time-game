class_name TacticalSystem
extends RefCounted
## 고수준 명령 (분대 명령칸). 명령 하나에 SOP 순서대로 여러 행동이 자동으로 이어진다.
##   진압 (attack): 길의 닫힌 문 개방 → 수관 연장·접근·분무 방수 (WaterSystem) → 그 방 불이 꺼지면 방수 중지
##   외부 방수 (exterior): 밖에서 직사로 연소 확대 저지
##   수색 (search): 길의 닫힌 문 개방 → 인명검색 → 찾은 구조대상자 이송 (자동화 수준에 따라)
##   철수 (withdraw): 그 조만 가장 가까운 문 밖으로
## 자동 행동도 SOP 안에서만 움직인다: 백드래프트 징후가 있는 문은 열지 않고 멈춰 보고한다 (210-4.5),
## 진입 명령이 없으면 입구에서 기다린다 (102-5.2). 자동화 수준은 난이도에 따라 다르다.

enum Phase { DOORS, ACT, WORKING, DONE }
const ACTIONS := {"attack": "진압", "exterior": "외부 방수", "search": "수색", "withdraw": "철수"}
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


func _init(p_fire: FireSim, p_units: UnitSystem, p_water: WaterSystem, p_doors: DoorSystem, p_rescue: RescueSystem, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	water = p_water
	doors_sys = p_doors
	rescue = p_rescue
	events = p_events


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
	if action == "exterior":
		events.add(tick, "tactical_start", {"crew": _crew_name(c), "action": ACTIONS[action]})
		return water.start_spray(crew_id, target, HoseLine.Pattern.STRAIGHT, tick)
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
	tasks = tasks.filter(func(t: Task) -> bool: return t.phase != Phase.DONE)


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
			if water.start_spray(t.crew_id, t.target, HoseLine.Pattern.FOG, tick):
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
	var e := {"crew": _crew_name(c), "reason": reason, "safety": safety_issue, "kind": kind, "crew_id": c.id,
		"action": t.action, "target": [t.target.x, t.target.y, t.target.z]}
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
