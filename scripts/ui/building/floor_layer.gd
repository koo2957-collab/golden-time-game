class_name FloorLayer
extends Node2D
## 입체(아이소메트릭) 화면의 층 하나 (R17: IsoView가 층마다 하나씩 둔다). 시뮬레이션 상태를 읽어 매 프레임 그린다.
## 그리는 순서 (뒤 → 앞):
##   1) 바닥 타일, 방 이름, 선택한 조의 경로
##   2) 대각선(x + y) 순서로 벽·문·창·가구·화염·대원 (앞에 있는 것이 나중에 그려져 뒤를 가린다)
##   3) 연기층: 천장에서 계산된 깊이만큼 내려온 반투명 덩어리
## 뒤쪽 외벽(북·서)은 천장 높이로, 나머지 벽은 낮게 잘라 실내가 보이게 한다.

## 위층 노드의 depth 시작값 (IsoView.ABOVE_DEPTH와 같음)
## 연기 읽기 계산 (색·빠르기·뻗는 길이, 2026-11-24)
const SmokeLook := preload("res://scripts/ui/smoke_look.gd")
const ABOVE_DEPTH := 100
const CEILING_M := 2.4
const WINDOW_SILL_M := 0.9
## 화면 연출: 이 세기(최대 열방출 대비) 넘게 타는 칸은 불꽃 뒤에 불덩이 그림을 깐다
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
## 본 적 있지만 지금 안 보이는 칸: 채도를 빼고 조금 어둡게 (2026-11-11)
const MEMORY_DESATURATE := 0.55
const MEMORY_DARKEN := 0.12
## 본 적 없는 칸 바닥: 색을 더 빼고 어둡게 (까맣게 칠하지 않는다)
const UNKNOWN_DESATURATE := 0.8
const UNKNOWN_DARKEN := 0.3
const FOG_UNKNOWN_ALPHA := 0.82
const FOG_SEEN_ALPHA := 0.4
## 도면도 없고 본 적도 없는 실내: 구조가 거의 보이지 않게 (기획안 9-1 "구조는 직접 밝힌다", R8)
const FOG_NO_PLAN_ALPHA := 0.95
const THERMAL_UNKNOWN := Color(0.03, 0.03, 0.05)
## 낮은 자세 대원의 키 비율
const CROUCH_SCALE := 0.62
## 할 일 없이 서 있는 분대의 '대기' 글자 (팀 줄 TeamStrip.IDLE_COLOR와 같은 색)
const IDLE_TAG := TeamStrip.IDLE_COLOR

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
				_ghost_units.visible = v or people_outline
			queue_redraw()
## 더 있는 층을 알리는 잘린 벽 (2026-11-12 사용자 결정): 이 층이 보이는 맨 위층이고 그 위로 층이 더 있으면 stub_above —
## 한 층 위에 뒷벽·왼쪽 벽을 반쯤 세워 위로 갈수록 투명하게. 보이는 맨 아래층이고 아래로 더 있으면 stub_below —
## 바닥 아래로 앞·오른쪽 바깥벽을 반쯤 내려 아래로 갈수록 투명하게. 잘린 변은 불규칙
var stub_above := false:
	set(v):
		if v != stub_above:
			stub_above = v
			queue_redraw()
var stub_below := false:
	set(v):
		if v != stub_below:
			stub_below = v
			queue_redraw()
## 아래층 (2026-11-12 사용자 결정): 구조는 온전히(흑백·어둡게) 그리고 그 층 사람은 점선 테두리로 — 켜면 사람 테두리 노드를 보인다
var people_outline := false:
	set(v):
		if v != people_outline:
			people_outline = v
			if _ghost_units:
				_ghost_units.visible = ghost or v
			queue_redraw()
## 다른 층 그리는 방식: 0 지금 층 / 1 바로 위·아래 / 2 먼 아래층(외관 덩어리) / 3 먼 위층(사람 테두리만). ghost는 0이 아닐 때 켜진다
## 짝 층 바탕(흑백): 불·연기·사람은 그리지 않는다 — 색 겹(ghost_mode 4)이 따로 그린다
var skip_live := false:
	set(v):
		if v != skip_live:
			skip_live = v
			queue_redraw()
var ghost_mode := 0:
	set(v):
		if v != ghost_mode:
			ghost_mode = v
			# 색 겹(4)·바깥 땅 겹(5)은 사람 테두리를 그리지 않는다
			ghost = v != 0 and v != 4 and v != 5
			queue_redraw()
var _ghost_outdoor_idx: Dictionary = {}  # level -> 바깥 땅 칸 삼각형 index
const GHOST_CREW := Color(1.0, 0.85, 0.2, 0.9)
## 알파 1 = 테두리 셰이더가 표시 방식과 상관없이 늘 테두리를 그린다 (shaders/ghost_outline.gdshader)
const GHOST_VICTIM := Color(1.0, 0.3, 0.3, 1.0)
var _ghost_units: Node2D
var _smoke_outline: Node2D
## 가려진 대원 표시 방식 견본 (2026-11-24): 테두리 셰이더 재질 둘 · 머리 위 표식 층 · 표식 목록 {"ghost"·"smoke": [..]} · 지금 맞춘 방식
var _ghost_other_mat: ShaderMaterial
var _ghost_smoke_mat: ShaderMaterial
var _badge_layer: Node2D
var _badge_items: Dictionary = {}
var _ghost_style_applied := "outline"
## 이번 그림에서 사람을 덮을 만큼 연기가 짙고 낮게 깔린 방 (Compartment.index → true)
var _smoky := {}
## 연기 상자 화면 윤곽 (진하기가 smoke_outline_opacity 이상인 방) — 그 안에 든 사람은 테두리로
var _smoke_hulls: Array[PackedVector2Array] = []
## 지금 그리는 벽 조각 표시: UV.x = 1000 + 벽 깊이(칸 x + y). 0이면 벽이 아님 (unit_hole 셰이더가 대상 앞 벽만 옅게)
var _wall_uv := Vector2.ZERO
var _ghost_walls: Dictionary = {}  # level -> 벽 줄 목록 (_ghost_wall_runs)

## 층 고르기 (P4-5): 외부 보기에서 노랗게 테두리를 그릴 층 (-99 = 없음)
var hover_floor := -99:
	set(v):
		if v != hover_floor:
			hover_floor = v
			queue_redraw()
## 층 띠 위 안내 문구 (비면 "N층 — 클릭: 내부 보기")
var hover_text := ""
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
## 지금 층의 불(채) 목록과 칸 번호 → 불들 (_fire_layout)
var _fire_bodies: Array[Dictionary] = []
var _fire_at: Dictionary = {}
var _fire_key: Array = []
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

## 미리 그려 넣는 그림자·음영 (입체감 1단계, 2026-11-22 — ShadowDraw, data/ui/shadow_style.json).
## 움직이지 않는 것(건물 땅 그림자·벽 아래 띠)은 한 번 만들어 두고 삼각형 묶음 하나로 그린다: "층:외부 보기" -> {points, colors, indices}
var _shade_static: Dictionary = {}
## 가구 그림자: 층 -> [{x, y 보이는지 판정할 칸, pts 화면 좌표 사각형들}]. 확인한 방의 타지 않은 가구만 틱마다 모아 한 번에 그린다
var _furn_shadow: Dictionary = {}
var _furn_shadow_key: Array = []
var _furn_shadow_pts := PackedVector2Array()
var _furn_shadow_cols := PackedColorArray()
var _furn_shadow_idx := PackedInt32Array()
## 밤 정도 (0 낮 … 1 밤, 시나리오 시각) — 해 그림자를 옅게
var _night := 0.0


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
	_fire_key = []
	_build_shell()
	_night = stack.params.night_factor(ViewParams.clock_hour(str(sim.scenario.get("clock", ""))))
	# 다른 층 사람 테두리: 테두리 셰이더를 입힌 자식에 따로 그린다 (벽 선은 이 층에 그대로)
	_ghost_units = Node2D.new()
	var outline_shader: Shader = load("res://shaders/ghost_outline.gdshader")
	# 다른 층 사람: 얇은 테두리만, 안쪽은 투명 (2026-11-12 사용자 결정)
	var other := ShaderMaterial.new()
	other.shader = outline_shader
	other.set_shader_parameter("fill", stack.params.ghost_other_fill)
	other.set_shader_parameter("thickness", stack.params.ghost_outline_px)
	# 다른 층 사람은 점선 테두리 (같은 층에서 가려진 사람은 실선) (2026-11-12 사용자 결정)
	other.set_shader_parameter("dash_px", stack.params.ghost_dash_px)
	_ghost_units.material = other
	# 같은 층에서 연기에 가려진 사람: 원래 색 + 얇은 테두리
	var mat := ShaderMaterial.new()
	mat.shader = outline_shader
	mat.set_shader_parameter("fill", stack.params.ghost_body_alpha)
	mat.set_shader_parameter("thickness", stack.params.ghost_outline_px)
	_ghost_units.visible = ghost or people_outline
	# 벽 너머 테두리처럼: 지금 층 그림 위에 그린다 (아래층 사람이 지금 층 바닥에 가려지지 않게)
	_ghost_units.z_as_relative = false
	_ghost_units.z_index = 100
	_ghost_units.draw.connect(_draw_ghost_units)
	add_child(_ghost_units)
	# 연기에 묻힌 사람 테두리 (2026-11-12 사용자 결정): 이 층 연기 바로 위에 (자식은 부모 그림 위에 그려진다)
	_smoke_outline = Node2D.new()
	_smoke_outline.material = mat
	_smoke_outline.draw.connect(_draw_smoke_outlines)
	add_child(_smoke_outline)
	# 가려진 대원의 머리 위 표식 (ghost_style badge·mix — 2026-11-24 견본): 셰이더 없이 맨 위에
	_ghost_other_mat = other
	_ghost_smoke_mat = mat
	_badge_layer = Node2D.new()
	_badge_layer.z_as_relative = false
	_badge_layer.z_index = 101
	_badge_layer.draw.connect(_draw_badges)
	add_child(_badge_layer)


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
			_fill(poly, Color(PlanStyle.ENTRY_POINT, 0.18 * glow))
			var loop := poly.duplicate()
			loop.append(poly[0])
			draw_polyline(loop, Color(PlanStyle.ENTRY_POINT, 0.95), 3.0)
		# 이름은 남쪽 면 가운데 (긴 건물에서도 마우스 가까이)
		var s: PackedVector2Array = _band_polys(float(band[1]), float(band[2]))[0]
		var at := (s[0] + s[1] + s[2] + s[3]) * 0.25
		var text := hover_text if hover_text != "" else "%s — 클릭: 내부 보기" % sim.building.floor_name(hover_floor)
		var font := PlanStyle.font()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		# 벽 위에서도 읽히게 어두운 바탕
		draw_rect(Rect2(at + Vector2(-w * 0.5 - 8.0, -14.0), Vector2(w + 16.0, 26.0)), Color(0.04, 0.07, 0.12, 0.8))
		draw_string(font, at + Vector2(-w * 0.5, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


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
	# 백드래프트 징후 ③ 창에 짙은 연기 응축물(검은색 액체)이 흘러내린 얼룩 (화재1 p.44, 연기 읽기 2단계 2026-11-24) — 닫힌 창.
	# 외관의 창은 밖에서 늘 보인다 (문틈 연기와 같게 — 2026-11-24 검사)
	if not o.broken and not o.is_open and sim.hazards != null and sim.hazards.backdraft_sign(sim.fire.comps[o.room_a]):
		var st := SmokeLook.style()
		var sc: Array = st.get("bd_stain_color", [0.08, 0.06, 0.04, 0.6])
		var stain := Color(float(sc[0]), float(sc[1]), float(sc[2]), float(sc[3]))
		draw_colored_polygon(PackedVector2Array([_face_point(w.face, a, g1), _face_point(w.face, b, g1), _face_point(w.face, b, g0),
			_face_point(w.face, a, g0)]), stain)
		for k in 3:
			var x := lerpf(a, b, 0.25 + 0.25 * k)
			draw_line(_face_point(w.face, x, g1), _face_point(w.face, x + 0.04, lerpf(g1, g0, 0.55 + 0.12 * k)),
				Color(stain.darkened(0.5), minf(1.0, stain.a + 0.25)), 2.0)
	# 화염 분출: 불난 방(확인한 불)의 열린·깨진 창 위로 불꽃이 넘실댄다
	if _fire_rooms.has(o.room_a) and (o.broken or o.is_open):
		var base := _face_point(w.face, mid, g1)
		var half := (_face_point(w.face, b, g1) - _face_point(w.face, a, g1)).length() * 0.5
		var flick := 0.8 + 0.25 * sin(t * 9.0 + o.index * 1.7)
		var tip := _face_point(w.face, mid, g1 + fh * 0.9 * flick) + Vector2(sin(t * 5.0 + o.index) * 4.0, 0)
		if not _draw_window_fire(o.index, base, half, (base - tip).length(), t):
			_fill(_flame_shape(base, half, tip), Color(1.0, 0.45, 0.1, 0.9))
			_fill(_flame_shape(base, half * 0.5, base.lerp(tip, 0.6)), Color(1.0, 0.85, 0.3, 0.95))
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
		if FxArt.spill != null:
			for sp in smoke_spills(sim, int(row[0])):
				if not bool(sp[4]):
					_draw_spill(sp, float(row[1]), float(row[2]), int(sp[5]))
			# 백드래프트 징후: 바깥으로 난 닫힌 문·창 틈 (밖에서 늘 보인다)
			for bs in backdraft_seeps(sim, int(row[0])):
				if bool(bs[6]):
					_draw_backdraft_seep(bs, float(row[1]))
			continue
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
	# 불은 칸마다가 아니라 묶은 불(채)의 자리에만 (FireDraw, 2026-11-22)
	var b := sim.building
	_fire_layout()
	for ci: int in _fire_at:
		_add_object(by_diag, ci % b.width, ci / b.width)
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
	if _glow == null:
		_glow = FireGlowLayer.new()
		add_child(_glow)
		# 연기층 질감을 반복해 입힌다 (P15-FX)
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# 아래층(보이기만 하는 층)은 시뮬레이션 틱이 바뀔 때만, 두 아래층이 틱을 번갈아 다시 그린다 (R17 성능).
	# 지금 층은 대원 움직임·불꽃이 부드럽게 보이도록 매 프레임
	if depth > 0 and sim != null and ghost_mode != 5:
		# 다른 층 사람 테두리는 매 프레임 (걷는 동작·위치가 끊기지 않게, 2026-11-12) — 사람 몇 명뿐이라 가볍다
		if (ghost or people_outline) and _ghost_units:
			_ghost_units.queue_redraw()
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
	if not _smoky.is_empty() or not _smoke_hulls.is_empty():
		_smoky.clear()
		_smoke_hulls.clear()
		_smoke_outline.queue_redraw()
	if ghost_mode == 4:
		_draw_live_only()
		return
	# 바깥 땅 겹 (ghost_mode 5): 아래로 보이는 땅 층(흑백 바탕) 위에 차량·바깥 사람만 원래 색으로
	if ghost_mode == 5:
		_draw_outdoor_people()
		return
	if people_outline and _ghost_units:
		_ghost_units.queue_redraw()
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
	_draw_ground_shadows()
	if not skip_live:
		_draw_vehicle_shadows(alpha)
	_draw_slab_edges()
	if stub_below and depth > 0 and not _outside():
		_draw_stub_below()
	if not _outside() and depth == 0:
		_draw_room_labels()
	if level == _first_level:
		if depth == 0:
			_draw_face_labels()
		_draw_staging()
		if depth == 0 and not skip_live:
			ZoneDraw.draw_ground(self, sim.zones, func(p: Vector2) -> Vector2: return proj.to_screen(p, 0.03), 14)
	if not skip_live:
		_draw_route_lines(alpha)
	# 대원·차량을 대각선(x + y) 깊이별로 모아 벽·가구와 함께 뒤에서 앞으로 그린다
	var buckets := {}
	for ff in sim.units.firefighters:
		if ff.level == level and not ff.aboard:
			_bucket_person(buckets, _shown_pos(ff, alpha), ff, alpha)
	if level == _first_level:
		for v in sim.units.vehicles:
			if not v.away:
				_bucket(buckets, v.prev_pos.lerp(v.pos, alpha), v)
	for victim in sim.rescue.victims:
		if victim.discovered and victim.level == level:
			_bucket(buckets, _victim_shown_pos(victim, alpha), victim)
	var commander := sim.command.commander
	if commander.level == level and not commander.aboard:
		_bucket_person(buckets, UnitsView.display_pos(commander, alpha), commander, alpha)
	if level == _first_level:
		for w in sim.command.survey.witnesses:
			if w.present(sim.clock.tick):
				_bucket(buckets, w.pos, w)
		# 운전원 (소화전 점령·급수 연결 중에만 차에서 내려 있다)
		for v in sim.units.vehicles:
			var dl := _driver_layout(v)
			for who: String in ["driver", "other"]:
				if dl.has(who):
					_bucket(buckets, dl[who].pos, {"driver": v.id, "who": who})
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
				if skip_live and not item[1] is Witness:
					continue
				if item[1] is Dictionary:
					if not skip_live:
						_draw_driver(item[1])
				elif item[1] == commander:
					_draw_commander(alpha)
				elif item[1] is Firefighter:
					if not skip_live:
						_draw_unit(item[1], alpha)
				elif item[1] is Victim:
					if not skip_live:
						_draw_victim(item[1])
				elif item[1] is Witness:
					_draw_witness(item[1])
				else:
					_draw_vehicle(item[1], alpha)
	if _outside():
		# 외관이 실내(연기층 포함)를 가린다. 연기는 창·문으로 나오는 것만
		_draw_shell()
	elif not thermal and not skip_live:
		_draw_smoke()
	if not skip_live:
		_draw_blasts()
	if not _outside():
		_draw_open_walls()
	if _glow:
		_glow.z_as_relative = true
		_glow.z_index = 0
		_glow.spots = _glow_spots if not thermal and not _outside() else []
		_glow.queue_redraw()
		_glow_spots = []
	# 물줄기는 색 겹(연기 위)에서 그린다 — 바탕에서 그리면 흑백이 되고 연기에 묻힌다 (2026-11-12)
	if not skip_live:
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
	elif upper_level >= 0 and depth > 0 and depth < ABOVE_DEPTH and not stack.staggered():
		# (제자리 쌓기만 — 층 분리에서는 층끼리 가리지 않는다) 아래로 보이는 층만: 위층 바닥에 가려지는 칸을 뺀다. 지금 층(depth 0)은 위층이 턱·점선뿐이라 다 그린다
		# (지금 층도 계단 디딤판 때문에 upper_level 을 가진다, 2026-11-12)
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


## 차량(긴 상자) 옆에 선 사람의 그리기 순서 보정 (2026-11-15, 하차 동작): 차 가운데의 깊이(x + y)만으로 견주면
## 운전석 문 옆처럼 차 앞쪽·뒤편에 선 사람이 차 위에 그려진다. 차체에서 가장 가까운 점을 기준으로 뒤(북서)·앞(남동)을 가려,
## 깊이 순서가 그와 어긋나면 [차 가운데 자리, -1(차보다 먼저 그린다) 또는 +1(나중에)]을 돌려준다. 어긋나지 않으면 빈 배열
func _vehicle_side(p: Vector2, alpha: float) -> Array:
	if level != _first_level:
		return []
	for v in sim.units.vehicles:
		if v.away:
			continue
		var vp := v.prev_pos.lerp(v.pos, alpha)
		if p.distance_to(vp) > v.length_cells * 0.5 + 2.0:
			continue
		var n := p - v.closest_body_point(p, vp)
		var side := n.x + n.y
		var ahead := p.x + p.y - (vp.x + vp.y)
		if side < -0.01 and ahead >= 0.0:
			return [vp, -1.0]
		if side > 0.01 and ahead <= 0.0:
			return [vp, 1.0]
	return []


## 사람의 그리기 깊이 (x + y) — 차량 옆이면 차의 앞·뒤에 맞춘다
func _person_depth(p: Vector2, alpha: float) -> float:
	var fix := _vehicle_side(p, alpha)
	if fix.is_empty():
		return p.x + p.y
	var vp: Vector2 = fix[0]
	return vp.x + vp.y + 0.01 * float(fix[1])


## 사람을 깊이 묶음에 넣는다 — 차량 옆이면 그 차와 같은 묶음의 바로 앞·뒤 순서로
func _bucket_person(buckets: Dictionary, p: Vector2, obj: Object, alpha: float) -> void:
	var fix := _vehicle_side(p, alpha)
	if fix.is_empty():
		_bucket(buckets, p, obj)
		return
	if not _mask_now.is_empty() and sim.building.in_bounds(floori(p.x), floori(p.y)) \
			and _mask_now[floori(p.y) * sim.building.width + floori(p.x)] == 0:
		return
	var vp: Vector2 = fix[0]
	var d := floori(vp.x) + floori(vp.y)
	if not buckets.has(d):
		buckets[d] = []
	buckets[d].append([vp.x + vp.y + 0.01 * float(fix[1]), obj])


func _bucket(buckets: Dictionary, p: Vector2, obj: Variant) -> void:
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
	var key := [sim.clock.tick, level, thermal, sim.perception.enabled, sim.plan.known, lower_level, _outside()]
	if key == _ground_key:
		return
	_ground_key = key
	# 내부 화면(층 분리): 바깥 땅은 어둡게 — 건물 안에 집중 (2026-11-14). 외부 화면에서는 그대로
	var outdoor_darken := stack.params.split_outdoor_darken if stack.staggered() and not _outside() else 0.0
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
		if structure:
			@warning_ignore("integer_division")
			var wk := stack.wall_kind(level, k % b.width, k / b.width, _outside())
			if wk == FloorStack.Wall.HALF or wk == FloorStack.Wall.OPEN:
				structure = false
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
			if outdoor and outdoor_darken > 0.0:
				color = color.darkened(outdoor_darken)
			# 벽 바닥도 모르는 곳이면 덮는다 (외벽은 밖에서 보이므로 그대로)
			@warning_ignore("integer_division")
			var hidden_wall := structure and p.enabled and not sim.plan.structure_seen(level, k % b.width, k / b.width)
			# 2026-11-12: 구조는 늘 보인다. 본 적 있지만 지금 안 보이는 칸은 색만 조금 빼고,
			# 본 적 없는 칸은 색을 더 빼고 어둡게 (안의 것은 _draw_cell_objects가 숨긴다)
			if not structure and not vis:
				var gray := color.get_luminance()
				var dark := MEMORY_DARKEN if seen else UNKNOWN_DARKEN
				color = color.lerp(Color(gray, gray, gray), MEMORY_DESATURATE if seen else UNKNOWN_DESATURATE).darkened(dark)
				fog_of[k] = dark
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


# --- 미리 그려 넣는 그림자·음영 (입체감 1단계, 2026-11-22) ---
# 실시간 광원·그림자가 아니다: 바닥 바로 위에 반투명한 어두운 도형을 그린다 (ShadowDraw, data/ui/shadow_style.json).
# 호스·구역·이름·불·연기·선택 고리보다 먼저 그려 그 아래에 깔린다. 열화상 화면에는 그리지 않는다.

## 건물 땅 그림자·벽 아래 띠(한 번 만들어 둔 묶음)와 가구 그림자
func _draw_ground_shadows() -> void:
	if thermal or not ShadowDraw.on():
		return
	var key := "%d:%d" % [level, 1 if _outside() else 0]
	if not _shade_static.has(key):
		_shade_static[key] = _build_static_shade()
	var s: Dictionary = _shade_static[key]
	if not (s.indices as PackedInt32Array).is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), s.indices, s.points, s.colors)
	_draw_furniture_shadows()


## 사각형 하나를 묶음에 넣는다 (칸 좌표 4점, 점마다 진하기)
func _shade_quad(s: Dictionary, quad: PackedVector2Array, col: Color, alphas: Array) -> void:
	var points: PackedVector2Array = s.points
	var colors: PackedColorArray = s.colors
	var indices: PackedInt32Array = s.indices
	var at := points.size()
	for k in 4:
		points.append(proj.to_screen(quad[k], 0.0))
		colors.append(Color(col, col.a * float(alphas[k])))
	indices.append_array([at, at + 1, at + 2, at, at + 2, at + 3])
	s.points = points
	s.colors = colors
	s.indices = indices


## 움직이지 않는 음영: 건물이 땅에 드리우는 그림자(지상층)와 벽 아래 어두운 띠
func _build_static_shade() -> Dictionary:
	var s := {"points": PackedVector2Array(), "colors": PackedColorArray(), "indices": PackedInt32Array()}
	var b := sim.building
	var ext := _outside()
	var cast := ShadowDraw.cast_dir(proj)
	# 1) 건물 땅 그림자: 불난 건물(외부 보기는 외관 높이, 내부 화면은 잘린 벽 높이)과 이웃 건물(1층 높이)
	if level == _first_level:
		var sun := ShadowDraw.color("building_alpha", ShadowDraw.sun_scale(_night))
		var cut_m := ShadowDraw.num("interior_wall_m", CEILING_M)
		var masses: Array = [[Rect2(_shell_fp), _shell_top if ext else cut_m]]
		for i in range(1, b.structures.size()):
			masses.append([Rect2(b.structures[i].rect), cut_m])
		for m: Array in masses:
			var off := ShadowDraw.cast_offset(proj, float(m[1]), b.cell_size_m, "building_max_m")
			for quad in ShadowDraw.sweep_quads(ShadowDraw.rect_points(m[0]), off):
				_shade_quad(s, quad, sun, [1.0, 1.0, 1.0, 1.0])
	# 2) 벽 아래 띠: 벽 칸마다 그려지는 모양(칸 가득한 벽 / 얇은 실내 벽의 가로 막대·세로 팔)의 옆면 아래로
	var shadow_w := ShadowDraw.num("ao_shadow_m") / b.cell_size_m
	var lit_w := ShadowDraw.num("ao_lit_m") / b.cell_size_m
	var ao := ShadowDraw.num("ao_alpha")
	var lit_ratio := ShadowDraw.num("ao_lit_ratio")
	var t := clampf(stack.params.inner_wall_thick, 0.05, 1.0) * 0.5
	var bands: Array[Dictionary] = []
	for y in b.height:
		for x in b.width:
			var c := b.cell(level, x, y)
			if c != BuildingData.Cell.WALL and c != BuildingData.Cell.WINDOW:
				continue
			var kind := stack.wall_kind(level, x, y, ext)
			if kind == FloorStack.Wall.OPEN or kind == FloorStack.Wall.HIDDEN:
				continue
			if kind == FloorStack.Wall.HALF and c == BuildingData.Cell.WALL:
				# 얇은 실내 벽 (_thin_wall 과 같은 모양). 외부 보기에서는 외관에 가려 보이지 않는다
				if ext:
					continue
				var has := func(dx: int, dy: int) -> bool: return b.in_bounds(x + dx, y + dy) and b.cell(level, x + dx, y + dy) in FloorStack.WALL_CELLS
				var w: bool = has.call(-1, 0)
				var e: bool = has.call(1, 0)
				var n: bool = has.call(0, -1)
				var sth: bool = has.call(0, 1)
				var cx := x + 0.5
				var cy := y + 0.5
				var ns := ShadowDraw.NORTH | ShadowDraw.SOUTH
				var we := ShadowDraw.WEST | ShadowDraw.EAST
				if w:
					bands.append_array(ShadowDraw.box_bands(Rect2(x, cy - t, 0.5 - t, 2.0 * t), ns, cast, shadow_w, lit_w, ao, lit_ratio))
				if e:
					bands.append_array(ShadowDraw.box_bands(Rect2(cx + t, cy - t, 0.5 - t, 2.0 * t), ns, cast, shadow_w, lit_w, ao, lit_ratio))
				if n:
					bands.append_array(ShadowDraw.box_bands(Rect2(cx - t, y, 2.0 * t, 0.5 - t), we, cast, shadow_w, lit_w, ao, lit_ratio))
				if sth:
					bands.append_array(ShadowDraw.box_bands(Rect2(cx - t, cy + t, 2.0 * t, 0.5 - t), we, cast, shadow_w, lit_w, ao, lit_ratio))
				var mid := (0 if w else ShadowDraw.WEST) | (0 if e else ShadowDraw.EAST) | (0 if n else ShadowDraw.NORTH) | (0 if sth else ShadowDraw.SOUTH)
				bands.append_array(ShadowDraw.box_bands(Rect2(cx - t, cy - t, 2.0 * t, 2.0 * t), mid, cast, shadow_w, lit_w, ao, lit_ratio))
				continue
			var sides := 0
			for k in 4:
				var nb := Vector2i(x, y) + Vector2i(ShadowDraw.NORMALS[k])
				if _shade_ground_at(nb.x, nb.y, ext):
					sides |= ShadowDraw.SIDES[k]
			if sides != 0:
				bands.append_array(ShadowDraw.box_bands(Rect2(x, y, 1, 1), sides, cast, shadow_w, lit_w, ao, lit_ratio))
	var black := ShadowDraw.color("ao_alpha")
	black.a = 1.0
	for d in ShadowDraw.merge_bands(bands):
		var a := float(d.alpha)
		if d.has("fan"):
			_shade_quad(s, d.fan, black, [a, 0.0, 0.0, 0.0])
		else:
			_shade_quad(s, ShadowDraw.band_quad(d), black, [a, a, 0.0, 0.0])
	return s


