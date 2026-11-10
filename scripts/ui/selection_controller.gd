class_name SelectionController
extends Node2D
## 마우스 선택과 명령.
## - 좌클릭: 조·차량 선택 / Shift+좌클릭: 추가·해제 / 드래그: 범위 선택
## - 더블클릭: 같은 출동대 전체 선택
## - 우클릭(조): 이동 (방수 중이면 방수를 멈추고 이동) / 펌프차 우클릭: 그 펌프차에서 수관 연장
##              발견한 요구조자·쓰러진 대원 우클릭: 구조 / 닫힌 문 우클릭: 개방(잠긴 문은 파괴)
## - 우클릭(차량): 이동, 소화전 점령(소화전 우클릭), 급수(물탱크차로 펌프차 우클릭)
## - 현장지휘관 클릭: 지휘관 선택 → 우클릭: 이동 (건물 안으로는 들어가지 않는다)
## - 관계인 클릭: 진술 창 (witness_clicked)
## - 숫자 1~9: 팀 초상 줄 순서의 조 선택 (P10-1)
## - 대상 지정 명령(begin_mode): 수관 연장(펌프차 클릭), 직사·분무 방수(목표 클릭). 우클릭·Esc로 취소
## 선택 단위는 조(2인 1조)와 차량이며, 현재 보고 있는 층의 대원만 선택된다.
## 좌표 변환은 projection(상황판/입체)을 따른다.

enum Mode { NONE, ATTACK, SEARCH_AUTO, EXTERIOR, TREAT, TRANSPORT, WAYPOINT, MONITOR, PPV, VEHICLE_CONNECT, VEHICLE_MOVE, ZONE_SAFE, ZONE_CASUALTY, ZONE_LINE, TRIAGE_POST, OBSERVE, ENTRY_POINT }

## 관계인을 클릭했을 때 (world가 진술 창을 연다)
signal witness_clicked(index: int)
## 화면 알림 요청 (HUD가 띄운다)
signal notice(text: String)
## 지도에서 조를 좌클릭함 → 원형 메뉴 (기획안 9-1, P10-2)
signal crew_menu(crew_id: int, screen_pos: Vector2)
## 단면 보기에서 아래층(보이기만 하는 층)을 눌렀다 — 그 층을 지금 층으로 (R17)
signal floor_clicked(level: int)
## 진입 지시 4단계 (P4-2): 진입구를 골랐다 → 그 층 단면으로
signal entry_chosen(level: int)
## 진입구 고르기를 시작했다 → 바깥(진입구가 있는 층) 보기로
signal entry_mode_started(level: int)
## 임무 목표를 골랐다 → 임무 창 (임무·조건·지시)
signal mission_target(crew_ids: Array[int], target: Vector3i, kind: String, via: Vector3i, screen_pos: Vector2)
## 건물 안 조를 고른 채 가까운 문을 눌렀다 → 문 앞 휠 (P4-2)
signal door_menu(crew_id: int, door_index: int, screen_pos: Vector2)

const DRAG_THRESHOLD_PX := 6.0
## 마우스를 올린 조 (기획안 9-3: 잡힐 조의 윤곽이 빛나고 이름이 뜬다). 없으면 -1
var hover_crew := -1
var _last_pick := -1
var _last_pick_world := Vector2(-99999, -99999)
var _vp: ViewParams
const MARKER_DURATION_MS := 500.0
## 입체 화면에서 차체를 클릭했는지 볼 때 함께 확인하는 높이 (m)
const VEHICLE_PICK_HEIGHT_M := 1.0
const HYDRANT_PICK_HEIGHT_M := 0.6
const MODE_HINTS := {
	Mode.ATTACK: "화점진압: 방·층을 클릭 (수관 연장·진입·화점 탐색·방수·잔불 확인, 초진 뒤 불이 안 보이는 방은 잔불정리)",
	Mode.SEARCH_AUTO: "인명검색: 방·층을 클릭 (문 개방·방별 탐색·발견하면 보고 후 구조해 집결지로)",
	Mode.EXTERIOR: "경계: 창·개구부·인접 건물 쪽을 클릭 (관창 배치, 불이 다가오면 방수)",
	Mode.TREAT: "처치: 구조된 환자를 클릭 (구급대가 가서 응급처치)",
	Mode.TRANSPORT: "이송: 처치한 환자를 클릭 (들것으로 구급차에 태워 병원으로)",
	Mode.WAYPOINT: "경유지: 본 적 있는 곳을 클릭 (건물 안 조에게는 무전으로 전달)",
	Mode.MONITOR: "방수포: 바깥 창·문을 클릭 — 진입대원이 있는 방에는 쓰지 않는다 (SOP 207-1.1)",
	Mode.PPV: "송풍기 양압배연: 바깥 출입문을 클릭 — 먼저 반대편 창(배출구)을 확보한다",
	Mode.ZONE_SAFE: "안전구역: 건물 밖을 끌어서 사각형 (한 번 클릭하면 그 자리에 기본 크기) — 낙하물 위험구역은 피한다",
	Mode.ZONE_CASUALTY: "환자 집결지: 안전구역 안을 클릭 (구조한 사람을 여기로 옮긴다)",
	Mode.ZONE_LINE: "진입통제선: 선의 두 끝을 차례로 클릭",
	Mode.ENTRY_POINT: "진입구를 고르세요 (Esc 취소) — 밝은 표시만 고를 수 있다",
	Mode.OBSERVE: "구조자 관찰: 구조된 사람을 클릭 — 곁에 서 있으면 구급대가 올 때까지 악화가 느려진다",
	Mode.TRIAGE_POST: "분류소 설치: 안전구역 안을 클릭 — 구급대가 가서 차린다 (환자 집결지를 대신)",
	Mode.VEHICLE_CONNECT: "급수 연결: 소화전·송수구(펌프차) 또는 펌프차(물탱크차)를 클릭",
	Mode.VEHICLE_MOVE: "자리 옮기기: 차를 옮길 곳을 클릭",
}
## 창가 구조대상자 아래 이 거리(칸) 안의 땅을 우클릭하면 인명구조매트
const MAT_PICK_CELLS := 6.0
## 비상용승강기 승강장에서 이 거리(칸) 안의 조만 승강기를 탄다
const ELEVATOR_PICK_CELLS := 3.0
## 요구조자·쓰러진 대원을 클릭으로 고를 때 허용 반경 (px)
const CASUALTY_PICK_PX := 20.0
## 입체 화면에서 닫힌 문 블록을 클릭했는지 볼 때 함께 확인하는 높이 (m)
const DOOR_PICK_HEIGHT_M := 0.3

