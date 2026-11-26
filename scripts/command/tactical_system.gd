class_name TacticalSystem
extends RefCounted
## 고수준 명령 (분대 명령칸). 명령 하나에 SOP 순서대로 여러 행동이 자동으로 이어진다.
##   진압 (attack): 수관 연장(호스부터 — 자기 펌프차 후면에서 꺼낸다, 2026-11-24) → 길의 닫힌 문 개방 → 접근·분무 방수 (WaterSystem) → 그 방 불이 꺼지면 방수 중지
##   외부 방수 (exterior): 밖에서 직사로 연소 확대 저지
##   수색 (search): 길의 닫힌 문 개방 → 인명검색 → 찾은 구조대상자 이송 (자동화 수준에 따라)
##   철수 (withdraw): 그 조만 가장 가까운 문 밖으로
##   층 검색·층 진압 (search_floor·attack_floor, R7): 본 적 없는 곳은 층 단위로 맡긴다 (기획안 9-1).
##     층 검색은 아직 검색하지 않은 방을 가까운 곳부터 차례로, 층 진압은 그 층에서 타는 방을 찾아 차례로 진압
##   화점 발견·요구조자 발견·공기 경보는 질문 카드로 묻는다 (임무 조건 미리 정하기는 2026-11-17에 없앴다)
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
	## 진입구를 거쳐 간다 (P4-2): 먼저 그 바깥 칸으로, 닿으면 문 목록을 다시 정한다. x < 0이면 없음
	var via := Vector3i(-1, -1, -1)
	## 주수 방법 (P10-2 결정 ②): 화점실 앞에서 카드로 묻고 고른 HoseLine.Pattern (-1 = 아직)
	var nozzle := -1
	var nozzle_asked := false
	var nozzle_wait_until := -1
	## 직하층 확인: 남은 방 (구획 index)과 위·아래 세대 이름
	var unit_rooms: Array[int] = []
	var unit_check: Dictionary = {}
	## 화재진압은 호스부터 (2026-11-24): 수관 연장을 한 번 시켰는가 / 펌프차 후면에서 꺼내 오기를 기다리는 중인가
	var hose_asked := false
	var hose_wait := false


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
## 임무 수치 (data/command/mission_params.json)
var mission_data: Dictionary = {}
## 진입구 (P4-2 진입 지시 기록용)
var entries: EntryPoints
## 화점진압 조가 화점실 앞에서 주수 방법을 질문 카드로 묻는가 (지휘 규칙을 켠 판, P10-2)
var nozzle_cards := false
var _hot_layer_c := 300.0
var _pencil_done_c := 150.0
var _nozzle_wait_ticks := 300
var _fire_radius := 5.0
var _fire_seen: Dictionary = {}  # "조:방" -> true
## 화점진압 임무를 받은 틱 {조 id: tick} — 화점에 물을 대면 지운다 (화점 못 찾음 보고, 기획안 7-3)
var _attack_since: Dictionary = {}
var _fire_lost_ticks := 9000
var _fire_lost_vis_m := 1.0
## 세대 배치 (P2-2, SimWorld가 넣는다)
var layout: UnitAssembly
## 관계인 진술로 구조대상자가 있다고 들은 방 {구획 id: 말한 사람} (SiteSurvey.reported_rooms를 같이 쓴다, SimWorld가 넣는다)
var reported_rooms: Dictionary = {}
## 검색 순서 한 단계를 거리로 바꾼 값 (칸) — 층 안에서는 순위가 거리보다 늘 먼저다 (게임 설정값: 가장 큰 층보다 넓게)
const SEARCH_RANK_GAP := 1000.0
## 직하층 확인으로 얻은 추정 구조 {위 세대 이름: {from: 아래 세대, variant: 아래 세대 변형, furnish, tick}} — 지휘관이 아는 정보
var unit_estimates: Dictionary = {}
## 초진 틱 (PhaseSystem.knockdown_tick, SimWorld가 넣는다 — 2차 검색 판정)
var knockdown_tick: Callable
## 층 검색을 받은 틱 {조 id: tick} — 초진 뒤에 받았으면 2차 검색
var _search_since: Dictionary = {}
## 층 검색 중 화염·열기로 들어가지 못한 방 {구획 index: 틱} (2026-11-26 사용자·현직 소방관: 화점실이 화염으로 검색 불가면
## 문을 닫고 다른 실을 차례로 검색한다). search_heat_skip_s 동안·초진 전까지는 층 검색이 그 방을 건너뛴다
var heat_skipped: Dictionary = {}
## 건너뛴 뒤 물러나는 중인 조 {조 id: {floor, action, room, door (개구부 index, -1 없음), closing}} — 멈추면 문을 닫고 다음 방으로
var _heat_waits: Dictionary = {}
var _heat_skip_ticks := 0
var _door_close_wait_ticks := 0
## 검색 중인 조가 요구조자의 소리를 듣고 바로 구하러 가는 거리 (칸)
var _victim_hear_cells := 0.0
## 걸어 들어가도 되는 칸인가 (level, cell) -> bool — SimWorld 가 CrewConditionSystem.safe_to_enter 를 넣는다
var heat_ok: Callable
## 외부 방수 중인 조 {조 id: 목표 Vector3i} — 물줄기가 닿는 곳의 불꽃이 사라진 채 exterior_done_s가 지나면 방수를 멈추고 완료 보고.
## 불꽃을 한 번도 못 본 방수(경계관창 — 달궈지는 창 냉각)는 끝내지 않는다 (2026-11-18)
var _exterior: Dictionary = {}
## 대기(이 자리 대기) 지시를 받고 서 있는 조 {조 id: true} — 오른쪽 창의 현재 명령 표시용 (2026-11-27). 다른 지시를 받으면 지운다
var holding: Dictionary = {}
var _exterior_done_ticks := 100
## 경계 관창 (2026-11-24 사용자 결정 — 2026-11-18 '경계관창은 스스로 끝내지 않는다'를 바꿈): 관창을 배치해 두고(잠근 채 겨눔)
## 겨눈 곳이 달궈지거나 불꽃이 나오면 열고, 식으면 잠그고 보고한 뒤 계속 지킨다 (기획안 '경계·연소확대 방지: 관창 배치 → 불이 다가오면 방수').
## 그 자리 가까이의 창이 달궈진 정도 (칸·층) -> 0~1. SimWorld가 넣는다 (ExposureSystem.heat_near)
var exposure_heat := Callable()
## 달궈진 정도가 이 비율 이상이면 열고 / 이 비율 아래로 식고 불꽃도 없으면 잠근다 (mission_params exterior_open_ratio·exterior_close_ratio)
var _exterior_open_ratio := 0.15
var _exterior_close_ratio := 0.03
## 위협(가열·불꽃)이 마지막으로 있던 틱 {조 id: tick} / 개방·잠금을 이미 한 번 보고했는가 {조 id: {"open": true, "hold": true}}
var _ext_calm: Dictionary = {}
var _ext_told: Dictionary = {}


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
	_fire_lost_ticks = roundi(float(mission_data.get("fire_lost_s", {}).get("value", 900.0)) / SimClock.TICK_DT)
	_fire_lost_vis_m = float(mission_data.get("fire_lost_visibility_m", {}).get("value", 1.0))
	_exterior_done_ticks = roundi(float(mission_data.get("exterior_done_s", {}).get("value", 10.0)) / SimClock.TICK_DT)
	_exterior_open_ratio = float(mission_data.get("exterior_open_ratio", {}).get("value", 0.15))
	_exterior_close_ratio = float(mission_data.get("exterior_close_ratio", {}).get("value", 0.03))
	_heat_skip_ticks = roundi(float(mission_data.get("search_heat_skip_s", {}).get("value", 180.0)) / SimClock.TICK_DT)
	_victim_hear_cells = float(mission_data.get("search_victim_divert_m", {}).get("value", 6.0)) / units.cell_size_m
	_door_close_wait_ticks = roundi(float(mission_data.get("search_door_close_wait_s", {}).get("value", 20.0)) / SimClock.TICK_DT)


