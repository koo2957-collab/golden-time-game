class_name ScenarioMenu
extends Control
## 시작 화면: 시나리오 목록·설명·검증 결과. 문제가 있는 시나리오는 시작할 수 없다.

signal start_requested(path: String)

const BG := Color(0.05, 0.07, 0.1)

var scenarios: Array[Dictionary] = []
var _list: ItemList
var _detail: RichTextLabel
var _start: Button
var _mode: OptionButton
var _difficulty: OptionButton
## 열려 있는 내 기록·교관 설정 화면
var overlay: Control


func _ready() -> void:
	if not GameManager.defaults_applied:
		GameManager.defaults_applied = true
		var defs: Dictionary = InstructorSettings.load_settings().get("defaults", {})
		GameManager.mode = str(defs.get("mode", GameManager.mode))
		GameManager.difficulty = str(defs.get("difficulty", GameManager.difficulty))
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
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("normal_font_size", 18)
	_detail.add_theme_font_size_override("bold_font_size", 19)
	row.add_child(_detail)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	for spec in [["캠페인", open_campaign], ["내 기록", open_history], ["교관 설정", open_instructor]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(140, 48)
		b.pressed.connect(spec[1])
		buttons.add_child(b)
	_mode = OptionButton.new()
	_mode.focus_mode = Control.FOCUS_NONE
	_mode.custom_minimum_size = Vector2(330, 48)
	_mode.add_item("평가 모드 — 힌트 없음, 디브리핑에서 공개")
	_mode.add_item("교육 모드 — 판단할 때 SOP 힌트")
	_mode.select(1 if GameManager.mode == "교육" else 0)
	buttons.add_child(_mode)
	_difficulty = OptionButton.new()
	_difficulty.focus_mode = Control.FOCUS_NONE
	_difficulty.custom_minimum_size = Vector2(300, 48)
	for d in ["자동화: 시나리오 난이도", "자동화: 입문 (문·이송 자동)", "자동화: 중급 (보고 후 대기)", "자동화: 상급 (직접 지휘)"]:
		_difficulty.add_item(d)
	_difficulty.select(maxi(0, ["", "입문", "중급", "상급"].find(GameManager.difficulty)))
	buttons.add_child(_difficulty)
	_start = Button.new()
	_start.text = "시작 (Enter)"
	_start.focus_mode = Control.FOCUS_NONE
	_start.custom_minimum_size = Vector2(220, 48)
	_start.pressed.connect(_on_start)
	buttons.add_child(_start)
	box.add_child(buttons)
	reload()


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


func open_history() -> void:
	_open(HistoryUi.new())


func open_instructor() -> void:
	var ui := InstructorUi.new()
	ui.saved.connect(reload)
	_open(ui)


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
	start_requested.emit(scenarios[sel[0]].path)
