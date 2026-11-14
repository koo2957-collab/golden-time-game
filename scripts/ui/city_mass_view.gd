class_name CityMassView
extends Node2D
## 전체 지도의 도시 배경 (기획안 4-4, 결정 ①): 화재 건물·도로·소화전·차량 등 활동에 영향을 주는 것만 색을 넣고,
## 나머지 건물은 흰색 매스 모형(아이소 박스, 윗면 밝게·옆면 조금 어둡게)으로만 그린다.
## 2026-11-14 (사용자 결정): 화면을 꽉 채우는 도시 — 배치는 CityPlan(격자 도로망·필지·안전센터·출동 경로)이 만들고
## 여기서는 그리기만 한다. 길·블록 바닥·중앙선·횡단보도·건물·옥탑, 밤에는 창문 불빛과 가로등 점.
## 출동 중에는 그 위에 선착 소방차(구운 그림)가 안전센터에서 길을 따라 달리고, 대상 건물에서 연기 기둥이 오른다.
## 텍스처·그림자 없이 색만. 도시 전체를 사각형 묶음 몇 개로 한 번 만들어 두고 다시 만들지 않는다 (사무용 PC, 기획안 9-5).
## 수치·색은 data/ui/city.json.

## 횡단보도를 그리는 범위 (현장 가운데에서, 칸) — 멀리서는 보이지 않아 가까운 교차로만
const CROSSWALK_REACH := 170.0

var proj: IsoProjection
var plan: CityPlan
## 밤 정도 (0 = 낮 … 1 = 밤). setup 전에 넣는다
var night := 0.0
## 출동 진행률 (0~1, 출동 중이 아니면 음수) — World가 넣는다 (P9-1 출동 단계)
var progress: Callable
## 만든 그림량 (점검용)
var quad_count := 0
var window_count := 0
var lamp_count := 0
## 출동 중 화면(소방차·연기 기둥·이름표)을 그리는 겹
var _icons: Node2D
var _overlay_drawn := false
var _sim: SimWorld
## 그리기 묶음 [{points, colors, indices}]
var _batches: Array[Dictionary] = []
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _batch_limit := 2400


func setup(building: BuildingData, p_proj: IsoProjection, p_seed: int, p_sim: SimWorld = null) -> void:
	proj = p_proj
	_sim = p_sim
	if _icons == null:
		_icons = Node2D.new()
		# 현장 그림(건물·바닥)보다 위에 그린다 — 소방차가 현장 지도 가장자리에 닿아도 가려지지 않게
		_icons.z_index = 20
		_icons.draw.connect(_draw_overlay)
		add_child(_icons)
	var rows := Vector2i(-1, -1)
	for lv in building.levels():
		rows = building.road_rows(lv)
		if rows.x >= 0:
			break
	var lane_y := -1.0
	if _sim and not _sim.units.vehicles.is_empty():
		lane_y = _sim.units.vehicles[0].pos.y
	plan = CityPlan.new()
	plan.generate(Vector2i(building.width, building.height), rows, hash("city:%s:%d" % [building.id, p_seed]), lane_y)
	build_mesh()
	queue_redraw()


func _color(key: String, fallback: Color) -> Color:
	var c: Dictionary = plan.p.get("colors", {})
	return Color(str(c[key])) if c.has(key) else fallback


## 도시 전체를 사각형 묶음으로 만든다 (뒤에서 앞 순서 — 그리는 순서가 곧 가림 순서)
func build_mesh() -> void:
	_batches.clear()
	_points = PackedVector2Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()
	quad_count = 0
	window_count = 0
	lamp_count = 0
	_batch_limit = maxi(200, int(plan.num("quads_per_batch", 2400)))
	var road := _color("road", Color("313a45"))
	var lane := _color("lane", Color("d9cf9c"))
	var bounds := Rect2(plan.bounds)
	# 땅: 길 색으로 전체를 깔고 그 위에 블록 바닥
	_rect(bounds, 0.0, road)
	for pad in plan.pads:
		_rect(Rect2(pad), 0.0, _color("pad", Color("d4d6d1")))
	for yard in plan.yards:
		_rect(Rect2(yard), 0.0, _color("yard", Color("c3c6c1")))
	# 중앙선: 길마다 한 줄
	for r in plan.row_streets:
		_rect(Rect2(bounds.position.x, (r.x + r.y) * 0.5 - 0.15, bounds.size.x, 0.3), 0.0, Color(lane, 0.6))
	for c in plan.col_streets:
		_rect(Rect2((c.x + c.y) * 0.5 - 0.15, bounds.position.y, 0.3, bounds.size.y), 0.0, Color(lane, 0.6))
	_crosswalks()
	var lit := night > 0.05 and not DisplaySettings.low_spec
	if lit:
		_lamps()
	# 건물 (뒤에서 앞으로)
	var floor_m := plan.num("floor_m", 3.0)
	for lot: Dictionary in plan.lots:
		var rect := Rect2(lot.rect as Rect2i)
		var h := float(lot.floors) * floor_m
		var shade := float(lot.shade)
		var station: bool = lot.kind == "station"
		var top := _color("station_top", Color("c0392b")) if station else _shade(_color("top", Color("f5f5f2")), shade)
		var south := _color("station_south", Color("e7d9d6")) if station else _shade(_color("south", Color("dbdee0")), shade)
		var east := _color("station_east", Color("cdbcb9")) if station else _shade(_color("east", Color("c2c5c9")), shade)
		_box(rect, 0.0, h, top, south, east)
		if lit:
			_windows(lot, rect, floor_m, 0.9 if station else plan.num("window_lit_ratio", 0.3) * night)
		var roof: Rect2i = lot.roof
		if roof.size.x > 0 and not DisplaySettings.low_spec:
			_box(Rect2(roof), h, h + plan.num("roof_m", 2.5), top, south, east)
	_flush()