func set_level(name: String) -> void:
	level_name = name if LEVELS.has(name) else "입문"
	level = LEVELS[level_name]
	if ems:
		ems.auto_transport = level_name == "입문"


## 외부 방수(경계)를 하고 있는가
func exterior_of(crew_id: int) -> bool:
	return _exterior.has(crew_id)


func task_of_crew(crew_id: int) -> Task:
	for t in tasks:
		if t.crew_id == crew_id:
			return t
	return null


func cancel(crew_id: int) -> void:
	tasks = tasks.filter(func(t: Task) -> bool: return t.crew_id != crew_id)
	_exterior.erase(crew_id)
	holding.erase(crew_id)


## 고수준 명령 시작
func order(action: String, crew_id: int, target: Vector3i, tick: int, via := Vector3i(-1, -1, -1)) -> bool:
	var ok := _order(action, crew_id, target, tick)
	# 진입구를 골라 지시했으면 그 문으로 들어간다 (밖에 있는 조만, P4-2)
	var c := units.get_crew(crew_id)
	if ok and via.x >= 0 and c and not _indoor(c.leader.level, c.leader.pos):
		var t := task_of_crew(crew_id)
		if t:
			t.via = via
			units.order_move([crew_id] as Array[int], via, safety.pathfinder)
			var e := entries.nearest(Vector2(via.x, via.y), via.z, 2.5) if entries else null
			if e:
				events.add(tick, "entry_route", {"crew": _crew_name(c), "crew_id": crew_id, "entry": e.name, "side": entries.side(e),
					"target_level": target.z, "action": ACTIONS.get(action, action)})
	return ok


