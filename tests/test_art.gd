extends TestSuite
## P15: 구운 그림 연결 (data/art.json → res://art/sprites). 묶음·동작·방향이 다 있고, 게임 대상이 빠짐없이 연결되며, 메모리가 저사양 기준 안인지.

const CREW_ANIMS := ["idle", "walk", "crouch_walk", "spray", "search", "down", "force_a", "force_b", "lift_f", "lift_b", "drag"]
## 그림 텍스처 상한 (MB, 게임 설정값). 저사양 목표는 48MB(docs/perf.md)지만, 2026-11-15 사용자 결정: 행동을 모두 먼저 만들고
## 프레임 수는 나중에 줄인다 (docs/motions.md) — 그때까지 넉넉히 둔다
const TEXTURE_BUDGET_MB := 128.0


func _sets_in_config() -> Array[String]:
	var c := SpriteArt.config()
	var out: Array[String] = [str(c.crew), str(c.commander), str(c.witness), str(c.victims.male), str(c.victims.female)]
	for t: String in c.vehicles:
		out.append(str(c.vehicles[t]))
	for n: String in c.furniture.names:
		out.append(str(c.furniture.names[n]))
	for kw: Array in c.furniture.keywords:
		out.append(str(kw[1]))
	return out


func test_all_sets_load_with_every_direction() -> void:
	assert_true(SpriteArt.enabled(), "그림 켜짐")
	var bytes := 0
	var seen := {}
	var t0 := Time.get_ticks_msec()
	for id in _sets_in_config():
		if seen.has(id):
			continue
		seen[id] = true
		var s := SpriteArt.get_set(id)
		assert_true(s != null, "묶음 %s 불러옴" % id)
		if s == null:
			continue
		for tex in s.pages:
			bytes += tex.get_width() * tex.get_height() * 4
		for anim: String in s.anims:
			var a: Dictionary = s.anims[anim]
			assert_eq(a.cells.size(), s.directions * int(a.frames), "%s %s: 방향 %d × 프레임 %d" % [id, anim, s.directions, int(a.frames)])
	var mb := bytes / 1048576.0
	print("    그림 묶음 %d개, 텍스처 %.1f MB, 불러오기 %d ms" % [seen.size(), mb, Time.get_ticks_msec() - t0])
	assert_true(mb < TEXTURE_BUDGET_MB, "텍스처 %.1f MB < %.0f MB" % [mb, TEXTURE_BUDGET_MB])


func test_crew_has_every_action_and_helmet_layer() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	for anim in CREW_ANIMS:
		assert_true(s.has(anim), "대원 동작 %s (기획안 9-4-1)" % anim)
	assert_eq(s.directions, 8, "8방향")
	assert_eq(s.anims.idle.stripe.size(), s.anims.idle.cells.size(), "헬멧 색 층이 프레임마다 (출동대 종류 색)")


func test_helmet_color_by_squad_type_only() -> void:
	# 사용자 결정 (2026-11-11): 진압 검정 · 구조 주황 · 구급 흰색, 헬멧 색으로만 구분
	var fire := SpriteArt.helmet_color("진압대")
	var rescue := SpriteArt.helmet_color("구조대")
	var ems := SpriteArt.helmet_color("구급대")
	assert_true(fire.get_luminance() < 0.3, "진압대 = 검정")
	assert_true(rescue.r > 0.9 and rescue.g > 0.35 and rescue.g < 0.65 and rescue.b < 0.3, "구조대 = 주황")
	assert_true(ems.get_luminance() > 0.9, "구급대 = 흰색")
	assert_eq(SpriteArt.helmet_color("굴절차·고가사다리차"), fire, "그 밖의 출동대는 진압(검정)")
	assert_eq(SpriteArt.helmet_color("RIT"), fire, "RIT는 임무 — 헬멧 색 없음 (이름표)")
	var cmd := SpriteArt.helmet_color("지휘")
	assert_true(cmd.b > 0.8 and cmd.b > cmd.r + 0.4, "현장지휘관 = 파랑 (사용자 결정)")


