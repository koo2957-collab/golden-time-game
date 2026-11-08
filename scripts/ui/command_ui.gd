class_name CommandUi
extends Control
## 지휘 화면 요소:
##   출동 지령 창 (시작 시), 지휘권 선언·최초 상황보고 양식 (SOP 101-2.1), 전략 변경 창 (106-2),
##   방어 전략 중 진입 명령 확인 창, 무전 기록 (107), 진입 현황 (201-3.7),
##   조직·지원 창: 지원 요청 (103-1.2), 단위대 지정·해제 (105-3.1), 통솔범위 표시 (105)
##   진술 창 (관계인 클릭, 202-1.2), 현장 정보 창 (F, 101-2.2), 상황 보완 보고 창 (101-2.2①),
##   둘러보기·현장지휘소 판정 표시 (102-2.2, 104-1.3), 활동 종료 선언 확인 창 (113-1.1, 200-4.1, 202-6.5)
##   대원 안전 (109, SSG 9, 108-1.4): 긴급탈출 지시·인원점검 버튼, 조직 창의 RIT·현장안전담당 지정, 긴급탈출 상황 표시
## 창이 열려 있는 동안 게임 시간은 멈춘다 (dialog_changed로 알린다).

## 지휘 명령을 내릴 때 (world가 sim.issue로 넘긴다)
signal order_issued(order: CommandOrder)
## 창이 열리거나 닫힐 때
signal dialog_changed(open: bool)
## 종료 창을 열 때 (교육 모드 힌트)
signal end_dialog_opened

const RADIO_LINES := 6
const RADIO_WIDTH := 660.0
const DIALOG_WIDTH := 820.0
const PLACEHOLDER := "— 선택 —"
const TEXT_COLOR := Color("e2e8f0")
const DIM_COLOR := Color("94a3b8")
const RADIO_COLOR := Color("a7f3d0")
const REFRESH_S := 0.2
const WARN_COLOR := Color("fca5a5")

var sim: SimWorld
var _refresh := 0.0
var _radio_panel: PanelContainer
var _radio_label: Label
var _entry_label: Label
var _dispatch: PanelContainer
var _report: PanelContainer
var _strategy: PanelContainer
var _confirm: PanelContainer
var _confirm_squads: Array[int] = []
var _report_submit: Button
var _options: Dictionary = {}  # 항목 -> OptionButton
var _checks: Dictionary = {}  # 항목 -> Array[CheckBox]
var _auto_labels: Dictionary = {}  # 항목 -> Label
var _strategy_buttons: Array[Button] = []
var _span_label: Label
var _receo_label: RichTextLabel
var _org: PanelContainer
var _org_name: OptionButton
var _org_supervisor: OptionButton
var _org_members: HFlowContainer
var _org_list: VBoxContainer
var _org_support: HBoxContainer
var _org_squads: Array[int] = []  # 단위지휘관 보기 순서 -> squad id
var _survey_label: Label
var _witness: PanelContainer
var _witness_index := -1
var _witness_title: Label
var _witness_status: Label
var _witness_answers: Label
var _witness_checks: VBoxContainer
var _witness_ask: Button
var _info: PanelContainer
var _info_label: Label
var _update: PanelContainer
var _update_victims: OptionButton
var _update_hazards: Array[CheckBox] = []
var _end: PanelContainer
var _end_status: Label
var _end_watch: OptionButton
var _role_crew: OptionButton
var _role_crews: Array[int] = []
var _role_list: Label


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_radio_panel()
	_build_dispatch()
	_build_report()
	_build_strategy()
	_build_confirm()
	_build_org()
	_build_witness()
	_build_info()
	_build_update()
	_build_end()


func _process(delta: float) -> void:
	if sim == null:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		_refresh_radio()


func any_dialog_open() -> bool:
	return _dispatch.visible or _report.visible or _strategy.visible or _confirm.visible or _org.visible \
		or _witness.visible or _info.visible or _update.visible or _end.visible


func set_radio_visible(on: bool) -> void:
	_radio_panel.visible = on


## 지휘 버튼 / C: 선언 전이면 상황보고 양식, 선언 후면 전략 변경 창
func open_command_dialog() -> void:
	if any_dialog_open() or sim.command.is_declaring():
		return
	if sim.command.declared():
		_open(_strategy)
		var current := sim.command.effective_strategy()
		for i in _strategy_buttons.size():
			_strategy_buttons[i].disabled = i + 1 == current
	else:
		_auto_labels["arrived"].text = sim.command.arrived_text()
		_auto_labels["commander"].text = "%s %s %s, %s" % [sim.command.commander_title, sim.command.commander.name,
			sim.command.commander.rank, sim.command.commander_position_text()]
		_update_submit()
		_open(_report)


## 조직·지원 창 (O): 지원 요청, 단위대 지정·해제
func open_org_dialog() -> void:
	if any_dialog_open():
		return
	_rebuild_org()
	_open(_org)


func org_visible() -> bool:
	return _org.visible


## 단위대 지정 (조작 점검용): 이름·단위지휘관·소속 출동대를 고르고 지정한다
func assign_division(name: String, supervisor: int, members: Array[int]) -> void:
	for i in _org_name.item_count:
		if _org_name.get_item_text(i) == name:
			_org_name.select(i)
	_org_supervisor.select(_org_squads.find(supervisor))
	for cb: CheckBox in _org_members.get_children():
		cb.button_pressed = int(cb.get_meta("squad")) in members
	_submit_division()


