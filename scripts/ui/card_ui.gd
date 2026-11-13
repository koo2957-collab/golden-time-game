class_name CardUi
extends Control
## 무전 장면 (2026-11-14 사용자 결정, 프로스트펑크의 사건 창 방식 — 예전: 화면 위쪽의 질문 카드, P7).
## 대원·상황실이 지휘관에게 판단을 물어 오면 화면 가운데에 '말하는 사람 그림 + 무전 내용 + 선택지'를 띄운다.
##   훈련 방식: 장면이 떠 있는 동안 현장 시간이 멈춘다(World가 scene_changed를 받아 멈춤). 고르면 등급과 SOP 조항을 한 줄로 알려 준다
##   실전·악조건: 멈추지 않고 남은 시간 막대가 줄어든다. 등급은 끝난 뒤 평가 화면에서만 본다
##   뒤에서 기다리는 무전은 '+N 대기'. 답은 order_issued로 CommandOrder "card_answer"를 내보낸다 (기록·다시 하기)
## 누가 말하는지: 묻는 조의 조장(이름·계급) + 출동대 종류별 그림(data/art.json portraits). 조가 아니면 카드의 asker 글자

signal order_issued(order: CommandOrder)
## 장면이 뜨거나 닫힘 (World가 훈련 방식에서 시간을 멈추고 푼다)
signal scene_changed(open: bool)

const WIDTH := 760.0
const PORTRAIT := 168.0
const URGENCY_COLORS := {"긴급": Color("ef4444"), "중요": Color("facc15"), "일반": Color("e2e8f0")}
## 고른 직후 알려 주는 한 줄의 색 (훈련 방식)
const GRADE_COLORS := {"최선": Color("4ade80"), "허용": Color("facc15"), "오답": Color("fb923c"), "치명": Color("f87171")}
## 고른 직후 한 줄이 떠 있는 실제 시간 (초) — 화면 설정값
const FEEDBACK_S := 4.0

var sim: SimWorld
## 장면이 뜨면 시간이 멈추는 방식인가 (World가 준다: 훈련 = true). 없으면 멈추지 않는 것으로 본다
var pauses := Callable()
var _shade: ColorRect
var _panel: PanelContainer
var _style: StyleBoxFlat
var _portrait: TextureRect
var _badge: Label
var _who: Label
var _head: Label
var _text: Label
var _bar: ProgressBar
var _buttons: Array[Button] = []
var _more: Label
var _feedback: Label
var _feedback_box: PanelContainer
var _feedback_left := 0.0
var _shown_uid := -1
## 방금 답한 카드 — 시간이 멈춰 있으면 시뮬레이션이 답을 처리할 때까지 대기열에 남아 있으므로, 그동안은 닫힌 것으로 본다
var _answered_uid := -1
var _open := false
## 동시 진입 허가 (P4-5): 진입 허가를 묻는 출동대가 둘 이상이면 진입 카드 아래에
var _all: Button
static var _textures: Dictionary = {}


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 뒤 화면을 어둡게 (시간이 멈추는 방식에서만 보인다)
	_shade = ColorRect.new()
	_shade.color = Color(0.0, 0.0, 0.0, 0.45)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_shade.visible = false
	add_child(_shade)
	_panel = PanelContainer.new()
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	_style.set_border_width_all(3)
	_style.set_corner_radius_all(6)
	_style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", _style)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_panel.add_child(row)
	# 왼쪽: 말하는 사람
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(PORTRAIT, 0)
	row.add_child(left)
	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.13, 0.17, 0.24, 1.0)
	fs.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", fs)
	frame.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	left.add_child(frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	frame.add_child(_portrait)
	_badge = Label.new()
	_badge.text = "무전"
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 30)
	_badge.add_theme_color_override("font_color", Color("94a3b8"))
	frame.add_child(_badge)
	_who = Label.new()
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_who.custom_minimum_size = Vector2(PORTRAIT, 0)
	_who.add_theme_font_size_override("font_size", 15)
	left.add_child(_who)
	# 오른쪽: 무전 내용과 선택지
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	_head = Label.new()
	_head.add_theme_font_size_override("font_size", 14)
	box.add_child(_head)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(WIDTH - PORTRAIT - 60, 0)
	_text.add_theme_font_size_override("font_size", 20)
	box.add_child(_text)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	box.add_child(_bar)
	for i in 4:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(choose.bind(i))
		box.add_child(b)
		_buttons.append(b)
	_all = Button.new()
	_all.focus_mode = Control.FOCUS_NONE
	_all.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_all.custom_minimum_size = Vector2(0, 36)
	_all.add_theme_color_override("font_color", Color("fde68a"))
	_all.pressed.connect(approve_all)
	_all.visible = false
	box.add_child(_all)
	_more = Label.new()
	_more.add_theme_color_override("font_color", Color("94a3b8"))
	box.add_child(_more)
	add_child(_panel)
	_panel.visible = false
	# 고른 직후 한 줄 (훈련 방식): 화면 위쪽 가운데에 잠깐
	_feedback_box = PanelContainer.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.04, 0.05, 0.08, 0.9)
	fb.set_corner_radius_all(6)
	fb.set_content_margin_all(10)
	fb.content_margin_left = 18
	fb.content_margin_right = 18
	_feedback_box.add_theme_stylebox_override("panel", fb)
	_feedback_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_box.visible = false
	_feedback = Label.new()
	_feedback.add_theme_font_size_override("font_size", 20)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_box.add_child(_feedback)
	add_child(_feedback_box)


