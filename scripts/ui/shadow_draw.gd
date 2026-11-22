class_name ShadowDraw
extends RefCounted
## 미리 그려 넣는 그림자·음영 (입체감 1단계, 2026-11-22). 입체 화면(FloorLayer)과 배경 도시(CityMassView)가 같이 쓴다.
##   1) 건물·차량·가구가 땅에 드리우는 그림자: 바닥 다각형을 빛 반대쪽으로 밀어 낸 모양 (sweep_quads·sweep_hull)
##   2) 발밑 그림자: 가장자리가 옅어지는 납작한 타원 (soft_ellipse)
##   3) 벽 아래 어두운 띠: 벽 쪽은 진하고 바닥 쪽으로 투명해지는 사각형 (box_bands·merge_bands·band_quad)
## 실시간 광원·그림자가 아니다 — 반투명한 어두운 도형을 바닥 위에 그릴 뿐이다 (GPU 없는 사무용 PC).
## 빛이 오는 쪽은 소방호스와 같다 (data/ui/hose_style.json light_dir). 진하기·크기는 data/ui/shadow_style.json (화면 설정)

const PATH := "res://data/ui/shadow_style.json"
## 띠가 번지는 쪽 (비트). 순서는 NORMALS 와 같다
const WEST := 1
const NORTH := 2
const EAST := 4
const SOUTH := 8
const SIDES: Array[int] = [WEST, NORTH, EAST, SOUTH]
const NORMALS: Array[Vector2] = [Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1)]
## 발밑 그림자 타원을 나누는 조각 수
const ELLIPSE_STEPS := 16

static var _style: Dictionary = {}
## 점검용 (앞뒤 비교 사진·테스트): -1 = 파일의 enabled 값, 0 = 끔, 1 = 켬
static var _forced := -1
static var _ring := PackedVector2Array()
static var _ring_idx := PackedInt32Array()
static var _ring_cols: Dictionary = {}
static var _fan_idx: Dictionary = {}


## 설정값 {이름: 값} (파일의 value만)
static func style() -> Dictionary:
	if _style.is_empty():
		var data: Variant = JsonData.load_file(PATH)
		if data is Dictionary:
			for key: String in data:
				if data[key] is Dictionary and (data[key] as Dictionary).has("value"):
					_style[key] = data[key]["value"]
	return _style


## 그림자를 그리는가
static func on() -> bool:
	if _forced >= 0:
		return _forced == 1
	return bool(style().get("enabled", true))


## 점검용: 그림자를 억지로 켜거나(1) 끄거나(0), 파일 값으로 되돌린다(-1)
static func force(state: int) -> void:
	_forced = clampi(state, -1, 1)


static func num(key: String, fallback := 0.0) -> float:
	return float(style().get(key, fallback))


## 그림자 색. alpha_key 의 진하기에 scale 을 곱한다
static func color(alpha_key: String, scale := 1.0) -> Color:
	return Color(Color(str(style().get("color", "#000000"))), clampf(num(alpha_key) * scale, 0.0, 1.0))


## 밤 정도(0 낮 … 1 밤)에 따라 해 그림자 진하기에 곱하는 값
static func sun_scale(night: float) -> float:
	return lerpf(1.0, num("night_scale", 1.0), clampf(night, 0.0, 1.0))


## 그림자가 뻗는 쪽 (칸 좌표, 길이 1): 화면에서 빛 반대쪽으로 가는 바닥 위 방향 — 호스 그림자와 같은 쪽
static func cast_dir(proj: ViewProjection) -> Vector2:
	var l: Variant = HoseDraw.style().get("light_dir", [-0.5, -0.85])
	var light := Vector2(float(l[0]), float(l[1]))
	var d := proj.to_cell(-light) - proj.to_cell(Vector2.ZERO)
	return d.normalized() if d.length_squared() > 0.000001 else Vector2(1, 0)


