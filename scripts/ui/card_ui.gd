class_name CardUi
extends Control
## 무전 장면 (2026-11-14 사용자 결정, 프로스트펑크의 사건 창 방식 — 사용자 예시 그림. 예전: 화면 위쪽의 질문 카드, P7).
## 대원·상황실이 지휘관에게 판단을 물어 오면 화면 가운데에 띄운다:
##   먹물이 번진 어두운 바탕(테두리 상자 없음) · 왼쪽에 말하는 사람 큰 그림 · 작은 글씨로 누구·어디 · 큰 제목 · 무전 내용 · 둥근 선택 단추
##   훈련 방식: 장면이 떠 있는 동안 현장 시간이 멈춘다(World가 scene_changed를 받아 멈춤). 고르면 등급과 근거를 한 줄로 알려 준다
##   실전·악조건: 멈추지 않고 남은 시간 막대가 줄어든다. 등급은 끝난 뒤 평가 화면에서만 본다
##   뒤에서 기다리는 무전은 '+N 대기'. 답은 order_issued로 CommandOrder "card_answer"를 내보낸다 (기록·다시 하기)
## 누가 말하는지: 묻는 조의 조장(이름·계급) + 출동대 종류별 그림(data/art.json portraits). 조가 아니면 카드의 asker 글자

signal order_issued(order: CommandOrder)
## 장면이 뜨거나 닫힘 (World가 훈련 방식에서 시간을 멈추고 푼다)
signal scene_changed(open: bool)

## 장면 크기 (먹물 바탕) — 화면 설정값
const SCENE := Vector2(1180, 640)
const PORTRAIT := 400.0
const TEXT_W := 560.0
const BUTTON_W := 470.0
const BLOT_PATH := "res://art/ui/ink_blot.png"
const URGENCY_COLORS := {"긴급": Color("f87171"), "중요": Color("fcd34d"), "일반": Color("e2e8f0")}
## 고른 직후 알려 주는 한 줄의 색 (훈련 방식)
const GRADE_COLORS := {"최선": Color("4ade80"), "허용": Color("facc15"), "오답": Color("fb923c"), "치명": Color("f87171")}
## 고른 직후 한 줄이 떠 있는 실제 시간 (초) — 화면 설정값
const FEEDBACK_S := 4.0
const LINE_COLOR := Color(0.78, 0.9, 0.95, 0.85)

var sim: SimWorld
## 장면이 뜨면 시간이 멈추는 방식인가 (World가 준다: 훈련 = true). 없으면 멈추지 않는 것으로 본다
var pauses := Callable()
var _shade: ColorRect
var _panel: Control
var _glow: TextureRect
var _portrait: TextureRect
var _badge: Label
var _who: Label
var _ornament: Control
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
var _accent := Color.WHITE
## 동시 진입 허가 (P4-5): 진입 허가를 묻는 출동대가 둘 이상이면 진입 카드 아래에
var _all: Button
static var _textures: Dictionary = {}


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 뒤 화면을 어둡게 (장면이 떠 있는 동안. 시간이 멈추는 방식에서는 뒤 화면 조작도 막는다)
	_shade = ColorRect.new()
	_shade.color = Color(0.02, 0.03, 0.05, 0.5)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_shade.visible = false
	add_child(_shade)
	_panel = Control.new()
	_panel.custom_minimum_size = SCENE
	_panel.size = SCENE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var blot := TextureRect.new()
	blot.texture = _texture(BLOT_PATH)
	blot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blot.stretch_mode = TextureRect.STRETCH_SCALE
	blot.size = SCENE
	blot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(blot)
	# 말하는 사람 뒤의 따뜻한 빛 (손전등·불빛)
	_glow = TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.62, 0.25, 0.42))
	grad.set_color(1, Color(1.0, 0.5, 0.15, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	_glow.texture = gt
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.position = Vector2(110, 90)
	_glow.size = Vector2(PORTRAIT + 60, PORTRAIT + 60)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_glow)
	# 왼쪽: 말하는 사람 (큰 그림)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.position = Vector2(140, 96)
	_portrait.size = Vector2(PORTRAIT, PORTRAIT)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_portrait)
	_badge = Label.new()
	_badge.text = "무전"
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.position = _portrait.position
	_badge.size = _portrait.size
	_badge.add_theme_font_size_override("font_size", 44)
	_badge.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9, 0.6))
	_panel.add_child(_badge)
	# 오른쪽: 누구·어디(작게) → 꾸밈 줄 → 제목(크게) → 무전 내용 → 선택 단추
	var box := VBoxContainer.new()
	box.position = Vector2(530, 96)
	box.custom_minimum_size = Vector2(TEXT_W, 0)
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_ornament = Control.new()
	_ornament.custom_minimum_size = Vector2(TEXT_W, 14)
	_ornament.draw.connect(_draw_ornament)
	box.add_child(_ornament)
	_who = Label.new()
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_who.add_theme_font_size_override("font_size", 15)
	_who.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	box.add_child(_who)
	_head = Label.new()
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head.add_theme_font_size_override("font_size", 28)
	box.add_child(_head)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(TEXT_W, 0)
	_text.add_theme_font_size_override("font_size", 18)
	_text.add_theme_color_override("font_color", Color(0.86, 0.88, 0.9))
	_text.add_theme_constant_override("line_spacing", 5)
	box.add_child(_text)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 5)
	box.add_child(_bar)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	box.add_child(gap)
	for i in 4:
		var b := _pill()
		b.pressed.connect(choose.bind(i))
		box.add_child(b)
		_buttons.append(b)
	_all = _pill()
	_all.add_theme_color_override("font_color", Color("fde68a"))
	_all.pressed.connect(approve_all)
	_all.visible = false
	box.add_child(_all)
	_more = Label.new()
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_more.add_theme_color_override("font_color", Color("94a3b8"))
	box.add_child(_more)
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


