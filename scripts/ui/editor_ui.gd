class_name ScenarioEditorUi
extends Control
## 시나리오 편집기 화면 (시작 화면에서 연다). 기존 시나리오를 사본으로 불러와
## 제목·설명·출동 지령·난이도·제한 시간을 고치고, 도면을 클릭해 발화점·구조대상자·관계인 위치를 정한 뒤 저장한다.
## 데이터 처리는 ScenarioDraft가 한다. 저장하면 시작 화면 목록에 "(추가)"로 나온다.

signal saved

enum Tool { IGNITION, VICTIM, WITNESS, ERASE }
const TOOL_NAMES := ["발화점 놓기", "구조대상자 놓기", "관계인 옮기기", "지우기"]

var draft: ScenarioDraft
var level := 1
var tool := Tool.IGNITION
var _sources: Array[String] = []
var _base: OptionButton
var _title: LineEdit
var _summary: TextEdit
var _dispatch: TextEdit
var _difficulty: OptionButton
var _limit: SpinBox
var _random: CheckBox
var _tool: OptionButton
var _floor: OptionButton
var _v_name: LineEdit
var _v_age: SpinBox
var _v_mob: OptionButton
var _v_window: CheckBox
var _v_evac: CheckBox
var _w_index: OptionButton
var _map: MapPreview
var _status: Label