func _order(action: String, crew_id: int, target: Vector3i, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	if c == null or not ACTIONS.has(action):
		return false
	doors_sys.cancel(crew_id)
	rescue.cancel(crew_id)
	# 공기호흡기 교체 철수면 교체 뒤 이어 할 임무 (2026-11-24): 지금 하던 진압·층 진압·외부 방수
	var resume := {}
	var prev := task_of_crew(crew_id)
	if prev != null and prev.action in ["attack", "attack_floor"]:
		resume = {"action": prev.action, "target": prev.target}
	elif _exterior.has(crew_id):
		resume = {"action": "exterior", "target": _exterior[crew_id]}
	cancel(crew_id)
	# 새 임무를 받으면 관창부터 잠근다 (방수 임무는 방수 위치에 닿아 다시 연다). 2026-11-24 — 전에는 외부 방수를 하던 조에게
	# 진압·검색을 시켜도 잠그지 않아, 걸어가고 문을 여는 동안에도 예전 목표로 물이 나갔다 (물 낭비 + 물줄기가 엉뚱한 쪽으로 그려짐)
	water.stop_spray(crew_id, tick)
	# 호스가 필요 없는 임무를 받았으면 꺼내러 가던 호스는 거둔다 (2026-11-24 — 전에는 그대로 펌프차로 끌려갔다)
	if not action in ["attack", "attack_floor", "exterior"]:
		water.cancel_fetch(crew_id, tick)
		# 놓고 간 관창은 주인을 푼다 — 다른 조가 이어받고, 이 조는 구조·새 호스 등을 받을 수 있다 (철수는 아래에서 따로)
		if action != "withdraw":
			water.release_dropped(crew_id)
	# 새 지시를 받았으면 '교체 뒤 관창으로 돌아가기'는 잊는다 (2026-11-24 검사: 대기 지시 뒤에도 스스로 다시 들어갔다)
	# 막힌 철수를 다시 잇는 것도 잊는다 (2026-11-25)
	if action != "withdraw" and safety:
		safety.forget_return(crew_id)
	if action == "withdraw":
		water.stop_spray(crew_id, tick)
		safety.withdraw_crew(c, tick, "withdraw", resume)
		return true
	if action == "hold":
		water.stop_spray(crew_id, tick)
		holding[crew_id] = true
		units.order_move([crew_id] as Array[int], Vector3i(floori(c.leader.pos.x), floori(c.leader.pos.y), c.leader.level), safety.pathfinder)
		events.add(tick, "crew_hold", {"crew": _crew_name(c)})
		return true
	if action == "exterior":
		events.add(tick, "tactical_start", {"crew": _crew_name(c), "action": ACTIONS[action]})
		# 찍은 곳 가까이에 바깥으로 난 창·문이 있으면 그것을 겨눈다. 창·외벽이거나 다른 층이면 바깥 지상에서 올려 쏘는 경계 관창
		var tgt := water.exterior_target(target)
		var kind := fire.building.cell(tgt.z, tgt.x, tgt.y)
		var ext := tgt.z != c.leader.level or kind == BuildingData.Cell.WALL or kind == BuildingData.Cell.WINDOW
		# 지금 불꽃·가열이 없으면 관창을 배치만 한다 (잠근 채 겨눔) — 불이 다가오면 연다 (_step_exterior)
		var why := _exterior_threat(tgt, ext, _exterior_open_ratio)
		# 외부 방수 임무는 놓인 관창(건물 안)을 쓰지 않는다 — 자기 조가 놓고 간 관창은 주인을 풀고 새 호스를 꺼낸다 (2026-11-24 검사)
		water.release_dropped(crew_id)
		if not water.start_spray(crew_id, tgt, HoseLine.Pattern.STRAIGHT, tick, ext, why == "", false):
			return false
		_exterior[crew_id] = tgt
		_ext_calm[crew_id] = tick
		_ext_told[crew_id] = {"open": why != ""}
		if why == "":
			events.add(tick, "exterior_post", {"crew": _crew_name(c), "text": "경계 관창 배치 (%s) — 불이 다가오면 방수" % _exterior_place(tgt)})
		return true
	if action in ["attack", "attack_floor"] and not _attack_since.has(crew_id):
		_attack_since[crew_id] = tick
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
		# 화재진압은 호스부터 (2026-11-24 사용자·현직 소방관): 수관이 없으면 문·진입구로 가기 전에 자기 펌프차 후면에서 호스를 꺼낸다.
		# 꺼내는 동안은 기다리고, 다 꺼내면 깔면서 간다 (문 목록은 그 자리에서 다시 정한다).
		# 목표 층의 옥내 방수구를 쓸 수 있으면 그 층에서 결합하므로 기다리지 않는다. 연장을 시작할 수 없으면 예전처럼 간다 (방수 위치에서 알린다)
		if t.action == "attack" and t.phase == Phase.DOORS and not water.uses_outlet(t.target.z):
			if not t.hose_asked and water.held_hose(t.crew_id) == null:
				t.hose_asked = true
				water.ensure_hose(t.crew_id, t.target.z, tick)
			if water.fetching(t.crew_id):
				t.hose_wait = true
				continue
			if t.hose_wait:
				t.hose_wait = false
				if t.room >= 0 and t.via.x < 0:
					t.doors = _closed_doors_to(c, fire.comps[t.room])
		if t.via.x >= 0:
			# 고른 진입구 바깥 칸까지 먼저 간다
			if c.leader.level == t.via.z and c.leader.pos.distance_to(Vector2(t.via.x, t.via.y) + Vector2(0.5, 0.5)) <= 1.5:
				t.via = Vector3i(-1, -1, -1)
				if t.room >= 0:
					t.doors = _closed_doors_to(c, fire.comps[t.room])
			elif not c.leader.is_moving():
				units.order_move([t.crew_id] as Array[int], t.via, safety.pathfinder)
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
			_divert_to_victim(t, c, tick)
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
	_step_exterior(tick)
	_step_heat_waits(tick)
	if tick % 10 == 0:
		_check_fire_lost(tick)


## 외부 방수: 물줄기가 닿는 곳에 있던 불꽃이 사라진 채 잠시 지나면 방수를 멈추고 완료 보고 → 카드가 다음 지시를 묻는다.
## 밖에서는 닿는 곳만 안다 — 방 안쪽에 불이 남아 있을 수 있어 '화점 진압'이 아니라 '닿는 곳의 불꽃 소멸'로 보고한다.
## 다른 명령·철수로 방수가 끝났거나 목표가 바뀌었으면 지켜보지 않는다. 자동화 수준 상급(auto_stop 꺼짐)은 화점진압처럼 스스로 멈추지 않는다
##
## 경계 관창 (2026-11-24): 불꽃을 본 적 없는 방수는 '식히는 중'이다 — 가열·불꽃이 exterior_done_s 동안 없으면 관창을 잠그고
## 그 자리에서 계속 지킨다. 잠가 둔(배치만 한) 관창은 겨눈 곳이 달궈지거나 불꽃이 나오면 스스로 연다 (어느 자동화 수준에서나).
## 개방·잠금은 처음 한 번씩만 무전으로 알린다 (되풀이는 기록만)
func _step_exterior(tick: int) -> void:
	for id: int in _exterior.keys():
		var c := units.get_crew(id)
		var h := water.hose_of_crew(id)
		if c == null or c.leader.incapacitated or h == null or not (h.flowing or h.standby) or h.target != (_exterior[id] as Vector3i):
			_exterior.erase(id)
			_ext_calm.erase(id)
			_ext_told.erase(id)
			continue
		# 가열·불꽃은 1초마다 본다
		if tick % 10 == id % 10:
			var why := _exterior_threat(h.target, h.exterior, _exterior_close_ratio if h.flowing else _exterior_open_ratio)
			if why != "":
				_ext_calm[id] = tick
				if h.standby and not c.leader.is_moving() and not water.fetching(id):
					# 불이 다가왔다: 관창을 연다
					if water.start_spray(id, h.target, HoseLine.Pattern.STRAIGHT, tick, h.exterior, false):
						_tell_exterior(id, c, tick, "open", "경계 관창 개방 (%s) — %s" % [_exterior_place(h.target), why])
		if not h.flowing or not level.auto_stop:
			continue
		if h.flame_tick >= 0:
			# 불꽃에 쏘던 방수: 닿는 곳의 불꽃이 사라진 채 잠시 지나면 임무 완료
			if tick - h.flame_tick < _exterior_done_ticks or tick - int(_ext_calm.get(id, tick)) < _exterior_done_ticks:
				continue
			_exterior.erase(id)
			_ext_calm.erase(id)
			_ext_told.erase(id)
			water.stop_spray(id, tick)
			var e := {"crew": _crew_name(c), "text": "%s 외부 방수 — 닿는 곳의 불꽃 소멸, 방수 중지" % fire.building.floor_name(h.target.z)}
			e.merge(_final(c, "exterior", h.target.z))
			events.add(tick, "tactical_done", e)
		elif tick - int(_ext_calm.get(id, tick)) >= _exterior_done_ticks:
			# 식히던 방수: 식었다 — 관창을 잠그고 그 자리에서 계속 지킨다
			water.hold_nozzle(id, tick)
			_tell_exterior(id, c, tick, "hold", "경계 관창 잠금 (%s) — 가열 없음, 계속 감시" % _exterior_place(h.target))


## 경계 관창이 겨눈 곳의 위협: "" 없음 · "화염" · "가열". ratio = 가열로 보는 달궈진 정도 (열 때와 잠글 때가 다르다 — 떨림 방지)
func _exterior_threat(target: Vector3i, ext: bool, ratio: float) -> String:
	if not ext:
		# 방 안을 겨눈 외부 방수: 그 방에 타는 곳이 있으면 (물줄기가 훑는다)
		var room := fire.compartment_at(target.z, target.x, target.y)
		if room != null and _room_burning(room.index):
			return "화염"
	if water.flames_at(target, ext):
		return "화염"
	if exposure_heat.is_valid() and float(exposure_heat.call(target)) > ratio:
		return "가열"
	return ""


## 경계 관창이 겨눈 곳 이름 (보고용)
func _exterior_place(target: Vector3i) -> String:
	var o := fire.opening_at(target)
	if o != null and o.room_a >= 0 and o.room_a < fire.comps.size():
		return "%s %s" % [fire.comps[o.room_a].display_name(), "창" if o.kind == Opening.Kind.WINDOW else "문"]
	var room := fire.compartment_at(target.z, target.x, target.y)
	return room.display_name() if room != null else "%s 외벽" % fire.building.floor_name(target.z)


## 경계 관창의 개방·잠금 보고: 종류마다 처음 한 번은 무전(exterior_post), 그 뒤로는 기록만 (exterior_cycle)
func _tell_exterior(id: int, c: Crew, tick: int, key: String, text: String) -> void:
	var told: Dictionary = _ext_told.get(id, {})
	events.add(tick, "exterior_cycle" if bool(told.get(key, false)) else "exterior_post", {"crew": _crew_name(c), "text": text})
	told[key] = true
	_ext_told[id] = told


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
		_halt(t, c, tick, "%s 닫힘 — 문 개방 지시 바람" % _door_name(o), false, "closed", _door_ctx(o))
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
				var e := {"crew": _crew_name(c), "text": "%s 화염 진압, 방수 중지" % fire.comps[t.room].display_name()}
				# 방 하나 임무면 여기서 임무가 끝난다 (층 임무는 다음 방으로) — 카드가 다음 지시를 묻는다
				if t.floor < 0:
					e.merge(_final(c, "attack", fire.comps[t.room].level))
				events.add(tick, "tactical_done", e)
		"search":
			if rescue.task_of_crew(t.crew_id) is RescueSystem.SearchTask:
				return
			t.phase = Phase.DONE
			var v := _victim_in_room(t.room)
			if v == null:
				# 방 하나 검색: 아무도 없으면 그렇게 보고하고 끝 (예전에는 말없이 끝났다, 2026-11-17)
				if t.floor < 0 and t.unit_check.is_empty():
					var e := {"crew": _crew_name(c), "text": "%s 검색 완료 — 이상 없음" % fire.comps[t.room].display_name()}
					e.merge(_final(c, "search", fire.comps[t.room].level))
					events.add(tick, "tactical_done", e)
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


## 검색하러 가던(검색하던) 조가 요구조자를 직접 보았다 (2026-11-26 사용자: 복도로 들어온 구조대가 화점실인 거실로만 가느라
## 지나친 방1의 아이를 구하지 않았다): 인명구조가 먼저 — 하던 검색을 멈추고 바로 이송한다. 층 임무는 인계 뒤 이어 간다.
## 본 것 = 조원이 직접 본 칸(육안)이거나 소리가 들리는 거리. 다른 조가 이미 업으러 가는 사람은 두고 간다
func _divert_to_victim(t: Task, c: Crew, tick: int) -> void:
	if not level.auto_rescue or tick % 5 != 0 or rescue.task_of_crew(t.crew_id) is RescueSystem.CarryTask:
		return
	var taken := {}
	for ct in rescue.carries:
		if ct.kind == "victim":
			taken[ct.target_id] = true
	for v in rescue.victims:
		if not v.discovered or not v.alive() or v.carried_by >= 0 or taken.has(v.id) or v.level != c.leader.level:
			continue
		var seen := perception == null or perception.is_crew_visible(v.level, floori(v.pos.x), floori(v.pos.y))
		if not seen and c.leader.pos.distance_to(v.pos) > _victim_hear_cells:
			continue
		if not rescue.order_rescue(t.crew_id, "victim", v.id, tick):
			continue
		t.phase = Phase.DONE
		var room := fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
		events.add(tick, "tactical_done", {"crew": _crew_name(c), "text": "%s 발견 (%s) — 이송 시작" % [v.label(), room.display_name() if room else "내부"]})
		return


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


## 화염·열기로 더 들어가지 못해 하던 인명검색·구조를 멈췄다 (2026-11-24, SimWorld._on_heat_stop): 임무를 '지시 바람'으로 멈추고
## 무전으로 알린다. 스스로 다시 들어가지 않는다 — 다시 보낼지는 지휘관이 정한다 (층 임무도 이어 가지 않는다).
## place = 들어가지 못한 곳 이름
## at = 막힌 곳 (CrewConditionSystem.heat_stop_at, 모르면 x < 0)
func halt_for_heat(crew_id: int, tick: int, place: String, at := Vector3i(-1, -1, -1)) -> void:
	var c := units.get_crew(crew_id)
	if c == null:
		return
	var reason := "화염·열기로 %s 진입 불가 — 물러나 대기, 지시 바람" % place
	var t := task_of_crew(crew_id)
	# 층 검색 (2026-11-26): 지시를 기다리지 않고 그 방을 건너뛴다 — 물러난 뒤 문을 닫고 다음 방으로 (_step_heat_waits)
	if t != null and t.action == "search" and t.floor >= 0 and t.floor_action == "search_floor" and t.room >= 0:
		# 막힌 곳이 검색할 그 방이 아니라 가는 길의 다른 방이면: 그 너머 방들도 갈 수 없다 — 건너뛰지 않고 한 번 알리고 지시를 기다린다
		var through := _room_through(at, t.room, c)
		if through != null and through.index != t.room:
			_halt(t, c, tick, "화염·열기로 %s을(를) 지나갈 수 없어 %s 검색 중단 — 다른 진입구 또는 엄호 방수 필요, 지시 바람" % [
				through.display_name(), fire.building.floor_name(t.floor)], true, "heat")
			return
		_skip_for_heat(t, c, tick, at)
		return
	if t != null:
		_halt(t, c, tick, reason, true, "heat")
	else:
		events.add(tick, "tactical_halt", {"crew": _crew_name(c), "reason": reason, "safety": true, "kind": "heat", "crew_id": c.id})


## 열기에 막힌 곳(at)이 속한 방. 문 칸이면: 검색할 방(target)과 이어진 문이면 그 방, 아니면 조가 선 쪽 반대편 방 (밖이면 null)
func _room_through(at: Vector3i, target: int, c: Crew) -> Compartment:
	if at.x < 0:
		return null
	var room := fire.compartment_at(at.z, at.x, at.y)
	if room != null:
		return room
	var o := fire.opening_at(at)
	if o == null:
		return null
	if o.room_a == target or o.room_b == target:
		return fire.comps[target]
	var here := fire.compartment_at(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y))
	for r in [o.room_a, o.room_b]:
		if r != Opening.OUTSIDE and (here == null or r != here.index):
			return fire.comps[r]
	return null