func test_every_vehicle_and_furniture_is_linked() -> void:
	var vehicles: Dictionary = JsonData.load_file("res://data/units/vehicles.json")
	for type: String in vehicles:
		if type == "note":
			continue
		assert_true(SpriteArt.vehicle_set(type) != null, "차량 %s 그림" % type)
	# 아파트 집기 세트와 건물 파일의 가구 이름 (벽처럼 그림이 필요 없는 것은 뺀다)
	var skip := ["샌드위치패널 내벽"]
	var names := {}
	for f in DirAccess.get_files_at("res://data/furnishings"):
		var d: Dictionary = JsonData.load_file("res://data/furnishings/" + f)
		for k: String in d.sets:
			for it: Dictionary in d.sets[k].items:
				names[str(it.name)] = true
	for f in DirAccess.get_files_at("res://data/buildings"):
		if not f.ends_with(".json"):
			continue
		var b := BuildingData.from_file("res://data/buildings/" + f)
		if b == null:
			continue
		for lv in b.levels():
			for it in b.furniture(lv):
				names[str(it.name)] = true
	var missing: Array[String] = []
	for n: String in names:
		if not n in skip and SpriteArt.furniture_set(n) == null:
			missing.append(n)
	assert_eq(missing.size(), 0, "그림이 없는 가구: %s" % [missing])


func test_direction_and_credits() -> void:
	assert_eq(SpriteArt.dir8(Vector2(1, 0)), 0, "+x = 0")
	assert_eq(SpriteArt.dir8(Vector2(0, 1)), 2, "+y = 2")
	assert_eq(SpriteArt.dir8(Vector2(-1, -1)), 5, "-x-y = 5 (화면 위쪽)")
	var c: Dictionary = JsonData.load_file("res://data/credits.json")
	assert_true(" ".join(c.lines).contains("Kenney (kenney.nl), CC0"), "자료 출처에 Kenney CC0")


func test_fx_puffs_include_fire_and_flash() -> void:
	assert_true(FxArt.load_all(), "불꽃 그림 불러옴")
	var rows: Array = FxArt.meta.get("puffs", {}).get("rows", [])
	assert_eq(rows.size(), 4, "덩어리 그림 4줄: 검은 연기·흰 김·불덩이·섬광 (Kenney Smoke Particles)")
	assert_eq(FxArt.puffs.get_height(), int(FxArt.meta.puffs.size) * 4, "puffs.png 높이 = 4줄")
	var ci := Node2D.new()
	assert_true(not FxArt.draw_puff(ci, Vector2.ZERO, 10.0, 9, 0, Color.WHITE), "없는 종류는 false (도형으로 대체)")
	ci.free()


func test_fx_smoke_curtain_flipbook() -> void:
	# F04 (2026-11-12): Blender로 구운 연기층 앞면 커튼 (tools/blender/smoke_fx.py)
	assert_true(FxArt.load_all(), "불꽃 그림 불러옴")
	assert_true(FxArt.curtain != null, "smoke_curtain.png 있음")
	var m: Dictionary = FxArt.meta.get("smoke_curtain", {})
	assert_eq(FxArt.curtain.get_height(), int(m.h) * int(m.frames), "장을 세로로 쌓은 높이 = 장 높이 × 장 수")
	assert_eq(FxArt.curtain.get_width(), int(m.w), "가로 한 장")
	assert_true(float(m.body_v) > 0.5 and float(m.body_v) < 1.0, "연기층 아랫면은 그림 아래쪽, 그 아래는 말려 내려오는 가장자리")


func test_photo_trucks_have_drive_animation() -> void:
	# 2026-11-12 사용자 결정: 참고 그림으로 만든 소방차 3종은 달릴 때 바퀴가 도는 동작이 있다 (없는 차량은 서 있는 그림 그대로)
	for type: String in ["펌프차", "물탱크차", "구조공작차"]:
		var art := SpriteArt.vehicle_set(type)
		assert_true(art != null, "%s 그림 있음" % type)
		assert_true(art.frames("idle") == 1 and art.frames("drive") >= 2, "%s: 서 있는 그림 1장 + 달리는 동작 여러 장" % type)
	assert_eq(SpriteArt.vehicle_set("구급차").frames("drive"), 0, "구급차는 달리는 동작 없음 (서 있는 그림으로)")
	assert_true(float(SpriteArt.config().get("fps", {}).get("drive", 0.0)) > 0.0, "달리는 동작 속도")
	# 깜박이는 경광등 불빛은 그림의 경광등 막대 위에 (예전 모델 위치 0.3으로 두면 막대 뒤에 뜬다)
	var bars: Dictionary = SpriteArt.config().get("vehicle_lightbar", {})
	for type: String in ["펌프차", "물탱크차", "구조공작차"]:
		assert_true(float(bars[type].forward) > 0.35 and float(bars[type].h_m) < 3.2, "%s 경광등 불빛 위치" % type)