## 벽 옆 칸에 띠를 그릴 바닥이 보이는가 (외부 보기에서는 바깥 땅만 — 실내는 외관에 가린다)
func _shade_ground_at(x: int, y: int, ext: bool) -> bool:
	var b := sim.building
	if not b.in_bounds(x, y):
		return false
	var c := b.cell(level, x, y)
	if c == BuildingData.Cell.VOID:
		return false
	if ext:
		return c in BuildingData.OUTDOOR
	if c in FloorStack.WALL_CELLS:
		# 얇은 실내 벽·없앤 앞벽 칸은 바닥이 보인다
		var kind := stack.wall_kind(level, x, y, false)
		return kind == FloorStack.Wall.HALF or kind == FloorStack.Wall.OPEN
	return true


## 가구 그림자: 확인한 방의 타지 않은 가구만 (모르는 방의 가구를 그림자로 알려 주지 않는다 — 기획안 9-1)
func _draw_furniture_shadows() -> void:
	var b := sim.building
	if not _furn_shadow.has(level):
		var list: Array[Dictionary] = []
		for item in b.furniture(level):
			var r: Rect2i = item.rect
			var h: float = FURNITURE_HEIGHTS.get(item.name, DEFAULT_FURNITURE_M)
			var off := ShadowDraw.cast_offset(proj, h, b.cell_size_m, "furniture_max_m")
			var pts := PackedVector2Array()
			for quad in ShadowDraw.sweep_quads(ShadowDraw.rect_points(Rect2(r)), off):
				for p in quad:
					pts.append(proj.to_screen(p, 0.0))
			list.append({"x": r.end.x - 1, "y": r.end.y - 1, "pts": pts})
		_furn_shadow[level] = list
	var key := [sim.clock.tick, level, sim.perception.enabled, _outside()]
	if key != _furn_shadow_key:
		_furn_shadow_key = key
		_furn_shadow_pts = PackedVector2Array()
		_furn_shadow_idx = PackedInt32Array()
		for f: Dictionary in _furn_shadow[level]:
			var x: int = f.x
			var y: int = f.y
			if not _mask_now.is_empty() and _mask_now[y * b.width + x] == 0:
				continue
			if not (b.cell(level, x, y) in BuildingData.OUTDOOR or sim.plan.structure_seen(level, x, y)) or _cell_burnt(x, y):
				continue
			var pts: PackedVector2Array = f.pts
			@warning_ignore("integer_division")
			for q in pts.size() / 4:
				var at := _furn_shadow_pts.size()
				_furn_shadow_pts.append_array(pts.slice(q * 4, q * 4 + 4))
				_furn_shadow_idx.append_array([at, at + 1, at + 2, at, at + 2, at + 3])
		_furn_shadow_cols.resize(_furn_shadow_pts.size())
		_furn_shadow_cols.fill(ShadowDraw.color("furniture_alpha"))
	if not _furn_shadow_idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _furn_shadow_idx, _furn_shadow_pts, _furn_shadow_cols)


## 차량이 땅에 드리우는 그림자 (지상층). 차량·사람·호스보다 먼저 그린다
func _draw_vehicle_shadows(alpha: float) -> void:
	if thermal or level != _first_level or not ShadowDraw.on():
		return
	var col := ShadowDraw.color("vehicle_alpha", ShadowDraw.sun_scale(_night))
	for v in sim.units.vehicles:
		if v.away:
			continue
		var center := v.prev_pos.lerp(v.pos, alpha)
		if not _mask_now.is_empty() and sim.building.in_bounds(floori(center.x), floori(center.y)) \
				and _mask_now[floori(center.y) * sim.building.width + floori(center.x)] == 0:
			continue
		var off := ShadowDraw.cast_offset(proj, minf(v.height_m, VEHICLE_CUT_M), sim.building.cell_size_m)
		ShadowDraw.fill_convex(self, _lift(ShadowDraw.sweep_hull(v.footprint(center), off), 0.0), col)


## 사람 발밑 그림자 (타원). 그림자 설정이 켜져 있으면 가장자리가 옅어지는 타원, 꺼져 있거나 열화상이면 예전의 또렷한 타원
func _contact_shadow(feet: Vector2, rx: float, ry: float, plain_alpha: float) -> void:
	if thermal or not ShadowDraw.on():
		draw_colored_polygon(_ellipse(feet, rx, ry), Color(0, 0, 0, plain_alpha))
		return
	var k := ShadowDraw.num("contact_scale", 1.0)
	ShadowDraw.soft_ellipse(self, feet, rx * k, ry * GROUND_RATIO * k, ShadowDraw.color("contact_alpha"))


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
	# 2026-11-12 사용자 결정: 구조(벽·문·창)는 늘 그린다. 본 적 없는 칸은 안의 것(가구·불꽃 등)만 숨긴다
	var contents_seen := t in BuildingData.OUTDOOR or sim.plan.structure_seen(level, x, y)
	match t:
		BuildingData.Cell.WALL:
			var wh := _wall_height(x, y)
			match stack.wall_kind(level, x, y, _outside()):
				FloorStack.Wall.GLASS:
					_wall_piece(x, y, 0.0, wh, _structure_color(skin.color("wall")), stack.params.front_wall_alpha, stack.params.front_wall_alpha, stack.params.wall_cap_alpha)
				FloorStack.Wall.OPEN:
					pass  # 인형집: 앞 바깥벽은 그리지 않는다 (문·창은 따로)
				FloorStack.Wall.HALF:
					# 실내 벽: 천장까지, 아래 진하게·위로 갈수록 옅게 + 흰 윗면 테두리, 두께는 바깥벽의 1/3 (2026-11-12 사용자 결정)
					_inner_wall(x, y, 0.0, wh, _structure_color(skin.color("wall")))
				_:
					_block(x, y, 0.0, wh, _structure_color(skin.color("wall")), _cut_top(wh))
		BuildingData.Cell.WINDOW:
			_draw_window(x, y)
		BuildingData.Cell.DOOR:
			_draw_door(x, y)
	if not contents_seen:
		return
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
	if not skip_live:
		_draw_fires_at(x, y)


## 문: 닫힘(블록) / 열림(통로) / 잠김(표시) / 파괴(잔해). 작업 중이면 진행 막대.
func _draw_door(x: int, y: int) -> void:
	var o: Opening = _opening_of.get(Vector3i(x, y, level))
	if o == null:
		return
	var top := proj.to_screen(Vector2(x + 0.5, y + 0.5), minf(DOOR_TOP_M, _wall_height(x, y)) + 0.3)
	var first := Vector2i(x, y) == o.cells[0]
	# 실내 문 위(인방~천장)는 벽으로 채운다 (열려 있어도)
	if stack.wall_kind(level, x, y, _outside()) == FloorStack.Wall.HALF and _wall_height(x, y) > DOOR_TOP_M:
		_inner_wall(x, y, DOOR_TOP_M, _wall_height(x, y), _structure_color(skin.color("wall")))
	if not o.is_open:
		var dc := _structure_color(PlanStyle.CELL_COLORS[BuildingData.Cell.DOOR])
		if stack.wall_kind(level, x, y, _outside()) == FloorStack.Wall.HALF:
			_wall_uv = Vector2(1000.0 + x + y + 1.0, 0.0)
			_thin_wall(x, y, 0.0, minf(DOOR_TOP_M, _wall_height(x, y)), dc, Color(0, 0, 0, 0))
			_wall_uv = Vector2.ZERO
		else:
			_block(x, y, 0.0, minf(DOOR_TOP_M, _wall_height(x, y)), dc)
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
	# 인형집: 앞 바깥벽의 창은 바닥 높이 창틀 + 유리 선으로 낮게 (깨서 배연·진입구 개척 — 누를 수 있게)
	if stack.wall_kind(level, x, y, _outside()) == FloorStack.Wall.OPEN:
		h = stack.params.wall_cut_m
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


## 지금 층의 불(채) 목록 (FireDraw.bodies — 2026-11-22): 가까운 타는 칸을 묶어 열방출률에 맞는 크기의 불꽃 하나로.
## 정보 규칙은 예전과 같다 — 보이는 칸은 지금 타는 대로, 보이지 않지만 마지막으로 봤을 때 타던 칸은 흐리게.
## 틱·층이 바뀔 때만 다시 만든다. _fire_at: 칸 번호(y × 폭 + x) → 그 칸에서 그릴 불들 (깊이 순서에 끼워 그린다)
@warning_ignore("integer_division")
func _fire_layout() -> Array[Dictionary]:
	var key := [sim.clock.tick, level, sim.perception.enabled]
	if key == _fire_key:
		return _fire_bodies
	_fire_key = key
	var b := sim.building
	var grid := sim.fire.grid
	var p := sim.perception
	var remembered := FireDraw.num("remembered_intensity", 0.5)
	var cells: Array = []
	var start := grid.index(level, 0, 0)
	for k in b.width * b.height:
		var i := start + k
		var burning := grid.state[i] == FuelGrid.State.BURNING
		if not burning and p.seen_burning[i] != 1:
			continue
		var x := k % b.width
		var y := k / b.width
		var kw := 0.0
		var faded := false
		if p.is_visible(level, x, y):
			if not burning:
				continue
			kw = grid.hrr[i]
		elif p.is_seen(level, x, y) and p.seen_burning[i] == 1:
			faded = true
			kw = grid.peak_kw(i) * remembered
		else:
			continue
		var comp := sim.fire.compartment_at(level, x, y)
		# 플래시오버 뒤 최성기까지는 방 전체가 탄다 (화염이 천장까지 찬다)
		var full := comp != null and comp.flashed and (comp.stage == Compartment.Stage.FLASHOVER or comp.stage == Compartment.Stage.FULLY_DEVELOPED)
		cells.append({"x": x, "y": y, "kw": kw, "room": comp.index if comp else -1, "base": _furniture_height(x, y), "faded": faded, "full": full and not faded})
	_fire_bodies = FireDraw.bodies(cells, b.cell_size_m, CEILING_M)
	_fire_at = {}
	for f in _fire_bodies:
		var at: Vector2 = f.pos
		var ci := clampi(floori(at.y), 0, b.height - 1) * b.width + clampi(floori(at.x), 0, b.width - 1)
		if not _fire_at.has(ci):
			_fire_at[ci] = []
		_fire_at[ci].append(f)
	return _fire_bodies


## 이 칸에 자리한 불들을 그린다 (물체 깊이 순서 안에서)
func _draw_fires_at(x: int, y: int) -> void:
	if thermal:
		return
	_fire_layout()
	var list: Array = _fire_at.get(y * sim.building.width + x, [])
	for f: Dictionary in list:
		_draw_fire_body(f)


## 불 한 채: 바닥의 주황빛 + 불빛 번짐 + 불꽃 그림 (크기는 화염 높이에 맞춘 s·m·l·xl).
## 열화상에서는 화염 모양 대신 바닥 온도 색으로만 보인다
func _draw_fire_body(f: Dictionary) -> void:
	if thermal:
		return
	var fade := FireDraw.num("remembered_fade", 0.4) if bool(f.faded) else 1.0
	var at: Vector2 = f.pos
	var base_m := float(f.base_m)
	var base := proj.to_screen(at, base_m)
	var h_px := float(f.height_m) * IsoProjection.PX_PER_M
	var w_px := float(f.width_m) * IsoProjection.PX_PER_M
	var key := int(f.seed)
	# 바닥에서 1m가 화면에서 차지하는 길이 (px)
	var ground := (proj.to_screen(Vector2(1, -1), 0.0) - proj.to_screen(Vector2.ZERO, 0.0)).length() / (sqrt(2.0) * sim.building.cell_size_m)
	if not bool(f.satellite):
		var rx := maxf(float(f.diameter_m) * 0.65, 0.3) * ground
		ShadowDraw.soft_ellipse(self, base, rx, rx * GROUND_RATIO, Color(1.0, 0.45, 0.1, FireDraw.num("ember_alpha", 0.4) * fade))
		if depth == 0 and fade >= 1.0:
			var glow_m := float(f.width_m) * FireDraw.num("glow_per_m", 1.7) + FireDraw.num("glow_base_m", 1.6)
			_glow_spots.append([base, glow_m * ground, clampf(float(f.height_m) / CEILING_M, 0.3, 1.0), key % 9973])
	if FxArt.draw_fire(self, str(f.kind), base, w_px, h_px, key, Color(1, 1, 1, fade)):
		return
	# 구운 불꽃 그림이 없으면 예전 불꽃(셰이더로 구운 것), 그것도 없으면 도형
	if FxArt.draw_flame(self, base, w_px, h_px, key, Color(1, 1, 1, fade)):
		return
	var half := w_px * 0.35
	_fill(_flame_shape(base, half, proj.to_screen(at, base_m + float(f.height_m))), Color(0.95, 0.3, 0.06, 0.9 * fade))
	_fill(_flame_shape(base, half * 0.55, proj.to_screen(at, base_m + float(f.height_m) * 0.6)), Color(1.0, 0.8, 0.3, 0.95 * fade))


func _draw_unit(ff: Firefighter, alpha: float) -> void:
	var p := _shown_pos(ff, alpha)
	var squad := sim.units.squads[ff.squad_id]
	var crew := sim.units.get_crew(ff.crew_id)
	var feet := proj.to_screen(p, 0.0)
	_contact_shadow(feet, 10, 5, 0.3)
	# 들려 가는 쓰러진 대원(2인 운반)은 그 높이에 그린다 — 그림자는 바닥에
	var carried := _ff_carry_layout(ff, alpha)
	if not carried.is_empty():
		feet = proj.to_screen(p, float(carried.victim_h))
	if crew.id in selection.selected:
		draw_polyline(_ellipse(feet, 13, 6.5, true), PlanStyle.SELECTION, 2.0)
		# 팀장은 이중 고리 — 다시 누르면 분대 편성 둥근 버튼이 뜨는 사람 (2026-11-17)
		if ff.officer:
			draw_polyline(_ellipse(feet, 18, 9, true), PlanStyle.SELECTION, 1.5)
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
	# 이름표: 나뉜 조는 사람마다 조 번호, 나누지 않은 분대는 말하는 사람(팀장) 위에만 분대 이름 (2026-11-16)
	if crew.solo:
		# 한 명 보내기로 나간 대원: 맡은 임무 (급수 지원·방재실 연락·장비 가져오기·복귀 중)
		draw_string(PlanStyle.font(), label + Vector2(-60, 0), sim.solo_label(crew.id), HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color("fde68a"))
	elif not sim.units.whole_squad(crew):
		draw_string(PlanStyle.font(), label + Vector2(-30, 0), str(crew.number) + _role_tag(crew), HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color.WHITE)
	elif ff == crew.speaker():
		draw_string(PlanStyle.font(), label + Vector2(-45, 0), squad.name + _role_tag(crew), HORIZONTAL_ALIGNMENT_CENTER, 90, 12, Color.WHITE)
	# 팀장(분대 지휘관): 머리 위 ★ (선착대장은 파란 헬멧 지휘관 캐릭터라 따로)
	if ff.officer:
		PlanStyle.draw_star(self, label + Vector2(0, -20), 7.0)
	# 할 일 없이 서 있는 분대: 앞사람 머리 위 '대기' (임무 완료 뒤 다음 지시를 기다림, 2026-11-17)
	if ff == crew.leader and not crew.solo and not sim.ems.is_ems_crew(crew.id) and sim.squad_idle(crew.id):
		draw_string(PlanStyle.font(), label + Vector2(-30, -32), "대기", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, IDLE_TAG)
	_draw_air_bar(label + Vector2(0, 4), ff)


## 구운 그림으로 대원 그리기 (P15). 그림이 없거나 열화상이면 false → 도형
func _draw_unit_sprite(ff: Firefighter, crew: Crew, squad: Squad, feet: Vector2) -> bool:
	if thermal:
		return false
	var art := SpriteArt.crew_set(squad.type)
	if art == null:
		return false
	var pose := _unit_pose(ff, crew, art)
	# 헬멧 색은 출동대 종류로만 (진압 검정·구조 주황·구급 흰색). RIT·안전담당은 임무라 이름표로 (_role_tag)
	var tint := Color.WHITE.lerp(Color(1.0, 0.45, 0.35), clampf(ff.heat_stress, 0.0, 1.0) * 0.6)
	if not art.draw(self, pose[0], pose[1], pose[2], feet, tint, SpriteArt.helmet_color(squad.type)):
		return false
	return true


## 대원 그림 자세 [동작, 방향, 장] — 실제 그림과 테두리(다른 층·연기 속)가 같은 것을 쓴다 (2026-11-12).
## 걷는 방향·방수 방향을 이 노드의 _facing 에 기억한다
func _unit_pose(ff: Firefighter, crew: Crew, art: SpriteArt.SpriteSet) -> Array:
	var delta := ff.pos - ff.prev_pos
	var moving := ff.level == ff.prev_level and delta.length_squared() > 0.000001
	var anim := "idle"
	var task := sim.rescue.task_of_crew(crew.id)
	var hose := sim.water.held_hose(crew.id)
	var door_task := sim.doors.task_of_crew(crew.id)
	if moving:
		_facing[ff.id] = SpriteArt.dir8(delta)
	# 방향을 따로 정하는 동작 (운반): 0 이상이면 _facing 대신 쓴다
	var dir := -1
	# 진행 정도로 장을 고르는 동작 (문 개방): 0 이상이면 그 장
	var fixed_frame := -1
	if ff.incapacitated:
		anim = "down"
		# 들려·끌려 가는 쓰러진 대원: 엎드린 그림은 머리가 그림 방향 — 2인 운반은 머리가 뒷사람 쪽, 끌기는 끄는 사람 쪽
		var held := _ff_carry_layout(ff, 0.0)
		if not held.is_empty():
			dir = posmod(int(held.k) + 4, 8) if str(held.mode) == "lift" else int(held.k)
	elif not _helper_pose(ff).is_empty():
		# 소화전 급수를 둘이서 (2026-11-16 사용자): 차 옆에 남은 대원이 굴러온 호스 끝을 차 급수구에 결합한다
		var hp := _helper_pose(ff)
		anim = str(hp.anim)
		dir = int(hp.k)
		moving = false
		fixed_frame = int(hp.frame)
	elif not _ems_carry_layout(crew, art).is_empty():
		# 들것 이송 (A10, 2026-11-15 사용자가 블렌더에서 확인): 바깥은 주 들것(조장이 머리 쪽에서 밀고 짝은 발 쪽 옆에서 잡음),
		# 건물 안은 분리형 들것(둘이 앞뒤 끝을 쥐고 듦). 자리는 구울 때 적은 값 (조장 기준)
		var el := _ems_carry_layout(crew, art)
		anim = str(el.anims.get(ff.id, "cot_a"))
		dir = int(el.k)
	elif not _aid_layout(crew, art).is_empty():
		# 응급처치 (A9, 2026-11-15 사용자가 블렌더에서 확인): 조장은 환자 머리 옆에서 산소마스크·기도, 짝은 팔 옆에서 맥박.
		# 둘 다 두 무릎을 꿇고 앉아 숙인다. 자리는 구울 때 적은 값 (환자 가운데 기준)
		var al := _aid_layout(crew, art)
		anim = str(al.anims.get(ff.id, "aid_a"))
		dir = int(al.k)
		moving = false
	elif task is RescueSystem.CarryTask and task.carrying:
		# 운반 (2026-11-15, 구조 교재 제4편 제2장 구출 및 운반): 선 자세로 갈 수 있으면 2인 운반(사지운반법 — 조장이 앞에서 다리,
		# 짝이 뒤에서 겨드랑이), 연기층 아래 낮은 자세이거나 혼자면 1인 운반(구조대상자 끌기 — 조장이 옷깃을 잡고 뒷걸음, 짝은 앞에서 길을 살핀다)
		var lay := _carry_layout(crew, 0.0)
		var k := int(lay.get("k", _facing.get(crew.leader.id, 1)))
		moving = crew.leader.level == crew.leader.prev_level and (crew.leader.pos - crew.leader.prev_pos).length_squared() > 0.000001
		if ff != crew.leader and ff != crew.mate():
			# 분대의 나머지 조원은 옆에서 같이 걷는다 (드는 사람은 선두와 그 짝 둘)
			anim = ("crouch_walk" if ff.crouched else "walk") if moving else ("crouch_walk" if ff.crouched else "idle")
			dir = k
		elif str(lay.get("mode", "")) == "lift" and art.frames("lift_f") > 0:
			anim = "lift_f" if ff == crew.leader else "lift_b"
			dir = k
		elif art.frames("drag") > 0:
			anim = "drag" if ff == crew.leader else "crouch_walk"
			dir = posmod(k + 4, 8) if ff == crew.leader else k
		else:
			# 운반 그림이 없는 묶음(예전 그림): 들고 걷기, 그것도 없으면 걷기
			anim = "carry" if art.frames("carry") > 0 else "walk"
	elif _overhaul_layout(crew, art).get("anims", {}).has(ff.id):
		# 잔불 정리 (B3, 2026-11-15 사용자가 블렌더에서 확인): 조장은 갈고리로 천장을 뜯어 내리고, 짝은 그 속을 관창으로 겨눈다
		var ol := _overhaul_layout(crew, art)
		anim = str(ol.anims.get(ff.id, "ovh_a"))
		dir = int(ol.k)
		moving = false
	elif _window_breaker(crew, art) == ff.id:
		# 창 파괴 (B2, 2026-11-15 사용자가 블렌더에서 확인): 창 옆 벽에 붙어 만능도끼 곡괭이 끝으로 창 위쪽을 옆으로 차례로 깬다
		var wl := _window_layout(crew, art)
		anim = "window_break"
		dir = int(wl.k)
		moving = false
	elif _door_opener(crew, art) == ff.id:
		# 문 확인 후 개방 (B1, 2026-11-15 사용자가 블렌더에서 확인): 문 옆 벽(손잡이 쪽)에 붙어 손등으로 문 위·가운데·아래 온도를
		# 짚고(확인하는 동안), 낮은 자세로 손잡이를 잡고 천천히 연다(여는 동안 — 진행 정도로 장을 고른다)
		var dl := _door_check_layout(crew, art)
		anim = str(dl.anim)
		dir = int(dl.k)
		moving = false
		fixed_frame = int(dl.frame)
	elif door_task != null and _forcing(door_task, ff) and art.frames("force_a") > 0 and _force_layout(door_task, crew, art).anims.has(ff.id):
		# 잠긴 문 개방 (A1, 2026-11-15 사용자가 블렌더에서 확인): 두 대원이 문틈 양쪽에 서서 빠루 끝을 문틈에 넣고
		# 몸은 그대로, 두 손으로 번갈아 젖힌다. 조장 = force_a, 짝 = force_b. 서는 자리는 _force_layout
		var lay := _force_layout(door_task, crew, art)
		anim = str(lay.anims.get(ff.id, "force_a"))
		dir = int(lay.k)
		moving = false
	elif _spray_layout(crew, art).get("anims", {}).has(ff.id):
		# 방수 (A4, 2026-11-15 사용자가 블렌더에서 확인): 관창수(조장)는 두 손으로 관창을 들고 앞굽이,
		# 관창보조는 그 뒤에서 호스를 겨드랑이에 끼고 버틴다 (2인 = spray_h, 분대 = spray_h1·h2). 물이 찬 호스는 일직선
		var sl := _spray_layout(crew, art)
		anim = str(sl.anims.get(ff.id, "spray_n"))
		dir = int(sl.ks.get(ff.id, sl.k))
		# 꺾인 곳의 3번은 호스를 정리하며 오간다 (_spray_tidy) — 걷는 동안만 걷는 그림이 움직인다
		moving = bool(sl.get("walk", {}).get(ff.id, false))
		if anim == "crouch_walk" and not moving:
			fixed_frame = 0
	elif hose and ff == crew.leader and int(_door_ready_layout(crew, art).get("id", -1)) == ff.id:
		# 문 앞 방수태세 (E4): 다른 조원이 문을 확인·개방·파괴하는 동안 관창수는 문 옆에서 낮은 자세로 관창을 문에 겨눈다 (A5 그림의 첫 장)
		var rl := _door_ready_layout(crew, art)
		anim = "spray_ln"
		dir = int(rl.k)
		moving = false
		fixed_frame = 0
	elif hose and hose.fetch_until >= 0 and _hose_fetch_layout(crew, art).get("anims", {}).has(ff.id):
		# 호스 꺼내기 (E1): 차 후면을 보고 서서 접어 쌓은 호스를 당겨 꺼낸다
		var fl := _hose_fetch_layout(crew, art)
		anim = str(fl.anims.get(ff.id, "hose_fetch_a"))
		dir = int(fl.k)
		moving = false
	elif hose and not hose.charged and _hose_carry_layout(crew, art).get("anims", {}).has(ff.id):
		# 호스 끼고 걷기 (E2·A6·E3, 2026-11-21 사용자가 블렌더에서 확인): 물이 차기 전 — 1번·2번은 접은 호스 묶음을 겨드랑이에 끼고,
		# 3번은 낮은 자세로 깔린 호스를 정리하며 따라간다. 멈춰 서 있으면 첫 장으로 서 있다
		var hl := _hose_carry_layout(crew, art)
		anim = str(hl.anims.get(ff.id, "hose_carry_a"))
		dir = int(hl.ks.get(ff.id, hl.k))
		moving = bool(hl.moving)
		if not moving:
			fixed_frame = 0
	elif hose and hose.flowing and not hose.approaching and not moving and ff == crew.leader:
		# 관창은 조장(관창수) 한 사람만 든다 — 짝은 뒤에서 서 있는다 (2026-11-12)
		anim = "spray"
		_facing[ff.id] = SpriteArt.dir8(hose.aim - ff.pos)
	elif hose and hose.flowing and not hose.approaching and not moving:
		_facing[ff.id] = SpriteArt.dir8(hose.aim - ff.pos)
	elif task is RescueSystem.SearchTask and _search_layout(crew, art).get("anims", {}).has(ff.id):
		# 인명검색 이동 (A7, 2026-11-15 사용자가 블렌더에서 확인): 둘 다 낮은 자세로, 조장은 만능도끼로 앞바닥을 두드리며
		# 더듬고, 짝은 조장 공기호흡기 아래를 잡고 뒤따른다. 짝 자리는 구울 때 적은 값
		var sl := _search_layout(crew, art)
		anim = str(sl.anims.get(ff.id, "search_a"))
		dir = int(sl.ks.get(ff.id, sl.k))
	elif not _gas_layout(crew, art).is_empty() and ff == crew.leader:
		# 가스 차단 (B6, 2026-11-16 사용자가 블렌더에서 확인): LPG 용기 앞에 쪼그려 앉아 밸브 손잡이를 시계 방향으로 돌려 잠근다
		var gl := _gas_layout(crew, art)
		anim = "gas_off"
		dir = int(gl.k)
		moving = false
	elif ff.swap_timer > 0.0 and not moving and art.frames("scba_swap") > 0:
		# 공기호흡기 용기 교체 (B5, 2026-11-16 사용자가 블렌더에서 확인): 각자 앉아 등지게를 바닥에 놓고 공병을 바꾼다
		anim = "scba_swap"
	elif task is RescueSystem.SearchTask and not moving:
		anim = "search"
	elif moving:
		anim = "crouch_walk" if ff.crouched else "walk"
	elif ff.crouched:
		anim = "crouch_walk"
	# 무전 보고 (A8, 2026-11-15 사용자가 블렌더에서 확인): 이 조가 지금 무전을 보내고 있으면, 손이 비어 멈춰 있는 조장이
	# 무전기를 입 앞에 대고 말한다 — 누가 말하는지 보이게. 방수·문 개방·운반 중에는 그 동작을 그대로 둔다
	# 말하는 사람 = 팀장(분대 지휘관), 팀장이 없으면 선두 (2026-11-16 결정)
	if ff == crew.speaker() and not moving and anim in ["idle", "crouch_walk", "search"] and art.frames("radio") > 0 and _talking(crew):
		anim = "radio_low" if ff.crouched and art.frames("radio_low") > 0 else "radio"
	# 구급가방 (2026-11-15 사용자): 구급대 조의 짝(두 번째 대원)이 오른손에 들고 다닌다
	if ff == crew.partner and anim in ["idle", "walk"] and art.frames(anim + "_bag") > 0:
		anim += "_bag"
	var frame := 0
	# 여럿이 한 장면으로 구운 동작(문 개방·2인 운반)은 조장 기준 같은 박자로 — 구울 때 맞춘 엇갈림이 그대로 보이게
	var phase := (crew.leader.id if anim in PAIRED_ANIMS else ff.id) * 0.37
	if moving or anim in ["idle", "idle_bag", "spray", "search", "force_a", "force_b", "radio", "radio_low", "door_feel", "window_break", "scba_swap", "gas_off"] or anim in PAIRED_ANIMS:
		frame = SpriteArt.frame_at(anim, art.frames(anim), phase)
	if fixed_frame >= 0:
		frame = fixed_frame
	return [anim, dir if dir >= 0 else int(_facing.get(ff.id, 1)), frame]


