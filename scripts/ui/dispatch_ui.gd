class_name DispatchUi
extends Control
## 출동 중 장면 (기획안 4-4, 2026-11-14 사용자 결정 — 예전: 출동 지령 창 하나에 지령·배치·장비·임무를 한꺼번에).
## 소방차가 도시를 달리는 동안 결정을 한 번에 하나씩 묻는다 (프로스트펑크의 사건 창 방식):
##   오른쪽 = 장면 (먹물 바탕 + 차량 안에서 무전하는 소방관 그림 + 글 + 둥근 단추) — 가운데의 출동 경로·현장을 가리지 않는다
##   왼쪽 = 출동 준비판 (받은 상황실 무전, 신고 후 시각, 결정 목록과 고른 것, '현장 도착' 단추)
## 장면 순서 (data/ui/dispatch.json order): 출동 지령 → 상황실 요청 카드(관계자 조치·예비 소방용수) → 상황실 추가 무전
##   → 장비 챙기기(체크 목록) → 조마다 도착 후 임무 → 선착 차량 배치
## 시간: 실제 시간으로 흐른다 (phase_params dispatch_real_s). 현장 시계는 멈춰 있다 — 불은 이미 계산되어 있다
##   훈련: 차가 현장 앞에 닿아도 결정을 마칠 때까지 기다린다
##   실전·악조건: 시간이 다 되면 그대로 도착한다 — 정하지 않은 것은 준비하지 않은 것 (장비 없음, 임무 없음, 카드는 '정하지 않음')
##   결정을 모두 마치면 '현장 도착(Enter)'으로 남은 길을 건너뛴다 (결정은 건너뛸 수 없다)
## 결정은 여기서 바로 시뮬레이션에 넣지 않는다 — 도착할 때 CommandUi가 result()를 명령(기록·다시 하기 대상)으로 내린다

## 현장 도착 (차가 닿았거나 건너뜀). CommandUi가 결정을 명령으로 내리고 장면을 닫는다
signal finished

const PATH := "res://data/ui/dispatch.json"
const PANEL_BG := Color(0.07, 0.09, 0.12, 0.92)
const TEXT_COLOR := Color("e2e8f0")
const DIM_COLOR := Color("94a3b8")
const HEAD_COLOR := Color("fde68a")
const DONE_COLOR := Color("86efac")
const TITLE_COLOR := Color("fca5a5")
const ACCENT := Color("e2e8f0")

var sim: SimWorld
## 설정값 (data/ui/dispatch.json 의 value) · 장면 글
var p: Dictionary = {}
var texts: Dictionary = {}
## 장면 목록. 하나 = {kind, mode(pick 누르면 답 / multi 여럿 고르고 확인 / select 하나 고르고 확인), name, tag, who, portrait,
##   title, text, options [{text, value, note}], picked [고른 보기 순서], answered, cap, confirm, lines, card_id, crew_id}
var steps: Array[Dictionary] = []
## 지금 장면 (steps.size()면 모두 마침)
var index := 0
## 출동 단계에 흐른 실제 시간 (초)
var real_s := 0.0
## 출동 중인가 (장면·준비판이 떠 있다)
var active := false
## 남은 길을 건너뛰는 중
var skipping := false
## 장면의 위쪽 한계를 알려 주는 함수 (튜토리얼 안내판 아래로 내리기 — HUD가 넣는다). 없으면 0
var top_inset := Callable()
var _gap := 0.0
var _skip_rate := 1.0
var _shown := -2
var _scene: Control
var _portrait: TextureRect
var _badge: Label
var _tag: Label
var _ornament: Control
var _who: Label
var _head: Label
var _text: Label
var _grid: GridContainer
var _desc: Label
var _confirm: Button
var _count: Label
var _buttons: Array[Button] = []
var _prep: PanelContainer
var _clock: Label
var _bar: ProgressBar
var _lines: Label
var _steps_head: Label
var _step_rows: Array[Label] = []
var _go: Button
var _feedback: Label
var _feedback_box: PanelContainer
var _feedback_left := 0.0