func test_fx_smoke_sheet_plume_spill_flipbooks() -> void:
	# F04 (2026-11-12): 연기층 윗면·불에서 솟는 기둥·개구부 넘침 (tools/blender/smoke_fx.py)
	assert_true(FxArt.load_all(), "불꽃 그림 불러옴")
	for pair: Array in [[FxArt.sheet, "smoke_sheet"], [FxArt.plume, "smoke_plume"], [FxArt.spill, "smoke_spill"]]:
		var tex: Texture2D = pair[0]
		assert_true(tex != null, "%s.png 있음" % pair[1])
		var m: Dictionary = FxArt.meta.get(pair[1], {})
		assert_eq(tex.get_height(), int(m.h) * int(m.frames), "%s: 장을 세로로 쌓은 높이" % pair[1])
		assert_eq(tex.get_width(), int(m.w), "%s: 가로 한 장" % pair[1])
	assert_true(float(FxArt.meta.smoke_spill.lintel_v) > 0.5, "넘침 그림의 인방은 아래쪽 (그 위로 솟는다)")
	var ci := Node2D.new()
	assert_true(not FxArt.draw_flip(ci, null, "smoke_sheet", PackedVector2Array(), Vector2.ZERO, Vector2.ONE, Color.WHITE, 0), "그림이 없으면 false")
	ci.free()


func test_fx_water_stream_art() -> void:
	# 2026-11-12 사용자 결정: 방수하면 참고 그림의 물줄기가 나간다 — 직사(줄기·튀는 물), 분무(원뿔·물안개)
	assert_true(FxArt.load_all(), "불꽃 그림 불러옴")
	for tex: Texture2D in [FxArt.water_jet, FxArt.water_splash, FxArt.water_fog, FxArt.water_fog_splash]:
		assert_true(tex != null and tex.get_width() >= 128, "물줄기 그림 있음")
	assert_true(FxArt.water_jet.get_width() > FxArt.water_jet.get_height() * 2, "직사 줄기는 가로로 긴 그림 (왼쪽 = 관창)")
	var ci := Node2D.new()
	assert_true(FxArt.draw_water(ci, Vector2.ZERO, Vector2(120, 40), true, 0.0, Color.WHITE, 1), "직사 그리기")
	assert_true(FxArt.draw_water(ci, Vector2.ZERO, Vector2(120, 40), false, 30.0, Color.WHITE, 1), "분무 그리기")
	ci.free()


func test_nozzle_tip_recorded_for_spray_pose() -> void:
	# 2026-11-12 사용자 지적: 물줄기는 관창수 몸이 아니라 관창 끝에서 나간다 — 방수 자세의 방향·장마다 관창 끝 위치가 구워져 있다
	var art := SpriteArt.get_set(str(SpriteArt.config().get("crew", "")))
	assert_true(art != null and art.frames("spray") > 0, "대원 방수 그림")
	var seen := {}
	for dir in 8:
		for f in art.frames("spray"):
			var off := art.nozzle_offset("spray", dir, f, Vector2(999, 999))
			assert_true(off != Vector2(999, 999), "방향 %d 장 %d: 관창 끝 위치 있음" % [dir, f])
			# 카메라 쪽·반대쪽을 볼 때는 관창이 화면에서 짧게 보여 기준점 가까이에 온다
			assert_true(off.length() < 120.0, "관창 끝은 팔 길이 안 (%s)" % off)
			seen[dir] = off
	assert_true(seen[0].x > 20.0 and seen[4].x < -20.0, "옆을 볼 때 관창 끝은 몸 밖, 방향에 따라 반대쪽으로")
	assert_eq(art.nozzle_offset("idle", 0, 0, Vector2(1, 2)), Vector2(1, 2), "기록이 없는 동작은 기본값")


