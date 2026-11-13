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
## 지휘권 선언에서 '지도에서 지휘소 고르기'를 골랐다 (P4-4) — 화면이 클릭을 받아 선언을 마친다
signal post_pick_requested(answers: Dictionary)

const RADIO_LINES := 6
## 오른쪽 전술상황판 폭 (기획안 9-2)
const RADIO_WIDTH := 540.0
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
## 팀 카드 (조마다 한 줄: 위치·임무·공기·마지막 보고). 클릭 = 선택, 더블클릭 = 화면 이동, 끌어다 놓기 = 임무 (R7c)
var _team_box: VBoxContainer
var _team_buttons: Dictionary = {}  # 조 id -> Button
var _team_press := -1
var _team_press_pos := Vector2.ZERO
var _team_dragging := false
## 팀 카드 클릭 (선택)·더블클릭(화면 이동)·끌기 시작·놓기
signal team_selected(crew_id: int, focus: bool)
signal team_drag_started(crew_id: int)
signal team_dropped(crew_id: int, screen_pos: Vector2)
var _dispatch: PanelContainer
## 출동 단계 (기획안 4-4): 신고 후 0~4분을 실제 약 90초로 보여 준다. 출동 지령 줄은 시간에 맞춰 차례로 나온다
var _dispatch_real := 0.0
var _dispatch_clock: Label
var _dispatch_bar: ProgressBar
var _dispatch_lines: Array[Label] = []
## 출동 지령 창의 선착 차량 배치 보기 (시나리오 approach가 있을 때)
var _placement: OptionButton
## 출동 준비: 적재 장비 체크 (R10)
var _loadout_checks: Dictionary = {}  # key -> CheckBox
var _report: PanelContainer
var _strategy: PanelContainer
var _confirm: PanelContainer
var _confirm_squads: Array[int] = []
var _report_submit: Button
## 지휘 위치 고르기 (P4-4): 0 지금 선 자리 / 1 지도에서 고르기
var _post_choice: OptionButton
var _options: Dictionary = {}  # 항목 -> OptionButton
var _checks: Dictionary = {}  # 항목 -> Array[CheckBox]
var _auto_labels: Dictionary = {}  # 항목 -> Label
var _strategy_buttons: Array[Button] = []
var _span_label: Label
var _receo_label: RichTextLabel
var _todo_label: Label
var _board_title: Label
var _board_body: VBoxContainer
## 상황판 내용이 하단 콘솔에 닿지 않게 스크롤 (R7c)
var _board_scroll: ScrollContainer
## 상황판이 내려갈 수 있는 화면 y (HUD가 하단 콘솔 위로 맞춘다. 0이면 화면 끝)
var board_bottom := 0.0
var _fold_button: Button
## 지휘관 명령 버튼 줄 (HUD 하단 콘솔이 가져간다, R6b)
var command_rows: Array[HBoxContainer] = []
## 전술상황판을 접었는가 (Tab)
var board_folded := false
## 처음 차량이 들어오는 간격 (data/command/phase_params.json arrival_gap_s)
var arrive_gap_s := 5.0
## 오른쪽 무전 기록 패널 (P10-1, Hud가 넣는다) — 알림·카드를 그 왼쪽 가운데에
var right_panel: Control
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
## 선제지시 창
var _preorder: PanelContainer
var _preorder_checks: Dictionary = {}  # key -> CheckBox
## 완진 선언 창 (노출된 곳 확인 목록)
var _all_clear: PanelContainer
var _all_clear_status: Label
var _end_warning: Label
var _end_status: Label
var _end_watch: OptionButton
var _role_crew: OptionButton
var _role_crews: Array[int] = []
var _role_list: Label


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrive_gap_s = float(sim._phase_params.value("arrival_gap_s"))
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
	_build_all_clear()
	_build_preorder()


func _process(delta: float) -> void:
	if sim == null:
		return
	_tick_dispatch(delta)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		_refresh_radio()
		# 지휘대 도착: 이양 버튼을 보이고, 처음 한 번은 브리핑 창을 연다 (R13)
		var t := sim.transfer
		if _transfer_button:
			_transfer_button.visible = t.arrived() and not t.transferred()
		if _all_clear_button:
			_all_clear_button.visible = sim.phases.knockdown_tick >= 0 and sim.phases.all_clear.is_empty()
		if t.arrived() and not t.transferred() and not _transfer_prompted and not any_dialog_open():
			_transfer_prompted = true
			open_transfer_dialog()


## 전술상황판 접기·펴기 (Tab). 접으면 제목(확인 필요 수)과 지휘 버튼만 남는다
func toggle_board() -> void:
	board_folded = not board_folded
	# 지휘 버튼은 하단 콘솔로 옮겼으므로(R6b) 접으면 제목만 남는다
	_board_scroll.visible = not board_folded
	_fold_button.text = "◀ 펴기 (Tab)" if board_folded else "▶ 접기 (Tab)"
	_radio_panel.reset_size()


## 상황판이 가리지 않는 지도 영역의 가운데 x (알림·질문 카드를 여기에 띄운다)
func map_center_x() -> float:
	# 무전 기록 패널 자리는 접거나 숨겨도 비워 둔다 (카드·알림 자리가 왔다 갔다 하지 않게)
	if right_panel:
		return (size.x - RadioLogPanel.WIDTH - 16.0) * 0.5
	if _radio_panel == null or not _radio_panel.visible:
		return size.x * 0.5
	return (size.x - _radio_panel.size.x - 16.0) * 0.5


