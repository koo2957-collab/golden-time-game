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
			text = "소화전 점령 — %s%s" % [e.vehicle, _driver(e)]
		"hydrant_disconnected":
			text = "소화전 연결 해제 — %s" % e.vehicle
		"supply_connected":
			text = "급수 연결 — %s → %s%s" % [e.vehicle, e.to, _driver(e)]
		"hose_laid":
			text = "수관 연장 — %s (%s)" % [e.crew, e.vehicle]
		"hose_too_short":
			text = "수관 길이 부족 — %s" % e.crew
		"hose_limit":
			text = "수관 길이 한계 — %s" % e.crew
		"tank_empty":
			text = "탱크 물 소진 — %s" % e.vehicle
		"vehicle_locked":
			text = "수관이 연결되어 이동 불가 — %s%s" % [e.vehicle, _driver(e)]
		"vehicle_blocked":
			text = "차량 이동 불가 (차도·다른 차량) — %s%s" % [e.vehicle, _driver(e)]
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
		"ember_spotted":
			text = "불씨 확인 (열화상) — %s %d곳 — %s" % [e.room, e.count, e.crew]
		"overhaul_start":
			text = "잔불정리 시작 — %s: %s" % [e.crew, e.room]
		"overhaul_done":
			text = "잔불정리 완료 — %s, 불씨 %d곳 제거 — %s" % [e.room, e.embers, e.crew]
		"rekindle":
			text = "재발화 — %s" % e.room
		"mayday":
			text = "긴급탈출 선언 — %s %s, %s%s" % [e.crew, e.who, e.where, " (무전 응답 없음)" if e.silent else ""]
		"emergency_cleared":
			text = "긴급탈출 상황 해제"
		"evacuation_ordered":
			text = "긴급탈출 지시 전파 — 전 대원 탈출"
		"evacuate":
			text = "긴급탈출 — %s" % e.crew
		"par_done":
			text = "인원점검 — %s" % ("이상 없음" if e.missing == 0 and e.indoor == 0 else "건물 안 %d명, 미확인 %d명" % [e.indoor, e.missing])
		"role_assigned":
			text = "%s — %s" % [e.role, e.crew]
		"role_reserved":
			text = "%s은 다른 임무를 받지 않음 (SSG 9 1.2.2) — %s" % [e.role, e.crew]
		"rit_deployed":
			text = "RIT 투입 — %s (남은 RIT %d조, 추가 지정 필요 SSG 9 3.1.4)" % [e.crew, e.remaining]
		"officer_warning":
			text = "현장안전담당 경고 — %s %s 공기 %d%%" % [e.crew, e.who, e.air]
		"entry_factors":
			text = "진입 금지 판단 요소 (SOP 102-4.1) — %s: %s" % [e.squad, e.factors]
		"tactical_start":
			text = "%s 시작%s — %s" % [e.action, " (%s)" % e.room if e.has("room") else "", e.crew]
		"tactical_halt":
			text = "%s — %s" % [e.reason, e.crew]
		"tactical_done":
			text = "%s — %s" % [e.text, e.crew]
		"exposure_heating":
			text = "%s 외벽 가열 (%s 화염) — 경계관창 필요" % [e.target, e.get("from", "")]
		"exposure_ignition":
			text = "%s으로 연소 확대" % e.target
		"collapse_sign":
			text = "붕괴 징후 (폭음·균열음) — %s" % e.room
		"collapse":
			text = "붕괴 — %s" % e.room
		"gas_off_start":
			text = "가스 밸브 차단하러 감 — %s" % e.crew
		"gas_shutoff":
			text = "%s 차단 — %s" % [e.what, e.crew]
		"gas_explosion":
			text = "가스 폭발 — %s" % e.room
		"fdc_connected":
			text = "송수구 연결 — %s%s" % [e.vehicle, _driver(e)]
		"fdc_too_far":
			text = "송수구가 멀어 연결 못함 — %s%s" % [e.vehicle, _driver(e)]
		"fdc_not_connected":
			text = "송수구 미연결 — 방수구 사용 불가 (%s)" % e.crew
		"hose_outlet_laid":
			text = "방수구에서 수관 연장 — %s (%s)" % [e.crew, e.level]
		"card_asked":
			text = "판단 요청 [%s] — %s" % [e.urgency, e.title]
		"card_answered":
			text = "지시 — %s: %s" % [e.title, e.option]
		"card_timeout":
			text = "응답 없음 — %s (지시 대기)" % e.title
		"card_overflow":
			text = "판단 요청 대기 중 — %s" % e.title
		"card_info_check":
			text = "정보 확인 중 (약 %d초) — %s" % [e.seconds, e.crew]
		"card_preordered":
			text = "선제지시대로 처리 — %s" % e.title
		"preorder":
			text = "선제지시 %s — %s" % ["지정" if e.on else "해제", e.key]
		"realism":
			text = "난이도 — %s" % e.name
		"phase":
			text = "활동 단계 — %s" % e.phase
		"knockdown_reported":
			text = "초진 — %s (%s)" % [e.rooms, e.crew]
		"secondary_search_done":
			text = "2차 검색 완료 — %s" % e.room
		"all_clear_declared":
			text = "완진 선언 — 잔불정리·감시·인원점검 후 활동 종료"
		"time_warning":
			text = "활동 제한 시간 %d분 전" % e.min
		"end_suggested":
			text = "더 할 일이 없습니다 — %s" % ("인원점검 후 활동 종료하세요" if e.get("all_clear", false) else "완진 선언 후 활동 종료를 검토하세요")
		"hydrant_out":
			text = "소화전 사용 불가(고장) — %s%s" % [e.vehicle, _driver(e)]
		"shuttle_on":
			text = "순환보수 지정 — %s%s, 수원: %s" % [e.vehicle, _driver(e), e.source]
		"shuttle_off":
			text = "순환보수 해제 — %s" % e.vehicle
		"shuttle_depart":
			text = "급수하러 출발 — %s%s → %s (약 %d분 %02d초 뒤 복귀)" % [e.vehicle, _driver(e), e.source, int(e.eta_s) / 60, int(e.eta_s) % 60]
		"shuttle_return":
			text = "급수 마치고 복귀 — %s%s" % [e.vehicle, _driver(e)]
		"sign_warning":
			text = "간판 뒤 화염 분출 — %s 낙하 위험, 아래 접근 금지" % e.name
		"sign_fall":
			text = "간판 낙하 — %s" % e.name
		"shaft_heat":
			text = "%s 샤프트(PS)로 화염·연기 유입 — 위층 확인 필요" % e.floor
		"shaft_smoke":
			text = "%s 샤프트(PS)에서 연기 — 배관 관통부 연소 우려" % e.floor
		"shaft_ignition":
			text = "샤프트 통해 연소 확대 — %s" % e.room
		"shaft_checked":
			text = "%s 샤프트(PS) 확인·차단" % e.floor
		"victim_trapped":
			text = "대피하던 사람이 연기에 갇힘 — %s, %s" % [e.who, e.room]
		"victim_self_evac":
			text = "자력 대피 — %s 밖으로 나옴" % e.who
		"jump_risk":
			text = "창가 요구조자가 뛰어내리려 함 — %s, %s (공기안전매트 필요)" % [e.who, e.room]
		"victim_jumped":
			text = "%s 창에서 추락 — %s" % [e.who, "공기안전매트에 착지" if e.mat else "매트 없음"]
		"air_mat_start":
			text = "공기안전매트 설치하러 감 — %s" % e.crew
		"air_mat_ready":
			text = "공기안전매트 설치 완료 — %s" % e.crew
		"debris_zone":
			text = "낙하물 위험 — %s %s 창 파손, 아래 반경 %.1fm 접근 금지" % [e.floor, e.get("face", ""), e.radius_m]
		"debris_zone_entered":
			text = "낙하물 위험구역에 대원 진입 — %s" % e.crew
		"placement":
			text = "선착 차량 배치 — %s" % e.name
		"ems_triage":
			text = "환자 분류 %s — %s (SOP 402)" % [e.triage, e.who]
		"ems_treat_order":
			text = "처치 지시 — %s → %s (%s)" % [e.crew, e.who, e.triage]
		"ems_treat_start":
			text = "응급처치 시작 — %s, %s" % [e.crew, e.who]
		"ems_treated":
			text = "응급처치 완료 — %s (%s)%s" % [e.who, e.crew, "" if e.get("auto", false) else " — 이송 지시 바람"]
		"ems_carry":
			text = "들것으로 구급차까지 이동 — %s, %s" % [e.crew, e.who]
		"ems_depart":
			text = "환자 이송 출발 — %s (%s) → %s, %s 운전" % [e.who, e.triage, e.hospital, e.driver]
		"ems_handover":
			text = "병원 인계 — %s → %s" % [e.who, e.hospital]
		"ems_returned":
			text = "구급대 복귀 — %s" % e.squad
		"ems_no_ambulance":
			text = "구급차 없음 (이송 중) — %s" % e.crew
		"activity_ended":
			text = "활동 종료 — %s" % e.reason
		"span_warning":
			text = "통솔범위 %s — 직접 지휘 %d개 (적정 %d, 한계 %d). 단위지휘관을 지정하세요 (SOP 105)" % [e.level, e.count, e.ideal, e.max]
		_:
			text = str(e.type)
	return text


static func _driver(e: Dictionary) -> String:
	return " (운전원 %s)" % e.driver if e.has("driver") else ""
