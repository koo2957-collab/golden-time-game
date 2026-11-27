extends TestSuite
## 자연스러운 움직임 (2026-11-27 사용자: 방수·이동할 때 대원들이 왔다갔다 하는 게 어색하다 — tests/_probe_motion.gd 로 잰 세 원인):
##   ① 방수 중 전진 판단이 헛걸음이면 다음 시도를 늦춘다 (5초마다 대형이 풀리지 않게)
##   ② 설 자리가 한순간에 뛰면 순간이동하지 않고 걸어서 옮겨 간다
##   ③ 한순간 바뀌었다 돌아오는 동작은 걸러낸다


func _layer(sim: SimWorld) -> Array:
	var sel := SelectionController.new()
	var layer := FloorLayer.new()
	layer.setup(sim, sel, IsoProjection.new())
	layer.level = 1
	layer.smooth = true
	return [layer, sel]


func _free(nodes: Array) -> void:
	for n: Node in nodes:
		n.free()


## ① 전진을 지시했는데 제자리였으면 다음 시도가 5초 → 15초 → 25초 … (한도 advance_backoff_max_s)로 늦어지고, 움직였으면 다시 5초
func test_advance_backs_off_when_stuck() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.step_ticks(2)
	var c := sim.units.crews[0]
	var h := HoseLine.new()
	h.crew_id = c.id
	h.target = Vector3i(-9, -9, c.leader.level)  # 방이 아닌 곳 — 전진 계산은 거기서 끝난다 (기다림 계산만 본다)
	var every := WaterSystem.ADVANCE_EVERY_TICKS
	h.advance_from = c.leader.cell3()
	sim.water._advance(h, c, 1000)
	assert_eq(h.advance_fails, 1, "제자리 → 헛걸음 1")
	assert_eq(h.next_advance_tick, 1000 + every * 3, "다음 시도는 15초 뒤")
	h.advance_from = c.leader.cell3()
	sim.water._advance(h, c, h.next_advance_tick)
	assert_eq(h.advance_fails, 2, "또 제자리 → 헛걸음 2")
	var max_ticks: int = sim.water._advance_backoff_ticks
	var before := 0
	for i in 6:
		h.advance_from = c.leader.cell3()
		before = h.next_advance_tick
		sim.water._advance(h, c, before)
	assert_eq(h.next_advance_tick - before, max_ticks, "늦추는 한도(%d초)에서 멈춘다" % roundi(max_ticks * SimClock.TICK_DT))
	# 움직였으면(시작 칸과 다르면) 다시 처음 간격
	var t0 := h.next_advance_tick
	h.advance_from = c.leader.cell3() + Vector3i(3, 0, 0)
	sim.water._advance(h, c, t0)
	assert_eq([h.advance_fails, h.next_advance_tick], [0, t0 + every], "움직였으면 헛걸음 0 · 5초 간격")


## ② 설 자리가 뛰면 그 자리로 걸어서 간다: 바로 뛰지 않고, 시간이 지나면 닿는다. 아주 멀면 바로 선다
func test_shown_pos_walks_to_new_spot() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	sim.step_ticks(2)
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var ff := sim.units.crews[0].leader
	ff.aboard = false
	ff.prev_pos = ff.pos
	var cell_m := sim.units.cell_size_m
	var p0 := layer._shown_pos(ff, 0.0)
	assert_true(p0.is_equal_approx(ff.pos), "처음은 실제 자리")
	# 2m 뜀
	var jump := Vector2(2.0 / cell_m, 0.0)
	ff.pos += jump
	ff.prev_pos = ff.pos
	var p1 := layer._shown_pos(ff, 0.0)
	assert_true(p1.distance_to(p0) * cell_m < 0.3, "한순간에 뛰지 않는다 (%.2fm)" % (p1.distance_to(p0) * cell_m))
	assert_true(layer._settle_gap(ff).length() * cell_m > 1.5, "남은 거리가 있다")
	OS.delay_msec(300)
	var p2 := layer._shown_pos(ff, 0.0)
	assert_true(p2.distance_to(p0) > p1.distance_to(p0) and p2.distance_to(ff.pos) * cell_m > 0.5, "걷는 속도로 좁혀 가는 중 (남은 %.2fm)" % (p2.distance_to(ff.pos) * cell_m))
	for i in 8:
		OS.delay_msec(200)
		p2 = layer._shown_pos(ff, 0.0)
	assert_true(p2.is_equal_approx(ff.pos), "시간이 지나면 닿는다")
	# 이어진 걸음(작은 움직임)은 그대로 따라간다
	ff.pos += Vector2(0.1, 0.0)
	ff.prev_pos = ff.pos
	assert_true(layer._shown_pos(ff, 0.0).is_equal_approx(ff.pos), "작은 움직임은 바로 따라간다")
	# 아주 멀면(차에서 내림·승강기) 바로
	ff.pos += Vector2(20.0 / cell_m, 0.0)
	ff.prev_pos = ff.pos
	assert_true(layer._shown_pos(ff, 0.0).is_equal_approx(ff.pos), "아주 멀면 바로 선다")
	# 끄면(창 없는 테스트 기본) 늘 실제 자리
	layer.smooth = false
	ff.pos += jump
	ff.prev_pos = ff.pos
	assert_true(layer._shown_pos(ff, 0.0).is_equal_approx(ff.pos), "끄면 보정 없음")
	_free(nodes)


## ③ 서 있는 동작끼리는 새 동작이 anim_hold_ms 이어져야 바뀐다. 걷기 시작과 쓰러짐은 바로
func test_anim_flicker_is_held() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var hold := int(HoseDraw.style().get("anim_hold_ms", 200))
	assert_eq(layer._hold_anim(5, "spray_n", false), "spray_n", "처음 동작")
	assert_eq(layer._hold_anim(5, "idle", false), "spray_n", "한순간 바뀐 동작은 아직 안 보인다")
	assert_eq(layer._hold_anim(5, "spray_n", false), "spray_n", "돌아오면 그대로 — 깜빡임 없음")
	assert_eq(layer._hold_anim(5, "idle", false), "spray_n", "다시 바뀌려 함")
	OS.delay_msec(hold + 40)
	assert_eq(layer._hold_anim(5, "idle", false), "idle", "이어지면 바뀐다")
	assert_eq(layer._hold_anim(5, "walk", true), "walk", "걷기 시작은 바로")
	assert_eq(layer._hold_anim(5, "down", false), "down", "쓰러짐은 바로")
	_free(nodes)


## 걷는 방향도 여유각을 둔다 — 칸 경계에서 방향이 왔다갔다 하지 않는다
func test_walk_direction_hysteresis() -> void:
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH, false)
	var nodes := _layer(sim)
	var layer: FloorLayer = nodes[0]
	var hyst := float(HoseDraw.style().get("spray_turn_hysteresis_deg", 10.0))
	var key := FloorLayer.WALK_K_KEY - 3
	var v := func(deg: float) -> Vector2: return Vector2.RIGHT.rotated(deg_to_rad(deg))
	assert_eq(layer._hyst_k(key, v.call(0.0), 1), 0, "처음 = 걷는 쪽")
	assert_eq(layer._hyst_k(key, v.call(22.5 + hyst * 0.5), 1), 0, "경계를 조금 넘어도 그대로")
	assert_eq(layer._hyst_k(key, v.call(22.5 - hyst * 0.5), 1), 0, "되돌아와도 그대로")
	assert_eq(layer._hyst_k(key, v.call(45.0), 1), 1, "확실히 돌면 바뀐다")
	_free(nodes)
