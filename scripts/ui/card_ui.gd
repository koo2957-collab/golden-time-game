class_name CardUi
extends Control
## 질문 카드 화면 (기획안 3-3, P7). 화면 위쪽 가운데에 반투명하게 한 장씩 띄운다. 게임은 멈추지 않는다.
##   맨 앞 카드: 질문한 조(공기 잔량·층), 질문, 남은 시간 막대, 번호 붙은 선택 버튼 (클릭 또는 1~4)
##   뒤에서 기다리는 카드는 '+N 대기'로 표시. 정답·오답은 게임 중에 보이지 않는다.
##   답은 order_issued로 CommandOrder "card_answer"를 내보낸다 (기록·다시 하기)

signal order_issued(order: CommandOrder)

const WIDTH := 560.0
const URGENCY_COLORS := {"긴급": Color("ef4444"), "중요": Color("facc15"), "일반": Color("e2e8f0")}

var sim: SimWorld
var _panel: PanelContainer
var _style: StyleBoxFlat
var _head: Label
var _text: Label
var _bar: ProgressBar
var _buttons: Array[Button] = []
var _more: Label
var _shown_uid := -1


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	_style.set_border_width_all(3)
	_style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", _style)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_head = Label.new()
	_head.add_theme_font_size_override("font_size", 15)
	box.add_child(_head)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(WIDTH - 24, 0)
	_text.add_theme_font_size_override("font_size", 18)
	box.add_child(_text)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	box.add_child(_bar)
	for i in 4:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 34)
		b.pressed.connect(choose.bind(i))
		box.add_child(b)
		_buttons.append(b)
	_more = Label.new()
	_more.add_theme_color_override("font_color", Color("94a3b8"))
	box.add_child(_more)
	add_child(_panel)
	_panel.visible = false


func _process(_delta: float) -> void:
	if sim == null:
		return
	var c := sim.cards.active()
	_panel.visible = c != null and not sim.ended()
	if c == null:
		_shown_uid = -1
		return
	# 오른쪽 상황판이 가리지 않는 지도 영역 가운데에
	var hud := get_parent() as Hud
	var cx := hud.command_ui.map_center_x() if hud and hud.command_ui else size.x * 0.5
	_panel.position = Vector2(cx - WIDTH * 0.5, 96.0)
	if c.uid != _shown_uid:
		_shown_uid = c.uid
		_fill(c)
	var total := float(c.deadline_tick - c.asked_tick)
	_bar.value = 100.0 * float(c.deadline_tick - sim.clock.tick) / maxf(1.0, total)
	var waiting := sim.cards.queue.size() - 1
	_more.text = "+%d 대기" % waiting if waiting > 0 else ""
	if _more.visible != (waiting > 0):
		_more.visible = waiting > 0
		_panel.reset_size()


func _fill(c: CardSystem.Card) -> void:
	var color: Color = URGENCY_COLORS.get(c.urgency, Color.WHITE)
	_style.border_color = color
	var crew := sim.units.get_crew(c.crew_id)
	var info := ""
	if crew:
		var air := minf(crew.leader.air_ratio(), crew.partner.air_ratio() if crew.partner else 1.0)
		info = " · %s · 공기 %d%%" % [sim.building.floor_name(crew.leader.level), roundi(air * 100.0)]
	_head.text = "[%s] %s%s" % [c.urgency, str(c.spec.get("title", "")), info]
	_head.add_theme_color_override("font_color", color)
	_text.text = c.text
	for i in _buttons.size():
		var b := _buttons[i]
		b.visible = i < c.options.size()
		if b.visible:
			b.text = "%d. %s" % [i + 1, str(c.options[i].text)]
	_panel.reset_size()


## 맨 앞 카드에 답한다 (화면에 보인 순서 index)
func choose(index: int) -> void:
	var c := sim.cards.active()
	if c == null or index >= c.options.size():
		return
	order_issued.emit(CommandOrder.make("card_answer", [], index, Vector3i.ZERO, {"uid": c.uid}))


func _unhandled_key_input(event: InputEvent) -> void:
	if not _panel.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if k >= KEY_1 and k <= KEY_4:
		get_viewport().set_input_as_handled()
		choose(k - KEY_1)
