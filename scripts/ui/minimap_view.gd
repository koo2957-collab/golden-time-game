class_name MinimapView
extends Control
## 미니맵 (기획안 9-1 "도면과 미니맵", 9-2 ① 하단 콘솔 왼쪽, R8).
##   도면을 얻기 전: 잠김 ("도면 수신 대기" + 도면 얻는 곳 안내).
##   도면을 얻은 뒤: 지금 보는 층의 평면(대원이 본 곳은 실제, 나머지는 도면), 대원·지휘관 위치, 확인한 불, 발견한 구조대상자.
##   클릭하면 그곳으로 화면이 옮겨진다 (jump).
## 불·연기·사람은 도면이 있어도 대원 시야와 보고로만 안다 — 미니맵도 본 것만 그린다.

signal jump(cell: Vector2, level: int)

const BG := Color(0.03, 0.05, 0.09, 0.9)
const WALL := Color("94a3b8")
const PLAN_WALL := Color(0.55, 0.72, 0.95, 0.75)
const DOOR := Color("fbbf24")
const FLOOR := Color(0.16, 0.2, 0.27)
const FIRE := Color("ef4444")
const CREW := Color("38bdf8")
const COMMANDER := Color("fde047")
const VICTIM := Color("4ade80")

var sim: SimWorld
var level := 1
var _bounds := Rect2i()


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(200, 110)
	# 모든 층의 실내 칸을 감싸는 범위 (+여백)
	var b := sim.building
	var lo := Vector2i(b.width, b.height)
	var hi := Vector2i(-1, -1)
	for lv in b.levels():
		for y in b.height:
			for x in b.width:
				if not b.cell(lv, x, y) in BuildingData.OUTDOOR:
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	_bounds = Rect2i(lo - Vector2i(2, 2), hi - lo + Vector2i(5, 5)) if hi.x >= 0 else Rect2i(0, 0, b.width, b.height)


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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and unlocked():
		jump.emit(cell_at(event.position), level)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if sim == null:
		return
	var font := get_theme_default_font()
	if not unlocked():
		draw_string(font, Vector2(0, size.y * 0.42), "미니맵", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color("64748b"))
		draw_string(font, Vector2(0, size.y * 0.42 + 20), "도면 수신 대기", HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color("64748b"))
		if not sim.plan.office.is_empty():
			var hint := "%s에 조를 보내면 도면" % sim.plan.office.name
			if sim.plan.dwell_progress() > 0.0:
				hint = "도면 확인 중 %d%%" % roundi(sim.plan.dwell_progress() * 100.0)
			draw_string(font, Vector2(0, size.y * 0.42 + 40), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color("a78bfa"))
		return
	var s := _scale()
	var o := _origin()
	var b := sim.building
	var p := sim.perception
	var grid := sim.fire.grid
	for y in range(_bounds.position.y, _bounds.end.y):
		for x in range(_bounds.position.x, _bounds.end.x):
			if x < 0 or y < 0 or x >= b.width or y >= b.height:
				continue
			var seen := sim.plan.structure_seen(level, x, y)
			var t := b.cell(level, x, y) if seen else sim.plan.plan_cell(level, x, y)
			if t in BuildingData.OUTDOOR:
				continue
			var r := Rect2(o + Vector2(x, y) * s, Vector2(s, s) + Vector2(0.5, 0.5))
			match t:
				BuildingData.Cell.WALL, BuildingData.Cell.WINDOW:
					draw_rect(r, WALL if seen else PLAN_WALL)
				BuildingData.Cell.DOOR:
					draw_rect(r, DOOR)
				_:
					draw_rect(r, FLOOR)
			var i := grid.index(level, x, y)
			if p.is_visible(level, x, y) and grid.state[i] == FuelGrid.State.BURNING or not p.is_visible(level, x, y) and p.is_seen(level, x, y) and p.seen_burning[i] == 1:
				draw_rect(r, FIRE)
	for v in sim.rescue.victims:
		if v.discovered and v.level == level and v.alive():
			draw_circle(o + v.pos * s, maxf(2.5, s * 0.8), VICTIM)
	for ff in sim.units.firefighters:
		if ff.level == level and not ff.aboard:
			draw_circle(o + ff.pos * s, maxf(2.0, s * 0.6), Color("f87171") if ff.incapacitated else CREW)
	var c := sim.command.commander
	if c.level == level:
		draw_circle(o + c.pos * s, maxf(2.5, s * 0.7), COMMANDER)
	draw_string(font, Vector2(4, 14), b.floor_name(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("cbd5e1"))
