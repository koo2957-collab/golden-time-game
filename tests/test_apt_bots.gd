extends TestSuite
## P9: 아파트 스테이지(2-1) 시나리오 3개를 자동 봇으로 끝까지 돌린다.
##   최선 봇: 질문 카드에 늘 '최선' 선택지를 고른다 / 무응답 봇: 카드에 답하지 않는다
##   두 봇 모두 같은 지휘(공격 전략, 안전구역·환자 집결지, 출동대 3개부터 RIT 지정,
##   발화층 화점진압·발화층·직상층 인명검색)를 한다. 차이는 질문 카드 답뿐이다.
## 확인: 끝까지 진행되는지(오류 없이 제한 시간까지 또는 종료), 최선 봇이 무응답 봇보다 구조 인원이 많은지.
## 시드 변형(발화층 무작위)도 같은 봇으로 한 번 돌린다.

const SCENARIOS := [
	"res://data/scenarios/sop213_3_15f_day_low.json",
	"res://data/scenarios/sop213_4_15f_night_mid.json",
	"res://data/scenarios/sop213_5_15f_winter_high.json",
]
## 봇이 돌리는 현장 시간 (초) — 테스트 설정값 (15층 건물 1초 ≈ 80ms라 10분만. 선착대가 처음부터 현장에 있어 구조에는 충분)
const PLAY_S := 600.0
const ORDER_EVERY_S := 20.0


## 한 판을 돌리고 결과 {rescued, alive_rescued, cards_answered, ended, fire_floor}
func _play(path: String, answer: bool, seed := -1) -> Dictionary:
	var sim := SimWorld.from_scenario(path, true, seed)
	sim.tactical.set_level("입문")
	var fire_lv := sim.fire_floor_reported()
	sim.issue(CommandOrder.make("strategy", [], CommandSystem.Strategy.OFFENSIVE))
	_zones(sim)
	var answered := 0
	var next_order := 0
	var limit := roundi(PLAY_S / SimClock.TICK_DT)
	var step := roundi(1.0 / SimClock.TICK_DT)
	while sim.clock.tick < limit and not sim.ended():
		if sim.clock.tick >= next_order:
			next_order = sim.clock.tick + roundi(ORDER_EVERY_S / SimClock.TICK_DT)
			_orders(sim, fire_lv)
		sim.step_ticks(step)
		if answer:
			for c in sim.cards.queue.duplicate():
				var best := _best(c)
				sim.issue(CommandOrder.make("card_answer", [], best, Vector3i.ZERO, {"uid": c.uid}))
				answered += 1
	var rescued := 0
	var alive := 0
	for v in sim.rescue.victims:
		if v.state == Victim.State.RESCUED and v.rescued_by >= 0:
			rescued += 1
			if v.state_at_rescue != Victim.State.DEAD:
				alive += 1
	return {"rescued": rescued, "alive": alive, "answered": answered, "ended": sim.ended(), "tick": sim.clock.tick,
		"fire_floor": fire_lv, "victims": sim.rescue.victims.size()}


## 건물에서 떨어진 바깥 6×6 안전구역과 그 가운데 환자 집결지 (무전으로 지정)
func _zones(sim: SimWorld) -> void:
	var b := sim.building
	var fp := b.footprint(1)
	for y in range(fp.end.y + 2, b.height - 6):
		for x in range(fp.position.x, b.width - 6):
			var r := Rect2i(x, y, 6, 6)
			if sim.zones.safe_reject_reason(r) == "":
				sim.issue(CommandOrder.make("zone", [], 0, Vector3i.ZERO, {"kind": "safe", "rect": [r.position.x, r.position.y, r.size.x, r.size.y]}))
				return


## 안전구역이 무전으로 정해지면 그 가운데 환자 집결지 (안전구역이 먼저여야 한다)
func _casualty(sim: SimWorld) -> void:
	if sim.zones.has_safe() and sim.zones.casualty.x < 0 and not sim.command.radio.busy():
		var m := sim.zones.safe.get_center()
		sim.issue(CommandOrder.make("zone", [], 0, Vector3i.ZERO, {"kind": "casualty", "cell": [m.x, m.y]}))


## 최선 선택지 (없으면 첫 번째)
func _best(c: CardSystem.Card) -> int:
	for i in c.options.size():
		if str(c.options[i].get("grade", "")) == "최선":
			return i
	return 0


