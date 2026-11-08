class_name UnitsView
extends Node2D
## 대원을 원형 아이콘으로 그린다. 색 = 출동대, 숫자 = 조 번호.
## 다른 층의 대원은 흐리게 표시한다. 선택된 조는 고리와 남은 경로를 표시한다.

const RADIUS_CELLS := 0.42
const FONT_SIZE := 12

var sim: SimWorld
var selection: SelectionController
var level := 1


func setup(p_sim: SimWorld, p_selection: SelectionController) -> void:
	sim = p_sim
	selection = p_selection


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var alpha := sim.clock.alpha()
	_draw_doors()
	_draw_hoses()
	if level == sim.building.levels()[0]:
		for hydrant in sim.building.hydrants:
			var c := PlanStyle.to_px(Vector2(hydrant) + Vector2(0.5, 0.5))
			draw_circle(c, 7.0, PlanStyle.HYDRANT_COLOR)
			draw_arc(c, 7.0, 0.0, TAU, 16, Color.WHITE, 1.5)
			draw_string(PlanStyle.font(), c + Vector2(-30, -12), "소화전", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, PlanStyle.HYDRANT_COLOR.lightened(0.4))
		if sim.building.has_standpipe():
			var f := PlanStyle.to_px(Vector2(sim.building.fdc) + Vector2(0.5, 0.5))
			draw_rect(Rect2(f - Vector2(6, 6), Vector2(12, 12)), PlanStyle.STANDPIPE_COLOR)
			draw_string(PlanStyle.font(), f + Vector2(-60, -12), "송수구%s" % (" (연결)" if sim.water.fdc_vehicle >= 0 else ""), HORIZONTAL_ALIGNMENT_CENTER, 120, 12, PlanStyle.STANDPIPE_COLOR.lightened(0.4))
		if sim.gas.known(sim.command.survey):
			var g := PlanStyle.to_px(Vector2(sim.gas.valve) + Vector2(0.5, 0.5))
			var gc := PlanStyle.GAS_COLOR if sim.gas.open else PlanStyle.GAS_COLOR.darkened(0.5)
			draw_rect(Rect2(g - Vector2(6, 6), Vector2(12, 12)), gc)
			draw_string(PlanStyle.font(), g + Vector2(-60, -12), "%s%s" % [sim.gas.valve_text, "" if sim.gas.open else " (차단)"], HORIZONTAL_ALIGNMENT_CENTER, 120, 12, gc.lightened(0.4))
		for w in sim.command.survey.witnesses:
			if w.present(sim.clock.tick):
				var wc := PlanStyle.to_px(w.pos)
				var wr := RADIUS_CELLS * PlanStyle.CELL_PX
				draw_circle(wc, wr, PlanStyle.WITNESS_BODY)
				draw_arc(wc, wr, 0.0, TAU, 24, PlanStyle.WITNESS_HEAD, 2.0)
				draw_string(PlanStyle.font(), wc + Vector2(-60, -wr - 4.0), "관계인 · %s" % w.name, HORIZONTAL_ALIGNMENT_CENTER, 120, FONT_SIZE, PlanStyle.WITNESS_HEAD)
		var rects := sim.command.resources.staging_rects()
		for r in rects:
			var px := Rect2(PlanStyle.to_px(r.position), PlanStyle.to_px(r.end) - PlanStyle.to_px(r.position))
			var corners := [px.position, Vector2(px.end.x, px.position.y), px.end, Vector2(px.position.x, px.end.y)]
			for k in 4:
				draw_dashed_line(corners[k], corners[(k + 1) % 4], PlanStyle.STAGING_COLOR, 2.0, 8.0)
		if not rects.is_empty():
			draw_string(PlanStyle.font(), PlanStyle.to_px(Vector2(rects[0].position.x + 0.5, rects[0].end.y + 0.8)),
				"대기1단계 장소 (%s)" % sim.command.resources.staging_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PlanStyle.STAGING_COLOR.lightened(0.3))
		for v in sim.units.vehicles:
			if not v.away:
				_draw_vehicle(v, alpha)
		for line in supply_lines(sim):
			draw_line(PlanStyle.to_px(line[0]), PlanStyle.to_px(line[1]), PlanStyle.SUPPLY_LINE, 4.0)
	for o in sim.building.outlets:
		if o.z == level:
			var oc := PlanStyle.to_px(Vector2(o.x, o.y) + Vector2(0.5, 0.5))
			draw_rect(Rect2(oc - Vector2(5, 5), Vector2(10, 10)), PlanStyle.STANDPIPE_COLOR)
			draw_string(PlanStyle.font(), oc + Vector2(-40, -10), "방수구", HORIZONTAL_ALIGNMENT_CENTER, 80, 11, PlanStyle.STANDPIPE_COLOR.lightened(0.4))
	for o in sim.command.survey.lit_windows():
		if o.level == level:
			for c in o.cells:
				draw_rect(Rect2(PlanStyle.to_px(Vector2(c)), Vector2.ONE * PlanStyle.CELL_PX), PlanStyle.LIT_WINDOW)
	for e in sim.rekindle.spotted_cells():
		if e.z == level:
			var ep := PlanStyle.to_px(Vector2(e.x, e.y) + Vector2(0.5, 0.5))
			draw_circle(ep, 4.0, PlanStyle.EMBER)
			draw_arc(ep, 7.0, 0.0, TAU, 16, PlanStyle.EMBER, 1.5)
	for room in sim.building.rooms(level):
		if sim.command.survey.reported_rooms.has(room.id):
			var rr: Rect2i = room.rect
			var rc := PlanStyle.to_px(Vector2(rr.position) + Vector2(rr.size) * 0.5)
			draw_string(PlanStyle.font(), rc + Vector2(-90, 22), "[제보: 구조대상자 가능]", HORIZONTAL_ALIGNMENT_CENTER, 180, FONT_SIZE, PlanStyle.REPORTED_ROOM)
	for crew_id in selection.selected:
		_draw_path(sim.units.get_crew(crew_id).leader, alpha)
	if selection.commander_selected:
		_draw_path(sim.command.commander, alpha)
	# 다른 층 대원을 먼저 그려 현재 층 대원이 위에 오게 한다
	for pass_current in [false, true]:
		for ff in sim.units.firefighters:
			if (ff.level == level) == pass_current and not ff.aboard:
				_draw_unit(ff, alpha)
	_draw_commander(alpha)
	_draw_victims()
	_draw_room_marks()
	_draw_sprays(alpha)
	_draw_smoke_plumes()
	_draw_blasts()


