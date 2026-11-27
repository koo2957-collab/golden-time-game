class_name NoticeFeed
extends VBoxContainer
## 위쪽 알림 칩 (2026-11-27 사용자 결정 — 예전: 노란 글자만 위 가운데에 4초, 무엇인지·어디서인지 몰랐다).
## CoH·프로스트펑크의 아이콘 알림처럼 종류마다 아이콘·색 띠(위험 빨강·구조대상자 주황·차량 파랑·관계인 초록·단서 노랑·현장 회색).
## 그 자리를 알 수 있는 알림은 칩을 누르면 화면이 그 자리로 가고(jump), 뜰 때 지도의 그 자리에도 표시한다(placed — 관계인 진술은 말풍선).
## 종류·색·시간은 data/ui/notices.json. 칩은 마우스를 막지 않는 빈 자리에서만 클릭을 받는다

## 칩을 누름: 그 자리로 화면 이동 (World)
signal jump(pos: Vector2, lv: int)
## 자리를 아는 알림이 떴다: 지도에 표시 (World → SelectionController.notice_ping)
signal placed(pos: Vector2, lv: int, color: Color, text: String, seconds: float)

const PATH := "res://data/ui/notices.json"
const ICON_PX := 24.0
const FONT_PX := 17
const TIME_PX := 13
const TEXT_MAX_W := 700.0
## 지도 표시 글자 최대 길이 (넘으면 …)
const PING_TEXT_MAX := 26

var sim: SimWorld
var seconds := 8.0
var fade_s := 1.0
var max_n := 4
var bubble_s := 6.0
var ping_s := 2.4
var _cats: Dictionary = {}  # 종류 -> {label, color, icon, types, radio}
var _order: Array[String] = []
## 떠 있는 알림 {text, cat, where, left, chip}
var _items: Array[Dictionary] = []


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 5)
	_load()


func _load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	seconds = float(_value(data, "seconds", seconds))
	fade_s = float(_value(data, "fade_s", fade_s))
	max_n = int(_value(data, "max", max_n))
	bubble_s = float(_value(data, "statement_bubble_s", bubble_s))
	ping_s = float(_value(data, "map_ping_s", ping_s))
	var cats: Dictionary = data.get("categories", {})
	for k: String in cats:
		if k.begins_with("_"):
			continue
		var c: Dictionary = cats[k]
		_cats[k] = {"label": str(c.get("label", k)), "color": Color(str(c.get("color", "#94a3b8"))), "icon": str(c.get("icon", "info")),
			"types": c.get("types", []), "radio": c.get("radio", [])}
		_order.append(k)


static func _value(data: Dictionary, key: String, fallback: Variant) -> Variant:
	var entry: Variant = data.get(key)
	if entry is Dictionary and (entry as Dictionary).has("value"):
		return entry["value"]
	return fallback


## 사건 종류 → 알림 종류 (무전은 우선순위로)
func category_of(type: String, priority := "") -> String:
	for k in _order:
		var c: Dictionary = _cats[k]
		if type == "radio":
			if priority in c.radio:
				return k
		elif type in c.types:
			return k
	return "info"


func color_of(cat: String) -> Color:
	return (_cats.get(cat, {}) as Dictionary).get("color", Color("94a3b8"))


## 사건 하나를 알림으로
func push_event(e: Dictionary) -> void:
	var type := str(e.get("type", ""))
	var cat := category_of(type, str(e.get("priority", "")))
	var where := where_of(e)
	var text := SimEventLog.describe_text(e)
	var t := int(e.get("time_s", 0))
	var ping_text := _short(text)
	var ping_secs := ping_s
	if type == "statement":
		# 관계인 머리 위 말풍선에 답을 짧게
		ping_text = "“%s”" % _short(str(e.get("text", "")))
		ping_secs = bubble_s
	push(text, cat, where, "%02d:%02d" % [floori(t / 60.0), t % 60], ping_text, ping_secs)