## 설정 파일의 value 만 모은다 (texts·preassign 은 통째로)
static func load_params() -> Dictionary:
	var out: Dictionary = {}
	var data: Variant = JsonData.load_file(PATH)
	if data is Dictionary:
		for key: String in data:
			var entry: Variant = data[key]
			if entry is Dictionary and (entry as Dictionary).has("value"):
				out[key] = entry["value"]
			elif key in ["texts", "preassign"]:
				out[key] = entry
	return out


func num(key: String, fallback := 0.0) -> float:
	return float(p.get(key, fallback))


func t(key: String) -> String:
	return str(texts.get(key, key))


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	p = load_params()
	texts = p.get("texts", {})
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_steps()
	_build_scene()
	_build_prep()
	_build_feedback()
	visible = false


# --- 장면 목록 ---

## 시나리오로 장면 목록을 만든다 (지령 줄·출동 단계 카드·적재 장비·처음 오는 조·차량 배치 보기)
func build_steps() -> void:
	steps.clear()
	var d := sim.command.dispatch
	var lines: Array = d.get("lines", [])
	var first := clampi(int(num("brief_first_lines", 2)), 1, maxi(1, lines.size()))
	var stand_in := _portrait_path(str(p.get("portrait_key", "출동")))
	for part: String in p.get("order", ["brief", "cards", "brief_more", "loadout", "preassign", "placement"]):
		match part:
			"brief":
				if not lines.is_empty():
					steps.append(_step("brief", "pick", t("brief_title"), t("brief_tag"), t("brief_who"), stand_in,
						str(d.get("title", t("brief_title"))), _joined(lines.slice(0, first)), [{"text": t("brief_ok"), "value": 0}],
						{"lines": lines.slice(0, first)}))
			"brief_more":
				if lines.size() > first:
					steps.append(_step("brief", "pick", t("brief_more_title"), t("brief_tag"), t("brief_who"), stand_in,
						t("brief_more_title"), _joined(lines.slice(first)), [{"text": t("brief_more_ok"), "value": 0}],
						{"lines": lines.slice(first)}))
			"cards":
				for spec: Dictionary in sim.cards.dispatch_specs():
					var opts: Array = []
					var src: Array = spec.get("options", [])
					for i in _shuffled(src.size(), str(spec.get("id", ""))):
						opts.append({"text": str(src[i].get("text", "")), "value": i, "grade": str(src[i].get("grade", ""))})
					steps.append(_step("card", "pick", str(spec.get("title", "")), t("card_tag"), t("card_who"), stand_in,
						str(spec.get("title", "")), str(spec.get("text", "")), opts, {"card_id": str(spec.get("id", "")), "spec": spec}))
			"loadout":
				var data: Variant = JsonData.load_file("res://data/units/equipment.json")
				if data is Dictionary and not (data.get("items", []) as Array).is_empty():
					var cap := int(data.get("capacity", 3))
					var items: Array = []
					for it: Dictionary in data.get("items", []):
						items.append({"text": str(it.get("label", "")), "value": str(it.get("key", "")), "note": "%s (SOP %s)" % [it.get("note", ""), it.get("sop", "")]})
					steps.append(_step("loadout", "multi", t("loadout_title"), t("loadout_tag"), t("loadout_who"), stand_in,
						t("loadout_title"), t("loadout_text").format({"cap": cap}), items, {"cap": cap, "confirm": t("loadout_ok")}))
			"preassign":
				for c: Crew in sim.units.crews:
					if not sim.command.resources.on_scene(c.squad_id) or sim.ems.is_ems_crew(c.id):
						continue
					var squad := sim.units.squads[c.squad_id]
					var crew_name := "%s %d조" % [squad.name, c.number]
					var kinds: Array = []
					for k: Array in p.get("preassign", {}).get("options", []):
						if str(k[0]) == "office" and sim.plan.office.is_empty():
							continue
						kinds.append({"text": str(k[1]), "value": str(k[0])})
					steps.append(_step("preassign", "pick", "%s 임무" % crew_name, t("preassign_tag"),
						"%s · %s %s" % [crew_name, c.leader.rank, c.leader.name], _portrait_path(squad.type),
						t("preassign_title"), t("preassign_text").format({"crew": crew_name}), kinds, {"crew_id": c.id}))
			"placement":
				var opts := Placement.options(sim)
				if not opts.is_empty():
					var list: Array = []
					for i in opts.size():
						list.append({"text": str(opts[i].get("name", "")), "value": i, "note": str(opts[i].get("text", ""))})
					steps.append(_step("placement", "select", t("placement_title"), t("placement_tag"), t("placement_who"), stand_in,
						t("placement_title"), t("placement_text"), list, {"confirm": t("placement_ok")}))


