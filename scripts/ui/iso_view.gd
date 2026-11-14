class_name IsoView
extends Node2D
## 입체(아이소메트릭) 화면. 층 노드(FloorLayer)를 묶어 건물을 두 모습으로 보여 준다 (R17).
##   외부 보기: 지상층 노드 하나가 바깥(도로·차량)과 건물 외관을 그린다.
##   내부 화면(층 분리, 2026-11-14 사용자 결정): 고른 층은 제자리, 직상층은 위로, 직하층은 아래로 떼어
##     세 층 모두 온전하게(불투명) 그린다. 이웃 층 바탕은 흑백·조금 어둡게, 사람·불·연기는 원래 색 (색 겹).
##   (예전) 단면 보기(인형집): 지금 층과 아래 층(FloorStack)을 층 노드마다 쌓아 그린다.
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
## 짝 층의 불·연기·사람만 원래 색으로 그리는 겹 (바탕은 흑백, 2026-11-12)
var partner_live: FloorLayer
## 지금 층의 움직이는 것(사람·불·연기·수관·구역·차량)을 원래 색으로 그리는 겹 — 바탕은 색을 뺀다 (2026-11-12)
var current_live: FloorLayer
var _hole_shader: Shader
var _proj: IsoProjection
## 직하층의 불·연기·사람 색 겹 (내부 화면에서 이웃 층이 둘일 때)
var partner_live_low: FloorLayer


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
	current_live = FloorLayer.new()
	current_live.name = "CurrentLive"
	add_child(current_live)
	current_live.setup(sim, p_selection, p_proj, stack)
	current_live.visible = false
	# 지금 층 바로 다음에 그린다 (위층보다 먼저 — 위층이 가리는 곳은 구멍으로 비친다)
	move_child(current_live, layers[0].get_index() + 1)
	partner_live = FloorLayer.new()
	partner_live.name = "PartnerLive"
	add_child(partner_live)
	partner_live.setup(sim, p_selection, p_proj, stack)
	partner_live.visible = false
	partner_live_low = FloorLayer.new()
	partner_live_low.name = "PartnerLiveLow"
	add_child(partner_live_low)
	partner_live_low.setup(sim, p_selection, p_proj, stack)
	partner_live_low.visible = false
	# 떼어 놓은 층들의 계단을 잇는 점선 (위층 위에 그린다)
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
	# 전환 연출은 예전 제자리 단면에서만 — 내부 화면(층 분리)은 층들이 화면에서 제자리에 있어야 하고
	# 안팎을 오갈 때는 카메라가 함께 바뀐다 (2026-11-14)
	if changed and animate and params.transition_s > 0.0 and is_inside_tree() and not stack.staggered():
		_animate(old_level, old_exterior)


## 내부 화면의 층 간격을 바꾼다 (화면 px). 실제 층·칸 좌표와 무관 — 그리는 위치만
func set_lift(px: float) -> void:
	if layers.is_empty():
		return
	params.split_lift_px = maxf(params.split_min_px, px)
	stack = FloorStack.new(sim.building, params)
	for node: FloorLayer in _all_layers():
		node.stack = stack
	if _tween != null:
		_tween.kill()
	ghost.visible = false
	_apply()


func lift_px() -> float:
	return stack.lift_px if stack != null else 0.0


func _all_layers() -> Array[FloorLayer]:
	var out: Array[FloorLayer] = []
	out.append_array(layers)
	out.append_array(upper_layers)
	out.append_array([current_live, partner_live, partner_live_low, ghost])
	return out


## 내부 화면에서 함께 보이는 층과 그 화면 위치 (아래층부터): [[level, Vector2], ...]. 외부 화면이면 지금 층만
func shown_floors() -> Array:
	var out: Array = []
	if _exterior or stack == null or not stack.staggered():
		return [[_level, Vector2.ZERO]]
	var vis := stack.visible_levels(_level)
	if vis.size() > 1:
		out.append([vis[1], stack.offset_vec(1)])
	out.append([_level, Vector2.ZERO])
	var above := stack.above_levels(_level)
	if not above.is_empty():
		out.append([above[0], stack.upper_vec(1)])
	return out