## 확인 필요 항목: 아직 해결되지 않은 일 (기획안 9-2). 해결되면 사라진다. 지휘관이 아는 정보만 쓴다
func todo_items() -> Array[String]:
	var out: Array[String] = []
	var cmd := sim.command
	if cmd.safety.emergency():
		out.append("긴급탈출 상황 — 쓰러진 대원 구출 (RIT)")
	if sim.transfer.arrived() and not sim.transfer.transferred():
		out.append("지휘대 도착 — 지휘권 이양 브리핑 (SOP 112)")
	var waiting := sim.cards.queue.size()
	if waiting > 0:
		out.append("대원 판단 요청 %d건 대기" % waiting)
	for r: String in cmd.survey.reported_rooms:
		var room: Compartment = null
		for c in sim.fire.comps:
			if c.id == r:
				room = c
		if room and room.searched_tick < 0:
			out.append("%s — 구조대상자 제보, 미검색" % room.display_name())
	for p in sim.ems.patients:
		if p.stage == EmsSystem.Stage.WAITING and sim.ems.on_scene(p):
			out.append("%s — 처치 대기" % sim.rescue.victims[p.victim_id].label())
	if sim.gas.open and sim.gas.known(cmd.survey):
		out.append("%s 열림 — 차단 필요" % sim.gas.valve_text)
	# 물탱크 25% 이하 (운전원 경고 무전, 기획안 5-4)
	for v in sim.units.vehicles:
		if v.is_pump() and v.tank_capacity > 0.0 and v.tank_l <= v.tank_capacity * 0.25 and v.hydrant < 0:
			out.append("%s 물 %d%% — 급수원 확인" % [sim.water._name(v), roundi(v.tank_l / v.tank_capacity * 100.0)])
	if sim.water.hydrants_out.size() > 0 and sim.events.of_type("hydrant_out").size() > 0 and sim.shuttle.tankers.is_empty():
		out.append("소화전 고장 — 물탱크차 순환보수 미지정")
	for lv: int in sim.shafts.hot:
		if not sim.shafts.checked.has(lv + 1) and sim.shafts.shaft_rooms.has(lv + 1):
			out.append("%s 샤프트 확인 필요" % sim.building.floor_name(lv + 1))
	for id: int in sim.falls.warned:
		if not sim.falls.jumped.has(id) and sim.rescue.victims[id].state == Victim.State.CONSCIOUS and sim.falls.mats.is_empty():
			out.append("%s 창가 — 공기안전매트 없음" % sim.rescue.victims[id].label())
	if sim.phases.knockdown_tick >= 0 and sim.phases.all_clear.is_empty() and sim.rekindle.spotted_cells().size() > 0:
		out.append("찾은 불씨 %d곳 — 잔불정리" % sim.rekindle.spotted_cells().size())
	return out


func any_dialog_open() -> bool:
	return _dispatch.visible or _report.visible or _strategy.visible or _confirm.visible or _org.visible \
		or _witness.visible or _info.visible or _update.visible or _end.visible or _all_clear.visible or _preorder.visible


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


## 조직·지원 창 (지휘관 명령 E 지원 요청 ▸ 조직): 지원 요청, 단위대 지정·해제
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


## 현장 정보 창 (명령 카드 옆 현장 정보 버튼): 둘러보기·진술·물증 기록
func open_info_dialog() -> void:
	if any_dialog_open():
		return
	_info_label.text = _info_text()
	_open(_info)


func info_visible() -> bool:
	return _info.visible


## 열린 창을 모두 닫는다 (디브리핑으로 넘어갈 때)
func close_all() -> void:
	for p in [_dispatch, _report, _strategy, _confirm, _org, _witness, _info, _update, _end, _transfer]:
		if p:
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


## 출동 단계 시계 (실제 시간으로 진행, 시뮬레이션과 따로 — 불은 이미 계산되어 있다)
func _tick_dispatch(delta: float) -> void:
	if _dispatch_clock == null or not _dispatch.visible or sim.dispatch_s <= 0.0:
		return
	var real_total := maxf(1.0, float(sim._phase_params.value("dispatch_real_s")))
	_dispatch_real = minf(real_total, _dispatch_real + delta)
	var frac := _dispatch_real / real_total
	var call_s := roundi(sim.dispatch_s * frac)
	_dispatch_bar.value = frac
	_dispatch_clock.text = ("선착대 현장 도착 — 신고 후 %02d:%02d. 차량 배치·장비를 확인하고 현장 도착을 누르세요" if frac >= 1.0 else "출동 중 — 신고 후 %02d:%02d (선착 도착 %02d:%02d, 화재는 계속 진행 중)") % ([call_s / 60, call_s % 60] if frac >= 1.0 else [call_s / 60, call_s % 60, int(sim.dispatch_s) / 60, int(sim.dispatch_s) % 60])
	# 상황실 무전: 지령 줄이 시간에 맞춰 차례로 (첫 줄은 바로)
	for k in _dispatch_lines.size():
		_dispatch_lines[k].visible = k == 0 or frac >= float(k) / float(_dispatch_lines.size())


func dispatch_visible() -> bool:
	return _dispatch.visible


## 출동 진행률 (0~1). 출동 지령 창이 닫혔으면 -1 (도시 지도 차량 아이콘, P9-1)
func dispatch_progress() -> float:
	if _dispatch == null or not _dispatch.visible or sim.dispatch_s <= 0.0:
		return -1.0
	return clampf(_dispatch_real / maxf(1.0, float(sim._phase_params.value("dispatch_real_s"))), 0.0, 1.0)


