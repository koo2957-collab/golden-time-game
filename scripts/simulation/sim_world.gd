class_name SimWorld
extends RefCounted
## 시뮬레이션 전체 상태. 화면 노드에 의존하지 않는다.
## 명령은 issue()로 받아 다음 틱 시작 시 실행하고 기록한다.
## 한 틱의 순서: 명령(투입·지연 판정) → 문 작업 → 열기 접근 판정 → 진입 통제 → 이동 → 후착대 도착 → 대원 상태 → 구조(운반·검색) → 물 → 화재
##               → 특수현상 → 불씨·재발화 → 인접 건물·가스·붕괴 → 고수준 명령 → 요구조자 노출·발견 → 무전·보고 → (주기적으로) 시야

const DEFAULT_UNIT_STATS_PATH := "res://data/units/firefighter.json"
const FIRE_PARAMS_PATH := "res://data/fire/fire_params.json"
const MATERIALS_PATH := "res://data/materials/materials.json"
const VEHICLES_PATH := "res://data/units/vehicles.json"
const EMS_PARAMS_PATH := "res://data/units/ems_params.json"
const PHASE_PARAMS_PATH := "res://data/command/phase_params.json"
const CARDS_PATH := "res://data/cards/cards.json"
const CARD_PARAMS_PATH := "res://data/cards/card_params.json"
const HAZARD_PARAMS_PATH := "res://data/fire/hazard_params.json"
const RADIO_PARAMS_PATH := "res://data/command/radio_params.json"
const SURVEY_PARAMS_PATH := "res://data/command/survey_params.json"
const SAFETY_PARAMS_PATH := "res://data/command/safety_params.json"
## 시야는 이 틱마다 다시 계산한다 (0.3초)
const PERCEPTION_EVERY_TICKS := 3

var clock := SimClock.new()
## 시나리오 시드로 초기화되는 난수. 시뮬레이션의 모든 무작위 요소는 이것만 쓴다 (결정론).
var rng := RandomNumberGenerator.new()
var building: BuildingData
var pathfinder: Pathfinder
var units: UnitSystem
var fire: FireSim
var water: WaterSystem
var doors: DoorSystem
var conditions: CrewConditionSystem
var perception: Perception
var rescue: RescueSystem
var hazards: HazardSystem
var rekindle: RekindleSystem
var tactical: TacticalSystem
var exposure: ExposureSystem
var gas: GasSystem
var collapse: CollapseSystem
var ems: EmsSystem
var falls: FallSystem
var shafts: ShaftSystem
var evac: EvacSystem
var shuttle: ShuttleSystem
var phases: PhaseSystem
var cards: CardSystem
## 난이도 (기획안 8장): "훈련" 제한시간 2배·일시정지·배속 / "실전" 1배속 고정 / "악조건" 실전 + 강풍·후착대 지연·소화전 고장.
## 빈 문자열이면 시나리오 그대로 (자동 테스트). 화면의 시간 규칙(배속·일시정지)은 world가 이 값을 보고 정한다
var realism := ""
var _phase_params: ParamTable
var _card_training_factor := 2.0
var command: CommandSystem
var command_log := CommandLog.new()
var events := SimEventLog.new()
## 평가용 상태 기록 (1초마다)
var recorder := SimRecorder.new()
## 시나리오 원본 (평가 설정·숨은 정보 공개에 쓴다)
var scenario: Dictionary = {}
## 활동 종료 틱과 사유 (SOP 113-1.1). 끝나기 전이면 -1
var ended_tick := -1
var end_reason := ""
## 이 틱이 되면 활동을 자동으로 끝낸다 (-1: 제한 없음)
var time_limit_tick := -1
## 시나리오 파일 경로와 실제로 쓴 시드 (다시 하기에 쓴다)
var scenario_path := ""
var rng_seed := 0
## 내린 명령과 내린 틱 [{tick, command}]. 같은 시나리오에 같은 틱에 다시 넣으면 같은 결과가 나온다 (다시 하기)
var issued: Array[Dictionary] = []
## 플레이 방식 (평가·교육). 결과 기록용이며 시뮬레이션에는 영향이 없다
var play_mode := "평가"
## 명령 밖에서 상태를 바꾼 적이 있으면(개발용 발화·정보 안개 끄기) 다시 하기를 할 수 없다
var replayable := true

