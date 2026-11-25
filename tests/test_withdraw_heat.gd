extends TestSuite
## 열기에 막힌 철수 (2026-11-25 사용자 결정 — 튜토리얼 자동 진행에서 철수하던 구조 분대가 쓰러진 흐름):
##   ① 호스를 거두며 나오다 열기에 막히면 수관을 그 자리에 놓고 회수를 멈춘다 (전에는 1초마다 다시 불 쪽으로 길을 잡았다)
##   ② 물러날 곳은 뜨거운 칸을 밟지 않고 닿는 식은 칸에서 고른다 (전에는 걸음 수만 보고 불 건너 현관 밖을 골라 매 틱 막혔다)
##   ③ 철수 지시를 기억했다가 길이 열리면 스스로 다시 나온다 ("퇴로 확보, 철수 재개"). 다른 출구가 열려 있으면 그리로 나온다
##   ④ 놓인 관창으로 가다 열기에 막히면 다시 시도하지 않고 "지시 바람"을 보고한다
## 건물: house_2f 1층. 거실(x 9~18, y 12~19) 남쪽에 현관문 (13~14, 20), 동쪽에 복도로 가는 문 (19, 12), 북쪽에 주방 문 (14, 11).
## 현관 안쪽 두 칸에 화염을 세워 현관만 열기로 막는다 (거실 안쪽·복도·주방은 식어 있다)

const HOT_CELLS: Array[Vector2i] = [Vector2i(13, 19), Vector2i(14, 19)]
const HOT_KW := 100.0
const INSIDE := Vector2i(17, 15)
const SIDE_DOOR := Vector3i(31, 12, 1)
const BACK_DOOR := Vector3i(12, 3, 1)


## 현관 안쪽의 화염을 켜거나 끈다 (틱마다 다시 넣는다 — 타는 칸 목록은 화재 단계가 틱마다 새로 만든다)
func _heat(sim: SimWorld, on: bool) -> void:
	var g := sim.fire.grid
	for cell in HOT_CELLS:
		var i := g.index(1, cell.x, cell.y)
		g.hrr[i] = HOT_KW if on else 0.0
		if on and not g.burning.has(i):
			g.burning.append(i)


func _run(sim: SimWorld, ticks: int, hot: bool, until := Callable()) -> bool:
	for k in ticks:
		_heat(sim, hot)
		sim.step_ticks(1)
		sim.cards.queue.clear()
		if until.is_valid() and bool(until.call()):
			_heat(sim, hot)
			return true
	_heat(sim, hot)
	return false


func _indoor(sim: SimWorld, c: Crew) -> bool:
	return not sim.building.cell(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y)) in BuildingData.OUTDOOR


## 현관만 열린 집 (옆문·뒷문은 닫는다 — only_front 가 아니면 모두 열어 둔다)
func _house(only_front: bool) -> SimWorld:
	var sim := make_sim()
	if only_front:
		for at: Vector3i in [SIDE_DOOR, BACK_DOOR]:
			sim.fire.opening_at(at).is_open = false
		sim.doors.sync_blocking()
	return sim


## 조를 거실 안쪽에 세운다 (조원은 조장 옆 칸)
func _put_inside(sim: SimWorld, crew_id: int) -> Crew:
	var c := sim.units.get_crew(crew_id)
	for k in c.list.size():
		var ff: Firefighter = c.list[k]
		ff.pos = Vector2(INSIDE.x + k + 0.5, INSIDE.y + 0.5)
		ff.prev_pos = ff.pos
		ff.level = 1
		ff.prev_level = 1
		ff.path.clear()
	return c


## 진압 조(0)가 거실 안쪽까지 수관을 깔고 서 있다 → [조, 수관]
func _with_hose(sim: SimWorld) -> Array:
	var c := _put_inside(sim, 0)
	sim.water.lay_hose(c.id, sim.water._nearest_pump(Vector2(10, 30)), sim.clock.tick)
	var h := fetch_hose(sim, c.id)
	assert_true(h != null and h.held() and h.points.size() > 5, "거실 안쪽까지 수관이 깔렸다")
	return [c, h]


