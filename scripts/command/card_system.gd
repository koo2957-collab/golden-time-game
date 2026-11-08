class_name CardSystem
extends RefCounted
## 질문 카드 (기획안 3-3, 7장, P7). 대원이 판단을 묻고 지휘관이 고르며, 결과는 시뮬레이션이 만든다.
##   트리거: 사건(tactical_halt 종류·air_alarm·knockdown_reported)이 생기면 data/cards/cards.json에서 맞는 카드를 만든다
##   대기열: 최대 queue_max장, 긴급도(긴급·중요·일반) 순, 긴급은 맨 앞. 만장이면 무전 "대기 중"으로 밀린다
##   제한시간: 긴급도별 초(card_params.json), 훈련 난이도는 배율. 미응답이면 카드는 사라지고 대원은 '지시 대기'로 멈춘 채
##   선택: CommandOrder "card_answer"로 기록(다시 하기). 선택지의 effect를 행동으로 실행한다 — 등급은 화면에 보이지 않는다
##   선제지시: 카드의 skip_if_preordered 키가 켜져 있으면 카드 없이 '최선' 선택을 바로 실행하고 선제지시로 기록
##   기록(log): 묻고 답한 시각, 선택, 등급, 결과(answered·timeout·preordered·overflow) → 디브리핑

const URGENCY_ORDER := {"긴급": 0, "중요": 1, "일반": 2}
const GRADE_SCORE := {"최선": 1.0, "허용": 0.5, "오답": 0.0, "치명": 0.0}


class Card:
	extends RefCounted
	var uid := 0
	var id := ""
	var spec: Dictionary = {}
	var text := ""
	## 화면에 보이는 순서대로 섞은 선택지
	var options: Array = []
	var urgency := "일반"
	var crew_id := -1
	var ctx: Dictionary = {}
	var asked_tick := 0
	var deadline_tick := 0


var units: UnitSystem
var tactical: TacticalSystem
var doors: DoorSystem
var rescue: RescueSystem
var rekindle: RekindleSystem
var water: WaterSystem
var fire: FireSim
var events: SimEventLog
var cards: Array = []
## 대기 중인 카드 (맨 앞이 화면에 보이는 카드)
var queue: Array[Card] = []
## 켜 둔 선제지시 키
var preorders: Dictionary = {}
## 결정 기록 [{uid, id, title, asked_tick, answered_tick, option, grade, result, sop}]
var log: Array[Dictionary] = []
## 훈련 난이도 제한시간 배율
var time_factor := 1.0

var _seconds: Dictionary = {}
var _queue_max := 3
var _event_index := 0
var _next_uid := 1
var _seed := 0
## 이어서 할 일: 창 배연이 끝나면 문을 열고 임무를 다시 시작 [{crew, window, door, action, target}]
var _followups: Array[Dictionary] = []


func _init(p_units: UnitSystem, p_tactical: TacticalSystem, p_doors: DoorSystem, p_rescue: RescueSystem, p_rekindle: RekindleSystem,
		p_water: WaterSystem, p_fire: FireSim, params: ParamTable, card_data: Dictionary, p_events: SimEventLog, p_seed: int) -> void:
	units = p_units
	tactical = p_tactical
	doors = p_doors
	rescue = p_rescue
	rekindle = p_rekindle
	water = p_water
	fire = p_fire
	events = p_events
	_seed = p_seed
	cards = card_data.get("cards", [])
	_seconds = {"긴급": params.value("urgent_s"), "중요": params.value("important_s"), "일반": params.value("normal_s")}
	_queue_max = int(params.value("queue_max"))


func active() -> Card:
	return queue[0] if not queue.is_empty() else null


func set_preorder(key: String, on: bool, tick: int) -> void:
	if on:
		preorders[key] = true
	else:
		preorders.erase(key)
	events.add(tick, "preorder", {"key": key, "on": on, "crew": "현장지휘관"})


