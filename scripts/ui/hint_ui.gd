class_name HintUi
extends Control
## 교육 모드 힌트 카드 (data/sop/hints.json). 판단이 필요한 순간에 SOP 조항·원리·권장 행동을 보여 주고 게임을 멈춘다.
## 같은 힌트는 한 판에 한 번만 띄운다. 평가 모드에서는 꺼져 있다. 시뮬레이션 상태를 읽기만 한다 (다시 하기 결정론과 무관).

signal dialog_changed(open: bool)

const HINTS_PATH := "res://data/sop/hints.json"
const CHECK_S := 0.25

var sim: SimWorld
var enabled := false
var shown: Dictionary = {}  # hint id -> true
var _hints: Array = []
var _queue: Array[Dictionary] = []
var _panel: PanelContainer
var _title: Label
var _body: RichTextLabel
var _timer := 0.0
var _had_fire := false


func setup(p_sim: SimWorld, on: bool) -> void:
	sim = p_sim
	enabled = on
	var data: Variant = JsonData.load_file(HINTS_PATH)
	_hints = data.get("hints", []) if data is Dictionary else []
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.16, 0.97)
	style.border_color = Color("38bdf8")
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(760, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color("7dd3fc"))
	box.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.custom_minimum_size = Vector2(720, 0)
	_body.add_theme_font_size_override("normal_font_size", 17)
	box.add_child(_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var ok := Button.new()
	ok.text = "확인 (Enter)"
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Vector2(180, 40)
	ok.pressed.connect(close_hint)
	row.add_child(ok)
	box.add_child(row)
	add_child(_panel)
	_panel.visible = false


func visible_hint() -> bool:
	return _panel.visible


func close_hint() -> void:
	if not _panel.visible:
		return
	_panel.visible = false
	if _queue.is_empty():
		dialog_changed.emit(false)
	else:
		_show(_queue.pop_front())


## 종료 창을 열 때 (인원점검 없이 끝내려 하면 힌트)
func on_end_dialog() -> void:
	if enabled and sim.command.safety.par_log.is_empty():
		_trigger("end_without_par")


func _process(delta: float) -> void:
	if sim == null or not enabled or sim.ended():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_S
	_check()


func _check() -> void:
	var cmd := sim.command
	var ev := sim.events
	var t := sim.clock.tick * SimClock.TICK_DT
	if not cmd.declared() and not cmd.is_declaring() and t >= 60.0:
		_trigger("declare_delay")
	if not ev.of_type("entry_ordered").is_empty() and cmd.safety.crews_with(SafetySystem.Role.RIT).is_empty():
		_trigger("entry_without_rit")
	for e in ev.of_type("entry_factors"):
		if str(e.factors).contains("⑧"):
			_trigger("entry_with_signs")
	for type in ["rollover_sign", "backdraft_sign", "air_alarm", "mayday", "victim_found", "tactical_halt"]:
		if not ev.of_type(type).is_empty():
			_trigger(type)
	for type in ["exposure_heating", "collapse_sign", "jump_risk", "debris_zone", "shaft_heat", "sign_warning", "victim_trapped", "hydrant_out", "knockdown_reported", "end_suggested", "time_warning"]:
		if not ev.of_type(type).is_empty():
			_trigger(type)
	for p in sim.ems.patients:
		if p.stage == EmsSystem.Stage.WAITING and sim.ems.on_scene(p) and sim.clock.tick - sim.rescue.victims[p.victim_id].rescued_tick >= roundi(60.0 / SimClock.TICK_DT):
			_trigger("patient_waiting")
	if sim.gas.open and sim.gas.known(cmd.survey):
		_trigger("gas_known")
	if not ev.of_type("squad_staged").is_empty():
		_trigger("staged")
	if not ev.of_type("span_warning").is_empty():
		_trigger("span")
	var burning := sim.fire.grid.burning.size()
	if burning > 0:
		_had_fire = true
	elif _had_fire:
		_trigger("knockdown")


func _trigger(id: String) -> void:
	if shown.has(id):
		return
	shown[id] = true
	for h: Dictionary in _hints:
		if str(h.get("trigger", "")) == id:
			if _panel.visible:
				_queue.append(h)
			else:
				_show(h)
				dialog_changed.emit(true)
			return


func _show(h: Dictionary) -> void:
	_title.text = "교육 — %s" % h.get("title", "")
	_body.text = "[color=#a5b4fc]SOP %s「%s」[/color]\n[color=#94a3b8]왜? %s[/color]\n[color=#86efac]→ %s[/color]" % [
		h.get("sop", ""), h.get("text", ""), h.get("why", ""), h.get("advice", "")]
	_panel.visible = true
	_panel.reset_size()
	_panel.position = Vector2((size.x - _panel.get_combined_minimum_size().x) / 2.0, 120.0).floor()