func close_dispatch() -> void:
	_arrive()


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
	_close(_report)
	if _post_choice and _post_choice.selected == 1:
		post_pick_requested.emit(a)
		return
	order_issued.emit(CommandOrder.make("declare", [], 0, Vector3i.ZERO, a))


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
	var silent: PackedStringArray = []
	for id in sim.command.safety.par_no_response:
		var c := sim.units.get_crew(id)
		silent.append("%s %d조 (%s)" % [sim.units.squads[c.squad_id].name, c.number, sim.building.floor_name(c.leader.level)])
	_par_alert.text = "⚠ 인원 점검 무응답: %s — 긴급탈출 상황 선포·RIT 투입을 판단하세요" % ", ".join(silent)
	_par_alert.visible = not silent.is_empty()
	var bottom := board_bottom if board_bottom > 0.0 else size.y - 16.0
	var room := maxf(160.0, bottom - 64.0 - 60.0)
	_board_scroll.custom_minimum_size = Vector2(RADIO_WIDTH, minf(_board_body.get_combined_minimum_size().y, room))
	_radio_panel.reset_size()
	_radio_panel.position = Vector2(size.x - _radio_panel.size.x - 16.0, 64.0)
	var radio := sim.command.radio
	var lines: PackedStringArray = ["무전 기록 (최근 순, 지휘망)" + ("   대기 %d건" % radio.queue.size() if not radio.queue.is_empty() else "")]
	if radio.current:
		lines.append("▶ 송신 중 %d%%  %s" % [roundi(radio.progress() * 100.0), radio.current.text()])
	# 무전과 답한 질문 카드("질문 → 내 답")를 시간 순으로 섞어 최근 것부터
	var items: Array = []
	var start := maxi(0, radio.history.size() - RADIO_LINES)
	for i in range(start, radio.history.size()):
		var m := radio.history[i]
		items.append([m.end_tick, m.text()])
	for e in sim.events.of_type("card_answered").slice(-RADIO_LINES):
		items.append([int(e.tick), "질문: %s → %s" % [e.title, e.option]])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for it in items.slice(0, RADIO_LINES):
		var t := int(int(it[0]) * SimClock.TICK_DT)
		lines.append("%02d:%02d  %s" % [floori(t / 60.0), t % 60, it[1]])
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
	_refresh_team_cards()
	var cmd := sim.command
	var n := cmd.direct_count()
	var span := "직접 지휘 %d (적정 %d, 한계 %d)" % [n, cmd.org.span_ideal, cmd.org.span_max]
	if n > cmd.org.span_ideal:
		span += " — 초과: 명령 %.0f초 지연. 단위대를 지정하세요 (지휘관 명령 E ▸ 조직)" % cmd.span_delay_s()
	if cmd.held_count() > 0:
		span += "  · 실행 대기 명령 %d건" % cmd.held_count()
	_span_label.text = span
	_survey_label.text = _survey_text()
	_receo_label.text = _receo_text()
	var todo := todo_items()
	_todo_label.text = "확인 필요\n" + "\n".join(todo.map(func(t: String) -> String: return "• " + t)) if not todo.is_empty() else ""
	_board_title.text = "전술상황판%s" % ("  · 확인 필요 %d" % todo.size() if not todo.is_empty() else "")
	_span_label.add_theme_color_override("font_color", WARN_COLOR if n > cmd.org.span_ideal else DIM_COLOR)


## 진입 현황: 출동대별 진입 허가, 건물 안 조와 공기 잔량
func _entry_text() -> String:
	var cmd := sim.command
	var lines: PackedStringArray = ["전략: %s%s" % [CommandSystem.STRATEGY_NAMES[cmd.strategy],
		"" if cmd.declared() else "  (지휘권 미선언 — 지휘관 명령 Q)"]]
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
		# 조별 위치·공기는 아래 팀 카드에 (R7c)
		lines.append("%s: %s%s" % [squad.name, state, "  · 내부 %d조" % inside.size() if not inside.is_empty() else ""])
	for u in res.upcoming(sim.clock.tick):
		var eta := roundi(u.eta_s)
		lines.append("%s: %s 출동 중 — %s" % [u.name, u.reason,
			"약 %d분 %02d초 뒤 도착" % [eta / 60, eta % 60] if eta > 0 else "대기 장소 자리 기다림"])
	return "\n".join(lines)


