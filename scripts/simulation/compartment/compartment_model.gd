class_name CompartmentModel
extends RefCounted
## 구획 2층 모델 계산.
## 1) 연소: 열방출, 산소 소비, 미연소가스·그을음 생성, 화염 기둥(플룸)이 만드는 연기층
## 2) 개구부 흐름: 연기층이 문 상단보다 내려오면 옆 구획·외부로 넘침, 계단으로 상승, 공기 교환
## 3) 상부층 온도: MQH 상관식으로 목표 온도를 구하고 서서히 따라감 (최성기 상한 근처에서 포화)

const G := 9.81
const CP := 1.0  # kJ/(kg·K)
const PLUME_COEFF := 0.071  # Zukoski 플룸 유입 질량식
const CONVECTIVE_FRACTION := 0.7
const OUTFLOW_COEFF := 0.47  # (2/3) × 유량계수 0.7
const LAYER_MIN_CLEAR_M := 0.05
const STEFAN_BOLTZMANN := 5.67e-11  # kW/(m²·K⁴)
const SATURATION_EXPONENT := 8.0
const MAX_COOLING_SHARE := 0.9
## 계단 구획이 이만큼 남기고 연기로 차면 '꽉 참'
const STAIR_FULL_MARGIN_M := 0.3

var comps: Array[Compartment]
## 굴뚝효과 배율 (계단·승강로 상승 기류, FireSim이 계절·건물 높이로 정한다)
var stack_factor := 1.0
var openings: Array[Opening]

var _t_amb: float
var _t_max: float
var _mqh_coeff: float
var _h_k: float
var _tau: float
var _vent_limit: float
var _k_exchange: float
var _o2_full: float
var _o2_min: float
var _fuel_heat: float
var _o2_heat: float
var _gas_burn: float
var _closed_leak: float
var _min_leak: float
var _smolder: float
var _gas_max_pct: float
var _hot_margin: float
var _stair_coeff: float
var _stair_depth: float


func _init(p_comps: Array[Compartment], p_openings: Array[Opening], config: FireConfig) -> void:
	comps = p_comps
	openings = p_openings
	_t_amb = config.value("ambient_temp_c")
	_t_max = config.value("max_layer_temp_c")
	_mqh_coeff = config.value("mqh_coeff")
	_h_k = config.value("wall_conductance_kw_m2k")
	_tau = config.value("layer_time_constant_s")
	_vent_limit = config.value("vent_limit_kw_per_ah")
	_k_exchange = config.value("air_exchange_kg_s_per_ah")
	_o2_full = config.value("o2_flaming_full_pct")
	_o2_min = config.value("o2_flaming_min_pct")
	_fuel_heat = config.value("fuel_heat_kj_kg")
	_o2_heat = config.value("o2_heat_kj_kg")
	_gas_burn = config.value("gas_burn_rate_per_s")
	_closed_leak = config.value("closed_door_leak_ah")
	_min_leak = config.value("room_min_leak_ah")
	_smolder = config.value("smolder_consumption_ratio")
	_gas_max_pct = config.value("unburned_gas_max_pct")
	_hot_margin = config.value("hot_layer_flow_margin_c")
	_stair_coeff = config.value("stair_upflow_coeff")
	_stair_depth = config.value("stair_upflow_depth_m")
	for c in comps:
		c.t_upper = _t_amb
		c.t_lower = _t_amb


func step(dt: float) -> void:
	for c in comps:
		_combust(c, dt)
		c.imported_kw = 0.0
	for o in openings:
		_flow(o, dt)
	for c in comps:
		_update_temperature(c, dt)


## 구획의 전체 개구 인자 (닫힌 문은 틈새값, 최소 누설 포함)
func room_ah(c: Compartment) -> float:
	var total := _min_leak
	for oi in c.openings:
		total += openings[oi].effective_ah(_closed_leak)
	return total


## 천장 고온층이 바닥 가연물에 주는 복사열 (kW/m²). 연기층이 깊을수록 많이 받는다.
func layer_radiation_kw_m2(c: Compartment) -> float:
	var tk := c.t_upper + 273.0
	var ta := _t_amb + 273.0
	var view := clampf(c.layer_depth / c.height, 0.0, 1.0)
	return STEFAN_BOLTZMANN * (tk * tk * tk * tk - ta * ta * ta * ta) * view


