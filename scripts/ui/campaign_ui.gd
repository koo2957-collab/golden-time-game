class_name CampaignUi
extends Control
## 캠페인 화면 (시작 화면에서 연다). 장별 진행(완료·도전 가능·잠김·준비 중)과 시나리오별 최고 등급.
## 도전 가능한 장의 시나리오를 누르면 시작 화면에서 그 시나리오를 고른다.

signal scenario_chosen(id: String)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08, 1.0)
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
	title.text = "캠페인 — 선착대장 성장 과정"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("fde68a"))
	box.add_child(title)
	var titles := {}
	for s in ScenarioLoader.list():
		titles[str(s.id)] = str(s.title)
	for p: Dictionary in Campaign.progress(PlayHistory.entries()):
		var ch: Dictionary = p.chapter
		var status: Campaign.Status = p.status
		var color: Color = {Campaign.Status.DONE: Color("86efac"), Campaign.Status.OPEN: Color("fde68a"),
			Campaign.Status.LOCKED: Color("64748b"), Campaign.Status.SOON: Color("64748b")}[status]
		var head := Label.new()
		head.text = "%s  [%s]" % [ch.title, Campaign.STATUS_NAMES[status]]
		head.add_theme_font_size_override("font_size", 21)
		head.add_theme_color_override("font_color", color)
		box.add_child(head)
		var text := Label.new()
		text.text = "%s  (통과 기준: %s 이상)" % [ch.get("text", ""), ch.get("min_grade", "C")]
		text.add_theme_color_override("font_color", Color("94a3b8"))
		box.add_child(text)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		for id: String in p.grades:
			var b := Button.new()
			var g: String = p.grades[id]
			b.text = "%s — %s" % [titles.get(id, id), "최고 " + g if g != "" else "기록 없음"]
			b.custom_minimum_size = Vector2(0, 40)
			b.focus_mode = Control.FOCUS_NONE
			b.disabled = status == Campaign.Status.LOCKED or not titles.has(id)
			b.pressed.connect(func() -> void:
				scenario_chosen.emit(id)
				queue_free())
			row.add_child(b)
		box.add_child(row)
	var note := Label.new()
	note.text = "잠긴 장도 시작 화면 목록에서 자유 연습으로 할 수 있습니다. 진행은 내 기록(결과 파일)의 최고 등급으로 계산합니다."
	note.add_theme_color_override("font_color", Color("64748b"))
	box.add_child(note)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.custom_minimum_size = Vector2(160, 44)
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(queue_free)
	box.add_child(close)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
