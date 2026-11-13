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
	## 조장의 판단 장면이면 그 속말 (spec.scene == "judgment"). 지휘관에게 오는 무전이면 ""
	var monologue := ""

	## 조장이 스스로 판단하는 장면인가 (아니면 지휘관에게 오는 무전)
	func judgment() -> bool:
		return str(spec.get("scene", "")) == "judgment" and crew_id >= 0


## 시뮬레이션 전체 (사건에 없는 문맥 — 방·구조대상자·차량·가까운 조 — 을 상태에서 찾는다)
var sim: SimWorld
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
## 대원 판단 장면 (2026-11-14 사용자 결정): true = 플레이어가 그 조장으로서 고른다 (전 직원 훈련).
## false = 대원이 SOP대로(최선) 알아서 한다 (지휘관 훈련) — 장면이 뜨지 않고 보고만 온다
var crew_judgment := true
## 켜 둔 선제지시 키
var preorders: Dictionary = {}
## 결정 기록 [{uid, id, title, asked_tick, answered_tick, option, grade, result, sop}]
var log: Array[Dictionary] = []
## 훈련 난이도 제한시간 배율
var time_factor := 1.0
## 현장 시계 배속: 제한시간은 실제 초라 현장 틱으로는 이만큼 길다 (기획안 5-8)
var clock_scale := 1.0

var _seconds: Dictionary = {}
var _queue_max := 3
var _event_index := 0
var _next_uid := 1
var _seed := 0
## 이어서 할 일: 창 배연이 끝나면 문을 열고 임무를 다시 시작 [{crew, window, door, action, target}]
var _followups: Array[Dictionary] = []
## 정보 확인 뒤 할 행동 [{tick, effect, card}]
var _delayed: Array[Dictionary] = []
## 연기가 찼지만 아직 아무도 보지 못한 계단실 {구획 index: true}
var _pending_smoke: Dictionary = {}


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
	if tick % 10 == 0:
		_check_pending_smoke(tick)
	_step_followups(tick)
	for c in queue.duplicate():
		if tick >= c.deadline_tick:
			queue.erase(c)
			_log(c, tick, null, "timeout")
			events.add(tick, "card_timeout", {"crew": _crew_name(c.crew_id), "title": str(c.spec.get("title", c.id))})
			# 진입 허가 요청에 답하지 않음: 대원은 입구에서 기다리고 잠시 뒤 다시 묻는다 (P10-2)
			if c.ctx.has("squad_id") and str(c.spec.get("trigger", "")) == "entry_request" and sim:
				sim.command.entry_request_expired(int(c.ctx.squad_id), tick)


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
		# 조장의 판단은 지휘관의 지시가 아니라 그 조의 보고로 남긴다
		events.add(tick, "crew_decided" if c.judgment() else "card_answered", {"crew": _crew_name(c.crew_id), "title": str(c.spec.get("title", c.id)), "option": str(opt.text)})
		# 정보 확인 선택지: 그만큼 시간이 흐른 뒤 then 행동을 한다 (그동안 대원은 기다린다)
		if opt.has("time_cost_sec"):
			_delayed.append({"tick": tick + roundi(float(opt.time_cost_sec) / SimClock.TICK_DT), "effect": str(opt.get("then", "hold")), "card": c})
			events.add(tick, "card_info_check", {"crew": _crew_name(c.crew_id), "seconds": int(opt.time_cost_sec)})
		else:
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
		# 같은 트리거에 카드가 여러 장이면 모두 묻는다 (once 카드는 한 판에 한 번)
		for spec: Dictionary in cards:
			if str(spec.get("trigger", "")) != trigger:
				continue
			# 스테이지 전용 카드 (R14): stages에 지금 시나리오의 스테이지가 있어야 묻는다
			if spec.has("stages") and not (sim and str(sim.scenario.get("meta", {}).get("stage", "")) in spec.stages):
				continue
			if bool(spec.get("once", false)) and log.any(func(l: Dictionary) -> bool: return l.id == str(spec.id)) \
					or not bool(spec.get("multi", false)) and queue.any(func(q: Card) -> bool: return q.id == str(spec.id)):
				continue
			_raise(spec, e, tick)


