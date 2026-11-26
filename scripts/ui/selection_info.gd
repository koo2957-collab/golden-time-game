class_name SelectionInfo
extends Control
## 오른쪽 정보 창의 위쪽 (2026-11-27 사용자: 글이 너무 많다 → 아이콘·막대, 이름 대신 대원1·2·3과 임무, 초상 크게).
## 한 Control 이 직접 그린다 (노드를 매번 만들지 않아 가볍다). 자세한 숫자는 마우스를 올리면 툴팁으로.
## 모델(Dictionary)은 SelectionModel 이 시뮬레이션에서 만든다:
##   title, title_tip, portrait(Texture2D)
##   chips: [{icon, text, color, tip}]                — 위치·상태 칩 (초상 오른쪽)
##   bars:  [{icon, label, value 0..1, text, color, tip}] — 수관 길이·작업 진행 막대
##   warns: [{icon, text, tip}]                       — 빨간 경고
##   groups: [{head, members: [{num, role, air(-1=없음), need, heat, down, icons: [{icon, color, tip}], tip}]}]
##   compact: [{name, air, state, tip}]               — 조가 많을 때 조마다 한 줄

const PAD := 2.0
const CHIP_H := 22.0
const BAR_H := 20.0
const ROW_H := 24.0
const GAP := 8.0

var model: Dictionary = {}
var style: SidePanelStyle
var _tips: Array = []  # [Rect2, String]


func _init() -> void:
	style = SidePanelStyle.get_default()
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(style.panel_w - 20.0, style.portrait_px)


func set_model(m: Dictionary) -> void:
	model = m
	var h := _paint(false)
	if absf(custom_minimum_size.y - h) > 0.5:
		custom_minimum_size.y = h
	queue_redraw()


func _draw() -> void:
	_paint(true)


func _get_tooltip(at: Vector2) -> String:
	for t: Array in _tips:
		if (t[0] as Rect2).has_point(at):
			return str(t[1])
	return ""


func _tip(r: Rect2, text: String) -> void:
	if text != "":
		_tips.append([r, text])


