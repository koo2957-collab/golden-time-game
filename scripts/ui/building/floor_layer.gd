class_name FloorLayer
extends Node2D
## 입체(아이소메트릭) 화면의 층 하나 (R17: IsoView가 층마다 하나씩 둔다). 시뮬레이션 상태를 읽어 매 프레임 그린다.
## 그리는 순서 (뒤 → 앞):
##   1) 바닥 타일, 방 이름, 선택한 조의 경로
##   2) 대각선(x + y) 순서로 벽·문·창·가구·화염·대원 (앞에 있는 것이 나중에 그려져 뒤를 가린다)
##   3) 연기층: 천장에서 계산된 깊이만큼 내려온 반투명 덩어리
## 뒤쪽 외벽(북·서)은 천장 높이로, 나머지 벽은 낮게 잘라 실내가 보이게 한다.

## 위층 노드의 depth 시작값 (IsoView.ABOVE_DEPTH와 같음)
const ABOVE_DEPTH := 100
const CEILING_M := 2.4
const WALL_CUT_M := 0.45
const WINDOW_SILL_M := 0.9
## 화면 연출: 이 세기(최대 열방출 대비) 넘게 타는 칸은 불꽃 뒤에 불덩이 그림을 깐다
const FIRE_MASS_FROM := 0.6
const WINDOW_TOP_M := 2.1
const DOOR_TOP_M := 2.0
## 사람 비율 (방화복·공기호흡기 착용): 어깨 높이, 머리 중심, 이름표 높이 (m)
const UNIT_BODY_M := 1.38
const UNIT_HIP_M := 0.85
const UNIT_HEAD_M := 1.6
const UNIT_LABEL_M := 2.35
## 장비 착용 대원 폭 약 0.5m
## 어깨 절반 폭(px, 약 0.45m), 발 절반 폭, 머리(안전모) 반지름
const UNIT_HALF_W := 17.0
const UNIT_FOOT_HALF_W := 11.0
const UNIT_HEAD_R := 9.0
const REFLECTIVE := Color(0.95, 0.95, 0.7)
## 바닥 위 타원(그림자·선택 고리 등)의 세로 비율 보정 (바닥 비율 / 2:1)
const GROUND_RATIO := IsoProjection.HALF_H / IsoProjection.HALF_W / 0.5
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
## 차량을 그리는 최대 높이. 약 50° 부감이라 실제 높이로 그려도 건물을 거의 가리지 않는다
const VEHICLE_CUT_M := 3.0
const VEHICLE_ALPHA := 0.9
const NOZZLE_M := 1.1
const IMPACT_M := 0.4
## 정보 안개: 모르는 곳 / 본 적 있지만 지금은 안 보이는 곳
const FOG_COLOR := Color(0.04, 0.05, 0.07)
const FOG_UNKNOWN_ALPHA := 0.82
const FOG_SEEN_ALPHA := 0.4
## 도면도 없고 본 적도 없는 실내: 구조가 거의 보이지 않게 (기획안 9-1 "구조는 직접 밝힌다", R8)
const FOG_NO_PLAN_ALPHA := 0.95
## 도면으로만 아는 벽·문·창 (흐린 선)
const PLAN_LINE := Color(0.55, 0.72, 0.95, 0.35)
const PLAN_DOOR := Color(0.95, 0.85, 0.45, 0.4)
const THERMAL_UNKNOWN := Color(0.03, 0.03, 0.05)
## 낮은 자세 대원의 키 비율
const CROUCH_SCALE := 0.62

## 외부 보기 (R16): 1층 바깥 + 건물 외관. 1층 외벽은 천장 높이까지 세우고, 위층은 층마다 쌓은 외관(창 상태)으로 그린다.
## 층이 많으면 위층 높이를 줄여(최소 SHELL_MIN_FLOOR_M) 전체가 SHELL_CAP_M 안에 들어오게 한다 — 교육용 표시.
const FLOOR_M := 2.8
const SHELL_CAP_M := 30.0
const SHELL_MIN_FLOOR_M := 1.0
const PARAPET_M := 0.4
const SHELL_WALL := Color(0.56, 0.59, 0.64)
const SHELL_ALPHA := 1.0
const SHELL_LINE := Color(0.2, 0.22, 0.26, 0.8)
const FIRE_GLASS := Color(1.0, 0.45, 0.12, 0.95)
const SMOKE_GLASS := Color(0.42, 0.42, 0.45, 0.95)
const DARK_GLASS := Color(0.16, 0.22, 0.3, 0.95)
## 외관 꾸밈 (R17): 창틀·층 띠·발코니 난간·옥상·창 상태 표시
const WINDOW_FRAME := Color(0.2, 0.22, 0.26, 0.9)
const FLOOR_BAND := Color(0.72, 0.74, 0.77)
const RAILING := Color(0.8, 0.82, 0.85, 0.9)
const ROOF_TOP := Color(0.5, 0.53, 0.57)
const PENTHOUSE := Color(0.64, 0.67, 0.71)
const BROKEN_LINE := Color(0.85, 0.9, 0.95, 0.85)
const PERSON_BODY := Color("fbbf24")
const PERSON_MARK := Color("4ade80")

var sim: SimWorld
var selection: SelectionController
var proj: IsoProjection
var level := 1
var thermal := false
var exterior := false
## R17 층 쌓기 (IsoView가 정한다): 지금 층에서 몇 층 아래인가(0 = 지금 층), 바로 위·아래에 함께 보이는 층(-1 = 없음)
var depth := 0
var upper_level := -1
var lower_level := -1
var stack: FloorStack
var skin: TileSkin
var _ramps: Dictionary = {}  # "아래:위" -> Array[Vector2i] (위층과 이어지는 계단 칸)
var _ramp_rects: Dictionary = {}  # "아래:위" -> Rect2i
var _slab_edges: Dictionary = {}  # level -> Array[Vector3i] (x, y, 방향 비트: 남 1, 동 2)
var _masks: Dictionary = {}  # 그릴 칸 표 (가려지는 칸 빼기, _draw_mask)
var _mask_now := PackedByteArray()  # 이번 그리기에 쓰는 표 (비어 있으면 모두 그린다)
var _drawn_tick := -1  # 아래층이 마지막으로 그린 틱
## 외관 묶어 그리기 (그리기 호출 수를 줄인다): 사각형은 삼각형 배열 하나, 선은 선 묶음 하나로
var _batching := false
var _bq_pts := PackedVector2Array()
var _bq_cols := PackedColorArray()
var _bq_idx := PackedInt32Array()
var _bl_pts := PackedVector2Array()
var _bl_cols := PackedColorArray()
## 다른 층 (F01, 2026-11-11 사용자 결정): 고른 층 외의 위·아래 층은 벽 선(외곽·방 벽)만 얇은 반투명으로,
## 불을 아는 방의 벽만 주황, 대원은 몸 테두리만 노랑, 발견한 요구조자는 빨강. 가구·바닥·불·연기는 그리지 않는다
var ghost := false:
	set(v):
		if v != ghost:
			ghost = v
			if _ghost_units:
				_ghost_units.visible = v
			queue_redraw()
## 다른 층 그리는 방식: 0 지금 층 / 1 바로 위·아래 / 2 먼 아래층(외관 덩어리) / 3 먼 위층(사람 테두리만). ghost는 0이 아닐 때 켜진다
var ghost_mode := 0:
	set(v):
		if v != ghost_mode:
			ghost_mode = v
			ghost = v != 0
			queue_redraw()
var _ghost_outdoor_idx: Dictionary = {}  # level -> 바깥 땅 칸 삼각형 index
var _ghost_floor_idx: Dictionary = {}  # level -> 실내 바닥 칸 삼각형 index
const GHOST_WALL := Color(1, 1, 1, 0.42)
const GHOST_INNER := Color(1, 1, 1, 0.34)
const GHOST_FIRE_WALL := Color(1.0, 0.55, 0.15, 0.8)
## 벽 면 채움 (바깥벽은 거의 투명, 확인된 내부 벽은 옅게)
const GHOST_FACE_ALPHA := 0.04
const GHOST_INNER_FACE_ALPHA := 0.1
const GHOST_CREW := Color(1.0, 0.85, 0.2, 0.9)
const GHOST_VICTIM := Color(1.0, 0.3, 0.3, 0.9)
var _ghost_units: Node2D
var _ghost_walls: Dictionary = {}  # level -> 벽 줄 목록 (_ghost_wall_runs)

## 층 고르기 (P4-5): 외부 보기에서 노랗게 테두리를 그릴 층 (-99 = 없음)
var hover_floor := -99:
	set(v):
		if v != hover_floor:
			hover_floor = v
			queue_redraw()
## 외관 층 [{kind: "floor"|"gap", level, h0, h1, text}] (아래 → 위)
var _shell: Array[Dictionary] = []
var _shell_top := CEILING_M
var _shell_fp := Rect2i()
## 층 -> 보는 쪽(남·동) 바깥 창 [{o: Opening, face: "S"|"E", a, b}]
var _ext_windows: Dictionary = {}
## 이번 프레임에 불이 보인(또는 마지막으로 본) 방 index
var _fire_rooms: Dictionary = {}

var _furniture_h: Dictionary = {}  # level -> PackedFloat32Array
var _opening_of: Dictionary = {}  # Vector3i -> Opening
var _footprint: Dictionary = {}  # level -> Rect2i
var _lit: Array[Opening] = []  # 불빛이 보이는 창 (그릴 때마다 갱신)
## 구운 그림(P15)의 마지막 방향 {대원 id: 0~7} — 멈춰 있으면 마지막으로 움직인 쪽을 본다
var _facing: Dictionary = {}
## 가구 그림 (P15): 층 -> {칸 index: 가구 번호} (그림으로 그리는 칸은 블록을 그리지 않는다), 층 -> {앞쪽 칸 index: 그릴 정보}
var _furn_cells: Dictionary = {}
var _furn_draw: Dictionary = {}
## 불빛 번짐 (P15-FX, 실시간 셰이더). 지금 층만
var _glow: FireGlowLayer
var _glow_spots: Array = []
var _first_level := 0  # 지상층 (levels()는 부를 때마다 배열을 복사하므로 한 번만 읽는다)

## 바닥 캐시. 칸 모양은 층별로 고정이고, 색(바닥·그을음·열화상·정보 안개)은 시뮬레이션 틱이 바뀔 때만 달라진다.
## 그래서 모양은 setup에서 한 번 만들고, 색은 틱·층·열화상·안개 켜짐이 바뀔 때만 다시 계산해 한 번에 그린다.
var _ground_cells: Dictionary = {}  # level -> PackedInt32Array (VOID가 아닌 칸의 y * width + x)
var _ground_types: Dictionary = {}  # level -> PackedByteArray (_ground_cells 순서의 칸 종류)
var _ground_points: Dictionary = {}  # level -> PackedVector2Array (칸마다 꼭짓점 4개)
var _ground_indices: Dictionary = {}  # level -> PackedInt32Array (칸마다 삼각형 2개)
var _stair_cells: Dictionary = {}  # level -> PackedInt32Array
var _stair_points: Dictionary = {}  # level -> PackedVector2Array (계단 칸마다 선 4개 = 점 8개)
var _ground_colors := PackedColorArray()
var _stair_colors := PackedColorArray()
var _ground_key: Array = []

## 대각선(x + y) 순서로 그릴 물체가 있는 칸. 그 밖의 칸은 그릴 것이 없으므로 건너뛴다.
## 고정 물체(벽·창·문·가구·소화전·송수구·방수구·가스 밸브)는 setup에서, 화염 칸은 틱마다 다시 모은다.
var _static_objects: Dictionary = {}  # level -> {d: PackedInt32Array (x 오름차순)}
var _objects: Dictionary = {}  # 지금 층의 {d: PackedInt32Array}: 고정 물체 + 화염 칸
var _objects_key: Array = []


func setup(p_sim: SimWorld, p_selection: SelectionController, p_proj: IsoProjection, p_stack: FloorStack = null) -> void:
	sim = p_sim
	selection = p_selection
	proj = p_proj
	var b := sim.building
	stack = p_stack if p_stack != null else FloorStack.new(b)
	skin = TileSkin.load_default()
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
		_build_furniture_sprites(lv)
	for o in sim.fire.openings:
		for c in o.cells:
			_opening_of[Vector3i(c.x, c.y, o.level)] = o
	_first_level = b.levels()[0]
	for lv in b.levels():
		_build_ground_geometry(lv)
		_build_static_objects(lv)
	_ground_key = []
	_objects_key = []
	_build_shell()
	# 다른 층 사람 테두리: 테두리 셰이더를 입힌 자식에 따로 그린다 (벽 선은 이 층에 그대로)
	_ghost_units = Node2D.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ghost_outline.gdshader")
	_ghost_units.material = mat
	_ghost_units.visible = ghost
	# 벽 너머 테두리처럼: 지금 층 그림 위에 그린다 (아래층 사람이 지금 층 바닥에 가려지지 않게)
	_ghost_units.z_as_relative = false
	_ghost_units.z_index = 100
	_ghost_units.draw.connect(_draw_ghost_units)
	add_child(_ghost_units)


# --- 외부 보기: 건물 외관 (R16) ---

