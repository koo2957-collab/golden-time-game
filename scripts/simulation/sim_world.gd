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
const COMMANDS_PATH := "res://data/commands.json"
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
## 출동대 종류 → 기본 임무 (data/commands.json, 처음 쓸 때 읽는다)
var _default_missions: Dictionary = {}
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
var _fetch_s := 10.0
var shafts: ShaftSystem
var evac: EvacSystem
var shuttle: ShuttleSystem
var phases: PhaseSystem
var cards: CardSystem
## 도면·구조 정보 (R8)
var plan: PlanIntel
## 방수포·송풍기 양압배연 (R11)
var monitors: MonitorSystem
## 굴절차 전개·바스켓 구조 (P9)
var aerial: AerialSystem
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
## 판단 중 정지 (2026-11-15): 무전 장면·지휘 창이 떠 있는 동안 현장 시계를 멈추는 난이도인가 (훈련·실전 = true, 악조건 = false).
## 시계를 멈추는 것은 화면(World)이 한다 — 시뮬레이션은 값만 들고 있다
var decision_pause := true
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
	sim.units.line_gap_cells = maxi(1, roundi(stats.value("line_gap_m") / building.cell_size_m))
	# 휴대 장비 (P4-1): 출동대 종류별 기본 장비. 이미 만든 조에도 나눠 준다
	var equip: Variant = JsonData.load_file("res://data/units/equipment.json")
	if equip is Dictionary:
		sim.units.default_items = equip.get("default_items", {})
		for c in sim.units.crews:
			for k in sim.units.default_items.get(sim.units.squads[c.squad_id].type, []):
				if not str(k) in c.items:
					c.items.append(str(k))
		sim._fetch_s = float(equip.get("fetch", {}).get("value", 10.0))
	sim.fire = FireSim.new(building, fire_config, sim.rng, sim.events)
	sim.water = WaterSystem.new(building, sim.units, sim.pathfinder, sim.fire, fire_config, sim.events)
	sim.doors = DoorSystem.new(sim.fire, sim.units, sim.pathfinder, stats, sim.events)
	sim.conditions = CrewConditionSystem.new(sim.fire, sim.units, sim.pathfinder, stats, sim.events)
	sim.perception = Perception.new(sim.fire, sim.units, stats)
	var hazard_params := ParamTable.from_dict(hazard_data)
	sim.rescue = RescueSystem.new(sim.fire, sim.units, sim.pathfinder, sim.perception, hazard_params, sim.events)
	sim.rescue.safe_at = sim.conditions.safe_to_enter
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
	sim.collapse.perception = sim.perception
	sim.rekindle.perception = sim.perception
	sim.ems = EmsSystem.new(sim.units, sim.rescue, sim.pathfinder, ParamTable.from_dict(ems_data), sim.events)
	sim.command = CommandSystem.new(sim.fire, sim.units, sim.pathfinder, sim.rescue, sim.water, sim.doors, sim.perception, sim.clock, ParamTable.from_dict(radio_data), sim.events)
	sim.zones = ZoneSystem.new(building, sim.units, sim.falls, ParamTable.from_dict(ems_data).value("triage_setup_s"),
		ParamTable.from_dict(safety_data).value("safe_zone_default_m"), sim.events)
	sim.command.resources = ResourceSystem.new(sim.units, sim.pathfinder, sim.conditions, building, sim.events)
	sim.command.resources.commander = sim.command.commander
	var safety := SafetySystem.new(sim.fire, sim.units, sim.pathfinder, sim.rescue, sim.water, sim.doors, ParamTable.from_dict(safety_data), sim.events)
	safety.radio = sim.command.radio
	safety.org = sim.command.org
	safety.resources = sim.command.resources
	safety.entry_allowed = sim.command.entry_allowed
	sim.command.safety = safety
	sim.command.zones = sim.zones
	# 놓인 관창을 잡으러 건물 안으로 가도 되는가 (진입 허가·진입 금지 요소, 2026-11-24 검사)
	sim.water.take_allowed = sim.command.can_take_hose
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
	sim.conditions.on_heat_stop = sim._on_heat_stop
	sim.tactical.heat_ok = sim.conditions.safe_to_enter
	# 열기에 막힌 철수: 길이 열리면 다시 잇는다 (2026-11-25)
	safety.way_reopened = sim.conditions.way_reopened
	safety.note_blocked = sim.conditions.note_blocked
	safety.other_duty = sim._has_other_duty
	sim.tactical.exposure_heat = sim.exposure.heat_near
	sim.monitors =MonitorSystem.new(sim.fire, sim.units, fire_config, sim.events)
	sim.aerial = AerialSystem.new(sim.fire, sim.units, sim.rescue, sim.falls, sim.events)
	sim.aerial.zones = sim.zones
	sim.monitors.aerial = sim.aerial
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
	sim.command.on_seen = sim.knowledge.apply
	# 지휘소 (P4-4): 지휘소를 떠나 이동지휘 중이면 상황판 갱신이 늦고 일상 보고를 놓친다
	# 층·계단 고르기 (P4-5)
	sim.command.stairs = StairCores.new(building)
	sim.command.exposure = sim.exposure
	sim.command.post = CommandPost.new(sim.command, sim.units, sim.pathfinder, ParamTable.from_dict(radio_data), sim.events, building.cell_size_m)
	sim.zones.post = sim.command.post
	var deliver := sim.command.post.wrap(sim.knowledge.on_message)
	sim.command.radio.on_delivered = deliver
	sim.command.org.on_delivered = deliver
	sim.transfer = CommandTransfer.new(sim)
	sim.elevator = ElevatorSystem.new(sim.fire, sim.units, sim.pathfinder, sim.events)
	sim.lifeline = LifelineSystem.new(sim.fire, sim.units, sim.pathfinder, hazard_params, sim.events)
	if building_data is Dictionary:
		sim.elevator.apply_building(building_data)
	sim.falls.commander = sim.command.commander
	sim.command.survey = SiteSurvey.new(sim.fire, sim.units, sim.pathfinder, sim.command.resources, sim.command.commander, ParamTable.from_dict(survey_data), sim.events)
	# 층 검색은 구조대상자가 있다고 들은 방부터 (같은 사전을 같이 쓴다)
	sim.tactical.reported_rooms = sim.command.survey.reported_rooms
	sim.water.safe_cell = sim.conditions.safe_to_enter
	sim.rescue.water = sim.water
	sim.rescue.zones = sim.zones
	sim.ems.zones = sim.zones
	sim.ems.fed_death = sim.rescue.fed_death()
	sim.doors.on_door_opened = sim.hazards.on_door_opened
	sim.doors.on_door_approach = sim.hazards.on_door_approach
	sim.doors.window_break_s = hazard_params.value("window_break_s")
	sim.doors.set_fetch_s(sim._fetch_s)
	# 층 임무 '화재진압'이 그 층에 닿았을 때 보이는 불이 없으면 잔불정리로 바뀐다
	sim.command.floor_overhaul = sim._start_floor_overhaul
	sim.command.floor_watch = sim.rekindle.order_watch
	sim.tactical.knockdown_tick = func() -> int: return sim.phases.knockdown_tick
	sim.perception.update(0)
	return sim


