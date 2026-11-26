class_name SelectionModel
extends RefCounted
## 고른 조·차량·지휘관 → 오른쪽 정보 창 모델 (SelectionInfo 가 그린다). 2026-11-27 사용자 결정:
##   - 대원 이름 대신 "대원1·2·3" + 임무(관창수·관창보조 / 구조대원 / 주처치자·보조처치자). 팀장은 "팀장". 실제 이름은 툴팁에만
##   - 상태 글 대신 칩(위치·지금 하는 일)·막대(공기·열·수관·작업 진행)·빨간 경고. 숫자는 툴팁에
##   - 운전원은 "운전원 · 차량 종류"

var sim: SimWorld
var style: SidePanelStyle
## 명령 id → 짧은 이름 (data/commands.json 모든 세트)
var labels: Dictionary = {}


func _init(p_sim: SimWorld) -> void:
	sim = p_sim
	style = SidePanelStyle.get_default()
	var sets := CommandCard.load_sets()
	for k: String in sets:
		for it: Dictionary in sets[k]:
			labels[str(it.id)] = str(it.label)
			for s: Dictionary in it.get("sub", []):
				labels[str(s.id)] = str(s.label)
	labels["hold"] = "대기"


## 대원 번호와 임무: [번호 글, 임무 글]. 번호는 출동대 안에서 대원 id 순 (나누고 합쳐도 같다). 팀장은 번호 없이
func member_label(ff: Firefighter, crew: Crew) -> Array[String]:
	var squad := sim.units.squads[ff.squad_id]
	if ff.officer:
		return [style.officer_label, ""] as Array[String]
	var n := 0
	for o in sim.units.firefighters:
		if o.squad_id == ff.squad_id and not o.officer and o.id <= ff.id:
			n += 1
	var names := style.role_names(squad.type)
	var lead := crew != null and not crew.list.is_empty() and (crew.list[0] == ff or (crew.list[0].officer and crew.list.size() > 1 and crew.list[1] == ff))
	if ff.incapacitated:
		return ["대원%d" % n, "행동 불능"] as Array[String]
	return ["대원%d" % n, str(names.get("lead" if lead else "other", ""))] as Array[String]


func build(crew_ids: Array[int], vehicle_ids: Array[int], commander: bool, portrait: Texture2D) -> Dictionary:
	var m: Dictionary
	var crews: Array[Crew] = []
	for id in crew_ids:
		var c := sim.units.get_crew(id)
		if c != null and not c.list.is_empty():
			crews.append(c)
	if not crews.is_empty():
		m = _crews_model(crews)
	elif not vehicle_ids.is_empty():
		m = _vehicle_model(vehicle_ids)
	elif commander:
		m = _commander_model()
	else:
		return {}
	m["portrait"] = portrait
	return m


# --- 조 ---

func _crews_model(crews: Array[Crew]) -> Dictionary:
	var m := {"chips": [], "bars": [], "warns": [], "groups": [], "compact": []}
	var first := crews[0]
	var squad := sim.units.squads[first.squad_id]
	var same_squad := crews.all(func(c: Crew) -> bool: return c.squad_id == first.squad_id)
	if crews.size() == 1:
		m.title = "%s 분대%s" % [squad.name, " · %d조" % first.number if squad.crews.size() > 1 else ""]
	elif same_squad:
		m.title = "%s 분대 · %d개 조" % [squad.name, crews.size()]
	else:
		m.title = "%d개 조 선택" % crews.size()
	m.title_tip = "%s (%s)" % [squad.name, squad.type]
	_squad_chips(m, first.squad_id)
	# 위치·지금 하는 일·상태는 첫 조 기준 (여러 조면 조마다 줄에 짧게)
	if crews.size() == 1:
		_crew_chips(m, first)
		_crew_bars(m, first)
	var many := crews.size() > style.max_crew_rows
	for c in crews:
		if many:
			m.compact.append(_compact(c))
			continue
		var g := {"head": "" if crews.size() == 1 else "%s · %d조 — %s" % [sim.units.squads[c.squad_id].name, c.number, _doing_text(c)], "members": []}
		for ff in c.members():
			g.members.append(_member(ff, c))
		m.groups.append(g)
		if crews.size() > 1:
			_crew_warns(m, c)
	return m


