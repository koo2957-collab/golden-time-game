extends SceneTree
## 점검용 (테스트 목록에 넣지 않음): 건물의 화재하중과, 손대지 않을 때 화재실의 열방출률·온도·연기 진행을 문헌 값과 견줄 수 있게 찍는다.
## 인자: [시나리오 경로] [분]


func _initialize() -> void:
	var path := "res://data/scenarios/tutorial_basics.json"
	var minutes := 20
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]
	if args.size() > 1:
		minutes = int(args[1])
	var sim := SimWorld.from_scenario(path, false)
	var fire := sim.fire
	print("── 화재하중 (구획별: 면적, 가연물 열량, 면적당, 칸 최대 열방출률 합) ──")
	var tot_a := 0.0
	var tot_mj := 0.0
	for c in fire.comps:
		var mj := 0.0
		var peak := 0.0
		for i in fire.grid.room_cells[c.index]:
			mj += fire.grid.fuel0[i]
			peak += fire.grid.peak_kw(i)
		print("%-14s %5.1f㎡  %6d MJ  %4d MJ/㎡  최대 %5d kW (%4d kW/㎡)  부피 %4.0f㎥" % [c.display_name(), c.area, roundi(mj), roundi(mj / maxf(c.area, 0.1)), roundi(peak), roundi(peak / maxf(c.area, 0.1)), c.volume])
		if not c.display_name().contains("옆집"):
			tot_a += c.area
			tot_mj += mj
	print("화재 건물 합계 %.0f㎡, %d MJ, 평균 %d MJ/㎡" % [tot_a, roundi(tot_mj), roundi(tot_mj / maxf(tot_a, 1.0))])
	print("── 진행 (발화 후 시간, 30초마다) ──")
	var origin: Compartment = null
	var t := 0.0
	var marks := {}
	for step in minutes * 2 + 1:
		if origin == null:
			for c in fire.comps:
				if c.q > 0.0:
					origin = c
		var total_q := 0.0
		for c in fire.comps:
			total_q += c.q
			if c.flashed and not marks.has(c.index):
				marks[c.index] = "%s 플래시오버 %d초" % [c.display_name(), int(t)]
		if origin:
			print("%4d초 %s: Q %5d kW (환기 상한 %5d) 타는 면적 %4.1f㎡ 상부 %3d℃ 하부 %3d℃ 연기층 %.2fm O2 %4.1f%% 연소효율 %.2f | 건물 전체 Q %5d kW · 타는 칸 %d" % [
				int(t), origin.display_name(), roundi(origin.q), roundi(origin.q_max), origin.burning_area_m2, roundi(origin.t_upper), roundi(origin.t_lower),
				origin.layer_depth, origin.o2_percent(), origin.combustion_eff, roundi(total_q), fire.grid.burning.size()])
		for i in roundi(30.0 / SimClock.TICK_DT):
			fire.step(SimClock.TICK_DT, 0)
		t += 30.0
	for k in marks:
		print(marks[k])
	quit()
