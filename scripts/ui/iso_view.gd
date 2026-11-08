class_name IsoView
extends Node2D
## 입체(아이소메트릭) 화면. 시뮬레이션 상태를 읽어 매 프레임 그린다.
## 그리는 순서 (뒤 → 앞):
##   1) 바닥 타일, 방 이름, 선택한 조의 경로
##   2) 대각선(x + y) 순서로 벽·문·창·가구·화염·대원 (앞에 있는 것이 나중에 그려져 뒤를 가린다)
##   3) 연기층: 천장에서 계산된 깊이만큼 내려온 반투명 덩어리
## 뒤쪽 외벽(북·서)은 천장 높이로, 나머지 벽은 낮게 잘라 실내가 보이게 한다.

const CEILING_M := 2.4
const WALL_CUT_M := 0.45
const WINDOW_SILL_M := 0.9
const WINDOW_TOP_M := 2.1
const DOOR_TOP_M := 2.0
const UNIT_BODY_M := 1.35
const UNIT_HEAD_M := 1.55
const UNIT_LABEL_M := 1.95
## 장비 착용 대원 폭 약 0.5m
const UNIT_HALF_W := 11.0
const UNIT_HEAD_R := 7.0
const LABEL_FONT_SIZE := 13
const FACE_FONT_SIZE := 18
const SOUTH_SHADE := 0.22
const EAST_SHADE := 0.4
const GLASS_COLOR := Color(0.42, 0.66, 0.88, 0.55)
const THERMAL_STRUCTURE := Color(0.05, 0.05, 0.08)
const THERMAL_FURNITURE := Color(0.14, 0.12, 0.2)
const SMOKE_MIN_ALPHA := 0.12
const SMOKE_DENSITY_ALPHA := 0.5
## 가구 이름별 높이 (m). 없으면 DEFAULT_FURNITURE_M
const FURNITURE_HEIGHTS := {
	"소파": 0.8, "침대": 0.55, "탁자": 0.45, "식탁": 0.75, "책상": 0.75,
	"조리대": 0.9, "거실장": 1.0, "장롱": 1.9, "책장": 1.8,
}
const DEFAULT_FURNITURE_M := 0.8
const HYDRANT_M := 0.8
const VEHICLE_CUT_M := 1.3
const VEHICLE_ALPHA := 0.9
const NOZZLE_M := 1.1
const IMPACT_M := 0.4
## 정보 안개: 모르는 곳 / 본 적 있지만 지금은 안 보이는 곳
const FOG_COLOR := Color(0.04, 0.05, 0.07)
const FOG_UNKNOWN_ALPHA := 0.82
const FOG_SEEN_ALPHA := 0.4
const THERMAL_UNKNOWN := Color(0.03, 0.03, 0.05)
## 낮은 자세 대원의 키 비율
const CROUCH_SCALE := 0.62

var sim: SimWorld
var selection: SelectionController
var proj: IsoProjection
var level := 1
var thermal := false

var _furniture_h: Dictionary = {}  # level -> PackedFloat32Array
var _opening_of: Dictionary = {}  # Vector3i -> Opening
var _footprint: Dictionary = {}  # level -> Rect2i
var _lit: Array[Opening] = []  # 불빛이 보이는 창 (그릴 때마다 갱신)


func setup(p_sim: SimWorld, p_selection: SelectionController, p_proj: IsoProjection) -> void:
	sim = p_sim
	selection = p_selection
	proj = p_proj
	var b := sim.building
	for lv in b.levels():
		var heights := PackedFloat32Array()
		heights.resize(b.width * b.height)
		for item in b.furniture(lv):
			var r: Rect2i = item.rect
			var h: float = FURNITURE_HEIGHTS.get(item.name, DEFAULT_FURNITURE_M)
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					heights[y * b.width + x] = h
		_furniture_h[lv] = heights
		_footprint[lv] = b.footprint(lv)
	for o in sim.fire.openings:
		for c in o.cells:
			_opening_of[Vector3i(c.x, c.y, o.level)] = o


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var b := sim.building
	var alpha := sim.clock.alpha()
	_lit = sim.command.survey.lit_windows()
	_draw_ground()
	_draw_room_labels()
	if level == b.levels()[0]:
		_draw_face_labels()
		_draw_staging()
	for crew_id in selection.selected:
		_draw_path(sim.units.get_crew(crew_id).leader, alpha)
	if selection.commander_selected:
		_draw_path(sim.command.commander, alpha)
	_draw_hoses()
	if level == b.levels()[0]:
		for line in UnitsView.supply_lines(sim):
			draw_line(proj.to_screen(line[0], 0.05), proj.to_screen(line[1], 0.05), PlanStyle.SUPPLY_LINE, 4.0)
	# 대원·차량을 대각선(x + y) 깊이별로 모아 벽·가구와 함께 뒤에서 앞으로 그린다
	var buckets := {}
	for ff in sim.units.firefighters:
		if ff.level == level and not ff.aboard:
			_bucket(buckets, UnitsView.display_pos(ff, alpha), ff)
	if level == b.levels()[0]:
		for v in sim.units.vehicles:
			if not v.away:
				_bucket(buckets, v.prev_pos.lerp(v.pos, alpha), v)
	for victim in sim.rescue.victims:
		if victim.discovered and victim.level == level:
			_bucket(buckets, victim.pos, victim)
	var commander := sim.command.commander
	if commander.level == level:
		_bucket(buckets, UnitsView.display_pos(commander, alpha), commander)
	if level == b.levels()[0]:
		for w in sim.command.survey.witnesses:
			if w.present(sim.clock.tick):
				_bucket(buckets, w.pos, w)
	for d in range(0, b.width + b.height - 1):
		for x in range(maxi(0, d - b.height + 1), mini(d, b.width - 1) + 1):
			_draw_cell_objects(x, d - x)
		if buckets.has(d):
			var group: Array = buckets[d]
			group.sort_custom(func(a: Array, c: Array) -> bool: return a[0] < c[0])
			for item: Array in group:
				if item[1] == commander:
					_draw_commander(alpha)
				elif item[1] is Firefighter:
					_draw_unit(item[1], alpha)
				elif item[1] is Victim:
					_draw_victim(item[1])
				elif item[1] is Witness:
					_draw_witness(item[1])
				else:
					_draw_vehicle(item[1], alpha)
	if not thermal:
		_draw_smoke()
	_draw_blasts()
	_draw_sprays(alpha)
	for e in sim.rekindle.spotted_cells():
		if e.z == level:
			var ep := proj.to_screen(Vector2(e.x, e.y) + Vector2(0.5, 0.5), 0.05)
			draw_circle(ep, 4.0, PlanStyle.EMBER)
			draw_arc(ep, 7.0, 0.0, TAU, 16, PlanStyle.EMBER, 1.5)
	if level == b.levels()[0]:
		_draw_staging_label()


