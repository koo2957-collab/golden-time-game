class_name TutorialUi
extends Control
## 튜토리얼 안내판 (시나리오 tutorial: 단계 파일). 화면 오른쪽 위에 지금 할 일과 SOP 근거를 보여 주고,
## 조건이 이루어지면 다음 단계로 넘어간다. 게임을 멈추지 않는다. 시뮬레이션은 읽기만 한다.
## 단계 조건(check) 종류는 _done()에 있다.

const CHECK_S := 0.25
const WIDTH := 470.0

var sim: SimWorld
var selection: SelectionController
var steps: Array = []
var index := 0
var finished := false
var _panel: PanelContainer
var _label: RichTextLabel
var _timer := 0.0
var _had_fire := false


func setup(p_sim: SimWorld, p_selection: SelectionController, path: String) -> void:
	sim = p_sim
	selection = p_selection
	var data: Variant = JsonData.load_file(path)
	steps = data.get("steps", []) if data is Dictionary else []
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.12, 0.1, 0.98)
	style.border_color = Color("34d399")
	style.set_border_width_all(2)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.custom_minimum_size = Vector2(WIDTH - 28, 0)
	_label.add_theme_font_size_override("normal_font_size", 16)
	_panel.add_child(_label)
	add_child(_panel)
	visible = not steps.is_empty()
	_refresh()


func current() -> Dictionary:
	return steps[index] if index < steps.size() else {}


func _process(delta: float) -> void:
	if sim == null or finished or steps.is_empty():
		return
	_panel.position = Vector2(size.x - WIDTH - 16.0, 64.0)
	_timer += delta
	if _timer < CHECK_S:
		return
	_timer = 0.0
	check()


## 조건을 확인하고 이루어진 단계만큼 넘어간다
func check() -> void:
	if finished or steps.is_empty():
		return
	if sim.fire.grid.burning.size() > 0:
		_had_fire = true
	var advanced := false
	# 앞 단계보다 먼저 해 둔 것은 바로 넘어간다
	while index < steps.size() and _done(steps[index]):
		index += 1
		advanced = true
	if index >= steps.size():
		finished = true
	if advanced:
		_refresh()


## 단계 조건. 시뮬레이션 상태·기록과 현재 선택만 본다
func _done(step: Dictionary) -> bool:
	var ev := sim.events
	var cmd := sim.command
	match str(step.get("check", "")):
		"time":
			return sim.clock.tick * SimClock.TICK_DT >= float(step.get("s", 5))
		"declared":
			return cmd.declared()
		"selected":
			return not selection.selected.is_empty()
		"faces":
			return cmd.survey.faces_seen.size() >= int(step.get("count", 2))
		"rit":
			return not cmd.safety.crews_with(SafetySystem.Role.RIT).is_empty()
		"event":
			return not ev.of_type(str(step.get("event", ""))).is_empty()
		"knockdown":
			return _had_fire and sim.fire.grid.burning.size() == 0
		"ended":
			return sim.ended_tick >= 0
	return false


func _refresh() -> void:
	if steps.is_empty():
		return
	var lines: PackedStringArray = []
	if finished:
		lines.append("[font_size=20][color=#6ee7b7]튜토리얼 완료[/color][/font_size]")
		lines.append("기본 지휘 흐름을 모두 해 보았습니다. 디브리핑에서 판단 근거를 확인하고, 시작 화면에서 주택화재 ①부터 도전하세요.")
		_label.text = "\n".join(lines)
		return
	var s: Dictionary = steps[index]
	lines.append("[color=#94a3b8]튜토리얼 %d / %d[/color]" % [index + 1, steps.size()])
	lines.append("[font_size=20][color=#6ee7b7]%s[/color][/font_size]" % s.get("title", ""))
	lines.append(str(s.get("text", "")))
	if s.has("keys"):
		lines.append("[color=#fde68a]조작: %s[/color]" % s.keys)
	if s.has("sop"):
		lines.append("[color=#a5b4fc]SOP %s[/color] [color=#94a3b8]%s[/color]" % [s.sop, s.get("why", "")])
	var done: PackedStringArray = []
	for i in index:
		done.append("✓ %s" % steps[i].get("title", ""))
	if not done.is_empty():
		lines.append("[color=#475569]%s[/color]" % "  ".join(done.slice(maxi(0, done.size() - 3))))
	_label.text = "\n".join(lines)