func _squad_chips(m: Dictionary, squad_id: int) -> void:
	var res := sim.command.resources
	if res.is_en_route(squad_id):
		m.chips.append({"icon": "clock", "text": "현장 접근 중", "color": SidePanelStyle.WARN, "tip": "아직 현장에 오는 중입니다"})
	elif res.is_staged(squad_id):
		var pending := sim.command.commit_pending(squad_id)
		m.chips.append({"icon": "radio" if pending else "clock", "text": "투입 무전 중" if pending else "대기1단계", "color": SidePanelStyle.WARN,
			"tip": "투입 무전을 보내는 중" if pending else "대기1단계 — 명령하면 투입 무전 후 실행합니다"})
	var d := sim.command.org.division_of(squad_id)
	if d:
		m.chips.append({"icon": "pin", "text": "%s 단위대%s" % [d.name, " 지휘" if d.supervisor == squad_id else ""], "color": SidePanelStyle.DIM, "tip": ""})


func _crew_chips(m: Dictionary, c: Crew) -> void:
	var lead := c.leader
	var where := "차량 탑승" if lead.aboard else (sim.building.floor_name(lead.level) if _indoor(lead) else "건물 밖")
	m.chips.append({"icon": "pin", "text": where, "color": SidePanelStyle.TEXT, "tip": "조장(선두)이 있는 곳"})
	# 지금 하는 일
	var hose := sim.water.hose_of_crew(c.id)
	if hose and hose.held() and hose.flowing:
		m.chips.append({"icon": "water", "text": "방수 중 · %s" % hose.pattern_name(), "color": SidePanelStyle.WATER, "tip": "관창을 열어 방수하고 있습니다"})
	else:
		var cmd := sim.crew_command(c.id)
		if cmd != "":
			m.chips.append({"icon": cmd, "text": str(labels.get(cmd, cmd)), "color": style.accent, "tip": sim.crew_busy(c.id)})
		elif not lead.aboard:
			var busy := sim.crew_busy(c.id)
			m.chips.append({"icon": "hold" if busy == "" else "clock", "text": "명령 대기" if busy == "" else _short(busy),
				"color": SidePanelStyle.DIM, "tip": busy if busy != "" else "맡은 임무가 없습니다 — 명령을 내리세요"})
	var role := sim.command.safety.role_of(c.id)
	if role != SafetySystem.Role.NONE:
		var dep := sim.command.safety.deployed.has(c.id)
		m.chips.append({"icon": "exterior", "text": SafetySystem.ROLE_NAMES[role] + (" 투입" if dep else ""), "color": style.accent,
			"tip": "투입됨" if dep else "다른 임무 불가 — 밖에서 대기"})
	if hose and not hose.held():
		var t := "관창으로 가는 중" if hose.to_nozzle else ("호스 회수 중" if hose.recovering else "관창 놓음")
		m.chips.append({"icon": "hose", "text": t, "color": SidePanelStyle.DIM, "tip": ""})
	var wt := sim.rekindle.watch_of_crew(c.id)
	if wt and wt.room >= 0:
		m.chips.append({"icon": "eye", "text": "감시 · %s" % sim.fire.comps[wt.room].display_name(), "color": SidePanelStyle.DIM, "tip": "재발화 감시 — 탄 방을 차례로 돌며 확인"})
	var task := sim.doors.task_of_crew(c.id)
	if task and task.stacked(c.id):
		var wc := sim.units.get_crew(task.worker())
		m.chips.append({"icon": "door", "text": "문 옆 대기", "color": SidePanelStyle.DIM, "tip": "%s 이(가) 문을 여는 동안 대기" % (sim.units.crew_name(wc) if wc != null else "다른 분대")})
	if sim.doors.fetch_progress(c.id, sim.clock.tick) < 0.0 and sim.doors.fetches.any(func(f: Dictionary) -> bool: return int(f.crew) == c.id):
		m.chips.append({"icon": "tool", "text": "장비 가지러 감", "color": SidePanelStyle.DIM, "tip": "장비를 가지러 차량으로 가는 중"})
	if lead.aboard and sim.command.resources.arriving_now():
		m.chips.append({"icon": "transport", "text": "차량 이동 중", "color": SidePanelStyle.DIM, "tip": "차량을 타고 오는 중"})
	if c.has_item("fire_door_breaker"):
		m.chips.append({"icon": "tool", "text": "방화문 파괴기", "color": SidePanelStyle.DIM, "tip": "휴대 장비: 방화문 파괴기"})


