class_name HistoryUi
extends Control
## 내 기록 화면 (시작 화면에서 연다). 지난 판의 등급·점수, 축별 성장(처음 3판 → 최근 3판),
## 익명 집계 내보내기. 다른 사람과의 순위 비교는 없다 (SOP 113-3.1.6).

const AXIS_NAMES := {"safety": "대원 안전", "rescue": "인명구조", "property": "재산 보호", "fire": "화재 안정화", "command": "지휘 절차"}

var _body: RichTextLabel
var _status: Label
var _list: Array[Dictionary] = []


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
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "내 기록 — 성장 확인용 (순위 비교 없음, SOP 113-3.1.6)"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("fde68a"))
	box.add_child(title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 17)
	box.add_child(_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("94a3b8"))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status)
	var export := Button.new()
	export.text = "익명 집계 내보내기 (교관 제출용)"
	export.custom_minimum_size = Vector2(320, 46)
	export.focus_mode = Control.FOCUS_NONE
	export.pressed.connect(_export)
	row.add_child(export)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.custom_minimum_size = Vector2(160, 46)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(queue_free)
	row.add_child(close)
	box.add_child(row)
	refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()


func refresh() -> void:
	_list = PlayHistory.entries()
	_body.text = text_for(_list)
	_status.text = "결과 폴더: %s" % ProjectSettings.globalize_path(Evaluator.REPORT_DIR)


static func text_for(list: Array[Dictionary]) -> String:
	if list.is_empty():
		return "아직 끝낸 판이 없습니다. 활동을 종료하면 결과가 여기에 쌓입니다."
	var lines: PackedStringArray = []
	var weekly := InstructorSettings.weekly()
	if not weekly.is_empty():
		var done := list.any(func(e: Dictionary) -> bool: return e.scenario_id == str(weekly.get("scenario", "")))
		lines.append("[color=#fbbf24]★ 이번 주 훈련: %s — %s[/color]%s" % [weekly.get("scenario", ""), weekly.get("note", ""), "  (완료)" if done else ""])
		lines.append("")
	lines.append("[b]축별 성장 (처음 3판 평균 → 최근 3판 평균)[/b]")
	var g := PlayHistory.growth(list)
	for id: String in AXIS_NAMES:
		if not g.has(id):
			continue
		var pair: Array = g[id]
		var diff: float = pair[1] - pair[0]
		var color := "86efac" if diff > 0.02 else ("fca5a5" if diff < -0.02 else "e2e8f0")
		lines.append("  %s  %d → [color=#%s]%d[/color]" % [AXIS_NAMES[id], roundi(pair[0] * 100), color, roundi(pair[1] * 100)])
	lines.append("")
	lines.append("[b]지난 판 (최근 순)[/b]")
	for i in range(list.size() - 1, maxi(-1, list.size() - 21), -1):
		var e: Dictionary = list[i]
		var tags := " · ".join(PackedStringArray([e.mode, e.difficulty].filter(func(x: String) -> bool: return x != "")))
		if e.get("incomplete", false):
			lines.append("  %s  %s%s  [color=#fbbf24]미완료[/color] (중간에 나감 — 성장·집계에 넣지 않음)" % [e.saved_at, e.title, "  [%s]" % tags if tags != "" else ""])
			continue
		lines.append("  %s  %s%s  등급 [b]%s[/b] (%.1f점)" % [e.saved_at, e.title, "  [%s]" % tags if tags != "" else "", e.grade, e.points])
		if not e.weak.is_empty():
			lines.append("      [color=#94a3b8]고칠 점: %s[/color]" % ", ".join(PackedStringArray(e.weak.slice(0, 2))))
	return "\n".join(lines)


func _export() -> void:
	var path := PlayHistory.export_aggregate(_list)
	_status.text = "내보냄: %s (이름·개인 기록 없이 시나리오별 통계만)" % ProjectSettings.globalize_path(path) if path != "" else "내보내기 실패"
