class_name SelectionController
extends Node2D
## 마우스 선택과 명령. 좌클릭 = 보기·고르기, 우클릭 = 지시 (2026-11-16 사용자 결정 — docs/decisions.md '조작').
## - 좌클릭: 조·차량·지휘관 고르기 / Shift+좌클릭: 추가·해제 / 드래그: 범위 선택 / 더블클릭: 같은 출동대 전체.
##   빈 곳: 외부 보기의 외벽 층 → 그 층 내부 보기, 내부 화면의 바깥 땅 → 외부 보기, 함께 보이는 다른 층 → 그 층. 대원은 움직이지 않는다
##   마우스를 올리면 누를 수 있는 곳(외벽 층·다른 층·바깥 땅)이 노랗게 (고른 것이 없어도)
## - 우클릭 (분대를 고른 채): 누른 곳에 따라
##     층 (외벽 층·내부 화면의 그 층 아무 곳·층 막대) → 지시 창: 임무(분대 종류의 기본 임무가 골라져 있다 — data/commands.json default_mission)
##       + 진입구(가까운 문이 골라져 있다) + 지시. 방 단위 지시는 없다 (2026-11-16 사용자 결정)
##     노란 진입구 → 그 문 앞으로 / 바깥 땅 → 분대 이동 (밖의 분대만)
##     대상(펌프차·방수구·밸브·창·요구조자·환자) → 그 작업. 계단·문 처리는 대원이 질문 카드로 묻는다 (2026-11-17)
## - 우클릭 (지휘관을 고른 채): 지휘관 이동. 아무것도 안 골랐으면 우클릭은 아무 일도 하지 않는다 (알림만)
## - 우클릭(차량): 이동, 소화전 점령(소화전 우클릭), 급수(물탱크차로 펌프차 우클릭)
## - 관계인 클릭: 진술 창 (witness_clicked)
## - 숫자 1~9: 팀 초상 줄 순서의 조 선택 (P10-1)
## - 대상 지정 명령(begin_mode): 명령 카드를 누른 뒤 목표를 좌클릭. 우클릭·Esc로 취소
## 선택 단위는 조와 차량이며, 내부 화면에서 함께 보이는 층(아래층 바깥 땅 포함)의 대원·차량도 그려진 자리에서 고른다.
## 좌표 변환은 projection(상황판/입체)을 따른다.

## 대상 지정 명령 (명령 카드를 누른 뒤 목표를 좌클릭). 인명검색·화재진압은 여기 없다 — 층 우클릭 지시 창 (2026-11-17)
enum Mode { NONE, EXTERIOR, TREAT, TRANSPORT, WAYPOINT, MONITOR, PPV, VEHICLE_CONNECT, VEHICLE_MOVE, ZONE_SAFE, ZONE_CASUALTY, ZONE_LINE, TRIAGE_POST, OBSERVE, BASKET, POST, FORWARD }

## 관계인을 클릭했을 때 (world가 진술 창을 연다)
signal witness_clicked(index: int)
## 화면 알림 요청 (HUD가 띄운다)
signal notice(text: String)
## 분대를 고른 채 층을 우클릭 (외벽 층·내부 화면의 그 층 아무 곳·층 막대) → 지시 창 (임무 + 진입구)
signal floor_order(crew_ids: Array[int], level: int, screen_pos: Vector2)
## 빈 곳 좌클릭으로 보기를 바꾼다 (외벽 층 → 그 층 내부, 바깥 땅 → 외부 보기)
signal guide_view(level: int, exterior: bool)
## 내부 화면에서 함께 보이는 다른 층의 빈 곳을 눌렀다 — 그 층을 지금 층으로, 화면은 제자리 (R17)
signal floor_clicked(level: int)
## 이미 고른 분대의 팀장을 다시 눌렀다 (선착 분대는 고른 지휘관을 다시) → 분대 편성 둥근 버튼 (2026-11-16)
signal squad_menu(squad_id: int, screen_pos: Vector2)

