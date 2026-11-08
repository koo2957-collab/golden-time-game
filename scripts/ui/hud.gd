class_name Hud
extends Control
## 화면 정보: 게임 시계·배속·모드, 층 탭, 선택 정보, 명령 패널, 조작 안내,
## 열화상 범례, 개발용 화재 정보 패널. 지휘 화면(무전·상황보고·전략)은 command_ui.gd, 디브리핑은 debrief_ui.gd.

## 명령 패널 버튼을 눌렀을 때 (id: "entry" / "search" / "door" / "hose" / "straight" / "fog" / "stop")
signal command_pressed(id: String)

const DEBUG_REFRESH_S := 0.25
const COMMAND_CARDS_PATH := "res://data/units/command_cards.json"
const SELECTION_REFRESH_S := 0.25
## 화면 위쪽에 알림으로 띄우는 사건. 대원이 무전으로 보고하는 사건(CommandSystem.REPORT_PRIORITY)은
## 무전 송신이 끝났을 때 무전 기록에 나오고, 대원 안전·구조대상자 무전은 알림으로도 띄운다.
const NOTICE_TYPES: Array[String] = [
	"hydrant_connected", "hydrant_disconnected", "supply_connected", "hose_laid", "hose_too_short",
	"hose_limit", "tank_empty", "vehicle_locked", "vehicle_blocked", "spray_unreachable",
	"door_opened", "door_closed", "door_forced", "door_cannot_close", "door_unreachable",
	"heat_blocked", "heat_retreat", "air_alarm", "scba_swapped",
	"victim_found", "victim_state", "victim_rescued", "victim_recovered", "ff_rescued", "rescue_pickup",
	"rescue_hose_crew", "exit_blocked", "search_done", "rollover_sign", "backdraft_sign", "backdraft",
	"fgi_warning", "window_vented", "entry_wait", "entry_rejected", "withdraw", "auto_slow",
	"squad_dispatched", "staging_full", "order_en_route", "span_warning", "division_set", "division_cleared",
	"face_seen", "site_info_found", "clue_found", "witness_arrived", "statement", "ask_too_far", "ask_cancelled",
	"command_post", "report_updated", "overhaul_start", "rekindle",
	"emergency_cleared", "evacuation_ordered", "par_done", "role_assigned", "role_reserved", "rit_deployed",
	"entry_factors", "order_unseen", "plan_acquired", "panel_fire_floor", "plan_diff_found",
]
## 알림으로도 띄우는 무전 우선순위
const NOTICE_RADIO_PRIORITIES: Array[String] = ["대원 안전", "구조대상자"]
const NOTICE_SECONDS := 4.0
const NOTICE_MAX := 3
const DEBUG_EVENT_LINES := 8
const DEBUG_COLUMNS: Array[String] = ["구획", "단계", "상부℃", "하부℃", "연기층m", "O2%", "가스%", "열방출kW", "시야m", "FO℃"]

@onready var clock_label: Label = $ClockPanel/ClockLabel
@onready var floor_tabs: VBoxContainer = $FloorTabs
@onready var selection_label: Label = $SelectionPanel/SelectionLabel

var sim: SimWorld
var mode_text := ""
var _floor_buttons: Dictionary = {}  # level -> Button
var _legend: Control
var _victim_panel: PanelContainer
var _debug_panel: PanelContainer
var _debug_cells: Array[Label] = []
var _debug_events: Label
var _debug_timer := 0.0
var _crew_ids: Array[int] = []
var _vehicle_ids: Array[int] = []
var _selection_timer := 0.0
var _victim_label: Label
var _command_panel: VBoxContainer
var _command_buttons: Dictionary = {}  # id -> Button
## 분대 명령칸 (위 줄): 출동대 종류별 고수준 명령 (data/units/command_cards.json)
var _card_row: HBoxContainer
var _card_type := ""
var _cards: Dictionary = {}
var _notice_label: Label
var _notices: Array[Array] = []  # [문장, 남은 시간(실제 초)]
var _events_seen := 0
var _commander_selected := false
var command_ui: CommandUi
var debrief: DebriefUi
var hint_ui: HintUi
## 화면 위 활동 단계 표시줄 (①~⑧, 지금 단계 강조)
var phase_bar: RichTextLabel
## 튜토리얼 시나리오에서만 만든다
var tutorial_ui: TutorialUi
## 질문 카드 (화면 위쪽 가운데)
var card_ui: CardUi


