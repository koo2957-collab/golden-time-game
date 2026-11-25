extends TestSuite
## 불꽃 배치 (FireDraw — 2026-11-22, 참고 그림 '화재성장속도, 4단계'):
## 가까운 타는 칸을 불 한 채로 묶고, 열방출률로 화염 높이를 셈해(Heskestad 식) 크기에 맞는 그림을 고른다. 화면 없이 계산만 본다.

const CELL_M := 0.5
const CEILING_M := 2.4


func _cell(x: int, y: int, kw: float, room := 0, base := 0.0, faded := false) -> Dictionary:
	return {"x": x, "y": y, "kw": kw, "room": room, "base": base, "faded": faded}


## 가로 w칸 × 세로 h칸이 모두 같은 세기로 탄다
func _block(x0: int, y0: int, w: int, h: int, kw: float, room := 0) -> Array:
	var out: Array = []
	for y in h:
		for x in w:
			out.append(_cell(x0 + x, y0 + y, kw, room))
	return out


func _main(list: Array[Dictionary]) -> Array[Dictionary]:
	return list.filter(func(f: Dictionary) -> bool: return not bool(f.satellite))


func test_style_values_have_source() -> void:
	var data: Variant = JsonData.load_file(FireDraw.PATH)
	assert_true(data is Dictionary, "설정 파일")
	for key: String in data:
		if key == "note":
			continue
		assert_true(data[key] is Dictionary and data[key].has("value") and str(data[key].get("source", "")) != "", "%s 값과 source" % key)
	assert_true(str(data.heskestad_a.source).contains("공학 표준"), "화염 높이 식의 근거는 공학 표준")
	var aspect: Dictionary = FireDraw.style().kind_aspect
	for kind in FireDraw.KINDS:
		assert_true(aspect.has(kind), "%s 그림의 모양" % kind)


## Heskestad 식: L = 0.235·Q^0.4 − 1.02·D
func test_flame_height_follows_heskestad() -> void:
	assert_true(absf(FireDraw.flame_height_m(100.0, 0.5) - (0.235 * pow(100.0, 0.4) - 0.51)) < 0.001, "100kW · 지름 0.5m")
	assert_true(absf(FireDraw.flame_height_m(1000.0, 1.0) - 2.704) < 0.01, "1MW · 지름 1m ≈ 2.7m (%.2f)" % FireDraw.flame_height_m(1000.0, 1.0))
	assert_true(FireDraw.flame_height_m(500.0, 1.0) > FireDraw.flame_height_m(100.0, 1.0), "열방출률이 크면 더 높다")
	assert_true(FireDraw.flame_height_m(500.0, 2.0) < FireDraw.flame_height_m(500.0, 1.0), "같은 열방출률이면 넓게 퍼진 불이 더 낮다")
	assert_eq(FireDraw.flame_height_m(1.0, 3.0), 0.0, "0보다 작아지지 않는다")
	assert_eq(FireDraw.flame_height_m(0.0, 0.5), 0.0, "타지 않으면 0")
	assert_true(absf(FireDraw.diameter_m(PI) - 2.0) < 0.001, "넓이 π m² = 지름 2m")


func test_single_cell_is_one_small_flame_at_cell_center() -> void:
	var list := FireDraw.bodies([_cell(6, 9, 20.0)], CELL_M, CEILING_M)
	assert_eq(list.size(), 1, "불 하나")
	var f: Dictionary = list[0]
	assert_eq(f.pos, Vector2(6.5, 9.5), "그 칸 가운데")
	assert_eq(f.kind, "s", "작은 불")
	assert_true(float(f.height_m) >= FireDraw.num("min_height_m"), "갓 붙은 불도 보인다 (%.2fm)" % float(f.height_m))
	assert_true(not bool(f.capped) and not bool(f.satellite) and not bool(f.faded), "천장에 닿지 않은 보통 불")


