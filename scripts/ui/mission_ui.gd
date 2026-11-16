class_name MissionUi
extends Control
## 임무형 내부 지휘 화면 (기획안 9-1·9-2, R7c)
##   - 지시 창 (2026-11-16·17 사용자 결정, open_order): 분대를 고른 채 층을 우클릭하면 임무(분대 기본 임무가 골라져 있다)
##     + 진입구 + 지시. 임무를 주는 길은 이것 하나 — 방 단위 지시·조건 3개 임무 창·팀 카드 끌어다 놓기·문 앞 목록은 없앴다.
##   - 팀장 둥근 버튼 (분대 편성)과 한 명 보내기 목록, 대기 ▸ 지원 투입
## 화면만 만든다. 명령은 order_issued로 내보내고 시뮬레이션이 실행한다 (다시 하기에 기록된다).

signal order_issued(command: RefCounted)
signal notice(text: String)

var sim: SimWorld
var selection: SelectionController
## 화면 좌표 → 칸 (x, y, 층)
var to_cell: Callable
## 커서 곁 작은 목록 (한 명 보내기 임무 고르기)
var menu: PanelContainer
var _menu_box: VBoxContainer
var _menu_title: Label
var _menu_pick := Callable()
## 목록 항목 id (테스트·화면 점검용)
var menu_ids: Array[String] = []
## 팀장 둥근 버튼 (분대 편성)과 그 항목 id · 누른 출동대
var radial: RadialMenu
var radial_ids: Array[String] = []
var _radial_squad := -1
var _radial_pos := Vector2.ZERO
var _menu_buttons: Array[Button] = []
## 지시 창 (층 우클릭): 임무·진입구를 고르고 '지시'. 화면 점검이 읽는 값 — 고른 임무, 층, 진입구 목록(가까운 순)과 고른 진입구.
## 직하층 확인은 세대 배치가 있는 건물(공동주택)에서만 보인다
const ORDER_KINDS := {"search": "인명검색", "attack": "화재진압", "check_below": "직하층 확인"}
const ORDER_KEYS := {"search": "Q", "attack": "W", "check_below": "E"}
var order: PanelContainer
var _order_box: VBoxContainer
var _order_crews: Array[int] = []
var order_level := 0
var order_kind := ""
var order_entries: Array[int] = []
var order_entry := -1
## 명령 카드 (Hud와 같은 것)와 칸 누르기 (World._press_card)
var card: CommandCard
var press_card: Callable


func setup(p_sim: SimWorld, p_selection: SelectionController, p_to_cell: Callable) -> void:
	sim = p_sim
	selection = p_selection
	to_cell = p_to_cell
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_menu()
	_build_order()
	# 팀장 둥근 버튼 (분대 편성)
	radial = RadialMenu.new()
	add_child(radial)
	radial.picked.connect(_on_squad_pick)


func is_open() -> bool:
	return menu.visible or radial.visible or order.visible


func close_all() -> void:
	close_menu()
	close_order()
	radial.close()


# --- 팀장 둥근 버튼: 분대 편성 (2026-11-16 결정 — 명령 카드는 임무, 둥근 버튼은 편성) ---

