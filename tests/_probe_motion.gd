extends SceneTree
## 대원 움직임 점검 (테스트 목록에 넣지 않음): godot --path . -s res://tests/_probe_motion.gd -- [현장 초=240] [배속=2]
## 2026-11-27 사용자: "대원들이 방수를 하거나 이동할 때 왔다갔다 하는 게 어색하다" — 화면에 그려지는 자리·방향·동작이
## 프레임마다 어떻게 바뀌는지 센다: 순간이동(한 프레임에 크게 뜀), 방향 왔다갔다(A→B→A), 동작 왔다갔다, 시뮬레이션 선두의 되돌아가기

const JUMP_M := 0.45
const FLIP_S := 0.8


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 240.0
	var speed := float(args[1]) if args.size() > 1 else 2.0
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/sop214_1_day_living.json"
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	var world = root.get_node("Main/World")
	world.confine_mouse(false)
	world.hud.command_ui.close_all()
	world.hud.card_ui.pauses = Callable()
	var sim: SimWorld = world.sim
	var d = world.hud.command_ui.dispatch
	d.answer_rest()
	d.skip()
	for i in 900:
		if not d.active and not world.camera.locked:
			break
		await process_frame
	sim.decision_pause = false
	world.set_speed(4.0)
	if sim.units.crews[0].leader.aboard and not sim.command.resources.arriving_now():
		sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 6000:
		if i > 30 and not sim.command.resources.arriving_now() and not sim.units.crews[0].leader.aboard:
			break
		_answer(sim)
		await process_frame
	sim.command.strategy = CommandSystem.Strategy.OFFENSIVE
	world.set_speed(speed)
	var crews := sim.units.crews
	var att: Crew = null
	var res: Crew = null
	for c in crews:
		var t := sim.units.squads[c.squad_id].type
		if t == "진압대" and att == null:
			att = c
		if t == "구조대" and res == null:
			res = c
	world.mission_ui.issue_floor_mission("attack", [att.id] as Array[int], 1)
	if res != null:
		world.mission_ui.issue_floor_mission("search", [res.id] as Array[int], 1)
	var lvls: Array = []
	for l in world.iso_view.layers:
		lvls.append(l.level)
	print("준비: 진압 ", att != null, " 탑승 ", att.leader.aboard if att else "-", " 층 ", att.leader.level if att else -1, " 그림판 층 ", lvls, " 도착중 ", sim.command.resources.arriving_now())
	var art := SpriteArt.get_set(str(SpriteArt.config().get("crew", "")))
	var cell := sim.building.cell_size_m
	var st := {}
	var t_end := sim.clock.tick + roundi(seconds / SimClock.TICK_DT)
	var frames := 0
	while sim.clock.tick < t_end and not sim.ended():
		_answer(sim)
		await process_frame
		frames += 1
		var now := Time.get_ticks_msec() / 1000.0
		for c: Crew in [att, res]:
			if c == null:
				continue
			for ff in c.members():
				var layer = null
				for l in world.iso_view.layers:
					if l.level == ff.level:
						layer = l
				if layer == null or ff.aboard:
					continue
				var pose: Array = layer._unit_pose(ff, c, art)
				var shown: Vector2 = layer._shown_pos(ff, 1.0)
				var s: Dictionary = st.get(ff.id, {})
				if s.is_empty():
					s = {"name": "%s-%d" % [sim.units.squads[c.squad_id].name, c.list.find(ff) + 1], "pos": shown, "dir": int(pose[1]), "anim": str(pose[0]),
						"jumps": [], "dir_changes": 0, "dir_flips": 0, "anim_changes": 0, "anim_flips": [], "dir_hist": [], "anim_hist": [], "samples": 0,
						"flip_ctx": {}, "level": ff.level}
					st[ff.id] = s
				s.samples += 1
				var dist := (shown - (s.pos as Vector2)).length() * cell
				if dist > JUMP_M and int(s.level) == ff.level:
					(s.jumps as Array).append([snappedf(sim.clock.tick * SimClock.TICK_DT, 0.1), snappedf(dist, 0.01), "%s→%s" % [s.anim, pose[0]]])
				if int(pose[1]) != int(s.dir):
					s.dir_changes += 1
					var h: Array = s.dir_hist
					# A→B→A: 짧은 시간 안에 예전 방향으로 되돌아옴
					if h.size() >= 1 and int(h[-1][0]) == int(pose[1]) and now - float(h[-1][1]) < FLIP_S:
						s.dir_flips += 1
						var key := str(pose[0])
						s.flip_ctx[key] = int(s.flip_ctx.get(key, 0)) + 1
					h.append([int(s.dir), now])
					if h.size() > 4:
						h.pop_front()
				if str(pose[0]) != str(s.anim):
					s.anim_changes += 1
					var ah: Array = s.anim_hist
					if ah.size() >= 1 and str(ah[-1][0]) == str(pose[0]) and now - float(ah[-1][1]) < FLIP_S:
						(s.anim_flips as Array).append("%s↔%s" % [s.anim, pose[0]])
					ah.append([str(s.anim), now])
					if ah.size() > 4:
						ah.pop_front()
				s.pos = shown
				s.dir = int(pose[1])
				s.anim = str(pose[0])
				s.level = ff.level
	print("=== 움직임 점검: 현장 %d초, 배속 %.0f, 프레임 %d ===" % [int(seconds), speed, frames])
	for id: int in st:
		var s: Dictionary = st[id]
		var flips := {}
		for f: String in s.anim_flips:
			flips[f] = int(flips.get(f, 0)) + 1
		print("%s  순간이동 %d회 · 방향 바뀜 %d회 (왔다갔다 %d회 %s) · 동작 바뀜 %d회 (왔다갔다 %d회 %s)" % [s.name, (s.jumps as Array).size(),
			s.dir_changes, s.dir_flips, s.flip_ctx, s.anim_changes, (s.anim_flips as Array).size(), flips])
		var js: Array = s.jumps
		for k in mini(js.size(), 12):
			print("     뜀 t=%s초 %sm %s" % [js[k][0], js[k][1], js[k][2]])
	quit()


func _answer(sim: SimWorld) -> void:
	for card in sim.cards.queue.duplicate():
		var pick := 0
		for k in card.options.size():
			if str(card.options[k].get("grade", "")) == "최선":
				pick = k
		sim.cards.answer(card.uid, pick, sim.clock.tick)