## 관계인 진술 창 (관계인 클릭)
func open_witness(index: int) -> void:
	if any_dialog_open() or index < 0 or index >= sim.command.survey.witnesses.size():
		return
	_witness_index = index
	_rebuild_witness()
	_open(_witness)


func witness_visible() -> bool:
	return _witness.visible


## 진술 창에서 질문을 고르고 묻는다 (조작 점검용)
func ask_witness(questions: Array[String]) -> void:
	for cb: CheckBox in _witness_checks.get_children():
		cb.button_pressed = str(cb.get_meta("q")) in questions
	_submit_ask()


## 현장 정보 창 (F): 둘러보기·진술·물증 기록
func open_info_dialog() -> void:
	if any_dialog_open():
		return
	_info_label.text = _info_text()
	_open(_info)


func info_visible() -> bool:
	return _info.visible


## 열린 창을 모두 닫는다 (디브리핑으로 넘어갈 때)
func close_all() -> void:
	for p in [_dispatch, _report, _strategy, _confirm, _org, _witness, _info, _update, _end]:
		_close(p)
	_radio_panel.visible = false


## 활동 종료 선언을 확인하는 창 (조작 점검용으로도 쓴다)
func open_end_confirm() -> void:
	_close(_strategy)
	if not any_dialog_open():
		_rebuild_end()
		_open(_end)
		end_dialog_opened.emit()


func confirm_end() -> void:
	var watch := ""
	if _end_watch.selected > 0:
		watch = _end_watch.get_item_text(_end_watch.selected)
	order_issued.emit(CommandOrder.make("end", [], 0, Vector3i.ZERO, {"watch": watch}))
	_close(_end)


## 종료 창의 감시 지정을 고른다 (조작 점검용): 0 지정 안 함, 1 관계자, 2부터 출동대 감시조
func set_end_watch(i: int) -> void:
	_end_watch.select(i)


## 조에 안전 임무를 맡긴다 (조작 점검용)
func assign_role(crew_id: int, role: int) -> void:
	order_issued.emit(CommandOrder.make("role", [crew_id], role))


func show_dispatch() -> void:
	if sim.command.dispatch.is_empty():
		return
	_open(_dispatch)


func dispatch_visible() -> bool:
	return _dispatch.visible


func close_dispatch() -> void:
	_close(_dispatch)


## 방어 전략 중 진입 명령: 병행으로 바꾸고 진입할지 묻는다
func confirm_defensive_entry(squad_ids: Array[int]) -> void:
	if any_dialog_open():
		return
	_confirm_squads = squad_ids.duplicate()
	_open(_confirm)


## 양식의 답 (선택하지 않은 항목은 빈 문자열)
func report_answers() -> Dictionary:
	var a := {}
	for key: String in _options:
		var ob: OptionButton = _options[key]
		a[key] = ob.get_item_text(ob.selected) if ob.selected > 0 else ""
	for key: String in _checks:
		var picked: Array[String] = []
		for cb: CheckBox in _checks[key]:
			if cb.button_pressed:
				picked.append(cb.text)
		a[key] = picked
	a["strategy"] = CommandSystem.STRATEGY_NAMES.find(a["strategy"]) if a["strategy"] != "" else 0
	return a


## 양식 항목을 보기 글자로 고른다 (조작 점검용)
func set_report_choice(key: String, text: String) -> void:
	var ob: OptionButton = _options[key]
	for i in ob.item_count:
		if ob.get_item_text(i) == text:
			ob.select(i)
	_update_submit()


func submit_report() -> void:
	var a := report_answers()
	if not _report_complete():
		return
	order_issued.emit(CommandOrder.make("declare", [], 0, Vector3i.ZERO, a))
	_close(_report)


# --- 내부 ---

func _open(panel: PanelContainer) -> void:
	panel.visible = true
	panel.reset_size()
	panel.position = ((size - panel.get_combined_minimum_size()) / 2.0).floor()
	dialog_changed.emit(true)


func _close(panel: PanelContainer) -> void:
	if not panel.visible:
		return
	panel.visible = false
	if not any_dialog_open():
		dialog_changed.emit(false)


func _report_complete() -> bool:
	for key: String in _options:
		if _options[key].selected <= 0:
			return false
	return true


func _update_submit() -> void:
	if _report_submit:
		_report_submit.disabled = not _report_complete()


func _refresh_radio() -> void:
	var radio := sim.command.radio
	var lines: PackedStringArray = ["무전 (지휘망)" + ("   대기 %d건" % radio.queue.size() if not radio.queue.is_empty() else "")]
	var start := maxi(0, radio.history.size() - RADIO_LINES)
	for i in range(start, radio.history.size()):
		var m := radio.history[i]
		var t := int(m.end_tick * SimClock.TICK_DT)
		lines.append("%02d:%02d  %s" % [floori(t / 60.0), t % 60, m.text()])
	if radio.current:
		lines.append("▶ 송신 중 %d%%  %s" % [roundi(radio.progress() * 100.0), radio.current.text()])
	# 작전망: 단위대마다 송신 중이거나 마지막 무전 한 줄
	for d in sim.command.org.divisions:
		var r := d.radio
		var last := "(무전 없음)"
		if r.current:
			last = "▶ %d%%  %s" % [roundi(r.progress() * 100.0), r.current.text()]
		elif not r.history.is_empty():
			last = r.history[-1].text()
		lines.append("[%s · %s] %s" % [r.channel, d.name, last])
	_radio_label.text = "\n".join(lines)
	_entry_label.text = _entry_text()
	var cmd := sim.command
	var n := cmd.direct_count()
	var span := "직접 지휘 %d (적정 %d, 한계 %d)" % [n, cmd.org.span_ideal, cmd.org.span_max]
	if n > cmd.org.span_ideal:
		span += " — 초과: 명령 %.0f초 지연. 단위대를 지정하세요 (O)" % cmd.span_delay_s()
	if cmd.held_count() > 0:
		span += "  · 실행 대기 명령 %d건" % cmd.held_count()
	_span_label.text = span
	_survey_label.text = _survey_text()
	_receo_label.text = _receo_text()
	_span_label.add_theme_color_override("font_color", WARN_COLOR if n > cmd.org.span_ideal else DIM_COLOR)


