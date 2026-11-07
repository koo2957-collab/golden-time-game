class_name HazardSystem
extends RefCounted
## 특수현상의 징후와 피해 (SOP 210, 교재 제2장 제5절).
## - 롤오버 징후: 상부층이 플래시오버 온도 가까이(rollover_margin_c) 오르면 천장 화염이 굽이친다 (플래시오버 전조)
## - 플래시오버: 그 순간 방 안의 대원은 행동 불능, 요구조자는 사망 (교재: 방화복 착용자도 2초 이상 버티지 못함)
## - 백드래프트: 미연소가스가 폭발하한(12.5%) 이상·산소 부족·고온인 방의 문(하부 개구부)을 열면 폭발.
##   문 앞 작업을 시작하면 징후(문틈 검은 연기·휘파람 소리·문 뜨거움)를 알린다. 창 파괴(상부 배연)는 폭발을 일으키지 않는다
## - 화재가스발화 위험: 대원이 있는 방이 350℃ 이상이면 즉시 대피 경고 (SOP 210-10.5.4)
## 징후 알림은 지휘관이 알 수 있을 때(그 방이 보이거나 대원이 근처에 있을 때)만 낸다.

const WARNING_COOLDOWN_TICKS := 200
## 폭발 연출을 남겨 두는 시간 (틱)
const BLAST_SHOW_TICKS := 25

var fire: FireSim
var units: UnitSystem
var rescue: RescueSystem
var perception: Perception
var events: SimEventLog
## 화면 연출용 최근 폭발: [위치(셀 좌표), 층, 틱]
var blasts: Array[Array] = []

var _rollover_margin: float
var _rollover_layer: float
var _bd_gas: float
var _bd_o2: float
var _bd_temp: float
var _bd_sign_gas: float
var _bd_range: float
var _fgi_temp: float
var _warned: Dictionary = {}  # 키 -> 틱


func _init(p_fire: FireSim, p_units: UnitSystem, p_rescue: RescueSystem, p_perception: Perception, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	rescue = p_rescue
	perception = p_perception
	events = p_events
	_rollover_margin = params.value("rollover_margin_c")
	_rollover_layer = params.value("rollover_min_layer_m")
	_bd_gas = params.value("backdraft_gas_pct")
	_bd_o2 = params.value("backdraft_o2_max_pct")
	_bd_temp = params.value("backdraft_temp_c")
	_bd_sign_gas = params.value("backdraft_sign_gas_pct")
	_bd_range = params.value("backdraft_blast_range_m") / fire.building.cell_size_m
	_fgi_temp = params.value("fgi_warning_temp_c")


## 화재 계산 직후 (같은 틱)
func step(tick: int) -> void:
	for c in fire.comps:
		if c.flashover_tick == tick:
			_flashover_damage(c, tick)
		_update_rollover(c, tick)
		_fgi_warning(c, tick)
	while not blasts.is_empty() and tick - int(blasts[0][2]) > BLAST_SHOW_TICKS:
		blasts.pop_front()


## 문(하부 개구부)이 열렸을 때: 백드래프트 판정
func on_door_opened(o: Opening, tick: int) -> void:
	for r in _rooms_of(o):
		var c := fire.comps[r]
		if c.gas_percent() >= _bd_gas and c.o2_percent() <= _bd_o2 and c.t_upper >= _bd_temp:
			_backdraft(c, o, tick)
			return


## 조가 닫힌 문 앞 작업을 시작할 때: 백드래프트 징후
func on_door_approach(o: Opening, tick: int) -> void:
	for r in _rooms_of(o):
		var c := fire.comps[r]
		if c.gas_percent() >= _bd_sign_gas and c.o2_percent() <= _bd_o2 + 2.0 and c.t_upper >= _bd_temp * 0.6:
			_warn("bd_sign:%d" % o.index, tick, "backdraft_sign", {"room": c.display_name()})
			return


func _flashover_damage(c: Compartment, tick: int) -> void:
	for ff in units.firefighters:
		if not ff.incapacitated and _in_room(ff.level, ff.pos, c):
			ff.incapacitated = true
			ff.path.clear()
			events.add(tick, "ff_down", {"crew": _ff_name(ff), "reason": "플래시오버"})
	rescue.on_flashover(c, tick)


func _update_rollover(c: Compartment, tick: int) -> void:
	var near := not c.flashed and c.t_upper >= c.flashover_temp - _rollover_margin and c.layer_depth >= _rollover_layer
	if near and not c.rollover and _noticeable(c):
		_warn("rollover:%d" % c.index, tick, "rollover_sign", {"room": c.display_name()})
	c.rollover = near


func _fgi_warning(c: Compartment, tick: int) -> void:
	if c.t_upper < _fgi_temp:
		return
	for ff in units.firefighters:
		if not ff.incapacitated and _in_room(ff.level, ff.pos, c):
			_warn("fgi:%d" % c.index, tick, "fgi_warning", {"room": c.display_name()})
			return


func _backdraft(c: Compartment, o: Opening, tick: int) -> void:
	var center := Vector2.ZERO
	for cell in o.cells:
		center += Vector2(cell) + Vector2(0.5, 0.5)
	center /= o.cells.size()
	events.add(tick, "backdraft", {"room": c.display_name()})
	blasts.append([center, o.level, tick])
	for ff in units.firefighters:
		if not ff.incapacitated and ff.level == o.level and ff.pos.distance_to(center) <= _bd_range:
			ff.incapacitated = true
			ff.path.clear()
			events.add(tick, "ff_down", {"crew": _ff_name(ff), "reason": "백드래프트"})
	# 쌓인 가스가 한꺼번에 타며 방 전체가 화염에 휩싸인다
	c.gas *= 0.2
	fire.grid.ignite_room(c.index, 0.7)
	if not c.flashed:
		c.flashed = true
		c.flashover_tick = tick
	rescue.on_flashover(c, tick)


## 지휘관이 알 수 있는 상황인지: 그 방이 보이거나, 대원이 그 방 또는 맞닿은 칸에 있음
func _noticeable(c: Compartment) -> bool:
	if perception.room_visible(c):
		return true
	for ff in units.firefighters:
		if ff.level == c.level and c.rect.grow(1).has_point(Vector2i(ff.pos.floor())):
			return true
	return false


func _warn(key: String, tick: int, type: String, data: Dictionary) -> void:
	if tick - int(_warned.get(key, -WARNING_COOLDOWN_TICKS)) < WARNING_COOLDOWN_TICKS:
		return
	_warned[key] = tick
	events.add(tick, type, data)


func _rooms_of(o: Opening) -> Array[int]:
	var out: Array[int] = [o.room_a]
	if o.room_b != Opening.OUTSIDE:
		out.append(o.room_b)
	return out


func _in_room(level: int, pos: Vector2, c: Compartment) -> bool:
	return level == c.level and fire.compartment_at(level, floori(pos.x), floori(pos.y)) == c


func _ff_name(ff: Firefighter) -> String:
	return "%s %d조 %s" % [units.squads[ff.squad_id].name, units.get_crew(ff.crew_id).number, ff.name]
