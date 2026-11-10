class_name RadioLogPanel
extends PanelContainer
## 오른쪽 무전 기록 패널 (기획안 9-2, P10-1): 실시간 무전만. 상황 요약·팀 카드·확인 필요는 전술상황판으로 옮겼다.
##   - 긴급 고정줄(맨 위 최대 2줄): 긴급탈출 · 인원 점검 무응답 · 잔압 경보 · 물탱크 고갈. 해결되면 사라지고, 접어도 남는다
##   - 무전 목록: 최신이 맨 위, 최대 MAX_ROWS건. 현장 시각·발신자·내용, 우선순위 색(대원 안전 빨강·구조대상자 주황·일반 흰색)
##   - 답한 질문 카드는 "○○ 질문 → 내 답" 한 줄. 항목을 누르면 그 대원·장소로 화면 이동
##   - 필터: 전체 / 긴급 / 내 지시. 아래를 보는 중에 새 무전이 오면 "새 무전 N건 ↑" 배지만

signal jump(crew_id: int)

const WIDTH := 430.0
const MAX_ROWS := 200
const PINNED_MAX := 2
const COLORS := {Radio.Priority.SAFETY: Color("f87171"), Radio.Priority.VICTIM: Color("fb923c")}
const NORMAL := Color("e2e8f0")
const MINE := Color("93c5fd")
const FILTERS: Array[String] = ["전체", "긴급", "내 지시"]

var sim: SimWorld
## 쌓인 항목 [{tick, text, color, urgent, mine, crew}] (오래된 것부터)
var entries: Array[Dictionary] = []
var filter := "전체"
var folded := false
var unseen := 0

var _pinned: VBoxContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _badge: Button
var _tabs: HBoxContainer
var _fold: Button
var _seen_radio: Dictionary = {}  # Radio 인스턴스 id → history에서 읽은 수
var _seen_cards := 0
var _refresh := 0.0


func setup(p_sim: SimWorld) -> void:
	sim = p_sim
	# 빈 곳을 누르면 지도로 (예전 상황판처럼). 버튼·항목만 받는다
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.12, 0.72)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "무전 기록"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("fdba74"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_fold = _small("▶ 접기", toggle_fold)
	head.add_child(_fold)
	box.add_child(head)
	_pinned = VBoxContainer.new()
	box.add_child(_pinned)
	_tabs = HBoxContainer.new()
	for f in FILTERS:
		var b := _small(f, set_filter.bind(f))
		b.toggle_mode = true
		b.button_pressed = f == filter
		_tabs.add_child(b)
	box.add_child(_tabs)
	_badge = _small("", func() -> void:
		_scroll.scroll_vertical = 0
		unseen = 0
		_badge.visible = false)
	_badge.add_theme_color_override("font_color", Color("fde68a"))
	_badge.visible = false
	box.add_child(_badge)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(WIDTH - 16, 360)
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	box.add_child(_scroll)
	collect()
	_rebuild()


func _process(delta: float) -> void:
	if sim == null:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.25
	var added := collect()
	refresh_pinned()
	if added > 0:
		# 맨 위를 보고 있으면 바로 보여 주고, 아래를 보는 중이면 배지만
		if _scroll.scroll_vertical > 0:
			unseen += added
			_badge.text = "새 무전 %d건 ↑" % unseen
			_badge.visible = not folded
		_rebuild()


## 새 무전·답한 카드를 항목으로 모은다. 더한 수
func collect() -> int:
	var added := 0
	var radios: Array[Radio] = [sim.command.radio]
	for d in sim.command.org.divisions:
		radios.append(d.radio)
	var fresh: Array[Dictionary] = []
	for r in radios:
		var key := r.get_instance_id()
		var start: int = _seen_radio.get(key, 0)
		for i in range(start, r.history.size()):
			var m := r.history[i]
			var who := sim.knowledge._crew_named(m.sender) if sim.knowledge else null
			fresh.append({"tick": m.end_tick, "text": "%s%s → %s: %s" % ["" if r == sim.command.radio else "[%s] " % r.channel, m.sender, m.receiver, m.body],
				"color": MINE if m.mine else COLORS.get(m.priority, NORMAL), "urgent": m.priority <= Radio.Priority.VICTIM, "mine": m.mine,
				"crew": who.id if who else -1})
		_seen_radio[key] = r.history.size()
	var answers := sim.events.of_type("card_answered")
	for i in range(_seen_cards, answers.size()):
		var e: Dictionary = answers[i]
		var who := sim.knowledge._crew_named(str(e.crew)) if sim.knowledge else null
		fresh.append({"tick": int(e.tick), "text": "%s 질문 → %s" % [e.crew, e.option], "color": MINE, "urgent": false, "mine": true,
			"crew": who.id if who else -1})
	_seen_cards = answers.size()
	fresh.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.tick) < int(b.tick))
	for f in fresh:
		entries.append(f)
		added += 1
	while entries.size() > MAX_ROWS:
		entries.pop_front()
	return added


