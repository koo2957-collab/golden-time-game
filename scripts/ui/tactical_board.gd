class_name TacticalBoard
extends Control
## 전술상황판 (기획안 9-2-1, P10-1): 아래 바 단추·Tab·M으로 여닫는 판. 게임은 계속 간다.
## 2026-11-14 화이트보드 (사용자 결정): 화면의 85%, 가로형 16:9, 알루미늄 틀·모서리 캡·마커 받침이 있는 흰 판 한 장.
## 판 위의 글은 모두 보드마커 손글씨. 모양·비율·글꼴은 data/ui/board_style.json.
##   맨 위 줄: "전술상황판" + 층 탭(외부 / 1층 / …) + 닫기
##   왼쪽 60%: 도면 (BoardMap — 무전 보고만)
##   오른쪽 40%: 선으로 나눈 정보 칸 세 줄 — 2026-11-15 사용자 결정: 글자를 키우고 중요한 것만 (칸마다 판 폭을 다 쓴다)
##     ① 전략 · 우선순위: 전략 한 줄 + 지금 해당하는 우선순위(대원 안전 → RECEO, 가장 급한 것은 빨강) + 확인 필요 몇 건
##     ② 임무 부여 · 진입대원 통제 (팀 카드 — 보기만, 임무는 지도에서 층 우클릭 지시 창으로), 통솔범위는 넘었을 때만
##     ③ 구조대상자 · 물 · 출동대(오는 중·대기 중인 출동대만)
##   뺀 것: 출동 지령 원문·둘러보기(→ 현장 정보 창), 해당 없는 우선순위 줄, 구역 한 줄(외부 도면에 그려진다), 출동대별 진입 상태
## 열려 있을 때만 2Hz로 다시 그린다 (사무용 PC). 질문 카드는 이보다 위에 뜬다.

const REFRESH_S := 0.5


## 흰 판 한 장: 그림자, 알루미늄 틀, 모서리 캡, 흰 면, 아래 마커 받침과 마커 두 자루 (참고: 사용자 제공 화이트보드 사진)
class BoardFrame:
	extends Control

	var style: BoardStyle

	func _draw() -> void:
		if style == null:
			return
		var f := style.frame_px
		var body := Rect2(Vector2.ZERO, Vector2(size.x, size.y - style.tray_px))
		draw_rect(Rect2(body.position + Vector2(5.0, 7.0), body.size), style.color("shadow", 0.35))
		# 틀: 바깥 어두운 선 → 알루미늄 → 안쪽 밝은 줄
		draw_rect(body, style.color("frame"))
		draw_rect(body.grow(-f * 0.3), style.color("frame_light"), false, maxf(1.0, f * 0.2))
		draw_rect(body, style.color("frame_dark"), false, 1.0)
		# 흰 면
		var face := body.grow(-f)
		draw_rect(face, style.color("board"))
		draw_rect(face, style.color("frame_dark"), false, 1.0)
		# 모서리 캡 (짙은 회색, 둥근 모서리)
		var cap := StyleBoxFlat.new()
		cap.bg_color = style.color("corner")
		cap.set_corner_radius_all(roundi(style.corner_px * 0.22))
		var c := style.corner_px
		var inset := -2.0
		for p: Vector2 in [Vector2(inset, inset), Vector2(body.size.x - c - inset, inset),
				Vector2(inset, body.size.y - c - inset), Vector2(body.size.x - c - inset, body.size.y - c - inset)]:
			draw_style_box(cap, Rect2(p, Vector2(c, c)))
		# 마커 받침
		var tray := Rect2(size.x * 0.08, body.end.y - 2.0, size.x * 0.84, style.tray_px)
		draw_rect(tray, style.color("frame"))
		draw_rect(Rect2(tray.position, Vector2(tray.size.x, 2.0)), style.color("frame_light"))
		draw_rect(Rect2(tray.position + Vector2(0.0, tray.size.y - 2.0), Vector2(tray.size.x, 2.0)), style.color("frame_dark"))
		# 마커 두 자루 (파랑·검정)
		var x := tray.position.x + 26.0
		for key: String in ["marker_blue", "ink"]:
			var pen := Rect2(x, tray.position.y - 7.0, 58.0, 8.0)
			draw_rect(pen, Color("eef0f2"))
			draw_rect(pen, style.color("frame_dark"), false, 1.0)
			draw_rect(Rect2(pen.position, Vector2(16.0, pen.size.y)), style.color(key))
			draw_rect(Rect2(pen.end.x - 4.0, pen.position.y + 2.0, 5.0, pen.size.y - 4.0), style.color(key))
			x += 74.0


