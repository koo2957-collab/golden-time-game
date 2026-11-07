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

	## 무전 문장: "받는 쪽, 보내는 쪽. 본문"
	func text() -> String:
		return "%s, %s. %s" % [receiver, sender, body]


## 채널 이름 (지휘망, 작전망 1 …)
var channel := "지휘망"
var queue: Array[Message] = []
var current: Message
## 송신이 끝난 무전 (오래된 것부터)
var history: Array[Message] = []
var events: SimEventLog

var _call_s: float
var _per_char_s: float
var _max_s: float
var _gap_s: float
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


func send(priority: Priority, sender: String, receiver: String, body: String, tick: int, on_sent := Callable()) -> Message:
	var m := Message.new()
	_seq += 1
	m.seq = _seq
	m.priority = priority
	m.sender = sender
	m.receiver = receiver
	m.body = body
	m.duration_s = minf(_max_s, _call_s + body.length() * _per_char_s)
	m.queued_tick = tick
	m.on_sent = on_sent
	queue.append(m)
	queue.sort_custom(func(a: Message, b: Message) -> bool:
		return a.priority < b.priority or (a.priority == b.priority and a.seq < b.seq))
	return m


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
	if cb.is_valid():
		cb.call(tick)
