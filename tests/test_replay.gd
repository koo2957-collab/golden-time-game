extends TestSuite
## M6b: 다시 하기 — 같은 명령을 같은 틱에 다시 넣으면 같은 상태가 된다 (결정론)

const T := 900


## 상태 요약: 대원·차량·지휘관 위치, 연소 칸, 구획 온도, 요구조자 노출, 사건·무전 수
func _fingerprint(sim: SimWorld) -> String:
	var parts: PackedStringArray = []
	for ff in sim.units.firefighters:
		parts.append("%.3f,%.3f,%d,%.1f" % [ff.pos.x, ff.pos.y, ff.level, ff.air_l])
	for v in sim.units.vehicles:
		parts.append("%.3f,%.3f,%.0f" % [v.pos.x, v.pos.y, v.tank_l])
	parts.append("%.3f,%.3f" % [sim.command.commander.pos.x, sim.command.commander.pos.y])
	parts.append(str(sim.fire.grid.burning.size()))
	for c in sim.fire.comps:
		parts.append("%.2f" % c.t_upper)
	for v in sim.rescue.victims:
		parts.append("%.4f,%d" % [v.fed(), v.state])
	parts.append("%d,%d" % [sim.events.entries.size(), sim.command.radio.history.size()])
	return "|".join(parts)


func _play(sim: SimWorld, until: int) -> void:
	var answers := {
		"fire": "연기만 확인", "victims": "있음", "use": "단독주택", "floors": "2층",
		"structure": "벽돌조", "hazards": [], "activities": ["인명검색"],
		"strategy": CommandSystem.Strategy.OFFENSIVE, "support": "불필요", "access": "진입 가능, 회차 불가",
	}
	var script := {
		5: [CommandOrder.make("declare", [], 0, Vector3i.ZERO, answers)],
		12: [CommandOrder.make("entry", [0, 1])],
		300: [MoveCommand.new([0], Vector3i(13, 21, 1)), CommandOrder.make("survey")],
		420: [EquipmentCommand.make("door_open", [0, 1], -1, -1, Vector3i(13, 20, 1))],
		700: [EquipmentCommand.make("spray", [0], -1, 0, Vector3i(12, 16, 1)), EquipmentCommand.make("search", [2], -1, -1, Vector3i(24, 17, 1))],
	}
	while sim.clock.tick < until:
		for c in script.get(sim.clock.tick, []):
			sim.issue(c)
		sim.step_ticks(1)


func test_replay_matches_original() -> void:
	var original := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	_play(original, T)
	assert_true(original.issued.size() >= 7, "명령 기록 (%d건)" % original.issued.size())
	assert_eq(original.issued[0].tick, 5, "내린 틱 기록")
	var before := _fingerprint(original)
	var r := Replay.begin(original.scenario_path, original.issued, T)
	var chunks := 0
	while not r.step(200):
		chunks += 1
	assert_true(chunks >= 3, "여러 번에 나눠 진행")
	assert_eq(r.sim.clock.tick, T, "목표 틱까지 진행")
	assert_eq(_fingerprint(r.sim), before, "다시 하기한 상태가 원래 판과 같다")
	assert_eq(r.sim.issued.size(), original.issued.size(), "다시 하기한 판에도 명령 기록이 남는다 (또 다시 하기 가능)")


func test_replay_to_earlier_point() -> void:
	var original := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	_play(original, T)
	var r := Replay.begin(original.scenario_path, original.issued, 350)
	r.step(100000)
	assert_eq(r.sim.issued.size(), 4, "그 시점 전에 내린 명령만 재생 (선언·진입·이동·둘러보기)")
	var again := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	_play(again, 350)
	assert_eq(_fingerprint(r.sim), _fingerprint(again), "중간 시점 상태도 같다")
	assert_eq(r.progress(), 1.0, "진행률")