## 둥근 선택 단추 (가운데 정렬, 얇은 밝은 테두리)
func _pill() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(BUTTON_W, 46)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color(0.92, 0.95, 0.97))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	for state: String in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.07, 0.1, 0.13, 0.82), "hover": Color(0.13, 0.22, 0.27, 0.95), "pressed": Color(0.2, 0.33, 0.4, 1.0)}[state]
		sb.set_corner_radius_all(22)
		sb.set_border_width_all(2 if state != "normal" else 1)
		sb.border_color = LINE_COLOR if state != "normal" else Color(LINE_COLOR, 0.5)
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 9
		sb.content_margin_bottom = 9
		b.add_theme_stylebox_override(state, sb)
	return b


## 제목 위의 꾸밈 줄: 가운데 마름모와 양쪽으로 가늘어지는 선
func _draw_ornament() -> void:
	var w := _ornament.size.x
	var y := 7.0
	var c := Color(_accent, 0.9)
	var mid := w * 0.5
	_ornament.draw_colored_polygon(PackedVector2Array([Vector2(mid, y - 5), Vector2(mid + 5, y), Vector2(mid, y + 5), Vector2(mid - 5, y)]), c)
	for side: float in [-1.0, 1.0]:
		_ornament.draw_line(Vector2(mid + side * 12, y), Vector2(mid + side * 70, y), c, 1.5)
		_ornament.draw_line(Vector2(mid + side * 70, y), Vector2(mid + side * 130, y), Color(c, 0.25), 1.0)
		_ornament.draw_circle(Vector2(mid + side * 76, y), 2.0, c)


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
	_shade.visible = open
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP if pausing() else Control.MOUSE_FILTER_IGNORE
	_shade.color.a = 0.5 if pausing() else 0.22
	if not open:
		_shown_uid = -1
		return
	if c.uid != _shown_uid:
		_shown_uid = c.uid
		_fill(c)
	# 지도 영역 가운데에 (오른쪽 상황판이 가리지 않는 곳). 화면이 작으면 줄여서 넣는다
	var k := minf(1.0, minf(size.x / (SCENE.x + 40.0), size.y / (SCENE.y + 40.0)))
	_panel.scale = Vector2(k, k)
	_panel.position = Vector2(_map_center_x() - SCENE.x * k * 0.5, maxf(20.0, (size.y - SCENE.y * k) * 0.44))
	var total := float(c.deadline_tick - c.asked_tick)
	_bar.visible = not pausing()
	_bar.value = 100.0 * float(c.deadline_tick - sim.clock.tick) / maxf(1.0, total)
	var waiting := sim.cards.queue.size() - 1
	var entries := sim.command.waiting_squads().size()
	_all.visible = c.id == CommandOrder.ENTRY_CARD and entries >= 2
	if _all.visible:
		_all.text = "5. 기다리는 %d개 출동대 모두 진입 허가" % entries
	_more.text = "+%d 대기" % waiting if waiting > 0 else ""
	_more.visible = waiting > 0


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
		"name": "%s %d조 · %s %s" % [squad.name if squad else "", crew.number, ff.rank, ff.name],
		"where": "%s · 공기 %d%%" % [p_sim.building.floor_name(ff.level), roundi(air * 100.0)],
		"portrait": str(portraits.get(squad.type if squad else "", portraits.get("default", ""))),
	}


func _fill(c: CardSystem.Card) -> void:
	_accent = URGENCY_COLORS.get(c.urgency, Color.WHITE)
	var sp := speaker(sim, c)
	_who.text = "%s%s" % [str(sp.name), "  ·  " + str(sp.where) if str(sp.where) != "" else ""]
	var tex := _texture(str(sp.portrait))
	_portrait.texture = tex
	_portrait.visible = tex != null
	_glow.visible = tex != null
	_badge.visible = tex == null
	_head.text = str(c.spec.get("title", ""))
	_head.add_theme_color_override("font_color", _accent)
	_ornament.queue_redraw()
	_text.text = spoken(c.text)
	for i in _buttons.size():
		var b := _buttons[i]
		b.visible = i < c.options.size()
		if b.visible:
			b.text = str(c.options[i].text)
			b.tooltip_text = "숫자키 %d" % (i + 1)


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


## 훈련 방식: 고른 직후 등급과 근거를 한 줄로 (2026-11-14 사용자 결정). 실전에서는 부르지 않는다
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
