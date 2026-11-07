extends TestSuite
## M7a: 분대 명령칸 고수준 명령 — 진압·수색·철수, 자동화 수준, 자동 행동의 SOP 준수 (백드래프트 징후 문 보류)

const LIVING := Vector3i(13, 15, 1)  # 1층 거실
const ROOM1 := Vector3i(24, 17, 1)  # 1층 방1 (아이)


func _sim(level := "입문") -> SimWorld:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.tactical.set_level(level)
	return sim


func _until(sim: SimWorld, cond: Callable, max_s: float) -> bool:
	for i in roundi(max_s / SimClock.TICK_DT):
		if cond.call():
			return true
		sim.step_ticks(1)
	return cond.call()


func _halts(sim: SimWorld) -> Array[String]:
	var out: Array[String] = []
	for e in sim.events.of_type("tactical_halt"):
		out.append(str(e.reason))
	return out


func test_attack_opens_locked_door_and_sprays() -> void:
	var sim := _sim("입문")
	var front := sim.fire.opening_at(Vector3i(13, 20, 1))
	assert_true(front.locked and not front.is_open, "현관 잠김")
	sim.issue(TacticalCommand.make("attack", [0], LIVING))
	sim.step_ticks(1)
	assert_eq(sim.events.of_type("tactical_start").size(), 1, "진압 시작")
	var ok := _until(sim, func() -> bool:
		var h := sim.water.hose_of_crew(0)
		return h != null and h.flowing, 150.0)
	assert_true(ok, "입문: 잠긴 현관을 파괴하고 수관 연장·방수까지 이어진다")
	assert_true(front.is_open, "현관 개방")
	assert_eq(sim.water.hose_of_crew(0).pattern, HoseLine.Pattern.FOG, "실내는 분무")


func test_levels_halt_at_doors() -> void:
	var sim := _sim("중급")
	sim.issue(TacticalCommand.make("attack", [0], LIVING))
	sim.step_ticks(20)
	var h := _halts(sim)
	assert_true(h.size() == 1 and h[0].contains("잠김"), "중급: 잠긴 문은 지시를 기다린다 (%s)" % [h])
	var sim2 := _sim("상급")
	open_all_doors(sim2)
	sim2.fire.openings[sim2.fire.opening_at(Vector3i(13, 20, 1)).index].is_open = true
	var side := sim2.fire.opening_at(Vector3i(19, 12, 1))
	if side:
		side.is_open = false
		sim2.doors.sync_blocking()
	sim2.issue(TacticalCommand.make("search", [2], ROOM1))
	sim2.step_ticks(20)
	var h2 := _halts(sim2)
	assert_true(h2.is_empty() or h2[0].contains("문 개방 지시"), "상급: 닫힌 문은 직접 열어야 한다 (%s)" % [h2])


func test_backdraft_sign_door_not_opened() -> void:
	var sim := _sim("입문")
	open_all_doors(sim)
	# 거실 문을 닫고 거실에 백드래프트 징후가 있다고 둔다
	var door := sim.fire.opening_at(Vector3i(14, 11, 1))
	assert_true(door != null, "거실 위쪽 문")
	door.is_open = false
	sim.doors.sync_blocking()
	sim.events.add(0, "backdraft_sign", {"room": "1층 거실"})
	for ff in sim.units.get_crew(0).members():
		ff.path.clear()
		ff.pos = Vector2(14.5 + ff.id % 2, 9.5)
		ff.prev_pos = ff.pos
	sim.issue(TacticalCommand.make("attack", [0], LIVING))
	sim.step_ticks(30)
	var h := _halts(sim)
	assert_true(h.size() == 1 and h[0].contains("SOP 210-4.5"), "징후가 있는 문은 열지 않고 보고 (%s)" % [h])
	assert_true(not door.is_open and sim.doors.task_of(door) == null, "문은 닫힌 채")


func test_search_and_auto_rescue() -> void:
	var sim := _sim("입문")
	open_all_doors(sim)
	sim.issue(TacticalCommand.make("search", [2], ROOM1))
	var ok := _until(sim, func() -> bool: return not sim.events.of_type("rescue_pickup").is_empty(), 200.0)
	assert_true(ok, "입문: 수색에서 찾은 아이를 자동으로 이송")
	var sim2 := _sim("중급")
	open_all_doors(sim2)
	sim2.issue(TacticalCommand.make("search", [2], ROOM1))
	_until(sim2, func() -> bool: return not _halts(sim2).is_empty(), 200.0)
	var h := _halts(sim2)
	assert_true(h.size() == 1 and h[0].contains("구조 지시"), "중급: 찾으면 보고하고 지시를 기다림 (%s)" % [h])


func test_auto_stop_and_withdraw() -> void:
	var sim := _sim("입문")
	open_all_doors(sim)
	sim.issue(TacticalCommand.make("attack", [0], LIVING))
	_until(sim, func() -> bool:
		var h := sim.water.hose_of_crew(0)
		return h != null and h.flowing, 120.0)
	var ok := _until(sim, func() -> bool: return not sim.events.of_type("tactical_done").is_empty(), 300.0)
	assert_true(ok, "방 화염이 잡히면 자동으로 방수 중지")
	assert_true(not sim.water.hose_of_crew(0).flowing, "방수 중지")
	var lead := sim.units.get_crew(0).leader
	sim.issue(TacticalCommand.make("withdraw", [0]))
	sim.step_ticks(200)
	assert_true(sim.building.cell(1, floori(lead.pos.x), floori(lead.pos.y)) in BuildingData.OUTDOOR, "철수: 그 조만 밖으로")


func test_other_order_cancels_and_replay() -> void:
	var sim := _sim("입문")
	sim.issue(TacticalCommand.make("attack", [0], LIVING))
	sim.step_ticks(5)
	sim.issue(MoveCommand.new([0], Vector3i(4, 24, 1)))
	sim.step_ticks(1)
	assert_true(sim.tactical.task_of_crew(0) == null, "다른 명령을 받으면 고수준 명령 취소")
	# 다시 하기에서 같은 결과
	var a := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	a.tactical.set_level("입문")
	a.issue(CommandOrder.make("entry", [0]))
	a.step_ticks(30)
	a.issue(TacticalCommand.make("attack", [0], LIVING))
	a.step_ticks(600)
	var r := Replay.begin(a.scenario_path, a.issued, 630, -1, "입문")
	r.step(100000)
	assert_eq(r.sim.units.get_crew(0).leader.pos, a.units.get_crew(0).leader.pos, "고수준 명령도 다시 하기로 같은 결과")