## 층 하나가 차지하는 화면 범위 (world 좌표, 바닥부터 벽 높이까지)
func _floor_rect(lv: int, off: Vector2) -> Rect2:
	var fp := sim.building.footprint(lv)
	var r := Rect2(_proj.to_screen(Vector2(fp.position)) + off, Vector2.ZERO)
	for c: Vector2 in [Vector2(fp.position), Vector2(fp.end.x, fp.position.y), Vector2(fp.end), Vector2(fp.position.x, fp.end.y)]:
		for h: float in [0.0, params.inner_wall_m]:
			r = r.expand(_proj.to_screen(c, h) + off)
	return r


## 내부 화면의 화면 맞춤 범위 (2026-11-14 사용자 결정, 층 수 단추):
##   span 1 = 고른 층 하나 — 화면 가운데에 크게, 직상층·직하층은 위아래로 잘려 보인다
##   span 2 = 고른 층 + 짝 층 (기본 직상층, with_lower 면 직하층 — 그쪽 층이 없으면 반대쪽)
##   span 3 = 보이는 세 층 모두
func frame_rect(span := 1, with_lower := false) -> Rect2:
	var r := _floor_rect(_level, Vector2.ZERO)
	if span <= 1 or _exterior or stack == null or not stack.staggered():
		return r
	if span >= 3:
		return shown_rect()
	var pair := stack.pair_level(_level, with_lower)
	if pair < 0:
		return r
	var off := stack.upper_vec(1) if stack.neighbor_step(_level, pair) > 0 else stack.offset_vec(1)
	return r.merge(_floor_rect(pair, off))


## 보이는 모든 층의 화면 범위 (카메라 이동 범위용)
func shown_rect() -> Rect2:
	var r := _floor_rect(_level, Vector2.ZERO)
	for spec: Array in shown_floors():
		r = r.merge(_floor_rect(spec[0], spec[1]))
	return r


## 고른 층을 from 에서 to 로 바꿀 때, 층들이 화면에서 제자리에 있으려면 카메라가 움직여야 하는 거리.
## (고른 층이 늘 기준 자리에 오므로 위층을 고르면 모든 층이 한 간격 아래로 내려간다)
func level_shift(from: int, to: int) -> Vector2:
	if stack == null or not stack.staggered():
		return Vector2.ZERO
	return -stack.upper_vec(1) * float(sim.building.floor_number(to) - sim.building.floor_number(from))


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
		# 아래층도 온전히 그린다 (2026-11-12 사용자 결정): 지금 층이 가리는 곳 빼고 구조 그대로, 흑백 + 한 단계 어둡게.
		# 연기·불은 그리지 않고 사람은 점선 테두리 (_apply_partner). 비켜 놓기(stagger)의 짝 층도 온전하게
		layer.ghost_mode = 0
		var dim := params.partner_dim
		layer.modulate = Color(dim, dim, dim, params.partner_alpha) if stack.staggered() and depth > 0 else Color.WHITE
		# 자식(사람 테두리)은 어두워지지 않게 자기 그림만
		layer.self_modulate = Color(dim, dim, dim) if not stack.staggered() and depth > 0 and not _exterior else Color.WHITE
	# 위층: 지금 층 위로 FLOOR_GAP_PX씩 올려 반투명 (외부 보기에서는 숨김)
	var above: Array[int] = []
	if not _exterior and stack != null:
		above = stack.above_levels(_level)
	# 더 있는 층은 잘린 벽으로만 알린다 (2026-11-12 사용자 결정): 보이는 맨 위층 위, 보이는 맨 아래층 아래
	for d in layers.size():
		layers[d].stub_below = not _exterior and d > 0 and d == shown.size() - 1 and stack.more_below(_level)
	for k in upper_layers.size():
		upper_layers[k].stub_above = not above.is_empty() and k == above.size() - 1 and stack.more_above(_level)
	# 지금 층의 올라가는 계단을 입체 디딤판으로 (위층이 함께 보일 때, 2026-11-12 사용자 결정)
	if not above.is_empty() and layers[0].upper_level != above[0]:
		layers[0].upper_level = above[0]
		layers[0].refresh()
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
		up.position = stack.upper_vec(k + 1)
		# 비켜 놓기: 짝 위층은 흐리게. 예전 방식은 투명도가 선 색에 들어 있다
		var udim := params.partner_dim
		up.modulate = Color(udim, udim, udim, params.partner_alpha) if stack.staggered() else Color.WHITE
	_apply_partner()


