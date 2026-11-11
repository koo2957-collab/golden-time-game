class_name IsoView
extends Node2D
## 입체(아이소메트릭) 화면. 층 노드(FloorLayer)를 묶어 건물을 두 모습으로 보여 준다 (R17).
##   외부 보기: 지상층 노드 하나가 바깥(도로·차량)과 건물 외관을 그린다.
##   단면 보기(인형집): 지금 층과 아래 층(FloorStack)을 층 노드마다 쌓아 그린다.
##     지금 층은 화면 높이 0, 아래 층은 floor_height_px씩 아래로 내려 그리고 한 층 내려갈수록 어둡게 한다.
##     위 층·지붕은 그리지 않는다. 보이지 않는 층 노드는 visible = false (시뮬레이션은 계속 돈다).
## 전환 연출(transition_s): 안으로·아래로 갈 때는 이전 모습(외벽·위층)이 위로 흐려지며 사라지고,
##   밖으로·위로 갈 때는 새 맨 위 층이 위에서 내려앉는다. 화면 연출일 뿐 게임은 멈추지 않는다.
## 바깥 코드(world.gd)는 show_view()·thermal만 쓰고, 층 노드 배치는 여기서 한다.

var sim: SimWorld
var params: ViewParams
var stack: FloorStack
## 깊이 순서 (0 = 지금 층). 장면 트리에서는 깊은 층이 먼저 오게 둔다 (먼저 그려져 위층에 가린다)
var layers: Array[FloorLayer] = []
## 전환 연출용: 사라지는 이전 맨 위 모습 (맨 위에 그린다)
var ghost: FloorLayer
## 위층 노드 (기획안 9-4 위·아래 각 2개 층). depth는 ABOVE_DEPTH부터 (지금 층·아래층과 구별)
var upper_layers: Array[FloorLayer] = []
const ABOVE_DEPTH := 100

var level := 1:
	get:
		return _level
	set(value):
		show_view(value, _exterior)
var exterior := false:
	get:
		return _exterior
	set(value):
		show_view(_level, value)
var thermal := false:
	set(value):
		thermal = value
		_apply()

var _level := 1
var _exterior := false
var _tween: Tween
var _links: Node2D
var _shadow: Node2D
var _hole_shader: Shader
var _proj: IsoProjection


func setup(p_sim: SimWorld, p_selection: SelectionController, p_proj: IsoProjection) -> void:
	sim = p_sim
	params = ViewParams.load_default()
	stack = FloorStack.new(sim.building, params)
	for depth in params.visible_floors_below + 1:
		var layer := FloorLayer.new()
		layer.name = "Floor%d" % depth
		add_child(layer)
		move_child(layer, 0)
		layer.setup(sim, p_selection, p_proj, stack)
		layers.append(layer)
	# 비켜 놓은 위층이 아래층 바닥에 드리우는 그림자 (아래층 다음, 위층 앞에 그린다)
	_shadow = Node2D.new()
	_shadow.name = "UpperShadow"
	_shadow.draw.connect(_draw_shadow)
	add_child(_shadow)
	# 위층 (지금 층 위에 반투명으로, 기획안 9-4)
	for k in params.visible_floors_above:
		var up := FloorLayer.new()
		up.name = "Above%d" % (k + 1)
		add_child(up)
		up.setup(sim, p_selection, p_proj, stack)
		upper_layers.append(up)
	# 비켜 놓은 두 층의 계단을 잇는 점선 (위층 위에 그린다)
	_links = Node2D.new()
	_links.name = "StairLinks"
	_links.z_as_relative = false
	_links.z_index = 60
	_links.draw.connect(_draw_links)
	add_child(_links)
	_proj = p_proj
	_hole_shader = load("res://shaders/unit_hole.gdshader")
	for node in layers + upper_layers:
		var mat := ShaderMaterial.new()
		mat.shader = _hole_shader
		node.material = mat
	ghost = FloorLayer.new()
	ghost.name = "Ghost"
	add_child(ghost)
	ghost.setup(sim, p_selection, p_proj, stack)
	ghost.visible = false
	_apply()


