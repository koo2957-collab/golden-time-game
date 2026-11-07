class_name DebriefUi
extends Control
## 디브리핑 화면 (SOP 113-2.1). 활동이 끝나면 전체 화면으로 띄운다.
##   머리: 등급·점수·축별 점수 (대원 안전·인명구조 기준에 못 미치면 등급 상한, 108-1.2·214-2.1)
##   ① 무엇을 계획했나  ② 실제로 무슨 일이 (타임라인·숨은 정보 공개)  ③ 왜 일어났나 (판단 → 결과 → 조항)
##   ④ 다음에는 (고칠 점·잘한 점, 113-3.1 칭찬 필수)
## 아래: 다시 시작 / 시나리오 선택 / 타임라인의 한 시점부터 다시 하기

signal restart_requested
signal menu_requested
## tick 시점(그 사건 직전)부터 다시 하기
signal replay_requested(tick: int)

const BG := Color(0.05, 0.07, 0.1, 0.97)
const TEXT := "e2e8f0"
const DIM := "94a3b8"
const GOOD := "86efac"
const BAD := "fca5a5"
const WARN := "fde68a"
const QUOTE := "a5b4fc"

var report: Dictionary = {}
var _tabs: TabContainer
var _moments: OptionButton


func show_report(p_report: Dictionary, saved_path: String) -> void:
	report = p_report
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for c in get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	box.add_child(_rich(_header(saved_path), 18, false))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_add_tab("① 무엇을 계획했나", _plan_text())
	_add_tab("② 실제로 무슨 일이", _actual_text())
	_add_tab("③ 왜 일어났나", _why_text())
	_add_tab("④ 다음에는", _next_text())
	_tabs.current_tab = 3
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_moments = OptionButton.new()
	_moments.focus_mode = Control.FOCUS_NONE
	_moments.custom_minimum_size = Vector2(620, 44)
	_moments.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ticks: Array = report.get("timeline_ticks", [])
	for i in ticks.size():
		if int(ticks[i]) > 0:
			_moments.add_item("%s 직전" % report.timeline[i])
			_moments.set_item_metadata(_moments.item_count - 1, int(ticks[i]))
	row.add_child(_moments)
	var replay := _button("이 시점부터 다시 하기", func() -> void:
		if _moments.selected >= 0:
			replay_requested.emit(int(_moments.get_item_metadata(_moments.selected))))
	var can_replay: bool = report.get("replayable", true) and _moments.item_count > 0
	replay.disabled = not can_replay
	_moments.disabled = not can_replay
	if not report.get("replayable", true):
		replay.tooltip_text = "개발용 기능(즉시 발화·정보 안개 끄기)을 쓴 판은 다시 하기를 할 수 없습니다."
	row.add_child(replay)
	row.add_child(_button("다시 시작 (F5)", func() -> void: restart_requested.emit()))
	row.add_child(_button("시나리오 선택", func() -> void: menu_requested.emit()))
	box.add_child(row)
	visible = true


func select_tab(i: int) -> void:
	_tabs.current_tab = i


func tab_count() -> int:
	return _tabs.get_tab_count()


# --- 내용 ---

func _header(saved_path: String) -> String:
	var r := report
	var grade_color := GOOD if r.grade in ["S", "A"] else (WARN if r.grade in ["B", "C"] else BAD)
	var lines: PackedStringArray = []
	lines.append("[font_size=28][color=#%s]디브리핑[/color][/font_size]  [color=#%s]%s · %s 모드 · 난이도 %s · %s · 활동 시간 %s[/color]" % [
		WARN, DIM, r.scenario_title, r.get("mode", "평가"), r.get("difficulty", ""), r.end_reason, _clock(r.end_time_s)])
	var cap := "  [color=#%s](등급 상한: %s)[/color]" % [BAD, "; ".join(PackedStringArray(r.cap_reasons))] if r.capped else ""
	lines.append("[font_size=36][color=#%s]%s[/color][/font_size]  [font_size=22]%.1f점[/font_size]%s" % [grade_color, r.grade, r.points, cap])
	var axes: PackedStringArray = []
	for a: Dictionary in r.axes:
		axes.append("%s %s" % [a.name, "%d%%" % roundi(a.score * 100.0) if a.applicable else "해당 없음"])
	lines.append("[color=#%s]%s   (가중치: 전술 우선순위 순, SOP 106-1.1②)[/color]" % [TEXT, "  ·  ".join(axes)])
	lines.append("[color=#%s]판정 근거: %s · 결과는 지도·개선 용도로만 씁니다 (SOP 113-3.1.6)[/color]" % [DIM, r.get("basis", "")])
	if saved_path != "":
		lines.append("[color=#%s]결과 저장: %s[/color]" % [DIM, ProjectSettings.globalize_path(saved_path)])
	return "\n".join(lines)


func _plan_text() -> String:
	var p: Dictionary = report.plan
	var lines: PackedStringArray = ["[b]학습 목표[/b]"]
	for o in p.objectives:
		lines.append("  • %s" % o)
	lines.append("[color=#%s]바람직한 종결 상태: %s[/color]" % [DIM, p.end_state])
	lines.append("")
	lines.append("[b]지휘권 선언[/b]  %s" % p.declared)
	if not p.report_items.is_empty():
		lines.append("[b]최초 상황보고 (SOP 101-2.1)[/b]")
		for it: Dictionary in p.report_items:
			var mark := ""
			if it.scored:
				mark = "[color=#%s] ✓[/color]" % GOOD if it.correct else "[color=#%s] ✗ (확인 가능했던 사실: %s)[/color]" % [BAD, it.truth]
			lines.append("  %s %s: %s%s" % [_circled(int(it.no)), it.name, it.answer, mark])
	lines.append("[b]전략 변경[/b]  %s" % (", ".join(PackedStringArray(p.strategy_changes)) if not p.strategy_changes.is_empty() else "없음"))
	lines.append("[b]단위대[/b]  %s" % (", ".join(PackedStringArray(p.organization)) if not p.organization.is_empty() else "지정하지 않음"))
	lines.append("[b]지원 요청[/b]  %s" % p.support)
	return "\n".join(lines)


