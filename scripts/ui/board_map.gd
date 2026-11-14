class_name BoardMap
extends Control
## 전술상황판 가운데 평면도 (기획안 9-2-1, P10-1). 실제 불·연기·사람을 읽지 않고 KnowledgeBoard(무전 보고)만 그린다.
## 2026-11-14 화이트보드: 흰 판에 마커 선으로 그린 평면도 + 기호 + 자석 명패 + 범례 (기호·색은 data/ui/board_style.json).
##   내부 층: 대원이 밝힌 구조(도면을 얻으면 도면, 안 본 곳은 회색 빈칸에 건물 외곽선만), 직하층 확인 추정 구조(점선),
##            보고된 화점(불꽃 + 빨간 빗금)·연기(물결선), 구조대상자(사람 표시 + 인원수, 구조 완료는 체크), 위험 징후(삼각형),
##            검색 지시(/)·검색 완료(✕), 조 자석(마지막 보고 위치·보고 시각, 오래되면 흐리게), 수관(방수 중 실선·연장만 점선)
##   외부(level = -1): 차량 자석, 소화전·급수 연결, 수관, 진입구 화살표, 구역(점선)·집결지·분류소, 지휘소 깃발, 밖의 조
## 조 자석을 방·세대로 끌어다 놓으면 임무 창 (진입 지시 3~4단계)

signal crew_dropped(crew_id: int, target: Vector3i, screen_pos: Vector2)

## 범례 글 (기호 id → 설명)
const LEGEND := {
	"fire": "화점", "smoke": "연기", "victim": "구조대상자", "rescued": "구조 완료", "search_ordered": "검색 지시", "searched": "검색 완료",
	"hazard": "위험 징후", "hose_flow": "방수 중", "hose_laid": "수관 연장", "crew": "조 (흐림 = 오래된 보고)", "unseen": "아직 못 본 곳",
	"estimate": "추정 구조", "vehicle": "차량", "hydrant": "소화전", "supply": "급수", "entry": "진입구", "post": "지휘소",
	"safe_zone": "안전구역", "control_line": "진입통제선", "casualty": "집결지·분류소",
}
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var sim: SimWorld
var style: BoardStyle
## 보는 층 (-1 = 외부)
var level := -1
var _drag_crew := -1
var _drag_at := Vector2.ZERO


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	style = BoardStyle.get_default()
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _font() -> Font:
	return PlanStyle.font()


## 범례 자리 (판 아래 두 줄)
func legend_height() -> float:
	return style.legend_row_px * 2.0 + 8.0


## 평면도를 그리는 자리 (범례를 뺀 크기)
func _area() -> Vector2:
	return Vector2(maxf(1.0, size.x), maxf(1.0, size.y - legend_height()))


## 그릴 범위 (칸): 층 탭은 건물 바닥 둘레, 외부는 지도 전체
func _bounds() -> Rect2:
	var b := sim.building
	if level < 0:
		return Rect2(0, 0, b.width, b.height)
	return Rect2(b.footprint(level)).grow(3.0).intersection(Rect2(0, 0, b.width, b.height))


func _scale() -> float:
	var r := _bounds()
	var a := _area()
	return minf(a.x / r.size.x, a.y / r.size.y)


func _origin() -> Vector2:
	var r := _bounds()
	return (_area() - r.size * _scale()) * 0.5 - r.position * _scale()


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


## 보고가 오래되면 흐리게
func _alpha(since_tick: int) -> float:
	return style.stale_alpha if KnowledgeBoard.age_s(since_tick, sim.clock.tick) > style.stale_s else 1.0


## 지휘관이 아는 그 칸의 종류: 바깥·대원이 본 칸은 실제, 도면을 얻었으면 도면. 모르면 -1
func known_cell(lv: int, x: int, y: int) -> int:
	var b := sim.building
	if x < 0 or y < 0 or x >= b.width or y >= b.height:
		return -1
	var t := b.cell(lv, x, y)
	if t in BuildingData.OUTDOOR or sim.plan.structure_seen(lv, x, y):
		return t
	if sim.plan.known or not sim.perception.enabled:
		return sim.plan.plan_cell(lv, x, y)
	return -1


## 그 방의 구조를 아는가 (방 가운데쯤 칸으로 본다)
func room_known(c: Compartment) -> bool:
	if c.cells.is_empty():
		return false
	var cell: Vector2i = c.cells[c.cells.size() / 2]
	return known_cell(c.level, cell.x, cell.y) >= 0


