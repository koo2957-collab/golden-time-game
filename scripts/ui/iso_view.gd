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
## 짝 층의 불·연기·사람만 원래 색으로 그리는 겹 (바탕은 흑백, 2026-11-12)
var partner_live: FloorLayer
## 지금 층의 움직이는 것(사람·불·연기·수관·구역·차량)을 원래 색으로 그리는 겹 — 바탕은 색을 뺀다 (2026-11-12)
var current_live: FloorLayer
var _shadow: Node2D
var _hole_shader: Shader
var _proj: IsoProjection
## 층 분리 보기 (시험 화면, 2026-11-14): 지금 층과 짝 층을 화면 위아래로 떼어 둘 다 온전하게 보인다.
## 위층을 반투명하게 하거나 뚫지 않는다. 실제 층·칸 좌표는 그대로이고 그리는 위치만 띄운다.
## 그리기는 예전 비켜 놓기(stagger)를 그대로 쓰되 뒤로 비키지 않고 위로만 띄운다
var split := false
## 위층을 띄운 거리 (화면 px)
var split_lift_px := 0.0
## 끄면 되돌릴 설정 [stack_mode, stagger_back_ratio, stagger_floor_px]
var _split_saved: Array = []


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


## 층 분리 보기를 쓸 수 있는 건물인가 (층 번호가 이어진 층이 둘 이상)
func split_available() -> bool:
	if stack == null or sim == null:
		return false
	for lv in sim.building.levels():
		if stack.partner(lv) >= 0:
			return true
	return false


## 층 분리 보기를 켜고 끈다. lift_px 를 주면 그 간격으로 (0 이하면 기본 간격)
func set_split(on: bool, lift_px := -1.0) -> void:
	if layers.is_empty():
		return
	if on and not split:
		_split_saved = [params.stack_mode, params.stagger_back_ratio, params.stagger_floor_px]
	if on:
		split_lift_px = maxf(params.split_min_px, lift_px) if lift_px > 0.0 else stack.split_default_lift_px()
		params.stack_mode = "stagger"
		params.stagger_back_ratio = 0.0
		params.stagger_floor_px = split_lift_px
	elif split:
		params.stack_mode = _split_saved[0]
		params.stagger_back_ratio = _split_saved[1]
		params.stagger_floor_px = _split_saved[2]
	split = on
	stack = FloorStack.new(sim.building, params)
	for node: FloorLayer in layers + upper_layers + [current_live, partner_live, ghost]:
		node.stack = stack
	if _tween != null:
		_tween.kill()
	ghost.visible = false
	_apply()


## 층 분리 보기에서 지금 층과 짝 층이 차지하는 화면 범위 (world 좌표, 벽 높이까지). 카메라 맞춤·이동 범위용.
## 분리 보기가 아니거나 짝 층이 없으면 지금 층만
func split_rect() -> Rect2:
	var specs: Array = [[_level, Vector2.ZERO]]
	if split and not _exterior:
		var pa := stack.partner(_level)
		if pa >= 0:
			var up: bool = sim.building.floor_number(pa) > sim.building.floor_number(_level)
			specs.append([pa, stack.upper_vec(1) if up else stack.offset_vec(1)])
	var r := Rect2()
	var first := true
	for spec: Array in specs:
		var fp := sim.building.footprint(spec[0])
		var off: Vector2 = spec[1]
		for c: Vector2 in [Vector2(fp.position), Vector2(fp.end.x, fp.position.y), Vector2(fp.end), Vector2(fp.position.x, fp.end.y)]:
			for h: float in [0.0, params.inner_wall_m]:
				var p: Vector2 = _proj.to_screen(c, h) + off
				if first:
					r = Rect2(p, Vector2.ZERO)
					first = false
				else:
					r = r.expand(p)
	return r


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


