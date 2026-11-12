extends TestSuite
## 연기 선두 (기획안 5-3-1, 2026-11-12 사용자 결정 A): 불 위에서 솟은 연기가 천장을 따라 교재 수평 속도(0.5~1m/s)로
## 퍼져 벽까지 덮은 뒤 아래로 쌓이고, 선두가 문에 닿고 연기층이 문 윗면보다 내려와야 옆방으로 넘친다

const HOUSE := "res://data/scenarios/sop214_2_night_upstairs.json"


func _sim() -> SimWorld:
	var sim := SimWorld.from_scenario(HOUSE)
	sim.command.resources.clear_schedule()
	return sim


func _room(sim: SimWorld, level: int, name: String) -> Compartment:
	for c in sim.fire.comps:
		if c.level == level and c.name == name:
			return c
	return null


func test_fire_room_front_starts_above_fire_and_covers_at_textbook_speed() -> void:
	var sim := _sim()
	var room := _room(sim, 2, "방4")
	var started := -1.0
	var covered := -1.0
	for s in 120:
		sim.step_ticks(10)
		if started < 0.0 and room.smoke_started():
			started = s + 1.0
			# 출발점은 타는 칸 가운데 (불 위)
			var burning := false
			for i in sim.fire.grid.burning:
				var c3 := sim.fire.grid.cell_of(i)
				if c3.z == 2 and Vector2(c3.x, c3.y).distance_to(room.smoke_origin) < 2.0:
					burning = true
			assert_true(burning, "선두는 불 위에서 출발")
			assert_true(not room.smoke_covered(), "처음에는 천장을 다 덮지 않음")
			assert_true(room.shown_layer_depth() <= room.jet_depth_m + 0.001, "다 덮기 전 화면 두께는 천장류 두께까지만")
		if started >= 0.0 and covered < 0.0 and room.smoke_covered():
			covered = s + 1.0
	assert_true(started >= 0.0 and covered >= 0.0, "불난 방 천장을 다 덮음")
	var took := covered - started
	# 교재 0.5~1m/s: 가장 먼 곳까지 거리 ÷ 1.0 ~ ÷ 0.5 (1초 단위 반올림 여유)
	assert_true(took >= room.smoke_full_m / 1.0 - 1.0 and took <= room.smoke_full_m / 0.5 + 1.0,
		"덮는 시간 %.0fs ≈ %.1fm ÷ 0.5~1m/s" % [took, room.smoke_full_m])


func test_corridor_front_starts_at_door_and_spreads() -> void:
	var sim := _sim()
	var hall := _room(sim, 2, "복도")
	var fire_room := _room(sim, 2, "방4")
	var t_in := -1.0
	var t_cov := -1.0
	for s in 120:
		sim.step_ticks(10)
		if t_in < 0.0 and hall.smoke_started():
			t_in = s + 1.0
			# 들어온 곳 = 불난 방과 복도 사이 개구부
			var door: Opening = null
			for o in sim.fire.openings:
				if (o.room_a == hall.index and o.room_b == fire_room.index) or (o.room_b == hall.index and o.room_a == fire_room.index):
					door = o
			assert_true(door != null and hall.smoke_origin.distance_to(door.center()) < 0.01, "복도 선두는 불난 방 문에서 출발")
			# 문에서 먼 복도 끝은 아직 맑다
			var far := Vector2(hall.rect.position) + Vector2(0.5, 0.5)
			if hall.smoke_origin.distance_to(far) < hall.smoke_origin.distance_to(Vector2(hall.rect.end) - Vector2(0.5, 0.5)):
				far = Vector2(hall.rect.end) - Vector2(0.5, 0.5)
			assert_true(not hall.smoke_reaches(far), "복도 먼 끝은 아직 연기 선두 밖")
		if t_in >= 0.0 and t_cov < 0.0 and hall.smoke_covered():
			t_cov = s + 1.0
	assert_true(t_in > 0.0 and t_cov > t_in, "복도는 문에서 퍼져 나중에 다 덮인다")
	assert_true(t_cov - t_in >= hall.smoke_full_m / 1.0 - 1.0, "11m 복도는 수평 1m/s보다 빨리 덮이지 않음 (%.0fs)" % (t_cov - t_in))


func test_no_outflow_before_front_reaches_door() -> void:
	# 연기층은 문 윗면보다 내려왔어도 선두가 그 문에 닿기 전에는 옆으로 넘치지 않는다
	var sim := _sim()
	var hall := _room(sim, 2, "복도")
	var target: Opening = null
	for o in sim.fire.openings:
		if o.level == 2 and o.room_b != Opening.OUTSIDE and (o.room_a == hall.index or o.room_b == hall.index):
			target = o
	assert_true(target != null, "복도에 옆방 문")
	target.is_open = true
	var other := sim.fire.comps[target.other_side(hall.index)]
	# 복도 반대쪽 끝에서 연기가 막 들어온 상태
	var far := Vector2(hall.rect.position) + Vector2(0.5, 0.5)
	if far.distance_to(target.center()) < (Vector2(hall.rect.end) - Vector2(0.5, 0.5)).distance_to(target.center()):
		far = Vector2(hall.rect.end) - Vector2(0.5, 0.5)
	hall.start_smoke_front(far)
	hall.layer_depth = 1.0
	hall.soot = 0.5
	hall.t_upper = 200.0
	assert_true(not hall.smoke_reaches(target.center(), CompartmentModel.FRONT_DOOR_MARGIN_M), "선두가 아직 문에 안 닿음")
	var before := other.layer_depth
	sim.fire.model.step(0.1)
	assert_eq(other.layer_depth, before, "선두가 닿기 전에는 문으로 넘치지 않음")
	hall.smoke_reach_m = hall.smoke_full_m
	sim.fire.model.step(0.1)
	assert_true(other.layer_depth > before, "선두가 닿으면 넘친다")


func test_legacy_layer_without_front_counts_as_covered() -> void:
	# 선두 없이 연기층만 정한 경우(시험·예전 저장)는 다 덮인 것으로 — 기존 계산 그대로
	var sim := _sim()
	var hall := _room(sim, 2, "복도")
	hall.layer_depth = 1.0
	assert_true(hall.smoke_covered() and hall.smoke_reaches(Vector2(hall.rect.position)), "선두 없음 = 다 덮임")
	assert_eq(hall.shown_layer_depth(), 1.0, "화면 두께 = 실제 두께")


func test_front_params_from_textbook() -> void:
	var d: Dictionary = JsonData.load_file("res://data/fire/fire_params.json")
	assert_eq([d.smoke_front_min_mps.value, d.smoke_front_max_mps.value], [0.5, 1.0], "교재 수평 연기 속도 0.5~1m/s (화재2 제4편 제7절)")
	assert_true(String(d.smoke_front_min_mps.source) == "교재" and String(d.ceiling_jet_depth_ratio.source) == "공학 표준", "근거 표시")
