class_name BoardMap
extends Control
## 전술상황판 가운데 평면도 (기획안 9-2-1, P10-1). 실제 불·연기·사람을 읽지 않고 KnowledgeBoard(무전 보고)만 그린다.
##   내부 층: 대원이 밝힌 구조(도면을 얻으면 도면), 보고된 화점·연기, 요구조자(보고·구조), 위험 징후, 검색 완료(빗금),
##            팀(마지막 보고 위치·보고 시각, 60초 넘으면 흐리게), 호스 라인, RIT
##   외부(level = -1): 차량·대기 장소, 소화전·급수 연결, 진입구, 안전구역·집결지·분류소, 지휘소, 밖의 조
## 팀 아이콘을 방·세대로 끌어다 놓으면 임무 창 (진입 지시 3~4단계)

signal crew_dropped(crew_id: int, target: Vector3i, screen_pos: Vector2)

const STALE_S := 60.0
const BG := Color(0.05, 0.08, 0.12, 0.92)
const WALL := Color("cbd5e1")
const FLOOR := Color(0.22, 0.26, 0.32)
const DOOR := Color("a16207")
const UNKNOWN := Color(0.1, 0.12, 0.16)
const FIRE := Color(0.95, 0.25, 0.15, 0.55)
const SMOKE := Color(0.6, 0.6, 0.65, 0.35)
const HATCH := Color(0.5, 0.85, 0.6, 0.6)

var sim: SimWorld
## 보는 층 (-1 = 외부)
var level := -1
var _drag_crew := -1
var _drag_at := Vector2.ZERO


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


## 그릴 범위 (칸): 층 탭은 건물 바닥 둘레, 외부는 지도 전체
func _bounds() -> Rect2:
	var b := sim.building
	if level < 0:
		return Rect2(0, 0, b.width, b.height)
	return Rect2(b.footprint(level)).grow(3.0).intersection(Rect2(0, 0, b.width, b.height))


func _scale() -> float:
	var r := _bounds()
	return minf(size.x / r.size.x, size.y / r.size.y)


func _origin() -> Vector2:
	var r := _bounds()
	return (size - r.size * _scale()) * 0.5 - r.position * _scale()


func to_px(cell: Vector2) -> Vector2:
	return _origin() + cell * _scale()


func to_cell(p: Vector2) -> Vector2:
	return (p - _origin()) / _scale()


## 지금 그리는 층의 실제 층 번호 (외부 = 가장 아래층)
func draw_level() -> int:
	return sim.building.levels()[0] if level < 0 else level


## 상황판에 그릴 화점 구획 (KnowledgeBoard에 보고된 것만) — 테스트가 쓴다
func fire_rooms(lv: int) -> Array[int]:
	var out: Array[int] = []
	for idx: int in sim.knowledge.fires:
		if sim.fire.comps[idx].level == lv:
			out.append(idx)
	return out


func _alpha(since_tick: int) -> float:
	return 0.45 if KnowledgeBoard.age_s(since_tick, sim.clock.tick) > STALE_S else 1.0


func _draw() -> void:
	if sim == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var s := _scale()
	var b := sim.building
	var lv := draw_level()
	var kb := sim.knowledge
	var font := get_theme_default_font()
	# 구조: 대원이 밝힌 칸, 도면을 얻었으면 도면
	var plan_ok: bool = sim.plan.known or not sim.perception.enabled
	for y in b.height:
		for x in b.width:
			var t := b.cell(lv, x, y)
			var r := Rect2(to_px(Vector2(x, y)), Vector2(s, s) + Vector2(0.5, 0.5))
			if t in BuildingData.OUTDOOR:
				if level < 0:
					draw_rect(r, Color(0.16, 0.18, 0.2) if t == BuildingData.Cell.ROAD else Color(0.12, 0.15, 0.13))
				continue
			if level < 0:
				draw_rect(r, Color(0.3, 0.33, 0.38))
				continue
			var seen: bool = sim.plan.structure_seen(lv, x, y)
			if not seen and not plan_ok:
				draw_rect(r, UNKNOWN)
				continue
			var pt: int = t if seen else sim.plan.plan_cell(lv, x, y)
			match pt:
				BuildingData.Cell.WALL, BuildingData.Cell.WINDOW:
					draw_rect(r, WALL)
				BuildingData.Cell.DOOR:
					draw_rect(r, DOOR)
				_:
					draw_rect(r, FLOOR)
	if level >= 0:
		_draw_inside(lv, kb, font)
	else:
		_draw_outside(font)