## 참고 그림의 뜻: 불이 자라면(열방출률이 커지면) 불꽃이 s → m → l → xl 로 커진다
func test_flame_grows_through_four_sizes() -> void:
	var seen: Array[String] = []
	var last_h := 0.0
	var last_rank := 0
	for kw_per_cell: float in [2.0, 20.0, 45.0, 75.0, 90.0, 160.0]:
		var f: Dictionary = _main(FireDraw.bodies(_block(0, 0, 4, 4, kw_per_cell), CELL_M, CEILING_M))[0]
		var rank := FireDraw.KINDS.find(str(f.kind))
		assert_true(float(f.height_m) >= last_h, "%.0fkW/칸: 높이가 줄지 않는다 (%.2f)" % [kw_per_cell, float(f.height_m)])
		assert_true(rank >= last_rank, "%.0fkW/칸: 그림이 작아지지 않는다 (%s)" % [kw_per_cell, f.kind])
		last_h = float(f.height_m)
		last_rank = rank
		if not seen.has(str(f.kind)):
			seen.append(str(f.kind))
	assert_eq(seen, ["s", "m", "l", "xl"] as Array[String], "네 크기를 차례로 거친다")


func test_height_is_capped_at_ceiling() -> void:
	var f: Dictionary = _main(FireDraw.bodies(_block(0, 0, 4, 4, 300.0), CELL_M, CEILING_M))[0]
	assert_true(absf(float(f.height_m) - CEILING_M) < 0.001, "천장 높이까지만 (%.2f)" % float(f.height_m))
	assert_true(bool(f.capped), "천장에 닿았다는 표시")
	assert_eq(f.kind, "xl", "넓게 타며 천장에 닿으면 불바다 그림")
	# 가구 위에서 타면 남은 높이까지만
	var cells := _block(0, 0, 4, 4, 300.0)
	for c: Dictionary in cells:
		c.base = 0.8
	var on_top: Dictionary = _main(FireDraw.bodies(cells, CELL_M, CEILING_M))[0]
	assert_true(absf(float(on_top.base_m) - 0.8) < 0.001, "불 뿌리 = 가구 높이")
	assert_true(absf(float(on_top.height_m) - (CEILING_M - 0.8)) < 0.001, "천장까지 남은 높이 (%.2f)" % float(on_top.height_m))


## 화염 높이는 방 하나의 불 전체로 셈한다: 바둑판 여러 칸에 걸친 불을 조각마다 따로 셈하면 실제보다 낮아진다
func test_height_uses_whole_room_fire() -> void:
	# 4m × 2m 가 60kW/칸으로 탄다 (두 채): 전체 1,920kW · 지름 3.19m → 약 1.6m
	var wide := _main(FireDraw.bodies(_block(0, 0, 8, 4, 60.0), CELL_M, CEILING_M))
	assert_eq(wide.size(), 2, "두 채")
	var whole := FireDraw.flame_height_m(60.0 * 32, FireDraw.diameter_m(32 * CELL_M * CELL_M))
	var alone := FireDraw.flame_height_m(60.0 * 16, FireDraw.diameter_m(16 * CELL_M * CELL_M))
	assert_true(whole > alone, "한 덩어리로 셈한 높이가 더 높다 (%.2f > %.2f)" % [whole, alone])
	for f in wide:
		assert_true(absf(float(f.height_m) - whole) < 0.001, "두 채 모두 방 전체로 셈한 높이 (%.2f)" % float(f.height_m))
	# 센 채와 약한 채: 약한 쪽이 낮되 weak_ratio 아래로는 내려가지 않는다
	var cells := _block(0, 0, 4, 4, 100.0)
	cells.append_array(_block(4, 0, 4, 4, 10.0))
	var mixed := _main(FireDraw.bodies(cells, CELL_M, CEILING_M))
	mixed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.kw) > float(b.kw))
	assert_true(float(mixed[1].height_m) < float(mixed[0].height_m), "약한 채가 더 낮다")
	assert_true(float(mixed[1].height_m) >= float(mixed[0].height_m) * FireDraw.num("weak_ratio") - 0.001, "그래도 센 채의 %.0f%% 이상" % (FireDraw.num("weak_ratio") * 100.0))
	# 다른 방의 불은 높이에 끼어들지 않는다
	var other := _block(0, 0, 2, 2, 5.0, 1)
	other.append_array(_block(2, 0, 2, 2, 300.0, 2))
	var small: Dictionary = FireDraw.bodies(other, CELL_M, CEILING_M).filter(func(f: Dictionary) -> bool: return float(f.kw) < 100.0)[0]
	assert_eq(small.kind, "s", "옆방이 세게 타도 이 방의 작은 불은 작게")


