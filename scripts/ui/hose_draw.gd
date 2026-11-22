class_name HoseDraw
extends RefCounted
## 소방호스 그리기 (docs/motions.md '라. 소방호스 표현', 2026-11-18). 입체 화면(FloorLayer)과 평면 화면(UnitsView)이 같이 쓴다.
##   D1 납작한 호스 (송수 전): 넓고 납작한 띠
##   D2 부푼 호스 (송수 뒤): 좁고 통통한 관 (아래 그늘·위 밝은 줄)
##   D4 결합구: 1본(15m)마다 금속 고리
##   D5 여유 호스 (2026-11-21): 호스는 펌프차 후면 방수구(동작 패널)에서 나오고, 방수구 옆과 건물 조금 앞에 구불구불한 굽이를 둔다.
##      그림만이다 — 굽이는 옆으로만 휘므로 결합구·물머리 자리(시뮬레이션 거리)는 그대로다.
##      남은 호스가 적어지면 굽이가 펴져 팽팽해진다 ("호스가 팽팽해서 더 못 들어갑니다" 전에 눈으로 보인다)
## 꺾이는 곳은 둥글린다. 색·폭은 data/ui/hose_style.json (화면 설정 — 시뮬레이션과 상관없다)

const PATH := "res://data/ui/hose_style.json"

static var _style: Dictionary = {}
## 호스마다 계산해 둔 배치 {호스 instance id: {key, lay}} — 호스가 바뀔 때만 다시 계산한다
static var _lay_cache: Dictionary = {}


## 설정값 {이름: 값} (파일의 value만)
static func style() -> Dictionary:
	if _style.is_empty():
		var data: Variant = JsonData.load_file(PATH)
		if data is Dictionary:
			for key: String in data:
				if data[key] is Dictionary and (data[key] as Dictionary).has("value"):
					_style[key] = data[key]["value"]
	return _style


