extends SceneTree
## 점검용 (테스트 목록에 넣지 않음): 연기층이 방마다 언제 생기고 얼마나 내려오는지 시간별로 찍는다


func _initialize() -> void:
	var path := "res://data/scenarios/sop214_2_night_upstairs.json"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		path = args[0]
	var sim := SimWorld.from_scenario(path)
	sim.command.resources.clear_schedule()
	var fire := sim.fire
	var first := {}
	var covered := {}
	var t := 0.0
	for step in 300:
		sim.step_ticks(10)
		t += 1.0
		for c in fire.comps:
			if c.layer_depth > 0.02 and not first.has(c.index):
				first[c.index] = t
			if c.smoke_started() and c.smoke_covered() and not covered.has(c.index):
				covered[c.index] = "%ds (출발 %s, %.1fm)" % [int(t), str(c.smoke_origin), c.smoke_full_m]
		if int(t) % 15 == 0:
			var row := "t=%3ds " % int(t)
			for c in fire.comps:
				if c.layer_depth > 0.02:
					row += "| %s %.2fm Q%.0f " % [c.display_name(), c.layer_depth, c.q]
			print(row)
	print("--- 연기층이 처음 생긴 시각(s) ---")
	for c in fire.comps:
		var rs := c.rect.size
		print("%s %dx%d칸(%.1fx%.1fm): %s" % [c.display_name(), rs.x, rs.y, rs.x * 0.5, rs.y * 0.5, str(first.get(c.index, "-")) + " / 다 덮음 " + str(covered.get(c.index, "-"))])
	quit()