## 연기 찬 계단실을 누군가 보게 되면 그때 보고 (계단실 연기 카드)
func _check_pending_smoke(tick: int) -> void:
	if sim == null:
		return
	for idx: int in _pending_smoke.keys():
		var room: Compartment = fire.comps[idx]
		if sim.perception.room_visible(room):
			_pending_smoke.erase(idx)
			events.add(tick, "stair_smoke_seen", {"room": room.display_name(), "crew": "현장 대원"})


## 사건 → 트리거 이름
func _trigger_of(e: Dictionary) -> String:
	match str(e.type):
		"tactical_halt":
			return "halt_" + str(e.get("kind", ""))
		"air_alarm":
			return "air_alarm"
		"knockdown_reported":
			return "knockdown"
		"rollover_sign", "jump_risk", "exposure_heating", "sign_warning", "debris_zone", "hydrant_out", "tank_empty", "mayday", \
				"victim_trapped", "end_suggested":
			return str(e.type)
		"shaft_heat", "shaft_smoke":
			return "shaft"
		"site_info_found":
			return "gas_found" if str(e.get("text", "")).contains("가스") or str(e.get("text", "")).contains("LPG") else ""
		"smoke":
			# 연기 시작은 시뮬레이션 사실 — 누가 그 계단실을 봐야 묻는다 (보이기 전이면 기다렸다가 _check_pending_smoke)
			if str(e.get("room", "")).contains("계단실") and fire.building.levels().size() >= 3:
				var room := _room_named(str(e.get("room", "")))
				if room and sim and sim.perception.room_visible(room):
					return "stair_smoke"
				if room:
					_pending_smoke[room.index] = true
			return ""
		"stair_smoke_seen":
			return "stair_smoke"
		"victim_found":
			var alive := 0
			for v in rescue.victims:
				if v.discovered and v.alive() and v.carried_by < 0:
					alive += 1
			return "victims_many" if alive >= 2 else ""
		"tactical_start":
			if str(e.get("action", "")) == "수색":
				return "first_search"
			return "attack_upper" if _upper_attack(e) else ""
		"search_done":
			return "search_mark"
		"fire_found":
			return "fire_found"
		"phase":
			return "arrival" if int(e.get("index", -1)) == 1 else ""
		"entry_request", "rescue_no_point", "triage_needed", "nozzle_choice", "equipment_missing", "fire_not_found", "ppv_no_exhaust", 				"monitor_crew_check", "post_danger":
			return str(e.type)
		# P9 아파트 카드 (기획안 7-3)
		"vehicle_arrived":
			return "tanker_arrived" if str(e.get("vehicle", "")).contains("물탱크") else ""
		"squad_staged":
			return "tanker_arrived" if str(e.get("vehicles", "")).contains("물탱크차") else ""
		"strategy_set":
			# 5층 이상 공동주택에서 자력 대피할 주민이 있으면, 전략을 정한 뒤 대피 안내 순서를 묻는다
			if sim and fire.building.levels().size() >= 5 and rescue.victims.any(func(v: Victim) -> bool: return v.self_evac):
				return "evac_order"
			return ""
		"hose_limit", "hose_resupply":
			# 수관 연장이 힘들 때 대기 중인 RIT가 있으면 "RIT에게 돕게 할까요?" (SSG 9: RIT는 다른 임무 금지)
			return "rit_help" if sim and not _idle_rit().is_empty() else ""
	return ""


## 투입되지 않고 대기 중인 RIT 조
func _idle_rit() -> Array[int]:
	var out: Array[int] = []
	for id in sim.command.safety.crews_with(SafetySystem.Role.RIT):
		if not sim.command.safety.deployed.has(id):
			out.append(id)
	return out


## 2층보다 높은 층을 진압하러 가고, 연결송수관이 있는데 아직 송수구를 잇지 않았는가
func _upper_attack(e: Dictionary) -> bool:
	if sim == null or not fire.building.has_standpipe() or water.fdc_vehicle >= 0 or str(e.get("action", "")) != "진압":
		return false
	for c in fire.comps:
		if c.display_name() == str(e.get("room", "")):
			return c.level >= 3
	return false


