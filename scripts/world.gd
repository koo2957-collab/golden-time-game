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
var view_mode := ViewMode.ISO
var thermal := false
var ignite_mode := false
var command_hint := ""
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
	InstructorSettings.active = true
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
	if sim == null:
		push_error("시나리오를 불러오지 못했습니다: %s" % path)
		return
	sim.play_mode = GameManager.mode
	floor_view.setup(sim.building)
	fire_view.setup(sim)
	selection.setup(sim)
	units_view.setup(sim, selection)
	iso_view.setup(sim, selection, projections[ViewMode.ISO])
	hud.setup(sim, set_view_level)
	hud.command_pressed.connect(_on_command)
	hud.command_ui.order_issued.connect(sim.issue)
	hud.command_ui.dialog_changed.connect(_on_dialog_changed)
	selection.witness_clicked.connect(hud.command_ui.open_witness)
	var tutorial := str(sim.scenario.get("tutorial", ""))
	# 튜토리얼은 안내판이 순서를 알려 주므로 멈추는 힌트 카드는 끈다
	hud.hint_ui.setup(sim, GameManager.mode == "교육" and tutorial == "")
	if tutorial != "":
		hud.tutorial_ui = TutorialUi.new()
		hud.add_child(hud.tutorial_ui)
		hud.tutorial_ui.setup(sim, selection, tutorial)
	hud.hint_ui.dialog_changed.connect(_on_dialog_changed)
	hud.command_ui.end_dialog_opened.connect(hud.hint_ui.on_end_dialog)
	EventBus.command_mode_changed.connect(_on_command_mode_changed)
	camera.setup(projection().bounds(sim.building), START_ZOOM[view_mode])
	# 지도가 도로 쪽으로 넓으므로 건물을 화면 가운데에 두고 시작한다
	var house := Rect2(sim.building.footprint(sim.building.levels()[0]))
	camera.retarget(projection().bounds(sim.building), projection().to_screen(house.get_center() + Vector2(0, 4)))
	set_view_mode(view_mode)
	set_view_level(sim.building.levels()[0])
	hud.debrief.restart_requested.connect(GameManager.restart)
	hud.debrief.menu_requested.connect(GameManager.back_to_menu)
	hud.debrief.replay_requested.connect(func(tick: int) -> void: GameManager.request_replay(sim.issued, tick, sim.rng_seed, sim.tactical.level_name, sim.realism))
	if replay_tick >= 0:
		sim.clock.paused = true
		var t := int(replay_tick * SimClock.TICK_DT)
		hud.show_notice("다시 하기: %02d:%02d 시점입니다. Space로 다시 진행하세요." % [t / 60, t % 60])
	else:
		hud.command_ui.show_dispatch()


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
	var r := Replay.begin(path, entries, int(info.get("tick", 0)), int(info.get("seed", -1)), str(info.get("automation", "")), str(info.get("realism", "")))
	if r == null:
		return null
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 28)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	$UI.add_child(label)
	while not r.step(REPLAY_CHUNK_TICKS):
		label.text = "다시 하기 준비 중… %d%%" % roundi(r.progress() * 100.0)
		await get_tree().process_frame
	label.queue_free()
	return r.sim


func _process(delta: float) -> void:
	if sim:
		sim.advance(delta)
		if sim.ended() and not hud.debrief.visible:
			_show_debrief()


## 활동이 끝나면 평가하고 결과를 저장한 뒤 디브리핑을 띄운다 (SOP 113)
func _show_debrief() -> void:
	hud.command_ui.close_all()
	selection.cancel_mode()
	var report := Evaluator.evaluate(sim)
	hud.debrief.show_report(report, Evaluator.save(report))


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
	if event.is_action_pressed("cmd_report"):
		hud.command_ui.open_command_dialog()
	elif event.is_action_pressed("cmd_org"):
		hud.command_ui.open_org_dialog()
	elif event.is_action_pressed("cmd_info"):
		hud.command_ui.open_info_dialog()
	elif event.is_action_pressed("cmd_par"):
		sim.issue(CommandOrder.make("par"))
	elif event.is_action_pressed("cmd_entry"):
		_on_command("entry")
	elif event.is_action_pressed("time_pause"):
		# 실전·악조건은 일시정지 없음 (다시 하기로 멈춰 있을 때 다시 진행하는 것만 허용)
		if realtime() and not sim.clock.paused:
			hud.show_notice("%s 난이도는 일시정지할 수 없습니다 — 현장은 멈추지 않습니다" % sim.realism)
		else:
			sim.clock.paused = not sim.clock.paused
	elif event.is_action_pressed("floor_up"):
		_step_level(1)
	elif event.is_action_pressed("floor_down"):
		_step_level(-1)
	elif event.is_action_pressed("cmd_hose"):
		_on_command("hose")
	elif event.is_action_pressed("cmd_straight"):
		_on_command("straight")
	elif event.is_action_pressed("cmd_fog"):
		_on_command("fog")
	elif event.is_action_pressed("cmd_stop"):
		_on_command("stop")
	elif event.is_action_pressed("cmd_door"):
		_on_command("door")
	elif event.is_action_pressed("cmd_search"):
		_on_command("search")
	elif event.is_action_pressed("cmd_overhaul"):
		_on_command("overhaul")
	elif event.is_action_pressed("cmd_primary"):
		_on_command("primary")
	elif event.is_action_pressed("cmd_secondary"):
		_on_command("secondary")
	elif event.is_action_pressed("cmd_shuttle"):
		for vid in selection.selected_vehicles:
			sim.issue(EquipmentCommand.make("shuttle", [], vid))
	elif event.is_action_pressed("cmd_withdraw"):
		_on_command("withdraw")
	elif event.is_action_pressed("debug_info_fog") and OS.is_debug_build():
		sim.perception.enabled = not sim.perception.enabled
		sim.replayable = false
		_update_mode_text()
	elif event.is_action_pressed("ui_cancel"):
		selection.cancel_mode()
		if ignite_mode:
			_set_ignite_mode(false)
	elif event.is_action_pressed("toggle_view"):
		set_view_mode(ViewMode.PLAN if view_mode == ViewMode.ISO else ViewMode.ISO)
	elif event.is_action_pressed("toggle_thermal"):
		set_thermal(not thermal)
	elif event.is_action_pressed("debug_fire_panel") and OS.is_debug_build():
		hud.set_debug_visible(not hud.is_debug_visible())
	elif event.is_action_pressed("debug_ignite") and OS.is_debug_build():
		_set_ignite_mode(not ignite_mode)
	else:
		for action: String in SPEED_ACTIONS:
			if event.is_action_pressed(action):
				if realtime() and SPEED_ACTIONS[action] != 1.0:
					hud.show_notice("%s 난이도는 1배속 고정입니다" % sim.realism)
				else:
					sim.clock.speed = SPEED_ACTIONS[action]


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
	camera.retarget(projection().bounds(sim.building), projection().to_screen(center_cell))
	_update_mode_text()


