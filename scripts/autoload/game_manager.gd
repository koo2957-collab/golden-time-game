extends Node
## 게임 전역 상태 관리.

enum GameState { BOOT, MENU, BRIEFING, MISSION, DEBRIEF }

var state: GameState = GameState.BOOT


func change_state(new_state: GameState) -> void:
	state = new_state