## (숨김) 예전 오른쪽 상황판. P10-1에서 무전 기록은 RadioLogPanel, 요약·팀 카드·확인 필요는 TacticalBoard로 옮겼다. 여기서 만든 위젯을 그쪽이 가져다 쓴다. 접기
func _build_radio_panel() -> void:
	_radio_panel = PanelContainer.new()
	_radio_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio_panel.position = Vector2(16, 64)
	_radio_panel.custom_minimum_size = Vector2(RADIO_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.12, 0.72)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	_radio_panel.add_theme_stylebox_override("panel", style)
	var outer := VBoxContainer.new()
	_radio_panel.add_child(outer)
	var head := HBoxContainer.new()
	_board_title = _label("전술상황판", 17, Color("fdba74"))
	_board_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_board_title)
	_fold_button = _button("▶ 접기 (Tab)", toggle_board)
	head.add_child(_fold_button)
	outer.add_child(head)
	# 긴급 줄: 인원 점검 무응답 조 (P10-2). 접어도 보인다 — 정식 고정줄은 P10-1
	_par_alert = _label("", 16, Color("fca5a5"))
	_par_alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_par_alert.custom_minimum_size = Vector2(RADIO_WIDTH - 16, 0)
	_par_alert.visible = false
	outer.add_child(_par_alert)
	var box := VBoxContainer.new()
	_board_body = box
	_board_scroll = ScrollContainer.new()
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_board_scroll.add_child(box)
	outer.add_child(_board_scroll)
	_receo_label = RichTextLabel.new()
	_receo_label.bbcode_enabled = true
	_receo_label.fit_content = true
	_receo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_receo_label.custom_minimum_size = Vector2(RADIO_WIDTH - 16, 0)
	_receo_label.add_theme_font_size_override("normal_font_size", 15)
	box.add_child(_receo_label)
	box.add_child(_label("팀 현황", 15, Color("fdba74")))
	_entry_label = _label("", 14, TEXT_COLOR)
	box.add_child(_entry_label)
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", 2)
	box.add_child(_team_box)
	_todo_label = _label("", 15, WARN_COLOR)
	_todo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_todo_label.custom_minimum_size = Vector2(RADIO_WIDTH - 16, 0)
	box.add_child(_todo_label)
	box.add_child(HSeparator.new())
	_radio_label = _label("", 14, RADIO_COLOR)
	_radio_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_label.custom_minimum_size = Vector2(RADIO_WIDTH - 16, 0)
	box.add_child(_radio_label)
	_span_label = _label("", 15, DIM_COLOR)
	_span_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_span_label.custom_minimum_size = Vector2(RADIO_WIDTH - 16, 0)
	box.add_child(_span_label)
	_survey_label = _label("", 15, TEXT_COLOR)
	_survey_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_survey_label.custom_minimum_size = Vector2(RADIO_WIDTH - 16, 0)
	box.add_child(_survey_label)
	# 명령 카드(Q W E R A S)에 없는 지휘관 기능 (P10-2): 정보는 늘, 완진 선언은 초진 뒤, 지휘권 이양은 지휘대 도착 뒤
	var row := HBoxContainer.new()
	var info_button := _button("현장 정보", open_info_dialog)
	var walk_button := _button("360° 둘러보기", func() -> void: order_issued.emit(CommandOrder.make("survey")))
	_all_clear_button = _button("완진 선언", open_all_clear)
	_all_clear_button.visible = false
	var end := _button("활동 종료", open_end_confirm)
	# 지휘대가 도착하면 보이는 지휘권 이양 버튼 (SOP 112, R13)
	_transfer_button = _button("지휘권 이양", open_transfer_dialog)
	_transfer_button.add_theme_color_override("font_color", Color("fde68a"))
	_transfer_button.visible = false
	for b in [info_button, walk_button, _all_clear_button, end, _transfer_button]:
		b.custom_minimum_size = Vector2(118, 30)
		b.add_theme_font_size_override("font_size", 13)
		row.add_child(b)
	box.add_child(row)
	command_rows.append(row)
	add_child(_radio_panel)


func _build_dispatch() -> void:
	_dispatch = _dialog()
	var box: VBoxContainer = _dispatch.get_child(0)
	var d := sim.command.dispatch
	box.add_child(_label(str(d.get("title", "출동 지령")), 24, Color("fca5a5")))
	_dispatch_clock = _label("출동 중 — 신고 후 00:00", 18, Color("fde68a"))
	box.add_child(_dispatch_clock)
	_dispatch_bar = ProgressBar.new()
	_dispatch_bar.show_percentage = false
	_dispatch_bar.custom_minimum_size = Vector2(DIALOG_WIDTH - 40, 8)
	_dispatch_bar.max_value = 1.0
	box.add_child(_dispatch_bar)
	_dispatch_lines.clear()
	for line in d.get("lines", []):
		var l := _label("상황실: " + str(line), 18, TEXT_COLOR)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(DIALOG_WIDTH - 40, 0)
		box.add_child(l)
		_dispatch_lines.append(l)
	box.add_child(_label("도착하면 지휘권을 선언하고 최초 상황보고를 하십시오 (지휘관 명령 Q 전략 변경). 건물 안 임무를 받은 조는 입구에서 진입 허가를 무전으로 요청합니다.", 16, DIM_COLOR))
	var opts := Placement.options(sim)
	if not opts.is_empty():
		box.add_child(_label("선착 차량 배치 (SOP 200-3.1.1) — 화염·낙하물 피해, 후착대·특수차 공간, 소화전을 생각해 고르세요", 17, Color("fde68a")))
		_placement = OptionButton.new()
		_placement.focus_mode = Control.FOCUS_NONE
		for o: Dictionary in opts:
			_placement.add_item(str(o.get("name", "")))
		_placement.select(Placement.default_index(sim))
		box.add_child(_placement)
		var desc := _label("", 15, DIM_COLOR)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(DIALOG_WIDTH - 40, 0)
		desc.text = str(opts[_placement.selected].get("text", ""))
		_placement.item_selected.connect(func(i: int) -> void: desc.text = str(opts[i].get("text", "")))
		box.add_child(desc)
	_build_loadout(box)
	_build_preassign(box)
	var go := _button("현장 도착 (Enter)", _arrive)
	box.add_child(go)