## 발견한 요구조자: 상태별 색 마름모 + 이름표
func _draw_victims() -> void:
	for p in sim.ems.patients:
		var pv := sim.rescue.victims[p.victim_id]
		if level != sim.building.levels()[0] or not sim.ems.on_scene(p) or pv.carried_by >= 0:
			continue
		var pc := PlanStyle.to_px(pv.pos)
		var tag: Color = EmsSystem.TRIAGE_COLORS[p.triage]
		draw_rect(Rect2(pc - Vector2(7, 7), Vector2(14, 14)), tag)
		draw_rect(Rect2(pc - Vector2(7, 7), Vector2(14, 14)), Color.WHITE, false, 1.5)
		draw_string(PlanStyle.font(), pc + Vector2(-80, -12), "%s · %s · %s" % [pv.label(), sim.ems.triage_name(p), EmsSystem.STAGE_NAMES[p.stage]], HORIZONTAL_ALIGNMENT_CENTER, 160, 12, tag.lightened(0.3))
	for v in sim.rescue.victims:
		if not v.discovered or v.level != level or v.state == Victim.State.RESCUED:
			continue
		var c := PlanStyle.to_px(v.pos)
		var r := 8.0 if v.carried_by < 0 else 5.0
		var color: Color = PlanStyle.VICTIM_COLORS[v.state]
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)
		if v.carried_by < 0:
			draw_string(PlanStyle.font(), c + Vector2(-50, -12), "%s · %s" % [v.label(), v.state_name()], HORIZONTAL_ALIGNMENT_CENTER, 100, 12, color.lightened(0.4))