func _step(kind: String, mode: String, step_name: String, tag: String, who: String, portrait: String, title: String, text: String,
		options: Array, more: Dictionary) -> Dictionary:
	var s := {"kind": kind, "mode": mode, "name": step_name, "tag": tag, "who": who, "portrait": portrait, "title": title, "text": text,
		"options": options, "picked": [], "answered": false}
	s.merge(more)
	return s


func _joined(lines: Array) -> String:
	return "\n".join(PackedStringArray(lines))


func _portrait_path(key: String) -> String:
	var portraits: Dictionary = SpriteArt.config().get("portraits", {})
	return str(portraits.get(key, portraits.get("default", "")))


## 보기 순서를 섞는다 (같은 시나리오·같은 카드는 늘 같은 순서 — 자리로 외우지 못하게, 다시 하기에서도 같게)
func _shuffled(count: int, key: String) -> Array:
	var order: Array = range(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("dispatch:%d:%s" % [sim.cards._seed, key])
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = order[i]
		order[i] = order[j]
		order[j] = tmp
	return order


# --- 진행 ---

## 출동을 시작한다 (장면과 준비판을 띄운다)
func open() -> void:
	index = 0
	real_s = 0.0
	skipping = false
	_gap = num("next_delay_s", 0.6)
	_shown = -2
	active = true
	visible = true
	_refresh()


## 도착하지 않고 닫는다 (디브리핑으로 넘어갈 때·조작 점검)
func cancel() -> void:
	active = false
	visible = false


## 결정을 모두 마쳤는가
func done() -> bool:
	return index >= steps.size()


## 지금 떠 있는 장면 (다음 장면을 기다리는 사이·모두 마친 뒤에는 빈 것)
func current() -> Dictionary:
	if not active or done() or _gap > 0.0:
		return {}
	return steps[index]


func real_total() -> float:
	return maxf(1.0, float(sim._phase_params.value("dispatch_real_s")))


## 출동 진행률 0~1
func frac() -> float:
	return clampf(real_s / real_total(), 0.0, 1.0)


## 도시 위 소방차가 쓰는 진행률 (출동 중이 아니면 -1)
func progress() -> float:
	return frac() if active and sim.dispatch_s > 0.0 else -1.0


## 시간이 다 되면 기다리지 않고 도착하는 방식인가 (실전·악조건)
func realtime() -> bool:
	return sim.realism in ["실전", "악조건"]


## 보기를 누른다: pick = 그 답으로 정함 / multi = 켜고 끔(정한 개수까지) / select = 고름(확인은 따로)
func choose(i: int) -> void:
	var s := current()
	if s.is_empty() or i < 0 or i >= (s.options as Array).size():
		return
	var picked: Array = s.picked
	match str(s.mode):
		"pick":
			s.picked = [i]
			_answer(s)
		"multi":
			if i in picked:
				picked.erase(i)
			elif picked.size() < int(s.get("cap", 99)):
				picked.append(i)
			_fill_options(s)
		"select":
			s.picked = [i]
			_fill_options(s)


## 고른 것으로 정한다 (multi·select 장면의 확인 단추)
func confirm() -> void:
	var s := current()
	if s.is_empty() or str(s.mode) == "pick":
		return
	if str(s.mode) == "select" and (s.picked as Array).is_empty():
		return
	_answer(s)


func _answer(s: Dictionary) -> void:
	s.answered = true
	if str(s.kind) == "card" and not realtime():
		_show_feedback(s)
	index += 1
	_gap = num("next_delay_s", 0.6)
	_refresh()


## Enter: 확인할 것이 있으면 확인, 결정을 모두 마쳤으면 남은 길을 건너뛴다
func enter() -> void:
	var s := current()
	if not s.is_empty():
		if str(s.mode) != "pick":
			confirm()
		elif (s.options as Array).size() == 1:
			choose(0)
		return
	skip()


## 남은 길 건너뛰기 — 결정을 모두 마친 뒤에만 (결정은 건너뛸 수 없다, 기획안 4-4)
func skip() -> void:
	if not active or not done() or skipping:
		return
	skipping = true
	_skip_rate = maxf(1.0, (real_total() - real_s) / maxf(0.1, num("skip_s", 2.5)))
	_refresh()


## 남은 결정을 모두 첫 보기로 정한다 (조작 점검용 — 실제 화면에서는 쓰지 않는다)
func answer_rest() -> void:
	while active and not done():
		var s := steps[index]
		_gap = 0.0
		if str(s.mode) == "pick":
			choose(0)
		else:
			if str(s.mode) == "select":
				choose(0)
			confirm()
	_gap = 0.0


## 실제 시간 delta 만큼 진행한다 (_process 가 부른다)
func advance(delta: float) -> void:
	if not active:
		return
	_gap = maxf(0.0, _gap - delta)
	real_s = minf(real_total(), real_s + delta * (_skip_rate if skipping else 1.0))
	# 현장 앞: 결정을 마쳤거나, 기다리지 않는 방식이면 도착
	if frac() >= 1.0 and (done() or realtime()):
		active = false
		visible = false
		finished.emit()


## 도착할 때 명령으로 내릴 결정들.
##   cards {카드 id: 고른 선택지(카드 파일 순서) 또는 -1 = 정하지 않음} · loadout [장비 키] · has_loadout 장비 장면이 있었는가
##   placement 배치 보기 순서(-1 = 정하지 않음) · preassign {조 id(문자열): 임무 키}
func result() -> Dictionary:
	var out := {"cards": {}, "loadout": [], "has_loadout": false, "placement": -1, "preassign": {}}
	for s: Dictionary in steps:
		var picked: Array = s.picked if bool(s.answered) else []
		var opts: Array = s.options
		match str(s.kind):
			"card":
				out.cards[str(s.card_id)] = int(opts[picked[0]].value) if not picked.is_empty() else -1
			"loadout":
				out.has_loadout = true
				for i: int in picked:
					out.loadout.append(str(opts[i].value))
			"placement":
				out.placement = int(opts[picked[0]].value) if not picked.is_empty() else -1
			"preassign":
				if not picked.is_empty() and str(opts[picked[0]].value) != "":
					out.preassign[str(int(s.crew_id))] = str(opts[picked[0]].value)
	return out


## 준비판에 적는 그 결정의 한 줄 요약
func summary(s: Dictionary) -> String:
	if not bool(s.answered):
		return ""
	var opts: Array = s.options
	var picked: Array = s.picked
	match str(s.kind):
		"brief":
			return "수신"
		"loadout":
			if picked.is_empty():
				return t("loadout_none")
			var names := PackedStringArray()
			for i: int in picked:
				names.append(str(opts[i].text))
			return ", ".join(names)
	return str(opts[picked[0]].text) if not picked.is_empty() else ""


## 지금까지 받은 상황실 무전 줄 (떠 있는 지령 장면까지)
func received_lines() -> Array:
	var out: Array = []
	for i in steps.size():
		if i > index or (i == index and _gap > 0.0):
			break
		if str(steps[i].kind) == "brief":
			out.append_array(steps[i].get("lines", []))
	return out


# --- 화면 ---

func _build_scene() -> void:
	var sw := num("scene_w", 900)
	var sh := num("scene_h", 660)
	_scene = Control.new()
	_scene.custom_minimum_size = Vector2(sw, sh)
	_scene.size = Vector2(sw, sh)
	_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scene)
	var blot := TextureRect.new()
	blot.texture = CardUi._texture(CardUi.BLOT_PATH)
	blot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blot.stretch_mode = TextureRect.STRETCH_SCALE
	blot.size = Vector2(sw, sh)
	blot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(blot)
	var pr: Array = p.get("portrait_rect", [44, 120, 290, 410])
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.position = Vector2(float(pr[0]), float(pr[1]))
	_portrait.size = Vector2(float(pr[2]), float(pr[3]))
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene.add_child(_portrait)
	_badge = Label.new()
	_badge.text = "무전"
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.position = _portrait.position
	_badge.size = _portrait.size
	_badge.add_theme_font_size_override("font_size", 44)
	_badge.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9, 0.6))
	_scene.add_child(_badge)
	var tw := num("text_w", 500)
	var box := VBoxContainer.new()
	box.position = Vector2(num("text_x", 356), num("text_y", 78))
	box.custom_minimum_size = Vector2(tw, 0)
	box.add_theme_constant_override("separation", 7)
	_scene.add_child(box)
	_tag = Label.new()
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.add_theme_font_size_override("font_size", 14)
	_tag.add_theme_color_override("font_color", CardUi.RADIO_TAG)
	box.add_child(_tag)
	_ornament = Control.new()
	_ornament.custom_minimum_size = Vector2(tw, 14)
	_ornament.draw.connect(func() -> void: CardUi.draw_ornament(_ornament, ACCENT))
	box.add_child(_ornament)
	_who = Label.new()
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_who.add_theme_font_size_override("font_size", 15)
	_who.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	box.add_child(_who)
	_head = Label.new()
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_head.custom_minimum_size = Vector2(tw, 0)
	_head.add_theme_font_size_override("font_size", 27)
	_head.add_theme_color_override("font_color", ACCENT)
	box.add_child(_head)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(tw, 0)
	_text.add_theme_font_size_override("font_size", 17)
	_text.add_theme_color_override("font_color", Color(0.86, 0.88, 0.9))
	_text.add_theme_constant_override("line_spacing", 4)
	box.add_child(_text)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	box.add_child(gap)
	_grid = GridContainer.new()
	_grid.columns = 1
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 7)
	box.add_child(_grid)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(tw, 0)
	_desc.add_theme_font_size_override("font_size", 15)
	_desc.add_theme_color_override("font_color", Color(0.8, 0.84, 0.88))
	box.add_child(_desc)
	_confirm = CardUi.pill(num("button_w", 470))
	_confirm.add_theme_color_override("font_color", HEAD_COLOR)
	_confirm.pressed.connect(confirm)
	box.add_child(_confirm)
	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_font_size_override("font_size", 14)
	_count.add_theme_color_override("font_color", DIM_COLOR)
	box.add_child(_count)
	_scene.visible = false