## 이미 고른 분대의 팀장(선착 분대는 지휘관 캐릭터)을 다시 눌렀다: 나누기 또는 합치기 · 한 명 보내기 · 복귀.
## 할 수 없는 항목은 회색이고 올리면 이유가 보인다
func open_squad_menu(squad_id: int, screen_pos: Vector2) -> void:
	if squad_id < 0 or squad_id >= sim.units.squads.size():
		return
	var squad := sim.units.squads[squad_id]
	_radial_squad = squad_id
	_radial_pos = screen_pos
	var split_now := sim.units.main_crews(squad).size() >= 2
	var items: Array[Dictionary] = []
	for it: Dictionary in CommandCard.load_sets().get("squad", []):
		var id := str(it.id)
		# 나누기·합치기는 지금 할 수 있는 쪽 하나만
		if (id == "split" and split_now) or (id == "merge" and not split_now):
			continue
		var why := ""
		if str(it.get("need", "")) == "later":
			why = "다음 작업에서"
		elif id in ["split", "merge"]:
			why = sim.regroup_reason(squad_id, id == "split")
		elif id == "detach":
			why = _detach_reason(squad_id)
		elif id == "recall":
			why = sim.recall_reason(squad_id)
		items.append({"id": id, "label": str(it.label), "enabled": why == "", "tip": str(it.get("hint", "")) if why == "" else "%s — %s" % [str(it.label), why]})
	radial_ids.clear()
	for it in items:
		radial_ids.append(str(it.id))
	radial.open(screen_pos, "%s · 분대 편성" % squad.name, items)


## 한 명 보내기를 할 수 없는 이유: 맡길 수 있는 임무가 하나라도 있으면 "" (임무별 이유는 목록에서 보인다)
func _detach_reason(squad_id: int) -> String:
	var first := ""
	for s: Dictionary in sim.solo_specs():
		var why := sim.solo_reason(squad_id, str(s.id))
		if why == "":
			return ""
		if first == "":
			first = why
	return first if first != "" else "맡길 임무가 없음"


func _on_squad_pick(id: String) -> void:
	if _radial_squad < 0:
		return
	var squad := sim.units.squads[_radial_squad]
	var ids: Array[int] = [_radial_squad]
	match id:
		"split", "merge":
			order_issued.emit(CommandOrder.make("regroup", ids, 1 if id == "split" else 0))
			notice.emit("%s: %s 지시" % [squad.name, "2개 조로 나누기" if id == "split" else "합치기"])
		"recall":
			order_issued.emit(CommandOrder.make("recall", ids))
			notice.emit("%s: 나간 대원 복귀 지시" % squad.name)
		"detach":
			open_solo_menu(_radial_squad, _radial_pos)


## 한 명 보내기: 맡길 임무 고르기 (커서 곁 목록). 못 맡기는 임무는 회색이고 올리면 이유가 보인다
func open_solo_menu(squad_id: int, screen_pos: Vector2) -> void:
	var squad := sim.units.squads[squad_id]
	var items: Array[Dictionary] = []
	var specs := sim.solo_specs()
	for k in specs.size():
		var s: Dictionary = specs[k]
		var why := sim.solo_reason(squad_id, str(s.id))
		items.append({"id": str(s.id), "label": "%d  %s" % [k + 1, str(s.label)], "enabled": why == "", "tip": str(s.get("hint", "")) if why == "" else why})
	open_menu("%s · 한 명 보내기" % squad.name, items, screen_pos, func(id: String) -> void:
		order_issued.emit(CommandOrder.make("solo", [squad_id] as Array[int], 0, Vector3i.ZERO, {"task": id}))
		notice.emit("%s: 한 명 보내기 — %s" % [squad.name, str(sim.solo_spec(id).get("label", id))]))

# --- 지시 창 (2026-11-16 사용자 결정): 분대를 고른 채 층을 우클릭 → 임무 + 진입구 + 지시. 임무를 주는 길은 이것 하나 ---