## 보이는 층·외부 보기를 바꾼다. animate면 전환 연출을 한다
func show_view(p_level: int, p_exterior: bool, animate := true) -> void:
	var old_level := _level
	var old_exterior := _exterior
	_level = p_level
	_exterior = p_exterior
	if layers.is_empty():
		return
	if _tween != null:
		_tween.kill()
	ghost.visible = false
	_apply()
	var changed := p_level != old_level or p_exterior != old_exterior
	if changed and animate and params.transition_s > 0.0 and is_inside_tree():
		_animate(old_level, old_exterior)


## 지금 보이는 층 (깊이 순서)
func shown_levels() -> Array[int]:
	if _exterior or stack == null:
		return [_level]
	return stack.visible_levels(_level)


## 외부 보기에서 외관 꼭대기 높이 (m, 카메라 범위용)
func shell_top_m() -> float:
	return layers[0].shell_top_m() if not layers.is_empty() else 0.0


## 단면 보기에서 아래로 쌓인 층이 차지하는 화면 높이 (px, 카메라 범위용)
func stack_depth_px() -> float:
	return stack.offset_px(shown_levels().size() - 1) if stack != null else 0.0


## 외부 보기 화면에서 world_pos 아래에 건물 외관이 있는가 (줌 전환 판단)
func building_under(world_pos: Vector2, proj: ViewProjection) -> bool:
	if layers.is_empty():
		return false
	var fp := Rect2(layers[0].shell_rect())
	var top := shell_top_m()
	var h := 0.0
	while h <= top:
		if fp.has_point(proj.to_cell_at(world_pos, h)):
			return true
		h += 0.5
	return false


## 층 고르기 (P4-5): 외부 보기에서 world_pos 아래 외벽의 층 (-99 = 없음)
func shell_level_at(world_pos: Vector2) -> int:
	if not _exterior or layers.is_empty():
		return -99
	return layers[0].shell_level_at(world_pos - layers[0].position)


## 층 고르기: 노랗게 테두리를 그릴 층 (-99 = 없음)
func set_hover_floor(lv: int) -> void:
	if not layers.is_empty():
		layers[0].hover_floor = lv if _exterior else -99


## 전환 연출 중인가
func transitioning() -> bool:
	return _tween != null and _tween.is_running()


func _apply() -> void:
	if layers.is_empty():
		return
	var shown := shown_levels()
	for depth in layers.size():
		var layer := layers[depth]
		if depth >= shown.size():
			layer.visible = false
			continue
		layer.visible = true
		_configure(layer, depth, shown, _exterior)
		layer.position = stack.offset_vec(depth)
		# 비켜 놓기(2026-11-12): 두 층 모두 온전하게. 예전 방식: 바로 아래층 회백색 10%, 그 아래 외관 덩어리
		if stack.staggered():
			layer.ghost_mode = 0
		else:
			layer.ghost_mode = 0 if depth == 0 else (1 if depth == 1 else 2)
		# 비켜 놓기: 고른 층이 아닌 짝 층은 흐리게 (2026-11-12 사용자 결정 25%)
		layer.modulate = Color(1, 1, 1, params.partner_alpha) if stack.staggered() and depth > 0 else Color.WHITE
	# 위층: 지금 층 위로 FLOOR_GAP_PX씩 올려 반투명 (외부 보기에서는 숨김)
	var above: Array[int] = []
	if not _exterior and stack != null:
		above = stack.above_levels(_level)
	for k in upper_layers.size():
		var up := upper_layers[k]
		if k >= above.size():
			up.visible = false
			continue
		up.visible = true
		up.depth = ABOVE_DEPTH + k
		up.level = above[k]
		up.exterior = false
		up.thermal = thermal
		up.upper_level = above[k + 1] if k + 1 < above.size() else -1
		up.lower_level = above[k - 1] if k > 0 else _level
		# 비켜 놓기: 위층도 온전하게(뒤로 비켜 있다). 예전 방식: 바로 위층 회백색 10%, 더 위는 사람 테두리만
		up.ghost_mode = 0 if stack.staggered() else (1 if k == 0 else 3)
		up.refresh()
		up.position = -stack.offset_vec(k + 1)
		# 비켜 놓기: 짝 위층은 흐리게 (25%). 예전 방식은 투명도가 선 색에 들어 있다
		up.modulate = Color(1, 1, 1, params.partner_alpha) if stack.staggered() else Color.WHITE


