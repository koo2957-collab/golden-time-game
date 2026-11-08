class_name BuildingData
extends RefCounted
## 건물 도면 데이터. 층마다 셀 격자(문자 행)와 방(구획) 목록을 가진다.
## 도면 표시, 길찾기, 그리고 M2 이후 화재 시뮬레이션의 구획 정보로 함께 쓰인다.

enum Cell { VOID, GROUND, ROAD, FLOOR, WALL, DOOR, WINDOW, STAIRS, SIDEWALK }

const CHAR_TO_CELL := {
	" ": Cell.VOID,
	",": Cell.GROUND,
	"=": Cell.ROAD,
	"-": Cell.SIDEWALK,
	".": Cell.FLOOR,
	"#": Cell.WALL,
	"D": Cell.DOOR,
	"W": Cell.WINDOW,
	"S": Cell.STAIRS,
}
const WALKABLE: Array[int] = [Cell.GROUND, Cell.ROAD, Cell.SIDEWALK, Cell.FLOOR, Cell.DOOR, Cell.STAIRS]
## 건물 밖 (개구부의 외부 쪽 판정 등)
const OUTDOOR: Array[int] = [Cell.VOID, Cell.GROUND, Cell.ROAD, Cell.SIDEWALK]
const STRUCTURE: Array[int] = [Cell.FLOOR, Cell.WALL, Cell.DOOR, Cell.WINDOW, Cell.STAIRS]


class FloorData:
	var level: int
	var name: String
	var cells: PackedByteArray
	var rooms: Array[Dictionary] = []
	var furniture: Array[Dictionary] = []


var id := ""
var name := ""
var structure := ""
var cell_size_m := 0.5
var width := 0
var height := 0
var faces: Dictionary = {}
## 소화전 위치 (가장 아래층 기준 셀)
var hydrants: Array[Vector2i] = []
## 도면 안의 건물들 [{id, name, rect: Rect2i, exposure}]. 첫 번째(main)가 화재 건물, exposure는 인접 건물(연소 확대 대상)
var structures: Array[Dictionary] = []
## 연결송수관 (SOP 200-3.3.1): 송수구 칸, 층별 방수구 (x, y, level), 방수구에서 쓰는 수관 길이(m). 없으면 fdc = (-1, -1)
var fdc := Vector2i(-1, -1)
var outlets: Array[Vector3i] = []
var outlet_hose_m := 30.0
## 옥내소화전 (SOP 235): 송수구 연결 없이 건물 수조 물로 방수구를 쓴다. 0이면 없음
var indoor_lpm := 0.0
var indoor_tank_l := 0.0
## 현관 방화문 칸 (모든 층). 잠겨 있으면 파괴에 더 오래 걸린다 (SOP 213-2.3)
var fire_doors: Array[Vector2i] = []
## 같은 건물 아래층 창 → 위층 창 연소 확대 (SOP 213-1.1)
var vertical_exposure := false
## 배관 샤프트 [{name, rect: Rect2i, levels: [층]}] (SOP 212-2.3)
var shafts: Array[Dictionary] = []
## 외벽 간판 [{name, rect: Rect2i, level}] (SOP 212-1.4)
var signs: Array[Dictionary] = []
var load_errors: PackedStringArray = []

var _floors: Dictionary = {}  # level -> FloorData
var _levels: Array[int] = []


static func from_file(path: String) -> BuildingData:
	var data: Variant = JsonData.load_file(path)
	if not data is Dictionary:
		return null
	var building := BuildingData.new()
	building._parse(data)
	if not building.load_errors.is_empty():
		for e in building.load_errors:
			push_error("%s: %s" % [path, e])
		return null
	return building


func levels() -> Array[int]:
	return _levels.duplicate()


func has_level(level: int) -> bool:
	return _floors.has(level)


func floor_name(level: int) -> String:
	return _floors[level].name if _floors.has(level) else ""


func rooms(level: int) -> Array[Dictionary]:
	return _floors[level].rooms if _floors.has(level) else []


## 가구 목록 {name, material, rect}
func furniture(level: int) -> Array[Dictionary]:
	return _floors[level].furniture if _floors.has(level) else []


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func cell(level: int, x: int, y: int) -> int:
	if not _floors.has(level) or not in_bounds(x, y):
		return Cell.VOID
	return _floors[level].cells[y * width + x]


func is_walkable(level: int, x: int, y: int) -> bool:
	return cell(level, x, y) in WALKABLE


## 셀이 속한 방을 반환한다. 방이 아니면 빈 Dictionary.
func room_at(level: int, x: int, y: int) -> Dictionary:
	for room in rooms(level):
		if room.rect.has_point(Vector2i(x, y)):
			return room
	return {}


## lower 층과 lower+1 층이 같은 위치에 모두 계단인 셀 (층간 이동 지점)
func stair_links(lower: int) -> Array[Vector2i]:
	var links: Array[Vector2i] = []
	if not (has_level(lower) and has_level(lower + 1)):
		return links
	for y in height:
		for x in width:
			if cell(lower, x, y) == Cell.STAIRS and cell(lower + 1, x, y) == Cell.STAIRS:
				links.append(Vector2i(x, y))
	return links


## 맨 왼쪽 열 기준으로 차도가 차지하는 행 범위 (x = 첫 행, y = 마지막 행). 없으면 (-1, -1)
func road_rows(level: int) -> Vector2i:
	var rows := Vector2i(-1, -1)
	for y in height:
		if cell(level, 0, y) == Cell.ROAD:
			if rows.x < 0:
				rows.x = y
			rows.y = y
	return rows