## 방별 표시: 검색 완료, 롤오버 징후(보이는 방만)
func _draw_room_marks() -> void:
	var px := PlanStyle.CELL_PX
	for c in sim.fire.comps:
		if c.level != level:
			continue
		var rect := Rect2(Vector2(c.rect.position) * px, Vector2(c.rect.size) * px)
		if c.searched_tick >= 0:
			draw_string(PlanStyle.font(), Vector2(rect.position.x, rect.get_center().y + 22), "[검색 완료]", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, PlanStyle.SEARCHED)
		if c.rollover and sim.perception.room_visible(c):
			var t := Time.get_ticks_msec() / 1000.0
			draw_rect(rect.grow(-2.0), Color(1.0, 0.45, 0.1, 0.6 + 0.3 * sin(t * 8.0)), false, 3.0)


func _draw_blasts() -> void:
	for blast in sim.hazards.blasts:
		if int(blast[1]) != level:
			continue
		var age := float(sim.clock.tick - int(blast[2])) / HazardSystem.BLAST_SHOW_TICKS
		var at := PlanStyle.to_px(blast[0])
		draw_circle(at, 12.0 + age * 60.0, Color(1.0, 0.5, 0.1, 0.6 * (1.0 - age)))


## 문 상태: 열림(바닥색 + 문틀 선) / 닫힘(문 색) / 잠김·파괴 표시 / 작업 진행 막대
func _draw_doors() -> void:
	var px := PlanStyle.CELL_PX
	for o in sim.fire.openings:
		if o.kind != Opening.Kind.DOOR or o.level != level:
			continue
		for c in o.cells:
			var rect := Rect2(Vector2(c) * px, Vector2(px, px))
			if o.is_open:
				draw_rect(rect, PlanStyle.CELL_COLORS[BuildingData.Cell.FLOOR] if not o.forced else Color("5d4037"))
				draw_rect(rect, PlanStyle.CELL_COLORS[BuildingData.Cell.DOOR], false, 2.0)
		var top := PlanStyle.to_px(Vector2(o.cells[0]) + Vector2(0.5, -0.3))
		if o.locked:
			draw_string(PlanStyle.font(), top + Vector2(-30, 0), "잠김", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color("ffcc80"))
		elif o.forced:
			draw_string(PlanStyle.font(), top + Vector2(-30, 0), "파괴", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color("bcaaa4"))
		var task := sim.doors.task_of(o)
		if task:
			var r := Rect2(top.x - 20.0, top.y + 4.0, 40.0, 5.0)
			draw_rect(r, PlanStyle.TANK_BG)
			draw_rect(Rect2(r.position, Vector2(r.size.x * task.progress / task.required, r.size.y)), Color("ffb74d"))
			if task.waiting_people:
				draw_string(PlanStyle.font(), top + Vector2(-40, 22), "인원 부족", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color("ff8a80"))


func _draw_smoke_plumes() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for line in IsoView.smoke_outlets(sim, level):
		var at := PlanStyle.to_px(line[0])
		var strength: float = line[1]
		for k in 4:
			var f := fmod(k / 4.0 + t * 0.35, 1.0)
			draw_circle(at + Vector2(sin(t + k) * 5.0, -f * 30.0), (6.0 + f * 12.0) * (0.6 + 0.4 * strength), Color(PlanStyle.SMOKE_PLUME, PlanStyle.SMOKE_PLUME.a * (1.0 - f) * strength))


