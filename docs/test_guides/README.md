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
