class_name SidePanelStyle
extends RefCounted
## 오른쪽 정보 창 모양 설정. data/ui/side_panel.json 에서 읽는다 (2026-11-27).

const PATH := "res://data/ui/side_panel.json"

static var _cached: SidePanelStyle

var panel_w := 430.0
var portrait_px := 148.0
var button_size := Vector2(96, 62)
var icon_px := 26.0
var blink_hz := 1.4
var accent := Color("fde047")
var max_crew_rows := 4
var air_warn := 0.5
var air_danger := 0.25
var heat_warn := 0.35
var heat_danger := 0.7
var flux_show_kw := 0.5
var bar_full_bar := 300.0
var officer_label := "팀장"
var roles: Dictionary = {}
var driver_label := "운전원"

## 판·글자 색 (한 곳에서 정해 창 전체가 같은 색을 쓴다)
const BG := Color(0.035, 0.06, 0.1, 0.9)
const LINE := Color(0.55, 0.65, 0.8, 0.22)
const TEXT := Color("e2e8f0")
const DIM := Color("94a3b8")
const MUTED := Color("64748b")
const OK := Color("4ade80")
const WARN := Color("facc15")
const DANGER := Color("f87171")
const WATER := Color("60a5fa")
const HEAT := Color("fb923c")
const CHIP_BG := Color(0.12, 0.17, 0.25, 0.95)
const TRACK := Color(0.14, 0.19, 0.27, 1.0)


static func get_default() -> SidePanelStyle:
	if _cached == null:
		_cached = SidePanelStyle.new()
		_cached._load(PATH)
	return _cached


func _load(path: String) -> void:
	var data: Variant = JsonData.load_file(path)
	if not data is Dictionary:
		push_error("오른쪽 정보 창 설정을 읽지 못함: %s" % path)
		return
	panel_w = float(_value(data, "panel_w", panel_w))
	portrait_px = float(_value(data, "portrait_px", portrait_px))
	var bs: Array = _value(data, "button_size", [button_size.x, button_size.y])
	button_size = Vector2(float(bs[0]), float(bs[1]))
	icon_px = float(_value(data, "icon_px", icon_px))
	blink_hz = float(_value(data, "blink_hz", blink_hz))
	accent = Color(str(_value(data, "accent", accent.to_html(false))))
	max_crew_rows = int(_value(data, "max_crew_rows", max_crew_rows))
	air_warn = float(_value(data, "air_warn", air_warn))
	air_danger = float(_value(data, "air_danger", air_danger))
	heat_warn = float(_value(data, "heat_warn", heat_warn))
	heat_danger = float(_value(data, "heat_danger", heat_danger))
	flux_show_kw = float(_value(data, "flux_show_kw", flux_show_kw))
	bar_full_bar = float(_value(data, "bar_full_bar", bar_full_bar))
	officer_label = str(_value(data, "officer_label", officer_label))
	roles = _value(data, "roles", roles)
	driver_label = str(_value(data, "driver_label", driver_label))


## 출동대 종류별 임무 이름 {lead, other}
func role_names(squad_type: String) -> Dictionary:
	return roles.get(squad_type, roles.get("default", {"lead": "대원", "other": "대원"}))


func air_color(ratio: float) -> Color:
	if ratio <= air_danger:
		return DANGER
	return WARN if ratio <= air_warn else OK


func heat_color(ratio: float) -> Color:
	if ratio >= heat_danger:
		return DANGER
	return HEAT if ratio >= heat_warn else Color("fdba74")


static func _value(data: Dictionary, key: String, fallback: Variant) -> Variant:
	var entry: Variant = data.get(key)
	if entry is Dictionary and (entry as Dictionary).has("value"):
		return entry["value"]
	return fallback
