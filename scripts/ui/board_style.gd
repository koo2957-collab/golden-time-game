class_name BoardStyle
extends RefCounted
## 전술상황판(화이트보드) 모양·기호 설정. data/ui/board_style.json에서 읽는다 (2026-11-14).

const PATH := "res://data/ui/board_style.json"

static var _cached: BoardStyle

var board_screen_ratio := 0.85
var board_aspect := 1.7778
var map_ratio := 0.6
var info_rows: Array = [0.3, 0.34, 0.36]
var frame_px := 11.0
var corner_px := 24.0
var tray_px := 13.0
var cell_line_px := 2
var cell_pad_px := 8
var legend_row_px := 22.0
var font_path := "res://art/fonts/Gaegu-Regular.ttf"
var font_bold_path := "res://art/fonts/Gaegu-Bold.ttf"
var title_font := 28
var head_font := 20
var body_font := 17
var stale_s := 60.0
var stale_alpha := 0.4
var wall_ratio := 0.32
var wall_min_px := 2.0
var hatch_step_px := 9.0
var symbol_px := 10.0
var label_font := 15
var room_font := 15
var face_font := 19
var magnet_font := 15
var magnet_h_px := 22.0
var hose_px := 2.5
## 색 이름 → Color (data의 colors)
var colors: Dictionary = {}
## 차종 → 자석에 쓰는 짧은 이름
var vehicle_labels: Dictionary = {}
var _font: Font
var _font_bold: Font


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
	board_screen_ratio = float(_value(data, "board_screen_ratio", board_screen_ratio))
	board_aspect = float(_value(data, "board_aspect", board_aspect))
	map_ratio = float(_value(data, "map_ratio", map_ratio))
	info_rows = _value(data, "info_rows", info_rows)
	frame_px = float(_value(data, "frame_px", frame_px))
	corner_px = float(_value(data, "corner_px", corner_px))
	tray_px = float(_value(data, "tray_px", tray_px))
	cell_line_px = int(_value(data, "cell_line_px", cell_line_px))
	cell_pad_px = int(_value(data, "cell_pad_px", cell_pad_px))
	font_path = str(_value(data, "font", font_path))
	font_bold_path = str(_value(data, "font_bold", font_bold_path))
	title_font = int(_value(data, "title_font", title_font))
	head_font = int(_value(data, "head_font", head_font))
	body_font = int(_value(data, "body_font", body_font))
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


## 판 위 글씨 (보드마커 손글씨). 글꼴 파일이 없으면 기본 글꼴
func marker_font() -> Font:
	if _font == null:
		_font = _load_font(font_path)
	return _font


## 굵은 마커 글씨 (제목·자석)
func marker_bold() -> Font:
	if _font_bold == null:
		_font_bold = _load_font(font_bold_path)
	return _font_bold


static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f: Variant = load(path)
		if f is Font:
			return f
	return ThemeDB.fallback_font


## 차량 자석에 쓰는 이름
func vehicle_label(type: String) -> String:
	return str(vehicle_labels.get(type, type))


static func _value(data: Dictionary, key: String, fallback: Variant) -> Variant:
	var entry: Variant = data.get(key)
	if entry is Dictionary and (entry as Dictionary).has("value"):
		return entry["value"]
	return fallback
