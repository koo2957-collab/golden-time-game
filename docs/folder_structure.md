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
  command/         지휘 계층: command_system.gd(지휘권·상황보고·전략·진입 명령·대원 보고·자동 감속),
                   resource_system.gd(후착대·대기1단계·투입·지원 요청), organization.gd(단위대·통솔범위·작전망),
                   site_survey.gd(둘러보기·물증·진술·현장지휘소), witness.gd(관계인),
                   safety_system.gd(긴급탈출·무선 침묵·인원점검·RIT·현장안전담당),
                   tactical_system.gd·tactical_command.gd(분대 명령칸 고수준 명령),
                   radio.gd(무전 채널), 명령 객체(move_command, equipment_command, command_order), command_log.gd
  simulation/      시뮬레이션 코어 (화면과 분리, 고정 틱)
                   sim_world.gd(전체 상태·명령 실행), sim_clock.gd(고정 틱 시계), json_data.gd,
                   fire_sim.gd(화재 통합·사건 판정), fire_config.gd(화재 수치·재질), param_table.gd,
                   door_system.gd(문 개방·폐쇄·파괴), crew_condition_system.gd(자세·복사열·열 스트레스·공기호흡기),
                   perception.gd(정보 안개·시야·열화상), rescue_system.gd(요구조자·검색·구조), ems_system.gd(구급 처치·이송)
    compartment/   구획(방) 2층 모델: compartment.gd, opening.gd(문·창·계단), compartment_model.gd(계산)
    grid/          건물 도면(building_data.gd), 길찾기(pathfinder.gd), 셀 연소(fuel_grid.gd)
    hazards/       특수현상(hazard_system.gd): 롤오버 징후, 플래시오버 피해, 백드래프트 징후·폭발, 350℃ 경고, 인접 건물 연소(exposure_system.gd), 가스(gas_system.gd), 붕괴(collapse_system.gd)
                   잔불정리·재발화(rekindle_system.gd)
    suppression/   물 공급·방수(water_system.gd), 수관(hose_line.gd). 배연은 M4
  units/           대원, 출동대, 차량, 요구조자
  scenario/        시나리오 목록·검증(scenario_loader.gd). 이벤트 트리거는 M8
  evaluation/      사건 기록(sim_event_log.gd), 상태 기록(sim_recorder.gd), SOP 판정·평가·디브리핑 자료(evaluator.gd)
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

## 지휘 요약 (M5a)

| 요소 | 내용 |
|---|---|
| 출동 지령 | 시나리오 `dispatch`: 신고 내용·대상·시간·날씨. 신고로 구조대상자 가능성이 알려졌으면(`reported_victims`) 상황보고의 '구조대상자 있음'이 정답 |
| 지휘권 선언 | 최초 상황보고 9개 항목(SOP 101-2.1)을 보기에서 골라 무전 송신. 송신이 끝난 시각이 선언 시각. 그때까지 확인할 수 있던 사실과 비교해 기록(점수는 M6). 활동 계획·지원 요청은 기록만 |
| 진입 명령 | 출동대별. 명령 전에는 건물 밖 대원의 경로를 입구 앞에서 자른다. 지휘관은 혼자 들어가지 않는다 |
| 전략 | 공격·방어·병행. 방어로 바꾸면 진입 허가를 거두고 내부 대원을 가장 가까운 열린 외부 문 밖으로 철수. 방어 중 진입 명령은 받지 않는다(병행으로 바꾸고 진입할지 묻는다). 추천 전략(추정): 플래시오버 전 공격, 이후 구조대상자 가능성 있으면 병행, 없으면 방어 |
| 무전 | 한 채널, 한 번에 한 송신. 우선순위 대원 안전 → 구조대상자 → 주요요소 → 전략·전술. 송신 시간 = 호출 + 글자 수 비례. 명령은 송신이 끝나야 전달되고 받는 쪽이 복명복창 |
| 대원 보고 | 공기 경보·행동 불능·특수현상 징후·요구조자 발견·검색 완료·진입 등을 무전으로 보고. 대원 안전·구조대상자 무전은 화면 알림으로도 띄운다 |
| 자동 감속 | 행동 불능·공기 경보·요구조자 발견·특수현상·플래시오버가 생기면 1배속 |

수치는 `data/command/radio_params.json`. 검증은 `tests/test_command.gd`.