func _combust(c: Compartment, dt: float) -> void:
	var vent_q := _vent_limit * room_ah(c)
	c.combustion_eff = clampf((c.o2_percent() - _o2_min) / (_o2_full - _o2_min), 0.0, 1.0)
	# 불꽃이 약해지면 가연물을 가열하는 열도 줄어 열분해가 훈소 수준으로 느려진다
	var q_available := c.q_potential * (_smolder + (1.0 - _smolder) * c.combustion_eff)
	var q_flame := minf(q_available, vent_q) * c.combustion_eff
	# 타지 못한 열분해 가스는 미연소가스로 쌓이고(농도가 높을수록 둔화), 산소가 있으면 탄다 (문 개방 시 급연소)
	var saturation := maxf(0.0, 1.0 - c.gas_percent() / _gas_max_pct)
	var pyrolysis := (q_available - q_flame) / _fuel_heat * saturation
	var gas_burn := c.gas * _gas_burn * c.combustion_eff
	var q_total := q_flame + gas_burn * _fuel_heat
	var o2_mass := c.y_o2 * Compartment.AIR_DENSITY * c.volume
	var o2_use := q_total / _o2_heat * dt
	if o2_use > o2_mass * 0.5:
		var scale := o2_mass * 0.5 / o2_use
		q_total *= scale
		gas_burn *= scale
		o2_use *= scale
	c.q = q_total
	c.q_max = maxf(c.q_max, q_total)
	c.y_o2 = maxf(0.0, c.y_o2 - o2_use / (Compartment.AIR_DENSITY * c.volume))
	c.gas = maxf(0.0, c.gas + (pyrolysis - gas_burn) * dt)
	# 산소가 부족할수록 그을음이 많이 나온다
	c.soot += c.soot_rate * (1.0 + 2.0 * (1.0 - c.combustion_eff)) * dt
	if q_total > 0.0:
		var z := maxf(0.1, c.height - c.layer_depth)
		var m_plume := PLUME_COEFF * pow(CONVECTIVE_FRACTION * q_total, 1.0 / 3.0) * pow(z, 5.0 / 3.0)
		_add_layer(c, m_plume / _gas_density(c.t_upper) * dt)


func _flow(o: Opening, dt: float) -> void:
	if o.kind == Opening.Kind.STAIR:
		_exchange_air(o, _k_exchange * o.area * 0.5, dt)
		_layer_outflow_up(o, dt)
		return
	var ah := o.effective_ah(_closed_leak)
	if ah <= 0.0:
		return
	_exchange_air(o, _k_exchange * ah, dt)
	if o.is_open:
		_layer_outflow(o, o.room_a, o.room_b, dt)
		if o.room_b != Opening.OUTSIDE:
			_layer_outflow(o, o.room_b, o.room_a, dt)


## 개구부 양쪽의 산소 농도 차이만큼 공기가 섞인다.
func _exchange_air(o: Opening, m_exchange: float, dt: float) -> void:
	var a := comps[o.room_a]
	var mass_a := Compartment.AIR_DENSITY * a.volume
	var y_b := Compartment.O2_AMBIENT_MASS
	var mass_b := INF
	if o.room_b != Opening.OUTSIDE:
		y_b = comps[o.room_b].y_o2
		mass_b = Compartment.AIR_DENSITY * comps[o.room_b].volume
	var flow := m_exchange * (y_b - a.y_o2) * dt
	var limit := 0.4 * absf(y_b - a.y_o2) * minf(mass_a, mass_b)
	flow = clampf(flow, -limit, limit)
	a.y_o2 += flow / mass_a
	if o.room_b != Opening.OUTSIDE:
		comps[o.room_b].y_o2 -= flow / mass_b


## 연기층 하단이 개구부 상단보다 낮아지면 그 차이만큼 넘쳐 흐른다.
## 받는 쪽 연기층이 더 두꺼워도 그쪽이 더 차가우면 뜨거운 가스는 그 위로 계속 넘어간다 (부력·압력 차, 화재2 337쪽 중성대).
## 받는 쪽이 더 두껍고 비슷하게 뜨거울 때만 멈춘다.
func _layer_outflow(o: Opening, from: int, to: int, dt: float) -> void:
	var c := comps[from]
	if c.layer_depth <= 0.01:
		return
	if to != Opening.OUTSIDE and comps[to].layer_depth >= c.layer_depth and comps[to].t_upper >= c.t_upper - _hot_margin:
		return
	var bottom := c.height - c.layer_depth
	if bottom >= o.top:
		return
	var h := o.top - maxf(bottom, o.sill)
	var d_t := maxf(c.t_upper - _t_amb, 5.0)
	var rate := OUTFLOW_COEFF * o.width * sqrt(2.0 * G * d_t / (_t_amb + 273.0)) * pow(h, 1.5)
	_move_layer(c, to, rate * dt, dt)