func step(_dt: float, tick: int) -> void:
	_scan_events(tick)
	_step_followups(tick)
	for c in queue.duplicate():
		if tick >= c.deadline_tick:
			queue.erase(c)
			_log(c, tick, null, "timeout")
			events.add(tick, "card_timeout", {"crew": _crew_name(c.crew_id), "title": str(c.spec.get("title", c.id))})


## 답하기 (CommandOrder "card_answer"). index는 화면에 보인 순서
func answer(uid: int, index: int, tick: int) -> bool:
	for c: Card in queue:
		if c.uid != uid:
			continue
		if index < 0 or index >= c.options.size():
			return false
		queue.erase(c)
		var opt: Dictionary = c.options[index]
		_log(c, tick, opt, "answered")
		events.add(tick, "card_answered", {"crew": _crew_name(c.crew_id), "title": str(c.spec.get("title", c.id)), "option": str(opt.text)})
		_apply(str(opt.get("effect", "")), c, tick)
		return true
	return false


# --- 트리거 ---

func _scan_events(tick: int) -> void:
	var list := events.entries
	while _event_index < list.size():
		var e: Dictionary = list[_event_index]
		_event_index += 1
		var trigger := _trigger_of(e)
		if trigger == "":
			continue
		for spec: Dictionary in cards:
			if str(spec.get("trigger", "")) == trigger:
				_raise(spec, e, tick)
				break


## 사건 → 트리거 이름
func _trigger_of(e: Dictionary) -> String:
	match str(e.type):
		"tactical_halt":
			return "halt_" + str(e.get("kind", ""))
		"air_alarm":
			return "air_alarm"
		"knockdown_reported":
			return "knockdown"
	return ""


func _raise(spec: Dictionary, e: Dictionary, tick: int) -> void:
	var c := Card.new()
	c.uid = _next_uid
	_next_uid += 1
	c.id = str(spec.get("id", ""))
	c.spec = spec
	c.crew_id = int(e.get("crew_id", -1))
	c.ctx = e.duplicate()
	c.urgency = str(spec.get("urgency", "일반"))
	c.text = str(spec.get("text", ""))
	var opts: Array = spec.get("options", [])
	for v: Dictionary in spec.get("variants", []):
		if _matches(v.get("if", {}), c.ctx):
			c.text = str(v.get("text", c.text))
			opts = v.get("options", opts)
			c.urgency = str(v.get("urgency", c.urgency))
	c.text = c.text.format(c.ctx)
	c.options = _shuffled(opts, c.uid)
	c.asked_tick = tick
	# 선제지시: 카드 없이 최선 선택을 바로 실행
	var pre := str(spec.get("skip_if_preordered", ""))
	if pre != "" and preorders.has(pre):
		var best: Dictionary = {}
		for o: Dictionary in opts:
			if str(o.get("grade", "")) == "최선":
				best = o
		_log(c, tick, best, "preordered")
		events.add(tick, "card_preordered", {"crew": _crew_name(c.crew_id), "title": str(spec.get("title", c.id))})
		if not best.is_empty():
			_apply(str(best.get("effect", "")), c, tick)
		return
	if queue.size() >= _queue_max:
		_log(c, tick, null, "overflow")
		events.add(tick, "card_overflow", {"crew": _crew_name(c.crew_id), "title": str(spec.get("title", c.id))})
		return
	c.deadline_tick = tick + roundi(float(spec.get("time_limit_sec", _seconds.get(c.urgency, 20.0))) * time_factor / SimClock.TICK_DT)
	queue.append(c)
	queue.sort_custom(func(a: Card, b: Card) -> bool:
		var ua: int = URGENCY_ORDER.get(a.urgency, 2)
		var ub: int = URGENCY_ORDER.get(b.urgency, 2)
		return ua < ub or (ua == ub and a.uid < b.uid))
	events.add(tick, "card_asked", {"crew": _crew_name(c.crew_id), "title": str(spec.get("title", c.id)), "urgency": c.urgency})


func _matches(cond: Dictionary, ctx: Dictionary) -> bool:
	for k: String in cond:
		if ctx.get(k) != cond[k]:
			return false
	return true


