# 기능 목록표 (A-1)

2026-11-11 작성. 계획: docs/plan_feature_by_feature.md

- **상태:** ✅ 원하는 대로 둔다 / 🔧 고친다 / ➖ 뺀다 / ⏸ 보류(기능 스위치로 꺼 두고 그 순서가 오면 다룬다)
- **추천** 칸은 내 의견이다. **결정** 칸은 사용자가 정한다.
- **연결** 칸: 이 기능이 기대는 것 → 이 기능이 영향을 주는 것. 고칠 때 함께 확인할 곳이다.
- 파일은 scripts/ 아래 경로. 테스트는 tests/ 아래 파일.

## 1. 화면·보기

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F01 | 입체 보기: 외부 보기·층 단면 | 외부는 건물 외관(층 띠), 안은 초점 층 + 위아래 층을 반투명으로 쌓아 보임 | ui/building/floor_layer, ui/iso_view, ui/building/floor_stack | 그림·시야 → 모든 화면 | ui_cutaway, test_cutaway | 🔧 단면에서 위층 반투명 면이 불·대원을 가림 | |
| F02 | 평면 보기 · 전술상황판(M·Tab) | 평면 보기(상황판 화면)와 전술상황판(보고된 것만 그린 평면도)이 따로 있음 | ui/floor_plan_view, ui/tactical_board, ui/board_map | 무전 보고(F35) | test_board | 🔧 두 평면 화면의 역할이 겹침 — 하나로 정리 | |
| F03 | 카메라·층 막대·미니맵 | 휠 확대, 가운데 버튼 끌기, 층 막대 클릭, 미니맵 클릭 | ui/rts_camera, ui/floor_bar_view, ui/minimap_view | F01 | ui_smoke | ✅ | |
| F04 | 그림: 대원·차량·가구, 불·연기 | Blender로 구운 8방향 그림, 셰이더 불꽃·연기 | ui/sprite_art, ui/fx_art, tools/blender | — | test_art | ✅ (오늘 완성) | |
| F05 | 알림·상단 정보·힌트 | 알림이 위쪽 글줄·무전 기록·카드·팀 줄·힌트 여러 곳에 흩어짐 | ui/hud, ui/hint_ui | 모든 사건 | ui_smoke | 🔧 한곳(주의 대기열)으로 모으기 | |

## 2. 현장지휘관

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F06 | 지휘관 이동·360° 둘러보기 | 땅 우클릭 = 지휘관 이동, 면을 볼 때마다 정보 | command/command_system, command/site_survey | 시야(F34) | test_site_survey | ✅ (오늘 결정) | |
| F07 | 지휘소·이동지휘 | 지휘소를 떠나면 상황판이 15초 늦고 일상 보고 25%를 놓침 | command/command_post | 무전(F35), 후착대(F13) | test_command_post | ⏸ 지휘관을 직접 움직이게 된 지금 답답할 수 있음 | |
| F08 | 관계인 진술 | 관계인 클릭 → 질문 → 진술 | command/witness, command/site_survey | 정보(F35) | test_site_survey | ✅ | |

## 3. 출동·차량

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F09 | 출동 지령·차량 도착 | 지령 창 → 차량이 지도 끝에서 한 대씩 들어와 대원 하차 | command/resource_system, ui/city_mass_view | 모든 대원 기능 | test_arrival, test_dispatch_prep | ✅ (도착이 길면 🔧) | |
| F10 | 선착 차량 배치 고르기 | 도착 때 배치 위치 선택지 | command/placement | F11 | test_placement | ✅ | |
| F11 | 차량 이동·소화전·급수·물탱크 순환 | 차량 우클릭 이동, 소화전 점령, 물탱크 → 펌프 급수, 순환보수 | simulation/suppression/water_system, shuttle_system | 방수(F27) | test_water_flow, test_shuttle | ✅ | |
| F12 | 굴절차 (바스켓 구조·방수포) | 굴절차 바스켓으로 창가 구조, 방수포 | simulation/suppression/aerial_system, monitor_system | F25 | test_aerial | ⏸ 아파트 단계에서 | |
| F13 | 후착대 임무 받기 | 후착대가 차 옆에서 "임무 주십시오"를 반복하고, 지휘관을 따라옴 | command/command_post | F07 | test_command_post | 🔧 즉시 지시·새 이동 방식과 맞춰 단순하게 | |