func _build_shell() -> void:
	var b := sim.building
	# 외관 범위: 화재 건물 범위(한 칸 여유) 안에서 실제 벽·바닥이 있는 칸을 꼭 맞게 감싼다
	var rough: Rect2i = _footprint[_first_level].grow(1)
	var tight := Rect2i()
	var found := false
	for y in range(rough.position.y, rough.end.y):
		for x in range(rough.position.x, rough.end.x):
			if not b.cell(_first_level, x, y) in BuildingData.OUTDOOR:
				tight = Rect2i(x, y, 1, 1) if not found else tight.merge(Rect2i(x, y, 1, 1))
				found = true
	_shell_fp = tight if found else _footprint[_first_level]
	var above: Array[int] = []
	for lv in b.levels():
		if lv != _first_level and b.floor_number(lv) >= 1:
			above.append(lv)
	above.sort_custom(func(a: int, c: int) -> bool: return b.floor_number(a) < b.floor_number(c))
	var units := above.size()
	var prev: int = b.floor_number(_first_level)
	for lv in above:
		if b.floor_number(lv) - prev > 1:
			units += 2
		prev = b.floor_number(lv)
	var fh := clampf((SHELL_CAP_M - CEILING_M) / maxf(1.0, units), SHELL_MIN_FLOOR_M, FLOOR_M)
	var h := CEILING_M
	prev = b.floor_number(_first_level)
	_shell.clear()
	for lv in above:
		var n: int = b.floor_number(lv)
		if n - prev > 1:
			_shell.append({"kind": "gap", "level": -1, "h0": h, "h1": h + fh * 2.0, "text": "%d~%d층" % [prev + 1, n - 1]})
			h += fh * 2.0
		_shell.append({"kind": "floor", "level": lv, "h0": h, "h1": h + fh, "text": "%d층" % n})
		h += fh
		prev = n
	_shell_top = h + PARAPET_M
	# 보는 쪽(남·동)으로 난 바깥 창 (창 칸 옆 바깥 칸의 방향으로 판단 — 건물 범위 값이 벽과 한 칸 어긋나도 된다)
	for o in sim.fire.openings:
		if o.kind != Opening.Kind.WINDOW or o.room_b != Opening.OUTSIDE:
			continue
		var out := Vector2i.ZERO
		for c in o.cells:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if b.cell(o.level, c.x + d.x, c.y + d.y) in BuildingData.OUTDOOR:
					out += d
		var south := out.y > 0 and out.y >= absi(out.x)
		var east := not south and out.x > 0
		if not south and not east:
			continue
		var lo := 1 << 30
		var hi := -(1 << 30)
		for c in o.cells:
			var k := c.x if south else c.y
			lo = mini(lo, k)
			hi = maxi(hi, k + 1)
		if not _ext_windows.has(o.level):
			_ext_windows[o.level] = []
		_ext_windows[o.level].append({"o": o, "face": "S" if south else "E", "a": lo, "b": hi})


## 지금 외부 보기인가 (외관은 바깥이 있는 맨 아래 층에서만)
func _outside() -> bool:
	return exterior and level == _first_level


## 외부 보기에서 카메라가 올라가야 하는 높이 (m)
func shell_top_m() -> float:
	return _shell_top


## 외관 바닥 범위 (칸)
func shell_rect() -> Rect2i:
	return _shell_fp


## 외관 층의 그리기 높이 [h0, h1]. 외관에 없는 층(1층·지하)은 빈 배열
func shell_band(lv: int) -> Array:
	for it in _shell:
		if it.kind == "floor" and int(it.level) == lv:
			return [it.h0, it.h1]
	return []


func _update_fire_rooms() -> void:
	_fire_rooms.clear()
	var grid := sim.fire.grid
	var p := sim.perception
	for i in grid.burning:
		var c3 := grid.cell_of(i)
		if p.enabled and not p.is_visible(c3.z, c3.x, c3.y) and p.seen_burning[i] != 1:
			continue
		var comp := sim.fire.compartment_at(c3.z, c3.x, c3.y)
		if comp:
			_fire_rooms[comp.index] = true


## 밖에서 본 창 색: 확인한 불 > 확인한 짙은 연기 > 실내등 > 깨진 창 > 유리 (모르는 창은 어둡게)
func _facade_glass(o: Opening) -> Color:
	if thermal:
		return THERMAL_STRUCTURE
	var p := sim.perception
	var cell := o.cells[0]
	var now := not p.enabled or p.is_visible(o.level, cell.x, cell.y)
	var seen := now or p.is_seen(o.level, cell.x, cell.y)
	if _fire_rooms.has(o.room_a):
		var flick := 0.85 + 0.15 * sin(Time.get_ticks_msec() / 90.0 + o.index)
		return Color(FIRE_GLASS.r, FIRE_GLASS.g * flick, FIRE_GLASS.b, FIRE_GLASS.a)
	var comp := sim.fire.comps[o.room_a]
	if seen and comp.layer_depth > 0.6:
		return SMOKE_GLASS
	if o in _lit:
		return PlanStyle.LIT_WINDOW
	if o.broken:
		return Color(0.05, 0.05, 0.06, 0.95)
	return GLASS_COLOR if seen else DARK_GLASS


## 남쪽 면(y = fp.end.y)·동쪽 면(x = fp.end.x) 위의 사각형 (a~b는 그 면을 따라가는 칸 범위)
func _face_quad(face: String, a: float, b: float, h0: float, h1: float, color: Color) -> void:
	var fp := _shell_fp
	var p0: Vector2
	var p1: Vector2
	if face == "S":
		p0 = Vector2(a, fp.end.y)
		p1 = Vector2(b, fp.end.y)
	else:
		p0 = Vector2(fp.end.x, a)
		p1 = Vector2(fp.end.x, b)
	_quad(proj.to_screen(p0, h0), proj.to_screen(p1, h0), proj.to_screen(p1, h1), proj.to_screen(p0, h1), color)


func _draw_shell() -> void:
	var fp := _shell_fp
	var wall := THERMAL_STRUCTURE if thermal else SHELL_WALL
	var south := Color(wall.darkened(SOUTH_SHADE), SHELL_ALPHA)
	var east := Color(wall.darkened(EAST_SHADE), SHELL_ALPHA)
	var font := PlanStyle.font()
	# 이웃 건물(구조물 2번째부터): 1층 높이 지붕만 덮는다 (층수 정보가 없으므로)
	var structures := sim.building.structures
	for i in range(1, structures.size()):
		var nr := _tile_rect(structures[i].rect, CEILING_M)
		_quad(nr[0], nr[1], nr[2], nr[3], Color(wall.darkened(0.15), 1.0))
		draw_polyline(PackedVector2Array([nr[0], nr[1], nr[2], nr[3], nr[0]]), SHELL_LINE, 1.0)
	# 외벽 면·층 띠·창은 한 번에 묶어 그리고, 글자·창 상태 표시(불꽃·사람)는 그 위에 (R17 성능)
	_batching = true
	var texts: Array = []
	# 1층 위 바닥판 (1층 외벽 위로 위층이 없을 때는 지붕)
	if _shell.is_empty():
		_face_quad("S", fp.position.x, fp.end.x, CEILING_M, _shell_top, south)
		_face_quad("E", fp.position.y, fp.end.y, CEILING_M, _shell_top, east)
	for it in _shell:
		var h0: float = it.h0
		var h1: float = it.h1
		_face_quad("S", fp.position.x, fp.end.x, h0, h1, south)
		_face_quad("E", fp.position.y, fp.end.y, h0, h1, east)
		var fh := h1 - h0
		if it.kind == "gap":
			# 줄여 그린 층: 흐린 창 띠와 끊김 표시
			for k in 2:
				var wh0 := h0 + fh * (0.18 + k * 0.5)
				_face_quad("S", fp.position.x + 1, fp.end.x - 1, wh0, wh0 + fh * 0.18, Color(DARK_GLASS, 0.5))
				_face_quad("E", fp.position.y + 1, fp.end.y - 1, wh0, wh0 + fh * 0.18, Color(DARK_GLASS, 0.5))
			var mid := proj.to_screen(Vector2(fp.end.x, fp.end.y), (h0 + h1) * 0.5)
			texts.append([mid + Vector2(6, 5), it.text, 13, Color("cbd5e1")])
		else:
			var lv := int(it.level)
			# 층 띠 (바닥판 높이의 밝은 띠)
			_face_quad("S", fp.position.x, fp.end.x, h0, h0 + fh * 0.12, Color(FLOOR_BAND.darkened(SOUTH_SHADE), SHELL_ALPHA))
			_face_quad("E", fp.position.y, fp.end.y, h0, h0 + fh * 0.12, Color(FLOOR_BAND.darkened(EAST_SHADE), SHELL_ALPHA))
			for w: Dictionary in _ext_windows.get(lv, []):
				_draw_facade_window(w, h0, fh)
			if fh * IsoProjection.PX_PER_M >= 13.0:
				var corner := proj.to_screen(Vector2(fp.end.x, fp.end.y), (h0 + h1) * 0.5)
				texts.append([corner + Vector2(6, 5), it.text, 12, Color("e2e8f0")])
		# 층 경계선
		_line(proj.to_screen(Vector2(fp.position.x, fp.end.y), h0), proj.to_screen(Vector2(fp.end.x, fp.end.y), h0), SHELL_LINE)
		_line(proj.to_screen(Vector2(fp.end.x, fp.end.y), h0), proj.to_screen(Vector2(fp.end.x, fp.position.y), h0), SHELL_LINE)
	if not _shell.is_empty():
		var top0: float = _shell[-1].h1
		_face_quad("S", fp.position.x, fp.end.x, top0, _shell_top, south)
		_face_quad("E", fp.position.y, fp.end.y, top0, _shell_top, east)
	_flush_batch()
	for t: Array in texts:
		draw_string(font, t[0], t[1], HORIZONTAL_ALIGNMENT_LEFT, -1, t[2], t[3])
	# 창 상태 표시: 화염 분출·깨진 유리·창가의 사람 (위층 외벽 위로 불꽃이 올라가도록 외벽 다음에)
	for it in _shell:
		if it.kind == "floor":
			for w: Dictionary in _ext_windows.get(int(it.level), []):
				_draw_window_signs(w, it.h0, it.h1 - it.h0)
	# 1층 창: 창 자체는 바닥 층 그림이 그리고, 그 위에 상태 표시만
	for w: Dictionary in _ext_windows.get(_first_level, []):
		_draw_window_signs(w, 0.0, CEILING_M)
	_draw_roof(wall)
	_draw_shell_plumes()
	_draw_shell_markers()
	_draw_floor_hover()


## 층 고르기 (P4-5): 마우스를 올린 층의 외벽 테두리를 노랗게 (SelectionController가 hover_floor를 정한다)
func _draw_floor_hover() -> void:
	if hover_floor == -99:
		return
	for band in _floor_bands():
		if int(band[0]) != hover_floor:
			continue
		var t := Time.get_ticks_msec() / 1000.0
		var glow := 0.55 + 0.25 * sin(t * 5.0)
		for poly: PackedVector2Array in _band_polys(float(band[1]), float(band[2])):
			draw_colored_polygon(poly, Color(PlanStyle.ENTRY_POINT, 0.18 * glow))
			var loop := poly.duplicate()
			loop.append(poly[0])
			draw_polyline(loop, Color(PlanStyle.ENTRY_POINT, 0.95), 3.0)
		# 이름은 남쪽 면 가운데 (긴 건물에서도 마우스 가까이)
		var s: PackedVector2Array = _band_polys(float(band[1]), float(band[2]))[0]
		var at := (s[0] + s[1] + s[2] + s[3]) * 0.25
		draw_string(PlanStyle.font(), at + Vector2(-90, 6), "%s — 클릭하면 이 층으로" % sim.building.floor_name(hover_floor), HORIZONTAL_ALIGNMENT_CENTER, 180, 16, Color.WHITE)


## 외부 보기의 층 띠 [층, 아래 높이, 위 높이] (1층 포함, 줄여 그린 층 제외)
func _floor_bands() -> Array:
	var out: Array = [[_first_level, 0.0, CEILING_M]]
	for it in _shell:
		if it.kind == "floor":
			out.append([int(it.level), float(it.h0), float(it.h1)])
	return out


## 층 띠의 남쪽·동쪽 외벽 면 (화면 다각형 2개)
func _band_polys(h0: float, h1: float) -> Array[PackedVector2Array]:
	var fp := _shell_fp
	var s := PackedVector2Array([proj.to_screen(Vector2(fp.position.x, fp.end.y), h0), proj.to_screen(Vector2(fp.end.x, fp.end.y), h0),
		proj.to_screen(Vector2(fp.end.x, fp.end.y), h1), proj.to_screen(Vector2(fp.position.x, fp.end.y), h1)])
	var e := PackedVector2Array([proj.to_screen(Vector2(fp.end.x, fp.end.y), h0), proj.to_screen(Vector2(fp.end.x, fp.position.y), h0),
		proj.to_screen(Vector2(fp.end.x, fp.position.y), h1), proj.to_screen(Vector2(fp.end.x, fp.end.y), h1)])
	return [s, e]


## 외부 보기에서 화면 점(이 층 그림 좌표) 아래의 층. 없으면 -99
func shell_level_at(p: Vector2) -> int:
	if not _outside():
		return -99
	for band in _floor_bands():
		for poly in _band_polys(float(band[1]), float(band[2])):
			if Geometry2D.is_point_in_polygon(p, poly):
				return int(band[0])
	return -99