## 여럿이 한 장면으로 구운 동작 (프레임을 조장 기준으로 맞춘다)
const PAIRED_ANIMS := ["hose_fetch_a", "hose_fetch_b", "hose_carry_a", "hose_carry_b", "hose_tidy", "force_a", "force_b", "lift_f", "lift_b", "drag", "spray_n", "spray_h", "spray_h1", "spray_h2",
	"spray_ln", "spray_lh", "spray_lh1", "spray_lh2", "search_a", "search_b", "aid_a", "aid_b",
	"cot_a", "cot_b", "scoop_a", "scoop_b", "ovh_a", "ovh_b"]


## 잔불 정리 배치 (B3): 그 조가 잔불 정리를 맡아 그 방에 멈춰 있으면 {k, anims {대원 id: 동작}, spots {짝 id: 칸 좌표}}, 아니면 빈 것.
## 기준점 = 조장 (조장 자리 그대로, 짝은 구울 때 적은 자리). 방향 = 조장이 마지막으로 본 쪽
func _overhaul_layout(crew: Crew, art: SpriteArt.SpriteSet, alpha := 0.0) -> Dictionary:
	if crew == null or art == null or art.frames("ovh_a") <= 0 or sim.rekindle.tasks.is_empty():
		return {}
	var t := sim.rekindle.task_of_crew(crew.id)
	var lead := crew.leader
	if t == null or lead.incapacitated or lead.is_moving():
		return {}
	var room := sim.fire.compartment_at(lead.level, floori(lead.pos.x), floori(lead.pos.y))
	if room == null or room.index != t.room:
		return {}
	var k := int(_facing.get(lead.id, 1))
	var facing := Vector2.RIGHT.rotated(k * PI / 4.0)
	var out := {"k": k, "anims": {lead.id: "ovh_a"}, "spots": {}}
	var mate := crew.partner
	if mate != null and not mate.incapacitated and mate.level == lead.level:
		out.anims[mate.id] = "ovh_b"
		out.spots[mate.id] = stand_spot(UnitsView.display_pos(lead, alpha), facing, art.stand("ovh_b"), sim.units.cell_size_m)
	return out


## 문 확인 후 개방 배치 (B1): 그 조가 문을 열기 전 확인 중(door_feel)이거나 잠기지 않은 문을 여는 중(door_open)이면
## {k 문을 보는 방향, opener 여는 대원 id, anim, frame(여는 중의 장, 확인 중은 -1), spot 서는 자리}, 아니면 빈 것.
## 여는 사람 = 짝(없으면 조장) — 조장(관창수)은 문 앞에서 기다린다. 기준점 = 문 가운데
func _door_check_layout(crew: Crew, art: SpriteArt.SpriteSet) -> Dictionary:
	if crew == null or art == null or art.frames("door_feel") <= 0:
		return {}
	var door: Opening = null
	var anim := "door_feel"
	var frame := -1
	var dt := sim.doors.task_of_crew(crew.id)
	if dt != null and dt.stacked(crew.id):
		dt = null
	if dt != null and dt.open and dt.opening != null and not dt.opening.locked and not dt.waiting_people:
		door = dt.opening
		anim = "door_open"
		var n := art.frames("door_open")
		frame = clampi(int(dt.progress / maxf(dt.required, 0.001) * n), 0, n - 1)
	else:
		door = sim.cards.checking_door(crew.id)
	if door == null or door.cells.is_empty():
		return {}
	var opener := crew.partner if crew.partner != null and not crew.partner.incapacitated else crew.leader
	if opener.incapacitated or opener.level != door.level or opener.is_moving() or opener.pos.distance_to(door_center(door)) > 3.5:
		return {}
	var fr := force_frame(door, opener.pos)
	return {"k": fr.k, "opener": opener.id, "anim": anim, "frame": frame,
		"spot": stand_spot(door_center(door), fr.facing, art.stand(anim), sim.units.cell_size_m)}


## 창 파괴 배치 (B2): 그 조가 창을 깨는 중이면 {k 창을 보는 방향, breaker 깨는 대원 id(조장), spot 서는 자리}, 아니면 빈 것.
## 기준점 = 창 가운데. 구울 때 적은 자리(창의 왼쪽 옆)
func _window_layout(crew: Crew, art: SpriteArt.SpriteSet) -> Dictionary:
	if crew == null or art == null or art.frames("window_break") <= 0 or sim.doors.tasks.is_empty():
		return {}
	var t := sim.doors.task_of_crew(crew.id)
	if t == null or t.stacked(crew.id) or t.opening == null or t.opening.kind != Opening.Kind.WINDOW or t.opening.cells.is_empty() or t.waiting_people:
		return {}
	var ff := crew.leader
	if ff.incapacitated or ff.level != t.opening.level or ff.is_moving() or ff.pos.distance_to(door_center(t.opening)) > 3.5:
		return {}
	var fr := force_frame(t.opening, ff.pos)
	return {"k": fr.k, "breaker": ff.id, "spot": stand_spot(door_center(t.opening), fr.facing, art.stand("window_break"), sim.units.cell_size_m)}


## 가스 차단 배치 (B6): 그 조가 가스 밸브 차단을 맡아 밸브 곁에 멈춰 있으면 {k, spot 조장 자리}, 아니면 빈 것.
## 기준점 = 밸브 칸(LPG 용기). 조장은 다가온 쪽에서 용기를 본다
func _gas_layout(crew: Crew, art: SpriteArt.SpriteSet) -> Dictionary:
	if crew == null or art == null or art.frames("gas_off") <= 0 or not sim.gas.workers.has(crew.id):
		return {}
	var lead := crew.leader
	var valve := Vector2(sim.gas.valve) + Vector2(0.5, 0.5)
	if lead.incapacitated or lead.is_moving() or lead.level != 1 or lead.pos.distance_to(valve) > 2.0:
		return {}
	var away := lead.pos - valve
	if away.length_squared() < 0.0001:
		away = Vector2.DOWN
	var st := art.stand("gas_off")
	var phi := away.angle() - atan2(float(st.get("right_m", 0.0)), float(st.get("fwd_m", 0.0)))
	var k := posmod(roundi(phi / (PI / 4.0)), 8)
	return {"k": k, "spot": stand_spot(valve, Vector2.RIGHT.rotated(k * PI / 4.0), st, sim.units.cell_size_m)}


## 문 앞 방수태세 자리 (E4): 문 가운데(center)에서 대원 쪽으로 back(칸)만큼 물러나고, 문을 여는 사람(opener_spot)의 반대쪽 옆으로
## side(칸)만큼 비킨 곳. 여는 사람이 없거나(문 파괴 — 두 사람이 문틈 양쪽에 선다) 가운데에 있으면 비키지 않는다.
## facing = 대원 쪽에서 문을 보는 방향
static func door_ready_spot(center: Vector2, facing: Vector2, opener_spot: Variant, back: float, side: float) -> Vector2:
	var right := facing.rotated(PI / 2.0)
	var away := 0.0
	if opener_spot is Vector2:
		away = -signf(((opener_spot as Vector2) - center).dot(right))
	return center - facing * back + right * away * side


## 문 앞 방수태세 배치 (E4 — 화재1 화점실 진입 '문의 측면에 위치해 엄호방수하면서 서서히 문을 개방', '방수태세를 갖춘 후 개방'):
## 수관을 가진 조가 문을 확인·개방·파괴하는 동안, 그 일을 하지 않는 관창수(선두)가 문 옆에서 낮은 자세로 관창을 문에 겨누고 기다린다.
## 새 그림 없이 낮은 자세 방수(A5 spray_ln)의 첫 장을 쓴다 (2026-11-21 결정). → {id 관창수, k 방향, spot 자리} 또는 빈 것
func _door_ready_layout(crew: Crew, art: SpriteArt.SpriteSet) -> Dictionary:
	if crew == null or art == null or art.frames("spray_ln") <= 0:
		return {}
	if sim.doors.tasks.is_empty() and sim.cards.checking_door(crew.id) == null:
		return {}
	var h := sim.water.held_hose(crew.id)
	if h == null or h.to_outlet or h.fetch_until >= 0:
		return {}
	var lead := crew.leader
	if lead == null or lead.incapacitated or lead.is_moving():
		return {}
	var door: Opening = null
	var opener_spot: Variant = null
	var busy: Array = []
	var dt := sim.doors.task_of_crew(crew.id)
	var dl := _door_check_layout(crew, art)
	if not dl.is_empty():
		door = dt.opening if dt != null and dt.open and dt.opening != null and not dt.opening.locked and not dt.waiting_people else sim.cards.checking_door(crew.id)
		busy = [int(dl.opener)]
		opener_spot = dl.spot
	elif dt != null and _forcing(dt, lead) and art.frames("force_a") > 0:
		door = dt.opening
		busy = _force_layout(dt, crew, art).anims.keys()
	if door == null or door.kind != Opening.Kind.DOOR or door.cells.is_empty() or lead.id in busy:
		return {}
	var center := door_center(door)
	if lead.level != door.level or lead.pos.distance_to(center) > 3.5:
		return {}
	# 자리는 문 개방 분대 배치(경첩 쪽, 문 정면 띠 밖 — 2026-11-24)를 따른다
	var tl := _door_team_layout(crew, art)
	var spot: Vector2
	if tl.get("spots", {}).has(lead.id):
		spot = tl.spots[lead.id]
	else:
		var st := HoseDraw.style()
		var cell_m := sim.units.cell_size_m
		var fr := force_frame(door, lead.pos)
		spot = door_ready_spot(center, fr.facing, opener_spot, float(st.get("ready_back_m", 1.1)) / cell_m, float(st.get("ready_side_m", 0.4)) / cell_m)
	return {"id": lead.id, "k": SpriteArt.dir8(center - spot), "spot": spot}


## 경첩 쪽 (칸 좌표의 단위 벡터, facing = 대원 쪽에서 문을 보는 방향). 문을 여는 사람은 손잡이 쪽 벽에 붙어 연다 —
## B1 문 확인(door_feel)을 구울 때 선 쪽(right_m 부호)이 손잡이 쪽이므로 그 반대
func _hinge_dir(facing: Vector2, art: SpriteArt.SpriteSet) -> Vector2:
	var right := facing.rotated(PI / 2.0)
	var r := -0.7
	if art != null and art.frames("door_feel") > 0:
		r = float(art.stand("door_feel").get("right_m", -0.7))
	return -right * (signf(r) if r != 0.0 else -1.0)


## 문 개방 때 분대 배치 (2026-11-24 사용자 결정 — 화재1 p.134 '문의 측면에 위치해 엄호방수하면서 서서히 문을 개방',
## p.215 '문을 개방하는 대원 및 관창의 위치는 정면을 피한다', p.217 '관창수는 문의 측면에서 주수', 관창수는 경첩 쪽):
## 문 일(확인·개방·파괴)을 하지 않는 조원은 문 정면 띠(문 폭 + 양옆 door_front_margin_m) 밖 경첩 쪽에 줄을 선다 —
## 선두(관창수)가 맨 앞(문에서 nozzle_door_back_m), 그 뒤로 관창보조(door_assist_gap_m), 나머지(팀장 등)(door_rest_gap_m씩).
## 그 조가 문을 여는 분대로서 문 일을 하고 있을 때만 → {door, facing, k 문을 보는 방향, spots {대원 id: 칸}}, 아니면 빈 것
func _door_team_layout(crew: Crew, art: SpriteArt.SpriteSet) -> Dictionary:
	if crew == null or art == null:
		return {}
	var door: Opening = null
	var dt := sim.doors.task_of_crew(crew.id)
	if dt != null and not dt.stacked(crew.id) and dt.open and dt.opening != null and not dt.waiting_people:
		door = dt.opening
	if door == null:
		door = sim.cards.checking_door(crew.id)
	if door == null or door.kind != Opening.Kind.DOOR or door.cells.is_empty():
		return {}
	var lead := crew.leader
	if lead == null or lead.incapacitated or lead.is_moving() or lead.level != door.level:
		return {}
	var center := door_center(door)
	if lead.pos.distance_to(center) > 3.5:
		return {}
	# 문 일을 하는 사람 (여는 사람 · 부수는 두 사람)은 뺀다
	var busy: Array = []
	var dl := _door_check_layout(crew, art)
	if not dl.is_empty():
		busy.append(int(dl.opener))
	if dt != null and not dt.stacked(crew.id) and _forcing(dt, lead) and art.frames("force_a") > 0:
		busy.append_array(_force_layout(dt, crew, art).anims.keys())
	var st := HoseDraw.style()
	var cell_m := maxf(0.01, sim.units.cell_size_m)
	var fr := force_frame(door, lead.pos)
	var facing: Vector2 = fr.facing
	var hinge := _hinge_dir(facing, art)
	var side := (door.cells.size() * cell_m * 0.5 + float(st.get("door_front_margin_m", 0.3))) / cell_m
	var back := float(st.get("nozzle_door_back_m", 1.0)) / cell_m
	var gap1 := float(st.get("door_assist_gap_m", 0.9)) / cell_m
	var gap2 := float(st.get("door_rest_gap_m", 0.8)) / cell_m
	# 줄 순서: 선두(관창수) → 일하는 조원 → 팀장(일하지 않는 지휘자)
	var order: Array[Firefighter] = [lead]
	for ff in crew.workers():
		if not ff in order:
			order.append(ff)
	for ff in crew.members():
		if not ff in order:
			order.append(ff)
	var spots := {}
	var n := 0
	for ff in order:
		if ff.incapacitated or ff.id in busy or ff.level != door.level:
			continue
		var d := back + (0.0 if n == 0 else gap1 + gap2 * (n - 1))
		spots[ff.id] = center - facing * d + hinge * side
		n += 1
	if spots.is_empty():
		return {}
	var first: Vector2 = spots.values()[0]
	return {"door": door, "facing": facing, "k": SpriteArt.dir8(center - first), "spots": spots}


## 문을 여는(확인·개방·파괴) 조의 선두가 그 일을 하지 않을 때 기다리는 자리 (방수태세가 없는 조 — 구조대 등).
## 방수태세 자리(door_ready_spot)와 같은 곳: 문에서 ready_back_m 물러나 여는 사람의 반대쪽 옆.
## 2026-11-24 — 선두가 실제 자리(문 앞 작업 칸)에 그대로 그려져 문틈 옆에서 문을 부수는 조원과 겹쳤다. 아니면 null
func _door_lead_wait_spot(crew: Crew, art: SpriteArt.SpriteSet) -> Variant:
	if crew == null or art == null:
		return null
	var lead := crew.leader
	if lead == null or lead.incapacitated or lead.is_moving():
		return null
	if not _door_ready_layout(crew, art).is_empty():
		return null
	var door: Opening = null
	var opener_spot: Variant = null
	var dt := sim.doors.task_of_crew(crew.id)
	var dl := _door_check_layout(crew, art)
	if not dl.is_empty():
		if int(dl.opener) == lead.id:
			return null
		door = dt.opening if dt != null and not dt.stacked(crew.id) and dt.opening != null else sim.cards.checking_door(crew.id)
		opener_spot = dl.spot
	elif dt != null and _forcing(dt, lead) and art.frames("force_a") > 0:
		if _force_layout(dt, crew, art).anims.has(lead.id):
			return null
		door = dt.opening
	if door == null or door.kind != Opening.Kind.DOOR or door.cells.is_empty():
		return null
	var center := door_center(door)
	if lead.level != door.level or lead.pos.distance_to(center) > 3.5:
		return null
	var tl := _door_team_layout(crew, art)
	if tl.get("spots", {}).has(lead.id):
		return tl.spots[lead.id]
	var st := HoseDraw.style()
	var cell_m := sim.units.cell_size_m
	var fr := force_frame(door, lead.pos)
	return door_ready_spot(center, fr.facing, opener_spot, float(st.get("ready_back_m", 1.1)) / cell_m, float(st.get("ready_side_m", 0.4)) / cell_m)


## 창을 깨는 대원 id (없으면 -1)
func _window_breaker(crew: Crew, art: SpriteArt.SpriteSet) -> int:
	var wl := _window_layout(crew, art)
	return int(wl.breaker) if not wl.is_empty() else -1


## 문을 확인·여는 대원 id (없으면 -1)
func _door_opener(crew: Crew, art: SpriteArt.SpriteSet) -> int:
	var dl := _door_check_layout(crew, art)
	return int(dl.opener) if not dl.is_empty() else -1


## 운전원 작업 (2026-11-16 사용자 결정, SOP 205): 차가 소화전 점령·급수 연결을 하는 동안만 운전원이 내려 직접 호스를 연결한다.
## 진행률 구간마다 동작·자리(data/art.json driver_steps). 사람마다 {anim, k, frame, pos, depth}:
## driver = 이 차 운전원, helper = 둘이서 할 때 차 옆 조의 조장(차 쪽 결합), other = 급수받는 펌프차 운전원.
## hose = 굴려 펴는 중·편 뒤의 호스가 놓인 길 (셀 좌표 점들). 작업이 없으면 빈 것
func _driver_layout(v: Vehicle) -> Dictionary:
	if v == null or v.work.is_empty() or v.away or thermal:
		return {}
	var dart := SpriteArt.get_set(str(SpriteArt.config().get("driver", "")))
	if dart == null:
		return {}
	var kind := str(v.work.kind)
	var helper := int(v.work.get("helper", -1))
	var key := kind
	if kind == "hydrant":
		key = "hydrant_pair" if helper >= 0 else "hydrant_solo"
	var plan: Dictionary = SpriteArt.config().get("driver_steps", {}).get(key, {})
	if plan.is_empty():
		return {}
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var a_body := v.pos
	var b_body := Vector2.ZERO
	var other_v: Vehicle = null
	if kind == "hydrant":
		var hi := int(v.work.target)
		if hi < 0 or hi >= sim.building.hydrants.size():
			return {}
		b = Vector2(sim.building.hydrants[hi]) + Vector2(0.5, 0.5)
		# 차 쪽 결합 자리: 펌프차는 후면 보수구 (2026-11-21)
		a = HoseDraw.intake_point(v, b)
		b_body = b
	else:
		other_v = sim.units.get_vehicle(int(v.work.target))
		if other_v == null:
			return {}
		# 물탱크차 후면에서 펌프차 후면으로 (두 차 모두 후면에 결합 — 2026-11-21)
		b = HoseDraw.intake_point(other_v, v.rear_point())
		a = HoseDraw.intake_point(v, b)
		b_body = other_v.pos
	var prog := sim.water.work_progress(v)
	var out := {}
	for who: String in ["driver", "helper", "other"]:
		if not plan.has(who):
			continue
		var art := dart if who != "helper" else SpriteArt.crew_set("진압대")
		var placed := _driver_step(plan[who], prog, art, a, b, a_body, b_body, kind, v.id)
		if not placed.is_empty():
			out[who] = placed
	if kind == "hydrant" and helper >= 0:
		out.helper_crew = helper
	if other_v != null:
		out.other_vehicle = other_v.id
	# 호스 선: 굴려 펴는 동안 시작점에서 쭉 늘어나고, 편 뒤에는 끝까지
	var roll: Array = plan.get("roll", [])
	if roll.size() == 2 and prog >= float(roll[0]):
		# 소화전 급수는 소화전에서 차 쪽으로, 물탱크차 급수는 물탱크차에서 펌프차 쪽으로 편다 (차 몸통에 걸리면 돌아가는 길 — HoseDraw.supply_route·supply_between)
		var route: PackedVector2Array = HoseDraw.supply_route(v, b, sim.building.cell_size_m) if kind == "hydrant" else HoseDraw.supply_between(v, other_v, sim.building.cell_size_m)
		var f := clampf((prog - float(roll[0])) / maxf(0.001, float(roll[1]) - float(roll[0])), 0.0, 1.0)
		out.hose = HoseDraw.cut(route, f)
	return out


## 한 사람의 지금 구간: 동작·방향·자리. 동작이 ""이면 빈 것 (안 보임)
func _driver_step(steps: Array, prog: float, art: SpriteArt.SpriteSet, a: Vector2, b: Vector2, a_body: Vector2, b_body: Vector2,
		kind: String, seed: int) -> Dictionary:
	if art == null or steps.is_empty():
		return {}
	var t0 := 0.0
	var step: Array = steps[steps.size() - 1]
	for s: Array in steps:
		if prog < float(s[0]):
			step = s
			break
		t0 = float(s[0])
	var anim := str(step[1])
	var where := str(step[2])
	if anim == "" or art.frames(anim) <= 0:
		return {}
	var f := clampf((prog - t0) / maxf(0.001, float(step[0]) - t0), 0.0, 1.0)
	var cell := sim.units.cell_size_m
	var pos := a
	var k := 0
	var frame := -1
	match where:
		"walk_a_b", "walk_b_a":
			var p0 := a if where == "walk_a_b" else b
			var p1 := b if where == "walk_a_b" else a
			pos = p0.lerp(p1, f)
			k = SpriteArt.dir8(p1 - p0)
		"roll_a", "roll_b":
			# 호스를 굴려 펴기: 시작점에서 상대 쪽을 보고 굴린다. 장은 진행 정도로 (한 번)
			var p0 := a if where == "roll_a" else b
			var p1 := b if where == "roll_a" else a
			# 소화전(차) 바로 옆에서 상대 쪽으로 반 걸음 나와 굴린다 (소화전과 겹치지 않게)
			pos = p0 + (p1 - p0).normalized() * (0.6 / maxf(0.01, cell))
			k = SpriteArt.dir8(p1 - p0)
			frame = clampi(int(f * art.frames(anim)), 0, art.frames(anim) - 1)
		"at_a", "at_b":
			var spot := a if where == "at_a" else b
			var away := spot - (a_body if where == "at_a" else b_body)
			if where == "at_b" and kind == "hydrant":
				away = a - b  # 소화전에서는 차 쪽에 선다
			if away.length_squared() < 0.0001:
				away = Vector2.DOWN
			# 서기(idle)는 결합하던 자리 그대로
			var st := art.stand(anim if anim != "idle" else "cpl_mid")
			var phi := away.angle() - atan2(float(st.get("right_m", 0.0)), float(st.get("fwd_m", 0.0)))
			k = posmod(roundi(phi / (PI / 4.0)), 8)
			pos = stand_spot(spot, Vector2.RIGHT.rotated(k * PI / 4.0), st, cell)
	if frame < 0:
		frame = SpriteArt.frame_at(anim, art.frames(anim), seed * 0.37)
	return {"anim": anim, "k": k, "frame": frame, "pos": pos, "depth": pos.x + pos.y}


## 차 옆 조의 조장이 소화전 급수를 도와 차 쪽 결합을 하는 중이면 그 자세 {anim, k, frame, pos}, 아니면 빈 것
func _helper_pose(ff: Firefighter) -> Dictionary:
	var c := sim.units.get_crew(ff.crew_id)
	if c == null or c.leader != ff:
		return {}
	for v in sim.units.vehicles:
		if v.work.is_empty() or int(v.work.get("helper", -1)) != c.id:
			continue
		var dl := _driver_layout(v)
		if dl.has("helper"):
			return dl.helper
	return {}


