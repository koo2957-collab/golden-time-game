class_name TileSkin
extends RefCounted
## 입체 화면 타일 종류표 (R17). data/ui/tile_skin.json에서 종류마다 색(지금)과 그림 영역(그래픽 교체 G1 때)을 읽는다.
## 그리는 코드는 색을 바로 쓰지 않고 종류 이름으로 묻는다 — 나중에 그림으로 바꿀 때 이 표만 고치면 된다.

const PATH := "res://data/ui/tile_skin.json"

var _colors: Dictionary = {}  # 종류 -> Color
var _sprites: Dictionary = {}  # 종류 -> {atlas, rect} (없으면 색으로 그린다)


static func load_default() -> TileSkin:
	var s := TileSkin.new()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("타일 종류표를 읽지 못했습니다: %s" % PATH)
		return s
	for kind: String in data:
		var entry: Variant = data[kind]
		if not entry is Dictionary:
			continue
		if entry.has("color"):
			s._colors[kind] = Color(str(entry.color))
		if entry.get("sprite") is Dictionary:
			s._sprites[kind] = entry.sprite
	return s


func color(kind: String, fallback := Color.MAGENTA) -> Color:
	return _colors.get(kind, fallback)


## 그림 영역이 정해져 있으면 그 정보, 없으면 빈 Dictionary (G1 전까지는 늘 비어 있다)
func sprite(kind: String) -> Dictionary:
	return _sprites.get(kind, {})


func has_kind(kind: String) -> bool:
	return _colors.has(kind) or _sprites.has(kind)