## 옥상: 바닥판 + 난간(파라펫) 안쪽 면 + 계단실 옥탑 (R17)
func _draw_roof(wall: Color) -> void:
	var fp := _shell_fp
	var top0 := _shell_top - PARAPET_M
	var roof := _tile_rect(fp, top0)
	_quad(roof[0], roof[1], roof[2], roof[3], Color(ROOF_TOP if not thermal else wall, 1.0))
	# 뒤쪽(북·서) 난간의 안쪽 면이 보인다
	var nw := proj.to_screen(Vector2(fp.position.x, fp.position.y), top0)
	var ne := proj.to_screen(Vector2(fp.end.x, fp.position.y), top0)
	var sw := proj.to_screen(Vector2(fp.position.x, fp.end.y), top0)
	var up := Vector2(0, -PARAPET_M * IsoProjection.PX_PER_M)
	_quad(nw, ne, ne + up, nw + up, Color(wall.darkened(SOUTH_SHADE), 1.0))
	_quad(nw, sw, sw + up, nw + up, Color(wall.darkened(EAST_SHADE), 1.0))
	# 계단실 옥탑: 맨 위층 계단 칸 위
	if not _shell.is_empty():
		var cells := _stair_cells_in_shell(int(_shell[-1].level))
		if not cells.is_empty():
			var r := Rect2i(cells[0], Vector2i.ONE)
			for c in cells:
				r = r.merge(Rect2i(c, Vector2i.ONE))
			var pc := PENTHOUSE if not thermal else wall
			_box(Vector2(r.position), Vector2(r.end), top0, top0 + CEILING_M * 0.8, pc, pc, pc.lightened(0.1))
	# 앞쪽(남·동) 난간 바깥 면은 옥상 바닥판 뒤에 다시 그린다
	_face_quad("S", fp.position.x, fp.end.x, top0, _shell_top, Color(wall.darkened(SOUTH_SHADE), 1.0))
	_face_quad("E", fp.position.y, fp.end.y, top0, _shell_top, Color(wall.darkened(EAST_SHADE), 1.0))
	var rim := _tile_rect(fp, _shell_top)
	draw_polyline(PackedVector2Array([rim[0], rim[1], rim[2], rim[3], rim[0]]), SHELL_LINE, 1.0)


func _stair_cells_in_shell(lv: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var b := sim.building
	for y in range(_shell_fp.position.y, _shell_fp.end.y):
		for x in range(_shell_fp.position.x, _shell_fp.end.x):
			if b.cell(lv, x, y) == BuildingData.Cell.STAIRS:
				out.append(Vector2i(x, y))
	return out


## 외관의 창 하나: 유리(상태 색) + 창틀 + (아파트) 발코니 난간 (상태 표시는 _draw_window_signs가 외벽 다음에)
func _draw_facade_window(w: Dictionary, h0: float, fh: float) -> void:
	var a := float(w.a) + 0.1
	var b := float(w.b) - 0.1
	var g0 := h0 + fh * 0.3
	var g1 := h0 + fh * 0.8
	_face_quad(w.face, a, b, g0, g1, _facade_glass(w.o))
	if not thermal:
		var p0 := _face_point(w.face, a, g0)
		var p1 := _face_point(w.face, b, g0)
		var p2 := _face_point(w.face, b, g1)
		var p3 := _face_point(w.face, a, g1)
		_line(p0, p1, WINDOW_FRAME)
		_line(p1, p2, WINDOW_FRAME)
		_line(p2, p3, WINDOW_FRAME)
		_line(p3, p0, WINDOW_FRAME)
		# 창 가운데 문살
		_line(_face_point(w.face, (a + b) * 0.5, g0), _face_point(w.face, (a + b) * 0.5, g1), WINDOW_FRAME)
	if sim.building.facade_style.get("balcony", false) and not thermal:
		# 발코니 난간: 창 아래 허리 높이 띠
		var r0 := h0 + fh * 0.12
		var r1 := h0 + fh * 0.36
		var shade := SOUTH_SHADE if w.face == "S" else EAST_SHADE
		_face_quad(w.face, a - 0.3, b + 0.3, r0, r1, Color(RAILING.darkened(shade), RAILING.a))
		_line(_face_point(w.face, a - 0.3, r1), _face_point(w.face, b + 0.3, r1), Color.WHITE)


## 창 상태 표시 (R17): 화염 분출 · 깨진 유리 · 창가·발코니의 사람.
## 실내 불빛·짙은 연기는 유리 색(_facade_glass)이, 연기 분출은 연기 기둥(_draw_shell_plumes)이 보여 준다.
## 모두 바깥 시야(대원·차량·지휘관)에 들어왔거나 본 적 있는 것만 (기획안 9-1)
func _draw_window_signs(w: Dictionary, h0: float, fh: float) -> void:
	if thermal:
		return
	var o: Opening = w.o
	var p := sim.perception
	var cell := o.cells[0]
	var seen := not p.enabled or p.is_visible(o.level, cell.x, cell.y) or p.is_seen(o.level, cell.x, cell.y)
	var a := float(w.a) + 0.1
	var b := float(w.b) - 0.1
	var g0 := h0 + fh * 0.3
	var g1 := h0 + fh * 0.8
	var mid := (a + b) * 0.5
	var t := Time.get_ticks_msec() / 1000.0
	# 깨진 유리: 금 간 선
	if o.broken and seen:
		var c0 := _face_point(w.face, lerpf(a, b, 0.2), g1)
		var c1 := _face_point(w.face, lerpf(a, b, 0.55), lerpf(g0, g1, 0.55))
		var c2 := _face_point(w.face, lerpf(a, b, 0.35), g0)
		var c3 := _face_point(w.face, lerpf(a, b, 0.85), lerpf(g0, g1, 0.7))
		draw_polyline(PackedVector2Array([c0, c1, c2]), BROKEN_LINE, 1.2)
		draw_line(c1, c3, BROKEN_LINE, 1.2)
	# 화염 분출: 불난 방(확인한 불)의 열린·깨진 창 위로 불꽃이 넘실댄다
	if _fire_rooms.has(o.room_a) and (o.broken or o.is_open):
		var base := _face_point(w.face, mid, g1)
		var half := (_face_point(w.face, b, g1) - _face_point(w.face, a, g1)).length() * 0.5
		var flick := 0.8 + 0.25 * sin(t * 9.0 + o.index * 1.7)
		var tip := _face_point(w.face, mid, g1 + fh * 0.9 * flick) + Vector2(sin(t * 5.0 + o.index) * 4.0, 0)
		if not _draw_window_fire(o.index, base, half, (base - tip).length(), t):
			draw_colored_polygon(_flame_shape(base, half, tip), Color(1.0, 0.45, 0.1, 0.9))
			draw_colored_polygon(_flame_shape(base, half * 0.5, base.lerp(tip, 0.6)), Color(1.0, 0.85, 0.3, 0.95))
	# 창가·발코니의 사람 (구조대상자)
	var v := _victim_at_window(o)
	if v != null:
		var along := clampf(v.pos.x if w.face == "S" else v.pos.y, a + 0.3, b - 0.3)
		var foot := _face_point(w.face, along, g0)
		var body_h := (g1 - g0) * IsoProjection.PX_PER_M * 0.75
		var head := foot + Vector2(0, -body_h)
		draw_line(foot, head + Vector2(0, 6), PERSON_BODY, 6.0)
		draw_circle(head, 4.5, Color("f5d0a9"))
		# 손을 흔든다
		var wave := sin(t * 6.0 + v.id) * 5.0
		draw_line(head + Vector2(0, 8), head + Vector2(9 + wave * 0.3, -6 + wave), PERSON_BODY, 2.5)
		draw_arc(head + Vector2(0, body_h * 0.4), body_h * 0.75, 0.0, TAU, 20, PERSON_MARK, 1.5)


## 창 가까이(2칸 안)에 있는, 밖에서 보이는(발견했거나 지금 보이는) 구조대상자
func _victim_at_window(o: Opening) -> Victim:
	var p := sim.perception
	for v in sim.rescue.victims:
		if v.level != o.level or not v.alive() or v.carried_by >= 0:
			continue
		var near := false
		for c in o.cells:
			if v.pos.distance_to(Vector2(c) + Vector2(0.5, 0.5)) <= 2.0:
				near = true
				break
		if not near:
			continue
		if not p.enabled or v.discovered or p.is_visible(v.level, floori(v.pos.x), floori(v.pos.y)):
			return v
	return null


## 남쪽 면(y = fp.end.y)·동쪽 면(x = fp.end.x) 위의 한 점 (along은 그 면을 따라가는 칸 좌표)
func _face_point(face: String, along: float, h: float) -> Vector2:
	var fp := _shell_fp
	return proj.to_screen(Vector2(along, fp.end.y) if face == "S" else Vector2(fp.end.x, along), h)

func _tile_rect(r: Rect2i, h: float) -> PackedVector2Array:
	return PackedVector2Array([
		proj.to_screen(Vector2(r.position.x, r.position.y), h), proj.to_screen(Vector2(r.end.x, r.position.y), h),
		proj.to_screen(Vector2(r.end.x, r.end.y), h), proj.to_screen(Vector2(r.position.x, r.end.y), h),
	])


## 창 밖으로 분출하는 화염 (구운 그림): 창 윗부분에서 불덩이(Kenney Explosion)가 벽을 타고 오르며 사그라들고,
## 그 위로 셰이더 불꽃이 넘실댄다. 그림이 없으면 false → 도형으로
func _draw_window_fire(key: int, base: Vector2, half: float, rise: float, t: float) -> bool:
	if not FxArt.load_all():
		return false
	for k in 3:
		var f := fmod(k / 3.0 + t * 0.6 + key * 0.13, 1.0)
		var pos := base + Vector2(sin(t * 2.0 + k + key) * half * 0.2, -rise * (0.15 + f * 0.9))
		var size := half * (1.6 + f * 1.2)
		if not FxArt.draw_puff(self, pos, size, FxArt.PUFF_FIRE, key + k, Color(1, 1, 1, 0.85 * (1.0 - f * f))):
			return false
	FxArt.draw_flame(self, base, half * 2.2, rise * 1.1, key * 5 + 1)
	return true


## 창·열린 문에서 나오는 연기 (모든 층, 외관 높이에 맞춰)
func _draw_shell_plumes() -> void:
	if thermal:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var levels: Array = [[_first_level, 0.0, CEILING_M]]
	for it in _shell:
		if it.kind == "floor":
			levels.append([it.level, it.h0, it.h1 - it.h0])
	for row: Array in levels:
		var base: float = row[1] + row[2] * 0.7
		for line in smoke_outlets(sim, int(row[0])):
			var at: Vector2 = line[0]
			var strength: float = line[1]
			for k in 5:
				var f := fmod(k / 5.0 + t * 0.35, 1.0)
				var pos := proj.to_screen(at, base + f * 2.5) + Vector2(sin(t + k) * 6.0, 0)
				var r := (8.0 + f * 18.0) * (0.6 + 0.4 * strength)
				var a := PlanStyle.SMOKE_PLUME.a * (1.0 - f) * strength
				if not FxArt.draw_puff(self, pos, r * 3.2, FxArt.PUFF_BLACK, k + int(t), Color(0.55, 0.55, 0.58, a * 1.6)):
					draw_circle(pos, r, Color(PlanStyle.SMOKE_PLUME, a))


## 건물 안 조·발견한 구조대상자를 그 층 높이에 표식으로 (벽 너머 위치를 알려 준다)
func _draw_shell_markers() -> void:
	var font := PlanStyle.font()
	for crew in sim.units.crews:
		var ff := crew.leader
		if ff.aboard or sim.building.cell(ff.level, floori(ff.pos.x), floori(ff.pos.y)) in BuildingData.OUTDOOR:
			continue
		var h := _marker_height(ff.level)
		if h < 0.0:
			continue
		var at := proj.to_screen(ff.pos, h)
		var squad := sim.units.squads[ff.squad_id]
		if crew.id in selection.selected:
			draw_arc(at, 13.0, 0.0, TAU, 24, PlanStyle.SELECTION, 2.5)
		draw_circle(at, 10.0, Color(squad.color, 0.95))
		draw_arc(at, 10.0, 0.0, TAU, 24, Color.WHITE, 1.5)
		draw_string(font, at + Vector2(-10, 5), str(crew.number), HORIZONTAL_ALIGNMENT_CENTER, 20, 13, Color.WHITE)
		draw_string(font, at + Vector2(-50, -14), squad.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color("e2e8f0"))
	for v in sim.rescue.victims:
		if not v.discovered or not v.alive() or v.level == _first_level and sim.building.cell(v.level, floori(v.pos.x), floori(v.pos.y)) in BuildingData.OUTDOOR:
			continue
		var h := _marker_height(v.level)
		if h < 0.0:
			continue
		var at := proj.to_screen(v.pos, h)
		draw_circle(at, 7.0, Color("4ade80"))
		draw_arc(at, 7.0, 0.0, TAU, 16, Color.WHITE, 1.2)


func _marker_height(lv: int) -> float:
	if lv == _first_level:
		return CEILING_M * 0.5
	var band := shell_band(lv)
	return -1.0 if band.is_empty() else (float(band[0]) + float(band[1])) * 0.5


func _build_ground_geometry(lv: int) -> void:
	var b := sim.building
	var cells := PackedInt32Array()
	var types := PackedByteArray()
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var stairs := PackedInt32Array()
	var stair_points := PackedVector2Array()
	for y in b.height:
		for x in b.width:
			var t := b.cell(lv, x, y)
			if t == BuildingData.Cell.VOID:
				continue
			var base := points.size()
			cells.append(y * b.width + x)
			types.append(t)
			points.append_array(_tile(x, y, 0.0))
			indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
			if t == BuildingData.Cell.STAIRS:
				stairs.append(y * b.width + x)
				for k in 4:
					var f := (k + 0.5) / 4.0
					stair_points.append(proj.to_screen(Vector2(x, y + f)))
					stair_points.append(proj.to_screen(Vector2(x + 1, y + f)))
	_ground_cells[lv] = cells
	_ground_types[lv] = types
	_ground_points[lv] = points
	_ground_indices[lv] = indices
	_stair_cells[lv] = stairs
	_stair_points[lv] = stair_points


func _build_static_objects(lv: int) -> void:
	var b := sim.building
	var heights: PackedFloat32Array = _furniture_h[lv]
	var by_diag := {}
	for y in b.height:
		for x in b.width:
			var t := b.cell(lv, x, y)
			var has := t in [BuildingData.Cell.WALL, BuildingData.Cell.WINDOW, BuildingData.Cell.DOOR] \
				or heights[y * b.width + x] > 0.0 \
				or Vector3i(x, y, lv) in b.outlets \
				or sim.plan.plan_cell(lv, x, y) != t
			if lv == _first_level:
				var c := Vector2i(x, y)
				has = has or c in b.hydrants or c == b.fdc or c == sim.gas.valve
				has = has or (not sim.plan.office.is_empty() and c == sim.plan.office.cell)
			if has:
				_add_object(by_diag, x, y)
	_static_objects[lv] = by_diag


## 대각선 d = x + y 목록에 x를 오름차순으로 넣는다 (같은 칸은 한 번만)
static func _add_object(by_diag: Dictionary, x: int, y: int) -> void:
	var d := x + y
	if not by_diag.has(d):
		by_diag[d] = PackedInt32Array([x])
		return
	var xs: PackedInt32Array = by_diag[d]
	var at := xs.bsearch(x)
	if at < xs.size() and xs[at] == x:
		return
	xs.insert(at, x)
	by_diag[d] = xs


## 지금 층에서 그릴 물체가 있는 칸: 고정 물체 + 타고 있는(또는 마지막으로 봤을 때 타던) 칸.
## 틱·층이 바뀔 때만 다시 모은다.
@warning_ignore("integer_division")
func _object_cells() -> Dictionary:
	var key := [sim.clock.tick, level, sim.perception.enabled]
	if key == _objects_key:
		return _objects
	_objects_key = key
	var by_diag := {}
	var fixed: Dictionary = _static_objects[level]
	for d in fixed:
		by_diag[d] = (fixed[d] as PackedInt32Array).duplicate()
	var b := sim.building
	var grid := sim.fire.grid
	var seen_burning := sim.perception.seen_burning
	var start := grid.index(level, 0, 0)
	for k in b.width * b.height:
		var i := start + k
		if grid.state[i] == FuelGrid.State.BURNING or seen_burning[i] == 1:
			_add_object(by_diag, k % b.width, k / b.width)
	_objects = by_diag
	return _objects


## 매 프레임 바뀔 수 있는 물체 칸: 공기안전매트·낙하물 위험구역 (몇 개뿐이라 매번 모은다)
func _dynamic_object_cells() -> Dictionary:
	var out := {}
	var b := sim.building
	for c in _ramp_cells():
		_add_dynamic(out, c, b)
	if level != _first_level:
		return out
	for m in sim.falls.mats:
		_add_dynamic(out, Vector2i(m.floor()), b)
	for z in sim.falls.zones:
		_add_dynamic(out, Vector2i(z.center.floor()), b)
	return out


static func _add_dynamic(out: Dictionary, c: Vector2i, b: BuildingData) -> void:
	if not b.in_bounds(c.x, c.y):
		return
	var d := c.x + c.y
	if not out.has(d):
		out[d] = []
	out[d].append(c.x)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _glow == null and depth == 0:
		_glow = FireGlowLayer.new()
		add_child(_glow)
		# 연기층 질감을 반복해 입힌다 (P15-FX)
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# 아래층(보이기만 하는 층)은 시뮬레이션 틱이 바뀔 때만, 두 아래층이 틱을 번갈아 다시 그린다 (R17 성능).
	# 지금 층은 대원 움직임·불꽃이 부드럽게 보이도록 매 프레임
	if depth > 0 and sim != null:
		var tick := sim.clock.tick
		if tick == _drawn_tick or (tick % 2 != depth % 2 and _drawn_tick >= 0 and tick - _drawn_tick < 2):
			return
		_drawn_tick = tick
	queue_redraw()


## 층 배치가 바뀌었다 — 아래층도 바로 다시 그린다
func refresh() -> void:
	_drawn_tick = -1
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	if ghost:
		_draw_ghost()
		return
	var b := sim.building
	var alpha := sim.clock.alpha()
	_lit = sim.command.survey.lit_windows()
	if _outside():
		_update_fire_rooms()
	_mask_now = _draw_mask()
	_draw_ground()
	_draw_slab_edges()
	if not _outside() and depth == 0:
		_draw_room_labels()
	if level == _first_level:
		if depth == 0:
			_draw_face_labels()
		_draw_staging()
		if depth == 0:
			ZoneDraw.draw_ground(self, sim.zones, func(p: Vector2) -> Vector2: return proj.to_screen(p, 0.03), 14)
	if depth == 0:
		for crew_id in selection.selected:
			_draw_path(sim.units.get_crew(crew_id).leader, alpha)
		if selection.commander_selected:
			_draw_path(sim.command.commander, alpha)
	_draw_hoses()
	if level == _first_level:
		for line in UnitsView.supply_lines(sim):
			draw_line(proj.to_screen(line[0], 0.05), proj.to_screen(line[1], 0.05), PlanStyle.SUPPLY_LINE, 4.0)
	# 대원·차량을 대각선(x + y) 깊이별로 모아 벽·가구와 함께 뒤에서 앞으로 그린다
	var buckets := {}
	for ff in sim.units.firefighters:
		if ff.level == level and not ff.aboard:
			_bucket(buckets, UnitsView.display_pos(ff, alpha), ff)
	if level == _first_level:
		for v in sim.units.vehicles:
			if not v.away:
				_bucket(buckets, v.prev_pos.lerp(v.pos, alpha), v)
	for victim in sim.rescue.victims:
		if victim.discovered and victim.level == level:
			_bucket(buckets, victim.pos, victim)
	var commander := sim.command.commander
	if commander.level == level:
		_bucket(buckets, UnitsView.display_pos(commander, alpha), commander)
	if level == _first_level:
		for w in sim.command.survey.witnesses:
			if w.present(sim.clock.tick):
				_bucket(buckets, w.pos, w)
	# 그릴 물체가 있는 칸만 대각선마다 x 오름차순으로 (빈 바닥 칸은 그릴 것이 없다)
	var objects := _object_cells()
	var extra := _dynamic_object_cells()
	for d in range(0, b.width + b.height - 1):
		var xs: PackedInt32Array = objects.get(d, PackedInt32Array())
		if extra.has(d):
			var merged := {d: xs.duplicate()}
			for x: int in extra[d]:
				_add_object(merged, x, d - x)
			xs = merged[d]
		for x in xs:
			if not _mask_now.is_empty() and _mask_now[(d - x) * b.width + x] == 0:
				continue
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
	if _outside():
		# 외관이 실내(연기층 포함)를 가린다. 연기는 창·문으로 나오는 것만
		_draw_shell()
	elif not thermal:
		_draw_smoke()
	_draw_blasts()
	if _glow:
		_glow.spots = _glow_spots if not thermal and not _outside() else []
		_glow.queue_redraw()
		_glow_spots = []
	_draw_sprays(alpha)
	_draw_monitors_and_fans()
	for e in sim.rekindle.spotted_cells():
		if e.z == level and not _outside():
			var ep := proj.to_screen(Vector2(e.x, e.y) + Vector2(0.5, 0.5), 0.05)
			draw_circle(ep, 4.0, PlanStyle.EMBER)
			draw_arc(ep, 7.0, 0.0, TAU, 16, PlanStyle.EMBER, 1.5)
	if level == _first_level and depth == 0:
		_draw_staging_label()
		ZoneDraw.draw_marks(self, sim.zones, func(p: Vector2) -> Vector2: return proj.to_screen(p, 0.03), 14, sim.clock.tick)


## 그릴 칸 표 (R17 성능): 가려져 화면에 나오지 않는 칸은 0. 빈 배열이면 모두 그린다.
##   외부 보기: 1층 실내는 외관(남·동 외벽과 위층·지붕)에 가려진다 → 바깥 칸과 바깥에 닿은 외벽 칸만
##   단면의 아래층: 바로 위층 바닥판에 가려진다 → 위층 바닥 밖으로 보이는 앞쪽 띠와 계단 구멍 아래만.
##     아래층 칸은 화면에서 위층 칸 (x+s, y+s)에 겹친다 (s = 0 ~ 층 높이/칸 세로 — 물체가 높을수록 s가 작다).
##     그 범위의 위층 칸이 하나라도 바닥이 아니면(밖·계단 구멍) 보인다고 본다 (넉넉하게)
func _draw_mask() -> PackedByteArray:
	var key := ""
	if _outside():
		key = "ext:%d" % level
	elif upper_level >= 0 and depth < ABOVE_DEPTH:
		# 아래층만: 위층 바닥에 가려지는 칸을 뺀다 (위층 노드는 반투명이라 다 그린다)
		key = "%d:%d" % [level, upper_level]
	else:
		return PackedByteArray()
	if _masks.has(key):
		return _masks[key]
	var b := sim.building
	var w := b.width
	var mask := PackedByteArray()
	mask.resize(w * b.height)
	if _outside():
		for y in b.height:
			for x in w:
				var t := b.cell(level, x, y)
				var keep := t in BuildingData.OUTDOOR
				if not keep and t in FloorStack.WALL_CELLS:
					# 보는 쪽(남·동)으로 바깥에 닿은 외벽만 — 북·서 외벽은 건물 뒤에 가려진다
					keep = b.cell(level, x, y + 1) in BuildingData.OUTDOOR or b.cell(level, x + 1, y) in BuildingData.OUTDOOR
				mask[y * w + x] = 1 if keep else 0
	else:
		var holes := {}
		for c: Vector2i in stack.stair_links_between(level, upper_level):
			holes[c] = true
		var reach := ceili(stack.params.floor_height_px / (2.0 * IsoProjection.HALF_H))
		for y in b.height:
			for x in w:
				var vis := false
				for k in reach + 1:
					for o: Vector2i in [Vector2i(k, k), Vector2i(k + 1, k), Vector2i(k, k + 1)]:
						var u := Vector2i(x + o.x, y + o.y)
						if not b.cell(upper_level, u.x, u.y) in BuildingData.STRUCTURE or holes.has(u):
							vis = true
							break
					if vis:
						break
				mask[y * w + x] = 1 if vis else 0
	_masks[key] = mask
	return mask


func _bucket(buckets: Dictionary, p: Vector2, obj: Object) -> void:
	if not _mask_now.is_empty() and sim.building.in_bounds(floori(p.x), floori(p.y)) \
			and _mask_now[floori(p.y) * sim.building.width + floori(p.x)] == 0:
		return
	var d := floori(p.x) + floori(p.y)
	if not buckets.has(d):
		buckets[d] = []
	buckets[d].append([p.x + p.y, obj])


# --- 바닥 ---

func _draw_ground() -> void:
	_update_ground_colors()
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _ground_indices[level], _ground_points[level], _ground_colors)
	if not thermal and not _stair_colors.is_empty():
		draw_multiline_colors(_stair_points[level], _stair_colors, 1.0)
	if not thermal:
		_draw_grid_lines()
		_draw_lane_line()


