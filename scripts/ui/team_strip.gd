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
const IDLE_COLOR := Color("7dd3fc")
## 무전 표시 색 (무전 카드의 분대 배지·지도 위 표시와 같은 색)
const RADIO_COLOR := Color("fde047")

var sim: SimWorld
var selected: Array[int] = []
## 지금 떠 있는 무전을 보낸 조 (-1 = 없음)
var speaking := -1
var _refresh := 0.0


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "


## 줄에 보이는 조 (현장에 있는 조, 출동 순서)
func crews() -> Array[int]:
	var out: Array[int] = []
	for c in sim.units.crews:
		# 한 명 보내기로 나간 대원은 줄에 없다 (고르거나 명령하지 않는다)
		if not c.solo and not sim.command.resources.is_en_route(c.squad_id) and not c.leader.aboard:
			out.append(c.id)
	return out


func _process(delta: float) -> void:
	if sim == null:
		return
	var card := sim.cards.active()
	var now_speaking := card.crew_id if card != null else -1
	if now_speaking != speaking or speaking >= 0:
		speaking = now_speaking
		queue_redraw()
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
	return "%s · 공기 %d%%%s (%d번 키)" % [sim.units.crew_name(c), roundi(air(c.id) * 100.0),
		" · 질문 대기" if asking(c.id) else (" · 임무 없음 (대기)" if idle(c.id) else ""), i + 1]


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


## 할 일 없이 서 있는가 (구급대는 처치·이송을 따로 보여 주므로 빼고)
func idle(crew_id: int) -> bool:
	return not sim.ems.is_ems_crew(crew_id) and sim.squad_idle(crew_id)


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
		var label := short_label(sim, c)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, center + Vector2(-w / 2.0, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		# 인원 점: 조원 수만큼 (쓰러진 대원은 빨강) — 3명 이상일 때만
		if c.list.size() > 2:
			for k in c.list.size():
				var dot := Vector2(center.x + (k - (c.list.size() - 1) * 0.5) * 7.0, r.position.y + 9.0)
				draw_circle(dot, 2.5, Color("ef4444") if c.list[k].incapacitated else Color(1, 1, 1, 0.9))
		draw_string(font, Vector2(r.position.x + 2, r.end.y + 14), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("94a3b8"))
		if c.id == speaking:
			# 지금 떠 있는 무전을 보낸 조: 노란 고리가 맥박치듯 + 무전기 표시 (2026-11-27 사용자 결정 — 어느 분대가 무전했는지)
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.6)
			draw_arc(center, SIZE * 0.5 + 3.0 + pulse * 3.0, 0.0, TAU, 40, Color(RADIO_COLOR, 0.45 + 0.55 * pulse), 2.5)
			draw_circle(r.position + Vector2(SIZE - 8, 8), 10.0, RADIO_COLOR)
			draw_radio_icon(self, r.position + Vector2(SIZE - 8, 8), 7.0, Color.BLACK)
		elif asking(c.id):
			draw_circle(r.position + Vector2(SIZE - 8, 8), 9.0, Color("fde047"))
			draw_string(font, r.position + Vector2(SIZE - 12, 13), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)
		elif idle(c.id):
			# 할 일 없이 서 있는 분대 (노는 일꾼 알림처럼 — 다음 임무를 줄 분대를 한눈에, 2026-11-17)
			draw_string(font, Vector2(r.end.x - 24, r.end.y + 14), "대기", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, IDLE_COLOR)
		if down:
			draw_string(font, center + Vector2(-6, -8), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ef4444"))


## 분대 짧은 이름: 나누지 않은 분대는 분대 이름("진압2"), 나뉜 조는 앞 두 글자 + 조 번호 (팀 초상·무전 카드 배지)
static func short_label(p_sim: SimWorld, c: Crew) -> String:
	if p_sim.units.whole_squad(c):
		return p_sim.units.squads[c.squad_id].name
	return "%s%d" % [p_sim.units.squads[c.squad_id].name.substr(0, 2), c.number]


## 작은 무전기 그림 (몸통 + 안테나 + 스피커 줄). at = 가운데, s = 반 높이
static func draw_radio_icon(ci: CanvasItem, at: Vector2, s: float, col: Color) -> void:
	ci.draw_rect(Rect2(at + Vector2(-s * 0.5, -s * 0.45), Vector2(s, s * 1.4)), col)
	ci.draw_line(at + Vector2(s * 0.25, -s * 0.45), at + Vector2(s * 0.25, -s * 1.05), col, maxf(1.0, s * 0.22))
	var hole := Color(1.0 - col.r, 1.0 - col.g, 1.0 - col.b, 0.8)
	for k in 2:
		var y := at.y + s * 0.32 * k
		ci.draw_line(Vector2(at.x - s * 0.28, y), Vector2(at.x + s * 0.28, y), hole, maxf(1.0, s * 0.14))