func _append_drivers(items: Array) -> void:
	for v in sim.units.vehicles:
		var dl := _driver_layout(v)
		for who: String in ["driver", "other"]:
			if dl.has(who):
				items.append([float(dl[who].depth), {"driver": v.id, "who": who}])


func _draw_driver(d: Dictionary) -> void:
	var v := sim.units.get_vehicle(int(d.driver))
	var dl := _driver_layout(v)
	var who := str(d.get("who", "driver"))
	if not dl.has(who):
		return
	var p: Dictionary = dl[who]
	var art := SpriteArt.get_set(str(SpriteArt.config().get("driver", "")))
	var owner := v if who == "driver" else sim.units.get_vehicle(int(dl.get("other_vehicle", v.id)))
	var feet := proj.to_screen(p.pos, 0.0)
	_contact_shadow(feet, 10, 5, 0.3)
	art.draw(self, str(p.anim), int(p.k), int(p.frame), feet, Color.WHITE, SpriteArt.helmet_color(sim.units.squads[owner.squad_id].type))


## 구급대 들것 이송 배치 (A10): 처치한 환자를 구급차로 옮기는 중이면
## {kind 들것 종류, k 방향, anims, spots {짝 id: 칸 좌표}, victim 환자(들것) 그림 자리, victim_anim}, 아니면 빈 것.
## 바깥(평지)은 주 들것(cot), 건물 안은 분리형 들것(scoop). 기준점 = 조장. 방향 = 조장이 걷는 쪽
func _ems_carry_layout(crew: Crew, art: SpriteArt.SpriteSet, alpha := 0.0) -> Dictionary:
	if crew == null or art == null or sim.ems.patients.is_empty():
		return {}
	var p := sim.ems.patient_of_crew(crew.id)
	if p == null or p.stage != EmsSystem.Stage.CARRYING or p.victim_id < 0 or p.victim_id >= sim.rescue.victims.size():
		return {}
	var lead := crew.leader
	if lead.incapacitated:
		return {}
	var v: Victim = sim.rescue.victims[p.victim_id]
	var vart := SpriteArt.victim_set(v.label())
	if vart == null:
		return {}
	var kind := "cot" if _outdoor_at(lead.pos) else "scoop"
	if art.frames(kind + "_a") <= 0 or vart.frames(kind + "_v") <= 0:
		kind = "cot"
		if art.frames("cot_a") <= 0 or vart.frames("cot_v") <= 0:
			return {}
	var d := lead.pos - lead.prev_pos
	var k := SpriteArt.dir8(d) if lead.level == lead.prev_level and d.length_squared() > 0.000001 else int(_facing.get(lead.id, 1))
	var facing := Vector2.RIGHT.rotated(k * PI / 4.0)
	var cell := sim.units.cell_size_m
	var lp := UnitsView.display_pos(lead, alpha)
	var out := {"kind": kind, "k": k, "anims": {lead.id: kind + "_a"}, "spots": {},
		"victim": stand_spot(lp, facing, vart.stand(kind + "_v"), cell), "victim_anim": kind + "_v"}
	var mate := crew.partner
	if mate != null and not mate.incapacitated and mate.level == lead.level:
		out.anims[mate.id] = kind + "_b"
		out.spots[mate.id] = stand_spot(lp, facing, art.stand(kind + "_b"), cell)
	return out


## 응급처치 배치 (A9): 구급대 조가 환자 곁에 멈춰 처치 중이면
## {k 방향, anims {대원 id: 동작}, spots {대원 id: 칸 좌표}, victim 환자 그림 자리, victim_id}, 아니면 빈 것.
## 기준점 = 환자 자리(몸 가운데). 조장 = aid_a(머리 옆), 짝 = aid_b(팔 옆). 방향은 조장이 다가온 쪽에서 환자를 보는 쪽
func _aid_layout(crew: Crew, art: SpriteArt.SpriteSet, alpha := 0.0) -> Dictionary:
	if crew == null or art == null or art.frames("aid_a") <= 0 or sim.ems.patients.is_empty():
		return {}
	var p := sim.ems.patient_of_crew(crew.id)
	if p == null or p.stage != EmsSystem.Stage.TREATING or p.treat_start_tick < 0:
		return {}
	var lead := crew.leader
	if lead.incapacitated or lead.is_moving() or p.victim_id < 0 or p.victim_id >= sim.rescue.victims.size():
		return {}
	var v: Victim = sim.rescue.victims[p.victim_id]
	var vart := SpriteArt.victim_set(v.label())
	if vart == null or vart.frames("aid_v") <= 0:
		return {}
	var d := v.pos - lead.pos
	var k := SpriteArt.dir8(d) if d.length_squared() > 0.0001 else 1
	var facing := Vector2.RIGHT.rotated(k * PI / 4.0)
	var cell := sim.units.cell_size_m
	var out := {"k": k, "anims": {lead.id: "aid_a"}, "spots": {lead.id: stand_spot(v.pos, facing, art.stand("aid_a"), cell)},
		"victim": stand_spot(v.pos, facing, vart.stand("aid_v"), cell), "victim_id": v.id}
	var mate := crew.partner
	if mate != null and not mate.incapacitated and mate.level == lead.level:
		out.anims[mate.id] = "aid_b"
		out.spots[mate.id] = stand_spot(v.pos, facing, art.stand("aid_b"), cell)
	return out


## 이 조가 지금 무전을 보내는 중인가 (지휘망·작전망의 송신 중 무전). 보고 사건에 조 번호가 있으면 그것으로,
## 없으면 보낸 쪽 이름("진압1 1조")으로 찾는다
func _talking(crew: Crew) -> bool:
	var radios: Array = [sim.command.radio]
	for dv in sim.command.org.divisions:
		radios.append(dv.radio)
	var call := sim.units.crew_name(crew)
	for r in radios:
		var m: Radio.Message = r.current
		if m == null:
			continue
		if int(m.data.get("crew_id", -1)) == crew.id or m.sender == call:
			return true
	return false


## 인명검색 이동 배치 (A7): 검색 중인 조의 조장이 걷고 있으면 {k 방향, anims {대원 id: 동작}, spots {짝 id: 칸 좌표}}, 아니면 빈 것.
## 조장 = search_a(앞), 짝 = search_b(조장 뒤 — 구울 때 적은 자리). 조장이 멈추면 예전처럼 제자리 검색(search)
func _search_layout(crew: Crew, art: SpriteArt.SpriteSet, alpha := 0.0) -> Dictionary:
	if art == null or art.frames("search_a") <= 0 or crew == null:
		return {}
	if not sim.rescue.task_of_crew(crew.id) is RescueSystem.SearchTask:
		return {}
	# 2인 1조씩: 첫째 짝(조원 첫째·둘째), 4명 분대는 둘째 짝(셋째·넷째)도 — 짝마다 앞사람이 걷는 방향으로 (2026-11-16 결정)
	var pairs: Array = [[crew.leader, crew.partner]]
	if crew.list.size() >= 4:
		pairs.append([crew.list[2], crew.list[3]])
	var out := {"k": 1, "ks": {}, "anims": {}, "spots": {}}
	for pair: Array in pairs:
		var lead: Firefighter = pair[0]
		var mate: Firefighter = pair[1]
		if lead.incapacitated or mate == null or mate.incapacitated or mate.level != lead.level:
			continue
		var delta := lead.pos - lead.prev_pos
		if lead.level != lead.prev_level or delta.length_squared() <= 0.000001:
			continue
		var k := SpriteArt.dir8(delta)
		var facing := Vector2.RIGHT.rotated(k * PI / 4.0)
		var lp := UnitsView.display_pos(lead, alpha)
		out.anims[lead.id] = "search_a"
		out.anims[mate.id] = "search_b"
		out.ks[lead.id] = k
		out.ks[mate.id] = k
		out.spots[mate.id] = stand_spot(lp, facing, art.stand("search_b"), sim.units.cell_size_m)
		if lead == crew.leader:
			out.k = k
	return out if not out.anims.is_empty() else {}


## 호스 꺼내기 배치 (E1): 분대가 펌프차 후면에서 호스를 꺼내는 동안(수관 준비 시간), 1번(관창수)과 2번이 차 후면(열린 셔터)을 보고
## 나란히 서서 접어 쌓은 호스를 두 손으로 당겨 꺼낸다. 1번은 후면 가운데에서 fetch_stand_m 뒤, 2번은 구울 때 적은 옆자리.
## → {k 방향(차가 보는 쪽), anims {대원 id: 동작}, spots {대원 id: 칸 좌표}} 또는 빈 것 (그림이 아직 없으면 빈 것 — 서 있는 그림)
func _hose_fetch_layout(crew: Crew, art: SpriteArt.SpriteSet) -> Dictionary:
	if art == null or crew == null or art.frames("hose_fetch_a") <= 0:
		return {}
	var h := sim.water.held_hose(crew.id)
	if h == null or h.fetch_until < 0 or h.outlet >= 0:
		return {}
	var v := sim.units.get_vehicle(h.vehicle_id)
	var lead := crew.leader
	if v == null or lead == null or lead.incapacitated or lead.level != v.level:
		return {}
	var cell_m := sim.units.cell_size_m
	var k := SpriteArt.dir8(v.heading)
	var facing := Vector2.RIGHT.rotated(k * PI / 4.0)
	var base := v.rear_point(float(HoseDraw.style().get("fetch_stand_m", 0.75)) / cell_m)
	var out := {"k": k, "anims": {lead.id: "hose_fetch_a"}, "spots": {lead.id: base}}
	for ff in crew.workers():
		if ff != lead and not ff.incapacitated and ff.level == lead.level and art.frames("hose_fetch_b") > 0:
			out.anims[ff.id] = "hose_fetch_b"
			out.spots[ff.id] = stand_spot(base, facing, art.stand("hose_fetch_b"), cell_m)
			break
	return out


## 호스 끼고 걷기 배치 (E2·A6·E3, 2026-11-21 사용자가 블렌더에서 확인): 펌프차에서 꺼낸 호스에 아직 물이 차지 않은 동안,
## 관창수(1번) = hose_carry_a(접은 호스 묶음을 겨드랑이에), 다음 일하는 조원(2번) = hose_carry_b(더 큰 묶음 — 바닥으로는 여기서 떨어진다),
## 그다음(3번) = hose_tidy(낮은 자세로 깔린 호스를 들어 꼬임을 편다). 팀장은 그냥 걷는다. 멈춰 서 있을 때는 첫 장으로 서 있다.
## 2·3번은 호스가 깔린 길 위에서 1번 뒤로 구울 때 적은 거리만큼 떨어진 자리에 선다 (모퉁이를 돌아도 호스를 따라간다).
## 방수 위치에 닿아 관창을 겨누면(방수 배치) 묶음을 내려놓은 것으로 본다.
## → {k, ks {대원 id: 방향}, anims {대원 id: 동작}, spots {대원 id: 칸 좌표}, moving,
##    ground_end 바닥 호스가 끝나는 거리(칸, 2번이 있을 때), gap [from, to] 3번이 들어 올린 구간(칸)} 또는 빈 것
func _hose_carry_layout(crew: Crew, art: SpriteArt.SpriteSet, alpha := 0.0) -> Dictionary:
	if art == null or crew == null or art.frames("hose_carry_a") <= 0:
		return {}
	var h := sim.water.held_hose(crew.id)
	if h == null or h.outlet >= 0 or h.to_outlet or h.fetch_until >= 0 or h.charged or h.points.size() < 2:
		return {}
	var lead := crew.leader
	if lead == null or lead.incapacitated or lead.crouched or lead.level != h.points[h.points.size() - 1].z:
		return {}
	var moving := lead.level == lead.prev_level and (lead.pos - lead.prev_pos).length_squared() > 0.000001
	if h.flowing and not h.approaching and not moving:
		return {}
	var members: Array[Firefighter] = []
	for ff in crew.workers():
		if not ff.incapacitated:
			members.append(ff)
	if members.is_empty() or members[0] != lead:
		return {}
	var cell_m := sim.units.cell_size_m
	var trail := HoseDraw.trail(h, lead.level, UnitsView.display_pos(lead, alpha))
	if trail.is_empty():
		return {}
	var first: float = trail.dist[0]
	var end: float = trail.dist[trail.dist.size() - 1]
	var k := int(_facing.get(lead.id, 1))
	var out := {"k": k, "ks": {lead.id: k}, "anims": {lead.id: "hose_carry_a"}, "spots": {}, "moving": moving}
	var st := HoseDraw.style()
	var names: Array = ["hose_carry_b", "hose_tidy"]
	for i in range(1, mini(members.size(), names.size() + 1)):
		var ff := members[i]
		var anim: String = names[i - 1]
		if ff.level != lead.level or art.frames(anim) <= 0:
			continue
		# 구울 때 적은 자리: 1번 뒤로 몇 m (fwd_m이 음수)
		var d := end + float(art.stand(anim).get("fwd_m", 0.0)) / cell_m
		if d < first + 0.5:
			continue  # 호스가 아직 거기까지 깔리지 않았다 — 이 사람은 그냥 걷는다
		if anim == "hose_carry_b":
			# 2번은 1번 바로 뒤(1번이 보는 방향 기준)에 선다 — 1번 묶음에서 이어지는 호스가 그림에서 곧게 뒤로 나가므로.
			# 모퉁이에서는 끌려오는 수레처럼 안쪽으로 돈다. 바닥 호스는 2번 뒤에서 닿는다
			var facing := Vector2.RIGHT.rotated(k * PI / 4.0)
			var drop := float(st.get("carry_drop_m", 0.8)) / cell_m
			out.anims[ff.id] = anim
			out.spots[ff.id] = stand_spot(trail.pts[trail.pts.size() - 1], facing, art.stand(anim), cell_m)
			out.ks[ff.id] = k
			# 바닥 호스의 끝을 그림 속 호스가 바닥에 닿은 자리(2번 뒤)로 잇는다 — 길이 굽어 있어도 끊겨 보이지 않게.
			# 바닥 호스는 깔린 길에서 그 자리와 가장 가까운 곳까지만 그린다 (지나쳤다 되돌아오지 않게)
			var tail := (out.spots[ff.id] as Vector2) - facing * drop
			var best_d := d - drop
			var best := INF
			var s := maxf(first, d - drop - 3.0)
			while s <= end:
				var q := HoseDraw.point_at(trail, s).distance_squared_to(tail)
				if q < best:
					best = q
					best_d = s
				s += 0.1
			out.ground_end = best_d
			out.ground_tail = tail
			out.tail_dir = facing
			continue
		# 3번은 깔린 호스 길 위에 선다. 들어 올린 호스 그림은 곧으므로, 그 구간에서 길이 굽으면 호스를 들지 않고 낮은 자세로만 걷는다
		# (굽은 곳에서 그림과 바닥 호스가 어긋나 끊겨 보이지 않게)
		var front := float(st.get("tidy_gap_front_m", 0.94)) / cell_m
		var back := float(st.get("tidy_gap_back_m", 0.86)) / cell_m
		var here := HoseDraw.point_at(trail, d)
		# 구간 양 끝에서 길이 가는 방향을 견준다 (끝 쪽에서만 꺾여도 알아채게)
		var ahead := HoseDraw.point_at(trail, minf(end, d + front)) - HoseDraw.point_at(trail, minf(end, d + front) - 0.5)
		var behind := HoseDraw.point_at(trail, maxf(first, d - back) + 0.5) - HoseDraw.point_at(trail, maxf(first, d - back))
		var along := HoseDraw.point_at(trail, minf(end, d + 0.6)) - HoseDraw.point_at(trail, maxf(first, d - 0.6))
		var bent := ahead.length_squared() < 0.0001 or behind.length_squared() < 0.0001 or along.length_squared() < 0.0001 \
			or absf(ahead.angle_to(behind)) > 0.2 or absf(ahead.angle_to(along)) > 0.2
		var ground: float = out.get("ground_end", end)
		if bent or d + front > ground:
			if art.frames("crouch_walk") > 0:
				out.anims[ff.id] = "crouch_walk"
		else:
			out.anims[ff.id] = anim
			out.gap = [d - back, d + front]
		if out.anims.has(ff.id):
			out.spots[ff.id] = here
			out.ks[ff.id] = SpriteArt.dir8(along) if along.length_squared() > 0.0001 else k
	return out


## _spray_layout 이 계산해 둔 것 {조 id: [바뀌면 다시 계산할 값들, 결과]}
var _spray_cache: Dictionary = {}


## 방수 배치 (A4): 관창수(조장)가 방수 중이면 {k 방향, ks {대원 id: 방향}, anims {대원 id: 동작}, spots {대원 id: 칸 좌표},
## ground_end·ground_tail·tail_dir·tail_h 바닥 호스가 끝나는 곳 (맨 뒤 사람의 그림 속 호스 끝)}, 아니면 빈 것.
## 조가 2명이면 관창수 + 관창보조(spray_h), 3명 이상(분대)이면 관창보조1·2(spray_h1·h2). 자리는 구울 때 적은 값
func _spray_layout(crew: Crew, art: SpriteArt.SpriteSet, alpha := 0.0) -> Dictionary:
	if art == null or art.frames("spray_n") <= 0:
		return {}
	var hose := sim.water.held_hose(crew.id)
	var lead := crew.leader
	if hose == null or not hose.flowing or hose.approaching or lead.incapacitated or lead.is_moving():
		return {}
	var k := SpriteArt.dir8(hose.aim - lead.pos)
	var facing := Vector2.RIGHT.rotated(k * PI / 4.0)
	# 방수는 일하는 조원만 — 진압 분대의 팀장은 호스를 잡지 않고 옆에서 통솔한다 (2026-11-16 결정)
	var members: Array[Firefighter] = crew.workers()
	var names: Array = ["spray_n", "spray_h"] if members.size() <= 2 else ["spray_n", "spray_h1", "spray_h2"]
	# 낮은 자세 (A5, 2026-11-15 사용자가 블렌더에서 확인): 관창수가 낮은 자세면 모두 무릎을 꿇고 호스를 겨드랑이에 낀다
	if lead.crouched and art.frames("spray_ln") > 0:
		names = ["spray_ln", "spray_lh"] if members.size() <= 2 else ["spray_ln", "spray_lh1", "spray_lh2"]
	var lp := UnitsView.display_pos(lead, alpha)
	var out := {"k": k, "ks": {}, "anims": {}, "spots": {}}
	# 줄 선 사람들 (쓰러진 사람은 빼고 앞에서부터) — 관창수가 빠지면 예전처럼 곧게 세운다
	var line: Array[Firefighter] = []
	var line_names: Array = []
	for i in members.size():
		if not members[i].incapacitated:
			line.append(members[i])
			line_names.append(names[mini(i, names.size() - 1)])
	if line.is_empty():
		return out
	# 한 화면에 여러 번 묻는다 (사람마다 자리·자세, 호스) — 바뀐 것이 없으면 계산해 둔 것을 쓴다
	var key := [sim.clock.tick, alpha, lp, hose.aim, lead.crouched, hose.points.size(), line.size(), art.id]
	var cached: Array = _spray_cache.get(crew.id, [])
	if cached.size() == 2 and cached[0] == key:
		return cached[1]
	_spray_cache[crew.id] = [key, out]
	if line[0] != lead:
		for i in line.size():
			out.anims[line[i].id] = line_names[i]
			out.spots[line[i].id] = stand_spot(lp, facing, art.stand(line_names[i]), sim.units.cell_size_m)
		return out
	# 뒤 사람은 앞사람 바로 뒤에 서되, 벽에 막히거나 호스 길이 꺾인 곳에서는 호스가 온 쪽으로 틀어 선다 (2026-11-24 사용자 —
	# 꺾이는 곳에서도 세 명이 일렬로 서던 것). 그림 속 호스의 끝끼리 맞추므로 호스가 이어져 보인다 (HoseDraw.chain_spots)
	var cell_m := sim.units.cell_size_m
	var stands := {}
	for anim_name: String in line_names:
		stands[anim_name] = art.stand(anim_name)
		if HoseDraw.DROP_ANIM.has(anim_name):
			stands[HoseDraw.DROP_ANIM[anim_name]] = art.stand(str(HoseDraw.DROP_ANIM[anim_name]))
	var at_level := lead.level
	var clear := func(from: Vector2, to: Vector2) -> bool: return _floor_clear(at_level, from, to)
	var trail := HoseDraw.trail(hose, at_level, lp)
	var chain := HoseDraw.chain_spots(lp, k, line_names, stands, cell_m, trail, clear,
		float(HoseDraw.style().get("chain_near_m", 0.6)) / cell_m)
	# 줄에 선 사람만 (꺾인 곳에서는 줄이 2번에서 끊긴다 — 2번은 호스가 바닥으로 떨어지는 그림으로 바뀌어 있다)
	var chained: int = (chain.spots as Array).size()
	for i in chained:
		out.anims[line[i].id] = chain.names[i]
		out.spots[line[i].id] = chain.spots[i]
		out.ks[line[i].id] = chain.ks[i]
	# 바닥 호스는 맨 뒤 사람의 그림 속 호스가 끝나는 곳까지만 그린다 (그 앞은 그림에 들어 있다)
	if chain.has("tail") and not trail.is_empty():
		var first: float = trail.dist[0]
		var end: float = trail.dist[trail.dist.size() - 1]
		out.ground_tail = chain.tail.pos
		out.tail_dir = chain.tail.dir
		out.tail_h = chain.tail.h_m
		out.ground_end = clampf(_tail_dist(trail, chain.tail.pos, float(chain.tail.h_m), chain.spots[chain.spots.size() - 1], cell_m), first, end)
	# 줄에서 빠진 사람(꺾인 곳의 3번)은 호스를 정리하며 호스를 따라 앞뒤로 움직인다
	if chained < line.size() and not trail.is_empty():
		_spray_tidy(out, line.slice(chained), art, trail, chain.spots, float(out.get("ground_end", trail.dist[trail.dist.size() - 1])), cell_m, alpha)
	return out


## 방수 중 호스 정리 (2026-11-24 사용자: 꺾인 곳에서는 3번이 호스 전개 때처럼 호스를 정리하며 호스 앞뒤로 움직인다).
## 줄에서 빠진 사람(loose)을 깔린 호스 길 위에 세운다: 2번 뒤(ground = 바닥 호스가 2번 그림에 닿는 거리)에서 spray_tidy_near_m 물러난 곳과
## 거기서 spray_tidy_range_m 더 뒤 사이를 낮은 자세로 오가고, 양 끝에서 잠깐 멈춘다. 줄에 선 사람(taken 자리)과는 chain_min_sep_m 넘게 떨어진다.
## 시간은 현장 시간 — 일시정지하면 멈춘다. 호스가 짧아 설 자리가 없으면 아무것도 하지 않는다 (그 사람은 제자리에 서 있다).
## out 에 anims·spots·ks 와 walk {대원 id: 걷는 중인가} 를 넣는다
func _spray_tidy(out: Dictionary, loose: Array[Firefighter], art: SpriteArt.SpriteSet, trail: Dictionary, taken: Array, ground: float, cell_m: float, alpha: float) -> void:
	if art.frames("crouch_walk") <= 0:
		return
	var st := HoseDraw.style()
	var first: float = trail.dist[0]
	var end: float = trail.dist[trail.dist.size() - 1]
	var sep := float(st.get("chain_min_sep_m", 1.2)) / cell_m
	var near := ground - float(st.get("spray_tidy_near_m", 1.0)) / cell_m
	while near > first:
		var apart := true
		for q: Vector2 in taken:
			apart = apart and HoseDraw.point_at(trail, near).distance_to(q) >= sep
		if apart:
			break
		near -= 0.25
	if near < first + 0.5:
		return
	var far := maxf(first + 0.5, near - float(st.get("spray_tidy_range_m", 2.5)) / cell_m)
	var speed := maxf(0.05, float(st.get("spray_tidy_speed_mps", 0.5)))
	var dwell := maxf(0.0, float(st.get("spray_tidy_dwell_s", 2.0)))
	var walk_s := (near - far) * cell_m / speed
	var now := (sim.clock.tick + alpha) * SimClock.TICK_DT
	out.walk = {}
	for n in loose.size():
		var ff := loose[n]
		# 가까운 끝에서 멈춤 → 뒤로 걷기 → 먼 끝에서 멈춤 → 앞으로 걷기
		var t := fposmod(now + ff.id * 1.7, 2.0 * (walk_s + dwell)) if walk_s + dwell > 0.0 else 0.0
		var d := near
		var forward := true
		var walking := false
		if walk_s >= 0.5:
			if t < dwell:
				pass
			elif t < dwell + walk_s:
				d = lerpf(near, far, (t - dwell) / walk_s)
				forward = false
				walking = true
			elif t < 2.0 * dwell + walk_s:
				d = far
				forward = false
			else:
				d = lerpf(far, near, (t - 2.0 * dwell - walk_s) / walk_s)
				walking = true
		# 둘째부터는 더 뒤에서
		d = maxf(first, d - n * sep)
		var along := HoseDraw.point_at(trail, minf(end, d + 0.6)) - HoseDraw.point_at(trail, maxf(first, d - 0.6))
		if along.length_squared() < 0.0001:
			continue
		out.anims[ff.id] = "crouch_walk"
		out.spots[ff.id] = HoseDraw.point_at(trail, d)
		out.ks[ff.id] = SpriteArt.dir8(along if forward else -along)
		out.walk[ff.id] = walking and not sim.clock.paused


## 문 앞 방수태세(E4)일 때 바닥 호스가 끝나는 곳 {ground_end, ground_tail, tail_dir, tail_h} — 관창수가 겨눈 관창의 결합구. 아니면 빈 것
func _ready_hose_end(crew: Crew, art: SpriteArt.SpriteSet, hose: HoseLine) -> Dictionary:
	if sim.doors.tasks.is_empty() and sim.cards.checking_door(crew.id) == null:
		return {}
	var rl := _door_ready_layout(crew, art)
	var back: Variant = HoseDraw.end_of("spray_ln", "back")
	if rl.is_empty() or back == null or crew.leader == null:
		return {}
	var cell_m := sim.units.cell_size_m
	var facing := Vector2.RIGHT.rotated(int(rl.k) * PI / 4.0)
	var spot: Vector2 = rl.spot
	var trail := HoseDraw.trail(hose, crew.leader.level, UnitsView.display_pos(crew.leader, 0.0))
	if trail.is_empty():
		return {}
	var tail := HoseDraw.end_spot(spot, facing, back, cell_m)
	return {"ground_tail": tail, "tail_dir": facing, "tail_h": (back as Vector3).z,
		"ground_end": clampf(_tail_dist(trail, tail, (back as Vector3).z, spot, cell_m), float(trail.dist[0]), float(trail.dist[trail.dist.size() - 1]))}


## 바닥 호스가 끝나는 거리 (칸): 그림 속 호스의 끝(tail)과 가장 가까운 호스 길 위의 곳.
## 끝이 바닥이 아니면 (관창수가 혼자 든 관창의 결합구 — 몸 앞에 있다) 그 사람 뒤 0.3m 에서 바닥을 떠나 올라간다
func _tail_dist(trail: Dictionary, tail: Vector2, h_m: float, spot: Vector2, cell_m: float) -> float:
	if h_m > 0.3:
		return HoseDraw._trail_dist(trail, spot) - 0.3 / cell_m
	return HoseDraw._trail_dist(trail, tail)