## 층 검색이 화염·열기로 들어가지 못한 방을 건너뛴다: 그 방을 기억하고(heat_skipped), 무전으로 알리고,
## 물러난 뒤(CrewConditionSystem 이 식은 곳으로 데려간다) 그 방의 열린 문을 닫고 다음 방을 검색한다
func _skip_for_heat(t: Task, c: Crew, tick: int, at := Vector3i(-1, -1, -1)) -> void:
	t.phase = Phase.DONE
	t.halted = true
	heat_skipped[t.room] = tick
	var room := fire.comps[t.room]
	# 닫을 문: 막힌 바로 그 문(조가 선 쪽에서 화점실로 들어가는 문)이 먼저 — 없으면 그 방의 다른 열린 문
	var door := fire.opening_at(at) if at.x >= 0 else null
	if door == null or door.kind != Opening.Kind.DOOR or not door.is_open or door.forced or not (door.room_a == t.room or door.room_b == t.room):
		door = _open_door_of(room, c.leader.pos)
	_heat_waits[c.id] = {"floor": t.floor, "action": t.floor_action, "room": t.room, "door": door.index if door != null else -1, "closing": false}
	events.add(tick, "search_skipped", {"crew": _crew_name(c), "crew_id": c.id, "room": room.display_name(),
		"text": "%s 화염·열기로 진입 불가 — %s다음 실 검색" % [room.display_name(), "문 닫고 " if door != null else ""]})


