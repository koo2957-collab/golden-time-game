extends TestSuite
## 연기 읽기 (2026-11-24 사용자 결정, data/ui/smoke_look.json): 방의 시뮬레이션 값으로 연기 색·빠르기·뻗는 길이를 정한다.
## 화재1 p.342 '중기 이후 검은 연기 분출' · p.124 '분출속도가 약한 백색 연기' · p.255 '연기의 색깔 및 수증기로 소화효과 판단'

const SmokeLook := preload("res://scripts/ui/smoke_look.gd")


func _room() -> Array:
	var sim := SimWorld.from_scenario("res://data/scenarios/dev_squad_house_fire.json", false)
	var c: Compartment = sim.fire.comps[0]
	return [sim, c]


func _lum(col: Color) -> float:
	return (col.r + col.g + col.b) / 3.0


## 갓 난 연기(식고 옅고 산소 충분): 흰빛 회색, 느리게, 짧게
func test_early_smoke_white_slow() -> void:
	var s := _room()
	var sim: SimWorld = s[0]
	var c: Compartment = s[1]
	c.soot = 0.0
	c.t_upper = 30.0
	c.y_o2 = 0.23
	c.cooling_kw = 0.0
	var lk := SmokeLook.look(sim.fire, c)
	assert_true(_lum(lk.color) > 0.75, "흰빛 (밝기 %.2f)" % _lum(lk.color))
	assert_true(float(lk.rate) < 0.7, "느리게 떠오른다 (재생 %.2f)" % lk.rate)
	assert_true(float(lk.reach) < 0.8, "짧게 뻗는다 (%.2f)" % lk.reach)


## 중기 이후(뜨겁고 짙고 산소 부족): 검은 연기, 빠르게, 멀리
func test_developed_smoke_black_fast() -> void:
	var s := _room()
	var sim: SimWorld = s[0]
	var c: Compartment = s[1]
	c.soot = c.volume * 0.05
	c.t_upper = 600.0
	c.y_o2 = 0.10
	c.cooling_kw = 0.0
	var lk := SmokeLook.look(sim.fire, c)
	assert_true(_lum(lk.color) < 0.2, "검은 연기 (밝기 %.2f)" % _lum(lk.color))
	assert_true(float(lk.rate) > 1.5, "세게 뿜어 나온다 (재생 %.2f)" % lk.rate)
	assert_true(float(lk.reach) > 1.3, "멀리 뻗는다 (%.2f)" % lk.reach)


## 방수로 고온층 열을 빼앗으면 흰 수증기가 섞여 밝아진다
func test_steam_whitens() -> void:
	var s := _room()
	var sim: SimWorld = s[0]
	var c: Compartment = s[1]
	c.soot = c.volume * 0.05
	c.t_upper = 300.0
	c.y_o2 = 0.15
	c.cooling_kw = 0.0
	var before := _lum(SmokeLook.look(sim.fire, c).color)
	c.cooling_kw = 800.0
	var lk := SmokeLook.look(sim.fire, c)
	assert_true(_lum(lk.color) > before + 0.3, "수증기로 밝아진다 (%.2f → %.2f)" % [before, _lum(lk.color)])
	assert_true(float(lk.steam) > 0.5, "수증기 비율 %.2f" % lk.steam)


## 백드래프트 징후 (연기 읽기 2단계, 화재1 p.44): 징후가 있는 방의 닫힌 문 틈에서만 검은 연기가 새어 나온다 —
## 조건은 무전 징후 보고(HazardSystem.backdraft_sign)와 같다. 문을 열면(또는 징후가 없으면) 없다
func test_backdraft_seep_only_on_sign() -> void:
	var s := _room()
	var sim: SimWorld = s[0]
	var door: Opening = null
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.DOOR and o.room_a != Opening.OUTSIDE and o.level == 1:
			door = o
			break
	assert_true(door != null, "1층 문")
	if door == null:
		return
	var c: Compartment = sim.fire.comps[door.room_a]
	door.is_open = false
	assert_true(FloorLayer.backdraft_seeps(sim, 1).filter(func(e: Array) -> bool: return int(e[5]) == door.index).is_empty(), "징후 없으면 없다")
	c.gas = 0.2 * 1.2 * c.volume
	c.y_o2 = 0.23 * 10.0 / 21.0
	c.t_upper = 500.0
	assert_true(sim.hazards.backdraft_sign(c), "징후 조건 (가스 %.1f%% · 산소 %.1f%% · %.0f℃)" % [c.gas_percent(), c.o2_percent(), c.t_upper])
	var seeps := FloorLayer.backdraft_seeps(sim, 1).filter(func(e: Array) -> bool: return int(e[5]) == door.index)
	assert_eq(seeps.size(), 1, "닫힌 문 틈에서 검은 연기")
	door.is_open = true
	assert_true(FloorLayer.backdraft_seeps(sim, 1).filter(func(e: Array) -> bool: return int(e[5]) == door.index).is_empty(), "문을 열면 없다")


## 색은 단계가 아니라 이어진다 (온도가 오르면 점점 어두워진다)
func test_continuous() -> void:
	var s := _room()
	var sim: SimWorld = s[0]
	var c: Compartment = s[1]
	c.soot = c.volume * 0.004
	c.y_o2 = 0.2
	c.cooling_kw = 0.0
	var last := 2.0
	for t in [40.0, 120.0, 220.0, 320.0, 420.0]:
		c.t_upper = t
		var l := _lum(SmokeLook.look(sim.fire, c).color)
		assert_true(l <= last + 0.001, "%.0f℃ 에서 더 어둡거나 같다 (%.2f)" % [t, l])
		last = l
