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
## 세대별 변형·집기 세트 (기획안 4-2-1, P2-2)
var unit_layout: UnitAssembly
## 도어체크를 이미 보고한 문 (opening index)
var _door_clues_reported: Dictionary = {}
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
## 구역 지정: 안전구역·환자 집결지·진입통제선·분류소 (P10-2 ⓑ)
var zones: ZoneSystem
## 진입구 (P4-2): 바깥 출입문 목록, 급기측·배기측
var entries: EntryPoints
## 지휘관이 아는 것 — 무전으로 전달된 보고 (P10-1 전술상황판, CLAUDE.md 규칙 7)
var knowledge: KnowledgeBoard
var shafts: ShaftSystem
var evac: EvacSystem
var shuttle: ShuttleSystem
var phases: PhaseSystem
var cards: CardSystem
## 도면·구조 정보 (R8)
var plan: PlanIntel
## 방수포·송풍기 양압배연 (R11)
var monitors: MonitorSystem
var vent: VentSystem
## 지휘권 이양·비상용승강기 (R13)
var transfer: CommandTransfer
var elevator: ElevatorSystem
## 라이트라인·방향감각 상실 (지하층, R14)
var lifeline: LifelineSystem
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
## 종료 종류 (MissionEndChecker.END_*): 작전 완료 / 조기 종료 / 전소 / 미완료. 끝나기 전이면 ""
var end_type := ""
## 종료 조건 (기획안 8-3, P11-1). 시나리오 제한시간은 없다
var mission_end: MissionEndChecker
## 게임 메뉴로 멈춘 횟수 (기록만, 감점 없음 — 기획안 8-4)
var pause_count := 0
## 현장 시계 배속 (기획안 5-8, 난이도별). 화면(world)이 SimClock.speed로 쓴다. 테스트(난이도 없음)는 1
var field_scale := 1.0
## 신고 → 선착대 도착 (출동 단계, 기획안 4-4) / 발화 → 신고 지연(늦은 신고 preburn_s)
var dispatch_s := 0.0
var ignition_to_call_s := 0.0
var _dispatched := false
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
## unit_setup: 시나리오 units {mix, overrides} — 세대별 변형·집기 세트 (P2-2). 비우면 표준 평면 + 일반 집기
static func create(building_path: String, roster_path: String, unit_stats_path := DEFAULT_UNIT_STATS_PATH, p_seed := 0, vehicle_overrides: Dictionary = {}, unit_setup: Dictionary = {}) -> SimWorld:
	var building := BuildingData.from_file(building_path)
	var building_raw: Variant = JsonData.load_file(building_path)
	var layout := UnitAssembly.new()
	if building and building_raw is Dictionary:
		layout = UnitAssembly.apply(building, building_raw.get("units", {}), p_seed, unit_setup)
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
	sim.unit_layout = layout
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
	sim.mission_end = MissionEndChecker.new(sim.fire, sim.collapse, sim.phases, sim._phase_params, sim.events)
	sim.shuttle = ShuttleSystem.new(sim.units, sim.water, sim.events)
	sim.shafts = ShaftSystem.new(sim.fire, sim.units, sim.water, hazard_params, sim.events)
	sim.evac = EvacSystem.new(sim.fire, sim.rescue, sim.pathfinder, hazard_params, sim.units.walk_speed_cells, sim.events)
	sim.falls = FallSystem.new(sim.fire, sim.exposure, sim.units, sim.rescue, sim.pathfinder, hazard_params, sim.events)
	sim.ems = EmsSystem.new(sim.units, sim.rescue, sim.pathfinder, ParamTable.from_dict(ems_data), sim.events)
	sim.command = CommandSystem.new(sim.fire, sim.units, sim.pathfinder, sim.rescue, sim.water, sim.doors, sim.perception, sim.clock, ParamTable.from_dict(radio_data), sim.events)
	sim.zones = ZoneSystem.new(building, sim.units, sim.falls, ParamTable.from_dict(ems_data).value("triage_setup_s"),
		ParamTable.from_dict(safety_data).value("safe_zone_default_m"), sim.events)
	sim.command.resources = ResourceSystem.new(sim.units, sim.pathfinder, sim.conditions, building, sim.events)
	var safety := SafetySystem.new(sim.fire, sim.units, sim.pathfinder, sim.rescue, sim.water, sim.doors, ParamTable.from_dict(safety_data), sim.events)
	safety.radio = sim.command.radio
	safety.org = sim.command.org
	safety.resources = sim.command.resources
	safety.entry_allowed = sim.command.entry_allowed
	sim.command.safety = safety
	sim.command.zones = sim.zones
	sim.tactical = TacticalSystem.new(sim.fire, sim.units, sim.water, sim.doors, sim.rescue, sim.events)
	sim.tactical.safety = safety
	sim.tactical.perception = sim.perception
	sim.command.tactical = sim.tactical
	sim.tactical.ems = sim.ems
	sim.cards = CardSystem.new(sim.units, sim.tactical, sim.doors, sim.rescue, sim.rekindle, sim.water, sim.fire,
		ParamTable.from_dict(card_params), card_data, sim.events, p_seed)
	sim._card_training_factor = ParamTable.from_dict(card_params).value("training_time_factor")
	sim.cards.sim = sim
	sim.perception.commander = sim.command.commander
	# 호흡량 4단계·긴장 배율·출구까지 필요 공기 (R9, 기획안 5-6)
	sim.conditions.activity_of = sim.activity_level
	sim.conditions.emergency = func() -> bool: return sim.command.safety.emergency()
	sim.conditions.exits = sim.rescue.exit_cells
	sim.conditions.covered = sim.water.is_covered
	sim.monitors = MonitorSystem.new(sim.fire, sim.units, fire_config, sim.events)
	sim.vent = VentSystem.new(sim.fire, sim.units, fire_config, sim.events)
	sim.plan = PlanIntel.new(sim.fire, sim.units, sim.perception, sim.command.interior, sim.events)
	var building_data: Variant = JsonData.load_file(building_path)
	if building_data is Dictionary:
		# 세대 변형의 도면 차이를 더한다 (도면은 표준 평면만 보여 준다)
		var diffs: Array = building_data.get("plan_diffs", []).duplicate()
		for d in layout.plan_diffs:
			diffs.append(d)
		building_data["plan_diffs"] = diffs
		sim.plan.apply_building(building_data)
	sim._apply_unit_doors()
	sim.tactical.layout = layout
	sim.entries = EntryPoints.new(sim.fire, sim.exposure, building_data.get("entry_names", {}) if building_data is Dictionary else {})
	sim.tactical.entries = sim.entries
	sim.command.interior.entries = sim.entries
	sim.knowledge = KnowledgeBoard.new(sim.fire, sim.units, sim.rescue)
	sim.command.radio.on_delivered = sim.knowledge.on_message
	sim.command.org.on_delivered = sim.knowledge.on_message
	sim.transfer = CommandTransfer.new(sim)
	sim.elevator = ElevatorSystem.new(sim.fire, sim.units, sim.pathfinder, sim.events)
	sim.lifeline = LifelineSystem.new(sim.fire, sim.units, sim.pathfinder, hazard_params, sim.events)
	if building_data is Dictionary:
		sim.elevator.apply_building(building_data)
	sim.command.survey = SiteSurvey.new(sim.fire, sim.units, sim.pathfinder, sim.command.resources, sim.command.commander, ParamTable.from_dict(survey_data), sim.events)
	sim.water.safe_cell = sim.conditions.safe_to_enter
	sim.rescue.water = sim.water
	sim.rescue.zones = sim.zones
	sim.ems.zones = sim.zones
	sim.ems.fed_death = sim.rescue.fed_death()
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
		data.get("vehicles", {}),
		data.get("units", {}))
	if sim:
		sim.scenario = data
		sim.scenario_path = path
		sim.rng_seed = seed_override if seed_override >= 0 else int(data.get("seed", 0))
		sim.fire.apply_scenario(data.get("fire", {}))
		sim.fire.apply_season(str(data.get("season", "")))
		sim.rescue.add_victims(data.get("victims", []), sim.rng)
		sim.command.apply_scenario(data)
		sim.exposure.apply_scenario(data)
		sim.gas.apply_scenario(data)
		sim.ems.apply_scenario(data)
		sim.shuttle.apply_scenario(data)
		sim.transfer.apply_scenario(data)
		sim.lifeline.enabled = bool(data.get("lifeline", false))
		var ev: Dictionary = data.get("evac", {})
		if ev.has("refuge_level"):
			sim.evac.refuge_level = int(ev.refuge_level)
			sim.evac.refuge_cell = Vector2i(int(ev.refuge_cell[0]), int(ev.refuge_cell[1]))
		# 구조자 운반·집결지 카드는 지휘 규칙을 켠 판에서만 (P10-2 ⓒ)
		sim.rescue.dropoff_enabled = command_rules
		sim.tactical.nozzle_cards = command_rules
		if not command_rules:
			sim.command.entry_order_required = false
			sim.command.auto_slow = false
			sim.command.resources.clear_schedule()
		sim.doors.sync_blocking()
		# 늦게 신고된 화재: 출동 전에 불만 먼저 진행시킨다 (시나리오 fire.preburn_s, R10). 다시 하기도 같다
		var pre := float(data.get("fire", {}).get("preburn_s", 0.0))
		sim.ignition_to_call_s = pre
		for i in roundi(pre / SimClock.TICK_DT):
			sim.fire.step(SimClock.TICK_DT, 0)
		sim.perception.update(0)
	return sim