## 현장 도착: 고른 배치를 명령으로 내린다 (기록·다시 하기 대상)
func _arrive() -> void:
	if not _loadout_checks.is_empty() and sim.loadout.is_empty() and sim.clock.tick <= Placement.MAX_TICK:
		order_issued.emit(CommandOrder.make("loadout", [], 0, Vector3i.ZERO, {"items": loadout_selection()}))
	if _placement and sim.command.placement.is_empty() and sim.clock.tick <= Placement.MAX_TICK:
		order_issued.emit(CommandOrder.make("placement", [], _placement.selected))
	# 도착 후 임무 미리 정하기 (P9-1): 정한 조는 차에서 내리자마자 움직인다
	var pre := preassign_selection()
	if not pre.is_empty():
		order_issued.emit(CommandOrder.make("preassign", [], 0, Vector3i.ZERO, {"tasks": pre}))
	# 차량이 지도 가장자리에서 한 대씩 들어온다 (펌프차 먼저, 기획안 6-1·P4-1)
	order_issued.emit(CommandOrder.make("arrive", [], 0, Vector3i.ZERO, {"gap_s": arrive_gap_s}))
	_close(_dispatch)


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
	# 지휘 위치 = 현장지휘소 (SOP 101-2.1⑤, 104). 선언하면 고정지휘 (P4-4)
	grid.add_child(_label("⑤ 지휘 위치 (지휘소)", 17, DIM_COLOR))
	_post_choice = OptionButton.new()
	_post_choice.focus_mode = Control.FOCUS_NONE
	_post_choice.add_item("지금 선 자리")
	_post_choice.add_item("지도에서 고르기 (송신 뒤 클릭)")
	_post_choice.select(0)
	_post_choice.custom_minimum_size = Vector2(320, 34)
	grid.add_child(_post_choice)
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
		exposure_text = "%s 연소 확대됨" % ex.label() if not ex.ignited.is_empty() else "%s 가열 %d%%" % [ex.label(), roundi(r * 100.0)]
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
	lines.append("[color=#94a3b8]구역: %s[/color]" % zones_text())
	return "\n".join(lines)


## 상황판 외부 구역 한 줄 (P10-2 ⓑ): "안전구역 ✓ · 환자 집결지 – · 진입통제선 – · 분류소 설치 중"
func zones_text() -> String:
	var z: ZoneSystem = sim.zones
	var parts: PackedStringArray = ["안전구역 %s" % ("✓" if z.has_safe() else "–")]
	if z.triage.x >= 0:
		parts.append("분류소 ✓ (집결지 대신)")
	else:
		parts.append("환자 집결지 %s" % ("✓" if z.casualty.x >= 0 else "–"))
		if not z.triage_setup.is_empty():
			parts.append("분류소 설치 중")
	parts.append("진입통제선 %s" % ("✓" if z.line.size() == 2 else "–"))
	return " · ".join(parts)


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
	_end_warning = _label("", 16, WARN_COLOR)
	_end_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_warning.custom_minimum_size = Vector2(DIALOG_WIDTH - 40, 0)
	box.add_child(_end_warning)
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


## 활동 종료 선언 경고 (기획안 8-3, P11-1): 완진 전 · 연소 중으로 본 구역 · 발화층·직상층 등 미검색 구역.
## 지휘관이 아는 정보만 쓴다. 비어 있으면 작전 완료로 끝난다
func end_warnings() -> PackedStringArray:
	var out: PackedStringArray = []
	if sim.phases.all_clear.is_empty():
		out.append("⚠ 아직 완진 선언 전입니다. 그대로 종료하면 지금 상태로 평가합니다 (완진 선언 → 인원점검 → 감시 지정 → 종료가 원칙).")
	var burning: Array[Compartment] = sim.seen_burning_rooms()
	if not burning.is_empty():
		out.append("⚠ 연소 중으로 본 곳 %d곳: %s" % [burning.size(), _room_list(burning)])
	var unsearched: Array[Compartment] = sim.unsearched_rooms()
	if not unsearched.is_empty():
		out.append("⚠ 검색하지 않은 곳 %d곳: %s — 남은 구조대상자는 미구조로 처리됩니다 (기획안 8-3)" % [unsearched.size(), _room_list(unsearched)])
	# 구조·인계·인원점검 (2026-11-13: 작전 완료 조건)
	for gap in sim.completion_gaps():
		if gap.contains("구조") or gap.contains("인원점검"):
			out.append("⚠ %s" % gap)
	if not out.is_empty():
		out.append("→ 지금 종료하면 '조기 종료'로 기록됩니다. 모두 마치면 '작전 완료'입니다.")
	return out


func _room_list(rooms: Array[Compartment]) -> String:
	var names: PackedStringArray = []
	for c in rooms.slice(0, 5):
		names.append(c.display_name())
	return ", ".join(names) + (" 외" if rooms.size() > 5 else "")


