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
## - Ctrl+숫자: 부대 지정 / 숫자: 부대 호출
## - 대상 지정 명령(begin_mode): 수관 연장(펌프차 클릭), 직사·분무 방수(목표 클릭). 우클릭·Esc로 취소
## 선택 단위는 조(2인 1조)와 차량이며, 현재 보고 있는 층의 대원만 선택된다.
## 좌표 변환은 projection(상황판/입체)을 따른다.

enum Mode { NONE, HOSE, STRAIGHT, FOG, DOOR, SEARCH, OVERHAUL, PRIMARY, ATTACK, SEARCH_AUTO, EXTERIOR, RESCUE, TREAT, TRANSPORT, AIR_MAT, WAYPOINT, PENCIL, COVER, MONITOR, PPV, ELEVATOR, LIFELINE }

## 관계인을 클릭했을 때 (world가 진술 창을 연다)
signal witness_clicked(index: int)
## 화면 알림 요청 (HUD가 띄운다)
signal notice(text: String)
## 건물 안 조를 우클릭함 → 원형 메뉴 (기획안 9-1, R7c)
signal crew_menu(crew_id: int, screen_pos: Vector2)
## 단면 보기에서 아래층(보이기만 하는 층)을 눌렀다 — 그 층을 지금 층으로 (R17)
signal floor_clicked(level: int)

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
	Mode.HOSE: "수관 연장: 펌프차를 클릭",
	Mode.STRAIGHT: "직사 방수: 목표 지점을 클릭",
	Mode.FOG: "분무 방수: 목표 지점을 클릭",
	Mode.DOOR: "문 개방·폐쇄 / 창 파괴(배연): 문이나 창을 클릭 (잠긴 문은 파괴, 2명 이상 필요)",
	Mode.SEARCH: "인명검색: 검색할 방을 클릭",
	Mode.OVERHAUL: "잔불정리: 방을 클릭 (열화상으로 찾은 불씨를 없앤다)",
	Mode.PRIMARY: "주 임무: 방을 클릭 (진압대는 진압, 구조대는 수색)",
	Mode.ATTACK: "진압: 방을 클릭 (문 개방·수관 연장·분무 방수, 불이 잡히면 중지)",
	Mode.SEARCH_AUTO: "수색: 방을 클릭 (문 개방·인명검색·이송)",
	Mode.EXTERIOR: "외부 방수: 창이나 개구부를 클릭 (밖에서 직사)",
	Mode.RESCUE: "구조: 발견한 구조대상자나 쓰러진 대원을 클릭",
	Mode.TREAT: "처치: 구조된 환자를 클릭 (구급대가 가서 응급처치)",
	Mode.TRANSPORT: "이송: 처치한 환자를 클릭 (들것으로 구급차에 태워 병원으로)",
	Mode.AIR_MAT: "공기안전매트: 창 아래 바닥(1층 바깥)을 클릭 — 구조대가 가서 설치",
	Mode.WAYPOINT: "경유지: 본 적 있는 곳을 클릭 (건물 안 조에게는 무전으로 전달)",
	Mode.PENCIL: "펜슬링·3D 주수: 천장 가스층을 클릭 — 짧게 끊어 쏴 가스층을 식힌다, 물이 적게 든다 (SOP 210-10.4)",
	Mode.COVER: "엄호 주수: 앞을 클릭 — 넓은 분무 막으로 옆 대원의 복사열을 줄인다 (SOP 203-2.1)",
	Mode.MONITOR: "방수포: 바깥 창·문을 클릭 — 진입대원이 있는 방에는 쓰지 않는다 (SOP 207-1.1)",
	Mode.PPV: "송풍기 양압배연: 바깥 출입문을 클릭 — 먼저 반대편 창(배출구)을 확보한다",
	Mode.LIFELINE: "라이트라인: 끝 지점을 클릭 — 조가 지금 자리에서 그곳까지 유도선을 깔며 간다 (시계 0 구역, SOP 217)",
	Mode.ELEVATOR: "비상용승강기: 내릴 층으로 화면을 옮긴 뒤(층 막대·PgUp/PgDn) 지도를 클릭 — 화재층 2개층 아래까지 (SOP 222)",
}
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

