class_name Hud
extends Control
## 화면 정보: 게임 시계·배속·모드, 층 탭, 선택 정보, 명령 패널, 조작 안내,
## 열화상 범례, 개발용 화재 정보 패널. 지휘 화면(무전·상황보고·전략)은 command_ui.gd, 디브리핑은 debrief_ui.gd.

## 명령 카드 칸을 눌렀을 때 (Q W E R A S — 단축키와 같은 처리, P10-2)
signal card_key_pressed(key: String)
## 내부 보기 단추: 켜면 내부 화면(층 분리), 끄면 외부 화면. 층 간격 넓히기(+1)·좁히기(-1)
signal interior_toggled(on: bool)
## 내부 화면 층 수 단추: 한 화면에 맞춰 넣을 층 수 (1·2·3)
signal span_selected(span: int)
signal split_gap_step(dir: int)
## 지휘관 명령 칸의 단추를 눌렀을 때 (명령 id — data/commands.json commander_board·commander_tools)
signal board_pressed(id: String)

const DEBUG_REFRESH_S := 0.25
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
	"fgi_warning", "window_vented", "entry_wait", "entry_rejected", "entry_denied", "zone_set", "zone_rejected", "zone_warning", "triage_post_set", "victim_handover", "rescue_no_point", "triage_tagged", "withdraw", "auto_slow",
	"squad_dispatched", "staging_full", "order_en_route", "span_warning", "division_set", "division_cleared",
	"face_seen", "site_info_found", "clue_found", "witness_arrived", "statement", "ask_too_far", "ask_cancelled",
	"command_post", "report_updated", "overhaul_start", "rekindle",
	"emergency_cleared", "evacuation_ordered", "par_done", "par_no_response", "role_assigned", "role_reserved", "rit_deployed",
	"entry_factors", "order_unseen", "exit_air_low", "indoor_hydrant_empty", "command_unit_arrived", "command_transferred", "lifeline_laid", "crew_disoriented", "crew_reoriented", "victim_refuge", "elevator_ride", "elevator_arrived", "elevator_far", "elevator_too_high", "monitor_start", "monitor_no_target", "monitor_too_far", "monitor_crew_inside", "ppv_start", "ppv_no_door", "ppv_no_exhaust", "ppv_fire_push", "ppv_exhaust_order", "ppv_exhaust_none", "command_post_set", "post_danger", "forward_set", "command_mode", "zone_install_go", "zone_no_crew", "aerial_deploying", "aerial_deployed", "aerial_stowed", "aerial_debris", "aerial_out_of_reach", "aerial_no_target", "aerial_no_window", "aerial_busy", "aerial_rescue_start", "aerial_no_feed", "fire_not_found", "evac_priority", "rit_misused", "tanker_idle", "hose_to_outlet", "plan_acquired", "panel_fire_floor", "plan_diff_found",
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
var floor_bar: FloorBarView
var _floor_bar_fit_h := 0.0
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
## 명령 카드 (기획안 9-1, P10-2): 6칸 Q W E R / A S. 원형 메뉴와 같은 CommandCard를 그린다.
## 조·차량을 골랐을 때만 오른쪽 정보 창에 보인다 — 지휘관 명령은 아래 바의 네 묶음(board_groups)에 있다
var card: CommandCard
var _command_panel: VBoxContainer
var _card_title: Label
var _card_buttons: Array[Button] = []
var _card_back: Button
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
## 질문 카드 (화면 위쪽 가운데) — 전술상황판보다 뒤에 더해 위에 뜬다
var card_ui: CardUi
## 오른쪽 무전 기록 패널, 팀 초상 줄, 전술상황판 (기획안 9-2·9-2-1, P10-1)
var radio_log: RadioLogPanel
var team_strip: TeamStrip
var board: TacticalBoard
var _board_button: Button
## 화면 모드·조작 안내 한 줄 (왼쪽 위)
var _mode_label: Label


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
	# 층 막대: 반투명 건물 입면 (R16)
	floor_bar = FloorBarView.new()
	floor_bar.setup(sim)
	floor_bar.tooltip_text = " "  # _get_tooltip이 칸마다 문구를 돌려준다
	floor_bar.floor_pressed.connect(on_floor_selected)
	floor_tabs.add_child(floor_bar)
	_build_split_controls()
	$ClockPanel.gui_input.connect(_on_badge_input)
	$ClockPanel.tooltip_text = "클릭: 지휘권 선언 · 전략 변경"
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label = Label.new()
	_mode_label.position = Vector2(16, 12)
	_mode_label.custom_minimum_size = Vector2(420, 0)
	_mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_label.add_theme_font_size_override("font_size", 14)
	_mode_label.add_theme_color_override("font_color", Color("cbd5e1"))
	_mode_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_mode_label.add_theme_constant_override("outline_size", 4)
	add_child(_mode_label)
	_build_subtitles()
	_build_emergency()
	_build_legend()
	_build_debug_panel()
	card = CommandCard.new()
	_build_command_panel()
	_build_notice_label()
	_build_victim_panel()
	# 전술상황판은 지휘 창(command_ui)보다 아래에 깐다 — 상황판을 연 채로 지휘 창·질문 카드가 위에 뜬다
	board = TacticalBoard.new()
	add_child(board)
	command_ui = CommandUi.new()
	add_child(command_ui)
	command_ui.setup(sim)
	# 출동 중 장면은 튜토리얼 안내판 아래에서 시작한다
	command_ui.dispatch.top_inset = func() -> float:
		return tutorial_ui._panel.position.y + tutorial_ui._panel.size.y + 8.0 if tutorial_ui and tutorial_ui.visible and not tutorial_ui.finished else 0.0
	_build_console()
	board.setup(sim, command_ui)
	# 예전 오른쪽 상황판(무전+요약)은 숨기고 무전 기록 전용 패널로
	command_ui._radio_panel.visible = false
	radio_log = RadioLogPanel.new()
	add_child(radio_log)
	radio_log.setup(sim)
	command_ui.right_panel = radio_log
	team_strip = TeamStrip.new()
	add_child(team_strip)
	team_strip.setup(sim)
	radio_log._fold.visible = false
	_radio_urgent_seen = radio_log.urgent_total
	# 그리는 순서: 지도 위 패널들 < 전술상황판 < 지휘 창 < (나중에 더하는) 힌트·디브리핑·질문 카드
	move_child(board, get_child_count() - 1)
	move_child(command_ui, get_child_count() - 1)
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
	if radio_log:
		radio_log.visible = not on
	_debug_timer = 0.0