## 검색을 지시해 둔 방 (지휘관이 내린 임무 기준, 아직 검색 완료 보고가 없는 것). 층 검색이면 그 층에서 구조를 아는 방 모두
func search_ordered_rooms(lv: int) -> Array[int]:
	var out: Array[int] = []
	if sim.tactical == null:
		return out
	for t in sim.tactical.tasks:
		if t.action != "search":
			continue
		if t.floor >= 0:
			if t.floor != lv:
				continue
			for c in sim.fire.comps:
				if c.level == lv and not sim.knowledge.searched.has(c.index) and room_known(c) and not out.has(c.index):
					out.append(c.index)
		elif t.room >= 0 and sim.fire.comps[t.room].level == lv and not sim.knowledge.searched.has(t.room) and not out.has(t.room):
			out.append(t.room)
	return out


## 자석에 쓰는 조 이름: "진압1-1" (+ RIT·안전)
func crew_label(c: Crew) -> String:
	var text := "%s-%d" % [sim.units.squads[c.squad_id].name, c.number]
	match sim.command.safety.role_of(c.id):
		SafetySystem.Role.RIT:
			text += " RIT"
		SafetySystem.Role.OFFICER:
			text += " 안전"
	return text


## 범례에 나올 기호 (지금 보는 판에 따라)
func legend_items() -> Array[String]:
	if level < 0:
		return ["vehicle", "crew", "hydrant", "supply", "hose_flow", "hose_laid", "entry", "post", "safe_zone", "control_line", "casualty"]
	var out: Array[String] = ["fire", "smoke", "victim", "rescued", "search_ordered", "searched", "hazard", "hose_flow", "hose_laid", "crew", "unseen"]
	if not _estimates(level).is_empty():
		out.append("estimate")
	return out


func _draw() -> void:
	if sim == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), style.color("board"))
	var lv := draw_level()
	var font := _font()
	if level >= 0:
		_draw_plan(lv, font)
		_draw_faces(lv, font)
		_draw_inside(lv, font)
	else:
		_draw_site(lv)
		_draw_faces(lv, font)
		_draw_outside(lv, font)
	var title := "외부 배치도" if level < 0 else "%s 평면도" % sim.building.floor_name(lv)
	draw_string(font, Vector2(10, 22), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, style.color("ink"))
	_draw_legend(font)


# --- 평면도 (내부 층) ---

static func _is_line(t: int) -> bool:
	return t == BuildingData.Cell.WALL or t == BuildingData.Cell.WINDOW or t == BuildingData.Cell.DOOR


