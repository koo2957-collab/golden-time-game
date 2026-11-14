extends TestSuite
## 출동 중 장면 (기획안 4-4, 2026-11-14): 차가 달리는 동안 결정을 하나씩 — 지령·상황실 요청 카드·장비(체크 목록)·조별 임무·차량 배치.
## 훈련은 결정을 마칠 때까지 기다리고, 실전은 시간이 되면 도착한다 (정하지 않은 것 = 준비 안 함). 장면은 DispatchUi, 적용은 명령으로.

const HOUSE := "res://data/scenarios/sop214_1_day_living.json"
const LPG := "res://data/scenarios/sop214_3_kitchen_lpg.json"
const WATER_CARD := "ARRIVAL-WATER-01"
const RELAY_CARD := "ARRIVAL-RELAY-01"


func _ui(sim: SimWorld) -> DispatchUi:
	var ui := DispatchUi.new()
	ui.setup(sim)
	ui.open()
	return ui


func _kinds(ui: DispatchUi) -> Array:
	return ui.steps.map(func(s: Dictionary) -> String: return str(s.kind))


## 그 종류의 장면이 뜰 때까지 앞 장면을 첫 보기로 넘긴다
func _goto(ui: DispatchUi, kind: String) -> Dictionary:
	for i in 40:
		ui.advance(1.0)
		var s := ui.current()
		if s.is_empty() or str(s.kind) == kind:
			return s
		if str(s.mode) == "pick":
			ui.choose(0)
		else:
			if str(s.mode) == "select":
				ui.choose(0)
			ui.confirm()
	return {}


func test_params_have_source() -> void:
	var data: Dictionary = JsonData.load_file(DispatchUi.PATH)
	for key: String in data:
		var entry: Variant = data[key]
		if entry is Dictionary:
			assert_true((entry as Dictionary).has("source"), "%s에 source" % key)
	var p := DispatchUi.load_params()
	assert_true(p.has("order") and p.has("texts") and p.has("preassign"), "설정을 읽는다")
	# 출동 단계는 실제 180초 (2026-11-14 사용자 결정: 90초는 너무 빠르다)
	var phase: Dictionary = JsonData.load_file("res://data/command/phase_params.json")
	assert_eq(float(phase.dispatch_real_s.value), 180.0, "출동 단계 실제 시간")
	assert_true(str(SpriteArt.config().get("portraits", {}).get(str(p.portrait_key), "")) != "", "차량 안 무전 그림 자리")


func test_scene_order() -> void:
	var sim := SimWorld.from_scenario(HOUSE)
	var ui := _ui(sim)
	var kinds := _kinds(ui)
	var crews := sim.units.crews.filter(func(c: Crew) -> bool: return sim.command.resources.on_scene(c.squad_id) and not sim.ems.is_ems_crew(c.id)).size()
	assert_true(crews >= 2, "처음 오는 조 (%d)" % crews)
	var want: Array = ["brief", "card", "card", "brief", "loadout"]
	for i in crews:
		want.append("preassign")
	want.append("placement")
	assert_eq(kinds, want, "장면 순서: 지령 → 상황실 요청 → 추가 무전 → 장비 → 조별 임무 → 차량 배치")
	# 지령 줄은 두 장면에 나뉘어 모두 들어간다
	var lines: Array = sim.command.dispatch.lines
	assert_eq((ui.steps[0].lines as Array).size(), 2, "첫 지령 장면에 2줄")
	assert_eq((ui.steps[0].lines as Array) + (ui.steps[3].lines as Array), lines, "지령 줄을 빠짐없이")
	assert_eq([str(ui.steps[1].card_id), str(ui.steps[2].card_id)].has(WATER_CARD) and [str(ui.steps[1].card_id), str(ui.steps[2].card_id)].has(RELAY_CARD), true, "예비 소방용수·관계자 조치 요청도 장면으로")
	assert_eq(str(ui.steps[4].mode), "multi", "장비는 체크 목록")
	assert_eq(str(ui.steps[kinds.size() - 1].mode), "select", "차량 배치는 고르고 확인")
	# 조별 임무 장면은 그 조의 조장이 말한다 (출동대 종류 그림)
	var pre: Dictionary = ui.steps[5]
	assert_true(str(pre.who).contains("조") and str(pre.portrait) != "", "조별 임무: 말하는 사람·그림 (%s)" % pre.who)
	assert_true(str(pre.text).contains("조"), "조 이름이 글에 들어간다")
	# 배치 보기가 없는 시나리오에는 배치 장면이 없다
	var dev := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var dev_ui := _ui(dev)
	assert_true(not _kinds(dev_ui).has("placement"), "배치 보기가 없으면 배치 장면도 없다")
	ui.free()
	dev_ui.free()