var sim: SimWorld
var level := 1
var projection: ViewProjection = PlanProjection.new()
var selected: Array[int] = []
var selected_vehicles: Array[int] = []
var commander_selected := false
var mode := Mode.NONE
## 방수포 모드에서 쓸 펌프차 (R11)
var monitor_vehicle := -1
## 설정되어 있으면 좌클릭을 선택 대신 이 함수로 넘긴다 (셀 좌표 Vector2i). 개발용 발화 모드 등에 쓴다.
var click_override := Callable()
## 설정되어 있으면 빈 곳 클릭 때 화면 위치로 맞은 층을 묻는다 (단면 보기의 아래층, R17). (world_pos) -> level
var level_picker := Callable()


var _pressing := false
var _dragging := false
var _skip_release := false
var _press_screen := Vector2.ZERO
var _press_world := Vector2.ZERO
var _drag_rect := Rect2()
## 구역 지정 중: 안전구역 끌기 시작 칸, 진입통제선 첫 점 (-1 = 아직)
var _zone_from := Vector2(-1, -1)
## 팀 초상 줄 순서 (TeamStrip.crews) — 숫자키 1~9
var team_order: Callable
## 진입 지시 (P4-2): 고를 임무, 고른 진입구, 마우스 아래 칸까지 예상 경로
var pending_kind := ""
var chosen_entry: EntryPoints.Entry = null
var _hover_entry: EntryPoints.Entry = null
var _preview: Array[Vector3i] = []
var _preview_to := Vector3i(-1, -1, -1)
var _mouse_screen := Vector2.ZERO
## 진입구를 고를 때 클릭 허용 거리 (칸)
const ENTRY_PICK_CELLS := 3.0
## 문 앞 휠: 조가 문에서 이 거리(칸) 안 (기획안: 2타일)
const DOOR_WHEEL_CELLS := 2.5
var _zone_to := Vector2(-1, -1)
var _marker_world := Vector2.ZERO
var _marker_start_ms := -1.0


func setup(p_sim: SimWorld) -> void:
	sim = p_sim


func begin_mode(p_mode: Mode) -> void:
	mode = p_mode
	EventBus.command_mode_changed.emit(MODE_HINTS.get(mode, ""))


func cancel_mode() -> void:
	_zone_from = Vector2(-1, -1)
	if mode in [Mode.ENTRY_POINT, Mode.ATTACK, Mode.SEARCH_AUTO]:
		_preview.clear()
		_preview_to = Vector3i(-1, -1, -1)
		_hover_entry = null
	if mode != Mode.NONE:
		mode = Mode.NONE
		EventBus.command_mode_changed.emit("")


## 선택한 조 중 수관을 가진 조
func crews_with_hose() -> Array[int]:
	var out: Array[int] = []
	for id in selected:
		if sim.water.hose_of_crew(id):
			out.append(id)
	return out


## 선택한 조 중 방수 중(또는 방수 위치로 이동 중)인 조
func crews_spraying() -> Array[int]:
	var out: Array[int] = []
	for id in crews_with_hose():
		if sim.water.hose_of_crew(id).flowing:
			out.append(id)
	return out


func _process(_delta: float) -> void:
	if _marker_start_ms >= 0.0:
		queue_redraw()
	# 올리면 미리 보임: 잡힐 조의 윤곽과 이름 (기획안 9-3)
	if sim != null:
		var mouse_world := _to_world(get_viewport().get_mouse_position())
		var h := -1
		var hits := crews_under(mouse_world)
		if not hits.is_empty():
			h = hits[0]
		if h != hover_crew:
			hover_crew = h
			queue_redraw()
		elif h >= 0:
			queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventMouseButton:
		_handle_button(event)
	elif event is InputEventMouseMotion and mode in [Mode.ENTRY_POINT, Mode.ATTACK, Mode.SEARCH_AUTO]:
		_mouse_screen = event.position
		_update_preview(_to_world(event.position))
	elif event is InputEventMouseMotion and _zone_from.x >= 0:
		_zone_to = projection.to_cell(_to_world(event.position))
		queue_redraw()
	elif event is InputEventMouseMotion and _pressing:
		if (event.position - _press_screen).length() > DRAG_THRESHOLD_PX:
			_dragging = true
		if _dragging:
			_drag_rect = Rect2(_press_world, Vector2.ZERO).expand(_to_world(event.position))
			queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_group_key(event)


func _handle_button(event: InputEventMouseButton) -> void:
	var world_pos := _to_world(event.position)
	if event.is_action_pressed("select") and click_override.is_valid():
		click_override.call(Vector2i(projection.to_cell(world_pos).floor()))
		get_viewport().set_input_as_handled()
		return
	if mode == Mode.ENTRY_POINT and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick_entry(world_pos)
		get_viewport().set_input_as_handled()
		return
	if mode in [Mode.ZONE_SAFE, Mode.ZONE_LINE] and _zone_click(event, world_pos):
		get_viewport().set_input_as_handled()
		return
	if mode != Mode.NONE and (event.is_action_pressed("select") or event.is_action_pressed("command")):
		if event.is_action_pressed("select"):
			_complete_mode(world_pos)
		cancel_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("select"):
		if event.double_click:
			var crew_id := _crew_at(world_pos)
			if crew_id >= 0:
				var squad := sim.units.squad_of_crew(crew_id)
				var ids: Array[int] = []
				for c in squad.crews:
					ids.append(c.id)
				_set_selection(_merge(ids) if event.shift_pressed else ids, [])
			_skip_release = true
		else:
			_pressing = true
			_press_screen = event.position
			_press_world = world_pos
		get_viewport().set_input_as_handled()
	elif event.is_action_released("select") and (_pressing or _skip_release):
		if _skip_release:
			_skip_release = false
		elif _dragging:
			_box_select(event.shift_pressed)
		else:
			_click_select(world_pos, event.shift_pressed, event.position)
		_pressing = false
		_dragging = false
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("command"):
		# 우클릭은 이동·상황 행동만 (원형 메뉴는 좌클릭, 기획안 9-1)
		_issue_right_click(world_pos)
		get_viewport().set_input_as_handled()


