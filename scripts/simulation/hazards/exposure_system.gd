class_name ExposureSystem
extends RefCounted
## 인접 건물로의 연소 확대 (SOP 214-2.4, RECEO의 E). 화재 건물 개구부로 나오는 화염의 복사열이
## 마주 보는 인접 건물 창을 가열하고, 누적 가열량이 기준을 넘으면 창이 깨지고 실내에 불이 옮겨 붙는다.
##   바람 (214-2.4.4): 풍하 쪽일수록 강해진다 (시나리오 wind: from_deg 바람이 불어오는 방향, speed_mps)
##   경계관창 (214-2.4.1·2.4.2): 방수 목표가 인접 창 가까이 또는 두 건물 사이에 있으면 가열이 식고 더 쌓이지 않는다

class Pair:
	extends RefCounted
	var source: Opening
	var target: Opening
	var dist_m := 1.0
	var wind := 1.0
	## 같은 건물 아래층 창 → 바로 위층 창 (SOP 213-1.1)
	var vertical := false


var fire: FireSim
var water: WaterSystem
var events: SimEventLog
var pairs: Array[Pair] = []
## 인접 건물 창 index -> 누적 가열량 (kJ/㎡)
var dose: Dictionary = {}
## 불이 옮겨 붙은 인접 창 index
var ignited: Dictionary = {}
## 가열이 가장 높았던 비율 (평가용, 0~1)
var peak := 0.0
## 경계관창이 처음 가열 중인 창을 막은 tick (-1이면 없음)
var protected_tick := -1
var wind_from_deg := 0.0
var wind_mps := 0.0

var _ext: float
var _crit: float
var _ignite: float
var _cool: float
var _sign_ratio: float
var _wind_k: float
var _max_m: float
var _signed: Dictionary = {}  # 구획 index -> true (창이 여러 개여도 방마다 한 번 알림)
var _ignited_rooms: Dictionary = {}


