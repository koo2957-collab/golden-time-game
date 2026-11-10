class_name ScenarioMenu
extends Control
## 시작 화면: 시나리오 목록·설명·검증 결과. 문제가 있는 시나리오는 시작할 수 없다.

signal start_requested(path: String)
## 게임 종료 버튼 (확인 창은 main이 띄운다, 기획안 8-4)
signal quit_requested

const BG := Color(0.05, 0.07, 0.1)

var scenarios: Array[Dictionary] = []
var _list: ItemList
var _detail: RichTextLabel
var _start: Button
var _mode: OptionButton
var _difficulty: OptionButton
var _realism: OptionButton
## 열려 있는 내 기록·교관 설정 화면
var overlay: Control
var _profile_label: Label
var _profile_panel: PanelContainer
var _profile_name: LineEdit
var _profile_unit: LineEdit


func _ready() -> void:
	if not GameManager.defaults_applied:
		GameManager.defaults_applied = true
		var defs: Dictionary = InstructorSettings.load_settings().get("defaults", {})
		GameManager.mode = str(defs.get("mode", GameManager.mode))
		GameManager.difficulty = str(defs.get("difficulty", GameManager.difficulty))
		GameManager.realism = str(defs.get("realism", GameManager.realism))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Fire Commander — 현장지휘 표준작전절차 훈련"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("fde68a"))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "시나리오를 고르세요. 추가 시나리오 폴더: %s" % ProjectSettings.globalize_path("user://scenarios")
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color("94a3b8"))
	box.add_child(sub)
	# 교육생 프로필 (기획안 8-4 화면 흐름: 타이틀 → 프로필 → 스테이지 선택). 결과 파일·CSV에만 쓴다
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 12)
	_profile_label = Label.new()
	_profile_label.add_theme_font_size_override("font_size", 17)
	_profile_label.add_theme_color_override("font_color", Color("e2e8f0"))
	prow.add_child(_profile_label)
	var pb := Button.new()
	pb.text = "프로필 바꾸기"
	pb.focus_mode = Control.FOCUS_NONE
	pb.pressed.connect(open_profile)
	prow.add_child(pb)
	box.add_child(prow)
	_refresh_profile()
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(560, 0)
	_list.add_theme_font_size_override("font_size", 19)
	_list.item_selected.connect(_show)
	_list.item_activated.connect(func(_i: int) -> void: _on_start())
	row.add_child(_list)
	# 오른쪽: 설명 → 선택(평가/교육·난이도·자동화) → 큰 시작 버튼 (상용 게임처럼 고른 것 바로 아래)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("normal_font_size", 18)
	_detail.add_theme_font_size_override("bold_font_size", 19)
	right.add_child(_detail)
	var opts := HFlowContainer.new()
	opts.add_theme_constant_override("h_separation", 12)
	opts.add_theme_constant_override("v_separation", 8)
	right.add_child(opts)
	_mode = OptionButton.new()
	_mode.focus_mode = Control.FOCUS_NONE
	_mode.custom_minimum_size = Vector2(330, 48)
	_mode.add_item("평가 모드 — 힌트 없음, 디브리핑에서 공개")
	_mode.add_item("교육 모드 — 판단할 때 SOP 힌트")
	_mode.select(1 if GameManager.mode == "교육" else 0)
	opts.add_child(_mode)
	_realism = OptionButton.new()
	_realism.focus_mode = Control.FOCUS_NONE
	_realism.custom_minimum_size = Vector2(250, 48)
	for r in ["난이도: 훈련 (카드 시간 2배·일시정지)", "난이도: 실전 (1배속 고정)", "난이도: 악조건 (강풍·지연·소화전 고장)"]:
		_realism.add_item(r)
	_realism.select(maxi(0, ["훈련", "실전", "악조건"].find(GameManager.realism)))
	_realism.tooltip_text = "실전·악조건은 시간이 멈추지 않습니다 (창·힌트가 떠도 진행, 배속 없음). 출동 지령을 읽는 동안만 멈춥니다."
	opts.add_child(_realism)
	_difficulty = OptionButton.new()
	_difficulty.focus_mode = Control.FOCUS_NONE
	_difficulty.custom_minimum_size = Vector2(300, 48)
	for d in ["자동화: 시나리오 난이도", "자동화: 입문 (문·이송 자동)", "자동화: 중급 (보고 후 대기)", "자동화: 상급 (직접 지휘)"]:
		_difficulty.add_item(d)
	_difficulty.select(maxi(0, ["", "입문", "중급", "상급"].find(GameManager.difficulty)))
	opts.add_child(_difficulty)
	_start = Button.new()
	_start.text = "▶  시작 (Enter)"
	_start.focus_mode = Control.FOCUS_NONE
	_start.custom_minimum_size = Vector2(320, 64)
	_start.size_flags_horizontal = Control.SIZE_SHRINK_END
	_start.add_theme_font_size_override("font_size", 24)
	var go := StyleBoxFlat.new()
	go.bg_color = Color("b91c1c")
	go.set_corner_radius_all(8)
	go.set_content_margin_all(10)
	_start.add_theme_stylebox_override("normal", go)
	var go_hover: StyleBoxFlat = go.duplicate()
	go_hover.bg_color = Color("dc2626")
	_start.add_theme_stylebox_override("hover", go_hover)
	_start.add_theme_stylebox_override("pressed", go_hover)
	_start.add_theme_color_override("font_color", Color.WHITE)
	_start.add_theme_color_override("font_hover_color", Color.WHITE)
	_start.pressed.connect(_on_start)
	right.add_child(_start)
	# 아래 줄: 부가 메뉴
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 12)
	for spec in [["캠페인", open_campaign], ["내 기록", open_history], ["교관 설정", open_instructor], ["시나리오 편집기", open_editor], ["화면 설정", open_display], ["자료 출처", open_credits], ["게임 종료", func() -> void: quit_requested.emit()]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(140, 44)
		b.pressed.connect(spec[1])
		buttons.add_child(b)
	box.add_child(buttons)
	reload()


## 자료 출처 (P15): data/credits.json
func open_credits() -> void:
	var d: Variant = JsonData.load_file("res://data/credits.json")
	var lines: Array = d.get("lines", []) if d is Dictionary else []
	var dlg := AcceptDialog.new()
	dlg.title = "자료 출처"
	dlg.dialog_text = "
".join(lines)
	dlg.ok_button_text = "닫기"
	add_child(dlg)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _refresh_profile() -> void:
	var p := Profile.load_profile()
	_profile_label.text = "교육생: %s" % (Profile.text(p) if not p.is_empty() and Profile.text(p) != "" else "(이름·소속을 넣어 주세요 — 결과 파일에 들어갑니다)")


## 프로필 입력 창 (처음 실행하면 자동으로 뜬다)
func open_profile() -> void:
	if _profile_panel == null:
		_profile_panel = PanelContainer.new()
		_profile_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_profile_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_profile_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		_profile_panel.custom_minimum_size = Vector2(460, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		_profile_panel.add_child(v)
		var t := Label.new()
		t.text = "교육생 프로필"
		t.add_theme_font_size_override("font_size", 24)
		v.add_child(t)
		var n := Label.new()
		n.text = "이름과 소속은 결과 파일·결과 CSV(교관 제출용)에만 들어갑니다. 순위는 만들지 않습니다."
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size = Vector2(420, 0)
		v.add_child(n)
		_profile_name = LineEdit.new()
		_profile_name.placeholder_text = "이름"
		v.add_child(_profile_name)
		_profile_unit = LineEdit.new()
		_profile_unit.placeholder_text = "소속 (예: ○○119안전센터)"
		v.add_child(_profile_unit)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		var cancel := Button.new()
		cancel.text = "나중에"
		cancel.pressed.connect(func() -> void: _profile_panel.visible = false)
		row.add_child(cancel)
		var ok := Button.new()
		ok.text = "저장"
		ok.pressed.connect(func() -> void:
			Profile.save_profile(_profile_name.text, _profile_unit.text)
			_profile_panel.visible = false
			_refresh_profile())
		row.add_child(ok)
		v.add_child(row)
		add_child(_profile_panel)
	var p := Profile.load_profile()
	_profile_name.text = str(p.get("name", ""))
	_profile_unit.text = str(p.get("unit", ""))
	_profile_panel.visible = true


func reload() -> void:
	scenarios = ScenarioLoader.list()
	_list.clear()
	var weekly := str(InstructorSettings.weekly().get("scenario", ""))
	for s in scenarios:
		var meta: Dictionary = s.meta
		var label := "%s%s%s" % ["★ 이번 주 훈련 — " if str(s.id) == weekly and weekly != "" else "", s.title, "  [%s]" % meta.difficulty if meta.has("difficulty") else ""]
		if not s.errors.is_empty():
			label += "  ⚠ 오류"
		if s.source == "추가":
			label += "  (추가)"
		_list.add_item(label)
	if not scenarios.is_empty():
		var first := 0
		for i in scenarios.size():
			if scenarios[i].errors.is_empty():
				first = i
				break
		select(first)


func select(i: int) -> void:
	_list.select(i)
	_show(i)


func selected_path() -> String:
	var sel := _list.get_selected_items()
	return scenarios[sel[0]].path if not sel.is_empty() else ""


func open_campaign() -> void:
	var ui := CampaignUi.new()
	ui.scenario_chosen.connect(select_id)
	_open(ui)


## 시나리오 id로 목록에서 고른다
func select_id(id: String) -> void:
	for i in scenarios.size():
		if str(scenarios[i].id) == id:
			select(i)


func open_editor() -> void:
	var ui := ScenarioEditorUi.new()
	ui.saved.connect(reload)
	_open(ui)


func open_history() -> void:
	_open(HistoryUi.new())


func open_instructor() -> void:
	var ui := InstructorUi.new()
	ui.saved.connect(reload)
	_open(ui)


func open_display() -> void:
	_open(DisplayUi.new())


func _open(ui: Control) -> void:
	if is_instance_valid(overlay):
		overlay.queue_free()
	overlay = ui
	add_child(ui)


func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(overlay) and not overlay.is_queued_for_deletion():
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_on_start()


func _show(i: int) -> void:
	var s := scenarios[i]
	var m: Dictionary = s.meta
	var lines: PackedStringArray = ["[font_size=26][color=#fde68a]%s[/color][/font_size]" % s.title]
	var facts: PackedStringArray = []
	for pair in [["sop", "대응 SOP"], ["difficulty", "난이도"], ["role", "역할"], ["estimated_min", "예상 시간(분)"]]:
		if m.has(pair[0]):
			var value: Variant = m[pair[0]]
			facts.append("%s %s" % [pair[1], str(int(value)) if value is float else str(value)])
	if not facts.is_empty():
		lines.append("[color=#94a3b8]%s[/color]" % "  ·  ".join(facts))
	var weekly := InstructorSettings.weekly()
	if str(weekly.get("scenario", "")) == str(s.id) and str(s.id) != "":
		lines.append("[color=#fbbf24]★ 이번 주 훈련%s[/color]" % (" — " + str(weekly.note) if str(weekly.get("note", "")) != "" else ""))
	if m.has("summary"):
		lines.append("")
		lines.append(str(m.summary))
	if not s.objectives.is_empty():
		lines.append("")
		lines.append("[b]학습 목표[/b]")
		for o in s.objectives:
			lines.append("  • %s" % o)
	if not s.errors.is_empty():
		lines.append("")
		lines.append("[color=#fca5a5][b]시나리오 오류 — 고친 뒤 다시 실행하세요[/b][/color]")
		for e in s.errors:
			lines.append("[color=#fca5a5]  • %s[/color]" % e)
	lines.append("")
	lines.append("[color=#64748b]%s[/color]" % s.path)
	_detail.text = "\n".join(lines)
	_start.disabled = not s.errors.is_empty()


func _on_start() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty() or not scenarios[sel[0]].errors.is_empty():
		return
	GameManager.mode = "교육" if _mode.selected == 1 else "평가"
	GameManager.difficulty = ["", "입문", "중급", "상급"][_difficulty.selected]
	GameManager.realism = ["훈련", "실전", "악조건"][_realism.selected]
	start_requested.emit(scenarios[sel[0]].path)