var _pending: Array = []


## vehicle_overrides: 차종 -> 제원 일부 (시나리오 vehicles). 기본 제원(vehicles.json)을 덮어쓰거나 새 차종을 더한다
static func create(building_path: String, roster_path: String, unit_stats_path := DEFAULT_UNIT_STATS_PATH, p_seed := 0, vehicle_overrides: Dictionary = {}) -> SimWorld:
	var building := BuildingData.from_file(building_path)
	var roster: Variant = JsonData.load_file(roster_path)
	var stats_data: Variant = JsonData.load_file(unit_stats_path)
	var vehicle_stats: Variant = JsonData.load_file(VEHICLES_PATH)
	var hazard_data: Variant = JsonData.load_file(HAZARD_PARAMS_PATH)
	if hazard_data is Dictionary:
		hazard_data = InstructorSettings.apply("hazard", hazard_data)
	var radio_data: Variant = JsonData.load_file(RADIO_PARAMS_PATH)
	var survey_data: Variant = JsonData.load_file(SURVEY_PARAMS_PATH)
	var safety_data: Variant = JsonData.load_file(SAFETY_PARAMS_PATH)
	var ems_data: Variant = JsonData.load_file(EMS_PARAMS_PATH)
	var phase_data: Variant = JsonData.load_file(PHASE_PARAMS_PATH)
	var card_data: Variant = JsonData.load_file(CARDS_PATH)
	var card_params: Variant = JsonData.load_file(CARD_PARAMS_PATH)
	if safety_data is Dictionary:
		safety_data = InstructorSettings.apply("safety", safety_data)
	if ems_data is Dictionary:
		ems_data = InstructorSettings.apply("ems", ems_data)
	var fire_config := FireConfig.load_files(FIRE_PARAMS_PATH, MATERIALS_PATH)
	if building == null or not roster is Dictionary or not stats_data is Dictionary or not vehicle_stats is Dictionary or not hazard_data is Dictionary or not radio_data is Dictionary or not survey_data is Dictionary or not safety_data is Dictionary or not ems_data is Dictionary or not phase_data is Dictionary or not card_data is Dictionary or not card_params is Dictionary or fire_config == null:
		return null
	var stats := ParamTable.from_dict(stats_data)
	for type: String in vehicle_overrides:
		var merged: Dictionary = vehicle_stats.get(type, {}).duplicate()
		merged.merge(vehicle_overrides[type], true)
		vehicle_stats[type] = merged
	var sim := SimWorld.new()
	sim.rng.seed = p_seed
	sim.building = building
	sim.pathfinder = Pathfinder.new(building)
	var speed_cells := stats.value("walk_speed_mps") / building.cell_size_m
	sim.units = UnitSystem.from_roster(roster, speed_cells, vehicle_stats, building.cell_size_m)
	sim.fire = FireSim.new(building, fire_config, sim.rng, sim.events)
	sim.water = WaterSystem.new(building, sim.units, sim.pathfinder, sim.fire, fire_config, sim.events)
	sim.doors = DoorSystem.new(sim.fire, sim.units, sim.pathfinder, stats, sim.events)
	sim.conditions = CrewConditionSystem.new(sim.fire, sim.units, sim.pathfinder, stats, sim.events)
	sim.perception = Perception.new(sim.fire, sim.units, stats)
	var hazard_params := ParamTable.from_dict(hazard_data)
	sim.rescue = RescueSystem.new(sim.fire, sim.units, sim.pathfinder, sim.perception, hazard_params, sim.events)
	sim.hazards = HazardSystem.new(sim.fire, sim.units, sim.rescue, sim.perception, hazard_params, sim.events)
	sim.rekindle = RekindleSystem.new(sim.fire, sim.units, sim.pathfinder, hazard_params, sim.events, p_seed)
	sim.exposure = ExposureSystem.new(sim.fire, sim.water, hazard_params, sim.events)
	sim.gas = GasSystem.new(sim.fire, sim.units, sim.pathfinder, hazard_params, sim.events)
	sim.collapse = CollapseSystem.new(sim.fire, sim.units, sim.rescue, hazard_params, sim.events)
	sim._phase_params = ParamTable.from_dict(phase_data)
	sim.phases = PhaseSystem.new(sim.fire, sim.units, sim.water, sim.rescue, sim.rekindle, sim.perception, ParamTable.from_dict(phase_data), sim.events)
	sim.shuttle = ShuttleSystem.new(sim.units, sim.water, sim.events)
	sim.shafts = ShaftSystem.new(sim.fire, sim.units, sim.water, hazard_params, sim.events)
	sim.evac = EvacSystem.new(sim.fire, sim.rescue, sim.pathfinder, hazard_params, sim.units.walk_speed_cells, sim.events)
	sim.falls = FallSystem.new(sim.fire, sim.exposure, sim.units, sim.rescue, sim.pathfinder, hazard_params, sim.events)
	sim.ems = EmsSystem.new(sim.units, sim.rescue, sim.pathfinder, ParamTable.from_dict(ems_data), sim.events)
	sim.command = CommandSystem.new(sim.fire, sim.units, sim.pathfinder, sim.rescue, sim.water, sim.doors, sim.perception, sim.clock, ParamTable.from_dict(radio_data), sim.events)
	sim.command.resources = ResourceSystem.new(sim.units, sim.pathfinder, sim.conditions, building, sim.events)
	var safety := SafetySystem.new(sim.fire, sim.units, sim.pathfinder, sim.rescue, sim.water, sim.doors, ParamTable.from_dict(safety_data), sim.events)
	safety.radio = sim.command.radio
	safety.org = sim.command.org
	safety.resources = sim.command.resources
	safety.entry_allowed = sim.command.entry_allowed
	sim.command.safety = safety
	sim.tactical = TacticalSystem.new(sim.fire, sim.units, sim.water, sim.doors, sim.rescue, sim.events)
	sim.tactical.safety = safety
	sim.tactical.perception = sim.perception
	sim.tactical.ems = sim.ems
	sim.cards = CardSystem.new(sim.units, sim.tactical, sim.doors, sim.rescue, sim.rekindle, sim.water, sim.fire,
		ParamTable.from_dict(card_params), card_data, sim.events, p_seed)
	sim._card_training_factor = ParamTable.from_dict(card_params).value("training_time_factor")
	sim.cards.sim = sim
	sim.command.survey = SiteSurvey.new(sim.fire, sim.units, sim.pathfinder, sim.command.resources, sim.command.commander, ParamTable.from_dict(survey_data), sim.events)
	sim.water.safe_cell = sim.conditions.safe_to_enter
	sim.rescue.water = sim.water
	sim.doors.on_door_opened = sim.hazards.on_door_opened
	sim.doors.on_door_approach = sim.hazards.on_door_approach
	sim.doors.window_break_s = hazard_params.value("window_break_s")
	sim.perception.update(0)
	return sim


