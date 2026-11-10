class_name CityMassView
extends Node2D
## 전체 지도의 도시 배경 (기획안 4-4, 결정 ①): 화재 건물·도로·소화전·차량 등 활동에 영향을 주는 것만 색을 넣고,
## 나머지 건물은 흰색 매스 모형(아이소 박스, 윗면 밝게·옆면 조금 어둡게)으로만 그린다.
## 덩어리는 시드로 현장 지도 둘레에 자동으로 만든다 (스테이지마다 손으로 그리지 않음). 같은 시나리오는 늘 같은 도시.
## 텍스처·그림자 없이 색만, 한 번 그려 두면 다시 그리지 않는다 (사무용 PC, 기획안 9-5).

const TOP := Color(0.96, 0.96, 0.95)
const LEFT := Color(0.86, 0.87, 0.88)
const RIGHT := Color(0.76, 0.77, 0.79)
const EDGE := Color(0.62, 0.64, 0.67, 0.6)
const ROAD := Color(0.42, 0.45, 0.5)
const GROUND := Color(0.83, 0.84, 0.82)

## 블록 설정 (칸 단위)
const BLOCK_CELLS := 28
const STREET_CELLS := 8
const RINGS := 3
const FLOOR_M := 3.0

var proj: IsoProjection
## [{rect: Rect2i(칸), floors}]
var blocks: Array[Dictionary] = []
var _map_rect := Rect2i()
## 출동 진행률 (0~1, 출동 중이 아니면 음수) — World가 넣는다 (P9-1 출동 단계 차량 아이콘)
var progress: Callable
var _icons: Node2D
var _sim: SimWorld


func setup(building: BuildingData, p_proj: IsoProjection, p_seed: int, p_sim: SimWorld = null) -> void:
	proj = p_proj
	_sim = p_sim
	if _icons == null:
		_icons = Node2D.new()
		_icons.draw.connect(_draw_icons)
		add_child(_icons)
	_map_rect = Rect2i(0, 0, building.width, building.height)
	blocks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("city:%s:%d" % [building.id, p_seed])
	var step := BLOCK_CELLS + STREET_CELLS
	var reach := RINGS * step
	var x0 := -reach
	while x0 < building.width + reach:
		var y0 := -reach
		while y0 < building.height + reach:
			var cell_rect := Rect2i(x0 + STREET_CELLS / 2, y0 + STREET_CELLS / 2, BLOCK_CELLS, BLOCK_CELLS)
			if not cell_rect.intersects(_map_rect.grow(STREET_CELLS)):
				_add_block(cell_rect, rng)
			y0 += step
		x0 += step
	# 뒤(위쪽)부터 그리도록 화면 깊이(x + y) 순
	blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.rect.position.x + a.rect.position.y) < (b.rect.position.x + b.rect.position.y))
	queue_redraw()


## 블록 하나를 건물 1~4개로 나눈다 (높이·크기가 다른 매스)
func _add_block(r: Rect2i, rng: RandomNumberGenerator) -> void:
	var split := rng.randi_range(1, 3)
	if split == 1:
		blocks.append({"rect": r.grow(-2), "floors": rng.randi_range(2, 15)})
		return
	var half := r.size / 2
	for qx in 2:
		for qy in 2:
			if split == 2 and qy == 1:
				continue
			var sub := Rect2i(r.position + Vector2i(qx * half.x, qy * half.y), Vector2i(half.x, half.y if split == 3 else r.size.y))
			if rng.randf() < 0.15:
				continue  # 빈터·주차장
			blocks.append({"rect": sub.grow(-2), "floors": rng.randi_range(1, 12)})


func _process(_delta: float) -> void:
	if _icons and progress.is_valid() and float(progress.call()) >= 0.0:
		_icons.queue_redraw()
	elif _icons and _icons.visible:
		_icons.queue_redraw()


## 출동 중: 안전센터 쪽 도시 끝에서 화재 건물 앞 도로로 다가오는 선착 차량 아이콘 (도로를 따라 직선)
func _draw_icons() -> void:
	if _sim == null or not progress.is_valid():
		return
	var f := float(progress.call())
	if f < 0.0:
		return
	var reach := RINGS * (BLOCK_CELLS + STREET_CELLS)
	var font := PlanStyle.font()
	# 화면 배율과 상관없이 같은 크기로 보이게 (멀리 본 도시에서도 아이콘이 보이도록)
	var k := 1.0 / maxf(0.05, _icons.get_global_transform_with_canvas().get_scale().x)
	var i := 0
	for v in _sim.units.vehicles:
		if v.squad_id != 0:
			continue
		var target := v.pos
		var start := Vector2(_map_rect.end.x + reach / RINGS, target.y)
		var p := start.lerp(target, clampf(f, 0.0, 1.0)) + Vector2(i * 6.0, 0)
		var sp := proj.to_screen(p, 0.5)
		_icons.draw_circle(sp, 12.0 * k, Color(v.color, 0.95))
		_icons.draw_arc(sp, 12.0 * k, 0.0, TAU, 20, Color.WHITE, 2.0 * k)
		_icons.draw_set_transform(sp, 0.0, Vector2(k, k))
		_icons.draw_string(font, Vector2(-40, -18), v.short_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color.BLACK)
		_icons.draw_set_transform(Vector2.ZERO)
		i += 1


func _draw() -> void:
	if proj == null:
		return
	# 바닥(도로망)
	var reach := RINGS * (BLOCK_CELLS + STREET_CELLS)
	var ground := Rect2(Vector2(-reach, -reach), Vector2(_map_rect.size) + Vector2(reach, reach) * 2.0)
	draw_colored_polygon(_quad(ground, 0.0), ROAD)
	for b in blocks:
		var r: Rect2i = b.rect
		var pad := Rect2(Vector2(r.position) - Vector2(1, 1), Vector2(r.size) + Vector2(2, 2))
		draw_colored_polygon(_quad(pad, 0.0), GROUND)
	for b in blocks:
		_box(Rect2(b.rect), float(b.floors) * FLOOR_M)


func _quad(r: Rect2, h: float) -> PackedVector2Array:
	return PackedVector2Array([proj.to_screen(r.position, h), proj.to_screen(Vector2(r.end.x, r.position.y), h),
		proj.to_screen(r.end, h), proj.to_screen(Vector2(r.position.x, r.end.y), h)])


## 아이소 박스: 보이는 두 옆면(남·동)과 윗면
func _box(r: Rect2, h: float) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var c := r.end
	var d := Vector2(r.position.x, r.end.y)
	# 남쪽 면 (d-c)
	draw_colored_polygon(PackedVector2Array([proj.to_screen(d), proj.to_screen(c), proj.to_screen(c, h), proj.to_screen(d, h)]), LEFT)
	# 동쪽 면 (b-c)
	draw_colored_polygon(PackedVector2Array([proj.to_screen(b), proj.to_screen(c), proj.to_screen(c, h), proj.to_screen(b, h)]), RIGHT)
	var top := PackedVector2Array([proj.to_screen(a, h), proj.to_screen(b, h), proj.to_screen(c, h), proj.to_screen(d, h)])
	draw_colored_polygon(top, TOP)
	top.append(top[0])
	draw_polyline(top, EDGE, 1.0)
