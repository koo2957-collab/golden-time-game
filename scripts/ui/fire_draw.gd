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


## 롤오버 천장 화염의 세기 0~1 (2026-11-25): 상부층 온도가 플래시오버 온도보다 roll_ramp_c 낮을 때 0, 플래시오버 온도에서 1.
## 롤오버는 플래시오버의 전조 — 가까워질수록 천장 화염이 진해지고 넓어진다 (화면에만 쓴다. 롤오버 여부는 시뮬레이션이 정한다)
static func rollover_strength(t_upper: float, flashover_temp: float) -> float:
	return clampf(1.0 - (flashover_temp - t_upper) / maxf(1.0, num("roll_ramp_c", 100.0)), 0.0, 1.0)


## 그 세기의 천장 화염 진하기 (roll_alpha_min ~ roll_alpha_max)
static func rollover_alpha(strength: float) -> float:
	return lerpf(num("roll_alpha_min", 0.5), num("roll_alpha_max", 0.95), clampf(strength, 0.0, 1.0))


## 플래시오버 전이 0~1 (3단계, 2026-11-25): 플래시오버 순간 0, flash_surge_s 초 뒤 1. 그 사이 천장 화염이 바닥까지 내려오고
## 번쩍 밝아졌던 것이 가라앉는다. 처음에 빠르고 끝에 느리다 (화면에만 쓴다 — 플래시오버 시각은 시뮬레이션이 정한다)
static func flash_progress(seconds: float) -> float:
	var x := clampf(seconds / maxf(0.1, num("flash_surge_s", 3.0)), 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)


## 개구부(열린·깨진 창, 열린 문) 밖으로 뿜는 화염의 세기 0~1 (4단계, 2026-11-25) — 방의 상태로:
##   플래시오버 뒤: 상부층 온도로 (rollover_strength — 플래시오버 온도 위에서 1, 식으면 줄어든다). 타는 동안은 vent_growth_k 아래로 안 내려간다
##   롤오버 징후: vent_growth_k → vent_roll_k (플래시오버에 가까울수록 크게)
##   그 밖(성장기의 불이 보일 때): vent_growth_k — 개구부 윗부분에서 작은 불꽃만
static func vent_strength(flashed: bool, rollover: bool, t_upper: float, flashover_temp: float) -> float:
	var low := num("vent_growth_k", 0.15)
	var s := rollover_strength(t_upper, flashover_temp)
	if flashed:
		return maxf(low, s)
	if rollover:
		return lerpf(low, num("vent_roll_k", 0.45), s)
	return low


## 그 세기의 분출 화염이 개구부 윗면(인방) 위로 솟는 높이 (m)
static func vent_rise_m(strength: float) -> float:
	return lerpf(num("vent_rise_min_m", 0.4), num("vent_rise_max_m", 2.4), clampf(strength, 0.0, 1.0))


