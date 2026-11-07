# 폴더 구조와 규칙

원칙: **로직(scripts) · 화면(scenes) · 내용(data)을 분리**한다.
시나리오와 SOP 규칙, 성상 수치는 코드 수정 없이 `data/`만 고쳐서 바꿀 수 있어야 한다.

```
assets/            원본 리소스 (sprites, tilesets, ui, audio/sfx, audio/music, fonts)
scenes/
  main/            진입 씬 (main.tscn)
  world/           게임 월드 (Map / Units / Effects / Camera2D / UI)
  units/ vehicles/ ui/ debrief/
scripts/
  autoload/        전역 싱글톤 (EventBus, GameManager)
  command/         지휘 계층: 지휘권, 무전, 통솔범위, 명령 객체
  simulation/      시뮬레이션 코어 (화면과 분리, 고정 틱)
                   sim_world.gd(전체 상태·명령 실행), sim_clock.gd(고정 틱 시계), json_data.gd,
                   fire_sim.gd(화재 통합·사건 판정), fire_config.gd(화재 수치·재질), param_table.gd,
                   door_system.gd(문 개방·폐쇄·파괴), crew_condition_system.gd(자세·복사열·열 스트레스·공기호흡기),
                   perception.gd(정보 안개·시야·열화상)
    compartment/   구획(방) 2층 모델: compartment.gd, opening.gd(문·창·계단), compartment_model.gd(계산)
    grid/          건물 도면(building_data.gd), 길찾기(pathfinder.gd), 셀 연소(fuel_grid.gd)
    hazards/       특수현상 대응 판정 (M4): 백드래프트, 롤오버, FGI, 붕괴
    suppression/   물 공급·방수(water_system.gd), 수관(hose_line.gd). 배연은 M4
  units/           대원, 출동대, 차량, 요구조자
  scenario/        시나리오 로더, 검증기, 이벤트 트리거
  evaluation/      사건 기록(sim_event_log.gd), SOP 규칙 판정, 채점, 디브리핑
  ui/
data/
  buildings/       건물 도면 JSON (층별 문자 격자 + 방 목록)
  scenarios/       시나리오 JSON (기본 제공분)
  sop/             SOP 규칙 라이브러리 (조항 ID 기준)
  fire/            화재 성상 수치 (교재 근거 값)
  materials/       재질·가연물 특성
  units/           대원·차량·장비 능력치
docs/              기획 문서
tests/             단위 테스트(test_*.gd)와 조작 점검(ui_smoke.gd)
```

## 건물 도면 형식 (`data/buildings/*.json`)

층마다 `grid`(문자 행, 1문자 = 0.5m 셀)와 `rooms`(방 id·이름·rect[x, y, w, h])를 둔다.

| 문자 | 의미 | 통행 |
|---|---|---|
| ` ` | 빈 공간 (위층의 건물 바깥) | 불가 |
| `,` | 마당 | 가능 |
| `=` | 도로 | 가능 |
| `.` | 실내 바닥 | 가능 |
| `#` | 벽 | 불가 |
| `D` | 문 | 가능 |
| `W` | 창 | 불가 (M1 기준) |
| `S` | 계단 — 위아래 층의 같은 위치가 모두 `S`이면 층간 이동 지점 | 가능 |

`hydrants`는 소화전 위치 목록(가장 아래층 셀)이다. `-`는 보도(사람만 통행)다.

차량은 차체 전체가 차도(`=`) 위에 있어야 하며, 제자리에서 돌지 않고 차체 방향(heading) 그대로 전진·후진만 한다.
목표 지점은 차체 축에 투영되고, 차도를 벗어나거나 다른 차량과 겹치기 직전에서 멈춘다.
회전반경을 고려한 방향 전환은 교차로가 있는 지도를 만들 때(M8) 추가한다.

`faces`는 방면 명칭(SOP 105-2.2: 전면 A, 시계방향 B·C·D)과 방향(south/west/north/east)의 대응이다.

- 방(`rooms`)마다 `lining`(내장재 재질)을 줄 수 있다. 생략하면 `내장재`, `불연`이면 타지 않는다.
- 층마다 `furniture`(가구 목록: name, material, rect)를 둔다. material은 `data/materials/materials.json`의 이름이다.
- 문·창은 같은 문자가 이어진 묶음 하나가 개구부 하나다. 외부 출입문은 처음에 닫혀 있고, 실내 문은 열려 있다
  (시나리오의 `fire.doors_closed` / `doors_open`으로 바꿀 수 있다).

## 화재 모델 요약