## 숫자키 1~9: 팀 초상 줄 순서의 조를 고른다 (P10-1). 질문 카드가 떠 있으면 1~4는 카드가 먼저 받는다
func _handle_group_key(event: InputEventKey) -> void:
	if event.keycode < KEY_1 or event.keycode > KEY_9 or event.ctrl_pressed or not team_order.is_valid():
		return
	var order: Array = team_order.call()
	var n := event.keycode - KEY_1
	if n < order.size():
		_set_selection([int(order[n])] as Array[int], [] as Array[int])
	get_viewport().set_input_as_handled()


func _click_select(world_pos: Vector2, add: bool, screen_pos := Vector2(-1, -1)) -> void:
	if not add and _commander_at(world_pos):
		_set_selection([], [], true)
		return
	var witness := _witness_at(world_pos)
	if not add and witness >= 0:
		witness_clicked.emit(witness)
		return
	var crew_id := _crew_at(world_pos)
	# 문 앞 휠: 다른 대원이 잡히면 그 대원 선택이 먼저 (기획안 9-3 우선순위). 이미 고른 그 조로 문을 누르면 휠
	if not add and (crew_id < 0 or (selected.size() == 1 and selected[0] == crew_id)) and _door_wheel(world_pos, screen_pos):
		return
	var vehicle_id := -1 if crew_id >= 0 else _vehicle_at(world_pos)
	if crew_id < 0 and vehicle_id < 0:
		# 아래층은 보이기만 한다 — 누르면 그 층이 지금 층이 된다 (선택은 그대로 둔다)
		if not add and level_picker.is_valid():
			var picked: int = level_picker.call(world_pos)
			if picked != level:
				floor_clicked.emit(picked)
				return
		if not add:
			_set_selection([], [])
		return
	if not add:
		if crew_id >= 0:
			_set_selection([crew_id], [])
			# 지도에서 조를 누르면 그 자리에 원형 메뉴 (명령 카드와 같은 항목, 기획안 9-1)
			if screen_pos.x >= 0.0 and not sim.view_only and not sim.units.get_crew(crew_id).leader.incapacitated:
				crew_menu.emit(crew_id, screen_pos)
		else:
			_set_selection([], [vehicle_id])
		return
	var crews := selected.duplicate()
	var vehicles := selected_vehicles.duplicate()
	_toggle(crews if crew_id >= 0 else vehicles, crew_id if crew_id >= 0 else vehicle_id)
	_set_selection(crews, vehicles)


## 범위 안의 조를 고른다. 조가 하나도 없으면 범위 안의 차량을, 차량도 없으면 현장지휘관을 고른다
## (지휘관 이동은 대원 이동과 다른 명령이라 조·차량과 섞어 고르지 않는다).
func _box_select(add: bool) -> void:
	var ids: Array[int] = []
	for c in sim.units.crews:
		for ff in c.members():
			if ff.level == level and not ff.aboard and _drag_rect.has_point(projection.to_screen(ff.pos)):
				ids.append(c.id)
				break
	var vehicles: Array[int] = []
	if ids.is_empty() and level == sim.building.levels()[0]:
		for v in sim.units.vehicles:
			if not v.away and _drag_rect.has_point(projection.to_screen(v.pos)):
				vehicles.append(v.id)
	if ids.is_empty() and vehicles.is_empty() and not add:
		var c := sim.command.commander
		if c.level == level and _drag_rect.has_point(projection.to_screen(c.pos)):
			_set_selection([], [], true)
			return
	if add:
		_set_selection(_merge(ids), _merge_vehicles(vehicles))
	else:
		_set_selection(ids, vehicles)


func _issue_right_click(world_pos: Vector2) -> void:
	var cell_f := projection.to_cell(world_pos)
	var cell := Vector2i(cell_f.floor())
	var marker_cell := Vector2(cell) + Vector2(0.5, 0.5)
	if commander_selected:
		sim.issue(CommandOrder.make("commander_move", [], 0, Vector3i(cell.x, cell.y, level)))
		_marker_world = projection.to_screen(marker_cell)
		_marker_start_ms = Time.get_ticks_msec()
		return
	if selected.is_empty() and selected_vehicles.is_empty():
		return
	if not selected_vehicles.is_empty():
		_issue_vehicle_click(world_pos)
	if not selected.is_empty():
		# 건물 안 조는 지도 우클릭 이동을 막는다 — 원형 메뉴(무전 지시)로만 (기획안 9-1 내부 조작)
		if sim.command.interior.enabled and selected.any(func(id: int) -> bool: return sim.command.interior.crew_inside(id)):
			notice.emit("건물 안 조는 원형 메뉴로 지시합니다 — 조를 클릭 → 임무, 또는 A 대기 ▸ E 여기로 (문은 문을 클릭)")
			return
		_issue_crew_right_click(world_pos)


## 고른 차량에게: 소화전·송수구·펌프차를 누르면 연결, 아니면 그곳으로 이동 (우클릭·명령 카드 급수 연결)
func _issue_vehicle_click(world_pos: Vector2) -> void:
	var cell_f := projection.to_cell(world_pos)
	var cell := Vector2i(cell_f.floor())
	var hydrant := sim.water.hydrant_near(cell_f, 1.5)
	if hydrant < 0:
		# 입체 화면에서 소화전 기둥 윗부분을 누른 경우
		hydrant = sim.water.hydrant_near(projection.to_cell_at(world_pos, HYDRANT_PICK_HEIGHT_M), 1.5)
	var target_vehicle := _vehicle_at(world_pos)
	var on_fdc := sim.building.has_standpipe() and cell_f.distance_to(Vector2(sim.building.fdc) + Vector2(0.5, 0.5)) <= 1.5
	for vid in selected_vehicles:
		var v := sim.units.get_vehicle(vid)
		if on_fdc and v.is_pump():
			sim.issue(EquipmentCommand.make("fdc", [], vid))
		elif hydrant >= 0:
			sim.issue(EquipmentCommand.make("hydrant", [], vid, hydrant))
		elif target_vehicle >= 0 and target_vehicle != vid and v.transfer_lpm > 0.0:
			sim.issue(EquipmentCommand.make("supply", [], vid, target_vehicle))
		else:
			sim.issue(EquipmentCommand.make("vehicle_move", [], vid, -1, Vector3i(cell.x, cell.y, 1)))
	_marker_world = projection.to_screen(Vector2(cell) + Vector2(0.5, 0.5))
	_marker_start_ms = Time.get_ticks_msec()