func _crew_bars(m: Dictionary, c: Crew) -> void:
	var cell := sim.building.cell_size_m
	var hose := sim.water.hose_of_crew(c.id)
	if hose and hose.held():
		var len_m := hose.length_cells() * cell
		var max_m := hose.max_cells * cell
		m.bars.append({"icon": "hose", "label": "수관", "value": len_m / maxf(1.0, max_m), "text": "%.0f/%.0fm" % [len_m, max_m],
			"color": SidePanelStyle.WATER, "tip": "깐 수관 길이 / 가진 수관 길이"})
	var task := sim.doors.task_of_crew(c.id)
	if task and not task.stacked(c.id):
		var what := "문 파괴" if task.opening.locked else ("문 개방" if task.open else "문 폐쇄")
		m.bars.append({"icon": "door", "label": what, "value": float(task.progress) / maxf(1.0, float(task.required)),
			"text": "%d/%d초" % [int(task.progress), int(task.required)], "color": style.accent,
			"tip": "인원 부족 — 손이 모자라 느립니다" if task.waiting_people else ""})
	var oh := sim.rekindle.task_of_crew(c.id)
	if oh:
		var total := sim.rekindle.overhaul_seconds()
		m.bars.append({"icon": "flame", "label": "잔불정리", "value": (total - oh.remain) / maxf(1.0, total),
			"text": "%d/%d초" % [int(total - oh.remain), int(total)], "color": SidePanelStyle.HEAT, "tip": "탄 곳을 헤집어 숨은 불씨를 끕니다"})
	var fp := sim.doors.fetch_progress(c.id, sim.clock.tick)
	if fp >= 0.0:
		m.bars.append({"icon": "tool", "label": "장비 꺼냄", "value": fp, "text": "%d%%" % roundi(fp * 100.0), "color": style.accent, "tip": "차량에서 장비를 꺼내는 중"})
	_crew_warns(m, c)


func _crew_warns(m: Dictionary, c: Crew) -> void:
	var hose := sim.water.hose_of_crew(c.id)
	if hose and hose.held():
		if hose.flowing and hose.flow_fraction < 0.99:
			m.warns.append({"icon": "water", "text": "수압 부족 (%d%%)" % roundi(hose.flow_fraction * 100.0), "tip": "물이 모자랍니다 — 급수 연결·소화전 점령을 확인하세요"})
		if hose.flowing and hose.blocked:
			m.warns.append({"icon": "warn", "text": "물줄기 막힘", "tip": "벽·문에 막혀 목표에 닿지 않습니다"})
		if hose.at_limit:
			m.warns.append({"icon": "hose", "text": "수관 길이 한계", "tip": "가진 수관을 다 깔았습니다 — 더 들어갈 수 없습니다"})
	var short := false
	for ff in c.members():
		if not ff.incapacitated and ff.exit_air_l > 0.0 and ff.air_l <= ff.exit_air_l:
			short = true
	if short:
		m.warns.append({"icon": "warn", "text": "출구까지 공기 부족", "tip": "지금 나가도 출구 전에 공기가 떨어질 수 있습니다 — 철수하세요"})


