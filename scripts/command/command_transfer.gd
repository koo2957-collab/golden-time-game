class_name CommandTransfer
extends RefCounted
## 지휘권 이양 (SOP 112, 기획안 4장 2-2·R13): 지휘대가 도착하면 선착대장이 브리핑하고 지휘권을 넘긴다.
## 이양 뒤 플레이어는 지휘대장으로 계속 지휘한다 (2026-11-08 결정: 이양 = 역할 전환, 종료 아님).
##   - 브리핑 항목 6개(화재·인명·전략·투입 자원·안전·필요 자원)마다 보기 중 지금 아는 사실과 맞는 것을 고른다
##   - 이양하면 상황실에서 도면이 들어오고(SOP 112, R8 연결), 단위대(O)로 묶은 출동대의 질문 카드는
##     그 단위지휘관이 대신 처리한다 (기획안 3-3 "단위지휘관 지정으로 질문 수를 줄이는 것 자체가 지휘 실력")
## 시나리오: command_unit {time_s, name, chief: {name, rank, title}}

const ITEMS := ["fire", "victims", "strategy", "resources", "safety", "needs"]
const ITEM_NAMES := {"fire": "화재 상황", "victims": "인명 상황", "strategy": "전략·전술", "resources": "투입 자원", "safety": "안전 위험요인", "needs": "필요 자원"}

var sim: SimWorld
var events: SimEventLog
## 시나리오 설정 (비어 있으면 지휘대가 오지 않는다)
var unit: Dictionary = {}
var arrive_tick := -1
var arrived_tick := -1
var transferred_tick := -1
## 브리핑 정확도 (0~1)와 항목별 결과 [{item, answer, correct}]
var accuracy := 0.0
var briefing: Array[Dictionary] = []


func _init(p_sim: SimWorld) -> void:
	sim = p_sim
	events = p_sim.events


func apply_scenario(data: Dictionary) -> void:
	unit = data.get("command_unit", {})
	if not unit.is_empty():
		arrive_tick = roundi(float(unit.get("time_s", 600)) / SimClock.TICK_DT)


func arrived() -> bool:
	return arrived_tick >= 0


func transferred() -> bool:
	return transferred_tick >= 0


func step(tick: int) -> void:
	if arrive_tick >= 0 and arrived_tick < 0 and tick >= arrive_tick:
		arrived_tick = tick
		events.add(tick, "command_unit_arrived", {"crew": str(unit.get("name", "지휘대")), "unit": str(unit.get("name", "지휘대"))})