func _init(p_fire: FireSim, p_water: WaterSystem, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	water = p_water
	events = p_events
	_ext = params.value("exposure_ext_fraction")
	_crit = params.value("exposure_crit_kw")
	_ignite = params.value("exposure_ignite_kj")
	_cool = params.value("exposure_cool_kw")
	_sign_ratio = params.value("exposure_sign_ratio")
	_wind_k = params.value("wind_k")
	_max_m = params.value("exposure_max_m")
	_build_pairs()


## 시나리오 wind: {from_deg, speed_mps}
func apply_scenario(data: Dictionary) -> void:
	var w: Dictionary = data.get("wind", {})
	wind_from_deg = float(w.get("from_deg", 0.0))
	wind_mps = float(w.get("speed_mps", 0.0))
	for p in pairs:
		p.wind = 1.0 if p.vertical else _wind_factor(p)


func has_exposure() -> bool:
	return not pairs.is_empty()


## 그 구획의 창 가열 비율 중 가장 높은 값 (0~1). 창가 주민의 위험 판단에 쓴다
func room_ratio(room: Compartment) -> float:
	var m := 0.0
	for p in pairs:
		if _room(p.target) == room:
			m = maxf(m, float(dose.get(p.target.index, 0.0)) / _ignite)
	return 1.0 if ignited.keys().any(func(i: int) -> bool: return _room(fire.openings[i]) == room) else clampf(m, 0.0, 1.0)


## 인접 건물 가열 중 가장 높은 비율 (0~1, 화면 표시용)
func max_ratio() -> float:
	var m := 0.0
	for k in dose:
		m = maxf(m, dose[k] / _ignite)
	return clampf(m, 0.0, 1.0)


## 화면·평가용 이름: 인접 건물이 있으면 그 이름, 상층 연소만 있으면 "상층 세대"
func label() -> String:
	for st in fire.building.structures:
		if st.exposure:
			return str(st.name)
	return "상층 세대" if fire.building.vertical_exposure else "인접 건물"


func exposure_name() -> String:
	for st in fire.building.structures:
		if st.exposure:
			return str(st.name)
	return "인접 건물"


## 1초마다: 화재 건물 개구부 → 인접 창 가열, 경계관창 냉각, 착화
func step(dt: float, tick: int) -> void:
	var flux_at: Dictionary = {}
	var main_src: Dictionary = {}  # 대상 창 index -> 가장 센 원천 구획
	var best_q: Dictionary = {}
	for p in pairs:
		var src := _room(p.source)
		if src == null or not (src.flashed or src.stage == Compartment.Stage.FULLY_DEVELOPED):
			continue
		if not (p.source.is_open or p.source.broken):
			continue
		var q := src.q * _ext * p.wind / (4.0 * PI * p.dist_m * p.dist_m)
		flux_at[p.target.index] = flux_at.get(p.target.index, 0.0) + q
		if q > float(best_q.get(p.target.index, 0.0)):
			best_q[p.target.index] = q
			main_src[p.target.index] = src
	for p in pairs:
		var t := p.target
		if ignited.has(t.index):
			continue
		var d: float = dose.get(t.index, 0.0)
		if _protected(p):
			if d > 0.0 and protected_tick < 0:
				protected_tick = tick
			d = maxf(0.0, d - _cool * dt)
		else:
			d += maxf(0.0, float(flux_at.get(t.index, 0.0)) - _crit) * dt
		dose[t.index] = d
		peak = maxf(peak, minf(1.0, d / _ignite))
		var t_room := _room(t)
		var room_key: int = t_room.index if t_room else -1 - t.index
		if d >= _ignite * _sign_ratio and not _signed.has(room_key):
			_signed[room_key] = true
			var from: Compartment = main_src.get(t.index, _room(p.source))
			var target := "%s (위층 창)" % _room(t).display_name() if p.vertical else exposure_name()
			events.add(tick, "exposure_heating", {"target": target, "from": from.display_name(), "crew": "현장 대원"})
		if d >= _ignite:
			_ignite_target(t, tick)


# --- 내부 ---

func _build_pairs() -> void:
	var b := fire.building
	if b.vertical_exposure:
		_build_vertical_pairs()
	if b.structures.size() < 2:
		return
	var cell_m := b.cell_size_m
	for s in fire.openings:
		if not _exterior(s) or _in_exposure(s):
			continue
		for t in fire.openings:
			if t.kind != Opening.Kind.WINDOW or not _exterior(t) or not _in_exposure(t):
				continue
			var cs := _center(s)
			var ct := _center(t)
			# 층 차이도 거리에 넣는다 (층 높이 약 3m)
			var d := Vector2(cs.distance_to(ct) * cell_m, absi(s.level - t.level) * 3.0).length()
			if d > _max_m:
				continue
			if _outward(s).dot(ct - cs) <= 0.0 or _outward(t).dot(cs - ct) <= 0.0:
				continue
			var p := Pair.new()
			p.source = s
			p.target = t
			p.dist_m = maxf(1.0, d)
			pairs.append(p)


## 아래층 바깥 창 → 바로 위층의 같은 면 창 (수평 3칸 안). 거리는 층 높이 3m
func _build_vertical_pairs() -> void:
	for s in fire.openings:
		if s.kind != Opening.Kind.WINDOW or not _exterior(s) or _in_exposure(s):
			continue
		for t in fire.openings:
			if t.kind != Opening.Kind.WINDOW or t.level != s.level + 1 or not _exterior(t) or _in_exposure(t):
				continue
			if _outward(s) != _outward(t) or _center(s).distance_to(_center(t)) > 3.0:
				continue
			var p := Pair.new()
			p.source = s
			p.target = t
			p.dist_m = 3.0
			p.vertical = true
			pairs.append(p)


func _exterior(o: Opening) -> bool:
	return o.kind != Opening.Kind.STAIR and (o.room_a == Opening.OUTSIDE or o.room_b == Opening.OUTSIDE)


func _in_exposure(o: Opening) -> bool:
	return fire.building.is_exposure(o.cells[0].x, o.cells[0].y)


## 개구부가 속한 건물 사각형 기준 바깥 방향
func _outward(o: Opening) -> Vector2:
	var st := fire.building.structure_at(o.cells[0].x, o.cells[0].y)
	if st.is_empty():
		return Vector2.ZERO
	var r: Rect2i = st.rect
	var c: Vector2i = o.cells[0]
	if c.x == r.position.x:
		return Vector2.LEFT
	if c.x == r.end.x - 1:
		return Vector2.RIGHT
	if c.y == r.position.y:
		return Vector2.UP
	return Vector2.DOWN


## 풍하 쪽일수록 강해진다: 바람이 불어가는 방향과 (원천 → 대상) 방향이 같을수록
func _wind_factor(p: Pair) -> float:
	if wind_mps <= 0.0:
		return 1.0
	var to_rad := deg_to_rad(wind_from_deg + 180.0)
	var blow := Vector2(sin(to_rad), -cos(to_rad))  # 화면 좌표: 북쪽 = -y
	var dir := (_center(p.target) - _center(p.source)).normalized()
	return clampf(1.0 + _wind_k * wind_mps * blow.dot(dir), 0.3, 3.0)


## 경계관창: 흐르는 관창의 목표가 대상 창 가까이(1.5m) 또는 두 개구부 사이(1m 안)
func _protected(p: Pair) -> bool:
	var a := _center(p.source)
	var b := _center(p.target)
	for h in water.hoses:
		if not h.flowing:
			continue
		if p.vertical and h.target.z != p.source.level and h.target.z != p.target.level:
			continue
		var tgt := Vector2(h.target.x, h.target.y) + Vector2(0.5, 0.5)
		if tgt.distance_to(b) <= 3.0:
			return true
		if Geometry2D.get_closest_point_to_segment(tgt, a, b).distance_to(tgt) <= 2.0:
			return true
	return false


func _ignite_target(t: Opening, tick: int) -> void:
	ignited[t.index] = true
	t.broken = true
	t.is_open = true
	var room := _room(t)
	if room == null:
		return
	var best := -1
	var best_d := INF
	var c := _center(t)
	for cell in room.cells:
		var i := fire.grid.index(room.level, cell.x, cell.y)
		if fire.grid.state[i] != FuelGrid.State.UNBURNED:
			continue
		var d := c.distance_to(Vector2(cell) + Vector2(0.5, 0.5))
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		fire.grid.ignite(best, 0.5)
	if _ignited_rooms.has(room.index):
		return
	_ignited_rooms[room.index] = true
	events.add(tick, "exposure_ignition", {"target": room.display_name() if fire.building.vertical_exposure and not _in_exposure(t) else room.name, "crew": "현장 대원"})


func _room(o: Opening) -> Compartment:
	var i := o.room_a if o.room_a != Opening.OUTSIDE else o.room_b
	return fire.comps[i] if i >= 0 and i < fire.comps.size() else null


func _center(o: Opening) -> Vector2:
	var s := Vector2.ZERO
	for cell in o.cells:
		s += Vector2(cell) + Vector2(0.5, 0.5)
	return s / o.cells.size()
