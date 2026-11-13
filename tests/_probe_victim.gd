extends SceneTree
## 점검용 (테스트 목록에 넣지 않음, G2-1): 아무도 손대지 않을 때 구조대상자가 있는 방의 연기·열과 노출량을 분마다 찍는다.
## 인자: [시나리오 경로] [분]


func _initialize() -> void:
	var path := "res://data/scenarios/tutorial_basics.json"
	var minutes := 30
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]
	if args.size() > 1:
		minutes = int(args[1])
	var sim := SimWorld.from_scenario(path)
	# 셋째 인자 closed: 구조대상자가 있는 방의 안쪽 문을 모두 닫고 시작한다 (문 열림·닫힘 비교, UL 실험 대조)
	if args.size() > 2 and args[2] == "closed":
		for v in sim.rescue.victims:
			var room := sim.fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
			for o in sim.fire.openings:
				if o.kind == Opening.Kind.DOOR and (o.room_a == room.index or o.room_b == room.index):
					o.is_open = false
		sim.doors.sync_blocking()
	sim.apply_realism("훈련")
	var hz := ParamTable.from_dict(JsonData.load_file("res://data/fire/hazard_params.json"))
	var co_per_soot: float = hz.value("co_per_soot")
	var lower: float = hz.value("lower_layer_exposure_ratio")
	var lying: float = hz.value("lying_breath_height_m")
	var table: Array = hz.params.get("co_death_table", {}).get("value", [])
	print("신고 후 = 표시 시각 + %d초 (출동 중 선행 연소)" % int(sim.dispatch_s))
	for m in minutes + 1:
		for v in sim.rescue.victims:
			var c := sim.fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
			if c == null:
				continue
			var in_layer := lying >= c.height - c.layer_depth
			var conc := c.soot / maxf(c.layer_volume(), 0.05 * c.volume)
			var ppm_layer := conc * co_per_soot / 1.145 * 1e6
			var ppm := ppm_layer * (1.0 if in_layer else lower)
			var temp := c.t_upper if in_layer else c.t_lower
			print("%2d분 %s[%s] %s | 연기층 %.2f/%.1fm %s | 층CO %6dppm → 마시는 CO %6dppm (사망까지 %5.0f분) | 상부 %3d℃ 하부 %3d℃ → %3d℃ | O2 %.1f%% | 독성 %.2f 열 %.2f (1 의식잃음·3 사망) | 방 단계 %s" % [
				m, v.name, v.state_name(), c.display_name(), c.layer_depth, c.height, "잠김" if in_layer else "층 아래",
				roundi(ppm_layer), roundi(ppm), RescueSystem.co_death_minutes(ppm, table) if ppm > 1.0 else 99999.0,
				roundi(c.t_upper), roundi(c.t_lower), roundi(temp), c.o2_percent(), v.fed_toxic, v.fed_heat, Compartment.Stage.keys()[c.stage]])
		# 불이 난 방과 그 사이 통로도 함께 (연구 자료와 비교용)
		var row := "      "
		for c in sim.fire.comps:
			if c.level != 1 or c.soot <= 0.0:
				continue
			var cc := c.soot / maxf(c.layer_volume(), 0.05 * c.volume) * co_per_soot / 1.145 * 1e6
			row += "%s 층%.1fm CO%d 상%d℃ 하%d℃ | " % [c.display_name().replace("1층 ", ""), c.layer_depth, roundi(cc), roundi(c.t_upper), roundi(c.t_lower)]
		print(row)
		sim.step_ticks(roundi(60.0 / SimClock.TICK_DT))
	for type: String in ["door_burnt_through", "flashover", "stage"]:
		for e in sim.events.of_type(type):
			var line := SimEventLog.describe(e)
			if type != "stage" or line.contains("발화기"):
				print("사건 ", line, " ", str(e.get("room", e.get("cell", ""))))
	quit()