## 이 방식에서는 장면이 뜨면 시간이 멈추는가 (훈련)
func pausing() -> bool:
	return pauses.is_valid() and bool(pauses.call())


## 지금 보여 줄 무전 (방금 답해 아직 처리되지 않은 것은 뺀다)
func current() -> CardSystem.Card:
	var c := sim.cards.active()
	if c == null:
		_answered_uid = -1
		return null
	return null if c.uid == _answered_uid else c


## 장면이 떠 있는가 (화면 점검·World)
func scene_open() -> bool:
	return _open


func _process(delta: float) -> void:
	if sim == null:
		return
	if _feedback_left > 0.0:
		_feedback_left -= delta
		_feedback_box.modulate.a = clampf(_feedback_left, 0.0, 1.0)
		_feedback_box.position = Vector2(_map_center_x() - _feedback_box.size.x * 0.5, 150.0)
		if _feedback_left <= 0.0:
			_feedback_box.visible = false
	var c := current()
	var open := c != null and not sim.ended()
	if open != _open:
		_open = open
		scene_changed.emit(open)
	_panel.visible = open
	_shade.visible = open and pausing()
	if not open:
		_shown_uid = -1
		return
	if c.uid != _shown_uid:
		_shown_uid = c.uid
		_fill(c)
	# 지도 영역 가운데에 (오른쪽 상황판이 가리지 않는 곳)
	_panel.position = Vector2(_map_center_x() - _panel.size.x * 0.5, maxf(70.0, (size.y - _panel.size.y) * 0.42))
	var total := float(c.deadline_tick - c.asked_tick)
	_bar.visible = not pausing()
	_bar.value = 100.0 * float(c.deadline_tick - sim.clock.tick) / maxf(1.0, total)
	var waiting := sim.cards.queue.size() - 1
	var entries := sim.command.waiting_squads().size()
	var show_all := c.id == CommandOrder.ENTRY_CARD and entries >= 2
	if _all.visible != show_all:
		_all.visible = show_all
		_panel.reset_size()
	if show_all:
		_all.text = "5. 진입구 앞에서 기다리는 %d개 출동대 모두 동시 진입 허가" % entries
	_more.text = "+%d 대기" % waiting if waiting > 0 else ""
	if _more.visible != (waiting > 0):
		_more.visible = waiting > 0
		_panel.reset_size()


func _map_center_x() -> float:
	var hud := get_parent() as Hud
	return hud.command_ui.map_center_x() if hud and hud.command_ui else size.x * 0.5