## 비켜 놓기: 짝 층 바탕은 흑백(불·연기·사람 빼고), 그 위 색 겹에 불·연기·사람만 원래 색으로 (2026-11-12 사용자 결정)
func _apply_partner() -> void:
	for node in layers + upper_layers:
		node.skip_live = false
		node.people_outline = false
	if partner_live == null:
		return
	partner_live.visible = false
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
	var pair := _pair()
	if pair.is_empty():
		# 제자리 쌓기: 아래층들은 흑백 바탕(연기·불·사람 빼고) + 사람 점선 테두리.
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
	var other: FloorLayer = pair[0] if pair[0] != layers[0] else pair[1]
	other.skip_live = true
	partner_live.visible = true
	partner_live.ghost_mode = 4
	partner_live.depth = ABOVE_DEPTH + 10
	partner_live.level = other.level
	partner_live.exterior = false
	partner_live.thermal = thermal
	partner_live.position = other.position
	partner_live.modulate = Color(1, 1, 1, params.partner_live_alpha)
	partner_live.refresh()


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
	# 지금 층 색 겹은 바탕 층의 전환 연출(위치·투명도)을 그대로 따라간다
	if current_live and current_live.visible and not layers.is_empty():
		current_live.position = layers[0].position
		current_live.modulate.a = layers[0].modulate.a
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
	var partner_node: FloorLayer = null
	var pr := _pair()
	if not pr.is_empty():
		partner_node = pr[0] if pr[0] != layers[0] else pr[1]
	for node in layers + upper_layers:
		var m := node.material as ShaderMaterial
		if m:
			m.set_shader_parameter("count", 0)
			var g := 0.0
			if node == partner_node or (not stack.staggered() and not _exterior and layers.find(node) > 0):
				g = params.partner_gray
			elif node == layers[0] and not _exterior:
				g = params.current_gray
			m.set_shader_parameter("gray", g)
	# 지금 층: 대원·발견한 요구조자·불난 방보다 앞에 선 실내 벽만 옅게 (F04 3단계, 2026-11-12 사용자 결정)
	var wall_holes: Array[Vector4] = []
	if not _exterior and not layers.is_empty():
		wall_holes = _wall_fade_holes(layers[0])
	if pair.is_empty() or pair[0] != layers[0]:
		_set_holes(layers[0], wall_holes)
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
	# 불난 방 (타는 칸이 있는 구획): 방 가운데, 방 크기에 맞춘 반지름
	var rooms := {}
	var grid := sim.fire.grid
	for i in grid.burning:
		var c3 := grid.cell_of(i)
		if c3.z == lv:
			var comp := sim.fire.compartment_at(c3.z, c3.x, c3.y)
			if comp:
				rooms[comp.index] = comp
	for comp: Compartment in rooms.values():
		if holes.size() >= 16:
			break
		var wc: Vector2 = xf * _proj.to_screen(Vector2(comp.rect.get_center()), 0.5)
		var rr := clampf(Vector2(comp.rect.size).length() * IsoProjection.HALF_W * 0.6, r, params.fire_hole_px)
		holes.append(Vector4(wc.x, wc.y, rr, 0.0))
	# 지금 층이 위층(맨 위층에서 아래층과 짝)이면 벽 구멍도 같은 그림에
	if upper == layers[0]:
		holes.append_array(wall_holes)
	_set_holes(upper, holes)


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


## 위층 그림자: 위층 바닥을 아래층 바닥 높이로 내린 자리
func _draw_shadow() -> void:
	var pair := _pair()
	# 층 분리 보기는 위로만 띄워 그림자가 아래층 전체를 덮으므로 그리지 않는다
	if pair.is_empty() or split:
		return
	var upper: FloorLayer = pair[0]
	var fp := sim.building.footprint(upper.level)
	var drop := Vector2(0, params.stagger_floor_px)
	var pts := PackedVector2Array()
	for c in [Vector2(fp.position), Vector2(fp.end.x, fp.position.y), Vector2(fp.end), Vector2(fp.position.x, fp.end.y)]:
		pts.append(_proj.to_screen(c) + upper.position + drop)
	_shadow.draw_colored_polygon(pts, Color(0, 0, 0, params.upper_shadow_alpha))