## 알림을 하나 더한다. where = {pos, lv} (모르면 {}): 누르면 그 자리로, 지도에도 표시
func push(text: String, cat := "info", where := {}, time_text := "", ping_text := "", ping_secs := -1.0) -> void:
	if not _cats.has(cat):
		cat = "info" if _cats.has("info") else cat
	var chip := _chip(text, cat, where, time_text)
	add_child(chip)
	_items.append({"text": text, "cat": cat, "where": where, "left": seconds, "chip": chip})
	while _items.size() > max_n:
		var old: Dictionary = _items.pop_front()
		(old.chip as Control).queue_free()
	if not where.is_empty():
		placed.emit(where.pos, int(where.lv), color_of(cat), ping_text if ping_text != "" else _short(text), ping_secs if ping_secs > 0.0 else ping_s)


## 시간이 지나면 옅어지다 사라진다 (실제 시간)
func step(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for it in _items:
		it.left = float(it.left) - delta
		var chip: Control = it.chip
		if float(it.left) <= 0.0:
			chip.queue_free()
			continue
		chip.modulate.a = clampf(float(it.left) / fade_s, 0.0, 1.0)
		keep.append(it)
	_items = keep
	visible = not _items.is_empty()


## 떠 있는 알림 글 (화면 점검용)
func feed_text() -> String:
	var lines: PackedStringArray = []
	for it in _items:
		lines.append(str(it.text))
	return "\n".join(lines)


## 떠 있는 알림 [{text, cat, where}] (화면 점검용)
func items() -> Array[Dictionary]:
	return _items


## 알림 칩을 누른다 (화면 점검용)
func press(i: int) -> void:
	if i >= 0 and i < _items.size() and not (_items[i].where as Dictionary).is_empty():
		jump.emit(_items[i].where.pos, int(_items[i].where.lv))


## 사건이 일어난 자리 {pos(칸), lv} — 칸·관계인·차량·조·방·출동대 순으로 찾는다. 모르면 {}
func where_of(e: Dictionary) -> Dictionary:
	if sim == null:
		return {}
	var ground := sim.building.levels()[0]
	var cell: Variant = e.get("cell")
	if cell is Array and (cell as Array).size() >= 3:
		return {"pos": Vector2(float(cell[0]) + 0.5, float(cell[1]) + 0.5), "lv": int(cell[2])}
	if e.has("witness"):
		for w in sim.command.survey.witnesses:
			if w.label() == str(e.witness):
				return {"pos": w.pos, "lv": ground}
	if e.has("vehicle"):
		for v in sim.units.vehicles:
			if v.display_name(sim.units.squads[v.squad_id].name) == str(e.vehicle):
				return {"pos": v.pos, "lv": ground}
	# 조: crew(번호·이름), 무전이면 보낸 쪽(from)
	var who: Variant = e.get("crew", e.get("from") if str(e.get("type", "")) == "radio" else null)
	if who != null:
		var crew: Crew = null
		if who is int:
			crew = sim.units.get_crew(int(who))
		else:
			for c in sim.units.crews:
				if sim.units.crew_name(c) == str(who) or (sim.units.whole_squad(c) and sim.units.squads[c.squad_id].name == str(who)):
					crew = c
					break
		if crew != null and not crew.leader.aboard:
			return {"pos": crew.leader.pos, "lv": crew.leader.level}
	if e.has("room"):
		for comp in sim.fire.comps:
			if comp.display_name() == str(e.room):
				return {"pos": Vector2(comp.rect.get_center()), "lv": comp.level}
	if e.has("squad"):
		for s in sim.units.squads:
			if s.name == str(e.squad):
				for c in sim.units.crews:
					if c.squad_id == s.id and not c.leader.aboard:
						return {"pos": c.leader.pos, "lv": c.leader.level}
				for v in sim.units.vehicles_of_squad(s.id):
					return {"pos": v.pos, "lv": ground}
	return {}


static func _short(text: String) -> String:
	return text if text.length() <= PING_TEXT_MAX else text.substr(0, PING_TEXT_MAX - 1) + "…"


func _chip(text: String, cat: String, where: Dictionary, time_text: String) -> Control:
	var c: Dictionary = _cats.get(cat, {"color": Color("94a3b8"), "icon": "info", "label": ""})
	var col: Color = c.color
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(SidePanelStyle.BG, 0.9)
	st.border_color = Color(col, 0.55)
	st.set_border_width_all(1)
	st.border_width_left = 5
	st.border_color = col
	st.set_corner_radius_all(6)
	st.content_margin_left = 10
	st.content_margin_right = 14
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", st)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kind := str(c.icon)
	icon.draw.connect(func() -> void: draw_icon(icon, kind, icon.size * 0.5, ICON_PX * 0.5, col))
	row.add_child(icon)
	if time_text != "":
		var tl := _label(time_text, TIME_PX, SidePanelStyle.DIM)
		row.add_child(tl)
	var l := _label(text, FONT_PX, SidePanelStyle.TEXT)
	var w := get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).x
	if w > TEXT_MAX_W:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size = Vector2(TEXT_MAX_W, 0)
		l.tooltip_text = text
	row.add_child(l)
	if where.is_empty():
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		# 그 자리를 아는 알림: 누르면 화면 이동 (오른쪽 끝 작은 ◎)
		row.add_child(_label("◎", 14, Color(col, 0.9)))
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.tooltip_text = "누르면 그 자리로"
		var at: Vector2 = where.pos
		var lv := int(where.lv)
		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				jump.emit(at, lv)
				panel.accept_event())
	return panel


