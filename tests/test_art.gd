extends TestSuite
## P15: 구운 그림 연결 (data/art.json → res://art/sprites). 묶음·동작·방향이 다 있고, 게임 대상이 빠짐없이 연결되며, 메모리가 저사양 기준 안인지.

const CREW_ANIMS := ["idle", "walk", "crouch_walk", "carry", "spray", "search", "down"]
## 저사양 PC 기준 그림 텍스처 상한 (MB, 게임 설정값 — docs/perf.md)
const TEXTURE_BUDGET_MB := 48.0


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


func test_crew_has_every_action_and_helmet_stripe() -> void:
	var s := SpriteArt.get_set(str(SpriteArt.config().crew))
	for anim in CREW_ANIMS:
		assert_true(s.has(anim), "대원 동작 %s (기획안 9-4-1)" % anim)
	assert_eq(s.directions, 8, "8방향")
	assert_eq(s.anims.idle.stripe.size(), s.anims.idle.cells.size(), "헬멧 띠 그림이 프레임마다 (역할 색)")
	for role in ["진압대", "구조대", "구급대", "RIT", "현장안전담당", "지휘"]:
		assert_true(SpriteArt.stripe_color(role) != Color.WHITE or role == "지휘", "%s 띠 색" % role)


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