func _process(delta: float) -> void:
	if sim == null:
		return
	# 시계는 신고 후 경과 (출동 4분 포함, 기획안 4-4) · 현장 시계 배속 (5-8)
	var t := int(sim.since_call_s())
	var text := "신고 후 %02d:%02d" % [floori(t / 60.0), t % 60]
	text += "   현장 시계 ×%s" % (str(snappedf(sim.clock.speed, 0.1)) if fmod(sim.clock.speed, 1.0) != 0.0 else str(int(sim.clock.speed)))
	if sim.realism != "":
		text += "   %s" % sim.realism
	if sim.clock.paused:
		text += "   일시정지"
	clock_label.text = text + "\n" + _badge_line()
	# 화면 모드·조작 안내는 왼쪽 위에 작게 (위 가운데 시계가 길어지지 않게)
	_mode_label.text = "[%s]" % mode_text if mode_text != "" else ""
	_refresh_phase_bar()
	if _notice_label:
		# 알림은 오른쪽 상황판이 가리지 않는 지도 영역 가운데에
		var cx := command_ui.map_center_x()
		_notice_label.offset_left = cx - size.x * 0.5 - 400.0
		_notice_label.offset_right = cx - size.x * 0.5 + 400.0
		_notice_label.offset_top = top_reserved_px() + (56.0 if _emergency_button and _emergency_button.visible else 4.0)
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
	floor_bar.current = level
	floor_bar.queue_redraw()


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
		var extra := ""
		var p := sim.ems.patient_of(v.id)
		if p and sim.ems.on_scene(p):
			where = v.dropoff if v.dropoff != "" else "바깥"
			extra = " · 분류 %s" % sim.ems.tag_name(p)
		lines.append("%s · %s · %s · 발견 %02d:%02d%s" % [v.label(), where, v.state_name(), floori(t / 60.0), t % 60, extra])
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
	우클릭: 이동 (건물 안으로는 혼자 들어가지 않음) · 관계인 클릭: 질문" % [
			cmd.commander.name, cmd.commander.rank, cmd.commander_title, cmd.commander_position_text(),
			" · 관계인에게 질문 중 (%d개 남음)" % ask.questions.size() if not ask.is_empty() else ""])
	selection_label.text = "\n".join(lines) if not lines.is_empty() else _squad_summary()
	# 오른쪽 정보 창은 무언가를 골랐을 때만 (그림은 출동대 종류별)
	if side_panel:
		side_panel.visible = not lines.is_empty()
		if side_panel.visible:
			_side_portrait.texture = _portrait_texture(_selected_kind())
	# 선택 대상에 따라 명령 카드 세트가 바뀐다. 아무것도 안 고르면 카드는 숨는다 (지휘관 명령은 아래 바에 늘 있다)
	card.set_target(card_set())
	_command_panel.visible = card.set_name != ""
	_refresh_card()
	_refresh_board()