func setup(p_sim: SimWorld, on_floor_selected: Callable) -> void:
	sim = p_sim
	# 다시 하기로 중간부터 시작하면 그 전 사건은 알림으로 띄우지 않는다
	_events_seen = sim.events.entries.size()
	phase_bar = RichTextLabel.new()
	phase_bar.bbcode_enabled = true
	phase_bar.fit_content = true
	phase_bar.scroll_active = false
	phase_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_bar.custom_minimum_size = Vector2(900, 0)
	phase_bar.add_theme_font_size_override("normal_font_size", 15)
	phase_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	phase_bar.position = Vector2(-450, 6)
	add_child(phase_bar)
	var group := ButtonGroup.new()
	var levels := sim.building.levels()
	levels.reverse()
	for level in levels:
		var button := Button.new()
		button.text = sim.building.floor_name(level)
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(160, 34)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = "이 층 보기 (PgUp·PgDn)"
		button.add_theme_color_override("font_pressed_color", PlanStyle.SELECTION)
		button.add_theme_color_override("font_hover_pressed_color", PlanStyle.SELECTION)
		button.pressed.connect(on_floor_selected.bind(level))
		floor_tabs.add_child(button)
		_floor_buttons[level] = button
	$ClockPanel.gui_input.connect(_on_badge_input)
	$ClockPanel.tooltip_text = "클릭: 전략 변경 (지휘 C)"
	_build_subtitles()
	_build_emergency()
	_build_legend()
	_build_debug_panel()
	_build_command_panel()
	_build_notice_label()
	_build_victim_panel()
	command_ui = CommandUi.new()
	add_child(command_ui)
	command_ui.setup(sim)
	_build_console()
	hint_ui = HintUi.new()
	add_child(hint_ui)
	debrief = DebriefUi.new()
	debrief.visible = false
	add_child(debrief)
	EventBus.selection_changed.connect(_on_selection_changed)
	EventBus.commander_selection_changed.connect(_on_commander_selection_changed)
	EventBus.vehicle_selection_changed.connect(_on_vehicle_selection_changed)
	EventBus.view_floor_changed.connect(_on_view_floor_changed)
	_on_selection_changed([])


func set_thermal_visible(on: bool) -> void:
	_legend.visible = on


func is_debug_visible() -> bool:
	return _debug_panel.visible


func set_debug_visible(on: bool) -> void:
	_debug_panel.visible = on
	command_ui.set_radio_visible(not on)
	_debug_timer = 0.0


func _process(delta: float) -> void:
	if sim == null:
		return
	var t := int(sim.clock.elapsed_seconds())
	var text := "경과 %02d:%02d" % [floori(t / 60.0), t % 60]
	if sim.time_limit_tick > 0:
		var left := maxi(0, int((sim.time_limit_tick - sim.clock.tick) * SimClock.TICK_DT))
		text += " / 남은 %02d:%02d" % [floori(left / 60.0), left % 60]
	text += "   ×%d" % int(sim.clock.speed)
	if sim.realism != "":
		text += "   %s%s" % [sim.realism, " · 1배속 고정" if sim.realism != "훈련" else ""]
	if sim.clock.paused:
		text += "   일시정지"
	if mode_text != "":
		text += "   [%s]" % mode_text
	clock_label.text = text + "\n" + _badge_line()
	_refresh_phase_bar()
	if _notice_label:
		# 알림은 오른쪽 상황판이 가리지 않는 지도 영역 가운데에
		var cx := command_ui.map_center_x()
		_notice_label.offset_left = cx - size.x * 0.5 - 400.0
		_notice_label.offset_right = cx - size.x * 0.5 + 400.0
	_refresh_floor_bar(delta)
	_layout_console()
	_refresh_subtitles()
	_refresh_emergency()
	_update_notices(delta)
	_selection_timer -= delta
	if _selection_timer <= 0.0:
		_selection_timer = SELECTION_REFRESH_S
		_refresh_selection()
		_refresh_victims()
	if _debug_panel.visible:
		_debug_timer -= delta
		if _debug_timer <= 0.0:
			_debug_timer = DEBUG_REFRESH_S
			_refresh_debug()


func _on_view_floor_changed(level: int) -> void:
	# set_pressed_no_signal은 버튼 그룹의 단일 선택을 처리하지 않으므로 전부 직접 맞춘다
	for lv: int in _floor_buttons:
		_floor_buttons[lv].set_pressed_no_signal(lv == level)