func _build_prep() -> void:
	var w := num("prep_w", 450)
	_prep = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color("475569")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_prep.add_theme_stylebox_override("panel", style)
	_prep.custom_minimum_size = Vector2(w, 0)
	add_child(_prep)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_prep.add_child(box)
	var inner := w - 28.0
	var title := _label(str(sim.command.dispatch.get("title", t("prep_title"))), 21, TITLE_COLOR)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(inner, 0)
	box.add_child(title)
	_clock = _label("", 15, HEAD_COLOR)
	_clock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_clock.custom_minimum_size = Vector2(inner, 0)
	box.add_child(_clock)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(inner, 8)
	_bar.max_value = 1.0
	box.add_child(_bar)
	box.add_child(_label(t("prep_lines"), 15, HEAD_COLOR))
	_lines = _label("", 14, TEXT_COLOR)
	_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lines.custom_minimum_size = Vector2(inner, 0)
	box.add_child(_lines)
	_steps_head = _label("", 15, HEAD_COLOR)
	box.add_child(_steps_head)
	for i in steps.size():
		var row := _label("", 14, DIM_COLOR)
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.custom_minimum_size = Vector2(inner, 0)
		box.add_child(row)
		_step_rows.append(row)
	_go = Button.new()
	_go.focus_mode = Control.FOCUS_NONE
	_go.custom_minimum_size = Vector2(inner, 40)
	_go.add_theme_font_size_override("font_size", 16)
	_go.pressed.connect(skip)
	box.add_child(_go)