## ②: 현관이 열기로 막혔으면 가까운 현관 밖이 아니라, 뜨거운 칸을 밟지 않고 닿는 식은 곳(복도·주방 쪽)을 고른다
func test_cool_cell_avoids_hot_cells() -> void:
	var sim := _house(false)
	_heat(sim, true)
	var cond := sim.conditions
	var hazard := cond.hazard_kw_m2()
	var start := Vector2i(15, 18)
	assert_true(cond.heat_at(1, Vector2i(14, 19), false) >= hazard, "현관 안쪽 칸은 위험 (%.1f)" % cond.heat_at(1, Vector2i(14, 19), false))
	var here := cond.heat_at(1, start, false)
	assert_true(here > 1.7 and here < hazard, "선 칸은 따뜻하지만 버틸 만하다 (%.1f)" % here)
	var out := sim.pathfinder.find_path(Vector3i(start.x, start.y, 1), Vector3i(14, 22, 1))
	assert_true(not out.is_empty() and not cond.route_clear(out, false), "현관으로 나가는 길은 열기에 막혀 있다")
	var to := cond._cool_cell(1, start, 2)
	assert_true(to.x >= 0 and to != start, "물러날 칸이 있다 (%s)" % to)
	assert_true(cond._cool_found, "열 스트레스가 쌓이지 않는 곳을 찾았다")
	assert_true(cond.heat_at(1, to, false) <= 1.7, "간 곳은 식은 곳 (%.1f)" % cond.heat_at(1, to, false))
	var path := cond._cool_path(Vector3i(start.x, start.y, 1), to, false)
	assert_true(path.size() >= 2 and path[0] == Vector3i(start.x, start.y, 1), "길은 선 칸에서 시작한다")
	assert_true(cond.route_clear(path, false), "가는 길에 뜨거운 칸이 없다")


## ②: 식은 방으로 가는 문이 모두 닫혀 있으면 닿는 곳 중 가장 덜 뜨거운 칸으로 옮긴다
func test_coolest_reachable_when_sealed() -> void:
	var sim := _house(false)
	for at: Vector3i in [Vector3i(19, 12, 1), Vector3i(14, 11, 1)]:
		sim.fire.opening_at(at).is_open = false
	sim.doors.sync_blocking()
	_heat(sim, true)
	var cond := sim.conditions
	var start := Vector2i(15, 18)
	var to := cond._cool_cell(1, start, 2)
	assert_true(to.x >= 0 and to != start, "옮길 칸이 있다 (%s)" % to)
	assert_true(not cond._cool_found, "다른 방의 식은 곳은 없다")
	assert_true(sim.fire.compartment_at(1, to.x, to.y) == sim.fire.compartment_at(1, start.x, start.y), "같은 방 안에서 옮긴다")
	assert_true(cond.heat_at(1, to, false) < cond.heat_at(1, start, false) * 0.5, "뚜렷이 덜 뜨거운 칸 (%.1f → %.1f)" % [cond.heat_at(1, start, false), cond.heat_at(1, to, false)])
	assert_true(cond.route_clear(cond._cool_path(Vector3i(start.x, start.y, 1), to, false), false), "가는 길에 뜨거운 칸이 없다")


## ①②③: 호스를 거두며 나오다 현관이 열기로 막힘 → 수관을 놓고 식은 곳으로 물러나 기다림 → 고립 보고 → 길이 열리면 스스로 나온다
func test_blocked_recovery_waits_and_resumes() -> void:
	var sim := _house(true)
	var s := _with_hose(sim)
	var c: Crew = s[0]
	var h: HoseLine = s[1]
	if h == null:
		return
	var safety := sim.command.safety
	var cond := sim.conditions
	_heat(sim, true)
	safety.withdraw_crew(c, sim.clock.tick)
	assert_true(h.recovering, "호스를 거두며 철수")
	assert_true(safety.withdrawing.has(c.id), "철수 중으로 적어 둔다")
	var left := _run(sim, 600, true, func() -> bool: return not sim.events.of_type("hose_left_heat").is_empty())
	assert_true(left, "열기에 막히면 호스 회수를 멈춘다")
	assert_true(h.dropped and not h.recovering and h.crew_id == c.id, "수관은 그 자리에 놓인다")
	for ff in c.members():
		assert_eq(ff.speed_factor, 1.0, "호스에서 풀려 제 빠르기로")
	assert_true(safety.withdrawing.has(c.id), "철수 지시는 기억한다")
	# 막힌 채 40초: 식은 곳에서 기다리고, 고립을 한 번 보고한다. 불 쪽으로 다시 가지 않는다
	_run(sim, 400, true)
	var room := sim.fire.compartment_at(1, floori(c.leader.pos.x), floori(c.leader.pos.y))
	assert_true(room == null or room.display_name() != "1층 거실", "거실 밖으로 물러났다 (%s)" % c.leader.pos)
	for ff in c.members():
		assert_true(not ff.incapacitated, "%s 쓰러지지 않음" % ff.name)
		var q := cond.heat_at(ff.level, Vector2i(ff.pos.floor()), ff.crouched)
		assert_true(q <= 1.7, "%s 식은 곳에 있다 (%.1f)" % [ff.name, q])
		assert_true(ff.heat_stress < 0.2, "%s 열 스트레스가 쌓이지 않는다 (%.2f)" % [ff.name, ff.heat_stress])
	assert_true(_indoor(sim, c), "아직 건물 안")
	assert_eq(sim.events.of_type("crew_trapped").size(), 1, "퇴로 차단 — 고립 보고 한 번")
	assert_true(sim.events.of_type("heat_blocked").size() <= 2, "열기 접근 불가를 되풀이하지 않는다 (%d회)" % sim.events.of_type("heat_blocked").size())
	assert_eq(sim.events.of_type("withdraw_resume").size(), 0, "길이 막혀 있는 동안은 나서지 않는다")
	# 열기가 걷히면 스스로 다시 나온다
	var out := _run(sim, 1200, false, func() -> bool: return not _indoor(sim, c) and not c.leader.is_moving())
	assert_true(out, "길이 열리면 밖으로 나온다")
	assert_eq(sim.events.of_type("withdraw_resume").size(), 1, "퇴로 확보, 철수 재개 보고")
	var said := sim.events.of_type("withdraw_resume")
	if not said.is_empty():
		assert_true(SimEventLog.describe_text(said[0]).contains("철수 재개"), "보고 문장: %s" % SimEventLog.describe_text(said[0]))
	_run(sim, 20, false)
	assert_true(not safety.withdrawing.has(c.id), "나왔으면 잊는다")
	assert_true(h.dropped, "수관은 놓인 채 남는다 (다시 잡거나 다른 조가 이어받는다)")