## 두 자리(칸 좌표) 사이가 걸을 수 있는 바닥으로 이어져 있는가 (벽·빈 곳을 지나지 않는가)
func _floor_clear(at_level: int, from: Vector2, to: Vector2) -> bool:
	var n := maxi(1, ceili(from.distance_to(to) / 0.25))
	for s in n + 1:
		var p := from.lerp(to, float(s) / n)
		if not sim.building.is_walkable(at_level, floori(p.x), floori(p.y)):
			return false
	return true


## 잠긴 문을 부수는 중인가 (그 문 가까이에서, 사람이 모자라 기다리는 중이 아닐 때)
func _forcing(task: DoorSystem.Task, ff: Firefighter) -> bool:
	if not task.open or task.waiting_people or task.opening == null or not task.opening.locked or task.opening.cells.is_empty():
		return false
	# 문 옆에서 기다리는 분대는 문을 부수지 않는다 (2026-11-24 — 두 분대가 같은 두 자리에 겹쳐 그려졌다)
	if task.stacked(ff.crew_id):
		return false
	return ff.level == task.opening.level and ff.pos.distance_to(door_center(task.opening)) <= 3.5


## 문 칸들의 가운데 (칸 좌표)
static func door_center(o: Opening) -> Vector2:
	var c := Vector2.ZERO
	for cell in o.cells:
		c += Vector2(cell) + Vector2(0.5, 0.5)
	return c / maxf(1.0, o.cells.size())


## 문 개방 배치 (A1): 대원이 서 있는 쪽에서 문을 보는 방향(축 방향 4개 중 하나)과, 그쪽 벽면의 문틈(문 가운데).
## 문이 여러 칸이면 벽은 그 칸들이 놓인 방향이고 보는 방향은 그에 수직이다. → {k 방향(8방향), facing, seam 칸 좌표}
static func force_frame(o: Opening, from: Vector2) -> Dictionary:
	var center := door_center(o)
	var v := center - from
	var facing := Vector2.ZERO
	if o.cells.size() > 1:
		var along := Vector2(o.cells[o.cells.size() - 1] - o.cells[0])
		facing = Vector2(-along.y, along.x).normalized()
		if facing.dot(v) < 0.0:
			facing = -facing
	elif absf(v.x) >= absf(v.y):
		facing = Vector2(signf(v.x) if v.x != 0.0 else 1.0, 0.0)
	else:
		facing = Vector2(0.0, signf(v.y))
	return {"k": SpriteArt.dir8(facing), "facing": facing, "seam": center - facing * 0.5}


## 구울 때 적은 자리(기준점에서 보는 방향으로 fwd_m, 오른쪽으로 right_m)를 칸 좌표로 (cell_m = 칸 한 변 m)
static func stand_spot(seam: Vector2, facing: Vector2, stand: Dictionary, cell_m: float) -> Vector2:
	var right := facing.rotated(PI / 2.0)
	return seam + (facing * float(stand.get("fwd_m", 0.0)) + right * float(stand.get("right_m", 0.0))) / maxf(0.01, cell_m)


## 그 조가 이 문을 부수는 배치: {k, seam, spots {대원 id: 칸 좌표}, anims {대원 id: 동작}} — 조장 force_a, 짝 force_b
func _force_layout(task: DoorSystem.Task, crew: Crew, art: SpriteArt.SpriteSet) -> Dictionary:
	var fr := force_frame(task.opening, crew.leader.pos)
	var out := {"k": fr.k, "seam": fr.seam, "spots": {}, "anims": {}}
	var names := ["force_a", "force_b"]
	# 문을 젖히는 두 사람: 2인 조는 조장·짝, 분대(일하는 조원 3명 이상)는 둘째·셋째 —
	# 선두(관창수·팀장)는 문 앞에서 기다린다 (2026-11-16 결정, 방수태세 그림은 나중에)
	var workers: Array[Firefighter] = crew.workers()
	var order: Array[Firefighter] = workers.duplicate()
	if workers.size() >= 3:
		order = workers.slice(1)
		order.append(workers[0])
	var n := 0
	for ff in order:
		if ff.incapacitated or n >= 2:
			continue
		var anim: String = names[n]
		out.anims[ff.id] = anim
		out.spots[ff.id] = stand_spot(fr.seam, fr.facing, art.stand(anim), sim.units.cell_size_m)
		n += 1
	return out


# --- 운반 배치 (2026-11-15) ---

## 운반 배치의 자리 (칸). mode "lift" = 2인 운반(사지운반법): 앞사람 = 조장, 뒷사람 = 짝, 옮겨지는 사람은 그 사이에 들려 있다 /
## "drag" = 1인 운반(구조대상자 끌기): 조장이 끌고, 옮겨지는 사람은 뒤에 바닥으로, 짝은 앞에서 길을 살핀다. dir = 가는 방향.
## → {partner 짝의 자리, victim 옮겨지는 사람의 자리, victim_h 그 높이(m)}. 거리·높이는 data/art.json carry_layout
static func carry_spots(mode: String, lead: Vector2, dir: Vector2, cfg: Dictionary) -> Dictionary:
	if mode == "lift":
		var gap := float(cfg.get("lift_gap_cells", 3.0))
		return {"partner": lead - dir * gap, "victim": lead - dir * gap * 0.5, "victim_h": float(cfg.get("lift_height_m", 0.55))}
	return {"partner": lead + dir * float(cfg.get("drag_partner_cells", 1.6)),
		"victim": lead - dir * float(cfg.get("drag_victim_cells", 1.9)), "victim_h": float(cfg.get("drag_height_m", 0.05))}


## 운반 방식: 조장이 낮은 자세(연기층 아래)이거나 짝이 없으면 끌기, 아니면 2인 운반
static func carry_mode(crew: Crew) -> String:
	# 들 사람이 둘이 안 되면 끌기 (분대는 일하는 조원 중 움직일 수 있는 사람 수)
	var solo := crew.able_workers() < 2
	return "drag" if (crew.leader.crouched or solo) else "lift"


## 그 조가 누군가를 옮기는 중이면 배치 {mode, k 가는 방향(8방향), dir, lead, partner, victim, victim_h, kind, target}, 아니면 빈 것
func _carry_layout(crew: Crew, alpha: float) -> Dictionary:
	var task := sim.rescue.task_of_crew(crew.id)
	if not (task is RescueSystem.CarryTask and task.carrying):
		return {}
	var k := int(_facing.get(crew.leader.id, 1))
	var dir := Vector2.RIGHT.rotated(k * PI / 4.0)
	var lead := UnitsView.display_pos(crew.leader, alpha)
	var mode := carry_mode(crew)
	var out := carry_spots(mode, lead, dir, SpriteArt.config().get("carry_layout", {}))
	out.merge({"mode": mode, "k": k, "dir": dir, "lead": lead, "kind": task.kind, "target": task.target_id, "victim_anim": ""})
	# 2인 운반 (A2, 2026-11-15 사용자가 블렌더에서 확인): 구울 때 적은 자리 — 기준점 = 앞사람(조장), 뒷사람·구조대상자는 그 뒤
	if mode == "lift":
		var crew_art := SpriteArt.get_set(str(SpriteArt.config().get("crew", "")))
		var cell_m := sim.units.cell_size_m
		if crew_art != null and not crew_art.stand("lift_b").is_empty():
			out.partner = stand_spot(lead, dir, crew_art.stand("lift_b"), cell_m)
		if task.kind == "victim":
			var vart := SpriteArt.victim_set(sim.rescue.victims[task.target_id].label())
			if vart != null and vart.frames("lift_v") > 0:
				out.victim = stand_spot(lead, dir, vart.stand("lift_v"), cell_m)
				out.victim_h = 0.0
				out.victim_anim = "lift_v"
				out.victim_dir = k
	# 1인 운반 = 끌기 (A3, 2026-11-15 사용자가 블렌더에서 확인): 장면에서 대원은 구조대상자를 본다(가는 방향의 반대) —
	# 구조대상자 자리는 대원이 보는 쪽으로 구운 거리만큼
	elif task.kind == "victim":
		var vart := SpriteArt.victim_set(sim.rescue.victims[task.target_id].label())
		if vart != null and vart.frames("drag_v") > 0:
			out.victim = stand_spot(lead, -dir, vart.stand("drag_v"), sim.units.cell_size_m)
			out.victim_h = 0.0
			out.victim_anim = "drag_v"
			out.victim_dir = posmod(k + 4, 8)
	return out


## 그 대원이 옮겨지는 중(쓰러진 대원 구출)이면 그 배치
func _ff_carry_layout(ff: Firefighter, alpha: float) -> Dictionary:
	if not ff.incapacitated:
		return {}
	for t in sim.rescue.carries:
		if t.carrying and t.kind == "ff" and t.target_id == ff.id:
			return _carry_layout(sim.units.get_crew(t.crew_id), alpha)
	return {}


## 문을 확인·열거나(B1) 부수는(A1) 조원이 서는 자리 (칸 좌표). 그 일을 하는 조원이 아니면 null.
## 조건은 자세(_unit_pose)의 문 확인·개방·파괴와 같다 — 자세와 자리가 서로 다른 배치에서 나오지 않게
func _door_work_spot(ff: Firefighter, crew: Crew, art: SpriteArt.SpriteSet) -> Variant:
	if crew == null or art == null or (sim.doors.tasks.is_empty() and sim.cards.checking_door(crew.id) == null):
		return null
	var dl := _door_check_layout(crew, art)
	if not dl.is_empty() and int(dl.opener) == ff.id:
		return dl.spot
	var dt := sim.doors.task_of_crew(crew.id)
	if dt != null and _forcing(dt, ff) and art.frames("force_a") > 0:
		var lay := _force_layout(dt, crew, art)
		if lay.spots.has(ff.id):
			return lay.spots[ff.id]
	return null


## 대원을 그리는 자리: 보통은 실제 자리, 운반 중인 짝·옮겨지는 대원·문을 부수는 대원은 배치 자리
func _shown_pos(ff: Firefighter, alpha: float) -> Vector2:
	var p := UnitsView.display_pos(ff, alpha)
	if not ff.incapacitated and not sim.water.hoses.is_empty():
		# 호스 꺼내기 (E1): 1번·2번은 차 후면 앞 정해진 자리에
		var fc := sim.units.get_crew(ff.crew_id)
		var fh := sim.water.held_hose(fc.id) if fc != null else null
		if fh != null and fh.fetch_until >= 0:
			var fart := SpriteArt.get_set(str(SpriteArt.config().get("crew", ""))) if not thermal else null
			var fl := _hose_fetch_layout(fc, fart)
			if not fl.is_empty() and fl.spots.has(ff.id):
				return fl.spots[ff.id]
	if not ff.incapacitated and not sim.water.hoses.is_empty():
		var sc := sim.units.get_crew(ff.crew_id)
		if sc != null and sc.leader != ff:
			var sart := SpriteArt.get_set(str(SpriteArt.config().get("crew", ""))) if not thermal else null
			# 문을 확인·열거나 부수는 조원은 문 앞 자리가 먼저다 — 자세(_unit_pose)가 문 동작을 방수 줄·호스 끼고 걷기보다 먼저 고르므로
			# 자리도 같은 순서로 (2026-11-24 사용자: 호스를 가진 조가 문을 열 때 관창수만 문 앞에 남고 다른 조원이 사라졌다 —
			# 문 여는 자세를 한 채 호스 길 위 자리(문에서 몇 칸 뒤, 펌프차 쪽)에 그려졌다)
			var ds: Variant = _door_work_spot(ff, sc, sart)
			if ds != null:
				return ds
			# 문 개방 중인 분대의 나머지 조원은 경첩 쪽 문 정면 띠 밖에 줄을 선다 (2026-11-24) — 호스 길 위(문 정면일 수 있다)가 아니라
			var dtl := _door_team_layout(sc, sart)
			if dtl.get("spots", {}).has(ff.id):
				return dtl.spots[ff.id]
			var sl := _spray_layout(sc, sart, alpha)
			if not sl.is_empty():
				return sl.spots.get(ff.id, p)
			# 호스 끼고 걷기: 2·3번은 호스가 깔린 길 위, 1번 뒤 정해진 거리에
			var hl := _hose_carry_layout(sc, sart, alpha)
			if not hl.is_empty():
				return hl.spots.get(ff.id, p)
	if not ff.incapacitated:
		var hp := _helper_pose(ff)
		if not hp.is_empty():
			return hp.pos
	if not sim.ems.patients.is_empty() and not ff.incapacitated:
		var ec := sim.units.get_crew(ff.crew_id)
		if ec != null:
			var eart := SpriteArt.crew_set(sim.units.squads[ec.squad_id].type) if not thermal else null
			var al := _aid_layout(ec, eart, alpha)
			if not al.is_empty():
				return al.spots.get(ff.id, p)
			var el := _ems_carry_layout(ec, eart, alpha)
			if not el.is_empty():
				return el.spots.get(ff.id, p)
	if not ff.incapacitated and (not sim.doors.tasks.is_empty() or sim.cards.checking_door(ff.crew_id) != null):
		var dc := sim.units.get_crew(ff.crew_id)
		var dart := SpriteArt.crew_set(sim.units.squads[dc.squad_id].type) if dc != null and not thermal else null
		var dl := _door_check_layout(dc, dart)
		if not dl.is_empty() and int(dl.opener) == ff.id:
			return dl.spot
		# 호스 없는 조(구조대 등)의 조원도 문 개방 중에는 경첩 쪽 문 정면 띠 밖에 줄을 선다 (2026-11-24)
		if dc != null and dc.leader != ff:
			var dtl := _door_team_layout(dc, dart)
			if dtl.get("spots", {}).has(ff.id):
				return dtl.spots[ff.id]
		# 문 앞 방수태세 (E4): 관창수는 문 옆 정해진 자리에
		if dc != null and dc.leader == ff and not sim.water.hoses.is_empty():
			var rl := _door_ready_layout(dc, dart)
			if not rl.is_empty():
				return rl.spot
		# 호스 없는 조(구조대 등)의 선두는 방수태세 자리처럼 문에서 물러나 기다린다
		if dc != null and dc.leader == ff:
			var lw: Variant = _door_lead_wait_spot(dc, dart)
			if lw != null:
				return lw
		var wl := _window_layout(dc, dart)
		if not wl.is_empty() and int(wl.breaker) == ff.id:
			return wl.spot
	if not ff.incapacitated and not sim.gas.workers.is_empty():
		var gc := sim.units.get_crew(ff.crew_id)
		if gc != null and gc.leader == ff:
			var gart := SpriteArt.crew_set(sim.units.squads[gc.squad_id].type) if not thermal else null
			var gl := _gas_layout(gc, gart)
			if not gl.is_empty():
				return gl.spot
	if not ff.incapacitated and not sim.rekindle.tasks.is_empty():
		var oc := sim.units.get_crew(ff.crew_id)
		if oc != null and oc.partner == ff:
			var oart := SpriteArt.crew_set(sim.units.squads[oc.squad_id].type) if not thermal else null
			var ol := _overhaul_layout(oc, oart, alpha)
			if not ol.is_empty():
				return ol.spots.get(ff.id, p)
	if not sim.rescue.searches.is_empty() and not ff.incapacitated:
		var scr := sim.units.get_crew(ff.crew_id)
		if scr != null and scr.leader != ff:
			var art0 := SpriteArt.get_set(str(SpriteArt.config().get("crew", ""))) if not thermal else null
			var srl := _search_layout(scr, art0, alpha)
			if not srl.is_empty():
				return srl.spots.get(ff.id, p)
	if not sim.doors.tasks.is_empty() and not ff.incapacitated:
		var dt := sim.doors.task_of_crew(ff.crew_id)
		if dt != null and _forcing(dt, ff):
			var art := SpriteArt.get_set(str(SpriteArt.config().get("crew", ""))) if not thermal else null
			if art != null and art.frames("force_a") > 0:
				var lay := _force_layout(dt, sim.units.get_crew(ff.crew_id), art)
				return lay.spots.get(ff.id, p)
	if sim.rescue.carries.is_empty():
		return p
	if ff.incapacitated:
		var held := _ff_carry_layout(ff, alpha)
		return held.victim if not held.is_empty() else p
	var crew := sim.units.get_crew(ff.crew_id)
	if crew != null and crew.leader != ff and crew.mate() == ff:
		var lay := _carry_layout(crew, alpha)
		if not lay.is_empty():
			return lay.partner
	return p


## 구조대상자를 그리는 자리: 옮겨지는 중이면 배치 자리
func _victim_shown_pos(v: Victim, alpha: float) -> Vector2:
	if v.carried_by < 0:
		return v.pos
	var lay := _carry_layout(sim.units.get_crew(v.carried_by), alpha)
	return lay.victim if not lay.is_empty() else v.pos


## 요구조자 그림 자세 [동작, 방향, 장, 색] — 실제 그림과 테두리가 같은 것을 쓴다
func _victim_pose(v: Victim, art: SpriteArt.SpriteSet) -> Array:
	var walking := sim.evac.paths.has(v.id) and v.state == Victim.State.CONSCIOUS
	var standing := v.state == Victim.State.CONSCIOUS
	var anim := "walk" if walking else ("idle" if standing else "down_up")
	# 구조 요청 (B8, 2026-11-16 사용자가 블렌더에서 확인): 창가 요구조자가 의식이 있으면 창밖으로 몸을 내밀어 두 팔을 흔든다
	if v.jumper and standing and not walking and v.carried_by < 0 and art.frames("wave") > 0:
		anim = "wave"
	var tint := Color(0.55, 0.55, 0.6) if v.state == Victim.State.DEAD else Color.WHITE
	return [anim, (v.id * 3) % 8, SpriteArt.frame_at(anim, art.frames(anim), v.id * 0.5), tint]


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
	_contact_shadow(feet, 10, 5, 0.3)
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
	_contact_shadow(feet, 10, 5, 0.3)
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

## 수관: 물이 차기 전에는 납작한 띠, 찬 뒤에는 통통한 관, 1본마다 결합구 (HoseDraw — docs/motions.md D1·D2·D4)
func _draw_hoses(alpha := 0.0) -> void:
	var to_screen := func(p: Vector2) -> Vector2: return proj.to_screen(p, 0.03)
	var one: float = sim.water.hose_length_cells()
	# 높이 1m가 화면에서 올라가는 거리 — 부푼 호스를 반지름만큼 띄워 그린다
	var up := proj.to_screen(Vector2.ZERO, 1.0) - proj.to_screen(Vector2.ZERO, 0.0)
	var art := SpriteArt.get_set(str(SpriteArt.config().get("crew", ""))) if not thermal else null
	for h in sim.water.hoses:
		var lay := HoseDraw.layout(h, sim.units.get_vehicle(h.vehicle_id), sim.building)
		# 호스 끼고 걷는 중: 바닥 호스는 2번 뒤에서 끝나고 3번이 들어 올린 구간은 비운다 (그 부분은 대원 그림에 들어 있다)
		var hose_crew := sim.units.get_crew(h.crew_id)
		var carry := _hose_carry_layout(hose_crew, art, alpha) if not h.charged else {}
		# 방수 중: 바닥 호스는 맨 뒤 사람의 그림 속 호스가 바닥에 닿은 곳에서 끝난다 (2026-11-24 — 전에는 관창수 발밑까지 그려 그림과 어긋났다)
		if carry.is_empty() and hose_crew != null and art != null and h.flowing:
			carry = _spray_layout(hose_crew, art, alpha)
		# 문 앞 방수태세 (E4): 관창수가 문 옆에서 겨눈 관창의 결합구까지 호스가 올라간다.
		# 이때 다른 조원은 문을 열고 있어 호스를 끼고 있지 않다 — 끼고 걷기 배치보다 먼저 본다
		if hose_crew != null and art != null and not h.flowing and h.fetch_until < 0:
			var ready_end := _ready_hose_end(hose_crew, art, h)
			if not ready_end.is_empty():
				carry = ready_end
		if carry.has("ground_end") or carry.has("gap"):
			lay = lay.duplicate()
			if carry.has("ground_end"):
				lay.ground_end = carry.ground_end
				lay.ground_tail = carry.ground_tail
				if carry.has("tail_dir"):
					lay.tail_dir = carry.tail_dir
					lay.tail_h = float(carry.get("tail_h", 0.0))
			if carry.has("gap"):
				lay.gap = carry.gap
		HoseDraw.draw(self, h, level, to_screen, IsoProjection.PX_PER_M, sim.building.cell_size_m, h.water_head, one, up, lay)


## 열린 후면 셔터 (2026-11-22 사용자 결정: 차 그림을 다시 굽지 않고 게임에서 덧그린다 — 펌프차는 후면 셔터 안에 접어 쌓은 호스와
## 동작 패널이 있다). fp = [뒤 왼쪽, 앞 왼쪽, 앞 오른쪽, 뒤 오른쪽], h = 차 높이(m). 후면이 화면 뒤쪽을 보면 그리지 않는다.
## 크기·색은 data/ui/hose_style.json shutter_*
func _draw_open_shutter(fp: PackedVector2Array, h: float) -> void:
	if ((fp[0] + fp[3]) * 0.5 - (fp[1] + fp[2]) * 0.5).dot(Vector2.ONE) <= 0.0:
		return
	var st := HoseDraw.style()
	var side := float(st.get("shutter_side_ratio", 0.08))
	var a := fp[0].lerp(fp[3], side)
	var b := fp[0].lerp(fp[3], 1.0 - side)
	var bottom := float(st.get("shutter_bottom_m", 0.85))
	var top := minf(float(st.get("shutter_top_m", 2.05)), h - 0.1)
	if top <= bottom:
		return
	var quad := func(from: Vector2, to: Vector2, z0: float, z1: float) -> PackedVector2Array:
		return PackedVector2Array([proj.to_screen(from, z0), proj.to_screen(to, z0), proj.to_screen(to, z1), proj.to_screen(from, z1)])
	# 열린 칸 (어두운 안쪽)
	draw_colored_polygon(quad.call(a, b, bottom, top), Color(str(st.get("shutter_dark_color", "#0e0e11"))))
	# 접어 쌓은 호스
	var rows := int(st.get("shutter_stack_rows", 7))
	var pitch := float(st.get("shutter_stack_pitch_m", 0.07))
	var stack_to := float(st.get("shutter_stack_ratio", 0.72))
	var hose_color := Color(str(st.get("flat_color", "#cfc5a8")))
	for i in rows:
		var z0 := bottom + 0.1 + i * pitch
		if z0 + pitch * 0.65 > top:
			break
		draw_colored_polygon(quad.call(a.lerp(b, 0.04), a.lerp(b, stack_to), z0, z0 + pitch * 0.65), hose_color)
	# 동작 패널
	draw_colored_polygon(quad.call(a.lerp(b, stack_to + 0.06), a.lerp(b, 0.96), bottom + 0.15, minf(top - 0.1, bottom + 0.75)),
		Color(str(st.get("shutter_panel_color", "#73787f"))))
	# 말려 올라간 셔터
	draw_colored_polygon(quad.call(a, b, top, minf(h, top + 0.14)), Color(str(st.get("shutter_roll_color", "#9ea3a8"))))


func _draw_vehicle(v: Vehicle, alpha: float) -> void:
	var center := v.prev_pos.lerp(v.pos, alpha)
	var fp := v.footprint(center)
	var h := minf(v.height_m, VEHICLE_CUT_M)
	var color := THERMAL_FURNITURE if thermal else v.color
	color.a = VEHICLE_ALPHA
	var art := SpriteArt.vehicle_set(v.type) if not thermal else null
	# 달리는 중이면 바퀴가 도는 동작 (그 그림이 구워져 있는 차량만, 2026-11-12 사용자 결정)
	var anim := "drive" if art != null and v.is_moving() and art.frames("drive") > 0 else "idle"
	var frame := SpriteArt.frame_at(anim, art.frames(anim), v.id * 0.5) if art != null else 0
	if art != null and art.draw(self, anim, SpriteArt.dir8(v.heading), frame, proj.to_screen(center, 0.0), Color(1, 1, 1, VEHICLE_ALPHA)):
		_vehicle_details_sprite(v, center)
	else:
		_prism(fp, 0.0, h, color)
		# 앞쪽 1/4 운전석 지붕
		var cab := PackedVector2Array([fp[0].lerp(fp[1], 0.75), fp[1], fp[2], fp[3].lerp(fp[2], 0.75)])
		draw_colored_polygon(_lift(cab, h), Color(color.darkened(0.35), VEHICLE_ALPHA))
		if not thermal:
			_vehicle_details(v, fp, h)
	if not thermal:
		# 분대가 호스를 꺼내는 동안 후면 셔터가 열려 있다 (docs/motions.md E1 — 차 후면이 카메라 쪽을 볼 때만 보인다)
		for hz in sim.water.hoses:
			if hz.vehicle_id == v.id and hz.fetch_until >= 0:
				_draw_open_shutter(fp, h)
				break
	if not thermal:
		# 운전원 작업 진행 막대 (기획안 6-1)
		var wp := sim.water.work_progress(v)
		if wp >= 0.0:
			var top := proj.to_screen(center, h + 1.2)
			draw_rect(Rect2(top + Vector2(-30, 0), Vector2(60, 6)), Color(0.1, 0.1, 0.1, 0.8))
			draw_rect(Rect2(top + Vector2(-30, 0), Vector2(60 * wp, 6)), Color("ffb74d"))
			draw_string(ThemeDB.fallback_font, top + Vector2(-50, -4), "%s %d초" % [v.work.label, ceili(float(v.work.remain))], HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color("ffe0b2"))
		# 분대가 후면에서 호스를 꺼내는 중 (docs/motions.md E1): 차 후면 위에 진행 막대 (여러 분대면 위로 쌓는다)
		var row := 0
		for hz in sim.water.hoses:
			if hz.vehicle_id != v.id or hz.fetch_until < 0 or hz.fetch_ticks <= 0:
				continue
			var left := maxi(0, hz.fetch_until - sim.clock.tick)
			var at := proj.to_screen(v.rear_point(0.0, 0.0, center), h + 0.4) + Vector2(0, -20.0 * row)
			draw_rect(Rect2(at + Vector2(-30, 0), Vector2(60, 6)), Color(0.1, 0.1, 0.1, 0.8))
			draw_rect(Rect2(at + Vector2(-30, 0), Vector2(60 * (1.0 - float(left) / hz.fetch_ticks), 6)), Color("ffb74d"))
			draw_string(ThemeDB.fallback_font, at + Vector2(-50, -4), "수관 준비 %d초" % ceili(left * SimClock.TICK_DT), HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color("ffe0b2"))
			row += 1
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
	# 불빛 위치는 차종별 그림의 경광등 막대에 맞춘다 (data/art.json vehicle_lightbar, 2026-11-12)
	var bars: Dictionary = SpriteArt.config().get("vehicle_lightbar", {})
	var bar: Dictionary = bars.get(v.type, bars.get("default", {}))
	var front := center + v.heading * v.length_cells * float(bar.get("forward", 0.3))
	var side := Vector2(-v.heading.y, v.heading.x) * v.width_cells * float(bar.get("side", 0.2))
	var h := float(bar.get("h_m", v.height_m)) + 0.05
	draw_circle(proj.to_screen(front + side, h), 4.0, Color("ef4444") if on else Color("7f1d1d"))
	draw_circle(proj.to_screen(front - side, h), 4.0, Color("3b82f6") if not on else Color("1e3a8a"))