const DRAG_THRESHOLD_PX := 6.0
## 안전구역을 지정하면 이어서 환자 집결지 찍기로 넘어간다 (구조자 둘 곳 카드에서 시작했을 때 — 지휘관 명령 칸을 다시 찾지 않게)
var casualty_after_safe := false
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
	Mode.EXTERIOR: "경계: 창·개구부·인접 건물 쪽을 클릭 (관창 배치, 불이 다가오면 방수)",
	Mode.TREAT: "처치: 구조된 환자를 클릭 (구급대가 가서 응급처치)",
	Mode.TRANSPORT: "이송: 처치한 환자를 클릭 (들것으로 구급차에 태워 병원으로)",
	Mode.WAYPOINT: "경유지: 본 적 있는 곳을 클릭 (건물 안 조에게는 무전으로 전달)",
	Mode.MONITOR: "방수포: 바깥 창·문을 클릭 — 진입대원이 있는 방에는 쓰지 않는다 (SOP 207-1.1)",
	Mode.POST: "현장지휘소: 건물 밖을 클릭 — 현장이 보이고, 낙하물 위험반경(발화층 높이 1/2) 밖이며, 차량 동선을 막지 않는 곳 (SOP 104-1.3)",
	Mode.FORWARD: "직전대기 장소: 진입구 가까운 건물 밖을 클릭 — 후착대가 여기 모인다 (SOP 103-2.1.3)",
	Mode.BASKET: "바스켓 구조: 그 층 단면에서 창가의 요구조자를 클릭 (작업 높이·수평 거리 안, 첫 사용은 전개 시간)",
	Mode.PPV: "송풍기 양압배연: 바깥 출입문을 클릭 — 먼저 반대편 창(배출구)을 확보한다",
	Mode.ZONE_SAFE: "안전구역: 건물 밖을 끌어서 사각형 (한 번 클릭하면 그 자리에 기본 크기) — 낙하물 위험구역은 피한다",
	Mode.ZONE_CASUALTY: "환자 집결지: 안전구역 안을 클릭 (구조한 사람을 여기로 옮긴다)",
	Mode.ZONE_LINE: "진입통제선: 선의 두 끝을 차례로 클릭",
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
## 바스켓 구조를 맡길 굴절차 (P9)
var basket_vehicle := -1
## 지휘권 선언을 지휘소 클릭까지 미룬 답 (P4-4). 비어 있으면 지휘소 옮기기
var pending_declare: Dictionary = {}
## 설정되어 있으면 좌클릭을 선택 대신 이 함수로 넘긴다 (셀 좌표 Vector2i). 개발용 발화 모드 등에 쓴다.
var click_override := Callable()
## 설정되어 있으면 빈 곳 클릭 때 화면 위치로 맞은 층을 묻는다 (단면 보기의 아래층, R17). (world_pos) -> level
var level_picker := Callable()
## 외부 보기에서 외벽 아래의 층 (world_pos) -> level (-99 = 없음), 노란 테두리를 그릴 층 (level) -> void (P4-5)
var shell_picker := Callable()
var shell_hover := Callable()
## 함께 보이는 층과 그 화면 위치 () -> [[level, Vector2], ...] (world가 정한다, 지금 층은 Vector2.ZERO가 아닐 수도 있다)
var shown_floors := Callable()
## 빈 곳 좌클릭으로 볼 곳 (world_pos) -> Vector2i(층, 방식): 방식 0 = 같은 화면에서 그 층, 1 = 외부 보기, 2 = 외벽 층 → 그 층 내부. 층 -99 = 없음
var view_picker := Callable()
## 보이지 않는 층의 화면 위치 표시
const NOT_SHOWN := Vector2(INF, INF)

# --- 안내 흐름 (P4-5): 마우스 아래의 고를 수 있는 것 ---
var _g_entry: EntryPoints.Entry = null
var _g_floor := -99
## 마우스 아래의 볼 곳 (view_picker 결과)
var _g_view := Vector2i(-99, 0)
var _g_text := ""
var _defaults: Dictionary = {}
var _g_room := -1
var _g_events := 0


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
## 노란 진입구 우클릭 허용 거리 (칸)
const ENTRY_PICK_CELLS := 3.0
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
	casualty_after_safe = false
	if mode != Mode.NONE:
		mode = Mode.NONE
		EventBus.command_mode_changed.emit("")


## 선택한 조 중 수관을 가진 조
func crews_with_hose() -> Array[int]:
	var out: Array[int] = []
	for id in selected:
		if sim.water.held_hose(id):
			out.append(id)
	return out


## 선택한 조 중 방수 중(또는 방수 위치로 이동 중)인 조
func crews_spraying() -> Array[int]:
	var out: Array[int] = []
	for id in crews_with_hose():
		if sim.water.held_hose(id).flowing:
			out.append(id)
	return out


func _process(_delta: float) -> void:
	if _marker_start_ms >= 0.0:
		queue_redraw()
	# 합쳐져 없어진 조는 선택에서 뺀다 (분대 합치기)
	if sim != null and selected.any(func(id: int) -> bool: return not sim.units.crew_active(id)):
		var alive: Array[int] = []
		for id in selected:
			if sim.units.crew_active(id):
				alive.append(id)
		_set_selection(alive, selected_vehicles.duplicate(), commander_selected)
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
		_update_guide(mouse_world, h)
		_watch_guide_events()