# --- 2026-11-15: 문 개방·운반 동작과 물줄기 굵기 (사용자 참고 그림·구조 교재 제4편 제2장 구출 및 운반) ---

func test_new_actions_baked() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	for anim in ["force_a", "force_b", "lift_f", "lift_b", "drag"]:
		assert_true(s.frames(anim) >= 6, "%s: 움직이는 동작 (%d장)" % [anim, s.frames(anim)])
		assert_true(float(SpriteArt.config().fps.get(anim, 0.0)) > 0.0, "%s: 프레임 속도 설정" % anim)
	# 방수: 관창 끝 자리가 방향·프레임마다 기록되어 있다 (물줄기가 거기서 시작한다)
	for k in s.directions:
		for i in s.frames("spray"):
			assert_true(s.nozzle_offset("spray", k, i, Vector2(-999, -999)) != Vector2(-999, -999), "방수 %d방향 %d장: 관창 끝 자리" % [k, i])
	# 누운 구조대상자 그림 (운반·끌기 때 쓴다)
	for key in ["male", "female"]:
		assert_true(SpriteArt.get_set(str(SpriteArt.config().victims[key])).frames("down_up") >= 1, "구조대상자(%s) 누운 그림" % key)


func test_carry_layout_spots() -> void:
	var cfg: Dictionary = SpriteArt.config().carry_layout
	assert_true(str(cfg.get("_source", "")) != "", "운반 배치 설정에 source")
	var lead := Vector2(20.5, 30.5)
	var dir := Vector2.RIGHT
	# 2인 운반(사지운반법): 조장이 앞, 짝이 뒤(사람 몸길이만큼), 옮겨지는 사람은 그 사이에 들려 있다
	var lift := FloorLayer.carry_spots("lift", lead, dir, cfg)
	assert_true((lift.partner as Vector2).x < lead.x - 2.0 and is_equal_approx((lift.partner as Vector2).y, lead.y), "뒷사람은 가는 방향의 뒤")
	assert_true((lift.victim as Vector2).is_equal_approx(lead.lerp(lift.partner, 0.5)), "옮겨지는 사람은 두 사람 가운데")
	assert_true(float(lift.victim_h) >= 0.4 and float(lift.victim_h) <= 0.9, "허리 아래 높이로 든다 (%.2fm)" % float(lift.victim_h))
	# 1인 운반(끌기): 끌려가는 사람은 뒤 바닥에, 짝은 앞에서 길을 살핀다
	var drag := FloorLayer.carry_spots("drag", lead, dir, cfg)
	assert_true((drag.victim as Vector2).x < lead.x - 1.0 and float(drag.victim_h) < 0.2, "끌려가는 사람은 뒤 바닥")
	assert_true((drag.partner as Vector2).x > lead.x + 1.0, "짝은 앞")
	# 방식: 선 자세·두 사람 = 2인 운반 / 낮은 자세(연기층 아래)·혼자 = 끌기
	var sim := SimWorld.from_scenario(DEV_SCENARIO_PATH)
	var crew := sim.units.crews[0]
	crew.leader.crouched = false
	assert_eq(FloorLayer.carry_mode(crew), "lift", "선 자세로 갈 수 있으면 2인 운반")
	crew.leader.crouched = true
	assert_eq(FloorLayer.carry_mode(crew), "drag", "낮은 자세면 끌기")
	crew.leader.crouched = false
	crew.partner.incapacitated = true
	assert_eq(FloorLayer.carry_mode(crew), "drag", "짝이 없으면 혼자 끈다")


