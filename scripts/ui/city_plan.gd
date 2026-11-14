class_name CityPlan
extends RefCounted
## 출동 단계에 보는 도시의 배치 (기획안 4-4, 2026-11-14). 그리기(CityMassView)와 따로 두어 화면 없이 점검할 수 있다.
## 현장 앞 도로를 큰길로 이어 격자 도로망을 만들고, 블록을 필지로 나눠 건물(흰 덩어리)을 세운다.
##   - 화면을 꽉 채운다: 원경 배율에서 화면에 들어오는 땅(화면 축으로 가로 overview_width_m)을 모두 덮는다
##   - 가리지 않는다: 현장과 출동 경로의 앞쪽(남·동쪽 = 화면 아래쪽)에 오는 건물은 층수를 낮춘다
##   - 안전센터와 출동 경로: 서북쪽 안전센터 → 남북 길 → 큰길 → 현장 지도 서쪽 끝
## 같은 건물·같은 시드면 늘 같은 도시. 수치는 data/ui/city.json. 좌표는 현장 지도의 칸(0.5m), 지도 밖은 음수·큰 값.

const PATH := "res://data/ui/city.json"
const CELL_M := 0.5
## 건물 높이 1m가 화면에서 가리는 땅 깊이 (칸, x·y 각각): 높이는 화면 위로 PX_PER_M, 땅 한 칸 대각은 2 × HALF_H
const SHIFT_PER_M := IsoProjection.PX_PER_M / (2.0 * IsoProjection.HALF_H)

## 설정값 (키 → 값)
var p: Dictionary = {}
var map_rect := Rect2i()
## 화면 가운데에 오는 칸 (현장 지도 가운데)
var center := Vector2.ZERO
## 원경에서 화면에 들어오는 범위 (가운데 기준, x − y 방향 절반 · x + y 방향 위·아래)
var half_u := 0.0
var half_v := 0.0
var bottom_v := 0.0
## 도시 전체 (길·바닥을 까는 범위)
var bounds := Rect2i()
## 큰길 = 현장 앞 도로를 이은 길 (y 범위 [x, y))
var avenue := Vector2i.ZERO
## 동서로 난 길의 y 범위들, 남북으로 난 길의 x 범위들 [시작, 끝)
var row_streets: Array[Vector2i] = []
var col_streets: Array[Vector2i] = []
## 블록 바닥 (보도 포함)
var pads: Array[Rect2i] = []
## 빈터·주차장
var yards: Array[Rect2i] = []
## 건물 [{rect: Rect2i, floors: int, shade: float, roof: Rect2i(없으면 크기 0), kind: "building"·"station", seed: int}] — 뒤(북서)에서 앞 순서
var lots: Array[Dictionary] = []
## 안전센터 {rect, floors} (lots에도 들어 있다)
var station: Dictionary = {}
## 출동 경로 (칸): 안전센터 앞 → 남북 길 → 큰길 → 현장 지도 서쪽 끝
var route := PackedVector2Array()
## 가리면 안 되는 곳 [{rect: Rect2i, cover: float}]
var protected: Array[Dictionary] = []


static func load_params() -> Dictionary:
	var out: Dictionary = {}
	var data: Variant = JsonData.load_file(PATH)
	if data is Dictionary:
		for key: String in data:
			var entry: Variant = data[key]
			if entry is Dictionary and (entry as Dictionary).has("value"):
				out[key] = entry["value"]
			elif key == "colors":
				out[key] = entry
	return out


func num(key: String, fallback := 0.0) -> float:
	return float(p.get(key, fallback))