## 난이도 적용 (시나리오를 불러온 직후, 진행 전에). 다시 하기도 같은 값으로 부른다
func apply_realism(name: String) -> void:
	realism = name
	# 임무형 내부 지휘는 모든 난이도에 적용 (R7, 2026-11-08 사용자 결정)
	command.interior.enabled = true
	var pp := _phase_params
	# 현장 시계 배속 (기획안 5-8): 훈련 1.5 · 실전 2 · 악조건 2.5
	var fts: Dictionary = pp.params.get("field_time_scale", {})
	field_scale = float(fts.get("by_realism", {}).get(name, fts.get("value", 1.0))) if not fts.is_empty() else 1.0
	cards.clock_scale = field_scale
	_begin_dispatch()
	match name:
		"훈련":
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


## 리플레이 보기 (디브리핑, R12): 명령을 받지 않고 기록대로만 진행
var view_only := false
## 적용한 대원 성장 {이름: xp} (다시 하기에 넘긴다)
var growth: Dictionary = {}


## 대원 성장 적용 (CrewGrowth, R12): 이름별 경험치 단계의 공기·열 배율을 곱한다. 판 시작 때 한 번
func apply_growth(xp: Dictionary) -> void:
	if not growth.is_empty() or xp.is_empty():
		return
	growth = xp.duplicate()
	for ff in units.firefighters:
		var l := CrewGrowth.level_of(CrewGrowth.xp_of(growth, ff.name))
		ff.air_factor *= float(l.get("air", 1.0))
		ff.heat_factor *= float(l.get("heat", 1.0))
		ff.grade = str(l.get("name", ""))