## 초진 보고 뒤 그 층에 보이는 불이 없으면: 처음 잔불정리할 방의 칸 (탄 자리가 있고 아직 잔불정리하지 않은 방 중
## from에서 가까운 곳 — 그 뒤는 RekindleSystem이 그 층을 차례로 잇는다). 없으면 (-1, -1, -1). (기획안 9-1)
func floor_overhaul_target(lv: int, from: Vector2) -> Vector3i:
	var none := Vector3i(-1, -1, -1)
	if phases.knockdown_tick < 0:
		return none
	var grid := fire.grid
	for room in fire.comps:
		if room.level != lv:
			continue
		for c in room.cells:
			if perception.enabled and not perception.is_seen(lv, c.x, c.y):
				continue
			if grid.state[grid.index(lv, c.x, c.y)] == FuelGrid.State.BURNING:
				return none
	return rekindle.next_floor_room(lv, from)


## 층 임무 화재진압이 그 층에 닿았을 때: 잔불정리할 곳이 있으면 층 단위 잔불정리를 시작하고 true
func _start_floor_overhaul(crew_id: int, lv: int, tick: int) -> bool:
	var c := units.get_crew(crew_id)
	if c == null:
		return false
	var target := floor_overhaul_target(lv, c.leader.pos)
	return target.x >= 0 and rekindle.order_overhaul(crew_id, target, tick, true)


## 임무를 마친 분대에게 줄 다음 임무 (완료 보고 카드 MISSION-DONE-01의 '다음 임무', 2026-11-17).
## 지휘관이 아는 정보로만 고른다: 본 불(seen_burning_rooms)·잔불정리할 곳·검색을 마치지 않은 층.
##   기본 임무가 화재진압인 분대(진압대): 본 불이 있는 가까운 층 → 초진 뒤 잔불정리할 층 → 검색
##   그 밖: 검색 — 화점층 → 직상층 → 최상층 → 나머지 (SOP 202-3.1.2). 초진 뒤에는 2차 검색
## {kind: "attack"·"search", level, text} — 없으면 {}. 옆 건물에 들어가 있는 분대는 지휘관이 정한다
func next_task(crew_id: int) -> Dictionary:
	var c := units.get_crew(crew_id)
	if c == null or c.solo or ems.is_ems_crew(crew_id):
		return {}
	var here := fire.compartment_at(c.leader.level, floori(c.leader.pos.x), floori(c.leader.pos.y))
	if here and fire.is_exposure_comp(here):
		return {}
	var lv := c.leader.level
	var near_first := building.levels().duplicate()
	near_first.sort_custom(func(a: int, b: int) -> bool: return absi(a - lv) < absi(b - lv) or (absi(a - lv) == absi(b - lv) and a > b))
	if _default_mission(c) == "attack":
		var best := -1
		var cleared: Dictionary = _cleared_levels()
		for r in seen_burning_rooms():
			# 화점 진압 완료를 보고받은 층은 마지막 모습이 '타는 중'으로 남아 있어도 뺀다 (그 뒤 화점 발견·재발화 보고가 없으면)
			if cleared.has(r.level):
				continue
			if best < 0 or absi(r.level - lv) < absi(best - lv):
				best = r.level
		if best >= 0:
			return {"kind": "attack", "level": best, "text": "%s 화재진압" % building.floor_name(best)}
		if phases.knockdown_tick >= 0:
			for l: int in near_first:
				if floor_overhaul_target(l, c.leader.pos).x >= 0:
					return {"kind": "attack", "level": l, "text": "%s 잔불정리" % building.floor_name(l)}
	var fl := fire_floor_reported()
	var levels := building.levels()
	var order: Array = [fl, fl + 1, levels.max()]
	for l: int in levels:
		order.append(l)
	var after := phases.knockdown_tick
	for l: int in order:
		if not building.has_level(l):
			continue
		for room in fire.comps:
			if room.level == l and not room.cells.is_empty() and not fire.is_exposure_comp(room) and not tactical.room_searched(room, after):
				return {"kind": "search", "level": l, "text": "%s %s" % [building.floor_name(l), "2차 검색" if after >= 0 else "인명검색"]}
	return {}


## 화점 진압 완료를 보고받은 층 {층: 틱} — 그 뒤에 그 층의 화점 발견·재발화 보고가 오면 다시 뺀다 (2026-11-17:
## 방금 끈 방이 연기 때문에 '마지막으로 본 모습 = 타는 중'으로 남아 다음 임무로 같은 층 화재진압을 권하던 것).
## 화재진압하러 갔다가 '화점을 찾지 못함'을 보고한 층도 같다 (2026-11-18)
func _cleared_levels() -> Dictionary:
	var out := {}
	for e in events.entries:
		match str(e.type):
			"tactical_done":
				if bool(e.get("final", false)) and str(e.get("mission", "")) == "attack":
					out[int(e.level)] = int(e.tick)
			"tactical_halt":
				var t: Array = e.get("target", [])
				if str(e.get("kind", "")) == "no_fire" and t.size() >= 3:
					out[int(t[2])] = int(e.tick)
			"fire_found", "rekindle_found":
				var room := _comp_named(str(e.get("room", "")))
				if room and out.has(room.level) and int(e.tick) > int(out[room.level]):
					out.erase(room.level)
	return out


func _comp_named(name: String) -> Compartment:
	for c in fire.comps:
		if c.display_name() == name:
			return c
	return null


