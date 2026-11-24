extends SceneTree
## 대원 그림이 사라지는 문제 점검 (점검용, 테스트 목록에 넣지 않음, 2026-11-24):
##   godot --path . -s res://tests/_shot_vanish.gd -- 저장폴더 [ext|int] [mission|real|door|open] [clear] [시나리오 이름]
## 보기: ext = 외부 화면, int = 내부 화면. 흐름: mission = 호스를 먼저 꺼내 준 뒤 1층 화재진압 지시 / real = 호스 없이 바로 지시 /
##   door = 호스를 가진 조에게 잠긴 현관문을 열라고만 (파괴 + 문 앞 방수태세) / open = 잠금을 풀고 (확인·개방 + 방수태세).
##   clear = 다른 출동대를 화면 밖으로 (겹쳐서 세기 어렵다).
## 한 틱씩 돌리며 조원마다 실제 자리·그리는 자리·자세·그림 칸을 적고(log_*.txt), 문 작업·방수 장면을 조에 가깝게 찍은 뒤
## 조원마다 몸 그림이 화면에 실제로 보이는지 잰다 (그 대원만 붉게 칠해 다시 그려 달라진 점을 센다 — _measure).


var world
var sim: SimWorld
var out := ""
var lines: PackedStringArray = []
var _imgs: Dictionary = {}
var _shots: Dictionary = {}
var _sa = null
var _flow := "mission"


func _initialize() -> void:
	_run.call_deferred()


func _say(s: String) -> void:
	lines.append(s)
	print(s)


func _layer():
	var iso = world.iso_view
	return iso.layers[0] if world.exterior_view else iso.current_live


## 그림 칸에 보이는 점이 몇 개인가 (-1 = 칸 없음)
func _cell_pixels(art, pose: Array) -> int:
	var a: Dictionary = art.anims.get(pose[0], {})
	if a.is_empty():
		return -1
	var n := maxi(1, int(a.frames))
	var key := "%d_%d" % [posmod(int(pose[1]), art.directions), posmod(int(pose[2]), n)]
	var cell: Array = a.cells.get(key, [])
	if cell.is_empty():
		return -1
	var page := int(cell[0])
	if not _imgs.has(page):
		var im: Image = art.pages[page].get_image()
		if im.is_compressed():
			im.decompress()
		_imgs[page] = im
	var img: Image = _imgs[page]
	var count := 0
	for y in range(int(cell[2]), int(cell[2]) + int(cell[4]), 2):
		for x in range(int(cell[1]), int(cell[1]) + int(cell[3]), 2):
			if img.get_pixel(x, y).a > 0.2:
				count += 1
	return count


func _dump(crew: Crew, tag: String) -> String:
	var layer = _layer()
	var alpha := sim.clock.alpha()
	var squad = sim.units.squads[crew.squad_id]
	var art = _sa.crew_set(squad.type)
	var h := sim.water.hose_of_crew(crew.id)
	var dt := sim.doors.task_of_crew(crew.id)
	var head := "t=%d [%s] %s" % [sim.clock.tick, tag, "외부" if world.exterior_view else "내부"]
	if h != null:
		head += " hose(flow=%s appr=%s charged=%s fetch=%d to_outlet=%s pts=%d)" % [h.flowing, h.approaching, h.charged, h.fetch_until, h.to_outlet, h.points.size()]
	else:
		head += " hose(none)"
	if dt != null:
		head += " door(open=%s locked=%s wait=%s prog=%.1f/%.1f)" % [dt.open, dt.opening.locked if dt.opening else false, dt.waiting_people, dt.progress, dt.required]
	if sim.cards.checking_door(crew.id) != null:
		head += " checking_door"
	_say(head)
	var sig := ""
	var workers := crew.workers()
	for ff in crew.members():
		var role := "선두" if ff == crew.leader else ("팀장" if ff.officer else "%d번" % (workers.find(ff) + 1))
		var p: Vector2 = ff.pos if ff.prev_level != ff.level else ff.prev_pos.lerp(ff.pos, alpha)
		var sp: Vector2 = layer._shown_pos(ff, alpha)
		var pose: Array = layer._unit_pose(ff, crew, art)
		var px := _cell_pixels(art, pose)
		var b := sim.building
		var cx := floori(sp.x)
		var cy := floori(sp.y)
		var walk := b.is_walkable(ff.level, cx, cy)
		var outdoor: bool = b.cell(ff.level, cx, cy) in BuildingData.OUTDOOR
		var masked := false
		if not layer._mask_now.is_empty() and b.in_bounds(cx, cy):
			masked = layer._mask_now[cy * b.width + cx] == 0
		var note := ""
		if px < 0:
			note += " <칸 없음 → 도형>"
		elif px == 0:
			note += " <빈 그림>"
		if masked:
			note += " <가림표 0 — 그리지 않음>"
		if sp.distance_to(p) > 2.0:
			note += " <실제 자리에서 %.1f칸>" % sp.distance_to(p)
		if not walk:
			note += " <걸을 수 없는 칸>"
		if world.exterior_view and not outdoor:
			note += " <건물 안 — 외관에 가림>"
		_say("   %s#%d lv%d%s%s sim=(%.2f,%.2f) shown=(%.2f,%.2f) pose=%s/%d/%d px=%d%s" % [role, ff.id, ff.level,
			" 낮은" if ff.crouched else "", " 걷는중" if ff.is_moving() else "", p.x, p.y, sp.x, sp.y, pose[0], pose[1], pose[2], px, note])
		sig += "%s:%s " % [role, pose[0]]
	return sig


