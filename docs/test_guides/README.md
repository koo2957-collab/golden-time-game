# 테스트 방법 모음

단계(마일스톤)마다 자동 테스트 명령과 직접 해 보는 확인 절차를 파일 하나로 정리한다.

## 공통 준비

- `GODOT`은 이 PC의 Godot 4.7.2 콘솔 실행 파일(`Godot_v4.7.2-stable_win64_console.exe`) 경로다. PC마다 위치가 다르다.
  - 예: `C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
  - 예: `C:\Users\<사용자>\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- 아래 명령은 프로젝트 폴더(`project.godot`이 있는 곳)에서 실행한다.
- 새 스크립트를 받은 뒤 처음에는 한 번 가져오기를 한다: `GODOT --headless --path . --import`

| 할 일 | 명령 |
|---|---|
| 단위 테스트 전체 (약 26분) | `GODOT --headless --path . -s res://tests/run_tests.gd` |
| 관련 테스트만 (여러 개는 쉼표) | `GODOT --headless --path . -s res://tests/run_tests.gd -- test_cards,test_missions` |
| 한 파일만 정확히 | `GODOT --headless --path . -s res://tests/run_tests.gd -- test_building.gd` |
| 조작 점검 (창이 잠깐 열림, 약 3분) | `GODOT --path . -s res://tests/ui_smoke.gd` |
| 건물 화면 점검 (외부 보기·단면, 스크린샷·프레임 측정, 약 1분 30초) | `GODOT --path . -s res://tests/ui_cutaway.gd` |
| 게임 실행 | Godot 편집기에서 프로젝트를 열고 F5, 또는 `게임_실행.bat` |

- 이름 일부(`test_cards`)는 파일 이름과 테스트 이름 모두에서 찾는다. 그래서 다른 파일의 같은 이름 테스트도 함께 돈다. 파일 하나만 돌리려면 `.gd`까지 쓴다.
- 결과 줄이 `결과: N 통과, 0 실패`, 조작 점검은 `조작 점검: 모두 통과`면 정상이다.
- 끝에 **파일별 시간(느린 순)**과 **실패한 테스트 목록**이 나온다.

## 언제 무엇을 돌리나

| 언제 | 무엇을 |
|---|---|
| 기능 하나를 만들거나 고칠 때마다 | 아래 대응표에서 **고친 곳의 테스트 + 그 기능의 새 테스트** |
| 시뮬레이션 핵심(아래 "핵심" 줄)을 고쳤을 때 | 위에 더해 **핵심 묶음** |
| 큰 단계(R 번호)가 끝날 때, GitHub에 올리기 전 | **전체 테스트 1회** (백그라운드로) |

핵심 묶음 (약 40초): `test_replay.gd,test_units.gd,test_evaluation.gd,test_scoring.gd,test_building.gd,test_sim_clock.gd`
(다시 하기 결정론·대원 이동·평가가 깨지지 않았는지 본다. 화재 수치는 느려서 전체 테스트 때 본다 — 화재 계산 자체를 고쳤을 때만 `test_fire.gd`를 더한다)

### 느린 파일 (2026-11-09 측정, 전체 약 26분)

대응표에서 아래 파일이 나오면 몇 분 걸린다. 한 번에 여러 개를 고르지 말고 꼭 필요한 것만 고른다.

| 파일 | 시간 |
|---|---|
| test_rescue_hazards | 약 3분 40초 |
| test_transfer | 약 3분 30초 |
| test_highrise | 약 2분 40초 |
| test_ems | 약 2분 30초 |
| test_suppression | 약 2분 20초 |
| test_fire | 약 2분 15초 |
| test_phases | 약 2분 15초 |
| test_crew_and_vision | 약 1분 10초 |
| test_overhaul | 약 1분 |

나머지는 모두 40초 이하이고, 대부분 15초 이하다.

## 고친 곳 → 돌릴 테스트 (대응표)