func _build_feedback() -> void:
	_feedback_box = PanelContainer.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.04, 0.05, 0.08, 0.9)
	fb.set_corner_radius_all(6)
	fb.set_content_margin_all(10)
	fb.content_margin_left = 18
	fb.content_margin_right = 18
	_feedback_box.add_theme_stylebox_override("panel", fb)
	_feedback_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_box.visible = false
	_feedback = Label.new()
	_feedback.add_theme_font_size_override("font_size", 20)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_box.add_child(_feedback)
	add_child(_feedback_box)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _process(delta: float) -> void:
	if sim == null:
		return
	# 고른 직후 한 줄은 도착한 뒤에도 마저 보인다
	if _feedback_left > 0.0:
		_feedback_left -= delta
		_feedback_box.modulate.a = clampf(_feedback_left, 0.0, 1.0)
		_feedback_box.position = Vector2((size.x - _feedback_box.size.x) * 0.5, 150.0)
		if _feedback_left <= 0.0:
			_feedback_box.visible = false
	if not active:
		_scene.visible = false
		_prep.visible = false
		visible = _feedback_left > 0.0
		return
	advance(delta)
	if not active:
		return
	_refresh()
	_place()


## 장면은 화면 오른쪽에, 준비판은 왼쪽에. 화면이 작으면 장면을 줄여서 넣는다
func _place() -> void:
	var sw := num("scene_w", 900)
	var sh := num("scene_h", 660)
	var k := minf(1.0, minf(size.x * 0.5 / sw, size.y / (sh + 40.0)))
	_scene.scale = Vector2(k, k)
	var y := maxf(20.0, (size.y - sh * k) * 0.46)
	if top_inset.is_valid():
		y = maxf(y, float(top_inset.call()) - num("text_y", 78) * k * 0.5)
	_scene.position = Vector2(size.x - sw * k - num("scene_right_px", 0), minf(y, maxf(20.0, size.y - sh * k - 60.0)))
	_prep.reset_size()
	_prep.position = Vector2(12.0, num("prep_top_px", 76))