func _member(ff: Firefighter, c: Crew) -> Dictionary:
	var lab := member_label(ff, c)
	var full := style.bar_full_bar
	var need := ff.exit_air_l / maxf(1.0, ff.air_capacity)
	var air_tip := "잔압 %dbar (%d%%)" % [roundi(ff.air_ratio() * full), roundi(ff.air_ratio() * 100.0)]
	if need > 0.0:
		air_tip += "\n출구까지 필요 %dbar (흰 눈금) · 호흡 %dℓ/분" % [maxi(1, roundi(need * full)), roundi(sim.conditions.air_rate(ff))]
	var heat_tip := "열 스트레스 %d%%" % roundi(ff.heat_stress * 100.0)
	if ff.heat_flux >= 0.05:
		heat_tip += "\n복사열 %.1fkW/㎡" % ff.heat_flux
	var icons: Array = []
	if ff.incapacitated:
		icons.append({"icon": "down", "color": SidePanelStyle.DANGER, "tip": "행동 불능"})
	if ff.crouched:
		icons.append({"icon": "crouch", "color": SidePanelStyle.DIM, "tip": "낮은 자세 (연기·열 때문에)"})
	if ff.heat_flux >= style.flux_show_kw:
		icons.append({"icon": "flame", "color": SidePanelStyle.HEAT, "tip": "복사열 %.1fkW/㎡" % ff.heat_flux})
	if c.thermal_camera and ff == c.leader:
		icons.append({"icon": "thermal", "color": SidePanelStyle.DIM, "tip": "열화상카메라"})
	var traits: PackedStringArray = []
	if ff.grade != "":
		traits.append(ff.grade)
	traits.append_array(ff.traits)
	if not traits.is_empty():
		icons.append({"icon": "veteran", "color": Color("fcd34d") if not "신참" in traits else SidePanelStyle.DIM, "tip": "개성: " + ", ".join(traits)})
	return {"num": lab[0], "role": lab[1], "air": ff.air_ratio(), "need": need, "heat": ff.heat_stress, "down": ff.incapacitated,
		"icons": icons, "air_tip": air_tip, "heat_tip": heat_tip,
		"tip": "%s %s%s" % [ff.rank, ff.name, " · " + ff.role if ff.role != "" else ""]}


func _compact(c: Crew) -> Dictionary:
	var air := 1.0
	for ff in c.members():
		air = minf(air, ff.air_ratio())
	return {"name": "%s · %d조" % [sim.units.squads[c.squad_id].name, c.number], "air": air, "state": _doing_text(c),
		"tip": "가장 낮은 공기 %d%%" % roundi(air * 100.0)}


## 조가 하는 일 짧게 (여러 조를 골랐을 때 조 머리글)
func _doing_text(c: Crew) -> String:
	var hose := sim.water.hose_of_crew(c.id)
	if hose and hose.held() and hose.flowing:
		return "방수 중"
	var cmd := sim.crew_command(c.id)
	if cmd != "":
		return str(labels.get(cmd, cmd))
	var busy := sim.crew_busy(c.id)
	return _short(busy) if busy != "" else "명령 대기"


func _short(text: String) -> String:
	return text.replace("을 잡고 있음", "").replace(" 중", "").replace("(RIT·현장안전담당)", "")


func _indoor(ff: Firefighter) -> bool:
	return not sim.building.cell(ff.level, floori(ff.pos.x), floori(ff.pos.y)) in BuildingData.OUTDOOR


# --- 차량 ---