func _on_selection_changed(crew_ids: Array[int]) -> void:
	_crew_ids = crew_ids
	_refresh_selection()


func _on_commander_selection_changed(selected: bool) -> void:
	_commander_selected = selected
	_refresh_selection()


func _on_vehicle_selection_changed(vehicle_ids: Array[int]) -> void:
	_vehicle_ids = vehicle_ids
	_refresh_selection()


func _refresh_victims() -> void:
	var lines: PackedStringArray = []
	for v in sim.rescue.victims:
		if not v.discovered:
			continue
		var room := sim.fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
		var where := room.display_name() if room else ("바깥" if v.carried_by < 0 else "이송 중")
		if v.carried_by >= 0:
			where = "이송 중"
		var t := int(v.discovered_tick * SimClock.TICK_DT)
		lines.append("%s · %s · %s · 발견 %02d:%02d" % [v.label(), where, v.state_name(), floori(t / 60.0), t % 60])
	_victim_label.text = "요구조자 현황
" + "
".join(lines) if not lines.is_empty() else ""
	_victim_label.get_parent().visible = not lines.is_empty()


func _build_victim_panel() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -436
	panel.offset_right = -16
	panel.offset_top = 150
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_victim_panel = panel
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_victim_label = Label.new()
	_victim_label.add_theme_font_size_override("font_size", 16)
	_victim_label.add_theme_color_override("font_color", Color("ffe082"))
	panel.add_child(_victim_label)
	add_child(panel)
	panel.visible = false


func _refresh_selection() -> void:
	var lines: PackedStringArray = []
	var any_flowing := false
	for crew_id in _crew_ids:
		var crew := sim.units.get_crew(crew_id)
		var squad := sim.units.squads[crew.squad_id]
		var names: PackedStringArray = []
		for ff in crew.members():
			names.append("%s %s" % [ff.name, ff.rank])
		var line := "[%s] %d조 — %s (%s)" % [squad.name, crew.number, " · ".join(names), sim.building.floor_name(crew.leader.level)]
		line += _squad_state(squad.id)
		var role := sim.command.safety.role_of(crew_id)
		if role != SafetySystem.Role.NONE:
			line += "  · %s%s" % [SafetySystem.ROLE_NAMES[role], " (투입)" if sim.command.safety.deployed.has(crew_id) else " — 다른 임무 불가, 밖에서 대기"]
		line += _crew_status(crew)
		var hose := sim.water.hose_of_crew(crew_id)
		if hose:
			line += "  · 수관 %.0f/%.0fm" % [hose.length_cells() * sim.building.cell_size_m, hose.max_cells * sim.building.cell_size_m]
			if hose.flowing:
				any_flowing = true
				line += " · 방수 중(%s)" % hose.pattern_name()
				if hose.flow_fraction < 0.99:
					line += " 수압 부족"
				if hose.blocked:
					line += " 막힘"
			if hose.at_limit:
				line += " · 수관 길이 한계"
		lines.append(line)
	for vid in _vehicle_ids:
		lines.append(_vehicle_line(sim.units.get_vehicle(vid)))
	if _commander_selected:
		var cmd := sim.command
		var ask := cmd.survey.asking()
		lines.append("현장지휘관 %s %s (%s) — 지휘 위치: %s%s
    우클릭: 이동 (건물 안으로는 혼자 들어가지 않음) · C: 지휘권 선언·전략 · 관계인 클릭: 질문" % [
			cmd.commander.name, cmd.commander.rank, cmd.commander_title, cmd.commander_position_text(),
			" · 관계인에게 질문 중 (%d개 남음)" % ask.questions.size() if not ask.is_empty() else ""])
	selection_label.text = "\n".join(lines) if not lines.is_empty() else _squad_summary()
	_command_panel.visible = not _crew_ids.is_empty()
	# 아무 조도 고르지 않았으면 지휘관 명령 (기획안 9-2: 선택 대상에 따라 바뀌는 명령 버튼)
	_commander_box.visible = _crew_ids.is_empty()
	if not _crew_ids.is_empty():
		var squad := sim.units.squad_of_crew(_crew_ids[0])
		var card := "%s %s" % [squad.arrival, squad.type]
		_build_card_row(card if _cards.has(card) else squad.type)
	_command_buttons["stop"].disabled = not any_flowing
	var entry := _command_buttons["entry"] as Button
	var need := false
	var pending := false
	for crew_id in _crew_ids:
		var squad_id := sim.units.get_crew(crew_id).squad_id
		if not sim.command.can_enter(squad_id):
			need = true
			pending = pending or sim.command.entry_pending(squad_id)
	entry.disabled = not need or pending
	entry.text = "진입 명령 송신 중" if pending else ("진입 명령 (R)" if need else "진입 허가됨")


