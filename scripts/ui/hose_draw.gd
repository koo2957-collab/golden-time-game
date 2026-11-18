class_name HoseDraw
extends RefCounted
## 소방호스 그리기 (docs/motions.md '라. 소방호스 표현', 2026-11-18). 입체 화면(FloorLayer)과 평면 화면(UnitsView)이 같이 쓴다.
##   D1 납작한 호스 (송수 전): 넓고 납작한 띠
##   D2 부푼 호스 (송수 뒤): 좁고 통통한 관 (아래 그늘·위 밝은 줄)
##   D4 결합구: 1본(15m)마다 금속 고리
## 꺾이는 곳은 둥글린다. 색·폭은 data/ui/hose_style.json (화면 설정 — 시뮬레이션과 상관없다)

const PATH := "res://data/ui/hose_style.json"

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


## 그 층에 놓인 호스 조각들 [{pts: PackedVector2Array (칸 좌표), dist: PackedFloat32Array (펌프차 쪽 끝부터 잰 거리, 칸)}].
## 일직선 위의 점은 빼고, 꺾이는 곳은 corner_cells 반지름으로 둥글린다. 다른 층을 지나면 조각이 나뉜다 (계단 한 층 = HoseLine.length_cells와 같은 6칸)
static func runs(h: HoseLine, level: int, corner_cells: float, corner_steps: int) -> Array[Dictionary]:
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
			_close(out, pts, dist, corner_cells, corner_steps)
			pts = PackedVector2Array()
			dist = PackedFloat32Array()
	_close(out, pts, dist, corner_cells, corner_steps)
	return out


static func _close(out: Array[Dictionary], pts: PackedVector2Array, dist: PackedFloat32Array, corner_cells: float, corner_steps: int) -> void:
	if pts.size() < 2:
		return
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
		for s in corner_steps + 1:
			var t := float(s) / corner_steps
			rp.append(p0.lerp(sp[k], t).lerp(sp[k].lerp(p2, t), t))
			rd.append(sd[k] - r + 2.0 * r * t)
	rp.append(sp[sp.size() - 1])
	rd.append(sd[sd.size() - 1])
	out.append({"pts": rp, "dist": rd})


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
## head_cells: 물머리 위치(펌프차 쪽 끝부터, 칸) — 그 앞은 부푼 호스, 뒤는 납작한 호스. length_cells: 1본 길이(칸)
static func draw(ci: CanvasItem, h: HoseLine, level: int, to_screen: Callable, px_per_m: float, cell_m: float, head_cells: float, length_cells: float) -> void:
	var st := style()
	var flat_w := float(st.get("flat_width_m", 0.16)) * px_per_m
	var round_w := float(st.get("round_width_m", 0.1)) * px_per_m
	var joint_r := float(st.get("coupling_radius_m", 0.09)) * px_per_m
	for run in runs(h, level, float(st.get("corner_radius_m", 0.6)) / cell_m, int(st.get("corner_steps", 4))):
		var dry := _screen(slice(run, head_cells, INF), to_screen)
		if dry.size() >= 2:
			ci.draw_polyline(dry, Color(str(st.get("flat_edge_color", "#8f8669"))), flat_w + 1.5)
			ci.draw_polyline(dry, Color(str(st.get("flat_color", "#cfc5a8"))), flat_w)
		var wet := _screen(slice(run, -INF, head_cells), to_screen)
		if wet.size() >= 2:
			ci.draw_polyline(wet, Color(str(st.get("round_shade_color", "#5b5136"))), round_w + 2.0)
			ci.draw_polyline(wet, Color(str(st.get("round_color", "#f2e6c4"))), round_w)
			# 위쪽 밝은 줄: 화면 위로 조금 올려 그어 둥근 관처럼
			var lit := PackedVector2Array()
			for p in wet:
				lit.append(p + Vector2(0.0, -round_w * 0.22))
			ci.draw_polyline(lit, Color(Color(str(st.get("round_highlight_color", "#ffffff"))), 0.75), maxf(1.0, round_w * 0.28))
		for d in couplings(run, length_cells):
			var at: Vector2 = to_screen.call(point_at(run, d))
			ci.draw_circle(at, joint_r + 1.0, Color(str(st.get("coupling_edge_color", "#2b3138"))))
			ci.draw_circle(at, joint_r, Color(str(st.get("coupling_color", "#b8c0c8"))))


static func _screen(pts: PackedVector2Array, to_screen: Callable) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(to_screen.call(p))
	return out