## map_size = 현장 지도 크기(칸), road_rows = 현장 앞 도로의 행 (첫 행, 끝 행 — 없으면 x < 0),
## lane_y = 선착 차량이 들어오는 행 (없으면 큰길 북쪽 차로)
func generate(map_size: Vector2i, road_rows: Vector2i, p_seed: int, lane_y := -1.0, params: Dictionary = {}) -> void:
	p = params if not params.is_empty() else load_params()
	map_rect = Rect2i(Vector2i.ZERO, map_size)
	center = Vector2(map_size) * 0.5
	var s := int(num("street_cells", 12))
	var b := int(num("block_cells", 60))
	avenue = Vector2i(road_rows.x, road_rows.y + 1) if road_rows.x >= 0 else Vector2i(map_size.y - s, map_size.y)
	half_u = num("overview_width_m", 400) / (CELL_M * sqrt(2.0))
	half_v = num("aspect_max", 0.75) * half_u * IsoProjection.HALF_W / IsoProjection.HALF_H
	bottom_v = num("bottom_margin_m", 48) * IsoProjection.PX_PER_M / IsoProjection.HALF_H
	var reach := ceili((half_u + half_v + bottom_v) * 0.5) + b + s
	# 동서 길과 그 사이 블록 줄 (y)
	var row_bands: Array[Vector2i] = []
	row_streets = [avenue, Vector2i(-s, 0)]
	if avenue.x > 0:
		row_bands.append(Vector2i(0, avenue.x))
	var y := avenue.y
	while y < center.y + reach:
		row_bands.append(Vector2i(y, y + b))
		row_streets.append(Vector2i(y + b, y + b + s))
		y += b + s
	y = -s
	while y > center.y - reach:
		row_bands.append(Vector2i(y - b, y))
		row_streets.append(Vector2i(y - b - s, y - b))
		y -= b + s
	# 남북 길과 그 사이 블록 줄 (x) — 현장 지도 폭이 한 블록
	var col_bands: Array[Vector2i] = [Vector2i(0, map_size.x)]
	col_streets = [Vector2i(-s, 0), Vector2i(map_size.x, map_size.x + s)]
	var x := map_size.x + s
	while x < center.x + reach:
		col_bands.append(Vector2i(x, x + b))
		col_streets.append(Vector2i(x + b, x + b + s))
		x += b + s
	x = -s
	while x > center.x - reach:
		col_bands.append(Vector2i(x - b, x))
		col_streets.append(Vector2i(x - b - s, x - b))
		x -= b + s
	var x_min := 0
	var x_max := map_size.x
	for c in col_streets:
		x_min = mini(x_min, c.x)
		x_max = maxi(x_max, c.y)
	var y_min := 0
	var y_max := map_size.y
	for r in row_streets:
		y_min = mini(y_min, r.x)
		y_max = maxi(y_max, r.y)
	bounds = Rect2i(x_min, y_min, x_max - x_min, y_max - y_min)
	_place_station(s, b, lane_y)
	# 블록마다 필지·건물
	pads.clear()
	yards.clear()
	lots.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	for rb in row_bands:
		for cb in col_bands:
			var block := Rect2i(cb.x, rb.x, cb.y - cb.x, rb.y - rb.x)
			if block.intersects(map_rect):
				continue  # 현장 자리
			pads.append(block)
			if in_view(Vector2(block.get_center()), float(b + s)):
				_fill_block(block, rng)
	lots.append({"rect": station.rect, "floors": int(station.floors), "shade": 0.0, "roof": Rect2i(), "kind": "station", "seed": 0})
	# 뒤(북서)부터 그리도록 화면 깊이(x + y) 순
	lots.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		var ra: Rect2i = a.rect
		var rc: Rect2i = c.rect
		return (ra.position.x + ra.end.x + ra.position.y + ra.end.y) < (rc.position.x + rc.end.x + rc.position.y + rc.end.y))


## 안전센터·출동 경로·가리면 안 되는 곳
func _place_station(s: int, b: int, lane_y: float) -> void:
	var west := maxi(1, int(num("station_blocks_west", 3)))
	var north := maxi(1, int(num("station_blocks_north", 1)))
	var step := s + b
	# 서쪽 west번째 블록 줄의 동쪽 끝 = 그 옆 남북 길의 서쪽 끝
	var street_x0 := -(west - 1) * step - s
	var band_y0 := -north * step
	var side := int(num("sidewalk_cells", 2))
	var depth := mini(26, b - side * 2)
	var width := mini(30, b - side * 2)
	var rect := Rect2i(street_x0 - side - depth, band_y0 + (b - width) / 2, depth, width)
	station = {"rect": rect, "floors": int(num("station_floors", 2))}
	var lane_x := street_x0 + s * 0.5
	var door_y := rect.position.y + rect.size.y * 0.5
	var ly := lane_y if lane_y >= 0.0 else avenue.x + 2.5
	route = PackedVector2Array([Vector2(rect.end.x, door_y), Vector2(lane_x, door_y), Vector2(lane_x, ly), Vector2(0.0, ly)])
	protected = [
		{"rect": map_rect, "cover": num("site_cover_cells", 2)},
		{"rect": Rect2i(street_x0, floori(door_y), s, avenue.y - floori(door_y)), "cover": num("route_cover_cells", 6)},
		{"rect": Rect2i(street_x0, avenue.x, -street_x0, avenue.y - avenue.x), "cover": num("route_cover_cells", 6)},
	]


## 블록 하나를 필지로 나눠 건물을 세운다
func _fill_block(block: Rect2i, rng: RandomNumberGenerator) -> void:
	var inner := block.grow(-int(num("sidewalk_cells", 2)))
	if inner.size.x < 8 or inner.size.y < 8:
		return
	var lot := maxf(8.0, num("lot_cells", 28))
	var gap := int(num("lot_gap_cells", 2))
	if rng.randf() < num("merge_block_ratio", 0.1) and inner.size.x >= lot * 1.5 and inner.size.y >= lot * 1.5:
		_add_lot(inner, rng)
		return
	var nx := maxi(1, roundi(inner.size.x / lot))
	var ny := maxi(1, roundi(inner.size.y / lot))
	for j in ny:
		var y0 := inner.position.y + inner.size.y * j / ny
		var y1 := inner.position.y + inner.size.y * (j + 1) / ny - (gap if j + 1 < ny else 0)
		var i := 0
		while i < nx:
			var span := 2 if i + 1 < nx and rng.randf() < num("merge_pair_ratio", 0.25) else 1
			var x0 := inner.position.x + inner.size.x * i / nx
			var x1 := inner.position.x + inner.size.x * (i + span) / nx - (gap if i + span < nx else 0)
			i += span
			var r := Rect2i(x0, y0, x1 - x0, y1 - y0)
			if rng.randf() < num("empty_lot_ratio", 0.1):
				yards.append(r)
			else:
				_add_lot(r, rng)


