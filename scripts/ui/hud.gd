class_name Hud
extends Control
## 화면 정보: 게임 시계·배속·모드, 층 탭, 선택 정보, 명령 패널, 조작 안내,
## 열화상 범례, 개발용 화재 정보 패널.

## 명령 패널 버튼을 눌렀을 때 (id: "hose" / "straight" / "fog" / "stop")
signal command_pressed(id: String)

const DEBUG_REFRESH_S := 0.25
const SELECTION_REFRESH_S := 0.25
## 화면 위쪽에 알림으로 띄우는 사건 (지휘관이 현장에서 바로 알 수 있는 장비 상황만)
const NOTICE_TYPES: Array[String] = [
	"hydrant_connected", "hydrant_disconnected", "supply_connected", "hose_laid", "hose_too_short",
	"hose_limit", "tank_empty", "vehicle_locked", "vehicle_blocked", "spray_unreachable",
	"door_opened", "door_closed", "door_forced", "door_cannot_close", "door_unreachable",
	"heat_blocked", "heat_retreat", "air_alarm", "scba_swapped", "ff_down",
]
const NOTICE_SECONDS := 4.0
const NOTICE_MAX := 3
const DEBUG_EVENT_LINES := 8
const DEBUG_COLUMNS: Array[String] = ["구획", "단계", "상부℃", "하부℃", "연기층m", "O2%", "가스%", "열방출kW", "시야m", "FO℃"]

@onready var clock_label: Label = $ClockPanel/ClockLabel
@onready var floor_tabs: HBoxContainer = $FloorTabs
@onready var selection_label: Label = $SelectionPanel/SelectionLabel

var sim: SimWorld
var mode_text := ""
var _floor_buttons: Dictionary = {}  # level -> Button
var _legend: Control
var _debug_panel: PanelContainer
var _debug_cells: Array[Label] = []
var _debug_events: Label
var _debug_timer := 0.0
var _crew_ids: Array[int] = []
var _vehicle_ids: Array[int] = []
var _selection_timer := 0.0
var _command_panel: HBoxContainer
var _command_buttons: Dictionary = {}  # id -> Button
var _notice_label: Label
var _notices: Array[Array] = []  # [문장, 남은 시간(실제 초)]
var _events_seen := 0


func setup(p_sim: SimWorld, on_floor_selected: Callable) -> void:
	sim = p_sim
	var group := ButtonGroup.new()
	for level in sim.building.levels():
		var button := Button.new()
		button.text = sim.building.floor_name(level)
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(80, 40)
		button.add_theme_color_override("font_pressed_color", PlanStyle.SELECTION)
		button.add_theme_color_override("font_hover_pressed_color", PlanStyle.SELECTION)
		button.pressed.connect(on_floor_selected.bind(level))
		floor_tabs.add_child(button)
		_floor_buttons[level] = button
	_build_legend()
	_build_debug_panel()
	_build_command_panel()
	_build_notice_label()
	EventBus.selection_changed.connect(_on_selection_changed)
	EventBus.vehicle_selection_changed.connect(_on_vehicle_selection_changed)
	EventBus.view_floor_changed.connect(_on_view_floor_changed)
	_on_selection_changed([])


func set_thermal_visible(on: bool) -> void:
	_legend.visible = on


func is_debug_visible() -> bool:
	return _debug_panel.visible


func set_debug_visible(on: bool) -> void:
	_debug_panel.visible = on
	_debug_timer = 0.0


func _process(delta: float) -> void:
	if sim == null:
		return
	var t := int(sim.clock.elapsed_seconds())
	var text := "경과 %02d:%02d   ×%d" % [floori(t / 60.0), t % 60, int(sim.clock.speed)]
	if sim.clock.paused:
		text += "   일시정지"
	if mode_text != "":
		text += "   [%s]" % mode_text
	clock_label.text = text
	_update_notices(delta)
	_selection_timer -= delta
	if _selection_timer <= 0.0:
		_selection_timer = SELECTION_REFRESH_S
		_refresh_selection()
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


func _on_vehicle_selection_changed(vehicle_ids: Array[int]) -> void:
	_vehicle_ids = vehicle_ids
	_refresh_selection()


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
	selection_label.text = "\n".join(lines) if not lines.is_empty() else "선택 없음"
	_command_panel.visible = not _crew_ids.is_empty()
	_command_buttons["stop"].disabled = not any_flowing


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
	var task := sim.doors.task_of_crew(crew.id)
	if task:
		var what := "문 파괴" if task.opening.locked else ("문 개방" if task.open else "문 폐쇄")
		parts.append("%s %d/%d초%s" % [what, int(task.progress), int(task.required), " (인원 부족)" if task.waiting_people else ""])
	return "\n    " + " · ".join(parts)


func _vehicle_line(v: Vehicle) -> String:
	var squad := sim.units.squads[v.squad_id]
	var line := "[%s] %s — 물 %s / %sL" % [squad.name, v.type, _thousands(v.tank_l), _thousands(v.tank_capacity)]
	if v.hydrant >= 0:
		line += " · 소화전 연결"
	if v.supply_to >= 0:
		line += " · 급수 중"
	if v.is_pump():
		line += " · 수관 %d" % sim.water.hoses_of_vehicle(v.id).size()
		line += "\n    소화전 우클릭: 점령"
	elif v.transfer_lpm > 0.0:
		line += "\n    펌프차 우클릭: 급수 · 소화전 우클릭: 점령"
	return line


static func _thousands(value: float) -> String:
	var s := str(int(value))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _update_notices(delta: float) -> void:
	var entries := sim.events.entries
	while _events_seen < entries.size():
		var e := entries[_events_seen]
		_events_seen += 1
		if e.type in NOTICE_TYPES:
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
	_command_panel = HBoxContainer.new()
	_command_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_command_panel.offset_left = -860
	_command_panel.offset_right = -16
	_command_panel.offset_top = -112
	_command_panel.offset_bottom = -64
	_command_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_command_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_command_panel.alignment = BoxContainer.ALIGNMENT_END
	for spec in [["door", "문 (E)"], ["hose", "수관 연장 (H)"], ["straight", "직사 방수 (A)"], ["fog", "분무 방수 (S)"], ["stop", "방수 중지 (D)"]]:
		var b := Button.new()
		b.text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(160, 44)
		b.pressed.connect(func() -> void: command_pressed.emit(spec[0]))
		_command_panel.add_child(b)
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