## 진입 현황: 출동대별 진입 허가, 건물 안 조와 공기 잔량
func _entry_text() -> String:
	var cmd := sim.command
	var lines: PackedStringArray = ["전략: %s%s" % [CommandSystem.STRATEGY_NAMES[cmd.strategy],
		"" if cmd.declared() else "  (지휘권 미선언 — C)"]]
	if cmd.safety.emergency():
		lines.insert(0, "⚠ 긴급탈출 상황 — 무선 침묵 (SOP 109). 쓰러진 대원에게 RIT·가까운 조 투입 (우클릭)")
	var res := cmd.resources
	for squad in sim.units.squads:
		if res.is_en_route(squad.id):
			lines.append("%s: 현장 접근 중" % squad.name)
			continue
		var state := "진입 허가" if cmd.entry_allowed.has(squad.id) else ("진입 명령 송신 중" if cmd.entry_pending(squad.id) else "진입 대기")
		if not cmd.entry_order_required:
			state = "제한 없음"
		if res.is_staged(squad.id):
			state = "투입 무전 송신 중" if cmd.commit_pending(squad.id) else "대기1단계 (명령하면 투입)"
		var d := cmd.org.division_of(squad.id)
		if d:
			state += " · %s%s" % [d.name, " 지휘" if d.supervisor == squad.id else ""]
		var inside: PackedStringArray = []
		for c in squad.crews:
			var role := cmd.safety.role_of(c.id)
			if role != SafetySystem.Role.NONE:
				state += " · %d조 %s%s" % [c.number, "RIT" if role == SafetySystem.Role.RIT else "안전담당", " 투입" if cmd.safety.deployed.has(c.id) else ""]
			if not sim.building.cell(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y)) in BuildingData.OUTDOOR:
				var air := minf(c.leader.air_ratio(), c.partner.air_ratio() if c.partner else 1.0)
				inside.append("%d조 %s 공기 %d%%" % [c.number, sim.building.floor_name(c.leader.level), roundi(air * 100.0)])
		lines.append("%s: %s%s" % [squad.name, state, ("  · 내부 " + ", ".join(inside)) if not inside.is_empty() else ""])
	for u in res.upcoming(sim.clock.tick):
		var eta := roundi(u.eta_s)
		lines.append("%s: %s 출동 중 — %s" % [u.name, u.reason,
			"약 %d분 %02d초 뒤 도착" % [eta / 60, eta % 60] if eta > 0 else "대기 장소 자리 기다림"])
	return "\n".join(lines)


func _build_radio_panel() -> void:
	_radio_panel = PanelContainer.new()
	_radio_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio_panel.position = Vector2(16, 64)
	_radio_panel.custom_minimum_size = Vector2(RADIO_WIDTH, 0)
	var box := VBoxContainer.new()
	_radio_panel.add_child(box)
	_radio_label = _label("", 15, RADIO_COLOR)
	_radio_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_label.custom_minimum_size = Vector2(RADIO_WIDTH - 16, 0)
	box.add_child(_radio_label)
	box.add_child(HSeparator.new())
	_entry_label = _label("", 15, TEXT_COLOR)
	box.add_child(_entry_label)
	_receo_label = RichTextLabel.new()
	_receo_label.bbcode_enabled = true
	_receo_label.fit_content = true
	_receo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_receo_label.custom_minimum_size = Vector2(RADIO_WIDTH - 16, 0)
	_receo_label.add_theme_font_size_override("normal_font_size", 15)
	box.add_child(_receo_label)
	_span_label = _label("", 15, DIM_COLOR)
	_span_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_span_label.custom_minimum_size = Vector2(RADIO_WIDTH - 16, 0)
	box.add_child(_span_label)
	_survey_label = _label("", 15, TEXT_COLOR)
	_survey_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_survey_label.custom_minimum_size = Vector2(RADIO_WIDTH - 16, 0)
	box.add_child(_survey_label)
	var row := HBoxContainer.new()
	var report_button := _button("지휘 (C)", open_command_dialog)
	var org_button := _button("조직·지원 (O)", open_org_dialog)
	var info_button := _button("현장 정보 (F)", open_info_dialog)
	var walk_button := _button("360° 둘러보기", func() -> void: order_issued.emit(CommandOrder.make("survey")))
	for b in [report_button, org_button, info_button, walk_button]:
		b.custom_minimum_size = Vector2(150, 34)
		row.add_child(b)
	box.add_child(row)
	var row2 := HBoxContainer.new()
	var evac := _button("긴급탈출 지시", func() -> void: order_issued.emit(CommandOrder.make("evacuate")))
	evac.add_theme_color_override("font_color", WARN_COLOR)
	var par := _button("인원점검 (P)", func() -> void: order_issued.emit(CommandOrder.make("par")))
	for b in [evac, par]:
		b.custom_minimum_size = Vector2(150, 34)
		row2.add_child(b)
	box.add_child(row2)
	add_child(_radio_panel)