## 플래시오버 뒤 방 전체가 타는 동안(full)은 칸마다의 세기와 상관없이 화염이 천장까지 찬다
func test_fully_involved_room_fills_to_ceiling() -> void:
	var cells := _block(0, 0, 8, 8, 15.0)
	var before := _main(FireDraw.bodies(cells, CELL_M, CEILING_M))
	for c: Dictionary in cells:
		c.full = true
	var after := _main(FireDraw.bodies(cells, CELL_M, CEILING_M))
	assert_true(float(before[0].height_m) < 1.0, "같은 세기라도 방 전체가 타기 전에는 낮다 (%.2f)" % float(before[0].height_m))
	for f in after:
		assert_true(absf(float(f.height_m) - CEILING_M) < 0.001 and bool(f.capped), "천장까지 (%.2f)" % float(f.height_m))
		assert_eq(f.kind, "xl", "불바다 그림")


## 좁게 솟는 센 불은 불바다(xl)가 아니라 불기둥(l)
func test_narrow_strong_fire_is_a_column() -> void:
	var f: Dictionary = FireDraw.bodies([_cell(0, 0, 600.0)], CELL_M, CEILING_M)[0]
	assert_eq(f.kind, "l", "한 칸에서 솟는 센 불")
	assert_eq(FireDraw.kind_for(2.3, 2.2), "xl", "넓고 높은 불")
	assert_eq(FireDraw.kind_for(2.3, 0.6), "l", "좁고 높은 불")
	assert_eq(FireDraw.kind_for(1.2, 2.2), "m", "넓어도 낮으면 중간 불")


## 방 하나가 다 탈 때: 칸마다 하나가 아니라 몇 채로 묶인다 (줄 맞춘 고깔이 되지 않는다)
func test_room_fire_is_a_few_bodies_not_one_per_cell() -> void:
	var cells := _block(0, 0, 12, 8, 120.0)
	var list := FireDraw.bodies(cells, CELL_M, CEILING_M)
	var main := _main(list)
	assert_eq(main.size(), 6, "2m 바둑판 3 × 2 = 여섯 채")
	assert_true(list.size() <= main.size() * (1 + int(FireDraw.num("satellite_count"))), "곁불은 한 채에 둘까지 (%d)" % list.size())
	assert_true(list.size() < cells.size() / 4, "그리는 불꽃이 타는 칸보다 훨씬 적다 (%d < %d칸)" % [list.size(), cells.size()])
	var total := 0.0
	for f in main:
		total += float(f.kw)
		assert_eq(f.kind, "xl", "다 타는 방은 불바다 그림")
	assert_true(absf(total - 120.0 * cells.size()) < 0.01, "열방출률 합은 그대로 (%.0fkW)" % total)
	# 자리가 줄 맞춰 서지 않는다: 바둑판 칸 가운데에서 조금씩 흩어져 있다
	var off_grid := 0
	for f in main:
		var p: Vector2 = f.pos
		if absf(fmod(p.x, 4.0) - 2.0) > 0.01 or absf(fmod(p.y, 4.0) - 2.0) > 0.01:
			off_grid += 1
	assert_true(off_grid >= 4, "여섯 채 중 넷 이상이 칸 가운데에서 벗어나 있다 (%d)" % off_grid)
	# 뒤에서 앞으로 (깊이 순서)
	for k in range(1, list.size()):
		assert_true(list[k].pos.x + list[k].pos.y >= list[k - 1].pos.x + list[k - 1].pos.y, "깊이 순서")


