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


## 가장 높은 불 (한 덩어리를 여러 그림으로 나눠 세웠을 때의 대표)
func _tallest(list: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = list[0]
	for f in list:
		if float(f.height_m) > float(best.height_m):
			best = f
	return best


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
		var f: Dictionary = _tallest(FireDraw.bodies(_block(0, 0, 4, 4, kw_per_cell), CELL_M, CEILING_M))
		var rank := FireDraw.KINDS.find(str(f.kind))
		assert_true(float(f.height_m) >= last_h, "%.0fkW/칸: 높이가 줄지 않는다 (%.2f)" % [kw_per_cell, float(f.height_m)])
		assert_true(rank >= last_rank, "%.0fkW/칸: 그림이 작아지지 않는다 (%s)" % [kw_per_cell, f.kind])
		last_h = float(f.height_m)
		last_rank = rank
		if not seen.has(str(f.kind)):
			seen.append(str(f.kind))
	assert_eq(seen, ["s", "m", "l", "xl"] as Array[String], "네 크기를 차례로 거친다")


func test_height_is_capped_at_ceiling() -> void:
	var f: Dictionary = _tallest(FireDraw.bodies(_block(0, 0, 4, 4, 300.0), CELL_M, CEILING_M))
	assert_true(absf(float(f.height_m) - CEILING_M) < 0.001, "천장 높이까지만 (%.2f)" % float(f.height_m))
	assert_true(bool(f.capped), "천장에 닿았다는 표시")
	assert_eq(f.kind, "xl", "넓게 타며 천장에 닿으면 불바다 그림")
	# 가구 위에서 타면 남은 높이까지만
	var cells := _block(0, 0, 4, 4, 300.0)
	for c: Dictionary in cells:
		c.base = 0.8
	var on_top: Dictionary = _tallest(FireDraw.bodies(cells, CELL_M, CEILING_M))
	assert_true(absf(float(on_top.base_m) - 0.8) < 0.001, "불 뿌리 = 가구 높이")
	assert_true(absf(float(on_top.height_m) - (CEILING_M - 0.8)) < 0.001, "천장까지 남은 높이 (%.2f)" % float(on_top.height_m))


## 화염 높이는 방 하나의 불 전체로 셈한다: 바둑판 여러 칸에 걸친 불을 조각마다 따로 셈하면 실제보다 낮아진다
func test_height_uses_whole_room_fire() -> void:
	# 4m × 2m 가 60kW/칸으로 탄다 (한 덩어리 — 길어서 그림 몇 개로 나눠 세운다): 전체 1,920kW · 지름 3.19m → 약 1.6m
	var wide := FireDraw.bodies(_block(0, 0, 8, 4, 60.0), CELL_M, CEILING_M)
	assert_true(wide.size() >= 2 and wide.size() <= int(FireDraw.num("cluster_max")), "길게 퍼진 불은 그림 몇 개로 (%d)" % wide.size())
	var whole := FireDraw.flame_height_m(60.0 * 32, FireDraw.diameter_m(32 * CELL_M * CELL_M))
	var alone := FireDraw.flame_height_m(60.0 * 16, FireDraw.diameter_m(16 * CELL_M * CELL_M))
	assert_true(whole > alone, "한 덩어리로 셈한 높이가 더 높다 (%.2f > %.2f)" % [whole, alone])
	for f in wide:
		assert_true(absf(float(f.height_m) - whole) < 0.001, "나눠 세운 그림 모두 덩어리 전체로 셈한 높이 (%.2f)" % float(f.height_m))
	# 센 쪽과 약한 쪽: 약한 쪽이 낮되 weak_ratio 아래로는 내려가지 않는다
	var cells := _block(0, 0, 4, 4, 100.0)
	cells.append_array(_block(4, 0, 4, 4, 10.0))
	var mixed := FireDraw.bodies(cells, CELL_M, CEILING_M)
	var lo := INF
	var hi := 0.0
	for f in mixed:
		lo = minf(lo, float(f.height_m))
		hi = maxf(hi, float(f.height_m))
	assert_true(mixed.size() >= 2 and lo < hi, "약한 쪽이 더 낮다 (%.2f < %.2f)" % [lo, hi])
	assert_true(lo >= hi * FireDraw.num("weak_ratio") - 0.001, "그래도 센 쪽의 %.0f%% 이상" % (FireDraw.num("weak_ratio") * 100.0))
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
	# 전실 화재의 입체감 (2026-11-25): 촘촘한 바둑판(full_tile_m)마다 기둥 하나 — 여러 줄, 높이는 제각각, 뒤는 어둡게
	var per_side := roundi(8 * CELL_M / FireDraw.num("full_tile_m"))
	assert_eq(after.size(), per_side * per_side, "촘촘하게 여러 줄 (%d채)" % after.size())
	assert_true(after.size() > before.size(), "방 전체가 타기 전보다 많다")
	var lo := INF
	var hi := 0.0
	var shades := {}
	var kinds := {}
	for f in after:
		var h := float(f.height_m)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		shades[snappedf(float(f.shade), 0.01)] = true
		assert_true(bool(f.full) and bool(f.capped), "전실 화재의 기둥")
		assert_true(h >= CEILING_M * FireDraw.num("full_reach_min") - 0.001 and h <= CEILING_M * FireDraw.num("full_reach_max") + 0.001, "천장 높이쯤 (%.2f)" % h)
		assert_true(str(f.kind) in ["l", "xl"], "불기둥·불바다 그림 (%s)" % f.kind)
		kinds[str(f.kind)] = true
		assert_true(float(f.width_m) >= FireDraw.num("full_tile_m") * 1.1, "이웃 기둥과 겹친다 (폭 %.2fm)" % float(f.width_m))
	assert_true(hi - lo > 0.2, "높이가 제각각이다 (%.2f ~ %.2f)" % [lo, hi])
	assert_true(hi > CEILING_M, "일부는 천장 위로 솟는다 (%.2f)" % hi)
	assert_true(kinds.has("l"), "혀가 갈라진 불기둥 그림이 섞여 있다 (한 덩어리로 뭉개지지 않게)")
	assert_true(shades.has(0.0) and shades.has(1.0) and shades.size() >= 4, "앞뒤 자리에 따라 음영이 여러 단계 (%d)" % shades.size())
	for f in before:
		assert_true(not bool(f.full) and float(f.shade) == 1.0, "방 전체가 타기 전의 불은 음영 없이")


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
	assert_true(list.size() >= 2 and list.size() <= int(FireDraw.num("cluster_max")), "한 덩어리 — 그림 몇 개로 (%d)" % list.size())
	assert_true(list.size() < cells.size() / 4, "그리는 불꽃이 타는 칸보다 훨씬 적다 (%d < %d칸)" % [list.size(), cells.size()])
	var total := 0.0
	for f in list:
		total += float(f.kw)
		assert_eq(f.kind, "xl", "넓게 세게 타는 불은 불바다 그림")
		assert_true(not bool(f.satellite), "따로 선 곁불은 없다")
	assert_true(absf(total - 120.0 * cells.size()) < 0.01, "열방출률 합은 그대로 (%.0fkW)" % total)
	# 서로 크게 겹친다 (한 불로 보인다): 이웃 그림 사이 거리가 그림 폭보다 짧다
	var sorted := list.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.x < b.pos.x)
	for k in range(1, sorted.size()):
		var gap_m: float = (sorted[k].pos as Vector2).distance_to(sorted[k - 1].pos) * CELL_M
		assert_true(gap_m < float(sorted[k].width_m), "이웃 그림과 겹친다 (거리 %.2fm < 폭 %.2fm)" % [gap_m, float(sorted[k].width_m)])
	# 뒤에서 앞으로 (깊이 순서)
	for k in range(1, list.size()):
		assert_true(list[k].pos.x + list[k].pos.y >= list[k - 1].pos.x + list[k - 1].pos.y, "깊이 순서")