## 바닥 색을 다시 계산한다 (틱·층·열화상·정보 안개 켜짐이 바뀌었을 때만).
## 정보 안개는 원래 바닥 위에 반투명 마름모를 한 번 더 그리던 것을, 불투명한 바닥 색에 미리 섞어 같은 색을 낸다.
## 계단선도 안개에 덮이던 색이 그대로 나오도록 같은 비율로 섞는다.
func _update_ground_colors() -> void:
	var key := [sim.clock.tick, level, thermal, sim.perception.enabled, sim.plan.known, lower_level]
	if key == _ground_key:
		return
	_ground_key = key
	var b := sim.building
	var cells: PackedInt32Array = _ground_cells[level]
	var types: PackedByteArray = _ground_types[level]
	_ground_colors.resize(cells.size() * 4)
	var fog_of := {}
	# 칸마다 함수를 여러 번 부르면 느리므로 시야·그을음 배열을 직접 읽는다 (_fog_alpha·_cell_burnt와 같은 판정)
	var p := sim.perception
	var grid := sim.fire.grid
	var start := grid.index(level, 0, 0)
	var floor_dark: Color = skin.color("floor").darkened(0.3)
	# 아래층 계단이 이 층 바닥까지 올라오는 곳은 바닥을 뚫는다 (계단실)
	var holes := {}
	if lower_level >= 0:
		for c: Vector2i in stack.stair_links_between(lower_level, level):
			holes[c.y * b.width + c.x] = true
	for n in cells.size():
		var k := cells[n]
		var t := types[n]
		var structure := t == BuildingData.Cell.WALL or t == BuildingData.Cell.WINDOW
		var color: Color
		if thermal:
			@warning_ignore("integer_division")
			color = _thermal_ground_color(k % b.width, k / b.width)
		else:
			var i := start + k
			var outdoor := t in BuildingData.OUTDOOR
			var vis := not p.enabled or outdoor or p.visible_now[i] == 1
			var seen := vis or p.seen_tick[i] >= 0
			color = floor_dark if structure else _ground_base(t)
			var burnt := grid.state[i] == FuelGrid.State.BURNT if vis else (seen and p.seen_burnt[i] == 1)
			# 그을린 칸 (탄 칸은 가구 높이가 0이 되므로 _furniture_height 조건은 늘 참)
			if burnt:
				color = color.lerp(FireView.CHAR_COLOR, 0.8)
			# 벽 바닥도 모르는 곳이면 덮는다 (외벽은 밖에서 보이므로 그대로)
			@warning_ignore("integer_division")
			var hidden_wall := structure and p.enabled and not sim.plan.structure_seen(level, k % b.width, k / b.width)
			if (not structure and not vis) or hidden_wall:
				var fog := FOG_SEEN_ALPHA if seen else (FOG_UNKNOWN_ALPHA if sim.plan.known else FOG_NO_PLAN_ALPHA)
				color = color.lerp(FOG_COLOR, fog)
				fog_of[k] = fog
		if holes.has(k):
			color = Color(0, 0, 0, 0)
		for j in 4:
			_ground_colors[n * 4 + j] = color
	var stairs: PackedInt32Array = _stair_cells[level]
	_stair_colors.resize(stairs.size() * 4)
	for n in stairs.size():
		var fog: float = fog_of.get(stairs[n], 0.0)
		var line := PlanStyle.STAIR_LINE.lerp(FOG_COLOR, fog)
		line.a = 0.0 if holes.has(stairs[n]) else PlanStyle.STAIR_LINE.a
		for k in 4:
			_stair_colors[n * 4 + k] = line


