class_name SimWorld
extends RefCounted
## 시뮬레이션 전체 상태. 화면 노드에 의존하지 않는다.
## 명령은 issue()로 받아 다음 틱 시작 시 실행하고 기록한다.
## 한 틱의 순서: 명령 → 문 작업 → 열기 접근 판정 → 이동 → 대원 상태 → 물 → 화재 → (주기적으로) 시야

const DEFAULT_UNIT_STATS_PATH := "res://data/units/firefighter.json"
const FIRE_PARAMS_PATH := "res://data/fire/fire_params.json"
const MATERIALS_PATH := "res://data/materials/materials.json"
const VEHICLES_PATH := "res://data/units/vehicles.json"
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
var command_log := CommandLog.new()
var events := SimEventLog.new()

var _pending: Array = []


static func create(building_path: String, roster_path: String, unit_stats_path := DEFAULT_UNIT_STATS_PATH, p_seed := 0) -> SimWorld:
	var building := BuildingData.from_file(building_path)
	var roster: Variant = JsonData.load_file(roster_path)
	var stats_data: Variant = JsonData.load_file(unit_stats_path)
	var vehicle_stats: Variant = JsonData.load_file(VEHICLES_PATH)
	var fire_config := FireConfig.load_files(FIRE_PARAMS_PATH, MATERIALS_PATH)
	if building == null or not roster is Dictionary or not stats_data is Dictionary or not vehicle_stats is Dictionary or fire_config == null:
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
	sim.water.safe_cell = sim.conditions.safe_to_enter
	sim.perception.update(0)
	return sim


## 시나리오 파일(data/scenarios/*.json)로 시뮬레이션을 만든다.
static func from_scenario(path: String) -> SimWorld:
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
	for command in _pending:
		command.tick = clock.tick
		command.execute(self)
		command_log.record(command)
	_pending.clear()
	doors.step(dt, clock.tick)
	conditions.before_move(clock.tick)
	units.step(dt)
	conditions.after_move(dt, clock.tick)
	water.step(dt, clock.tick)
	fire.step(dt, clock.tick)
	if clock.tick % PERCEPTION_EVERY_TICKS == 0:
		perception.update(clock.tick)
	clock.tick += 1