## 타는 칸들 → 불(채) 목록.
## cells: [{x, y 칸, kw 열방출률, room 방 번호, base 불 뿌리 높이(m), faded 기억 속의 불인가, full 방 전체가 타는 중인가(플래시오버 뒤)}]
## 돌려주는 값 (하나가 불꽃 그림 하나): {pos 칸 좌표, kw, cells 칸 수, diameter_m, height_m, width_m 그릴 폭, kind, base_m, faded, seed,
##   capped 천장에 닿았는가, satellite(쓰지 않음 — 늘 false), full, shade, room}. 깊이(x + y) 순서 — 뒤에서 앞으로
##
## 붙어 있는 불은 하나로 (2026-11-25 사용자: 한 칸의 불이 다음 칸으로 가면 합쳐져서 더 크게 보여야 한다 — 칸마다 불씨가 하나씩 있는 것 같다):
## 플래시오버 전의 불은 서로 가까운(merge_gap_m 안) 타는 칸들을 한 덩어리로 묶어 불 하나로 그린다 (_merged_bodies).
## 번질수록 그 한 덩어리가 커진다. 전에는 2m 바둑판마다 하나 + 떨어진 칸의 작은 곁불을 따로 세웠다.
##
## 전실 화재의 입체감 (2026-11-25 사용자: 화염이 입체감이 없다 — 방에 화염 그림을 바른 상자처럼 보였다):
## full 인 방은 더 촘촘한 바둑판(full_tile_m)으로 묶어 불기둥을 여러 줄 세우고, 기둥마다 높이를 달리해(full_reach_min~max × 방 높이 —
## 일부는 천장 위로 솟는다) 끝이 들쭉날쭉하게 한다. shade = 그 방 안에서의 앞뒤 자리 (0 맨 뒤 … 1 맨 앞 — 뒤는 어둡고 붉게 칠한다),
## full = 전실 화재의 기둥인가, room = 방 번호
static func bodies(cells: Array, cell_m: float, ceiling_m: float) -> Array[Dictionary]:
	var tile := maxi(1, roundi(num("tile_m", 2.0) / cell_m))
	var full_tile := maxi(1, roundi(num("full_tile_m", 1.0) / cell_m))
	var groups := {}
	# 방마다(보이는 불 · 기억 속의 불 따로): 열방출률 합, 칸 수, 전체가 타는가, 가장 센 채의 열방출률
	var rooms := {}
	# 플래시오버 전의 불 (붙어 있는 칸끼리 한 덩어리로 묶는다)
	var loose: Array = []
	for c: Dictionary in cells:
		if not bool(c.get("full", false)):
			loose.append(c)
			continue
		var room_key := "%d|%d" % [int(c.room), 1 if bool(c.get("faded", false)) else 0]
		var size := full_tile if bool(c.get("full", false)) else tile
		var key := "%s|%d|%d|%d" % [room_key, size, floori(float(c.x) / size), floori(float(c.y) / size)]
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
		var size := full_tile if bool(first.get("full", false)) else tile
		var tx := floori(float(first.x) / size)
		var ty := floori(float(first.y) / size)
		var seed := absi(hash(Vector3i(tx, ty, int(first.room) + (1000 if size != tile else 0))))
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
		body.room = int(first.room)
		if bool(room.full) and bool(first.get("full", false)):
			# 전실 화재의 기둥: 높이가 제각각 (일부는 천장 위로), 폭은 이웃 기둥과 겹치게
			var reach := lerpf(num("full_reach_min", 0.8), num("full_reach_max", 1.18), _unit((seed >> 5) + 11))
			body.height_m = maxf(min_h, (ceiling_m - float(body.base_m)) * reach)
			# 불기둥(l — 혀가 갈라져 틈이 보인다)과 불바다(xl — 넓고 밝다)를 섞는다: 모두 xl 이면 겹쳐서 밝은 한 덩어리로 뭉개진다
			body.kind = "xl" if _unit((seed >> 7) + 29) < num("full_xl_share", 0.3) else "l"
			# 폭은 그림의 제 비율 그대로 (2026-11-25 사용자: 화염이미지처럼 둥근 불덩이 — 늘여서 기둥을 만들지 않는다)
			body.width_m = draw_width_m(str(body.kind), float(body.height_m), float(body.diameter_m))
			body.full = true
		out.append(body)
	out.append_array(_merged_bodies(loose, cell_m, ceiling_m))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = a.pos.x + a.pos.y
		var db: float = b.pos.x + b.pos.y
		return da < db if da != db else a.seed < b.seed)
	# 전실 화재의 기둥: 방 안에서의 앞뒤 자리 (깊이 x + y 가 가장 작은 기둥 0 … 가장 큰 기둥 1)
	var span := {}
	for f in out:
		if bool(f.full):
			var d: float = f.pos.x + f.pos.y
			var mm: Array = span.get(int(f.room), [d, d])
			span[int(f.room)] = [minf(float(mm[0]), d), maxf(float(mm[1]), d)]
	for f in out:
		if bool(f.full):
			var mm: Array = span[int(f.room)]
			f.shade = clampf((f.pos.x + f.pos.y - float(mm[0])) / maxf(0.5, float(mm[1]) - float(mm[0])), 0.0, 1.0)
	return out