var sim: SimWorld
var style: BoardStyle
var map: BoardMap
## 흰 판 (틀·받침 포함)
var frame: BoardFrame
## 도면 칸과 정보 칸 묶음 (비율 점검용)
var map_cell: PanelContainer
var info_cell: PanelContainer
var _ui: CommandUi
var _tabs: HBoxContainer
var _entry: Label
var _receo: RichTextLabel
var _span: Label
var _status: RichTextLabel
var _refresh := 0.0


## command_ui의 팀 카드(진입대원 통제표)는 이 판으로 옮겨 쓰고, 나머지 글은 command_ui의 글을 받아 마커 글씨로 다시 쓴다
func setup(p_sim: SimWorld, ui: CommandUi) -> void:
	sim = p_sim
	_ui = ui
	style = BoardStyle.get_default()
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 팀 카드 글자색을 마커 색으로
	ui.paper_palette = {"text": style.color("ink"), "dim": style.color("ink_soft"),
		"warn": style.color("marker_orange"), "danger": style.color("marker_red")}
	# 화면의 85% 안에 16:9로 맞춘 판
	var fit := AspectRatioContainer.new()
	var edge := (1.0 - style.board_screen_ratio) * 0.5
	fit.anchor_left = edge
	fit.anchor_top = edge
	fit.anchor_right = 1.0 - edge
	fit.anchor_bottom = 1.0 - edge
	fit.ratio = style.board_aspect
	fit.stretch_mode = AspectRatioContainer.STRETCH_FIT
	fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fit)
	frame = BoardFrame.new()
	frame.style = style
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	fit.add_child(frame)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := roundi(style.frame_px) + 8
	# 왼쪽·오른쪽은 모서리 캡에 글자가 걸리지 않을 만큼
	var side := maxi(inset + 4, roundi(style.corner_px) + 4)
	pad.add_theme_constant_override("margin_left", side)
	pad.add_theme_constant_override("margin_right", side)
	pad.add_theme_constant_override("margin_top", inset)
	pad.add_theme_constant_override("margin_bottom", inset + roundi(style.tray_px) + 2)
	frame.add_child(pad)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	pad.add_child(outer)
	_build_head(outer)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	outer.add_child(body)
	# 왼쪽 — 도면
	map_cell = PanelContainer.new()
	map_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_cell.size_flags_stretch_ratio = style.map_ratio
	# 안쪽 여백 = 선 굵기 (도면이 선을 덮지 않게)
	map_cell.add_theme_stylebox_override("panel", _line_box(true, true, false, true, style.cell_line_px))
	body.add_child(map_cell)
	map = BoardMap.new()
	map.setup(sim)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_cell.add_child(map)
	# 오른쪽 — 정보 칸
	info_cell = PanelContainer.new()
	info_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_cell.size_flags_stretch_ratio = 1.0 - style.map_ratio
	info_cell.add_theme_stylebox_override("panel", _line_box(false, false, true, true, 0))
	body.add_child(info_cell)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	info_cell.add_child(rows)
	var top := _cell(_row(rows, 0), "전략 · 우선순위")
	_entry = _text(top)
	_entry.add_theme_font_override("font", style.marker_bold())
	_receo = _rich(top)
	var teams := _cell(_row(rows, 1), "임무 부여 · 진입대원 통제")
	ui.team_compact = true
	_move_teams(teams)
	_span = _text(teams, "marker_red")
	_status = _rich(_cell(_row(rows, 2), "구조대상자 · 물 · 출동대"))
	_build_tabs()