## 고른 조 우클릭: 펌프차면 수관, 아니면 이동·상황 행동
func _issue_crew_right_click(world_pos: Vector2) -> void:
	var cell_f := projection.to_cell(world_pos)
	var cell := Vector2i(cell_f.floor())
	var marker_cell := Vector2(cell) + Vector2(0.5, 0.5)
	var pump := _vehicle_at(world_pos)
	var without_hose: Array[int] = []
	for id in selected:
		if sim.water.hose_of_crew(id) == null:
			without_hose.append(id)
	var door := _door_at(world_pos)
	var window: Opening = null
	var any_open := _door_at(world_pos, true)
	if any_open and any_open.kind == Opening.Kind.WINDOW:
		window = any_open
	var casualty := _casualty_at(world_pos)
	var patient := _patient_at(world_pos)
	if patient >= 0 and sim.ems.is_ems_crew(selected[0]):
		var p := sim.ems.patient_of(patient)
		sim.issue(EquipmentCommand.make("ems_transport" if p.stage == EmsSystem.Stage.TREATED else "ems_treat", selected, -1, patient))
		marker_cell = sim.rescue.victims[patient].pos
	elif casualty.x >= 0:
		sim.issue(EquipmentCommand.make("rescue" if casualty.x == 0 else "rescue_ff", selected, -1, casualty.y))
	elif _outlet_at(cell_f) >= 0 and not without_hose.is_empty():
		# 방수구 우클릭: 수관이 없는 조는 방수구에서 수관 연장 (연결송수관)
		sim.issue(EquipmentCommand.make("hose_outlet", without_hose, -1, _outlet_at(cell_f)))
	elif level == 1 and sim.gas.open and sim.gas.known(sim.command.survey) and sim.gas.valve_near(cell_f):
		# 가스 밸브 우클릭: 첫 조가 가서 차단 (SOP 214-2.2)
		sim.issue(EquipmentCommand.make("gas_off", selected))
		marker_cell = Vector2(sim.gas.valve) + Vector2(0.5, 0.5)
	elif _mat_spot(cell):
		# 창가 구조대상자 아래 땅 우클릭: 인명구조매트 (SOP 213-2.4.3)
		sim.issue(EquipmentCommand.make("air_mat", selected, -1, -1, Vector3i(cell.x, cell.y, 1)))
	elif window and not window.broken and not window.is_open:
		# 창 우클릭: 깨서 연다 (배연 배기구·진입구 개척)
		sim.issue(EquipmentCommand.make("door_open", selected, -1, -1, Vector3i(window.cells[0].x, window.cells[0].y, level)))
		marker_cell = Vector2(window.cells[0]) + Vector2(0.5, 0.5)
	elif sim.elevator.available() and level != sim.units.get_crew(selected[0]).leader.level \
			and sim.units.get_crew(selected[0]).leader.pos.distance_to(Vector2(sim.elevator.cell) + Vector2(0.5, 0.5)) <= ELEVATOR_PICK_CELLS:
		# 비상용승강기 앞에 있는 조로 다른 층을 우클릭: 승강기로 그 층까지 (SOP 222 — 화재층 2개층 아래까지)
		sim.issue(EquipmentCommand.make("elevator", selected, -1, level))
	elif door and not door.is_open:
		# 닫힌 문 우클릭: 문 개방 (잠긴 문은 파괴)
		sim.issue(EquipmentCommand.make("door_open", selected, -1, -1, Vector3i(door.cells[0].x, door.cells[0].y, level)))
		marker_cell = Vector2(door.cells[0]) + Vector2(0.5, 0.5)
	elif pump >= 0 and sim.units.get_vehicle(pump).is_pump() and not without_hose.is_empty():
		# 펌프차 우클릭: 수관이 없는 조는 이 펌프차에서 수관 연장
		sim.issue(EquipmentCommand.make("hose", without_hose, pump))
		marker_cell = sim.units.get_vehicle(pump).pos
	else:
		var target := sim.pathfinder.nearest_walkable(level, cell)
		if target != Pathfinder.NO_CELL:
			# 스타크래프트처럼: 이동 명령은 방수를 멈춘다
			var spraying := crews_spraying()
			if not spraying.is_empty():
				sim.issue(EquipmentCommand.make("stop", spraying))
			if sim.lifeline.enabled and not sim.building.cell(level, target.x, target.y) in BuildingData.OUTDOOR:
				# 유도로프를 쓰는 판(지하·시계 0 구역)에서 건물 안으로 이동: 유도로프를 깔며 간다 (SOP 217)
				sim.issue(EquipmentCommand.make("lifeline", [selected[0]] as Array[int], -1, -1, Vector3i(target.x, target.y, level)))
				if selected.size() > 1:
					sim.issue(MoveCommand.new(selected.slice(1), Vector3i(target.x, target.y, level)))
			else:
				sim.issue(MoveCommand.new(selected, Vector3i(target.x, target.y, level)))
			marker_cell = Vector2(target) + Vector2(0.5, 0.5)
	_marker_world = projection.to_screen(marker_cell)
	_marker_start_ms = Time.get_ticks_msec()


## 안전구역(끌기)·진입통제선(두 번 클릭). 처리했으면 true
func _zone_click(event: InputEventMouseButton, world_pos: Vector2) -> bool:
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_mode()
		return true
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	var cell := projection.to_cell(world_pos)
	if mode == Mode.ZONE_SAFE:
		if event.pressed:
			_zone_from = cell
			_zone_to = cell
		elif _zone_from.x >= 0:
			var a := Vector2i(_zone_from.floor())
			var b := Vector2i(cell.floor())
			var r := Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), (a - b).abs() + Vector2i.ONE)
			if r.size.x <= 2 and r.size.y <= 2:
				r = sim.zones.default_safe(a)
			sim.issue(CommandOrder.make("zone", [], 0, Vector3i.ZERO, {"kind": "safe", "rect": [r.position.x, r.position.y, r.size.x, r.size.y]}))
			cancel_mode()
		return true
	# 진입통제선: 첫 클릭은 한 끝, 두 번째 클릭으로 지정
	if not event.pressed:
		return true
	if _zone_from.x < 0:
		_zone_from = cell
		_zone_to = cell
		return true
	sim.issue(CommandOrder.make("zone", [], 0, Vector3i.ZERO, {"kind": "line", "a": [_zone_from.x, _zone_from.y], "b": [cell.x, cell.y]}))
	cancel_mode()
	return true


