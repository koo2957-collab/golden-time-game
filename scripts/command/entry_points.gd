class_name EntryPoints
extends RefCounted
## 진입구 (기획안 9-1 '진입 지시', P4-2): 밖에서 건물 안으로 들어가는 문.
## 건물 데이터의 바깥 출입문(공동현관·현관·계단실 입구·비상계단·지하주차장 연결문)에서 만든다.
## 이름은 건물 JSON entry_names {"x,y": "공동현관"}가 있으면 그것, 없으면 안쪽 방 이름 + "출입문".
## 사다리·굴절차 도달 창은 그 차량이 생기면 더한다 (지금 차량 목록에 없음).
## 급기측·배기측: 바람이 불어오는 쪽 문이 급기측(풍상), 반대가 배기측(풍하) — 상황 배지에 풍향이 보이므로 '알려진 정보'.

class Entry:
	extends RefCounted
	var index := 0
	var name := ""
	var opening: Opening
	var level := 1
	## 문 바로 바깥 칸 (모이는 자리)
	var outside := Vector3i.ZERO
	## 문 칸
	var door := Vector2i.ZERO
	## 바깥으로 향하는 방향 (문 → 바깥 칸)
	var outward := Vector2.ZERO
	## 안쪽 구획 index
	var room := -1


var fire: FireSim
var exposure: ExposureSystem
var list: Array[Entry] = []


func _init(p_fire: FireSim, p_exposure: ExposureSystem, names: Dictionary = {}) -> void:
	fire = p_fire
	exposure = p_exposure
	var b := fire.building
	for o in fire.openings:
		if o.kind != Opening.Kind.DOOR or (o.room_b != Opening.OUTSIDE and o.room_a != Opening.OUTSIDE):
			continue
		var inside_room := o.room_a if o.room_b == Opening.OUTSIDE else o.room_b
		var out_cell := Vector3i(-1, -1, -1)
		var door_cell := o.cells[0]
		for cell in o.cells:
			for d: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
				var n := cell + d
				if out_cell.x < 0 and b.in_bounds(n.x, n.y) and b.cell(o.level, n.x, n.y) in BuildingData.OUTDOOR and b.is_walkable(o.level, n.x, n.y):
					out_cell = Vector3i(n.x, n.y, o.level)
					door_cell = cell
		if out_cell.x < 0:
			continue
		var e := Entry.new()
		e.index = list.size()
		e.opening = o
		e.level = o.level
		e.outside = out_cell
		e.door = door_cell
		e.outward = (Vector2(out_cell.x, out_cell.y) - Vector2(door_cell)).normalized()
		e.room = inside_room
		var key := "%d,%d" % [door_cell.x, door_cell.y]
		var room_name := fire.comps[inside_room].display_name() if inside_room >= 0 else ""
		e.name = str(names.get(key, "%s 출입문" % room_name if room_name != "" else "출입문"))
		list.append(e)


## 칸(x, y, 층) 가까이(max_cells 안)의 진입구 (없으면 null)
func nearest(cell: Vector2, level: int, max_cells: float) -> Entry:
	var best: Entry = null
	var best_d := max_cells
	for e in list:
		if e.level != level:
			continue
		var d := cell.distance_to(Vector2(e.door) + Vector2(0.5, 0.5))
		if d <= best_d:
			best_d = d
			best = e
	return best


## "급기측" / "배기측" / "측면" / "" (바람 없음): 바람이 불어오는 쪽을 향한 문이 급기측
func side(e: Entry) -> String:
	if exposure == null or exposure.wind_mps <= 0.0:
		return ""
	var rad := deg_to_rad(exposure.wind_from_deg)
	var from_vec := Vector2(sin(rad), -cos(rad))
	var d := e.outward.dot(from_vec)
	if d > 0.3:
		return "급기측"
	if d < -0.3:
		return "배기측"
	return "측면"


## 문에서 보이는 연기 (관찰 정보): 안쪽 방 시야로 나눈다. 짙은 연기 1m 미만·옅은 연기 5m 미만 (기획안 9-1 시야 규칙의 기준)
const DENSE_VIS_M := 1.0
const LIGHT_VIS_M := 5.0


func smoke_text(e: Entry) -> String:
	if e.room < 0:
		return ""
	var vis := fire.visibility_m(fire.comps[e.room])
	if vis >= LIGHT_VIS_M:
		return "연기 없음"
	if not e.opening.is_open:
		return "문틈으로 연기"
	return "검은 연기 분출" if vis < DENSE_VIS_M else "연기 나옴"
