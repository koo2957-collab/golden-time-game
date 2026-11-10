# 질문 카드 초안 검수표 (P13)

2026-11-11. 원문: 2025 재난현장표준작전절차 SOP 201·204·205·206·208·209. 초안 파일: data/cards/draft_sop201_209.json (게임은 아직 읽지 않음).

**검수 방법:** 마지막 칸에 ○(그대로)·△(고쳐서)·×(빼기)를 적어 주시면, ○·△ 카드만 data/cards/cards.json으로 옮기고 필요한 사건·행동을 만듭니다.

규칙(P13): 조항 하나에 카드 하나('상황 → 행동' 조항만), 선택지 최선 1·허용 0~1·오답 1~2·치명 0~1, 무전 말투 2문장 이내, 해설은 원문 근거 2문장 이내.

| 카드 | 질문 | 최선 | 선택지 등급 | SOP | 뜨는 때(트리거) | 검수 |
| --- | --- | --- | --- | --- | --- | --- |
| D201-REST-01 | 팀장님, 2조 공기 교체하고 나왔습니다. 바로 다시 들어갈까요? | 휴식처에서 쉬게 하고 건강 상태를 확인한 뒤 진입을 정한다 | 최선 · 허용 · 오답 | SOP 201-3.5 | NEW:crew_air_swapped | |
| D201-DOOR-01 | 팀장님, 현관 출입문 앞에 짐과 남은 장비가 쌓였습니다. 어떻게 할까요? | 바로 치우게 한다 — 출입문 주위에 장애물을 두지 않는다 | 최선 · 오답 | SOP 201-3.3 | NEW:doorway_blocked | |
| D201-OFFICER-01 | 팀장님, 진입이 시작됐는데 현장안전담당이 없습니다. 지정할까요? | 남는 대원 한 명을 현장안전담당으로 지정·배치한다 | 최선 · 허용 · 오답 | SOP 201-3.8 | NEW:entry_without_officer | |
| D204-LOST-01 | 팀장님, {crew}입니다. 연기 때문에 방향을 잃었습니다. 손에 호스가 잡힙니다. | 호스 커플링 수나사 쪽으로 호스를 따라 나와라 | 최선 · 허용 · 오답 · 치명 | SOP 204-2.1, SOP 204-2.2, SOP 204-4.5 | crew_disoriented | |
| D204-SIGNAL-01 | 팀장님, {crew}입니다. 출구가 무너져 갇혔습니다. 무전이 잘 안 됩니다. | 개인 안전경보장치를 켜고 벽을 규칙적으로 두드리며 호흡을 조절하라 | 최선 · 허용 · 오답 | SOP 204-3.1, SOP 204-3.2, SOP 204-3.3, SOP 204-4.3 | NEW:crew_trapped | |
| D204-FOCUS-01 | 팀장님, {crew} 고립입니다. 지금 요구조자 구조 중인 조도 있습니다. 어떻게 할까요? | 구조 중인 조는 그대로 두고, 나머지 소방력을 고립 대원 구출에 집중한다 | 최선 · 오답 · 허용 | SOP 204-4.1, SOP 109-1.1 | mayday | |
| D205-GLASS-01 | 팀장님, 3층 창에 깨진 유리가 걸려 있습니다. 털어낼까요? 아래로 대원이 지나다닙니다. | 아래에 대원이 없는지 확인하고 경계하며 '낙하물' 통보 후 털어낸다 | 최선 · 허용 · 오답 | SOP 205-1.2 | NEW:glass_hanging | |
| D205-CRACK-01 | 팀장님, 균열음이 들리고 건물이 흔들립니다. 콘크리트가 떨어지기 시작했습니다. | 건물 안 대원 즉시 철수, 붕괴 우려 높이의 1.5배 밖으로 물린다 | 최선 · 허용 · 오답 | SOP 205-2.2, SOP 205-3.5 | collapse_sign | |
| D205-WATER-01 | 팀장님, 방수포로 40분째 계속 쏘고 있습니다. 바닥에 물이 고입니다. | 방수량을 줄이고 배수 방안을 마련하며 붕괴 징후를 감시한다 | 최선 · 허용 · 오답 | SOP 205-3.1, SOP 205-3.4 | NEW:long_heavy_flow | |
| D206-SMOKE-01 | 팀장님, 연기가 짙어 화점이 안 보입니다. 어디부터 쏠까요? | 천장 → 벽면 → 수용물 → 바닥 순으로 주수한다 | 최선 · 허용 · 오답 | SOP 206-2.2 | NEW:nozzle_no_view | |
| D206-SIDE-01 | 팀장님, 반대편 발코니 쪽이 가까운데 거기서 안쪽으로 쏠까요? | 아직 안 탄 쪽(현관·복도)에서 타는 쪽으로 쏜다 | 최선 · 오답 | SOP 206-2.3 | NEW:attack_from_burnt_side | |
| D206-CROSS-01 | 팀장님, 맞은편 창으로 다른 조가 들어가 있습니다. 이쪽 문에서 방수할까요? | 맞은편 조와 교신해 위치를 확인한 뒤 방수한다 | 최선 · 허용 · 치명 | SOP 206-2.6, SOP 207-1.1 | NEW:crew_opposite_opening | |
| D206-ELEC-01 | 팀장님, 분전반 쪽에 불이 붙었습니다. 전원 차단이 아직 확인되지 않았습니다. | 관계인·한전에 전원 차단을 요청하고 확인될 때까지 주수하지 않는다 | 최선 · 허용 · 치명 | SOP 206-2.7 | NEW:electric_fire | |
| D206-PUMP-01 | 팀장님, 운전원입니다. 수관 연장 끝났습니다. 관창수 신호 없이 송수할까요? | 관창수·지휘관의 방수 신호(무전)를 받고 단계적으로 압력을 올린다 | 최선 · 오답 | SOP 206-1.2, SOP 206-1.3 | NEW:hose_ready_no_signal | |
| D208-RECEO-01 | 팀장님, 지금 수관 한 라인만 깔 수 있습니다. 어디부터 할까요? | 요구조자가 있는 쪽 — 구조 엄호와 대피로 확보(생명보호) | 최선 · 허용 · 오답 | SOP 208-1.1 | NEW:first_line | |
| D208-SLACK-01 | 팀장님, 호스가 팽팽해서 더 못 들어갑니다. | 차량·방수 위치·모퉁이에 여유 호스를 두고 다시 연장한다 | 최선 · 허용 · 오답 | SOP 208-1.3 | hose_limit | |
| D208-ROPE-01 | 팀장님, 계단에 짐이 쌓여 4층까지 호스를 끌고 갈 수 없습니다. | 창 개구부에서 로프를 내려 말뚝매기·옭매듭으로 묶어 끌어올린다 | 최선 · 허용 · 오답 | SOP 208-1.4, SOP 235 | NEW:stair_hose_blocked | |
| D209-SETUP-01 | 팀장님, 굴절차입니다. 지정하신 자리 위로 전선이 지나고 바닥이 기울었습니다. | 가공전선·간판·지반 경사·굴신 반경을 확인해 다른 자리에 전개한다 | 최선 · 허용 · 치명 | SOP 209-1.1, SOP 207-1.4 | NEW:aerial_setup | |
| D209-BASKET-01 | 팀장님, 바스켓에 요구조자 두 명과 대원이 탔습니다. 바로 내릴까요? | 적재 정량을 지키고 안전벨트·안전로프를 연결한 뒤 천천히 내린다 | 최선 · 허용 · 오답 | SOP 209-2.1, SOP 209-2.2, SOP 209-1.4 | NEW:basket_loading | |