## 종료 창: 인원점검 상태(200-4.1)와 감시 보기를 지금 상황으로 채운다
func _rebuild_end() -> void:
	var cmd := sim.command
	var pars := cmd.safety.par_log
	var inside := 0
	for ff in sim.units.firefighters:
		if not sim.building.cell(ff.level, floori(ff.pos.x), floori(ff.pos.y)) in BuildingData.OUTDOOR:
			inside += 1
	var par_text := "인원점검: %s" % ("하지 않음 — 지휘관 명령 R 인원 점검으로 먼저 확인하세요 (SOP 200-4.1)" if pars.is_empty()
		else "마지막 %s (%s)" % [_time(pars[-1].tick), "이상 없음" if pars[-1].missing == 0 and pars[-1].indoor == 0 else "건물 안 %d명, 미확인 %d명" % [pars[-1].indoor, pars[-1].missing]])
	_end_status.text = "%s\n지금 건물 안 대원: %d명" % [par_text, inside]
	_end_warning.text = "\n".join(end_warnings())
	_end_watch.clear()
	_end_watch.add_item("지정 안 함")
	_end_watch.add_item("관계자에게 감시 당부")
	for squad in sim.units.squads:
		if cmd.resources.on_scene(squad.id):
			_end_watch.add_item("%s 감시조" % squad.name)
	_end_watch.select(0)


## 완진 선언 창: 지휘관이 알 수 있는 것만으로 노출된 곳 확인 목록을 보여 준다 (소방전술 I 8단계 ⑥)
func open_all_clear() -> void:
	_close(_strategy)
	if any_dialog_open() or not sim.phases.all_clear.is_empty():
		return
	_all_clear_status.text = all_clear_checklist()
	_open(_all_clear)


func all_clear_checklist() -> String:
	var ph := sim.phases
	var lines: PackedStringArray = []
	lines.append("%s 초진 보고 %s" % ["✓" if ph.knockdown_tick >= 0 else "✗", _time(ph.knockdown_tick) if ph.knockdown_tick >= 0 else "없음"])
	var origin_level := -1
	for e in sim.events.of_type("ignition"):
		var c := sim.fire.compartment_at(int(e.cell[2]), int(e.cell[0]), int(e.cell[1]))
		if c:
			origin_level = c.level
			break
	for pair in [[origin_level, "발화층"], [origin_level + 1, "직상층"]]:
		var lv: int = pair[0]
		if not sim.building.has_level(lv):
			continue
		var total := 0
		var done := 0
		for c in ph.search_targets():
			if c.level == lv:
				total += 1
				if ph.secondary.has(c.index):
					done += 1
		lines.append("%s %s(%s) 2차 검색 %d/%d" % ["✓" if done == total else "✗", pair[1], sim.building.floor_name(lv), done, total])
	var seen := 0
	for i in sim.fire.grid.burning:
		if not sim.perception.enabled or sim.perception.seen_burning[i] == 1:
			seen += 1
	lines.append("%s 보이는 불 %s" % ["✓" if seen == 0 else "✗", "없음" if seen == 0 else "%d곳" % seen])
	var embers := sim.rekindle.spotted_cells().size()
	lines.append("%s 찾은 불씨 %s · 잔불정리 %d회" % ["✓" if embers == 0 else "✗", "없음" if embers == 0 else "%d곳 남음" % embers, sim.events.of_type("overhaul_done").size()])
	return "\n".join(lines)


func _build_all_clear() -> void:
	_all_clear = _dialog()
	var box: VBoxContainer = _all_clear.get_child(0)
	box.add_child(_label("완진 선언 (소방전술 I 8단계 ⑥, SOP 202-6)", 22, Color("fde68a")))
	var l := _label("발화층·직상층·각 진압 구역 등 노출된 모든 곳을 확인했으면 완진을 선언합니다. 아직 불이 남아 있어도 선언은 할 수 있지만 그대로 평가됩니다. 선언 뒤에는 인원 점검(지휘관 명령 R)과 활동 종료(재발화 감시 지정)로 마무리합니다.", 16, TEXT_COLOR)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(DIALOG_WIDTH - 40, 0)
	box.add_child(l)
	_all_clear_status = _label("", 17, TEXT_COLOR)
	box.add_child(_all_clear_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_button("취소", func() -> void: _close(_all_clear)))
	row.add_child(_button("완진 선언 (무전)", confirm_all_clear))
	box.add_child(row)


## 선제지시 창: 자주 묻는 상황을 미리 정해 두면 그 질문 카드가 뜨지 않는다 (기획안 3-3 ⑤)
func open_preorder() -> void:
	_close(_strategy)
	if any_dialog_open():
		return
	for key: String in _preorder_checks:
		_preorder_checks[key].set_pressed_no_signal(sim.cards.preorders.has(key))
	_open(_preorder)


func set_preorder(key: String, on: bool) -> void:
	order_issued.emit(CommandOrder.make("preorder", [], 1 if on else 0, Vector3i.ZERO, {"key": key}))


func _build_preorder() -> void:
	_preorder = _dialog()
	var box: VBoxContainer = _preorder.get_child(0)
	box.add_child(_label("선제지시 — 미리 정해 두면 대원이 묻지 않고 그대로 합니다", 22, Color("fde68a")))
	var data: Variant = JsonData.load_file(SimWorld.CARDS_PATH)
	for p: Dictionary in (data.get("preorders", []) if data is Dictionary else []):
		var cb := CheckBox.new()
		cb.text = "%s (SOP %s)" % [p.label, p.sop]
		cb.focus_mode = Control.FOCUS_NONE
		var key := str(p.key)
		cb.toggled.connect(func(on: bool) -> void: set_preorder(key, on))
		box.add_child(cb)
		_preorder_checks[key] = cb
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_button("닫기", func() -> void: _close(_preorder)))
	box.add_child(row)


func confirm_all_clear() -> void:
	order_issued.emit(CommandOrder.make("all_clear"))
	_close(_all_clear)


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


# --- 팀 카드 (기획안 9-2 ②, R7c) ---