## 선택지 순서는 카드마다 섞되 시드로 정한다 (다시 하기에서 같다)
func _shuffled(opts: Array, uid: int) -> Array:
	var out := opts.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_seed * 7919 + uid)
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = out[i]
		out[i] = out[j]
		out[j] = t
	return out


# --- 행동 (결과는 시뮬레이션이 만든다) ---

func _apply(effect: String, c: Card, tick: int) -> void:
	var crew := units.get_crew(c.crew_id)
	if crew == null:
		return
	var door := _opening(c.ctx.get("door", []))
	var action := str(c.ctx.get("action", ""))
	var target := _cell(c.ctx.get("target", []))
	match effect:
		"open_door", "force_door":
			if door:
				tactical.allow_door(c.crew_id, door.index)
				tactical.order(action if action != "" else "attack", c.crew_id, target, tick)
		"vent_then_open":
			var win := _window_behind(door, crew)
			if door and win:
				doors.request(c.crew_id, Vector3i(win.cells[0].x, win.cells[0].y, win.level), true, tick)
				_followups.append({"crew": c.crew_id, "window": win.index, "door": door.index, "action": action, "target": target})
			elif door:
				tactical.allow_door(c.crew_id, door.index)
				tactical.order(action if action != "" else "attack", c.crew_id, target, tick)
		"rescue_victim":
			rescue.order_rescue(c.crew_id, "victim", int(c.ctx.get("victim", -1)), tick)
		"resume":
			if action != "":
				tactical.order(action, c.crew_id, target, tick)
		"withdraw":
			tactical.order("withdraw", c.crew_id, Vector3i.ZERO, tick)
		"overhaul":
			var room := _cell(c.ctx.get("room_cell", []))
			rekindle.order_overhaul(c.crew_id, room, tick)
		"flood":
			var room := _cell(c.ctx.get("room_cell", []))
			water.start_spray(c.crew_id, room, HoseLine.Pattern.STRAIGHT, tick)
		"hold", "":
			pass


func _step_followups(tick: int) -> void:
	for f in _followups.duplicate():
		var win: Opening = fire.openings[int(f.window)]
		if win.broken or win.is_open:
			_followups.erase(f)
			tactical.allow_door(int(f.crew), int(f.door))
			tactical.order(str(f.action) if str(f.action) != "" else "attack", int(f.crew), f.target, tick)


## 문 너머 방의 바깥 창 (상부 배연용). 조가 있는 쪽이 아닌 방
func _window_behind(door: Opening, crew: Crew) -> Opening:
	if door == null:
		return null
	var here := fire.compartment_at(crew.leader.level, floori(crew.leader.pos.x), floori(crew.leader.pos.y))
	var room_i := door.room_b if here and door.room_a == here.index else door.room_a
	if room_i < 0:
		return null
	for oi in fire.comps[room_i].openings:
		var o := fire.openings[oi]
		if o.kind == Opening.Kind.WINDOW and not o.broken:
			return o
	return null


func _opening(cell: Variant) -> Opening:
	if not cell is Array or (cell as Array).size() < 3:
		return null
	return fire.opening_at(Vector3i(int(cell[0]), int(cell[1]), int(cell[2])))


func _cell(a: Variant) -> Vector3i:
	if not a is Array or (a as Array).size() < 3:
		return Vector3i.ZERO
	return Vector3i(int(a[0]), int(a[1]), int(a[2]))


func _log(c: Card, tick: int, opt: Variant, result: String) -> void:
	var o: Dictionary = opt if opt is Dictionary else {}
	log.append({"uid": c.uid, "id": c.id, "title": str(c.spec.get("title", c.id)), "asked_tick": c.asked_tick, "answered_tick": tick,
		"option": str(o.get("text", "")), "grade": str(o.get("grade", "")), "result": result,
		"sop": ", ".join(PackedStringArray(c.spec.get("sop_ref", []))), "debrief": str(c.spec.get("debrief", ""))})


func _crew_name(crew_id: int) -> String:
	var c := units.get_crew(crew_id)
	return "%s %d조" % [units.squads[c.squad_id].name, c.number] if c else "현장 대원"