## 지금 보이는 항목 (필터 적용, 최신이 앞)
func visible_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(entries.size() - 1, -1, -1):
		var e := entries[i]
		if filter == "긴급" and not bool(e.urgent):
			continue
		if filter == "내 지시" and not bool(e.mine):
			continue
		out.append(e)
	return out


## 긴급 고정줄 (원인이 남아 있는 동안만, 중요한 순서로 최대 2줄)
func pinned_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	var cmd := sim.command
	if cmd.safety.emergency():
		out.append("⚠ 긴급탈출 상황 — 무선 침묵, RIT 투입 판단")
	var silent: PackedStringArray = []
	for id in cmd.safety.par_no_response:
		silent.append(_crew_name(id))
	if not silent.is_empty():
		out.append("⚠ 인원 점검 무응답: %s" % ", ".join(silent))
	var alarm: PackedStringArray = []
	for c in sim.units.crews:
		if cmd.interior.crew_inside(c.id) and c.members().any(func(ff: Firefighter) -> bool: return ff.air_alarm_logged and not ff.incapacitated):
			alarm.append(_crew_name(c.id))
	if not alarm.is_empty():
		out.append("⚠ 잔압 경보: %s" % ", ".join(alarm))
	var dry: PackedStringArray = []
	for v in sim.units.vehicles:
		if v.is_pump() and not v.away and v.tank_l <= 0.0 and v.hydrant < 0 and sim.water.fdc_vehicle != v.id:
			if sim.water.hoses.any(func(h: HoseLine) -> bool: return h.vehicle_id == v.id):
				dry.append(v.display_name(sim.units.squads[v.squad_id].name))
	if not dry.is_empty():
		out.append("⚠ 물탱크 고갈: %s" % ", ".join(dry))
	return out.slice(0, PINNED_MAX)


func refresh_pinned() -> void:
	var lines := pinned_lines()
	var labels := _pinned.get_children()
	for i in maxi(lines.size(), labels.size()):
		if i >= lines.size():
			labels[i].queue_free()
			continue
		var l: Label
		if i < labels.size():
			l = labels[i]
		else:
			l = Label.new()
			l.add_theme_font_size_override("font_size", 15)
			l.add_theme_color_override("font_color", Color("fecaca"))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(WIDTH - 16, 0)
			var bg := StyleBoxFlat.new()
			bg.bg_color = Color(0.5, 0.05, 0.05, 0.85)
			bg.set_content_margin_all(4)
			l.add_theme_stylebox_override("normal", bg)
			_pinned.add_child(l)
		l.text = lines[i]


func set_filter(f: String) -> void:
	filter = f
	for b: Button in _tabs.get_children():
		b.button_pressed = b.text == f
	_rebuild()


## 접기: 고정줄만 남긴다
func toggle_fold() -> void:
	folded = not folded
	_tabs.visible = not folded
	_scroll.visible = not folded
	_badge.visible = not folded and unseen > 0
	_fold.text = "◀ 펴기" if folded else "▶ 접기"
	reset_size()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	for e in visible_entries():
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(WIDTH - 28, 0)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", e.color)
		var t := int(int(e.tick) * SimClock.TICK_DT)
		b.text = "%02d:%02d  %s" % [floori(t / 60.0), t % 60, e.text]
		var crew := int(e.crew)
		if crew >= 0:
			b.pressed.connect(func() -> void: jump.emit(crew))
		_list.add_child(b)
	if _scroll.scroll_vertical == 0:
		unseen = 0
		_badge.visible = false


func _crew_name(id: int) -> String:
	var c := sim.units.get_crew(id)
	return "%s %d조" % [sim.units.squads[c.squad_id].name, c.number] if c else ""


func _small(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b