func test_one_scene_at_a_time() -> void:
	var sim := SimWorld.from_scenario(HOUSE)
	var ui := _ui(sim)
	assert_true(ui.active and ui.current().is_empty(), "시작 직후에는 잠깐 도시만 보인다")
	assert_true(ui.received_lines().is_empty(), "아직 받은 무전 없음")
	ui.advance(1.0)
	assert_eq(str(ui.current().kind), "brief", "첫 장면 = 출동 지령")
	assert_eq(ui.received_lines().size(), 2, "지령 장면이 뜨면 준비판에도 그 줄")
	ui.choose(0)
	assert_true(bool(ui.steps[0].answered) and ui.index == 1, "수신하면 다음으로")
	assert_true(ui.current().is_empty(), "다음 장면은 잠깐 뒤에")
	ui.choose(0)
	assert_eq(ui.index, 1, "장면이 뜨기 전에는 눌러도 답이 되지 않는다")
	ui.advance(1.0)
	assert_eq(str(ui.current().kind), "card", "다음 장면")
	assert_eq(ui.summary(ui.steps[0]), "수신", "준비판 요약")
	# 카드 보기는 섞여 있어도 고른 것은 카드 파일의 순서로 남는다
	var s := ui.current()
	var spec: Dictionary = s.spec
	ui.choose(1)
	var value := int(s.options[1].value)
	assert_eq(str(spec.options[value].text), str(s.options[1].text), "보기 ↔ 카드 선택지")
	assert_eq(int(ui.result().cards[str(s.card_id)]), value, "고른 선택지가 결과에")
	assert_true(ui.feedback_text(s).contains(str(spec.options[value].grade)) and ui.feedback_text(s).contains("SOP"), "훈련: 등급·근거 한 줄 (%s)" % ui.feedback_text(s))
	ui.free()


func test_loadout_checklist_and_placement() -> void:
	var sim := SimWorld.from_scenario(HOUSE)
	var ui := _ui(sim)
	var s := _goto(ui, "loadout")
	assert_eq(str(s.kind), "loadout", "장비 장면")
	var cap := int(s.cap)
	for i in (s.options as Array).size():
		ui.choose(i)
	assert_eq((s.picked as Array).size(), cap, "정한 개수(%d)까지만" % cap)
	ui.choose(0)
	assert_eq((s.picked as Array).size(), cap - 1, "다시 누르면 뺀다")
	assert_true(not bool(s.answered), "확인 전에는 정해지지 않는다")
	ui.confirm()
	assert_true(bool(s.answered), "확인하면 정해진다")
	var r := ui.result()
	assert_eq((r.loadout as Array).size(), cap - 1, "챙긴 장비")
	assert_true(not (r.loadout as Array).has(str(s.options[0].value)), "뺀 장비는 없다")
	# 차량 배치: 고르기 전에는 확인할 수 없다
	s = _goto(ui, "placement")
	assert_eq(str(s.kind), "placement", "배치 장면")
	ui.confirm()
	assert_true(not bool(s.answered), "고르지 않으면 확인되지 않는다")
	ui.choose(2)
	ui.choose(1)
	assert_eq(s.picked, [1], "하나만 고른다")
	ui.enter()
	assert_true(bool(s.answered) and ui.done(), "Enter = 확인, 마지막 결정")
	r = ui.result()
	assert_eq(int(r.placement), 1, "고른 배치")
	assert_true(not (r.preassign as Dictionary).is_empty(), "조별 임무")
	for id: String in r.preassign:
		assert_true(sim.units.get_crew(int(id)) != null and str(r.preassign[id]) != "", "조 id → 임무 키")
	ui.free()


func test_unanswered_is_unprepared() -> void:
	var sim := SimWorld.from_scenario(HOUSE)
	var ui := _ui(sim)
	var r := ui.result()
	assert_eq([int(r.cards[WATER_CARD]), int(r.cards[RELAY_CARD])], [-1, -1], "정하지 않은 카드는 -1")
	assert_eq([(r.loadout as Array).size(), int(r.placement), (r.preassign as Dictionary).size()], [0, -1, 0], "장비·배치·임무 없음")
	ui.free()