func _draw_sprays(alpha: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for h in sim.water.hoses:
		# 실제로 물이 나간 틱만 그린다 (HoseLine.spraying, 2026-11-24 — 전에는 방수 위치로 걸어가는 동안에도 예전 자리로 물줄기가 남았다)
		if not h.flowing or h.flow_fraction <= 0.0 or not h.spraying:
			continue
		var leader := sim.units.get_crew(h.crew_id).leader
		if leader.level != level:
			continue
		# 외부 보기: 건물 안에서 쏘는 물은 외관에 가려진다
		if _outside() and not sim.building.cell(level, floori(leader.pos.x), floori(leader.pos.y)) in BuildingData.OUTDOOR:
			continue
		var from := proj.to_screen(UnitsView.display_pos(leader, alpha), NOZZLE_M)
		# 물줄기는 관창수 그림의 관창 끝에서 시작한다 (2026-11-12 사용자 지적: 몸에서 물이 나갔음) — 구울 때 기록한 위치
		var crew_art := SpriteArt.get_set(str(SpriteArt.config().get("crew", ""))) if not thermal else null
		if crew_art != null and not h.approaching:
			var feet := proj.to_screen(UnitsView.display_pos(leader, alpha), 0.0)
			var nanim := "spray_n" if crew_art.frames("spray_n") > 0 else "spray"
			if leader.crouched and crew_art.frames("spray_ln") > 0:
				nanim = "spray_ln"
			var fr := SpriteArt.frame_at(nanim, crew_art.frames(nanim), leader.id * 0.37)
			from = feet + crew_art.nozzle_offset(nanim, SpriteArt.dir8(h.aim - leader.pos), fr, from - feet)
		var to := proj.to_screen(h.impact, IMPACT_M)
		# 경계 관창이 창·외벽으로 올려 쏜다 (2026-11-24): 끝은 그 층 창 높이의 벽면, 줄기는 위로 휘어 오른다
		var arc_px := 0.0
		var on_wall := false
		if h.exterior:
			to = _exterior_hit(h)
			arc_px = from.distance_to(to) * float(HoseDraw.style().get("exterior_arc_ratio", 0.12))
			on_wall = true
		# 물줄기 그림 (사용자 참고 그림, 2026-11-12): 직사는 가는 줄기와 튀는 물, 그 밖(분무 등)은 원뿔 물안개. 없으면 아래 도형
		var straight := h.pattern == HoseLine.Pattern.STRAIGHT
		var spread := 0.0 if straight else sim.water.radius_cells(h.pattern) * IsoProjection.HALF_W
		if not thermal and FxArt.draw_water(self, from, to, straight, spread, Color(0.88, 0.95, 1.0, 0.95), h.crew_id, arc_px, on_wall):
			continue
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
			# 관창이 목표 칸 바로 앞이면 물줄기 삼각형이 넓이 0이 된다 (그리기 경고 'triangulation failed') — 원만 그린다
			if from.distance_to(to) > 1.0:
				draw_colored_polygon(PackedVector2Array([from, to + side, to - side]), PlanStyle.FOG_COLOR)
			_fill(_ellipse(to, r, r * 0.5), Color(PlanStyle.FOG_COLOR, 0.25))


## 경계 관창의 물이 맞는 곳 (화면 좌표): 겨눈 창·외벽의 벽면, 그 층 창 높이.
## 외부 보기에서는 외관의 그 층 높이(층이 많으면 줄여 그린 높이 — _shell), 내부 보기에서는 층 높이 그대로
func _exterior_hit(h: HoseLine) -> Vector2:
	var at := Vector2(h.target.x + 0.5, h.target.y + 0.5)
	var up_m := exterior_hit_height(h.target.z)
	if _outside():
		for w: Dictionary in _ext_windows.get(h.target.z, []):
			if Vector2i(h.target.x, h.target.y) in (w.o as Opening).cells:
				return _face_point(str(w.face), (float(w.a) + float(w.b)) * 0.5, up_m)
	return proj.to_screen(at, up_m)


## 그 층의 창 가운데 높이 (m, 맨 아래 층 바닥에서) — 외관에 그리는 층 높이를 따른다
func exterior_hit_height(target_level: int) -> float:
	var win := float(HoseDraw.style().get("exterior_window_m", 1.5))
	if target_level == _first_level:
		return win
	for s: Dictionary in _shell:
		if int(s.level) == target_level:
			return float(s.h0) + (float(s.h1) - float(s.h0)) * 0.55
	return (sim.building.floor_number(target_level) - sim.building.floor_number(_first_level)) * FLOOR_M + win


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
		_fill(face, Color(color.darkened(SOUTH_SHADE if n.y >= n.x else EAST_SHADE), color.a))
	_fill(_lift(base, h1), color)


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
	# 불에서 솟는 연기 기둥 (연기층보다 먼저 — 위쪽은 연기층에 묻힌다)
	var fires := _draw_fire_plumes()
	for c in rooms:
		# 천장을 다 덮기 전에는 출발점에서 선두까지 둥글게, 천장류 두께로만 (기획안 5-3-1)
		var layer_d := c.shown_layer_depth()
		var reach := c.smoke_reach_m if not c.smoke_covered() else INF
		var vis := sim.fire.visibility_m(c)
		var fade := 1.0
		if not p.room_visible(c):
			if p.room_seen[c.index] == 0:
				continue
			layer_d = p.room_seen_depth[c.index]
			vis = p.room_seen_visibility[c.index]
			reach = p.room_seen_reach[c.index]
			if reach < 1.0e5 and c.smoke_started():
				layer_d = minf(layer_d, c.jet_depth_m)
			else:
				reach = INF
			fade = 0.5
		var spread := Vector3(0, 0, -1)
		if reach < INF:
			spread = Vector3(c.smoke_origin.x, c.smoke_origin.y, reach / c.cell_m)
		layer_d = clampf(layer_d, 0.0, CEILING_M)
		if layer_d < 0.05:
			continue
		var density := 1.0 - clampf(vis / 10.0, 0.0, 1.0)
		var a := (SMOKE_MIN_ALPHA + SMOKE_DENSITY_ALPHA * density) * fade
		var r := c.rect
		var h := CEILING_M - layer_d
		# 연기 진하기 하나 (2026-11-12 사용자 결정): 위에서 보면 연기층 두께를 꿰뚫어 본다 → 두꺼울수록 진하다.
		# 커튼 천장 쪽·윗면 판이 같은 값을 쓴다
		var sp0 := stack.params
		var op := minf(sp0.smoke_max_opacity, 1.0 - exp(-sp0.smoke_opacity_k * (0.25 + 0.75 * density) * layer_d)) * fade
		# 화면에서 이 연기 상자(윗면 + 앞면)에 덮인 사람은 테두리로 — 어느 방 연기든 (2026-11-12 사용자 결정)
		if op >= stack.params.smoke_outline_opacity:
			_smoke_hulls.append(Geometry2D.convex_hull(PackedVector2Array([
				proj.to_screen(Vector2(r.position), CEILING_M), proj.to_screen(Vector2(r.end.x, r.position.y), CEILING_M),
				proj.to_screen(Vector2(r.end), CEILING_M), proj.to_screen(Vector2(r.position.x, r.end.y), CEILING_M),
				proj.to_screen(Vector2(r.end.x, r.position.y), h), proj.to_screen(Vector2(r.end), h),
				proj.to_screen(Vector2(r.position.x, r.end.y), h)])))
		if _draw_smoke_cloud(c, h, layer_d, a, density, fires, spread, op):
			if c.rollover and p.room_visible(c):
				_draw_rollover(r, h)
			continue
		# 덩어리 그림이 없을 때만 예전 판
		var plane := PackedVector2Array([
			proj.to_screen(Vector2(r.position), h), proj.to_screen(Vector2(r.end.x, r.position.y), h),
			proj.to_screen(Vector2(r.end), h), proj.to_screen(Vector2(r.position.x, r.end.y), h),
		])
		# 단면(남·동 앞면): 천장부터 연기층 아래 경계(중성대)까지 채워 연기층 두께가 보이게 한다 (R17)
		var front := Color(FireView.SMOKE_COLOR, minf(0.6, a + 0.1))
		_face_room("S", r, h, CEILING_M, front.darkened(SOUTH_SHADE))
		_face_room("E", r, h, CEILING_M, front.darkened(EAST_SHADE))
		_fill(plane, Color(FireView.SMOKE_COLOR, a * 0.65))
		_draw_smoke_texture(plane, r, a, c.index)
		plane.append(plane[0])
		draw_polyline(plane, Color(FireView.SMOKE_COLOR.darkened(0.3), minf(1.0, a + 0.15)), 1.5)
		if c.rollover and p.room_visible(c):
			_draw_rollover(r, h)
	if not _draw_smoke_spills():
		_draw_smoke_plumes()
	if _smoke_outline:
		_smoke_outline.queue_redraw()


## 연기층 = 천장에서부터 겹겹이 쌓이는 연기 덩어리 (Kenney Smoke Particles, 2026-11-12 사용자 결정).
## 잘린 앞면(남·동 가장자리): 천장부터 smoke_row_m 간격으로 줄을 겹쳐 쌓는다. 연기층이 두꺼워지면 아래에 새 줄이
##   옅게 생겨 진해지고, 맨 아래 줄은 연기층 하단을 따라 내려온다 — 쌓이며 내려오는 모습.
## 방 안쪽: 맨 아래 줄 하나만 옅게 (바닥·대원이 비친다).
## 덩어리는 제자리에서 천천히 아래로 흘러내리며 옅어지고 위에서 다시 생긴다 (smoke_sink_s 주기).
## 짙으면(가시거리 짧음) 검은 연기, 옅으면 회색 연기
func _draw_smoke_cloud(c: Compartment, h: float, thick: float, a: float, density: float, fires: Array[Vector2] = [], reach := Vector3(0, 0, -1), op := -1.0) -> bool:
	if FxArt.puffs == null and not FxArt.load_all():
		return false
	if FxArt.puffs == null:
		return false
	var sp := stack.params
	var r := c.rect
	var t := Time.get_ticks_msec() / 1000.0
	var dark := density >= sp.smoke_dark_density
	var kind := FxArt.PUFF_BLACK if dark else FxArt.PUFF_WHITE
	var tint := Color(1, 1, 1) if dark else Color(0.62, 0.63, 0.66)
	var step := maxf(1.0, sp.smoke_puff_spacing_m / sim.building.cell_size_m)
	var w0 := step * IsoProjection.HALF_W * 3.4
	var row_m := maxf(0.1, sp.smoke_row_m)
	var h0 := minf(w0 * 0.6, row_m * IsoProjection.PX_PER_M * 2.6)
	var rows := clampi(ceili(thick / row_m - 0.001), 1, sp.smoke_max_rows)
	var nx := maxi(1, ceili(r.size.x / step))
	var ny := maxi(1, ceili(r.size.y / step))
	# 커튼 방식: 앞면은 Blender로 구운 커튼이 맡고, 덩어리는 방 안쪽 아랫면 한 줄만
	var curtain := sp.smoke_style == "curtain" and FxArt.curtain != null
	# 윗면 그림이 있으면 방 안쪽 덩어리 대신 연기 판 하나
	var sheet := curtain and FxArt.sheet != null
	var col := Color(0.36, 0.36, 0.38) if dark else Color(0.8, 0.81, 0.84)
	# 연기층 색도 연기 읽기 색으로 (흰 → 회 → 검, 수증기) — 2026-11-24. 덩어리 그림(검은·흰 묶음)은 짙기로 고른 그대로
	col = _smoke_look(c).get("color", col)
	if op < 0.0:
		op = minf(sp.smoke_max_opacity, a * 1.3)
	if sheet:
		# 연기 상자 (2026-11-12 사용자 결정): 윗면은 천장 높이에 — 윗면·앞면 두 개만 그려 화면에서 겹치지 않는다
		_draw_smoke_sheet(r, CEILING_M, Color(col, op), c.index, _spread_dir(r, fires), reach)
	# 그릴 덩어리: [깊이 순서, 칸, 줄]. 뒤(북서)에서 앞(남동)으로, 같은 자리는 위 줄부터
	var draws: Array = []
	for j in (0 if sheet else ny):
		for i in nx:
			var front := (i == nx - 1 or j == ny - 1) and not curtain
			for k in (rows if front else 1):
				var row := k if front else rows - 1
				# 연기 선두 밖은 아직 연기가 없다
				var cc := Vector2(r.position) + (Vector2(i, j) + Vector2(0.5, 0.5)) * step
				if not _in_front(reach, cc):
					continue
				draws.append([i + j, Vector2i(i, j), row])
	if draws.size() > sp.smoke_max_puffs:
		# 많으면 앞쪽을 남긴다
		draws.sort_custom(func(m: Array, n: Array) -> bool: return m[0] > n[0])
		draws.resize(sp.smoke_max_puffs)
	draws.sort_custom(func(m: Array, n: Array) -> bool: return m[0] < n[0] or (m[0] == n[0] and m[2] < n[2]))
	var lo := Vector2(r.position) + Vector2(0.4, 0.4)
	var hi := Vector2(r.end) - Vector2(0.4, 0.4)
	for d: Array in draws:
		var g: Vector2i = d[1]
		var k: int = d[2]
		var front := (g.x == nx - 1 or g.y == ny - 1) and not curtain
		var seed := c.index * 97 + g.x * 13 + g.y * 31 + k * 7
		var jit := Vector2(_rand01(seed) - 0.5, _rand01(seed + 3) - 0.5) * step * 0.5
		var drift := Vector2(sin(t * 0.3 + seed), cos(t * 0.23 + seed * 1.3)) * step * 0.12
		var at := (Vector2(r.position) + (Vector2(g) + Vector2(0.5, 0.5)) * step + jit + drift).clamp(lo, hi)
		# k번째 줄 아랫면: 천장에서 (k+1)줄 아래, 연기층 하단보다 내려가지 않는다
		var slot := maxf(h, CEILING_M - (k + 1) * row_m)
		# 새로 생기는 줄은 옅게 시작해 두꺼워질수록 진해진다
		var grow := clampf((thick - k * row_m) / row_m, 0.25, 1.0)
		# 흘러내림: 줄 안에서 위 → 아래로 내려오며 옅어지고 위에서 다시
		var phase := fposmod(t / sp.smoke_sink_s + _rand01(seed + 11), 1.0)
		var bottom_m := maxf(h - 0.05, slot + row_m * (0.35 - 0.6 * phase))
		var pulse := sin(phase * PI)
		var base_a := minf(sp.smoke_front_alpha, a + 0.15) if front else a * (sp.smoke_top_alpha * 1.5 if curtain else sp.smoke_top_alpha)
		var alpha := base_a * grow * (0.55 + 0.45 * pulse)
		var w := w0 * (0.9 + 0.2 * _rand01(seed + 5))
		var hh := h0 * (0.9 + 0.25 * pulse)
		var bottom := proj.to_screen(at, bottom_m)
		FxArt.draw_puff_rect(self, Rect2(bottom - Vector2(w * 0.5, hh * 0.9), Vector2(w, hh)), kind, seed, Color(tint, alpha))
	if curtain:
		_draw_curtain_faces(r, h, Color(col, op), c.index, reach)
	if reach.z >= 0.0:
		_draw_smoke_front_edge(r, h, reach, Color(col, op), c.index)
	return true


## 연기 선두 원(출발점 x·y, 반지름 z — 셀) 안인가. z < 0 = 다 덮임
func _in_front(front: Vector3, p: Vector2) -> bool:
	return front.z < 0.0 or Vector2(front.x, front.y).distance_to(p) <= front.z


## 퍼지는 연기 선두 가장자리: 둥근 선두를 따라 연기 덩어리가 말려 나간다 (방 안쪽만)
func _draw_smoke_front_edge(r: Rect2i, h: float, front: Vector3, col: Color, seed: int) -> void:
	var o := Vector2(front.x, front.y)
	var rad := front.z
	if rad <= 0.05:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var n := clampi(ceili(TAU * rad / 2.0), 6, 28)
	var size := IsoProjection.HALF_W * 2.6
	var inner := Rect2(r).grow(-0.2)
	for k in n:
		var ang := TAU * (k + 0.5 * _rand01(seed + k)) / n + t * 0.05
		var p := o + Vector2(cos(ang), sin(ang)) * rad
		if not inner.has_point(p):
			continue
		var roll := sin(t * 1.3 + k * 1.7)
		var w := size * (0.85 + 0.25 * _rand01(seed * 3 + k))
		var hh := w * 0.5
		var bottom := proj.to_screen(p, h - 0.05 + 0.04 * roll)
		# 흰 김 덩어리에 연기 판 색을 곱한다 (검은 덩어리는 작게 그리면 테두리가 고리처럼 보인다)
		FxArt.draw_puff_rect(self, Rect2(bottom - Vector2(w * 0.5, hh * 0.85), Vector2(w, hh)), FxArt.PUFF_WHITE, seed + k, Color(col, col.a * (0.6 + 0.25 * roll)))


## 잘린 앞면(동·남)에 연기 커튼: 위 = 천장, 그림의 body_v 높이 = 연기층 아랫면(h), 그 아래는 말려 내려오는 가장자리.
## 가로는 tile_m 마다 한 장 (건물 좌표에 맞춰 이웃 방과 무늬가 이어진다)
func _draw_curtain_faces(r: Rect2i, h: float, col: Color, seed: int, front := Vector3(0, 0, -1)) -> void:
	var m: Dictionary = FxArt.meta.get("smoke_curtain", {})
	var body_v := clampf(float(m.get("body_v", 0.75)), 0.3, 1.0)
	var tile := maxf(1.0, float(m.get("tile_m", 2.0)) / sim.building.cell_size_m)
	var bottom := maxf(0.0, CEILING_M - (CEILING_M - h) / body_v)
	# 천장 쪽 진하기 = col.a (그림 평균 불투명도로 나눠 맞춘다). 아래 끝 배율은 연기층 아랫면에서
	# smoke_curtain_low 가 되게 그림 맨 아래까지 늘인다
	col = Color(col, minf(1.0, col.a / FxArt.mean_alpha("smoke_curtain", 0.86)))
	var low := clampf(stack.params.smoke_curtain_low, 0.0, 1.0)
	var fade_end := maxf(0.0, 1.0 - (1.0 - low) / body_v)
	# 동쪽 면 (x = 끝, y 방향) → 남쪽 면 (y = 끝, x 방향)
	for face in 2:
		var from := float(r.position.y if face == 0 else r.position.x)
		var to := float(r.end.y if face == 0 else r.end.x)
		var fixed := float(r.end.x if face == 0 else r.end.y)
		# 연기 선두가 이 면에 닿은 구간만
		if front.z >= 0.0:
			var d := fixed - (front.x if face == 0 else front.y)
			if absf(d) >= front.z:
				continue
			var half := sqrt(front.z * front.z - d * d)
			var mid := front.y if face == 0 else front.x
			from = maxf(from, mid - half)
			to = minf(to, mid + half)
		var s := from
		while s < to - 0.001:
			var e := minf(to, (floorf(s / tile) + 1.0) * tile)
			var u0 := s / tile - floorf(s / tile)
			var u1 := u0 + (e - s) / tile
			var pa := Vector2(fixed, s) if face == 0 else Vector2(s, fixed)
			var pb := Vector2(fixed, e) if face == 0 else Vector2(e, fixed)
			FxArt.draw_curtain(self, proj.to_screen(pa, CEILING_M), proj.to_screen(pb, CEILING_M), proj.to_screen(pb, bottom), proj.to_screen(pa, bottom), u0, u1, col, seed + face, fade_end)
			s = e


## 연기 상자 윗면 (Blender 플립북, 가로·세로 타일): 방 바닥 모양 그대로 높이 h(천장)에 깐다.
## 진하기 = 시선이 연기층 두께를 지나는 만큼 — 쌓일수록 진해진다. 틈으로 바닥·대원이 비친다.
## spread: 무늬가 흘러가는 방향 (불난 방에서 멀어지는 쪽 — 연기가 퍼지는 모습). 불난 방은 제자리에서 끓는다
func _draw_smoke_sheet(r: Rect2i, h: float, col: Color, seed: int, spread: Vector2, front := Vector3(0, 0, -1)) -> void:
	var m: Dictionary = FxArt.meta.get("smoke_sheet", {})
	var cell := sim.building.cell_size_m
	var tile := maxf(1.0, float(m.get("tile_m", 2.0)) / cell)
	var t := Time.get_ticks_msec() / 1000.0
	# 무늬를 spread 쪽으로 밀면 그림 좌표는 반대로 간다
	var off := (-spread * stack.params.smoke_sheet_flow_mps / cell * t).posmod(tile)
	# 평균 진하기 = col.a: 그림 평균(mean)보다 옅으면 그림만 옅게, 진하면 그림 아래에 고른 색 B를 깐다
	# (1 - (1 - B)(1 - mean) = col.a)
	var mean := FxArt.mean_alpha("smoke_sheet", 0.42)
	var base := Color(col, maxf(0.0, 1.0 - (1.0 - col.a) / (1.0 - mean)) if col.a > mean else 0.0)
	col = Color(col, minf(1.0, col.a / mean))
	var x := float(r.position.x)
	while x < r.end.x - 0.001:
		var kx := floorf((x + off.x) / tile + 0.0001)
		var xe := minf(r.end.x, (kx + 1.0) * tile - off.x)
		var u0 := maxf(0.0, (x + off.x) / tile - kx)
		var u1 := u0 + (xe - x) / tile
		var y := float(r.position.y)
		while y < r.end.y - 0.001:
			var ky := floorf((y + off.y) / tile + 0.0001)
			var ye := minf(r.end.y, (ky + 1.0) * tile - off.y)
			var v0 := maxf(0.0, (y + off.y) / tile - ky)
			var v1 := v0 + (ye - y) / tile
			var cut := _front_cut(front, Rect2(x, y, xe - x, ye - y))
			if cut.is_empty():
				var pts := PackedVector2Array([proj.to_screen(Vector2(x, y), h), proj.to_screen(Vector2(xe, y), h),
					proj.to_screen(Vector2(xe, ye), h), proj.to_screen(Vector2(x, ye), h)])
				if base.a > 0.0:
					_fill(pts, base)
				FxArt.draw_flip(self, FxArt.sheet, "smoke_sheet", pts, Vector2(u0, v0), Vector2(u1, v1), col, seed)
			else:
				# 선두 원과 겹친 조각만
				for poly: PackedVector2Array in cut:
					var spts := PackedVector2Array()
					var uvs := PackedVector2Array()
					for q in poly:
						spts.append(proj.to_screen(q, h))
						uvs.append(Vector2(u0 + (q.x - x) / tile, v0 + (q.y - y) / tile))
					if base.a > 0.0 and spts.size() >= 3:
						_fill(spts, base)
					FxArt.draw_flip_poly(self, FxArt.sheet, "smoke_sheet", spts, uvs, col, seed)
			y = ye
		x = xe


## 직사각형(셀 좌표)을 연기 선두 원으로 자른다: 빈 배열 = 통째로 안(자르지 않음), [[]] 꼴의 빈 조각 = 통째로 밖
func _front_cut(front: Vector3, rect: Rect2) -> Array:
	if front.z < 0.0:
		return []
	var o := Vector2(front.x, front.y)
	var far := 0.0
	for p: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		far = maxf(far, o.distance_to(p))
	if far <= front.z:
		return []
	var near := o.clamp(rect.position, rect.end).distance_to(o)
	if near >= front.z:
		return [PackedVector2Array()]
	var circle := PackedVector2Array()
	for k in 32:
		circle.append(o + Vector2.from_angle(TAU * k / 32.0) * front.z)
	var quad := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var out: Array = Geometry2D.intersect_polygons(quad, circle)
	return out if not out.is_empty() else [PackedVector2Array()]


## 연기가 퍼지는 방향: 가장 가까운 불난 곳에서 이 방 쪽 (불난 방 자신·불 없음이면 0)
func _spread_dir(r: Rect2i, fires: Array[Vector2]) -> Vector2:
	var center := Vector2(r.get_center())
	var best := Vector2.ZERO
	var best_d := INF
	for f in fires:
		if Rect2(r).has_point(f):
			return Vector2.ZERO
		var d := center.distance_squared_to(f)
		if d < best_d:
			best_d = d
			best = f
	return Vector2.ZERO if best_d == INF else (center - best).normalized()


## 불에서 솟아 천장에 부딪혀 퍼지는 연기 기둥 (Blender 플립북). 방마다 타는 칸 가운데에 하나,
## 타는 칸이 많을수록 굵게. 불꽃과 같은 정보 규칙 — 보이는 불은 진하게, 본 적 있는 불은 흐리게.
## 돌려주는 값: 불난 곳들(방마다 타는 칸 가운데, 셀 좌표) — 연기층 무늬가 퍼지는 방향에 쓴다
func _draw_fire_plumes() -> Array[Vector2]:
	var fires: Array[Vector2] = []
	var grid := sim.fire.grid
	var p := sim.perception
	var sums := {}
	for i in grid.burning:
		var c3 := grid.cell_of(i)
		if c3.z != level:
			continue
		var fade := 1.0
		if not p.is_visible(level, c3.x, c3.y):
			if not (p.is_seen(level, c3.x, c3.y) and p.seen_burning[i] == 1):
				continue
			fade = 0.4
		var comp := sim.fire.compartment_at(level, c3.x, c3.y)
		var key := comp.index if comp else -1
		var acc: Array = sums.get(key, [Vector2.ZERO, 0, 0.0])
		sums[key] = [acc[0] + Vector2(c3.x, c3.y) + Vector2(0.5, 0.5), int(acc[1]) + 1, maxf(float(acc[2]), fade)]
	var sp := stack.params
	for key: int in sums:
		var acc: Array = sums[key]
		var n := float(acc[1])
		var at: Vector2 = acc[0] / n
		fires.append(at)
		if FxArt.plume == null:
			continue
		var base := _furniture_height(floori(at.x), floori(at.y)) + 0.5
		if base > CEILING_M - 0.4:
			continue
		var bottom := proj.to_screen(at, base)
		var top := proj.to_screen(at, CEILING_M)
		var hh := bottom.y - top.y
		var m: Dictionary = FxArt.meta.get("smoke_plume", {})
		var ratio := float(m.get("w", 120)) / maxf(1.0, float(m.get("h", 192)))
		var hw := hh * ratio * clampf(0.6 + 0.1 * n, 0.7, 1.4) * 0.5
		# 불 위 연기 기둥도 그 방의 연기 읽기 색·빠르기 (2026-11-24)
		var plk: Dictionary = _smoke_look(sim.fire.comps[key]) if key >= 0 and key < sim.fire.comps.size() else {}
		var col: Color = plk.get("color", Color(0.32, 0.32, 0.34))
		col.a = sp.smoke_plume_alpha * float(acc[2]) * clampf(0.5 + 0.1 * n, 0.5, 1.0)
		FxArt.draw_flip(self, FxArt.plume, "smoke_plume", PackedVector2Array([top + Vector2(-hw, 0), top + Vector2(hw, 0),
			bottom + Vector2(hw, 0), bottom + Vector2(-hw, 0)]), Vector2.ZERO, Vector2.ONE, col, key + 3, 1.0, float(plk.get("rate", 1.0)))
	return fires


## 개구부 윗부분으로 흘러나오는 연기 (Blender 플립북): 바깥으로 난 창·문에서 밖으로 나와 솟아오른다.
## 방 사이 문은 그리지 않는다 — 인방~천장 틈이 좁아 눌러 그리면 검은 붓 자국처럼 보이고,
## 옆방으로 번진 연기는 그 방 연기층(윗면·커튼)이 보여 준다. 그림이 없으면 false (예전 덩어리 기둥으로)
func _draw_smoke_spills() -> bool:
	if FxArt.spill == null:
		return false
	for s in smoke_spills(sim, level):
		if not bool(s[4]):
			_draw_spill(s, 0.0, CEILING_M, int(s[5]))
	# 백드래프트 징후: 지금 보이는 닫힌 문·창 틈에서만 (정보 안개 — 본 적만 있는 곳의 지금 상태를 보여 주지 않는다, 2026-11-24 검사)
	var p := sim.perception
	for s in backdraft_seeps(sim, level):
		var at: Vector2 = s[0]
		if p.enabled and not p.is_visible(level, floori(at.x), floori(at.y)):
			continue
		_draw_backdraft_seep(s, 0.0)
	return true


## 흘러나오는 연기 한 줄기. floor_h = 그 층 바닥 높이, ceil_m = 층 높이 (방 사이 문은 천장까지만)
func _draw_spill(s: Array, floor_h: float, ceil_m: float, seed: int) -> void:
	var m: Dictionary = FxArt.meta.get("smoke_spill", {})
	var cell := sim.building.cell_size_m
	var at: Vector2 = s[0]
	var dir: Vector2 = s[2]
	var top: float = s[3]
	var interior: bool = s[4]
	var img_h := float(m.get("height_m", 2.0))
	var lintel := (1.0 - float(m.get("lintel_v", 0.75))) * img_h
	# 세로 배율: 밖은 그대로 솟고, 방 사이 문은 인방~천장 틈에 맞춰 눌러 그린다
	var k := 1.0 if not interior else clampf((ceil_m - top) / maxf(0.1, img_h - lintel), 0.3, 1.0)
	# 연기 읽기 (2026-11-24, data/ui/smoke_look.json): 나오는 방의 그을음·산소·온도로 색(흰 → 회 → 검), 온도로 빠르기·뻗는 길이,
	# 방수로 빼앗긴 열만큼 흰 수증기 (화재1 p.342·124·255)
	var src_i := int(s[5]) if s.size() > 5 else -1
	var lk: Dictionary = _smoke_look(sim.fire.comps[src_i]) if src_i >= 0 and src_i < sim.fire.comps.size() else {}
	var reach := float(lk.get("reach", 1.0))
	var out := float(m.get("out_m", 1.6)) * (0.75 if interior else 1.0) * (0.7 + 0.4 * float(s[1])) * reach / cell
	var wall := at + dir * 0.5
	var lo := floor_h + top - lintel * k
	var hi := floor_h + top + (img_h - lintel) * k * lerpf(1.0, reach, 0.5)
	var col: Color = lk.get("color", Color(0.34, 0.34, 0.36) if float(s[1]) >= 0.6 else Color(0.78, 0.79, 0.82))
	col.a = stack.params.smoke_spill_alpha * clampf(float(s[1]), 0.3, 1.0)
	FxArt.draw_flip(self, FxArt.spill, "smoke_spill", PackedVector2Array([proj.to_screen(wall, hi), proj.to_screen(wall + dir * out, hi),
		proj.to_screen(wall + dir * out, lo), proj.to_screen(wall, lo)]), Vector2.ZERO, Vector2.ONE, col, seed, 1.0, float(lk.get("rate", 1.0)))


## 개구부로 넘치는 연기: [위치(개구부 가운데, 셀), 세기 0~1, 흐르는 방향(셀 단위 축), 인방 높이(m),
## 방 사이 문인가, 연기가 나오는 방 번호, 받는 방 번호(밖이면 나오는 방)]
static func smoke_spills(p_sim: SimWorld, lv: int) -> Array[Array]:
	var out: Array[Array] = []
	var fire := p_sim.fire
	for o in fire.openings:
		if o.level != lv or not o.is_open or o.cells.is_empty() or o.room_a == Opening.OUTSIDE:
			continue
		var src := fire.comps[o.room_a]
		var dst := src
		var interior := o.room_b != Opening.OUTSIDE
		if interior:
			var cb := fire.comps[o.room_b]
			# 연기층 아랫면이 더 낮은(연기가 더 찬) 방에서 나온다
			if cb.height - cb.layer_depth < src.height - src.layer_depth:
				dst = src
				src = cb
			else:
				dst = cb
			var gap := (dst.height - dst.layer_depth) - (src.height - src.layer_depth)
			if gap < 0.15:
				continue
		if src.height - src.layer_depth >= o.top or src.soot <= 0.001:
			continue
		var center := o.center()
		if not src.smoke_reaches(center, CompartmentModel.FRONT_DOOR_MARGIN_M):
			continue
		var density := 1.0 - clampf(fire.visibility_m(src) / 10.0, 0.0, 1.0)
		out.append([center, clampf(0.3 + density, 0.0, 1.0), _spill_dir(p_sim, lv, o, src, dst, center), o.top, interior, src.index, dst.index])
	return out


## 방의 연기 모습 (SmokeLook.look) — 같은 틱 안에서는 방마다 한 번만 셈한다 (그리기마다 줄기·덩어리마다 불렸다, 2026-11-24 검사)
var _look_cache: Dictionary = {}
var _look_tick := -1


func _smoke_look(c: Compartment) -> Dictionary:
	if c == null:
		return {}
	if sim.clock.tick != _look_tick:
		_look_tick = sim.clock.tick
		_look_cache.clear()
	if not _look_cache.has(c.index):
		_look_cache[c.index] = SmokeLook.look(sim.fire, c)
	return _look_cache[c.index]


## 백드래프트 징후 (연기 읽기 2단계, 2026-11-24 — 화재1 p.44 '닫힌 문 주위에서 나오는 무겁고 검은 연기', '연기가 건물 내로
## 되돌아오거나 맴도는 현상'): 징후가 있는 방(HazardSystem.backdraft_sign — 무전 징후 보고와 같은 조건)의 닫힌 문·창.
## → [틈 위치(셀), 새어 나가는 방향, 인방 높이(m), 방 번호, 창인가, 개구부 번호, 바깥으로 난 것인가]
static func backdraft_seeps(p_sim: SimWorld, lv: int) -> Array[Array]:
	var out: Array[Array] = []
	if p_sim.hazards == null:
		return out
	for o in p_sim.fire.openings:
		if o.level != lv or o.is_open or o.cells.is_empty() or o.room_a == Opening.OUTSIDE:
			continue
		if o.kind == Opening.Kind.STAIR or (o.kind == Opening.Kind.WINDOW and o.broken):
			continue
		var rooms: Array[int] = [o.room_a]
		if o.room_b != Opening.OUTSIDE:
			rooms.append(o.room_b)
		for r in rooms:
			var src := p_sim.fire.comps[r]
			if not p_sim.hazards.backdraft_sign(src):
				continue
			var other := o.room_b if r == o.room_a else o.room_a
			var dst := p_sim.fire.comps[other] if other != Opening.OUTSIDE else src
			var center := o.center()
			out.append([center, _spill_dir(p_sim, lv, o, src, dst, center), o.top, r, o.kind == Opening.Kind.WINDOW, o.index,
				o.room_b == Opening.OUTSIDE])
			break
	return out


## 백드래프트 징후 연기 한 줄기: 닫힌 틈 위로 검은 연기가 새어 나왔다가 빨려 들어가기를 되풀이한다 (bd_pulse_s 주기)
func _draw_backdraft_seep(s: Array, floor_h: float) -> void:
	if FxArt.spill == null:
		return
	var st := SmokeLook.style()
	var period := maxf(0.5, float(st.get("bd_pulse_s", 2.6)))
	var t := Time.get_ticks_msec() / 1000.0
	var phase := sin(TAU * t / period + float(s[5]) * 1.3)
	# 밀려 나올 때 길고 진하게, 빨려 들어갈 때 짧고 옅게
	var push := 0.5 + 0.5 * phase
	var cell := sim.building.cell_size_m
	var at: Vector2 = s[0]
	var dir: Vector2 = s[1]
	var top: float = s[2]
	var wall := at + dir * 0.5
	var out := (0.15 + 0.55 * push) / cell
	var lo := floor_h + top - 0.12
	var hi := floor_h + top + 0.35 + 0.45 * push
	var col: Color = _smoke_look(sim.fire.comps[int(s[3])]).get("color", Color(0.1, 0.1, 0.11))
	col = col.darkened(0.25)
	col.a = float(st.get("bd_alpha", 0.8)) * (0.45 + 0.55 * push)
	FxArt.draw_flip(self, FxArt.spill, "smoke_spill", PackedVector2Array([proj.to_screen(wall, hi), proj.to_screen(wall + dir * out, hi),
		proj.to_screen(wall + dir * out, lo), proj.to_screen(wall, lo)]), Vector2.ZERO, Vector2.ONE, col, int(s[5]) + 11, 1.0, 0.6)


## 나오는 방에서 멀어지는 축 방향: 개구부 칸 양옆을 보고 정한다 (안 되면 방 가운데 → 개구부)
static func _spill_dir(p_sim: SimWorld, lv: int, o: Opening, src: Compartment, dst: Compartment, center: Vector2) -> Vector2:
	var c0 := o.cells[0]
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var back := p_sim.fire.compartment_at(lv, c0.x - d.x, c0.y - d.y)
		var ahead := p_sim.fire.compartment_at(lv, c0.x + d.x, c0.y + d.y)
		if back == src and ahead != src:
			return Vector2(d)
	var target := Vector2(dst.rect.get_center()) if dst != src else center
	var v := target - Vector2(src.rect.get_center())
	if v == Vector2.ZERO:
		return Vector2(1, 0)
	return Vector2(signf(v.x), 0) if absf(v.x) >= absf(v.y) else Vector2(0, signf(v.y))


## 0~1 고정 난수 (덩어리 위치 흩뜨리기)
func _rand01(seed: int) -> float:
	return fposmod(sin(float(seed) * 12.9898) * 43758.5453, 1.0)


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
	if v.carried_by >= 0 and not thermal:
		# 구급대 들것 이송 (A10): 들것 위에 누운 그림 (들것까지 함께 구웠다). 박자는 조장과 같게, 멈추면 첫 장
		var ep := sim.ems.patient_of(v.id)
		if ep != null and ep.stage == EmsSystem.Stage.CARRYING:
			var ec := sim.units.get_crew(v.carried_by)
			var el := _ems_carry_layout(ec, SpriteArt.crew_set(sim.units.squads[ec.squad_id].type), sim.clock.alpha()) if ec != null else {}
			if not el.is_empty():
				var vart := SpriteArt.victim_set(v.label())
				var va := str(el.victim_anim)
				var walking := ec.leader.level == ec.leader.prev_level and (ec.leader.pos - ec.leader.prev_pos).length_squared() > 0.000001
				var fr := SpriteArt.frame_at(va, vart.frames(va), ec.leader.id * 0.37) if walking else 0
				vart.draw(self, va, int(el.k), fr, proj.to_screen(el.victim, 0.0))
				return
	if v.carried_by >= 0:
		# 옮겨지는 중 (2026-11-15): 누운 그림을 운반 배치대로 — 2인 운반은 두 사람 사이에 들려서(머리가 뒷사람 쪽),
		# 끌기는 끄는 사람 뒤 바닥에(머리가 끄는 사람 쪽). 누운 그림은 발이 그림 방향을 향한다
		var lay := _carry_layout(sim.units.get_crew(v.carried_by), sim.clock.alpha())
		var held_art := SpriteArt.victim_set(v.label()) if not thermal and not lay.is_empty() else null
		var held_anim := str(lay.get("victim_anim", ""))
		if held_art != null and held_anim != "" and held_art.frames(held_anim) > 0:
			# 2인 운반(lift_v): 두 사람 사이에 들린 그림 / 끌기(drag_v): 대원 앞 바닥에 끌려가는 그림.
			# 구울 때 높이까지 들어 있다. 박자는 조장과 같게
			var c := sim.units.get_crew(v.carried_by)
			var walking := c.leader.level == c.leader.prev_level and (c.leader.pos - c.leader.prev_pos).length_squared() > 0.000001
			var fr := SpriteArt.frame_at(held_anim, held_art.frames(held_anim), c.leader.id * 0.37) if walking else 0
			held_art.draw(self, held_anim, int(lay.get("victim_dir", lay.k)), fr, proj.to_screen(lay.victim, 0.0))
			return
		if held_art != null and held_art.frames("down_up") > 0:
			var spot: Vector2 = lay.victim
			_contact_shadow(proj.to_screen(spot, 0.0), 14, 5, 0.25)
			var feet_dir := int(lay.k) if str(lay.mode) == "lift" else posmod(int(lay.k) + 4, 8)
			held_art.draw(self, "down_up", feet_dir, 0, proj.to_screen(spot, float(lay.victim_h)))
			return
		var at := proj.to_screen(v.pos, 1.5)
		draw_colored_polygon(_ellipse(at, 12, 4), color)
		return
	if v.state == Victim.State.RESCUED:
		var p := sim.ems.patient_of(v.id)
		if p == null or not sim.ems.on_scene(p):
			return
		var tag: Color = sim.ems.shown_color(p)
		var at := proj.to_screen(v.pos, 0.05)
		# 응급처치 중 (A9): 구급대원 둘 사이에 반듯이 누운 그림 — 구울 때 자리·방향 그대로, 박자는 조장과 같게
		var ac := sim.units.get_crew(p.crew_id) if p.crew_id >= 0 else null
		var aart := SpriteArt.crew_set(sim.units.squads[ac.squad_id].type) if ac != null and not thermal else null
		var al := _aid_layout(ac, aart, sim.clock.alpha()) if aart != null else {}
		var vart := SpriteArt.victim_set(v.label()) if not al.is_empty() else null
		if vart != null:
			var fr := SpriteArt.frame_at("aid_v", vart.frames("aid_v"), ac.leader.id * 0.37)
			vart.draw(self, "aid_v", int(al.k), fr, proj.to_screen(al.victim, 0.0))
		elif not _draw_victim_sprite(v, at):
			draw_colored_polygon(_ellipse(at + Vector2(0, -3), 13, 5), color)
		draw_circle(at + Vector2(12, -5), 5.0, tag)
		draw_string(PlanStyle.font(), at + Vector2(-70, -14), "%s · %s · %s" % [v.label(), sim.ems.shown_name(p), EmsSystem.STAGE_NAMES[p.stage]], HORIZONTAL_ALIGNMENT_CENTER, 140, 12, tag.lightened(0.3))
		return
	var feet := proj.to_screen(v.pos, 0.05)
	_contact_shadow(feet, 15, 6, 0.35)
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
	var pose := _victim_pose(v, art)
	return art.draw(self, pose[0], pose[1], pose[2], feet, pose[3])


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


## 얇은 벽 한 칸: 가로 막대(서↔동)와 세로 막대(북↔남)를 이어 그린다. 두께 = 칸 × inner_wall_thick.
## 이웃 칸으로 벽이 이어지는 쪽 끝면은 그리지 않아 이음새 줄무늬가 생기지 않는다. 그리는 순서: 북쪽 팔 → 가로 막대 → 남쪽 팔
func _thin_wall(x: int, y: int, h0: float, h1: float, color: Color, top: Color, a0 := -1.0, a1 := -1.0) -> void:
	var b := sim.building
	var wallish := [BuildingData.Cell.WALL, BuildingData.Cell.DOOR, BuildingData.Cell.WINDOW]
	var has := func(dx: int, dy: int) -> bool: return b.in_bounds(x + dx, y + dy) and b.cell(level, x + dx, y + dy) in wallish
	var t := clampf(stack.params.inner_wall_thick, 0.05, 1.0) * 0.5
	var cx := x + 0.5
	var cy := y + 0.5
	var w: bool = has.call(-1, 0)
	var e: bool = has.call(1, 0)
	var n: bool = has.call(0, -1)
	var sth: bool = has.call(0, 1)
	if n:
		_thin_box(Vector2(cx - t, y), Vector2(cx + t, cy - t), h0, h1, color, top, false, true, a0, a1)
	var x0 := float(x) if w else cx - t
	var x1 := float(x + 1) if e else cx + t
	_thin_box(Vector2(x0, cy - t), Vector2(x1, cy + t), h0, h1, color, top, not sth or x1 - x0 > 2.0 * t + 0.001, not e, a0, a1)
	if sth:
		_thin_box(Vector2(cx - t, cy + t), Vector2(cx + t, y + 1), h0, h1, color, top, false, true, a0, a1)


## 실내 벽 (2026-11-12 사용자 결정 F04): 높이 h0~h1 구간을 바닥 0m 진하기 inner_wall_alpha_bottom → 천장 inner_wall_alpha_top 으로
## 높이에 따라 옅게 (문 위 조각도 같은 높이면 같은 진하기). 천장 높이에 닿으면 윗면을 흰 테두리로
func _inner_wall(x: int, y: int, h0: float, h1: float, color: Color) -> void:
	var sp := stack.params
	var a_at := func(hm: float) -> float: return lerpf(sp.inner_wall_alpha_bottom, sp.inner_wall_alpha_top, clampf(hm / CEILING_M, 0.0, 1.0))
	var cap := Color(1, 1, 1, sp.inner_wall_cap_alpha) if h1 >= CEILING_M - 0.01 else Color(_structure_color(skin.color("cut_face")), a_at.call(h1))
	_wall_uv = Vector2(1000.0 + x + y + 1.0, 0.0)
	_thin_wall(x, y, h0, h1, color, cap, a_at.call(h0), a_at.call(h1))
	_wall_uv = Vector2.ZERO


## 상자 (_box와 같고 남·동 면을 고를 수 있다). a0·a1 >= 0 이면 옆면 진하기를 아래 a0 → 위 a1 로
func _thin_box(p0: Vector2, p1: Vector2, h0: float, h1: float, color: Color, top: Color, south: bool, east: bool, a0 := -1.0, a1 := -1.0) -> void:
	var nw := proj.to_screen(p0)
	var ne := proj.to_screen(Vector2(p1.x, p0.y))
	var se := proj.to_screen(p1)
	var sw := proj.to_screen(Vector2(p0.x, p1.y))
	var lo := Vector2(0, -h0 * IsoProjection.PX_PER_M)
	var hi := Vector2(0, -h1 * IsoProjection.PX_PER_M)
	if a0 >= 0.0:
		if south:
			var cs := color.darkened(SOUTH_SHADE)
			_quad_grad(sw + lo, se + lo, se + hi, sw + hi, Color(cs, a0), Color(cs, a1))
		if east:
			var ce := color.darkened(EAST_SHADE)
			_quad_grad(ne + lo, se + lo, se + hi, ne + hi, Color(ce, a0), Color(ce, a1))
	else:
		if south:
			_quad(sw + lo, se + lo, se + hi, sw + hi, Color(color.darkened(SOUTH_SHADE), color.a))
		if east:
			_quad(ne + lo, se + lo, se + hi, ne + hi, Color(color.darkened(EAST_SHADE), color.a))
	_quad(nw + hi, ne + hi, se + hi, sw + hi, top if top.a > 0.0 else color)


## 없앤 앞 바깥벽 자리 (인형집, 2026-11-12): 바닥선은 얇은 실선, 벽 꼭대기선·양 끝 세로선은 반투명 점선
func _draw_open_walls() -> void:
	var a := stack.params.open_wall_alpha
	var line := Color(1, 1, 1, a)
	var dash := Color(1, 1, 1, a * 0.85)
	for run: Dictionary in _ghost_wall_runs(level):
		if not run.outer:
			continue
		var ac := Vector2i(run.a.floor())
		if stack.wall_kind(level, ac.x, ac.y, false) != FloorStack.Wall.OPEN:
			continue
		var a0 := proj.to_screen(run.a, 0.02)
		var b0 := proj.to_screen(run.b, 0.02)
		var a1 := proj.to_screen(run.a, CEILING_M)
		var b1 := proj.to_screen(run.b, CEILING_M)
		draw_line(a0, b0, line, 1.5)
		draw_dashed_line(a1, b1, dash, 1.5, 6.0)
		# 세로기둥은 건물 바깥 모서리에만 (벽이 꺾이는 곳), 굵고 진하게
		var post := Color(1, 1, 1, stack.params.corner_post_alpha)
		for end: Vector2 in [run.a, run.b]:
			if _outer_corner(Vector2i(end.floor())):
				draw_dashed_line(proj.to_screen(end, 0.02), proj.to_screen(end, CEILING_M), post, 2.5, 8.0)


## 건물 바깥 모서리 칸인가: 바깥에 닿은 벽 칸이 가로·세로 두 방향으로 꺾인다
func _outer_corner(c: Vector2i) -> bool:
	var b := sim.building
	var outer := func(p: Vector2i) -> bool:
		if not b.in_bounds(p.x, p.y) or not b.cell(level, p.x, p.y) in [BuildingData.Cell.WALL, BuildingData.Cell.DOOR, BuildingData.Cell.WINDOW]:
			return false
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := p + d
			if not b.in_bounds(n.x, n.y) or b.cell(level, n.x, n.y) in BuildingData.OUTDOOR:
				return true
		return false
	var horizontal: bool = outer.call(c + Vector2i.LEFT) or outer.call(c + Vector2i.RIGHT)
	var vertical: bool = outer.call(c + Vector2i.UP) or outer.call(c + Vector2i.DOWN)
	return horizontal and vertical


## 경로·수관·급수선 (지금 층의 색 겹이나, 나누지 않을 때 바탕에서)
func _draw_route_lines(alpha: float) -> void:
	if depth == 0:
		for crew_id in selection.selected:
			_draw_path(sim.units.get_crew(crew_id).leader, alpha)
		if selection.commander_selected:
			_draw_path(sim.command.commander, alpha)
	_draw_hoses(alpha)
	if level == _first_level:
		for line in UnitsView.supply_lines(sim):
			_draw_supply_hose(line)
		# 운전원이 연결하는 중인 호스: 첫 결합한 곳에서 운전원(또는 연장이 끝났으면 다음 결합 자리)까지
		for v in sim.units.vehicles:
			var dl := _driver_layout(v)
			if not dl.is_empty() and dl.has("hose"):
				_draw_supply_hose(dl.hose)


## 급수 호스 (소화전·물탱크차 → 차): 셀 좌표 점들을 이은 선
func _draw_supply_hose(line: PackedVector2Array) -> void:
	if line.size() < 2:
		return
	var px := PackedVector2Array()
	for p in line:
		px.append(proj.to_screen(p, 0.05))
	draw_polyline(px, PlanStyle.SUPPLY_LINE, 4.0)


## 색 겹 (ghost_mode 4, 2026-11-12 사용자 결정 — 정적인 것은 무채색, 움직이는 것만 색):
## 바탕(바닥·벽·가구)은 색을 뺀 같은 층 노드가 그리고, 여기서는 구역·경로·수관·차량·불꽃·사람·연기만 원래 색으로
func _draw_live_only() -> void:
	var alpha := sim.clock.alpha()
	_draw_vehicle_shadows(alpha)
	if level == _first_level and depth == 0:
		ZoneDraw.draw_ground(self, sim.zones, func(p: Vector2) -> Vector2: return proj.to_screen(p, 0.03), 14)
	_draw_route_lines(alpha)
	for f in _fire_layout():
		_draw_fire_body(f)
	# 사람·차량은 깊이(x + y) 순서로
	var items: Array = []
	for ff in sim.units.firefighters:
		if ff.level == level and not ff.aboard:
			var p := _shown_pos(ff, alpha)
			items.append([_person_depth(p, alpha), ff])
	for v in sim.rescue.victims:
		if v.discovered and v.level == level:
			var vp := _victim_shown_pos(v, alpha)
			items.append([vp.x + vp.y, v])
	var cmd := sim.command.commander
	if cmd.level == level and not cmd.aboard:
		var cp := UnitsView.display_pos(cmd, alpha)
		items.append([cp.x + cp.y, cmd])
	if level == _first_level:
		for veh in sim.units.vehicles:
			if not veh.away:
				var vp := veh.prev_pos.lerp(veh.pos, alpha)
				items.append([vp.x + vp.y, veh])
		_append_drivers(items)
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for it: Array in items:
		var o: Variant = it[1]
		if o is Dictionary:
			_draw_driver(o)
		elif o == cmd:
			_draw_commander(alpha)
		elif o is Firefighter:
			_draw_unit(o, alpha)
		elif o is Victim:
			_draw_victim(o)
		else:
			_draw_vehicle(o, alpha)
	if not thermal:
		_draw_smoke()
	_draw_sprays(alpha)
	_draw_blasts()
	if _glow:
		_glow.z_as_relative = true
		_glow.z_index = 0
		_glow.spots = _glow_spots if not thermal else []
		_glow.queue_redraw()
		_glow_spots = []


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
	if cap > 0.0:
		_quad(nw + hi, ne + hi, se + hi, sw + hi, Color(_structure_color(skin.color("cut_face")), cap))


## 아래 두 점은 bottom 색, 위 두 점은 top 색 (a, b = 아래 / c, d = 위)
func _quad_grad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, bottom: Color, top: Color) -> void:
	if _batching:
		var base := _bq_pts.size()
		_bq_pts.append_array([a, b, c, d])
		_bq_cols.append_array([bottom, bottom, top, top])
		_bq_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		return
	draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([bottom, bottom, top, top]), _wall_uvs())