## 층을 우클릭했다: 임무(분대 종류의 기본 임무가 골라져 있다)와 진입구(가는 중인 문, 없으면 가까운 문)를 보이고
## Enter·'지시'로 보낸다. 건물 안 분대만이면 진입구 줄은 없다 (무전으로 지시)
func open_order(crew_ids: Array[int], level: int, screen_pos: Vector2) -> void:
	if crew_ids.is_empty() or not sim.building.has_level(level):
		return
	close_all()
	_order_crews = crew_ids.duplicate()
	order_level = level
	order_kind = selection.default_kind(crew_ids[0])
	if order_kind == "":
		order_kind = "search"
	# 진입구: 밖에 있는 분대가 있을 때만. 가까운 순 (첫 밖의 분대 기준)
	order_entries.clear()
	order_entry = -1
	var outside := -1
	for id in crew_ids:
		if outside < 0 and not sim.command.interior.crew_inside(id):
			outside = id
	if outside >= 0 and sim.entries:
		var from: Vector2 = sim.units.get_crew(outside).leader.pos
		var list: Array = sim.entries.list.duplicate()
		list.sort_custom(func(a: EntryPoints.Entry, b: EntryPoints.Entry) -> bool:
			return from.distance_to(Vector2(a.outside.x, a.outside.y)) < from.distance_to(Vector2(b.outside.x, b.outside.y)))
		for e: EntryPoints.Entry in list:
			order_entries.append(e.index)
		var going: EntryPoints.Entry = selection.entry_for(outside)
		order_entry = going.index if going else (order_entries[0] if not order_entries.is_empty() else -1)
	_rebuild_order()
	order.size = Vector2.ZERO
	order.reset_size()
	var area := get_viewport_rect().size
	var at := screen_pos if screen_pos.x >= 0.0 else area * 0.5 - order.size * 0.5
	order.position = Vector2(clampf(at.x + 14.0, 8.0, area.x - order.size.x - 8.0), clampf(at.y + 14.0, 8.0, area.y - order.size.y - 100.0))
	order.visible = true


## 지시 창에서 임무를 바꾼다 ("search"·"attack")
func pick_order_kind(kind: String) -> void:
	if not order.visible or not kind in order_kinds():
		return
	order_kind = kind
	_rebuild_order()


## 지시 창에 보일 임무: 인명검색·화재진압, 세대 배치가 있는 건물에서 아래층이 있으면 직하층 확인 (SOP 202 4.4)
func order_kinds() -> Array[String]:
	var out: Array[String] = ["search", "attack"]
	var layout := sim.tactical.layout
	if layout != null and not layout.units.is_empty() and sim.building.has_level(order_level - 1):
		out.append("check_below")
	return out


## 직하층 확인의 기준 칸: 그 층에서 불이 났던 방(타고 있거나 탄 자리), 없으면 층 가운데 — 그 세대 바로 아래 세대를 본다
func _below_target(lv: int) -> Vector3i:
	var fires: Dictionary = sim.tactical._fire_rooms(lv)
	for idx: int in fires:
		var room := sim.fire.comps[idx]
		if not room.cells.is_empty():
			return Vector3i(room.cells[0].x, room.cells[0].y, lv)
	var mid := Vector2i(sim.building.footprint(lv).get_center())
	return Vector3i(mid.x, mid.y, lv)


## 지시 창에서 진입구를 바꾼다 (EntryPoints 목록 index)
func pick_order_entry(entry_index: int) -> void:
	if not order.visible or not entry_index in order_entries:
		return
	order_entry = entry_index
	_rebuild_order()


## '지시': 그 층 단위 임무를 내린다. 초진 뒤 그 층에 보이는 불이 없으면 화재진압은 잔불정리가 된다
func confirm_order() -> void:
	if not order.visible or _order_crews.is_empty():
		return
	var crews := _order_crews.duplicate()
	var lv := order_level
	var names: PackedStringArray = []
	for id in crews:
		names.append(_crew_name(id))
	var via := Vector3i(-1, -1, -1)
	var via_name := ""
	if order_entry >= 0 and order_entry < sim.entries.list.size():
		var e: EntryPoints.Entry = sim.entries.list[order_entry]
		via = e.outside
		via_name = e.name
	close_order()
	var embers := selection.overhaul_target(lv) if order_kind == "attack" else Vector3i(-1, -1, -1)
	if embers.x >= 0:
		# 층 단위 잔불정리 (other = 1): 그 층의 탄 방을 차례로
		order_issued.emit(EquipmentCommand.make("overhaul", crews, -1, 1, embers))
		notice.emit("%s, %s 잔불정리 — 초진 뒤 불이 보이지 않아 탄 방을 차례로 열화상으로 확인·정리" % [" · ".join(names), sim.building.floor_name(lv)])
		return
	var fp := sim.building.footprint(lv)
	var mid := Vector2i(fp.get_center())
	var cmd := TacticalCommand.make(order_kind + "_floor", crews, Vector3i(mid.x, mid.y, lv), via)
	if order_kind == "check_below":
		cmd = TacticalCommand.make("check_below", crews, _below_target(lv), via)
	order_issued.emit(cmd)
	notice.emit("%s, %s%s" % [" · ".join(names), "%s로 진입 — " % via_name if via_name != "" else "", sim.command.interior.order_text(cmd)])