func _bucket(buckets: Dictionary, p: Vector2, obj: Object) -> void:
	var d := floori(p.x) + floori(p.y)
	if not buckets.has(d):
		buckets[d] = []
	buckets[d].append([p.x + p.y, obj])


# --- 바닥 ---

func _draw_ground() -> void:
	var b := sim.building
	var fire := sim.fire
	var t_amb := fire.config.value("ambient_temp_c")
	for y in b.height:
		for x in b.width:
			var t := b.cell(level, x, y)
			if t == BuildingData.Cell.VOID:
				continue
			var color: Color
			var structure := t in [BuildingData.Cell.WALL, BuildingData.Cell.WINDOW]
			if thermal:
				if structure:
					color = THERMAL_STRUCTURE
				elif t in BuildingData.OUTDOOR:
					color = FireView.thermal_color(t_amb, t_amb)
				elif sim.perception.is_thermal_visible(level, x, y):
					color = FireView.thermal_color(_cell_temperature(x, y), t_amb)
				else:
					color = THERMAL_UNKNOWN
			else:
				color = PlanStyle.CELL_COLORS[t]
				if structure:
					color = PlanStyle.CELL_COLORS[BuildingData.Cell.FLOOR].darkened(0.3)
				if _cell_burnt(x, y) and _furniture_height(x, y) <= 0.0:
					color = color.lerp(FireView.CHAR_COLOR, 0.8)
			var tile := _tile(x, y, 0.0)
			draw_colored_polygon(tile, color)
			if t == BuildingData.Cell.STAIRS and not thermal:
				_draw_stair_steps(x, y)
			if not thermal and not structure:
				var fog := _fog_alpha(x, y)
				if fog > 0.0:
					draw_colored_polygon(tile, Color(FOG_COLOR, fog))
	if not thermal:
		_draw_grid_lines()
		_draw_lane_line()


## 대기1단계 장소: 차로 바닥에 점선 테두리와 이름
func _draw_staging() -> void:
	var rects := sim.command.resources.staging_rects()
	for r in rects:
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for k in 4:
			draw_dashed_line(proj.to_screen(corners[k], 0.02), proj.to_screen(corners[(k + 1) % 4], 0.02), PlanStyle.STAGING_COLOR, 2.0, 8.0)



## 대기1단계 장소 이름: 차량에 가리지 않게 맨 위에 그린다
func _draw_staging_label() -> void:
	var rects := sim.command.resources.staging_rects()
	if not rects.is_empty():
		var p := proj.to_screen(Vector2(rects[0].position.x + 0.5, rects[0].end.y + 0.8), 0.02)
		draw_string(PlanStyle.font(), p, "대기1단계 장소 (%s)" % sim.command.resources.staging_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, PlanStyle.STAGING_COLOR.lightened(0.3))


func _draw_lane_line() -> void:
	if level != sim.building.levels()[0]:
		return
	var rows := sim.building.road_rows(level)
	if rows.x < 0:
		return
	var y := (rows.x + rows.y + 1) * 0.5
	var x := 0
	while x < sim.building.width:
		draw_line(proj.to_screen(Vector2(x, y), 0.01), proj.to_screen(Vector2(x + 2, y), 0.01), PlanStyle.LANE_LINE, 2.0)
		x += 4


func _draw_grid_lines() -> void:
	var b := sim.building
	var line := Color(0, 0, 0, 0.06)
	for x in range(0, b.width + 1, 2):
		draw_line(proj.to_screen(Vector2(x, 0)), proj.to_screen(Vector2(x, b.height)), line, 1.0)
	for y in range(0, b.height + 1, 2):
		draw_line(proj.to_screen(Vector2(0, y)), proj.to_screen(Vector2(b.width, y)), line, 1.0)


func _draw_stair_steps(x: int, y: int) -> void:
	for k in 4:
		var f := (k + 0.5) / 4.0
		draw_line(proj.to_screen(Vector2(x, y + f)), proj.to_screen(Vector2(x + 1, y + f)), PlanStyle.STAIR_LINE, 1.0)


