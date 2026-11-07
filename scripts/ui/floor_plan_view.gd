class_name FloorPlanView
extends Node2D
## 건물 도면을 벡터로 그린다.
## 보고 있는 층을 진하게 그리고, 그 층의 빈 공간에는 아래층을 흐리게 비춰 보인다.

const ROOM_FONT_SIZE := 14
const FACE_FONT_SIZE := 18

var building: BuildingData
var level := 1


func setup(p_building: BuildingData) -> void:
	building = p_building
	queue_redraw()


func set_level(p_level: int) -> void:
	level = p_level
	queue_redraw()


func _draw() -> void:
	if building == null:
		return
	var size_px := Vector2(building.width, building.height) * PlanStyle.CELL_PX
	draw_rect(Rect2(Vector2.ZERO, size_px), PlanStyle.BACKGROUND)
	if building.has_level(level - 1):
		_draw_cells(level - 1, PlanStyle.OTHER_FLOOR_ALPHA)
	_draw_cells(level, 1.0)
	_draw_furniture()
	_draw_grid(size_px)
	_draw_room_labels()
	if level == building.levels()[0]:
		_draw_lane_line()
		_draw_face_labels()
		_draw_road_label()


func _draw_cells(lv: int, alpha: float) -> void:
	var px := PlanStyle.CELL_PX
	for y in building.height:
		for x in building.width:
			var c := building.cell(lv, x, y)
			if c == BuildingData.Cell.VOID:
				continue
			var color: Color = PlanStyle.CELL_COLORS[c]
			color.a *= alpha
			var r := Rect2(x * px, y * px, px, px)
			draw_rect(r, color)
			if c == BuildingData.Cell.STAIRS:
				var line := PlanStyle.STAIR_LINE
				line.a *= alpha
				for i in 3:
					var yy := r.position.y + px * (i + 1) / 4.0
					draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), line, 1.0)


func _draw_furniture() -> void:
	var px := PlanStyle.CELL_PX
	for item in building.furniture(level):
		var r: Rect2i = item.rect
		var rect := Rect2(Vector2(r.position) * px, Vector2(r.size) * px).grow(-2.0)
		draw_rect(rect, PlanStyle.FURNITURE_FILL)
		draw_rect(rect, PlanStyle.FURNITURE_LINE, false, 1.0)


## 1m 간격 눈금 (축척 감각용)
func _draw_grid(size_px: Vector2) -> void:
	var step := PlanStyle.CELL_PX / building.cell_size_m
	var x := 0.0
	while x <= size_px.x:
		draw_line(Vector2(x, 0), Vector2(x, size_px.y), PlanStyle.GRID_LINE, 1.0)
		x += step
	var y := 0.0
	while y <= size_px.y:
		draw_line(Vector2(0, y), Vector2(size_px.x, y), PlanStyle.GRID_LINE, 1.0)
		y += step


func _draw_room_labels() -> void:
	var font := PlanStyle.font()
	for room in building.rooms(level):
		var r: Rect2i = room.rect
		var rect_px := Rect2(Vector2(r.position) * PlanStyle.CELL_PX, Vector2(r.size) * PlanStyle.CELL_PX)
		var baseline := Vector2(rect_px.position.x, rect_px.get_center().y + ROOM_FONT_SIZE * 0.35)
		draw_string(font, baseline, room.name, HORIZONTAL_ALIGNMENT_CENTER, rect_px.size.x, ROOM_FONT_SIZE, PlanStyle.ROOM_LABEL)


## 건물 방면 표시 (SOP 105-2.2: 전면 A, 시계방향 B·C·D)
func _draw_face_labels() -> void:
	var fp := building.footprint(level)
	var px := PlanStyle.CELL_PX
	var rect := Rect2(Vector2(fp.position) * px, Vector2(fp.size) * px)
	var gap := px * 1.2
	var anchors := {
		"south": Vector2(rect.get_center().x, rect.end.y + gap + FACE_FONT_SIZE * 0.5),
		"north": Vector2(rect.get_center().x, rect.position.y - gap),
		"west": Vector2(rect.position.x - gap * 1.6, rect.get_center().y),
		"east": Vector2(rect.end.x + gap * 1.6, rect.get_center().y),
	}
	var font := PlanStyle.font()
	for face: String in building.faces:
		var side: String = building.faces[face]
		if not anchors.has(side):
			continue
		var p: Vector2 = anchors[side]
		draw_string(font, p - Vector2(40, 0), "%s면" % face, HORIZONTAL_ALIGNMENT_CENTER, 80, FACE_FONT_SIZE, PlanStyle.FACE_LABEL)


## 차도 중앙선 (점선)
func _draw_lane_line() -> void:
	var rows := building.road_rows(level)
	if rows.x < 0:
		return
	var y := (rows.x + rows.y + 1) * 0.5 * PlanStyle.CELL_PX
	var x := 0
	while x < building.width:
		draw_line(Vector2(x, y) * Vector2(PlanStyle.CELL_PX, 1), Vector2(x + 2, y) * Vector2(PlanStyle.CELL_PX, 1), PlanStyle.LANE_LINE, 2.0)
		x += 4


func _draw_road_label() -> void:
	var px := PlanStyle.CELL_PX
	for y in building.height:
		if building.cell(level, 0, y) == BuildingData.Cell.ROAD:
			var p := Vector2((building.width - 1) * px, (y + 2.6) * px)
			draw_string(PlanStyle.font(), p, "도로", HORIZONTAL_ALIGNMENT_RIGHT, -1, ROOM_FONT_SIZE, PlanStyle.ROAD_LABEL)
			return