func close_order() -> void:
	if order:
		order.visible = false
	_order_crews.clear()


## 지시 창 내용을 다시 그린다 (임무·진입구 단추의 고른 표시)
func _rebuild_order() -> void:
	for ch in _order_box.get_children():
		ch.queue_free()
		_order_box.remove_child(ch)
	var names: PackedStringArray = []
	for id in _order_crews:
		names.append(_crew_name(id))
	var title := Label.new()
	title.text = "%s → %s" % [" · ".join(names), sim.building.floor_name(order_level)]
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("fde68a"))
	_order_box.add_child(title)
	_order_box.add_child(_order_caption("임무"))
	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 6)
	for k: String in order_kinds():
		var b := _order_button("%s  %s" % [ORDER_KEYS[k], ORDER_KINDS[k]], k == order_kind)
		b.custom_minimum_size = Vector2(130, 36)
		# 단추가 자기 신호 안에서 지워지지 않게 다음 프레임에 다시 그린다
		b.pressed.connect(func() -> void: pick_order_kind.call_deferred(k))
		kinds.add_child(b)
	_order_box.add_child(kinds)
	if order_entries.is_empty():
		_order_box.add_child(_order_caption("건물 안 분대 — 무전으로 지시합니다"))
	else:
		_order_box.add_child(_order_caption("진입구 (문 앞에서 진입 허가를 묻습니다)"))
		for n in order_entries.size():
			var e: EntryPoints.Entry = sim.entries.list[order_entries[n]]
			var parts: PackedStringArray = [e.name]
			var side := sim.entries.side(e)
			if side != "":
				parts.append(side)
			var smoke := sim.entries.smoke_text(e)
			if smoke != "":
				parts.append(smoke)
			var b := _order_button("%d  %s" % [n + 1, " · ".join(parts)], e.index == order_entry)
			b.custom_minimum_size = Vector2(306, 34)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var ei := e.index
			b.pressed.connect(func() -> void: pick_order_entry.call_deferred(ei))
			_order_box.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	var cancel := Button.new()
	cancel.text = "취소 (Esc)"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(close_order)
	row.add_child(cancel)
	var go := Button.new()
	go.text = "지시 (Enter)"
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(130, 38)
	go.add_theme_color_override("font_color", Color("fde68a"))
	go.pressed.connect(confirm_order)
	row.add_child(go)
	_order_box.add_child(row)
	order.size = Vector2.ZERO
	order.reset_size()


func _order_caption(text: String) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", Color("94a3b8"))
	return lab


## 고른 것은 노란 테두리·밝은 글씨 (라디오 단추처럼 하나만)
func _order_button(text: String, on: bool) -> Button:
	var b := Button.new()
	b.text = ("● " if on else "○ ") + text
	b.focus_mode = Control.FOCUS_NONE
	if on:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.98, 0.75, 0.14, 0.22)
		style.border_color = Color("fbbf24")
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(6)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, style)
		b.add_theme_color_override("font_color", Color("fde68a"))
	return b


func _build_order() -> void:
	order = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.12, 0.96)
	style.border_color = Color("fbbf24")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	order.add_theme_stylebox_override("panel", style)
	order.visible = false
	_order_box = VBoxContainer.new()
	_order_box.add_theme_constant_override("separation", 6)
	order.add_child(_order_box)
	add_child(order)


