class_name FallSystem
extends RefCounted
## 창가 주민 추락과 공기안전매트 (SOP 213-2.4.3), 낙하물 안전구역 (213-2.7.1).
##   추락: 시나리오에서 window: true인 요구조자가 3층 이상 창가에서 의식이 있을 때
##         창이 달궈지기 시작하거나(상층 연소 가열 40%) 연기 노출(jump_warn_fed)이 생기면 "뛰어내리려 함" 징후를 보이고,
##         방에 불이 붙은 뒤 jump_delay_s가 지나거나 노출이 jump_fed를 넘거나 방이 플래시오버면 뛰어내린다.
##         창 아래에 공기안전매트가 있으면 다쳐도 살고(구조됨, 응급), 없으면 사망한다
##   매트: 구조대 조가 창 아래 바닥으로 가서 정해진 시간 설치한다
##   낙하물: 3층 이상 창이 깨지면 그 아래 바닥에 반경 = 층 높이의 1/2 안전구역이 생긴다.
##           구역 안에 머문 대원 시간을 쌓고 처음 들어가면 경고한다

const FLOOR_M := 3.0

var fire: FireSim
var exposure: ExposureSystem
var units: UnitSystem
var rescue: RescueSystem
var pathfinder: Pathfinder
var events: SimEventLog
## 설치된 매트 위치 (셀 좌표, 1층 바닥)
var mats: Array[Vector2] = []
## 매트 설치 중인 조 id -> {cell: Vector2i, left: 초}
var setups: Dictionary = {}
## 낙하물 구역 [{center: Vector2, radius: 셀, room: 이름}]
var zones: Array[Dictionary] = []
## 구역 안에 대원이 머문 시간 합 (대원·초)
var zone_seconds := 0.0
var warned: Dictionary = {}  # 요구조자 id -> true (뛰어내리려 함 알림)
var jumped: Dictionary = {}  # 요구조자 id -> {mat: bool, tick}

var _warn_fed: float
var _jump_fed: float
var _jump_delay_ticks: int
var _burning_since: Dictionary = {}  # 요구조자 id -> 그 방에 불이 붙은 tick
var _setup_s: float
var _mat_radius: float
var _cell_m: float
var _zoned: Dictionary = {}  # opening index -> true
var _zone_warned: Dictionary = {}  # 대원 id -> true


func _init(p_fire: FireSim, p_exposure: ExposureSystem, p_units: UnitSystem, p_rescue: RescueSystem, p_pathfinder: Pathfinder, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	exposure = p_exposure
	units = p_units
	rescue = p_rescue
	pathfinder = p_pathfinder
	events = p_events
	_cell_m = fire.building.cell_size_m
	_warn_fed = params.value("jump_warn_fed")
	_jump_fed = params.value("jump_fed")
	_jump_delay_ticks = roundi(params.value("jump_delay_s") / SimClock.TICK_DT)
	_setup_s = params.value("air_mat_setup_s")
	_mat_radius = params.value("air_mat_radius_m") / _cell_m


## 이 건물에서 추락·낙하물을 따지는가 (3층 이상 건물)
func enabled() -> bool:
	return fire.building.levels().size() >= 3


## 공기안전매트 설치 명령: 구조대 조만 (매트를 싣고 다닌다)
func order_mat(crew_id: int, cell: Vector2i, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	var s := units.squad_of_crew(crew_id)
	if c == null or s == null or s.type != "구조대":
		return false
	var spot := pathfinder.nearest_walkable(1, cell)
	if spot == Pathfinder.NO_CELL or not fire.building.cell(1, spot.x, spot.y) in BuildingData.OUTDOOR:
		return false
	setups[crew_id] = {"cell": spot, "left": _setup_s}
	units.order_move([crew_id] as Array[int], Vector3i(spot.x, spot.y, 1), pathfinder)
	events.add(tick, "air_mat_start", {"crew": _crew_name(c)})
	return true


func cancel(crew_id: int) -> void:
	setups.erase(crew_id)


## 창 아래 바닥 지점 (창에서 바깥으로 2칸, 1층). 창이 없으면 (-1, -1)
func ground_below(v: Victim) -> Vector2:
	var w := _window_near(v.level, Vector2i(v.pos.floor()))
	if w.x < 0:
		return Vector2(-1, -1)
	return Vector2(w) + Vector2(0.5, 0.5) + _outward(w) * 2.0


func mat_near(p: Vector2) -> bool:
	for m in mats:
		if m.distance_to(p) <= _mat_radius:
			return true
	return false


func step(dt: float, tick: int) -> void:
	if not enabled():
		return
	_step_setups(dt, tick)
	for v in rescue.victims:
		if v.jumper and v.state == Victim.State.CONSCIOUS and v.carried_by < 0 and v.level >= 3 and not jumped.has(v.id):
			_step_jumper(v, tick)
	_update_zones(tick)
	_count_zone(dt, tick)


# --- 내부 ---

func _step_setups(dt: float, tick: int) -> void:
	for id: int in setups.keys():
		var c := units.get_crew(id)
		var s: Dictionary = setups[id]
		var at := Vector2(s.cell) + Vector2(0.5, 0.5)
		if c.leader.incapacitated or c.leader.is_moving() or c.leader.level != 1 or c.leader.pos.distance_to(at) > 2.0:
			continue
		s.left -= dt
		if s.left <= 0.0:
			setups.erase(id)
			mats.append(at)
			events.add(tick, "air_mat_ready", {"crew": _crew_name(c)})


func _step_jumper(v: Victim, tick: int) -> void:
	var room := fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y))
	if room != null and room.ever_burned and not _burning_since.has(v.id):
		_burning_since[v.id] = tick
	var desperate := v.fed() >= _jump_fed or (room != null and room.flashed) 		or (_burning_since.has(v.id) and tick - int(_burning_since[v.id]) >= _jump_delay_ticks)
	var heated := room != null and exposure.room_ratio(room) >= 0.4
	if (v.fed() >= _warn_fed or heated or _burning_since.has(v.id)) and not warned.has(v.id):
		warned[v.id] = true
		v.discovered = true  # 창가에서 몸을 내밀어 밖에서 보인다
		events.add(tick, "jump_risk", {"who": v.label(), "room": room.display_name() if room else "", "crew": "현장 대원"})
	if not desperate:
		return
	var below := ground_below(v)
	if below.x < 0:
		return
	var on_mat := mat_near(below)
	jumped[v.id] = {"mat": on_mat, "tick": tick}
	v.pos = below
	v.level = 1
	v.discovered = true
	v.fell = true
	if on_mat:
		v.state_at_rescue = Victim.State.CONSCIOUS
		v.state = Victim.State.RESCUED
		v.rescued_tick = tick
		events.add(tick, "victim_jumped", {"who": v.label(), "mat": true, "crew": "현장 대원"})
		events.add(tick, "victim_rescued", {"who": v.label(), "state": "공기안전매트 착지"})
	else:
		v.state = Victim.State.DEAD
		events.add(tick, "victim_jumped", {"who": v.label(), "mat": false, "crew": "현장 대원"})
		events.add(tick, "victim_state", {"who": v.label(), "state": Victim.STATE_NAMES[Victim.State.DEAD], "reason": "추락"})