func _configure(layer: FloorLayer, depth: int, shown: Array[int], ext: bool) -> void:
	layer.depth = depth
	layer.level = shown[depth]
	layer.exterior = ext and depth == 0
	layer.thermal = thermal
	layer.upper_level = shown[depth - 1] if depth > 0 else -1
	layer.lower_level = shown[depth + 1] if depth + 1 < shown.size() else -1
	layer.refresh()


func _animate(old_level: int, old_exterior: bool) -> void:
	var rise := params.transition_rise_px
	var b := sim.building
	var going_in: bool = (old_exterior and not _exterior) \
		or (not _exterior and not old_exterior and b.floor_number(_level) < b.floor_number(old_level))
	_tween = create_tween().set_parallel(true)
	if going_in:
		# 이전 맨 위 모습(외관 또는 위층)을 잔상으로 남겨 위로 흐려지며 사라지게 한다
		var old_shown: Array[int] = [old_level]
		if not old_exterior:
			old_shown = stack.visible_levels(old_level)
		_configure(ghost, 0, old_shown, old_exterior)
		ghost.visible = true
		ghost.position = Vector2.ZERO
		ghost.modulate = Color(1, 1, 1, 1)
		_tween.tween_property(ghost, "position:y", -rise, params.transition_s)
		_tween.tween_property(ghost, "modulate:a", 0.0, params.transition_s)
		_tween.chain().tween_callback(func() -> void: ghost.visible = false)
	else:
		# 새 맨 위 층(또는 외관)이 위에서 내려앉는다
		var top := layers[0]
		top.position = Vector2(0, -rise)
		top.modulate.a = 0.0
		_tween.tween_property(top, "position:y", 0.0, params.transition_s)
		_tween.tween_property(top, "modulate:a", 1.0, params.transition_s)