func _vehicle_model(ids: Array[int]) -> Dictionary:
	var v := sim.units.get_vehicle(ids[0])
	var squad := sim.units.squads[v.squad_id]
	var m := {"title": v.display_name(squad.name), "chips": [], "bars": [], "warns": [], "groups": [], "compact": []}
	var hints: PackedStringArray = ["운전원: %s" % v.driver_label()]
	_squad_chips(m, v.squad_id)
	if v.away:
		m.chips.append({"icon": "transport", "text": "환자 이송 중", "color": SidePanelStyle.WARN, "tip": "현장에 없습니다"})
	if v.hydrant >= 0:
		m.chips.append({"icon": "hydrant", "text": "소화전 연결", "color": SidePanelStyle.WATER, "tip": ""})
	if v.supply_to >= 0:
		m.chips.append({"icon": "water", "text": "급수 중", "color": SidePanelStyle.WATER, "tip": "다른 펌프차에 물을 보내는 중"})
	if v.is_pump():
		var hs := sim.water.hoses_of_vehicle(v.id)
		m.chips.append({"icon": "hose", "text": "수관 %d" % hs.size(), "color": SidePanelStyle.TEXT, "tip": "이 차에 연결된 수관 수"})
		if sim.water.fdc_vehicle == v.id:
			m.chips.append({"icon": "office", "text": "송수구 연결", "color": SidePanelStyle.WATER, "tip": "연결송수관 가압 중"})
		hints.append("소화전 우클릭: 점령")
		if sim.building.has_standpipe():
			hints.append("송수구 우클릭: 연결송수관 가압")
	elif v.transfer_lpm > 0.0:
		var sh: Dictionary = sim.shuttle.tankers.get(v.id, {})
		if not sh.is_empty():
			m.chips.append({"icon": "shuttle", "text": "순환보수 %d회" % int(sh.trips), "color": SidePanelStyle.WATER, "tip": ""})
		hints.append("펌프차 우클릭: 급수 · 소화전 우클릭: 점령")
	if v.tank_capacity > 0.0:
		m.bars.append({"icon": "tank", "label": "물탱크", "value": v.tank_l / v.tank_capacity, "text": "%s L" % _thousands(v.tank_l),
			"color": SidePanelStyle.WATER if v.tank_l > v.tank_capacity * style.air_danger else SidePanelStyle.DANGER,
			"tip": "%s / %s L" % [_thousands(v.tank_l), _thousands(v.tank_capacity)]})
	if not v.work.is_empty():
		var total := float(v.work.get("total", 1.0))
		var remain := float(v.work.get("remain", 0.0))
		m.bars.append({"icon": "clock", "label": str(v.work.get("label", "작업")), "value": (total - remain) / maxf(1.0, total),
			"text": "%d초 남음" % ceili(remain), "color": style.accent, "tip": ""})
	m.title_tip = "\n".join(hints)
	m.groups.append({"head": "", "members": [{"num": "%s · %s" % [style.driver_label, v.type], "role": _driver_job(v), "air": -1.0,
		"icons": [], "tip": v.driver_label()}]})
	for i in range(1, ids.size()):
		var o := sim.units.get_vehicle(ids[i])
		m.compact.append({"name": o.display_name(sim.units.squads[o.squad_id].name), "air": -1.0, "state": _driver_job(o), "tip": ""})
	return m


func _driver_job(v: Vehicle) -> String:
	if v.away:
		return "이송 중"
	if not v.work.is_empty():
		return str(v.work.get("label", "작업 중"))
	if v.is_moving():
		return "운전 중"
	var pumping := v.supply_to >= 0
	for h in sim.water.hoses_of_vehicle(v.id):
		if h.flowing:
			pumping = true
	if pumping:
		return "펌프 조작"
	return "대기"


static func _thousands(value: float) -> String:
	var s := str(roundi(value))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


# --- 지휘관 ---

func _commander_model() -> Dictionary:
	var cmd := sim.command
	var m := {"title": "현장지휘관", "chips": [], "bars": [], "warns": [], "groups": [], "compact": []}
	m.title_tip = "%s %s (%s)\n우클릭: 이동 (건물 안으로는 혼자 들어가지 않음) · 관계인 우클릭: 다가가 질문" % [cmd.commander.rank, cmd.commander.name, cmd.commander_title]
	m.chips.append({"icon": "pin", "text": cmd.commander_position_text(), "color": SidePanelStyle.TEXT, "tip": "지휘 위치"})
	m.chips.append({"icon": "person", "text": cmd.commander_title, "color": style.accent, "tip": ""})
	var ask := cmd.survey.asking()
	if not ask.is_empty():
		m.chips.append({"icon": "report", "text": "질문 중 · %d개 남음" % ask.questions.size(), "color": SidePanelStyle.WARN, "tip": "관계인에게 질문하는 중"})
	return m
