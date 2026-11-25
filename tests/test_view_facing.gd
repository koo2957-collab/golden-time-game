extends TestSuite
## 외부 화면 ↔ 내부 화면을 오가도 대원 그림의 방향·자리가 같다 (2026-11-25 사용자: 대원이 밖에 있을 때 건물 내부를 눌렀다가
## 외부로 나오면 대원 위치와 보는 방향이 달라져 있다).
## 외부 화면의 대원은 지상층 겹(IsoView.layers[0])이, 내부 화면의 대원은 색 겹(current_live)이 그린다. 전에는 방향 기억이 겹마다
## 따로였고 그 겹이 그리는 동안 걸은 것만 적었다. 이제 한 사전을 같이 쓰고 IsoView 가 매 프레임 적는다 (update_facing).
## 화면 없이 자세·자리 계산만 본다.

const SCENARIO := "res://data/scenarios/dev_squad_house_fire.json"


## 화면 없이 쓰는 입체 화면 [입체 화면, 선택] — 끝나면 _free 로 지운다
func _iso(sim: SimWorld) -> Array:
	var sel := SelectionController.new()
	var iso := IsoView.new()
	iso.setup(sim, sel, IsoProjection.new())
	return [iso, sel]


func _free(nodes: Array) -> void:
	for n: Node in nodes:
		n.free()


## 조를 (dx, dy) 만큼 걷게 하고 멈출 때까지 돌린다 (프레임마다 방향을 적는 것을 흉내 낸다)
func _walk(sim: SimWorld, iso: IsoView, c: Crew, step: Vector2i) -> void:
	sim.units.order_move([c.id] as Array[int], Vector3i(floori(c.leader.pos.x) + step.x, floori(c.leader.pos.y) + step.y, c.leader.level), sim.pathfinder)
	for i in 600:
		sim.step_ticks(1)
		sim.cards.queue.clear()
		iso.update_facing()
		if not c.leader.is_moving() and i > 5:
			break
	sim.step_ticks(2)
	iso.update_facing()


func _dir(layer: FloorLayer, sim: SimWorld, c: Crew, ff: Firefighter) -> int:
	return int(layer._unit_pose(ff, c, SpriteArt.crew_set(sim.units.squads[c.squad_id].type))[1])


## 외부 화면에서 걸은 뒤 내부 화면으로: 색 겹도 같은 방향 (전에는 기본 방향 1로 돌아섰다)
func test_same_direction_after_entering_interior() -> void:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var nodes := _iso(sim)
	var iso: IsoView = nodes[0]
	var c := sim.units.get_crew(0)
	var ground: int = sim.building.levels()[0]
	iso.show_view(ground, true, false)
	_walk(sim, iso, c, Vector2i(-5, 0))
	var west := SpriteArt.dir8(Vector2(-1, 0))
	assert_true(west != 1, "서쪽은 기본 방향(1)이 아니다")
	assert_eq(_dir(iso.layers[0], sim, c, c.leader), west, "외부 화면: 걸어간 쪽(서)을 본다")
	iso.show_view(ground, false, false)
	for ff in c.list:
		assert_eq(_dir(iso.current_live, sim, c, ff), _dir(iso.layers[0], sim, c, ff), "%s 내부 화면에서도 같은 방향" % ff.name)
	assert_eq(_dir(iso.current_live, sim, c, c.leader), west, "내부 화면: 조장은 여전히 서쪽을 본다")
	_free(nodes)


## 내부 화면을 보는 동안 걸은 뒤 외부 화면으로: 지상층 겹도 새 방향 (전에는 들어가기 전의 옛 방향이었다)
func test_same_direction_after_walking_in_interior_view() -> void:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var nodes := _iso(sim)
	var iso: IsoView = nodes[0]
	var c := sim.units.get_crew(0)
	var ground: int = sim.building.levels()[0]
	iso.show_view(ground, true, false)
	_walk(sim, iso, c, Vector2i(-5, 0))
	iso.show_view(ground, false, false)
	_walk(sim, iso, c, Vector2i(5, 0))
	var east := SpriteArt.dir8(Vector2(1, 0))
	assert_eq(_dir(iso.current_live, sim, c, c.leader), east, "내부 화면: 새로 걸어간 쪽(동)을 본다")
	iso.show_view(ground, true, false)
	for ff in c.list:
		assert_eq(_dir(iso.layers[0], sim, c, ff), _dir(iso.current_live, sim, c, ff), "%s 외부 화면에서도 같은 방향" % ff.name)
	assert_eq(_dir(iso.layers[0], sim, c, c.leader), east, "외부 화면: 조장은 동쪽을 본다")
	_free(nodes)


## 조장 방향을 기준으로 서는 조원(물이 차기 전 호스를 끼고 걷는 2번)은 자리도 두 화면에서 같다
func test_hose_carry_spot_same_in_both_views() -> void:
	var sim := SimWorld.from_scenario(SCENARIO, false)
	var nodes := _iso(sim)
	var iso: IsoView = nodes[0]
	var c := sim.units.get_crew(0)
	var ground: int = sim.building.levels()[0]
	iso.show_view(ground, true, false)
	sim.water.lay_hose(c.id, sim.water._nearest_pump(c.leader.pos), sim.clock.tick)
	var h := fetch_hose(sim, c.id, false)
	assert_true(h != null, "호스를 꺼냈다")
	if h == null:
		_free(nodes)
		return
	h.ready_tick = 1 << 30
	_walk(sim, iso, c, Vector2i(8, -3))
	var art := SpriteArt.crew_set(sim.units.squads[c.squad_id].type)
	var ext: FloorLayer = iso.layers[0]
	var live: FloorLayer = iso.current_live
	var lay := ext._hose_carry_layout(c, art)
	assert_true(not h.charged and lay.get("spots", {}).size() >= 1, "호스 끼고 걷기 배치가 살아 있다 (조원 자리 %d개)" % lay.get("spots", {}).size())
	iso.show_view(ground, false, false)
	for ff in c.list:
		var a := ext._shown_pos(ff, 1.0)
		var b := live._shown_pos(ff, 1.0)
		assert_true(a.distance_to(b) < 0.001, "%s 그리는 자리가 두 화면에서 같다 (%s · %s)" % [ff.name, a, b])
		assert_eq(_dir(live, sim, c, ff), _dir(ext, sim, c, ff), "%s 방향도 같다" % ff.name)
	_free(nodes)