## 4. 대원 선택·이동·진입

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F14 | 조 선택 | 클릭·드래그·Shift·더블클릭(출동대)·숫자키·팀 줄 | ui/selection_controller, ui/team_strip | — | ui_smoke | ✅ | |
| F15 | 진입구 → 진입 허가 → 층 → 계단 → 방 | 노란 진입구·층 테두리·계단·방, 문 앞 진입 허가, 동시 진입 | command/command_system, ui/selection_controller, ui/mission_ui | F16·F17·F20·F21 | test_floor_flow, test_entry_flow | 🔧 오늘 완성 — 사용자 확인 대기 | |
| F16 | 진입 허가 판단 | 문 앞 요청 카드: 허가·대기·금지 (정답 근거: 전략·징후·공기·수관·RIT) | command/command_system | F15, 평가(F45) | test_entry_request | ✅ | |
| F17 | 명령 카드(Q W E R A S)와 예전 4단계 진입 모드 | 카드 W/Q → 진입구 고르기 모드 → 목표 → 조건 창 | ui/command_card, ui/command_ui, ui/selection_controller | F15와 겹침 | ui_command_card | 🔧 W/Q도 새 흐름(노란 방 고르기)으로 통일, 예전 진입구 모드는 뺌 | |
| F18 | 즉시 지시·무전 지연 (난이도별) | 훈련·실전은 바로 실행, 악조건은 무전 뒤 | command/radio, command/command_system | F35 | test_instant_orders | 🔧 오늘 완성 — 사용자 확인 대기 | |
| F19 | 통솔범위·단위대 편성 | 직접 지휘 5개 초과면 명령 지연, 단위대(작전망) 편성 | command/organization | F18 | test_organization | ⏸ 고층·지휘대장 단계에서 | |
| F20 | 임무 조건 창 | 철수 잔압·불 발견 시·요구조자 발견 시 행동 | ui/mission_ui, command/tactical_system | F15 | ui_smoke | 🔧 평소엔 숨기고 '조건 바꾸기'로만 (지금도 기본값으로 바로 지시됨) | |
| F21 | 문 개방·파괴·문 행동 | 닫힌 문 우클릭 개방, 문 앞 목록(가스 확인·옆 벽·파괴·배연 후·대기) | simulation/door_system | F15, 카드(F37) | test_entry_flow, test_field_work | ✅ | |
| F22 | 유도로프·비상용승강기 | 지하 시계 0 구역 유도로프, 화재층 2개층 아래까지 승강기 | simulation/lifeline_system, elevator_system | F15 | test_highrise, test_stages | ⏸ 해당 스테이지에서 | |

## 5. 인명검색·구조

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F23 | 인명검색·발견·구조 | 방별 탐색, 육안·열화상·소리로 발견, 보고 후 업고 집결지로 | simulation/rescue_system, command/tactical_system | 시야(F34), 구역(F26) | test_missions, test_rescue_hazards, test_apt_bots | ✅ (봇 확인됨) | |
| F24 | 요구조자 상태·자력 대피·119 신고 | 연기 노출로 악화, 자력 대피, 갇히면 상황실 신고(세대·층만) | units/victim, simulation/evac_system | F34·F35 | test_general | ✅ | |
| F25 | 창가 요구조자·투신 위험·인명구조매트 | 창가에서 구조 요청, 투신 위험 카드, 매트 | simulation/hazards/fall_system | F12 | test_falls | ⏸ 아파트 단계에서 | |
| F26 | 안전구역·환자 집결지·진입통제선 | 끌어서 지정 → 조가 가서 30초 설치(빈 조 없으면 운전원 60초 뒤) | command/zone_system, ui/zone_draw | F23, 구급(F44) | test_zones | 🔧 설치를 기다리는 시간이 길고 표시가 약함 | |

## 6. 물·방수

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F27 | 수관 연장·방수·물 소모·수손 | 펌프차 우클릭 수관, 직사·분무·펜슬링, 물탱크 소모, 수손 누적 | simulation/suppression/water_system, hose_line | F11, 화재(F30) | test_suppression, test_streams, test_nozzle | ✅ | |
| F28 | 연결송수관·옥내소화전·방수구 | 송수구 연결, 층 방수구에서 수관 | simulation/suppression/water_system | F27 | test_highrise | ⏸ 아파트 단계에서 | |
| F29 | 배연 (송풍기 양압·창 깨기) | 출입문 송풍기, 배출구 창 | simulation/suppression/vent_system | 연기(F31) | test_tactical | ⏸ 고급 전술 — 나중에 | |

