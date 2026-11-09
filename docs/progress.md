# 진행 기록

프롬프트 하나가 끝날 때마다 Claude Code가 아래 형식으로 한 줄씩 추가합니다.

| 날짜 | 프롬프트 | 바뀐 주요 파일 | 남은 문제 |
| --- | --- | --- | --- |
| 2026-11-10 | P11-1 + P3-1[2] 화재 확산 | scripts/command/mission_end_checker.gd(새), scripts/ui/game_menu.gd(새), scripts/scenario/profile.gd(새), sim_world·phase_system·fuel_grid·compartment_model·fire_sim·fire_config, world·main·scenario_menu·debrief_ui·command_ui·hud·history_ui·editor_ui, evaluator·report_export·play_history·campaign, data(fire_params·phase_params·rules·hints·scenarios 19개), tests(test_mission_end·test_spread·ui_end_menu 새, 기존 4개 수정) | 메뉴 설정은 화면 설정만(P10-1·P14), 확산 수치 검수 필요 |
| 2026-11-10 | P2-2 층·세대별 구조 변형·집기 | scripts/simulation/grid/unit_assembly.gd(새), data/furnishings/apartment_a.json·data/unit_variants/apartment_a.json(새), 아파트 3동 units 블록, 아파트 시나리오 6개 units, sim_world·pathfinder·fuel_grid·rekindle·rescue·opening·tactical_system·interior_orders·mission_ui·floor_plan_view·world·sim_event_log·command_system, tests/test_unit_layout.gd | 벽 철거(구획 변경) 변형 없음, 실내등 단서는 기존 그대로, 15층 로드 0.58초 |
| 2026-11-10 | P14·P3-1·P6-1 | fuel_grid·perception·compartment_model·fire_sim·exposure·shaft·rekindle·water_system·monitor_system·rescue·vehicle·unit_system·evaluator·debrief_ui·command_ui·display_settings·display_ui·view_params, data(fire_params·hazard_params·materials·vehicles·firefighter·rules·commercial_3f·시나리오), tests(test_water_flow·test_fire_extras 새, test_suppression·test_evaluation 수정), docs/perf.md | 엘리베이터 피스톤·HVAC 보류, 확산·방수 수치 검수 필요 |
| 2026-11-10 | P9-1·P2-1 | sim_world(field_scale·dispatch)·card_system·world·hud·command_ui(출동 단계 시계)·city_mass_view(새)·iso_view·floor_stack·floor_layer·view_params, data(phase_params·view_params), tests(test_time_axis 새, test_cards·test_cutaway·ui_cutaway 수정) | 출동 준비판 상황실 요청·신고 기준 도착표·소방차 아이콘 이동은 남음 |
| 2026-11-10 | P4-3 대원 클릭 판정 | scripts/ui/selection_controller.gd, data/ui/view_params.json·view_params.gd, tests/ui_pick.gd(새) | 가려진 대원의 윤곽은 마우스를 올렸을 때만 보임(늘 보이게 할지는 P10-1에서) |
