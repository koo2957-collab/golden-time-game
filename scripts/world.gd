extends Node2D
## 게임 월드 루트. 시뮬레이션(SimWorld)을 소유하고 화면 노드들을 연결한다.
## 화면은 두 가지이며 Tab으로 전환한다.
##   입체(기본): Iso/IsoView 하나가 도면·화염·연기층·대원을 모두 그린다.
##   상황판: Map(도면) / Effects(화염·연기) / Units(대원)
## 선택·이동·카메라는 현재 화면의 좌표 변환(ViewProjection)을 따른다.

enum ViewMode { ISO, PLAN }

## 시작 화면 없이 실행했을 때 쓰는 시나리오
const SCENARIO_PATH := "res://data/scenarios/dev_house_fire.json"
## 다시 하기: 한 프레임에 다시 계산하는 틱 수 (화면이 멈추지 않게 나눈다)
const REPLAY_CHUNK_TICKS := 120
const SPEED_ACTIONS := {"time_speed_1x": 1.0, "time_speed_2x": 2.0, "time_speed_4x": 4.0}
const START_ZOOM := {ViewMode.ISO: 0.75, ViewMode.PLAN: 1.4}

var sim: SimWorld
var view_level := 1
## 외부 보기 (바깥 + 건물 외관, R16). 시작은 외부 보기 — 지휘관은 밖에 있다
var exterior_view := false
var view_mode := ViewMode.ISO
var thermal := false
var ignite_mode := false
var command_hint := ""
## 지시 창(층 우클릭)·팀장 둥근 버튼 (R7c, 2026-11-17)
var mission_ui: MissionUi
## 리플레이 보기: 아직 넣지 않은 기록 (R12)
var _view_entries: Array[Dictionary] = []
var _view_next := 0
var _last_report: Dictionary = {}
## 게임 메뉴 (Esc, 기획안 8-4, P11-1)
var game_menu: GameMenu
## 전소가 확실할 때 뜨는 '결과 보기' 버튼 (기획안 8-3)
var result_button: Button
var _result_check := 0.0
var _estimates_drawn := 0
## 흰 매스 도시 배경 (기획안 4-4) / 도착 연출을 아직 하지 않았는가
var city: CityMassView
var _arrival_pending := false
var _arrival_zoom_to := Vector2.ONE
var _arrival_pos_to := Vector2.ZERO
## 성능 표시 (F12, R15): 프레임마다 시뮬레이션에 쓴 시간(ms, 이동 평균)
var _sim_ms := 0.0
## 창(출동 지령·상황보고 등)을 열기 전의 일시정지 상태
var _paused_before_dialog := false
var projections := {ViewMode.ISO: IsoProjection.new(), ViewMode.PLAN: PlanProjection.new()}

@onready var floor_view: FloorPlanView = $Map/FloorPlanView
@onready var fire_view: FireView = $Effects/FireView
@onready var units_view: UnitsView = $Units/UnitsView
@onready var iso_view: IsoView = $Iso/IsoView
@onready var selection: SelectionController = $SelectionController
@onready var camera: RtsCamera = $Camera2D
@onready var hud: Hud = $UI/HUD