static func _shade(c: Color, amount: float) -> Color:
	return c.lightened(amount) if amount >= 0.0 else c.darkened(-amount)


## 현장 가까운 교차로의 횡단보도 (흰 줄 다섯)
func _crosswalks() -> void:
	var white := _color("crosswalk", Color("c9ced3"))
	for r in plan.row_streets:
		for c in plan.col_streets:
			var mid := Vector2((c.x + c.y) * 0.5, (r.x + r.y) * 0.5)
			if mid.distance_to(plan.site_center) > CROSSWALK_REACH:
				continue
			# 교차로의 동·서쪽 (남북으로 놓인 줄), 남·북쪽 (동서로 놓인 줄)
			for x0: float in [c.x - 5.0, c.y + 1.0]:
				var y := r.x + 1.0
				while y + 1.0 <= r.y - 1.0:
					_rect(Rect2(x0, y, 4.0, 1.0), 0.0, white)
					y += 2.0
			for y0: float in [r.x - 5.0, r.y + 1.0]:
				var x := c.x + 1.0
				while x + 1.0 <= c.y - 1.0:
					_rect(Rect2(x, y0, 1.0, 4.0), 0.0, white)
					x += 2.0


## 가로등 (밤): 길가에 따뜻한 점 + 옅은 빛 번짐. 화면에 들어오는 곳만
func _lamps() -> void:
	var gap := maxf(8.0, plan.num("lamp_spacing_cells", 40))
	var size := plan.num("lamp_m", 0.8) / CityPlan.CELL_M
	var lamp := Color(_color("lamp", Color("ffcf70")), minf(1.0, night))
	var glow := _color("lamp_glow", Color("ffcf7040"))
	glow.a *= night
	var b := plan.bounds
	for r in plan.row_streets:
		var x := float(b.position.x)
		while x < b.end.x:
			_lamp(Vector2(x, r.x + 0.5), size, lamp, glow)
			x += gap
	for c in plan.col_streets:
		var y := float(b.position.y) + gap * 0.5
		while y < b.end.y:
			_lamp(Vector2(c.x + 0.5, y), size, lamp, glow)
			y += gap


func _lamp(at: Vector2, size: float, lamp: Color, glow: Color) -> void:
	if not plan.in_view(at) or plan.map_rect.has_point(Vector2i(at)):
		return
	_rect(Rect2(at - Vector2(size, size) * 2.5, Vector2(size, size) * 5.0), 0.0, glow)
	_rect(Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)), 0.2, lamp)
	lamp_count += 1


## 불 켜진 창 (밤): 보이는 두 면(남·동)의 창 칸 가운데 일부만. 건물마다 정해진 시드라 늘 같은 창이 켜진다
func _windows(lot: Dictionary, rect: Rect2, floor_m: float, ratio: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lot.seed) + 7
	var bay := maxf(1.0, plan.num("window_bay_m", 3.0))
	var half_w := plan.num("window_w_m", 1.3) / CityPlan.CELL_M * 0.5
	var win_h := plan.num("window_h_m", 1.4)
	var sill := plan.num("window_sill_m", 0.9)
	var max_cols := int(plan.num("window_max_cols", 10))
	var color := _color("window", Color("ffd873"))
	var cols_s := clampi(floori(rect.size.x * CityPlan.CELL_M / bay), 1, max_cols)
	var cols_e := clampi(floori(rect.size.y * CityPlan.CELL_M / bay), 1, max_cols)
	for f in int(lot.floors):
		var h0 := f * floor_m + sill
		var h1 := h0 + win_h
		for k in cols_s:
			if rng.randf() < ratio:
				var x := rect.position.x + (k + 0.5) * rect.size.x / cols_s
				_quad(proj.to_screen(Vector2(x - half_w, rect.end.y), h0), proj.to_screen(Vector2(x + half_w, rect.end.y), h0),
					proj.to_screen(Vector2(x + half_w, rect.end.y), h1), proj.to_screen(Vector2(x - half_w, rect.end.y), h1), color)
				window_count += 1
		for k in cols_e:
			if rng.randf() < ratio:
				var y := rect.position.y + (k + 0.5) * rect.size.y / cols_e
				_quad(proj.to_screen(Vector2(rect.end.x, y - half_w), h0), proj.to_screen(Vector2(rect.end.x, y + half_w), h0),
					proj.to_screen(Vector2(rect.end.x, y + half_w), h1), proj.to_screen(Vector2(rect.end.x, y - half_w), h1), color.darkened(0.12))
				window_count += 1