## 불 자리 = 열방출률 무게 중심 (세게 타는 쪽으로 쏠린다)
func test_position_is_heat_weighted() -> void:
	var list := FireDraw.bodies([_cell(0, 0, 10.0), _cell(3, 0, 300.0)], CELL_M, CEILING_M)
	var f: Dictionary = _main(list)[0]
	assert_true(f.pos.x > 2.5, "센 칸 쪽으로 (x = %.2f)" % f.pos.x)
	assert_eq(int(f.cells), 2, "두 칸을 묶음")


func test_rooms_and_remembered_fire_are_kept_apart() -> void:
	# 같은 바둑판 칸 안이라도 방이 다르면 따로 (벽 너머 불과 한 덩어리가 되지 않는다)
	var two_rooms := FireDraw.bodies([_cell(0, 0, 50.0, 1), _cell(1, 0, 50.0, 2)], CELL_M, CEILING_M)
	assert_eq(two_rooms.size(), 2, "방마다 따로")
	# 지금 보이는 불과 기억 속의 불도 따로
	var mixed := FireDraw.bodies([_cell(0, 0, 50.0, 1), _cell(1, 0, 50.0, 1, 0.0, true)], CELL_M, CEILING_M)
	assert_eq(mixed.size(), 2, "보이는 불 · 기억 속의 불")
	assert_eq(mixed.filter(func(f: Dictionary) -> bool: return bool(f.faded)).size(), 1, "기억 속의 불 하나")


func test_satellites_sit_on_far_burning_cells() -> void:
	var cells := _block(0, 0, 4, 4, 60.0)
	var list := FireDraw.bodies(cells, CELL_M, CEILING_M)
	var sats := list.filter(func(f: Dictionary) -> bool: return bool(f.satellite))
	assert_eq(sats.size(), int(FireDraw.num("satellite_count")), "곁불 수")
	var body: Dictionary = _main(list)[0]
	for s: Dictionary in sats:
		assert_true(float(s.height_m) < float(body.height_m), "곁불은 몸통보다 낮다")
		assert_true(s.pos.distance_to(body.pos) * CELL_M >= FireDraw.num("satellite_min_dist_m") - 0.001, "몸통에서 떨어져 있다")
		assert_eq(Vector2(s.pos) - Vector2(s.pos).floor(), Vector2(0.5, 0.5), "타는 칸 가운데")
	# 작은 불에는 곁불이 없다
	assert_eq(FireDraw.bodies(_block(0, 0, 2, 2, 60.0), CELL_M, CEILING_M).size(), 1, "네 칸짜리 불은 하나만")


func test_layout_is_stable() -> void:
	var cells := _block(3, 5, 9, 7, 80.0)
	var a := FireDraw.bodies(cells, CELL_M, CEILING_M)
	var b := FireDraw.bodies(cells, CELL_M, CEILING_M)
	assert_eq(a.size(), b.size(), "같은 수")
	for k in a.size():
		assert_eq([a[k].pos, a[k].kind, a[k].seed], [b[k].pos, b[k].kind, b[k].seed], "같은 입력이면 같은 배치 (%d)" % k)


func test_draw_width_covers_fire_without_big_stretch() -> void:
	var stretch := FireDraw.num("max_stretch")
	for kind in FireDraw.KINDS:
		var natural := 2.0 * float(FireDraw.style().kind_aspect[kind])
		for d: float in [0.3, 1.0, 2.3, 6.0]:
			var w := FireDraw.draw_width_m(kind, 2.0, d)
			assert_true(w >= natural / stretch - 0.001 and w <= natural * stretch + 0.001, "%s · 지름 %.1fm: 제 비율의 %.1f배 안 (%.2f)" % [kind, d, stretch, w])
	assert_true(FireDraw.draw_width_m("m", 1.2, 1.2) >= 1.2, "타는 자리를 덮는다")