func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventMouseButton:
		_handle_button(event)
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
	# 대상 지정 중(명령 카드): 다른 층(직상층·직하층)을 누르면 그 층이 고른 층이 되고, 같은 클릭을 그 층에서 처리한다 —
	# 보이는 층 어디든 한 번에 지시 (2026-11-14). 화면은 제자리라 누른 자리는 그대로다.
	# 평소의 좌클릭(고르기·보기)·우클릭(지시)은 층을 바꾸지 않고 그 층에서 처리한다 (_click_select·_right_click_at, 2026-11-16)
	if event.pressed and level_picker.is_valid() and not click_override.is_valid() and mode != Mode.NONE \
			and (event.is_action_pressed("select") or event.is_action_pressed("command")):
		var picked: int = level_picker.call(world_pos)
		if picked != level:
			floor_clicked.emit(picked)
			world_pos = _to_world(event.position)
	if event.is_action_pressed("select") and click_override.is_valid():
		click_override.call(Vector2i(projection.to_cell(world_pos).floor()))
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
		# 우클릭 = 지시 (2026-11-16)
		_right_click_at(world_pos, event.position)
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
		# 이미 고른 지휘관을 다시 누르면 자기 분대(선착 분대 — 팀장이 곧 선착대장)의 편성 둥근 버튼
		if commander_selected and screen_pos.x >= 0.0 and not sim.units.squads.is_empty() and not sim.units.squads[0].crews.is_empty():
			squad_menu.emit(0, screen_pos)
			return
		_set_selection([], [], true)
		return
	var witness := _witness_at(world_pos)
	if not add and witness >= 0:
		witness_clicked.emit(witness)
		return
	var crew_id := _crew_at(world_pos)
	# 이미 고른 분대의 팀장을 다시 누르면 편성 둥근 버튼 (첫 클릭은 늘 선택만 — 2026-11-11 결정)
	if not add and crew_id >= 0 and selected.size() == 1 and selected[0] == crew_id and screen_pos.x >= 0.0 and officer_under(crew_id, world_pos):
		squad_menu.emit(sim.units.get_crew(crew_id).squad_id, screen_pos)
		return
	var vehicle_id := -1 if crew_id >= 0 else _vehicle_at(world_pos)
	if crew_id < 0 and vehicle_id < 0:
		# 빈 곳: 볼 곳(외벽 층·바깥 땅·다른 층)이면 보기만 바꾼다 — 선택은 그대로 (2026-11-16)
		if not add and _view_click(world_pos):
			return
		if not add:
			_set_selection([], [])
		return
	if not add:
		if crew_id >= 0:
			# 고르기만 한다 — 지시는 우클릭이나 명령 카드로 (2026-11-16)
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
	var offs := _floor_offsets()
	for c in sim.units.crews:
		if c.solo:
			continue
		for ff in c.members():
			if offs.has(ff.level) and not ff.aboard and _drag_rect.has_point(projection.to_screen(ff.pos) + (offs[ff.level] as Vector2)):
				ids.append(c.id)
				break
	var vehicles: Array[int] = []
	var ground: int = sim.building.levels()[0]
	if ids.is_empty() and offs.has(ground):
		for v in sim.units.vehicles:
			if not v.away and _drag_rect.has_point(projection.to_screen(v.pos) + (offs[ground] as Vector2)):
				vehicles.append(v.id)
	if ids.is_empty() and vehicles.is_empty() and not add:
		var c := sim.command.commander
		if offs.has(c.level) and _drag_rect.has_point(projection.to_screen(c.pos) + (offs[c.level] as Vector2)):
			_set_selection([], [], true)
			return
	if add:
		_set_selection(_merge(ids), _merge_vehicles(vehicles))
	else:
		_set_selection(ids, vehicles)


## 우클릭 = 지시. 내부 화면에서 함께 보이는 다른 층(아래층 바깥 땅 등)을 누르면 화면은 그대로 두고 그 층에서 처리한다
func _right_click_at(world_pos: Vector2, screen_pos := Vector2(-1, -1)) -> void:
	var picked := level
	if level_picker.is_valid() and not click_override.is_valid():
		picked = level_picker.call(world_pos)
	var off := _floor_off(picked)
	if picked == level or off == NOT_SHOWN:
		_issue_right_click(world_pos, screen_pos)
		return
	var keep := level
	var t0 := _marker_start_ms
	level = picked
	_issue_right_click(world_pos - off, screen_pos)
	level = keep
	if _marker_start_ms != t0:
		_marker_world += off


func _issue_right_click(world_pos: Vector2, screen_pos := Vector2(-1, -1)) -> void:
	var cell_f := projection.to_cell(world_pos)
	var cell := Vector2i(cell_f.floor())
	var marker_cell := Vector2(cell) + Vector2(0.5, 0.5)
	if not selected_vehicles.is_empty() and not commander_selected:
		_issue_vehicle_click(world_pos)
		return
	# 분대를 고른 채 우클릭: 누른 곳에 따라 지시 (2026-11-16). 시킬 일이 없는 곳이면 알림만 (지휘관은 움직이지 않는다)
	if not commander_selected and not selected.is_empty():
		if not _issue_crew_right_click(world_pos, screen_pos):
			notice.emit("여기서는 시킬 일이 없습니다 — 방·외벽 층·노란 진입구·바깥 땅을 우클릭 (지휘관을 옮기려면 지휘관을 고르세요)")
		return
	# 아무것도 안 골랐으면 우클릭은 아무 일도 하지 않는다 — 고른 것만 움직인다 (2026-11-16 사용자 결정: 헷갈리지 않게)
	if not commander_selected:
		notice.emit("고른 대상이 없습니다 — 지휘관을 옮기려면 지휘관(파란 헬멧)이나 아래 바의 지휘관 그림을 먼저 고르세요")
		return
	# 지휘관을 고른 채 땅 우클릭 = 현장지휘관 이동
	sim.issue(CommandOrder.make("commander_move", [], 0, Vector3i(cell.x, cell.y, level)))
	_marker_world = projection.to_screen(marker_cell)
	_marker_start_ms = Time.get_ticks_msec()


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