## 분대 명령칸: 첫 번째로 선택한 조의 출동대 종류에 맞춰 다시 만든다
func _build_card_row(type: String) -> void:
	if type == _card_type:
		return
	_card_type = type
	for c in _card_row.get_children():
		c.queue_free()
		_card_row.remove_child(c)
	var title := Label.new()
	title.text = "%s 명령칸" % type
	title.add_theme_color_override("font_color", Color("fde68a"))
	_card_row.add_child(title)
	for spec: Dictionary in _cards.get(type, _cards.get("진압대", [])):
		var b := Button.new()
		b.text = "%s (%s)" % [spec.label, spec.key] if str(spec.get("key", "")) != "" else str(spec.label)
		b.tooltip_text = str(spec.get("hint", ""))
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(170, 44)
		b.add_theme_color_override("font_color", Color("fde68a"))
		var id := str(spec.id)
		b.pressed.connect(func() -> void: command_pressed.emit(id))
		_card_row.add_child(b)


## 조 상태 요약: 공기 잔량(낮은 쪽), 복사열, 열 스트레스, 자세, 행동 불능, 열화상카메라, 문 작업
func _crew_status(crew: Crew) -> String:
	var air := 1.0
	var stress := 0.0
	var flux := 0.0
	var down := 0
	for ff in crew.members():
		air = minf(air, ff.air_ratio())
		stress = maxf(stress, ff.heat_stress)
		flux = maxf(flux, ff.heat_flux)
		if ff.incapacitated:
			down += 1
	var parts: PackedStringArray = ["공기 %d%%" % roundi(air * 100.0)]
	var traits: PackedStringArray = []
	for ff in crew.members():
		for t in ff.traits:
			traits.append("%s %s" % [ff.name, t])
	if not traits.is_empty():
		parts.append("개성: " + ", ".join(traits))
	if flux >= 0.5:
		parts.append("복사열 %.1fkW/㎡" % flux)
	if stress >= 0.05:
		parts.append("열 스트레스 %d%%" % roundi(stress * 100.0))
	if crew.leader.crouched:
		parts.append("낮은 자세")
	if crew.thermal_camera:
		parts.append("열화상")
	if down > 0:
		parts.append("행동 불능 %d명" % down)
	var oh := sim.rekindle.task_of_crew(crew.id)
	if oh:
		parts.append("잔불정리 %d/%d초" % [int(sim.rekindle.overhaul_seconds() - oh.remain), int(sim.rekindle.overhaul_seconds())])
	var task := sim.doors.task_of_crew(crew.id)
	if task:
		var what := "문 파괴" if task.opening.locked else ("문 개방" if task.open else "문 폐쇄")
		parts.append("%s %d/%d초%s" % [what, int(task.progress), int(task.required), " (인원 부족)" if task.waiting_people else ""])
	return "\n    " + " · ".join(parts)


## 출동대 상태: 접근 중 / 대기1단계 / 단위대 소속
func _squad_state(squad_id: int) -> String:
	var cmd := sim.command
	var parts: PackedStringArray = []
	if cmd.resources.is_en_route(squad_id):
		parts.append("현장 접근 중")
	elif cmd.resources.is_staged(squad_id):
		parts.append("투입 무전 송신 중" if cmd.commit_pending(squad_id) else "대기1단계 — 명령하면 투입 무전 후 실행")
	var d := cmd.org.division_of(squad_id)
	if d:
		parts.append("%s 단위대%s" % [d.name, " 지휘" if d.supervisor == squad_id else ""])
	return "  · " + " · ".join(parts) if not parts.is_empty() else ""


