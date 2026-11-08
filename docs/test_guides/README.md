# 테스트 방법 모음

단계(마일스톤)마다 자동 테스트 명령과 직접 해 보는 확인 절차를 파일 하나로 정리한다.

## 공통 준비

- Godot 실행 파일 (예): `C:\Users\koo29\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- 아래 명령은 프로젝트 폴더(`F:\golden time game\새-게임-프로젝트`)에서 실행한다. `GODOT`은 위 실행 파일 경로.
- 새 스크립트를 받은 뒤 처음에는 한 번 가져오기를 한다: `GODOT --headless --path . --import`

| 할 일 | 명령 |
|---|---|
| 단위 테스트 전체 (약 15분) | `GODOT --headless --path . -s res://tests/run_tests.gd` |
| 단위 테스트 한 파일 | `GODOT --headless --path . -s res://tests/run_tests.gd -- test_safety` (파일 이름 일부) |
| 조작 점검 (창이 잠깐 열림, 약 3분) | `GODOT --path . -s res://tests/ui_smoke.gd` |
| 게임 실행 | Godot 편집기에서 프로젝트를 열고 F5, 또는 `Godot_v4.7.2-stable_win64.exe --path .` |

결과 줄이 `결과: N 통과, 0 실패`, 조작 점검은 `조작 점검: 모두 통과`면 정상이다.

## 단계별 문서

| 단계 | 문서 |
|---|---|
| M6a 평가·디브리핑 | [M6a_evaluation.md](M6a_evaluation.md) |
| M6b 시나리오·다시 하기 | [M6b_scenarios_replay.md](M6b_scenarios_replay.md) |
| M6.5 2025 SOP 정합화 | [M6.5_sop2025.md](M6.5_sop2025.md) |
| M7a 명령칸·교육 모드 | [M7a_command_cards.md](M7a_command_cards.md) |
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
| **R1~R5 빠른 점검 (한 판으로 확인)** | [R1-R5_빠른점검.md](R1-R5_빠른점검.md) |
