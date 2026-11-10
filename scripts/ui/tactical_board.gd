class_name TacticalBoard
extends Control
## 전술상황판 (기획안 9-2-1, P10-1): 상황 배지 옆 버튼·Tab·M으로 여닫는 반투명 오버레이(화면의 약 80%). 게임은 계속 간다.
##   왼쪽 열(지휘): 전략·대응단계·출동대 진입 현황, 지휘 조직·통솔범위, 둘러보기, 진입대원 통제표(팀 카드)
##   가운데: 층 탭(외부 / 1층 / …) + 평면도 (BoardMap — 무전 보고만)
##   오른쪽 열(확인): 상황 요약(RECEO), 확인 필요, 물 현황, 요구조자 집계
## 열려 있을 때만 2Hz로 다시 그린다 (사무용 PC). 질문 카드는 이보다 위에 뜬다.

signal crew_dropped(crew_id: int, target: Vector3i, screen_pos: Vector2)

const REFRESH_S := 0.5
const MARGIN := 0.1
const COLUMN := 360.0

var sim: SimWorld
var map: BoardMap
var _tabs: HBoxContainer
var _water: Label
var _victims: Label
var _refresh := 0.0


## command_ui의 지휘 정보 위젯(전략·통솔범위·둘러보기·팀 카드·RECEO·확인 필요)을 이 판으로 옮겨 쓴다
func setup(p_sim: SimWorld, ui: CommandUi) -> void:
	sim = p_sim
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.anchor_left = MARGIN
	panel.anchor_top = MARGIN * 0.8
	panel.anchor_right = 1.0 - MARGIN
	panel.anchor_bottom = 1.0 - MARGIN * 1.2
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.09, 0.88)
	style.border_color = Color("fdba74")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var outer := VBoxContainer.new()
	panel.add_child(outer)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "전술상황판 — 무전으로 보고된 것만 (Tab·M 닫기, 게임은 계속 진행)"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("fdba74"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_tabs = HBoxContainer.new()
	head.add_child(_tabs)
	var close := Button.new()
	close.text = "닫기"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle)
	head.add_child(close)
	outer.add_child(head)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	outer.add_child(row)
	# 왼쪽 열 — 지휘
	var left := _column(row, "지휘 · 진입대원 통제표")
	for w in [ui._entry_label, ui._span_label, ui._survey_label]:
		_move(w, left)
	_move(ui._team_box, left)
	# 가운데 — 평면도
	map = BoardMap.new()
	map.setup(sim)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.crew_dropped.connect(func(id: int, t: Vector3i, p: Vector2) -> void: crew_dropped.emit(id, t, p))
	row.add_child(map)
	# 오른쪽 열 — 확인
	var right := _column(row, "확인")
	_move(ui._receo_label, right)
	_move(ui._todo_label, right)
	_water = _text(right)
	_victims = _text(right)
	_build_tabs()


func _column(row: HBoxContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLUMN, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size = Vector2(COLUMN - 14, 0)
	scroll.add_child(box)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color("fdba74"))
	box.add_child(l)
	row.add_child(scroll)
	return box


func _move(w: Control, to: Container) -> void:
	if w == null:
		return
	if w.get_parent():
		w.get_parent().remove_child(w)
	if w is Label:
		(w as Label).custom_minimum_size = Vector2(COLUMN - 20, 0)
	elif w is RichTextLabel:
		(w as RichTextLabel).custom_minimum_size = Vector2(COLUMN - 20, 0)
	to.add_child(w)


func _text(to: Container) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color("e2e8f0"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(COLUMN - 20, 0)
	to.add_child(l)
	return l


## 층 탭: 외부 / 1층 / 2층 … (지하는 아래에서부터)
func _build_tabs() -> void:
	var b := sim.building
	var order := b.levels()
	order.sort_custom(func(a: int, c: int) -> bool: return b.floor_number(a) < b.floor_number(c))
	var specs: Array = [[-1, "외부"]]
	for lv in order:
		specs.append([lv, b.floor_name(lv)])
	for s: Array in specs:
		var btn := Button.new()
		btn.text = str(s[1])
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
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
	_water.text = water_text()
	_victims.text = victims_text()
	map.queue_redraw()


## 물 현황: 펌프차 물탱크 잔량·급수원·예상 고갈
func water_text() -> String:
	var lines: PackedStringArray = ["물 현황"]
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
	return "\n".join(lines)


## 요구조자 집계 (무전 보고 기준): 보고 · 구조 · 대피 · 미확인
func victims_text() -> String:
	var reported := 0
	var saved := 0
	for vid: int in sim.knowledge.victims:
		if sim.knowledge.victims[vid].state == "구조":
			saved += 1
		else:
			reported += 1
	var evac := sim.events.of_type("victim_self_evac").size()
	return "요구조자 (보고 기준)\n보고 %d · 구조 %d · 스스로 대피 %d" % [reported, saved, evac]