## 말하는 사람: {name: 이름 줄, where: 층·공기, portrait: 그림 경로(없으면 "")}
static func speaker(p_sim: SimWorld, c: CardSystem.Card) -> Dictionary:
	var portraits: Dictionary = SpriteArt.config().get("portraits", {})
	var crew := p_sim.units.get_crew(c.crew_id)
	if crew == null:
		var asker := str(c.spec.get("asker", "무전"))
		return {"name": asker, "where": "", "portrait": str(portraits.get(asker, ""))}
	var squad := p_sim.units.squad_of_crew(crew.id)
	var ff := crew.leader
	var air := minf(ff.air_ratio(), crew.partner.air_ratio() if crew.partner else 1.0)
	return {
		"name": "%s %d조\n%s %s" % [squad.name if squad else "", crew.number, ff.rank, ff.name],
		"where": "%s · 공기 %d%%" % [p_sim.building.floor_name(ff.level), roundi(air * 100.0)],
		"portrait": str(portraits.get(squad.type if squad else "", portraits.get("default", ""))),
	}


func _fill(c: CardSystem.Card) -> void:
	var color: Color = URGENCY_COLORS.get(c.urgency, Color.WHITE)
	_style.border_color = color
	var sp := speaker(sim, c)
	_who.text = str(sp.name)
	var tex := _texture(str(sp.portrait))
	_portrait.texture = tex
	_portrait.visible = tex != null
	_badge.visible = tex == null
	_head.text = "%s%s" % [str(c.spec.get("title", "")), "  ·  " + str(sp.where) if str(sp.where) != "" else ""]
	_head.add_theme_color_override("font_color", color)
	_text.text = "“%s”" % spoken(c.text)
	for i in _buttons.size():
		var b := _buttons[i]
		b.visible = i < c.options.size()
		if b.visible:
			b.text = "%d. %s" % [i + 1, str(c.options[i].text)]
	_panel.reset_size()


## 무전 내용에서 맨 앞의 "진압1 1조: " 같은 이름표를 뗀다 — 누가 말하는지는 그림과 이름 줄이 보여 준다
static func spoken(text: String) -> String:
	var i := text.find(": ")
	return text.substr(i + 2) if i > 0 and i <= 14 and not text.substr(0, i).contains(".") else text


static func _texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path]


## 동시 진입 허가 (5번 키)
func approve_all() -> void:
	if sim.command.waiting_squads().size() >= 2:
		var c := current()
		if c:
			_answered_uid = c.uid
		order_issued.emit(CommandOrder.make("entry_all"))


## 지금 무전에 답한다 (화면에 보인 순서 index)
func choose(index: int) -> void:
	var c := current()
	if c == null or index >= c.options.size():
		return
	if pausing():
		_show_feedback(c, index)
	_answered_uid = c.uid
	order_issued.emit(CommandOrder.make("card_answer", [], index, Vector3i.ZERO, {"uid": c.uid}))


## 훈련 방식: 고른 직후 등급과 SOP 조항을 한 줄로 (2026-11-14 사용자 결정). 실전에서는 부르지 않는다
func _show_feedback(c: CardSystem.Card, index: int) -> void:
	_feedback.text = feedback_text(c, index)
	_feedback.add_theme_color_override("font_color", GRADE_COLORS.get(str(c.options[index].get("grade", "")), Color.WHITE))
	_feedback_box.modulate.a = 1.0
	_feedback_box.visible = true
	_feedback_box.reset_size()
	_feedback_left = FEEDBACK_S


## 등급 — 근거 조항 (예: "최선 — SOP 102-4.1"). 진입 허가 요청은 그때 상황으로 본 까닭을 붙인다 (예: "오답 — 출동대 3개인데 RIT 미지정 (SSG 9)")
static func feedback_text(c: CardSystem.Card, index: int) -> String:
	var grade := str(c.options[index].get("grade", ""))
	var reason := str(c.ctx.get("reason", ""))
	if c.id == CommandOrder.ENTRY_CARD and reason != "":
		return "%s — %s" % [grade, reason]
	var refs: Array = c.spec.get("sop_ref", [])
	var ref := ", ".join(PackedStringArray(refs)) if not refs.is_empty() else ""
	return grade if ref == "" else "%s — %s" % [grade, ref]


func _unhandled_key_input(event: InputEvent) -> void:
	if not _panel.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	# 방금 답해서 무전이 없는데 아직 화면이 안 바뀐 사이에는 숫자키를 팀 선택(1~9)에 넘긴다
	if current() == null:
		return
	var k: int = event.keycode
	if k >= KEY_1 and k <= KEY_4:
		get_viewport().set_input_as_handled()
		choose(k - KEY_1)
	elif k == KEY_5 and _all.visible:
		get_viewport().set_input_as_handled()
		approve_all()
