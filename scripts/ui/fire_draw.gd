class_name FireDraw
extends RefCounted
## 불꽃 배치 (2026-11-22 사용자 결정 — 참고 그림 '화재성장속도, 4단계'). 화면 없이 계산만 한다.
## 타는 칸마다 같은 불꽃을 하나씩 세우면 방이 다 탈 때 고깔이 줄 맞춰 선 것처럼 보인다. 그래서
##   1) 가까운 타는 칸(같은 방, tile_m 바둑판 한 칸 안)을 불 한 채로 묶고
##   2) 그 열방출률과 타는 넓이로 화염 높이를 셈해 (Heskestad 식 — 공학 표준)
##   3) 높이에 맞는 크기의 불꽃 그림(s·m·l·xl) 하나를 열방출률 무게 중심에 그린다.
## 불이 자라면 s → m → l → xl 로 커지므로 크기만 봐도 세기가 읽힌다. 수치는 data/ui/fire_style.json

const PATH := "res://data/ui/fire_style.json"
const KINDS: Array[String] = ["s", "m", "l", "xl"]

static var _style: Dictionary = {}


## 설정값 {이름: 값} (파일의 value만)
static func style() -> Dictionary:
	if _style.is_empty():
		var data: Variant = JsonData.load_file(PATH)
		if data is Dictionary:
			for key: String in data:
				if data[key] is Dictionary and (data[key] as Dictionary).has("value"):
					_style[key] = data[key]["value"]
	return _style


static func num(key: String, fallback := 0.0) -> float:
	return float(style().get(key, fallback))


## 타는 넓이(m²)와 같은 넓이의 원의 지름 (m)
static func diameter_m(area_m2: float) -> float:
	return sqrt(4.0 * maxf(0.0, area_m2) / PI)


## 평균 화염 높이 (m): Heskestad 식 L = a·Q^(2/5) − b·D (Q kW, D m). 0보다 작으면 0
static func flame_height_m(kw: float, fire_diameter_m: float) -> float:
	if kw <= 0.0:
		return 0.0
	return maxf(0.0, num("heskestad_a", 0.235) * pow(kw, 0.4) - num("heskestad_b", 1.02) * fire_diameter_m)


## 화염 높이·불 지름에 맞는 그림 종류 ("s" · "m" · "l" · "xl")
static func kind_for(height_m: float, fire_diameter_m: float) -> String:
	var cuts: Array = style().get("kind_heights_m", [0.95, 1.6])
	if height_m < float(cuts[0]):
		return "s"
	if height_m < float(cuts[1]):
		return "m"
	if height_m >= num("xl_min_height_m", 1.9) and fire_diameter_m >= num("xl_min_diameter_m", 1.5):
		return "xl"
	return "l"