## 열화상 화면의 바닥 색 (열화상 모드에서만 쓰므로 느린 판정 함수를 그대로 쓴다)
func _thermal_ground_color(x: int, y: int) -> Color:
	var t := sim.building.cell(level, x, y)
	var t_amb := sim.fire.config.value("ambient_temp_c")
	if t == BuildingData.Cell.WALL or t == BuildingData.Cell.WINDOW:
		return THERMAL_STRUCTURE
	if t in BuildingData.OUTDOOR:
		return FireView.thermal_color(t_amb, t_amb)
	if sim.perception.is_thermal_visible(level, x, y):
		return FireView.thermal_color(_cell_temperature(x, y), t_amb)
	return THERMAL_UNKNOWN


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
	if level != _first_level:
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


func _draw_room_labels() -> void:
	if thermal:
		return
	var font := PlanStyle.font()
	for room in sim.building.rooms(level):
		if not _room_known(room.id):
			continue
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
	# 모르는 실내 구조는 그리지 않는다. 도면이 있으면 흐린 선만 (R8)
	if not t in BuildingData.OUTDOOR and not sim.plan.structure_seen(level, x, y):
		if sim.plan.known:
			_draw_plan_cell(x, y)
		return
	match t:
		BuildingData.Cell.WALL:
			var wh := _wall_height(x, y)
			match stack.wall_kind(level, x, y, _outside()):
				FloorStack.Wall.GLASS:
					_wall_piece(x, y, 0.0, wh, _structure_color(skin.color("wall")), stack.params.front_wall_alpha, stack.params.front_wall_alpha, stack.params.wall_cap_alpha)
				FloorStack.Wall.HALF:
					var ta := stack.params.inner_wall_top_alpha
					_wall_piece(x, y, 0.0, wh, _structure_color(skin.color("wall")), 1.0, ta, maxf(ta, 0.35))
				_:
					_block(x, y, 0.0, wh, _structure_color(skin.color("wall")), _cut_top(wh))
		BuildingData.Cell.WINDOW:
			_draw_window(x, y)
		BuildingData.Cell.DOOR:
			_draw_door(x, y)
	if level == _first_level and Vector2i(x, y) in sim.building.hydrants:
		_box(Vector2(x + 0.3, y + 0.3), Vector2(x + 0.7, y + 0.7), 0.0, HYDRANT_M, PlanStyle.HYDRANT_COLOR, PlanStyle.HYDRANT_COLOR)
		var label := proj.to_screen(Vector2(x + 0.5, y + 0.5), HYDRANT_M + 0.4)
		draw_string(PlanStyle.font(), label + Vector2(-30, 0), "소화전", HORIZONTAL_ALIGNMENT_CENTER, 60, 13, PlanStyle.HYDRANT_COLOR.lightened(0.4))
	var b := sim.building
	if level == _first_level:
		for m in sim.falls.mats:
			if Vector2i(m.floor()) == Vector2i(x, y):
				_box(m - Vector2(1.2, 0.8), m + Vector2(1.2, 0.8), 0.0, 0.5, Color("fde047"), Color("facc15"))
				draw_string(PlanStyle.font(), proj.to_screen(m, 0.9) + Vector2(-50, 0), "공기안전매트", HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color("fef08a"))
		for z in sim.falls.zones:
			if Vector2i(z.center.floor()) == Vector2i(x, y):
				var pts := PackedVector2Array()
				for k in 25:
					var a := TAU * k / 24.0
					pts.append(proj.to_screen(z.center + Vector2(cos(a), sin(a)) * z.radius, 0.02))
				draw_polyline(pts, Color(0.95, 0.3, 0.3, 0.8), 2.0)
				draw_string(PlanStyle.font(), proj.to_screen(z.center, 0.1) + Vector2(-50, 0), "낙하물 위험", HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color(1, 0.6, 0.6))
	if b.has_standpipe() and ((level == _first_level and Vector2i(x, y) == b.fdc) or Vector3i(x, y, level) in b.outlets):
		var is_fdc := Vector2i(x, y) == b.fdc and level == _first_level
		var sc := PlanStyle.STANDPIPE_COLOR
		_box(Vector2(x + 0.2, y + 0.2), Vector2(x + 0.8, y + 0.8), 0.0, 0.8, sc, sc)
		var sl := proj.to_screen(Vector2(x + 0.5, y + 0.5), 1.2)
		var txt := "송수구%s" % (" (연결)" if sim.water.fdc_vehicle >= 0 else "") if is_fdc else "방수구"
		draw_string(PlanStyle.font(), sl + Vector2(-50, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, 100, 13, sc.lightened(0.4))
	if level == _first_level and Vector2i(x, y) == sim.gas.valve and sim.gas.known(sim.command.survey):
		var gc := PlanStyle.GAS_COLOR if sim.gas.open else PlanStyle.GAS_COLOR.darkened(0.5)
		_box(Vector2(x + 0.25, y + 0.25), Vector2(x + 0.75, y + 0.75), 0.0, 0.9, gc, gc)
		var gl := proj.to_screen(Vector2(x + 0.5, y + 0.5), 1.3)
		draw_string(PlanStyle.font(), gl + Vector2(-60, 0), "%s%s" % [sim.gas.valve_text, "" if sim.gas.open else " (차단)"], HORIZONTAL_ALIGNMENT_CENTER, 120, 13, gc.lightened(0.4))
	if level == _first_level and not sim.plan.office.is_empty() and Vector2i(x, y) == sim.plan.office.cell:
		_draw_office(x, y)
	var fh := _furniture_height(x, y)
	var ci := y * sim.building.width + x
	if fh > 0.0 and (thermal or not SpriteArt.enabled() or not _furn_cells.get(level, {}).has(ci)):
		var color := THERMAL_FURNITURE if thermal else _furniture_color(x, y)
		_block(x, y, 0.0, fh, color)
	elif not thermal and SpriteArt.enabled() and _furn_draw.get(level, {}).has(ci):
		_draw_furniture_sprite(_furn_draw[level][ci], x, y)
	if upper_level >= 0 and t == BuildingData.Cell.STAIRS:
		_draw_stair_step(x, y)
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
	if _outside() and _wall_height(x, y) > DOOR_TOP_M:
		# 외부 보기: 문 위 벽 (외벽이 천장까지 서 있으므로, 문 블록 다음에 그려야 윗면에 덮이지 않는다)
		_block(x, y, DOOR_TOP_M, _wall_height(x, y), _structure_color(PlanStyle.CELL_COLORS[BuildingData.Cell.WALL]))
	var task := sim.doors.task_of(o)
	if task and first:
		var r := Rect2(top.x - 22.0, top.y + 4.0, 44.0, 5.0)
		draw_rect(r, PlanStyle.TANK_BG)
		draw_rect(Rect2(r.position, Vector2(r.size.x * task.progress / task.required, r.size.y)), Color("ffb74d"))
		if task.waiting_people:
			draw_string(PlanStyle.font(), top + Vector2(-40, 22), "인원 부족", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color("ff8a80"))


func _draw_window(x: int, y: int) -> void:
	var h := _wall_height(x, y)
	var wall := _structure_color(skin.color("wall"))
	var o: Opening = _opening_of.get(Vector3i(x, y, level))
	var glass := GLASS_COLOR if not (o and o.broken) else Color(0, 0, 0, 0)
	if o and not o.broken and o in _lit:
		glass = PlanStyle.LIT_WINDOW
	if _outside() and o and o.room_b == Opening.OUTSIDE:
		glass = _facade_glass(o)
	if thermal:
		glass = THERMAL_STRUCTURE
	if h < WINDOW_SILL_M:
		# 잘린 창: 벽 단면 띠 위에 유리 선만 남긴다
		_block(x, y, 0.0, h, wall, _cut_top(h))
		if glass.a > 0.0 and not thermal:
			var g := _tile(x + 0.4, y + 0.4, h)
			draw_line((g[0] + g[3]) * 0.5, (g[1] + g[2]) * 0.5, Color(glass, 0.9), 2.0)
		return
	_block(x, y, 0.0, WINDOW_SILL_M, wall)
	if glass.a > 0.0:
		_block(x, y, WINDOW_SILL_M, minf(WINDOW_TOP_M, h), glass)
	# 창 위 벽: 앞 바깥벽이면 벽과 같은 반투명 (창 자체는 진하게 — 깨서 배연하는 대상)
	if stack.wall_kind(level, x, y, _outside()) == FloorStack.Wall.GLASS:
		_wall_piece(x, y, WINDOW_TOP_M, h, wall, stack.params.front_wall_alpha, stack.params.front_wall_alpha, stack.params.wall_cap_alpha)
	else:
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
	if depth == 0 and fade >= 1.0:
		_glow_spots.append([base, IsoProjection.HALF_W * (3.0 + 3.0 * intensity), intensity, x * 131 + y])
	# 셰이더로 구운 불꽃 그림 (tools/bake_fx.gd). 없으면 아래 도형
	var fh_px := (0.6 + 1.5 * intensity) * IsoProjection.PX_PER_M * flicker
	var fw_px := IsoProjection.HALF_W * (1.0 + 0.6 * intensity)
	# 최성기(세게 타는 칸)는 불꽃 뒤에 불덩이(Kenney Explosion)를 깔아 불의 덩어리감을 준다
	if intensity > FIRE_MASS_FROM:
		var mass := (intensity - FIRE_MASS_FROM) / (1.0 - FIRE_MASS_FROM)
		var bob := Vector2(0, -fh_px * 0.35 - sin(t * 1.7 + seed_f) * 3.0)
		FxArt.draw_puff(self, base + bob, fw_px * (1.3 + 0.4 * mass), FxArt.PUFF_FIRE, x * 7 + y * 3 + int(t * 0.5), Color(1, 1, 1, 0.55 * mass * fade))
	if FxArt.draw_flame(self, base + Vector2(sin(t * 2.3 + seed_f) * 1.5, 0), fw_px, fh_px, (x * 31 + y * 17), Color(1, 1, 1, fade)):
		return
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
		if not _draw_unit_sprite(ff, crew, squad, feet):
			draw_colored_polygon(_ellipse(feet, 16, 6), body_color.darkened(0.2))
			draw_circle(feet + Vector2(14, -2), UNIT_HEAD_R * 0.8, Color.WHITE)
		var warn := proj.to_screen(p, 0.9)
		draw_string(PlanStyle.font(), warn + Vector2(-40, 0), "행동 불능", HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color("ff6b6b"))
		return
	var scale := CROUCH_SCALE if ff.crouched else 1.0
	if not _draw_unit_sprite(ff, crew, squad, feet):
		_draw_figure(p, scale, body_color, SpriteArt.helmet_color(squad.type))
	var label := proj.to_screen(p, UNIT_LABEL_M * scale)
	draw_string(PlanStyle.font(), label + Vector2(-30, 0), str(crew.number) + _role_tag(crew), HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color.WHITE)
	_draw_air_bar(label + Vector2(0, 4), ff)


## 구운 그림으로 대원 그리기 (P15). 그림이 없거나 열화상이면 false → 도형
func _draw_unit_sprite(ff: Firefighter, crew: Crew, squad: Squad, feet: Vector2) -> bool:
	if thermal:
		return false
	var art := SpriteArt.get_set(str(SpriteArt.config().get("crew", "")))
	if art == null:
		return false
	var delta := ff.pos - ff.prev_pos
	var moving := ff.level == ff.prev_level and delta.length_squared() > 0.000001
	var anim := "idle"
	var task := sim.rescue.task_of_crew(crew.id)
	var hose := sim.water.hose_of_crew(crew.id)
	if moving:
		_facing[ff.id] = SpriteArt.dir8(delta)
	if ff.incapacitated:
		anim = "down"
	elif task is RescueSystem.CarryTask and task.carrying:
		anim = "carry"
	elif hose and hose.flowing and not hose.approaching and not moving:
		anim = "spray"
		_facing[ff.id] = SpriteArt.dir8(hose.aim - ff.pos)
	elif task is RescueSystem.SearchTask and not moving:
		anim = "search"
	elif moving:
		anim = "crouch_walk" if ff.crouched else "walk"
	elif ff.crouched:
		anim = "crouch_walk"
	var frame := 0
	if moving or anim in ["idle", "spray", "search"]:
		frame = SpriteArt.frame_at(anim, art.frames(anim), ff.id * 0.37)
	# 헬멧 색은 출동대 종류로만 (진압 검정·구조 주황·구급 흰색). RIT·안전담당은 임무라 이름표로 (_role_tag)
	var tint := Color.WHITE.lerp(Color(1.0, 0.45, 0.35), clampf(ff.heat_stress, 0.0, 1.0) * 0.6)
	return art.draw(self, anim, int(_facing.get(ff.id, 1)), frame, feet, tint, SpriteArt.helmet_color(squad.type))


## 임무 역할 이름표: RIT·현장안전담당 (헬멧 색은 바꾸지 않는다)
func _role_tag(crew: Crew) -> String:
	match sim.command.safety.role_of(crew.id):
		SafetySystem.Role.RIT:
			return " RIT"
		SafetySystem.Role.OFFICER:
			return " 안전"
	return ""


## 현장지휘관: 흰 몸체·빨간 안전모, "지휘" 표시
func _draw_commander(alpha: float) -> void:
	var c := sim.command.commander
	var p := UnitsView.display_pos(c, alpha)
	var feet := proj.to_screen(p, 0.0)
	draw_colored_polygon(_ellipse(feet, 10, 5), Color(0, 0, 0, 0.3))
	if selection.commander_selected:
		draw_polyline(_ellipse(feet, 13, 6.5, true), PlanStyle.SELECTION, 2.0)
	var art := SpriteArt.get_set(str(SpriteArt.config().get("commander", ""))) if not thermal else null
	var delta := c.pos - c.prev_pos
	var moving := c.level == c.prev_level and delta.length_squared() > 0.000001
	if moving:
		_facing[-1] = SpriteArt.dir8(delta)
	var anim := "walk" if moving else "idle"
	if art == null or not art.draw(self, anim, int(_facing.get(-1, 1)), SpriteArt.frame_at(anim, art.frames(anim)), feet,
			Color.WHITE, SpriteArt.helmet_color("지휘")):
		_draw_figure(p, 1.0, PlanStyle.COMMANDER_BODY, PlanStyle.COMMANDER_HELMET)
	var label := proj.to_screen(p, UNIT_LABEL_M)
	draw_string(PlanStyle.font(), label + Vector2(-30, 0), "지휘", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color.WHITE)


## 관계인: 사복 차림, 머리 위 이름
func _draw_witness(w: Witness) -> void:
	var feet := proj.to_screen(w.pos, 0.0)
	draw_colored_polygon(_ellipse(feet, 10, 5), Color(0, 0, 0, 0.3))
	var art := SpriteArt.get_set(str(SpriteArt.config().get("witness", ""))) if not thermal else null
	if art == null or not art.draw(self, "idle", 1, SpriteArt.frame_at("idle", art.frames("idle"), 0.5), feet):
		_draw_figure(w.pos, 1.0, PlanStyle.WITNESS_BODY, PlanStyle.WITNESS_HEAD, false)
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
	var h := minf(v.height_m, VEHICLE_CUT_M)
	var color := THERMAL_FURNITURE if thermal else v.color
	color.a = VEHICLE_ALPHA
	var art := SpriteArt.vehicle_set(v.type) if not thermal else null
	if art != null and art.draw(self, "idle", SpriteArt.dir8(v.heading), 0, proj.to_screen(center, 0.0), Color(1, 1, 1, VEHICLE_ALPHA)):
		_vehicle_details_sprite(v, center)
	else:
		_prism(fp, 0.0, h, color)
		# 앞쪽 1/4 운전석 지붕
		var cab := PackedVector2Array([fp[0].lerp(fp[1], 0.75), fp[1], fp[2], fp[3].lerp(fp[2], 0.75)])
		draw_colored_polygon(_lift(cab, h), Color(color.darkened(0.35), VEHICLE_ALPHA))
		if not thermal:
			_vehicle_details(v, fp, h)
	if not thermal:
		# 운전원 작업 진행 막대 (기획안 6-1)
		var wp := sim.water.work_progress(v)
		if wp >= 0.0:
			var top := proj.to_screen(center, h + 1.2)
			draw_rect(Rect2(top + Vector2(-30, 0), Vector2(60, 6)), Color(0.1, 0.1, 0.1, 0.8))
			draw_rect(Rect2(top + Vector2(-30, 0), Vector2(60 * wp, 6)), Color("ffb74d"))
			draw_string(ThemeDB.fallback_font, top + Vector2(-50, -4), "%s %d초" % [v.work.label, ceili(float(v.work.remain))], HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color("ffe0b2"))
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


## 차량 세부: 보이는 옆면의 바퀴·반사띠, 앞면 유리창, 지붕 경광등
func _vehicle_details(v: Vehicle, fp: PackedVector2Array, h: float) -> void:
	# fp = [뒤 왼쪽, 앞 왼쪽, 앞 오른쪽, 뒤 오른쪽]. 화면 앞쪽(x + y가 큰 쪽) 옆면만 보인다
	var left := [fp[0], fp[1]]
	var right := [fp[3], fp[2]]
	var side: Array = right if (right[0] + right[1]).dot(Vector2.ONE) > (left[0] + left[1]).dot(Vector2.ONE) else left
	var stripe_color := Color.WHITE if v.color.get_luminance() < 0.6 else Color("ef4444")
	var band := PackedVector2Array([proj.to_screen(side[0], h * 0.38), proj.to_screen(side[1], h * 0.38),
		proj.to_screen(side[1], h * 0.46), proj.to_screen(side[0], h * 0.46)])
	draw_colored_polygon(band, Color(stripe_color, 0.9))
	for f in [0.18, 0.78]:
		var wp := proj.to_screen(side[0].lerp(side[1], f), 0.45)
		draw_circle(wp, 0.45 * IsoProjection.PX_PER_M, Color(0.08, 0.08, 0.1))
		draw_circle(wp, 0.2 * IsoProjection.PX_PER_M, Color(0.5, 0.5, 0.55))
	# 앞면(fp[1] → fp[2])이 보이면 유리창
	if ((fp[1] + fp[2]) * 0.5 - (fp[0] + fp[3]) * 0.5).dot(Vector2.ONE) > 0.0:
		var glass := PackedVector2Array([proj.to_screen(fp[1], h * 0.62), proj.to_screen(fp[2], h * 0.62),
			proj.to_screen(fp[2], h * 0.92), proj.to_screen(fp[1], h * 0.92)])
		draw_colored_polygon(glass, Color(0.15, 0.25, 0.35, 0.95))
	# 지붕 경광등 (운전석 위, 빨강·파랑 깜빡임)
	var t := Time.get_ticks_msec() / 1000.0
	var on := int(t * 3.0) % 2 == 0
	var bar_a := fp[1].lerp(fp[0], 0.12).lerp(fp[2].lerp(fp[3], 0.12), 0.3)
	var bar_b := fp[1].lerp(fp[0], 0.12).lerp(fp[2].lerp(fp[3], 0.12), 0.7)
	draw_circle(proj.to_screen(bar_a, h + 0.1), 5.0, Color("ef4444") if on else Color("7f1d1d"))
	draw_circle(proj.to_screen(bar_b, h + 0.1), 5.0, Color("3b82f6") if not on else Color("1e3a8a"))


## 구운 차량 그림 위에 경광등 깜빡임만 (P15). 차체·바퀴·유리는 그림에 있다
func _vehicle_details_sprite(v: Vehicle, center: Vector2) -> void:
	if not (v.is_pump() or v.is_aerial() or v.type in ["구급차", "구조공작차", "물탱크차"]):
		return
	var t := Time.get_ticks_msec() / 1000.0
	var on := int(t * 3.0) % 2 == 0
	var front := center + v.heading * v.length_cells * 0.3
	var side := Vector2(-v.heading.y, v.heading.x) * v.width_cells * 0.2
	draw_circle(proj.to_screen(front + side, v.height_m + 0.05), 4.0, Color("ef4444") if on else Color("7f1d1d"))
	draw_circle(proj.to_screen(front - side, v.height_m + 0.05), 4.0, Color("3b82f6") if not on else Color("1e3a8a"))


func _draw_sprays(alpha: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for h in sim.water.hoses:
		if not h.flowing or h.flow_fraction <= 0.0:
			continue
		var leader := sim.units.get_crew(h.crew_id).leader
		if leader.level != level:
			continue
		# 외부 보기: 건물 안에서 쏘는 물은 외관에 가려진다
		if _outside() and not sim.building.cell(level, floori(leader.pos.x), floori(leader.pos.y)) in BuildingData.OUTDOOR:
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
		var layer_d := c.layer_depth
		var vis := sim.fire.visibility_m(c)
		var fade := 1.0
		if not p.room_visible(c):
			if p.room_seen[c.index] == 0:
				continue
			layer_d = p.room_seen_depth[c.index]
			vis = p.room_seen_visibility[c.index]
			fade = 0.5
		layer_d = clampf(layer_d, 0.0, CEILING_M)
		if layer_d < 0.05:
			continue
		var density := 1.0 - clampf(vis / 10.0, 0.0, 1.0)
		var a := (SMOKE_MIN_ALPHA + SMOKE_DENSITY_ALPHA * density) * fade
		var r := c.rect
		var h := CEILING_M - layer_d
		var plane := PackedVector2Array([
			proj.to_screen(Vector2(r.position), h), proj.to_screen(Vector2(r.end.x, r.position.y), h),
			proj.to_screen(Vector2(r.end), h), proj.to_screen(Vector2(r.position.x, r.end.y), h),
		])
		# 단면(남·동 앞면): 천장부터 연기층 아래 경계(중성대)까지 채워 연기층 두께가 보이게 한다 (R17)
		var front := Color(FireView.SMOKE_COLOR, minf(0.6, a + 0.1))
		_face_room("S", r, h, CEILING_M, front.darkened(SOUTH_SHADE))
		_face_room("E", r, h, CEILING_M, front.darkened(EAST_SHADE))
		draw_colored_polygon(plane, Color(FireView.SMOKE_COLOR, a * 0.65))
		_draw_smoke_texture(plane, r, a, c.index)
		plane.append(plane[0])
		draw_polyline(plane, Color(FireView.SMOKE_COLOR.darkened(0.3), minf(1.0, a + 0.15)), 1.5)
		if c.rollover and p.room_visible(c):
			_draw_rollover(r, h)
	_draw_smoke_plumes()


## 연기층 평면에 셰이더로 구운 연기 질감을 두 겹, 서로 다른 쪽으로 흘려 입힌다 (P15-FX)
func _draw_smoke_texture(plane: PackedVector2Array, r: Rect2i, a: float, seed: int) -> void:
	if not FxArt.load_all() or FxArt.noise == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var corners := [Vector2(r.position), Vector2(r.end.x, r.position.y), Vector2(r.end), Vector2(r.position.x, r.end.y)]
	for layer in 2:
		var uvs := PackedVector2Array()
		var drift := Vector2(t * 0.018, t * 0.011) if layer == 0 else Vector2(-t * 0.013, t * 0.02)
		var scale := 0.09 if layer == 0 else 0.15
		for cv: Vector2 in corners:
			uvs.append(cv * scale + drift + Vector2(seed * 0.37, seed * 0.21))
		var col := Color(FireView.SMOKE_COLOR.lightened(0.15 * layer), a * (0.55 if layer == 0 else 0.35))
		draw_polygon(plane, PackedColorArray([col, col, col, col]), uvs, FxArt.noise)


## 방 직사각형의 앞면(남 "S" 또는 동 "E")에서 높이 h0~h1 띠
func _face_room(face: String, r: Rect2i, h0: float, h1: float, color: Color) -> void:
	var a := Vector2(r.position.x, r.end.y) if face == "S" else Vector2(r.end.x, r.position.y)
	var b := Vector2(r.end)
	_quad(proj.to_screen(a, h0), proj.to_screen(b, h0), proj.to_screen(b, h1), proj.to_screen(a, h1), color)


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
		if _draw_blast_art(at, age, int(blast[2])):
			continue
		draw_circle(at, 20.0 + age * 90.0, Color(1.0, 0.5, 0.1, 0.6 * (1.0 - age)))
		draw_circle(at, 10.0 + age * 50.0, Color(1.0, 0.9, 0.4, 0.8 * (1.0 - age)))


## 폭발(플래시오버·백드래프트) 순간 (구운 그림): 처음엔 흰 섬광, 이어서 불덩이 여럿이 퍼지며 검은 연기로 바뀐다
func _draw_blast_art(at: Vector2, age: float, key: int) -> bool:
	if not FxArt.load_all():
		return false
	var fade := 1.0 - age
	for k in 5:
		var dir := Vector2.from_angle(TAU * k / 5.0 + key) * Vector2(1.0, 0.55)
		var pos := at + dir * (10.0 + age * 70.0) + Vector2(0, -age * 30.0)
		var size := 60.0 + age * 110.0
		# 뒤쪽은 검은 연기로 번진다
		FxArt.draw_puff(self, pos + Vector2(0, -12), size * 1.15, FxArt.PUFF_BLACK, key + k, Color(0.3, 0.3, 0.32, 0.5 * fade * age))
		if not FxArt.draw_puff(self, pos, size, FxArt.PUFF_FIRE, key + k, Color(1, 1, 1, 0.95 * fade)):
			return false
	if age < 0.35:
		FxArt.draw_puff(self, at, 90.0 + age * 160.0, FxArt.PUFF_FLASH, key, Color(1, 1, 1, 1.0 - age / 0.35))
	return true


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
		var tag: Color = sim.ems.shown_color(p)
		var at := proj.to_screen(v.pos, 0.05)
		if not _draw_victim_sprite(v, at):
			draw_colored_polygon(_ellipse(at + Vector2(0, -3), 13, 5), color)
		draw_circle(at + Vector2(12, -5), 5.0, tag)
		draw_string(PlanStyle.font(), at + Vector2(-70, -14), "%s · %s · %s" % [v.label(), sim.ems.shown_name(p), EmsSystem.STAGE_NAMES[p.stage]], HORIZONTAL_ALIGNMENT_CENTER, 140, 12, tag.lightened(0.3))
		return
	var feet := proj.to_screen(v.pos, 0.05)
	draw_colored_polygon(_ellipse(feet, 15, 6), Color(0, 0, 0, 0.35))
	if not _draw_victim_sprite(v, feet):
		draw_colored_polygon(_ellipse(feet + Vector2(0, -3), 13, 5), color)
		draw_circle(feet + Vector2(12, -5), 5.0, color.lightened(0.3))
	draw_string(PlanStyle.font(), feet + Vector2(-50, -14), "%s · %s" % [v.label(), v.state_name()], HORIZONTAL_ALIGNMENT_CENTER, 100, 12, color.lightened(0.4))


## 구운 그림으로 요구조자 (P15): 의식 있음 = 서 있음(대피 중이면 걷기), 그 밖 = 누움. 사망은 어둡게
func _draw_victim_sprite(v: Victim, feet: Vector2) -> bool:
	if thermal:
		return false
	var art := SpriteArt.victim_set(v.label())
	if art == null:
		return false
	var walking := sim.evac.paths.has(v.id) and v.state == Victim.State.CONSCIOUS
	var standing := v.state == Victim.State.CONSCIOUS
	var anim := "walk" if walking else ("idle" if standing else "down_up")
	var tint := Color(0.55, 0.55, 0.6) if v.state == Victim.State.DEAD else Color.WHITE
	var dir := (v.id * 3) % 8
	return art.draw(self, anim, dir, SpriteArt.frame_at(anim, art.frames(anim), v.id * 0.5), feet, tint)


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
			var col := Color(PlanStyle.SMOKE_PLUME, PlanStyle.SMOKE_PLUME.a * (1.0 - f) * strength)
			if not FxArt.draw_puff(self, pos, r * 3.2, 0, k + int(t), Color(0.55, 0.55, 0.58, col.a * 1.6)):
				draw_circle(pos, r, col)


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


## 면은 모두 볼록 사각형이라 다각형 분할(draw_colored_polygon)이 필요 없다: draw_primitive로 바로 그린다.
## 높이는 화면에서 위로 PX_PER_M씩 올라가므로 바닥 모서리 4개만 변환하고 높이는 더한다.
func _box(p0: Vector2, p1: Vector2, h0: float, h1: float, color: Color, side_color: Color, top_color := Color(0, 0, 0, 0)) -> void:
	var nw := proj.to_screen(p0)
	var ne := proj.to_screen(Vector2(p1.x, p0.y))
	var se := proj.to_screen(p1)
	var sw := proj.to_screen(Vector2(p0.x, p1.y))
	var lo := Vector2(0, -h0 * IsoProjection.PX_PER_M)
	var hi := Vector2(0, -h1 * IsoProjection.PX_PER_M)
	_quad(sw + lo, se + lo, se + hi, sw + hi, Color(side_color.darkened(SOUTH_SHADE), side_color.a))
	_quad(ne + lo, se + lo, se + hi, ne + hi, Color(side_color.darkened(EAST_SHADE), side_color.a))
	_quad(nw + hi, ne + hi, se + hi, sw + hi, top_color if top_color.a > 0.0 else color)


## 투명한 벽 한 칸: 이웃이 벽(벽·문·창)인 쪽 면은 그리지 않아 겹친 이음새가 보이지 않는다.
## 면은 바닥(a0) → 꼭대기(a1)로 진하기가 바뀐다. 꼭대기 윗면은 cap 진하기 (벽 경계가 또렷하게)
func _wall_piece(x: int, y: int, h0: float, h1: float, color: Color, a0: float, a1: float, cap: float) -> void:
	if h1 <= h0:
		return
	var b := sim.building
	var wallish := [BuildingData.Cell.WALL, BuildingData.Cell.DOOR, BuildingData.Cell.WINDOW]
	var nw := proj.to_screen(Vector2(x, y))
	var ne := proj.to_screen(Vector2(x + 1, y))
	var se := proj.to_screen(Vector2(x + 1, y + 1))
	var sw := proj.to_screen(Vector2(x, y + 1))
	var lo := Vector2(0, -h0 * IsoProjection.PX_PER_M)
	var hi := Vector2(0, -h1 * IsoProjection.PX_PER_M)
	if not (b.in_bounds(x, y + 1) and b.cell(level, x, y + 1) in wallish):
		var c := color.darkened(SOUTH_SHADE)
		_quad_grad(sw + lo, se + lo, se + hi, sw + hi, Color(c, a0), Color(c, a1))
	if not (b.in_bounds(x + 1, y) and b.cell(level, x + 1, y) in wallish):
		var c := color.darkened(EAST_SHADE)
		_quad_grad(ne + lo, se + lo, se + hi, ne + hi, Color(c, a0), Color(c, a1))
	_quad(nw + hi, ne + hi, se + hi, sw + hi, Color(_structure_color(skin.color("cut_face")), cap))


## 아래 두 점은 bottom 색, 위 두 점은 top 색 (a, b = 아래 / c, d = 위)
func _quad_grad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, bottom: Color, top: Color) -> void:
	if _batching:
		var base := _bq_pts.size()
		_bq_pts.append_array([a, b, c, d])
		_bq_cols.append_array([bottom, bottom, top, top])
		_bq_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		return
	draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([bottom, bottom, top, top]), PackedVector2Array())


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	if _batching:
		var base := _bq_pts.size()
		_bq_pts.append_array([a, b, c, d])
		_bq_cols.append_array([color, color, color, color])
		_bq_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		return
	draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([color, color, color, color]), PackedVector2Array())