## 바탕은 흑백(불·연기·사람 빼고), 그 위 색 겹에 불·연기·사람만 원래 색으로 (2026-11-12 사용자 결정).
## 내부 화면(층 분리)에서는 고른 층과 이웃 층(직상층·직하층) 모두 그렇게 그린다
func _apply_partner() -> void:
	for node in layers + upper_layers:
		node.skip_live = false
		node.people_outline = false
	if partner_live == null:
		return
	partner_live.visible = false
	partner_live_low.visible = false
	current_live.visible = false
	if _exterior or layers.is_empty():
		return
	# 지금 층: 바닥·벽·가구는 색을 뺀 바탕, 움직이는 것은 그 위 색 겹
	layers[0].skip_live = true
	current_live.visible = true
	current_live.ghost_mode = 4
	current_live.depth = 0
	current_live.level = _level
	current_live.exterior = false
	current_live.thermal = thermal
	current_live.upper_level = layers[0].upper_level
	current_live.lower_level = layers[0].lower_level
	current_live.position = layers[0].position
	current_live.modulate = Color.WHITE
	current_live.refresh()
	if not stack.staggered():
		# (예전) 제자리 쌓기: 아래층들은 흑백 바탕(연기·불·사람 빼고) + 사람 점선 테두리.
		# 땅 층이 아래로 보이면 그 위에 차량·바깥 사람만 원래 색으로 (바깥 땅 겹)
		for d in range(1, layers.size()):
			var low := layers[d]
			if not low.visible:
				continue
			low.skip_live = true
			low.people_outline = true
			if low.level == sim.building.levels()[0]:
				partner_live.visible = true
				partner_live.ghost_mode = 5
				partner_live.depth = low.depth
				partner_live.level = low.level
				partner_live.exterior = false
				partner_live.thermal = thermal
				partner_live.position = low.position
				partner_live.modulate = Color.WHITE
				move_child(partner_live, low.get_index() + 1)
				partner_live.refresh()
		return
	var lives: Array[FloorLayer] = [partner_live, partner_live_low]
	var nb := _neighbors()
	for i in nb.size():
		var other := nb[i]
		var live := lives[i]
		other.skip_live = true
		live.visible = true
		live.ghost_mode = 4
		live.depth = ABOVE_DEPTH + 10 + i
		live.level = other.level
		live.exterior = false
		live.thermal = thermal
		live.position = other.position
		live.modulate = Color(1, 1, 1, params.partner_live_alpha)
		# 이웃 층 위에 그린다 (맨 뒤로 — 계단 점선·잔상보다는 앞에 오지 않게 _links 앞)
		move_child(live, _links.get_index())
		live.refresh()


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