## 자원·조직 요약 (M5b)

| 요소 | 내용 |
|---|---|
| 지도 | 가로 72칸(36m). 도로 동쪽(x 43~)이 대기1단계 장소. 건물·기존 좌표는 그대로 |
| 후착대 도착 | 시나리오 `arrivals`의 시각에 차량이 지도 동쪽 밖에서 서쪽을 보고 들어와 차로(`staging.lanes`) 앞부터 선다. 자리가 없으면 진입로에서 기다린다. 차량이 서면 조가 내리고 출동대명·인원·위치를 무전 보고 (`resource_system.gd`) |
| 투입 | 대기 중인 출동대에 처음 명령하면 투입 무전이 먼저 나가고, 전달된 뒤 그 명령을 실행한다. 아직 도착하지 않은 출동대에 내린 명령은 받지 않는다 |
| 지원 요청 | O 창 또는 최초 상황보고 ⑧. 시나리오 `support`의 출동대가 정한 시간 뒤 도착. 대응 1단계로 올리면 아직 부르지 않은 출동대만 더 온다 |
| 통솔범위 | 직접 지휘 = 단위대 수 + 단위대에 속하지 않은 현장 출동대 수. 적정(5)을 넘으면 넘은 수 × 5초(추정)만큼 직접 지휘 출동대 명령이 늦게 실행된다 (`organization.gd`) |
| 단위대 | 방면(A~D면)·층·기능(배연·인명구조·급수). 출동대장 한 명을 단위지휘관으로 정한다. 단위대마다 작전망을 두고, 소속 출동대의 일반 보고·응답은 작전망으로 간다(대원 안전·구조대상자 보고는 지휘망). 전략 전파 응답은 단위지휘관이 한 번 |

검증은 `tests/test_organization.gd`.

## 현장 정보 요약 (M5c)

| 요소 | 내용 |
|---|---|
| 둘러보기 | 지휘관이 건물 면 바깥 10m 안에서 30° 이상 각도로 보면 그 면을 확인 (모서리에서는 두 면). 시나리오 `site.faces`의 면 정보가 열리고, 위험 요소면 상황보고 ④ 정답에 들어간다. [360° 둘러보기]는 건물 둘레 3칸 밖 모서리를 시계 방향으로 돈다 |
| 관계인 | `site.witnesses`. 3m 안에서 질문 (질문당 8초, 움직이면 끊김). 진술의 `reliable`은 화면에 나오지 않는다 (M6 디브리핑). `rooms`는 지도에 [제보: 구조대상자 가능], 믿을 만한 진술의 `hazard`는 확인한 위험 요소 |
| 물증 | 실내등(`site.lights`): 확인한 면의 창에 불빛. 현관 신발(`site.shoes`): 문이 열리고 지휘관·대원이 2m 안 |
| 보완 보고 | 선언 후 C → 구조대상자·위험 요소를 다시 송신, 그때 확인 가능한 사실과 비교해 기록 |
| 현장지휘소 | 30초 이상 머문 곳: 관찰(보이는 면 2개 좋음·1개 보통·0 나쁨), 안전(SOP 205-1.3: 발화층 높이 ½ 안 위험, 건물 높이 안 주의), 동선(차도·대기 장소 위 방해). 고정·이동 시간도 기록 |

수치는 `data/command/survey_params.json`. 검증은 `tests/test_site_survey.gd`.

## 평가·디브리핑 요약 (M6a)

| 요소 | 내용 |
|---|---|
| 활동 종료 | 선언 후 C → 활동 종료 선언, 또는 시나리오 `evaluation.time_limit_s`. 종료 후 시뮬레이션은 멈춘다 |
| 기록 | 사건 기록 + `SimRecorder`(1초마다 연소 칸 수·직접 지휘 수·내부 대원 수, 공기 경보 후 내부 체류 구간) |
| 규칙 | `data/sop/rules.json`. check 함수(`Evaluator._check_*`)가 0~1 점수와 설명. 해당 없으면 빼고 축 점수를 낸다. 시나리오 `evaluation.rules`가 고르고 `evaluation.params`로 기준값을 덮어쓴다 |
| 점수 | 축 가중치 대원 안전 25 · 인명구조 25 · 재산 15 · 화재 15 · 지휘 20 (결과 축 80). 등급 S 90 · A 80 · B 70 · C 60 |
| 등급 상한 | 규칙의 `cap`: 대원 행동 불능(108-1.2), 구조대상자 생존 구조 50% 미만(214-2.1) → 최고 C |
| 디브리핑 | ① 계획(학습 목표·최초 보고 ✓✗·전략·조직·지원) ② 실제(숨은 정보: 구조대상자 실제 위치, 진술 진위, 면 정보, 불난 구획 + 타임라인) ③ 왜(축별 규칙 점수·설명·조항 원문) ④ 다음에는(잘한 점 최소 1개, 고칠 점 최대 3개와 다음 행동) |
| 저장 | `user://reports/<시나리오>_<날짜시각>.json` |

