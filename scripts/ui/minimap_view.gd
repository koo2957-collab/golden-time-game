class_name MinimapView
extends Control
## 미니맵 (기획안 9-1 "도면과 미니맵", 9-2 ① 하단 콘솔 왼쪽, R8 → R16 스타크래프트식).
##   바깥 배치도(도로·보도·마당·이웃 건물·소화전·차량)는 지휘관 눈에 보이는 곳이라 처음부터 그린다.
##   건물 안은 도면을 얻기 전에는 외곽(덩어리)과 대원이 본 구조만, 도면을 얻은 뒤에는 지금 보는 층의 평면도.
##   지금 화면에 보이는 범위를 테두리로 그리고, 누르거나 누른 채 끌면 그곳으로 화면이 옮겨진다 (jump).
## 불·연기·사람은 도면이 있어도 대원 시야와 보고로만 안다 — 미니맵도 본 것만 그린다.

signal jump(cell: Vector2, level: int)

const BG := Color(0.03, 0.05, 0.09, 0.9)
const WALL := Color("94a3b8")
const PLAN_WALL := Color(0.55, 0.72, 0.95, 0.75)
const DOOR := Color("fbbf24")
const FLOOR := Color(0.16, 0.2, 0.27)
## 도면 전, 본 적 없는 건물 안 (밖에서 보이는 덩어리)
const MASS := Color(0.24, 0.27, 0.33)
const GROUND := Color(0.1, 0.15, 0.11)
const ROAD := Color(0.2, 0.21, 0.24)
const SIDEWALK := Color(0.27, 0.27, 0.3)
## 다른 층을 볼 때 바깥은 흐리게
const OUTSIDE_DIM := 0.55
const FIRE := Color("ef4444")
const CREW := Color("38bdf8")
const COMMANDER := Color("fde047")
const VICTIM := Color("4ade80")
const VEHICLE := Color("f97316")
const HYDRANT := Color("60a5fa")
const VIEW_RECT := Color(1, 1, 1, 0.85)

var sim: SimWorld
var level := 1
## 지금 화면 네 모서리의 칸 좌표를 돌려주는 함수 (world.gd가 넣는다). 없으면 화면 범위를 그리지 않는다
var view_corners: Callable
var _bounds := Rect2i()
var _pressed := false


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(200, 110)
	# 모든 층에서 비어 있지 않은 칸(바깥 포함)을 감싸는 범위 (+여백)
	var b := sim.building
	var lo := Vector2i(b.width, b.height)
	var hi := Vector2i(-1, -1)
	for lv in b.levels():
		for y in b.height:
			for x in b.width:
				if b.cell(lv, x, y) != BuildingData.Cell.VOID:
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		_bounds = Rect2i(0, 0, b.width, b.height)
	else:
		_bounds = Rect2i(lo - Vector2i(1, 1), hi - lo + Vector2i(3, 3)).intersection(Rect2i(0, 0, b.width, b.height))


## 건물 안 평면도를 볼 수 있는가 (도면을 얻었거나 정보 안개가 꺼진 판)
func unlocked() -> bool:
	return sim != null and (sim.plan.known or not sim.perception.enabled)


func _scale() -> float:
	return minf(size.x / _bounds.size.x, size.y / _bounds.size.y)


func _origin() -> Vector2:
	var s := _scale()
	return (size - Vector2(_bounds.size) * s) * 0.5 - Vector2(_bounds.position) * s


## 화면(미니맵 안) 좌표 → 칸
func cell_at(p: Vector2) -> Vector2:
	return (p - _origin()) / _scale()