var _groups: Dictionary = {}  # 숫자 -> Array[int]
var _pressing := false
var _dragging := false
var _skip_release := false
var _press_screen := Vector2.ZERO
var _press_world := Vector2.ZERO
var _drag_rect := Rect2()
var _marker_world := Vector2.ZERO
var _marker_start_ms := -1.0


func setup(p_sim: SimWorld) -> void:
	sim = p_sim


func begin_mode(p_mode: Mode) -> void:
	mode = p_mode
	EventBus.command_mode_changed.emit(MODE_HINTS.get(mode, ""))


func cancel_mode() -> void:
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
			_click_select(world_pos, event.shift_pressed)
		_pressing = false
		_dragging = false
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("command"):
		# 건물 안 조를 우클릭하면 원형 메뉴 (임무형 내부 지휘)
		var menu_crew := _crew_at(world_pos)
		if menu_crew >= 0 and sim.command.interior.enabled and sim.command.interior.crew_inside(menu_crew) \
				and not sim.units.get_crew(menu_crew).leader.incapacitated:
			_set_selection([menu_crew] as Array[int])
			crew_menu.emit(menu_crew, event.position)
		else:
			_issue_right_click(world_pos)
		get_viewport().set_input_as_handled()


func _handle_group_key(event: InputEventKey) -> void:
	if event.keycode < KEY_1 or event.keycode > KEY_9:
		return
	var n := event.keycode - KEY_0
	if event.ctrl_pressed:
		_groups[n] = [selected.duplicate(), selected_vehicles.duplicate()]
	elif _groups.has(n):
		var crews: Array[int] = []
		var vehicles: Array[int] = []
		crews.assign(_groups[n][0])
		vehicles.assign(_groups[n][1])
		_set_selection(crews, vehicles)
	get_viewport().set_input_as_handled()


func _click_select(world_pos: Vector2, add: bool) -> void:
	if not add and _commander_at(world_pos):
		_set_selection([], [], true)
		return
	var witness := _witness_at(world_pos)
	if not add and witness >= 0:
		witness_clicked.emit(witness)
		return
	var crew_id := _crew_at(world_pos)
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
	if not selected.is_empty():
		var pump := _vehicle_at(world_pos)
		var without_hose: Array[int] = []
		for id in selected:
			if sim.water.hose_of_crew(id) == null:
				without_hose.append(id)
		var door := _door_at(world_pos)
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
				sim.issue(MoveCommand.new(selected, Vector3i(target.x, target.y, level)))
				marker_cell = Vector2(target) + Vector2(0.5, 0.5)
	_marker_world = projection.to_screen(marker_cell)
	_marker_start_ms = Time.get_ticks_msec()