func _raise(spec: Dictionary, e: Dictionary, tick: int) -> void:
	var c := Card.new()
	c.uid = _next_uid
	_next_uid += 1
	c.id = str(spec.get("id", ""))
	c.spec = spec
	c.crew_id = int(e.get("crew_id", -1))
	c.ctx = e.duplicate()
	_resolve(c)
	c.urgency = str(spec.get("urgency", "일반"))
	c.text = str(spec.get("text", ""))
	var opts: Array = spec.get("options", [])
	for v: Dictionary in spec.get("variants", []):
		if _matches(v.get("if", {}), c.ctx):
			c.text = str(v.get("text", c.text))
			opts = v.get("options", opts)
			c.urgency = str(v.get("urgency", c.urgency))
	c.text = c.text.format(c.ctx)
	c.monologue = str(spec.get("monologue", "")).format(c.ctx)
	c.options = _shuffled(opts, c.uid)
	c.asked_tick = tick
	# 지휘권 이양 뒤 단위대에 묶인 출동대: 단위지휘관이 대신 처리한다 (기획안 3-3, R13)
	var by := sim.transfer.delegates(c.crew_id) if sim and sim.transfer else ""
	if by != "":
		var pick: Dictionary = {}
		for o: Dictionary in opts:
			if str(o.get("grade", "")) == "최선":
				pick = o
		_log(c, tick, pick, "delegated")
		events.add(tick, "card_delegated", {"crew": _crew_name(c.crew_id), "title": str(spec.get("title", c.id)), "by": by})
		if not pick.is_empty():
			_apply(str(pick.get("effect", "")), c, tick)
		return
	# 임무 조건 (R7): 진입구에서 정한 조건이 있으면 카드 없이 그 행동 (등급은 같은 행동의 선택지)
	var ce := tactical.condition_effect(c.crew_id, c.id)
	if ce != "":
		for o: Dictionary in opts:
			if str(o.get("effect", "")) == ce:
				_log(c, tick, o, "condition")
				events.add(tick, "card_condition", {"crew": _crew_name(c.crew_id), "title": str(spec.get("title", c.id)), "option": str(o.get("text", ""))})
				_apply(ce, c, tick)
				return
	# 문 앞 휠로 미리 정한 문 처리 (P4-2): 카드 없이 그대로, 등급은 같은 행동의 선택지
	if _door_preordered(c, opts, tick):
		return
	# 예비 소방용수를 정해 두었으면 소화전 고장에 묻지 않고 다음 소화전으로 (P9-1)
	if str(spec.get("trigger", "")) == "hydrant_out" and sim and sim.command.reserve_water and sim.next_hydrant(str(c.ctx.get("vehicle", "")), tick):
		_log(c, tick, {"text": "예비 소방용수로 옮김 (출동 중 선정)", "grade": "최선", "effect": "next_hydrant"}, "preordered")
		events.add(tick, "card_preordered", {"crew": _crew_name(c.crew_id), "title": str(spec.get("title", c.id))})
		return
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
	# 대원 판단 장면을 껐으면: 대원이 SOP대로 알아서 하고 보고만 한다 (지휘관 훈련)
	if c.judgment() and not crew_judgment:
		var sop: Dictionary = {}
		for o: Dictionary in opts:
			if str(o.get("grade", "")) == "최선":
				sop = o
		_log(c, tick, sop, "crew_auto")
		events.add(tick, "crew_decided", {"crew": _crew_name(c.crew_id), "title": str(spec.get("title", c.id)), "option": str(sop.get("text", "")), "auto": true})
		if not sop.is_empty():
			_apply(str(sop.get("effect", "")), c, tick)
		return
	if queue.size() >= _queue_max:
		_log(c, tick, null, "overflow")
		if c.ctx.has("squad_id") and str(spec.get("trigger", "")) == "entry_request" and sim:
			sim.command.entry_request_expired(int(c.ctx.squad_id), tick)
		events.add(tick, "card_overflow", {"crew": _crew_name(c.crew_id), "title": str(spec.get("title", c.id))})
		return
	c.deadline_tick = tick + roundi(float(spec.get("time_limit_sec", _seconds.get(c.urgency, 20.0))) * time_factor * clock_scale / SimClock.TICK_DT)
	queue.append(c)
	queue.sort_custom(func(a: Card, b: Card) -> bool:
		var ua: int = URGENCY_ORDER.get(a.urgency, 2)
		var ub: int = URGENCY_ORDER.get(b.urgency, 2)
		return ua < ub or (ua == ub and a.uid < b.uid))
	events.add(tick, "card_asked", {"crew": _crew_name(c.crew_id), "title": str(spec.get("title", c.id)), "urgency": c.urgency})