func _build_dispatch() -> void:
	_dispatch = _dialog()
	var box: VBoxContainer = _dispatch.get_child(0)
	var d := sim.command.dispatch
	box.add_child(_label(str(d.get("title", "출동 지령")), 24, Color("fca5a5")))
	for line in d.get("lines", []):
		var l := _label(str(line), 18, TEXT_COLOR)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(DIALOG_WIDTH - 40, 0)
		box.add_child(l)
	box.add_child(_label("도착하면 지휘권을 선언하고 최초 상황보고를 하십시오 (C). 내부 진입은 진입 명령(R)을 받은 출동대만 합니다.", 16, DIM_COLOR))
	var go := _button("현장 도착 (Enter)", func() -> void: _close(_dispatch))
	box.add_child(go)


func _build_report() -> void:
	_report = _dialog()
	var box: VBoxContainer = _report.get_child(0)
	box.add_child(_label("지휘권 선언 · 최초 상황보고 (SOP 101-2.1)", 22, Color("fde68a")))
	box.add_child(_label("현장에서 확인한 사실만 보고합니다. 아직 모르는 것은 '확인 중'으로.", 15, DIM_COLOR))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	var opts := CommandSystem.REPORT_OPTIONS
	_row_auto(grid, "① 도착 출동대", "arrived")
	_row_option(grid, "② 연소 상황", "fire", sim.command.fire_options())
	_row_option(grid, "② 구조대상자", "victims", opts.victims)
	_row_option(grid, "③ 건물 용도", "use", opts.use)
	_row_option(grid, "③ 층수", "floors", opts.floors)
	_row_option(grid, "③ 건축 구조", "structure", opts.structure)
	_row_checks(grid, "④ 위험 요소 (없으면 비움)", "hazards", opts.hazards)
	_row_auto(grid, "⑤ 지휘권 선언", "commander")
	_row_checks(grid, "⑥ 소방 활동", "activities", opts.activities)
	_row_option(grid, "⑦ 전략", "strategy", ["공격", "방어", "병행"])
	_row_option(grid, "⑧ 지원 요청", "support", opts.support)
	_row_option(grid, "⑨ 차량 진입·회차 (참고, 채점 안 함)", "access", opts.access)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_report_submit = _button("무전 송신", submit_report)
	buttons.add_child(_button("취소", func() -> void: _close(_report)))
	buttons.add_child(_report_submit)
	box.add_child(buttons)


func _build_strategy() -> void:
	_strategy = _dialog()
	var box: VBoxContainer = _strategy.get_child(0)
	box.add_child(_label("전략 변경 (SOP 106-2) — 무전으로 전 대원에게 전파", 22, Color("fde68a")))
	box.add_child(_label("공격: 내부 진입해 검색·진압 · 방어: 외부에서 연소 확대 방지 (내부 대원 철수) · 병행: 둘 다", 15, DIM_COLOR))
	var row := HBoxContainer.new()
	for i in 3:
		var s := i + 1
		var b := _button(CommandSystem.STRATEGY_NAMES[s], func() -> void:
			order_issued.emit(CommandOrder.make("strategy", [], s))
			_close(_strategy))
		row.add_child(b)
		_strategy_buttons.append(b)
	row.add_child(_button("취소", func() -> void: _close(_strategy)))
	box.add_child(row)
	box.add_child(HSeparator.new())
	box.add_child(_label("둘러보기·진술로 새로 알게 된 구조대상자·위험 요소는 보완 보고로 전파합니다 (SOP 101-2.2①).", 15, DIM_COLOR))
	var more := HBoxContainer.new()
	more.add_child(_button("활동 종료 선언", open_end_confirm))
	more.add_child(_button("상황 보완 보고", func() -> void:
		_close(_strategy)
		_update_victims.select(0)
		for cb in _update_hazards:
			cb.button_pressed = false
		_open(_update)))
	box.add_child(more)


func _build_confirm() -> void:
	_confirm = _dialog()
	var box: VBoxContainer = _confirm.get_child(0)
	box.add_child(_label("지금은 방어 전략입니다. 방어 전략에서는 내부 진입을 하지 않습니다.", 20, Color("fde68a")))
	box.add_child(_label("병행 전략으로 바꿔 전파하고 진입 명령을 내리시겠습니까? (SOP 106-2.1.3)", 16, TEXT_COLOR))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_button("취소", func() -> void: _close(_confirm)))
	row.add_child(_button("병행으로 변경 후 진입", func() -> void:
		order_issued.emit(CommandOrder.make("strategy", [], CommandSystem.Strategy.COMBINED))
		order_issued.emit(CommandOrder.make("entry", _confirm_squads))
		_close(_confirm)))
	box.add_child(row)