## 내부 화면(층 분리): 이웃한 두 층 사이마다 이어진 계단 점선과 건물 모서리 안내선, 층마다 이름표
func _draw_links() -> void:
	if _exterior or stack == null or not stack.staggered() or sim == null:
		return
	var shown := shown_floors()
	var st: StairCores = sim.command.stairs
	var color := Color(1.0, 0.85, 0.3, 0.85)
	var guide := Color(1, 1, 1, params.stagger_guide_alpha)
	for k in shown.size() - 1:
		var lower: int = shown[k][0]
		var lower_y: Vector2 = shown[k][1]
		var upper: int = shown[k + 1][0]
		var upper_y: Vector2 = shown[k + 1][1]
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
		# 분해도 안내선: 아래층 건물 모서리 → 위층 같은 모서리 (떼어 놓은 층이라는 표시)
		var fp := sim.building.footprint(lower)
		for c in [Vector2(fp.position), Vector2(fp.end.x, fp.position.y), Vector2(fp.end), Vector2(fp.position.x, fp.end.y)]:
			_links.draw_dashed_line(_proj.to_screen(c) + lower_y, _proj.to_screen(c) + upper_y, guide, 1.5, 6.0)
	# 층 이름표: 각 층 앞쪽 왼쪽 모서리에 "N층" (고른 층은 진하게)
	for spec: Array in shown:
		var lv: int = spec[0]
		var fpl := sim.building.footprint(lv)
		var at: Vector2 = _proj.to_screen(Vector2(fpl.position.x, fpl.end.y), 0.0) + spec[1] + Vector2(-70, 20)
		var mine := lv == _level
		_links.draw_string(PlanStyle.font(), at, sim.building.floor_name(lv) + (" ◀ 고른 층" if mine else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 22 if mine else 18,
			Color(1, 0.92, 0.55, 1.0) if mine else Color(1, 1, 1, 0.55))


func _process(_delta: float) -> void:
	if _links:
		_links.queue_redraw()
	# 지금 층 색 겹은 바탕 층의 전환 연출(위치·투명도)을 그대로 따라간다
	if current_live and current_live.visible and not layers.is_empty():
		current_live.position = layers[0].position
		current_live.modulate.a = layers[0].modulate.a
	_update_holes()


## 내부 화면(층 분리)에서 고른 층 말고 함께 보이는 이웃 층 노드 (직상층·직하층)
func _neighbors() -> Array[FloorLayer]:
	var out: Array[FloorLayer] = []
	if _exterior or stack == null or not stack.staggered() or sim == null:
		return out
	if not upper_layers.is_empty() and upper_layers[0].visible:
		out.append(upper_layers[0])
	if layers.size() > 1 and layers[1].visible:
		out.append(layers[1])
	return out


## 층마다 바탕 흑백 정도를 셰이더에 넣고, 고른 층은 대원·요구조자·불난 방 앞에 선 실내 벽만 옅게 한다.
## 층 분리에서는 층끼리 가리지 않으므로 위층에 구멍을 내지 않는다 (위층을 투명하게 하지 않는다, 2026-11-14)
func _update_holes() -> void:
	var nb := _neighbors()
	for node in layers + upper_layers:
		var m := node.material as ShaderMaterial
		if m:
			m.set_shader_parameter("count", 0)
			var g := 0.0
			if node in nb or (not stack.staggered() and not _exterior and layers.find(node) > 0):
				g = params.partner_gray
			elif node == layers[0] and not _exterior:
				g = params.current_gray
			m.set_shader_parameter("gray", g)
	# 지금 층: 대원·발견한 요구조자·불난 방보다 앞에 선 실내 벽만 옅게 (F04 3단계, 2026-11-12 사용자 결정)
	var wall_holes: Array[Vector4] = []
	if not _exterior and not layers.is_empty():
		wall_holes = _wall_fade_holes(layers[0])
	_set_holes(layers[0], wall_holes)


## 셰이더 구멍 설정 (16개까지)
func _set_holes(node: FloorLayer, holes: Array[Vector4]) -> void:
	var mat := node.material as ShaderMaterial
	if mat == null:
		return
	var list := holes.slice(0, 16)
	var n := list.size()
	while list.size() < 16:
		list.append(Vector4.ZERO)
	mat.set_shader_parameter("holes", list)
	mat.set_shader_parameter("count", n)
	mat.set_shader_parameter("min_alpha", params.unit_hole_alpha)
	mat.set_shader_parameter("wall_min_alpha", params.wall_fade_alpha)


## 지금 층에서 벽을 옅게 할 대상: [화면 x, y, 반지름, 대상 깊이(칸 x + y) + 1].
## 대원(조 단위로 겹치면 하나), 발견한 요구조자, 타는 칸이 있는 방 가운데
func _wall_fade_holes(node: FloorLayer) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var xf := node.get_global_transform()
	var r := params.wall_fade_px
	var add := func(p: Vector2, h: float, rr: float) -> void:
		var w: Vector2 = xf * _proj.to_screen(p, h)
		for o in out:
			if Vector2(o.x, o.y).distance_to(w) < rr * 0.3:
				return
		out.append(Vector4(w.x, w.y, rr, p.x + p.y + 1.0))
	for ff in sim.units.firefighters:
		if ff.level == _level and not ff.aboard:
			add.call(ff.pos, 1.0, r)
	for v in sim.rescue.victims:
		if v.discovered and v.level == _level and v.carried_by < 0:
			add.call(v.pos, 0.4, r)
	var rooms := {}
	var grid := sim.fire.grid
	for i in grid.burning:
		var c3 := grid.cell_of(i)
		if c3.z == _level:
			var comp := sim.fire.compartment_at(c3.z, c3.x, c3.y)
			if comp:
				rooms[comp.index] = comp
	for comp: Compartment in rooms.values():
		add.call(Vector2(comp.rect.get_center()), 1.0, clampf(Vector2(comp.rect.size).length() * IsoProjection.HALF_W * 0.6, r, params.fire_hole_px))
	return out