## 칸 → 미니맵 안 좌표
func point_of(cell: Vector2) -> Vector2:
	return _origin() + cell * _scale()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pressed = event.pressed
		if event.pressed:
			_jump_to(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _pressed:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_jump_to(event.position)
		else:
			_pressed = false
		accept_event()


func _jump_to(p: Vector2) -> void:
	var c := cell_at(p)
	c = c.clamp(Vector2(_bounds.position), Vector2(_bounds.end))
	jump.emit(c, level)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if sim == null:
		return
	var font := get_theme_default_font()
	var s := _scale()
	var o := _origin()
	var b := sim.building
	var p := sim.perception
	var grid := sim.fire.grid
	var ground_level := b.levels()[0]
	var dim := 1.0 if level == ground_level else OUTSIDE_DIM
	var plan_ok := unlocked()
	for y in range(_bounds.position.y, _bounds.end.y):
		for x in range(_bounds.position.x, _bounds.end.x):
			var r := Rect2(o + Vector2(x, y) * s, Vector2(s, s) + Vector2(0.5, 0.5))
			var t := b.cell(level, x, y)
			if t in BuildingData.OUTDOOR:
				# 이 층에 바닥이 없으면 1층 바깥 배치도를 흐리게 깐다
				var g := b.cell(ground_level, x, y) if t == BuildingData.Cell.VOID else t
				var gc := _outdoor_color(g)
				if gc.a > 0.0:
					draw_rect(r, Color(gc.r * dim, gc.g * dim, gc.b * dim))
				elif t == BuildingData.Cell.VOID and level != ground_level and not b.cell(ground_level, x, y) in BuildingData.OUTDOOR:
					# 다른 건물(이웃)의 1층 덩어리
					draw_rect(r, Color(MASS.r * dim, MASS.g * dim, MASS.b * dim))
				continue
			var seen: bool = sim.plan.structure_seen(level, x, y)
			if not seen and not plan_ok:
				draw_rect(r, MASS)
			else:
				var pt: int = t if seen else sim.plan.plan_cell(level, x, y)
				match pt:
					BuildingData.Cell.WALL, BuildingData.Cell.WINDOW:
						draw_rect(r, WALL if seen else PLAN_WALL)
					BuildingData.Cell.DOOR:
						draw_rect(r, DOOR)
					_:
						draw_rect(r, MASS if pt in BuildingData.OUTDOOR else FLOOR)
			var i := grid.index(level, x, y)
			if p.is_visible(level, x, y) and grid.state[i] == FuelGrid.State.BURNING or not p.is_visible(level, x, y) and p.is_seen(level, x, y) and p.seen_burning[i] == 1:
				draw_rect(r, FIRE)
	var dot := maxf(2.0, s * 0.6)
	for h in b.hydrants:
		draw_rect(Rect2(o + (Vector2(h) + Vector2(0.5, 0.5)) * s - Vector2(dot, dot) * 0.6, Vector2(dot, dot) * 1.2), Color(HYDRANT, dim))
	if level == ground_level:
		for v in sim.units.vehicles:
			if not v.away:
				var vp := o + v.pos * s
				draw_rect(Rect2(vp - Vector2(dot, dot) * 1.1, Vector2(dot, dot) * 2.2), VEHICLE)
	for v in sim.rescue.victims:
		if v.discovered and v.level == level and v.alive():
			draw_circle(o + v.pos * s, maxf(2.5, s * 0.8), VICTIM)
	for ff in sim.units.firefighters:
		if ff.level == level and not ff.aboard:
			draw_circle(o + ff.pos * s, dot, Color("f87171") if ff.incapacitated else CREW)
	if level == ground_level:
		ZoneDraw.draw(self, sim.zones, func(cell: Vector2) -> Vector2: return o + cell * s, 0, sim.clock.tick)
	var c := sim.command.commander
	if c.level == level:
		draw_circle(o + c.pos * s, maxf(2.5, s * 0.7), COMMANDER)
	_draw_view_rect()
	draw_string(font, Vector2(4, 14), b.floor_name(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("cbd5e1"))
	if not plan_ok:
		var hint := "도면 수신 대기"
		if not sim.plan.office.is_empty():
			hint = "도면: %s에 조를 보내면" % sim.plan.office.name
			if sim.plan.dwell_progress() > 0.0:
				hint = "도면 확인 중 %d%%" % roundi(sim.plan.dwell_progress() * 100.0)
		draw_string(font, Vector2(4, size.y - 6), hint, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 11, Color("a78bfa"))


## 지금 화면에 보이는 범위 (입체 화면이면 마름모꼴). 미니맵 밖으로 나간 부분은 잘린다
func _draw_view_rect() -> void:
	if not view_corners.is_valid():
		return
	var corners: Array = view_corners.call()
	if corners.size() != 4:
		return
	var box := Rect2(Vector2.ZERO, size)
	var pts := PackedVector2Array()
	for cell: Vector2 in corners:
		pts.append(point_of(cell))
	var clipped := Geometry2D.intersect_polygons(pts, PackedVector2Array([box.position, Vector2(box.end.x, 0), box.end, Vector2(0, box.end.y)]))
	for poly in clipped:
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, VIEW_RECT, 1.2)


static func _outdoor_color(t: int) -> Color:
	match t:
		BuildingData.Cell.ROAD:
			return ROAD
		BuildingData.Cell.SIDEWALK:
			return SIDEWALK
		BuildingData.Cell.GROUND:
			return GROUND
	return Color(0, 0, 0, 0)