## 구조: 흰 바탕에 마커 선. 벽 = 먹 선, 창 = 파란 선, 문 = 갈색 선, 계단 = 가는 줄. 모르는 칸은 회색 + 건물 외곽선
func _draw_plan(lv: int, font: Font) -> void:
	var b := sim.building
	var s := _scale()
	var w := maxf(style.wall_min_px, s * style.wall_ratio)
	var cells := Rect2i(_bounds())
	var est := _estimates(lv)
	var soft := style.color("ink_soft")
	for y in range(cells.position.y, cells.end.y):
		for x in range(cells.position.x, cells.end.x):
			if b.cell(lv, x, y) in BuildingData.OUTDOOR:
				continue
			var p := to_px(Vector2(x, y))
			var c := p + Vector2(s, s) * 0.5
			var t := known_cell(lv, x, y)
			if t < 0:
				draw_rect(Rect2(p, Vector2(s, s) + Vector2(0.5, 0.5)), style.color("unseen"))
				# 직하층 확인으로 추정한 벽: 점선 (칸마다 점 하나)
				if _is_line(_estimate_cell(est, x, y)):
					draw_rect(Rect2(c - Vector2(w, w) * 0.5, Vector2(w, w)), style.color("estimate"))
				# 건물 외곽선 (밖에서 보이는 것)
				for d in DIRS:
					var n := Vector2i(x, y) + d
					if n.x < 0 or n.y < 0 or n.x >= b.width or n.y >= b.height or b.cell(lv, n.x, n.y) in BuildingData.OUTDOOR:
						var mid := c + Vector2(d) * s * 0.5
						var side := Vector2(-d.y, d.x) * s * 0.5
						draw_line(mid - side, mid + side, soft, 1.5)
				continue
			if t == BuildingData.Cell.STAIRS:
				draw_line(p + Vector2(1.0, s * 0.3), p + Vector2(s - 1.0, s * 0.3), soft, 1.0)
				draw_line(p + Vector2(1.0, s * 0.75), p + Vector2(s - 1.0, s * 0.75), soft, 1.0)
			elif _is_line(t):
				var col := style.color("ink")
				var lw := w
				if t == BuildingData.Cell.WINDOW:
					col = style.color("window")
					lw = w * 0.6
				elif t == BuildingData.Cell.DOOR:
					col = style.color("door")
					lw = w * 0.6
				var linked := false
				for d in DIRS:
					if _is_line(known_cell(lv, x + d.x, y + d.y)):
						draw_line(c, c + Vector2(d) * s * 0.5, col, lw)
						linked = true
				var dot := lw if linked else s * 0.6
				draw_rect(Rect2(c - Vector2(dot, dot) * 0.5, Vector2(dot, dot)), col)
	# 추정 구조 범위와 이름
	for e: Dictionary in est:
		var r: Rect2i = e.rect
		var rect_px := Rect2(to_px(Vector2(r.position)), Vector2(r.size) * s)
		BoardSymbols.dashed_rect(self, rect_px, style.color("estimate"))
		draw_string(font, rect_px.position + Vector2(5, style.label_font + 4.0), "추정 구조 (직하층 %s)" % str(e.from),
			HORIZONTAL_ALIGNMENT_LEFT, -1, style.label_font, style.color("estimate"))
	# 방 이름 (구조를 아는 방만)
	for room in sim.fire.comps:
		if room.level != lv or room.name == "" or not room_known(room):
			continue
		var rect_px := Rect2(to_px(Vector2(room.rect.position)), Vector2(room.rect.size) * s)
		if rect_px.size.x < 44.0:
			continue
		draw_string(font, rect_px.position + Vector2(0.0, style.room_font + s * 0.6 + 2.0), room.name,
			HORIZONTAL_ALIGNMENT_CENTER, rect_px.size.x, style.room_font, soft)