## 닫을 문: 그 방의 열린 문 가운데 집 안쪽(다른 실)으로 이어진 문을 먼저 — 불이 나머지 실로 번지는 것을 막는 문이다.
## 바깥으로 난 문(현관)은 안쪽 문이 없을 때만. 같으면 from 에서 가까운 것. 부순 문은 닫을 수 없어 뺀다. 없으면 null
func _open_door_of(room: Compartment, from: Vector2) -> Opening:
	var best: Opening = null
	var best_key := Vector2(INF, INF)
	for oi in room.openings:
		var o: Opening = fire.openings[oi]
		if o.kind != Opening.Kind.DOOR or not o.is_open or o.forced or o.level != room.level:
			continue
		var outside := o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE
		var key := Vector2(1.0 if outside else 0.0, _center(o).distance_to(from))
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best_key = key
			best = o
	return best


## 건너뛴 조: 물러나기를 마치면(멈추면) 문을 닫는다 — 문 앞이 위험 수준이면 닫지 못했다고 알린다. 그 뒤 다음 방
func _step_heat_waits(tick: int) -> void:
	for id: int in _heat_waits.keys():
		var c := units.get_crew(id)
		if c == null or c.leader.incapacitated:
			_heat_waits.erase(id)
			continue
		# 다른 임무를 받았으면 잊는다
		if task_of_crew(id) != null:
			_heat_waits.erase(id)
			continue
		if c.leader.is_moving():
			continue
		var w: Dictionary = _heat_waits[id]
		if bool(w.closing):
			if doors_sys.task_of_crew(id) != null:
				# 문까지 가는 길이 열기로 막혀 문 작업이 끝나지 않는다: 잠시 기다린 뒤 거두고 닫지 못했다고 알린다
				if tick - int(w.since) < _door_close_wait_ticks:
					continue
				doors_sys.cancel(id)
				events.add(tick, "door_left_open", {"crew": _crew_name(c), "crew_id": id, "room": _door_name(fire.openings[int(w.door)])})
		else:
			var di := int(w.door)
			if di >= 0 and fire.openings[di].is_open:
				var o: Opening = fire.openings[di]
				var cell: Vector2i = o.cells[0]
				if not heat_ok.is_valid() or bool(heat_ok.call(o.level, cell)):
					if doors_sys.request(id, Vector3i(cell.x, cell.y, o.level), false, tick):
						w.closing = true
						w.since = tick
						continue
				events.add(tick, "door_left_open", {"crew": _crew_name(c), "crew_id": id, "room": _door_name(o)})
		_heat_waits.erase(id)
		_order_floor(str(w.action), c, int(w.floor), tick, false)


