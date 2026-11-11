class_name Radio
extends RefCounted
## 무전 채널 하나 (SOP 107). 지휘망 하나와 단위대마다 작전망을 둔다 (107-3.2). 한 번에 한 사람만 송신하고, 기다리는 송신은 우선순위 순으로 나간다.
## 우선순위 (107-1.3): 대원 안전 → 구조대상자 → 재난현장 주요요소 → 전략·전술.
## 송신 시간은 호출 시간 + 본문 길이에 비례한다. 명령은 송신이 끝나야 받는 쪽에 전달된다.

enum Priority { SAFETY, VICTIM, KEY_FACTOR, TACTICS }
const PRIORITY_NAMES: Array[String] = ["대원 안전", "구조대상자", "주요요소", "전략·전술"]


class Message:
	extends RefCounted
	var seq := 0
	var priority := Priority.TACTICS
	var sender := ""
	var receiver := ""
	var body := ""
	var duration_s := 0.0
	var queued_tick := 0
	var start_tick := -1
	var end_tick := -1
	## 송신이 끝나면 호출 (tick을 받는다). 명령은 이때 받는 쪽에 전달된다.
	var on_sent := Callable()
	## 실린 보고 사건 (대원 보고, P10-1 상황판) — 비어 있으면 일반 무전
	var data: Dictionary = {}
	## 지휘관 지시인가 (무전 기록 '내 지시' 필터)
	var mine := false
	## 이동지휘 중이라 지휘관이 놓친 보고 (P4-4) — 상황판에 오르지 않는다
	var missed := false

	## 무전 문장: "받는 쪽, 보내는 쪽. 본문"
	func text() -> String:
		return "%s, %s. %s" % [receiver, sender, body]


## 채널 이름 (지휘망, 작전망 1 …)
var channel := "지휘망"
var queue: Array[Message] = []
var current: Message
## 송신이 끝난 무전 (오래된 것부터)
var history: Array[Message] = []
## 송신이 끝날 때마다 (Message, tick) — 상황판(KnowledgeBoard)이 듣는다
var on_delivered := Callable()
## 즉시 지시 (2026-11-11 사용자 결정 ③): 지휘관 지시와 대원의 복명복창은 채널에 줄 서지 않고 바로 전달·기록한다.
## 대원 → 지휘관 보고는 그대로 줄을 서서 늦게 온다 (보고된 정보만 상황판에). 훈련·실전 = 켬, 악조건 = 끔 (SimWorld.apply_realism)
var instant_orders := false
var events: SimEventLog

var _call_s: float
var _per_char_s: float
var _max_s: float
var _gap_s: float
var _instant_char_scale := 1.0
var _remaining := 0.0
var _gap := 0.0
var _seq := 0


func _init(params: ParamTable, p_events: SimEventLog, p_channel := "지휘망") -> void:
	events = p_events
	channel = p_channel
	_call_s = params.value("call_s")
	_per_char_s = params.value("per_char_s")
	_max_s = params.value("max_message_s")
	_gap_s = params.value("gap_s")
	_instant_char_scale = params.value("instant_char_scale")


func send(priority: Priority, sender: String, receiver: String, body: String, tick: int, on_sent := Callable()) -> Message:
	var m := Message.new()
	_seq += 1
	m.seq = _seq
	m.priority = priority
	m.sender = sender
	m.receiver = receiver
	m.body = body
	m.duration_s = minf(_max_s, _call_s + body.length() * _per_char_s * (_instant_char_scale if instant_orders else 1.0))
	m.queued_tick = tick
	m.on_sent = on_sent
	m.mine = sender == CommandSystem.COMMANDER
	if instant_orders and m.mine:
		_deliver_now(m, tick)
		return m
	queue.append(m)
	queue.sort_custom(func(a: Message, b: Message) -> bool:
		return a.priority < b.priority or (a.priority == b.priority and a.seq < b.seq))
	return m


## 복명복창·진입 허가 요청처럼 지휘관의 결정을 기다리는 대원 무전. 즉시 지시면 바로 기록·전달, 아니면 일반 송신
func send_ack(priority: Priority, sender: String, receiver: String, body: String, tick: int, on_sent := Callable()) -> Message:
	if not instant_orders:
		return send(priority, sender, receiver, body, tick, on_sent)
	var m := Message.new()
	m.on_sent = on_sent
	_seq += 1
	m.seq = _seq
	m.priority = priority
	m.sender = sender
	m.receiver = receiver
	m.body = body
	_deliver_now(m, tick)
	return m


func _deliver_now(m: Message, tick: int) -> void:
	m.queued_tick = tick
	m.start_tick = tick
	_finish(m, tick)


func busy() -> bool:
	return current != null or not queue.is_empty()


## 지금 송신 중인 무전의 진행 비율 (0~1)
func progress() -> float:
	if current == null or current.duration_s <= 0.0:
		return 0.0
	return clampf(1.0 - _remaining / current.duration_s, 0.0, 1.0)


func step(dt: float, tick: int) -> void:
	if current:
		_remaining -= dt
		if _remaining > SimClock.EPSILON:
			return
		_finish(current, tick)
		current = null
		_gap = _gap_s
		return
	if _gap > SimClock.EPSILON:
		_gap -= dt
		return
	if not queue.is_empty():
		current = queue.pop_front()
		current.start_tick = tick
		_remaining = current.duration_s


func _finish(m: Message, tick: int) -> void:
	m.end_tick = tick
	history.append(m)
	events.add(tick, "radio", {
		"text": m.text(),
		"priority": PRIORITY_NAMES[m.priority],
		"channel": channel,
		"wait_s": (m.start_tick - m.queued_tick) * SimClock.TICK_DT,
	})
	var cb := m.on_sent
	m.on_sent = Callable()
	if on_delivered.is_valid():
		on_delivered.call(m, tick)
	if cb.is_valid():
		cb.call(tick)