## 고른 분대 우클릭 (2026-11-16): 지시했으면 true, 시킬 일이 없는 곳이면 false
##   밖의 분대 → 대상 작업·노란 진입구 → 층(외벽 층·내부 화면의 그 층 아무 곳): 지시 창 (임무 + 진입구)
##   → 바깥 땅(분대 이동, 밖의 분대만).
##   문 앞 목록·계단 클릭은 없앴다 (2026-11-17) — 문 처리·계단은 대원이 질문 카드로 묻는다
func _issue_crew_right_click(world_pos: Vector2, screen_pos := Vector2(-1, -1)) -> bool:
	var cell_f := projection.to_cell(world_pos)
	var cell := Vector2i(cell_f.floor())
	# 아직 차에 탄 분대 (아래 팀 초상으로 고른 경우): 내린 뒤에 지시한다
	if selected.all(func(id: int) -> bool: return sim.units.get_crew(id) != null and sim.units.get_crew(id).leader.aboard):
		notice.emit("아직 차에 타고 있습니다 — 내린 뒤 지시하세요")
		return true
	var all_out := _outside_crews().size() == selected.size()
	if all_out and _issue_target_click(world_pos):
		return true
	var band := int(shell_picker.call(world_pos)) if shell_picker.is_valid() else -99
	if band != -99:
		return order_floor(band, screen_pos)
	# 내부 화면: 그 층의 건물 안 어디를 눌러도 그 층 임무 (방 단위 지시는 없다 — 2026-11-16 사용자 결정)
	if sim.command.interior.indoor(level, cell_f):
		return order_floor(level, screen_pos)
	# 바깥 땅 → 분대 이동 (보이는 곳은 직접. 건물 안 조는 임무·무전으로)
	if all_out and level == sim.building.levels()[0] and sim.building.cell(level, cell.x, cell.y) in BuildingData.OUTDOOR:
		var goal := sim.pathfinder.nearest_walkable(level, cell)
		if goal != Pathfinder.NO_CELL:
			sim.issue(MoveCommand.new(selected.duplicate(), Vector3i(goal.x, goal.y, level)))
			_mark(Vector2(goal) + Vector2(0.5, 0.5))
			return true
	return false


## 고른 분대에게 그 층 임무를 준다 → 지시 창 (임무 + 진입구 + 지시). 층 막대 우클릭도 이리로 온다.
## 건물 안 임무가 없는 대원(구급대)만 골랐으면 알림만. 처리했으면 true
func order_floor(lv: int, screen_pos := Vector2(-1, -1)) -> bool:
	if sim == null or mode != Mode.NONE or commander_selected or selected.is_empty() or sim.view_only:
		return false
	var ids: Array[int] = []
	var riding := 0
	for id in selected:
		var c := sim.units.get_crew(id)
		if c and c.leader.aboard:
			riding += 1
			continue
		if default_kind(id) != "":
			ids.append(id)
	if ids.is_empty():
		notice.emit("아직 차에 타고 있습니다 — 내린 뒤 지시하세요 (출동 중이면 '도착 후 임무'로 정할 수 있습니다)" if riding > 0 \
			else "고른 대원은 건물 안 임무가 없습니다 (구급대) — 오른쪽 명령 칸으로 지시")
		return true
	floor_order.emit(ids, lv, screen_pos)
	return true


## 초진 보고 뒤 그 층에 보이는 불이 없으면: 처음 잔불정리할 방의 칸 (탄 자리가 있고 아직 잔불정리하지 않은 방 중
## 고른 첫 분대에서 가까운 곳 — 그 뒤는 RekindleSystem이 그 층을 차례로 잇는다). 없으면 (-1, -1, -1).
## 화재진압이 그 층에서 잔불정리로 바뀐다 (기획안 9-1)
func overhaul_target(lv: int) -> Vector3i:
	var from := Vector2(sim.building.footprint(lv).get_center())
	if not selected.is_empty():
		from = sim.units.get_crew(selected[0]).leader.pos
	return sim.floor_overhaul_target(lv, from)


## 그 조의 우클릭 기본 임무 ("attack"·"search", 없으면 "")
func default_kind(crew_id: int) -> String:
	if _defaults.is_empty():
		_defaults = CommandCard.load_default_missions()
	var c := sim.units.get_crew(crew_id)
	if c == null or sim.ems.is_ems_crew(crew_id):
		return ""
	return str(_defaults.get(sim.units.squads[c.squad_id].type, ""))