## 그 분대가 할 일 없이 서 있는가 — 임무·운반·문 작업·잔불정리·층 이동·진입구 접근·방수·걷기가 없고 현장에 내려 있음.
## 완료 보고 카드(CardSystem)와 화면의 '대기' 표시가 같이 쓴다 (2026-11-17)
func squad_idle(crew_id: int) -> bool:
	var c := units.get_crew(crew_id)
	if c == null or c.solo or c.leader.incapacitated or c.leader.aboard or c.leader.is_moving():
		return false
	if tactical.task_of_crew(crew_id) or rescue.task_of_crew(crew_id) or doors.task_of_crew(crew_id) or rekindle.task_of_crew(crew_id) \
			or rekindle.watch_of_crew(crew_id):
		return false
	var h := water.hose_of_crew(crew_id)
	if h and h.flowing:
		return false
	return not command.floor_goals.has(crew_id) and not command.approach.has(crew_id) and not command.resources.is_en_route(c.squad_id)


## 출동대 종류의 기본 임무 (data/commands.json default_mission — 진압대 attack, 구조대 search)
func _default_mission(c: Crew) -> String:
	if _default_missions.is_empty():
		var data: Variant = JsonData.load_file(COMMANDS_PATH)
		if data is Dictionary and data.get("default_mission", {}).get("by_type") is Dictionary:
			_default_missions = data.default_mission.by_type
	return str(_default_missions.get(units.squads[c.squad_id].type, ""))


## 시나리오 파일(data/scenarios/*.json)로 시뮬레이션을 만든다.
## command_rules가 false면 진입 명령 규칙·자동 감속·후착대 도착을 끈다 (지휘 절차와 상관없는 테스트용).
## seed_override가 0 이상이면 시나리오 seed 대신 쓴다 (판마다 다른 변형, 다시 하기).
static func from_scenario(path: String, command_rules := true, seed_override := -1) -> SimWorld:
	# 발화층 토큰({F})을 시드로 푼다 (P9, ScenarioVariant). 시드를 따로 주지 않으면 기본 발화층
	var data: Variant = ScenarioVariant.read(path, seed_override)
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
		# 외부 안전구역 안내 거리 (SOP 213-2.7.1): 신고된 발화층·풍속으로
		var hz := ParamTable.from_dict(JsonData.load_file(HAZARD_PARAMS_PATH))
		sim.zones.set_guide(sim.fire_floor_reported(), sim.building.levels().max(), float(data.get("wind", {}).get("speed_mps", 0.0)),
			hz.value("safe_zone_strong_wind_mps"), hz.value("floor_height_m"))
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
	# 지시 방식 (2026-11-11 사용자 결정 ③): 훈련 = 바로 실행 · 실전 = 바로 실행 + 통솔범위 지연 · 악조건 = 무전이 끝나야 실행
	command.set_order_mode(name != "악조건", name != "훈련")
	# 없는 장비는 차량에 가서 가져와야 한다, 처음 차량은 한 대씩 들어온다 (P4-1, 실제 플레이에서만)
	doors.require_equipment = true
	command.resources.arrival_drive = true
	command.resources.prepare_arrival()
	var pp := _phase_params
	# 현장 시계 기본 배속 (2026-11-15: 모두 1배 — 플레이 중 배속 단추로 올린다)
	var fts: Dictionary = pp.params.get("field_time_scale", {})
	field_scale = float(fts.get("by_realism", {}).get(name, fts.get("value", 1.0))) if not fts.is_empty() else 1.0
	cards.clock_scale = field_scale
	var dp: Dictionary = pp.params.get("decision_pause", {})
	decision_pause = float(dp.get("by_realism", {}).get(name, dp.get("value", 1.0))) > 0.0 if not dp.is_empty() else true
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


# --- 분대 편성: 2개 조로 나누기 · 합치기 (2026-11-16 결정 — docs/decisions.md '분대', 팀장 둥근 버튼) ---

## 무전으로 보낸 편성 지시가 아직 닿지 않은 분대 {출동대 id: true}
var _regroup_pending: Dictionary = {}
## 받을 조가 없어 차에 실어 둔 열화상카메라 수 (출동 준비 '열화상카메라 1대 추가') — 분대를 나누면 카메라 없는 조가 든다
var spare_thermal := 0


## 이 조가 일을 맡고 있으면 그 이유 ("" = 쉬는 중) — 합칠 때 들어오는 조는 쉬고 있어야 한다
func crew_busy(crew_id: int) -> String:
	var c := units.get_crew(crew_id)
	if c == null or c.list.is_empty():
		return ""
	if c.leader.aboard:
		return "차량·승강기에 타고 있음"
	if water.held_hose(crew_id) != null:
		return "수관을 잡고 있음"
	var rt: RefCounted = rescue.task_of_crew(crew_id)
	if rt is RescueSystem.CarryTask:
		return "구조대상자를 옮기는 중"
	if rt != null:
		return "인명검색 중"
	if tactical.task_of_crew(crew_id) != null:
		return "임무 중"
	if doors.task_of_crew(crew_id) != null or doors.fetches.any(func(f: Dictionary) -> bool: return int(f.crew) == crew_id):
		return "문 작업 중"
	if command.safety.role_of(crew_id) != SafetySystem.Role.NONE or command.safety.role_pending(crew_id):
		return "안전 임무(RIT·현장안전담당)를 맡고 있음"
	if cards.queue.any(func(q: CardSystem.Card) -> bool: return q.crew_id == crew_id):
		return "질문에 답을 기다리는 중"
	if rekindle.task_of_crew(crew_id) != null:
		return "잔불 정리 중"
	if rekindle.watch_of_crew(crew_id) != null:
		return "재발화 감시 중"
	if vent != null and vent.crew_id == crew_id:
		return "송풍기 배연 중"
	if gas.workers.has(crew_id):
		return "가스 차단 중"
	if command.post != null and command.post.jobs.any(func(j: Dictionary) -> bool: return int(j.crew) == crew_id):
		return "구역 설치 중"
	return ""