func _vehicle_line(v: Vehicle) -> String:
	var squad := sim.units.squads[v.squad_id]
	var water := " — 물 %s / %sL" % [_thousands(v.tank_l), _thousands(v.tank_capacity)] if v.tank_capacity > 0.0 else ""
	var line := "[%s] %s (운전원 %s)%s%s" % [squad.name, v.type, v.driver_label(), water, _squad_state(v.squad_id)]
	if v.away:
		line += " · 환자 이송 중 (현장 없음)"
	if v.hydrant >= 0:
		line += " · 소화전 연결"
	if v.supply_to >= 0:
		line += " · 급수 중"
	if v.is_pump():
		line += " · 수관 %d" % sim.water.hoses_of_vehicle(v.id).size()
		if sim.water.fdc_vehicle == v.id:
			line += " · 송수구 연결"
		line += "\n    소화전 우클릭: 점령%s" % (" · 송수구 우클릭: 연결송수관 가압" if sim.building.has_standpipe() else "")
	elif v.transfer_lpm > 0.0:
		var sh: Dictionary = sim.shuttle.tankers.get(v.id, {})
		if not sh.is_empty():
			line += " · 순환보수 %d회" % int(sh.trips)
		line += "\n    펌프차 우클릭: 급수 · 소화전 우클릭: 점령%s" % ("" if not sim.shuttle.available() else (" · B: 순환보수 해제" if not sh.is_empty() else " · B: 순환보수 지정"))
	return line


static func _thousands(value: float) -> String:
	var s := str(int(value))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


## 알림 한 줄을 띄운다 (사건이 아닌 안내)
func show_notice(text: String) -> void:
	_notices.append([text, NOTICE_SECONDS * 2.0])


func _update_notices(delta: float) -> void:
	var entries := sim.events.entries
	while _events_seen < entries.size():
		var e := entries[_events_seen]
		_events_seen += 1
		if e.type in NOTICE_TYPES and not CommandSystem.REPORT_PRIORITY.has(e.type):
			_notices.append([SimEventLog.describe(e), NOTICE_SECONDS])
		elif e.type == "radio" and e.priority in NOTICE_RADIO_PRIORITIES:
			_notices.append([SimEventLog.describe(e), NOTICE_SECONDS])
	for n in _notices:
		n[1] -= delta
	_notices = _notices.filter(func(n: Array) -> bool: return n[1] > 0.0)
	while _notices.size() > NOTICE_MAX:
		_notices.pop_front()
	var lines: PackedStringArray = []
	for n in _notices:
		lines.append(n[0])
	_notice_label.text = "\n".join(lines)
	_notice_label.visible = not lines.is_empty()


func _build_notice_label() -> void:
	_notice_label = Label.new()
	_notice_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice_label.offset_left = -400
	_notice_label.offset_right = 400
	_notice_label.offset_top = 70
	_notice_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_label.add_theme_font_size_override("font_size", 20)
	_notice_label.add_theme_color_override("font_color", Color("fde68a"))
	_notice_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_notice_label.add_theme_constant_override("outline_size", 6)
	add_child(_notice_label)
	_notice_label.visible = false


func _build_command_panel() -> void:
	var cards: Variant = JsonData.load_file(COMMAND_CARDS_PATH)
	_cards = cards if cards is Dictionary else {}
	_command_panel = VBoxContainer.new()
	_command_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_command_panel.offset_left = -1200
	_command_panel.offset_right = -16
	_command_panel.offset_top = -240
	_command_panel.offset_bottom = -130
	_command_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_command_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_command_panel.alignment = BoxContainer.ALIGNMENT_END
	_card_row = HBoxContainer.new()
	_card_row.alignment = BoxContainer.ALIGNMENT_END
	_command_panel.add_child(_card_row)
	var detail := HBoxContainer.new()
	detail.alignment = BoxContainer.ALIGNMENT_END
	_command_panel.add_child(detail)
	for spec in [["entry", "진입 명령 (R)"], ["search", "검색 (Q)"], ["door", "문·창 (E)"], ["hose", "수관 연장 (H)"], ["straight", "직사 방수 (A)"], ["fog", "분무 방수 (S)"], ["stop", "방수 중지 (D)"]]:
		var b := Button.new()
		b.text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(160, 44)
		b.pressed.connect(func() -> void: command_pressed.emit(spec[0]))
		detail.add_child(b)
		_command_buttons[spec[0]] = b
	add_child(_command_panel)
	_command_panel.visible = false


func _build_legend() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -316
	panel.offset_right = -16
	panel.offset_top = 64
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "열화상"
	box.add_child(title)
	var bar := TextureRect.new()
	var tex := GradientTexture1D.new()
	tex.gradient = FireView.thermal_gradient()
	bar.texture = tex
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.custom_minimum_size = Vector2(280, 14)
	box.add_child(bar)
	var scale_row := HBoxContainer.new()
	var lo := Label.new()
	lo.text = "%d℃" % int(sim.fire.config.value("ambient_temp_c"))
	lo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hi := Label.new()
	hi.text = "%d℃ 이상" % int(FireView.THERMAL_MAX_C)
	scale_row.add_child(lo)
	scale_row.add_child(hi)
	box.add_child(scale_row)
	add_child(panel)
	panel.visible = false
	_legend = panel