func _complete_mode(world_pos: Vector2) -> void:
	match mode:
		Mode.HOSE:
			var vid := _vehicle_at(world_pos)
			if vid >= 0 and sim.units.get_vehicle(vid).is_pump() and not selected.is_empty():
				sim.issue(EquipmentCommand.make("hose", selected, vid))
		Mode.DOOR:
			var door := _door_at(world_pos, true)
			if door and not selected.is_empty():
				var action := "door_close" if door.is_open and door.kind == Opening.Kind.DOOR else "door_open"
				sim.issue(EquipmentCommand.make(action, selected, -1, -1, Vector3i(door.cells[0].x, door.cells[0].y, level)))
		Mode.SEARCH:
			if not selected.is_empty():
				var cell := Vector2i(projection.to_cell(world_pos).floor())
				var target := Vector3i(cell.x, cell.y, level)
				if _floor_only(target):
					sim.issue(TacticalCommand.make("search_floor", selected, target))
				else:
					sim.issue(EquipmentCommand.make("search", selected, -1, -1, target))
		Mode.PRIMARY, Mode.ATTACK, Mode.SEARCH_AUTO, Mode.EXTERIOR:
			if not selected.is_empty():
				var cell := Vector2i(projection.to_cell(world_pos).floor())
				var target := Vector3i(cell.x, cell.y, level)
				var attack: Array[int] = []
				var search: Array[int] = []
				for id in selected:
					var rescue_squad := sim.units.squad_of_crew(id).type == "구조대"
					if mode == Mode.SEARCH_AUTO or (mode == Mode.PRIMARY and rescue_squad):
						search.append(id)
					else:
						attack.append(id)
				if mode == Mode.EXTERIOR:
					sim.issue(TacticalCommand.make("exterior", selected, target))
				else:
					# 본 적 없는 방은 층 단위 임무로 (기획안 9-1, R7 — 도면을 얻으면 방 단위)
					var by_floor := _floor_only(target)
					if not attack.is_empty():
						sim.issue(TacticalCommand.make("attack_floor" if by_floor else "attack", attack, target))
					if not search.is_empty():
						sim.issue(TacticalCommand.make("search_floor" if by_floor else "search", search, target))
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
		Mode.AIR_MAT:
			if not selected.is_empty():
				var cell := Vector2i(projection.to_cell(world_pos).floor())
				sim.issue(EquipmentCommand.make("air_mat", selected, -1, -1, Vector3i(cell.x, cell.y, 1)))
				_marker_world = projection.to_screen(Vector2(cell) + Vector2(0.5, 0.5))
				_marker_start_ms = Time.get_ticks_msec()
		Mode.TREAT, Mode.TRANSPORT:
			var patient := _patient_at(world_pos)
			if patient >= 0 and not selected.is_empty():
				sim.issue(EquipmentCommand.make("ems_treat" if mode == Mode.TREAT else "ems_transport", selected, -1, patient))
		Mode.RESCUE:
			var casualty := _casualty_at(world_pos)
			if casualty.x >= 0 and not selected.is_empty():
				sim.issue(EquipmentCommand.make("rescue" if casualty.x == 0 else "rescue_ff", selected, -1, casualty.y))
		Mode.OVERHAUL:
			if not selected.is_empty():
				var cell := Vector2i(projection.to_cell(world_pos).floor())
				sim.issue(EquipmentCommand.make("overhaul", selected, -1, -1, Vector3i(cell.x, cell.y, level)))
		Mode.LIFELINE:
			if not selected.is_empty():
				var lcell := Vector2i(projection.to_cell(world_pos).floor())
				sim.issue(EquipmentCommand.make("lifeline", [selected[0]] as Array[int], -1, -1, Vector3i(lcell.x, lcell.y, level)))
		Mode.ELEVATOR:
			if not selected.is_empty():
				sim.issue(EquipmentCommand.make("elevator", selected, -1, level))
		Mode.MONITOR:
			var win := _door_at(world_pos, true)
			if win and monitor_vehicle >= 0:
				sim.issue(EquipmentCommand.make("monitor", [], monitor_vehicle, -1, Vector3i(win.cells[0].x, win.cells[0].y, win.level)))
		Mode.PPV:
			var door := _door_at(world_pos)
			if door and not selected.is_empty():
				sim.issue(EquipmentCommand.make("ppv", [selected[0]] as Array[int], -1, -1, Vector3i(door.cells[0].x, door.cells[0].y, door.level)))
		Mode.STRAIGHT, Mode.FOG, Mode.PENCIL, Mode.COVER:
			if not selected.is_empty():
				var cell := Vector2i(projection.to_cell(world_pos).floor())
				var pattern: HoseLine.Pattern = {Mode.STRAIGHT: HoseLine.Pattern.STRAIGHT, Mode.FOG: HoseLine.Pattern.FOG,
					Mode.PENCIL: HoseLine.Pattern.PENCIL, Mode.COVER: HoseLine.Pattern.COVER}[mode]
				sim.issue(EquipmentCommand.make("spray", selected, -1, pattern, Vector3i(cell.x, cell.y, level)))
				_marker_world = projection.to_screen(Vector2(cell) + Vector2(0.5, 0.5))
				_marker_start_ms = Time.get_ticks_msec()


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
	if _dragging:
		draw_rect(_drag_rect, Color(PlanStyle.SELECTION, 0.12))
		draw_rect(_drag_rect, PlanStyle.SELECTION, false, 1.5)
	if _marker_start_ms >= 0.0:
		var t := (Time.get_ticks_msec() - _marker_start_ms) / MARKER_DURATION_MS
		if t >= 1.0:
			_marker_start_ms = -1.0
		else:
			draw_arc(_marker_world, 6.0 + t * 14.0, 0.0, TAU, 24, Color(PlanStyle.SELECTION, 1.0 - t), 2.0)


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