func _build_org() -> void:
	_org = _dialog()
	var box: VBoxContainer = _org.get_child(0)
	box.add_child(_label("조직·지원 (SOP 103, 105) — 무전으로 지시", 22, Color("fde68a")))
	box.add_child(_label("지원 요청 (상황실)", 17, DIM_COLOR))
	_org_support = HBoxContainer.new()
	box.add_child(_org_support)
	box.add_child(HSeparator.new())
	box.add_child(_label("단위대 지정: 출동대장 한 명을 단위지휘관으로 정하고 소속 출동대를 묶는다. 단위대는 통솔범위에서 1로 센다.", 15, DIM_COLOR))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	grid.add_child(_label("단위대", 17, DIM_COLOR))
	_org_name = OptionButton.new()
	_org_name.focus_mode = Control.FOCUS_NONE
	_org_name.custom_minimum_size = Vector2(320, 34)
	for n in Organization.division_names(sim.building):
		_org_name.add_item(n)
	grid.add_child(_org_name)
	grid.add_child(_label("단위지휘관", 17, DIM_COLOR))
	_org_supervisor = OptionButton.new()
	_org_supervisor.focus_mode = Control.FOCUS_NONE
	_org_supervisor.custom_minimum_size = Vector2(320, 34)
	grid.add_child(_org_supervisor)
	grid.add_child(_label("소속 출동대", 17, DIM_COLOR))
	_org_members = HFlowContainer.new()
	_org_members.custom_minimum_size = Vector2(520, 0)
	grid.add_child(_org_members)
	var assign := HBoxContainer.new()
	assign.alignment = BoxContainer.ALIGNMENT_END
	assign.add_child(_button("단위대 지정", _submit_division))
	box.add_child(assign)
	box.add_child(HSeparator.new())
	box.add_child(_label("현재 단위대", 17, DIM_COLOR))
	_org_list = VBoxContainer.new()
	box.add_child(_org_list)
	box.add_child(HSeparator.new())
	box.add_child(_label("안전 임무 (SSG 9 RIT, SOP 108-1.4 현장안전담당) — 맡은 조는 다른 임무를 받지 않고 밖에서 대기", 15, DIM_COLOR))
	var roles := HBoxContainer.new()
	_role_crew = OptionButton.new()
	_role_crew.focus_mode = Control.FOCUS_NONE
	_role_crew.custom_minimum_size = Vector2(260, 38)
	roles.add_child(_role_crew)
	for spec in [["RIT 지정", SafetySystem.Role.RIT], ["현장안전담당 지정", SafetySystem.Role.OFFICER], ["임무 해제", SafetySystem.Role.NONE]]:
		var role: int = spec[1]
		var b := _button(spec[0], func() -> void:
			if _role_crew.selected >= 0 and _role_crew.selected < _role_crews.size():
				order_issued.emit(CommandOrder.make("role", [_role_crews[_role_crew.selected]], role))
				_close(_org))
		b.custom_minimum_size = Vector2(170, 38)
		roles.add_child(b)
	box.add_child(roles)
	_role_list = _label("", 15, TEXT_COLOR)
	box.add_child(_role_list)
	var close := HBoxContainer.new()
	close.alignment = BoxContainer.ALIGNMENT_END
	close.add_child(_button("닫기", func() -> void: _close(_org)))
	box.add_child(close)


## 창을 열 때마다 현장 출동대·단위대에 맞춰 다시 만든다
func _rebuild_org() -> void:
	var cmd := sim.command
	for c in _org_support.get_children():
		c.queue_free()
		_org_support.remove_child(c)
	for level in cmd.resources.support_options():
		var b := _button(level, func() -> void:
			order_issued.emit(CommandOrder.make("support", [], 0, Vector3i.ZERO, {"level": level}))
			_close(_org))
		b.custom_minimum_size = Vector2(220, 38)
		b.disabled = cmd.resources.support_level == level
		_org_support.add_child(b)
	if cmd.resources.support_level != "":
		_org_support.add_child(_label("  요청함: %s" % cmd.resources.support_level, 15, DIM_COLOR))
	_org_supervisor.clear()
	_org_squads.clear()
	for c in _org_members.get_children():
		c.queue_free()
		_org_members.remove_child(c)
	for squad in sim.units.squads:
		if not cmd.resources.on_scene(squad.id):
			continue
		_org_supervisor.add_item("%s 대장" % squad.name)
		_org_squads.append(squad.id)
		var cb := CheckBox.new()
		cb.text = squad.name
		cb.focus_mode = Control.FOCUS_NONE
		cb.set_meta("squad", squad.id)
		_org_members.add_child(cb)
	_role_crew.clear()
	_role_crews.clear()
	var role_lines: PackedStringArray = []
	for c in sim.units.crews:
		if not cmd.resources.on_scene(c.squad_id):
			continue
		var name := "%s %d조" % [sim.units.squads[c.squad_id].name, c.number]
		var role := cmd.safety.role_of(c.id)
		_role_crew.add_item(name + ("  [%s]" % SafetySystem.ROLE_NAMES[role] if role != SafetySystem.Role.NONE else ""))
		_role_crews.append(c.id)
		if role != SafetySystem.Role.NONE:
			role_lines.append("%s — %s%s" % [name, SafetySystem.ROLE_NAMES[role], " (투입)" if cmd.safety.deployed.has(c.id) else ""])
	_role_list.text = "현재: " + (", ".join(role_lines) if not role_lines.is_empty() else "없음")
	for c in _org_list.get_children():
		c.queue_free()
		_org_list.remove_child(c)
	if cmd.org.divisions.is_empty():
		_org_list.add_child(_label("없음 — 모든 출동대를 현장지휘관이 직접 지휘", 15, TEXT_COLOR))
	for d in cmd.org.divisions:
		var row := HBoxContainer.new()
		var names: PackedStringArray = []
		for id in d.squads:
			names.append(sim.units.squads[id].name)
		var l := _label("%s — 지휘: %s 대장 · 소속: %s · %s" % [d.name, sim.units.squads[d.supervisor].name, "·".join(names), d.radio.channel], 16, TEXT_COLOR)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var dname := d.name
		var b := _button("해제", func() -> void:
			order_issued.emit(CommandOrder.make("division_clear", [], 0, Vector3i.ZERO, {"name": dname}))
			_close(_org))
		b.custom_minimum_size = Vector2(90, 34)
		row.add_child(b)
		_org_list.add_child(row)