## 편성 지시를 할 수 없는 이유 ("" = 할 수 있다). split: true 나누기 / false 합치기
func regroup_reason(squad_id: int, split: bool) -> String:
	if squad_id < 0 or squad_id >= units.squads.size():
		return "없는 출동대"
	var squad := units.squads[squad_id]
	if command.resources.is_en_route(squad_id) or squad.crews.is_empty():
		return "아직 현장에 없음"
	if _regroup_pending.has(squad_id):
		return "앞의 편성 지시가 전달되는 중"
	if units.solo_of(squad) != null:
		return "한 명이 나가 있음 — 복귀시킨 뒤에"
	if split:
		if squad.crews.size() != 1:
			return "이미 나뉘어 있음"
		var c := squad.crews[0]
		if c.list.size() != 4:
			return "4명 분대만 2인 1조 둘로 나눌 수 있음 (%d명)" % c.list.size()
		if c.list.any(func(ff: Firefighter) -> bool: return ff.incapacitated):
			return "쓰러진 대원이 있음"
		if c.leader.aboard:
			return "차량·승강기에 타고 있음"
		if rescue.task_of_crew(c.id) is RescueSystem.CarryTask:
			return "구조대상자를 옮기는 중"
		return ""
	if squad.crews.size() != 2:
		return "나뉘어 있지 않음"
	if _merge_keeper(squad) == null:
		return "두 조 모두 임무 중 — 한 조를 대기·철수시킨 뒤 합치기 (%s: %s)" % [units.crew_short(squad.crews[1]), crew_busy(squad.crews[1].id)]
	return ""


## 합칠 때 남는 조: 한 조만 쉬고 있으면 일하는 조(쉬는 조가 합류), 둘 다 쉬면 1조. 둘 다 일하면 null
func _merge_keeper(squad: Squad) -> Crew:
	var a := squad.crews[0]
	var b := squad.crews[1]
	var a_busy := crew_busy(a.id) != ""
	var b_busy := crew_busy(b.id) != ""
	if a_busy and b_busy:
		return null
	return b if b_busy else a


## 편성 지시 (CommandOrder "regroup"): 할 수 없으면 이유를 기록하고, 할 수 있으면 무전으로 지시한다 — 닿아야 바뀐다
func order_regroup(squad_id: int, split: bool, tick: int) -> bool:
	var why := regroup_reason(squad_id, split)
	if why != "":
		var who := units.squads[squad_id].name if squad_id >= 0 and squad_id < units.squads.size() else ""
		events.add(tick, "regroup_rejected", {"squad": who, "what": "나누기" if split else "합치기", "reason": why})
		return false
	var squad := units.squads[squad_id]
	_regroup_pending[squad_id] = true
	var body := "2개 조로 나눠 활동하라." if split else "다시 한 분대로 합쳐 활동하라."
	command.radio.send(Radio.Priority.TACTICS, CommandSystem.COMMANDER, squad.name, body, tick, _on_regroup.bind(squad_id, split))
	return true


func _on_regroup(tick: int, squad_id: int, split: bool) -> void:
	_regroup_pending.erase(squad_id)
	var squad := units.squads[squad_id]
	# 전달되는 사이 상황이 바뀌었으면 하지 않는다
	var why := regroup_reason(squad_id, split)
	if why != "":
		events.add(tick, "regroup_rejected", {"squad": squad.name, "what": "나누기" if split else "합치기", "reason": why})
		return
	if split:
		var made: Crew = units.split_squad(squad)
		if made == null:
			return
		if not made.thermal_camera and spare_thermal > 0:
			made.thermal_camera = true
			spare_thermal -= 1
		command._decide(tick, "분대 나누기 — %s (2인 1조 둘)" % squad.name)
		events.add(tick, "squad_split", {"squad": squad.name, "crew": units.crew_name(made), "crew_id": made.id,
			"first": _names(squad.crews[0]), "second": _names(squad.crews[1])})
		command.radio.send(Radio.Priority.TACTICS, squad.name, CommandSystem.COMMANDER, "2개 조로 나눔. %s %s, %s %s." % [
			units.crew_short(squad.crews[0]), _names(squad.crews[0]), units.crew_short(squad.crews[1]), _names(squad.crews[1])], tick)
		return
	var keeper := _merge_keeper(squad)
	var home := crew_busy(squad.crews[0].id) == "" and crew_busy(squad.crews[1].id) == ""
	# 두 조가 모두 열화상카메라를 들었으면 하나는 다시 차에 (다음에 나눌 때 쓴다)
	if keeper != null and squad.crews[0].thermal_camera and squad.crews[1].thermal_camera:
		spare_thermal += 1
	if keeper == null or not units.merge_squad(squad, keeper, home):
		return
	units.gather(keeper, pathfinder)
	command._decide(tick, "분대 합치기 — %s" % squad.name)
	events.add(tick, "squad_merged", {"squad": squad.name, "crew_id": keeper.id})
	command.radio.send(Radio.Priority.TACTICS, squad.name, CommandSystem.COMMANDER, "한 분대로 합침.", tick)


func _names(c: Crew) -> String:
	var out: PackedStringArray = []
	for ff in c.list:
		out.append(ff.name)
	return "·".join(out)


# --- 한 명 보내기 · 복귀 (2026-11-16 결정 — docs/decisions.md '분대') ---
# 분대가 건물 밖에 있을 때만, 밖의 임무만: 급수 지원(water_help)·방재실·관리실 연락(office)·장비 가져오기(fetch).
# 2인 1조는 대원의 기본 행동이라 나간 한 명은 건물에 들어가지 않는다. 임무가 끝나면 스스로 돌아온다.

const SOLO_PATH := "res://data/commands.json"
## 나가 있는 대원 {1인 조 id: {task, label, phase, squad, vehicle, item, until, worked, retry}}
var solos: Dictionary = {}
var _solo_specs: Array = []


## 1인 임무 목록 (data/commands.json sets.solo): [{id, label, hint, item}]
func solo_specs() -> Array:
	if _solo_specs.is_empty():
		var d: Variant = JsonData.load_file(SOLO_PATH)
		if d is Dictionary:
			_solo_specs = d.get("sets", {}).get("solo", [])
	return _solo_specs


func solo_spec(task: String) -> Dictionary:
	for s: Dictionary in solo_specs():
		if str(s.id) == task:
			return s
	return {}


## 나간 대원의 임무 이름 (이름표용, 없으면 "")
func solo_label(crew_id: int) -> String:
	var e: Dictionary = solos.get(crew_id, {})
	if e.is_empty():
		return ""
	return "복귀 중" if str(e.phase) == "return" else str(e.label)


