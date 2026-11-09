class_name DisplayUi
extends Control
## 화면 설정 화면 (시작 화면에서 연다). 해상도·창/전체 화면·프레임 상한을 고르고 바로 적용해 user://display.json에 저장한다.

var _resolution: OptionButton
var _screen_mode: OptionButton
var _fps: OptionButton
var _low_spec: CheckBox
var _status: Label


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
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	var title := Label.new()
	title.text = "화면 설정"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("fde68a"))
	box.add_child(title)
	var s := DisplaySettings.load_settings()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)

	_resolution = _option(DisplaySettings.RESOLUTION_ORDER.map(func(k: String) -> String: return DisplaySettings.RESOLUTION_NAMES[k]))
	_resolution.select(DisplaySettings.RESOLUTION_ORDER.find(s.resolution))
	_row(grid, "해상도", _resolution, "창 모드의 창 크기 (창이 화면보다 크면 최대화)")

	_screen_mode = _option(["창", "전체 화면"])
	_screen_mode.select(1 if s.fullscreen else 0)
	_screen_mode.item_selected.connect(func(_i: int) -> void: _resolution.disabled = _screen_mode.selected == 1)
	_resolution.disabled = s.fullscreen
	_row(grid, "화면 모드", _screen_mode, "전체 화면은 모니터 해상도로 띄웁니다")

	_fps = _option(DisplaySettings.FPS_OPTIONS.map(func(f: int) -> String: return "%d프레임%s" % [f, " (저사양 PC 권장)" if f < 60 else " (기본)"]))
	_fps.select(DisplaySettings.FPS_OPTIONS.find(int(s.fps)))
	_row(grid, "화면 갱신", _fps, "30프레임이면 화면을 그리는 횟수가 절반이라 내장그래픽·저사양 PC에서 부드럽게 돕니다 (시뮬레이션 속도는 같음)")
	_low_spec = CheckBox.new()
	_low_spec.text = "켜기"
	_low_spec.button_pressed = bool(s.get("low_spec", false))
	_row(grid, "저사양 모드", _low_spec, "30프레임 고정 + 효과 축소(단면 보기에서 함께 쌓는 층 수를 줄임). 교육장 PC가 느릴 때 (기획안 9-5)")

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	_status = _label("저장 위치: %s" % ProjectSettings.globalize_path(DisplaySettings.PATH), Color("94a3b8"))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	row.add_child(_button("기본값으로", _reset))
	row.add_child(_button("적용·저장", _save))
	row.add_child(_button("닫기 (Esc)", queue_free))
	box.add_child(row)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()


## 화면 값 → 설정 사전
func collect() -> Dictionary:
	return {
		"resolution": DisplaySettings.RESOLUTION_ORDER[_resolution.selected],
		"fullscreen": _screen_mode.selected == 1,
		"fps": DisplaySettings.FPS_OPTIONS[_fps.selected],
		"low_spec": _low_spec.button_pressed,
	}


func _save() -> void:
	var data := collect()
	DisplaySettings.apply(get_window(), data)
	var ok := DisplaySettings.save_settings(data)
	_status.text = "적용하고 저장했습니다. 다음 실행 때도 이 설정으로 시작합니다." if ok else "적용했지만 저장하지 못했습니다."


func _reset() -> void:
	var d := DisplaySettings.DEFAULTS
	_resolution.select(DisplaySettings.RESOLUTION_ORDER.find(d.resolution))
	_screen_mode.select(1 if d.fullscreen else 0)
	_resolution.disabled = d.fullscreen
	_fps.select(DisplaySettings.FPS_OPTIONS.find(int(d.fps)))
	_low_spec.button_pressed = false


func _row(grid: GridContainer, name: String, control: Control, note: String) -> void:
	grid.add_child(_label(name))
	grid.add_child(control)
	grid.add_child(_label(note, Color("94a3b8")))


func _option(items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.custom_minimum_size = Vector2(320, 44)
	o.add_theme_font_size_override("font_size", 18)
	for item in items:
		o.add_item(str(item))
	return o


func _label(text: String, color := Color("e2e8f0")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b
