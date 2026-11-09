class_name InteriorOrders
extends RefCounted
## 임무형 내부 지휘 (기획안 9-1, R7). "보이는 곳은 직접, 안 보이는 곳은 임무와 무전으로."
##   - 건물 안에 있는 조에게 내리는 명령은 무전으로 간다: 지휘망에 지시가 송신된 뒤 실행되고,
##     조가 복명복창한다 (SOP 107 3.1⑤ — 지시 → 수신 확인). 밖에 있는 조는 대면 지시라 바로 실행된다.
##   - 건물 안 칸으로의 직접 이동(경유지)은 대원이 본 적 있는 칸에만 찍을 수 있다.
##     본 적 없는 곳은 진압·검색 임무로 맡긴다 (어디서 무엇을 = 지휘관, 어떻게 = 대원).
## 모든 난이도에 적용한다 (2026-11-08 사용자 결정). SimWorld.apply_realism이 켠다 — 지휘 규칙과 무관한 테스트는 끔.

const NOT_SEEN := "본 적 없는 곳에는 경유지를 찍을 수 없습니다 — 진압·검색 임무로 맡기세요"
const ROOM_NOT_SEEN := "본 적 없는 방은 층 단위 임무(층 검색·층 진압)로 맡기세요"

var enabled := false
var fire: FireSim
var units: UnitSystem
var perception: Perception
## 무전으로 보낸 지시 수 (디브리핑·테스트용)
var relayed := 0
## 본 적 없는 곳이라 거절한 이동 수
var rejected := 0
## 도면을 얻었는가 (R8). 얻으면 본 적 없는 방도 방 단위 임무를 줄 수 있다
var plan_known := false


func _init(p_fire: FireSim, p_units: UnitSystem, p_perception: Perception) -> void:
	fire = p_fire
	units = p_units
	perception = p_perception


func indoor(level: int, p: Vector2) -> bool:
	return not fire.building.cell(level, floori(p.x), floori(p.y)) in BuildingData.OUTDOOR


func crew_inside(crew_id: int) -> bool:
	var c := units.get_crew(crew_id)
	return c != null and indoor(c.leader.level, c.leader.pos)


## 명령을 받는 조 (MoveCommand·TacticalCommand·EquipmentCommand)
static func crews_of(cmd: RefCounted) -> Array[int]:
	var out: Array[int] = []
	if cmd is MoveCommand or cmd is TacticalCommand or cmd is EquipmentCommand:
		out.assign(cmd.crew_ids)
	return out


## 이 명령을 거절할 이유 ("" = 허용). 건물 안 칸으로의 이동은 본 적 있는 칸만,
## 방 단위 진압·검색은 본 적 있는 방만 (도면이 없을 때 — 2026-11-08 사용자 결정: 층 단위)
func reject_reason(cmd: RefCounted) -> String:
	if not enabled:
		return ""
	if (cmd is TacticalCommand and cmd.action in ["attack", "search"]) or (cmd is EquipmentCommand and cmd.action == "search"):
		return "" if room_known(cmd.target) else ROOM_NOT_SEEN
	if not cmd is MoveCommand:
		return ""
	var t: Vector3i = cmd.target
	if not indoor(t.z, Vector2(t.x, t.y)):
		return ""
	if perception.is_seen(t.z, t.x, t.y):
		return ""
	return NOT_SEEN


## 방 단위 임무를 줄 수 있는 방인가 (본 적 있거나 도면이 있다). 방이 아닌 칸은 그대로 허용
func room_known(t: Vector3i) -> bool:
	if plan_known:
		return true
	var room := fire.compartment_at(t.z, t.x, t.y)
	return room == null or perception.room_seen[room.index] != 0


## 무전으로 보내야 하는 명령인가 (받는 조 중 하나라도 건물 안)
func needs_radio(cmd: RefCounted) -> bool:
	if not enabled:
		return false
	for id in crews_of(cmd):
		if crew_inside(id):
			return true
	return false


## 철수·긴급 지시는 대원 안전 우선순위로 (107-1.3)
func priority_of(cmd: RefCounted) -> Radio.Priority:
	if cmd is TacticalCommand and cmd.action == "withdraw":
		return Radio.Priority.SAFETY
	return Radio.Priority.TACTICS


## 받는 쪽 이름: "진압1 1조" / "진압1 1조·2조"
func receiver_of(cmd: RefCounted) -> String:
	var names: PackedStringArray = []
	var squad := -1
	for id in crews_of(cmd):
		var c := units.get_crew(id)
		if c == null:
			continue
		if c.squad_id == squad:
			names.append("%d조" % c.number)
		else:
			squad = c.squad_id
			names.append("%s %d조" % [units.squads[c.squad_id].name, c.number])
	return "·".join(names)


## 지시 문장: "2층 거실 진압하라."
func order_text(cmd: RefCounted) -> String:
	return _verb(cmd) + "하라."


## 복명복창: "2층 거실 진압하겠음."
func ack_text(cmd: RefCounted) -> String:
	return _verb(cmd) + "하겠음."


func _verb(cmd: RefCounted) -> String:
	if cmd is MoveCommand:
		return "%s 이동" % _with_ro(_place(cmd.target))
	if cmd is TacticalCommand:
		match cmd.action:
			"attack":
				return "%s 진압" % _place(cmd.target)
			"search":
				return "%s 검색" % _place(cmd.target)
			"search_floor":
				return "%s 검색" % fire.building.floor_name(cmd.target.z)
			"attack_floor":
				return "%s 진압" % fire.building.floor_name(cmd.target.z)
			"check_below":
				return "%s 직하층 확인" % _place(cmd.target)
			"withdraw":
				return "즉시 철수"
			"hold":
				return "현 위치 대기"
			"exterior":
				return "외부 방수"
	if cmd is EquipmentCommand:
		match cmd.action:
			"door_open":
				return "%s 문 개방" % _place(cmd.target)
			"door_close":
				return "%s 문 폐쇄" % _place(cmd.target)
			"search":
				return "%s 인명검색" % _place(cmd.target)
			"spray":
				return "%s 방수 개시" % _place(cmd.target)
			"stop":
				return "방수 중지"
			"rescue":
				return "구조대상자 구조"
			"rescue_ff":
				return "쓰러진 대원 구조"
			"overhaul":
				return "%s 잔불정리" % _place(cmd.target)
			"gas_off":
				return "가스 밸브 차단"
			"hose", "hose_outlet":
				return "수관 연장"
	return "지시 수행"


## "거실" → "거실로", "주방" → "주방으로" (받침 있으면 으로, ㄹ 받침은 로)
static func _with_ro(word: String) -> String:
	if word.is_empty():
		return word
	var code := word.unicode_at(word.length() - 1)
	if code < 0xAC00 or code > 0xD7A3:
		return word + "(으)로"
	var jong := (code - 0xAC00) % 28
	return word + ("으로" if jong != 0 and jong != 8 else "로")


## 칸 → "2층 거실" (방 이름이 없으면 층 이름)
func _place(t: Vector3i) -> String:
	var c := fire.compartment_at(t.z, t.x, t.y)
	if c:
		return c.display_name()
	return fire.building.floor_name(t.z)