## 고른 것 → 명령 카드 세트: 조(구급대면 ems) > 차량 > 없음("")
func card_set() -> String:
	if not _crew_ids.is_empty():
		var squad := sim.units.squad_of_crew(_crew_ids[0])
		return "ems" if squad and squad.type == "구급대" else "team"
	if not _vehicle_ids.is_empty():
		return "vehicle"
	return ""


## 명령 카드 6칸을 지금 상태로 다시 쓴다 (칸 이름·쓸 수 있는지·하위 칸)
func _refresh_card() -> void:
	if _card_title == null:
		return
	_card_title.text = card.title()
	var slots := card.slots()
	for i in _card_buttons.size():
		var b := _card_buttons[i]
		var it: Dictionary = slots[i]
		if it.is_empty():
			b.text = ""
			b.tooltip_text = ""
			b.disabled = true
			b.modulate.a = 0.35
			continue
		var more := "…" if it.get("act", true) == false else ""
		b.text = "%s  %s%s" % [CommandCard.KEYS[i], str(it.label), more]
		b.tooltip_text = str(it.get("hint", "")) + ("
(다음 작업에서 쓸 수 있습니다)" if str(it.get("need", "")) == "later" else "")
		b.disabled = not card.is_enabled(it)
		b.modulate.a = 1.0
		b.add_theme_color_override("font_color", Color("fca5a5") if it.get("danger", false) else Color("f1f5f9"))
	_card_back.visible = card.parent != ""


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
	var need := 0.0
	for ff in crew.members():
		need = maxf(need, ff.exit_air_l / maxf(1.0, ff.air_capacity))
	var parts: PackedStringArray = ["잔압 %dbar (%d%%)" % [roundi(air * 300.0), roundi(air * 100.0)]]
	if need > 0.0:
		parts.append("출구까지 필요 %dbar · 호흡 %dℓ/분" % [maxi(1, roundi(need * 300.0)), roundi(sim.conditions.air_rate(crew.leader))])
	var traits: PackedStringArray = []
	for ff in crew.members():
		if ff.grade != "":
			traits.append("%s %s" % [ff.name, ff.grade])
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
	# 현장 작업 (P4-1): 장비 가지러 감, 차량 타고 오는 중, 휴대 장비
	var fp := sim.doors.fetch_progress(crew.id, sim.clock.tick)
	if fp >= 0.0:
		parts.append("장비 꺼내는 중 %d%%" % roundi(fp * 100.0))
	elif sim.doors.fetches.any(func(f: Dictionary) -> bool: return int(f.crew) == crew.id):
		parts.append("장비 가지러 차량으로")
	if crew.leader.aboard and sim.command.resources.arriving_now():
		parts.append("차량 타고 오는 중")
	if crew.has_item("fire_door_breaker"):
		parts.append("휴대: 방화문 파괴기")
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
		if e.type in NOTICE_TYPES and not CommandSystem.REPORT_PRIORITY.has(e.type) and sim.command.observable(e):
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
	_command_panel = VBoxContainer.new()
	_command_panel.alignment = BoxContainer.ALIGNMENT_END
	var head := HBoxContainer.new()
	_card_title = Label.new()
	_card_title.add_theme_color_override("font_color", Color("fde68a"))
	_card_title.add_theme_font_size_override("font_size", 15)
	_card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_card_title)
	_card_back = Button.new()
	_card_back.text = "◀ 뒤로 (Esc)"
	_card_back.focus_mode = Control.FOCUS_NONE
	_card_back.pressed.connect(func() -> void: card_key_pressed.emit("BACK"))
	head.add_child(_card_back)
	_command_panel.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 4
	_command_panel.add_child(grid)
	for i in CommandCard.KEYS.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(98, 40)
		b.add_theme_font_size_override("font_size", 14)
		b.clip_text = true
		var key := CommandCard.KEYS[i]
		b.pressed.connect(func() -> void: card_key_pressed.emit(key))
		grid.add_child(b)
		_card_buttons.append(b)
	add_child(_command_panel)
	card.changed.connect(_refresh_card)


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
	# 위 가운데: 시계(상황 배지) 바로 아래
	var badge: Control = $ClockPanel
	phase_bar.position = Vector2((size.x - phase_bar.size.x) * 0.5, badge.position.y + badge.size.y + 2.0)


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
	floor_bar.fire = fire
	floor_bar.smoke = smoke
	floor_bar.crews = crews
	floor_bar.queue_redraw()


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
	_emergency_button.text = "⚠ 긴급탈출 상황 — 눌러서 전원 긴급탈출 지시 (RIT 투입은 긴급탈출 무전에 답해서)"
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
	_emergency_button.position = Vector2((size.x - _emergency_button.size.x) * 0.5, top_reserved_px() + 2.0)
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


