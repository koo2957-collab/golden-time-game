class_name RadialMenu
extends Control
## 원형 메뉴 (기획안 9-1·9-3): 커서 주변에 둥글게 펼쳐 손을 덜 움직인다.
## 항목 {id, label, enabled, tip}. 첫 항목이 위쪽, 시계 방향. 고르면 picked(id), 바깥 클릭·우클릭·Esc는 닫기.

signal picked(id: String)

const R_OUT := 112.0
const R_IN := 36.0
const ARC_STEPS := 12
const FONT_SIZE := 15
const FILL := Color(0.06, 0.10, 0.17, 0.94)
const FILL_HOVER := Color("1d4ed8")
const FILL_OFF := Color(0.18, 0.18, 0.2, 0.85)
const EDGE := Color(1, 1, 1, 0.28)
const TEXT := Color("f1f5f9")
const TEXT_OFF := Color("64748b")

var items: Array[Dictionary] = []
var title := ""
var center := Vector2.ZERO
var _hover := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open(p_center: Vector2, p_title: String, p_items: Array[Dictionary]) -> void:
	var margin := R_OUT + 24.0
	var area := get_viewport_rect().size
	center = Vector2(clampf(p_center.x, margin, area.x - margin), clampf(p_center.y, margin + 24.0, area.y - margin))
	title = p_title
	items = p_items
	_hover = -1
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


## 테스트·키보드용: id로 고르기
func pick(id: String) -> bool:
	for it in items:
		if str(it.id) == id and bool(it.get("enabled", true)):
			close()
			picked.emit(id)
			return true
	return false


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := index_at(event.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		accept_event()
		var i := index_at(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT and i >= 0:
			if bool(items[i].get("enabled", true)):
				close()
				picked.emit(str(items[i].id))
		else:
			close()


## 화면 좌표의 항목 index (-1 = 없음)
func index_at(p: Vector2) -> int:
	var d := p - center
	var r := d.length()
	if items.is_empty() or r < R_IN or r > R_OUT + 16.0:
		return -1
	var n := items.size()
	var step := TAU / n
	var a := fposmod(d.angle() + PI / 2.0 + step / 2.0, TAU)
	return int(a / step) % n


## 항목 가운데의 화면 좌표 (테스트용)
func item_position(i: int) -> Vector2:
	var step := TAU / items.size()
	return center + Vector2.from_angle(-PI / 2.0 + i * step) * (R_IN + R_OUT) / 2.0


func _draw() -> void:
	if items.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.18))
	var font := get_theme_default_font()
	var n := items.size()
	var step := TAU / n
	for i in n:
		var a0 := -PI / 2.0 + i * step - step / 2.0 + 0.02
		var a1 := a0 + step - 0.04
		var pts := PackedVector2Array()
		for k in ARC_STEPS + 1:
			pts.append(center + Vector2.from_angle(lerpf(a0, a1, float(k) / ARC_STEPS)) * R_OUT)
		for k in range(ARC_STEPS, -1, -1):
			pts.append(center + Vector2.from_angle(lerpf(a0, a1, float(k) / ARC_STEPS)) * R_IN)
		var on := bool(items[i].get("enabled", true))
		draw_colored_polygon(pts, FILL_OFF if not on else (FILL_HOVER if i == _hover else FILL))
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, EDGE, 1.5, true)
		var label := str(items[i].label)
		var at := item_position(i)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, at + Vector2(-w / 2.0, FONT_SIZE * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT if on else TEXT_OFF)
	draw_circle(center, R_IN - 6.0, Color(0.03, 0.05, 0.09, 0.95))
	if title != "":
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 1).x
		var tp := center + Vector2(-tw / 2.0, -R_OUT - 12.0)
		draw_rect(Rect2(tp + Vector2(-8, -FONT_SIZE - 4), Vector2(tw + 16, FONT_SIZE + 12)), Color(0.03, 0.05, 0.09, 0.9))
		draw_string(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 1, Color("fde68a"))
	if _hover >= 0:
		var tip := str(items[_hover].get("tip", ""))
		if tip != "":
			var pw := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1).x
			var pp := center + Vector2(-pw / 2.0, R_OUT + 26.0)
			draw_rect(Rect2(pp + Vector2(-8, -FONT_SIZE - 2), Vector2(pw + 16, FONT_SIZE + 10)), Color(0.03, 0.05, 0.09, 0.9))
			draw_string(font, pp, tip, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, TEXT)