## 선 (묶어 그리는 중이면 모았다가 한 번에)
func _line(a: Vector2, b: Vector2, color: Color) -> void:
	if _batching:
		_bl_pts.append(a)
		_bl_pts.append(b)
		_bl_cols.append(color)
		return
	draw_line(a, b, color, 1.5)


func _flush_batch() -> void:
	_batching = false
	if not _bq_pts.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _bq_idx, _bq_pts, _bq_cols)
	if not _bl_pts.is_empty():
		draw_multiline_colors(_bl_pts, _bl_cols, 1.5)
	_bq_pts.clear()
	_bq_cols.clear()
	_bq_idx.clear()
	_bl_pts.clear()
	_bl_cols.clear()


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
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry * GROUND_RATIO))
	return pts


## 사람 모양: 발 → 엉덩이 → 어깨로 넓어지는 몸통, 반사띠, 머리(안전모). 키 약 1.75m
func _draw_figure(p: Vector2, scale: float, body: Color, helmet: Color, stripes := true) -> void:
	var feet := proj.to_screen(p, 0.0)
	var hip := proj.to_screen(p, UNIT_HIP_M * scale).y
	var shoulder := proj.to_screen(p, UNIT_BODY_M * scale).y
	var w := UNIT_HALF_W
	var poly := PackedVector2Array([
		Vector2(feet.x - UNIT_FOOT_HALF_W, feet.y), Vector2(feet.x + UNIT_FOOT_HALF_W, feet.y),
		Vector2(feet.x + w * 0.8, hip), Vector2(feet.x + w, shoulder + 3.0), Vector2(feet.x + w * 0.7, shoulder),
		Vector2(feet.x - w * 0.7, shoulder), Vector2(feet.x - w, shoulder + 3.0), Vector2(feet.x - w * 0.8, hip)])
	draw_colored_polygon(poly, body)
	# 장화·다리 사이
	draw_rect(Rect2(feet.x - UNIT_FOOT_HALF_W, feet.y - 5.0, UNIT_FOOT_HALF_W * 2.0, 5.0), body.darkened(0.55))
	draw_line(Vector2(feet.x, feet.y), Vector2(feet.x, lerpf(feet.y, hip, 0.85)), body.darkened(0.45), 1.5)
	if stripes:
		for h in [0.35, 1.05]:
			var y := proj.to_screen(p, h * scale).y
			var half := lerpf(UNIT_FOOT_HALF_W, w * 0.8, clampf(h / UNIT_HIP_M, 0.0, 1.0)) if h < UNIT_HIP_M else w * 0.85
			draw_line(Vector2(feet.x - half, y), Vector2(feet.x + half, y), REFLECTIVE, 2.5)
	poly.append(poly[0])
	draw_polyline(poly, PlanStyle.UNIT_OUTLINE, 1.0)
	var head := proj.to_screen(p, UNIT_HEAD_M * scale)
	draw_circle(head + Vector2(0, 2), UNIT_HEAD_R * 0.8, Color(0.93, 0.78, 0.65))
	draw_colored_polygon(_ellipse(head + Vector2(0, 1), UNIT_HEAD_R * 1.25, UNIT_HEAD_R * 0.3), helmet.darkened(0.15))
	draw_circle(head - Vector2(0, 2), UNIT_HEAD_R * 0.9, helmet)
	draw_arc(head - Vector2(0, 2), UNIT_HEAD_R * 0.9, PI, TAU, 10, PlanStyle.UNIT_OUTLINE, 1.0)