func _outdoor(ff: Firefighter) -> bool:
	return building.cell(ff.level, floori(ff.pos.x), floori(ff.pos.y)) in BuildingData.OUTDOOR


## 급수를 도울 차량: 운전원 작업 중이거나 곧 할 차 → 물탱크차 → 그 출동대 첫 차 → 아무 차. 가까운 순
func _solo_vehicle(squad: Squad, from: Vector2) -> Vehicle:
	var best: Vehicle = null
	var best_score := INF
	for v in units.vehicles:
		if v.away:
			continue
		var rank := 3.0
		if not v.work.is_empty() or v.pending_hydrant >= 0 or v.pending_supply >= 0:
			rank = 0.0
		elif v.type == "물탱크차":
			rank = 1.0
		elif v.squad_id == squad.id:
			rank = 2.0
		var score := rank * 100000.0 + v.pos.distance_to(from)
		if score < best_score:
			best_score = score
			best = v
	return best


## 한 명 보내기를 할 수 없는 이유 ("" = 할 수 있다)
func solo_reason(squad_id: int, task: String) -> String:
	if squad_id < 0 or squad_id >= units.squads.size():
		return "없는 출동대"
	var squad := units.squads[squad_id]
	if command.resources.is_en_route(squad_id) or squad.crews.is_empty():
		return "아직 현장에 없음"
	if _regroup_pending.has(squad_id):
		return "앞의 편성 지시가 전달되는 중"
	if units.solo_of(squad) != null:
		return "이미 한 명이 나가 있음 — 복귀한 뒤에"
	var mains := units.main_crews(squad)
	if mains.size() != 1:
		return "2개 조로 나뉘어 있음 — 2명 조에서는 한 명을 보낼 수 없음 (혼자 남는다)"
	var from := mains[0]
	var able := from.list.filter(func(ff: Firefighter) -> bool: return not ff.incapacitated).size()
	if able < 3:
		return "2명 조에서는 한 명을 보낼 수 없음 (혼자 남는다)"
	if units.detach_candidate(from) == null:
		return "보낼 대원이 없음"
	if from.list.any(func(ff: Firefighter) -> bool: return ff.aboard):
		return "차량·승강기에 타고 있음"
	if from.list.any(func(ff: Firefighter) -> bool: return not _outdoor(ff)):
		return "분대가 건물 안에 있음 — 밖에 있을 때만 한 명을 보낼 수 있음 (2인 1조)"
	if rescue.task_of_crew(from.id) is RescueSystem.CarryTask:
		return "구조대상자를 옮기는 중"
	var spec := solo_spec(task)
	if spec.is_empty():
		return "없는 임무"
	match task:
		"water_help":
			if _solo_vehicle(squad, from.leader.pos) == null:
				return "도울 차량이 없음"
		"office":
			if plan.office.is_empty():
				return "이 건물에는 방재실·관리실이 없음"
			if plan.known:
				return "도면은 이미 얻었음"
			var oc: Vector2i = plan.office.cell
			if not building.cell(int(plan.office.level), oc.x, oc.y) in BuildingData.OUTDOOR:
				return "%s이(가) 건물 안에 있음 — 한 명만 보낼 수 없음 (분대로 보내기)" % str(plan.office.name)
		"fetch":
			var item := str(spec.get("item", ""))
			if from.has_item(item):
				return "이미 가지고 있음"
			if units.vehicles.all(func(v: Vehicle) -> bool: return v.away):
				return "가져올 차량이 없음"
	return ""


## 한 명 보내기 지시 (CommandOrder "solo"): 무전으로 지시하고, 닿으면 한 명이 떨어져 나가 임무를 시작한다
func order_solo(squad_id: int, task: String, tick: int) -> bool:
	var why := solo_reason(squad_id, task)
	var label := str(solo_spec(task).get("label", task))
	if why != "":
		var who := units.squads[squad_id].name if squad_id >= 0 and squad_id < units.squads.size() else ""
		events.add(tick, "solo_rejected", {"squad": who, "task": label, "reason": why})
		return false
	var squad := units.squads[squad_id]
	_regroup_pending[squad_id] = true
	command.radio.send(Radio.Priority.TACTICS, CommandSystem.COMMANDER, squad.name, "한 명을 보내 %s 하라." % str(solo_spec(task).get("order", label)), tick, _on_solo.bind(squad_id, task))
	return true


func _on_solo(tick: int, squad_id: int, task: String) -> void:
	_regroup_pending.erase(squad_id)
	var squad := units.squads[squad_id]
	var spec := solo_spec(task)
	var label := str(spec.get("label", task))
	var why := solo_reason(squad_id, task)
	if why != "":
		events.add(tick, "solo_rejected", {"squad": squad.name, "task": label, "reason": why})
		return
	var s: Crew = units.detach_member(squad, units.main_crews(squad)[0])
	if s == null:
		return
	solos[s.id] = {"task": task, "label": label, "phase": "go", "squad": squad_id, "vehicle": -1, "item": str(spec.get("item", "")),
		"until": -1, "worked": false, "retry": 0}
	command._decide(tick, "한 명 보내기 — %s: %s" % [units.crew_name(s), label])
	events.add(tick, "solo_sent", {"squad": squad.name, "crew": units.crew_name(s), "crew_id": s.id, "task": label})
	command.radio.send(Radio.Priority.TACTICS, units.crew_name(s), CommandSystem.COMMANDER, "%s 가겠음." % label, tick)


## 복귀 지시 (CommandOrder "recall")
func recall_reason(squad_id: int) -> String:
	if squad_id < 0 or squad_id >= units.squads.size():
		return "없는 출동대"
	var s := units.solo_of(units.squads[squad_id])
	if s == null:
		return "나가 있는 대원이 없음"
	if str(solos.get(s.id, {}).get("phase", "")) == "return":
		return "이미 돌아오는 중"
	return ""


func order_recall(squad_id: int, tick: int) -> bool:
	var why := recall_reason(squad_id)
	if why != "":
		var who := units.squads[squad_id].name if squad_id >= 0 and squad_id < units.squads.size() else ""
		events.add(tick, "solo_rejected", {"squad": who, "task": "복귀", "reason": why})
		return false
	var s := units.solo_of(units.squads[squad_id])
	command.radio.send(Radio.Priority.TACTICS, CommandSystem.COMMANDER, units.crew_name(s), "분대로 복귀하라.", tick, _on_recall.bind(s.id))
	return true


