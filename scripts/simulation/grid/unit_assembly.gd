class_name UnitAssembly
extends RefCounted
## 층·세대마다 다른 구조와 집기 (기획안 4-2-1, P2-2). "같은 뼈대, 다른 속".
##   동(건물 JSON의 층 격자·계단실·샤프트)은 그대로 두고, 세대마다 (변형, 집기 세트)를 시드로 골라 끼운다.
##   - 집기 세트(data/furnishings/*.json): 세대 안 가구를 통째로 바꾼다. 가구마다 재질·통과(walk/slow/block)·숨은 잔화 계수·숨는 곳 가중치
##   - 변형(data/unit_variants/*.json): 도면과 다른 곳(plan_wall), 현관문 잠김·도어체크, 발코니 피난시설 앞 짐
##   - 같은 시드면 항상 같은 맵 (세대마다 시드·층·세대 번호로 난수를 따로 만든다 — 다른 세대 선택이 서로 영향을 주지 않음)
##   - 교관이 세대를 직접 지정하면(시나리오 units.overrides) 그것이 우선
##   시나리오에 units 설정이 없으면 모든 세대가 표준 평면 + 일반 집기 (지금까지와 같은 맵)
## 도면(FloorPlanIntel)에는 표준 평면만 보인다. 변형은 plan_diffs로 넘겨 대원이 본 뒤에만 실제 구조가 된다.

## 세대 결과 [{level, id, name(예: "301호"), rect, mirror, variant, furnish, front_door(Vector2i 또는 (-1,-1)), door}]
var units: Array[Dictionary] = []
## 도면과 실제가 다른 곳 (plan_intel이 읽는 plan_diffs 형식)
var plan_diffs: Array[Dictionary] = []
## 통과 가중치 (pass -> AStar 가중치)
var pass_weight := {"walk": 1.0, "slow": 2.0, "block": 4.0}


## building: 동, raw: 건물 JSON의 units 블록, setup: 시나리오 units {mix: {variants: {이름: 가중치}, furnishings: {...}}, overrides: {"301": {variant, furnish}}}
static func apply(building: BuildingData, raw: Dictionary, p_seed: int, setup: Dictionary) -> UnitAssembly:
	var a := UnitAssembly.new()
	if raw.is_empty():
		return a
	var furn: Variant = JsonData.load_file(str(raw.get("furnishings", "")))
	var vars: Variant = JsonData.load_file(str(raw.get("variants", "")))
	if not furn is Dictionary or not vars is Dictionary:
		return a
	var pw: Dictionary = furn.get("pass_weight", {})
	for k: String in pw:
		a.pass_weight[k] = float(pw[k])
	var sets: Dictionary = furn.get("sets", {})
	var variants: Dictionary = vars.get("variants", {})
	var mix: Dictionary = setup.get("mix", {})
	var overrides: Dictionary = setup.get("overrides", {})
	for level in building.levels():
		for u: Dictionary in raw.get("list", []):
			var name := "%d%s호" % [building.floor_number(level), str(u.get("id", ""))]
			if not a._has_unit_rooms(building, level, name):
				continue
			var r: Array = u.get("rect", [0, 0, 0, 0])
			var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("%d:%d:%s" % [p_seed, level, str(u.get("id", ""))])
			var pick_variant := _weighted(rng, mix.get("variants", {}), "표준")
			var pick_furnish := _weighted(rng, mix.get("furnishings", {}), "일반")
			var ov: Dictionary = overrides.get(name.trim_suffix("호"), overrides.get(name, {}))
			pick_variant = str(ov.get("variant", pick_variant))
			pick_furnish = str(ov.get("furnish", pick_furnish))
			if not variants.has(pick_variant):
				pick_variant = "표준"
			if not sets.has(pick_furnish):
				pick_furnish = "일반"
			var unit := {"level": level, "id": str(u.get("id", "")), "name": name, "rect": rect, "mirror": bool(u.get("mirror", false)),
				"variant": pick_variant, "furnish": pick_furnish, "door": str(variants[pick_variant].get("door", "")),
				"front_door": a._front_door(building, level, rect)}
			a._furnish(building, unit, sets[pick_furnish], variants[pick_variant])
			a._plan_diff(unit, variants[pick_variant])
			a.units.append(unit)
	return a