# --- 아래 바 · 오른쪽 정보 창 (2026-11-14 결정, 프로스트펑크식) ---
# 아래 바: 지휘관 초상 + 지휘관 명령 네 묶음(누르면 세부 명령이 위에 펼쳐진다) + 전술상황판 + 확인 단추 + 팀 초상 줄 + 무전 기록 단추.
# 오른쪽: 조·차량·지휘관을 골랐을 때만 정보 창(그림 + 상태 + 명령 카드), 무전 단추를 켜면 그 아래에 무전 기록.
# 미니맵은 없앴다 — 층 이동은 층 막대, 보고된 평면도는 전술상황판.

## 지휘관 초상 단추를 눌렀을 때 (World가 지휘관을 고른다)
signal commander_pressed

const BAR_H := 80.0
const BAR_BUTTON := Vector2(66, 64)
const SIDE_W := 430.0
var console: PanelContainer
## 없앤 미니맵 자리 — 늘 null (World가 본다)
var minimap: MinimapView
var commander_button: Button
var radio_button: Button
## 무전 기록을 펴 두었는가 (기본은 접힘 — 무전은 자막과 무전 장면으로 본다)
var radio_open := false
var _radio_urgent_seen := 0
var side_panel: PanelContainer
var _side_portrait: TextureRect


func _build_console() -> void:
	console = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.12, 0.82)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	console.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	console.add_child(row)
	# 지휘관 초상
	commander_button = Button.new()
	commander_button.focus_mode = Control.FOCUS_NONE
	commander_button.custom_minimum_size = Vector2(64, 64)
	commander_button.tooltip_text = "현장지휘관 — 누르면 지휘관을 고릅니다 (지휘 위치는 지도에서 우클릭으로 옮깁니다)"
	commander_button.pressed.connect(func() -> void: commander_pressed.emit())
	var face := TextureRect.new()
	face.texture = _portrait_texture("지휘")
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	commander_button.add_child(face)
	row.add_child(commander_button)
	# 지휘관 명령 네 묶음
	_build_board(row)
	# 전술상황판
	_board_button = _bar_button("board", "상황판", "전술상황판 (Tab·M) — 무전으로 보고된 것만 그린 평면도와 현황")
	_board_button.pressed.connect(board.toggle)
	row.add_child(_board_button)
	row.add_child(VSeparator.new())
	# 명령이 아닌 확인 단추와 조작 도움말
	var tools := GridContainer.new()
	tools.columns = 2
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for it in CommandCard.load_tools():
		var t := _make_board_button(it)
		t.custom_minimum_size = Vector2(118, BOARD_BUTTON.y)
		tools.add_child(t)
	var help := Button.new()
	help.text = "? 조작"
	help.focus_mode = Control.FOCUS_NONE
	help.alignment = HORIZONTAL_ALIGNMENT_LEFT
	help.add_theme_font_size_override("font_size", BOARD_FONT)
	help.custom_minimum_size = Vector2(118, BOARD_BUTTON.y)
	help.tooltip_text = $HelpLabel.text
	tools.add_child(help)
	row.add_child(tools)
	# 가운데는 비워 둔다 (팀 초상 줄이 그 위에 놓인다)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	# 무전 기록 단추
	radio_button = _bar_button("radio", "무전", "무전 기록을 화면 오른쪽에 펴거나 접습니다.\n숫자는 접어 둔 동안 들어온 긴급 무전 수입니다")
	radio_button.toggle_mode = true
	radio_button.toggled.connect(set_radio_open)
	row.add_child(radio_button)
	$HelpLabel.visible = false
	add_child(console)
	move_child(console, 0)
	_build_side_panel()