## 벽 조각이면 네 점 모두 벽 표시 UV, 아니면 빈 배열
func _wall_uvs() -> PackedVector2Array:
	if _wall_uv == Vector2.ZERO:
		return PackedVector2Array()
	return PackedVector2Array([_wall_uv, _wall_uv, _wall_uv, _wall_uv])


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	if _batching:
		var base := _bq_pts.size()
		_bq_pts.append_array([a, b, c, d])
		_bq_cols.append_array([color, color, color, color])
		_bq_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		return
	draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([color, color, color, color]), _wall_uvs())


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


## 다각형 채우기 — 넓이가 거의 0이면 건너뛴다 (작은 불꽃·관창 바로 앞 물줄기 등: 그리기 경고 'triangulation failed' 방지, 2026-11-17)
func _fill(pts: PackedVector2Array, color: Color) -> void:
	if pts.size() < 3:
		return
	var area := 0.0
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	if absf(area) < 1.0:
		return
	draw_colored_polygon(pts, color)


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
		FloorStack.Wall.FULL, FloorStack.Wall.GLASS, FloorStack.Wall.OPEN:
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
		_draw_outdoor_people()
	# 다른 층은 바로 위·아래든 먼 아래층이든 평면도 선만 (2026-11-12 사용자 결정)
	if ghost_mode == 1 or ghost_mode == 2:
		_draw_adjacent()
	_draw_ghost_glow()
	if _ghost_units:
		_ghost_units.queue_redraw()