func _ready() -> void:
	add_to_group("world")
	InstructorSettings.active = true
	_ensure_card_keys()
	# 창 모드에서도 가장자리 스크롤이 되도록 게임 중에는 마우스를 창 안에 가둔다 (Esc로 풂, 기획안 9-3)
	confine_mouse(true)
	var path := GameManager.scenario_path if GameManager.scenario_path != "" else SCENARIO_PATH
	var replay_tick := int(GameManager.replay.get("tick", -1))
	if replay_tick >= 0:
		sim = await _run_replay(path)
	else:
		# 시나리오 variation.random_seed면 판마다 다른 시드 (구조대상자 위치 등이 바뀐다)
		var data: Variant = JsonData.load_file(path)
		var random_seed: bool = data is Dictionary and bool(data.get("variation", {}).get("random_seed", false))
		sim = SimWorld.from_scenario(path, true, randi() % 1000000 if random_seed else -1)
		if sim:
			sim.tactical.set_level(_automation_level(data if data is Dictionary else {}))
			sim.apply_realism(GameManager.realism)
			sim.cards.crew_judgment = GameManager.crew_judgment
			# 대원 성장 기록 적용 (신임·일반·숙련·고참, R12)
			sim.apply_growth(CrewGrowth.load_xp())
	if sim == null:
		push_error("시나리오를 불러오지 못했습니다: %s" % path)
		return
	sim.play_mode = GameManager.mode
	# 현장 시계 기본 배속 (2026-11-15: 1배) — 플레이 중 배속 단추·F1·F2·F3으로 바꾼다
	sim.clock.speed = sim.field_scale
	floor_view.setup(sim.building)
	floor_view.tactical = sim.tactical
	floor_view.layout = sim.unit_layout
	city = CityMassView.new()
	$Iso.add_child(city)
	$Iso.move_child(city, 0)
	# 밤이면 창문 불빛·가로등 (시나리오 시각에 따라, 화면 분위기와 같은 기준)
	city.night = ViewParams.load_default().night_factor(ViewParams.clock_hour(str(sim.scenario.get("clock", ""))))
	city.setup(sim.building, projections[ViewMode.ISO], sim.rng_seed, sim)
	fire_view.setup(sim)
	_setup_mood()
	selection.setup(sim)
	units_view.setup(sim, selection)
	iso_view.setup(sim, selection, projections[ViewMode.ISO])
	hud.setup(sim, set_view_level)
	hud.card_key_pressed.connect(_press_card)
	hud.card.enabled_fn = _card_item_enabled
	hud.board_pressed.connect(_press_board)
	hud.interior_toggled.connect(_set_interior)
	hud.span_selected.connect(set_interior_span)
	interior_span = clampi(iso_view.params.split_default_span, 1, _max_span())
	hud.set_span_state(interior_span, _max_span())
	hud.split_gap_step.connect(_step_split_gap)
	hud.board_done_fn = _board_done
	hud.command_ui.order_issued.connect(sim.issue)
	hud.command_ui.dialog_changed.connect(_on_dialog_changed)
	selection.witness_clicked.connect(hud.command_ui.open_witness)
	selection.notice.connect(hud.show_notice)
	# 임무형 내부 지휘: 층 우클릭 지시 창·팀장 둥근 버튼 (R7c, 2026-11-17)
	mission_ui = MissionUi.new()
	hud.add_child(mission_ui)
	mission_ui.setup(sim, selection, screen_to_cell)
	mission_ui.order_issued.connect(sim.issue)
	mission_ui.notice.connect(hud.show_notice)
	mission_ui.card = hud.card
	selection.squad_menu.connect(mission_ui.open_squad_menu)
	# 좌클릭 = 보기·고르기, 우클릭 = 지시 (2026-11-16 사용자 결정): 층 우클릭 → 지시 창 (임무 + 진입구 + 지시)
	# 우클릭 층 = 분대 기본 임무를 바로 (2026-11-26 — 지시 창 대신), 명령판 임무 → 층 클릭
	selection.floor_order.connect(mission_ui.quick_order)
	selection.floor_mission.connect(mission_ui.issue_floor_mission)
	hud.floor_bar.floor_ordered.connect(func(lv: int, pos: Vector2) -> void: selection.order_floor(lv, pos))
	selection.guide_view.connect(func(lv: int, ext: bool) -> void: set_view_level(lv, ext))
	selection.shell_picker = func(world_pos: Vector2) -> int:
		if view_mode != ViewMode.ISO or not exterior_view:
			return -99
		return iso_view.shell_level_at(world_pos)
	selection.shell_hover = func(lv: int, text: String) -> void: iso_view.set_hover_floor(lv, text)
	# 내부 화면에서 함께 보이는 층과 화면 위치 — 아래층 바깥의 대원·차량도 그려진 자리에서 고른다
	selection.shown_floors = func() -> Array:
		if view_mode != ViewMode.ISO:
			return [[view_level, Vector2.ZERO]]
		return iso_view.shown_floors()
	# 빈 곳 좌클릭으로 볼 곳: 외부 보기의 외벽 층 → 그 층 내부, 내부 화면의 바깥 땅 → 외부 보기, 다른 층 → 그 층
	selection.view_picker = _view_target
	mission_ui.press_card = _press_card
	# 단면 보기: 아래층을 누르면 그 층으로 (R17)
	selection.level_picker = func(world_pos: Vector2) -> int:
		if view_mode != ViewMode.ISO or exterior_view:
			return view_level
		return iso_view.stack.pick_level(view_level, world_pos, projection())
	# 내부 화면에서 다른 층을 누름: 그 층이 고른 층이 되고 화면은 제자리 (같은 클릭이 그 층에서 처리된다)
	selection.floor_clicked.connect(func(lv: int) -> void: set_view_level(lv, false, true))
	city.progress = hud.command_ui.dispatch_progress
	city.placement = hud.command_ui.dispatch_placement
	# 팀 카드·상황판에 끌어다 놓아 임무 주기는 없앴다 (2026-11-17 — 임무는 층 우클릭 지시 창 하나로)
	hud.radio_log.jump.connect(_jump_to_crew)
	hud.team_strip.jump.connect(_jump_to_crew)
	hud.team_strip.picked.connect(func(id: int) -> void: selection._set_selection([id] as Array[int], [] as Array[int]))
	selection.team_order = hud.team_strip.crews
	hud.command_ui.team_selected.connect(_on_team_selected)
	# 미니맵 누르기·끌기: 그곳으로 화면 이동, 지금 화면 범위 표시 (R8 → R16)
	if hud.minimap:
		hud.minimap.jump.connect(func(cell: Vector2, lv: int) -> void:
			if lv != view_level:
				set_view_level(lv)
			camera.retarget(_view_bounds(), projection().to_screen(cell)))
		hud.minimap.view_corners = _view_corners
	# 아래 바의 지휘관 초상: 지휘관을 고른다
	hud.commander_pressed.connect(func() -> void: selection._set_selection([] as Array[int], [] as Array[int], true))
	var tutorial := str(sim.scenario.get("tutorial", ""))
	# 튜토리얼은 안내판이 순서를 알려 주므로 멈추는 힌트 카드는 끈다
	hud.hint_ui.setup(sim, GameManager.mode == "교육" and tutorial == "")
	if tutorial != "":
		hud.tutorial_ui = TutorialUi.new()
		hud.add_child(hud.tutorial_ui)
		hud.tutorial_ui.setup(sim, selection, tutorial)
	hud.hint_ui.dialog_changed.connect(_on_dialog_changed)
	hud.card_ui = CardUi.new()
	hud.add_child(hud.card_ui)
	hud.card_ui.setup(sim)
	hud.card_ui.order_issued.connect(sim.issue)
	# 무전 장면: 떠 있는 동안 현장 시간이 멈춘다 (2026-11-15: 훈련·실전 — 판단은 지휘관의 시간). 악조건은 멈추지 않는다.
	# 고른 직후 등급을 알려 주는 것은 훈련만
	hud.card_ui.pauses = func() -> bool: return not realtime()
	hud.card_ui.teaches = func() -> bool: return not _graded_later()
	hud.speed_pressed.connect(set_speed)
	hud.pause_pressed.connect(toggle_pause)
	hud.card_ui.scene_changed.connect(_on_radio_scene)
	hud.command_ui.end_dialog_opened.connect(hud.hint_ui.on_end_dialog)
	# 지휘권 선언: 지휘 위치를 지도에서 고르면 클릭으로 선언을 마친다 (P4-4)
	hud.command_ui.post_pick_requested.connect(func(a: Dictionary) -> void:
		selection.pending_declare = a
		selection.begin_mode(SelectionController.Mode.POST))
	EventBus.command_mode_changed.connect(_on_command_mode_changed)
	camera.setup(_view_bounds(), START_ZOOM[view_mode])
	# 지도가 도로 쪽으로 넓으므로 건물을 화면 가운데에 두고 시작한다
	var house := Rect2(sim.building.footprint(sim.building.levels()[0]))
	camera.retarget(_view_bounds(), projection().to_screen(house.get_center() + Vector2(0, 4)))
	set_view_mode(view_mode)
	set_view_level(sim.building.levels()[0], true)
	hud.floor_bar.floor_step.connect(_step_level)
	hud.debrief.restart_requested.connect(GameManager.restart)
	hud.debrief.menu_requested.connect(GameManager.back_to_menu)
	hud.debrief.replay_requested.connect(func(tick: int) -> void: GameManager.request_replay(sim.issued, tick, sim.rng_seed, sim.tactical.level_name, sim.realism, false, sim.growth))
	hud.debrief.view_requested.connect(func(tick: int) -> void: GameManager.request_replay(sim.issued, tick, sim.rng_seed, sim.tactical.level_name, sim.realism, true, sim.growth))
	hud.debrief.export_requested.connect(_export_report)
	hud.debrief.next_requested.connect(func(next_path: String) -> void:
		GameManager.scenario_path = next_path
		GameManager.restart())
	_build_game_menu()
	if replay_tick >= 0:
		sim.clock.paused = true
		var t := int(replay_tick * SimClock.TICK_DT)
		if sim.view_only:
			_build_view_banner()
			hud.show_notice("리플레이 보기: %02d:%02d부터 — Space 재생/정지 · F2·F3 배속 · T 열화상(온도) · M 입체/평면 · Esc 끝내기" % [t / 60, t % 60])
		else:
			hud.show_notice("다시 하기: %02d:%02d 시점입니다. Space로 다시 진행하세요." % [t / 60, t % 60])
	else:
		hud.command_ui.show_dispatch()
		# 출동 단계: 도시를 멀리서 본다 → 도착하면 확대 (기획안 4-4).
		# 출동 중 장면을 띄운 뒤에 확인한다 (예전에는 띄우기 전에 확인해 원경이 적용되지 않았다)
		if not sim.view_only and hud.command_ui.dispatch_visible():
			_arrival_pending = true
			_arrival_zoom_to = camera.zoom
			# 원경: 도시 전체가 한 화면에 (data/ui/city.json overview_width_m). 도착할 때까지 카메라는 고정
			var far := city.plan.overview_zoom(get_viewport_rect().size.x)
			camera.zoom = Vector2(far, far)
			_arrival_pos_to = camera.position
			camera.position = projections[ViewMode.ISO].to_screen(city.plan.center)
			camera.locked = true


## 자동화 수준: 시작 화면에서 고른 난이도, 없으면 시나리오 난이도 (개발용은 입문)
func _automation_level(data: Dictionary) -> String:
	if GameManager.difficulty != "":
		return GameManager.difficulty
	var d := str(data.get("meta", {}).get("difficulty", "입문"))
	return d if TacticalSystem.LEVELS.has(d) else "입문"


