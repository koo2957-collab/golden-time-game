class_name FireView
extends Node2D
## 화염·연기·그을음 표시, 그리고 열화상 화면.
## - 일반 화면: 방마다 연기층 깊이와 농도에 따라 회색으로 덮고, 타는 셀에 일렁이는 화염을 그린다.
## - 열화상 화면: 셀마다 온도를 색으로 칠한다 (실제 열화상카메라처럼 방 이름 등은 보이지 않음).

const SMOKE_COLOR := Color(0.16, 0.16, 0.17)
const SMOKE_MAX_ALPHA := 0.88
const CHAR_COLOR := Color(0.12, 0.1, 0.09, 0.8)
const FOG_COLOR := Color(0.04, 0.05, 0.07)
const FOG_UNKNOWN_ALPHA := 0.8
const FOG_SEEN_ALPHA := 0.38
const THERMAL_MAX_C := 900.0
## 열화상 팔레트 (0 = 외기 온도, 1 = THERMAL_MAX_C)
const THERMAL_STOPS: Array[Array] = [
	[0.0, Color("0a0a1e")],
	[0.12, Color("3b1a6b")],
	[0.3, Color("9c1f6e")],
	[0.5, Color("e2422d")],
	[0.7, Color("f89a1c")],
	[0.88, Color("fde74c")],
	[1.0, Color("ffffff")],
]

var sim: SimWorld
var level := 1
var thermal := false


func setup(p_sim: SimWorld) -> void:
	sim = p_sim


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	if thermal:
		_draw_thermal()
	else:
		_draw_fire_and_smoke()


func _draw_fire_and_smoke() -> void:
	var fire := sim.fire
	var grid := fire.grid
	var px := PlanStyle.CELL_PX
	var t := Time.get_ticks_msec() / 1000.0
	var p := sim.perception
	# 그을음(탄 자리): 보이는 곳은 실제, 아니면 마지막으로 본 상태
	for i in grid.fuel_cells:
		var cell := grid.cell_of(i)
		if cell.z != level:
			continue
		var burnt := grid.state[i] == FuelGrid.State.BURNT
		if not p.is_visible(level, cell.x, cell.y):
			burnt = p.is_seen(level, cell.x, cell.y) and p.seen_burnt[i] == 1
		if burnt:
			draw_rect(Rect2(cell.x * px, cell.y * px, px, px), CHAR_COLOR)
	# 연기: 연기층이 내려올수록, 짙을수록 진하게 (본 적만 있는 방은 마지막 상태를 흐리게)
	var smoke_alpha := {}
	for c in fire.comps:
		if c.level != level:
			continue
		var a := _smoke_alpha(c)
		if not p.room_visible(c):
			a = _seen_smoke_alpha(c) if p.room_seen[c.index] == 1 else 0.0
		smoke_alpha[c.index] = a
		if a > 0.01:
			draw_rect(Rect2(Vector2(c.rect.position) * px, Vector2(c.rect.size) * px), Color(SMOKE_COLOR, a))
	_draw_fog()
	# 화염: 연기 속에서도 불빛은 비쳐 보이도록 연기 위에 그린다
	for i in grid.fuel_cells:
		var cell := grid.cell_of(i)
		if cell.z != level:
			continue
		var fade := 1.0
		if p.is_visible(level, cell.x, cell.y):
			if grid.state[i] != FuelGrid.State.BURNING:
				continue
		elif p.is_seen(level, cell.x, cell.y) and p.seen_burning[i] == 1:
			fade = 0.4
		else:
			continue
		var intensity := clampf(grid.hrr[i] / maxf(grid.peak_kw(i), 1.0), 0.15, 1.0) if fade == 1.0 else 0.5
		var seed_f := float((cell.x * 73856093) ^ (cell.y * 19349663)) * 0.0001
		var flicker := 0.75 + 0.25 * sin(t * 9.0 + seed_f) * sin(t * 5.3 + seed_f * 1.7)
		var room_i: int = grid.room[i]
		var dim := (1.0 - 0.45 * float(smoke_alpha.get(room_i, 0.0))) * fade
		var center := Vector2(cell.x + 0.5, cell.y + 0.5) * px
		var r := px * 0.55 * (0.6 + 0.4 * intensity) * flicker
		draw_circle(center, r * 1.25, Color(0.85, 0.18, 0.05, 0.45 * dim * intensity))
		draw_circle(center, r, Color(1.0, 0.45, 0.08, 0.8 * dim))
		draw_circle(center, r * 0.5, Color(1.0, 0.85, 0.35, 0.85 * dim * intensity))