검증은 `tests/test_evaluation.gd`.

## 시나리오·다시 하기 요약 (M6b)

| 요소 | 내용 |
|---|---|
| 시작 화면 | `scenes/main/menu.tscn`(scenario_menu.gd). `ScenarioLoader.list()`가 res://data/scenarios와 user://scenarios를 읽어 meta.order 순으로 보여 준다. 오류가 있으면 시작 불가 |
| 검증 | 필수 항목, 도면·편성 파일, 차종, 발화 지점(방 안), 문 좌표, 방 id, 면, 관계인 위치·질문, 대기 차로, 규칙 id, 제한 시간 |
| 시나리오별 장비 | `vehicles`: 차종 -> 제원 일부. 기본 제원을 덮어쓴다 (차종 단위: 같은 차종 후착대도 같이 바뀐다) |
| 변형 | `variation.random_seed`면 판마다 시드를 새로 뽑는다. `victims[].rooms` 후보 중 시드로 방을 고른다 |
| 다시 하기 | `SimWorld.issued`에 명령과 내린 틱을 남긴다. `Replay`가 같은 시나리오·시드로 새로 만들어 그 틱까지 명령을 다시 넣는다(결정론). 개발용 즉시 발화·정보 안개 끄기를 쓰면 불가. 화면에서는 프레임마다 120틱씩 진행하며 진행률 표시. 진입은 GameManager(씬을 다시 불러와도 남는 값) |
| 잔불정리 | 물로 끈 셀에 연료가 25% 이상 남으면 30% 확률로 불씨(3~8분 뒤 재발화). 열화상 조장이 방에 들어가면 발견, G로 45초 정리. 수치는 hazard_params.json (추정) |
| 정식 시나리오 | sop214_1(입문, 낮 거실), sop214_2(중급, 새벽 2층 침실, 딸 위치 변형), sop214_3(상급, 저녁 주방·LPG·소형 펌프차·늦은 후착) |

검증은 `tests/test_scenario_loader.gd`, `tests/test_replay.gd`, `tests/test_overhaul.gd`.

## 2025 SOP 정합화 요약 (M6.5)

| 요소 | 내용 |
|---|---|
| 근거 | 판정은 2025 재난현장표준작전절차(조항 번호는 교재와 같음), 원리는 소방전술. 규칙마다 `sop`·`text`(원문)와 `tactic`·`tactic_text`(원리 요약). 결과 파일에 `rules_version` 2 |
| 최초 상황보고 | 2025판 8개 항목. ⑨ 차량 진입·회차는 '참고'로 남기고 채점하지 않음 |
| 긴급탈출 (109) | 건물 안 대원이 쓰러지면 같은 조가 "긴급탈출" 3회 송신 (조 전원이면 지휘관이 무응답 긴급탈출 전파). 긴급탈출 상황 중에는 대원 안전·구조대상자 외 일반 보고를 멈추고 대기 중인 일반 보고도 비움. 쓰러진 대원이 건물 안에 없으면 해제 |
| 긴급탈출 지시·인원점검 | 지휘관 지시로 전원 탈출(문 밖 몇 칸까지), 진입 허가 취소. 인원점검(P)은 단위대는 단위지휘관이, 나머지는 출동대가 "인원 N명 이상 없음, 장비 이상 없음" 또는 건물 안·미확인 인원 보고 |
| RIT (SSG 9) | 조직 창에서 지정. 투입 전에는 밖에 머물고 이동 외 명령은 막힘. 긴급탈출 상황에서 명령하면 투입(진입 제한 해제), 추가 RIT 지정 안내 |
| 현장안전담당 (108-1.4) | 지정한 조는 밖에 머물며 진입 대원 공기 40% 미만을 경보 전에 무전으로 알림 |
| 진입 판단 (102-4.1) | 진입 명령 때 ② 화재 상층부 임무, ⑧ 특수현상 징후(최근 2분), ⑨ 위험 정보, ⑩ 구조대상자 내부 존재를 알리고 기록. ⑧ 중 진입 명령은 감점 |
| 종료 | 종료 창에 인원점검 상태·건물 안 인원, 재발화 감시 지정(관계자 당부·출동대 감시조) |
| 디브리핑 | ③에 주요 의사결정과 그때 알던 정보(111-2.2), 규칙마다 SOP 원문 + "왜?(소방전술)". 머리에 판정 근거와 '지도·개선 용도로만'(113-3.1.6) |