## 그리기와 높이 재기를 한 번에 (paint=false 면 높이만). 돌려주는 값 = 전체 높이
func _paint(paint: bool) -> float:
	_tips.clear()
	var font := get_theme_default_font()
	var w := maxf(size.x, custom_minimum_size.x)
	var pp := style.portrait_px
	# --- 초상 ---
	var tex: Texture2D = model.get("portrait")
	var pr := Rect2(Vector2.ZERO, Vector2(pp, pp))
	if paint:
		draw_rect(pr, Color(0.07, 0.1, 0.16, 1.0))
		if tex != null:
			var ts := tex.get_size()
			var k := maxf(pp / ts.x, pp / ts.y)
			var src_size := Vector2(pp, pp) / k
			draw_texture_rect_region(tex, pr, Rect2((ts - src_size) * 0.5, src_size))
		draw_rect(pr, Color(style.accent, 0.55), false, 1.5)
	_tip(pr, str(model.get("title_tip", "")))
	# --- 오른쪽: 제목 · 칩 · 막대 · 경고 ---
	var x0 := pp + 12.0
	var cw := w - x0
	var y := 0.0
	var title := str(model.get("title", ""))
	if paint:
		draw_string(font, Vector2(x0, y + 19.0), title, HORIZONTAL_ALIGNMENT_LEFT, cw, 19, SidePanelStyle.TEXT)
	_tip(Rect2(x0, y, cw, 24.0), str(model.get("title_tip", "")))
	y += 30.0
	# 칩 (줄바꿈)
	var cx := x0
	for chip: Dictionary in model.get("chips", []):
		var t := str(chip.text)
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var cwid := tw + 30.0
		if cx + cwid > w and cx > x0:
			cx = x0
			y += CHIP_H + 4.0
		var r := Rect2(cx, y, minf(cwid, cw), CHIP_H)
		var col: Color = chip.get("color", SidePanelStyle.TEXT)
		if paint:
			var sb := StyleBoxFlat.new()
			sb.bg_color = SidePanelStyle.CHIP_BG
			sb.border_color = Color(col, 0.45)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(int(CHIP_H * 0.5))
			draw_style_box(sb, r)
			CmdIcon.draw(self, str(chip.get("icon", "")), Vector2(cx + 13.0, y + CHIP_H * 0.5), 13.0, col)
			draw_string(font, Vector2(cx + 23.0, y + 15.5), t, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 26.0, 12, col)
		_tip(r, str(chip.get("tip", "")))
		cx += cwid + 5.0
	if not model.get("chips", []).is_empty():
		y += CHIP_H + 8.0
	# 막대 (수관·작업 진행)
	for bar: Dictionary in model.get("bars", []):
		var col: Color = bar.get("color", SidePanelStyle.WATER)
		var label := str(bar.get("label", ""))
		var txt := str(bar.get("text", ""))
		var lw := 64.0
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 4.0
		var bx := x0 + 18.0 + lw
		var bw := maxf(30.0, w - bx - tw - 4.0)
		if paint:
			CmdIcon.draw(self, str(bar.get("icon", "")), Vector2(x0 + 7.0, y + BAR_H * 0.5), 13.0, col)
			draw_string(font, Vector2(x0 + 18.0, y + 14.0), label, HORIZONTAL_ALIGNMENT_LEFT, lw - 2.0, 12, SidePanelStyle.DIM)
			_bar(Rect2(bx, y + 6.0, bw, 8.0), clampf(float(bar.get("value", 0.0)), 0.0, 1.0), col)
			draw_string(font, Vector2(bx + bw + 4.0, y + 14.0), txt, HORIZONTAL_ALIGNMENT_LEFT, tw, 11, SidePanelStyle.TEXT)
		_tip(Rect2(x0, y, cw, BAR_H), str(bar.get("tip", "")))
		y += BAR_H
	# 경고 (빨강)
	for wn: Dictionary in model.get("warns", []):
		if paint:
			CmdIcon.draw(self, str(wn.get("icon", "warn")), Vector2(x0 + 7.0, y + 10.0), 13.0, SidePanelStyle.DANGER)
			draw_string(font, Vector2(x0 + 18.0, y + 14.5), str(wn.text), HORIZONTAL_ALIGNMENT_LEFT, cw - 18.0, 12, SidePanelStyle.DANGER)
		_tip(Rect2(x0, y, cw, BAR_H), str(wn.get("tip", "")))
		y += BAR_H
	y = maxf(y, pp) + GAP
	# --- 대원 줄 ---
	var groups: Array = model.get("groups", [])
	var any_air := false
	for g: Dictionary in groups:
		for m: Dictionary in g.members:
			if float(m.get("air", -1.0)) >= 0.0:
				any_air = true
	var ax := 150.0
	var aw := maxf(60.0, w - ax - 140.0)
	var hx := ax + aw + 10.0
	var hw := 56.0
	var ix := hx + hw + 10.0
	if any_air:
		if paint:
			draw_line(Vector2(0, y - 3.0), Vector2(w, y - 3.0), SidePanelStyle.LINE, 1.0)
			draw_string(font, Vector2(ax, y + 11.0), "공기", HORIZONTAL_ALIGNMENT_LEFT, aw, 11, SidePanelStyle.MUTED)
			draw_string(font, Vector2(hx, y + 11.0), "열", HORIZONTAL_ALIGNMENT_LEFT, hw, 11, SidePanelStyle.MUTED)
		y += 15.0
	for g: Dictionary in groups:
		var head := str(g.get("head", ""))
		if head != "":
			if paint:
				draw_string(font, Vector2(0, y + 14.0), head, HORIZONTAL_ALIGNMENT_LEFT, w, 12, style.accent)
			y += 18.0
		for m: Dictionary in g.members:
			var down: bool = m.get("down", false)
			var num := str(m.get("num", ""))
			var role := str(m.get("role", ""))
			var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			if paint:
				draw_string(font, Vector2(0, y + 16.0), num, HORIZONTAL_ALIGNMENT_LEFT, ax - 4.0, 14, SidePanelStyle.TEXT)
				draw_string(font, Vector2(nw + 6.0, y + 16.0), role, HORIZONTAL_ALIGNMENT_LEFT, maxf(10.0, (ax if float(m.get("air", -1.0)) >= 0.0 else w) - nw - 10.0), 12,
					SidePanelStyle.DANGER if down else SidePanelStyle.DIM)
			_tip(Rect2(0, y, ax - 4.0, ROW_H), str(m.get("tip", "")))
			var air := float(m.get("air", -1.0))
			if air >= 0.0:
				var ar := Rect2(ax, y + 8.0, aw, 8.0)
				if paint:
					_bar(ar, air, style.air_color(air) if not down else SidePanelStyle.MUTED)
					var need := float(m.get("need", 0.0))
					if need > 0.0:
						var nx := ax + aw * clampf(need, 0.0, 1.0)
						draw_line(Vector2(nx, y + 5.0), Vector2(nx, y + 19.0), Color.WHITE, 1.5)
				_tip(Rect2(ax, y, aw, ROW_H), str(m.get("air_tip", "")))
				var heat := float(m.get("heat", 0.0))
				if paint:
					_bar(Rect2(hx, y + 8.0, hw, 8.0), heat, style.heat_color(heat))
				_tip(Rect2(hx, y, hw, ROW_H), str(m.get("heat_tip", "")))
			var icx := ix
			for ic: Dictionary in m.get("icons", []):
				if paint:
					CmdIcon.draw(self, str(ic.icon), Vector2(icx + 8.0, y + 12.0), 15.0, ic.get("color", SidePanelStyle.DIM))
				_tip(Rect2(icx, y, 18.0, ROW_H), str(ic.get("tip", "")))
				icx += 19.0
			y += ROW_H
		y += 4.0
	# --- 조가 많을 때: 조마다 한 줄 ---
	for c: Dictionary in model.get("compact", []):
		var air := float(c.get("air", -1.0))
		if paint:
			draw_string(font, Vector2(0, y + 16.0), str(c.name), HORIZONTAL_ALIGNMENT_LEFT, ax - 4.0, 13, SidePanelStyle.TEXT)
			if air >= 0.0:
				_bar(Rect2(ax, y + 8.0, aw, 8.0), air, style.air_color(air))
			draw_string(font, Vector2(hx, y + 16.0), str(c.get("state", "")), HORIZONTAL_ALIGNMENT_LEFT, w - hx, 12, SidePanelStyle.DIM)
		_tip(Rect2(0, y, w, ROW_H), str(c.get("tip", "")))
		y += ROW_H
	return y + PAD


func _bar(r: Rect2, v: float, col: Color) -> void:
	draw_rect(r, SidePanelStyle.TRACK)
	if v > 0.0:
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(v, 0.0, 1.0), r.size.y)), col)
