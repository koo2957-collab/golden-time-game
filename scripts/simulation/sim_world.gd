class_name SimWorld
extends RefCounted
## 시뮬레이션 전체 상태. 화면 노드에 의존하지 않는다.
## 명령은 issue()로 받아 다음 틱 시작 시 실행하고 기록한다.
## 한 틱의 순서: 명령(투입·지연 판정) → 문 작업 → 열기 접근 판정 → 진입 통제 → 이동 → 후착대 도착 → 대원 상태 → 구조(운반·검색) → 물 → 화재
##               → 특수현상 → 요구조자 노출·발견 → 무전·보고 → (주기적으로) 시야

const DEFAULT_UNIT_STATS_PATH := "res://data/units/firefighter.json"
const FIRE_PARAMS_PATH := "res://data/fire/fire_params.json"
const MATERIALS_PATH := "res://data/materials/materials.json"
const VEHICLES_PATH := "res://data/units/vehicles.json"
const HAZARD_PARAMS_PATH := "res://data/fire/hazard_params.json"
const RADIO_PARAMS_PATH := "res://data/command/radio_params.json"
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
var command: CommandSystem
var command_log := CommandLog.new()
var events := SimEventLog.new()

var _pending: Array = []


static func create(building_path: String, roster_path: String, unit_stats_path := DEFAULT_UNIT_STATS_PATH, p_seed := 0) -> SimWorld:
	var building := BuildingData.from_file(building_path)
	var roster: Variant = JsonData.load_file(roster_path)
	var stats_data: Variant = JsonData.load_file(unit_stats_path)
	var vehicle_stats: Variant = JsonData.load_file(VEHICLES_PATH)
	var hazard_data: Variant = JsonData.load_file(HAZARD_PARAMS_PATH)
	var radio_data: Variant = JsonData.load_file(RADIO_PARAMS_PATH)
	var fire_config := FireConfig.load_files(FIRE_PARAMS_PATH, MATERIALS_PATH)
	if building == null or not roster is Dictionary or not stats_data is Dictionary or not vehicle_stats is Dictionary or not hazard_data is Dictionary or not radio_data is Dictionary or fire_config == null:
		return null
	var stats := ParamTable.from_dict(stats_data)
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
	sim.command = CommandSystem.new(sim.fire, sim.units, sim.pathfinder, sim.rescue, sim.water, sim.doors, sim.perception, sim.clock, ParamTable.from_dict(radio_data), sim.events)
	sim.command.resources = ResourceSystem.new(sim.units, sim.pathfinder, sim.conditions, building, sim.events)
	sim.water.safe_cell = sim.conditions.safe_to_enter
	sim.rescue.water = sim.water
	sim.doors.on_door_opened = sim.hazards.on_door_opened
	sim.doors.on_door_approach = sim.hazards.on_door_approach
	sim.doors.window_break_s = hazard_params.value("window_break_s")
	sim.perception.update(0)
	return sim


## 시나리오 파일(data/scenarios/*.json)로 시뮬레이션을 만든다.
## command_rules가 false면 진입 명령 규칙·자동 감속·후착대 도착을 끈다 (지휘 절차와 상관없는 테스트용).
static func from_scenario(path: String, command_rules := true) -> SimWorld:
	var data: Variant = JsonData.load_file(path)
	if not data is Dictionary:
		return null
	var sim := create(
		str(data.get("building", "")),
		str(data.get("roster", "")),
		str(data.get("unit_stats", DEFAULT_UNIT_STATS_PATH)),
		int(data.get("seed", 0)))
	if sim:
		sim.fire.apply_scenario(data.get("fire", {}))
		sim.rescue.add_victims(data.get("victims", []), sim.rng)
		sim.command.apply_scenario(data)
		if not command_rules:
			sim.command.entry_order_required = false
			sim.command.auto_slow = false
			sim.command.resources.clear_schedule()
		sim.doors.sync_blocking()
		sim.perception.update(0)
	return sim


func issue(command: RefCounted) -> void:
	_pending.append(command)


## 실제 경과 시간만큼 틱을 진행한다.
func advance(delta: float) -> void:
	step_ticks(clock.consume(delta))


func step_ticks(n: int) -> void:
	for i in n:
		_step()


func _step() -> void:
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
	rescue.step_after_fire(dt, clock.tick)
	command.step(dt, clock.tick)
	if clock.tick % PERCEPTION_EVERY_TICKS == 0:
		perception.update(clock.tick)
	clock.tick += 1