## 비켜 놓은 두 층: 이어진 계단마다 아래층 계단 → 위층 계단 점선 (2026-11-12)
func _draw_links() -> void:
	if _exterior or stack == null or not stack.staggered() or sim == null:
		return
	var pa := stack.partner(_level)
	if pa < 0:
		return
	var lower := _level if sim.building.floor_number(pa) > sim.building.floor_number(_level) else pa
	var upper := pa if lower == _level else _level
	# 지금 층은 제자리, 짝 층은 offset_vec만큼 비켜 있다
	var lower_y := Vector2.ZERO if lower == _level else stack.offset_vec(1)
	var upper_y := -stack.offset_vec(1) if upper != _level else Vector2.ZERO
	var st: StairCores = sim.command.stairs
	var color := Color(1.0, 0.85, 0.3, 0.85)
	for i in st.cores(lower).size():
		var land := st.landing(lower, i, upper)
		if land.x < 0:
			continue
		var a := _proj.to_screen(st.center(lower, i), 0.05) + lower_y
		var b := _proj.to_screen(Vector2(land) + Vector2(0.5, 0.5), 0.05) + upper_y
		_links.draw_dashed_line(a, b, color, 2.0, 8.0)
		_links.draw_circle(a, 4.0, color)
		_links.draw_circle(b, 4.0, color)
		_links.draw_string(PlanStyle.font(), (a + b) * 0.5 + Vector2(8, 0), "%s 계단" % st.label(lower, i), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	# 층 이름표: 각 층 앞쪽 왼쪽 모서리에 "N층" (고른 층은 진하게)
	for spec in [[lower, lower_y], [upper, upper_y]]:
		var lv: int = spec[0]
		var fpl := sim.building.footprint(lv)
		var at: Vector2 = _proj.to_screen(Vector2(fpl.position.x, fpl.end.y), 0.0) + spec[1] + Vector2(-70, 20)
		var mine := lv == _level
		_links.draw_string(PlanStyle.font(), at, sim.building.floor_name(lv) + (" ◀ 지금 층" if mine else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 22 if mine else 18,
			Color(1, 0.92, 0.55, 1.0) if mine else Color(1, 1, 1, 0.55))
	# 분해도 안내선: 아래층 건물 모서리 → 위층 같은 모서리 (들어 올린 층이라는 표시)
	var fp := sim.building.footprint(lower)
	var guide := Color(1, 1, 1, params.stagger_guide_alpha)
	for c in [Vector2(fp.position), Vector2(fp.end.x, fp.position.y), Vector2(fp.end), Vector2(fp.position.x, fp.end.y)]:
		_links.draw_dashed_line(_proj.to_screen(c) + lower_y, _proj.to_screen(c) + upper_y, guide, 1.5, 6.0)


func _process(_delta: float) -> void:
	if _links:
		_links.queue_redraw()
	if _shadow:
		_shadow.queue_redraw()
	_update_holes()


## 비켜 놓은 두 층: (위층 노드, 아래층 노드, 아래층 level). 없으면 빈 배열
func _pair() -> Array:
	if _exterior or stack == null or not stack.staggered() or sim == null:
		return []
	var pa := stack.partner(_level)
	if pa < 0:
		return []
	if sim.building.floor_number(pa) > sim.building.floor_number(_level):
		return [upper_layers[0], layers[0], _level] if upper_layers[0].visible else []
	return [layers[0], layers[1], pa] if layers.size() > 1 and layers[1].visible else []


## 아래층의 대원·발견한 요구조자 둘레만 위층을 반투명하게 (셰이더 uniform)
func _update_holes() -> void:
	var pair := _pair()
	for node in layers + upper_layers:
		var m := node.material as ShaderMaterial
		if m:
			m.set_shader_parameter("count", 0)
	if pair.is_empty():
		return
	var upper: FloorLayer = pair[0]
	var lower: FloorLayer = pair[1]
	var lv: int = pair[2]
	var holes: Array[Vector4] = []
	var xf := lower.get_global_transform()
	var r := params.unit_hole_px
	for ff in sim.units.firefighters:
		if ff.level == lv and not ff.aboard and holes.size() < 16:
			var w: Vector2 = xf * _proj.to_screen(ff.pos, 0.9)
			holes.append(Vector4(w.x, w.y, r, 0.0))
	for v in sim.rescue.victims:
		if v.discovered and v.level == lv and v.carried_by < 0 and holes.size() < 16:
			var w2: Vector2 = xf * _proj.to_screen(v.pos, 0.3)
			holes.append(Vector4(w2.x, w2.y, r, 0.0))
	var mat := upper.material as ShaderMaterial
	if mat == null:
		return
	while holes.size() < 16:
		holes.append(Vector4.ZERO)
	mat.set_shader_parameter("holes", holes)
	mat.set_shader_parameter("count", mini(16, holes.filter(func(h: Vector4) -> bool: return h.z > 0.0).size()))
	mat.set_shader_parameter("min_alpha", params.unit_hole_alpha)


## 위층 그림자: 위층 바닥을 아래층 바닥 높이로 내린 자리
func _draw_shadow() -> void:
	var pair := _pair()
	if pair.is_empty():
		return
	var upper: FloorLayer = pair[0]
	var fp := sim.building.footprint(upper.level)
	var drop := Vector2(0, params.stagger_floor_px)
	var pts := PackedVector2Array()
	for c in [Vector2(fp.position), Vector2(fp.end.x, fp.position.y), Vector2(fp.end), Vector2(fp.position.x, fp.end.y)]:
		pts.append(_proj.to_screen(c) + upper.position + drop)
	_shadow.draw_colored_polygon(pts, Color(0, 0, 0, params.upper_shadow_alpha))
