class_name SimEventLog
extends RefCounted
## 시뮬레이션에서 일어난 사건의 기록 (예: 거실 플래시오버, 방1 창 파손).
## 디브리핑 타임라인과 평가의 원재료가 된다.

var entries: Array[Dictionary] = []


func add(tick: int, type: String, data: Dictionary = {}) -> void:
	var entry := data.duplicate()
	entry["tick"] = tick
	entry["time_s"] = tick * SimClock.TICK_DT
	entry["type"] = type
	entries.append(entry)


func of_type(type: String) -> Array[Dictionary]:
	return entries.filter(func(e: Dictionary) -> bool: return e.type == type)


## 사건을 한 줄 문장으로 (예: "06:02 플래시오버 — 1층 거실 (597℃)")
static func describe(e: Dictionary) -> String:
	var t := int(e.time_s)
	var clock := "%02d:%02d" % [floori(t / 60.0), t % 60]
	var text := ""
	match e.type:
		"ignition":
			text = "발화 — %s (%s)" % [e.room, e.material]
		"stage":
			text = "%s  %s → %s" % [e.room, e.from, e.to]
		"flashover":
			text = "플래시오버 — %s (%d℃)" % [e.room, int(e.temp_c)]
		"window_broken":
			text = "유리창 파손 — %s" % e.room
		"smoke":
			text = "연기 유입 — %s" % e.room
		"door_opened":
			text = "문 개방 — %s" % e.get("room", "")
		"door_closed":
			text = "문 폐쇄 — %s" % e.get("room", "")
		"door_forced":
			text = "잠긴 문 파괴 (강제 개방) — %s" % e.room
		"door_cannot_close":
			text = "문을 닫을 수 없음 (파괴됨·통로에 사람) — %s" % e.crew
		"door_unreachable":
			text = "문 앞으로 갈 수 없음 — %s" % e.crew
		"heat_blocked":
			text = "열기가 강해 더 접근할 수 없음 — %s" % e.crew
		"heat_retreat":
			text = "열기로 후퇴 — %s" % e.crew
		"air_alarm":
			text = "공기호흡기 경보 (잔량 부족) — %s" % e.crew
		"scba_swapped":
			text = "공기호흡기 교체 — %s" % e.crew
		"ff_down":
			text = "대원 행동 불능 (%s) — %s" % [e.reason, e.crew]
		"hydrant_connected":
			text = "소화전 점령 — %s" % e.vehicle
		"hydrant_disconnected":
			text = "소화전 연결 해제 — %s" % e.vehicle
		"supply_connected":
			text = "급수 연결 — %s → %s" % [e.vehicle, e.to]
		"hose_laid":
			text = "수관 연장 — %s (%s)" % [e.crew, e.vehicle]
		"hose_too_short":
			text = "수관 길이 부족 — %s" % e.crew
		"hose_limit":
			text = "수관 길이 한계 — %s" % e.crew
		"tank_empty":
			text = "탱크 물 소진 — %s" % e.vehicle
		"vehicle_locked":
			text = "수관이 연결되어 이동 불가 — %s" % e.vehicle
		"vehicle_blocked":
			text = "차량 이동 불가 (차도·다른 차량) — %s" % e.vehicle
		"spray_start":
			text = "방수 시작 — %s (%s)" % [e.crew, e.pattern]
		"spray_stop":
			text = "방수 중지 — %s" % e.crew
		"spray_unreachable":
			text = "방수 위치 없음 (물줄기가 닿는 곳에 갈 수 없음) — %s" % e.crew
		_:
			text = str(e.type)
	return "%s  %s" % [clock, text]
