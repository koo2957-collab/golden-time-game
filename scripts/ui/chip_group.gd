class_name ChipGroup
extends HFlowContainer
## 칩 단추 묶음 (2026-11-27 사용자 결정: 지휘권 선언 양식의 드롭다운·체크박스 대신 한 번 눌러 고르는 칩 — EMERGENCY·시티즈 옆 패널 방식).
##   multi = false: 하나만 고른다 (다른 칩을 누르면 옮겨 가고, 고른 칩을 다시 누르면 풀린다)
##   multi = true: 여럿 고른다 (고른 칩 앞에 ✓)
## 모양은 오른쪽 정보 창(SidePanelStyle)과 같은 색: 어두운 칩 + 고르면 노란 테두리

signal changed

const FONT_PX := 15
const RADIUS := 13

var multi := false
var _buttons: Array[Button] = []


func setup(items: Array, p_multi := false) -> ChipGroup:
	multi = p_multi
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 6)
	for it in items:
		var b := Button.new()
		b.text = str(it)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		style_chip(b)
		b.toggled.connect(_on_toggled.bind(b))
		add_child(b)
		_buttons.append(b)
	return self


## 칩 모양 (다른 창의 칩·작은 단추도 같은 모양을 쓰게 static)
static func style_chip(b: Button) -> void:
	var accent := SidePanelStyle.get_default().accent
	var normal := _box(SidePanelStyle.CHIP_BG, SidePanelStyle.LINE, 1)
	var hover := _box(SidePanelStyle.CHIP_BG.lightened(0.08), Color(accent, 0.55), 1)
	var on := _box(Color(accent, 0.16), accent, 2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("disabled", _box(Color(SidePanelStyle.CHIP_BG, 0.5), Color(SidePanelStyle.LINE, 0.1), 1))
	b.add_theme_font_size_override("font_size", FONT_PX)
	b.add_theme_color_override("font_color", SidePanelStyle.TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", accent.lightened(0.45))
	b.add_theme_color_override("font_hover_pressed_color", accent.lightened(0.45))
	b.add_theme_color_override("font_disabled_color", SidePanelStyle.MUTED)


static func _box(bg: Color, line: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = line
	s.set_border_width_all(width)
	s.set_corner_radius_all(RADIUS)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 5
	s.anti_aliasing = true
	return s


func _on_toggled(on: bool, b: Button) -> void:
	if on and not multi:
		for o in _buttons:
			if o != b and o.button_pressed:
				o.set_pressed_no_signal(false)
	_mark()
	changed.emit()


## 여럿 고르기: 고른 칩 앞에 ✓
func _mark() -> void:
	if not multi:
		return
	for b in _buttons:
		var t := b.text.trim_prefix("✓ ")
		b.text = ("✓ " + t) if b.button_pressed else t


func chip_text(b: Button) -> String:
	return b.text.trim_prefix("✓ ")


## 하나 고르기: 고른 칩 글자 (없으면 "")
func selected_text() -> String:
	for b in _buttons:
		if b.button_pressed:
			return chip_text(b)
	return ""


## 고른 칩 번호 (없으면 -1)
func selected_index() -> int:
	for i in _buttons.size():
		if _buttons[i].button_pressed:
			return i
	return -1


## 여럿 고르기: 고른 칩 글자들 (보기 순서)
func picked() -> Array[String]:
	var out: Array[String] = []
	for b in _buttons:
		if b.button_pressed:
			out.append(chip_text(b))
	return out


func has_choice() -> bool:
	return selected_index() >= 0


## 글자로 고른다 (하나 고르기면 나머지는 풀린다, 여럿이면 그 칩을 켠다)
func select_text(text: String) -> void:
	for b in _buttons:
		if chip_text(b) == text:
			b.set_pressed_no_signal(true)
		elif not multi:
			b.set_pressed_no_signal(false)
	_mark()
	changed.emit()


func select_index(i: int) -> void:
	if i >= 0 and i < _buttons.size():
		select_text(chip_text(_buttons[i]))


func clear() -> void:
	for b in _buttons:
		b.set_pressed_no_signal(false)
	_mark()
	changed.emit()


func buttons() -> Array[Button]:
	return _buttons