func _actual_text() -> String:
	var h: Dictionary = report.hidden
	var lines: PackedStringArray = ["[b]숨은 정보 공개[/b]"]
	lines.append("[color=#%s]구조대상자[/color]" % WARN)
	for v in h.victims:
		lines.append("  • %s" % v)
	lines.append("[color=#%s]관계인 진술의 진위[/color]" % WARN)
	for s in h.statements:
		var color := BAD if str(s).contains("— 틀림") else TEXT
		lines.append("  • [color=#%s]%s[/color]" % [color, s])
	if not h.faces.is_empty():
		lines.append("[color=#%s]면별 정보[/color]" % WARN)
		for f in h.faces:
			lines.append("  • %s" % f)
	lines.append("[color=#%s]불이 난 구획[/color]" % WARN)
	for c in h.fire_rooms:
		lines.append("  • %s" % c)
	lines.append("")
	lines.append("[b]타임라인[/b]")
	for t in report.timeline:
		lines.append("  %s" % t)
	return "\n".join(lines)


func _why_text() -> String:
	var lines: PackedStringArray = ["[color=#%s]'누가'가 아니라 '무엇'이 결과를 만들었는지 봅니다 (SOP 113-2.1③). 판단 → 결과 → SOP 조항 → 왜(소방전술). 기준값 중 '추정'은 현장 검수 전 값입니다.[/color]" % DIM, ""]
	var decisions: Array = report.get("decisions", [])
	if not decisions.is_empty():
		lines.append("[b]주요 의사결정과 그때 알던 정보 (SOP 111-2.2)[/b]")
		for d: Dictionary in decisions:
			lines.append("  %s  %s" % [d.time, d.decision])
			lines.append("        [color=#%s]%s[/color]" % [DIM, d.context])
		lines.append("")
	for a: Dictionary in report.axes:
		lines.append("[b]%s[/b] %s" % [a.name, "%d%%" % roundi(a.score * 100.0) if a.applicable else "(해당 없음)"])
		for r: Dictionary in report.rules:
			if r.axis != a.id:
				continue
			if not r.applicable:
				lines.append("  [color=#%s]— %s (SOP %s): 해당 없음[/color]" % [DIM, r.title, r.sop])
				continue
			var color := GOOD if r.score >= Evaluator.STRENGTH_MIN else (BAD if r.score < Evaluator.WEAKNESS_MAX else WARN)
			var crit := " [color=#%s][등급 상한 %s][/color]" % [BAD, r.cap.grade] if r.violated else ""
			lines.append("  [color=#%s]%3d%%[/color]  %s (SOP %s, %s)%s" % [color, roundi(r.score * 100.0), r.title, r.sop, r.source, crit])
			lines.append("        %s" % r.detail)
			lines.append("        [color=#%s]SOP %s「%s」[/color]" % [QUOTE, r.sop, r.text])
			if str(r.get("tactic_text", "")) != "":
				lines.append("        [color=#%s]왜? %s — %s[/color]" % [DIM, r.tactic, r.tactic_text])
		lines.append("")
	return "\n".join(lines)


func _next_text() -> String:
	var lines: PackedStringArray = ["[b][color=#%s]잘한 점 — 계속 유지[/color][/b]" % GOOD]
	for s: Dictionary in report.strengths:
		lines.append("  • %s (SOP %s) — %s" % [s.title, s.sop, s.detail])
	lines.append("")
	lines.append("[b][color=#%s]고칠 점 — 다음에는[/color][/b]" % WARN)
	if report.weaknesses.is_empty():
		lines.append("  • 기준에 크게 못 미친 항목이 없습니다.")
	for w: Dictionary in report.weaknesses:
		lines.append("  • %s (SOP %s)" % [w.title, w.sop])
		lines.append("      결과: %s" % w.detail)
		lines.append("      [color=#%s]→ %s[/color]" % [GOOD, w.advice])
	return "\n".join(lines)


# --- 도움 ---

## 고를 수 있는 다시 하기 시점 수 (조작 점검용)
func moment_count() -> int:
	return _moments.item_count


func moment_tick(i: int) -> int:
	return int(_moments.get_item_metadata(i))


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(200, 44)
	b.pressed.connect(on_press)
	return b


func _add_tab(title: String, bbcode: String) -> void:
	var label := _rich(bbcode, 17, true)
	label.name = title
	_tabs.add_child(label)


func _rich(bbcode: String, size: int, scroll: bool) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.text = "[color=#%s]%s[/color]" % [TEXT, bbcode]
	l.add_theme_font_size_override("normal_font_size", size)
	l.add_theme_font_size_override("bold_font_size", size + 1)
	l.fit_content = not scroll
	l.scroll_active = scroll
	l.selection_enabled = true
	if scroll:
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return l


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [floori(s / 60.0), s % 60]


static func _circled(n: int) -> String:
	var marks := ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨"]
	return marks[n - 1] if n >= 1 and n <= marks.size() else str(n)
