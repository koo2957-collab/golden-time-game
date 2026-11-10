class_name MissionUi
extends Control
## 임무형 내부 지휘 화면 (기획안 9-1·9-2, R7c)
##   - 원형 메뉴: 지도에서 조를 좌클릭 → 명령 카드와 같은 칸 (data/commands.json, P10-2)
##   - 끌어다 놓기: 전술상황판의 팀 카드를 지도의 방·층에 놓으면 임무 창 → 임무(화점 진압·인명 검색) + 임무 조건
## 화면만 만든다. 명령은 order_issued로 내보내고 시뮬레이션이 실행한다 (다시 하기에 기록된다).

signal order_issued(command: RefCounted)
signal notice(text: String)

const PANEL_WIDTH := 420.0

var sim: SimWorld
var selection: SelectionController
## 화면 좌표 → 칸 (x, y, 층)
var to_cell: Callable
var radial: RadialMenu
var panel: PanelContainer

var _menu_crew := -1
var _menu_center := Vector2.ZERO
## 명령 카드 (Hud와 같은 것)와 칸 누르기 (World._press_card)
var card: CommandCard
var press_card: Callable
var _drop_crew := -1
var _drop_target := Vector3i.ZERO
var _drag_crew := -1
var _ghost: Label
var _title: Label
var _hint: Label
var _opts: Dictionary = {}  # 조건 키 -> OptionButton
var _groups := {"withdraw_air": "withdraw_air_options", "on_fire": "on_fire_options", "on_victim": "on_victim_options"}
## 마지막으로 고른 조건 (다음 임무 창의 기본값)
var _last := {"withdraw_air": "alarm", "on_fire": "ask", "on_victim": "ask"}


func setup(p_sim: SimWorld, p_selection: SelectionController, p_to_cell: Callable) -> void:
	sim = p_sim
	selection = p_selection
	to_cell = p_to_cell
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()
	_ghost = Label.new()
	_ghost.add_theme_font_size_override("font_size", 16)
	_ghost.add_theme_color_override("font_color", Color("fde68a"))
	_ghost.add_theme_color_override("font_outline_color", Color.BLACK)
	_ghost.add_theme_constant_override("outline_size", 4)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.visible = false
	add_child(_ghost)
	radial = RadialMenu.new()
	add_child(radial)
	radial.picked.connect(_on_radial)


func _process(_delta: float) -> void:
	if _drag_crew >= 0:
		_ghost.position = get_viewport().get_mouse_position() + Vector2(16, 6)


func is_open() -> bool:
	return radial.visible or panel.visible


func close_all() -> void:
	radial.close()
	panel.visible = false
	end_drag()


# --- 원형 메뉴 ---

## 지도에서 조 좌클릭 (SelectionController.crew_menu): 명령 카드와 같은 칸을 커서 둘레에 (기획안 9-1, P10-2)
func open_crew_menu(crew_id: int, screen_pos: Vector2) -> void:
	var c := sim.units.get_crew(crew_id)
	if c == null or card == null:
		return
	_menu_crew = crew_id
	_menu_center = screen_pos
	_open_radial()


func _open_radial() -> void:
	var items: Array[Dictionary] = []
	var slots := card.slots()
	for i in slots.size():
		var it: Dictionary = slots[i]
		if it.is_empty():
			continue
		items.append({"id": CommandCard.KEYS[i], "label": "%s %s" % [CommandCard.KEYS[i], str(it.label)],
			"tip": str(it.get("hint", "")), "enabled": card.is_enabled(it)})
	var task := sim.tactical.mission_text(_menu_crew)
	var head := "%s · %s" % [_crew_name(_menu_crew), task if task != "" else "임무 없음"]
	if card.parent != "":
		head += " ▸ " + str(card.parent_item().get("label", ""))
	radial.open(_menu_center, head, items)


## 원형 메뉴에서 칸을 고름 = 명령 카드 칸을 누름 (같은 처리). 하위 칸만 펼쳤으면 그 자리에서 다시 연다
func _on_radial(key: String) -> void:
	if not press_card.is_valid():
		return
	press_card.call(key)
	if card.parent != "" and selection.mode == SelectionController.Mode.NONE:
		_open_radial()


## 지원 투입할 조: 밖에 있고 임무가 없는 조 (같은 출동대 우선, 가까운 순). RIT·안전담당·구급대는 빼고
func support_crew(crew_id: int) -> int:
	var c := sim.units.get_crew(crew_id)
	if c == null:
		return -1
	var best := -1
	var best_d := INF
	for h in sim.units.crews:
		if h.id == crew_id or h.leader.incapacitated or h.leader.aboard or sim.command.interior.crew_inside(h.id):
			continue
		if sim.command.resources.is_en_route(h.squad_id) or sim.command.safety.role_of(h.id) != SafetySystem.Role.NONE:
			continue
		if sim.tactical.task_of_crew(h.id) != null or sim.rescue.task_of_crew(h.id) != null or sim.ems.is_ems_crew(h.id):
			continue
		var d := h.leader.pos.distance_to(c.leader.pos) + (0.0 if h.squad_id == c.squad_id else 6.0)
		if d < best_d:
			best_d = d
			best = h.id
	return best


func send_support(crew_id: int) -> void:
	var helper := support_crew(crew_id)
	if helper < 0:
		notice.emit("투입할 수 있는 조가 없습니다")
		return
	var c := sim.units.get_crew(crew_id)
	var t := sim.tactical.task_of_crew(crew_id)
	var action := "search_floor"
	var target := Vector3i(floori(c.leader.pos.x), floori(c.leader.pos.y), c.leader.level)
	if t:
		action = t.floor_action if t.floor >= 0 else t.action
		target = t.target
	elif sim.fire.compartment_at(target.z, target.x, target.y) and sim.command.interior.room_known(target):
		action = "search"
	order_issued.emit(TacticalCommand.make(action, [helper] as Array[int], target))
	notice.emit("지원 투입: %s → %s 쪽 %s" % [_crew_name(helper), _crew_name(crew_id), TacticalSystem.ACTIONS.get(action, action)])