## 타는 칸들 → 불(채) 목록.
## cells: [{x, y 칸, kw 열방출률, room 방 번호, base 불 뿌리 높이(m), faded 기억 속의 불인가, full 방 전체가 타는 중인가(플래시오버 뒤)}]
## 화염 높이는 방 하나의 불 전체(열방출률 합·타는 넓이 합)로 셈한다 — 불 하나를 바둑판으로 나눠 따로 셈하면 실제보다 낮게 나온다.
## 그 방에서 가장 센 채가 그 높이, 약한 채는 weak_ratio 까지 낮다. full 인 방은 천장까지 찬다 (전실 화재).
## 돌려주는 값 (하나가 불꽃 그림 하나): {pos 칸 좌표, kw, cells 칸 수, diameter_m, height_m, width_m 그릴 폭, kind, base_m, faded, seed,
##   capped 천장에 닿았는가, satellite 곁불인가}. 깊이(x + y) 순서 — 뒤에서 앞으로
static func bodies(cells: Array, cell_m: float, ceiling_m: float) -> Array[Dictionary]:
	var tile := maxi(1, roundi(num("tile_m", 2.0) / cell_m))
	var groups := {}
	# 방마다(보이는 불 · 기억 속의 불 따로): 열방출률 합, 칸 수, 전체가 타는가, 가장 센 채의 열방출률
	var rooms := {}
	for c: Dictionary in cells:
		var room_key := "%d|%d" % [int(c.room), 1 if bool(c.get("faded", false)) else 0]
		var key := "%s|%d|%d" % [room_key, floori(float(c.x) / tile), floori(float(c.y) / tile)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(c)
		var acc: Dictionary = rooms.get(room_key, {"kw": 0.0, "cells": 0, "full": false, "top": 0.0, "tiles": {}})
		acc.kw += maxf(float(c.kw), 0.001)
		acc.cells += 1
		acc.full = bool(acc.full) or bool(c.get("full", false))
		acc.tiles[key] = float(acc.tiles.get(key, 0.0)) + maxf(float(c.kw), 0.001)
		acc.top = maxf(float(acc.top), float(acc.tiles[key]))
		rooms[room_key] = acc
	var weak := num("weak_ratio", 0.6)
	var out: Array[Dictionary] = []
	var min_h := num("min_height_m", 0.35)
	var base_max := num("base_max_m", 1.0)
	var jitter := num("jitter_m", 0.2) / cell_m
	var sat_min := int(num("satellite_min_cells", 5))
	var sat_count := int(num("satellite_count", 2))
	var sat_dist := num("satellite_min_dist_m", 0.7) / cell_m
	for key: String in groups:
		var list: Array = groups[key]
		var kw := 0.0
		var sum := Vector2.ZERO
		var base := 0.0
		for c: Dictionary in list:
			var w := maxf(float(c.kw), 0.001)
			kw += w
			sum += Vector2(float(c.x) + 0.5, float(c.y) + 0.5) * w
			base += float(c.get("base", 0.0)) * w
		var first: Dictionary = list[0]
		var tx := floori(float(first.x) / tile)
		var ty := floori(float(first.y) / tile)
		var seed := absi(hash(Vector3i(tx, ty, int(first.room))))
		var pos := sum / kw
		# 한 칸짜리 불은 그 칸 가운데에 그대로, 여러 칸이면 조금 흩는다 (줄 맞춰 보이지 않게)
		if list.size() > 1:
			pos += Vector2(_unit(seed) - 0.5, _unit((seed >> 3) + 3) - 0.5) * 2.0 * jitter
		var faded := bool(first.get("faded", false))
		var room: Dictionary = rooms["%d|%d" % [int(first.room), 1 if faded else 0]]
		# 방 전체의 불로 셈한 높이 (전체가 타는 방은 천장 너머로 — 아래에서 천장 높이로 자른다)
		var room_h := ceiling_m * 2.0 if bool(room.full) else flame_height_m(float(room.kw), diameter_m(int(room.cells) * cell_m * cell_m))
		var free := room_h * lerpf(weak, 1.0, kw / maxf(float(room.top), 0.001))
		var body := _make(pos, kw, list.size(), minf(base / kw, base_max), free, cell_m, ceiling_m, min_h, faded, seed)
		out.append(body)
		# 곁불: 무게 중심에서 먼 타는 칸에 작은 불 — 큰 그림 하나만 덩그러니 있지 않게
		if list.size() >= sat_min and sat_count > 0:
			var far := list.duplicate()
			far.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var da := Vector2(float(a.x) + 0.5, float(a.y) + 0.5).distance_squared_to(pos)
				var db := Vector2(float(b.x) + 0.5, float(b.y) + 0.5).distance_squared_to(pos)
				return da > db if da != db else (int(a.x) + int(a.y) * 1000) < (int(b.x) + int(b.y) * 1000))
			var placed: Array[Vector2] = []
			for c: Dictionary in far:
				if placed.size() >= sat_count:
					break
				var at := Vector2(float(c.x) + 0.5, float(c.y) + 0.5)
				if at.distance_to(pos) < sat_dist:
					break
				var near := false
				for q in placed:
					if q.distance_to(at) < sat_dist:
						near = true
				if near:
					continue
				placed.append(at)
				# 곁불의 높이는 그 칸 하나의 불로 셈하되 몸통보다는 낮게
				var sat_h := minf(flame_height_m(float(c.kw), diameter_m(cell_m * cell_m)), float(body.height_m) * num("satellite_max_ratio", 0.6))
				var sat := _make(at, float(c.kw), 1, minf(float(c.get("base", 0.0)), base_max), sat_h, cell_m, ceiling_m, min_h, faded,
					absi(hash(Vector3i(int(c.x), int(c.y), int(first.room) + 77))))
				sat.satellite = true
				out.append(sat)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = a.pos.x + a.pos.y
		var db: float = b.pos.x + b.pos.y
		return da < db if da != db else a.seed < b.seed)
	return out


## free = 천장이 없을 때의 화염 높이 (m)
static func _make(pos: Vector2, kw: float, count: int, base_m: float, free: float, cell_m: float, ceiling_m: float, min_h: float, faded: bool, seed: int) -> Dictionary:
	var d := diameter_m(count * cell_m * cell_m)
	var room := maxf(min_h, ceiling_m - base_m)
	var h := clampf(free, min_h, room)
	var kind := kind_for(h, d)
	return {
		"pos": pos, "kw": kw, "cells": count, "diameter_m": d, "height_m": h, "width_m": draw_width_m(kind, h, d), "kind": kind,
		"base_m": base_m, "faded": faded, "seed": seed, "capped": free > room, "satellite": false,
	}


## 불꽃 그림을 그릴 폭 (m): 그림 제 비율대로의 폭을, 타는 자리를 덮게 넓히되 너무 찌그러지지 않게
static func draw_width_m(kind: String, height_m: float, fire_diameter_m: float) -> float:
	var aspect: Dictionary = style().get("kind_aspect", {})
	var natural := height_m * float(aspect.get(kind, 0.75))
	var stretch := maxf(1.0, num("max_stretch", 1.6))
	return clampf(fire_diameter_m * num("width_cover", 1.25), natural / stretch, natural * stretch)


## 0~1 (정해진 값 — 같은 seed 면 늘 같다)
static func _unit(seed: int) -> float:
	return float(posmod(seed * 1103515245 + 12345, 9973)) / 9973.0