func _complete_mode(world_pos: Vector2) -> void:
	match mode:
		Mode.ZONE_CASUALTY:
			var c := Vector2i(projection.to_cell(world_pos).floor())
			sim.issue(CommandOrder.make("zone", [], 0, Vector3i.ZERO, {"kind": "casualty", "cell": [c.x, c.y]}))
		Mode.OBSERVE:
			var pid := _patient_at(world_pos)
			if pid >= 0 and not selected.is_empty():
				var vp := Vector2i(sim.rescue.victims[pid].pos.floor())
				var near := sim.pathfinder.nearest_walkable(1, vp + Vector2i(1, 0))
				if near != Pathfinder.NO_CELL:
					sim.issue(MoveCommand.new([selected[0]] as Array[int], Vector3i(near.x, near.y, 1)))
		Mode.TRIAGE_POST:
			var tc := Vector2i(projection.to_cell(world_pos).floor())
			var ems_ids: Array[int] = []
			for id in selected:
				if sim.ems.is_ems_crew(id):
					ems_ids.append(id)
			if not ems_ids.is_empty():
				sim.issue(EquipmentCommand.make("triage_post", ems_ids, -1, -1, Vector3i(tc.x, tc.y, 1)))
		Mode.VEHICLE_CONNECT:
			if not selected_vehicles.is_empty():
				_issue_vehicle_click(world_pos)
		Mode.VEHICLE_MOVE:
			var cell := Vector2i(projection.to_cell(world_pos).floor())
			for vid in selected_vehicles:
				sim.issue(EquipmentCommand.make("vehicle_move", [], vid, -1, Vector3i(cell.x, cell.y, 1)))
		Mode.ATTACK, Mode.SEARCH_AUTO, Mode.EXTERIOR:
			if not selected.is_empty():
				var cell := Vector2i(projection.to_cell(world_pos).floor())
				var target := Vector3i(cell.x, cell.y, level)
				var attack: Array[int] = []
				var search: Array[int] = []
				for id in selected:
					if mode == Mode.SEARCH_AUTO:
						search.append(id)
					else:
						attack.append(id)
				if mode == Mode.EXTERIOR:
					sim.issue(TacticalCommand.make("exterior", selected, target))
				elif mode == Mode.ATTACK and _overhaul_room(target):
					# 초진 뒤 불이 보이지 않는 방에 화점진압 → 잔불정리 (화점진압 = 진압 → 잔불 확인, 기획안 9-1)
					sim.issue(EquipmentCommand.make("overhaul", selected, -1, -1, target))
					notice.emit("초진 뒤 불이 보이지 않는 방 → 잔불정리 (열화상으로 불씨를 찾아 정리)")
				else:
					# 4단계: 임무 창 (임무·조건을 고르고 '지시'). 본 적 없는 방은 층 단위 (기획안 9-1)
					var via := chosen_entry.outside if chosen_entry else Vector3i(-1, -1, -1)
					mission_target.emit(selected.duplicate(), target, "attack" if mode == Mode.ATTACK else "search", via, _mouse_screen)
					chosen_entry = null
				_marker_world = projection.to_screen(Vector2(cell) + Vector2(0.5, 0.5))
				_marker_start_ms = Time.get_ticks_msec()
		Mode.WAYPOINT:
			if not selected.is_empty():
				var cell := Vector2i(projection.to_cell(world_pos).floor())
				var target := sim.pathfinder.nearest_walkable(level, cell)
				if target != Pathfinder.NO_CELL:
					sim.issue(MoveCommand.new(selected, Vector3i(target.x, target.y, level)))
					_marker_world = projection.to_screen(Vector2(target) + Vector2(0.5, 0.5))
					_marker_start_ms = Time.get_ticks_msec()
		Mode.TREAT, Mode.TRANSPORT:
			var patient := _patient_at(world_pos)
			if patient >= 0 and not selected.is_empty():
				sim.issue(EquipmentCommand.make("ems_treat" if mode == Mode.TREAT else "ems_transport", selected, -1, patient))
		Mode.MONITOR:
			var win := _door_at(world_pos, true)
			if win and monitor_vehicle >= 0:
				sim.issue(EquipmentCommand.make("monitor", [], monitor_vehicle, -1, Vector3i(win.cells[0].x, win.cells[0].y, win.level)))
		Mode.PPV:
			var door := _door_at(world_pos)
			if door and not selected.is_empty():
				sim.issue(EquipmentCommand.make("ppv", [selected[0]] as Array[int], -1, -1, Vector3i(door.cells[0].x, door.cells[0].y, door.level)))



# --- 진입 지시 4단계 (P4-2, 기획안 9-1) ---

## 고른 조가 모두 밖에 있으면 진입구부터 고른다 (이미 들어간 조는 바로 목표 — 구역 변경)
func begin_mission(kind: String) -> void:
	pending_kind = kind
	chosen_entry = null
	var outside := not selected.is_empty()
	for id in selected:
		if sim.command.interior.crew_inside(id):
			outside = false
	if outside and sim.command.interior.enabled and sim.entries and not sim.entries.list.is_empty():
		begin_mode(Mode.ENTRY_POINT)
		entry_mode_started.emit(sim.entries.list[0].level)
	else:
		begin_mode(Mode.ATTACK if kind == "attack" else Mode.SEARCH_AUTO)


## 진입구 고르기: 진입구만 고를 수 있다. 고르면 그 층 단면 보기로 바꾸고 목표 고르기
func _pick_entry(world_pos: Vector2) -> void:
	var e := sim.entries.nearest(projection.to_cell(world_pos), level, ENTRY_PICK_CELLS)
	if e == null:
		notice.emit("진입구(밝은 표시)를 고르세요 — 공동현관·계단실 입구 등 바깥 출입문")
		return
	chosen_entry = e
	entry_chosen.emit(e.level)
	begin_mode(Mode.ATTACK if pending_kind == "attack" else Mode.SEARCH_AUTO)
	EventBus.command_mode_changed.emit("%s로 진입 — 목표 층·세대·방을 클릭 (층 막대·PgUp/PgDn으로 층 이동, Esc 취소)" % e.name)