## 카드로 만들지 않은 조항

- 201-1·2(출동지령·출동 단계 차량 안전), 201-4(복귀): 지휘 판단이 아닌 개인 절차라 카드 대신 출동 연출·체크리스트로.
- 201-3.6(안전 확보 전 진입 보류): 이미 진입 허가 카드(ENTRY-01)로 있음.
- 204-1(고립 시 확인사항): 고립 대원 스스로의 확인 — D204-LOST-01·D204-SIGNAL-01 선택지에 녹임.
- 205-1.3(외부 위험반경 발화층 1/2): 이미 DEBRIS-01·안전구역 안내선으로 있음.
- 206-2.1(주수 요령 숙지), 206-3.1~3.3(방수 자세), 207-2(사다리 설치): 개인 기술이라 자동 행동(7-4)으로.
- 207-1.1(진입대원 있을 때 방수포): 이미 MONITOR-CREW-01.
- 209-1.3·2.3(붐 진동·통신 유지): 운전원 자동 행동.

## 새로 만들어야 하는 것 (검수 뒤)

- 새 사건(트리거): aerial_setup, attack_from_burnt_side, basket_loading, crew_air_swapped, crew_opposite_opening, crew_trapped, doorway_blocked, electric_fire, entry_without_officer, first_line, glass_hanging, hose_ready_no_signal, long_heavy_flow, nozzle_no_view, stair_hose_blocked
- 새 행동(effect): add_section, add_slack, aerial_deploy_now, aerial_relocate, all_to_mayday, assign_officer, attack_reverse, basket_fast, basket_safe, basket_split, charge_now, clear_doorway, escape_by_hose, extinguisher, glass_now, hoist_hose, pass_and_tap, power_off, reduce_flow, remove_mask, rest_then_check, signal_window
- 이미 있는 사건으로 바로 쓸 수 있는 카드: D204-LOST-01(crew_disoriented), D204-FOCUS-01(mayday), D205-CRACK-01(collapse_sign), D208-SLACK-01(hose_limit) — 같은 사건에 기존 카드가 있으면 둘 중 하나를 고르거나 변형(variants)으로 합친다.