## 불 자리 = 열방출률 무게 중심 (세게 타는 쪽으로 쏠린다)
func test_position_is_heat_weighted() -> void:
	# 붙어 있는 두 칸: 한 덩어리로 묶이고, 자리는 센 칸 쪽으로 쏠린다
	var list := FireDraw.bodies([_cell(0, 0, 10.0), _cell(1, 0, 300.0)], CELL_M, CEILING_M)
	assert_eq(list.size(), 1, "불 하나")
	var f: Dictionary = list[0]
	assert_true(f.pos.x > 1.3, "센 칸 쪽으로 (x = %.2f)" % f.pos.x)
	assert_eq(int(f.cells), 2, "두 칸을 묶음")


func test_rooms_and_remembered_fire_are_kept_apart() -> void:
	# 같은 바둑판 칸 안이라도 방이 다르면 따로 (벽 너머 불과 한 덩어리가 되지 않는다)
	var two_rooms := FireDraw.bodies([_cell(0, 0, 50.0, 1), _cell(1, 0, 50.0, 2)], CELL_M, CEILING_M)
	assert_eq(two_rooms.size(), 2, "방마다 따로")
	# 지금 보이는 불과 기억 속의 불도 따로
	var mixed := FireDraw.bodies([_cell(0, 0, 50.0, 1), _cell(1, 0, 50.0, 1, 0.0, true)], CELL_M, CEILING_M)
	assert_eq(mixed.size(), 2, "보이는 불 · 기억 속의 불")
	assert_eq(mixed.filter(func(f: Dictionary) -> bool: return bool(f.faded)).size(), 1, "기억 속의 불 하나")