func test_water_jet_starts_at_nozzle_width() -> void:
	var cfg: Dictionary = SpriteArt.config().water_jet
	assert_true(str(cfg.get("_source", "")) != "", "물줄기 굵기 설정에 source")
	var mouth_px := float(cfg.mouth_m) * IsoProjection.PX_PER_M
	var end_px := float(cfg.end_m) * IsoProjection.PX_PER_M
	assert_true(mouth_px >= 3.0 and mouth_px <= 7.0, "관창 입 굵기 = 관창 그림 굵기 (%.1fpx)" % mouth_px)
	assert_true(end_px > mouth_px * 2.0 and end_px <= 30.0, "맞는 곳에서 퍼지되 지나치게 굵지 않다 (%.1fpx)" % end_px)


## A1 문 개방 (2026-11-15 사용자가 블렌더에서 확인): 두 대원이 문틈 양쪽에 서서 빠루를 문틈에 넣고 번갈아 젖힌다
func test_door_force_two_sides() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	var a := s.stand("force_a")
	var b := s.stand("force_b")
	assert_true(not a.is_empty() and not b.is_empty(), "두 사람의 서는 자리가 구울 때 적혀 있다")
	assert_true(float(a.right_m) * float(b.right_m) < 0.0, "문틈 양쪽 (오른쪽 %.2f / %.2f)" % [float(a.right_m), float(b.right_m)])
	assert_true(float(a.fwd_m) < 0.0 and float(b.fwd_m) < 0.0, "문 앞에 선다 (문틈보다 뒤)")
	assert_eq(s.frames("force_a"), s.frames("force_b"), "두 사람 프레임 수가 같다 (번갈아 젖힌다)")
	# 배치: 문이 가로(칸 두 개가 x로)면 보는 방향은 y, 대원이 있는 쪽에서 문을 본다
	var o := Opening.new()
	o.cells = [Vector2i(10, 20), Vector2i(11, 20)] as Array[Vector2i]
	var fr := FloorLayer.force_frame(o, Vector2(11.0, 24.0))
	assert_eq([fr.facing, fr.k], [Vector2(0, -1), 6], "아래(+y)에서 위의 문을 본다")
	assert_true((fr.seam as Vector2).is_equal_approx(Vector2(11.0, 21.0)), "문틈 = 문 가운데, 대원 쪽 벽면 (%s)" % fr.seam)
	var pa := FloorLayer.stand_spot(fr.seam, fr.facing, a, 0.5)
	var pb := FloorLayer.stand_spot(fr.seam, fr.facing, b, 0.5)
	assert_true(pa.y > 21.0 and pb.y > 21.0, "둘 다 문 앞(대원 쪽)")
	assert_true((pa.x - 11.0) * (pb.x - 11.0) < 0.0 and absf(pa.x - pb.x) > 1.5, "문틈 양쪽으로 갈라 선다 (%.1f / %.1f)" % [pa.x, pb.x])
	# 문이 한 칸이면 대원이 있는 쪽에서 축 방향으로
	var one := Opening.new()
	one.cells = [Vector2i(5, 5)] as Array[Vector2i]
	assert_eq(FloorLayer.force_frame(one, Vector2(2.5, 5.8)).facing, Vector2(1, 0), "왼쪽에서 오른쪽 문을 본다")


## A2 2인 운반 (2026-11-15 사용자가 블렌더에서 확인): 앞사람(조장)·뒷사람(짝)·구조대상자를 한 장면으로 구웠다
func test_two_person_carry_baked_together() -> void:
	var crew := SpriteArt.get_set(str(SpriteArt.config().crew))
	assert_true(crew.frames("lift_f") >= 16 and crew.frames("lift_f") == crew.frames("lift_b"), "앞·뒷사람 같은 장 수 (부드럽게 16장)")
	var b := crew.stand("lift_b")
	assert_true(not b.is_empty() and float(b.fwd_m) < -0.5 and absf(float(b.right_m)) < 0.05, "뒷사람은 앞사람 바로 뒤 (%.2fm)" % float(b.get("fwd_m", 0.0)))
	for key in ["male", "female"]:
		var v := SpriteArt.get_set(str(SpriteArt.config().victims[key]))
		assert_eq(v.frames("lift_v"), crew.frames("lift_f"), "구조대상자(%s) 들린 그림 — 같은 장 수" % key)
		var s := v.stand("lift_v")
		assert_true(float(s.fwd_m) < 0.0 and float(s.fwd_m) > float(b.fwd_m), "구조대상자(%s)는 두 사람 사이" % key)
	for anim in ["lift_f", "lift_b", "lift_v"]:
		assert_true(float(SpriteArt.config().fps.get(anim, 0.0)) >= 8.0, "%s: 부드럽게 (초당 장 수)" % anim)
	assert_true(FloorLayer.PAIRED_ANIMS.has("lift_f") and FloorLayer.PAIRED_ANIMS.has("lift_b"), "두 사람은 같은 박자로")