func _submit_division() -> void:
	if _org_supervisor.selected < 0 or _org_supervisor.selected >= _org_squads.size():
		return
	var supervisor := _org_squads[_org_supervisor.selected]
	var members: Array[int] = []
	for cb: CheckBox in _org_members.get_children():
		if cb.button_pressed:
			members.append(int(cb.get_meta("squad")))
	var name := _org_name.get_item_text(_org_name.selected)
	order_issued.emit(CommandOrder.make("division", members, supervisor, Vector3i.ZERO, {"name": name}))
	_close(_org)


## 대원 안전 + RECEO 상태판 (SOP 106-1.1② 전술적 우선순위, 208-1.1 RECEO). 확인한 정보 기준,
## 처리되지 않은 첫 줄을 '현재 우선'으로 강조한다.
func _receo_text() -> String:
	var cmd := sim.command
	var b := sim.building
	var inside := 0
	var min_air := 1.0
	for ff in sim.units.firefighters:
		if not b.cell(ff.level, floori(ff.pos.x), floori(ff.pos.y)) in BuildingData.OUTDOOR:
			inside += 1
			min_air = minf(min_air, ff.air_ratio())
	var signs := 0
	for t in ["rollover_sign", "backdraft_sign", "fgi_warning"]:
		for e in sim.events.of_type(t):
			if sim.clock.tick - int(e.tick) <= cmd.safety.factor_recent_ticks:
				signs += 1
	var possible := cmd.victim_truth() == "있음"
	var found := 0
	var saved := 0
	for v in sim.rescue.victims:
		if v.discovered:
			found += 1
		if v.state == Victim.State.RESCUED:
			saved += 1
	var unsearched := 0
	for c in sim.fire.comps:
		if c.searched_tick < 0 and not sim.fire.is_exposure_comp(c):
			unsearched += 1
	var rooms := {}
	var grid := sim.fire.grid
	for i in grid.burning:
		if not sim.perception.enabled or sim.perception.seen_burning[i] == 1:
			var p := grid.cell_of(i)
			var c := sim.fire.compartment_at(p.z, p.x, p.y)
			if c:
				rooms[c.index] = true
	var flashed := 0
	for c in sim.fire.comps:
		if c.flashed:
			flashed += 1
	var nozzles := 0
	for h in sim.water.hoses:
		if h.flowing:
			nozzles += 1
	var embers := sim.rekindle.spotted_cells().size()
	var ex := sim.exposure
	var exposure_text := "인접 건물 없음"
	var exposure_hot := false
	if ex.has_exposure():
		var r := ex.max_ratio()
		exposure_hot = r >= 0.2 or not ex.ignited.is_empty()
		exposure_text = "%s 연소 확대됨" % ex.exposure_name() if not ex.ignited.is_empty() else "%s 가열 %d%%" % [ex.exposure_name(), roundi(r * 100.0)]
	if sim.gas.has_gas():
		exposure_text += " · 가스 %s" % ("차단됨" if not sim.gas.open else "열림")
	var items := [
		[cmd.safety.emergency() or signs > 0 or (inside > 0 and min_air < 0.3), "안전",
			"%s내부 %d명%s%s" % ["⚠ 긴급탈출 · " if cmd.safety.emergency() else "", inside,
			" · 최저 공기 %d%%" % roundi(min_air * 100.0) if inside > 0 else "", " · 특수현상 징후 %d" % signs if signs > 0 else ""]],
		[(possible and (found > saved or unsearched > 0)) or sim.ems.waiting_count() > 0, "R 구조",
			"구조대상자 %s · 발견 %d · 구조 %d · 미검색 구획 %d%s" % ["가능성 있음" if possible else "없음", found, saved, unsearched,
			" · 처치 대기 %d" % sim.ems.waiting_count() if sim.ems.waiting_count() > 0 else ""]],
		[flashed > 0 or exposure_hot, "E 외부", "%s · %s" % ["창 화염 분출 가능 %d구획" % flashed if flashed > 0 else "징후 없음", exposure_text]],
		[rooms.size() > 1, "C 확산", "연소 확인 구획 %d" % rooms.size()],
		[rooms.size() > 0, "E 진압", "방수 중 관창 %d" % nozzles],
		[embers > 0, "O 잔불", "찾은 불씨 %d" % embers],
	]
	var lines: PackedStringArray = ["[color=#94a3b8]우선순위 (대원 안전 → RECEO)[/color]"]
	var marked := false
	for it: Array in items:
		var mark := ""
		var color := "94a3b8"
		if it[0] and not marked:
			mark = "▶ "
			color = "fde68a"
			marked = true
		elif it[0]:
			color = "e2e8f0"
		lines.append("[color=#%s]%s%s: %s[/color]" % [color, mark, it[1], it[2]])
	return "\n".join(lines)