## 플래시오버 전의 불: 가까운 타는 칸들을 한 덩어리로 묶어 (같은 방, 보이는 불·기억 속의 불 따로, merge_gap_m 안이면 이어진 것)
## 덩어리마다 불 하나 — 그 덩어리의 열방출률 합·타는 넓이로 화염 높이를 셈하고(Heskestad), 열방출률 무게 중심에 선다.
## 덩어리가 불꽃 그림 폭보다 길게 퍼졌으면 긴 쪽을 따라 몇 개로 나눠 세우되, 서로 크게 겹쳐(cluster_overlap) 한 불로 보이게 한다
static func _merged_bodies(cells: Array, cell_m: float, ceiling_m: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cells.is_empty():
		return out
	var min_h := num("min_height_m", 0.35)
	var base_max := num("base_max_m", 1.0)
	var weak := num("weak_ratio", 0.6)
	var gap := maxi(1, roundi(num("merge_gap_m", 1.0) / cell_m))
	var overlap := clampf(num("cluster_overlap", 0.6), 0.2, 1.0)
	var most := maxi(1, int(num("cluster_max", 4)))
	# "방|기억" → {칸: 그 칸}
	var maps := {}
	for c: Dictionary in cells:
		var key := "%d|%d" % [int(c.room), 1 if bool(c.get("faded", false)) else 0]
		if not maps.has(key):
			maps[key] = {}
		maps[key][Vector2i(int(c.x), int(c.y))] = c
	var keys: Array = maps.keys()
	keys.sort()
	for key: String in keys:
		var m: Dictionary = maps[key]
		var starts: Array = m.keys()
		starts.sort()
		var seen := {}
		for s0: Vector2i in starts:
			if seen.has(s0):
				continue
			# 이어진 칸 모으기 (gap 칸 안이면 이어진 것 — 가구 사이 빈 바닥 한두 칸은 건너뛴다)
			var comp: Array = []
			var queue: Array[Vector2i] = [s0]
			seen[s0] = true
			var head := 0
			while head < queue.size():
				var p := queue[head]
				head += 1
				comp.append(m[p])
				for dy in range(-gap, gap + 1):
					for dx in range(-gap, gap + 1):
						var n := p + Vector2i(dx, dy)
						if not seen.has(n) and m.has(n):
							seen[n] = true
							queue.append(n)
			var kw := 0.0
			var sum := Vector2.ZERO
			var base := 0.0
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for c: Dictionary in comp:
				var w := maxf(float(c.kw), 0.001)
				var at := Vector2(float(c.x) + 0.5, float(c.y) + 0.5)
				kw += w
				sum += at * w
				base += float(c.get("base", 0.0)) * w
				lo = lo.min(at)
				hi = hi.max(at)
			var first: Dictionary = comp[0]
			var faded := bool(first.get("faded", false))
			var seed := absi(hash(Vector3i(s0.x, s0.y, int(first.room) + 500)))
			var d := diameter_m(comp.size() * cell_m * cell_m)
			var free := flame_height_m(kw, d)
			var whole := _make(sum / kw, kw, comp.size(), minf(base / kw, base_max), free, cell_m, ceiling_m, min_h, faded, seed)
			whole.room = int(first.room)
			# 길게 퍼진 덩어리: 긴 쪽을 따라 나눠 세운다 (크게 겹쳐 한 불로 보인다)
			var along_x := hi.x - lo.x >= hi.y - lo.y
			var long_m := ((hi.x - lo.x) if along_x else (hi.y - lo.y)) * cell_m + cell_m
			# 작은 덩어리(cluster_min_m 보다 짧은)는 나누지 않는다 — 두세 칸짜리 불이 불꽃 여러 개로 갈라지지 않게
			var parts := clampi(ceili(long_m / maxf(num("cluster_min_m", 1.2), float(whole.width_m) * overlap) - 0.001), 1, mini(most, comp.size()))
			if parts <= 1:
				out.append(whole)
				continue
			var order := comp.duplicate()
			order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ka := int(a.x) if along_x else int(a.y)
				var kb := int(b.x) if along_x else int(b.y)
				return ka < kb if ka != kb else (int(a.x) + int(a.y) * 1000) < (int(b.x) + int(b.y) * 1000))
			var slices: Array = []
			var top_kw := 0.0
			for k in parts:
				var from := k * order.size() / parts
				var to := (k + 1) * order.size() / parts
				var skw := 0.0
				var ssum := Vector2.ZERO
				var sbase := 0.0
				for q in range(from, to):
					var c: Dictionary = order[q]
					var w := maxf(float(c.kw), 0.001)
					skw += w
					ssum += Vector2(float(c.x) + 0.5, float(c.y) + 0.5) * w
					sbase += float(c.get("base", 0.0)) * w
				slices.append([ssum / skw, skw, to - from, sbase / skw])
				top_kw = maxf(top_kw, skw / maxf(1.0, float(to - from)))  # 칸당 열방출률로 견준다 (칸 수가 하나 많다고 더 센 조각이 되지 않게)
			for k in slices.size():
				var sl: Array = slices[k]
				# 높이는 덩어리 전체의 불로 셈한 높이 — 가장 센 조각이 그 높이, 약한 조각은 weak_ratio 까지
				var body := _make(sl[0], float(sl[1]), int(sl[2]), minf(float(sl[3]), base_max), free * lerpf(weak, 1.0, clampf(float(sl[1]) / maxf(1.0, float(sl[2])) / maxf(top_kw, 0.001), 0.0, 1.0)),
					cell_m, ceiling_m, min_h, faded, absi(hash(Vector3i(s0.x + k * 131, s0.y, int(first.room) + 500))))
				# 폭은 덩어리 전체의 폭 그대로 (이웃 조각과 크게 겹친다), 그림 종류는 그 높이와 덩어리 지름으로
				body.diameter_m = d
				body.kind = kind_for(float(body.height_m), d)
				body.width_m = draw_width_m(str(body.kind), float(body.height_m), d)
				body.room = int(first.room)
				out.append(body)
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
		"full": false, "shade": 1.0, "room": -1,
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