## 아래 바의 네모 단추: 작은 그림 + 아래에 글자
func _bar_button(kind: String, label: String, tip: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = BAR_BUTTON
	b.tooltip_text = tip
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := BarIcon.new(kind)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var text := Label.new()
	text.name = "Text"
	text.text = label
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 13)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)
	b.add_child(box)
	return b


## 출동대 종류별 그림 (data/art.json portraits — 무전 장면과 같은 그림)
func _portrait_texture(kind: String) -> Texture2D:
	var portraits: Dictionary = SpriteArt.config().get("portraits", {})
	var path := str(portraits.get(kind, portraits.get("default", "")))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## 오른쪽 정보 창: 고른 조·차량·지휘관의 그림 + 상태 글 + 명령 카드(Q W E R / A S). 아무것도 안 고르면 숨는다
func _build_side_panel() -> void:
	side_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.12, 0.86)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	side_panel.add_theme_stylebox_override("panel", style)
	side_panel.custom_minimum_size = Vector2(SIDE_W, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	side_panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_side_portrait = TextureRect.new()
	_side_portrait.custom_minimum_size = Vector2(104, 104)
	_side_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_side_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_side_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_side_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_side_portrait)
	selection_label.get_parent().remove_child(selection_label)
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_label.custom_minimum_size = Vector2(SIDE_W - 20.0 - 114.0, 0)
	selection_label.add_theme_font_size_override("font_size", 16)
	head.add_child(selection_label)
	box.add_child(head)
	$SelectionPanel.visible = false
	# 고른 조·차량의 명령 카드
	_command_panel.get_parent().remove_child(_command_panel)
	_command_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_command_panel.visible = false
	box.add_child(_command_panel)
	side_panel.visible = false
	add_child(side_panel)
	move_child(side_panel, 1)


## 고른 것의 그림 종류: 지휘관 > 조(출동대 종류) > 차량
func _selected_kind() -> String:
	if _commander_selected:
		return "지휘"
	if not _crew_ids.is_empty():
		var squad := sim.units.squad_of_crew(_crew_ids[0])
		return squad.type if squad else "default"
	return "차량 운전원"


## 무전 기록 펴기·접기 (아래 바 무전 단추)
func set_radio_open(on: bool) -> void:
	radio_open = on
	if radio_button:
		radio_button.set_pressed_no_signal(on)
	if radio_log:
		_radio_urgent_seen = radio_log.urgent_total


## 화면 위쪽에서 시계·단계 표시줄이 차지하는 높이 (px) — World가 내부 화면을 맞출 때 뺀다
func top_reserved_px() -> float:
	if phase_bar == null:
		return 84.0
	return phase_bar.position.y + phase_bar.size.y + 6.0


# --- 화면 전환 단추 (2026-11-14: 외부 화면 ↔ 내부 화면) ---

var interior_button: Button
## 층 수 단추 세 개 (1개 층 / 2개 층 / 3개 층) — 하나만 눌린 채로 있다
var span_buttons: Array[Button] = []
var _span_row: HBoxContainer
var _split_row: HBoxContainer
var _split_label: Label