## 땅(또는 높이 h)의 네모
func _rect(r: Rect2, h: float, color: Color) -> void:
	_quad(proj.to_screen(r.position, h), proj.to_screen(Vector2(r.end.x, r.position.y), h),
		proj.to_screen(r.end, h), proj.to_screen(Vector2(r.position.x, r.end.y), h), color)


## 아이소 박스: 보이는 두 옆면(남·동)과 윗면. h0 = 밑 높이, h1 = 윗면 높이 (m)
func _box(r: Rect2, h0: float, h1: float, top: Color, south: Color, east: Color) -> void:
	var b := Vector2(r.end.x, r.position.y)
	var c := r.end
	var d := Vector2(r.position.x, r.end.y)
	_quad(proj.to_screen(d, h0), proj.to_screen(c, h0), proj.to_screen(c, h1), proj.to_screen(d, h1), south)
	_quad(proj.to_screen(b, h0), proj.to_screen(c, h0), proj.to_screen(c, h1), proj.to_screen(b, h1), east)
	_rect(r, h1, top)


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	var at := _points.size()
	_points.append_array(PackedVector2Array([a, b, c, d]))
	_colors.append_array(PackedColorArray([color, color, color, color]))
	_indices.append_array(PackedInt32Array([at, at + 1, at + 2, at, at + 2, at + 3]))
	quad_count += 1
	if _points.size() >= _batch_limit * 4:
		_flush()


func _flush() -> void:
	if _points.is_empty():
		return
	_batches.append({"points": _points, "colors": _colors, "indices": _indices})
	_points = PackedVector2Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()


func _draw() -> void:
	for b: Dictionary in _batches:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), b.indices, b.points, b.colors)


func _process(_delta: float) -> void:
	if _icons == null or not progress.is_valid():
		return
	# 출동 중에만 매 프레임 다시 그린다 (차·연기가 움직인다). 끝나면 한 번 지우고 멈춘다
	var active := float(progress.call()) >= 0.0
	if active or _overlay_drawn:
		_icons.queue_redraw()
	_overlay_drawn = active


## 출동 중인 선착 차량의 자리 (칸): 안전센터에서 길을 따라 큰길로, 현장 지도 서쪽 끝 바로 밖까지.
## f = 진행률 0~1, index = 몇 번째 차 (뒤차는 간격을 두고 따라온다), length_cells = 차 길이.
## 아직 안전센터를 나서지 않은 뒤차는 x가 아주 작은 값(-100000)
func truck_cell(f: float, index: int, length_cells: float) -> Vector2:
	var d := truck_distance(f, index, length_cells)
	if d < 0.0:
		return Vector2(-100000, 0)
	return plan.route_point(d / maxf(1.0, plan.route_length()))


## 그 차가 경로를 따라 달린 거리 (칸, 음수 = 아직 출발 전).
## 맨 앞차는 진행률 1에서 현장 지도 바로 밖(시뮬레이션 차량이 들어오기 시작하는 자리)에 선다
func truck_distance(f: float, index: int, length_cells: float) -> float:
	var stop := plan.route_length() - (length_cells * 0.5 + 1.0)
	return clampf(f, 0.0, 1.0) * stop - index * (length_cells + plan.num("truck_gap_cells", 6))