func _add_lot(r: Rect2i, rng: RandomNumberGenerator) -> void:
	# 건물마다 조금씩 물려 짓는다 (같은 크기 상자가 줄지어 서지 않게)
	var l := rng.randi_range(0, 3)
	var t := rng.randi_range(0, 3)
	var rr := rng.randi_range(0, 3)
	var bb := rng.randi_range(0, 3)
	var rect := Rect2i(r.position.x + l, r.position.y + t, maxi(8, r.size.x - l - rr), maxi(8, r.size.y - t - bb))
	var floors := _pick_floors(rng)
	var want_roof := rng.randf() < num("roof_ratio", 0.5)
	var roof_corner := rng.randi_range(0, 3)
	var lot_seed := rng.randi()
	var shade := rng.randf_range(-0.03, 0.03)
	if not station.is_empty() and rect.intersects((station.rect as Rect2i).grow(2)):
		return
	var cap := max_floors(rect)
	var roof := Rect2i()
	if floors > cap:
		floors = cap
	elif floors >= 3 and want_roof:
		var size := Vector2i(maxi(4, roundi(rect.size.x * 0.4)), maxi(4, roundi(rect.size.y * 0.4)))
		var at := rect.position + Vector2i(2, 2)
		if roof_corner % 2 == 1:
			at.x = rect.end.x - size.x - 2
		if roof_corner >= 2:
			at.y = rect.end.y - size.y - 2
		roof = Rect2i(at, size)
	lots.append({"rect": rect, "floors": floors, "shade": shade, "roof": roof, "kind": "building", "seed": lot_seed})


func _pick_floors(rng: RandomNumberGenerator) -> int:
	var groups: Array = p.get("floors", [[1, 4, 0.6], [5, 9, 0.3], [10, 15, 0.1]])
	var roll := rng.randf()
	var pick: Array = groups[groups.size() - 1]
	var acc := 0.0
	for g: Array in groups:
		acc += float(g[2])
		if roll < acc:
			pick = g
			break
	return rng.randi_range(int(pick[0]), int(pick[1]))


## 그 자리 건물이 현장·출동 경로를 정해진 깊이보다 더 가리지 않는 가장 높은 층수 (제한이 없으면 99, 적어도 1층)
func max_floors(rect: Rect2i) -> int:
	var h := INF
	for pr: Dictionary in protected:
		var q: Rect2i = pr.rect
		# 건물 윗부분은 화면에서 (-k, -k)칸 쪽 땅을 가린다. k가 k_min을 넘으면 q에 닿기 시작한다
		var k_min := maxf(maxf(rect.position.x - q.end.x, rect.position.y - q.end.y), 0.0)
		var k_max := minf(rect.end.x - q.position.x, rect.end.y - q.position.y)
		if k_min < k_max:
			h = minf(h, (k_min + float(pr.cover)) / SHIFT_PER_M)
	if h == INF:
		return 99
	return maxi(1, floori(h / num("floor_m", 3.0)))


## 원경 화면에 들어오는 칸인가 (margin = 여유, x ∓ y 단위)
func in_view(cell: Vector2, margin := 0.0) -> bool:
	var du := (cell.x - cell.y) - (center.x - center.y)
	var dv := (cell.x + cell.y) - (center.x + center.y)
	return absf(du) <= half_u + margin and dv >= -half_v - margin and dv <= half_v + bottom_v + margin


## 출동 단계 원경 배율: 화면 가로에 overview_width_m가 들어오게
func overview_zoom(screen_w: float) -> float:
	return screen_w / (2.0 * half_u * IsoProjection.HALF_W)


## 출동 경로의 길이 (칸)
func route_length() -> float:
	var total := 0.0
	for i in route.size() - 1:
		total += route[i].distance_to(route[i + 1])
	return total


## 출동 경로 위의 자리 (t = 0 안전센터 앞 … 1 현장 지도 서쪽 끝)
func route_point(t: float) -> Vector2:
	if route.is_empty():
		return Vector2.ZERO
	var left := clampf(t, 0.0, 1.0) * route_length()
	for i in route.size() - 1:
		var d := route[i].distance_to(route[i + 1])
		if left <= d and d > 0.0:
			return route[i].lerp(route[i + 1], left / d)
		left -= d
	return route[route.size() - 1]


## 그 자리에서 달리는 방향 (단위 벡터)
func route_heading(t: float) -> Vector2:
	if route.size() < 2:
		return Vector2.RIGHT
	var left := clampf(t, 0.0, 1.0) * route_length()
	for i in route.size() - 1:
		var d := route[i].distance_to(route[i + 1])
		if left <= d and d > 0.0:
			return (route[i + 1] - route[i]).normalized()
		left -= d
	return (route[route.size() - 1] - route[route.size() - 2]).normalized()