## 밖의 분대 우클릭 대상: 환자·요구조자·노란 진입구·방수구·밸브·매트·창·승강기·문·펌프차 (처리했으면 true)
func _issue_target_click(world_pos: Vector2) -> bool:
	var cell_f := projection.to_cell(world_pos)
	var cell := Vector2i(cell_f.floor())
	var marker_cell := Vector2(cell) + Vector2(0.5, 0.5)
	var pump := _vehicle_at(world_pos)
	var without_hose: Array[int] = []
	for id in selected:
		if sim.water.held_hose(id) == null:
			without_hose.append(id)
	var door := _door_at(world_pos)
	var window: Opening = null
	var any_open := _door_at(world_pos, true)
	if any_open and any_open.kind == Opening.Kind.WINDOW:
		window = any_open
	# 노란 진입구: 그 문을 바로 눌렀거나, 다른 문·창을 누르지 않았고 진입구 가까이 (창·옆 문 우클릭을 가로채지 않는다)
	var entry: EntryPoints.Entry = null
	if sim.entries:
		for en: EntryPoints.Entry in sim.entries.list:
			if door != null and en.opening == door:
				entry = en
		if entry == null and door == null and window == null and pump < 0:
			entry = sim.entries.nearest(cell_f, level, ENTRY_PICK_CELLS)
	var casualty := _casualty_at(world_pos)
	var patient := _patient_at(world_pos)
	if patient >= 0 and sim.ems.is_ems_crew(selected[0]):
		var p := sim.ems.patient_of(patient)
		sim.issue(EquipmentCommand.make("ems_transport" if p.stage == EmsSystem.Stage.TREATED else "ems_treat", selected, -1, patient))
		marker_cell = sim.rescue.victims[patient].pos
	elif casualty.x >= 0:
		sim.issue(EquipmentCommand.make("rescue" if casualty.x == 0 else "rescue_ff", selected, -1, casualty.y))
	elif entry != null:
		# 노란 진입구: 그 문 앞으로 가서 진입 허가를 묻는다 (P4-5)
		sim.issue(CommandOrder.make("approach", selected.duplicate(), entry.index))
		var side := sim.entries.side(entry)
		notice.emit("%s로 — 문 앞에서 진입 허가를 묻습니다%s" % [entry.name, " (%s)" % side if side != "" else ""])
		marker_cell = Vector2(entry.outside.x, entry.outside.y) + Vector2(0.5, 0.5)
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
		return false
	_marker_world = projection.to_screen(marker_cell)
	_marker_start_ms = Time.get_ticks_msec()
	return true


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
			var chain := casualty_after_safe
			cancel_mode()
			if chain:
				begin_mode(Mode.ZONE_CASUALTY)
				notice.emit("이제 안전구역 안에 환자 집결지를 클릭하세요")
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
		Mode.EXTERIOR:
			if not selected.is_empty():
				var cell := Vector2i(projection.to_cell(world_pos).floor())
				sim.issue(TacticalCommand.make("exterior", selected, Vector3i(cell.x, cell.y, level)))
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
		Mode.POST, Mode.FORWARD:
			var pc := Vector2i(projection.to_cell(world_pos).floor())
			if mode == Mode.POST and not pending_declare.is_empty():
				var a := pending_declare.duplicate()
				a["post"] = [pc.x, pc.y]
				pending_declare = {}
				sim.issue(CommandOrder.make("declare", [], 0, Vector3i.ZERO, a))
			else:
				sim.issue(CommandOrder.make("zone", [], 0, Vector3i.ZERO, {"kind": "post" if mode == Mode.POST else "forward", "cell": [pc.x, pc.y]}))
		Mode.BASKET:
			var who := _casualty_at(world_pos)
			if who.x == 0 and basket_vehicle >= 0:
				sim.issue(EquipmentCommand.make("basket", [], basket_vehicle, who.y))
		Mode.PPV:
			var door := _door_at(world_pos)
			if door and not selected.is_empty():
				sim.issue(EquipmentCommand.make("ppv", [selected[0]] as Array[int], -1, -1, Vector3i(door.cells[0].x, door.cells[0].y, door.level)))



## 창가 구조대상자(뛰어내릴 수 있는 사람) 아래 바깥 땅인가 → 인명구조매트 (상황 행동)
func _mat_spot(cell: Vector2i) -> bool:
	if level != sim.building.levels()[0] or not sim.building.cell(level, cell.x, cell.y) in BuildingData.OUTDOOR:
		return false
	for v in sim.rescue.victims:
		if v.discovered and v.alive() and v.jumper and Vector2(cell).distance_to(Vector2(v.pos.x, v.pos.y)) <= MAT_PICK_CELLS:
			return true
	return false


## 함께 보이는 층 → 지금 층 기준 화면 위치 차이 (지금 층은 늘 ZERO). 보이지 않는 층은 들어있지 않다
func _floor_offsets() -> Dictionary:
	var out := {level: Vector2.ZERO}
	if not shown_floors.is_valid():
		return out
	var specs: Array = shown_floors.call()
	var base := Vector2.ZERO
	for spec: Array in specs:
		if int(spec[0]) == level:
			base = spec[1]
	for spec: Array in specs:
		if int(spec[0]) != level:
			out[int(spec[0])] = (spec[1] as Vector2) - base
	return out