## 붙어 있는 불은 하나로 (2026-11-25 사용자: 한 칸의 불이 다음 칸으로 가면 합쳐져서 더 크게 보여야 한다)
func test_adjacent_fire_merges_and_grows() -> void:
	# 한 칸 → 옆 칸으로 번짐 → 더 번짐: 불은 늘 하나이고 점점 크다
	var last_h := 0.0
	var last_w := 0.0
	for n: int in [1, 2, 4]:
		var cells: Array = []
		for k in n:
			cells.append(_cell(5 + k % 2, 5 + k / 2, 60.0))
		var list := FireDraw.bodies(cells, CELL_M, CEILING_M)
		assert_eq(list.size(), 1, "%d칸이 타도 불은 하나" % n)
		assert_eq(int(list[0].cells), n, "그 칸들을 다 묶었다")
		assert_true(float(list[0].height_m) >= last_h and float(list[0].width_m) >= last_w, "번질수록 커진다 (%d칸: 높이 %.2f · 폭 %.2f)" % [n, float(list[0].height_m), float(list[0].width_m)])
		last_h = float(list[0].height_m)
		last_w = float(list[0].width_m)
	assert_true(last_h > FireDraw.num("min_height_m"), "네 칸이면 갓 붙은 불보다 높다")
	# 가구 사이 빈 바닥 한 칸을 건너뛴 불도 한 덩어리 (merge_gap_m 안)
	var gap_cells := maxi(1, roundi(FireDraw.num("merge_gap_m") / CELL_M))
	var two := FireDraw.diameter_m(2 * CELL_M * CELL_M)
	var one := FireDraw.diameter_m(CELL_M * CELL_M)
	var near := FireDraw.bodies([_cell(0, 0, 60.0), _cell(gap_cells, 0, 60.0)], CELL_M, CEILING_M)
	for f in near:
		assert_true(absf(float(f.diameter_m) - two) < 0.001, "%d칸 떨어진 불은 한 덩어리로 셈한다" % gap_cells)
	# 멀리 떨어진 불은 따로
	var far := FireDraw.bodies([_cell(0, 0, 60.0), _cell(gap_cells + 3, 0, 60.0)], CELL_M, CEILING_M)
	assert_eq(far.size(), 2, "멀리 떨어진 불은 따로")
	for f in far:
		assert_true(absf(float(f.diameter_m) - one) < 0.001, "저마다 한 칸짜리 불")
	# 따로 선 작은 곁불은 없다
	for f in FireDraw.bodies(_block(0, 0, 4, 4, 60.0), CELL_M, CEILING_M):
		assert_true(not bool(f.satellite), "곁불 없음")
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


## 플래시오버 전이 (3단계, 2026-11-25): 플래시오버 순간부터 flash_surge_s 동안 0 → 1, 처음에 빠르다
func test_flash_progress() -> void:
	var s := FireDraw.num("flash_surge_s", 3.0)
	assert_true(s >= 1.0 and s <= 10.0, "전이 시간 (%.1f초)" % s)
	assert_eq(FireDraw.flash_progress(0.0), 0.0, "플래시오버 순간 0")
	assert_eq(FireDraw.flash_progress(s), 1.0, "전이가 끝나면 1")
	assert_eq(FireDraw.flash_progress(s * 10.0), 1.0, "그 뒤로도 1")
	assert_eq(FireDraw.flash_progress(INF), 1.0, "플래시오버 시각을 모르면 다 끝난 것으로")
	var half := FireDraw.flash_progress(s * 0.5)
	assert_true(half > 0.5 and half < 1.0, "처음에 빠르다 (절반 시간에 %.2f)" % half)
	assert_true(FireDraw.flash_progress(s * 0.25) < half, "시간이 갈수록 커진다")
	# 전실 화재의 진하기: 처음부터 보이고, 방 안이 조금 비친다
	# 전실 화재: 천장 화염은 옅게 깔아 불기둥 끝이 비치고, 연기 상자는 옅게 한다 (2026-11-25 — 상자에 그림을 바른 것처럼 보이지 않게)
	assert_true(FireDraw.num("full_sheet_alpha") > 0.3 and FireDraw.num("full_sheet_alpha") < 0.8, "천장 화염은 옅게 깔린다")
	assert_true(FireDraw.num("full_smoke_cut") > 0.4 and FireDraw.num("full_smoke_cut") < 1.0, "연기 상자를 옅게 하되 없애지는 않는다")
	assert_true(FireDraw.num("surge_start_ratio") > 0.3 and FireDraw.num("surge_start_ratio") < 1.0, "플래시오버 순간 기둥은 낮게 시작한다")
	assert_true(FireDraw.num("roll_feather_m") >= 0.5, "천장 화염 가장자리는 흐려진다")
	var back: Array = FireDraw.style().get("full_back_tint", [])
	assert_true(back.size() == 3 and float(back[0]) > float(back[1]) and float(back[1]) >= float(back[2]) and float(back[0]) < 1.0, "뒤 줄은 어둡고 붉게")
	assert_true(FireDraw.num("full_glow_ratio") >= FireDraw.num("roll_glow_ratio"), "불빛 번짐도 롤오버보다 넓다")