## 그 층에 놓인 호스 조각들 [{pts: PackedVector2Array (칸 좌표), dist: PackedFloat32Array (펌프차 쪽 끝부터 잰 거리, 칸)}].
## 일직선 위의 점은 빼고, 꺾이는 곳은 corner_cells 반지름으로 둥글린다. 다른 층을 지나면 조각이 나뉜다 (계단 한 층 = HoseLine.length_cells와 같은 6칸).
## lay(layout의 결과)에 방수구가 있으면 호스가 시작하는 조각은 차 가운데가 아니라 방수구에서 나온다.
## slack_from = 그 조각에서 여유 호스 굽이를 둘 수 있는 첫 거리
static func runs(h: HoseLine, level: int, corner_cells: float, corner_steps: int, lay: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pts := PackedVector2Array()
	var dist := PackedFloat32Array()
	var total := 0.0
	for k in h.points.size():
		var p := h.points[k]
		if k > 0:
			var a := h.points[k - 1]
			total += Vector2(a.x, a.y).distance_to(Vector2(p.x, p.y)) if a.z == p.z else 6.0
		if p.z == level:
			pts.append(Vector2(p.x + 0.5, p.y + 0.5))
			dist.append(total)
		elif not pts.is_empty():
			_close(out, pts, dist, corner_cells, corner_steps, lay)
			pts = PackedVector2Array()
			dist = PackedFloat32Array()
	_close(out, pts, dist, corner_cells, corner_steps, lay)
	return out


static func _close(out: Array[Dictionary], pts: PackedVector2Array, dist: PackedFloat32Array, corner_cells: float, corner_steps: int, lay: Dictionary = {}) -> void:
	if pts.size() < 2:
		return
	var slack_from := dist[0]
	# 0) 호스가 시작하는 조각: 차 몸통 밑을 지나는 점을 버리고 후면 방수구에서 나오게 한다 (D5)
	if lay.has("port") and dist[0] <= 0.0001:
		var joined := with_port(pts, dist, lay.port, lay.port_out, lay.body, lay.get("port_corner"), lay.get("port_front"))
		pts = joined.pts
		dist = joined.dist
		slack_from = joined.from
	# 1) 일직선 위의 점을 뺀다
	var sp := PackedVector2Array([pts[0]])
	var sd := PackedFloat32Array([dist[0]])
	for k in range(1, pts.size() - 1):
		var a := (pts[k] - sp[sp.size() - 1]).normalized()
		var b := (pts[k + 1] - pts[k]).normalized()
		if a.dot(b) < 0.999:
			sp.append(pts[k])
			sd.append(dist[k])
	sp.append(pts[pts.size() - 1])
	sd.append(dist[dist.size() - 1])
	# 2) 꺾이는 곳을 둥글린다: 모서리 앞뒤 r 칸 지점을 잇는 2차 곡선 (r은 옆 구간 길이의 절반까지)
	var rp := PackedVector2Array([sp[0]])
	var rd := PackedFloat32Array([sd[0]])
	for k in range(1, sp.size() - 1):
		var before := sp[k].distance_to(sp[k - 1])
		var after := sp[k].distance_to(sp[k + 1])
		var r := minf(corner_cells, minf(before, after) * 0.5)
		if r <= 0.01 or corner_steps < 2:
			rp.append(sp[k])
			rd.append(sd[k])
			continue
		var p0 := sp[k].move_toward(sp[k - 1], r)
		var p2 := sp[k].move_toward(sp[k + 1], r)
		# 곡선 양 끝의 거리: 옆 구간에서 r만큼 들어간 자리 (구간의 거리가 실제 길이와 같으면 모서리 거리 ∓ r)
		var d_in := sd[k] - (sd[k] - sd[k - 1]) * r / before
		var d_out := sd[k] + (sd[k + 1] - sd[k]) * r / after
		for s in corner_steps + 1:
			var t := float(s) / corner_steps
			rp.append(p0.lerp(sp[k], t).lerp(sp[k].lerp(p2, t), t))
			rd.append(lerpf(d_in, d_out, t))
	rp.append(sp[sp.size() - 1])
	rd.append(sd[sd.size() - 1])
	out.append({"pts": rp, "dist": rd, "slack_from": slack_from})


## 호스의 시작을 펌프차 후면 방수구로 옮기고, 차 몸통 밑을 지나지 않게 한다 (D5 — 그림만. 길 찾기는 차를 피하지 않는다):
## 방수구(port) → 그 바로 바깥(port_out) → 원래 길. 차 몸통(body) 안의 점은 버리고, 그 사이를 이은 선이 차에 걸리면
## 차 모서리 바깥(corner = 뒤 모서리, front = 앞 모서리)을 돌아간다.
## 거리는 방수구가 0이고 원래 길의 점은 원래 거리 그대로다 (결합구·물머리 자리가 바뀌지 않는다) — 끼워 넣은 점은 그 사이를 나눈다.
## from = 방수구 바로 바깥의 거리 — 거기서부터 여유 호스 굽이를 둘 수 있다
static func with_port(pts: PackedVector2Array, dist: PackedFloat32Array, port: Vector2, port_out: Vector2, body: PackedVector2Array,
		corner: Variant = null, front: Variant = null) -> Dictionary:
	# 1) 차 몸통 안의 점을 버린다 (남긴 점의 원래 번호를 기억한다)
	var kp := PackedVector2Array()
	var kd := PackedFloat32Array()
	var ki := PackedInt32Array()
	for i in pts.size():
		if not Geometry2D.is_point_in_polygon(pts[i], body) or i == pts.size() - 1:
			kp.append(pts[i])
			kd.append(dist[i])
			ki.append(i)
	# 2) 방수구 바깥에서 원래 길로: 곧장 이으면 차에 걸릴 때는 모서리를 돌고,
	#    아니면 가까워지는 동안의 점은 건너뛴다 (되돌아가는 갈고리가 생기지 않게)
	var np := PackedVector2Array([port, port_out])
	var nd := PackedFloat32Array([0.0, -1.0])
	var k := 0
	if _crosses(port_out, kp[0], body):
		for via in _detour(port_out, kp[0], body, corner, front):
			np.append(via)
			nd.append(-1.0)
	else:
		while k + 1 < kp.size() and port_out.distance_squared_to(kp[k + 1]) < port_out.distance_squared_to(kp[k]) and not _crosses(port_out, kp[k + 1], body):
			k += 1
	# 3) 차례로 잇는다. 점을 버린 곳에서 이은 선이 차에 걸리면 모서리 바깥을 돈다
	for i in range(k, kp.size()):
		if i > k and ki[i] != ki[i - 1] + 1 and _crosses(kp[i - 1], kp[i], body):
			for via in _detour(kp[i - 1], kp[i], body, corner, front):
				np.append(via)
				nd.append(-1.0)
		np.append(kp[i])
		nd.append(kd[i])
	# 4) 끼워 넣은 점(-1)의 거리: 앞뒤 원래 점의 거리 사이를 화면 길이 비율로 나눈다
	var known := 0
	for j in range(1, np.size()):
		if nd[j] < 0.0:
			continue
		if j - known > 1:
			var total := 0.0
			for m in range(known + 1, j + 1):
				total += np[m - 1].distance_to(np[m])
			var gone := 0.0
			for m in range(known + 1, j):
				gone += np[m - 1].distance_to(np[m])
				nd[m] = lerpf(nd[known], nd[j], gone / total if total > 0.0 else 0.0)
		known = j
	for j in range(1, np.size()):
		nd[j] = maxf(nd[j], nd[j - 1] + 0.01)
	return {"pts": np, "dist": nd, "from": nd[1]}


## a와 b를 이은 선이 차 몸통에 걸리는가
static func _crosses(a: Vector2, b: Vector2, body: PackedVector2Array) -> bool:
	if a.is_equal_approx(b):
		return false
	return not Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), body).is_empty()