검증은 `tests/test_safety.gd`.

## 지휘 조작 개편·교육 모드 요약 (M7a)

| 요소 | 내용 |
|---|---|
| 명령칸 | `data/units/command_cards.json`. 첫 번째로 선택한 조의 출동대 종류에 맞춰 HUD 위 줄에 표시, 아래 줄은 세부 명령 |
| 고수준 명령 | `TacticalCommand`(기록·다시 하기 대상) → `TacticalSystem`. 진압: 구획 경로상의 닫힌 문을 차례로 개방 → 분무 방수 → 그 방 연소 셀이 없으면 중지. 수색: 문 개방 → 검색 → 찾은 구조대상자 이송. 외부 방수: 직사. 철수: 그 조만 |
| SOP 준수 | 백드래프트 징후가 있는 문은 열지 않고 보고(210-4.5). 진입 명령 없으면 입구 대기(102-5.2). 멈추면 `tactical_halt` 무전 보고 |
| 자동화 수준 | 입문: 잠긴 문까지 자동 파괴, 찾으면 자동 이송, 자동 방수 중지 / 중급: 잠기지 않은 문만, 찾으면 보고 후 대기 / 상급: 문 자동 개방 없음, 방수 중지도 직접. 시나리오 난이도가 기본, 시작 화면에서 바꿈. 다시 하기에도 같은 수준을 쓴다 |
| RECEO 상태판 | 무전 패널: 안전 / R 구조 / E 외부 / C 확산 / E 진압 / O 잔불. 확인한 정보 기준, 처리되지 않은 첫 줄을 '현재 우선'으로 |
| 교육 모드 | `HintUi` + `data/sop/hints.json` 13종. 트리거가 처음 성립하면 카드(SOP 조항·원리·권장 행동)를 띄우고 멈춤. 결과 파일에 mode·difficulty 기록 |

검증은 `tests/test_tactical.gd`, `tests/test_hints.gd`.

## 시나리오 편집기 요약 (M9d)

| 요소 | 내용 |
|---|---|
| 데이터 | `scripts/scenario/scenario_draft.gd` (`ScenarioDraft.from_base/open/add_ignition/add_victim/move_witness/remove_near/save`). 기본 제공 파일은 건드리지 않고 user://scenarios/custom_날짜.json으로 저장, `ScenarioLoader.validate` 결과를 돌려준다 |
| 화면 | `scripts/ui/editor_ui.gd` (`ScenarioEditorUi`, 안쪽 `MapPreview`). 시작 화면 '시나리오 편집기' 버튼 |

검증은 `tests/test_editor.gd`.

## 골목 안 주택 요약 (M9c)

| 요소 | 내용 |
|---|---|
| 지도 | `data/buildings/house_alley.json` (house_2f에서 생성: 골목 x33~38 차도, 담장 y22, 옆집 동쪽으로 5칸, 소화전 [56,26]) |
| 시나리오 | `sop214_4_alley.json` (meta.order 3.5 — 목록 정렬은 실수 비교), 배치 보기 3종(골목 안 차량은 heading [0,-1]) |
| 캠페인 | 4장에 추가 |

검증은 `tests/test_alley.gd`.

## 순환보수 요약 (M9b)