## 둘러보기 현황과 현장지휘소 판정 한 줄
func _survey_text() -> String:
	var survey := sim.command.survey
	var faces: PackedStringArray = []
	for key in survey.face_keys():
		faces.append("%s%s" % [key, "✓" if survey.face_seen(key) else "–"])
	var p := survey.post
	var text := "둘러보기 %s" % " ".join(faces)
	if not p.is_empty():
		text += "  ·  지휘 위치: 관찰 %s%s · 안전 %s (건물에서 %.1fm) · 동선 %s" % [p.observe,
			"(%s면)" % p.faces if p.faces != "" else "", p.safety, p.distance_m, p.route]
	return text


func _info_text() -> String:
	var survey := sim.command.survey
	var lines: PackedStringArray = [_survey_text(), ""]
	if survey.log.is_empty():
		lines.append("아직 확인한 정보가 없습니다.")
	for entry in survey.log:
		var t := int(entry.tick * SimClock.TICK_DT)
		lines.append("%02d:%02d  [%s] %s — %s" % [floori(t / 60.0), t % 60, entry.kind, entry.source, entry.text])
	var hz := survey.known_hazards()
	lines.append("")
	lines.append("확인한 위험 요소: %s" % (", ".join(PackedStringArray(hz)) if not hz.is_empty() else "없음"))
	return "\n".join(lines)


func _build_witness() -> void:
	_witness = _dialog()
	var box: VBoxContainer = _witness.get_child(0)
	_witness_title = _label("", 22, Color("fde68a"))
	box.add_child(_witness_title)
	box.add_child(_label("관계인·목격자의 말은 틀릴 수도 있습니다. 다른 단서와 맞춰 보세요 (SOP 101-2.2②).", 15, DIM_COLOR))
	_witness_status = _label("", 16, TEXT_COLOR)
	box.add_child(_witness_status)
	_witness_answers = _label("", 16, RADIO_COLOR)
	_witness_answers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_witness_answers.custom_minimum_size = Vector2(DIALOG_WIDTH - 40, 0)
	box.add_child(_witness_answers)
	_witness_checks = VBoxContainer.new()
	box.add_child(_witness_checks)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_button("지휘관 이동", func() -> void:
		var w := sim.command.survey.witnesses[_witness_index]
		order_issued.emit(CommandOrder.make("commander_move", [], 0, Vector3i(floori(w.pos.x) + 1, floori(w.pos.y), 1)))
		_close(_witness)))
	row.add_child(_button("닫기", func() -> void: _close(_witness)))
	_witness_ask = _button("질문", _submit_ask)
	row.add_child(_witness_ask)
	box.add_child(row)


func _rebuild_witness() -> void:
	var survey := sim.command.survey
	var w := survey.witnesses[_witness_index]
	_witness_title.text = "관계인 — %s" % w.label()
	var near := survey.in_ask_range(_witness_index)
	_witness_status.text = "질문할 수 있음 (질문 하나에 %.0f초, 그동안 지휘관은 움직이지 않음)" % survey.ask_seconds() if near \
		else "지휘관이 가까이(3m) 가야 질문할 수 있습니다."
	var answers: PackedStringArray = []
	for q: String in w.asked:
		answers.append("%s → \"%s\"" % [SiteSurvey.QUESTIONS[q], w.statements[q].get("text", "")])
	_witness_answers.text = "\n".join(answers) if not answers.is_empty() else "(아직 들은 진술 없음)"
	for c in _witness_checks.get_children():
		c.queue_free()
		_witness_checks.remove_child(c)
	for q: String in SiteSurvey.QUESTIONS:
		if w.asked.has(q) or not w.statements.has(q):
			continue
		var cb := CheckBox.new()
		cb.text = SiteSurvey.QUESTIONS[q]
		cb.focus_mode = Control.FOCUS_NONE
		cb.set_meta("q", q)
		_witness_checks.add_child(cb)
	_witness_ask.disabled = not near or _witness_checks.get_child_count() == 0


func _submit_ask() -> void:
	var qs: Array[String] = []
	for cb: CheckBox in _witness_checks.get_children():
		if cb.button_pressed:
			qs.append(str(cb.get_meta("q")))
	if qs.is_empty():
		return
	order_issued.emit(CommandOrder.make("ask", [], _witness_index, Vector3i.ZERO, {"questions": qs}))
	_close(_witness)


func _build_info() -> void:
	_info = _dialog()
	var box: VBoxContainer = _info.get_child(0)
	box.add_child(_label("현장 정보 (SOP 101-2.2, 202-2) — 둘러보기·진술·물증", 22, Color("fde68a")))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DIALOG_WIDTH - 40, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_info_label = _label("", 16, TEXT_COLOR)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(DIALOG_WIDTH - 60, 0)
	scroll.add_child(_info_label)
	box.add_child(scroll)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_button("닫기", func() -> void: _close(_info)))
	box.add_child(row)