func _label(text: String, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	return l


## 종류 아이콘: 색 원 + 어두운 그림 (truck 차량 · speech 말풍선 · eye 눈 · danger 느낌표 세모 · person 사람 · info i)
static func draw_icon(ci: CanvasItem, kind: String, at: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(at, r, col)
	var ink := Color(0.05, 0.07, 0.1)
	var s := r * 0.55
	match kind:
		"truck":
			ci.draw_rect(Rect2(at + Vector2(-s, -s * 0.55), Vector2(s * 1.25, s * 0.95)), ink)
			ci.draw_rect(Rect2(at + Vector2(s * 0.3, -s * 0.2), Vector2(s * 0.7, s * 0.6)), ink)
			ci.draw_circle(at + Vector2(-s * 0.55, s * 0.55), s * 0.26, ink)
			ci.draw_circle(at + Vector2(s * 0.6, s * 0.55), s * 0.26, ink)
		"speech":
			ci.draw_rect(Rect2(at + Vector2(-s, -s * 0.75), Vector2(s * 2.0, s * 1.2)), ink)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.5, s * 0.4), at + Vector2(0, s * 0.4), at + Vector2(-s * 0.7, s * 0.95)]), ink)
		"eye":
			var pts := PackedVector2Array()
			for k in 17:
				var a := TAU * k / 16.0
				pts.append(at + Vector2(cos(a) * s * 1.05, sin(a) * s * 0.6))
			ci.draw_polyline(pts, ink, maxf(1.5, s * 0.22), true)
			ci.draw_circle(at, s * 0.36, ink)
		"danger":
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s * 1.05), at + Vector2(s * 1.05, s * 0.8), at + Vector2(-s * 1.05, s * 0.8)]), ink)
			ci.draw_line(at + Vector2(0, -s * 0.45), at + Vector2(0, s * 0.2), col, maxf(1.5, s * 0.25))
			ci.draw_circle(at + Vector2(0, s * 0.5), s * 0.14, col)
		"person":
			ci.draw_circle(at + Vector2(0, -s * 0.5), s * 0.38, ink)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.7, s * 0.9), at + Vector2(-s * 0.5, 0.0), at + Vector2(s * 0.5, 0.0), at + Vector2(s * 0.7, s * 0.9)]), ink)
		_:
			ci.draw_circle(at + Vector2(0, -s * 0.55), s * 0.17, ink)
			ci.draw_line(at + Vector2(0, -s * 0.15), at + Vector2(0, s * 0.75), ink, maxf(1.5, s * 0.3))