## 층 검색이 지금 건너뛰는 방인가: 화염·열기로 못 들어간 뒤 search_heat_skip_s 안이고 그 뒤 초진 전
func heat_skipping(room_index: int, tick: int) -> bool:
	if not heat_skipped.has(room_index):
		return false
	var at: int = heat_skipped[room_index]
	var k := knockdown_tick.call() as int if knockdown_tick.is_valid() else -1
	if k >= at:
		return false
	return tick - at < _heat_skip_ticks


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
	return units.crew_name(c)


# --- 층 단위 임무 (R7) ---

## 층 임무의 다음 방을 맡긴다. first: 처음 받은 명령 (아니면 방 하나를 마친 뒤)
func _order_floor(action: String, c: Crew, lv: int, tick: int, first: bool) -> bool:
	var floor_name := fire.building.floor_name(lv)
	if first and action == "search_floor":
		_search_since[c.id] = tick
	var room := _next_floor_room(c, action, lv, tick)
	if room == null:
		if action == "attack_floor" and first:
			events.add(tick, "tactical_halt", {"crew": _crew_name(c), "reason": "%s 화점을 찾지 못함 — 지시 바람" % floor_name,
				"safety": false, "kind": "no_fire", "crew_id": c.id, "action": action, "target": [0, 0, lv]})
		else:
			var e := {"crew": _crew_name(c), "text": "%s %s 완료" % [floor_name, "검색" if action == "search_floor" else "화점 진압"]}
			if action == "search_floor":
				var left: PackedStringArray = []
				for idx: int in heat_skipped:
					if fire.comps[idx].level == lv and heat_skipping(idx, tick):
						left.append(fire.comps[idx].display_name())
				if not left.is_empty():
					e.text += " — %s 화염으로 미검색" % ", ".join(left)
			e.merge(_final(c, "search" if action == "search_floor" else "attack", lv))
			events.add(tick, "tactical_done", e)
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
			"text": "%s 확인 — %s도 같은 구조로 추정" % [check.below, check.above], "crew_id": c.id, "final": true})
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


