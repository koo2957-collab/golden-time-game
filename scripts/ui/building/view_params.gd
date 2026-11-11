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
var inner_wall_m := 1.2
var inner_wall_top_alpha := 0.2
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
	inner_wall_top_alpha = float(_value(data, "inner_wall_top_alpha", inner_wall_top_alpha))
	adjacent_alpha = float(_value(data, "adjacent_alpha", adjacent_alpha))
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
