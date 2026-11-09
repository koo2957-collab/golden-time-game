class_name FloorBarView
extends Control
## 왼쪽 건물 층 막대 (기획안 9-2 "건물 실루엣을 세로로 세운 막대", R16).
## 반투명 건물 입면에 층마다 한 칸: 본 불(빨강·불꽃)·짙은 연기(회색)·대원 수, 지금 보는 층은 테두리.
## 땅(외부) 띠 아래는 지하층. 상세하지 않은 층(초고층 2~27층 등)은 한 덩어리로 줄여 그린다.
## 층 칸 클릭 = 그 층 단면, 외부 띠 클릭 = 외부 보기(건물 외관), 막대 위 휠 = 한 칸씩. 불·연기는 본 것만 (정보 안개 규칙).

signal floor_pressed(level: int, exterior: bool)
## 휠: 한 칸 오르내림 (+1 위, -1 아래). 순서(외부 보기 포함)는 world가 정한다
signal floor_step(direction: int)

const WIDTH := 172.0
const BUILDING_W := 70.0
const ROW_MAX := 30.0
const ROW_MIN := 12.0
const GAP_H := 14.0
const GROUND_H := 16.0
const BG := Color(0.04, 0.07, 0.12, 0.55)
const WALL_FILL := Color(0.62, 0.68, 0.78, 0.16)
const WALL_LINE := Color(0.72, 0.78, 0.88, 0.55)
const WINDOW := Color(0.75, 0.82, 0.92, 0.22)
const SMOKE_FILL := Color(0.55, 0.57, 0.6, 0.55)
const FIRE_FILL := Color(0.94, 0.27, 0.27, 0.5)
const FIRE_WINDOW := Color(1.0, 0.62, 0.2, 0.95)
const GROUND := Color(0.24, 0.36, 0.25, 0.75)
const TEXT := Color("e2e8f0")
const CREW := Color("38bdf8")

var sim: SimWorld
## 지금 보는 층, 외부 보기 중인가 (외부 띠가 강조된다)
var current := 1
var exterior := false
## 층 -> true (본 불 / 짙은 연기), 층 -> 대원 수
var fire: Dictionary = {}
var smoke: Dictionary = {}
var crews: Dictionary = {}
## 아래(땅 밑) → 위 순서의 그리기 항목 {kind: "floor"|"gap"|"ground", level, rect, text}
var _rows: Array[Dictionary] = []
## 아래 → 위 순서의 층 (휠 이동용)
var _order: Array[int] = []
var _row_h := ROW_MAX


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	mouse_filter = Control.MOUSE_FILTER_STOP
	_order = sim.building.levels()
	_order.sort_custom(func(a: int, b: int) -> bool: return sim.building.floor_number(a) < sim.building.floor_number(b))
	fit(600.0)


## 쓸 수 있는 높이에 맞춰 층 칸 높이를 정한다
func fit(max_h: float) -> void:
	var extras := GROUND_H + 8.0
	for i in range(1, _order.size()):
		if _gap_between(_order[i - 1], _order[i]) != "":
			extras += GAP_H
	_row_h = clampf((max_h - extras) / maxf(1.0, _order.size()), ROW_MIN, ROW_MAX)
	_layout()


func _gap_between(lower: int, upper: int) -> String:
	var a: int = sim.building.floor_number(lower)
	var b: int = sim.building.floor_number(upper)
	# 지하1층 바로 위는 1층 (0층 없음)
	if b - a <= 1 or a == -1 and b == 1:
		return ""
	var lo: int = a + 1 if a + 1 != 0 else 1
	var hi: int = b - 1 if b - 1 != 0 else -1
	return _short(lo) if lo == hi else "%s~%s" % [_short(lo).trim_suffix("층"), _short(hi)]


static func _short(n: int) -> String:
	return "지하%d층" % -n if n < 0 else "%d층" % n


## 위에서 아래로 쌓아 rect를 정한다 (그리기 좌표는 위가 0)
func _layout() -> void:
	var items: Array[Dictionary] = []
	for i in _order.size():
		var lv := _order[i]
		if i > 0:
			var gap := _gap_between(_order[i - 1], lv)
			if gap != "":
				items.append({"kind": "gap", "level": -999, "text": gap})
		if i > 0 and sim.building.floor_number(_order[i - 1]) < 1 and sim.building.floor_number(lv) >= 1:
			items.append({"kind": "ground", "level": _ground_level(), "text": "외부"})
		items.append({"kind": "floor", "level": lv, "text": _short(sim.building.floor_number(lv))})
	# 지하층이 없으면 땅 띠는 맨 아래
	if not items.any(func(it: Dictionary) -> bool: return it.kind == "ground"):
		items.insert(0, {"kind": "ground", "level": _ground_level(), "text": "외부"})
	items.reverse()
	var y := 4.0
	for it in items:
		var h: float = _row_h if it.kind == "floor" else (GAP_H if it.kind == "gap" else GROUND_H)
		it.rect = Rect2(4.0, y, WIDTH - 8.0, h)
		y += h
	_rows = items
	custom_minimum_size = Vector2(WIDTH, y + 4.0)
	size = custom_minimum_size
	queue_redraw()


## 바깥이 있는 층 (맨 아래 index 층)
func _ground_level() -> int:
	return sim.building.levels()[0]