## 브리핑 보기: 항목마다 [보기…], 첫 번째가 지금 아는 사실 (화면에서는 섞는다 — 시드)
func options() -> Dictionary:
	var cmd := sim.command
	var out := {}
	# 화재: 대원이 본 타는 층
	var floors: PackedStringArray = []
	for lv in sim.building.levels():
		for c in sim.fire.comps:
			if c.level == lv and sim.perception.room_seen[c.index] != 0 and _room_seen_burning(c):
				floors.append(sim.building.floor_name(lv))
				break
	var fire_truth := ("화점 %s, 확인한 연소 범위 %s" % [floors[0], "·".join(floors)]) if not floors.is_empty() else "화점 확인 중 (연기만 확인)"
	out["fire"] = [fire_truth, "화점 확인 중 (연기만 확인)" if not floors.is_empty() else "화점 1층, 연소 확대 없음", "초진 완료"]
	# 인명: 구조·처치·남은 제보
	var rescued := sim.events.of_type("victim_rescued").size()
	var reported := cmd.survey.reported_rooms.size()
	var searched := 0
	for c in sim.fire.comps:
		if c.searched_tick >= 0:
			searched += 1
	out["victims"] = ["구조 %d명, 제보 위치 %d곳 · 검색 완료 구획 %d" % [rescued, reported, searched], "요구조자 없음 (전원 대피)", "구조 %d명, 추가 요구조자 없음 확인" % (rescued + 1)]
	var strat := CommandSystem.STRATEGY_NAMES[cmd.strategy]
	out["strategy"] = ["%s 전략" % strat, "%s 전략" % ("방어" if strat != "방어" else "공격"), "전략 미선언"]
	var on_scene := 0
	var inside := 0
	for s in sim.units.squads:
		if not cmd.resources.is_en_route(s.id):
			on_scene += 1
	for c in sim.units.crews:
		if cmd.interior.crew_inside(c.id):
			inside += 1
	out["resources"] = ["현장 출동대 %d개, 내부 진입 %d개 조" % [on_scene, inside], "현장 출동대 %d개, 내부 진입 없음" % on_scene, "현장 출동대 %d개, 내부 진입 %d개 조" % [on_scene + 2, inside + 2]]
	var dangers: PackedStringArray = []
	if cmd.safety.emergency():
		dangers.append("긴급탈출 상황")
	for t in ["rollover_sign", "backdraft_sign", "collapse_sign", "fgi_warning", "debris_zone"]:
		if not sim.events.of_type(t).is_empty():
			dangers.append(SimEventLog.describe_text(sim.events.of_type(t)[-1]).split(" — ")[0])
	var safety_truth := ", ".join(dangers) if not dangers.is_empty() else "확인된 특수현상 징후 없음"
	out["safety"] = [safety_truth, "확인된 특수현상 징후 없음" if not dangers.is_empty() else "백드래프트 징후 있음", "대원 안전 문제 없음 (인원점검 생략)"]
	var held := cmd.resources.upcoming(sim.clock.tick).size()
	out["needs"] = ["추가 요청 출동대 %d개 도착 예정, 교대조·급수 확보 필요" % held, "추가 자원 필요 없음", "대응 2단계 필요"]
	return out


func _room_seen_burning(c: Compartment) -> bool:
	var p := sim.perception
	for cell in c.cells:
		var i := sim.fire.grid.index(c.level, cell.x, cell.y)
		if p.is_seen(c.level, cell.x, cell.y) and p.seen_burning[i] == 1:
			return true
	return false


## 이양 (CommandOrder "transfer"): answers {item: 고른 보기 문장}. 지금 아는 사실과 맞는 항목 비율을 기록
func transfer(answers: Dictionary, tick: int) -> bool:
	if not arrived() or transferred():
		return false
	var truth := options()
	briefing.clear()
	var right := 0
	for k in ITEMS:
		var a := str(answers.get(k, ""))
		var ok: bool = a == str(truth[k][0])
		if ok:
			right += 1
		briefing.append({"item": ITEM_NAMES[k], "answer": a, "truth": str(truth[k][0]), "correct": ok})
	accuracy = float(right) / ITEMS.size()
	transferred_tick = tick
	var chief: Dictionary = unit.get("chief", {})
	sim.command.commander_title = str(chief.get("title", "지휘대장"))
	if chief.has("name"):
		sim.command.commander.name = str(chief.name)
		sim.command.commander.rank = str(chief.get("rank", ""))
	events.add(tick, "command_transferred", {"crew": sim.command.commander_title, "accuracy": roundi(accuracy * 100.0),
		"delay_s": roundi((tick - arrived_tick) * SimClock.TICK_DT)})
	# 이양받은 현장지휘관은 고정지휘 (SOP 101-3, 기획안 9-1-1): 지금 자리를 지휘소로
	if sim.command.post:
		sim.command.post.set_post(Vector2i(sim.command.commander.pos.floor()), tick, "지휘권 이양")
	# 지휘대 도착과 함께 상황실 도면 수신 (SOP 112, R8)
	sim.plan.acquire("상황실 (지휘대 도착)", tick)
	return true


## 단위지휘관 대리 처리: 이양 뒤, 단위대에 묶인 출동대의 질문 카드는 그 단위지휘관이 처리한다
func delegates(crew_id: int) -> String:
	if not transferred():
		return ""
	var c := sim.units.get_crew(crew_id)
	if c == null:
		return ""
	var d := sim.command.org.division_of(c.squad_id)
	if d == null:
		return ""
	return "%s(%s)" % [d.name, sim.units.squads[d.supervisor].name] if d.supervisor >= 0 else d.name
