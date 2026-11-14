class_name BoardStyle
extends RefCounted
## 전술상황판(화이트보드) 모양·기호 설정. data/ui/board_style.json에서 읽는다 (2026-11-14).

const PATH := "res://data/ui/board_style.json"

static var _cached: BoardStyle

var panel_margin_x := 0.03
var panel_margin_top := 0.085
var panel_margin_bottom := 0.095
var column_px := 330.0
var frame_px := 5.0
var legend_row_px := 20.0
var stale_s := 60.0
var stale_alpha := 0.4
var wall_ratio := 0.32
var wall_min_px := 2.0
var hatch_step_px := 9.0
var symbol_px := 10.0
var label_font := 12
var room_font := 11
var face_font := 15
var magnet_font := 12
var magnet_h_px := 20.0
var hose_px := 2.5
## 색 이름 → Color (data의 colors)
var colors: Dictionary = {}
## 차종 → 자석에 쓰는 짧은 이름
var vehicle_labels: Dictionary = {}


## 한 번 읽어 같이 쓴다
static func get_default() -> BoardStyle:
	if _cached == null:
		_cached = from_file(PATH)
	return _cached


static func from_file(path: String) -> BoardStyle:
	var s := BoardStyle.new()
	var data: Variant = JsonData.load_file(path)
	if data is Dictionary:
		s.apply(data)
	return s


func apply(data: Dictionary) -> void:
	panel_margin_x = float(_value(data, "panel_margin_x", panel_margin_x))
	panel_margin_top = float(_value(data, "panel_margin_top", panel_margin_top))
	panel_margin_bottom = float(_value(data, "panel_margin_bottom", panel_margin_bottom))
	column_px = float(_value(data, "column_px", column_px))
	frame_px = float(_value(data, "frame_px", frame_px))
	legend_row_px = float(_value(data, "legend_row_px", legend_row_px))
	stale_s = float(_value(data, "stale_s", stale_s))
	stale_alpha = float(_value(data, "stale_alpha", stale_alpha))
	wall_ratio = float(_value(data, "wall_ratio", wall_ratio))
	wall_min_px = float(_value(data, "wall_min_px", wall_min_px))
	hatch_step_px = float(_value(data, "hatch_step_px", hatch_step_px))
	symbol_px = float(_value(data, "symbol_px", symbol_px))
	label_font = int(_value(data, "label_font", label_font))
	room_font = int(_value(data, "room_font", room_font))
	face_font = int(_value(data, "face_font", face_font))
	magnet_font = int(_value(data, "magnet_font", magnet_font))
	magnet_h_px = float(_value(data, "magnet_h_px", magnet_h_px))
	hose_px = float(_value(data, "hose_px", hose_px))
	var c: Dictionary = data.get("colors", {})
	for key: String in c:
		if key in ["source", "note"]:
			continue
		colors[key] = Color(str(c[key]))
	var v: Dictionary = data.get("vehicle_labels", {})
	for key: String in v:
		if key in ["source", "note"]:
			continue
		vehicle_labels[key] = str(v[key])


## 색 (없으면 먹색) — alpha를 주면 그 불투명도로
func color(key: String, alpha := 1.0) -> Color:
	var c: Color = colors.get(key, Color("1f2933"))
	return Color(c, c.a * alpha)


## 차량 자석에 쓰는 이름
func vehicle_label(type: String) -> String:
	return str(vehicle_labels.get(type, type))


static func _value(data: Dictionary, key: String, fallback: Variant) -> Variant:
	var entry: Variant = data.get(key)
	if entry is Dictionary and (entry as Dictionary).has("value"):
		return entry["value"]
	return fallback