## 마우스 아래: 진입구 고르기면 가까운 진입구, 목표 고르기면 출발점 → 그 칸 예상 경로
func _update_preview(world_pos: Vector2) -> void:
	if mode == Mode.ENTRY_POINT:
		_hover_entry = sim.entries.nearest(projection.to_cell(world_pos), level, ENTRY_PICK_CELLS)
		queue_redraw()
		return
	var cell := Vector2i(projection.to_cell(world_pos).floor())
	var to := Vector3i(cell.x, cell.y, level)
	if to == _preview_to:
		return
	_preview_to = to
	_preview = preview_path(to)
	queue_redraw()


## 출발점(고른 진입구 바깥 칸, 없으면 첫 조의 자리) → 목표 칸 경로 (못 가면 빈 배열)
func preview_path(to: Vector3i) -> Array[Vector3i]:
	if selected.is_empty() or not sim.building.in_bounds(to.x, to.y):
		return []
	var from: Vector3i = chosen_entry.outside if chosen_entry else sim.units.get_crew(selected[0]).leader.cell3()
	var goal := sim.pathfinder.nearest_walkable(to.z, Vector2i(to.x, to.y))
	if goal == Pathfinder.NO_CELL:
		return []
	return sim.pathfinder.find_path_through_doors(from, Vector3i(goal.x, goal.y, to.z))


## 경로 칸을 아는 칸인가 (본 적 있거나 도면이 있다) — 실선/점선
func known_cell(p: Vector3i) -> bool:
	return sim.command.interior.plan_known or sim.perception.is_seen(p.z, p.x, p.y) or sim.building.cell(p.z, p.x, p.y) in BuildingData.OUTDOOR


## 예상 소요 시간(현장 초)과 도착 시 공기 잔량 비율 (첫 조 조장 기준, 걸어서 이동 호흡량)
func preview_estimate(path: Array[Vector3i]) -> Vector2:
	if path.is_empty() or selected.is_empty():
		return Vector2(-1, -1)
	var secs := float(path.size()) / maxf(0.1, sim.units.walk_speed_cells)
	var ff := sim.units.get_crew(selected[0]).leader
	var left := ff.air_l - sim.conditions.walking_air_lpm() * secs / 60.0
	return Vector2(secs, clampf(left / maxf(1.0, ff.air_capacity), 0.0, 1.0))


## 문 앞 휠을 열 수 있는가: 건물 안 조 하나를 골랐고 그 조가 누른 문 2칸 안
func _door_wheel(world_pos: Vector2, screen_pos: Vector2) -> bool:
	if selected.size() != 1 or screen_pos.x < 0.0 or not sim.command.interior.crew_inside(selected[0]):
		return false
	var door := _door_at(world_pos)
	if door == null or door.kind != Opening.Kind.DOOR:
		return false
	var c := sim.units.get_crew(selected[0])
	if c.leader.level != door.level:
		return false
	for cell in door.cells:
		if c.leader.pos.distance_to(Vector2(cell) + Vector2(0.5, 0.5)) <= DOOR_WHEEL_CELLS:
			door_menu.emit(c.id, door.index, screen_pos)
			return true
	return false


## 초진 보고 뒤, 불이 보이지 않는 방인가 → 화점진압 대신 잔불정리
func _overhaul_room(target: Vector3i) -> bool:
	if sim.phases.knockdown_tick < 0:
		return false
	var room := sim.fire.compartment_at(target.z, target.x, target.y)
	if room == null:
		return false
	var grid := sim.fire.grid
	for c in room.cells:
		var i := grid.index(room.level, c.x, c.y)
		if (not sim.perception.enabled and grid.state[i] == FuelGrid.State.BURNING) or (sim.perception.enabled and sim.perception.seen_burning[i] == 1 and grid.state[i] == FuelGrid.State.BURNING):
			return false
	return true


## 창가 구조대상자(뛰어내릴 수 있는 사람) 아래 바깥 땅인가 → 인명구조매트 (상황 행동)
func _mat_spot(cell: Vector2i) -> bool:
	if level != sim.building.levels()[0] or not sim.building.cell(level, cell.x, cell.y) in BuildingData.OUTDOOR:
		return false
	for v in sim.rescue.victims:
		if v.discovered and v.alive() and v.jumper and Vector2(cell).distance_to(Vector2(v.pos.x, v.pos.y)) <= MAT_PICK_CELLS:
			return true
	return false


## 본 적 없는 방이라 층 단위로만 맡길 수 있는가 (알림도 띄운다)
func _floor_only(target: Vector3i) -> bool:
	var interior := sim.command.interior
	var room := sim.fire.compartment_at(target.z, target.x, target.y)
	if not interior.enabled or room == null or interior.room_known(target):
		return false
	notice.emit("본 적 없는 방 → %s 단위 임무로 지시 (방이 보이거나 도면을 얻으면 방 단위)" % sim.building.floor_name(target.z))
	return true


## 이벤트의 화면 좌표를 월드 좌표로 바꾼다 (카메라 이동·줌 반영).
func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


## world_pos 아래(현재 층)에 있는 대원의 조 id. 없으면 -1. (기획안 9-3, P4-3)
##   - 대원마다 그림을 덮는 타원 판정 (화면 기준 최소 48×64px, 줌과 상관없이)
##   - 2인 1조는 한 덩어리: 두 사람 사이(캡슐)를 눌러도 팀 선택
##   - 맞은 것이 없으면 화면 30px 안의 가장 가까운 조 (자석 선택)
##   - 겹치면 선택 안 된 조가 우선, 같은 곳을 다시 누르면 다음 조로 넘어간다
##   - 안개(시야 밖) 속 대원은 고를 수 없다 (상황판 팀 카드로)
func _crew_at(world_pos: Vector2) -> int:
	var hits := crews_under(world_pos)
	if hits.is_empty():
		return -1
	if hits.size() > 1 and _last_pick_world.distance_to(world_pos) < 4.0 and _last_pick in hits:
		var next: int = hits[(hits.find(_last_pick) + 1) % hits.size()]
		_last_pick = next
		return next
	for id in hits:
		if not id in selected:
			_last_pick = id
			_last_pick_world = world_pos
			return id
	_last_pick = hits[0]
	_last_pick_world = world_pos
	return hits[0]