func _wall_height(x: int, y: int) -> float:
	# R17: 뒷벽(바깥이 북·서) 천장까지. 외부 보기는 외벽이 모두 천장까지.
	# 2026-11-11: 앞 바깥벽은 천장 높이 반투명(GLASS), 실내 벽은 허리 높이(HALF)
	match stack.wall_kind(level, x, y, _outside()):
		FloorStack.Wall.FULL, FloorStack.Wall.GLASS:
			return CEILING_M
		FloorStack.Wall.CUT:
			return stack.params.wall_cut_m
		FloorStack.Wall.HALF:
			return stack.params.inner_wall_m
	return 0.0


## 잘린 벽 윗면 색 (두께가 보이는 밝은 단면 띠). 천장까지 선 벽은 몸체 색 그대로
func _cut_top(h: float) -> Color:
	if h >= CEILING_M - 0.01:
		return Color(0, 0, 0, 0)
	return _structure_color(skin.color("cut_face"))


## 바닥 칸 색 (실내 바닥·계단은 타일 종류표, 바깥은 평면도 색)
func _ground_base(t: int) -> Color:
	match t:
		BuildingData.Cell.FLOOR:
			return skin.color("floor")
		BuildingData.Cell.STAIRS:
			return skin.color("stairs")
	return PlanStyle.CELL_COLORS[t]


## 위층과 이어지는 계단 칸 (위층이 함께 보일 때만)
func _ramp_cells() -> Array[Vector2i]:
	if upper_level < 0:
		return []
	var key := "%d:%d" % [level, upper_level]
	if not _ramps.has(key):
		var cells := stack.stair_links_between(level, upper_level)
		_ramps[key] = cells
		var r := Rect2i()
		for i in cells.size():
			r = Rect2i(cells[i], Vector2i.ONE) if i == 0 else r.merge(Rect2i(cells[i], Vector2i.ONE))
		_ramp_rects[key] = r
	return _ramps[key]


## 아래층 바닥에서 위층 바닥까지 올라가는 계단 디딤판 (칸마다 두 단, 북쪽으로 올라간다 — 챌판이 보는 쪽)
func _draw_stair_step(x: int, y: int) -> void:
	var key := "%d:%d" % [level, upper_level]
	if not _ramp_rects.has(key):
		return
	var r: Rect2i = _ramp_rects[key]
	if not r.has_point(Vector2i(x, y)):
		return
	var rise := stack.params.floor_height_px / IsoProjection.PX_PER_M
	var steps := r.size.y * 2
	var color := _structure_color(skin.color("stair_step"))
	for k in 2:
		var y0 := y + k * 0.5
		var from_south := int(roundf((r.end.y - (y0 + 0.5)) / 0.5))
		var h := rise * float(from_south + 1) / float(steps)
		_box(Vector2(x, y0), Vector2(x + 1, y0 + 0.5), 0.0, h, color, color)


## 층 사이 바닥판 앞 모서리 (바깥이 빈 공중인 남·동쪽): 두께가 보이는 진회색 띠
func _draw_slab_edges() -> void:
	if not _slab_edges.has(level):
		var list: Array[Vector3i] = []
		var b := sim.building
		for y in b.height:
			for x in b.width:
				if not b.cell(level, x, y) in BuildingData.STRUCTURE:
					continue
				var bits := 0
				if b.cell(level, x, y + 1) == BuildingData.Cell.VOID:
					bits |= 1
				if b.cell(level, x + 1, y) == BuildingData.Cell.VOID:
					bits |= 2
				if bits != 0:
					list.append(Vector3i(x, y, bits))
		_slab_edges[level] = list
	var slab := _structure_color(skin.color("slab_edge"))
	var lo := Vector2(0, stack.params.slab_m * IsoProjection.PX_PER_M)
	for e: Vector3i in _slab_edges[level]:
		var se := proj.to_screen(Vector2(e.x + 1, e.y + 1))
		if e.z & 1:
			var sw := proj.to_screen(Vector2(e.x, e.y + 1))
			_quad(sw, se, se + lo, sw + lo, slab)
		if e.z & 2:
			var ne := proj.to_screen(Vector2(e.x + 1, e.y))
			_quad(ne, se, se + lo, ne + lo, slab.darkened(0.15))


## 가구마다 그림 묶음·방향·이어 붙일 조각을 정해 둔다 (P15). 앞면은 그 방 가운데를 본다
func _build_furniture_sprites(lv: int) -> void:
	var b := sim.building
	var cells := {}
	var draws := {}
	var items := b.furniture(lv)
	for n in items.size():
		var item: Dictionary = items[n]
		var art := SpriteArt.furniture_set(str(item.name))
		if art == null:
			continue
		var r: Rect2i = item.rect
		var center := Vector2(r.position) + Vector2(r.size) * 0.5
		var room := sim.fire.compartment_at(lv, floori(center.x), floori(center.y))
		var rc := Vector2(room.rect.get_center()) if room else center
		var along_x := r.size.x >= r.size.y
		var long_cells := float(maxi(r.size.x, r.size.y))
		var info := {"art": art, "rect": r}
		if art.directions == 8:
			# 차량 그림 (주차 차량): 긴 쪽 방향, 크기는 실제 길이 비율
			info.dir = 0 if along_x else 2
			var size_m: Array = art.meta.get("size_m", [long_cells * b.cell_size_m])
			info.segments = [center]
			info.size = long_cells * b.cell_size_m / float(size_m[0])
		else:
			if along_x:
				info.dir = 0 if rc.y >= center.y else 2
			else:
				info.dir = 3 if rc.x >= center.x else 1
			var nominal: Array = art.meta.get("nominal", [long_cells, 1])
			var count := maxi(1, roundi(long_cells / float(nominal[0])))
			var seg := long_cells / count
			var segs: Array[Vector2] = []
			for k in count:
				var off := -long_cells * 0.5 + seg * (k + 0.5)
				segs.append(center + (Vector2(off, 0) if along_x else Vector2(0, off)))
			info.segments = segs
			info.size = seg / float(nominal[0])
		for yy in range(r.position.y, r.end.y):
			for xx in range(r.position.x, r.end.x):
				cells[yy * b.width + xx] = n
		draws[(r.end.y - 1) * b.width + (r.end.x - 1)] = info
	_furn_cells[lv] = cells
	_furn_draw[lv] = draws


