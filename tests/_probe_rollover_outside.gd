extends SceneTree
## 점검용 (테스트 목록에 넣지 않음, 2026-11-25): 문이 닫힌 화점실 밖(현관 앞)에 선 조가 롤오버 징후를 보고하는가.
## 사용: godot --headless --path . -s res://tests/_probe_rollover_outside.gd


func _initialize() -> void:
	var sim := SimWorld.from_scenario("res://data/scenarios/sop214_1_day_living.json", true)
	sim.decision_pause = false
	# 바깥으로 난 닫힌 문 가운데 방과 맞닿은 것
	for o in sim.fire.openings:
		if o.kind != Opening.Kind.DOOR or o.room_b != Opening.OUTSIDE:
			continue
		var room := sim.fire.comps[o.room_a]
		o.is_open = false
		var dc := o.cells[0]
		# 문 바깥쪽 칸 (걸을 수 있는 바깥)
		var outside := Vector2i(-1, -1)
		for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var p := dc + n
			if sim.building.cell(o.level, p.x, p.y) in BuildingData.OUTDOOR:
				outside = p
		if outside.x < 0:
			continue
		print("문 %d %s 방=%s rect=%s 바깥 칸=%s" % [o.index, dc, room.display_name(), room.rect, outside])
		for spot: Array in [["문 바로 앞", outside], ["문 칸 위", dc], ["문에서 한 칸 더 밖", outside + (outside - dc)]]:
			var c := sim.units.crews[0]
			for ff in c.members():
				ff.aboard = false
				ff.level = o.level
				ff.pos = Vector2(spot[1]) + Vector2(0.5, 0.5)
				ff.prev_pos = ff.pos
				ff.path.clear()
			# 다른 조는 멀리
			for other in sim.units.crews:
				if other != c:
					for ff in other.members():
						ff.aboard = true
			sim.perception.update(sim.clock.tick)
			var vis := sim.perception.room_visible(room)
			var adj := false
			for ff in c.members():
				adj = adj or room.rect.grow(1).has_point(Vector2i(ff.pos.floor()))
			var by_crew := 0
			var by_any := 0
			for y in range(room.rect.position.y, room.rect.end.y):
				for x in range(room.rect.position.x, room.rect.end.x):
					if sim.fire.compartment_at(room.level, x, y) != room:
						continue
					by_crew += 1 if sim.perception.is_crew_visible(room.level, x, y) else 0
					by_any += 1 if sim.perception.is_visible(room.level, x, y) else 0
			print("  %s: 방이 보임=%s (대원 눈 %d칸 · 창 포함 %d칸)  방 둘레 1칸 안=%s  → 직접 본 사람=%d" % [spot[0], vis, by_crew, by_any, adj, sim.perception.clear_seer(room)])
	quit()