## 시나리오 파일(data/scenarios/*.json)로 시뮬레이션을 만든다.
## command_rules가 false면 진입 명령 규칙·자동 감속·후착대 도착을 끈다 (지휘 절차와 상관없는 테스트용).
## seed_override가 0 이상이면 시나리오 seed 대신 쓴다 (판마다 다른 변형, 다시 하기).
static func from_scenario(path: String, command_rules := true, seed_override := -1) -> SimWorld:
	var data: Variant = JsonData.load_file(path)
	if not data is Dictionary:
		return null
	var sim := create(
		str(data.get("building", "")),
		str(data.get("roster", "")),
		str(data.get("unit_stats", DEFAULT_UNIT_STATS_PATH)),
		seed_override if seed_override >= 0 else int(data.get("seed", 0)),
		data.get("vehicles", {}))
	if sim:
		sim.scenario = data
		sim.scenario_path = path
		sim.rng_seed = seed_override if seed_override >= 0 else int(data.get("seed", 0))
		var limit := float(data.get("evaluation", {}).get("time_limit_s", -1))
		sim.time_limit_tick = roundi(limit / SimClock.TICK_DT) if limit > 0.0 else -1
		sim.fire.apply_scenario(data.get("fire", {}))
		sim.rescue.add_victims(data.get("victims", []), sim.rng)
		sim.command.apply_scenario(data)
		sim.exposure.apply_scenario(data)
		sim.gas.apply_scenario(data)
		sim.ems.apply_scenario(data)
		sim.shuttle.apply_scenario(data)
		if not command_rules:
			sim.command.entry_order_required = false
			sim.command.auto_slow = false
			sim.command.resources.clear_schedule()
		sim.doors.sync_blocking()
		sim.perception.update(0)
	return sim