## 세대 이름(예: "301호")으로 찾는다
func unit_named(name: String) -> Dictionary:
	for u in units:
		if u.name == name:
			return u
	return {}


## 그 칸이 속한 세대 (없으면 빈 사전)
func unit_at(level: int, cell: Vector2i) -> Dictionary:
	for u in units:
		if u.level == level and (u.rect as Rect2i).has_point(cell):
			return u
	return {}


## 바로 아래층의 같은 자리 세대 (직하층 확인)
func unit_below(unit: Dictionary) -> Dictionary:
	for u in units:
		if u.level == int(unit.level) - 1 and u.id == unit.id:
			return u
	return {}


static func _weighted(rng: RandomNumberGenerator, weights: Dictionary, fallback: String) -> String:
	var total := 0.0
	for k: String in weights:
		total += maxf(0.0, float(weights[k]))
	var roll := rng.randf() * total
	if total <= 0.0:
		return fallback
	for k: String in weights:
		roll -= maxf(0.0, float(weights[k]))
		if roll <= 0.0:
			return k
	return fallback


func _has_unit_rooms(building: BuildingData, level: int, name: String) -> bool:
	for room in building.rooms(level):
		if str(room.name).begins_with(name):
			return true
	return false


## 세대 경계의 문 가운데 바깥(계단실·복도)으로 나가는 문 = 현관문
func _front_door(building: BuildingData, level: int, rect: Rect2i) -> Vector2i:
	for y in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			if building.cell(level, x, y) != BuildingData.Cell.DOOR:
				continue
			for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
				var a := Vector2i(x, y) + d
				var b := Vector2i(x, y) - d
				if rect.has_point(a) and not rect.has_point(b) and building.is_walkable(level, b.x, b.y):
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## 세대 안 가구를 집기 세트로 바꾼다 (오른쪽 세대는 좌우 뒤집기)
func _furnish(building: BuildingData, unit: Dictionary, set_data: Dictionary, variant: Dictionary) -> void:
	var rect: Rect2i = unit.rect
	var list: Array[Dictionary] = building.furniture(unit.level)
	for k in range(list.size() - 1, -1, -1):
		if rect.encloses(list[k].rect):
			list.remove_at(k)
	var items: Array = set_data.get("items", []).duplicate()
	if variant.has("evac_blocked"):
		items.append(variant.evac_blocked)
	for item: Dictionary in items:
		var r: Array = item.get("rect", [0, 0, 1, 1])
		var lx := int(r[0])
		if unit.mirror:
			lx = rect.size.x - int(r[0]) - int(r[2])
		var abs_rect := Rect2i(rect.position.x + lx, rect.position.y + int(r[1]), int(r[2]), int(r[3]))
		if not rect.encloses(abs_rect):
			continue
		var p := str(item.get("pass", "walk"))
		list.append({"name": str(item.get("name", "")), "material": str(item.get("material", "")), "rect": abs_rect,
			"pass": p, "weight": float(pass_weight.get(p, 1.0)), "ember": float(item.get("ember", 1.0)),
			"hide": float(item.get("hide", 0.0)), "unit": unit.name})


func _plan_diff(unit: Dictionary, variant: Dictionary) -> void:
	var cells: Array = []
	var rect: Rect2i = unit.rect
	for c: Array in variant.get("plan_wall", []):
		var lx := int(c[0])
		if unit.mirror:
			lx = rect.size.x - 1 - lx
		cells.append([rect.position.x + lx, rect.position.y + int(c[1])])
	if not cells.is_empty():
		plan_diffs.append({"level": unit.level, "cells": cells, "plan": "wall",
			"note": "%s %s — %s" % [unit.name, str(variant.get("label", "")), str(variant.get("note", "도면과 다르다"))]})