| 고친 곳 | 돌릴 테스트 |
|---|---|
| **핵심** `scripts/simulation/sim_world.gd`, `sim_clock.gd`, `replay.gd`, `grid/` | 핵심 묶음 + `test_pathfinder.gd` |
| 화재 계산 `fire_sim.gd`, `fire_config.gd`, `compartment/`, `data/fire/` | 핵심 묶음 + `test_fire.gd` |
| `scripts/simulation/suppression/` (수관·방수·방수포·송풍기·물탱크차) | `test_suppression,test_streams,test_shuttle,test_apartment` |
| `scripts/simulation/hazards/` (붕괴·인접 건물·낙하·가스) | `test_exposure,test_falls,test_general,test_rescue_hazards` |
| `rescue_system.gd`, `evac_system.gd`, `perception.gd`, `door_system.gd` | `test_rescue_hazards,test_crew_and_vision,test_general,test_plan` |
| `crew_condition_system.gd`, `lifeline_system.gd` (공기·열·호흡량·라이트라인) | `test_numbers,test_crew_and_vision,test_safety,test_stages` |
| `ems_system.gd` (구급) | `test_ems,test_falls` |
| `elevator_system.gd` | `test_transfer,test_stages` |
| `scripts/units/` (대원 이동·2인 1조·길찾기) | `test_units,test_pathfinder` |
| `scripts/command/` 지휘·무전·진입 명령 | `test_command,test_safety,test_organization` |
| `scripts/command/tactical_system.gd` (분대 명령칸) | `test_tactical,test_missions` |
| `scripts/command/interior_orders.gd`, 임무·임무 조건 | `test_interior,test_missions` |
| `scripts/command/card_system.gd`, `data/cards/` | `test_cards,test_cards_r4` |
| `scripts/command/phase_system.gd`, `data/command/phase_params.json` (초진·완진·종료) | `test_phases,test_overhaul` |
| `scripts/command/command_transfer.gd` (지휘권 이양) | `test_transfer` |
| `scripts/command/plan_intel.gd` (도면·미니맵 정보) | `test_plan` |
| `site_survey.gd` (360° 둘러보기·관계인 진술) | `test_site_survey` |
| 차량 배치·골목 | `test_placement,test_alley` |
| `scripts/evaluation/` 평가·판정, `data/sop/rules.json` | `test_evaluation,test_scoring,test_debrief_ext` |
| 보고서·CSV·대원 성장 (`report_export.gd`, `crew_growth.gd`) | `test_debrief_ext,test_campaign` |
| `data/sop/hints.json`, 교육 힌트 | `test_hints` |
| 난이도 (훈련·실전·악조건) | `test_realism,test_cards,test_interior` |
| `scripts/scenario/`, `data/scenarios/` | `test_scenario_loader` + 그 시나리오의 테스트 (예: 스테이지 → `test_stages`, 15층 → `test_highrise`) |
| `data/buildings/` 건물 지도 | `test_building` + 그 건물을 쓰는 시나리오의 테스트 |
| `data/campaign/`, 내 기록·교관 설정 | `test_campaign,test_history` |
| `data/tutorial/`, 튜토리얼 | `test_tutorial` |
| 시나리오 편집기 | `test_editor` |
| `data/units/` 대원·차량·장비 수치 | `test_units,test_numbers` |
| `scripts/ui/building/` 층 쌓기·벽 모양 (`floor_stack.gd`, `view_params.gd`), `data/ui/view_params.json` | `test_cutaway` |
| `scripts/ui/iso_view.gd`, `scripts/ui/building/floor_layer.gd`, `data/ui/tile_skin.json` (입체 화면 그리기) | 건물 화면 점검(`ui_cutaway.gd`) + 조작 점검 |
| 화면 코드만 (`scripts/ui/`, `scenes/`) | 단위 테스트 대신 **조작 점검**(`ui_smoke.gd`) + 직접 확인 |

## 단계별 문서

