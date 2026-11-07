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

enum Mode { NONE, HOSE, STRAIGHT, FOG, DOOR, SEARCH }

## 관계인을 클릭했을 때 (world가 진술 창을 연다)
signal witness_clicked(index: int)

const DRAG_THRESHOLD_PX := 6.0
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
## 설정되어 있으면 좌클릭을 선택 대신 이 함수로 넘긴다 (셀 좌표 Vector2i). 개발용 발화 모드 등에 쓴다.
var click_override := Callable()

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


## 범위 안의 조를 고른다. 조가 하나도 없으면 범위 안의 차량을 고른다.
func _box_select(add: bool) -> void:
	var ids: Array[int] = []
	for c in sim.units.crews:
		for ff in c.members():
			if ff.level == level and _drag_rect.has_point(projection.to_screen(ff.pos)):
				ids.append(c.id)
				break
	var vehicles: Array[int] = []
	if ids.is_empty() and level == sim.building.levels()[0]:
		for v in sim.units.vehicles:
			if _drag_rect.has_point(projection.to_screen(v.pos)):
				vehicles.append(v.id)
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
		for vid in selected_vehicles:
			var v := sim.units.get_vehicle(vid)
			if hydrant >= 0:
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
		if casualty.x >= 0:
			sim.issue(EquipmentCommand.make("rescue" if casualty.x == 0 else "rescue_ff", selected, -1, casualty.y))
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
				sim.issue(EquipmentCommand.make("search", selected, -1, -1, Vector3i(cell.x, cell.y, level)))
		Mode.STRAIGHT, Mode.FOG:
			if not selected.is_empty():
				var cell := Vector2i(projection.to_cell(world_pos).floor())
				var pattern := HoseLine.Pattern.STRAIGHT if mode == Mode.STRAIGHT else HoseLine.Pattern.FOG
				sim.issue(EquipmentCommand.make("spray", selected, -1, pattern, Vector3i(cell.x, cell.y, level)))
				_marker_world = projection.to_screen(Vector2(cell) + Vector2(0.5, 0.5))
				_marker_start_ms = Time.get_ticks_msec()


## 이벤트의 화면 좌표를 월드 좌표로 바꾼다 (카메라 이동·줌 반영).
func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


## world_pos 아래(현재 층)에 있는 대원의 조 id. 없으면 -1.
func _crew_at(world_pos: Vector2) -> int:
	var best := -1
	var best_d := projection.pick_radius_px
	for ff in sim.units.firefighters:
		if ff.level != level:
			continue
		var d := projection.to_screen(ff.pos, projection.pick_height_m).distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = ff.crew_id
	return best


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
	if _dragging:
		draw_rect(_drag_rect, Color(PlanStyle.SELECTION, 0.12))
		draw_rect(_drag_rect, PlanStyle.SELECTION, false, 1.5)
	if _marker_start_ms >= 0.0:
		var t := (Time.get_ticks_msec() - _marker_start_ms) / MARKER_DURATION_MS
		if t >= 1.0:
			_marker_start_ms = -1.0
		else:
			draw_arc(_marker_world, 6.0 + t * 14.0, 0.0, TAU, 24, Color(PlanStyle.SELECTION, 1.0 - t), 2.0)