| 요소 | 내용 |
|---|---|
| 데이터 | 시나리오 `water {hydrants_out: [index], shuttle: {name, round_trip_s, fill_lpm}}` |
| 실행 | `scripts/simulation/suppression/shuttle_system.gd` (`ShuttleSystem.toggle/step`). `WaterSystem.hydrants_out` — 고장 소화전 점령 시 `hydrant_out` 무전. 다녀오는 동안 `Vehicle.away` |
| 조작 | 입력 `cmd_shuttle`(B): 선택한 물탱크차 순환보수 지정·해제. 장비 명령 `shuttle`(기록·다시 하기) |
| 평가 | fire.shuttle (35개). 소화전이 모두 고장이면 fire.water_supply는 급수 연결만 본다 |

검증은 `tests/test_shuttle.gd`.

## 일반 건축물화재 요약 (M9a)

| 요소 | 내용 |
|---|---|
| 건물 | `data/buildings/commercial_3f.json` (1층 식당·주방·편의점·창고, 2층 학원, 3층 사무실, 서쪽 계단실·비상구, 가운데 PS). 키 `shafts [{name, rect, levels}]`, `signs [{name, rect, level}]` |
| 자력 대피 | `scripts/simulation/evac_system.gd` (`EvacSystem`). 요구조자 `self_evac`, `alert_s`. 값 evac_alert_s·evac_clear_m·evac_hot_c·evac_speed_factor |
| 샤프트 | `scripts/simulation/hazards/shaft_system.gd` (`ShaftSystem`: hot·checked·ignited). 값 shaft_rise_s·shaft_spread_s |
| 간판 | `FallSystem._update_signs` (sign_due·sign_fallen). 값 sign_fall_s·sign_radius_m |
| 평가·힌트 | fire.shaft (34개), 힌트 shaft_heat·sign_warning·victim_trapped (22종) |
| 시나리오 | `sop212_1_commercial_kitchen.json` (order 6): 강사·학생1·2 자력 대피, 학생3·4 갇힘, 3층 야근자(모름), 주방 가스 밸브(C면), 배치 보기 3종 |

검증은 `tests/test_general.gd`.

## 아파트 상층 확대·추락·낙하물 요약 (M8b-2)

| 요소 | 내용 |
|---|---|
| 상층 연소 | `ExposureSystem._build_vertical_pairs` (Pair.vertical), `room_ratio`, `label()`. 알림·착화 무전은 방마다 한 번 |
| 추락·매트·낙하물 | `scripts/simulation/hazards/fall_system.gd` (`FallSystem`, 3층 이상 건물만). 요구조자 `jumper`(시나리오 window)·`fell`. 장비 명령 `air_mat`(구조대만), 구조대 명령칸 '공기안전매트', 선택 모드 AIR_MAT. 값은 hazard_params(jump_warn_fed·jump_fed·jump_delay_s·air_mat_*) |
| 화면 | 상황판·입체에 노란 공기안전매트, 빨간 원 낙하물 위험 |
| 평가·힌트 | rescue.air_mat, safety.debris (33개), 힌트 jump_risk·debris_zone (19종) |
| 시나리오 | `sop213_2_apartment_night.json` (order 5, 상급): 302호 화재 → 402호 창가 주민, 401호 할머니 |

검증은 `tests/test_falls.gd`.

## 아파트화재 요약 (M8b-1)

| 요소 | 내용 |
|---|---|
| 건물 | `data/buildings/apartment_5f.json` (생성기: 스크래치 gen_apartment.py와 같은 규칙 — 층당 2세대 + 계단실, 좌우 대칭). 키 `standpipe {fdc, outlets[[x,y,층]], outlet_hose_m}`, `fire_doors`, `vertical_exposure`(M8b-2) |
| 연결송수관 | `WaterSystem.fdc_vehicle`, `connect_fdc`(소화전 연결 거리의 1.5배 안), `lay_hose_outlet`(방수구 → 조, 30m, 물은 송수구 펌프차). `start_spray`는 목표가 2층 이상이고 송수구가 연결돼 있으면 방수구를 먼저 쓴다. `HoseLine.outlet` |
| 조작 | 펌프차 선택 → 송수구 우클릭 = `fdc`, 조 선택 → 방수구 우클릭 = `hose_outlet`. 입체·상황판에 주황 송수구·방수구 표시, 차량 줄에 "송수구 연결" |
| 방화문 | `DoorSystem`: 잠긴 방화문 파괴 시간 × fire_door_force_factor(2) |
| 시나리오 | `sop213_1_apartment_3f.json` (meta.order 4): 301호 현관 열림, 할머니 401호·학생 302호, 관계인(301호 주민·관리사무소), 배치 보기(공동현관 앞 / 건너편 차로 / 서쪽 끝) |