## 이 카드가 문 카드이고 그 조가 그 문을 문 앞 휠로 정해 두었으면 그대로 처리하고 true
func _door_preordered(c: Card, opts: Array, tick: int) -> bool:
	var door := _opening(c.ctx.get("door", []))
	if door == null or c.crew_id < 0:
		return false
	var m := tactical.door_method(c.crew_id, door.index)
	if m.is_empty():
		return false
	tactical.door_methods.erase(c.crew_id)
	var pick: Dictionary = {"text": str(m.label), "grade": "허용", "effect": str(m.effect)}
	for o: Dictionary in opts:
		if str(o.get("effect", "")) == str(m.effect):
			pick = o.duplicate()
			pick["text"] = "%s (문 앞 휠: %s)" % [str(o.get("text", "")), str(m.label)]
			break
	_log(c, tick, pick, "preordered")
	events.add(tick, "card_preordered", {"crew": _crew_name(c.crew_id), "title": str(c.spec.get("title", c.id))})
	if bool(m.check):
		_delayed.append({"tick": tick + int(m.check_ticks), "effect": str(m.effect), "card": c})
		events.add(tick, "card_info_check", {"crew": _crew_name(c.crew_id), "seconds": roundi(int(m.check_ticks) * SimClock.TICK_DT)})
	else:
		_apply(str(m.effect), c, tick)
	return true


## 문 앞 휠을 골랐을 때 그 조·그 문 카드가 이미 떠 있으면 바로 처리한다
func preempt_door(crew_id: int, door_index: int, tick: int) -> void:
	for c in queue.duplicate():
		var door := _opening(c.ctx.get("door", []))
		if c.crew_id == crew_id and door and door.index == door_index:
			queue.erase(c)
			_door_preordered(c, c.options, tick)
			return


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


## 사건에 없는 문맥을 시뮬레이션 상태에서 채운다 (방·구조대상자·차량·묻는 조)
func _resolve(c: Card) -> void:
	if sim == null:
		return
	var room := _room_named(str(c.ctx.get("room", "")))
	if room:
		var cell: Vector2i = room.cells[room.cells.size() / 2]
		c.ctx["room_cell"] = [cell.x, cell.y, room.level]
		c.ctx["room_index"] = room.index
	var who := str(c.ctx.get("who", ""))
	for v in rescue.victims:
		if v.label() == who:
			c.ctx["victim"] = v.id
	if c.crew_id < 0:
		var near := Vector2(room.rect.get_center()) if room else Vector2(fire.building.footprint(1).get_center())
		c.crew_id = _nearest_crew(near, room.level if room else -1)
	# 카드 글에 쓰는 값 (P9)
	match str(c.spec.get("trigger", "")):
		"evac_order":
			c.ctx["floor"] = fire.building.floor_name(sim.fire_floor_reported())
		"rit_help":
			var rits := _idle_rit()
			c.ctx["rit"] = _crew_name(rits[0]) if not rits.is_empty() else "RIT"
			c.ctx["rit_id"] = rits[0] if not rits.is_empty() else -1
		"jump_risk":
			# 굴절차가 현장에 서 있으면 바스켓 구조 선택지가 있는 변형 (SOP 326-2.13)
			c.ctx["aerial_ready"] = _aerial() != null
		"tanker_arrived":
			if not c.ctx.has("vehicle"):
				c.ctx["vehicle"] = "%s 물탱크차" % str(c.ctx.get("squad", ""))


func _room_named(name: String) -> Compartment:
	if name == "":
		return null
	for comp in fire.comps:
		if comp.display_name() == name or comp.name == name:
			return comp
	return null