## 출동 중 화면: 대상 건물의 연기 기둥, 길을 따라 달리는 선착 소방차, 안전센터 이름
func _draw_overlay() -> void:
	if _sim == null or not progress.is_valid() or plan == null:
		return
	var f := float(progress.call())
	if f < 0.0:
		return
	# 화면 배율과 상관없이 같은 크기로 보이게 하는 배수 (멀리 본 도시에서도 글자·표시가 보이도록)
	var k := 1.0 / maxf(0.01, _icons.get_global_transform_with_canvas().get_scale().x)
	var font := PlanStyle.font()
	_draw_plume()
	# 안전센터 이름
	var st: Rect2i = plan.station.rect
	_label(proj.to_screen(Vector2(st.get_center()), float(plan.station.floors) * plan.num("floor_m", 3.0)) + Vector2(0, -10) * k,
		str(plan.p.get("station_name", "119안전센터")), k, font, _color("station_top", Color("c0392b")))
	var now := Time.get_ticks_msec() / 1000.0
	var i := 0
	for v in _sim.units.vehicles:
		if v.squad_id != 0:
			continue
		var d := truck_distance(f, i, v.length_cells)
		i += 1
		if d < 0.0:
			continue
		var t := d / maxf(1.0, plan.route_length())
		var sp := proj.to_screen(plan.route_point(t), 0.0)
		# 눈에 띄게: 차 둘레에 번쩍이는 빨간 빛 (화면에서 늘 같은 크기)
		var pulse := 0.5 + 0.5 * sin(now * 9.0 + i)
		_icons.draw_circle(sp, (15.0 + 5.0 * pulse) * k, Color(1.0, 0.15, 0.1, 0.16 + 0.14 * pulse))
		var art := SpriteArt.vehicle_set(v.type)
		var heading := plan.route_heading(t)
		var drawn := false
		if art != null:
			var anim := "drive" if art.frames("drive") > 0 and f < 1.0 else "idle"
			drawn = art.draw(_icons, anim, SpriteArt.dir8(heading), SpriteArt.frame_at(anim, art.frames(anim), v.id * 0.5), sp,
				Color.WHITE, Color(0, 0, 0, 0), plan.num("truck_scale", 1.5))
		if not drawn:
			_icons.draw_circle(sp, 9.0 * k, Color(v.color, 0.95))
			_icons.draw_arc(sp, 9.0 * k, 0.0, TAU, 20, Color.WHITE, 2.0 * k)
		_label(sp + Vector2(0, -26) * k, v.short_name, k, font, _color("label_box", Color("1f2933")))


## 화면에서 늘 같은 크기의 이름표: 짙은 바탕(box)에 흰 글자 — 밤 화면 분위기(어둡게·무채색)에서도 읽히게
func _label(at: Vector2, text: String, k: float, font: Font, box: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_icons.draw_set_transform(at, 0.0, Vector2(k, k))
	_icons.draw_rect(Rect2(-w * 0.5 - 6.0, -16.0, w + 12.0, 22.0), Color(box, 0.92))
	_icons.draw_string(font, Vector2(-w * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, _color("label_text", Color.WHITE))
	_icons.draw_set_transform(Vector2.ZERO)


## 대상 건물에서 오르는 연기 기둥 (기획안 4-4): 멀리서도 어디로 가는지 보인다. 바람이 부는 쪽으로 기운다.
## 밤에는 밑동에 불빛. 연기 덩이가 천천히 올라가며 커지고 옅어진다
func _draw_plume() -> void:
	var b := _sim.building
	var fp := b.footprint(b.levels()[0])
	var floors := 0
	for lv in b.levels():
		if b.floor_number(lv) >= 1:
			floors += 1
	var floor_m := plan.num("floor_m", 3.0)
	var base_h := maxf(1, floors) * floor_m
	var height := plan.num("plume_height_m", 45)
	var puffs := maxi(4, int(plan.num("plume_puffs", 12)))
	var r0 := plan.num("plume_radius_m", 4.0) * IsoProjection.PX_PER_M
	# 바람이 불어 가는 쪽 (칸 좌표): 불어 오는 쪽의 반대
	var rad := deg_to_rad(_sim.exposure.wind_from_deg)
	var lean := -Vector2(sin(rad), -cos(rad)) * plan.num("plume_lean_cells", 30)
	var center := Vector2(fp.get_center())
	var now := Time.get_ticks_msec() / 1000.0 * plan.num("plume_speed", 0.08)
	var col := _color("plume", Color("2b2d31"))
	if night > 0.3:
		var glow := _color("plume_glow", Color("ff7a1a"))
		_icons.draw_circle(proj.to_screen(center, base_h), r0 * 1.6, Color(glow, 0.35 * night))
		_icons.draw_circle(proj.to_screen(center, base_h), r0 * 0.8, Color(glow, 0.5 * night))
	for i in puffs:
		var u := fposmod(float(i) / puffs + now, 1.0)
		# 덩이마다 조금씩 옆으로 비켜 뭉게뭉게 (한 줄로 겹친 동심원이 되지 않게)
		var sway := Vector2(sin(i * 2.4) * r0 * 0.5 * (0.3 + u), cos(i * 1.7) * r0 * 0.25)
		var at := proj.to_screen(center + lean * u * u, base_h + height * u) + sway
		_icons.draw_circle(at, r0 * (0.8 + 2.4 * u), Color(col, col.a * (1.0 - pow(u, 1.5)) * 0.5))