func _on_recall(tick: int, crew_id: int) -> void:
	if solos.has(crew_id) and str(solos[crew_id].phase) != "return":
		_solo_return(crew_id, tick, "복귀 지시")


func _solo_return(crew_id: int, tick: int, why: String) -> void:
	var e: Dictionary = solos[crew_id]
	e.phase = "return"
	e.retry = 0
	var s := units.get_crew(crew_id)
	events.add(tick, "solo_done", {"crew": units.crew_name(s), "task": str(e.label), "why": why})


## 나가 있는 대원의 진행 (매 틱): 가기 → 일하기 → 돌아오기 → 분대에 합류
func _step_solos(tick: int) -> void:
	if solos.is_empty():
		return
	var second := roundi(1.0 / SimClock.TICK_DT)
	for id: int in solos.keys():
		var s := units.get_crew(id)
		if s == null or s.list.is_empty():
			solos.erase(id)
			continue
		var ff: Firefighter = s.list[0]
		var e: Dictionary = solos[id]
		if ff.incapacitated:
			continue
		var squad := units.squads[int(e.squad)]
		if str(e.phase) == "return":
			_step_solo_return(s, ff, e, squad, tick, second)
			continue
		match str(e.task):
			"water_help":
				var v := units.get_vehicle(int(e.vehicle))
				# 일이 있는 차가 따로 생기면 그 차로 옮긴다 (1초마다 살핀다)
				if tick % second == 0 and (v == null or (v.work.is_empty() and v.pending_hydrant < 0 and v.pending_supply < 0)):
					var better := _solo_vehicle(squad, ff.pos)
					if better != null and better != v:
						v = better
						e.vehicle = v.id
						e.phase = "go"
				if v == null:
					continue
				if not v.work.is_empty():
					e.worked = true
				elif bool(e.worked) and v.pending_hydrant < 0 and v.pending_supply < 0:
					_solo_return(id, tick, "급수 연결 끝")
					continue
				if v.distance_to_body(ff.pos) > 2.5 or ff.level != v.level:
					if not ff.is_moving() and tick >= int(e.retry):
						e.retry = tick + second
						_solo_go_vehicle(s, v)
				else:
					e.phase = "work"
			"office":
				if plan.known:
					_solo_return(id, tick, "도면 확보")
					continue
				var oc: Vector2i = plan.office.cell
				var at := Vector2(oc) + Vector2(0.5, 0.5)
				if (ff.level != int(plan.office.level) or ff.pos.distance_to(at) > PlanIntel.OFFICE_RADIUS * 0.7) and not ff.is_moving() and tick >= int(e.retry):
					e.retry = tick + second
					var near := pathfinder.nearest_walkable(int(plan.office.level), oc)
					if near != Pathfinder.NO_CELL:
						units.order_move([id] as Array[int], Vector3i(near.x, near.y, int(plan.office.level)), pathfinder, Vector3i(-1, -1, -1), true)
				elif not ff.is_moving():
					e.phase = "work"
			"fetch":
				var v := units.get_vehicle(int(e.vehicle))
				if v == null:
					var vs := units.vehicles_of_squad(squad.id)
					v = vs[0] if not vs.is_empty() else _solo_vehicle(squad, ff.pos)
					if v == null:
						_solo_return(id, tick, "가져올 차량이 없음")
						continue
					e.vehicle = v.id
				if int(e.until) >= 0:
					if tick >= int(e.until):
						s.items.append(str(e.item))
						events.add(tick, "equipment_fetched", {"crew": units.crew_name(s), "item": str(e.label)})
						_solo_return(id, tick, "장비 챙김")
				elif v.distance_to_body(ff.pos) > 2.5 or ff.level != v.level:
					if not ff.is_moving() and tick >= int(e.retry):
						e.retry = tick + second
						_solo_go_vehicle(s, v)
				elif not ff.is_moving():
					# 혼자 꺼내므로 2배 (기획안 6-1 작업 시간)
					e.phase = "work"
					e.until = tick + roundi(doors.fetch_seconds() * 2.0 / SimClock.TICK_DT)


func _solo_go_vehicle(s: Crew, v: Vehicle) -> void:
	var near := pathfinder.nearest_walkable(v.level, Vector2i(v.closest_body_point(s.leader.pos).floor()))
	if near != Pathfinder.NO_CELL:
		units.order_move([s.id] as Array[int], Vector3i(near.x, near.y, v.level), pathfinder, Vector3i(-1, -1, -1), true)


## 돌아오기: 분대 선두가 밖에 있으면 그 곁으로, 건물 안에 있으면 가장 가까운 출구 앞에서 기다린다 (들어가지 않는다).
## 선두 곁(2.5칸)에 닿으면 합류하고, 들고 온 장비는 분대의 것이 된다
func _step_solo_return(s: Crew, ff: Firefighter, e: Dictionary, squad: Squad, tick: int, second: int) -> void:
	var home: Crew = s.home_crew
	if home == null or home.list.is_empty():
		return
	var lead := home.leader
	if lead.level == ff.level and lead.pos.distance_to(ff.pos) <= 2.5 and _outdoor(ff):
		var who := units.crew_name(s)
		var carried := not s.items.is_empty()
		if units.attach_member(squad, s):
			solos.erase(s.id)
			events.add(tick, "solo_back", {"squad": squad.name, "crew": who, "crew_id": home.id, "task": str(e.label), "item": str(e.label) if carried else ""})
			command.radio.send(Radio.Priority.TACTICS, who, CommandSystem.COMMANDER, "분대 복귀." if not carried else "%s — 분대에 전달, 복귀." % str(e.label), tick)
		return
	if ff.is_moving() or tick < int(e.retry):
		return
	e.retry = tick + second
	var goal := Vector3i(floori(lead.pos.x), floori(lead.pos.y), lead.level)
	if not _outdoor(lead) or lead.aboard:
		# 분대가 건물 안: 가장 가까운 출구 앞까지만
		var best := Vector3i(-1, -1, -1)
		var best_d := INF
		for x in rescue.exit_cells():
			var d := Vector2(x.x, x.y).distance_to(lead.pos) + absi(x.z - lead.level) * 1000.0
			if d < best_d and building.cell(x.z, x.x, x.y) in BuildingData.OUTDOOR:
				best_d = d
				best = x
		if best.x < 0:
			return
		goal = best
	if Vector2(goal.x + 0.5, goal.y + 0.5).distance_to(ff.pos) > 1.5 or goal.z != ff.level:
		units.order_move([s.id] as Array[int], goal, pathfinder, Vector3i(-1, -1, -1), true)