검증은 `tests/test_apartment.gd`.

## 선착 차량 배치 요약 (M8a)

| 요소 | 내용 |
|---|---|
| 데이터 | 시나리오 `approach {default, squad, options: [{id, name, text, score, feedback, vehicles: [{spawn, heading}]}]}` |
| 실행 | `scripts/command/placement.gd`. 지휘 명령 `placement`(value = 보기 index, 기록·다시 하기 대상). 도착 직후(5초 안) 한 번만. 모두 들어 올린 뒤 차례로 세우고, 한 대라도 도로 밖·겹침이면 모두 원래 자리 |
| 화면 | 출동 지령 창의 배치 보기와 설명. "현장 도착"(Enter) 때 명령이 나간다 |
| 평가 | fire.placement (SOP 200-3.1.1): 고른 보기의 score·feedback. 고르지 않으면 0.5 |

검증은 `tests/test_placement.gd`.

## 대원 개성·캠페인 요약 (M7c-3)

| 요소 | 내용 |
|---|---|
| 개성 | `data/units/traits.json` (air·speed·heat 배율). 편성 members[].traits → `Firefighter.traits/air_factor/trait_speed/heat_factor`. 공기 소모(crew_condition_system)·이동(firefighter.step)·열 스트레스에 반영. HUD 조 상태 "개성: 이름 개성" |
| 캠페인 | `data/campaign/campaign.json` (장: scenarios, min_grade), `scripts/scenario/campaign.gd` (`Campaign.progress`), 화면 `scripts/ui/campaign_ui.gd`. 시작 화면 '캠페인' 버튼 → 도전 가능한 시나리오를 누르면 목록에서 고른다 |

검증은 `tests/test_campaign.gd`.

## 내 기록·교관 설정 요약 (M7c-2)