## 높이 height_m 인 물체의 그림자가 바닥에서 뻗는 거리 (칸 좌표 벡터). max_key 가 있으면 그 설정값(m)을 넘지 않는다
static func cast_offset(proj: ViewProjection, height_m: float, cell_m: float, max_key := "") -> Vector2:
	var len_m := maxf(0.0, height_m) * num("sun_length_ratio")
	if max_key != "":
		len_m = minf(len_m, num(max_key, len_m))
	return cast_dir(proj) * len_m / maxf(0.01, cell_m)


static func rect_points(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## 볼록한 바닥 다각형이 offset 만큼 드리우는 그림자에서 다각형 자리를 뺀 부분: 빛 반대쪽을 보는 변마다 사각형 하나
## [변 a, 변 b, b + offset, a + offset]. 사각형끼리 겹치지 않는다 (반투명으로 그려도 진하기가 고르다)
static func sweep_quads(base: PackedVector2Array, offset: Vector2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if base.size() < 3 or offset.length_squared() < 0.000001:
		return out
	var center := Vector2.ZERO
	for p in base:
		center += p
	center /= base.size()
	for k in base.size():
		var a := base[k]
		var b := base[(k + 1) % base.size()]
		var n := (b - a).orthogonal()
		if n.dot((a + b) * 0.5 - center) < 0.0:
			n = -n
		if n.dot(offset) > 0.000001:
			out.append(PackedVector2Array([a, b, b + offset, a + offset]))
	return out


## 볼록한 바닥 다각형과 그 그림자를 합친 윤곽 (볼록 껍질) — 차량처럼 그림이 바닥 자리를 다 덮지 않는 것에 쓴다
static func sweep_hull(base: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var all := base.duplicate()
	for p in base:
		all.append(p + offset)
	var hull := Geometry2D.convex_hull(all)
	# convex_hull 은 첫 점을 끝에 한 번 더 넣는다
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	return hull


## 상자(칸 좌표)의 옆면 아래에서 바닥으로 번지는 띠. sides = 띠를 낼 쪽 (WEST | NORTH | EAST | SOUTH), cast = cast_dir.
## 그늘지는 쪽(cast 쪽)은 넓고 진하게, 빛 받는 쪽은 좁고 옅게. width 는 칸 단위 [그늘 쪽, 빛 쪽].
## 결과: 띠 {side 0~3, at 면의 좌표, a·b 면을 따라가는 범위, w 폭, alpha 벽 쪽 진하기}
##       + 띠를 낸 두 면이 만나는 바깥 모서리마다 부채 {fan: [모서리, 한쪽 끝, 대각선 끝, 다른 쪽 끝], alpha 모서리 진하기}
static func box_bands(r: Rect2, sides: int, cast: Vector2, shadow_w: float, lit_w: float, alpha: float, lit_ratio: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var widths: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var alphas: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for k in 4:
		if sides & SIDES[k] == 0:
			continue
		var s := clampf(NORMALS[k].dot(cast), 0.0, 1.0)
		widths[k] = lerpf(lit_w, shadow_w, s)
		alphas[k] = alpha * lerpf(lit_ratio, 1.0, s)
		var along_y := k == 0 or k == 2
		out.append({
			"side": k,
			"at": (r.position.x if k == 0 else r.end.x) if along_y else (r.position.y if k == 1 else r.end.y),
			"a": r.position.y if along_y else r.position.x,
			"b": r.end.y if along_y else r.end.x,
			"w": widths[k], "alpha": alphas[k],
		})
	# 바깥 모서리: 북서·북동·남동·남서 (이웃한 두 면 모두 띠가 있을 때)
	var corners: Array = [
		[0, 1, r.position], [1, 2, Vector2(r.end.x, r.position.y)], [2, 3, r.end], [3, 0, Vector2(r.position.x, r.end.y)]]
	for c: Array in corners:
		var i: int = c[0]
		var j: int = c[1]
		if widths[i] <= 0.0 or widths[j] <= 0.0:
			continue
		var p: Vector2 = c[2]
		var da := NORMALS[i] * widths[i]
		var db := NORMALS[j] * widths[j]
		out.append({"fan": PackedVector2Array([p, p + da, p + da + db, p + db]), "alpha": (alphas[i] + alphas[j]) * 0.5})
	return out


## 같은 면 위에서 이어지는 띠를 하나로 합친다 (긴 벽 = 띠 하나 — 그리는 양을 줄인다). 부채는 그대로 둔다
static func merge_bands(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var groups := {}
	for d in list:
		if d.has("fan"):
			out.append(d)
			continue
		var key := "%d|%.3f|%.3f|%.3f" % [int(d.side), float(d.at), float(d.w), float(d.alpha)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(d)
	for key: String in groups:
		var g: Array = groups[key]
		g.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p.a) < float(q.a))
		var cur: Dictionary = (g[0] as Dictionary).duplicate()
		for k in range(1, g.size()):
			var nx: Dictionary = g[k]
			if float(nx.a) <= float(cur.b) + 0.001:
				cur.b = maxf(float(cur.b), float(nx.b))
			else:
				out.append(cur)
				cur = nx.duplicate()
		out.append(cur)
	return out


## 띠 하나의 사각형 (칸 좌표): [벽 쪽 a, 벽 쪽 b, 바깥 b, 바깥 a] — 앞의 두 점이 진하고 뒤의 두 점은 투명
static func band_quad(d: Dictionary) -> PackedVector2Array:
	var k := int(d.side)
	var at := float(d.at)
	var a := float(d.a)
	var b := float(d.b)
	var out_at := at + (NORMALS[k].x + NORMALS[k].y) * float(d.w)
	if k == 0 or k == 2:
		return PackedVector2Array([Vector2(at, a), Vector2(at, b), Vector2(out_at, b), Vector2(out_at, a)])
	return PackedVector2Array([Vector2(a, at), Vector2(b, at), Vector2(b, out_at), Vector2(a, out_at)])


## 볼록 다각형(화면 좌표)을 한 색으로 채운다 — 삼각형 나누기 없이 부채꼴로 바로 그린다
static func fill_convex(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var n := pts.size()
	if n < 3:
		return
	if not _fan_idx.has(n):
		var idx := PackedInt32Array()
		for k in range(1, n - 1):
			idx.append_array([0, k, k + 1])
		_fan_idx[n] = idx
	var cols := PackedColorArray()
	cols.resize(n)
	cols.fill(col)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _fan_idx[n], pts, cols)


## 발밑 그림자: 가운데(core 비율 안쪽)는 고르게 진하고 가장자리로 갈수록 투명해지는 납작한 타원 (화면 좌표, 반지름 rx·ry)
static func soft_ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float, col: Color) -> void:
	if _ring.is_empty():
		_build_ring()
	var key := col.to_rgba32()
	if not _ring_cols.has(key):
		var cols := PackedColorArray()
		cols.resize(_ring.size())
		cols.fill(col)
		var clear := Color(col, 0.0)
		for k in ELLIPSE_STEPS:
			cols[1 + ELLIPSE_STEPS + k] = clear
		_ring_cols[key] = cols
	var pts := Transform2D(Vector2(rx, 0), Vector2(0, ry), center) * _ring
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _ring_idx, pts, _ring_cols[key])


## 단위 타원: 가운데 점 1 + 안쪽 고리 + 바깥 고리
static func _build_ring() -> void:
	var core := clampf(num("contact_core", 0.45), 0.05, 0.95)
	_ring = PackedVector2Array([Vector2.ZERO])
	for scale: float in [core, 1.0]:
		for k in ELLIPSE_STEPS:
			var a := TAU * k / ELLIPSE_STEPS
			_ring.append(Vector2(cos(a), sin(a)) * scale)
	_ring_idx = PackedInt32Array()
	for k in ELLIPSE_STEPS:
		var n := (k + 1) % ELLIPSE_STEPS
		var i0 := 1 + k
		var i1 := 1 + n
		var o0 := 1 + ELLIPSE_STEPS + k
		var o1 := 1 + ELLIPSE_STEPS + n
		_ring_idx.append_array([0, i0, i1, i0, o0, o1, i0, o1, i1])