## 층 검색: 아직 검색하지 않은 방을 교재 순서로 (_search_rank), 같은 순위면 조에게서 가까운 곳부터.
## 층 진압: 타는 방 — 가까운 곳부터
func _next_floor_room(c: Crew, action: String, lv: int, tick := 0) -> Compartment:
	var search := action == "search_floor"
	var fire_rooms := _fire_rooms(lv) if search else {}
	var best: Compartment = null
	var best_d := INF
	# 층 임무는 그 조가 있는 건물 안에서만 — 화재 건물의 층 검색이 옆집으로 넘어가지 않게 (2026-11-17)
	var here := fire.compartment_at(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y))
	var in_exposure := fire.is_exposure_comp(here)
	for room in fire.comps:
		if room.level != lv or room.cells.is_empty() or fire.is_exposure_comp(room) != in_exposure:
			continue
		if search and room_searched(room, _search_since.get(c.id, -1)):
			continue
		if search and heat_skipping(room.index, tick):
			continue
		if action == "attack_floor" and not _room_burning(room.index):
			continue
		var d := c.leader.pos.distance_to(Vector2(room.rect.get_center())) + absi(lv - c.leader.level) * 8.0
		if search:
			d += _search_rank(room, fire_rooms) * SEARCH_RANK_GAP
		if d < best_d:
			best_d = d
			best = room
	return best


## 검색을 마친 방인가. 초진 뒤에 받은 검색(ordered_tick ≥ 초진)은 2차 검색이라 초진 전에 한 검색은 치지 않는다
## (소방전술 I 8단계 ⑤, SOP 202-6.3 — 예전에는 초진 전에 검색한 층을 다시 보내면 바로 '검색 완료'로 끝났다, 2026-11-17)
func room_searched(room: Compartment, ordered_tick: int) -> bool:
	var k := knockdown_tick.call() as int if knockdown_tick.is_valid() else -1
	if k >= 0 and ordered_tick >= k:
		return room.searched_tick >= k
	return room.searched_tick >= 0