func _draw_room_labels() -> void:
	if thermal:
		return
	var font := PlanStyle.font()
	for room in sim.building.rooms(level):
		var r: Rect2i = room.rect
		var center := proj.to_screen(Vector2(r.position) + Vector2(r.size) * 0.5)
		draw_string(font, center + Vector2(-60, LABEL_FONT_SIZE * 0.35), room.name, HORIZONTAL_ALIGNMENT_CENTER, 120, LABEL_FONT_SIZE, PlanStyle.ROOM_LABEL)
		if _room_searched(room.id):
			draw_string(font, center + Vector2(-60, LABEL_FONT_SIZE * 1.6), "[검색 완료]", HORIZONTAL_ALIGNMENT_CENTER, 120, LABEL_FONT_SIZE, PlanStyle.SEARCHED)
		elif sim.command.survey.reported_rooms.has(room.id):
			draw_string(font, center + Vector2(-90, LABEL_FONT_SIZE * 1.6), "[제보: 구조대상자 가능]", HORIZONTAL_ALIGNMENT_CENTER, 180, LABEL_FONT_SIZE, PlanStyle.REPORTED_ROOM)


func _draw_face_labels() -> void:
	var fp: Rect2i = _footprint[level]
	var c := Vector2(fp.position) + Vector2(fp.size) * 0.5
	var gap := 2.0
	var anchors := {
		"south": Vector2(c.x, fp.end.y + gap),
		"north": Vector2(c.x, fp.position.y - gap),
		"west": Vector2(fp.position.x - gap, c.y),
		"east": Vector2(fp.end.x + gap, c.y),
	}
	for face: String in sim.building.faces:
		var side: String = sim.building.faces[face]
		if anchors.has(side):
			var p := proj.to_screen(anchors[side])
			var seen := sim.command.survey.face_seen(face)
			draw_string(PlanStyle.font(), p + Vector2(-50, 0), "%s면%s" % [face, " ✓" if seen else ""], HORIZONTAL_ALIGNMENT_CENTER, 100, FACE_FONT_SIZE, PlanStyle.FACE_LABEL)


func _draw_path(ff: Firefighter, alpha: float) -> void:
	if not ff.is_moving() or ff.level != level:
		return
	var points := PackedVector2Array([proj.to_screen(UnitsView.display_pos(ff, alpha), 0.02)])
	for wp in ff.path:
		if wp.z != level:
			break
		points.append(proj.to_screen(Vector2(wp.x + 0.5, wp.y + 0.5), 0.02))
	if points.size() >= 2:
		draw_polyline(points, PlanStyle.PATH_LINE, 1.5)


# --- 대각선 순서로 그리는 물체 ---