func _draw_inside(lv: int, kb: KnowledgeBoard, font: Font) -> void:
	var s := _scale()
	for idx: int in kb.smoky:
		var c := sim.fire.comps[idx]
		if c.level == lv:
			for cell in c.cells:
				draw_rect(Rect2(to_px(Vector2(cell)), Vector2(s, s)), Color(SMOKE, SMOKE.a * _alpha(kb.smoky[idx])))
	for idx in fire_rooms(lv):
		var c := sim.fire.comps[idx]
		for cell in c.cells:
			draw_rect(Rect2(to_px(Vector2(cell)), Vector2(s, s)), Color(FIRE, FIRE.a * _alpha(kb.fires[idx])))
		draw_string(font, to_px(Vector2(c.rect.get_center())) + Vector2(-40, 0), "화점 (보고)", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color("fecaca"))
	# 검색 완료: 빗금
	for idx: int in kb.searched:
		var c := sim.fire.comps[idx]
		if c.level != lv:
			continue
		var r := Rect2(to_px(Vector2(c.rect.position)), Vector2(c.rect.size) * s)
		var step := 10.0
		var k := 0.0
		while k < r.size.x + r.size.y:
			var a := r.position + Vector2(minf(k, r.size.x), maxf(0.0, k - r.size.x))
			var b2 := r.position + Vector2(maxf(0.0, k - r.size.y), minf(k, r.size.y))
			draw_line(a, b2, HATCH, 1.0)
			k += step
	# 호스 라인 (우리 장비)
	for h in sim.water.hoses:
		var pts := PackedVector2Array()
		for p in h.points:
			if p.z == lv:
				pts.append(to_px(Vector2(p.x, p.y) + Vector2(0.5, 0.5)))
		if pts.size() >= 2:
			draw_polyline(pts, PlanStyle.HOSE_COLOR, 2.0)
	for hz in kb.hazards:
		if int(hz.level) != lv or hz.pos.x < 0:
			continue
		var p := to_px(hz.pos)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -9), p + Vector2(8, 6), p + Vector2(-8, 6)]), Color(1, 0.8, 0.1, _alpha(hz.tick)))
		draw_string(font, p + Vector2(-50, 20), str(hz.kind), HORIZONTAL_ALIGNMENT_CENTER, 100, 12, Color(1, 0.85, 0.4, _alpha(hz.tick)))
	for vid: int in kb.victims:
		var v: Dictionary = kb.victims[vid]
		if int(v.level) != lv:
			continue
		var col := Color("4ade80") if v.state == "구조" else Color("fde047")
		draw_circle(to_px(v.pos), 6.0, Color(col, _alpha(v.tick)))
		draw_string(font, to_px(v.pos) + Vector2(-40, -10), "요구조자 %s" % v.state, HORIZONTAL_ALIGNMENT_CENTER, 80, 11, col)
	_draw_crews(lv, font)


