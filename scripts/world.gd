extends Node2D
## 게임 월드 루트. 시뮬레이션(SimWorld)을 소유하고 화면 노드들을 연결한다.
## 화면은 두 가지이며 Tab으로 전환한다.
##   입체(기본): Iso/IsoView 하나가 도면·화염·연기층·대원을 모두 그린다.
##   상황판: Map(도면) / Effects(화염·연기) / Units(대원)
## 선택·이동·카메라는 현재 화면의 좌표 변환(ViewProjection)을 따른다.

enum ViewMode { ISO, PLAN }

const SCENARIO_PATH := "res://data/scenarios/dev_house_fire.json"
const SPEED_ACTIONS := {"time_speed_1x": 1.0, "time_speed_2x": 2.0, "time_speed_4x": 4.0}
const START_ZOOM := {ViewMode.ISO: 0.9, ViewMode.PLAN: 1.4}

var sim: SimWorld
var view_level := 1
var view_mode := ViewMode.ISO
var thermal := false
var ignite_mode := false
var command_hint := ""
var projections := {ViewMode.ISO: IsoProjection.new(), ViewMode.PLAN: PlanProjection.new()}

@onready var floor_view: FloorPlanView = $Map/FloorPlanView
@onready var fire_view: FireView = $Effects/FireView
@onready var units_view: UnitsView = $Units/UnitsView
@onready var iso_view: IsoView = $Iso/IsoView
@onready var selection: SelectionController = $SelectionController
@onready var camera: RtsCamera = $Camera2D
@onready var hud: Hud = $UI/HUD


func _ready() -> void:
	sim = SimWorld.from_scenario(SCENARIO_PATH)
	if sim == null:
		push_error("시나리오를 불러오지 못했습니다: %s" % SCENARIO_PATH)
		return
	floor_view.setup(sim.building)
	fire_view.setup(sim)
	selection.setup(sim)
	units_view.setup(sim, selection)
	iso_view.setup(sim, selection, projections[ViewMode.ISO])
	hud.setup(sim, set_view_level)
	hud.command_pressed.connect(_on_command)
	EventBus.command_mode_changed.connect(_on_command_mode_changed)
	camera.setup(projection().bounds(sim.building), START_ZOOM[view_mode])
	set_view_mode(view_mode)
	set_view_level(sim.building.levels()[0])


func _process(delta: float) -> void:
	if sim:
		sim.advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event.is_action_pressed("time_pause"):
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
	elif event.is_action_pressed("debug_info_fog") and OS.is_debug_build():
		sim.perception.enabled = not sim.perception.enabled
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
	_set_ignite_mode(false)


func _on_command_mode_changed(hint: String) -> void:
	command_hint = hint
	_update_mode_text()


## 명령 패널 버튼 / 단축키 (H 수관 연장, A 직사 방수, S 분무 방수, D 방수 중지)
func _on_command(id: String) -> void:
	if selection.selected.is_empty():
		return
	match id:
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