## 다시 하기: 같은 시나리오를 처음부터 만들어 기록된 명령을 그 시점까지 재생한다 (진행률 표시)
func _run_replay(path: String) -> SimWorld:
	var info: Dictionary = GameManager.replay
	GameManager.replay = {}
	var entries: Array[Dictionary] = []
	entries.assign(info.get("entries", []))
	var r := Replay.begin(path, entries, int(info.get("tick", 0)), int(info.get("seed", -1)), str(info.get("automation", "")), str(info.get("realism", "")),
		info.get("growth", {}))
	# 대원 판단 장면 설정도 같아야 같은 결과가 나온다 (꺼져 있었으면 대원이 알아서 한 판)
	if r:
		r.sim.cards.crew_judgment = GameManager.crew_judgment
	if r == null:
		return null
	# 리플레이 보기: 그 뒤의 기록도 시간에 맞춰 다시 넣는다 (플레이어 명령은 받지 않음)
	if bool(info.get("view", false)):
		for e in entries:
			if int(e.tick) >= int(info.get("tick", 0)):
				_view_entries.append(e)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 28)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	$UI.add_child(label)
	while not r.step(REPLAY_CHUNK_TICKS):
		label.text = "다시 하기 준비 중… %d%%" % roundi(r.progress() * 100.0)
		await get_tree().process_frame
	label.queue_free()
	r.sim.view_only = bool(info.get("view", false))
	return r.sim


func _process(delta: float) -> void:
	_step_glide()
	var t0 := Time.get_ticks_usec()
	_process_sim(delta)
	if hud.perf_visible():
		_sim_ms = lerpf(_sim_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)
		hud.update_perf(_sim_ms)


func _process_sim(delta: float) -> void:
	_refresh_result_button(delta)
	# 구조자 둘 곳 카드에서 '환자 집결지 지정'을 골랐다 → 바로 구역 지정 (P10-2 ⓒ)
	if sim and sim.rescue.zone_prompt:
		sim.rescue.zone_prompt = false
		selection.begin_mode(SelectionController.Mode.ZONE_CASUALTY if sim.zones.safe_ordered() else SelectionController.Mode.ZONE_SAFE)
		selection.casualty_after_safe = not sim.zones.safe_ordered()
		hud.show_notice("구조한 조가 입구에서 기다립니다 — %s" % ("안전구역 안에 환자 집결지를 찍으세요" if sim.zones.safe_ordered() else "먼저 건물 밖을 끌어서 안전구역을 지정하세요 — 이어서 환자 집결지를 찍습니다"))
	if sim and sim.view_only:
		# 리플레이 보기: 한 틱씩 진행하며 기록된 명령을 그 틱에 넣는다
		for i in sim.clock.consume(delta):
			while _view_next < _view_entries.size() and int(_view_entries[_view_next].tick) <= sim.clock.tick:
				sim.issue_replay(_view_entries[_view_next].command)
				_view_next += 1
			sim.step_ticks(1)
		if sim.ended() and not hud.debrief.visible:
			_show_debrief()
	elif sim:
		sim.advance(delta)
		if sim.ended() and not hud.debrief.visible:
			_show_debrief()


## 활동이 끝나면 평가하고 결과를 저장한 뒤 디브리핑을 띄운다 (SOP 113)
func _show_debrief() -> void:
	hud.command_ui.close_all()
	selection.cancel_mode()
	if result_button:
		result_button.visible = false
	var report := Evaluator.evaluate(sim)
	# 대원 성장: 끝까지 한 판만 (리플레이 보기·개발용 기능을 쓴 판·미완료 판 제외, R12·P11-1)
	if not sim.view_only and sim.replayable and sim.end_type != MissionEndChecker.END_INCOMPLETE:
		report["growth_lines"] = CrewGrowth.award(sim, report)
	report["decision_lines"] = decision_lines()
	_last_report = report
	hud.debrief.show_report(report, Evaluator.save(report) if not sim.view_only else "")


func _unhandled_input(event: InputEvent) -> void:
	if sim == null or hud.debrief.visible:
		return
	if hud.hint_ui.visible_hint():
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			hud.hint_ui.close_hint()
			get_viewport().set_input_as_handled()
		return
	if hud.command_ui.dispatch_visible():
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			hud.command_ui.close_dispatch()
			get_viewport().set_input_as_handled()
		return
	var card_key := _card_key(event)
	if card_key != "":
		_press_card(card_key)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("time_pause"):
		toggle_pause()
	elif event.is_action_pressed("floor_up"):
		_step_level(1)
	elif event.is_action_pressed("floor_down"):
		_step_level(-1)
	elif event.is_action_pressed("perf_overlay"):
		hud.toggle_perf()
	elif event.is_action_pressed("debug_info_fog") and OS.is_debug_build():
		sim.perception.enabled = not sim.perception.enabled
		sim.replayable = false
		_update_mode_text()
	elif event.is_action_pressed("ui_cancel") and sim.view_only:
		# 리플레이 보기 끝내기 → 시작 화면
		GameManager.back_to_menu()
	elif event.is_action_pressed("ui_cancel"):
		# 하던 선택 모드가 있으면 취소, 없으면 마우스 가둠을 푼다 (다시 클릭하면 가둠)
		if selection.mode != SelectionController.Mode.NONE or ignite_mode:
			selection.cancel_mode()
			hud.card.back()
			if ignite_mode:
				_set_ignite_mode(false)
		elif hud.card.back():
			pass
		elif hud.command_ui.any_dialog_open():
			hud.command_ui.close_all()
		elif mission_ui and mission_ui.is_open():
			mission_ui.close_all()
		else:
			# 취소할 것이 없으면 게임 메뉴 (게임을 멈추고 마우스 가둠도 푼다, 기획안 8-4)
			open_game_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_board") or event.is_action_pressed("toggle_view"):
		# Tab·M = 전술상황판 (P10-1)
		hud.board.toggle()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_HOME:
		# 지휘소(현장지휘관 위치)로 돌아오기 (기획안 9-3)
		var c := sim.command.commander
		set_view_level(c.level, _outdoors(c.level, c.pos))
		camera.retarget(_view_bounds(), projection().to_screen(c.pos))
	elif event.is_action_pressed("toggle_thermal"):
		set_thermal(not thermal)
	elif event.is_action_pressed("debug_fire_panel") and OS.is_debug_build():
		hud.set_debug_visible(not hud.is_debug_visible())
	elif event.is_action_pressed("debug_ignite") and OS.is_debug_build():
		_set_ignite_mode(not ignite_mode)
	else:
		for action: String in SPEED_ACTIONS:
			if event.is_action_pressed(action):
				set_speed(SPEED_ACTIONS[action])


func projection() -> ViewProjection:
	return projections[view_mode]


func set_view_mode(mode: ViewMode) -> void:
	# 화면을 바꿔도 보고 있던 지점이 그대로 가운데에 오게 한다
	var center_cell := projection().to_cell(camera.position)
	view_mode = mode
	var iso := mode == ViewMode.ISO
	$Iso.visible = iso
	$Map.visible = not iso
	$Effects.visible = not iso
	$Units.visible = not iso
	selection.projection = projection()
	camera.retarget(_view_bounds(), projection().to_screen(center_cell))
	_update_mode_text()


## 화면은 둘이다 (2026-11-14 사용자 결정):
##   외부 화면 (exterior = true): 건물 외관과 바깥 — 큰 틀의 작전과 밖에서 보이는 연기·화염
##   내부 화면 (exterior = false): level 층을 고른 층으로 한 층 분리 (고른 층 + 직상층 + 직하층)
## keep_screen: 내부 화면에서 지도의 다른 층을 눌러 바꿨다 — 층들이 화면에서 제자리에 있게 카메라만 따라간다
func set_view_level(level: int, exterior := false, keep_screen := false) -> void:
	if not sim.building.has_level(level):
		return
	var was_exterior := exterior_view
	var old_level := view_level
	view_level = level
	exterior_view = exterior and level == sim.building.levels()[0]
	floor_view.set_level(level)
	fire_view.level = level
	units_view.level = level
	iso_view.show_view(level, exterior_view)
	selection.level = level
	if hud.minimap:
		hud.minimap.level = level
	if hud.floor_bar:
		hud.floor_bar.exterior = exterior_view
	_fit_view_change(was_exterior, old_level, keep_screen)
	# 내부 화면에서는 주변 건물을 흐리게 (건물 안에 집중)
	if city:
		var dim := 1.0 if exterior_view else iso_view.params.split_city_dim
		city.modulate = Color(dim, dim, dim)
	hud.set_view_state(not exterior_view, iso_view.lift_px())
	camera.retarget(_view_bounds(), camera.position)
	camera.force_update_scroll()
	_update_mode_text()
	EventBus.view_floor_changed.emit(level)


