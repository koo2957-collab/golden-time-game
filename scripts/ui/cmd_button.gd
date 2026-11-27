class_name CmdButton
extends Button
## 오른쪽 정보 창의 명령 칸 하나 (2026-11-27 — 스타크래프트 명령판처럼): 가운데 선 아이콘, 아래 짧은 이름, 왼쪽 위 단축키.
## 상태 표시 (사용자 결정 — 상용 게임 방식):
##   STATE_TARGET  명령을 누르고 대상(층·지점)을 고르는 중 → 노란 테두리가 천천히 깜빡인다
##   STATE_ACTIVE  고른 조가 지금 이 명령을 수행 중 → 고정 노란 테두리 + 오른쪽 위 작은 점
## 쓸 수 없는 칸은 흐리고, 마우스를 올리면 이유가 툴팁에 나온다.

const STATE_NONE := 0
const STATE_TARGET := 1
const STATE_ACTIVE := 2

var cmd_id := ""
var label_text := ""
var key_text := ""
var danger := false
var more := false
var state := STATE_NONE:
	set(v):
		if v == state:
			return
		state = v
		set_process(state == STATE_TARGET)
		queue_redraw()
## 이미 한 명령 (지휘관 명령 — 선언·완진 등): 오른쪽 위에 초록 ✓ (2026-11-27)
var done := false:
	set(v):
		if v != done:
			done = v
			queue_redraw()
## 오른쪽 위 빨간 숫자 (접어 둔 동안 들어온 긴급 무전 수 등). 0 이면 없음
var badge := 0:
	set(v):
		if v != badge:
			badge = v
			queue_redraw()
## 아이콘 크기(px). 0 이면 설정값
var icon_px := 0.0
var style: SidePanelStyle


func _init() -> void:
	style = SidePanelStyle.get_default()
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = style.button_size
	text = ""
	for name in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(name, _box(name))
	set_process(false)


func _box(kind: String) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.set_corner_radius_all(6)
	b.bg_color = Color(0.09, 0.13, 0.2, 0.95)
	b.border_color = Color(0.5, 0.6, 0.75, 0.22)
	b.set_border_width_all(1)
	match kind:
		"hover", "hover_pressed":
			b.bg_color = Color(0.14, 0.2, 0.3, 0.98)
			b.border_color = Color(0.7, 0.8, 0.95, 0.5)
		"pressed":
			b.bg_color = Color(0.2, 0.27, 0.38, 1.0)
		"disabled":
			b.bg_color = Color(0.07, 0.1, 0.15, 0.7)
			b.border_color = Color(0.5, 0.6, 0.75, 0.1)
		"focus":
			b.draw_center = false
			b.set_border_width_all(0)
	return b


func set_item(id: String, label: String, key: String, p_danger: bool, p_more: bool) -> void:
	cmd_id = id
	label_text = label
	key_text = key
	danger = p_danger
	more = p_more
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var on := not disabled and cmd_id != ""
	if done and disabled:
		on = true  # 이미 한 명령은 흐리지 않고 ✓ 로 보인다 (누를 수는 없다)
	var fg := Color("fca5a5") if danger else SidePanelStyle.TEXT
	if not on:
		fg = Color(SidePanelStyle.MUTED, 0.55)
	elif done:
		fg = SidePanelStyle.DIM
	if state == STATE_ACTIVE or (toggle_mode and button_pressed):
		fg = style.accent
	# 켜 둔 단추(펼친 묶음·무전 기록): 고정 노란 테두리 (점 없음)
	if toggle_mode and button_pressed and state == STATE_NONE:
		var tb := StyleBoxFlat.new()
		tb.bg_color = Color(style.accent, 0.1)
		tb.border_color = style.accent
		tb.set_border_width_all(2)
		tb.set_corner_radius_all(6)
		draw_style_box(tb, Rect2(Vector2(1, 1), size - Vector2(2, 2)))
	elif danger and on and state == STATE_NONE:
		var db := StyleBoxFlat.new()
		db.draw_center = false
		db.border_color = Color(SidePanelStyle.DANGER, 0.45)
		db.set_border_width_all(1)
		db.set_corner_radius_all(6)
		draw_style_box(db, Rect2(Vector2.ZERO, size))
	# 테두리: 수행 중 = 고정, 고르는 중 = 깜빡임
	if state != STATE_NONE:
		var a := 1.0
		if state == STATE_TARGET:
			a = 0.35 + 0.65 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * style.blink_hz))
		var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		var sb := StyleBoxFlat.new()
		sb.draw_center = state == STATE_ACTIVE
		sb.bg_color = Color(style.accent, 0.1)
		sb.border_color = Color(style.accent, a)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		draw_style_box(sb, r)
		if state == STATE_ACTIVE:
			draw_circle(Vector2(size.x - 9.0, 9.0), 3.5, style.accent)
	if cmd_id == "":
		return
	# 단축키 (왼쪽 위 작은 글자)
	if key_text != "":
		draw_string(font, Vector2(7, 15), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(SidePanelStyle.DIM, 0.9 if on else 0.4))
	# 아이콘
	var ic := Vector2(size.x * 0.5, size.y * 0.42)
	CmdIcon.draw(self, cmd_id, ic, icon_px if icon_px > 0.0 else style.icon_px, fg)
	# 완료 ✓ (초록) · 숫자 (빨강)
	if done:
		var c := Vector2(size.x - 11.0, 11.0)
		draw_circle(c, 7.0, Color(SidePanelStyle.OK, 0.9))
		draw_polyline(PackedVector2Array([c + Vector2(-3.5, 0), c + Vector2(-1, 2.8), c + Vector2(3.8, -2.6)]), Color(0.04, 0.1, 0.06), 1.8, true)
	if badge > 0:
		var c := Vector2(size.x - 12.0, 12.0)
		draw_circle(c, 8.5, SidePanelStyle.DANGER)
		draw_string(font, c + Vector2(-8.5, 4.5), str(mini(badge, 99)), HORIZONTAL_ALIGNMENT_CENTER, 17.0, 12, Color.WHITE)
	# 이름 (아래 가운데). 하위 칸이 있으면 …
	var t := label_text + ("…" if more else "")
	var fs := 13
	while fs > 10 and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 8.0:
		fs -= 1
	draw_string(font, Vector2(4, size.y - 8.0), t, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8.0, fs, fg)
