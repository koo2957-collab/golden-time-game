class_name ViewParams
extends RefCounted
## 건물 화면(외부 보기·인형집 단면) 설정. data/ui/view_params.json에서 읽는다 (R17).

const PATH := "res://data/ui/view_params.json"

var floor_height_px := 143.0
var visible_floors_below := 2
var visible_floors_above := 2
var above_alpha := 0.25
var pick_w_px := 48.0
var pick_h_px := 64.0
var pick_magnet_px := 30.0
var below_modulate: Array[float] = [0.75, 0.55]
## "cut"(잘린 벽) 또는 "hidden"(숨김)
var front_wall := "glass"
var front_wall_alpha := 0.15
var wall_cap_alpha := 0.75
var inner_wall_m := 2.4
var inner_wall_alpha_bottom := 0.7
var inner_wall_alpha_top := 0.15
var inner_wall_cap_alpha := 0.8
var ghost_inner_wall_m := 1.2
var stack_mode := "stagger"
var partner_alpha := 1.0
var partner_dim := 0.72
var current_gray := 0.85
var fire_hole_px := 160.0
var partner_gray := 1.0
var partner_live_alpha := 0.9
var corner_post_alpha := 0.8
var inner_wall_thick := 0.34
var open_wall_alpha := 0.5
var unit_hole_px := 60.0
var unit_hole_alpha := 0.3
var upper_shadow_alpha := 0.2
var stagger_guide_alpha := 0.45
var stagger_back_ratio := 0.3
var stagger_floor_px := 260.0
var smoke_puff_spacing_m := 1.0
var smoke_max_puffs := 90
var smoke_top_alpha := 0.4
var smoke_front_alpha := 0.85
var smoke_dark_density := 0.45
var smoke_row_m := 0.4
var smoke_max_rows := 6
var smoke_sink_s := 6.0
var smoke_style := "curtain"
var smoke_max_opacity := 0.75
var smoke_opacity_k := 1.2
var smoke_curtain_low := 0.15
var smoke_sheet_flow_mps := 0.06
var smoke_plume_alpha := 0.55
var smoke_spill_alpha := 0.75
var smoke_outline_opacity := 0.35
var wall_fade_px := 80.0
var wall_fade_alpha := 0.15
var ghost_line_alpha := 0.2
var ghost_body_alpha := 0.25
var adjacent_alpha := 0.1
var wall_cut_m := 0.2
var slab_m := 0.3
var transition_s := 0.3
var transition_rise_px := 30.0
var zoom_switch := true
var zoom_enter_interior := 1.3
var zoom_exit_exterior := 0.6


static func load_default() -> ViewParams:
	return from_file(PATH)


static func from_file(path: String) -> ViewParams:
	var p := ViewParams.new()
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("화면 설정을 읽지 못했습니다: %s" % path)
		return p
	p.apply(data)
	return p