## ③: 수관 없는 조도 같다 — 현관이 막혔고 옆문이 열려 있으면 옆문으로 나온다
func test_blocked_withdraw_uses_other_exit() -> void:
	var sim := _house(false)
	var c := _put_inside(sim, 2)
	var safety := sim.command.safety
	_heat(sim, true)
	safety.withdraw_crew(c, sim.clock.tick)
	assert_true(safety.withdrawing.has(c.id), "철수 중으로 적어 둔다")
	var out := _run(sim, 1500, true, func() -> bool: return not _indoor(sim, c) and not c.leader.is_moving())
	assert_true(out, "다른 출구로 밖에 나왔다")
	assert_true(c.leader.pos.y < 20.0, "현관(남쪽)이 아닌 문으로 나왔다 (%s)" % c.leader.pos)
	assert_eq(sim.events.of_type("withdraw_resume").size(), 1, "퇴로 확보, 철수 재개 보고")
	for ff in c.members():
		assert_true(not ff.incapacitated, "%s 쓰러지지 않음" % ff.name)


## ③: 막혀서 기다리던 조가 다른 지시(이동)를 받으면 철수를 다시 잇지 않는다
func test_new_order_forgets_withdraw() -> void:
	var sim := _house(true)
	var c := _put_inside(sim, 2)
	var safety := sim.command.safety
	_heat(sim, true)
	safety.withdraw_crew(c, sim.clock.tick)
	_run(sim, 200, true)
	assert_true(safety.withdrawing.has(c.id) and bool(safety.withdrawing[c.id].blocked), "막혀서 기다리는 중")
	sim.issue(MoveCommand.new([c.id] as Array[int], Vector3i(24, 12, 1)))
	_run(sim, 5, true)
	assert_true(not safety.withdrawing.has(c.id), "이동 지시로 철수를 잊었다")
	var went_out := _run(sim, 600, false, func() -> bool: return not _indoor(sim, c))
	assert_true(not went_out, "길이 열려도 스스로 나가지 않는다")


## ④: 놓인 관창으로 가다 열기에 막히면 수관을 놓아 두고 "지시 바람"을 보고한다 — 다시 시도하지 않는다
func test_return_to_nozzle_blocked_reports() -> void:
	var sim := _house(true)
	var s := _with_hose(sim)
	var c: Crew = s[0]
	var h: HoseLine = s[1]
	if h == null:
		return
	sim.water.drop_nozzle(c.id, sim.clock.tick)
	for k in c.list.size():
		var ff: Firefighter = c.list[k]
		ff.pos = Vector2(13.5 + k, 23.5)
		ff.prev_pos = ff.pos
		ff.path.clear()
	_heat(sim, true)
	assert_true(sim.water.return_to_nozzle(c.id, sim.clock.tick), "관창으로 간다")
	var halted := _run(sim, 600, true, func() -> bool: return not h.to_nozzle)
	assert_true(halted, "열기에 막히면 관창으로 가기를 멈춘다")
	assert_true(h.dropped and not h.to_nozzle, "수관은 놓인 그대로")
	var said := sim.events.of_type("tactical_halt").filter(func(e: Dictionary) -> bool: return str(e.reason).contains("관창"))
	assert_eq(said.size(), 1, "재진입 보류, 지시 바람 보고")
	_run(sim, 300, true)
	assert_eq(sim.events.of_type("nozzle_return").size(), 1, "다시 시도하지 않는다")
	assert_eq(sim.events.of_type("hose_abandoned").size(), 0, "제한 시간까지 끌지 않는다")
	assert_true(not _indoor(sim, c), "밖에서 기다린다")
	for ff in c.members():
		assert_true(not ff.incapacitated, "%s 쓰러지지 않음" % ff.name)