## 맨 위 줄: 제목 + 안내 + 층 탭 + 닫기
func _build_head(outer: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "전술상황판"
	title.add_theme_font_override("font", style.marker_bold())
	title.add_theme_font_size_override("font_size", style.title_font)
	title.add_theme_color_override("font_color", style.color("ink"))
	head.add_child(title)
	var note := Label.new()
	note.text = "무전으로 보고된 것만"
	note.add_theme_font_override("font", style.marker_font())
	note.add_theme_font_size_override("font_size", style.body_font)
	note.add_theme_color_override("font_color", style.color("ink_soft"))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_END
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(note)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	head.add_child(_tabs)
	var close := _marker_button("닫기", false)
	close.pressed.connect(toggle)
	head.add_child(close)
	outer.add_child(head)


## 정보 칸 한 줄 (높이 비율은 info_rows)
func _row(rows: VBoxContainer, index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.size_flags_stretch_ratio = float(style.info_rows[index]) if index < style.info_rows.size() else 1.0
	rows.add_child(row)
	return row


## 칸 하나: 왼쪽·위 선 + 파란 마커 제목 + 내용(넘치면 휠로 넘김). 내용을 넣을 상자를 돌려준다
func _cell(row: Container, title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.clip_contents = true
	p.add_theme_stylebox_override("panel", _line_box(true, true, false, false, style.cell_pad_px))
	row.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var head := Label.new()
	head.text = title
	head.add_theme_font_override("font", style.marker_bold())
	head.add_theme_font_size_override("font_size", style.head_font)
	head.add_theme_color_override("font_color", style.color("marker_blue"))
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)
	return box


## 칸을 나누는 마커 선 (고른 변에만), pad = 안쪽 여백
func _line_box(left: bool, top: bool, right: bool, bottom: bool, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = style.color("ink")
	var w := style.cell_line_px
	sb.border_width_left = w if left else 0
	sb.border_width_top = w if top else 0
	sb.border_width_right = w if right else 0
	sb.border_width_bottom = w if bottom else 0
	sb.set_content_margin_all(pad)
	return sb


## 마커 글씨 한 덩어리 (자동 줄바꿈)
func _text(to: Container, color_key := "ink") -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", style.marker_font())
	l.add_theme_font_size_override("font_size", style.body_font)
	l.add_theme_color_override("font_color", style.color(color_key))
	l.add_theme_constant_override("line_spacing", -1)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to.add_child(l)
	return l


## 색을 섞어 쓰는 마커 글씨 (검정·파랑·빨강)
func _rich(to: Container) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("normal_font", style.marker_font())
	l.add_theme_font_override("bold_font", style.marker_bold())
	l.add_theme_font_size_override("normal_font_size", style.body_font)
	l.add_theme_font_size_override("bold_font_size", style.body_font)
	l.add_theme_color_override("default_color", style.color("ink"))
	l.add_theme_constant_override("line_separation", -1)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to.add_child(l)
	return l


## 층 탭·닫기: 마커로 쓴 글씨, 고른 것은 파란 네모
func _marker_button(text: String, toggle_mode: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle_mode
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", style.marker_bold())
	b.add_theme_font_size_override("font_size", style.head_font)
	for key in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(key, style.color("ink"))
	for key in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, style.color("marker_blue"))
	var plain := StyleBoxFlat.new()
	plain.draw_center = false
	plain.set_content_margin_all(2)
	plain.content_margin_left = 9
	plain.content_margin_right = 9
	var hover: StyleBoxFlat = plain.duplicate()
	hover.draw_center = true
	hover.bg_color = style.color("highlight", 0.6)
	hover.set_corner_radius_all(4)
	var picked: StyleBoxFlat = plain.duplicate()
	picked.border_color = style.color("marker_blue")
	picked.set_border_width_all(2)
	picked.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", plain)
	b.add_theme_stylebox_override("focus", plain)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", picked)
	b.add_theme_stylebox_override("hover_pressed", picked)
	return b


## 팀 카드(진입대원 통제표) 묶음을 이 칸으로 옮긴다. 단추 모양은 _style_team_cards가 판에 맞게 바꾼다
func _move_teams(to: Container) -> void:
	var box := _ui._team_box
	if box == null:
		return
	if box.get_parent():
		box.get_parent().remove_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	to.add_child(box)


## 팀 카드를 흰 판의 표 한 줄처럼: 마커 글씨, 아래 가는 줄, 마우스를 올리면 형광펜
func _style_team_cards() -> void:
	for id: int in _ui._team_buttons:
		var b: Button = _ui._team_buttons[id]
		if b.has_meta("paper"):
			continue
		b.set_meta("paper", true)
		b.custom_minimum_size = Vector2.ZERO
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_override("font", style.marker_font())
		b.add_theme_font_size_override("font_size", style.body_font)
		var line := StyleBoxFlat.new()
		line.draw_center = false
		line.border_color = style.color("ink_soft", 0.6)
		line.border_width_bottom = 1
		line.set_content_margin_all(3)
		var hover: StyleBoxFlat = line.duplicate()
		hover.draw_center = true
		hover.bg_color = style.color("highlight", 0.6)
		for key in ["normal", "focus", "pressed"]:
			b.add_theme_stylebox_override(key, line)
		b.add_theme_stylebox_override("hover", hover)


## 층 탭: 외부 / 1층 / 2층 … (지하는 아래에서부터)
func _build_tabs() -> void:
	var b := sim.building
	var order := b.levels()
	order.sort_custom(func(a: int, c: int) -> bool: return b.floor_number(a) < b.floor_number(c))
	var specs: Array = [[-1, "외부"]]
	for lv in order:
		specs.append([lv, b.floor_name(lv)])
	for s: Array in specs:
		var btn := _marker_button(str(s[1]), true)
		btn.button_pressed = int(s[0]) == map.level
		var lv: int = s[0]
		btn.pressed.connect(func() -> void: show_level(lv))
		_tabs.add_child(btn)


func show_level(lv: int) -> void:
	map.level = lv
	for i in _tabs.get_child_count():
		var btn: Button = _tabs.get_child(i)
		btn.button_pressed = (i == 0 and lv < 0) or btn.text == (sim.building.floor_name(lv) if lv >= 0 else "외부")
	map.queue_redraw()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh = 0.0


func _process(delta: float) -> void:
	# 닫혀 있으면 갱신하지 않는다 (사무용 PC)
	if not visible or sim == null:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_S
	refresh_text()
	map.queue_redraw()


## 정보 칸 글을 다시 쓴다
func refresh_text() -> void:
	_style_team_cards()
	_entry.text = strategy_text()
	_receo.text = receo_bbcode()
	_span.text = span_text()
	_span.visible = _span.text != ""
	_status.text = status_bbcode()


func _hex(key: String) -> String:
	return style.color(key).to_html(false)


## 전략 한 줄 (지휘권을 선언하지 않았으면 그것도)
func strategy_text() -> String:
	var cmd := sim.command
	return "전략: %s%s" % [CommandSystem.STRATEGY_NAMES[cmd.strategy], "" if cmd.declared() else " (지휘권 미선언)"]


## 우선순위 칸에 쓸 줄을 고른다 (중요한 것만): 해당하는 우선순위 항목만 순서대로, 확인 필요는 정한 개수까지.
##   items = CommandUi.receo_items() [[해당하는가, 이름, 내용], …] · todo = 확인 필요 글
##   → {priority [["이름", "내용"], …] (첫 줄이 가장 급한 것), todo [글, …], more 남은 확인 필요 건수}
static func urgent_lines(items: Array, todo: Array, todo_max: int) -> Dictionary:
	var priority: Array = []
	for it: Array in items:
		if bool(it[0]):
			priority.append([str(it[1]), str(it[2])])
	var shown: Array = todo.slice(0, maxi(0, todo_max))
	return {"priority": priority, "todo": shown, "more": todo.size() - shown.size()}


## 우선순위 칸: 지금 가장 급한 항목은 빨간 마커 + ▶, 그 밖의 해당 항목은 검정, 확인 필요는 빨간 점. 해당 없는 항목은 쓰지 않는다
func receo_bbcode() -> String:
	var u := urgent_lines(_ui.receo_items(), _ui.todo_items(), style.todo_max)
	var lines: PackedStringArray = []
	var priority: Array = u.priority
	for i in priority.size():
		if i == 0:
			lines.append("[color=#%s][b]▶ %s: %s[/b][/color]" % [_hex("marker_red"), priority[i][0], priority[i][1]])
		else:
			lines.append("%s: %s" % [priority[i][0], priority[i][1]])
	if priority.is_empty():
		lines.append("[color=#%s]지금 급한 항목 없음[/color]" % _hex("ink_soft"))
	for t: String in u.todo:
		lines.append("[color=#%s]• %s[/color]" % [_hex("marker_red"), t])
	if int(u.more) > 0:
		lines.append("[color=#%s]… 확인 필요 %d건 더[/color]" % [_hex("ink_soft"), int(u.more)])
	return "\n".join(lines)


## 통솔범위: 넘었을 때와 실행 대기 명령이 있을 때만 쓴다 (평소에는 빈 글)
func span_text() -> String:
	var cmd := sim.command
	var parts: PackedStringArray = []
	var n := cmd.direct_count()
	if n > cmd.org.span_ideal:
		parts.append("직접 지휘 %d (적정 %d) — 명령 %.0f초 지연, 단위대를 지정하세요" % [n, cmd.org.span_ideal, cmd.span_delay_s()])
	if cmd.held_count() > 0:
		parts.append("실행 대기 명령 %d건" % cmd.held_count())
	return " · ".join(parts)


## 구조대상자 집계 + 물 현황 + 오는 중인 출동대 — 작은 제목은 파란 마커
func status_bbcode() -> String:
	var lines: PackedStringArray = ["[color=#%s][b]구조대상자[/b][/color]  %s" % [_hex("marker_blue"), victims_text()]]
	for group: Array in [["물", water_lines()], ["출동대", arrival_lines()]]:
		var rows: PackedStringArray = group[1]
		if rows.is_empty():
			continue
		# 작은 제목은 첫 줄 앞에 붙인다 (줄 수를 아낀다)
		lines.append("[color=#%s][b]%s[/b][/color]  %s" % [_hex("marker_blue"), group[0], rows[0]])
		lines.append_array(rows.slice(1))
	return "\n".join(lines)


## 물 현황: 펌프차마다 한 줄 — 물탱크 잔량·급수원·예상 고갈
func water_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for v in sim.units.vehicles:
		if not v.is_pump() or v.away:
			continue
		var use := 0.0
		for h in sim.water.hoses:
			if h.vehicle_id == v.id and h.flowing:
				use += sim.water.hose_lpm(h, v)
		var src := "소화전" if v.hydrant >= 0 else ("송수구" if sim.water.fdc_vehicle == v.id else "")
		for t in sim.units.vehicles:
			if t.supply_to == v.id:
				src = "물탱크차 급수"
		var left := "%d/%dL" % [roundi(v.tank_l), roundi(v.tank_capacity)]
		var eta := ""
		if src == "" and use > 0.0:
			eta = " · 약 %d분 뒤 고갈" % roundi(v.tank_l / use)
		lines.append("%s %s · %s%s" % [v.display_name(sim.units.squads[v.squad_id].name), left, src if src != "" else "급수원 없음", eta])
	return lines


## 아직 현장에 투입되지 않은 출동대: 접근 중 · 대기1단계 · 출동 중(도착 예정). 현장에서 활동 중인 조는 팀 카드에 있다
func arrival_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	var res := sim.command.resources
	for squad in sim.units.squads:
		if res.is_en_route(squad.id):
			lines.append("%s 현장 접근 중" % squad.name)
		elif res.is_staged(squad.id):
			lines.append("%s 대기1단계 (명령하면 투입)" % squad.name)
	for u in res.upcoming(sim.clock.tick):
		var eta := roundi(u.eta_s)
		@warning_ignore("integer_division")
		lines.append("%s %s" % [u.name, "약 %d분 %02d초 뒤 도착" % [eta / 60, eta % 60] if eta > 0 else "대기 장소 자리 기다림"])
	return lines


## 구조대상자 집계 (무전 보고 기준): 보고 · 구조 · 스스로 대피
func victims_text() -> String:
	var reported := 0
	var saved := 0
	for vid: int in sim.knowledge.victims:
		if sim.knowledge.victims[vid].state == "구조":
			saved += 1
		else:
			reported += 1
	var evac := sim.events.of_type("victim_self_evac").size()
	return "보고 %d · 구조 %d · 스스로 대피 %d" % [reported, saved, evac]