## 출동 준비: 고른 적재 장비를 적용한다 (CommandOrder "loadout", 기획안 P9). 한 번만
var loadout: Array = []


func apply_loadout(items: Array, tick: int) -> void:
	if not loadout.is_empty():
		return
	var data: Variant = JsonData.load_file("res://data/units/equipment.json")
	var cap := int(data.get("capacity", 3)) if data is Dictionary else 3
	for key in items:
		if loadout.size() >= cap or str(key) in loadout:
			continue
		loadout.append(str(key))
		match str(key):
			"thermal_extra":
				for c in units.crews:
					if not c.thermal_camera and not ems.is_ems_crew(c.id):
						c.thermal_camera = true
						break
			"fire_door_breaker":
				doors.fire_door_factor_scale = 0.5
			"spare_cylinders":
				conditions.swap_scale = 0.5
			"gas_detector":
				if gas.has_gas():
					command.survey.add_hazard("가스 누출 (가스측정기 감지)", tick)
			"air_mat":
				falls.setup_scale = 0.5
			"high_rise_pack":
				building.outlet_hose_m += 15.0
	events.add(tick, "loadout", {"items": ", ".join(PackedStringArray(loadout))})


## 대원의 활동 단계 (호흡량): 0 대기·보행 40 / 1 수색·호스 전개 55 / 2 방수·파괴 65 / 3 구조·계단 80 ℓ/분 (기획안 5-6)
func activity_level(ff: Firefighter) -> int:
	if rescue.task_of_crew(ff.crew_id) is RescueSystem.CarryTask:
		return 3
	if ff.is_moving() and building.cell(ff.level, floori(ff.pos.x), floori(ff.pos.y)) == BuildingData.Cell.STAIRS:
		return 3
	var h := water.hose_of_crew(ff.crew_id)
	if (h and h.flowing) or doors.task_of_crew(ff.crew_id) != null:
		return 2
	return 1 if ff.is_moving() else 0