const TEAM_REPORT_STALE_S := 90.0


## 현장에 있는 조마다 한 줄. 출동대가 새로 도착하면 카드를 더한다
func _refresh_team_cards() -> void:
	if _team_box == null:
		return
	for c in sim.units.crews:
		var on_scene := not sim.command.resources.is_en_route(c.squad_id)
		if on_scene and not _team_buttons.has(c.id):
			var b := Button.new()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 13)
			b.custom_minimum_size = Vector2(RADIO_WIDTH - 16, 0)
			b.mouse_filter = Control.MOUSE_FILTER_STOP
			b.tooltip_text = "클릭: 선택 · 더블클릭: 화면 이동 · 끌어서 지도의 방·층에 놓기: 임무와 임무 조건"
			b.gui_input.connect(_on_team_input.bind(c.id, b))
			_team_box.add_child(b)
			_team_buttons[c.id] = b
		if _team_buttons.has(c.id):
			var b: Button = _team_buttons[c.id]
			b.text = team_text(c.id)
			b.add_theme_color_override("font_color", _team_color(c.id))


## "진압1 1조 · 1층 거실 · 층 진압 (1층 거실) · 공기 72% · 보고 12초 전" (판단 요청 대기 중이면 앞에 ?)
func team_text(crew_id: int) -> String:
	var c := sim.units.get_crew(crew_id)
	var squad := sim.units.squads[c.squad_id]
	var name := "%s %d조" % [squad.name, c.number]
	var inside := sim.command.interior.crew_inside(crew_id)
	var room := sim.fire.compartment_at(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y))
	var where := (room.display_name() if room else sim.building.floor_name(c.leader.level)) if inside else "밖"
	var task := sim.tactical.mission_text(crew_id)
	var parts: PackedStringArray = [name, where, task if task != "" else "임무 없음"]
	if c.leader.incapacitated:
		parts[2] = "쓰러짐"
	if inside:
		var air := 1.0
		var need := 0.0
		for ff in c.members():
			air = minf(air, ff.air_ratio())
			need = maxf(need, ff.exit_air_l / maxf(1.0, ff.air_capacity))
		# 잔압(bar)과 출구까지 필요한 공기 (기획안 5-6, R9)
		parts.append("잔압 %dbar (출구 %dbar)" % [roundi(air * 300.0), maxi(1, roundi(need * 300.0))])
		var last := int(sim.command.last_report_tick.get(name, -1))
		parts.append("보고 %d초 전" % roundi((sim.clock.tick - last) * SimClock.TICK_DT) if last >= 0 else "보고 없음")
	var cond := sim.tactical.condition_text(crew_id)
	var waiting := sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.crew_id == crew_id)
	return ("? " if waiting else "") + " · ".join(parts) + ("\n    조건: " + cond if cond != "" else "")


## 쓰러짐·공기 부족 = 빨강, 보고가 오래됨 = 노랑 (기획안 9-2)
func _team_color(crew_id: int) -> Color:
	var c := sim.units.get_crew(crew_id)
	if c.leader.incapacitated:
		return Color("f87171")
	if not sim.command.interior.crew_inside(crew_id):
		return DIM_COLOR
	var air := 1.0
	for ff in c.members():
		air = minf(air, ff.air_ratio())
	if air < 0.3:
		return Color("f87171")
	var name := "%s %d조" % [sim.units.squads[c.squad_id].name, c.number]
	var last := int(sim.command.last_report_tick.get(name, -1))
	if last < 0 or (sim.clock.tick - last) * SimClock.TICK_DT > TEAM_REPORT_STALE_S:
		return WARN_COLOR
	return TEXT_COLOR


func _on_team_input(event: InputEvent, crew_id: int, b: Button) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_team_press = crew_id
			_team_press_pos = event.global_position
			_team_dragging = false
			if event.double_click:
				team_selected.emit(crew_id, true)
				_team_press = -1
		elif _team_press == crew_id:
			if _team_dragging:
				team_dropped.emit(crew_id, event.global_position)
			elif b.get_global_rect().has_point(event.global_position):
				team_selected.emit(crew_id, false)
			_team_press = -1
			_team_dragging = false
	elif event is InputEventMouseMotion and _team_press == crew_id and not _team_dragging:
		if event.global_position.distance_to(_team_press_pos) > 10.0:
			_team_dragging = true
			team_drag_started.emit(crew_id)


# --- 출동 준비: 적재 장비 선택 (기획안 P9, R10) ---

func _build_loadout(box: VBoxContainer) -> void:
	var data: Variant = JsonData.load_file("res://data/units/equipment.json")
	if not data is Dictionary:
		return
	var cap := int(data.get("capacity", 3))
	box.add_child(_label("출동 준비 — 기본 장비 외에 %d개까지 더 싣는다 (현장 상황을 생각해 고르세요)" % cap, 17, Color("fde68a")))
	var grid := GridContainer.new()
	grid.columns = 2
	for it: Dictionary in data.get("items", []):
		var cb := CheckBox.new()
		cb.text = str(it.get("label", ""))
		cb.tooltip_text = "%s (SOP %s)" % [it.get("note", ""), it.get("sop", "")]
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 15)
		cb.toggled.connect(func(_on: bool) -> void: _limit_loadout(cap))
		grid.add_child(cb)
		_loadout_checks[str(it.key)] = cb
	box.add_child(grid)