## 팀: 건물 안은 마지막 보고 위치·보고 시각 (보고가 없으면 그리지 않음), 밖은 지금 자리
func _draw_crews(lv: int, font: Font) -> void:
	for c in sim.units.crews:
		var at := crew_spot(c.id)
		if at.z != lv or at.x < -999:
			continue
		var p := to_px(Vector2(at.x, at.y))
		var info: Dictionary = sim.knowledge.crews.get(c.id, {})
		var inside := sim.command.interior.crew_inside(c.id)
		var a := _alpha(int(info.get("tick", sim.clock.tick))) if inside else 1.0
		var col: Color = sim.units.squads[c.squad_id].color
		draw_circle(p, 9.0, Color(col, a))
		if sim.command.safety.role_of(c.id) == SafetySystem.Role.RIT:
			draw_arc(p, 12.0, 0.0, TAU, 20, Color(1, 1, 1, a), 2.0)
		draw_string(font, p + Vector2(-4, 4), str(c.number), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, a))
		if inside:
			var age := KnowledgeBoard.age_s(int(info.get("tick", -1)), sim.clock.tick)
			draw_string(font, p + Vector2(-50, -13), "%s %d조 · %d초 전" % [sim.units.squads[c.squad_id].name, c.number, roundi(age)],
				HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color(1, 1, 1, a))


## 상황판에 보이는 조 자리 (x, y, 층). 건물 안인데 보고가 없으면 (-1000, …)
func crew_spot(crew_id: int) -> Vector3:
	var c := sim.units.get_crew(crew_id)
	if c.leader.aboard:
		return Vector3(-1000, 0, -99)
	if not sim.command.interior.crew_inside(crew_id):
		return Vector3(c.leader.pos.x, c.leader.pos.y, c.leader.level)
	var info: Dictionary = sim.knowledge.crews.get(crew_id, {})
	if info.is_empty():
		return Vector3(-1000, 0, -99)
	return Vector3(info.pos.x, info.pos.y, int(info.level))


func _draw_outside(font: Font) -> void:
	ZoneDraw.draw(self, sim.zones, func(p: Vector2) -> Vector2: return to_px(p), 12, sim.clock.tick)
	for h in sim.building.hydrants:
		draw_circle(to_px(Vector2(h) + Vector2(0.5, 0.5)), 5.0, PlanStyle.HYDRANT_COLOR)
	for v in sim.units.vehicles:
		if v.away:
			continue
		var p := to_px(v.pos)
		draw_rect(Rect2(p - Vector2(10, 6), Vector2(20, 12)), Color(sim.units.squads[v.squad_id].color, 0.9))
		draw_string(font, p + Vector2(-30, -9), str(v.type), HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color.WHITE)
		if v.hydrant >= 0:
			draw_line(p, to_px(Vector2(sim.building.hydrants[v.hydrant]) + Vector2(0.5, 0.5)), PlanStyle.WATER_COLOR, 2.0)
		if v.supply_to >= 0:
			draw_line(p, to_px(sim.units.get_vehicle(v.supply_to).pos), PlanStyle.WATER_COLOR, 2.0)
	for e in sim.entries.list:
		var ep := to_px(Vector2(e.door) + Vector2(0.5, 0.5))
		draw_circle(ep, 6.0, PlanStyle.ENTRY_POINT)
		draw_string(font, ep + Vector2(-50, 16), e.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 11, PlanStyle.ENTRY_POINT)
	var cp := to_px(sim.command.commander.pos)
	draw_rect(Rect2(cp - Vector2(6, 6), Vector2(12, 12)), PlanStyle.COMMANDER_HELMET)
	draw_string(font, cp + Vector2(-30, -9), "지휘소", HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color.WHITE)
	_draw_crews(sim.building.levels()[0], font)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_crew = crew_at(event.position)
			_drag_at = event.position
		elif _drag_crew >= 0:
			var id := _drag_crew
			_drag_crew = -1
			if event.position.distance_to(_drag_at) > 6.0:
				var cell := to_cell(event.position)
				crew_dropped.emit(id, Vector3i(floori(cell.x), floori(cell.y), draw_level()), get_global_transform() * event.position)
		accept_event()


## 상황판의 팀 아이콘 (누른 자리 12px 안)
func crew_at(p: Vector2) -> int:
	for c in sim.units.crews:
		var at := crew_spot(c.id)
		if at.z == draw_level() and to_px(Vector2(at.x, at.y)).distance_to(p) <= 12.0:
			return c.id
	return -1
