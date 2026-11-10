class_name AerialSystem
extends RefCounted
## 굴절차 (기획안 6-1·P9, SOP 207·209·326): 전개해야 쓸 수 있는 고소 방수포와 바스켓 구조.
##   - 전개: 차가 멈춘 자리에서 아웃트리거·붐을 펴는 데 deploy_s가 걸린다. 차를 옮기면 다시 접어야 한다
##   - 닿는 곳: 창 높이((층-1)×3m + 1.5m)가 작업 높이(reach_m) 안이고, 차체에서 창까지 수평 거리가 outreach_m 안
##   - 낙하물 구역(유리·간판) 안에 서 있으면 전개를 미루고 알린다 (SOP 209 전개 공간 확인)
##   - 방수포: MonitorSystem이 굴절차도 받는다. 물은 feed_m 안의 펌프차 탱크에서 끌어온다
##   - 바스켓 구조: 창가의 요구조자에게 바스켓을 올려 태우고 내려온다. 바스켓이 오는 동안 그 사람은 뛰어내리지 않는다
## 수치는 data/units/vehicles.json "굴절차" (모두 추정, 검수 필요)

const FLOOR_M := 3.0
const SILL_M := 1.5


class Rescue:
	extends RefCounted
	var vehicle_id := -1
	var victim_id := -1
	var done_tick := 0


var fire: FireSim
var units: UnitSystem
var rescue: RescueSystem
var falls: FallSystem
var zones: ZoneSystem
var events: SimEventLog
## 전개가 끝나는(끝난) 틱 {차량 id: tick}. 없으면 접힌 상태
var deployed_at: Dictionary = {}
## 전개한 자리 (차가 움직이면 접힌다)
var _deployed_pos: Dictionary = {}
var rescues: Array[Rescue] = []