func _shot(crew: Crew, name: String, zoom := 2.6) -> void:
	var n := int(_shots.get(name, 0))
	_shots[name] = n + 1
	if n >= 3:
		return
	var layer = _layer()
	var c := Vector2.ZERO
	var k := 0
	for ff in crew.members():
		c += layer._shown_pos(ff, 0.0)
		k += 1
	world.selection.selected = [crew.id] as Array[int]
	world.camera.zoom = Vector2(zoom, zoom)
	world.camera.position = world.projection().to_screen(c / maxf(1.0, k), 0.6)
	root.warp_mouse(Vector2(10, 10))
	for i in 8:
		await process_frame
	world.hud.card_ui.visible = false
	var file := "%s%s_%s_%s_%d_t%d.png" % [out, "ext" if world.exterior_view else "int", _flow, name, n, sim.clock.tick]
	root.get_texture().get_image().save_png(file)
	_say("   >> 화면 " + file)
	await _measure(crew)


## 떠 있는 질문 카드에 답한다 (최선 등급, 없으면 첫째)
func _answer_cards() -> void:
	for card in sim.cards.queue.duplicate():
		var pick := -1
		for i in card.options.size():
			if str(card.options[i].get("effect", "")) in ["entry_grant", "force_door", "open_door", "vent_then_open"]:
				pick = i
				break
		for i in card.options.size():
			if pick < 0 and str(card.options[i].get("grade", "")) == "최선":
				pick = i
		pick = maxi(pick, 0)
		_say("   카드 %s → %s (%s)" % [card.id, str(card.options[pick].get("text", "")).left(40), str(card.options[pick].get("effect", ""))])
		sim.cards.answer(card.uid, pick, sim.clock.tick)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = (args[0] if not args.is_empty() else OS.get_user_data_dir()) + "/"
	var view: String = args[1] if args.size() > 1 else "ext"
	var flow: String = args[2] if args.size() > 2 else "mission"
	var opts: String = args[3] if args.size() > 3 else ""
	var clear_others := opts.contains("clear")
	var scen: String = args[4] if args.size() > 4 else "sop214_1_day_living"
	_flow = flow
	var gm = root.get_node_or_null("GameManager")
	gm.scenario_path = "res://data/scenarios/%s.json" % scen
	gm.skip_menu = true
	root.add_child(load("res://scenes/main/main.tscn").instantiate())
	for i in 10:
		await process_frame
	world = root.get_node("Main/World")
	_sa = load("res://scripts/ui/sprite_art.gd")
	world.confine_mouse(false)
	world.camera.edge_scroll = false
	world.hud.command_ui.close_all()
	sim = world.sim
	sim.decision_pause = false
	world.hud.card_ui.pauses = Callable()
	if world.hud.tutorial_ui:
		world.hud.tutorial_ui.visible = false
	var d = world.hud.command_ui.dispatch
	d.skip()
	sim.issue(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": 1.0}))
	for i in 120:
		sim.step_ticks(10)
		sim.cards.queue.clear()
		await process_frame
	for i in 600:
		if not world.camera.locked:
			break
		await process_frame
	world.hud.command_ui.close_all()
	world.hud.card_ui.visible = false
	sim.clock.paused = true
	var crew: Crew = null
	for c in sim.units.crews:
		if sim._default_mission(c) == "attack" and not c.leader.aboard and (not opts.contains("officer") or c.officer() != null):
			crew = c
			break
	if crew == null:
		_say("진압 분대 없음")
		_finish()
		return
	world.set_view_level(1, view == "ext")
	if clear_others:
		# 다른 출동대는 화면 밖으로 (겹쳐서 세기 어렵다)
		for c in sim.units.crews:
			if c != crew:
				for ff in c.members():
					ff.pos = Vector2(40.5, 30.5)
					ff.prev_pos = ff.pos
					ff.path.clear()
	for i in 4:
		await process_frame
	_say("조 %d · 조원 %d명 (일하는 조원 %d명) · 보기 %s" % [crew.id, crew.members().size(), crew.workers().size(), view])
	# 1) 호스 꺼내기 (real 은 호스 없이 바로 지시한다 — 지금 진행 순서 그대로)
	var pump := sim.water._nearest_pump(crew.leader.pos)
	if flow != "real" and sim.water.hose_of_crew(crew.id) == null and not sim.water.lay_hose(crew.id, pump, sim.clock.tick):
		_say("수관 연장 실패")
		_finish()
		return
	var h := sim.water.hose_of_crew(crew.id)
	for i in 1500:
		if h == null or (not h.to_outlet and h.fetch_until < 0):
			break
		sim.step_ticks(1)
		sim.cards.queue.clear()
		if h.fetch_until >= 0 and not _shots.has("fetch") and i % 30 == 29:
			_dump(crew, "fetch")
			await _shot(crew, "fetch")
	_dump(crew, "호스 꺼냄")
	if flow not in ["mission", "real", "both"]:
		await _door_flow(crew, flow)
		_finish()
		return
	# 2) 실제 명령: 화재 건물 1층 화재진압 (가까운 주 진입구)
	var entry = null
	for e in sim.entries.list:
		if e.level == 1 and not e.neighbour and (entry == null or crew.leader.pos.distance_to(Vector2(e.door)) < crew.leader.pos.distance_to(Vector2(entry.door))):
			entry = e
	if entry == null:
		_say("진입구 없음")
		_finish()
		return
	if flow == "both":
		await _both_flow(crew, entry)
		_finish()
		return
	sim.issue(CommandOrder.make("floor_mission", [crew.squad_id] as Array[int], entry.level, Vector3i.ZERO, {"kind": "attack", "entry": entry.index}))
	_say("지시: 1층 화재진압 · 진입구 %d 문 %s" % [entry.index, entry.door])
	var last_sig := ""
	var spray_seen := 0
	for i in 6000:
		sim.step_ticks(1)
		if not sim.cards.queue.is_empty():
			_dump(crew, "카드")
			_answer_cards()
		h = sim.water.hose_of_crew(crew.id)
		var dt := sim.doors.task_of_crew(crew.id)
		var state := ""
		if sim.cards.checking_door(crew.id) != null:
			state = "check"
		elif dt != null and dt.open and not dt.waiting_people and not crew.leader.is_moving():
			state = "force" if dt.opening != null and dt.opening.locked else "open"
		elif h != null and h.flowing and not h.approaching and not crew.leader.is_moving():
			state = "spray_low" if crew.leader.crouched else "spray"
		elif h != null and h.fetch_until >= 0:
			state = "fetch"
		elif crew.leader.is_moving():
			state = "walk"
		if i % 5 != 0:
			continue
		var layer = _layer()
		var art = _sa.crew_set(sim.units.squads[crew.squad_id].type)
		if state in ["check", "open", "force"] and not layer._door_ready_layout(crew, art).is_empty():
			state += "_ready"
		var tag := state if state != "" else "-"
		var sig := tag + " "
		for ff in crew.members():
			sig += str(layer._unit_pose(ff, crew, art)[0]) + " "
		if sig != last_sig:
			last_sig = sig
			_dump(crew, tag)
			if state != "" and state != "walk" and state != "fetch":
				# 자세가 바뀐 직후 말고 조금 지나서 (동작이 자리 잡은 뒤)
				sim.step_ticks(4)
				_dump(crew, tag + "+4")
				await _shot(crew, state)
		if state.begins_with("spray"):
			spray_seen += 1
			if spray_seen in [20, 60, 150, 300]:
				_dump(crew, tag + " 계속")
				await _shot(crew, state + "_later")
			if spray_seen > 400:
				break
	_finish()


## 진압 분대와 구조 분대가 같은 진입구에서 만날 때 (2026-11-24 사용자 보고: 진압대에 화재진압, 구조대에 인명구조를 시켜
## 둘이 한 문 앞에서 만나 문을 열면 대원이 사라진다). 두 분대 모두 그 진입구로 보내고, 어느 쪽이든 자세가 바뀌면 두 분대를 다 적고 잰다
func _both_flow(attack: Crew, entry) -> void:
	var rescue_crew: Crew = null
	for c in sim.units.crews:
		if c != attack and c.squad_id != attack.squad_id and sim._default_mission(c) == "search" and not c.leader.aboard:
			rescue_crew = c
			break
	if rescue_crew == null:
		_say("구조 분대 없음")
		return
	_say("구조 분대: 조 %d (%s)" % [rescue_crew.id, sim.units.squads[rescue_crew.squad_id].name])
	sim.issue(CommandOrder.make("floor_mission", [attack.squad_id] as Array[int], entry.level, Vector3i.ZERO, {"kind": "attack", "entry": entry.index}))
	sim.issue(CommandOrder.make("floor_mission", [rescue_crew.squad_id] as Array[int], entry.level, Vector3i.ZERO, {"kind": "search", "entry": entry.index}))
	_say("지시: 진압 = 1층 화재진압 · 구조 = 1층 인명구조 · 같은 진입구 %d 문 %s" % [entry.index, entry.door])
	var last_sig := ""
	var after := 0
	for i in 9000:
		sim.step_ticks(1)
		if not sim.cards.queue.is_empty():
			_answer_cards()
		if i % 5 != 0:
			continue
		var layer = _layer()
		var sig := ""
		for c: Crew in [attack, rescue_crew]:
			var art = _sa.crew_set(sim.units.squads[c.squad_id].type)
			var dt := sim.doors.task_of_crew(c.id)
			sig += "[%s%s] " % ["문" if dt != null and dt.open else "", "확인" if sim.cards.checking_door(c.id) != null else ""]
			for ff in c.members():
				sig += str(layer._unit_pose(ff, c, art)[0]) + " "
		if sig == last_sig:
			continue
		last_sig = sig
		_say("--- 자세 바뀜: " + sig)
		_dump(attack, "진압")
		_dump(rescue_crew, "구조")
		# 두 분대가 문 가까이 함께 있을 때만 찍는다 (아니면 기록만)
		var door_p := Vector2(entry.door) + Vector2(0.5, 0.5)
		var near: bool = attack.leader.pos.distance_to(door_p) <= 5.0 and rescue_crew.leader.pos.distance_to(door_p) <= 5.0 \
			and attack.leader.level == entry.level and rescue_crew.leader.level == entry.level
		if near:
			sim.step_ticks(4)
			await _shot_pair(attack, rescue_crew, "both")
			after = 0
		else:
			after += 1
		# 두 분대 모두 건물 안 깊이 들어갔으면 끝
		if not near and after > 30:
			break


## 두 분대 가운데를 찍고 두 분대 모두 몸이 보이는지 잰다
func _shot_pair(a: Crew, b: Crew, name: String) -> void:
	var n := int(_shots.get(name, 0))
	_shots[name] = n + 1
	if n >= 12:
		return
	var layer = _layer()
	var c := Vector2.ZERO
	var k := 0
	for cr: Crew in [a, b]:
		for ff in cr.members():
			c += layer._shown_pos(ff, 0.0)
			k += 1
	world.selection.selected = [] as Array[int]
	world.camera.zoom = Vector2(2.4, 2.4)
	world.camera.position = world.projection().to_screen(c / maxf(1.0, k), 0.6)
	root.warp_mouse(Vector2(10, 10))
	for i in 8:
		await process_frame
	world.hud.card_ui.visible = false
	var file := "%s%s_%s_%s_%d_t%d.png" % [out, "ext" if world.exterior_view else "int", _flow, name, n, sim.clock.tick]
	root.get_texture().get_image().save_png(file)
	_say("   >> 화면 " + file)
	_say("   [진압]")
	await _measure(a)
	_say("   [구조]")
	await _measure(b)


func _finish() -> void:
	var f := FileAccess.open(out + ("log_%s_%s.txt" % ["ext" if world != null and world.exterior_view else "int", _flow]), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	quit()


## 문 작업만 따로 (tests/_shot_check.gd ready 와 같은 흐름): 호스를 가진 조에게 가까운 1층 출입문을 열라고 한다.
## flow: door = 잠긴 그대로(파괴) / open = 잠금을 풀고(확인·개방) / *_charged = 호스에 물이 찬 상태로
func _door_flow(crew: Crew, flow: String) -> void:
	var h := sim.water.hose_of_crew(crew.id)
	var door := Vector2i(-1, -1)
	for e in sim.entries.list:
		if e.level == 1 and not e.neighbour and (door.x < 0 or crew.leader.pos.distance_to(Vector2(e.door)) < crew.leader.pos.distance_to(Vector2(door))):
			door = Vector2i(e.door)
	var o = sim.fire.opening_at(Vector3i(door.x, door.y, 1))
	if o == null:
		_say("문 없음")
		return
	if flow.begins_with("open"):
		o.locked = false
		sim.doors.sync_blocking()
	if flow.ends_with("charged"):
		h.charged = true
	if not sim.doors.request(crew.id, Vector3i(door.x, door.y, 1), true, sim.clock.tick):
		_say("문 개방 지시 실패 %s" % door)
		return
	_say("지시: 문 %s 개방 (잠김 %s)" % [door, o.locked])
	var seen := 0
	var last_sig := ""
	for i in 2500:
		sim.step_ticks(1)
		sim.cards.queue.clear()
		var t := sim.doors.task_of_crew(crew.id)
		if t == null and i > 50:
			break
		var working: bool = t != null and t.open and not t.waiting_people and not crew.leader.is_moving() and crew.leader.pos.distance_to(Vector2(door) + Vector2(0.5, 0.5)) <= 3.5
		if i % 5 == 0:
			var layer = _layer()
			var art = _sa.crew_set(sim.units.squads[crew.squad_id].type)
			var sig := ""
			for ff in crew.members():
				sig += str(layer._unit_pose(ff, crew, art)[0]) + " "
			if sig != last_sig:
				last_sig = sig
				_dump(crew, "문 작업" if working else "가는 중")
		if working and t.progress > 1.0:
			seen += 1
			if seen in [1, 40]:
				_dump(crew, "문 작업 %d" % seen)
				await _shot(crew, "door", 3.0)
	_dump(crew, "문 작업 끝")


## 둘째 화면이 첫째보다 그 네모 안에서 붉어진(초록·파랑만 줄어든) 점 수
func _diff(a: Image, b: Image, r: Rect2) -> int:
	var x0 := clampi(int(r.position.x), 0, a.get_width() - 1)
	var x1 := clampi(int(r.end.x), 0, a.get_width() - 1)
	var y0 := clampi(int(r.position.y), 0, a.get_height() - 1)
	var y1 := clampi(int(r.end.y), 0, a.get_height() - 1)
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			# 열 스트레스 색은 초록·파랑만 줄인다 (빨강은 그대로) — 연기·물줄기·불꽃이 움직여 달라진 점과 구별된다
			var dg := p.g - q.g
			var db := p.b - q.b
			if dg > 0.025 and db > 0.025 and absf(p.r - q.r) < 0.015 + 0.3 * dg:
				n += 1
	return n


## 몸 그림이 화면에 실제로 보이는가: 동작을 멈춰 놓고 그 대원만 열 스트레스 색(붉게)을 입혀 다시 그린 뒤,
## 그림이 놓이는 네모 안에서 달라진 점을 센다 (가려졌거나 그려지지 않았으면 달라지지 않는다). 고리·이름표는 색이 그대로라 세지 않는다
func _measure(crew: Crew) -> void:
	var layer = _layer()
	var art = _sa.crew_set(sim.units.squads[crew.squad_id].type)
	var fps: Dictionary = _sa.config().get("fps", {})
	var keep := fps.duplicate()
	for key in fps.keys():
		if not str(key).begins_with("_"):
			fps[key] = 0.0
	# 이미 열 스트레스로 붉어진 대원은 색이 더 달라지지 않는다 — 재는 동안 모두 0으로 두고 한 명씩 1로 올린다
	var heat_was: Dictionary = {}
	for ff in crew.members():
		heat_was[ff] = ff.heat_stress
		ff.heat_stress = 0.0
	for i in 3:
		await process_frame
	var base: Image = root.get_texture().get_image()
	for i in 2:
		await process_frame
	var base2: Image = root.get_texture().get_image()
	var xf: Transform2D = root.get_final_transform() * layer.get_global_transform_with_canvas()
	var zoom := xf.get_scale().x
	_say("   (화면 %dx%d · 배율 %.2f)" % [base.get_width(), base.get_height(), zoom])
	var seen := 0
	var outlined := 0
	var gone := 0
	var text := ""
	var workers := crew.workers()
	for ff in crew.members():
		var role := "선두" if ff == crew.leader else ("팀장" if ff.officer else "%d번" % (workers.find(ff) + 1))
		var pose: Array = layer._unit_pose(ff, crew, art)
		var a: Dictionary = art.anims.get(pose[0], {})
		var key := "%d_%d" % [posmod(int(pose[1]), art.directions), posmod(int(pose[2]), maxi(1, int(a.get("frames", 1))))]
		var cell: Array = a.get("cells", {}).get(key, [])
		if cell.is_empty():
			text += " %s 칸없음" % role
			continue
		var feet: Vector2 = layer.proj.to_screen(layer._shown_pos(ff, sim.clock.alpha()), 0.0)
		var kk: float = 1.0 / art.scale
		var r := Rect2(xf * (feet + Vector2(float(cell[5]), float(cell[6])) * kk), Vector2(float(cell[3]), float(cell[4])) * kk * zoom)
		ff.heat_stress = 1.0
		for i in 2:
			await process_frame
		var img: Image = root.get_texture().get_image()
		ff.heat_stress = 0.0
		var changed := _diff(base, img, r) - _diff(base, base2, r)
		var expect := float(_cell_pixels(art, pose)) * 4.0 * pow(kk * zoom, 2.0)
		var pct := roundi(100.0 * maxf(0.0, changed) / maxf(1.0, expect))
		var on_screen := Rect2(0, 0, base.get_width(), base.get_height()).encloses(r)
		# 몸의 밝은 부분(방화복)만 색이 달라진다 — 다 보여도 100%가 되지는 않는다. 15% 아래면 안 보이는 것으로 친다.
		# 연기에 묻힌 사람은 연기 위에 노란 테두리로 다시 그린다 (_draw_smoke_outlines) — 그 테두리가 몸 자리에 있는지도 본다
		var sim_p: Vector2 = ff.pos if ff.prev_level != ff.level else ff.prev_pos.lerp(ff.pos, sim.clock.alpha())
		var shown_p: Vector2 = layer._shown_pos(ff, sim.clock.alpha())
		var hulls = layer._smoke_hulls
		var ol_sim: bool = not hulls.is_empty() and layer._in_hulls(layer.proj.to_screen(sim_p, 1.0), hulls)
		var ol_shown: bool = not hulls.is_empty() and layer._in_hulls(layer.proj.to_screen(shown_p, 1.0), hulls)
		# 테두리를 그리는 자리: 고친 뒤(_outline_crew 있음)는 몸을 그리는 자리, 그 전에는 실제 자리
		var fixed: bool = layer.has_method("_outline_crew")
		if fixed:
			ol_sim = ol_shown
			sim_p = shown_p
		var verdict := "보임"
		if pct >= 15:
			seen += 1
		elif ol_sim and sim_p.distance_to(shown_p) <= 0.75:
			verdict = "연기 속 테두리"
			outlined += 1
		elif ol_sim:
			verdict = "사라짐(테두리가 %.1f칸 떨어진 곳에)" % sim_p.distance_to(shown_p)
			gone += 1
		else:
			verdict = "사라짐(테두리 없음%s)" % (" — 그린 자리는 연기 속" if ol_shown else "")
			gone += 1
		text += " %s %d%% %s%s" % [role, pct, verdict, "" if on_screen else "(화면 밖)"]
	for key in keep.keys():
		fps[key] = keep[key]
	for ff: Firefighter in heat_was:
		ff.heat_stress = heat_was[ff]
	for i in 2:
		await process_frame
	_say("   >> 조원 %d명: 몸이 보임 %d · 연기 속 테두리 %d · 사라짐 %d ·%s" % [crew.members().size(), seen, outlined, gone, text])