## 구운 화염 벽 그림: 바닥에서 천장까지 (가로 타일)
func test_baked_fire_wall_image() -> void:
	var meta: Variant = JsonData.load_file("res://art/fx/fx.json")
	var m: Dictionary = meta.get("fire_wall", {}) if meta is Dictionary else {}
	assert_true(not m.is_empty(), "fire_wall 그림 정보")
	if m.is_empty():
		return
	assert_true(FileAccess.file_exists("res://art/fx/fire_wall.png") or ResourceLoader.exists("res://art/fx/fire_wall.png"), "fire_wall.png")
	assert_true(int(m.frames) >= 8 and float(m.fps) > 0.0 and float(m.tile_m) >= 2.0, "장 수·속도·타일 길이")
	assert_true(float(m.height_m) >= 2.0, "방 높이를 채운다 (%.1fm)" % float(m.height_m))
	assert_true(float(m.mean_alpha) > 0.4, "방 전체가 타는 모습 — 롤오버 띠보다 빽빽하다 (평균 진하기 %.2f)" % float(m.mean_alpha))
	assert_true(FxArt.load_all() and FxArt.fire_wall != null, "게임이 그림을 불러온다")


## 창·문 밖 분출 화염 (4단계, 2026-11-25): 세기는 방의 상태로 — 성장기 < 롤오버 < 플래시오버 뒤, 식으면 줄어든다
func test_vent_strength_follows_room_state() -> void:
	var low := FireDraw.num("vent_growth_k")
	var roll := FireDraw.num("vent_roll_k")
	assert_true(low > 0.0 and low < roll and roll < 1.0, "성장기 %.2f < 롤오버 %.2f < 1" % [low, roll])
	assert_eq(FireDraw.vent_strength(false, false, 300.0, 600.0), low, "성장기의 불: 작은 불꽃")
	assert_eq(FireDraw.vent_strength(false, true, 500.0, 600.0), low, "롤오버가 막 시작될 때는 성장기와 같다")
	assert_true(absf(FireDraw.vent_strength(false, true, 600.0, 600.0) - roll) < 0.001, "플래시오버 직전의 롤오버")
	assert_eq(FireDraw.vent_strength(true, false, 700.0, 600.0), 1.0, "플래시오버 뒤 전실 화재: 가장 세다")
	var cooling := FireDraw.vent_strength(true, false, 550.0, 600.0)
	assert_true(cooling < 1.0 and cooling > low, "식으면 줄어든다 (%.2f)" % cooling)
	assert_eq(FireDraw.vent_strength(true, false, 100.0, 600.0), low, "타는 동안은 성장기 아래로 내려가지 않는다")
	assert_true(FireDraw.vent_rise_m(1.0) > FireDraw.vent_rise_m(low) and FireDraw.vent_rise_m(low) > 0.2, "셀수록 높이 솟는다 (%.1fm → %.1fm)" % [FireDraw.vent_rise_m(low), FireDraw.vent_rise_m(1.0)])
	assert_true(FireDraw.vent_rise_m(1.0) >= 2.0, "전실 화재는 한 층 높이쯤 솟는다")