func _draw_cell_objects(x: int, y: int) -> void:
	var t := sim.building.cell(level, x, y)
	match t:
		BuildingData.Cell.WALL:
			_block(x, y, 0.0, _wall_height(x, y), _structure_color(PlanStyle.CELL_COLORS[t]))
		BuildingData.Cell.WINDOW:
			_draw_window(x, y)
		BuildingData.Cell.DOOR:
			_draw_door(x, y)
	if level == sim.building.levels()[0] and Vector2i(x, y) in sim.building.hydrants:
		_box(Vector2(x + 0.3, y + 0.3), Vector2(x + 0.7, y + 0.7), 0.0, HYDRANT_M, PlanStyle.HYDRANT_COLOR, PlanStyle.HYDRANT_COLOR)
		var label := proj.to_screen(Vector2(x + 0.5, y + 0.5), HYDRANT_M + 0.4)
		draw_string(PlanStyle.font(), label + Vector2(-30, 0), "소화전", HORIZONTAL_ALIGNMENT_CENTER, 60, 13, PlanStyle.HYDRANT_COLOR.lightened(0.4))
	var b := sim.building
	if b.has_standpipe() and ((level == b.levels()[0] and Vector2i(x, y) == b.fdc) or Vector3i(x, y, level) in b.outlets):
		var is_fdc := Vector2i(x, y) == b.fdc and level == b.levels()[0]
		var sc := PlanStyle.STANDPIPE_COLOR
		_box(Vector2(x + 0.2, y + 0.2), Vector2(x + 0.8, y + 0.8), 0.0, 0.8, sc, sc)
		var sl := proj.to_screen(Vector2(x + 0.5, y + 0.5), 1.2)
		var txt := "송수구%s" % (" (연결)" if sim.water.fdc_vehicle >= 0 else "") if is_fdc else "방수구"
		draw_string(PlanStyle.font(), sl + Vector2(-50, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, 100, 13, sc.lightened(0.4))
	if level == sim.building.levels()[0] and Vector2i(x, y) == sim.gas.valve and sim.gas.known(sim.command.survey):
		var gc := PlanStyle.GAS_COLOR if sim.gas.open else PlanStyle.GAS_COLOR.darkened(0.5)
		_box(Vector2(x + 0.25, y + 0.25), Vector2(x + 0.75, y + 0.75), 0.0, 0.9, gc, gc)
		var gl := proj.to_screen(Vector2(x + 0.5, y + 0.5), 1.3)
		draw_string(PlanStyle.font(), gl + Vector2(-60, 0), "%s%s" % [sim.gas.valve_text, "" if sim.gas.open else " (차단)"], HORIZONTAL_ALIGNMENT_CENTER, 120, 13, gc.lightened(0.4))
	var fh := _furniture_height(x, y)
	if fh > 0.0:
		var color := THERMAL_FURNITURE if thermal else _furniture_color(x, y)
		_block(x, y, 0.0, fh, color)
	_draw_flame(x, y, fh)


## 문: 닫힘(블록) / 열림(통로) / 잠김(표시) / 파괴(잔해). 작업 중이면 진행 막대.
func _draw_door(x: int, y: int) -> void:
	var o: Opening = _opening_of.get(Vector3i(x, y, level))
	if o == null:
		return
	var top := proj.to_screen(Vector2(x + 0.5, y + 0.5), minf(DOOR_TOP_M, _wall_height(x, y)) + 0.3)
	var first := Vector2i(x, y) == o.cells[0]
	if not o.is_open:
		_block(x, y, 0.0, minf(DOOR_TOP_M, _wall_height(x, y)), _structure_color(PlanStyle.CELL_COLORS[BuildingData.Cell.DOOR]))
		if o.locked and first and not thermal:
			draw_string(PlanStyle.font(), top + Vector2(-30, 0), "잠김", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color("ffcc80"))
	elif o.forced:
		_block(x, y, 0.0, 0.12, _structure_color(Color("5d4037")))
		if first and not thermal:
			draw_string(PlanStyle.font(), top + Vector2(-30, 0), "파괴", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color("bcaaa4"))
	var task := sim.doors.task_of(o)
	if task and first:
		var r := Rect2(top.x - 22.0, top.y + 4.0, 44.0, 5.0)
		draw_rect(r, PlanStyle.TANK_BG)
		draw_rect(Rect2(r.position, Vector2(r.size.x * task.progress / task.required, r.size.y)), Color("ffb74d"))
		if task.waiting_people:
			draw_string(PlanStyle.font(), top + Vector2(-40, 22), "인원 부족", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color("ff8a80"))


func _draw_window(x: int, y: int) -> void:
	var h := _wall_height(x, y)
	var wall := _structure_color(PlanStyle.CELL_COLORS[BuildingData.Cell.WALL])
	var o: Opening = _opening_of.get(Vector3i(x, y, level))
	var glass := GLASS_COLOR if not (o and o.broken) else Color(0, 0, 0, 0)
	if o and not o.broken and o in _lit:
		glass = PlanStyle.LIT_WINDOW
	if thermal:
		glass = THERMAL_STRUCTURE
	if h < WINDOW_SILL_M:
		_block(x, y, 0.0, h, wall, glass if glass.a > 0.0 else wall.darkened(0.5))
		return
	_block(x, y, 0.0, WINDOW_SILL_M, wall)
	if glass.a > 0.0:
		_block(x, y, WINDOW_SILL_M, WINDOW_TOP_M, glass)
	_block(x, y, WINDOW_TOP_M, h, wall)


func _draw_flame(x: int, y: int, base_m: float) -> void:
	var grid := sim.fire.grid
	var i := grid.index(level, x, y)
	# 열화상에서는 화염 모양 대신 바닥 온도 색으로만 보인다
	if thermal:
		return
	var p := sim.perception
	var fade := 1.0
	var intensity := 0.5
	if p.is_visible(level, x, y):
		if grid.state[i] != FuelGrid.State.BURNING:
			return
		intensity = clampf(grid.hrr[i] / maxf(grid.peak_kw(i), 1.0), 0.15, 1.0)
	elif p.is_seen(level, x, y) and p.seen_burning[i] == 1:
		fade = 0.4  # 마지막으로 봤을 때 타고 있었음
	else:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var seed_f := float((x * 73856093) ^ (y * 19349663)) * 0.0001
	var flicker := 0.8 + 0.2 * sin(t * 8.0 + seed_f) * sin(t * 4.7 + seed_f * 1.3)
	var height := (0.35 + 1.15 * intensity) * flicker
	var c := Vector2(x + 0.5, y + 0.5)
	var base := proj.to_screen(c, base_m)
	var w := IsoProjection.HALF_W * 0.55
	var sway := Vector2(sin(t * 3.1 + seed_f) * 3.0, 0)
	draw_colored_polygon(_ellipse(base, w * 1.3, w * 0.65), Color(1.0, 0.45, 0.1, 0.35 * intensity * fade))
	draw_colored_polygon(_flame_shape(base, w, proj.to_screen(c, base_m + height) + sway), Color(0.95, 0.3, 0.06, 0.9 * fade))
	draw_colored_polygon(_flame_shape(base, w * 0.55, proj.to_screen(c, base_m + height * 0.6) + sway * 0.6), Color(1.0, 0.8, 0.3, 0.95 * fade))


func _draw_unit(ff: Firefighter, alpha: float) -> void:
	var p := UnitsView.display_pos(ff, alpha)
	var squad := sim.units.squads[ff.squad_id]
	var crew := sim.units.get_crew(ff.crew_id)
	var feet := proj.to_screen(p, 0.0)
	draw_colored_polygon(_ellipse(feet, 10, 5), Color(0, 0, 0, 0.3))
	if crew.id in selection.selected:
		draw_polyline(_ellipse(feet, 13, 6.5, true), PlanStyle.SELECTION, 2.0)
	# 열 스트레스가 쌓이면 붉게
	var body_color := squad.color.lerp(Color(1.0, 0.25, 0.1), clampf(ff.heat_stress, 0.0, 1.0) * 0.7)
	if ff.incapacitated:
		# 쓰러진 대원: 바닥에 누운 모습 + 경고 표시
		draw_colored_polygon(_ellipse(feet, 16, 6), body_color.darkened(0.2))
		draw_circle(feet + Vector2(14, -2), UNIT_HEAD_R * 0.8, Color.WHITE)
		var warn := proj.to_screen(p, 0.9)
		draw_string(PlanStyle.font(), warn + Vector2(-40, 0), "행동 불능", HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color("ff6b6b"))
		return
	var scale := CROUCH_SCALE if ff.crouched else 1.0
	var top := proj.to_screen(p, UNIT_BODY_M * scale)
	var body := Rect2(feet.x - UNIT_HALF_W, top.y, UNIT_HALF_W * 2.0, feet.y - top.y)
	draw_rect(body, body_color)
	draw_rect(body, PlanStyle.UNIT_OUTLINE, false, 1.0)
	var head := proj.to_screen(p, UNIT_HEAD_M * scale)
	var helmet := Color.WHITE if ff == crew.leader else squad.color.lightened(0.45)
	draw_circle(head, UNIT_HEAD_R, helmet)
	draw_arc(head, UNIT_HEAD_R, 0.0, TAU, 16, PlanStyle.UNIT_OUTLINE, 1.0)
	var label := proj.to_screen(p, UNIT_LABEL_M * scale)
	draw_string(PlanStyle.font(), label + Vector2(-20, 0), str(crew.number), HORIZONTAL_ALIGNMENT_CENTER, 40, 12, Color.WHITE)
	_draw_air_bar(label + Vector2(0, 4), ff)


## 현장지휘관: 흰 몸체·빨간 안전모, "지휘" 표시
func _draw_commander(alpha: float) -> void:
	var c := sim.command.commander
	var p := UnitsView.display_pos(c, alpha)
	var feet := proj.to_screen(p, 0.0)
	draw_colored_polygon(_ellipse(feet, 10, 5), Color(0, 0, 0, 0.3))
	if selection.commander_selected:
		draw_polyline(_ellipse(feet, 13, 6.5, true), PlanStyle.SELECTION, 2.0)
	var top := proj.to_screen(p, UNIT_BODY_M)
	var body := Rect2(feet.x - UNIT_HALF_W, top.y, UNIT_HALF_W * 2.0, feet.y - top.y)
	draw_rect(body, PlanStyle.COMMANDER_BODY)
	draw_rect(body, PlanStyle.UNIT_OUTLINE, false, 1.0)
	var head := proj.to_screen(p, UNIT_HEAD_M)
	draw_circle(head, UNIT_HEAD_R, PlanStyle.COMMANDER_HELMET)
	draw_arc(head, UNIT_HEAD_R, 0.0, TAU, 16, PlanStyle.UNIT_OUTLINE, 1.0)
	var label := proj.to_screen(p, UNIT_LABEL_M)
	draw_string(PlanStyle.font(), label + Vector2(-30, 0), "지휘", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color.WHITE)


## 관계인: 사복 차림, 머리 위 이름
func _draw_witness(w: Witness) -> void:
	var feet := proj.to_screen(w.pos, 0.0)
	draw_colored_polygon(_ellipse(feet, 10, 5), Color(0, 0, 0, 0.3))
	var top := proj.to_screen(w.pos, UNIT_BODY_M)
	var body := Rect2(feet.x - UNIT_HALF_W, top.y, UNIT_HALF_W * 2.0, feet.y - top.y)
	draw_rect(body, PlanStyle.WITNESS_BODY)
	draw_rect(body, PlanStyle.UNIT_OUTLINE, false, 1.0)
	var head := proj.to_screen(w.pos, UNIT_HEAD_M)
	draw_circle(head, UNIT_HEAD_R, PlanStyle.WITNESS_HEAD)
	draw_arc(head, UNIT_HEAD_R, 0.0, TAU, 16, PlanStyle.UNIT_OUTLINE, 1.0)
	var label := proj.to_screen(w.pos, UNIT_LABEL_M)
	draw_string(PlanStyle.font(), label + Vector2(-60, 0), "관계인 · %s" % w.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, PlanStyle.WITNESS_HEAD)


## 공기호흡기 잔량 막대 (경보 이하면 빨강)
func _draw_air_bar(at: Vector2, ff: Firefighter) -> void:
	var r := Rect2(at.x - 11.0, at.y, 22.0, 4.0)
	draw_rect(r, PlanStyle.TANK_BG)
	var f := ff.air_ratio()
	draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), PlanStyle.AIR_LOW if f < 0.18 else PlanStyle.AIR_OK)