## 다른 층으로 보이는 땅(1층)의 바깥: 차량·대원·지휘관·관계인·발견한 요구조자를 원래대로 (2026-11-12 사용자 결정 —
## 바깥 땅은 어느 층을 보든 그대로 보인다). 깊이(x + y) 순서로. 위층 건물에 가려지는 자리는 테두리도 함께 (_draw_ghost_units)
func _draw_outdoor_people() -> void:
	var alpha := sim.clock.alpha()
	_draw_vehicle_shadows(alpha)
	var items: Array = []
	for v in sim.units.vehicles:
		if not v.away:
			var vp := v.prev_pos.lerp(v.pos, alpha)
			items.append([vp.x + vp.y, v])
	for ff in sim.units.firefighters:
		if ff.level == level and not ff.aboard:
			var fp := _shown_pos(ff, alpha)
			if _outdoor_at(fp):
				items.append([_person_depth(fp, alpha), ff])
	for victim in sim.rescue.victims:
		if victim.discovered and victim.level == level and _outdoor_at(victim.pos):
			var vp := _victim_shown_pos(victim, alpha)
			items.append([vp.x + vp.y, victim])
	var cmd := sim.command.commander
	if cmd.level == level and not cmd.aboard:
		var cp := UnitsView.display_pos(cmd, alpha)
		if _outdoor_at(cp):
			items.append([cp.x + cp.y, cmd])
	for w in sim.command.survey.witnesses:
		if w.present(sim.clock.tick):
			items.append([w.pos.x + w.pos.y, w])
	if level == _first_level:
		_append_drivers(items)
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for it: Array in items:
		var o: Variant = it[1]
		if o is Dictionary:
			_draw_driver(o)
		elif o == cmd:
			_draw_commander(alpha)
		elif o is Firefighter:
			_draw_unit(o, alpha)
		elif o is Victim:
			_draw_victim(o)
		elif o is Witness:
			_draw_witness(o)
		else:
			_draw_vehicle(o, alpha)


## 바깥 땅 칸인가
func _outdoor_at(p: Vector2) -> bool:
	return sim.building.cell(level, floori(p.x), floori(p.y)) in BuildingData.OUTDOOR


## 이 층(아래로 보이는 층)의 그 자리 사람이 바로 위층 건물(바닥~천장 덩어리)에 화면에서 가려지는가
func _hidden_by_upper(p: Vector2, h: float) -> bool:
	if upper_level < 0 or depth <= 0 or depth >= ABOVE_DEPTH or stack.staggered():
		return false
	var fp: Rect2i = sim.building.footprint(upper_level)
	var shift := stack.offset_vec(depth - 1) - stack.offset_vec(depth)
	var pts := PackedVector2Array()
	for hh: float in [0.0, CEILING_M]:
		for c: Vector2 in [Vector2(fp.position), Vector2(fp.end.x, fp.position.y), Vector2(fp.end), Vector2(fp.position.x, fp.end.y)]:
			pts.append(proj.to_screen(c, hh) + shift)
	return Geometry2D.is_point_in_polygon(proj.to_screen(p, h), Geometry2D.convex_hull(pts))


## 다른 층의 불은 화면에 그리지 않는다 (2026-11-12 사용자 결정): 지금 층 바닥 위·방 위에 비쳐 이 층 불처럼 헷갈린다.
## 어느 층에 불이 있는지는 층 막대(본 불 = 빨강·주황 창)와 무전·상황판으로 안다. 지금 층이었을 때 남은 빛만 지운다
func _draw_ghost_glow() -> void:
	if _glow == null or _glow.spots.is_empty():
		return
	_glow.spots = []
	_glow.queue_redraw()


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


## 다른 층 (2026-11-12 사용자 결정): 면 칠 없이 흰 점선만 — 지금 층 연기와 겹쳐 진해지지 않는다.
## 바깥벽은 바닥·천장·모서리 세로선의 3차원 점선 상자, 실내 벽은 바닥 높이 점선 (확인된 곳만)
func _draw_adjacent() -> void:
	var tone := Color(0.86, 0.87, 0.9)
	var line := Color(tone, stack.params.ghost_line_alpha)
	var dash := stack.params.ghost_dash_px
	var upper := depth >= ABOVE_DEPTH
	var bd := sim.building
	var p := sim.perception
	var plan_known := sim.command.interior.plan_known
	for run: Dictionary in _ghost_wall_runs(level):
		var outer: bool = run.outer
		var ra: Vector2 = run.a
		var rb: Vector2 = run.b
		if upper:
			# 위층: 뒷벽(북)·왼쪽 벽(서)만 지금 층 바깥벽과 같은 한 칸 두께의 반투명 상자 — 지금 층 윤곽 바깥(배경 쪽)에 놓여
			# 지금 층을 가리지 않는다. 그 밖의 벽·실내 벽은 그리지 않고 건물 바깥 윤곽 점선 한 줄로 (_draw_upper_outline)
			if not outer:
				continue
			var horizontal := is_equal_approx(ra.y, rb.y)
			var mid := Vector2i(((ra + rb) * 0.5).floor())
			var out_cell := mid + (Vector2i(0, -1) if horizontal else Vector2i(-1, 0))
			if not bd.in_bounds(out_cell.x, out_cell.y) or bd.cell(level, out_cell.x, out_cell.y) in BuildingData.OUTDOOR:
				var p0 := ra - Vector2(0.5, 0.5)
				var p1 := rb + Vector2(0.5, 0.5)
				# 왼쪽 벽의 맨 위 모서리 칸은 뒷벽 상자가 이미 그렸다 (겹쳐 진해지지 않게)
				var first := Vector2i(ra.floor())
				if not horizontal and bd.in_bounds(first.x + 1, first.y) 						and bd.cell(level, first.x + 1, first.y) in [BuildingData.Cell.WALL, BuildingData.Cell.DOOR, BuildingData.Cell.WINDOW]:
					p0.y += 1.0
				var body := Color(tone, stack.params.ghost_back_wall_alpha)
				# 벽 아래에도 바닥판 두께만큼 — 턱의 바닥판 아랫면과 벽 아랫면이 맞는다 (2026-11-12 사용자 지적)
				_box(p0, p1, -stack.params.ghost_slab_m, CEILING_M, body, body, body)
				if stub_above:
					# 안쪽 면(북벽은 남쪽 면, 서벽은 동쪽 면)을 한 층 위에 반쯤
					var fa := Vector2(p0.x, p1.y) if horizontal else Vector2(p1.x, p0.y)
					_stub_face(fa, p1, stack.upper_vec(1), 1.0,
						tone.darkened(SOUTH_SHADE if horizontal else EAST_SHADE), stack.params.ghost_back_wall_alpha, level * 7 + (0 if horizontal else 3))
			continue
		# 아래층: 바깥벽은 바닥선 + 천장선 + 양 끝 세로선의 점선, 확인된 실내 벽은 바닥 높이 점선
		var known := outer or plan_known or not p.enabled
		for ci: int in run.comps:
			if not known and p.room_seen[ci] == 1:
				known = true
		if not known:
			continue
		if outer:
			var along: Vector2 = (rb - ra).normalized() * 0.5
			ra -= along
			rb += along
		var a0 := proj.to_screen(ra, 0.02)
		var b0 := proj.to_screen(rb, 0.02)
		draw_dashed_line(a0, b0, line, 1.2, dash)
		if outer:
			var a1 := proj.to_screen(ra, CEILING_M)
			var b1 := proj.to_screen(rb, CEILING_M)
			draw_dashed_line(a1, b1, line, 1.2, dash)
			draw_dashed_line(a0, a1, line, 1.2, dash)
			draw_dashed_line(b0, b1, line, 1.2, dash)
	# 위층은 뒷벽·왼쪽 벽 상자와 바닥 턱만 — 바깥 윤곽 점선은 그리지 않는다 (2026-11-12 사용자 결정: 지금 층 위를 가로질러 복잡)
	if upper:
		_draw_upper_ledge(tone)


## 잘린 벽 한 면: 바닥선 a→b (셀 좌표)를 화면에서 lift 만큼 옮긴 곳을 밑변으로, dir(1 = 위로, -1 = 아래로) 쪽으로
## 층 높이 × stub_height_ratio(±0.15) 만큼. 밑변은 진하기 alpha, 잘린 변은 거의 투명. 한 칸 남짓마다 높이가 달라 들쭉날쭉하다
func _stub_face(a: Vector2, b: Vector2, lift: Vector2, dir: float, color: Color, alpha: float, seed: int) -> void:
	var length := a.distance_to(b)
	if length < 0.5:
		return
	var n := maxi(2, ceili(length / 1.5))
	var ratio := stack.params.stub_height_ratio
	var base := Color(color, alpha)
	var faded := Color(color, alpha * 0.08)
	var prev_p := a
	var prev_h := CEILING_M * (ratio + (_rand01(seed) - 0.5) * 0.3)
	for k in range(1, n + 1):
		var cur_p := a.lerp(b, float(k) / n)
		var cur_h := CEILING_M * (ratio + (_rand01(seed + k * 17) - 0.5) * 0.3)
		draw_polygon(PackedVector2Array([proj.to_screen(prev_p, 0.0) + lift, proj.to_screen(cur_p, 0.0) + lift,
			proj.to_screen(cur_p, cur_h * dir) + lift, proj.to_screen(prev_p, prev_h * dir) + lift]),
			PackedColorArray([base, base, faded, faded]))
		prev_p = cur_p
		prev_h = cur_h


## 보이는 맨 아래층 밑으로 층이 더 있다: 건물 앞면(남)·오른쪽 면(동) 바깥벽을 바닥 아래로 반쯤 내려 그린다
func _draw_stub_below() -> void:
	var fp: Rect2i = sim.building.footprint(level)
	var wall := _structure_color(skin.color("wall"))
	var se := Vector2(fp.end)
	_stub_face(Vector2(fp.position.x, fp.end.y), se, Vector2.ZERO, -1.0, wall.darkened(SOUTH_SHADE), 1.0, level * 11)
	_stub_face(Vector2(fp.end.x, fp.position.y), se, Vector2.ZERO, -1.0, wall.darkened(EAST_SHADE), 1.0, level * 13 + 5)


## 위층 바닥 (2026-11-12 사용자 결정): 가운데가 둥글고 불규칙하게 뚫린 바닥판 — 뒷벽(북)·왼쪽 벽(서)에 붙은 쪽만 남는다.
## 구멍 가장자리: 뒷벽 쪽은 양 끝이 두껍고 가운데가 얇은 활 모양, 두 벽이 만나는 모서리는 둥글게, 한 칸 남짓마다 들쭉날쭉(고정 난수).
## 위층은 뒤(북)로 비켜 놓여 있어 뒷벽 쪽 폭은 그 거리만큼 넓다 — 가장 두꺼운 곳이 지금 층 뒷벽 바로 위까지 (방 안은 가리지 않는다).
## 바닥판 두께(ghost_slab_m)는 구멍 가장자리를 따라 어둡고 진하게 — 두께 있는 판으로 보이게
func _draw_upper_ledge(tone: Color) -> void:
	var fp: Rect2i = sim.building.footprint(level)
	var sp := stack.params
	var cell := sim.building.cell_size_m
	var w := sp.ghost_ledge_m / cell
	if w <= 0.0 or fp.size.x < 4 or fp.size.y < 4:
		return
	var x0 := fp.position.x + 1.0
	var y0 := fp.position.y + 1.0
	var x1 := float(fp.end.x)
	var y1 := float(fp.end.y)
	w = minf(w, (x1 - x0) * 0.3)
	# 뒷벽 쪽 가장 두꺼운 폭 = 턱 폭 + 뒤로 비켜 놓은 거리
	var wn := minf(w + stack.upper_back_cells(), (y1 - y0) * 0.8)
	var jag := sp.ghost_ledge_jag_m / cell
	var bow := minf(sp.ghost_ledge_bow_m / cell, wn - w * 0.5)
	var r := minf(sp.ghost_ledge_round_m / cell, minf((x1 - x0 - w) * 0.4, (y1 - y0 - wn) * 0.6))
	# 구멍 가장자리 (동쪽 끝 → 서쪽으로 활 모양 → 둥근 모서리 → 남쪽 끝)
	var hole: Array[Vector2] = [Vector2(x1, y0 + wn)]
	var k := 0
	var xa := x0 + w + r
	var n := maxi(4, ceili((x1 - xa) / 1.2))
	for q in range(1, n):
		var u := float(q) / n
		hole.append(Vector2(lerpf(x1, xa, u), y0 + wn - bow * sin(PI * u) + (_rand01(level * 53 + k) - 0.5) * 2.0 * jag))
		k += 1
	for q in 5:
		var ang := PI * 0.5 * q / 4.0
		var rr := r + (_rand01(level * 59 + k) - 0.5) * jag
		hole.append(Vector2(x0 + w + r - sin(ang) * rr, y0 + wn + r - cos(ang) * rr))
		k += 1
	var ya := y0 + wn + r
	n = maxi(2, ceili((y1 - ya) / 1.2))
	for q in range(1, n + 1):
		var u := float(q) / n
		hole.append(Vector2(x0 + w - bow * 0.3 * sin(PI * u) + (_rand01(level * 61 + k) - 0.5) * 2.0 * jag * (0.0 if q == n else 1.0), lerpf(ya, y1, u)))
		k += 1
	# 윗면
	var a := sp.ghost_back_wall_alpha
	var top := PackedVector2Array([proj.to_screen(Vector2(x0, y0), 0.0), proj.to_screen(Vector2(x1, y0), 0.0)])
	for q in hole:
		top.append(proj.to_screen(q, 0.0))
	top.append(proj.to_screen(Vector2(x0, y1), 0.0))
	_fill(top, Color(tone.lightened(0.25), a))
	# 바닥판 두께: 보는 쪽(남·동)을 향한 변만, 윗면보다 어둡고 진하게
	var t := sp.ghost_slab_m
	var side_a := minf(1.0, a + 0.25)
	var edge: Array[Vector2] = [Vector2(x1, y0)]
	edge.append_array(hole)
	edge.append(Vector2(x0, y1))
	for q in edge.size() - 1:
		var e0 := edge[q]
		var e1 := edge[q + 1]
		var d := e1 - e0
		var out := Vector2(d.y, -d.x)
		if out.x + out.y <= 0.0:
			continue
		_quad(proj.to_screen(e0, -t), proj.to_screen(e1, -t), proj.to_screen(e1, 0.0), proj.to_screen(e0, 0.0),
			Color(tone.darkened(0.35 if absf(out.y) >= absf(out.x) else 0.5), side_a))


## 다른 층의 대원(노랑)·발견한 요구조자(빨강): 그림을 테두리 셰이더로. 그림이 없으면 동그라미 테두리
func _draw_ghost_units() -> void:
	if sim == null or not (ghost or people_outline):
		_set_badges("ghost", [])
		return
	_draw_outlines(_ghost_units, {})


## 연기에 묻힌 대원(노랑)·요구조자(빨강): 벽 너머 사람과 같은 테두리를 연기 위에 (2026-11-12 사용자 결정)
func _draw_smoke_outlines() -> void:
	if sim == null or _smoke_hulls.is_empty() or thermal:
		_set_badges("smoke", [])
		return
	_draw_outlines(_smoke_outline, {}, _smoke_hulls)


## 가려진 대원 표시 방식(ViewParams.ghost_style)에 맞게 테두리 셰이더 값을 맞춘다 (바뀌었을 때만)
func _apply_ghost_style(style: String) -> void:
	if style == _ghost_style_applied or _ghost_other_mat == null:
		return
	_ghost_style_applied = style
	var p := stack.params
	for m: ShaderMaterial in [_ghost_smoke_mat, _ghost_other_mat]:
		m.set_shader_parameter("edge_strength", 1.0)
		m.set_shader_parameter("flat_tint", 0.0)
	match style:
		"silhouette", "mix":
			# 실제 그림을 반투명으로 + 출동대 색의 얇은 테두리 (다른 층은 더 옅게, 점선 없이)
			_ghost_smoke_mat.set_shader_parameter("fill", 0.6 if style == "silhouette" else 0.5)
			_ghost_smoke_mat.set_shader_parameter("thickness", 0.9)
			_ghost_other_mat.set_shader_parameter("fill", 0.35)
			_ghost_other_mat.set_shader_parameter("thickness", 0.9)
			_ghost_other_mat.set_shader_parameter("dash_px", 0.0)
		"badge_soft", "badge_flat":
			# 테두리 없이: 옅은 몸(원래 색) 또는 출동대 색 한 가지로 채운 실루엣
			_ghost_smoke_mat.set_shader_parameter("fill", 0.45 if style == "badge_soft" else 0.5)
			_ghost_smoke_mat.set_shader_parameter("edge_strength", 0.0)
			_ghost_smoke_mat.set_shader_parameter("flat_tint", 0.0 if style == "badge_soft" else 1.0)
		_:
			_ghost_smoke_mat.set_shader_parameter("fill", p.ghost_body_alpha)
			_ghost_smoke_mat.set_shader_parameter("thickness", p.ghost_outline_px)
			_ghost_other_mat.set_shader_parameter("fill", p.ghost_other_fill)
			_ghost_other_mat.set_shader_parameter("thickness", p.ghost_outline_px)
			_ghost_other_mat.set_shader_parameter("dash_px", p.ghost_dash_px)


## 머리 위 표식으로 그릴 대원 목록을 바꾸고 다시 그리게 한다 (which = "ghost" 다른 층 · "smoke" 연기 속)
func _set_badges(which: String, items: Array) -> void:
	if (_badge_items.get(which, []) as Array).is_empty() and items.is_empty():
		return
	_badge_items[which] = items
	if _badge_layer:
		_badge_layer.queue_redraw()


## 사람 테두리를 target에 그린다. rooms가 비어 있지 않으면 그 방(구획 index)에 있는 사람만,
## hulls가 비어 있지 않으면 화면에서 그 윤곽(연기 상자) 안에 몸이 든 사람만.
## 표시 방식(ghost_style): outline = 노란 테두리(지금) · silhouette = 출동대 색 실루엣 · badge = 머리 위 표식만 ·
## mix = 연기 속은 실루엣 + 표식, 다른 층은 표식만
func _draw_outlines(target: CanvasItem, rooms: Dictionary, hulls: Array[PackedVector2Array] = []) -> void:
	var alpha := sim.clock.alpha()
	var style: String = stack.params.ghost_style
	var other_floor := target == _ghost_units
	_apply_ghost_style(style)
	var badges: Array = []
	for it: Array in _outline_crew(other_floor, rooms, hulls, alpha):
		var ff: Firefighter = it[0]
		var c: Crew = it[1]
		var squad := sim.units.squads[c.squad_id]
		var crew_art := SpriteArt.crew_set(squad.type) if not thermal else null
		var feet := proj.to_screen(it[2], 0.0)
		var pose := _unit_pose(ff, c, crew_art) if crew_art else []
		var tint := GHOST_CREW
		var body := true
		if style != "outline":
			tint = Color(squad.color.lightened(0.25), 0.95)
			body = style == "silhouette" or (style in ["mix", "badge_soft", "badge_flat"] and not other_floor)
			if style != "silhouette":
				# 조원 자리 표시: 점 · 바닥 고리 · 없음(몸이 보이는 방식)
				var mark := "ring" if style == "badge_ring" else ("none" if body else "dot")
				badges.append({"ff": ff, "crew": c, "pos": it[2], "anim": str(pose[0]) if not pose.is_empty() else "idle", "mark": mark})
		if not body:
			continue
		if crew_art == null or not crew_art.draw(target, pose[0], pose[1], pose[2], feet, tint):
			target.draw_arc(feet + Vector2(0, -18), 9.0, 0.0, TAU, 16, tint, 2.0)
	_set_badges("ghost" if other_floor else "smoke", badges)
	for v in sim.rescue.victims:
		if not v.discovered or v.level != level or v.carried_by >= 0:
			continue
		if not rooms.is_empty() and not _in_rooms(v.pos, rooms):
			continue
		if not hulls.is_empty() and not _in_hulls(proj.to_screen(v.pos, 0.4), hulls):
			continue
		if target == _ghost_units and _outdoor_at(v.pos) and not _hidden_by_upper(v.pos, 0.4):
			continue
		var feet := proj.to_screen(v.pos, 0.05)
		var art := SpriteArt.victim_set(v.label()) if not thermal else null
		var vpose := _victim_pose(v, art) if art else []
		if art == null or not art.draw(target, vpose[0], vpose[1], vpose[2], feet, GHOST_VICTIM):
			target.draw_arc(feet + Vector2(0, -6), 9.0, 0.0, TAU, 16, GHOST_VICTIM, 2.0)


## 가려진 대원의 머리 위 표식 (ghost_style badge·mix): 조장 머리 위에 출동대 색 원 + 하는 일 그림 + 공기 잔량,
## 다른 조원은 발밑에 작은 점. 무엇을 하는지는 자세가 아니라 표식으로 읽는다 (프로스트펑크·EMERGENCY 방식)
func _draw_badges() -> void:
	if sim == null:
		return
	var ci := _badge_layer
	for which: String in _badge_items:
		for it: Dictionary in _badge_items[which]:
			var ff: Firefighter = it.ff
			var c: Crew = it.crew
			var col: Color = sim.units.squads[c.squad_id].color
			var pos: Vector2 = it.pos
			var feet := proj.to_screen(pos, 0.0)
			# 발밑 자리 표시 (조장·조원 같게): 점 또는 바닥 고리 (몸이 보이는 방식에서는 없음)
			match str(it.get("mark", "dot")):
				"dot":
					ci.draw_circle(feet, 4.5, Color(0.06, 0.07, 0.09, 0.85))
					ci.draw_circle(feet, 3.2, col)
				"ring":
					ci.draw_polyline(_ellipse(feet, 13, 6.5, true), Color(0.06, 0.07, 0.09, 0.8), 4.0)
					ci.draw_polyline(_ellipse(feet, 13, 6.5, true), col, 2.2)
			if ff != c.leader:
				continue
			var at := proj.to_screen(pos, 2.3)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 9), at + Vector2(6, 9), at + Vector2(0, 19)]), Color(0.06, 0.07, 0.09, 0.9))
			ci.draw_circle(at, 13.5, Color(0.06, 0.07, 0.09, 0.9))
			ci.draw_circle(at, 11.5, col)
			_badge_icon(ci, at, _badge_kind(str(it.anim)), Color.WHITE if col.get_luminance() < 0.6 else Color(0.08, 0.09, 0.11))
			# 공기 잔량
			var bar := Rect2(at.x - 12.0, at.y - 21.0, 24.0, 4.0)
			ci.draw_rect(bar.grow(1.0), Color(0.06, 0.07, 0.09, 0.9))
			var f := ff.air_ratio()
			ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), PlanStyle.AIR_LOW if f < 0.18 else PlanStyle.AIR_OK)


## 자세 이름 → 표식 그림 종류
static func _badge_kind(anim: String) -> String:
	if anim.begins_with("spray") or anim.begins_with("ovh"):
		return "water"
	if anim.begins_with("search"):
		return "search"
	if anim.begins_with("door") or anim.begins_with("force") or anim.begins_with("window"):
		return "door"
	if anim.begins_with("lift") or anim.begins_with("drag") or anim.begins_with("carry") or anim.begins_with("aid") or anim.begins_with("cot") or anim.begins_with("scoop"):
		return "rescue"
	if anim.contains("walk") or anim.begins_with("hose"):
		return "move"
	return "wait"


## 표식 안의 작은 그림 (지름 14px 안): 물방울 · 돋보기 · 문 · 십자 · 화살표 · 멈춤
static func _badge_icon(ci: CanvasItem, at: Vector2, kind: String, col: Color) -> void:
	match kind:
		"water":
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(5, 0), at + Vector2(4, 4), at + Vector2(0, 6.5),
				at + Vector2(-4, 4), at + Vector2(-5, 0)]), col)
		"search":
			ci.draw_arc(at + Vector2(-1.5, -1.5), 4.5, 0.0, TAU, 20, col, 2.2)
			ci.draw_line(at + Vector2(2, 2), at + Vector2(6.5, 6.5), col, 2.6)
		"door":
			ci.draw_rect(Rect2(at + Vector2(-4.5, -7), Vector2(9, 14)), col, false, 2.0)
			ci.draw_circle(at + Vector2(2, 0.5), 1.4, col)
		"rescue":
			ci.draw_rect(Rect2(at + Vector2(-2, -7), Vector2(4, 14)), col)
			ci.draw_rect(Rect2(at + Vector2(-7, -2), Vector2(14, 4)), col)
		"move":
			for dx: float in [-4.0, 1.5]:
				ci.draw_polyline(PackedVector2Array([at + Vector2(dx, -5), at + Vector2(dx + 4.5, 0), at + Vector2(dx, 5)]), col, 2.2)
		_:
			ci.draw_rect(Rect2(at + Vector2(-5, -6), Vector2(3.5, 12)), col)
			ci.draw_rect(Rect2(at + Vector2(1.5, -6), Vector2(3.5, 12)), col)


## 테두리로 그릴 이 층 대원 [[대원, 조, 그리는 자리(칸 좌표)], ...]. other_floor = 다른 층 사람 테두리(_ghost_units)인가.
## 자리는 몸을 그리는 자리(_shown_pos)다 — 연기에 덮였는지도 그 자리로 본다 (2026-11-24 사용자: 문 개방·방수 때 대원이 사라지고
## 선택 원만 남았다 — 실제 자리로 판정하고 그려서, 문 앞 방수태세·문 여는 자리·방수 줄처럼 배치 자리에 선 대원은
## 몸이 연기에 묻혀도 테두리가 딴 곳에 뜨거나 아예 없었다)
func _outline_crew(other_floor: bool, rooms: Dictionary, hulls: Array[PackedVector2Array], alpha: float) -> Array:
	var out: Array = []
	for c in sim.units.crews:
		for ff in c.members():
			if ff.level != level or ff.aboard:
				continue
			var p := _shown_pos(ff, alpha)
			if not rooms.is_empty() and not _in_rooms(p, rooms):
				continue
			if not hulls.is_empty() and not _in_hulls(proj.to_screen(p, 1.0), hulls):
				continue
			if other_floor and _outdoor_at(p) and not _hidden_by_upper(p, 1.0):
				continue
			out.append([ff, c, p])
	return out


## 화면 점이 윤곽들 중 하나 안인가
func _in_hulls(at: Vector2, hulls: Array[PackedVector2Array]) -> bool:
	for hull in hulls:
		if Geometry2D.is_point_in_polygon(at, hull):
			return true
	return false


## 그 자리(칸 좌표)가 rooms(구획 index 모음) 안인가
func _in_rooms(p: Vector2, rooms: Dictionary) -> bool:
	var comp := sim.fire.compartment_at(level, int(p.x), int(p.y))
	return comp != null and rooms.has(comp.index)