## 어느 개구부에서 뿜는가: 타는 방의 열린 문·깨진 창. 방 사이 문은 롤오버·플래시오버 뒤에만
func test_flame_vents_pick_open_openings_of_burning_room() -> void:
	var sim := make_sim()
	var living := sim.fire.compartment_at(1, 12, 16)
	assert_true(living != null, "거실")
	if living == null:
		return
	assert_eq(FloorLayer.flame_vents(sim, 1).size(), 0, "타는 방이 없으면 없다")
	# 성장기: 타고 있고 연기층이 인방 아래로 내려왔다 (모든 문은 열려 있다 — make_sim)
	living.q_potential = 800.0
	living.layer_depth = living.height - 0.8
	living.t_upper = 300.0
	assert_eq(FloorLayer.flame_vents(sim, 1).size(), 0, "성장기의 불은 개구부로 뿜지 않는다 (연기만 나온다)")
	# 롤오버 징후: 열린 문 위로 넘실댄다 (닫힌·안 깨진 창에서는 아니다)
	living.rollover = true
	living.t_upper = living.flashover_temp - 20.0
	var roll := FloorLayer.flame_vents(sim, 1)
	assert_true(not roll.is_empty(), "롤오버: 열린 문에서 뿜는다")
	for v: Array in roll:
		assert_eq(int(v[5]), living.index, "뿜는 방은 거실")
		assert_true(float(v[1]) > FireDraw.num("vent_growth_k") and float(v[1]) <= FireDraw.num("vent_roll_k") + 0.001, "롤오버 세기 (%.2f)" % float(v[1]))
		assert_true(not bool(v[8]), "닫힌(안 깨진) 창에서는 뿜지 않는다")
	living.rollover = false
	# 플래시오버 뒤: 방 사이 문으로도 뿜고, 깨진 창에서도 뿜는다
	living.flashed = true
	living.t_upper = living.flashover_temp + 50.0
	var window: Opening = null
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.WINDOW and o.level == 1 and o.room_a == living.index and o.room_b == Opening.OUTSIDE:
			window = o
			break
	assert_true(window != null, "거실의 바깥 창")
	if window != null:
		window.broken = true
		window.is_open = true
	var full := FloorLayer.flame_vents(sim, 1)
	var inner := full.filter(func(v: Array) -> bool: return bool(v[4]))
	var windows := full.filter(func(v: Array) -> bool: return bool(v[8]))
	assert_true(not inner.is_empty(), "전실 화재: 열린 방 사이 문으로 옆 방에 뿜는다")
	assert_eq(windows.size(), 1, "깨진 창 하나에서 뿜는다")
	for v: Array in full:
		assert_eq([int(v[5]), float(v[1])], [living.index, 1.0], "뿜는 방은 거실, 세기 1")
		var dir: Vector2 = v[2]
		var out_cell := Vector2i((v[0] as Vector2 + dir).floor())
		assert_true(sim.fire.compartment_at(1, out_cell.x, out_cell.y) != living, "방 밖으로 뿜는다 (%s → %s)" % [v[0], dir])
	# 문을 닫으면 그 문에서는 뿜지 않는다
	var n := full.size()
	for o in sim.fire.openings:
		if o.kind == Opening.Kind.DOOR and o.level == 1 and (o.room_a == living.index or o.room_b == living.index):
			o.is_open = false
	assert_eq(FloorLayer.flame_vents(sim, 1).size(), 1, "문을 다 닫으면 깨진 창만 남는다 (%d → 1)" % n)


## 구운 분출 화염 그림: 옆에서 본 모습 (왼쪽 = 벽, 아래에서 lintel_m = 개구부 윗면) — 밖으로 뿜어 나와 위로 말려 오른다
func test_baked_vent_image() -> void:
	var meta: Variant = JsonData.load_file("res://art/fx/fx.json")
	var m: Dictionary = meta.get("fire_vent", {}) if meta is Dictionary else {}
	assert_true(not m.is_empty(), "fire_vent 그림 정보")
	if m.is_empty():
		return
	assert_true(FileAccess.file_exists("res://art/fx/fire_vent.png") or ResourceLoader.exists("res://art/fx/fire_vent.png"), "fire_vent.png")
	assert_true(int(m.frames) >= 8 and float(m.fps) > 0.0, "장 수·속도")
	assert_true(float(m.width_m) >= 1.0, "벽에서 밖으로 1m 넘게 뻗는다 (%.2fm)" % float(m.width_m))
	assert_true(float(m.lintel_m) > 0.3 and float(m.height_m) - float(m.lintel_m) >= 1.5, "개구부 윗면 위로 솟는 높이가 있다")
	assert_true(FxArt.load_all() and FxArt.fire_vent != null, "게임이 그림을 불러온다")
	assert_true(FireDraw.num("vent_sheet_gap_m") > 0.2, "개구부 폭에 걸쳐 여러 장")
