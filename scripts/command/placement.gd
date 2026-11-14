class_name Placement
extends RefCounted
## 선착대 차량 배치 (SOP 200-3.1.1). 시나리오 approach.options 중 하나를 출동 중 장면(DispatchUi)에서 고르면
## 선착 출동대 차량이 그 자리에 선다. 배치마다 장단점(낙하물·화염, 후착대·특수차 공간, 소화전 거리)이 있고
## 평가 규칙 fire.placement가 고른 배치의 score로 판정한다.
##   approach: {note, squad(편성 id, 기본은 첫 출동대), default(기본 선택 index), options: [{id, name, text, score, feedback, vehicles: [{spawn, heading}]}]}

## 배치를 고를 수 있는 시간 (도착 직후)
const MAX_TICK := 50


static func options(sim: SimWorld) -> Array:
	return sim.scenario.get("approach", {}).get("options", [])


static func default_index(sim: SimWorld) -> int:
	return int(sim.scenario.get("approach", {}).get("default", 0))


## 고른 배치를 적용한다. 한 대라도 도로 밖이거나 겹치면 모두 원래 자리에 둔다
static func apply(sim: SimWorld, index: int, tick: int) -> bool:
	var opts := options(sim)
	if index < 0 or index >= opts.size() or tick > MAX_TICK or not sim.command.placement.is_empty():
		return false
	var opt: Dictionary = opts[index]
	var vehicles := sim.units.vehicles_of_squad(_squad(sim))
	var specs: Array = opt.get("vehicles", [])
	var n := mini(vehicles.size(), specs.size())
	var old: Array = []
	# 먼저 모두 들어 올린 뒤 차례로 세운다 (서로의 옛 자리와 겹치지 않게)
	for i in n:
		old.append([vehicles[i].pos, vehicles[i].heading])
		vehicles[i].pos = Vector2(-1000.0 - i * 100.0, -1000.0)
	var moved := 0
	for i in n:
		var v := vehicles[i]
		var spec: Dictionary = specs[i]
		var p: Array = spec.get("spawn", [old[i][0].x, old[i][0].y])
		var h: Array = spec.get("heading", [old[i][1].x, old[i][1].y])
		v.heading = Vector2(float(h[0]), float(h[1])).normalized()
		var at := Vector2(int(p[0]) + 0.5, int(p[1]) + 0.5)
		if not sim.water.vehicle_can_be_at(v, at):
			break
		v.pos = at
		moved += 1
	if moved < n:
		# 하나라도 못 서면 모두 원래 자리로
		for i in n:
			vehicles[i].pos = old[i][0]
			vehicles[i].heading = old[i][1]
		moved = 0
	for i in n:
		vehicles[i].prev_pos = vehicles[i].pos
		vehicles[i].goal = vehicles[i].pos
	sim.command.placement = {"id": str(opt.get("id", "")), "name": str(opt.get("name", "")), "score": float(opt.get("score", 0.5)),
		"feedback": str(opt.get("feedback", "")), "tick": tick, "moved": moved}
	sim.events.add(tick, "placement", {"name": str(opt.get("name", "")), "crew": "선착대"})
	return true


static func _squad(sim: SimWorld) -> int:
	var key := str(sim.scenario.get("approach", {}).get("squad", ""))
	for s in sim.units.squads:
		if (key == "" and not sim.units.vehicles_of_squad(s.id).is_empty()) or s.key == key:
			return s.id
	return 0