## 도착 후 임무 미리 정하기 (기획안 4-4 '도착 후 임무 미리 정하기', P9-1): 처음 현장에 오는 조마다
const PREASSIGN_KINDS := [["", "도착 후 지시 기다림"], ["attack", "화점진압 (관창)"], ["search", "인명검색"], ["office", "방재실·관리사무소 연락 (도면·수신반)"], ["officer", "현장안전담당"]]
var _preassign: Dictionary = {}  # 조 id → OptionButton


func _build_preassign(box: VBoxContainer) -> void:
	var crews: Array = sim.units.crews.filter(func(c: Crew) -> bool: return sim.command.resources.on_scene(c.squad_id) and not sim.ems.is_ems_crew(c.id))
	if crews.is_empty():
		return
	box.add_child(_label("도착 후 임무 미리 정하기 — 정한 조는 차에서 내리자마자 움직입니다 (건물 안 임무는 발화층 층 단위, 진입 허가는 입구에서)", 17, Color("fde68a")))
	var grid := GridContainer.new()
	grid.columns = 2
	for c: Crew in crews:
		grid.add_child(_label("%s %d조" % [sim.units.squads[c.squad_id].name, c.number], 15, TEXT_COLOR))
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		for k: Array in PREASSIGN_KINDS:
			if k[0] == "office" and sim.plan.office.is_empty():
				continue
			ob.add_item(str(k[1]))
			ob.set_item_metadata(ob.item_count - 1, str(k[0]))
		grid.add_child(ob)
		_preassign[c.id] = ob
	box.add_child(grid)


## {조 id(문자열): 임무 키} — 정하지 않은 조는 빠진다
func preassign_selection() -> Dictionary:
	var out := {}
	for id: int in _preassign:
		var ob: OptionButton = _preassign[id]
		var k := str(ob.get_item_metadata(ob.selected)) if ob.selected >= 0 else ""
		if k != "":
			out[str(id)] = k
	return out


## 정한 개수를 넘으면 나머지 체크를 막는다
func _limit_loadout(cap: int) -> void:
	var n := loadout_selection().size()
	for k: String in _loadout_checks:
		var cb: CheckBox = _loadout_checks[k]
		cb.disabled = n >= cap and not cb.button_pressed


func loadout_selection() -> Array:
	var out: Array = []
	for k: String in _loadout_checks:
		if (_loadout_checks[k] as CheckBox).button_pressed:
			out.append(k)
	return out


# --- 지휘권 이양 (SOP 112, R13) ---

var _transfer: PanelContainer
var _transfer_button: Button
## 초진 뒤에 보이는 완진 선언 버튼
var _all_clear_button: Button
## 무전 패널 맨 위 긴급 줄 (인원 점검 무응답)
var _par_alert: Label
var _transfer_prompted := false
var _transfer_opts: Dictionary = {}  # 항목 -> OptionButton


## 지휘권 이양 브리핑 창: 항목마다 지금 아는 사실을 고른다 (보기는 판 시드로 섞는다)
func open_transfer_dialog() -> void:
	var t := sim.transfer
	if not t.arrived() or t.transferred() or any_dialog_open():
		return
	if _transfer:
		_transfer.queue_free()
	_transfer = _dialog()
	var box: VBoxContainer = _transfer.get_child(0)
	box.add_child(_label("지휘권 이양 브리핑 (SOP 112) — %s 도착" % str(t.unit.get("name", "지휘대")), 22, Color("fde68a")))
	box.add_child(_label("항목마다 지금까지 확인한 사실을 고르세요. 모르는 것은 '확인 중'이 맞습니다.", 15, DIM_COLOR))
	var opts := t.options()
	var rng := RandomNumberGenerator.new()
	rng.seed = sim.rng_seed + 112
	_transfer_opts.clear()
	var grid := GridContainer.new()
	grid.columns = 2
	for k: String in CommandTransfer.ITEMS:
		grid.add_child(_label(CommandTransfer.ITEM_NAMES[k], 16, TEXT_COLOR))
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.custom_minimum_size = Vector2(DIALOG_WIDTH - 220, 0)
		var list: Array = (opts[k] as Array).duplicate()
		for i in range(list.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = list[i]
			list[i] = list[j]
			list[j] = tmp
		for o in list:
			ob.add_item(str(o))
		grid.add_child(ob)
		_transfer_opts[k] = ob
	box.add_child(grid)
	var row := HBoxContainer.new()
	row.add_child(_button("브리핑하고 이양", confirm_transfer))
	row.add_child(_button("나중에", func() -> void: _close(_transfer)))
	box.add_child(row)
	_open(_transfer)


func transfer_visible() -> bool:
	return _transfer != null and _transfer.visible


## 고른 내용으로 이양 (CommandOrder "transfer" — 다시 하기 기록)
func confirm_transfer() -> void:
	var answers := {}
	for k: String in _transfer_opts:
		var ob: OptionButton = _transfer_opts[k]
		answers[k] = ob.get_item_text(ob.selected) if ob.selected >= 0 else ""
	order_issued.emit(CommandOrder.make("transfer", [], 0, Vector3i.ZERO, answers))
	_close(_transfer)


## 조작 점검용: 항목마다 첫 번째(사실) 보기를 고른다
func pick_transfer_truth() -> void:
	var truth := sim.transfer.options()
	for k: String in _transfer_opts:
		var ob: OptionButton = _transfer_opts[k]
		for i in ob.item_count:
			if ob.get_item_text(i) == str(truth[k][0]):
				ob.select(i)