## 층 막대 아래: '내부 보기' 켜고 끄는 단추와 (내부 화면일 때) 층 수 단추, 층 간격 − +
func _build_split_controls() -> void:
	interior_button = Button.new()
	interior_button.text = "내부 보기"
	interior_button.toggle_mode = true
	interior_button.focus_mode = Control.FOCUS_NONE
	interior_button.add_theme_font_size_override("font_size", 14)
	interior_button.tooltip_text = "켜면 내부 화면: 고른 층을 가운데에 크게, 바로 위·아래층은 떼어 놓고 건물 안을 봅니다 (층 막대의 층을 눌러도 같습니다).\n끄면 외부 화면: 건물 외관과 바깥 — 차량·급수·구역·둘러보기.\n보이는 위치만 바뀌고 대원·불의 실제 위치는 그대로입니다"
	interior_button.toggled.connect(func(on: bool) -> void: interior_toggled.emit(on))
	floor_tabs.add_child(interior_button)
	_span_row = HBoxContainer.new()
	_span_row.visible = false
	_span_row.add_theme_constant_override("separation", 2)
	var tips: Array[String] = [
		"고른 층만 가운데에 크게 봅니다 (위·아래층은 잘려 보임)",
		"고른 층과 바로 위층을 함께 봅니다 (맨 위층이면 아래층과).\n보고 있는 두 층 안에서는 어느 층을 눌러도 화면이 그대로이고, 그 밖의 층을 누르면 한 층만 따라갑니다",
		"고른 층과 바로 위·아래층이 한 화면에 다 들어오게 축소합니다",
	]
	for i in tips.size():
		var span := i + 1
		var b := Button.new()
		b.text = "%d개 층" % span
		b.toggle_mode = true
		b.button_pressed = span == 1
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = tips[i]
		# 눌린 단추를 다시 눌러도 꺼지지 않는다 (셋 중 하나는 늘 켜져 있다)
		b.toggled.connect(func(on: bool) -> void:
			if on:
				span_selected.emit(span)
			else:
				b.set_pressed_no_signal(true))
		span_buttons.append(b)
		_span_row.add_child(b)
	floor_tabs.add_child(_span_row)
	_split_row = HBoxContainer.new()
	_split_row.visible = false
	for spec: Array in [["−", -1], ["+", 1]]:
		var dir: int = spec[1]
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(30, 26)
		b.tooltip_text = "층 간격 좁히기" if dir < 0 else "층 간격 넓히기"
		b.pressed.connect(func() -> void: split_gap_step.emit(dir))
		_split_row.add_child(b)
		if dir < 0:
			_split_label = Label.new()
			_split_label.add_theme_font_size_override("font_size", 13)
			_split_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_split_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_split_row.add_child(_split_label)
	floor_tabs.add_child(_split_row)


## 지금 화면을 단추에 반영한다 (World가 부른다): 내부 화면인가, 층 간격
func set_view_state(interior: bool, lift_px: float) -> void:
	if interior_button == null:
		return
	interior_button.set_pressed_no_signal(interior)
	_span_row.visible = interior
	_split_row.visible = interior
	_split_label.text = "간격 %dpx" % roundi(lift_px)
	floor_tabs.reset_size()
	# 간격 줄이 막 보이게 됐을 때 자리 잡기를 다음 프레임까지 미루면 그 사이 층 막대 위에 겹쳐 클릭을 가로챈다 — 바로 정렬
	floor_tabs.notification(Container.NOTIFICATION_SORT_CHILDREN)


## 층 수 단추에 지금 값을 반영한다 (World가 부른다). 이 건물에 그만큼 이어진 층이 없으면 그 단추는 끈다
func set_span_state(span: int, max_span: int) -> void:
	for i in span_buttons.size():
		span_buttons[i].set_pressed_no_signal(i + 1 == span)
		span_buttons[i].disabled = i + 1 > max_span


# --- 지휘관 명령 (G3, 2026-11-14 결정) ---

const BOARD_BUTTON := Vector2(146, 27)
const BOARD_FONT := 14
## 묶음 id(report·support·safety·zone) -> 아래 바 단추 / 세부 명령 목록 창
var board_groups: Dictionary = {}
var _flyouts: Dictionary = {}
## 지금 펼쳐진 묶음 ("" = 없음). 한 번에 하나만
var board_group_open := ""
## 명령 id -> Button (지휘관 명령·확인 단추)
var board_buttons: Dictionary = {}
## 이미 한 일이라 흐리게 둘 것인가 (명령 id -> bool). World가 넣는다
var board_done_fn: Callable


## 아래 바에 보고·지원·안전·구역 네 묶음 단추를 놓는다 (data/commands.json commander_board).
## 묶음을 누르면 그 세부 명령이 단추 위에 펼쳐지고, 명령을 누르거나 다른 곳을 누르면 닫힌다.
## 무엇을 고르고 있든 늘 같은 자리에 있고, 때가 됐다고 나타나거나 빛나지 않는다 — 이미 한 일만 흐려진다.
## 일찍 눌러도 막지 않는다: 그대로 실행·기록되고 평가가 시점·순서를 본다
func _build_board(row: HBoxContainer) -> void:
	for g in CommandCard.load_board():
		var gid := str(g.id)
		var b := _bar_button(gid, str(g.label), "%s — 누르면 세부 명령이 위에 펼쳐집니다" % str(g.label))
		b.toggle_mode = true
		b.toggled.connect(func(on: bool) -> void: open_board_group(gid if on else ""))
		board_groups[gid] = b
		row.add_child(b)
		var fly := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.04, 0.07, 0.12, 0.94)
		style.border_color = Color("fde68a")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(8)
		fly.add_theme_stylebox_override("panel", style)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		var head := Label.new()
		head.text = str(g.label)
		head.add_theme_font_size_override("font_size", BOARD_FONT)
		head.add_theme_color_override("font_color", Color("fde68a"))
		box.add_child(head)
		for it: Dictionary in g.get("items", []):
			var item := _make_board_button(it)
			item.custom_minimum_size = Vector2(190, 32)
			item.add_theme_font_size_override("font_size", 15)
			box.add_child(item)
		fly.add_child(box)
		fly.visible = false
		add_child(fly)
		_flyouts[gid] = fly


