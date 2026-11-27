class_name RadioSubtitles
extends VBoxContainer
## 무전 자막 줄 (2026-11-27 사용자 결정 — 위쪽 알림 칩에서 무전을 빼고 무전은 여기 한 곳에):
##   화면 아래 왼쪽, 최근 무전 2~3줄 + 지금 송신 중인 무전. 줄마다 말한 쪽 배지(분대 색 원 + 짧은 이름)·이름·본문
##   (레인보우 식스 자막처럼 누가 말하는지 색으로). 대원 안전 무전은 빨간 테두리. 5초 뒤 사라진다 (실제 시간이 아니라 현장 시간)
## 말한 쪽이 대원이면 그 분대 머리 위에 짧은 말풍선(bark), 대원 안전 무전이면 위 가운데 긴급 띠(urgent) — HUD 가 받아 그린다

## 대원이 무전을 시작했다: 그 자리 머리 위 짧은 말풍선 (pos 칸 좌표, lv 층)
signal bark(pos: Vector2, lv: int, color: Color, text: String, seconds: float)
## 대원 안전 무전이 시작됐다: 위 가운데 긴급 띠
signal urgent(speaker: String, body: String, color: Color, label: String, pos: Vector2, lv: int)

const SHOW_S := 5.0
const MAX_LINES := 3
const FONT_PX := 17
const BADGE_PX := 26.0
const BARK_S := 3.0
const BARK_MAX := 24
const SAFETY_COLOR := Color("f87171")
const BARK_COLOR := Color("7dd3fc")

var sim: SimWorld
var _shown_key := ""
var _last_current := -1


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 5)


## 매 프레임: 보일 무전이 바뀌었으면 줄을 다시 만든다. 새로 송신을 시작한 무전이면 말풍선·긴급 띠
func refresh() -> void:
	var radio := sim.command.radio
	var now := sim.clock.tick
	var list: Array = []
	for i in range(radio.history.size() - 1, -1, -1):
		var m: Radio.Message = radio.history[i]
		if (now - m.end_tick) * SimClock.TICK_DT > SHOW_S or list.size() >= MAX_LINES:
			break
		list.push_front([m, false])
	if radio.current:
		list.append([radio.current, true])
		if radio.current.seq != _last_current:
			_last_current = radio.current.seq
			_on_start(radio.current)
	var key := ""
	for it: Array in list:
		key += "%d%s," % [(it[0] as Radio.Message).seq, "*" if it[1] else ""]
	if key == _shown_key:
		return
	_shown_key = key
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for it: Array in list:
		add_child(_row(it[0], it[1]))
	visible = not list.is_empty()


## 떠 있는 자막 글 (화면 점검용)
func lines_text() -> String:
	var out: PackedStringArray = []
	for row in get_children():
		var parts: PackedStringArray = []
		for l in row.find_children("*", "Label", true, false):
			parts.append((l as Label).text)
		out.append(" ".join(parts))
	return "\n".join(out)


## 말한 쪽 {color, label(배지 글), name, crew(없으면 null)}
func speaker_of(sender: String) -> Dictionary:
	for c in sim.units.crews:
		if sim.units.crew_name(c) == sender or (sim.units.whole_squad(c) and sim.units.squads[c.squad_id].name == sender):
			return {"color": sim.units.squads[c.squad_id].color, "label": TeamStrip.short_label(sim, c), "name": sender, "crew": c}
	# 출동대 이름 또는 "진압1 펌프차"처럼 출동대 이름으로 시작하는 쪽 (차량 운전원)
	for s in sim.units.squads:
		if s.name == sender or sender.begins_with(s.name + " "):
			return {"color": s.color, "label": s.name, "name": sender, "crew": null}
	if sender == CommandSystem.COMMANDER:
		return {"color": SpriteArt.helmet_color("지휘"), "label": "지휘", "name": sender, "crew": null}
	return {"color": Color("64748b"), "label": sender.substr(0, 2), "name": sender, "crew": null}


func _on_start(m: Radio.Message) -> void:
	var sp := speaker_of(m.sender)
	var crew: Crew = sp.crew
	var pos := Vector2(-1, -1)
	var lv := 0
	if crew != null and not crew.leader.aboard:
		pos = crew.leader.pos
		lv = crew.leader.level
		var t := m.body if m.body.length() <= BARK_MAX else m.body.substr(0, BARK_MAX - 1) + "…"
		bark.emit(pos, lv, SAFETY_COLOR if m.priority == Radio.Priority.SAFETY else BARK_COLOR, t, BARK_S)
	if m.priority == Radio.Priority.SAFETY:
		urgent.emit(str(sp.name), m.body, sp.color, str(sp.label), pos, lv)


func _row(m: Radio.Message, live: bool) -> Control:
	var safety := m.priority == Radio.Priority.SAFETY
	var sp := speaker_of(m.sender)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.05, 0.08, 0.8)
	st.set_corner_radius_all(6)
	st.content_margin_left = 6
	st.content_margin_right = 12
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	if safety:
		st.set_border_width_all(2)
		st.border_color = SAFETY_COLOR
	panel.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(BADGE_PX, BADGE_PX)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: Color = sp.color
	var lab := str(sp.label)
	badge.draw.connect(func() -> void: draw_badge(badge, badge.size * 0.5, BADGE_PX * 0.5, col, lab))
	row.add_child(badge)
	var who := str(sp.name)
	if m.receiver != CommandSystem.COMMANDER:
		who += " → " + m.receiver
	row.add_child(_label(("▶ " if live else "") + who, col.lightened(0.45) if col.v < 0.85 else col, true))
	var body := _label(m.body, Color("fecaca") if safety else Color("f1f5f9"), false)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var w := get_theme_default_font().get_string_size(m.body, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x
	body.custom_minimum_size = Vector2(minf(w + 4.0, 620.0), 0)
	row.add_child(body)
	return panel


func _label(text: String, color: Color, strong: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", FONT_PX - (1 if strong else 0))
	l.add_theme_color_override("font_color", color)
	if strong:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("outline_size", 2)
	return l


## 말한 쪽 배지: 어두운 테두리 + 분대 색 원 + 짧은 이름 (아래 팀 초상과 같은 모양)
static func draw_badge(ci: CanvasItem, at: Vector2, r: float, color: Color, label: String) -> void:
	ci.draw_circle(at, r, Color(0.06, 0.09, 0.14, 0.95))
	ci.draw_circle(at, r - 2.5, color.darkened(0.15))
	var font := ThemeDB.fallback_font
	var fs := 9 if label.length() > 3 else 10
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, at + Vector2(-w * 0.5, fs * 0.38), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