## p 가까이 있는 움직일 수 있는 조 (같은 층 우선). type이 있으면 그 출동대 종류만
func _nearest_crew(p: Vector2, level := -1, type := "") -> int:
	var best := -1
	var best_d := INF
	for cr in units.crews:
		var s := units.squads[cr.squad_id]
		if cr.leader.incapacitated or cr.leader.aboard or (type != "" and s.type != type) or s.type == "구급대":
			continue
		if sim.command.resources.is_en_route(s.id):
			continue
		var d := cr.leader.pos.distance_to(p) + (0.0 if level < 0 or cr.leader.level == level else 40.0)
		if d < best_d:
			best_d = d
			best = cr.id
	return best


# --- 행동 (결과는 시뮬레이션이 만든다) ---

func _apply(effect: String, c: Card, tick: int) -> void:
	var crew := units.get_crew(c.crew_id)
	# 조가 없어도 되는 행동 (차량·대피 방송·안전구역·RIT 등)
	const NO_CREW := ["entry_grant", "entry_wait", "entry_deny", "dropoff_wait", "dropoff_ambulance", "dropoff_entrance",
		"tag_urgent", "tag_emergent", "tag_minor", "tag_delayed", "shuttle", "clear_zone", "shelter", "evacuate_now", "note", "hold", "", "connect_fdc", "supply_pump", "rit_deploy", "air_mat",
		"tanker_supply", "tanker_hydrant", "tanker_idle", "evac_fire_first", "evac_bottom_up", "rit_help", "monitor_now", "aerial_rescue", "post_move_safe"]
	if crew == null and not effect in NO_CREW:
		return
	var here := crew.leader.pos if crew else Vector2(fire.building.footprint(1).get_center())
	var here_level := crew.leader.level if crew else 1
	var door := _opening(c.ctx.get("door", []))
	var action := str(c.ctx.get("action", ""))
	var target := _cell(c.ctx.get("target", []))
	match effect:
		"reserve_water":
			if sim:
				sim.command.reserve_water = true
				events.add(tick, "dispatch_request", {"what": "예비 소방용수 2개소 선정 — 운전원에게 전파"})
		"relay_all", "relay_fire":
			if sim:
				sim.relay_request(effect == "relay_all", tick)
		"fetch_equipment":
			if sim:
				sim.doors.order_fetch(c.crew_id, str(c.ctx.get("item_key", "")), _cell(c.ctx.get("door", [])), tick)
		"nozzle_straight", "nozzle_fog", "nozzle_pencil", "nozzle_cover":
			var pats := {"nozzle_straight": HoseLine.Pattern.STRAIGHT, "nozzle_fog": HoseLine.Pattern.FOG, "nozzle_pencil": HoseLine.Pattern.PENCIL, "nozzle_cover": HoseLine.Pattern.COVER}
			tactical.set_nozzle(c.crew_id, int(pats[effect]))
		"dropoff_wait", "dropoff_ambulance", "dropoff_entrance":
			if sim:
				sim.rescue.set_dropoff_policy(effect.trim_prefix("dropoff_"), tick)
		"tag_urgent", "tag_emergent", "tag_minor", "tag_delayed":
			if sim:
				var tags := {"tag_urgent": EmsSystem.Triage.URGENT, "tag_emergent": EmsSystem.Triage.EMERGENT, "tag_minor": EmsSystem.Triage.MINOR, "tag_delayed": EmsSystem.Triage.DELAYED}
				sim.ems.set_tag(int(c.ctx.get("victim_id", -1)), int(tags[effect]), tick)
		"entry_grant", "entry_wait", "entry_deny":
			if sim:
				sim.command.answer_entry(int(c.ctx.get("squad_id", -1)), effect.trim_prefix("entry_"), tick)
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
		"close_then_resume":
			# 화재실 문을 닫고(210-3.5) 닫히면 하던 검색을 이어 간다
			var fr := _room_named(str(c.ctx.get("room", "")))
			var fd := _door_of(fr, crew) if fr else null
			if fd:
				tactical.cancel(c.crew_id)
				doors.request(c.crew_id, Vector3i(fd.cells[0].x, fd.cells[0].y, fd.level), false, tick)
				_followups.append({"kind": "closed", "crew": c.crew_id, "door": fd.index, "action": action, "target": target})
		"attack_found":
			tactical.order("attack", c.crew_id, _cell(c.ctx.get("room_cell", [])), tick)
		"halt_here":
			tactical.cancel(c.crew_id)
			rescue.cancel(c.crew_id)
		"withdraw":
			tactical.order("withdraw", c.crew_id, Vector3i.ZERO, tick)
		"overhaul":
			var room := _cell(c.ctx.get("room_cell", []))
			rekindle.order_overhaul(c.crew_id, room, tick)
		"flood":
			var room := _cell(c.ctx.get("room_cell", []))
			water.start_spray(c.crew_id, room, HoseLine.Pattern.STRAIGHT, tick)
		"close_room_door", "cool_and_close":
			var r := _room_named(str(c.ctx.get("room", "")))
			if r:
				if effect == "cool_and_close" and water.hose_of_crew(c.crew_id):
					water.start_spray(c.crew_id, _cell(c.ctx.get("room_cell", [])), HoseLine.Pattern.FOG, tick)
				else:
					var d := _door_of(r, crew)
					if d:
						doors.request(c.crew_id, Vector3i(d.cells[0].x, d.cells[0].y, d.level), false, tick)
		"air_mat":
			var v := int(c.ctx.get("victim", -1))
			var rc := _nearest_crew(here, 1, "구조대")
			if v >= 0 and rc >= 0:
				var below := sim.falls.ground_below(rescue.victims[v])
				if below.x >= 0:
					sim.falls.order_mat(rc, Vector2i(below.floor()), tick)
		"exterior_cover":
			var w := _hot_window()
			if w:
				tactical.order("exterior", c.crew_id, Vector3i(w.cells[0].x, w.cells[0].y, w.level), tick)
		"check_shaft":
			for lv: int in sim.shafts.shaft_rooms:
				if sim.shafts.hot.has(lv - 1) and not sim.shafts.checked.has(lv):
					var sh: Compartment = sim.shafts.shaft_rooms[lv]
					var sc: Vector2i = sh.cells[0]
					tactical.order("search", c.crew_id, Vector3i(sc.x, sc.y, lv), tick)
					break
		"clear_zone":
			for z: Dictionary in sim.falls.zones:
				for ff in units.firefighters:
					if ff.level == 1 and not ff.aboard and ff.pos.distance_to(z.center) <= float(z.radius) + 1.0:
						var away: Vector2 = z.center + (ff.pos - z.center).normalized() * (float(z.radius) + 3.0)
						var spot := sim.pathfinder.nearest_walkable(1, Vector2i(away.floor()))
						if spot != Pathfinder.NO_CELL:
							units.order_move([ff.crew_id] as Array[int], Vector3i(spot.x, spot.y, 1), sim.pathfinder)
		"shuttle":
			for v in units.vehicles:
				if v.transfer_lpm > 0.0 and not v.away and not sim.shuttle.tankers.has(v.id):
					sim.shuttle.toggle(v.id, tick)
					break
		"supply_pump":
			var pump := _vehicle_named(str(c.ctx.get("vehicle", "")))
			for v in units.vehicles:
				if pump and v.transfer_lpm > 0.0 and not v.away and v.supply_to < 0:
					if water.hydrants_out.size() >= fire.building.hydrants.size() and sim.shuttle.available():
						sim.shuttle.toggle(v.id, tick)
					else:
						water.connect_supply(v.id, pump.id, tick)
					break
		"rit_deploy":
			var downed := -1
			for ff in units.firefighters:
				if ff.incapacitated:
					downed = ff.id
					break
			var rits := sim.command.safety.crews_with(SafetySystem.Role.RIT)
			var rescuer: int = rits[0] if not rits.is_empty() else _nearest_crew(here, here_level)
			if downed >= 0 and rescuer >= 0:
				sim.command.safety.deploy(rescuer, tick)
				rescue.order_rescue(rescuer, "ff", downed, tick)
		"gas_off":
			sim.gas.order_off(c.crew_id, tick)
		"rescue_trapped":
			# 신고된 층을 검색 (위치를 알려 주지 않는다 — 대원이 찾아야 발견)
			var lv := int(c.ctx.get("level", -1))
			if lv >= 0:
				var rc := _nearest_crew(Vector2(fire.building.footprint(lv).get_center()), lv, "구조대")
				if rc < 0:
					rc = _nearest_crew(Vector2(fire.building.footprint(lv).get_center()), lv)
				if rc >= 0:
					tactical.order("search_floor", rc, Vector3i(0, 0, lv), tick)
		"connect_fdc":
			var best := -1
			var best_d := INF
			for v in units.vehicles:
				if v.is_pump() and not v.away:
					var d := v.distance_to_body(Vector2(fire.building.fdc))
					if d < best_d:
						best_d = d
						best = v.id
			if best >= 0:
				water.connect_fdc(best, tick)
		"tanker_supply", "tanker_hydrant":
			# 물탱크차 첫 조치 (기획안 7-3, SOP 200-3.1.1.2): 펌프차 급수 연결 또는 소화전 점령
			var tk := _tanker(str(c.ctx.get("vehicle", "")))
			if tk:
				var pump: Vehicle = null
				for v in units.vehicles:
					if v.is_pump() and not v.away and (pump == null or v.pos.distance_to(tk.pos) < pump.pos.distance_to(tk.pos)):
						pump = v
				if effect == "tanker_supply" and pump:
					water.connect_supply(tk.id, pump.id, tick)
				else:
					var hy := _nearest_hydrant(tk.pos)
					if hy >= 0:
						water.connect_hydrant(tk.id, hy, tick)
		"tanker_idle":
			events.add(tick, "tanker_idle", {"vehicle": str(c.ctx.get("vehicle", ""))})
		"evac_fire_first", "evac_bottom_up":
			sim.evac.set_priority(effect.trim_prefix("evac_"), sim.fire_floor_reported(), tick)
		"rit_help":
			# RIT를 호스 연장에 쓴다 → RIT가 없어진다 (SSG 9 1.2.2 위반)
			var rid := int(c.ctx.get("rit_id", -1))
			if rid >= 0:
				sim.command.safety.roles.erase(rid)
				sim.command.safety.deployed.erase(rid)
				events.add(tick, "rit_misused", {"crew": _crew_name(rid), "helping": str(c.ctx.get("crew", ""))})
				var helped := units.get_crew(int(c.ctx.get("crew_id", -1)))
				if helped:
					units.order_move([rid] as Array[int], helped.leader.cell3(), sim.pathfinder)
		"ppv_exhaust":
			# 배기구(바람길 구획의 창)를 먼저 연다: 그 층에서 송풍기 조가 아닌 가장 가까운 조가 창을 깬다
			var w := sim.vent.exhaust_window()
			if w:
				var center := Vector2(w.cells[0]) + Vector2(0.5, 0.5)
				var best := -1
				var best_d := INF
				for cr in units.crews:
					if cr.id == sim.vent.crew_id or cr.leader.incapacitated or cr.leader.aboard or cr.leader.level != w.level:
						continue
					if units.squads[cr.squad_id].type == "구급대" or sim.command.safety.reserved(cr.id):
						continue
					var d := cr.leader.pos.distance_to(center)
					if d < best_d:
						best_d = d
						best = cr.id
				if best >= 0:
					doors.request(best, Vector3i(w.cells[0].x, w.cells[0].y, w.level), true, tick)
					events.add(tick, "ppv_exhaust_order", {"crew": _crew_name(best), "room": fire.comps[w.room_a].display_name()})
				else:
					events.add(tick, "ppv_exhaust_none", {})
			else:
				events.add(tick, "ppv_exhaust_none", {})
		"ppv_stop":
			sim.vent.cancel(sim.vent.crew_id, tick)
		"post_move_safe":
			# 지휘소를 위험반경 밖으로 (P4-4, SOP 104-1.3)
			var safe := sim.command.post.safer_post() if sim and sim.command.post else Vector2i(-1, -1)
			if safe.x >= 0:
				sim.command.post.set_post(safe, tick, "낙하물 위험반경 밖으로 이동")
		"monitor_now":
			sim.monitors.start(int(c.ctx.get("vehicle_id", -1)), _cell(c.ctx.get("target", [])), tick, true)
		"aerial_rescue":
			var av := _aerial()
			var vid := int(c.ctx.get("victim", -1))
			if av and vid >= 0:
				sim.aerial.order_rescue(av.id, vid, tick)
			# 바스켓이 닿지 않으면(높이·거리) 매트로라도 받친다
			if vid >= 0 and not sim.falls.held.has(vid):
				var rc := _nearest_crew(here, 1, "구조대")
				var below := sim.falls.ground_below(rescue.victims[vid])
				if rc >= 0 and below.x >= 0:
					sim.falls.order_mat(rc, Vector2i(below.floor()), tick)
		"ppv_force":
			sim.vent.forced = true
		"shelter":
			sim.evac.instruction = "shelter"
		"evacuate_now":
			sim.evac.instruction = "evacuate"
		"hold", "note", "":
			pass