## 카메라 이동 범위: 지도 + (외부 화면이면) 건물 외관 꼭대기, (내부 화면이면) 위아래로 떼어 놓은 층까지
func _view_bounds() -> Rect2:
	var r := projection().bounds(sim.building)
	if view_mode == ViewMode.ISO and exterior_view:
		var b := sim.building
		for c: Vector2 in [Vector2(0, 0), Vector2(b.width, 0), Vector2(0, b.height), Vector2(b.width, b.height)]:
			r = r.expand(projection().to_screen(c, iso_view.shell_top_m()))
	elif view_mode == ViewMode.ISO:
		r.size.y += iso_view.stack_depth_px()
		r = r.merge(iso_view.shown_rect().grow(160.0))
	return r


## 내부 화면 층 수 단추 (2026-11-14): 한 화면에 맞춰 넣을 층 수 — 누를 때만 화면에 맞춘다 (2026-11-25).
## 1(기본) = 고른 층을 가운데에 크게, 2 = 고른 층 + 짝 층, 3 = 고른 층 + 직상층 + 직하층
var interior_span := 1
## '2개 층'에서 고른 층의 짝: false = 직상층, true = 직하층.
## 한 층 위로 옮겨 왔으면 떠나온 아래층과, 한 층 아래로 옮겨 왔으면 떠나온 위층과 함께 본다 (보던 두 층 안에서는 화면이 그대로)
var _pair_lower := false
## 다른 층을 눌러 바꾼 뒤: 마우스 단추를 떼면 그 층을 가운데로 미끄러뜨린다 (누르는 동안 화면이 움직이면 뗀 자리가 달라진다)
var _glide_pending := false
var _glide: Tween


## 화면이 바뀔 때의 카메라:
##   외부 ↔ 내부 (2026-11-25 사용자 결정): 배율·위치를 그대로 둔다 — 같은 자리에서 벽만 걷어 낸 것처럼 (심즈·XCOM·Door Kickers 처럼
##     확대는 휠로만). 전에는 들어갈 때 고른 층에 꽉 차게 맞추고 나올 때 외부 카메라를 되돌려, 오갈 때마다 배율이 바뀌었다.
##     위층은 외부 화면에서는 외벽의 그 층 높이에, 내부 화면에서는 땅 높이에 그리므로 그만큼만 카메라를 옮겨 그 층이 화면에서 제자리에 있게 한다.
##     내부 화면에서 외부 최소 배율보다 더 축소한 채 나오면 외부 최소 배율로 맞춘다.
##     화면에 맞추는 것은 층 수 단추(1·2·3개 층)를 누를 때만
##   내부에서 층 바꿈(층 막대·PgUp): 그 층(과 짝 층)을 가운데로 옮기되 배율은 그대로
##   지도에서 다른 층을 눌러 바꿈(keep_screen): 클릭은 제자리에서 처리하고, 단추를 떼면 그 층이 가운데로 미끄러져 온다
##     2개 층: 보고 있던 두 층 안에서 눌렀으면 제자리, 밖의 층을 눌렀으면 한 층만 따라간다
##     3개 층: 세 층이 다 보이므로 제자리에 둔다
func _fit_view_change(was_exterior: bool, old_level: int, keep_screen: bool) -> void:
	if view_mode != ViewMode.ISO:
		return
	_stop_glide()
	if exterior_view:
		camera.zoom_min = RtsCamera.ZOOM_MIN
		if not was_exterior:
			_stop_arrival_zoom()
			camera.position -= _shell_shift(old_level)
			if camera.zoom.x < camera.zoom_min:
				camera.zoom = Vector2(camera.zoom_min, camera.zoom_min)
		return
	camera.zoom_min = iso_view.params.split_zoom_min
	# 2개 층의 짝: 보고 있던 두 층 안에서 옮겼는가, 그리고 새 짝은 어느 쪽인가
	var stack := iso_view.stack
	var step := stack.neighbor_step(old_level, view_level) if not was_exterior else 0
	var in_pair := step != 0 and stack.pair_level(old_level, _pair_lower) == view_level
	if was_exterior or old_level != view_level:
		_pair_lower = step > 0
	_pair_lower = stack.neighbor_step(view_level, stack.pair_level(view_level, _pair_lower)) < 0
	if was_exterior:
		_stop_arrival_zoom()
		camera.position += _shell_shift(view_level)
	elif keep_screen:
		camera.position += iso_view.level_shift(old_level, view_level)
		_glide_pending = interior_span <= 1 or (interior_span == 2 and not in_pair)
	elif old_level != view_level:
		_frame_interior(false)


## 외부 화면에서 그 층이 그려지는 높이만큼의 화면 거리 (world 좌표): 외부 화면은 외벽의 그 층 높이에, 내부 화면은 땅 높이에 그린다.
## 외관에 없는 층(1층·지하)은 0
func _shell_shift(level: int) -> Vector2:
	if iso_view.layers.is_empty():
		return Vector2.ZERO
	var band: Array = iso_view.layers[0].shell_band(level)
	if band.is_empty():
		return Vector2.ZERO
	var p := projection()
	return p.to_screen(Vector2.ZERO, 0.0) - p.to_screen(Vector2.ZERO, float(band[0]))


## '내부 보기' 단추: 켜면 내부 화면(고른 조가 건물 안에 있으면 그 층, 아니면 지상층), 끄면 외부 화면
func _set_interior(on: bool) -> void:
	var ground: int = sim.building.levels()[0]
	if on:
		set_view_level(_entry_level(ground), false)
	else:
		set_view_level(ground, true)


## 내부 화면의 층 간격을 한 단계 넓히거나 좁힌다 (dir = +1 / -1)
func _step_split_gap(dir: int) -> void:
	if exterior_view:
		return
	iso_view.set_lift(iso_view.lift_px() + dir * iso_view.params.split_step_px)
	_stop_glide()
	_frame_interior(interior_span > 1)
	camera.retarget(_view_bounds(), camera.position)
	hud.set_view_state(true, iso_view.lift_px())


## 이 건물에서 한 화면에 함께 맞출 수 있는 층 수 (1~3)
func _max_span() -> int:
	return iso_view.stack.max_span() if iso_view.stack != null else 1


## 내부 화면 층 수 단추: 1 = 고른 층을 가운데에 크게, 2 = 짝 층과 함께, 3 = 위·아래층까지 다 들어오게 축소
func set_interior_span(span: int) -> void:
	interior_span = clampi(span, 1, _max_span())
	hud.set_span_state(interior_span, _max_span())
	if not exterior_view and view_mode == ViewMode.ISO:
		_stop_glide()
		_frame_interior(true)
		camera.retarget(_view_bounds(), camera.position)