## 현장에 있는 조마다 임무 (할 일이 없는 조만, 진입 허가는 입구에서 카드로): 진압대 첫 조 화점진압, 나머지 발화층·직상층 인명검색
func _orders(sim: SimWorld, fire_lv: int) -> void:
	_casualty(sim)
	# 출동대가 3개 이상이면 마지막에 도착한 조 하나를 RIT로 (SSG 9) — 임무를 주지 않는다
	var on_scene := sim.units.squads.filter(func(s: Squad) -> bool: return sim.command.resources.on_scene(s.id))
	var rit := sim.command.safety.crews_with(SafetySystem.Role.RIT)
	if on_scene.size() >= 3 and rit.is_empty():
		for c in sim.units.crews:
			if sim.command.resources.on_scene(c.squad_id) and not sim.ems.is_ems_crew(c.id) and not c.leader.aboard 					and sim.tactical.task_of_crew(c.id) == null and not _indoor(sim, c):
				sim.issue(CommandOrder.make("role", [c.id], SafetySystem.Role.RIT))
				rit = [c.id]
				break
	var n := 0
	for c in sim.units.crews:
		if not sim.command.resources.on_scene(c.squad_id) or sim.ems.is_ems_crew(c.id) or c.leader.aboard:
			continue
		if sim.tactical.task_of_crew(c.id) != null:
			n += 1
			continue
		if sim.command.safety.role_of(c.id) != SafetySystem.Role.NONE or sim.command.post.busy(c.id):
			continue
		var ids: Array[int] = [c.id]
		if n == 0:
			sim.issue(TacticalCommand.make("attack_floor", ids, Vector3i(0, 0, fire_lv)))
		else:
			var lv := fire_lv if n % 2 == 1 else mini(fire_lv + 1, sim.building.levels().max())
			sim.issue(TacticalCommand.make("search_floor", ids, Vector3i(0, 0, lv)))
		n += 1


func _indoor(sim: SimWorld, c: Crew) -> bool:
	return not sim.building.cell(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y)) in BuildingData.OUTDOOR


func _compare(path: String) -> void:
	var best := _play(path, true)
	var none := _play(path, false)
	var name := path.get_file().get_basename()
	print("    %s 최선 %s / 무응답 %s" % [name, best, none])
	var full := roundi(PLAY_S / SimClock.TICK_DT)
	assert_true(best.ended or best.tick >= full, "%s 최선 봇 끝까지" % name)
	assert_true(none.ended or none.tick >= full, "%s 무응답 봇 끝까지" % name)
	assert_true(best.answered > 0, "%s 카드가 떴다 (%d장 답함)" % [name, best.answered])
	assert_true(best.alive > none.alive, "%s 최선 봇 생존 구조 %d > 무응답 %d" % [name, best.alive, none.alive])


func test_bots_a_day_low() -> void:
	_compare(SCENARIOS[0])


func test_bots_b_night_mid() -> void:
	_compare(SCENARIOS[1])


func test_bots_c_winter_high() -> void:
	_compare(SCENARIOS[2])


func test_fire_floor_varies_by_seed() -> void:
	# 발화층(세대 번호)은 시드로 고른다: 기본은 시나리오 기준층, 시드가 다르면 범위 안에서 바뀐다
	var path: String = SCENARIOS[0]
	var base := SimWorld.from_scenario(path)
	assert_eq(base.fire_floor_reported(), 3, "시드를 따로 주지 않으면 기준층 3층")
	var seen := {}
	for s in [1, 2, 3, 4, 5, 6]:
		var sim := SimWorld.from_scenario(path, true, s)
		var lv := int(sim.scenario.fire.ignitions[0].level)
		seen[lv] = true
		assert_true(lv >= 2 and lv <= 4, "시드 %d 발화층 %d (2~4)" % [s, lv])
		assert_eq(sim.fire_floor_reported(), lv, "신고된 발화층도 같은 층")
		# 직상층 요구조자는 발화층 바로 위, 글도 같은 층 번호
		var up := sim.rescue.victims.filter(func(v: Victim) -> bool: return v.age >= 75)
		assert_eq(up[0].level, lv + 1, "직상층 노인은 %d층" % (lv + 1))
		assert_true(str(sim.scenario.dispatch.lines[0]).contains("%d01호" % lv), "출동 지령에 %d01호" % lv)
	assert_true(seen.size() >= 2, "시드마다 발화층이 바뀜 (%s)" % [seen.keys()])
	# 메뉴 설명은 층 번호 대신 ○
	var info := ScenarioLoader.info(path)
	assert_true(str(info.meta.summary).contains("○01호"), "메뉴 설명: %s" % str(info.meta.summary).left(40))
	assert_eq(ScenarioLoader.validate(path).size(), 0, "검사 통과")
