class_name TeamStrip
extends Control
## 팀 초상 줄 (기획안 9-2, P10-1): 하단 콘솔 가운데 위에 현장의 조마다 초상 + 공기 잔량 링 + 질문 대기 "?".
## 누르면 선택, 두 번 누르면 그 조로 화면 이동. 숫자키 1~9는 이 순서의 조를 고른다 (질문 카드가 떠 있으면 1~4는 카드 답).
## 전술상황판을 닫아도 공기와 질문 상태는 늘 보인다.

signal picked(crew_id: int)
signal jump(crew_id: int)

const SIZE := 46.0
const GAP := 8.0
const RING := 4.0

var sim: SimWorld
var selected: Array[int] = []
var _refresh := 0.0


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "


## 줄에 보이는 조 (현장에 있는 조, 출동 순서)
func crews() -> Array[int]:
	var out: Array[int] = []
	for c in sim.units.crews:
		if not sim.command.resources.is_en_route(c.squad_id) and not c.leader.aboard:
			out.append(c.id)
	return out


func _process(delta: float) -> void:
	if sim == null:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		var n := crews().size()
		custom_minimum_size = Vector2(n * (SIZE + GAP), SIZE + 18.0)
		queue_redraw()


func _slot(i: int) -> Rect2:
	return Rect2(Vector2(i * (SIZE + GAP), 0), Vector2(SIZE, SIZE))


func index_at(p: Vector2) -> int:
	var list := crews()
	for i in list.size():
		if _slot(i).grow(2).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := index_at(event.position)
		if i >= 0:
			var id: int = crews()[i]
			if event.double_click:
				jump.emit(id)
			else:
				picked.emit(id)
			accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	var i := index_at(at_position)
	if i < 0:
		return ""
	var c := sim.units.get_crew(crews()[i])
	return "%s %d조 · 공기 %d%%%s (%d번 키)" % [sim.units.squads[c.squad_id].name, c.number, roundi(air(c.id) * 100.0),
		" · 질문 대기" if asking(c.id) else "", i + 1]


## 조원 중 낮은 쪽 공기 비율
func air(crew_id: int) -> float:
	var c := sim.units.get_crew(crew_id)
	var low := 1.0
	for ff in c.members():
		low = minf(low, ff.air_ratio())
	return low


## 이 조가 낸 질문 카드가 답을 기다리는가
func asking(crew_id: int) -> bool:
	return sim.cards.queue.any(func(q: CardSystem.Card) -> bool: return q.crew_id == crew_id)


func _draw() -> void:
	if sim == null:
		return
	var font := get_theme_default_font()
	var list := crews()
	for i in list.size():
		var c := sim.units.get_crew(list[i])
		var r := _slot(i)
		var center := r.get_center()
		var color: Color = sim.units.squads[c.squad_id].color
		var down := c.leader.incapacitated
		draw_circle(center, SIZE * 0.5 - RING, Color(0.06, 0.09, 0.14, 0.9))
		draw_circle(center, SIZE * 0.5 - RING - 4.0, color.darkened(0.5 if down else 0.15))
		# 공기 잔량 링: 초록 → 주황 → 빨강
		var a := air(c.id)
		var ring_color := Color("22c55e") if a > 0.5 else (Color("f59e0b") if a > 0.25 else Color("ef4444"))
		draw_arc(center, SIZE * 0.5 - RING * 0.5, -PI / 2.0, -PI / 2.0 + TAU * a, 32, ring_color, RING)
		if c.id in selected:
			draw_arc(center, SIZE * 0.5 + 1.0, 0.0, TAU, 32, Color.WHITE, 2.0)
		var label := "%s%d" % [sim.units.squads[c.squad_id].name.substr(0, 2), c.number]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, center + Vector2(-w / 2.0, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		draw_string(font, Vector2(r.position.x + 2, r.end.y + 14), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("94a3b8"))
		if asking(c.id):
			draw_circle(r.position + Vector2(SIZE - 8, 8), 9.0, Color("fde047"))
			draw_string(font, r.position + Vector2(SIZE - 12, 13), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)
		if down:
			draw_string(font, center + Vector2(-6, -8), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ef4444"))