## world_pos(화면에 그려진 월드 좌표) 아래에 걸리는 조들 (가까운 순). 자석 판정 포함
func crews_under(world_pos: Vector2) -> Array[int]:
	var xf := get_canvas_transform()
	var mouse := xf * world_pos
	var vp: ViewParams = _view_params()
	var rx := vp.pick_w_px * 0.5
	var ry := vp.pick_h_px * 0.5
	var hits: Array[Dictionary] = []
	var nearest := -1
	var nearest_d := vp.pick_magnet_px
	for c in sim.units.crews:
		var pts: Array[Vector2] = []
		for ff in c.members():
			if ff.level != level or ff.aboard or not _crew_visible(ff):
				continue
			pts.append(xf * projection.to_screen(ff.pos, projection.pick_height_m))
		if pts.is_empty():
			continue
		var best := INF
		for p in pts:
			# 발밑보다 조금 위를 가운데로 하는 타원 (그림 전체를 덮는다)
			var d := mouse - (p - Vector2(0, ry * 0.4))
			var e := (d.x * d.x) / (rx * rx) + (d.y * d.y) / (ry * ry)
			if e <= 1.0:
				best = minf(best, d.length())
			var dist := p.distance_to(mouse)
			if dist < nearest_d:
				nearest_d = dist
				nearest = c.id
		if pts.size() == 2 and best == INF and Geometry2D.get_closest_point_to_segment(mouse, pts[0], pts[1]).distance_to(mouse) <= rx:
			best = Geometry2D.get_closest_point_to_segment(mouse, pts[0], pts[1]).distance_to(mouse)
		if best < INF:
			hits.append({"id": c.id, "d": best})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	var out: Array[int] = []
	for h in hits:
		out.append(int(h.id))
	if out.is_empty() and nearest >= 0:
		out.append(nearest)
	return out


func _crew_visible(ff: Firefighter) -> bool:
	if sim.perception == null or not sim.perception.enabled:
		return true
	return sim.perception.is_visible(ff.level, floori(ff.pos.x), floori(ff.pos.y))


func _view_params() -> ViewParams:
	if _vp == null:
		_vp = ViewParams.load_default()
	return _vp


## world_pos 아래에 현장지휘관이 있는지
func _witness_at(world_pos: Vector2) -> int:
	if level != sim.building.levels()[0]:
		return -1
	for w in sim.command.survey.witnesses:
		if w.present(sim.clock.tick) and projection.to_screen(w.pos, projection.pick_height_m).distance_to(world_pos) < projection.pick_radius_px:
			return w.index
	return -1


func _commander_at(world_pos: Vector2) -> bool:
	var c := sim.command.commander
	return c.level == level and projection.to_screen(c.pos, projection.pick_height_m).distance_to(world_pos) < projection.pick_radius_px


## world_pos 아래(현재 층)의 문 (with_windows면 창도). 입체 화면에서 닫힌 문 블록을 누른 경우도 잡는다. 없으면 null.
func _door_at(world_pos: Vector2, with_windows := false) -> Opening:
	for h in [0.0, DOOR_PICK_HEIGHT_M, 1.0, 1.5]:
		var c := Vector2i(projection.to_cell_at(world_pos, h).floor())
		var cell := Vector3i(c.x, c.y, level)
		var o := sim.doors.target_at(cell) if with_windows else sim.doors.door_at(cell)
		if o:
			return o
	return null