func _step_followups(tick: int) -> void:
	for d in _delayed.duplicate():
		if tick >= int(d.tick):
			_delayed.erase(d)
			_apply(str(d.effect), d.card, tick)
	for f in _followups.duplicate():
		if str(f.get("kind", "")) == "closed":
			var fd: Opening = fire.openings[int(f.door)]
			if not fd.is_open or doors.task_of_crew(int(f.crew)) == null:
				_followups.erase(f)
				if str(f.action) != "":
					tactical.order(str(f.action), int(f.crew), f.target, tick)
			continue
		var win: Opening = fire.openings[int(f.window)]
		if win.broken or win.is_open:
			_followups.erase(f)
			tactical.allow_door(int(f.crew), int(f.door))
			tactical.order(str(f.action) if str(f.action) != "" else "attack", int(f.crew), f.target, tick)


## 지금 가장 많이 달궈진 인접·위층 창 (경계관창 목표)
func _hot_window() -> Opening:
	var best: Opening = null
	var best_d := 0.0
	for i: int in sim.exposure.dose:
		if float(sim.exposure.dose[i]) > best_d and not sim.exposure.ignited.has(i):
			best_d = float(sim.exposure.dose[i])
			best = fire.openings[i]
	return best


## 현장에 서 있는 굴절차 (없으면 null)
func _aerial() -> Vehicle:
	if sim == null:
		return null
	for v in units.vehicles:
		if v.is_aerial() and not v.away and not sim.command.resources.is_en_route(v.squad_id):
			return v
	return null


