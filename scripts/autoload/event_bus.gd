extends Node
## 전역 시그널 허브.
## 시스템 간 직접 참조 대신 이 노드의 시그널을 통해 통신한다.
## (예: 시뮬레이션 → 평가, 지휘 계층 → UI)

## 선택된 조 목록이 바뀌었을 때 (조 id 배열)
signal selection_changed(crew_ids: Array[int])
## 선택된 차량 목록이 바뀌었을 때 (차량 id 배열)
signal vehicle_selection_changed(vehicle_ids: Array[int])
## 화면에 보이는 층이 바뀌었을 때
signal view_floor_changed(level: int)
## 대상 지정 명령(수관 연장·방수 등)이 시작·종료되었을 때. 끝나면 빈 문자열.
signal command_mode_changed(hint: String)
## 현장지휘관 선택이 바뀌었을 때
signal commander_selection_changed(selected: bool)