# --- 끌어다 놓기 ---

## 팀 카드를 끌기 시작 (전술상황판)
func begin_drag(crew_id: int) -> void:
	_drag_crew = crew_id
	_ghost.text = "▶ %s — 방이나 층에 놓기" % _crew_name(crew_id)
	_ghost.visible = true


func end_drag() -> void:
	_drag_crew = -1
	if _ghost:
		_ghost.visible = false


## 팀 카드를 지도에 놓음 → 임무 창
func drop_crew(crew_id: int, screen_pos: Vector2) -> void:
	end_drag()
	var t: Vector3i = to_cell.call(screen_pos)
	var room := sim.fire.compartment_at(t.z, t.x, t.y)
	if room == null:
		notice.emit("건물 안 방이나 층 위에 놓으세요 — 밖에서는 우클릭으로 직접 이동합니다")
		return
	_drop_crew = crew_id
	_drop_target = t
	_title.text = "%s → %s" % [_crew_name(crew_id), _target_name()]
	var cur: Dictionary = sim.tactical.conditions.get(crew_id, _last)
	for k: String in _opts:
		_select_key(_opts[k], _groups[k], str(cur.get(k, _last[k])))
	var cmd := sim.command
	var squad := sim.units.get_crew(crew_id).squad_id
	_hint.text = "" if not cmd.entry_order_required or cmd.entry_allowed.has(squad) else "진입 명령(R)이 아직 없습니다 — 임무를 받아도 입구에서 기다립니다"
	_hint.visible = _hint.text != ""
	panel.size = Vector2.ZERO
	panel.reset_size()
	var area := get_viewport_rect().size
	panel.position = Vector2(clampf(screen_pos.x + 14.0, 8.0, area.x - PANEL_WIDTH - 8.0), clampf(screen_pos.y + 14.0, 8.0, area.y - panel.size.y - 8.0))
	panel.visible = true


func _by_floor() -> bool:
	return sim.command.interior.enabled and not sim.command.interior.room_known(_drop_target)


func _target_name() -> String:
	if _by_floor():
		return "%s (층 단위 — 아직 본 적 없는 곳)" % sim.building.floor_name(_drop_target.z)
	return sim.fire.compartment_at(_drop_target.z, _drop_target.x, _drop_target.y).display_name()


## 임무 부여: 조건을 먼저 정하고 임무를 내린다 (화점 진압·인명 검색)
func assign(kind: String) -> void:
	if _drop_crew < 0:
		return
	var cond := {"crews": [_drop_crew]}
	for k: String in _opts:
		var key := _selected_key(_opts[k], _groups[k])
		cond[k] = key
		_last[k] = key
	order_issued.emit(CommandOrder.make("mission_conditions", [], 0, Vector3i.ZERO, cond))
	var action := kind + ("_floor" if _by_floor() and kind != "check_below" else "")
	order_issued.emit(TacticalCommand.make(action, [_drop_crew] as Array[int], _drop_target))
	notice.emit("%s 임무: %s %s" % [_crew_name(_drop_crew), _target_name(), TacticalSystem.ACTIONS.get(action, action)])
	panel.visible = false
	_drop_crew = -1


func _build_panel() -> void:
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.12, 0.95)
	style.border_color = Color("fbbf24")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", Color("fde68a"))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, 0)
	box.add_child(_title)
	var lab := Label.new()
	lab.text = "임무 조건 — 정해 두면 그 상황에서 묻지 않고 그대로 한다"
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", Color("94a3b8"))
	box.add_child(lab)
	for k: String in ["withdraw_air", "on_fire", "on_victim"]:
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		for o: Dictionary in sim.tactical.mission_data.get(_groups[k], []):
			ob.add_item(str(o.get("label", o.get("key", ""))))
			ob.set_item_metadata(ob.item_count - 1, str(o.get("key", "")))
		box.add_child(ob)
		_opts[k] = ob
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color("fca5a5"))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, 0)
	box.add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for spec in [["attack", "화점 진압"], ["search", "인명 검색"], ["check_below", "직하층 확인"]]:
		var b := Button.new()
		b.text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(110, 36)
		b.pressed.connect(assign.bind(spec[0]))
		row.add_child(b)
	var vent := Button.new()
	vent.text = "배연"
	vent.disabled = true
	vent.tooltip_text = "송풍기 양압배연은 R11에서"
	vent.custom_minimum_size = Vector2(70, 36)
	row.add_child(vent)
	var cancel := Button.new()
	cancel.text = "취소"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(70, 36)
	cancel.pressed.connect(func() -> void: panel.visible = false)
	row.add_child(cancel)
	box.add_child(row)
	add_child(panel)


func _select_key(ob: OptionButton, _group: String, key: String) -> void:
	for i in ob.item_count:
		if str(ob.get_item_metadata(i)) == key:
			ob.select(i)
			return
	ob.select(0)


func _selected_key(ob: OptionButton, _group: String) -> String:
	return str(ob.get_item_metadata(ob.selected)) if ob.selected >= 0 else ""


func _crew_name(crew_id: int) -> String:
	var c := sim.units.get_crew(crew_id)
	return "%s %d조" % [sim.units.squads[c.squad_id].name, c.number] if c else "—"