| 계층 | 내용 |
|---|---|
| 셀 연소 (`fuel_grid.gd`) | 셀마다 연료·누적 열량. 옆 화염 + 천장 고온층 복사열로 착화, 재질별 성장 시간 |
| 구획 모델 (`compartment_model.gd`) | 상부층 온도(MQH 상관식), 연기층(플룸·개구부 유출), 산소, 미연소가스, 그을음(가시거리) |
| 사건 (`fire_sim.gd`) | 상부층이 방별 플래시오버 온도(교재 483~649℃, 시드)에 도달하면 방 전체 동시 착화, 유리창 파손, 단계 변화, 연기 유입 |

## 대원 상태·시야 요약 (M4a)

| 요소 | 내용 |
|---|---|
| 문 | 닫힌 문은 통과 불가(길찾기 막힘). 개방 3초(1명), 잠긴 문 파괴 60초(문 앞 2명 이상). 파괴된 문은 닫을 수 없음. 문 상태가 바뀌면 환기 조건도 바뀜 |
| 자세 | 연기층이 서 있는 눈높이(1.6m)보다 내려오면 낮은 자세: 이동 속도 절반, 고온층 복사 절반, 시선이 하부층(더 맑음) |
| 복사열 | 고온층 복사 + 같은 구획 화염 복사 (벽 너머는 없음). 10kW/㎡ 이상 칸으로는 들어가지 않고, 그런 칸에 있으면 물러남 |
| 열 스트레스·공기호흡기 | 1.7kW/㎡ 초과분만큼 쌓임, 한계면 행동 불능. 건물 안에서 분당 40~80L, 18% 경보, 소진 시 행동 불능. 바깥 차량 옆 60초면 용기 교체 |
| 정보 안개 | 건물 밖은 항상 보임. 실내는 대원 시선·창(투명)·열린 문으로 보이는 곳만. 본 곳은 마지막 상태를 기억 |
| 시야 | 칸마다 그을음 가시거리로 "흐림" 누적: 1까지 형체, 3까지 화염 불빛. 랜턴 +0.5m. 열화상카메라 조는 연기 무시 15m(유리 통과 불가) |
| 방수 | 사거리 밖이면 다가가서 쏘고, 보이는 화점이 없으면 남은 화점이 보이는 (열기가 견딜 만한) 위치로 전진 |

수치는 `data/units/firefighter.json`에 있다. 검증은 `tests/test_crew_and_vision.gd`.

## 진압 모델 요약 (M3)

| 요소 | 내용 |
|---|---|
| 물 공급 | 펌프차 탱크 → 관창. 소화전 점령 시 탱크 계속 보충, 물탱크차는 펌프차에 급수 |
| 수관 | 펌프차에서 관창 조까지 경로를 따라 깔림. 조가 움직이면 늘어나고, 적재 길이(10본 × 15m)를 넘으면 멈춤. 끄는 조는 느려짐. 수관이 연결된 펌프차는 이동 불가 |
| 방수 | 관창수가 목표 방 안의 화점을 따라 물줄기를 훑음. 직사(12m, 가연물 냉각) / 분무(4m, 고온층 냉각). 벽·닫힌 문에 막힘 |
| 소화 | 물 1L = 2.6MJ 흡열. 셀 열방출률의 50초분 열을 빼앗으면 꺼짐. 젖은 셀은 물이 마를 때까지 재착화 안 됨 (재발화 가능) |
| 수손 | 상부층 100℃ 미만인 방에서 불 없는 곳에 뿌린 물 |

보정 목표는 `tests/test_suppression.gd`가 지킨다: 성장기 거실 → 관창 1개로 30초 안 진화, 최성기 거실 → 1~2분 진압.

수치는 모두 `data/fire/fire_params.json`·`data/materials/materials.json`·`data/units/vehicles.json`에 있고 출처(교재/공학식/추정)가 표시되어 있다.
교재 범위는 `tests/test_fire.gd`가 지킨다. 수치를 바꾼 뒤에는 반드시 단위 테스트를 돌린다.

## 테스트 실행

```
godot --headless --path . -s res://tests/run_tests.gd   # 단위 테스트
godot --path . -s res://tests/ui_smoke.gd               # 조작 점검 (창이 잠깐 열림)
```

- `project.godot`를 직접 수정할 때는 Godot 에디터를 닫는다. 열려 있으면 에디터가 이전 설정으로 덮어쓴다.
- `ui_smoke.gd`처럼 `-s`로 실행하는 스크립트는 autoload(EventBus 등)를 쓰는 클래스를 타입으로 참조하지 않는다.

## 규칙

- `scripts/simulation/`은 노드나 화면에 의존하지 않는다. (UI 없이 테스트 가능해야 함)
- 모든 수치는 `data/`에 두고, 교재 근거가 없는 값은 `"source": "추정"`으로 표시한다.
- 사용자 추가 시나리오는 `user://scenarios/`에서 불러온다.
- 빈 폴더의 `.gitkeep`은 폴더 유지용이며, 파일이 생기면 지워도 된다.
- `*.gd.uid` 파일은 Godot가 생성하는 리소스 ID다. 지우지 말고 함께 버전 관리한다.