## 임무가 끝났다는 표시 (완료 보고 사건에 붙인다 — CardSystem이 잠시 뒤 할 일 없이 서 있으면 다음 지시를 묻는다).
## mission·level: 무엇을 어느 층에서 마쳤나 — 화점 진압 완료를 보고한 층은 지휘관이 '불이 꺼졌다'고 안다 (SimWorld.next_task)
func _final(c: Crew, mission: String, lv: int) -> Dictionary:
	return {"crew_id": c.id, "final": true, "mission": mission, "level": lv}


## 층 안 검색 순서 (SOP 202-3.1.2 화점실 → 인근실 → 연소층): 0 구조대상자가 있다고 들은 방(관계인 진술) →
## 1 화점실(타고 있거나 탄 자리가 있는 방) → 2 인근실(화점실과 문으로 이어진 방) → 3 그 층 나머지.
## 어느 층부터 보낼지(화점층·직상층…)는 지휘관이 지시 창에서 정한다
func _search_rank(room: Compartment, fire_rooms: Dictionary) -> int:
	if reported_rooms.has(str(room.id)):
		return 0
	if fire_rooms.has(room.index):
		return 1
	for oi in room.openings:
		var o := fire.openings[oi]
		if o.kind == Opening.Kind.DOOR and (fire_rooms.has(o.room_a) or fire_rooms.has(o.room_b)):
			return 2
	return 3


## 그 층의 화점실: 타고 있거나 탄 자리(다 탔거나 타다 꺼져 연료가 준 칸)가 있는 방 {구획 index: true}
func _fire_rooms(lv: int) -> Dictionary:
	var out := {}
	var grid := fire.grid
	for room in fire.comps:
		if room.level != lv or room.index >= grid.room_cells.size():
			continue
		# 가구 칸까지 본다 (FuelGrid.room_cells)
		for i in grid.room_cells[room.index]:
			if RekindleSystem.scorched_cell(grid, i):
				out[room.index] = true
				break
	return out


## 방 가운데에 가까운 칸
func _room_cell(room: Compartment) -> Vector3i:
	var center := Vector2(room.rect.get_center())
	var best: Vector2i = room.cells[0]
	for cell in room.cells:
		if Vector2(cell).distance_to(center) < Vector2(best).distance_to(center):
			best = cell
	return Vector3i(best.x, best.y, room.level)


## 검색 중인 조가 가까이에서 타는 칸을 보면 화점 발견 보고 (방마다 한 번). 질문 카드 FIRE-FOUND-01
## 화점진압 조가 오래 화점에 물을 대지 못하고 앞이 안 보이면 보고한다 (기획안 7-3 '화점 15분 못 찾음·시계 0', SOP 102-4.1)
func _check_fire_lost(tick: int) -> void:
	for crew_id: int in _attack_since.keys():
		var t := task_of_crew(crew_id)
		var c := units.get_crew(crew_id)
		# 임무가 없어졌거나(다른 임무·철수) 쓰러졌으면 잊는다
		if t == null or c == null or c.leader.incapacitated or not t.action in ["attack", "attack_floor"]:
			_attack_since.erase(crew_id)
			continue
		var h := water.hose_of_crew(crew_id)
		if h and h.flowing and not h.approaching and h.charged and not h.blocked and h.flow_fraction > 0.0:
			_attack_since.erase(crew_id)
			continue
		var since: int = _attack_since[crew_id]
		if tick - since < _fire_lost_ticks or not _indoor(c.leader.level, c.leader.pos):
			continue
		var room := fire.compartment_at(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y))
		if room == null or fire.visibility_m(room) >= _fire_lost_vis_m:
			continue
		_attack_since.erase(crew_id)
		var air := PackedStringArray()
		for ff in c.members():
			air.append("%d%%" % roundi(ff.air_ratio() * 100.0))
		events.add(tick, "fire_not_found", {"crew": _crew_name(c), "crew_id": crew_id, "room": room.display_name(),
			"minutes": roundi(float(tick - since) * SimClock.TICK_DT / 60.0), "air": " · ".join(air)})


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
			"room_cell": [p.x, p.y, lv], "has_hose": water.held_hose(c.id) != null,
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


func _indoor(level: int, p: Vector2) -> bool:
	return not fire.building.cell(level, floori(p.x), floori(p.y)) in BuildingData.OUTDOOR


## 팀 카드·상황 보고용 임무 이름: "층 검색 (2층 방1)" / "진압 (1층 거실)" / ""
func mission_text(crew_id: int) -> String:
	var t := task_of_crew(crew_id)
	if t == null:
		return ""
	var room := fire.comps[t.room].display_name() if t.room >= 0 else ""
	return "%s%s" % [ACTIONS.get(t.floor_action if t.floor >= 0 else t.action, t.action), " (%s)" % room if room != "" else ""]