func _build_debug_panel() -> void:
	_debug_panel = PanelContainer.new()
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_panel.position = Vector2(16, 64)
	var box := VBoxContainer.new()
	_debug_panel.add_child(box)
	var title := Label.new()
	title.text = "화재 정보 (개발용, F9)"
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = DEBUG_COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 14)
	box.add_child(grid)
	for col in DEBUG_COLUMNS:
		grid.add_child(_debug_label(col, Color("8fa1b3")))
	for c in sim.fire.comps:
		for col in DEBUG_COLUMNS:
			var label := _debug_label("", Color.WHITE)
			grid.add_child(label)
			_debug_cells.append(label)
	_debug_events = _debug_label("", Color("cbd5e1"))
	box.add_child(_debug_events)
	add_child(_debug_panel)
	_debug_panel.visible = false


func _debug_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	return label


func _refresh_debug() -> void:
	var fire := sim.fire
	var n := DEBUG_COLUMNS.size()
	for ci in fire.comps.size():
		var c := fire.comps[ci]
		var values := [
			c.display_name(),
			c.stage_name(),
			"%.0f" % c.t_upper,
			"%.0f" % c.t_lower,
			"%.1f" % c.layer_depth,
			"%.1f" % c.o2_percent(),
			"%.1f" % c.gas_percent(),
			"%.0f" % c.q,
			"%.1f" % fire.visibility_m(c),
			"%.0f" % c.flashover_temp,
		]
		for k in n:
			var label := _debug_cells[ci * n + k]
			label.text = values[k]
			label.add_theme_color_override("font_color", Color("fca5a5") if c.flashed else Color.WHITE)
	var lines: PackedStringArray = []
	var entries := sim.events.entries
	for k in range(maxi(0, entries.size() - DEBUG_EVENT_LINES), entries.size()):
		lines.append(SimEventLog.describe(entries[k]))
	_debug_events.text = "\n".join(lines)


## 활동 단계 표시줄: 지난 단계는 흐리게, 지금 단계는 강조
func _refresh_phase_bar() -> void:
	if phase_bar == null:
		return
	var ph := sim.phases
	var parts: PackedStringArray = []
	for i in PhaseSystem.PHASE_NAMES.size():
		var name := "%s %s" % ["①②③④⑤⑥⑦⑧"[i], PhaseSystem.PHASE_NAMES[i]]
		if i == ph.phase:
			parts.append("[color=#fde68a][b]%s[/b][/color]" % name)
		elif ph.reached.has(i):
			parts.append("[color=#64748b]%s[/color]" % name)
		else:
			parts.append("[color=#94a3b8]%s[/color]" % name)
	phase_bar.text = "[center]%s[/center]" % " → ".join(parts)
	phase_bar.position = Vector2((size.x - phase_bar.size.x) * 0.5, 6.0)


# --- R6a: 상황 배지·층 막대·무전 자막·긴급탈출 ---

## 상황 배지 둘째 줄: 전략 · 풍향 · 대응 단계 (기획안 9-2)
func _badge_line() -> String:
	var cmd := sim.command
	var strategy := CommandSystem.STRATEGY_NAMES[cmd.strategy] if cmd.declared() else "전략 미선언"
	var wind := "바람 없음"
	if sim.exposure.wind_mps > 0.0:
		var dirs := ["북", "북동", "동", "남동", "남", "남서", "서", "북서"]
		wind = "%s풍 %.0fm/s" % [dirs[roundi(fposmod(sim.exposure.wind_from_deg, 360.0) / 45.0) % 8], sim.exposure.wind_mps]
	var level := "선착대"
	var sup := sim.events.of_type("support_requested")
	if not sup.is_empty():
		level = str(sup[-1].level)
	return "%s · %s · %s" % [strategy, wind, level]


func _on_badge_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		command_ui.open_command_dialog()


var _floor_timer := 0.0