func apply(data: Dictionary) -> void:
	floor_height_px = float(_value(data, "floor_height_px", floor_height_px))
	visible_floors_below = int(_value(data, "visible_floors_below", visible_floors_below))
	visible_floors_above = int(_value(data, "visible_floors_above", visible_floors_above))
	above_alpha = float(_value(data, "above_alpha", above_alpha))
	pick_w_px = float(_value(data, "pick_w_px", pick_w_px))
	pick_h_px = float(_value(data, "pick_h_px", pick_h_px))
	pick_magnet_px = float(_value(data, "pick_magnet_px", pick_magnet_px))
	# 저사양 모드: 함께 쌓는 층을 하나로 (효과 축소, P14)
	if DisplaySettings.low_spec:
		visible_floors_below = mini(visible_floors_below, 1)
		visible_floors_above = mini(visible_floors_above, 1)
	below_modulate.clear()
	for m: Variant in _value(data, "below_modulate", [0.75, 0.55]):
		below_modulate.append(float(m))
	front_wall = str(_value(data, "front_wall", front_wall))
	front_wall_alpha = float(_value(data, "front_wall_alpha", front_wall_alpha))
	wall_cap_alpha = float(_value(data, "wall_cap_alpha", wall_cap_alpha))
	inner_wall_m = float(_value(data, "inner_wall_m", inner_wall_m))
	inner_wall_alpha_bottom = float(_value(data, "inner_wall_alpha_bottom", inner_wall_alpha_bottom))
	inner_wall_alpha_top = float(_value(data, "inner_wall_alpha_top", inner_wall_alpha_top))
	inner_wall_cap_alpha = float(_value(data, "inner_wall_cap_alpha", inner_wall_cap_alpha))
	ghost_inner_wall_m = float(_value(data, "ghost_inner_wall_m", ghost_inner_wall_m))
	stack_mode = str(_value(data, "stack_mode", stack_mode))
	partner_alpha = float(_value(data, "partner_alpha", partner_alpha))
	partner_dim = float(_value(data, "partner_dim", partner_dim))
	current_gray = float(_value(data, "current_gray", current_gray))
	fire_hole_px = float(_value(data, "fire_hole_px", fire_hole_px))
	partner_gray = float(_value(data, "partner_gray", partner_gray))
	partner_live_alpha = float(_value(data, "partner_live_alpha", partner_live_alpha))
	corner_post_alpha = float(_value(data, "corner_post_alpha", corner_post_alpha))
	inner_wall_thick = float(_value(data, "inner_wall_thick", inner_wall_thick))
	open_wall_alpha = float(_value(data, "open_wall_alpha", open_wall_alpha))
	unit_hole_px = float(_value(data, "unit_hole_px", unit_hole_px))
	unit_hole_alpha = float(_value(data, "unit_hole_alpha", unit_hole_alpha))
	upper_shadow_alpha = float(_value(data, "upper_shadow_alpha", upper_shadow_alpha))
	stagger_guide_alpha = float(_value(data, "stagger_guide_alpha", stagger_guide_alpha))
	stagger_back_ratio = float(_value(data, "stagger_back_ratio", stagger_back_ratio))
	stagger_floor_px = float(_value(data, "stagger_floor_px", stagger_floor_px))
	smoke_puff_spacing_m = float(_value(data, "smoke_puff_spacing_m", smoke_puff_spacing_m))
	smoke_max_puffs = int(_value(data, "smoke_max_puffs", smoke_max_puffs))
	smoke_top_alpha = float(_value(data, "smoke_top_alpha", smoke_top_alpha))
	smoke_front_alpha = float(_value(data, "smoke_front_alpha", smoke_front_alpha))
	smoke_dark_density = float(_value(data, "smoke_dark_density", smoke_dark_density))
	smoke_row_m = float(_value(data, "smoke_row_m", smoke_row_m))
	smoke_max_rows = int(_value(data, "smoke_max_rows", smoke_max_rows))
	smoke_sink_s = float(_value(data, "smoke_sink_s", smoke_sink_s))
	smoke_style = str(_value(data, "smoke_style", smoke_style))
	smoke_max_opacity = float(_value(data, "smoke_max_opacity", smoke_max_opacity))
	smoke_opacity_k = float(_value(data, "smoke_opacity_k", smoke_opacity_k))
	smoke_curtain_low = float(_value(data, "smoke_curtain_low", smoke_curtain_low))
	smoke_sheet_flow_mps = float(_value(data, "smoke_sheet_flow_mps", smoke_sheet_flow_mps))
	smoke_plume_alpha = float(_value(data, "smoke_plume_alpha", smoke_plume_alpha))
	smoke_spill_alpha = float(_value(data, "smoke_spill_alpha", smoke_spill_alpha))
	smoke_outline_opacity = float(_value(data, "smoke_outline_opacity", smoke_outline_opacity))
	wall_fade_px = float(_value(data, "wall_fade_px", wall_fade_px))
	wall_fade_alpha = float(_value(data, "wall_fade_alpha", wall_fade_alpha))
	adjacent_alpha = float(_value(data, "adjacent_alpha", adjacent_alpha))
	ghost_line_alpha = float(_value(data, "ghost_line_alpha", ghost_line_alpha))
	ghost_body_alpha = float(_value(data, "ghost_body_alpha", ghost_body_alpha))
	wall_cut_m = float(_value(data, "wall_cut_m", wall_cut_m))
	slab_m = float(_value(data, "slab_m", slab_m))
	transition_s = float(_value(data, "transition_s", transition_s))
	transition_rise_px = float(_value(data, "transition_rise_px", transition_rise_px))
	zoom_switch = bool(_value(data, "zoom_switch", zoom_switch))
	zoom_enter_interior = float(_value(data, "zoom_enter_interior", zoom_enter_interior))
	zoom_exit_exterior = float(_value(data, "zoom_exit_exterior", zoom_exit_exterior))


static func _value(data: Dictionary, key: String, fallback: Variant) -> Variant:
	var entry: Variant = data.get(key)
	if entry is Dictionary and (entry as Dictionary).has("value"):
		return entry["value"]
	return fallback
