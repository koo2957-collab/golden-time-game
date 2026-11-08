# Fire Commander — 작업 안내

소방 SOP를 겪어서 익히는 2D 아이소메트릭 RTS 소방 지휘 훈련게임 (Godot 4.7, GDScript, 내부 교육용 Windows PC).

## 문서

- 목표 기획안: `docs/design.md` (사용자 기획안 원문). **이 문서대로 개발한다.**
- 기획안 대비 차이·수정 로드맵(R0~R15)·결정 사항: `docs/plan_gap.md` — 작업 순서는 여기를 따른다.
- 종료 체계·교재 근거 체계 세부 계획: `docs/next_plan.md`
- 기존 기획서(구현 이력 M0~M9d, P1): `docs/game_design.md`
- 폴더 규칙·도면 형식: `docs/folder_structure.md`, SOP 대응표: `docs/sop_mapping.md`
- 근거 자료 PDF 5권(SOP, 소방전술 화재1·화재2·구조·구급)은 저장소 루트에 있고 **커밋하지 않는다.**

## 진행 방식

- 기존 엔진(화재·대원·물·평가)은 살리고 기획안과 다른 부분만 고친다. 기획안 12장 프롬프트는 점검표로만 쓴다 (폴더 재배치·TileMapLayer 전환 안 함).
- 큰 단계(R 번호)는 로드맵 순서대로 **확인 없이 이어서 진행한다** (2026-11-08 사용자 결정, R1부터). 단계마다 테스트를 통과시키고 `docs/test_guides/<단계>.md`를 쓴 뒤 GitHub에 올리고 다음 단계로 넘어간다. 선택이 필요하면 추천안으로 정하고 문서에 남긴다.
- 결정 사항: 실전·악조건은 1배속·일시정지 없음, 훈련 난이도만 일시정지·배속. 지휘권 이양 후에는 지휘대장으로 계속 플레이.

## 코드 규칙

1. 렌더러 호환성(OpenGL 3.3), 3D 노드·실시간 광원·그림자 금지. 화면은 `_draw` 도형 (그래픽 교체는 G1 보류).
2. GDScript 정적 타입, 주석·문서·화면 문구는 한국어.
3. 시뮬레이션(`scripts/simulation/`, `scripts/command/`, `scripts/evaluation/`)은 `RefCounted` 순수 클래스, 화면 코드를 참조하지 않는다. 고정 틱(10틱/초) + 시드 결정론 — 다시 하기가 깨지면 안 된다.
4. 수치·카드·유닛·시나리오는 `data/*.json`에만 둔다. 수치마다 `source`(교재 / 공학식 / 추정)를 붙인다.
5. 판정은 SOP 조항으로, 설명은 교재(책·장·쪽)로 근거를 단다.
6. 작업 단위마다 `tests/`에 테스트를 추가한다.

## 실행·테스트

Godot은 PATH에 없고 PC마다 위치가 다르다: `C:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` 또는 `C:\Users\koo29\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`

```
godot --headless --path . -s res://tests/run_tests.gd   # 단위 테스트 (10분 이상 — 백그라운드로)
godot --path . -s res://tests/ui_smoke.gd               # 조작 점검 (창이 열림)
```

새로 클론한 뒤에는 `godot --headless --path . --import`를 한 번 먼저 돌린다.