# --- 차량·수관·방수 ---

func _draw_hoses() -> void:
	for h in sim.water.hoses:
		var pts := PackedVector2Array()
		for p in h.points:
			if p.z == level:
				pts.append(proj.to_screen(Vector2(p.x + 0.5, p.y + 0.5), 0.03))
			else:
				if pts.size() >= 2:
					draw_polyline(pts, PlanStyle.HOSE_COLOR, 2.5)
				pts.clear()
		if pts.size() >= 2:
			draw_polyline(pts, PlanStyle.HOSE_COLOR, 2.5)


func _draw_vehicle(v: Vehicle, alpha: float) -> void:
	var center := v.prev_pos.lerp(v.pos, alpha)
	var fp := v.footprint(center)
	# 도로가 화면 앞쪽이라 실제 높이로 그리면 건물을 가린다: 앞쪽 벽처럼 낮게 자르고 약간 투명하게
	var h := minf(v.height_m, VEHICLE_CUT_M)
	var color := THERMAL_FURNITURE if thermal else v.color
	color.a = VEHICLE_ALPHA
	_prism(fp, 0.0, h, color)
	# 앞쪽 1/4 운전석 지붕
	var cab := PackedVector2Array([fp[0].lerp(fp[1], 0.75), fp[1], fp[2], fp[3].lerp(fp[2], 0.75)])
	draw_colored_polygon(_lift(cab, h), Color(color.darkened(0.35), VEHICLE_ALPHA))
	if v.id in selection.selected_vehicles:
		var outline := _lift(fp, h)
		outline.append(outline[0])
		draw_polyline(outline, PlanStyle.SELECTION, 2.5)
	var label := proj.to_screen(center, h + 0.6)
	var text := v.short_name + (" · 후진" if v.reversing else "")
	draw_string(PlanStyle.font(), label + Vector2(-50, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 100, 14, Color.WHITE)
	var gauge := Rect2(label.x - 30.0, label.y + 6.0, 60.0, 7.0)
	draw_rect(gauge, PlanStyle.TANK_BG)
	var f := v.tank_l / v.tank_capacity if v.tank_capacity > 0.0 else 0.0
	draw_rect(Rect2(gauge.position, Vector2(gauge.size.x * f, gauge.size.y)), PlanStyle.TANK_FILL)


func _draw_sprays(alpha: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for h in sim.water.hoses:
		if not h.flowing or h.flow_fraction <= 0.0:
			continue
		var leader := sim.units.get_crew(h.crew_id).leader
		if leader.level != level:
			continue
		var from := proj.to_screen(UnitsView.display_pos(leader, alpha), NOZZLE_M)
		var to := proj.to_screen(h.impact, IMPACT_M)
		if h.pattern == HoseLine.Pattern.STRAIGHT:
			# 포물선을 그리며 날아가는 물방울
			var arc := PackedVector2Array()
			for k in 13:
				var f := k / 12.0
				arc.append(from.lerp(to, f) + Vector2(0, -sin(f * PI) * 16.0))
			draw_polyline(arc, Color(PlanStyle.WATER_COLOR, 0.45), 2.0)
			for k in 8:
				var f := fmod(k / 8.0 + t * 1.6, 1.0)
				draw_circle(from.lerp(to, f) + Vector2(0, -sin(f * PI) * 16.0), 2.4, PlanStyle.WATER_COLOR)
			draw_colored_polygon(_ellipse(to, 9, 4.5), Color(PlanStyle.WATER_COLOR, 0.5))
		else:
			var r := sim.water.radius_cells(h.pattern) * IsoProjection.HALF_W
			var side := (to - from).orthogonal().normalized() * r * 0.8
			draw_colored_polygon(PackedVector2Array([from, to + side, to - side]), PlanStyle.FOG_COLOR)
			draw_colored_polygon(_ellipse(to, r, r * 0.5), Color(PlanStyle.FOG_COLOR, 0.25))


## 바닥 다각형(셀 좌표)을 h0~h1 높이의 기둥으로 그린다. 보는 쪽 옆면과 윗면만 그린다.
func _prism(base: PackedVector2Array, h0: float, h1: float, color: Color) -> void:
	var center := Vector2.ZERO
	for p in base:
		center += p
	center /= base.size()
	for k in base.size():
		var a := base[k]
		var b := base[(k + 1) % base.size()]
		var n := (a + b) * 0.5 - center
		if n.x + n.y <= 0.01:
			continue
		var face := PackedVector2Array([proj.to_screen(a, h0), proj.to_screen(b, h0), proj.to_screen(b, h1), proj.to_screen(a, h1)])
		draw_colored_polygon(face, Color(color.darkened(SOUTH_SHADE if n.y >= n.x else EAST_SHADE), color.a))
	draw_colored_polygon(_lift(base, h1), color)


func _lift(base: PackedVector2Array, h: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in base:
		out.append(proj.to_screen(p, h))
	return out


# --- 연기층 ---

func _draw_smoke() -> void:
	var rooms: Array[Compartment] = []
	for c in sim.fire.comps:
		if c.level == level:
			rooms.append(c)
	rooms.sort_custom(func(a: Compartment, b: Compartment) -> bool:
		return a.rect.end.x + a.rect.end.y < b.rect.end.x + b.rect.end.y)
	# 연기층 하단 높이에 반투명 평면 하나를 그린다. 연기층이 내려올수록 평면이 바닥에 가까워지고,
	# 대원 머리 높이를 지나면 대원 상체가 연기에 묻혀 보인다.
	# 지금 보이는 방은 실제 상태, 본 적 있는 방은 마지막으로 확인한 상태(흐리게), 모르는 방은 그리지 않는다
	var p := sim.perception
	for c in rooms:
		var depth := c.layer_depth
		var vis := sim.fire.visibility_m(c)
		var fade := 1.0
		if not p.room_visible(c):
			if p.room_seen[c.index] == 0:
				continue
			depth = p.room_seen_depth[c.index]
			vis = p.room_seen_visibility[c.index]
			fade = 0.5
		depth = clampf(depth, 0.0, CEILING_M)
		if depth < 0.05:
			continue
		var density := 1.0 - clampf(vis / 10.0, 0.0, 1.0)
		var a := (SMOKE_MIN_ALPHA + SMOKE_DENSITY_ALPHA * density) * fade
		var r := c.rect
		var h := CEILING_M - depth
		var plane := PackedVector2Array([
			proj.to_screen(Vector2(r.position), h), proj.to_screen(Vector2(r.end.x, r.position.y), h),
			proj.to_screen(Vector2(r.end), h), proj.to_screen(Vector2(r.position.x, r.end.y), h),
		])
		draw_colored_polygon(plane, Color(FireView.SMOKE_COLOR, a))
		plane.append(plane[0])
		draw_polyline(plane, Color(FireView.SMOKE_COLOR.darkened(0.3), minf(1.0, a + 0.15)), 1.5)
		if c.rollover and p.room_visible(c):
			_draw_rollover(r, h)
	_draw_smoke_plumes()


func _room_searched(room_id: String) -> bool:
	for c in sim.fire.comps:
		if c.level == level and c.id == room_id:
			return c.searched_tick >= 0
	return false


## 롤오버 징후: 연기층 위로 굽이치는 화염 (플래시오버 임박)
func _draw_rollover(r: Rect2i, h: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for k in 4:
		var f := (k + 0.5) / 4.0
		var pts := PackedVector2Array()
		for j in 13:
			var u := j / 12.0
			var wave := sin(u * 10.0 + t * 6.0 + k) * 0.25
			pts.append(proj.to_screen(Vector2(lerpf(r.position.x, r.end.x, u), lerpf(r.position.y, r.end.y, f) + wave), h + 0.05))
		draw_polyline(pts, Color(1.0, 0.45 + 0.2 * sin(t * 9.0 + k), 0.1, 0.75), 2.5)


func _draw_blasts() -> void:
	for blast in sim.hazards.blasts:
		if int(blast[1]) != level:
			continue
		var age := float(sim.clock.tick - int(blast[2])) / HazardSystem.BLAST_SHOW_TICKS
		var at := proj.to_screen(blast[0], 1.0)
		draw_circle(at, 20.0 + age * 90.0, Color(1.0, 0.5, 0.1, 0.6 * (1.0 - age)))
		draw_circle(at, 10.0 + age * 50.0, Color(1.0, 0.9, 0.4, 0.8 * (1.0 - age)))


## 요구조자: 누운 모습, 상태별 색, 이름표. 업혀 있으면 대원 어깨 위에 작게
func _draw_victim(v: Victim) -> void:
	var color: Color = PlanStyle.VICTIM_COLORS[v.state]
	if v.carried_by >= 0:
		var at := proj.to_screen(v.pos, 1.5)
		draw_colored_polygon(_ellipse(at, 12, 4), color)
		return
	if v.state == Victim.State.RESCUED:
		var p := sim.ems.patient_of(v.id)
		if p == null or not sim.ems.on_scene(p):
			return
		var tag: Color = EmsSystem.TRIAGE_COLORS[p.triage]
		var at := proj.to_screen(v.pos, 0.05)
		draw_colored_polygon(_ellipse(at + Vector2(0, -3), 13, 5), color)
		draw_circle(at + Vector2(12, -5), 5.0, tag)
		draw_string(PlanStyle.font(), at + Vector2(-70, -14), "%s · %s · %s" % [v.label(), sim.ems.triage_name(p), EmsSystem.STAGE_NAMES[p.stage]], HORIZONTAL_ALIGNMENT_CENTER, 140, 12, tag.lightened(0.3))
		return
	var feet := proj.to_screen(v.pos, 0.05)
	draw_colored_polygon(_ellipse(feet, 15, 6), Color(0, 0, 0, 0.35))
	draw_colored_polygon(_ellipse(feet + Vector2(0, -3), 13, 5), color)
	draw_circle(feet + Vector2(12, -5), 5.0, color.lightened(0.3))
	draw_string(PlanStyle.font(), feet + Vector2(-50, -14), "%s · %s" % [v.label(), v.state_name()], HORIZONTAL_ALIGNMENT_CENTER, 100, 12, color.lightened(0.4))


## 바깥으로 연기가 뿜어져 나오는 창·문 (밖에서 늘 보이는 상황 판단 단서)
func _draw_smoke_plumes() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for line in smoke_outlets(sim, level):
		var at: Vector2 = line[0]
		var strength: float = line[1]
		for k in 5:
			var f := fmod(k / 5.0 + t * 0.35, 1.0)
			var pos := proj.to_screen(at, 1.6 + f * 2.5) + Vector2(sin(t + k) * 6.0, 0)
			var r := (8.0 + f * 18.0) * (0.6 + 0.4 * strength)
			draw_circle(pos, r, Color(PlanStyle.SMOKE_PLUME, PlanStyle.SMOKE_PLUME.a * (1.0 - f) * strength))


## 연기가 바깥으로 나오는 개구부: [위치(셀 좌표), 세기 0~1] 목록
static func smoke_outlets(p_sim: SimWorld, lv: int) -> Array[Array]:
	var out: Array[Array] = []
	for o in p_sim.fire.openings:
		if o.level != lv or o.room_b != Opening.OUTSIDE or not o.is_open:
			continue
		var c := p_sim.fire.comps[o.room_a]
		if c.height - c.layer_depth >= o.top or c.soot <= 0.001:
			continue
		var center := Vector2.ZERO
		for cell in o.cells:
			center += Vector2(cell) + Vector2(0.5, 0.5)
		var density := 1.0 - clampf(p_sim.fire.visibility_m(c) / 10.0, 0.0, 1.0)
		out.append([center / o.cells.size(), clampf(0.3 + density, 0.0, 1.0)])
	return out


# --- 정보 안개 도우미 ---

func _fog_alpha(x: int, y: int) -> float:
	var p := sim.perception
	if not p.enabled or p.is_visible(level, x, y):
		return 0.0
	return FOG_SEEN_ALPHA if p.is_seen(level, x, y) else FOG_UNKNOWN_ALPHA


## 그을음(탄 자리): 보이는 곳은 실제, 아니면 마지막으로 본 상태
func _cell_burnt(x: int, y: int) -> bool:
	var i := sim.fire.grid.index(level, x, y)
	if sim.perception.is_visible(level, x, y):
		return sim.fire.grid.state[i] == FuelGrid.State.BURNT
	return sim.perception.is_seen(level, x, y) and sim.perception.seen_burnt[i] == 1


# --- 도형 도우미 ---

func _tile(x: float, y: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		proj.to_screen(Vector2(x, y), h), proj.to_screen(Vector2(x + 1, y), h),
		proj.to_screen(Vector2(x + 1, y + 1), h), proj.to_screen(Vector2(x, y + 1), h),
	])


## 셀 하나 크기의 상자. 보는 쪽 두 옆면(남·동)과 윗면을 그린다.
func _block(x: int, y: int, h0: float, h1: float, color: Color, top_color := Color(0, 0, 0, 0)) -> void:
	if h1 <= h0:
		return
	_box(Vector2(x, y), Vector2(x + 1, y + 1), h0, h1, color, color, top_color)


func _box(p0: Vector2, p1: Vector2, h0: float, h1: float, color: Color, side_color: Color, top_color := Color(0, 0, 0, 0)) -> void:
	var south := PackedVector2Array([
		proj.to_screen(Vector2(p0.x, p1.y), h0), proj.to_screen(Vector2(p1.x, p1.y), h0),
		proj.to_screen(Vector2(p1.x, p1.y), h1), proj.to_screen(Vector2(p0.x, p1.y), h1),
	])
	var east := PackedVector2Array([
		proj.to_screen(Vector2(p1.x, p0.y), h0), proj.to_screen(Vector2(p1.x, p1.y), h0),
		proj.to_screen(Vector2(p1.x, p1.y), h1), proj.to_screen(Vector2(p1.x, p0.y), h1),
	])
	var top := PackedVector2Array([
		proj.to_screen(p0, h1), proj.to_screen(Vector2(p1.x, p0.y), h1),
		proj.to_screen(p1, h1), proj.to_screen(Vector2(p0.x, p1.y), h1),
	])
	draw_colored_polygon(south, Color(side_color.darkened(SOUTH_SHADE), side_color.a))
	draw_colored_polygon(east, Color(side_color.darkened(EAST_SHADE), side_color.a))
	draw_colored_polygon(top, top_color if top_color.a > 0.0 else color)


func _flame_shape(base: Vector2, half_w: float, tip: Vector2) -> PackedVector2Array:
	var mid_y := lerpf(base.y, tip.y, 0.45)
	return PackedVector2Array([
		base + Vector2(-half_w, 0), Vector2(base.x - half_w * 0.8, mid_y), tip,
		Vector2(base.x + half_w * 0.8, mid_y), base + Vector2(half_w, 0),
	])


static func _ellipse(center: Vector2, rx: float, ry: float, closed := false) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 16
	for k in n + (1 if closed else 0):
		var a := TAU * k / n
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _wall_height(x: int, y: int) -> float:
	var fp: Rect2i = _footprint[level]
	if y == fp.position.y or x == fp.position.x:
		return CEILING_M
	return WALL_CUT_M


func _furniture_height(x: int, y: int) -> float:
	var heights: PackedFloat32Array = _furniture_h[level]
	if heights[y * sim.building.width + x] <= 0.0 or _cell_burnt(x, y):
		return 0.0
	return heights[y * sim.building.width + x]


func _furniture_color(x: int, y: int) -> Color:
	var grid := sim.fire.grid
	var i := grid.index(level, x, y)
	var base := Color("a7b0ba")
	var m := grid.material_name(i)
	if m != "" and sim.fire.config.materials.has(m):
		base = Color(str(sim.fire.config.materials[m].get("color", "#a7b0ba")))
	if grid.state[i] == FuelGrid.State.BURNING and sim.perception.is_visible(level, x, y):
		base = base.lerp(Color(0.2, 0.12, 0.08), 0.6)
	return base


func _structure_color(color: Color) -> Color:
	return THERMAL_STRUCTURE if thermal else color


func _cell_temperature(x: int, y: int) -> float:
	var fire := sim.fire
	var temp := fire.config.value("ambient_temp_c")
	var c := fire.compartment_at(level, x, y)
	if c:
		temp = c.t_lower + (c.t_upper - c.t_lower) * 0.5
	var o: Opening = _opening_of.get(Vector3i(x, y, level))
	if o:
		temp = fire.comps[o.room_a].t_upper
		if o.room_b != Opening.OUTSIDE:
			temp = maxf(temp, fire.comps[o.room_b].t_upper)
	var i := fire.grid.index(level, x, y)
	if fire.grid.state[i] == FuelGrid.State.BURNING:
		temp = maxf(temp, 400.0 + 500.0 * fire.grid.hrr[i] / maxf(fire.grid.peak_kw(i), 1.0))
	return temp
