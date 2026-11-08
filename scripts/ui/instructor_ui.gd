class_name InstructorUi
extends Control
## 교관 설정 화면 (시작 화면에서 연다). 이번 주 훈련 시나리오와 안내 문구, 시작 화면 기본값,
## 수치 덮어쓰기(화재 위험·구급·대원 안전)를 user://instructor.json에 저장한다.
## 결과 파일에는 바뀐 수치가 함께 남는다 (instructor_params).

signal saved

var _weekly: OptionButton
var _note: LineEdit
var _mode: OptionButton
var _difficulty: OptionButton
var _status: Label
var _spins: Dictionary = {}  # "표.키" -> SpinBox
var _defaults: Dictionary = {}  # "표.키" -> 기본값
var _scenario_ids: Array[String] = [""]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = "교관 설정"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("fde68a"))
	box.add_child(title)
	var settings := InstructorSettings.load_settings()
	# 이번 주 훈련
	var week := HBoxContainer.new()
	week.add_theme_constant_override("separation", 10)
	week.add_child(_label("이번 주 훈련"))
	_weekly = OptionButton.new()
	_weekly.custom_minimum_size = Vector2(420, 40)
	_weekly.add_item("(지정 안 함)")
	var current := str(settings.get("weekly", {}).get("scenario", ""))
	for s in ScenarioLoader.list():
		_scenario_ids.append(str(s.id))
		_weekly.add_item(str(s.title))
		if str(s.id) == current:
			_weekly.select(_weekly.item_count - 1)
	week.add_child(_weekly)
	_note = LineEdit.new()
	_note.placeholder_text = "안내 문구 (예: 이번 주 중점 — 가스 차단과 경계관창)"
	_note.text = str(settings.get("weekly", {}).get("note", ""))
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	week.add_child(_note)
	box.add_child(week)
	# 시작 화면 기본값
	var defs := HBoxContainer.new()
	defs.add_theme_constant_override("separation", 10)
	defs.add_child(_label("시작 화면 기본값"))
	_mode = OptionButton.new()
	for m in ["평가 모드", "교육 모드"]:
		_mode.add_item(m)
	_mode.select(1 if str(settings.get("defaults", {}).get("mode", "평가")) == "교육" else 0)
	defs.add_child(_mode)
	_difficulty = OptionButton.new()
	for d in ["시나리오 난이도", "입문", "중급", "상급"]:
		_difficulty.add_item(d)
	_difficulty.select(maxi(0, ["", "입문", "중급", "상급"].find(str(settings.get("defaults", {}).get("difficulty", "")))))
	defs.add_child(_difficulty)
	box.add_child(defs)
	# 수치
	box.add_child(_label("수치 덮어쓰기 — 기본값은 교재·추정값 (마우스를 올리면 설명). 바꾼 값은 결과 파일에 기록된다", Color("94a3b8")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	scroll.add_child(grid)
	var over: Dictionary = settings.get("params", {})
	for table: String in InstructorSettings.TABLES:
		var spec: Array = InstructorSettings.TABLES[table]
		var data: Variant = JsonData.load_file(str(spec[1]))
		if not data is Dictionary:
			continue
		for key: String in data:
			if not data[key] is Dictionary or not data[key].has("value"):
				continue
			var base := float(data[key].value)
			var name := "%s.%s" % [table, key]
			_defaults[name] = base
			var l := _label("%s · %s" % [str(spec[0]).get_slice(" ", 0), key])
			l.tooltip_text = "%s\n기본값 %s (%s)" % [data[key].get("note", ""), base, data[key].get("source", "")]
			l.mouse_filter = Control.MOUSE_FILTER_STOP
			grid.add_child(l)
			var spin := SpinBox.new()
			spin.min_value = 0.0
			spin.max_value = maxf(10000.0, base * 10.0)
			spin.step = 0.01 if base < 10.0 else 1.0
			spin.value = float(over.get(table, {}).get(key, base))
			spin.custom_minimum_size = Vector2(150, 0)
			_spins[name] = spin
			grid.add_child(spin)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	_status = _label("저장 위치: %s" % ProjectSettings.globalize_path(InstructorSettings.PATH), Color("94a3b8"))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	row.add_child(_button("기본값으로", _reset))
	row.add_child(_button("저장", _save))
	row.add_child(_button("닫기 (Esc)", queue_free))
	box.add_child(row)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()


## 화면 값 → 설정 사전 (기본값과 같은 수치는 넣지 않는다)
func collect() -> Dictionary:
	var params := {}
	for name: String in _spins:
		var v: float = _spins[name].value
		if absf(v - float(_defaults[name])) > 0.0001:
			var parts := name.split(".")
			if not params.has(parts[0]):
				params[parts[0]] = {}
			params[parts[0]][parts[1]] = v
	var out := {"params": params, "defaults": {
		"mode": "교육" if _mode.selected == 1 else "평가",
		"difficulty": ["", "입문", "중급", "상급"][_difficulty.selected],
	}}
	if _weekly.selected > 0:
		out["weekly"] = {"scenario": _scenario_ids[_weekly.selected], "note": _note.text}
	return out


func _save() -> void:
	var ok := InstructorSettings.save_settings(collect())
	_status.text = "저장했습니다." if ok else "저장 실패"
	saved.emit()


func _reset() -> void:
	for name: String in _spins:
		_spins[name].value = _defaults[name]


func _label(text: String, color := Color("e2e8f0")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b