## world_pos 아래의 구조 대상: (0, 요구조자 id) / (1, 대원 id) / 없으면 (-1, -1)
func _casualty_at(world_pos: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := CASUALTY_PICK_PX
	for v in sim.rescue.victims:
		if v.discovered and v.level == level and v.alive() and v.carried_by < 0:
			var d := projection.to_screen(v.pos, 0.2).distance_to(world_pos)
			if d < best_d:
				best_d = d
				best = Vector2i(0, v.id)
	for ff in sim.units.firefighters:
		if ff.incapacitated and ff.level == level:
			var d := projection.to_screen(ff.pos, 0.2).distance_to(world_pos)
			if d < best_d:
				best_d = d
				best = Vector2i(1, ff.id)
	return best


## 지금 층에서 cell 가까이의 연결송수관 방수구 index (없으면 -1)
func _outlet_at(cell: Vector2) -> int:
	var outlets := sim.building.outlets
	for i in outlets.size():
		if outlets[i].z == level and cell.distance_to(Vector2(outlets[i].x, outlets[i].y) + Vector2(0.5, 0.5)) <= 1.5:
			return i
	return -1


## world_pos 아래의 구조된 환자 (요구조자 id, 없으면 -1). 1층 바깥에만 있다
func _patient_at(world_pos: Vector2) -> int:
	if level != sim.building.levels()[0]:
		return -1
	var best := -1
	var best_d := CASUALTY_PICK_PX
	for p in sim.ems.patients:
		var v := sim.rescue.victims[p.victim_id]
		if not sim.ems.on_scene(p) or v.carried_by >= 0:
			continue
		var d := projection.to_screen(v.pos, 0.2).distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = v.id
	return best


## world_pos 아래의 차량 id. 바닥면과 차체 중간 높이 둘 다 확인한다. 없으면 -1.
func _vehicle_at(world_pos: Vector2) -> int:
	if level != sim.building.levels()[0]:
		return -1
	var id := sim.water.vehicle_at(projection.to_cell(world_pos))
	if id < 0:
		id = sim.water.vehicle_at(projection.to_cell_at(world_pos, VEHICLE_PICK_HEIGHT_M))
	return id


func _merge(ids: Array[int]) -> Array[int]:
	var out := selected.duplicate()
	for id in ids:
		if not id in out:
			out.append(id)
	return out


func _merge_vehicles(ids: Array[int]) -> Array[int]:
	var out := selected_vehicles.duplicate()
	for id in ids:
		if not id in out:
			out.append(id)
	return out


static func _toggle(ids: Array, id: int) -> void:
	if id in ids:
		ids.erase(id)
	else:
		ids.append(id)


func _set_selection(ids: Array[int], vehicle_ids: Array[int] = [], with_commander := false) -> void:
	if commander_selected != with_commander:
		commander_selected = with_commander
		EventBus.commander_selection_changed.emit(with_commander)
	selected = ids
	selected.sort()
	selected_vehicles = vehicle_ids
	selected_vehicles.sort()
	EventBus.selection_changed.emit(selected.duplicate())
	EventBus.vehicle_selection_changed.emit(selected_vehicles.duplicate())


func _draw() -> void:
	_draw_hover()
	_draw_entry_mode()
	# 구역 지정 미리 보기: 안전구역 사각형·진입통제선
	if _zone_from.x >= 0 and projection:
		if mode == Mode.ZONE_SAFE:
			var a := _zone_from.floor()
			var b := _zone_to.floor()
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE
			var pts := PackedVector2Array([projection.to_screen(lo), projection.to_screen(Vector2(hi.x, lo.y)), projection.to_screen(hi), projection.to_screen(Vector2(lo.x, hi.y))])
			draw_colored_polygon(pts, Color(PlanStyle.SAFE_ZONE, 0.18))
			pts.append(pts[0])
			draw_polyline(pts, PlanStyle.SAFE_ZONE, 2.0)
		elif mode == Mode.ZONE_LINE:
			draw_dashed_line(projection.to_screen(_zone_from), projection.to_screen(_zone_to), PlanStyle.CONTROL_LINE, 3.0, 10.0)
	if _dragging:
		draw_rect(_drag_rect, Color(PlanStyle.SELECTION, 0.12))
		draw_rect(_drag_rect, PlanStyle.SELECTION, false, 1.5)
	if _marker_start_ms >= 0.0:
		var t := (Time.get_ticks_msec() - _marker_start_ms) / MARKER_DURATION_MS
		if t >= 1.0:
			_marker_start_ms = -1.0
		else:
			draw_arc(_marker_world, 6.0 + t * 14.0, 0.0, TAU, 24, Color(PlanStyle.SELECTION, 1.0 - t), 2.0)


## 진입 지시: 진입구 표시(진입구 고르기), 예상 경로(아는 구간 실선·모르는 구간 점선)와 시간·공기
func _draw_entry_mode() -> void:
	if sim == null or projection == null or not mode in [Mode.ENTRY_POINT, Mode.ATTACK, Mode.SEARCH_AUTO]:
		return
	var z := get_canvas_transform().get_scale().x
	var font := PlanStyle.font()
	if mode == Mode.ENTRY_POINT:
		for e in sim.entries.list:
			if e.level != level:
				continue
			var p := projection.to_screen(Vector2(e.door) + Vector2(0.5, 0.5), 1.0)
			var hot := e == _hover_entry
			draw_circle(p, (14.0 if hot else 10.0) / z, Color(PlanStyle.ENTRY_POINT, 0.9))
			draw_arc(p, (14.0 if hot else 10.0) / z, 0.0, TAU, 20, Color.WHITE, 2.0 / z)
			draw_string(font, p + Vector2(-80, -16) / z, e.name, HORIZONTAL_ALIGNMENT_CENTER, 160.0 / z, maxi(8, roundi(14.0 / z)), Color.WHITE)
			if hot:
				var side := sim.entries.side(e)
				var tip := "%s%s" % [sim.entries.smoke_text(e), " · " + side if side != "" else ""]
				draw_string(font, p + Vector2(-90, 26) / z, tip, HORIZONTAL_ALIGNMENT_CENTER, 180.0 / z, maxi(8, roundi(13.0 / z)), PlanStyle.ENTRY_POINT.lightened(0.4))
		return
	if _preview.size() < 2:
		return
	for i in range(1, _preview.size()):
		var a := _preview[i - 1]
		var b := _preview[i]
		if a.z != level or b.z != level:
			continue
		var pa := projection.to_screen(Vector2(a.x, a.y) + Vector2(0.5, 0.5), 0.05)
		var pb := projection.to_screen(Vector2(b.x, b.y) + Vector2(0.5, 0.5), 0.05)
		if known_cell(a) and known_cell(b):
			draw_line(pa, pb, PlanStyle.ENTRY_POINT, 3.0 / z)
		else:
			draw_dashed_line(pa, pb, PlanStyle.ENTRY_POINT, 2.0 / z, 6.0 / z)
	var est := preview_estimate(_preview)
	if est.x >= 0.0:
		var end := _preview[-1]
		var pe := projection.to_screen(Vector2(end.x, end.y) + Vector2(0.5, 0.5), 0.05)
		draw_string(font, pe + Vector2(-90, -14) / z, "예상 %d초 · 도착 공기 %d%%" % [roundi(est.x), roundi(est.y * 100.0)],
			HORIZONTAL_ALIGNMENT_CENTER, 180.0 / z, maxi(8, roundi(14.0 / z)), Color.WHITE)


## 마우스를 올린 조: 두 대원 둘레에 팀 색 윤곽 + 이름. 가려진 대원도 윤곽선으로 비쳐 보인다 (화면 크기 고정)
func _draw_hover() -> void:
	if hover_crew < 0 or sim == null:
		return
	var c := sim.units.get_crew(hover_crew)
	if c == null:
		return
	var z := get_canvas_transform().get_scale().x
	var vp := _view_params()
	var color: Color = sim.units.squads[c.squad_id].color
	var name_at := Vector2.ZERO
	for ff in c.members():
		if ff.level != level or ff.aboard:
			continue
		var p := projection.to_screen(ff.pos, projection.pick_height_m) - Vector2(0, vp.pick_h_px * 0.4 / z)
		var pts := PackedVector2Array()
		for k in 25:
			var a := TAU * k / 24.0
			pts.append(p + Vector2(cos(a) * vp.pick_w_px * 0.5, sin(a) * vp.pick_h_px * 0.5) / z)
		draw_polyline(pts, Color(color, 0.95), 2.5 / z)
		draw_polyline(pts, Color(1, 1, 1, 0.5), 1.0 / z)
		name_at = p - Vector2(0, vp.pick_h_px * 0.55 / z)
	var label := "%s %d조" % [sim.units.squads[c.squad_id].name, c.number]
	draw_string(PlanStyle.font(), name_at + Vector2(-60.0 / z, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 120.0 / z, maxi(8, roundi(14.0 / z)), Color(1, 1, 1, 0.95))