## 7. 화재·연기

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F30 | 화재 번짐·단계 | 칸 단위 연소 + 구획 2층 모델, 플래시오버·백드래프트·재발화 | simulation/fire_sim, grid/fuel_grid, compartment/*, hazards/hazard_system, rekindle_system | 거의 모든 기능 | test_fire, test_spread, test_fire_extras | ✅ (수치 검수는 나중) | |
| F31 | 연기 이동·계단실·샤프트 | 구획 사이 연기 흐름, 계단실 연기, 샤프트로 상층 확대 | simulation/compartment/*, hazards/shaft_system | F34, F24 | test_fire_extras | ✅ | |
| F32 | 붕괴·낙하물·인접 건물 복사열 | 붕괴 징후·반경, 낙하물 경고, 인접 건물 가열 | simulation/hazards/collapse_system, exposure_system | F26 | test_exposure | ⏸ 스테이지 3에서 | |
| F33 | 가스 누출·밸브 차단 | LPG 누출, 밸브 우클릭 차단 | simulation/hazards/gas_system | — | test_alley | ⏸ 주택 ③ 시나리오에서 | |

## 8. 시야·정보·무전

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F34 | 정보 안개·열화상(T) | 대원·차량·지휘관이 본 곳만 보이고, 본 적 있는 곳은 기억 | simulation/perception | 거의 모든 화면 | test_crew_and_vision | ✅ | |
| F35 | 무전 보고·전술상황판(보고된 것만) | 대원 보고가 지휘망으로 와서 상황판에 오름, 우선순위 줄 | command/radio, command/knowledge_board, ui/radio_log_panel | F02·F07 | test_board | 🔧 보고가 많고 무전 기록 읽기 어려움 — 정리 | |
| F36 | 도면 정보 | 관리사무소 도면 받으면 구조를 앎(층 단위 → 방 단위) | command/plan_intel | F15·F34 | test_plan | ✅ | |

## 9. 질문 카드

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F37 | 질문 카드 엔진 | 대원이 묻고 지휘관이 고름(대기열·남은 시간·선제지시), 틀린 답도 그대로 수행 | command/card_system, ui/card_ui | 거의 모든 임무 | test_cards, test_cards_r4, test_apt_cards | 🔧 카드가 너무 자주 뜸 — 분당 1~1.5장 목표로 | |
| F38 | 카드 내용 | 본 카드 + SOP 초안 19장(검수 대기) | data/cards | F37 | test_cards | ⏸ 초안은 검수 뒤에 | |

## 10. 안전

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F39 | 공기호흡기·열 스트레스·부상 | 공기 소모, 경보, 열 스트레스, 쓰러짐 | simulation/crew_condition_system | F23·F27 | test_crew_and_vision | ✅ | |
| F40 | RIT·현장안전담당·인원점검·철수·긴급탈출 | 역할 지정, PAR 보고, 전원 철수, 긴급탈출 | command/safety_system | F16 | test_safety | ✅ | |

## 11. 지휘 흐름

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F41 | 지휘권 선언·최초 상황보고·전략·대응단계 | 8항목 보고 양식, 공격/방어 전략, 대응 1단계 | command/command_system, ui/command_ui | F16·평가 | test_command | ✅ | |
| F42 | 단계 표시줄·완진·활동 종료 | ①지휘권 확립 … ⑧활동 종료, 초진·완진 선언, 종료 조건 | command/phase_system, command/mission_end_checker | 평가 | test_phases, test_mission_end | ✅ | |
| F43 | 지휘권 이양 | 지휘대 도착 → 브리핑 → 지휘대장으로 | command/command_transfer | F19 | test_transfer | ⏸ 고층 단계에서 | |

## 12. 구급

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F44 | 분류소·처치·이송 | 구급대가 인계받아 분류·처치·이송 | simulation/ems_system | F23·F26 | test_ems | ⏸ 순서 13에서 (그 전엔 구조로 끝) | |

## 13. 평가·메뉴·기타

| 번호 | 기능 | 지금 동작 | 주요 파일 | 연결 | 테스트 | 추천 | 결정 |
|---|---|---|---|---|---|---|---|
| F45 | 평가·디브리핑·다시 하기·보고서 | 5축 점수, 타임라인, 리플레이, PDF·CSV | evaluation/*, ui/debrief_ui, simulation/replay | 모든 사건 | test_evaluation, test_replay, test_scoring | ✅ (기능 완성에 맞춰 마지막에 다듬기) | |
| F46 | 대원 성장(경험치) | 플레이마다 대원 경험 누적 | evaluation/crew_growth | F45 | test_history | ⏸ 핵심이 아님 | |
| F47 | 시작 메뉴·캠페인·난이도 | 시나리오 목록, 캠페인, 훈련/실전/악조건 | ui/scenario_menu, ui/campaign_ui | — | test_campaign, test_realism | ✅ | |
| F48 | 교관 모드·맵 편집기 | 교관 사건 넣기, 건물 편집기 | ui/instructor_ui, ui/editor_ui | — | test_editor | ⏸ 나중에 | |
| F49 | 튜토리얼·힌트 | 15단계 안내(예전 조작으로 쓰여 있음) | ui/tutorial_ui, ui/hint_ui, data/tutorial | 전부 | test_tutorial, test_hints | ⏸ 맨 마지막에 완성 기능으로 다시 | |
| F50 | 원형 메뉴 코드 | 오늘 없앤 뒤 쓰지 않음 | ui/radial_menu | — | — | ➖ 지우기 | |
| F51 | 출동 지도·도시 전경 | 출동 단계의 도시 지도 | ui/city_mass_view | F09 | test_dispatch_prep | ✅ | |

## 요약 (추천 기준)

- ✅ 그대로: F03 F04 F06 F08 F09 F10 F11 F14 F16 F21 F23 F24 F27 F30 F31 F34 F36 F39 F40 F41 F42 F45 F47 F51
- 🔧 고칠 것:
  - 오늘 완성, 확인 대기: F15 F18
  - F01 단면이 가림
  - F02 평면 화면 정리
  - F05 알림 모으기
  - F13 후착대 단순화
  - F17 명령 카드 통일
  - F20 조건 창 숨기기
  - F26 구역 설치 시간
  - F35 무전 보고 정리
  - F37 카드 빈도
- ⏸ 보류(꺼 두기): F07 F12 F19 F22 F25 F28 F29 F32 F33 F38 F43 F44 F46 F48 F49
- ➖ 빼기: F50