| 요소 | 내용 |
|---|---|
| 내 기록 | `scripts/evaluation/play_history.gd` (`PlayHistory.entries/growth/aggregate/export_aggregate`), 화면 `scripts/ui/history_ui.gd`. 결과 파일(user://reports)을 읽는다. 결과 파일에 `saved_at`·`instructor_params` 추가 |
| 익명 집계 | 시나리오별 판 수·등급 분포·평균 점수·축 평균·자주 나온 고칠 점. 이름·날짜별 개인 기록 없음. user://export/aggregate_날짜.json·.csv |
| 교관 설정 | `scripts/scenario/instructor_settings.gd` (user://instructor.json), 화면 `scripts/ui/instructor_ui.gd`. weekly(이번 주 훈련), defaults(시작 화면 모드·자동화), params(hazard·ems·safety 표 덮어쓰기). `InstructorSettings.active`는 게임 화면(world)에서만 켜므로 자동 테스트는 늘 기본 수치 |
| 시작 화면 | 버튼 '내 기록'·'교관 설정', 이번 주 훈련 시나리오에 ★ 표시와 안내 문구 |

검증은 `tests/test_history.gd`.

## 튜토리얼 요약 (M7c-1)

| 요소 | 내용 |
|---|---|
| 시나리오 | `data/scenarios/tutorial_basics.json` (meta.order 0, 난이도 "튜토리얼"). `tutorial` 키가 단계 파일을 가리킨다. 검증기가 단계 파일을 확인 |
| 단계 | `data/tutorial/basics.json`. check: time / declared / selected / faces / rit / event / knockdown / ended. 교관이 문구·순서를 고칠 수 있다 |
| 화면 | `scripts/ui/tutorial_ui.gd` (HUD 자식, 오른쪽 위). 게임을 멈추지 않고, 시뮬레이션은 읽기만 한다. 튜토리얼에서는 멈추는 힌트 카드를 끈다 |

검증은 `tests/test_tutorial.gd`.

## 구급대·운전원 요약 (M7b-2)

| 요소 | 내용 |
|---|---|
| 구급 | `scripts/simulation/ems_system.gd`, 값 `data/units/ems_params.json`. 구조된 요구조자 → 환자 등록·중증도 분류 → 처치(구급대 조, 환자 옆) → 이송(들것으로 구급차까지, 출발하면 구급차 `away`·대원 `aboard`) → 병원 인계 → 복귀 |
| 명령 | 장비 명령 `ems_treat`·`ems_transport` (other = 요구조자 id). 구급대 명령칸: 처치(W)·이송(V). 구급대 선택 후 환자 우클릭도 같다 |
| 자동화 | 입문: 처치 후 자동 이송 / 중급·상급: "이송 지시 바람" 보고 후 대기 |
| 운전원 | 편성 파일 차량 `driver: {name, rank}` → `Vehicle.driver_label()`. HUD 차량 줄과 차량 기록에 표시 |
| 편성 | `dev_reinforcements.json`의 구급1·구급2. 시나리오 arrivals로 구급1이 4~6분 뒤 도착, 지원 요청에 구급2 |
| 평가·힌트 | rescue.ems_treat, rescue.ems_transport (29개), 힌트 patient_waiting (17종). RECEO R줄에 처치 대기 수 |

검증은 `tests/test_ems.gd`.

## 주택화재 완성도 요약 (M7b-1)

| 요소 | 내용 |
|---|---|
| 건물 묶음 | 건물 파일 `structures`: 화재 건물(첫 번째, 둘러보기 외곽 기준)과 `exposure: true` 인접 건물. `BuildingData.structure_at`·`is_exposure`, `FireSim.is_exposure_comp`. 인접 건물 구획의 플래시오버 온도는 따로 뽑아 기존 시드 결과가 바뀌지 않음 |
| 인접 건물 연소 | `scripts/simulation/hazards/exposure_system.gd`. 화재 건물 외부 개구부 ↔ 마주 보는 인접 창(8m 안) 짝. 원천 구획이 최성기·플래시오버이고 개구부가 열렸으면 q·분출 비율·바람/(4πd²) 복사열, 기준(5kW/㎡)을 넘는 만큼 누적 → 40% 가열 알림, 100% 창 파손·착화. 경계관창이면 식음 |
| 바람 | 시나리오 `wind: {from_deg, speed_mps}`. 풍하 방향일수록 1 + 0.15 × 풍속 × cos |
| 가스 | `gas_system.gd`, 시나리오 `site.gas {valve, stove, text}`. 장비 명령 `gas_off`(밸브 우클릭) — 10초 작업 |
| 붕괴 | `collapse_system.gd`. 건물 구조에 "벽돌"이 있으면 최성기 구획 진행 600초 → 60% 징후, 100% 붕괴 |
| 후착대 | `Squad.arrival` 선착/후착. 명령칸 `"후착 진압대"`: 포위 진압(W)·경계관창(V)·교차 탐색·철수(X) |
| 평가·힌트 | 규칙 property.exposure·property.gas·safety.collapse (27개), 힌트 exposure_heating·collapse_sign·gas_known (16종). 인접 건물 구획은 연소 확대(property.spread)·미검색 구획에서 뺀다 |

값은 모두 `data/fire/hazard_params.json`의 추정값. 검증은 `tests/test_exposure.gd`.

## 요구조자·구조·특수현상 요약 (M4b)

| 요소 | 내용 |
|---|---|
| 요구조자 | 시나리오 방의 인명검색 중점지역(침대 옆·창가·출입구·구석)에 시드로 배치. 호흡 높이(쓰러짐 0.3m·업힘 1.2m)의 연기(CO)·열 노출량(FED) 1이면 의식 잃음, 3이면 사망. 방에 플래시오버가 나면 사망 |
| 발견 | 대원 시야(창 밖 관찰 제외), 열화상카메라, 소리(의식 있을 때 3m, 벽 너머), 창가 목격 |
| 검색 | 방 둘레를 3칸 간격으로 돌고 가운데까지. 끝나면 검색 완료 표시 |
| 구조 | 2인 운반(속도 절반), 가장 가까운 열린 외부 문 밖으로 자동 이송. 수관 조는 불가. 쓰러진 대원도 같은 방식 |
| 특수현상 | 롤오버 징후(FO 100℃ 전), 플래시오버 순간 방 안 대원 행동 불능, 백드래프트(가스 12.5%↑·산소 15%↓·300℃↑ 방의 문 개방 시, 문 3m 안 대원 행동 불능, 문 앞 작업 시작 때 징후), 창 파괴(상부 배연)는 폭발 없음 |

수치는 `data/fire/hazard_params.json`. 검증은 `tests/test_rescue_hazards.gd` (약 6분 소요).

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