func _draw_hoses() -> void:
	for h in sim.water.hoses:
		var pts := PackedVector2Array()
		for p in h.points:
			if p.z == level:
				pts.append(PlanStyle.to_px(Vector2(p.x + 0.5, p.y + 0.5)))
			else:
				if pts.size() >= 2:
					draw_polyline(pts, PlanStyle.HOSE_COLOR, 2.5)
				pts.clear()
		if pts.size() >= 2:
			draw_polyline(pts, PlanStyle.HOSE_COLOR, 2.5)


func _draw_vehicle(v: Vehicle, alpha: float) -> void:
	var fp := v.footprint(v.prev_pos.lerp(v.pos, alpha))
	var poly := PackedVector2Array()
	for p in fp:
		poly.append(PlanStyle.to_px(p))
	draw_colored_polygon(poly, v.color)
	# 앞쪽 1/4은 운전석
	var cab := PackedVector2Array([poly[0].lerp(poly[1], 0.75), poly[1], poly[2], poly[3].lerp(poly[2], 0.75)])
	draw_colored_polygon(cab, v.color.darkened(0.35))
	var outline := poly.duplicate()
	outline.append(poly[0])
	var selected := v.id in selection.selected_vehicles
	draw_polyline(outline, PlanStyle.SELECTION if selected else PlanStyle.UNIT_OUTLINE, 3.0 if selected else 1.5)
	var center := PlanStyle.to_px(v.prev_pos.lerp(v.pos, alpha))
	var text := v.short_name + (" · 후진" if v.reversing else "")
	draw_string(PlanStyle.font(), center + Vector2(-50, 5), text, HORIZONTAL_ALIGNMENT_CENTER, 100, 14, Color.WHITE)
	var top := poly[0].y
	for p in poly:
		top = minf(top, p.y)
	_draw_tank_gauge(Vector2(center.x, top - 10.0), v)


func _draw_tank_gauge(at: Vector2, v: Vehicle) -> void:
	var rect := Rect2(at.x - 30.0, at.y - 4.0, 60.0, 7.0)
	draw_rect(rect, PlanStyle.TANK_BG)
	var f := v.tank_l / v.tank_capacity if v.tank_capacity > 0.0 else 0.0
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * f, rect.size.y)), PlanStyle.TANK_FILL)


func _draw_sprays(alpha: float) -> void:
	for h in sim.water.hoses:
		if not h.flowing or h.flow_fraction <= 0.0:
			continue
		var leader := sim.units.get_crew(h.crew_id).leader
		if leader.level != level:
			continue
		var from := PlanStyle.to_px(display_pos(leader, alpha))
		var to := PlanStyle.to_px(h.impact)
		if h.pattern == HoseLine.Pattern.STRAIGHT:
			draw_line(from, to, PlanStyle.WATER_COLOR, 2.5)
			draw_circle(to, 5.0, PlanStyle.WATER_COLOR)
		else:
			var r := sim.water.radius_cells(h.pattern) * PlanStyle.CELL_PX
			var side := (to - from).orthogonal().normalized() * r
			draw_colored_polygon(PackedVector2Array([from, to + side, to - side]), PlanStyle.FOG_COLOR)
			draw_arc(to, r, 0.0, TAU, 24, PlanStyle.WATER_COLOR, 1.5)