func _row_at(p: Vector2) -> Dictionary:
	for it in _rows:
		var r: Rect2 = it.rect
		if p.y >= r.position.y and p.y < r.end.y:
			return it
	return {}


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			var it := _row_at(event.position)
			if not it.is_empty() and it.kind != "gap":
				floor_pressed.emit(int(it.level), it.kind == "ground")
			accept_event()
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			floor_step.emit(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	var it := _row_at(at_position)
	if it.is_empty():
		return ""
	match it.kind:
		"gap":
			return "%s — 이 판에서는 계단·승강기로 지나가는 층 (상세 계산 없음)" % it.text
		"ground":
			return "외부 (%s 바깥) — 클릭: 보기\n휠: 한 층씩 오르내림 (PgUp·PgDn)" % sim.building.floor_name(int(it.level))
	var lv := int(it.level)
	var parts: PackedStringArray = [sim.building.floor_name(lv)]
	if fire.has(lv):
		parts.append("불 확인")
	elif smoke.has(lv):
		parts.append("짙은 연기 확인")
	parts.append("대원 %d명" % int(crews.get(lv, 0)))
	return " · ".join(parts) + "\n클릭: 이 층 보기 · 휠: 한 층씩 오르내림 (PgUp·PgDn)"


func _draw() -> void:
	if sim == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var font := get_theme_default_font()
	var fs := 14 if _row_h >= 20.0 else 11
	var bx := 8.0
	# 건물 입면 (층 칸 전체를 감싸는 외곽선은 층마다 그린다)
	for it in _rows:
		var r: Rect2 = it.rect
		var body := Rect2(bx, r.position.y, BUILDING_W, r.size.y)
		match it.kind:
			"ground":
				draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.35, r.size.x, r.size.y * 0.3), GROUND)
				var on := exterior and int(it.level) == current
				if on:
					draw_rect(r.grow(-1.0), PlanStyle.SELECTION, false, 2.0)
				draw_string(font, Vector2(bx + BUILDING_W + 8.0, r.position.y + r.size.y * 0.5 + 5.0), it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PlanStyle.SELECTION if on else Color("86efac"))
			"gap":
				draw_rect(body, Color(WALL_FILL, 0.08))
				# 끊긴 표시 (물결 두 줄)
				for k in 2:
					var yy := r.position.y + 4.0 + k * 5.0
					var pts := PackedVector2Array()
					for s in 9:
						pts.append(Vector2(bx - 3.0 + s * (BUILDING_W + 6.0) / 8.0, yy + (2.0 if s % 2 == 0 else -2.0)))
					draw_polyline(pts, WALL_LINE, 1.0)
				draw_string(font, Vector2(bx + BUILDING_W + 8.0, r.end.y - 2.0), it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("94a3b8"))
			"floor":
				_draw_floor(it, body, font, fs)


func _draw_floor(it: Dictionary, body: Rect2, font: Font, fs: int) -> void:
	var lv := int(it.level)
	var r: Rect2 = it.rect
	var on_fire := fire.has(lv)
	var smoky := smoke.has(lv)
	draw_rect(body, WALL_FILL)
	if smoky:
		draw_rect(body, SMOKE_FILL)
	if on_fire:
		draw_rect(body, FIRE_FILL)
	# 창 4개 (불이 보인 층은 주황 불빛)
	var wh := maxf(3.0, body.size.y * 0.45)
	for k in 4:
		var wx := body.position.x + 6.0 + k * (BUILDING_W - 12.0) / 4.0
		draw_rect(Rect2(wx, body.position.y + (body.size.y - wh) * 0.5, (BUILDING_W - 12.0) / 4.0 - 4.0, wh), FIRE_WINDOW if on_fire else WINDOW)
	draw_rect(body, WALL_LINE, false, 1.0)
	var text_x := body.end.x + 8.0
	var mid := r.position.y + r.size.y * 0.5 + fs * 0.38
	var color := Color("f87171") if on_fire else (Color("cbd5e1") if smoky else TEXT)
	draw_string(font, Vector2(text_x, mid), it.text, HORIZONTAL_ALIGNMENT_LEFT, 50, fs, color)
	if on_fire:
		_draw_flame(Vector2(text_x + 52.0, r.position.y + r.size.y * 0.5), minf(r.size.y * 0.42, 9.0))
	var n := int(crews.get(lv, 0))
	if n > 0:
		var cx := r.end.x - 26.0
		draw_circle(Vector2(cx, r.position.y + r.size.y * 0.5), minf(r.size.y * 0.25, 5.0), CREW)
		draw_string(font, Vector2(cx + 6.0, mid), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CREW)
	if lv == current and not exterior:
		draw_rect(r.grow(-1.0), PlanStyle.SELECTION, false, 2.0)
		# 왼쪽 가장자리 화살표
		var cy := r.position.y + r.size.y * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(0, cy - 5), Vector2(6, cy), Vector2(0, cy + 5)]), PlanStyle.SELECTION)


func _draw_flame(c: Vector2, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.7, s * 0.6), c + Vector2(-s * 0.7, s * 0.6)]), Color("f97316"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.3), c + Vector2(s * 0.35, s * 0.6), c + Vector2(-s * 0.35, s * 0.6)]), Color("fde047"))