## 장면·준비판 내용을 지금 상태로 맞춘다
func _refresh() -> void:
	if _scene == null:
		return
	var s := current()
	_scene.visible = active and not s.is_empty()
	_prep.visible = active
	var at := index if not s.is_empty() else -1
	if at != _shown:
		_shown = at
		if not s.is_empty():
			_fill(s)
	# 준비판: 시각·받은 무전·결정 목록
	var total := int(sim.dispatch_s)
	var now := roundi(sim.dispatch_s * frac())
	var fmt := {"now": "%02d:%02d" % [now / 60, now % 60], "eta": "%02d:%02d" % [total / 60, total % 60]}
	_clock.text = (t("prep_clock_wait") if not done() else t("prep_clock_arrived")).format(fmt) if frac() >= 1.0 else t("prep_clock").format(fmt)
	_bar.value = frac()
	var got := received_lines()
	_lines.text = _joined(got) if not got.is_empty() else t("prep_lines_none")
	var answered := 0
	for i in steps.size():
		var st := steps[i]
		var row := _step_rows[i]
		if bool(st.answered):
			answered += 1
			row.text = "✓ %s — %s" % [st.name, summary(st)]
			row.add_theme_color_override("font_color", DONE_COLOR)
		elif i == index:
			row.text = "▶ %s" % st.name
			row.add_theme_color_override("font_color", HEAD_COLOR)
		else:
			row.text = "· %s" % st.name
			row.add_theme_color_override("font_color", DIM_COLOR)
		row.tooltip_text = row.text
	_steps_head.text = t("prep_steps").format({"done": answered, "all": steps.size()})
	_go.disabled = not done() or skipping
	_go.text = t("prep_skipping") if skipping else (t("prep_go") if done() else t("prep_left").format({"n": steps.size() - answered}))


