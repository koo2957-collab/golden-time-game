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
	return "%02d:%02d  %s" % [floori(t / 60.0), t % 60, describe_text(e)]


## 시각 없이 사건 내용만 (무전 보고 본문 등)
static func describe_text(e: Dictionary) -> String:
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
		"victim_found":
			text = "요구조자 발견 (%s) — %s, %s, %s" % [e.how, e.who, e.room, e.state]
		"victim_state":
			text = "요구조자 상태 악화 — %s: %s" % [e.who, e.state]
		"victim_rescued":
			text = "구조 완료 — %s (%s)" % [e.who, e.state]
		"victim_recovered":
			text = "요구조자 수습 (사망) — %s" % e.who
		"ff_rescued":
			text = "대원 구출 완료 — %s" % e.who
		"rescue_pickup":
			text = "구조 대상 확보, 이송 중 — %s → %s" % [e.crew, e.who]
		"rescue_hose_crew":
			text = "수관 담당 조는 구조할 수 없음 — 다른 조를 투입하세요 (%s)" % e.crew
		"exit_blocked":
			text = "나갈 길이 없음 (외부 문 개방 필요) — %s" % e.crew
		"search_start":
			text = "인명검색 시작 — %s: %s" % [e.crew, e.room]
		"search_done":
			text = "검색 완료 — %s (%s)" % [e.room, e.crew]
		"rollover_sign":
			text = "롤오버 징후 (천장 화염, 플래시오버 임박) — %s" % e.room
		"backdraft_sign":
			text = "백드래프트 징후 (문틈 검은 연기·휘파람 소리·문 뜨거움) — %s" % e.room
		"backdraft":
			text = "백드래프트 발생 — %s" % e.room
		"fgi_warning":
			text = "350℃ 이상 — 즉시 대피 (%s)" % e.room
		"window_vented":
			text = "창 파괴 (배연) — %s" % e.room
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
		"radio":
			var channel := str(e.get("channel", "지휘망"))
			text = "[무전%s] %s" % ["" if channel == "지휘망" else " " + channel, e.text]
		"command_declared":
			text = "지휘권 선언 (최초 상황보고 %d/%d 항목 일치, %s 전략)" % [e.correct, e.scored, e.strategy]
		"strategy_set":
			text = "전략 전파 — %s" % e.strategy
		"entry_ordered":
			text = "내부 진입 명령 — %s" % e.squad
		"entry_rejected":
			text = "진입 명령 불가 (%s) — %s" % [e.reason, e.squad]
		"entry_wait":
			text = "진입 명령 대기 (입구 앞에서 멈춤) — %s" % e.crew
		"crew_entered":
			text = "%s 진입 — %s" % [e.floor, e.crew]
		"withdraw":
			text = "철수 — %s" % e.crew
		"auto_slow":
			text = "자동 감속 (1배속): %s" % e.reason
		"squad_dispatched":
			text = "%s 출동 — %s (약 %d분 뒤 도착)" % [e.reason, e.squads, roundi(e.eta_s / 60.0)]
		"squad_arriving":
			text = "현장 접근 — %s" % e.squad
		"staging_full":
			text = "대기 장소에 자리가 없어 진입로에서 대기 — %s" % e.squad
		"squad_staged":
			text = "대기1단계 장소 도착 (%s, 인원 %d명, %s) — %s" % [e.place, e.people, e.vehicles, e.squad]
		"squad_committed":
			text = "대기 해제, 현장 투입 — %s" % e.squad
		"order_en_route":
			text = "아직 현장에 도착하지 않아 명령할 수 없음 — %s" % e.squad
		"support_requested":
			text = "지원 요청 — %s" % e.level
		"division_set":
			text = "단위대 지정 — %s (지휘: %s 대장, 소속: %s, %s)" % [e.division, e.supervisor, e.squads, e.channel]
		"division_cleared":
			text = "단위대 해제 — %s" % e.division
		"face_seen":
			text = "%s면 확인 (둘러보기 %d/%d)" % [e.face, e.count, e.total]
		"site_info_found":
			text = "%s면에서 확인 — %s" % [e.face, e.text]
		"clue_found":
			text = "물증 — %s" % e.text
		"witness_arrived":
			text = "관계인 도착 — %s" % e.witness
		"statement":
			text = "진술 — %s: \"%s\"" % [e.witness, e.text]
		"ask_too_far":
			text = "관계인에게 질문하려면 지휘관이 가까이 가야 함 — %s" % e.witness
		"ask_cancelled":
			text = "지휘관이 움직여 질문이 끊김 — %s" % e.witness
		"command_post":
			text = "현장지휘소 — 관찰 %s%s · 안전 %s (건물에서 %.1fm) · 동선 %s" % [e.observe, " (%s면)" % e.faces if e.faces != "" else "", e.safety, e.distance_m, e.route]
		"report_updated":
			text = "상황 보완 보고 (%d/%d 항목 일치)" % [e.correct, e.scored]
		"span_warning":
			text = "통솔범위 %s — 직접 지휘 %d개 (적정 %d, 한계 %d). 단위지휘관을 지정하세요 (SOP 105)" % [e.level, e.count, e.ideal, e.max]
		_:
			text = str(e.type)
	return text