## 층 막대: 층마다 보이는 불·연기와 대원 수 (기획안 9-2). 맨 아래 층은 바깥 포함
func _refresh_floor_bar(delta: float) -> void:
	_floor_timer -= delta
	if _floor_timer > 0.0:
		return
	_floor_timer = 0.5
	var fire := {}
	var smoke := {}
	var grid := sim.fire.grid
	for i in grid.burning:
		if not sim.perception.enabled or sim.perception.seen_burning[i] == 1:
			fire[grid.cell_of(i).z] = true
	for c in sim.fire.comps:
		if c.layer_depth > 0.6 and (not sim.perception.enabled or sim.perception.room_visible(c)):
			smoke[c.level] = true
	var crews := {}
	for ff in sim.units.firefighters:
		if not ff.aboard:
			crews[ff.level] = int(crews.get(ff.level, 0)) + 1
	var lowest := sim.building.levels()[0]
	for level: int in _floor_buttons:
		var b: Button = _floor_buttons[level]
		var mark := " 불" if fire.has(level) else (" 연기" if smoke.has(level) else "")
		b.text = "%s%s%s  %d명" % [sim.building.floor_name(level), "·외부" if level == lowest else "", mark, int(crews.get(level, 0))]
		var color := Color("f87171") if fire.has(level) else (Color("cbd5e1") if smoke.has(level) else Color("e2e8f0"))
		b.add_theme_color_override("font_color", color)


var _subtitles: Label


## 무전 자막: 화면 아래 왼쪽 반투명 2~3줄, 5초 뒤 사라짐, 대원 안전 무전은 빨강 (기획안 9-2, SOP 107)
func _build_subtitles() -> void:
	_subtitles = Label.new()
	_subtitles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitles.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitles.custom_minimum_size = Vector2(760, 0)
	_subtitles.add_theme_font_size_override("font_size", 17)
	_subtitles.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_subtitles.add_theme_constant_override("outline_size", 5)
	add_child(_subtitles)


func _refresh_subtitles() -> void:
	var radio := sim.command.radio
	var now := sim.clock.tick
	var lines: PackedStringArray = []
	var danger := false
	var shown := 0
	for i in range(radio.history.size() - 1, -1, -1):
		var m := radio.history[i]
		if (now - m.end_tick) * SimClock.TICK_DT > 5.0 or shown >= 3:
			break
		lines.insert(0, m.text())
		danger = danger or m.priority == Radio.Priority.SAFETY
		shown += 1
	if radio.current:
		lines.append("▶ " + radio.current.text())
		danger = danger or radio.current.priority == Radio.Priority.SAFETY
	_subtitles.text = "\n".join(lines)
	_subtitles.add_theme_color_override("font_color", Color("fca5a5") if danger else Color("f1f5f9"))
	var bottom := console.position.y if console else size.y - 120.0
	_subtitles.position = Vector2(16, bottom - 8.0 - _subtitles.get_combined_minimum_size().y)


var _emergency_button: Button
var _vignette: Control


## 긴급탈출 상황: 화면 위쪽 큰 빨간 버튼(누르면 긴급탈출 지시 — 전원 철수), 화면 가장자리 붉은 비네트 (기획안 9-3)
func _build_emergency() -> void:
	_vignette = Control.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.draw.connect(_draw_vignette)
	add_child(_vignette)
	_emergency_button = Button.new()
	_emergency_button.text = "⚠ 긴급탈출 상황 — 눌러서 전원 긴급탈출 지시 (RIT는 조직 창·카드로 투입)"
	_emergency_button.focus_mode = Control.FOCUS_NONE
	_emergency_button.custom_minimum_size = Vector2(620, 48)
	_emergency_button.add_theme_font_size_override("font_size", 18)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.75, 0.08, 0.08, 0.92)
	st.set_corner_radius_all(8)
	_emergency_button.add_theme_stylebox_override("normal", st)
	_emergency_button.pressed.connect(func() -> void: command_ui.order_issued.emit(CommandOrder.make("evacuate")))
	_emergency_button.visible = false
	add_child(_emergency_button)


func _refresh_emergency() -> void:
	var on := sim.command.safety.emergency() and not sim.ended()
	_emergency_button.visible = on
	_emergency_button.position = Vector2((size.x - _emergency_button.size.x) * 0.5, 40.0)
	_vignette.queue_redraw()