## 그 층이 지금 층 기준으로 그려진 자리 차이 (보이지 않으면 NOT_SHOWN)
func _floor_off(lv: int) -> Vector2:
	return _floor_offsets().get(lv, NOT_SHOWN)


## 빈 곳 좌클릭: 볼 곳이면 보기를 바꾼다 (외벽 층 → 그 층 내부, 바깥 땅 → 외부 보기, 다른 층 → 그 층). 바꿨으면 true
func _view_click(world_pos: Vector2) -> bool:
	if not view_picker.is_valid():
		return false
	var t: Vector2i = view_picker.call(world_pos)
	if t.x == -99:
		return false
	shell_hover_clear()
	match t.y:
		1:
			guide_view.emit(t.x, true)
		2:
			guide_view.emit(t.x, false)
		_:
			floor_clicked.emit(t.x)
	return true


func shell_hover_clear() -> void:
	_g_floor = -99
	_g_view = Vector2i(-99, 0)
	if shell_hover.is_valid():
		shell_hover.call(-99, "")


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
	# 내부 화면: 함께 보이는 층(아래층 바깥 땅의 대원 등)도 그려진 자리에서 고른다 (2026-11-16)
	var offs := _floor_offsets()
	for c in sim.units.crews:
		# 한 명 보내기로 나간 대원은 고를 수 없다 (대원은 조작하지 않는다)
		if c.solo:
			continue
		var pts: Array[Vector2] = []
		for ff in c.members():
			if not offs.has(ff.level) or ff.aboard or not _crew_visible(ff):
				continue
			pts.append(xf * (projection.to_screen(ff.pos, projection.pick_height_m) + (offs[ff.level] as Vector2)))
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
		# 조원 사이(줄지어 선 사람과 사람 사이)를 눌러도 그 조 — 분대 3~4명도 한 덩어리
		if best == INF:
			for k in range(1, pts.size()):
				var near := Geometry2D.get_closest_point_to_segment(mouse, pts[k - 1], pts[k]).distance_to(mouse)
				if near <= rx:
					best = minf(best, near)
		if best < INF:
			hits.append({"id": c.id, "d": best})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	var out: Array[int] = []
	for h in hits:
		out.append(int(h.id))
	if out.is_empty() and nearest >= 0:
		out.append(nearest)
	return out


## 그 조의 팀장이 world_pos 아래에 있는가 (팀장 그림을 덮는 타원 안이고, 조원 중 팀장이 가장 가깝다)
func officer_under(crew_id: int, world_pos: Vector2) -> bool:
	var c := sim.units.get_crew(crew_id)
	if c == null:
		return false
	var o: Firefighter = c.officer()
	var offs := _floor_offsets()
	if o == null or o.incapacitated or not offs.has(o.level) or o.aboard or not _crew_visible(o):
		return false
	var xf := get_canvas_transform()
	var mouse := xf * world_pos
	var vp: ViewParams = _view_params()
	var rx := vp.pick_w_px * 0.5
	var ry := vp.pick_h_px * 0.5
	var op := xf * (projection.to_screen(o.pos, projection.pick_height_m) + (offs[o.level] as Vector2))
	var d := mouse - (op - Vector2(0, ry * 0.4))
	if (d.x * d.x) / (rx * rx) + (d.y * d.y) / (ry * ry) > 1.0:
		return false
	for ff in c.list:
		if ff != o and offs.has(ff.level) and not ff.aboard \
				and (xf * (projection.to_screen(ff.pos, projection.pick_height_m) + (offs[ff.level] as Vector2))).distance_to(mouse) < op.distance_to(mouse):
			return false
	return true


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
	var off := _floor_off(sim.building.levels()[0])
	if off == NOT_SHOWN:
		return -1
	world_pos -= off
	for w in sim.command.survey.witnesses:
		if w.present(sim.clock.tick) and projection.to_screen(w.pos, projection.pick_height_m).distance_to(world_pos) < projection.pick_radius_px:
			return w.index
	return -1


func _commander_at(world_pos: Vector2) -> bool:
	var c := sim.command.commander
	var off := _floor_off(c.level)
	return off != NOT_SHOWN and not c.aboard and (projection.to_screen(c.pos, projection.pick_height_m) + off).distance_to(world_pos) < projection.pick_radius_px


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
	var off := _floor_off(sim.building.levels()[0])
	if off == NOT_SHOWN:
		return -1
	world_pos -= off
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
	# 안내 한 줄: 무엇을 우클릭하면 되는지 (좌클릭 = 보기·고르기, 우클릭 = 지시 — 2026-11-16)
	if mode == Mode.NONE and sim != null:
		var hint := ""
		if with_commander:
			hint = "우클릭: 지휘관 이동"
		elif not selected.is_empty():
			hint = "우클릭: 층(외벽·내부·층 막대) = 임무 지시 · 진입구 = 문 앞으로 · 땅 = 이동" \
				if _outside_crews().size() == selected.size() \
				else "우클릭: 층(외벽·내부·층 막대) = 임무 지시(무전) · 곁의 문 = 문 행동"
		EventBus.command_mode_changed.emit(hint)
	EventBus.selection_changed.emit(selected.duplicate())
	EventBus.vehicle_selection_changed.emit(selected_vehicles.duplicate())