func _draw_thermal() -> void:
	var fire := sim.fire
	var b := sim.building
	var px := PlanStyle.CELL_PX
	var t_amb := fire.config.value("ambient_temp_c")
	draw_rect(Rect2(Vector2.ZERO, Vector2(b.width, b.height) * px), thermal_color(t_amb, t_amb))
	for y in b.height:
		for x in b.width:
			var cell_type := b.cell(level, x, y)
			if cell_type == BuildingData.Cell.VOID:
				continue
			var rect := Rect2(x * px, y * px, px, px)
			if cell_type == BuildingData.Cell.WALL:
				draw_rect(rect, Color(0.05, 0.05, 0.08))
				continue
			# 열화상카메라가 지금 보고 있는 곳만 온도가 나온다
			if cell_type in BuildingData.OUTDOOR or sim.perception.is_thermal_visible(level, x, y):
				draw_rect(rect, thermal_color(cell_temperature(level, x, y), t_amb))
			else:
				draw_rect(rect, Color(0.03, 0.03, 0.05))


## 열화상에 보일 셀 온도: 방의 상부층 온도에 타는 셀의 화염 온도를 더한다.
func cell_temperature(lv: int, x: int, y: int) -> float:
	var fire := sim.fire
	var t_amb := fire.config.value("ambient_temp_c")
	var temp := t_amb
	var c := fire.compartment_at(lv, x, y)
	if c:
		temp = c.t_upper
	elif sim.building.cell(lv, x, y) in [BuildingData.Cell.DOOR, BuildingData.Cell.WINDOW]:
		var o := fire.opening_at(Vector3i(x, y, lv))
		if o:
			temp = fire.comps[o.room_a].t_upper
			if o.room_b != Opening.OUTSIDE:
				temp = maxf(temp, fire.comps[o.room_b].t_upper)
	var i := fire.grid.index(lv, x, y)
	if fire.grid.state[i] == FuelGrid.State.BURNING:
		var intensity := fire.grid.hrr[i] / maxf(fire.grid.peak_kw(i), 1.0)
		temp = maxf(temp, 400.0 + 500.0 * intensity)
	return temp


static func thermal_color(temp_c: float, t_amb: float) -> Color:
	var f := clampf((temp_c - t_amb) / (THERMAL_MAX_C - t_amb), 0.0, 1.0)
	for k in range(1, THERMAL_STOPS.size()):
		var hi: Array = THERMAL_STOPS[k]
		if f <= hi[0]:
			var lo: Array = THERMAL_STOPS[k - 1]
			return (lo[1] as Color).lerp(hi[1], (f - lo[0]) / (hi[0] - lo[0]))
	return THERMAL_STOPS[-1][1]


static func thermal_gradient() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(THERMAL_STOPS.map(func(s: Array) -> float: return s[0]))
	g.colors = PackedColorArray(THERMAL_STOPS.map(func(s: Array) -> Color: return s[1]))
	return g


## 정보 안개: 모르는 실내는 짙게, 본 적만 있는 곳은 옅게 덮는다
func _draw_fog() -> void:
	var p := sim.perception
	if not p.enabled:
		return
	var b := sim.building
	var px := PlanStyle.CELL_PX
	for y in b.height:
		for x in b.width:
			var t := b.cell(level, x, y)
			if t in BuildingData.OUTDOOR or t == BuildingData.Cell.WALL or t == BuildingData.Cell.WINDOW:
				continue
			if p.is_visible(level, x, y):
				continue
			var a := FOG_SEEN_ALPHA if p.is_seen(level, x, y) else FOG_UNKNOWN_ALPHA
			draw_rect(Rect2(x * px, y * px, px, px), Color(FOG_COLOR, a))


func _seen_smoke_alpha(c: Compartment) -> float:
	var p := sim.perception
	var depth_f := clampf(p.room_seen_depth[c.index] / c.height, 0.0, 1.0)
	var density := 1.0 - clampf(p.room_seen_visibility[c.index] / 10.0, 0.0, 1.0)
	return SMOKE_MAX_ALPHA * depth_f * density * 0.5


func _smoke_alpha(c: Compartment) -> float:
	var depth_f := clampf(c.layer_depth / c.height, 0.0, 1.0)
	var density := 1.0 - clampf(sim.fire.visibility_m(c) / 10.0, 0.0, 1.0)
	return SMOKE_MAX_ALPHA * depth_f * density