## 내부 화면에서 카메라가 있어야 할 [위치, 배율]: 고른 층(층 수 단추가 2·3이면 이웃 층까지)을
## 왼쪽 정보창·위쪽 시계·아래 바·오른쪽 정보 창 자리를 뺀 영역의 가운데에.
## fit_zoom 이면 그 영역에 꽉 차는 배율, 아니면 지금 배율 그대로
func _interior_target(fit_zoom: bool) -> Array:
	var p := iso_view.params
	var r := iso_view.frame_rect(interior_span, _pair_lower)
	var vp := get_viewport().get_visible_rect().size
	# 위쪽은 시계·단계 표시줄
	var top := hud.top_reserved_px()
	var bottom := (hud.console.size.y if hud.console else 0.0) + 16.0
	var left := p.split_info_width_px
	# 오른쪽: 정보 창·무전 기록 자리는 늘 비워 둔다 (창이 떠도 평면도를 가리지 않게)
	var right := hud.right_reserved_px()
	var z := camera.zoom.x
	if fit_zoom:
		var avail := Vector2(vp.x - right - left, vp.y - top - bottom)
		var z_max: float = START_ZOOM[ViewMode.ISO] if interior_span > 1 else p.split_focus_zoom_max
		z = clampf(minf(avail.x / r.size.x, avail.y / r.size.y), camera.zoom_min, z_max)
	return [r.get_center() + Vector2((right - left) * 0.5, (bottom - top) * 0.5) / z, z]


## 내부 화면 맞춤 (바로)
func _frame_interior(fit_zoom: bool) -> void:
	_stop_arrival_zoom()
	var t := _interior_target(fit_zoom)
	camera.zoom = Vector2(t[1], t[1])
	camera.bounds = _view_bounds()
	camera.position = t[0]


func _stop_glide() -> void:
	_glide_pending = false
	if _glide != null:
		_glide.kill()
		_glide = null


## 다른 층을 눌러 바꾼 뒤 마우스 단추를 뗐으면 그 층을 가운데로 미끄러뜨린다 (배율은 그대로)
func _step_glide() -> void:
	if not _glide_pending:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return
	_glide_pending = false
	if exterior_view or view_mode != ViewMode.ISO:
		return
	var target: Vector2 = _interior_target(false)[0]
	var t := iso_view.params.split_glide_s
	if t <= 0.0:
		camera.position = target
		return
	_glide = create_tween()
	_glide.tween_property(camera, "position", target, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 내부 화면으로 들어갈 층:## 줌으로 들어갈 층: 선택한 조 중 건물 안에 있는 조의 층, 없으면 지상층
func _entry_level(ground: int) -> int:
	for crew_id in selection.selected:
		var ff := sim.units.get_crew(crew_id).leader
		if not _outdoors(ff.level, ff.pos):
			return ff.level
	return ground


func _outdoors(level: int, pos: Vector2) -> bool:
	return sim.building.cell(level, floori(pos.x), floori(pos.y)) in BuildingData.OUTDOOR


func set_thermal(on: bool) -> void:
	thermal = on
	fire_view.thermal = on
	iso_view.thermal = on
	hud.set_thermal_visible(on)
	_update_mode_text()


func _set_ignite_mode(on: bool) -> void:
	ignite_mode = on
	selection.click_override = _ignite_at if on else Callable()
	_update_mode_text()


func _ignite_at(cell: Vector2i) -> void:
	sim.fire.ignite(Vector3i(cell.x, cell.y, view_level), sim.clock.tick)
	sim.replayable = false
	_set_ignite_mode(false)


func _on_command_mode_changed(hint: String) -> void:
	command_hint = hint
	# 대상 고르기가 끝나면(또는 취소) 명령 카드는 첫 칸으로
	if hint == "" and hud:
		hud.card.settle(false)
	_update_mode_text()


## 현장이 멈추지 않는 난이도인가 (악조건): 창·무전 장면이 떠도 시간이 흐르고 일시정지도 없다.
## 2026-11-15 사용자 결정: 훈련·실전은 '판단 중 정지' — 판단은 지휘관의 시간(실제 초), 대원의 행동은 현장 시계 (data/command/phase_params.json decision_pause)
func realtime() -> bool:
	return sim != null and not sim.view_only and not sim.decision_pause


## 답의 등급을 그 자리에서 알려 주지 않는 난이도인가 (실전·악조건 — 디브리핑에서 본다)
func _graded_later() -> bool:
	return sim != null and not sim.view_only and sim.realism in ["실전", "악조건"]


## Space·정지 단추: 현장을 멈추거나 다시 흐르게 한다. 멈춘 채로 고르고 지시할 수 있다 (지시는 다시 흐를 때 실행된다)
func toggle_pause() -> void:
	# 악조건은 일시정지 없음 (다시 하기로 멈춰 있을 때 다시 진행하는 것만 허용)
	if realtime() and not sim.clock.paused:
		hud.show_notice("%s 난이도는 일시정지할 수 없습니다 — 현장은 멈추지 않습니다" % sim.realism)
	else:
		sim.clock.paused = not sim.clock.paused


## 배속 단추·F1·F2·F3 (2026-11-15: 기본 1배 + 플레이어가 고르는 배속 — 프로스트펑크 방식). 기본 배속(field_scale)의 step배.
## 평가·기록은 현장 시간이라 배속과 상관없다
func set_speed(step: float) -> void:
	sim.clock.speed = step * (1.0 if sim.view_only else sim.field_scale)


## 지휘관의 판단 시간 (실제 초): 무전 장면이 떠서 답할 때까지 걸린 시간들 — 디브리핑에 보여 준다 (시뮬레이션·평가 점수와는 무관)
var decision_times: Array[float] = []
var _scene_open_ms := -1


## 디브리핑에 넣을 판단 시간 줄
func decision_lines() -> Array:
	if decision_times.is_empty():
		return []
	var total := 0.0
	var longest := 0.0
	for t in decision_times:
		total += t
		longest = maxf(longest, t)
	return ["무전 판단 %d건 · 평균 %.1f초 · 가장 길었던 판단 %.1f초 · 모두 %d분 %02d초" % [decision_times.size(), total / decision_times.size(), longest,
		int(total) / 60, int(total) % 60],
		"판단하는 동안 현장은 멈춰 있었습니다 (실제 현장에서는 이 시간만큼 불이 더 진행됩니다)." if not realtime() else "판단하는 동안에도 현장은 계속 진행됐습니다."]


## 도착 연출 (기획안 4-4): 출동 단계에는 도시 전체를 멀리서 보고, 선착대가 도착하면(출동 중 장면이 끝나면) 화재 건물로 확대.
## 배율 차이가 커서(약 15배) 배율의 지수로 바꿔 간다 — 처음부터 끝까지 같은 빠르기로 다가가는 느낌
func _arrival_zoom() -> void:
	if not _arrival_pending:
		return
	_arrival_pending = false
	var from := camera.zoom.x
	var to := _arrival_zoom_to.x
	var pos_from := camera.position
	var pos_to := _arrival_pos_to
	var tw := create_tween()
	_arrival_tween = tw
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(k: float) -> void:
		var z := from * pow(to / from, k)
		camera.zoom = Vector2(z, z)
		# 화면 가운데도 원경의 중심에서 현장으로 — 화면에서 같은 빠르기로 미끄러지게 배율에 맞춰
		var slide := (1.0 / from - 1.0 / z) / (1.0 / from - 1.0 / to) if not is_equal_approx(from, to) else k
		camera.position = pos_from.lerp(pos_to, slide), 0.0, 1.0, city.plan.num("arrival_zoom_s", 1.6))
	tw.tween_callback(func() -> void: camera.locked = false)


## 도착 확대가 진행 중이면 멈춘다 (2026-11-15): 확대가 끝나기 전에 내부 화면으로 바꾸면 확대 연출이 화면 맞춤을 덮어썼다
var _arrival_tween: Tween


func _stop_arrival_zoom() -> void:
	if _arrival_tween != null:
		_arrival_tween.kill()
		_arrival_tween = null
		camera.locked = false