func ended() -> bool:
	return ended_tick >= 0


## 활동 종료. 이후 시뮬레이션은 멈추고 디브리핑(Evaluator)으로 넘어간다.
## p_type: MissionEndChecker.END_* (비우면 지휘관 선언으로 보고 작전 완료/조기 종료를 가린다)
func end_activity(reason: String, p_type := "") -> void:
	if ended():
		return
	ended_tick = clock.tick
	end_reason = reason
	end_type = p_type if p_type != "" else mission_end.declared_type(unsearched_rooms().size())
	clock.paused = true
	phases.on_ended(clock.tick)
	events.add(clock.tick, "activity_ended", {"reason": reason})


func issue(command: RefCounted) -> void:
	# 리플레이 보기에서는 플레이어 명령을 받지 않는다 (기록된 명령만 issue_replay로)
	if view_only:
		return
	issued.append({"tick": clock.tick, "command": command})
	_pending.append(command)


## 리플레이 보기: 기록된 명령을 그 틱에 넣는다 (R12)
func issue_replay(command: RefCounted) -> void:
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
	phases.step(dt, clock.tick, command.declared())
	cards.step(dt, clock.tick)
	shafts.step(dt, clock.tick)
	plan.step(dt, clock.tick)
	monitors.step(dt, clock.tick)
	transfer.step(clock.tick)
	elevator.step(clock.tick)
	lifeline.step(dt, clock.tick)
	vent.step(dt, clock.tick)
	evac.step(dt, clock.tick)
	falls.step(dt, clock.tick)
	ems.step(dt, clock.tick)
	zones.step(clock.tick)
	tactical.step(clock.tick)
	rescue.step_after_fire(dt, clock.tick)
	command.step(dt, clock.tick)
	if clock.tick % PERCEPTION_EVERY_TICKS == 0:
		perception.update(clock.tick)
		_check_door_clues(clock.tick)
		_check_estimates(clock.tick)
	recorder.step(self, clock.tick)
	clock.tick += 1
	var victims_waiting := false
	for v in rescue.victims:
		if v.alive():
			victims_waiting = true
	if mission_end.step(clock.tick, victims_waiting) == MissionEndChecker.END_BURNOUT:
		end_activity("전소 — 건물 %d%% 소실, 불이 스스로 꺼짐" % roundi(mission_end.loss_ratio() * 100.0), MissionEndChecker.END_BURNOUT)