## 도면 미리보기: 칸 색 + 발화점(빨강)·구조대상자(노랑)·관계인(파랑). 클릭하면 편집기에 칸을 알린다
class MapPreview:
	extends Control
	signal cell_clicked(cell: Vector2i)
	var ui: ScenarioEditorUi
	var cell_px := 8.0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			cell_clicked.emit(Vector2i((event.position / cell_px).floor()))

	func _draw() -> void:
		var d := ui.draft
		if d == null or d.building == null:
			return
		var b := d.building
		cell_px = floorf(minf(size.x / b.width, size.y / b.height))
		for y in b.height:
			for x in b.width:
				var t := b.cell(ui.level, x, y)
				draw_rect(Rect2(Vector2(x, y) * cell_px, Vector2.ONE * cell_px), PlanStyle.CELL_COLORS.get(t, Color.BLACK))
		for r: Dictionary in b.rooms(ui.level):
			var rr: Rect2i = r.rect
			draw_string(PlanStyle.font(), (Vector2(rr.position) + Vector2(0.3, 1.2)) * cell_px, str(r.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.6))
		for ig: Dictionary in d.ignitions():
			if int(ig.get("level", 1)) == ui.level:
				draw_circle(_px(ig.cell), cell_px * 0.8, Color("ef4444"))
		for v: Dictionary in d.victims():
			if int(v.get("level", 1)) == ui.level and v.has("cell"):
				var c := _px(v.cell)
				var r := cell_px * 0.9
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), Color("facc15"))
				draw_string(PlanStyle.font(), c + Vector2(-40, -r - 2), str(v.name), HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color("7c2d12"))
		if ui.level == b.levels()[0]:
			for w: Dictionary in d.witnesses():
				var p: Array = w.get("pos", [0, 0])
				draw_circle(_px(p), cell_px * 0.8, Color("60a5fa"))
				draw_string(PlanStyle.font(), _px(p) + Vector2(-40, -cell_px - 2), str(w.name), HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color("bfdbfe"))

	func _px(c: Array) -> Vector2:
		return (Vector2(float(c[0]), float(c[1])) + Vector2(0.5, 0.5)) * cell_px


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	# 위: 원본 선택·제목
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(_label("시나리오 편집기", 24, Color("fde68a")))
	_base = OptionButton.new()
	for s in ScenarioLoader.list():
		if s.errors.is_empty():
			_sources.append(str(s.path))
			_base.add_item(str(s.title))
	top.add_child(_base)
	top.add_child(_button("이 시나리오로 사본 만들기", _new_copy))
	_title = LineEdit.new()
	_title.placeholder_text = "제목"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_changed.connect(func(t: String) -> void: if draft: draft.set_title(t))
	top.add_child(_title)
	root.add_child(top)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)
	# 왼쪽: 도면
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tools := HBoxContainer.new()
	_floor = OptionButton.new()
	_floor.item_selected.connect(func(i: int) -> void:
		level = draft.building.levels()[i] if draft else 1
		_map.queue_redraw())
	tools.add_child(_floor)
	_tool = OptionButton.new()
	for t in TOOL_NAMES:
		_tool.add_item(t)
	_tool.item_selected.connect(func(i: int) -> void: tool = i as Tool)
	tools.add_child(_tool)
	_w_index = OptionButton.new()
	tools.add_child(_label("관계인", 15))
	tools.add_child(_w_index)
	left.add_child(tools)
	_map = MapPreview.new()
	_map.ui = self
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.custom_minimum_size = Vector2(580, 320)
	_map.cell_clicked.connect(_on_cell)
	left.add_child(_map)
	body.add_child(left)
	# 오른쪽: 글·구조대상자 속성
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(520, 0)
	right.add_child(_label("요약 (시작 화면 설명)", 15))
	_summary = _text_edit(80, func(t: String) -> void: draft.set_summary(t))
	right.add_child(_summary)
	right.add_child(_label("출동 지령 (한 줄에 한 항목)", 15))
	_dispatch = _text_edit(140, func(t: String) -> void: draft.set_dispatch_lines(t.split("\n")))
	right.add_child(_dispatch)
	var opts := HBoxContainer.new()
	_difficulty = OptionButton.new()
	for d in ["입문", "중급", "상급"]:
		_difficulty.add_item(d)
	_difficulty.item_selected.connect(func(i: int) -> void: if draft: draft.set_difficulty(_difficulty.get_item_text(i)))
	opts.add_child(_difficulty)
	opts.add_child(_label("제한 시간(분)", 15))
	_limit = SpinBox.new()
	_limit.min_value = 10
	_limit.max_value = 90
	_limit.value_changed.connect(func(v: float) -> void: if draft: draft.set_time_limit_min(int(v)))
	opts.add_child(_limit)
	_random = CheckBox.new()
	_random.text = "판마다 다른 시드"
	_random.toggled.connect(func(on: bool) -> void: if draft: draft.set_random_seed(on))
	opts.add_child(_random)
	right.add_child(opts)
	right.add_child(_label("구조대상자 속성 (다음에 놓을 사람)", 15, Color("fde68a")))
	var vrow := HBoxContainer.new()
	_v_name = LineEdit.new()
	_v_name.placeholder_text = "이름 (예: 할머니)"
	_v_name.custom_minimum_size = Vector2(150, 0)
	vrow.add_child(_v_name)
	_v_age = SpinBox.new()
	_v_age.min_value = 0
	_v_age.max_value = 100
	_v_age.value = 40
	vrow.add_child(_v_age)
	_v_mob = OptionButton.new()
	_v_mob.add_item("거동 가능")
	_v_mob.add_item("거동 불편")
	vrow.add_child(_v_mob)
	right.add_child(vrow)
	var vrow2 := HBoxContainer.new()
	_v_window = CheckBox.new()
	_v_window.text = "창가 (3층 이상이면 추락 위험)"
	vrow2.add_child(_v_window)
	_v_evac = CheckBox.new()
	_v_evac.text = "자력 대피"
	vrow2.add_child(_v_evac)
	right.add_child(vrow2)
	_status = _label("원본 시나리오를 고르고 '사본 만들기'를 누르세요. 저장 위치: %s" % ProjectSettings.globalize_path(ScenarioDraft.SAVE_DIR), 14, Color("94a3b8"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(500, 0)
	right.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_child(_button("저장·검증", _save))
	buttons.add_child(_button("닫기 (Esc)", queue_free))
	right.add_child(buttons)
	body.add_child(right)
	_new_copy()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()


## 고른 원본으로 사본을 만들고 화면 값을 채운다
func _new_copy() -> void:
	if _sources.is_empty():
		return
	load_draft(ScenarioDraft.from_base(_sources[_base.selected]))


func load_draft(d: ScenarioDraft) -> void:
	draft = d
	_title.text = str(d.data.get("title", ""))
	_summary.text = str(d.data.get("meta", {}).get("summary", ""))
	_dispatch.text = "\n".join(d.dispatch_lines())
	_difficulty.select(maxi(0, ["입문", "중급", "상급"].find(str(d.data.get("meta", {}).get("difficulty", "중급")))))
	_limit.value = int(d.data.get("evaluation", {}).get("time_limit_s", 2700)) / 60
	_random.button_pressed = bool(d.data.get("variation", {}).get("random_seed", false))
	_floor.clear()
	for lv in d.building.levels():
		_floor.add_item(d.building.floor_name(lv))
	level = d.building.levels()[0]
	_w_index.clear()
	for w: Dictionary in d.witnesses():
		_w_index.add_item(str(w.get("name", "")))
	_status.text = "사본: %s — 도면을 클릭해 고치고 저장하세요." % d.data.id
	_map.queue_redraw()


func _on_cell(cell: Vector2i) -> void:
	if draft == null:
		return
	var err := ""
	match tool:
		Tool.IGNITION:
			err = draft.add_ignition(level, cell)
		Tool.VICTIM:
			err = draft.add_victim(level, cell, _v_name.text, int(_v_age.value), ScenarioDraft.MOBILITY[_v_mob.selected], _v_window.button_pressed, _v_evac.button_pressed)
		Tool.WITNESS:
			err = draft.move_witness(_w_index.selected, cell)
		Tool.ERASE:
			err = "" if draft.remove_near(level, cell) else "이 층 그 자리 근처에 지울 발화점·구조대상자가 없습니다."
	_status.text = err if err != "" else "%s — %s (%d, %d)" % [TOOL_NAMES[tool], draft.building.floor_name(level), cell.x, cell.y]
	_map.queue_redraw()


func _save() -> void:
	if draft == null:
		return
	var errors := draft.save()
	if errors.is_empty():
		_status.text = "저장했습니다: %s — 시작 화면 목록에 '(추가)'로 나옵니다." % ProjectSettings.globalize_path(draft.path)
		saved.emit()
	else:
		_status.text = "저장했지만 고칠 곳이 있습니다 (고치기 전에는 시작할 수 없음):\n• " + "\n• ".join(errors)


func _label(text: String, size_px: int, color := Color("e2e8f0")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	return b


func _text_edit(height: float, on_change: Callable) -> TextEdit:
	var t := TextEdit.new()
	t.custom_minimum_size = Vector2(0, height)
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.text_changed.connect(func() -> void: if draft: on_change.call(t.text))
	return t