## A3 1인 운반 = 끌기 (2026-11-15 사용자가 블렌더에서 확인): 대원 + 끌려가는 구조대상자를 한 장면으로 구웠다
func test_drag_baked_together() -> void:
	var crew := SpriteArt.get_set(str(SpriteArt.config().crew))
	assert_true(crew.frames("drag") >= 16, "끌기 16장 (%d)" % crew.frames("drag"))
	for key in ["male", "female"]:
		var v := SpriteArt.get_set(str(SpriteArt.config().victims[key]))
		assert_eq(v.frames("drag_v"), crew.frames("drag"), "구조대상자(%s) 끌려가는 그림 — 같은 장 수" % key)
		var s := v.stand("drag_v")
		assert_true(float(s.fwd_m) > 0.4 and absf(float(s.right_m)) < 0.05, "구조대상자(%s)는 대원이 보는 쪽 바닥에 (%.2fm)" % [key, float(s.get("fwd_m", 0.0))])
	assert_true(float(SpriteArt.config().fps.get("drag", 0.0)) >= 10.0, "걸음 빠르기 (사용자 확인: 한 주기 약 1.3초)")


## A4 방수(서서) (2026-11-15 사용자가 블렌더에서 확인): 관창수 + 관창보조 (2인) / 관창보조1·2 (분대)
func test_spray_team_baked() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	for anim in ["spray_n", "spray_h", "spray_h1", "spray_h2"]:
		assert_eq(s.frames(anim), 12, "%s 12장" % anim)
	# 관창 끝 자리: 방향·프레임마다 (물줄기가 거기서 시작한다)
	for k in s.directions:
		for i in s.frames("spray_n"):
			assert_true(s.nozzle_offset("spray_n", k, i, Vector2(-999, -999)) != Vector2(-999, -999), "관창 끝 %d방향 %d장" % [k, i])
	# 관창보조는 관창수 뒤에 일직선으로 (2인 = 한 명, 분대 = 두 명)
	var h := s.stand("spray_h")
	var h1 := s.stand("spray_h1")
	var h2 := s.stand("spray_h2")
	assert_true(float(h.fwd_m) < -0.5 and float(h1.fwd_m) < -0.5, "관창보조는 관창수 뒤")
	assert_true(float(h2.fwd_m) < float(h1.fwd_m) - 0.6, "관창보조2는 관창보조1 뒤 (%.2f / %.2f)" % [float(h2.fwd_m), float(h1.fwd_m)])
	assert_true(absf(float(h1.right_m)) < 0.5 and absf(float(h2.right_m)) < 0.5, "옆으로 크게 벗어나지 않는다 (호스가 일직선)")


## A5 방수(낮은 자세) (2026-11-15 사용자가 블렌더에서 확인): 모두 무릎을 꿇고 호스를 겨드랑이에 낀다 — 2인 / 분대
func test_spray_low_team_baked() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	for anim in ["spray_ln", "spray_lh", "spray_lh1", "spray_lh2"]:
		assert_eq(s.frames(anim), 12, "%s 12장" % anim)
	for k in s.directions:
		assert_true(s.nozzle_offset("spray_ln", k, 0, Vector2(-999, -999)) != Vector2(-999, -999), "낮은 자세 관창 끝 %d방향" % k)
	# 관창 끝이 서서 쏠 때보다 낮다 (화면 위쪽이 음수)
	var low := s.nozzle_offset("spray_ln", 2, 0, Vector2.ZERO)
	var high := s.nozzle_offset("spray_n", 2, 0, Vector2.ZERO)
	assert_true(low.y > high.y, "낮은 자세 관창이 더 낮다 (%.1f / %.1f)" % [low.y, high.y])
	var h1 := s.stand("spray_lh1")
	var h2 := s.stand("spray_lh2")
	assert_true(float(s.stand("spray_lh").fwd_m) < -0.5 and float(h1.fwd_m) < -0.5, "관창보조는 관창수 뒤")
	assert_true(float(h2.fwd_m) < float(h1.fwd_m) - 0.6, "관창보조2는 관창보조1 뒤")