## 출동 단계 (기획안 4-4): 신고부터 선착대 도착까지 4분 동안 불이 뒤에서 진행된다.
## 화면은 이 시간을 실제 약 90초로 보여 주지만, 결과가 늘 같도록(다시 하기·리플레이) 여기서 한 번에 계산한다
func _begin_dispatch() -> void:
	if _dispatched:
		return
	_dispatched = true
	dispatch_s = float(scenario.get("dispatch_s", _phase_params.value("dispatch_s")))
	for i in roundi(dispatch_s / SimClock.TICK_DT):
		fire.step(SimClock.TICK_DT, 0)
	perception.update(0)


## 신고 후 경과 (초) — 화면 시계 (기획안 4-4)
func since_call_s() -> float:
	return dispatch_s + clock.elapsed_seconds()


## 발화 후 경과 (초) — 디브리핑
func since_ignition_s() -> float:
	return ignition_to_call_s + since_call_s()


## 직하층 확인으로 추정한 세대에 들어가 보니 변형이 다르면 보고 (기획안 4-2-1: "구조가 다릅니다")
func _check_estimates(tick: int) -> void:
	for name: String in tactical.unit_estimates:
		var est: Dictionary = tactical.unit_estimates[name]
		if est.get("reported", false):
			continue
		var u := unit_layout.unit_named(name)
		if u.is_empty() or u.variant == est.variant:
			continue
		for c in fire.comps:
			if c.level == int(u.level) and c.display_name().contains(name) and perception.room_visible(c):
				est["reported"] = true
				events.add(tick, "estimate_differs", {"unit": name, "from": est.from, "actual": str(u.variant), "crew": "현장 대원"})
				break


## 세대 현관문 상태 (P2-2): 잠김 → 파괴 필요, 도어체크 → 안에 사람이 있다는 단서
func _apply_unit_doors() -> void:
	for u in unit_layout.units:
		var cell: Vector2i = u.front_door
		if cell.x < 0 or str(u.door) == "":
			continue
		var o := fire.opening_at(Vector3i(cell.x, cell.y, int(u.level)))
		if o == null:
			continue
		if u.door == "locked":
			o.is_open = false
			o.locked = true
		elif u.door == "door_check":
			o.door_check = true
	doors.sync_blocking()


## 대원이 도어체크 걸린 현관문을 보면 보고한다 (화재1: 요구조자가 있다고 판단)
func _check_door_clues(tick: int) -> void:
	for o in fire.openings:
		if not o.door_check or _door_clues_reported.has(o.index):
			continue
		var c: Vector2i = o.cells[0]
		if perception.enabled and not perception.is_crew_visible(o.level, c.x, c.y):
			continue
		_door_clues_reported[o.index] = true
		var u := unit_layout.unit_at(o.level, c + Vector2i(0, 0))
		if u.is_empty():
			for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
				u = unit_layout.unit_at(o.level, c + d)
				if not u.is_empty():
					break
		events.add(tick, "door_check_seen", {"unit": str(u.get("name", "세대")), "crew": "현장 대원", "level": o.level, "cell": [c.x, c.y, o.level]})


## 지휘관이 아는 미검색 구역: 발화층·직상층과 불이 붙었던 구획 가운데 검색 끝 보고가 없는 곳 (기획안 8-3 종료 경고)
func unsearched_rooms() -> Array[Compartment]:
	var levels := {}
	for c in fire.comps:
		if c.ever_burned and not fire.is_exposure_comp(c):
			levels[c.level] = true
			levels[c.level + 1] = true
	var out: Array[Compartment] = []
	for c in phases.search_targets():
		if c.searched_tick < 0 and (c.ever_burned or levels.has(c.level)):
			out.append(c)
	return out


## 지휘관이 연소 중으로 본 구획 (마지막으로 본 모습이 타고 있던 칸이 있는 곳, 종료 경고)
func seen_burning_rooms() -> Array[Compartment]:
	var out: Array[Compartment] = []
	for c in fire.comps:
		if fire.is_exposure_comp(c):
			continue
		for cell in c.cells:
			var i := fire.grid.index(c.level, cell.x, cell.y)
			if perception.is_seen(c.level, cell.x, cell.y) and perception.seen_burning[i] == 1:
				out.append(c)
				break
	return out