func _draw_unit(ff: Firefighter, alpha: float) -> void:
	var on_floor := ff.level == level
	var squad := sim.units.squads[ff.squad_id]
	var crew := sim.units.get_crew(ff.crew_id)
	var center := PlanStyle.to_px(display_pos(ff, alpha))
	var r := RADIUS_CELLS * PlanStyle.CELL_PX * (1.0 if on_floor else 0.75)
	var a := 1.0 if on_floor else PlanStyle.OTHER_FLOOR_ALPHA
	if on_floor and crew.id in selection.selected:
		draw_arc(center, r + 4.0, 0.0, TAU, 32, PlanStyle.SELECTION, 2.5)
	# 열 스트레스가 쌓이면 붉게
	var body := squad.color.lerp(Color(1.0, 0.25, 0.1), clampf(ff.heat_stress, 0.0, 1.0) * 0.7)
	draw_circle(center, r, Color(body, a))
	var outline_width := 2.5 if ff == crew.leader else 1.2
	draw_arc(center, r, 0.0, TAU, 32, Color(PlanStyle.UNIT_OUTLINE, a), outline_width)
	if not on_floor:
		return
	if ff.incapacitated:
		var d := r * 0.7
		draw_line(center - Vector2(d, d), center + Vector2(d, d), Color("ff5252"), 3.0)
		draw_line(center + Vector2(-d, d), center + Vector2(d, -d), Color("ff5252"), 3.0)
		return
	var font := PlanStyle.font()
	var baseline := center + Vector2(-r, FONT_SIZE * 0.35)
	draw_string(font, baseline, str(crew.number), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, FONT_SIZE, PlanStyle.UNIT_TEXT)
	# 낮은 자세: 아래쪽 반원 표시 / 공기 잔량 막대
	if ff.crouched:
		draw_arc(center, r + 2.0, 0.2, PI - 0.2, 12, Color.WHITE, 1.5)
	var bar := Rect2(center.x - r, center.y - r - 6.0, r * 2.0, 3.0)
	draw_rect(bar, PlanStyle.TANK_BG)
	var f := ff.air_ratio()
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), PlanStyle.AIR_LOW if f < 0.18 else PlanStyle.AIR_OK)


## 현장지휘관: 흰 사각형·빨간 테두리, "지휘" 표시
func _draw_commander(alpha: float) -> void:
	var c := sim.command.commander
	if c.level != level:
		return
	var center := PlanStyle.to_px(display_pos(c, alpha))
	var r := RADIUS_CELLS * PlanStyle.CELL_PX
	if selection.commander_selected:
		draw_arc(center, r + 5.0, 0.0, TAU, 32, PlanStyle.SELECTION, 2.5)
	var box := Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0)
	draw_rect(box, PlanStyle.COMMANDER_BODY)
	draw_rect(box, PlanStyle.COMMANDER_HELMET, false, 2.5)
	draw_string(PlanStyle.font(), center + Vector2(-20, -r - 4.0), "지휘", HORIZONTAL_ALIGNMENT_CENTER, 40, FONT_SIZE, Color.WHITE)


func _draw_path(ff: Firefighter, alpha: float) -> void:
	if not ff.is_moving():
		return
	var points := PackedVector2Array()
	if ff.level == level:
		points.append(PlanStyle.to_px(display_pos(ff, alpha)))
	for wp in ff.path:
		if wp.z == level:
			points.append(PlanStyle.to_px(Vector2(wp.x + 0.5, wp.y + 0.5)))
	if points.size() >= 2:
		draw_polyline(points, PlanStyle.PATH_LINE, 1.5)


## 소화전 흡수관과 물탱크차 급수관: [시작점, 끝점] (셀 좌표) 목록
static func supply_lines(p_sim: SimWorld) -> Array[Array]:
	var lines: Array[Array] = []
	for v in p_sim.units.vehicles:
		if v.hydrant >= 0:
			var h := Vector2(p_sim.building.hydrants[v.hydrant]) + Vector2(0.5, 0.5)
			lines.append([h, v.closest_body_point(h)])
		if v.supply_to >= 0:
			var p := p_sim.units.get_vehicle(v.supply_to)
			lines.append([v.closest_body_point(p.pos), p.closest_body_point(v.pos)])
	return lines


## 직전 틱과 현재 틱 사이를 보간한 화면 위치. 층이 바뀐 직후에는 보간하지 않는다.
static func display_pos(ff: Firefighter, alpha: float) -> Vector2:
	if ff.prev_level != ff.level:
		return ff.pos
	return ff.prev_pos.lerp(ff.pos, alpha)