## 도착 후 임무 미리 정하기 (P9-1): {조 id: attack·search·office·officer}. 그 조가 차에서 내리면 바로 지시한다
var preassign: Dictionary = {}


func set_preassign(tasks: Dictionary, tick: int) -> void:
	for k in tasks:
		preassign[int(k)] = str(tasks[k])
	command._decide(tick, "도착 후 임무 미리 정함 — %d개 조" % preassign.size())


func _step_preassign(tick: int) -> void:
	if preassign.is_empty():
		return
	for id: int in preassign.keys():
		var c := units.get_crew(id)
		if c == null:
			preassign.erase(id)
			continue
		if c.leader.aboard:
			continue
		var kind := str(preassign[id])
		preassign.erase(id)
		var lv := fire_floor_reported()
		var ids: Array[int] = [id]
		match kind:
			"attack":
				issue(TacticalCommand.make("attack_floor", ids, Vector3i(0, 0, lv)))
			"search":
				issue(TacticalCommand.make("search_floor", ids, Vector3i(0, 0, lv)))
			"office":
				if not plan.office.is_empty():
					var oc: Vector2i = plan.office.cell
					var lvl := int(plan.office.level)
					var near := pathfinder.nearest_walkable(lvl, oc)
					if near != Pathfinder.NO_CELL:
						issue(MoveCommand.new(ids, Vector3i(near.x, near.y, lvl)))
			"officer":
				issue(CommandOrder.make("role", [id] as Array[int], SafetySystem.Role.OFFICER))
		events.add(tick, "preassign_start", {"crew": units.crew_name(c), "task": kind})


## 신고·상황실이 알려 준 발화층 (출동 지령 dispatch.fire_level → 신고된 첫 발화 지점 층 → 가장 뜨거운 구획 층)
func fire_floor_reported() -> int:
	var lv := int(command.dispatch.get("fire_level", -1))
	if lv >= 0 and building.has_level(lv):
		return lv
	# 신고 내용의 발화층 = 시나리오 첫 발화 지점 층
	var ign: Array = scenario.get("fire", {}).get("ignitions", [])
	if not ign.is_empty() and building.has_level(int(ign[0].get("level", -1))):
		return int(ign[0].level)
	var hot: Compartment = null
	for c in fire.comps:
		if not fire.is_exposure_comp(c) and (hot == null or c.t_upper > hot.t_upper):
			hot = c
	return hot.level if hot else building.levels()[0]


## 상황실 관계자 조치 요청 (P9-1, 카드 ARRIVAL-RELAY-01): 가스 차단(도시가스), 발화 위치 확인(신고자·관계인 → 상황판)
## 요청하지 않은 조치는 현장에 반영되지 않는다
func relay_request(all: bool, tick: int) -> void:
	if all and gas.has_gas() and gas.open:
		gas.open = false
		gas.closed_tick = tick
		events.add(tick, "gas_shutoff", {"crew": "도시가스(관계자 조치)", "what": gas.valve_text})
	# 발화 위치: 시나리오 첫 발화 지점의 구획 (신고자·관계인이 알린 곳)
	var origin: Compartment = null
	var igs: Array = scenario.get("fire", {}).get("ignitions", [])
	if not igs.is_empty():
		var ig: Dictionary = igs[0]
		var cell: Array = ig.get("cell", [])
		if cell.size() >= 2:
			origin = fire.compartment_at(int(ig.get("level", 1)), int(cell[0]), int(cell[1]))
	if origin:
		knowledge.fires[origin.index] = tick
		knowledge.smoky[origin.index] = tick
		events.add(tick, "relay_fire_location", {"room": origin.display_name()})


## 예비 소방용수 (P9-1): 그 차량을 아직 고장 나지 않은 가장 가까운 다른 소화전에 잇는다. 옮겼으면 true
func next_hydrant(vehicle_name: String, tick: int) -> bool:
	for v in units.vehicles:
		if v.display_name(units.squads[v.squad_id].name) != vehicle_name or not v.is_pump() and v.transfer_lpm <= 0.0:
			continue
		var best := -1
		var best_d := INF
		for i in building.hydrants.size():
			if i in water.hydrants_out:
				continue
			var d := v.pos.distance_to(Vector2(building.hydrants[i]))
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			return false
		events.add(tick, "reserve_hydrant", {"vehicle": vehicle_name, "driver": v.driver_label()})
		water.connect_hydrant(v.id, best, tick)
		return true
	return false


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
				var given := false
				for c in units.crews:
					if not c.thermal_camera and not ems.is_ems_crew(c.id):
						c.thermal_camera = true
						given = true
						break
				# 분대마다 이미 있으면 차에 실어 두고, 분대를 나눌 때 카메라가 없는 조가 든다 (2026-11-16 분대 편성)
				if not given:
					spare_thermal += 1
			"fire_door_breaker":
				# 선착 진압대 조가 든다 (P4-1: 없으면 차량에 가서 가져와야 한다)
				for c in units.crews:
					if units.squads[c.squad_id].type == "진압대" and c.squad_id == 0 and not c.has_item("fire_door_breaker"):
						c.items.append("fire_door_breaker")
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