func _draw_furniture_sprite(info: Dictionary, x: int, y: int) -> void:
	var art: SpriteArt.SpriteSet = info.art
	# 다 탄 가구는 어둡게, 타는 중이면 붉게
	var grid := sim.fire.grid
	var i := grid.index(level, x, y)
	var tint := Color.WHITE
	if _cell_burnt(x, y):
		tint = Color(0.25, 0.22, 0.2)
	elif grid.state[i] == FuelGrid.State.BURNING and sim.perception.is_visible(level, x, y):
		tint = Color(0.6, 0.4, 0.3)
	for c: Vector2 in info.segments:
		art.draw(self, "idle", int(info.dir), 0, proj.to_screen(c, 0.0), tint, Color(0, 0, 0, 0), float(info.size))


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


# --- 도면 (R8) ---

## 도면으로만 아는 칸: 벽·창은 낮은 흐린 선, 문은 노란 흐린 선
func _draw_plan_cell(x: int, y: int) -> void:
	var t := sim.plan.plan_cell(level, x, y)
	if t == BuildingData.Cell.WALL or t == BuildingData.Cell.WINDOW:
		_block(x, y, 0.0, 0.12, PLAN_LINE)
	elif t == BuildingData.Cell.DOOR:
		_block(x, y, 0.0, 0.06, PLAN_DOOR)


## 방 이름을 보여도 되는가: 대원이 그 방을 봤거나 도면이 있다
func _room_known(room_id: String) -> bool:
	if not sim.perception.enabled or sim.plan.known:
		return true
	for c in sim.fire.comps:
		if c.id == room_id:
			return sim.perception.room_seen[c.index] != 0
	return true


## 관리사무소·방재실: 조를 보내 머물게 하면 도면을 얻는다 (R8)
func _draw_office(x: int, y: int) -> void:
	var oc := Color("a78bfa")
	_box(Vector2(x - 0.4, y - 0.4), Vector2(x + 1.4, y + 1.4), 0.0, 1.6, oc.darkened(0.3), oc.darkened(0.5), oc)
	var at := proj.to_screen(Vector2(x + 0.5, y + 0.5), 2.2)
	var label := str(sim.plan.office.name)
	if sim.plan.known:
		label += " — 도면 확보"
	elif sim.plan.dwell_progress() > 0.0:
		label += " — 도면 확인 중 %d%%" % roundi(sim.plan.dwell_progress() * 100.0)
	else:
		label += " (조를 보내면 도면)"
	draw_string(PlanStyle.font(), at + Vector2(-110, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 220, 13, oc.lightened(0.4))


## 방수포 물줄기(펌프차 → 창)와 송풍기 표시 (R11). 지금 층의 창만 그린다
func _draw_monitors_and_fans() -> void:
	for st in sim.monitors.streams:
		var v := sim.units.get_vehicle(st.vehicle_id)
		var o: Opening = sim.fire.openings[st.opening]
		if v == null or o.level != level:
			continue
		var a := proj.to_screen(v.pos, v.height_m + 0.6)
		var b := proj.to_screen(Vector2(o.cells[0]) + Vector2(0.5, 0.5), 1.2)
		var mid := (a + b) * 0.5 + Vector2(0, -60)
		var pts := PackedVector2Array()
		for k in 17:
			var t := k / 16.0
			pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
		draw_polyline(pts, Color(0.55, 0.8, 1.0, 0.85), 5.0, true)
		draw_string(PlanStyle.font(), b + Vector2(-40, -18), "방수포", HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color("bae6fd"))
	# 라이트라인·비상용승강기는 건물 안 — 외부 보기에서는 외관에 가려진다
	for lc: Vector3i in sim.lifeline.cells:
		if lc.z == level and not _outside():
			draw_circle(proj.to_screen(Vector2(lc.x + 0.5, lc.y + 0.5), 0.15), 3.0, Color("facc15"))
	if sim.elevator.available() and not _outside():
		# 승강로: 위층이 함께 보이면 위층 바닥까지 이어 그려 여러 층을 관통한다 (R17)
		var ec := Vector2(sim.elevator.cell) + Vector2(0.5, 0.5)
		var top := stack.params.floor_height_px / IsoProjection.PX_PER_M if upper_level >= 0 else 2.2
		var shaft := _structure_color(skin.color("shaft"))
		_box(ec - Vector2(0.45, 0.45), ec + Vector2(0.45, 0.45), 0.0, top, shaft, shaft.darkened(0.25), shaft.lightened(0.4))
		if depth == 0:
			draw_string(PlanStyle.font(), proj.to_screen(ec, 2.6) + Vector2(-60, 0), sim.elevator.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color("e2e8f0"))
	var vent := sim.vent
	if vent.opening >= 0:
		var op: Opening = sim.fire.openings[vent.opening]
		if op.level == level:
			var spot := Vector2(vent._outside_cell(op)) + Vector2(0.5, 0.5)
			_box(spot - Vector2(0.4, 0.4), spot + Vector2(0.4, 0.4), 0.0, 0.8, Color("94a3b8"), Color("64748b"), Color("cbd5e1"))
			var label := "송풍기" + (" — 가동" if vent.active else " — 설치 중")
			draw_string(PlanStyle.font(), proj.to_screen(spot, 1.3) + Vector2(-50, 0), label, HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color("e2e8f0"))


# --- 다른 층: 실루엣 (F01) ---

## 벽 줄: 이어진 벽 칸(벽·문·창)을 가로·세로 줄로 묶는다. 층마다 한 번.
## [{a: 시작(칸 가운데), b: 끝, outer: 바깥벽인가, comps: 맞닿은 방 index}]
func _ghost_wall_runs(lv: int) -> Array:
	if _ghost_walls.has(lv):
		return _ghost_walls[lv]
	var b := sim.building
	var wallish := [BuildingData.Cell.WALL, BuildingData.Cell.DOOR, BuildingData.Cell.WINDOW]
	var is_wall := func(x: int, y: int) -> bool: return b.in_bounds(x, y) and b.cell(lv, x, y) in wallish
	var runs: Array = []
	for horizontal in [true, false]:
		var outer_n: int = b.height if horizontal else b.width
		var inner_n: int = b.width if horizontal else b.height
		for o in outer_n:
			var k := 0
			while k < inner_n:
				var x: int = k if horizontal else o
				var y: int = o if horizontal else k
				if not is_wall.call(x, y):
					k += 1
					continue
				var start := k
				while k < inner_n and is_wall.call(k if horizontal else o, o if horizontal else k):
					k += 1
				var end := k - 1
				if end - start < 1:
					continue
				var cells: Array[Vector2i] = []
				for t in range(start, end + 1):
					cells.append(Vector2i(t, o) if horizontal else Vector2i(o, t))
				var outdoor := 0
				var touch: Array[int] = []
				for c in cells:
					var near_out := false
					for e: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						var n := c + e
						if not b.in_bounds(n.x, n.y) or b.cell(lv, n.x, n.y) in BuildingData.OUTDOOR:
							near_out = true
						var comp := sim.fire.compartment_at(lv, n.x, n.y)
						if comp and not comp.index in touch:
							touch.append(comp.index)
					if near_out:
						outdoor += 1
				runs.append({"a": Vector2(cells[0]) + Vector2(0.5, 0.5), "b": Vector2(cells[-1]) + Vector2(0.5, 0.5),
					"outer": outdoor * 2 >= cells.size(), "comps": touch})
	_ghost_walls[lv] = runs
	return runs


## 다른 층 (2026-11-11 사용자 결정):
##   ghost_mode 1 = 바로 위·아래 층: 벽·바닥만 회백색 한 톤 adjacent_alpha (바깥벽 천장 높이, 확인된 실내 벽 허리 높이)
##   ghost_mode 2 = 먼 아래층: 건물 외관 덩어리 (외벽·창·지붕) — 땅에서부터 이어진 건물로 보인다
##   ghost_mode 3 = 먼 위층: 아무것도 그리지 않는다 (지금 층을 가리므로 잘라 낸다 — 인형집 단면)
## 어느 경우든 그 층의 대원은 노란 테두리, 발견한 요구조자는 빨간 테두리 (_draw_ghost_units, 지금 층 위에 비쳐 보임).
## 1층(땅)이면 바깥 땅과 차량은 그대로 그린다
func _draw_ghost() -> void:
	_update_fire_rooms()
	if level == _first_level and ghost_mode != 3:
		_draw_outdoor_ground()
		var alpha := sim.clock.alpha()
		for v in sim.units.vehicles:
			if not v.away:
				_draw_vehicle(v, alpha)
	match ghost_mode:
		1:
			_draw_adjacent()
		2:
			_draw_far_block()
	if _ghost_units:
		_ghost_units.queue_redraw()


## 바깥 땅만 (건물 안 바닥 칸은 빼고)
func _draw_outdoor_ground() -> void:
	_update_ground_colors()
	if not _ghost_outdoor_idx.has(level):
		var idx := PackedInt32Array()
		var types: PackedByteArray = _ground_types[level]
		for n in types.size():
			if types[n] in BuildingData.OUTDOOR:
				var base := n * 4
				idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		_ghost_outdoor_idx[level] = idx
	var oi: PackedInt32Array = _ghost_outdoor_idx[level]
	if not oi.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), oi, _ground_points[level], _ground_colors)


## 바로 위·아래 층: 실내 바닥 칸과 벽을 회백색 한 톤으로 흐리게
func _draw_adjacent() -> void:
	var a := stack.params.adjacent_alpha
	var tone := Color(0.86, 0.87, 0.9)
	# 바닥: 실내 칸 마름모를 한 번에
	if not _ghost_floor_idx.has(level):
		var idx := PackedInt32Array()
		var types: PackedByteArray = _ground_types[level]
		for n in types.size():
			if not types[n] in BuildingData.OUTDOOR:
				var base := n * 4
				idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		_ghost_floor_idx[level] = idx
	var fi: PackedInt32Array = _ghost_floor_idx[level]
	# 위층 바닥은 그리지 않는다: 지금 층 전체를 뿌옇게 덮는다 (벽만으로 위층이 있음을 안다)
	if not fi.is_empty() and depth < ABOVE_DEPTH:
		var cols := PackedColorArray()
		cols.resize(_ground_points[level].size())
		cols.fill(Color(tone, a))
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), fi, _ground_points[level], cols)
	# 벽: 바깥벽은 천장 높이, 실내 벽은 확인된 곳만 허리 높이
	var p := sim.perception
	var plan_known := sim.command.interior.plan_known
	for run: Dictionary in _ghost_wall_runs(level):
		var outer: bool = run.outer
		var known := outer or plan_known or not p.enabled
		for ci: int in run.comps:
			if not known and p.room_seen[ci] == 1:
				known = true
		if not known:
			continue
		var h := CEILING_M if outer else stack.params.inner_wall_m
		var a0 := proj.to_screen(run.a, 0.0)
		var b0 := proj.to_screen(run.b, 0.0)
		var a1 := proj.to_screen(run.a, h)
		var b1 := proj.to_screen(run.b, h)
		draw_colored_polygon(PackedVector2Array([a0, b0, b1, a1]), Color(tone, a))
		draw_line(a1, b1, Color(tone, minf(1.0, a * 2.5)), 1.2)


## 먼 아래층: 건물 외관 덩어리 (외벽 남·동 면 + 지붕 + 창)
func _draw_far_block() -> void:
	var fp: Rect2i = _footprint.get(level, _shell_fp)
	var wall := Color(SHELL_WALL, 1.0)
	_box(Vector2(fp.position), Vector2(fp.end), 0.0, CEILING_M, wall, wall, ROOF_TOP)
	# 앞쪽(남·동) 창: 외부 보기와 같은 그림 (불빛·연기 창 색 포함)
	for w: Dictionary in _ext_windows.get(level, []):
		_draw_facade_window(w, 0.0, CEILING_M)


## 다른 층의 대원(노랑)·발견한 요구조자(빨강): 그림을 테두리 셰이더로. 그림이 없으면 동그라미 테두리
func _draw_ghost_units() -> void:
	if sim == null or not ghost:
		return
	var alpha := sim.clock.alpha()
	var crew_art := SpriteArt.get_set(str(SpriteArt.config().get("crew", ""))) if not thermal else null
	for c in sim.units.crews:
		for ff in c.members():
			if ff.level != level or ff.aboard:
				continue
			var p := UnitsView.display_pos(ff, alpha)
			var feet := proj.to_screen(p, 0.0)
			var moving := ff.level == ff.prev_level and (ff.pos - ff.prev_pos).length_squared() > 0.000001
			var anim := "down" if ff.incapacitated else ("walk" if moving else "idle")
			if crew_art == null or not crew_art.draw(_ghost_units, anim, int(_facing.get(ff.id, 1)), SpriteArt.frame_at(anim, crew_art.frames(anim), ff.id * 0.37), feet, GHOST_CREW):
				_ghost_units.draw_arc(feet + Vector2(0, -18), 9.0, 0.0, TAU, 16, GHOST_CREW, 2.0)
	for v in sim.rescue.victims:
		if not v.discovered or v.level != level or v.carried_by >= 0:
			continue
		var feet := proj.to_screen(v.pos, 0.05)
		var art := SpriteArt.victim_set(v.label()) if not thermal else null
		var anim := "idle" if v.state == Victim.State.CONSCIOUS else "down_up"
		if art == null or not art.draw(_ghost_units, anim, (v.id * 3) % 8, 0, feet, GHOST_VICTIM):
			_ghost_units.draw_arc(feet + Vector2(0, -6), 9.0, 0.0, TAU, 16, GHOST_VICTIM, 2.0)