func _init(p_fire: FireSim, p_units: UnitSystem, p_rescue: RescueSystem, p_falls: FallSystem, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	rescue = p_rescue
	falls = p_falls
	events = p_events


func is_deployed(vehicle_id: int, tick: int) -> bool:
	return deployed_at.has(vehicle_id) and tick >= int(deployed_at[vehicle_id])


## 전개를 시작한다 (이미 했거나 하는 중이면 그대로). 끝나는 틱, 못 하면 -1
func deploy(v: Vehicle, tick: int) -> int:
	if v == null or not v.is_aerial() or v.away or v.is_moving():
		return -1
	if deployed_at.has(v.id):
		return int(deployed_at[v.id])
	# 낙하물 구역 안이면 전개하지 않는다 (차량·운전원 피해)
	for z: Dictionary in falls.zones:
		if v.pos.distance_to(z.center) <= float(z.radius) + v.length_cells * 0.5:
			events.add(tick, "aerial_debris", {"vehicle": _name(v), "driver": v.driver_label()})
			return -1
	var done := tick + roundi(v.deploy_s / SimClock.TICK_DT)
	deployed_at[v.id] = done
	_deployed_pos[v.id] = v.pos
	events.add(tick, "aerial_deploying", {"vehicle": _name(v), "driver": v.driver_label(), "seconds": roundi(v.deploy_s)})
	return done


## 이 개구부(창)에 바스켓·방수포가 닿는가. 닿으면 "", 아니면 이유
func reach_reason(v: Vehicle, level: int, cell: Vector2i) -> String:
	var h := (level - 1) * FLOOR_M + SILL_M
	if h > v.reach_m:
		return "높이 %dm — 작업 높이 %dm 넘음" % [roundi(h), roundi(v.reach_m)]
	var d := v.distance_to_body(Vector2(cell) + Vector2(0.5, 0.5)) * fire.building.cell_size_m
	if d > v.outreach_m:
		return "수평 거리 %dm — %dm 넘음 (차를 건물 가까이)" % [roundi(d), roundi(v.outreach_m)]
	return ""


## 방수포 물을 줄 펌프차 (feed_m 안에서 가장 가까운). 없으면 null
func feed_pump(v: Vehicle) -> Vehicle:
	var best: Vehicle = null
	var limit := v.feed_m / fire.building.cell_size_m
	for p in units.vehicles:
		if not p.is_pump() or p.away:
			continue
		var d := p.pos.distance_to(v.pos)
		if d <= limit and (best == null or d < best.pos.distance_to(v.pos)):
			best = p
	return best


## 바스켓 구조 지시. 시작했으면 true
func order_rescue(vehicle_id: int, victim_id: int, tick: int) -> bool:
	var v := units.get_vehicle(vehicle_id)
	if v == null or not v.is_aerial() or victim_id < 0 or victim_id >= rescue.victims.size():
		return false
	var vic := rescue.victims[victim_id]
	if not vic.discovered or not vic.alive() or vic.carried_by >= 0 or vic.level < 2:
		events.add(tick, "aerial_no_target", {"vehicle": _name(v)})
		return false
	if rescues.any(func(r: Rescue) -> bool: return r.vehicle_id == vehicle_id):
		events.add(tick, "aerial_busy", {"vehicle": _name(v)})
		return false
	var w := falls.window_near(vic.level, Vector2i(vic.pos.floor()))
	if w.x < 0:
		events.add(tick, "aerial_no_window", {"vehicle": _name(v), "who": vic.label()})
		return false
	var why := reach_reason(v, vic.level, w)
	if why != "":
		events.add(tick, "aerial_out_of_reach", {"vehicle": _name(v), "who": vic.label(), "reason": why})
		return false
	var ready := deploy(v, tick)
	if ready < 0:
		return false
	var r := Rescue.new()
	r.vehicle_id = vehicle_id
	r.victim_id = victim_id
	var climb_s := ((vic.level - 1) * FLOOR_M + SILL_M) / maxf(0.1, v.basket_mps)
	r.done_tick = maxi(tick, ready) + roundi((climb_s * 2.0 + v.basket_load_s) / SimClock.TICK_DT)
	rescues.append(r)
	falls.held[victim_id] = true
	events.add(tick, "aerial_rescue_start", {"vehicle": _name(v), "who": vic.label(), "floor": fire.building.floor_name(vic.level),
		"eta_s": roundi((r.done_tick - tick) * SimClock.TICK_DT)})
	return true


func step(tick: int) -> void:
	# 차가 움직이면 붐을 접는다 (바스켓 구조도 중단)
	for id: int in deployed_at.keys():
		var v := units.get_vehicle(id)
		if v == null or v.is_moving() or v.pos.distance_to(_deployed_pos[id]) > 0.5:
			deployed_at.erase(id)
			_deployed_pos.erase(id)
			for r in rescues.duplicate():
				if r.vehicle_id == id:
					rescues.erase(r)
					falls.held.erase(r.victim_id)
			events.add(tick, "aerial_stowed", {"vehicle": _name(v)})
		elif tick == int(deployed_at[id]):
			events.add(tick, "aerial_deployed", {"vehicle": _name(v), "driver": v.driver_label()})
	for r in rescues.duplicate():
		var vic := rescue.victims[r.victim_id]
		if not vic.alive() or vic.carried_by >= 0 or vic.state == Victim.State.RESCUED:
			rescues.erase(r)
			falls.held.erase(r.victim_id)
			continue
		if tick < r.done_tick:
			continue
		rescues.erase(r)
		falls.held.erase(r.victim_id)
		var v := units.get_vehicle(r.vehicle_id)
		# 바스켓에서 내려 환자 집결지(있으면)나 차 옆에 둔다
		var spot := Vector2(zones.casualty) + Vector2(0.5, 0.5) if zones and zones.casualty.x >= 0 else v.pos + Vector2(0.0, v.width_cells * 0.5 + 1.0)
		vic.pos = spot
		vic.level = 1
		vic.discovered = true
		vic.state_at_rescue = vic.state
		vic.state = Victim.State.RESCUED
		vic.rescued_tick = tick
		vic.dropoff = "굴절차"
		events.add(tick, "victim_rescued", {"who": vic.label(), "state": Victim.STATE_NAMES[vic.state_at_rescue], "by": _name(v) + " 바스켓"})


func _name(v: Vehicle) -> String:
	return v.display_name(units.squads[v.squad_id].name) if v else "굴절차"
