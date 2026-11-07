class_name CollapseSystem
extends RefCounted
## 노후 벽돌조 붕괴 (SOP 214-1.2, 214-2.5, 205). 화재 건물이 벽돌조이면, 최성기 상태로 오래 탄 구획부터 붕괴가 진행된다.
##   징후 (205-2.2 폭음·균열음·건물 진동): 진행이 정해진 비율에 이르면 알린다
##   붕괴: 그 구획 안의 대원은 행동 불능, 요구조자는 사망
## 붕괴 징후가 보이면 대원을 건물 밖으로 철수시켜야 한다 (205-3.5).

var fire: FireSim
var units: UnitSystem
var rescue: RescueSystem
var events: SimEventLog
var enabled := false
## 구획 index -> 붕괴 진행 (0~1)
var progress: Dictionary = {}
var signed: Dictionary = {}
var collapsed: Dictionary = {}

var _rate: float
var _sign: float


func _init(p_fire: FireSim, p_units: UnitSystem, p_rescue: RescueSystem, params: ParamTable, p_events: SimEventLog) -> void:
	fire = p_fire
	units = p_units
	rescue = p_rescue
	events = p_events
	_rate = 1.0 / maxf(1.0, params.value("collapse_s"))
	_sign = params.value("collapse_sign_ratio")
	enabled = fire.building.structure.contains("벽돌")


func first_sign_tick() -> int:
	var t := -1
	for e in events.of_type("collapse_sign"):
		if t < 0 or int(e.tick) < t:
			t = int(e.tick)
	return t


func step(dt: float, tick: int) -> void:
	if not enabled:
		return
	for c in fire.comps:
		if collapsed.has(c.index) or fire.building.is_exposure(c.rect.position.x, c.rect.position.y):
			continue
		if not (c.stage == Compartment.Stage.FULLY_DEVELOPED or c.stage == Compartment.Stage.FLASHOVER):
			continue
		var p: float = progress.get(c.index, 0.0) + _rate * dt
		progress[c.index] = p
		if p >= _sign and not signed.has(c.index):
			signed[c.index] = true
			events.add(tick, "collapse_sign", {"room": c.display_name(), "crew": "현장 대원"})
		if p >= 1.0:
			_collapse(c, tick)


func _collapse(c: Compartment, tick: int) -> void:
	collapsed[c.index] = true
	events.add(tick, "collapse", {"room": c.display_name(), "crew": "현장 대원"})
	for ff in units.firefighters:
		if ff.incapacitated:
			continue
		if fire.compartment_at(ff.level, floori(ff.pos.x), floori(ff.pos.y)) == c:
			ff.incapacitated = true
			ff.path.clear()
			var crew := units.get_crew(ff.crew_id)
			events.add(tick, "ff_down", {"crew": "%s %d조 %s" % [units.squads[ff.squad_id].name, crew.number, ff.name], "reason": "붕괴"})
	for v in rescue.victims:
		if v.alive() and v.carried_by < 0 and fire.compartment_at(v.level, floori(v.pos.x), floori(v.pos.y)) == c:
			v.state = Victim.State.DEAD
			events.add(tick, "victim_state", {"who": v.label(), "state": Victim.STATE_NAMES[Victim.State.DEAD], "reason": "붕괴"})
