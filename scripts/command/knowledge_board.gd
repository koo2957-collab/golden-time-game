class_name KnowledgeBoard
extends RefCounted
## 지휘관이 아는 것 (기획안 9-1 '보이는 것과 기록되는 것은 다르다', CLAUDE.md 규칙 7, P10-1).
## 무전으로 보고가 전달된 때에만 쌓는다 — 전술상황판은 이것만 읽어 그린다 (실제 상태를 직접 읽지 않는다).
##   팀: 마지막으로 무전을 보낸 위치·시각 / 화점·연소 확대 / 요구조자(보고·구조) / 위험 징후 / 검색 완료 구획
## 밖의 것(차량·소화전·구역·진입구·지휘소)은 지휘관이 직접 보는 것이라 여기 두지 않는다.

var fire: FireSim
var units: UnitSystem
var rescue: RescueSystem

## 조 id → {pos: Vector2, level, tick}
var crews: Dictionary = {}
## 구획 index → 보고 틱 (불이 있다고 보고됨). 초진·진압 보고로 지운다
var fires: Dictionary = {}
## 요구조자 id → {state: "보고"·"구조", pos: Vector2, level, tick}
var victims: Dictionary = {}
## [{kind, room, pos: Vector2, level, tick}] (롤오버·백드래프트·FGI·붕괴 징후·붕괴·가스)
var hazards: Array[Dictionary] = []
## 구획 index → 틱 (검색 완료)
var searched: Dictionary = {}
## 연기가 있다고 보고된 구획 index → 틱
var smoky: Dictionary = {}

const HAZARD_TYPES := {"rollover_sign": "롤오버", "backdraft_sign": "백드래프트 징후", "fgi_warning": "FGI 위험",
	"collapse_sign": "붕괴 징후", "collapse": "붕괴", "gas_explosion": "가스 폭발", "backdraft": "백드래프트"}


func _init(p_fire: FireSim, p_units: UnitSystem, p_rescue: RescueSystem) -> void:
	fire = p_fire
	units = p_units
	rescue = p_rescue


## 무전 한 건이 지휘관에게 전달됨 (Radio.on_delivered): 보낸 조의 위치, 실린 사건(보고 내용)
func on_message(m: Radio.Message, tick: int) -> void:
	var c := _crew_named(m.sender)
	if c:
		crews[c.id] = {"pos": c.leader.pos, "level": c.leader.level, "tick": tick}
	if not m.data.is_empty():
		apply(m.data, tick)


## 보고 사건 하나를 상황판에 올린다
func apply(e: Dictionary, tick: int) -> void:
	var t := str(e.get("type", ""))
	match t:
		"fire_found":
			var room := _room_of(e)
			if room:
				fires[room.index] = tick
				smoky[room.index] = tick
		"knockdown_reported":
			fires.clear()
		"tactical_done":
			# "거실 화염 진압, 방수 중지" — 그 방 불은 꺼짐으로
			for idx: int in fires.keys():
				if str(e.get("text", "")).begins_with(fire.comps[idx].display_name()) and str(e.get("text", "")).contains("진압"):
					fires.erase(idx)
		"victim_found":
			var v := _victim_named(str(e.get("who", "")))
			if v:
				victims[v.id] = {"state": "보고", "pos": v.pos, "level": v.level, "tick": tick}
		"victim_rescued", "victim_handover":
			var v := _victim_named(str(e.get("who", "")))
			if v:
				victims[v.id] = {"state": "구조", "pos": v.pos, "level": v.level, "tick": tick}
		"search_done":
			var room := _room_of(e)
			if room:
				searched[room.index] = tick
		"stair_smoke", "shaft_smoke":
			var room := _room_of(e)
			if room:
				smoky[room.index] = tick
	if HAZARD_TYPES.has(t):
		var room := _room_of(e)
		var pos := Vector2(room.rect.get_center()) if room else Vector2(-1, -1)
		hazards.append({"kind": HAZARD_TYPES[t], "room": room.index if room else -1, "pos": pos, "level": room.level if room else 1, "tick": tick})


## 보고 시각으로부터 지난 초 (없으면 -1)
static func age_s(since_tick: int, now_tick: int) -> float:
	return (now_tick - since_tick) * SimClock.TICK_DT if since_tick >= 0 else -1.0


func _room_of(e: Dictionary) -> Compartment:
	var rc: Variant = e.get("room_cell", null)
	if rc is Array and (rc as Array).size() >= 3:
		return fire.compartment_at(int(rc[2]), int(rc[0]), int(rc[1]))
	var name := str(e.get("room", ""))
	if name == "":
		return null
	for c in fire.comps:
		if c.display_name() == name:
			return c
	return null


func _crew_named(sender: String) -> Crew:
	for c in units.crews:
		var name := "%s %d조" % [units.squads[c.squad_id].name, c.number]
		if sender == name or sender.begins_with(name + " "):
			return c
	return null


func _victim_named(who: String) -> Victim:
	for v in rescue.victims:
		if v.label() == who:
			return v
	return null