## a에서 b로 차 몸통을 피해 가려면 거쳐야 하는 모서리 바깥 점들 (뒤 모서리·앞 모서리 가운데 걸리지 않는 가장 짧은 조합). 없으면 빈 것
static func _detour(a: Vector2, b: Vector2, body: PackedVector2Array, rear: Variant, front: Variant) -> PackedVector2Array:
	var options: Array[PackedVector2Array] = []
	if rear is Vector2:
		options.append(PackedVector2Array([rear]))
	if front is Vector2:
		options.append(PackedVector2Array([front]))
	if rear is Vector2 and front is Vector2:
		options.append(PackedVector2Array([rear, front]))
		options.append(PackedVector2Array([front, rear]))
	for via in options:
		var line := PackedVector2Array([a])
		line.append_array(via)
		line.append(b)
		if Geometry2D.intersect_polyline_with_polygon(line, body).is_empty():
			return via
	return PackedVector2Array()


## 점들을 따라 잰 실제 길이 (칸, 첫 점 0)
static func _lengths(pts: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		out.append(out[k - 1] + pts[k - 1].distance_to(pts[k]))
	return out


## xs(늘기만 하는 값)에서 x가 놓인 자리의 ys 값 (구간마다 곧게 이음, 밖이면 끝 값)
static func _map(xs: PackedFloat32Array, ys: PackedFloat32Array, x: float) -> float:
	if x <= xs[0]:
		return ys[0]
	for k in range(1, xs.size()):
		if x <= xs[k]:
			var span := xs[k] - xs[k - 1]
			return lerpf(ys[k - 1], ys[k], (x - xs[k - 1]) / span if span > 0.0 else 1.0)
	return ys[ys.size() - 1]


## 여유 호스 굽이 (D5 — 그림만): windows = [[from, to, 크기 비율]] 거리 구간마다 호스를 옆으로 구불구불 휘게 한다.
## 구간 양 끝에서는 휘는 양이 0이라 앞뒤와 매끄럽게 이어지고, 점마다 거리는 그대로다 (옆으로만 옮긴다).
## amp = 가장 크게 휘는 폭(칸), wave = 굽이 하나의 길이(칸), step = 점 간격(칸) — 굽이 모양은 화면에 놓인 실제 길이로 잰다
static func with_slack(run: Dictionary, windows: Array, amp: float, wave: float, step: float) -> Dictionary:
	if amp <= 0.001 or windows.is_empty() or wave <= 0.0 or step <= 0.0:
		return run
	var pts: PackedVector2Array = run.pts
	var dist: PackedFloat32Array = run.dist
	var geo := _lengths(pts)
	var first := dist[0]
	var last := dist[dist.size() - 1]
	var np := PackedVector2Array()
	var nd := PackedFloat32Array()
	var k := 0
	for w: Array in windows:
		var a := maxf(float(w[0]), first)
		var b := minf(float(w[1]), last)
		var ga := _map(dist, geo, a)
		var gb := _map(dist, geo, b)
		if gb - ga < wave * 0.5 or (not nd.is_empty() and a < nd[nd.size() - 1]):
			continue
		while k < pts.size() and dist[k] < a - 0.001:
			np.append(pts[k])
			nd.append(dist[k])
			k += 1
		var n := maxi(4, ceili((gb - ga) / step))
		var waves := maxf(1.0, roundf((gb - ga) / wave))
		for s in n + 1:
			var u := float(s) / n
			var g := lerpf(ga, gb, u)
			var d := a if s == 0 else (b if s == n else _map(geo, dist, g))
			if not nd.is_empty() and d <= nd[nd.size() - 1]:
				continue
			var t := point_at(run, _map(geo, dist, minf(gb, g + step))) - point_at(run, _map(geo, dist, maxf(ga, g - step)))
			var side := t.normalized().orthogonal() if t.length_squared() > 0.000001 else Vector2.ZERO
			np.append(point_at(run, d) + side * amp * float(w[2]) * sin(PI * u) * sin(TAU * waves * u))
			nd.append(d)
		while k < pts.size() and dist[k] <= b + 0.001:
			k += 1
	while k < pts.size():
		np.append(pts[k])
		nd.append(dist[k])
		k += 1
	return {"pts": np, "dist": nd, "slack_from": run.get("slack_from", first)}


## 조각 위 거리 d에서 화면에 놓인 길이로 length(칸)만큼 더 간 곳의 거리
static func dist_ahead(run: Dictionary, d: float, length: float) -> float:
	var geo := _lengths(run.pts)
	return _map(geo, run.dist, _map(run.dist, geo, d) + length)


## 굽이 크기 (0~1): 남은 호스가 전체의 full_ratio 이상이면 1, 줄어들수록 펴져 한계에서 0 (팽팽). 한도를 모르면 1
static func slack_amount(length_cells: float, max_cells: float, full_ratio: float) -> float:
	if max_cells <= 0.0 or full_ratio <= 0.0:
		return 1.0
	return clampf((max_cells - length_cells) / (max_cells * full_ratio), 0.0, 1.0)


## 호스가 건물에 처음 들어서는 거리 (칸) — 밖에서 시작해 건물 칸(바닥·문·계단 등)을 처음 밟는 점. 없으면 -1
static func entry_dist(h: HoseLine, building: BuildingData) -> float:
	if h.points.is_empty() or building.cell(h.points[0].z, h.points[0].x, h.points[0].y) in BuildingData.STRUCTURE:
		return -1.0
	var total := 0.0
	for k in range(1, h.points.size()):
		var a := h.points[k - 1]
		var p := h.points[k]
		total += Vector2(a.x, a.y).distance_to(Vector2(p.x, p.y)) if a.z == p.z else 6.0
		if building.cell(p.z, p.x, p.y) in BuildingData.STRUCTURE:
			return total
	return -1.0


## 펌프차 후면 방수구 {port, port_out, port_corner, port_front, body} (칸 좌표) — 펌프차는 후면 셔터 안에 동작 패널과 방수구가 있다
## (2026-11-21 사용자·현직 소방관). 방수구는 후면 가운데에서 호스가 나가는 쪽으로 across_ratio × 차 폭만큼 비켜 있다
## (호스가 옆으로 벗어나지 않으면 가운데). port_out = 방수구에서 clear_cells만큼 뒤,
## port_corner·port_front = 호스가 나가는 쪽의 뒤·앞 모서리 바깥 (차 옆을 따라 앞으로 갈 때 돌아가는 곳).
## 호스가 차에서 떨어진 곳에서 시작하면 빈 것 (차가 자리를 옮긴 뒤 등)
static func port_of(h: HoseLine, v: Vehicle, across_ratio: float, clear_cells: float) -> Dictionary:
	if h.points.is_empty() or h.points[0].z != v.level:
		return {}
	var first := Vector2(h.points[0].x + 0.5, h.points[0].y + 0.5)
	if v.distance_to_body(first) > clear_cells + 1.5:
		return {}
	var side_dir := Vector2(-v.heading.y, v.heading.x)
	var side := 0.0
	for p in h.points:
		if p.z != v.level:
			break
		var across := (Vector2(p.x + 0.5, p.y + 0.5) - v.pos).dot(side_dir)
		if absf(across) > v.width_cells * 0.5 + clear_cells:
			side = signf(across)
			break
	var shift := side * v.width_cells * across_ratio
	# 돌아갈 모서리: 호스가 나가는 쪽 (옆으로 벗어나지 않으면 오른쪽)
	var edge := (side if side != 0.0 else 1.0) * (v.width_cells * 0.5 + clear_cells)
	return {
		"port": v.rear_point(0.0, shift),
		"port_out": v.rear_point(clear_cells, shift),
		"port_corner": v.rear_point(clear_cells, edge),
		"port_front": v.pos + v.heading * (v.length_cells * 0.5 + clear_cells) + side_dir * edge,
		"body": v.footprint(),
	}


## 물을 싣는 차인가 (펌프차·물탱크차) — 급수 호스가 후면에 붙는 차
static func has_rear_panel(v: Vehicle) -> bool:
	return v.is_pump() or v.transfer_lpm > 0.0


## 급수 호스가 차에 붙는 자리 (칸 좌표): 펌프차·물탱크차는 후면(보수구·방수구) — 후면에서 호스가 오는 쪽 끝
## (2026-11-21 사용자·현직 소방관: 펌프차 후면에 동작 패널, 물탱크차도 같다). 그 밖의 차는 가장 가까운 차체 둘레
static func intake_point(v: Vehicle, toward: Vector2) -> Vector2:
	if not has_rear_panel(v):
		return v.closest_body_point(toward)
	var across := (toward - v.pos).dot(Vector2(-v.heading.y, v.heading.x))
	return v.rear_point(0.0, signf(across) * v.width_cells * float(style().get("intake_across_ratio", 0.45)))


## 급수 호스가 놓이는 길 (칸 좌표): from(소화전·급수하는 차 쪽 끝)에서 차의 급수 자리(intake_point)까지.
## 곧게 이으면 차 몸통에 걸릴 때는 (예: 앞에 선 차에서 올 때) 차 모서리 바깥을 돌아 후면으로 간다
static func supply_route(v: Vehicle, from: Vector2, cell_m: float) -> PackedVector2Array:
	var into := intake_point(v, from)
	var body := v.footprint()
	if not has_rear_panel(v) or not _crosses(from, into, body):
		return PackedVector2Array([from, into])
	var clear := float(style().get("port_clear_m", 0.8)) / cell_m
	var side_dir := Vector2(-v.heading.y, v.heading.x)
	var side := signf((from - v.pos).dot(side_dir))
	var edge := (side if side != 0.0 else 1.0) * (v.width_cells * 0.5 + clear)
	var behind := into - v.heading * clear
	var out := PackedVector2Array([from])
	if _crosses(from, behind, body):
		out.append_array(_detour(from, behind, body, v.rear_point(clear, edge), v.pos + v.heading * (v.length_cells * 0.5 + clear) + side_dir * edge))
	out.append(behind)
	out.append(into)
	return out


## 차에서 차로 가는 급수 호스의 길 (물탱크차 → 펌프차): src 후면에서 나와 dst 후면으로 — 두 차의 몸통을 모두 돌아간다
static func supply_between(src: Vehicle, dst: Vehicle, cell_m: float) -> PackedVector2Array:
	var into := intake_point(dst, src.rear_point())
	# src 쪽: 받는 차의 급수 자리를 보고 나가는 길 (뒤집으면 src 후면에서 시작)
	var out := supply_route(src, into, cell_m)
	out.reverse()
	out.remove_at(out.size() - 1)
	# dst 쪽: src를 벗어난 마지막 점에서 받는 차의 후면까지
	var last := out[out.size() - 1]
	var tail := supply_route(dst, last, cell_m)
	for k in range(1, tail.size()):
		out.append(tail[k])
	return out


## 길의 앞부분만 (전체 길이의 f, 0~1) — 호스를 굴려 펴는 중인 모습
static func cut(pts: PackedVector2Array, f: float) -> PackedVector2Array:
	var geo := _lengths(pts)
	var upto := geo[geo.size() - 1] * clampf(f, 0.0, 1.0)
	var out := PackedVector2Array([pts[0]])
	for k in range(1, pts.size()):
		if geo[k] <= upto:
			out.append(pts[k])
			continue
		var span := geo[k] - geo[k - 1]
		out.append(pts[k - 1].lerp(pts[k], (upto - geo[k - 1]) / span if span > 0.0 else 0.0))
		break
	return out


## 호스 한 줄의 배치 (D5): 방수구 자리(펌프차에서 연장한 호스만)·건물에 들어서는 거리·굽이 크기. draw에 넘긴다.
## v = 물을 대는 펌프차 (옥내 방수구에서 연장했으면 없어도 된다)
static func layout(h: HoseLine, v: Vehicle, building: BuildingData) -> Dictionary:
	var key := [h.points.size(), h.points[0] if not h.points.is_empty() else Vector3i.ZERO, h.points[-1] if not h.points.is_empty() else Vector3i.ZERO,
		h.max_cells, h.outlet, v.pos if v != null else Vector2.ZERO, v.heading if v != null else Vector2.ZERO]
	var cached: Dictionary = _lay_cache.get(h.get_instance_id(), {})
	if not cached.is_empty() and cached.key == key:
		return cached.lay
	var st := style()
	var lay := {
		"amount": slack_amount(h.length_cells(), h.max_cells, float(st.get("slack_full_ratio", 0.3))),
		"entry": entry_dist(h, building),
		"indoor_start": h.outlet >= 0,
	}
	if h.outlet < 0 and v != null:
		lay.merge(port_of(h, v, float(st.get("port_across_ratio", 0.25)), float(st.get("port_clear_m", 0.5)) / building.cell_size_m))
	if _lay_cache.size() > 64:
		_lay_cache.clear()
	_lay_cache[h.get_instance_id()] = {"key": key, "lay": lay}
	return lay


## 조각에 둘 여유 호스 굽이 구간 [[from, to, 크기 비율]] (칸): ① 호스가 시작하는 조각의 방수구 옆 ② 건물에 들어서기 조금 앞.
## 옥내 방수구 옆은 좁으므로 작게 휜다
static func slack_windows(run: Dictionary, lay: Dictionary, cell_m: float) -> Array:
	var out: Array = []
	if lay.is_empty():
		return out
	var st := style()
	var length := float(st.get("slack_length_m", 4.0)) / cell_m
	var d0: float = run.dist[0]
	var d1: float = run.dist[run.dist.size() - 1]
	var used := d0
	if d0 <= 0.0001:
		var a := float(run.get("slack_from", d0))
		# 방수구 앞머리는 거리가 눌려 있으므로 화면에 놓인 길이로 잰다
		used = minf(dist_ahead(run, a, length), d1)
		out.append([a, used, float(st.get("slack_indoor_ratio", 0.5)) if bool(lay.get("indoor_start", false)) else 1.0])
	var entry := float(lay.get("entry", -1.0)) - float(st.get("slack_door_gap_m", 1.0)) / cell_m
	if entry > d0 and entry <= d1:
		out.append([maxf(entry - length, used), entry, 1.0])
	return out


## 그 층에 그릴 호스 조각들 — runs에 방수구 시작점과 여유 호스 굽이(lay = layout의 결과)를 입힌 것
static func shaped_runs(h: HoseLine, level: int, cell_m: float, lay: Dictionary = {}) -> Array[Dictionary]:
	var st := style()
	var out: Array[Dictionary] = []
	var amp := float(st.get("slack_amp_m", 0.4)) / cell_m * float(lay.get("amount", 0.0))
	for run in runs(h, level, float(st.get("corner_radius_m", 0.6)) / cell_m, int(st.get("corner_steps", 4)), lay):
		out.append(with_slack(run, slack_windows(run, lay, cell_m), amp, float(st.get("slack_wave_m", 2.0)) / cell_m, float(st.get("slack_step_m", 0.25)) / cell_m))
	return out


## 조각에서 거리 from~to 사이만 잘라 낸 점들 (칸 좌표). 그 사이에 걸친 것이 없으면 빈 것
static func slice(run: Dictionary, from: float, to: float) -> PackedVector2Array:
	var pts: PackedVector2Array = run.pts
	var dist: PackedFloat32Array = run.dist
	var out := PackedVector2Array()
	var a := maxf(from, dist[0])
	var b := minf(to, dist[dist.size() - 1])
	if b - a <= 0.001:
		return out
	out.append(point_at(run, a))
	for k in pts.size():
		if dist[k] > a and dist[k] < b:
			out.append(pts[k])
	out.append(point_at(run, b))
	return out


## 조각 위에서 거리 d인 지점 (칸 좌표). 조각 밖이면 가까운 끝
static func point_at(run: Dictionary, d: float) -> Vector2:
	var pts: PackedVector2Array = run.pts
	var dist: PackedFloat32Array = run.dist
	if d <= dist[0]:
		return pts[0]
	for k in range(1, pts.size()):
		if d <= dist[k]:
			var span := dist[k] - dist[k - 1]
			return pts[k - 1].lerp(pts[k], (d - dist[k - 1]) / span if span > 0.0 else 0.0)
	return pts[pts.size() - 1]


## 호스 끝(관창수)에서 거슬러 가는 길 (호스 끼고 걷기 — docs/motions.md E2·E3): 그 층에 이어져 깔린 마지막 부분의 점들(칸 좌표)에
## 관창수의 지금 자리(at)를 끝으로 맞춘 것. dist = 펌프차 쪽 끝부터 잰 거리 (칸) — 끝 거리는 관창수가 걷는 만큼 부드럽게 늘어난다
## (호스 점은 칸 단위로 늘지만, 뒤따르는 대원의 자리가 튀지 않게). 그 층에 깔린 것이 없으면 빈 것
static func trail(h: HoseLine, level: int, at: Vector2) -> Dictionary:
	var n := h.points.size()
	if n == 0 or h.points[n - 1].z != level:
		return {}
	var first := n - 1
	while first > 0 and h.points[first - 1].z == level:
		first -= 1
	var pts := PackedVector2Array()
	var dist := PackedFloat32Array()
	var d := h.length_cells()
	for k in range(n - 1, first - 1, -1):
		pts.append(Vector2(h.points[k].x + 0.5, h.points[k].y + 0.5))
		dist.append(d)
		if k > first:
			d -= Vector2(h.points[k].x, h.points[k].y).distance_to(Vector2(h.points[k - 1].x, h.points[k - 1].y))
	pts.reverse()
	dist.reverse()
	var last := pts.size() - 1
	var b := pts[last]
	if last >= 1:
		var a := pts[last - 1]
		var t := (at - a).dot(b - a) / maxf(0.0001, (b - a).length_squared())
		if t < 1.0:
			# 관창수가 아직 마지막 칸 가운데에 닿지 않았다: 끝을 그 자리까지로 당긴다
			var on := a + (b - a) * clampf(t, 0.0, 1.0)
			pts[last] = on
			dist[last] = dist[last - 1] + a.distance_to(on)
			return {"pts": pts, "dist": dist}
	if at.distance_to(b) > 0.01:
		pts.append(at)
		dist.append(dist[last] + at.distance_to(b))
	return {"pts": pts, "dist": dist}


## 납작한(물이 차지 않은) 호스를 바닥에 그릴 거리 구간들 [[from, to]]: head(물머리)부터, stop(바닥 호스가 끝나는 거리 — 그 앞은 대원이 끼고 있다)까지,
## gap [from, to](대원이 들어 올린 구간)은 뺀다
static func dry_ranges(head: float, stop: float, gap: Array) -> Array:
	var out: Array = []
	if stop <= head:
		return out
	if gap.size() != 2 or float(gap[1]) <= head or float(gap[0]) >= stop:
		out.append([head, stop])
		return out
	if float(gap[0]) > head:
		out.append([head, float(gap[0])])
	if float(gap[1]) < stop:
		out.append([float(gap[1]), stop])
	return out


## 조각에 놓이는 결합구 거리들 (칸): 펌프차 쪽 끝(0)부터 1본(length_cells)마다. 관창 쪽 끝에는 두지 않는다
static func couplings(run: Dictionary, length_cells: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var dist: PackedFloat32Array = run.dist
	if length_cells <= 0.0:
		return out
	var k := ceili(dist[0] / length_cells - 0.0001)
	while k * length_cells < dist[dist.size() - 1] - 0.01:
		out.append(k * length_cells)
		k += 1
	return out


## 호스 한 줄을 그린다. to_screen: 칸 좌표 → 화면 좌표, px_per_m: 화면 1m의 길이(px), cell_m: 칸 크기(m),
## head_cells: 물머리 위치(펌프차 쪽 끝부터, 칸) — 그 앞은 부푼 호스, 뒤는 납작한 호스. length_cells: 1본 길이(칸),
## up: 높이 1m가 화면에서 올라가는 거리 (입체 화면 = 위쪽, 평면 화면 = 0) — 부푼 호스를 반지름만큼 띄워 그린다.
## 입체로 보이게 겹쳐 그린다 (2026-11-21 사용자 요청 — 진짜 3D가 아니라 선을 겹친 음영):
##   부푼 호스: 바닥 그림자 → 테두리 → 몸통 → 그늘진 쪽 → 밝은 쪽 → 반짝이는 줄, 바닥에서 반지름만큼 뜸
##   납작한 호스: 바닥에 붙은 띠 + 가운데 접힌 줄 + 빛 받는 가장자리
##   결합구: 호스 방향으로 놓인 짧은 금속 원통. 물머리: 불룩한 마디
## 빛은 한 방향(light_dir)에서 온다 — 호스가 어느 쪽으로 누워 있든 빛을 받는 쪽이 밝다.
## lay: layout의 결과 — 방수구 시작점·여유 호스 굽이 (D5). 비어 있으면 칸 중심을 잇는 길 그대로
static func draw(ci: CanvasItem, h: HoseLine, level: int, to_screen: Callable, px_per_m: float, cell_m: float, head_cells: float, length_cells: float, up := Vector2.ZERO, lay: Dictionary = {}) -> void:
	var st := style()
	var flat_w := float(st.get("flat_width_m", 0.2)) * px_per_m
	var round_w := float(st.get("round_width_m", 0.13)) * px_per_m
	var light := _vec(st.get("light_dir", [-0.5, -0.85])).normalized()
	var shadow := Color(Color(str(st.get("shadow_color", "#000000"))), float(st.get("shadow_alpha", 0.35)))
	# 그림자는 빛 반대쪽 바닥에 떨어진다
	var cast := -light * round_w * float(st.get("shadow_offset_ratio", 0.45))
	var lift := up * float(st.get("round_width_m", 0.13)) * 0.5
	# 호스 끼고 걷는 중이면 (lay.ground_end·gap — FloorLayer._hose_carry_layout): 바닥 호스는 2번 대원 뒤에서 끝나고, 3번이 들어 올린 구간은 비운다
	var stop := float(lay.get("ground_end", INF))
	var gap: Array = lay.get("gap", [])
	# ground_tail: 바닥 호스의 끝을 이어 줄 자리 (칸 좌표) — 2번 대원 그림의 호스가 바닥에 닿은 곳
	var tail: Variant = lay.get("ground_tail")
	for run in shaped_runs(h, level, cell_m, lay):
		for part: Array in dry_ranges(head_cells, stop, gap):
			var cells := slice(run, float(part[0]), float(part[1]))
			if tail is Vector2 and not cells.is_empty() and float(part[1]) == stop and stop <= float(run.dist[run.dist.size() - 1]):
				cells.append(tail)
			var dry := _screen(cells, to_screen)
			if dry.size() < 2:
				continue
			ci.draw_polyline(_shift(dry, cast * 0.3), Color(shadow, shadow.a * 0.6), flat_w)
			ci.draw_polyline(dry, Color(str(st.get("flat_edge_color", "#7d7455"))), flat_w + 1.5)
			ci.draw_polyline(dry, Color(str(st.get("flat_color", "#cfc5a8"))), flat_w)
			ci.draw_polyline(_lit(dry, light, flat_w * 0.34), Color(str(st.get("flat_light_color", "#e9e0c6"))), maxf(1.0, flat_w * 0.2))
			ci.draw_polyline(dry, Color(Color(str(st.get("flat_crease_color", "#8f8669"))), 0.7), maxf(1.0, flat_w * 0.1))
		var ground := _screen(slice(run, -INF, head_cells), to_screen)
		if ground.size() >= 2:
			var wet := _shift(ground, lift)
			ci.draw_polyline(_shift(ground, cast), shadow, round_w)
			ci.draw_polyline(wet, Color(str(st.get("round_shade_color", "#3d3622"))), round_w + 2.0)
			ci.draw_polyline(wet, Color(str(st.get("round_color", "#dccd9c"))), round_w)
			ci.draw_polyline(_lit(wet, light, -round_w * 0.3), Color(str(st.get("round_dark_color", "#9c8c5e"))), maxf(1.0, round_w * 0.36))
			ci.draw_polyline(_lit(wet, light, round_w * 0.16), Color(str(st.get("round_light_color", "#f6edcf"))), maxf(1.0, round_w * 0.44))
			ci.draw_polyline(_lit(wet, light, round_w * 0.28), Color(Color(str(st.get("round_highlight_color", "#ffffff"))), 0.85), maxf(1.0, round_w * 0.14))
		# 물머리: 차오르는 중이면 불룩한 마디
		var d0: float = run.dist[0]
		var d1: float = run.dist[run.dist.size() - 1]
		if head_cells > d0 + 0.05 and head_cells < d1 - 0.05:
			var at: Vector2 = to_screen.call(point_at(run, head_cells)) + lift
			var r := round_w * float(st.get("head_bulge_ratio", 0.8))
			ci.draw_circle(at - lift + cast, r, shadow)
			ci.draw_circle(at, r + 1.0, Color(str(st.get("round_shade_color", "#3d3622"))))
			ci.draw_circle(at, r, Color(str(st.get("round_color", "#dccd9c"))))
			ci.draw_circle(at + light * r * 0.35, r * 0.45, Color(str(st.get("round_light_color", "#f6edcf"))))
		# 결합구: 호스 방향으로 놓인 짧은 금속 원통 (물이 찬 쪽은 호스와 같이 떠 있다)
		var half := float(st.get("coupling_length_m", 0.2)) / cell_m * 0.5
		var joint_w := round_w * float(st.get("coupling_width_ratio", 1.5))
		# 결합구 길이는 화면에 놓인 길이로 잰다 (방수구 앞머리는 거리가 눌려 있다)
		var geo := _lengths(run.pts)
		for d in couplings(run, length_cells):
			if d > stop or (gap.size() == 2 and d > float(gap[0]) and d < float(gap[1])):
				continue  # 대원이 끼고 있거나 들어 올린 곳 — 그 그림에 들어 있다
			var raise := lift if d < head_cells else Vector2.ZERO
			var g := _map(run.dist, geo, d)
			var a: Vector2 = to_screen.call(point_at(run, _map(geo, run.dist, maxf(0.0, g - half)))) + raise
			var b: Vector2 = to_screen.call(point_at(run, _map(geo, run.dist, minf(geo[geo.size() - 1], g + half)))) + raise
			if a.distance_to(b) < 1.0:
				continue
			var n := (b - a).normalized().orthogonal()
			var side := n * n.dot(light)
			ci.draw_line(a - raise + cast, b - raise + cast, shadow, joint_w)
			ci.draw_line(a, b, Color(str(st.get("coupling_edge_color", "#2b3138"))), joint_w + 2.0)
			ci.draw_line(a, b, Color(str(st.get("coupling_color", "#aab2ba"))), joint_w)
			ci.draw_line(a + side * joint_w * 0.25, b + side * joint_w * 0.25, Color(str(st.get("coupling_light_color", "#eef2f5"))), maxf(1.0, joint_w * 0.22))


static func _vec(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2(-0.5, -0.85)


static func _shift(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out


## 선을 빛 받는 쪽으로 amount만큼 옮긴 것 (음수면 그늘 쪽). 옮기는 양은 그 자리에서 호스가 빛과 이루는 각에 따른다:
## 빛과 직각으로 누운 곳은 한쪽 옆이 다 밝고, 빛과 나란한 곳은 양옆이 같아 가운데에 머문다 — 꺾여도 밝은 쪽이 튀지 않는다
static func _lit(pts: PackedVector2Array, light: Vector2, amount: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in pts.size():
		var t := pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]
		var n := t.normalized().orthogonal() if t.length_squared() > 0.0001 else Vector2.ZERO
		out.append(pts[k] + n * n.dot(light) * amount)
	return out


static func _screen(pts: PackedVector2Array, to_screen: Callable) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(to_screen.call(p))
	return out