func test_training_waits_and_realtime_arrives() -> void:
	# 훈련: 차가 현장 앞에 닿아도 결정을 마칠 때까지 기다린다
	var sim := SimWorld.from_scenario(HOUSE)
	sim.apply_realism("훈련")
	var ui := _ui(sim)
	var arrived := [0]
	ui.finished.connect(func() -> void: arrived[0] += 1)
	ui.skip()
	assert_true(not ui.skipping, "결정을 마치기 전에는 건너뛸 수 없다")
	ui.advance(ui.real_total() + 5.0)
	assert_true(ui.active and ui.frac() >= 1.0 and arrived[0] == 0, "훈련: 현장 앞에서 기다린다")
	assert_eq(ui.progress(), 1.0, "차는 현장 앞에 서 있다")
	ui.answer_rest()
	ui.advance(0.1)
	assert_true(not ui.active and arrived[0] == 1, "결정을 마치면 도착")
	assert_eq(ui.progress(), -1.0, "도착하면 도시 위 소방차는 사라진다")
	ui.free()
	# 실전: 시간이 되면 그대로 도착 — 정하지 않은 것은 준비 안 함
	var sim2 := SimWorld.from_scenario(HOUSE)
	sim2.apply_realism("실전")
	var ui2 := _ui(sim2)
	var arrived2 := [0]
	ui2.finished.connect(func() -> void: arrived2[0] += 1)
	ui2.advance(ui2.real_total() - 1.0)
	assert_true(ui2.active and arrived2[0] == 0, "실전: 시간이 되기 전")
	ui2.advance(1.5)
	assert_true(not ui2.active and arrived2[0] == 1, "실전: 시간이 되면 도착")
	assert_eq(int(ui2.result().cards[WATER_CARD]), -1, "정하지 않고 도착")
	ui2.free()
	# 결정을 모두 마치면 남은 길을 건너뛴다 — 차는 사라지지 않고 빨리 달려 도착한다
	var sim3 := SimWorld.from_scenario(HOUSE)
	var ui3 := _ui(sim3)
	var arrived3 := [0]
	ui3.finished.connect(func() -> void: arrived3[0] += 1)
	ui3.answer_rest()
	ui3.advance(1.0)
	assert_true(ui3.active and ui3.frac() < 0.1, "마쳐도 누르기 전에는 계속 달린다")
	ui3.enter()
	assert_true(ui3.skipping, "Enter = 남은 길 건너뛰기")
	var before := ui3.frac()
	ui3.advance(ui3.num("skip_s") * 0.5)
	assert_true(ui3.active and ui3.frac() > before + 0.3 and ui3.frac() < 1.0, "건너뛰는 동안 차가 빨리 달린다 (%.2f)" % ui3.frac())
	ui3.advance(ui3.num("skip_s") * 0.5 + 0.1)
	assert_true(not ui3.active and arrived3[0] == 1, "정한 시간 안에 도착")
	ui3.free()


func _option_index(sim: SimWorld, card_id: String, effect: String) -> int:
	for spec: Dictionary in sim.cards.dispatch_specs():
		if str(spec.id) != card_id:
			continue
		var opts: Array = spec.options
		for i in opts.size():
			if str(opts[i].effect) == effect:
				return i
	return -1


func _log_of(sim: SimWorld, card_id: String) -> Dictionary:
	for l in sim.cards.log:
		if str(l.id) == card_id:
			return l
	return {}


## 출동 중에 답한 카드는 도착한 뒤 묻지 않고 그 답대로, 정하지 않은 카드는 '정하지 않음'으로 남는다
func test_dispatch_answers_apply_on_arrival() -> void:
	var sim := SimWorld.from_scenario(LPG)
	assert_eq(sim.cards.dispatch_specs().size(), 2, "출동 단계 카드 2장")
	var relay := _option_index(sim, RELAY_CARD, "relay_all")
	assert_true(relay >= 0, "관계자 조치 '모두 요청' 선택지")
	assert_true(sim.gas.has_gas() and sim.gas.open, "가스 열림")
	sim.issue(CommandOrder.make("dispatch_answers", [], 0, Vector3i.ZERO, {"cards": {RELAY_CARD: relay, WATER_CARD: -1}}))
	var asked := false
	for i in roundi(40.0 / SimClock.TICK_DT):
		sim.step_ticks(1)
		for c in sim.cards.queue:
			if c.id in [RELAY_CARD, WATER_CARD]:
				asked = true
		if not _log_of(sim, RELAY_CARD).is_empty() and not _log_of(sim, WATER_CARD).is_empty():
			break
	assert_true(not asked, "도착한 뒤에 다시 묻지 않는다")
	assert_eq([str(_log_of(sim, RELAY_CARD).get("result", "")), str(_log_of(sim, RELAY_CARD).get("grade", ""))], ["answered", "최선"], "답한 카드는 그 등급으로 기록")
	assert_true(not sim.gas.open, "요청한 조치가 현장에 반영된다 (가스 차단)")
	assert_true(not sim.knowledge.fires.is_empty(), "발화 위치가 상황판에 오른다")
	assert_eq(str(_log_of(sim, WATER_CARD).get("result", "")), "unprepared", "정하지 않은 카드")
	assert_true(not sim.command.reserve_water, "예비 소방용수는 정해지지 않았다")
	assert_eq(sim.events.of_type("dispatch_unprepared").size(), 1, "무전 기록에 '정하지 않음'")
	# 한 번만: 더 흘러도 다시 나오지 않는다
	sim.step_ticks(roundi(20.0 / SimClock.TICK_DT))
	assert_eq(sim.cards.log.filter(func(l: Dictionary) -> bool: return str(l.id) in [RELAY_CARD, WATER_CARD]).size(), 2, "카드마다 한 번")
	# 출동 중 장면을 쓰지 않으면(명령 없음) 예전처럼 도착한 뒤에 묻는다
	var old := SimWorld.from_scenario(LPG)
	var seen := false
	for i in roundi(30.0 / SimClock.TICK_DT):
		old.step_ticks(1)
		if old.cards.queue.any(func(c: CardSystem.Card) -> bool: return c.id == RELAY_CARD):
			seen = true
			break
	assert_true(seen, "명령이 없으면 도착 후 카드로")