## 커서 곁 작은 목록. 숫자키 1~n·클릭으로 고르고 Esc·바깥 클릭으로 닫는다
func open_menu(title: String, items: Array[Dictionary], screen_pos: Vector2, on_pick: Callable) -> void:
	for ch in _menu_box.get_children():
		if ch != _menu_title:
			ch.queue_free()
	_menu_title.text = title
	menu_ids.clear()
	_menu_buttons.clear()
	for it in items:
		var b := Button.new()
		b.text = str(it.label)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(220, 34)
		b.disabled = not bool(it.get("enabled", true))
		b.tooltip_text = str(it.get("tip", ""))
		b.pressed.connect(pick.bind(str(it.id)))
		_menu_box.add_child(b)
		_menu_buttons.append(b)
		menu_ids.append(str(it.id))
	_menu_pick = on_pick
	menu.size = Vector2.ZERO
	menu.reset_size()
	var area := get_viewport_rect().size
	menu.position = Vector2(clampf(screen_pos.x + 12.0, 8.0, area.x - 260.0), clampf(screen_pos.y + 12.0, 8.0, area.y - 60.0 - 40.0 * items.size()))
	menu.visible = true


## 대상 메뉴에서 고름 (버튼·숫자키·테스트)
func pick(id: String) -> void:
	var f := _menu_pick
	close_menu()
	if f.is_valid():
		f.call(id)


func close_menu() -> void:
	if menu:
		menu.visible = false
	_menu_pick = Callable()


func _input(event: InputEvent) -> void:
	if order != null and order.visible:
		_order_input(event)
		return
	if menu == null or not menu.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var n: int = event.keycode - KEY_1
			if n < menu_ids.size():
				if not _menu_buttons[n].disabled:
					pick(menu_ids[n])
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not menu.get_global_rect().has_point(event.position):
		close_menu()


## 지시 창이 떠 있는 동안: Enter 지시 · Esc 취소 · 1~9 진입구 · Q/W 임무. 창 밖을 누르면 닫힌다 (그 클릭은 지도로 넘어간다)
func _order_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var handled := true
		if event.keycode == KEY_ESCAPE:
			close_order()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			confirm_order()
		elif event.keycode == KEY_Q:
			pick_order_kind("search")
		elif event.keycode == KEY_W:
			pick_order_kind("attack")
		elif event.keycode == KEY_E:
			pick_order_kind("check_below")
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var n: int = event.keycode - KEY_1
			if n < order_entries.size():
				pick_order_entry(order_entries[n])
		else:
			handled = false
		if handled:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not order.get_global_rect().has_point(event.position):
		close_order()


func _build_menu() -> void:
	menu = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.12, 0.96)
	style.border_color = Color("fbbf24")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	menu.add_theme_stylebox_override("panel", style)
	menu.visible = false
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 4)
	menu.add_child(_menu_box)
	_menu_title = Label.new()
	_menu_title.add_theme_font_size_override("font_size", 15)
	_menu_title.add_theme_color_override("font_color", Color("fde68a"))
	_menu_box.add_child(_menu_title)
	add_child(menu)


## 지원 투입할 조: 밖에 있고 임무가 없는 조 (같은 출동대 우선, 가까운 순). RIT·안전담당·구급대는 빼고
func support_crew(crew_id: int) -> int:
	var c := sim.units.get_crew(crew_id)
	if c == null:
		return -1
	var best := -1
	var best_d := INF
	for h in sim.units.crews:
		if h.solo or h.id == crew_id or h.leader.incapacitated or h.leader.aboard or sim.command.interior.crew_inside(h.id):
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


func _crew_name(crew_id: int) -> String:
	var c := sim.units.get_crew(crew_id)
	return sim.units.crew_name(c) if c else "—"