func _on_dialog_changed(open: bool) -> void:
	if not open and _arrival_pending and not hud.command_ui.dispatch_visible():
		_arrival_zoom()
	# 실전·악조건에서는 출동 단계(도착 전)에만 현장 시계가 멈춰 있다 — 출동 시간은 실제 시간으로 따로 흐른다 (DispatchUi)
	if realtime() and not hud.command_ui.dispatch_visible():
		if not open and _paused_before_dialog == false:
			sim.clock.paused = false
		return
	if open:
		_paused_before_dialog = sim.clock.paused
		sim.clock.paused = true
	else:
		sim.clock.paused = _paused_before_dialog


## 화면 분위기 (2026-11-14 사용자 결정, 프로스트펑크 느낌): 지도 위·화면 요소 아래에 화면 색을 바꾸는 겹을 하나 둔다.
## 시나리오 시각(clock)에 따라 낮은 약하게, 밤은 강하게 (data/ui/view_params.json mood_*). 저사양 설정에서는 두지 않는다
var mood_rect: ColorRect


func _setup_mood() -> void:
	var vp := ViewParams.load_default()
	if not vp.mood_enabled or DisplaySettings.low_spec:
		return
	var layer := CanvasLayer.new()
	layer.name = "Mood"
	layer.layer = 0
	add_child(layer)
	move_child(layer, $UI.get_index())
	mood_rect = ColorRect.new()
	mood_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mood_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mood_grade.gdshader")
	var m := vp.mood_at(ViewParams.clock_hour(str(sim.scenario.get("clock", ""))))
	for key: String in m:
		mat.set_shader_parameter(key, m[key])
	mood_rect.material = mat
	layer.add_child(mood_rect)


## 무전 장면이 뜨거나 닫힘: 훈련 방식이면 그동안 현장 시간을 멈춘다 (지휘 창과 같은 방식). 다른 창이 열려 있으면 그 창이 시간을 맡는다
var _paused_before_scene := false
var _scene_paused := false


func _on_radio_scene(open: bool) -> void:
	if sim == null:
		return
	if open:
		_scene_open_ms = Time.get_ticks_msec()
		# 새 무전이 오면 배속을 풀어 1배로 (빨리 넘기다가 놓치지 않게)
		if not sim.view_only and sim.clock.speed > sim.field_scale:
			sim.clock.speed = sim.field_scale
		if not hud.card_ui.pausing():
			return
		if hud.command_ui.any_dialog_open():
			return
		_paused_before_scene = sim.clock.paused
		_scene_paused = true
		sim.clock.paused = true
	if not open and _scene_open_ms >= 0:
		decision_times.append((Time.get_ticks_msec() - _scene_open_ms) / 1000.0)
		_scene_open_ms = -1
	if not open and _scene_paused:
		_scene_paused = false
		if not hud.command_ui.any_dialog_open():
			sim.clock.paused = _paused_before_scene


## 무전 기록·팀 초상: 그 조로 화면 이동 (층도 바꾼다)
func _jump_to_crew(crew_id: int) -> void:
	var c := sim.units.get_crew(crew_id)
	if c == null or c.leader.aboard:
		return
	set_view_level(c.leader.level, _outdoors(c.leader.level, c.leader.pos))
	camera.retarget(_view_bounds(), projection().to_screen(c.leader.pos))


## 명령판 12칸의 단축키 입력 동작 (cmd_q … cmd_v). 프로젝트 설정에 없는 키(D F Z X C V — 2026-11-26 명령판 세 줄)는 여기서 더한다
func _ensure_card_keys() -> void:
	for k in CommandCard.KEYS:
		var action := "cmd_" + k.to_lower()
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = OS.find_keycode_from_string(k)
		InputMap.action_add_event(action, ev)


## 명령 카드 단축키 (Q W E R · A S D F · Z X C V). 입력 칸에 글을 쓰는 중이거나 창이 떠 있으면 쓰지 않는다
func _card_key(event: InputEvent) -> String:
	if not (event is InputEventKey) or not event.pressed or event.echo or sim.view_only:
		return ""
	if event.ctrl_pressed or event.alt_pressed or hud.command_ui.any_dialog_open():
		return ""
	for k in CommandCard.KEYS:
		if event.is_action_pressed("cmd_" + k.to_lower()):
			return k
	return ""


## 명령 카드 칸 누르기 (단축키·카드 버튼 공통, P10-2). "BACK" = 뒤로
func _press_card(key: String) -> void:
	# 단축키·카드 버튼으로 고르면 떠 있던 대상 메뉴는 닫는다
	if mission_ui:
		mission_ui.close_menu()
	if key == "BACK":
		selection.cancel_mode()
		hud.card.back()
		return
	var id := hud.card.press(key)
	if id != "":
		_on_command(id)
		hud.card.settle(selection.mode != SelectionController.Mode.NONE)


## 칸을 쓸 수 있는지: 차량 칸은 차종(need), 방수 중지는 쏘는 조가 있을 때
func _card_item_enabled(item: Dictionary) -> bool:
	match str(item.get("need", "")):
		"pump":
			return selection.selected_vehicles.any(func(v: int) -> bool: return sim.units.get_vehicle(v).is_pump())
		"monitor":
			return selection.selected_vehicles.any(func(v: int) -> bool: return sim.units.get_vehicle(v).is_pump() or sim.units.get_vehicle(v).is_aerial())
		"aerial":
			return selection.selected_vehicles.any(func(v: int) -> bool: return sim.units.get_vehicle(v).is_aerial())
		"tanker":
			return selection.selected_vehicles.any(func(v: int) -> bool: return sim.units.get_vehicle(v).transfer_lpm > 0.0)
	match str(item.get("id", "")):
		"search", "attack":
			return selection.selected.any(func(id: int) -> bool: return selection.default_kind(id) != "")
		"check_below":
			return sim.tactical.layout != null and not sim.tactical.layout.units.is_empty()
		"watch":
			return not sim.phases.all_clear.is_empty()
		"split", "merge":
			return _selected_squads().any(func(s: int) -> bool: return sim.regroup_reason(s, str(item.id) == "split") == "")
		"recall":
			return _selected_squads().any(func(s: int) -> bool: return sim.recall_reason(s) == "")
		"detach":
			return _selected_squads().any(func(s: int) -> bool: return mission_ui._detach_reason(s) == "")
		"stop":
			return not selection.crews_spraying().is_empty()
		"elevator":
			return sim.elevator.available()
		"support":
			return selection.selected.size() == 1 and mission_ui.support_crew(selection.selected[0]) >= 0
	return true


## 지휘관 명령 칸의 단추 누르기 (G3). 조·차량을 고른 채로도 쓴다 — 하던 대상 고르기는 그만둔다
func _press_board(id: String) -> void:
	if sim.view_only:
		return
	if mission_ui:
		mission_ui.close_menu()
	selection.cancel_mode()
	hud.card.back()
	_commander_command(id)


## 지휘관 명령 칸에서 이미 한 일 (단추를 흐리게): 한 번 하면 끝나는 선언·요청만
func _board_done(id: String) -> bool:
	match id:
		"declare":
			return sim.command.declared() or sim.command.is_declaring()
		"all_clear":
			return not sim.phases.all_clear.is_empty()
		"transfer":
			return sim.transfer.transferred()
		"support_more":
			return sim.command.resources.support_level != ""
		"response_1":
			return sim.command.resources.support_level == "대응 1단계 발령"
	return false