## 묶음의 세부 명령 목록을 편다 ("" 이면 모두 닫는다)
func open_board_group(id: String) -> void:
	board_group_open = id if _flyouts.has(id) else ""
	for gid: String in _flyouts:
		(_flyouts[gid] as Control).visible = gid == board_group_open
		(board_groups[gid] as Button).set_pressed_no_signal(gid == board_group_open)
	_place_flyout()


## 펼쳐진 목록을 그 묶음 단추 바로 위에 놓는다
func _place_flyout() -> void:
	if board_group_open == "" or console == null:
		return
	var fly: Control = _flyouts[board_group_open]
	var b: Control = board_groups[board_group_open]
	fly.size = fly.get_combined_minimum_size()
	fly.position = Vector2(b.global_position.x - global_position.x, console.position.y - fly.size.y - 6.0)


## 펼쳐진 목록 밖을 누르거나 Esc 를 누르면 닫는다 (그 입력은 그대로 흘려보낸다)
func _input(event: InputEvent) -> void:
	if board_group_open == "":
		return
	if event.is_action_pressed("ui_cancel"):
		open_board_group("")
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if (_flyouts[board_group_open] as Control).get_global_rect().has_point(mb.position):
		return
	for gid: String in board_groups:
		if (board_groups[gid] as Control).get_global_rect().has_point(mb.position):
			return
	open_board_group("")


## 지도 오른쪽에서 정보 창·무전 기록 자리로 비워 두는 폭 (px). 창이 뜨고 사라져도 평면도가 가려지거나 움직이지 않게 늘 같은 값.
## World가 내부 화면을 맞출 때 이만큼 뺀다
func right_reserved_px() -> float:
	return 16.0 + SIDE_W + 8.0


func _make_board_button(item: Dictionary) -> Button:
	var b := Button.new()
	var id := str(item.id)
	b.text = str(item.label)
	b.tooltip_text = str(item.get("hint", ""))
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = BOARD_BUTTON
	b.add_theme_font_size_override("font_size", BOARD_FONT)
	if item.get("danger", false):
		b.add_theme_color_override("font_color", Color("fca5a5"))
	b.pressed.connect(func() -> void:
		board_pressed.emit(id)
		open_board_group(""))
	board_buttons[id] = b
	return b


## 이미 한 일(선언·지원 요청·완진 선언·이양)과 보기 전용에서는 흐리게
func _refresh_board() -> void:
	for id: String in board_buttons:
		var b: Button = board_buttons[id]
		b.disabled = sim.view_only or (board_done_fn.is_valid() and board_done_fn.call(id))


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


## 왼쪽 열(층 막대)이 올라갈 수 있는 맨 위 (시계는 위 가운데로 옮겨 왼쪽 위는 비어 있다)
const LEFT_TOP := 24.0