func _draw() -> void:
	_draw_hover()
	_draw_guide()
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
	var offs := _floor_offsets()
	for ff in c.members():
		if not offs.has(ff.level) or ff.aboard:
			continue
		var p := projection.to_screen(ff.pos, projection.pick_height_m) + (offs[ff.level] as Vector2) - Vector2(0, vp.pick_h_px * 0.4 / z)
		var pts := PackedVector2Array()
		for k in 25:
			var a := TAU * k / 24.0
			pts.append(p + Vector2(cos(a) * vp.pick_w_px * 0.5, sin(a) * vp.pick_h_px * 0.5) / z)
		draw_polyline(pts, Color(color, 0.95), 2.5 / z)
		draw_polyline(pts, Color(1, 1, 1, 0.5), 1.0 / z)
		name_at = p - Vector2(0, vp.pick_h_px * 0.55 / z)
	var label := sim.units.crew_name(c)
	draw_string(PlanStyle.font(), name_at + Vector2(-60.0 / z, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 120.0 / z, maxi(8, roundi(14.0 / z)), Color(1, 1, 1, 0.95))


# --- 안내 흐름 (P4-5, 2026-11-11 사용자 결정): 조를 고르면 고를 수 있는 곳이 노랗게 ---

## 안내 흐름을 쓰는가: 조를 골랐고, 다른 지시 모드가 아니며, 보기 전용이 아님
func _guiding() -> bool:
	return sim != null and mode == Mode.NONE and not selected.is_empty() and not commander_selected and not sim.view_only


func _outside_crews() -> Array[int]:
	var out: Array[int] = []
	for id in selected:
		if not sim.command.interior.crew_inside(id):
			out.append(id)
	return out


## 마우스 아래의 누를 수 있는 것 (매 프레임, 가볍게).
## 볼 곳(외벽 층·다른 층·바깥 땅)은 늘 노랗게 (좌클릭). 분대를 고르면 우클릭 대상(진입구·층)도 노랗게.
## 계단은 지도에서 고르지 않는다 — 갈리면 질문 카드(STAIR-01)로 묻는다 (2026-11-17)
func _update_guide(mouse_world: Vector2, crew_under: int) -> void:
	var entry: EntryPoints.Entry = null
	var floor_lv := -99
	var view := Vector2i(-99, 0)
	var room := -1
	var over_map := crew_under < 0 and mode == Mode.NONE
	var cell := projection.to_cell(mouse_world)
	if over_map and _guiding() and _outside_crews().size() == selected.size() and sim.entries:
		entry = sim.entries.nearest(cell, level, ENTRY_PICK_CELLS)
	if over_map and entry == null:
		if shell_picker.is_valid():
			floor_lv = int(shell_picker.call(mouse_world))
		if floor_lv == -99 and view_picker.is_valid():
			view = view_picker.call(mouse_world)
		# 분대를 고른 채 지금 층의 건물 안: 우클릭하면 그 층 임무 지시 (방 단위는 없다)
		if floor_lv == -99 and view.x == -99 and _guiding() and sim.command.interior.indoor(level, cell):
			room = level
	var text := ""
	if floor_lv != -99:
		text = "%s — 클릭: 내부 보기" % sim.building.floor_name(floor_lv)
		if _guiding():
			text += " · 우클릭: %s 임무 지시" % sim.building.floor_name(floor_lv)
	if shell_hover.is_valid() and (floor_lv != _g_floor or text != _g_text):
		shell_hover.call(floor_lv, text)
	if entry != _g_entry or floor_lv != _g_floor or room != _g_room or view != _g_view or text != _g_text:
		_g_entry = entry
		_g_floor = floor_lv
		_g_view = view
		_g_text = text
		_g_room = room
		queue_redraw()
	elif _guiding() or view.x != -99:
		queue_redraw()  # 깜빡임


## 밖의 조가 쓸 진입구: 가고 있는 진입구, 없으면 가장 가까운 진입구
func entry_for(crew_id: int) -> EntryPoints.Entry:
	var ei := int(sim.command.approach.get(crew_id, -1))
	if ei >= 0 and ei < sim.entries.list.size():
		return sim.entries.list[ei]
	var c := sim.units.get_crew(crew_id)
	var best: EntryPoints.Entry = null
	for e in sim.entries.main_entries():
		if best == null or c.leader.pos.distance_to(Vector2(e.outside.x, e.outside.y)) < c.leader.pos.distance_to(Vector2(best.outside.x, best.outside.y)):
			best = e
	return best


func _mark(cell: Vector2) -> void:
	_marker_world = projection.to_screen(cell)
	_marker_start_ms = Time.get_ticks_msec()


## 진입 허가 뒤 층 묻기·계단 묻기: 안내 한 줄만 띄운다. 화면과 선택은 바꾸지 않는다 —
## 지휘관이 보고 싶은 곳을 직접 본다 (2026-11-16 사용자 결정)
func _watch_guide_events() -> void:
	var entries := sim.events.entries
	while _g_events < entries.size():
		var e := entries[_g_events]
		_g_events += 1
		if e.type != "floor_ask" or sim.view_only or mode != Mode.NONE:
			continue
		# 계단 묻기는 질문 카드(STAIR-01)가 맡는다 — 여기서는 층 묻기만 안내한다
		if e.type == "floor_ask":
			EventBus.command_mode_changed.emit("진입 허가 — %s: 분대를 고르고 맡길 층을 우클릭 (외벽·내부 화면·층 막대)" % e.squad)


## 노랗게: 진입구(밖의 조), 마우스 아래 층
func _draw_guide() -> void:
	if sim == null or projection == null:
		return
	var z := get_canvas_transform().get_scale().x
	var font := PlanStyle.font()
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.6 + 0.4 * sin(t * 5.0)
	var gold := PlanStyle.ENTRY_POINT
	_draw_view_hover(z, font, pulse, gold)
	if not _guiding():
		return
	# 진입구 (밖의 조가 있을 때)
	if not _outside_crews().is_empty() and sim.entries:
		for e in sim.entries.list:
			if e.level != level:
				continue
			var hot := e == _g_entry
			var p := projection.to_screen(Vector2(e.door) + Vector2(0.5, 0.5), 1.0)
			var r := (15.0 if hot else 9.0 + 3.0 * pulse) / z
			draw_circle(p, r * 1.6, Color(gold, 0.18 * pulse))
			draw_circle(p, r, Color(gold, 0.95 if hot else 0.75))
			draw_arc(p, r, 0.0, TAU, 20, Color.WHITE, 2.0 / z)
			if hot or z >= 0.8:
				draw_string(font, p + Vector2(-110, -18) / z, e.name + (" — 우클릭: 이 문으로" if hot else ""), HORIZONTAL_ALIGNMENT_CENTER, 220.0 / z, maxi(8, roundi(14.0 / z)), Color.WHITE)
			if hot:
				var side := sim.entries.side(e)
				var waiting := _waiting_at(e)
				var tip := "%s%s%s" % [sim.entries.smoke_text(e), " · " + side if side != "" else "", " · 대기: " + waiting if waiting != "" else ""]
				draw_string(font, p + Vector2(-110, 28) / z, tip, HORIZONTAL_ALIGNMENT_CENTER, 220.0 / z, maxi(8, roundi(13.0 / z)), gold.lightened(0.4))
	# 마우스 아래가 지금 층의 건물 안: 그 층 바닥 테두리 + '우클릭: 임무 지시' (방 단위는 없다)
	if _g_room >= 0 and _g_room == level:
		var fp := Rect2(sim.building.footprint(level))
		var pts := PackedVector2Array()
		for c: Vector2 in [fp.position, Vector2(fp.end.x, fp.position.y), fp.end, Vector2(fp.position.x, fp.end.y), fp.position]:
			pts.append(projection.to_screen(c, 0.05))
		draw_polyline(pts, Color(gold, 0.6 + 0.35 * pulse), 3.0 / z)
		var mouse := _to_world(get_viewport().get_mouse_position())
		draw_string(font, mouse + Vector2(16, -10) / z, "%s — 우클릭: 임무 지시" % sim.building.floor_name(level), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, roundi(15.0 / z)), Color(gold.lightened(0.3), 0.95))