## 명령 실행. 지휘관·차량 명령은 조를 고르지 않아도 된다
func _on_command(id: String) -> void:
	if _commander_command(id) or _vehicle_command(id):
		return
	if selection.selected.is_empty():
		return
	match id:
		"ppv":
			if sim.vent.crew_id in selection.selected:
				sim.issue(EquipmentCommand.make("ppv_stop", [sim.vent.crew_id] as Array[int]))
			else:
				selection.begin_mode(SelectionController.Mode.PPV)
		"stop":
			var spraying := selection.crews_spraying()
			if not spraying.is_empty():
				sim.issue(EquipmentCommand.make("stop", spraying))
		"hold":
			sim.issue(TacticalCommand.make("hold", selection.selected))
		"report":
			sim.issue(CommandOrder.make("report_request", [], 0, Vector3i.ZERO, {"crews": selection.selected.duplicate()}))
		"waypoint":
			selection.begin_mode(SelectionController.Mode.WAYPOINT)
		"observe":
			selection.begin_mode(SelectionController.Mode.OBSERVE)
		"support":
			mission_ui.send_support(selection.selected[0])
		"treat":
			selection.begin_mode(SelectionController.Mode.TREAT)
		"triage_post":
			if not sim.zones.has_safe():
				hud.show_notice("안전구역이 아직 없습니다 — 지휘관이 먼저 안전구역을 지정해야 분류소를 차립니다")
			else:
				selection.begin_mode(SelectionController.Mode.TRIAGE_POST)
		"transport":
			selection.begin_mode(SelectionController.Mode.TRANSPORT)
		"exterior":
			selection.begin_mode(SelectionController.Mode.EXTERIOR)
		"withdraw":
			sim.issue(TacticalCommand.make("withdraw", selection.selected))
		# 명령판 임무 (2026-11-26): 누른 뒤 층을 클릭
		"search", "attack", "check_below", "watch":
			selection.begin_floor_mission(id)
		# 명령판 편성 (2026-11-26 — 팀장 두 번 클릭 둥근 버튼 대신)
		"split", "merge", "recall":
			mission_ui.squad_command(id, _selected_squads())
		"detach":
			var sqs := _selected_squads()
			if not sqs.is_empty():
				mission_ui.open_solo_menu(sqs[0], get_viewport().get_mouse_position())


## 고른 조들의 출동대 (겹치지 않게, 고른 순서)
func _selected_squads() -> Array[int]:
	var out: Array[int] = []
	for id in selection.selected:
		var c := sim.units.get_crew(id)
		if c != null and not c.squad_id in out:
			out.append(c.squad_id)
	return out


## 지휘관 명령 (지휘관 명령 칸 — data/commands.json commander_board·commander_tools). 처리했으면 true.
## 때가 아니어도 막지 않는다. 할 수 없는 일(이양받을 지휘대가 없음 등)만 알림으로 답한다
func _commander_command(id: String) -> bool:
	var ui := hud.command_ui
	match id:
		"declare":
			if sim.command.declared():
				hud.show_notice("이미 지휘권을 선언했습니다 — 새로 알게 된 것은 상황 보완 보고로 전파합니다")
			else:
				ui.open_command_dialog()
		"update_report":
			if sim.command.declared():
				ui.open_update_dialog()
			else:
				hud.show_notice("최초 상황보고 전입니다 — 보완할 보고가 없습니다")
		"strategy":
			# 선언 전이면 최초 상황보고 양식이 열린다 (전략은 그 보고의 한 항목)
			ui.open_command_dialog()
		"all_clear":
			if sim.phases.all_clear.is_empty():
				ui.open_all_clear()
			else:
				hud.show_notice("이미 완진을 선언했습니다")
		"transfer":
			if sim.transfer.transferred():
				hud.show_notice("이미 지휘권을 이양했습니다")
			elif not sim.transfer.arrived():
				hud.show_notice("지휘대가 아직 도착하지 않았습니다 — 지휘권을 넘겨받을 사람이 없습니다")
			else:
				ui.open_transfer_dialog()
		"end":
			ui.open_end_confirm()
		"rit":
			ui.open_role_dialog(SafetySystem.Role.RIT)
		"officer":
			ui.open_role_dialog(SafetySystem.Role.OFFICER)
		"info":
			ui.open_info_dialog()
		"survey":
			sim.issue(CommandOrder.make("survey"))
		"response_1":
			sim.issue(CommandOrder.make("support", [], 0, Vector3i.ZERO, {"level": "대응 1단계 발령"}))
		"support_more":
			sim.issue(CommandOrder.make("support", [], 0, Vector3i.ZERO, {"level": "추가 출동대 요청"}))
		"org":
			ui.open_org_dialog()
		"par":
			sim.issue(CommandOrder.make("par"))
		"withdraw_all":
			var inside: Array[int] = []
			for c in sim.units.crews:
				if sim.command.interior.crew_inside(c.id):
					inside.append(c.id)
			if inside.is_empty():
				hud.show_notice("건물 안에 있는 조가 없습니다")
			else:
				sim.issue(TacticalCommand.make("withdraw", inside))
		"evacuate":
			sim.issue(CommandOrder.make("evacuate"))
		"zone_safe":
			selection.begin_mode(SelectionController.Mode.ZONE_SAFE)
		"zone_casualty":
			if not sim.zones.safe_ordered():
				hud.show_notice("안전구역을 먼저 지정하세요 (지휘관 명령 칸 '구역'의 안전구역)")
			else:
				selection.begin_mode(SelectionController.Mode.ZONE_CASUALTY)
		"zone_line":
			selection.begin_mode(SelectionController.Mode.ZONE_LINE)
		"zone_post":
			selection.pending_declare = {}
			selection.begin_mode(SelectionController.Mode.POST)
		"zone_forward":
			selection.begin_mode(SelectionController.Mode.FORWARD)
		_:
			return false
	return true


## 차량 명령 (명령 카드 vehicle 세트). 처리했으면 true
func _vehicle_command(id: String) -> bool:
	var vids := selection.selected_vehicles
	match id:
		"vehicle_connect":
			selection.begin_mode(SelectionController.Mode.VEHICLE_CONNECT)
		"vehicle_move":
			selection.begin_mode(SelectionController.Mode.VEHICLE_MOVE)
		"vehicle_monitor":
			var pump := -1
			for vid in vids:
				if sim.units.get_vehicle(vid).is_pump() or sim.units.get_vehicle(vid).is_aerial():
					pump = vid
					break
			if pump < 0:
				return true
			if sim.monitors.stream_of(pump):
				sim.issue(EquipmentCommand.make("monitor_stop", [], pump))
			else:
				selection.monitor_vehicle = pump
				selection.begin_mode(SelectionController.Mode.MONITOR)
		"shuttle":
			for vid in vids:
				sim.issue(EquipmentCommand.make("shuttle", [], vid))
		"vehicle_basket":
			for vid in vids:
				if sim.units.get_vehicle(vid).is_aerial():
					selection.basket_vehicle = vid
					selection.begin_mode(SelectionController.Mode.BASKET)
					break
		_:
			return false
	return true


func _update_mode_text() -> void:
	var modes: PackedStringArray = ["입체" if view_mode == ViewMode.ISO else "상황판"]
	if view_mode == ViewMode.ISO:
		modes.append("외부 화면" if exterior_view else "내부 화면 · %s" % sim.building.floor_name(view_level))
	if thermal:
		modes.append("열화상")
	if not sim.perception.enabled:
		modes.append("정보 안개 꺼짐(개발용)")
	if ignite_mode:
		modes.append("발화: 클릭할 위치 선택")
	if command_hint != "":
		modes.append(command_hint)
	hud.mode_text = " · ".join(modes)