## A7 인명검색 이동 (2026-11-15 사용자가 블렌더에서 확인): 조장(검색봉으로 바닥 두드리기) + 짝(공기호흡기 잡고 뒤따름)
func test_search_pair_baked() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	assert_eq(s.frames("search_a"), 16, "조장 16장")
	assert_eq(s.frames("search_b"), 16, "짝 16장")
	var b := s.stand("search_b")
	assert_true(float(b.fwd_m) < -0.6 and float(b.fwd_m) > -1.1, "짝은 조장 뒤 0.6~1.1m (%.2f)" % float(b.get("fwd_m", 0.0)))
	assert_true(absf(float(b.right_m)) < 0.2, "짝은 조장 바로 뒤")


## A8 무전 보고 (2026-11-15 사용자가 블렌더에서 확인): 서서 / 낮은 자세, 오른손 무전기를 입 앞에
func test_radio_baked() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	assert_eq(s.frames("radio"), 8, "서서 8장")
	assert_eq(s.frames("radio_low"), 8, "낮은 자세 8장")
	assert_true(float(SpriteArt.config().fps.get("radio", 0.0)) > 0.0, "빠르기")


## A9 응급처치 + 구급대원 그림 (2026-11-15 사용자가 블렌더에서 확인)
func test_paramedic_and_first_aid_baked() -> void:
	var ems := SpriteArt.crew_set("구급대")
	assert_true(ems != null and ems != SpriteArt.get_set(str(SpriteArt.config().crew)), "구급대는 구급대원 그림")
	assert_true(SpriteArt.crew_set("진압대") == SpriteArt.get_set(str(SpriteArt.config().crew)), "진압대는 대원 그림 그대로")
	for anim in ["idle", "walk", "idle_bag", "walk_bag"]:
		assert_true(ems.frames(anim) > 0, "구급대원 %s" % anim)
	assert_eq(ems.frames("aid_a"), 12, "응급처치(머리 옆) 12장")
	assert_eq(ems.frames("aid_b"), 12, "응급처치(팔 옆) 12장")
	var a := ems.stand("aid_a")
	var b := ems.stand("aid_b")
	assert_true(float(a.right_m) > 0.2 and float(b.right_m) < -0.2, "두 대원은 환자 양옆 (%.2f / %.2f)" % [float(a.right_m), float(b.right_m)])
	for key in ["male", "female"]:
		var v := SpriteArt.get_set(str(SpriteArt.config().victims[key]))
		assert_eq(v.frames("aid_v"), 12, "누운 환자(%s) 12장" % key)


## A10 들것 이송 (2026-11-15 사용자가 블렌더에서 확인): 주 들것(바깥) · 분리형 들것(건물 안)
func test_stretchers_baked() -> void:
	var ems := SpriteArt.crew_set("구급대")
	for kind in ["cot", "scoop"]:
		assert_eq(ems.frames(kind + "_a"), 16, "%s 조장 16장" % kind)
		assert_eq(ems.frames(kind + "_b"), 16, "%s 짝 16장" % kind)
		assert_true(float(ems.stand(kind + "_b").fwd_m) > 1.5, "%s 짝은 조장 앞 (%.2f)" % [kind, float(ems.stand(kind + "_b").get("fwd_m", 0.0))])
		for key in ["male", "female"]:
			var v := SpriteArt.get_set(str(SpriteArt.config().victims[key]))
			assert_eq(v.frames(kind + "_v"), 16, "%s 환자(%s) 16장" % [kind, key])
			assert_true(float(v.stand(kind + "_v").fwd_m) > 0.5, "%s 환자는 조장 앞 들것 위" % kind)