## 계단: 아래층 연기층이 위층으로 올라간다. 수직 연기 속도가 교재 값(계단 초기 약 1.5m/s, 중기 3~4m/s, 화재2 330쪽)에
## 가깝도록 계수를 맞춘다 (stair_upflow_coeff·stair_upflow_depth_m). 위층으로 빨리 빠져나가 꼭대기부터 차는 모습이 된다 (SOP 223 1.3)
func _layer_outflow_up(o: Opening, dt: float) -> void:
	var c := comps[o.room_a]
	var upper := comps[o.room_b]
	if c.layer_depth <= 0.02 or c.t_upper < upper.t_upper - 1.0:
		return
	# 위층 계단이 연기로 꽉 차면 더 올라가지 못하고 아래층에 쌓인다 → 꼭대기부터 아래로 찬다
	if upper.layer_depth >= upper.height - STAIR_FULL_MARGIN_M:
		return
	var d_t := maxf(c.t_upper - _t_amb, 5.0)
	var rate := _stair_coeff * o.area * sqrt(2.0 * G * d_t / (_t_amb + 273.0)) * minf(1.0, c.layer_depth / _stair_depth) * stack_factor
	_move_layer(c, o.room_b, rate * dt, dt)


## 연기층 일부(부피 dv)를 그을음·가스·열과 함께 옮긴다.
func _move_layer(c: Compartment, to: int, dv: float, dt: float) -> void:
	var vol := c.layer_volume()
	if vol <= 0.0:
		return
	dv = minf(dv, vol * 0.3)
	var frac := dv / vol
	var soot_moved := c.soot * frac
	var gas_moved := c.gas * frac
	c.soot -= soot_moved
	c.gas -= gas_moved
	c.layer_depth -= dv / c.area
	if to == Opening.OUTSIDE:
		return
	var d := comps[to]
	d.soot += soot_moved
	d.gas += gas_moved
	d.toxicity = maxf(d.toxicity, c.toxicity)
	_add_layer(d, dv)
	d.imported_kw += _gas_density(c.t_upper) * dv / dt * CP * (c.t_upper - _t_amb)


func _update_temperature(c: Compartment, dt: float) -> void:
	var ah := room_ah(c)
	var surface := maxf(c.surface - ah, 1.0)
	# 방수 냉각은 들어오는 열의 일부까지만 상쇄한다 (불이 타는 동안 실내가 외기 온도까지 식지는 않음)
	var q_in := c.q + CONVECTIVE_FRACTION * c.imported_kw
	var q_eff := q_in - minf(c.cooling_kw, MAX_COOLING_SHARE * q_in)
	var rise := 0.0
	if q_eff > 0.0:
		rise = _mqh_coeff * pow(q_eff * q_eff / (ah * _h_k * surface), 1.0 / 3.0)
	# 최성기 상한 근처에서만 포화시킨다 (지수가 클수록 상한 아래에서는 MQH 값을 그대로 따른다)
	var max_rise := _t_max - _t_amb
	rise = rise / pow(1.0 + pow(rise / max_rise, SATURATION_EXPONENT), 1.0 / SATURATION_EXPONENT)
	var target := _t_amb + rise
	# 자연 냉각은 느리지만, 방수로 식히는 중에는 빠르게 내려간다
	var tau := _tau if target >= c.t_upper or c.cooling_kw > 0.0 else _tau * 3.0
	c.t_upper += (target - c.t_upper) * minf(1.0, dt / tau)
	var f := c.layer_depth / c.height
	c.t_lower = _t_amb + (c.t_upper - _t_amb) * f * f


func _add_layer(c: Compartment, dv: float) -> void:
	c.layer_depth = clampf(c.layer_depth + dv / c.area, 0.0, c.height - LAYER_MIN_CLEAR_M)


static func _gas_density(t_c: float) -> float:
	return 353.0 / (t_c + 273.0)