## 위기 비네트: 긴급탈출이거나 최근 30초 안에 특수현상 징후가 있으면 화면 가장자리를 붉게
func _draw_vignette() -> void:
	var hot := sim.command.safety.emergency()
	if not hot:
		for t in ["rollover_sign", "backdraft_sign", "fgi_warning", "collapse_sign", "jump_risk"]:
			var list := sim.events.of_type(t)
			if not list.is_empty() and (sim.clock.tick - int(list[-1].tick)) * SimClock.TICK_DT < 30.0:
				hot = true
	if not hot or sim.ended():
		return
	var pulse := 0.25 + 0.15 * sin(Time.get_ticks_msec() / 250.0)
	var r := Rect2(Vector2.ZERO, _vignette.size)
	for k in 6:
		var w := 6.0 * (k + 1)
		var c := Color(0.9, 0.1, 0.1, pulse * (1.0 - k / 6.0))
		_vignette.draw_rect(r.grow(-w + 6.0), c, false, 6.0)


# --- R6b: 하단 콘솔 (기획안 9-2) ---

const CONSOLE_MIN_H := 150.0
var console: PanelContainer
var _commander_box: VBoxContainer
var minimap: MinimapView
var _minimap_ms := 0


## 화면 아래 반투명 띠: 왼쪽 미니맵 자리 · 가운데 선택 정보 · 오른쪽 명령 버튼 (선택 대상에 따라)
func _build_console() -> void:
	console = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.12, 0.78)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	console.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	console.add_child(row)
	# 미니맵: 도면을 얻기 전에는 잠김, 얻으면 평면·대원·확인한 불 (R8)
	minimap = MinimapView.new()
	minimap.setup(sim)
	minimap.custom_minimum_size = Vector2(240, 0)
	minimap.tooltip_text = "도면은 관리사무소·방재실에 조를 보내거나 지휘대가 도착하면 얻습니다. 얻은 뒤에는 클릭하면 그곳으로 이동"
	row.add_child(minimap)
	# 선택 정보
	var info := ScrollContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	selection_label.get_parent().remove_child(selection_label)
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(selection_label)
	row.add_child(info)
	$SelectionPanel.visible = false
	# 명령: 조를 고르면 출동대 명령칸·세부 명령, 아니면 지휘관 명령
	var cmd := VBoxContainer.new()
	cmd.alignment = BoxContainer.ALIGNMENT_END
	_command_panel.get_parent().remove_child(_command_panel)
	_command_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cmd.add_child(_command_panel)
	_commander_box = VBoxContainer.new()
	for r in command_ui.command_rows:
		r.get_parent().remove_child(r)
		_commander_box.add_child(r)
	cmd.add_child(_commander_box)
	var help := Button.new()
	help.text = "? 조작"
	help.focus_mode = Control.FOCUS_NONE
	help.tooltip_text = $HelpLabel.text
	help.size_flags_horizontal = Control.SIZE_SHRINK_END
	cmd.add_child(help)
	$HelpLabel.visible = false
	row.add_child(cmd)
	add_child(console)
	move_child(console, 0)


## 아무것도 고르지 않았을 때: 출동대 전체 요약 (기획안 9-2)
func _squad_summary() -> String:
	var lines: PackedStringArray = ["선택 없음 — 출동대 요약 (대원을 클릭하거나 끌어서 고르세요)"]
	var res := sim.command.resources
	for squad in sim.units.squads:
		var state := "현장 접근 중" if res.is_en_route(squad.id) else ("대기1단계" if res.is_staged(squad.id) else "현장")
		var inside := 0
		var low := 1.0
		for c in squad.crews:
			if not sim.building.cell(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y)) in BuildingData.OUTDOOR:
				inside += 1
				low = minf(low, c.leader.air_ratio())
		lines.append("%s (%s) %s%s" % [squad.name, squad.type, state, " · 내부 %d조, 최저 공기 %d%%" % [inside, roundi(low * 100.0)] if inside > 0 else ""])
	return "\n".join(lines)


## 콘솔·왼쪽 열(층 막대·구조대상자·열화상 범례) 자리 잡기
func _layout_console() -> void:
	if console == null:
		return
	var h := maxf(CONSOLE_MIN_H, size.y * 0.18)
	console.position = Vector2(8.0, size.y - h - 8.0)
	command_ui.board_bottom = console.position.y - 8.0
	if minimap and Time.get_ticks_msec() - _minimap_ms > 250:
		_minimap_ms = Time.get_ticks_msec()
		minimap.queue_redraw()
	console.size = Vector2(size.x - 16.0, h)
	var y := floor_tabs.position.y + floor_tabs.size.y + 8.0
	if _victim_panel:
		_victim_panel.position = Vector2(16.0, y)
		if _victim_panel.visible:
			y += _victim_panel.size.y + 8.0
	if _legend:
		_legend.position = Vector2(16.0, y)