## 볼 곳 (좌클릭): 내부 화면에서 함께 보이는 다른 층 → 그 층 바닥 테두리, 바깥 땅 → 마우스 곁에 '외부 보기'
func _draw_view_hover(z: float, font: Font, pulse: float, gold: Color) -> void:
	if _g_view.x == -99:
		return
	var mouse := _to_world(get_viewport().get_mouse_position())
	var fs := maxi(8, roundi(15.0 / z))
	if _g_view.y == 1:
		draw_string(font, mouse + Vector2(16, -10) / z, "클릭: 외부 보기", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(gold.lightened(0.3), 0.95))
		return
	var off := _floor_off(_g_view.x)
	if off == NOT_SHOWN:
		return
	var fp := Rect2(sim.building.footprint(_g_view.x))
	var pts := PackedVector2Array()
	for c: Vector2 in [fp.position, Vector2(fp.end.x, fp.position.y), fp.end, Vector2(fp.position.x, fp.end.y), fp.position]:
		pts.append(projection.to_screen(c, 0.05) + off)
	draw_polyline(pts, Color(gold, 0.6 + 0.35 * pulse), 3.0 / z)
	draw_string(font, mouse + Vector2(16, -10) / z, "%s — 클릭: 이 층 보기" % sim.building.floor_name(_g_view.x), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(gold.lightened(0.3), 0.95))


## 진입구 앞에서 기다리는 조 이름 (없으면 "")
func _waiting_at(e: EntryPoints.Entry) -> String:
	var names := PackedStringArray()
	for id: int in sim.command.approach.keys():
		if int(sim.command.approach[id]) == e.index:
			var c := sim.units.get_crew(id)
			if c and not c.leader.is_moving():
				names.append(sim.units.crew_name(c))
	return ", ".join(names)
