class_name ScenarioDraft
extends RefCounted
## 시나리오 편집기의 데이터 (화면과 분리). 기존 시나리오를 사본으로 불러와 고치고 user://scenarios/에 저장한다.
## 저장할 때 ScenarioLoader.validate로 검증해 한글 오류를 돌려준다. 기본 제공 시나리오 파일은 건드리지 않는다.

const SAVE_DIR := "user://scenarios"
const MOBILITY := ["", "거동 불편 (자력 피난 불가)"]

var data: Dictionary = {}
var building: BuildingData
var path := ""


## 기존 시나리오를 사본으로 연다. id·제목을 새로 정하고 정렬 순서는 기본 시나리오 뒤로
static func from_base(base_path: String) -> ScenarioDraft:
	var src: Variant = JsonData.load_file(base_path)
	if not src is Dictionary:
		return null
	var d := ScenarioDraft.new()
	d.data = (src as Dictionary).duplicate(true)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
	d.data["id"] = "custom_%s" % stamp
	d.data["title"] = "(사본) %s" % str(src.get("title", ""))
	var meta: Dictionary = d.data.get("meta", {})
	meta["order"] = 50
	meta["note_editor"] = "시나리오 편집기로 만듦 (원본: %s)" % base_path.get_file()
	d.data["meta"] = meta
	d.data.erase("tutorial")
	d.building = BuildingData.from_file(str(d.data.get("building", "")))
	return d


## 기존 사용자 시나리오를 그대로 연다 (다시 고치기)
static func open(user_path: String) -> ScenarioDraft:
	var src: Variant = JsonData.load_file(user_path)
	if not src is Dictionary:
		return null
	var d := ScenarioDraft.new()
	d.data = (src as Dictionary).duplicate(true)
	d.path = user_path
	d.building = BuildingData.from_file(str(d.data.get("building", "")))
	return d


# --- 글 ---

func set_title(text: String) -> void:
	data["title"] = text


func set_summary(text: String) -> void:
	_meta()["summary"] = text


func set_difficulty(text: String) -> void:
	_meta()["difficulty"] = text


func dispatch_lines() -> PackedStringArray:
	return PackedStringArray(data.get("dispatch", {}).get("lines", []))


func set_dispatch_lines(lines: PackedStringArray) -> void:
	var d: Dictionary = data.get("dispatch", {"title": "출동 지령"})
	d["lines"] = Array(lines).filter(func(l: String) -> bool: return l.strip_edges() != "")
	data["dispatch"] = d



## 판마다 다른 시드 (구조대상자 위치 등이 바뀐다)
func set_random_seed(on: bool) -> void:
	data["variation"] = {"random_seed": on}


# --- 도면 위 항목 ---

func ignitions() -> Array:
	return data.get("fire", {}).get("ignitions", [])


## 발화점 추가: 그 층 실내 바닥(걸을 수 있는 칸)이어야 한다. 성공하면 빈 문자열, 아니면 이유
func add_ignition(level: int, cell: Vector2i, time_s: float = 0.0) -> String:
	if not _indoor(level, cell):
		return "발화점은 건물 안 바닥 칸이어야 합니다."
	var fire: Dictionary = data.get("fire", {})
	var list: Array = fire.get("ignitions", [])
	list.append({"level": level, "cell": [cell.x, cell.y], "time_s": time_s, "note": "편집기"})
	fire["ignitions"] = list
	data["fire"] = fire
	return ""


func victims() -> Array:
	return data.get("victims", [])


func add_victim(level: int, cell: Vector2i, name: String, age: int, mobility: String, window := false, self_evac := false) -> String:
	if not _indoor(level, cell):
		return "구조대상자는 건물 안 바닥 칸에 놓아야 합니다."
	var v := {"name": name if name != "" else "요구조자", "age": age, "mobility": mobility, "level": level, "cell": [cell.x, cell.y]}
	if window:
		v["window"] = true
	if self_evac:
		v["self_evac"] = true
	var list: Array = data.get("victims", [])
	list.append(v)
	data["victims"] = list
	return ""


func witnesses() -> Array:
	return data.get("site", {}).get("witnesses", [])


## 관계인 위치 옮기기 (바깥 걸을 수 있는 칸)
func move_witness(index: int, cell: Vector2i) -> String:
	var list := witnesses()
	if index < 0 or index >= list.size():
		return "관계인이 없습니다."
	var lv := building.levels()[0]
	if not building.is_walkable(lv, cell.x, cell.y) or not building.cell(lv, cell.x, cell.y) in BuildingData.OUTDOOR:
		return "관계인은 1층 바깥 걸을 수 있는 칸에 둡니다."
	list[index]["pos"] = [cell.x, cell.y]
	return ""


## 그 칸에 가까운 발화점·구조대상자를 지운다 (2칸 안). 지웠으면 true
func remove_near(level: int, cell: Vector2i) -> bool:
	for key in ["ignitions", "victims"]:
		var list: Array = ignitions() if key == "ignitions" else victims()
		for i in list.size():
			var item: Dictionary = list[i]
			var c: Array = item.get("cell", [])
			if c.size() >= 2 and int(item.get("level", 1)) == level and Vector2i(int(c[0]), int(c[1])).distance_to(cell) <= 2.0:
				list.remove_at(i)
				return true
	return false


# --- 저장 ---

## user://scenarios/<id>.json에 저장하고 검증 오류(없으면 빈 배열)를 돌려준다
func save() -> PackedStringArray:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if path == "":
		path = "%s/%s.json" % [SAVE_DIR, data.get("id", "custom")]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return PackedStringArray(["저장할 수 없습니다: %s" % path])
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return ScenarioLoader.validate(path)


func _meta() -> Dictionary:
	if not data.has("meta"):
		data["meta"] = {}
	return data["meta"]


func _indoor(level: int, cell: Vector2i) -> bool:
	return building != null and building.has_level(level) and building.is_walkable(level, cell.x, cell.y) \
		and not building.cell(level, cell.x, cell.y) in BuildingData.OUTDOOR