## 이름이 맞는 물탱크차 (없으면 아직 급수하지 않는 아무 물탱크차)
func _tanker(name: String) -> Vehicle:
	var any: Vehicle = null
	for v in units.vehicles:
		if v.transfer_lpm <= 0.0 or v.away:
			continue
		if v.display_name(units.squads[v.squad_id].name) == name or name.begins_with(units.squads[v.squad_id].name):
			return v
		if any == null and v.supply_to < 0:
			any = v
	return any


func _nearest_hydrant(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in fire.building.hydrants.size():
		if i in water.hydrants_out:
			continue
		var d := p.distance_to(Vector2(fire.building.hydrants[i]))
		if d < best_d:
			best_d = d
			best = i
	return best


func _vehicle_named(name: String) -> Vehicle:
	for v in units.vehicles:
		if v.display_name(units.squads[v.squad_id].name) == name:
			return v
	return null


## 방의 문 중 조에게 가장 가까운 문
func _door_of(room: Compartment, crew: Crew) -> Opening:
	var best: Opening = null
	var best_d := INF
	for oi in room.openings:
		var o := fire.openings[oi]
		if o.kind == Opening.Kind.DOOR and o.is_open:
			var d := crew.leader.pos.distance_to(Vector2(o.cells[0]))
			if d < best_d:
				best_d = d
				best = o
	return best


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
		"sop": ", ".join(PackedStringArray(c.spec.get("sop_ref", []))), "debrief": str(c.spec.get("debrief", "")),
		"scene": "judgment" if c.judgment() else "radio"})


func _crew_name(crew_id: int) -> String:
	var c := units.get_crew(crew_id)
	return "%s %d조" % [units.squads[c.squad_id].name, c.number] if c else "현장 대원"
