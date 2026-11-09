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
	# 위층 (지금 층 위에 반투명으로, 기획안 9-4)
	for k in params.visible_floors_above:
		var up := FloorLayer.new()
		up.name = "Above%d" % (k + 1)
		add_child(up)
		up.setup(sim, p_selection, p_proj, stack)
		upper_layers.append(up)
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
		layer.position = Vector2(0, stack.offset_px(depth))
		var m := stack.modulate_for(depth)
		layer.modulate = Color(m, m, m, 1.0)
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
		up.refresh()
		up.position = Vector2(0, -stack.offset_px(k + 1))
		up.modulate = Color(1, 1, 1, params.above_alpha)


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