## 구운 그림이 있으면 설정의 모양과 맞아야 한다 (그림을 다시 구웠는데 설정을 안 고친 경우를 잡는다)
func test_baked_images_match_style() -> void:
	var meta: Variant = JsonData.load_file("res://art/fx/fx.json")
	assert_true(meta is Dictionary, "art/fx/fx.json")
	for kind in FireDraw.KINDS:
		var m: Dictionary = meta.get("fire_" + kind, {})
		assert_true(not m.is_empty(), "fire_%s 그림 정보" % kind)
		if m.is_empty():
			continue
		assert_true(FileAccess.file_exists("res://art/fx/fire_%s.png" % kind) or ResourceLoader.exists("res://art/fx/fire_%s.png" % kind), "fire_%s.png" % kind)
		var aspect := float(m.width_m) / float(m.height_m)
		assert_true(absf(aspect - float(FireDraw.style().kind_aspect[kind])) < 0.02, "%s 모양 (그림 %.3f / 설정 %.3f)" % [kind, aspect, float(FireDraw.style().kind_aspect[kind])])
		assert_true(int(m.frames) >= 8 and float(m.fps) > 0.0, "%s 장 수·속도" % kind)


## 롤오버 천장 화염 (2단계, 2026-11-25): 플래시오버에 가까울수록 진하다
func test_rollover_strength_grows_toward_flashover() -> void:
	var ramp := FireDraw.num("roll_ramp_c", 100.0)
	assert_eq(FireDraw.rollover_strength(600.0 - ramp, 600.0), 0.0, "롤오버가 막 시작될 때 0")
	assert_true(absf(FireDraw.rollover_strength(600.0 - ramp * 0.5, 600.0) - 0.5) < 0.001, "가운데는 0.5")
	assert_eq(FireDraw.rollover_strength(600.0, 600.0), 1.0, "플래시오버 온도에서 1")
	assert_eq(FireDraw.rollover_strength(900.0, 600.0), 1.0, "넘어도 1")
	assert_eq(FireDraw.rollover_strength(100.0, 600.0), 0.0, "한참 아래는 0")
	var lo := FireDraw.rollover_alpha(0.0)
	var hi := FireDraw.rollover_alpha(1.0)
	assert_true(lo > 0.2 and hi <= 1.0 and hi > lo, "진하기: 처음에도 보이고(%.2f) 갈수록 진하다(%.2f)" % [lo, hi])
	assert_true(FireDraw.rollover_alpha(0.5) > lo and FireDraw.rollover_alpha(0.5) < hi, "가운데는 그 사이")
	# 진해지는 온도 폭은 롤오버 징후가 뜨는 폭(시뮬레이션)과 같아야 처음부터 끝까지 고르게 진해진다
	var hz: Variant = JsonData.load_file("res://data/fire/hazard_params.json")
	assert_eq(ramp, float(hz.rollover_margin_c.value), "roll_ramp_c = rollover_margin_c")


## 구운 롤오버 그림: 위에서 본 화염 판(가로·세로 타일)과 앞면 화염 띠(가로 타일)
func test_baked_rollover_images() -> void:
	var meta: Variant = JsonData.load_file("res://art/fx/fx.json")
	assert_true(meta is Dictionary, "art/fx/fx.json")
	for key: String in ["fire_roll", "fire_rollc"]:
		var m: Dictionary = meta.get(key, {})
		assert_true(not m.is_empty(), "%s 그림 정보" % key)
		if m.is_empty():
			continue
		assert_true(FileAccess.file_exists("res://art/fx/%s.png" % key) or ResourceLoader.exists("res://art/fx/%s.png" % key), "%s.png" % key)
		assert_true(int(m.frames) >= 8 and float(m.fps) > 0.0 and float(m.tile_m) >= 1.0, "%s 장 수·속도·타일 길이" % key)
		assert_true(float(m.mean_alpha) > 0.05 and float(m.mean_alpha) < 0.8, "%s: 화염 사이로 연기가 비친다 (평균 진하기 %.2f)" % [key, float(m.mean_alpha)])
	var band: Dictionary = meta.get("fire_rollc", {})
	if not band.is_empty():
		assert_true(float(band.band_m) > 0.3 and float(band.band_m) <= 1.2, "화염 띠 높이 (m)")
	assert_true(FxArt.load_all() and FxArt.roll_sheet != null and FxArt.roll_curtain != null, "게임이 두 그림을 불러온다")