| 단계 | 문서 |
|---|---|
| M6a 평가·디브리핑 | [M6a_evaluation.md](M6a_evaluation.md) |
| M6b 시나리오·다시 하기 | [M6b_scenarios_replay.md](M6b_scenarios_replay.md) |
| M6.5 2025 SOP 정합화 | [M6.5_sop2025.md](M6.5_sop2025.md) |
| M7a 명령칸·교육 모드 | [M7a_command_cards.md](M7a_command_cards.md) |
| P10-2 ⓐ 명령 카드·진입 허가 요청·인원 점검 | [P10-2a_command_card_entry.md](P10-2a_command_card_entry.md) |
| P10-2 ⓑ 구역 지정·분류소 | [P10-2b_zones.md](P10-2b_zones.md) |
| P10-2 ⓒ 구조자 운반·START 분류 | [P10-2c_rescue_triage.md](P10-2c_rescue_triage.md) |
| P4-2 원형 메뉴·진입 지시 4단계·문 앞 휠 | [P4-2_entry_flow.md](P4-2_entry_flow.md) |
| M7b-1 인접 건물·가스·붕괴·후착대 | [M7b1_exposure.md](M7b1_exposure.md) |
| M7b-2 구급대·운전원 | [M7b2_ems.md](M7b2_ems.md) |
| M7c-1 튜토리얼 | [M7c1_tutorial.md](M7c1_tutorial.md) |
| M7c-2 내 기록·교관 설정 | [M7c2_history_instructor.md](M7c2_history_instructor.md) |
| M7c-3 대원 개성·캠페인 | [M7c3_traits_campaign.md](M7c3_traits_campaign.md) |
| M8a 선착 차량 배치 | [M8a_placement.md](M8a_placement.md) |
| M8b-1 아파트화재 ① (연결송수관·방화문) | [M8b1_apartment.md](M8b1_apartment.md) |
| 화면 점검 (시점·대원 비율·차량) | [V1_view_scale.md](V1_view_scale.md) |
| M8b-2 아파트화재 ② (상층 확대·공기안전매트·낙하물) | [M8b2_falls.md](M8b2_falls.md) |
| M9a 일반건축물 ① (자력 대피·샤프트·간판) | [M9a_general.md](M9a_general.md) |
| M9b 물탱크차 순환보수 | [M9b_shuttle.md](M9b_shuttle.md) |
| M9c 골목 안 주택 (진입·회차) | [M9c_alley.md](M9c_alley.md) |
| M9d 시나리오 편집기 | [M9d_editor.md](M9d_editor.md) |
| R1 종료 체계 (활동 단계·초진·완진 선언) | [R1_end.md](R1_end.md) |
| R2 실시간 규칙 (난이도 훈련·실전·악조건) | [R2_realtime.md](R2_realtime.md) |
| R3 질문 카드 엔진 | [R3_cards.md](R3_cards.md) |
| R4 질문 카드 확장 (28장) | [R4_cards30.md](R4_cards30.md) |
| R5 평가 배점·SOP 준수 축 | [R5_scoring.md](R5_scoring.md) |
| R6a 화면 배치 ① (상황판·층 막대·자막) | [R6a_screen.md](R6a_screen.md) |
| R6b 화면 배치 ② (하단 콘솔·Home) | [R6b_console.md](R6b_console.md) |
| R7a·R7b 임무형 내부 지휘 ① (무전 지시·층 단위 임무·임무 조건) | [R7ab_missions.md](R7ab_missions.md) |
| R7c 임무형 내부 지휘 ② (원형 메뉴·팀 카드 끌어다 놓기) | [R7c_radial.md](R7c_radial.md) |
| R8 도면·미니맵 (구조는 직접 밝힌다) | [R8_plan.md](R8_plan.md) |
| R9 수치 정비 (CO 교재 표·호흡량·산소·출구 공기·편성) | [R9_numbers.md](R9_numbers.md) |
| R10 스테이지 2-1 (15층 아파트·옥내소화전·출동 준비) | [R10_highrise.md](R10_highrise.md) |
| R11 주수 확장·송풍기 양압배연 | [R11_streams.md](R11_streams.md) |
| R12 디브리핑 확장 (리플레이 보기·보고서·대원 성장) | [R12_debrief.md](R12_debrief.md) |
| R13 지휘권 이양·지휘대장·비상용승강기 (2-2) | [R13_transfer.md](R13_transfer.md) |
| R14 나머지 스테이지 (0·1-2·3-1·3-2·3-3·4-1) | [R14_stages.md](R14_stages.md) |
| R15 배포 (성능 표시·벤치마크·내보내기) | [R15_deploy.md](R15_deploy.md) |
| R16 화면 개선 (지휘관 드래그·미니맵·입면 층 막대·외부 보기) | [R16_screen.md](R16_screen.md) |
| R17 건물 두 모습 (외부 보기·인형집 단면·프레임 측정) | [R17_cutaway.md](R17_cutaway.md) |
| **최종 보고서** (기획서 대비 구현·개선점) | [../최종_보고서.md](../최종_보고서.md) |
| **R1~R5 빠른 점검 (한 판으로 확인)** | [R1-R5_빠른점검.md](R1-R5_빠른점검.md) |