## 아래 바·위 가운데 시계·오른쪽 자리(정보 창·무전 기록)·왼쪽 열(층 막대·구조대상자·열화상 범례) 자리 잡기
func _layout_console() -> void:
	if console == null:
		return
	console.position = Vector2(8.0, size.y - BAR_H - 8.0)
	console.size = Vector2(size.x - 16.0, BAR_H)
	# 위 가운데: 시계(상황 배지). 단계 표시줄은 그 아래 (_refresh_phase_bar)
	var badge: Control = $ClockPanel
	badge.size = badge.get_combined_minimum_size()
	badge.position = Vector2((size.x - badge.size.x) * 0.5, 6.0)
	# 오른쪽 자리: 고른 것의 정보 창, 그 아래 (무전 단추를 켰으면) 무전 기록. 튜토리얼 안내판이 떠 있으면 그 아래부터
	var rx := size.x - SIDE_W - 8.0
	var ry := 16.0
	if tutorial_ui and tutorial_ui.visible and not tutorial_ui.finished:
		ry = tutorial_ui._panel.position.y + tutorial_ui._panel.size.y + 8.0
	if side_panel:
		side_panel.size = side_panel.get_combined_minimum_size()
		side_panel.position = Vector2(rx, ry)
		if side_panel.visible:
			ry += side_panel.size.y + 8.0
	if radio_log:
		radio_log.visible = radio_open and not _debug_panel.visible
		radio_log._scroll.custom_minimum_size.y = maxf(120.0, console.position.y - ry - 130.0)
		radio_log.size = radio_log.get_combined_minimum_size()
		radio_log.position = Vector2(rx, ry)
		# 접어 둔 동안 들어온 긴급 무전 수를 단추에 보인다
		if radio_open:
			_radio_urgent_seen = radio_log.urgent_total
		var missed := radio_log.urgent_total - _radio_urgent_seen
		var text: Label = radio_button.find_child("Text", true, false)
		text.text = "무전 %d" % missed if missed > 0 else "무전"
		text.add_theme_color_override("font_color", Color("f87171") if missed > 0 else Color("e2e8f0"))
	# 팀 초상 줄은 아래 바 가운데에
	if team_strip:
		team_strip.position = Vector2((size.x - team_strip.custom_minimum_size.x) * 0.5, console.position.y + (BAR_H - team_strip.custom_minimum_size.y) * 0.5)
		team_strip.size = team_strip.custom_minimum_size
	command_ui.board_bottom = console.position.y - 8.0
	_place_flyout()
	# 층 막대는 콘솔 위 공간의 60%까지 (아래에 구조대상자 현황·범례 자리)
	var bottom := console.position.y - 8.0
	if floor_bar:
		var max_h := (bottom - LEFT_TOP) * 0.6
		if absf(max_h - _floor_bar_fit_h) > 4.0:
			_floor_bar_fit_h = max_h
			floor_bar.fit(max_h)
			floor_tabs.reset_size()
	# 층 막대는 위 표시줄과 아래 띠 사이의 위아래 가운데에 (2026-11-14 사용자 결정) — 가운데의 평면도와 눈높이를 맞춘다.
	# 막대 자체를 가운데에 두므로 그 아래 단추 줄이 나타나도 막대는 움직이지 않는다.
	# 아래에 단추·구조대상자 현황·범례가 들어갈 자리가 모자랄 때만 그만큼 위로 올린다
	var below := 0.0
	if _victim_panel and _victim_panel.visible:
		below += _victim_panel.size.y + 8.0
	if _legend and _legend.visible:
		below += _legend.size.y + 8.0
	var bar_h := floor_bar.size.y if floor_bar else floor_tabs.size.y
	var y0 := clampf((LEFT_TOP + bottom - bar_h) * 0.5, LEFT_TOP, maxf(LEFT_TOP, bottom - floor_tabs.size.y - below))
	floor_tabs.position.y = y0
	var y := y0 + floor_tabs.size.y + 8.0
	if _victim_panel:
		_victim_panel.position = Vector2(16.0, y)
		if _victim_panel.visible:
			y += _victim_panel.size.y + 8.0
	if _legend:
		_legend.position = Vector2(16.0, y)


# --- 성능 표시 (F12, 기획안 P14, R15) ---

var _perf: Label


func toggle_perf() -> void:
	if _perf == null:
		_perf = Label.new()
		_perf.add_theme_font_size_override("font_size", 14)
		_perf.add_theme_color_override("font_color", Color("a7f3d0"))
		_perf.add_theme_color_override("font_outline_color", Color.BLACK)
		_perf.add_theme_constant_override("outline_size", 4)
		_perf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_perf.position = Vector2(16, 64)
		add_child(_perf)
		_perf.visible = false
	_perf.visible = not _perf.visible


## 조작 안내 문구 (게임 메뉴의 조작 도움말)
func help_text() -> String:
	return $HelpLabel.text


func perf_visible() -> bool:
	return _perf != null and _perf.visible


## fps · 프레임 ms · 시뮬레이션 ms · 그리기 호출 · 메모리
func update_perf(sim_ms: float) -> void:
	var fps := Engine.get_frames_per_second()
	_perf.text = "성능 (F12)  %d fps · 프레임 %.1fms · 시뮬레이션 %.1fms · 그리기 %d · 메모리 %dMB" % [fps,
		1000.0 / maxf(1.0, fps), sim_ms, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)]