func set_view_level(level: int) -> void:
	if not sim.building.has_level(level):
		return
	view_level = level
	floor_view.set_level(level)
	fire_view.level = level
	units_view.level = level
	iso_view.level = level
	selection.level = level
	EventBus.view_floor_changed.emit(level)


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
	_update_mode_text()


## 창이 열려 있는 동안 게임 시간을 멈춘다
## 실전·악조건: 1배속 고정, 일시정지 없음, 창이 떠도 시간 진행 (기획안 3-3, 8장)
func realtime() -> bool:
	return sim != null and sim.realism in ["실전", "악조건"]


func _on_dialog_changed(open: bool) -> void:
	# 실전·악조건에서는 출동 지령(도착 전)만 멈춘다
	if realtime() and not hud.command_ui.dispatch_visible():
		if not open and _paused_before_dialog == false:
			sim.clock.paused = false
		return
	if open:
		_paused_before_dialog = sim.clock.paused
		sim.clock.paused = true
	else:
		sim.clock.paused = _paused_before_dialog


## 명령 패널 버튼 / 단축키 (R 진입 명령, H 수관 연장, A 직사 방수, S 분무 방수, D 방수 중지)
func _on_command(id: String) -> void:
	if selection.selected.is_empty():
		return
	match id:
		"entry":
			var squads: Array[int] = []
			for crew_id in selection.selected:
				var squad_id := sim.units.get_crew(crew_id).squad_id
				if not squad_id in squads and not sim.command.can_enter(squad_id):
					squads.append(squad_id)
			if squads.is_empty():
				return
			if sim.command.effective_strategy() == CommandSystem.Strategy.DEFENSIVE:
				hud.command_ui.confirm_defensive_entry(squads)
			else:
				sim.issue(CommandOrder.make("entry", squads))
		"hose":
			selection.begin_mode(SelectionController.Mode.HOSE)
		"straight":
			selection.begin_mode(SelectionController.Mode.STRAIGHT)
		"fog":
			selection.begin_mode(SelectionController.Mode.FOG)
		"stop":
			var spraying := selection.crews_spraying()
			if not spraying.is_empty():
				sim.issue(EquipmentCommand.make("stop", spraying))
		"door":
			selection.begin_mode(SelectionController.Mode.DOOR)
		"search":
			selection.begin_mode(SelectionController.Mode.SEARCH)
		"overhaul":
			selection.begin_mode(SelectionController.Mode.OVERHAUL)
		# 분대 명령칸 (고수준 명령)
		"primary":
			var lead := sim.units.squad_of_crew(selection.selected[0]) if not selection.selected.is_empty() else null
			selection.begin_mode(SelectionController.Mode.TREAT if lead and lead.type == "구급대" else SelectionController.Mode.PRIMARY)
		"treat":
			selection.begin_mode(SelectionController.Mode.TREAT)
		"air_mat":
			selection.begin_mode(SelectionController.Mode.AIR_MAT)
		"transport":
			selection.begin_mode(SelectionController.Mode.TRANSPORT)
		"attack":
			selection.begin_mode(SelectionController.Mode.ATTACK)
		"search_auto":
			selection.begin_mode(SelectionController.Mode.SEARCH_AUTO)
		"exterior":
			selection.begin_mode(SelectionController.Mode.EXTERIOR)
		"rescue":
			selection.begin_mode(SelectionController.Mode.RESCUE)
		"secondary":
			var first := sim.units.squad_of_crew(selection.selected[0])
			if first.type == "구급대":
				selection.begin_mode(SelectionController.Mode.TRANSPORT)
			else:
				selection.begin_mode(SelectionController.Mode.RESCUE if first.type == "구조대" else SelectionController.Mode.EXTERIOR)
		"withdraw":
			sim.issue(TacticalCommand.make("withdraw", selection.selected))


func _update_mode_text() -> void:
	var modes: PackedStringArray = ["입체" if view_mode == ViewMode.ISO else "상황판"]
	if thermal:
		modes.append("열화상")
	if not sim.perception.enabled:
		modes.append("정보 안개 꺼짐(개발용)")
	if ignite_mode:
		modes.append("발화: 클릭할 위치 선택")
	if command_hint != "":
		modes.append(command_hint)
	hud.mode_text = " · ".join(modes)


func _step_level(direction: int) -> void:
	var levels := sim.building.levels()
	var i := clampi(levels.find(view_level) + direction, 0, levels.size() - 1)
	set_view_level(levels[i])