## 열기에 막히거나 밀려난 조가 인명검색·구조 중이었으면 그 임무를 멈추고 알린다 (2026-11-24 사용자: 화염으로 진입이 안 되면
## 스스로 후퇴해야 하는데 제자리에서 왔다 갔다 한다 — 검색·구조가 계속 다시 길을 잡았고, 물러나도 임무가 남아 되돌아갔다).
## 이미 구조대상자를 업었으면 그대로 데리고 나간다. 방수하러 가는 조는 건드리지 않는다. 멈춘 임무가 있었으면 true
##
## 2026-11-25 (튜토리얼에서 철수하던 구조 분대가 쓰러짐): 수관·철수도 같이 멈춘다 —
##   호스를 거두며 나오던 조 → 수관을 그 자리에 놓는다 (전에는 1초마다 다시 불난 방 쪽으로 길을 잡았다)
##   놓인 관창으로 가던 조(교체 뒤 재진입·교대조 인수) → 수관을 놓아 두고 "재진입 보류, 지시 바람"
##   철수 중이던 조 → 식은 곳으로 물러나 길이 열리기를 기다린다 (SafetySystem.withdrawing — 열리면 스스로 다시 나온다)
func _on_heat_stop(c: Crew, tick: int, _kind: String) -> bool:
	var stopped := false
	var t := rescue.task_of_crew(c.id)
	if t != null:
		if t is RescueSystem.CarryTask and (t as RescueSystem.CarryTask).carrying:
			return false
		var place := "내부"
		if t is RescueSystem.SearchTask:
			var st := t as RescueSystem.SearchTask
			if st.room >= 0 and st.room < fire.comps.size():
				place = fire.comps[st.room].display_name()
		else:
			place = "구조대상자 쪽"
		rescue.cancel(c.id)
		tactical.halt_for_heat(c.id, tick, place, conditions.heat_stop_at.get(c.id, Vector3i(-1, -1, -1)))
		stopped = true
	else:
		# 검색할 방으로 걸어가던 조 (2026-11-26): 전에는 길만 지워지고 임무가 남아 다음 틱에 또 그 방으로 길을 잡았다
		var tt := tactical.task_of_crew(c.id)
		if tt != null and tt.action == "search" and tt.phase != TacticalSystem.Phase.DONE:
			tactical.halt_for_heat(c.id, tick, fire.comps[tt.room].display_name() if tt.room >= 0 else "내부",
				conditions.heat_stop_at.get(c.id, Vector3i(-1, -1, -1)))
			stopped = true
	match water.leave_for_heat(c.id, tick):
		"recover":
			stopped = true
		"nozzle":
			command.safety.air_swaps.erase(c.id)
			tactical.halt_for_heat(c.id, tick, "관창 쪽")
			stopped = true
	if command.safety.withdraw_blocked(c.id):
		stopped = true
	return stopped


## 그 조가 철수 말고 다른 일을 받았는가 (SafetySystem.other_duty — 막힌 철수를 다시 잇지 않는다):
## 전술 임무·검색·구조·문 작업·잔불정리·층 이동·진입구 접근·방수·호스 꺼내기·놓인 관창으로 가기
func _has_other_duty(crew_id: int) -> bool:
	if tactical.task_of_crew(crew_id) or rescue.task_of_crew(crew_id) or doors.task_of_crew(crew_id) or rekindle.task_of_crew(crew_id) \
			or rekindle.watch_of_crew(crew_id):
		return true
	if command.floor_goals.has(crew_id) or command.approach.has(crew_id):
		return true
	var h := water.hose_of_crew(crew_id)
	return h != null and (h.flowing or h.to_nozzle or h.to_outlet or h.fetch_until >= 0)


## 대원의 활동 단계 (호흡량): 0 대기·보행 40 / 1 수색·호스 전개 55 / 2 방수·파괴 65 / 3 구조·계단 80 ℓ/분 (기획안 5-6)
func activity_level(ff: Firefighter) -> int:
	if rescue.task_of_crew(ff.crew_id) is RescueSystem.CarryTask:
		return 3
	if ff.is_moving() and building.cell(ff.level, floori(ff.pos.x), floori(ff.pos.y)) == BuildingData.Cell.STAIRS:
		return 3
	var h := water.hose_of_crew(ff.crew_id)
	var dt := doors.task_of_crew(ff.crew_id)
	# 문 옆에서 기다리기만 하는 분대는 문 작업(2단계)이 아니다 (2026-11-24 검사에서 찾음)
	if (h and h.flowing) or (dt != null and not dt.stacked(ff.crew_id)):
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
	end_type = p_type if p_type != "" else (MissionEndChecker.END_COMPLETE if completion_gaps().is_empty() else MissionEndChecker.END_EARLY)
	clock.paused = true
	phases.on_ended(clock.tick)
	events.add(clock.tick, "activity_ended", {"reason": reason})


## 작전 완료에 모자란 것 (2026-11-13 사용자 결정, SOP 202-6·200-4.1·400-3.2). 비어 있으면 활동 종료 선언이 '작전 완료',
## 하나라도 있으면 '조기 종료'. 종료는 막지 않는다 — 종료 창이 이 목록을 경고로 보여 준다.
##   완진 선언 · 타는 곳 없음 · 미검색 없음 (예전 조건) + 발견한 구조대상자 구조 · 구조자 구급대 인계 · 대원이 모두 나온 뒤 인원점검
func completion_gaps() -> PackedStringArray:
	var out: PackedStringArray = []
	if phases.all_clear.is_empty():
		out.append("완진 선언 전")
	if fire.grid.burning.size() > 0:
		out.append("타는 곳이 남아 있음")
	var unsearched := unsearched_rooms().size()
	if unsearched > 0:
		out.append("검색하지 않은 곳 %d곳" % unsearched)
	var has_ems := false
	for s in units.squads:
		if s.type == "구급대":
			has_ems = true
	var not_out := 0
	var not_handed := 0
	for v in rescue.victims:
		if v.state == Victim.State.RESCUED:
			if v.state_at_rescue == Victim.State.DEAD:
				continue
			var p := ems.patient_of(v.id)
			if v.left_at_entrance or (has_ems and (p == null or p.stage == EmsSystem.Stage.WAITING)):
				not_handed += 1
		elif v.alive() and (v.discovered or v.carried_by >= 0):
			not_out += 1
	if not_out > 0:
		out.append("발견하고 구조를 마치지 못한 구조대상자 %d명" % not_out)
	if not_handed > 0:
		out.append("구급대에 인계하지 않은 구조자 %d명" % not_handed)
	var pars := command.safety.par_log
	if pars.is_empty():
		out.append("인원점검을 하지 않음")
	elif int(pars[-1].indoor) > 0:
		out.append("마지막 인원점검 때 건물 안에 대원 %d명" % int(pars[-1].indoor))
	return out


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
	aerial.step(clock.tick)
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
	_step_preassign(clock.tick)
	_step_solos(clock.tick)
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