## 해당 층에서 화재 건물(main)의 범위. structures가 없으면 구조물(바닥·벽·문·창·계단)이 차지하는 범위
func footprint(level: int) -> Rect2i:
	if not structures.is_empty():
		return structures[0].rect
	var result := Rect2i()
	var found := false
	for y in height:
		for x in width:
			if cell(level, x, y) in STRUCTURE:
				var r := Rect2i(x, y, 1, 1)
				result = r if not found else result.merge(r)
				found = true
	return result


func _parse(data: Dictionary) -> void:
	id = str(data.get("id", ""))
	name = str(data.get("name", ""))
	structure = str(data.get("structure", ""))
	cell_size_m = float(data.get("cell_size_m", 0.5))
	width = int(data.get("width", 0))
	height = int(data.get("height", 0))
	faces = data.get("faces", {})
	for st: Dictionary in data.get("structures", []):
		var r: Array = st.get("rect", [0, 0, 0, 0])
		structures.append({
			"id": str(st.get("id", "")), "name": str(st.get("name", "")),
			"rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])),
			"exposure": bool(st.get("exposure", false)),
		})
	for h: Array in data.get("hydrants", []):
		hydrants.append(Vector2i(int(h[0]), int(h[1])))
	var sp: Dictionary = data.get("standpipe", {})
	if not sp.is_empty():
		var f: Array = sp.get("fdc", [-1, -1])
		fdc = Vector2i(int(f[0]), int(f[1]))
		for o: Array in sp.get("outlets", []):
			outlets.append(Vector3i(int(o[0]), int(o[1]), int(o[2])))
		outlet_hose_m = float(sp.get("outlet_hose_m", outlet_hose_m))
	var ih: Dictionary = data.get("indoor_hydrant", {})
	indoor_lpm = float(ih.get("lpm", 0.0))
	indoor_tank_l = float(ih.get("tank_l", 0.0))
	for d: Array in data.get("fire_doors", []):
		fire_doors.append(Vector2i(int(d[0]), int(d[1])))
	vertical_exposure = bool(data.get("vertical_exposure", false))
	for sh: Dictionary in data.get("shafts", []):
		var r: Array = sh.get("rect", [0, 0, 1, 1])
		shafts.append({"name": str(sh.get("name", "샤프트")), "rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])),
			"levels": sh.get("levels", []).map(func(l: Variant) -> int: return int(l))})
	for sg: Dictionary in data.get("signs", []):
		var r: Array = sg.get("rect", [0, 0, 1, 1])
		signs.append({"name": str(sg.get("name", "간판")), "rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])), "level": int(sg.get("level", 2))})
	if width <= 0 or height <= 0:
		load_errors.append("width/height가 올바르지 않습니다.")
		return
	for floor_data: Dictionary in data.get("floors", []):
		_parse_floor(floor_data)
	if _floors.is_empty():
		load_errors.append("층(floors) 정보가 없습니다.")
	_levels.assign(_floors.keys())
	_levels.sort()


func _parse_floor(data: Dictionary) -> void:
	var f := FloorData.new()
	f.level = int(data.get("level", 0))
	f.name = str(data.get("name", "%d층" % f.level))
	var grid: Array = data.get("grid", [])
	if grid.size() != height:
		load_errors.append("%s grid 행 수가 %d입니다 (기대값 %d)." % [f.name, grid.size(), height])
		return
	f.cells.resize(width * height)
	for y in height:
		var row: String = grid[y]
		if row.length() != width:
			load_errors.append("%s grid %d행 길이가 %d입니다 (기대값 %d)." % [f.name, y, row.length(), width])
			return
		for x in width:
			var ch := row[x]
			if not CHAR_TO_CELL.has(ch):
				load_errors.append("%s grid (%d, %d)에 알 수 없는 문자 '%s'가 있습니다." % [f.name, x, y, ch])
				return
			f.cells[y * width + x] = CHAR_TO_CELL[ch]
	for room_data: Dictionary in data.get("rooms", []):
		var r: Array = room_data.get("rect", [])
		if r.size() != 4:
			load_errors.append("%s 방 '%s'의 rect가 올바르지 않습니다." % [f.name, room_data.get("id", "?")])
			continue
		f.rooms.append({
			"id": str(room_data.get("id", "")),
			"name": str(room_data.get("name", "")),
			"rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])),
			"lining": str(room_data.get("lining", "")),
		})
	for item: Dictionary in data.get("furniture", []):
		var r: Array = item.get("rect", [])
		if r.size() != 4:
			load_errors.append("%s 가구 '%s'의 rect가 올바르지 않습니다." % [f.name, item.get("name", "?")])
			continue
		f.furniture.append({
			"name": str(item.get("name", "")),
			"material": str(item.get("material", "")),
			"rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])),
		})
	_floors[f.level] = f


## 셀이 속한 건물 (structures). 없으면 빈 사전
func structure_at(x: int, y: int) -> Dictionary:
	for st in structures:
		if (st.rect as Rect2i).has_point(Vector2i(x, y)):
			return st
	return {}


## 인접 건물(연소 확대 대상)의 셀인지
func is_exposure(x: int, y: int) -> bool:
	return bool(structure_at(x, y).get("exposure", false))


func has_standpipe() -> bool:
	return fdc.x >= 0 and not outlets.is_empty()


## 그 층의 방수구 index (없으면 -1)
func outlet_on(level: int) -> int:
	for i in outlets.size():
		if outlets[i].z == level:
			return i
	return -1


func is_fire_door(cell: Vector2i) -> bool:
	return cell in fire_doors