## 층 한 칸 오르내리기 (PgUp·PgDn, 층 막대 휠). 순서는 실제 층 번호대로이고, 외부 보기는 1층 바로 아래 칸
func _step_level(direction: int) -> void:
	var b := sim.building
	var order := b.levels()
	order.sort_custom(func(a: int, c: int) -> bool: return b.floor_number(a) < b.floor_number(c))
	var steps: Array[Array] = []
	for lv in order:
		if lv == b.levels()[0]:
			steps.append([lv, true])
		steps.append([lv, false])
	var i := 0
	for k in steps.size():
		if steps[k][0] == view_level and steps[k][1] == exterior_view:
			i = k
	var j := clampi(i + direction, 0, steps.size() - 1)
	set_view_level(steps[j][0], steps[j][1])


## 빈 곳을 좌클릭했을 때 볼 곳 (2026-11-16 사용자 결정 — 좌클릭 = 보기·고르기): Vector2i(층, 외부 보기면 1).
## 외부 보기: 외벽의 층 띠 → 그 층 내부. 내부 화면: 바깥 땅 → 외부 보기, 함께 보이는 다른 층 → 그 층. 없으면 (-99, 0)
func _view_target(world_pos: Vector2) -> Vector2i:
	if view_mode != ViewMode.ISO:
		return Vector2i(-99, 0)
	if exterior_view:
		var band := iso_view.shell_level_at(world_pos)
		return Vector2i(band, 0) if band != -99 else Vector2i(-99, 0)
	var lv := iso_view.stack.pick_level(view_level, world_pos, projection())
	var ground := sim.building.levels()[0]
	if lv == ground:
		var off := Vector2.ZERO
		for spec: Array in iso_view.shown_floors():
			if int(spec[0]) == ground:
				off = spec[1]
		var c := projection().to_cell(world_pos - off)
		if sim.building.cell(ground, floori(c.x), floori(c.y)) in BuildingData.OUTDOOR:
			return Vector2i(ground, 1)
	return Vector2i(lv, 0) if lv != view_level else Vector2i(-99, 0)


## 마우스 가둠 (기획안 9-3). 자동 테스트·헤드리스에서는 하지 않는다
func confine_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED if on else Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and sim and not sim.ended():
		confine_mouse(true)


# --- 임무형 내부 지휘 (R7c) ---

## 화면 좌표 → 칸 (지금 보는 층)
## 지금 화면 네 모서리(왼위·오른위·오른아래·왼아래)의 칸 좌표 (미니맵의 화면 범위 표시)
func _view_corners() -> Array:
	var s := get_viewport().get_visible_rect().size
	var out: Array = []
	for p: Vector2 in [Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]:
		out.append(projection().to_cell(selection._to_world(p)))
	return out


func screen_to_cell(screen_pos: Vector2) -> Vector3i:
	var c := projection().to_cell(selection._to_world(screen_pos))
	return Vector3i(floori(c.x), floori(c.y), selection.level)


## 팀 카드 클릭: 그 조 선택, 더블클릭이면 그 조가 있는 곳으로 화면 이동
func _on_team_selected(crew_id: int, focus: bool) -> void:
	selection._set_selection([crew_id] as Array[int])
	if focus:
		var c := sim.units.get_crew(crew_id)
		set_view_level(c.leader.level, _outdoors(c.leader.level, c.leader.pos))
		camera.retarget(_view_bounds(), projection().to_screen(c.leader.pos))


# --- 디브리핑 확장 (R12) ---

## 인쇄용 HTML·결과 CSV 저장 (기획안 8-1 ⑤)
func _export_report() -> void:
	if _last_report.is_empty():
		return
	var path := ReportExport.save(_last_report)
	if path == "":
		hud.show_notice("보고서를 저장하지 못했습니다")
		return
	hud.show_notice("보고서 저장: %s (CSV: %s)" % [ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(ReportExport.EXPORT_DIR + "/" + ReportExport.CSV_NAME)])
	if DisplayServer.get_name() != "headless":
		OS.shell_open(ProjectSettings.globalize_path(path))


## 리플레이 보기 표시줄 (화면 위)
func _build_view_banner() -> void:
	var l := Label.new()
	l.text = "▶ 리플레이 보기 — 명령은 받지 않습니다 (기록대로 진행). Space 재생/정지 · T 열화상(온도) · Esc 끝내기"
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color("fde68a"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.position.y = 40
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(l)


# --- 게임 메뉴·나가기 (기획안 8-3·8-4, P11-1) ---

func _build_game_menu() -> void:
	game_menu = GameMenu.new()
	add_child(game_menu)
	game_menu.help_text = hud.help_text()
	game_menu.in_mission = not sim.view_only
	game_menu.resumed.connect(func() -> void: confine_mouse(true))
	game_menu.restart_confirmed.connect(func() -> void:
		save_incomplete("처음부터 다시")
		GameManager.restart())
	game_menu.abandon_confirmed.connect(abandon)
	game_menu.main_menu_confirmed.connect(func() -> void:
		save_incomplete("메인 메뉴로 나감")
		GameManager.back_to_menu())
	game_menu.quit_confirmed.connect(func() -> void:
		save_incomplete("게임 종료")
		get_tree().quit())
	result_button = Button.new()
	result_button.text = "결과 보기 — 전소가 확실합니다"
	result_button.tooltip_text = "불붙은 곳이 모두 최성기·쇠퇴기이고 한동안 방수가 없습니다. 지금 상태를 '전소'로 확정하고 디브리핑으로 갑니다 (기획안 8-3)"
	result_button.focus_mode = Control.FOCUS_NONE
	result_button.add_theme_font_size_override("font_size", 18)
	result_button.custom_minimum_size = Vector2(360, 44)
	result_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	result_button.position.y = 120.0
	result_button.visible = false
	result_button.pressed.connect(confirm_burnout)
	hud.add_child(result_button)


## 게임 메뉴를 연다 (게임이 멈춘다). 멈춘 횟수는 기록만 한다
func open_game_menu() -> void:
	if game_menu == null or game_menu.is_open():
		return
	if sim and not sim.ended():
		sim.pause_count += 1
	game_menu.open()


## 창 닫기(X)·Alt+F4: 게임 종료 확인 창 (main이 부른다)
func request_quit() -> void:
	if game_menu:
		game_menu.open_confirm("quit")


## 임무 포기: '미완료'로 끝내고 디브리핑으로 (기록은 디브리핑이 저장)
func abandon() -> void:
	if sim and not sim.ended() and not sim.view_only:
		sim.end_activity("임무 포기", MissionEndChecker.END_INCOMPLETE)


## 끝내지 않고 나갈 때 그때까지를 '미완료'로 저장한다. 저장 경로 (이미 끝났거나 리플레이 보기면 "")
func save_incomplete(reason: String) -> String:
	if sim == null or sim.view_only or sim.ended():
		return ""
	sim.end_activity(reason, MissionEndChecker.END_INCOMPLETE)
	return Evaluator.save(Evaluator.evaluate(sim))


## '결과 보기': 전소가 확실하면 남은 계산 없이 그 자리에서 전소로 확정 (2026-11-10 결정)
func confirm_burnout() -> void:
	if sim and not sim.ended() and sim.mission_end.burnout_certain(sim.clock.tick):
		sim.end_activity("전소 확정 — 결과 보기 (건물 %d%% 소실)" % roundi(sim.mission_end.loss_ratio() * 100.0), MissionEndChecker.END_BURNOUT)


func _refresh_result_button(delta: float) -> void:
	if result_button == null or sim == null:
		return
	_result_check -= delta
	if _result_check > 0.0:
		return
	_result_check = 0.5
	# 직하층 확인 추정 구조가 새로 생기면 평면도에 반영 (P2-2)
	if sim.tactical.unit_estimates.size() != _estimates_drawn:
		_estimates_drawn = sim.tactical.unit_estimates.size()
		floor_view.queue_redraw()
	result_button.visible = not sim.ended() and not sim.view_only and sim.mission_end.burnout_certain(sim.clock.tick)