## 난이도 적용 (시나리오를 불러온 직후, 진행 전에). 다시 하기도 같은 값으로 부른다
func apply_realism(name: String) -> void:
	realism = name
	# 임무형 내부 지휘는 모든 난이도에 적용 (R7, 2026-11-08 사용자 결정)
	command.interior.enabled = true
	var pp := _phase_params
	match name:
		"훈련":
			if time_limit_tick > 0:
				time_limit_tick = roundi(time_limit_tick * pp.value("training_time_factor"))
			cards.time_factor = _card_training_factor
		"악조건":
			var w: Dictionary = scenario.get("wind", {})
			var speed := maxf(float(w.get("speed_mps", 0.0)) * pp.value("harsh_wind_factor"), pp.value("harsh_wind_min_mps"))
			exposure.apply_scenario({"wind": {"from_deg": float(w.get("from_deg", 270.0)), "speed_mps": speed}})
			command.resources.delay_arrivals(pp.value("harsh_arrival_factor"))
			for i in building.hydrants.size():
				if not i in water.hydrants_out:
					water.hydrants_out.append(i)
			if not shuttle.available():
				shuttle.source_name = "원거리 소화전 (악조건)"
				shuttle.round_trip_s = pp.value("harsh_shuttle_round_trip_s")
	events.add(clock.tick, "realism", {"name": name})


func ended() -> bool:
	return ended_tick >= 0


## 활동 종료. 이후 시뮬레이션은 멈추고 디브리핑(Evaluator)으로 넘어간다.
func end_activity(reason: String) -> void:
	if ended():
		return
	ended_tick = clock.tick
	end_reason = reason
	clock.paused = true
	phases.on_ended(clock.tick)
	events.add(clock.tick, "activity_ended", {"reason": reason})


func issue(command: RefCounted) -> void:
	issued.append({"tick": clock.tick, "command": command})
	_pending.append(command)


## 실제 경과 시간만큼 틱을 진행한다.
func advance(delta: float) -> void:
	step_ticks(clock.consume(delta))


func step_ticks(n: int) -> void:
	for i in n:
		_step()


func _step() -> void:
	if ended():
		return
	var dt := SimClock.TICK_DT
	# 대기 중인 출동대 투입·통솔범위 지연으로 미룬 명령은 command가 골라 돌려준다
	var ready := command.gate(_pending, clock.tick)
	_pending.clear()
	for c in ready:
		c.tick = clock.tick
		c.execute(self)
		command_log.record(c)
	doors.step(dt, clock.tick)
	conditions.before_move(clock.tick)
	command.before_move(clock.tick)
	units.step(dt)
	command.after_move(dt, clock.tick)
	conditions.after_move(dt, clock.tick)
	rescue.step_after_move(dt, clock.tick)
	water.step(dt, clock.tick)
	fire.step(dt, clock.tick)
	hazards.step(clock.tick)
	rekindle.step(dt, clock.tick)
	exposure.step(dt, clock.tick)
	gas.step(dt, clock.tick)
	collapse.step(dt, clock.tick)
	shuttle.step(dt, clock.tick)
	phases.step(dt, clock.tick, command.declared(), time_limit_tick)
	cards.step(dt, clock.tick)
	shafts.step(dt, clock.tick)
	evac.step(dt, clock.tick)
	falls.step(dt, clock.tick)
	ems.step(dt, clock.tick)
	tactical.step(clock.tick)
	rescue.step_after_fire(dt, clock.tick)
	command.step(dt, clock.tick)
	if clock.tick % PERCEPTION_EVERY_TICKS == 0:
		perception.update(clock.tick)
	recorder.step(self, clock.tick)
	clock.tick += 1
	if time_limit_tick >= 0 and clock.tick >= time_limit_tick:
		end_activity("제한 시간 종료")
