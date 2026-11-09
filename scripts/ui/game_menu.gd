class_name GameMenu
extends CanvasLayer
## 게임 메뉴 (Esc, 기획안 8-4, P11-1). 열면 게임을 멈추고(get_tree().paused) 지도·질문 카드를 어둡게 가린다.
## 메뉴를 연 채 질문을 오래 고민해 '항상 실시간' 규칙을 피하지 못하게 하려는 것이다. 일시정지 횟수는 기록만 한다.
##   계속하기 / 조작 도움말 / 설정 / 처음부터 다시 / 임무 포기 / 메인 메뉴로 / 게임 종료
##   다시·포기·메인·종료는 확인 창을 거친다. 무엇을 할지는 신호로 world가 정한다 (기록 저장·씬 전환).

signal resumed
signal restart_confirmed
signal abandon_confirmed
signal main_menu_confirmed
signal quit_confirmed

const LAYER := 90
## 지도·카드를 가리는 어두운 막 (셰이더 흐림 대신 — 사무용 PC 부담 없음)
const SHADE := Color(0.02, 0.04, 0.07, 0.9)
const PANEL_BG := Color(0.06, 0.1, 0.18, 0.97)
const ACCENT := Color("f97316")
const TEXT := Color("e2e8f0")
const DIM := Color("94a3b8")
const WIDTH := 420.0

## 확인 창 문구: 항목 id -> [제목, 설명, 확인 버튼]
const CONFIRMS := {
	"restart": ["처음부터 다시", "같은 시나리오를 처음부터 새로 시작합니다. 지금 판은 '미완료'로 기록됩니다.", "다시 시작"],
	"abandon": ["임무 포기", "지금 상태로 판을 끝내고 디브리핑으로 갑니다. 이 판은 '미완료'로 기록됩니다.", "임무 포기"],
	"main": ["메인 메뉴로", "시나리오 선택 화면으로 나갑니다. 지금 판은 '미완료'로 기록됩니다.", "나가기"],
	"quit": ["게임 종료", "프로그램을 닫습니다. 진행 중인 판은 '미완료'로 기록됩니다.", "종료"],
}

var help_text := ""
## 진행 중인 판이 없으면(디브리핑·시작 화면) 포기·다시 항목을 숨긴다
var in_mission := true

var _shade: ColorRect
var _main: PanelContainer
var _confirm: PanelContainer
var _confirm_title: Label
var _confirm_text: Label
var _confirm_ok: Button
var _confirm_id := ""
var _help: PanelContainer
var _items: Dictionary = {}
var _settings: Control
## 확인 창만 띄운 상태 (창 닫기 X) — 취소하면 메뉴 없이 바로 닫는다
var _confirm_only := false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_shade = ColorRect.new()
	_shade.color = SHADE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_main = _panel()
	var box: VBoxContainer = _main.get_child(0)
	box.add_child(_label("게임 메뉴", 26, ACCENT))
	box.add_child(_label("게임이 멈춰 있습니다", 15, DIM))
	for item: Array in [["resume", "계속하기 (Esc)"], ["help", "조작 도움말"], ["settings", "설정"], ["restart", "처음부터 다시"],
			["abandon", "임무 포기"], ["main", "메인 메뉴로"], ["quit", "게임 종료"]]:
		var id: String = item[0]
		var b := _button(item[1], func() -> void: choose(id))
		_items[id] = b
		box.add_child(b)
	_confirm = _panel()
	var cbox: VBoxContainer = _confirm.get_child(0)
	_confirm_title = _label("", 24, ACCENT)
	cbox.add_child(_confirm_title)
	_confirm_text = _label("", 17, TEXT)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.custom_minimum_size = Vector2(WIDTH - 40.0, 0)
	cbox.add_child(_confirm_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	row.add_child(_button("취소", cancel_confirm))
	_confirm_ok = _button("", func() -> void: _accept(_confirm_id))
	row.add_child(_confirm_ok)
	cbox.add_child(row)
	_confirm.visible = false
	_help = _panel(720.0)
	_help.visible = false


func is_open() -> bool:
	return visible


func confirm_visible() -> bool:
	return visible and _confirm.visible


func confirm_id() -> String:
	return _confirm_id if confirm_visible() else ""


## 메뉴를 연다 (게임을 멈춤)
func open() -> void:
	if visible:
		return
	visible = true
	_confirm_only = false
	_main.visible = true
	_confirm.visible = false
	_help.visible = false
	for id in ["restart", "abandon"]:
		_items[id].visible = in_mission
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## 메뉴를 닫고 게임을 이어 간다
func close() -> void:
	if not visible:
		return
	visible = false
	if is_instance_valid(_settings):
		_settings.queue_free()
	get_tree().paused = false
	resumed.emit()


## 확인 창만 띄운다 (창 닫기 X·Alt+F4 → 게임 종료 확인)
func open_confirm(id: String) -> void:
	if not visible:
		open()
		_confirm_only = true
	choose(id)


func choose(id: String) -> void:
	match id:
		"resume":
			close()
		"help":
			_show_help()
		"settings":
			_settings = DisplayUi.new()
			add_child(_settings)
		_:
			if CONFIRMS.has(id):
				var c: Array = CONFIRMS[id]
				_confirm_id = id
				_confirm_title.text = c[0]
				_confirm_text.text = c[1] if in_mission or id == "quit" else c[1].split(".")[0] + "."
				_confirm_ok.text = c[2]
				_main.visible = false
				_confirm.visible = true


func cancel_confirm() -> void:
	_confirm.visible = false
	_confirm_id = ""
	if _confirm_only:
		close()
		return
	_main.visible = true


func _accept(id: String) -> void:
	_confirm.visible = false
	_confirm_id = ""
	visible = false
	get_tree().paused = false
	match id:
		"restart":
			restart_confirmed.emit()
		"abandon":
			abandon_confirmed.emit()
		"main":
			main_menu_confirmed.emit()
		"quit":
			quit_confirmed.emit()


func _show_help() -> void:
	var box: VBoxContainer = _help.get_child(0)
	for c in box.get_children():
		c.queue_free()
	box.add_child(_label("조작 도움말", 24, ACCENT))
	var l := _label(help_text if help_text != "" else "조작 안내가 없습니다.", 16, TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(680.0, 0)
	box.add_child(l)
	box.add_child(_button("돌아가기", func() -> void:
		_help.visible = false
		_main.visible = true))
	_main.visible = false
	_help.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_settings) and not _settings.is_queued_for_deletion():
			return  # 설정 화면이 스스로 닫는다
		if _confirm.visible:
			cancel_confirm()
		elif _help.visible:
			_help.visible = false
			_main.visible = true
		else:
			close()


func _panel(width := WIDTH) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(20)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(width, 0)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	p.add_child(box)
	add_child(p)
	return p


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(on_press)
	return b
