# 소방 지휘관 RTS 훈련게임 (Godot 4)

소방관 직원교육용 실시간 지휘 훈련게임이다. 플레이어는 선착대장→지휘대장으로서 대원에게 임무를 주고, 대원이 SOP 판단을 질문 카드로 물으면 고른다. 틀린 답도 그대로 수행되고 결과가 나온다.

## 문서 위치
- 기획안: docs/design.md (절 번호로 찾아 읽어라. 전체를 매번 읽지 말고 프롬프트가 지정한 절만 읽어라)
- 진행 기록: docs/progress.md (작업이 끝날 때마다 한 줄씩 추가)
- 교재 발췌: docs/sop/ (있으면 카드·수치 근거로 사용)
- 단계별 프롬프트: .claude/commands/ (사용자가 /p0, /p10-1 처럼 실행)

## 지금 상황: 이미 만든 프로그램을 고치는 중
- 이 게임은 Claude Code로 만들고 있고, 기획안을 고치기 전 버전까지 프로그램이 이미 만들어져 있다.
- 그 뒤 기획안(docs/design.md)과 프롬프트(.claude/commands/)가 여러 번 바뀌었다. 그래서 프롬프트는 새로 만드는 지시가 아니라 **기존 프로그램을 고치는 지시**다.
- 기획안·프롬프트 내용과 현재 코드가 다를 수 있다. 기획안이 항상 맞다고 가정하지 마라.

## 기획안과 현재 구현이 다를 때 (모든 프롬프트에 적용)
1. 구현 전에 관련 코드를 읽고, 다른 점마다 아래 표를 만들어 보여라.

   | 항목 | 기획안 | 현재 구현 | 비슷한 상용 게임의 방식 | 추천 | 이유 |
   | --- | --- | --- | --- | --- | --- |

2. 추천은 상용 게임(스타크래프트, 컴퍼니 오브 히어로즈, 레인보우 식스·Door Kickers, 프로스트펑크, EMERGENCY 시리즈 등)에서 검증된 조작 방식을 빌려, 처음 하는 소방관도 설명 없이 알 수 있는 쪽을 고른다. 판단 기준:
   - 조작이 직관적인가 (클릭 수, 손 이동, 익숙한 관례)
   - 이 게임의 원칙에 맞는가 (지휘관 시점, 내부는 임무·무전으로, 보고된 정보만 상황판에, SOP 근거)
   - GPU 없는 사무실 PC에서 가벼운가
   - 이미 잘 동작하는 코드를 살릴 수 있는가 (같은 수준이면 현재 구현을 살린다)
3. 기획안과 현재 구현 둘 다 아닌 제3의 방식이 더 나으면 그것도 제안한다.
4. 표를 보여 준 뒤 사용자가 고를 때까지 구현하지 마라. 사소한 차이(이름, 파일 위치)는 표 없이 한 줄로 알리고 진행해도 된다.
5. 결정은 docs/decisions.md 에 "날짜 · 항목 · 고른 방식 · 이유"로 남기고, 기획안과 달라진 점은 사용자가 기획안에 옮길 수 있게 마지막에 요약한다.

## 작업 방식
1. 먼저 관련 코드를 찾아 현재 상태를 보고하고, 계획을 보여 준 뒤 승인을 받아 구현한다.
2. 작업 단위마다 tests/ 에 headless 테스트를 추가하고 `godot --headless -s tests/run_all.gd` 로 통과시킨다.
3. 통과하면 git 커밋한다. 커밋 메시지는 "P번호: 내용".
4. 끝나면 docs/progress.md 에 프롬프트 번호, 바뀐 파일, 남은 문제를 적는다.

## 코드 규칙
1. 렌더러는 Compatibility. 3D 노드, 실시간 광원·그림자 금지 (GPU 없는 사무실 PC 대상).
2. GDScript 정적 타입 필수, 주석은 한국어.
3. 시뮬레이션 코드(scripts/sim/)는 Node를 상속하지 않는 순수 클래스(RefCounted)로 쓰고 화면 코드를 참조하지 않는다.
4. 수치·카드·유닛·스테이지·명령 목록은 res://data/*.json 에만 둔다. 코드에 숫자를 박지 않는다.
5. 모든 수치에 source 필드(교재 근거 / 공학 표준 / 게임 설정값)를 붙인다.
6. 시스템 간 통신은 EventBus 오토로드 시그널로 한다.
7. 화면에 보이는 것과 별개로, 전술상황판·평가는 무전으로 보고된 정보(KnowledgeBoard)만 쓴다.
8. 시간은 SimClock 현장 시간(time_scale 적용)과 UI용 실제 시간을 구분한다.

## 폴더 구조
autoload/ scripts/sim/ scripts/units/ scripts/cards/ scripts/ui/ scenes/ data/ maps/ tests/ docs/

## 이 저장소의 실제 경로·테스트 (2026-11-10 덧붙임 — 위 규칙의 경로와 다름)
- 위 폴더 구조·`scripts/sim/`·`tests/run_all.gd`는 기획안 기준 이름이다. 이 저장소는 `scripts/simulation/`(시뮬레이션), `scripts/command/`(지휘·카드·무전), `scripts/evaluation/`, `scripts/autoload/`(EventBus·GameManager), 수치는 `data/` 아래 영역별 JSON을 쓴다. 옮기지 않는다 (docs/decisions.md).
- 테스트: `godot --headless --path . -s res://tests/run_tests.gd` (전체 10분 이상), 파일 하나만은 `-- test_fire.gd`, 화면 점검은 `godot --path . -s res://tests/ui_smoke.gd`. 작업 중에는 관련 테스트만, 전체는 단계 끝·푸시 전.
- Godot: `C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` (PC마다 다름). 새로 클론하면 `--import` 먼저.
- 점검 보고서 docs/audit.md, 교재 대조 docs/fire_textbook_check.md, 단계별 안내 docs/test_guides/.