## 직하층 확인으로 얻은 추정 구조: [{rect(위 세대), level(아래 세대 층), offset(아래 − 위), from(아래 세대 이름)}]
func _estimates(lv: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tac := sim.tactical
	if tac == null or tac.layout == null:
		return out
	for unit_name: String in tac.unit_estimates:
		var u := tac.layout.unit_named(unit_name)
		if u.is_empty() or int(u.level) != lv:
			continue
		var from_name := str(tac.unit_estimates[unit_name].get("from", ""))
		var src := tac.layout.unit_named(from_name)
		if src.is_empty():
			continue
		var ur: Rect2i = u.rect
		var sr: Rect2i = src.rect
		out.append({"rect": ur, "level": int(src.level), "offset": sr.position - ur.position, "from": from_name})
	return out


## 추정 구조에서 그 칸의 종류 (아래 세대의 같은 자리). 추정이 없으면 -1
func _estimate_cell(est: Array[Dictionary], x: int, y: int) -> int:
	for e: Dictionary in est:
		var r: Rect2i = e.rect
		if r.has_point(Vector2i(x, y)):
			var off: Vector2i = e.offset
			return sim.building.cell(int(e.level), x + off.x, y + off.y)
	return -1


## 건물 면 (SOP 105-2.2: 전면 A, 시계방향 B·C·D) — 건물 둘레 밖에
func _draw_faces(lv: int, font: Font) -> void:
	var fp := sim.building.footprint(lv)
	var s := _scale()
	var rect := Rect2(to_px(Vector2(fp.position)), Vector2(fp.size) * s)
	var f := style.face_font
	# 내부 층은 건물 둘레 밖에, 외부 판은 건물 안쪽 가장자리에 (밖에는 진입구·차량이 있다)
	var gap := maxf(s * 1.4, 16.0) if level >= 0 else -(f * 0.9 + 4.0)
	var anchors := {
		"south": Vector2(rect.get_center().x, rect.end.y + gap + f * 0.4),
		"north": Vector2(rect.get_center().x, rect.position.y - gap + f * 0.4),
		"west": Vector2(rect.position.x - gap - signf(gap) * f * 0.6, rect.get_center().y + f * 0.4),
		"east": Vector2(rect.end.x + gap + signf(gap) * f * 0.6, rect.get_center().y + f * 0.4),
	}
	for face: String in sim.building.faces:
		var side: String = sim.building.faces[face]
		if anchors.has(side):
			var p: Vector2 = anchors[side]
			draw_string(font, p - Vector2(30, 0), "%s면" % face, HORIZONTAL_ALIGNMENT_CENTER, 60, f, style.color("ink"))


func _draw_inside(lv: int, font: Font) -> void:
	var s := _scale()
	var kb := sim.knowledge
	var r := style.symbol_px
	var lf := style.label_font
	# 연기: 물결선
	for idx: int in kb.smoky:
		var c := sim.fire.comps[idx]
		if c.level == lv:
			BoardSymbols.smoke(self, _room_px(c), style.color("smoke", _alpha(kb.smoky[idx])))
	# 화점: 빨간 빗금 + 불꽃
	for idx in fire_rooms(lv):
		var c := sim.fire.comps[idx]
		var a := _alpha(kb.fires[idx])
		var rect := _room_px(c)
		BoardSymbols.hatch(self, rect, style.hatch_step_px, style.color("fire", 0.55 * a), 1.5)
		draw_rect(rect, style.color("fire", a), false, 2.0)
		BoardSymbols.flame(self, rect.get_center(), r * 1.3, style.color("fire", a))
		draw_string(font, rect.get_center() + Vector2(-40, r * 1.3 + lf + 3.0), "화점", HORIZONTAL_ALIGNMENT_CENTER, 80, lf + 1, style.color("fire", a))
	# 검색: 지시 = 사선 한 줄, 완료 = ✕
	for idx in search_ordered_rooms(lv):
		BoardSymbols.slash(self, _room_px(sim.fire.comps[idx]), style.color("search", 0.8), 2.0)
	for idx: int in kb.searched:
		var c := sim.fire.comps[idx]
		if c.level == lv:
			BoardSymbols.cross(self, _room_px(c), style.color("search", 0.8), 2.0)
	_draw_hoses(lv)
	# 위험 징후: 방 오른쪽 위에 (가운데는 불꽃 자리), 같은 방에 여럿이면 아래로 이어서
	var stacked: Dictionary = {}
	for hz in kb.hazards:
		if int(hz.level) != lv or hz.pos.x < 0:
			continue
		var p := to_px(hz.pos)
		var room_idx := int(hz.get("room", -1))
		if room_idx >= 0:
			var rect := _room_px(sim.fire.comps[room_idx])
			var k := int(stacked.get(room_idx, 0))
			stacked[room_idx] = k + 1
			p = rect.get_center() + Vector2(rect.size.x * 0.27, -rect.size.y * 0.27 + k * (r * 2.0 + lf + 6.0))
		var a := _alpha(hz.tick)
		BoardSymbols.hazard(self, p, r, style.color("hazard", a), style.color("ink", a))
		draw_string(font, p + Vector2(-60, r + lf + 2.0), str(hz.kind), HORIZONTAL_ALIGNMENT_CENTER, 120, lf, style.color("ink", a))
	_draw_victims(lv, font, false)
	_draw_crews(crew_magnets(lv), font)


func _room_px(c: Compartment) -> Rect2:
	return Rect2(to_px(Vector2(c.rect.position)), Vector2(c.rect.size) * _scale())


## 수관 (우리 장비): 방수 중 = 파란 실선, 연장만 = 파란 점선
func _draw_hoses(lv: int) -> void:
	var col := style.color("hose")
	for h in sim.water.hoses:
		var pts := PackedVector2Array()
		for p in h.points:
			if p.z == lv:
				pts.append(to_px(Vector2(p.x, p.y) + Vector2(0.5, 0.5)))
		if pts.size() < 2:
			continue
		if h.flowing:
			draw_polyline(pts, col, style.hose_px)
		else:
			BoardSymbols.dashed_polyline(self, pts, col, style.hose_px)


## 구조대상자 (보고된 것만): 같은 방은 한 표시 + 인원수. 구조 완료는 회색 사람 + 초록 체크
## outdoor_only = 외부 판 (건물 밖에 있는 것만)
func _draw_victims(lv: int, font: Font, outdoor_only: bool) -> void:
	var kb := sim.knowledge
	var groups: Dictionary = {}
	for vid: int in kb.victims:
		var v: Dictionary = kb.victims[vid]
		if int(v.level) != lv:
			continue
		var pos: Vector2 = v.pos
		var outdoors := sim.building.cell(lv, floori(pos.x), floori(pos.y)) in BuildingData.OUTDOOR
		if outdoor_only != outdoors:
			continue
		var room := sim.fire.compartment_at(lv, floori(pos.x), floori(pos.y))
		var key := "%s:%d" % [v.state, room.index if room else -1000 - vid]
		if not groups.has(key):
			groups[key] = {"pos": pos, "n": 0, "tick": int(v.tick), "state": str(v.state)}
		groups[key].n += 1
		groups[key].tick = maxi(int(groups[key].tick), int(v.tick))
	var r := style.symbol_px
	var lf := style.label_font
	for key: String in groups:
		var g: Dictionary = groups[key]
		var p := to_px(g.pos)
		var a := _alpha(int(g.tick))
		if g.state == "구조":
			BoardSymbols.person(self, p, r, style.color("unseen", a), style.color("ink_soft", a))
			BoardSymbols.check(self, p + Vector2(r * 0.5, 0.0), r, style.color("rescued", a))
			draw_string(font, p + Vector2(r * 1.6, lf * 0.4), "구조 %d명" % int(g.n), HORIZONTAL_ALIGNMENT_LEFT, -1, lf, style.color("rescued", a))
		else:
			BoardSymbols.person(self, p, r, style.color("victim", a), style.color("ink", a))
			draw_string(font, p + Vector2(r * 1.1, lf * 0.4), "%d명" % int(g.n), HORIZONTAL_ALIGNMENT_LEFT, -1, lf + 1, style.color("ink", a))


## 조 자석 자리 (조 id → 판 위 네모). 건물 안은 마지막 보고 위치, 밖은 지금 자리.
## 서로 겹치면 아래로 비키고, 외부 판에서는 차량 자석도 피한다
func crew_magnets(lv: int) -> Dictionary:
	var out: Dictionary = {}
	var placed: Array[Rect2] = []
	if level < 0:
		var vehicles := vehicle_magnets()
		for id: int in vehicles:
			placed.append(vehicles[id])
	var font := _font()
	for c in sim.units.crews:
		var at := crew_spot(c.id)
		if at.z != lv or at.x < -999:
			continue
		var sz := BoardSymbols.magnet_size(crew_label(c), font, style)
		var rect := Rect2(to_px(Vector2(at.x, at.y)) - sz * 0.5, sz)
		for i in 8:
			if not placed.any(func(o: Rect2) -> bool: return o.intersects(rect)):
				break
			rect.position.y += sz.y + 3.0
		placed.append(rect)
		out[c.id] = rect
	return out


## 조 자석: 헬멧 색 칩 + "진압1-1". 건물 안이면 보고 시각, 60초 넘으면 흐리게. RIT는 빨간 겹테두리
func _draw_crews(magnets: Dictionary, font: Font) -> void:
	for id: int in magnets:
		var c := sim.units.get_crew(id)
		var rect: Rect2 = magnets[id]
		var info: Dictionary = sim.knowledge.crews.get(id, {})
		var inside := sim.command.interior.crew_inside(id)
		var a := _alpha(int(info.get("tick", sim.clock.tick))) if inside else 1.0
		var ring := style.color("rit") if sim.command.safety.role_of(id) == SafetySystem.Role.RIT else Color(0, 0, 0, 0)
		BoardSymbols.magnet(self, rect, crew_label(c), SpriteArt.helmet_color(sim.units.squads[c.squad_id].type), font, style, a, false, ring)
		if inside:
			draw_string(font, Vector2(rect.position.x, rect.end.y + style.label_font), age_text(int(info.get("tick", -1))),
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, style.label_font - 1, style.color("ink" if a < 1.0 else "ink_soft"))


## 보고한 지 얼마나 됐나: "40초 전" · "3분 전"
func age_text(since_tick: int) -> String:
	var age := KnowledgeBoard.age_s(since_tick, sim.clock.tick)
	if age < 0.0:
		return ""
	return "%d초 전" % roundi(age) if age < 60.0 else "%d분 전" % floori(age / 60.0)


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


# --- 외부 배치도 ---

## 땅: 도로·보도는 옅은 회색, 건물은 회색 덩어리 + 먹 외곽선
func _draw_site(lv: int) -> void:
	var b := sim.building
	var s := _scale()
	var cell := Vector2(s, s) + Vector2(0.5, 0.5)
	var ink := style.color("ink")
	for y in b.height:
		for x in b.width:
			var t := b.cell(lv, x, y)
			var p := to_px(Vector2(x, y))
			if t == BuildingData.Cell.ROAD:
				draw_rect(Rect2(p, cell), style.color("road"))
			elif t == BuildingData.Cell.SIDEWALK:
				draw_rect(Rect2(p, cell), style.color("sidewalk"))
			elif not t in BuildingData.OUTDOOR:
				draw_rect(Rect2(p, cell), style.color("building"))
				var c := p + Vector2(s, s) * 0.5
				for d in DIRS:
					var n := Vector2i(x, y) + d
					if n.x < 0 or n.y < 0 or n.x >= b.width or n.y >= b.height or b.cell(lv, n.x, n.y) in BuildingData.OUTDOOR:
						var mid := c + Vector2(d) * s * 0.5
						var side := Vector2(-d.y, d.x) * s * 0.5
						draw_line(mid - side, mid + side, ink, 2.0)


## 차량 자석 자리 (차량 id → 네모)
func vehicle_magnets() -> Dictionary:
	var out: Dictionary = {}
	var font := _font()
	for v in sim.units.vehicles:
		if v.away:
			continue
		var sz := BoardSymbols.magnet_size(vehicle_text(v), font, style)
		out[v.id] = Rect2(to_px(v.pos) - sz * 0.5, sz)
	return out


## 차량 자석 글: "진압1 펌프"
func vehicle_text(v: Vehicle) -> String:
	return "%s %s" % [sim.units.squads[v.squad_id].name, style.vehicle_label(v.type)]


func _draw_outside(lv: int, font: Font) -> void:
	var r := style.symbol_px
	var lf := style.label_font
	_draw_zones(font)
	# 급수: 소화전·물탱크차에서 펌프차로 파란 선
	var water := style.color("hydrant")
	for v in sim.units.vehicles:
		if v.away:
			continue
		if v.hydrant >= 0:
			draw_line(to_px(v.pos), to_px(Vector2(sim.building.hydrants[v.hydrant]) + Vector2(0.5, 0.5)), water, 2.0)
		if v.supply_to >= 0:
			draw_line(to_px(v.pos), to_px(sim.units.get_vehicle(v.supply_to).pos), water, 2.0)
	_draw_hoses(lv)
	for h in sim.building.hydrants:
		BoardSymbols.hydrant(self, to_px(Vector2(h) + Vector2(0.5, 0.5)), r * 0.8, water, style.color("board"))
	# 진입구: 건물 쪽을 가리키는 초록 화살표 + 이름
	for e in sim.entries.list:
		var door := Vector2(e.door) + Vector2(0.5, 0.5)
		var out_dir: Vector2 = e.outward.normalized() if e.outward.length() > 0.01 else Vector2(0, 1)
		var tip := to_px(door) + out_dir * 4.0
		BoardSymbols.arrow(self, tip, -out_dir, r, style.color("entry"))
		var tail := tip + out_dir * (r * 2.3 + 4.0)
		var name_w := font.get_string_size(e.name, HORIZONTAL_ALIGNMENT_LEFT, -1, lf).x
		var at := tail + Vector2(-name_w * 0.5, lf if out_dir.y > 0.0 else -3.0)
		if out_dir.x > 0.5:
			at = tail + Vector2(0.0, lf * 0.4)
		elif out_dir.x < -0.5:
			at = tail + Vector2(-name_w, lf * 0.4)
		draw_string(font, at, e.name, HORIZONTAL_ALIGNMENT_LEFT, -1, lf, style.color("entry"))
	var vehicles := vehicle_magnets()
	for id: int in vehicles:
		var v := sim.units.get_vehicle(id)
		BoardSymbols.magnet(self, vehicles[id], vehicle_text(v), sim.units.squads[v.squad_id].color, font, style, 1.0, true)
	_draw_victims(lv, font, true)
	# 지휘관 자석 (파란 헬멧)
	var cmd_text := "지휘관"
	var sz := BoardSymbols.magnet_size(cmd_text, font, style)
	BoardSymbols.magnet(self, Rect2(to_px(sim.command.commander.pos) - sz * 0.5, sz), cmd_text, SpriteArt.helmet_color("지휘"), font, style)
	_draw_crews(crew_magnets(lv), font)


## 구역 (흰 판용): 안전구역 = 초록 점선 테두리, 진입통제선 = 주황 점선, 집결지·분류소 = 십자, 지휘소·직전대기 = 깃발
func _draw_zones(font: Font) -> void:
	var z := sim.zones
	if z == null:
		return
	var lf := style.label_font
	var r := style.symbol_px
	var ink := style.color("ink")
	var safe := style.color("safe_zone")
	if not z.has_safe() and z.guide_m > 0.0:
		var g := z.guide_rect()
		var rect := Rect2(to_px(g.position), g.size * _scale())
		BoardSymbols.dashed_rect(self, rect, style.color("safe_zone", 0.5), 1.5)
		var guide := "안전구역은 이 선 밖 (%s %dm)" % [z.guide_reason, roundi(z.guide_m)]
		var guide_w := font.get_string_size(guide, HORIZONTAL_ALIGNMENT_LEFT, -1, lf - 1).x
		draw_string(font, Vector2(rect.end.x - guide_w, rect.position.y - 4.0), guide, HORIZONTAL_ALIGNMENT_LEFT, -1, lf - 1, safe)
	if z.has_safe():
		var rect := Rect2(to_px(Vector2(z.safe.position)), Vector2(z.safe.size) * _scale())
		draw_rect(rect, style.color("safe_zone", 0.1))
		BoardSymbols.dashed_rect(self, rect, safe)
		draw_string(font, rect.position + Vector2(5, lf + 4.0), "안전구역", HORIZONTAL_ALIGNMENT_LEFT, -1, lf, safe)
	if z.line.size() == 2:
		var line_col := style.color("control_line")
		draw_dashed_line(to_px(z.line[0]), to_px(z.line[1]), line_col, 3.0, 10.0)
		draw_string(font, to_px(z.line[0]) + Vector2(-50, -6), "진입통제선", HORIZONTAL_ALIGNMENT_CENTER, 100, lf, line_col)
	if z.casualty.x >= 0 and z.triage.x < 0:
		_mark(font, to_px(Vector2(z.casualty) + Vector2(0.5, 0.5)), style.color("casualty"), "환자 집결지")
	if z.triage.x >= 0:
		_mark(font, to_px(Vector2(z.triage) + Vector2(0.5, 0.5)), style.color("triage"), "분류소")
	var cp := z.post
	if cp:
		if cp.has_post():
			var at := to_px(Vector2(cp.post) + Vector2(0.5, 0.5))
			BoardSymbols.flag(self, at, r * 2.2, style.color("post"), ink)
			draw_string(font, at + Vector2(-70, -r * 2.2 - 4.0), "지휘소 · %s" % CommandPost.MODE_NAMES[cp.mode], HORIZONTAL_ALIGNMENT_CENTER, 140, lf, style.color("post"))
		if cp.forward.x >= 0:
			var at := to_px(Vector2(cp.forward) + Vector2(0.5, 0.5))
			BoardSymbols.flag(self, at, r * 2.2, style.color("triage"), ink)
			draw_string(font, at + Vector2(-70, -r * 2.2 - 4.0), "직전대기", HORIZONTAL_ALIGNMENT_CENTER, 140, lf, style.color("triage"))
		for j: Dictionary in cp.jobs:
			var at := to_px(Vector2(j.target) + Vector2(0.5, 0.5))
			draw_arc(at, r, 0.0, TAU, 20, safe, 2.0)
			draw_string(font, at + Vector2(-70, -r - 5.0), "%s 설치%s" % [ZoneSystem.KIND_NAMES.get(j.kind, j.kind), " 중" if int(j.start) >= 0 else " 대기"],
				HORIZONTAL_ALIGNMENT_CENTER, 140, lf - 1, safe)
	elif not z.triage_setup.is_empty():
		var at := to_px(Vector2(z.triage_setup.cell) + Vector2(0.5, 0.5))
		var prog := z.triage_progress(sim.clock.tick)
		draw_arc(at, r, 0.0, TAU, 20, style.color("triage", 0.5), 2.0)
		if prog >= 0.0:
			draw_arc(at, r, -PI / 2.0, -PI / 2.0 + TAU * prog, 20, style.color("triage"), 3.0)
		draw_string(font, at + Vector2(-60, -r - 5.0), "분류소 설치 중", HORIZONTAL_ALIGNMENT_CENTER, 120, lf, style.color("triage"))


## 십자 표시 + 이름
func _mark(font: Font, p: Vector2, col: Color, label: String) -> void:
	var r := style.symbol_px
	BoardSymbols.cross_mark(self, p, r, col, style.color("ink"), style.color("board"))
	draw_string(font, p + Vector2(-60, -r - 4.0), label, HORIZONTAL_ALIGNMENT_CENTER, 120, style.label_font, col)


# --- 범례 ---

## 판 아래 두 줄: 기호 + 설명
func _draw_legend(font: Font) -> void:
	var row := style.legend_row_px
	var top := size.y - legend_height()
	draw_line(Vector2(8, top), Vector2(size.x - 8, top), style.color("ink_soft", 0.6), 1.0)
	var fs := style.label_font
	var x := 10.0
	var y := top + 4.0 + row * 0.5
	for id in legend_items():
		var text: String = LEGEND[id]
		var need := 28.0 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0
		if x + need > size.x - 6.0 and x > 10.0:
			x = 10.0
			y += row
		_legend_symbol(id, Vector2(x + 11.0, y), font)
		draw_string(font, Vector2(x + 28.0, y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, style.color("ink"))
		x += need


## 범례 속 작은 기호 (p = 가운데)
func _legend_symbol(id: String, p: Vector2, font: Font) -> void:
	var r := 7.0
	var box := Rect2(p - Vector2(9, 7), Vector2(18, 14))
	var ink := style.color("ink")
	match id:
		"fire":
			BoardSymbols.flame(self, p + Vector2(0, 1), r, style.color("fire"))
		"smoke":
			BoardSymbols.wave(self, p - Vector2(9, 0), 18.0, style.color("smoke"))
		"victim":
			BoardSymbols.person(self, p, r, style.color("victim"), ink)
		"rescued":
			BoardSymbols.check(self, p, r, style.color("rescued"))
		"search_ordered":
			draw_rect(box, style.color("ink_soft"), false, 1.0)
			BoardSymbols.slash(self, box, style.color("search"), 2.0)
		"searched":
			draw_rect(box, style.color("ink_soft"), false, 1.0)
			BoardSymbols.cross(self, box, style.color("search"), 2.0)
		"hazard":
			BoardSymbols.hazard(self, p + Vector2(0, 1), r, style.color("hazard"), ink)
		"hose_flow":
			draw_line(p - Vector2(10, 0), p + Vector2(10, 0), style.color("hose"), style.hose_px)
		"hose_laid":
			draw_dashed_line(p - Vector2(10, 0), p + Vector2(10, 0), style.color("hose"), style.hose_px, 5.0)
		"crew":
			draw_rect(Rect2(p - Vector2(10, 5), Vector2(20, 10)), Color.WHITE)
			draw_rect(Rect2(p - Vector2(10, 5), Vector2(20, 10)), ink, false, 1.5)
			draw_circle(p - Vector2(5, 0), 3.0, SpriteArt.helmet_color("진압대"))
		"vehicle":
			draw_rect(Rect2(p - Vector2(10, 6), Vector2(20, 12)), Color.WHITE)
			draw_rect(Rect2(p - Vector2(10, 6), Vector2(20, 12)), ink, false, 1.5)
			draw_rect(Rect2(p - Vector2(7, 3), Vector2(6, 6)), style.color("fire"))
		"unseen":
			draw_rect(box, style.color("unseen"))
			draw_rect(box, style.color("ink_soft"), false, 1.0)
		"estimate":
			draw_dashed_line(p - Vector2(10, 0), p + Vector2(10, 0), style.color("estimate"), 3.0, 3.0)
		"hydrant":
			BoardSymbols.hydrant(self, p, r, style.color("hydrant"), style.color("board"))
		"supply":
			draw_line(p - Vector2(10, 0), p + Vector2(10, 0), style.color("hydrant"), 2.0)
		"entry":
			BoardSymbols.arrow(self, p + Vector2(9, 0), Vector2(1, 0), r, style.color("entry"))
		"post":
			BoardSymbols.flag(self, p + Vector2(-4, 8), 15.0, style.color("post"), ink)
		"safe_zone":
			BoardSymbols.dashed_rect(self, box, style.color("safe_zone"), 2.0, 4.0)
		"control_line":
			draw_dashed_line(p - Vector2(10, 0), p + Vector2(10, 0), style.color("control_line"), 3.0, 5.0)
		"casualty":
			BoardSymbols.cross_mark(self, p, r, style.color("casualty"), ink, style.color("board"))


# --- 끌어다 놓기 ---

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


## 상황판의 조 자석 (누른 자리가 자석 위, 살짝 넉넉하게)
func crew_at(p: Vector2) -> int:
	var magnets := crew_magnets(draw_level())
	for id: int in magnets:
		var rect: Rect2 = magnets[id]
		if rect.grow(3.0).has_point(p):
			return id
	return -1