## 3층 이상 바깥 창이 깨지면 그 아래에 낙하물 구역
func _update_zones(tick: int) -> void:
	for o in fire.openings:
		if o.kind != Opening.Kind.WINDOW or not o.broken or o.level < 3 or _zoned.has(o.index):
			continue
		if o.room_a != Opening.OUTSIDE and o.room_b != Opening.OUTSIDE:
			continue
		_zoned[o.index] = true
		var w := o.cells[0]
		var center := Vector2(w) + Vector2(0.5, 0.5) + _outward(w) * 1.0
		var radius := maxf(2.0, o.level * FLOOR_M * 0.5 / _cell_m)
		# 같은 층 가까운 창(같은 방 창 여러 칸)은 한 구역으로
		var merged := false
		for z in zones:
			if int(z.level) == o.level and z.center.distance_to(center) <= 8.0:
				merged = true
		if merged:
			continue
		zones.append({"center": center, "radius": radius, "level": o.level, "tick": tick})
		var room := fire.comps[o.room_a if o.room_a != Opening.OUTSIDE else o.room_b]
		events.add(tick, "debris_zone", {"floor": room.display_name(), "face": _face_name(w), "radius_m": snappedf(radius * _cell_m, 0.1), "crew": "현장안전담당"})


func _count_zone(dt: float, tick: int) -> void:
	if zones.is_empty():
		return
	for ff in units.firefighters:
		if ff.level != 1 or ff.aboard or ff.incapacitated:
			continue
		if not fire.building.cell(1, floori(ff.pos.x), floori(ff.pos.y)) in BuildingData.OUTDOOR:
			continue
		for z in zones:
			if ff.pos.distance_to(z.center) <= z.radius:
				zone_seconds += dt
				if not _zone_warned.has(ff.crew_id):
					_zone_warned[ff.crew_id] = true
					events.add(tick, "debris_zone_entered", {"crew": _crew_name(units.get_crew(ff.crew_id))})
				break


func _window_near(level: int, c: Vector2i) -> Vector2i:
	for r in range(1, 3):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector2i(dx, dy)
				if fire.building.cell(level, p.x, p.y) == BuildingData.Cell.WINDOW and _outward(p) != Vector2.ZERO:
					return p
	return Vector2i(-1, -1)


## 바깥벽 창의 바깥 방향 (건물 외곽 기준). 외곽벽이 아니면 0
func _outward(c: Vector2i) -> Vector2:
	var r := fire.building.footprint(1)
	if c.x == r.position.x:
		return Vector2.LEFT
	if c.x == r.end.x - 1:
		return Vector2.RIGHT
	if c.y == r.position.y:
		return Vector2.UP
	if c.y == r.end.y - 1:
		return Vector2.DOWN
	return Vector2.ZERO


## 창이 있는 면 이름 (A면 등). 모르면 빈 문자열
func _face_name(c: Vector2i) -> String:
	var dir: String = {Vector2.DOWN: "south", Vector2.UP: "north", Vector2.LEFT: "west", Vector2.RIGHT: "east"}.get(_outward(c), "")
	for key: String in fire.building.faces:
		if fire.building.faces[key] == dir:
			return key + "면"
	return ""


func _crew_name(c: Crew) -> String:
	return "%s %d조" % [units.squads[c.squad_id].name, c.number]