## B1 문 확인 후 개방 (2026-11-15 사용자가 블렌더에서 확인): 손등으로 문 온도 짚기 · 낮은 자세로 천천히 열기
func test_door_check_baked() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	assert_eq(s.frames("door_feel"), 12, "문 확인 12장")
	assert_eq(s.frames("door_open"), 12, "서서히 개방 12장")
	for anim in ["door_feel", "door_open"]:
		var st := s.stand(anim)
		assert_true(absf(float(st.right_m)) > 0.5, "%s: 문 앞이 아니라 문 옆 벽에 (%.2f)" % [anim, float(st.get("right_m", 0.0))])


## B2 창 파괴 (2026-11-15 사용자가 블렌더에서 확인): 창 옆에서 곡괭이 끝으로 위쪽을 옆으로 차례로
func test_window_break_baked() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	assert_eq(s.frames("window_break"), 12, "창 파괴 12장")
	var st := s.stand("window_break")
	assert_true(absf(float(st.right_m)) > 0.4, "창 정면이 아니라 창 옆에 선다 (%.2f)" % float(st.get("right_m", 0.0)))


## B3 잔불 정리 (2026-11-15 사용자가 블렌더에서 확인): 갈고리로 천장 뜯기 + 관창으로 그 속 겨누기
func test_overhaul_baked() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	assert_eq(s.frames("ovh_a"), 12, "갈고리 12장")
	assert_eq(s.frames("ovh_b"), 12, "관창 12장")
	var b := s.stand("ovh_b")
	assert_true(Vector2(float(b.fwd_m), float(b.right_m)).length() > 0.5, "짝은 조장 옆 (%.2f, %.2f)" % [float(b.get("fwd_m", 0.0)), float(b.get("right_m", 0.0))])


## 운전원 작업 그림 (2026-11-16 사용자 확인): 공기호흡기 없는 운전원, 호스를 굴려 펴고 결합·소화전 개방
func test_driver_baked() -> void:
	var d := SpriteArt.get_set(str(SpriteArt.config().driver))
	assert_true(d != null, "운전원 그림 묶음")
	for anim in ["idle", "walk", "carry_roll", "roll_out", "cpl_low", "cpl_mid", "open"]:
		assert_true(d.frames(anim) > 0, "운전원 %s" % anim)
	assert_true(SpriteArt.crew_set("진압대").frames("cpl_mid") > 0, "차 옆 대원(공기호흡기 착용)의 차 급수구 결합")
	var plans: Dictionary = SpriteArt.config().driver_steps
	for key in ["hydrant_solo", "hydrant_pair", "supply"]:
		for who in ["driver", "helper", "other"]:
			if not plans[key].has(who):
				continue
			var last := 0.0
			for st: Array in plans[key][who]:
				assert_true(float(st[0]) > last, "%s %s 구간이 차례로 커진다" % [key, who])
				if str(st[1]) != "":
					var art := d if who != "helper" else SpriteArt.crew_set("진압대")
					assert_true(art.frames(str(st[1])) > 0, "%s %s %s 그림" % [key, who, st[1]])
				last = float(st[0])
			assert_eq(last, 1.0, "%s %s 끝 = 1" % [key, who])
	# 소화전은 차 쪽 결합(cpl_mid)이 끝난 뒤 마지막에 연다 (사용자)
	var solo: Array = plans.hydrant_solo.driver
	assert_eq(str(solo[solo.size() - 1][1]), "open", "마지막은 소화전 개방")


## B5 공기호흡기 용기 교체 (2026-11-16 사용자가 블렌더에서 확인): 각자 앉아서
func test_scba_swap_baked() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	assert_eq(s.frames("scba_swap"), 16, "용기 교체 16장")


## B6 가스 차단 (2026-11-16 사용자가 블렌더에서 확인): LPG 용기 밸브를 시계 방향으로 돌려 잠근다
func test_gas_off_baked() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	assert_eq(s.frames("gas_off"), 16, "가스 차단 16장")
	var st := s.stand("gas_off")
	assert_true(Vector2(float(st.fwd_m), float(st.right_m)).length() > 0.3, "용기 앞에 선다 (용기와 겹치지 않음)")