## 장면 하나를 채운다
func _fill(s: Dictionary) -> void:
	var tex := CardUi._texture(str(s.portrait))
	_portrait.texture = tex
	_portrait.visible = tex != null
	_badge.visible = tex == null
	_tag.text = str(s.tag)
	_who.text = str(s.who)
	_head.text = str(s.title)
	_text.text = CardUi.spoken(str(s.text)) if str(s.kind) == "card" else str(s.text)
	_count.text = "%d / %d" % [index + 1, steps.size()]
	_ornament.queue_redraw()
	for b in _buttons:
		_grid.remove_child(b)
		b.queue_free()
	_buttons.clear()
	var opts: Array = s.options
	var two := str(s.mode) == "multi" and opts.size() > 3
	_grid.columns = 2 if two else 1
	var bw := (num("text_w", 500) - 8.0) * 0.5 if two else num("button_w", 470)
	for i in opts.size():
		var b := CardUi.pill(bw)
		b.toggle_mode = str(s.mode) != "pick"
		b.tooltip_text = "숫자키 %d%s" % [i + 1, " — " + str(opts[i].note) if str(s.mode) == "multi" and str(opts[i].get("note", "")) != "" else ""]
		# 꺼진 단추(정한 개수를 다 채움)는 흐리게
		b.add_theme_stylebox_override("disabled", b.get_theme_stylebox("normal"))
		b.add_theme_color_override("font_disabled_color", Color(0.55, 0.6, 0.66, 0.6))
		b.pressed.connect(choose.bind(i))
		_grid.add_child(b)
		_buttons.append(b)
	_fill_options(s)


## 보기 단추의 글·눌림·꺼짐, 고른 보기의 설명, 확인 단추
func _fill_options(s: Dictionary) -> void:
	var opts: Array = s.options
	var picked: Array = s.picked
	var mode := str(s.mode)
	var full := mode == "multi" and picked.size() >= int(s.get("cap", 99))
	for i in _buttons.size():
		var b := _buttons[i]
		var on := i in picked
		b.text = ("✓ " if on and mode != "pick" else "") + str(opts[i].text)
		if mode != "pick":
			b.set_pressed_no_signal(on)
			b.disabled = full and not on
	# 고른 보기의 설명 (차량 배치: 그 자리의 장단점)
	var note := ""
	if mode == "select" and not picked.is_empty():
		note = str(opts[picked[0]].get("note", ""))
	_desc.text = note
	_desc.visible = note != ""
	_confirm.visible = mode != "pick"
	_confirm.disabled = mode == "select" and picked.is_empty()
	_confirm.text = str(s.get("confirm", "")).format({"n": picked.size(), "cap": int(s.get("cap", 0))}) + " (Enter)"


## 훈련 방식: 카드에 답한 직후 등급과 근거를 한 줄로 (무전 장면과 같다). 실전에서는 부르지 않는다
func _show_feedback(s: Dictionary) -> void:
	if _feedback == null or (s.picked as Array).is_empty():
		return
	_feedback.text = feedback_text(s)
	_feedback.add_theme_color_override("font_color", CardUi.GRADE_COLORS.get(str(s.options[s.picked[0]].get("grade", "")), Color.WHITE))
	_feedback_box.modulate.a = 1.0
	_feedback_box.visible = true
	_feedback_box.reset_size()
	_feedback_left = num("feedback_s", 4.0)


## 등급 — 근거 조항 (예: "최선 — SOP 200-2.2")
func feedback_text(s: Dictionary) -> String:
	var grade := str(s.options[s.picked[0]].get("grade", ""))
	var refs: Array = (s.get("spec", {}) as Dictionary).get("sop_ref", [])
	return grade if refs.is_empty() else "%s — %s" % [grade, ", ".join(PackedStringArray(refs))]


func _unhandled_key_input(event: InputEvent) -> void:
	if not active or not event is InputEventKey or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if k >= KEY_1 and k <= KEY_9:
		# 출동 중에는 숫자키를 장면의 보기에만 쓴다 (팀 선택으로 넘기지 않는다)
		get_viewport().set_input_as_handled()
		choose(k - KEY_1)
	elif k in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		enter()