func _build_update() -> void:
	_update = _dialog()
	var box: VBoxContainer = _update.get_child(0)
	box.add_child(_label("상황 보완 보고 (SOP 101-2.2①)", 22, Color("fde68a")))
	box.add_child(_label("지금까지 확인한 사실로 다시 보고합니다. 전략은 그대로 유지합니다 (바꾸려면 전략 변경).", 15, DIM_COLOR))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)
	grid.add_child(_label("② 구조대상자", 17, DIM_COLOR))
	_update_victims = OptionButton.new()
	_update_victims.focus_mode = Control.FOCUS_NONE
	_update_victims.custom_minimum_size = Vector2(320, 34)
	_update_victims.add_item(PLACEHOLDER)
	for v in CommandSystem.REPORT_OPTIONS.victims:
		_update_victims.add_item(v)
	grid.add_child(_update_victims)
	grid.add_child(_label("④ 위험 요소 (없으면 비움)", 17, DIM_COLOR))
	var flow := HFlowContainer.new()
	flow.custom_minimum_size = Vector2(520, 0)
	for h in CommandSystem.REPORT_OPTIONS.hazards:
		var cb := CheckBox.new()
		cb.text = h
		cb.focus_mode = Control.FOCUS_NONE
		flow.add_child(cb)
		_update_hazards.append(cb)
	grid.add_child(flow)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_button("취소", func() -> void: _close(_update)))
	row.add_child(_button("무전 송신", func() -> void:
		if _update_victims.selected <= 0:
			return
		var hz: Array[String] = []
		for cb in _update_hazards:
			if cb.button_pressed:
				hz.append(cb.text)
		order_issued.emit(CommandOrder.make("update_report", [], 0, Vector3i.ZERO,
			{"victims": _update_victims.get_item_text(_update_victims.selected), "hazards": hz}))
		_close(_update)))
	box.add_child(row)


func _build_end() -> void:
	_end = _dialog()
	var box: VBoxContainer = _end.get_child(0)
	box.add_child(_label("활동 종료 선언 (SOP 113-1.1)", 22, Color("fde68a")))
	var l := _label("활동을 끝내고 디브리핑으로 넘어갑니다. 아직 연소 중이거나 찾지 못한 구조대상자가 있으면 그대로 평가됩니다.", 16, TEXT_COLOR)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(DIALOG_WIDTH - 40, 0)
	box.add_child(l)
	_end_status = _label("", 16, TEXT_COLOR)
	_end_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_status.custom_minimum_size = Vector2(DIALOG_WIDTH - 40, 0)
	box.add_child(_end_status)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)
	grid.add_child(_label("재발화 감시 (SOP 202-6.5)", 17, DIM_COLOR))
	_end_watch = OptionButton.new()
	_end_watch.focus_mode = Control.FOCUS_NONE
	_end_watch.custom_minimum_size = Vector2(320, 34)
	grid.add_child(_end_watch)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_button("취소", func() -> void: _close(_end)))
	row.add_child(_button("종료하고 디브리핑", confirm_end))
	box.add_child(row)


## 종료 창: 인원점검 상태(200-4.1)와 감시 보기를 지금 상황으로 채운다
func _rebuild_end() -> void:
	var cmd := sim.command
	var pars := cmd.safety.par_log
	var inside := 0
	for ff in sim.units.firefighters:
		if not sim.building.cell(ff.level, floori(ff.pos.x), floori(ff.pos.y)) in BuildingData.OUTDOOR:
			inside += 1
	var par_text := "인원점검: %s" % ("하지 않음 — 무전 패널의 인원점검(P)으로 먼저 확인하세요 (SOP 200-4.1)" if pars.is_empty()
		else "마지막 %s (%s)" % [_time(pars[-1].tick), "이상 없음" if pars[-1].missing == 0 and pars[-1].indoor == 0 else "건물 안 %d명, 미확인 %d명" % [pars[-1].indoor, pars[-1].missing]])
	_end_status.text = "%s\n지금 건물 안 대원: %d명" % [par_text, inside]
	_end_watch.clear()
	_end_watch.add_item("지정 안 함")
	_end_watch.add_item("관계자에게 감시 당부")
	for squad in sim.units.squads:
		if cmd.resources.on_scene(squad.id):
			_end_watch.add_item("%s 감시조" % squad.name)
	_end_watch.select(0)


static func _time(tick: int) -> String:
	var t := int(tick * SimClock.TICK_DT)
	return "%02d:%02d" % [floori(t / 60.0), t % 60]


func _row_auto(grid: GridContainer, title: String, key: String) -> void:
	grid.add_child(_label(title, 17, DIM_COLOR))
	var l := _label("", 17, TEXT_COLOR)
	grid.add_child(l)
	_auto_labels[key] = l


func _row_option(grid: GridContainer, title: String, key: String, items: Array) -> void:
	grid.add_child(_label(title, 17, DIM_COLOR))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_item(PLACEHOLDER)
	for it in items:
		ob.add_item(str(it))
	ob.select(0)
	ob.custom_minimum_size = Vector2(320, 34)
	ob.item_selected.connect(func(_i: int) -> void: _update_submit())
	grid.add_child(ob)
	_options[key] = ob


func _row_checks(grid: GridContainer, title: String, key: String, items: Array) -> void:
	grid.add_child(_label(title, 17, DIM_COLOR))
	var flow := HFlowContainer.new()
	flow.custom_minimum_size = Vector2(520, 0)
	var boxes: Array[CheckBox] = []
	for it in items:
		var cb := CheckBox.new()
		cb.text = str(it)
		cb.focus_mode = Control.FOCUS_NONE
		flow.add_child(cb)
		boxes.append(cb)
	grid.add_child(flow)
	_checks[key] = boxes


func _dialog() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(DIALOG_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.12, 0.96)
	style.border_color = Color("475569")
	style.set_border_width_all(2)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	add_child(panel)
	panel.visible = false
	return panel


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(160, 42)
	b.pressed.connect(on_press)
	return b
